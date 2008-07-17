//
//  NSArray+CArray.h
//  HotspotShield
//
//  Created by Angelo Laub on 7/5/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSArray (cArray)

- (const char **) cArray;

@end
