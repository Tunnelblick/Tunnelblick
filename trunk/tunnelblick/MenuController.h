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

#import <Cocoa/Cocoa.h>
#import <Sparkle/SUUpdater.h>
#import "UKKQueue/UKKQueue.h"
#import "VPNConnection.h"

@class NetSocket;
BOOL needsInstallation(void);
void terminateBecauseOfBadConfiguration(void);
BOOL deployContentsOwnerOrPermissionsNeedRepair(NSString * deployDirPath);
BOOL isOwnedByRootAndHasPermissions(NSString *fPath, NSString * permsShouldHave);


@interface MenuController : NSObject
{
    IBOutlet NSButton       * monitorConnnectionCheckbox;
    IBOutlet NSButton       * autoLaunchCheckbox;
    IBOutlet NSButton       * clearButton;
    IBOutlet NSButton       * connectButton;
    IBOutlet NSButton       * disconnectButton;
    IBOutlet NSButton       * editButton;
    IBOutlet NSWindow       * logWindow;
    IBOutlet NSWindow       * splashWindow;
    IBOutlet NSTabView      * tabView;
    IBOutlet NSButton       * useNameserverCheckbox;

    IBOutlet id               myVPNMenu;                    // Tunnelblick's menu, displayed in Status Bar
    NSStatusItem            * theItem;                      // Our place in the Status Bar
    IBOutlet NSMenuItem     * statusMenuItem;               // First line of menu, displays status (e.g. "Tunnelblick: 1 connection active"
    NSMenuItem              * optionsItem;                  // "Options" item for menu
    NSMenu                  * optionsSubmenu;               //    Submenu for "Options"
    NSMenuItem              * preferencesTitleItem;         //    "Preferences" menu item (just used as a title)
    NSMenuItem              * putIconNearSpotlightItem;     //      "Put Icon Near the Spotlight Icon" menu item
    NSMenuItem              * monitorConfigurationDirItem;  //      "Monitor the Configuration Folder" menu item
    NSMenuItem              * showConnectedDurationsItem;   //      "Show Connection Timers" menu item
    NSMenuItem              * warnAboutSimultaneousItem;    //      "Warn About Simultaneous Connections" menu item
    NSMenuItem              * useShadowCopiesItem;          //      "Use Shadow Copies of Configuration Files" menu item
    NSMenuItem              * autoCheckForUpdatesItem;      //      "Automatically Check for Updates" menu item
    NSMenuItem              * reportAnonymousInfoItem;      //        "Report Anonymous System Info" menu item
    NSMenuItem              * checkForUpdatesNowItem;       //    "Check For Updates Now" menu item
    NSMenuItem              * aboutItem;                    //    "About..." item for menu
	NSMenuItem              * detailsItem;                  // "Details..." item for menu
    NSMenuItem              * quitItem;                     // "Quit..." item for menu

    NSAnimation             * theAnim;                      // For animation of the Tunnelblick icon in the Status Bar
    NSMutableArray          * animImages;                   // Images for animation of the Tunnelblick icon in the Status Bar
    int                       animNumFrames;                // # of images
    NSImage                 * connectedImage;               // Image to display when one or more connections are active
    NSImage                 * mainImage;                    // Image to display when there are no connections active

    NSString                * configDirPath;                // Path to folder that has configuration files
    BOOL                      configDirIsDeploy;            // Indicates that configDirPath is /Resources/Deploy

    NSMutableArray          * myConfigArray;                // Sorted list of all configuration filenames including .ovnp or .conf extensions
    NSMutableDictionary     * myVPNConnectionDictionary;    // List of all configurations and corresponding VPNConnections
                                                            // Key is the configuration filename including extension, object is the VPNConnection object for the configuration
    NSMutableArray          * connectionArray;              // VPNConnections that are currently connected
    NSMutableArray          * connectionsToRestore;         // VPNConnections to be restored when awaken from sleep
    
    BOOL                      unloadKextsAtTermination;     // Indicates tun/tap kexts should be unloaded at program termination
    
    NSString                * lastState;                    // Most recent state of connection (EXITING, SLEEP, etc.)
    
    BOOL                      logWindowIsOpen;              // Indicates if OpenVPN Log window is being displayed
    
    UKKQueue                * myQueue;                      // UKKQueue item for monitoring the configuration file folder
    
