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
    IBOutlet NSMenuItem *statusMenuItem;
    IBOutlet id myVPNMenu;
	
	NSMenuItem *detailsItem, *quitItem;
	NSUserDefaults  *appDefaults;
    NSMutableDictionary *userDefaults;
    NSStatusItem *theItem; 
    NSImage *mainImage, *transitionalImage0, *transitionalImage1, *transitionalImage2, *transitionalImage3;
    NSImage *connectedImage;
    NSImage *errorImage;
    NSImage *transitionalImage;
    //LogController *myLogController;
    NSMutableArray *connectionArray, *activeConnections, *connectionsToRestore;
    NSMutableDictionary *myVPNConnectionDictionary;
    NSString* lastState;
    NSArray *myConfigArray; 
	NSMutableArray *myVPNConnectionArray;
    NSAnimation *theAnim;
    // from LogController
    IBOutlet NSWindow *logWindow;
    IBOutlet NSButton *connectButton, *disconnectButton, *editButton, *clearButton, *autoLaunchCheckbox, *useNameserverCheckbox;
    IBOutlet NSTabView *tabView;
	int numberOfConfigs, oldNumberOfConfigs;
	SUUpdater *updater;
}

- (NSArray *)myConfigArray;



- (NSTextView*) selectedLogView;

- (void)activateStatusMenu;
-(void)addConnection:(id)sender;

- (void) updateUI;
- (IBAction)connect:(id)sender;
- (void)connectionError;
- (IBAction)disconnect:(id)sender;
- (void) configError;
-(NSArray *)getConfigs;
- (void) setState: (NSString*) newState;
- (IBAction) editConfig:(id)sender;
- (BOOL)validateMenuItem:(NSMenuItem*)anItem;
//-(NSString *)authenticate:keyChainManager;
- (IBAction) quit: (id) sender;
//-(void)setLogController:(id)controller withID:(NSNumber *)inID;
//-(id)logControllerwithID:(NSNumber *)inID;
-(void)killAllConnections;
- (IBAction) openLogWindow: (id) sender;
- (IBAction) validateLogButtons: (id) sender;
-(void)updateTabLabels;
-(void)saveAutoLaunchCheckboxState:(BOOL)inBool;
-(IBAction) nameserverPrefButtonWasClicked: (id) sender;
-(IBAction) autoLaunchPrefButtonWasClicked: (id) sender;
-(BOOL)getCurrentAutoLaunchSetting;
-(void)showAnimation;
-(void)removeConnection:(id)sender;
- (IBAction) validateLogButtons;
- (VPNConnection*) selectedConnection;
- (BOOL)windowShouldClose:(id)sender;
// from LogController
- (IBAction)clearLog:(id)sender;
-(void)addText:(NSString *)text;
-(void)setVisible:(BOOL)isVisible;
-(void)fileSystemHasChanged:(NSNotification *)n;
-(void) kqueue: (UKKQueue*)kq receivedNotification: (NSString*)nm forFile: (NSString*)fpath;
-(void)executeWithPrivileges:(NSString *)toolPath withArguments:(NSArray *)arguments;
@end
