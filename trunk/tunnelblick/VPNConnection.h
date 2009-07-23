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
	NSString      * configPath;
	NSDate        * connectedSinceDate;
	id              delegate;
	NSString      * lastState;
	NSTextStorage * logStorage;
	NetSocket     * managementSocket;
	AuthAgent     * myAuthAgent;
	NSMenu        * myMenu;
	pid_t           pid;
	unsigned int    portNumber;
}

-(void)             addToLog:                   (NSString *) text           atDate:         (NSCalendarDate *) date;
-(NSString*)        configName;
-(BOOL)             configNeedsRepair:          (NSString *) configFile;
-(NSString*)        configPath;
-(IBAction)         connect:                    (id) sender;
-(NSDate *)         connectedSinceDate;
-(void)             connectToManagementSocket;
-(IBAction)         disconnect:                 (id) sender;
-(unsigned int)     getFreePort;
-(id)               initWithConfig:             (NSString *) inConfig;
-(BOOL)             isConnected;
-(BOOL)             isDisconnected;
-(void)             killProcess;
-(NSTextStorage*)   logStorage;
-(void)             netsocket:                  (NetSocket *)   socket      dataAvailable:  (unsigned) inAmount;
-(void)             netsocketConnected:         (NetSocket *)   socket;
-(void)             netsocketDisconnected:      (NetSocket *)   inSocket;
-(void)             processLine:                (NSString *)    line;
-(OSStatus)         repairConfigPermissions:    (NSString *)    configFile;
-(void)             setConnectedSinceDate:      (NSDate *)      value;
-(void)             setDelegate:                (id)            newDelegate;
-(void)             setManagementSocket:        (NetSocket *)   socket;
-(void)             setMenu:                    (NSMenu *)      inMenu;
-(void)             setState:                   (NSString *)    newState;
-(NSString*)        state;
-(IBAction)         toggle:                     (id)            sender;

@end
