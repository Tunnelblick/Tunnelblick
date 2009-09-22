/*
 * Copyright (c) 2004, 2005, 2006, 2007, 2008, 2009 Angelo Laub
 * Contributions by Dirk Theisen <dirk@objectpark.org>, 
 *                  Jens Ohlig, 
 *                  Waldemar Brodkorb,
 *                  Jonathan K. Bullard
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */


#import "MenuController.h"
#import <CoreFoundation/CoreFoundation.h>
#import <signal.h>
#import <sys/types.h>
#import <sys/socket.h>
#import <stdlib.h>
#import <errno.h>
#import <Security/Security.h>
#import <CoreServices/CoreServices.h>
#import <Foundation/NSDebug.h>
#import <Security/Authorization.h>
#import <Security/AuthorizationTags.h>
#import <sys/types.h>
#import <sys/stat.h>
#import "KeyChain.h"
#import "NetSocket.h"
#import "NSApplication+LoginItem.h"
#import "NSApplication+NetworkNotifications.h"
#import "helper.h"


// *******************************************************************************************************************
// Start of code from http://www.cocoadev.com/index.pl?DeterminingOSVersion

@interface NSApplication (SystemVersion)

- (void)getSystemVersionMajor:(unsigned *)major
                        minor:(unsigned *)minor
                       bugFix:(unsigned *)bugFix;

@end

@implementation NSApplication (SystemVersion)

- (void)getSystemVersionMajor:(unsigned *)major
                        minor:(unsigned *)minor
                       bugFix:(unsigned *)bugFix;
{
    OSErr err;
    SInt32 systemVersion, versionMajor, versionMinor, versionBugFix;
    if ((err = Gestalt(gestaltSystemVersion, &systemVersion)) != noErr) goto fail;
    if (systemVersion < 0x1040)
    {
        if (major) *major = ((systemVersion & 0xF000) >> 12) * 10 +
            ((systemVersion & 0x0F00) >> 8);
        if (minor) *minor = (systemVersion & 0x00F0) >> 4;
        if (bugFix) *bugFix = (systemVersion & 0x000F);
    }
    else
    {
        if ((err = Gestalt(gestaltSystemVersionMajor, &versionMajor)) != noErr) goto fail;
        if ((err = Gestalt(gestaltSystemVersionMinor, &versionMinor)) != noErr) goto fail;
        if ((err = Gestalt(gestaltSystemVersionBugFix, &versionBugFix)) != noErr) goto fail;
        if (major) *major = versionMajor;
        if (minor) *minor = versionMinor;
        if (bugFix) *bugFix = versionBugFix;
    }
    
    return;
    
fail:
    NSLog(@"Unable to obtain system version: %ld", (long)err);
    if (major) *major = 10;
    if (minor) *minor = 0;
    if (bugFix) *bugFix = 0;
}

@end

// End of code from http://www.cocoadev.com/index.pl?DeterminingOSVersion
// *******************************************************************************************************************

BOOL runningOnTigerOrNewer()
{
    unsigned major, minor, bugFix;
    [[NSApplication sharedApplication] getSystemVersionMajor:&major minor:&minor bugFix:&bugFix];
    return ( (major > 10) || (minor > 2) );
}

@interface NSStatusBar (NSStatusBar_Private)
- (id)_statusItemWithLength:(float)l withPriority:(int)p;
- (id)_insertStatusItem:(NSStatusItem *)i withPriority:(int)p;
@end


@implementation MenuController

// Places an item with our icon in the Status Bar (creating it first if it doesn't already exist)
// By default, it uses an undocumented hack to place the icon on the right side, next to SpotLight
// Otherwise ("placeIconInStandardPositionInStatusBar" preference or hack not available), it places it normally (on the left)
- (void) createStatusItem
{
	NSStatusBar *bar = [NSStatusBar systemStatusBar];

	if (   [bar respondsToSelector: @selector(_statusItemWithLength:withPriority:)]
        && [bar respondsToSelector: @selector(_insertStatusItem:withPriority:)]
        && (  ! [[NSUserDefaults standardUserDefaults] boolForKey:@"placeIconInStandardPositionInStatusBar"]  )
       ) {
        // Force icon to the right in Status Bar
        int priority = INT32_MAX;
        if (  runningOnTigerOrNewer()  ) {
            priority = MIN(priority, 2147483646); // found by experimenting - dirk
        }
        
        if ( ! theItem  ) {
            if (  ! ( theItem = [[bar _statusItemWithLength: NSVariableStatusItemLength withPriority: priority] retain] )  ) {
                NSLog(@"Can't insert icon in Status Bar");
            }
        }
        // Re-insert item to place it correctly, to the left of SpotLight
        [bar removeStatusItem: theItem];
        [bar _insertStatusItem: theItem withPriority: priority];
    } else {
        // Standard placement of icon in Status Bar
        if (  ! theItem  ) {
            if (  ! (theItem = [[bar statusItemWithLength: NSVariableStatusItemLength] retain])  ) {
                NSLog(@"Can't insert icon in Status Bar");
            }
        }
    }
}

