/*
 * Copyright 2004, 2005, 2006, 2007, 2008, 2009 Angelo Laub
 * Contributions by Dirk Theisen, Jens Ohlig, Waldemar Brodkorb
 * Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021. All rights reserved.
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

/* MenuController */

#import <Carbon/Carbon.h>
#import <Security/Security.h>

#import "defines.h"


@class ConfigurationMultiUpdater;
@class MainIconView;
@class MyPrefsWindowController;
@class NetSocket;
@class SplashWindowController;
@class StatusWindowController;
@class SUUpdater;
@class SystemAuth;
@class TBUIUpdater;
@class TBUpdater;
@class VPNConnection;
@class WelcomeController;

#ifdef INCLUDE_VPNSERVICE
@class VPNService;
#endif


enum TerminationReason {
    terminatingForUnknownReason    = 0,
    terminatingBecauseOfLogout     = 1,
    terminatingBecauseOfShutdown   = 2,
    terminatingBecauseOfRestart    = 3,
    terminatingBecauseOfQuit       = 4,
    terminatingBecauseOfError      = 5,
    terminatingBecauseOfFatalError = 6,
	terminatingBecauseOfUpdate     = 7
};

enum SleepWakeState {
    noSleepState         = 0,
    gettingReadyForSleep = 1,
    readyForSleep        = 2,
    wakingUp             = 3
};

enum ActiveInactiveState {
    active                  = 0,
    gettingReadyForInactive = 1,
    readyForInactive        = 2,
    gettingReadyforActive   = 3
};

@interface NSStatusBar (NSStatusBar_Private)
- (nullable id)_statusItemWithLength:(CGFloat)l withPriority:(long long)p;
- (nullable id)_insertStatusItem:(nonnull NSStatusItem *)i withPriority:(long long)p;
@end

@interface MenuController : NSObject <NSAnimationDelegate,NSMenuDelegate,NSUserNotificationCenterDelegate>

{
    IBOutlet NSMenu         * myVPNMenu;                    // Tunnelblick's menu, displayed in Status Bar
	NSArray                 * cachedMenuItems;				// Cached copy of configuration items and folders for menu
    NSStatusItem            * statusItem;                   // Our place in the Status Bar
    NSStatusBarButton       * statusItemButton;             // Or nil if not on 10.10 or higher
    MainIconView            * ourMainIconView;              // View for the main icon
    IBOutlet NSMenuItem     * statusMenuItem;               // First line of menu, displays status (e.g. "Tunnelblick: 1 connection active"
    NSMenuItem              * noConfigurationsItem;         // Displayed if there are no configurations installed
	NSMenuItem              * reenableInternetItem;         // "Re-enable Network Access" item for menu
    NSMenuItem              * tbUpdateAvailableItem;        // Displayed iff there is a Tunnelblick update available
    NSMenuItem              * configUpdateAvailableItem;    // Displayed iff there is a configuration update available
    NSMenuItem              * warningsItem;                 // "Warnings..." item for menu
    NSMenuItem              * vpnDetailsItem;               // "VPN Details..." item for menu
    NSMenuItem              * addConfigurationItem;         // "Add a VPN..." menu item
    NSMenuItem              * contactTunnelblickItem;       // "Contact Tunnelblick..." menu item (if beta version)
    
#ifdef INCLUDE_VPNSERVICE
    NSMenuItem              * registerForTunnelblickItem;//    "Register for Tunnelblick..." menu item
#endif
    
    NSMenuItem              * quitItem;                     // "Quit Tunnelblick" item for menu

    NSArray                 * screenList;                   // Array of NSDictionaries with info about each display screen
    
    NSAnimation             * theAnim;                      // For animation of the Tunnelblick icon in the Status Bar
	
    NSMutableArray          * animImages;                   // Images for animation of the Tunnelblick icon in the Status Bar
    NSImage                 * connectedImage;               // Image to display when one or more connections are active
    NSImage                 * mainImage;                    // Image to display when there are no connections active

    NSMutableArray          * highlightedAnimImages;        // Corresponding highlighted images (the large images are never highlighted)
    NSImage                 * highlightedConnectedImage;
    NSImage                 * highlightedMainImage;
	
    NSMutableArray          * largeAnimImages;              // Images for animation of the Tunnelblick icon in the Status Window
    NSImage                 * largeConnectedImage;          // Image to display when one or more connections are active
    NSImage                 * largeMainImage;               // Image to display when there are no connections active
    
    SystemAuth              * startupInstallAuth;           // Authorization when starting up Tunnelblick
    
    MyPrefsWindowController * logScreen;                    // Log window ("VPN Details..." window)
    
