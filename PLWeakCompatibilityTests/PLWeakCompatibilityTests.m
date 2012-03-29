//
//  PLWeakCompatibilityTests.m
//  PLWeakCompatibilityTests
//
//  Created by Michael Ash on 3/28/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "PLWeakCompatibilityTests.h"

#import <objc/message.h>
#import <objc/runtime.h>

#define EXCLUDE_STUB_PROTOTYPES 1
#import "PLWeakCompatibilityStubs.h"


#define TESTCLASS(name, superclass) \
    @interface name : superclass @end \
    @implementation name { SEL _release; } \
    - (id) init { \
        self = [super init]; \
        _release = sel_getUid("release"); \
        Method m = class_getInstanceMethod([name class], _release); \
        class_addMethod([name class], _release, method_getImplementation(m), method_getTypeEncoding(m)); \
        return self; \
    } \
    - (void) release_toswizzle { \
        struct { void *obj, *class; } superStruct = { (__bridge void *)self, (__bridge void *)[superclass class] }; \
        void (*msgSendSuper)(void *, SEL) = (void (*)(void *, SEL))objc_msgSendSuper; \
        msgSendSuper(&superStruct, _release); \
    } \
    - (void) dealloc { _release = NULL; } \
    @end

TESTCLASS(PLWeakCompatibilityTestClass1, NSObject)
TESTCLASS(PLWeakCompatibilityTestClass2, PLWeakCompatibilityTestClass1)
TESTCLASS(PLWeakCompatibilityTestClass3, PLWeakCompatibilityTestClass2)

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

    PLWeakCompatibilitySetMAZWREnabled(YES);
    [self reallyTestBasics];
}

- (void) reallyTestInheritance {
    __weak id weakObj1;
    __weak id weakObj2;

    @autoreleasepool {
        PLWeakCompatibilityTestClass1 *obj1 = [[PLWeakCompatibilityTestClass1 alloc] init];
        PLWeakCompatibilityTestClass2 *obj2 = [[PLWeakCompatibilityTestClass2 alloc] init];

        weakObj1 = obj1;
        weakObj2 = obj2;

        STAssertNotNil(weakObj1, @"Test object 1 should not be nil");
        STAssertNotNil(weakObj2, @"Test object 2 should not be nil");

        NSArray *array = [NSArray arrayWithObjects: obj1, obj2, nil];
        array = [NSArray arrayWithObjects: obj2, obj1, nil];
        NSMutableArray *mutableArray = [array mutableCopy];
        [mutableArray removeAllObjects];
    }

    STAssertNil(weakObj1, @"Test object 1 should be nil");
    STAssertNil(weakObj2, @"Test object 2 should be nil");
}

- (void) DISABLED_testInheritance {
    PLWeakCompatibilitySetFallthroughEnabled(YES);
    [self reallyTestInheritance];
    PLWeakCompatibilitySetFallthroughEnabled(NO);
    [self reallyTestInheritance];
}

@end
