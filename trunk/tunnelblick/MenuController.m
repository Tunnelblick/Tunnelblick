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
#import <sys/sysctl.h>
#import <sys/types.h>
#import <sys/stat.h>
#import "KeyChain.h"
#import "NetSocket.h"
#import "NSApplication+LoginItem.h"
#import "NSApplication+NetworkNotifications.h"
#import "NSApplication+SystemVersion.h"
#import "helper.h"
#import "TBUserDefaults.h"

extern TBUserDefaults  * gTbDefaults;

@interface NSStatusBar (NSStatusBar_Private)
- (id)_statusItemWithLength:(float)l withPriority:(int)p;
- (id)_insertStatusItem:(NSStatusItem *)i withPriority:(int)p;
@end

@implementation MenuController

-(id) init
{	
    if (self = [super init]) {
        
        unloadKextsAtTermination = FALSE;
        
        if (  ! runningOnTigerOrNewer()  ) {
            TBRunAlertPanel(NSLocalizedString(@"System Requirements Not Met", @"Window title"),
                            NSLocalizedString(@"Tunnelblick requires OS X 10.4 or above\n     (\"Tiger\", \"Leopard\", or \"Snow Leopard\")", @"Window text"),
                            nil, nil, nil);
            [NSApp terminate:self];

        }
        
        [self dmgCheck];
		
		[NSApp setDelegate:self];
		
        // Backup/restore Resources/Deploy and/or repair ownership and permissions if necessary
        NSFileManager * fMgr             = [NSFileManager defaultManager];
        NSString      * deployDirPath    = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent: @"Contents/Resources/Deploy"];
        NSString      * deployBackupPath = [[[[@"/Library/Application Support/Tunnelblick/Backup" stringByAppendingPathComponent: [[NSBundle mainBundle] bundlePath]]
                                              stringByDeletingLastPathComponent]
                                             stringByAppendingPathComponent: @"TunnelblickBackup"]
                                            stringByAppendingPathComponent: @"Deploy"];
        BOOL isDir;
        BOOL needsChangeOwnershipAndOrPermissions;
        BOOL needsMoveLibraryOpenVPN;
        BOOL haveDeploy   = [fMgr fileExistsAtPath: deployDirPath    isDirectory: &isDir] && isDir;
        BOOL haveBackup   = [fMgr fileExistsAtPath: deployBackupPath isDirectory: &isDir] && isDir;
        needsInstallation( &needsChangeOwnershipAndOrPermissions, &needsMoveLibraryOpenVPN );
        BOOL remove     = FALSE;   // Remove the backup of Resources/Deploy
        BOOL restore    = FALSE;   // Restore Resources/Deploy from backup

        if ( haveBackup && ( ! haveDeploy) ) {
            restore = TRUE;
/* REMOVED FOR PRODUCTION. An end user should always restore from backup. We can't make this a preference since the preferences
                           haven't been loaded yet because we don't know if we have a "forced-preferences.plist" file
 
            int response = TBRunAlertPanel(NSLocalizedString(@"Restore Configuration Settings from Backup?", @"Window title"),
                                           NSLocalizedString(@"This copy of Tunnelblick does not contain any configuration settings. Do you wish to restore the configuration settings from the backup copy?\n\nAn administrator username and password will be required.", @"Window text"),
                                           NSLocalizedString(@"Restore", @"Button"),        // Default Button
                                           NSLocalizedString(@"Remove backup and do not restore", @"Button"), // Alternate Button
                                           NSLocalizedString(@"Do not restore", @"Button")); // Other button
            if (  response == NSAlertDefaultReturn ) {
                restore = TRUE;
            } else if (  response == NSAlertAlternateReturn ) {
                remove = TRUE;
            }
*/
        }
        // The installer restores Resources/Deploy and/or removes its backups and/or repairs permissions,
        // then moves the config folder if it hasn't already been moved, then backs up Resources/Deploy if it exists
        if (  restore || remove || needsChangeOwnershipAndOrPermissions || needsMoveLibraryOpenVPN  ) {
            if (  ! [self runInstallerRestoreDeploy: restore
                                          repairApp: needsChangeOwnershipAndOrPermissions
                                       removeBackup: remove
                                 moveLibraryOpenVPN: needsMoveLibraryOpenVPN]  ) {
                // runInstallerRestoreDeploy has already put up an error dialog and put a message in the console log if error occurred
                [NSApp setAutoLaunchOnLogin: NO];
                [NSApp terminate:self];
            }
        }

        // If Resources/Deploy exists now (perhaps after being restored) and has one or more .conf or .ovpn files,
        //    set configDirIsDeploy TRUE and set configDirPath to point to it
        // Otherwise set configDirIsDeploy FALSE and set configDirPath to point to ~/Library/Application Support/Tunnelblick/Configurations
        configDirIsDeploy = FALSE;
        configDirPath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Tunnelblick/Configurations/"] copy];
        
        if (  [fMgr fileExistsAtPath: deployDirPath isDirectory: &isDir] && isDir ) {
            NSArray *dirContents = [fMgr directoryContentsAtPath: deployDirPath];
            int i;
            for (i=0; i<[dirContents count]; i++) {
                NSString * ext  = [[dirContents objectAtIndex: i] pathExtension];
                if ( [ext isEqualToString:@"conf"] || [ext isEqualToString:@"ovpn"]  ) {
                    configDirIsDeploy = TRUE;
                    [configDirPath release];
                    configDirPath = [deployDirPath copy];
                    break;
                }
            }
        }

        // Set up to override user preferences from Deploy/forced-permissions.plist if it exists,
        // Otherwise use our equivalent of [NSUserDefaults standardUserDefaults]
        NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: [deployDirPath stringByAppendingPathComponent: @"forced-preferences.plist"]];
        gTbDefaults = [[TBUserDefaults alloc] initWithDefaultsDictionary: dict];
        
        // Set default preferences as needed
        if (  [gTbDefaults objectForKey: @"showConnectedDurations"] == nil  ) {
            [gTbDefaults setBool: TRUE forKey: @"showConnectedDurations"];
        }
        
        myVPNConnectionDictionary = [[NSMutableDictionary alloc] init];
        connectionArray = [[[NSMutableArray alloc] init] retain];

        [self loadMenuIconSet];
        
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
		
        ignoreNoConfigs = FALSE;    // We don't ignore the "no configurations" situation
        if (  ! [gTbDefaults boolForKey:@"doNotMonitorConfigurationFolder"]  ) {
            myQueue = [UKKQueue sharedFileWatcher];
            [myQueue addPathToQueue: configDirPath];
            [myQueue setDelegate: self];
            [myQueue setAlwaysNotify: YES];
		}
        
		[NSThread detachNewThreadSelector:@selector(moveSoftwareUpdateWindowToForegroundThread) toTarget:self withObject:nil];
		
		userIsAnAdmin = isUserAnAdmin();
		
        updater = [[SUUpdater alloc] init];

        [self loadKexts];

        // The following two lines work around a Sparkle Updater bug on Snow Leopard: the updater window doesn't appear.
        // If we have a window of our own, the updater window appears. The window needn't be visible; it only needs to
        // be loaded and the app needs to be activated for the updater window to appear. On Tiger and Leopard, it was
        // sufficient to run moveSoftwareUpdateWindowToForeground (via a delayed thread), and that code is left in so
        // Tiger and Leopard still show the update window. Presumably a newer version of Sparkle will fix this bug.
        [NSBundle loadNibNamed: @"SplashWindow" owner: self];   // Loads, but does not display
        [NSApp activateIgnoringOtherApps:YES];
        
        // Process "Automatically connect on launch" checkboxes
        NSString * filename;
        VPNConnection * myConnection;
        NSEnumerator * m = [myConfigArray objectEnumerator];
        while (filename = [m nextObject]) {
            myConnection = [myVPNConnectionDictionary objectForKey: filename];
            if([gTbDefaults boolForKey: [[myConnection configName] stringByAppendingString: @"autoConnect"]]) {
                if(![myConnection isConnected]) {
                    [myConnection connect:self];
                }
            }
        }
	}


    return self;
}

- (void) dealloc
{
    [animImages release];
    [connectedImage release];
    [mainImage release];
    
    [gTbDefaults release];

    [configDirPath release];
    [connectionArray release];
    [connectionsToRestore release];
    [lastState release];
    [myConfigArray release];
    [myVPNConnectionDictionary release];
    [myVPNMenu release];
    [showDurationsTimer release];
    [theAnim release];
    [updater release];
    
    [aboutItem release];
    [checkForUpdatesNowItem release];
    [reportAnonymousInfoItem release];
    [autoCheckForUpdatesItem release];
    [warnAboutSimultaneousItem release];
    [useShadowCopiesItem release];
    [monitorConfigurationDirItem release];
    [putIconNearSpotlightItem release];
    [optionsSubmenu release];
    [optionsItem release];
    [detailsItem release];
    [quitItem release];
    [statusMenuItem release];
    [theItem release]; 
    
    [super dealloc];
}

