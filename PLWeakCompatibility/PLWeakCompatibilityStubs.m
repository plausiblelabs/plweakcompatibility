//
//  PLWeakCompatibilityStubs.m
//  PLWeakCompatibility
//
//  Created by Michael Ash on 3/28/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "PLWeakCompatibilityStubs.h"

#import <dlfcn.h>
#import <pthread.h>

// We need our own prototypes for some functions to avoid conflicts, so disable the ones from the header
#define object_getClass object_getClass_disabled_for_ARC_PLWeakCompatibilityStubs
#define objc_loadWeak objc_loadWeak_disabled_for_ARC_PLWeakCompatibilityStubs
#define objc_storeWeak objc_storeWeak_disabled_for_ARC_PLWeakCompatibilityStubs
#import <objc/runtime.h>
#undef object_getClass
#undef objc_loadWeak
#undef objc_storeWeak

// MAZeroingWeakRef Support
static Class MAZWR = Nil;
static bool mazwrEnabled = true;
static inline bool has_mazwr () {
    if (!mazwrEnabled)
        return false;

    static dispatch_once_t lookup_once = 0;
    dispatch_once(&lookup_once, ^{
        MAZWR = NSClassFromString(@"MAZeroingWeakRef");
    });

    if (MAZWR != nil)
        return true;
    return false;
}

// Minimal MAZWR API that we rely on
@interface MAZeroingWeakRef : NSObject
+ (id) initWithTarget: (PLObjectPtr) target;
- (PLObjectPtr) target;
@end

void PLWeakCompatibilitySetMAZWREnabled(BOOL enabled) {
    mazwrEnabled = enabled;
}

BOOL PLWeakCompatibilityHasMAZWR(void) {
    return has_mazwr();
}

// Runtime (or ARC compatibility) prototypes we use here.
PLObjectPtr objc_release(PLObjectPtr obj);
PLObjectPtr objc_autorelease(PLObjectPtr obj);
PLObjectPtr objc_retain(PLObjectPtr obj);
Class object_getClass(PLObjectPtr obj);

// Primitive functions used to implement all weak stubs
static PLObjectPtr PLLoadWeakRetained(PLObjectPtr *location);
static void PLRegisterWeak(PLObjectPtr *location, PLObjectPtr obj);
static void PLUnregisterWeak(PLObjectPtr *location, PLObjectPtr obj);

// Convenience for falling through to the system implementation.
static BOOL fallthroughEnabled = YES;

