//
//  PLWeakCompatibilityTests.m
//  PLWeakCompatibilityTests
//
//  Created by Michael Ash on 3/28/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "PLWeakCompatibilityTests.h"

#import "PLWeakCompatibilityStubs.h"


@implementation PLWeakCompatibilityTests

- (void) reallyTestBasics {
    __weak id weakObj;

    @autoreleasepool {
        id obj = [[NSObject alloc] init];
        weakObj = obj;
        STAssertNotNil(weakObj, @"Weak pointer should not be nil");

        obj = nil;
    }

    STAssertNil(weakObj, @"Weak pointer should be nil after destroying the object");
}

- (void) testBasics {
    PLWeakCompatibilitySetFallthroughEnabled(YES);
    [self reallyTestBasics];
    PLWeakCompatibilitySetFallthroughEnabled(NO);
    [self reallyTestBasics];
}

@end
