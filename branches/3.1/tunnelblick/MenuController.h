/*
 * Copyright (c) 2004, 2005, 2006, 2007, 2008, 2009 Angelo Laub
 * Contributions by Dirk Theisen, Jens Ohlig, Waldemar Brodkorb
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

/* MenuController */

#import <Carbon/Carbon.h>
#import <Security/Security.h>
#import "Sparkle/SUUpdater.h"
#import "UKKQueue/UKKQueue.h"

@class NetSocket;

BOOL needToRunInstaller(BOOL * changeOwnershipAndOrPermissions, BOOL * moveLibraryOpenVPN, BOOL  *restoreDeploy, BOOL * needsPkgRepair, BOOL inApplications); 
BOOL needToChangeOwnershipAndOrPermissions(BOOL inApplications);
BOOL needToMoveLibraryOpenVPN(void);
BOOL needToRestoreDeploy(void);
BOOL needToRepairPackages(void);

@interface MenuController : NSObject
{
    IBOutlet id               onLaunchRadioButton;
    IBOutlet id               onSystemStartRadioButton;
    IBOutlet NSButton       * autoConnectCheckbox;
    IBOutlet NSButton       * clearButton;
    IBOutlet NSButton       * connectButton;
    IBOutlet NSButton       * disconnectButton;
    IBOutlet NSButton       * editButton;
    IBOutlet NSWindow       * logWindow;
    IBOutlet NSButton       * monitorConnnectionCheckbox;
    IBOutlet NSButton       * shareButton;
    IBOutlet NSTabView      * tabView;
    IBOutlet NSPopUpButton  * modifyNameserverPopUpButton;
    IBOutlet NSSplitView    * splitView;
    IBOutlet NSView         * leftSplitView;
    IBOutlet NSView         * rightSplitView;
    IBOutlet NSTableView    * leftNavListView;
    IBOutlet NSTableColumn  * leftNavTableColumn;

    IBOutlet NSArrayController * modifyNameserverPopUpButtonArrayController;
    IBOutlet NSMenu         * myVPNMenu;                    // Tunnelblick's menu, displayed in Status Bar
    NSStatusItem            * statusItem;                   // Our place in the Status Bar
    IBOutlet NSMenuItem     * statusMenuItem;               // First line of menu, displays status (e.g. "Tunnelblick: 1 connection active"
    NSMenuItem              * noConfigurationsItem;         // Displayed if there are no configurations installed
	NSMenuItem              * detailsItem;                  // "Details..." item for menu
    NSMenuItem              * optionsItem;                  // "Options" item for menu
    NSMenu                  * optionsSubmenu;               //    Submenu for "Options"
    NSMenuItem              * preferencesTitleItem;         //    "Preferences" menu item (just used as a title)
    NSMenuItem              * putIconNearSpotlightItem;     //      "Put Icon Near the Spotlight Icon" menu item
    NSMenuItem              * useOriginalIconItem;          //      "Use Original Icon" menu item
    NSMenuItem              * monitorConfigurationDirItem;  //      "Monitor the Configuration Folder" menu item
    NSMenuItem              * showConnectedDurationsItem;   //      "Show Connection Timers" menu item
    NSMenuItem              * warnAboutSimultaneousItem;    //      "Warn About Simultaneous Connections" menu item
    NSMenuItem              * useShadowCopiesItem;          //      "Use Shadow Copies of Configuration Files" menu item
    NSMenuItem              * autoCheckForUpdatesItem;      //      "Automatically Check for Updates" menu item
    NSMenuItem              * reportAnonymousInfoItem;      //      "Report Anonymous System Info" menu item
    NSMenu                  * hotKeySubmenu;                //      Shortcut Key Submenu
    NSMenuItem              * hotKeySubmenuItem;            //      Shortcut Key Item in Options menu
    NSMenuItem              * addConfigurationItem;         //    "Add Configuration..." menu item
    NSMenuItem              * checkForUpdatesNowItem;       //    "Check For Updates Now" menu item
    NSMenuItem              * aboutItem;                    //    "About..." item for menu
    NSMenuItem              * quitItem;                     // "Quit Tunnelblick" item for menu