#define NEXT(name, ...) do { \
        static dispatch_once_t fptrOnce; \
        static __typeof__(&name) fptr; \
        dispatch_once(&fptrOnce, ^{ fptr = dlsym(RTLD_NEXT, #name); });\
        if (fallthroughEnabled && fptr != NULL) \
            return fptr(__VA_ARGS__); \
    } while(0)

void PLWeakCompatibilitySetFallthroughEnabled(BOOL enabled) {
    fallthroughEnabled = enabled;
}

////////////////////
#pragma mark Stubs
////////////////////

PLObjectPtr objc_loadWeakRetained(PLObjectPtr *location) {
    NEXT(objc_loadWeakRetained, location);

    return PLLoadWeakRetained(location);
}

PLObjectPtr objc_initWeak(PLObjectPtr *addr, PLObjectPtr val) {
    NEXT(objc_initWeak, addr, val);
    *addr = NULL;
    return objc_storeWeak(addr, val);
}

void objc_destroyWeak(PLObjectPtr *addr) {
    NEXT(objc_destroyWeak, addr);
    objc_storeWeak(addr, NULL);
}

void objc_copyWeak(PLObjectPtr *to, PLObjectPtr *from) {
    NEXT(objc_copyWeak, to, from);
    objc_initWeak(to, objc_loadWeak(from));
}

void objc_moveWeak(PLObjectPtr *to, PLObjectPtr *from) {
    NEXT(objc_moveWeak, to, from);
    objc_copyWeak(to, from);
    objc_destroyWeak(from);
}

PLObjectPtr objc_loadWeak(PLObjectPtr *location) {
    NEXT(objc_loadWeak, location);
    return objc_autorelease(objc_loadWeakRetained(location));
}

PLObjectPtr objc_storeWeak(PLObjectPtr *location, PLObjectPtr obj) {
    NEXT(objc_storeWeak, location, obj);

    PLUnregisterWeak(location, obj);

    *location = obj;

    if (obj != nil)
        PLRegisterWeak(location, obj);

    return obj;
}


////////////////////
#pragma mark Internal Globals and Prototypes
////////////////////

// This mutex protects all shared state
static pthread_mutex_t gWeakMutex;

// A map from objects to CFMutableSets containing weak addresses
static CFMutableDictionaryRef gObjectToAddressesMap;

// A list of all classes that have been swizzled
static CFMutableSetRef gSwizzledClasses;

// Ensure everything is properly initialized
static void WeakInit(void);

// Make sure the object's class is properly swizzled to clear weak refs on deallocation
static void EnsureDeallocationTrigger(PLObjectPtr obj);

// Selectors, for convenience and to work around ARC paranoia re: @selector(release) etc.
static SEL releaseSEL;
static SEL releaseSELSwizzled;
static SEL deallocSEL;
static SEL deallocSELSwizzled;

// Tables tracking the last class a swizzled method was sent to on an object
static CFMutableDictionaryRef gLastReleaseClassTable;
static CFMutableDictionaryRef gLastDeallocClassTable;


////////////////////
#pragma mark Primitive Functions
////////////////////

/**
 * Load a weak reference.
 *
 * @param location a pointer to the weak reference to load
 * @return the object stored at the weak reference, retained, or nil if none
 */
static PLObjectPtr PLLoadWeakRetained(PLObjectPtr *location) {
    /* Hand off to MAZWR */
    if (has_mazwr()) {
        MAZeroingWeakRef *mazrw = (__bridge MAZeroingWeakRef *) *location;
        return objc_retain([mazrw target]);
    }

    WeakInit();

    // Fetch the object with the global mutex held. Since weakly referenced objects
    // hold the mutex while releasing and deallocating, this guarantees we either
    // get a reference to a live object, or nil.
    PLObjectPtr obj;
    pthread_mutex_lock(&gWeakMutex); {
        obj = *location;
        objc_retain(obj);
    }
    pthread_mutex_unlock(&gWeakMutex);

    return obj;
}

/**
 * Register an object in a new weak reference.
 *
 * @param location a pointer to the weak reference where obj is being stored
 * @param the object being weakly referenced at this location
 */
static void PLRegisterWeak(PLObjectPtr *location, PLObjectPtr obj) {
    /* Hand off to MAZWR */
    if (has_mazwr()) {        
        MAZeroingWeakRef *ref = [[MAZWR alloc] initWithTarget: obj];
        *location = (__bridge_retained PLObjectPtr) ref;
        return;
    }

    WeakInit();

    // Add the location to the list of weak references pointing to the object.
    pthread_mutex_lock(&gWeakMutex); {
        CFMutableSetRef addresses = (CFMutableSetRef)CFDictionaryGetValue(gObjectToAddressesMap, obj);

        // If this is the first weak reference to this object, addresses won't exist yet, so create it.
        if (addresses == NULL) {
            addresses = CFSetCreateMutable(NULL, 0, NULL);
            CFDictionarySetValue(gObjectToAddressesMap, obj, addresses);
            CFRelease(addresses);
        }

        CFSetAddValue(addresses, location);

        // Make sure the appropriate swizzling has been done to obj's class.
        EnsureDeallocationTrigger(obj);
    } pthread_mutex_unlock(&gWeakMutex);
}

/**
 * Unregister an object from the given weak reference.
 *
 * @param location a pointer to the weak reference to unregister
 * @param obj the object to unregister
 */
static void PLUnregisterWeak(PLObjectPtr *location, PLObjectPtr obj) {
    /* Hand off to MAZWR */
    if (has_mazwr()) {
        if (*location != nil)
            objc_release(*location);
        return;
    }

    WeakInit();

    pthread_mutex_lock(&gWeakMutex); {
        // Remove the location from the set of weakly referenced addresses.
        CFMutableSetRef addresses = (CFMutableSetRef)CFDictionaryGetValue(gObjectToAddressesMap, *location);
        if (addresses != NULL)
            CFSetRemoveValue(addresses, location);
    } pthread_mutex_unlock(&gWeakMutex);
}


////////////////////
#pragma mark Internal Functions
////////////////////

/**
 * Initialize all weak reference global variables.
 */
static void WeakInit(void) {
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        pthread_mutexattr_t attr;
        pthread_mutexattr_init(&attr);
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);

        pthread_mutex_init(&gWeakMutex, &attr);

        pthread_mutexattr_destroy(&attr);

        gObjectToAddressesMap = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);

        gSwizzledClasses = CFSetCreateMutable(NULL, 0, NULL);

        releaseSEL = sel_getUid("release");
        releaseSELSwizzled = sel_getUid("release_PLWeakCompatibility_swizzled");
        deallocSEL = sel_getUid("dealloc");
        deallocSELSwizzled = sel_getUid("dealloc_PLWeakCompatibility_swizzled");
        
        gLastReleaseClassTable = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
        gLastDeallocClassTable = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    });
}

/**
 * Search for the top implementation of a given method. Starting at a given class,
 * it searches the class hierarchy upwards until it finds a class with a different
 * implementation for the given selector. It then returns the topmost class to have
 * the same implementation as the class that was passed in. This is used to emulate
 * a "super" call to a swizzled method by seeing which class the swizzled implementation
 * belongs to, and targeting the next class above it for the next call.
 *
 * @param start the class to start examining
 * @param sel the selector of the method to search for
 */
