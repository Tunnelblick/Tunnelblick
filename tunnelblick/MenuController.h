/*
 * Copyright 2004, 2005, 2006, 2007, 2008, 2009 Angelo Laub
 * Contributions by Dirk Theisen, Jens Ohlig, Waldemar Brodkorb
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

/* MenuController */

#import <Carbon/Carbon.h>
#import <Security/Security.h>
#import "defines.h"


@class VPNConnection;
@class SUUpdater;
@class UKKQueue;
@class ConfigurationUpdater;
@class MyPrefsWindowController;
@class NetSocket;
@class SplashWindowController;
@class StatusWindowController;
@class MainIconView;
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

// The following line is needed to avoid a crash on load on 10.4 and 10.5. The crash is caused by the use of "block" structures in the code,
// even though the block structures are not used when running under 10.4 or 10.5.
// The code that uses blocks is the line
//      [idxSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
// which appears in the setPreferenceForSelectedConfigurationsWithKey:to:isBOOL: method.
// This fix was found at http://lists.apple.com/archives/xcode-users/2009/Oct/msg00608.html
void * _NSConcreteStackBlock __attribute__((weak));


@interface MenuController : NSObject <NSAnimationDelegate,NSMenuDelegate>
{
    IBOutlet NSMenu         * myVPNMenu;                    // Tunnelblick's menu, displayed in Status Bar
    NSStatusItem            * statusItem;                   // Our place in the Status Bar
    MainIconView            * ourMainIconView;                 // View for the main icon
    IBOutlet NSMenuItem     * statusMenuItem;               // First line of menu, displays status (e.g. "Tunnelblick: 1 connection active"
    NSMenuItem              * noConfigurationsItem;         // Displayed if there are no configurations installed
    NSMenuItem              * vpnDetailsItem;               //    "VPN Details..." item for menu
    NSMenuItem              * addConfigurationItem;         //    "Add a VPN..." menu item
    NSMenuItem              * contactTunnelblickItem;       //    "Contact Tunnelblick..." menu item (if beta version)
    
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
	
    NSMutableArray          * largeAnimImages;              // Images for animation of the Tunnelblick icon in the the Status Window
    NSImage                 * largeConnectedImage;          // Image to display when one or more connections are active
    NSImage                 * largeMainImage;               // Image to display when there are no connections active
    
    NSArray                 * openvpnVersionNames;          // A sorted array of the names of versions of OpenVPN that are available
    NSArray                 * openvpnVersionInfo;           // An array of dictionaries corresponding to openvpnVersionNames
    //                                                      //    Each dictionary contains the following keys:
    //                                                      //    "full", "preMajor", "major", @"preMinor", "minor", "preSuffix", @"suffix", @"postSuffix"
    
    MyPrefsWindowController * logScreen;                    // Log window ("VPN Details..." window)
    
    SplashWindowController * splashScreen;                 // Splash window (used for install also)
    
    NSMutableArray          * dotTblkFileList;              // Array of paths to .tblk files that should be "opened" (i.e., installed) when we're finished launching
    
    NSDictionary            * myConfigDictionary;           // List of all configurations. key = display name, value = path to .ovpn or .conf file or .tblk package

    NSDictionary            * myVPNConnectionDictionary;    // List of all VPNConnections. key = display name, value = VPNConnection object for the configuration
    
    NSArray                 * connectionArray;              // VPNConnections that are currently connected
    
    NSMutableArray          * connectionsToRestoreOnWakeup; // VPNConnections to be restored when awakened from sleep
    
    NSArray                 * connectionsToRestoreOnUserActive; // VPNConnections to be restored when user becomes active again
    
    NSMutableArray          * pIDsWeAreTryingToHookUpTo;    // List of process IDs for processes we are trying to hookup to
    
    NSMutableArray          * activeIPCheckThreads;         // List of threadIDs of active IPCheck threads that have not been queued for cancellation
    NSMutableArray          * cancellingIPCheckThreads;     // List of threadIDs of IPCheck threads that have been queued for cancellation
    
    NSString                * lastState;                    // Most recent state of connection (EXITING, SLEEP, etc.)
    
    UKKQueue                * myQueue;                      // UKKQueue item for monitoring the configuration file folder
    
    NSTimer                 * showDurationsTimer;           // Used to periodically update display of connections' durations in the VPNDetails... Window
	
    NSTimer                 * hookupWatchdogTimer;          // Used to check for failures to hookup to openvpn processes, and deal with unknown OpenVPN processes 
	
    NSTimer                 * statisticsWindowTimer;        // Used to check for stale statistics that must be cleared 
    
    NSTimer                 * configsChangedTimer;          // Used when configurations change
    
    SUUpdater               * updater;                      // Sparkle Updater item used to check for updates to the program