-(id) init
{	
    if (self = [super init]) {
        [self dmgCheck];
		
		[NSApp setDelegate:self];
		
        if(needsRepair()){
            if ([self repairPermissions] != TRUE) {
                [NSApp terminate:self];
            }
        } 
                
        myVPNConnectionDictionary = [[NSMutableDictionary alloc] init];
        connectionArray = [[[NSMutableArray alloc] init] retain];
 
        userDefaults = [[NSMutableDictionary alloc] init];
        appDefaults = [NSUserDefaults standardUserDefaults];
        [appDefaults registerDefaults:userDefaults];

        [self loadMenuIconSet];

		detailsItem = [[NSMenuItem alloc] init];
		[detailsItem setTitle: @"Details..."];
		[detailsItem setTarget: self];
		[detailsItem setAction: @selector(openLogWindow:)];
		
		aboutItem = [[NSMenuItem alloc] init];
		[aboutItem setTitle: @"About..."];
		[aboutItem setTarget: self];
		[aboutItem setAction: @selector(openAboutWindow:)];
		
		quitItem = [[NSMenuItem alloc] init];
		[quitItem setTitle: @"Quit"]; 
		[quitItem setTarget: self];
		[quitItem setAction: @selector(quit:)];
        
		[self createStatusItem];
		
		[self createMenu];
        [self setState: @"EXITING"]; // synonym for "Disconnected"
        
        [[NSNotificationCenter defaultCenter] addObserver: self 
                                                 selector: @selector(logNeedsScrolling:) 
                                                     name: @"LogDidChange" 
                                                   object: nil];
		
		// In case the systemUIServer restarts, we observed this notification.
		// We use it to prevent to end up with a statusItem right of Spotlight:
		[[NSDistributedNotificationCenter defaultCenter] addObserver: self 
															selector: @selector(menuExtrasWereAdded:) 
																name: @"com.apple.menuextra.added" 
															  object: nil];
		[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
															   selector: @selector(willGoToSleep)
																   name: @"NSWorkspaceWillSleepNotification"
																 object:nil];
		
		[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
															   selector: @selector(wokeUpFromSleep)
																   name: @"NSWorkspaceDidWakeNotification"
																 object:nil];
		
		NSString* vpnDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/openvpn/"];
		
        if (  ! [[NSUserDefaults standardUserDefaults] boolForKey:@"doNotMonitorConfigurationFolder"]  ) {
            UKKQueue* myQueue = [UKKQueue sharedFileWatcher];
            [myQueue addPathToQueue: vpnDirectory];
            [myQueue setDelegate: self];
            [myQueue setAlwaysNotify: YES];
		}
        
		[NSThread detachNewThreadSelector:@selector(moveSoftwareUpdateWindowToForegroundThread) toTarget:self withObject:nil];
		
        updater = [[SUUpdater alloc] init];

	}
    return self;
}

-(void)moveSoftwareUpdateWindowToForegroundThread
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    sleep(3);
    [self moveSoftwareUpdateWindowToForeground];
    //	[NSTimer scheduledTimerWithTimeInterval: 1.0 target: self selector: @selector(moveSoftwareUpdateWindowToForeground) userInfo: nil repeats: YES];
    [pool release];
}


- (void) menuExtrasWereAdded: (NSNotification*) n
{
	[self createStatusItem];
}


- (IBAction) quit: (id) sender
{
    // Remove us from the login items if terminates manually...
    [NSApp setAutoLaunchOnLogin: NO];
    [NSApp terminate: sender];
}



- (void) awakeFromNib
{
	[self createDefaultConfig];
	[self initialiseAnim];
}

- (void) loadMenuIconSet
{
    NSString *menuIconSet = [[NSUserDefaults standardUserDefaults] stringForKey:@"menuIconSet"];
    if (  menuIconSet == nil  ) {
        menuIconSet = @"TunnelBlick.TBMenuIcons";
    }

    int nFrames = 0;
    int i=0;
    NSString *file;
    NSString *fullPath;
    NSString *confDir = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"IconSets"] stringByAppendingPathComponent:menuIconSet];
    NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath: confDir];
    NSArray *allObjects = [dirEnum allObjects];
    
    animImages = [[NSMutableArray alloc] init];

    for(i=0;i<[allObjects count];i++) {
        file = [allObjects objectAtIndex:i];
        fullPath = [confDir stringByAppendingPathComponent:file];
        
        if ([[file pathExtension] isEqualToString: @"png"]) {
            NSString *name = [[file lastPathComponent] stringByDeletingPathExtension];

            if(         [name isEqualToString:@"closed"]) {
                mainImage = [[NSImage alloc] initWithContentsOfFile:fullPath];
            
            } else if(  [name isEqualToString:@"open"]) {
                connectedImage = [[NSImage alloc] initWithContentsOfFile:fullPath];
            
            } else {
                if(  [[file lastPathComponent] isEqualToString:@"0.png"]) {  //[name intValue] returns 0 on failure, so make sure we find the first frame
                    nFrames++;
                } else if(  [name intValue] > 0) {
                    nFrames++;
                }
            }
        }
    }

    NSFileManager * fileMgr = [[NSFileManager alloc] init];     // don't choke on a bad set of files, e.g., {0.png, 1abc.png, 2abc.png, 3.png, 4.png, 6.png}
                                                                // (won't necessarily find all files, but won't try to load files that don't exist)
    for(i=0;i<nFrames;i++) {
        fullPath = [confDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.png", i]];
        if ([fileMgr fileExistsAtPath:fullPath]) {
            NSImage *frame = [[NSImage alloc] initWithContentsOfFile:fullPath];
            [animImages addObject:frame];
            [frame release];
        }
    }
    
    [fileMgr release];

}

- (void) initialiseAnim
{
    int i;
	// theAnim is an NSAnimation instance variable
	theAnim = [[NSAnimation alloc] initWithDuration:2.0
                                     animationCurve:NSAnimationLinear];
	[theAnim setFrameRate:7.0];
	[theAnim setDelegate:self];
	
    for (i=1; i<=[animImages count]; i++)
    {
        NSAnimationProgress p = ((float)i)/((float)[animImages count]);
        [theAnim addProgressMark:p];
    }
	[theAnim setAnimationBlockingMode:  NSAnimationNonblocking];
}

// Initial creation of the menu
-(void) createMenu 
{	
    [theItem setHighlightMode:YES];
    [theItem setMenu:nil];
	[myVPNMenu release]; myVPNMenu = nil;
	[[myVPNConnectionDictionary allValues] makeObjectsPerformSelector:@selector(disconnect:) withObject:self];
	[myVPNConnectionDictionary removeAllObjects];
	
	myVPNMenu = [[NSMenu alloc] init];
    [myVPNMenu setDelegate:self];
    
	[theItem setMenu: myVPNMenu];
	
	statusMenuItem = [[NSMenuItem alloc] init];
	[myVPNMenu addItem:statusMenuItem];
	[myVPNMenu addItem:[NSMenuItem separatorItem]];
    
	[myConfigArray release];
    myConfigArray = [[[[self getConfigs] sortedArrayUsingSelector:@selector(compare:)] mutableCopy] retain];
    
	NSEnumerator *m = [myConfigArray objectEnumerator];
	NSString *configString;
    int i = 2; // we start at MenuItem #2
	
    while (configString = [m nextObject]) 
    {
		NSMenuItem *connectionItem = [[[NSMenuItem alloc] init] autorelease];
		
        // configure connection object:
		VPNConnection* myConnection = [[VPNConnection alloc] initWithConfig: configString]; // initialize VPN Connection with config	
		[myConnection setState:@"EXITING"];
		[myConnection setDelegate:self];
        
        // handle autoconnection:
		NSString *autoConnectKey = [[myConnection configName] stringByAppendingString: @"autoConnect"];
		if([[NSUserDefaults standardUserDefaults] boolForKey:autoConnectKey]) 
        {
			if(![myConnection isConnected]) [myConnection connect:self];
        }
        
		[myVPNConnectionDictionary setObject: myConnection forKey:configString];
		
        // Note: The item's title will be set on demand in -validateMenuItem
		[connectionItem setTarget:myConnection]; 
		[connectionItem setAction:@selector(toggle:)];
		
		[myVPNMenu insertItem:connectionItem atIndex:i];
		i++;
	}
	
	[myVPNMenu addItem: [NSMenuItem separatorItem]];
	[myVPNMenu addItem: detailsItem];
	[myVPNMenu addItem: [NSMenuItem separatorItem]];
	[myVPNMenu addItem: aboutItem];
	[myVPNMenu addItem: [NSMenuItem separatorItem]];
	[myVPNMenu addItem: quitItem];
    
    // Localize all menu items:
    NSMenuItem *item;
    NSEnumerator *e = [[myVPNMenu itemArray] objectEnumerator];
    
    while (item = [e nextObject]) 
    {
        [item setTitle:NSLocalizedString([item title], nil)];
    }
}


