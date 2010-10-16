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

#import <Foundation/NSDebug.h>
#import <Security/AuthSession.h>
#import <sys/stat.h>
#import <sys/mount.h>
#import <uuid/uuid.h>
#import "defines.h"
#import "MenuController.h"
#import "NSApplication+LoginItem.h"
#import "NSApplication+NetworkNotifications.h"
#import "NSApplication+SystemVersion.h"
#import "helper.h"
#import "TBUserDefaults.h"
#import "ConfigurationManager.h"
#import "VPNConnection.h"


// These are global variables rather than class variables to make access to them easier
NSMutableArray        * gConfigDirs;          // Array of paths to configuration directories currently in use
NSString              * gDeployPath;          // Path to Tunnelblick.app/Contents/Resources/Deploy
NSString              * gPrivatePath;         // Path to ~/Library/Application Support/Tunnelblick/Configurations
NSString              * gSharedPath;          // Path to /Library/Application Support/Tunnelblick/Shared
TBUserDefaults        * gTbDefaults;          // Our preferences
NSFileManager         * gFileMgr;             // [NSFileManager defaultManager]
NSDictionary          * gOpenVPNVersionDict;  // Dictionary with OpenVPN version information
SecuritySessionId       gSecuritySessionId;   // Session ID used to create temporary files
unsigned int            gHookupTimeout;       // Number of seconds to try to establish communications with (hook up to) an OpenVPN process
//                                               or zero to keep trying indefinitely
UInt32 fKeyCode[16] = {0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64,        // KeyCodes for F1...F16
    0x65, 0x6D, 0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A};

void terminateBecauseOfBadConfiguration(void);

OSStatus hotKeyPressed(EventHandlerCallRef nextHandler,EventRef theEvent, void * userData);

extern BOOL folderContentsNeedToBeSecuredAtPath(NSString * theDirPath);
extern BOOL checkOwnerAndPermissions(NSString * fPath, uid_t uid, gid_t gid, NSString * permsShouldHave);

@interface NSStatusBar (NSStatusBar_Private)
- (id)_statusItemWithLength:(float)l withPriority:(int)p;
- (id)_insertStatusItem:(NSStatusItem *)i withPriority:(int)p;
@end

@interface MenuController() // PRIVATE METHODS

// System interfaces:
-(BOOL)             application:                            (NSApplication *)   theApplication
                      openFiles:                            (NSArray * )        filePaths;

-(void)             applicationDidFinishLaunching:          (NSNotification *)  notification;

-(void)             applicationWillFinishLaunching:         (NSNotification *)  notification;

-(void)             applicationWillTerminate:               (NSNotification*)   notification;

// Private interfaces
-(void)             addCustomMenuItems;
-(BOOL)             addCustomMenuItemsFromFolder:           (NSString *)        folderPath
                                          toMenu:           (NSMenu *)          theMenu;
-(void)             addOneCustomMenuItem:                   (NSString *)        file
                              fromFolder:                   (NSString *)        folder
                                  toMenu:                   (NSMenu *)          theMenu;
-(BOOL)             addOneCustomMenuSubmenu:                (NSString *)        file
                                 fromFolder:                (NSString *)        folder
                                     toMenu:                (NSMenu *)          theMenu;
-(void)             addPath:                                (NSString *)        path
             toMonitorQueue:                                (UKKQueue *)        queue;
-(void)             activateStatusMenu;
-(void)             addNewConfig:                           (NSString *)        path
                 withDisplayName:                           (NSString *)        dispNm;
-(BOOL)             appNameIsTunnelblickWarnUserIfNot:      (BOOL)              tellUser;
-(BOOL)             cannotRunFromVolume:                    (NSString *)        path;
-(NSString *)       deconstructOpenVPNLogPath:              (NSString *)        logPath
                                       toPort:              (int *)             portPtr
                                  toStartArgs:              (NSString * *)      startArgsPtr;
-(NSArray *)        findTblksToInstallInPath:               (NSString *)        thePath;
-(void)             fixWhenConnectingButtons;
-(void)             checkNoConfigurations;
-(void)             createMenu;
-(void)             createStatusItem;
-(void)             deleteExistingConfig:                   (NSString *)        dispNm;
-(void)             dmgCheck;
-(int)              firstDifferentComponent:                (NSArray *)         a
                          and:                              (NSArray *)         b;
-(int)              getLoadedKextsMask;
-(void)             hookupWatchdogHandler;
-(void)             hookupWatchdog;
-(void)             hookupToRunningOpenVPNs;
-(NSString *)       indent:                                 (NSString *)        s
                        by:                                 (int)               n;
-(NSMenuItem *)     initPrefMenuItemWithTitle:              (NSString *)        title
                                    andAction:              (SEL)               action
                                   andToolTip:              (NSString *)        tip
                           atIndentationLevel:              (int)               indentLevel
                             andPreferenceKey:              (NSString *)        prefKey
                                      negated:              (BOOL)              negatePref;
-(void)             initialiseAnim;
-(void)             insertConnectionMenuItem:               (NSMenuItem *)      theItem
                                    IntoMenu:               (NSMenu *)          theMenu
                                  afterIndex:               (int)               theIndex
                                    withName:               (NSString *)        displayName;
-(NSString *)       installationId;
-(int)              intValueOfBuildForBundle:               (NSBundle *)        theBundle;
-(void)             killAllConnectionsIncludingDaemons:     (BOOL)              includeDaemons;
-(void)             loadMenuIconSet;
-(void)             makeSymbolicLink;
-(NSString *)       menuNameForItem:                        (NSMenuItem *)      theItem;
-(NSString *)       menuNameFromFilename:                   (NSString *)        inString;
-(void)             removeConnectionWithDisplayName:        (NSString *)        theName
                                           FromMenu:        (NSMenu *)          theMenu
                                         afterIndex:        (int)               theIndex;
-(void)             removePath:                             (NSString *)        path
              fromMonitorQueue:                             (UKKQueue *)        queue;
-(void)             runCustomMenuItem:                      (NSMenuItem *)      item;
-(BOOL)             runInstallerRestoreDeploy:              (BOOL)              restore
                                      copyApp:              (BOOL)              copyIt
                                    repairApp:              (BOOL)              repairIt
                           moveLibraryOpenVPN:              (BOOL)              moveConfigs
                               repairPackages:              (BOOL)              repairPkgs;
-(void)             saveMonitorConnectionCheckboxState:     (BOOL)              inBool;
-(void)             saveOnSystemStartRadioButtonState:      (BOOL)              onSystemStart
                                        forConnection:      (VPNConnection *)   connection;
-(void)             saveAutoLaunchCheckboxState:            (BOOL)              inBool;
-(void)             saveUseNameserverPopupButtonState:      (unsigned)          inValue;
-(VPNConnection *)  selectedConnection;
-(NSTextView *)     selectedLogView;
-(void)             setLogWindowTitle;
-(void)             setTitle:                               (NSString *)        newTitle
                   ofControl:                               (id)                theControl;
-(void)             setupHotKeyWithCode:                    (UInt32)            keyCode
                        andModifierKeys:                    (UInt32)            modifierKeys;
-(void)             setupSparklePreferences;
-(void)             startOrStopDurationsTimer;
-(NSStatusItem *)   statusItem;
-(NSString *)       timeLabelForConnection:                 (VPNConnection *)   connection;
-(void)             toggleMenuItem:                         (NSMenuItem *)      item
                 withPreferenceKey:                         (NSString *)        prefKey;
-(void)             updateMenuAndLogWindow;
-(void)             updateNavigationLabels;
-(void)             updateUI;
-(void)             validateConnectAndDisconnectButtonsForConnection: (VPNConnection *) connection;
-(void)             validateWhenConnectingForConnection:    (VPNConnection *)   connection;
-(void)             validateDetailsWindowControls;
-(BOOL)             validateMenuItem:                       (NSMenuItem *)      anItem;
-(void)             watcher:                                (UKKQueue *)        kq
       receivedNotification:                                (NSString *)        nm
                    forPath:                                (NSString *)        fpath;
@end

@implementation MenuController

-(id) init
{	
    if (self = [super init]) {
        
        if (  ! runningOnTigerOrNewer()  ) {
            TBRunAlertPanel(NSLocalizedString(@"System Requirements Not Met", @"Window title"),
                            NSLocalizedString(@"Tunnelblick requires OS X 10.4 or above\n     (\"Tiger\", \"Leopard\", or \"Snow Leopard\")", @"Window text"),
                            nil, nil, nil);
            [NSApp terminate:self];
            
        }
        
        launchFinished = FALSE;
        hotKeyEventHandlerIsInstalled = FALSE;
        
        noUnknownOpenVPNsRunning = NO;   // We assume there are unattached processes until we've had time to hook up to them
        
        showDurationsTimer = nil;
        
        // Use a session ID in temporary files to support fast user switching
        OSStatus error;
        SessionAttributeBits sessionInfo;
        error = SessionGetInfo(callerSecuritySession, &gSecuritySessionId, &sessionInfo);
        if (  error != 0  ) {
            gSecuritySessionId = 0;
        }
        
        dotTblkFileList = nil;
        oldSelectedConnectionName = nil;
        hotKeySubmenuItemThatIsOn = nil;
        customRunOnLaunchPath = nil;
        customRunOnConnectPath = nil;
        customMenuScripts = nil;
        
        tunCount = 0;
        tapCount = 0;
        
        selectedModifyNameserverIndex = -1; // Won't match any valid value, so when first set it will trigger a change notice
        
        gFileMgr    = [NSFileManager defaultManager];
        
        gDeployPath = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"Deploy"] copy];
        gSharedPath = [@"/Library/Application Support/Tunnelblick/Shared" copy];
        gPrivatePath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Tunnelblick/Configurations"] copy];
        
		gConfigDirs = [[NSMutableArray alloc] initWithCapacity: 2];
        
		[NSApp setDelegate: self];
		
        userIsAnAdmin = isUserAnAdmin();
        
        // Create folder for OpenVPN log and scripts log if necessary
        if (  createDir(LOG_DIR, 0777) == -1  ) {
            NSLog(@"Warning: Tunnelblick was unable to create a temporary log folder at %@", LOG_DIR);
            [NSApp setAutoLaunchOnLogin: NO];
            [NSApp terminate:self];
        }
        
        // Create private configurations folder if necessary
        createDir(gPrivatePath, 0755);
        
        [self dmgCheck];    // If running from a place that can't do suid (e.g., a disk image), this method does not return
		
        // Try to create a symbolic link to the private configurations folder from its old place (~/Library/openvpn)
        // May fail if old place hasn't been moved yet, so we do it again later anyway.
        // The installer can't do this on some networked home directories because root on this
        // computer may not have permission to modify the home directory on the network server.
        [self makeSymbolicLink];
        
        // Run the installer only if necessary. The installer restores Resources/Deploy and/or repairs permissions,
        // moves the config folder if it hasn't already been moved, and backs up Resources/Deploy if it exists
        BOOL needsChangeOwnershipAndOrPermissions;
        BOOL needsMoveLibraryOpenVPN;
        BOOL needsRestoreDeploy;
        BOOL needsPkgRepair;
        if (  needToRunInstaller( &needsChangeOwnershipAndOrPermissions, &needsMoveLibraryOpenVPN, &needsRestoreDeploy, &needsPkgRepair, FALSE )  ) {
            if (  ! [self runInstallerRestoreDeploy: needsRestoreDeploy
                                            copyApp: FALSE
                                          repairApp: needsChangeOwnershipAndOrPermissions
                                 moveLibraryOpenVPN: needsMoveLibraryOpenVPN
                                     repairPackages: needsPkgRepair]  ) {
                // runInstallerRestoreDeploy has already put up an error dialog and put a message in the console log if error occurred
                [NSApp setAutoLaunchOnLogin: NO];
                [NSApp terminate:self];
            }
        }
        
        // Try again to create a symbolic link to the private configurations folder, after having run the installer (which may have moved the
        // configuration folder contents to the new place)
        [self makeSymbolicLink];
        
        // Set up to override user preferences from Deploy/forced-permissions.plist if it exists,
        // Otherwise use our equivalent of [NSUserDefaults standardUserDefaults]
        NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: [gDeployPath stringByAppendingPathComponent: @"forced-preferences.plist"]];
        gTbDefaults = [[TBUserDefaults alloc] initWithForcedDictionary: dict
                                                andSecondaryDictionary: nil
                                                     usingUserDefaults: YES];
        
        // Set default preferences as needed
        if (  [gTbDefaults objectForKey: @"showConnectedDurations"] == nil  ) {
            [gTbDefaults setBool: TRUE forKey: @"showConnectedDurations"];
        }
        
        // If Resources/Deploy exists now (perhaps after being restored) and has one or more .tblk packages or .conf or .ovpn files,
        // Then make it the first entry in gConfigDirs
        BOOL isDir;
        if (   [gFileMgr fileExistsAtPath: gDeployPath isDirectory: &isDir]
            && isDir ) {
            NSString * file;
            NSDirectoryEnumerator *dirEnum = [gFileMgr enumeratorAtPath: gDeployPath];
            while (file = [dirEnum nextObject]) {
                NSString * path = [gDeployPath stringByAppendingPathComponent: file];
                if (  itemIsVisible(path)  ) {
                    NSString * ext  = [file pathExtension];
                    if (   [gFileMgr fileExistsAtPath: path isDirectory: &isDir]
                        && ( ! isDir)  ) {
                        if ( [ext isEqualToString:@"conf"] || [ext isEqualToString:@"ovpn"]  ) {
                            [gConfigDirs addObject: [[gDeployPath copy] autorelease]];
                            break;
                        }
                    } else {
                        if ( [ext isEqualToString:@"tblk"]  ) {
                            [gConfigDirs addObject: [[gDeployPath copy] autorelease]];
                            break;
                        }
                    }
                }
            }
        }
        
        // If not Deployed, or if Deployed and it is specifically allowed,
        // Then add /Library/Application Support/Tunnelblick/Shared
        //      and ~/Library/Application Support/Tunnelblick/Configurations
        //      to configDirs
        if (  [gConfigDirs count] == 0  ) {
            [gConfigDirs addObject: [[gSharedPath  copy] autorelease]];
            [gConfigDirs addObject: [[gPrivatePath copy] autorelease]];
        } else {
            if (  ! [gTbDefaults canChangeValueForKey: @"useSharedConfigurationsWithDeployedOnes"]  ) {
                if (  [gTbDefaults boolForKey: @"useSharedConfigurationsWithDeployedOnes"]  ) {
                    [gConfigDirs addObject: [[gSharedPath copy] autorelease]];
                }
            }
            if (  ! [gTbDefaults canChangeValueForKey: @"usePrivateConfigurationsWithDeployedOnes"]  ) {
                if (  [gTbDefaults boolForKey: @"usePrivateConfigurationsWithDeployedOnes"]  ) {
                    [gConfigDirs addObject: [[gPrivatePath copy] autorelease]];
                }
            }
        }
        
        // Create a link to this application in the private configurations folder if we are using it
        if (  [gConfigDirs containsObject: gPrivatePath]  ) {
            if (  ! [gTbDefaults boolForKey: @"doNotCreateLaunchTunnelblickLinkinConfigurations"]  ) {
                NSString * pathToThisApp = [[NSBundle mainBundle] bundlePath];
                NSString * launchTunnelblickSymlinkPath = [gPrivatePath stringByAppendingPathComponent: @"Launch Tunnelblick"];
                NSString * linkContents = [gFileMgr pathContentOfSymbolicLinkAtPath: launchTunnelblickSymlinkPath];
                if (  linkContents == nil  ) {
                    [gFileMgr removeFileAtPath: launchTunnelblickSymlinkPath handler: nil];
                    if (  [gFileMgr createSymbolicLinkAtPath: launchTunnelblickSymlinkPath
                                                   pathContent: pathToThisApp]  ) {
                        NSLog(@"Created 'Launch Tunnelblick' link in Configurations folder; links to %@", pathToThisApp);
                    } else {
                        NSLog(@"Unable to create 'Launch Tunnelblick' link in Configurations folder linking to %@", pathToThisApp);
                    }
                } else if (  ! [linkContents isEqualToString: pathToThisApp]  ) {
                    ignoreNoConfigs = TRUE; // We're dealing with no configs already, and will either quit or create one
                    if (  ! [gFileMgr removeFileAtPath: launchTunnelblickSymlinkPath handler: nil]  ) {
                        NSLog(@"Unable to remove %@", launchTunnelblickSymlinkPath);
                    }
                    if (  [gFileMgr createSymbolicLinkAtPath: launchTunnelblickSymlinkPath
                                                   pathContent: pathToThisApp]  ) {
                        NSLog(@"Replaced 'Launch Tunnelblick' link in Configurations folder; now links to %@", pathToThisApp);
                    } else {
                        NSLog(@"Unable to create 'Launch Tunnelblick' link in Configurations folder linking to %@", pathToThisApp);
                    }
                }
            }
        }
        
        gOpenVPNVersionDict = [getOpenVPNVersion() copy];
        
        myVPNConnectionDictionary = [[NSMutableDictionary alloc] init];
        connectionArray = [[[NSMutableArray alloc] init] retain];
        
        [self loadMenuIconSet];
        
		[self createStatusItem];
		
        // Get hot key keyCode and modifiers
        id code = [gTbDefaults objectForKey: @"keyboardShortcutKeyCode"];
        if (  [code respondsToSelector: @selector(unsignedIntValue)]  ) {
            hotKeyKeyCode = (UInt32) [code unsignedIntValue];
        } else {
            hotKeyKeyCode = 0x7A;   /* F1 key */
        }
        code = [gTbDefaults objectForKey: @"keyboardShortcutModifiers"];
        if (  [code respondsToSelector: @selector(unsignedIntValue)]  ) {
            hotKeyModifierKeys = (UInt32) [code unsignedIntValue];
        } else {
            hotKeyModifierKeys = cmdKey+optionKey;
        }
        
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
		
        ignoreNoConfigs = TRUE;    // We ignore the "no configurations" situation until we've processed application:openFiles:
		
        updater = [[SUUpdater alloc] init];
        
    }
    
    return self;
}