    NSTimer                 * showDurationsTimer;           // Used to periodically update display of connections' durations in the Details... Window (i.e, logWindow)
	
    SUUpdater               * updater;                      // Sparkle Updater item used to check for updates to the program
}

// Button and checkbox actions
-(IBAction)         monitorConnectionPrefButtonWasClicked:  (id)                sender;
-(IBAction)         autoLaunchPrefButtonWasClicked:         (id)                sender;
-(IBAction)         checkForUpdates:                        (id)                sender;
-(IBAction)         clearLog:                               (id)                sender;
-(IBAction)         connect:                                (id)                sender;
-(IBAction)         disconnect:                             (id)                sender;
-(IBAction)         editConfig:                             (id)                sender;
-(IBAction)         nameserverPrefButtonWasClicked:         (id)                sender;

// Menu actions
-(IBAction)         togglePlaceIconNearSpotlight:           (NSMenuItem *)      item;   // On Options submenu
-(IBAction)         toggleMonitorConfigurationDir:          (NSMenuItem *)      item;   // On Options submenu
-(IBAction)         toggleWarnAboutSimultaneous:            (NSMenuItem *)      item;   // On Options submenu
-(IBAction)         toggleUseShadowCopies:                  (NSMenuItem *)      item;   // On Options submenu
-(IBAction)         toggleAutoCheckForUpdates:              (NSMenuItem *)      item;   // On Options submenu
-(IBAction)         toggleReportAnonymousInfo:              (NSMenuItem *)      item;   // On Options submenu
-(IBAction)         openLogWindow:                          (id)                sender;
-(IBAction)         quit:                                   (id)                sender;

-(void)             activateStatusMenu;
-(void)             addConnection:                          (id)                sender;
-(void)             cleanup;
-(void)             createDefaultConfigUsingTitle:          (NSString *)        ttl
                                       andMessage:          (NSString *)        msg;
-(void)             createMenu;
-(void)             createStatusItem;
-(void)             dmgCheck;
-(void)             fileSystemHasChanged:                   (NSNotification *)  n;
-(NSMutableArray *) getConfigs;
-(BOOL)             getCurrentAutoLaunchSetting;
-(NSMenuItem *)     initPrefMenuItemWithTitle:              (NSString *)        title
                        andAction:                          (SEL)               action
                       andToolTip:                          (NSString *)        tip
               atIndentationLevel:                          (int)               indentLevel
                 andPreferenceKey:                          (NSString *)        prefKey
                          negated:                          (BOOL)              negatePref;
-(void)             initialiseAnim;
-(void)             killAllConnections;
-(void)             loadKexts; 
-(void)             loadMenuIconSet;
-(void)             localizeControl:                        (NSButton *)        button       
                    shiftRight:                             (NSButton *)        buttonToRight
                    shiftLeft:                              (NSButton *)        buttonToLeft
                    shiftSelfLeft:                          (BOOL)              shiftSelfLeft;
-(void)             moveSoftwareUpdateWindowToForeground;
-(NSString *)       openVPNLogHeader;
-(void)             removeConnection:                       (id)                sender;
-(BOOL)             runInstallerRestoreDeploy:              (BOOL)              restore
                                    repairApp:              (BOOL)              repairIt
                                 removeBackup:              (BOOL)              removeBkup;
-(void)             saveMonitorConnectionCheckboxState:     (BOOL)              inBool;
-(void)             saveAutoLaunchCheckboxState:            (BOOL)              inBool;
-(VPNConnection *)  selectedConnection;
-(NSTextView *)     selectedLogView;
-(void)             setState:                               (NSString *)        newState;
-(void)             toggleMenuItem:                         (NSMenuItem *)      item
                 withPreferenceKey:                         (NSString *)        prefKey;
-(void)             unloadKexts; 
-(void)             updateMenuAndLogWindow;
-(void)             updateTabLabels;
-(void)             updateUI;
-(void)             validateLogButtons;
-(BOOL)             validateMenuItem:                       (NSMenuItem *)      anItem;
-(void)             waitUntilGone:                          (pid_t)             pid;
-(void)             watcher:                                (UKKQueue *)        kq
                    receivedNotification:                   (NSString *)        nm
                    forPath:                                (NSString *)        fpath;

@end