    NSString                * feedURL;                      // URL to send program update requests to
    
    ConfigurationUpdater    * myConfigUpdater;              // Our class used to check for updates to the configurations
    
    BOOL                      launchFinished;               // Flag that we have executed "applicationDidFinishLaunching"
    
    BOOL                      userIsAnAdmin;                // Indicates logged-in user is a member of the "admin" group, and can administer the computer
    
    BOOL                      ignoreNoConfigs;              // Indicates that the absense of any configuration files should be ingored. This is used to prevent the creation
    //                                                         of a link to Tunnelblick in the Configurations folder in checkNoConfigurations from
    //                                                         triggering a second invocation of it because of the filesystem change when the link is created
    
    BOOL                      checkingForNoConfigs;         // Used to avoid infinite recursion
    
    BOOL                      noUnknownOpenVPNsRunning;     // Indicates that no unknown OpenVPN processes were left running after the TB launch
    //                                                         and therefore we can safely terminate unknown OpenVPN processes when quitting TB
    
    BOOL                      terminatingAtUserRequest;     // Indicates that we are terminating because the user Quit or Command-Q-ed
    
    BOOL                      mouseIsInMainIcon;            // Indicates that the mouse is over the Tunnelblick (not tracked unless preference says to)
    BOOL                      mouseIsInStatusWindow;        // Indicates that the mouse is over the icon or a status window
    
	BOOL					  signatureIsInvalid;			// Indicates the app is digitally signed but the signature does not check out
	
	BOOL					  doingSetupOfUI;				// Indicates we are setting up the UI, and not making changes to preferences
	
	BOOL					  menuIsOpen;					// Indicates the main Tunnelblick menu is open
	
    unsigned                  tapCount;                     // # of instances of openvpn that are using our tap kext
    unsigned                  tunCount;                     // # of instances of openvpn that are using our tun kext
    
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
    
#ifdef INCLUDE_VPNSERVICE
    VPNService              * vpnService;                   // VPNService object. if it responds to doVPNService, doVPNService is invoked at end of
    //                                                      // application:didFinishLaunching. The object persists until Tunnelblick terminates
    
    NSString                * vpnServiceConnectDisplayName; // Display name of connection that VPNService is trying to connect
#endif
}

// Menu actions
-(IBAction)         contactTunnelblickWasClicked:           (id)                sender;
-(IBAction)         openPreferencesWindow:                  (id)                sender;
-(IBAction)         addConfigurationWasClicked:             (id)                sender;
-(IBAction)         quit:                                   (id)                sender;

// General methods
-(void)             addConnection:                          (id)                sender;
-(void)             addNewConfig:                           (NSString *)        path
                 withDisplayName:                           (NSString *)        dispNm;
-(void)             setPreferenceForSelectedConfigurationsWithKey: (NSString *) key
															   to: (id)         newValue
                                                           isBOOL: (BOOL)       isBOOL;
-(void)             setBooleanPreferenceForSelectedConnectionsWithKey: (NSString *)	key
																   to: (BOOL)       newValue
															 inverted: (BOOL)		inverted;
-(void)             changedCheckForBetaUpdatesSettings;
-(void)             changedDisplayConnectionSubmenusSettings;
-(void)             changedDisplayConnectionTimersSettings;
-(void)             changedMonitorConfigurationFoldersSettings;
-(void)             checkForUpdates:                        (id)                sender;
-(BOOL)             cleanup;
-(NSArray *)        connectionsNotDisconnected;
-(void)             createMenu;
-(void)             createStatusItem;
-(unsigned)         decrementTapCount;
-(void)             deleteExistingConfig:                   (NSString *)        dispNm;
-(NSURL *)          getIPCheckURL;
-(void)             installConfigurationsUpdateInBundleAtPathHandler: (NSString *)path;
-(void)             installConfigurationsUpdateInBundleAtPath: (NSString *)     path;
-(unsigned)         decrementTunCount;
-(unsigned)         incrementTapCount;
-(unsigned)         incrementTunCount;
-(void)             killAllConnectionsIncludingDaemons:     (BOOL)              includeDaemons
                                                except:     (NSArray *)         connectionsToLeaveConnected
                                            logMessage:     (NSString *)        logMessage;
-(BOOL)             loadMenuIconSet;
-(BOOL)             loadMenuIconSet:                        (NSString *)        iconSetName
                               main:                        (NSImage **)        ptrMainImage
                         connecting:                        (NSImage **)        ptrConnectedImage
                               anim:                        (NSMutableArray **) ptrAnimImages;
- (void)            recreateStatusItemAndMenu;
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
-(void)             reconnectAfterBecomeActiveUser;
-(void)             removeConnection:                       (id)                sender;
-(BOOL)             runInstaller:                           (unsigned)          installerFlags
                  extraArguments:                           (NSArray *)         extraArguments;

