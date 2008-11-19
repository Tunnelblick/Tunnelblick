/*
 * Copyright (c) 2004 Angelo Laub
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


#import <Cocoa/Cocoa.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>
#import <CoreServices/CoreServices.h>
#import "KeyChain.h"
#import "NetSocket.h"
#import <signal.h>
#import "NSApplication+LoginItem.h"
#import <Foundation/NSDebug.h>
#import "AuthAgent.h"
#import "helper.h"

@interface VPNConnection : NSObject {
	NSString *configPath;
	unsigned int portNumber;
	NetSocket *managementSocket;
//	LogController *myLogController;
	NSString* lastState;
	NSDate *connectedSinceDate;
	NSMenu *myMenu;
	
	NSTextStorage* logStorage;
	id delegate;
	AuthAgent *myAuthAgent;
	pid_t pid;
}

-(id) initWithConfig:(NSString *)inConfig;

- (void) setManagementSocket: (NetSocket*) socket;
- (IBAction) connect: (id) sender;
//- (IBAction) viewLog: (id) sender;
- (NSTextStorage*) logStorage;
- (void) setDelegate: (id) newDelegate;
- (NSString*) state;

- (void) connectToManagementSocket;
- (IBAction) disconnect: (id) sender;
- (IBAction) toggle: (id) sender;
-(BOOL) isDisconnected ;

- (void) netsocketConnected: (NetSocket*) socket;
- (void) processLine: (NSString*) line;
- (void) netsocket: (NetSocket*) socket dataAvailable: (unsigned) inAmount;
- (void) netsocketDisconnected: (NetSocket*) inSocket;
- (void) setState: (NSString*) newState;
-(void)addToLog:(NSString *)text atDate:(NSCalendarDate *)date;
-(void)setMenu:(NSMenu *)inMenu;
- (NSString*) configPath;
- (NSString*) configName;
- (NSDate *)connectedSinceDate;
- (void)setConnectedSinceDate:(NSDate *)value;





//- (IBAction) updateUI;

- (unsigned int) getFreePort;

@end
