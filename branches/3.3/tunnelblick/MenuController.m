/*
 * Copyright 2004, 2005, 2006, 2007, 2008, 2009 Angelo Laub
 * Contributions by Dirk Theisen <dirk@objectpark.org>, 
 *                  Jens Ohlig, 
 *                  Waldemar Brodkorb
 * Contributions by Jonathan K. Bullard Copyright 2010, 2011
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

#import <Foundation/NSDebug.h>
#import <pthread.h>
#import <sys/stat.h>
#import <sys/mount.h>
#import <uuid/uuid.h>
#import "defines.h"
#import "MenuController.h"
#import "NSApplication+LoginItem.h"
#import "NSApplication+NetworkNotifications.h"
#import "NSApplication+SystemVersion.h"
#import "NSString+TB.h"
#import "helper.h"
#import "TBUserDefaults.h"
#import "ConfigurationManager.h"
#import "VPNConnection.h"
#import "NSFileManager+TB.h"
#import "MainIconView.h"
#import "MyPrefsWindowController.h"
#import "SplashWindowController.h"
#import "ConfigurationUpdater.h"
#import "UKKQueue/UKKQueue.h"
#import "Sparkle/SUUpdater.h"
#import "VPNConnection.h"
#import "WelcomeController.h"
#import "easyRsa.h"

#ifdef INCLUDE_VPNSERVICE
#import "VPNService.h"
#endif

// These are global variables rather than class variables to make access to them easier
NSMutableArray        * gConfigDirs = nil;            // Array of paths to configuration directories currently in use
NSString              * gPrivatePath = nil;           // Path to ~/Library/Application Support/Tunnelblick/Configurations
NSString              * gDeployPath = nil;            // Path to Tunnelblick.app/Contents/Resources/Deploy
TBUserDefaults        * gTbDefaults = nil;            // Our preferences
NSFileManager         * gFileMgr = nil;               // [NSFileManager defaultManager]
AuthorizationRef        gAuthorization = nil;         // Used to call installer
NSArray               * gProgramPreferences = nil;    // E.g., 'placeIconInStandardPositionInStatusBar'
NSArray               * gConfigurationPreferences = nil; // E.g., '-onSystemStart'
BOOL                    gShuttingDownTunnelblick = FALSE;// TRUE if applicationShouldTerminate: has been invoked
BOOL                    gShuttingDownWorkspace = FALSE;
BOOL                    gShuttingDownOrRestartingComputer = FALSE;
BOOL                    gComputerIsGoingToSleep = FALSE;// Flag that the computer is going to sleep
BOOL                    gUserWasAskedAboutConvertNonTblks = FALSE;// Flag that the user has been asked to convert non-.tblk configurations
BOOL                    gOkToConvertNonTblks = FALSE; // Flag that the user has agreed to convert non-.tblk configurations
unsigned                gHookupTimeout = 0;           // Number of seconds to try to establish communications with (hook up to) an OpenVPN process
//                                                    // or zero to keep trying indefinitely
unsigned                gMaximumLogSize = 0;          // Maximum size (bytes) of buffer used to display the log
NSArray               * gRateUnits = nil;             // Array of strings with localized data units      (KB/s, MB/s, GB/s, etc.)
NSArray               * gTotalUnits = nil;            // Array of strings with localized data rate units (KB,   MB,   GB,   etc.)
NSTimeInterval          gDelayToShowStatistics = 0.0; // Time delay from mouseEntered icon or statistics window until showing the statistics window
NSTimeInterval          gDelayToHideStatistics = 0.0; // Time delay from mouseExited icon or statistics window until hiding the statistics window


enum TerminationReason  reasonForTermination;   // Why we are terminating execution

UInt32 fKeyCode[16] = {0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64,        // KeyCodes for F1...F16
    0x65, 0x6D, 0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A};

void terminateBecauseOfBadConfiguration(void);

OSStatus hotKeyPressed(EventHandlerCallRef nextHandler,EventRef theEvent, void * userData);
OSStatus RegisterMyHelpBook(void);
BOOL checkOwnedByRootWheel(NSString * path);

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
-(BOOL)             installTblks:                           (NSArray * )        filePaths
        skipConfirmationMessage:                            (BOOL)              skipConfirmMsg
              skipResultMessage:                            (BOOL)              skipResultMsg
                 notifyDelegate:                            (BOOL)              notifyDelegate;

-(BOOL)             canRunFromVolume:                       (NSString *)        path;
-(NSURL *)          contactURL;
-(NSString *)       deconstructOpenVPNLogPath:              (NSString *)        logPath
                                       toPort:              (unsigned *)        portPtr
                                  toStartArgs:              (NSString * *)      startArgsPtr;
-(NSArray *)        findTblksToInstallInPath:               (NSString *)        thePath;
-(void)             checkNoConfigurations;
-(void)             deleteLogs;
-(void)             initialChecks:							(NSString *)        ourAppName;
-(unsigned)         getLoadedKextsMask;
-(BOOL)             hasValidSignature;
-(void)             hookupWatchdogHandler;
-(void)             hookupWatchdog;
-(BOOL)             hookupToRunningOpenVPNs;
-(void)             initialiseAnim;
-(void)             insertConnectionMenuItem:               (NSMenuItem *)      theItem
                                    IntoMenu:               (NSMenu *)          theMenu
                                  afterIndex:               (int)               theIndex
                                    withName:               (NSString *)        displayName;
-(NSString *)       installationId;
-(void)             makeSymbolicLink;
-(NSString *)       menuNameFromFilename:                   (NSString *)        inString;
-(void)             removeConnectionWithDisplayName:        (NSString *)        theName
                                           fromMenu:        (NSMenu *)          theMenu
                                         afterIndex:        (int)               theIndex;
-(void)             removeConnectionWithDisplayName:        (NSString *)        theName
                                           fromMenu:        (NSMenu *)          theMenu
                                         afterIndex:        (int)               theIndex
                                        workingName:        (NSString *)        workingName;
-(void)             removePath:                             (NSString *)        path
              fromMonitorQueue:                             (UKKQueue *)        queue;
-(void)             runCustomMenuItem:                      (NSMenuItem *)      item;
-(BOOL)             setupHookupWatchdogTimer;
-(void)             setupHotKeyWithCode:                    (UInt32)            keyCode
                        andModifierKeys:                    (UInt32)            modifierKeys;
-(void)				showWelcomeScreen;
-(NSStatusItem *)   statusItem;
-(void)             updateMenuAndLogWindow;
-(void)             updateNavigationLabels;
-(BOOL)             validateMenuItem:                       (NSMenuItem *)      anItem;
-(void)             watcher:                                (UKKQueue *)        kq
       receivedNotification:                                (NSString *)        nm
                    forPath:                                (NSString *)        fpath;
-(void) relaunchIfNecessary;
-(void) secureIfNecessary;

@end

@implementation MenuController

-(id) init
{	
    if (  (self = [super init])  ) {
        
        reasonForTermination = terminatingForUnknownReason;
        
        if (  ! runningOnTigerOrNewer()  ) {
            TBRunAlertPanel(NSLocalizedString(@"System Requirements Not Met", @"Window title"),
                            NSLocalizedString(@"Tunnelblick requires OS X 10.4 or above\n     (\"Tiger\", \"Leopard\", or \"Snow Leopard\")", @"Window text"),
                            nil, nil, nil);
            [self terminateBecause: terminatingBecauseOfError];
            
        }
        
        launchFinished = FALSE;
        hotKeyEventHandlerIsInstalled = FALSE;
        terminatingAtUserRequest = FALSE;
        mouseIsInMainIcon = FALSE;
        mouseIsInStatusWindow = FALSE;
		signatureIsInvalid = FALSE;

		gOkToConvertNonTblks = FALSE;
		gUserWasAskedAboutConvertNonTblks = FALSE;
		
        gShuttingDownTunnelblick = FALSE;
        gShuttingDownOrRestartingComputer = FALSE;
        gShuttingDownWorkspace = FALSE;
        gComputerIsGoingToSleep = FALSE;
        
        noUnknownOpenVPNsRunning = NO;   // We assume there are unattached processes until we've had time to hook up to them
        
        dotTblkFileList = nil;
        showDurationsTimer = nil;
        customRunOnLaunchPath = nil;
        customRunOnConnectPath = nil;
        customMenuScripts = nil;
                
        tunCount = 0;
        tapCount = 0;
        
        connectionsToRestoreOnWakeup = [[NSMutableArray alloc] initWithCapacity: 5];
        
        gFileMgr    = [NSFileManager defaultManager];
        
        gPrivatePath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Tunnelblick/Configurations"] copy];
        createDir(gPrivatePath, PERMS_PRIVATE_SELF);     // Create private configurations folder if necessary
        

        gConfigDirs = [[NSMutableArray alloc] initWithCapacity: 2];
        
		[NSApp setDelegate: self];
		
        userIsAnAdmin = isUserAnAdmin();
        
        NSBundle * ourBundle   = [NSBundle mainBundle];
        NSString * ourBundlePath = [ourBundle bundlePath];
        NSArray  * execComponents = [ourBundlePath pathComponents];
        if (  [execComponents count] < 1  ) {
            NSLog(@"Too few execComponents; ourBundlePath = %@", ourBundlePath);
            exit(1);
        }
        NSString * ourAppName = [execComponents lastObject];
		if (  [ourAppName hasSuffix: @".app"]  ) {
			ourAppName = [ourAppName substringToIndex: [ourAppName length] - 4];
		}
        gDeployPath = [[[ourBundle resourcePath] stringByAppendingPathComponent: @"Deploy"] copy];
		
		// Remove any old "Launch Tunnelblick" link in the private configurations folder
		NSString * tbLinkPath = [gPrivatePath stringByAppendingPathComponent: @"Launch Tunnelblick"];
		[gFileMgr tbRemoveFileAtPath: tbLinkPath handler: nil];
        
        gProgramPreferences = [[NSArray arrayWithObjects:
                                @"skipWarningAboutReprotectingConfigurationFile",
                                @"skipWarningAboutSimultaneousConnections",
								@"skipWarningAboutConvertingToTblks",
                                @"skipWarningThatCannotModifyConfigurationFile",
                                @"skipWarningThatNameChangeDisabledUpdates",
                                @"skipWarningAboutNonAdminUpdatingTunnelblick",
                                @"skipWarningAboutUnknownOpenVpnProcesses",
                                @"skipWarningAboutOnComputerStartAndTblkScripts",
                                @"skipWarningAboutIgnoredConfigurations",
                                @"skipWarningAboutConfigFileProtectedAndAlwaysExamineIt",
                                @"skipWarningThatIPAddressDidNotChangeAfterConnection",
                                @"skipWarningThatDNSIsNotWorking",
                                @"skipWarningThatInternetIsNotReachable",
								@"skipWarningAboutInvalidSignature",
								@"skipWarningAboutNoSignature",
                                
                                @"placeIconInStandardPositionInStatusBar",
                                @"doNotMonitorConfigurationFolder",
								@"doNotLaunchOnLogin",
                                @"onlyAdminsCanUnprotectConfigurationFiles",
                                @"standardApplicationPath",
                                @"doNotCreateLaunchTunnelblickLinkinConfigurations",
                                @"useShadowConfigurationFiles",
                                @"hookupTimeout",
                                @"openvpnTerminationInterval",
                                @"openvpnTerminationTimeout",
                                @"menuIconSet",
                                @"easy-rsaPath",
                                @"IPAddressCheckURL",
                                @"notOKToCheckThatIPAddressDidNotChangeAfterConnection",
                                @"askedUserIfOKToCheckThatIPAddressDidNotChangeAfterConnection",
                                @"timeoutForIPAddressCheckBeforeConnection",
                                @"timeoutForIPAddressCheckAfterConnection",
                                @"delayBeforeIPAddressCheckAfterConnection",
                                @"tunnelblickVersionHistory",
                                
                                @"disableAdvancedButton",
                                @"disableCheckNowButton",
                                @"disableResetDisabledWarningsButton",
                                
                                @"disableAddConfigurationButton",
                                @"disableRemoveConfigurationButton",
                                @"disableWorkOnConfigurationButton",
                                
                                @"disableRenameConfigurationMenuItem",
                                @"disableDuplicateConfigurationMenuItem",
                                @"disableMakeConfigurationPublicOrPrivateMenuItem",
                                @"disableRevertToShadowMenuItem",
                                @"disableExamineOpenVpnConfigurationFileMenuItem",
                                @"disableShowOpenVpnLogInFinderMenuItem",
                                @"disableDeleteConfigurationCredentialsInKeychainMenuItem",
                                
                                @"disableCopyLogToClipboardButton",
                                
                                @"doNotShowNotificationWindowBelowIconOnMouseover",
                                @"doNotShowNotificationWindowOnMouseover",
                                @"doNotShowDisconnectedNotificationWindows",
                                @"doNotShowConnectionSubmenus",
                                @"doNotShowVpnDetailsMenuItem",
                                @"doNotShowSuggestionOrBugReportMenuItem",
                                @"doNotShowAddConfigurationMenuItem",
                                @"doNotShowSplashScreen",
								@"doNotShowOutlineViewOfConfigurations",
                                @"showConnectedDurations",
                                @"showStatusWindow",
                                
                                @"welcomeURL",
                                @"welcomeWidth",
                                @"welcomeHeight",
                                @"doNotShowWelcomeDoNotShowAgainCheckbox",
                                @"skipWelcomeScreen",
                                
                                @"openvpnVersion",
                                @"maximumNumberOfTabs",
                                @"onlyAdminCanUpdate",
                                @"connectionWindowDisplayCriteria",
                                @"showTooltips",
                                @"maxLogDisplaySize",
                                @"lastConnectedDisplayName",
                                @"installationUID",
                                @"keyboardShortcutIndex",
                                @"doNotUnrebrandLicenseDescription",
                                @"useSharedConfigurationsWithDeployedOnes",
                                @"usePrivateConfigurationsWithDeployedOnes",
								@"namedCredentialsThatAllConfigurationsUse",
                                @"namedCredentialsNames",
                                
                                @"delayToShowStatistics",
                                @"delayToHideStatistics",
                                @"statisticsRateTimeInterval",
                                
                                @"updateAutomatically",
                                @"updateCheckAutomatically",
                                @"updateCheckInterval",
                                @"updateFeedURL",
                                @"updateSendProfileInfo",
                                @"updateSigned",
                                @"updateUnsigned",
                                @"updateUUID",

                                @"NSWindow Frame SettingsSheetWindow",
                                @"NSWindow Frame ConnectingWindow",
                                @"NSWindow Frame SUStatusFrame",
                                @"detailsWindowFrameVersion",
                                @"detailsWindowFrame",
                                @"detailsWindowLeftFrame",
								@"leftNavOutlineViewExpandedDisplayNames",
								@"leftNavSelectedDisplayName",
                                
                                @"haveDealtWithSparkle1dot5b6",
                                
                                @"SUEnableAutomaticChecks",
                                @"SUFeedURL",
                                @"SUScheduledCheckInterval",
                                @"SUSendProfileInfo",
                                @"SUAutomaticallyUpdate",
                                @"SULastCheckTime",
                                @"SULastProfileSubmissionDate",
                                @"SUHasLaunchedBefore",
                                @"SUSkippedVersion",
                                
                                
                                @"WebKitDefaultFontSize",
                                @"WebKitStandardFont",
                                
                                @"ApplicationCrashedAfterRelaunch",
                                
                                // No longer used
                                @"doNotShowCheckForUpdatesNowMenuItem",
                                @"doNotShowForcedPreferenceMenuItems",
                                @"doNotShowKeyboardShortcutSubmenu",
                                @"doNotShowOptionsSubmenu",
                                @"keyboardShortcutKeyCode",
                                @"keyboardShortcutModifiers",
                                @"maximumLogSize",
                                
                                nil] retain];
        
        gConfigurationPreferences = [[NSArray arrayWithObjects:
                                      @"-skipWarningAboutDownroot",
                                      @"-skipWarningAboutNoTunOrTap",
                                      @"-skipWarningUnableToToEstablishOpenVPNLink",
                                      
                                      @"autoConnect",
                                      @"-onSystemStart",
                                      @"useDNS",
                                      @"-notMonitoringConnection",
                                      @"-doNotRestoreOnDnsReset",
                                      @"-doNotRestoreOnWinsReset",
                                      @"-leasewatchOptions",
                                      @"-doNotDisconnectOnFastUserSwitch",
                                      @"-doNotReconnectOnFastUserSwitch",
                                      @"-doNotReconnectOnWakeFromSleep",
                                      @"-resetPrimaryInterfaceAfterDisconnect",
                                      @"-routeAllTrafficThroughVpn",
                                      @"-doNotFlushCache",
                                      @"-useDownRootPlugin",
                                      @"-keychainHasPrivateKey",
                                      @"-keychainHasUsernameAndPassword",
                                      @"-doNotParseConfigurationFile",
                                      @"-disableEditConfiguration",
                                      @"-disableConnectButton",
                                      @"-disableDisconnectButton",
                                      @"-doNotLoadTapKext",
                                      @"-doNotLoadTunKext",
                                      @"-loadTapKext",
                                      @"-loadTunKext",
                                      @"-credentialsGroup",
									  
                                      @"-changeDNSServersAction",
                                      @"-changeDomainAction",
                                      @"-changeSearchDomainAction",
                                      @"-changeWINSServersAction",
                                      @"-changeNetBIOSNameAction",
                                      @"-changeWorkgroupAction",
                                      @"-changeOtherDNSServersAction",
                                      @"-changeOtherDomainAction",
                                      @"-changeOtherSearchDomainAction",
                                      @"-changeOtherWINSServersAction",
                                      @"-changeOtherNetBIOSNameAction",
                                      @"-changeOtherWorkgroupAction",
                                      @"-lastConnectionSucceeded",
                                      @"-tunnelDownSoundName",
                                      @"-tunnelUpSoundName",
                                      @"-doNotDisconnectWhenTunnelblickQuits",
                                      @"-prependDomainNameToSearchDomains",
                                      @"-doNotReconnectOnUnexpectedDisconnect", // This preference is NOT IMPLEMENTED and it is not in the .xib

                                      @"-doNotShowOnTunnelblickMenu",
                                      
                                      // No longer used
                                      @"-authUsername",
                                      @"-usernameIsSet",
                                      nil] retain];
        
        // If this is the first time we are using the new CFBundleIdentifier
        //    Rename the old preferences so we can access them with the new CFBundleIdentifier
        //    And create a link to the new preferences from the old preferences (make the link read-only)
        if (  [[[NSBundle mainBundle] bundleIdentifier] isEqualToString: @"net.tunnelblick.tunnelblick"]  ) {
            NSString * oldPreferencesPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/com.openvpn.tunnelblick.plist"];
            NSString * newPreferencesPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/net.tunnelblick.tunnelblick.plist"];
            if (  ! [gFileMgr fileExistsAtPath: newPreferencesPath]  ) {
                if (  [gFileMgr fileExistsAtPath: oldPreferencesPath]  ) {
                    if (  [gFileMgr tbMovePath: oldPreferencesPath toPath: newPreferencesPath handler: nil]  ) {
                        NSLog(@"Renamed existing preferences from %@ to %@", [oldPreferencesPath lastPathComponent], [newPreferencesPath lastPathComponent]);
                        if (  [gFileMgr tbCreateSymbolicLinkAtPath: oldPreferencesPath
                                                       pathContent: newPreferencesPath]  ) {
                            NSLog(@"Created a symbolic link from old preferences at %@ to %@", oldPreferencesPath, [newPreferencesPath lastPathComponent]);
							if (  lchmod([oldPreferencesPath fileSystemRepresentation], S_IRUSR+S_IRGRP+S_IROTH) == EXIT_SUCCESS  ) {
								NSLog(@"Made the symbolic link read-only at %@", oldPreferencesPath);
							} else {
								NSLog(@"Warning: Unable to make the symbolic link read-only at %@", oldPreferencesPath);
							}
                        } else {
                            NSLog(@"Warning: Unable to create a symbolic link from the old preferences at %@ to the new preferences %@", oldPreferencesPath, [newPreferencesPath lastPathComponent]);
                        }
                    } else {
                        NSLog(@"Warning: Unable to rename old preferences at %@ to %@", oldPreferencesPath, [newPreferencesPath lastPathComponent]);
                    }
                }
            }
        }
            
        // Create a symbolic link to the private configurations folder, after having run the installer (which may have moved the
        // configuration folder contents to the new place)
        [self makeSymbolicLink];
        
        // Set up to override user preferences from Deploy/forced-permissions.plist if it exists,
        NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: [gDeployPath stringByAppendingPathComponent: @"forced-preferences.plist"]];
        gTbDefaults = [[TBUserDefaults alloc] initWithForcedDictionary: dict
                                                andSecondaryDictionary: nil
                                                     usingUserDefaults: YES];
        
        if (  ! [gTbDefaults boolForKey: @"doNotShowSplashScreen"]  ) {
            splashScreen = [[SplashWindowController alloc] init];
            NSString * text = NSLocalizedString(@"Starting Tunnelblick...", @"Window text");
            [splashScreen setMessage: text];
            [splashScreen showWindow: self];
        }
		
        // Set default preferences as needed
        if (  [gTbDefaults objectForKey: @"showConnectedDurations"] == nil  ) {
            [gTbDefaults setBool: TRUE forKey: @"showConnectedDurations"];
        }
        
		// Scan for unknown preferences
        NSString * bundleId = [[NSBundle mainBundle] bundleIdentifier];
        NSString * prefsPath = [[[[NSHomeDirectory()
                                   stringByAppendingPathComponent:@"Library"]
                                  stringByAppendingPathComponent:@"Preferences"]
                                 stringByAppendingPathComponent: bundleId]
                                stringByAppendingPathExtension: @"plist"];
        dict = [NSDictionary dictionaryWithContentsOfFile: prefsPath];
        [gTbDefaults scanForUnknownPreferencesInDictionary: dict displayName: @"Preferences"];
        
        // Check that we can run Tunnelblick from this volume, that it is in /Applications, and that it is secured
        [self initialChecks: ourAppName];    // WE MAY NOT RETURN FROM THIS METHOD (it may install a new copy of Tunnelblick, launch it, and quit)
		
        // If gDeployPath exists and has one or more .tblk packages or .conf or .ovpn files,
        // Then make it the first entry in gConfigDirs
        BOOL isDir;
        if (   [gFileMgr fileExistsAtPath: gDeployPath isDirectory: &isDir]
            && isDir ) {
            NSString * file;
            NSDirectoryEnumerator *dirEnum = [gFileMgr enumeratorAtPath: gDeployPath];
            while (  (file = [dirEnum nextObject])  ) {
                NSString * path = [gDeployPath stringByAppendingPathComponent: file];
                if (  itemIsVisible(path)  ) {
                    NSString * ext  = [file pathExtension];
                    if (   [gFileMgr fileExistsAtPath: path isDirectory: &isDir]
                        && ( ! isDir)  ) {
                        if ( [ext isEqualToString:@"conf"] || [ext isEqualToString:@"ovpn"]  ) {
                            [gConfigDirs addObject: gDeployPath];
                            break;
                        }
                    } else {
                        if ( [ext isEqualToString:@"tblk"]  ) {
                            [gConfigDirs addObject: gDeployPath];
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
            [gConfigDirs addObject: L_AS_T_SHARED];
            [gConfigDirs addObject: [[gPrivatePath copy] autorelease]];
        } else {
            if (  ! [gTbDefaults canChangeValueForKey: @"useSharedConfigurationsWithDeployedOnes"]  ) {
                if (  [gTbDefaults boolForKey: @"useSharedConfigurationsWithDeployedOnes"]  ) {
                    [gConfigDirs addObject: L_AS_T_SHARED];
                }
            }
            if (  ! [gTbDefaults canChangeValueForKey: @"usePrivateConfigurationsWithDeployedOnes"]  ) {
                if (  [gTbDefaults boolForKey: @"usePrivateConfigurationsWithDeployedOnes"]  ) {
                    [gConfigDirs addObject: [[gPrivatePath copy] autorelease]];
                }
            }
        }
        
        gMaximumLogSize = [gTbDefaults unsignedIntForKey: @"maxLogDisplaySize"
                                                 default: DEFAULT_LOG_SIZE_BYTES
                                                     min: MIN_LOG_SIZE_BYTES
                                                     max: MAX_LOG_SIZE_BYTES];
        
		id obj;
        if (   (obj = [gTbDefaults objectForKey: @"delayToShowStatistics"])
            && [obj respondsToSelector: @selector(doubleValue)]  ) {
            gDelayToShowStatistics = [obj doubleValue];
        } else {
            gDelayToShowStatistics = 0.5;
        }
        if (   (obj = [gTbDefaults objectForKey: @"delayToHideStatistics"])
            && [obj respondsToSelector: @selector(doubleValue)]  ) {
            gDelayToHideStatistics = [obj doubleValue];
        } else {
            gDelayToHideStatistics = 1.5;
        }
        
        gRateUnits = [[NSArray arrayWithObjects:
                       NSLocalizedString(@"B/s", @"Window text"),
                       NSLocalizedString(@"KB/s", @"Window text"),
                       NSLocalizedString(@"MB/s", @"Window text"),
                       NSLocalizedString(@"GB/s", @"Window text"),
                       NSLocalizedString(@"TB/s", @"Window text"),
                       NSLocalizedString(@"PB/s", @"Window text"),
                       NSLocalizedString(@"EB/s", @"Window text"),
                       NSLocalizedString(@"ZB/s", @"Window text"),
                       @"***",
                       nil] retain];
        
        gTotalUnits = [[NSArray arrayWithObjects:
                        NSLocalizedString(@"B", @"Window text"),
                        NSLocalizedString(@"KB", @"Window text"),
                        NSLocalizedString(@"MB", @"Window text"),
                        NSLocalizedString(@"GB", @"Window text"),
                        NSLocalizedString(@"TB", @"Window text"),
                        NSLocalizedString(@"PB", @"Window text"),
                        NSLocalizedString(@"EB", @"Window text"),
                        NSLocalizedString(@"ZB", @"Window text"),
                        @"***",
                        nil] retain];
		
        connectionArray = [[NSArray alloc] init];
        
        if (  ! [self loadMenuIconSet]  ) {
            NSLog(@"Unable to load the Menu icon set");
            [self terminateBecause: terminatingBecauseOfError];
        }
        
		[self createStatusItem];
		
        myConfigDictionary = [[[ConfigurationManager defaultManager] getConfigurations] copy];
        
        // set up myVPNConnectionDictionary, which has the same keys as myConfigDictionary, but VPNConnections as objects
        NSMutableDictionary * tempVPNConnectionDictionary = [[NSMutableDictionary alloc] init];
        NSString * dispNm;
        NSEnumerator * e = [myConfigDictionary keyEnumerator];
        while (  (dispNm = [e nextObject])  ) {
            NSString * cfgPath = [[self myConfigDictionary] objectForKey: dispNm];
            // configure connection object:
            VPNConnection* myConnection = [[VPNConnection alloc] initWithConfigPath: cfgPath
                                                                    withDisplayName: dispNm];
            [myConnection setDelegate:self];
            [tempVPNConnectionDictionary setObject: myConnection forKey: dispNm];
        }
        [self setMyVPNConnectionDictionary: [[tempVPNConnectionDictionary copy] autorelease]];
        [tempVPNConnectionDictionary release];
        
		[self createMenu];
        
        // logScreen is a MyPrefsWindowController, but the sharedPrefsWindowController is a DBPrefsWindowController
        logScreen = (id) [MyPrefsWindowController sharedPrefsWindowController];
        
        [self setState: @"EXITING"]; // synonym for "Disconnected"
        
        [[NSNotificationCenter defaultCenter] addObserver: self 
                                                 selector: @selector(TunnelblickShutdownUIHandler:) 
                                                     name: @"TunnelblickUIShutdownNotification" 
                                                   object: nil];
        
        [[NSNotificationCenter defaultCenter] addObserver: logScreen 
                                                 selector: @selector(logNeedsScrollingHandler:) 
                                                     name: @"LogDidChange" 
                                                   object: nil];
		
		
        // In case the systemUIServer restarts, we observed this notification.
		// We use it to prevent ending up with a statusItem to the right of Spotlight:
		[[NSDistributedNotificationCenter defaultCenter] addObserver: self 
															selector: @selector(menuExtrasWereAddedHandler:) 
																name: @"com.apple.menuextra.added" 
															  object: nil];
        
        // These notifications are seen when the user is logging out or the system is being shut down or restarted.
        //
        // They are seen *before* getting the workspace's NSWorkspaceWillPowerOffNotification and used to track
        // whether this is a logout, or a shutdown or restart, and set 'reasonForTermination' if appropriate.
        //
        // When a logout is requested: com.apple.logoutInitiated
        //                  confirmed: com.apple.logoutContinued
        //                  cancelled: com.apple.logoutCancelled
        //
        // When a restart is requested: com.apple.restartInitiated
        //                   confirmed: com.apple.logoutContinued
        //                   cancelled: com.apple.logoutCancelled
        //
        // When a shutdown is requested: com.apple.shutdownInitiated
        //                    confirmed: com.apple.logoutContinued
        //                    cancelled: com.apple.logoutCancelled
        
		[[NSDistributedNotificationCenter defaultCenter] addObserver: self 
															selector: @selector(restartInitiatedHandler:) 
																name: @"com.apple.restartInitiated" 
															  object: nil];
        
		[[NSDistributedNotificationCenter defaultCenter] addObserver: self 
															selector: @selector(logoutInitiatedHandler:) 
																name: @"com.apple.logoutInitiated" 
															  object: nil];
        
		[[NSDistributedNotificationCenter defaultCenter] addObserver: self 
															selector: @selector(shutdownInitiatedHandler:) 
																name: @"com.apple.shutdownInitiated" 
															  object: nil];
        
        [[NSDistributedNotificationCenter defaultCenter] addObserver: self 
															selector: @selector(logoutCancelledHandler:) 
																name: @"com.apple.logoutCancelled" 
															  object: nil];
        
		[[NSDistributedNotificationCenter defaultCenter] addObserver: self 
															selector: @selector(logoutContinuedHandler:) 
																name: @"com.apple.logoutContinued" 
															  object: nil];
        
        
		[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
															   selector: @selector(willGoToSleepHandler:)
																   name: NSWorkspaceWillSleepNotification
																 object:nil];
		
		[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
															   selector: @selector(willLogoutOrShutdownHandler:)
																   name: NSWorkspaceWillPowerOffNotification
																 object:nil];
		
		[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
															   selector: @selector(wokeUpFromSleepHandler:)
																   name: NSWorkspaceDidWakeNotification
																 object:nil];
		
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                               selector: @selector(didBecomeActiveUserHandler:)
                                                                   name: NSWorkspaceSessionDidBecomeActiveNotification
                                                                 object: nil];
        
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                               selector: @selector(didBecomeInactiveUserHandler:)
                                                                   name: NSWorkspaceSessionDidResignActiveNotification
                                                                 object: nil];
        
        if (  [gTbDefaults boolForKey: @"notificationsLog"] ) {
            
            NSLog(@"Observing all notifications");
            
            [[NSDistributedNotificationCenter defaultCenter] addObserver: self 
                                                                selector: @selector(allDistributedNotificationsHandler:) 
                                                                    name: nil 
                                                                  object: nil];
            
            [[NSNotificationCenter defaultCenter] addObserver: self 
                                                     selector: @selector(allNotificationsHandler:) 
                                                         name: nil 
                                                       object: nil];        
            
            [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self 
                                                                   selector: @selector(allWorkspaceNotificationsHandler:) 
                                                                       name: nil 
                                                                     object: nil];
        }
        
        ignoreNoConfigs = TRUE;    // We ignore the "no configurations" situation until we've processed application:openFiles:
		
        updater = [[SUUpdater alloc] init];
        myConfigUpdater = [[ConfigurationUpdater alloc] init]; // Set up a separate Sparkle Updater for configurations   
    }
    
    return self;
}

-(void)allNotificationsHandler: (NSNotification *) n
{
    NSString * name = [n name];
    NSLog(@"NOTIFICATION              : %@", name);
    if (  [name isEqualToString: [gTbDefaults objectForKey: @"notificationsVerbose"]]  ) {
        NSLog(@"NOTIFICATION              : %@; object = %@; userInfo = %@", [n name], [n object], [n userInfo]);
    }
}

-(void)allDistributedNotificationsHandler: (NSNotification *) n
{
    NSString * name = [n name];
    NSLog(@"NOTIFICATION (Distributed): %@", name);
    if (  [name isEqualToString: [gTbDefaults objectForKey: @"notificationsVerbose"]]  ) {
        NSLog(@"NOTIFICATION (Distributed): %@; object = %@; userInfo = %@", [n name], [n object], [n userInfo]);
    }
}

-(void)allWorkspaceNotificationsHandler: (NSNotification *) n
{
    NSString * name = [n name];
    NSLog(@"NOTIFICATION   (Workspace): %@", name);
    if (  [name isEqualToString: [gTbDefaults objectForKey: @"notificationsVerbose"]]  ) {
        NSLog(@"NOTIFICATION   (Workspace): %@; object = %@; userInfo = %@", [n name], [n object], [n userInfo]);
    }
}

// Attempts to make a symbolic link from the old configurations folder to the new configurations folder
- (void) makeSymbolicLink
{
    BOOL isDir;
    NSString * oldConfigDirPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/openvpn"];
    NSDictionary * fileAttributes = [gFileMgr tbFileAttributesAtPath: oldConfigDirPath traverseLink: NO];
    if (  [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
        // A symbolic link exists
        if (  ! [[gFileMgr tbPathContentOfSymbolicLinkAtPath: oldConfigDirPath] isEqualToString: gPrivatePath]  ) {
            NSLog(@"Warning: %@ exists and is a symbolic link but does not reference %@. Attempting repair...", oldConfigDirPath, gPrivatePath);
            if (  ! [gFileMgr tbRemoveFileAtPath:oldConfigDirPath handler: nil]  ) {
                NSLog(@"Warning: Unable to remove %@", oldConfigDirPath);
            }
            if (  ! [gFileMgr tbCreateSymbolicLinkAtPath: oldConfigDirPath
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
                while (  (file = [dirEnum nextObject])  ) {
                    if (  itemIsVisible([oldConfigDirPath stringByAppendingPathComponent: file])  ) {
                        isEmpty = FALSE;
                        break;
                    }
                }
                if (  isEmpty  ) {
                    if (  [gFileMgr tbRemoveFileAtPath:oldConfigDirPath handler: nil]  ) {
                        if (  [gFileMgr tbCreateSymbolicLinkAtPath: oldConfigDirPath
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
            if (  [gFileMgr tbCreateSymbolicLinkAtPath: oldConfigDirPath
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
    [showDurationsTimer release];
    [animImages release];
    [connectedImage release];
    [mainImage release];
    
    [gConfigDirs release];
    
    [gTbDefaults release];
    [connectionArray release];
    [connectionsToRestoreOnWakeup release];
    [connectionsToRestoreOnUserActive release];
    [dotTblkFileList release];
    [lastState release];
    [gPrivatePath release];
    [myConfigDictionary release];
    [myVPNConnectionDictionary release];
    [myVPNMenu release];
    [hookupWatchdogTimer invalidate];
    [hookupWatchdogTimer release];
    [theAnim release];
    [updater release];
    [myConfigUpdater release];
    [customMenuScripts release];
    [customRunOnLaunchPath release];
    [customRunOnConnectPath release];
    
    [aboutItem release];
    [checkForUpdatesNowItem release];
    [vpnDetailsItem release];
    [quitItem release];
    [statusMenuItem release];
    [statusItem release];
    [logScreen release];
    [welcomeScreen release];
    
#ifdef INCLUDE_VPNSERVICE
    [vpnService release];
    [registerForTunnelblickItem release];
#endif
    
    [super dealloc];
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
    [statusItem release];
    statusItem = nil;
    
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
        if (  statusItem  ) {
            [bar removeStatusItem: statusItem];
            [statusItem release];
            if (  (statusItem = [[bar statusItemWithLength: NSVariableStatusItemLength] retain])  ) {
            } else {
                NSLog(@"Can't insert icon in Status Bar");
            }
        } else {
            if (  ! (statusItem = [[bar statusItemWithLength: NSVariableStatusItemLength] retain])  ) {
                NSLog(@"Can't insert icon in Status Bar");
            }
        }
    }
}

- (void) menuExtrasWereAddedHandler: (NSNotification*) n
{
	(void) n;
	
    NSLog(@"DEBUG: menuExtrasWereAddedHandler: invoked");
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
	[self performSelectorOnMainThread: @selector(menuExtrasWereAdded) withObject: nil waitUntilDone: NO];
}

- (void) menuExtrasWereAdded
{
    [self createStatusItem];
    [self createMenu];
    [self updateUI];
}

- (IBAction) quit: (id) sender
{
	(void) sender;
	
    [self terminateBecause: terminatingBecauseOfQuit];
}

-(BOOL) terminatingAtUserRequest
{
    return terminatingAtUserRequest;
}

- (void) awakeFromNib
{
	[self initialiseAnim];
}

-(BOOL) loadMenuIconSet
{
    // Try with the specified icon set
    NSString * requestedMenuIconSet = [gTbDefaults objectForKey:@"menuIconSet"];
    if (  requestedMenuIconSet   ) {
        NSString * requestedLargeIconSet = [NSString stringWithFormat: @"large-%@", requestedMenuIconSet];
        if (  [self loadMenuIconSet: requestedMenuIconSet
                               main: &mainImage
                         connecting: &connectedImage
                               anim: &animImages]  ) {
            if (  [self loadMenuIconSet: requestedLargeIconSet
                                   main: &mainImage
                             connecting: &connectedImage
                                   anim: &animImages]  ) {
                [self updateUI];    // Display the new images
                return YES;
            } else {
                NSLog(@"Icon set '%@' not found", requestedLargeIconSet);
            }
        } else {
            if (  [self loadMenuIconSet: requestedLargeIconSet
                                   main: &mainImage
                             connecting: &connectedImage
                                   anim: &animImages]  ) {
                NSLog(@"Icon set '%@' not found", requestedMenuIconSet);
            } else {
                NSLog(@"Icon set '%@' not found and icon set '%@' not found", requestedMenuIconSet, requestedLargeIconSet);
            }
        }
    }
    
    // Try with standard icon set if haven't already
    NSString * menuIconSet = @"TunnelBlick.TBMenuIcons";
    if (  ! [requestedMenuIconSet isEqualToString: menuIconSet]  ) {
        if (   [self loadMenuIconSet: menuIconSet
                                main: &mainImage
                          connecting: &connectedImage
                                anim: &animImages]
            && [self loadMenuIconSet: [NSString stringWithFormat: @"large-%@", menuIconSet]
                                main: &largeMainImage
                          connecting: &largeConnectedImage
                                anim: &largeAnimImages]  )
        {
            if (  requestedMenuIconSet  ) {
                NSLog(@"Using icon set %@", menuIconSet);
            }
            [self updateUI];    // Display the new images
            return YES;
        } else {
            NSLog(@"Icon set '%@' not found", menuIconSet);
        }
    }
        
    // Try with monochrome icon set
    menuIconSet = @"TunnelBlick-black-white.TBMenuIcons";
    if (   [self loadMenuIconSet: menuIconSet
                            main: &mainImage
                      connecting: &connectedImage
                            anim: &animImages]
        && [self loadMenuIconSet: [NSString stringWithFormat: @"large-%@", menuIconSet]
                            main: &largeMainImage
                      connecting: &largeConnectedImage
                            anim: &largeAnimImages]  )
    {
        NSLog(@"Using icon set %@", menuIconSet);
        [self updateUI];    // Display the new images
        return YES;
    }
    
    return NO;
}
    
-(BOOL) loadMenuIconSet: (NSString *)        iconSetName
                   main: (NSImage **)        ptrMainImage
             connecting: (NSImage **)        ptrConnectedImage
                   anim: (NSMutableArray **) ptrAnimImages
{
    // Search for the folder with the animated icon set in (1) Deploy and (2) Shared, before falling back on the copy in the app's Resources
    BOOL isDir;
    NSString * iconSetDir = [[gDeployPath stringByAppendingPathComponent: @"IconSets"] stringByAppendingPathComponent: iconSetName];
    if (  ! (   [gFileMgr fileExistsAtPath: iconSetDir isDirectory: &isDir]
             && isDir )  ) {
        iconSetDir = [[L_AS_T_SHARED stringByAppendingPathComponent: @"IconSets"] stringByAppendingPathComponent: iconSetName];
        if (  ! (   [gConfigDirs containsObject: L_AS_T_SHARED]
                 && [gFileMgr fileExistsAtPath: iconSetDir isDirectory: &isDir]
                 && isDir )  ) {
            iconSetDir = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"IconSets"] stringByAppendingPathComponent: iconSetName];
            if (  ! (   [gFileMgr fileExistsAtPath: iconSetDir isDirectory: &isDir]
                     && isDir )  ) {
                // Can't find the specified icon set
                return FALSE;
            }
        }
    }
    
    unsigned nFrames = 0;
    NSString *file;
    NSString *fullPath;
    NSDirectoryEnumerator *dirEnum = [gFileMgr enumeratorAtPath: iconSetDir];
    NSArray *allObjects = [dirEnum allObjects];
    
    [*ptrAnimImages release];
    *ptrAnimImages = [[NSMutableArray alloc] init];
    
    unsigned i=0;
    for(i=0;i<[allObjects count];i++) {
        file = [allObjects objectAtIndex:i];
        fullPath = [iconSetDir stringByAppendingPathComponent:file];
        
        if (  itemIsVisible(fullPath)  ) {
            if ([[file pathExtension] isEqualToString: @"png"]) {
                NSString *name = [[file lastPathComponent] stringByDeletingPathExtension];
                
                if (  [name isEqualToString:@"closed"]) {
                    [*ptrMainImage release];
                    *ptrMainImage = [[NSImage alloc] initWithContentsOfFile:fullPath];
                    
                } else if(  [name isEqualToString:@"open"]) {
                    [*ptrConnectedImage release];
                    *ptrConnectedImage = [[NSImage alloc] initWithContentsOfFile:fullPath];
                    
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
        fullPath = [iconSetDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.png", i]];
        if (  itemIsVisible(fullPath)  ) {
            if ([gFileMgr fileExistsAtPath:fullPath]) {
                NSImage *frame = [[NSImage alloc] initWithContentsOfFile:fullPath];
                [*ptrAnimImages addObject:frame];
                [frame release];
            }
        }
    }
    
    if (   (*ptrMainImage == nil)
        || (*ptrConnectedImage == nil)
        || ([*ptrAnimImages count] == 0)  ) {
        NSLog(@"Icon set '%@' does not have required images", iconSetName);
        return FALSE;
    }
    
    return TRUE;
}

- (void) initialiseAnim
{
    if (  gShuttingDownWorkspace  ) {
        [theAnim stopAnimation];
        return;
    }
    
    if (  theAnim == nil  ) {
        unsigned i;
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
}

// Lock this to change myVPNMenu
static pthread_mutex_t myVPNMenuMutex = PTHREAD_MUTEX_INITIALIZER;

-(void) createMenu 
{
    OSStatus status = pthread_mutex_lock( &myVPNMenuMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &myVPNMenuMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    
    [noConfigurationsItem release];
    noConfigurationsItem = [[NSMenuItem alloc] init];
    [noConfigurationsItem setTitle: NSLocalizedString(@"No VPN Configurations Available", @"Menu item")];
    
#ifdef INCLUDE_VPNSERVICE
    [registerForTunnelblickItem release];
    registerForTunnelblickItem = [[NSMenuItem alloc] init];
    [registerForTunnelblickItem setTitle: NSLocalizedString(@"Register for Tunnelblick...", @"Menu item VPNService")];
    [registerForTunnelblickItem setTarget: self];
    [registerForTunnelblickItem setAction: @selector(registerForTunnelblickWasClicked:)];
#endif
    
    if (  ! [gTbDefaults boolForKey:@"doNotShowAddConfigurationMenuItem"]  ) {
        [addConfigurationItem release];
        addConfigurationItem = [[NSMenuItem alloc] init];
        [addConfigurationItem setTitle: NSLocalizedString(@"Add a VPN...", @"Menu item")];
        [addConfigurationItem setTarget: self];
        [addConfigurationItem setAction: @selector(addConfigurationWasClicked:)];
    }
    
    [vpnDetailsItem release];
    vpnDetailsItem = [[NSMenuItem alloc] init];
    [vpnDetailsItem setTitle: NSLocalizedString(@"VPN Details...", @"Menu item")];
    [vpnDetailsItem setTarget: self];
    [vpnDetailsItem setAction: @selector(openPreferencesWindow:)];
    
    [contactTunnelblickItem release];
    contactTunnelblickItem = nil;
/*
    if ( ! [gTbDefaults boolForKey: @"doNotShowSuggestionOrBugReportMenuItem"]  ) {
        if (  [self contactURL]  ) {
            NSString * menuTitle = nil;
            NSDictionary * infoPlist = [[NSBundle mainBundle] infoDictionary];
            if (  [[infoPlist objectForKey: @"CFBundleShortVersionString"] rangeOfString: @"beta"].length != 0  ) {
                if (  [NSLocalizedString(@"Tunnelblick", "Window title") isEqualToString: @"Tunnel" "blick"]  ) {
                    if (  [@"Tunnelblick" isEqualToString: @"Tunnel" "blick"]  ) {
                        menuTitle = NSLocalizedString(@"Suggestion or Bug Report...", @"Menu item");
                    }
                }
            }
            if (  menuTitle  ) {
                contactTunnelblickItem = [[NSMenuItem alloc] init];
                [contactTunnelblickItem setTitle: menuTitle];
                [contactTunnelblickItem setTarget: self];
                [contactTunnelblickItem setAction: @selector(contactTunnelblickWasClicked:)];
            }
        }
    }
 */
    
    [quitItem release];
    quitItem = [[NSMenuItem alloc] init];
    [quitItem setTitle: NSLocalizedString(@"Quit Tunnelblick", @"Menu item")];
    [quitItem setTarget: self];
    [quitItem setAction: @selector(quit:)];
    
    [statusMenuItem release];
	statusMenuItem = [[NSMenuItem alloc] init];
    [statusMenuItem setTarget: self];
    [statusMenuItem setAction: @selector(disconnectAllMenuItemWasClicked:)];
    
    [myVPNMenu release];
	myVPNMenu = [[NSMenu alloc] init];
    [myVPNMenu setDelegate:self];

    [self setOurMainIconView: [[[MainIconView alloc] initWithFrame: NSMakeRect(0.0, 0.0, 20.0, 23.0)] autorelease]];
    [statusItem setView: [self ourMainIconView]];
    
	[myVPNMenu addItem:statusMenuItem];
	
    [myVPNMenu addItem:[NSMenuItem separatorItem]];
    
    // Add each connection to the menu
    NSString * dispNm;
    NSArray *keyArray = [[[self myConfigDictionary] allKeys]
						 sortedArrayUsingSelector: @selector(caseInsensitiveNumericCompare:)];
	NSEnumerator * e = [keyArray objectEnumerator];
    while (  (dispNm = [e nextObject])  ) {
        if (  ! [gTbDefaults boolForKey: [dispNm stringByAppendingString: @"-doNotShowOnTunnelblickMenu"]]  ) {
            // configure connection object:
            NSMenuItem *connectionItem = [[[NSMenuItem alloc] init] autorelease];
            VPNConnection* myConnection = [[self myVPNConnectionDictionary] objectForKey: dispNm];
            
            // Note: The menu item's title will be set on demand in VPNConnection's validateMenuItem
            [connectionItem setTarget:myConnection]; 
            [connectionItem setAction:@selector(toggle:)];
            
            [self insertConnectionMenuItem: connectionItem IntoMenu: myVPNMenu afterIndex: 2 withName: dispNm];
        }
    }
    
    if (  [[self myConfigDictionary] count] == 0  ) {
        [myVPNMenu addItem: noConfigurationsItem];
        if (  ! [gTbDefaults boolForKey:@"doNotShowAddConfigurationMenuItem"]  ) {
            [myVPNMenu addItem: addConfigurationItem];
        }
    }
    
    [myVPNMenu addItem: [NSMenuItem separatorItem]];
    