-(BOOL)             runInstaller: (unsigned) installFlags
                  extraArguments: (NSArray *) extraArguments
                 usingAuthRefPtr: (AuthorizationRef *) authRef
                         message: (NSString *) message
               installTblksFirst: (NSArray *) tblksToInstallFirst;

-(void)             saveConnectionsToRestoreOnRelaunch;
-(void)             setHotKeyIndex:                         (unsigned)          newIndex;
-(void)             setState:                               (NSString *)        newState;
-(void)             setOurPreferencesFromSparkles;
-(NSArray *)        sortedSounds;
-(unsigned)         statusScreenIndex;
-(void)             unloadKexts;
-(BOOL)             userIsAnAdmin;
-(void)             statusWindowController:                 (id)                ctl
                        finishedWithChoice:                 (StatusWindowControllerChoice) choice
                            forDisplayName:                 (NSString *)        theName;
-(void)             showStatisticsWindows;
-(void)             hideStatisticsWindows;
-(void)             updateIconImage;
-(void)				updateMenuAndDetailsWindow;
-(void)				updateUpdateFeedURLForceDowngrade:		(BOOL)				forceDowngrade;
-(void)             terminateBecause:                       (enum TerminationReason) reason;

-(void) addActiveIPCheckThread: (NSString *) threadID;
-(void) cancelIPCheckThread: (NSString *) threadID;
-(void) cancelAllIPCheckThreadsForConnection: (VPNConnection *) connection;
-(BOOL) isOnCancellingListIPCheckThread: (NSString *) threadID;
-(void) haveFinishedIPCheckThread: (NSString *) threadID;

-(void) welcomeOKButtonWasClicked;

// Getters and Setters

-(NSArray *)        animImages;
-(NSImage *)        connectedImage;
-(NSImage *)        mainImage;
-(NSArray *)        connectionsToRestoreOnUserActive;
-(NSMutableArray *) largeAnimImages;
-(NSImage *)        largeConnectedImage;
-(NSImage *)        largeMainImage;
-(MyPrefsWindowController *) logScreen;
-(NSString *)       customRunOnConnectPath;
-(void)             startOrStopDurationsTimer;
-(BOOL)             terminatingAtUserRequest;
-(SUUpdater *)      updater;
-(BOOL)				doingSetupOfUI;
-(void)				setDoingSetupOfUI: (BOOL) value;

#ifdef INCLUDE_VPNSERVICE
// VPNService support
-(IBAction)         registerForTunnelblickWasClicked:       (id)                sender;
-(BOOL)             tryToConnect:                           (NSString *)        displayName;
-(VPNService *)     vpnService;
-(NSString *)       vpnServiceConnectDisplayName;
-(void)             setVPNServiceConnectDisplayName:        (NSString *)        newValue;
#endif

// AppleScript support

-(BOOL)             application:                            (NSApplication *)   sender
             delegateHandlesKey:                            (NSString *)        key;
-(NSArray *)        applescriptConfigurationList;

TBPROPERTY_READONLY(NSStatusItem *, statusItem)
TBPROPERTY_READONLY(NSMenu *,		myVPNMenu)
TBPROPERTY_READONLY(NSMutableArray *, activeIPCheckThreads)
TBPROPERTY_READONLY(NSMutableArray *, cancellingIPCheckThreads)

TBPROPERTY(NSArray *,      screenList,                setScreenList)
TBPROPERTY(MainIconView *, ourMainIconView,           setOurMainIconView)
TBPROPERTY(NSDictionary *, myVPNConnectionDictionary, setMyVPNConnectionDictionary)
TBPROPERTY(NSDictionary *, myConfigDictionary,        setMyConfigDictionary)
TBPROPERTY(NSArray      *, openvpnVersionNames,       setOpenvpnVersionNames)
TBPROPERTY(NSArray      *, openvpnVersionInfo,        setOpenvpnVersionInfo)
TBPROPERTY(NSArray      *, connectionArray,           setConnectionArray)
TBPROPERTY(NSTimer      *, hookupWatchdogTimer,       setHookupWatchdogTimer)
TBPROPERTY(NSTimer      *, showDurationsTimer,        setShowDurationsTimer)
TBPROPERTY(NSTimer      *, configsChangedTimer,       setConfigsChangedTimer)
TBPROPERTY(NSTimer      *, statisticsWindowTimer,     setStatisticsWindowTimer)
TBPROPERTY(NSMutableArray *, highlightedAnimImages,   setHighlightedAnimImages)
TBPROPERTY(NSImage      *, highlightedConnectedImage, setHighlightedConnectedImage)
TBPROPERTY(NSImage      *, highlightedMainImage,      setHighlightedMainImage)

@end
