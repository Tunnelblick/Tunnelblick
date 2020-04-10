/*
 * Copyright 2004, 2005, 2006, 2007, 2008, 2009 by Angelo Laub
 * Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019. All rights reserved.
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

#import "TBPerformer.h"

@class AlertWindowController;
@class AuthAgent;
@class LogDisplay;
@class NetSocket;
@class StatusWindowController;

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

typedef unsigned long long TBByteCount;

struct RateInfo {
    TBByteCount      lastInBytecount;   // Input  bytecount in last interval
    TBByteCount      lastOutBytecount;  // Output bytecount in last interval
    NSTimeInterval   lastTimeInterval;  // Number of seconds in last interval        
};

#define RB_SIZE 30

struct Statistics {
    NSDate        *  lastSet;           // Date/time statistics were last set
    TBByteCount      totalInBytecount;  // Total in, out  bytecount since tunnel up
    TBByteCount      totalOutBytecount;
    TBByteCount      totalInByteCountBeforeThisConnection; // Total in, out bytecounts since Tunnelblick was launched
    TBByteCount      totalOutByteCountBeforeThisConnection;
    int              rbIx;              // Index of the next item in ringBuffer to write to
    struct RateInfo  rb[RB_SIZE];       // Ring buffer holding info for rate statistics
};

@interface VPNConnection : TBPerformer <NSWindowDelegate>
{
    NSString      * configPath;         // Full path to the .tblk package
    // The configuration file MUST reside (for security reasons) in
    //      Tunnelblick.app/Contents/Resources/Deploy
    // or   ~/Library/Application Support/Tunnelblick/Configurations
    // or   /Library/Application Support/Tunnelblick/Shared
    // or   /Library/Application Support/Tunnelblick/Users/<username>
    // or a subdirectory of one of them
	NSString      * displayName;        // The configuration name, including directory prefix, as sometimes displayed to the user NON-LOCALIZED
    //                                     BUT only sometimes. In the menu and in the left navigation tabs, the leading
    //                                     directory references are stripped out (e.g., abc/def/ghi.ovpn becomes just "ghi"
    
	NSString      * localizedName;      // The configuration name, localized
	
    NSMenuItem    * menuItem;           // Menu item in the Tunnelblick icon's menu for this connection

	NSDate        * connectedSinceDate; // Initialized to time connection init'ed, set to current time upon connection
	NSString      * lastState;          // Known get/put externally as "state" and "setState", this is "EXITING", "CONNECTED", "SLEEP", etc.
    NSString      * tunOrTap;           // nil, "tun", or "tap", as determined by parsing the configuration file
    NSString      * requestedState;     // State of connection that was last requested by user (or automation), or that the user is expecting
    //                                  // after an error alert. Defaults to "EXITING" (meaning disconnected); the only other valid value is "CONNECTED"
    LogDisplay    * logDisplay;         // Used to store and display the OpenVPN log
	NetSocket     * managementSocket;   // Used to communicate with the OpenVPN process created for this connection
	AuthAgent     * myAuthAgent;
    NSSound       * tunnelDownSound;    // Sound to play when tunnel is broken down
    NSSound       * tunnelUpSound;      // Sound to play when tunnel is established
    NSString      * ipAddressBeforeConnect; // IP address of client (this computer) obtained from webpage before a connection was last attempted
    //                                      // (Webpage URL is from the forced-preference "IPCheckURL" string, or from the "IPCheckURL" string in Info.plist)
    NSString      * serverIPAddress;        // IP address of IPCheck server obtained from webpage before a connection was last attempted
    StatusWindowController * statusScreen;    // Status window, may or may not be displayed
    
    AlertWindowController * slowDisconnectWindowController;
    
	NSString      * sanitizedConfigurationFileContents;
	NSString      * condensedSanitizedConfigurationFileContents;
	
	NSString	  * dynamicChallengeUsername; // When nil, no dynamic challenge info is valid
	NSString	  * dynamicChallengeState;
	NSString	  * dynamicChallengePrompt;
	NSString	  * dynamicChallengeFlags;
	NSString      * authRetryParameter;		// Parameter from auth-retry as seen in configuration file (or nil if not seen)
	
	pid_t           pid;                // 0, or process ID of OpenVPN process created for this connection
	unsigned int    portNumber;         // 0, or port number used to connect to management socket
    volatile int32_t avoidHasDisconnectedDeadlock; // See note at start of 'hasDisconnected' method
    
	NSMutableArray * messagesIfConnectionFails; // Localized strings to display if connection failed (e.g., "Unrecognized option...")
	
    VPNConnectionUserWantsState
                    userWantsState;     // Indicates what the user wants to do about authorization failures
    
    unsigned        connectedUseScripts;// The value of 'useScripts' when the configuration was connected
    NSString *      connectedCfgLocCodeString; // The value of 'cfgLocCode' (as a string) when the configuration was connected
	
    // These variables are updated (outside of the main thread) by netsocket:dataAvailable:
    struct Statistics statistics;
    NSDate        * bytecountsUpdated;  // Time variables were last updated
    NSArray       * argumentsUsedToStartOpenvpnstart;   // The arguments that were last used to run openvpnstart
    
	BOOL            waitingForNetworkAvailability;
	BOOL            wereWaitingForNetworkAvailability;
	BOOL            stopWaitForNetworkAvailabilityThread;
	
    pthread_mutex_t bytecountMutex;     // Used to avoid race conditions when accessing the above

    BOOL            bytecountMutexOK;   // Flag that the mutex is set up. (If not, we don't do statistics)
    BOOL            serverNotClient;    // Flag that the connection is a server connection, so statistics are not available

    BOOL            authFailed;         // Indicates authorization failed
    BOOL            credentialsAskedFor;// Indicates whether credentials have been asked for but not provided
	BOOL            useManualChallengeResponseOnce;
	BOOL		    doNotClearUseManualChallengeResponseOnceOnNextConnect;
    BOOL            usedModifyNameserver;// True iff "Set nameserver" was used for the current (or last) time this connection was made or attempted
    BOOL            tryingToHookup;     // True iff this connection is trying to hook up to an instance of OpenVPN
    BOOL            initialHookupTry;   // True iff this is the initial hookup try (not as a result of a connection attempt)
    BOOL            isHookedup;         // True iff this connection is hooked up to an existing instance of OpenVPN
    BOOL            areDisconnecting;   // True iff the we are in the process of disconnecting
	BOOL            disconnectWhenStateChanges; // True iff we should disconnect when a state changes. This is needed because OpenVPN doesn't respond
    //                                          // to SIGTERM when doing name resolution and so a SIGTERM while doing a reconnect can be lost. By trying
    //                                          // to disconnect each time the state changes, we can catch OpenVPN when it is not in the "RESOLVE" state.
    BOOL            haveConnectedSince; // True iff the we have succesfully connected since the latter of Tunnelblick launch, computer wakeup, or became active user
    BOOL            areConnecting;      // True iff the we are in the process of connecting
    BOOL            loadedOurTap;       // True iff last connection loaded our tap kext
    BOOL            loadedOurTun;       // True iff last connection loaded our tun kext
    BOOL            logFilesMayExist;   // True iff have tried to connect (thus may have created log files) or if hooked up to existing OpenVPN process
    BOOL            showingStatusWindow; // True iff displaying statusScreen
    BOOL            ipCheckLastHostWasIPAddress; // Host part of server's URL that was last used to check IP info was an IP address, not a name
	BOOL            speakWhenConnected; // True iff should speak that we are connected
	BOOL            speakWhenDisconnected; // True iff should speak that we are disconnected
    BOOL            hasAuthUserPass;    // True iff configuration has a 'auth-user-pass' option. VALID ONLY IF tunOrTap is not nil
    BOOL            discardSocketInput; // True if should discard anything from the managment socket (set after receiving status of EXITING)
	
	BOOL volatile	connectAfterDisconnect; // True if need to connect again after the disconnect completes
	BOOL volatile	connectAfterDisconnectUserKnows; // Argument for the reconnect
    BOOL volatile   completelyDisconnected; // True only after GUI has caught up to disconnect request

	BOOL volatile   skipConfigurationUpdateCheckOnce; // True only after have skipped a configuration update, so the next
													  // connection attempt will not try to check for the update
}

// PUBLIC METHODS:
// (Private method interfaces are in VPNConnection.m)

-(void)             addMessageToDisplayIfConnectionFails: (NSString *) message;

-(void)             addToLog:                   (NSString *)        text;

-(BOOL)             authFailed;

-(BOOL)             checkConnectOnSystemStart:  (BOOL)              startIt;

-(void)             clearLog;

-(void)             updateStatisticsDisplay;

-(NSString *)       configPath;

-(BOOL)				configurationIsSecureOrMatchesShadowCopy;

-(NSDate *)         connectedSinceDate;

-(NSString *)       connectTimeString;

-(void)             connectOnMainThreadUserKnows: (NSNumber *)        userKnows;

-(void)             connect:                    (id)                sender
                  userKnows:                    (BOOL)              userKnows;

-(void)             connectUserKnows:           (NSNumber *)     userKnowsNumber;

-(NSArray *)        currentIPInfoWithIPAddress: (BOOL)           useIPAddress
                               timeoutInterval: (NSTimeInterval) timeoutInterval;
-(BOOL)             startDisconnectingUserKnows: (NSNumber *)    userKnows;

-(BOOL)             waitUntilDisconnected;

-(void)             waitUntilCompletelyDisconnected;

-(NSUInteger)		defaultVersionIxFromVersionNames: (NSArray *) versionNames;

-(void) 			disconnectBecauseShuttingDownComputer;

-(NSString *)       displayLocation;

-(NSString *)       displayName;

-(void)             displaySlowDisconnectionDialogLater;

-(void)             fadeAway;

-(NSUInteger)       getOpenVPNVersionIxToUseConnecting: (BOOL) connecting;

-(void)             hasDisconnected;

-(void)             reloadPreferencesFromTblk;

-(void)             readStatisticsTo:           (struct Statistics *)  returnValue;

-(void)				initializeAuthAgent;

-(id)               initWithConfigPath:         (NSString *)    inPath
                       withDisplayName:         (NSString *)    inDisplayName;

-(void)             invalidateConfigurationParse;

-(BOOL)             tryingToHookup;
-(BOOL)             isHookedup;

-(BOOL)             isConnected;

-(BOOL)             isDisconnected;

-(BOOL)             noOpenvpnProcess;

-(BOOL)             launchdPlistWillConnectOnSystemStart;

-(BOOL)				makeShadowCopyMatchConfiguration;

-(BOOL)             mayConnectWhenComputerStarts;

-(NSArray *)        modifyNameserverOptionList;

-(void)             netsocket:                  (NetSocket *)   socket
                dataAvailable:                  (unsigned)      inAmount;

-(void)             netsocketConnected:         (NetSocket *)   socket;

-(void)             netsocketDisconnected:      (NetSocket *)   inSocket;

-(NSString *)       openvpnLogPath;

-(pid_t)            pid;

-(void)             reInitialize;

-(NSString *)       requestedState;

-(NSString *)       sanitizedConfigurationFileContents;
-(NSString *)       condensedSanitizedConfigurationFileContents;

-(void)				sendSigtermToManagementSocket;

-(void)             setConnectedSinceDate:      (NSDate *)          value;

-(void)             setState:                   (NSString *)    newState;

-(BOOL)				shadowCopyIsIdentical;

-(BOOL)             shouldDisconnectWhenBecomeInactiveUser;

-(void)             showStatusWindowForce:      (BOOL)          force;

-(void)             speakActivity:              (NSString *)    activityName;

-(void)             startMonitoringLogFiles;
-(void)             stopMonitoringLogFiles;

-(NSString*)        state;

-(void)             stopTryingToHookup;

-(IBAction)         toggle:                     (id)            sender;

-(void)             tryToHookup:                (NSDictionary *) dict;

-(int)              useDNSStatus;

-(BOOL)             usedModifyNameserver;

-(BOOL)				userOrGroupOptionExistsInConfiguration;

TBPROPERTY_READONLY(StatusWindowController *,  statusScreen)
TBPROPERTY_READONLY(NSString *,                tapOrTun)
TBPROPERTY_READONLY(AuthAgent *,               authAgent)
TBPROPERTY_WRITEONLY(NSSound *,                tunnelUpSound,                    setTunnelUpSound)
TBPROPERTY_WRITEONLY(NSSound *,                tunnelDownSound,                  setTunnelDownSound)
TBPROPERTY_WRITEONLY(BOOL,                     speakWhenConnected,               setSpeakWhenConnected)
TBPROPERTY_WRITEONLY(BOOL,                     speakWhenDisconnected,            setSpeakWhenDisconnected)
TBPROPERTY_WRITEONLY(BOOL,                     skipConfigurationUpdateCheckOnce, setSkipConfigurationUpdateCheckOnce)
TBPROPERTY(          NSMenuItem *,             menuItem,                         setMenuItem)
TBPROPERTY(          NSDate *,                 bytecountsUpdated,                setBytecountsUpdated)
TBPROPERTY(          NSArray *,                argumentsUsedToStartOpenvpnstart, setArgumentsUsedToStartOpenvpnstart)
TBPROPERTY(          AlertWindowController *,  slowDisconnectWindowController,   setSlowDisconnectWindowController)
TBPROPERTY(          NSString *,               ipAddressBeforeConnect,           setIpAddressBeforeConnect)
TBPROPERTY(          NSString *,               dynamicChallengeUsername,         setDynamicChallengeUsername)
TBPROPERTY(          NSString *,               dynamicChallengeState,            setDynamicChallengeState)
TBPROPERTY(          NSString *,               dynamicChallengePrompt,           setDynamicChallengePrompt)
TBPROPERTY(          NSString *,               dynamicChallengeFlags,            setDynamicChallengeFlags)
TBPROPERTY(          NSString *,               authRetryParameter,               setAuthRetryParameter)
TBPROPERTY(          NSString *,               serverIPAddress,                  setServerIPAddress)
TBPROPERTY(          NSString *,               connectedCfgLocCodeString,        setConnectedCfgLocCodeString)
TBPROPERTY(          BOOL,                     ipCheckLastHostWasIPAddress,      setIpCheckLastHostWasIPAddress)
TBPROPERTY(          BOOL,                     haveConnectedSince,               setHaveConnectedSince)
TBPROPERTY(          BOOL,                     logFilesMayExist,                 setLogFilesMayExist)
TBPROPERTY(          NSString *,               localizedName,                    setLocalizedName)

//*********************************************************************************************************
//
// AppleScript support
//
//*********************************************************************************************************

-(NSScriptObjectSpecifier *) objectSpecifier;

-(NSString *)                autoConnect;
-(NSString *)                bytesIn;
-(NSString *)                bytesOut;

@end
