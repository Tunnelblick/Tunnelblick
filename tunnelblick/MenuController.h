/*
 * Copyright (c) 2004 Angelo Laub
 * Contributions by Dirk Theisen, Jens Ohlig, Waldemar Brodkorb
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
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
