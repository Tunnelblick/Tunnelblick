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
@class InstallWindowController;

#ifdef INCLUDE_VPNSERVICE
@class VPNService;
#endif


BOOL needToRunInstaller(BOOL * changeOwnershipAndOrPermissions,
                        BOOL * moveLibraryOpenVPN,
                        BOOL * restoreDeploy,
                        BOOL * needsPkgRepair,
                        BOOL * needsBundleCopy,
                        BOOL inApplications); 

BOOL needToChangeOwnershipAndOrPermissions(BOOL inApplications);
BOOL needToMoveLibraryOpenVPN(void);
BOOL needToRestoreDeploy(void);
BOOL needToRepairPackages(void);
BOOL needToCopyBundle(void);


@interface MenuController : NSObject <NSAnimationDelegate,NSMenuDelegate>
{
    IBOutlet NSMenu         * myVPNMenu;                    // Tunnelblick's menu, displayed in Status Bar
    NSStatusItem            * statusItem;                   // Our place in the Status Bar
    IBOutlet NSMenuItem     * statusMenuItem;               // First line of menu, displays status (e.g. "Tunnelblick: 1 connection active"
    NSMenuItem              * noConfigurationsItem;         // Displayed if there are no configurations installed
    NSMenuItem              * vpnDetailsItem;               //    "VPN Details..." item for menu
    NSMenuItem              * addConfigurationItem;         //    "Add a VPN..." menu item
    
#ifdef INCLUDE_VPNSERVICE
    NSMenuItem              * registerForTunnelblickItem;//    "Register for Tunnelblick..." menu item
#endif
    
    NSMenuItem              * checkForUpdatesNowItem;       //    "Check For Updates Now" menu item
    NSMenuItem              * aboutItem;                    //    "About..." item for menu
    NSMenuItem              * quitItem;                     // "Quit Tunnelblick" item for menu

    NSAnimation             * theAnim;                      // For animation of the Tunnelblick icon in the Status Bar
    NSMutableArray          * animImages;                   // Images for animation of the Tunnelblick icon in the Status Bar
    NSImage                 * connectedImage;               // Image to display when one or more connections are active
    NSImage                 * mainImage;                    // Image to display when there are no connections active

    NSMutableArray          * largeAnimImages;              // Images for animation of the Tunnelblick icon in the the Status Window
    NSImage                 * largeConnectedImage;          // Image to display when one or more connections are active
    NSImage                 * largeMainImage;               // Image to display when there are no connections active
    
    MyPrefsWindowController * logScreen;                    // Log window ("VPN Details..." window)
    
    InstallWindowController * installScreen;                // Install window
    
    NSMutableArray          * dotTblkFileList;              // Array of paths to .tblk files that should be "opened" (i.e., installed) when we're finished launching
    
    NSMutableDictionary     * myConfigDictionary;           // List of all configurations. key = display name, value = path to .ovpn or .conf file or .tblk package

    NSMutableDictionary     * myVPNConnectionDictionary;    // List of all VPNConnections. key = display name, value = VPNConnection object for the configuration
    
    NSMutableArray          * connectionArray;              // VPNConnections that are currently connected
    
    NSArray                 * connectionsToRestoreOnWakeup; // VPNConnections to be restored when awakened from sleep
    
    NSArray                 * connectionsToRestoreOnUserActive; // VPNConnections to be restored when user becomes active again
    
    NSMutableArray          * pIDsWeAreTryingToHookUpTo;    // List of process IDs for processes we are trying to hookup to
    
    NSString                * lastState;                    // Most recent state of connection (EXITING, SLEEP, etc.)
    
    UKKQueue                * myQueue;                      // UKKQueue item for monitoring the configuration file folder
    
    NSTimer                 * showDurationsTimer;           // Used to periodically update display of connections' durations in the VPNDetails... Window
	
    NSTimer                 * hookupWatchdogTimer;          // Used to check for failures to hookup to openvpn processes, and deal with unknown OpenVPN processes 
	
    SUUpdater               * updater;                      // Sparkle Updater item used to check for updates to the program

    ConfigurationUpdater    * myConfigUpdater;              // Our class used to check for updates to the configurations
    
    BOOL                      areLoggingOutOrShuttingDown;  // Flag that NSWorkspaceWillPowerOffNotification was received
    
    BOOL                      launchFinished;               // Flag that we have executed "applicationDidFinishLaunching"
    
    BOOL                      userIsAnAdmin;                // Indicates logged-in user is a member of the "admin" group, and can administer the computer
    
    BOOL                      ignoreNoConfigs;              // Indicates that the absense of any configuration files should be ingored. This is used to prevent the creation
    //                                                         of a link to Tunnelblick in the Configurations folder in checkNoConfigurations from
    //                                                         triggering a second invocation of it because of the filesystem change when the link is created
    
