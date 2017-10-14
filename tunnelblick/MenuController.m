/*
 * Copyright 2004, 2005, 2006, 2007, 2008, 2009 Angelo Laub
 * Contributions by Dirk Theisen <dirk@objectpark.org>,
 *                  Jens Ohlig, 
 *                  Waldemar Brodkorb
 * Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017. All rights reserved.
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

#import <libkern/OSAtomic.h>
#import <pthread.h>
#import <sys/stat.h>
#import <sys/mount.h>

#import "MenuController.h"

#import "defines.h"
#import "easyRsa.h"
#import "helper.h"
#import "sharedRoutines.h"

#import "AuthAgent.h"
#import "ConfigurationManager.h"
#import "ConfigurationMultiUpdater.h"
#import "ConfigurationsView.h"
#import "ConfigurationUpdater.h"
#import "LeftNavItem.h"
#import "LeftNavViewController.h"
#import "MainIconView.h"
#import "MyPrefsWindowController.h"
#import "NSApplication+LoginItem.h"
#import "NSFileManager+TB.h"
#import "NSString+TB.h"
#import "NSTimer+TB.h"
#import "Sparkle/SUUpdater.h"
#import "SplashWindowController.h"
#import "SystemAuth.h"
#import "TBUIUpdater.h"
#import "TBUserDefaults.h"
#import "UIHelper.h"
#import "VPNConnection.h"
#import "WelcomeController.h"


#ifdef INCLUDE_VPNSERVICE
#import "VPNService.h"
#endif

// These are global variables rather than class variables to make access to them easier
NSThread              * gMainThread = nil;            // Used on 10.4 because [NSThread isMainThread] is not available
NSMutableArray        * gConfigDirs = nil;            // Array of paths to configuration directories currently in use
NSString              * gPrivatePath = nil;           // Path to ~/Library/Application Support/Tunnelblick/Configurations
NSString              * gDeployPath = nil;            // Path to Tunnelblick.app/Contents/Resources/Deploy
TBUserDefaults        * gTbDefaults = nil;            // Our preferences
NSFileManager         * gFileMgr = nil;               // [NSFileManager defaultManager]
NSArray               * gProgramPreferences = nil;    // E.g., 'placeIconInStandardPositionInStatusBar'
NSArray               * gConfigurationPreferences = nil; // E.g., '-onSystemStart'
BOOL                    gShuttingDownTunnelblick = FALSE;// TRUE if applicationShouldTerminate: has been invoked
BOOL                    gShuttingDownWorkspace = FALSE;
BOOL                    gShuttingDownOrRestartingComputer = FALSE;
BOOL                    gUserWasAskedAboutConvertNonTblks = FALSE;// Flag that the user has been asked to convert non-.tblk configurations
BOOL                    gOkToConvertNonTblks = FALSE; // Flag that the user has agreed to convert non-.tblk configurations
unsigned                gHookupTimeout = 0;           // Number of seconds to try to establish communications with (hook up to) an OpenVPN process
//                                                    // or zero to keep trying indefinitely
unsigned                gMaximumLogSize = 0;          // Maximum size (bytes) of buffer used to display the log
NSArray               * gRateUnits = nil;             // Array of strings with localized data units      (KB/s, MB/s, GB/s, etc.)
NSArray               * gTotalUnits = nil;            // Array of strings with localized data rate units (KB,   MB,   GB,   etc.)
NSTimeInterval          gDelayToShowStatistics = 0.0; // Time delay from mouseEntered icon or statistics window until showing the statistics window
NSTimeInterval          gDelayToHideStatistics = 0.0; // Time delay from mouseExited icon or statistics window until hiding the statistics window

volatile int32_t        gSleepWakeState = noSleepState;// Describes sleep/wake state
volatile int32_t        gActiveInactiveState = active;// Describes active/inactive

enum TerminationReason  reasonForTermination;         // Why we are terminating execution

UInt32 fKeyCode[16] = {0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64,        // KeyCodes for F1...F16
    0x65, 0x6D, 0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A};

void terminateBecauseOfBadConfiguration(void);

OSStatus hotKeyPressed(EventHandlerCallRef nextHandler,EventRef theEvent, void * userData);
OSStatus RegisterMyHelpBook(void);
BOOL checkOwnedByRootWheel(NSString * path);

unsigned needToRunInstaller(BOOL inApplications);

BOOL needToChangeOwnershipAndOrPermissions(BOOL inApplications);
BOOL needToMoveLibraryOpenVPN(void);
BOOL needToRepairPackages(void);
BOOL needToConvertNonTblks(void);

@interface MenuController() // PRIVATE METHODS

// System interfaces:
-(BOOL)             application:                            (NSApplication *)   theApplication
                      openFiles:                            (NSArray * )        filePaths;

-(void)             applicationDidFinishLaunching:          (NSNotification *)  notification;

-(void)             applicationWillFinishLaunching:         (NSNotification *)  notification;

// Private interfaces
-(void)             addCustomMenuItems;
-(BOOL)             addCustomMenuItemsFromFolder:           (NSString *)        folderPath
                                          toMenu:           (NSMenu *)          theMenu;
-(void)             addNewConfig:                           (NSString *)        path
                 withDisplayName:                           (NSString *)        dispNm;
-(void)             addOneCustomMenuItem:                   (NSString *)        file
                              fromFolder:                   (NSString *)        folder
                                  toMenu:                   (NSMenu *)          theMenu;
-(BOOL)             addOneCustomMenuSubmenu:                (NSString *)        file
                                 fromFolder:                (NSString *)        folder
                                     toMenu:                (NSMenu *)          theMenu;
-(BOOL)             canRunFromVolume:                       (NSString *)        path;
-(BOOL)             checkPlist:                             (NSString *)        path
                   renameIfBad:                             (BOOL)              renameIfBad;
-(NSURL *)          contactURL;
-(void)             createMenu;
-(void)             createStatusItem;
-(NSString *)       deconstructOpenVPNLogPath:              (NSString *)        logPath
                                       toPort:              (unsigned *)        portPtr
                                  toStartArgs:              (NSString * *)      startArgsPtr;
-(void)             deleteExistingConfig:                   (NSString *)        dispNm;
-(NSArray *)        findTblksToInstallInPath:               (NSString *)        thePath;
-(void)             checkNoConfigurations;
-(void)             deleteLogs;
-(void)             initialChecks:							(NSString *)        ourAppName;
-(BOOL)             hasValidSignature;
-(void)             hookupWatchdogHandler;
-(void)             hookupWatchdog;
-(void)             hookupToRunningOpenVPNs;
-(void)             initialiseAnim;
-(void)             insertConnectionMenuItem:               (NSMenuItem *)      theItem
                                    IntoMenu:               (NSMenu *)          theMenu
                                  afterIndex:               (int)               theIndex
                                    withName:               (NSString *)        displayName;
-(void)             checkSymbolicLink;
-(NSString *)       menuNameFromFilename:                   (NSString *)        inString;
-(void)             removeConnectionWithDisplayName:        (NSString *)        theName
                                           fromMenu:        (NSMenu *)          theMenu
                                         afterIndex:        (int)               theIndex;
-(void)             removeConnectionWithDisplayName:        (NSString *)        theName
                                           fromMenu:        (NSMenu *)          theMenu
                                         afterIndex:        (int)               theIndex
                                        workingName:        (NSString *)        workingName;
-(void)             runCustomMenuItem:                      (NSMenuItem *)      item;
-(BOOL)             setupHookupWatchdogTimer;
-(void)             setupHotKeyWithCode:                    (UInt32)            keyCode
                        andModifierKeys:                    (UInt32)            modifierKeys;
-(BOOL)				showWelcomeScreenForWelcomePath:        (NSString *)        welcomePath;
-(NSStatusItem *)   statusItem;
-(void)				updateMenuAndDetailsWindow;
-(void)             updateUI;
-(BOOL)             validateMenuItem:                       (NSMenuItem *)      anItem;
-(void) relaunchIfNecessary;
-(void) secureIfNecessary;

@end

@implementation MenuController

//*********************************************************************************************************
//
// Getters and Setters
//
//*********************************************************************************************************

TBSYNTHESIZE_NONOBJECT_GET(BOOL volatile, menuIsOpen)
TBSYNTHESIZE_NONOBJECT_GET(BOOL volatile, launchFinished)
TBSYNTHESIZE_NONOBJECT_GET(BOOL         , languageAtLaunchWasRTL)

TBSYNTHESIZE_NONOBJECT(BOOL         , doingSetupOfUI, setDoingSetupOfUI)

TBSYNTHESIZE_OBJECT_GET(retain, MyPrefsWindowController *,   logScreen)
TBSYNTHESIZE_OBJECT_GET(retain, NSString *,                  customRunOnConnectPath)
TBSYNTHESIZE_OBJECT_GET(retain, SUUpdater *,                 updater)
TBSYNTHESIZE_OBJECT_GET(retain, NSMutableArray *,            largeAnimImages)
TBSYNTHESIZE_OBJECT_GET(retain, NSImage *,                   largeConnectedImage)
TBSYNTHESIZE_OBJECT_GET(retain, NSImage *,                   largeMainImage)
TBSYNTHESIZE_OBJECT_GET(retain, NSArray *,                   animImages)
TBSYNTHESIZE_OBJECT_GET(retain, NSImage *,                   connectedImage)
TBSYNTHESIZE_OBJECT_GET(retain, NSImage *,                   mainImage)
TBSYNTHESIZE_OBJECT_GET(retain, NSStatusItem *,              statusItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenu *,                    myVPNMenu)
TBSYNTHESIZE_OBJECT_GET(retain, NSMutableArray *,            activeIPCheckThreads)
TBSYNTHESIZE_OBJECT_GET(retain, NSMutableArray *,            cancellingIPCheckThreads)
TBSYNTHESIZE_OBJECT_GET(retain, ConfigurationMultiUpdater *, myConfigMultiUpdater)

TBSYNTHESIZE_OBJECT(retain, SystemAuth   *, startupInstallAuth,        setStartupInstallAuth)
TBSYNTHESIZE_OBJECT(retain, NSStatusBarButton *, statusItemButton,          setStatusItemButton)
TBSYNTHESIZE_OBJECT(retain, NSArray      *, screenList,                setScreenList)
TBSYNTHESIZE_OBJECT(retain, MainIconView *, ourMainIconView,           setOurMainIconView)
TBSYNTHESIZE_OBJECT(retain, NSDictionary *, myVPNConnectionDictionary, setMyVPNConnectionDictionary)
TBSYNTHESIZE_OBJECT(retain, NSDictionary *, myConfigDictionary,        setMyConfigDictionary)
TBSYNTHESIZE_OBJECT(retain, NSArray      *, openvpnVersionNames,       setOpenvpnVersionNames)
TBSYNTHESIZE_OBJECT(retain, NSArray      *, connectionArray,           setConnectionArray)
TBSYNTHESIZE_OBJECT(retain, NSArray      *, nondisconnectedConnections,setNondisconnectedConnections)
TBSYNTHESIZE_OBJECT(retain, NSTimer      *, hookupWatchdogTimer,       setHookupWatchdogTimer)
TBSYNTHESIZE_OBJECT(retain, TBUIUpdater  *, uiUpdater,                 setUiUpdater)
TBSYNTHESIZE_OBJECT(retain, NSTimer      *, statisticsWindowTimer,     setStatisticsWindowTimer)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, highlightedAnimImages,   setHighlightedAnimImages)
TBSYNTHESIZE_OBJECT(retain, NSImage      *, highlightedConnectedImage, setHighlightedConnectedImage)
TBSYNTHESIZE_OBJECT(retain, NSImage      *, highlightedMainImage,      setHighlightedMainImage)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, connectionsToRestoreOnUserActive, setConnectionsToRestoreOnUserActive)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, connectionsToRestoreOnWakeup,     setConnectionsToRestoreOnWakeup)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, connectionsToWaitForDisconnectOnWakeup, setConnectionsToWaitForDisconnectOnWakeup)
TBSYNTHESIZE_OBJECT(retain, NSBundle     *, deployLocalizationBundle,  setDeployLocalizationBundle)
TBSYNTHESIZE_OBJECT(retain, NSString     *, languageAtLaunch,          setLanguageAtLaunch)
TBSYNTHESIZE_OBJECT(retain, NSString     *, publicIPAddress,           setPublicIPAddress)
TBSYNTHESIZE_OBJECT(retain, NSString     *, tunnelblickVersionString,  setTunnelblickVersionString)


-(NSString *) localizedString: (NSString *) key
				   fromBundle: (NSBundle *) bundle {
	
	if (  key) {
		if (  bundle  ) {
			return [bundle localizedStringForKey: key value: nil table: @"Localizable"];
		}
		
		return [[key copy] autorelease];
	}
	
	NSLog(@"MenuController:localizedString: key is nil; stack trace: %@", callStack());
	return @"";
}

-(NSString *) localizedString: (NSString *) key {
	
	return [self localizedString: key fromBundle: [self deployLocalizationBundle]];
}


-(NSString *) localizedString: (NSString *) key
			   fromBundlePath: (NSString *) bundlePath {
	
	NSBundle * bundle = [NSBundle bundleWithPath: bundlePath];
	if (  ! bundle) {
		NSLog(@"Not a bundle: %@", bundlePath);
		return @"Invalid bundle";
	}
	
	return [self localizedString: key fromBundle: bundle];
}

-(NSString *) localizedString: (NSString *) key
				   fromBundle: (NSBundle *) firstBundle
				     orBundle: (NSBundle *) secondBundle {
	
	if (  firstBundle  ) {
		NSString * localName = [self localizedString: key fromBundle: firstBundle];
		if (   localName
			&& ( ! [localName isEqualToString: key] )  ) {
			return localName;
		}
	}
	
	return [self localizedString: key fromBundle: secondBundle];
}

-(NSString *) localizedNameforDisplayName: (NSString *) displayName
                                 tblkPath: (NSString *) tblkPath  {
	
	NSBundle * bundle = [NSBundle bundleWithPath: tblkPath];
	NSMutableString * localName = [NSMutableString stringWithCapacity: 2 * [displayName length]];
	NSArray * components = [displayName componentsSeparatedByString: @"/"];
	if (  [components count] > 1  ) {
		NSUInteger i;
		for (  i=0; i<[components count] - 1; i++  ) {
			NSString * nonLocalizedName = [components objectAtIndex: i];
			
			[localName appendFormat: @"%@/", [self localizedString: nonLocalizedName fromBundle: bundle orBundle: [self deployLocalizationBundle]]];
		}
	}
	
	NSString * nonLocalizedName = [components lastObject];
	[localName appendString: [self localizedString: nonLocalizedName fromBundle: bundle orBundle: [self deployLocalizationBundle]]];
	return [NSString stringWithString: localName];
}

-(NSString *) localizedNameForDisplayName: (NSString *) displayName {
    
    NSString * path = [myConfigDictionary objectForKey: displayName];
    if (  ! path  ) {
        NSLog(@"localNameFromDisplayName: '%@' is not a known displayName", displayName);
        return displayName;
    }
    
    return [self localizedNameforDisplayName: displayName tblkPath: path];
}

-(NSDictionary *) tunnelblickInfoDictionary {
    
    // We get the Info.plist contents as follows because NSBundle's objectForInfoDictionaryKey: method returns the object as it was at
    // compile time, before the TBBUILDNUMBER is replaced by the actual build number (which is done in the final run-script that builds Tunnelblick)
    // By constructing the path, we force the objects to be loaded with their values at run time.
    
    NSString * plistPath    = [[[[NSBundle mainBundle] bundlePath]
                                stringByAppendingPathComponent: @"Contents"]
                               stringByAppendingPathComponent: @"Info.plist"];
    NSDictionary * infoDict = [NSDictionary dictionaryWithContentsOfFile: plistPath];
    if (  ! infoDict  ) {
        NSLog(@"Info.plist invalid at path %@", plistPath);
        [self terminateBecause: terminatingBecauseOfFatalError];
    }
    return infoDict;
}

-(id) init
{	
    if (  (self = [super init])  ) {
        
        reasonForTermination = terminatingForUnknownReason;
        
		doingSetupOfUI = FALSE;
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
        
        noUnknownOpenVPNsRunning = NO;   // We assume there are unattached processes until we've had time to hook up to them
		
		menuIsOpen = FALSE;
        
        iconPosition = iconNotShown;
        
        dotTblkFileList = [[NSMutableArray arrayWithCapacity: 10] retain];
        uiUpdater = nil;
        customRunOnLaunchPath = nil;
        customRunOnConnectPath = nil;
        customMenuScripts = nil;
                
        tunCount = 0;
        tapCount = 0;
		
		iconTrackingRectTag = 0;
        
        gProgramPreferences = [[NSArray arrayWithObjects:
                                
                                @"DB-ALL",    // All extra logging
								@"DB-AA",     // Extra logging for system authorization (for executeAuthorized)
                                @"DB-AU",	  // Extra logging for VPN authorization
                                @"DB-CD",     // Extra logging for connect/disconnect
                                @"DB-DD",     // Extra logging for drag/drop onto VPN Details window
                                @"DB-HU",     // Extra logging for hookup,
                                @"DB-IC",     // Extra logging for IP address checking
                                @"DB-IT",     // Extra logging for IP address check threading
                                @"DB-MO",     // Extra logging for mouseover (of icon and status windows)
                                @"DB-PU",     // Extra logging for information popups
								@"DB-SD",     // Extra logging for shutdown
                                @"DB-SI",     // Extra logging for status item creation/deletion/move
                                @"DB-SU",     // Extra logging for startup
                                @"DB-SW",     // Extra logging for sleep/wake and inactive user/active user
                                @"DB-TD",     // Extra logging for tunnelblickd interactions,
                                @"DB-UC",     // Extra logging for updating configurations
                                @"DB-UP",     // Extra logging for the up script
								@"DB-UU",	  // Extra logging for UI updates
								
								@"useRtlLayout",	// Use RTL language layout, regardless of language (for debugging RTL layout issues)
                                
                                @"allowNonAdminSafeConfigurationReplacement",  // Must be forced; regular preference is ignored
                                
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
                                @"skipWarningThatIPANotFetchedBeforeConnection",
                                @"skipWarningThatIPAddressDidNotChangeAfterConnection",
                                @"skipWarningThatDNSIsNotWorking",
                                @"skipWarningThatInternetIsNotReachable",
								@"skipWarningAboutInvalidSignature",
								@"skipWarningAboutNoSignature",
                                @"skipWarningAboutSystemClock",
                                @"skipWarningAboutUnavailableOpenvpnVersions",
                                @"skipWarningAbout64BitVersionOnSnowLeopardPointEight",
                                @"skipWarningAbout64BitVersionWithTap",
                                @"skipWarningAbout64BitVersionWithTunOnSnowLeopardPointEight",
                                @"skipWarningAbout64BitVersionOnNonSnowLeopardPointEight",
                                @"skipWarningAboutInstallsWithCommands",
                                @"skipWarningAboutPreAuthorizedActivity",
                                @"skipWarningAboutPlacingIconNearTheSpotlightIcon",
                                
                                @"timeoutForOpenvpnToTerminateAfterDisconnectBeforeAssumingItIsReconnecting",
                                @"timeoutForIPAddressCheckBeforeConnection",
                                @"timeoutForIPAddressCheckAfterConnection",
                                @"timeoutForIPAddressCheckAfterSleeping",
                                @"delayBeforeReconnectingAfterSleep",
                                @"delayBeforeReconnectingAfterSleepAndIpaFetchError",
                                @"delayBeforeIPAddressCheckAfterConnection",
								@"delayBeforeSlowDisconnectDialog",
								@"delayBeforePopupHelp",
                                @"hookupTimeout",
                                @"displayUpdateInterval",
                                @"managementPortStartingPortNumber",
                                
								@"inhibitOutboundTunneblickTraffic",
                                @"placeIconInStandardPositionInStatusBar",
                                @"doNotMonitorConfigurationFolder",
								@"doNotLaunchOnLogin", // DISABLE the ability to launch on login provided by launchAtNextLogin
                                @"launchAtNextLogin",
                                @"onlyAdminsCanUnprotectConfigurationFiles",
                                @"standardApplicationPath",
                                @"doNotCreateLaunchTunnelblickLinkinConfigurations",
                                @"useShadowConfigurationFiles",
                                @"menuIconSet",
                                @"easy-rsaPath",
                                @"IPAddressCheckURL",
                                @"notOKToCheckThatIPAddressDidNotChangeAfterConnection",
                                @"tunnelblickVersionHistory",
								@"statusDisplayNumber",
                                @"lastLaunchTime",
                                @"allow64BitIntelOpenvpnOnTigerOrLeopard",
								@"doNotRedisplayLoginOrPassphraseWindowAtScreenChangeOrWakeFromSleep",
                                @"doNotEjectTunnelblickVolume",
                                
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
                                @"disableShowHideOnTbMenuItem",
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
                                
                                @"welcomeURL",
                                @"welcomeWidth",
                                @"welcomeHeight",
                                @"doNotShowWelcomeDoNotShowAgainCheckbox",
                                @"skipWelcomeScreen",
                                @"lastLanguageAtLaunchWasRTL",
                                
                                @"openvpnVersion",
                                @"maximumNumberOfTabs",
                                @"onlyAdminCanUpdate",
                                @"connectionWindowDisplayCriteria",
                                @"showTooltips",
                                @"maxLogDisplaySize",
                                @"lastConnectedDisplayName",
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
                                @"updateCheckBetas",
                                @"updateCheckInterval",
                                @"updateFeedURL",
                                @"updateSigned",
                                @"updateUnsigned",
                                
                                @"NSWindow Frame SettingsSheetWindow",
                                @"NSWindow Frame ConnectingWindow",
                                @"NSWindow Frame SUStatusFrame",
								@"NSWindow Frame SUUpdateAlert",
                                @"NSWindow Frame ListingWindow",
                                @"detailsWindowFrameVersion",
                                @"detailsWindowFrame",
                                @"detailsWindowLeftFrame",
								@"detailsWindowViewIndex",
								@"detailsWindowConfigurationsTabIdentifier",
								@"leftNavOutlineViewExpandedDisplayNames",
								@"leftNavSelectedDisplayName",
								@"AdvancedWindowTabIdentifier",
                                
                                @"haveDealtWithOldTunTapPreferences",
                                @"haveDealtWithOldLoginItem",
                                @"haveStartedAnUpdateOfTheApp",
                                
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
								@"askedUserIfOKToCheckThatIPAddressDidNotChangeAfterConnection",
                                @"doNotShowCheckForUpdatesNowMenuItem",
                                @"doNotShowForcedPreferenceMenuItems",
                                @"doNotShowKeyboardShortcutSubmenu",
                                @"doNotShowOptionsSubmenu",
								@"haveDealtWithSparkle1dot5b6",
                                @"keyboardShortcutKeyCode",
                                @"keyboardShortcutModifiers",
                                @"maximumLogSize",
                                @"skipWarningAboutUsingOpenvpnTxpVersion",
                                @"skipWarningAboutUsingOpenvpnNonTxpVersion",
                                @"skipWarningAboutNoOpenvpnTxpVersion",
                                @"skipWarningAboutOnlyOpenvpnTxpVersion",
                                @"tunnelblickdHash",
                                @"tunnelblickdPlistHash",
								@"updateSendProfileInfo",
                                
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
                                      @"-runMtuTest",
                                      @"-doNotFlushCache",
                                      @"-useRouteUpInsteadOfUp",
                                      @"-useDownRootPlugin",
                                      @"-keychainHasPrivateKey",
                                      @"-keychainHasUsernameAndPassword",
                                      @"-keychainHasUsername",
                                      @"-doNotParseConfigurationFile",
                                      @"-disableEditConfiguration",
                                      @"-disableConnectButton",
                                      @"-disableDisconnectButton",
                                      @"-doNotLoadTapKext",
                                      @"-doNotLoadTunKext",
                                      @"-loadTapKext",
                                      @"-loadTunKext",
                                      @"-loadTap",
                                      @"-loadTun",
                                      @"-credentialsGroup",
									  @"-openvpnVersion",
									  @"-notOKToCheckThatIPAddressDidNotChangeAfterConnection",
									  @"-keepConnected",
                                      @"-doNotDisconnectOnSleep",
									  @"-doNotUseDefaultDomain",
                                      @"-waitForDHCPInfoIfTap",
                                      @"-enableIpv6OnTap",
                                      @"-doNotDisableIpv6onTun",
                                      @"-loggingLevel",
									  
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
                                      @"-doNotWaitForInternetAtBoot",
                                      @"-doNotReconnectOnUnexpectedDisconnect", // This preference is NOT IMPLEMENTED and it is not in the .xib

                                      @"-doNotShowOnTunnelblickMenu",
                                      
                                      // No longer used
                                      @"-authUsername",
                                      @"-usernameIsSet",
                                      nil] retain];
        
        connectionsToRestoreOnWakeup = [[NSMutableArray alloc] initWithCapacity: 5];
        
        gFileMgr    = [NSFileManager defaultManager];
        
        TBLog(@"DB-SU", @"init: 000")
        
        unsigned major, minor, bugFix;
        NSString * osVersionString = (  getSystemVersion(&major, &minor, &bugFix) == EXIT_SUCCESS
                                      ? [NSString stringWithFormat:@"%d.%d.%d", major, minor, bugFix]
                                      : @"version is unknown");
        NSLog(@"Tunnelblick: OS X %@; %@", osVersionString, tunnelblickVersion([NSBundle mainBundle]));
        
		// Create private configurations folder if necessary
        gPrivatePath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Tunnelblick/Configurations"] copy];
        if (  createDir(gPrivatePath, privateFolderPermissions(gPrivatePath)) == -1  ) {
			NSLog(@"Unable to create %@", gPrivatePath);
			exit(1);
		}
        
        gConfigDirs = [[NSMutableArray alloc] initWithCapacity: 2];
        
		[NSApp setDelegate: (id)self];
		
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
        
        [self checkPlist: [gDeployPath stringByAppendingPathComponent: @"forced-preferences.plist"] renameIfBad: NO];

		// Remove any old "Launch Tunnelblick" link in the private configurations folder
		NSString * tbLinkPath = [gPrivatePath stringByAppendingPathComponent: @"Launch Tunnelblick"];
		if (  [gFileMgr fileExistsAtPath: tbLinkPath]  ) {
			[gFileMgr tbRemoveFileAtPath: tbLinkPath handler: nil];
        }
		
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
        
        // Check that the preferences are OK or don't exist
        [self checkPlist: @"/Library/Preferences/net.tunnelblick.tunnelblick.plist" renameIfBad: NO];
        [self checkPlist: [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Preferences/net.tunnelblick.tunnelblick.plist"] renameIfBad: YES];
		
        // Set up to override user preferences with preferences from L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH and Deploy/forced-permissions.plist
        NSDictionary * primaryForcedPreferencesDict = nil;
        NSDictionary * deployedForcedPreferencesDict = nil;
        if (  [gFileMgr fileExistsAtPath: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH]  ) {
            primaryForcedPreferencesDict  = [NSDictionary dictionaryWithContentsOfFile: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH];
            if (  ! primaryForcedPreferencesDict  ) {
                NSLog(@".plist is being ignored because it is corrupt or unreadable: %@", L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);
            }
        }
        NSString * deployedForcedPreferencesPath = [gDeployPath stringByAppendingPathComponent: @"forced-preferences.plist"];
        if (  [gFileMgr fileExistsAtPath: deployedForcedPreferencesPath]  ) {
            deployedForcedPreferencesDict  = [NSDictionary dictionaryWithContentsOfFile: deployedForcedPreferencesPath];
            if (  ! deployedForcedPreferencesPath  ) {
                NSLog(@".plist is being ignored because it is corrupt or unreadable: %@", deployedForcedPreferencesPath);
            }
        }
        gTbDefaults = [[TBUserDefaults alloc] initWithPrimaryDictionary: primaryForcedPreferencesDict
                                                  andDeployedDictionary: deployedForcedPreferencesDict];
        if (  ! gTbDefaults  ) {
            return nil; // An error was already logged
        }
        
        TBLog(@"DB-SU", @"init: 001")
        
		NSDictionary * infoPlist = [self tunnelblickInfoDictionary];
		[self setTunnelblickVersionString: [infoPlist objectForKey: @"CFBundleShortVersionString"]];
		
        if (  ! [gTbDefaults boolForKey: @"doNotShowSplashScreen"]  ) {
            splashScreen = [[SplashWindowController alloc] init];
			NSString * text = [NSString stringWithFormat: NSLocalizedString(@"Starting Tunnelblick %@...", @"Window text; '%@' will be replaced with a version number such as '3.6.10'"), [self tunnelblickVersionString]];
            [splashScreen setMessage: text];
            [splashScreen showWindow: self];
        }
		
        TBLog(@"DB-SU", @"init: 002")
        
        TBLog(@"DB-SU", @"init: 003")
		// Set the new per-configuration "*-openvpnVersion" preference from the old global "openvpnVersion" preference to
		NSString * version = [gTbDefaults stringForKey: @"openvpnVersion"];
		if (  version  ) {
			if (  ! [[gTbDefaults stringForKey: @"*-openvpnVersion"] isEqualToString: version]  ) {
				[gTbDefaults setObject: version forKey: @"*-openvpnVersion"];
				NSLog(@"Set the new '*-openvpnVersion' preference from the 'openvpnVersion' preference");
			}
		}
        
        TBLog(@"DB-SU", @"init: 004")
        TBLog(@"DB-SU", @"init: 005")
		// Set the new per-configuration "*-notOKToCheckThatIPAddressDidNotChangeAfterConnection" preference from the old global "notOKToCheckThatIPAddressDidNotChangeAfterConnection" preference to
		id obj = [gTbDefaults objectForKey: @"notOKToCheckThatIPAddressDidNotChangeAfterConnection"];
		if (  obj  ) {
            if (  [obj respondsToSelector: @selector(boolValue)]  ) {
				if (  [obj boolValue] != [gTbDefaults boolForKey: @"*-notOKToCheckThatIPAddressDidNotChangeAfterConnection"]  ) {
					[gTbDefaults setBool: [obj boolValue] forKey: @"*-notOKToCheckThatIPAddressDidNotChangeAfterConnection"];
					NSLog(@"Set the new '*-notOKToCheckThatIPAddressDidNotChangeAfterConnection' preference from the 'notOKToCheckThatIPAddressDidNotChangeAfterConnection' preference");
				}
            } else {
                NSLog(@"Preference 'notOKToCheckThatIPAddressDidNotChangeAfterConnection' is not a boolean; it is being removed");
				[gTbDefaults removeObjectForKey: @"notOKToCheckThatIPAddressDidNotChangeAfterConnection"];
            }
        }
        
        // Set up for the rest
        NSString * bundleId = [[NSBundle mainBundle] bundleIdentifier];
        NSString * prefsPath = [[[[NSHomeDirectory()
                                   stringByAppendingPathComponent:@"Library"]
                                  stringByAppendingPathComponent:@"Preferences"]
                                 stringByAppendingPathComponent: bundleId]
                                stringByAppendingPathExtension: @"plist"];
        NSDictionary * userDefaultsDict = [NSDictionary dictionaryWithContentsOfFile: prefsPath];
        
        TBLog(@"DB-SU", @"init: 006")
        // Convert the old "-loadTunKext", "-doNotLoadTunKext", "-loadTapKext", and "-doNotLoadTapKext"  to the new '-loadTun' and 'loadTap' equivalents
        // That is, if NOTLOAD set to NEVER
        //          else if LOAD, set to ALWAYS
        // (Default is automatic, indicated by no preference)
        if (  ! [gTbDefaults preferenceExistsForKey: @"haveDealtWithOldTunTapPreferences"]) {

			NSMutableArray * loadTunConfigNames      = [[[NSMutableArray alloc] initWithCapacity: 100] autorelease];
            NSMutableArray * loadTapConfigNames      = [[[NSMutableArray alloc] initWithCapacity: 100] autorelease];
            NSMutableArray * doNotLoadTunConfigNames = [[[NSMutableArray alloc] initWithCapacity: 100] autorelease];
            NSMutableArray * doNotLoadTapConfigNames = [[[NSMutableArray alloc] initWithCapacity: 100] autorelease];
            
            NSString * key;
            NSEnumerator * e = [userDefaultsDict keyEnumerator];
            while (  (key = [e nextObject])  ) {
                NSRange r = [key rangeOfString: @"-" options: NSBackwardsSearch];
                if (  r.length != 0  ) {
                    NSString * configName = [key substringWithRange: NSMakeRange(0, r.location)];
                    if      (  [key hasSuffix: @"-loadTunKext"]      ) { [loadTunConfigNames      addObject: configName]; }
                    else if (  [key hasSuffix: @"-loadTapKext"]      ) { [loadTapConfigNames      addObject: configName]; }
                    else if (  [key hasSuffix: @"-doNotLoadTunKext"] ) { [doNotLoadTunConfigNames addObject: configName]; }
                    else if (  [key hasSuffix: @"-doNotLoadTapKext"] ) { [doNotLoadTapConfigNames addObject: configName]; }
                }
            }
            
            NSString * configName;
            e = [loadTunConfigNames objectEnumerator];
            while (  (configName = [e nextObject])  ) {
                if (  ! [doNotLoadTunConfigNames containsObject: configName]  ) {
                    [gTbDefaults setObject: @"always" forKey: [configName stringByAppendingString: @"-loadTun"]];
                }
            }
            
            e = [loadTapConfigNames objectEnumerator];
            while (  (configName = [e nextObject])  ) {
                if (  ! [doNotLoadTapConfigNames containsObject: configName]  ) {
                    [gTbDefaults setObject: @"always" forKey: [configName stringByAppendingString: @"-loadTap"]];
                }
            }
            
            e = [doNotLoadTunConfigNames objectEnumerator];
            while (  (configName = [e nextObject])  ) {
                [gTbDefaults setObject: @"never" forKey: [configName stringByAppendingString: @"-loadTun"]];
            }
            
            e = [doNotLoadTapConfigNames objectEnumerator];
            while (  (configName = [e nextObject])  ) {
                [gTbDefaults setObject: @"never" forKey: [configName stringByAppendingString: @"-loadTap"]];
            }
            
            [gTbDefaults setBool: TRUE forKey: @"haveDealtWithOldTunTapPreferences"];
        }
        
        TBLog(@"DB-SU", @"init: 007")
		// Scan for unknown preferences
        [gTbDefaults scanForUnknownPreferencesInDictionary: primaryForcedPreferencesDict  displayName: @"Primary forced preferences"];
        [gTbDefaults scanForUnknownPreferencesInDictionary: deployedForcedPreferencesDict displayName: @"Deployed forced preferences"];
        [gTbDefaults scanForUnknownPreferencesInDictionary: userDefaultsDict              displayName: @"preferences"];
        
        TBLog(@"DB-SU", @"init: 008")
        // Check any symbolic link to the private configurations folder, after having run the installer (which may have moved the
        // configuration folder contents to the new place)
        [self checkSymbolicLink];
        
        TBLog(@"DB-SU", @"init: 009")
        // Check that we can run Tunnelblick from this volume, that it is in /Applications, and that it is secured
        [self initialChecks: ourAppName];    // WE MAY NOT RETURN FROM THIS METHOD (it may install a new copy of Tunnelblick, launch it, and quit)
		
        TBLog(@"DB-SU", @"init: 010")
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
			
			[self setDeployLocalizationBundle: [NSBundle bundleWithPath: [gDeployPath stringByAppendingPathComponent: @"Localization.bundle"]]];
        }
        
        TBLog(@"DB-SU", @"init: 011")
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
        
        gDelayToShowStatistics = [gTbDefaults timeIntervalForKey: @"delayToShowStatistics"
                                                         default: 0.5
                                                             min: 0.0
                                                             max: 60.0];
        
        gDelayToHideStatistics = [gTbDefaults timeIntervalForKey: @"delayToHideStatistics"
                                                         default: 1.5
                                                             min: 0.0
                                                             max: 60.0];
        
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
        
        TBLog(@"DB-SU", @"init: 012")
        if (  ! [self loadMenuIconSet]  ) {
            NSLog(@"Unable to load the Menu icon set");
            [self terminateBecause: terminatingBecauseOfError];
        }
        
        TBLog(@"DB-SU", @"init: 013")
        myConfigDictionary = [[ConfigurationManager getConfigurations] copy];
        
        TBLog(@"DB-SU", @"init: 014")
        // set up myVPNConnectionDictionary, which has the same keys as myConfigDictionary, but VPNConnections as objects
        NSMutableDictionary * tempVPNConnectionDictionary = [[NSMutableDictionary alloc] init];
        NSString * dispNm;
        NSEnumerator * e = [myConfigDictionary keyEnumerator];
        while (  (dispNm = [e nextObject])  ) {
            NSString * cfgPath = [[self myConfigDictionary] objectForKey: dispNm];
            // configure connection object:
            VPNConnection* myConnection = [[[VPNConnection alloc] initWithConfigPath: cfgPath
                                                                     withDisplayName: dispNm] autorelease];
            [tempVPNConnectionDictionary setObject: myConnection forKey: dispNm];
        }
        [self setMyVPNConnectionDictionary: [[tempVPNConnectionDictionary copy] autorelease]];
        [tempVPNConnectionDictionary release];
        
        TBLog(@"DB-SU", @"init: 015")
		[self createMenu];
        
        TBLog(@"DB-SU", @"init: 015.1")
		[self createStatusItem];
		
        [self setState: @"EXITING"]; // synonym for "Disconnected"
        
        TBLog(@"DB-SU", @"init: 016")
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(TunnelblickShutdownUIHandler:) 
                                                     name: @"TunnelblickUIShutdownNotification" 
                                                   object: nil];
        
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(screenParametersChangedHandler:)
                                                     name: NSApplicationDidChangeScreenParametersNotification
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
#ifndef NSWorkspaceActiveDisplayDidChangeNotification
#define NSWorkspaceActiveDisplayDidChangeNotification @"NSWorkspaceActiveDisplayDidChangeNotification"
#endif
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                               selector: @selector(activeDisplayDidChangeHandler:)
                                                                   name: NSWorkspaceActiveDisplayDidChangeNotification
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
        
        TBLog(@"DB-SU", @"init: 017")
		
        updater = [[SUUpdater alloc] init];
		
		if (  [updater respondsToSelector: @selector(setDelegate:)]  ) {
			[updater setDelegate: (id)self];
		} else {
			NSLog(@"Cannot set Sparkle delegate because Sparkle Updater does not respond to setDelegate:");
		}
        TBLog(@"DB-SU", @"init: 018 - LAST")
    }
    
    return self;
}

-(void) reactivateTunnelblick {
	
	// When Tunnelblick gets an AuthorizationRef, OS X does that by activating Finder to display
	// a dialog asking for the username/password of an admin user. When the user dismisses the
	// dialog, Finder is left activated, not Tunnelblick, and Finder windows that overlap Tunnelblick
	// windows will obsure them.
	//
	// Because [NSApp activateIgnoringOtherApps:] does not work, this method executes a shell script
    // which uses AppleScript to activate Tunnelblick. It launches the script and returns immediately
    // without waiting for the script to complete, because Tunnelblick needs to finish the run loop
    // so it can respond to the "activate". (The script doesn't run until this routine returns and
    // its caller finishes the run loop, and if this routine waits for the script to finish,
    // that will never happen, so there will be a deadlock!)
	
	NSString * scriptPath = [[NSBundle mainBundle] pathForResource: @"reactivate-tunnelblick" ofType: @"sh"];
	NSTask * task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath: scriptPath];
    [task setCurrentDirectoryPath: @"/private/tmp"];
    [task setEnvironment: getSafeEnvironment()];
    [task launch];
}

-(void)allNotificationsHandler: (NSNotification *) n
{
    NSString * name = [n name];
    NSLog(@"NOTIFICATION              : %@", name);
    if (   name
        && [[gTbDefaults stringForKey: @"notificationsVerbose"] isEqualToString: name]  ) {
        NSLog(@"NOTIFICATION              : %@; object = %@; userInfo = %@", [n name], [n object], [n userInfo]);
    }
}

-(void)allDistributedNotificationsHandler: (NSNotification *) n
{
    NSString * name = [n name];
    NSLog(@"NOTIFICATION (Distributed): %@", name);
    if (   name
        && [[gTbDefaults stringForKey: @"notificationsVerbose"] isEqualToString: name]  ) {
        NSLog(@"NOTIFICATION (Distributed): %@; object = %@; userInfo = %@", [n name], [n object], [n userInfo]);
    }
}

-(void)allWorkspaceNotificationsHandler: (NSNotification *) n
{
    NSString * name = [n name];
    NSLog(@"NOTIFICATION   (Workspace): %@", name);
    if (   name
        && [[gTbDefaults stringForKey: @"notificationsVerbose"] isEqualToString: name]  ) {
        NSLog(@"NOTIFICATION   (Workspace): %@; object = %@; userInfo = %@", [n name], [n object], [n userInfo]);
    }
}

// Check that the old configurations folder (if it exists) has been replaced with a symbolic link to the new configurations folder
- (void) checkSymbolicLink
{
	BOOL isDir;
	NSString * oldConfigDirPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/openvpn"];
	if (  [gFileMgr fileExistsAtPath: oldConfigDirPath isDirectory: &isDir]  ) {
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
		}
	}
}

- (void) dealloc
{
    [uiUpdater release];
    [animImages release];
    [connectedImage release];
    [mainImage release];
    [highlightedAnimImages release];
    [highlightedConnectedImage release];
    [highlightedMainImage release];
	
    [gConfigDirs release];
	
    [gTbDefaults release];
    [connectionArray release];
    [nondisconnectedConnections release];
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
    [myConfigMultiUpdater release];
    [customMenuScripts release];
    [customRunOnLaunchPath release];
    [customRunOnConnectPath release];
    
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

-(BOOL) checkPlist: (NSString *) path renameIfBad: (BOOL) renameIfBad {
    
    // Checks the syntax of a .plist using plutil.
    // If 'renameIfBad' is set and the .plist is bad, renames the .plist to be xxx.plist.bad and displays a warning dialog
    
    if (  ! [gFileMgr fileExistsAtPath: path]  ) {
        TBLog(@"DB-SU", @"No file to check at %@", path)
        return YES;
    }
    
    if (  ! [gFileMgr fileExistsAtPath: TOOL_PATH_FOR_PLUTIL]  ) {
        NSLog(@"No 'plutil at %@", TOOL_PATH_FOR_PLUTIL);
        return YES;
    }
    
    NSArray *  arguments = [NSArray arrayWithObject: path];
    NSString * stdOutput = nil;
    NSString * errOutput = nil;
    OSStatus status = runTool(TOOL_PATH_FOR_PLUTIL, arguments, &stdOutput, &errOutput);
    if (  status == EXIT_SUCCESS  ) {
        TBLog(@"DB-SU", @"Preferences OK at %@", path)
        return YES;
    }
    
    NSLog(@"Preferences are corrupted at %@:\nstdout from plutil:\n%@stderr from plutil:\n%@", path, stdOutput, errOutput);
    
    if (  renameIfBad  ) {
        NSString * dotBadPath = [path stringByAppendingPathExtension: @"bad"];
        if (  [gFileMgr fileExistsAtPath: dotBadPath]  ) {
            if (  ! [gFileMgr tbRemoveFileAtPath: dotBadPath handler: nil]  ) {
                NSLog(@"Unable to delete %@", dotBadPath);
            }
        }
        if (  [gFileMgr tbMovePath: path toPath: dotBadPath handler: nil]  ) {
            NSLog(@"Renamed %@ to %@", path, [dotBadPath lastPathComponent]);
        } else {
            NSLog(@"Unable to rename %@ to %@", path, [dotBadPath lastPathComponent]);
        }
        
        TBShowAlertWindow(NSLocalizedString(@"Warning", @"Window title"),
						 NSLocalizedString(@"The Tunnelblick preferences were corrupted and have been cleared. (The old preferences were renamed.)\n\nSee the Console Log for details.", @"Window text"));
    }
    
    return NO;
}

- (void) removeStatusItem {
    
    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    if (  ! bar  ) {
        NSLog(@"removeStatusItem: Could not get system status bar");
    }
    
    if (  statusItem  ) {
        if (   iconTrackingRectTag != 0  ) {
            if (  statusItemButton  ) {
                TBLog(@"DB-SI", @"removeStatusItem: Removing tracking rectangle for status item")
                [statusItemButton removeTrackingRect: iconTrackingRectTag];
            } else {
                NSLog(@"removeStatusItem: Did not remove tracking rectangle for status item because there was no statusItemButton");
            }
            iconTrackingRectTag = 0;
        } else {
            TBLog(@"DB-SI", @"removeStatusItem: No tracking rectangle to remove")
        }
        TBLog(@"DB-SI", @"removeStatusItem: Removing status item from status bar")
        [bar removeStatusItem: statusItem];
        [statusItem release];
        statusItem = nil;
        iconPosition = iconNotShown;
    }
}

- (void) createStatusItem {
    
    // Places an item with our icon in the Status Bar (creating it first if it doesn't already exist)
    // By default, it uses an undocumented hack to place the icon on the right side, next to SpotLight
    // Otherwise ("placeIconInStandardPositionInStatusBar" preference or hack not available), it places it normally (on the left)
    // On Mavericks & higher with multiple displays and "Displays have different spaces" enabled in Mission Control System Preferences, it always places it normally (on the left)

	NSStatusBar *bar = [NSStatusBar systemStatusBar];
    if (  ! bar  ) {
        NSLog(@"createStatusItem: Could not get system status bar");
    }
    
    [self removeStatusItem];
    
    // Create new status item
    if (   [bar respondsToSelector: @selector(_statusItemWithLength:withPriority:)]
        && [bar respondsToSelector: @selector(_insertStatusItem:withPriority:)]
        && (  ! [gTbDefaults boolForKey:@"placeIconInStandardPositionInStatusBar"]  )
        && (  ! mustPlaceIconInStandardPositionInStatusBar()  )
        ) {
        
        // Force icon to the right in Status Bar
        long long priority = (  runningOnMountainLionOrNewer()
							  ? 0x000000007FFFFFFDll			// Mountain Lion will accept, and Yosemite and higher need, 2147483645 (0x7FFFFFFD)
							  : 0x000000007FFFFFFEll);			// Lion won't work with that, though
        
        if (  ! ( statusItem = [[bar _statusItemWithLength: NSVariableStatusItemLength withPriority: priority] retain] )  ) {
            NSLog(@"Can't obtain status item near Spotlight icon");
        }
        TBLog(@"DB-SI", @"createStatusItem: Created status item near the Spotlight icon")
        
        // Re-insert item to place it correctly
        [bar removeStatusItem: statusItem];
        [bar _insertStatusItem: statusItem withPriority: priority];
        TBLog(@"DB-SI", @"createStatusItem: Removed and reinserted status item to put it near the Spotlight icon")
        iconPosition = iconNearSpotlight;

    } else {
        // Standard placement of icon in Status Bar
        if (  ! (statusItem = [[bar statusItemWithLength: NSVariableStatusItemLength] retain])  ) {
            NSLog(@"Can't obtain status item in standard position");
        }
        TBLog(@"DB-SI", @"createStatusItem: Created status item placed normally (to the left of existing status items)")
        iconPosition = iconNormal;
    }
	
    if (  ! ourMainIconView  ) {
        [self setOurMainIconView: [[[MainIconView alloc] initWithFrame: NSMakeRect(0.0, 0.0, 24.0, 22.0)] autorelease]];
    }
    
/* Removed but left in for when the deprecated 'setView:' method of NSStatusItem is removed from OS X
     if (   [statusItem respondsToSelector: @selector(button)]  ) {
        
        [self setStatusItemButton: [statusItem performSelector: @selector(button) withObject: nil]];
        if (  statusItemButton  ) {
            [statusItemButton setImage: mainImage];  // Set image so that frame is set up so we can set the tracking rectangle
            NSRect frame = [statusItemButton frame];
            NSRect trackingRect = NSMakeRect(frame.origin.x + 1.0f, frame.origin.y, frame.size.width - 1.0f, frame.size.height);
            iconTrackingRectTag = [statusItemButton addTrackingRect: trackingRect
                                                              owner: self
                                                           userData: nil
                                                       assumeInside: NO];
            TBLog(@"DB-SI", @"createStatusItem: Added tracking rectangle (%f,%f, %f, %f) for status item",
                  trackingRect.origin.x, trackingRect.origin.y, trackingRect.size.width, trackingRect.size.height)
            [statusItem setView: [self ourMainIconView]];
        } else {
            TBLog(@"DB-SI", @"createStatusItem: Did not add tracking rectangle for status item because there was no statusItemButton");
            [statusItem setView: [self ourMainIconView]];
        }
        [[self ourMainIconView] setupTrackingRect];
    } else {
 */
    if (  [self statusItemButton]  ) {
            [self setStatusItemButton: nil];
        }
        TBLog(@"DB-SI", @"createStatusItem: Did not add tracking rectangle for status item because it does not respond to 'button'")
        [statusItem setView: [self ourMainIconView]];
        [[self ourMainIconView] setupTrackingRect];
