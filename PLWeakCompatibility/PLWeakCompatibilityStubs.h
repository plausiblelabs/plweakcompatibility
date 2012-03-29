//
//  PLWeakCompatibilityStubs.h
//  PLWeakCompatibility
//
//  Created by Michael Ash on 3/28/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

__unsafe_unretained id objc_loadWeakRetained(__unsafe_unretained id *location);
__unsafe_unretained id objc_initWeak(__unsafe_unretained id *addr, __unsafe_unretained id val);
void objc_destroyWeak(__unsafe_unretained id *addr);
void objc_copyWeak(__unsafe_unretained id *to, __unsafe_unretained id *from);
void objc_moveWeak(__unsafe_unretained id *to, __unsafe_unretained id *from);
__unsafe_unretained id objc_loadWeak(__unsafe_unretained id *location);
__unsafe_unretained id objc_storeWeak(__unsafe_unretained id *location, __unsafe_unretained id obj);

void PLWeakCompatibilitySetFallthroughEnabled(BOOL enabled);
