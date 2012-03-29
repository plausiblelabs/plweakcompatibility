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

// We need our own prototypes for some functions to avoid conflicts, so disable the one from the header
#define object_getClass object_getClass_disabled_for_ARC_PLWeakCompatibilityStubs
#define objc_loadWeak objc_loadWeak_disabled_for_ARC_PLWeakCompatibilityStubs
#define objc_storeWeak objc_storeWeak_disabled_for_ARC_PLWeakCompatibilityStubs
#import <objc/runtime.h>
#undef object_getClass
#undef objc_loadWeak
#undef objc_storeWeak

// MAZeroingWeakRef Support
static Class MAZWR = Nil;
static bool mazwrEnabled = false;
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


// Runtime (or ARC compatibility) prototypes we use here.
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

    if (has_mazwr()) {
        MAZeroingWeakRef *mazrw = (__bridge MAZeroingWeakRef *) *location;
        return objc_retain([mazrw target]);
    }

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

    if (has_mazwr()) {
        if (*location != nil)
            objc_autorelease(*location);

        if (obj != nil) {
            MAZeroingWeakRef *ref = [[MAZWR alloc] initWithTarget: obj];
            *location = (__bridge_retained PLObjectPtr) ref;
        } else {
            *location = nil;
        }

        return obj;
    }

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


////////////////////
#pragma mark Primitive Functions
////////////////////

static PLObjectPtr PLLoadWeakRetained(PLObjectPtr *location) {
    WeakInit();

    PLObjectPtr obj;
    pthread_mutex_lock(&gWeakMutex); {
        obj = *location;
        objc_retain(obj);
    }
    pthread_mutex_unlock(&gWeakMutex);

    return obj;
}

static void PLRegisterWeak(PLObjectPtr *location, PLObjectPtr obj) {
    WeakInit();

    pthread_mutex_lock(&gWeakMutex); {
        CFMutableSetRef addresses = (CFMutableSetRef)CFDictionaryGetValue(gObjectToAddressesMap, obj);
        if (addresses == NULL) {
            addresses = CFSetCreateMutable(NULL, 0, NULL);
            CFDictionarySetValue(gObjectToAddressesMap, obj, addresses);
            CFRelease(addresses);
        }

        CFSetAddValue(addresses, location);

        EnsureDeallocationTrigger(obj);
    } pthread_mutex_unlock(&gWeakMutex);
}

static void PLUnregisterWeak(PLObjectPtr *location, PLObjectPtr obj) {
    WeakInit();

    pthread_mutex_lock(&gWeakMutex); {
        CFMutableSetRef addresses = (CFMutableSetRef)CFDictionaryGetValue(gObjectToAddressesMap, *location);
        if (addresses != NULL)
            CFSetRemoveValue(addresses, location);
    } pthread_mutex_unlock(&gWeakMutex);
}


////////////////////
#pragma mark Internal Functions
////////////////////

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
    });
}

static void SwizzledReleaseIMP(PLObjectPtr self, SEL _cmd) {
    pthread_mutex_lock(&gWeakMutex); {
        Class targetClass = object_getClass(self);
        void (*origIMP)(PLObjectPtr, SEL) = (__typeof__(origIMP))class_getMethodImplementation(targetClass, releaseSELSwizzled);
        origIMP(self, _cmd);
    } pthread_mutex_unlock(&gWeakMutex);
}

static void ClearAddress(const void *value, void *context) {
    void **address = (void **)value;
    *address = NULL;
}

static void SwizzledDeallocIMP(PLObjectPtr self, SEL _cmd) {
    pthread_mutex_lock(&gWeakMutex); {
        CFSetRef addresses = CFDictionaryGetValue(gObjectToAddressesMap, self);
        if (addresses != NULL)
            CFSetApplyFunction(addresses, ClearAddress, NULL);
        CFDictionaryRemoveValue(gObjectToAddressesMap, self);

        Class targetClass = object_getClass(self);
        void (*origIMP)(PLObjectPtr, SEL) = (__typeof__(origIMP))class_getMethodImplementation(targetClass, deallocSELSwizzled);
        origIMP(self, _cmd);
    } pthread_mutex_unlock(&gWeakMutex);
}

static void Swizzle(Class c, SEL orig, SEL new, IMP newIMP) {
    Method m = class_getInstanceMethod(c, orig);
    IMP origIMP = method_getImplementation(m);
    class_addMethod(c, new, origIMP, method_getTypeEncoding(m));
    method_setImplementation(m, newIMP);
}

static void EnsureDeallocationTrigger(PLObjectPtr obj) {
    Class c = object_getClass(obj);
    if (CFSetContainsValue(gSwizzledClasses, (__bridge const void *)c))
        return;

    Swizzle(c, releaseSEL, releaseSELSwizzled, (IMP)SwizzledReleaseIMP);
    Swizzle(c, deallocSEL, deallocSELSwizzled, (IMP)SwizzledDeallocIMP);

    CFSetAddValue(gSwizzledClasses, (__bridge const void *)c);
}
