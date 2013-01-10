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
    @interface name : superclass \
    @property (copy) dispatch_block_t releaseBlock; \
    @property (copy) dispatch_block_t deallocBlock; \
    @end \
    @implementation name { SEL _release; } \
    @synthesize releaseBlock = _releaseBlock ## name, deallocBlock = _deallocBlock ## name; \
    - (id) init { \
        self = [super init]; \
        _release = sel_getUid("release"); \
        Method m = class_getInstanceMethod([name class], @selector(release_toswizzle)); \
        class_addMethod([name class], _release, method_getImplementation(m), method_getTypeEncoding(m)); \
        return self; \
    } \
    - (void) release_toswizzle { \
        if ([self releaseBlock] != nil) [self releaseBlock](); \
        if (_release == NULL) _release = sel_getUid("release"); \
        struct { void *obj, *class; } superStruct = { (__bridge void *)self, (__bridge void *)[superclass class] }; \
        void (*msgSendSuper)(void *, SEL) = (void (*)(void *, SEL))objc_msgSendSuper; \
        msgSendSuper(&superStruct, _release); \
    } \
    - (void) dealloc { \
        if ([self deallocBlock] != nil) [self deallocBlock](); \
        _release = NULL; \
    } \
    @end

TESTCLASS(PLWeakCompatibilityTestClass1, NSObject)
TESTCLASS(PLWeakCompatibilityTestClass2, PLWeakCompatibilityTestClass1)
TESTCLASS(PLWeakCompatibilityTestClass3, PLWeakCompatibilityTestClass2)

@interface PLWeakCompatibilityEmptyTestSubclass : NSObject @end
@implementation PLWeakCompatibilityEmptyTestSubclass @end

@interface PLWeakCompatibilityManipulateSelfInDeallocClass : NSObject @end
@implementation PLWeakCompatibilityManipulateSelfInDeallocClass

- (void) dealloc {
    CFRelease(CFBridgingRetain(self));
}

@end

@implementation PLWeakCompatibilityTests

- (void) enumerateConfigurations: (void (^)(void)) block {
    PLWeakCompatibilitySetFallthroughEnabled(YES);
    PLWeakCompatibilitySetMAZWREnabled(NO);
    block();

    PLWeakCompatibilitySetFallthroughEnabled(NO);
    block();

    PLWeakCompatibilitySetMAZWREnabled(YES);
    if (PLWeakCompatibilityHasMAZWR()) {
        block();
    } else {
        NSLog(@"Unable to test MAZeroingWeakRef usage as MAZWR is not present");
    }
}

- (void) testBasics {
    [self enumerateConfigurations: ^{
        __weak id weakObj;

        @autoreleasepool {
            id obj = [[PLWeakCompatibilityEmptyTestSubclass alloc] init];
            weakObj = obj;
            STAssertNotNil(weakObj, @"Weak pointer should not be nil");

            obj = nil;
        }

        STAssertNil(weakObj, @"Weak pointer should be nil after destroying the object");
    }];
}

- (void) testInheritance {
    [self enumerateConfigurations: ^{
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
    }];
}

- (void) testDeallocDeadlock {
    [self enumerateConfigurations: ^{
        /* MAZeroingWeakRef is (currently?) susceptible to this deadlock, so don't test it
         * since we don't want to deadlock the tests. */
        if (PLWeakCompatibilityHasMAZWR()) {
            return;
        }
        
        @autoreleasepool {
            __weak id weakSelf = self;
            
            PLWeakCompatibilityTestClass1 *obj = [[PLWeakCompatibilityTestClass1 alloc] init];
            [obj setDeallocBlock: ^{
                dispatch_group_t group = dispatch_group_create();
                dispatch_group_async(group, dispatch_get_global_queue(0, 0), ^{
                    [weakSelf self];
                });
                dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
                dispatch_release(group);
            }];
            __weak id weakObj = obj;
            obj = nil;
            weakObj = nil;
        }
    }];
}