    NSAnimation             * theAnim;                      // For animation of the Tunnelblick icon in the Status Bar
    NSMutableArray          * animImages;                   // Images for animation of the Tunnelblick icon in the Status Bar
    int                       animNumFrames;                // # of images
    NSImage                 * connectedImage;               // Image to display when one or more connections are active
    NSImage                 * mainImage;                    // Image to display when there are no connections active

    NSMutableArray          * dotTblkFileList;              // Array of paths to .tblk files that should be "opened" (i.e., installed) when we're finished launching
    
    NSMutableDictionary     * myConfigDictionary;           // List of all configurations. key = display name, value = path to .ovpn or .conf file or .tblk package

    NSMutableDictionary     * myVPNConnectionDictionary;    // List of all VPNConnections. key = display name, value = VPNConnection object for the configuration
    
    AuthorizationRef          myAuth;                       // Used to call installer
    
    NSMutableArray          * connectionArray;              // VPNConnections that are currently connected
    
    NSMutableArray          * connectionsToRestore;         // VPNConnections to be restored when awaken from sleep
    
    NSString                * lastState;                    // Most recent state of connection (EXITING, SLEEP, etc.)
    
    UKKQueue                * myQueue;                      // UKKQueue item for monitoring the configuration file folder
    
    NSTimer                 * showDurationsTimer;           // Used to periodically update display of connections' durations in the Details... Window (i.e, logWindow)
	
    NSTimer                 * hookupWatchdogTimer;              // Used to check for failures to hookup to openvpn processes, and deal with unknown OpenVPN processes 
	
    SUUpdater               * updater;                      // Sparkle Updater item used to check for updates to the program
    
    NSString                * oldSelectedConnectionName;    // The name of the selected connection (if any) before a making a private configuration public or vice-versa
    //                                                         so the program can re-select. nil after re-selecting it
    
    NSMutableArray          * leftNavList;                  // Items in the left navigation list as displayed to the user
    //                                                         Each item is a string with either
    //                                                         a folder name (possibly indented) or
    //                                                         a connection name (possibly indented)

    NSMutableArray          * leftNavDisplayNames;          // A string for each item in leftNavList
    //                                                         Each item is a string with either
    //                                                         An empty string (corresponding to a folder name entry in leftNavList) or
    //                                                         The full display name for the corresponding connection
    
    int                       selectedLeftNavListIndex;     // Index of the selected item in the left navigation list
    
    BOOL                      launchFinished;               // Flag that we have executed "applicationDidFinishLaunching"
    
    BOOL                      logWindowIsOpen;              // Indicates if Details window is being displayed
    
    BOOL                      logWindowIsUsingTabs;         // Indicates Details window is using tabs (and not using left-navigation)
    
    BOOL                      userIsAnAdmin;                // Indicates logged-in user is a member of the "admin" group, and can administer the computer
    
    BOOL                      ignoreNoConfigs;              // Indicates that the absense of any configuration files should be ingored. This is used to prevent the creation
    //                                                         of a link to Tunnelblick in the Configurations folder in checkNoConfigurations from
    //                                                         triggering a second invocation of it because of the filesystem change when the link is created
    
    BOOL                      noUnknownOpenVPNsRunning;     // Indicates that no unknown OpenVPN processes were left running after the TB launch
    //                                                         and therefore we can safely terminate unknown OpenVPN processes when quitting TB
    
    BOOL                      terminatingAtUserRequest;     // Indicates that we are terminating because the user Quit or Command-Q-ed
    
    unsigned                  tapCount;                     // # of instances of openvpn that are using our tap kext
    unsigned                  tunCount;                     // # of instances of openvpn that are using our tun kext
    