// Places an item with our icon in the Status Bar (creating it first if it doesn't already exist)
// By default, it uses an undocumented hack to place the icon on the right side, next to SpotLight
// Otherwise ("placeIconInStandardPositionInStatusBar" preference or hack not available), it places it normally (on the left)
- (void) createStatusItem
{
	NSStatusBar *bar = [NSStatusBar systemStatusBar];
    
	if (   [bar respondsToSelector: @selector(_statusItemWithLength:withPriority:)]
        && [bar respondsToSelector: @selector(_insertStatusItem:withPriority:)]
        && (  ! [gTbDefaults boolForKey:@"placeIconInStandardPositionInStatusBar"]  )
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
	[self createDefaultConfigUsingTitle:NSLocalizedString(@"Welcome to Tunnelblick", @"Window title") 
							 andMessage: NSLocalizedString(@"Tunnelblick's configuration folder does not exist or it does not contain any configuration files.\n\nTunnelblick needs one or more configuration files for your VPN(s). These files are usually supplied to you by your network administrator or your VPN service provider and they must be kept in the configuration folder. You may also have certificate or key files; they are usually put in the configuration folder, too.\n\nYou may\n     • Install a sample configuration file and edit it. (Tunnelblick will keep running.)\n     • Open the configuration folder and put your files into it. (You will have to launch Tunnelblick again.)\n     • Quit Tunnelblick\n\n", @"Window text")];
	[self initialiseAnim];
}

- (void) loadMenuIconSet
{
    NSString *menuIconSet = [gTbDefaults objectForKey:@"menuIconSet"];
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
    if (  ! [gTbDefaults boolForKey:@"doNotShowOptionsSubmenu"]  ) {
        preferencesTitleItem = [[NSMenuItem alloc] init];
        [preferencesTitleItem setTitle: NSLocalizedString(@"Preferences", @"Menu item")];
        [preferencesTitleItem setTarget: self];
        [preferencesTitleItem setAction: @selector(togglePreferencesTitle:)];
        
        putIconNearSpotlightItem = [self initPrefMenuItemWithTitle: NSLocalizedString(@"Place Icon Near the Spotlight Icon", @"Menu item")
                                                         andAction: @selector(togglePlaceIconNearSpotlight:)
                                                        andToolTip: NSLocalizedString(@"Takes effect the next time Tunnelblick is launched", @"Menu item tooltip")
                                                atIndentationLevel: 1
                                                  andPreferenceKey: @"placeIconInStandardPositionInStatusBar"
                                                           negated: YES];
        
        monitorConfigurationDirItem = [self initPrefMenuItemWithTitle: NSLocalizedString(@"Monitor the Configuration Folder", @"Menu item")
                                                            andAction: @selector(toggleMonitorConfigurationDir:)
                                                           andToolTip: NSLocalizedString(@"Takes effect immediately", @"Menu item tooltip")
                                                   atIndentationLevel: 1
                                                     andPreferenceKey: @"doNotMonitorConfigurationFolder"
                                                              negated: YES];
        
//        warnAboutSimultaneousItem = [self initPrefMenuItemWithTitle: NSLocalizedString(@"Warn About Simultaneous Connections", @"Menu item")
//                                                          andAction: @selector(toggleWarnAboutSimultaneous:)
//                                                         andToolTip: NSLocalizedString(@"Takes effect with the next connection", @"Menu item tooltip")
//                                                 atIndentationLevel: 1
//                                                   andPreferenceKey: @"skipWarningAboutSimultaneousConnections"
//                                                            negated: YES];
//        
//        showConnectedDurationsItem = [self initPrefMenuItemWithTitle: NSLocalizedString(@"Show Connection Timers", @"Menu item")
//                                                          andAction: @selector(toggleConnectionTimers:)
//                                                         andToolTip: NSLocalizedString(@"Takes effect immediately", @"Menu item tooltip")
//                                                 atIndentationLevel: 1
//                                                   andPreferenceKey: @"showConnectedDurations"
//                                                            negated: NO];
//        
        useShadowCopiesItem = [self initPrefMenuItemWithTitle: NSLocalizedString(@"Use Shadow Copies of Configuration Files", @"Menu item")
                                                    andAction: @selector(toggleUseShadowCopies:)
                                                   andToolTip: NSLocalizedString(@"Takes effect with the next connection", @"Menu item tooltip")
                                           atIndentationLevel: 1
                                             andPreferenceKey: @"useShadowConfigurationFiles"
                                                      negated: NO];
        
        autoCheckForUpdatesItem = [self initPrefMenuItemWithTitle: NSLocalizedString(@"Automatically Check for Updates", @"Menu item")
                                                        andAction: @selector(toggleAutoCheckForUpdates:)
                                                       andToolTip: NSLocalizedString(@"Takes effect the next time Tunnelblick is launched", @"Menu item tooltip")
                                               atIndentationLevel: 1
                                                 andPreferenceKey: @"SUEnableAutomaticChecks"
                                                          negated: NO];
        
        reportAnonymousInfoItem = [self initPrefMenuItemWithTitle: NSLocalizedString(@"Send Anonymous System Profile", @"Menu item")
                                                        andAction: @selector(toggleReportAnonymousInfo:)
                                                       andToolTip: NSLocalizedString(@"Takes effect at the next check for updates", @"Menu item tooltip")
                                               atIndentationLevel: 1
                                                 andPreferenceKey: @"SUSendProfileInfo"
                                                          negated: NO];

        if (  ! [gTbDefaults boolForKey:@"doNotShowCheckForUpdatesNowMenuItem"]  ) {
            checkForUpdatesNowItem = [[NSMenuItem alloc] init];
            [checkForUpdatesNowItem setTitle: NSLocalizedString(@"Check For Updates Now", @"Menu item")];
            [checkForUpdatesNowItem setTarget: self];
            [checkForUpdatesNowItem setAction: @selector(checkForUpdates:)];
        }
    }
    
    aboutItem = [[NSMenuItem alloc] init];
    [aboutItem setTitle: NSLocalizedString(@"About...", @"Menu item")];
    [aboutItem setTarget: self];
    [aboutItem setAction: @selector(openAboutWindow:)];
    
    if (   putIconNearSpotlightItem
        || monitorConfigurationDirItem
        || showConnectedDurationsItem
        || warnAboutSimultaneousItem
        || useShadowCopiesItem
        || autoCheckForUpdatesItem
        || reportAnonymousInfoItem
        || checkForUpdatesNowItem
        ) {
        optionsSubmenu = [[NSMenu alloc] initWithTitle:@"Options SubMenu Title"];
        
        if (  preferencesTitleItem              ) { [optionsSubmenu addItem: preferencesTitleItem           ]; }
        if (  putIconNearSpotlightItem          ) { [optionsSubmenu addItem: putIconNearSpotlightItem       ]; }
        if (  monitorConfigurationDirItem       ) { [optionsSubmenu addItem: monitorConfigurationDirItem    ]; }
        if (  warnAboutSimultaneousItem         ) { [optionsSubmenu addItem: warnAboutSimultaneousItem      ]; }
        if (  showConnectedDurationsItem        ) { [optionsSubmenu addItem: showConnectedDurationsItem     ]; }
        if (  useShadowCopiesItem               ) { [optionsSubmenu addItem: useShadowCopiesItem            ]; }

        if (   putIconNearSpotlightItem || monitorConfigurationDirItem || warnAboutSimultaneousItem || showConnectedDurationsItem || useShadowCopiesItem  ) {
            [optionsSubmenu addItem: [NSMenuItem separatorItem]];
        }
        
        if (  autoCheckForUpdatesItem  ) { [optionsSubmenu addItem: autoCheckForUpdatesItem ]; }
        if (  reportAnonymousInfoItem  ) { [optionsSubmenu addItem: reportAnonymousInfoItem ]; }
        
        if (  autoCheckForUpdatesItem || reportAnonymousInfoItem  ) {
            [optionsSubmenu addItem: [NSMenuItem separatorItem]];
        }
        
        if (  checkForUpdatesNowItem  ) { [optionsSubmenu addItem: checkForUpdatesNowItem   ]; }

        if (  checkForUpdatesNowItem && aboutItem  ) {
            [optionsSubmenu addItem: [NSMenuItem separatorItem]];
        }
        
        if (  aboutItem  ) { [optionsSubmenu addItem: aboutItem]; }
        
        optionsItem = [[NSMenuItem alloc] init];
        [optionsItem setTitle: NSLocalizedString(@"Options", @"Menu item")];
        [optionsItem setSubmenu: optionsSubmenu];
        
    } else {
        optionsItem = nil;
    }
    
    detailsItem = [[NSMenuItem alloc] init];
    [detailsItem setTitle: NSLocalizedString(@"Details...", @"Menu item")];
    [detailsItem setTarget: self];
    [detailsItem setAction: @selector(openLogWindow:)];
    
    quitItem = [[NSMenuItem alloc] init];
    [quitItem setTitle: NSLocalizedString(@"Quit", @"Menu item")];
    [quitItem setTarget: self];
    [quitItem setAction: @selector(quit:)];
    
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
		VPNConnection* myConnection = [[VPNConnection alloc] initWithConfig: configString
                                                                inDirectory: configDirPath
                                                                 isInDeploy: configDirIsDeploy]; // initialize VPN Connection with config	
		[myConnection setState:@"EXITING"];
		[myConnection setDelegate:self];
        
		[myVPNConnectionDictionary setObject: myConnection forKey:configString];
		
        // Note: The item's title will be set on demand in VPNConnection's -validateMenuItem
		[connectionItem setTarget:myConnection]; 
		[connectionItem setAction:@selector(toggle:)];
		
		[myVPNMenu insertItem:connectionItem atIndex:i];
		i++;
	}
	[myVPNMenu addItem: [NSMenuItem separatorItem]];
    
	[myVPNMenu addItem: detailsItem];
	[myVPNMenu addItem: [NSMenuItem separatorItem]];
	
    if (  optionsItem  ) {
        [myVPNMenu addItem: optionsItem];
    } else {
        [myVPNMenu addItem: aboutItem];
    }
    [myVPNMenu addItem: [NSMenuItem separatorItem]];

    [myVPNMenu addItem: quitItem];

}

-(NSMenuItem *)initPrefMenuItemWithTitle: (NSString *) title
                               andAction: (SEL) action
                              andToolTip: (NSString *) tip
                      atIndentationLevel: (int) indentLevel
                        andPreferenceKey: (NSString *) prefKey
                                 negated: (BOOL) negatePref
{
    if (  [gTbDefaults canChangeValueForKey:prefKey] || ( ! [gTbDefaults boolForKey: @"doNotShowForcedPreferenceMenuItems"] )  ) {
        NSMenuItem * item = [[NSMenuItem alloc] init];
        [item setTitle:   title];
        [item setTarget:  self];
        [item setAction:  action];
        [item setToolTip: tip];
        [item setIndentationLevel: indentLevel];
        [item setRepresentedObject: prefKey];
        BOOL state = [gTbDefaults boolForKey:prefKey];
        state = negatePref ? ! state : state;
        if (  state  ) {
            [item setState: NSOnState];
        } else {
            [item setState: NSOffState];
        }
        return item;
    } else {
        return nil;
    }
    
}

