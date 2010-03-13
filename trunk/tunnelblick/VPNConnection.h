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
#import "NamedPipe.h"

@interface VPNConnection : NSObject {
    NSString      * configPath;         // Full path to the configuration file.
                                        // The file MUST reside (for security reasons) in either
                                        //      Tunnelblick.app/Contents/Resources/Deploy
                                        // or
                                        //      ~/Library/Application Support/Tunnelblick/Configurations
                                        // or a subdirectory of either of them
	NSString      * displayName;        // The configuration name as displayed to the user

	NSDate        * connectedSinceDate; // Initialized to time connection init'ed, set to current time upon connection
	id              delegate;
	NSString      * lastState;          // Known get/put externally as "state" and "setState", this is "EXITING", "CONNECTED", "SLEEP", etc.
	NSTextStorage * logStorage;         // nil, or contains entire log (or that part of log since it was cleared)
	NetSocket     * managementSocket;   // Used to communicate with the OpenVPN process created for this connection
	AuthAgent     * myAuthAgent;
    NamedPipe     * myPipe;             // Up/down scripts send data through this pipe and we append the data to the OpenVPN Log
    NSMutableString * myPipeBuffer;     // Buffer in which we collect data from the pipe until the ETX-LF character combination that completes a log entry
	pid_t           pid;                // 0, or process ID of OpenVPN process created for this connection
	unsigned int    portNumber;         // 0, or port number used to connect to management socket
    BOOL            usedSetNameserver;  // True iff "Set nameserver" was used for the current (or last) time this connection was made or attempted
    BOOL            authenticationFailed; // True iff a message from OpenVPN has been received that password/passphrase authentication failed and the user hasn't been notified yet
}

// PUBLIC METHODS:
// (Private method interfaces are in VPNConnection.m)

-(void)             addToLog:                   (NSString *)        text
                      atDate:                   (NSCalendarDate *)  date;
-(void)             appendDataToLog:            (NSData *)          data;
-(NSString *)       configPath;
-(NSDate *)         connectedSinceDate;
-(IBAction)         connect:                    (id) sender;
-(void)             destroyPipe;
-(IBAction)         disconnect:                 (id) sender;
-(NSString *)       displayName;
-(void)             emptyPipe;
-(id)               initWithConfigPath:         (NSString *)    inPath
                       withDisplayName:         (NSString *)    inDisplayName;
-(BOOL)             isConnected;
-(BOOL)             isDisconnected;
-(NSString *)       lastPartsOfPath;
-(NSTextStorage*)   logStorage;
-(void)             netsocket:                  (NetSocket *)   socket      dataAvailable:  (unsigned)      inAmount;
-(void)             netsocketConnected:         (NetSocket *)   socket;
-(void)             netsocketDisconnected:      (NetSocket *)   inSocket;
-(NSString *)       preferencePrefix;
-(void)             setDelegate:                (id)            newDelegate;
-(void)             setState:                   (NSString *)    newState;
-(NSString*)        state;
-(IBAction)         toggle:                     (id)            sender;
-(BOOL)             unprotectConfigurationFile: (NSString *)    configFilePath;
-(BOOL)             usedSetNameserver;

@end
