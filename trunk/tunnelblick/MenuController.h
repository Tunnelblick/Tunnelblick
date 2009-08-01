/*
 * Copyright (c) 2004 Angelo Laub
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
#import <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <stdlib.h>
#include <errno.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>
#import <CoreServices/CoreServices.h>
#import "KeyChain.h"
#import "NetSocket.h"
#import "NSApplication+LoginItem.h"
#import "NSArray+cArray.h"
#import <Foundation/NSDebug.h>
#import "VPNConnection.h"
#import "UKKQueue/UKKQueue.h"
#include <Security/Authorization.h>
#include <Security/AuthorizationTags.h>
#import <sys/types.h>
#import <sys/stat.h>
#import <Sparkle/SUUpdater.h>
#import "helper.h"

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
    IBOutlet NSButton       * useNameserverCheckbox;

    NSMutableArray          * animImages;
    int                       animNumFrames;
    NSImage                 * connectedImage;
    NSImage                 * mainImage;

    NSMenuItem              * aboutItem;
    NSMutableArray          * activeConnections;
	NSUserDefaults          * appDefaults;
    NSMutableArray          * connectionArray; 
    NSMutableArray          * connectionsToRestore;
	NSMenuItem              * detailsItem;
    NSString                * lastState;
    IBOutlet NSWindow       * logWindow;
    NSArray                 * myConfigArray;
    NSArray                 * myConfigModDatesArray;
	NSMutableArray          * myVPNConnectionArray;
    NSMutableDictionary     * myVPNConnectionDictionary;
    IBOutlet id               myVPNMenu;
	int                       numberOfConfigs;
    int                       oldNumberOfConfigs;
    NSMenuItem              * quitItem;
    NSTimer                 * showDurationsTimer;           //Used to periodically update display of connections' durations in the Details... Window (i.e, logWindow)
    IBOutlet NSMenuItem     * statusMenuItem;
    IBOutlet NSTabView      * tabView;
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
-(IBAction)         disconnect:                     (id) sender;
-(void)             dmgCheck;
-(IBAction)         editConfig:                     (id) sender;
-(void)             fileSystemHasChanged:           (NSNotification *) n;
-(NSArray *)        getConfigs;
-(BOOL)             getCurrentAutoLaunchSetting;
-(NSArray *)        getModDates:                    (NSArray *) fileArray;
-(void)             initialiseAnim;
-(void)             killAllConnections;
-(void)             kqueue:                         (UKKQueue*) kq      receivedNotification: (NSString*) nm        forFile: (NSString*) fpath;
-(void)             loadMenuIconSet;
-(void)             moveAllWindowsToForeground;
-(IBAction)         nameserverPrefButtonWasClicked: (id) sender;
-(IBAction)         openLogWindow:                  (id) sender;
-(IBAction)         quit:                           (id) sender;
-(void)             removeConnection:               (id) sender;
-(BOOL)             repairPermissions;
-(void)             saveAutoLaunchCheckboxState:    (BOOL) inBool;
-(VPNConnection*)   selectedConnection;
-(NSTextView*)      selectedLogView;
-(void)             setState:                       (NSString*) newState;
-(void)             updateMenu;
-(void)             updateTabLabels;
-(void)             updateUI;
-(IBAction)         validateLogButtons;

@end
