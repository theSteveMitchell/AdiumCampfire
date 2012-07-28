//
//  MSCampfireRoom.h
//  AdiumCampfire
//
//  Created by Marek Stępniowski on 10-03-30.
//  Copyright 2010 Apple Inc. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface MSCampfireRoom : NSObject {

  NSInteger uid;
  NSMutableArray *contactUIDs;
    NSDictionary *usersByUID;
} 

- (MSCampfireRoom *)initWithUID:(NSInteger)anUID;
- (void)addContactWithUID:(NSInteger)anUID;
- (void)removeContactWithUID:(NSInteger)toRemove;
- (NSArray *)contactUIDs;

@end
