/*
 * Copyright (c) 2004 Angelo Laub
 * Contributions by Dirk Theisen <dirk@objectpark.org>, 
 *                  Jens Ohlig, 
 *                  Waldemar Brodkorb
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
#import "NSApplication+NetworkNotifications.h"
#import "helper.h"


#define NSAppKitVersionNumber10_0 577
#define NSAppKitVersionNumber10_1 620
#define NSAppKitVersionNumber10_2 663
#define NSAppKitVersionNumber10_3 743



BOOL systemIsTigerOrNewer()
{
    return (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_3) ;
}

@interface NSStatusBar (NSStatusBar_Private)
- (id)_statusItemWithLength:(float)l withPriority:(int)p;
@end


@implementation MenuController

- (void) createStatusItem
{
	NSStatusBar *bar = [NSStatusBar systemStatusBar];
	int priority = INT32_MAX;
	if (systemIsTigerOrNewer()) {
		priority = MIN(priority, 2147483646); // found by experimenting - dirk
	}
	
	if (!theItem) {
		theItem = [[bar _statusItemWithLength: NSVariableStatusItemLength withPriority: priority] retain];
		//theItem = [[bar _statusItemWithLength: NSVariableStatusItemLength withPriority: 0] retain];
	}
	// Dirk: For Tiger and up, re-insert item to place it correctly.
	if ([bar respondsToSelector: @selector(_insertStatusItem:withPriority:)]) {
		[bar removeStatusItem: theItem];
		[bar _insertStatusItem: theItem withPriority: priority];
	}	
}

-(id) init
{	
    if (self = [super init]) {
        [self dmgCheck];
		
        errorImage = [[NSImage imageNamed: @"error.tif"] retain];
        mainImage = [[NSImage imageNamed: @"00_closed.tif"] retain];
        connectedImage = [[NSImage imageNamed: @"connected.png"] retain];
        
		
		transitionalImage1 = [[NSImage imageNamed: @"01.tif"] retain];
		transitionalImage2 = [[NSImage imageNamed: @"02.tif"] retain];
		transitionalImage3 = [[NSImage imageNamed: @"03.tif"] retain];
		[NSApp setDelegate:self];
		
        myVPNConnectionDictionary = [[NSMutableDictionary alloc] init];
        myVPNConnectionArray = [[[NSMutableArray alloc] init] retain];
        userDefaults = [[NSMutableDictionary alloc] init];
        
        connectionArray = [[[NSMutableArray alloc] init] retain];
        appDefaults = [NSUserDefaults standardUserDefaults];
        [appDefaults registerDefaults:userDefaults];
		
		
		detailsItem = [[NSMenuItem alloc] init];
		[detailsItem setTitle: @"Details..."];
		[detailsItem setTarget: self];
		[detailsItem setAction: @selector(openLogWindow:)];
		
		quitItem = [[NSMenuItem alloc] init];
		[quitItem setTitle: @"Quit"]; 
		[quitItem setTarget: self];
		[quitItem setAction: @selector(quit:)];
        
		[self createStatusItem];
		
		[self updateMenu];
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
		
		UKKQueue* myQueue = [UKKQueue sharedQueue];
		[myQueue addPathToQueue: vpnDirectory];
		[myQueue setDelegate: self];
		[myQueue setAlwaysNotify: YES];
		

		[NSThread detachNewThreadSelector:@selector(moveAllWindowsToForegroundThread) toTarget:self withObject:nil];

		
		updater = [[SUUpdater alloc] init];


	}
    return self;
}

-(void)moveAllWindowsToForegroundThread {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	sleep(3);
	[self moveAllWindowsToForeground];
//	[NSTimer scheduledTimerWithTimeInterval: 1.0 target: self selector: @selector(moveAllWindowsToForeground) userInfo: nil repeats: YES];
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

- (void) initialiseAnim
{
	NSAnimationProgress progMarks[] = {
		1.0/8.0, 2.0/8.0, 3.0/8.0, 4.0/8.0, 5.0/8.0, 6.0/8.0, 7.0/8.0, 8.0/8.0
	};
	
	int i, count = 8;
	// theAnim is an NSAnimation instance variable
	theAnim = [[NSAnimation alloc] initWithDuration:2.0
									 animationCurve:NSAnimationLinear];
	[theAnim setFrameRate:8.0];
	[theAnim setDelegate:self];
	
	for (i=0; i<count; i++)
		[theAnim addProgressMark:progMarks[i]];
	
	[theAnim setAnimationBlockingMode:  NSAnimationNonblocking];
}

-(void) updateMenu 
{	
    [theItem setHighlightMode:YES];
    [theItem setMenu:nil];
	[myVPNMenu dealloc]; myVPNMenu = nil;
	[[myVPNConnectionDictionary allValues] makeObjectsPerformSelector:@selector(disconnect:) withObject:self];
	[myVPNConnectionDictionary removeAllObjects];
	
	myVPNMenu = [[NSMenu alloc] init];
    [myVPNMenu setDelegate:self];
    
	[theItem setMenu: myVPNMenu];
	
	statusMenuItem = [[NSMenuItem alloc] init];
	[myVPNMenu addItem:statusMenuItem];
	[myVPNMenu addItem:[NSMenuItem separatorItem]];

	[myConfigArray release];
    myConfigArray = [[[self getConfigs] sortedArrayUsingSelector:@selector(compare:)] retain];
    [myConfigModDatesArray release];
    myConfigModDatesArray = [[self getModDates:myConfigArray] retain];
    
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
	[myVPNMenu addItem: quitItem];
    
    // Localize all menu items:
    NSMenuItem *item;
    NSEnumerator *e = [[myVPNMenu itemArray] objectEnumerator];
    
    while (item = [e nextObject]) 
    {
        [item setTitle:local([item title])];
    }
}

- (void)activateStatusMenu
{
	//[theItem retain];
    [self updateUI];
    
	// If any config files were changed/added/deleted, update the menu
    // We don't do it UNLESS files were changed/added/deleted because all connections are reset when the menu is updated.
    // activateStatusMenu is called whenever anything changes in the config directory, even the file-accessed date,
    // so a backup of the directory, for example, would cause disconnects if we always updated the menu.
    NSArray * curConfigsArray = [[self getConfigs] sortedArrayUsingSelector:@selector(compare:)];
    NSArray * curModDatesArray = [self getModDates:curConfigsArray];
    
    if ( ! (   [myConfigArray isEqualToArray:curConfigsArray]
            && [myConfigModDatesArray isEqualToArray:curModDatesArray]  )  ) {
        NSLog(@"One or more configuration files were changed, added, or deleted. All connections will be closed.\n");
        [self updateMenu];
    }
}

- (void)connectionStateDidChange:(id)connection
{
	[self updateTabLabels];
    if (connection == [self selectedConnection]) 
	{
		[self validateLogButtons];
	}	
}


-(NSArray *)getConfigs {
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

// Returns an array of modification date strings
// Each entry in the array is the modification date of the file in the corresponding entry in fileArray
-(NSArray *)getModDates:(NSArray *)fileArray {
    int i;
    NSMutableArray *array = [[[NSMutableArray alloc] init] autorelease];
    NSString *file;
    NSString *cfgDirSlash = [NSHomeDirectory() stringByAppendingString: @"/Library/openvpn/"];
    NSString *filePath;
    NSDate *modDate;
    NSString *modDateS;
	NSFileManager *fileManager = [NSFileManager defaultManager];
    for (i=0; i<[fileArray count]; i++) {
		file = [fileArray objectAtIndex:i];
        filePath = [cfgDirSlash stringByAppendingString:file];
        modDate = [[fileManager fileAttributesAtPath:filePath traverseLink:YES] fileModificationDate];
        if (modDate == nil) {
            modDateS = @"";
        } else if (   (modDateS = [modDate description]) == nil  )  {
            modDateS = @"";
        }
        [array insertObject:modDateS atIndex:i];
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
		NSString *label = [NSString stringWithFormat:@"%@ (%@)",[myConnection configName],local([myConnection state])];
		[[tabView tabViewItemAtIndex:i] setLabel:label];
		i++;
	}
}


- (void) updateUI
{
	unsigned connectionNumber = [connectionArray count];
	NSString *myState;
	if(connectionNumber == 1) {
		myState = local(@"OpenVPN: 1 connection active.");
	} else {
		myState = [NSString stringWithFormat:local(@"OpenVPN: %d connections active."),connectionNumber];
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
		if ([theAnim isAnimating])
		{
			[theAnim stopAnimation];
		}
	}
	if (connectionNumber > 0 ) {
		[theItem setImage: connectedImage];
	} else {
		[theItem setImage: mainImage];
	} 
}

- (void)animationDidEnd:(NSAnimation*)animation
{
	if ((![lastState isEqualToString:@"EXITING"]) && (![lastState isEqualToString:@"CONNECTED"]))
	{
		// NSLog(@"Starting Animation (2)");
		[theAnim startAnimation];
	}
	if ([connectionArray count] > 0 ) {
        [theItem setImage: connectedImage];
    } else {
        [theItem setImage: mainImage];
    }
}

- (void)animation:(NSAnimation *)animation
            didReachProgressMark:(NSAnimationProgress)progress
{
	if (animation == theAnim)
	{
		// NSLog(@"progress is %f %i", progress, lround(progress * 8));
		// Do an effect appropriate to progress mark.
		switch(lround(progress * 8))
		{
			case 1:
				[theItem performSelectorOnMainThread:@selector(setImage:) withObject:mainImage waitUntilDone:YES];
				break;
				
			case 2:
				[theItem performSelectorOnMainThread:@selector(setImage:) withObject:transitionalImage1 waitUntilDone:YES];
				break;
				
			case 3:
				[theItem performSelectorOnMainThread:@selector(setImage:) withObject:transitionalImage2 waitUntilDone:YES];
				break;
				
			case 4:
				[theItem performSelectorOnMainThread:@selector(setImage:) withObject:transitionalImage3 waitUntilDone:YES];
				break;
				
			case 5:
				[theItem performSelectorOnMainThread:@selector(setImage:) withObject:connectedImage waitUntilDone:YES];
				break;
				
			case 6:
				[theItem performSelectorOnMainThread:@selector(setImage:) withObject:transitionalImage3 waitUntilDone:YES];
				break;
				
			case 7:
				[theItem performSelectorOnMainThread:@selector(setImage:) withObject:transitionalImage2 waitUntilDone:YES];
				break;
				
			case 8:
				[theItem performSelectorOnMainThread:@selector(setImage:) withObject:transitionalImage1 waitUntilDone:YES];
				break;
				
			default:
				NSLog(@"Unknown progress mark %f selected by Tunnelblick animation", progress);
		}
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
	NSString * versionInfo = [NSString stringWithFormat:@"Tunnelblick version %@",[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
	NSCalendarDate* date = [NSCalendarDate date];
	NSString *dateText = [NSString stringWithFormat:@"%@: %@\n",[date descriptionWithCalendarFormat:@"%a %m/%d/%y %I:%M %p"],versionInfo];
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
	[[self selectedConnection] connect: sender]; 
}

- (IBAction)disconnect:(id)sender
{
    [[self selectedConnection] disconnect: sender];      
}


- (IBAction) openLogWindow: (id) sender
{
	//	if (!logWindow) {
	//[logWindow close];
	[logWindow dealloc];
	[NSBundle loadNibNamed: @"LogWindow" owner: self]; // also sets tabView etc.
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
	
	// Localize Buttons
	[clearButton setTitle:local([clearButton title])];
	[editButton setTitle:local([editButton title])];
	[connectButton setTitle:local([connectButton title])];
	[disconnectButton setTitle:local([disconnectButton title])];
	[useNameserverCheckbox setTitle:local([useNameserverCheckbox title])];
	[autoLaunchCheckbox setTitle:local([autoLaunchCheckbox title])];

    [logWindow makeKeyAndOrderFront: self];
    [logWindow orderFrontRegardless];
	//[logWindow setLevel:NSStatusWindowLevel];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void) dealloc
{
    [lastState release];
    [theItem release];
    [myConfigArray release];
    
#warning todo: release non-IB ivars here!
    [statusMenuItem release];
    [myVPNMenu release];
    [userDefaults release];
    [appDefaults release];
    [theItem release]; 
    
    [mainImage release];
    [connectedImage release];
    [errorImage release];
    [transitionalImage release];
    [connectionArray release];
    
    
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
        if(NSRunCriticalAlertPanel(local(@"Welcome to OpenVPN on Mac OS X: Please put your config file (e.g. openvpn.conf) to '~/Library/openvpn/'."), local(@"You can also continue and Tunnelblick will create an example config at the right place that you can customize or replace."),local(@"Quit"),local(@"Continue"),nil) == NSAlertDefaultReturn) {
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
	
	//	NSString *helper = @"/usr/sbin/chown";
	//	NSString *userString = [NSString stringWithFormat:@"%d",getuid()];
	//	NSArray *arguments = [NSArray arrayWithObjects:userString,configPath,nil];
	//	AuthorizationRef authRef = [NSApplication getAuthorizationRef];
	//	[NSApplication executeAuthorized:helper withArguments:arguments withAuthorizationRef:authRef];
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
	if(needsRepair()){
		if ([self repairPermissions] != TRUE) {
			[NSApp terminate:self];
		}
	} 

	[updater checkForUpdatesInBackground];
}

-(void) dmgCheck
{
	NSString *path = [[NSBundle mainBundle] bundlePath];
	if([path hasPrefix:@"/Volumes/Tunnelblick"]) {
		NSPanel *panel = NSGetAlertPanel(local(@"You're trying to launch Tunnelblick from the disk image"),local(@"Please copy Tunnelblick.app to your Harddisk before launching it."),local(@"Okay"),nil,nil);
		[panel setLevel:NSStatusWindowLevel];
		[panel makeKeyAndOrderFront:nil];
		[NSApp runModalForWindow:panel];
		exit(2);
	}
}

-(void)moveAllWindowsToForeground
{
	NSArray *windows = [NSApp windows];
	NSEnumerator *e = [windows objectEnumerator];
	NSWindow *window = nil;
	while(window = [e nextObject]) {
		[window setLevel:NSStatusWindowLevel];
	}
}

-(void) fileSystemHasChanged: (NSNotification*) n
{
	if(NSDebugEnabled) NSLog(@"FileSystem has changed.");
	[self performSelectorOnMainThread: @selector(activateStatusMenu) withObject: nil waitUntilDone: YES];
}
-(void) kqueue: (UKKQueue*) kq receivedNotification: (NSString*) nm forFile: (NSString*) fpath {
	
	[self fileSystemHasChanged: nil];
}

-(BOOL)repairPermissions
{
	NSBundle *thisBundle = [NSBundle mainBundle];
	NSString *installer = [thisBundle pathForResource:@"installer" ofType:nil];
	
	AuthorizationRef authRef= [NSApplication getAuthorizationRef];
	
	if(authRef == nil)
		return FALSE;
	
	while(needsRepair()) {
		NSLog(@"Repairing Application...\n");
		[NSApplication executeAuthorized:installer withArguments:nil withAuthorizationRef:authRef];
		sleep(1);
	}
	AuthorizationFree(authRef, kAuthorizationFlagDefaults);
	return TRUE;
}




BOOL needsRepair() 
{
	NSBundle *thisBundle = [NSBundle mainBundle];
	NSString *helperPath = [thisBundle pathForResource:@"openvpnstart" ofType:nil];
	NSString *tunPath = [thisBundle pathForResource:@"tun.kext" ofType:nil];
	NSString *tapPath = [thisBundle pathForResource:@"tap.kext" ofType:nil];
	
	NSString *tunExecutable = [tunPath stringByAppendingPathComponent:@"/Contents/MacOS/tun"];
	NSString *tapExecutable = [tapPath stringByAppendingPathComponent:@"/Contents/MacOS/tap"];
	NSString *openvpnPath = [thisBundle pathForResource:@"openvpn" ofType:nil];
	
	
	// check setuid helper
	const char *path = [helperPath UTF8String];
    struct stat sb;
	if(stat(path,&sb)) runUnrecoverableErrorPanel();
	
	if (!(			  (sb.st_mode & S_ISUID) // set uid bit is set
					  && (sb.st_mode & S_IXUSR) // owner may execute it
					  && (sb.st_uid == 0) // is owned by root
					  )) {
		NSLog(@"openvpnstart helper has missing set uid bit");
		return YES;		
	}
	
	// check files which should be only accessible by root
	NSArray *inaccessibleObjects = [NSArray arrayWithObjects:tunExecutable,tapExecutable,openvpnPath,nil];
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
	
	// check tun and tap driver packages
	NSArray *filesToCheck = [NSArray arrayWithObjects:tunPath,tapPath,nil];
	NSEnumerator *enumerator = [filesToCheck objectEnumerator];
	NSString *file;
	while(file = [enumerator nextObject]) {
		NSDictionary *fileAttributes = [fileManager fileAttributesAtPath:file traverseLink:YES];
		unsigned long perms = [fileAttributes filePosixPermissions];
		NSString *octalString = [NSString stringWithFormat:@"%o",perms];
		if ( (![octalString isEqualToString:@"755"])  ) {
			NSLog(@"File %@ has permissions: %@ and needs repair...\n",currentPath,octalString);
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
	NSPanel *panel = NSGetAlertPanel(@"Tunnelblick Error",@"It seems like you need to reinstall Tunnelblick. Please move Tunnelblick to the Trash and download a fresh copy.",@"Download",@"Quit",nil);
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
