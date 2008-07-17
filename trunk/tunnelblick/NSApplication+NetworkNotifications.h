//
//  NSApplication+NetworkNotifications.h
//  Tunnelblick
//
//  Created by Dirk Theisen on 16.08.05.
//  Copyright 2005 Dirk Theisen. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface NSApplication (NetworkNotifications)


- (void) callDelegateOnNetworkChange: (BOOL) doNotify;


@end
