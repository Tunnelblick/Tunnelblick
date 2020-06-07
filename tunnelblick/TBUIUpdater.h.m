/*
 * Copyright (c) 2014 Jonathan K. Bullard. All rights reserved.
 *
 *  This file is part of Tunnelblick.
 *
 *  Tunnelblick is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  Tunnelblick is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *  or see http://www.gnu.org/licenses/.
 */

//*************************************************************************************************
/*
 *  TBUIUpdater
 *
 *  TBUIUpdater is used to control UI elements that should update every second:
 *
 *      * TB menu items that display the time the status has been unchanged (and not disconnected)
 *      * Notification window status, statistics, and the time the status has been unchanged (and not disconnected)
 *      * The VPN Details window title for the selected configuration
 *      * The Advanced window title for the selected configuration
 *
 */

//*************************************************************************************************

#import "TBUIUpdater.h"

#import "NSTimer+TB.h"

#import "helper.h"

#import "MenuController.h"
#import "MyPrefsWindowController.h"
#import "SettingsSheetWindowController.h"
#import "StatusWindowController.h"
#import "TBUserDefaults.h"
#import "VPNConnection.h"

extern MenuController * gMC;
extern TBUserDefaults * gTbDefaults;

@implementation TBUIUpdater

-(id) init {
    
    self = [super init];
    if (self) {
		
		invalidateAfterNextTickFlag = FALSE;
		
        NSTimeInterval period = [gTbDefaults timeIntervalForKey: @"displayUpdateInterval"
                                                        default: 1.0
                                                            min: 0.5
                                                            max: 10.0];
		
		timer = [[NSTimer scheduledTimerWithTimeInterval: period
												  target: self selector:@selector(timerTickHandler:)
												userInfo: nil
												 repeats: YES]
				 retain];
		
		[[NSRunLoop mainRunLoop]    addTimer: timer forMode: NSRunLoopCommonModes];

        [timer tbSetTolerance: -1.0];
        TBLog(@"DB-UU", @"TBUIUpdater created with update interval %f", period);
    }
    
    return self;
}

-(void) dealloc {
    
    [timer invalidate]; [timer release]; timer = nil;
    
    [nonDisconnectedConnectionsAtPreviousTick release]; nonDisconnectedConnectionsAtPreviousTick = nil;

    TBLog(@"DB-UU", @"TBUIUpdater removed");

    [super dealloc];
}

-(void) invalidateAfterNextTick {
	
	invalidateAfterNextTickFlag = TRUE;
}

-(void) fireTimer {
	
	[timer fire];
}

-(void) timerTickHandler: (NSTimer *) theTimer {
    if (  timer == theTimer  ) {
        
        TBLog(@"DB-UU", @"TBUIUpdater timerTickHandler invoked");
        
        // Make a list of connections to update, consisting of
        //      Connections that are not currrently disconnected
        // plus
        //      Connections that have been removed since the last tick
        
        MenuController * mc = gMC;
        NSArray * notDisconnected = [mc nondisconnectedConnections];
        
        NSUInteger maxSize = [notDisconnected count] + [nonDisconnectedConnectionsAtPreviousTick count];
        NSMutableArray * connectionsToUpdate = [NSMutableArray arrayWithCapacity: maxSize];
        [connectionsToUpdate addObjectsFromArray: notDisconnected];
        NSEnumerator * oldListEnum = [nonDisconnectedConnectionsAtPreviousTick objectEnumerator];
        VPNConnection * connection;
        while (  (connection = [oldListEnum nextObject])  ) {
            if (  ! [notDisconnected containsObject: connection]  ) {
                [connectionsToUpdate addObject: connection];
            }
        }
        
        // Remember the non-disconnected connections for next time through
        [self setNonDisconnectedConnectionsAtPreviousTick: notDisconnected];
        
        // Update the VPN Details... window and the Advanced window if one of the connections to update is selected
        MyPrefsWindowController       * vpnDetailsWc = [mc logScreen];
        SettingsSheetWindowController * advancedWc   = [vpnDetailsWc settingsSheetWindowController];
        connection = [vpnDetailsWc selectedConnection];
        if (   [connectionsToUpdate containsObject: connection]  ) {
            NSWindow * vpnDetailsWindow = [vpnDetailsWc window];
            NSWindow * advancedWindow   = [advancedWc window];
			BOOL showingAdvancedWindow  = [advancedWc showingSettingsSheet];
			if (   vpnDetailsWindow
				|| showingAdvancedWindow  ) {
				NSString * name = [connection localizedName];
				NSString * privateSharedDeployed = [connection displayLocation];
				NSString * state = localizeNonLiteral([connection state], @"Connection status");
				NSString * timeString = [connection connectTimeString];
				if (  vpnDetailsWindow  ) {
					NSString * statusMsg = [NSString stringWithFormat: @"%@%@: %@%@ - Tunnelblick",
											name, privateSharedDeployed, state, timeString];
					[vpnDetailsWindow setTitle: statusMsg];
					TBLog(@"DB-UU", @"TBUIUpdater timerTickHandler: set title of VPN Details... window to '%@'", statusMsg);
				}
				if (   advancedWindow
					&& showingAdvancedWindow  ) {
					NSString * statusMsg = [NSString stringWithFormat: @"%@%@: %@%@ - Advanced - Tunnelblick",
											name, privateSharedDeployed, state, timeString];
					[advancedWindow setTitle: statusMsg];
					TBLog(@"DB-UU", @"TBUIUpdater timerTickHandler: set title of Advanced       window to '%@'", statusMsg);
				}
			}
		}
        
        // Update status windows and menu items for the connections to update
        NSEnumerator * e = [connectionsToUpdate objectEnumerator];
        while (  (connection = [e nextObject])  ) {
			
			StatusWindowController * swc = [connection statusScreen];
			if (  [swc isOpen]  ) {
				TBLog(@"DB-UU", @"TBUIUpdater timerTickHandler: updating status window for            '%@'", [connection displayName]);
				[connection updateStatisticsDisplay];
			}
			
			if (  [mc menuIsOpen]  ) {
				TBLog(@"DB-UU", @"TBUIUpdater timerTickHandler: updating menu item                    '%@'", [connection displayName]);
				NSMenuItem * menuItem = [connection menuItem];
				[connection validateMenuItem: menuItem];
			}
		}
		
		if (  invalidateAfterNextTickFlag  ) {
			[timer invalidate];
		}
    }
}

TBSYNTHESIZE_OBJECT(retain, NSArray *, nonDisconnectedConnectionsAtPreviousTick, setNonDisconnectedConnectionsAtPreviousTick)

@end

