#ifdef INCLUDE_VPNSERVICE
    if (  registerForTunnelblickItem  ) {
        [myVPNMenu addItem: registerForTunnelblickItem];
        [myVPNMenu addItem: [NSMenuItem separatorItem]];
    }
#endif

    [self addCustomMenuItems];

    if (  contactTunnelblickItem  ) {
        [myVPNMenu addItem: contactTunnelblickItem];
        [myVPNMenu addItem: [NSMenuItem separatorItem]];
    }
    
    if (  ! [gTbDefaults boolForKey:@"doNotShowVpnDetailsMenuItem"]  ) {
        [myVPNMenu addItem: vpnDetailsItem];
        [myVPNMenu addItem: [NSMenuItem separatorItem]];
	}
    
    [myVPNMenu addItem: quitItem];
    
    status = pthread_mutex_unlock( &myVPNMenuMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &myVPNMenuMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
    }
}

// LOCK configModifyMutex BEFORE INVOKING THIS METHOD
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
            } else if (  [[menuItem title] isEqualToString: NSLocalizedString(@"Add a VPN...", @"Menu item")]  ) {
                break;
            } else {                                                            // item is a connection item
                menuItemTitle = [[menuItem target] displayName];
            }
            
			menuItemTitle = [menuItemTitle lastPathComponent];
            if (  [menuItemTitle compare: theName options: NSCaseInsensitiveSearch | NSNumericSearch] == NSOrderedDescending  ) {
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
                NSComparisonResult  result = [menuItemTitle compare: subMenuName options: NSCaseInsensitiveSearch | NSNumericSearch];
                if (  result == NSOrderedSame  ) {
                    // Have found correct submenu, so add this item to it
					int nItemsInMenu = [subMenu numberOfItems] - 1;
					if (  nItemsInMenu < 0  ) {
						nItemsInMenu = 0;
					}
                    [self insertConnectionMenuItem: theItem IntoMenu: subMenu afterIndex: nItemsInMenu withName: restOfName];
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
    NSMenuItem * newMenuItem = [[[NSMenuItem alloc] init] autorelease];
    [newMenuItem setTitle: subMenuName];
    [newMenuItem setSubmenu: newSubmenu];
    
    // Add the new submenu item to the outer menu
    [self insertConnectionMenuItem: newMenuItem IntoMenu: theMenu afterIndex: theIndex withName: subMenuName];
    
    // Insert the original item we wanted to (now that the submenu has been created)
    [self insertConnectionMenuItem: theItem IntoMenu: theMenu afterIndex: theIndex withName: theName];
}

-(void) addCustomMenuItems
{
    // Reset custom script variables
    customMenuScriptIndex = 0;
    [customMenuScripts release];
    customMenuScripts = [[NSMutableArray alloc] init];
    
    // Process the contents of the Menu folder
    NSString * menuDirPath = [gDeployPath stringByAppendingPathComponent: @"Menu"];
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
    while (  (file = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        [itemsInMenuFolder addObject: file];
    }
    
    // Sort the list
	NSArray *sortedArray = [itemsInMenuFolder sortedArrayUsingSelector: @selector(caseInsensitiveNumericCompare:)];

    // Use the sorted list to add items to the Tunnelblick menu, or to run them on launch or on connect
    BOOL haveAddedItems = FALSE;
    BOOL isDir;
    
    unsigned i;
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
        [subMenuItem setTitle: localizeNonLiteral([self menuNameFromFilename: file], @"Menu item")];
        [subMenuItem setSubmenu: subMenu];
        [theMenu addItem: subMenuItem];
        return TRUE;
    }
    
    return FALSE;
}

-(void) addOneCustomMenuItem: (NSString *) file fromFolder: (NSString *) folder toMenu: (NSMenu *) theMenu
{
    NSMenuItem * item = [[[NSMenuItem alloc] init] autorelease];
    [item setTitle: localizeNonLiteral([self menuNameFromFilename: file], @"Menu item")];
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
    if (  tag < 0  ) {
        NSLog(@"runCustomMenuItem: tag %d is < 0", tag);
    }
    NSString * scriptPath = [customMenuScripts objectAtIndex: (unsigned)tag];
    NSTask* task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath: scriptPath];
	[task setArguments: [NSArray array]];
	[task setCurrentDirectoryPath: [scriptPath stringByDeletingLastPathComponent]];
	[task launch];
    if (  [[[scriptPath stringByDeletingPathExtension] pathExtension] isEqualToString: @"wait"]) {
        [task waitUntilExit];
    }
}