    SplashWindowController * splashScreen;                 // Splash window (used for install also)
    
	NSArray					* knownPublicDnsServerAddresses; // Strings of IPv4 or IPv6 addresses, parsed from Resources/FreePublicDnsServersList.txt
	
    NSMutableArray          * dotTblkFileList;              // Array of paths to .tblk files that should be "opened" (i.e., installed) when we're finished launching
    
    NSDictionary            * myConfigDictionary;           // List of all configurations. key = display name, value = path to .tblk package

    NSDictionary            * myVPNConnectionDictionary;    // List of all VPNConnections. key = display name, value = VPNConnection object for the configuration
    
    NSArray                 * connectionArray;              // VPNConnections that are currently connected
    NSArray                 * nondisconnectedConnections;   // VPNConnections that are currently not disconnected (any with status != EXITING)
    
    NSMutableArray          * connectionsToRestoreOnWakeup; // VPNConnections to be restored when awakened from sleep
    
    NSMutableArray          * connectionsToRestoreOnUserActive; // VPNConnections to be restored when user becomes active again
    
    NSMutableArray          * connectionsToWaitForDisconnectOnWakeup; // VPNConnections to be waited for disconnection from when awakened from sleep
    
    NSMutableArray          * pIDsWeAreTryingToHookUpTo;    // List of process IDs for processes we are trying to hookup to
    
    NSMutableArray          * activeIPCheckThreads;         // List of threadIDs of active IPCheck threads that have not been queued for cancellation
    NSMutableArray          * cancellingIPCheckThreads;     // List of threadIDs of IPCheck threads that have been queued for cancellation

    NSMutableDictionary     * warningNotes;                 // One entry for each pending warning, keys are strings with integers

    NSString                * lastState;                    // Most recent state of connection (EXITING, SLEEP, etc.)
    
	NSString                * publicIPAddress;				// Apparent public IP address

	NSString				* openVPNLogHeader;				// Header for OpenVPN logs: macOS version, Tunnelblick version, previous Tunnelblick version
	
    TBUIUpdater             * uiUpdater;                    // Used to periodically update displays
	
    NSTimer                 * hookupWatchdogTimer;          // Used to check for failures to hookup to openvpn processes, and deal with unknown OpenVPN processes 
	
    NSTimer                 * statisticsWindowTimer;        // Used to check for stale statistics that must be cleared 
    
    TBUpdater               * tbupdater;                    // TBUpdater item used to check for updates to the program
    NSDate                  * lastCheckNow;                 // Date/time Check Now button was last clicked

    ConfigurationMultiUpdater * myConfigMultiUpdater;       // Checks for configuration updates
	
	NSString                * languageAtLaunch;				// Lower-case version of the language we are using. Passed on to runOnConnect, runOnLaunch, and Menu command scripts
    
    NSTrackingRectTag         iconTrackingRectTag;          // Used to track mouseEntered and mouseExited events for statusItemButton
    
	BOOL					  languageAtLaunchWasRTL;		// Used to load RTL xibs and adjust spacing of controls as needed
	
    BOOL volatile             launchFinished;               // Flag that we have executed "applicationDidFinishLaunching"
    
    BOOL                      checkingForNoConfigs;         // Used to avoid infinite recursion
    
    BOOL                      noUnknownOpenVPNsRunning;     // Indicates that no unknown OpenVPN processes were left running after the TB launch
    //                                                         and therefore we can safely terminate unknown OpenVPN processes when quitting TB
    
    BOOL                      showingConfirmIconNearSpotlightIconDialog;
    
    BOOL                      terminatingAtUserRequest;     // Indicates that we are terminating because the user Quit or Command-Q-ed
    
    BOOL volatile             mouseIsInMainIcon;            // Indicates that the mouse is over the Tunnelblick (not tracked unless preference says to)
    BOOL volatile             mouseIsInStatusWindow;        // Indicates that the mouse is over the icon or a status window
    
	BOOL					  signatureIsInvalid;			// Indicates the app is digitally signed but the signature does not check out
	
	BOOL volatile             doingSetupOfUI;				// Indicates we are setting up the UI, and not making changes to preferences
	
	BOOL volatile             menuIsOpen;					// Indicates the main Tunnelblick menu is open

	BOOL					  quittingAfterAnInstall;		// Used to control cleanup: after an install
	
	BOOL					  haveClearedQuitLog;

	BOOL					  showingImportSetupWindow;		// True iff we are actively importing a .tblksetup

