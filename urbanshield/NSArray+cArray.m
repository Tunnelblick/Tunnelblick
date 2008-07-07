//
//  NSArray+CArray.m
//  HotspotShield
//
//  Created by Angelo Laub on 7/5/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "NSArray+cArray.h"


@implementation NSArray (cArray)

-(const char **) cArray 
{
	int i=0;
	int size = 0;
	int count = [self count];
	for(i=0;i < count;i++) {
		size += sizeof([[self objectAtIndex:i] UTF8String]);
	}
	const char **myCArray = (const char **)malloc(size+1);
	for(i=0;i < count;i++) {
		myCArray[i] = [[self objectAtIndex:i] UTF8String];
	}
	myCArray[i] = NULL;
	return myCArray;
}

@end