- (BOOL)validateMenuItem:(NSMenuItem *)anItem 
{
    // We set the on/off state from the CURRENT preferences, not the preferences when launched.
    // That is easier than setting the on/off state whenever we change a preference, and
    // some preferences are changed by Sparkle, so we must set them here anyway
    SEL act = [anItem action];
    if (  act == @selector(togglePlaceIconNearSpotlight:)  ) {
        if (  ! [gTbDefaults boolForKey:@"placeIconInStandardPositionInStatusBar"]  ) {
            [anItem setState: NSOnState];
        } else {
            [anItem setState: NSOffState];
        }
    } else if (  act == @selector(toggleMonitorConfigurationDir:)  ) {
        if (  ! [gTbDefaults boolForKey:@"doNotMonitorConfigurationFolder"]  ) {
            [anItem setState: NSOnState];
        } else {
            [anItem setState: NSOffState];
        }
    } else if (  act == @selector(toggleWarnAboutSimultaneous:)  ) {
        if (  ! [gTbDefaults boolForKey:@"skipWarningAboutSimultaneousConnections"]  ) {
            [anItem setState: NSOnState];
        } else {
            [anItem setState: NSOffState];
        }
    } else if (  act == @selector(toggleConnectionTimers:)  ) {
        if (  [gTbDefaults boolForKey:@"showConnectedDurations"]  ) {
            [anItem setState: NSOnState];
        } else {
            [anItem setState: NSOffState];
        }
    } else if (  act == @selector(toggleUseShadowCopies:)  ) {
        if (  [gTbDefaults boolForKey:@"useShadowConfigurationFiles"]  ) {
            [anItem setState: NSOnState];
        } else {
            [anItem setState: NSOffState];
        }
    } else if (  act == @selector(toggleAutoCheckForUpdates:)  ) {
        if (  [gTbDefaults boolForKey:@"SUEnableAutomaticChecks"]  ) {
            [anItem setState: NSOnState];
        } else {
            [anItem setState: NSOffState];
        }
    } else if (  act == @selector(toggleReportAnonymousInfo:)  ) {
        if (  [gTbDefaults boolForKey:@"SUSendProfileInfo"]  ) {
            [anItem setState: NSOnState];
        } else {
            [anItem setState: NSOffState];
        }
    }

    // We store the preference key for a menu itme in the item's representedObject so we can do the following:
    if (  [anItem representedObject]  ) {
        if (  ! [gTbDefaults canChangeValueForKey: [anItem representedObject]]  ) {
            return NO;
        }
    }

    return YES;
}

-(void)togglePlaceIconNearSpotlight: (NSMenuItem *) item
{
    [self toggleMenuItem: item withPreferenceKey: @"placeIconInStandardPositionInStatusBar"];
}

-(void)toggleMonitorConfigurationDir: (NSMenuItem *) item
{
    [self toggleMenuItem: item withPreferenceKey: @"doNotMonitorConfigurationFolder"];
    if (  [gTbDefaults boolForKey: @"doNotMonitorConfigurationFolder"]  ) {
        if (  myQueue  ) {
            [myQueue removePathFromQueue: configDirPath];
        }
    } else {
        if ( myQueue  ) {
            [myQueue addPathToQueue: configDirPath];
            [self activateStatusMenu];
        } else {
            myQueue = [UKKQueue sharedFileWatcher];
            [myQueue addPathToQueue: configDirPath];
            [myQueue setDelegate: self];
            [myQueue setAlwaysNotify: YES];
            [self activateStatusMenu];
        }
    }
}

-(void)toggleWarnAboutSimultaneous: (NSMenuItem *) item
{
    [self toggleMenuItem: item withPreferenceKey: @"skipWarningAboutSimultaneousConnections"];
}

-(void)toggleConnectionTimers: (NSMenuItem *) item
{
    [self toggleMenuItem: item withPreferenceKey: @"showConnectedDurations"];
    
    if (  [gTbDefaults boolForKey:@"showConnectedDurations"]  ) {
        // Now on, so it was off. Start the timer
        if (  showDurationsTimer == nil  ) {
            showDurationsTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0
                                                                   target:self
                                                                 selector:@selector(updateTabLabels)
                                                                 userInfo:nil
                                                                  repeats:YES] retain];
        }
    } else {
        // Now off, so was on. Stop the timer
        if (showDurationsTimer != nil) {
            [showDurationsTimer invalidate];
            [showDurationsTimer release];
            showDurationsTimer = nil;
        }
    }
    [self updateTabLabels];
}

-(void)toggleUseShadowCopies: (NSMenuItem *) item
{
    [self toggleMenuItem: item withPreferenceKey: @"useShadowConfigurationFiles"];
}

-(void)toggleAutoCheckForUpdates: (NSMenuItem *) item
{
    [self toggleMenuItem: item withPreferenceKey: @"SUEnableAutomaticChecks"];
}

-(void)toggleReportAnonymousInfo: (NSMenuItem *) item
{
    [self toggleMenuItem: item withPreferenceKey: @"SUSendProfileInfo"];
}