// If any new config files have been added, add each to the menu and add tabs for each to the Log window.
// If any config files have been deleted, remove them from the menu and remove their tabs in the Log window
-(void) updateMenuAndLogWindow 
{	
    NSArray * curConfigsArray = [[self getConfigs] sortedArrayUsingSelector:@selector(compare:)];
	NSEnumerator *m = [curConfigsArray objectEnumerator];
	NSString *configString;
    
    BOOL needToUpdateLogWindow = FALSE;

    // First add the new ones
    while (configString = [m nextObject]) {
        if (  [myConfigArray indexOfObject:configString] == NSNotFound  ) {
            
            // Add new config to myVPNConnectionDictionary
            VPNConnection* myConnection = [[VPNConnection alloc] initWithConfig: configString];
            [myConnection setState:@"EXITING"];
            [myConnection setDelegate:self];
            [myVPNConnectionDictionary setObject: myConnection forKey:configString];
            
            // Add new config to myConfigArray and the menu, keeping myConfigArray sorted
            // Note: The item's title will be set on demand in -validateMenuItem
            NSMenuItem *connectionItem = [[[NSMenuItem alloc] init] autorelease];
            [connectionItem setTarget:myConnection]; 
            [connectionItem setAction:@selector(toggle:)];
            int i;
            for (i=0; i<[myConfigArray count]; i++) {
                if (  [[myConfigArray objectAtIndex:i] isGreaterThan:configString]  ) {
                    break;
                }
            }
            [myConfigArray insertObject:configString atIndex:i];
            [myVPNMenu insertItem:connectionItem atIndex:i+2];  // Note: first item is status, second is a separator
            
            needToUpdateLogWindow = TRUE;
        }
    }
    
    // Now remove the ones that have been deleted
    m = [myConfigArray objectEnumerator];
    while (configString = [m nextObject]) {
        if (  [curConfigsArray indexOfObject:configString] == NSNotFound  ) {
            
            // Disconnect first if necessary
            VPNConnection* myConnection = [myVPNConnectionDictionary objectForKey:configString];
            if (  ! [[myConnection state] isEqualTo:@"EXITING"]  ) {
                [myConnection disconnect:self];
                NSAlert * alert = [[NSAlert alloc] init];
                NSString * msg1 = NSLocalizedString(@"'%@' has been disconnected", nil);
                NSString * msg2 = NSLocalizedString(@"Tunnelblick has disconnected '%@' because its configuration file has been removed.", nil);
                [alert setMessageText:[NSString stringWithFormat:msg1, [myConnection configName]]];
                [alert setInformativeText:[NSString stringWithFormat:msg2, [myConnection configName]]];
                [alert runModal];
                [alert release];
            }

            [[myVPNConnectionDictionary objectForKey:configString] release];
            
            [myVPNConnectionDictionary removeObjectForKey:configString];
            
            // Remove config from myConfigArray and the menu
            int i = [myConfigArray indexOfObject:configString];
            [myConfigArray removeObjectAtIndex:i];
            [myVPNMenu removeItemAtIndex:i+2];  // Note: first item is status, second is a separator
            
            needToUpdateLogWindow = TRUE;
        }
    }
    
    if (  needToUpdateLogWindow  ) {
        // Add or remove configurations from the Log window (if it is open) by closing and reopening the Log window
        BOOL logWindowWasOpen = logWindowIsOpen;
        if (  logWindowIsOpen  ) {
            [logWindow close];
            [logWindow release];
            logWindow = nil;
        }
        if (  logWindowWasOpen  ) {
            [self openLogWindow:self];
        }
    }
}

- (void)activateStatusMenu
{
    [self updateUI];
    [self updateMenuAndLogWindow];
}

- (void)connectionStateDidChange:(id)connection
{
	[self updateTabLabels];
    if (connection == [self selectedConnection]) 
	{
		[self validateLogButtons];
	}	
}

-(NSMutableArray *)getConfigs {
    int i = 0;  	
    NSMutableArray *array = [[[NSMutableArray alloc] init] autorelease];
    NSString *file;
    NSString *confDir = [NSHomeDirectory() stringByAppendingPathComponent: @"/Library/openvpn"];
    NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath: confDir];
    while (file = [dirEnum nextObject]) {
        if ([[file pathExtension] isEqualToString: @"conf"] || [[file pathExtension] isEqualToString: @"ovpn"]) {
			[array insertObject:file atIndex:i];
			//if(NSDebugEnabled) NSLog(@"Object: %@ atIndex: %d\n",file,i);
			i++;
        }
    }
    return array;
}

- (IBAction)validateLogButtons
{
    //NSLog(@"validating log buttons");
    VPNConnection* connection = [self selectedConnection];
    [connectButton setEnabled:[connection isDisconnected]];
    [disconnectButton setEnabled:(![connection isDisconnected])];
	[[NSUserDefaults standardUserDefaults] synchronize];
	NSString *autoConnectKey = [[connection configName] stringByAppendingString:@"autoConnect"];
	if([[NSUserDefaults standardUserDefaults] boolForKey:autoConnectKey]) {
		[autoLaunchCheckbox setState:NSOnState];
	} else {
		[autoLaunchCheckbox setState:NSOffState];
	}
	
	BOOL lol = useDNSStatus(connection);
	if(lol) {
		[useNameserverCheckbox setState:NSOnState];
	} else {
		[useNameserverCheckbox setState:NSOffState];
	}
}

