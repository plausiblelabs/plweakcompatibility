//
//  PLAppDelegate.m
//  PLWeakCompatibility
//
//  Created by Michael Ash on 3/28/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "PLAppDelegate.h"

@implementation PLAppDelegate

@synthesize window = _window;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // do some lame tests
    id obj = [[NSObject alloc] init];
    __weak id weakObj = obj;
    dispatch_block_t block = [^{ NSLog(@"%@", weakObj); } copy];
    NSLog(@"%@", weakObj);
    block();
    
    return YES;
}

@end
