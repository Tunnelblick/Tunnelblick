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

#import "VPNConnection.h"
#import <CoreServices/CoreServices.h>
#import <Foundation/NSDebug.h>
#import <signal.h>
#import "KeyChain.h"
#import "NetSocket.h"
#import "NetSocket+Text.h"
#import "NSApplication+LoginItem.h"
#import "helper.h"
#import "MenuController.h"
#import "TBUserDefaults.h"
#import "ConfigurationManager.h"

extern NSMutableArray       * gConfigDirs;
extern NSString             * gDeployPath;
extern NSString             * gSharedPath;
extern NSFileManager        * gFileMgr;
extern TBUserDefaults       * gTbDefaults;

extern NSString * firstPartOfPath(NSString * thePath);

extern NSString * lastPartOfPath(NSString * thePath);

@interface VPNConnection()          // PRIVATE METHODS

-(void)             connectToManagementSocket;

-(unsigned int)     getFreePort;

-(void)             killProcess;                                                // Kills the OpenVPN process associated with this connection, if any

-(void)             processLine:                (NSString *)        line;

-(void)             setConnectedSinceDate:      (NSDate *)          value;

-(void)             setManagementSocket:        (NetSocket *)       socket;

@end

@implementation VPNConnection

-(id) initWithConfigPath: (NSString *) inPath withDisplayName: (NSString *) inDisplayName
{	
    if (self = [super init]) {
        configPath = [inPath copy];
        displayName = [inDisplayName copy];
        portNumber = 0;
		pid = 0;
		connectedSinceDate = [[NSDate alloc] init];
		[self addToLog:[[NSApp delegate] openVPNLogHeader] atDate: nil];
        lastState = @"EXITING";
		myAuthAgent = [[AuthAgent alloc] initWithConfigName:[self displayName]];
        NSArray  * pipePathComponents = [inPath pathComponents];
        NSArray  * pipePathComponentsAfter1st = [pipePathComponents subarrayWithRange: NSMakeRange(1, [pipePathComponents count]-1)];
        NSString * pipePath = [NSString stringWithFormat: @"/tmp/tunnelblick-%@.logpipe",
                               [pipePathComponentsAfter1st componentsJoinedByString: @"-"]];
        myPipeBuffer = [[NSMutableString alloc] initWithCapacity: 10000];
        myPipe = [[NamedPipe alloc] initPipeReadingFromPath: pipePath
                                              sendingDataTo: @selector(appendDataToLog:)
                                                  whichIsIn: self];
        if ( ! myPipe ) {
            NSLog(@"Unable to create pipe %@ for up/down scripts to write to OpenVPN Log", pipePath);
        }
        
        // If a package, set preferences that haven't been defined yet
        if (  [[inPath pathExtension] isEqualToString: @"tblk"]  ) {
            NSString * infoPath = [inPath stringByAppendingPathComponent: @"Contents/Info.plist"];
            NSDictionary * infoDict = [NSDictionary dictionaryWithContentsOfFile: infoPath];
            NSString * key;
            NSEnumerator * e = [infoDict keyEnumerator];
            while (  key = [e nextObject]  ) {
                if (  [key hasPrefix: @"TBPreference"]  ) {
                    NSString * preferenceKey = [displayName stringByAppendingString: [key substringFromIndex: [@"TBPreference" length]]];
                    if (  [gTbDefaults objectForKey: preferenceKey] == nil  ) {
                        [gTbDefaults setObject: [infoDict objectForKey: key] forKey: preferenceKey];
                    }
                }
            }
        }
    }
    
    return self;
}

-(NSString *) description
{
	return [NSString stringWithFormat:@"VPN Connection %@", displayName];
}

-(void)setPort:(unsigned int)inPort 
{
	portNumber = inPort;
}

-(unsigned int)port 
{
    return portNumber;
}

-(NSString *) configPath
{
    return [[configPath retain] autorelease];
}

// Also used as the prefix for preference and Keychain keys
-(NSString *) displayName
{
    return [[displayName retain] autorelease];
}