// Attempts to make a symbolic link from the old configurations folder to the new configurations folder
- (void) makeSymbolicLink
{
    BOOL isDir;
    NSString * oldConfigDirPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/openvpn"];
    NSDictionary * fileAttributes = [gFileMgr fileAttributesAtPath: oldConfigDirPath traverseLink: NO];
    if (  [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
        // A symbolic link exists
        if (  ! [[gFileMgr pathContentOfSymbolicLinkAtPath: oldConfigDirPath] isEqualToString: gPrivatePath]  ) {
            NSLog(@"Warning: %@ exists and is a symbolic link but does not reference %@. Attempting repair...", oldConfigDirPath, gPrivatePath);
            if (  ! [gFileMgr removeFileAtPath: oldConfigDirPath handler: nil]  ) {
                NSLog(@"Warning: Unable to remove %@", oldConfigDirPath);
            }
            if (  ! [gFileMgr createSymbolicLinkAtPath: oldConfigDirPath
                                           pathContent: gPrivatePath]  ) {
                NSLog(@"Warning: Unable to change symbolic link %@ to point to %@", oldConfigDirPath, gPrivatePath);
            }
        }
        
    } else {
        // Not a symbolic link
        if (  [gFileMgr fileExistsAtPath: oldConfigDirPath isDirectory: &isDir]  ) {
            if (  isDir  ) {
                // If empty (i.e., only has invisible files), delete it and create the symlink
                BOOL isEmpty = TRUE;
                NSDirectoryEnumerator *dirEnum = [gFileMgr enumeratorAtPath: oldConfigDirPath];
                NSString * file;
                while (file = [dirEnum nextObject]) {
                    if (  itemIsVisible([oldConfigDirPath stringByAppendingPathComponent: file])  ) {
                        isEmpty = FALSE;
                        break;
                    }
                }
                if (  isEmpty  ) {
                    if (  [gFileMgr removeFileAtPath: oldConfigDirPath handler: nil]  ) {
                        if (  [gFileMgr createSymbolicLinkAtPath: oldConfigDirPath
                                                     pathContent: gPrivatePath]  ) {
                            NSLog(@"Replaceed %@ with a symbolic link to %@", oldConfigDirPath, gPrivatePath);
                        } else {
                            NSLog(@"Warning: Unable to create a symbolic link to %@ at %@", gPrivatePath, oldConfigDirPath);
                        }
                    } else {
                        NSLog(@"Warning: unable to remove %@ folder to replace it with a symbolic link", oldConfigDirPath);
                    }
                } else {
                    NSLog(@"Warning: %@ is a folder which is not empty.", oldConfigDirPath);
                }
            } else {
                NSLog(@"Warning: %@ exists but is not a symbolic link or a folder.", oldConfigDirPath);
            }
        } else {
            if (  [gFileMgr createSymbolicLinkAtPath: oldConfigDirPath
                                         pathContent: gPrivatePath]  ) {
                NSLog(@"Created a symbolic link to %@ at %@", gPrivatePath, oldConfigDirPath);
            } else {
                NSLog(@"Warning: Unable to create a symbolic link to %@ at %@", gPrivatePath, oldConfigDirPath);
            }
        }
    }
}    

- (void) dealloc
{
    [animImages release];
    [connectedImage release];
    [mainImage release];
    
    [gConfigDirs release];
    
    [gTbDefaults release];
    [oldSelectedConnectionName release];
    [connectionArray release];
    [connectionsToRestore release];
    [gDeployPath release];
    [dotTblkFileList release];
    [lastState release];
    [gPrivatePath release];
    [myConfigDictionary release];
    [myVPNConnectionDictionary release];
    [myVPNMenu release];
    [showDurationsTimer release];
    [hookupWatchdogTimer release];
    [theAnim release];
    [updater release];
    [gOpenVPNVersionDict release];
    [customMenuScripts release];
    [customRunOnLaunchPath release];
    [customRunOnConnectPath release];
    
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
    [hotKeySubmenuItemThatIsOn release];
    [hotKeySubmenuItem release];
    [hotKeySubmenu release];
    [statusMenuItem release];
    [statusItem release];
    
    [super dealloc];
}

-(NSMutableDictionary *) myVPNConnectionDictionary
{
    return [[myVPNConnectionDictionary copy] autorelease];
}

-(NSMutableDictionary *) myConfigDictionary
{
    return [[myConfigDictionary copy] autorelease];
}

-(BOOL) userIsAnAdmin
{
    return userIsAnAdmin;
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
        
        if ( ! statusItem  ) {
            if (  ! ( statusItem = [[bar _statusItemWithLength: NSVariableStatusItemLength withPriority: priority] retain] )  ) {
                NSLog(@"Can't insert icon in Status Bar");
            }
        }
        // Re-insert item to place it correctly, to the left of SpotLight
        [bar removeStatusItem: statusItem];
        [bar _insertStatusItem: statusItem withPriority: priority];
    } else {
        // Standard placement of icon in Status Bar
        if (  ! statusItem  ) {
            if (  ! (statusItem = [[bar statusItemWithLength: NSVariableStatusItemLength] retain])  ) {
                NSLog(@"Can't insert icon in Status Bar");
            }
        }
    }
}

- (void) menuExtrasWereAdded: (NSNotification*) n
{
	[self performSelectorOnMainThread: @selector(createStatusItem) withObject: nil waitUntilDone: NO];
}


- (IBAction) quit: (id) sender
{
    // Remove us from the login items if terminates manually...
    [NSApp setAutoLaunchOnLogin: NO];
    [NSApp terminate: sender];
}



- (void) awakeFromNib
{
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
        
        if (  itemIsVisible(fullPath)  ) {
            if ([[file pathExtension] isEqualToString: @"png"]) {
                NSString *name = [[file lastPathComponent] stringByDeletingPathExtension];
                
                if (  [name isEqualToString:@"closed"]) {
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
    }
    
    // don't choke on a bad set of files, e.g., {0.png, 1abc.png, 2abc.png, 3.png, 4.png, 6.png}
    // (won't necessarily find all files, but won't try to load files that don't exist)
    for(i=0;i<nFrames;i++) {
        fullPath = [confDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.png", i]];
        if (  itemIsVisible(fullPath)  ) {
            if ([gFileMgr fileExistsAtPath:fullPath]) {
                NSImage *frame = [[NSImage alloc] initWithContentsOfFile:fullPath];
                [animImages addObject:frame];
                [frame release];
            }
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
    hotKeySubmenu = nil;
    
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
        if (  ! [gTbDefaults boolForKey:@"doNotShowAddConfigurationMenuItem"]  ) {
            addConfigurationItem = [[NSMenuItem alloc] init];
            [addConfigurationItem setTitle: NSLocalizedString(@"Add a Configuration...", @"Menu item")];
            [addConfigurationItem setTarget: self];
            [addConfigurationItem setAction: @selector(addConfigurationWasClicked:)];
        }
        
        if (  ! [gTbDefaults boolForKey:@"doNotShowKeyboardShortcutSubmenu"]  ) {
            hotKeySubmenu = [[NSMenu alloc] init];
            [hotKeySubmenu setTitle: NSLocalizedString(@"Keyboard Shortcut", @"Menu item")];
            
            // Virtual Key Codes for F1...F16. Taken from Snow Leopard HIToolBox/Events.h
            int j;
            for (j=0; j<16; j++) {
                if (  fKeyCode[j] == hotKeyKeyCode  ) {
                    break;
                }
            }
            int i;
            // We allow F1...F12 so the menu isn't too long (and MacBook keyboards only go that high, anyway)
            for (i=0; i<12; i++) {
                hotKeySubmenuItem =  [[NSMenuItem alloc] init];
                const unichar cmdOptionChars[] = {0x2318,' ',0x2325};
                NSString * cmdOptionString = [NSString stringWithCharacters: cmdOptionChars
                                                             length: sizeof cmdOptionChars / sizeof * cmdOptionChars];
                [hotKeySubmenuItem setTitle: [NSString stringWithFormat: @"%@ F%d", cmdOptionString , i+1]];
                [hotKeySubmenuItem setTarget: self];
                [hotKeySubmenuItem setAction: @selector(hotKeySubmenuItemWasClicked:)];
                [hotKeySubmenuItem setRepresentedObject: [NSNumber numberWithInt: i]];
                if (  i == j  ) {
                    [hotKeySubmenuItem setState: NSOnState];
                    hotKeySubmenuItemThatIsOn = [hotKeySubmenuItem retain];
                } else {
                    [hotKeySubmenuItem setState: NSOffState];
                }
                
                [hotKeySubmenu addItem: hotKeySubmenuItem];
            }
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
        if (  hotKeySubmenu  ) {
            hotKeySubmenuItem = [[NSMenuItem alloc] init];
            [hotKeySubmenuItem setTitle: NSLocalizedString(@"Keyboard Shortcut", @"Menu item")];
            [hotKeySubmenuItem setIndentationLevel: 1];
            [hotKeySubmenuItem setSubmenu: hotKeySubmenu];
            [optionsSubmenu addItem: hotKeySubmenuItem];
        }
        
        if (   putIconNearSpotlightItem
            || monitorConfigurationDirItem
            || warnAboutSimultaneousItem
            || showConnectedDurationsItem
            || useShadowCopiesItem
            || autoCheckForUpdatesItem
            || reportAnonymousInfoItem
            || hotKeySubmenu  ) {
            [optionsSubmenu addItem: [NSMenuItem separatorItem]];
        }

        if (  addConfigurationItem  ) {
            [optionsSubmenu addItem: addConfigurationItem];
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
    
    noConfigurationsItem = [[NSMenuItem alloc] init];
    [noConfigurationsItem setTitle: NSLocalizedString(@"No VPN Configurations Available", @"Menu item")];
    
    detailsItem = [[NSMenuItem alloc] init];
    [detailsItem setTitle: NSLocalizedString(@"Details...", @"Menu item")];
    // We set the target and action below, but only if there are any configurations,
    // so it is dimmed/disabled if there aren't any configuratinos
    
    quitItem = [[NSMenuItem alloc] init];
    [quitItem setTitle: NSLocalizedString(@"Quit Tunnelblick", @"Menu item")];
    [quitItem setTarget: self];
    [quitItem setAction: @selector(quit:)];
    
    [statusItem setHighlightMode:YES];
    [statusItem setMenu:nil];
	[myVPNMenu release]; myVPNMenu = nil;
	[[myVPNConnectionDictionary allValues] makeObjectsPerformSelector:@selector(disconnectAndWait:) withObject: [NSNumber numberWithBool: YES]];
	[myVPNConnectionDictionary removeAllObjects];
	
	myVPNMenu = [[NSMenu alloc] init];
    [myVPNMenu setDelegate:self];
	[statusItem setMenu: myVPNMenu];
    
	statusMenuItem = [[NSMenuItem alloc] init];
	[myVPNMenu addItem:statusMenuItem];
	[myVPNMenu addItem:[NSMenuItem separatorItem]];
    
	[myConfigDictionary release];
    myConfigDictionary = [[[[ConfigurationManager defaultManager] getConfigurations] mutableCopy] retain];
    
    // Add each connection to the menu
    NSString * dispNm;
    NSArray *keyArray = [myConfigDictionary allKeys];
	NSEnumerator * e = [keyArray objectEnumerator];
    while (dispNm = [e nextObject]) {
		NSMenuItem *connectionItem = [[[NSMenuItem alloc] init] autorelease];
		NSString * cfgPath = [myConfigDictionary objectForKey: dispNm];
        
        // configure connection object:
		VPNConnection* myConnection = [[VPNConnection alloc] initWithConfigPath: cfgPath
                                                                withDisplayName: dispNm];
		[myConnection setDelegate:self];
        
		[myVPNConnectionDictionary setObject: myConnection forKey: dispNm];
        
        // Note: The menu item's title will be set on demand in VPNConnection's validateMenuItem
		[connectionItem setTarget:myConnection]; 
		[connectionItem setAction:@selector(toggle:)];
        
        [self insertConnectionMenuItem: connectionItem IntoMenu: myVPNMenu afterIndex: 2 withName: [[connectionItem target] displayName]];
	}
    
    if (  [myConfigDictionary count] == 0  ) {
        [myVPNMenu addItem: noConfigurationsItem];
        if (  addConfigurationItem  ) {
            [myVPNMenu addItem: [[addConfigurationItem copy] autorelease]]; // Use a copy because the original is used in the Options... submenu
        }
    } else {
        [detailsItem setTarget: self];
        [detailsItem setAction: @selector(openLogWindow:)];
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
    
    [self addCustomMenuItems];
    
    [myVPNMenu addItem: quitItem];
    
}

-(void) insertConnectionMenuItem: (NSMenuItem *) theItem IntoMenu: (NSMenu *) theMenu afterIndex: (int) theIndex withName: (NSString *) theName
{
    int i;
    NSRange    slashRange = [theName rangeOfString: @"/" options: 0 range: NSMakeRange(0, [theName length] - 1)];
    if (   (slashRange.length == 0)
        || [gTbDefaults boolForKey: @"doNotShowConnectionSubmenus"]  ) {
        // The item goes directly in the menu
        for (  i=theIndex; i < [theMenu numberOfItems]; i++  ) {
            id menuItem = [theMenu itemAtIndex: i];
            NSString * menuItemTitle;
            if (  [menuItem isSeparatorItem]  ) {
                break;                       // A separator marks the end of list of connection items
            }
            if (   [menuItem submenu]  ) {    // item is a submenu
                menuItemTitle = [menuItem title];
            } else {                                                            // item is a connection item
                menuItemTitle = [self menuNameForItem: menuItem];
            }
            
            if (  [menuItemTitle caseInsensitiveCompare: theName] == NSOrderedDescending  ) {
                break;
            }
        }
        [theMenu insertItem: theItem atIndex: i];
        return;
    }
    
    // The item goes on a submenu
    NSString * subMenuName = [theName substringWithRange: NSMakeRange(0, slashRange.location + 1)];
    NSString * restOfName = [theName substringFromIndex: slashRange.location + 1];
    for (  i=theIndex; i < [theMenu numberOfItems]; i++  ) {
        id menuItem = [theMenu itemAtIndex: i];
        if (  [menuItem isSeparatorItem]  ) {
            break; // A separator marks the end of list of connection items
        } else {
            NSMenu * subMenu = [menuItem submenu];
            if (  subMenu   ) {
                // Item is a submenu
                NSString * menuItemTitle = [menuItem title];
                NSComparisonResult  result = [menuItemTitle caseInsensitiveCompare: subMenuName];
                if (  result == NSOrderedSame  ) {
                    // Have found correct submenu, so add this item to it
                    [self insertConnectionMenuItem: theItem IntoMenu: subMenu afterIndex: 0 withName: restOfName];
                    return;
                }
                if (  result == NSOrderedDescending  ) {
                    // Have found a different submenu that comes later
                    break;
                }
            }
        }
    }
    
    // Didn't find the submenu, so we have to create a new submenu and try again.
    
    // Create the new submenu
    NSMenu * newSubmenu = [[[NSMenu alloc] initWithTitle:@"A Configuration SubMenu Title"] autorelease];
    
    // Create a new submenu item for the outer menu
    NSMenuItem * newMenuItem = [[NSMenuItem alloc] init];
    [newMenuItem setTitle: subMenuName];
    [newMenuItem setSubmenu: newSubmenu];
    
    // Add the new submenu item to the outer menu
    [self insertConnectionMenuItem: newMenuItem IntoMenu: theMenu afterIndex: theIndex withName: subMenuName];
    
    // Insert the original item we wanted to (now that the submenu has been created)
    [self insertConnectionMenuItem: theItem IntoMenu: theMenu afterIndex: theIndex withName: theName];
}

-(NSString *) menuNameForItem: (NSMenuItem *) theItem
{
    NSString * theName = [[theItem target] displayName];
    NSRange    slashRange = [theName rangeOfString: @"/" options: NSBackwardsSearch];
    if (  slashRange.length == 0  ) {
        return theName;
    }
    
    return [theName substringFromIndex: slashRange.location + 1];
}

-(void) addCustomMenuItems
{
    // Reset custom script variables
    customMenuScriptIndex = 0;
    [customMenuScripts release];
    customMenuScripts = [[NSMutableArray alloc] init];
    
    // Process the contents of the Menu folder
    NSString * menuDirPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"/Deploy/Menu"];
    if (  [self addCustomMenuItemsFromFolder: menuDirPath toMenu: myVPNMenu]  ) {
        [myVPNMenu addItem: [NSMenuItem separatorItem]];
    }
}

// Note: this method is indirectly recursive because it invokes addOneCustomMenuSubmenu, which may invoke this method
-(BOOL) addCustomMenuItemsFromFolder: (NSString *) folderPath toMenu: (NSMenu *) theMenu
{
    // List the items in the folder
    NSMutableArray * itemsInMenuFolder = [[[NSMutableArray alloc] init] autorelease];
    NSString * file;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: folderPath];
    while (file = [dirEnum nextObject]) {
        [dirEnum skipDescendents];
        [itemsInMenuFolder addObject: file];
    }
    
    // Sort the list
	NSArray *sortedArray = [itemsInMenuFolder sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];

    // Use the sorted list to add items to the Tunnelblick menu, or to run them on launch or on connect
    BOOL haveAddedItems = FALSE;
    BOOL isDir;
    
    int i;
    for (i=0; i<[sortedArray count]; i++) {
        file = [sortedArray objectAtIndex: i];
        NSString * fullPath = [folderPath stringByAppendingPathComponent: file];
        if (  itemIsVisible(fullPath)  ) {
            if (   [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]  ) {
                if (  isDir  ) {
                    haveAddedItems = [self addOneCustomMenuSubmenu: file fromFolder: folderPath toMenu: theMenu] || haveAddedItems;
                } else if (  [[file pathExtension] isEqualToString: @"executable"]  ) {
                    NSString * name = [file stringByDeletingPathExtension];
                    if (  [[name pathExtension] isEqualToString: @"wait"]  ) {
                        name = [name stringByDeletingPathExtension];
                    }
                    NSString * extension = [name pathExtension];
                    if (  [extension isEqualToString: @"runOnLaunch"]  ) {
                        if (  customRunOnLaunchPath  ) {
                            NSLog(@"%@ is being ignored; %@ is already set up to be run on launch", fullPath, customRunOnLaunchPath);
                        } else {
                            customRunOnLaunchPath = [fullPath copy];
                        }
                    } else if (  [extension isEqualToString: @"runOnConnect"]  ) {
                        if (  customRunOnConnectPath  ) {
                            NSLog(@"%@ is being ignored; %@ is already set up to be run on connect", fullPath, customRunOnConnectPath);
                        } else {
                            customRunOnConnectPath = [fullPath copy];
                        }
                    } else if (  [extension isEqualToString: @"addToMenu"]  ) {
                        [self addOneCustomMenuItem: file fromFolder: folderPath toMenu: theMenu];
                        haveAddedItems = TRUE;
                    }
                }
            }
        }
    }
    
    return haveAddedItems;
}

-(BOOL) addOneCustomMenuSubmenu: (NSString *) file fromFolder: (NSString *) folder toMenu: (NSMenu *) theMenu
{
    NSMenu * subMenu = [[[NSMenu alloc] init] autorelease];
    if (  [self addCustomMenuItemsFromFolder: [folder stringByAppendingPathComponent: file] toMenu: subMenu]  ) {
        NSMenuItem * subMenuItem = [[[NSMenuItem alloc] init] autorelease];
        [subMenuItem setTitle: NSLocalizedString([self menuNameFromFilename: file], @"Menu item")];
        [subMenuItem setSubmenu: subMenu];
        [theMenu addItem: subMenuItem];
        return TRUE;
    }
    
    return FALSE;
}

-(void) addOneCustomMenuItem: (NSString *) file fromFolder: (NSString *) folder toMenu: (NSMenu *) theMenu
{
    NSMenuItem * item = [[[NSMenuItem alloc] init] autorelease];
    [item setTitle: NSLocalizedString([self menuNameFromFilename: file], @"Menu item")];
    [item setTarget: self];
    [item setAction: @selector(runCustomMenuItem:)];
    [item setTag: customMenuScriptIndex++];

    NSString * scriptPath = [folder stringByAppendingPathComponent: file];
    [customMenuScripts addObject: scriptPath];
    
    [theMenu addItem: item];
}

// Strips off .addToMenu, .wait, and .executable from the end of a string, and everything up to and including the first underscore
-(NSString *) menuNameFromFilename: (NSString *) inString
{
    NSString * s = [[inString copy] autorelease];
    if (  [[s pathExtension] isEqualToString: @"executable"]  ) {
        s = [s stringByDeletingPathExtension];
    }
    
    if (  [[s pathExtension] isEqualToString: @"wait"]  ) {
        s = [s stringByDeletingPathExtension];
    }
    
    if (  [[s pathExtension] isEqualToString: @"addToMenu"]  ) {
        s = [s stringByDeletingPathExtension];
    }
    
    NSRange underscoreRange = [s rangeOfString: @"_"];
    if (  underscoreRange.length != 0  ) {
        if (  underscoreRange.location == [s length] -1  ) {
            NSLog(@"Not stripping through the underscore from the name of menu item %@ because there is nothing after the underscore", inString);
            return s;
        }
        return [s substringFromIndex: underscoreRange.location+1];
    }
    
    return s;
}

-(void) runCustomMenuItem: (NSMenuItem *) item
{
    int tag = [item tag];
    NSString * scriptPath = [customMenuScripts objectAtIndex: tag];
    NSTask* task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath: scriptPath];
	[task setArguments: [NSArray array]];
	[task setCurrentDirectoryPath: [scriptPath stringByDeletingLastPathComponent]];
	[task launch];
    if (  [[[scriptPath stringByDeletingPathExtension] pathExtension] isEqualToString: @"wait"]) {
        [task waitUntilExit];
    }
}

-(void) removeConnectionWithDisplayName: (NSString *) theName FromMenu: (NSMenu *) theMenu afterIndex: (int) theIndex
{
    int i;
    NSRange slashRange = [theName rangeOfString: @"/" options: 0 range: NSMakeRange(0, [theName length] - 1)];
    if (   (slashRange.length == 0)
        || [gTbDefaults boolForKey: @"doNotShowConnectionSubmenus"]  ) {
        // The item is directly in the menu
        for (  i=theIndex; i < [theMenu numberOfItems]; i++  ) {
            id menuItem = [theMenu itemAtIndex: i];
            NSString * menuItemTitle;
            if (  [menuItem isSeparatorItem]  ) {
                break;                              // A separator marks the end of list of connection items
            }
            if (   [menuItem submenu]  ) {          // item is a submenu
                menuItemTitle = [menuItem title];
            } else {                                // item is a connection item
                menuItemTitle = [self menuNameForItem: menuItem];
            }
            
            if (  [menuItemTitle caseInsensitiveCompare: theName] == NSOrderedSame  ) {
                [theMenu removeItemAtIndex: i];
                return;
            }
        }
        
        NSLog(@"Unable to find '%@' in the menu, removal failed", theName);
        return;
    }

    // The item is on a submenu
    NSString * subMenuName = [theName substringWithRange: NSMakeRange(0, slashRange.location + 1)];
    NSString * restOfName = [theName substringFromIndex: slashRange.location + 1];
    for (  i=theIndex; i < [theMenu numberOfItems]; i++  ) {
        id menuItem = [theMenu itemAtIndex: i];
        if (  [menuItem isSeparatorItem]  ) {
            break; // A separator marks the end of list of connection items
        } else {
            NSMenu * subMenu = [menuItem submenu];
            if (  subMenu   ) {
                // Item is a submenu
                NSString * menuItemTitle = [menuItem title];
                if (  [menuItemTitle caseInsensitiveCompare: subMenuName] == NSOrderedSame  ) {
                    // Have found correct submenu, so remove this item from it
                    [self removeConnectionWithDisplayName: restOfName FromMenu: subMenu afterIndex: 0];
                    if (  [subMenu numberOfItems] == 0  ) {
                        // No more items on the submenu, so delete it, too
                        [theMenu removeItemAtIndex: i];
                    }
                    return;
                }
            }
        }
    }
    
    NSLog(@"Unable to find submenu '%@' in the menu, removal failed", restOfName);
}

// Note: ToolTips are disabled because they interfere with VoiceOver
-(NSMenuItem *)initPrefMenuItemWithTitle: (NSString *) title
                               andAction: (SEL) action
                              andToolTip: (NSString *) tip
                      atIndentationLevel: (int) indentLevel
                        andPreferenceKey: (NSString *) prefKey
                                 negated: (BOOL) negatePref
{
    if (  [gTbDefaults canChangeValueForKey:prefKey] || ( ! [gTbDefaults boolForKey: @"doNotShowForcedPreferenceMenuItems"] )  ) {
        NSMenuItem * menuItem = [[NSMenuItem alloc] init];
        [menuItem setTitle:   title];
        [menuItem setTarget:  self];
        [menuItem setAction:  action];
        if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
            [menuItem setToolTip: tip];
        }
        [menuItem setIndentationLevel: indentLevel];
        [menuItem setRepresentedObject: prefKey];
        BOOL state = [gTbDefaults boolForKey:prefKey];
        state = negatePref ? ! state : state;
        if (  state  ) {
            [menuItem setState: NSOnState];
        } else {
            [menuItem setState: NSOffState];
        }
        return menuItem;
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
            if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
                [anItem setToolTip: NSLocalizedString(@"Disabled because you cannot administer this computer and the 'onlyAdminCanUpdate' preference is set", @"Menu item tooltip")];
            }
            return NO;
        } else if (  ! [updater respondsToSelector:@selector(setSendsSystemProfile:)]  ) {
            if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
                [anItem setToolTip: NSLocalizedString(@"Disabled because Sparkle Updater does not respond to setSendsSystemProfile:", @"Menu item tooltip")];
            }
            return NO;
        }
        if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
            [anItem setToolTip: NSLocalizedString(@"Takes effect at the next check for updates", @"Menu item tooltip")];
        }
    } else if (  act == @selector(toggleAutoCheckForUpdates:)  ) {
        [anItem setState: NSOffState];
        
        [self setupSparklePreferences]; // If first run, Sparkle may have changed the auto update preference
        
        if (   [gTbDefaults boolForKey:@"onlyAdminCanUpdate"]
            && ( ! userIsAnAdmin )  ) {
            if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
                [anItem setToolTip: NSLocalizedString(@"Disabled because you cannot administer this computer and the 'onlyAdminCanUpdate' preference is set", @"Menu item tooltip")];
            }
            return NO;
        } else if (  ! [updater respondsToSelector:@selector(setAutomaticallyChecksForUpdates:)]  ) {
            if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
                [anItem setToolTip: NSLocalizedString(@"Disabled because Sparkle Updater does not respond to setAutomaticallyChecksForUpdates:", @"Menu item tooltip")];
            }
            return NO;
        } else if (  ! [self appNameIsTunnelblickWarnUserIfNot: NO]  ) {
            if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
                [anItem setToolTip: NSLocalizedString(@"Disabled because the name of the application has been changed", @"Menu item tooltip")];
            }
            return NO;
        }
        if (  [gTbDefaults boolForKey:@"updateCheckAutomatically"]  ) {
            [anItem setState: NSOnState];
        }
        if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
            [anItem setToolTip: NSLocalizedString(@"Takes effect the next time Tunnelblick is launched", @"Menu item tooltip")];
        }
    } else if (  act == @selector(checkForUpdates:)  ) {
        if (   [gTbDefaults boolForKey:@"onlyAdminCanUpdate"]
            && ( ! userIsAnAdmin )  ) {
            if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
                [anItem setToolTip: NSLocalizedString(@"Disabled because you cannot administer this computer and the 'onlyAdminCanUpdate' preference is set", @"Menu item tooltip")];
            }
            return NO;
        } else if (  ! [self appNameIsTunnelblickWarnUserIfNot: NO]  ) {
            if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
                [anItem setToolTip: NSLocalizedString(@"Disabled because the name of the application has been changed", @"Menu item tooltip")];
            }
            return NO;
        }
        if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
            [anItem setToolTip: @""];
        }
    } else {
        if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
            [anItem setToolTip: @""];
        }
    }
    
    // We store the preference key for a menu item in the item's representedObject so we can do the following:
    if (  [anItem representedObject]  ) {
        if (  ! [gTbDefaults canChangeValueForKey: [anItem representedObject]]  ) {
            if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
                [anItem setToolTip: NSLocalizedString(@"Disabled because this setting is being forced", @"Menu item tooltip")];
            }
            return NO;
        }
    }
    
    return YES;
}

