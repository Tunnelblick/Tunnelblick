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
#import <uuid/uuid.h>
#include <sys/mount.h>
#import "KeyChain.h"
#import "NetSocket.h"
#import "NSApplication+LoginItem.h"
#import "NSApplication+NetworkNotifications.h"
#import "NSApplication+SystemVersion.h"
#import "helper.h"
#import "TBUserDefaults.h"

extern NSMutableArray  * gConfigDirs;
extern NSString        * gDeployPath;
extern NSString        * gSharedPath;
extern NSFileManager   * gFileMgr;
extern TBUserDefaults  * gTbDefaults;

extern NSString * firstPartOfPath(NSString * thePath);
extern NSString * lastPartOfPath(NSString * thePath);

@interface NSStatusBar (NSStatusBar_Private)
- (id)_statusItemWithLength:(float)l withPriority:(int)p;
- (id)_insertStatusItem:(NSStatusItem *)i withPriority:(int)p;
@end

@interface MenuController() // PRIVATE METHODS
-(void)             activateStatusMenu;
-(void)             addNewConfig:                           (NSString *)        path
                 withDisplayName:                           (NSString *)        dispNm;
-(BOOL)             appNameIsTunnelblickWarnUserIfNot:      (BOOL)              tellUser;
-(BOOL)             cannotRunFromVolume:                    (NSString *)        path;
-(void)             createDefaultConfigUsingTitle:          (NSString *)        ttl
                                       andMessage:          (NSString *)        msg;
-(void)             createMenu;
-(void)             createStatusItem;
-(void)             deleteExistingConfig:                   (NSString *)        dispNm;
-(void)             destroyAllPipes;
-(void)             dmgCheck;
-(void)             fileSystemHasChanged:                   (NSNotification *)  n;
-(BOOL)             folderContentsNeedToBeSecuredAtPath:    (NSString *)        theDirPath;
-(NSMutableDictionary *) getConfigurations;
-(NSMenuItem *)     initPrefMenuItemWithTitle:              (NSString *)        title
                                    andAction:              (SEL)               action
                                   andToolTip:              (NSString *)        tip
                           atIndentationLevel:              (int)               indentLevel
                             andPreferenceKey:              (NSString *)        prefKey
                                      negated:              (BOOL)              negatePref;
-(void)             initialiseAnim;
-(NSString *)       installationId;
-(int)              intValueOfBuildForBundle:               (NSBundle *)        theBundle;
-(BOOL)             isOwnedByRootAtPath:                    (NSString *)        fPath
                        withPermissions:                    (NSString *)        permsShouldHave;
-(void)             killAllConnections;
-(void)             loadMenuIconSet;
-(void)             loadKexts; 
-(void)             localizeControl:                        (NSButton *)        button       
                         shiftRight:                        (NSButton *)        buttonToRight
                          shiftLeft:                        (NSButton *)        buttonToLeft
                      shiftSelfLeft:                        (BOOL)              shiftSelfLeft;
-(BOOL)             needsInstallation:                      (BOOL *)            changeOwnershipAndOrPermissions
                          moveLibrary:                      (BOOL *)            moveLibraryOpenVPN;
-(BOOL)             runInstallerRestoreDeploy:              (BOOL)              restore
                                    repairApp:              (BOOL)              repairIt
                                 removeBackup:              (BOOL)              removeBkup
                           moveLibraryOpenVPN:              (BOOL)              moveConfigs;
-(void)             saveMonitorConnectionCheckboxState:     (BOOL)              inBool;
-(void)             saveAutoLaunchCheckboxState:            (BOOL)              inBool;
-(VPNConnection *)  selectedConnection;
-(NSTextView *)     selectedLogView;
-(void)             setupSparklePreferences;
-(void)             terminateBecauseOfBadConfiguration;
-(void)             toggleMenuItem:                         (NSMenuItem *)      item
                 withPreferenceKey:                         (NSString *)        prefKey;