- (void) setManagementSocket: (NetSocket*) socket
{
    [socket retain];
    [managementSocket autorelease];
    managementSocket = socket;
    [managementSocket setDelegate: self];    
}

- (void) dealloc
{
    [self disconnect:self];
    [logStorage release];
    [managementSocket close];
    [managementSocket setDelegate: nil];
    [managementSocket release]; 
    [lastState release];
    [configPath release];
    [displayName release];
    [connectedSinceDate release];
    [myAuthAgent release];
    [myPipe release];
    [myPipeBuffer release];
    [super dealloc];
}


- (IBAction) connect: (id) sender
{
    if (  ! [gTbDefaults boolForKey:@"skipWarningAboutSimultaneousConnections"]  ) {
        // Count the total number of connections and what their "Set nameserver" status was at the time of connection
        int numConnections = 1;
        int numConnectionsWithSetNameserver = 0;
        if (  useDNSStatus(self)  ) {
            numConnectionsWithSetNameserver = 1;
        }
        VPNConnection * connection;
        NSEnumerator* e = [[[NSApp delegate] myVPNConnectionDictionary] objectEnumerator];
        while (connection = [e nextObject]) {
            if (  ! [[connection state] isEqualToString:@"EXITING"]  ) {
                numConnections++;
                if (  [connection usedSetNameserver]  ) {
                    numConnectionsWithSetNameserver++;
                }
            }
        }
        
        if (  numConnections != 1  ) {
            int button = TBRunAlertPanelExtended(NSLocalizedString(@"Do you wish to connect?", @"Window title"),
                                                 [NSString stringWithFormat:NSLocalizedString(@"Multiple simultaneous connections would be created (%d with 'Set nameserver', %d without 'Set nameserver').", @"Window text"), numConnectionsWithSetNameserver, (numConnections-numConnectionsWithSetNameserver) ],
                                                 NSLocalizedString(@"Connect", @"Button"),  // Default button
                                                 NSLocalizedString(@"Cancel", @"Button"),   // Alternate button
                                                 nil,
                                                 @"skipWarningAboutSimultaneousConnections",
                                                 NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
                                                 nil);
            if (  button == NSAlertAlternateReturn  ) {
                return;
            }
        }
    }
    
	NSString *cfgPath = [self configPath];
    NSString *altPath = [NSString stringWithFormat:@"/Library/Application Support/Tunnelblick/Users/%@/%@",
                         NSUserName(), lastPartOfPath(configPath)];

    if ( ! (cfgPath = [[ConfigurationManager defaultManager] getConfigurationToUse: cfgPath orAlt: altPath]) ) {
        return;
    }
    
    authenticationFailed = NO;
    
	NSString* path = [[NSBundle mainBundle] pathForResource: @"openvpnstart" 
													 ofType: nil];
    [managementSocket close];
    [managementSocket setDelegate: nil];
    [managementSocket release];
    managementSocket = nil;
    
    [self setPort:[self getFreePort]];
	NSTask* task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath: path]; 
		
	NSString *portString = [NSString stringWithFormat:@"%d",portNumber];
	NSArray *arguments;
		
	NSString *useDNS = @"0";
	if(useDNSStatus(self)) {
        NSString * useDownRootPluginKey = [[self displayName] stringByAppendingString: @"-useDownRootPlugin"];
        if (  [gTbDefaults boolForKey: useDownRootPluginKey]  ) {
            useDNS = @"2";
        } else {
            useDNS = @"1";
        }
        usedSetNameserver = TRUE;
	} else {
        usedSetNameserver = FALSE;
    }

    NSString *altCfgLoc = @"0";
    if ( [cfgPath isEqualToString:altPath] ) {
        altCfgLoc = @"1";
    } else if (  [configPath hasPrefix: gDeployPath]  ) {
        altCfgLoc = @"2";
    } else if (  [configPath hasPrefix: gSharedPath]  ) {
        altCfgLoc = @"3";
    }
    
    NSString * noMonitorKey = [[self displayName] stringByAppendingString: @"-notMonitoringConnection"];
    NSString * noMonitor = @"0";
    if (  [useDNS isEqualToString: @"0"] || [gTbDefaults boolForKey: noMonitorKey]  ) {
        noMonitor = @"1";
    }
    
    // for OpenVPN v. 2.1_rc9 or higher, clear skipScrSec so we use "--script-security 2"
    
    NSDictionary * vers = getOpenVPNVersion();
    int intMajor =  [[vers objectForKey:@"major"]  intValue];
    int intMinor =  [[vers objectForKey:@"minor"]  intValue];
    int intSuffix = [[vers objectForKey:@"suffix"] intValue];
    
	NSString *skipScrSec =@"1";
    if ( intMajor == 2 ) {
        if ( intMinor == 1 ) {
            if (  [[vers objectForKey:@"preSuffix"] isEqualToString:@"_rc"] ) {
                if ( intSuffix > 8 ) {
                    skipScrSec = @"0";
                }
            } else {
                skipScrSec = @"0";
            }
        } else if ( intMinor > 1 ) {
            skipScrSec = @"0";
        }
    } else if ( intMajor > 2 ) {
        skipScrSec = @"0";
    }
    
    NSPipe * errPipe = [[NSPipe alloc] init];
    [task setStandardError: errPipe];
    NSPipe * stdPipe = [[NSPipe alloc] init];
    [task setStandardOutput: stdPipe];
    
    arguments = [NSArray arrayWithObjects:@"start", lastPartOfPath(configPath), portString, useDNS, skipScrSec, altCfgLoc, noMonitor, nil];
    
    NSString * logText = [NSString stringWithFormat:@"*Tunnelblick: Attempting connection with %@%@; Set nameserver = %@%@",
                          [self displayName],
                          (  [altCfgLoc isEqualToString:@"1"]
                           ? @" using shadow copy"
                           : (  [altCfgLoc isEqualToString:@"2"]
                              ? @" from Deploy"
                              : @""  )  ),
                          useDNS,
                          (  [noMonitor isEqualToString:@"1"]
                           ? @"; not monitoring connection"
                           : @"; monitoring connection" )
                          ];
    [self addToLog: logText atDate: nil];

    NSMutableArray * escapedArguments = [NSMutableArray arrayWithCapacity:40];
    int i;
    for (i=0; i<[arguments count]; i++) {
        [escapedArguments addObject: [[[arguments objectAtIndex: i] componentsSeparatedByString: @" "] componentsJoinedByString: @"\\ "]];
    }
    
    [self addToLog: [NSString stringWithFormat: @"*Tunnelblick: %@ %@",
                     [[path componentsSeparatedByString: @" "] componentsJoinedByString: @"\\ "],
                     [escapedArguments componentsJoinedByString: @" "]]
            atDate: nil];
    
	[task setArguments:arguments];
	[task setCurrentDirectoryPath: firstPartOfPath(configPath)];
	[task launch];
	[task waitUntilExit];
    
    // Standard output has command line that openvpnstart used to start OpenVPN; copy it to the log
    NSFileHandle * file = [stdPipe fileHandleForReading];
    NSData * data = [file readDataToEndOfFile];
    [file closeFile];
    [stdPipe release];
    NSString * openvpnstartOutput = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
    openvpnstartOutput = [openvpnstartOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [self addToLog: [NSString stringWithFormat:@"*Tunnelblick: %@", openvpnstartOutput] atDate: nil];

    int status = [task terminationStatus];
    if (  status != 0  ) {
        if (  status == 240  ) {
            openvpnstartOutput = @"Internal Tunnelblick error: openvpnstart syntax error";
        } else {
            file = [errPipe fileHandleForReading];
            data = [file readDataToEndOfFile];
            [file closeFile];
            openvpnstartOutput = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
            openvpnstartOutput = [openvpnstartOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        
        [self addToLog: [NSString stringWithFormat:NSLocalizedString(@"*Tunnelblick: openvpnstart status #%d: %@", @"OpenVPN Log message"), status, openvpnstartOutput]
                atDate: nil];
    }
    
    [errPipe release];
    
	[self setState: @"SLEEP"];
    
	//sleep(1);
	[self connectToManagementSocket];
	// Wait some time for the demon to start up before connecting to the management interface:
	//[NSTimer scheduledTimerWithTimeInterval: 3.0 target: self selector: @selector(connectToManagementSocket) userInfo: nil repeats: NO];
}


- (NSDate *)connectedSinceDate {
    return [[connectedSinceDate retain] autorelease];
}

- (void)setConnectedSinceDate:(NSDate *)value {
    if (connectedSinceDate != value) {
        [connectedSinceDate release];
        connectedSinceDate = [value copy];
    }
}

- (BOOL) usedSetNameserver {
    return usedSetNameserver;
}


- (IBAction) toggle: (id) sender
{
	if (![self isDisconnected]) {
		[self disconnect: sender];
	} else {
		[self connect: sender];
	}
}


- (void) connectToManagementSocket
{
    [self setManagementSocket: [NetSocket netsocketConnectedToHost: @"127.0.0.1" port: portNumber]];   
}

- (IBAction) disconnect: (id)sender 
{
    pid_t savedPid = 0;
	if(pid > 0) {
        savedPid = pid;
		[self killProcess];
	} else {
		if([managementSocket isConnected]) {
			[managementSocket writeString: @"signal SIGTERM\r\n" encoding: NSASCIIStringEncoding];
		}
        sleep(5);       // Wait five seconds for OpenVPN to disappear
	}
    
    [self emptyPipe];
    
    [[NSApp delegate] removeConnection:self];
    [self setState:@"EXITING"];
    
    if (  savedPid != 0  ) {
        [NSApp waitUntilNoProcessWithID: savedPid];     // Wait until OpenVPN process is completely gone
    }
    
    if (  ! [managementSocket peekData]  ) {
        [managementSocket close]; [managementSocket setDelegate: nil];
        [managementSocket release]; managementSocket = nil;
    }
}



// Kills the OpenVPN process associated with this connection, if any
-(void)killProcess 
{
	NSParameterAssert(pid > 0);
	NSString* path = [[NSBundle mainBundle] pathForResource: @"openvpnstart" 
													 ofType: nil];
	NSTask* task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath: path]; 
	NSString *pidString = [NSString stringWithFormat:@"%d", pid];
	NSArray *arguments = [NSArray arrayWithObjects:@"kill", pidString, nil];
	[task setArguments:arguments];
	[task setCurrentDirectoryPath: firstPartOfPath(configPath)];
    pid = 0;
	[task launch];
	[task waitUntilExit];
    
}

- (void) netsocketConnected: (NetSocket*) socket
{
    
    NSParameterAssert(socket == managementSocket);
    
    if (NSDebugEnabled) NSLog(@"Tunnelblick connected to management interface on port %d.", [managementSocket remotePort]);
    
    NS_DURING {
		[managementSocket writeString: @"pid\r\n" encoding: NSASCIIStringEncoding];
        [managementSocket writeString: @"state on\r\n" encoding: NSASCIIStringEncoding];    
        [managementSocket writeString: @"log on all\r\n" encoding: NSASCIIStringEncoding];
        [managementSocket writeString: @"hold release\r\n" encoding: NSASCIIStringEncoding];
    } NS_HANDLER {
        NSLog(@"Exception caught while writing to socket: %@\n", localException);
    }
    NS_ENDHANDLER
    
}

-(void)setPIDFromLine:(NSString *)line 
{
	if([line rangeOfString: @"SUCCESS: pid="].length) {
		@try {
			NSArray* parameters = [line componentsSeparatedByString: @"="];
			NSString *pidString = [parameters lastObject];
			pid = atoi([pidString UTF8String]);			
		} @catch(NSException *exception) {
			pid = 0;
		}
	}
}


- (void) processLine: (NSString*) line
{
    if (NSDebugEnabled) NSLog(@">openvpn: '%@'", line);
    
    if (![line hasPrefix: @">"]) {
        // Output in response to command to OpenVPN. Could be the PID command, or additional log output from LOG ON ALL
		[self setPIDFromLine:line];
		@try {
			NSArray* parameters = [line componentsSeparatedByString: @","];
            NSCalendarDate* date = nil;
            if ( [[parameters objectAtIndex: 0] intValue] != 0) {
                date = [NSCalendarDate dateWithTimeIntervalSince1970: [[parameters objectAtIndex: 0] intValue]];
            }
            NSString* logLine = [parameters lastObject];
			[self addToLog:logLine atDate:date];
		} @catch (NSException *exception) {
			
		}
		return;
	}
    // "Real time" output from OpenVPN.
    NSRange separatorRange = [line rangeOfString: @":"];
    if (separatorRange.length) {
        NSRange commandRange = NSMakeRange(1, separatorRange.location-1);
        NSString* command = [line substringWithRange: commandRange];
        NSString* parameterString = [line substringFromIndex: separatorRange.location+1];
        //NSLog(@"Found command '%@' with parameters: %@", command, parameterString);
        
        if ([command isEqualToString: @"STATE"]) {
            NSArray* parameters = [parameterString componentsSeparatedByString: @","];
            NSString* state = [parameters objectAtIndex: 1];
            if (NSDebugEnabled) NSLog(@"State is '%@'", state);
            [self setState: state];

            if([state isEqualToString: @"RECONNECTING"]) {
                [managementSocket writeString: @"hold release\r\n" encoding: NSASCIIStringEncoding];
            
            } else if ([state isEqualToString: @"CONNECTED"]) {
                NSDate *now = [[NSDate alloc] init];
                [[NSApp delegate] addConnection:self];
                [self setConnectedSinceDate:now];
                [now release];
            
            } else if ([state isEqualToString: @"EXITING"]) {
                [managementSocket close]; [managementSocket setDelegate: nil];
                [managementSocket release]; managementSocket = nil;
            }
            
        } else if ([command isEqualToString: @"PASSWORD"]) {
            if ([line rangeOfString: @"Failed"].length) {
                if (NSDebugEnabled) NSLog(@"Passphrase or user/auth verification failed");
                authenticationFailed = YES;
            } else {
                // Password request from server. If it comes immediately after a failure, inform user and ask what to do
                if (  authenticationFailed  ) {
                    authenticationFailed = NO;
                    id buttonWithDifferentCredentials = nil;
                    if (  [myAuthAgent authMode]  ) {               // Handle "auto-login" --  we were never asked for credentials, so authMode was never set
                        if ([myAuthAgent keychainHasCredentials]) { //                         so credentials in Keychain (if any) were never used, so we needn't delete them to rery
                            buttonWithDifferentCredentials = NSLocalizedString(@"Try again with different credentials", @"Button");
                        }
                    }
                    int alertVal = TBRunAlertPanel([NSString stringWithFormat:@"%@: %@", [self displayName], NSLocalizedString(@"Authentication failed", @"Window title")],
                                                   NSLocalizedString(@"The credentials (passphrase or username/password) were not accepted by the remote VPN server.", @"Window text"),
                                                   NSLocalizedString(@"Try again", @"Button"),  // Default
                                                   buttonWithDifferentCredentials,              // Alternate
                                                   NSLocalizedString(@"Cancel", @"Button"));    // Other
                    if (alertVal == NSAlertAlternateReturn) {
                        [myAuthAgent deleteCredentialsFromKeychain];
                    }
                    if (  (alertVal != NSAlertDefaultReturn) && (alertVal != NSAlertAlternateReturn)  ) {	// If cancel or error then disconnect
                        [self disconnect:nil];
                        return;
                    }
                }

                // Find out whether the server wants a private key or user/auth:
                NSRange pwrange_need = [parameterString rangeOfString: @"Need \'"];
                NSRange pwrange_password = [parameterString rangeOfString: @"\' password"];
                if (pwrange_need.length && pwrange_password.length) {
                    if (NSDebugEnabled) NSLog(@"Server wants user private key.");
                    [myAuthAgent setAuthMode:@"privateKey"];
                    [myAuthAgent performAuthentication];
                    NSString *myPassphrase = [myAuthAgent passphrase];
					NSRange tokenNameRange = NSMakeRange(pwrange_need.length, pwrange_password.location - 6 );
					NSString* tokenName = [parameterString substringWithRange: tokenNameRange];
					if (NSDebugEnabled) NSLog(@"tokenName is  '%@'", tokenName);
                    if(myPassphrase){
                        [managementSocket writeString: [NSString stringWithFormat: @"password \"%@\" \"%@\"\r\n", tokenName, escaped(myPassphrase)] encoding:NSISOLatin1StringEncoding]; 
                    } else {
                        [self disconnect:self];
                    }

                } else if ([line rangeOfString: @"Auth"].length) {
                    if (NSDebugEnabled) NSLog(@"Server wants user auth/pass.");
                    [myAuthAgent setAuthMode:@"password"];
                    [myAuthAgent performAuthentication];
                    NSString *myPassword = [myAuthAgent password];
                    NSString *myUsername = [myAuthAgent username];
                    if(myUsername && myPassword){
                        [managementSocket writeString:[NSString stringWithFormat:@"username \"Auth\" \"%@\"\r\n", escaped(myUsername)] encoding:NSISOLatin1StringEncoding];
                        [managementSocket writeString:[NSString stringWithFormat:@"password \"Auth\" \"%@\"\r\n", escaped(myPassword)] encoding:NSISOLatin1StringEncoding];
                    } else {
                        [self disconnect:self];
                    }
                
                } else {
                    NSLog(@"Unrecognized PASSWORD command from OpenVPN management interface has been ignored:\n%@", line);
                }
            }

        } else if ([command isEqualToString:@"LOG"]) {
            NSArray* parameters = [parameterString componentsSeparatedByString: @","];
            NSCalendarDate* date = nil;
            if ( [[parameters objectAtIndex: 0] intValue] != 0) {
                date = [NSCalendarDate dateWithTimeIntervalSince1970: [[parameters objectAtIndex: 0] intValue]];
            }
            NSString* logLine = [parameters lastObject];
            [self addToLog:logLine atDate:date];
            
        } else if ([command isEqualToString:@"NEED-OK"]) {
            // NEED-OK: MSG:Please insert TOKEN
            if ([line rangeOfString: @"Need 'token-insertion-request' confirmation"].length) {
                if (NSDebugEnabled) NSLog(@"Server wants token.");
                NSRange tokenNameRange = [parameterString rangeOfString: @"MSG:"];
                NSString* tokenName = [parameterString substringFromIndex: tokenNameRange.location+4];
                int needButtonReturn = TBRunAlertPanel([NSString stringWithFormat:@"%@: %@",
                                                        [self displayName],
                                                        NSLocalizedString(@"Please insert token", @"Window title")],
                                                       [NSString stringWithFormat:NSLocalizedString(@"Please insert token \"%@\", then click \"OK\"", @"Window text"), tokenName],
                                                       nil,
                                                       NSLocalizedString(@"Cancel", @"Button"),
                                                       nil);
                if (needButtonReturn == NSAlertDefaultReturn) {
                    if (NSDebugEnabled) NSLog(@"Write need ok.");
                    [managementSocket writeString:[NSString stringWithFormat:@"needok 'token-insertion-request' ok\r\n"] encoding:NSASCIIStringEncoding];
                } else {
                    if (NSDebugEnabled) NSLog(@"Write need cancel.");
                    [managementSocket writeString:[NSString stringWithFormat:@"needok 'token-insertion-request' cancel\r\n"] encoding:NSASCIIStringEncoding];
                }
            }
        }
    }
}


// Adds a message to the OpenVPN Log with a specified date/time. If date/time is nil, current date/time is used
-(void)addToLog:(NSString *)text atDate:(NSCalendarDate *)date {
    if ( ! date ) {
        date = [NSCalendarDate date];
    }
    NSString *dateText = [NSString stringWithFormat:@"%@ %@\n",[date descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S"],text];
    [[self logStorage] appendAttributedString: [[[NSAttributedString alloc] initWithString: dateText] autorelease]];
}

- (void) netsocket: (NetSocket*) socket dataAvailable: (unsigned) inAmount
{
    NSParameterAssert(socket == managementSocket);
    NSString* line;
    
    while (line = [socket readLine]) {
        // Can we get blocked here?
        //NSLog(@">>> %@", line);
        if ([line length]) {
            [self performSelectorOnMainThread: @selector(processLine:) 
                                   withObject: line 
                                waitUntilDone: NO];
        }
    }
}

- (void) netsocketDisconnected: (NetSocket*) inSocket
{
    if (inSocket==managementSocket) {
        [self setManagementSocket: nil];
    }
    if (NSDebugEnabled) NSLog(@"Socket disconnected");
	//[self performSelectorOnMainThread:@selector(disconnect:) withObject:nil waitUntilDone:NO];
    [self disconnect:self];
}

- (NSString*) state
{
    return lastState;
}

- (void) setDelegate: (id) newDelegate
{
    delegate = newDelegate;
}

-(BOOL) isConnected
{
    return [[self state] isEqualToString:@"CONNECTED"];
}
-(BOOL) isDisconnected 
{
    return [[self state] isEqualToString:@"EXITING"];
}

- (void) setState: (NSString*) newState
	// Be sure to call this in main thread only
{
    [newState retain];
    [lastState release];
    lastState = newState;
    [[NSApp delegate] performSelectorOnMainThread:@selector(setState:) withObject:newState waitUntilDone:NO];
//    [self performSelectorOnMainThread:@selector(updateUI) withObject:nil waitUntilDone:NO];
    
    [delegate performSelector: @selector(connectionStateDidChange:) withObject: self];    
}

- (NSTextStorage*) logStorage 
/*" Returns all collected log messages for the reciever. "*/
{
    if (!logStorage) {
        logStorage = [[NSTextStorage alloc] init];
    }
    return logStorage;
}

- (unsigned int) getFreePort
{
	unsigned int resultPort = 1336; // start port	
	int fd = socket(AF_INET, SOCK_STREAM, 0);
	int result = 0;
	
	do {		
		struct sockaddr_in address;
		int len = sizeof(struct sockaddr_in);
		resultPort++;
		
		address.sin_len = len;
		address.sin_family = AF_INET;
		address.sin_port = htons(resultPort);
		address.sin_addr.s_addr = htonl(0x7f000001); // 127.0.0.1, localhost
		
		memset(address.sin_zero,0,sizeof(address.sin_zero));
		
		result = bind(fd, (struct sockaddr *)&address,sizeof(address));
		
	} while (result!=0);
	
	close(fd);
	
	return resultPort;
}

- (BOOL)validateMenuItem:(NSMenuItem *)anItem 
{
    SEL action = [anItem action];
	
    if (action == @selector(toggle:)) 
    {
        VPNConnection *connection = [anItem target];
        
        // setting menu item's state:
        int state = NSMixedState;
        
        if ([connection isConnected]) 
        {
            state = NSOnState;
        } 
        else if ([connection isDisconnected]) 
        {
            state = NSOffState;
        }
        
        [anItem setState:state];
        
        // setting menu command title depending on current status:
        NSString *commandString; 
        if ([[connection state] isEqualToString:@"CONNECTED"]) commandString = NSLocalizedString(@"Disconnect", @"Button");
        else commandString = NSLocalizedString(@"Connect", @"Button");
        
        NSString * locationMessage = @"";
        if (  [gConfigDirs count] > 1  ) {
            if (  [[connection configPath] hasPrefix: gDeployPath]  ) {
                locationMessage =  NSLocalizedString(@" (Deployed)", @"Window title");
            } else if (  [[connection configPath] hasPrefix: gSharedPath]  ) {
                locationMessage =  NSLocalizedString(@" (Shared)", @"Window title");
            }
        }
        NSString *itemTitle = [NSString stringWithFormat:@"%@ %@%@", commandString, [connection displayName], locationMessage];
        [anItem setTitle:itemTitle];
        [anItem setToolTip: [connection configPath]];
	}
	return YES;
}

-(void) destroyPipe
{
    [self emptyPipe];
    [myPipe destroyPipe];
}

-(void) emptyPipe
{
    if (  [myPipeBuffer length] != 0  ) {
        [self appendDataToLog: [@"\003\n" dataUsingEncoding: NSUTF8StringEncoding]];
    }
}
         
/* Invoked when data is available from myPipe, which accepts data and sends it to the OpenVPN Log via this routine
 
 The pipe is created in /tmp by the "initWithConfig:inDirectory: method (above)
 The name of the pipe is formed in part by replacing slash characters in the configuration file's path with dashes:
 If the configuration file's path is
                      "/Users/joe/Application Support/Tunnelblick/Configurations/test.conf"
 then the pipe is named
      "/tmp/tunnelblick-Users-joe-Application Support-Tunnelblick-Configurations-test.conf.logpipe"
 
Data sent to the pipe should a message consisting of
       ETX LF timestamp SP star SP program SP message ETX LF

 Where ETX       is the ASCII ETX character (use "\003" in the "echo -e" command)
       LF        is the ASCII LF character ("\n")
       timestamp is in the form "YYYY-MM-DD HH:MM:SS", as generated by bash shell "$(date '+%Y-%m-%d %T')"
       SP        is a single space character
       star      is the asterisk character "*"
       program   is the name of the program generating the message
       message   is the message that is to be displayed in the log. It may include any sequence of characters except ETX LF

 This format will make piped log output consistent with the way that Tunnelblick displays other messages in the log

 The first ETX LF forces any partial message that wasn't terminated to be output. If there is no partial message, then
 nothing will be output and the first ETX LF are ignored.
 
 Example:
 echo -e "\003\n$(date '+%Y-%m-%d %T') * XYZ-Script This-is-the-actual-message.\003"
 will append a line like the following to the log. Note that the echo command appends a LF after the second ETX.

       2010-01-15 10:05:02 * XYZ-Script This is the actual message

 Also, see leasewatch for shell code that outputs multi-line messages to the log window when the network configuration changes.
*/

-(void) appendDataToLog: (NSData *) data
{
    if (  [data length] != 0  ) {
        // Append the data to the buffer
        NSString * s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [myPipeBuffer appendString: s];
        [s release];
    }
    
    NSString * endOfMsgMarker = @"\003\n";
    
    NSRange eomRange = [myPipeBuffer rangeOfString: endOfMsgMarker];
    if (  eomRange.location != NSNotFound  ) {
        
        while (  [myPipeBuffer length] != 0  ) {
            
            // Get message up to, but not including, the ETX-LF
            NSMutableString * msg = [[NSMutableString alloc] initWithString: [myPipeBuffer substringWithRange: NSMakeRange(0, eomRange.location)]];
            
            // Remove LFs at the end of the message (for example, if have: msg  LF  ETX  LF, removes the first LF
            // We do this to make indentation easy, and we add a final LF to the end of the message when it goes in the log
            while (  [msg hasSuffix: @"\n"]  ) {
                [msg deleteCharactersInRange:NSMakeRange([msg length]-1, 1)];
            }
            
            if (  [msg length] != 0  ) {
                // Indent all lines after the first. Since msg doesn't have the terminating \n, we can just replace all \n characters
                [msg replaceOccurrencesOfString: @"\n"
                                     withString: @"\n                                          " options: 0 range: NSMakeRange(0, [msg length])];
                
                [msg appendString: @"\n"];
                
                // Add the message to the log
                NSAttributedString * msgAS = [[NSAttributedString alloc] initWithString: msg];
                [[self logStorage] appendAttributedString: msgAS];
                [msgAS release];
            }
            
            [msg release];
            
            // Remove the entry from the buffer
            [myPipeBuffer deleteCharactersInRange: NSMakeRange(0, eomRange.location + [endOfMsgMarker length])  ];
            
            eomRange = [myPipeBuffer rangeOfString: endOfMsgMarker];
            if (  eomRange.location == NSNotFound  ) {
                break;
            }
        }
    }
}

@end
