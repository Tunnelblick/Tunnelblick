/*
 * Copyright 2004, 2005, 2006, 2007, 2008, 2009 Angelo Laub
 * Contributions by Dirk Theisen, Jens Ohlig, Waldemar Brodkorb
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
    terminatingBecauseOfFatalError = 6
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

enum StatusIconPosition {
    iconNotShown        = 0,
    iconNearSpotlight   = 1,
    iconNormal          = 2
};

@interface NSStatusBar (NSStatusBar_Private)
- (id)_statusItemWithLength:(CGFloat)l withPriority:(long long)p;
- (id)_insertStatusItem:(NSStatusItem *)i withPriority:(long long)p;
@end

@interface MenuController : NSObject <NSAnimationDelegate,NSMenuDelegate,NSUserNotificationCenterDelegate>

{
    IBOutlet NSMenu         * myVPNMenu;                    // Tunnelblick's menu, displayed in Status Bar
    NSStatusItem            * statusItem;                   // Our place in the Status Bar
    NSStatusBarButton       * statusItemButton;             // Or nil if not on 10.10 or higher
    MainIconView            * ourMainIconView;              // View for the main icon
    IBOutlet NSMenuItem     * statusMenuItem;               // First line of menu, displays status (e.g. "Tunnelblick: 1 connection active"
    NSMenuItem              * noConfigurationsItem;         // Displayed if there are no configurations installed
	NSMenuItem              * reenableInternetItem;         // "Re-enable Internet Access" item for menu
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
    
    NSArray                 * openvpnVersionNames;          // A sorted array of the names of versions of OpenVPN that are available
    
    SystemAuth              * startupInstallAuth;           // Authorization when starting up Tunnelblick
    
    MyPrefsWindowController * logScreen;                    // Log window ("VPN Details..." window)
    
    SplashWindowController * splashScreen;                 // Splash window (used for install also)
    
    NSMutableArray          * dotTblkFileList;              // Array of paths to .tblk files that should be "opened" (i.e., installed) when we're finished launching
    
    NSDictionary            * myConfigDictionary;           // List of all configurations. key = display name, value = path to .ovpn or .conf file or .tblk package

    NSDictionary            * myVPNConnectionDictionary;    // List of all VPNConnections. key = display name, value = VPNConnection object for the configuration
    
    NSArray                 * connectionArray;              // VPNConnections that are currently connected
    NSArray                 * nondisconnectedConnections;   // VPNConnections that are currently not disconnected (any with status != EXITING)
    
    NSMutableArray          * connectionsToRestoreOnWakeup; // VPNConnections to be restored when awakened from sleep
    
    NSMutableArray          * connectionsToRestoreOnUserActive; // VPNConnections to be restored when user becomes active again
    
    NSMutableArray          * connectionsToWaitForDisconnectOnWakeup; // VPNConnections to be waited for disconnection from when awakened from sleep
    
    NSMutableArray          * pIDsWeAreTryingToHookUpTo;    // List of process IDs for processes we are trying to hookup to
    
    NSMutableArray          * activeIPCheckThreads;         // List of threadIDs of active IPCheck threads that have not been queued for cancellation
    NSMutableArray          * cancellingIPCheckThreads;     // List of threadIDs of IPCheck threads that have been queued for cancellation
    
    NSString                * lastState;                    // Most recent state of connection (EXITING, SLEEP, etc.)
    
	NSString                * publicIPAddress;				// Apparent public IP address
	
    TBUIUpdater             * uiUpdater;                    // Used to periodically update displays
	
    NSTimer                 * hookupWatchdogTimer;          // Used to check for failures to hookup to openvpn processes, and deal with unknown OpenVPN processes 
	
    NSTimer                 * statisticsWindowTimer;        // Used to check for stale statistics that must be cleared 
    
    SUUpdater               * updater;                      // Sparkle Updater item used to check for updates to the program

    ConfigurationMultiUpdater * myConfigMultiUpdater;       // Checks for configuration updates
	
	NSString                * languageAtLaunch;				// Lower-case version of the language we are using. Passed on to runOnConnect, runOnLaunch, and Menu command scripts
    
	NSString                * tunnelblickVersionString;		// Copy of CFBundleShortVersionString
	
    NSTrackingRectTag         iconTrackingRectTag;          // Used to track mouseEntered and mouseExited events for statusItemButton
    
	BOOL					  languageAtLaunchWasRTL;		// Used to load RTL xibs and adjust spacing of controls as needed
	
    BOOL volatile             launchFinished;               // Flag that we have executed "applicationDidFinishLaunching"
    
    BOOL                      userIsAnAdmin;                // Indicates logged-in user is a member of the "admin" group, and can administer the computer
    
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
	
    unsigned                  tapCount;                     // # of instances of openvpn that are using our tap kext
    unsigned                  tunCount;                     // # of instances of openvpn that are using our tun kext
    
    enum StatusIconPosition   iconPosition;                 // Position of Tunnelblick icon in the status menu
    
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

// Used to implement drag/drop of configuration files onto the Tunnelblick icon in the status bar or the configuration list in the 'VPN Details' window
-(BOOL)             openFiles:                              (NSArray * )        filePaths;

// Menu actions
-(IBAction)         contactTunnelblickWasClicked:           (id)                sender;
-(IBAction)         openPreferencesWindow:                  (id)                sender;
-(IBAction)         quit:                                   (id)                sender;

// General methods
-(void)             addConnection:                          (VPNConnection *)   connection;
-(void)             addNonconnection:                       (VPNConnection *)   connection;
-(void)             setBooleanPreferenceForSelectedConnectionsWithKey: (NSString *)	key
																   to: (BOOL)       newValue
															 inverted: (BOOL)		inverted;
-(void)             showConfirmIconNearSpotlightIconDialog;
-(void)             recreateMainMenu;
-(void)             changedDisplayConnectionTimersSettings;
-(void)             checkForUpdates:                        (id)                sender;
-(BOOL)             cleanup;
-(void)             configurationsChanged;
-(void)             configurationsChangedWithRenameDictionary: (NSDictionary *)  renameDictionary;
-(NSArray *)        connectionsNotDisconnected;
-(void)             connectionStateDidChange:                  (id)              connection;
-(unsigned)         decrementTapCount;
-(NSURL *)          getIPCheckURL;
-(NSNumber *)       haveConfigurations;
-(void)             installConfigurationsUpdateInBundleAtPathMainThread: (NSString *)path;
-(unsigned)         decrementTunCount;
-(unsigned)         incrementTapCount;
-(unsigned)         incrementTunCount;
-(BOOL)             loadMenuIconSet;
-(BOOL)             loadMenuIconSet:                        (NSString *)        iconSetName
                               main:                        (NSImage **)        ptrMainImage
                         connecting:                        (NSImage **)        ptrConnectedImage
                               anim:                        (NSMutableArray **) ptrAnimImages;
-(NSString *)       localizedNameForDisplayName:            (NSString *)        displayName;
-(NSString *)       localizedNameforDisplayName:            (NSString *)        displayName
                                       tblkPath:            (NSString *)        tblkPath;
-(void)             moveStatusItemIfNecessary;
-(void)             mouseEnteredMainIcon:                   (id)                control
                                   event:                   (NSEvent *)         theEvent;
-(void)             mouseExitedMainIcon:                    (id)                windowController
                                  event:                    (NSEvent *)         theEvent;
-(void)             mouseEnteredStatusWindow:               (id)                control
                                       event:               (NSEvent *)         theEvent;
-(void)             mouseExitedStatusWindow:                (id)                windowController
                                      event:                (NSEvent *)         theEvent;
-(BOOL)             mouseIsInsideAnyView;
-(NSString *)       openVPNLogHeader;
-(void)             reactivateTunnelblick;
-(void)             reconnectAfterBecomeActiveUser;
-(void)             removeConnection:                       (VPNConnection *)   connection;
-(NSInteger)        runInstaller: (unsigned)           installFlags
                  extraArguments: (NSArray *)          extraArguments
                 usingSystemAuth: (SystemAuth *)       auth
                    installTblks: (NSArray *)          tblksToInstall;
-(void)             saveConnectionsToRestoreOnRelaunch;
-(void)             setHotKeyIndex:                         (unsigned)          newIndex;
-(void)             setState:                               (NSString *)        newState;
-(void)             setPreferenceForSelectedConfigurationsWithDict: (NSDictionary * ) dict;
-(void)             setupUpdaterAutomaticChecks;
-(NSArray *)        sortedSounds;
-(unsigned)         statusScreenIndex;
-(void)             unloadKexts;
-(BOOL)             userIsAnAdmin;
-(void)             startCheckingForConfigurationUpdates;
-(void)             statusWindowController:                 (id)                ctl
                        finishedWithChoice:                 (StatusWindowControllerChoice) choice
                            forDisplayName:                 (NSString *)        theName;
-(void)             showStatisticsWindows;
-(void)             hideStatisticsWindows;
-(NSDictionary *)   tunnelblickInfoDictionary;
-(void)             updateIconImage;
-(void)             updateUI;
-(void)             terminateBecause:                       (enum TerminationReason) reason;
-(void) welcomeOKButtonWasClicked;

-(void) addActiveIPCheckThread: (NSString *) threadID;
-(void) cancelIPCheckThread: (NSString *) threadID;
-(void) cancelAllIPCheckThreadsForConnection: (VPNConnection *) connection;
-(BOOL) isOnCancellingListIPCheckThread: (NSString *) threadID;
-(void) haveFinishedIPCheckThread: (NSString *) threadID;

// AppleScript support

-(BOOL)             application:                            (NSApplication *)   sender
             delegateHandlesKey:                            (NSString *)        key;
-(NSArray *)        applescriptConfigurationList;

// Getters and Setters

-(NSArray *)        animImages;
-(NSImage *)        connectedImage;
-(NSImage *)        mainImage;
-(NSMutableArray *) largeAnimImages;
-(NSImage *)        largeConnectedImage;
-(NSImage *)        largeMainImage;
-(MyPrefsWindowController *) logScreen;
-(NSString *)       customRunOnConnectPath;
-(void)             startOrStopUiUpdater;
-(BOOL)             terminatingAtUserRequest;
-(SUUpdater *)      updater;
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

TBPROPERTY_READONLY(NSStatusItem *, statusItem)
TBPROPERTY_READONLY(BOOL volatile, menuIsOpen)
TBPROPERTY_READONLY(BOOL volatile, launchFinished)
TBPROPERTY_READONLY(BOOL         , languageAtLaunchWasRTL)
TBPROPERTY_READONLY(NSMenu *,		myVPNMenu)
TBPROPERTY_READONLY(NSMutableArray *, activeIPCheckThreads)
TBPROPERTY_READONLY(NSMutableArray *, cancellingIPCheckThreads)
TBPROPERTY_READONLY(ConfigurationMultiUpdater *, myConfigMultiUpdater)

TBPROPERTY(SystemAuth   *, startupInstallAuth,        setStartupInstallAuth)
TBPROPERTY(NSArray      *, screenList,                setScreenList)
TBPROPERTY(MainIconView *, ourMainIconView,           setOurMainIconView)
TBPROPERTY(NSDictionary *, myVPNConnectionDictionary, setMyVPNConnectionDictionary)
TBPROPERTY(NSDictionary *, myConfigDictionary,        setMyConfigDictionary)
TBPROPERTY(NSArray      *, openvpnVersionNames,       setOpenvpnVersionNames)
TBPROPERTY(NSArray      *, connectionArray,           setConnectionArray)
TBPROPERTY(NSArray      *, nondisconnectedConnections,setNondisconnectedConnections)
TBPROPERTY(NSTimer      *, hookupWatchdogTimer,       setHookupWatchdogTimer)
TBPROPERTY(TBUIUpdater  *, uiUpdater,                 setUiUpdater)
TBPROPERTY(NSTimer      *, statisticsWindowTimer,     setStatisticsWindowTimer)
TBPROPERTY(NSMutableArray *, highlightedAnimImages,   setHighlightedAnimImages)
TBPROPERTY(NSImage      *, highlightedConnectedImage, setHighlightedConnectedImage)
TBPROPERTY(NSImage      *, highlightedMainImage,      setHighlightedMainImage)
TBPROPERTY(NSMutableArray *, connectionsToRestoreOnUserActive, setConnectionsToRestoreOnUserActive)
TBPROPERTY(NSMutableArray *, connectionsToRestoreOnWakeup, setConnectionsToRestoreOnWakeup)
TBPROPERTY(NSMutableArray *, connectionsToWaitForDisconnectOnWakeup, setConnectionsToWaitForDisconnectOnWakeup)
TBPROPERTY(NSBundle       *, deployLocalizationBundle, setDeployLocalizationBundle)
TBPROPERTY(NSString       *, languageAtLaunch,        setLanguageAtLaunch)
TBPROPERTY(NSString       *, publicIPAddress,         setPublicIPAddress)
TBPROPERTY(NSString       *, tunnelblickVersionString, setTunnelblickVersionString)

@end
