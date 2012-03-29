//
//  PLWeakCompatibilityStubs.h
//  PLWeakCompatibility
//
//  Created by Michael Ash on 3/28/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

// Convince ARC to leave these kids alone
typedef void *VoidPtr;
#define id VoidPtr

id objc_loadWeakRetained(id *location);
id objc_initWeak(id *addr, id val);
void objc_destroyWeak(id *addr);
void objc_copyWeak(id *to, id *from);
void objc_moveWeak(id *to, id *from);
id objc_loadWeak(id *location);
id objc_storeWeak(id *location, id obj);
