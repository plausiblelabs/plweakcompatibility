//
//  PLWeakCompatibilityStubs.h
//  PLWeakCompatibility
//
//  Created by Michael Ash on 3/28/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void *PLObjectPtr;

PLObjectPtr objc_loadWeakRetained(PLObjectPtr *location);
PLObjectPtr objc_initWeak(PLObjectPtr *addr, PLObjectPtr val);
void objc_destroyWeak(PLObjectPtr *addr);
void objc_copyWeak(PLObjectPtr *to, PLObjectPtr *from);
void objc_moveWeak(PLObjectPtr *to, PLObjectPtr *from);
PLObjectPtr objc_loadWeak(PLObjectPtr *location);
PLObjectPtr objc_storeWeak(PLObjectPtr *location, PLObjectPtr obj);

void PLWeakCompatibilitySetMAZWREnabled(BOOL enabled);
void PLWeakCompatibilitySetFallthroughEnabled(BOOL enabled);
