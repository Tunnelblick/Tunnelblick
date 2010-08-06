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

#import <Security/Security.h>
#import "AuthAgent.h"
#import "NetSocket.h"
#import "LogDisplay.h"

@interface VPNConnection : NSObject {
    NSString      * configPath;         // Full path to the configuration file (.conf or .ovpn file or .tblk package)
    // The configuration file MUST reside (for security reasons) in
    //      Tunnelblick.app/Contents/Resources/Deploy
    // or   ~/Library/Application Support/Tunnelblick/Configurations
    // or   /Library/Application Support/Tunnelblick/Shared
    // or   /Library/Application Support/Tunnelblick/User/<username>
    // or a subdirectory of one of them
	NSString      * displayName;        // The configuration name as displayed to the user

	NSDate        * connectedSinceDate; // Initialized to time connection init'ed, set to current time upon connection
	id              delegate;
	NSString      * lastState;          // Known get/put externally as "state" and "setState", this is "EXITING", "CONNECTED", "SLEEP", etc.
    LogDisplay    * logDisplay;         // Used to store and display the OpenVPN log
	NetSocket     * managementSocket;   // Used to communicate with the OpenVPN process created for this connection
	AuthAgent     * myAuthAgent;
	pid_t           pid;                // 0, or process ID of OpenVPN process created for this connection
	unsigned int    portNumber;         // 0, or port number used to connect to management socket
    BOOL            usedSetNameserver;  // True iff "Set nameserver" was used for the current (or last) time this connection was made or attempted
    BOOL            authenticationFailed; // True iff a message from OpenVPN has been received that password/passphrase authentication failed and the user hasn't been notified yet
    BOOL            tryingToHookup;     // True iff this connection is trying to hook up to an existing instance of OpenVPN
    BOOL            isHookedup;         // True iff this connection is hooked up to an existing instance of OpenVPN
    BOOL            areDisconnecting;   // True iff the we are in the process of disconnecting
    BOOL            connectedWithTap;   // True iff last connection was made loading our tap kext
    BOOL            connectedWithTun;   // True iff last connection was made loading our tun kext
    NSString      * tunOrTap;           // nil, "tun", or "tap", as determined by parsing the configuration file
}

// PUBLIC METHODS:
// (Private method interfaces are in VPNConnection.m)

-(void)             addToLog:                   (NSString *)        text;

-(BOOL)             checkConnectOnSystemStart:  (BOOL)              startIt
                                     withAuth:  (AuthorizationRef)  inAuthRef;

-(void)             clearLog;

-(NSString *)       configPath;

-(NSDate *)         connectedSinceDate;

-(void)             connect:                    (id) sender;

-(void)             disconnectAndWait:          (NSNumber *)    wait;

-(NSString *)       displayName;

-(id)               initWithConfigPath:         (NSString *)    inPath
                       withDisplayName:         (NSString *)    inDisplayName;

-(void)             invalidateConfigurationParse;

-(NSTextStorage *)  logStorage;

-(BOOL)             tryingToHookup;
-(BOOL)             isHookedup;

-(BOOL)             isConnected;

-(BOOL)             isDisconnected;

-(void)             netsocket:                  (NetSocket *)   socket
                dataAvailable:                  (unsigned)      inAmount;

-(void)             netsocketConnected:         (NetSocket *)   socket;

-(void)             netsocketDisconnected:      (NetSocket *)   inSocket;

-(pid_t)            pid;

-(void)             setDelegate:                (id)            newDelegate;

-(void)             setState:                   (NSString *)    newState;

-(NSString*)        state;

-(void)             stopTryingToHookup;

-(IBAction)         toggle:                     (id)            sender;

-(void)             tryToHookupToPort:          (int)           inPortNumber
                 withOpenvpnstartArgs:          (NSString *)    inStartArgs;

-(BOOL)             usedSetNameserver;


@end