	BOOL					  didFinishLaunching;			// True if Tunnelblick has been secured or installed securely (user didn't cancel install)
    unsigned                  tapCount;                     // # of instances of openvpn that are using our tap kext
    unsigned                  tunCount;                     // # of instances of openvpn that are using our tun kext
    
    BOOL                      tbUpdatesAreAvailable;        // True if updates to the program are available
    double                  tbUpdatePercentageDownloaded; // Percent of a program update that TBUpdater has downloaded

    BOOL                      configUpdatesAreAvailable;    // True if updates to a VPN configuration are available

    BOOL                      hotKeyEventHandlerIsInstalled;// The event handler for the hot key (keyboard shortcut to pop up the Tunnelblick menu) has been installed
    EventHotKeyRef            hotKeyRef;                    // Reference for the current hot key
    UInt32                    hotKeyKeyCode;                // Current hot key: Virtual key code
    UInt32                    hotKeyModifierKeys;           //                  Modifier keys code or 0 to indicate no hot key active
    unsigned                  hotKeyCurrentIndex;           // Index of the hot key that is currently in use (0 = none, else 1...MAX_HOTKEY_IX)

    NSMutableArray          * customMenuScripts;            // Array of paths to the scripts for custom menu items
    int                       customMenuScriptIndex;        // Index used while building the customMenuScripts array
    NSString                * customRunOnLaunchPath;        // Path of a file to be executed before processing "connect when Tunnelblick launches" configurations
    NSString                * customRunOnConnectPath;       // Path of a file to be executed before making a connection
    
    WelcomeController       * welcomeScreen;                // Controller for welcome window
    
	NSBundle                * deployLocalizationBundle;	    // Bundle for Deploy/Localization.bundle
	
#ifdef INCLUDE_VPNSERVICE
    VPNService              * vpnService;                   // VPNService object. if it responds to doVPNService, doVPNService is invoked at end of
    //                                                      // application:didFinishLaunching. The object persists until Tunnelblick terminates
    
    NSString                * vpnServiceConnectDisplayName; // Display name of connection that VPNService is trying to connect
#endif
}

-(void) tbUpdateIsAvailable: (nonnull NSNumber *) isAvailable;
-(void) tbUpdateErrorOccurredInAppUpdate: (nonnull NSNumber *) inAppUpdate;
-(void) tbUpdateDownloadCompletePercentage: (double) percentage;
-(void) tbUpdateWillInstallUpdate;
-(void) tbUpdateDidInstallUpdate;
-(void) tbUpdaterFailedToInstallUpdate;

// Used to implement drag/drop of configuration files onto the Tunnelblick icon in the status bar or the configuration list in the 'VPN Details' window
-(BOOL)             openFiles:                              (nonnull NSArray * )        filePaths;

// Menu actions
-(IBAction)         openPreferencesWindow:                  (nonnull id)                sender;
-(IBAction)         quit:                                   (nonnull id)                sender;

-(void) addWarningNote: (nonnull NSDictionary *) dict;

-(void)             addWarningNoteWithHeadline:             (nonnull NSString *)            headline
                                       message:             (nonnull NSAttributedString *)  message
                                 preferenceKey:             (nullable NSString *)            preferenceKey;

-(void)             removeWarningNoteAtIndex:               (nonnull NSString *)        index;

// General methods
-(void)             addConnection:                          (nonnull VPNConnection *)   connection;
-(void)             addNonconnection:                       (nonnull VPNConnection *)   connection;
-(void)             setBooleanPreferenceForSelectedConnectionsWithKey: (nonnull NSString *)	key
																   to: (BOOL)       newValue
															 inverted: (BOOL)		inverted;
-(void)             activateIgnoringOtherApps;
-(void)             myReplyToOpenOrPrint:                   (nonnull NSNumber *)        delegateNotifyValue;
-(BOOL)				askAndMaybeReenableNetworkAccessTryingToConnect;
-(void)             recreateMenu;
-(void)             recreateMainMenuClearCache:				(BOOL)				clearCache;
-(void)             changedDisplayConnectionTimersSettings;
-(void)             checkForUpdates:                        (nonnull id)                sender;
-(BOOL)             cleanup;
-(void)             configurationsChanged;
-(void)             configurationsChangedForceLeftNavigationUpdate;
-(nonnull NSArray *)connectionsNotDisconnected;
-(void)             connectionStateDidChange:                  (nonnull VPNConnection *)              connection;
-(nullable VPNConnection *) connectionForDisplayName:               (nonnull NSString *)         displayName;
-(unsigned)         decrementTapCount;
-(nullable NSURL *) getIPCheckURL;
-(nonnull NSNumber *)       haveConfigurations;
-(void)             installConfigurationsUpdateInBundleAtPathMainThread: (nonnull NSString *)path;
-(unsigned)         decrementTunCount;
-(unsigned)         incrementTapCount;
-(unsigned)         incrementTunCount;
-(void)             installOrUninstallKexts;
-(BOOL)             loadMenuIconSet;
-(BOOL)             loadMenuIconSet:                        (NSString * _Nonnull) iconSetName
                               main:                        (NSImage * _Nonnull * _Nonnull) ptrMainImage
                         connecting:                        (NSImage * _Nonnull * _Nonnull)ptrConnectedImage
                               anim:                        (NSMutableArray * _Nonnull * _Nonnull) ptrAnimImages;
