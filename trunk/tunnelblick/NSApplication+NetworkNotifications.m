//
//  NSApplication+NetworkNotifications.m
//  Tunnelblick
//
//  Created by Dirk Theisen on 16.08.05.
//  Copyright 2005 Dirk Theisen. All rights reserved.
//

#import "NSApplication+NetworkNotifications.h"
#import <Foundation/NSDebug.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/time.h>
#include <unistd.h>
#include <notify.h>

static int qtoken = 0; 

@implementation NSApplication (NetworkNotifications)



+ (void) netConfigChanged: (NSNotification*) fileNotification
{
	NSFileHandle* handle = [fileNotification object];
	NSData* dataRead = [[fileNotification userInfo] objectForKey: NSFileHandleNotificationDataItem];

	//NSLog(@"Read notification data: %@", dataRead);
	if ((*((int*)[dataRead bytes]))!=qtoken && NSDebugEnabled)  NSLog(@"Problem with notification token. Please check!");
	
	if ([[NSApp delegate] respondsToSelector: @selector(networkConfigurationDidChange)]) {
		[[NSApp delegate] performSelector: @selector(networkConfigurationDidChange)];
	}
	
	[handle readInBackgroundAndNotify];		
}

- (void) callDelegateOnNetworkChange: (BOOL) doNotify
/*" Calls the NSApp delegate method 'networkConfigurationDidChange' whenever the network configuration changes. "*/
{
	static NSFileHandle* netChangedNotificationHandle = nil;
	 if (doNotify) {
		if (!netChangedNotificationHandle) {
		int nf = 0;
		int status = notify_register_file_descriptor("com.apple.system.config.network_change",
												 &nf, 0, &qtoken);

		if (status != NOTIFY_STATUS_OK) {
			NSLog(@"Warning: notify_register_file_descriptor: registration failed (%u)\n", status);
		}
		
		netChangedNotificationHandle = [[NSFileHandle alloc] initWithFileDescriptor: nf];
		
		[[NSNotificationCenter defaultCenter] addObserver: [self class] 
												 selector: @selector(netConfigChanged:) 
													 name: NSFileHandleReadCompletionNotification 
												   object: netChangedNotificationHandle];
		
		[netChangedNotificationHandle readInBackgroundAndNotify];	
		
		}
	} else {
		if (netChangedNotificationHandle) {		
			
			[[NSNotificationCenter defaultCenter] removeObserver: self 
															name: NSFileHandleReadCompletionNotification 
														  object: [self class]];
			
			[netChangedNotificationHandle release]; netChangedNotificationHandle = nil;
			
			//notify_cancel(qtoken); qtoken = 0;
		}
	}
}

@end