-(void) changedDisplayConnectionSubmenusSettings
{
    [self createStatusItem];
    [self createMenu];
    [self updateUI];
}

-(void) removeConnectionWithDisplayName: (NSString *) theName
                               fromMenu: (NSMenu *)   theMenu
                             afterIndex: (int)        theIndex
{
    [self removeConnectionWithDisplayName: theName fromMenu: theMenu afterIndex: theIndex workingName: [[theName copy] autorelease]];
}

-(void) removeConnectionWithDisplayName: (NSString *) theName
                               fromMenu: (NSMenu *)   theMenu
                             afterIndex: (int)        theIndex
                            workingName: (NSString *) workingName
{
    int i;
    NSRange slashRange = [workingName rangeOfString: @"/" options: 0 range: NSMakeRange(0, [workingName length] - 1)];
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
                menuItemTitle = [[menuItem target] displayName];
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
    NSString * subMenuName = [workingName substringWithRange: NSMakeRange(0, slashRange.location + 1)];
    NSString * restOfName = [workingName substringFromIndex: slashRange.location + 1];
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
                    [self removeConnectionWithDisplayName: theName fromMenu: subMenu afterIndex: 0 workingName: restOfName];
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

- (BOOL)validateMenuItem:(NSMenuItem *)anItem 
{
    // We set the on/off state from the CURRENT preferences, not the preferences when launched.
    SEL act = [anItem action];
    if (  act == @selector(disconnectAllMenuItemWasClicked:)  ) {
        unsigned nConnections = [[self connectionArray] count];
        NSString * myState;
        if (  nConnections == 0  ) {
            myState = NSLocalizedString(@"No Active Connections", @"Status message");
            [statusMenuItem setTitle: myState];
            return NO;
        } else if (  nConnections == 1) {
            NSString * name = nil;
            if (  [[self connectionArray] count] > 0  ) {
                name = [[[self connectionArray] objectAtIndex: 0] displayName];
            }
            if (  ! name  ) {
                name = @"1 connection";
            }
            myState = [NSString stringWithFormat: NSLocalizedString(@"Disconnect All (%@)", @"Status message"), name];
            [statusMenuItem setTitle: myState];
        } else {
            myState = [NSString stringWithFormat:NSLocalizedString(@"Disconnect All (%d Connections)", @"Status message"),nConnections];
            [statusMenuItem setTitle: myState];
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

-(void) changedDisplayConnectionTimersSettings
{
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
            NSEnumerator * connEnum = [[self myVPNConnectionDictionary] objectEnumerator];
            while (  (conn = [connEnum nextObject])  ) {
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
        if (  [gTbDefaults boolForKey:@"showConnectedDurations"]  ) {
            VPNConnection * conn;
            NSEnumerator * connEnum = [[self myVPNConnectionDictionary] objectEnumerator];
            while (  (conn = [connEnum nextObject])  ) {
                if (  [[conn state] isEqualToString: @"CONNECTED"]) {
                    return;
                }
            }
        }
        
        [showDurationsTimer invalidate];
        [showDurationsTimer release];
        showDurationsTimer = nil;
    }
}

-(void)updateNavigationLabels
{
    [logScreen updateNavigationLabels];
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
    while (  (dispNm = [e nextObject])  ) {
        BOOL sameDispNm = [[self myConfigDictionary] objectForKey: dispNm] != nil;
        BOOL sameFolder = [[[self myConfigDictionary] objectForKey: dispNm] isEqualToString: [curConfigsDict objectForKey: dispNm]];
        
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
	NSMutableArray * removeList = [NSMutableArray arrayWithCapacity: 10];
    e = [[self myConfigDictionary] keyEnumerator];
    while (  (dispNm = [e nextObject])  ) {
        BOOL sameDispNm = [curConfigsDict objectForKey: dispNm] != nil;
        if (  ! sameDispNm  ) {
            [removeList addObject: [[dispNm copy] autorelease]]; // No new config with same name
        }
    }
    e = [removeList objectEnumerator];
    while (  (dispNm = [e nextObject])  ) {
        [self deleteExistingConfig: dispNm];
        needToUpdateLogWindow = TRUE;
    }
    
	// If there aren't any configuration files left, deal with that
    if (  ! checkingForNoConfigs  ) {
        [self checkNoConfigurations];
    }
    
    if (  needToUpdateLogWindow  ) {
        [logScreen update];
    }
}

// Lock this to change myVPNConnectionDictionary, myMenu, and/or myConfigDictionary
static pthread_mutex_t configModifyMutex = PTHREAD_MUTEX_INITIALIZER;

// Add new config to myVPNConnectionDictionary, the menu, and myConfigDictionary
// Note: The menu item's title will be set on demand in VPNConnection's validateMenuItem
-(void) addNewConfig: (NSString *) path withDisplayName: (NSString *) dispNm
{
    if (  invalidConfigurationName(dispNm, PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING)  ) {
		TBRunAlertPanel(NSLocalizedString(@"Name not allowed", @"Window title"),
						[NSString stringWithFormat: NSLocalizedString(@"Configuration '%@' will be ignored because its"
																	  @" name contains characters that are not allowed.\n\n"
																	  @"Characters that are not allowed: '%s'\n\n", @"Window text"),
						 dispNm, PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING],
						nil, nil, nil);
        return;
    }
    VPNConnection* myConnection = [[VPNConnection alloc] initWithConfigPath: path
                                                            withDisplayName: dispNm];
    [myConnection setDelegate:self];
    
    NSMenuItem *connectionItem = [[[NSMenuItem alloc] init] autorelease];
    [connectionItem setTarget:myConnection]; 
    [connectionItem setAction:@selector(toggle:)];
    
    OSStatus status = pthread_mutex_lock( &configModifyMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &configModifyMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    
    status = pthread_mutex_lock( &myVPNMenuMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &myVPNMenuMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    
    // Add connection to myVPNConnectionDictionary
    NSMutableDictionary * tempVPNConnectionDictionary = [myVPNConnectionDictionary mutableCopy];
    [tempVPNConnectionDictionary setObject: myConnection forKey: dispNm];
    [self setMyVPNConnectionDictionary: [[tempVPNConnectionDictionary copy] autorelease]];
    [tempVPNConnectionDictionary release];
    
    int itemIx = (int) [myVPNMenu indexOfItemWithTitle: NSLocalizedString(@"No VPN Configurations Available", @"Menu item")];
    if (  itemIx  != -1) {
        [myVPNMenu removeItemAtIndex: itemIx];
    }
    
    [self insertConnectionMenuItem: connectionItem IntoMenu: myVPNMenu afterIndex: 2 withName: [[connectionItem target] displayName]];
    
    // Add connection to myConfigDictionary
    NSMutableDictionary * tempConfigDictionary = [myConfigDictionary mutableCopy];
    [tempConfigDictionary setObject: path forKey: dispNm];
    [self setMyConfigDictionary: [[tempConfigDictionary copy] autorelease]];
    [tempConfigDictionary release];
     
    status = pthread_mutex_unlock( &myVPNMenuMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &myVPNMenuMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    status = pthread_mutex_unlock( &configModifyMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &configModifyMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
    }
}

// Remove config from myVPNConnectionDictionary, the menu, and myConfigDictionary
// Disconnect first if necessary
-(void) deleteExistingConfig: (NSString *) dispNm
{
    VPNConnection* myConnection = [myVPNConnectionDictionary objectForKey: dispNm];
    if (  ! [[myConnection state] isEqualTo: @"EXITING"]  ) {
        [myConnection addToLog: @"*Tunnelblick: Disconnecting; user asked to delete the configuration"];
        [myConnection disconnectAndWait: [NSNumber numberWithBool: NO] userKnows: YES];
        
        TBRunAlertPanel([NSString stringWithFormat: NSLocalizedString(@"'%@' has been disconnected", @"Window title"), dispNm],
                        [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick has disconnected '%@' because its configuration file has been removed.", @"Window text"), dispNm],
                        nil, nil, nil);
    }
    
    OSStatus status = pthread_mutex_lock( &configModifyMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &configModifyMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    
    status = pthread_mutex_lock( &myVPNMenuMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &myVPNMenuMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    
    // Remove connection from myVPNConnectionDictionary
    NSMutableDictionary * tempVPNConnectionDictionary = [myVPNConnectionDictionary mutableCopy];
    [tempVPNConnectionDictionary removeObjectForKey: dispNm];
    [self setMyVPNConnectionDictionary: [[tempVPNConnectionDictionary copy] autorelease]];
    [tempVPNConnectionDictionary release];
        
    [self removeConnectionWithDisplayName: dispNm fromMenu: myVPNMenu afterIndex: 2];

    // Remove connection from myConfigDictionary
    NSMutableDictionary * tempConfigDictionary = [myConfigDictionary mutableCopy];
    [tempConfigDictionary removeObjectForKey: dispNm];
    [self setMyConfigDictionary: [[tempConfigDictionary copy] autorelease]];
    [tempConfigDictionary release];

    if (  [[self myConfigDictionary] count] == 0  ) {
        int itemIx = (int) [myVPNMenu indexOfItemWithTitle: NSLocalizedString(@"No VPN Configurations Available", @"Menu item")];
        if (  itemIx  == -1  ) {
            [myVPNMenu insertItem: noConfigurationsItem atIndex: 2];
        }
        
        itemIx = (int) [myVPNMenu indexOfItemWithTitle: NSLocalizedString(@"Add a VPN...", @"Menu item")];
        if (   (itemIx  == -1)
            && addConfigurationItem  ) {
            [myVPNMenu insertItem: [[addConfigurationItem copy] autorelease] atIndex: 3]; // Use a copy because the original is used in elsewhere
        }
    }
    
    status = pthread_mutex_unlock( &myVPNMenuMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &myVPNMenuMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    status = pthread_mutex_unlock( &configModifyMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &configModifyMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
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
    [logScreen validateConnectAndDisconnectButtonsForConnection: connection];
}

- (void) updateUI
{
    if (  gShuttingDownWorkspace  ) {
        [theAnim stopAnimation];
        return;
    }
    
	if (   (![lastState isEqualToString:@"EXITING"])
        && (![lastState isEqualToString:@"CONNECTED"]) ) { 
		//  Anything other than connected or disconnected shows the animation
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
        
        if (  [lastState isEqualToString:@"CONNECTED"]  ) {
            [[self ourMainIconView] setImage: connectedImage];
        } else {
            [[self ourMainIconView] setImage: mainImage];
        }
	}
}

- (void)animationDidEnd:(NSAnimation*)animation
{
	if (  animation != theAnim  ) {
		return;
	}
	
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
	if (   (![lastState isEqualToString:@"EXITING"])
        && (![lastState isEqualToString:@"CONNECTED"]))
	{
		// NSLog(@"Starting Animation (2)");
		[theAnim startAnimation];
	}
}

- (void)animation:(NSAnimation *)animation didReachProgressMark:(NSAnimationProgress)progress
{
    if (  gShuttingDownWorkspace  ) {  // Stop _any_ animation we are doing
        [animation stopAnimation];
        return;
    }
    
	if (animation == theAnim) {
        [[self ourMainIconView] performSelectorOnMainThread:@selector(setImage:) withObject:[animImages objectAtIndex: (unsigned) (lround(progress * [animImages count]) - 1)] waitUntilDone:YES];
	}
}

- (NSString *) openVPNLogHeader
{
    unsigned major, minor, bugFix;
    [[NSApplication sharedApplication] getSystemVersionMajor:&major minor:&minor bugFix:&bugFix];
    
    NSArray  * versionHistory     = [gTbDefaults objectForKey: @"tunnelblickVersionHistory"];
    NSString * priorVersionString = (  (  [versionHistory count] > 1  )
                                     ? [NSString stringWithFormat: @"; prior version %@", [versionHistory objectAtIndex: 1]]
                                     : @"");

    return ([NSString stringWithFormat:@"*Tunnelblick: OS X %d.%d.%d; %@%@",
             major, minor, bugFix, tunnelblickVersion([NSBundle mainBundle]), priorVersionString]);
}

- (void) checkForUpdates: (id) sender
{
	(void) sender;
	
    if (   [gTbDefaults boolForKey:@"onlyAdminCanUpdate"]
        && ( ! userIsAnAdmin )  ) {
        NSLog(@"Check for updates was not performed because user is not allowed to administer this computer and 'onlyAdminCanUpdate' preference is set");
    } else {
        if (  [updater respondsToSelector: @selector(checkForUpdates:)]  ) {
            if (  feedURL != nil  ) {
                if (  ! userIsAnAdmin  ) {
                    int response = TBRunAlertPanelExtended(NSLocalizedString(@"Only computer administrators should update Tunnelblick", @"Window title"),
                                                           NSLocalizedString(@"You will not be able to use Tunnelblick after updating unless you provide an administrator username and password.\n\nAre you sure you wish to check for updates?", @"Window text"),
                                                           NSLocalizedString(@"Check For Updates Now", @"Button"),  // Default button
                                                           NSLocalizedString(@"Cancel", @"Button"),                 // Alternate button
                                                           nil,                                                     // Other button
                                                           @"skipWarningAboutNonAdminUpdatingTunnelblick",          // Preference about seeing this message again
                                                           NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
                                                           nil,
														   NSAlertDefaultReturn);
                    if (  response != NSAlertDefaultReturn  ) {   // No action if cancelled or error occurred
                        return;
                    }
                }
                [updater checkForUpdates: self];
            } else {
                NSLog(@"'Check for Updates Now' ignored because no FeedURL has been set");
            }
            
        } else {
            NSLog(@"'Check for Updates Now' ignored because Sparkle Updater does not respond to checkForUpdates:");
        }
        
        [myConfigUpdater startWithUI: YES]; // Display the UI
    }
}

// May be called from cleanup or willGoToSleepHandler, so only do one at a time
static pthread_mutex_t killAllConnectionsIncludingDaemonsMutex = PTHREAD_MUTEX_INITIALIZER;
    
// If possible, we try to use 'killall' to kill all processes named 'openvpn'
// But if there are unknown open processes that the user wants running, or we have active daemon processes,
//     then we must use 'kill' to kill each individual process that should be killed
-(void) killAllConnectionsIncludingDaemons: (BOOL) includeDaemons logMessage: (NSString *) logMessage
{
    // DO NOT put this code inside the mutex: we want to return immediately if computer is shutting down or restarting
    if (  gShuttingDownOrRestartingComputer  ) {
        NSLog(@"DEBUG: killAllConnectionsIncludingDaemons: Computer is shutting down or restarting; OS X will kill OpenVPN instances");
        return;
    }
    
    OSStatus status = pthread_mutex_lock( &killAllConnectionsIncludingDaemonsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &killAllConnectionsIncludingDaemonsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    
    NSEnumerator * connEnum = [[self myVPNConnectionDictionary] objectEnumerator];
    VPNConnection * connection;
    
    BOOL noActiveDaemons = YES;
    if (  ! includeDaemons  ) {
        // See if any of our daemons are active -- i.e., have a process ID (they may be in the process of connecting or disconnecting)
        while (  (connection = [connEnum nextObject])  ) {
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
    
    NSLog(@"DEBUG: killAllConnectionsIncludingDaemons: has checked for active daemons");
    
    // See if any connections that are not disconnected use down-root
    BOOL noDownRootsActive = YES;
    connEnum = [[self myVPNConnectionDictionary] objectEnumerator];
    while (  (connection = [connEnum nextObject])  ) {
        if (  ! [connection isDisconnected]  ) {
            NSString * useDownRootPluginKey = [[connection displayName] stringByAppendingString: @"-useDownRootPlugin"];
            if (   [gTbDefaults boolForKey: useDownRootPluginKey]  ) {
                noDownRootsActive = NO;
				NSLog(@"DEBUG: %@ is not disconnected and is using the down-root plugin", [connection displayName]);
                break;
            }
        }
    }
    
	NSLog(@"DEBUG: includeDaemons = %d; noUnknownOpenVPNsRunning = %d; noActiveDaemons = %d; noDownRootsActive = %d ",
		  (int) includeDaemons, (int) noUnknownOpenVPNsRunning, (int) noActiveDaemons, (int) noDownRootsActive);
    if (   ALLOW_OPENVPNSTART_KILLALL
		&& noDownRootsActive
		&& ( includeDaemons
			|| ( noUnknownOpenVPNsRunning && noActiveDaemons )
			)
		) {
        
        NSLog(@"DEBUG: killAllConnectionsIncludingDaemons: will use killAll");

        // Killing everything, so we use 'killall' to kill all processes named 'openvpn'
        // But first append a log entry for each connection that will be restored
        NSEnumerator * connectionEnum = [connectionsToRestoreOnWakeup objectEnumerator];
        while (  (connection = [connectionEnum nextObject])  ) {
            [connection addToLog: logMessage];
        }
        // If we've added any log entries, sleep for one second so they come before OpenVPN entries associated with closing the connections
        if (  [connectionsToRestoreOnWakeup count] != 0  ) {
            NSLog(@"DEBUG: killAllConnectionsIncludingDaemons: sleeping for logs to settle");
            sleep(1);
        }
        
        NSLog(@"DEBUG: killAllConnectionsIncludingDaemons: requested killAll");
        runOpenvpnstart([NSArray arrayWithObject: @"killall"], nil, nil);
        NSLog(@"DEBUG: killAllConnectionsIncludingDaemons: killAll finished");
    } else {
        
        NSLog(@"DEBUG: killAllConnectionsIncludingDaemons: will kill individually");
        // Killing selected processes only -- those we know about that are not daemons
		connEnum = [[self myVPNConnectionDictionary] objectEnumerator];
        while (  (connection = [connEnum nextObject])  ) {
            if (  ! [connection isDisconnected]  ) {
                NSString* onSystemStartKey = [[connection displayName] stringByAppendingString: @"-onSystemStart"];
                NSString* autoConnectKey = [[connection displayName] stringByAppendingString: @"autoConnect"];
                if (   ( ! [gTbDefaults boolForKey: onSystemStartKey]  )
                    || ( ! [gTbDefaults boolForKey: autoConnectKey]    )  ) {
                    pid_t procId = [connection pid];
					if (  ALLOW_OPENVPNSTART_KILL  ) {
						if (  procId > 0  ) {
							[connection addToLog: logMessage];
							NSArray * arguments = [NSArray arrayWithObjects: @"kill", [NSString stringWithFormat: @"%ld", (long) procId], nil];
							NSLog(@"DEBUG: killAllConnectionsIncludingDaemons: killing '%@'", [connection displayName]);
							runOpenvpnstart(arguments, nil, nil);
							NSLog(@"DEBUG: killAllConnectionsIncludingDaemons: have killed '%@'", [connection displayName]);
						} else {
							[connection addToLog: @"*Tunnelblick: Disconnecting; all configurations are being disconnected"];
							NSLog(@"DEBUG: killAllConnectionsIncludingDaemons: disconnecting '%@'", [connection displayName]);
							[connection disconnectAndWait: [NSNumber numberWithBool: NO] userKnows: NO];
							NSLog(@"DEBUG: killAllConnectionsIncludingDaemons: have disconnected '%@'", [connection displayName]);
						}
					} else {
						NSLog(@"DEBUG: killAllConnectionsIncludingDaemons: requesting disconnection of '%@' (pid %lu) via disconnectAndWait",
							  [connection displayName], (long) procId);
						[connection disconnectAndWait: [NSNumber numberWithBool: NO] userKnows: YES];
					}
				} else {
					NSLog(@"DEBUG: killAllConnectionsIncludingDaemons: Not requesting disconnection of '%@' (pid %lu) because"
						  @" it is set to connect when the computer starts.",
						  [connection displayName], (long) [connection pid]);
				}
			}
        }
    }
    
    status = pthread_mutex_unlock( &killAllConnectionsIncludingDaemonsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &killAllConnectionsIncludingDaemonsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
    }
}    
    
// May be called from cleanup, so only do one at a time
static pthread_mutex_t unloadKextsMutex = PTHREAD_MUTEX_INITIALIZER;

// Unloads our loaded tun/tap kexts if tunCount/tapCount is zero.
-(void) unloadKexts
{
    OSStatus status = pthread_mutex_trylock( &unloadKextsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &unloadKextsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    
    unsigned bitMask = [self getLoadedKextsMask] & ( ~ (OPENVPNSTART_FOO_TAP_KEXT | OPENVPNSTART_FOO_TUN_KEXT)  );    // Don't unload foo.tun/tap
    
    if (  bitMask != 0  ) {
        if (  tapCount != 0  ) {
            bitMask = bitMask & ( ~OPENVPNSTART_OUR_TAP_KEXT);
        }
        
        if (  tunCount != 0  ) {
            bitMask = bitMask & ( ~OPENVPNSTART_OUR_TUN_KEXT);
        }
        
        if (  bitMask != 0  ) {
            NSString * arg1 = [NSString stringWithFormat: @"%d", bitMask];
            runOpenvpnstart([NSArray arrayWithObjects:@"unloadKexts", arg1, nil], nil, nil);
        }
    }
    
    status = pthread_mutex_unlock( &unloadKextsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &unloadKextsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
    }    
}

// Returns with a bitmask of kexts that are loaded that can be unloaded
// Launches "kextstat" to get the list of loaded kexts, and does a simple search
-(unsigned) getLoadedKextsMask
{
    NSString * tempDir = newTemporaryDirectoryPath();
    NSString * kextOutputPath = [tempDir stringByAppendingPathComponent: @"Tunnelblick-kextstat-output.txt"];
    if (  ! [gFileMgr createFileAtPath: kextOutputPath contents: [NSData data] attributes: nil]  ) {
        fprintf(stderr, "Warning: Unable to create temporary directory for kextstat output file. Assuming foo.tun and foo.tap kexts are loaded.\n");
        [gFileMgr tbRemoveFileAtPath: tempDir handler: nil];
        [tempDir release];
        return (OPENVPNSTART_FOO_TAP_KEXT | OPENVPNSTART_FOO_TUN_KEXT);
    }
    NSFileHandle * kextOutputHandle = [NSFileHandle fileHandleForWritingAtPath: kextOutputPath];
    if (  ! kextOutputHandle  ) {
        fprintf(stderr, "Warning: Unable to create temporary output file for kextstat. Assuming foo.tun and foo.tap kexts are loaded.\n");
        [gFileMgr tbRemoveFileAtPath: tempDir handler: nil];
        [tempDir release];
        return (OPENVPNSTART_FOO_TAP_KEXT | OPENVPNSTART_FOO_TUN_KEXT);
    }
    
    NSTask * task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath: TOOL_PATH_FOR_KEXTSTAT];
    
    NSArray  *arguments = [NSArray array];
    [task setArguments: arguments];
    
    [task setStandardOutput: kextOutputHandle];
    
    [task launch];
    
    [task waitUntilExit];
    
    [kextOutputHandle closeFile];
    
    OSStatus status = [task terminationStatus];
    if (  status != EXIT_SUCCESS  ) {
        fprintf(stderr, "Warning: kextstat to list loaded kexts failed. Assuming foo.tun and foo.tap kexts are loaded.\n");
        return (OPENVPNSTART_FOO_TAP_KEXT | OPENVPNSTART_FOO_TUN_KEXT);
    }
    
    NSData * data = [gFileMgr contentsAtPath: kextOutputPath];
    
    [gFileMgr tbRemoveFileAtPath: tempDir handler: nil];
    [tempDir release];
    
    NSString * string = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
    
    unsigned bitMask = 0;
    
    if (  [string rangeOfString: @"foo.tap"].length != 0  ) {
        bitMask = OPENVPNSTART_FOO_TAP_KEXT;
    }
    if (  [string rangeOfString: @"foo.tun"].length != 0  ) {
        bitMask = bitMask | OPENVPNSTART_FOO_TUN_KEXT;
    }
    if (  [string rangeOfString: @"net.tunnelblick.tap"].length != 0  ) {
        bitMask = bitMask | OPENVPNSTART_OUR_TAP_KEXT;
    }
    if (  [string rangeOfString: @"net.tunnelblick.tun"].length != 0  ) {
        bitMask = bitMask | OPENVPNSTART_OUR_TUN_KEXT;
    }
    
    return bitMask;
}

-(void) resetActiveConnections {
	VPNConnection *connection;
	NSEnumerator* e = [[self connectionArray] objectEnumerator];
	while (  (connection = [e nextObject])  ) {
		if ([[connection connectedSinceDate] timeIntervalSinceNow] < -5) {
			if (NSDebugEnabled) NSLog(@"Resetting connection: %@",[connection displayName]);
            [connection addToLog: @"*Tunnelblick: Disconnecting; resetting all connections"];
			[connection disconnectAndWait: [NSNumber numberWithBool: YES] userKnows: NO];
			[connection connect:self userKnows: NO];
		} else {
			if (NSDebugEnabled) NSLog(@"Not Resetting connection: %@, waiting...",[connection displayName]);
		}
	}
}

-(NSArray *) connectionsNotDisconnected {
    NSMutableArray * list = [[[NSMutableArray alloc] initWithCapacity:10] autorelease];
    NSEnumerator * connEnum = [[self myVPNConnectionDictionary] objectEnumerator];
    VPNConnection * connection;
    while (  (connection = [connEnum nextObject])  ) {
        if (  ! [[connection state] isEqualToString: @"EXITING"]  ) {
            [list addObject: connection];
        }
    }
    
    return list;
}

BOOL anyNonTblkConfigs(void)
{
	// Returns TRUE if there were any private non-tblks (and they need to be converted)
    NSString * file;
    NSDirectoryEnumerator *dirEnum = [gFileMgr enumeratorAtPath: gPrivatePath];
    while (  (file = [dirEnum nextObject])  ) {
        NSString * fullPath = [gPrivatePath stringByAppendingPathComponent: file];
        if (  itemIsVisible(fullPath)  ) {
			NSString * ext = [file pathExtension];
            if (  [ext isEqualToString: @"tblk"]  ) {
				[dirEnum skipDescendents];
            } else {
				if (   [ext isEqualToString: @"ovpn"]
					|| [ext isEqualToString: @"conf"]  ) {
					return YES;
				}
			}
		}
	}
	
	return NO;
}

-(void) checkNoConfigurations {
    
    // If there aren't ANY config files in the config folders
    // then guide the user
    //
    // When Sparkle updates us while we're running, it moves us to the Trash, then replaces us, then terminates us, then launches the new copy.

    if (   ignoreNoConfigs
        || ( [[self myConfigDictionary] count] != 0 )
        ) {
        return;
    }
    
    // Make sure we notice any configurations that have just been installed
    checkingForNoConfigs = TRUE;    // Avoid infinite recursion
    [self activateStatusMenu];
    checkingForNoConfigs = FALSE;
    
    if (  [[self myConfigDictionary] count] != 0  ) {
        return;
    }
    
    // If this is a Deployed version with no configurations, quit Tunnelblick
    if (   [gConfigDirs count] == 1
        && [[gConfigDirs objectAtIndex:0] isEqualToString: gDeployPath]  ) {
        TBRunAlertPanel(NSLocalizedString(@"All configuration files removed", @"Window title"),
                        NSLocalizedString(@"All configuration files have been removed. Tunnelblick must quit.", @"Window text"),
                        nil, nil, nil);
        [self terminateBecause: terminatingBecauseOfError];
    }
    
    if (  anyNonTblkConfigs()  ) {
        int response = TBRunAlertPanel(NSLocalizedString(@"Warning", @"Window title"),
                                       NSLocalizedString(@"You have OpenVPN configurations but you do not have any Tunnelblick VPN Configurations.\n\n"
                                                         @"You must convert OpenVPN configurations to Tunnelblick VPN Configurations if you want to use them.\n\n", @"Window text"),
                                       NSLocalizedString(@"Convert Configurations", @"Button"), // Default return
                                       NSLocalizedString(@"Ignore", @"Button"),                 // Alternate return
                                       NSLocalizedString(@"Quit", @"Button"));                  // Other return
        
		if (   (response == NSAlertOtherReturn)
            || (response == NSAlertErrorReturn)  ) {  // Quit if requested or error
			[[NSApp delegate] terminateBecause: terminatingBecauseOfQuit];
		}
		
		if (  response == NSAlertDefaultReturn  ) {
            ignoreNoConfigs = TRUE; // Because we do the testing and don't want interference
            if (  [self runInstaller: INSTALLER_CONVERT_NON_TBLKS
                      extraArguments: nil
                     usingAuthRefPtr: &gAuthorization
                             message: nil
                   installTblksFirst: nil]  ) {
                // Installer did conversion(s); set up to use the new configurations
                [self activateStatusMenu];
                if (  [[self myConfigDictionary] count] != 0  ) {
                    ignoreNoConfigs = FALSE;
                    return;
                }
                
                // fall through if still don't have any configurations
            }
            
            ignoreNoConfigs = FALSE;
            // fall through if installer failed or still don't have any configurations
        }
	}
	
    [[ConfigurationManager defaultManager] haveNoConfigurationsGuide];
}

-(IBAction) addConfigurationWasClicked: (id) sender
{
 	(void) sender;
	
	[[ConfigurationManager defaultManager] addConfigurationGuide];
}

-(IBAction) disconnectAllMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    NSEnumerator * connEnum = [[self myVPNConnectionDictionary] objectEnumerator];
    VPNConnection * connection;
    while (  (connection = [connEnum nextObject])  ) {
        if (  ! [connection isDisconnected]  ) {
            [connection addToLog: @"*Tunnelblick: Disconnecting; 'Disconnect all' menu command invoked"];
            [connection disconnectAndWait: [NSNumber numberWithBool: NO] userKnows: YES];
        }
    }
}

-(IBAction) contactTunnelblickWasClicked: (id) sender
{
	(void) sender;
	
    NSURL * url = [self contactURL];
    if (  url  ) {
        [[NSWorkspace sharedWorkspace] openURL: url];
    }
}

-(NSURL *) contactURL
{
    NSString * string = [NSString stringWithFormat: @"http://www.tunnelblick.net/contact?v=%@", tunnelblickVersion([NSBundle mainBundle])];
    string = [string stringByAddingPercentEscapesUsingEncoding: NSASCIIStringEncoding];
    NSURL * url = [NSURL URLWithString: string];
    if (  ! url  ) {
        NSLog(@"Invalid contactURL");
    }
    
    return url;
}

-(IBAction) openPreferencesWindow: (id) sender
{
	(void) sender;
	
    [[MyPrefsWindowController sharedPrefsWindowController] showWindow: nil];
    [NSApp activateIgnoringOtherApps:YES];  // Force Preferences window to front (if it already exists and is covered by another window)

}

- (void) networkConfigurationDidChange
{
	if (NSDebugEnabled) NSLog(@"Got networkConfigurationDidChange notification!!");
	[self resetActiveConnections];
}

static pthread_mutex_t cleanupMutex = PTHREAD_MUTEX_INITIALIZER;

// Returns TRUE if cleaned up, or FALSE if a cleanup is already taking place
-(BOOL) cleanup 
{
    NSLog(@"DEBUG: Cleanup: Entering cleanup");
    
    OSStatus status = pthread_mutex_trylock( &cleanupMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_trylock( &cleanupMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        NSLog(@"pthread_mutex_trylock( &cleanupMutex ) failed is normal and expected when Tunnelblick is updated");
        return FALSE;
    }
    
    // DO NOT ever unlock cleanupMutex -- we don't want to allow another cleanup to take place
    
    if ( gShuttingDownOrRestartingComputer ) {
        NSLog(@"DEBUG: Cleanup: Skipping cleanup because computer is shutting down or restarting");
        // DO NOT ever unlock cleanupMutex -- we don't want to allow another cleanup to take place
        return TRUE;
    }
    
    NSLog(@"DEBUG: Cleanup: Setting callDelegateOnNetworkChange: NO");
    [NSApp callDelegateOnNetworkChange: NO];
    
    if (  ! [lastState isEqualToString:@"EXITING"]) {
        NSLog(@"DEBUG: Cleanup: Will killAllConnectionsIncludingDaemons: NO");
        [self killAllConnectionsIncludingDaemons: NO logMessage: @"*Tunnelblick: Tunnelblick is quitting. Closing connection..."];  // Kill any of our OpenVPN processes that still exist unless they're "on computer start" configurations
    }
    
    if (  reasonForTermination == terminatingBecauseOfFatalError  ) {
        NSLog(@"Skipping unloading of kexts because of fatal error.");
    } else {
        NSLog(@"DEBUG: Cleanup: Unloading kexts");
        [self unloadKexts];     // Unload .tun and .tap kexts
    }
    
    if (  reasonForTermination == terminatingBecauseOfFatalError  ) {
        NSLog(@"Skipping deleting logs because of fatal error.");
    } else {
        NSLog(@"DEBUG: Cleanup: Deleting logs");
        [self deleteLogs];
    }

    if ( ! gShuttingDownWorkspace  ) {
        if (  statusItem  ) {
            NSLog(@"DEBUG: Cleanup: Removing status bar item");
            [[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
        }
        
        if (  hotKeyEventHandlerIsInstalled && hotKeyModifierKeys != 0  ) {
            NSLog(@"DEBUG: Cleanup: Unregistering hotKeyEventHandler");
            UnregisterEventHotKey(hotKeyRef);
        }
    }
    
    // DO NOT ever unlock cleanupMutex -- we don't want to allow another cleanup to take place
    return TRUE;
}

-(void) deleteLogs
{
    VPNConnection * connection;
    NSEnumerator * e = [[self myVPNConnectionDictionary] objectEnumerator];
    while (  (connection = [e nextObject])  ) {
        [connection deleteLogs];
    }
}

- (void) setState: (NSString*) newState
{
	// Be sure to call this in main thread only
	//
    // Decide how to display the Tunnelblick icon:
    // Ignore the newState argument and look at the configurations:
    //   If any configuration should be open but isn't open and isn't closed, then show animation
    //   If any configuration should be closed but isn't, then show animation
    //   Otherwise, if any configurations are open, show open
    //              else show closed

	(void) newState;
	
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    BOOL atLeastOneIsConnected = FALSE;
    NSString * newDisplayState = @"EXITING";
    VPNConnection * connection;
    NSEnumerator * connEnum = [[self myVPNConnectionDictionary] objectEnumerator];
    while (  (connection = [connEnum nextObject])  ) {
        NSString * curState = [connection state];
        NSString * reqState = [connection requestedState];
        if     (  [reqState isEqualToString: @"CONNECTED"]  ) {
            if (  [curState isEqualToString: @"CONNECTED"]  ) {
                atLeastOneIsConnected = TRUE;
            } else if (  ! [curState isEqualToString: @"EXITING"]  ) {
                newDisplayState = @"ANIMATED";
                break;
            }
        } else if (  [reqState isEqualToString: @"EXITING"]  ) {
            if (   ! [curState isEqualToString: @"EXITING"]  ) {
                newDisplayState = @"ANIMATED";
                break;
            }
        } else {
            NSLog(@"Internal program error: invalid requestedState = %@", reqState);
        }
    }
    
    if (   atLeastOneIsConnected
        && [newDisplayState isEqualToString: @"EXITING"]  ) {
        newDisplayState = @"CONNECTED";
    }
    
    // Display that unless it is already being displayed
    if (  ![newDisplayState isEqualToString: lastState]  ) {
        [newDisplayState retain];
        [lastState release];
        lastState = newDisplayState;
        [self performSelectorOnMainThread:@selector(updateUI) withObject:nil waitUntilDone:NO];
    }
}

static pthread_mutex_t connectionArrayMutex = PTHREAD_MUTEX_INITIALIZER;

-(void)addConnection:(id)sender 
{
	if (  sender != nil  ) {
        OSStatus status = pthread_mutex_trylock( &connectionArrayMutex );
        if (  status != EXIT_SUCCESS  ) {
            NSLog(@"pthread_mutex_trylock( &connectionArrayMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
            return;
        }
        NSMutableArray * tempConnectionArray = [[self connectionArray] mutableCopy];
		[tempConnectionArray removeObject:sender];
		[tempConnectionArray addObject:sender];
        [self setConnectionArray: tempConnectionArray];
        [tempConnectionArray release];
        status = pthread_mutex_unlock( &connectionArrayMutex );
        if (  status != EXIT_SUCCESS  ) {
            NSLog(@"pthread_mutex_unlock( &connectionArrayMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
            return;
        }    
        
        [self startOrStopDurationsTimer];
	}
}

-(void)removeConnection:(id)sender
{
	if (  sender != nil  ) {
        OSStatus status = pthread_mutex_trylock( &connectionArrayMutex );
        if (  status != EXIT_SUCCESS  ) {
            NSLog(@"pthread_mutex_trylock( &connectionArrayMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
            return;
        }
        NSMutableArray * tempConnectionArray = [[self connectionArray] mutableCopy];
        [tempConnectionArray removeObject:sender];
        [self setConnectionArray: tempConnectionArray];
        [tempConnectionArray release];
        status = pthread_mutex_unlock( &connectionArrayMutex );
        if (  status != EXIT_SUCCESS  ) {
            NSLog(@"pthread_mutex_unlock( &connectionArrayMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
            return;
        }    
        
        [self startOrStopDurationsTimer];
    }
}

-(void) terminateBecause: (enum TerminationReason) reason
{
	reasonForTermination = reason;
    
    if (   (reason != terminatingBecauseOfLogout)
        && (reason != terminatingBecauseOfRestart)
        && (reason != terminatingBecauseOfShutdown)  ) {
        [NSApp setAutoLaunchOnLogin: NO];
        terminatingAtUserRequest = TRUE;
    }
    
    if (  reason == terminatingBecauseOfQuit  ) {
        terminatingAtUserRequest = TRUE;
    }
        [NSApp terminate: self];
}

int runUnrecoverableErrorPanel(NSString * msg)
{
	int result = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick Error", @"Window title"),
                                 [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick encountered a fatal error.\n\nReinstalling Tunnelblick may fix this problem. The problem was:\n\n%@", @"Window text"),
                                  msg],
                                 NSLocalizedString(@"Download", @"Button"),
                                 NSLocalizedString(@"Quit", @"Button"),
                                 nil);
	if( result == NSAlertDefaultReturn ) {
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://tunnelblick.net/"]];
	}
    
    // Quit if "Quit" or error
    
    exit(2);
}

static void signal_handler(int signalNumber)
{
    if (signalNumber == SIGHUP) {
        NSLog(@"SIGHUP received. Restarting active connections");
        [[NSApp delegate] resetActiveConnections];
    } else  {
        if (  signalNumber == SIGTERM ) {
            if (   gShuttingDownTunnelblick
                && (   (reasonForTermination == terminatingBecauseOfLogout)
                    || (reasonForTermination == terminatingBecauseOfRestart)
                    || (reasonForTermination == terminatingBecauseOfShutdown) )  ) {
                NSLog(@"Ignoring SIGTERM (signal %d) because Tunnelblick is already terminating", signalNumber);
                return;
            } else {
                NSLog(@"SIGTERM (signal %d) received", signalNumber);
                [[NSApp delegate] terminateBecause: terminatingBecauseOfQuit];
                return;
            }
        }
        
        NSLog(@"Received fatal signal %d.", signalNumber);
        if ( reasonForTermination == terminatingBecauseOfFatalError ) {
            NSLog(@"signal_handler: Error while handling signal.");
            exit(0);
        } else {
            runUnrecoverableErrorPanel([NSString stringWithFormat: NSLocalizedString(@"Received fatal signal %d.", @"Window text"), signalNumber]);
            reasonForTermination = terminatingBecauseOfFatalError;
            gShuttingDownTunnelblick = TRUE;
            NSLog(@"signal_handler: Starting cleanup.");
            if (  [[NSApp delegate] cleanup]  ) {
                NSLog(@"signal_handler: Cleanup finished.");
            } else {
                NSLog(@"signal_handler: Cleanup already being done.");
            }
        }
        exit(0);	
    }
}

- (void) installSignalHandler
{
    struct sigaction action;
    
    action.sa_handler = signal_handler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    
    if (sigaction(SIGHUP,  &action, NULL) || 
        sigaction(SIGQUIT, &action, NULL) || 
        sigaction(SIGTERM, &action, NULL) ||
        sigaction(SIGBUS,  &action, NULL) ||
        sigaction(SIGSEGV, &action, NULL) ||
        sigaction(SIGPIPE, &action, NULL)) {
        NSLog(@"Warning: setting signal handler failed: '%s'", strerror(errno));
    }	
}


// Invoked by Tunnelblick modifications to Sparkle with the path to a .bundle with updated configurations to install
-(void) installConfigurationsUpdateInBundleAtPathHandler: (NSString *) path
{
    // This handler SHOULD proceed even if the computer is shutting down
    [self performSelectorOnMainThread: @selector(installConfigurationsUpdateInBundleAtPath:)
                           withObject: path 
                        waitUntilDone: YES];
}

-(void) installConfigurationsUpdateInBundleAtPath: (NSString *) path
{
    if (  ! path  ) {
        NSLog(@"Configuration update installer: Not installing configurations update: Invalid path to update");
        return;
    }
    
    // Get version of bundle whose contents we are installing, so we can (later) update /Library/Application Support/.../Tunnelblick Configurations.bundle
    NSString * plistPath = [path stringByAppendingPathComponent: @"Contents/Info.plist"];
    NSDictionary * dict  = [NSDictionary dictionaryWithContentsOfFile: plistPath];
    NSString * version   = [dict objectForKey: @"CFBundleVersion"];
    if (  ! version  ) {
        NSLog(@"Configuration update installer: Not installing configurations update: No version information in %@", plistPath);
        return;
    }
    NSString * versionShortString = [dict objectForKey: @"CFBundleShortVersionString"];
    
    // Install the updated configurations
    BOOL gotMyAuth = FALSE;
    
    BOOL isDir;
    NSString * installFolder = [path stringByAppendingPathComponent: @"Contents/Resources/Install"];
    if (  [gFileMgr fileExistsAtPath: installFolder isDirectory: &isDir]
        && isDir  ) {
        // Install folder should consist of zero or more .tblks -- make an array of their paths
        NSMutableArray * paths = [NSMutableArray arrayWithCapacity: 16];
        NSString * fileName;
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: installFolder];
        while (  (fileName = [dirEnum nextObject])  ) {
            [dirEnum skipDescendents];
            NSString * fullPath = [installFolder stringByAppendingPathComponent: fileName];
            if (  itemIsVisible(fullPath)  ) {
                if (  [[fileName pathExtension] isEqualToString: @"tblk"]  ) {
                    [paths addObject: fullPath];
                } else {
                    NSLog(@"Configuration update installer: Item %@ is not a .tblk and has been ignored", fullPath);
                }
            }
        }
        
        if (  [paths count] != 0  ) {
            if ( ! gAuthorization  ) {
                NSString * msg = NSLocalizedString(@"Tunnelblick needs to install one or more Tunnelblick VPN Configurations.", @"Window text");
                gAuthorization = [NSApplication getAuthorizationRef: msg];
                gotMyAuth = TRUE;
            }
            
            if (  ! gAuthorization  ) {
                NSLog(@"Configuration update installer: The Tunnelblick installation was cancelled by the user.");
                return;
            }
            
            [self installTblks: paths skipConfirmationMessage: YES skipResultMessage: YES notifyDelegate: NO];   // Install .tblks
            
        } else {
            NSLog(@"Configuration update installer: Not installing update: No items to install in %@", installFolder);
            return;
        }
    } else {
        NSLog(@"Configuration update installer: Not installing update: %@ does not exist", installFolder);
        return;
    }
    
    // Set the version # in /Library/Application Support/Tunnelblick/Configuration Updates/Tunnelblick Configurations.bundle/Contents/Info.plist
    // and remove the bundle's Contents/Resources/Install folder that contains the updates so we don't update with them again
    if ( ! gAuthorization  ) {
        NSString * msg = NSLocalizedString(@"Tunnelblick needs to install one or more Tunnelblick VPN Configurations.", @"Window text");
        gAuthorization = [NSApplication getAuthorizationRef: msg];
        gotMyAuth = TRUE;
    }
    
    if (  ! gAuthorization  ) {
        NSLog(@"Configuration update installer: The Tunnelblick installation was cancelled by the user.");
        return;
    }
    
    NSString * masterPlistPath = [CONFIGURATION_UPDATES_BUNDLE_PATH stringByAppendingPathComponent: @"Contents/Info.plist"];

    NSString *launchPath = [[NSBundle mainBundle] pathForResource:@"installer" ofType:nil];
    NSArray * arguments = [NSArray arrayWithObjects: [NSString stringWithFormat: @"%u", INSTALLER_SET_VERSION], version, versionShortString, nil];
    
    BOOL okNow = FALSE; // Assume failure
    unsigned i;
    for (i=0; i<5; i++) {
        if (  i != 0  ) {
            usleep( i * 500000 );
            NSLog(@"Configuration update installer: Retrying execution of installer");
        }
        
        if (  [NSApplication waitForExecuteAuthorized: launchPath withArguments: arguments withAuthorizationRef: gAuthorization] ) {
            // Try for up to 6.35 seconds to verify that installer succeeded -- sleeping .05 seconds first, then .1, .2, .4, .8, 1.6,
            // and 3.2 seconds (totals 6.35 seconds) between tries as a cheap and easy throttling mechanism for a heavily loaded computer
            useconds_t sleepTime;
            for (sleepTime=50000; sleepTime < 7000000; sleepTime=sleepTime*2) {
                usleep(sleepTime);
                
                NSDictionary * masterDict = [NSDictionary dictionaryWithContentsOfFile: masterPlistPath];
                if (  (okNow = [version isEqualToString: [masterDict objectForKey: @"CFBundleVersion"]])  ) {
                    break;
                }
            }
            
            if (  okNow  ) {
                break;
            } else {
                NSLog(@"Configuration update installer: installer did not make the necessary changes");
            }
        } else {
            NSLog(@"Configuration update installer: Failed to execute %@: %@", launchPath, arguments);
        }
    }
    
    
    if (   ! okNow  ) {
        NSDictionary * masterDict = [NSDictionary dictionaryWithContentsOfFile: masterPlistPath];
        if (  ! [version isEqualToString: [masterDict objectForKey: @"CFBundleVersion"]]  ) {
            NSLog(@"Configuration update installer: Unable to update CFBundleVersion in %@", masterPlistPath);
        }
    }
    
    if (  gotMyAuth  ) {
        AuthorizationFree(gAuthorization, kAuthorizationFlagDefaults);
        gAuthorization = nil;
    }
}

// Invoked when the user double-clicks on one or more .tblk packages,
//                  or drags and drops one or more .tblk package(s) onto Tunnelblick
- (BOOL)application: (NSApplication * )theApplication
          openFiles: (NSArray * )filePaths
{
	(void) theApplication;
	
    return [self installTblks: filePaths skipConfirmationMessage: NO skipResultMessage: NO notifyDelegate: YES];
}


-(BOOL)            installTblks: (NSArray * )      filePaths
        skipConfirmationMessage: (BOOL)            skipConfirmMsg
              skipResultMessage: (BOOL)            skipResultMsg
                 notifyDelegate: (BOOL)            notifyDelegate {
    
    // If we have finished launching Tunnelblick, we open the file(s) now
    // otherwise the file(s) opening launched us, but we have not initialized completely.
    // so we store the paths and open the file(s) later, in applicationDidFinishLaunching.
	
    if (  launchFinished  ) {
        BOOL oldIgnoreNoConfigs = ignoreNoConfigs;
        ignoreNoConfigs = TRUE;
        [[ConfigurationManager defaultManager] openDotTblkPackages: filePaths
                                                         usingAuth: gAuthorization
                                           skipConfirmationMessage: skipConfirmMsg
                                                 skipResultMessage: skipResultMsg
                                                    notifyDelegate: notifyDelegate];
        ignoreNoConfigs = oldIgnoreNoConfigs;
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
    
	(void) notification;
	
    [myConfigUpdater setup];    // Set up to run the configuration updater

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
    
    // We set the Feed URL, even if we haven't run Sparkle yet (and thus haven't set our Sparkle preferences) because
    // the user may do a 'Check for Updates Now' on the first run, and we need to check with the correct Feed URL
    
    // If the 'updateFeedURL' preference is being forced, set the program update FeedURL from it
    if (  ! [gTbDefaults canChangeValueForKey: @"updateFeedURL"]  ) {
        feedURL = [gTbDefaults objectForKey: @"updateFeedURL"];
        if (  ! [[feedURL class] isSubclassOfClass: [NSString class]]  ) {
            NSLog(@"Ignoring 'updateFeedURL' preference from 'forced-preferences.plist' because it is not a string");
            feedURL = nil;
        }
    }
    // Otherwise, use the Info.plist entry. We don't check the normal preferences because an unprivileged user can set them and thus
    // could send the update check somewhere it shouldn't go. (For example, to force Tunnelblick to ignore an update.)
    
    if (  feedURL == nil  ) {
        NSString * contentsPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent: @"Contents"];
        NSDictionary * infoPlist = [NSDictionary dictionaryWithContentsOfFile: [contentsPath stringByAppendingPathComponent: @"Info.plist"]];
        feedURL = [infoPlist objectForKey: @"SUFeedURL"];
        if (  feedURL == nil ) {
            NSLog(@"Missing 'SUFeedURL' item in Info.plist");
        } else {
            if (  ! [[feedURL class] isSubclassOfClass: [NSString class]]  ) {
                NSLog(@"Ignoring 'SUFeedURL' item in Info.plist because it is not a string");
                feedURL = nil;
            }
        }
    }
    
    if (  feedURL != nil  ) {
        if (  [updater respondsToSelector: @selector(setFeedURL:)]  ) {
            NSURL * url = [NSURL URLWithString: feedURL];
            if ( url  ) {
                [updater setFeedURL: url];
                NSLog(@"Set program update feedURL to %@", feedURL);
            } else {
                feedURL = nil;
                NSLog(@"Not setting program update feedURL because the string '%@' could not be converted to a URL", feedURL);
            }
        } else {
            feedURL = nil;
            NSLog(@"Not setting program update feedURL because Sparkle Updater does not respond to setFeedURL:");
        }
    }
    
    // Set up automatic update checking
    if (  [updater respondsToSelector: @selector(setAutomaticallyChecksForUpdates:)]  ) {
        if (  userIsAdminOrNonAdminsCanUpdate  ) {
            if (  [gTbDefaults objectForKey: @"updateCheckAutomatically"]  ) {
                [updater setAutomaticallyChecksForUpdates: [gTbDefaults boolForKey: @"updateCheckAutomatically"]];
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
                [updater setAutomaticallyDownloadsUpdates: [gTbDefaults boolForKey: @"updateAutomatically"]];
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
            if (   [[checkInterval class] isSubclassOfClass: [NSNumber class]]
                || [[checkInterval class] isSubclassOfClass: [NSString class]]  ) {
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

-(BOOL) hasValidSignature
{
    if (  ! runningOnLeopardOrNewer()  ) {              // If on Tiger, we can't check the signature, so pretend it is valid
        return TRUE;
    }
    
    // Normal versions of Tunnelblick can be checked with codesign running as the user
    //
    // But Deployed versions need to run codesign as root, so codesign will "see" the .tblk contents that
    // are owned by root and not accessible to other users (like keys and certificates)
    //
    // "openvpnstart checkSignature" runs codesign as root, but it can only be used if openvpnstart has been set SUID by the
    // installation process.
    //
    // So if a Deployed Tunnelblick hasn't been installed yet (e.g., it is running from .dmg), we don't check the signature here.
    //
    // There could be a separate check for an invalid signature in installer, when it is not run from /Applications, since it could run
    // codesign as root using the installer's authorization. However, installer runs without a UI, so it is complicated to provide the ability
    // to report a failure and provide the option to continue. Considering that the first run after installation will catch an invalid
    // signature, this separate check has a low priority.
    
    NSString * appPath = [[NSBundle mainBundle] bundlePath];
    
    if (  [gFileMgr fileExistsAtPath: gDeployPath]  ) {
        NSString * appContainer = [appPath stringByDeletingLastPathComponent];
        if (  ! [appContainer isEqualToString: @"/Applications"]  ) {
            // Deployed but not in /Applications
            // Return TRUE because we must check the signature as root but we can't because openvpnstart isn't suid
            return YES;
        }
        
        // Deployed and in /Applications, so openvpnstart has SUID root, so we can run it to check the signature
        OSStatus status = runOpenvpnstart([NSArray arrayWithObject: @"checkSignature"], nil, nil);
        return (status == EXIT_SUCCESS);
    }
    
    // Not a Deployed version of Tunnelblick, so we can run codesign as the user
    if (  ! [gFileMgr fileExistsAtPath: TOOL_PATH_FOR_CODESIGN]  ) {  // If codesign binary doesn't exist, complain and assume it is NOT valid
        NSLog(@"Assuming digital signature invalid because '%@' does not exist", TOOL_PATH_FOR_CODESIGN);
        return FALSE;
    }
    
    NSArray *arguments = [NSArray arrayWithObjects:@"-v", appPath, nil];
    
    NSTask* task = [[[NSTask alloc] init] autorelease];
    [task setCurrentDirectoryPath: @"/tmp"];    // Won't be used, but we should specify something
    [task setLaunchPath: TOOL_PATH_FOR_CODESIGN];
    [task setArguments:arguments];
    [task launch];
    [task waitUntilExit];
    OSStatus status = [task terminationStatus];
    return (status == EXIT_SUCCESS);
}

- (NSURL *) getIPCheckURL
{
    NSURL * url = nil;
    NSString * urlString;
	id obj = [gTbDefaults objectForKey: @"IPCheckURL"];
	if (   obj
		&& [[obj class] isSubclassOfClass: [NSString class]]
		&& ( ! [gTbDefaults canChangeValueForKey: @"IPCheckURL"])  ) {
		urlString = (NSString *) obj;
	} else {
        NSDictionary * infoPlist = [[NSBundle mainBundle] infoDictionary];
        urlString = [infoPlist objectForKey: @"IPCheckURL"];
    }
    
    if (  urlString  ) {
        url = [NSURL URLWithString: urlString];
        if (  ! url  ) {
            NSLog(@"Unable to make into a URL: %@", urlString);
        }
    } else {
        NSLog(@"No IPCheckURL forced preference or Info.plist entry");
    }
    
    return url;
}

-(BOOL)applicationShouldHandleReopen: (NSApplication *) theApp hasVisibleWindows: (BOOL) hasWindows
{
	// Invoked when the Dock item is clicked to relaunch Tunnelblick, or it is double-clicked.
	// Just show the VPN Details… window.
	
	(void) theApp;
	(void) hasWindows;
	
	[self openPreferencesWindow: self];
	return NO;
}

- (void) applicationDidFinishLaunching: (NSNotification *)notification
{
	(void) notification;
	
	[NSApp callDelegateOnNetworkChange: NO];
    [self installSignalHandler];    
    
    // If checking for updates is enabled, we do a check every time Tunnelblick is launched (i.e., now)
    // We also check for updates if we haven't set our preferences yet. (We have to do that so that Sparkle
    // will ask the user whether to check or not, then we set our preferences from that.)
    if (      [gTbDefaults boolForKey:   @"updateCheckAutomatically"]
        || (  [gTbDefaults objectForKey: @"updateCheckAutomatically"] == nil  )
        ) {
        if (  [updater respondsToSelector: @selector(checkForUpdatesInBackground)]  ) {
            if (  feedURL != nil  ) {
                [updater checkForUpdatesInBackground];
            } else {
                NSLog(@"Not checking for updates because no FeedURL has been set");
            }
        } else {
            NSLog(@"Cannot check for updates because Sparkle Updater does not respond to checkForUpdatesInBackground");
        }
    }
    
    // Install configuration updates if any are available
    NSString * installFolder = [CONFIGURATION_UPDATES_BUNDLE_PATH stringByAppendingPathComponent: @"Contents/Resources/Install"];
    if (  [gFileMgr fileExistsAtPath: installFolder]  ) {
        BOOL oldLaunchFinished = launchFinished;    // Fake out installTblks so it installs the .tblk(s) immediately
        launchFinished = TRUE;
        [self installConfigurationsUpdateInBundleAtPath: CONFIGURATION_UPDATES_BUNDLE_PATH];
        launchFinished = oldLaunchFinished;
    }
    
    if (  dotTblkFileList  ) {
        BOOL oldIgnoreNoConfigs = ignoreNoConfigs;
        ignoreNoConfigs = TRUE;
        NSString * text = NSLocalizedString(@"Installing Tunnelblick VPN Configurations...", @"Window text");
        [splashScreen setMessage: text];

        [[ConfigurationManager defaultManager] openDotTblkPackages: dotTblkFileList
                                                         usingAuth: gAuthorization
                                           skipConfirmationMessage: YES
                                                 skipResultMessage: YES
                                                    notifyDelegate: YES];
        text = NSLocalizedString(@"Installation finished successfully.", @"Window text");
        [splashScreen setMessage: text];

        ignoreNoConfigs = oldIgnoreNoConfigs;
    }
    
    [myConfigUpdater startWithUI: NO];    // Start checking for configuration updates in the background (when the application updater is finished)
    
    // Set up to monitor configuration folders
    myQueue = [UKKQueue sharedFileWatcher];
    if (  ! [gTbDefaults boolForKey:@"doNotMonitorConfigurationFolder"]  ) {
        unsigned i;
        for (i = 0; i < [gConfigDirs count]; i++) {
            [self addPath: [gConfigDirs objectAtIndex: i] toMonitorQueue: myQueue];
        }
    }
    [myQueue setDelegate: self];
    [myQueue setAlwaysNotify: YES];
    
    [self activateStatusMenu];
    
    ignoreNoConfigs = NO;    // We should NOT ignore the "no configurations" situation
    
    [self checkNoConfigurations];

    [self hookupToRunningOpenVPNs];
    [self setupHookupWatchdogTimer];
    
    // Make sure the '-onSystemStart' preferences for all connections are consistent with the /Library/LaunchDaemons/...plist file for the connection
    NSEnumerator * connEnum = [[self myVPNConnectionDictionary] objectEnumerator];
    VPNConnection * connection;
    while (  (connection = [connEnum nextObject])  ) {
        if (  ! [connection tryingToHookup]  ) {
            [logScreen validateWhenConnectingForConnection: connection];
        }
    }
    
    // Make sure we have asked the user if we can check the IP info
    if (  ! [gTbDefaults boolForKey: @"askedUserIfOKToCheckThatIPAddressDidNotChangeAfterConnection"]  ) {
        if (  [gTbDefaults canChangeValueForKey: @"notOKToCheckThatIPAddressDidNotChangeAfterConnection"]  ) {
            NSURL * url = [self getIPCheckURL];
            if (  url  ) {
				NSString * host = [url host];
				if (  host  ) {
					int result = TBRunAlertPanel(NSLocalizedString(@"New Feature", @"Window title"),
												 [NSString stringWithFormat:
												  NSLocalizedString(@"Tunnelblick can check that the apparent public IP address of your computer"
																	@" changes when you connect to a VPN, and warn you if it doesn't.\n\n"
																	@"This may help Tunnelblick diagnose problems with your connection.\n\n"
																	@"This process attempts to access\n"
																	@"%@\n\n"
																	@"Do you wish to check for this IP address change?\n", @"Window text"), host],
												 NSLocalizedString(@"Check for a change", @"Button"),           // Default
												 NSLocalizedString(@"Do not check for a change", @"Button"),    // Alternate
												 nil);
                    // Only check for change if requested (not if error)
					[gTbDefaults setBool: (result != NSAlertDefaultReturn)
								  forKey: @"notOKToCheckThatIPAddressDidNotChangeAfterConnection"];
					[gTbDefaults setBool: YES
								  forKey: @"askedUserIfOKToCheckThatIPAddressDidNotChangeAfterConnection"];
				} else {
					NSLog(@"Could not extract host from URL: %@", url);
				}
            }
        }
    }
    
    activeIPCheckThreads = [[NSMutableArray alloc] initWithCapacity: 4];
    cancellingIPCheckThreads = [[NSMutableArray alloc] initWithCapacity: 4];
    
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
                [self terminateBecause: terminatingBecauseOfError];
            }
        }
    }

    // Process connections that should be restored on relaunch (from updating configurations)
    VPNConnection * myConnection;
    NSArray * restoreList = [gTbDefaults objectForKey: @"connectionsToRestoreOnLaunch"];
    if (   restoreList
        && ( [restoreList count] != 0 )  ) {
        NSString * dispNm;
        NSEnumerator * listEnum = [restoreList objectEnumerator];
        while (  (dispNm = [listEnum nextObject])  ) {
            myConnection = [[self myVPNConnectionDictionary] objectForKey: dispNm];
            if (   myConnection
                && ( ! [myConnection isConnected] )  ) {
                [myConnection connect:self userKnows: YES];
            }
        }
        [gTbDefaults removeObjectForKey: @"connectionsToRestoreOnLaunch"];
        [gTbDefaults synchronize];
    }
    
    // Process "Automatically connect on launch" checkboxes (but skip any that were restored on relaunch above)
    NSString * dispNm;
    NSEnumerator * e = [[self myConfigDictionary] keyEnumerator];
    while (   (dispNm = [e nextObject])
           && (   (! restoreList)
               || ( [restoreList indexOfObject: dispNm] == NSNotFound) )  ) {
        myConnection = [[self myVPNConnectionDictionary] objectForKey: dispNm];
        if (  [gTbDefaults boolForKey: [dispNm stringByAppendingString: @"autoConnect"]]  ) {
            if (  ! [gTbDefaults boolForKey: [dispNm stringByAppendingString: @"-onSystemStart"]]  ) {
                if (  ![myConnection isConnected]  ) {
                    [myConnection connect:self userKnows: YES];
                }
            }
        }
    }
    
	if (  ! [gTbDefaults boolForKey: @"doNotLaunchOnLogin"]  ) {
		[NSApp setAutoLaunchOnLogin: YES];
	}
	
    unsigned kbsIx = [gTbDefaults unsignedIntForKey: @"keyboardShortcutIndex"
                                            default: 1 /* F1     */
                                                min: 0 /* (none) */
                                                max: MAX_HOTKEY_IX];
    
    [self setHotKeyIndex: kbsIx];
    
    // Install easy-rsa if it isn't installed already, or update it if appropriate
    installOrUpdateOurEasyRsa();
    
    AuthorizationFree(gAuthorization, kAuthorizationFlagDefaults);
    gAuthorization = nil;
    
#ifdef INCLUDE_VPNSERVICE
    if (  vpnService = [[VPNService alloc] init]  ) {
        if (  [vpnService respondsToSelector: @selector(showOnLaunchScreen)]) {
            [vpnService showOnLaunchScreen];
        } else {
            NSLog(@"VPNService enabled but vpnService object does not respond to showOnLaunchScreen");
        }
    } else {
        NSLog(@"VPNService enabled but vpnService object is NULL");
    }
#endif
    
    NSString * prefVersion = [gTbDefaults objectForKey: @"openvpnVersion"];
    if (   prefVersion
        && ( ! [prefVersion isEqualToString: @"-"] )  ) {
        NSArray * versions = availableOpenvpnVersions();
        if (  [versions count] == 0  ) {
            NSLog(@"Tunnelblick does not include any versions of OpenVPN");
            [self terminateBecause: terminatingBecauseOfError];
            return;
        }
        if (  ! [versions containsObject: prefVersion]  ) {
            NSString * useVersion = [versions lastObject];
            TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                            [NSString stringWithFormat: NSLocalizedString(@"OpenVPN version %@ is not available. Using the latest, version %@", @"Window text"),
                             prefVersion, useVersion],
                            nil, nil, nil);
            [gTbDefaults setObject: @"-" forKey: @"openvpnVersion"];
        }
    }
    
    // Add this Tunnelblick version to the start of the tunnelblickVersionHistory preference array if it isn't already the first entry
    NSDictionary * infoPlist = [[NSBundle mainBundle] infoDictionary];
    NSString * thisVersion = [infoPlist objectForKey: @"CFBundleShortVersionString"];
    if (  thisVersion  ) {
        BOOL dirty = FALSE;
        NSMutableArray * versions = [[[gTbDefaults objectForKey: @"tunnelblickVersionHistory"] mutableCopy] autorelease];
        if (  ! versions  ) {
            versions = [[[NSArray array] mutableCopy] autorelease];
            dirty = TRUE;
        }
        
        if (   (  [versions count] == 0  )
            || (! [[versions objectAtIndex: 0] isEqualToString: thisVersion])  ) {
            [versions insertObject: thisVersion atIndex: 0];
            dirty = TRUE;
        }

        while (  [versions count] > MAX_VERSIONS_IN_HISTORY  ) {
            [versions removeLastObject];
            dirty = TRUE;
        }
        
        if (  dirty  ) {
            [gTbDefaults setObject: versions forKey: @"tunnelblickVersionHistory"];
        }
    }
    
	[[self ourMainIconView] setOrRemoveTrackingRect];
    
    NSString * text = NSLocalizedString(@"Tunnelblick is ready.", @"Window text");
    [splashScreen setMessage: text];

    [splashScreen fadeOutAndClose];
    
	[self showWelcomeScreen];
	
    launchFinished = TRUE;
}

-(NSString *) fileURLStringWithPath: (NSString *) path
{
    NSString * urlString = [@"file://" stringByAppendingString: path];
    return urlString;
}

-(void) showWelcomeScreen
{
	if (  [gTbDefaults boolForKey: @"skipWelcomeScreen"]  ) {
		return;
	}
	
    NSString * welcomeURLString = nil;
    NSString * welcomeIndexFile = [[gDeployPath
                                    stringByAppendingPathComponent: @"Welcome"]
                                   stringByAppendingPathComponent: @"index.html"];
    BOOL isDir;
    if (   [gFileMgr fileExistsAtPath: welcomeIndexFile isDirectory: &isDir]
        && ( ! isDir )  ) {
        welcomeURLString = [self fileURLStringWithPath: welcomeIndexFile];
    } else if (  ! [gTbDefaults canChangeValueForKey: @"welcomeURL"]  ) {
        welcomeURLString = [gTbDefaults objectForKey: @"welcomeURL"];
    }
	
	if (  ! welcomeURLString  ) {
		return;
	}
    
    float welcomeWidth  = 500.0;
    NSNumber * num = [gTbDefaults objectForKey: @"welcomeWidth"];
    if (   num
        && [num respondsToSelector: @selector(floatValue)]  ) {
        welcomeWidth = [num floatValue];
    }
    float welcomeHeight = 500.0;
    num = [gTbDefaults objectForKey: @"welcomeHeight"];
    if (   num
        && [num respondsToSelector: @selector(floatValue)]  ) {
        welcomeHeight = [num floatValue];
    }
    
    BOOL showCheckbox = ! [gTbDefaults boolForKey: @"doNotShowWelcomeDoNotShowAgainCheckbox"];
	
    welcomeScreen = [[[WelcomeController alloc]
					  initWithDelegate: self
					  urlString: welcomeURLString
					  windowWidth: welcomeWidth
					  windowHeight: welcomeHeight
					  showDoNotShowAgainCheckbox: showCheckbox] retain];
	
	[welcomeScreen showWindow: self];
}

-(void) welcomeOKButtonWasClicked
{
	[[welcomeScreen window] close];
    [welcomeScreen release];
    welcomeScreen = nil;
}

// Returns TRUE if a hookupWatchdog timer was created or already exists
-(BOOL) setupHookupWatchdogTimer
{
    if (  hookupWatchdogTimer  ) {
        return TRUE;
    }
    
    
    gHookupTimeout = [gTbDefaults unsignedIntForKey: @"hookupTimeout"
                                            default: 5
                                                min: 0
                                                max: 300];
    if (  gHookupTimeout == 0) {
        return FALSE;
    }
    
    hookupWatchdogTimer = [NSTimer scheduledTimerWithTimeInterval: (NSTimeInterval) gHookupTimeout
                                                           target: self
                                                         selector: @selector(hookupWatchdogHandler)
                                                         userInfo: nil
                                                          repeats: NO];
    return TRUE;
}

-(void) changedMonitorConfigurationFoldersSettings
{
    if (  [gTbDefaults boolForKey: @"doNotMonitorConfigurationFolder"]  ) {
        unsigned i;
        for (i = 0; i < [gConfigDirs count]; i++) {
            [[NSApp delegate] removePath: [gConfigDirs objectAtIndex: i] fromMonitorQueue: myQueue];
        }
    } else {
        unsigned i;
        for (i = 0; i < [gConfigDirs count]; i++) {
            [[NSApp delegate] addPath: [gConfigDirs objectAtIndex: i] toMonitorQueue: myQueue];
        }
        [self activateStatusMenu];
    }
}

-(void) addPath: (NSString *) path toMonitorQueue: (UKKQueue *) queue
{
    // Add the path itself
    [queue addPathToQueue: path];

    // Add folders and subfolders
    NSString * file;
    BOOL isDir;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: path];
    while (  (file = [dirEnum nextObject])  ) {
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
    while (  (file = [dirEnum nextObject])  ) {
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
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    hookupWatchdogTimer = nil;  // NSTimer invalidated it and takes care of releasing it
	[self performSelectorOnMainThread: @selector(hookupWatchdog) withObject: nil waitUntilDone: NO];
}

-(void) hookupWatchdog
{
    // Remove process IDs from the pIDsWeAreTryingToHookUpTo list for connections that have hooked up successfully
    VPNConnection * connection;
    NSEnumerator * connEnum = [[self myVPNConnectionDictionary] objectEnumerator];
    while (  (connection = [connEnum nextObject])  ) {
        if (  [connection isHookedup]  ) {
            pid_t thePid = [connection pid];
            if (  thePid != 0  ) {
                NSNumber * processId = [NSNumber numberWithInt: (int) thePid];
                if (  [pIDsWeAreTryingToHookUpTo containsObject: processId]  ) {
                    [pIDsWeAreTryingToHookUpTo removeObject: processId];
                }
            }
        } else {
            [connection stopTryingToHookup];
        }
    }
    
   if (  [pIDsWeAreTryingToHookUpTo count]  ) {
	   if (  ALLOW_OPENVPNSTART_KILL  ) {
		   int result = TBRunAlertPanelExtended(NSLocalizedString(@"Warning: Unknown OpenVPN processes", @"Window title"),
												NSLocalizedString(@"One or more OpenVPN processes are running but are unknown to Tunnelblick. If you are not running OpenVPN separately from Tunnelblick, this usually means that an earlier launch of Tunnelblick was unable to shut them down properly and you should terminate them. They are likely to interfere with Tunnelblick's operation. Do you wish to terminate them?", @"Window text"),
												NSLocalizedString(@"Ignore", @"Button"),
												NSLocalizedString(@"Terminate", @"Button"),
												nil,
												@"skipWarningAboutUnknownOpenVpnProcesses",
												NSLocalizedString(@"Do not ask again, always 'Ignore'", @"Checkbox name"),
												nil,
												NSAlertDefaultReturn);
		   if (  result == NSAlertAlternateReturn  ) {
			   NSNumber * pidNumber;
			   NSEnumerator * pidsEnum = [pIDsWeAreTryingToHookUpTo objectEnumerator];
			   while (  (pidNumber = [pidsEnum nextObject])  ) {
				   NSString * pidString = [NSString stringWithFormat: @"%d", [pidNumber intValue]];
				   NSArray  * arguments = [NSArray arrayWithObjects:@"kill", pidString, nil];
				   runOpenvpnstart(arguments, nil, nil);
				   noUnknownOpenVPNsRunning = YES;
			   }
		   } else if (result == NSAlertErrorReturn  ) {
               NSLog(@"Ignoring error return from TBRunAlertPanelExtended; not killing unknown OpenVPN processes");
           }
	   } else if (  ALLOW_OPENVPNSTART_KILLALL  ) {
		   int result = TBRunAlertPanelExtended(NSLocalizedString(@"Warning: Unknown OpenVPN processes", @"Window title"),
												NSLocalizedString(@"One or more OpenVPN processes are running but are unknown to Tunnelblick. If you are not running OpenVPN separately from Tunnelblick, this usually means that an earlier launch of Tunnelblick was unable to shut them down properly and you should terminate them. They are likely to interfere with Tunnelblick's operation. Do you wish to terminate all OpenVPN processes?", @"Window text"),
												NSLocalizedString(@"Ignore", @"Button"),
												NSLocalizedString(@"Terminate All OpenVPN processes", @"Button"),
												nil,
												@"skipWarningAboutUnknownOpenVpnProcesses",
												NSLocalizedString(@"Do not ask again, always 'Ignore'", @"Checkbox name"),
												nil,
												NSAlertDefaultReturn);
		   if (  result == NSAlertAlternateReturn  ) {
               NSArray  * arguments = [NSArray arrayWithObject:@"killall"];
               runOpenvpnstart(arguments, nil, nil);
               noUnknownOpenVPNsRunning = YES;
		   } else if (result == NSAlertErrorReturn  ) {
               NSLog(@"Ignoring error return from TBRunAlertPanelExtended; not killing unknown OpenVPN processes");
           }
       } else {
		   TBRunAlertPanel(NSLocalizedString(@"Warning: Unknown OpenVPN processes", @"Window title"),
						   NSLocalizedString(@"One or more OpenVPN processes are running but are unknown"
											 @" to Tunnelblick. If you are not running OpenVPN separately"
											 @" from Tunnelblick, this usually means that an earlier"
											 @" launch of Tunnelblick was unable to shut them down"
											 @" properly and you should terminate them. They are likely"
											 @" to interfere with Tunnelblick's operation.\n\n"
											 @"They can be terminated in the 'Activity Monitor' application.\n\n", @"Window text"),
						   nil, nil, nil);
		   noUnknownOpenVPNsRunning = NO;
	   }
   } else {
	   noUnknownOpenVPNsRunning = YES;
   }
	
    [self reconnectAfterBecomeActiveUser];  // Now that we've hooked up everything we can, connect anything else we need to
}

-(void) saveConnectionsToRestoreOnRelaunch
{
    NSMutableArray * restoreList = [NSMutableArray arrayWithCapacity: 8];
    NSEnumerator * connEnum = [[self connectionArray] objectEnumerator];
    VPNConnection * connection;
    while (  (connection = [connEnum nextObject])  ) {
        NSString* autoConnectKey   = [[connection displayName] stringByAppendingString: @"autoConnect"];
        NSString* onSystemStartKey = [[connection displayName] stringByAppendingString: @"-onSystemStart"];
        if (  ! (   [gTbDefaults boolForKey: autoConnectKey]
                 && [gTbDefaults boolForKey: onSystemStartKey] )  ) {
            [restoreList addObject: [connection displayName]];
        }
    }
    
    if (  [restoreList count] != 0) {
        [gTbDefaults setObject: restoreList forKey: @"connectionsToRestoreOnLaunch"];
        [gTbDefaults synchronize];
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
        
        unsigned nConfigurations    = [[self myConfigDictionary] count];
        unsigned nModifyNameserver  = 0;
        unsigned nMonitorConnection = 0;
        unsigned nPackages          = 0;
        
        NSString * key;
        NSString * path;
        
        // Count # of .tblk packages
        NSEnumerator * e = [[self myConfigDictionary] objectEnumerator];
        while (  (path = [e nextObject])  ) {
            NSString * last = lastPartOfPath(path);
            NSString * firstComponent = firstPathComponent(last);
            if (  [[firstComponent pathExtension] isEqualToString: @"tblk"]  ) {
                nPackages++;
            }
        }
        
        // Count # of configurations with 'Set nameserver' checked and the # with 'Monitor connection' set
        e = [[self myConfigDictionary] keyEnumerator];
        while (  (key = [e nextObject])  ) {
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
                 @"nConn",   @"key", sConn, @"value", NSLocalizedString(@"Configurations",      @"Window text" ), @"displayKey", sConn, @"displayValue", nil],
                [NSDictionary dictionaryWithObjectsAndKeys:
                 @"nSetDNS", @"key", sSN,   @"value", NSLocalizedString(@"Set nameserver",      @"PopUpButton" ), @"displayKey", sSN,   @"displayValue", nil],
                [NSDictionary dictionaryWithObjectsAndKeys:
                 @"nPkgs  ", @"key", sPkg,  @"value", NSLocalizedString(@"VPN Connections",     @"Window text" ), @"displayKey", sPkg,  @"displayValue", nil],
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

// Sparkle delegate:
- (void)updater:(SUUpdater *)theUpdater willInstallUpdate:(SUAppcastItem *)update
{
	(void) theUpdater;
	(void) update;
	
	[gTbDefaults removeObjectForKey: @"skipWarningAboutInvalidSignature"];
	[gTbDefaults removeObjectForKey: @"skipWarningAboutNoSignature"];
	
	reasonForTermination = terminatingBecauseOfQuit;
    
    [NSApp setAutoLaunchOnLogin: NO];
    terminatingAtUserRequest = TRUE;

    NSLog(@"updater:willInstallUpdate: Starting cleanup.");
    if (  [self cleanup]  ) {
        NSLog(@"updater:willInstallUpdate: Cleanup finished.");
    } else {
        NSLog(@"updater:willInstallUpdate: Cleanup already being done.");
    }
    
    // DO NOT UNLOCK cleanupMutex --
    // We do not want to execute cleanup a second time, because:
    //     (1) We've already just run it and thus cleaned up everything, and
    //     (2) The newly-installed openvpnstart won't be secured and thus will fail
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


-(void) setPIDsWeAreTryingToHookUpTo: (NSArray *) newValue
{
    if (  pIDsWeAreTryingToHookUpTo != newValue) {
        [pIDsWeAreTryingToHookUpTo release];
        pIDsWeAreTryingToHookUpTo = [newValue mutableCopy];
    }
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
//
// Returns TRUE if started trying to hook up to one or more running OpenVPN processes

-(BOOL) hookupToRunningOpenVPNs
{
    BOOL tryingToHookupToOpenVPN = FALSE;
    
    [self setPIDsWeAreTryingToHookUpTo: [NSApp pIdsForOpenVPNMainProcesses]];
    if (  [pIDsWeAreTryingToHookUpTo count] != 0  ) {
        NSString * filename;
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: L_AS_T_LOGS];
        while (  (filename = [dirEnum nextObject])  ) {
            [dirEnum skipDescendents];
            NSString * oldFullPath = [L_AS_T_LOGS stringByAppendingPathComponent: filename];
            if (  [[filename pathExtension] isEqualToString: @"log"]) {
                if (  [[[filename stringByDeletingPathExtension] pathExtension] isEqualToString: @"openvpn"]) {
                    unsigned port = 0;
                    NSString * startArguments = nil;
                    NSString * cfgPath = [self deconstructOpenVPNLogPath: oldFullPath
                                                                  toPort: &port
                                                             toStartArgs: &startArguments];
                    NSArray * keysForConfig = [[self myConfigDictionary] allKeysForObject: cfgPath];
                    unsigned long keyCount = [keysForConfig count];
                    if (  keyCount == 0  ) {
                        NSLog(@"No keys in myConfigDictionary for %@", cfgPath);
                    } else {
                        if (  keyCount != 1  ) {
                            NSLog(@"Using first of %ld keys in myConfigDictionary for %@", keyCount, cfgPath);
                        }
                        NSString * displayName = [keysForConfig objectAtIndex: 0];
                        VPNConnection * connection = [[self myVPNConnectionDictionary] objectForKey: displayName];
                        if (  connection  ) {
                            [connection tryToHookupToPort: port withOpenvpnstartArgs: startArguments];
                            tryingToHookupToOpenVPN = TRUE;
                        }
                    }
                }
            }
        }
    }
    
    return tryingToHookupToOpenVPN;
}

// Returns a configuration path (and port number and the starting arguments from openvpnstart) from a path created by openvpnstart
-(NSString *) deconstructOpenVPNLogPath: (NSString *) logPath toPort: (unsigned *) portPtr toStartArgs: (NSString * *) startArgsPtr
{
    NSString * prefix = [NSString stringWithFormat:@"%@/", L_AS_T_LOGS];
    NSString * suffix = @".openvpn.log";
    if (  [logPath hasPrefix: prefix]  ) {
        if (  [logPath hasSuffix: suffix]  ) {
            unsigned prefixLength = [prefix length];
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
                
                *portPtr = (unsigned)port;
                
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

BOOL warnAboutNonTblks(void)
{
	// Returns TRUE if there were any private non-tblks and the user has agreed to convert them

	if (  anyNonTblkConfigs() ) {
		int response = TBRunAlertPanelExtended(NSLocalizedString(@"Tunnelblick VPN Configuration Installation", @"Window title"),
											   NSLocalizedString(@"You have one or more OpenVPN configurations that will not be available"
                                                                 @" when using this version of Tunnelblick. You can:\n\n"
																 @"     • Let Tunnelblick convert these OpenVPN configurations to Tunnelblick VPN Configurations; or\n"
                                                                 @"     • Quit and install a different version of Tunnelblick; or\n"
                                                                 @"     • Ignore this and continue without converting.\n\n"
                                                                 @"If you choose 'Ignore' the configurations will not be available!\n\n", @"Window text"),
											   NSLocalizedString(@"Convert Configurations", @"Button"), // Default return
											   NSLocalizedString(@"Ignore", @"Button"),                 // Alternate return
											   NSLocalizedString(@"Quit", @"Button"),                   // Other return
											   @"skipWarningAboutConvertingToTblks",
											   NSLocalizedString(@"Do not ask again, always convert", @"Checkbox name"),
											   nil,
											   NSAlertDefaultReturn);
		gUserWasAskedAboutConvertNonTblks = TRUE;
		if (   (response == NSAlertOtherReturn)
            || (response == NSAlertErrorReturn)  ) {  // Quit if "Quit" or error
			[[NSApp delegate] terminateBecause: terminatingBecauseOfQuit];
		}
		
		if (  response == NSAlertDefaultReturn  ) {
			return YES;
		}
        
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick VPN Configuration Installation", @"Window title"),
                        NSLocalizedString(@"Are you sure you do not want to convert OpenVPN configurations to Tunnelblick VPN Configurations?\n\n"
                                          @"CONFIGURATIONS WILL NOT BE AVAILABLE IF YOU DO NOT CONVERT THEM!\n\n", @"Window text"),
                        NSLocalizedString(@"Convert Configurations", @"Button"), // Default return
                        NSLocalizedString(@"Ignore", @"Button"),                 // Alternate return
                        NSLocalizedString(@"Quit", @"Button"));                  // Other return
		if (  response == NSAlertOtherReturn  ) {
			[[NSApp delegate] terminateBecause: terminatingBecauseOfQuit];
		}
		
		if (  response == NSAlertDefaultReturn  ) {
			return YES;
		}
        
        // "Ignore" or error occured: fall through to ignore
	}
	
	return NO;
}

-(void) initialChecks: (NSString *) ourAppName
{
    [NSApp setAutoLaunchOnLogin: NO];
    
#ifdef TBDebug
	(void) ourAppName;
#else
	if (  tunnelblickTestDeployed()  ) {
		NSDictionary * bundleInfoDict = [[NSBundle mainBundle] infoDictionary];
		if (  ! bundleInfoDict  ) {
			TBRunAlertPanel(NSLocalizedString(@"System Requirements Not Met", @"Window title"),
							NSLocalizedString(@"This 'Deployed' version of Tunnelblick cannot be launched or installed because it"
											  @" does not have an Info.plist.\n\n", @"Window text"),
							nil,nil,nil);
			[self terminateBecause: terminatingBecauseOfQuit];
		}
		
		NSString * ourBundleIdentifier = [bundleInfoDict objectForKey: @"CFBundleIdentifier"];
		
		NSString * ourUpdateFeedURLString;
		if (  ! [gTbDefaults canChangeValueForKey: @"updateFeedURL"]  ) {
			ourUpdateFeedURLString = [gTbDefaults objectForKey: @"updateFeedURL"];
		} else {
			ourUpdateFeedURLString = [bundleInfoDict objectForKey: @"SUFeedURL"];
		}
		
		NSString * ourExecutable = [bundleInfoDict objectForKey: @"CFBundleExecutable"];
		
        // PLEASE DO NOT REMOVE THE FOLLOWING REBRANDING CHECKS!
        //
        // Running a Deployed version of Tunnelblick without rebranding it can lead to unpredictable behavior,
        // may be less secure, can lead to problems with updating, and can interfere with other installations
        // of Tunnelblick on the same computer. Please don't do it!
        //
        // For instructions on rebranding Tunnelblick, see https://code.google.com/p/tunnelblick/wiki/cRebranding
        
		if (   [@"Tunnelblick" isEqualToString: @"T" @"unnelblick"] // Quick rebranding checks (not exhaustive, obviously)
			
            || ( ! ourAppName )
			|| [ourAppName     isEqualToString: @"Tunnelbl" @"ick"]
			
			|| ( ! ourExecutable )
			|| [ourExecutable  isEqualToString: @"Tun" @"nelblick"]
            
            || ( ! ourBundleIdentifier )
			|| ([ourBundleIdentifier    rangeOfString: @"net.tunnelb" @"lick."].length != 0)
			
			|| ( ! ourUpdateFeedURLString )
			|| ([ourUpdateFeedURLString rangeOfString: @"tu" @"nnelblick.net" ].length != 0)
			) {
			TBRunAlertPanel(NSLocalizedString(@"System Requirements Not Met", @"Window title"),
							NSLocalizedString(@"This 'Deployed' version of Tunnelblick cannot be  launched or installed because it"
											  @" has not been rebranded, or updateFeedURL or SUFeedURL are missing or contain 'tu" @"nnelbli" @"ck.net',"
											  @" or CFBundleIdentifier is missing or contains 'net.tunnelbl" @"ick'.\n\n", @"Window text"),
							nil,nil,nil);
			[self terminateBecause: terminatingBecauseOfQuit];
		}
        
        NSURL * ourUpdateFeedURL = [NSURL URLWithString: ourUpdateFeedURLString];
        if (  ! ourUpdateFeedURL  ) {
            TBRunAlertPanel(NSLocalizedString(@"System Requirements Not Met", @"Window title"),
                            NSLocalizedString(@"This version of Tunnelblick cannot be launched or installed because"
                                              @" it has an invalid update URL.\n\n", @"Window text"),
                            nil,nil,nil);
			[self terminateBecause: terminatingBecauseOfQuit];
        }
	} else if (  tunnelblickTestHasDeployBackups()  ) {
		
		TBRunAlertPanel(NSLocalizedString(@"System Requirements Not Met", @"Window title"),
						NSLocalizedString(@"This version of Tunnelblick cannot be launched or installed because"
										  @" it is not a 'Deployed' version, and one or more 'Deployed' versions"
										  @" of Tunnelblick were previously installed.\n\n", @"Window text"),
						nil,nil,nil);
		[self terminateBecause: terminatingBecauseOfQuit];
	}
#endif
	
    // If necessary, warn that non-.tblks will be converted
	gOkToConvertNonTblks = warnAboutNonTblks();
    
    // If necessary, (re)install Tunnelblick in /Applications
    [self relaunchIfNecessary];  // (May not return from this)
    
	[self secureIfNecessary];
}

-(void) warnIfInvalidOrNoSignatureAllowCheckbox: (BOOL) allowCheckbox
{
	NSString * checkboxPrefKey = nil;
	NSString * checkboxText    = nil;
	
	NSString * contentsPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent: @"Contents"];
	if (   [gFileMgr fileExistsAtPath: [contentsPath stringByAppendingPathComponent: @"_CodeSignature"]]  ) {
		if (  signatureIsInvalid  ) {
			
			if (  allowCheckbox  ) {
				checkboxPrefKey = @"skipWarningAboutInvalidSignature";
				checkboxText    = NSLocalizedString(@"Do not ask again, always Continue", @"Checkbox name");
			}
			
			int result = TBRunAlertPanelExtended(NSLocalizedString(@"Warning!", @"Window title"),
												 NSLocalizedString(@"This copy of Tunnelblick has been tampered with (the"
																   @" digital signature is invalid).\n\n"
																   @"Please check with the provider of this copy of Tunnelblick before"
																   @" using it.\n\n", @"Window text"),
												 NSLocalizedString(@"Quit", @"Button"),
												 nil,
												 NSLocalizedString(@"Continue", @"Button"),
												 checkboxPrefKey,
												 checkboxText,
												 nil,
												 NSAlertOtherReturn);
			if (  result != NSAlertOtherReturn  ) {   // Quit if "Quit" or error
				[self terminateBecause: terminatingBecauseOfQuit];
			}
		}
#ifndef TBDebug
	} else {
		if (   [gTbDefaults canChangeValueForKey: @"skipWarningAboutNoSignature"]
			|| ( ! [gTbDefaults boolForKey: @"skipWarningAboutNoSignature"] )
			) {
			if (  allowCheckbox  ) {
				checkboxPrefKey = @"skipWarningAboutNoSignature";
				checkboxText    = NSLocalizedString(@"Do not ask again, always Continue", @"Checkbox name");
			}
			
			int result = TBRunAlertPanelExtended(NSLocalizedString(@"Warning!", @"Window title"),
												 NSLocalizedString(@"This copy of Tunnelblick is not digitally signed.\n\n"
																   @"There is no way to verify that this copy has not been tampered with.\n\n"
																   @" Check with the the provider of this copy of Tunnelblick before"
																   @" using it.\n\n", @"Window text"),
												 NSLocalizedString(@"Quit", @"Button"),
												 nil,
												 NSLocalizedString(@"Continue", @"Button"),
												 checkboxPrefKey,
												 checkboxText,
												 nil,
												 NSAlertOtherReturn);
			if (  result != NSAlertOtherReturn  ) {   // Quit if "Quit" or error
				[self terminateBecause: terminatingBecauseOfQuit];
			}
		}
#endif
	}
}

-(int) countTblks: (NSArray *) tblksToInstallPaths {
    
    // Given an array of paths to .tblks to be installed, counts how many will be installed, including nested .tblks

    int counter = 0;
    
    unsigned i;
    for (  i=0; i<[tblksToInstallPaths count]; i++) {
        BOOL innerTblksFound = FALSE;
        NSString * outerPath = [tblksToInstallPaths objectAtIndex: i];
        if (  [outerPath hasSuffix: @".tblk"]  ) {
            NSString * file;
            NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: outerPath];
            while (  (file = [dirEnum nextObject])  ) {
                NSString * fullPath = [outerPath stringByAppendingPathComponent: file];
                if (   itemIsVisible( fullPath)
                    && [file hasSuffix: @".tblk"]  ) {
                    [dirEnum skipDescendents];
                    counter++;
                    innerTblksFound = TRUE;
                }
            }
            
            if (  ! innerTblksFound  ) {
                counter++;
            }
        } else {
            NSLog(@"%@ is not a .tblk and can't be installed", outerPath);
        }
    }
    
    return counter;
}

-(void) relaunchIfNecessary
{
	NSString * currentPath = [[NSBundle mainBundle] bundlePath];
	
	NSString * contentsPath = [currentPath stringByAppendingPathComponent: @"Contents"];
    if (   [gFileMgr fileExistsAtPath: [contentsPath stringByAppendingPathComponent: @"_CodeSignature"]]
		&& ( ! [self hasValidSignature] )  ) {
		signatureIsInvalid = TRUE;
	} else {
		signatureIsInvalid = FALSE;	// (But it might not have one)
	}
	
    // Move or copy Tunnelblick.app to /Applications if it isn't already there
    
    BOOL canRunOnThisVolume = [self canRunFromVolume: currentPath];
    
    if (  canRunOnThisVolume ) {
#ifdef TBDebug
        NSLog(@"Tunnelblick: WARNING: This is an insecure copy of Tunnelblick to be used for debugging only!");
        [self warnIfInvalidOrNoSignatureAllowCheckbox: YES];
        return;
#endif
        if (  [[currentPath stringByDeletingLastPathComponent] isEqualToString: @"/Applications"]  ) {
			[self warnIfInvalidOrNoSignatureAllowCheckbox: YES];
            return;
        } else {
            NSLog(@"Tunnelblick can only run when it is in /Applications; path = %@.", currentPath);
        }
    } else {
        NSLog(@"Tunnelblick cannot run when it is on /%@ because the volume has the MNT_NOSUID statfs flag set.", [[currentPath pathComponents] objectAtIndex: 1]);
    }
    
    // Not installed in /Applications on a runnable volume. Need to move/install to /Applications
    
	[self warnIfInvalidOrNoSignatureAllowCheckbox: NO];
	
    //Install into /Applications
	
    // Set up message about installing .tblks on the .dmg
    NSString * tblksMsg;
    NSArray * tblksToInstallPaths = [self findTblksToInstallInPath: [currentPath stringByDeletingLastPathComponent]];
    if (  tblksToInstallPaths  ) {
        tblksMsg = [NSString stringWithFormat: NSLocalizedString(@"\n\nand install %ld Tunnelblick VPN Configurations", @"Window text"),
                    (long) [self countTblks: tblksToInstallPaths]];
    } else {
        tblksMsg = @"";
    }
    
    // Set up messages to get authorization and notify of success
	NSString * appVersion   = tunnelblickVersion([NSBundle mainBundle]);	
    NSString * tbInApplicationsPath = [@"/Applications" stringByAppendingPathComponent: [currentPath lastPathComponent]];
    NSString * applicationsPath = @"/Applications";
    NSString * tbInApplicationsDisplayName = [[gFileMgr componentsToDisplayForPath: tbInApplicationsPath] componentsJoinedByString: @"/"];
    NSString * applicationsDisplayName = [[gFileMgr componentsToDisplayForPath: applicationsPath] componentsJoinedByString: @"/"];
    
    NSString * launchWindowTitle = NSLocalizedString(@"Installation succeeded", @"Window title");
    NSString * launchWindowText;
    NSString * authorizationText;
    
	NSString * signatureWarningText;
	if (  signatureIsInvalid  ) {
		signatureWarningText = NSLocalizedString(@" WARNING: This copy of Tunnelblick has been tampered with.\n\n", @"Window text");
	} else {
		signatureWarningText = @"";
	}
	
	NSString * convertTblksText;
	if (  gOkToConvertNonTblks  ) {
		convertTblksText = NSLocalizedString(@" Note: OpenVPN configurations will be converted to Tunnelblick VPN Configurations.\n\n", @"Window text");
	} else {
		convertTblksText = @"";
	}
	
    if (  [gFileMgr fileExistsAtPath: tbInApplicationsPath]  ) {
        NSBundle * previousBundle = [NSBundle bundleWithPath: tbInApplicationsPath];
        NSString * previousVersion = tunnelblickVersion(previousBundle);
        authorizationText = [NSString stringWithFormat:
                             NSLocalizedString(@" Do you wish to replace\n    %@\n    in %@\nwith %@%@?\n\n", @"Window text"),
                             previousVersion, applicationsDisplayName, appVersion, tblksMsg];
        launchWindowText = NSLocalizedString(@"Tunnelblick was successfully replaced.\n\nDo you wish to launch the new version of Tunnelblick now?", @"Window text");
    } else {
        authorizationText = [NSString stringWithFormat:
                             NSLocalizedString(@" Do you wish to install %@ to %@%@?\n\n", @"Window text"),
                             appVersion, applicationsDisplayName, tblksMsg];
        launchWindowText = NSLocalizedString(@"Tunnelblick was successfully installed.\n\nDo you wish to launch Tunnelblick now?", @"Window text");
    }
    
    // Get authorization to install and secure
    gAuthorization = [NSApplication getAuthorizationRef:
                      [[[NSLocalizedString(@" Tunnelblick must be installed in Applications.\n\n", @"Window text")
						 stringByAppendingString: authorizationText]
                        stringByAppendingString: convertTblksText]
					   stringByAppendingString: signatureWarningText]
					  ];
	if (  ! gAuthorization  ) {
		NSLog(@"The Tunnelblick installation was cancelled by the user.");
		[self terminateBecause: terminatingBecauseOfQuit];
	}
    
    // Stop any currently running Tunnelblicks
    int numberOfOthers = [NSApp countOtherInstances];
    while (  numberOfOthers > 0  ) {
        int button = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick is currently running", @"Window title"),
                                     NSLocalizedString(@"You must stop the currently running Tunnelblick to launch the new copy.\n\nClick \"Close VPN Connections and Stop Tunnelblick\" to close all VPN connections and quit the currently running Tunnelblick before launching Tunnelblick.", @"Window text"),
                                     NSLocalizedString(@"Close VPN Connections and Stop Tunnelblick", @"Button"), // Default button
                                     NSLocalizedString(@"Cancel",  @"Button"),   // Alternate button
                                     nil);
        if (  button != NSAlertDefaultReturn  ) {// Cancel or error: Quit Tunnelblick
            [self terminateBecause: terminatingBecauseOfQuit];
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
    
    [splashScreen setMessage: NSLocalizedString(@"Installing and securing Tunnelblick...", @"Window text")];
    
	[gTbDefaults removeObjectForKey: @"skipWarningAboutInvalidSignature"];
	[gTbDefaults removeObjectForKey: @"skipWarningAboutNoSignature"];
    
    // Install this program and secure it
    if (  ! [self runInstaller: (  INSTALLER_COPY_APP
                                 | INSTALLER_COPY_BUNDLE
                                 | INSTALLER_SECURE_APP
                                 | INSTALLER_SECURE_TBLKS
                                 | (gOkToConvertNonTblks
                                    ? INSTALLER_CONVERT_NON_TBLKS
                                    : 0)
                                 | (needToMoveLibraryOpenVPN()
                                    ? INSTALLER_MOVE_LIBRARY_OPENVPN
                                    : 0)
                                 )
                extraArguments: nil
               usingAuthRefPtr: &gAuthorization
                       message: nil
              installTblksFirst: tblksToInstallPaths]
        ) {
        // An error dialog and a message in the console log have already been displayed if an error occurred
        [self terminateBecause: terminatingBecauseOfError];
    }
	
	gOkToConvertNonTblks = FALSE;
	gUserWasAskedAboutConvertNonTblks = FALSE;
    
    // Install configurations from Tunnelblick Configurations.bundle if any were copied
    NSString * installFolder = [CONFIGURATION_UPDATES_BUNDLE_PATH stringByAppendingPathComponent: @"Contents/Resources/Install"];
    if (  [gFileMgr fileExistsAtPath: installFolder]  ) {
        NSString * text = NSLocalizedString(@"Installing Tunnelblick VPN Configurations...", @"Window text");
        [splashScreen setMessage: text];
        BOOL oldLaunchFinished = launchFinished;    // Fake out installTblks so it installs the .tblk(s) immediately
        launchFinished = TRUE;
        [self installConfigurationsUpdateInBundleAtPath: CONFIGURATION_UPDATES_BUNDLE_PATH];
        launchFinished = oldLaunchFinished;
    }
    
    [splashScreen setMessage: NSLocalizedString(@"Installation finished successfully.", @"Window text")];
    int response = TBRunAlertPanel(launchWindowTitle,
                                   launchWindowText,
                                   NSLocalizedString(@"Launch", "Button"), // Default button
                                   NSLocalizedString(@"Quit", "Button"), // Alternate button
                                   nil);
    
    [splashScreen fadeOutAndClose];
    
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
    
    // If error, just terminate this instance
    
    [self terminateBecause: terminatingBecauseOfQuit];
}

-(NSArray *) findTblksToInstallInPath: (NSString *) thePath
{
    NSMutableArray * arrayToReturn = nil;
    NSString * file;
    BOOL isDir;
    
    NSString * folder = [thePath stringByAppendingPathComponent: @"auto-install"];
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: folder];
    while (  (file = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        if (   [gFileMgr fileExistsAtPath: [folder stringByAppendingPathComponent: file] isDirectory: &isDir]
            && isDir
            && [[file pathExtension] isEqualToString: @"tblk"]  ) {
            if (  arrayToReturn == nil  ) {
                arrayToReturn = [NSMutableArray arrayWithCapacity:10];
            }
            [arrayToReturn addObject: [folder stringByAppendingPathComponent: file]];
        }
    }
    
    folder = [thePath stringByAppendingPathComponent: @".auto-install"];
    dirEnum = [gFileMgr enumeratorAtPath: folder];
    while (  (file = [dirEnum nextObject])  ) {
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

// Returns TRUE if can run Tunnelblick from this volume (can run setuid binaries), FALSE otherwise
-(BOOL) canRunFromVolume: (NSString *)path
{
    if ([path hasPrefix:@"/Volumes/Tunnelblick/"]  ) {
        return FALSE;
    }
    
    const char * fileName = [gFileMgr fileSystemRepresentationWithPath: path];
    struct statfs stats_buf;
    
    if (  0 == statfs(fileName, &stats_buf)  ) {
        if (  (stats_buf.f_flags & MNT_NOSUID) == 0  ) {
            return TRUE;
		}
    } else {
        NSLog(@"statfs on %@ failed; assuming cannot run from that volume\nError was '%s'", path, strerror(errno));
    }
    return FALSE;   // Network volume or error accessing the file's data.
}

-(void) secureIfNecessary
{
    // If necessary, run the installer to secure this copy of Tunnelblick
    unsigned installFlags;
    if (  (installFlags = needToRunInstaller(FALSE)) != 0  ) {
        
        [splashScreen setMessage: NSLocalizedString(@"Securing Tunnelblick...", @"Window text")];
        
        if (  ! [self runInstaller: installFlags
                    extraArguments: nil]  ) {
            
			// An error dialog and a message in the console log have already been displayed if an error occurred
            [self terminateBecause: terminatingBecauseOfError];
        }
		
        [splashScreen setMessage: NSLocalizedString(@"Tunnelblick has been secured successfully.", @"Window text")];
    }
}

// Invoked when a folder containing configurations has changed.
-(void) watcher: (UKKQueue*) kq receivedNotification: (NSString*) nm forPath: (NSString*) fpath {
	(void) kq;
	(void) nm;
	(void) fpath;
		
    if (  ! ignoreNoConfigs  ) {
        [self performSelectorOnMainThread: @selector(activateStatusMenu) withObject: nil waitUntilDone: YES];
    }
}

-(BOOL) runInstaller: (unsigned) installFlags
      extraArguments: (NSArray *) extraArguments
{
    return [self runInstaller: installFlags extraArguments: extraArguments usingAuthRefPtr: &gAuthorization message: nil installTblksFirst: nil];
}

-(BOOL) runInstaller: (unsigned) installFlags
      extraArguments: (NSArray *) extraArguments
     usingAuthRefPtr: (AuthorizationRef *) authRefPtr
             message: (NSString *) message
   installTblksFirst: (NSArray *) tblksToInstallFirst
{
    // Returns TRUE if installer ran successfully and does not need to be run again, FALSE otherwise
    
    if (   (installFlags == 0)
		&& (extraArguments == nil)  ) {
		NSLog(@"runInstaller:extraArguments invoked but no action specified");
        return YES;
    }
    
    if (  installFlags & INSTALLER_COPY_APP  ) {
        installFlags = installFlags | INSTALLER_SECURE_TBLKS;
    }
    
    BOOL authRefIsLocal;
    AuthorizationRef localAuthRef = NULL;
    if (  authRefPtr == nil  ) {
        authRefPtr = &localAuthRef;
        authRefIsLocal = TRUE;
    } else {
        authRefIsLocal = FALSE;
    }
    
    if (  *authRefPtr == nil  ) {
        NSMutableString * msg;
        if (  message  ) {
            msg = [[message mutableCopy] autorelease];
        } else {
            msg = [NSMutableString stringWithString: NSLocalizedString(@"Tunnelblick needs to:\n", @"Window text")];
            if (    installFlags & INSTALLER_COPY_APP              ) [msg appendString: NSLocalizedString(@"  • Be installed in /Applications\n", @"Window text")];
            if (    installFlags & INSTALLER_SECURE_APP            ) [msg appendString: NSLocalizedString(@"  • Change ownership and permissions of the program to secure it\n", @"Window text")];
            if (    installFlags & INSTALLER_MOVE_LIBRARY_OPENVPN  ) [msg appendString: NSLocalizedString(@"  • Move the private configurations folder\n", @"Window text")];
            if (    tblksToInstallFirst                            ) [msg appendString: NSLocalizedString(@"  • Install or update configuration(s)\n", @"Window text")];
            if (    installFlags & INSTALLER_CONVERT_NON_TBLKS     ) [msg appendString: NSLocalizedString(@"  • Convert OpenVPN configurations\n", @"Window text")];
            if (   (installFlags & INSTALLER_SECURE_TBLKS)
                || (installFlags & INSTALLER_COPY_BUNDLE)          ) [msg appendString: NSLocalizedString(@"  • Secure configurations\n", @"Window text")];
        }
        
#ifdef TBDebug
        [msg appendString: NSLocalizedString(@"\n WARNING: THIS COPY OF TUNNELBLICK MAKES YOUR COMPUTER INSECURE."
                                             @" It is for debugging purposes only.\n", @"Window text")];
#endif
		
		if (  signatureIsInvalid  ) {
			[msg appendString: NSLocalizedString(@"\n WARNING: THIS COPY OF TUNNELBLICK HAS BEEN TAMPERED WITH.\n", @"Window text")];
		}
        
		NSLog(@"%@", msg);
        
        // Get an AuthorizationRef and use executeAuthorized to run the installer
        *authRefPtr = [NSApplication getAuthorizationRef: msg];
        if(  *authRefPtr == NULL  ) {
            NSLog(@"Installation or repair cancelled");
            return FALSE;
        }
        
        // NOTE: We do NOT free gAuthorization here. It may be used to install .tblk packages, so we free it when we
        // are finished launching, in applicationDidFinishLaunching
    }
    
    if (  tblksToInstallFirst  ) {
		BOOL oldLaunchFinished = launchFinished;
        launchFinished = TRUE;  // Fake out installTblks so it installs the .tblk(s) immediately
        [self installTblks: tblksToInstallFirst skipConfirmationMessage: YES skipResultMessage: YES notifyDelegate: NO];
        launchFinished = oldLaunchFinished;
    }
        
    NSLog(@"Beginning installation or repair");

    NSString *launchPath = [[NSBundle mainBundle] pathForResource:@"installer" ofType:nil];

	installFlags = installFlags | INSTALLER_CLEAR_LOG;
	
    int result = -1;    // Last result from waitForExecuteAuthorized
    BOOL okNow = FALSE;
    unsigned i;
    for (i=0; i<5; i++) {
        if (  i != 0  ) {
            usleep( i * 1000000 );	// Sleep for 1.0, 2.0, 3.0, and 4.0 seconds (total 8.0 seconds)
            NSLog(@"Retrying execution of installer");
        }
        
		NSMutableArray * arguments = [[[NSMutableArray alloc] initWithCapacity:3] autorelease];
		[arguments addObject: [NSString stringWithFormat: @"%u", installFlags]];
		
		NSString * arg;
		NSEnumerator * e = [extraArguments objectEnumerator];
		while (  (arg = [e nextObject])  ) {
			[arguments addObject: arg];
		}
		
		installFlags = installFlags & ( ~ INSTALLER_CLEAR_LOG );
		
        result = [NSApplication waitForExecuteAuthorized: launchPath withArguments: arguments withAuthorizationRef: *authRefPtr];
        
        okNow = FALSE;
        
        if (  result == wfeaExecAuthFailed  ) {
            NSLog(@"Failed to execute %@: %@", launchPath, arguments);
            continue;
        } else if (  result == wfeaTimedOut  ) {
            NSLog(@"Timed out executing %@: %@", launchPath, arguments);
            continue;
        } else if (  result == wfeaFailure  ) {
            NSLog(@"installer reported failure: %@: %@", launchPath, arguments);
            continue;
        } else if (  result == wfeaSuccess  ) {
            okNow = (0 == (   installFlags
                           & (  INSTALLER_COPY_APP
                              | INSTALLER_SECURE_APP
                              | INSTALLER_COPY_BUNDLE
                              | INSTALLER_SECURE_TBLKS
                              | INSTALLER_CONVERT_NON_TBLKS
                              | INSTALLER_MOVE_LIBRARY_OPENVPN
                              )
                           )
                     ? YES
                     
                     // We do this to make sure installer actually did what MenuController told it to do
                     : needToRunInstaller(installFlags & INSTALLER_COPY_APP) == 0
                     );
            
            if (  okNow  ) {
                break;
            } else {
                NSLog(@"installer did not make the necessary changes");
            }
        } else {
            NSLog(@"Unknown value %d returned by waitForExecuteAuthorized:withArguments:withAuthorizationRef:", result);
        }
    }
	
	NSString * installerLog = @"";
	if (  [gFileMgr fileExistsAtPath: @"/tmp/tunnelblick-installer-log.txt"]  ) {
		NSData * data = [gFileMgr contentsAtPath: @"/tmp/tunnelblick-installer-log.txt"];
		if (  data  ) {
			installerLog = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
		}
	}
    
    if (  okNow  ) {
        NSLog(@"Installation or repair succeeded; Log:\n%@", installerLog);
        [installerLog release];
        if (  authRefIsLocal  ) {
            AuthorizationFree(localAuthRef, kAuthorizationFlagDefaults);
        }
        
        return TRUE;
    }
    
    NSLog(@"Installation or repair failed; Log:\n%@", installerLog);
    TBRunAlertPanel(NSLocalizedString(@"Installation or Repair Failed", "Window title"),
                    NSLocalizedString(@"The installation, removal, recovery, or repair of one or more Tunnelblick components failed. See the Console Log for details.", "Window text"),
                    nil, nil, nil);
    [installerLog release];
    if (  authRefIsLocal  ) {
        AuthorizationFree(localAuthRef, kAuthorizationFlagDefaults);
    }
    return FALSE;
}

// Checks whether the installer needs to be run
// Sets bits in a flag for use by the runInstaller:extraArguments method, and, ultimately, by the installer program
//
// DOES NOT SET INSTALLER_COPY_APP (or INSTALLER_MOVE_NOT_COPY, INSTALLER_DELETE, or INSTALLER_SET_VERSION)
//
// Returns an unsigned containing INSTALLER_... bits set appropriately
unsigned needToRunInstaller(BOOL inApplications)
{
    unsigned flags = 0;
    
    if (  needToChangeOwnershipAndOrPermissions(inApplications)  ) flags = flags | INSTALLER_SECURE_APP;
    if (  needToCopyBundle()                                     ) flags = flags | INSTALLER_COPY_BUNDLE;
    if (  needToRepairPackages()                                 ) flags = flags | INSTALLER_SECURE_TBLKS;
    if (  needToConvertNonTblks()                                ) flags = flags | INSTALLER_CONVERT_NON_TBLKS;
    if (  needToMoveLibraryOpenVPN()                             ) flags = flags | INSTALLER_MOVE_LIBRARY_OPENVPN;
    
    return flags;
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
    NSDictionary * fileAttributes = [gFileMgr tbFileAttributesAtPath: oldConfigDirPath traverseLink: NO];
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
        if (  ! [[gFileMgr tbPathContentOfSymbolicLinkAtPath: oldConfigDirPath] isEqualToString: newConfigDirPath]  ) {
            NSLog(@"Warning: %@ exists and is a symbolic link but does not reference %@", oldConfigDirPath, newConfigDirPath);
        }
    }

    return NO;  // Nothing needs to be done
}

BOOL needToSecureFolderAtPath(NSString * path)
{
    // Returns YES if the folder (a Deploy folder in the app needs to be secured
    //
    // There is a SIMILAR function in openvpnstart: exitIfTblkNeedsRepair
    //
    // There is a SIMILAR function in installer: secureOneFolder, that secures a folder with these permissions
    
    mode_t selfPerms;           //  For the folder itself (if not a .tblk)
    mode_t tblkFolderPerms;     //  For a .tblk itself and any folders inside it
    mode_t privateFolderPerms;  //  For folders in /Library/Application Support/Tunnelblick/Users/...
    mode_t publicFolderPerms;   //  For all other folders
    mode_t scriptPerms;         //  For files with .sh extensions
    mode_t executablePerms;     //  For files with .executable extensions (only appear in a Deploy folder
    mode_t forcedPrefsPerms;    //  For files named forced-preferences (only appear in a Deploy folder
    mode_t otherPerms;          //  For all other files
    
	uid_t user = 0;
	gid_t group = 0;
	
    selfPerms		   = PERMS_SECURED_SELF;
    tblkFolderPerms    = PERMS_SECURED_TBLK_FOLDER;
    privateFolderPerms = PERMS_SECURED_PRIVATE_FOLDER;
    publicFolderPerms  = PERMS_SECURED_PUBLIC_FOLDER;
    scriptPerms        = PERMS_SECURED_SCRIPT;
    executablePerms    = PERMS_SECURED_EXECUTABLE;
    forcedPrefsPerms   = PERMS_SECURED_FORCED_PREFS;
    otherPerms         = PERMS_SECURED_OTHER;

    if (  ! checkOwnerAndPermissions(path, 0, 0, selfPerms)  ) {
        return YES;
    }
    
    BOOL isDir;
    NSString * file;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: path];
	
    while (  (file = [dirEnum nextObject])  ) {
        NSString * filePath = [path stringByAppendingPathComponent: file];
        if (  itemIsVisible(filePath)  ) {
            
            NSString * ext  = [file pathExtension];
            
            if (  [ext isEqualToString: @"tblk"]  ) {
                if (  ! checkOwnerAndPermissions(filePath, user, group, tblkFolderPerms)  ) {
                    return YES;
                }
            
            } else if (   [gFileMgr fileExistsAtPath: filePath isDirectory: &isDir] && isDir  ) {
			
                if (  [filePath rangeOfString: @".tblk/"].location != NSNotFound  ) {
					if (  ! checkOwnerAndPermissions(filePath, user, group, tblkFolderPerms)  ) {
						return YES;
					}
				
                } else if (   [filePath hasPrefix: [gDeployPath   stringByAppendingString: @"/"]]
                           || [filePath hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]  ) {
					if (  ! checkOwnerAndPermissions(filePath, user, group, publicFolderPerms)  ) {
						return YES;
					}
				
                } else {
					if (  ! checkOwnerAndPermissions(filePath, user, group, privateFolderPerms)  ) {
						return YES;
					}
				}
			
            } else if ( [ext isEqualToString:@"sh"]  ) {
                if (  ! checkOwnerAndPermissions(filePath, user, group, scriptPerms)  ) {
                    return YES;
                }
            
            } else if ( [ext isEqualToString:@"executable"]  ) {
                if (  ! checkOwnerAndPermissions(filePath, user, group, executablePerms)  ) {
                    return YES;
                }
            
            } else if ( [file isEqualToString:@"forced-preferences.plist"]  ) {
                if (  ! checkOwnerAndPermissions(filePath, user, group, forcedPrefsPerms)  ) {
                    return YES;
                }
                
            } else {
                if (  ! checkOwnerAndPermissions(filePath, user, group, otherPerms)  ) {
                    return YES;
                }
            }
        }
    }
    
    return NO;
}

BOOL needToChangeOwnershipAndOrPermissions(BOOL inApplications)
{
	// Check ownership and permissions on components of Tunnelblick.app
    NSString * resourcesPath = [[NSBundle mainBundle] resourcePath];
    if ( inApplications  ) {
		NSString * ourAppName = [[[resourcesPath 
								   stringByDeletingLastPathComponent]	// Remove "/Resources
								  stringByDeletingLastPathComponent]	// Remove "/Contents"
								 lastPathComponent];
								  
        resourcesPath = [NSString stringWithFormat: @"/Applications/%@/Contents/Resources", ourAppName];
	}
    
	NSString *contentsPath			    = [resourcesPath stringByDeletingLastPathComponent];
    NSString *tunnelblickPath           = [contentsPath  stringByDeletingLastPathComponent];
    
	NSString *openvpnstartPath          = [resourcesPath stringByAppendingPathComponent: @"openvpnstart"                        ];
	NSString *openvpnFolderPath         = [resourcesPath stringByAppendingPathComponent: @"openvpn"                             ];
	NSString *atsystemstartPath         = [resourcesPath stringByAppendingPathComponent: @"atsystemstart"                       ];
	NSString *installerPath             = [resourcesPath stringByAppendingPathComponent: @"installer"                           ];
	NSString *ssoPath                   = [resourcesPath stringByAppendingPathComponent: @"standardize-scutil-output"           ];
	NSString *leasewatchPath            = [resourcesPath stringByAppendingPathComponent: @"leasewatch"                          ];
	NSString *leasewatch3Path           = [resourcesPath stringByAppendingPathComponent: @"leasewatch3"                         ];
	NSString *clientUpPath              = [resourcesPath stringByAppendingPathComponent: @"client.up.osx.sh"                    ];
	NSString *clientDownPath            = [resourcesPath stringByAppendingPathComponent: @"client.down.osx.sh"                  ];
	NSString *clientNoMonUpPath         = [resourcesPath stringByAppendingPathComponent: @"client.nomonitor.up.osx.sh"          ];
	NSString *clientNoMonDownPath       = [resourcesPath stringByAppendingPathComponent: @"client.nomonitor.down.osx.sh"        ];
	NSString *clientNewUpPath           = [resourcesPath stringByAppendingPathComponent: @"client.up.tunnelblick.sh"            ];
	NSString *clientNewDownPath         = [resourcesPath stringByAppendingPathComponent: @"client.down.tunnelblick.sh"          ];
	NSString *clientNewRoutePreDownPath = [resourcesPath stringByAppendingPathComponent: @"client.route-pre-down.tunnelblick.sh"];
	NSString *clientNewAlt1UpPath       = [resourcesPath stringByAppendingPathComponent: @"client.1.up.tunnelblick.sh"          ];
	NSString *clientNewAlt1DownPath     = [resourcesPath stringByAppendingPathComponent: @"client.1.down.tunnelblick.sh"        ];
	NSString *clientNewAlt2UpPath       = [resourcesPath stringByAppendingPathComponent: @"client.2.up.tunnelblick.sh"          ];
	NSString *clientNewAlt2DownPath     = [resourcesPath stringByAppendingPathComponent: @"client.2.down.tunnelblick.sh"        ];
	NSString *clientNewAlt3UpPath       = [resourcesPath stringByAppendingPathComponent: @"client.3.up.tunnelblick.sh"          ];
	NSString *clientNewAlt3DownPath     = [resourcesPath stringByAppendingPathComponent: @"client.3.down.tunnelblick.sh"        ];
    NSString *deployPath                = [resourcesPath stringByAppendingPathComponent: @"Deploy"];
    NSString *infoPlistPath             = [[resourcesPath stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"Info.plist"];

	if (  ! checkOwnedByRootWheel(tunnelblickPath) ) {
        NSLog(@"%@ not owned by root:wheel", tunnelblickPath);
        return YES;
	}
    
    if (  ! checkOwnerAndPermissions(tunnelblickPath, 0, 0, 0755)  ) {
        return YES; // NSLog already called
    }
    
    if (  ! checkOwnerAndPermissions(contentsPath,    0, 0, 0755)  ) {
        return YES; // NSLog already called
    }
    
    if (  ! checkOwnerAndPermissions(resourcesPath,   0, 0, 0755)  ) {
        return YES; // NSLog already called
    }
    
	// check openvpnstart owned by root with suid and 544 permissions
	const char *path = [gFileMgr fileSystemRepresentationWithPath: openvpnstartPath];
    struct stat sb;
	if (  stat(path, &sb)  != 0  ) {
        NSLog(@"Unable to determine status of %s\nError was '%s'", path, strerror(errno));
        return YES;
	}
	if (   (sb.st_uid != 0)
        || ((sb.st_mode & 07777) != 04555)  ) {
        return YES;
	}
	
    // check openvpn folder
    if (  ! checkOwnerAndPermissions(openvpnFolderPath, 0, 0, 0755)  ) {
        return YES; // NSLog already called
    }
    
    // Check OpenVPN version folders and the binaries of openvpn and openvpn-down-root.so in them
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: openvpnFolderPath];
    NSString * file;
    BOOL isDir;
    while (  (file = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        NSString * fullPath = [openvpnFolderPath stringByAppendingPathComponent: file];
        if (   [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
            && isDir  ) {
            if (  [file hasPrefix: @"openvpn-"]  ) {
                if (  ! checkOwnerAndPermissions(fullPath, 0, 0, 0755)  ) {
                    return YES;
                }
                
                NSString * thisOpenvpnPath = [fullPath stringByAppendingPathComponent: @"openvpn"];
                if (  ! checkOwnerAndPermissions(thisOpenvpnPath, 0, 0, 0755)  ) {
                    return YES;
                }
                
                NSString * thisOpenvpnDownRootPath = [fullPath stringByAppendingPathComponent: @"openvpn-down-root.so"];
                if (  ! checkOwnerAndPermissions(thisOpenvpnDownRootPath, 0, 0, 0744)  ) {
                    return YES;
                }
            }
        }
    }
    
	// check files which should be owned by root with 744 permissions
	NSArray *root744Objects = [NSArray arrayWithObjects:
                               atsystemstartPath, installerPath, ssoPath, leasewatchPath, leasewatch3Path,
                               clientUpPath, clientDownPath,
                               clientNoMonUpPath, clientNoMonDownPath,
                               clientNewUpPath, clientNewDownPath, clientNewRoutePreDownPath,
                               clientNewAlt1UpPath, clientNewAlt1DownPath,
                               clientNewAlt2UpPath, clientNewAlt2DownPath,
                               clientNewAlt3UpPath, clientNewAlt3DownPath,
                               nil];
	NSEnumerator *e = [root744Objects objectEnumerator];
	NSString *currentPath;
	while (  (currentPath = [e nextObject])  ) {
        if (  ! checkOwnerAndPermissions(currentPath, 0, 0, 0744)  ) {
            return YES; // NSLog already called
        }
	}
    
    // check Info.plist
    if (  ! checkOwnerAndPermissions(infoPlistPath, 0, 0, 0644)  ) {
        return YES; // NSLog already called
    }
    
    // check that log directory exists and has proper ownership and permissions
    if (  ! (   [gFileMgr fileExistsAtPath: L_AS_T_LOGS isDirectory: &isDir]
             && isDir )  ) {
        NSLog(@"Need to create log directory '%@'", L_AS_T_LOGS);
        return YES;
    }
    if (  ! checkOwnerAndPermissions(L_AS_T_LOGS, 0, 0, 0755)  ) {
        return YES; // NSLog already called
    }
    
    // check that Users directory exists and has proper ownership and permissions
    if (  ! (   [gFileMgr fileExistsAtPath: L_AS_T_USERS isDirectory: &isDir]
             && isDir )  ) {
        NSLog(@"Need to create Users directory '%@'", L_AS_T_USERS);
        return YES;
    }
    if (  ! checkOwnerAndPermissions(L_AS_T_USERS, 0, 0, 0750)  ) {
        return YES; // NSLog already called
    }
    
    // check permissions of files in Resources/Deploy (if it exists)
    if (  [gFileMgr fileExistsAtPath: deployPath isDirectory: &isDir]
        && isDir  ) {
        if (  needToSecureFolderAtPath(deployPath)  ) {
            return YES;
        }
    }
    
    return NO;
}

BOOL checkAttributes(NSDictionary * atts)
{
    // Check that a set of file attributes shows ownership by root:wheel
    if (  [[atts fileOwnerAccountID] intValue] != 0  ) {
        return NO;
    }
    
    if (  [[atts fileGroupOwnerAccountID] intValue] != 0  ) {
        return NO;
    }
    
    return YES;
}    

BOOL checkOwnedByRootWheel(NSString * path)
{
    // Check that everything in path and it's subfolders is owned by root:wheel (checks symlinks, too)
	NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: path];
	NSString * file;
	NSDictionary * atts;
	while (  (file = [dirEnum nextObject])  ) {
		NSString * filePath = [path stringByAppendingPathComponent: file];
		if (  itemIsVisible(filePath)  ) {
			atts = [gFileMgr tbFileAttributesAtPath: filePath traverseLink: NO];
            if (  ! checkAttributes(atts)  ) {
                return NO;
            }
			if (  [[atts objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
				atts = [gFileMgr tbFileAttributesAtPath: filePath traverseLink: YES];
                if (  ! checkAttributes(atts)  ) {
                    return NO;
                }
			}
		}
	}
	
	return YES;
}
        
BOOL needToRepairPackages(void)
{
    // Check permissions of private .tblk packages.
    //
	// If ...tblk/Contents is owned by root:wheel (old setup), we need to change the ownership to user:group,
	// because in the new setup, the private configs are no longer secured (the shadow copies are secured)
    //
    // This check is to detect when the permissions have been reverted to the old scheme _after_ using the new scheme and setting the preference
    // 
	
    NSString * file;
    BOOL isDir;
    NSDirectoryEnumerator *dirEnum = [gFileMgr enumeratorAtPath: gPrivatePath];
    while (  (file = [dirEnum nextObject])  ) {
        NSString * fullPath = [gPrivatePath stringByAppendingPathComponent: file];
        if (  itemIsVisible(fullPath)  ) {
			NSString * ext = [file pathExtension];
            if (   [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
                && isDir
                && [ext isEqualToString: @"tblk"]  ) {
                if (  checkOwnedByRootWheel([fullPath stringByAppendingPathComponent: @"Contents"])  ) {
                    return YES;
                }
				[dirEnum skipDescendents];
			}
        }
    }
    
    return NO;
}

BOOL needToCopyBundle()
{
    NSString * appConfigurationsBundlePath = [[[NSBundle mainBundle] resourcePath]
                                              stringByAppendingPathComponent: @"Tunnelblick Configurations.bundle"];
    
    BOOL isDir;
    
    if (   [gFileMgr fileExistsAtPath: appConfigurationsBundlePath isDirectory: &isDir]
        && isDir  ) {
        
        NSString * appConfigBundlePlistPath = [appConfigurationsBundlePath stringByAppendingPathComponent: @"Contents/Info.plist"];
        NSDictionary * appDict = [NSDictionary dictionaryWithContentsOfFile: appConfigBundlePlistPath];
        NSString * appVersion = [appDict objectForKey: @"CFBundleVersion"];
        if (  appVersion  ) {
            if (  [gFileMgr fileExistsAtPath: CONFIGURATION_UPDATES_BUNDLE_PATH]  ) {
                NSString * libPlistPath = [CONFIGURATION_UPDATES_BUNDLE_PATH stringByAppendingPathComponent: @"Contents/Info.plist"];
                NSDictionary * libDict = [NSDictionary dictionaryWithContentsOfFile: libPlistPath];
                NSString * libVersion = [libDict objectForKey: @"CFBundleVersion"];
                if (  libVersion  ) {
                    if (  [appVersion compare: libVersion options: NSNumericSearch]  == NSOrderedDescending  ) {
                        return YES;  // App has higher version than /Library...
                    }
                } else {
                    return YES;  // No version info in /Library... copy
                }
            } else {
                return YES;  // No /Library... copy
            }
        } else {
            NSLog(@"No CFBundleVersion in %@", appConfigurationsBundlePath);
        }
    }
    
    return NO;
}

BOOL needToConvertNonTblks(void)
{
	if (  gUserWasAskedAboutConvertNonTblks  ) {		// Have already asked
		if (  anyNonTblkConfigs()  ) {
			return gOkToConvertNonTblks;
		}
		
		gOkToConvertNonTblks = FALSE;
		gUserWasAskedAboutConvertNonTblks = FALSE;
		return NO;
	}
	
	if (  warnAboutNonTblks()  ) {	// Ask if necessary
		return YES;
	}
	
	gOkToConvertNonTblks = FALSE;
	gUserWasAskedAboutConvertNonTblks = FALSE;
	return NO;
}

void terminateBecauseOfBadConfiguration(void)
{
    TBRunAlertPanel(NSLocalizedString(@"Tunnelblick Configuration Problem", @"Window title"),
                    NSLocalizedString(@"Tunnelblick could not be launched because of a problem with the configuration. Please examine the Console Log for details.", @"Window text"),
                    nil, nil, nil);
    [[NSApp delegate] terminateBecause: terminatingBecauseOfError];
}

-(NSApplicationTerminateReply) applicationShouldTerminate: (NSApplication *) sender
{
	(void) sender;
	
	NSArray * reasons = [NSArray arrayWithObjects:
						 @"for unknown reason, probably Command-Q",
						 @"because of logout",
						 @"because of shutdown",
						 @"because of restart",
						 @"because of Quit",
						 @"because of an error",
						 @"because of a fatal error",
						 nil];
	NSString * reasonString;
	if (  reasonForTermination < [reasons count]  ) {
		reasonString = [reasons objectAtIndex: reasonForTermination];
	} else {
		reasonString = [reasons objectAtIndex: 0];
	}

    NSLog(@"applicationShouldTerminate: termination %@; delayed until 'shutdownTunnelblick' finishes", reasonString);
    [self performSelectorOnMainThread: @selector(shutDownTunnelblick) withObject: nil waitUntilDone: NO];
    return NSTerminateLater;
}

-(void) shutDownTunnelblick
{
    NSLog(@"DEBUG: shutDownTunnelblick: started.");
    terminatingAtUserRequest = TRUE;
    
    if (  [theAnim isAnimating]  ) {
        NSLog(@"DEBUG: shutDownTunnelblick: stopping icon animation.");
        [theAnim stopAnimation];
    }
    
    NSLog(@"DEBUG: shutDownTunnelblick: Starting cleanup.");
    if (  [self cleanup]  ) {
        NSLog(@"DEBUG: shutDownTunnelblick: Cleanup finished.");
    } else {
        NSLog(@"DEBUG: shutDownTunnelblick: Cleanup already being done.");
    }
    
    NSLog(@"Finished shutting down Tunnelblick; allowing termination");
    [NSApp replyToApplicationShouldTerminate: YES];
}


- (void) applicationWillTerminate: (NSNotification*) notification
{
	(void) notification;
	
    NSLog(@"DEBUG: applicationWillTerminate: invoked");
}

// These five notifications happen BEFORE the "willLogoutOrShutdown" notification and indicate intention

-(void) logoutInitiatedHandler: (NSNotification *) n
{
	(void) n;
	
    reasonForTermination = terminatingBecauseOfLogout;
    NSLog(@"DEBUG: Initiated logout");
}

-(void) restartInitiatedHandler: (NSNotification *) n
{
	(void) n;
	
    reasonForTermination = terminatingBecauseOfRestart;
    NSLog(@"DEBUG: Initiated computer restart");
}

-(void) shutdownInitiatedHandler: (NSNotification *) n
{
	(void) n;
	
    reasonForTermination = terminatingBecauseOfShutdown;
    NSLog(@"DEBUG: Initiated computer shutdown");
}

-(void) logoutCancelledHandler: (NSNotification *) n
{
	(void) n;
	
    reasonForTermination = terminatingForUnknownReason;
    NSLog(@"DEBUG: Cancelled logout, or computer shutdown or restart.");
}

// reasonForTermination should be set before this is invoked

-(void) setShutdownVariables
{
    // Only change the shutdown variables once. Maybe by logoutContinuedHandler:, maybe by willLogoutOrShutdownHandler:, whichever
    // occurs first.
    //
    // NEVER unlock this mutex. It is only invoked when Tunnelblick is quitting or about to quit
    static pthread_mutex_t shuttingDownMutex = PTHREAD_MUTEX_INITIALIZER;
    
    int status = pthread_mutex_trylock( &shuttingDownMutex );
    if (  status != EXIT_SUCCESS  ) {
        if (  status == EBUSY  ) {
            NSLog(@"DEBUG: setShutdownVariables: invoked, but have already set them");
        } else {
            NSLog(@"DEBUG: setShutdownVariables: pthread_mutex_trylock( &myVPNMenuMutex ) failed; status = %ld; %s", (long) status, strerror(status));
        }
        
        return;
    }

    gShuttingDownTunnelblick = TRUE;
    if (   (reasonForTermination == terminatingBecauseOfRestart)
        || (reasonForTermination == terminatingBecauseOfShutdown)  ) {
        gShuttingDownOrRestartingComputer = TRUE;
    }
    if (   gShuttingDownOrRestartingComputer
        || (reasonForTermination == terminatingBecauseOfLogout)  ) {
        gShuttingDownWorkspace = TRUE;
        
        NSNotification * note = [NSNotification notificationWithName: @"TunnelblickUIShutdownNotification" object: nil];
        [[NSNotificationCenter defaultCenter] postNotification:note];
    }
}

-(void) logoutContinuedHandler: (NSNotification *) n
{
	(void) n;
	
    NSLog(@"DEBUG: logoutContinuedHandler: Confirmed logout, or computer shutdown or restart.");
    [self setShutdownVariables];
}

// This notification happens when we know we actually will logout or shutdown (or restart)
-(void) willLogoutOrShutdownHandler: (NSNotification *) n
{
 	(void) n;
	
   NSLog(@"DEBUG: willLogoutOrShutdownHandler: Received 'NSWorkspaceWillPowerOffNotification' notification");
    [self setShutdownVariables];
}


-(void)TunnelblickShutdownUIHandler: (NSNotification *) n
{
	(void) n;
	
    NSLog(@"DEBUG: TunnelblickShutdownUIHandler: invoked");
}


-(void)willGoToSleepHandler: (NSNotification *) n
{
 	(void) n;
	
   if (  gShuttingDownOrRestartingComputer  ) {
        return;
    }
    
    gComputerIsGoingToSleep = TRUE;
	NSLog(@"DEBUG: willGoToSleepHandler: Setting up connections to restore when computer wakes up");
    
    [connectionsToRestoreOnWakeup removeAllObjects];
    VPNConnection * connection; 
	NSEnumerator * connEnum = [[self myVPNConnectionDictionary] objectEnumerator];
    while (  (connection = [connEnum nextObject])  ) {
        if (  ! [[connection requestedState] isEqualToString: @"EXITING"]  ) {
            [connectionsToRestoreOnWakeup addObject: connection];
        }
    }
    
    terminatingAtUserRequest = TRUE;
    if (  [connectionsToRestoreOnWakeup count] != 0  ) {
        NSLog(@"DEBUG: willGoToSleepHandler: Closing all connections");
        [self killAllConnectionsIncludingDaemons: YES logMessage: @"*Tunnelblick: Computer is going to sleep. Closing connections..."];  // Kill any OpenVPN processes that still exist
        if (  ! [gTbDefaults boolForKey: @"doNotPutOffSleepUntilOpenVPNsTerminate"] ) {
            // Wait until all OpenVPN processes have terminated
            NSLog(@"DEBUG: willGoToSleepHandler: Putting off sleep until all OpenVPNs have terminated");
            while (  [[NSApp pIdsForOpenVPNProcesses] count] != 0  ) {
                usleep(100000);
            }
        }
    }
    
    NSLog(@"DEBUG: willGoToSleepHandler: OK to go to sleep");
}
-(void) wokeUpFromSleepHandler: (NSNotification *) n
{
 	(void) n;
	
   if (  gShuttingDownOrRestartingComputer  ) {
        return;
    }
    
    [self performSelectorOnMainThread: @selector(wokeUpFromSleep) withObject:nil waitUntilDone:NO];
}

-(void)wokeUpFromSleep
{
    [self menuExtrasWereAdded]; // Recreate the Tunnelblick icon
    [[self ourMainIconView] changedDoNotShowNotificationWindowOnMouseover]; // Recreate tracking rectangle if needed
    
    gComputerIsGoingToSleep = FALSE;
	if(NSDebugEnabled) NSLog(@"Computer just woke up from sleep");
	
	NSEnumerator *e = [connectionsToRestoreOnWakeup objectEnumerator];
	VPNConnection *connection;
	while (  (connection = [e nextObject])  ) {
        NSString * name = [connection displayName];
        NSString * key  = [name stringByAppendingString: @"-doNotReconnectOnWakeFromSleep"];
        if (  ! [gTbDefaults boolForKey: key]  ) {
            if (NSDebugEnabled) NSLog(@"Restoring connection %@", name);
            [connection addToLog: @"*Tunnelblick: Woke up from sleep. Attempting to re-establish connection..."];
            [connection connect:self userKnows: YES];
        } else {
            if (NSDebugEnabled) NSLog(@"Not restoring connection %@ because of preference", name);
            [connection addToLog: @"*Tunnelblick: Woke up from sleep. Not attempting to re-establish connection..."];
        }
	}
    
    [connectionsToRestoreOnWakeup removeAllObjects];
}
-(void)didBecomeInactiveUserHandler: (NSNotification *) n
{
 	(void) n;
	
   [self performSelectorOnMainThread: @selector(didBecomeInactiveUser) withObject:nil waitUntilDone:NO];
}

-(void)didBecomeInactiveUser
{
    // Remember current connections so they can be restored if/when we become the active user
    connectionsToRestoreOnUserActive = [[self connectionArray] copy];
    
    // For each open connection, either reInitialize it or disconnect it
    NSEnumerator * e = [[self connectionArray] objectEnumerator];
	VPNConnection * connection;
	while (  (connection = [e nextObject])  ) {
        if (  [connection shouldDisconnectWhenBecomeInactiveUser]  ) {
            [connection addToLog: @"*Tunnelblick: Disconnecting; user became inactive"];
            [connection disconnectAndWait: [NSNumber numberWithBool: YES] userKnows: YES];
        } else {
            [connection addToLog: @"*Tunnelblick: Stopping communication with OpenVPN because user became inactive"];
            [connection reInitialize];
        }
    }
}

-(void)didBecomeActiveUserHandler: (NSNotification *) n
{
	(void) n;
	
    [self performSelectorOnMainThread: @selector(didBecomeActiveUser) withObject:nil waitUntilDone:NO];
}

-(void)didBecomeActiveUser
{
    [self hookupToRunningOpenVPNs];
    if (  [self setupHookupWatchdogTimer]  ) {
        return; // reconnectAfterBecomeActiveUser will be done when the hookup timer times out or there are no more hookups pending
    }
    
    // Wait a second to give hookups a chance to happen, then restore connections after processing the hookups
    sleep(1);   
    
    [self performSelectorOnMainThread: @selector(reconnectAfterBecomeActiveUser) withObject: nil waitUntilDone: YES];
}

-(void)reconnectAfterBecomeActiveUser
{
   // Reconnect configurations that were connected before this user was switched out and that aren't connected now
    NSEnumerator * e = [connectionsToRestoreOnUserActive objectEnumerator];
	VPNConnection * connection;
	while (  (connection = [e nextObject])  ) {
        if (  ! [connection isHookedup]  ) {
            NSString * key = [[connection displayName] stringByAppendingString: @"-doNotReconnectOnFastUserSwitch"];
            if (  ! [gTbDefaults boolForKey: key]  ) {
                [connection stopTryingToHookup];
                [connection addToLog: @"*Tunnelblick: Attempting to reconnect because user became active"];
                [connection connect: self userKnows: YES];
            }
        }
    }
    
    [connectionsToRestoreOnUserActive release];
    connectionsToRestoreOnUserActive = nil;
}

-(void) setHotKeyIndex: (unsigned) newIndex
{
    hotKeyCurrentIndex = newIndex;

    if (  newIndex == 0  ) {
        UnregisterEventHotKey(hotKeyRef);        
        hotKeyModifierKeys = 0;
        hotKeyKeyCode = 0;
    } else {
        [self setupHotKeyWithCode: fKeyCode[newIndex-1] andModifierKeys:  cmdKey + optionKey];
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
	(void) nextHandler;
	(void) theEvent;
	
    // When the hotKey is pressed, pop up the Tunnelblick menu from the Status Bar
    MenuController * menuC = (MenuController *) userData;
    NSStatusItem * statusI = [menuC statusItem];
    [statusI popUpStatusItemMenu: [[NSApp delegate] myVPNMenu]];
    return noErr;
}

-(NSArray *) sortedSounds
{
    // Get all the names of sounds
    NSMutableArray * sounds = [[[NSMutableArray alloc] initWithCapacity: 30] autorelease];
    NSArray * soundDirs = [NSArray arrayWithObjects:
                           [NSHomeDirectory() stringByAppendingString: @"/Library/Sounds"],
                           @"/Library/Sounds",
                           @"/Network/Library/Sounds",
                           @"/System/Library/Sounds",
                           nil];
    NSArray * soundTypes = [NSArray arrayWithObjects: @"aiff", @"wav", nil];
    NSEnumerator * soundDirEnum = [soundDirs objectEnumerator];
    NSString * folder;
    NSString * file;
    while (  (folder = [soundDirEnum nextObject])  ) {
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: folder];
        while (  (file = [dirEnum nextObject])  ) {
            [dirEnum skipDescendents];
            if (  [soundTypes containsObject: [file pathExtension]]  ) {
                NSString * soundName = [file stringByDeletingPathExtension];
                if (  ! [sounds containsObject: soundName]  ) {
                    [sounds addObject: soundName];
                }
            }
        }
    }
    
    // Return them sorted
    return [sounds sortedArrayUsingSelector: @selector(caseInsensitiveNumericCompare:)];
}

-(void) updateStatisticsDisplaysHandler {
    if (  gShuttingDownWorkspace  ) {
        [statisticsWindowTimer invalidate];
        return;
    }
    
    [self performSelectorOnMainThread: @selector(updateStatisticsDisplays) withObject: nil waitUntilDone: NO];
}

-(void) updateStatisticsDisplays {
    NSEnumerator * e = [connectionArray objectEnumerator];
    VPNConnection * connection;
    while (  (connection = [e nextObject])  ) {
        [connection updateStatisticsDisplay];
    }
}

-(void) statisticsWindowsShow: (BOOL) showThem {

    NSEnumerator * e = [myVPNConnectionDictionary objectEnumerator];
    VPNConnection * connection;
    BOOL showingAny = FALSE;
    while (  (connection = [e nextObject])  ) {
        if (  [connection logFilesMayExist]  ) {
            if (  showThem  ) {
                if (   (! [gTbDefaults boolForKey: @"doNotShowDisconnectedNotificationWindows"])
                    || ( ! [connection isDisconnected])  ) {
                    [connection showStatusWindow];
                    showingAny = TRUE;
                }
            } else {
                if (   [connection isConnected]
                    || [connection isDisconnected]  ) {
                    [connection fadeAway];
                }
            }
        }
    }
    
    if (  showingAny  ) {
        if (  statisticsWindowTimer == nil  ) {
            statisticsWindowTimer = [[NSTimer scheduledTimerWithTimeInterval: 1.0
                                                                      target: self
                                                                    selector: @selector(updateStatisticsDisplaysHandler)
                                                                    userInfo: nil
                                                                     repeats: YES] retain];
        }
    } else {
        [statisticsWindowTimer invalidate];
        [statisticsWindowTimer release];
        statisticsWindowTimer = nil;
    }
}

-(void) showStatisticsWindows {

    [self statisticsWindowsShow: YES];
}

-(void) hideStatisticsWindows {
    
    [self statisticsWindowsShow: NO];
}

-(BOOL) mouseIsInsideAnyView {
    // Returns TRUE if the mouse is inside any status window or the main Icon
    
    return mouseIsInStatusWindow || mouseIsInMainIcon;
}

static pthread_mutex_t threadIdsMutex = PTHREAD_MUTEX_INITIALIZER;

-(void) addActiveIPCheckThread: (NSString *) threadID
{
    OSStatus status = pthread_mutex_lock( &threadIdsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &threadIdsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    
    [activeIPCheckThreads addObject: threadID];
	NSLog(@"DEBUG: addActiveIPCheckThread: threadID '%@' added to the active list", threadID);
    
    status = pthread_mutex_unlock( &threadIdsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &threadIdsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
}

-(void) cancelIPCheckThread: (NSString *) threadID
{
    OSStatus status = pthread_mutex_lock( &threadIdsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &threadIdsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    
    if (  [activeIPCheckThreads containsObject: threadID]  ) {
        if (  ! [cancellingIPCheckThreads containsObject: threadID]  ) {
            [activeIPCheckThreads removeObject: threadID];
            [cancellingIPCheckThreads addObject: threadID];
            NSLog(@"DEBUG: cancelIPCheckThread: threadID '%@' removed from the active list and added to the cancelling list", threadID);
            
        } else {
            NSLog(@"cancelIPCheckThread: ERROR: threadID '%@' is on both the active and cancelling lists! Removing from active list", threadID);
            [activeIPCheckThreads removeObject: threadID];
        }
    } else {
        if (  [cancellingIPCheckThreads containsObject: threadID]  ) {
            NSLog(@"DEBUG: cancelIPCheckThread: threadID '%@' is already on the cancelling list!", threadID);
        } else {
            NSLog(@"cancelIPCheckThread: ERROR: threadID '%@' is not in the the active or cancelling list! Added it to cancelling list", threadID);
            [cancellingIPCheckThreads addObject: threadID];
        }
    }
    
    status = pthread_mutex_unlock( &threadIdsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &threadIdsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
}

-(void) cancelAllIPCheckThreadsForConnection: (VPNConnection *) connection
{
    OSStatus status = pthread_mutex_lock( &threadIdsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &threadIdsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    
    NSLog(@"DEBUG: cancelAllIPCheckThreadsForConnection: Entered");
    // Make a list of threadIDs to cancel
    NSString * prefix = [NSString stringWithFormat: @"%lu-", (long) connection];
    NSMutableArray * threadsToCancel = [NSMutableArray arrayWithCapacity: 5];
    NSEnumerator * e = [activeIPCheckThreads objectEnumerator];
    NSString * threadID;
    while (  (threadID = [e nextObject])  ) {
        if (  [threadID hasPrefix: prefix]  ) {
            [threadsToCancel addObject: threadID];
        }
    }

    NSLog(@"DEBUG: cancelAllIPCheckThreadsForConnection: No active threads for connection %lu", (long) connection);
    
    // Then cancel them. (This avoids changing the list while we enumerate it.)
    e = [threadsToCancel objectEnumerator];
    while (  (threadID = [e nextObject])  ) {
        if (  [activeIPCheckThreads containsObject: threadID]  ) {
            if (  ! [cancellingIPCheckThreads containsObject: threadID]  ) {
                [activeIPCheckThreads removeObject: threadID];
                [cancellingIPCheckThreads addObject: threadID];
                NSLog(@"DEBUG: cancelAllIPCheckThreadsForConnection: threadID '%@' removed from the active list and added to the cancelling list", threadID);

            } else {
                NSLog(@"cancelAllIPCheckThreadsForConnection: ERROR: threadID '%@' is on both the active and cancelling lists! Removing from active list", threadID);
                [activeIPCheckThreads removeObject: threadID];
            }
        } else {
            if (  [cancellingIPCheckThreads containsObject: threadID]  ) {
                NSLog(@"cancelAllIPCheckThreadsForConnection: ERROR: threadID '%@' is already on the cancelling list!", threadID);
            } else {
                NSLog(@"cancelAllIPCheckThreadsForConnection: ERROR: threadID '%@' is not in the the active or cancelling list! Added it to cancelling list", threadID);
                [cancellingIPCheckThreads addObject: threadID];
            }
        }
    }
    
    status = pthread_mutex_unlock( &threadIdsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &threadIdsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
}

-(BOOL) isOnCancellingListIPCheckThread: (NSString *) threadID
{
    OSStatus status = pthread_mutex_lock( &threadIdsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &threadIdsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return NO;
    }
    
    BOOL answer = ([cancellingIPCheckThreads containsObject: threadID] ? YES : NO);
    if (  answer  ) {
        NSLog(@"DEBUG: isOnCancellingListIPCheckThread: threadID '%@' is on the the cancelling list", threadID);
    } else {
        NSLog(@"DEBUG: isOnCancellingListIPCheckThread: threadID '%@' is not on the the cancelling list", threadID);
    }
    
    status = pthread_mutex_unlock( &threadIdsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &threadIdsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return NO;
    }
    
    return answer;
}

-(void) haveFinishedIPCheckThread: (NSString *) threadID
{
    OSStatus status = pthread_mutex_lock( &threadIdsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &threadIdsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    
    if (  [activeIPCheckThreads containsObject: threadID]  ) {
        NSLog(@"DEBUG: haveFinishedIPCheckThread: threadID '%@' removed from active list", threadID);
        [activeIPCheckThreads removeObject: threadID];
    }
    
    if (  [cancellingIPCheckThreads containsObject: threadID]  ) {
        NSLog(@"DEBUG: haveFinishedIPCheckThread: threadID '%@' removed from cancelling list", threadID);
        [cancellingIPCheckThreads removeObject: threadID];
    }

    status = pthread_mutex_unlock( &threadIdsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &threadIdsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
}


#ifdef INCLUDE_VPNSERVICE
//*********************************************************************************************************
//
// VPNService screen support
//
//*********************************************************************************************************

-(IBAction) registerForTunnelblickWasClicked: (id) sender
{
    [vpnService showRegisterForTunneblickVPNScreen];
}

-(BOOL) tryToConnect: (NSString *) displayName
{
    VPNConnection * connection = [[self myVPNConnectionDictionary] objectForKey: displayName];
    if (  connection  ) {
        [self setVPNServiceConnectDisplayName: displayName];
        [connection connect: self userKnows: YES];
        return YES;
    }
    
    TBRunAlertPanel(NSLocalizedString(@"No configuration available", @"Window title VPNService"),
                    [NSString stringWithFormat:
                     NSLocalizedString(@"There is no configuration named '%@' installed.\n\n"
                                       "Try reinstalling Tunnelblick from a disk image.", @"Window text VPNService"),
                     displayName],
                    nil,nil,nil);
    [NSApp activateIgnoringOtherApps:YES];
    return NO;
}

-(VPNService *) vpnService
{
    return [[vpnService retain] autorelease];
}


-(NSString *) vpnServiceConnectDisplayName
{
    return [[vpnServiceConnectDisplayName retain] autorelease];
}

-(void) setVPNServiceConnectDisplayName: (NSString *) newValue
{
    if ( vpnServiceConnectDisplayName != newValue  ) {
        [vpnServiceConnectDisplayName release];
        vpnServiceConnectDisplayName = [newValue retain];
    }
}
#endif

//*********************************************************************************************************
//
// StatusWindowController support
//
//*********************************************************************************************************

-(void) statusWindowController: (id) ctl
            finishedWithChoice: (StatusWindowControllerChoice) choice
                forDisplayName: (NSString *) theName
{
	(void) ctl;
	
    VPNConnection * connection = [[self myVPNConnectionDictionary] objectForKey: theName];
    if (  connection  ) {
        if (  choice == statusWindowControllerDisconnectChoice  ) {
            [connection addToLog: @"*Tunnelblick: Disconnecting; Disconnect button pressed"];
            [connection disconnectAndWait: [NSNumber numberWithBool: YES] userKnows: YES];
        } else if (  choice == statusWindowControllerConnectChoice  ) {
            [connection addToLog: @"*Tunnelblick: Connecting; Connect button pressed"];
            [connection connect: self userKnows: YES];
        } else {
            NSLog(@"Invalid choice -- statusWindowController:finishedWithChoice: %d forDisplayName: %@", choice, theName);
        }
    } else {
        NSLog(@"Invalid displayName -- statusWindowController:finishedWithChoice: %d forDisplayName: %@", choice, theName);
    }
}

//*********************************************************************************************************
//
// AppleScript support
//
//*********************************************************************************************************

-(BOOL) application: (NSApplication *) sender delegateHandlesKey: (NSString *) key
{
	(void) sender;
	
    if ([key isEqual:@"applescriptConfigurationList"]) {
        return YES;
    } else {
        return NO;
    }
}

-(NSArray *) applescriptConfigurationList
{
    NSArray *keyArray = [[[self myVPNConnectionDictionary] allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveNumericCompare:)];
    NSArray *myConnectionArray = [[self myVPNConnectionDictionary] objectsForKeys:keyArray notFoundMarker:[NSNull null]];
    return myConnectionArray;
}

//*********************************************************************************************************
//
// Getters and Setters
//
//*********************************************************************************************************

-(NSTimer *) showDurationsTimer
{
    return showDurationsTimer;
}

-(MyPrefsWindowController *) logScreen
{
    return logScreen;
}

-(NSString *) customRunOnConnectPath
{
    return customRunOnConnectPath;
}

-(SUUpdater *) updater
{
    return [[updater retain] autorelease];
}

-(NSArray *) connectionsToRestoreOnUserActive
{
    return [[connectionsToRestoreOnUserActive retain] autorelease];
}

-(NSMutableArray *) largeAnimImages
{
    return [[largeAnimImages retain] autorelease];
}

-(NSImage *) largeConnectedImage
{
    return [[largeConnectedImage retain] autorelease];
}

-(NSImage *) largeMainImage
{
    return [[largeMainImage retain] autorelease];
}

-(NSArray *) animImages
{
    return [[animImages retain] autorelease];
}

-(NSImage *) connectedImage
{
    return [[connectedImage retain] autorelease];
}

-(NSImage *) mainImage
{
    return [[mainImage retain] autorelease];
}

TBSYNTHESIZE_OBJECT_GET(retain, NSStatusItem *, statusItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenu *,       myVPNMenu)
TBSYNTHESIZE_OBJECT_GET(retain, NSMutableArray *, activeIPCheckThreads)
TBSYNTHESIZE_OBJECT_GET(retain, NSMutableArray *, cancellingIPCheckThreads)

TBSYNTHESIZE_OBJECT(retain, MainIconView *, ourMainIconView,           setOurMainIconView)
TBSYNTHESIZE_OBJECT(retain, NSDictionary *, myVPNConnectionDictionary, setMyVPNConnectionDictionary)
TBSYNTHESIZE_OBJECT(retain, NSDictionary *, myConfigDictionary,        setMyConfigDictionary)
TBSYNTHESIZE_OBJECT(retain, NSArray      *, connectionArray,           setConnectionArray)


// Event Handlers

-(void) showStatisticsWindowsTimerHandler: (NSTimer *) theTimer
{
    // Event handler; NOT on MainThread
    
	(void) theTimer;
	
    if (  gShuttingDownWorkspace  ) {  // Don't do anything if computer is shutting down or restarting
        return;
    }
    
    if (  [self mouseIsInsideAnyView] ) {
        [self performSelectorOnMainThread: @selector(showStatisticsWindows) withObject: nil waitUntilDone: NO];
    }
}

-(void) hideStatisticsWindowsTimerHandler: (NSTimer *) theTimer {
    // Event handler; NOT on MainThread
    
	(void) theTimer;
	
    if (  gShuttingDownWorkspace  ) {  // Don't do anything if computer is shutting down or restarting
        return;
    }
    
    if (  ! [self mouseIsInsideAnyView]  ) {
        [[NSApp delegate] performSelectorOnMainThread: @selector(hideStatisticsWindows) withObject: nil waitUntilDone: NO];
	}
}        


-(void) showOrHideStatisticsWindowsAfterDelay: (NSTimeInterval) delay
                                fromTimestamp: (NSTimeInterval) timestamp
                                     selector: (SEL)            selector
{
    
    // Event handlers invoke this; NOT on MainThread
    
    if (  gShuttingDownWorkspace  ) {  // Don't do anything if computer is shutting down or restarting
        return;
    }
    
    NSTimeInterval timeUntilAct;
    if (  timestamp == 0.0  ) {
        timeUntilAct = 0.0;
	} else if (  ! runningOnLeopardOrNewer()  ) {
		timeUntilAct = delay;
    } else {
        uint64_t systemStartNanoseconds = nowAbsoluteNanoseconds();
        NSTimeInterval systemStart = (  ((NSTimeInterval) systemStartNanoseconds) / 1.0e9  );
        timeUntilAct = timestamp - systemStart + delay;
    }
    
    [NSTimer scheduledTimerWithTimeInterval: timeUntilAct
                                     target: self
                                   selector: selector
                                   userInfo: nil
                                    repeats: NO];
}

-(void) mouseEnteredMainIcon: (id) control event: (NSEvent *) theEvent  {
    // Event handlers invoke this; NOT on MainThread

	(void) control;
	
    if (  gShuttingDownWorkspace  ) {
        return;
    }
        
    mouseIsInMainIcon = TRUE;
    [self showOrHideStatisticsWindowsAfterDelay: gDelayToShowStatistics
                                  fromTimestamp: ( theEvent ? [theEvent timestamp] : 0.0)
                                       selector: @selector(showStatisticsWindowsTimerHandler:)];
}

-(void) mouseExitedMainIcon: (id) control event: (NSEvent *) theEvent {
    // Event handlers invoke this; NOT on MainThread
    
	(void) control;
	
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    mouseIsInMainIcon = FALSE;
    [self showOrHideStatisticsWindowsAfterDelay: gDelayToHideStatistics
                                  fromTimestamp: ( theEvent ? [theEvent timestamp] : 0.0)
                                       selector: @selector(hideStatisticsWindowsTimerHandler:)];
}

-(void) mouseEnteredStatusWindow: (id) control event: (NSEvent *) theEvent  {
    // Event handlers invoke this; NOT on MainThread
    
	(void) control;
	
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    mouseIsInStatusWindow = TRUE;
    [self showOrHideStatisticsWindowsAfterDelay: gDelayToShowStatistics
                                  fromTimestamp: ( theEvent ? [theEvent timestamp] : 0.0)
                                       selector: @selector(showStatisticsWindowsTimerHandler:)];
}

-(void) mouseExitedStatusWindow: (id) control event: (NSEvent *) theEvent {
    // Event handlers invoke this; NOT on MainThread
    
	(void) control;
	
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    mouseIsInStatusWindow = FALSE;
    [self showOrHideStatisticsWindowsAfterDelay: gDelayToHideStatistics
                                  fromTimestamp: ( theEvent ? [theEvent timestamp] : 0.0)
                                       selector: @selector(hideStatisticsWindowsTimerHandler:)];
}

@end