-(void)updateTabLabels
{
	NSArray *keyArray = [[myVPNConnectionDictionary allKeys] sortedArrayUsingSelector: @selector(compare:)];
	NSArray *myConnectionArray = [myVPNConnectionDictionary objectsForKeys:keyArray notFoundMarker:[NSNull null]];
	NSEnumerator *connectionEnumerator = [myConnectionArray objectEnumerator];
	VPNConnection *myConnection;

	int i = 0;
	while(myConnection = [connectionEnumerator nextObject]) {
		//NSLog(@"configName: %@\nconnectionState: %@\n",[myConnection configName],[myConnection state]);
        NSString * cState = [myConnection state];
        NSString * cTimeS = @"";

        // Get connection duration if preferences say to 
        if (    [[NSUserDefaults standardUserDefaults] objectForKey:@"showConnectedDurations"]
             && [cState isEqualToString: @"CONNECTED"]    ) {
            NSDate * csd = [myConnection connectedSinceDate];
            NSTimeInterval ti = [csd timeIntervalSinceNow];
            long cTimeL = (long) round(-ti);
            if ( cTimeL >= 0 ) {
                if ( cTimeL < 3600 ) {
                    cTimeS = [NSString stringWithFormat:@" %li:%02li", cTimeL/60, cTimeL%60];
                } else {
                    cTimeS = [NSString stringWithFormat:@" %li:%02li:%02li", cTimeL/3600, (cTimeL/60) % 60, cTimeL%60];
                }
            }
        }
		NSString *label = [NSString stringWithFormat:@"%@ (%@%@)",[myConnection configName], NSLocalizedString(cState, nil), cTimeS];
		[[tabView tabViewItemAtIndex:i] setLabel:label];
		i++;
	}
}


- (void) updateUI
{
	unsigned connectionNumber = [connectionArray count];
	NSString *myState;
	if(connectionNumber == 1) {
		myState = NSLocalizedString(@"Tunnelblick: 1 connection active.", nil);
	} else {
		myState = [NSString stringWithFormat:NSLocalizedString(@"Tunnelblick: %d connections active.", nil),connectionNumber];
	}
	
    [statusMenuItem setTitle: myState];
    [theItem setToolTip: myState];
	
	if( (![lastState isEqualToString:@"EXITING"]) && (![lastState isEqualToString:@"CONNECTED"]) ) { 
		// override while in transitional state
		// Any other state shows "transitional" image:
		//[theItem setImage: transitionalImage];
		if (![theAnim isAnimating])
		{
			//NSLog(@"Starting Animation");
			[theAnim startAnimation];
		}
	} else
	{
        //we have a new connection, or error, so stop animating and show the correct icon
		if ([theAnim isAnimating])
		{
			[theAnim stopAnimation];
		}
        
        if (connectionNumber > 0 ) {
            [theItem setImage: connectedImage];
        } else {
            [theItem setImage: mainImage];
        }
	}
}

- (void)animationDidEnd:(NSAnimation*)animation
{
	if ((![lastState isEqualToString:@"EXITING"]) && (![lastState isEqualToString:@"CONNECTED"]))
	{
		// NSLog(@"Starting Animation (2)");
		[theAnim startAnimation];
	}
}

- (void)animation:(NSAnimation *)animation didReachProgressMark:(NSAnimationProgress)progress
{
	if (animation == theAnim)
	{
        [theItem performSelectorOnMainThread:@selector(setImage:) withObject:[animImages objectAtIndex:lround(progress * [animImages count]) - 1] waitUntilDone:YES];
	}
}

- (void) tabView: (NSTabView*) inTabView willSelectTabViewItem: (NSTabViewItem*) tabViewItem
{
    NSView* view = [[inTabView selectedTabViewItem] view];
    [tabViewItem setView: view];
    [[[self selectedLogView] textStorage] setDelegate: nil];
}

- (void) tabView: (NSTabView*) inTabView didSelectTabViewItem: (NSTabViewItem*) tabViewItem
{
    VPNConnection* newConnection = [self selectedConnection];
    NSTextView* logView = [self selectedLogView];
    [[logView layoutManager] replaceTextStorage: [newConnection logStorage]];
    //[logView setSelectedRange: NSMakeRange([[logView textStorage] length],[[logView textStorage] length])];
	[logView scrollRangeToVisible: NSMakeRange([[logView string] length]-1, 0)];
	
    [[logView textStorage] setDelegate: self];
	
    [self validateLogButtons];
}
- (void) textStorageDidProcessEditing: (NSNotification*) aNotification
{
    NSNotification *notification = [NSNotification notificationWithName: @"LogDidChange" 
                                                                 object: [self selectedLogView]];
    [[NSNotificationQueue defaultQueue] enqueueNotification: notification 
                                               postingStyle: NSPostWhenIdle
                                               coalesceMask: NSNotificationCoalescingOnName | NSNotificationCoalescingOnSender 
                                                   forModes: nil];
}

- (void) logNeedsScrolling: (NSNotification*) aNotification
{
    NSTextView* textView = [aNotification object];
    [textView scrollRangeToVisible: NSMakeRange([[textView string] length]-1, 0)];
}

- (NSTextView*) selectedLogView
{
    NSTextView* result = [[[[[tabView selectedTabViewItem] view] subviews] lastObject] documentView];
    return result;
}

