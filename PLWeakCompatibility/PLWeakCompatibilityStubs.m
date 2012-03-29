//
//  PLWeakCompatibilityStubs.m
//  PLWeakCompatibility
//
//  Created by Michael Ash on 3/28/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "PLWeakCompatibilityStubs.h"

#import <dlfcn.h>


// Runtime (or ARC compatibility) prototypes we use here.
id objc_autorelease(id obj);

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

__unsafe_unretained id objc_loadWeakRetained(__unsafe_unretained id *location) {
    NEXT(objc_loadWeakRetained, location);
    
    // TODO: this is a primitive method
    return NULL;
}

__unsafe_unretained id objc_initWeak(__unsafe_unretained id *addr, __unsafe_unretained id val) {
    NEXT(objc_initWeak, addr, val);
    *addr = NULL;
    return objc_storeWeak(addr, val);
}

void objc_destroyWeak(__unsafe_unretained id *addr) {
    NEXT(objc_destroyWeak, addr);
    objc_storeWeak(addr, NULL);
}

void objc_copyWeak(__unsafe_unretained id *to, __unsafe_unretained id *from) {
    NEXT(objc_copyWeak, to, from);
    objc_initWeak(to, objc_loadWeak(from));
}

void objc_moveWeak(__unsafe_unretained id *to, __unsafe_unretained id *from) {
    NEXT(objc_moveWeak, to, from);
    objc_copyWeak(to, from);
    objc_destroyWeak(from);
}

__unsafe_unretained id objc_loadWeak(__unsafe_unretained id *location) {
    NEXT(objc_loadWeak, location);
    return objc_autorelease(objc_loadWeakRetained(location));
}

__unsafe_unretained id objc_storeWeak(__unsafe_unretained id *location, __unsafe_unretained id obj) {
    NEXT(objc_storeWeak, location, obj);
    
    // TODO: this is a primitive method
    return NULL;
}
