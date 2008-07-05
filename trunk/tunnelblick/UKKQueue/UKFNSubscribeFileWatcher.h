//
//  UKFNSubscribeFileWatcher.h
//  Filie
//
//  Created by Uli Kusterer on 02.03.05.
//  Copyright 2005 M. Uli Kusterer. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "UKFileWatcher.h"
#import <Carbon/Carbon.h>


@interface UKFNSubscribeFileWatcher : NSObject <UKFileWatcher>
{
    id                      delegate;           // Delegate must respond to UKFileWatcherDelegate protocol.
    NSMutableDictionary*    subscriptions;      // List of FNSubscription pointers in NSValues, with the pathnames as their keys.
}

// UKFileWatcher defines the methods: addPath: removePath: and delegate accessors.

// Private:
-(void) sendDelegateMessage: (FNMessage)message forSubscription: (FNSubscriptionRef)subscription;

@end
