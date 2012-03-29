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
#define ALLOW_FALLTHROUGH 1

#if ALLOW_FALLTHROUGH
    #define NEXT(name, ...) do { \
            __typeof__(&name) fptr = dlsym(RTLD_NEXT, #name); \
            if (fptr != NULL) \
                return fptr(__VA_ARGS__); \
        } while(0)
#else
    #define NEXT(name, ...) (void)0
#endif

id objc_loadWeakRetained(id *location) {
    NEXT(objc_loadWeakRetained, location);
    
    // TODO: this is a primitive method
    return NULL;
}

id objc_initWeak(id *addr, id val) {
    NEXT(objc_initWeak, addr, val);
    *addr = NULL;
    return objc_storeWeak(addr, val);
}

void objc_destroyWeak(id *addr) {
    NEXT(objc_destroyWeak, addr);
    objc_storeWeak(addr, NULL);
}

void objc_copyWeak(id *to, id *from) {
    NEXT(objc_copyWeak, to, from);
    objc_initWeak(to, objc_loadWeak(from));
}

void objc_moveWeak(id *to, id *from) {
    NEXT(objc_moveWeak, to, from);
    objc_copyWeak(to, from);
    objc_destroyWeak(from);
}

id objc_loadWeak(id *location) {
    NEXT(objc_loadWeak, location);
    return objc_autorelease(objc_loadWeakRetained(location));
}

id objc_storeWeak(id *location, id obj) {
    NEXT(objc_storeWeak, location, obj);
    
    // TODO: this is a primitive method
    return NULL;
}