- (IBAction) clearLog: (id) sender
{
	NSCalendarDate* date = [NSCalendarDate date];
	NSString *dateText = [NSString stringWithFormat:@"%@ %@; %@\n",
                          [date descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S"],
                          tunnelblickVersion(),
                          openVPNVersion()
                         ];
	[[self selectedLogView] setString: [[[NSString alloc] initWithString: dateText] autorelease]];
}

- (VPNConnection*) selectedConnection
	/*" Returns the connection associated with the currently selected log tab or nil on error. "*/
{
	if (![tabView selectedTabViewItem]) {
		[tabView selectFirstTabViewItem: nil];
	}
	
    NSString* configPath = [[tabView selectedTabViewItem] identifier];
	VPNConnection* connection = [myVPNConnectionDictionary objectForKey:configPath];
	NSArray *allConnections = [myVPNConnectionDictionary allValues];
	if(connection) return connection;
	else if([allConnections count]) return [allConnections objectAtIndex:0] ; 
	else return nil;
}


- (IBAction)connect:(id)sender
{
    if (  ! [[NSUserDefaults standardUserDefaults] boolForKey:@"skipWarningAboutSimultaneousConnections"]  ) {
        // Count the total number of connections and what their "Set nameserver" status was at the time of connection
        int numConnections = 1;
        int numConnectionsWithSetNameserver = 0;
        if (  useDNSStatus([self selectedConnection])  ) {
            numConnectionsWithSetNameserver = 1;
        }
        VPNConnection * connection;
        NSEnumerator* e = [myVPNConnectionDictionary objectEnumerator];
        while (connection = [e nextObject]) {
            if (  ! [[connection state] isEqualToString:@"EXITING"]  ) {
                numConnections++;
                if (  [connection usedSetNameserver]  ) {
                    numConnectionsWithSetNameserver++;
                }
            }
        }
    
        if (  numConnections != 1  ) {
            // Dictionary for the panel -- can't use NSPanel because the Tiger version of NSPanel doesn't support "Don't show this message again" checkbox
            NSMutableDictionary* dict = [NSMutableDictionary dictionary];
            NSString *question = [NSString stringWithFormat:NSLocalizedString(@"Multiple simultaneous connections would be created (%d with 'Set nameserver', %d without 'Set nameserver').", nil), numConnectionsWithSetNameserver, (numConnections-numConnectionsWithSetNameserver) ];
            [dict setObject:NSLocalizedString(@"Do you wish to connect?", nil) forKey:(NSString *)kCFUserNotificationAlertHeaderKey];
            [dict setObject:question forKey:(NSString *)kCFUserNotificationAlertMessageKey];
            [dict setObject:NSLocalizedString(@"Do not warn about this again", nil) forKey:(NSString *)kCFUserNotificationCheckBoxTitlesKey];
            [dict setObject:NSLocalizedString(@"Connect", nil) forKey:(NSString *)kCFUserNotificationDefaultButtonTitleKey];
            [dict setObject:NSLocalizedString(@"Cancel", nil) forKey:(NSString *)kCFUserNotificationAlternateButtonTitleKey];
            SInt32 error;
            CFUserNotificationRef notification = CFUserNotificationCreate(NULL, 30, CFUserNotificationSecureTextField(0), &error, (CFDictionaryRef)dict);
            CFOptionFlags response;
            // If we couldn't receive a response, don't connect
            if((error) || (CFUserNotificationReceiveResponse(notification, 0, &response))) {
                return;
            }
            // If user clicked Cancel, don't connect
            if((response & 0x3) != kCFUserNotificationDefaultResponse) {
                return;
            }
            // If user checked the "Do not warn... again" checbox, set a preference
            if((response & CFUserNotificationCheckBoxChecked(0))) {
                [[NSUserDefaults standardUserDefaults] setBool:TRUE forKey:@"skipWarningAboutSimultaneousConnections"];
                [[NSUserDefaults standardUserDefaults] synchronize];
            }
        }
    }
    
    [[self selectedConnection] connect: sender]; 
}

- (IBAction)disconnect:(id)sender
{
    [[self selectedConnection] disconnect: sender];      
}


- (IBAction) openLogWindow: (id) sender
{
    if (logWindow != nil) {
        [logWindow makeKeyAndOrderFront: self];
        [NSApp activateIgnoringOtherApps:YES];
        return;
    }
    
    [NSBundle loadNibNamed: @"LogWindow" owner: self]; // also sets tabView etc.

    // Set the window's size and position from preferences (saved when window is closed)
    // But only if the preference's version matches the TB version (since window size could be different in different versions of TB)
    NSString * tbVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    id tmp = [[NSUserDefaults standardUserDefaults] objectForKey:@"detailsWindowFrameVersion"];
    if (tmp != nil) {
        if (  [tbVersion isEqualToString: [[NSUserDefaults standardUserDefaults] stringForKey:@"detailsWindowFrameVersion"]]    ) {
            tmp = [[NSUserDefaults standardUserDefaults] objectForKey:@"detailsWindowFrame"];
            if(tmp != nil) {
                NSString * frame = [[NSUserDefaults standardUserDefaults] stringForKey:@"detailsWindowFrame"];
                [logWindow setFrameFromString:frame];
            }
        }
    }

	[logWindow setDelegate:self];
	VPNConnection *myConnection = [self selectedConnection];
	NSTextStorage* store = [myConnection logStorage];
	[[[self selectedLogView] layoutManager] replaceTextStorage: store];
	
	NSEnumerator* e = [[[myVPNConnectionDictionary allKeys] sortedArrayUsingSelector: @selector(compare:)] objectEnumerator];
	//id test = [[myVPNConnectionDictionary allKeys] sortedArrayUsingSelector: @selector(compare:)];
	NSTabViewItem* initialItem;
	VPNConnection* connection = [myVPNConnectionDictionary objectForKey: [e nextObject]];
	if (connection) {
		initialItem = [tabView tabViewItemAtIndex: 0];
		[initialItem setIdentifier: [connection configPath]];
		[initialItem setLabel: [connection configName]];
		
		int curTabIndex = 0;
		[tabView selectTabViewItemAtIndex:0];
		BOOL haveOpenConnection = ! [connection isDisconnected];
		while (connection = [myVPNConnectionDictionary objectForKey: [e nextObject]]) {
			NSTabViewItem* newItem = [[NSTabViewItem alloc] init];
			[newItem setIdentifier: [connection configPath]];
			[newItem setLabel: [connection configName]];
			[tabView addTabViewItem: newItem];
			++curTabIndex;
			if (  ( ! haveOpenConnection ) && ( ! [connection isDisconnected] )  ) {
				[tabView selectTabViewItemAtIndex:curTabIndex];
				haveOpenConnection = YES;
			}
		}
	}
	[self tabView:tabView didSelectTabViewItem:initialItem];
	[self validateLogButtons];
	[self updateTabLabels];
    
    // Set up a timer to update the tab labels with connections' duration times
    if (    (showDurationsTimer == nil)  && [[NSUserDefaults standardUserDefaults] objectForKey:@"showConnectedDurations"]    ) {
        showDurationsTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0
                                                               target:self
                                                             selector:@selector(updateTabLabels)
                                                             userInfo:nil
                                                              repeats:YES] retain];
    }
	
	// Localize buttons and checkboxes
    [self localizeControl:clearButton            shiftRight:editButton       shiftLeft:nil               shiftSelfLeft:NO ];
    [self localizeControl:editButton             shiftRight:nil              shiftLeft:nil               shiftSelfLeft:NO ];
    [self localizeControl:connectButton          shiftRight:nil              shiftLeft:disconnectButton  shiftSelfLeft:YES];
    [self localizeControl:disconnectButton       shiftRight:nil              shiftLeft:nil               shiftSelfLeft:YES];
    [self localizeControl:useNameserverCheckbox  shiftRight:nil              shiftLeft:nil               shiftSelfLeft:NO ];
    [self localizeControl:autoLaunchCheckbox     shiftRight:nil              shiftLeft:nil               shiftSelfLeft:NO ];

    [logWindow makeKeyAndOrderFront: self];
    [NSApp activateIgnoringOtherApps:YES];
    logWindowIsOpen = TRUE;
}