-(nonnull NSString *)       localizedNameForDisplayName:            (nonnull NSString *)        displayName;
-(nonnull NSString *)       localizedNameforDisplayName:            (nonnull NSString *)        displayName
                                       tblkPath:            (nonnull NSString *)        tblkPath;
-(void)             mouseEnteredMainIcon:                   (nonnull id)                control
                                   event:                   (nullable NSEvent *)         theEvent;
-(void)             mouseExitedMainIcon:                    (nonnull id)                windowController
                                  event:                    (nullable NSEvent *)         theEvent;
-(void)             mouseEnteredStatusWindow:               (nonnull id)                control
                                       event:               (nullable NSEvent *)         theEvent;
-(void)             mouseExitedStatusWindow:                (nonnull id)                windowController
                                      event:                (nullable NSEvent *)         theEvent;
-(BOOL)             mouseIsInsideAnyView;
-(void)             openvpnConfigurationFileChangedForDisplayName: (nonnull NSString *) displayName;
-(nonnull NSString *)       openVPNLogHeader;
-(nullable NSString *)		openvpnVersionToUseInsteadOfVersion: (nonnull NSString *) prefVersion;
-(void)             reactivateTunnelblick;
-(void)             reconnectAfterBecomeActiveUser;
-(void)             removeConnection:                       (nonnull VPNConnection *)   connection;
-(NSInteger)        runInstaller: (unsigned)           installFlags
                  extraArguments: (nullable NSArray *)          extraArguments
                 usingSystemAuth: (nullable SystemAuth *)       auth
                    installTblks: (nullable NSArray *)          tblksToInstall;
-(void)             saveConnectionsToRestoreOnRelaunch;
-(void)             setHotKeyIndex:                         (unsigned)          newIndex;
-(void)             setState:                               (nonnull NSString *)        newState;
-(void)             setPreferenceForSelectedConfigurationsWithDict: (nonnull NSDictionary * ) dict;
-(void)             setupUpdaterAutomaticChecks;
-(BOOL)             shouldInstallConfigurations: (nonnull NSArray *) filePaths
                                withTunnelblick: (BOOL) withTunnelblick;
-(nullable NSArray *)        sortedSounds;
-(unsigned)         statusScreenIndex;
-(void)             updateSettingsHaveChanged;
-(void)				uninstall;
-(void)             unloadKextsForce: (BOOL) force;
-(void)				updateMenuAndDetailsWindowForceLeftNavigation: (BOOL) forceLeftNavigationUpdate;
-(void)             startCheckingForConfigurationUpdates;
-(void)             statusWindowController:                 (nonnull id)                ctl
                        finishedWithChoice:                 (StatusWindowControllerChoice) choice
                            forDisplayName:                 (nonnull NSString *)        theName;
-(void)             showStatisticsWindows;
-(void)             hideStatisticsWindows;
-(nonnull NSDictionary *)   tunnelblickInfoDictionary;
-(void)             updateIconImage;
-(void)             updateUI;
-(void)             terminateBecause:                       (enum TerminationReason) reason;
-(void) welcomeOKButtonWasClicked;

-(void) addActiveIPCheckThread: (nonnull NSString *) threadID;
-(void) cancelIPCheckThread: (nonnull NSString *) threadID;
-(void) cancelAllIPCheckThreadsForConnection: (nonnull VPNConnection *) connection;
-(BOOL) isOnCancellingListIPCheckThread: (nonnull NSString *) threadID;
-(void) haveFinishedIPCheckThread: (nonnull NSString *) threadID;

-(void) renameConfigurationUsingConfigurationManager: (nonnull NSDictionary *) dict;
-(void) renameConfigurationFolderUsingConfigurationManager: (nonnull NSDictionary *) dict;
-(void) moveOrCopyOneConfigurationUsingConfigurationManager: (nonnull NSDictionary *) dict;

// AppleScript support