-(void)togglePlaceIconNearSpotlight: (NSMenuItem *) menuItem
{
    [self toggleMenuItem: menuItem withPreferenceKey: @"placeIconInStandardPositionInStatusBar"];
}

-(void)toggleMonitorConfigurationDir: (NSMenuItem *) menuItem
{
    [self toggleMenuItem: menuItem withPreferenceKey: @"doNotMonitorConfigurationFolder"];
    if (  [gTbDefaults boolForKey: @"doNotMonitorConfigurationFolder"]  ) {
        int i;
        for (i = 0; i < [gConfigDirs count]; i++) {
            [self removePath: [gConfigDirs objectAtIndex: i] fromMonitorQueue: myQueue];
        }
    } else {
        int i;
        for (i = 0; i < [gConfigDirs count]; i++) {
            [self addPath: [gConfigDirs objectAtIndex: i] toMonitorQueue: myQueue];
        }
        [self activateStatusMenu];
    }
}

-(void)toggleWarnAboutSimultaneous: (NSMenuItem *) menuItem
{
    [self toggleMenuItem: menuItem withPreferenceKey: @"skipWarningAboutSimultaneousConnections"];
}

-(void)toggleConnectionTimers: (NSMenuItem *) menuItem
{
    [self toggleMenuItem: menuItem withPreferenceKey: @"showConnectedDurations"];
    [self startOrStopDurationsTimer];
    [self updateNavigationLabels];
}

// Starts or stops the timer for showing connection durations.
// Starts it (or lets it continue) if it is enabled and any tunnels are connected; stops it otherwise
-(void) startOrStopDurationsTimer
{
    if (  showDurationsTimer == nil  ) {
        // Timer is inactive. Start it if enabled and any tunnels are connected
        if (  [gTbDefaults boolForKey:@"showConnectedDurations"]  ) {
            VPNConnection * conn;
            NSEnumerator * connEnum = [myVPNConnectionDictionary objectEnumerator];
            while (  conn = [connEnum nextObject]  ) {
                if (  [[conn state] isEqualToString: @"CONNECTED"]) {
                    showDurationsTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0
                                                                           target:self
                                                                         selector:@selector(updateNavigationLabels)
                                                                         userInfo:nil
                                                                          repeats:YES] retain];
                    return;
                }
            }
        }
    } else {
        // Timer is active. Stop it if not enabled or if no tunnels are connected.
        if (  ! [gTbDefaults boolForKey:@"showConnectedDurations"]  ) {
            [showDurationsTimer invalidate];
            [showDurationsTimer release];
            showDurationsTimer = nil;
        } else {
            VPNConnection * conn;
            NSEnumerator * connEnum = [myVPNConnectionDictionary objectEnumerator];
            while (  conn = [connEnum nextObject]  ) {
                if (  [[conn state] isEqualToString: @"CONNECTED"]) {
                    return;
                }
            }
            
            [showDurationsTimer invalidate];
            [showDurationsTimer release];
            showDurationsTimer = nil;
        }
    }
}

-(void)toggleUseShadowCopies: (NSMenuItem *) menuItem
{
    [self toggleMenuItem: menuItem withPreferenceKey: @"useShadowConfigurationFiles"];
}

-(void)toggleAutoCheckForUpdates: (NSMenuItem *) menuItem
{
    if (  [updater respondsToSelector: @selector(setAutomaticallyChecksForUpdates:)]  ) {
        if (  ! [gTbDefaults boolForKey:@"updateCheckAutomatically"]  ) {
            // Was OFF, trying to change to ON
            if (  [self appNameIsTunnelblickWarnUserIfNot: NO]  ) {
                [self toggleMenuItem: menuItem withPreferenceKey: @"updateCheckAutomatically"];
                [updater setAutomaticallyChecksForUpdates: YES];
            } else {
                NSLog(@"'Automatically Check for Updates' change ignored because the name of the application has been changed");
            }
        } else {
            // Was ON, change to OFF
            [self toggleMenuItem: menuItem withPreferenceKey: @"updateCheckAutomatically"];
            [updater setAutomaticallyChecksForUpdates: NO];
        }
    } else {
        NSLog(@"'Automatically Check for Updates' change ignored because Sparkle Updater does not respond to setAutomaticallyChecksForUpdates:");
    }
}

-(void)toggleReportAnonymousInfo: (NSMenuItem *) menuItem
{
    if (  [updater respondsToSelector: @selector(setSendsSystemProfile:)]  ) {
        [self toggleMenuItem: menuItem withPreferenceKey: @"updateSendProfileInfo"];
        [updater setSendsSystemProfile: [gTbDefaults boolForKey:@"updateSendProfileInfo"]];
    } else {
        NSLog(@"'Send Anonymous System Profile' change ignored because Sparkle Updater does not respond to setSendsSystemProfile:");
    }
}

-(void)toggleMenuItem: (NSMenuItem *) menuItem withPreferenceKey: (NSString *) prefKey
{
    [gTbDefaults setBool: ! [gTbDefaults boolForKey:prefKey] forKey:prefKey];
    [gTbDefaults synchronize];
    
    if (  [menuItem state] == NSOnState  ) {
        [menuItem setState: NSOffState];
    } else {
        [menuItem setState:NSOnState];
    }
}

// If any new config files have been added, add each to the menu and add tabs for each to the Log window.
// If any config files have been deleted, remove them from the menu and remove their tabs in the Log window
-(void) updateMenuAndLogWindow 
{
    BOOL needToUpdateLogWindow = FALSE;         // If we changed any configurations, process the changes after we're done
    
    NSString * dispNm;
    
    NSDictionary * curConfigsDict = [[ConfigurationManager defaultManager] getConfigurations];
    
    // Add new configurations and replace updated ones
	NSEnumerator * e = [curConfigsDict keyEnumerator];
    while (dispNm = [e nextObject]) {
        BOOL sameDispNm = [myConfigDictionary objectForKey: dispNm] != nil;
        BOOL sameFolder = [[myConfigDictionary objectForKey: dispNm] isEqualToString: [curConfigsDict objectForKey: dispNm]];
        
        if (  sameDispNm  ) {
            if (  ! sameFolder  ) {
                    // Replace a configuration
                    [self deleteExistingConfig: dispNm];
                    [self addNewConfig: [curConfigsDict objectForKey: dispNm] withDisplayName: dispNm];
                    needToUpdateLogWindow = TRUE;
            }
        } else {
            // Add a configuration
            [self addNewConfig: [curConfigsDict objectForKey: dispNm] withDisplayName: dispNm]; // No old config with same name
            needToUpdateLogWindow = TRUE;
        }
    }
    
    // Remove configurations that are no longer available
	e = [myConfigDictionary keyEnumerator];
    while (dispNm = [e nextObject]) {
        BOOL sameDispNm = [curConfigsDict objectForKey: dispNm] != nil;
        
        if (  ! sameDispNm  ) {
            [self deleteExistingConfig: dispNm]; // No new config with same name
            needToUpdateLogWindow = TRUE;
        }
    }
    
	// If there aren't any configuration files left, deal with that
    [self checkNoConfigurations];
    
    if (  needToUpdateLogWindow  ) {
        // Add or remove configurations from the Log window (if it is open) by closing and reopening it
        BOOL logWindowWasOpen = logWindowIsOpen;
        [logWindow close];
        [logWindow release];
        logWindow = nil;
        if (  logWindowWasOpen  ) {
            [self openLogWindow:self];
        } else {
            oldSelectedConnectionName = nil;
        }

    }
}

// Add new config to myVPNConnectionDictionary, the menu, and myConfigDictionary
// Note: The menu item's title will be set on demand in VPNConnection's validateMenuItem
-(void) addNewConfig: (NSString *) path withDisplayName: (NSString *) dispNm
{
    VPNConnection* myConnection = [[VPNConnection alloc] initWithConfigPath: path
                                                            withDisplayName: dispNm];
    [myConnection setDelegate:self];
    [myVPNConnectionDictionary setObject: myConnection forKey: dispNm];
    
    NSMenuItem *connectionItem = [[[NSMenuItem alloc] init] autorelease];
    [connectionItem setTarget:myConnection]; 
    [connectionItem setAction:@selector(toggle:)];
    
    int itemIx = (int) [myVPNMenu indexOfItemWithTitle: NSLocalizedString(@"No VPN Configurations Available", @"Menu item")];
    if (  itemIx  != -1) {
        [myVPNMenu removeItemAtIndex: itemIx];
    }
    
    itemIx = (int) [myVPNMenu indexOfItemWithTitle: NSLocalizedString(@"Add a Configuration...", @"Menu item")];
    if (  itemIx  != -1) {
        [myVPNMenu removeItemAtIndex: itemIx];
    }
    
    [self insertConnectionMenuItem: connectionItem IntoMenu: myVPNMenu afterIndex: 2 withName: [[connectionItem target] displayName]];
    
    [detailsItem setTarget: self];
    [detailsItem setAction: @selector(openLogWindow:)];
    
    [myConfigDictionary setObject: path forKey: dispNm];
}

