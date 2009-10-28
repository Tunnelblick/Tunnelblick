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

int connectStatus;
void executeAuthorized(NSString *toolPath,NSArray *arguments,AuthorizationRef myAuthorizationRef);

@class NetSocket;
BOOL needsInstallation();
BOOL isOwnedByRootAndHasPermissions(NSString *fPath, NSString * permsShouldHave);


@interface MenuController : NSObject
{
    IBOutlet NSButton       * autoLaunchCheckbox;
    IBOutlet NSButton       * clearButton;
    IBOutlet NSButton       * connectButton;
    IBOutlet NSButton       * disconnectButton;
    IBOutlet NSButton       * editButton;
    IBOutlet NSWindow       * logWindow;
    IBOutlet NSTabView      * tabView;
    IBOutlet NSButton       * useNameserverCheckbox;

    NSMutableArray          * animImages;                   // Images for animation of the Tunnelblick icon in the Status Bar
    int                       animNumFrames;                // # of images
    BOOL                      configDirIsDeploy;            // Indicates that configDirPath is /Resources/Deploy
    NSString                * configDirPath;                // Path to folder that has configuration files
    NSImage                 * connectedImage;               // Image to display when one or more connections are active
    NSImage                 * mainImage;                    // Image to display when there are no connections active

    NSMenuItem              * aboutItem;                    // "About..." item for menu
    NSMutableArray          * connectionArray;              // VPNConnections that are currently connected
    NSMutableArray          * connectionsToRestore;         // VPNConnections to be restored when awaken from sleep
	NSMenuItem              * detailsItem;                  // "Details..." item for menu
    NSString                * lastState;                    // Most recent state of connection (EXITING, SLEEP, etc.)
    BOOL                      logWindowIsOpen;              // Indicates if OpenVPN Log window is being displayed
    NSMutableArray          * myConfigArray;                // Sorted list of all configuration filenames including .ovnp or .conf extensions
    NSMutableDictionary     * myVPNConnectionDictionary;    // List of all configurations and corresponding VPNConnections
                                                            // Key is the configuration filename including extension, object is the VPNConnection object for the configuration
    IBOutlet id               myVPNMenu;                    // Tunnelblick's menu, displayed in Status Bar
    NSMenuItem              * quitItem;                     // "Quit..." item for menu
    NSTimer                 * showDurationsTimer;           // Used to periodically update display of connections' durations in the Details... Window (i.e, logWindow)
    IBOutlet NSMenuItem     * statusMenuItem;               // First line of menu, displays status (e.g. "Tunnelblick: 1 connection active"
    NSAnimation             * theAnim;                      // For animation of the Tunnelblick icon in the Status Bar
    NSStatusItem            * theItem;                      // Our place in the Status Bar
	SUUpdater               * updater;                      // Sparkle Updater item used to check for updates to the program
}

-(IBAction)         autoLaunchPrefButtonWasClicked: (id)                sender;
-(IBAction)         clearLog:                       (id)                sender;
-(IBAction)         connect:                        (id)                sender;
-(IBAction)         disconnect:                     (id)                sender;
-(IBAction)         editConfig:                     (id)                sender;
-(IBAction)         nameserverPrefButtonWasClicked: (id)                sender;
-(IBAction)         openLogWindow:                  (id)                sender;
-(IBAction)         quit:                           (id)                sender;

-(void)             activateStatusMenu;
-(void)             addConnection:                  (id)                sender;
-(void)             cleanup;
-(void)             createDefaultConfigUsingTitle:  (NSString *)        ttl
                                       andMessage:  (NSString *)        msg;
-(void)             createMenu;
-(void)             createStatusItem;
-(void)             dmgCheck;
-(void)             fileSystemHasChanged:           (NSNotification *)  n;
-(NSMutableArray *) getConfigs;
-(BOOL)             getCurrentAutoLaunchSetting;
-(void)             initialiseAnim;
-(void)             killAllConnections;
-(void)             loadMenuIconSet;
-(void)             localizeControl:                (NSButton *)        button       
                    shiftRight:                     (NSButton *)        buttonToRight
                    shiftLeft:                      (NSButton *)        buttonToLeft
                    shiftSelfLeft:                  (BOOL)              shiftSelfLeft;
-(void)             moveSoftwareUpdateWindowToForeground;
-(void)             removeConnection:               (id)                sender;
-(BOOL)             runInstaller:                   (BOOL)              restore;
-(void)             saveAutoLaunchCheckboxState:    (BOOL)              inBool;
-(VPNConnection *)  selectedConnection;
-(NSTextView *)     selectedLogView;
-(void)             setState:                       (NSString *)        newState;
-(void)             updateMenuAndLogWindow;
-(void)             updateTabLabels;
-(void)             updateUI;
-(IBAction)         validateLogButtons;
-(void)             watcher:                        (UKKQueue *)        kq
                    receivedNotification:           (NSString *)        nm
                    forPath:                        (NSString *)        fpath;

@end