-(BOOL)             application:                            (nonnull NSApplication *)   sender
             delegateHandlesKey:                            (nonnull NSString *)        key;
-(nullable NSArray *)        applescriptConfigurationList;

// Getters and Setters

-(nullable NSArray *)        animImages;
-(nullable NSImage *)        connectedImage;
-(nullable NSImage *)        mainImage;
-(nullable NSMutableArray *) largeAnimImages;
-(nullable NSImage *)        largeConnectedImage;
-(nullable NSImage *)        largeMainImage;
-(nullable MyPrefsWindowController *) logScreen;
-(nullable NSString *)       customRunOnConnectPath;
-(void)             startOrStopUiUpdater;
-(BOOL)             terminatingAtUserRequest;
-(BOOL volatile)    doingSetupOfUI;
-(void)				setDoingSetupOfUI: (BOOL) value;

#ifdef INCLUDE_VPNSERVICE
// VPNService support
-(IBAction)         registerForTunnelblickWasClicked:       (id)                sender;
-(BOOL)             tryToConnect:                           (NSString *)        displayName;
-(VPNService *)     vpnService;
-(NSString *)       vpnServiceConnectDisplayName;
-(void)             setVPNServiceConnectDisplayName:        (NSString *)        newValue;
#endif

TBPROPERTY_READONLY(nullable NSStatusItem *, statusItem)
TBPROPERTY_READONLY(BOOL volatile, menuIsOpen)
TBPROPERTY_READONLY(BOOL volatile, launchFinished)
TBPROPERTY_READONLY(BOOL         , languageAtLaunchWasRTL)
TBPROPERTY_READONLY(nullable NSMenu *,		myVPNMenu)
TBPROPERTY_READONLY(nullable NSMutableArray *, activeIPCheckThreads)
TBPROPERTY_READONLY(nullable NSMutableArray *, cancellingIPCheckThreads)
TBPROPERTY_READONLY(nullable ConfigurationMultiUpdater *, myConfigMultiUpdater)
TBPROPERTY_READONLY(nullable NSArray *, knownPublicDnsServerAddresses)
TBPROPERTY_READONLY(nullable TBUpdater *, tbupdater)

TBPROPERTY(nullable SystemAuth   *, startupInstallAuth,        setStartupInstallAuth)
TBPROPERTY(nullable NSArray      *, cachedMenuItems,			  setCachedMenuItems)
TBPROPERTY(nullable NSArray      *, screenList,                setScreenList)
TBPROPERTY(nullable MainIconView *, ourMainIconView,           setOurMainIconView)
TBPROPERTY(nullable NSDictionary *, myVPNConnectionDictionary, setMyVPNConnectionDictionary)
TBPROPERTY(nullable NSDictionary *, myConfigDictionary,        setMyConfigDictionary)
TBPROPERTY(nullable NSArray      *, connectionArray,           setConnectionArray)
TBPROPERTY(nullable NSArray      *, nondisconnectedConnections,setNondisconnectedConnections)
TBPROPERTY(nullable NSTimer      *, hookupWatchdogTimer,       setHookupWatchdogTimer)
TBPROPERTY(nullable TBUIUpdater  *, uiUpdater,                 setUiUpdater)
TBPROPERTY(nullable NSTimer      *, statisticsWindowTimer,     setStatisticsWindowTimer)
TBPROPERTY(nullable NSMutableArray *, highlightedAnimImages,   setHighlightedAnimImages)
TBPROPERTY(nullable NSImage      *, highlightedConnectedImage, setHighlightedConnectedImage)
TBPROPERTY(nullable NSImage      *, highlightedMainImage,      setHighlightedMainImage)
TBPROPERTY(nullable NSMutableArray *, connectionsToRestoreOnUserActive, setConnectionsToRestoreOnUserActive)
TBPROPERTY(nullable NSMutableArray *, connectionsToRestoreOnWakeup, setConnectionsToRestoreOnWakeup)
TBPROPERTY(nullable NSMutableArray *, connectionsToWaitForDisconnectOnWakeup, setConnectionsToWaitForDisconnectOnWakeup)
TBPROPERTY(nullable NSBundle       *, deployLocalizationBundle, setDeployLocalizationBundle)
TBPROPERTY(nullable NSString       *, languageAtLaunch,        setLanguageAtLaunch)
TBPROPERTY(nullable NSString       *, publicIPAddress,         setPublicIPAddress)
TBPROPERTY(BOOL            , showingImportSetupWindow, setShowingImportSetupWindow)
TBPROPERTY(nullable NSDate         *, lastCheckNow,             setLastCheckNow)

@end