// Remove config from myVPNConnectionDictionary, the menu, and myConfigDictionary
// Disconnect first if necessary
-(void) deleteExistingConfig: (NSString *) dispNm
{
    VPNConnection* myConnection = [myVPNConnectionDictionary objectForKey: dispNm];
    if (  ! [[myConnection state] isEqualTo: @"EXITING"]  ) {
        [myConnection disconnectAndWait: [NSNumber numberWithBool: NO]];
        
        TBRunAlertPanel([NSString stringWithFormat: NSLocalizedString(@"'%@' has been disconnected", @"Window title"), dispNm],
                        [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick has disconnected '%@' because its configuration file has been removed.", @"Window text"), dispNm],
                        nil, nil, nil);
    }
    
    [myVPNConnectionDictionary removeObjectForKey: dispNm];
    
    [self removeConnectionWithDisplayName: dispNm FromMenu: myVPNMenu afterIndex: 2];

    [myConfigDictionary removeObjectForKey: dispNm];

    if (  [myConfigDictionary count] == 0  ) {
        int itemIx = (int) [myVPNMenu indexOfItemWithTitle: NSLocalizedString(@"No VPN Configurations Available", @"Menu item")];
        if (  itemIx  == -1  ) {
            [myVPNMenu insertItem: noConfigurationsItem atIndex: 2];
        }
        
        itemIx = (int) [myVPNMenu indexOfItemWithTitle: NSLocalizedString(@"Add a Configuration...", @"Menu item")];
        if (   (itemIx  == -1)
            && addConfigurationItem  ) {
            [myVPNMenu insertItem: [[addConfigurationItem copy] autorelease] atIndex: 3]; // Use a copy because the original is used in the Options... submenu
        }
        
        [detailsItem setTarget: nil];
        [detailsItem setAction: nil];
    }
}

- (void)activateStatusMenu
{
    [self updateUI];
    [self updateMenuAndLogWindow];
}

- (void)connectionStateDidChange:(id)connection
{
	[self updateNavigationLabels];
    if (connection == [self selectedConnection]) 
	{
		[self validateConnectAndDisconnectButtonsForConnection: connection];
	}	
}

// Validates (disables or enables) the Connect and Disconnect buttons in the Details... window
-(void) validateConnectAndDisconnectButtonsForConnection: (VPNConnection *) connection
{
    NSString * displayName = [connection displayName];
    
    NSString * disableConnectButtonKey    = [displayName stringByAppendingString: @"-disableConnectButton"];
    NSString * disableDisconnectButtonKey = [displayName stringByAppendingString: @"-disableDisconnectButton"];
    [connectButton setEnabled: (   [connection isDisconnected]
                                && ( ! [gTbDefaults boolForKey: disableConnectButtonKey] )  )];
    [disconnectButton setEnabled:(   ( ! [connection isDisconnected] )
                                  && ( ! [gTbDefaults boolForKey: disableDisconnectButtonKey] )  )];
}

// Validates the "when Tunnelblick launches" and "when the computer starts" radio buttons for the specified connection
-(void) validateWhenConnectingForConnection: (VPNConnection *) connection
{
    NSString * displayName      = [connection displayName];
    NSString * autoConnectKey   = [displayName stringByAppendingString:@"autoConnect"];
    NSString * onSystemStartKey = [displayName stringByAppendingString: @"-onSystemStart"];
    
    if (   [gTbDefaults boolForKey:autoConnectKey]  ) {
        if (  [gTbDefaults boolForKey: onSystemStartKey]  ) {
            if (  [[connection configPath] hasPrefix: gPrivatePath]  ) {
                // onSystemStart pref, but this is a private configuration, so force the pref off
                if (  [gTbDefaults canChangeValueForKey: onSystemStartKey]  ) {
                    [gTbDefaults setBool: FALSE forKey: onSystemStartKey];  // Shouldn't be set, so clear it
                    [self saveOnSystemStartRadioButtonState: TRUE forConnection: connection];
                    NSLog(@"The '-onSystemStart' preference was set but it has been cleared because '%@' is a private configuration", displayName);
                } else {
                    NSLog(@"The '-onSystemStart' preference for '%@' is being forced, but will be ignored because it is a private configuration", displayName);
                }
            } else {
                [self saveOnSystemStartRadioButtonState: TRUE forConnection: connection];
            }
        } else {
            [self saveOnSystemStartRadioButtonState: FALSE forConnection: connection];
        }
    } else {
        [self saveOnSystemStartRadioButtonState: FALSE forConnection: connection];
    }
    
    if (   [gTbDefaults boolForKey:autoConnectKey]
        && [gTbDefaults canChangeValueForKey: autoConnectKey]
        && [gTbDefaults canChangeValueForKey: onSystemStartKey]  ) {
        if (  [[connection configPath] hasPrefix: gPrivatePath]  ) {
            [onSystemStartRadioButton setEnabled: NO];
            [onLaunchRadioButton      setEnabled: NO];
        } else {
            [onSystemStartRadioButton setEnabled: YES];
            [onLaunchRadioButton      setEnabled: YES];
        }
        
        if (   [gTbDefaults boolForKey: autoConnectKey]
            && [gTbDefaults boolForKey: onSystemStartKey]  ) {
            [autoConnectCheckbox         setEnabled: NO];        // Disable other controls for daemon connections because otherwise
            [modifyNameserverPopUpButton setEnabled: NO];        // we have to update the daemon's .plist to reflect changes, and
            [monitorConnnectionCheckbox  setEnabled: NO];        // that requires admin authorization for each change
            [shareButton                 setEnabled: NO];
        }
    } else {
        [onLaunchRadioButton      setEnabled: NO];
        [onSystemStartRadioButton setEnabled: NO];
    }
}    

// Validates (sets and disables or enables) all of the controls in the Details... window (including the Connect and Disconnect buttons)
-(void) validateDetailsWindowControls
{
    VPNConnection* connection = [self selectedConnection];
    
    NSString * displayName = [connection displayName];
    
    [self validateConnectAndDisconnectButtonsForConnection: connection];

	// The "Edit configuration" button is also the "Examine Configuration" button so first we indicate which it is
    if (  [[ConfigurationManager defaultManager] userCanEditConfiguration: [[self selectedConnection] configPath]]  ) {
        [self setTitle: NSLocalizedString(@"Edit configuration", @"Button") ofControl: editButton];
    } else {
        [self setTitle: NSLocalizedString(@"Examine configuration", @"Button") ofControl: editButton];
    }
    
    NSString *disableEditConfigKey = [displayName stringByAppendingString:@"disableEditConfiguration"];
    if (  [gTbDefaults boolForKey:disableEditConfigKey]  ) {
        [editButton setEnabled: NO];
    } else {
        [editButton setEnabled: YES];
    }
    
	// The "Share configuration" button is also the "Make configuration private" button and it is only active when it is a .tblk configuration
    NSString *disableShareConfigKey = [displayName stringByAppendingString:@"disableShareConfigurationButton"];
    if (  ! [gTbDefaults boolForKey: disableShareConfigKey]  ) {
        NSString * path = [[self selectedConnection] configPath];
        if (  [[path pathExtension] isEqualToString: @"tblk"]  ) {
            if (  [path hasPrefix: gSharedPath]  ) {
                [self setTitle: NSLocalizedString(@"Make configuration private", @"Button") ofControl: shareButton];
                [shareButton setEnabled: YES];
            } else if (  [path hasPrefix: gPrivatePath]  ) {
                [self setTitle: NSLocalizedString(@"Share configuration"       , @"Button") ofControl: shareButton];
                [shareButton setEnabled: YES];
            } else {
                // Deployed, so we don't offer to share it or make it private
                [self setTitle: NSLocalizedString(@"Share configuration"       , @"Button") ofControl: shareButton];
                [shareButton setEnabled: NO];
            }
        } else {
            [self setTitle: NSLocalizedString(@"Share configuration"           , @"Button") ofControl: shareButton];
            [shareButton setEnabled: NO];
        }
    } else {
        [shareButton setEnabled: NO];
    }
    
    // Set up the 'Set nameserver' popup button with localized values
    [modifyNameserverPopUpButtonArrayController setContent: [connection modifyNameserverOptionList]];
    
    // If the width of the 'Set nameserver' popup button changes, shift the 'Monitor connection' checkbox left or right as needed
    NSRect oldRect = [modifyNameserverPopUpButton frame];
    [modifyNameserverPopUpButton sizeToFit];
    NSRect newRect = [modifyNameserverPopUpButton frame];
    float widthChange = newRect.size.width - oldRect.size.width;
    NSRect oldPos = [monitorConnnectionCheckbox frame];
    oldPos.origin.x = oldPos.origin.x + widthChange;
    [monitorConnnectionCheckbox setFrame:oldPos];
    
	NSString *useDNSKey = [displayName stringByAppendingString:@"useDNS"];
    int index = [connection useDNSStatus];

    // ***** Duplicate the effect of [self setSelectedModifyNameserverIndex: index] but without calling ourselves
    if (  index != selectedModifyNameserverIndex  ) {
        selectedModifyNameserverIndex = index;
        [modifyNameserverPopUpButton selectItemAtIndex: index];
        [self saveUseNameserverPopupButtonState: (unsigned) index];
        //[self validateDetailsWindowControls]; DO NOT DO THIS -- recurses infinitely. That is why we do this duplicate code instead of invoking setSelectedModifyNameserverIndex:
    }
    // ***** End duplication of the effect of [self setSelectedModifyNameserverIndex: index] but without calling ourselves
    
    [modifyNameserverPopUpButton setNeedsDisplay]; // Workaround for bug in OS X 10.4.11 ("Tiger") that causes misdraws
    [monitorConnnectionCheckbox  setNeedsDisplay];
    
    if (  [gTbDefaults canChangeValueForKey: useDNSKey]  ) {
        [modifyNameserverPopUpButton setEnabled: YES];
    } else {
        [modifyNameserverPopUpButton setEnabled: NO];
	}
	
	NSString *notMonitorConnectionKey = [displayName stringByAppendingString:@"-notMonitoringConnection"];
    if (   [gTbDefaults canChangeValueForKey: notMonitorConnectionKey]
        && ([connection useDNSStatus] == 1)  ) {
        [monitorConnnectionCheckbox setEnabled: YES];
    } else {
        [monitorConnnectionCheckbox setEnabled: NO];
	}
    
	if(   ( ! [gTbDefaults boolForKey:notMonitorConnectionKey] )
       && ( [connection useDNSStatus] == 1 )  ) {
		[monitorConnnectionCheckbox setState:NSOnState];
	} else {
		[monitorConnnectionCheckbox setState:NSOffState];
	}
    
    NSString *autoConnectKey = [displayName stringByAppendingString:@"autoConnect"];
    if (  [gTbDefaults canChangeValueForKey: autoConnectKey]  ) {
        [autoConnectCheckbox setEnabled: YES];
    } else {
        [autoConnectCheckbox setEnabled: NO];
    }
	if (  [gTbDefaults boolForKey: autoConnectKey]  ) {
		[autoConnectCheckbox setState:NSOnState];
	} else {
		[autoConnectCheckbox setState:NSOffState];
	}
	
    [self validateWhenConnectingForConnection: connection];     // May disable other controls if 'when computer connects' is selected
}
-(void)updateNavigationLabels
{
    if (  logWindowIsUsingTabs  ) {
        NSArray *keyArray = [[myVPNConnectionDictionary allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
        NSArray *myConnectionArray = [myVPNConnectionDictionary objectsForKeys:keyArray notFoundMarker:[NSNull null]];
        NSEnumerator *connectionEnumerator = [myConnectionArray objectEnumerator];
        VPNConnection *connection;
        int i = 0;
        while(connection = [connectionEnumerator nextObject]) {
            NSString * label = [self timeLabelForConnection: connection];
            [[tabView tabViewItemAtIndex:i] setLabel: label];
            i++;
        }
    } else {
        NSString * dispName = [leftNavDisplayNames objectAtIndex: selectedLeftNavListIndex];
        VPNConnection  * connection = [myVPNConnectionDictionary objectForKey: dispName];
        NSString * label = [self timeLabelForConnection: connection];
        [[tabView tabViewItemAtIndex:0] setLabel: label];
	}
}

-(NSString *) timeLabelForConnection: (VPNConnection *) connection
{ 
    NSString * cState = [connection state];
    NSString * cTimeS = @"";
    
    // Get connection duration if preferences say to 
    if (   [gTbDefaults boolForKey:@"showConnectedDurations"]
        && [cState isEqualToString: @"CONNECTED"]    ) {
        NSDate * csd = [connection connectedSinceDate];
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
    return [NSString stringWithFormat:@"%@ (%@%@)",[connection displayName], NSLocalizedString(cState, nil), cTimeS];
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
    if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
        [statusItem setToolTip: myState];
	}
    
	if (   (![lastState isEqualToString:@"EXITING"])
        && (![lastState isEqualToString:@"CONNECTED"]) ) { 
		// override while in transitional state
		// Any other state shows "transitional" image:
		//[statusItem setImage: transitionalImage];
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
            [statusItem setImage: connectedImage];
        } else {
            [statusItem setImage: mainImage];
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
        [statusItem performSelectorOnMainThread:@selector(setImage:) withObject:[animImages objectAtIndex:lround(progress * [animImages count]) - 1] waitUntilDone:YES];
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
    [logView setEditable: NO];
    [[logView layoutManager] replaceTextStorage: [newConnection logStorage]];
    //[logView setSelectedRange: NSMakeRange([[logView textStorage] length],[[logView textStorage] length])];
	[logView scrollRangeToVisible: NSMakeRange([[logView string] length]-1, 0)];
	
    [[logView textStorage] setDelegate: self];
    
    [self setLogWindowTitle];

    [self validateDetailsWindowControls];
}

- (void) setLogWindowTitle
{
    NSString * locationMessage = @"";
    if (  [gConfigDirs count] > 1  ) {
        NSString * path = [[self selectedConnection] configPath];
        if (  [path hasPrefix: gDeployPath]) {
            locationMessage =  NSLocalizedString(@" (Deployed)", @"Window title");
        } else if (  [path hasPrefix: gSharedPath]) {
            locationMessage =  NSLocalizedString(@" (Shared)", @"Window title");
        } else {
            locationMessage =  NSLocalizedString(@" (Private)", @"Window title");
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
    [self performSelectorOnMainThread: @selector(doLogScrolling:) withObject: [aNotification object] waitUntilDone: NO];
}

-(void) doLogScrolling: (NSTextView *) textView
{
    [textView scrollRangeToVisible: NSMakeRange([[textView string] length]-1, 0)];
}

- (NSTextView*) selectedLogView
{
    NSTextView* result = [[[[[tabView selectedTabViewItem] view] subviews] lastObject] documentView];
    return result;
}

- (IBAction) clearLogButtonWasClicked: (id) sender
{
    [[self selectedConnection] clearLog];
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
    NSString* dispNm;
    if (  logWindowIsUsingTabs  ) {
        if (![tabView selectedTabViewItem]) {
            [tabView selectFirstTabViewItem: nil];
        }
        dispNm = [[tabView selectedTabViewItem] identifier];
    } else {
        dispNm = [leftNavDisplayNames objectAtIndex: selectedLeftNavListIndex];
    }
    
    VPNConnection* connection = [myVPNConnectionDictionary objectForKey: dispNm];
    NSArray *allConnections = [myVPNConnectionDictionary allValues];
    if(connection) return connection;
    else if([allConnections count]) return [allConnections objectAtIndex:0] ; 
    else return nil;
}

- (IBAction)connectButtonWasClicked:(id)sender
{
    [[self selectedConnection] connect: sender]; 
}

- (IBAction)disconnectButtonWasClicked:(id)sender
{
    [[self selectedConnection] disconnectAndWait: [NSNumber numberWithBool: YES]];      
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
                                                           NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
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
    NSArray * allConfigsSorted = [[myVPNConnectionDictionary allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
	NSEnumerator* e = [allConfigsSorted objectEnumerator];
	NSTabViewItem* initialItem;
	VPNConnection* connection = [myVPNConnectionDictionary objectForKey: [e nextObject]];
    if (  ! connection  ) {
        NSLog(@"Internal program error: openLogWindow: but there are no configurations");
        return;
    }
    
    [NSBundle loadNibNamed: @"LogWindow" owner: self]; // also sets tabView etc.
    
    int maxNumberOfTabs;
    id obj = [gTbDefaults objectForKey: @"maximumNumberOfTabs"];
    if (  obj  ) {
        maxNumberOfTabs = [obj intValue];
    } else {
        maxNumberOfTabs = 8;
    }
    
    logWindowIsUsingTabs = (  [myVPNConnectionDictionary count] <= maxNumberOfTabs  );
    
    // Set the window's size and position from preferences (saved when window is closed)
    // But only if the preference's version matches the TB version (since window size could be different in different versions of TB)
    NSString * tbVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    if (  [tbVersion isEqualToString: [gTbDefaults objectForKey:@"detailsWindowFrameVersion"]]    ) {
        NSString * frameString = [gTbDefaults objectForKey: @"detailsWindowFrame"];
        if (  frameString != nil  ) {
            [logWindow setFrameFromString:frameString];
        }
        frameString = [gTbDefaults objectForKey: @"detailsWindowLeftFrame"];
        if (  frameString != nil  ) {
            NSRect frame;
            frame = NSRectFromString(frameString);
            if (  frame.size.width < LEFT_NAV_AREA_MINIMUM_SIZE  ) {
                frame.size.width = LEFT_NAV_AREA_MINIMUM_SIZE;
            }
            [leftSplitView setFrame: frame];
        }
    }
    
    initialItem = [tabView tabViewItemAtIndex: 0];
    NSString * dispNm = [connection displayName];
    [initialItem setIdentifier: dispNm];
    [initialItem setLabel:      dispNm];
    
    int leftNavIndexToSelect = 0;
    
    if (  logWindowIsUsingTabs  ) {
        // Make the left navigation area very small
        NSRect frameRect = [leftSplitView frame];
        frameRect.size.width = LEFT_NAV_AREA_MINIMAL_SIZE;
        [leftSplitView setFrame: frameRect];
        [leftSplitView display];
        
        int curTabIndex = 0;
        [tabView selectTabViewItemAtIndex:0];
        BOOL haveSelectedAConnection = ! [connection isDisconnected];
        while (connection = [myVPNConnectionDictionary objectForKey: [e nextObject]]) {
            NSTabViewItem* newItem = [[NSTabViewItem alloc] init];
            dispNm = [connection displayName];
            [newItem setIdentifier: dispNm];
            [newItem setLabel:      dispNm];
            [tabView addTabViewItem: newItem];
            [newItem release];
            ++curTabIndex;
            if (  oldSelectedConnectionName  ) {
                if (  [dispNm isEqualToString: oldSelectedConnectionName]  ) {
                    [tabView selectTabViewItemAtIndex:curTabIndex];
                    haveSelectedAConnection = YES;
                    oldSelectedConnectionName = nil;
                }
            } else if (   ( ! haveSelectedAConnection )
                       && ( ! [connection isDisconnected] )  ) {
                [tabView selectTabViewItemAtIndex:curTabIndex];
                haveSelectedAConnection = YES;
            }
        }
    } else {
        [leftNavList         release];
        [leftNavDisplayNames release];
        leftNavList         = [[NSMutableArray alloc] initWithCapacity: [myVPNConnectionDictionary count]];
        leftNavDisplayNames = [[NSMutableArray alloc] initWithCapacity: [myVPNConnectionDictionary count]];
        int curTabIndex = 0;
        BOOL haveSelectedAConnection = ! [connection isDisconnected];
        NSMutableArray * currentFolders = [NSMutableArray array]; // Components of folder enclosing most-recent leftNavList/leftNavDisplayNames entry
        NSEnumerator* configEnum = [allConfigsSorted objectEnumerator];
        while (connection = [myVPNConnectionDictionary objectForKey: [configEnum nextObject]]) {
            dispNm = [connection displayName];
            NSArray * currentConfig = [dispNm componentsSeparatedByString: @"/"];
            int firstDiff = [self firstDifferentComponent: currentConfig and: currentFolders];

            // Track any necessary "outdenting"
            if (  firstDiff < [currentFolders count]  ) {
                // Remove components from the end of currentFolders until we have a match
                int i;
                for (  i=0; i < ([currentFolders count]-firstDiff); i++  ) {
                    [currentFolders removeLastObject];
                }
            }

            // currentFolders and currentConfig now match, up to but not including the firstDiff-th entry

            // Add a "folder" line for each folder in currentConfig starting with the first-Diff-th entry (if any)
            int i;
            for (  i=firstDiff; i < [currentConfig count]-1; i++  ) {
                [leftNavDisplayNames addObject: @""];
                NSString * folderName = [currentConfig objectAtIndex: i];
                [leftNavList         addObject: [NSString stringWithString: 
                                                 [self indent: folderName by: firstDiff+i]]];
                [currentFolders addObject: folderName];
                ++curTabIndex;
            }
            
            // Add a "configuration" line
            [leftNavDisplayNames addObject: [NSString stringWithString: [connection displayName]]];
            [leftNavList         addObject: [NSString stringWithString: 
                                             [self indent: [currentConfig lastObject] by: [currentConfig count]-1]]];
            
            if (  oldSelectedConnectionName  ) {
                if (  [dispNm isEqualToString: oldSelectedConnectionName]  ) {
                    [self setSelectedLeftNavListIndex: curTabIndex];
                    haveSelectedAConnection = YES;
                    oldSelectedConnectionName = nil;
                }
            } else if (   ( ! haveSelectedAConnection )
                       && ( ! [connection isDisconnected] )  ) {
                leftNavIndexToSelect = curTabIndex;
                haveSelectedAConnection = YES;
            }
            ++curTabIndex;
        }
    }
    
	[logWindow setDelegate:self];
    
	[self setLogWindowTitle];
    
	// Localize buttons and checkboxes, shifting their neighbors left or right as needed
    // NOTE: We don't localize the contents of modifyNameserverPopUpButton because they are localized when they are inserted into it by
    //       validateDetailsWindowControls, which also does any necessary shifting of its neighbor, the 'Monitor connection' checkbox.
    
    [self setTitle: NSLocalizedString(@"Clear log"                  , @"Button")        ofControl: clearButton                ];
    [self setTitle: NSLocalizedString(@"Edit configuration"         , @"Button")        ofControl: editButton                 ];
    [self setTitle: NSLocalizedString(@"Share configuration"        , @"Button")        ofControl: shareButton                ];
    [self setTitle: NSLocalizedString(@"Connect"                    , @"Button")        ofControl: connectButton              ];
    [self setTitle: NSLocalizedString(@"Disconnect"                 , @"Button")        ofControl: disconnectButton           ];
    [self setTitle: NSLocalizedString(@"Monitor connection"         , @"Checkbox name") ofControl: monitorConnnectionCheckbox ];
    [self setTitle: NSLocalizedString(@"Automatically connect"      , @"Checkbox name") ofControl: autoConnectCheckbox        ];
    [self setTitle: NSLocalizedString(@"when Tunnelblick launches"  , @"Checkbox name") ofControl: onLaunchRadioButton        ];
    [self setTitle: NSLocalizedString(@"when computer starts"       , @"Checkbox name") ofControl: onSystemStartRadioButton   ];
    
	VPNConnection * myConnection = [self selectedConnection];
	NSTextStorage * store = [myConnection logStorage];
    
    [[[self selectedLogView] layoutManager] replaceTextStorage: store];
	
    if (  logWindowIsUsingTabs  ) {
        [self tabView:tabView didSelectTabViewItem:initialItem];
    } else {
        [leftNavListView reloadData];
        selectedLeftNavListIndex = -1;  // Force a change
        [self setSelectedLeftNavListIndex: leftNavIndexToSelect];
        [leftNavListView scrollRowToVisible: leftNavIndexToSelect];
    }

    [self updateNavigationLabels];
    
    // Set up a timer to update the tab labels with connections' duration times
    [self startOrStopDurationsTimer];
	
    [logWindow display];
    [logWindow makeKeyAndOrderFront: self];
    [NSApp activateIgnoringOtherApps:YES];
    logWindowIsOpen = TRUE;
}

-(int) firstDifferentComponent: (NSArray *) a and: (NSArray *) b
{
    int retVal = 0;
    int i;
    for (i=0;
            (i < [a count]) 
         && (i < [b count])
         && [[a objectAtIndex: i] isEqual: [b objectAtIndex: i]];
         i++  ) {
        ++retVal;
    }

    return retVal;
}

-(NSString *) indent: (NSString *) s by: (int) n
{
    NSString * retVal = [NSString stringWithFormat:@"%*s%@", 3*n, "", s];
    return retVal;
}

-(int)numberOfRowsInTableView:(NSTableView *)aTableView
{
    if (  aTableView == leftNavListView  ) {
        int n = [leftNavList count];
        return n;
    }
    
    return 0;
}

-(id) tableView:(NSTableView *) aTableView objectValueForTableColumn:(NSTableColumn *) aTableColumn row:(int) rowIndex
{
    if (  aTableView == leftNavListView  ) {
        NSString * s = [leftNavList objectAtIndex: rowIndex];
        return s;
    }
    
    return nil;
}

// Sets the title for a control, shifting the origin of the control itself to the left, and the origin of other controls to the left or right to accomodate any change in width.
-(void) setTitle: (NSString *) newTitle ofControl: (id) theControl
{
    NSRect oldRect = [theControl frame];
	
    if (   [theControl isEqual: onLaunchRadioButton]
        || [theControl isEqual: onSystemStartRadioButton]  ) {
        id cell = [theControl cellAtRow: 0 column: 0];
        [cell setTitle: newTitle];
    } else {
        [theControl setTitle: newTitle];
    }
    [theControl sizeToFit];
    
    NSRect newRect = [theControl frame];
    float widthChange = newRect.size.width - oldRect.size.width;
    NSRect oldPos;
    
    if (   [theControl isEqual: connectButton]                      // Shift the control itself left/right if necessary
        || [theControl isEqual: disconnectButton]  ) {
        oldPos = [theControl frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [theControl setFrame:oldPos];
    }

    if (  [theControl isEqual: clearButton]  )  {                   // If the Clear log button changes, shift the Edit and Share buttons right/left
        oldPos = [editButton frame];
        oldPos.origin.x = oldPos.origin.x + widthChange;
        [editButton setFrame:oldPos];
        oldPos = [shareButton frame];
        oldPos.origin.x = oldPos.origin.x + widthChange;
        [shareButton setFrame:oldPos];
    } else if (  [theControl isEqual: editButton]  )  {             // If the Edit button changes, shift the Share button right/left
        oldPos = [shareButton frame];
        oldPos.origin.x = oldPos.origin.x + widthChange;
        [shareButton setFrame:oldPos];
    } else if (  [theControl isEqual: connectButton]  )  {          // If the Connect button changes, shift the Disconnect button left/right
        oldPos = [disconnectButton frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [disconnectButton setFrame:oldPos];
    } else if (  [theControl isEqual: autoConnectCheckbox]  ) {     // If the Auto Connect checkbox changes, shift the On Launch and On Computer Startup buttons left/right
        oldPos = [onLaunchRadioButton frame];
        oldPos.origin.x = oldPos.origin.x + widthChange;
        [onLaunchRadioButton setFrame:oldPos];
        oldPos = [onSystemStartRadioButton frame];
        oldPos.origin.x = oldPos.origin.x + widthChange;
        [onSystemStartRadioButton setFrame:oldPos];
    } else if (  [theControl isEqual: onLaunchRadioButton]  ) {     // If the On Launch checkbox changes, shift the On Computer Startup button left/right
        oldPos = [onSystemStartRadioButton frame];
        oldPos.origin.x = oldPos.origin.x + widthChange;
        [onSystemStartRadioButton setFrame:oldPos];
    } else if (  [theControl isEqual: onLaunchRadioButton]  ) {     // If the On Launch radio button changes, shift the On System Startup button left/right
        oldPos = [onSystemStartRadioButton frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [onSystemStartRadioButton setFrame:oldPos];
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
        NSString * mainFrame = [logWindow stringWithSavedFrame];
        NSString * leftFrame = nil;
        if (  [leftSplitView frame].size.width > (LEFT_NAV_AREA_MINIMAL_SIZE + 5.0)  ) {
            leftFrame = NSStringFromRect([leftSplitView frame]);
        }
        NSString * tbVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
        BOOL saveIt = TRUE;
        if (  [tbVersion isEqualToString: [gTbDefaults objectForKey:@"detailsWindowFrameVersion"]]    ) {
            if (   [mainFrame isEqualToString: [gTbDefaults objectForKey:@"detailsWindowFrame"]]
                && [leftFrame isEqualToString: [gTbDefaults objectForKey:@"detailsWindowLeftFrame"]]  ) {
                saveIt = FALSE;
            }
        }
        
        if (saveIt) {
            [gTbDefaults setObject: mainFrame forKey: @"detailsWindowFrame"];
            if (  leftFrame  ) {
                [gTbDefaults setObject: leftFrame forKey: @"detailsWindowLeftFrame"];
            }
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

// If possible, we try to use 'killall' to kill all processes named 'openvpn'
// But if there are unknown open processes that the user wants running, or we have active daemon processes,
//     then we must use 'kill' to kill each individual process that should be killed
-(void) killAllConnectionsIncludingDaemons: (BOOL) includeDaemons
{
    NSEnumerator * connEnum = [myVPNConnectionDictionary objectEnumerator];
    VPNConnection * connection;
    BOOL noActiveDaemons = YES;
    
    if (  ! includeDaemons  ) {
        // See if any of our daemons are active -- i.e., have a process ID (they may be in the process of connecting or disconnecting)
        while (  connection = [connEnum nextObject]  ) {
            NSString* onSystemStartKey = [[connection displayName] stringByAppendingString: @"-onSystemStart"];
            NSString* autoConnectKey = [[connection displayName] stringByAppendingString: @"autoConnect"];
            if (   [gTbDefaults boolForKey: onSystemStartKey]
                && [gTbDefaults boolForKey: autoConnectKey]  ) {
                if (  [connection pid] != 0  ) {
                    noActiveDaemons = NO;
                    break;
                }
            }
        }
    }
    
    if (   includeDaemons
        || ( noUnknownOpenVPNsRunning && noActiveDaemons )  ) {
        
        // Killing everything, so we use 'killall' to kill all processes named 'openvpn'
        NSString* path = [[NSBundle mainBundle] pathForResource: @"openvpnstart" ofType: nil];
        NSTask* task = [[[NSTask alloc] init] autorelease];
        [task setLaunchPath: path];
        [task setArguments: [NSArray arrayWithObject: @"killall"]];
        [task launch];
        [task waitUntilExit];
    } else {
        
        // Killing selected processes only -- those we know about that are not daemons
        while (  connection = [connEnum nextObject]  ) {
            if (  ! [connection isDisconnected]  ) {
                NSString* onSystemStartKey = [[connection displayName] stringByAppendingString: @"-onSystemStart"];
                NSString* autoConnectKey = [[connection displayName] stringByAppendingString: @"autoConnect"];
                if (   ( ! [gTbDefaults boolForKey: onSystemStartKey]  )
                    || ( ! [gTbDefaults boolForKey: autoConnectKey]    )  ) {
                    pid_t procId = [connection pid];
                    if (  procId > 0  ) {
                        NSString* path = [[NSBundle mainBundle] pathForResource: @"openvpnstart" ofType: nil];
                        NSTask* task = [[[NSTask alloc] init] autorelease];
                        [task setLaunchPath: path];
                        [task setArguments: [NSArray arrayWithObjects: @"kill", [NSString stringWithFormat: @"%d", procId], nil]];
                        [task launch];
                        [task waitUntilExit];
                    } else {
                        [connection disconnectAndWait: [NSNumber numberWithBool: NO]];
                    }
                }
            }
        }
    }
}    
    
// Unloads loaded tun/tap kexts if tunCount/tapCount is zero.
// If fooOnly is TRUE, only the foo tun/tap kexts will be unloaded (if they are loaded, and without reference to the tunCount/tapCount)
-(void) unloadKextsFooOnly: (BOOL) fooOnly 
{
    int bitMask = [self getLoadedKextsMask];
    
    if (  fooOnly  ) {
        bitMask = bitMask & (FOO_TAP_KEXT | FOO_TUN_KEXT);
    }
    if (  bitMask != 0  ) {
        
        if (   (bitMask & FOO_TAP_KEXT)
            || (bitMask & FOO_TUN_KEXT)  ) {
            int result = TBRunAlertPanelExtended(NSLocalizedString(@"Remove kexts?", @"Window title"),
                                                 NSLocalizedString(@"One or both of the 'foo.tap' and 'foo.tun' system driver files (yes, those really are their names!) are loaded. They were used by older versions of Tunnelblick, and will interfere with Tunnelblick's operation.\n\nDo you wish to remove the foo.tap and/or foo.tun kexts?", @"Window text"),
                                                 NSLocalizedString(@"Ignore", @"Button"),
                                                 NSLocalizedString(@"Remove", @"Button"),
                                                 nil,
                                                 @"skipAskingToUnloadFooKexts",
                                                 NSLocalizedString(@"Do not ask again, always 'Ignore'", @"Checkbox name"),
                                                 nil);
            if (  result == NSAlertDefaultReturn  ) {
                bitMask = bitMask & (  ~(FOO_TAP_KEXT | FOO_TUN_KEXT)  );
            }
        }
        
        if (  tapCount != 0  ) {
            bitMask = bitMask & ( ~OUR_TAP_KEXT);
        }
        
        if (  tunCount != 0  ) {
            bitMask = bitMask & ( ~OUR_TUN_KEXT);
        }
        
        if (  bitMask != 0  ) {
            NSString * arg1 = [NSString stringWithFormat: @"%d", bitMask];
            NSString* path = [[NSBundle mainBundle] pathForResource: @"openvpnstart" 
                                                             ofType: nil];
            NSTask* task = [[NSTask alloc] init];
            [task setLaunchPath: path]; 
            
            NSArray *arguments = [NSArray arrayWithObjects:@"unloadKexts", arg1, nil];
            [task setArguments:arguments];
            [task launch];
            [task waitUntilExit];
            [task release];
        }
    }
}

// Returns with a bitmask of kexts that are loaded that can be unloaded
// Launches "kextstat" to get the list of loaded kexts, and does a simple search
-(int) getLoadedKextsMask
{
    NSString * exePath = @"/usr/sbin/kextstat";

    NSTask * task = [[NSTask alloc] init];
    [task setLaunchPath: exePath];

    NSArray  *arguments = [NSArray array];
    [task setArguments: arguments];
    
    NSPipe * pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    
    NSFileHandle * file = [pipe fileHandleForReading];
    
    [task launch];
    
    NSData * data = [file readDataToEndOfFile];
    
    [task release];
    
    NSString * string = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    
    int bitMask = 0;

    if (  [string rangeOfString: @"foo.tap"].length != 0  ) {
        bitMask = bitMask | FOO_TAP_KEXT;
    }
    if (  [string rangeOfString: @"foo.tun"].length != 0  ) {
        bitMask = bitMask | FOO_TUN_KEXT;
    }
    if (  [string rangeOfString: @"net.tunnelblick.tap"].length != 0  ) {
        bitMask = bitMask | OUR_TAP_KEXT;
    }
    if (  [string rangeOfString: @"net.tunnelblick.tun"].length != 0  ) {
        bitMask = bitMask | OUR_TUN_KEXT;
    }
    
    [string release];
    
    return bitMask;
}

-(void) resetActiveConnections {
	VPNConnection *connection;
	NSEnumerator* e = [connectionArray objectEnumerator];
	while (connection = [e nextObject]) {
		if ([[connection connectedSinceDate] timeIntervalSinceNow] < -5) {
			if (NSDebugEnabled) NSLog(@"Resetting connection: %@",[connection displayName]);
			[connection disconnectAndWait: [NSNumber numberWithBool: YES]];
			[connection connect:self];
		} else {
			if (NSDebugEnabled) NSLog(@"Not Resetting connection: %@, waiting...",[connection displayName]);
		}
	}
}

// If there aren't ANY config files in the config folders 
// then guide the user
-(void) checkNoConfigurations
{
    if (  ignoreNoConfigs || [myConfigDictionary count] != 0  ) {
        return;
    }
    
    // If this is a Deployed version with no configurations, quit Tunnelblick
    if (   [gConfigDirs count] == 1
        && [[gConfigDirs objectAtIndex:0] isEqualToString: gDeployPath]  ) {
        TBRunAlertPanel(NSLocalizedString(@"All configuration files removed", @"Window title"),
                        [NSString stringWithFormat: NSLocalizedString(@"All configuration files in %@ have been removed. Tunnelblick must quit.", @"Window text"),
                         [[gFileMgr componentsToDisplayForPath: gDeployPath] componentsJoinedByString: @"/"]],
                        nil, nil, nil);
        [NSApp setAutoLaunchOnLogin: NO];
        [NSApp terminate: nil];
    }
    
    [[ConfigurationManager defaultManager] haveNoConfigurationsGuide];
}

-(IBAction) addConfigurationWasClicked: (id) sender
{
    [[ConfigurationManager defaultManager] addConfigurationGuide];
}

-(IBAction) editConfigButtonWasClicked: (id) sender
{
    VPNConnection * connection = [self selectedConnection];
	[[ConfigurationManager defaultManager] editConfigurationAtPath: [connection configPath] forConnection: connection];
}

-(IBAction) shareConfigButtonWasClicked: (id) sender
{
    NSString * disableShareConfigKey = [[[self selectedConnection] displayName] stringByAppendingString:@"disableShareConfigurationButton"];
    if (  ! [gTbDefaults boolForKey: disableShareConfigKey]  ) {
        NSString * path = [[self selectedConnection] configPath];
        if (  [[path pathExtension] isEqualToString: @"tblk"]  ) {
            int result;
            if (  [path hasPrefix: gSharedPath]  ) {
                result = TBRunAlertPanel(NSLocalizedString(@"Make Configuration Private?", @"Window title"),
                                             NSLocalizedString(@"This configuration is shared with all other users of this computer.\n\nDo you wish to make it private, so that only you can use it?", @"Window title"),
                                         NSLocalizedString(@"Make configuration private", @"Button"),   // Default button
                                         NSLocalizedString(@"Cancel", @"Button"),                       // Alternate button
                                             nil);
                
            } else if (  [path hasPrefix: gPrivatePath]  ) {
                result = TBRunAlertPanel(NSLocalizedString(@"Share Configuration?", @"Window title"),
                                         NSLocalizedString(@"This configuration is private -- only you can use it.\n\nDo you wish to make it shared, so that all other users of this computer can use it?", @"Window title"),
                                         NSLocalizedString(@"Share configuration", @"Button"),  // Default button
                                         NSLocalizedString(@"Cancel", @"Button"),               // Alternate button
                                         nil);
            } else {
                // Deployed, so can't share or make private
                return;
            }
            
            if (  result == NSAlertDefaultReturn  ) {
                oldSelectedConnectionName = [[self selectedConnection] displayName];
                [[ConfigurationManager defaultManager] shareOrPrivatizeAtPath: path];
            }
        }
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
    if (  hotKeyEventHandlerIsInstalled && hotKeyModifierKeys != 0  ) {
        UnregisterEventHotKey(hotKeyRef);
    }
    
	[NSApp callDelegateOnNetworkChange: NO];
    [self killAllConnectionsIncludingDaemons: NO];  // Kill any of our OpenVPN processes that still exist unless they're "on computer start" configurations
    [self unloadKextsFooOnly: NO];     // Unload .tun and .tap kexts
	if (  statusItem  ) {
        [[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
    }
}


-(void)saveMonitorConnectionCheckboxState:(BOOL)inBool
{
	VPNConnection* connection = [self selectedConnection];
	if(connection != nil) {
		NSString* key = [[connection displayName] stringByAppendingString: @"-notMonitoringConnection"];
        if (  [gTbDefaults boolForKey: key] != (! inBool)  ) {
            [gTbDefaults setObject: [NSNumber numberWithBool: ! inBool] forKey: key];
            [gTbDefaults synchronize];
            if (  ! [connection isDisconnected]  ) {
                TBRunAlertPanel(NSLocalizedString(@"Configuration Change", @"Window title"),
                                NSLocalizedString(@"The change will take effect the next time you connect.", @"Window text"),
                                nil, nil, nil);
            }
        }
    }
}

-(void)saveUseNameserverPopupButtonState:(unsigned)inValue
{
	VPNConnection* connection = [self selectedConnection];
	if(connection != nil) {
		NSString* key = [[connection displayName] stringByAppendingString: @"useDNS"];
        NSNumber * num = [NSNumber numberWithInt: (int) inValue];
        id obj = [gTbDefaults objectForKey: key];
        if (   ( ! [[obj class] isSubclassOfClass: [num class]] )
            || ( ! [num isEqualToNumber: obj] )  ) {
            [gTbDefaults setObject: num forKey: key];
            [gTbDefaults synchronize];
            if (  ! [connection isDisconnected]  ) {
                TBRunAlertPanel(NSLocalizedString(@"Configuration Change", @"Window title"),
                                NSLocalizedString(@"The change will take effect the next time you connect.", @"Window text"),
                                nil, nil, nil);
            }
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

-(void)saveOnSystemStartRadioButtonState: (BOOL) onSystemStart
                           forConnection: (VPNConnection *) connection
{
	if(connection != nil) {
        NSString * name = [connection displayName];
        BOOL coss = [connection checkConnectOnSystemStart: onSystemStart withAuth: myAuth];
		NSString* systemStartkey = [name stringByAppendingString: @"-onSystemStart"];
        if (  [gTbDefaults boolForKey: systemStartkey] != coss  ) {
            [gTbDefaults setBool: coss forKey: systemStartkey];
            [gTbDefaults synchronize];
        }
        
        NSString * autoConnectKey = [name stringByAppendingString: @"autoConnect"];
        BOOL col = ( ! coss ) && [gTbDefaults boolForKey: autoConnectKey];
        
        [[onLaunchRadioButton      cellAtRow: 0 column: 0]  setState: (int) col];
        [[onSystemStartRadioButton cellAtRow: 0 column: 0]  setState: (int) coss];
	}
}
- (void) setState: (NSString*) newState
// Be sure to call this in main thread only
{
    [newState retain];
    [lastState release];
    lastState = newState;
	[self performSelectorOnMainThread:@selector(updateUI) withObject:nil waitUntilDone:NO];
}

-(void)addConnection:(id)sender 
{
	if (  sender != nil  ) {
		[connectionArray removeObject:sender];
		[connectionArray addObject:sender];
        [self startOrStopDurationsTimer];
	}
}

-(void)removeConnection:(id)sender
{
	if (  sender != nil  ) {
        [connectionArray removeObject:sender];
        [self startOrStopDurationsTimer];
    }
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
        NSLog(@"Warning: setting signal handler failed: '%s'", strerror(errno));
    }	
}

// Invoked when the user double-clicks on one or more .tblk packages,
//                  or drags and drops one or more .tblk package(s) onto Tunnelblick
- (BOOL)application: (NSApplication * )theApplication openFiles: (NSArray * )filePaths
{
    // If we have finished launching Tunnelblick, we open the file(s) now
    // otherwise the file(s) opening launched us, but we have not initialized completely.
    // so we store the paths and open the file(s) later, in applicationDidFinishLaunching.
    if (  launchFinished  ) {
        [[ConfigurationManager defaultManager] openDotTblkPackages: filePaths usingAuth: myAuth];
    } else {
        if (  ! dotTblkFileList  ) {
            dotTblkFileList = [NSMutableArray arrayWithArray: filePaths];
        } else {
            [dotTblkFileList addObjectsFromArray: filePaths];
        }
    }
    
    return TRUE;
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
    
    if (  dotTblkFileList  ) {
        [[ConfigurationManager defaultManager] openDotTblkPackages: dotTblkFileList usingAuth: myAuth];
    }
    
    // Set up to monitor configuration folders
    myQueue = [UKKQueue sharedFileWatcher];
    if (  ! [gTbDefaults boolForKey:@"doNotMonitorConfigurationFolder"]  ) {
        int i;
        for (i = 0; i < [gConfigDirs count]; i++) {
            [self addPath: [gConfigDirs objectAtIndex: i] toMonitorQueue: myQueue];
        }
    }
    [myQueue setDelegate: self];
    [myQueue setAlwaysNotify: YES];
    
    [self activateStatusMenu];
    
    ignoreNoConfigs = NO;    // We should NOT ignore the "no configurations" situation
    
    [self checkNoConfigurations];

    // Make sure the '-onSystemStart' preferences for all connections are consistent with the /Library/LaunchDaemons/...plist file for the connection
    NSEnumerator * connEnum = [myVPNConnectionDictionary objectEnumerator];
    VPNConnection * connection;
    while (  connection = [connEnum nextObject]  ) {
        [self validateWhenConnectingForConnection: connection];
    }
    
    [self hookupToRunningOpenVPNs];
    
    AuthorizationFree(myAuth, kAuthorizationFlagDefaults);
    myAuth = nil;
    
    [self unloadKextsFooOnly: YES];
    
    // Process runOnLaunch item
    if (  customRunOnLaunchPath  ) {
        NSTask* task = [[[NSTask alloc] init] autorelease];
        [task setLaunchPath: customRunOnLaunchPath];
        [task setArguments: [NSArray array]];
        [task setCurrentDirectoryPath: [customRunOnLaunchPath stringByDeletingLastPathComponent]];
        [task launch];
        if (  [[[customRunOnLaunchPath stringByDeletingPathExtension] pathExtension] isEqualToString: @"wait"]) {
            [task waitUntilExit];
            int status = [task terminationStatus];
            if (  status != 0  ) {
                NSLog(@"Tunnelblick runOnLaunch item %@ returned %d; Tunnelblick launch cancelled", customRunOnLaunchPath, status);
                [NSApp terminate:self];
            }
        }
    }
    
    // Process "Automatically connect on launch" checkboxes
    VPNConnection * myConnection;
    NSString * dispNm;
    NSEnumerator * e = [myConfigDictionary keyEnumerator];
    while (dispNm = [e nextObject]) {
        myConnection = [myVPNConnectionDictionary objectForKey: dispNm];
        if (  [gTbDefaults boolForKey: [dispNm stringByAppendingString: @"autoConnect"]]  ) {
            if (  ! [gTbDefaults boolForKey: [dispNm stringByAppendingString: @"-onSystemStart"]]  ) {
                if (  ![myConnection isConnected]  ) {
                    [myConnection connect:self];
                }
            }
        }
    }
    
    gHookupTimeout = 5; // Default
    id hookupTimeout;
    if (  hookupTimeout = [gTbDefaults objectForKey: @"hookupTimeout"]  ) {
        if (   [[hookupTimeout class]  isSubclassOfClass: [NSNumber class]]
            || [[hookupTimeout class]  isSubclassOfClass: [NSString class]]) {
            gHookupTimeout = [hookupTimeout intValue];
        }
    }
    
    if (  gHookupTimeout  != 0) {
        hookupWatchdogTimer = [NSTimer scheduledTimerWithTimeInterval: (NSTimeInterval) gHookupTimeout
                                                               target: self
                                                             selector: @selector(hookupWatchdogHandler)
                                                             userInfo: nil
                                                              repeats: NO];
    }
    
    [NSApp setAutoLaunchOnLogin: YES];
    
    if (  hotKeyModifierKeys != 0  ) {
        [self setupHotKeyWithCode: hotKeyKeyCode andModifierKeys: hotKeyModifierKeys]; // Set up hotkey to reveal the Tunnelblick menu (since VoiceOver can't access the Tunnelblick in the System Status Bar)
    }

    launchFinished = TRUE;
}

-(void) addPath: (NSString *) path toMonitorQueue: (UKKQueue *) queue
{
    // Add the path itself
    [queue addPathToQueue: path];

    // Add folders and subfolders
    NSString * file;
    BOOL isDir;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: path];
    while (  file = [dirEnum nextObject]  ) {
        if (  ! [file hasSuffix: @".tblk"]  ) {
            NSString * subPath = [path stringByAppendingPathComponent: file];
            if (  [gFileMgr fileExistsAtPath: subPath isDirectory: &isDir]
                && isDir  ) {
                [queue addPathToQueue: subPath];
            }
        }
    }
}

-(void) removePath: (NSString *) path fromMonitorQueue: (UKKQueue *) queue
{
    // Remove the path itself
    [queue removePathFromQueue: path];
    
    // Remove folders and subfolders
    NSString * file;
    BOOL isDir;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: path];
    while (  file = [dirEnum nextObject]  ) {
        if (  ! [file hasSuffix: @".tblk"]  ) {
            NSString * subPath = [path stringByAppendingPathComponent: file];
            if (  [gFileMgr fileExistsAtPath: subPath isDirectory: &isDir]
                && isDir  ) {
                [queue removePathFromQueue: subPath];
            }
        }
    }
}

-(void) hookupWatchdogHandler
{
	[self performSelectorOnMainThread: @selector(hookupWatchdog) withObject: nil waitUntilDone: NO];
}

-(void) hookupWatchdog
{
    NSMutableArray * pids = [NSApp pIdsForOpenVPNProcesses];
    
    VPNConnection * connection;
    NSEnumerator * connEnum = [myVPNConnectionDictionary objectEnumerator];
    while (  connection = [connEnum nextObject]  ) {
        if (  [connection isHookedup]  ) {
            NSNumber * processId = [NSNumber numberWithInt: (int) [connection pid]];
            if (  processId != 0  ) {
                if (  [pids containsObject: processId]  ) {
                    [pids removeObject: processId];
                }
            }
        } else {
            if (  [connection tryingToHookup]  ) {
                [connection stopTryingToHookup];
            }
        }
    }
    
    if (  [pids count]  ) {
        int result = TBRunAlertPanelExtended(NSLocalizedString(@"Warning: Unknown OpenVPN processes", @"Window title"),
                                             NSLocalizedString(@"One or more OpenVPN processes are running but are unknown to Tunnelblick. If you are not running OpenVPN separately from Tunnelblick, this usually means that an earlier launch of Tunnelblick was unable to shut them down properly and you should terminate them. They are likely to interfere with Tunnelblick's operation. Do you wish to terminate them?", @"Window text"),
                                             NSLocalizedString(@"Ignore", @"Button"),
                                             NSLocalizedString(@"Terminate", @"Button"),
                                             nil,
                                             @"skipWarningAboutUnknownOpenVpnProcesses",
                                             NSLocalizedString(@"Do not ask again, always 'Ignore'", @"Checkbox name"),
                                             nil);
        if (  result == NSAlertAlternateReturn  ) {
            NSNumber * pidNumber;
            NSEnumerator * pidsEnum = [pids objectEnumerator];
            while (  pidNumber = [pidsEnum nextObject]  ) {
                
                NSString* path = [[NSBundle mainBundle] pathForResource: @"openvpnstart" ofType: nil];
                NSString *pidString = [NSString stringWithFormat:@"%d", [pidNumber intValue]];
                NSArray *arguments = [NSArray arrayWithObjects:@"kill", pidString, nil];
                
                NSTask* task = [[[NSTask alloc] init] autorelease];
                [task setLaunchPath: path]; 
                [task setArguments:arguments];
                [task setCurrentDirectoryPath: @"/tmp"];
                [task launch];
                [task waitUntilExit];
                noUnknownOpenVPNsRunning = YES;
            }
        }
    } else {
        noUnknownOpenVPNsRunning = YES;
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
        int nModifyNameserver  = 0;
        int nMonitorConnection = 0;
        int nPackages          = 0;
        
        NSString * key;
        NSString * path;
        
        // Count # of .tblk packages
        NSEnumerator * e = [myConfigDictionary objectEnumerator];
        while (  path = [e nextObject]  ) {
            NSString * last = lastPartOfPath(path);
            NSString * firstComponent = firstPathComponent(last);
            if (  [[firstComponent pathExtension] isEqualToString: @"tblk"]  ) {
                nPackages++;
            }
        }
        
        // Count # of configurations with 'Set nameserver' checked and the # with 'Monitor connection' set
        e = [myConfigDictionary keyEnumerator];
        while (  key = [e nextObject]  ) {
            NSString * dnsKey = [key stringByAppendingString:@"useDNS"];
            if (  [gTbDefaults objectForKey: dnsKey]  ) {
                if (  [gTbDefaults boolForKey: dnsKey]  ) {
                    nModifyNameserver++;
                }
            } else {
                nModifyNameserver++;
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
        NSString * sSN   = [NSString stringWithFormat:@"%d", nModifyNameserver  ];
        NSString * sPkg  = [NSString stringWithFormat:@"%d", nPackages          ];
        NSString * sMC   = [NSString stringWithFormat:@"%d", nMonitorConnection ];
        NSString * sDep  = ([[gConfigDirs objectAtIndex: 0] isEqualToString: gDeployPath] ? @"1" : @"0");
        NSString * sAdm  = (userIsAnAdmin ? @"1" : @"0");
        NSString * sUuid = [self installationId];
        
        // IMPORTANT: If new keys are added here, they must also be added to profileConfig.php on the website
        //            or the user's data for the new keys will not be recorded in the database.
        
        return [NSArray arrayWithObjects:
                [NSDictionary dictionaryWithObjectsAndKeys:
                 @"nConn",   @"key", sConn, @"value", NSLocalizedString(@"Configurations",      @"Window text"  ), @"displayKey", sConn, @"displayValue", nil],
                [NSDictionary dictionaryWithObjectsAndKeys:
                 @"nSetDNS", @"key", sSN,   @"value", NSLocalizedString(@"Set nameserver",      @"Checkbox name"), @"displayKey", sSN,   @"displayValue", nil],
                [NSDictionary dictionaryWithObjectsAndKeys:
                 @"nPkgs  ", @"key", sPkg,  @"value", NSLocalizedString(@"VPN Connections",     @"Window text"  ), @"displayKey", sPkg,  @"displayValue", nil],
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

// This method tries to "hook up" to any running OpenVPN processes.
//
// (If no OpenVPN processes exist, there's nothing to hook up to, so we skip all this)
//
// It searches for files in the log directory with names of A.B.C.openvpn.log, where
// A is the path to the configuration file (with -- instead of dashes and -/ instead of slashes)
// B is the arguments that openvpnstart was invoked with, separated by underscores
// C is the management port number
// The file contains the OpenVPN log.
//
// The [connection tryToHookupToPort:] method corresponding to the configuration file is used to set
// the connection's port # and initiate communications to get the process ID for that instance of OpenVPN

-(void) hookupToRunningOpenVPNs
{
    if (  [[NSApp pIdsForOpenVPNProcesses] count] != 0  ) {
        NSString * filename;
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: LOG_DIR];
        while (  filename = [dirEnum nextObject]  ) {
            [dirEnum skipDescendents];
            NSString * oldFullPath = [LOG_DIR stringByAppendingPathComponent: filename];
            if (  [[filename pathExtension] isEqualToString: @"log"]) {
                if (  [[[filename stringByDeletingPathExtension] pathExtension] isEqualToString: @"openvpn"]) {
                    int port = 0;
                    NSString * startArguments = nil;
                    NSString * cfgPath = [self deconstructOpenVPNLogPath: oldFullPath
                                                                  toPort: &port
                                                             toStartArgs: &startArguments];
                    NSArray * keysForConfig = [myConfigDictionary allKeysForObject: cfgPath];
                    int keyCount = [keysForConfig count];
                    if (  keyCount == 0  ) {
                        NSLog(@"No keys in myConfigDictionary for %@", cfgPath);
                    } else {
                        if (  keyCount != 1  ) {
                            NSLog(@"Using first of %d keys in myConfigDictionary for %@", keyCount, cfgPath);
                        }
                        NSString * displayName = [keysForConfig objectAtIndex: 0];
                        VPNConnection * connection = [myVPNConnectionDictionary objectForKey: displayName];
                        [connection tryToHookupToPort: port withOpenvpnstartArgs: startArguments];
                    }
                }
            }
        }
    }
}

// Returns a configuration path (and port number and the starting arguments from openvpnstart) from a path created by openvpnstart
-(NSString *) deconstructOpenVPNLogPath: (NSString *) logPath toPort: (int *) portPtr toStartArgs: (NSString * *) startArgsPtr
{
    NSString * prefix = [NSString stringWithFormat:@"%@/", LOG_DIR];
    NSString * suffix = @".openvpn.log";
    if (  [logPath hasPrefix: prefix]  ) {
        if (  [logPath hasSuffix: suffix]  ) {
            int prefixLength = [prefix length];
            NSRange r = NSMakeRange(prefixLength, [logPath length] - prefixLength - [suffix length]);
            NSString * withoutPrefixOrDotOpenvpnDotLog = [logPath substringWithRange: r];
            NSString * withoutPrefixOrPortOrOpenvpnDotLog = [withoutPrefixOrDotOpenvpnDotLog stringByDeletingPathExtension];
            NSString * startArguments = [withoutPrefixOrPortOrOpenvpnDotLog pathExtension];
            if (  startArguments  ) {
                if (  ! ( [startArguments isEqualToString: @"ovpn"] || [startArguments isEqualToString: @"conf"] )  ) {
                    *startArgsPtr = startArguments;
                }
            }
            NSString * portString = [withoutPrefixOrDotOpenvpnDotLog pathExtension];
            int port = [portString intValue];
            if (   port != 0
                && port != INT_MAX
                && port != INT_MIN  ) {
                
                *portPtr = port;
                
                NSMutableString * cfg = [[withoutPrefixOrPortOrOpenvpnDotLog stringByDeletingPathExtension] mutableCopy];
                [cfg replaceOccurrencesOfString: @"-S" withString: @"/" options: 0 range: NSMakeRange(0, [cfg length])];
                [cfg replaceOccurrencesOfString: @"--" withString: @"-" options: 0 range: NSMakeRange(0, [cfg length])];
                [cfg replaceOccurrencesOfString: @".tblk/Contents/Resources/config.ovpn" withString: @".tblk" options: 0 range: NSMakeRange(0, [cfg length])];
                NSString * returnVal = [[cfg copy] autorelease];
                [cfg release];
                
                return returnVal;
            } else {
                NSLog(@"deconstructOpenVPNLogPath: called with invalid port number in path %@", logPath);
                return @"";
            }
        } else {
            NSLog(@"deconstructOpenVPNLogPath: called with non-log path %@", logPath);
            return @"";
        }
    } else {
        NSLog(@"deconstructOpenVPNLogPath: called with invalid prefix to path %@", logPath);
        return @"";
    }
}

-(unsigned) incrementTapCount
{
    return ++tapCount;
}

-(unsigned) incrementTunCount
{
    return ++tunCount;
}

-(unsigned) decrementTapCount
{
    return --tapCount;
}

-(unsigned) decrementTunCount
{
    return --tunCount;
}

-(void) dmgCheck
{
    [NSApp setAutoLaunchOnLogin: NO];
    
	NSString * currentPath = [[NSBundle mainBundle] bundlePath];
	if (  [self cannotRunFromVolume: currentPath]  ) {
        
        NSString * appVersion   = tunnelblickVersion([NSBundle mainBundle]);
        
        NSString * preMessage = NSLocalizedString(@" Tunnelblick cannot be used from this location. It must be installed on a local hard drive.\n\n", @"Window text");
        NSString * displayApplicationName = [gFileMgr displayNameAtPath: @"Tunnelblick.app"];
        
        NSString * tbInApplicationsPath = @"/Applications/Tunnelblick.app";
        NSString * applicationsPath = @"/Applications";
        NSString * tbInApplicationsDisplayName = [[gFileMgr componentsToDisplayForPath: tbInApplicationsPath] componentsJoinedByString: @"/"];
        NSString * applicationsDisplayName = [[gFileMgr componentsToDisplayForPath: applicationsPath] componentsJoinedByString: @"/"];
        
        NSString * changeLocationText = [NSString stringWithFormat: NSLocalizedString(@" (To install in a different location, drag %@ to that location.)", @"Window text"), displayApplicationName];
        NSString * launchWindowTitle = NSLocalizedString(@"Installation succeeded", @"Window title");
        NSString * launchWindowText;
        NSString * authorizationText;
        int response;
        
        // See if there are any .tblks on the .dmg that should be installed
        NSString * tblksMsg = @"";
        NSArray * tblksToInstallPaths = [self findTblksToInstallInPath: [currentPath stringByDeletingLastPathComponent]];
        if (  tblksToInstallPaths  ) {
            tblksMsg = [NSString stringWithFormat: NSLocalizedString(@"\n\nand install %d Tunnelblick VPN Configurations", @"Window text"),
                        [tblksToInstallPaths count]];
        }
        
        if (  [gFileMgr fileExistsAtPath: tbInApplicationsPath]  ) {
            NSBundle * previousBundle = [NSBundle bundleWithPath: tbInApplicationsPath];
            NSString * previousVersion = tunnelblickVersion(previousBundle);
                authorizationText = [NSString stringWithFormat:
                                     NSLocalizedString(@" Do you wish to replace\n    %@\n    in %@\nwith %@%@?\n\n%@", @"Window text"),
                                     previousVersion, applicationsDisplayName, appVersion, tblksMsg, changeLocationText];
                launchWindowText = NSLocalizedString(@"Tunnelblick was successfully replaced.\n\nDo you wish to launch Tunnelblick now?", @"Window text");
        } else {
            authorizationText = [NSString stringWithFormat:
                                 NSLocalizedString(@" Do you wish to install %@ to %@%@?\n\n%@", @"Window text"),
                                 appVersion, applicationsDisplayName, tblksMsg, changeLocationText];
            launchWindowText = NSLocalizedString(@"Tunnelblick was successfully installed.\n\nDo you wish to launch Tunnelblick now?", @"Window text");
        }
        
        // Get authorization to install and secure
        myAuth = [NSApplication getAuthorizationRef: [preMessage stringByAppendingString: authorizationText]];
        if (  ! myAuth  ) {
            NSLog(@"The Tunnelblick installation was cancelled by the user.");
            [NSApp terminate:self];
        }
        
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
        
        // Install .tblks
        if (  tblksToInstallPaths  ) {
            // Install the .tblks
            launchFinished = TRUE;  // Fake out openFiles so it installs the .tblk(s) immediately
            [self application: NSApp openFiles: tblksToInstallPaths];
            launchFinished = FALSE;
        }
        
        // Install this program and secure it
        if (  ! [self runInstallerRestoreDeploy: TRUE
                                        copyApp: TRUE
                                      repairApp: TRUE
                             moveLibraryOpenVPN: TRUE
                                 repairPackages: FALSE]  ) {
            // runInstallerRestoreDeploy has already put up an error dialog and put a message in the console log if error occurred
            [NSApp terminate:self];
        }
        
        response = TBRunAlertPanel(launchWindowTitle,
                                   [NSString stringWithFormat: launchWindowText],
                                   NSLocalizedString(@"Launch", "Button"), // Default button
                                   NSLocalizedString(@"Quit", "Button"), // Alternate button
                                   nil);
        if (  response == NSAlertDefaultReturn  ) {
            // Launch the program in /Applications
            if (  ! [[NSWorkspace sharedWorkspace] launchApplication: tbInApplicationsPath]  ) {
                TBRunAlertPanel(NSLocalizedString(@"Unable to launch Tunnelblick", @"Window title"),
                                [NSString stringWithFormat: NSLocalizedString(@"An error occurred while trying to launch %@", @"Window text"), tbInApplicationsDisplayName],
                                NSLocalizedString(@"Cancel", @"Button"),                // Default button
                                nil,
                                nil);
            }
        }
        
        [NSApp terminate: nil];
    }
}

-(NSArray *) findTblksToInstallInPath: (NSString *) thePath
{
    NSMutableArray * arrayToReturn = nil;
    NSString * file;
    
    NSString * folder = [thePath stringByAppendingPathComponent: @"auto-install"];
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: folder];
    while (  file = [dirEnum nextObject]  ) {
        if (  [[file pathExtension] isEqualToString: @"tblk"]  ) {
            if (  arrayToReturn == nil  ) {
                arrayToReturn = [NSMutableArray arrayWithCapacity:10];
            }
            [arrayToReturn addObject: [folder stringByAppendingPathComponent: file]];
        }
    }
    
    folder = [thePath stringByAppendingPathComponent: @".auto-install"];
    dirEnum = [gFileMgr enumeratorAtPath: folder];
    while (  file = [dirEnum nextObject]  ) {
        [dirEnum skipDescendents];
        if (  [[file pathExtension] isEqualToString: @"tblk"]  ) {
            if (  arrayToReturn == nil  ) {
                arrayToReturn = [NSMutableArray arrayWithCapacity:10];
            }
            [arrayToReturn addObject: [folder stringByAppendingPathComponent: file]];
        }
    }
    
    return [[arrayToReturn copy] autorelease];
}

// Returns TRUE if can't run Tunnelblick from this volume (can't run setuid binaries) or if statfs on it fails, FALSE otherwise
-(BOOL) cannotRunFromVolume: (NSString *)path
{
    if ([path hasPrefix:@"/Volumes/Tunnelblick"]  ) {
        return TRUE;
    }
    
    const char * fileName = [path UTF8String];
    struct statfs stats_buf;
    
    if (  0 == statfs(fileName, &stats_buf)  ) {
        if (  (stats_buf.f_flags & MNT_NOSUID) == 0  ) {
            return FALSE;
        }
    } else {
        NSLog(@"statfs on %@ failed; assuming cannot run from that volume\nError was '%s'", path, strerror(errno));
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

// Invoked when a folder containing configurations has changed.
-(void) watcher: (UKKQueue*) kq receivedNotification: (NSString*) nm forPath: (NSString*) fpath {
    [self performSelectorOnMainThread: @selector(activateStatusMenu) withObject: nil waitUntilDone: YES];
}

// Runs the installer to backup/restore Resources/Deploy and/or repair ownership/permissions of critical files and/or move the config folder
// restore     should be TRUE if Resources/Deploy should be restored from its backup
// repairIt    should be TRUE if needsRepair() returned TRUE
// moveIt      should be TRUE if /Library/openvpn needs to be moved to /Library/Application Support/Tunnelblick/Configurations
// repairPkgs  should be TRUE if .tblk packages should have their ownership/permissions repaired
// inAuthRef   should be nil or an AuthorizationRef
// Returns TRUE if ran successfully, FALSE if failed
-(BOOL) runInstallerRestoreDeploy: (BOOL) restoreDeploy copyApp: (BOOL) copyIt repairApp: (BOOL) repairApp moveLibraryOpenVPN: (BOOL) moveConfigs repairPackages: (BOOL) repairPkgs
{
    if (  ! (restoreDeploy || copyIt || repairApp || moveConfigs  || repairPkgs)  ) {
        return YES;
    }
    
    // Use our own copies of the arguments
    BOOL needsRestoreDeploy = restoreDeploy;
    BOOL copyAppToApplications = copyIt;
    BOOL needsAppRepair     = repairApp;
    BOOL needsPkgRepair     = repairPkgs;
    BOOL needsMoveConfigs   = moveConfigs;
    
    if (  myAuth == nil  ) {
        NSMutableString * msg = [NSMutableString stringWithString: NSLocalizedString(@"Tunnelblick needs to:\n", @"Window text")];
        if (  needsAppRepair      ) [msg appendString: NSLocalizedString(@"  • Change ownership and permissions of the program to secure it\n", @"Window text")];
        if (  needsMoveConfigs    ) [msg appendString: NSLocalizedString(@"  • Repair the private configurations folder\n", @"Window text")];
        if (  needsRestoreDeploy  ) [msg appendString: NSLocalizedString(@"  • Restore configuration(s) from the backup\n", @"Window text")];
        if (  needsPkgRepair      ) [msg appendString: NSLocalizedString(@"  • Secure Tunnelblick VPN Configurations\n", @"Window text")];
        
        NSLog(msg);
        
        // Get an AuthorizationRef and use executeAuthorized to run the installer
        myAuth= [NSApplication getAuthorizationRef: msg];
        if(myAuth == nil) {
            NSLog(@"Installation or repair cancelled");
            return FALSE;
        }
    }
        
    NSLog(@"Beginning installation or repair");

    int i;
    BOOL okNow;
    
    for (i=0; i < 5; i++) {
        NSMutableArray * arguments = [[[NSMutableArray alloc] initWithCapacity:2] autorelease];
        
        if (  needsAppRepair || needsMoveConfigs || copyAppToApplications  ) {
            if (  copyAppToApplications  ) {
                [arguments addObject:@"2"];
            } else {
                [arguments addObject:@"1"];
            }
        } else {
            [arguments addObject:@"0"];
        }
        if (  needsPkgRepair  ) {
            [arguments addObject:@"1"];
        } else {
            [arguments addObject:@"0"];
        }
        
        
        if (   [self runInstallerWithArguments: arguments authorization: myAuth]
            && ( okNow = ( ! needToRunInstaller(&needsAppRepair, &needsMoveConfigs, &needsRestoreDeploy, &needsPkgRepair, copyAppToApplications) ) )  ) {
            break;
        }
        
        sleep(1);
        
        okNow = ! needToRunInstaller( &needsAppRepair, &needsMoveConfigs, &needsRestoreDeploy, &needsPkgRepair, copyAppToApplications );
        if (  okNow  ) {
            break;
        }
        
        NSLog(@"Installation or repair failed; retrying");
    }
    
    // NOTE: We do NOT free myAuth here. It may be used to install .tblk packages, so we free it when we are finished launching
    
    if (  ! okNow  ) {
        NSLog(@"Installation or repair failed");
        TBRunAlertPanel(NSLocalizedString(@"Installation or Repair Failed", "Window title"),
                        NSLocalizedString(@"The installation, removal, recovery, or repair of one or more Tunnelblick components failed. See the Console Log for details.", "Window text"),
                        nil, nil, nil);
        return FALSE;
    }
    
    NSLog(@"Installation or repair succeeded");
    return TRUE;
}

-(BOOL) runInstallerWithArguments: (NSArray *) arguments authorization: (AuthorizationRef) authRef
{
    // We create a file that indicates that the installer is running. The installer deletes it after it finishes, and we see that deletion as a signal that it is done
    // The filename needs the session ID to support fast user switching
    NSString * privilegedRunningFlagFilePath = [NSString stringWithFormat:@"/tmp/Tunnelblick/InstallationInProcess-%d.txt", gSecuritySessionId];
    if (  ! [gFileMgr createFileAtPath: privilegedRunningFlagFilePath
                              contents: [NSData data]
                            attributes: [NSDictionary dictionary]]  ) {
        NSLog(@"Unable to create flag file %@", privilegedRunningFlagFilePath);
    }
    
    // Similarly, installer creates a file to act as a flag that the installation failed. installer deletes it before a success return
    NSString * privilegedFailureFlagFilePath = [NSString stringWithFormat:@"/tmp/Tunnelblick/InstallationFailed-%d.txt", gSecuritySessionId];
    
    NSString *launchPath = [[NSBundle mainBundle] pathForResource:@"installer" ofType:nil];
    
    OSStatus status = [NSApplication executeAuthorized: launchPath withArguments: arguments withAuthorizationRef: authRef];
    if (  status != 0  ) {
        NSLog(@"Returned status of %d indicates failure of installer execution of %@: %@", status, launchPath, arguments);
        if (  [gFileMgr fileExistsAtPath: privilegedFailureFlagFilePath]  ) {
            [gFileMgr removeFileAtPath: privilegedFailureFlagFilePath handler: nil];
        }
        return FALSE;
    }
    
    int counter = 0;   // Wait up to twenty seconds for the inProgress file to disappear
    while (   (counter++ < 20)
           && [gFileMgr fileExistsAtPath: privilegedRunningFlagFilePath]  ) {
        sleep(1);
    }
    
    if (  counter > 19  ) {
        NSLog(@"Timed out waiting for installer to finish. %@ still exists", privilegedRunningFlagFilePath);
    }
    
    if (  [gFileMgr fileExistsAtPath: privilegedFailureFlagFilePath]  ) {
        [gFileMgr removeFileAtPath: privilegedFailureFlagFilePath handler: nil];
        NSLog(@"Presence of error file indicates failure executing %@: %@", launchPath, arguments);
        return FALSE;
    }
    
    return TRUE;
}    

// Checks whether the installer needs to be run
// Returns with the respective arguments set YES or NO, and returns YES if any is YES. Otherwise returns NO.
BOOL needToRunInstaller(BOOL * changeOwnershipAndOrPermissions, BOOL * moveLibraryOpenVPN, BOOL  *restoreDeploy, BOOL * needsPkgRepair, BOOL inApplications) 
{
    *moveLibraryOpenVPN = needToMoveLibraryOpenVPN();
    *changeOwnershipAndOrPermissions = needToChangeOwnershipAndOrPermissions(inApplications);
    *restoreDeploy = needToRestoreDeploy();
    *needsPkgRepair = needToRepairPackages();
    
    return ( * moveLibraryOpenVPN || * changeOwnershipAndOrPermissions || * restoreDeploy || * needsPkgRepair );
}

BOOL needToMoveLibraryOpenVPN(void)
{
    // Check that the configuration folder has been moved and replaced by a symlink. If not, return YES
    NSString * oldConfigDirPath = [NSHomeDirectory() stringByAppendingPathComponent: @"Library/openvpn"];
    NSString * newConfigDirPath = [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Application Support/Tunnelblick/Configurations"];
    BOOL isDir;
    
    BOOL newFolderExists = FALSE;
    // Check NEW location of private configurations
    if (  [gFileMgr fileExistsAtPath: newConfigDirPath isDirectory: &isDir]  ) {
        if (  isDir  ) {
            newFolderExists = TRUE;
        } else {
            NSLog(@"Error: %@ exists but is not a folder", newConfigDirPath);
            terminateBecauseOfBadConfiguration();
        }
    } else {
       NSLog(@"%@ does not exist", newConfigDirPath);
       return YES; // New folder does not exist.
    }
    
    // OLD location must either be a directory, or a symbolic link to the NEW location
    NSDictionary * fileAttributes = [gFileMgr fileAttributesAtPath: oldConfigDirPath traverseLink: NO];
    if (  ! [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
        if (  [gFileMgr fileExistsAtPath: oldConfigDirPath isDirectory: &isDir]  ) {
            if (  isDir  ) {
                if (  newFolderExists  ) {
                    NSLog(@"Both %@ and %@ exist and are folders", oldConfigDirPath, newConfigDirPath);
                    return YES; // Installer will try to repair this
                } else {
                    NSLog(@"%@ exists, but %@ doesn't", oldConfigDirPath, newConfigDirPath);
                    return YES;  // old folder exists, but new one doesn't, so do the move
                }
            } else {
                NSLog(@"Error: %@ exists but is not a symbolic link or a folder", oldConfigDirPath);
                terminateBecauseOfBadConfiguration();
            }
        }
    } else {
        // ~/Library/openvpn is a symbolic link
        if (  ! [[gFileMgr pathContentOfSymbolicLinkAtPath: oldConfigDirPath] isEqualToString: newConfigDirPath]  ) {
            NSLog(@"%@ exists and is a symbolic link but does not reference %@", oldConfigDirPath, newConfigDirPath);
            return YES; // Installer will repair this
        }
    }

    return NO;  // Nothing needs to be done
}

BOOL needToChangeOwnershipAndOrPermissions(BOOL inApplications)
{
	// Check ownership and permissions on components of Tunnelblick.app
    NSString * resourcesPath;
    if ( inApplications  ) {
        resourcesPath = @"/Applications/Tunnelblick.app/Contents/Resources";
    } else {
        resourcesPath = [[NSBundle mainBundle] resourcePath];
	}
    
	NSString *installerPath         = [resourcesPath stringByAppendingPathComponent: @"installer"                      ];
	NSString *openvpnstartPath      = [resourcesPath stringByAppendingPathComponent: @"openvpnstart"                   ];
	NSString *openvpnPath           = [resourcesPath stringByAppendingPathComponent: @"openvpn"                        ];
	NSString *atsystemstartPath     = [resourcesPath stringByAppendingPathComponent: @"atsystemstart"                  ];
	NSString *leasewatchPath        = [resourcesPath stringByAppendingPathComponent: @"leasewatch"                     ];
	NSString *clientUpPath          = [resourcesPath stringByAppendingPathComponent: @"client.up.osx.sh"               ];
	NSString *clientDownPath        = [resourcesPath stringByAppendingPathComponent: @"client.down.osx.sh"             ];
	NSString *clientNoMonUpPath     = [resourcesPath stringByAppendingPathComponent: @"client.nomonitor.up.osx.sh"     ];
	NSString *clientNoMonDownPath   = [resourcesPath stringByAppendingPathComponent: @"client.nomonitor.down.osx.sh"   ];
	NSString *clientNewUpPath       = [resourcesPath stringByAppendingPathComponent: @"client.up.tunnelblick.sh"       ];
	NSString *clientNewDownPath     = [resourcesPath stringByAppendingPathComponent: @"client.down.tunnelblick.sh"     ];
	NSString *clientNewAlt1UpPath   = [resourcesPath stringByAppendingPathComponent: @"client.1.up.tunnelblick.sh"     ];
	NSString *clientNewAlt1DownPath = [resourcesPath stringByAppendingPathComponent: @"client.1.down.tunnelblick.sh"   ];
	NSString *clientNewAlt2UpPath   = [resourcesPath stringByAppendingPathComponent: @"client.2.up.tunnelblick.sh"     ];
	NSString *clientNewAlt2DownPath = [resourcesPath stringByAppendingPathComponent: @"client.2.down.tunnelblick.sh"   ];
    NSString *deployPath            = [resourcesPath stringByAppendingPathComponent: @"Deploy"];
    NSString *infoPlistPath         = [[resourcesPath stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"Info.plist"];

	// check openvpnstart owned by root with suid and 544 permissions
	const char *path = [openvpnstartPath UTF8String];
    struct stat sb;
	if(stat(path,&sb)) {
        NSLog(@"Unable to determine status of \"openvpnstart\"");
        return YES;
	}
	if (   (sb.st_uid != 0)
        || ((sb.st_mode & 07777) != 04555)  ) {
        return YES;
	}
	
    // check openvpn
    if (  ! checkOwnerAndPermissions(openvpnPath, 0, 0, @"755")  ) {
        return YES; // NSLog already called
    }
    
	// check files which should be owned by root with 744 permissions
	NSArray *root744Objects = [NSArray arrayWithObjects:
                                    installerPath, atsystemstartPath, leasewatchPath,
                                    clientUpPath, clientDownPath,
                                    clientNoMonUpPath, clientNoMonDownPath,
                                    clientNewUpPath, clientNewDownPath,
                                    clientNewAlt1UpPath, clientNewAlt1DownPath,
                                    clientNewAlt2UpPath, clientNewAlt2DownPath,
                                    nil];
	NSEnumerator *e = [root744Objects objectEnumerator];
	NSString *currentPath;
	while(currentPath = [e nextObject]) {
        if (  ! checkOwnerAndPermissions(currentPath, 0, 0, @"744")  ) {
            return YES; // NSLog already called
        }
	}
    
    // check Info.plist
    if (  ! checkOwnerAndPermissions(infoPlistPath, 0, 0, @"644")  ) {
        return YES; // NSLog already called
    }
    
    // check permissions of files in Resources/Deploy (if it exists)
    BOOL isDir;
    if (  [gFileMgr fileExistsAtPath: deployPath isDirectory: &isDir]
        && isDir  ) {
        if (  folderContentsNeedToBeSecuredAtPath(deployPath)  ) {
            return YES;
        }
    }
    
    // check permissions of files in the Deploy backup, also (if any)        
    NSString * deployBackupPath = [[[[@"/Library/Application Support/Tunnelblick/Backup" stringByAppendingPathComponent: [[NSBundle mainBundle] bundlePath]]
                                     stringByDeletingLastPathComponent]
                                    stringByAppendingPathComponent: @"TunnelblickBackup"]
                                   stringByAppendingPathComponent: @"Deploy"];
    if (  [gFileMgr fileExistsAtPath: deployBackupPath isDirectory: &isDir]
        && isDir  ) {
        if (  folderContentsNeedToBeSecuredAtPath(deployBackupPath)  ) {
            return YES;
        }
    }
    
    return NO;
}

BOOL needToRestoreDeploy(void)
{
    // Restore Resources/Deploy and/or repair ownership and permissions and/or  if necessary
    NSString * gDeployPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"Deploy"];
    NSString * deployBackupPath = [[[[@"/Library/Application Support/Tunnelblick/Backup" stringByAppendingPathComponent: [[NSBundle mainBundle] bundlePath]]
                                     stringByDeletingLastPathComponent]
                                    stringByAppendingPathComponent: @"TunnelblickBackup"]
                                   stringByAppendingPathComponent: @"Deploy"];
    BOOL isDir;
    BOOL haveBackup   = [gFileMgr fileExistsAtPath: deployBackupPath isDirectory: &isDir]
    && isDir;
    BOOL haveDeploy   = [gFileMgr fileExistsAtPath: gDeployPath    isDirectory: &isDir]
    && isDir;
    return haveBackup && ( ! haveDeploy);
}    

BOOL needToRepairPackages(void)
{
    // check permissions of .tblk packages
    uid_t realUid = getuid();
    gid_t realGid = getgid();
    NSString * packagesPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Tunnelblick/Configurations/"];
    NSString * file;
    NSDirectoryEnumerator *dirEnum = [gFileMgr enumeratorAtPath: packagesPath];
    while (file = [dirEnum nextObject]) {
        NSString * fullPath = [packagesPath stringByAppendingPathComponent: file];
        if (  itemIsVisible(fullPath)  ) {
            NSString * ext  = [file pathExtension];
            if (  [ext isEqualToString: @"tblk"]  ) {
                if (  [fullPath hasPrefix: gPrivatePath]  ) {
                    if (  ! checkOwnerAndPermissions(fullPath, realUid, realGid, @"755")  ) {
                        return YES;
                    }
                } else {
                    if (  ! checkOwnerAndPermissions(fullPath, 0, 0, @"755")  ) {
                        return YES;
                    }
                }
                if (  folderContentsNeedToBeSecuredAtPath(fullPath)) {
                    return YES;
                }
            }
        }
    }
    
    return NO;
}

void terminateBecauseOfBadConfiguration(void)
{
    TBRunAlertPanel(NSLocalizedString(@"Tunnelblick Configuration Problem", @"Window title"),
                    NSLocalizedString(@"Tunnelblick could not be launched because of a problem with the configuration. Please examine the Console Log for details.", @"Window text"),
                    nil, nil, nil);
    [NSApp setAutoLaunchOnLogin: NO];
    [NSApp terminate: nil];
}

-(void)willGoToSleep
{
	if(NSDebugEnabled) NSLog(@"Computer will go to sleep");
	connectionsToRestore = [connectionArray mutableCopy];
	[self killAllConnectionsIncludingDaemons: YES];  // Kill any OpenVPN processes that still exist
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

-(IBAction) autoConnectPrefButtonWasClicked: (id) sender
{
	if([sender state]) {
		[self saveAutoLaunchCheckboxState:TRUE];
	} else {
		[self saveAutoLaunchCheckboxState:FALSE];
	}
    [self validateDetailsWindowControls];
}

-(IBAction) monitorConnectionPrefButtonWasClicked: (id) sender
{
	if([sender state]) {
		[self saveMonitorConnectionCheckboxState:TRUE];
	} else {
		[self saveMonitorConnectionCheckboxState:FALSE];
	}
    [self validateDetailsWindowControls];
}

-(IBAction) onLaunchRadioButtonWasClicked: (id) sender
{
	if([[sender cellAtRow: 0 column: 0] state]) {
		[self saveOnSystemStartRadioButtonState: FALSE forConnection: [self selectedConnection]];
	} else {
		[self saveOnSystemStartRadioButtonState: TRUE forConnection: [self selectedConnection]];
	}
    [self performSelectorOnMainThread:@selector(fixWhenConnectingButtons) withObject:nil waitUntilDone:NO];
}

-(IBAction) onSystemStartRadioButtonWasClicked: (id) sender
{
	if([[sender cellAtRow: 0 column: 0] state]) {
		[self saveOnSystemStartRadioButtonState: TRUE forConnection: [self selectedConnection]];
	} else {
		[self saveOnSystemStartRadioButtonState: FALSE forConnection: [self selectedConnection]];
	}
    [self performSelectorOnMainThread:@selector(fixWhenConnectingButtons) withObject:nil waitUntilDone:NO];
}

// We use this to get around a problem with our use of the "when Tunnelblick launches" and "when the computer starts" radio buttons.
// If the user clicks the button but then cancels, OS X changes the state of the button _after_ our WasClicked handler. So
// we set both buttons to the way they should be _after_ OS X makes that change.
-(void) fixWhenConnectingButtons
{
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        NSString* key = [[connection displayName] stringByAppendingString: @"-onSystemStart"];
        BOOL preferenceValue = [gTbDefaults boolForKey: key];
        [[onSystemStartRadioButton cellAtRow: 0 column: 0]  setState:   preferenceValue];
        [[onLaunchRadioButton      cellAtRow: 0 column: 0]  setState: ! preferenceValue];
        [self validateDetailsWindowControls];
    }
}

-(void) hotKeySubmenuItemWasClicked: (NSMenuItem *) fKey
{
    if (  fKey == hotKeySubmenuItemThatIsOn  ) {
        UnregisterEventHotKey(hotKeyRef);
        
        [hotKeySubmenuItemThatIsOn setState: NSOffState];
        [hotKeySubmenuItemThatIsOn release];
        hotKeySubmenuItemThatIsOn = nil;
        
        hotKeyModifierKeys = 0;
        hotKeyKeyCode = 0;
        
        [gTbDefaults setObject: [NSNumber numberWithInt: 0] forKey: @"keyboardShortcutModifiers"];
        [gTbDefaults setObject: [NSNumber numberWithInt: 0] forKey: @"keyboardShortcutKeyCode"];
    } else {
        [hotKeySubmenuItemThatIsOn setState: NSOffState];
        [hotKeySubmenuItemThatIsOn release];
        hotKeySubmenuItemThatIsOn = nil;
        
        int fIndex = [[fKey representedObject] intValue];

        [self setupHotKeyWithCode: fKeyCode[fIndex] andModifierKeys:  cmdKey + optionKey];
        
        hotKeySubmenuItemThatIsOn = [fKey retain];
        [hotKeySubmenuItemThatIsOn setState: NSOnState];
        
        [gTbDefaults setObject: [NSNumber numberWithInt: hotKeyModifierKeys] forKey:  @"keyboardShortcutModifiers"];
        [gTbDefaults setObject: [NSNumber numberWithInt: hotKeyKeyCode]      forKey:  @"keyboardShortcutKeyCode"];
    }
}

-(void) setupHotKeyWithCode: (UInt32) keyCode andModifierKeys: (UInt32) modifierKeys
{
    if (  hotKeyEventHandlerIsInstalled  ) {
        if (  hotKeyModifierKeys != 0  ) {
            UnregisterEventHotKey(hotKeyRef);
        }
    } else {
        EventTypeSpec eventType;
        eventType.eventClass = kEventClassKeyboard;
        eventType.eventKind  = kEventHotKeyPressed;
        InstallApplicationEventHandler(&hotKeyPressed, 1, &eventType, (void *) self, NULL);
        hotKeyEventHandlerIsInstalled = TRUE;
    }
    
    EventHotKeyID hotKeyID;
    hotKeyID.signature = 'htk1';
    hotKeyID.id = 1;
    RegisterEventHotKey(keyCode, modifierKeys, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef);
    
    hotKeyKeyCode = keyCode;
    hotKeyModifierKeys = modifierKeys;
}

OSStatus hotKeyPressed(EventHandlerCallRef nextHandler,EventRef theEvent, void * userData)
{
    // When the hotKey is pressed, pop up the Tunnelblick menu from the Status Bar
    MenuController * menuC = (MenuController *) userData;
    NSStatusItem * statusI = [menuC statusItem];
    [statusI popUpStatusItemMenu: [statusI menu]];
    return noErr;
}

-(NSStatusItem *) statusItem
{
    return statusItem;
}
    
-(int) selectedModifyNameserverIndex
{
    return selectedModifyNameserverIndex;
}

-(void) setSelectedModifyNameserverIndex: (int) newValue
{
    // We duplicate this code in validateDetailsWindowControls but without calling itself
    if (  newValue != selectedModifyNameserverIndex  ) {
        selectedModifyNameserverIndex = newValue;
        [modifyNameserverPopUpButton selectItemAtIndex: newValue];
        [self saveUseNameserverPopupButtonState: (unsigned) newValue];
        [self validateDetailsWindowControls];   // The code in validateDetailsWindowControls DOES NOT do this
    }
}

-(NSString *) customRunOnConnectPath
{
    return customRunOnConnectPath;
}

-(int) selectedLeftNavListIndex
{
    return selectedLeftNavListIndex;
}

-(void) tableViewSelectionDidChange:(NSNotification *)notification
{
    [self performSelectorOnMainThread: @selector(selectedLeftNavListIndexChanged) withObject: nil waitUntilDone: NO];
}

-(void) selectedLeftNavListIndexChanged
{
    int n = [leftNavListView selectedRow];
    [self setSelectedLeftNavListIndex: n];
}

-(void) setSelectedLeftNavListIndex: (int) newValue
{
    if (  newValue != selectedLeftNavListIndex  ) {
        
        // Don't allow selection of a "folder" row, only of a "configuration" row
        while (  [[leftNavDisplayNames objectAtIndex: newValue] length] == 0) {
            ++newValue;
        }
        
        selectedLeftNavListIndex = newValue;
        [leftNavListView selectRowIndexes: [NSIndexSet indexSetWithIndex: newValue] byExtendingSelection: NO];
        NSString * label = [[leftNavList objectAtIndex: newValue] stringByTrimmingCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @" "]];
        [[tabView tabViewItemAtIndex:0] setLabel: label];
        
        [[[self selectedLogView] textStorage] setDelegate: nil];
        VPNConnection* newConnection = [self selectedConnection];
        NSTextView* logView = [self selectedLogView];
        [logView setEditable: NO];
        [[logView layoutManager] replaceTextStorage: [newConnection logStorage]];
        [logView scrollRangeToVisible: NSMakeRange([[logView string] length]-1, 0)];
        [[logView textStorage] setDelegate: self];
        [self setLogWindowTitle];
        [self validateDetailsWindowControls];
    }
}

@end
