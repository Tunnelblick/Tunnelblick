/*
 * Copyright (c) 2004, 2005, 2006, 2007, 2008, 2009 Angelo Laub
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
#import "NetSocket.h"
#import "AuthAgent.h"

@interface VPNConnection : NSObject {
	NSString      * configPath;         // This contains the filename and extension (not the full path) of the configuration file
	NSDate        * connectedSinceDate; // Initialized to time connection init'ed, set to current time upon connection
	id              delegate;
	NSString      * lastState;          // Known get/put externally as "state" and "setState", this is "EXITING", "CONNECTED", "SLEEP", etc.
	NSTextStorage * logStorage;         // nil, or contains entire log (or that part of log since it was cleared)
	NetSocket     * managementSocket;   // Used to communicate with the OpenVPN process created for this connection
	AuthAgent     * myAuthAgent;
	pid_t           pid;                // 0, or process ID of OpenVPN process created for this connection
	unsigned int    portNumber;         // 0, or port number used to connect to management socket
}

// Used exernally (outside of VPNConnection):
-(NSString*)        configName;
-(NSString*)        configPath;
-(NSDate *)         connectedSinceDate;
-(IBAction)         connect:                    (id) sender;
-(IBAction)         disconnect:                 (id) sender;
-(id)               initWithConfig:             (NSString *)    inConfig;
-(BOOL)             isConnected;
-(BOOL)             isDisconnected;
-(NSTextStorage*)   logStorage;
-(void)             netsocket:                  (NetSocket *)   socket      dataAvailable:  (unsigned) inAmount;
-(void)             netsocketConnected:         (NetSocket *)   socket;
-(void)             netsocketDisconnected:      (NetSocket *)   inSocket;
-(void)             setDelegate:                (id)            newDelegate;
-(void)             setState:                   (NSString *)    newState;
-(NSString*)        state;
-(IBAction)         toggle:                     (id)            sender;

// Used internally (only by VPNConnection):
-(void)             addToLog:                   (NSString *)    text           atDate:         (NSCalendarDate *) date;
-(BOOL)             configNeedsRepair:          (NSString *)    configFile;
-(void)             connectToManagementSocket;
-(unsigned int)     getFreePort;
-(void)             killProcess;
-(void)             processLine:                (NSString *)    line;
-(OSStatus)         repairConfigPermissions:    (NSString *)    configFile;
-(void)             setConnectedSinceDate:      (NSDate *)      value;
-(void)             setManagementSocket:        (NetSocket *)   socket;

@end
