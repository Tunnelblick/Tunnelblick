/*
 * Copyright 2004, 2005, 2006, 2007, 2008, 2009 by Angelo Laub
 * Contributions by Jonathan K. Bullard Copyright 2010, 2011
 *
 *  This file is part of Tunnelblick.
 *
 *  Tunnelblick is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  Tunnelblick is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *  or see http://www.gnu.org/licenses/.
 */

#import <Security/Security.h>
#import "AuthAgent.h"
#import "NetSocket.h"
#import "LogDisplay.h"
#import "StatusWindowController.h"

typedef enum
{
	authStateIdle,
	authStateFailed
} VPNConnectionAuthState;

typedef enum
{
	userWantsUndecided,
	userWantsRetry,
    userWantsAbandon
} VPNConnectionUserWantsState;

@interface VPNConnection : NSObject <NSWindowDelegate>
{
    NSString      * configPath;         // Full path to the configuration file (.conf or .ovpn file or .tblk package)
    // The configuration file MUST reside (for security reasons) in
    //      Tunnelblick.app/Contents/Resources/Deploy
    // or   ~/Library/Application Support/Tunnelblick/Configurations
    // or   /Library/Application Support/Tunnelblick/Shared
    // or   /Library/Application Support/Tunnelblick/Users/<username>
    // or a subdirectory of one of them
	NSString      * displayName;        // The configuration name, including directory prefix, as sometimes displayed to the user 
    //                                     BUT only sometimes. In the menu and in the left navigation tabs, the leading
    //                                     directory references are stripped out (e.g., abc/def/ghi.ovpn becomes just "ghi"

	NSDate        * connectedSinceDate; // Initialized to time connection init'ed, set to current time upon connection
	id              delegate;
	NSString      * lastState;          // Known get/put externally as "state" and "setState", this is "EXITING", "CONNECTED", "SLEEP", etc.
    NSString      * tunOrTap;           // nil, "tun", or "tap", as determined by parsing the configuration file
    NSString      * requestedState;     // State of connection that was last requested by user (or automation), or that the user is expecting
    //                                  // after an error alert. Defaults to "EXITING" (meaning disconnected); the only other valid value is "CONNECTED"
    LogDisplay    * logDisplay;         // Used to store and display the OpenVPN log
	NetSocket     * managementSocket;   // Used to communicate with the OpenVPN process created for this connection
	AuthAgent     * myAuthAgent;
    NSTimer       * forceKillTimer;     // Used to keep trying to kill a (temporarily, we hope) non-responsive OpenVPN process
    NSSound       * tunnelDownSound;    // Sound to play when tunnel is broken down
    NSSound       * tunnelUpSound;      // Sound to play when tunnel is established
    StatusWindowController * statusScreen;    // Status window, may or may not be displayed
    unsigned int    forceKillTimeout;   // Number of seconds to wait before forcing a disconnection
    unsigned int    forceKillInterval;  // Number of seconds between tries to kill a non-responsive OpenVPN process
    unsigned int    forceKillWaitSoFar; // Number of seconds since forceKillTimer was first set for this disconnection attempt
	pid_t           pid;                // 0, or process ID of OpenVPN process created for this connection
	unsigned int    portNumber;         // 0, or port number used to connect to management socket
    VPNConnectionUserWantsState
                    userWantsState;     // Indicates what the user wants to do about authorization failures
    BOOL            authFailed;         // Indicates authorization failed
    BOOL            credentialsAskedFor;// Indicates whether credentials have been asked for but not provided
    BOOL            usedModifyNameserver;// True iff "Set nameserver" was used for the current (or last) time this connection was made or attempted
    BOOL            tryingToHookup;     // True iff this connection is trying to hook up to an instance of OpenVPN
    BOOL            initialHookupTry;   // True iff this is the initial hookup try (not as a result of a connection attempt)
    BOOL            isHookedup;         // True iff this connection is hooked up to an existing instance of OpenVPN
    BOOL            areDisconnecting;   // True iff the we are in the process of disconnecting
    BOOL            loadedOurTap;       // True iff last connection loaded our tap kext
    BOOL            loadedOurTun;       // True iff last connection loaded our tun kext
    BOOL            logFilesMayExist;   // True iff have tried to connect (thus may have created log files) or if hooked up to existing OpenVPN process
    BOOL            showingStatusWindow; // True iff displaying statusScreen
}

// PUBLIC METHODS:
// (Private method interfaces are in VPNConnection.m)

-(void)             addToLog:                   (NSString *)        text;

-(BOOL)             authFailed;

-(BOOL)             checkConnectOnSystemStart:  (BOOL)              startIt
                                     withAuth:  (AuthorizationRef)  inAuthRef;

-(void)             clearLog;

-(NSString *)       configPath;

-(NSDate *)         connectedSinceDate;

-(NSString *)       connectTimeString;

-(void)             connect:                    (id)                sender
                  userKnows:                    (BOOL)              userKnows;

-(void)             deleteLogs;

-(void)             disconnectAndWait:          (NSNumber *)    wait
                            userKnows:          (BOOL)          userKnows;

-(NSString *)       displayLocation;

-(NSString *)       displayName;

-(void)             hasDisconnected;

-(id)               initWithConfigPath:         (NSString *)    inPath
                       withDisplayName:         (NSString *)    inDisplayName;

-(void)             invalidateConfigurationParse;

-(NSTextStorage *)  logStorage;

-(BOOL)             tryingToHookup;
-(BOOL)             isHookedup;

-(BOOL)             isConnected;

-(BOOL)             isDisconnected;

-(BOOL)             launchdPlistWillConnectOnSystemStart;

-(NSArray *)        modifyNameserverOptionList;

-(void)             netsocket:                  (NetSocket *)   socket
                dataAvailable:                  (unsigned)      inAmount;

-(void)             netsocketConnected:         (NetSocket *)   socket;

-(void)             netsocketDisconnected:      (NetSocket *)   inSocket;

-(NSString *)       openvpnLogPath;

-(pid_t)            pid;

-(void)             reInitialize;

-(NSString *)       requestedState;

-(void)             setDelegate:                (id)            newDelegate;

-(void)             setState:                   (NSString *)    newState;

-(BOOL)             shouldDisconnectWhenBecomeInactiveUser;

-(void)             startMonitoringLogFiles;
-(void)             stopMonitoringLogFiles;

-(NSString*)        state;

-(void)             stopTryingToHookup;

-(IBAction)         toggle:                     (id)            sender;

-(void)             tryToHookupToPort:          (int)           inPortNumber
                 withOpenvpnstartArgs:          (NSString *)    inStartArgs;

-(int)              useDNSStatus;

-(BOOL)             usedModifyNameserver;

//*********************************************************************************************************
//
// AppleScript support
//
//*********************************************************************************************************

-(NSScriptObjectSpecifier *) objectSpecifier;

-(NSString *)                autoConnect;

@end