- (void) testGrabDuringRelease {
    /* This test only applies to the built-in ZWR implementation (the OS's can grab a weak ref
     * while blocked in release, and MAZWR will use that when it's available), so exclude other
     * configurations. */
    PLWeakCompatibilitySetFallthroughEnabled(NO);
    PLWeakCompatibilitySetMAZWREnabled(NO);
    
    /* Declare the target and a weak reference to it. Target is a void * so we can have
     * better control over its lifetime. Also note the massive proliferation of
     * @autoreleasepool blocks for the same reason. */
    __block const void *target;
    __weak PLWeakCompatibilityTestClass1 *weakTarget;
    
    @autoreleasepool {
        target = CFBridgingRetain([[PLWeakCompatibilityTestClass1 alloc] init]);
        weakTarget = (__bridge id)target;
    }
    
    /* Set up the block that will be used to acquire the weak reference. Do it now so
     * all of the weak calls used to set up the block are complete before we start blocking. */
    __block BOOL acquired;
    dispatch_semaphore_t acquiredSem = dispatch_semaphore_create(0);
    dispatch_block_t acquireBlock;
    @autoreleasepool {
        acquireBlock = [^{
            id target = weakTarget;
            acquired = target != nil;
            dispatch_semaphore_signal(acquiredSem);
        } copy];
    }
    
    /* Make the object block when released. */
    dispatch_semaphore_t releaseStartedSem = dispatch_semaphore_create(0);
    dispatch_semaphore_t releaseSem = dispatch_semaphore_create(0);
    void (*setReleaseBlock)(const void *, SEL, dispatch_block_t);
    @autoreleasepool {
        setReleaseBlock = (void *)[(__bridge id)target methodForSelector: @selector(setReleaseBlock:)];
    }
    /* When this line runs, target MUST have a retain count of 1, and must do nothing more than be released
     * and deallocate, because this release block is only safe to run once. The rest of the code is set up
     * to make that happen. */
    dispatch_retain(releaseStartedSem);
    dispatch_retain(releaseSem);
    setReleaseBlock(target, @selector(setReleaseBlock:), ^{
        dispatch_semaphore_signal(releaseStartedSem);
        dispatch_semaphore_wait(releaseSem, DISPATCH_TIME_FOREVER);
        dispatch_release(releaseSem);
        dispatch_release(releaseStartedSem);
    });
    
    /* Start the release in the background, but it will wait. */
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        CFRelease(target);
        target = NULL;
    });
    
    /* We want to wait for it to get started here. */
    dispatch_semaphore_wait(releaseStartedSem, DISPATCH_TIME_FOREVER);
    
    /* target is now blocked in release. Start trying to acquire it. */
    dispatch_async(dispatch_get_global_queue(0, 0), acquireBlock);
    
    /* Wait a moment to ensure everybody is blocked. */
    [NSThread sleepUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
    
    /* Unblock the release. */
    dispatch_semaphore_signal(releaseSem);
    
    /* Wait for acquisition. */
    dispatch_semaphore_wait(acquiredSem, DISPATCH_TIME_FOREVER);
    
    /* Make sure we got nil. */
    STAssertFalse(acquired, @"Should have loaded nil from the weak reference while releasing.");
    
    /* Clean up. */
    dispatch_release(releaseSem);
    dispatch_release(releaseStartedSem);
    dispatch_release(acquiredSem);
}

- (void) testMultithreadedRelease {
    [self enumerateConfigurations: ^{
        /* Use a lot of iterations because this bug doesn't show up reliably. */
        for(int n = 0; n < 100000; n++) {
            const void *targetCF;
            __weak PLWeakCompatibilityTestClass1 *weakTarget;
            
            /* Create the target in an autorelease pool so we can control its lifetime. */
            @autoreleasepool {
                PLWeakCompatibilityTestClass1 *target = [[PLWeakCompatibilityTestClass1 alloc] init];
                weakTarget = target;
                targetCF = CFBridgingRetain(target);
            }
            
            /* At this point, target has a retain count of 1. Bump that up so we can get some simultaneous release going. */
            CFRetain(targetCF);
            
            /* Release it twice in the background. */
            for (int i = 0; i < 2; i++)
                [NSThread detachNewThreadSelector: @selector(invoke) toTarget: [^{
                    @autoreleasepool {
                        CFRelease(targetCF);
                    }
                } copy] withObject: nil];
            
            /* Wait for the weak target to go nil. If the ZWR implementation is vulnerable to race conditions between multiple
             * release calls, this will *occasionally* trigger it. */
            while (1) {
                @autoreleasepool {
                    id target = weakTarget;
                    if (target == nil) {
                        break;
                    }
                }
            }
        }
    }];
}

- (void) testReleaseInDealloc {
    [self enumerateConfigurations: ^{
        id obj = [[PLWeakCompatibilityManipulateSelfInDeallocClass alloc] init];
        __weak id weakObj = obj;
        [obj self];
        [weakObj self];
    }];
}

@end