/*  }
 */
    
    [statusItem setMenu: myVPNMenu];
    TBLog(@"DB-SI", @"createStatusItem: Set menu for status item")
}

-(void) moveStatusItemIfNecessary {
    
    // "Move" the status item if it should be in a different place from its current location.
    // Move it by recreating it so it is in the new place. That is necessary because a status item near the Spotlight icon is
    // a different status item (because it has a "priority").
    
    enum StatusIconPosition whereIconShouldBe = (   [gTbDefaults boolForKey:@"placeIconInStandardPositionInStatusBar"]
                                                 || mustPlaceIconInStandardPositionInStatusBar()
                                                 ? iconNormal
                                                 : iconNearSpotlight);
    TBLog(@"DB-SI", @"moveStatusItemIfNecessary: iconPosition = %d; should be = %d", iconPosition, whereIconShouldBe)
    
    if (  iconPosition != whereIconShouldBe  ) {
        [self createStatusItem];
    }
    
    // Always re-set up the checkbox that controls the icon's position, update the icon image and status windows
    [[self logScreen] setupAppearancePlaceIconNearSpotlightCheckbox];
    [self updateIconImage];
}

-(void) updateScreenList {
    
    TBLog(@"DB-SI", @"updateScreenList: Current screen list = %@", screenList)
    NSArray * screenArray = [NSScreen screens];
    NSMutableArray * screens = [NSMutableArray arrayWithCapacity: [screenArray count]];
    unsigned i;
    for (  i=0; i<[screenArray count]; i++  ) {
		NSScreen * screen = [screenArray objectAtIndex: i];
        NSDictionary * dict = [screen deviceDescription];
        CGDirectDisplayID displayNumber = [[dict objectForKey: @"NSScreenNumber"] unsignedIntValue];
		NSRect displayFrame = [screen frame];
        unsigned displayWidth  = (unsigned) displayFrame.size.width;
        unsigned displayHeight = (unsigned) displayFrame.size.height;
		
        [screens addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithUnsignedInt: (unsigned) displayNumber], @"DisplayNumber",
                             [NSNumber numberWithUnsignedInt:            displayWidth],  @"DisplayWidth",
                             [NSNumber numberWithUnsignedInt:            displayHeight], @"DisplayHeight",
                             nil]];
    }
    
    [self setScreenList: [NSArray arrayWithArray: screens]];
    TBLog(@"DB-SI", @"updateScreenList: New screen list = %@", screenArray)
}

-(unsigned) statusScreenIndex {
    
    // Returns an index into screenList of the display on which the status screen should be displayed
	
    unsigned returnValue = UINT_MAX;
	
    unsigned displayNumberFromPrefs = [gTbDefaults unsignedIntForKey: @"statusDisplayNumber" default: 0 min: 0 max: UINT_MAX];
    if (  displayNumberFromPrefs == 0 ) {
		returnValue = 0;
	} else {
		unsigned i;
		for (  i=0; i<[screenList count]; i++  ) {
			NSDictionary * dict = [screenList objectAtIndex: i];
			unsigned displayNumber = [[dict objectForKey: @"DisplayNumber"] unsignedIntValue];
			if (  displayNumber == displayNumberFromPrefs  ) {
				returnValue = i;
				break;
			}
		}
	}
	
	if (  returnValue == UINT_MAX  ) {
		NSLog(@"Selected status window screen is not available, using screen 0");
		returnValue = 0;
	}
	
	return returnValue;
}

- (void) recreateMenu
{
    [self createMenu];
    [self updateIconImage];
    [statusItem setMenu: myVPNMenu];
}

-(NSString *) iconPositionAsString {
    
    return (  (iconPosition == iconNotShown)
            ? @"status icon not being displayed"
            : (  (iconPosition == iconNormal)
               ? @"status icon on left"
               : @"status icon near Spotlight icon"
               )
            );
}

-(void) screenParametersChanged {
    
    TBLog(@"DB-SI", @"screenParametersChanged: %@", [self iconPositionAsString])
    
    [self updateScreenList];
    [self moveStatusItemIfNecessary];
    [[self logScreen] setupAppearanceConnectionWindowScreenButton];
}

-(void) activeDisplayDidChange {
    
    TBLog(@"DB-SI", @"activeDisplayDidChange: %@", [self iconPositionAsString])
    
    [self updateScreenList];
    [self moveStatusItemIfNecessary];
    [[self logScreen] setupAppearanceConnectionWindowScreenButton];
}


-(void) menuExtrasWereAdded {
    
    // If the icon is near the Spotlight icon, then redraw it there
    TBLog(@"DB-SI", @"menuExtrasWereAdded: %@", [self iconPositionAsString])
    if (  iconPosition == iconNearSpotlight  ) {
        [self createStatusItem];
        [[self logScreen] setupAppearancePlaceIconNearSpotlightCheckbox];
        [self updateIconImage];
    }
}

-(void) screenParametersChangedHandler: (NSNotification *) n {
    
    (void) n;
    
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
	[self performSelectorOnMainThread: @selector(screenParametersChanged) withObject: nil waitUntilDone: NO];
}

-(void) activeDisplayDidChangeHandler: (NSNotification *) n {
    
    (void) n;
    
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
	[self performSelectorOnMainThread: @selector(screenParametersChanged) withObject: nil waitUntilDone: NO];
}

