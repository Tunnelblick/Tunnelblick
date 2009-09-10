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
BOOL needsRepair(void);

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

    NSMutableArray          * animImages;
    int                       animNumFrames;
    NSImage                 * connectedImage;
    NSImage                 * mainImage;

    NSMenuItem              * aboutItem;
	NSUserDefaults          * appDefaults;
    NSMutableArray          * connectionArray; 
    NSMutableArray          * connectionsToRestore;
	NSMenuItem              * detailsItem;
    NSString                * lastState;
    BOOL                      logWindowIsOpen;
    NSMutableArray          * myConfigArray;
    NSMutableDictionary     * myVPNConnectionDictionary;
    IBOutlet id               myVPNMenu;
	int                       numberOfConfigs;
    int                       oldNumberOfConfigs;
    NSMenuItem              * quitItem;
    NSTimer                 * showDurationsTimer;           //Used to periodically update display of connections' durations in the Details... Window (i.e, logWindow)
    IBOutlet NSMenuItem     * statusMenuItem;
    NSAnimation             * theAnim;
    NSStatusItem            * theItem; 
	SUUpdater               * updater;
    NSMutableDictionary     * userDefaults;
}

-(void)             activateStatusMenu;
-(IBAction)         autoLaunchPrefButtonWasClicked: (id) sender;
-(void)             addConnection:                  (id) sender;
-(void)             cleanup;
-(IBAction)         clearLog:                       (id) sender;
-(IBAction)         connect:                        (id) sender;
-(void)             createDefaultConfig;
-(void)             createMenu;
-(IBAction)         disconnect:                     (id) sender;
-(void)             dmgCheck;
-(IBAction)         editConfig:                     (id) sender;
-(void)             fileSystemHasChanged:           (NSNotification *) n;
-(NSMutableArray *) getConfigs;
-(BOOL)             getCurrentAutoLaunchSetting;
-(void)             initialiseAnim;
-(void)             killAllConnections;
-(void)             watcher:                         (UKKQueue*) kq      receivedNotification: (NSString*) nm        forPath: (NSString*) fpath;
-(void)             loadMenuIconSet;
-(void)             moveSoftwareUpdateWindowToForeground;
-(IBAction)         nameserverPrefButtonWasClicked: (id) sender;
-(IBAction)         openLogWindow:                  (id) sender;
-(IBAction)         quit:                           (id) sender;
-(void)             removeConnection:               (id) sender;
-(BOOL)             repairPermissions;
-(void)             saveAutoLaunchCheckboxState:    (BOOL) inBool;
-(VPNConnection*)   selectedConnection;
-(NSTextView*)      selectedLogView;
-(void)             setState:                       (NSString*) newState;
-(void)             updateMenuAndLogWindow;
-(void)             updateTabLabels;
-(void)             updateUI;
-(IBAction)         validateLogButtons;

@end