// Localizes a control, optionally shifting the origin of the control itself to the left, and the origin of other controls to the left or right to accomodate any change in width.
- (void)localizeControl:(NSButton*) button shiftRight:(NSButton*) buttonToRight shiftLeft:(NSButton* ) buttonToLeft shiftSelfLeft:(BOOL)shiftSelfLeft
{
    NSRect oldRect = [button frame];
	[button setTitle:NSLocalizedString([button title], nil)];
    [button sizeToFit];
    NSRect newRect = [button frame];
    float widthChange = newRect.size.width - oldRect.size.width;
    if (shiftSelfLeft) {
        NSRect oldPos = [button frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [button setFrame:oldPos];
    }
    if (buttonToRight) {
        NSRect oldPos = [buttonToRight frame];
        oldPos.origin.x = oldPos.origin.x + widthChange;
        [buttonToRight setFrame:oldPos];
    }
    if (buttonToLeft) {
        NSRect oldPos = [buttonToLeft frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [buttonToLeft setFrame:oldPos];
    }
}


// Invoked when the Details... window (logWindow) will close
- (void)windowWillClose:(NSNotification *)n
{
    if ( [n object] == logWindow ) {
        // Stop and release the timer used to update the duration displays
        if (showDurationsTimer != nil) {
            [showDurationsTimer invalidate];
            [showDurationsTimer release];
            showDurationsTimer = nil;
        }

        // Save the window's size and position in the preferences and save the TB version that saved them, BUT ONLY IF anything has changed
        NSString * frame = [logWindow stringWithSavedFrame];
        NSString * tbVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
        BOOL saveIt = TRUE;
        id tmp = [[NSUserDefaults standardUserDefaults] objectForKey:@"detailsWindowFrame"];
        if(tmp != nil) {
            tmp = [[NSUserDefaults standardUserDefaults] objectForKey:@"detailsWindowFrameVersion"];
            if (tmp != nil) {
                if (  [tbVersion isEqualToString: [[NSUserDefaults standardUserDefaults] stringForKey:@"detailsWindowFrameVersion"]]    ) {
                    if (   [frame isEqualToString: [[NSUserDefaults standardUserDefaults] stringForKey:@"detailsWindowFrame"]]    ) {
                        saveIt = FALSE;
                    }
                }
            }
        }

        if (saveIt) {
            [[NSUserDefaults standardUserDefaults] setObject: frame forKey: @"detailsWindowFrame"];
            [[NSUserDefaults standardUserDefaults] setObject: [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]
                                                      forKey: @"detailsWindowFrameVersion"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        logWindowIsOpen = FALSE;
    }
}


- (IBAction) openAboutWindow: (id) sender
// Uses the "...WithOptions" version of orderFrontStandardAboutPanel so all localization can be in Localizable.strings files
{
    NSImage  * appIcon      = [NSImage imageNamed:@"tunnelblick.icns"];
    NSString * appName      = @"Tunnelblick";
    NSString * appVersion   = tunnelblickVersion();
    NSString * version      = @"";
    NSString * html         = [NSString stringWithFormat:@"%@%@%@",
                               @"<html><body><center><div style=\"font-family: Verdana, Arial, Helvetica, sans-serif; font-size: 10px\">",
                               openVPNVersion(),
                               @"</div><br><br><a href=\"http://code.google.com/p/tunnelblick\">http://code.google.com/p/tunnelblick</a></center><body></html>"];
    NSData * data = [html dataUsingEncoding:NSASCIIStringEncoding];
    NSMutableAttributedString * credits = [[[NSAttributedString alloc] init] autorelease];
    [credits initWithHTML:data documentAttributes:NULL];

    NSString * copyright    = NSLocalizedString(@"Copyright © 2004-2009 by Angelo Laub and others. All rights reserved.", nil);

    NSDictionary * aboutPanelDict;
    aboutPanelDict = [NSDictionary dictionaryWithObjectsAndKeys:
                      appIcon, @"ApplicationIcon",
                      appName, @"ApplicationName",
                      appVersion, @"ApplicationVersion",
                      version, @"Version",
                      credits, @"Credits",
                      copyright, @"Copyright",
                      nil];
                    
    [NSApp orderFrontStandardAboutPanelWithOptions:aboutPanelDict];
    [NSApp activateIgnoringOtherApps:YES];                          // Force About window to front (if it already exists and is covered by another window)
}
- (void) dealloc
{
    [animImages release];
    [connectedImage release];
    [mainImage release];

    [aboutItem release];
    [connectionArray release];
    [connectionsToRestore release];
    [detailsItem release];
    [lastState release];
    [myConfigArray release];
    [myVPNConnectionDictionary release];
    [myVPNMenu release];
    [quitItem release];
    [showDurationsTimer release];
    [statusMenuItem release];
    [theAnim release];
    [theItem release]; 
    [updater release];
    [userDefaults release];

    [super dealloc];
}


-(void)killAllConnections
{
	id connection;
    NSEnumerator* e = [connectionArray objectEnumerator];
    
    while (connection = [e nextObject]) {
        [connection disconnect:self];
		if(NSDebugEnabled) NSLog(@"Killing connection.\n");
    }
}

-(void)killAllOpenVPN 
{
	NSString* path = [[NSBundle mainBundle] pathForResource: @"openvpnstart" 
													 ofType: nil];
	NSTask* task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath: path]; 
	
	NSArray *arguments = [NSArray arrayWithObjects:@"killall", nil];
	[task setArguments:arguments];
	[task launch];
	[task waitUntilExit];
}

-(void)resetActiveConnections {
	VPNConnection *connection;
	NSEnumerator* e = [connectionArray objectEnumerator];
	
	while (connection = [e nextObject]) {
		if (NSDebugEnabled) NSLog(@"Connection %@ is connected for %f seconds\n",[connection configName],[[connection connectedSinceDate] timeIntervalSinceNow]);
		if ([[connection connectedSinceDate] timeIntervalSinceNow] < -5) {
			if (NSDebugEnabled) NSLog(@"Resetting connection: %@\n",[connection configName]);
			[connection disconnect:self];
			[connection connect:self];
		}
		else {
			if (NSDebugEnabled) NSLog(@"Not Resetting connection: %@\n, waiting...",[connection configName]);
		}
	}
}

-(void)createDefaultConfig 
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *directoryPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/openvpn"];
	NSString *confResource = [[NSBundle mainBundle] pathForResource: @"openvpn" 
															 ofType: @"conf"];
	
	if([[self getConfigs] count] == 0) { // if there are no config files, create a default one
		[NSApp activateIgnoringOtherApps:YES];
        if(NSRunCriticalAlertPanel(NSLocalizedString(@"Welcome to Tunnelblick on Mac OS X: Please put your configuration file (e.g. openvpn.conf) in '~/Library/openvpn/'.", nil),
                                   NSLocalizedString(@"You can also continue and Tunnelblick will create an example configuration file at the right place that you can customize or replace.", nil),
                                   NSLocalizedString(@"Quit", nil),
                                   NSLocalizedString(@"Continue", nil),
                                   nil) == NSAlertDefaultReturn) {
            exit (1);
        }
        else {
			[fileManager createDirectoryAtPath:directoryPath attributes:nil];
			[fileManager copyPath:confResource toPath:[directoryPath stringByAppendingPathComponent:@"/openvpn.conf"] handler:nil];
            [self editConfig:self];
        }
		
		
	}
}

-(IBAction)editConfig:(id)sender
{
	VPNConnection *connection = [self selectedConnection];
    NSString *directoryPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/openvpn"];
	NSString *configPath = [connection configPath];
    if(configPath == nil) configPath = @"/openvpn.conf";
	
	//	NSString *openvpnstart = @"/usr/sbin/chown";
	//	NSString *userString = [NSString stringWithFormat:@"%d",getuid()];
	//	NSArray *arguments = [NSArray arrayWithObjects:userString,configPath,nil];
	//	AuthorizationRef authRef = [NSApplication getAuthorizationRef];
	//	[NSApplication executeAuthorized:openvpnstart withArguments:arguments withAuthorizationRef:authRef];
	//	AuthorizationFree(authRef,kAuthorizationFlagDefaults);
	
    [[NSWorkspace sharedWorkspace] openFile:[directoryPath stringByAppendingPathComponent:configPath] withApplication:@"TextEdit"];
}


- (void) networkConfigurationDidChange
{
	if (NSDebugEnabled) NSLog(@"Got networkConfigurationDidChange notification!!");
	[self resetActiveConnections];
}

- (void) applicationWillTerminate: (NSNotification*) notification 
{	
    if (NSDebugEnabled) NSLog(@"App will terminate...\n");
	[self cleanup];
}

-(void)cleanup 
{
	[NSApp callDelegateOnNetworkChange: NO];
	[self killAllConnections];
	[self killAllOpenVPN];
	[[NSStatusBar systemStatusBar] removeStatusItem:theItem];
}

-(void)saveUseNameserverCheckboxState:(BOOL)inBool
{
	VPNConnection* connection = [self selectedConnection];
	if(connection != nil) {
		NSString* key = [[connection configName] stringByAppendingString: @"useDNS"];
		[[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithBool: inBool] forKey: key];
		[[NSUserDefaults standardUserDefaults] synchronize];
	}
	
}
-(void)saveAutoLaunchCheckboxState:(BOOL)inBool
{
	VPNConnection* connection = [self selectedConnection];
	if(connection != nil) {
		NSString* autoConnectKey = [[connection configName] stringByAppendingString: @"autoConnect"];
		[[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithBool: inBool] forKey: autoConnectKey];
		[[NSUserDefaults standardUserDefaults] synchronize];
	}
	
}

-(BOOL)getCurrentAutoLaunchSetting
{
	VPNConnection *connection = [self selectedConnection];
	NSString *autoConnectKey = [[connection configName] stringByAppendingString:@"autoConnect"];
	return [[NSUserDefaults standardUserDefaults] boolForKey:autoConnectKey];
}

- (void) setState: (NSString*) newState
	// Be sure to call this in main thread only
{
    [newState retain];
    [lastState release];
    lastState = newState;
    //[self updateUI];
	[self performSelectorOnMainThread:@selector(updateUI) withObject:nil waitUntilDone:NO];
}

-(void)addConnection:(id)sender 
{
	if(sender != nil) {
		[connectionArray removeObject:sender];
		[connectionArray addObject:sender];
	}
}

-(void)removeConnection:(id)sender
{
	if(sender != nil) [connectionArray removeObject:sender];	
}

static void signal_handler(int signalNumber)
{
    printf("signal %d caught!\n",signalNumber);
    
    if (signalNumber == SIGHUP) {
        printf("SIGHUP received. Restarting active connections...\n");
        [[NSApp delegate] resetActiveConnections];
    } else  {
        printf("Received fatal signal. Cleaning up...\n");
        [[NSApp delegate] cleanup];
        exit(0);	
    }
}


- (void) installSignalHandler
{
    struct sigaction action;
    
    action.sa_handler = signal_handler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    
    if (sigaction(SIGHUP, &action, NULL) || 
        sigaction(SIGQUIT, &action, NULL) || 
        sigaction(SIGTERM, &action, NULL) ||
        sigaction(SIGBUS, &action, NULL) ||
        sigaction(SIGSEGV, &action, NULL) ||
        sigaction(SIGPIPE, &action, NULL)) {
        NSLog(@"Warning: setting signal handler failed: %s", strerror(errno));
    }	
}
- (void) applicationDidFinishLaunching: (NSNotification *)notification
{
	[NSApp callDelegateOnNetworkChange: NO];
    [self installSignalHandler];    
    [NSApp setAutoLaunchOnLogin: YES];
    [self activateStatusMenu];
	[updater checkForUpdatesInBackground];
}

-(void) dmgCheck
{
	NSString *path = [[NSBundle mainBundle] bundlePath];
	if([path hasPrefix:@"/Volumes/Tunnelblick"]) {
		NSPanel *panel = NSGetAlertPanel(NSLocalizedString(@"You're trying to launch Tunnelblick from the disk image", nil),NSLocalizedString(@"Please copy Tunnelblick.app to your Harddisk before launching it.", nil),NSLocalizedString(@"Cancel", nil),nil,nil);
		[panel setLevel:NSStatusWindowLevel];
		[panel makeKeyAndOrderFront:nil];
		[NSApp runModalForWindow:panel];
		exit(2);
	}
}

-(void)moveSoftwareUpdateWindowToForeground
{
    NSArray *windows = [NSApp windows];
    NSEnumerator *e = [windows objectEnumerator];
    NSWindow *window = nil;
    while(window = [e nextObject]) {
    	if (  [[window title] isEqualToString:@"Software Update"]  ) {
            [window setLevel:NSStatusWindowLevel];
        }
    }
}

-(void) fileSystemHasChanged: (NSNotification*) n
{
	if(NSDebugEnabled) NSLog(@"FileSystem has changed.");
	[self performSelectorOnMainThread: @selector(activateStatusMenu) withObject: nil waitUntilDone: YES];
}
-(void) watcher: (UKKQueue*) kq receivedNotification: (NSString*) nm forPath: (NSString*) fpath {
	
	[self fileSystemHasChanged: nil];
}

-(BOOL)repairPermissions
{
	NSBundle *thisBundle = [NSBundle mainBundle];
	NSString *installer = [thisBundle pathForResource:@"installer" ofType:nil];
	
	AuthorizationRef authRef= [NSApplication getAuthorizationRef];
	
	if(authRef == nil)
		return FALSE;
	
    int i = 5;
	while(  needsRepair()  && (i-- > 0)  ) {
		NSLog(@"Repairing Application...\n");
		[NSApplication executeAuthorized:installer withArguments:nil withAuthorizationRef:authRef];
		sleep(1);
	}
	AuthorizationFree(authRef, kAuthorizationFlagDefaults);

    if ( needsRepair()  ) {
        NSLog(@"Unable to repair ownership and/or permissions or set uid bit in five attempts");
        return FALSE;
    }
    
	return TRUE;
}




BOOL needsRepair() 
{
	NSBundle *thisBundle = [NSBundle mainBundle];
	
	NSString *openvpnstartPath = [thisBundle pathForResource:@"openvpnstart"       ofType:nil];
	NSString *openvpnPath      = [thisBundle pathForResource:@"openvpn"            ofType:nil];
	NSString *leasewatchPath   = [thisBundle pathForResource:@"leasewatch"         ofType:nil];
	NSString *clientUpPath     = [thisBundle pathForResource:@"client.up.osx.sh"   ofType:nil];
	NSString *clientDownPath   = [thisBundle pathForResource:@"client.down.osx.sh" ofType:nil];
	
	// check openvpnstart owned by root, set uid, owner may execute
	const char *path = [openvpnstartPath UTF8String];
    struct stat sb;
	if(stat(path,&sb)) runUnrecoverableErrorPanel();
	
	if (!(			  (sb.st_mode & S_ISUID) // set uid bit is set
					  && (sb.st_mode & S_IXUSR) // owner may execute it
					  && (sb.st_uid == 0) // is owned by root
					  )) {
		NSLog(@"openvpnstart has missing set uid bit, is not owned by root, or owner can't execute it");
		return YES;		
	}
	
	// check files which should be only writable by root
	NSArray *inaccessibleObjects = [NSArray arrayWithObjects:openvpnPath, leasewatchPath, clientUpPath, clientDownPath, nil];
	NSEnumerator *e = [inaccessibleObjects objectEnumerator];
	NSString *currentPath;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	while(currentPath = [e nextObject]) {
		NSDictionary *fileAttributes = [fileManager fileAttributesAtPath:currentPath traverseLink:YES];
		unsigned long perms = [fileAttributes filePosixPermissions];
		NSString *octalString = [NSString stringWithFormat:@"%o",perms];
		NSNumber *fileOwner = [fileAttributes fileOwnerAccountID];
		
		if ( (![octalString isEqualToString:@"744"])  || (![fileOwner isEqualToNumber:[NSNumber numberWithInt:0]])) {
			NSLog(@"File %@ has permissions: %@, is owned by %@ and needs repair...\n",currentPath,octalString,fileOwner);
			return YES;
		}
	}
	
	return NO;
}

-(void)willGoToSleep
{
	if(NSDebugEnabled) NSLog(@"Computer will go to sleep...\n");
	connectionsToRestore = [connectionArray mutableCopy];
	[self killAllConnections];
}
-(void)wokeUpFromSleep 
{
	if(NSDebugEnabled) NSLog(@"Computer just woke up from sleep...\n");
	
	NSEnumerator *e = [connectionsToRestore objectEnumerator];
	VPNConnection *connection;
	while(connection = [e nextObject]) {
		if(NSDebugEnabled) NSLog(@"Restoring Connection %@",[connection configName]);
		[connection connect:self];
	}
}
int runUnrecoverableErrorPanel(void) 
{
	NSPanel *panel = NSGetAlertPanel(NSLocalizedString(@"Tunnelblick Error", nil),
                                     NSLocalizedString(@"It seems like you need to reinstall Tunnelblick. Please move Tunnelblick to the Trash and download a fresh copy.", nil),
                                     NSLocalizedString(@"Download", nil),
                                     NSLocalizedString(@"Quit", nil),
                                     nil);
	[panel setLevel:NSStatusWindowLevel];
	[panel makeKeyAndOrderFront:nil];
	if( [NSApp runModalForWindow:panel] != NSAlertDefaultReturn ) {
		exit(2);
	} else {
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://tunnelblick.net/"]];
		exit(2);
	}
}

-(IBAction) autoLaunchPrefButtonWasClicked: (id) sender
{
	if([sender state]) {
		[self saveAutoLaunchCheckboxState:TRUE];
	} else {
		[self saveAutoLaunchCheckboxState:FALSE];
	}
}

-(IBAction) nameserverPrefButtonWasClicked: (id) sender
{
	if([sender state]) {
		[self saveUseNameserverCheckboxState:TRUE];
	} else {
		[self saveUseNameserverCheckboxState:FALSE];
	}
}

@end