    BOOL                      hotKeyEventHandlerIsInstalled;// The event handler for the hot key (keyboard shortcut to pop up the Tunnelblick menu) has been installed
    EventHotKeyRef            hotKeyRef;                    // Reference for the current hot key
    UInt32                    hotKeyKeyCode;                // Current hot key: Virtual key code
    UInt32                    hotKeyModifierKeys;           //                  Modifier keys code or 0 to indicate no hot key active
    NSMenuItem              * hotKeySubmenuItemThatIsOn;    // Menu item for the hot key that is currently in use or nil if no hot key active

    int                       selectedModifyNameserverIndex;// Holds index of the selected 'Set nameserver' option

    NSMutableArray          * customMenuScripts;            // Array of paths to the scripts for custom menu items
    int                       customMenuScriptIndex;        // Index used while building the customMenuScripts array
    NSString                * customRunOnLaunchPath;        // Path of a file to be executed before processing "connect when Tunnelblick launches" configurations
    NSString                * customRunOnConnectPath;       // Path of a file to be executed before making a connection
}

// Button and checkbox actions
-(IBAction)         monitorConnectionPrefButtonWasClicked:  (id)                sender;
-(IBAction)         autoConnectPrefButtonWasClicked:        (id)                sender;
-(IBAction)         onLaunchRadioButtonWasClicked:          (id)                sender;
-(IBAction)         onSystemStartRadioButtonWasClicked:     (id)                sender;
-(IBAction)         clearLogButtonWasClicked:               (id)                sender;
-(IBAction)         connectButtonWasClicked:                (id)                sender;
-(IBAction)         disconnectButtonWasClicked:             (id)                sender;
-(IBAction)         editConfigButtonWasClicked:             (id)                sender;
-(IBAction)         shareConfigButtonWasClicked:            (id)                sender;
-(IBAction)         addConfigurationWasClicked:             (id)                sender;

// Menu actions
-(IBAction)         checkForUpdates:                        (id)                sender;
-(IBAction)         openLogWindow:                          (id)                sender;
-(IBAction)         quit:                                   (id)                sender;
-(IBAction)         togglePlaceIconNearSpotlight:           (NSMenuItem *)      item;   // On Options submenu
-(IBAction)         toggleMonitorConfigurationDir:          (NSMenuItem *)      item;   // On Options submenu
-(IBAction)         toggleWarnAboutSimultaneous:            (NSMenuItem *)      item;   // On Options submenu
-(IBAction)         toggleUseShadowCopies:                  (NSMenuItem *)      item;   // On Options submenu
-(IBAction)         toggleAutoCheckForUpdates:              (NSMenuItem *)      item;   // On Options submenu
-(IBAction)         toggleReportAnonymousInfo:              (NSMenuItem *)      item;   // On Options submenu
-(IBAction)         toggleUseOriginalIcon:                  (NSMenuItem *)      item;   // On Options submenu

// General methods
-(void)             addConnection:                          (id)                sender;
-(void)             cleanup;
-(unsigned)         decrementTapCount;
-(unsigned)         decrementTunCount;
-(unsigned)         incrementTapCount;
-(unsigned)         incrementTunCount;

-(NSMutableDictionary *)    myConfigDictionary;
-(NSMutableDictionary *)    myVPNConnectionDictionary;
-(NSString *)       openVPNLogHeader;
-(void)             removeConnection:                       (id)                sender;
-(BOOL)             runInstallerWithArguments:              (NSArray *)         arguments
                                authorization:              (AuthorizationRef)  authRef;
-(void)             setState:                               (NSString *)        newState;
-(void)             unloadKexts; 
-(BOOL)             userIsAnAdmin;

// Getters and Setters

-(int)              selectedModifyNameserverIndex;
-(void)             setSelectedModifyNameserverIndex:       (int)               newValue;
-(NSString *)       customRunOnConnectPath;
-(int)              selectedLeftNavListIndex;
-(void)             setSelectedLeftNavListIndex:            (int)               newValue;
-(BOOL)             terminatingAtUserRequest;

@end
