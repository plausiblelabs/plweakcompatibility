//
//  PLWeakCompatibilityStubs.m
//  PLWeakCompatibility
//
//  Created by Michael Ash on 3/28/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "PLWeakCompatibilityStubs.h"

id objc_autorelease(id obj);

id objc_loadWeakRetained(id *location)
{
    // TODO: this is a primitive method
    return NULL;
}

id objc_initWeak(id *addr, id val)
{
    *addr = NULL;
    return objc_storeWeak(addr, val);
}

void objc_destroyWeak(id *addr)
{
    objc_storeWeak(addr, NULL);
}

void objc_copyWeak(id *to, id *from)
{
    objc_initWeak(to, objc_loadWeak(from));
}

void objc_moveWeak(id *to, id *from)
{
    objc_copyWeak(to, from);
    objc_destroyWeak(from);
}

id objc_loadWeak(id *location)
{
    return objc_autorelease(objc_loadWeakRetained(location));
}

id objc_storeWeak(id *location, id obj)
{
    // TODO: this is a primitive method
    return NULL;
}
