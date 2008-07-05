//
//  UKFNSubscribeFileWatcher.m
//  Filie
//
//  Created by Uli Kusterer on 02.03.05.
//  Copyright 2005 M. Uli Kusterer. All rights reserved.
//

#import "UKFNSubscribeFileWatcher.h"
#import <Carbon/Carbon.h>


void    UKFileSubscriptionProc(FNMessage message, OptionBits flags, void *refcon, FNSubscriptionRef subscription);


@implementation UKFNSubscribeFileWatcher

-(id)   init
{
    self = [super init];
    if( !self ) 
        return nil;
    
    subscriptions = [[NSMutableDictionary alloc] init];
    
    return self;
}

-(void) dealloc
{
    NSEnumerator*   enny = [subscriptions objectEnumerator];
    NSValue*        subValue = nil;
    
    while( (subValue = [enny nextObject]) )
    {
        FNSubscriptionRef   subscription = [subValue pointerValue];
        FNUnsubscribe( subscription );
    }
    
    [subscriptions release];
    [super dealloc];
}

-(void) addPath: (NSString*)path
{
    OSStatus                    err = noErr;
    static FNSubscriptionUPP    subscriptionUPP = NULL;
    FNSubscriptionRef           subscription = NULL;
    
    if( !subscriptionUPP )
        subscriptionUPP = NewFNSubscriptionUPP( UKFileSubscriptionProc );
    
    err = FNSubscribeByPath( [path fileSystemRepresentation], subscriptionUPP, (void*)self,
                                kNilOptions, &subscription );
    if( err != noErr )
    {
        NSLog( @"UKFNSubscribeFileWatcher addPath: %@ failed due to error ID=%ld.", path, err );
        return;
    }
    
    [subscriptions setObject: [NSValue valueWithPointer: subscription] forKey: path];
}


-(void) removePath: (NSString*)path
{
    NSValue*            subValue = nil;
    @synchronized( self )
    {
        subValue = [[[subscriptions objectForKey: path] retain] autorelease];
        [subscriptions removeObjectForKey: path];
    }
    
    FNSubscriptionRef   subscription = [subValue pointerValue];
    
    FNUnsubscribe( subscription );
}


-(void) sendDelegateMessage: (FNMessage)message forSubscription: (FNSubscriptionRef)subscription
{
    NSValue*                    subValue = [NSValue valueWithPointer: subscription];
    NSString*                   path = [[subscriptions allKeysForObject: subValue] objectAtIndex: 0];
    
    [delegate watcher: self receivedNotification: UKFileWatcherWriteNotification forPath: path];
    NSLog( @"UKFNSubscribeFileWatcher noticed change to %@", path );
}



-(id)   delegate
{
    return delegate;
}


-(void) setDelegate: (id)newDelegate
{
    delegate = newDelegate;
}


@end


void    UKFileSubscriptionProc( FNMessage message, OptionBits flags, void *refcon, FNSubscriptionRef subscription )
{
    UKFNSubscribeFileWatcher*   obj = (UKFNSubscribeFileWatcher*) refcon;
    
    if( message == kFNDirectoryModifiedMessage )    // No others exist as of 10.3
        [obj sendDelegateMessage: message forSubscription: subscription];
    else
        NSLog( @"UKFileSubscriptionProc: Unknown message %d", message );
}