static Class TopClassImplementingMethod(Class start, SEL sel) {
    IMP imp = class_getMethodImplementation(start, sel);

    Class previous = start;
    Class cursor = class_getSuperclass(previous);
    while (cursor != Nil) {
        if (imp != class_getMethodImplementation(cursor, sel))
            break;
        previous = cursor;
        cursor = class_getSuperclass(cursor);
    }

    return previous;
}

/**
 * A swizzled release implementation which calls through to the real implementation with the
 * global weak mutex held, to eliminate race conditions between an object being destroyed and
 * a weak reference to that object being fetched.
 */
static void SwizzledReleaseIMP(PLObjectPtr self, SEL _cmd) {
    pthread_mutex_lock(&gWeakMutex); {
        // Figure out which class release was last sent to, in the event of recursive releases.
        // If lastSent is Nil, then this is the first release call on the stack for this object
        // and the call should start at the bottom. Otherwise, we want the next class above the
        // last one that was used.
        Class lastSent = (__bridge Class)CFDictionaryGetValue(gLastReleaseClassTable, self);
        Class targetClass = lastSent == Nil ? object_getClass(self) : class_getSuperclass(lastSent);
        targetClass = TopClassImplementingMethod(targetClass, releaseSELSwizzled);
        CFDictionarySetValue(gLastReleaseClassTable, self, (__bridge void *)targetClass);

        // Call through to the original implementation on the target class.
        void (*origIMP)(PLObjectPtr, SEL) = (__typeof__(origIMP))class_getMethodImplementation(targetClass, releaseSELSwizzled);
        origIMP(self, _cmd);

        // Reset the association to leave it clean for the next call to release.
        CFDictionaryRemoveValue(gLastReleaseClassTable, self);
    } pthread_mutex_unlock(&gWeakMutex);
}

/**
 * A helper function used when enumerating the CFSet of weak reference addresses. It clears out
 * the given address.
 */
static void ClearAddress(const void *value, void *context) {
    void **address = (void **)value;
    *address = NULL;
}

/**
 * A swizzled dealloc implementation which clears all weak references to the object before beginning destruction.
 */
static void SwizzledDeallocIMP(PLObjectPtr self, SEL _cmd) {
    pthread_mutex_lock(&gWeakMutex); {
        // Clear all weak references and delete the addresses set.
        CFSetRef addresses = CFDictionaryGetValue(gObjectToAddressesMap, self);
        if (addresses != NULL)
            CFSetApplyFunction(addresses, ClearAddress, NULL);
        CFDictionaryRemoveValue(gObjectToAddressesMap, self);

        // We follow the same procedure as in SwizzledReleaseIMP to properly handle recursion.
        Class lastSent = (__bridge Class)CFDictionaryGetValue(gLastDeallocClassTable, self);
        Class targetClass = lastSent == Nil ? object_getClass(self) : class_getSuperclass(lastSent);
        targetClass = TopClassImplementingMethod(targetClass, deallocSELSwizzled);
        CFDictionarySetValue(gLastDeallocClassTable, self, (__bridge void *)targetClass);
        
        // Call through to the original implementation.
        void (*origIMP)(PLObjectPtr, SEL) = (__typeof__(origIMP))class_getMethodImplementation(targetClass, deallocSELSwizzled);
        origIMP(self, _cmd);
        
        // Remove the class from the last sent table to leave it clean for the next object to occupy this space
        CFDictionaryRemoveValue(gLastDeallocClassTable, self);
    } pthread_mutex_unlock(&gWeakMutex);
}

/**
 * Swizzle out a method on a given class.
 *
 * @param c the class to manipulate
 * @param orig the original selector of the method
 * @param new the swizzled selector of the method; the original implementation will be found here afterwards
 * @param newIMP the new method implementation to install under "orig"
 */
static void Swizzle(Class c, SEL orig, SEL new, IMP newIMP) {
    Method m = class_getInstanceMethod(c, orig);
    IMP origIMP = method_getImplementation(m);
    class_addMethod(c, new, origIMP, method_getTypeEncoding(m));
    class_replaceMethod(c, orig, newIMP, method_getTypeEncoding(m));
}

/**
 * Ensure that the appropriate swizzling has been done to the given object's class.
 *
 * @param obj the object to check
 */
static void EnsureDeallocationTrigger(PLObjectPtr obj) {
    Class c = object_getClass(obj);
    if (CFSetContainsValue(gSwizzledClasses, (__bridge const void *)c))
        return;

    Swizzle(c, releaseSEL, releaseSELSwizzled, (IMP)SwizzledReleaseIMP);
    Swizzle(c, deallocSEL, deallocSELSwizzled, (IMP)SwizzledDeallocIMP);

    CFSetAddValue(gSwizzledClasses, (__bridge const void *)c);
}