    BOOL                      checkingForNoConfigs;         // Used to avoid infinite recursion
    
    BOOL                      noUnknownOpenVPNsRunning;     // Indicates that no unknown OpenVPN processes were left running after the TB launch
    //                                                         and therefore we can safely terminate unknown OpenVPN processes when quitting TB
    
    BOOL                      terminatingAtUserRequest;     // Indicates that we are terminating because the user Quit or Command-Q-ed
    
    unsigned                  tapCount;                     // # of instances of openvpn that are using our tap kext
    unsigned                  tunCount;                     // # of instances of openvpn that are using our tun kext
    
    BOOL                      hotKeyEventHandlerIsInstalled;// The event handler for the hot key (keyboard shortcut to pop up the Tunnelblick menu) has been installed
    EventHotKeyRef            hotKeyRef;                    // Reference for the current hot key
    UInt32                    hotKeyKeyCode;                // Current hot key: Virtual key code
    UInt32                    hotKeyModifierKeys;           //                  Modifier keys code or 0 to indicate no hot key active
    int                       hotKeyCurrentIndex;           // Index of the hot key that is currently in use (0 = none, else 1...12)

    NSMutableArray          * customMenuScripts;            // Array of paths to the scripts for custom menu items
    int                       customMenuScriptIndex;        // Index used while building the customMenuScripts array
    NSString                * customRunOnLaunchPath;        // Path of a file to be executed before processing "connect when Tunnelblick launches" configurations
    NSString                * customRunOnConnectPath;       // Path of a file to be executed before making a connection
    
#ifdef INCLUDE_VPNSERVICE
    VPNService              * vpnService;                   // VPNService object. if it responds to doVPNService, doVPNService is invoked at end of
    //                                                      // application:didFinishLaunching. The object persists until Tunnelblick terminates
    
    NSString                * vpnServiceConnectDisplayName; // Display name of connection that VPNService is trying to connect
#endif
}

// Menu actions
-(IBAction)         openPreferencesWindow:                  (id)                sender;
-(IBAction)         addConfigurationWasClicked:             (id)                sender;
-(IBAction)         quit:                                   (id)                sender;

// General methods
-(void)             addConnection:                          (id)                sender;
-(BOOL)             appNameIsTunnelblickWarnUserIfNot:      (BOOL)              tellUser;
-(void)             changedDisplayConnectionSubmenusSettings;
-(void)             changedDisplayConnectionTimersSettings;
-(void)             changedMonitorConfigurationFoldersSettings;
-(void)             checkForUpdates:                        (id)                sender;
-(void)             cleanup;
-(void)             createLinkToApp;
-(void)             createStatusItem;
-(unsigned)         decrementTapCount;
-(void)             installConfigurationsUpdateInBundleAtPathHandler: (NSString *)path;
-(void)             installConfigurationsUpdateInBundleAtPath: (NSString *)     path;
-(unsigned)         decrementTunCount;
-(unsigned)         incrementTapCount;
-(unsigned)         incrementTunCount;
-(BOOL)             loadMenuIconSet;
-(BOOL)             loadMenuIconSet:                        (NSString *)        iconSetName
                               main:                        (NSImage **)        ptrMainImage
                         connecting:                        (NSImage **)        ptrConnectedImage
                               anim:                        (NSMutableArray **) ptrAnimImages;
-(NSMutableDictionary *)    myConfigDictionary;
-(NSMutableDictionary *)    myVPNConnectionDictionary;
-(NSString *)       openVPNLogHeader;
-(void)             reconnectAfterBecomeActiveUser;
-(void)             removeConnection:                       (id)                sender;
-(void)             saveConnectionsToRestoreOnRelaunch;
-(void)             setHotKeyIndex:                         (int)               newIndex;
-(void)             setState:                               (NSString *)        newState;
-(void)             setupSparklePreferences;
-(void)             unloadKexts; 
-(BOOL)             userIsAnAdmin;
-(void)             statusWindowController:                 (id)                ctl
                        finishedWithChoice:                 (StatusWindowControllerChoice) choice
                            forDisplayName:                 (NSString *)        theName;


// Getters and Setters

-(NSArray *)        animImages;
-(NSImage *)        connectedImage;
-(NSImage *)        mainImage;
-(NSArray *)        connectionArray;
-(NSArray *)        connectionsToRestoreOnUserActive;
-(NSMutableArray *) largeAnimImages;
-(NSImage *)        largeConnectedImage;
-(NSImage *)        largeMainImage;
-(MyPrefsWindowController *) logScreen;
-(NSString *)       customRunOnConnectPath;
-(NSTimer *)        showDurationsTimer;
-(void)             startOrStopDurationsTimer;
-(BOOL)             terminatingAtUserRequest;
-(SUUpdater *)      updater;

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
@end