-(void)             unloadKexts; 
-(void)             updateMenuAndLogWindow;
-(void)             updateTabLabels;
-(void)             updateUI;
-(void)             validateLogButtons;
-(BOOL)             validateMenuItem:                       (NSMenuItem *)      anItem;
-(void)             watcher:                                (UKKQueue *)        kq
       receivedNotification:                   (NSString *)        nm
                    forPath:                                (NSString *)        fpath;
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
        
        gFileMgr = [NSFileManager defaultManager];
        
        gDeployPath = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"Deploy"] copy];
        gSharedPath = [@"/Library/Application Support/Tunnelblick/Shared" copy];
        libraryPath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Tunnelblick/Configurations/"] copy];

		gConfigDirs = [[NSMutableArray alloc] initWithCapacity: 2];

		[NSApp setDelegate:self];
		
        [self dmgCheck];
		
        // Backup/restore Resources/Deploy and/or repair ownership and permissions if necessary
        NSString      * deployBackupPath = [[[[@"/Library/Application Support/Tunnelblick/Backup" stringByAppendingPathComponent: [[NSBundle mainBundle] bundlePath]]
                                              stringByDeletingLastPathComponent]
                                             stringByAppendingPathComponent: @"TunnelblickBackup"]
                                            stringByAppendingPathComponent: @"Deploy"];
        BOOL isDir;
        BOOL needsChangeOwnershipAndOrPermissions;
        BOOL needsMoveLibraryOpenVPN;
        BOOL haveDeploy   = [gFileMgr fileExistsAtPath: gDeployPath      isDirectory: &isDir]
                         && isDir;
        BOOL haveBackup   = [gFileMgr fileExistsAtPath: deployBackupPath isDirectory: &isDir]
                         && isDir;
        [self needsInstallation: &needsChangeOwnershipAndOrPermissions moveLibrary: &needsMoveLibraryOpenVPN];
        BOOL remove     = FALSE;   // Remove the backup of Resources/Deploy
        BOOL restore    = FALSE;   // Restore Resources/Deploy from backup

        if (   haveBackup
            && ( ! haveDeploy) ) {
            restore = TRUE;
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

        // Set up to override user preferences from Deploy/forced-permissions.plist if it exists,
        // Otherwise use our equivalent of [NSUserDefaults standardUserDefaults]
        NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: [gDeployPath stringByAppendingPathComponent: @"forced-preferences.plist"]];
        gTbDefaults = [[TBUserDefaults alloc] initWithDefaultsDictionary: dict];
        
        // Set default preferences as needed
        if (  [gTbDefaults objectForKey: @"showConnectedDurations"] == nil  ) {
            [gTbDefaults setBool: TRUE forKey: @"showConnectedDurations"];
        }
        
        // If Resources/Deploy exists now (perhaps after being restored) and has one or more .conf or .ovpn files,
        // Then add it to gConfigDirs
        if (   [gFileMgr fileExistsAtPath: gDeployPath isDirectory: &isDir]
            && isDir ) {
            NSString * file;
            NSDirectoryEnumerator *dirEnum = [gFileMgr enumeratorAtPath: gDeployPath];
            while (file = [dirEnum nextObject]) {
                NSString * ext  = [file pathExtension];
                if ( [ext isEqualToString:@"conf"] || [ext isEqualToString:@"ovpn"]  ) {
                    if (   [gFileMgr fileExistsAtPath: [gDeployPath stringByAppendingPathComponent: file] isDirectory: &isDir]
                        && ( ! isDir)  ) {
                        [gConfigDirs addObject: [gDeployPath copy]];
                        break;
                    }
                }
            }
        }
        
        // If not Deployed, or if Deployed and it is specifically allowed,
        // Then   add /Library/Application Support/Tunnelblick/Shared to gConfigDirs
        // and/or add ~/Library/Application Support/Tunnelblick/Configurations to gConfigDirs
        if (  [gConfigDirs count] != 0  ) {
            if (  ! [gTbDefaults canChangeValueForKey: @"useSharedConfigurationsWithDeployedOnes"]  ) {
                if (  [gTbDefaults boolForKey: @"useSharedConfigurationsWithDeployedOnes"]  ) {
                    [gConfigDirs addObject: [gSharedPath copy]];
                }
            }
            if (  ! [gTbDefaults canChangeValueForKey: @"useLibraryConfigurationsWithDeployedOnes"]  ) {
                if (  [gTbDefaults boolForKey: @"useLibraryConfigurationsWithDeployedOnes"]  ) {
                    [gConfigDirs addObject: [libraryPath copy]];
                }
            }
        } else {
            [gConfigDirs addObject: [gSharedPath copy]];
            [gConfigDirs addObject: [libraryPath copy]];
        }
        
        myVPNConnectionDictionary = [[NSMutableDictionary alloc] init];
        connectionArray = [[[NSMutableArray alloc] init] retain];
        
        [self loadMenuIconSet];
        
		[self createStatusItem];
		
		[self createMenu];
        [self setState: @"EXITING"]; // synonym for "Disconnected"
        
        if (  ! [gTbDefaults boolForKey: @"doNotCreateLaunchTunnelblickLinkinConfigurations"]  ) {
            if (  [gConfigDirs containsObject: libraryPath]  ) {
                if (   [gFileMgr fileExistsAtPath: libraryPath isDirectory: &isDir]
                    && isDir  ) {
                    NSString * pathToThisApp = [[NSBundle mainBundle] bundlePath];
                    NSString * launchTunnelblickSymlink = [libraryPath stringByAppendingPathComponent: @"Launch Tunnelblick"];
                    if (  ! [gFileMgr fileAttributesAtPath: launchTunnelblickSymlink traverseLink: NO]  ) {
                        NSLog(@"Creating 'Launch Tunnelblick' link in Configurations folder; links to %@", pathToThisApp);
                    } else if (  ! [[gFileMgr pathContentOfSymbolicLinkAtPath: launchTunnelblickSymlink] isEqualToString: pathToThisApp]  ) {
                        NSLog(@"Replacing 'Launch Tunnelblick' link in Configurations folder; now links to %@", pathToThisApp);
                        [gFileMgr removeFileAtPath: launchTunnelblickSymlink handler: nil];
                    }
                    [gFileMgr createSymbolicLinkAtPath: launchTunnelblickSymlink
                                       pathContent: pathToThisApp];
                }
            }
        }
        
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
		// Monitor each config folder if specified
        if (  ! [gTbDefaults boolForKey:@"doNotMonitorConfigurationFolder"]  ) {
            int i;
            myQueue = [UKKQueue sharedFileWatcher];
			for (i = 0; i < [gConfigDirs count]; i++) {
                [myQueue addPathToQueue: [gConfigDirs objectAtIndex: i]];
            }
            [myQueue setDelegate: self];
            [myQueue setAlwaysNotify: YES];
		}
        
		userIsAnAdmin = isUserAnAdmin();
		
        updater = [[SUUpdater alloc] init];
        
        [self loadKexts];
        
        // Process "Automatically connect on launch" checkboxes
        VPNConnection * myConnection;
        NSString * dispNm;
        NSEnumerator * e = [myConfigDictionary keyEnumerator];
        while (dispNm = [e nextObject]) {
            myConnection = [myVPNConnectionDictionary objectForKey: dispNm];
            if (  [gTbDefaults boolForKey: [dispNm stringByAppendingString: @"autoConnect"]]  ) {
                if (  ![myConnection isConnected]  ) {
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
    
	int i;
  	for(i = 0; i < [gConfigDirs count]; i++) {
        [[gConfigDirs objectAtIndex:i] release];
    }
    [gConfigDirs release];

    [gTbDefaults release];
    [connectionArray release];
    [connectionsToRestore release];
    [gDeployPath release];
    [lastState release];
    [libraryPath release];
    [myConfigDictionary release];
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

-(NSMutableDictionary *) myVPNConnectionDictionary
{
    return myVPNConnectionDictionary;
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
    NSDirectoryEnumerator *dirEnum = [gFileMgr enumeratorAtPath: confDir];
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

    // don't choke on a bad set of files, e.g., {0.png, 1abc.png, 2abc.png, 3.png, 4.png, 6.png}
    // (won't necessarily find all files, but won't try to load files that don't exist)
    for(i=0;i<nFrames;i++) {
        fullPath = [confDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.png", i]];
        if ([gFileMgr fileExistsAtPath:fullPath]) {
            NSImage *frame = [[NSImage alloc] initWithContentsOfFile:fullPath];
            [animImages addObject:frame];
            [frame release];
        }
    }
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
                                                 andPreferenceKey: @"updateCheckAutomatically"
                                                          negated: NO];
        
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
//        reportAnonymousInfoItem = [self initPrefMenuItemWithTitle: NSLocalizedString(@"Send Anonymous System Profile", @"Menu item")
//                                                        andAction: @selector(toggleReportAnonymousInfo:)
//                                                       andToolTip: NSLocalizedString(@"Takes effect at the next check for updates", @"Menu item tooltip")
//                                               atIndentationLevel: 1
//                                                 andPreferenceKey: @"updateSendProfileInfo"
//                                                          negated: NO];
//
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
        if (  autoCheckForUpdatesItem  ) { [optionsSubmenu addItem: autoCheckForUpdatesItem ]; }
        if (  reportAnonymousInfoItem  ) { [optionsSubmenu addItem: reportAnonymousInfoItem ]; }
        

        if (   putIconNearSpotlightItem || monitorConfigurationDirItem || warnAboutSimultaneousItem || showConnectedDurationsItem || useShadowCopiesItem || autoCheckForUpdatesItem || reportAnonymousInfoItem  ) {
            [optionsSubmenu addItem: [NSMenuItem separatorItem]];
        }
        
        if (  checkForUpdatesNowItem  ) { [optionsSubmenu addItem: checkForUpdatesNowItem   ]; }

        if (   checkForUpdatesNowItem
            && aboutItem  ) {
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
    [quitItem setTitle: NSLocalizedString(@"Quit Tunnelblick", @"Menu item")];
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
    
	[myConfigDictionary release];
    myConfigDictionary = [[[self getConfigurations] mutableCopy] retain];
    
    int i = 2; // we start at MenuItem #2

    NSString * dispNm;
    NSArray *keyArray = [[myConfigDictionary allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
	NSEnumerator * e = [keyArray objectEnumerator];
    while (dispNm = [e nextObject]) {
		NSMenuItem *connectionItem = [[[NSMenuItem alloc] init] autorelease];
		
        // configure connection object:
		VPNConnection* myConnection = [[VPNConnection alloc] initWithConfigPath: [myConfigDictionary objectForKey: dispNm]
                                                                withDisplayName: dispNm];
		[myConnection setState:@"EXITING"];
		[myConnection setDelegate:self];
        
		[myVPNConnectionDictionary setObject: myConnection forKey: dispNm];
		
        // Note: The menu item's title will be set on demand in VPNConnection's validateMenuItem
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
    } else if (  act == @selector(toggleReportAnonymousInfo:)  ) {
        if (  [gTbDefaults boolForKey:@"updateSendProfileInfo"]  ) {
            [anItem setState: NSOnState];
        } else {
            [anItem setState: NSOffState];
        }
        if (   [gTbDefaults boolForKey:@"onlyAdminCanUpdate"]
            && ( ! userIsAnAdmin )  ) {
            [anItem setToolTip: NSLocalizedString(@"Disabled because you cannot administer this computer and the 'onlyAdminCanUpdate' preference is set", @"Menu item tooltip")];
            return NO;
        } else if (  ! [updater respondsToSelector:@selector(setSendsSystemProfile:)]  ) {
            [anItem setToolTip: NSLocalizedString(@"Disabled because Sparkle Updater does not respond to setSendsSystemProfile:", @"Menu item tooltip")];
            return NO;
        }
        [anItem setToolTip: NSLocalizedString(@"Takes effect at the next check for updates", @"Menu item tooltip")];
    } else if (  act == @selector(toggleAutoCheckForUpdates:)  ) {
        [anItem setState: NSOffState];
        
        [self setupSparklePreferences]; // If first run, Sparkle may have changed the auto update preference
        
        if (   [gTbDefaults boolForKey:@"onlyAdminCanUpdate"]
            && ( ! userIsAnAdmin )  ) {
            [anItem setToolTip: NSLocalizedString(@"Disabled because you cannot administer this computer and the 'onlyAdminCanUpdate' preference is set", @"Menu item tooltip")];
            return NO;
        } else if (  ! [updater respondsToSelector:@selector(setAutomaticallyChecksForUpdates:)]  ) {
            [anItem setToolTip: NSLocalizedString(@"Disabled because Sparkle Updater does not respond to setAutomaticallyChecksForUpdates:", @"Menu item tooltip")];
            return NO;
        } else if (  ! [self appNameIsTunnelblickWarnUserIfNot: NO]  ) {
            [anItem setToolTip: NSLocalizedString(@"Disabled because the name of the application has been changed", @"Menu item tooltip")];
            return NO;
        }
        if (  [gTbDefaults boolForKey:@"updateCheckAutomatically"]  ) {
            [anItem setState: NSOnState];
        }
        [anItem setToolTip: NSLocalizedString(@"Takes effect the next time Tunnelblick is launched", @"Menu item tooltip")];
    } else if (  act == @selector(checkForUpdates:)  ) {
        if (   [gTbDefaults boolForKey:@"onlyAdminCanUpdate"]
            && ( ! userIsAnAdmin )  ) {
            [anItem setToolTip: NSLocalizedString(@"Disabled because you cannot administer this computer and the 'onlyAdminCanUpdate' preference is set", @"Menu item tooltip")];
            return NO;
        } else if (  ! [self appNameIsTunnelblickWarnUserIfNot: NO]  ) {
            [anItem setToolTip: NSLocalizedString(@"Disabled because the name of the application has been changed", @"Menu item tooltip")];
            return NO;
        }
        [anItem setToolTip: @""];
    } else {
        [anItem setToolTip: @""];
        return YES;
    }
    
    // We store the preference key for a menu item in the item's representedObject so we can do the following:
    if (  [anItem representedObject]  ) {
        if (  ! [gTbDefaults canChangeValueForKey: [anItem representedObject]]  ) {
            [anItem setToolTip: NSLocalizedString(@"Disabled because this setting is being forced", @"Menu item tooltip")];
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
			int i;
            for (i = 0; i < [gConfigDirs count]; i++) {
                [myQueue removePathFromQueue: [gConfigDirs objectAtIndex: i]];
            }
        }
    } else {
        if ( myQueue  ) {
			int i;
            for (i = 0; i < [gConfigDirs count]; i++) {
                [myQueue addPathToQueue: [gConfigDirs objectAtIndex: i]];
            }
            [self activateStatusMenu];
        } else {
            myQueue = [UKKQueue sharedFileWatcher];
			int i;
            for (i = 0; i < [gConfigDirs count]; i++) {
                [myQueue addPathToQueue: [gConfigDirs objectAtIndex: i]];
            }
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
    if (  [updater respondsToSelector: @selector(setAutomaticallyChecksForUpdates:)]  ) {
        if (  ! [gTbDefaults boolForKey:@"updateCheckAutomatically"]  ) {
            // Was OFF, trying to change to ON
            if (  [self appNameIsTunnelblickWarnUserIfNot: NO]  ) {
                [self toggleMenuItem: item withPreferenceKey: @"updateCheckAutomatically"];
                [updater setAutomaticallyChecksForUpdates: YES];
            } else {
                NSLog(@"'Automatically Check for Updates' change ignored because the name of the application has been changed");
            }
        } else {
            // Was ON, change to OFF
            [self toggleMenuItem: item withPreferenceKey: @"updateCheckAutomatically"];
            [updater setAutomaticallyChecksForUpdates: NO];
        }
    } else {
        NSLog(@"'Automatically Check for Updates' change ignored because Sparkle Updater does not respond to setAutomaticallyChecksForUpdates:");
    }
}

-(void)toggleReportAnonymousInfo: (NSMenuItem *) item
{
    if (  [updater respondsToSelector: @selector(setSendsSystemProfile:)]  ) {
        [self toggleMenuItem: item withPreferenceKey: @"updateSendProfileInfo"];
        [updater setSendsSystemProfile: [gTbDefaults boolForKey:@"updateSendProfileInfo"]];
    } else {
        NSLog(@"'Send Anonymous System Profile' change ignored because Sparkle Updater does not respond to setSendsSystemProfile:");
    }
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
    BOOL needToUpdateLogWindow = FALSE;
    NSString * dispNm;

    NSDictionary * curConfigsDict = [self getConfigurations];

    // Add new configurations
	NSEnumerator * e = [curConfigsDict keyEnumerator];
    while (dispNm = [e nextObject]) {
        BOOL sameDispNm = [myConfigDictionary objectForKey: dispNm] != nil;
        BOOL sameFolder = [[myConfigDictionary objectForKey: dispNm] isEqualToString: [curConfigsDict objectForKey: dispNm]];
        BOOL newIsDeploy = [gDeployPath isEqualToString: firstPartOfPath([curConfigsDict objectForKey: dispNm])];
        
        if (  sameDispNm  ) {
            if (  ! sameFolder  ) {
                if (  newIsDeploy  ) {
                    // Replace one from ~/Library/.../Configurations with one from Deploy
                    [self deleteExistingConfig: dispNm];
                    [self addNewConfig: [curConfigsDict objectForKey: dispNm] withDisplayName: dispNm];
                    needToUpdateLogWindow = TRUE;
                } else {
                    ; // Ignore new configs that are in ~/Library/.../Configurations if there is one with the same display name in Deploy
                }
            } else {
                ; // Ignore -- not changed
            }
        } else {
            [self addNewConfig: [curConfigsDict objectForKey: dispNm] withDisplayName: dispNm]; // No old config with same name
            needToUpdateLogWindow = TRUE;
        }
    }

    // Remove configurations that are no longer available
    // (Or replace a deleted Deploy configuration with one from ~/Library/.../Configurations if it exists
	e = [myConfigDictionary keyEnumerator];
    while (dispNm = [e nextObject]) {
        BOOL sameDispNm = [curConfigsDict objectForKey: dispNm] != nil;
        BOOL sameFolder = [[myConfigDictionary objectForKey: dispNm] isEqualToString: [curConfigsDict objectForKey: dispNm]];
        BOOL oldWasDeploy = [gDeployPath isEqualToString: firstPartOfPath([myConfigDictionary objectForKey: dispNm])];
        
        if (  sameDispNm  ) {
            if (  ! sameFolder  ) {
                if (  oldWasDeploy  ) {
                    // Replace one from Deploy with one from ~/Library/.../Configurations
                    [self deleteExistingConfig: dispNm];
                    [self addNewConfig: [curConfigsDict objectForKey: dispNm] withDisplayName: dispNm];
                    needToUpdateLogWindow = TRUE;
                } else {
                    [self deleteExistingConfig: dispNm];  // No new config at same path
                    needToUpdateLogWindow = TRUE;
                }
            } else {
                ; // Ignore -- not changed
            }
        } else {
            [self deleteExistingConfig: dispNm]; // No new config with same name
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

// Add new config to myVPNConnectionDictionary, the menu, and myConfigDictionary
// Note: The menu item's title will be set on demand in VPNConnection's validateMenuItem
-(void) addNewConfig: (NSString *) path withDisplayName: (NSString *) dispNm
{
    VPNConnection* myConnection = [[VPNConnection alloc] initWithConfigPath: path
                                                            withDisplayName: dispNm];
    [myConnection setState:@"EXITING"];
    [myConnection setDelegate:self];
    [myVPNConnectionDictionary setObject: myConnection forKey: dispNm];
    
    NSMenuItem *connectionItem = [[[NSMenuItem alloc] init] autorelease];
    [connectionItem setTarget:myConnection]; 
    [connectionItem setAction:@selector(toggle:)];
    
    int i;
    NSArray *keyArray = [[myConfigDictionary allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
    for (  i=0; i < [keyArray count]; i++  ) {
        if (  [dispNm caseInsensitiveCompare: [keyArray objectAtIndex: i]] == NSOrderedAscending  ) {
            [myVPNMenu insertItem:connectionItem atIndex:i+2];      // 1st menu item is status, 2nd is a separator
            break;
        }
    }
    if (  i == [keyArray count]  ) {
        [myVPNMenu insertItem:connectionItem atIndex:i+2];
    }
    
    [myConfigDictionary setObject: path forKey: dispNm];
}

// Remove config from myVPNConnectionDictionary, the menu, and myConfigDictionary
// Disconnect first if necessary
-(void) deleteExistingConfig: (NSString *) dispNm
{
    VPNConnection* myConnection = [myVPNConnectionDictionary objectForKey: dispNm];
    if (  ! [[myConnection state] isEqualTo: @"EXITING"]  ) {
        [myConnection disconnect: self];
        
        TBRunAlertPanel([NSString stringWithFormat: NSLocalizedString(@"'%@' has been disconnected", @"Window title"), dispNm],
                        [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick has disconnected '%@' because its configuration file has been removed.", @"Window text"), dispNm],
                        nil, nil, nil);
    }
    
    [myVPNConnectionDictionary removeObjectForKey: dispNm];
    
    int i;
    NSArray *keyArray = [[myConfigDictionary allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
    for (  i=0; i < [keyArray count]; i++  ) {
        if (  [dispNm isEqualToString: [keyArray objectAtIndex: i]]  ) {
            [myVPNMenu removeItemAtIndex:i+2];      // 1st menu item is status, 2nd is a separator
            break;
        }
    }
    
    [myConfigDictionary removeObjectForKey: dispNm];
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

// Returns a dictionary with information about the configuration files in gConfigDirs.
// The key for each entry is the display name for the configuration
// The object is the path to the configuration file for the configuration
-(NSMutableDictionary *) getConfigurations {
    NSMutableDictionary * dict = [[[NSMutableDictionary alloc] init] autorelease];
    NSString * file;
    int i;
    BOOL isDir;
    for (i=0; i < [gConfigDirs count]; i++) {
        NSString * folder = [gConfigDirs objectAtIndex: i];
        NSDirectoryEnumerator *dirEnum = [gFileMgr enumeratorAtPath: folder];
        while (file = [dirEnum nextObject]) {
            NSString * path = [folder stringByAppendingPathComponent: file];
            NSString * ext = [file pathExtension];
            if ([ext isEqualToString: @"conf"] || [ext isEqualToString: @"ovpn"]) {
                if (   [gFileMgr fileExistsAtPath: path isDirectory: &isDir]
                    && ( ! isDir)  ) {
                    NSString * dispNm = [file substringToIndex: [file length]-5];
                    if (  ! [dict objectForKey: dispNm]  ) {
                        [dict setObject: path forKey: dispNm];
                    }
                }
            }
        }
    }

    return dict;
}

-(void)validateLogButtons
{
    //NSLog(@"validating log buttons");
    VPNConnection* connection = [self selectedConnection];
    [connectButton setEnabled:[connection isDisconnected]];
    [disconnectButton setEnabled:(![connection isDisconnected])];

	NSString *disableEditConfigKey = [[connection displayName] stringByAppendingString:@"disableEditConfiguration"];
    if (  [gTbDefaults boolForKey:disableEditConfigKey]  ) {
        [editButton setEnabled: NO];
    } else {
        [editButton setEnabled: YES];
    }
    
	NSString *autoConnectKey = [[connection displayName] stringByAppendingString:@"autoConnect"];
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
	
	NSString *useDNSKey = [[connection displayName] stringByAppendingString:@"useDNS"];
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
	
	NSString *notMonitorConnectionKey = [[connection displayName] stringByAppendingString:@"-notMonitoringConnection"];
    if (   [gTbDefaults canChangeValueForKey: notMonitorConnectionKey]
        && useDNSStatus(connection)  ) {
        [monitorConnnectionCheckbox setEnabled: YES];
    } else {
        [monitorConnnectionCheckbox setEnabled: NO];
	}
	if(   ( ! [gTbDefaults boolForKey:notMonitorConnectionKey] )
       && useDNSStatus(connection)  ) {
		[monitorConnnectionCheckbox setState:NSOnState];
	} else {
		[monitorConnnectionCheckbox setState:NSOffState];
	}
}

-(void)updateTabLabels
{
	NSArray *keyArray = [[myVPNConnectionDictionary allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
	NSArray *myConnectionArray = [myVPNConnectionDictionary objectsForKeys:keyArray notFoundMarker:[NSNull null]];
	NSEnumerator *connectionEnumerator = [myConnectionArray objectEnumerator];
	VPNConnection *myConnection;

	int i = 0;
	while(myConnection = [connectionEnumerator nextObject]) {
        NSString * cState = [myConnection state];
        NSString * cTimeS = @"";

        // Get connection duration if preferences say to 
        if (   [gTbDefaults boolForKey:@"showConnectedDurations"]
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
		NSString *label = [NSString stringWithFormat:@"%@ (%@%@)",[myConnection displayName], NSLocalizedString(cState, nil), cTimeS];
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
	
	if (   (![lastState isEqualToString:@"EXITING"])
        && (![lastState isEqualToString:@"CONNECTED"]) ) { 
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
	if (   (![lastState isEqualToString:@"EXITING"])
        && (![lastState isEqualToString:@"CONNECTED"]))
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
    
    NSString * locationMessage = @"";
    if (  [gConfigDirs count] > 1  ) {
        if (  [[newConnection configPath] hasPrefix: gDeployPath]) {
            locationMessage =  NSLocalizedString(@" (Deployed)", @"Window title");
        } else if (  [[newConnection configPath] hasPrefix: gSharedPath]) {
            locationMessage =  NSLocalizedString(@" (Shared)", @"Window title");
        }
    }
    [logWindow setTitle: [NSString stringWithFormat: @"%@ - %@%@",
                          NSLocalizedString(@"Details - Tunnelblick", @"Window title"),
                          [[self selectedConnection] displayName],
                          locationMessage]];
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
	
    NSString* dispNm = [[tabView selectedTabViewItem] identifier];
	VPNConnection* connection = [myVPNConnectionDictionary objectForKey: dispNm];
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

- (IBAction) checkForUpdates: (id) sender
{
    if (   [gTbDefaults boolForKey:@"onlyAdminCanUpdate"]
        && ( ! userIsAnAdmin )  ) {
        NSLog(@"Check for updates was not performed because user is not allowed to administer this computer and 'onlyAdminCanUpdate' preference is set");
    } else {
        if (  [updater respondsToSelector: @selector(checkForUpdates:)]  ) {
            if (  [self appNameIsTunnelblickWarnUserIfNot: NO]  ) {
                if (  ! userIsAnAdmin  ) {
                    int response = TBRunAlertPanelExtended(NSLocalizedString(@"Only computer administrators should update Tunnelblick", @"Window title"),
                                                           NSLocalizedString(@"You will not be able to use Tunnelblick after updating unless you provide an administrator username and password.\n\nAre you sure you wish to check for updates?", @"Window text"),
                                                           NSLocalizedString(@"Check For Updates Now", @"Button"),  // Default button
                                                           NSLocalizedString(@"Cancel", @"Button"),                 // Alternate button
                                                           nil,                                                     // Other button
                                                           @"skipWarningAboutNonAdminUpdatingTunnelblick",          // Preference about seeing this message again
                                                           NSLocalizedString(@"Do not warn about this again", @"Checkbox text"),
                                                           nil);
                    if (  response == NSAlertAlternateReturn  ) {
                        return;
                    }
                }
                [updater checkForUpdates: self];
            } else {
                NSLog(@"'Check for Updates Now' ignored because the name of the application has been changed");
            }
        } else {
            NSLog(@"'Check for Updates Now' ignored because Sparkle Updater does not respond to checkForUpdates:");
        }
    }
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

	NSEnumerator* e = [[[myVPNConnectionDictionary allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)] objectEnumerator];
	NSTabViewItem* initialItem;
	VPNConnection* connection = [myVPNConnectionDictionary objectForKey: [e nextObject]];
    if (  ! connection  ) {
        NSLog(@"myVPNConnectionsDictionary is empty; Tunnelblick must have at least one configuration");
        [NSApp setAutoLaunchOnLogin: NO];
        [NSApp terminate: self];
    }

    initialItem = [tabView tabViewItemAtIndex: 0];
    NSString * dispNm = [connection displayName];
    [initialItem setIdentifier: dispNm];
    [initialItem setLabel:      dispNm];
    
    int curTabIndex = 0;
    [tabView selectTabViewItemAtIndex:0];
    BOOL haveOpenConnection = ! [connection isDisconnected];
    while (connection = [myVPNConnectionDictionary objectForKey: [e nextObject]]) {
        NSTabViewItem* newItem = [[NSTabViewItem alloc] init];
        dispNm = [connection displayName];
        [newItem setIdentifier: dispNm];
        [newItem setLabel:      dispNm];
        [tabView addTabViewItem: newItem];
        [newItem release];
        ++curTabIndex;
        if (   ( ! haveOpenConnection )
            && ( ! [connection isDisconnected] )  ) {
            [tabView selectTabViewItemAtIndex:curTabIndex];
            haveOpenConnection = YES;
        }
    }
    
	[logWindow setDelegate:self];
	VPNConnection *myConnection = [self selectedConnection];
	NSTextStorage* store = [myConnection logStorage];
	[[[self selectedLogView] layoutManager] replaceTextStorage: store];
	
	[self tabView:tabView didSelectTabViewItem:initialItem];
	[self validateLogButtons];
	[self updateTabLabels];
    
    // Set up a timer to update the tab labels with connections' duration times
    if (   (showDurationsTimer == nil)
        && [gTbDefaults boolForKey:@"showConnectedDurations"]  ) {
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
    // Using [[NSBundle mainBundle] resourcePath: ALSO seems to not work (don't know why, maybe the same reason)
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

    NSString * copyright    = NSLocalizedString(@"Copyright © 2004-2010 Angelo Laub and others. All rights reserved.", @"Window text");

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
    
    NSArray *keyArray = [[myVPNConnectionDictionary allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
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
		if (NSDebugEnabled) NSLog(@"Connection %@ is connected for %f seconds\n",[connection displayName],[[connection connectedSinceDate] timeIntervalSinceNow]);
		if ([[connection connectedSinceDate] timeIntervalSinceNow] < -5) {
			if (NSDebugEnabled) NSLog(@"Resetting connection: %@",[connection displayName]);
			[connection disconnect:self];
			[connection connect:self];
		}
		else {
			if (NSDebugEnabled) NSLog(@"Not Resetting connection: %@\n, waiting...",[connection displayName]);
		}
	}
}

// If there aren't ANY config files in the config folders 
// then let the user either quit or create and edit a sample configuration file
// else do nothing
-(void)createDefaultConfigUsingTitle:(NSString *) ttl andMessage:(NSString *) msg 
{
    if (  ignoreNoConfigs || [[self getConfigurations] count] != 0  ) {
        return;
    }
    
    if (   [gConfigDirs count] == 1
        && [[gConfigDirs objectAtIndex:0] isEqualToString: gDeployPath]  ) {
        TBRunAlertPanel(NSLocalizedString(@"All configuration files removed", @"Window title"),
                        [NSString stringWithFormat: NSLocalizedString(@"All configuration files in %@ have been removed. Tunnelblick must quit.", @"Window text"),
                         [[gFileMgr componentsToDisplayForPath: gDeployPath] componentsJoinedByString: @"/"]],
                        nil, nil, nil);
        [NSApp setAutoLaunchOnLogin: NO];
        [NSApp terminate: nil];
    }
    
    NSString * openvpnConfPath = [[NSBundle mainBundle] pathForResource: @"openvpn"
                                                                 ofType: @"conf"];
    
    BOOL isDir;
    NSString * alternateButtonTitle = nil;
    if (  ! ([gFileMgr fileExistsAtPath: libraryPath isDirectory: &isDir])  ) {
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
    
    NSString * parentPath = [libraryPath stringByDeletingLastPathComponent];
    if (  ! [gFileMgr fileExistsAtPath: parentPath]  ) {                      // If ~/Library/Application Support/Tunnelblick doesn't exist, create it
        if ( ! [gFileMgr createDirectoryAtPath: parentPath attributes:nil]  ) {
            NSLog(@"Error creating %@", parentPath);
        }
    }
    
    if (  ! [gFileMgr fileExistsAtPath: libraryPath]  ) {                     // If ~/Library/Application Support/Tunnelblick/Configurations doesn't exist, create it
        if (  ! [gFileMgr createDirectoryAtPath: libraryPath attributes:nil]  ) {
            NSLog(@"Error creating %@", libraryPath);
        }
    }
    
    if (  ! [gTbDefaults boolForKey: @"doNotCreateLaunchTunnelblickLinkinConfigurations"]  ) {
        NSString * pathToThisApp = [[NSBundle mainBundle] bundlePath];
        NSString * launchTunnelblickSymlink = [libraryPath stringByAppendingPathComponent: @"Launch Tunnelblick"];
        if (  ! [gFileMgr fileExistsAtPath:launchTunnelblickSymlink]  ) {
            ignoreNoConfigs = TRUE; // We're dealing with no configs already, and will either quit or create one
            NSLog(@"Creating 'Launch Tunnelblick' link in Configurations folder; links to %@", pathToThisApp);
            [gFileMgr createSymbolicLinkAtPath: launchTunnelblickSymlink
                                      pathContent: pathToThisApp];
        } else if (  ! [[gFileMgr pathContentOfSymbolicLinkAtPath: launchTunnelblickSymlink] isEqualToString: pathToThisApp]  ) {
            ignoreNoConfigs = TRUE; // We're dealing with no configs already, and will either quit or create one
            NSLog(@"Replacing 'Launch Tunnelblick' link in Configurations folder; now links to %@", pathToThisApp);
            [gFileMgr removeFileAtPath: launchTunnelblickSymlink handler: nil];
            [gFileMgr createSymbolicLinkAtPath: launchTunnelblickSymlink
                                      pathContent: pathToThisApp];
        }
    }
    
    if (  button == NSAlertOtherReturn  ) { // CREATE CONFIGURATION FOLDER (already created)
        [[NSWorkspace sharedWorkspace] openFile: libraryPath];
        [NSApp setAutoLaunchOnLogin: NO];
        [NSApp terminate: nil];
    }
    
    NSString * targetPath = [libraryPath stringByAppendingPathComponent:@"openvpn.conf"];
    NSLog(@"Installing sample configuration file %@", targetPath);
    if (  ! [gFileMgr copyPath: openvpnConfPath toPath: targetPath handler: nil]  ) {
        NSLog(@"Installation failed. Not able to copy openvpn.conf to %@", libraryPath);
        TBRunAlertPanel(NSLocalizedString(@"Installation failed", @"Window title"),
                        [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not copy openvpn.conf to %@", @"Window text"),
                         [[gFileMgr componentsToDisplayForPath: libraryPath] componentsJoinedByString: @"/"]],
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
    NSString * targetPath = [connection configPath];
    if ( ! targetPath  ) {
        targetPath = [libraryPath stringByAppendingPathComponent: @"openvpn.conf"];
    }

    // To allow Tiger and Leopard users to edit and save a configuration file, we allow the user to unprotect the file before editing. 
    // This is because, although on Snow Leoapard TextEdit can save the file (the new file will be owned by the current user, with 644 permissions),
    // on Tiger and Leopard TextEdit cannot save a file if it is protected (owned by root with 644 permissions).
    if (  connection  ) {
        if (  [gFileMgr fileExistsAtPath: targetPath]  ) {           // Must check that file exists because isWritableAtPath returns NO if the file doesn't exist
            if (  ! [gFileMgr isWritableFileAtPath: targetPath]  ) {
                if (   [gFileMgr isWritableFileAtPath: [targetPath stringByDeletingLastPathComponent]]
                    && (userIsAnAdmin || ( ! [gTbDefaults boolForKey: @"onlyAdminsCanUnprotectConfigurationFiles"] ))  ) {
                    // Ask if user wants to unprotect the configuration file
                    int button = TBRunAlertPanelExtended(NSLocalizedString(@"The configuration file is protected", @"Window title"),
                                                         NSLocalizedString(@"You may examine the configuration file, but if you plan to modify it, you must unprotect it now. If you unprotect the configuration file now, you will need to provide an administrator username and password the next time you connect using it.", @"Window text"),
                                                         NSLocalizedString(@"Examine", @"Button"),                  // Default button
                                                         NSLocalizedString(@"Unprotect and Modify", @"Button"),     // Alternate button
                                                         NSLocalizedString(@"Cancel", @"Button"),                   // Other button
                                                         @"skipWarningAboutConfigFileProtectedAndAlwaysExamineIt",  // Preference about seeing this message again
                                                         NSLocalizedString(@"Do not warn about this again, always 'Examine'", @"Checkbox text"),
                                                         nil);
                    if (  button == NSAlertOtherReturn  ) {
                        return;
                    }
                    if (  button == NSAlertAlternateReturn  ) {
                        if (  ! [connection unprotectConfigurationFile]  ) {
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
		NSString* key = [[connection displayName] stringByAppendingString: @"-notMonitoringConnection"];
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
		NSString* key = [[connection displayName] stringByAppendingString: @"useDNS"];
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
		NSString* autoConnectKey = [[connection displayName] stringByAppendingString: @"autoConnect"];
		[gTbDefaults setObject: [NSNumber numberWithBool: inBool] forKey: autoConnectKey];
		[gTbDefaults synchronize];
	}
	
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

- (void) applicationWillFinishLaunching: (NSNotification *)notification
{
    // Sparkle Updater 1.5b6 allows system profiles to be sent to Tunnelblick's website.
    // However, a user who has already used Tunnelblick will not be asked permission to send them.
    // So we force Sparkle to ask the user again (i.e., ask again about checking for updates automatically) in order to allow
    // the user to respond as they see fit, after (if they wish) viewing the exact data that will be sent.
    //
    // We do this by clearing Sparkle's preferences. We use our own preference that indicates that we've done this so we only
    // do it once (and so we can override that preference with a forced-preferences.plist entry). The _value_ of that
    // preference doesn't matter; if it exists we assume this issue has been dealt with. The user will not be asked if
    // both the "updateCheckAutomatically" and "updateSendProfileInfo" preferences are forced (to any value).
    //
    // We do this check each time Tunnelblick is launched, to allow deployers to "un-force" this at some later time and have
    // the user asked for his/her preference.
    
    BOOL forcingAutoChecksAndSendProfile = (  ! [gTbDefaults canChangeValueForKey: @"updateCheckAutomatically" ]  )
                                        && ( ! [gTbDefaults canChangeValueForKey: @"updateSendProfileInfo"]  );
    BOOL userIsAdminOrNonAdminsCanUpdate = ( userIsAnAdmin ) || ( ! [gTbDefaults boolForKey:@"onlyAdminCanUpdate"] );
    NSUserDefaults * stdDefaults = [NSUserDefaults standardUserDefaults];
    
    if (  [gTbDefaults objectForKey: @"haveDealtWithSparkle1dot5b6"] == nil  ) {
        if (  ! forcingAutoChecksAndSendProfile  ) {
            // Haven't done this already and aren't forcing the user's answers, so ask the user (perhaps again) by clearing Sparkle's preferences
            // EXCEPT we SET "SUHasLaunchedBefore", so the user will be asked right away about checking for updates automatically and sending profile info
            [stdDefaults removeObjectForKey: @"SUEnableAutomaticChecks"];
            [stdDefaults removeObjectForKey: @"SUAutomaticallyUpdate"];
            [stdDefaults removeObjectForKey: @"SUupdateSendProfileInfo"];
            [stdDefaults removeObjectForKey: @"SULastCheckTime"];                       
            [stdDefaults removeObjectForKey: @"SULastProfileSubmissionDate"];
            
            [stdDefaults setBool: TRUE forKey: @"SUHasLaunchedBefore"];
            
            // We clear _our_ preferences, too, so they will be updated when the Sparkle preferences are set by Sparkle
            [stdDefaults removeObjectForKey: @"updateCheckAutomatically"];
            [stdDefaults removeObjectForKey: @"updateSendProfileInfo"];
            [stdDefaults synchronize];
            
            [gTbDefaults setBool: YES forKey: @"haveDealtWithSparkle1dot5b6"];
            [gTbDefaults synchronize];
        }
    }
    
    // We aren't supposed to use Sparkle Updater's preferences directly. However, we need to be able to, in effect,
    // override three of them via forced-preferences.plist. So we have three of our own preferences which mirror Sparkle's. Our
    // preferences are "updateCheckAutomatically", "updateSendProfileInfo", and "updateAutomatically", which mirror
    // Sparkle's "SUEnableAutomaticChecks", "SUupdateSendProfileInfo", and "SUAutomaticallyUpdate". We use our preferences to
    // set Sparkle's behavior by invoking methods of the updater instance.
    //
    // We also have two other preferences which affect Sparkle's behavior. Sparkle doesn't use preferences for them; they are set in
    // Info.plist or have default values. These two preferences are "updateCheckInterval", and "updateFeedURL".
    // Note that "updateFeedURL" may only be forced -- any normal, user-modifiable value will be ignored.
    //
    // Everywhere we change our preferences, we notify Sparkle via the appropriate updater methods.
    //
    // We access Sparkle's preferences only on a read-only basis, and only for the inital setup of our preferences (here).
    // We do the initial setup of our preferences from Sparkle's preferences because it is Sparkle that asks the user.
    // Until the user has been asked by Sparkle (and thus Sparkle has set its preferences), we assume we are not
    // checking, and not sending system profiles.
    
    // Initialize our preferences from Sparkle's if ours have not been set yet (and thus are not being forced), and Sparkle's _have_ been set
    // (We have to access Sparkle's prefs directly because we need to wait until they have actually been set one way or the other)
    // Note that we access Sparkle's preferences via stdDefaults, so they can't be forced (Sparkle would ignore the forcing, anyway)
    // However, when we try to set out preferences from Sparkle's, if they are forced then they won't be changed.
    
    [self setupSparklePreferences];
    
    // Set Sparkle's behavior from our preferences using Sparkle's approved methods
    BOOL warnedAlready = FALSE;
    if (  [updater respondsToSelector: @selector(setAutomaticallyChecksForUpdates:)]  ) {
        if (  userIsAdminOrNonAdminsCanUpdate  ) {
            if (  [gTbDefaults objectForKey: @"updateCheckAutomatically"] != nil  ) {
                if (  [gTbDefaults boolForKey: @"updateCheckAutomatically"]  ) {
                    if (  [self appNameIsTunnelblickWarnUserIfNot: TRUE]  ) {
                        [updater setAutomaticallyChecksForUpdates: YES];
                    } else {
                        warnedAlready = TRUE;
                        [updater setAutomaticallyChecksForUpdates: NO];
                    }
                } else {
                    [updater setAutomaticallyChecksForUpdates: NO];
                }
            }
        } else {
            if (  [gTbDefaults boolForKey: @"updateCheckAutomatically"]  ) {
                NSLog(@"Automatic check for updates will not be performed because user is not allowed to administer this computer and 'onlyAdminCanUpdate' preference is set");
            }
            [updater setAutomaticallyChecksForUpdates: NO];
        }
    } else {
        if (  [gTbDefaults boolForKey: @"updateCheckAutomatically"]  ) {
            NSLog(@"Ignoring 'updateCheckAutomatically' preference because Sparkle Updater does not respond to setAutomaticallyChecksForUpdates:");
        }
    }
    
    if (  [updater respondsToSelector: @selector(setAutomaticallyDownloadsUpdates:)]  ) {
        if (  userIsAdminOrNonAdminsCanUpdate  ) {
            if (  [gTbDefaults objectForKey: @"updateAutomatically"] != nil  ) {
                if (  [gTbDefaults boolForKey: @"updateAutomatically"]  ) {
                    if (  [self appNameIsTunnelblickWarnUserIfNot: warnedAlready]  ) {
                        [updater setAutomaticallyDownloadsUpdates: YES];
                    } else {
                        [updater setAutomaticallyDownloadsUpdates: NO];
                    }
                } else {
                    [updater setAutomaticallyDownloadsUpdates: NO];
                }
            }
        } else {
            if (  [gTbDefaults boolForKey: @"updateAutomatically"]  ) {
                NSLog(@"Automatic updates will not be performed because user is not allowed to administer this computer and 'onlyAdminCanUpdate' preference is set");
            }
            [updater setAutomaticallyDownloadsUpdates: NO];
        }
    } else {
        if (  [gTbDefaults boolForKey: @"updateAutomatically"]  ) {
            NSLog(@"Ignoring 'updateAutomatically' preference because Sparkle Updater does not respond to setAutomaticallyDownloadsUpdates:");
        }
    }
    
    if (  [updater respondsToSelector: @selector(setSendsSystemProfile:)]  ) {
        if (  [gTbDefaults objectForKey: @"updateSendProfileInfo"] != nil  ) {
            [updater setSendsSystemProfile: [gTbDefaults boolForKey:@"updateSendProfileInfo"]];
        }
    } else {
        NSLog(@"Ignoring 'updateSendProfileInfo' preference because Sparkle Updater Updater does not respond to setSendsSystemProfile:");
    }
    
    id checkInterval = [gTbDefaults objectForKey: @"updateCheckInterval"];
    if (  checkInterval  ) {
        if (  [updater respondsToSelector: @selector(setUpdateCheckInterval:)]  ) {
            if (  [checkInterval isMemberOfClass: [NSNumber class]]
                || [checkInterval isMemberOfClass: [NSString class]]  ) {
                NSTimeInterval d = [checkInterval doubleValue];
                if (  d == 0.0  ) {
                    NSLog(@"Ignoring 'updateCheckInterval' preference because it is 0 or is not a valid number");
                } else {
                    if (  d < 3600.0  ) {   // Minimum one hour to prevent DOS on the update servers
                        d = 3600.0;
                    }
                    [updater setUpdateCheckInterval: d];
                }
                
            } else {
                NSLog(@"Ignoring 'updateCheckInterval' preference because it is not a string or a number");
            }
        } else {
            NSLog(@"Ignoring 'updateCheckInterval' preference because Sparkle Updater does not respond to setUpdateCheckInterval:");
        }
    }
    
    // We set the Feed URL if it is forced, even if we haven't run Sparkle yet (and thus haven't set our Sparkle preferences) because
    // the user may do a 'Check for Updates Now' on the first run, and we need to check with the forced Feed URL
    if (  ! [gTbDefaults canChangeValueForKey: @"updateFeedURL"]  ) {
        if (  [updater respondsToSelector: @selector(setFeedURL:)]  ) {
            id feedURL = [gTbDefaults objectForKey: @"updateFeedURL"];
            if (  [feedURL isMemberOfClass: [NSString class]]  ) {
                [updater setFeedURL: [NSURL URLWithString: feedURL]];
            } else {
                NSLog(@"Ignoring 'updateFeedURL' preference from 'forced-preferences.plist' because it is not a string");
            }
        } else {
            NSLog(@"Ignoring 'updateFeedURL' preference because Sparkle Updater does not respond to setFeedURL:");
        }
    }
    
    // Set updater's delegate, so we can add our own info to the system profile Sparkle sends to our website
    // Do this even if we haven't set our preferences (see above), so Sparkle will include our data in the list
    // it presents to the user when asking the user for permission to send the data.
    if (  [updater respondsToSelector: @selector(setDelegate:)]  ) {
        [updater setDelegate: self];
    } else {
        NSLog(@"Cannot set Sparkle delegate because Sparkle Updater does not respond to setDelegate:");
    }
}

// If we haven't set up the updateCheckAutomatically, updateSendProfileInfo, and updateAutomatically preferences,
// and the corresponding Sparkle preferences have been set, copy Sparkle's settings to ours
-(void) setupSparklePreferences
{
    NSUserDefaults * stdDefaults = [NSUserDefaults standardUserDefaults];

    if (  [gTbDefaults objectForKey: @"updateCheckAutomatically"] == nil  ) {
        if (  [stdDefaults objectForKey: @"SUEnableAutomaticChecks"] != nil  ) {
            [gTbDefaults setBool: [stdDefaults boolForKey: @"SUEnableAutomaticChecks"]
                          forKey: @"updateCheckAutomatically"];
            [gTbDefaults synchronize];
        }
    }
    
    if (  [gTbDefaults objectForKey: @"updateSendProfileInfo"] == nil  ) {
        if (  [stdDefaults objectForKey: @"SUupdateSendProfileInfo"] != nil  ) {
            [gTbDefaults setBool: [stdDefaults boolForKey: @"SUupdateSendProfileInfo"]
                          forKey: @"updateSendProfileInfo"];
            [gTbDefaults synchronize];
        }
    }
    
    // SUAutomaticallyUpdate may be changed at any time by a checkbox in Sparkle's update window, so we always use Sparkle's version
    if (  [stdDefaults objectForKey: @"SUAutomaticallyUpdate"] != nil  ) {
        [gTbDefaults setBool: [updater automaticallyDownloadsUpdates]       // But if it is forced, this setBool will be ignored
                      forKey: @"updateAutomatically"];
        [gTbDefaults synchronize];
    }
    
}

- (void) applicationDidFinishLaunching: (NSNotification *)notification
{
	[NSApp callDelegateOnNetworkChange: NO];
    [self installSignalHandler];    
    [NSApp setAutoLaunchOnLogin: YES];
    [self activateStatusMenu];
    
    // If checking for updates is enabled, we do a check every time Tunnelblick is launched (i.e., now)
    // We also check for updates if we haven't set our preferences yet. (We have to do that so that Sparkle
    // will ask the user whether to check or not, then we set our preferences from that.)
    if (      [gTbDefaults boolForKey:   @"updateCheckAutomatically"]
        || (  [gTbDefaults objectForKey: @"updateCheckAutomatically"] == nil  )
        ) {
        if (  [updater respondsToSelector: @selector(checkForUpdatesInBackground)]  ) {
            if (  [self appNameIsTunnelblickWarnUserIfNot: NO]  ) {
                [updater checkForUpdatesInBackground];
            } else {
                NSLog(@"Not checking for updates because the name of the application has been changed");
            }
        } else {
            NSLog(@"Cannot check for updates because Sparkle Updater does not respond to checkForUpdatesInBackground");
        }
    }
}

// Sparkle delegate:
// This method allows you to add extra parameters to the appcast URL,
// potentially based on whether or not Sparkle will also be sending along
// the system profile. This method should return an array of dictionaries
// with keys: "key", "value", "displayKey", "displayValue", the latter two
// being human-readable variants of the former two.
- (NSArray *)feedParametersForUpdater:(SUUpdater *) updaterToFeed
                 sendingSystemProfile:(BOOL) sendingProfile
{
    if (  updaterToFeed == updater  ) {
        if (  ! sendingProfile  ) {
            return [NSArray array];
        }
        
        int nConfigurations    = [myConfigDictionary count];
        int nSetNameserver     = 0;
        int nMonitorConnection = 0;
        NSString * key;

        // Count # of configurations with 'Set nameserver' checked and the # with 'Monitor connection' set
        NSEnumerator * e = [myConfigDictionary keyEnumerator];
        while (  key = [e nextObject]  ) {
            NSString * dnsKey = [key stringByAppendingString:@"useDNS"];
            if (  [gTbDefaults objectForKey: dnsKey]  ) {
                if (  [gTbDefaults boolForKey: dnsKey]  ) {
                    nSetNameserver++;
                }
            } else {
                nSetNameserver++;
            }
            
            NSString * mcKey = [key stringByAppendingString:@"-notMonitoringConnection"];
            if (  [gTbDefaults objectForKey: mcKey]  ) {
                if (  ! [gTbDefaults boolForKey: mcKey]  ) {
                    nMonitorConnection++;
                }
            } else {
                nMonitorConnection++;
            }
        }
        
        NSString * sConn = [NSString stringWithFormat:@"%d", nConfigurations    ];
        NSString * sSN   = [NSString stringWithFormat:@"%d", nSetNameserver     ];
        NSString * sMC   = [NSString stringWithFormat:@"%d", nMonitorConnection ];
        NSString * sDep  = ([[gConfigDirs objectAtIndex: 0] isEqualToString: gDeployPath] ? @"1" : @"0");
        NSString * sAdm  = (userIsAnAdmin ? @"1" : @"0");
        NSString * sUuid = [self installationId];

// IMPORTANT: If new keys are added here, they must also be added to profileConfig.php on the website
//            or the user's data for the new keys will not be recorded in the database.

        return [NSArray arrayWithObjects:
                [NSDictionary dictionaryWithObjectsAndKeys:
                 @"nConn",   @"key", sConn, @"value", NSLocalizedString(@"Configurations",     @"Window text"  ), @"displayKey", sConn, @"displayValue", nil],
                [NSDictionary dictionaryWithObjectsAndKeys:
                 @"nSetDNS", @"key", sSN,   @"value", NSLocalizedString(@"Set nameserver",     @"Checkbox name"), @"displayKey", sSN,   @"displayValue", nil],
                [NSDictionary dictionaryWithObjectsAndKeys:
                 @"nMonCon", @"key", sMC,   @"value", NSLocalizedString(@"Monitor connection", @"Checkbox name"), @"displayKey", sMC,   @"displayValue", nil],
                [NSDictionary dictionaryWithObjectsAndKeys:
                 @"Deploy",  @"key", sDep,  @"value", NSLocalizedString(@"Deployed",           @"Window text"  ), @"displayKey", sDep,  @"displayValue", nil],
                [NSDictionary dictionaryWithObjectsAndKeys:
                 @"Admin",   @"key", sAdm,  @"value", NSLocalizedString(@"Computer admin",     @"Window text"  ), @"displayKey", sAdm,  @"displayValue", nil],
                [NSDictionary dictionaryWithObjectsAndKeys:
                 @"Uuid",    @"key", sUuid, @"value", NSLocalizedString(@"Anonymous unique ID",@"Window text"  ), @"displayKey", sUuid, @"displayValue", nil],
                nil
                ];
    }
    
    NSLog(@"feedParametersForUpdater: invoked with unknown 'updaterToFeed' = %@", updaterToFeed);
    return [NSArray array];
}

- (NSString *)installationId
{
    NSString * installationIdKey = @"installationUID";
    
    NSString *uuid = [gTbDefaults objectForKey:installationIdKey];
    
    if (uuid == nil) {
        uuid_t buffer;
        uuid_generate(buffer);
        char str[37];   // 36 bytes plus trailing \0
        uuid_unparse_upper(buffer, str);
        uuid = [NSString stringWithFormat:@"%s", str];
        [gTbDefaults setObject: uuid
                        forKey: installationIdKey];
    }
    return uuid;
}


// Returns TRUE if it is OK to update because the application name is still 'Tunnelblick'
// Returns FALSE iff Sparkle Updates should be disabled because the application name has been changed.
// Warns user about it if tellUser is TRUE
-(BOOL) appNameIsTunnelblickWarnUserIfNot: (BOOL) tellUser
{
    // Sparkle Updater doesn't work if the user has changed the name to something other than Tunnelblick
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *appName = [gFileMgr displayNameAtPath: bundlePath];
    if (  [appName isEqualToString:@"Tunnelblick"]
       || [appName isEqualToString:@"Tunnelblick.app"]  ) {
        return TRUE;
    }
    
    NSLog(@"Cannot check for updates because the name of Tunnelblick has been changed");
    if (  tellUser  ) {
        TBRunAlertPanelExtended(NSLocalizedString(@"Updates are disabled", @"Window title"),
                                [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick can only be updated if its name is 'Tunnelblick'. You have changed the name to %@, so updates are disabled.", @"Window text"), appName],
                                NSLocalizedString(@"OK", @"Button"),    // Default button
                                nil,
                                nil,
                                @"skipWarningThatNameChangeDisabledUpdates",
                                NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
                                nil);
    }
    return FALSE;
}

-(void) dmgCheck
{
    [NSApp setAutoLaunchOnLogin: NO];
    
	NSString * currentPath = [[NSBundle mainBundle] bundlePath];
	if (  [self cannotRunFromVolume: currentPath]  ) {
        
        NSString * appVersion   = tunnelblickVersion([NSBundle mainBundle]);
        
        NSString * standardPath;
        
        // Use a standardPath of /Applications/Tunnelblick.app unless overridden by a forced preference
        NSDictionary * forcedDefaults = [NSDictionary dictionaryWithContentsOfFile: [gDeployPath stringByAppendingPathComponent: @"forced-preferences.plist"]];
        standardPath = @"/Applications/Tunnelblick.app";
        id obj = [forcedDefaults objectForKey:@"standardApplicationPath"];
        if (  obj  ) {
            if (  [[obj class] isSubclassOfClass: [NSString class]]  ) {
                standardPath = [obj stringByExpandingTildeInPath];
            } else {
                NSLog(@"'standardApplicationPath' preference ignored because it is not a string.");
            }
        }
        
        NSString * preMessage = NSLocalizedString(@"Tunnelblick cannot be used from this location. It must be installed on a local hard drive.\n\n", @"Window text");
        NSString * displayApplicationName = [gFileMgr displayNameAtPath: @"Tunnelblick.app"];
        
        NSString * standardFolder = [standardPath stringByDeletingLastPathComponent];
        
        NSString * standardPathDisplayName = [[gFileMgr componentsToDisplayForPath: standardPath] componentsJoinedByString: @"/"];
        
        NSString * standardFolderDisplayName = [[gFileMgr componentsToDisplayForPath: standardFolder] componentsJoinedByString: @"/"];
        
        NSString * launchWindowTitle;
        NSString * launchWindowText;
        int response;
        
        NSString * changeLocationText = [NSString stringWithFormat: NSLocalizedString(@"(To install to a different location, drag %@ to that location.)", @"Window text"), displayApplicationName];
        
        if (  [gFileMgr fileExistsAtPath: standardPath]  ) {
            NSBundle * previousBundle = [NSBundle bundleWithPath: standardPath];
            int previousBuild = [self intValueOfBuildForBundle: previousBundle];
            int currentBuild  = [self intValueOfBuildForBundle: [NSBundle mainBundle]];
            NSString * previousVersion = tunnelblickVersion(previousBundle);
            if (  currentBuild < previousBuild  ) {
                launchWindowTitle = NSLocalizedString(@"Downgrade succeeded", @"Window title");
                launchWindowText = NSLocalizedString(@"Tunnelblick was successfully downgraded.\n\nDo you wish to launch Tunnelblick now?\n\n(An administrator username and password will be required so Tunnelblick can be secured.)", @"Window text");
                response = TBRunAlertPanel(NSLocalizedString(@"Downgrade Tunnelblick?", @"Window title"),
                                           [NSString stringWithFormat: [preMessage stringByAppendingString:
                                                                        NSLocalizedString(@"Do you wish to downgrade\n     %@\nto\n     %@?\n\nThe replaced version will be put in the Trash.\n\nInstall location: \"%@\"\n%@", @"Window text")], previousVersion, appVersion, standardFolderDisplayName, changeLocationText],
                                           NSLocalizedString(@"Downgrade", @"Button"),  // Default button
                                           NSLocalizedString(@"Cancel", @"Button"),     // Alternate button
                                           nil);                                        // Other button
            } else if (  currentBuild == previousBuild  ) {
                launchWindowTitle = NSLocalizedString(@"Reinstallation succeeded", @"Window title");
                launchWindowText = NSLocalizedString(@"Tunnelblick was successfully reinstalled.\n\nDo you wish to launch Tunnelblick now?\n\n(An administrator username and password will be required so Tunnelblick can be secured.)", @"Window text");
                response = TBRunAlertPanel(NSLocalizedString(@"Reinstall Tunnelblick?", @"Window title"),
                                           [NSString stringWithFormat: [preMessage stringByAppendingString:
                                                                        NSLocalizedString(@"Do you wish to reinstall\n     %@\nreplacing it with a fresh copy?\n\nThe old copy will be put in the Trash.\n\nInstall location: \"%@\"\n%@", @"Window text")], previousVersion, standardFolderDisplayName, changeLocationText],
                                           NSLocalizedString(@"Reinstall", @"Button"),  // Default button
                                           NSLocalizedString(@"Cancel", @"Button"),     // Alternate button
                                           nil);                                        // Other button
            } else {
                launchWindowTitle = NSLocalizedString(@"Upgrade succeeded", @"Window title");
                launchWindowText = NSLocalizedString(@"Tunnelblick was successfully upgraded.\n\nDo you wish to launch Tunnelblick now?\n\n(An administrator username and password will be required so Tunnelblick can be secured.)", @"Window text");
                previousVersion = tunnelblickVersion(previousBundle);
                response = TBRunAlertPanel(NSLocalizedString(@"Upgrade Tunnelblick?", @"Window title"),
                                           [NSString stringWithFormat: [preMessage stringByAppendingString:
                                                                        NSLocalizedString(@"Do you wish to upgrade\n     %@\nto\n     %@?\n\nThe old version will be put in the Trash.\n\nInstall location: \"%@\"\n%@", @"Window text")], previousVersion, appVersion, standardFolderDisplayName, changeLocationText],
                                           NSLocalizedString(@"Upgrade", @"Button"),    // Default button
                                           NSLocalizedString(@"Cancel", @"Button"),     // Alternate button
                                           nil);                                        // Other button
            }
        } else {
            launchWindowTitle = NSLocalizedString(@"Installation succeeded", @"Window title");
            launchWindowText = NSLocalizedString(@"Tunnelblick was successfully installed.\n\nDo you wish to launch Tunnelblick now?\n\n(An administrator username and password will be required so Tunnelblick can be secured.)", @"Window text");
            response = TBRunAlertPanel(NSLocalizedString(@"Install Tunnelblick?", @"Window title"),
                                       [NSString stringWithFormat: [preMessage stringByAppendingString:
                                                                    NSLocalizedString(@"Do you wish to install Tunnelblick in\n\"%@\"?\n\n%@", @"Window text")], standardFolderDisplayName, changeLocationText],
                                       NSLocalizedString(@"Install", @"Button"),    // Default button
                                       NSLocalizedString(@"Cancel", @"Button"),     // Alternate button
                                       nil);                                        // Other button
        }
        
        if (  response == NSAlertDefaultReturn  ) {
            
            // Install, Reinstall, Upgrade, or Downgrade
            if (  [gFileMgr fileExistsAtPath: standardPath]  ) {
                int tag;
                if (  [[NSWorkspace sharedWorkspace] performFileOperation: NSWorkspaceRecycleOperation source: standardFolder destination: standardFolder files: [NSArray arrayWithObject: [standardPath lastPathComponent]] tag: &tag]  ) {
                    NSLog(@"Moved %@ to Trash", standardPath);
                }
            }
            
            if (  [gFileMgr fileExistsAtPath: standardPath]  ) {
                NSLog(@"Unable to move %@ to Trash", standardPath);
                TBRunAlertPanel(NSLocalizedString(@"Unable to move previous version to Trash", @"Window title"),
                                [NSString stringWithFormat: NSLocalizedString(@"An error occurred while trying to move the previous version of %@ to the Trash.\n\nThe previous version is %@", @"Window text"), displayApplicationName, standardPathDisplayName],
                                NSLocalizedString(@"Cancel", @"Button"),                // Default button
                                nil,
                                nil);
            } else {
                if (  ! [gFileMgr copyPath: currentPath toPath: standardPath handler: nil]  ) {
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
                                } while (   (numberOfOthers > 0)
                                         && (i < 10)  );
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

// Returns TRUE if can't run Tunnelblick from this volume (can't run setuid binaries) or if statfs on it fails, FALSE otherwise
-(BOOL) cannotRunFromVolume: (NSString *)path
{
    if ([path hasPrefix:@"/Volumes/Tunnelblick"]  ) {
        return TRUE;
    }
    
    const char * fileName = [path UTF8String];
    struct statfs stats_buf;
    int status;
    
    if (  0 == (status = statfs(fileName, &stats_buf))  ) {
        if (  (stats_buf.f_flags & MNT_NOSUID) == 0  ) {
            return FALSE;
        }
    } else {
        NSLog(@"statfs returned error %@; treating %@ as if it were on a remote volume", [NSString stringWithCString:strerror(errno)], path);
    }
    return TRUE;   // Network volume or error accessing the file's data.
}

// After  r357, the build number is in Info.plist as "CFBundleVersion"
// From   r126 through r357, the build number was in Info.plist as "Build"
// Before r126, there was no build number
-(int)intValueOfBuildForBundle: (NSBundle *) theBundle
{
    int result = 0;
    id infoVersion = [theBundle objectForInfoDictionaryKey: @"CFBundleVersion"];
    
    id appBuild;
    if (   [[infoVersion class] isSubclassOfClass: [NSString class]]
        && [infoVersion rangeOfString: @"."].location == NSNotFound  ) {
        // No "." in version, so it is a build number
        appBuild   = infoVersion;
    } else {
        // "." in version, so build must be separate
        appBuild   = [theBundle objectForInfoDictionaryKey: @"Build"];
    }
    
    if (  appBuild  ) {
        if (  [[appBuild class] isSubclassOfClass: [NSString class]]  ) {
            NSString * tmpString = appBuild;
            result = [tmpString intValue];
        } else if (  [[appBuild class] isSubclassOfClass: [NSNumber class]] ) {
            NSNumber * tmpNumber = appBuild;
            result = [tmpNumber intValue];
        }
    }
    
    return result;
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
            msg = NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the program to secure it.", @"Window text");
            break;
        case 3:
            msg = NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the program to secure it and restore configuration(s) from the backup.", @"Window text");
            break;
        case 4:
            msg = NSLocalizedString(@"Tunnelblick needs to remove the configuration(s) backup.", @"Window text");
            break;
        case 5:
            msg = NSLocalizedString(@"Tunnelblick needs to restore configuration(s) from the backup and then remove the backup.", @"Window text");
            break;
        case 6:
            msg = NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the program to secure it and remove the configuration(s) backup.", @"Window text");
            break;
        case 7:
            msg = NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the program to secure it, restore configuration(s) from the backup, and remove the backup.", @"Window text");
            break;
        case 8:
            msg = NSLocalizedString(@"Tunnelblick needs to move the configurations folder.", @"Window text");
            break;
        case 9:
            msg = NSLocalizedString(@"Tunnelblick needs to restore configuration(s) from the backup and move the configurations folder.", @"Window text");
            break;
        case 10:
            msg = NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the program to secure it and move the configurations folder.", @"Window text");
            break;
        case 11:
            msg = NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the program to secure it, restore configuration(s) from the backup, and move the configurations folder.", @"Window text");
            break;
        case 12:
            msg = NSLocalizedString(@"Tunnelblick needs to move the configurations folder and remove the configuration(s) backup.", @"Window text");
            break;
        case 13:
            msg = NSLocalizedString(@"Tunnelblick needs to restore configuration(s) from the backup, remove the backup, and move the configurations folder.", @"Window text");
            break;
        case 14:
            msg = NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the program to secure it, remove the backup of configuration(s), and move the configurations folder.", @"Window text");
            break;
        case 15:
            msg = NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the program to secure it, restore configuration(s) from the backup, remove the backup, and move the configurations folder.", @"Window text");
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
    OSStatus status;
    BOOL installFailed;
    BOOL needsChangeOwnershipAndOrPermissions;
    BOOL needsMoveLibraryOpenVPN;
    do {
        if (  i != 5  ) {
            sleep(1);
        }
        status = [NSApplication executeAuthorized: installer withArguments: args withAuthorizationRef: authRef];
        installFailed = [gFileMgr fileExistsAtPath: @"/tmp/TunnelblickInstallationFailed.txt"];
        if (  installFailed  ) {
            [gFileMgr removeFileAtPath: @"/tmp/TunnelblickInstallationFailed.txt" handler: nil];
        }
    } while (   [self needsInstallation: &needsChangeOwnershipAndOrPermissions moveLibrary: &needsMoveLibraryOpenVPN]
             && (i-- > 0)  );
    
    AuthorizationFree(authRef, kAuthorizationFlagDefaults);
    
    if (   (status != EXIT_SUCCESS)
        || installFailed
        || needsChangeOwnershipAndOrPermissions
        || needsMoveLibraryOpenVPN
        ) {
        NSLog(@"Installation or repair failed");
        TBRunAlertPanel(NSLocalizedString(@"Installation or Repair Failed", "Window title"),
                        NSLocalizedString(@"The installation, removal, recovery, or repair of one or more Tunnelblick components failed. See the Console Log for details.", "Window text"),
                        nil, nil, nil);
        return FALSE;
    }
    
    NSLog(@"Installation or repair succeded");
    return TRUE;
}

// Checks ownership and permissions of critical files and whether ~/Library/openvpn has been moved to ~/Library/Application Support/Tunnelblick/Configurations (for 3.0b24)
// Returns with the respective arguments set YES or NO, and returns YES if either one is YES. Otherwise returns NO.
-(BOOL) needsInstallation: (BOOL *) changeOwnershipAndOrPermissions moveLibrary: (BOOL *) moveLibraryOpenVPN
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
    
    // Check ~/Library/Application Support/Tunnelblick/Configurations
    if (  [gFileMgr fileExistsAtPath: newParentDirPath isDirectory: &isDir]  ) {
        newParentExists = TRUE;
        if (  isDir  ) {
            if (  [gFileMgr fileExistsAtPath: newConfigDirPath isDirectory: &isDir]  ) {
                if (  isDir  ) {
                    newFolderExists = TRUE; // New folder exists, so we've already moved (check that's true below)
                } else {
                    NSLog(@"Error: %@ exists but is not a folder", newConfigDirPath);
                    [self terminateBecauseOfBadConfiguration];
                }
            } else {
                // New folder does not exist. That's OK if ~/Library/openvpn doesn't exist
            }
        } else {
            NSLog(@"Error: %@ exists but is not a folder", newParentDirPath);
            [self terminateBecauseOfBadConfiguration];
        }
    } else {
        // New folder's holder does not exist, so we need to do the move only if ~Library/openvpn exists and is a folder (which we check for below)
    }
    
    // If it exists, ~/Library/openvpn must either be a directory, or a symbolic link to ~/Library/Application Support/Tunnelblick/Configurations
    NSDictionary * fileAttributes = [gFileMgr fileAttributesAtPath: oldConfigDirPath traverseLink: NO];
    if (  ! [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
        if (  [gFileMgr fileExistsAtPath: oldConfigDirPath isDirectory: &isDir]  ) {
            if (  isDir  ) {
                if (  newFolderExists  ) {
                    NSLog(@"Error: Both %@ and %@ exist and are folders, so %@ cannot be moved", oldConfigDirPath, newConfigDirPath, oldConfigDirPath);
                    [self terminateBecauseOfBadConfiguration];
                } else {
                    if (  newParentExists  ) {
                        NSLog(@"Error: %@ exists and is a folder, but %@ already exists, so %@ cannot be moved", oldConfigDirPath, newParentDirPath, oldConfigDirPath);
                        [self terminateBecauseOfBadConfiguration];
                    }
                    *moveLibraryOpenVPN = YES;  // old folder exists, but new one doesn't, so do the move
                }
            } else {
                NSLog(@"Error: %@ exists but is not a symbolic link or a folder", oldConfigDirPath);
                [self terminateBecauseOfBadConfiguration];
            }
        } else {
            // ~/Library/openvpn does not exist, so we don't do the move (whether or not the new folder exists)
        }
    } else {
        // ~/Library/openvpn is a symbolic link
        if (  [[gFileMgr pathContentOfSymbolicLinkAtPath: oldConfigDirPath] isEqualToString: newConfigDirPath]  ) {
            if (  newFolderExists  ) {
                // ~/Library/openvpn is a symbolic link to ~/Library/Application Support/Tunnelblick/Configurations, which exists, so we've already done the move
            } else {
                NSLog(@"Error: %@ exists and is a symbolic link but its target, %@, does not exist", oldConfigDirPath, newConfigDirPath);
                [self terminateBecauseOfBadConfiguration];
            }
        } else {
            NSLog(@"Error: %@ exists and is a symbolic link but does not reference %@", oldConfigDirPath, newConfigDirPath);
            [self terminateBecauseOfBadConfiguration];
        }
    }
    
	// Check ownership and permissions on components of Tunnelblick.app
    NSBundle *thisBundle = [NSBundle mainBundle];
	
	NSString *installerPath         = [thisBundle pathForResource:@"installer"                      ofType:nil];
	NSString *openvpnstartPath      = [thisBundle pathForResource:@"openvpnstart"                   ofType:nil];
	NSString *openvpnPath           = [thisBundle pathForResource:@"openvpn"                        ofType:nil];
	NSString *leasewatchPath        = [thisBundle pathForResource:@"leasewatch"                     ofType:nil];
	NSString *clientUpPath          = [thisBundle pathForResource:@"client.up.osx.sh"               ofType:nil];
	NSString *clientDownPath        = [thisBundle pathForResource:@"client.down.osx.sh"             ofType:nil];
	NSString *clientNoMonUpPath     = [thisBundle pathForResource:@"client.nomonitor.up.osx.sh"     ofType:nil];
	NSString *clientNoMonDownPath   = [thisBundle pathForResource:@"client.nomonitor.down.osx.sh"   ofType:nil];
    NSString *infoPlistPath         = [[[installerPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"Info.plist"];
	
	// check openvpnstart owned by root, set uid, owner may execute
	const char *path = [openvpnstartPath UTF8String];
    struct stat sb;
	if(stat(path,&sb)) {
        runUnrecoverableErrorPanel(@"Unable to determine status of \"openvpnstart\"");
	}
    
	if (   ! (
              (sb.st_mode & S_ISUID) // set uid bit is set
              && (sb.st_mode & S_IXUSR) // owner may execute it
              && (sb.st_uid == 0) // is owned by root
              )
        ) {
		NSLog(@"openvpnstart has missing set uid bit, is not owned by root, or owner can't execute it");
        *changeOwnershipAndOrPermissions = YES;
		return YES;		
	}
	
	// check files which should be owned by root with 744 permissions
	NSArray *inaccessibleObjects = [NSArray arrayWithObjects: installerPath, openvpnPath, leasewatchPath, clientUpPath, clientDownPath, clientNoMonUpPath, clientNoMonDownPath, nil];
	NSEnumerator *e = [inaccessibleObjects objectEnumerator];
	NSString *currentPath;
	while(currentPath = [e nextObject]) {
        if (  ! [self isOwnedByRootAtPath: currentPath withPermissions: @"744"]  ) {
            *changeOwnershipAndOrPermissions = YES;
            return YES; // NSLog already called
        }
	}
    
    // check Info.plist
    if (  ! [self isOwnedByRootAtPath: infoPlistPath withPermissions: @"644"]  ) {
        return YES; // NSLog already called
    }

    // check permissions of files in Resources/Deploy (if any)        
    if (  [self folderContentsNeedToBeSecuredAtPath: [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"Deploy"]]  ) {
        *changeOwnershipAndOrPermissions = YES;
        return YES;
    }
    
    // check permissions of files in the Deploy backup, also (if any)        
    NSString * deployBackupPath = [[[[@"/Library/Application Support/Tunnelblick/Backup" stringByAppendingPathComponent: [[NSBundle mainBundle] bundlePath]]
                                     stringByDeletingLastPathComponent]
                                    stringByAppendingPathComponent: @"TunnelblickBackup"]
                                   stringByAppendingPathComponent: @"Deploy"];
    
    if (  [self folderContentsNeedToBeSecuredAtPath: deployBackupPath]  ) {
        *changeOwnershipAndOrPermissions = YES;
        return YES;
    }
    
    return *moveLibraryOpenVPN;
}

-(void) terminateBecauseOfBadConfiguration
{
    TBRunAlertPanel(NSLocalizedString(@"Tunnelblick Configuration Problem", @"Window title"),
                    NSLocalizedString(@"Tunnelblick could not be launched because of a problem with the configuration. Please examine the Console Log for details.", @"Window text"),
                    nil, nil, nil);
    [NSApp setAutoLaunchOnLogin: NO];
    [NSApp terminate: nil];
}

-(BOOL) folderContentsNeedToBeSecuredAtPath: (NSString *) theDirPath
{
    NSArray * extensionsFor600Permissions = [NSArray arrayWithObjects: @"cer", @"crt", @"der", @"key", @"p12", @"p7b", @"p7c", @"pem", @"pfx", nil];
    NSString * file;
    BOOL isDir;
    NSDirectoryEnumerator *dirEnum = [gFileMgr enumeratorAtPath: theDirPath];
    while (file = [dirEnum nextObject]) {
        NSString * filePath = [theDirPath stringByAppendingPathComponent: file];
        NSString * ext  = [file pathExtension];
        if (   [gFileMgr fileExistsAtPath: filePath isDirectory: &isDir]
            && isDir  ) {
            if (  ! [self isOwnedByRootAtPath: filePath withPermissions: @"755"]  ) {
                return YES; // NSLog already called
            }
        } else if ( [ext isEqualToString:@"sh"]  ) {
            if (  ! [self isOwnedByRootAtPath: filePath withPermissions: @"744"]  ) {
                return YES; // NSLog already called
            }
        } else if (  [extensionsFor600Permissions containsObject: ext]  ) {
            if (  ! [self isOwnedByRootAtPath: filePath withPermissions: @"600"]  ) {
                return YES; // NSLog already called
            }
        } else { // including .conf and .ovpn
            if (  ! [self isOwnedByRootAtPath: filePath withPermissions: @"644"]  ) {
                return YES; // NSLog already called
            }
        }
    }
    return NO;
}

-(BOOL) isOwnedByRootAtPath: (NSString *) fPath withPermissions: (NSString *) permsShouldHave
{
    NSDictionary *fileAttributes = [gFileMgr fileAttributesAtPath:fPath traverseLink:YES];
    unsigned long perms = [fileAttributes filePosixPermissions];
    NSString *octalString = [NSString stringWithFormat:@"%o",perms];
    NSNumber *fileOwner = [fileAttributes fileOwnerAccountID];
    
    if (   [octalString isEqualToString: permsShouldHave]
        && [fileOwner isEqualToNumber:[NSNumber numberWithInt:0]]  ) {
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
		if(NSDebugEnabled) NSLog(@"Restoring Connection %@",[connection displayName]);
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
