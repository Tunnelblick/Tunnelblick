//
//  UKLoginItemRegistry.h
//  TalkingMoose (XC2)
//
//  Created by Uli Kusterer on 14.03.06.
//  Copyright 2006 M. Uli Kusterer. All rights reserved.
//

// -----------------------------------------------------------------------------
//	Headers:
// -----------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import "LoginItemsAE.h"

/*
	This class is a wrapper around Apple's LoginItemsAE sample code.
	
	allLoginItems returns an array of dictionaries containing the URL of the
	login item under key UKLoginItemURL and the launch hidden status under
	UKLoginItemHidden.
	
	All methods that return a BOOL generally return YES on success and NO on
	failure.
*/

// -----------------------------------------------------------------------------
//	Constants:
// -----------------------------------------------------------------------------

#define UKLoginItemURL		((NSString*)kLIAEURL)
#define UKLoginItemHidden	((NSString*)kLIAEHidden)


// -----------------------------------------------------------------------------
//	Class Declaration:
// -----------------------------------------------------------------------------

@interface UKLoginItemRegistry : NSObject
{

}

+(NSArray*)	allLoginItems;
+(BOOL)		removeLoginItemAtIndex: (int)idx;

+(BOOL)		addLoginItemWithURL: (NSURL*)url hideIt: (BOOL)hide;
+(int)		indexForLoginItemWithURL: (NSURL*)url;		// Use this to detect whether you've already been set, if needed.
+(BOOL)		removeLoginItemWithURL: (NSURL*)url;

+(BOOL)		addLoginItemWithPath: (NSString*)path hideIt: (BOOL)hide;
+(int)		indexForLoginItemWithPath: (NSString*)path;	// Use this to detect whether you've already been set, if needed.
+(BOOL)		removeLoginItemWithPath: (NSString*)path;

@end