- (void) menuExtrasWereAddedHandler: (NSNotification*) n
{
	(void) n;
	
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
	[self performSelectorOnMainThread: @selector(menuExtrasWereAdded) withObject: nil waitUntilDone: NO];
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

-(void) menuWillOpen: (NSMenu *) menu {
	if (  menu == myVPNMenu  ) {
		menuIsOpen = TRUE;
		[self updateIconImage];    // Display the new images
	}
}

-(void) menuDidClose: (NSMenu *) menu {
	if (  menu == myVPNMenu  ) {
		menuIsOpen = FALSE;
		[self updateIconImage];    // Display the new images
	}
}

-(void) loadHighlightedIconSet: (NSString *) menuIconSet {
    // Attempts to load a highlighted image set
    // Assumes regular and large image sets have already loaded successfully
    
    if (  [mainImage isTemplate]  ) {
        [self setHighlightedMainImage:      [self tintTemplateImage: mainImage]];
        [self setHighlightedConnectedImage: [self tintTemplateImage: connectedImage]];
        
        [self setHighlightedAnimImages: [NSMutableArray arrayWithCapacity: [animImages count]]];
        NSUInteger i;
        for (  i=0; i<[animImages count] - 1; i++  ) {
            NSImage * animImage = [animImages objectAtIndex: i];
            [highlightedAnimImages addObject: [self tintTemplateImage: animImage]];
        }
    } else {
        // Default to the non-highlighted versions if there are not any highlighted versions
        [self setHighlightedMainImage:      mainImage];
        [self setHighlightedConnectedImage: connectedImage];
        [self setHighlightedAnimImages:     animImages];
        NSLog(@"Using icon set '%@' without Retina images", menuIconSet);
    }
}
-(BOOL) loadMenuIconSet
{
    // Try with the specified icon set
    NSString * requestedMenuIconSet = [gTbDefaults stringForKey:@"menuIconSet"];
    if (  requestedMenuIconSet   ) {
        NSString * requestedLargeIconSet = [NSString stringWithFormat: @"large-%@", requestedMenuIconSet];
        if (  [self loadMenuIconSet: requestedMenuIconSet
                               main: &mainImage
                         connecting: &connectedImage
                               anim: &animImages]  ) {
            if (  [self loadMenuIconSet: requestedLargeIconSet
                                   main: &largeMainImage
                             connecting: &largeConnectedImage
                                   anim: &largeAnimImages]  ) {
                [self loadHighlightedIconSet: requestedMenuIconSet];
                [self updateIconImage];
                return YES;
            } else {
                NSLog(@"Icon set '%@' not found", requestedLargeIconSet);
            }
        } else {
            if (  [self loadMenuIconSet: requestedLargeIconSet
                                   main: &largeMainImage
                             connecting: &largeConnectedImage
                                   anim: &largeAnimImages]  ) {
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
            [self loadHighlightedIconSet: menuIconSet];
            [self updateIconImage];
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
        [self loadHighlightedIconSet: menuIconSet];
        [self updateIconImage];
        return YES;
    }
    
    return NO;
}

-(void) markImage: (NSImage *) image asTemplate: (BOOL) isTemplate {
    
    if (   isTemplate
        && [image respondsToSelector: @selector(setTemplate:)]  ) {
        [image setTemplate: TRUE];
    }
}
-(NSImage *) tintTemplateImage: (NSImage *) image
{
    NSImage *tintedImage = [[image copy] autorelease];
    [tintedImage lockFocus];
    [[NSColor whiteColor] set];
    NSRectFillUsingOperation(NSMakeRect(0, 0, tintedImage.size.width, tintedImage.size.height), NSCompositeSourceAtop);
    [tintedImage unlockFocus];
    [tintedImage setTemplate: NO];
    return tintedImage;
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
    
	BOOL usingTemplates = FALSE;
    NSUInteger i=0;
    for(  i=0; i<[allObjects count]; i++  ) {
        file = [allObjects objectAtIndex: i];
		if (  [file hasPrefix: @"templates."]  ) {
			usingTemplates = TRUE;
		}
	}	
	
    [*ptrAnimImages release];
    *ptrAnimImages = [[NSMutableArray alloc] init];
    
    for(i=0;i<[allObjects count];i++) {
        file = [allObjects objectAtIndex:i];
        fullPath = [iconSetDir stringByAppendingPathComponent:file];
        
        if (  itemIsVisible(fullPath)  ) {
            if ([[file pathExtension] isEqualToString: @"png"]) {
                NSString *name = [[file lastPathComponent] stringByDeletingPathExtension];
                
                if (  [name isEqualToString:@"closed"]) {
                    [*ptrMainImage release];
                    *ptrMainImage = [[NSImage alloc] initWithContentsOfFile:fullPath];
                    [self markImage: *ptrMainImage asTemplate: usingTemplates];
                    
                } else if(  [name isEqualToString:@"open"]) {
                    [*ptrConnectedImage release];
                    *ptrConnectedImage = [[NSImage alloc] initWithContentsOfFile:fullPath];
                    [self markImage: *ptrConnectedImage asTemplate: usingTemplates];
                    
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
        fullPath = [iconSetDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu.png", (unsigned long)i]];
        if (  itemIsVisible(fullPath)  ) {
            if ([gFileMgr fileExistsAtPath:fullPath]) {
                NSImage * img = [[NSImage alloc] initWithContentsOfFile:fullPath];
                if (  img  ) {
                    [self markImage: img asTemplate: usingTemplates];
                    [*ptrAnimImages addObject: img];
                    [img release];
                } else {
                    NSLog(@"Unable to load status icon image (possible incorrect permissions) at %@", fullPath);
                }
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
            NSDictionary * infoPlist = [self tunnelblickInfoDictionary];
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

	[myVPNMenu addItem:statusMenuItem];
    [myVPNMenu addItem:[NSMenuItem separatorItem]];
    
	BOOL showVpnDetailsAtTop = (   ( ! [gTbDefaults boolForKey:@"doNotShowVpnDetailsMenuItem"] )
								&& ( ! [gTbDefaults boolForKey:@"putVpnDetailsAtBottom"] ) );
    if (  showVpnDetailsAtTop  ) {
        [myVPNMenu addItem: vpnDetailsItem];
        [myVPNMenu addItem: [NSMenuItem separatorItem]];
	}
    
    // Add each connection to the menu
    NSString * dispNm;
    NSArray *keyArray = [[[self myConfigDictionary] allKeys]
						 sortedArrayUsingSelector: @selector(caseInsensitiveNumericCompare:)];
	NSEnumerator * e = [keyArray objectEnumerator];
	NSUInteger itemsToSkip = (  showVpnDetailsAtTop
							  ? 4
							  : 2);
    while (  (dispNm = [e nextObject])  ) {
        if (  ! [gTbDefaults boolForKey: [dispNm stringByAppendingString: @"-doNotShowOnTunnelblickMenu"]]  ) {
            // configure connection object:
            NSMenuItem *connectionItem = [[[NSMenuItem alloc] init] autorelease];
            VPNConnection* myConnection = [[self myVPNConnectionDictionary] objectForKey: dispNm];
            
            // Note: The menu item's title will be set on demand in VPNConnection's validateMenuItem and by uiUpdater
            [connectionItem setTarget:myConnection]; 
            [connectionItem setAction:@selector(toggle:)];
            
			NSString * menuItemName = [myConnection localizedName];
            [self insertConnectionMenuItem: connectionItem IntoMenu: myVPNMenu afterIndex: itemsToSkip withName: menuItemName];
            
            [myConnection setMenuItem: connectionItem];
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
    
    if (   ( ! [gTbDefaults boolForKey:@"doNotShowVpnDetailsMenuItem"] )
        && [gTbDefaults boolForKey:@"putVpnDetailsAtBottom"]  ) {
        [myVPNMenu addItem: vpnDetailsItem];
        [myVPNMenu addItem: [NSMenuItem separatorItem]];
	}
    
    [myVPNMenu addItem: quitItem];
    
    if (  statusItemButton  ) {
        [statusItemButton setImage: mainImage];
        [statusItem setMenu: myVPNMenu];
    }
	
    status = pthread_mutex_unlock( &myVPNMenuMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &myVPNMenuMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
    }
}

// *******************************************************************************************
// Event Handlers for the main icon on Yosemite

-(void) mouseEntered: (NSEvent *) theEvent
{
    // Event handler; NOT on MainThread
    // Mouse entered the tracking area of the Tunnelblick icon
	
    if (   gShuttingDownWorkspace
        || [gTbDefaults boolForKey: @"doNotShowNotificationWindowOnMouseover"]  ) {
        TBLog(@"DB-SI", @"Mouse entered tracking rectangle for main icon but not showing notification windows");
        return;
    }
    
    [self mouseEnteredMainIcon: self event: theEvent];
}

-(void) mouseExited: (NSEvent *) theEvent
{
    // Event handler; NOT on MainThread
    // Mouse exited the tracking area of the Tunnelblick icon
	
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    [self mouseExitedMainIcon: self event: theEvent];
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
            if (  [menuItem isSeparatorItem]  ) {
                break;                       // A separator marks the end of list of connection items
            }
            NSString * menuItemTitle;
            if (   [menuItem submenu]  ) {    // item is a submenu
                menuItemTitle = [menuItem title];
            } else if (   [[menuItem title] isEqualToString: NSLocalizedString(@"Add a VPN...",   @"Menu item")]
					   || [[menuItem title] isEqualToString: NSLocalizedString(@"VPN Details...", @"Menu item")]  ) {
                break;
            } else {                                                            // item is a connection item
                menuItemTitle = [[menuItem target] localizedName];
            }
            
			NSString * menuItemTitleWithoutSlash = [menuItemTitle lastPathComponent];
			if (  [menuItemTitleWithoutSlash hasSuffix: @"/"]  ) {
				menuItemTitleWithoutSlash = [menuItemTitleWithoutSlash substringToIndex: [menuItemTitleWithoutSlash length] - 1];
			}
			NSString * theNameWithoutSlash = (  [theName hasSuffix: @"/"]
											  ? [theName substringToIndex: [theName length] - 1]
											  : theName);
            if (  [menuItemTitleWithoutSlash compare: theNameWithoutSlash options: NSCaseInsensitiveSearch | NSNumericSearch] == NSOrderedDescending  ) {
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
                NSString * menuItemTitleWithoutSlash = [menuItem title];
				if (  [menuItemTitleWithoutSlash hasSuffix: @"/"]  ) {
					menuItemTitleWithoutSlash = [menuItemTitleWithoutSlash substringToIndex: [menuItemTitleWithoutSlash length] - 1];
				}
				NSString * subMenuNameWithoutSlash = (  [subMenuName hasSuffix: @"/"]
													  ? [subMenuName substringToIndex: [subMenuName length] - 1]
													  : subMenuName);
                NSComparisonResult  result = [menuItemTitleWithoutSlash compare: subMenuNameWithoutSlash options: NSCaseInsensitiveSearch | NSNumericSearch];
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
            } else {
				if (  [[menuItem title] isEqualToString: NSLocalizedString(@"Add a VPN...", @"Menu item")]  ) {
					break;
				}
			}

        }
    }
    
    // Didn't find the submenu, so we have to create a new submenu and try again.
    
    // Create the new submenu
    NSMenu * newSubmenu = [[[NSMenu alloc] initWithTitle: NSLocalizedString(@"Tunnelblick", @"Window title")] autorelease];
    
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
    NSString * itemName = [self menuNameFromFilename: file];
    if (  [itemName length] != 0  ) {
        NSString * localName = [self localizedString: itemName];
        if (  [localName length] != 0  ) {
            NSMenu * subMenu = [[[NSMenu alloc] init] autorelease];
            if (  [self addCustomMenuItemsFromFolder: [folder stringByAppendingPathComponent: file] toMenu: subMenu]  ) {
                NSMenuItem * subMenuItem = [[[NSMenuItem alloc] init] autorelease];
                [subMenuItem setTitle: localName];
                [subMenuItem setSubmenu: subMenu];
                [theMenu addItem: subMenuItem];
                return TRUE;
            }
        }
    }

    return FALSE;
}

-(void) addOneCustomMenuItem: (NSString *) file fromFolder: (NSString *) folder toMenu: (NSMenu *) theMenu
{
    NSString * itemName = [self menuNameFromFilename: file];
    if (  [itemName length] != 0  ) {
        NSString * localName = [self localizedString: itemName];
        if (  [localName length] != 0  ) {
            NSMenuItem * item = [[[NSMenuItem alloc] init] autorelease];
            [item setTitle: localName];
            [item setTarget: self];
            [item setAction: @selector(runCustomMenuItem:)];
            [item setTag: customMenuScriptIndex++];
            
            NSString * scriptPath = [folder stringByAppendingPathComponent: file];
            [customMenuScripts addObject: scriptPath];
            
            [theMenu addItem: item];
        }
    }
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
	NSArray  * arguments = [NSArray arrayWithObject: [self languageAtLaunch]];
	if (  [[[scriptPath stringByDeletingPathExtension] pathExtension] isEqualToString: @"wait"]  ) {
        OSStatus status = runTool(scriptPath, arguments, nil, nil);
        if (  status != EXIT_SUCCESS) {
            NSLog(@"Error status %ld returned from custom menu item at '%@'", (long)status, scriptPath);
        }
	} else {
		startTool(scriptPath, arguments);
	}
}

// Sparkle delegates:
- (NSString *)feedURLStringForUpdater:(SUUpdater *) theUpdater {
	
	// This delegate method is implemented so Sparkle always uses the correct URL:
	//		* If we are running a beta version of Tunnelblick, we must check for a beta update.
	//		* Otherwise, we check for a beta update only if the user has requested it.
	
	(void) theUpdater;
	
	NSString * s = [self feedURLToUse];
	if (  ! s  ) {
		NSLog(@"MenuController: feedURL has not been set up; stack trace: %@", callStack());
	}
	return s;
}

-(NSString *) feedURLToUse {
	
	NSString * urlString = nil;
	
	// If the 'updateFeedURL' preference is being forced, use it
	if (  ! [gTbDefaults canChangeValueForKey: @"updateFeedURL"]  ) {
		urlString = [gTbDefaults stringForKey: @"updateFeedURL"];
		if (  ! [NSURL URLWithString: urlString]  ) {
			NSLog(@"Ignoring 'updateFeedURL' preference '%@' from 'forced-preferences.plist' because it could not be converted to a URL", urlString);
			urlString = nil;
		}
	
	// Otherwise, use the entry in Info.plist
	} else {
		urlString = [[self tunnelblickInfoDictionary] objectForKey: @"SUFeedURL"];
		if (  urlString ) {
			if (  ! [[urlString class] isSubclassOfClass: [NSString class]]  ) {
				NSLog(@"Ignoring 'SUFeedURL' item in Info.plist because it is not a string");
				urlString = nil;
			}
			if (  ! [NSURL URLWithString: urlString]  ) {
				NSLog(@"Ignoring 'SUFeedURL' item '%@' in Info.plist because it could not be converted to a URL", urlString);
				urlString = nil;
			}
		} else {
			NSLog(@"Missing 'SUFeedURL' item in Info.plist");
		}
	}
	
	if (  urlString  ) {
	
		// Add "-s" or "-b" to the URL, so it is:
		// .../appcast-s.rss --> update to latest Stable version
		// .../appcast-b.rss --> update to latest Beta version
		
		// Remove any existing extension.
		// Can't use stringByDeletingPathExtension because it changes double-slashes to single slashes (e.g., changes "https://www" to "https:/www")
		NSString * ext = [urlString pathExtension];
		NSString * withoutExt = ( ( 0 == [ext length])
								 ? [[urlString copy] autorelease]
								 : [urlString substringToIndex: [urlString length] - [ext length] - 1]);
		
		// Remove any existing -b or -d suffix
		if (   [withoutExt hasSuffix: @"-b"]
			|| [withoutExt hasSuffix: @"-d"]  ) {
			withoutExt = [withoutExt substringToIndex: [withoutExt length] - 2];
		}
		
		// Decide what suffix to add
		BOOL checkBeta = runningABetaVersion();
		if (  ! checkBeta  ) {
			id obj = [gTbDefaults objectForKey: @"updateCheckBetas"];
			checkBeta = (   [obj respondsToSelector: @selector(boolValue)]
						 && [obj boolValue]);
		}
		NSString * newSuffix = (  checkBeta
								? @"-b"
								: @"-s");
		
		urlString = (  (0 == [ext length])
					 ? [withoutExt stringByAppendingString: newSuffix]
					 : [NSString stringWithFormat: @"%@%@.%@", withoutExt, newSuffix, ext]  );
	}
	
	TBLog(@"DB-ALL", "Application update feed = %@", urlString);
	
	return urlString;
}

- (BOOL)updaterShouldPromptForPermissionToCheckForUpdates:(SUAppcastItem *) theUpdater {
	
	(void) theUpdater;
	
	return NO;
}

- (void)updater:(SUUpdater *)theUpdater willInstallUpdate:(SUAppcastItem *)update
{
	(void) theUpdater;
	(void) update;
	
	[gTbDefaults removeObjectForKey: @"skipWarningAboutInvalidSignature"];
	[gTbDefaults removeObjectForKey: @"skipWarningAboutNoSignature"];
	[gTbDefaults setBool: TRUE forKey: @"haveStartedAnUpdateOfTheApp"];
	
	reasonForTermination = terminatingBecauseOfQuit;
	
	[gTbDefaults setBool: NO forKey: @"launchAtNextLogin"];
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

-(void) changedDisplayConnectionSubmenusSettings
{
    [self recreateMenu];
}

-(void) removeConnectionWithDisplayName: (NSString *) theName
                               fromMenu: (NSMenu *)   theMenu
                             afterIndex: (int)        theIndex
{
	NSString * localName = [self localizedNameForDisplayName: theName];
    [self removeConnectionWithDisplayName: theName fromMenu: theMenu afterIndex: theIndex workingName: localName];
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
            myState = (  ! publicIPAddress
					   ? [NSString stringWithFormat: NSLocalizedString(@"Disconnect All (%@)", @"Status message"), name]
					   : [NSString stringWithFormat: NSLocalizedString(@"Disconnect All (%@) - apparent public IP address %@", @"Status message. First '%@' is the name of a configuration. Second '%@' is an IP address (e.g. '8.8.4.4')"), name, [self publicIPAddress]]);
			[statusMenuItem setTitle: myState];
			[statusMenuItem setTitle: myState];
        } else {
            myState = (  ! publicIPAddress
					   ? [NSString stringWithFormat:NSLocalizedString(@"Disconnect All (%d Connections)", @"Status message"),nConnections]
					   : [NSString stringWithFormat:NSLocalizedString(@"Disconnect All (%d Connections) - apparent public IP address %@", @"Status message. First '%@' is a number greater than 1 (e.g., '3'). Second '%@' is an IP address (e.g., '8.8.4.4')"),nConnections, [self publicIPAddress]]);
            [statusMenuItem setTitle: myState];
        }
        return YES;
    } else {
        if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
            [anItem setToolTip: @""];
        }
        if (  act == @selector(quit:)  ) {
            return YES;
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

-(void) configurationsChanged {
	
	[self updateMenuAndDetailsWindow];
}

-(void) configurationsChangedWithRenameDictionary: (NSDictionary *)  renameDictionary {
	
	NSString * oldDisplayName = [renameDictionary objectForKey: @"oldDisplayName"];
	NSString * newDisplayName = [renameDictionary objectForKey: @"newDisplayName"];
    
	BOOL oldNameWasSelected = [[[[self logScreen] selectedConnection] displayName] isEqualToString: oldDisplayName];

	[self updateMenuAndDetailsWindow];
	
	if (  oldNameWasSelected  ) {
		[[self logScreen] setupLeftNavigationToDisplayName: newDisplayName];
	}
}

-(void) changedDisplayConnectionTimersSettings
{
    [self startOrStopUiUpdater];
    [self updateUI];
}

// Starts or stops the timer for showing connection durations.
// Starts it (or lets it continue) if it is enabled and any tunnels are not disconnected; stops it otherwise
-(void) startOrStopUiUpdater
{
    if (  uiUpdater  ) {
        // Timer is active. Stop it if not enabled or if all tunnels are disconnected.
        if (  [gTbDefaults boolWithDefaultYesForKey:@"showConnectedDurations"]  ) {
            VPNConnection * conn;
            NSEnumerator * connEnum = [[self myVPNConnectionDictionary] objectEnumerator];
            while (  (conn = [connEnum nextObject])  ) {
                if (  ! [[conn state] isEqualToString: @"EXITING"]) {
                    return;
                }
            }
        }
        
		[uiUpdater invalidateAfterNextTick];
        [self setUiUpdater: nil];
    } else {
        // Timer is inactive. Start it if enabled and any tunnels are not disconnected
        if (  [gTbDefaults boolWithDefaultYesForKey:@"showConnectedDurations"]  ) {
            VPNConnection * conn;
            NSEnumerator * connEnum = [[self myVPNConnectionDictionary] objectEnumerator];
            while (  (conn = [connEnum nextObject])  ) {
                if (  ! [[conn state] isEqualToString: @"EXITING"]) {
                    [self setUiUpdater: [[[TBUIUpdater alloc] init] autorelease]];
					return;
                }
            }
        }
    }
}

-(void)updateUI
{
	[uiUpdater fireTimer];
}

// If any new config files have been added, add each to the menu and add tabs for each to the Log window.
// If any config files have been deleted, remove them from the menu and remove their tabs in the Log window
-(void) updateMenuAndDetailsWindow 
{
    BOOL needToUpdateLogWindow = FALSE;         // If we changed any configurations, process the changes after we're done
    
    NSString * dispNm;
    
    NSDictionary * curConfigsDict = [ConfigurationManager getConfigurations];
    
    // Add new configurations and replace updated ones
	NSEnumerator * e = [curConfigsDict keyEnumerator];
    while (  (dispNm = [e nextObject])  ) {
        BOOL sameDispNm = [[self myConfigDictionary] objectForKey: dispNm] != nil;
        BOOL sameFolder = [[[self myConfigDictionary] objectForKey: dispNm] isEqualToString: [curConfigsDict objectForKey: dispNm]];
        
        if (  sameDispNm  ) {
            if (  ! sameFolder  ) {
                    // Replace a configuration that has changed from private to shared (for example)
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
    
    if (  needToUpdateLogWindow  ) {
        [[self logScreen] update];
    }
}

// Lock this to change myVPNConnectionDictionary, myMenu, and/or myConfigDictionary
static pthread_mutex_t configModifyMutex = PTHREAD_MUTEX_INITIALIZER;

// Add new config to myVPNConnectionDictionary, the menu, and myConfigDictionary
// Note: The menu item's title will be set on demand in VPNConnection's validateMenuItem
-(void) addNewConfig: (NSString *) path withDisplayName: (NSString *) dispNm
{
    if (  invalidConfigurationName(dispNm, PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING)  ) {
		TBShowAlertWindow(NSLocalizedString(@"Name not allowed", @"Window title"),
						 [NSString stringWithFormat: NSLocalizedString(@"Configuration '%@' ('%@') will be ignored because its"
																	   @" name contains characters that are not allowed.\n\n"
																	   @"Characters that are not allowed: '%s'\n\n", @"Window text"),
						  [self localizedNameForDisplayName: dispNm], dispNm, PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING]);
        return;
    }
    VPNConnection* myConnection = [[[VPNConnection alloc] initWithConfigPath: path
                                                            withDisplayName: dispNm] autorelease];
    
    NSMenuItem *connectionItem = [[[NSMenuItem alloc] init] autorelease];
    [connectionItem setTarget:myConnection]; 
    [connectionItem setAction:@selector(toggle:)];
    
    OSStatus status = pthread_mutex_lock( &configModifyMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &configModifyMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
    }
    
    status = pthread_mutex_lock( &myVPNMenuMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &myVPNMenuMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
		status = pthread_mutex_unlock( &configModifyMutex );
		if (  status != EXIT_SUCCESS  ) {
			NSLog(@"pthread_mutex_unlock( &configModifyMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
		}
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
    
	BOOL showVpnDetailsAtTop = ( ( ! [gTbDefaults boolForKey:@"doNotShowVpnDetailsMenuItem"] )
								&& ( ! [gTbDefaults boolForKey:@"putVpnDetailsAtBottom"] ) );
	NSUInteger itemsToSkip = (  showVpnDetailsAtTop
							  ? 4
							  : 2);
    [self insertConnectionMenuItem: connectionItem IntoMenu: myVPNMenu afterIndex: itemsToSkip withName: [[connectionItem target] localizedName]];
    
    // Add connection to myConfigDictionary
    NSMutableDictionary * tempConfigDictionary = [myConfigDictionary mutableCopy];
    [tempConfigDictionary setObject: path forKey: dispNm];
    [self setMyConfigDictionary: [[tempConfigDictionary copy] autorelease]];
    [tempConfigDictionary release];
     
    status = pthread_mutex_unlock( &myVPNMenuMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &myVPNMenuMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
		status = pthread_mutex_unlock( &configModifyMutex );
		if (  status != EXIT_SUCCESS  ) {
			NSLog(@"pthread_mutex_unlock( &configModifyMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
		}
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
    if (   myConnection
		&& ( ! [[myConnection state] isEqualTo: @"EXITING"] )  ) {
        [myConnection addToLog: @"*Tunnelblick: Disconnecting; user asked to delete the configuration"];
        [myConnection startDisconnectingUserKnows: [NSNumber numberWithBool: YES]];
        [myConnection waitUntilDisconnected];
        
		NSString * localName = [myConnection localizedName];
        TBShowAlertWindow([NSString stringWithFormat: NSLocalizedString(@"'%@' has been disconnected", @"Window title"), localName],
						 [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick has disconnected '%@' because its configuration file has been removed.", @"Window text"), localName]);
    }
    
    OSStatus status = pthread_mutex_lock( &configModifyMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &configModifyMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    
    status = pthread_mutex_lock( &myVPNMenuMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &myVPNMenuMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
		status = pthread_mutex_unlock( &configModifyMutex );
		if (  status != EXIT_SUCCESS  ) {
			NSLog(@"pthread_mutex_unlock( &configModifyMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
		}
        return;
    }
    
    // Remove connection from myVPNConnectionDictionary
    NSMutableDictionary * tempVPNConnectionDictionary = [myVPNConnectionDictionary mutableCopy];
    [tempVPNConnectionDictionary removeObjectForKey: dispNm];
    [self setMyVPNConnectionDictionary: [[tempVPNConnectionDictionary copy] autorelease]];
    [tempVPNConnectionDictionary release];
	
	BOOL showVpnDetailsAtTop = (   ( ! [gTbDefaults boolForKey:@"doNotShowVpnDetailsMenuItem"] )
								&& ( ! [gTbDefaults boolForKey:@"putVpnDetailsAtBottom"] ) );
	int itemsToSkip = ( showVpnDetailsAtTop ? 4 : 2 );
    [self removeConnectionWithDisplayName: dispNm fromMenu: myVPNMenu afterIndex: itemsToSkip];

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
		status = pthread_mutex_unlock( &configModifyMutex );
		if (  status != EXIT_SUCCESS  ) {
			NSLog(@"pthread_mutex_unlock( &configModifyMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
		}
        return;
    }
    status = pthread_mutex_unlock( &configModifyMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &configModifyMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
    }
}

- (void)connectionStateDidChange:(id)connection
{
	[self updateUI];
    [[self logScreen] validateConnectAndDisconnectButtonsForConnection: connection];
}

- (void) updateIconImage
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
        
		if (  statusItemButton  ) {
			if (  [lastState isEqualToString:@"CONNECTED"]  ) {
				[statusItemButton setImage: connectedImage];
			} else {
				[statusItemButton setImage: mainImage];
			}
		} else {
			if (  [lastState isEqualToString:@"CONNECTED"]  ) {
				[[self ourMainIconView] setImage: (  menuIsOpen
												   ? highlightedConnectedImage
												   : connectedImage)];
			} else {
				[[self ourMainIconView] setImage: (  menuIsOpen
												   ? highlightedMainImage
												   : mainImage)];
			}
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
        NSMutableArray * images = (  statusItemButton
                                   ? animImages
                                   : (  menuIsOpen
                                      ? highlightedAnimImages
                                      : animImages)
                                   );
        NSImage * img = [images objectAtIndex: (unsigned) (lround(progress * [images count]) - 1)];
		if (  statusItemButton  ) {
			[statusItemButton performSelectorOnMainThread:@selector(setImage:) withObject: img waitUntilDone:YES];
		} else {
			[[self ourMainIconView] performSelectorOnMainThread:@selector(setImage:) withObject:img waitUntilDone:YES];
		}
	}
}

- (NSString *) openVPNLogHeader
{
    unsigned major, minor, bugFix;
    NSString * currentVersionString = (  getSystemVersion(&major, &minor, &bugFix) == EXIT_SUCCESS
                                       ? [NSString stringWithFormat:@"%d.%d.%d", major, minor, bugFix]
                                       : @"version is unknown");
    
    NSArray  * versionHistory     = [gTbDefaults arrayForKey: @"tunnelblickVersionHistory"];
    NSString * priorVersionString = (  (  [versionHistory count] > 1  )
                                     ? [NSString stringWithFormat: @"; prior version %@", [versionHistory objectAtIndex: 1]]
                                     : @"");

    return ([NSString stringWithFormat:@"*Tunnelblick: OS X %@; %@%@", currentVersionString, tunnelblickVersion([NSBundle mainBundle]), priorVersionString]);
}

- (void) checkForUpdates: (id) sender
{
	(void) sender;
	
    if (   [gTbDefaults boolForKey:@"onlyAdminCanUpdate"]
        && ( ! userIsAnAdmin )  ) {
        NSLog(@"Check for updates was not performed because user is not allowed to administer this computer and 'onlyAdminCanUpdate' preference is set");
    } else {
		if (  [updater respondsToSelector: @selector(checkForUpdates:)]  ) {
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
            NSLog(@"Check for updates was not performed because Sparkle Updater does not respond to checkForUpdates:");
        }
        
        [myConfigMultiUpdater startAllUpdateCheckingWithUI: YES]; // Display the UI
    }
}

//*********************************************************************************************************
// Disconnecting on quit, computer sleep, or become inactive user

-(NSMutableArray *) startDisconnecting: (NSArray *)  disconnectList
					  disconnectingAll: (BOOL)       disconnectingAll
                   quittingTunnelblick: (BOOL)       quittingTunnelblick
                            logMessage: (NSString *) logMessage {
    
    // Disconnect zero or more configurations.
    // If 'disconnectingAll', will be disconnecting all configurations, so can use 'killall' if that is allowed and no unknown instances of OpenVPN are running
	//
    // Returns a (possibly empty) mutable array of connections that have started to disconnect
    
    NSMutableArray * disconnections = [[[NSMutableArray alloc] initWithCapacity: 10] autorelease];
    
	if (  [disconnectList count] != 0  ) {
		
        BOOL useKillAll = (   disconnectingAll
                           && noUnknownOpenVPNsRunning
                           && ALLOW_OPENVPNSTART_KILLALL  );
        
        // Fill the disconnections array, start disconnecting individually if not using killall, and log the disconnect/kill
        VPNConnection * connection;
        NSEnumerator * e = [disconnectList objectEnumerator];
        while (  (connection = [e nextObject])  ) {
            if (  ! [connection isDisconnected]  ) {
                
                [disconnections addObject: connection];
                
                // Append a Tunnelblick log entry for each connection that is being disconnected unless shutting down the workspace or computer or quitting Tunnelblick
                if (   ( ! gShuttingDownWorkspace)
                    && ( ! gShuttingDownOrRestartingComputer)
                    && ( ! quittingTunnelblick)  ) {
                    [connection addToLog: [NSString stringWithFormat: @"*Tunnelblick: %@", logMessage]];
                }
                
                // Console-log the kill/disconnect and start the disconnect if not using killall
                if (  useKillAll  ) {
                    TBLog(@"DB-SD", @"startDisconnecting:disconnectingAll:logMessage: will use killall to disconnect %@", [connection displayName])
                } else {
                    TBLog(@"DB-SD", @"startDisconnecting:disconnectingAll:logMessage: starting disconnect of %@", [connection displayName])
                    [connection startDisconnectingUserKnows: [NSNumber numberWithBool: YES]];
                }
            }
        }
		
        // Use killall if not killing individually
		if (   useKillAll  ) {
			TBLog(@"DB-SD", @"startDisconnecting:disconnectingAll:logMessage: starting killAll")
			runOpenvpnstart([NSArray arrayWithObject: @"killall"], nil, nil);
			TBLog(@"DB-SD", @"startDisconnecting:disconnectingAll:logMessage: finished killAll")
		}
        
	} else {
		TBLog(@"DB-CD", @"startDisconnecting:disconnectingAll:logMessage: no configurations are to be disconnected")
	}
	
    return disconnections;
}

-(void) waitForDisconnection: (NSMutableArray *) connectionsList {
    
    // Notes: Removes items from the mutable array
	//        May return before all are disconnected if the computer is shutting down or restarting
    
	if (  [connectionsList count] != 0  ) {
		
		TBLog(@"DB-CD", @"Waiting for %lu configurations to disconnect: %@", (unsigned long)[connectionsList count], connectionsList)
		
		while (  [connectionsList count] != 0  ) {
			
			// Create a copy of connectionsList which will not be modified inside the inner loop
			NSMutableArray * listNotModifiedInInnerLoop = [[NSMutableArray alloc] initWithCapacity: [connectionsList count]];
			VPNConnection * connection;
			NSEnumerator * e = [connectionsList objectEnumerator];
			while (  (connection = [e nextObject])  ) {
				[listNotModifiedInInnerLoop addObject: connection];
			}
			
			e = [listNotModifiedInInnerLoop objectEnumerator];
			while (  (connection = [e nextObject])  ) {
				
				if (  gShuttingDownOrRestartingComputer  ) {
					NSLog(@"waitForDisconnection: Computer is shutting down or restarting; OS X will wait for OpenVPN instances to terminate");
					[listNotModifiedInInnerLoop release];
					return;
				}
				
				// Since this method runs in the main thread, it blocks the processing that sets the variables that 'isDisconnected' checks
				// So we check for disconnection with the 'noOpenvpnProcess' method, too. That works because the OpenVPN process quits independently of
				// Tunnelblick's main thread.
				if (   [connection isDisconnected]
					|| [connection noOpenvpnProcess]  ) {
					[connectionsList removeObject: connection];
					TBLog(@"DB-CD", @"%@ has disconnected", [connection displayName])
				}
			}
			
			[listNotModifiedInInnerLoop release];
			
			if (  [connectionsList count] != 0  ) {
				usleep(100000);
			}
		}
		
		TBLog(@"DB-CD", @"Disconnections complete")
	} else {
		TBLog(@"DB-CD", @"No disconnections to wait for")
	}
}

// Access only one mass disconnection at a time
static pthread_mutex_t doDisconnectionsMutex = PTHREAD_MUTEX_INITIALIZER;

-(void) doDisconnectionsForQuittingTunnelblick {
    
    // DO NOT put this code inside the mutex: we want to return immediately if computer is shutting down or restarting
    if (  gShuttingDownOrRestartingComputer  ) {
        NSLog(@"Computer is shutting down or restarting; OS X will kill OpenVPN instances");
        return;
    }
    
    OSStatus status = pthread_mutex_lock( &doDisconnectionsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"doDisconnectionsForQuittingTunnelblick: pthread_mutex_lock( &doDisconnectionsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    
    NSMutableArray * disconnectList = [[[NSMutableArray alloc] initWithCapacity: 10] autorelease];
    
    BOOL disconnectingAll = TRUE; // Assume we disconnect everything
    
    // Add connections to disconnectList if they are not disconnected and not set to connect when the computer starts
    VPNConnection * connection;
    NSEnumerator * e = [[self myVPNConnectionDictionary] objectEnumerator];
    while (  (connection = [e nextObject])  ) {
        
        if (  ! [connection isDisconnected]  ) {
            
            NSString* onSystemStartKey = [[connection displayName] stringByAppendingString: @"-onSystemStart"];
            NSString* autoConnectKey   = [[connection displayName] stringByAppendingString: @"autoConnect"];
            
            if (  ! (   [gTbDefaults boolForKey: onSystemStartKey]
                     && [gTbDefaults boolForKey: autoConnectKey]
                     )
                ) {
                [disconnectList addObject: connection];
            } else {
                disconnectingAll = FALSE;
            }
        }
    }
    
    NSMutableArray * connectionsToWaitFor = [self startDisconnecting: disconnectList
                                                    disconnectingAll: disconnectingAll
                                                 quittingTunnelblick: YES
                                                          logMessage: @"Disconnecting because quitting Tunnelblick"];
    [self waitForDisconnection: connectionsToWaitFor];
    
    status = pthread_mutex_unlock( &doDisconnectionsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"doDisconnectionsForQuittingTunnelblick: pthread_mutex_unlock( &doDisconnectionsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
    }
}

-(void) startDisconnectionsForSleeping {
    
    // Starts disconnecting appropriate configurations and sets connectionsToWaitForDisconnectOnWakeup and connectionsToRestoreOnWakeup
    
    // DO NOT put this code inside the mutex: we want to return immediately if computer is shutting down or restarting
    if (  gShuttingDownOrRestartingComputer  ) {
        NSLog(@"Computer is shutting down or restarting; OS X will kill OpenVPN instances");
        return;
    }
    
    NSMutableArray * disconnectList = [[[NSMutableArray alloc] initWithCapacity: 10] autorelease];
    [self setConnectionsToRestoreOnWakeup: [[[NSMutableArray alloc] initWithCapacity: 10] autorelease]];
    
    BOOL disconnectingAll = TRUE; // Assume we disconnect everything
    
    // Add connections to the DISCONNECT list if they ARE NOT disconnected and should DISCONNECT when the computer GOES TO SLEEP
	// Add connections to the  RECONNECT list if they WILL BE disconnected and should RECONNECT  when the computer WAKES UP
    VPNConnection * connection;
    NSEnumerator * e = [[self myVPNConnectionDictionary] objectEnumerator];
    while (  (connection = [e nextObject])  ) {
        
        if (  ! [connection isDisconnected]  ) {
            
            NSString* keepConnectedForSleepKey = [[connection displayName] stringByAppendingString: @"-doNotDisconnectOnSleep"];
            if (  ! [gTbDefaults boolForKey: keepConnectedForSleepKey]  ) {
                [disconnectList addObject: connection];
                NSString * doNotReconnectAfterSleepKey = [[connection displayName] stringByAppendingString: @"-doNotReconnectOnWakeFromSleep"];
                if (  ! [gTbDefaults boolForKey: doNotReconnectAfterSleepKey]  ) {
                    [connectionsToRestoreOnWakeup addObject: connection];
                }
            } else {
                disconnectingAll = FALSE;
            }
        }
    }
    
    NSMutableArray * connectionsToWaitFor = [self startDisconnecting: disconnectList
                                                    disconnectingAll: disconnectingAll
                                                 quittingTunnelblick: NO
                                                          logMessage: @"Disconnecting because computer is going to sleep"];
	
	[self setConnectionsToWaitForDisconnectOnWakeup: connectionsToWaitFor];
    
    return;
}

-(NSArray *) doDisconnectionsForBecameInactiveUser {
    
    // Returns array of connections to connect when become inactive
    
    // DO NOT put this code inside the mutex: we want to return immediately if computer is shutting down or restarting
    if (  gShuttingDownOrRestartingComputer  ) {
        TBLog(@"DB-SD", @"doDisconnectionsForBecameInactiveUser: Computer is shutting down or restarting; OS X will kill OpenVPN instances")
        return nil;
    }
    
    OSStatus status = pthread_mutex_lock( &doDisconnectionsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"doDisconnectionsForBecameInactiveUser: pthread_mutex_lock( &doDisconnectionsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return nil;
    }
    
    NSMutableArray * reconnectList  = [[[NSMutableArray alloc] initWithCapacity: 10] autorelease];
    NSMutableArray * disconnectList = [[[NSMutableArray alloc] initWithCapacity: 10] autorelease];
    
    BOOL disconnectingAll = TRUE; // Assume we disconnect everything
    
    // Add connections to disconnectList if they are not disconnected and should disconnect when the user becomes inactive
    VPNConnection * connection;
    NSEnumerator * e = [[self myVPNConnectionDictionary] objectEnumerator];
    while (  (connection = [e nextObject])  ) {
        
        if (  ! [connection isDisconnected]  ) {
            
            NSString* keepConnectedForInactiveKey = [[connection displayName] stringByAppendingString: @"-doNotDisconnectOnFastUserSwitch"];
            if (  ! [gTbDefaults boolForKey: keepConnectedForInactiveKey]  ) {
                [disconnectList addObject: connection];
            } else {
                NSString* doNotReconnectAfterInactiveKey = [[connection displayName] stringByAppendingString: @"-doNotReconnectOnFastUserSwitch"];
                if (  ! [gTbDefaults boolForKey: doNotReconnectAfterInactiveKey]  ) {
                    [reconnectList addObject: connection];
                }
                disconnectingAll = FALSE;
            }
        }
    }
    
    NSMutableArray * connectionsToWaitFor = [self startDisconnecting: disconnectList
                                                    disconnectingAll: disconnectingAll
                                                 quittingTunnelblick: NO
                                                          logMessage: @"Disconnecting because user is becoming inactive"];
    [self waitForDisconnection: connectionsToWaitFor];
    
    status = pthread_mutex_unlock( &doDisconnectionsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"doDisconnectionsForBecameInactiveUser: pthread_mutex_unlock( &doDisconnectionsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
    }
    
    return reconnectList;
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
    
    unsigned bitMask = getLoadedKextsMask() & ( ~ (OPENVPNSTART_FOO_TAP_KEXT | OPENVPNSTART_FOO_TUN_KEXT)  );    // Don't unload foo.tun/tap
    
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

-(NSNumber *) haveConfigurations {
	
	// Returns an NSNumber because it is invoked with [... performSelector:]
    
	NSUInteger count = [[self myConfigDictionary] count];
    return (  [NSNumber numberWithBool: (count != 0)]  );
}


-(void) checkNoConfigurations {
    
    // If there aren't ANY config files in the config folders
    // then guide the user

    if (  [((NSNumber *)[self haveConfigurations]) boolValue]  ) {
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
		NSString * tooBigMsg = allFilesAreReasonableIn(gPrivatePath);
        if (  tooBigMsg  ) {
            TBRunAlertPanel(NSLocalizedString(@"Warning", @"Window title"),
                            [NSString stringWithFormat:
							 NSLocalizedString(@"You have OpenVPN configurations but you do not have any Tunnelblick VPN Configurations.\n\n"
											   @"The OpenVPN configurations must be converted to Tunnelblick VPN Configurations if you want to use them.\n\n"
											   @"However, Tunnelblick cannot convert them because there was a problem:\n\n"
											   @"%@",
											   "Window text"), tooBigMsg],
                            nil,nil,nil);
            [self terminateBecause: terminatingBecauseOfError];
        }
        
        int response = TBRunAlertPanel(NSLocalizedString(@"Warning", @"Window title"),
                                       NSLocalizedString(@"You have OpenVPN configurations but you do not have any Tunnelblick VPN Configurations.\n\n"
                                                         @"The OpenVPN configurations must be converted to Tunnelblick VPN Configurations if you want to use them.\n\n", @"Window text"),
                                       NSLocalizedString(@"Convert Configurations", @"Button"), // Default return
                                       NSLocalizedString(@"Ignore", @"Button"),                 // Alternate return
                                       NSLocalizedString(@"Quit", @"Button"));                  // Other return
        
		if (   (response == NSAlertOtherReturn)
            || (response == NSAlertErrorReturn)  ) {  // Quit if requested or error
			[self terminateBecause: terminatingBecauseOfQuit];
		} else if (  response == NSAlertDefaultReturn  ) {
            if (  ! startupInstallAuth  ) {
                NSString * prompt = NSLocalizedString(@"Tunnelblick needs to convert OpenVPN configurations to Tunnelblick VPN Configurations.", @"Window text");
                SystemAuth * auth = [SystemAuth newAuthWithPrompt: prompt];
                if (  ! auth  ) {
                    NSLog(@"User cancelled authorization to convert OpenVPN configurations and there are no Tunnelblick configurations");
                    [ConfigurationManager haveNoConfigurationsGuideInNewThread];
                    return;
                }
                [self setStartupInstallAuth: auth];
                [auth release];
            }
            
			NSInteger installerResult = [self runInstaller: INSTALLER_CONVERT_NON_TBLKS
											extraArguments: nil
                                           usingSystemAuth: startupInstallAuth
                                              installTblks: nil];
            if (  installerResult != -1  ) {
                // Installation succeeded or was cancelled
				if (  installerResult == 0  ) {
					[self configurationsChanged];
				}
                return;
            }
            
            // fall through if installer failed
        }
	}
	
    [ConfigurationManager haveNoConfigurationsGuideInNewThread];
}

-(IBAction) addConfigurationWasClicked: (id) sender
{
 	(void) sender;
	
	[ConfigurationManager addConfigurationGuideInNewThread];
}

-(IBAction) disconnectAllMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    NSEnumerator * connEnum = [[self myVPNConnectionDictionary] objectEnumerator];
    VPNConnection * connection;
    while (  (connection = [connEnum nextObject])  ) {
        if (  ! [connection isDisconnected]  ) {
            [connection addToLog: @"*Tunnelblick: Disconnecting; 'Disconnect all' menu command invoked"];
            [connection startDisconnectingUserKnows: [NSNumber numberWithBool: YES]];
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
    NSString * string = [NSString stringWithFormat: @"https://www.tunnelblick.net/contact?v=%@", tunnelblickVersion([NSBundle mainBundle])];
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
	
	if (  ! logScreen  ) {
		logScreen = (MyPrefsWindowController *)[[MyPrefsWindowController sharedPrefsWindowController] retain];
	}
	
    NSUInteger flags = [[NSApp currentEvent] modifierFlags];
    if (  flags & NSAlternateKeyMask  ) {
        [[logScreen window] center];
    }

	[logScreen showWindow: nil];
	[NSApp activateIgnoringOtherApps:YES];
}

static pthread_mutex_t cleanupMutex = PTHREAD_MUTEX_INITIALIZER;

// Returns TRUE if cleaned up, or FALSE if a cleanup is already taking place
-(BOOL) cleanup 
{
    TBLog(@"DB-SD", @"cleanup: Entering cleanup")
    
    gShuttingDownTunnelblick = TRUE;
    
    OSStatus status = pthread_mutex_trylock( &cleanupMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_trylock( &cleanupMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        NSLog(@"pthread_mutex_trylock( &cleanupMutex ) failed is normal and expected when Tunnelblick is updated");
        return FALSE;
    }
    
    // DO NOT ever unlock cleanupMutex -- we don't want to allow another cleanup to take place
    
    if (  startupInstallAuth  ) {
        [self setStartupInstallAuth: nil];
    }
    
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    if ( gShuttingDownOrRestartingComputer ) {
        TBLog(@"DB-SD", @"cleanup: Skipping cleanup because computer is shutting down or restarting")
        // DO NOT ever unlock cleanupMutex -- we don't want to allow another cleanup to take place
        return TRUE;
    }
    
    [self doDisconnectionsForQuittingTunnelblick];
	
    TBCloseAllAlertPanels();
    
    if (  reasonForTermination == terminatingBecauseOfFatalError  ) {
        NSLog(@"Not unloading kexts and not deleting logs because of fatal error.");
    } else if (  needToReplaceLaunchDaemon()  ) {
        NSLog(@"Not unloading kexts and not deleting logs because tunnelblickd is not loaded.");
	} else {
        TBLog(@"DB-SD", @"cleanup: Unloading kexts")
        [self unloadKexts];
        TBLog(@"DB-SD", @"cleanup: Deleting logs")
        [self deleteLogs];
    }

    if ( ! gShuttingDownWorkspace  ) {
        if (  hotKeyEventHandlerIsInstalled && hotKeyModifierKeys != 0  ) {
            TBLog(@"DB-SD", @"cleanup: Unregistering hotKeyEventHandler")
            UnregisterEventHotKey(hotKeyRef);
        }
        
		[ourMainIconView removeTrackingRectangle];
		
        if (  statusItem  ) {
            TBLog(@"DB-SD", @"cleanup: Removing status bar item")
            [self removeStatusItem];
        }
    }
    
    // DO NOT ever unlock cleanupMutex -- we don't want to allow another cleanup to take place
    return TRUE;
}

-(void) deleteLogs
{
	// Delete all the log files for each configuration that is not a 'connect when computer starts' configuration.
    // Because log files are protected, this is done by 'openvpnstart deleteLogs'.
	
	// Only run openvpnstart if there is an OpenVPN log file
	NSString * filename;
	NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: L_AS_T_LOGS];
	while (  (filename = [dirEnum nextObject])  ) {
		[dirEnum skipDescendents];
		if (  [filename hasSuffix: @".openvpn.log"]  ) {
			NSArray  * arguments       = [NSArray arrayWithObject: @"deleteLogs"];
			NSString * stdoutString    = @"";
			NSString * stderrString    = @"";
			OSStatus status = runOpenvpnstart(arguments, &stdoutString, &stderrString);
			if (  status == EXIT_SUCCESS  ) {
				TBLog(@"DB-SD", @"Deleted log files");
			} else {
				NSLog(@"deleteLogs: Error status %lu deleting log files; stdout from openvpnstart = '%@'; stderr from openvpnstart = '%@'",
                      (unsigned long) status, stdoutString, stderrString);
			}
			break;
		}
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
        [self performSelectorOnMainThread:@selector(updateIconImage) withObject:nil waitUntilDone:NO];
    }
	
	[uiUpdater fireTimer];
}

static pthread_mutex_t connectionArrayMutex = PTHREAD_MUTEX_INITIALIZER;

-(void)addConnection: (VPNConnection *) connection
{
	if (  connection  ) {
        
        OSStatus status = pthread_mutex_trylock( &connectionArrayMutex );
        if (  status != EXIT_SUCCESS  ) {
            NSLog(@"pthread_mutex_trylock( &connectionArrayMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
            return;
        }
        
        if (  ! [[self connectionArray] containsObject: connection]  ) {
            NSMutableArray * tempConnectionArray = [[self connectionArray] mutableCopy];
            [tempConnectionArray addObject: connection];
            [self setConnectionArray: [NSArray arrayWithArray: tempConnectionArray]];
            [tempConnectionArray release];
        }
        if (  ! [[self nondisconnectedConnections] containsObject: connection]  ) {
            NSMutableArray * tempConnectionArray = [[self nondisconnectedConnections] mutableCopy];
            [tempConnectionArray addObject: connection];
            [self setNondisconnectedConnections: [NSArray arrayWithArray: tempConnectionArray]];
            [tempConnectionArray release];
        }
        
        status = pthread_mutex_unlock( &connectionArrayMutex );
        if (  status != EXIT_SUCCESS  ) {
            NSLog(@"pthread_mutex_unlock( &connectionArrayMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
            return;
        }    
        
        [self startOrStopUiUpdater];
	}
}

-(void)addNonconnection: (VPNConnection *) connection
{
	if (  connection  ) {
        
        OSStatus status = pthread_mutex_trylock( &connectionArrayMutex );
        if (  status != EXIT_SUCCESS  ) {
            NSLog(@"pthread_mutex_trylock( &connectionArrayMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
            return;
        }
        
        if (  ! [[self nondisconnectedConnections] containsObject: connection]  ) {
            NSMutableArray * tempConnectionArray = [[self nondisconnectedConnections] mutableCopy];
            [tempConnectionArray removeObject: connection];
            [tempConnectionArray addObject:    connection];
            [self setNondisconnectedConnections: [NSArray arrayWithArray: tempConnectionArray]];
            [tempConnectionArray release];
        }
        
        status = pthread_mutex_unlock( &connectionArrayMutex );
        if (  status != EXIT_SUCCESS  ) {
            NSLog(@"pthread_mutex_unlock( &connectionArrayMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
            return;
        }
        
        [self startOrStopUiUpdater];
	}
}

-(void)removeConnection: (VPNConnection *) connection
{
	if (  connection  ) {
        OSStatus status = pthread_mutex_trylock( &connectionArrayMutex );
        if (  status != EXIT_SUCCESS  ) {
            NSLog(@"pthread_mutex_trylock( &connectionArrayMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
            return;
        }
        
        if (  [[self connectionArray] containsObject: connection]  ) {
            NSMutableArray * tempConnectionArray = [[self connectionArray] mutableCopy];
            [tempConnectionArray removeObject: connection];
            [self setConnectionArray: [NSArray arrayWithArray: tempConnectionArray]];
            [tempConnectionArray release];
        }
        if (  [[self nondisconnectedConnections] containsObject: connection]  ) {
            NSMutableArray * tempConnectionArray = [[self nondisconnectedConnections] mutableCopy];
            [tempConnectionArray removeObject: connection];
            [self setNondisconnectedConnections: [NSArray arrayWithArray: tempConnectionArray]];
            [tempConnectionArray release];
        }
        
        status = pthread_mutex_unlock( &connectionArrayMutex );
        if (  status != EXIT_SUCCESS  ) {
            NSLog(@"pthread_mutex_unlock( &connectionArrayMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
            return;
        }    
        
        [self startOrStopUiUpdater];
    }
}

-(void) terminateBecause: (enum TerminationReason) reason
{
	reasonForTermination = reason;
    
    if (   (reason != terminatingBecauseOfLogout)
        && (reason != terminatingBecauseOfRestart)
        && (reason != terminatingBecauseOfShutdown)  ) {
        terminatingAtUserRequest = TRUE;
    }
    
    if (  reason == terminatingBecauseOfQuit  ) {
        terminatingAtUserRequest = TRUE;
    }
	
	gShuttingDownTunnelblick = TRUE;
    
    if (  reason == terminatingBecauseOfError  ) {
        NSLog(@"Terminating because of error; stack trace: %@", callStack());
    }
	
	[NSApp terminate: self];
}

int runUnrecoverableErrorPanel(NSString * msg)
{
	int result = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick Error", @"Window title"),
                                 [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick encountered a fatal error.\n\nPlease contact the developers at developers@tunnelblick.net for help.\n\nThe problem was:\n\n%@", @"Window text"),
                                  msg],
                                 NSLocalizedString(@"Download", @"Button"),
                                 NSLocalizedString(@"Quit", @"Button"),
                                 nil);
	if( result == NSAlertDefaultReturn ) {
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.tunnelblick.net/"]];
	}
    
    // Quit if "Quit" or error
    
    exit(2);
}

static void signal_handler(int signalNumber)
{
    if (  signalNumber == SIGTERM ) {
        if (   gShuttingDownTunnelblick
            && (   (reasonForTermination == terminatingBecauseOfLogout)
                || (reasonForTermination == terminatingBecauseOfRestart)
                || (reasonForTermination == terminatingBecauseOfShutdown) )  ) {
                NSLog(@"Ignoring SIGTERM (signal %d) because Tunnelblick is already terminating", signalNumber);
                return;
            } else {
                NSLog(@"SIGTERM (signal %d) received", signalNumber);
                [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfQuit];
                return;
            }
    }
    
    const char * siglist = (  signalNumber < NSIG
                            ? sys_siglist[signalNumber]
                            : "");
    
    NSLog(@"Received fatal signal %s (%d); stack trace: %@", siglist, signalNumber, callStack());
    
    if ( reasonForTermination == terminatingBecauseOfFatalError ) {
        NSLog(@"signal_handler: Error while handling signal.");
    } else {
        runUnrecoverableErrorPanel([NSString stringWithFormat: NSLocalizedString(@"Received fatal signal %d.", @"Window text"), signalNumber]);
        reasonForTermination = terminatingBecauseOfFatalError;
        gShuttingDownTunnelblick = TRUE;
        NSLog(@"signal_handler: Starting cleanup.");
        if (  [((MenuController *)[NSApp delegate]) cleanup]  ) {
            NSLog(@"signal_handler: Cleanup finished.");
        } else {
            NSLog(@"signal_handler: Cleanup already being done.");
        }
    }
    exit(0);
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
#ifndef TBDebug
        sigaction(SIGTRAP, &action, NULL) ||
#endif
        sigaction(SIGPIPE, &action, NULL)) {
        NSLog(@"Warning: setting signal handler failed: '%s'", strerror(errno));
    }	
}

// Invoked by Tunnelblick modifications to Sparkle with the path to a .bundle with updated configurations to install
-(void) installConfigurationsUpdateInBundleAtPathHandler: (NSString *) path
{
    // This handler SHOULD proceed even if the computer is shutting down
	TBLog(@"DB-UC", @"Scheduling installation of updated configurations at '%@'", path);
    [self performSelectorOnMainThread: @selector(installConfigurationsUpdateInBundleAtPathMainThread:)
                           withObject: path
                        waitUntilDone: YES];
}

-(void) installConfigurationsUpdateInBundleAtPathMainThread: (NSString *) path
{
    // Proceed even if the computer is shutting down
    TBLog(@"DB-UC", @"Starting a new thread to update configurations at '%@'", path);
	[ConfigurationManager installConfigurationsUpdateInBundleInMainThreadAtPath: path];
}

-(BOOL) shouldInstallConfigurations: (NSArray *) filePaths withTunnelblick: (BOOL) withTunnelblick {
    
    // If any of the configurations contain commands, asks the user if they should be installed.
    
    CommandOptionsStatus status = [ConfigurationManager commandOptionsInConfigurationsAtPaths: filePaths];
    
    int userAction;
    
    NSString * message;
    
    NSString * withTunnelblickMessage = (  withTunnelblick
                                         ? NSLocalizedString(@"Configurations that are not part of Tunnelblick are set up to be installed when you install Tunnelblick.\n\n", @"Window text")
                                         : @"");
    
    switch (  status  ) {
            
        case CommandOptionsNo:
            return YES;
            
        case CommandOptionsYes:
            message = [NSString stringWithFormat: @"%@%@", withTunnelblickMessage,
                       NSLocalizedString(@"One or more VPN configurations you are installing include programs which will run"
                                         @" as root when you connect to a VPN. They are able to TAKE"
                                         @" COMPLETE CONTROL OF YOUR COMPUTER.\n\n"
                                         @"YOU SHOULD NOT INSTALL THESE CONFIGURATIONS UNLESS YOU TRUST THEIR AUTHOR.\n\n"
                                         @"Do you trust the author of the configurations and wish to install them?\n\n",
                                         @"Window text")];
            userAction = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                                         message,
                                         NSLocalizedString(@"Cancel",  @"Button"), // Default
                                         NSLocalizedString(@"Install", @"Button"), // Alternate
                                         nil);                                     // Other
            if (  userAction == NSAlertAlternateReturn  ) {
                userAction = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                                             NSLocalizedString(@"Are you sure you wish to install configurations which can TAKE"
                                                               @" COMPLETE CONTROL OF YOUR COMPUTER?\n\n",
                                                               @"Window text"),
                                             NSLocalizedString(@"Cancel",  @"Button"), // Default
                                             NSLocalizedString(@"Install", @"Button"), // Alternate
                                             nil);                                     // Other
                if (  userAction == NSAlertAlternateReturn  ) {
                    return YES;
                }
            }
            
            return NO;
            break;
            
        case CommandOptionsUnknown:
            message = [NSString stringWithFormat: @"%@%@", withTunnelblickMessage,
                       NSLocalizedString(@"One or more VPN configurations you are installing include OpenVPN options that"
                                         @" were not recognized by Tunnelblick. That may be an error in the configuration or"
                                         @" an error in Tunnelblick, or the configurations might include programs"
                                         @" which will run as root when you connect to a VPN. Such programs would be able to"
                                         @" TAKE COMPLETE CONTROL OF YOUR COMPUTER.\n\n"
                                         @"YOU SHOULD NOT INSTALL THESE CONFIGURATIONS UNLESS YOU TRUST THEIR AUTHOR.\n\n"
                                         @"Do you trust the author of the configurations and wish to install them?\n\n",
                                         @"Window text")];
            userAction = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                                         message,
                                         NSLocalizedString(@"Cancel",  @"Button"), // Default
                                         NSLocalizedString(@"Install", @"Button"), // Alternate
                                         nil);                                     // Other
            
            if (  userAction == NSAlertAlternateReturn  ) {
                userAction = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                                             NSLocalizedString(@"Are you sure you wish to install configurations which might be able to TAKE"
                                                               @" COMPLETE CONTROL OF YOUR COMPUTER?\n\n",
                                                               @"Window text"),
                                             NSLocalizedString(@"Cancel",  @"Button"), // Default
                                             NSLocalizedString(@"Install", @"Button"), // Alternate
                                             nil);                                     // Other
                return (  userAction == NSAlertAlternateReturn  );
            }
            
            return NO;
            break;
            
        case CommandOptionsError:
        default:
            NSLog(@"error status %ld returned from commandOptionsInConfigurationsAtPaths:", (long)status);
            TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                            NSLocalizedString(@"An error occurred. See the Console Log for details.", @"Window text"),
                            nil, nil, nil);
            return NO;
    }
}

-(void) notifyDelegateAfterInstallingConfigurationsInPaths: (NSArray *) filePaths {
    
    // Configuration(s) were double-clicked or dropped onto Tunnelblick.app.
    // Installs them, perhaps after issuing a warning if any of them contain programs or OpenVPN options (such as "up") that invoke commands.
    
    if (  [self shouldInstallConfigurations: filePaths withTunnelblick: NO]  ) {
        [ConfigurationManager installConfigurationsInNewThreadShowMessagesNotifyDelegateWithPaths: filePaths];
    } else {
        [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
    }
}

// Invoked when the user double-clicks on one or more .tblk packages or .ovpn or .conf files,
//                  or drags and drops one or more .of them on the Tunnelblick application or the icon in the status bar
- (BOOL)application: (NSApplication * )theApplication
          openFiles: (NSArray * )filePaths
{
	(void) theApplication;
	
    // If we have finished launching Tunnelblick, we open the file(s) now
    // otherwise the file(s) opening launched us, but we have not initialized completely,
    // so we store the paths and open the file(s) later, in applicationDidFinishLaunching.
    
    if (  launchFinished  ) {
        [self notifyDelegateAfterInstallingConfigurationsInPaths: filePaths];
    } else {
        [dotTblkFileList addObjectsFromArray: filePaths];
    }
    
    return TRUE;
}

- (BOOL) openFiles: (NSArray * ) filePaths {
    
    // Invoked from MainIconView to implement files dropped on the icon for installation.
    
    return [self application: nil openFiles: filePaths];
}
-(void) setupUpdaterAutomaticChecks {
    
    if (  [updater respondsToSelector: @selector(setAutomaticallyChecksForUpdates:)]  ) {
        if (  [gTbDefaults boolForKey: @"inhibitOutboundTunneblickTraffic"]  ) {
            [updater setAutomaticallyChecksForUpdates: NO];
			[myConfigMultiUpdater stopAllUpdateChecking];
        } else {
            BOOL userIsAdminOrNonAdminsCanUpdate = (   userIsAnAdmin
                                                    || ( ! [gTbDefaults boolForKey:@"onlyAdminCanUpdate"])  );
			if (  userIsAdminOrNonAdminsCanUpdate  ) {
				if (  [gTbDefaults preferenceExistsForKey: @"updateCheckAutomatically"]  ) {
					BOOL startChecking = [gTbDefaults boolForKey: @"updateCheckAutomatically"];
					[updater setAutomaticallyChecksForUpdates: startChecking];
					if (  startChecking) {
						[myConfigMultiUpdater startAllUpdateCheckingWithUI: NO];
					} else {
						[myConfigMultiUpdater stopAllUpdateChecking];
					}
				}
			} else {
				if (  [gTbDefaults boolForKey: @"updateCheckAutomatically"]  ) {
					NSLog(@"Automatic check for updates will not be performed because user is not allowed to administer this computer and 'onlyAdminCanUpdate' preference is set");
				}
				[updater setAutomaticallyChecksForUpdates: NO];
			}
		}
    } else {
        if (  [gTbDefaults preferenceExistsForKey: @"updateCheckAutomatically"]  ) {
            NSLog(@"Automatic checks for updates will not be performed because the updater does not respond to setAutomaticallyChecksForUpdates:");
        }
	}
}

- (void) applicationWillFinishLaunching: (NSNotification *)notification
{
	(void) notification;
	
    TBLog(@"DB-SU", @"applicationWillFinishLaunching: 001")
    
    BOOL userIsAdminOrNonAdminsCanUpdate = ( userIsAnAdmin ) || ( ! [gTbDefaults boolForKey:@"onlyAdminCanUpdate"] );
	
    TBLog(@"DB-SU", @"applicationWillFinishLaunching: 002")
	
    // We aren't supposed to use Sparkle Updater's preferences directly. However, we need to be able to, in effect,
    // override two of them via forced-preferences.plist. So we have two of our own preferences which mirror Sparkle's. Our
    // preferences are "updateCheckAutomatically" and "updateAutomatically", which mirror
    // Sparkle's "SUEnableAutomaticChecks" and "SUAutomaticallyUpdate". We use our preferences to
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
    // checking.
    
    // Initialize our preferences from Sparkle's if ours have not been set yet (and thus are not being forced), and Sparkle's _have_ been set
    // (We have to access Sparkle's prefs directly because we need to wait until they have actually been set one way or the other)
    // Note that we access Sparkle's preferences via stdDefaults, so they can't be forced (Sparkle would ignore the forcing, anyway)
    // However, when we try to set out preferences from Sparkle's, if they are forced then they won't be changed.
    
    [self setOurPreferencesFromSparkles];
    
	[[NSUserDefaults standardUserDefaults] setBool: TRUE forKey: @"SUHasLaunchedBefore"];
	
    TBLog(@"DB-SU", @"applicationWillFinishLaunching: 003")
    
    [self setupUpdaterAutomaticChecks];
	
    TBLog(@"DB-SU", @"applicationWillFinishLaunching: 004")
    if (  [updater respondsToSelector: @selector(setAutomaticallyDownloadsUpdates:)]  ) {
        if (  userIsAdminOrNonAdminsCanUpdate  ) {
            if (  [gTbDefaults preferenceExistsForKey: @"updateAutomatically"]  ) {
                [updater setAutomaticallyDownloadsUpdates: [gTbDefaults boolForKey: @"updateAutomatically"]];
            }
        } else {
            if (  [gTbDefaults boolForKey: @"updateAutomatically"]  ) {
                NSLog(@"Automatic updates will not be performed because user is not allowed to administer this computer and 'onlyAdminCanUpdate' preference is set");
            }
            [updater setAutomaticallyDownloadsUpdates: NO];
        }
    } else {
        if (  [gTbDefaults preferenceExistsForKey: @"updateAutomatically"]  ) {
            NSLog(@"Ignoring 'updateAutomatically' preference because Sparkle Updater does not respond to setAutomaticallyDownloadsUpdates:");
        }
    }
    
    TBLog(@"DB-SU", @"applicationWillFinishLaunching: 005")
    if (  [updater respondsToSelector: @selector(setSendsSystemProfile:)]  ) {
        [updater setSendsSystemProfile: NO];
    } else {
        NSLog(@"Sparkle Updater Updater does not respond to setSendsSystemProfile:");
    }
    
    TBLog(@"DB-SU", @"applicationWillFinishLaunching: 006")
    if (  [updater respondsToSelector: @selector(setUpdateCheckInterval:)]  ) {
        NSTimeInterval checkInterval = [gTbDefaults timeIntervalForKey: @"updateCheckInterval"
                                                               default: 60.0 * 60.0 * 24.0          // Default = 24 hours
                                                                   min: 60.0 * 60.0                 // Minumum = 1 hour to prevent DOS on the update server
                                                                   max: 60.0 * 60.0 * 24.0 * 7];    // Maximum = 1 week
        [updater setUpdateCheckInterval: checkInterval];
    } else {
        if (  [gTbDefaults preferenceExistsForKey: @"updateCheckInterval"]  ) {
            NSLog(@"Ignoring 'updateCheckInterval' preference because Sparkle Updater Updater does not respond to setUpdateCheckInterval:");
        }
    }
    
    TBLog(@"DB-SU", @"applicationWillFinishLaunching: 008 -- LAST")
}

// If we haven't set up the updateCheckAutomatically and updateAutomatically preferences,
// and the corresponding Sparkle preferences have been set, copy Sparkle's settings to ours
-(void) setOurPreferencesFromSparkles
{
    NSUserDefaults * stdDefaults = [NSUserDefaults standardUserDefaults];
    
    if (  ! [gTbDefaults preferenceExistsForKey: @"updateCheckAutomatically"]  ) {
        id obj = [stdDefaults objectForKey: @"SUEnableAutomaticChecks"];
        if (  obj  ) {
            if (  [obj respondsToSelector:@selector(boolValue)]) {
                [gTbDefaults setBool: [obj boolValue] forKey: @"updateCheckAutomatically"];
            } else {
                NSLog(@"Preference 'SUEnableAutomaticChecks' is not a boolean and is being ignored by Tunnelblick");
            }
        }
    }
    
    // SUAutomaticallyUpdate may be changed at any time by a checkbox in Sparkle's update window, so we always use Sparkle's version
    if (  [stdDefaults objectForKey: @"SUAutomaticallyUpdate"]  ) {
        [gTbDefaults setBool: [updater automaticallyDownloadsUpdates]       // But if it is forced, this setBool will be ignored
                      forKey: @"updateAutomatically"];
    }
    
}

-(BOOL) checkSignatureIsOurs: (NSString *) codesignDvvOutput {
    
    BOOL sawRootCa   = FALSE;
    BOOL sawDevApple = FALSE;
    BOOL sawDevUs    = FALSE;
    BOOL sawIdent    = FALSE;
    BOOL sawTeam     = (  runningOnMavericksOrNewer()
                        ? FALSE
                        : TRUE);    // codesign on some OS X 10.8 and lower does not output this field
    
    NSArray * lines = [codesignDvvOutput componentsSeparatedByString: @"\n"];
    NSString * line;
    NSEnumerator * e = [lines objectEnumerator];
    while (  (line = [e nextObject])  ) {
        
        if (  [line hasPrefix: @"Identifier="]  ) {
            if (  [line isEqualToString: [@"Identifier=net.tunn" stringByAppendingString: @"elblick.tunnelblick"]]  ) {
                sawIdent = TRUE;
            } else {
                NSLog(@"The output from codesign contained an incorrect 'Identifier'");
                return FALSE;
            }
            
        } else if (  [line hasPrefix: @"TeamIdentifier="]  ) {
            if (  [line isEqualToString: @"TeamIdentifier=Z2SG5H3HC8"]  ) {
                sawTeam = TRUE;
            } else {
                NSLog(@"The output from codesign contained an incorrect 'TeamIdentifier'");
                return FALSE;
            }
            
        } else if (  [line hasPrefix: @"Authority="]  ) {
            if (         [line isEqualToString: @"Authority=Apple Root CA"]  ) {
                sawRootCa = TRUE;
            } else if (  [line isEqualToString: @"Authority=Developer ID Application: Jonathan Bullard (Z2SG5H3HC8)"]  ) {
                sawDevUs = TRUE;
            } else if (  [line isEqualToString: @"Authority=Developer ID Certification Authority"]  ) {
                sawDevApple = TRUE;
            } else {
                NSLog(@"The output from codesign contained an incorrect 'Authority'");
                return FALSE;
            }
        }
    }
    
    BOOL result = (  sawRootCa && sawDevApple && sawDevUs && sawTeam && sawIdent  );
    if (  ! result  ) {
        NSLog(@"The output from codesign did not include all the items that are required. The output was \n:%@", codesignDvvOutput);
    }
    return result;
}

-(BOOL) hasValidSignature
{
    // Normal versions of Tunnelblick can be checked with codesign running as the user until macOS Sierra 10.12.0
    //
    // But Deployed versions need to run codesign as root, so codesign will "see" the .tblk contents that
    // are owned by root and not accessible to other users (like keys and certificates). "openvpnstart checkSignature" runs codesign as
    // root, but only if the Deployed Tunnelblick has been installed.
    //
    // So if a Deployed Tunnelblick hasn't been installed yet (e.g., it is running from .dmg), we don't check the signature here, and we assume it is valid.
    //
    // There could be a separate check for an invalid signature in installer, since installer could run codesign as root
    // using the installer's authorization. However, installer runs without a UI, so it is complicated to provide the ability
    // to report a failure and provide the option to continue. Considering that most Deployed Tunnelblick's are unsigned, this
    // separate check has a low priority.
    
    // On Sierra or later, do digital signature checking without using codesign.
    // This could be done on Lion or newer (with a minor change because anything earlier than 10.10.3 doesn't support the
    // kSecCSStrictValidate flag), but for backward compatibility we're only doing this for Sierra (for now).
    // If extended to other versions, we could do it for Deployed versions, too, because we don't require openvpnstart.
    
    if (  runningOnSierraOrNewer()  ) {
        return appHasValidSignature();
    }
    
    if (  [gFileMgr fileExistsAtPath: gDeployPath]  ) {
        NSString * tunnelblickdPath = [[NSBundle mainBundle] pathForResource: @"tunnelblickd" ofType: nil];
        if (  [tunnelblickdPath isNotEqualTo: @"/Applications/Tunnelblick.app/Contents/Resources/tunnelblickd"]  ) {
            return YES;
        }
        NSDictionary * attributes = [gFileMgr tbFileAttributesAtPath: tunnelblickdPath traverseLink: NO];
        id obj = [attributes fileOwnerAccountID];
        if (   ( ! obj)
            || ( [obj unsignedLongValue] != 0)  ) {
            return YES;     // tunnelblickd is not owned by root:wheel, so it can't check the signature properly
        }
        obj = [attributes fileGroupOwnerAccountID];
        if (   ( ! obj)
            || ( [obj unsignedLongValue] != 0)  ) {
            return YES;     // tunnelblickd is not owned by root:wheel, so it can't check the signature properly
        }
        if (  needToReplaceLaunchDaemon()) {
            return YES;     // tunnelblickd is not loaded
        }

        // Deployed and tunnelblickd has been installed, so we can run it to check the signature
        OSStatus status = runOpenvpnstart([NSArray arrayWithObject: @"checkSignature"], nil, nil);
        return (status == EXIT_SUCCESS);
    }
    
	NSString * stdoutString = nil;
	NSString * stderrString = nil;
	
    // Not a Deployed version of Tunnelblick, so we can run codesign as the user
    if (  ! [gFileMgr fileExistsAtPath: TOOL_PATH_FOR_CODESIGN]  ) {  // If codesign binary doesn't exist, complain and assume it is NOT valid
        NSLog(@"Assuming digital signature invalid because '%@' does not exist", TOOL_PATH_FOR_CODESIGN);
        return FALSE;
    }
    
    NSString * appPath = [[NSBundle mainBundle] bundlePath];
    NSArray *arguments = (  runningOnLionOrNewer()
                          ? [NSArray arrayWithObjects: @"-v", @"-v", @"--deep", appPath, nil]
                          : [NSArray arrayWithObjects: @"-v", @"-v", appPath, nil]);
    OSStatus status = runTool(TOOL_PATH_FOR_CODESIGN, arguments, &stdoutString, &stderrString);

    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"'codesign -v -v [--deep]' returned status = %ld; stdout = '%@'; stderr = '%@'", (long)status, stdoutString, stderrString);
		return FALSE;
	}
	
    arguments = [NSArray arrayWithObjects: @"-dvv", appPath, nil];
    status = runTool(TOOL_PATH_FOR_CODESIGN, arguments, &stdoutString, &stderrString);
    
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"'codesign -dvv' returned status = %ld; stdout = '%@'; stderr = '%@'", (long)status, stdoutString, stderrString);
        return FALSE;
    }
    
    return [self checkSignatureIsOurs: stderrString];
}

- (NSURL *) getIPCheckURL
{
    NSString * urlString = [gTbDefaults stringForKey: @"IPCheckURL"];
	if (   ( ! urlString)
        || [gTbDefaults canChangeValueForKey: @"IPCheckURL"]  ) {
        NSDictionary * infoPlist = [self tunnelblickInfoDictionary];
        urlString = [infoPlist objectForKey: @"IPCheckURL"];
    }
    
    NSURL * url = nil;
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
	// Invoked when the Dock item is clicked to relaunch Tunnelblick, or the application is double-clicked.
	// Just show the VPN Details… window.
	(void) theApp;
	(void) hasWindows;
	
	[self openPreferencesWindow: self];
	return NO;
}

// Examines an NSString for the first decimal digit or the first series of decimal digits
// Returns an NSRange that includes all of the digits
-(NSRange) rangeOfDigits: (NSString *) s
{
    NSRange r1, r2;
    // Look for a digit
    r1 = [s rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet] ];
    if ( r1.length == 0 ) {
        
        // No digits, return that they were not found
        return (r1);
    } else {
        
        // r1 has range of the first digit. Look for a non-digit after it
        r2 = [[s substringFromIndex:r1.location] rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]];
        if ( r2.length == 0) {
            
            // No non-digits after the digits, so return the range from the first digit to the end of the string
            r1.length = [s length] - r1.location;
            return (r1);
        } else {
            
            // Have some non-digits, so the digits are between r1 and r2
            r1.length = r1.location + r2.location - r1.location;
            return (r1);
        }
    }
}

// Given a string with a version number, parses it and returns an NSDictionary with full, preMajor, major, preMinor, minor, preSuffix, suffix, and postSuffix fields
//              full is the full version string as displayed by openvpn when no arguments are given.
//              major, minor, and suffix are strings of digits (may be empty strings)
//              The first string of digits goes in major, the second string of digits goes in minor, the third string of digits goes in suffix
//              preMajor, preMinor, preSuffix and postSuffix are strings that come before major, minor, and suffix, and after suffix (may be empty strings)
//              if no digits, everything goes into preMajor
-(NSDictionary *) parseVersionInfoFromString: (NSString *) string
{
    NSRange r;
    NSString * s = string;
    
    NSString * preMajor     = @"";
    NSString * major        = @"";
    NSString * preMinor     = @"";
    NSString * minor        = @"";
    NSString * preSuffix    = @"";
    NSString * suffix       = @"";
    NSString * postSuffix   = @"";
    
    r = [self rangeOfDigits: s];
    if (r.length == 0) {
        preMajor = s;
    } else {
        preMajor = [s substringToIndex:r.location];
        major = [s substringWithRange:r];
        s = [s substringFromIndex:r.location+r.length];
        
        r = [self rangeOfDigits: s];
        if (r.length == 0) {
            preMinor = s;
        } else {
            preMinor = [s substringToIndex:r.location];
            minor = [s substringWithRange:r];
            s = [s substringFromIndex:r.location+r.length];
            
            r = [self rangeOfDigits: s];
            if (r.length == 0) {
                preSuffix = s;
            } else {
                preSuffix = [s substringToIndex:r.location];
                suffix = [s substringWithRange:r];
                postSuffix = [s substringFromIndex:r.location+r.length];
            }
        }
    }
    
    return (  [NSDictionary dictionaryWithObjectsAndKeys:
               [[string copy] autorelease], @"full",
               [[preMajor copy] autorelease], @"preMajor",
               [[major copy] autorelease], @"major",
               [[preMinor copy] autorelease], @"preMinor",
               [[minor copy] autorelease], @"minor",
               [[preSuffix copy] autorelease], @"preSuffix",
               [[suffix copy] autorelease], @"suffix",
               [[postSuffix copy] autorelease], @"postSuffix",
               nil]  );
}

-(BOOL) setUpOpenVPNNames {
    
    NSMutableArray * nameArray = [[[NSMutableArray alloc] initWithCapacity: 5] autorelease];
    
    NSString * openvpnDirPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"openvpn"];
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: openvpnDirPath];
    NSString * dirName;
    while (  (dirName = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        if (   ( [dirName hasPrefix: @"openvpn-"] )  ) {
			NSString * versionWithSslSuffix = [dirName substringFromIndex: [@"openvpn-" length]];
            NSArray * parts = [versionWithSslSuffix componentsSeparatedByString: @"-"];
			NSString * versionWithoutSslSuffix = [parts objectAtIndex: 0];
            
            // Use ./openvpn --version to get the version information
            NSString * openvpnPath = [[openvpnDirPath stringByAppendingPathComponent: dirName ]
                                      stringByAppendingPathComponent: @"openvpn"];
            NSString * stdoutString = @"";
            NSString * stderrString = @"";
            OSStatus status = runTool(openvpnPath, [NSArray arrayWithObject: @"--version"], &stdoutString, &stderrString);
            if (   (status != EXIT_SUCCESS)
				&& (status != 1)  ) {	//OpenVPN returns a status of 1 when the --version option is used
                NSLog(@"openvpnstart returned %lu trying to run '%@ --version'; stderr was '%@'; stdout was '%@'", (unsigned long)status, openvpnPath, stderrString, stdoutString);
                [self terminateBecause: terminatingBecauseOfError];
                return FALSE;
            }
            
            NSRange rng1stSpace = [stdoutString rangeOfString: @" "];
            if (  rng1stSpace.length != 0  ) {
                NSRange rng2ndSpace = [stdoutString rangeOfString: @" " options: 0 range: NSMakeRange(rng1stSpace.location + 1, [stdoutString length] - rng1stSpace.location - 1)];
                if ( rng2ndSpace.length != 0  ) {
                    NSString * versionString = [stdoutString substringWithRange: NSMakeRange(rng1stSpace.location + 1, rng2ndSpace.location - rng1stSpace.location -1)];
					if (  ! [versionString isEqualToString: versionWithoutSslSuffix]  ) {
						NSLog(@"OpenVPN version ('%@') reported by the program is not consistent with the version ('%@') derived from the name of folder '%@' in %@", versionString, versionWithoutSslSuffix, dirName, openvpnDirPath);
						[self terminateBecause: terminatingBecauseOfError];
						return FALSE;
					}
                    [nameArray addObject: versionWithSslSuffix];
                    continue;
                }
            }
            
            NSLog(@"Error getting info from '%@ --version': stdout was '%@'", openvpnPath, stdoutString);
            [self terminateBecause: terminatingBecauseOfError];
            return FALSE;
        }
    }
    
    if (  [nameArray count] == 0  ) {
        NSLog(@"There are no versions of OpenVPN in this copy of Tunnelblick");
        [self terminateBecause: terminatingBecauseOfError];
        return FALSE;
    }
	
	// Sort the array so OpenSSL comes before LibreSSL
	NSMutableArray * sortedNames = [[[NSMutableArray alloc] initWithCapacity: [nameArray count]] autorelease];
	NSUInteger ix;
	for (  ix=0; ix<[nameArray count]-1; ix++  ) {
		if (   (ix != [nameArray count]-1)
            && ([[nameArray objectAtIndex: ix]     rangeOfString: @"libressl"].length != 0)
			&& ([[nameArray objectAtIndex: ix + 1] rangeOfString: @"openssl"].length  != 0)  ) {
			[sortedNames addObject: [nameArray objectAtIndex: ix + 1]];
			[sortedNames addObject: [nameArray objectAtIndex: ix]];
			ix++;
		} else {
			[sortedNames addObject: [nameArray objectAtIndex: ix]];
		}
	}
	
    [self setOpenvpnVersionNames: [NSArray arrayWithArray: sortedNames]];
    
    return TRUE;
}

-(NSArray *) uninstalledConfigurationUpdates {
	
	NSDictionary * highestEditions = highestEditionForEachBundleIdinL_AS_T();
	
    NSMutableArray * configsToInstall = [NSMutableArray arrayWithCapacity: 10];
    NSString * bundleIdAndEdition;
    NSDirectoryEnumerator * containerEnum = [gFileMgr enumeratorAtPath: L_AS_T_TBLKS];
    while (  (bundleIdAndEdition = [containerEnum nextObject])  ) {
        [containerEnum skipDescendents];
        
        if (   [bundleIdAndEdition hasPrefix: @"."]
            || [bundleIdAndEdition hasSuffix: @".tblk"]  ) {
            continue;
        }
        
		NSString * bundleId = [bundleIdAndEdition stringByDeletingPathEdition];
		NSString * edition  = [bundleIdAndEdition pathEdition];
		NSString * highest  = [highestEditions objectForKey: bundleId];
		if (   highest
			&& [edition isEqualToString: highest]  ) {
			
			NSString * containerPath = [L_AS_T_TBLKS stringByAppendingPathComponent: bundleIdAndEdition];
			NSString * tblkFileName;
			NSDirectoryEnumerator * innerEnum = [gFileMgr enumeratorAtPath: containerPath];
			while (  (tblkFileName = [innerEnum nextObject])  ) {
				[innerEnum skipDescendents];
				if (  [tblkFileName hasSuffix: @".tblk"]  ) {
					NSString * tblkPath = [containerPath stringByAppendingPathComponent: tblkFileName];
					NSString * installedFilePath = [[tblkPath
													 stringByAppendingPathComponent: @"Contents"]
													stringByAppendingPathComponent: @"installed"];
					if (  ! [gFileMgr fileExistsAtPath: installedFilePath]  ) {
						TBLog(@"DB-UC", @"Found uninstalled configuration update in %@", bundleIdAndEdition);
						[configsToInstall addObject: tblkPath];
						break; // out of inner loop only
					}
				}
			}
		}
	}
    
    return [NSArray arrayWithArray: configsToInstall];
}

-(void) startCheckingForConfigurationUpdates {
    
    [myConfigMultiUpdater startAllUpdateCheckingWithUI: NO];    // Start checking for configuration updates in the background (when the application updater is finished)
}

-(void) doPlaceIconNearSpotlightIcon: (NSNumber *) newPreferenceValueNumber {
    
    showingConfirmIconNearSpotlightIconDialog = FALSE;
    
    BOOL newPreferenceValue = [newPreferenceValueNumber boolValue];
    BOOL currentPreferenceValue = [gTbDefaults boolForKey: @"placeIconInStandardPositionInStatusBar"];
    
    if (  currentPreferenceValue != newPreferenceValue  ) {
        [gTbDefaults setBool: newPreferenceValue forKey: @"placeIconInStandardPositionInStatusBar"];
        [((MenuController *)[NSApp delegate]) moveStatusItemIfNecessary];
    }
}

-(void) setSkipWarningAboutPlacingIconNearTheSpotlightIconToYes {
    
    [gTbDefaults setBool: YES forKey: @"skipWarningAboutPlacingIconNearTheSpotlightIcon"];
}

-(void) confirmIconNearSpotlightIconIsOKThread {
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    int result;
    BOOL checkboxResult = NO;
    do {
        result = TBRunAlertPanelExtended(NSLocalizedString(@"Tunnelblick", @"Window title"),
                                         NSLocalizedString(@"Your computer may not be able to reliably show the Tunnelblick icon near the Spotlight icon.\n\n"
                                                           @"This may cause the Tunnelblick icon to sometimes DISAPPEAR from the menu bar.\n\n"
                                                           @"Are you sure you want to place the Tunnelblick icon near the Spotlight icon?\n\n", @"Window text"),
                                         NSLocalizedString(@"Place Icon Normally",                @"Button"), // Default
                                         NSLocalizedString(@"More Info", @"Button"),                          // Alternate
                                         NSLocalizedString(@"Place Icon Near the Spotlight Icon", @"Button"), // Other
                                         @"skipWarningAboutPlacingIconNearTheSpotlightIcon",
                                         NSLocalizedString(@"Do not warn about this again",       @"Checkbox name"),
                                         &checkboxResult,
                                         NSAlertDefaultReturn);
        if (  result == NSAlertAlternateReturn  ) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.tunnelblick.net/cIconPlacement.html"]];
        }
    } while (  result == NSAlertAlternateReturn  );
    
    if (  checkboxResult) {
        [self performSelectorOnMainThread: @selector(setSkipWarningAboutPlacingIconNearTheSpotlightIconToYes) withObject: nil waitUntilDone: NO];
    }
    
    NSNumber * newPreferenceValue = [NSNumber numberWithBool: (result != NSAlertOtherReturn)];
    [self performSelectorOnMainThread: @selector(doPlaceIconNearSpotlightIcon:) withObject: newPreferenceValue waitUntilDone: NO];
    
    [pool drain];
}

-(void) showConfirmIconNearSpotlightIconDialog {
    
    if (   ( ! showingConfirmIconNearSpotlightIconDialog)
        && ( ! [gTbDefaults boolForKey: @"skipWarningAboutPlacingIconNearTheSpotlightIcon"])  ) {
        showingConfirmIconNearSpotlightIconDialog = TRUE;
        [NSThread detachNewThreadSelector: @selector(confirmIconNearSpotlightIconIsOKThread) toTarget: self withObject: nil];
    }
}

- (void) applicationDidFinishLaunching: (NSNotification *)notification
{
	(void) notification;
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 001")

    [self installSignalHandler];
	[self updateScreenList];
    
    // gMainThread is used on OS X 10.4 because [NSThread isMainThread] is not available.
    // This use of gMainThread assumes that
    //      (1) applicationDidFinishLaunching is launched on the main thread; and
    //      (2) the main thread does not change in the course of the program's execution.
    // Both of these assumptions appear true based on testing on OS X 10.4
    if (  gMainThread  ) {
        NSLog(@"Ignoring extra invocation of applicationDidFinishLaunching:");
        return;
    }
    gMainThread = [NSThread currentThread];
    
    [NSApp setupNewAutoLaunchOnLogin];

    // Get names and version info for all copies of OpenVPN in ../Resources/openvpn
    if (  ! [self setUpOpenVPNNames]) {
        return; // Error already put in log and app terminated
    }
    
    if (   [gTbDefaults objectForKey: @"installationUID"]
        && [gTbDefaults canChangeValueForKey: @"installationUID"]  ) {
        [gTbDefaults removeObjectForKey: @"installationUID"];
        NSLog(@"Removed the UUID for this user's installation of Tunnelblick. Tunnelblick no longer uses or transmits UUIDs.");
    }
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 002")
    // If checking for updates is enabled, we do a check every time Tunnelblick is launched (i.e., now)
    // We also check for updates if we haven't set our preferences yet. (We have to do that so that Sparkle
    // will ask the user whether to check or not, then we set our preferences from that.)
    if (   [gTbDefaults boolWithDefaultYesForKey: @"updateCheckAutomatically"]  ) {
        if (  [updater respondsToSelector: @selector(checkForUpdatesInBackground)]  ) {
            if (  [self feedURLToUse]  ) {
                [updater checkForUpdatesInBackground];
            } else {
                NSLog(@"Not checking for updates because no FeedURL has been set");
            }
        } else {
            NSLog(@"Cannot check for updates because Sparkle Updater does not respond to checkForUpdatesInBackground");
        }
    }
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 003")
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 004")
    myConfigMultiUpdater = [[ConfigurationMultiUpdater alloc] init]; // Set up separate Sparkle Updaters for configurations but don't start checking yet
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 05")
    [self updateIconImage];
    [self updateMenuAndDetailsWindow];
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 06")
    
    // If we got here, we are running from /Applications (or are a debug version), so we can eject the Tunnelblick disk image
	// We want to do this before we give instructions about how to add configurations so double-clicks don't start the copy
	// of Tunnelblick.app that is on the disk image.
    if (   ( ! [gTbDefaults boolForKey: @"doNotEjectTunnelblickVolume"] )
        && [gFileMgr fileExistsAtPath: @"/Volumes/Tunnelblick/Tunnelblick.app"]  ) {
        
        // Wait until the Tunnelblick installer running from the disk image has terminated
        NSUInteger timeoutCount = 0;
        while (  [[NSApp pidsOfProcessesWithPrefix: @"/Volumes/Tunnelblick/Tunnelblick"] count] > 0 ) {
            if (  ++timeoutCount > 30  ) {
                break;
            }
            NSLog(@"Waiting for Tunnelblick installer to terminate");
            sleep(1);
        }
        if (  timeoutCount > 60  ) {
            NSLog(@"Timed out waiting for Tunnelblick installer to terminate");
        } else if (  timeoutCount != 0  ) {
            NSLog(@"Done waiting for Tunnelblick installer to terminate");
        }
        
        TBLog(@"DB-SU", @"applicationDidFinishLaunching: 06.1")
        // Eject the disk image
		NSString * outString = nil;
		NSString * errString = nil;
        NSArray * args = [NSArray arrayWithObjects: @"eject", @"/Volumes/Tunnelblick", nil];
        OSStatus status = runTool(TOOL_PATH_FOR_DISKUTIL, args, &outString, &errString);
        if (  status != 0  ) {
            NSLog(@"diskutil eject /Volumes/Tunnelblick failed with status %ld; stdout =\n%@\nstderr =\n%@", (long) status, outString, errString);
        }
    }
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 007")
    [self hookupToRunningOpenVPNs];
    [self setupHookupWatchdogTimer];
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 008")
    // Make sure the '-onSystemStart' preferences for all connections are consistent with the /Library/LaunchDaemons/...plist file for the connection
    NSEnumerator * connEnum = [[self myVPNConnectionDictionary] objectEnumerator];
    VPNConnection * connection;
    while (  (connection = [connEnum nextObject])  ) {
        if (  ! [connection tryingToHookup]  ) {
           [[self logScreen] validateWhenConnectingForConnection: connection];
        }
    }
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 009")
    activeIPCheckThreads = [[NSMutableArray alloc] initWithCapacity: 4];
    cancellingIPCheckThreads = [[NSMutableArray alloc] initWithCapacity: 4];
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 010")
	
	// Set languageAtLaunch
	CFArrayRef allLocalizationsCF = CFBundleCopyBundleLocalizations(CFBundleGetMainBundle());
	CFArrayRef languagesCF        = CFBundleCopyPreferredLocalizationsFromArray(allLocalizationsCF);
	
	NSArray  * languages = (NSArray *) languagesCF;
	id language = [[[languages objectAtIndex: 0] copy] autorelease];
	
	if (  [[language class] isSubclassOfClass: [NSString class]]  ) {
		[self setLanguageAtLaunch: [language lowercaseString]];
	} else {
		[self setLanguageAtLaunch: @"english"];
	}
    
    NSArray * rtlLanguages = [NSArray arrayWithObjects: @"ar", @"fa", nil]; // Arabic, Farsi (Persian)
	languageAtLaunchWasRTL = (   [rtlLanguages containsObject: [self languageAtLaunch]]
							  || [gTbDefaults boolForKey: @"useRtlLayout"]);
	
	CFRelease(allLocalizationsCF);
	CFRelease(languagesCF);
	
    // Maintain the selected panel index if RTL status changed from last launch
    if (   [gTbDefaults objectForKey: @"detailsWindowViewIndex"]
        && [gTbDefaults objectForKey: @"lastLanguageAtLaunchWasRTL"]  ) {
        unsigned int oldIx = [gTbDefaults unsignedIntForKey: @"detailsWindowViewIndex" default: 0 min: 0 max: 6];
        unsigned int newIx = oldIx;
        BOOL lastLanguageWasRTL = [gTbDefaults boolForKey: @"lastLanguageAtLaunchWasRTL"];
        if (  lastLanguageWasRTL  ) {
            if (  oldIx < 2  ) {
                NSLog(@"Old panel index < 2; setting it to 6");
                newIx = 6;
            }
        } else if (  oldIx > 6  ) {
            NSLog(@"Old panel index > 6; setting it to 0");
            newIx = 0;
        }
        if (  languageAtLaunchWasRTL != lastLanguageWasRTL  ) {
            newIx = 6 - newIx;
            [gTbDefaults setBool: languageAtLaunchWasRTL forKey: @"lastLanguageAtLaunchWasRTL"];
        }
        if (  newIx != oldIx) {
            [gTbDefaults setObject: [NSNumber numberWithUnsignedInt: newIx] forKey: @"detailsWindowViewIndex"];
        }
    } else {
        [gTbDefaults setBool: languageAtLaunchWasRTL forKey: @"lastLanguageAtLaunchWasRTL"];
    }
    
    // Process runOnLaunch item
    if (  customRunOnLaunchPath  ) {
		NSArray * arguments = [NSArray arrayWithObject: languageAtLaunch];
		if (  [[[customRunOnLaunchPath stringByDeletingPathExtension] pathExtension] isEqualToString: @"wait"]  ) {
			OSStatus status = runTool(customRunOnLaunchPath, arguments, nil, nil);
            if (  status != 0  ) {
                NSLog(@"Tunnelblick runOnLaunch item %@ returned %ld; Tunnelblick launch cancelled", customRunOnLaunchPath, (long)status);
                [self terminateBecause: terminatingBecauseOfError];
            }
		} else {
			startTool(customRunOnLaunchPath, arguments);
		}
    }

    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 011")
    // Process connections that should be restored on relaunch (from updating configurations)
    VPNConnection * myConnection;
    NSArray * restoreList = [gTbDefaults arrayForKey: @"connectionsToRestoreOnLaunch"];
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
    }
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 012")
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
        [gTbDefaults setBool: YES forKey: @"launchAtNextLogin"];
	}
	
    unsigned kbsIx = [gTbDefaults unsignedIntForKey: @"keyboardShortcutIndex"
                                            default: 1 /* F1     */
                                                min: 0 /* (none) */
                                                max: MAX_HOTKEY_IX];
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 013")
    [self setHotKeyIndex: kbsIx];
    
    // Install easy-rsa if it isn't installed already, or update it if appropriate
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 014")
    installOrUpdateOurEasyRsa();
    // (installOrUpdateOurEasyRsa() informs the user if there was a problem, so we don't do it here)
    
    [self setStartupInstallAuth: nil];
    
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
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 015")
    NSString * prefVersion = [gTbDefaults stringForKey: @"*-openvpnVersion"];
    if (   prefVersion
        && ( ! [prefVersion isEqualToString: @"-"] )
        && ( ! [[self openvpnVersionNames] containsObject: prefVersion] )  ) {
		NSString * useVersion = [[self openvpnVersionNames] lastObject];
        if (  [gTbDefaults canChangeValueForKey: @"*-openvpnVersion"]  ) {
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
							 [NSString stringWithFormat: NSLocalizedString(@"OpenVPN version %@ is not available. Using the latest version (%@) as the default.", @"Window text"),
							  prefVersion, useVersion]);
            NSLog(@"OpenVPN version %@ is not available. Using the latest version (%@) as the default", prefVersion, useVersion);
            [gTbDefaults setObject: @"-" forKey: @"*-openvpnVersion"];
        } else {
            NSLog(@"'*-openvpnVersion' is being forced to '%@'. That version is not available in this version of Tunnelblick", prefVersion);
        }
    }
    
    // Register this application with Launch Services
    NSString * appPath = [[NSBundle mainBundle] bundlePath];
    CFURLRef appURL = (CFURLRef) [NSURL URLWithString: [@"file://" stringByAppendingString: appPath]];
    if (  ! appURL  ) {
        NSLog(@"Unable to create URL from %@", appPath);
    } else {
        OSStatus status = LSRegisterURL(appURL, YES);
        if (  status != EXIT_SUCCESS  ) {
            NSLog(@"Unable to register %@ with Launch Services; Launch Services result code was %ld", appPath, (long) status);
        }
    }
    
/* The most common result codes returned by Launch Services functions
 
       from: http://mirror.informatimago.com/next/developer.apple.com/documentation/Carbon/Reference/LaunchServicesReference/LSRReference/ResultCodes.html#//apple_ref/doc/uid/TP30000998-CH201-BCIHFFIA
       (They don't seem to be documented on any Apple site.)
     
     kLSAppInTrashErr                   -10660 	The application cannot be run because it is inside a Trash folder.
     kLSUnknownErr                      -10810 	An unknown error has occurred.
     kLSNotAnApplicationErr             -10811 	The item to be registered is not an application.
     kLSNotInitializedErr               -10812 	Formerly returned by LSInit on initialization failure; no longer used.
     kLSDataUnavailableErr              -10813 	Data of the desired type is not available (for example, there is no kind string).
     kLSApplicationNotFoundErr          -10814 	No application in the Launch Services database matches the input criteria.
     kLSUnknownTypeErr                  -10815 	Not currently used.
     kLSDataTooOldErr                   -10816 	Not currently used.
     kLSDataErr                         -10817 	Data is structured improperly (for example, an item’s information property list is malformed).
     kLSLaunchInProgressErr             -10818 	A launch of the application is already in progress.
     kLSNotRegisteredErr                -10819 	Not currently used.
     kLSAppDoesNotClaimTypeErr          -10820 	Not currently used.
     kLSAppDoesNotSupportSchemeWarning 	-10821 	Not currently used.
     kLSServerCommunicationErr          -10822 	There is a problem communicating with the server process that maintains the Launch Services database.
     kLSCannotSetInfoErr                -10823 	The filename extension to be hidden cannot be hidden.
     kLSNoRegistrationInfoErr           -10824 	Not currently used.
     kLSIncompatibleSystemVersionErr 	-10825 	The application to be launched cannot run on the current Mac OS version.
     kLSNoLaunchPermissionErr           -10826 	The user does not have permission to launch the application (on a managed network).
     kLSNoExecutableErr                 -10827 	The executable file is missing or has an unusable format.
     kLSNoClassicEnvironmentErr         -10828 	The Classic emulation environment was required but is not available.
     kLSMultipleSessionsNotSupportedErr -10829 	The application to be launched cannot run simultaneously in two different user sessions.
*/
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 016")
    // Add this Tunnelblick version to the start of the tunnelblickVersionHistory preference array if it isn't already the first entry
    if (  tunnelblickVersionString  ) {
        BOOL dirty = FALSE;
        NSMutableArray * versions = [[[gTbDefaults arrayForKey: @"tunnelblickVersionHistory"] mutableCopy] autorelease];
        if (  ! versions  ) {
            versions = [[[NSArray array] mutableCopy] autorelease];
            dirty = TRUE;
        }
        
        if (   (  [versions count] == 0  )
            || (! [[versions objectAtIndex: 0] isEqualToString: tunnelblickVersionString])  ) {
            [versions insertObject: tunnelblickVersionString atIndex: 0];
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
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 016.1")
    // Check that the system's clock is working
    NSTimeInterval nowSinceReferenceDate = [[NSDate date] timeIntervalSinceReferenceDate];
    id obj = [gTbDefaults objectForKey: @"lastLaunchTime"];
    if (  [obj respondsToSelector: @selector(doubleValue)]  ) {
        NSTimeInterval lastLaunchedSincReferenceDate = [obj doubleValue];
        NSTimeInterval march30TwentyFourteenSinceReferenceDate = [[NSDate dateWithString: @"2014-03-30 00:00:00 +0000"] timeIntervalSinceReferenceDate];
        
        if (   (nowSinceReferenceDate > lastLaunchedSincReferenceDate)
            && (nowSinceReferenceDate > march30TwentyFourteenSinceReferenceDate)) {
            // Update lastLaunchTime
            [gTbDefaults setObject: [NSNumber numberWithDouble: nowSinceReferenceDate] forKey: @"lastLaunchTime"];
        } else {
            TBRunAlertPanelExtended(NSLocalizedString(@"Warning!", @"Window title"),
                                    NSLocalizedString(@"Your system clock may not be set correctly.\n\n"
                                                      @"Some or all of your configurations may not connect unless the system clock has the correct date and time.\n\n", @"Window text"),
                                    nil, nil, nil,
                                    @"skipWarningAboutSystemClock",
                                    NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
                                    nil,
                                    NSAlertDefaultReturn);
        }
    } else {
        // Create lastLaunchTime
        [gTbDefaults setObject: [NSNumber numberWithDouble: nowSinceReferenceDate] forKey: @"lastLaunchTime"];
    }
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 017")
    
	[self showWelcomeScreenForWelcomePath: [gDeployPath stringByAppendingPathComponent: @"Welcome"]];
	
    launchFinished = TRUE;
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 018")
    // Start installing any updatable configurations that have been downloaded but not installed
    // Or start checking for configuration updates
    // (After installing any downloaded updates, the new thread will invoke startCheckingForConfigurationUpdates)
    NSArray * updatableConfigs = [self uninstalledConfigurationUpdates];
    if (  [updatableConfigs count] != 0  ) {
        [ConfigurationManager installConfigurationsInNewThreadShowMessagesDoNotNotifyDelegateWithPaths: updatableConfigs];
    } else {
        [self startCheckingForConfigurationUpdates];
    }
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 019")
    // Start installing any configurations that were double-clicked before we were finished launching
    if (  [dotTblkFileList count] != 0  ) {
        [self notifyDelegateAfterInstallingConfigurationsInPaths: dotTblkFileList];
    }
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 020")

	if (  runningOnMountainLionOrNewer()) {
		
		// The following lines are the equivalent of
		//
		//     [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate: self];
		//
		// but they build without error on Xcode 3.2.2, whose SDK does not define NSNotificationCenter. They also
		// implement some addional error checking.
		
		id nsuncClass = NSClassFromString(@"NSUserNotificationCenter");
		if (  ! nsuncClass) {
			NSLog(@"No result from 'NSClassFromString(@\"NSUserNotificationCenter\")'");
			[self terminateBecause: terminatingBecauseOfError];
		}
		if (  ! [nsuncClass respondsToSelector: @selector(defaultUserNotificationCenter)]  ) {
			NSLog(@"NSUserNotificationCenter does not respond to 'defaultUserNotificationCenter'");
			[self terminateBecause: terminatingBecauseOfError];
		}
		id center = [nsuncClass performSelector: @selector(defaultUserNotificationCenter)];
		if (  ! center) {
			NSLog(@"No result from [NSUserNotificationCenter defaultUserNotificationCenter]");
			[self terminateBecause: terminatingBecauseOfError];
		}
		if (  ! [center respondsToSelector: @selector(setDelegate:)]  ) {
			NSLog(@"[NSUserNotificationCenter defaultUserNotificationCenter] does not respond to 'setDelegate:'");
			[self terminateBecause: terminatingBecauseOfError];
		}
		[center performSelector: @selector(setDelegate:) withObject: self];
	}
    
    if (  [gTbDefaults boolForKey: @"haveStartedAnUpdateOfTheApp"]  ) {
        [gTbDefaults removeObjectForKey: @"haveStartedAnUpdateOfTheApp"];
        NSString * tbVersion = [[self tunnelblickInfoDictionary] objectForKey: @"CFBundleShortVersionString"];
        NSString * message = [NSString stringWithFormat: NSLocalizedString(@"Updated to %@.", "Notification text"), tbVersion];
        [UIHelper showSuccessNotificationTitle: @"Tunnelblick" msg: message];
    }
    
    if (  [dotTblkFileList count] == 0  ) {
        [self checkNoConfigurations];
    }
    
    if (   ( ! mustPlaceIconInStandardPositionInStatusBar() )
        && ( ! [gTbDefaults boolForKey: @"placeIconInStandardPositionInStatusBar"] )
        && ( shouldPlaceIconInStandardPositionInStatusBar() )
        ) {
        [self showConfirmIconNearSpotlightIconDialog];
    }
    
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 021")
	NSString * text = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick %@ is ready.", @"Window text; '%@' will be replaced with a version number such as '3.6.10'"), [self tunnelblickVersionString]];
	[splashScreen setMessage: text];
    [splashScreen fadeOutAndClose];
 
    TBLog(@"DB-SU", @"applicationDidFinishLaunching: 022 -- LAST")
}

-(BOOL) userNotificationCenter: (id) center
     shouldPresentNotification: (id) notification {
    
	// This implements
	//		-(BOOL) userNotificationCenter: (NSUserNotificationCenter *) center
	//			 shouldPresentNotification: (NSUserNotification *)       notification {
	// in a way that builds on Xcode 3.2.2, which does not include NSUserNotification or NSUserNotificationCenter
	// because they were introduced in OS X 10.8
	
    (void) center;
    (void) notification;
    
    return YES;
}

-(NSString *) fileURLStringWithPath: (NSString *) path
{
    NSString * urlString = [@"file://" stringByAppendingString: path];
    return urlString;
}

-(BOOL) showWelcomeScreenForWelcomePath: (NSString *) welcomePath {
    
    // Shows localized welcome screen from the bundle at the specified path (do not include the ".bundle") if available,
	// otherwise shows non-localized welcome screen from the specified path if available,
	// else shows welcome screen specified in welcomeURL forced preference
	
	// Returns TRUE if the screen was shown; FALSE otherwise
	
	if (  [gTbDefaults boolForKey: @"skipWelcomeScreen"]  ) {
		return FALSE;
	}
	
    NSString * welcomeURLString = nil;
    NSBundle * welcomeBundle = [NSBundle bundleWithPath: [welcomePath stringByAppendingPathExtension: @"bundle"]];
    if (   welcomeBundle  ) {
        NSArray * preferredLanguagesList = [welcomeBundle preferredLocalizations];
        if (  [preferredLanguagesList count] < 1  ) {
            NSLog(@"Unable to get preferred localization for %@", [welcomeBundle bundlePath]);
			return FALSE;
        }
        NSString * preferredLanguage = [preferredLanguagesList objectAtIndex: 0];
        NSString * welcomeIndexHtmlPath = [[[[[welcomeBundle bundlePath]
                                              stringByAppendingPathComponent: @"Contents"]
                                             stringByAppendingPathComponent: @"Resources"]
                                            stringByAppendingPathComponent: [preferredLanguage stringByAppendingPathExtension: @"lproj"]]
                                           stringByAppendingPathComponent: @"index.html"];
		if (  ! [gFileMgr fileExistsAtPath: welcomeIndexHtmlPath]  ) {
            NSLog(@"Unable to show Welcome window because file does not exist at %@", welcomeIndexHtmlPath);
			return FALSE;
		}
        welcomeURLString = [@"file://" stringByAppendingString: welcomeIndexHtmlPath];
        
    } else {
        NSString * welcomeIndexHtmlPath = [welcomePath stringByAppendingPathComponent: @"index.html"];
		if (  [gFileMgr fileExistsAtPath: welcomeIndexHtmlPath]  ) {
			welcomeURLString = [@"file://" stringByAppendingString: welcomeIndexHtmlPath];
		} else {
			if (  ! [gTbDefaults canChangeValueForKey: @"welcomeURL"]  ) {
				welcomeURLString = [gTbDefaults stringForKey: @"welcomeURL"];
			}
		}
	}
	
	if (  ! welcomeURLString  ) {
		return FALSE;
	}
    
    float welcomeWidth = [gTbDefaults floatForKey: @"welcomeWidth"
                                          default: 500.0
                                              min: 100.0
                                              max: 2500.0];
    
    float welcomeHeight = [gTbDefaults floatForKey: @"welcomeheight"
                                           default: 500.0
                                               min: 100.0
                                               max: 2500.0];
    
    BOOL showCheckbox = ! [gTbDefaults boolForKey: @"doNotShowWelcomeDoNotShowAgainCheckbox"];
	
    welcomeScreen = [[[WelcomeController alloc]
					  initWithDelegate:           self
					  urlString:                  welcomeURLString
					  windowWidth:                welcomeWidth
					  windowHeight:               welcomeHeight
					  showDoNotShowAgainCheckbox: showCheckbox]
                     retain];
	
	[welcomeScreen showWindow: self];
    
    return TRUE;
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
    if (  gHookupTimeout == 0  ) {
		noUnknownOpenVPNsRunning = ([[NSApp pIdsForOpenVPNProcessesOnlyMain: YES] count] == 0);
        return FALSE;
    }
    
    [self setHookupWatchdogTimer: [NSTimer scheduledTimerWithTimeInterval: (NSTimeInterval) gHookupTimeout
                                                                   target: self
                                                                 selector: @selector(hookupWatchdogHandler)
                                                                 userInfo: nil
                                                                  repeats: NO]];
    [hookupWatchdogTimer tbSetTolerance: -1.0];
    return TRUE;
}

-(void) hookupWatchdogHandler
{
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    [self setHookupWatchdogTimer: nil];
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
               NSLog(@"Ignoring error/cancel return from TBRunAlertPanelExtended; not killing unknown OpenVPN processes");
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
               NSLog(@"Ignoring error/cancel return from TBRunAlertPanelExtended; not killing unknown OpenVPN processes");
               return;
           }
       } else {
		   TBShowAlertWindow(NSLocalizedString(@"Warning: Unknown OpenVPN processes", @"Window title"),
							 NSLocalizedString(@"One or more OpenVPN processes are running but are unknown"
											   @" to Tunnelblick. If you are not running OpenVPN separately"
											   @" from Tunnelblick, this usually means that an earlier"
											   @" launch of Tunnelblick was unable to shut them down"
											   @" properly and you should terminate them. They are likely"
											   @" to interfere with Tunnelblick's operation.\n\n"
											   @"They can be terminated in the 'Activity Monitor' application.\n\n", @"Window text"));
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
    }
}

-(void) setPreferenceForSelectedConfigurationsWithKey: (NSString *) key
                                                   to: (id)         newValue
                                               isBOOL: (BOOL)       isBOOL {
    if (   key
        && newValue  ) {
		
        (void) isBOOL;
        
        ConfigurationsView      * cv     = [[self logScreen] configurationsPrefsView];
        LeftNavViewController   * ovc    = [cv outlineViewController];
        NSOutlineView           * ov     = [ovc outlineView];
        NSIndexSet              * idxSet = [ov selectedRowIndexes];
        
        if  (  [idxSet count] != 0  ) {
            
            // The Xcode 3.2 analyzer cannot deal with blocks, so to analyze (the rest of) MenuController, we don't compile the one section of code that has a block
#ifdef TBAnalyzeONLY
#warning "NOT AN EXECUTABLE -- ANALYZE ONLY but does not fully analyze code in setPreferenceForSelectedConfigurationsWithKey:to:isBool:"
            (void) idxSet;
#else
            [idxSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
                (void) stop;
                
                LeftNavItem * item = [ov itemAtRow: idx];
                NSString * displayName = [item displayName];
                if (  [displayName length] != 0  ) {	// Ignore folders; just process configurations
                    NSString * actualKey = [displayName stringByAppendingString: key];
                    [gTbDefaults setObject: newValue forKey: actualKey];
                }
            }];
#endif
        } else {
            NSLog(@"setPreferenceForSelectedConfigurationsWithKey: No configuration is selected so cannot change the '%@' preference", key);
        }
	} else {
        NSLog(@"setPreferenceForSelectedConfigurationsWithKey: Key and value for the preference were not provided");
    }
}

-(void) setBooleanPreferenceForSelectedConnectionsWithKey: (NSString *)	key
													   to: (BOOL)		newValue
												 inverted: (BOOL)		inverted {
    
    // This is invoked directly when a checkbox is clicked, so we check we are not doing setup of UI here
	
    if ( ! [((MenuController *)[NSApp delegate]) doingSetupOfUI]  ) {
		
		BOOL state = (  inverted
					  ? ! newValue
					  : newValue);
		
		[self setPreferenceForSelectedConfigurationsWithKey: key to: [NSNumber numberWithBool: state] isBOOL: true];
	}
}

-(void) setPreferenceForSelectedConfigurationsWithDict: (NSDictionary * ) dict {
    
	// This is invoked by performSelectorOnMainThread after checking that we are not doing setup of UI, so we don't check here
    
	NSString * key   = [dict objectForKey: @"PreferenceName"];
    id         value = [dict objectForKey: @"NewValue"];
    
	[self setPreferenceForSelectedConfigurationsWithKey: key to: value isBOOL: NO];
}

-(void) setPIDsWeAreTryingToHookUpTo: (NSArray *) newValue
{
    if (  pIDsWeAreTryingToHookUpTo != newValue) {
        [pIDsWeAreTryingToHookUpTo release];
        pIDsWeAreTryingToHookUpTo = [newValue mutableCopy];
    }
}

static BOOL runningHookupThread = FALSE;

-(void) hookupToRunningOpenVPNs {
    // This method starts a thread that tries to "hook up" to any running OpenVPN processes.
    //
    // Before doing that, it waits until no "openvpnstart" processes exist. This avoids the situation
    // of Tunnelblick looking for OpenVPN processes before they have been successfully started.
    //
    // (If no OpenVPN processes exist, there's nothing to hook up to, so we skip all this)
    //
    // It searches for files in the log directory with names of A.B.C.openvpn.log, where
    // A is the path to the configuration file (with -- instead of dashes and -/ instead of slashes)
    // B is the arguments that openvpnstart was invoked with, separated by underscores
    // C is the management port number
    // The file contains the OpenVPN log.
    //
    // The [connection tryToHookup:] method corresponding to the configuration file is used to set
    // the connection's port # and initiate communications to get the process ID for that instance of OpenVPN
    //
    // Returns TRUE if started trying to hook up to one or more running OpenVPN processes
    
    // The following mutex is used to protect 'runningHookupThread', which protects against running more than one hookupToRunningOpenVPNsThread
    static pthread_mutex_t hookupToRunningOpenVPNsMutex = PTHREAD_MUTEX_INITIALIZER;
    
    OSStatus status = pthread_mutex_lock( &hookupToRunningOpenVPNsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &hookupToRunningOpenVPNsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    
    if (  runningHookupThread  ) {
        status = pthread_mutex_unlock( &hookupToRunningOpenVPNsMutex );
        if (  status != EXIT_SUCCESS  ) {
            NSLog(@"pthread_mutex_unlock( &hookupToRunningOpenVPNsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
            return;
        }
        NSLog(@"hookupToRunningOpenVPNs: already running a thread to do that");
        return;
    }
    
    runningHookupThread = TRUE;
    
    status = pthread_mutex_unlock( &hookupToRunningOpenVPNsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &hookupToRunningOpenVPNsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    
    [NSThread detachNewThreadSelector: @selector(hookupToRunningOpenVPNsThread) toTarget: self withObject: nil];
}

-(void) hookupToRunningOpenVPNsThread {
	
	NSAutoreleasePool * threadPool = [NSAutoreleasePool new];
    
    // Sleep for a while to give openvpnstart processes time to be launched by launchd at computer start
    unsigned sleepTime = [gTbDefaults unsignedIntForKey: @"delayBeforeCheckingForOpenvpnstartProcesses"
                                                default: 1
                                                    min: 0
                                                    max: UINT_MAX];
    TBLog(@"DB-HU", @"hookupToRunningOpenVPNs: Delaying %lu seconds before checking for openvpnstart processes. Change"
          @" this time with the \"delayBeforeCheckingForOpenvpnstartProcesses\" preference", (unsigned long)sleepTime)
    if (  sleepTime != 0  ) {
        sleep(sleepTime);
    }
    
    // Update the Tunnelblick icon
    [self performSelectorOnMainThread: @selector(setState:) withObject: nil waitUntilDone: NO];
    
    // Wait until there are no "openvpnstart" processes running
    unsigned waitTime = [gTbDefaults unsignedIntForKey: @"timeToSpendCheckingForOpenvpnstartProcesses"
                                               default: 30
                                                   min: 0
                                                   max: UINT_MAX];
    if (  ! [NSApp wait: waitTime untilNoProcessNamed: @"openvpnstart"]  ) {
        TBLog(@"DB-HU", @"hookupToRunningOpenVPNs: timed out after %lu seconds waiting for openvpnstart processes to terminate; will start trying to hook up to OpenVPN processes anyway. Change"
              @" this time with the \"timeToSpendCheckingForOpenvpnstartProcesses\" preference", (unsigned long)waitTime)
    } else {
        TBLog(@"DB-HU", @"hookupToRunningOpenVPNs: no openvpnstart processes running")
    }
    
    // Get a list of running OpenVPN processes
    [self setPIDsWeAreTryingToHookUpTo: [NSApp pIdsForOpenVPNProcessesOnlyMain: YES]];
    TBLog(@"DB-HU", @"hookupToRunningOpenVPNs: pIDsWeAreTryingToHookUpTo = '%@'", pIDsWeAreTryingToHookUpTo)
    
    if (  [pIDsWeAreTryingToHookUpTo count] != 0  ) {

        // Search for the latest log file for each imbedded configuration displayName
        
        NSMutableDictionary * logFileInfo = [[NSMutableDictionary alloc] initWithCapacity: 100];
        // logFileInfo key = displayName; object = NSDictionary with info about the log file for that display name
        NSString * filename;
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: L_AS_T_LOGS];
        while (  (filename = [dirEnum nextObject])  ) {
            [dirEnum skipDescendents];
            NSString * oldFullPath = [L_AS_T_LOGS stringByAppendingPathComponent: filename];
            if (  [[filename pathExtension] isEqualToString: @"log"]) {
                if (  [[[filename stringByDeletingPathExtension] pathExtension] isEqualToString: @"openvpn"]) {
                    NSDate * thisFileDate = [[gFileMgr tbFileAttributesAtPath: oldFullPath traverseLink: NO] fileCreationDate];
                    TBLog(@"DB-HU", @"hookupToRunningOpenVPNs: found OpenVPN log file '%@' created %@", filename, thisFileDate)
                    unsigned port = 0;
                    NSString * openvpnstartArgs = nil;
                    NSString * cfgPath = [self deconstructOpenVPNLogPath: oldFullPath
                                                                  toPort: &port
                                                             toStartArgs: &openvpnstartArgs];
                    NSString * displayName = displayNameFromPath(cfgPath);
					if (  displayName  ) {
						VPNConnection * connection = [myVPNConnectionDictionary objectForKey: displayName];
						if (  connection  ) {
							NSDictionary * bestLogInfoSoFar = [logFileInfo objectForKey: displayName];
							if (   (! bestLogInfoSoFar)
								|| (  [thisFileDate isGreaterThan: [bestLogInfoSoFar objectForKey: @"fileCreationDate"]])  ) {
								NSDictionary * newEntry = [NSDictionary dictionaryWithObjectsAndKeys:
														   thisFileDate,                    @"fileCreationDate",
														   openvpnstartArgs,                @"openvpnstartArgs",
														   [NSNumber numberWithInt: port],  @"port",
														   connection,                      @"connection",
														   nil];
								[logFileInfo setObject: newEntry forKey: displayName];
								TBLog(@"DB-HU", @"hookupToRunningOpenVPNs: file is the best so far for '%@'", displayName)
							} else {
								TBLog(@"DB-HU", @"hookupToRunningOpenVPNs: file is not the best so far for '%@'; skipping it", displayName)
							}
						} else {
							TBLog(@"DB-HU", @"hookupToRunningOpenVPNs: no configuration available for '%@' -- ignoring '%@'", displayName, filename)
						}
					} else {
						TBLog(@"DB-HU", @"hookupToRunningOpenVPNs: could not extract displayName from '%@' -- ignoring '%@'", cfgPath, filename)
					}
				} else {
					TBLog(@"DB-HU", @"hookupToRunningOpenVPNs: not an OpenVPN log file -- ignoring '%@'", filename)
				}
			} else {
				TBLog(@"DB-HU", @"hookupToRunningOpenVPNs: not a log file -- ignoring '%@'", filename)
			}
		}
        
        TBLog(@"DB-HU", @"hookupToRunningOpenVPNs: logFileInfo = %@", logFileInfo)
        
        // Now try to hook up to the OpenVPN process for the latest log file for each displayName
        NSString * displayName;
        NSEnumerator * e = [logFileInfo keyEnumerator];
		unsigned nQueued = 0;
        while (  (displayName = [e nextObject])  ) {
            NSDictionary  * entry = [logFileInfo objectForKey: displayName];
			NSNumber      * portAsNumber   = [entry objectForKey: @"port"];
            NSString      * startArguments = [entry objectForKey: @"openvpnstartArgs"];
			VPNConnection * connection     = [entry objectForKey: @"connection"];
            
            TBLog(@"DB-HU", @"hookupToRunningOpenVPNs: queueing hook up of '%@' using port %lu", displayName, (unsigned long)[portAsNumber intValue])
            
            NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                   portAsNumber,   @"port",
                                   startArguments, @"openvpnstartArgs",
                                   nil];
            [connection performSelectorOnMainThread: @selector(tryToHookup:)  withObject: dict waitUntilDone: NO];
			nQueued++;
        }
		
		[logFileInfo release];
		
        TBLog(@"DB-HU", @"hookupToRunningOpenVPNs: finished queueing %lu hookups for %lu OpenVPN processes", (unsigned long)nQueued, (unsigned long)[pIDsWeAreTryingToHookUpTo count])
    }
    
    runningHookupThread = FALSE;
    
	[threadPool drain];
    return;
}

// Returns a configuration path (and port number and the starting arguments from openvpnstart) from a path created by openvpnstart
-(NSString *) deconstructOpenVPNLogPath: (NSString *)   logPath
								 toPort: (unsigned *)   portPtr
							toStartArgs: (NSString * *) startArgsPtr
{
    NSString * prefix = L_AS_T_LOGS @"/";       // Compiler concatenates the two strings
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
					if (  startArgsPtr  ) {
						*startArgsPtr = startArguments;
					}
                }
            }
            NSString * portString = [withoutPrefixOrDotOpenvpnDotLog pathExtension];
            int port = [portString intValue];
            if (   (port != 0)
                && (port != INT_MAX)
                && (port != INT_MIN)  ) {
                
				if (  portPtr  ) {
					*portPtr = (unsigned)port;
                }
				
				NSString * constructedPath = [withoutPrefixOrPortOrOpenvpnDotLog stringByDeletingPathExtension];
				NSMutableString * cfg = [[NSMutableString alloc] initWithCapacity: [constructedPath length]];
				unsigned i;
				for (  i=0; i<[constructedPath length]; i++  ) {
					char c = [constructedPath characterAtIndex: i];
					if (  c == '-'  ) {
						i++;
						c = [constructedPath characterAtIndex: i];
						if (  c == '-'  ) {
							[cfg appendString: @"-"];
						} else if (  c == 'S'  ) {
							[cfg appendString: @"/"];
						} else {
							NSLog(@"deconstructOpenVPNLogPath: invalid log path string has '-%c' (0x%02X) at position %lu in '%@'", c, (unsigned) c, (unsigned long) i, constructedPath);
							[((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
						}
					} else {
						[cfg appendFormat: @"%c", c];
					}
				}
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
		NSString * tooBigMsg = allFilesAreReasonableIn(gPrivatePath);
        if (  tooBigMsg  ) {
            int result = TBRunAlertPanel(NSLocalizedString(@"Warning", @"Window title"),
                                         [NSString stringWithFormat:
										  NSLocalizedString(@"You have OpenVPN configurations.\n\n"
															@"The OpenVPN configurations must be converted to Tunnelblick VPN Configurations if you want to use them.\n\n"
															@"However, Tunnelblick cannot convert them because there was a problem:\n\n"
															@"%@\n\n"
															@"If you choose 'Ignore' the configurations will not be available!\n\n", @"Window text"),
										  tooBigMsg],
                                         NSLocalizedString(@"Ignore", @"Button"),    // Default
                                         NSLocalizedString(@"Quit", @"Button"),      // Alternate
                                         nil);
            if (  result == NSAlertAlternateReturn  ) {
                [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfQuit];
            }
            
            gUserWasAskedAboutConvertNonTblks = YES;
            gOkToConvertNonTblks = NO;
            return NO;
        }

		int response = TBRunAlertPanelExtended(NSLocalizedString(@"VPN Configuration Installation", @"Window title"),
											   NSLocalizedString(@"You have one or more OpenVPN configurations that will not be available"
                                                                 @" when using this version of Tunnelblick. You can:\n\n"
																 @"  • Let Tunnelblick convert these OpenVPN configurations to Tunnelblick VPN Configurations; or\n"
                                                                 @"  • Quit and install a different version of Tunnelblick; or\n"
                                                                 @"  • Ignore this and continue without converting.\n\n"
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
            || (response == NSAlertErrorReturn)  ) {  // Quit if "Quit" or error/cancel
			[((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfQuit];
            return NO;
		} else if (  response == NSAlertDefaultReturn  ) {
			return YES;
		}
        
        response = TBRunAlertPanel(NSLocalizedString(@"VPN Configuration Installation", @"Window title"),
								   NSLocalizedString(@"Are you sure you do not want to convert OpenVPN configurations to Tunnelblick VPN Configurations?\n\n"
													 @"CONFIGURATIONS WILL NOT BE AVAILABLE IF YOU DO NOT CONVERT THEM!\n\n", @"Window text"),
								   NSLocalizedString(@"Convert Configurations", @"Button"), // Default return
								   NSLocalizedString(@"Ignore", @"Button"),                 // Alternate return
								   NSLocalizedString(@"Quit", @"Button"));                  // Other return
		if (  response == NSAlertOtherReturn  ) {
			[((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfQuit];
		}
		
		if (  response == NSAlertDefaultReturn  ) {
			return YES;
		}
        
        // "Ignore" or error/cancelled : fall through to ignore
	}
	
	return NO;
}

-(void) checkSystemFolder: (NSString *) folderPath {
    
    // Check existence, ownership, and permissions of a system folder. Complain and quit if it does not exist or is not secure.
    
    if (  ! [gFileMgr fileExistsAtPath: folderPath]  ) {
        NSLog(@"%@ does not exist.", folderPath);
        TBRunAlertPanel(NSLocalizedString(@"System Requirements Not Met", @"Window title"),
                        [NSString stringWithFormat: NSLocalizedString(@"The %@ system folder (%@) does not exist.", @"Window text"),
                         [gFileMgr displayNameAtPath: folderPath], folderPath],
                        NSLocalizedString(@"Quit", @"Button"), nil, nil);
        [self terminateBecause: terminatingBecauseOfError];
    }
    
    // The tests here are the same tests used in openvpnstart's "pathComponentIsNotSecure" function.
    
    BOOL isBad = TRUE;
    
    NSDictionary * attributes = [gFileMgr tbFileAttributesAtPath: folderPath traverseLink: NO];
    if (  attributes  ) {
        if (  [attributes fileType] != NSFileTypeSymbolicLink  ) {
            unsigned long owner = [[attributes objectForKey: NSFileOwnerAccountID] unsignedLongValue];
            if (  owner == 0  ) {
                unsigned long groupOwner = [[attributes objectForKey: NSFileGroupOwnerAccountID] unsignedLongValue];
                if (   (groupOwner == 0)
                    || (groupOwner == ADMIN_GROUP_ID)  ) {
                    mode_t perms = (mode_t) [[attributes objectForKey: NSFilePosixPermissions] shortValue];
                    if (  (perms & S_IWOTH) == 0   ) {
                        isBad = FALSE;
                    } else {
                        NSLog(@"%@ is writable by other (permissions = 0%lo)", folderPath, (long) perms);
                    }
                } else {
                    NSLog(@"The group owner of %@ is %ld, not 0 or %ld", folderPath, groupOwner, (long) ADMIN_GROUP_ID);
                }
            } else {
                NSLog(@"The owner of %@ is %ld, not 0", folderPath, owner);
            }
        } else {
            NSLog(@"%@ is a symlink", folderPath);
        }
    } else {
        NSLog(@"%@ does not have attributes (!)", folderPath);
    }
    
    if (  isBad  ) {
        
        NSLog(@"%@ is not secure", folderPath);
        
        int result = TBRunAlertPanel(NSLocalizedString(@"System Requirements Not Met", @"Window title"),
                                     [NSString stringWithFormat: NSLocalizedString(@"The %@ system folder (%@) is not secure.\n\n"
																				   @"Tunnelblick may not work properly unless this is fixed.\n\n"
																				   @"Disk Utility's 'Repair Disk Permissions' function may be able to repair the problem.", @"Window text"),
									  [gFileMgr displayNameAtPath: folderPath], folderPath],
                                     NSLocalizedString(@"Quit", @"Button"),
                                     NSLocalizedString(@"Help", @"Button"),
									 NSLocalizedString(@"Continue", @"Button"));
        if (  result == NSAlertAlternateReturn  ) {
            MyGotoHelpPage(@"system-folder-not-secure.html", nil);
        }
		
        if (  result == NSAlertDefaultReturn  ) {
			[self terminateBecause: terminatingBecauseOfError];
        }
    }
}

-(void) checkSystemFoldersAreSecure {
    
    // Check that the folders Tunnelblick uses exist and are secure; quit if they don't.
    
    [self checkSystemFolder: @"/Applications"];
    [self checkSystemFolder: @"/Library"];
    [self checkSystemFolder: @"/Library/Application Support"];
    [self checkSystemFolder: @"/Users"];
    [self checkSystemFolder: @"/usr"];
    [self checkSystemFolder: @"/usr/bin"];
    [self checkSystemFolder: @"/usr/sbin"];
    [self checkSystemFolder: @"/sbin"];
}

-(void) initialChecks: (NSString *) ourAppName
{
    TBLog(@"DB-SU", @"initialChecks: 001")
    [gTbDefaults setBool: NO forKey: @"launchAtNextLogin"];
    
    [self checkSystemFoldersAreSecure];
    
    TBLog(@"DB-SU", @"initialChecks: 002")
#ifdef TBDebug
	(void) ourAppName;
#else
	if (  tunnelblickTestDeployed()  ) {
		NSDictionary * bundleInfoDict = [self tunnelblickInfoDictionary];
		if (  ! bundleInfoDict  ) {
			TBRunAlertPanel(NSLocalizedString(@"System Requirements Not Met", @"Window title"),
							NSLocalizedString(@"This 'Deployed' version of Tunnelblick cannot be launched or installed because it"
											  @" does not have an Info.plist.\n\n", @"Window text"),
							nil,nil,nil);
			[self terminateBecause: terminatingBecauseOfQuit];
		}
		
		NSString * ourBundleIdentifier = [bundleInfoDict objectForKey: @"CFBundleIdentifier"];
		
		NSString * ourUpdateFeedURLString = [self feedURLToUse];
		
		NSString * ourExecutable = [bundleInfoDict objectForKey: @"CFBundleExecutable"];
		
        // PLEASE DO NOT REMOVE THE FOLLOWING REBRANDING CHECKS!
        //
        // Running a Deployed version of Tunnelblick without rebranding it can lead to unpredictable behavior,
        // may be less secure, can lead to problems with updating, and can interfere with other installations
        // of Tunnelblick on the same computer. Please don't do it!
        //
        // For instructions on rebranding Tunnelblick, see https://tunnelblick.net/cRebranding.html
        
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
	
    TBLog(@"DB-SU", @"initialChecks: 003")
    // If necessary, warn that non-.tblks will be converted
	gOkToConvertNonTblks = warnAboutNonTblks();
    
    TBLog(@"DB-SU", @"initialChecks: 004")
    // If necessary, (re)install Tunnelblick in /Applications
    [self relaunchIfNecessary];  // (May not return from this)
    
    TBLog(@"DB-SU", @"initialChecks: 005")
	[self secureIfNecessary];
    TBLog(@"DB-SU", @"initialChecks: 006 - LAST")
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
																   @" Check with the provider of this copy of Tunnelblick before"
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

-(BOOL) userAcceptedUserAgreement {
	
	// Returns YES if user agreed to this version of the User Agreement or has already agreed to it
	// Returns NO if user does not agree
	
	// if a fresh install, ask the user if Tunnelblick should check for updates and check for IP address changes, and sets preferences accordingly

	BOOL askCheckForQuestions = (  ! [gTbDefaults preferenceExistsForKey: @"tunnelblickVersionHistory"]  );

	NSString * userAgreementVersionAgreedTo = [gTbDefaults stringForKey: @"userAgreementVersionAgreedTo"];
	NSString * thisUserAgreementVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"UserAgreementVersion"];
	BOOL userAgreementChanged = ! [thisUserAgreementVersion isEqualTo: userAgreementVersionAgreedTo];
	
	if (   ( ! askCheckForQuestions )
		&& ( ! userAgreementChanged )  ) {
		return YES;
	}
	
	BOOL rebranded = (  ! [@"Tunnelblick" isEqualToString: @"Tu" @"nne" @"lb" @"li" @"ck"]  );
	
	NSString *acceptString = NSLocalizedString(@"I accept and agree to the above", @"Checkbox text");
	NSArray * checkboxLabels = (  askCheckForQuestions
								? [NSArray arrayWithObjects:
								   NSLocalizedString(@"Check for updates",				  @"Checkbox text"),
								   NSLocalizedString(@"Check for IP address changes",     @"Checkbox text"),
								   acceptString,
								   nil]
								: [NSArray arrayWithObject: acceptString]);
	
	NSArray * checkboxResults = (  askCheckForQuestions
								 ? [NSArray arrayWithObjects:
									[NSNumber numberWithBool: YES],
									[NSNumber numberWithBool: YES],
									[NSNumber numberWithBool: NO],
									nil]
								 : [NSArray arrayWithObject: [NSNumber numberWithBool: NO]]);
	
	NSString * windowTitle = (  askCheckForQuestions
							  ? NSLocalizedString(@"Welcome to Tunnelblick", @"Window title")
							  : NSLocalizedString(@"Tunnelblick Update", @"Window title"));
	
	NSString * rebrandingSentence = (  rebranded
									 ? @"Tunnelblick is based on Tu" @"nn" @"elbl" @"ick.\n\n"
									 : @"");
	
	NSURL * registerURL = [NSURL URLWithString: [[NSBundle mainBundle] objectForInfoDictionaryKey: @"RegistrationURL"]];
	NSString * registrationHost = [registerURL host];
	
	NSString * message = [NSString stringWithFormat: NSLocalizedString(@"%@Tu" @"nn" @"elbl" @"ick is free software: you can use it, redistribute it, and/or modify"
																	   @" it under the terms of the GNU General Public License version 2 as published"
																	   @" by the Free Software Foundation.\n\n"
																	   
																	   @"Tu" @"nn" @"elbl" @"ick is provided for free, as is, and without warranty of any kind."
																	   @" Tu" @"nn" @"elbl" @"ick and it's authors assume no liability or responsibility for damages"
																	   @" resulting from the use of Tu" @"nn" @"elbl" @"ick, or of any third-party modifications to"
																	   @" Tu" @"nn" @"elbl" @"ick. See the GNU General Public License version 2 for details.\n\n"
																	   
																	   @"If you accept and agree to these terms, your response will be sent to %@ anonymously and"
																	   @" you will be asked for authorization so Tunnelblick can be securely installed or updated.",
																	   
																	   @"Window text. The first %@ may be replaced by a sentence. The second %@ will be replaced by an"
																	   @" Internet address like 'tunnelblick .net'."),
						  rebrandingSentence,registrationHost];
	
	NSMutableString * moreInfo = [[[NSMutableString alloc] initWithString:
								   [NSString stringWithFormat: NSLocalizedString(@"To use Tunnelblick, you must indicate your acceptance of and agreement to the specified terms by putting"
																				 @" a check in the \"I accept and agree to the above\" checkbox.\n\n"
																				 
																				 @"If you do that and click \"Continue\", %@ will be accessed anonymously in accordance with the"
																				 @" Tu" @"nn" @"elbl" @"ick Privacy Policy and you will be able to install, update and use Tunnelblick.\n\n"
																				 
																				 @"If you do not, you cannot install, update, or use Tunnelblick.\n\n\n",
																				 
																				 @"Window text. The %@ is an Internet address like 'tunnelblick .net'"),
									registrationHost]]
								  autorelease];
	
	if (  askCheckForQuestions  ) {
		NSString * updateCheckHost = (  rebranded
									  ? [[NSURL URLWithString: [[NSBundle mainBundle] objectForInfoDictionaryKey: @"SUFeedURL"]] host]
									  : @"tu" @"nne" @"lbli" @"ck." @"net");
		NSString * ipCheckHost     = (  rebranded
									  ? [[NSURL URLWithString: [[NSBundle mainBundle] objectForInfoDictionaryKey: @"IPCheckURL"]] host]
									  : @"tu" @"nne" @"lbli" @"ck." @"net");
		
		[moreInfo appendString: [NSString stringWithFormat: NSLocalizedString(@"If \"Check for updates\" is checked, Tunnelblick will access %@"
																			  @" to check for updates when it is launched and periodically while running. You may change"
																			  @" this setting later.\n\n"
																			  
																			  @"If \"Check for IP address changes\" is checked, Tunnelblick will access %@"
																			  @" to determine the computer's apparent public IP address before and after a VPN is connected"
																			  @" and warn if the IP address does not change. You may change this setting later.\n\n\n",
																			  @"Window text. The two %@ are Internet addresses like 'tunnelblick .net'"),
								 updateCheckHost, ipCheckHost]];
	}
	
	[moreInfo appendString: NSLocalizedString(@"License:\n     https://www.gnu.org/licenses/gpl-2.0.html\n"
											  @"Free Software Foundation:\n     https://fsf.org\n"
											  @"Tu" @"nn" @"elbl" @"ick Privacy Policy:\n     https://tu" @"nne" @"lbli" @"ck." @"net/privacy.html\n\n",
											  @"Window text")];
	
	// Ask if user agrees to terms
	int button;
	BOOL keepAsking = YES;
	while (  keepAsking  ) {

		button = TBRunAlertPanelExtendedPlus(windowTitle,
											 message,
											 NSLocalizedString(@"Continue",		@"Button"), // Default button
											 NSLocalizedString(@"More Info...", @"Button"),	// Alternate button
											 NSLocalizedString(@"Cancel",		@"Button"), // Other button
											 nil, checkboxLabels, &checkboxResults, FALSE, nil, nil);
		
		
		if (  button == NSAlertAlternateReturn) {	// More Info button; show more info then repeat asking for agreement
			TBRunAlertPanel(NSLocalizedString(@"Tunnelblick Installation or Update", @"Window title"), moreInfo, nil, nil, nil); // Only an "OK" button
		} else {
			keepAsking = NO;
		}
	}
	
	// If didn't agree to the User Agreement, return NO
	NSInteger agreeIndex = (  askCheckForQuestions
							? 2
							: 0);
	if (  [[checkboxResults objectAtIndex: agreeIndex] isEqualTo: [NSNumber numberWithBool: NO]]  ) {
		return NO;
	}
	
	// If cancelled, return NO
	if (  button != NSAlertDefaultReturn  ) {
		return NO;
	}
	
	NSLog(@"The user agreed to the terms and conditions version %@", thisUserAgreementVersion);
	
	// Set up preferences if the user answered questions about them
	
	BOOL checkForUpdates = (  askCheckForQuestions
							? [[checkboxResults objectAtIndex: 0] boolValue]
							: [gTbDefaults boolForKey: @"updateCheckAutomatically"]);
	
	BOOL checkIpAddress  = (  askCheckForQuestions
							? [[checkboxResults objectAtIndex: 1] boolValue]
							: ! [gTbDefaults boolForKey: @"*-notOKToCheckThatIPAddressDidNotChangeAfterConnection"]);
	
	if (  askCheckForQuestions  ) {
		[gTbDefaults setBool: checkForUpdates  forKey: @"updateCheckAutomatically"];
		
		[gTbDefaults setBool: ! checkIpAddress forKey: @"*-notOKToCheckThatIPAddressDidNotChangeAfterConnection"];
	}
	
	if (  userAgreementChanged  ) {
		[gTbDefaults setObject: thisUserAgreementVersion forKey:@"userAgreementVersionAgreedTo"];
	}
	
	// "Register" this copy of Tunnelblick. q=asked_questions; c=check_for_updates; a=check_ip_address; r=rebranded, all y/n
	NSString * urlString = [NSString stringWithFormat: @"%@?q=%c&c=%c&a=%c&r=n",
							[registerURL absoluteString],
							askCheckForQuestions ? 'y' : 'n',
							checkForUpdates      ? 'y' : 'n',
							checkIpAddress       ? 'y' : 'n'];

	[NSThread detachNewThreadSelector: @selector(registerInstallationWithURLString:) toTarget: self withObject: urlString];
	
	return YES;
}

-(void) registerInstallationWithURLString: (NSString *) urlString {
	
	// Registers an installation or update by accessing a URL with a query string containing info about the installation or update
	// The website's log will include the query string, so the information can be extracted
	//
	// Logs errors but continues so users can block access to tunnelblick.net if they want (presumably few people will do this)
	//
	// RUNS IN ITS OWN THREAD because it does Internet access synchronously
	
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	NSURL * url = [NSURL URLWithString: urlString];
	if ( ! url  ) {
		NSLog(@"registerInstallationWithURL: Unable to create url from %@", urlString);
		[pool drain];
		return;
	}
	
	NSMutableURLRequest * req = [[[NSMutableURLRequest alloc] initWithURL: url] autorelease];
	if ( ! req  ) {
		NSLog(@"registerInstallationWithURL: Unable to create URLRequest");
		[pool drain];
		return;
	}
	
	NSString * tbVersion = [[self tunnelblickInfoDictionary] objectForKey: @"CFBundleShortVersionString"];
	NSString * userAgent = [NSString stringWithFormat: @"Tunnelblick installer/updater: %@", tbVersion];
	NSString * hostName = [url host];
	
	[req setValue: userAgent forHTTPHeaderField: @"User-Agent"];
	[req setValue: hostName  forHTTPHeaderField: @"Host"];
	[req setCachePolicy: NSURLRequestReloadIgnoringLocalAndRemoteCacheData];
	
	[req setTimeoutInterval: 60.0]; // Request a long timeout so it still works if tunnelblick.net is very busy
	
	// Perform the actual request
	NSError * requestError = nil;
	NSHTTPURLResponse * urlResponse  = nil;
	NSData * data =  [NSURLConnection sendSynchronousRequest: req
										   returningResponse: &urlResponse
													   error: &requestError];
	
	// Log errors, but don't do anything else about them. We let the request be blocked by firewalls, for example.
	
	if (  requestError  ) {
		NSLog(@"registerInstallationWithURL: Returned error was %@", requestError);
	}
	
	if (  ! data  ) {
		NSLog(@"registerInstallationWithURL: Returned data was nil");
	} else if (  [data length] > 40  ) {
		NSLog(@"registerInstallationWithURL:  Response data was too long (%ld bytes)", (long) [data length]);
	} else {
		NSString * content = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
		if ( ! content  ) {
			NSLog(@"registerInstallationWithURL: Content as string == nil");
		} else if (  ! [content isEqualToString: @"OK"]  ) {
			NSLog(@"registerInstallationWithURL: Content was not 'OK'. content = '%@'; response = %@", content, urlResponse);
		}
	}
	
	[pool drain];
}

-(int) countConfigurations: (NSArray *) tblksToInstallPaths {
    
    // Given an array of paths to .tblks, .ovpns, and/or .confs to be installed
    // Returns how many configurations will be installed, including nested .tblks and .ovpn and .conf configuration
    //
    // (Slightly tricky because if there is a .conf and a .ovpn with the same name, only the .ovpn will be installed)
    
    NSMutableArray * configPaths = [NSMutableArray arrayWithCapacity: [tblksToInstallPaths count]];
    unsigned i;
    for (  i=0; i<[tblksToInstallPaths count]; i++) {
        NSString * outerPath = [tblksToInstallPaths objectAtIndex: i];
        NSString * file;
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: outerPath];
        while (  (file = [dirEnum nextObject])  ) {
            if (   [file hasSuffix: @".ovpn"]
                || [file hasSuffix: @".conf"]  ) {
                NSString * fullPath = [outerPath stringByAppendingPathComponent: file];
                NSString * fullPathNoExt = [fullPath stringByDeletingPathExtension];
                NSString * fullPathConf  = [fullPathNoExt stringByAppendingPathExtension: @"conf"];
                NSString * fullPathOvpn  = [fullPathNoExt stringByAppendingPathExtension: @"ovpn"];
                if (  [fullPath isEqualToString: fullPathOvpn]  ) {
                    if (  [configPaths containsObject: fullPathConf]  ) {
                        [configPaths removeObject: fullPathConf];
                    }
                    [configPaths addObject:    fullPathOvpn];
                } else if (  [fullPath isEqualToString: fullPathConf]  ) {
                    if (  ! [configPaths containsObject: fullPathOvpn]  ) {
                        [configPaths addObject: fullPathConf];
                    }
                }
            }
        }
    }
    
    return [configPaths count];
}

-(void) setPreferencesFromDictionary: (NSDictionary *) dict
                 onlyIfNotSetAlready: (BOOL)           onlyIfNotSetAlready {
    
        NSString * key;
        NSEnumerator * e = [dict keyEnumerator];
        while (  (key = [e nextObject])  ) {
            id obj = [dict objectForKey: key];
            if (  obj  ) {
                if (  onlyIfNotSetAlready  ) {
                    if (  [gTbDefaults preferenceExistsForKey: key]  ) {
                        continue;
                    }
                }
                
                [gTbDefaults setObject: obj forKey: key];
                NSLog(@"Set preference '%@' to '%@'", key, obj);
            }
        }
}

-(void) setPreferencesFromDictionary: (NSDictionary *) dict
                                 key: (NSString *)     key
                 onlyIfNotSetAlready: (BOOL)           onlyIfNotSetAlready {
    
    id obj = [dict objectForKey: key];
    if (  obj  ) {
        if (  [[obj class] isSubclassOfClass: [NSDictionary class]]  ) {
            [self setPreferencesFromDictionary: (NSDictionary *) obj onlyIfNotSetAlready: onlyIfNotSetAlready];
        } else {
            NSLog(@"'%@' object is not a dictionary so it is being ignored", key);
            return;
        }
    }

}

-(void) removePreferences: (NSArray *) list {
    
    NSEnumerator * e = [list objectEnumerator];
    NSString * key;
    while (  (key = [e nextObject])  ) {
        id obj = [gTbDefaults objectForKey: key];
        if (  obj  ) {
            if (  [gTbDefaults canChangeValueForKey: key]  ) {
                [gTbDefaults removeObjectForKey: key];
                NSLog(@"Removed preference '%@' with value '%@'", key, obj);
            } else {
                NSLog(@"Preference '%@' with value '%@' is being forced, so it is not being removed", key, obj);
            }
        } else {
            NSLog(@"Preference '%@' does not exist, so it is not being removed", key);
        }
    }
}

-(void) setPreferencesFromPlistAtPath: (NSString *) plistPath {
    
    NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: plistPath];
    if (  dict  ) {
        
        // Remove items under the 'remove' key
        id removeList = [dict objectForKey: @"remove"];
        if (  removeList  ) {
            if (  [[removeList class] isSubclassOfClass: [NSArray class]]  ) {
                [self removePreferences: (NSArray *) removeList];
            } else {
                NSLog(@"Ignoring 'remove' object because it is not an array in %@", plistPath);
            }
        }
        
        // Set items under the 'always-set' key and the 'set-only-if-not-present' key
        [self setPreferencesFromDictionary: dict key: @"always-set"              onlyIfNotSetAlready: NO];
        [self setPreferencesFromDictionary: dict key: @"set-only-if-not-present" onlyIfNotSetAlready: YES];
        
        // Always set items that are not under the 'remove', 'always-set', or 'set-only-if-not-present' keys
        NSEnumerator * e = [dict keyEnumerator];
        NSString * key;
        while (  (key = [e nextObject])  ) {
            if (   [key isNotEqualTo: @"remove"]
                && [key isNotEqualTo: @"always-set"]
                && [key isNotEqualTo: @"set-only-if-not-present"]  ) {
                id obj = [dict objectForKey: key];
                [gTbDefaults setObject: obj forKey: key];
                NSLog(@"Set preference '%@' to '%@'", key, obj);
            }
        }
	}
}

-(void) setPreferencesFromAutoInstallFolders {
    
    NSString * enclosingFolderPath = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
    [self setPreferencesFromPlistAtPath: [enclosingFolderPath stringByAppendingPathComponent: @"auto-install/preferences.plist"]];
    [self setPreferencesFromPlistAtPath: [enclosingFolderPath stringByAppendingPathComponent: @".auto-install/preferences.plist"]];
}

-(NSString *) findPlistNamed: (NSString *) plistName toInstallInPath: (NSString *) thePath
{
    
    NSString * path = [[thePath stringByAppendingPathComponent: @"auto-install"] stringByAppendingPathComponent: plistName];
    if (  [gFileMgr fileExistsAtPath: path]  ) {
        if (  [NSDictionary dictionaryWithContentsOfFile: path]  ) {
            return path;
        }
        
        NSLog(@"Corrupted or unreadable .plist at %@", path);
    }
    
    path = [[thePath stringByAppendingPathComponent: @".auto-install"] stringByAppendingPathComponent: plistName];
    if (  [gFileMgr fileExistsAtPath: path]  ) {
        if (  [NSDictionary dictionaryWithContentsOfFile: path]  ) {
            return path;
        }
        
        NSLog(@"Corrupted or unreadable .plist at %@", path);
    }
    
    return nil;
}

-(void) relaunchIfNecessary
{
    TBLog(@"DB-SU", @"relaunchIfNecessary: 001")

	NSString * currentPath = [[NSBundle mainBundle] bundlePath];
	
	NSString * contentsPath = [currentPath stringByAppendingPathComponent: @"Contents"];
    if (   [gFileMgr fileExistsAtPath: [contentsPath stringByAppendingPathComponent: @"_CodeSignature"]]
		&& ( ! [self hasValidSignature] )  ) {
		signatureIsInvalid = TRUE;
	} else {
		signatureIsInvalid = FALSE;	// (But it might not have one)
	}
	
    TBLog(@"DB-SU", @"relaunchIfNecessary: 002")
    // Move or copy Tunnelblick.app to /Applications if it isn't already there
    
    BOOL canRunOnThisVolume = [self canRunFromVolume: currentPath];
    
    if (  canRunOnThisVolume ) {
#ifdef TBDebug
        NSLog(@"Tunnelblick: WARNING: This is an insecure copy of Tunnelblick to be used for debugging only!");
        [self warnIfInvalidOrNoSignatureAllowCheckbox: YES];
        return;
#else
        if (  [currentPath isEqualToString: @"/Applications/Tunnelblick.app"]  ) {
			[self warnIfInvalidOrNoSignatureAllowCheckbox: YES];
            return;
        } else {
            NSLog(@"Tunnelblick can only run when it is /Applications/Tunnelblick.app; path = %@.", currentPath);
        }
#endif
    } else {
        NSLog(@"Tunnelblick cannot run when it is on /%@ because the volume has the MNT_NOSUID statfs flag set.", [[currentPath pathComponents] objectAtIndex: 1]);
    }
    
    // Not installed in /Applications on a runnable volume. Need to move/install to /Applications
    
    TBLog(@"DB-SU", @"relaunchIfNecessary: 003")
	[self warnIfInvalidOrNoSignatureAllowCheckbox: NO];
	
	if (  ! [self userAcceptedUserAgreement]  ) {
		NSLog(@"The user did not agree to the terms for an installation");
		[self terminateBecause: terminatingBecauseOfQuit];
		return;
	}
	
    //Install into /Applications
	
    // Set up message about installing .tblks on the .dmg
    NSString * tblksMsg;
    NSArray * tblksToInstallPaths = [self findTblksToInstallInPath: [currentPath stringByDeletingLastPathComponent]];
    NSUInteger configurationInstallsBeingDone = [self countConfigurations: tblksToInstallPaths];
    if (  tblksToInstallPaths  ) {
        tblksMsg = [NSString stringWithFormat: NSLocalizedString(@"\n\nand install %ld Tunnelblick VPN Configurations", @"Window text"),
                    (long)configurationInstallsBeingDone];
    } else {
        tblksMsg = @"";
    }
    
    // Set up message about installing forced preferences on the .dmg
    NSString * forcedPlistToInstallPath = [self findPlistNamed: @"forced-preferences.plist"
                                               toInstallInPath: [currentPath stringByDeletingLastPathComponent]];
    NSString * plistMsg = (  forcedPlistToInstallPath
                           ? NSLocalizedString(@" Forced preferences will also be installed or replaced.\n\n", @"Window text")
                           : @"");
    
    // Set up messages to get authorization and notify of success
	NSString * appVersion   = tunnelblickVersion([NSBundle mainBundle]);	
    NSString * tbInApplicationsPath = [@"/Applications" stringByAppendingPathComponent: [currentPath lastPathComponent]];
    NSString * applicationsPath = @"/Applications";
    NSString * tbInApplicationsDisplayName = [[gFileMgr componentsToDisplayForPath: tbInApplicationsPath] componentsJoinedByString: @"/"];
    NSString * applicationsDisplayName = [[gFileMgr componentsToDisplayForPath: applicationsPath] componentsJoinedByString: @"/"];
    
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
        if (  configurationInstallsBeingDone == 0 ) {
            launchWindowText = NSLocalizedString(@"Tunnelblick was successfully replaced.", @"Window text");
        } else if (  configurationInstallsBeingDone == 1 ) {
            launchWindowText = NSLocalizedString(@"Tunnelblick was successfully replaced and one configuration was installed or replaced.", @"Window text");
        } else {
            launchWindowText = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick was successfully replaced and %ld configurations were installed or replaced.", @"Window text"), (unsigned long)configurationInstallsBeingDone];
       }
    } else {
        authorizationText = [NSString stringWithFormat:
                             NSLocalizedString(@" Do you wish to install %@ to %@%@?\n\n", @"Window text"),
                             appVersion, applicationsDisplayName, tblksMsg];
        if (  configurationInstallsBeingDone == 0 ) {
            launchWindowText = NSLocalizedString(@"Tunnelblick was successfully installed.", @"Window text");
        } else if (  configurationInstallsBeingDone == 1 ) {
            launchWindowText = NSLocalizedString(@"Tunnelblick was successfully installed and one configuration was installed or replaced.", @"Window text");
        } else {
            launchWindowText = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick was successfully installed and %ld configurations were installed or replaced.", @"Window text"), (unsigned long)configurationInstallsBeingDone];
        }
    }
    
    if (  tblksToInstallPaths  ) {
        if (  ! [self shouldInstallConfigurations: tblksToInstallPaths withTunnelblick: YES]  ) {
            NSLog(@"The Tunnelblick installation was cancelled by the user to avoid installing configurations that may have commands.");
            [self terminateBecause: terminatingBecauseOfQuit];
        }
    }
    
    TBLog(@"DB-SU", @"relaunchIfNecessary: 004")
    // Get authorization to install and secure
    if (  startupInstallAuth  ) {
        NSLog(@"relaunchIfNecessary: startupInstallAuth is already set");
        [self terminateBecause: terminatingBecauseOfError];
    }
    
    NSString * prompt = [[[[NSLocalizedString(@" Tunnelblick must be installed in Applications.\n\n", @"Window text")
                            stringByAppendingString: authorizationText]
                           stringByAppendingString: convertTblksText]
                          stringByAppendingString: signatureWarningText]
                         stringByAppendingString: plistMsg];
    SystemAuth * auth = [SystemAuth newAuthWithoutReactivationWithPrompt: prompt];
    if (  auth  ) {
        [self setStartupInstallAuth: auth];
        [auth release];
    } else {
        NSLog(@"The Tunnelblick installation was cancelled by the user.");
        [self terminateBecause: terminatingBecauseOfQuit];
        return;
    }
    
    TBLog(@"DB-SU", @"relaunchIfNecessary: 005")
    
    // Make sure there are no Tunnelblicks or OpenVPNs running
    BOOL openvpns          = ( [NSApp pidsOfProcessesWithPrefix: @"/Applications/Tunnelblick.app/Contents/Resources/openvpn"] != nil );
    BOOL otherTunnelblicks = ( [NSApp countOtherInstances] > 0 );
    
    while (   openvpns
           || otherTunnelblicks  ) {
        
        if (  openvpns  ) {
            int button = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                                         NSLocalizedString(@"One or more VPNs are currently connected. Please disconnect all VPNs and quit Tunnelblick before proceeding.", @"Window text"),
                                         NSLocalizedString(@"Retry", @"Button"),   // Default button
                                         NSLocalizedString(@"Cancel",  @"Button"), // Alternate button
                                         nil);
            if (  button != NSAlertDefaultReturn  ) {// Cancel or error: Quit Tunnelblick
                [self terminateBecause: terminatingBecauseOfQuit];
            }
        } else {
            int button = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                                         NSLocalizedString(@"Tunnelblick is currently running. It will be shut down before proceeding.", @"Window text"),
                                         NSLocalizedString(@"OK", @"Button"),      // Default button
                                         NSLocalizedString(@"Cancel",  @"Button"), // Alternate button
                                         nil);
            if (  button != NSAlertDefaultReturn  ) {// Cancel or error: Quit Tunnelblick
                [self terminateBecause: terminatingBecauseOfQuit];
            }
            
            // Kill other instances of Tunnelblick and wait up to about 10 seconds for them to quit
            [NSApp killOtherInstances];
            int i = 0;
            while (   ([NSApp countOtherInstances] > 0)
                   && (i < 10)  ) {
                sleep(1);
                i++;
            }
        }
        
        otherTunnelblicks = ( [NSApp countOtherInstances] > 0 );
		openvpns          = ( [NSApp pidsOfProcessesWithPrefix: @"/Applications/Tunnelblick.app/Contents/Resources/openvpn"] != nil );
    }
    
    TBLog(@"DB-SU", @"relaunchIfNecessary: 006")
	NSString * text = [NSString stringWithFormat: NSLocalizedString(@"Installing and securing Tunnelblick %@...", @"Window text; '%@' will be replaced with a version number such as '3.6.10'"), [self tunnelblickVersionString]];
	[splashScreen setMessage: text];
	[gTbDefaults removeObjectForKey: @"skipWarningAboutInvalidSignature"];
	[gTbDefaults removeObjectForKey: @"skipWarningAboutNoSignature"];
    
    [self setPreferencesFromAutoInstallFolders];
    
    TBLog(@"DB-SU", @"relaunchIfNecessary: 007")
    // Install this program and secure it
	NSInteger installerResult = [self runInstaller: (  INSTALLER_COPY_APP
													 | INSTALLER_SECURE_APP
													 | INSTALLER_SECURE_TBLKS
													 | (  gOkToConvertNonTblks
														? INSTALLER_CONVERT_NON_TBLKS
														: 0)
													 | (  needToMoveLibraryOpenVPN()
														? INSTALLER_MOVE_LIBRARY_OPENVPN
														: 0)
													 | (  forcedPlistToInstallPath
                                                        ? INSTALLER_INSTALL_FORCED_PREFERENCES
                                                        : 0)
                                                     )
									extraArguments: (  forcedPlistToInstallPath
                                                     ? [NSArray arrayWithObject: forcedPlistToInstallPath]
                                                     : nil)
								   usingSystemAuth: [self startupInstallAuth]
								      installTblks: tblksToInstallPaths];
    if (  installerResult != 0  ) {
        // Error occurred or the user cancelled. An error dialog and a message in the console log have already been displayed if an error occurred
        [self terminateBecause: terminatingBecauseOfError];
    }
	
    TBLog(@"DB-SU", @"relaunchIfNecessary: 008")
	gOkToConvertNonTblks = FALSE;
	gUserWasAskedAboutConvertNonTblks = FALSE;
    
    TBLog(@"DB-SU", @"relaunchIfNecessary: 009")
    [splashScreen setMessage: NSLocalizedString(@"Installation finished successfully.", @"Window text")];
	if (  runningOnMountainLionOrNewer()  ) {
		[UIHelper showSuccessNotificationTitle: NSLocalizedString(@"Installation succeeded", @"Window title") msg: launchWindowText];
    }
	
    TBLog(@"DB-SU", @"relaunchIfNecessary: 010")
    [splashScreen fadeOutAndClose];
    
    TBLog(@"DB-SU", @"relaunchIfNecessary: 011")
	// Launch the program in /Applications
	if (  ! [[NSWorkspace sharedWorkspace] launchApplication: tbInApplicationsPath]  ) {
		TBRunAlertPanel(NSLocalizedString(@"Unable to launch Tunnelblick", @"Window title"),
						[NSString stringWithFormat: NSLocalizedString(@"An error occurred while trying to launch %@", @"Window text"), tbInApplicationsDisplayName],
						nil, nil, nil);
	}
    
    TBLog(@"DB-SU", @"relaunchIfNecessary: 012")
    [self terminateBecause: terminatingBecauseOfQuit];
    TBLog(@"DB-SU", @"relaunchIfNecessary: 013 - LAST after terminateBecause")
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

-(NSString *) promptForInstaller: (unsigned)  installFlags
                    installTblks: (NSArray *) tblksToInstall {
    
    if (  installFlags & INSTALLER_COPY_APP  ) {
        installFlags = installFlags | INSTALLER_SECURE_TBLKS;
    }

    BOOL appended = FALSE;
    NSMutableString * msg = [NSMutableString stringWithString: NSLocalizedString(@"Tunnelblick needs to:\n", @"Window text")];
    if (    installFlags & INSTALLER_COPY_APP                   ) { [msg appendString: NSLocalizedString(@"  • Be installed in /Applications as Tunnelblick\n", @"Window text")]; appended = TRUE; }
    if (    installFlags & INSTALLER_SECURE_APP                 ) { [msg appendString: NSLocalizedString(@"  • Change ownership and permissions of the program to secure it\n", @"Window text")]; appended = TRUE; }
    if (    installFlags & INSTALLER_MOVE_LIBRARY_OPENVPN       ) { [msg appendString: NSLocalizedString(@"  • Move the private configurations folder\n", @"Window text")]; appended = TRUE; }
    if (    tblksToInstall                                 ) { [msg appendString: NSLocalizedString(@"  • Install or update configuration(s)\n", @"Window text")]; appended = TRUE; }
    if (    installFlags & INSTALLER_CONVERT_NON_TBLKS          ) { [msg appendString: NSLocalizedString(@"  • Convert OpenVPN configurations\n", @"Window text")]; appended = TRUE; }
    if (    installFlags & INSTALLER_SECURE_TBLKS               ) { [msg appendString: NSLocalizedString(@"  • Secure configurations\n", @"Window text")]; appended = TRUE; }
    if (    installFlags & INSTALLER_INSTALL_FORCED_PREFERENCES ) { [msg appendString: NSLocalizedString(@"  • Install forced preferences\n", @"Window text")]; appended = TRUE; }
    
    if (   ( ! appended)
        && ( ! tblksToInstall)  ) {
        if (  installFlags & INSTALLER_REPLACE_DAEMON           ) { [msg appendString: NSLocalizedString(@"  • Complete the update\n", @"Window text; appears after an update and will be prefixed by 'Tunnelblick needs to:'")]; appended = TRUE; }
    }
    
#ifdef TBDebug
    [msg appendString: NSLocalizedString(@"\n WARNING: This copy of Tunnelblick makes your computer insecure."
                                         @" It is for debugging purposes only.\n", @"Window text")];
#endif
    
    if (  signatureIsInvalid  ) {
        [msg appendString: NSLocalizedString(@"\n WARNING: This copy of Tunnelblick has been tampered with.\n", @"Window text")];
    }
    
    if (  ! appended  ) {
        msg = [NSMutableString stringWithString: NSLocalizedString(@"Tunnelblick needs to perform an action that requires administrator authorization.\n", @"Window text")];
    }
    
    return [NSString stringWithFormat: @"%@", msg];
}

-(void) secureIfNecessary
{
    // If necessary, run the installer to secure this copy of Tunnelblick
    unsigned installFlags;
    if (  (installFlags = needToRunInstaller(FALSE)) != 0  ) {
        
		if (  ! [self userAcceptedUserAgreement]  ) {
			NSLog(@"The user did not agree to the terms for an update");
			[self terminateBecause: terminatingBecauseOfQuit];
			return;
		}
		
		NSString * text = [NSString stringWithFormat: NSLocalizedString(@"Securing Tunnelblick %@...", @"Window text; '%@' will be replaced with a version number such as '3.6.10'"), [self tunnelblickVersionString]];
		[splashScreen setMessage: text];
        if (  startupInstallAuth  ) {
            NSLog(@"secureIfNecessary: startupInstallAuth is already set");
            [self terminateBecause: terminatingBecauseOfError];
        }
        
        NSString * prompt = [self promptForInstaller: installFlags installTblks: nil];
        SystemAuth * auth = [SystemAuth newAuthWithoutReactivationWithPrompt: prompt];
 
        if (  auth  ) {
            [self setStartupInstallAuth: auth];
            [auth release];
        } else {
            NSLog(@"The Tunnelblick installation was cancelled by the user.");
            [self terminateBecause: terminatingBecauseOfQuit];
            return;
        }
        
        NSInteger installerResult = [self runInstaller: installFlags
										extraArguments: nil
                                       usingSystemAuth: [self startupInstallAuth]
                                          installTblks: nil];
		if (  installerResult != 0  ) {
            
			// An error occurred or the user cancelled. An error dialog and a message in the console log have already been displayed if an error occurred
            [self terminateBecause: terminatingBecauseOfError];
        }
		
		text = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick %@ has been secured successfully.", @"Window text; '%@' will be replaced with a version number such as '3.2.1 (build 1234)'"), [self tunnelblickVersionString]];
		[splashScreen setMessage: text];
    }
}

-(NSInteger) runInstaller: (unsigned)           installFlags
		   extraArguments: (NSArray *)          extraArguments
                 usingSystemAuth: (SystemAuth *)       auth
                    installTblks: (NSArray *)          tblksToInstall {
    
    // Returns 1 if the user cancelled the installation
	//         0 if installer ran successfully and does not need to be run again
	//        -1 if an error occurred
	
    if (   (installFlags == 0)
		&& (extraArguments == nil)  ) {
		NSLog(@"runInstaller invoked but no action specified");
        return -1;
    }
    
    // Check that the authorization is valid and re-prompt if necessary
    if (  ! [auth authRef]  ) {
        NSLog(@"runInstaller:... authorization was cancelled");
        return 1;
    }
    
    if (  installFlags & INSTALLER_COPY_APP  ) {
        installFlags = installFlags | INSTALLER_SECURE_TBLKS;
    }
    
    NSString * msg = [[self promptForInstaller: installFlags installTblks: tblksToInstall]
                      stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSLog(@"%@", msg);
    
    NSLog(@"Beginning installation or repair");

    NSString *launchPath = [[NSBundle mainBundle] pathForResource:@"installer" ofType:nil];

	installFlags = installFlags | INSTALLER_CLEAR_LOG;
	
    int result = -1;    // Last result from waitForExecuteAuthorized
    BOOL okNow = FALSE;
    NSUInteger i;
    for (  i=0; ; i++  ) {
        
        if (  i != 0  ) {
            int result = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", "Window title"),
                                         NSLocalizedString(@"The installation or repair took too long or failed. Try again?", "Window text"),
                                         NSLocalizedString(@"Quit", @"Button"),
                                         NSLocalizedString(@"Retry", @"Button"),
                                         nil);
            if (  result != NSAlertAlternateReturn  ) {   // Quit if "Quit" or error
				NSString * installerLog = @" (none)";
				if (  [gFileMgr fileExistsAtPath: @"/tmp/tunnelblick-installer-log.txt"]  ) {
					NSData * data = [gFileMgr contentsAtPath: @"/tmp/tunnelblick-installer-log.txt"];
					if (  data  ) {
						installerLog = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
					}
				}
				NSLog(@"Installation or repair failed; Log:\n%@", installerLog);
				
				[installerLog release];
                [self terminateBecause: terminatingBecauseOfQuit];
				return -1;
			}
			
            NSLog(@"Retrying execution of installer");
        }
        
		NSMutableArray * arguments = [[[NSMutableArray alloc] initWithCapacity: 3] autorelease];
		[arguments addObject: [NSString stringWithFormat: @"%u", installFlags]];
		
		NSString * arg;
		NSEnumerator * e = [extraArguments objectEnumerator];
		while (  (arg = [e nextObject])  ) {
			[arguments addObject: arg];
		}
		
		installFlags = installFlags & ( ~ INSTALLER_CLEAR_LOG );
		
        result = [NSApplication waitForExecuteAuthorized: launchPath withArguments: arguments withAuthorizationRef: [auth authRef]];
        
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
                              | INSTALLER_SECURE_TBLKS
                              | INSTALLER_CONVERT_NON_TBLKS
                              | INSTALLER_MOVE_LIBRARY_OPENVPN
                              | INSTALLER_REPLACE_DAEMON
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
	
	NSString * installerLog = @" (none)";
	if (  [gFileMgr fileExistsAtPath: @"/tmp/tunnelblick-installer-log.txt"]  ) {
		NSData * data = [gFileMgr contentsAtPath: @"/tmp/tunnelblick-installer-log.txt"];
		if (  data  ) {
			installerLog = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
		}
	}
    
    if (  okNow  ) {
        NSLog(@"Installation or repair succeeded; Log:\n%@", installerLog);
        [installerLog release];
        
        if (  [tblksToInstall count] != 0  ) {
            [ConfigurationManager installConfigurationsInCurrentMainThreadDoNotShowMessagesDoNotNotifyDelegateWithPaths: tblksToInstall];
        }
        
        return 0;
    }
    
    NSLog(@"Installation or repair failed; Log:\n%@", installerLog);
    
	[installerLog release];
    TBRunAlertPanel(NSLocalizedString(@"Installation or Repair Failed", "Window title"),
					NSLocalizedString(@"The installation, removal, recovery, or repair of one or more Tunnelblick components failed. See the Console Log for details.", "Window text"),
					nil, nil, nil);
    return -1;
}

// Checks whether the installer needs to be run
// Sets bits in a flag for use by the runInstaller:extraArguments... method, and, ultimately, by the installer program
//
// DOES NOT SET INSTALLER_COPY_APP (or INSTALLER_MOVE_NOT_COPY, or INSTALLER_DELETE)
//
// Returns an unsigned containing INSTALLER_... bits set appropriately
unsigned needToRunInstaller(BOOL inApplications)
{
    unsigned flags = 0;
    
    if (  needToChangeOwnershipAndOrPermissions(inApplications)  ) flags = flags | INSTALLER_SECURE_APP;
    if (  needToReplaceLaunchDaemon()                            ) flags = flags | INSTALLER_REPLACE_DAEMON;
    if (  needToRepairPackages()                                 ) flags = flags | INSTALLER_SECURE_TBLKS;
    if (  needToMoveLibraryOpenVPN()                             ) flags = flags | INSTALLER_MOVE_LIBRARY_OPENVPN;
    if (  needToConvertNonTblks()  ) {
		flags = flags | INSTALLER_CONVERT_NON_TBLKS;
		NSLog(@"Need to convert non-.tblk configurations");
	}
    
    return flags;
}

BOOL needToMoveLibraryOpenVPN(void)
{
    // Check if the old (before 3.0b24 (2009-12-12)) configuration folder needs to be moved and replaced by a symlink.
    
    NSString * oldConfigDirPath = [NSHomeDirectory() stringByAppendingPathComponent: @"Library/openvpn"];
    
    // If there is no nothing to be moved, return NO. (MenuController/init will make sure the new configuration folder exists.)
    if (  ! [gFileMgr fileExistsAtPath: oldConfigDirPath]  ) {
        return NO;
    }
    
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

BOOL needToSecureFolderAtPath(NSString * path, BOOL isDeployFolder)
{
    // Returns YES if the folder needs to be secured
    //
    // There is a SIMILAR function in openvpnstart: exitIfTblkNeedsRepair
    //
    // There is a SIMILAR function in sharedRoutines: secureOneFolder, that secures a folder with these permissions
    
    mode_t folderPerms;         //  For folders
    mode_t scriptPerms;         //  For files with .sh extensions
    mode_t executablePerms;     //  For files with .executable extensions (only appear in a Deploy folder
    mode_t publicReadablePerms; //  For files named Info.plist (and forced-preferences.plist in a Deploy folder)
    mode_t otherPerms;          //  For all other files
    
	uid_t user = 0;
	gid_t group = 0;
	
    folderPerms         = PERMS_SECURED_FOLDER;
    scriptPerms         = PERMS_SECURED_SCRIPT;
    executablePerms     = PERMS_SECURED_EXECUTABLE;
    publicReadablePerms = PERMS_SECURED_READABLE;
    otherPerms          = PERMS_SECURED_OTHER;
    
    if (  ! checkOwnerAndPermissions(path, 0, 0, folderPerms)  ) {
        return YES;
    }
    
    BOOL isDir;
    NSString * file;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: path];
	
    while (  (file = [dirEnum nextObject])  ) {
        NSString * filePath = [path stringByAppendingPathComponent: file];
        NSString * ext  = [file pathExtension];
        
        if (   [gFileMgr fileExistsAtPath: filePath isDirectory: &isDir]
            && isDir  ) {
            if (  ! checkOwnerAndPermissions(filePath, user, group, folderPerms)  ) {
                return YES;
            }
            
        } else if ( [ext isEqualToString:@"sh"]  ) {
            if (  ! checkOwnerAndPermissions(filePath, user, group, scriptPerms)  ) {
                return YES;
            }
            
        } else if (   [ext isEqualToString: @"strings"]
                   || [ext isEqualToString: @"png"]
                   || [[file lastPathComponent] isEqualToString:@"Info.plist"]  ) {
            if (  ! checkOwnerAndPermissions(filePath, user, group, publicReadablePerms)  ) {
                return YES;
            }
            
        } else if (  isDeployFolder  ) {
            if (   [[file lastPathComponent] isEqualToString:@"forced-preferences.plist"]
                || [filePath hasPrefix: [path stringByAppendingPathComponent: @"Welcome"]]  ) {
                if (  ! checkOwnerAndPermissions(filePath, user, group, publicReadablePerms)  ) {
                    return YES;
                }
            } else if ( [ext isEqualToString:@"executable"]  ) {
                if (  ! checkOwnerAndPermissions(filePath, user, group, executablePerms)  ) {
                    return YES;
                }
            } else {
                if (  ! checkOwnerAndPermissions(filePath, user, group, otherPerms)  ) {
                    return YES;
                }
            }
            
        } else {
            if (  ! checkOwnerAndPermissions(filePath, user, group, otherPerms)  ) {
                return YES;
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
    NSString *pncPlistPath              = [resourcesPath stringByAppendingPathComponent: @"ProcessNetworkChanges.plist"         ];
    NSString *tunnelblickdPath          = [resourcesPath stringByAppendingPathComponent: @"tunnelblickd"                        ];
    NSString *tunnelblickHelperPath     = [resourcesPath stringByAppendingPathComponent: @"tunnelblick-helper"                  ];
    NSString *leasewatchPlistPath       = [resourcesPath stringByAppendingPathComponent: @"LeaseWatch.plist"                    ];
    NSString *leasewatch3PlistPath      = [resourcesPath stringByAppendingPathComponent: @"LeaseWatch3.plist"                   ];
    NSString *tunnelblickdPlistPath     = [resourcesPath stringByAppendingPathComponent: @"net.tunnelblick.tunnelblick.tunnelblickd.plist"];
    NSString *launchAtLoginPlistPath    = [resourcesPath stringByAppendingPathComponent: @"net.tunnelblick.tunnelblick.LaunchAtLogin.plist"];
    NSString *launchAtLoginScriptPath   = [resourcesPath stringByAppendingPathComponent: @"launchAtLogin.sh"                    ];
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
    NSString *reactivateTunnelblickPath = [resourcesPath stringByAppendingPathComponent: @"reactivate-tunnelblick.sh"           ];
	NSString *freePublicDnsServersPath  = [resourcesPath stringByAppendingPathComponent: @"FreePublicDnsServersList.txt"        ];
    NSString *deployPath                = [resourcesPath stringByAppendingPathComponent: @"Deploy"                              ];
    NSString *infoPlistPath             = [[resourcesPath stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"Info.plist"];

	if (  ! checkOwnedByRootWheel(tunnelblickPath) ) {
        NSLog(@"%@ not owned by root:wheel", tunnelblickPath);
        return YES;
	}
    
    if (  ! checkOwnerAndPermissions(tunnelblickPath, 0, 0, PERMS_SECURED_FOLDER)  ) {
        return YES; // NSLog already called
    }
    
    if (  ! checkOwnerAndPermissions(contentsPath,    0, 0, PERMS_SECURED_FOLDER)  ) {
        return YES; // NSLog already called
    }
    
    if (  ! checkOwnerAndPermissions(resourcesPath,   0, 0, PERMS_SECURED_FOLDER)  ) {
        return YES; // NSLog already called
    }
    
    if (  ! checkOwnerAndPermissions(openvpnstartPath, 0, 0, PERMS_SECURED_EXECUTABLE)  ) {
        return YES; // NSLog already called
	}
	
    if (  ! checkOwnerAndPermissions(tunnelblickHelperPath, 0, 0, PERMS_SECURED_EXECUTABLE)  ) {
        return YES; // NSLog already called
	}
	
    // check openvpn folder
    if (  ! checkOwnerAndPermissions(openvpnFolderPath, 0, 0, PERMS_SECURED_FOLDER)  ) {
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
            if (  ! checkOwnerAndPermissions(fullPath, 0, 0, PERMS_SECURED_FOLDER)  ) {
                return YES;
            }
            
            if (  [file hasPrefix: @"openvpn-"]  ) {
                NSString * thisOpenvpnPath = [fullPath stringByAppendingPathComponent: @"openvpn"];
                if (  ! checkOwnerAndPermissions(thisOpenvpnPath, 0, 0, PERMS_SECURED_EXECUTABLE)  ) {
                    return YES;
                }
                
                NSString * thisOpenvpnDownRootPath = [fullPath stringByAppendingPathComponent: @"openvpn-down-root.so"];
                if (  ! checkOwnerAndPermissions(thisOpenvpnDownRootPath, 0, 0, PERMS_SECURED_ROOT_EXEC)  ) {
                    return YES;
                }
            }
        }
    }
    
	// Check _CodeSignature if it is present. It should have 0755 permissions, and all of its contents should have 0644 permissions
	NSString * codeSigPath = [contentsPath stringByAppendingPathComponent: @"_CodeSignature"];
	if (   [gFileMgr fileExistsAtPath: codeSigPath isDirectory: &isDir]
		&& isDir  ) {
		if (  ! checkOwnerAndPermissions(codeSigPath, 0, 0, PERMS_SECURED_FOLDER)  ) {
			return YES;
		}
		dirEnum = [gFileMgr enumeratorAtPath: codeSigPath];
		while (  (file = [dirEnum nextObject])  ) {
			NSString * itemPath = [codeSigPath stringByAppendingPathComponent: file];
			if (  ! checkOwnerAndPermissions(itemPath, 0, 0, 0644)  ) {
				return YES;
			}
		}
	}
			
    // Check all kexts
    // Everything in a kext should have permissions of 0755 except Info.plist and the contents of _CodeSignature, which all should have permissions of 0644
    dirEnum = [gFileMgr enumeratorAtPath: resourcesPath];
    while (  (file = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        if (  [file hasSuffix: @".kext"]  ) {
            NSString * kextPath = [resourcesPath stringByAppendingPathComponent: file];
            if (   [gFileMgr fileExistsAtPath: kextPath isDirectory: &isDir]
                && isDir  ) {
                NSString * itemName;
                NSDirectoryEnumerator * kextEnum = [gFileMgr enumeratorAtPath: kextPath];
                while (  (itemName = [kextEnum nextObject])  ) {
                    NSString * fullPath = [kextPath stringByAppendingPathComponent: itemName];
                    if (   [fullPath hasSuffix: @"/Info.plist"]
                        || [[[fullPath stringByDeletingLastPathComponent] lastPathComponent] isEqualToString: @"_CodeSignature"]   ) {
                        if (  ! checkOwnerAndPermissions(fullPath, 0, 0, 0644)  ) {
                           return YES;
                        }
                    } else {
                        if (  ! checkOwnerAndPermissions(fullPath, 0, 0, 0755)  ) {
                            return YES;
                        }
                    }
                }
            } else {
                NSLog(@"Warning: Kext has disappeared (!) or is not a directory: %@", kextPath);
            }
        }
    }
    
	// check files which should be executable by root (only)
	NSArray *rootExecutableObjects = [NSArray arrayWithObjects:
									  atsystemstartPath, installerPath, ssoPath, tunnelblickdPath,
									  leasewatchPath, leasewatch3Path,
									  clientUpPath, clientDownPath,
									  clientNoMonUpPath, clientNoMonDownPath,
									  clientNewUpPath, clientNewDownPath, clientNewRoutePreDownPath,
									  clientNewAlt1UpPath, clientNewAlt1DownPath,
									  clientNewAlt2UpPath, clientNewAlt2DownPath,
									  clientNewAlt3UpPath, clientNewAlt3DownPath,
									  nil];
	NSEnumerator *e = [rootExecutableObjects objectEnumerator];
	NSString *currentPath;
	while (  (currentPath = [e nextObject])  ) {
        if (  ! checkOwnerAndPermissions(currentPath, 0, 0, PERMS_SECURED_ROOT_EXEC)  ) {
            return YES; // NSLog already called
        }
	}
    
	// check files which should be owned by root with 644 permissions
	NSArray *root644Objects = [NSArray arrayWithObjects: infoPlistPath, pncPlistPath, leasewatchPlistPath, leasewatch3PlistPath, launchAtLoginPlistPath, tunnelblickdPlistPath, freePublicDnsServersPath, nil];
	e = [root644Objects objectEnumerator];
	while (  (currentPath = [e nextObject])  ) {
        if (  ! checkOwnerAndPermissions(currentPath, 0, 0, PERMS_SECURED_READABLE)  ) {
            return YES; // NSLog already called
        }
	}
    
	// check files which should  be owned by root with 755 permissions
    if (  ! checkOwnerAndPermissions(launchAtLoginScriptPath, 0, 0, PERMS_SECURED_EXECUTABLE)  ) {
        return YES; // NSLog already called
    }
    if (  ! checkOwnerAndPermissions(reactivateTunnelblickPath, 0, 0, PERMS_SECURED_EXECUTABLE)  ) {
        return YES; // NSLog already called
    }
	
    // check that log directory exists and has proper ownership and permissions
    if (  ! (   [gFileMgr fileExistsAtPath: L_AS_T_LOGS isDirectory: &isDir]
             && isDir )  ) {
        NSLog(@"Need to create log directory '%@'", L_AS_T_LOGS);
        return YES;
    }
    if (  ! checkOwnerAndPermissions(L_AS_T_LOGS, 0, 0, PERMS_SECURED_FOLDER)  ) {
        return YES; // NSLog already called
    }
    
    // check that Users directory exists and has proper ownership and permissions
    if (  ! (   [gFileMgr fileExistsAtPath: L_AS_T_USERS isDirectory: &isDir]
             && isDir )  ) {
        NSLog(@"Need to create Users directory '%@'", L_AS_T_USERS);
        return YES;
    }
    if (  ! checkOwnerAndPermissions(L_AS_T_USERS, 0, 0, PERMS_SECURED_FOLDER)  ) {
        return YES; // NSLog already called
    }
    
    // check permissions of files in Resources/Deploy (if it exists)
    if (  [gFileMgr fileExistsAtPath: deployPath isDirectory: &isDir]
        && isDir  ) {
        if (  needToSecureFolderAtPath(deployPath, TRUE)  ) {
			NSLog(@"Need to secure the 'Deploy' folder");
            return YES;
        }
    }
    
    // Check the primary forced preferences .plist
    if (  [gFileMgr fileExistsAtPath: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH]  ) {
        if (  ! checkOwnerAndPermissions(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH, 0, 0, PERMS_SECURED_READABLE)  ) {
            return YES; // NSLog already called
        }
    }
    
    // Final check: Everything in the application is owned by root:wheel and is not writable by "other"
    dirEnum = [gFileMgr enumeratorAtPath: tunnelblickPath];
    while (  (file = [dirEnum nextObject])  ) {
        NSString     * fullPath = [tunnelblickPath stringByAppendingPathComponent: file];
        NSDictionary * atts     = [gFileMgr tbFileAttributesAtPath: fullPath traverseLink: NO];
        uid_t          owner    = (uid_t) [[atts fileOwnerAccountID]      unsignedIntValue];
        gid_t          group    = (gid_t) [[atts fileGroupOwnerAccountID] unsignedIntValue];
        unsigned long  perms    = [atts filePosixPermissions];
        if (   (owner != 0)
            || (group != 0)
            || ( (perms & S_IWOTH) != 0 )  ) {
            NSLog(@"Security warning: owned by %ld:%ld with permissions 0%lo: %@", (long) owner, (long) group, (long) perms, fullPath);
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
				NSString * contentsPath = [fullPath stringByAppendingPathComponent: @"Contents"];
                if (  checkOwnedByRootWheel(contentsPath)  ) {
					NSLog(@"%@ is owned by root:wheel; needs to be changed to owned by user:80", contentsPath);
                    return YES;
                }
				[dirEnum skipDescendents];
			}
        }
    }
    
    return NO;
}

BOOL needToConvertNonTblks(void)
{
	if (  gUserWasAskedAboutConvertNonTblks  ) {		// Have already asked
		if (  anyNonTblkConfigs()  ) {
            NSLog(@"Non-.tblk configurations are present and need to be converted (will %@convert them)", (  gOkToConvertNonTblks
                                                                                                           ? @""
                                                                                                           : @"not "));
			return gOkToConvertNonTblks;
		}
		
		gOkToConvertNonTblks = FALSE;
		gUserWasAskedAboutConvertNonTblks = FALSE;
		return NO;
	}
	
	if (  warnAboutNonTblks()  ) {	// Ask if necessary
        NSLog(@"Non-.tblk configurations are present and need to be converted");
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
    [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
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
    gShuttingDownTunnelblick = TRUE;
    
    TBLog(@"DB-SD", @"shutDownTunnelblick: started.")
    terminatingAtUserRequest = TRUE;
    
	if (   (reasonForTermination != terminatingBecauseOfLogout)
		&& (reasonForTermination != terminatingBecauseOfRestart)
		&& (reasonForTermination != terminatingBecauseOfShutdown)  ) {
        [gTbDefaults setBool: NO forKey: @"launchAtNextLogin"];
	}
	
    if (  [theAnim isAnimating]  ) {
        TBLog(@"DB-SD", @"shutDownTunnelblick: stopping icon animation.")
        [theAnim stopAnimation];
    }
    
    TBLog(@"DB-SD", @"shutDownTunnelblick: Starting cleanup.");
    if (  [self cleanup]  ) {
        TBLog(@"DB-SD", @"shutDownTunnelblick: Cleanup finished.")
    } else {
        TBLog(@"DB-SD", @"shutDownTunnelblick: Cleanup already being done.")
    }
    
    NSLog(@"Finished shutting down Tunnelblick; allowing termination");
    [NSApp replyToApplicationShouldTerminate: YES];
}


//- (void) applicationWillTerminate: (NSNotification*) notification
//{
//	(void) notification;
//
//    NSLog(@"DEBUG: applicationWillTerminate: invoked");
//}

// These five notifications happen BEFORE the "willLogoutOrShutdown" notification and indicate intention

-(void) logoutInitiatedHandler: (NSNotification *) n
{
	(void) n;
	
    reasonForTermination = terminatingBecauseOfLogout;
    TBLog(@"DB-SD", @"Initiated logout")
}

-(void) restartInitiatedHandler: (NSNotification *) n
{
	(void) n;
	
    reasonForTermination = terminatingBecauseOfRestart;
    TBLog(@"DB-SD", @"Initiated computer restart")
}

-(void) shutdownInitiatedHandler: (NSNotification *) n
{
	(void) n;
	
    reasonForTermination = terminatingBecauseOfShutdown;
    TBLog(@"DB-SD", @"Initiated computer shutdown")
}

-(void) logoutCancelledHandler: (NSNotification *) n
{
	(void) n;
	
    reasonForTermination = terminatingForUnknownReason;
    TBLog(@"DB-SD", @"Cancelled logout, or computer shutdown or restart.")
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
            NSLog(@"setShutdownVariables: invoked, but have already set them");
        } else {
            NSLog(@"setShutdownVariables: pthread_mutex_trylock( &myVPNMenuMutex ) failed; status = %ld; %s", (long) status, strerror(status));
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
	
    TBLog(@"DB-SD", @"logoutContinuedHandler: Confirmed logout, or computer shutdown or restart.")
    [self setShutdownVariables];
}

// This notification happens when we know we actually will logout or shutdown (or restart)
-(void) willLogoutOrShutdownHandler: (NSNotification *) n
{
 	(void) n;
	
   TBLog(@"DB-SD", @"willLogoutOrShutdownHandler: Received 'NSWorkspaceWillPowerOffNotification' notification")
    [self setShutdownVariables];
}


-(void)TunnelblickShutdownUIHandler: (NSNotification *) n
{
	(void) n;
	
    TBLog(@"DB-SD", @"TunnelblickShutdownUIHandler: invoked")
}

-(void)clearAllHaveConnectedSince {
    
    // Main loop only
    
    VPNConnection * connection;
    NSEnumerator * e = [myVPNConnectionDictionary objectEnumerator];
	while (  (connection = [e nextObject])  ) {
        [connection setHaveConnectedSince: NO];
    }
}

-(void)willGoToSleepHandler: (NSNotification *) n
{
 	(void) n;
    
    if (  gShuttingDownOrRestartingComputer  ) {
		TBLog(@"DB-SW", @"willGoToSleepHandler: ignored because computer is shutting down or restarting");
        return;
    }
    
    if (  OSAtomicCompareAndSwap32Barrier(noSleepState, gettingReadyForSleep, &gSleepWakeState)  ) {
		TBLog(@"DB-SW", "willGoToSleepHandler: state = gettingReadyForSleep");
	} else {
		NSLog(@"willGoToSleepHandler: ignored because gSleepWakeState was not 'noSleepState' (it is %ld)", (long) gSleepWakeState);
        return;
    }
    
    terminatingAtUserRequest = TRUE;
    
	TBLog(@"DB-SW", @"willGoToSleepHandler: Setting up to go to sleep")
	[self startDisconnectionsForSleeping];
    
    // Indicate no configurations have connected since sleep
    // Done here so it is correct immediately when computer wakes
    [self performSelectorOnMainThread: @selector(clearAllHaveConnectedSince) withObject: nil waitUntilDone: YES];
    
    if (  [[self connectionsToWaitForDisconnectOnWakeup] count] == 0  ) {
		TBLog(@"DB-SW", @"willGoToSleepHandler: no configurations to disconnect before sleep")
    } else {
		TBLog(@"DB-SW", @"willGoToSleepHandler: waiting for %lu configurations to disconnect before sleep", (unsigned long)[[self connectionsToWaitForDisconnectOnWakeup] count]);
		[self waitForDisconnection: connectionsToWaitForDisconnectOnWakeup];
		[self setConnectionsToWaitForDisconnectOnWakeup: nil];
		TBLog(@"DB-SW", @"willGoToSleepHandler: configurations have disconnected")
	}
	
    if (  OSAtomicCompareAndSwap32Barrier(gettingReadyForSleep, readyForSleep, &gSleepWakeState)  ) {
		TBLog(@"DB-SW", "willGoToSleepHandler: state = readyForSleep");
	} else {
		NSLog(@"willGoToSleepHandler: Ready to sleep but gSleepWakeState was not 'gettingReadyForSleep' (it is %ld)", (long) gSleepWakeState);
        return;
    }
	
    TBLog(@"DB-SW", @"willGoToSleepHandler: OK to go to sleep")
}

-(void) wokeUpFromSleepHandler: (NSNotification *) n
{
 	(void) n;
    
    if (  gShuttingDownOrRestartingComputer  ) {
		TBLog(@"DB-SW", @"wokeUpFromSleepHandler: ignored because computer is shutting down or restarting");
        return;
    }
    
    [self performSelectorOnMainThread: @selector(wokeUpFromSleep) withObject:nil waitUntilDone:NO];
}

-(void) checkIPAddressAfterSleepingConnectionThread: (NSDictionary *) dict
{
    // This method runs in a separate thread detached by startCheckingIPAddressAfterSleeping
    
    NSAutoreleasePool * threadPool = [NSAutoreleasePool new];
    
	TBLog(@"DB-IT", @"checkIPAddressAfterSleepingConnectionThread invoked")
	
	VPNConnection * connection = [dict objectForKey: @"connection"];
	NSString * threadID = [dict objectForKey: @"threadID"];
	
    NSTimeInterval timeoutToUse = [gTbDefaults timeIntervalForKey: @"timeoutForIPAddressCheckAfterSleeping"
                                                          default: 30.0
                                                              min: 1.0
                                                              max: 60.0 * 3];
	
    uint64_t startTimeNanoseconds = nowAbsoluteNanoseconds();
    
    NSArray * ipInfo = [connection currentIPInfoWithIPAddress: NO timeoutInterval: timeoutToUse];
    
    // Stop here if on cancelling list
    if (   [self isOnCancellingListIPCheckThread: threadID]  ) {
        [self haveFinishedIPCheckThread: threadID];
		TBLog(@"DB-IT", @"checkIPAddressAfterSleepingConnectionThread: cancelled because the thread is on the cancel list")
        [threadPool drain];
        return;
    }
	
	if (  ipInfo  ) {
		if (  [ipInfo count] < 3  ) {
            NSLog(@"After %.1f seconds, gave up trying to fetch IP address information after sleeping", timeoutToUse);
		} else {
			TBLog(@"DB-IT", @"checkIPAddressAfterSleepingConnectionThread: success");
		}

	} else {
        NSLog(@"An error occured fetching IP address information after sleeping");
        uint64_t timeToWaitNanoseconds = [gTbDefaults unsignedIntForKey: @"delayBeforeReconnectingAfterSleepAndIpaFetchError" default: 5 min: 0 max: 600] * 1000000000ull;
        uint64_t timeItTookNanoseconds = nowAbsoluteNanoseconds() - startTimeNanoseconds;
        if (  timeItTookNanoseconds < timeToWaitNanoseconds  ) {
            uint64_t sleepNanoseconds = timeToWaitNanoseconds - timeItTookNanoseconds;
            usleep(sleepNanoseconds/1000);
        }
    }
    
    [self performSelectorOnMainThread: @selector(finishWakingUpFromSleep) withObject: nil waitUntilDone: NO];
	[self haveFinishedIPCheckThread: threadID];
    [threadPool drain];
}

-(void)finishWakingUpFromSleep {
    
	TBLog(@"DB-SW", @"finishWakingUpFromSleep invoked")
	
	NSEnumerator *e = [connectionsToRestoreOnWakeup objectEnumerator];
	VPNConnection *connection;
	while (  (connection = [e nextObject])  ) {
        NSString * name = [connection displayName];
        NSString * key  = [name stringByAppendingString: @"-doNotReconnectOnWakeFromSleep"];
        if (  ! [gTbDefaults boolForKey: key]  ) {
			TBLog(@"DB-SW", @"finishWakingUpFromSleep: Attempting to connect %@", name)
            [connection addToLog: @"*Tunnelblick: Woke up from sleep. Attempting to re-establish connection..."];
            [connection connect:self userKnows: YES];
        } else {
            TBLog(@"DB-SW", @"finishWakingUpFromSleep: Not restoring connection %@ because of '-doNotReconnectOnWakeFromSleep' preference", name)
            [connection addToLog: @"*Tunnelblick: Woke up from sleep. Not attempting to re-establish connection..."];
        }
	}
    
    [self setConnectionsToRestoreOnWakeup: nil];
    
    if (  OSAtomicCompareAndSwap32Barrier(wakingUp, noSleepState, &gSleepWakeState)  ) {
		TBLog(@"DB-SW", "finishWakingUpFromSleep: state = noSleepState");
	} else {
        NSLog(@"finishWakingUpFromSleep: gSleepWakeState was not 'wakingUp' (it is %ld)", (long) gSleepWakeState);
    }
}

-(void) waitAfterSleepTimerHandler: (NSTimer *) timer {
    
    (void) timer;
    [self performSelectorOnMainThread: @selector(finishWakingUpFromSleep) withObject: nil waitUntilDone: NO];
}

-(void)wokeUpFromSleep
{
    // Runs on main thread
    
    if (  gSleepWakeState == gettingReadyForSleep   ) {
		TBLog(@"DB-SW", @"wokeUpFromSleep: being queued to execute again in 0.5 second -- still finishing operations that were started before computer went to sleep");
        [self performSelector: @selector(wokeUpFromSleepHandler:) withObject: nil afterDelay: 0.5];
        return;
    }
    
    if (  OSAtomicCompareAndSwap32Barrier(readyForSleep, wakingUp, &gSleepWakeState)  ) {
		TBLog(@"DB-SW", "wokeUpFromSleep: state = wakingUp");
	} else {
        NSLog(@"wokeUpFromSleep: ignored because gSleepWakeState was not 'gettingReadyForSleep' or 'readyForSleep' (it is %ld)", (long) gSleepWakeState);
        return;
    }
    
    TBLog(@"DB-SW", @"wokeUpFromSleep: Finished all needed activity before computer went to sleep");
    
    if (  [[self connectionsToWaitForDisconnectOnWakeup] count] == 0  ) {
		TBLog(@"DB-SW", @"wokeUpFromSleep: no configurations to disconnect on wakeup")
    } else {
		[self waitForDisconnection: connectionsToWaitForDisconnectOnWakeup];
		[self setConnectionsToWaitForDisconnectOnWakeup: nil];
	}
	
    if (  [[self connectionsToRestoreOnWakeup] count] == 0  ) {
		TBLog(@"DB-SW", @"wokeUpFromSleep: no configurations to reconnect on wakeup, so finished waking up")
		if (  OSAtomicCompareAndSwap32Barrier(wakingUp, noSleepState, &gSleepWakeState)  ) {
			TBLog(@"DB-SW", "wokeUpFromSleep: state = noSleepState");
		} else {
			NSLog(@"wokeUpFromSleep: ignored because gSleepWakeState was not 'wakingUp' (it is %ld)", (long) gSleepWakeState);
			return;
		}
		
    } else {
        
        // See if any connections that we are waking up allow us to check the IP address after connecting
        VPNConnection * connectionToCheckIpAddress = nil;
        
        if (  ! [gTbDefaults boolForKey: @"inhibitOutboundTunneblickTraffic"] ) {
            NSEnumerator *e = [connectionsToRestoreOnWakeup objectEnumerator];
            VPNConnection *connection;
            while (  (connection = [e nextObject])  ) {
                NSString * name = [connection displayName];
                NSString * key  = [name stringByAppendingString: @"-doNotReconnectOnWakeFromSleep"];
                if (  ! [gTbDefaults boolForKey: key]  ) {
                    key = [name stringByAppendingString: @"-notOKToCheckThatIPAddressDidNotChangeAfterConnection"];
                    if (  ! [gTbDefaults boolForKey: key]  ) {
                        connectionToCheckIpAddress = [[connection retain] autorelease];
                        break;
                    }
                }
            }
        }
        
        if (  connectionToCheckIpAddress  ) {
            NSString * threadID = [NSString stringWithFormat: @"%lu-%llu", (long) self, (long long) nowAbsoluteNanoseconds()];
            [self addActiveIPCheckThread: threadID];
            NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                   connectionToCheckIpAddress, @"connection",
                                   threadID,   @"threadID",
                                   nil];
            [NSThread detachNewThreadSelector: @selector(checkIPAddressAfterSleepingConnectionThread:) toTarget: self withObject: dict];
			
            TBLog(@"DB-SW", @"wokeUpFromSleep: exiting; checking IP address to determine connectivity before reconnecting configurations")
        } else {
            unsigned sleepTime = [gTbDefaults unsignedIntForKey: @"delayBeforeReconnectingAfterSleep" default: 5 min: 0 max: 300];
            TBLog(@"DB-SW", @"wokeUpFromSleep: cannot check IP address to determine connectivity so waiting %lu seconds before reconnecting configurations"
                  @" (Time may be specified in the \"delayBeforeReconnectingAfterSleep\" preference", (unsigned long)sleepTime)
            NSTimer * waitAfterWakeupTimer = [NSTimer scheduledTimerWithTimeInterval: (NSTimeInterval) sleepTime
                                                                              target: self
                                                                            selector: @selector(waitAfterSleepTimerHandler:)
                                                                            userInfo: nil
                                                                             repeats: NO];
            [waitAfterWakeupTimer tbSetTolerance: -1.0];
			
			TBLog(@"DB-SW", @"wokeUpFromSleep: exiting; waitAfterSleepTimerHandler: is queued to execute in %lu seconds", (unsigned long)sleepTime);
        }
    }
}

-(void)didBecomeInactiveUserHandler: (NSNotification *) n
{
 	(void) n;
	
   [self performSelectorOnMainThread: @selector(didBecomeInactiveUser) withObject:nil waitUntilDone:NO];
}

-(void)didBecomeInactiveUser
{
	if (  gShuttingDownOrRestartingComputer  ) {
		TBLog(@"DB-SW", @"didBecomeInactiveUser: ignored because computer is shutting down or restarting");
        return;
    }
    
    if (  OSAtomicCompareAndSwap32Barrier(active, gettingReadyForInactive, &gActiveInactiveState)  ) {
		TBLog(@"DB-SW", "didBecomeInactiveUser: state = gettingReadyForInactive");
	} else {
		NSLog(@"didBecomeInactiveUser: ignored because gActiveInactiveState was not 'active' (it is %ld)", (long) gActiveInactiveState);
        return;
    }
    
    terminatingAtUserRequest = TRUE;
    
	TBLog(@"DB-SW", @"didBecomeInactiveUser: Setting up to become an inactive user")
	
    // For each open connection, either reInitialize it or start disconnecting it
    // Remember connections that should be restored if/when we become the active user
    [self setConnectionsToRestoreOnUserActive: [[[NSMutableArray alloc] initWithCapacity: 10] autorelease]];
    NSMutableArray * disconnectionsWeAreWaitingFor = [[[NSMutableArray alloc] initWithCapacity: 10] autorelease];
	VPNConnection * connection;
    NSEnumerator * e = [[self myVPNConnectionDictionary] objectEnumerator];
	while (  (connection = [e nextObject])  ) {
        if (   [connection shouldDisconnectWhenBecomeInactiveUser]
            && ( ! [connection isDisconnected])  ) {
            [connection addToLog: @"*Tunnelblick: Disconnecting; user became inactive"];
            [connection startDisconnectingUserKnows: [NSNumber numberWithBool: YES]];
            [disconnectionsWeAreWaitingFor addObject: connection];
            NSString * key = [[connection displayName] stringByAppendingString: @"-doNotReconnectOnFastUserSwitch"];
            if (  ! [gTbDefaults boolForKey: key]  ) {
                [connectionsToRestoreOnUserActive addObject: connection];
				TBLog(@"DB-SW", "didBecomeInactiveUser: started disconnecting %@; will reconnect when become active user", [connection displayName]);
            } else {
				TBLog(@"DB-SW", "didBecomeInactiveUser: started disconnecting %@; will not reconnect when become active user", [connection displayName]);
			}
        } else {
            [connection addToLog: @"*Tunnelblick: Stopping communication with OpenVPN because user became inactive"];
            [connection reInitialize];
			if (  ! [connection isDisconnected]  ) {
				TBLog(@"DB-SW", "didBecomeInactiveUser: stopping communication with OpenVPN for %@ because user became inactive", [connection displayName]);
			}
		}
    }
    
    // Indicate no configurations have connected since user became active
    // Done here so it is correct immediately when the user becomes active again
    [self performSelectorOnMainThread: @selector(clearAllHaveConnectedSince) withObject: nil waitUntilDone: YES];
    
    [self waitForDisconnection: disconnectionsWeAreWaitingFor];
	
    if (  OSAtomicCompareAndSwap32Barrier(gettingReadyForInactive, readyForInactive, &gActiveInactiveState)  ) {
		TBLog(@"DB-SW", "didBecomeInactiveUser: state = readyForInactive");
	} else {
		NSLog(@"didBecomeInactiveUser: cannot set readyForActive because gActiveInactiveState was not 'gettingReadyForInactive' (it is %ld)", (long) gActiveInactiveState);
    }
}

-(void)didBecomeActiveUserHandler: (NSNotification *) n
{
	(void) n;
	
    [self performSelectorOnMainThread: @selector(didBecomeActiveUser) withObject:nil waitUntilDone:NO];
}

-(void)didBecomeActiveUser
{
	TBLog(@"DB-SW", @"didBecomeActiveUser: entered")
	
	if (  gActiveInactiveState == active  ) {
		TBLog(@"DB-SW", @"didBecomeActiveUser: ignored because already active");
		return;
	}
	
    if (  gActiveInactiveState != readyForInactive   ) {
		TBLog(@"DB-SW", @"didBecomeActiveUser: being queued to execute again in 0.5 second -- still finishing operations that were started before user became inactive");
        [self performSelector: @selector(didBecomeActiveUser) withObject: nil afterDelay: 0.5];
        return;
    }
    
    if (  OSAtomicCompareAndSwap32Barrier(readyForInactive, gettingReadyforActive, &gActiveInactiveState)  ) {
		TBLog(@"DB-SW", "didBecomeActiveUser: state = gettingReadyforActive");
	} else {
        NSLog(@"didBecomeActiveUser: ignored because gActiveInactiveState was not 'readyForInactive' (it is %ld)", (long) gActiveInactiveState);
        return;
    }
    
    [self hookupToRunningOpenVPNs];
    if (  [self setupHookupWatchdogTimer]  ) {
		TBLog(@"DB-SW", "didBecomeActiveUser: hooking up to running OpenVPN processes; will check for recconnections afterward");
        return; // reconnectAfterBecomeActiveUser will be done when the hookup timer times out or there are no more hookups pending
    }
    
    // Wait a second to give hookups a chance to happen, then restore connections after processing the hookups
    sleep(1);   
    
    [self performSelectorOnMainThread: @selector(reconnectAfterBecomeActiveUser) withObject: nil waitUntilDone: YES];
}

-(void)reconnectAfterBecomeActiveUser
{
    // Reconnect configurations that were connected before this user was switched out and that aren't connected now
	
	if (  [[self connectionsToRestoreOnUserActive] count] == 0  ) {
		TBLog(@"DB-SW", "reconnectAfterBecomeActiveUser: Nothing to reconnect after becoming active");
	} else {
		NSEnumerator * e = [[self connectionsToRestoreOnUserActive] objectEnumerator];
		VPNConnection * connection;
		while (  (connection = [e nextObject])  ) {
			if (  ! [connection isHookedup]  ) {
				[connection stopTryingToHookup];
				[connection addToLog: @"*Tunnelblick: Attempting to reconnect because user became active"];
				[connection connect: self userKnows: YES];
				TBLog(@"DB-SW", "reconnectAfterBecomeActiveUser: Attempting to reconnect '%@' because user became active", [connection displayName]);
			}
		}
	}
	
    [self setConnectionsToRestoreOnUserActive: nil];
	
	if (  gActiveInactiveState != active  ) {
		if (  OSAtomicCompareAndSwap32Barrier(gettingReadyforActive, active, &gActiveInactiveState)  ) {
			TBLog(@"DB-SW", "reconnectAfterBecomeActiveUser: state = active");
		} else {
			NSLog(@"reconnectAfterBecomeActiveUser: warning: gActiveInactiveState was not 'gettingReadyforActive' (it is %ld)", (long) gActiveInactiveState);
		}
	}
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
	(void) userData;
	
    // When the hotKey is pressed, pop up the Tunnelblick menu from the Status Bar
    MenuController * menuC = ((MenuController *)[NSApp delegate]);
	NSStatusBarButton * statusButton = [menuC statusItemButton];
	if (  statusButton  ) {
		[statusButton performClick: nil];
	} else {
		NSStatusItem * statusI = [menuC statusItem];
		[statusI popUpStatusItemMenu: [menuC myVPNMenu]];
	}
	
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

-(void) statisticsWindowsShow: (BOOL) showThem {

	TBLog(@"DB-MO", @"statisticsWindowsShow: %s entered", CSTRING_FROM_BOOL(showThem));
    NSEnumerator * e = [myVPNConnectionDictionary objectEnumerator];
    VPNConnection * connection;
    BOOL showingAny = FALSE;
    while (  (connection = [e nextObject])  ) {
        if (  [connection logFilesMayExist]  ) {
            if (  showThem  ) {
                if (   (! [gTbDefaults boolForKey: @"doNotShowDisconnectedNotificationWindows"])
                    || ( ! [connection isDisconnected])  ) {
                    [connection showStatusWindowForce: NO];
					TBLog(@"DB-MO", @"statisticsWindowsShow: requested show of status window for %@ because log files may exist for it", [connection displayName]);
                    showingAny = TRUE;
                }
            } else {
                if (   [connection isConnected]
                    || [connection isDisconnected]  ) {
                    [connection fadeAway];
					TBLog(@"DB-MO", @"statisticsWindowsShow: requested fade of status window for %@ because it is connected or disconnected", [connection displayName]);
                }
            }
        }
    }
    
    // If not showing any window yet because nothing is connected, show the window for the last-selected connection
    // or for the first connection on the list if the last-selected connection doesn't exist
    if (   showThem
        && (! showingAny)
        && (! [gTbDefaults boolForKey: @"doNotShowDisconnectedNotificationWindows"])  ) {
        NSString * lastConnectionName = [gTbDefaults stringForKey: @"lastConnectedDisplayName"];
        VPNConnection * lastConnection = nil;
        if (  lastConnectionName  ) {
            lastConnection = [myVPNConnectionDictionary objectForKey: lastConnectionName];
        }
        if (  ! lastConnection  ) {
            NSArray * sortedDisplayNames = [[myConfigDictionary allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveNumericCompare:)];
            if (  [sortedDisplayNames count] > 0  ) {
                lastConnection = [myVPNConnectionDictionary objectForKey: [sortedDisplayNames objectAtIndex: 0]];
            }
        }
        if (  lastConnection  ) {
            [lastConnection showStatusWindowForce: NO];
			[lastConnection setLogFilesMayExist: TRUE];
			TBLog(@"DB-MO", @"statisticsWindowsShow: requested show of status window for %@ because no other status windows are showing", [lastConnection displayName]);
        }
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

//*********************************************************************************************************
// IPCheckThread methods:

static pthread_mutex_t threadIdsMutex = PTHREAD_MUTEX_INITIALIZER;

-(void) addActiveIPCheckThread: (NSString *) threadID
{
    OSStatus status = pthread_mutex_lock( &threadIdsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &threadIdsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
        return;
    }
    
    [activeIPCheckThreads addObject: threadID];
    TBLog(@"DB-IT", @"addActiveIPCheckThread: threadID '%@' added to the active list", threadID)
    
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
            TBLog(@"DB-IT", @"cancelIPCheckThread: threadID '%@' removed from the active list and added to the cancelling list", threadID)
        } else {
            NSLog(@"cancelIPCheckThread: ERROR: threadID '%@' is on both the active and cancelling lists! Removing from active list", threadID);
            [activeIPCheckThreads removeObject: threadID];
        }
    } else {
        if (  [cancellingIPCheckThreads containsObject: threadID]  ) {
            TBLog(@"DB-IT", @"cancelIPCheckThread: threadID '%@' is already on the cancelling list!", threadID)
        } else {
            NSLog(@"cancelIPCheckThread: ERROR: threadID '%@' is not in the active or cancelling list! Added it to cancelling list", threadID);
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

    TBLog(@"DB-IT", @"cancelAllIPCheckThreadsForConnection: No active threads for connection %lu", (long) connection)
    
    // Then cancel them. (This avoids changing the list while we enumerate it.)
    e = [threadsToCancel objectEnumerator];
    while (  (threadID = [e nextObject])  ) {
        if (  [activeIPCheckThreads containsObject: threadID]  ) {
            if (  ! [cancellingIPCheckThreads containsObject: threadID]  ) {
                [activeIPCheckThreads removeObject: threadID];
                [cancellingIPCheckThreads addObject: threadID];
                TBLog(@"DB-IT", @"cancelAllIPCheckThreadsForConnection: threadID '%@' removed from the active list and added to the cancelling list", threadID)

            } else {
                NSLog(@"cancelAllIPCheckThreadsForConnection: ERROR: threadID '%@' is on both the active and cancelling lists! Removing from active list", threadID);
                [activeIPCheckThreads removeObject: threadID];
            }
        } else {
            if (  [cancellingIPCheckThreads containsObject: threadID]  ) {
                NSLog(@"cancelAllIPCheckThreadsForConnection: ERROR: threadID '%@' is already on the cancelling list!", threadID);
            } else {
                NSLog(@"cancelAllIPCheckThreadsForConnection: ERROR: threadID '%@' is not in the active or cancelling list! Added it to cancelling list", threadID);
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
        TBLog(@"DB-IT", @"isOnCancellingListIPCheckThread: threadID '%@' is on the cancelling list", threadID)
        ;
    } else {
        TBLog(@"DB-IT", @"isOnCancellingListIPCheckThread: threadID '%@' is not on the cancelling list", threadID)
        ;
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
    
	BOOL removedFromOneOfTheLists = FALSE;
	
    if (  [activeIPCheckThreads containsObject: threadID]  ) {
        TBLog(@"DB-IT", @"haveFinishedIPCheckThread: threadID '%@' removed from active list", threadID)
        [activeIPCheckThreads removeObject: threadID];
		removedFromOneOfTheLists = TRUE;
    }
    
    if (  [cancellingIPCheckThreads containsObject: threadID]  ) {
        TBLog(@"DB-IT", @"haveFinishedIPCheckThread: threadID '%@' removed from cancelling list", threadID)
        [cancellingIPCheckThreads removeObject: threadID];
		removedFromOneOfTheLists = TRUE;
    }
    
	if (  ! removedFromOneOfTheLists  ) {
		TBLog(@"DB-IT", @"haveFinishedIPCheckThread: threadID '%@' was not on the active list or the cancelling list", threadID)
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
                     [self localizedNameForDisplayName: displayName]],
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
            [connection addToLog: @"*Tunnelblick: Disconnecting; notification window disconnect button pressed"];
			NSString * oldRequestedState = [connection requestedState];
			[connection startDisconnectingUserKnows: [NSNumber numberWithBool: YES]];
			if (  [oldRequestedState isEqualToString: @"EXITING"]  ) {
				[connection displaySlowDisconnectionDialogLater];
			}
        } else if (  choice == statusWindowControllerConnectChoice  ) {
            [connection addToLog: @"*Tunnelblick: Connecting; notification window connect button pressed"];
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
		TBLog(@"DB-MO", @"showStatisticsWindowsTimerHandler: mouse still inside a view; queueing showStatisticsWindows");
    } else {
		TBLog(@"DB-MO", @"showStatisticsWindowsTimerHandler: mouse no longer inside a view; NOT queueing showStatisticsWindows");
	}
}

-(void) hideStatisticsWindowsTimerHandler: (NSTimer *) theTimer {
    // Event handler; NOT on MainThread
    
	(void) theTimer;
	
    if (  gShuttingDownWorkspace  ) {  // Don't do anything if computer is shutting down or restarting
        return;
    }
    
    if (  ! [self mouseIsInsideAnyView]  ) {
        [self performSelectorOnMainThread: @selector(hideStatisticsWindows) withObject: nil waitUntilDone: NO];
		TBLog(@"DB-MO", @"hideStatisticsWindowsTimerHandler: mouse NOT back inside a view; queueing hideStatisticsWindows");
    } else {
		TBLog(@"DB-MO", @"hideStatisticsWindowsTimerHandler: mouse is back inside a view; NOT queueing hideStatisticsWindows");
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
        timeUntilAct = 0.1;
    } else {
        uint64_t nowNanoseconds = nowAbsoluteNanoseconds();
        NSTimeInterval nowTimeInterval = (  ((NSTimeInterval) nowNanoseconds) / 1.0e9  );
        timeUntilAct = timestamp + delay - nowTimeInterval;
		TBLog(@"DB-MO", @"showOrHideStatisticsWindowsAfterDelay: delay = %f; timestamp = %f; nowNanoseconds = %llu; nowTimeInterval = %f; timeUntilAct = %f", delay, timestamp, (unsigned long long) nowNanoseconds, nowTimeInterval, timeUntilAct);
		if (  timeUntilAct < 0.1) {
			timeUntilAct = 0.1;
		}
    }
    
	TBLog(@"DB-MO", @"Queueing %s in %f seconds", sel_getName(selector), timeUntilAct);
    NSTimer * timer = [NSTimer scheduledTimerWithTimeInterval: timeUntilAct
                                                       target: self
                                                     selector: selector
                                                     userInfo: nil
                                                      repeats: NO];
    [timer tbSetTolerance: -1.0];
}

-(void) mouseEnteredMainIcon: (id) control event: (NSEvent *) theEvent  {
    // Event handlers invoke this; NOT on MainThread

	(void) control;
	
    if (  gShuttingDownWorkspace  ) {
        return;
    }
        
	TBLog(@"DB-MO", @"Mouse entered main icon");
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
    
	TBLog(@"DB-MO", @"Mouse exited main icon");
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
    
	TBLog(@"DB-MO", @"Mouse entered status window");
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
    
	TBLog(@"DB-MO", @"Mouse exited status window");
    mouseIsInStatusWindow = FALSE;
    [self showOrHideStatisticsWindowsAfterDelay: gDelayToHideStatistics
                                  fromTimestamp: ( theEvent ? [theEvent timestamp] : 0.0)
                                       selector: @selector(hideStatisticsWindowsTimerHandler:)];
}

@end