-(void)toggleMenuItem: (NSMenuItem *) item withPreferenceKey: (NSString *) prefKey
{
    [gTbDefaults setBool: ! [gTbDefaults boolForKey:prefKey] forKey:prefKey];
    [gTbDefaults synchronize];
    
    if (  [item state] == NSOnState  ) {
        [item setState: NSOffState];
    } else {
        [item setState:NSOnState];
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
            VPNConnection* myConnection = [[VPNConnection alloc] initWithConfig: configString
                                                                    inDirectory: configDirPath
                                                                     isInDeploy: configDirIsDeploy];
            [myConnection setState:@"EXITING"];
            [myConnection setDelegate:self];
            [myVPNConnectionDictionary setObject: myConnection forKey:configString];
            
            // Add new config to myConfigArray and the menu, keeping myConfigArray sorted
            // Note: The item's title will be set on demand in VPNConnection's -validateMenuItem
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
    
    // Remove the ones that have been deleted
    m = [myConfigArray objectEnumerator];
    while (configString = [m nextObject]) {
        if (  [curConfigsArray indexOfObject:configString] == NSNotFound  ) {
            
            // Disconnect first if necessary
            VPNConnection* myConnection = [myVPNConnectionDictionary objectForKey:configString];
            if (  ! [[myConnection state] isEqualTo:@"EXITING"]  ) {
                [myConnection disconnect:self];
                NSAlert * alert = [[NSAlert alloc] init];
                NSString * msg1 = NSLocalizedString(@"'%@' has been disconnected", @"Window title");
                NSString * msg2 = NSLocalizedString(@"Tunnelblick has disconnected '%@' because its configuration file has been removed.", @"Window text");
                [alert setMessageText:[NSString stringWithFormat:msg1, [myConnection configName]]];
                [alert setInformativeText:[NSString stringWithFormat:msg2, [myConnection configName]]];
                [alert runModal];
                [alert release];
            }

            [myVPNConnectionDictionary removeObjectForKey:configString];
            
            // Remove config from myConfigArray and the menu
            int i = [myConfigArray indexOfObject:configString];
            [myConfigArray removeObjectAtIndex:i];
            [myVPNMenu removeItemAtIndex:i+2];  // Note: first item is status, second is a separator
            
            needToUpdateLogWindow = TRUE;
        }
    }
    
	// If there aren't any configuration files left, deal with that
    [self createDefaultConfigUsingTitle: NSLocalizedString(@"All configuration files removed", @"Window title")
							 andMessage: NSLocalizedString(@"You have removed all configuration files from the configuration folder.\n\nTunnelblick needs one or more configuration files for your VPN(s). These files are usually supplied to you by your network administrator or your VPN service provider and they must be kept in the configuration folder. You may also have certificate or key files; they are usually put in the configuration folder, too.\n\nYou may\n     • Install a sample configuration file and edit it. (Tunnelblick will keep running.)\n     • Open the configuration folder and put your files into it. (You will have to launch Tunnelblick again.)\n     • Quit Tunnelblick\n\n", @"Window text")];
    
    if (  needToUpdateLogWindow  ) {
        // Add or remove configurations from the Log window (if it is open) by closing and reopening the Log window
        BOOL logWindowWasOpen = logWindowIsOpen;
        [logWindow close];
        [logWindow release];
        logWindow = nil;
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
    NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath: configDirPath];
    while (file = [dirEnum nextObject]) {
        if ([[file pathExtension] isEqualToString: @"conf"] || [[file pathExtension] isEqualToString: @"ovpn"]) {
			[array insertObject:file atIndex:i];
			//if(NSDebugEnabled) NSLog(@"Object: %@ atIndex: %d",file,i);
			i++;
        }
    }
    return array;
}

-(void)validateLogButtons
{
    //NSLog(@"validating log buttons");
    VPNConnection* connection = [self selectedConnection];
    [connectButton setEnabled:[connection isDisconnected]];
    [disconnectButton setEnabled:(![connection isDisconnected])];

	NSString *disableEditConfigKey = [[connection configName] stringByAppendingString:@"disableEditConfiguration"];
    if (  [gTbDefaults boolForKey:disableEditConfigKey]  ) {
        [editButton setEnabled: NO];
    } else {
        [editButton setEnabled: YES];
    }
    
	NSString *autoConnectKey = [[connection configName] stringByAppendingString:@"autoConnect"];
    if (  [gTbDefaults canChangeValueForKey: autoConnectKey]  ) {
        [autoLaunchCheckbox setEnabled: YES];
    } else {
        [autoLaunchCheckbox setEnabled: NO];
    }
	if([gTbDefaults boolForKey:autoConnectKey]) {
		[autoLaunchCheckbox setState:NSOnState];
	} else {
		[autoLaunchCheckbox setState:NSOffState];
	}
	
	NSString *useDNSKey = [[connection configName] stringByAppendingString:@"useDNS"];
    if (  [gTbDefaults canChangeValueForKey: useDNSKey]  ) {
        [useNameserverCheckbox setEnabled: YES];
    } else {
        [useNameserverCheckbox setEnabled: NO];
	}
	if(  useDNSStatus(connection)  ) {
		[useNameserverCheckbox setState:NSOnState];
	} else {
		[useNameserverCheckbox setState:NSOffState];
	}
	
	NSString *notMonitorConnectionKey = [[connection configName] stringByAppendingString:@"-notMonitoringConnection"];
    if (  [gTbDefaults canChangeValueForKey: notMonitorConnectionKey] && useDNSStatus(connection)  ) {
        [monitorConnnectionCheckbox setEnabled: YES];
    } else {
        [monitorConnnectionCheckbox setEnabled: NO];
	}
	if(  ( ! [gTbDefaults boolForKey:notMonitorConnectionKey] ) && useDNSStatus(connection)  ) {
		[monitorConnnectionCheckbox setState:NSOnState];
	} else {
		[monitorConnnectionCheckbox setState:NSOffState];
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
		//NSLog(@"configName: %@\nconnectionState: %@",[myConnection configName],[myConnection state]);
        NSString * cState = [myConnection state];
        NSString * cTimeS = @"";

        // Get connection duration if preferences say to 
        if (    [gTbDefaults boolForKey:@"showConnectedDurations"]
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
		myState = NSLocalizedString(@"Tunnelblick: 1 connection active.", @"Status message");
	} else {
		myState = [NSString stringWithFormat:NSLocalizedString(@"Tunnelblick: %d connections active.", @"Status message"),connectionNumber];
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
	[[self selectedLogView] setString: @""];
    [[self selectedConnection] addToLog: [self openVPNLogHeader] atDate: nil];
}

- (NSString *) openVPNLogHeader
{
    unsigned major, minor, bugFix;
    [[NSApplication sharedApplication] getSystemVersionMajor:&major minor:&minor bugFix:&bugFix];
    return ([NSString stringWithFormat:@"*Tunnelblick: OS X %d.%d.%d; %@; %@", major, minor, bugFix, tunnelblickVersion([NSBundle mainBundle]), openVPNVersion()]);
}

- (VPNConnection*) selectedConnection
	/*" Returns the connection associated with the currently selected log tab or nil on error. "*/
{
	if (![tabView selectedTabViewItem]) {
		[tabView selectFirstTabViewItem: nil];
	}
	
    NSString* configFilename = [[tabView selectedTabViewItem] identifier];
	VPNConnection* connection = [myVPNConnectionDictionary objectForKey:configFilename];
	NSArray *allConnections = [myVPNConnectionDictionary allValues];
	if(connection) return connection;
	else if([allConnections count]) return [allConnections objectAtIndex:0] ; 
	else return nil;
}


- (IBAction)connect:(id)sender
{
    if (  ! [gTbDefaults boolForKey:@"skipWarningAboutSimultaneousConnections"]  ) {
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
            int button = TBRunAlertPanelExtended(NSLocalizedString(@"Do you wish to connect?", @"Window title"),
                                                 [NSString stringWithFormat:NSLocalizedString(@"Multiple simultaneous connections would be created (%d with 'Set nameserver', %d without 'Set nameserver').", @"Window text"), numConnectionsWithSetNameserver, (numConnections-numConnectionsWithSetNameserver) ],
                                                 NSLocalizedString(@"Connect", @"Button"),  // Default button
                                                 NSLocalizedString(@"Cancel", @"Button"),   // Alternate button
                                                 nil,
                                                 @"skipWarningAboutSimultaneousConnections",
                                                 NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
                                                 nil);
            if (  button == NSAlertAlternateReturn  ) {
                return;
            }
        }
    }
    
    [[self selectedConnection] connect: sender]; 
}

- (IBAction)disconnect:(id)sender
{
    [[self selectedConnection] disconnect: sender];      
}


- (IBAction) checkForUpdates: (id) sender
{
    [NSThread detachNewThreadSelector:@selector(moveSoftwareUpdateWindowToForegroundThread) toTarget:self withObject:nil];
    [updater checkForUpdates: self];
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
    if (  [tbVersion isEqualToString: [gTbDefaults objectForKey:@"detailsWindowFrameVersion"]]    ) {
        NSString * frame = [gTbDefaults objectForKey: @"detailsWindowFrame"];
        if (  frame != nil  ) {
            [logWindow setFrameFromString:frame];
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
    if (  ! connection  ) {
        NSLog(@"myVPNConnectionsDictionary is empty; Tunnelblick must have at least one configuration");
        [NSApp setAutoLaunchOnLogin: NO];
        [NSApp terminate: self];
    }

    initialItem = [tabView tabViewItemAtIndex: 0];
    [initialItem setIdentifier: [connection configFilename]];
    [initialItem setLabel: [connection configName]];
    
    int curTabIndex = 0;
    [tabView selectTabViewItemAtIndex:0];
    BOOL haveOpenConnection = ! [connection isDisconnected];
    while (connection = [myVPNConnectionDictionary objectForKey: [e nextObject]]) {
        NSTabViewItem* newItem = [[NSTabViewItem alloc] init];
        [newItem setIdentifier: [connection configFilename]];
        [newItem setLabel: [connection configName]];
        [tabView addTabViewItem: newItem];
        [newItem release];
        ++curTabIndex;
        if (  ( ! haveOpenConnection ) && ( ! [connection isDisconnected] )  ) {
            [tabView selectTabViewItemAtIndex:curTabIndex];
            haveOpenConnection = YES;
        }
    }
	[self tabView:tabView didSelectTabViewItem:initialItem];
	[self validateLogButtons];
	[self updateTabLabels];
    
    // Set up a timer to update the tab labels with connections' duration times
    if (    (showDurationsTimer == nil)  && [gTbDefaults boolForKey:@"showConnectedDurations"]    ) {
        showDurationsTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0
                                                               target:self
                                                             selector:@selector(updateTabLabels)
                                                             userInfo:nil
                                                              repeats:YES] retain];
    }
	
    // Localize window title
    [logWindow setTitle:NSLocalizedString([logWindow title], nil)];

	// Localize buttons and checkboxes
    [self localizeControl:clearButton                   shiftRight:editButton                   shiftLeft:nil               shiftSelfLeft:NO ];
    [self localizeControl:editButton                    shiftRight:nil                          shiftLeft:nil               shiftSelfLeft:NO ];
    [self localizeControl:connectButton                 shiftRight:nil                          shiftLeft:disconnectButton  shiftSelfLeft:YES];
    [self localizeControl:disconnectButton              shiftRight:nil                          shiftLeft:nil               shiftSelfLeft:YES];
    [self localizeControl:useNameserverCheckbox         shiftRight:monitorConnnectionCheckbox shiftLeft:nil               shiftSelfLeft:NO ];
    [self localizeControl:monitorConnnectionCheckbox  shiftRight:nil                          shiftLeft:nil               shiftSelfLeft:NO ];
    [self localizeControl:autoLaunchCheckbox            shiftRight:nil                          shiftLeft:nil               shiftSelfLeft:NO ];

    [logWindow display];
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
        if (  [tbVersion isEqualToString: [gTbDefaults objectForKey:@"detailsWindowFrameVersion"]]    ) {
            if (   [frame isEqualToString: [gTbDefaults objectForKey:@"detailsWindowFrame"]]    ) {
                saveIt = FALSE;
            }
        }

        if (saveIt) {
            [gTbDefaults setObject: frame forKey: @"detailsWindowFrame"];
            [gTbDefaults setObject: [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]
                           forKey: @"detailsWindowFrameVersion"];
            [gTbDefaults synchronize];
        }
        logWindowIsOpen = FALSE;
    }
}


- (IBAction) openAboutWindow: (id) sender
// Uses the "...WithOptions" version of orderFrontStandardAboutPanel so all localization can be in Localizable.strings files
{
    NSImage  * appIcon      = [NSImage imageNamed:@"tunnelblick.icns"];
    NSString * appName      = @"Tunnelblick";
    NSString * appVersion   = tunnelblickVersion([NSBundle mainBundle]);
    NSString * version      = @"";
	
    NSString * basedOnHtml  = @"<br><br>";
    // Using [[NSBundle mainBundle] pathForResource: @"about" ofType: @"html" inDirectory: @"Deploy"] doesn't work -- it is apparently cached by OS X.
    // If it is used immediately after the installer creates and populates Resources/Deploy, nil is returned instead of the path
    // The workaround is to create the path "by hand" and use that.
    NSString * aboutPath    = [[[NSBundle mainBundle] bundlePath] stringByAppendingString: @"/Contents/Resources/about.html"];
	NSString * htmlFromFile = [NSString stringWithContentsOfFile: aboutPath encoding:NSASCIIStringEncoding error:NULL];
    if (  htmlFromFile  ) {
        basedOnHtml  = NSLocalizedString(@"<br><br>Based on Tunnelblick, free software available at <a href=\"http://code.google.com/p/tunnelblick\">http://code.google.com/p/tunnelblick</a>", @"Window text");
    } else {
        htmlFromFile = @"<br><br><a href=\"http://code.google.com/p/tunnelblick\">http://code.google.com/p/tunnelblick</a>";
    }
    NSString * html         = [NSString stringWithFormat:@"%@%@%@%@%@",
                               @"<html><body><center><div style=\"font-family: Verdana, Arial, Helvetica, sans-serif; font-size: 10px\">",
                               openVPNVersion(),
							   htmlFromFile,
                               basedOnHtml,
							   @"</div></center><body></html>"];
    NSData * data = [html dataUsingEncoding:NSASCIIStringEncoding];
    NSAttributedString * credits = [[[NSAttributedString alloc] initWithHTML:data documentAttributes:NULL] autorelease];

    NSString * copyright    = NSLocalizedString(@"Copyright © 2004-2009 Angelo Laub and others. All rights reserved.", @"Window text");

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

-(void)killAllConnections
{
	VPNConnection * connection;
    NSEnumerator* e = [connectionArray objectEnumerator];
    
    while (connection = [e nextObject]) {
        [connection disconnect:self];
		if(NSDebugEnabled) NSLog(@"Killing connection");
    }
}

-(void)destroyAllPipes
{
    VPNConnection * connection;
    
    NSArray *keyArray = [[myVPNConnectionDictionary allKeys] sortedArrayUsingSelector: @selector(compare:)];
    NSArray *myConnectionArray = [myVPNConnectionDictionary objectsForKeys:keyArray notFoundMarker:[NSNull null]];
    NSEnumerator* e = [myConnectionArray objectEnumerator];
    
    if(NSDebugEnabled) NSLog(@"Destroying pipes.\n");
    while (connection = [e nextObject]) {
        [connection destroyPipe];
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
    sleep(1);       //Give them a chance to end gracefully, first
	[task launch];
	[task waitUntilExit];
}

-(void)loadKexts 
{
	NSString* path = [[NSBundle mainBundle] pathForResource: @"openvpnstart" 
													 ofType: nil];
	NSTask* task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath: path]; 
	
	NSArray *arguments = [NSArray arrayWithObjects:@"loadKexts", nil];
	[task setArguments:arguments];
	[task launch];
	[task waitUntilExit];
    unloadKextsAtTermination = TRUE;    // Even if this load failed, the automatic load in openvpnstart may succeed, so we unload.
}

-(void)unloadKexts 
{
    if (  unloadKextsAtTermination  ) {
        NSString* path = [[NSBundle mainBundle] pathForResource: @"openvpnstart" 
                                                         ofType: nil];
        NSTask* task = [[[NSTask alloc] init] autorelease];
        [task setLaunchPath: path]; 
        
        NSArray *arguments = [NSArray arrayWithObjects:@"unloadKexts", nil];
        [task setArguments:arguments];
        [task launch];
        [task waitUntilExit];
    }
}

-(void)resetActiveConnections {
	VPNConnection *connection;
	NSEnumerator* e = [connectionArray objectEnumerator];
	
	while (connection = [e nextObject]) {
		if (NSDebugEnabled) NSLog(@"Connection %@ is connected for %f seconds\n",[connection configName],[[connection connectedSinceDate] timeIntervalSinceNow]);
		if ([[connection connectedSinceDate] timeIntervalSinceNow] < -5) {
			if (NSDebugEnabled) NSLog(@"Resetting connection: %@",[connection configName]);
			[connection disconnect:self];
			[connection connect:self];
		}
		else {
			if (NSDebugEnabled) NSLog(@"Not Resetting connection: %@\n, waiting...",[connection configName]);
		}
	}
}

// If there aren't ANY config files in the config folder 
// then let the user either quit or create and edit a sample configuration file
// else do nothing
-(void)createDefaultConfigUsingTitle:(NSString *) ttl andMessage:(NSString *) msg 
{
    if (  ignoreNoConfigs || [[self getConfigs] count] != 0  ) {
        return;
    }
    
    NSFileManager  * fileManager     = [NSFileManager defaultManager];
    
    if (  configDirIsDeploy  ) {
        TBRunAlertPanel(NSLocalizedString(@"All configuration files removed", @"Window title"),
                        [NSString stringWithFormat: NSLocalizedString(@"All configuration files in %@ have been removed. Tunnelblick must quit.", @"Window text"),
                         [[fileManager componentsToDisplayForPath: configDirPath] componentsJoinedByString: @"/"]],
                        nil, nil, nil);
        [NSApp setAutoLaunchOnLogin: NO];
        [NSApp terminate: nil];
    }
    
    NSString * openvpnConfPath = [[NSBundle mainBundle] pathForResource: @"openvpn"
                                                                 ofType: @"conf"];
    
    BOOL isDir;
    NSString * alternateButtonTitle = nil;
    if (  ! ([fileManager fileExistsAtPath: configDirPath isDirectory: &isDir])  ) {
        alternateButtonTitle = NSLocalizedString(@"Create and open configuration folder", @"Button");
    } else {
        alternateButtonTitle = NSLocalizedString(@"Open configuration folder", @"Button");
    }
    
    
    int button = TBRunAlertPanel(ttl,
                                 msg,
                                 NSLocalizedString(@"Quit", @"Button"), // Default button
                                 NSLocalizedString(@"Install and edit sample configuration file", @"Button"), // Alternate button
                                 alternateButtonTitle);                 // Other button
    
    if (  button == NSAlertDefaultReturn  ) {   // QUIT
        [NSApp setAutoLaunchOnLogin: NO];
        [NSApp terminate: nil];
    }
    
    NSString * parentPath = [configDirPath stringByDeletingLastPathComponent];
    if (  ! [fileManager fileExistsAtPath: parentPath]  ) {                      // If ~/Library/Application Support/Tunnelblick doesn't exist, create it
        if ( ! [fileManager createDirectoryAtPath: parentPath attributes:nil]  ) {
            NSLog(@"Error creating %@", parentPath);
        }
    }
    
    if (  ! [fileManager fileExistsAtPath: configDirPath]  ) {                      // If ~/Library/Application Support/Tunnelblick/Configurations doesn't exist, create it
        if (  ! [fileManager createDirectoryAtPath: configDirPath attributes:nil]  ) {
            NSLog(@"Error creating %@", configDirPath);
        }
    }
    
    if (  ! [gTbDefaults boolForKey: @"doNotCreateLaunchTunnelblickLinkinConfigurations"]  ) {
        NSString * pathToThisApp = [[NSBundle mainBundle] bundlePath];
        NSString * launchTunnelblickSymlink = [configDirPath stringByAppendingPathComponent: @"Launch Tunnelblick"];
        if (  ! [fileManager fileExistsAtPath:launchTunnelblickSymlink]  ) {
            ignoreNoConfigs = TRUE; // We're dealing with no configs already, and will either quit or create one
            NSLog(@"Creating 'Launch Tunnelblick' link in Configurations folder; links to %@", pathToThisApp);
            [fileManager createSymbolicLinkAtPath: launchTunnelblickSymlink
                                      pathContent: pathToThisApp];
        } else if (  ! [[fileManager pathContentOfSymbolicLinkAtPath: launchTunnelblickSymlink] isEqualToString: pathToThisApp]  ) {
            ignoreNoConfigs = TRUE; // We're dealing with no configs already, and will either quit or create one
            NSLog(@"Replacing 'Launch Tunnelblick' link in Configurations folder; now links to %@", pathToThisApp);
            [fileManager removeFileAtPath: launchTunnelblickSymlink handler: nil];
            [fileManager createSymbolicLinkAtPath: launchTunnelblickSymlink
                                      pathContent: pathToThisApp];
        }
    }
    
    if (  button == NSAlertOtherReturn  ) { // CREATE CONFIGURATION FOLDER (already created)
        [[NSWorkspace sharedWorkspace] openFile: configDirPath];
        [NSApp setAutoLaunchOnLogin: NO];
        [NSApp terminate: nil];
    }
    
    NSString * targetPath = [configDirPath stringByAppendingPathComponent:@"openvpn.conf"];
    NSLog(@"Installing sample configuration file %@", targetPath);
    if (  ! [fileManager copyPath: openvpnConfPath toPath: targetPath handler: nil]  ) {
        NSLog(@"Installation failed. Not able to copy openvpn.conf to %@", configDirPath);
        TBRunAlertPanel(NSLocalizedString(@"Installation failed", @"Window title"),
                        [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not copy openvpn.conf to %@", @"Window text"),
                         [[fileManager componentsToDisplayForPath: configDirPath] componentsJoinedByString: @"/"]],
                        nil,
                        nil,
                        nil);
        [NSApp setAutoLaunchOnLogin: NO];
        [NSApp terminate: nil];
    }
    
    [[NSWorkspace sharedWorkspace] openFile: targetPath withApplication: @"TextEdit"];
    
    ignoreNoConfigs = FALSE;    // Go back to checking for no configuration files
}

-(IBAction)editConfig:(id)sender
{
	VPNConnection *connection = [self selectedConnection];
	NSString *configFilename = [connection configFilename];
    if(configFilename == nil) configFilename = @"/openvpn.conf";
    NSString * targetPath = [configDirPath stringByAppendingPathComponent: configFilename];

    // To allow Tiger and Leopard users to edit and save a configuration file, we allow the user to unprotect the file before editing. 
    // This is because, although on Snow Leoapard TextEdit can save the file (the new file will be owned by the current user, with 644 permissions),
    // on Tiger and Leopard TextEdit cannot save a file if it is protected (owned by root with 644 permissions).
    if (  connection  ) {
        NSFileManager  * fileManager = [NSFileManager defaultManager];
        if (  [fileManager fileExistsAtPath: targetPath]  ) {           // Must check that file exists because isWritableAtPath returns NO if the file doesn't exist
            if (  ! [fileManager isWritableFileAtPath: targetPath]  ) {
                if (  runningOnSnowLeopardOrNewer()  ) {
                    int button = TBRunAlertPanelExtended(NSLocalizedString(@"The configuration file is protected", @"Window title"),
                                                         NSLocalizedString(@"If you modify the configuration file, you will need to provide an administrator username and password the next time you connect using it.", @"Window text"),
                                                         NSLocalizedString(@"Edit configuration", @"Button"),   // Default button
                                                         NSLocalizedString(@"Cancel", @"Button"),               // Alternate button
                                                         nil,                                                   // Other button
                                                         @"skipWarningAboutReprotectingConfigurationFile",      // Preference about seeing this message again
                                                         NSLocalizedString(@"Do not warn about this again", @"Checkbox text"),
                                                         nil);
                    if (  button == NSAlertAlternateReturn  ) {
                        return;
                    }
                } else {
                    if (  userIsAnAdmin || ( ! [gTbDefaults boolForKey: @"onlyAdminsCanUnprotectConfigurationFiles"] )  ) {
                        // Ask if user wants to unprotect the configuration file
                        int button = TBRunAlertPanel(NSLocalizedString(@"The configuration file is protected", @"Window title"),
                                                     NSLocalizedString(@"You may examine the configuration file, but if you plan to modify it, you must unprotect it now. If you unprotect the configuration file now, you will need to provide an administrator username and password the next time you connect using it.", @"Window text"),
                                                     NSLocalizedString(@"Examine", @"Button"),              // Default button
                                                     NSLocalizedString(@"Unprotect and Modify", @"Button"), // Alternate button
                                                     NSLocalizedString(@"Cancel", @"Button"));              // Other button
                        if (  button == NSAlertOtherReturn  ) {
                            return;
                        }
                        if (  button == NSAlertAlternateReturn  ) {
                            if (  ! [connection unprotectConfigurationFile: targetPath]  ) {
                                int button = TBRunAlertPanel(NSLocalizedString(@"Examine the configuration file?", @"Window title"),
                                                             NSLocalizedString(@"Tunnelblick could not unprotect the configuration file. Details are in the Console Log.\n\nDo you wish to examine the configuration file even though you will not be able to modify it?", @"Window text"),
                                                             NSLocalizedString(@"Cancel", @"Button"),    // Default button
                                                             NSLocalizedString(@"Examine", @"Button"),   // Alternate button
                                                             nil);
                                if (  button != NSAlertAlternateReturn  ) {
                                    return;
                                }
                            }
                        }
                    } else {
                        // User is only allowed to examine the configuration file
                        int button = TBRunAlertPanelExtended(NSLocalizedString(@"The configuration file is protected", @"Window title"),
                                                             NSLocalizedString(@"You may examine the configuration file, but you will not be allowed to modify it.", @"Window text"),
                                                             NSLocalizedString(@"Examine", @"Button"),          // Default button
                                                             NSLocalizedString(@"Cancel", @"Button"),           // Alternate button
                                                             nil,                                               // Other button
                                                             @"skipWarningThatCannotModifyConfigurationFile",   // Preference about seeing this message again
                                                             NSLocalizedString(@"Do not warn about this again", @"Checkbox text"),
                                                             nil);
                        if (  button == NSAlertAlternateReturn  ) {
                            return;
                        }
                    }                    
                }
            }
        }
            
        [[NSWorkspace sharedWorkspace] openFile: targetPath withApplication: @"TextEdit"];
    }
}

- (void) networkConfigurationDidChange
{
	if (NSDebugEnabled) NSLog(@"Got networkConfigurationDidChange notification!!");
	[self resetActiveConnections];
}

- (void) applicationWillTerminate: (NSNotification*) notification 
{	
    if (NSDebugEnabled) NSLog(@"App will terminate");
	[self cleanup];
}

-(void)cleanup 
{
	[NSApp callDelegateOnNetworkChange: NO];
	[self killAllConnections];
	[self killAllOpenVPN];  // Kill any OpenVPN processes that still exist
    [self destroyAllPipes];
    [self unloadKexts];     // Unload tun.kext and tap.kext
	if (  theItem  ) {
        [[NSStatusBar systemStatusBar] removeStatusItem:theItem];
    }
}

-(void)saveMonitorConnectionCheckboxState:(BOOL)inBool
{
	VPNConnection* connection = [self selectedConnection];
	if(connection != nil) {
		NSString* key = [[connection configName] stringByAppendingString: @"-notMonitoringConnection"];
		[gTbDefaults setObject: [NSNumber numberWithBool: ! inBool] forKey: key];
		[gTbDefaults synchronize];
        if (  ! [connection isDisconnected]  ) {
            TBRunAlertPanel(@"Configuration Change", @"The change will take effect the next time you connect.", nil, nil, nil);
        }
	}
	
}
-(void)saveUseNameserverCheckboxState:(BOOL)inBool
{
	VPNConnection* connection = [self selectedConnection];
	if(connection != nil) {
		NSString* key = [[connection configName] stringByAppendingString: @"useDNS"];
		[gTbDefaults setObject: [NSNumber numberWithBool: inBool] forKey: key];
		[gTbDefaults synchronize];
        if (  ! [connection isDisconnected]  ) {
            TBRunAlertPanel(@"Configuration Change", @"The change will take effect the next time you connect.", nil, nil, nil);
        }
	}
	
}
-(void)saveAutoLaunchCheckboxState:(BOOL)inBool
{
	VPNConnection* connection = [self selectedConnection];
	if(connection != nil) {
		NSString* autoConnectKey = [[connection configName] stringByAppendingString: @"autoConnect"];
		[gTbDefaults setObject: [NSNumber numberWithBool: inBool] forKey: autoConnectKey];
		[gTbDefaults synchronize];
	}
	
}

-(BOOL)getCurrentAutoLaunchSetting
{
	VPNConnection *connection = [self selectedConnection];
	NSString *autoConnectKey = [[connection configName] stringByAppendingString:@"autoConnect"];
	return [gTbDefaults boolForKey:autoConnectKey];
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
        printf("SIGHUP received. Restarting active connections\n");
        [[NSApp delegate] resetActiveConnections];
    } else  {
        printf("Received fatal signal. Cleaning up\n");
        [NSApp setAutoLaunchOnLogin: NO];
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
    [NSThread detachNewThreadSelector:@selector(moveSoftwareUpdateWindowToForegroundThread) toTarget:self withObject:nil];
}

-(void) dmgCheck
{
    [NSApp setAutoLaunchOnLogin: NO];
    
	NSString * currentPath = [[NSBundle mainBundle] bundlePath];
	if (  [currentPath hasPrefix:@"/Volumes/Tunnelblick"]  ) {
        
        NSString * appVersion   = tunnelblickVersion([NSBundle mainBundle]);
        
        NSFileManager * fMgr = [NSFileManager defaultManager];
        
        NSString * standardPath;
        
        // Use a standardPath of /Applications/Tunnelblick.app unless overridden by a forced preference
        NSString * deployDirPath = [currentPath stringByAppendingPathComponent: @"Contents/Resources/Deploy"];
        NSDictionary * forcedDefaults = [NSDictionary dictionaryWithContentsOfFile: [deployDirPath stringByAppendingPathComponent: @"forced-preferences.plist"]];
        standardPath = @"/Applications/Tunnelblick.app";
        id obj = [forcedDefaults objectForKey:@"standardApplicationPath"];
        if (  obj  ) {
            if (  [[obj class] isSubclassOfClass: [NSString class]]  ) {
                standardPath = [obj stringByExpandingTildeInPath];
            } else {
                NSLog(@"'standardApplicationPath' preference ignored because it is not a string.");
            }
        }
        
        NSString * displayApplicationName = [fMgr displayNameAtPath: @"Tunnelblick.app"];
        
        NSString * standardFolder = [standardPath stringByDeletingLastPathComponent];
        
        NSString * standardPathDisplayName = [[fMgr componentsToDisplayForPath: standardPath] componentsJoinedByString: @"/"];
        
        NSString * standardFolderDisplayName = [[fMgr componentsToDisplayForPath: standardFolder] componentsJoinedByString: @"/"];
        
        NSString * launchWindowTitle;
        NSString * launchWindowText;
        int response;
        
        NSString * changeLocationText = [NSString stringWithFormat: NSLocalizedString(@"(To install to a different location, drag %@ to that location.)", @"Window text"), displayApplicationName];
        
        if (  [fMgr fileExistsAtPath: standardPath]  ) {
            NSBundle * previousBundle = [NSBundle bundleWithPath: standardPath];
            int previousBuild = [self intValueOfBuildForBundle: previousBundle];
            int currentBuild  = [self intValueOfBuildForBundle: [NSBundle mainBundle]];
            NSString * previousVersion = tunnelblickVersion(previousBundle);
            if (  currentBuild < previousBuild  ) {
                launchWindowTitle = NSLocalizedString(@"Downgrade succeeded", @"Window title");
                launchWindowText = NSLocalizedString(@"Tunnelblick was successfully downgraded.\n\nDo you wish to launch Tunnelblick now?\n\n(An administrator username and password will be required so Tunnelblick can be secured.)", @"Window text");
                response = TBRunAlertPanel(NSLocalizedString(@"Downgrade Tunnelblick?", @"Window title"),
                                           [NSString stringWithFormat: NSLocalizedString(@"Do you wish to downgrade\n     %@\nto\n     %@?\n\nThe replaced version will be put in the Trash.\n\nInstall location: \"%@\"\n%@", @"Window text"), previousVersion, appVersion, standardFolderDisplayName, changeLocationText],
                                           NSLocalizedString(@"Downgrade", @"Button"),  // Default button
                                           NSLocalizedString(@"Cancel", @"Button"),     // Alternate button
                                           nil);                                        // Other button
            } else if (  currentBuild == previousBuild  ) {
                launchWindowTitle = NSLocalizedString(@"Reinstallation succeeded", @"Window title");
                launchWindowText = NSLocalizedString(@"Tunnelblick was successfully reinstalled.\n\nDo you wish to launch Tunnelblick now?\n\n(An administrator username and password will be required so Tunnelblick can be secured.)", @"Window text");
                response = TBRunAlertPanel(NSLocalizedString(@"Reinstall Tunnelblick?", @"Window title"),
                                           [NSString stringWithFormat: NSLocalizedString(@"Do you wish to reinstall\n     %@\nreplacing it with a fresh copy?\n\nThe old copy will be put in the Trash.\n\nInstall location: \"%@\"\n%@", @"Window text"), previousVersion, standardFolderDisplayName, changeLocationText],
                                           NSLocalizedString(@"Reinstall", @"Button"),  // Default button
                                           NSLocalizedString(@"Cancel", @"Button"),     // Alternate button
                                           nil);                                        // Other button
            } else {
                launchWindowTitle = NSLocalizedString(@"Upgrade succeeded", @"Window title");
                launchWindowText = NSLocalizedString(@"Tunnelblick was successfully upgraded.\n\nDo you wish to launch Tunnelblick now?\n\n(An administrator username and password will be required so Tunnelblick can be secured.)", @"Window text");
                previousVersion = tunnelblickVersion(previousBundle);
                response = TBRunAlertPanel(NSLocalizedString(@"Upgrade Tunnelblick?", @"Window title"),
                                           [NSString stringWithFormat: NSLocalizedString(@"Do you wish to upgrade\n     %@\nto\n     %@?\n\nThe old version will be put in the Trash.\n\nInstall location: \"%@\"\n%@", @"Window text"), previousVersion, appVersion, standardFolderDisplayName, changeLocationText],
                                           NSLocalizedString(@"Upgrade", @"Button"),    // Default button
                                           NSLocalizedString(@"Cancel", @"Button"),     // Alternate button
                                           nil);                                        // Other button
            }
        } else {
            launchWindowTitle = NSLocalizedString(@"Installation succeeded", @"Window title");
            launchWindowText = NSLocalizedString(@"Tunnelblick was successfully installed.\n\nDo you wish to launch Tunnelblick now?\n\n(An administrator username and password will be required so Tunnelblick can be secured.)", @"Window text");
            response = TBRunAlertPanel(NSLocalizedString(@"Install Tunnelblick?", @"Window title"),
                                       [NSString stringWithFormat: NSLocalizedString(@"Do you wish to install Tunnelblick in\n\"%@\"?\n\n%@", @"Window text"), standardFolderDisplayName, changeLocationText],
                                       NSLocalizedString(@"Install", @"Button"),    // Default button
                                       NSLocalizedString(@"Cancel", @"Button"),     // Alternate button
                                       nil);                                        // Other button
        }
        
        if (  response == NSAlertDefaultReturn  ) {
            
            // Install, Reinstall, Upgrade, or Downgrade
            if (  [fMgr fileExistsAtPath: standardPath]  ) {
                int tag;
                if (  [[NSWorkspace sharedWorkspace] performFileOperation: NSWorkspaceRecycleOperation source: standardFolder destination: standardFolder files: [NSArray arrayWithObject: [standardPath lastPathComponent]] tag: &tag]  ) {
                    NSLog(@"Moved %@ to Trash", standardPath);
                }
            }
            
            if (  [fMgr fileExistsAtPath: standardPath]  ) {
                NSLog(@"Unable to move %@ to Trash", standardPath);
                TBRunAlertPanel(NSLocalizedString(@"Unable to move previous version to Trash", @"Window title"),
                                [NSString stringWithFormat: NSLocalizedString(@"An error occurred while trying to move the previous version of %@ to the Trash.\n\nThe previous version is %@", @"Window text"), displayApplicationName, standardPathDisplayName],
                                NSLocalizedString(@"Cancel", @"Button"),                // Default button
                                nil,
                                nil);
            } else {
                if (  ! [fMgr copyPath: currentPath toPath: standardPath handler: nil]  ) {
                    NSLog(@"Unable to copy %@ to %@", currentPath, standardPath);
                    TBRunAlertPanel(NSLocalizedString(@"Unable to install Tunnelblick", @"Window title"),
                                    [NSString stringWithFormat: NSLocalizedString(@"An error occurred while trying to install Tunnelblick.app in %@", @"Window text"), standardPathDisplayName],
                                    NSLocalizedString(@"Cancel", @"Button"),                // Default button
                                    nil,
                                    nil);
                } else {
                    NSLog(@"Copied %@ to %@", currentPath, standardPath);
                    response = TBRunAlertPanel(launchWindowTitle,
                                               launchWindowText,
                                               NSLocalizedString(@"Launch", "Button"), // Default button
                                               NSLocalizedString(@"Quit", "Button"), // Alternate button
                                               nil);
                    if (  response == NSAlertDefaultReturn  ) {
                        
                        // Stop any currently running Tunnelblicks
                        int numberOfOthers = [NSApp countOtherInstances];
                        while (  numberOfOthers > 0  ) {
                            int button = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick is currently running", @"Window title"),
                                                         NSLocalizedString(@"You must stop the currently running Tunnelblick to launch the new copy.\n\nClick \"Close VPN Connections and Stop Tunnelblick\" to close all VPN connections and quit the currently running Tunnelblick before launching Tunnelblick.", @"Window text"),
                                                         NSLocalizedString(@"Close VPN Connections and Stop Tunnelblick", @"Button"), // Default button
                                                         NSLocalizedString(@"Cancel",  @"Button"),   // Alternate button
                                                         nil);
                            if (  button == NSAlertAlternateReturn  ) {
                                [NSApp terminate: nil];
                            }
                            
                            [NSApp killOtherInstances];
                            
                            numberOfOthers = [NSApp countOtherInstances];
                            if (  numberOfOthers > 0  ) {
                                int i = 0;
                                do {
                                    sleep(1);
                                    i++;
                                    numberOfOthers = [NSApp countOtherInstances];
                                } while (  (numberOfOthers > 0) && (i < 10)  );
                            }
                        }
                        
                        // If there was a problem finding other instances of Tunnelblick, log it but continue anyway
                        if (  numberOfOthers == -1  ) {
                            NSLog(@"Error: [NSApp countOtherInstances] returned -1");
                        }
                        
                        // Launch the new copy
                        if (  ! [[NSWorkspace sharedWorkspace] launchApplication: standardPath]  ) {
                            TBRunAlertPanel(NSLocalizedString(@"Unable to launch Tunnelblick", @"Window title"),
                                            [NSString stringWithFormat: NSLocalizedString(@"An error occurred while trying to launch %@", @"Window text"), standardPathDisplayName],
                                            NSLocalizedString(@"Cancel", @"Button"),                // Default button
                                            nil,
                                            nil);
                        }
                    } else {
                        if (  [NSApp countOtherInstances]  ) {
                            TBRunAlertPanel(NSLocalizedString(@"Warning", @"Window title"),
                                            NSLocalizedString(@"You are currently running a different copy of Tunnelblick.", @"Window text"),
                                            nil, nil, nil);
                        }
                    }

                }
            }
        }
        
        [NSApp terminate: nil];
    }
}

-(int)intValueOfBuildForBundle: (NSBundle *) theBundle
{
    int result = 0;
    id tmp = [theBundle objectForInfoDictionaryKey:@"Build"];
    if (  tmp  ) {
        if (  [[tmp class] isSubclassOfClass: [NSString class]]  ) {
            NSString * tmpString = tmp;
            result = [tmpString intValue];
        } else if (  [[tmp class] isSubclassOfClass: [NSNumber class]] ) {
            NSNumber * tmpNumber = tmp;
            result = [tmpNumber intValue];
        }
    }
    
    return result;
}

-(void)moveSoftwareUpdateWindowToForeground
{
    NSArray *windows = [NSApp windows];
    NSEnumerator *e = [windows objectEnumerator];
    NSWindow *window = nil;
    while(window = [e nextObject]) {
    	if (  [[window title] isEqualToString:@"Software Update"]  ) {
            [window makeKeyAndOrderFront: self];
            [window setLevel:NSStatusWindowLevel];
            [NSApp activateIgnoringOtherApps:YES]; // Force Software update window to front
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

// Runs the installer to backup/restore Resources/Deploy and/or repair ownership/permissions of critical files and/or move the config folder
// restore    should be TRUE if Resources/Deploy should be restored from its backup
// repairIt   should be TRUE if needsRepair() returned TRUE
// removeBkup should be TRUE if the backup of Resources/Deploy should be removed
// moveIt     should be TRUE if /Library/openvpn needs to be moved to /Library/Application Support/Tunnelblick/Configurations
// Returns TRUE if ran successfully, FALSE if failed
-(BOOL) runInstallerRestoreDeploy: (BOOL) restore repairApp: (BOOL) repairIt removeBackup: (BOOL) removeBkup moveLibraryOpenVPN: (BOOL) moveConfigs
{
	NSBundle *thisBundle = [NSBundle mainBundle];
	NSString *installer = [thisBundle pathForResource:@"installer" ofType:nil];
	AuthorizationRef authRef;

    NSMutableArray * args = [[[NSMutableArray alloc] initWithCapacity:3] autorelease];
    
    NSString * msg;
    
    int code = 0;
    if (restore    ) code = code + 1;
    if (repairIt   ) code = code + 2;
    if (removeBkup ) code = code + 4;
    if (moveConfigs) code = code + 8;

    switch (  code  ) {
        case 1:
            msg = NSLocalizedString(@"Tunnelblick needs to restore configuration(s) from the backup.", @"Window text");
            break;
        case 2:
            msg = NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the program.", @"Window text");
            break;
        case 3:
            msg = NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the program and restore configuration(s) from the backup.", @"Window text");
            break;
        case 4:
            msg = NSLocalizedString(@"Tunnelblick needs to remove the configuration(s) backup.", @"Window text");
            break;
        case 5:
            msg = NSLocalizedString(@"Tunnelblick needs to restore configuration(s) from the backup and then remove the backup.", @"Window text");
            break;
        case 6:
            msg = NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the program and remove the configuration(s) backup.", @"Window text");
            break;
        case 7:
            msg = NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the program, restore configuration(s) from the backup, and remove the backup.", @"Window text");
            break;
        case 8:
            msg = NSLocalizedString(@"Tunnelblick needs to move the configurations folder.", @"Window text");
            break;
        case 9:
            msg = NSLocalizedString(@"Tunnelblick needs to restore configuration(s) from the backup and move the configurations folder.", @"Window text");
            break;
        case 10:
            msg = NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the program and move the configurations folder.", @"Window text");
            break;
        case 11:
            msg = NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the program, restore configuration(s) from the backup, and move the configurations folder.", @"Window text");
            break;
        case 12:
            msg = NSLocalizedString(@"Tunnelblick needs to move the configurations folder and remove the configuration(s) backup.", @"Window text");
            break;
        case 13:
            msg = NSLocalizedString(@"Tunnelblick needs to restore configuration(s) from the backup, remove the backup, and move the configurations folder.", @"Window text");
            break;
        case 14:
            msg = NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the program, remove the backup of configuration(s), and move the configurations folder.", @"Window text");
            break;
        case 15:
            msg = NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the program, restore configuration(s) from the backup, remove the backup, and move the configurations folder.", @"Window text");
            break;
        default:
            msg = @"";
            break;
    }
    
    if (  restore  ) {
        [args addObject: @"1"];
    } else {
        [args addObject: @"0"];
    }
    if (  repairIt || moveConfigs  ) {
        [args addObject:@"1"];
    } else {
        [args addObject:@"0"];
    }
    if (  removeBkup  ) {
        [args addObject:@"1"];
    } else {
        [args addObject:@"0"];
    }
    
    NSLog(msg);
    
    // Get an AuthorizationRef and use executeAuthorized to run the installer
    authRef= [NSApplication getAuthorizationRef: msg];
    if(authRef == nil) {
        NSLog(@"Installation or repair cancelled");
        return FALSE;
    }
    
    int i = 5;
    NSFileManager * fMgr = [NSFileManager defaultManager];
    OSStatus status;
    BOOL installFailed;
    BOOL needsChangeOwnershipAndOrPermissions;
    BOOL needsMoveLibraryOpenVPN;
    do {
        if (  i != 5  ) {
            sleep(1);
        }
        status = [NSApplication executeAuthorized: installer withArguments: args withAuthorizationRef: authRef];
        installFailed = [fMgr fileExistsAtPath: @"/tmp/TunnelblickInstallationFailed.txt"];
        if (  installFailed  ) {
            [fMgr removeFileAtPath: @"/tmp/TunnelblickInstallationFailed.txt" handler: nil];
        }
    } while (  needsInstallation( &needsChangeOwnershipAndOrPermissions, &needsMoveLibraryOpenVPN )  && (i-- > 0)  );
    
    AuthorizationFree(authRef, kAuthorizationFlagDefaults);
    
    if (  (status != EXIT_SUCCESS) || installFailed || (  (i < 0) && needsInstallation( &needsChangeOwnershipAndOrPermissions, &needsMoveLibraryOpenVPN )  )  ) {
        NSLog(@"Installation or repair failed");
        TBRunAlertPanel(NSLocalizedString(@"Installation or Repair Failed", "Window title"),
                        NSLocalizedString(@"The installation, removal, recovery, or repair of one or more Tunnelblick components failed. See the Console Log for details.", "Window text"),
                        nil,
                        nil,
                        nil);
        return FALSE;
    }
    
    NSLog(@"Installation or repair succeded");
    return TRUE;
}

// Checks ownership and permissions of critical files and whether ~/Library/openvpn has been moved to ~/Library/Application Support/Tunnelblick/Configurations (for 3.0b24)
// Returns with the respective arguments set YES or NO, and returns YES if either one is YES. Otherwise returns NO.
BOOL needsInstallation(BOOL * changeOwnershipAndOrPermissions, BOOL * moveLibraryOpenVPN) 
{
    // Check that the configuration folder has been moved. If not, return YES
    NSString * oldConfigDirPath = [NSHomeDirectory() stringByAppendingPathComponent: @"Library/openvpn"];
    NSString * newParentDirPath = [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Application Support/Tunnelblick"];
    NSString * newConfigDirPath = [newParentDirPath stringByAppendingPathComponent: @"Configurations"];
    BOOL isDir;
    BOOL newFolderExists = FALSE;
    BOOL newParentExists = FALSE;
    
    *changeOwnershipAndOrPermissions = FALSE;
    *moveLibraryOpenVPN = FALSE;
    
    NSFileManager * fMgr = [NSFileManager defaultManager];
    
    // Check ~/Library/Application Support/Tunnelblick/Configurations
    if (  [fMgr fileExistsAtPath: newParentDirPath isDirectory: &isDir]  ) {
        newParentExists = TRUE;
        if (  isDir  ) {
            if (  [fMgr fileExistsAtPath: newConfigDirPath isDirectory: &isDir]  ) {
                if (  isDir  ) {
                    newFolderExists = TRUE; // New folder exists, so we've already moved (check that's true below)
                } else {
                    NSLog(@"Error: %@ exists but is not a folder", newConfigDirPath);
                    terminateBecauseOfBadConfiguration();
                }
            } else {
                // New folder does not exist. That's OK if ~/Library/openvpn doesn't exist
            }
        } else {
            NSLog(@"Error: %@ exists but is not a folder", newParentDirPath);
            terminateBecauseOfBadConfiguration();
        }
    } else {
        // New folder's holder does not exist, so we need to do the move only if ~Library/openvpn exists and is a folder (which we check for below)
    }
    
    // If it exists, ~/Library/openvpn must either be a directory, or a symbolic link to ~/Library/Application Support/Tunnelblick/Configurations
    NSDictionary * fileAttributes = [fMgr fileAttributesAtPath: oldConfigDirPath traverseLink: NO];
    if (  ! [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
        if (  [fMgr fileExistsAtPath: oldConfigDirPath isDirectory: &isDir]  ) {
            if (  isDir  ) {
                if (  newFolderExists  ) {
                    NSLog(@"Error: Both %@ and %@ exist and are folders, so %@ cannot be moved", oldConfigDirPath, newConfigDirPath, oldConfigDirPath);
                    terminateBecauseOfBadConfiguration();
                } else {
                    if (  newParentExists  ) {
                        NSLog(@"Error: %@ exists and is a folder, but %@ already exists, so %@ cannot be moved", oldConfigDirPath, newParentDirPath, oldConfigDirPath);
                        terminateBecauseOfBadConfiguration();
                    }
                    *moveLibraryOpenVPN = YES;  // old folder exists, but new one doesn't, so do the move
                }
            } else {
                NSLog(@"Error: %@ exists but is not a symbolic link or a folder", oldConfigDirPath);
                terminateBecauseOfBadConfiguration();
            }
        } else {
            // ~/Library/openvpn does not exist, so we don't do the move (whether or not the new folder exists)
        }
    } else {
        // ~/Library/openvpn is a symbolic link
        if (  [[fMgr pathContentOfSymbolicLinkAtPath: oldConfigDirPath] isEqualToString: newConfigDirPath]  ) {
            if (  newFolderExists  ) {
                // ~/Library/openvpn is a symbolic link to ~/Library/Application Support/Tunnelblick/Configurations, which exists, so we've already done the move
            } else {
                NSLog(@"Error: %@ exists and is a symbolic link but its target, %@, does not exist", oldConfigDirPath, newConfigDirPath);
                terminateBecauseOfBadConfiguration();
            }
        } else {
            NSLog(@"Error: %@ exists and is a symbolic link but does not reference %@", oldConfigDirPath, newConfigDirPath);
            terminateBecauseOfBadConfiguration();
        }
    }
    
	// Check ownership and permissions on components of Tunnelblick.app
    NSBundle *thisBundle = [NSBundle mainBundle];
	
	NSString *installerPath         = [thisBundle pathForResource:@"intaller"                       ofType:nil];
	NSString *openvpnstartPath      = [thisBundle pathForResource:@"openvpnstart"                   ofType:nil];
	NSString *openvpnPath           = [thisBundle pathForResource:@"openvpn"                        ofType:nil];
	NSString *leasewatchPath        = [thisBundle pathForResource:@"leasewatch"                     ofType:nil];
	NSString *clientUpPath          = [thisBundle pathForResource:@"client.up.osx.sh"               ofType:nil];
	NSString *clientDownPath        = [thisBundle pathForResource:@"client.down.osx.sh"             ofType:nil];
	NSString *clientNoMonUpPath     = [thisBundle pathForResource:@"client.nomonitor.up.osx.sh"     ofType:nil];
	NSString *clientNoMonDownPath   = [thisBundle pathForResource:@"client.nomonitor.down.osx.sh"   ofType:nil];
	
	// check openvpnstart owned by root, set uid, owner may execute
	const char *path = [openvpnstartPath UTF8String];
    struct stat sb;
	if(stat(path,&sb)) {
        runUnrecoverableErrorPanel(@"Unable to determine status of \"openvpnstart\"");
	}
    
	if ( !( (sb.st_mode & S_ISUID) // set uid bit is set
		 && (sb.st_mode & S_IXUSR) // owner may execute it
		 && (sb.st_uid == 0) // is owned by root
		)) {
		NSLog(@"openvpnstart has missing set uid bit, is not owned by root, or owner can't execute it");
        *changeOwnershipAndOrPermissions = YES;
		return YES;		
	}
	
	// check files which should be owned by root with 744 permissions
	NSArray *inaccessibleObjects = [NSArray arrayWithObjects: installerPath, openvpnPath, leasewatchPath, clientUpPath, clientDownPath, clientNoMonUpPath, clientNoMonDownPath, nil];
	NSEnumerator *e = [inaccessibleObjects objectEnumerator];
	NSString *currentPath;
	while(currentPath = [e nextObject]) {
        if (  ! isOwnedByRootAndHasPermissions(currentPath, @"744")  ) {
            *changeOwnershipAndOrPermissions = YES;
            return YES; // NSLog already called
        }
	}
    
    // check permissions of files in Resources/Deploy (if any)        
    NSString * deployDirPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent: @"Contents/Resources/Deploy"];
    if (  deployContentsOwnerOrPermissionsNeedRepair(deployDirPath)  ) {
        *changeOwnershipAndOrPermissions = YES;
        return YES;
    }
    
    // check permissions of files in the Deploy backup, also (if any)        
    NSString * deployBackupPath = [[[[@"/Library/Application Support/Tunnelblick/Backup" stringByAppendingPathComponent: [[NSBundle mainBundle] bundlePath]]
                                     stringByDeletingLastPathComponent]
                                    stringByAppendingPathComponent: @"TunnelblickBackup"]
                                   stringByAppendingPathComponent: @"Deploy"];
    
    if (  deployContentsOwnerOrPermissionsNeedRepair(deployBackupPath)  ) {
        *changeOwnershipAndOrPermissions = YES;
        return YES;
    }
    
    return *moveLibraryOpenVPN;
}

void terminateBecauseOfBadConfiguration(void)
{
    TBRunAlertPanel(NSLocalizedString(@"Tunnelblick Configuration Problem", @"Window title"),
                    NSLocalizedString(@"Tunnelblick could not be launched because of a problem with the configuration. Please examine the Console Log for details.", @"Window text"),
                    nil, nil, nil);
    [NSApp setAutoLaunchOnLogin: NO];
    [NSApp terminate: nil];
}
BOOL deployContentsOwnerOrPermissionsNeedRepair(NSString * deployDirPath)
{
    NSArray * extensionsFor600Permissions = [NSArray arrayWithObjects: @"cer", @"crt", @"der", @"key", @"p12", @"p7b", @"p7c", @"pem", @"pfx", nil];
    NSArray *dirContents = [[NSFileManager defaultManager] directoryContentsAtPath: deployDirPath];
    int i;
    
    for (i=0; i<[dirContents count]; i++) {
        NSString * file = [dirContents objectAtIndex: i];
        NSString * filePath = [deployDirPath stringByAppendingPathComponent: file];
        NSString * ext  = [file pathExtension];
        if ( [ext isEqualToString:@"sh"]  ) {
            if (  ! isOwnedByRootAndHasPermissions(filePath, @"744")  ) {
                return YES; // NSLog already called
            }
        } else if (  [extensionsFor600Permissions containsObject: ext]  ) {
            if (  ! isOwnedByRootAndHasPermissions(filePath, @"600")  ) {
                return YES; // NSLog already called
            }
        } else { // including .conf and .ovpn
            if (  ! isOwnedByRootAndHasPermissions(filePath, @"644")  ) {
                return YES; // NSLog already called
            }
        }
    }
    return NO;
}
BOOL isOwnedByRootAndHasPermissions(NSString * fPath, NSString * permsShouldHave)
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *fileAttributes = [fileManager fileAttributesAtPath:fPath traverseLink:YES];
    unsigned long perms = [fileAttributes filePosixPermissions];
    NSString *octalString = [NSString stringWithFormat:@"%o",perms];
    NSNumber *fileOwner = [fileAttributes fileOwnerAccountID];
    
    if (  [octalString isEqualToString: permsShouldHave] && [fileOwner isEqualToNumber:[NSNumber numberWithInt:0]]  ) {
        return YES;
    }
    
    NSLog(@"File %@ has permissions: %@, is owned by %@ and needs repair",fPath,octalString,fileOwner);
    return NO;
}

-(void)willGoToSleep
{
	if(NSDebugEnabled) NSLog(@"Computer will go to sleep");
	connectionsToRestore = [connectionArray mutableCopy];
	[self killAllConnections];
	[self killAllOpenVPN];  // Kill any OpenVPN processes that still exist
}
-(void)wokeUpFromSleep 
{
	if(NSDebugEnabled) NSLog(@"Computer just woke up from sleep");
	
	NSEnumerator *e = [connectionsToRestore objectEnumerator];
	VPNConnection *connection;
	while(connection = [e nextObject]) {
		if(NSDebugEnabled) NSLog(@"Restoring Connection %@",[connection configName]);
		[connection connect:self];
	}
}
int runUnrecoverableErrorPanel(msg) 
{
	int result = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick Error", @"Window title"),
                                 [NSString stringWithFormat: NSLocalizedString(@"You must reinstall Tunnelblick. Please move Tunnelblick to the Trash and download a fresh copy. The problem was:\n\n%@", @"Window text"),
                                                                               msg],
                                 NSLocalizedString(@"Download", @"Button"),
                                 NSLocalizedString(@"Quit", @"Button"),
                                 nil);
	if( result == NSAlertDefaultReturn ) {
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://tunnelblick.net/"]];
	}
    exit(2);
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
    [self validateLogButtons];
}

-(IBAction) monitorConnectionPrefButtonWasClicked: (id) sender
{
	if([sender state]) {
		[self saveMonitorConnectionCheckboxState:TRUE];
	} else {
		[self saveMonitorConnectionCheckboxState:FALSE];
	}
}

@end
