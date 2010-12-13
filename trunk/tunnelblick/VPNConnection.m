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

#import <CoreServices/CoreServices.h>
#import <Foundation/NSDebug.h>
#import <pthread.h>
#import <Security/AuthSession.h>
#import <signal.h>
#import "defines.h"
#import "VPNConnection.h"
#import "KeyChain.h"
#import "NetSocket.h"
#import "NetSocket+Text.h"
#import "NSApplication+LoginItem.h"
#import "helper.h"
#import "MenuController.h"
#import "TBUserDefaults.h"
#import "ConfigurationManager.h"
#import "NSFileManager+TB.h"

extern NSMutableArray       * gConfigDirs;
extern NSString             * gDeployPath;
extern NSString             * gSharedPath;
extern NSFileManager        * gFileMgr;
extern TBUserDefaults       * gTbDefaults;
extern NSDictionary         * gOpenVPNVersionDict;
extern SecuritySessionId      gSecuritySessionId;
extern unsigned int           gHookupTimeout;

extern NSString * firstPartOfPath(NSString * thePath);

extern NSString * lastPartOfPath(NSString * thePath);

@interface VPNConnection()          // PRIVATE METHODS

-(NSArray *)        argumentsForOpenvpnstartForNow: (BOOL)          forNow;

-(void)             connectToManagementSocket;

-(void)             flushDnsCache;

-(void)             forceKillWatchdogHandler;

-(void)             forceKillWatchdog;

-(unsigned int)     getFreePort;

-(void)             killProcess;                                                // Kills the OpenVPN process associated with this connection, if any

-(BOOL)             makePlistFileForAtPath:     (NSString *)        plistPath
                                 withLabel:     (NSString *)        daemonLabel;

-(void)             processLine:                (NSString *)        line;

-(void)             processState:               (NSString *)        newState
                           dated:               (NSString *)        dateTime;

-(void)             setBit:                     (unsigned int)      bit
                    inMask:                     (unsigned int *)    bitMaskPtr
    ifConnectionPreference:                     (NSString *)        keySuffix
                  inverted:                     (BOOL)              invert;

-(void)             setConnectedSinceDate:      (NSDate *)          value;

-(void)             setManagementSocket:        (NetSocket *)       socket;

-(void)             setPort:                    (unsigned int)      inPort;

-(void)             tellUserAboutDisconnectWait;

@end

@implementation VPNConnection

-(id) initWithConfigPath: (NSString *) inPath withDisplayName: (NSString *) inDisplayName
{	
    if (self = [super init]) {
        configPath = [inPath copy];
        displayName = [inDisplayName copy];
        portNumber = 0;
        managementSocket = nil;
		pid = 0;
		connectedSinceDate = [[NSDate alloc] init];
        logDisplay = [[LogDisplay alloc] initWithConfigurationPath: inPath];
        lastState = @"EXITING";
        requestedState = @"EXITING";
		myAuthAgent = [[AuthAgent alloc] initWithConfigName:[self displayName]];
        tryingToHookup = FALSE;
        isHookedup = FALSE;
        tunOrTap = nil;
        areDisconnecting = FALSE;
        connectedWithTap = FALSE;
        connectedWithTun = FALSE;
        
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

-(void) tryToHookupToPort: (int) inPortNumber
     withOpenvpnstartArgs: (NSString *) inStartArgs
{
    if (  portNumber != 0  ) {
        NSLog(@"Ignoring attempt to 'tryToHookupToPort' for '%@' -- already using port number %d", [self description], portNumber);
        return;
    }
    
    if (  managementSocket  ) {
        NSLog(@"Ignoring attempt to 'tryToHookupToPort' for '%@' -- already using managementSocket", [self description]);
        return;
    }

    [logDisplay startMonitoringLogFiles];   // Start monitoring the log files, and display any existing contents

    // Keep track of the number of tun and tap kexts that openvpnstart loaded
    NSArray * openvpnstartArgs = [inStartArgs componentsSeparatedByString: @"_"];
    unsigned bitMask = [[openvpnstartArgs lastObject] intValue];
    if (  (bitMask & OUR_TAP_KEXT) == OUR_TAP_KEXT ) {
        [[NSApp delegate] incrementTapCount];
        connectedWithTap = TRUE;
    } else {
        connectedWithTap = FALSE;
    }
    
    if (  (bitMask & OUR_TUN_KEXT) == OUR_TUN_KEXT ) {
        [[NSApp delegate] incrementTunCount];
        connectedWithTun = TRUE;
    } else {
        connectedWithTun = FALSE;
    }

    [self setPort: inPortNumber];
    tryingToHookup = TRUE;
    [self connectToManagementSocket];
}

-(void) stopTryingToHookup
{
    if (  tryingToHookup  ) {
        tryingToHookup = FALSE;

        if ( ! isHookedup  ) {
            [self setPort: 0];
            
            NSLog(@"Stopped trying to establish communications with an existing OpenVPN process for '%@' after %d seconds", [self displayName], gHookupTimeout);
            NSString * msg = [NSString stringWithFormat:
                              NSLocalizedString(@"Tunnelblick was unable to establish communications with an existing OpenVPN process for '%@' within %d seconds. The attempt to establish communications has been abandoned.", @"Window text"),
                              [self displayName],
                              gHookupTimeout];
            NSString * prefKey = [NSString stringWithFormat: @"%@-skipWarningUnableToToEstablishOpenVPNLink", [self displayName]];
            
            TBRunAlertPanelExtended(NSLocalizedString(@"Unable to Establish Communication", @"Window text"),
                                    msg,
                                    nil, nil, nil,
                                    prefKey,
                                    NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
                                    nil);
        }
    }
}

// User wants to connect, or not connect, the configuration when the system starts.
// Returns TRUE if can and will connect, FALSE otherwise
//
// Needs and asks for administrator username/password to make a change if a change is necessary and authRef is nil.
// (authRef is non-nil only when Tunnelblick is in the process of launching, and only when it was used for something else.
//
// A change is necesary if changing connect/not connect status, or if preference changes would change
// the .plist file used to connect when the system starts

-(BOOL) checkConnectOnSystemStart: (BOOL) startIt withAuth: (AuthorizationRef) inAuthRef
{
    NSString * daemonLabel = [NSString stringWithFormat: @"net.tunnelblick.startup.%@", [self displayName]];
    
    NSString * libPath = [NSString stringWithFormat: @"/Library/LaunchDaemons/%@.plist", daemonLabel];

    NSString * plistPath = [NSString stringWithFormat: @"/tmp/tunnelblick-atsystemstart.%d.plist", (int) gSecuritySessionId];
    
    if (  ! startIt  ) {
        if (  ! [gFileMgr fileExistsAtPath: libPath]  ) {
            return NO; // Don't want to connect at system startup and no .plist in /Library/LaunchDaemons, so return that we ARE NOT connecting at system start
        }
        if (  ! [self makePlistFileForAtPath: plistPath withLabel: daemonLabel]  ) {
            // Don't want to connect at system startup, but .plist exists in /Library/LaunchDaemons
            // User cancelled when asked about openvpn-down-root.so, so return that we ARE connecting at system start
            return YES;
        }
    } else {
        if (  ! (   [configPath hasPrefix: gDeployPath]
                 || [configPath hasPrefix: gSharedPath]   )  ) {
            NSLog(@"Tunnelblick will NOT connect '%@' when the computer starts because it is a private configuration", [self displayName]);
            return NO;
        }
        
        if (  ! [self makePlistFileForAtPath: plistPath withLabel: daemonLabel]  ) {
            if (  [gFileMgr fileExistsAtPath: libPath]  ) {
                // Want to connect at system start and a .plist exists, but user cancelled, so fall through to remove the .plist
                startIt = FALSE;
                // (Fall through to remove .plist)
            } else {
                // Want to connect at system start but no .plist exists and user cancelled, so return that we ARE NOT connecting at system start
                return NO;
            }

        } else if (  [gFileMgr contentsEqualAtPath: plistPath andPath: libPath]  ) {
            [gFileMgr tbRemoveFileAtPath:plistPath handler: nil];
            return YES; // .plist contents are the same, so we needn't do anything
        }
    }
    
    // Use executeAuthorized to run "atsystemstart" to replace or remove the .plist in /Library/LaunchDaemons
	NSBundle *thisBundle = [NSBundle mainBundle];
	NSString *launchPath = [thisBundle pathForResource:@"atsystemstart" ofType:nil];
    
    NSString * arg = ( startIt ? @"1" : @"0" );
    NSArray *  arguments = [NSArray arrayWithObject: arg];
    
    BOOL freeAuthRef = NO;
    if (  inAuthRef == nil  ) {
        // Get an AuthorizationRef
        NSString * msg;
        if (  startIt  ) {
            msg = [NSString stringWithFormat:
                   NSLocalizedString(@" Tunnelblick needs computer administrator access so it can automatically connect '%@' when the computer starts.", @"Window text"),
                   [self displayName]];
        } else {
            msg = [NSString stringWithFormat:
                   NSLocalizedString(@" Tunnelblick needs computer administrator access so it can stop automatically connecting '%@' when the computer starts.", @"Window text"),
                   [self displayName]];
        }
        
        inAuthRef= [NSApplication getAuthorizationRef: msg];
        freeAuthRef = YES;
    }
    
    if (  inAuthRef == nil  ) {
        if (  startIt  ) {
            NSLog(@"Connect '%@' when computer starts cancelled by user", [self displayName]);
            [gFileMgr tbRemoveFileAtPath:plistPath handler: nil];
            return NO;
        } else {
            NSLog(@"NOT connect '%@' when computer starts cancelled by user", [self displayName]);
            [gFileMgr tbRemoveFileAtPath:plistPath handler: nil];
            return YES;
        }
    }
    
    // The return code from executeAuthorized is NOT the code returned by the executed program. A 0 code
    // does not mean that the program succeeded. So we make sure that what we wanted the program to do was
    // actually done.
    //
    // There also is a problem doing that test -- without the sleep(1), the test often says that the program
    // did not succeed, even though it did. Probably an OS X cache problem of some sort.
    // The multiple tries are an attempt to make sure the program tries, even if the sleep(1) didn't clear up
    // whatever problem caused the bogus results -- for example, under heavy load perhaps sleep(1) isn't enough.
    
    NSString * flagPath = [NSString stringWithFormat: @"/tmp/tunnelblick-atsystemstart.%d.done", (int) gSecuritySessionId];

    int i;
    OSStatus status;
    BOOL didIt = FALSE;
    for (i=0; i < 5; i++) {
        if (  [gFileMgr fileExistsAtPath: flagPath]  ) {
            if (  ! [gFileMgr tbRemoveFileAtPath:flagPath handler: nil]  ) {
                NSLog(@"Unable to remove temporary file %@", flagPath);
            }
        }
            
        status = [NSApplication executeAuthorized: launchPath withArguments: arguments withAuthorizationRef: inAuthRef];
        if (  status != 0  ) {
            NSLog(@"Returned status of %d indicates failure of execution of %@: %@", status, launchPath, arguments);
        }
        
        int j;
        for (j=0; j < 6; j++) {
            if (  [gFileMgr contentsAtPath: flagPath]  ) {
                break;
            }
            sleep(1);
        }

        if (  ! [gFileMgr contentsAtPath: flagPath]  ) {
            NSLog(@"Timeout (5 seconds) waiting for atsystemstart execution to finish");
        }
        
        if (  startIt  ) {
            if (  [gFileMgr contentsEqualAtPath: plistPath andPath: libPath]  ) {
                didIt = TRUE;
                break;
            }
        } else {
            if (  ! [gFileMgr fileExistsAtPath: libPath]  ) {
                didIt = TRUE;
                break;
            }
        }
        sleep(1);
    }
    
    if (  freeAuthRef  ) {
        AuthorizationFree(inAuthRef, kAuthorizationFlagDefaults);
    }
    
    if (  ! [gFileMgr tbRemoveFileAtPath:flagPath handler: nil]  ) {
        NSLog(@"Unable to remove temporary file %@", flagPath);
    }

    if (  ! [gFileMgr tbRemoveFileAtPath:plistPath handler: nil]  ) {
        NSLog(@"Unable to remove temporary file %@", plistPath);
    }
    
    if (  ! didIt  ) {
        if (  startIt  ) {
            NSLog(@"Set up to connect '%@' when computer starts failed; tried 5 times", [self displayName]);
            return NO;
        } else {
            NSLog(@"Set up to NOT connect '%@' when computer starts failed; tried 5 times", [self displayName]);
            return YES;
        }
        
    }

    if (  startIt  ) {
        NSLog(@"%@ will be connected using '%@' when the computer starts"    ,
              [self displayName],
              [[NSBundle mainBundle] pathForResource: @"openvpnstart" ofType: nil]);
    } else {
        NSLog(@"%@ will NOT be connected when the computer starts", [self displayName]);
    }

    return startIt;
}

// Returns YES on success, NO if user cancelled out of dialog 
-(BOOL) makePlistFileForAtPath: (NSString *) plistPath withLabel: (NSString *) daemonLabel
{
    // Don't use the "Program" key, because we want the first argument to be the path to the program,
    // so openvpnstart can know where it is, so it can find other Tunnelblick compenents.
    NSString * openvpnstartPath = [[NSBundle mainBundle] pathForResource: @"openvpnstart" ofType: nil];
    NSMutableArray  * arguments = [[[self argumentsForOpenvpnstartForNow: NO] mutableCopy] autorelease];
    if (  ! arguments  ) {
        return NO;
    }
    
    [arguments insertObject: openvpnstartPath atIndex: 0];
    
    NSString * daemonDescription = [NSString stringWithFormat: @"Processes Tunnelblick 'Connect when system starts' for VPN configuration '%@'",
                                    [self displayName]];
    
    NSDictionary * plistDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                daemonLabel,                    @"Label",
                                arguments,                      @"ProgramArguments",
                                [NSNumber numberWithBool: YES], @"onDemand",
                                [NSNumber numberWithBool: YES], @"RunAtLoad",
                                firstPartOfPath(configPath),    @"WorkingDirectory",
                                daemonDescription,              @"ServiceDescription",
                                nil];
    
    [gFileMgr tbRemoveFileAtPath:plistPath handler: nil];
    if (  ! [plistDict writeToFile: plistPath atomically: YES]  ) {
        NSLog(@"Unable to create %@", plistPath);
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick Problem", @"Window title"),
                        NSLocalizedString(@"Tunnelblick could not continue because it was unable to create a temporary file. Please examine the Console Log for details.", @"Window text"),
                        nil, nil, nil);
        [NSApp setAutoLaunchOnLogin: NO];
        [NSApp terminate: nil];
    }
    return YES;
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

-(NSString *) requestedState
{
    return requestedState;
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
    [self disconnectAndWait: [NSNumber numberWithBool: NO] userKnows: NO];
    [logDisplay release];
    [managementSocket close];
    [managementSocket setDelegate: nil];
    [managementSocket release]; 
    [lastState release];
    [tunOrTap release];
    [configPath release];
    [displayName release];
    [connectedSinceDate release];
    [myAuthAgent release];
    [super dealloc];
}

-(void) invalidateConfigurationParse
{
    [tunOrTap release];
    tunOrTap = nil;
}

- (void) connect: (id) sender userKnows: (BOOL) userKnows
{
    NSString * oldRequestedState = requestedState;
    if (  userKnows  ) {
        requestedState = @"CONNECTED";
    }
    
    if (  ! [gTbDefaults boolForKey:@"skipWarningAboutSimultaneousConnections"]  ) {
        // Count the total number of connections and what their "Set nameserver" status was at the time of connection
        int numConnections = 1;
        int numConnectionsWithModifyNameserver = 0;
        if (  [self useDNSStatus] != 0  ) {
            numConnectionsWithModifyNameserver = 1;
        }
        VPNConnection * connection;
        NSEnumerator* e = [[[NSApp delegate] myVPNConnectionDictionary] objectEnumerator];
        while (connection = [e nextObject]) {
            if (  ! [[connection state] isEqualToString:@"EXITING"]  ) {
                numConnections++;
                if (  [connection usedModifyNameserver]  ) {
                    numConnectionsWithModifyNameserver++;
                }
            }
        }
        
        if (  numConnections != 1  ) {
            int button = TBRunAlertPanelExtended(NSLocalizedString(@"Do you wish to connect?", @"Window title"),
                                                 [NSString stringWithFormat:NSLocalizedString(@"Multiple simultaneous connections would be created (%d with 'Set nameserver', %d without 'Set nameserver').", @"Window text"), numConnectionsWithModifyNameserver, (numConnections-numConnectionsWithModifyNameserver) ],
                                                 NSLocalizedString(@"Connect", @"Button"),  // Default button
                                                 NSLocalizedString(@"Cancel", @"Button"),   // Alternate button
                                                 nil,
                                                 @"skipWarningAboutSimultaneousConnections",
                                                 NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
                                                 nil);
            if (  button == NSAlertAlternateReturn  ) {
                if (  userKnows  ) {
                    requestedState = oldRequestedState;
                }
                return;
            }
        }
    }
    
    authenticationFailed = NO;
    
    areDisconnecting = FALSE;
    
    [managementSocket close];
    [managementSocket setDelegate: nil];
    [managementSocket release];
    managementSocket = nil;
    
	NSArray *arguments = [self argumentsForOpenvpnstartForNow: YES];
    if (  arguments == nil  ) {
        if (  userKnows  ) {
            requestedState = oldRequestedState; // User cancelled
        }
        return;
    }
		
    // Process runOnConnect item
    NSString * path = [[NSApp delegate] customRunOnConnectPath];
    if (  path  ) {
        NSTask* task = [[[NSTask alloc] init] autorelease];
        [task setLaunchPath: path];
        [task setArguments: arguments];
        [task setCurrentDirectoryPath: [path stringByDeletingLastPathComponent]];
        [task launch];
        if (  [[[path stringByDeletingPathExtension] pathExtension] isEqualToString: @"wait"]) {
            [task waitUntilExit];
            int status = [task terminationStatus];
            if (  status != 0  ) {
                NSLog(@"Tunnelblick runOnConnect item %@ returned %d; '%@' connect cancelled", path, status, displayName);
                if (  userKnows  ) {
                    TBRunAlertPanel(NSLocalizedString(@"Warning!", @"Window title"),
                                    [NSString
                                     stringWithFormat: NSLocalizedString(@"The attempt to connect %@ has been cancelled: the runOnConnect script returned status: %d.", @"Window text"),
                                     [self displayName],
                                     status],
                                    nil, nil, nil);
                    requestedState = oldRequestedState;
                }
                return;
            }
        }
    }
    
    
	NSTask* task = [[[NSTask alloc] init] autorelease];
    
	path = [[NSBundle mainBundle] pathForResource: @"openvpnstart" ofType: nil];
	[task setLaunchPath: path]; 
		
    NSPipe * errPipe = [[NSPipe alloc] init];
    [task setStandardError: errPipe];
    NSPipe * stdPipe = [[NSPipe alloc] init];
    [task setStandardOutput: stdPipe];
    
    NSString * logText = [NSString stringWithFormat:@"*Tunnelblick: Attempting connection with %@%@; Set nameserver = %@%@",
                          [self displayName],
                          (  [[arguments objectAtIndex: 5] isEqualToString:@"1"]
                           ? @" using shadow copy"
                           : (  [[arguments objectAtIndex: 5] isEqualToString:@"2"]
                              ? @" from Deploy"
                              : @""  )  ),
                          [arguments objectAtIndex: 3],
                          (  [[arguments objectAtIndex: 6] isEqualToString:@"1"]
                           ? @"; not monitoring connection"
                           : @"; monitoring connection" )
                          ];
    [self addToLog: logText];

    NSMutableArray * escapedArguments = [NSMutableArray arrayWithCapacity:[arguments count]];
    int i;
    for (i=0; i<[arguments count]; i++) {
        [escapedArguments addObject: [[[arguments objectAtIndex: i] componentsSeparatedByString: @" "] componentsJoinedByString: @"\\ "]];
    }
    
    [self addToLog: [NSString stringWithFormat: @"*Tunnelblick: %@ %@",
                     [[path componentsSeparatedByString: @" "] componentsJoinedByString: @"\\ "],
                     [escapedArguments componentsJoinedByString: @" "]]];
    
    unsigned bitMask = [[arguments objectAtIndex: 7] intValue];
    if (  (bitMask & OUR_TAP_KEXT) == OUR_TAP_KEXT ) {
        [[NSApp delegate] incrementTapCount];
        connectedWithTap = TRUE;
    } else {
        connectedWithTap = FALSE;
    }
    
    if (  (bitMask & OUR_TUN_KEXT) == OUR_TUN_KEXT ) {
        [[NSApp delegate] incrementTunCount];
        connectedWithTun = TRUE;
    } else {
        connectedWithTun = FALSE;
    }
    
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
    if (  [openvpnstartOutput length] != 0  ) {
        [self addToLog: [NSString stringWithFormat:@"*Tunnelblick: %@", openvpnstartOutput]];
    }

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
        
        [self addToLog: [NSString stringWithFormat:NSLocalizedString(@"*Tunnelblick: openvpnstart status #%d: %@", @"OpenVPN Log message"), status, openvpnstartOutput]];
        [errPipe release];
        if (  userKnows  ) {
            TBRunAlertPanel(NSLocalizedString(@"Warning!", @"Window title"),
                            [NSString stringWithFormat:
                             NSLocalizedString(@"Tunnelblick was unable to start OpenVPN to connect %@. For details, see the OpenVPN log in the Details... window", @"Window text"),
                             [self displayName]],
                            nil, nil, nil);
            requestedState = oldRequestedState;
        }
    } else {
        file = [errPipe fileHandleForReading];
        data = [file readDataToEndOfFile];
        [file closeFile];
        openvpnstartOutput = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
        if (  openvpnstartOutput  ) {
            openvpnstartOutput = [openvpnstartOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (  [openvpnstartOutput length] != 0  ) {
                [self addToLog: [NSString stringWithFormat:NSLocalizedString(@"*Tunnelblick: openvpnstart message: %@", @"OpenVPN Log message"), openvpnstartOutput]];
            }
        }
        [logDisplay startMonitoringLogFiles];   // Start monitoring the log files, and display any existing contents
        [errPipe release];
        [self setState: @"SLEEP"];
        [self connectToManagementSocket];
    }
}

-(NSArray *) argumentsForOpenvpnstartForNow: (BOOL) forNow
{
    NSString *cfgPath = [self configPath];
    NSString *altPath = [NSString stringWithFormat:@"/Library/Application Support/Tunnelblick/Users/%@/%@",
                         NSUserName(), lastPartOfPath(configPath)];
    
    if ( ! (cfgPath = [[ConfigurationManager defaultManager] getConfigurationToUse: cfgPath orAlt: altPath]) ) {
        return nil;
    }
    
    BOOL useShadowCopy = [cfgPath isEqualToString: altPath];
    BOOL useDeploy     = [cfgPath hasPrefix: gDeployPath];
    BOOL useShared     = [cfgPath hasPrefix: gSharedPath];
    
    NSString *portString;
    if (  forNow  ) {
        [self setPort:[self getFreePort]];
        portString = [NSString stringWithFormat:@"%d", portNumber];
    } else {
        portString = @"0";
    }
    
    // Parse configuration file to catch "user" or "group" options and get tun/tap key
    if (  ! tunOrTap  ) {
        tunOrTap = [[[ConfigurationManager defaultManager] parseConfigurationPath: configPath forConnection: self] copy];
        // tunOrTap == nil means couldn't find 'tun' or 'tap', which is OK and we continue, but 'Cancel' means we cancel whatever we're doing
        if (  [tunOrTap isEqualToString: @"Cancel"]  ) {
            tunOrTap = nil;
            return nil;
        }
    }
    
    NSString *useDNSArg = @"0";
    unsigned useDNSStat = (unsigned) [self useDNSStatus];
	if(  useDNSStat == 0) {
        if (  forNow  ) {
            usedModifyNameserver = FALSE;
        }
	} else {
        NSString * useDownRootPluginKey = [[self displayName] stringByAppendingString: @"-useDownRootPlugin"];
        BOOL useDownRoot = [gTbDefaults boolForKey: useDownRootPluginKey];
        unsigned useDNSNum = (  (useDNSStat-1) << 2) + (useDownRoot ? 2 : 0) + 1;   // (script #) + downroot-flag + set-nameserver-flag
        useDNSArg = [NSString stringWithFormat: @"%u", useDNSNum];
        if (  forNow  ) {
            usedModifyNameserver = TRUE;
        }
    }
    
    // for OpenVPN v. 2.1_rc9 or higher, clear skipScrSec so we use "--script-security 2"
    int intMajor =  [[gOpenVPNVersionDict objectForKey:@"major"]  intValue];
    int intMinor =  [[gOpenVPNVersionDict objectForKey:@"minor"]  intValue];
    int intSuffix = [[gOpenVPNVersionDict objectForKey:@"suffix"] intValue];
    
	NSString *skipScrSec =@"1";
    if ( intMajor == 2 ) {
        if ( intMinor == 1 ) {
            if (  [[gOpenVPNVersionDict objectForKey:@"preSuffix"] isEqualToString:@"_rc"] ) {
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
    NSString *altCfgLoc = @"0";
    if ( useShadowCopy ) {
        altCfgLoc = @"1";
    } else if (  useDeploy  ) {
        altCfgLoc = @"2";
    } else if (  useShared  ) {
        altCfgLoc = @"3";
    }
    
    NSString * noMonitorKey = [[self displayName] stringByAppendingString: @"-notMonitoringConnection"];
    NSString * noMonitor = @"0";
    if (  [useDNSArg isEqualToString: @"0"] || [gTbDefaults boolForKey: noMonitorKey]  ) {
        noMonitor = @"1";
    }

    unsigned int bitMask = 0;
    NSString * noTapKextKey = [[self displayName] stringByAppendingString: @"-doNotLoadTapKext"];
    NSString * yesTapKextKey = [[self displayName] stringByAppendingString: @"-loadTapKext"];
    if (  ! [gTbDefaults boolForKey: noTapKextKey]  ) {
        if (   ( ! tunOrTap )
            || [tunOrTap isEqualToString: @"tap"]
            || [gTbDefaults boolForKey: yesTapKextKey]  ) {
            bitMask = bitMask | OUR_TAP_KEXT;
        }
    }
    
    NSString * noTunKextKey = [[self displayName] stringByAppendingString: @"-doNotLoadTunKext"];
    NSString * yesTunKextKey = [[self displayName] stringByAppendingString: @"-loadTunKext"];
    if (  ! [gTbDefaults boolForKey: noTunKextKey]  ) {
        if (   ( ! tunOrTap )
            || [tunOrTap isEqualToString: @"tun"]
            || [gTbDefaults boolForKey: yesTunKextKey]  ) {
            bitMask = bitMask | OUR_TUN_KEXT;
        }
    }
    
    [self setBit: RESTORE_ON_WINS_RESET  inMask: &bitMask ifConnectionPreference: @"-doNotRestoreOnWinsReset"   inverted: YES];
    [self setBit: RESTORE_ON_DNS_RESET   inMask: &bitMask ifConnectionPreference: @"-doNotRestoreOnDnsReset"    inverted: YES];
    
    NSString * bitMaskString = [NSString stringWithFormat: @"%d", bitMask];
    
    NSArray * args = [NSArray arrayWithObjects:
                      @"start", [[lastPartOfPath(cfgPath) copy] autorelease], portString, useDNSArg, skipScrSec, altCfgLoc, noMonitor, bitMaskString, nil];
    return args;
}

-(void) setBit: (unsigned int) bit inMask: (unsigned int *) bitMaskPtr ifConnectionPreference: (NSString *) keySuffix inverted: (BOOL) invert
{
    NSString * prefKey = [[self displayName] stringByAppendingString: keySuffix];
    if (  [gTbDefaults boolForKey: prefKey]  ) {
        if (  ! invert  ) {
            *bitMaskPtr = *bitMaskPtr | bit;
        }
    } else {
        if (  invert  ) {
            *bitMaskPtr = *bitMaskPtr | bit;
        }
    }
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

- (BOOL) usedModifyNameserver {
    return usedModifyNameserver;
}

-(BOOL) tryingToHookup
{
    return tryingToHookup;
}

-(BOOL) isHookedup
{
    return isHookedup;
}

-(pid_t) pid
{
    return pid;
}

- (IBAction) toggle: (id) sender
{
	if (![self isDisconnected]) {
		[self disconnectAndWait: [NSNumber numberWithBool: YES] userKnows: YES];
	} else {
		[self connect: sender userKnows: YES];
	}
}

- (void) connectToManagementSocket
{
    [self setManagementSocket: [NetSocket netsocketConnectedToHost: @"127.0.0.1" port: portNumber]];   
}

static pthread_mutex_t areDisconnectingMutex = PTHREAD_MUTEX_INITIALIZER;

// Start disconnecting by killing the OpenVPN process or signaling through the management interface
// Waits for up to 5 seconds for the disconnection to occur if "wait" is TRUE
- (void) disconnectAndWait: (NSNumber *) wait userKnows:(BOOL)userKnows
{
    if (  userKnows  ) {
        requestedState = @"EXITING";
    }

    if (  [self isDisconnected]  ) {
        return;
    }
    
    pthread_mutex_lock( &areDisconnectingMutex );
    if (  areDisconnecting  ) {
        pthread_mutex_unlock( &areDisconnectingMutex );
        NSLog(@"disconnect: while disconnecting");
        return;
    }
    
    if (  userKnows  ) {
        requestedState = @"EXITING";
    }

    areDisconnecting = TRUE;
    pthread_mutex_unlock( &areDisconnectingMutex );
    
    BOOL disconnectionComplete = FALSE;

    if (  pid > 0  ) {
        [self killProcess];
        if (  [wait boolValue]  ) {
            // Wait up to five seconds for the OpenVPN process to disappear
            disconnectionComplete = [NSApp waitUntilNoProcessWithID: pid];
        }
    } else {
        if([managementSocket isConnected]) {
            NSLog(@"No process ID; disconnecting via management interface");
            [managementSocket writeString: @"signal SIGTERM\r\n" encoding: NSASCIIStringEncoding];
            
            if (  [wait boolValue]  ) {
                // Wait up to five seconds for the management socket to disappear
                int i;
                for (i=0; i<5; i++) {
                    if (  managementSocket == nil  ) {
                        break;
                    }
                    sleep(1);
                }
            }

            disconnectionComplete = (managementSocket == nil) || ( ! [managementSocket isConnected]);
        }
    }
    
    if (  disconnectionComplete  ) {
        [self performSelectorOnMainThread: @selector(hasDisconnected) withObject: nil waitUntilDone: NO];
    } else {

        if (  [wait boolValue]  ) {
            forceKillInterval = 10;   // Seconds between disconnect attempts
            id terminationSeconds;
            if (  terminationSeconds = [gTbDefaults objectForKey: @"openvpnTerminationInterval"]  ) {
                if (   [terminationSeconds respondsToSelector: @selector(intValue)]  ) {
                    forceKillInterval = [terminationSeconds intValue];
                }
            }
            forceKillTimeout = 180;   // Seconds before considering it disconnected anyway
            if (  terminationSeconds = [gTbDefaults objectForKey: @"openvpnTerminationTimeout"]  ) {
                if (   [terminationSeconds respondsToSelector: @selector(intValue)]  ) {
                    forceKillTimeout = [terminationSeconds intValue];
                }
            }
            
            if (  forceKillInterval  != 0) {
                if ( forceKillTimeout != 0  ) {
                    forceKillWaitSoFar = 0;
                    forceKillTimer = [NSTimer scheduledTimerWithTimeInterval: (NSTimeInterval) forceKillInterval
                                                                      target: self
                                                                    selector: @selector(forceKillWatchdogHandler)
                                                                    userInfo: nil
                                                                     repeats: YES];
                    [self performSelectorOnMainThread: @selector(tellUserAboutDisconnectWait) withObject: nil waitUntilDone: NO];
                }
            }
        }
    }
}
// Tries to kill the OpenVPN process associated with this connection, if any
-(void)killProcess 
{
	NSString* path = [[NSBundle mainBundle] pathForResource: @"openvpnstart" 
													 ofType: nil];
	NSTask* task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath: path]; 
	NSString *pidString = [NSString stringWithFormat:@"%d", pid];
    
	NSArray *arguments = [NSArray arrayWithObjects:@"kill", pidString, nil];
	[task setArguments:arguments];
	[task setCurrentDirectoryPath: firstPartOfPath(configPath)];
	[task launch];
	[task waitUntilExit];
}

-(void) tellUserAboutDisconnectWait
{
    TBRunAlertPanel(NSLocalizedString(@"OpenVPN Not Responding", @"Window title"),
                    [NSString stringWithFormat: NSLocalizedString(@"OpenVPN is not responding to disconnect requests.\n\n"
                                                                  "There is a known bug in OpenVPN version 2.1 that sometimes"
                                                                  " causes a delay of one or two minutes before it responds to such requests.\n\n"
                                                                  "Tunnelblick will continue to try to disconnect for up to %d seconds.\n\n"
                                                                  "The connection will be unavailable until OpenVPN disconnects or %d seconds elapse,"
                                                                  " whichever comes first.", @"Window text"), forceKillTimeout, forceKillTimeout],
                    nil, nil, nil);
}    

-(void) forceKillWatchdogHandler
{
    [self performSelectorOnMainThread: @selector(forceKillWatchdog) withObject: nil waitUntilDone: NO];
}

-(void) forceKillWatchdog
{
    if (  ! [self isDisconnected]  ) {
        
        if (  pid > 0  ) {
            [self killProcess];
        } else {
            if([managementSocket isConnected]) {
                [managementSocket writeString: @"signal SIGTERM\r\n" encoding: NSASCIIStringEncoding];
            }
        }

        forceKillWaitSoFar += forceKillInterval;
        if (  forceKillWaitSoFar > forceKillTimeout) {
            TBRunAlertPanel(NSLocalizedString(@"Warning!", @"Window title"),
                            [NSString stringWithFormat: NSLocalizedString(@"OpenVPN has not responded to disconnect requests for %d seconds.\n\n"
                                                                          "The connection will be considered disconnected, but this computer's"
                                                                          " network configuration may be in an inconsistent state.", @"Window text"),
                             forceKillTimeout],
                            nil, nil, nil);
            [forceKillTimer invalidate];
            forceKillTimer = nil;
            [self hasDisconnected];
        }
    } else {
        [forceKillTimer invalidate];
        forceKillTimer = nil;
    }
}

static pthread_mutex_t lastStateMutex = PTHREAD_MUTEX_INITIALIZER;

// Call on main thread only
-(void) hasDisconnected
{
    pthread_mutex_lock( &lastStateMutex );
    if (  [lastState isEqualToString: @"EXITING"]  ) {
        pthread_mutex_unlock( &lastStateMutex );
        return;
    }
    [self setState:@"EXITING"];
    pthread_mutex_unlock( &lastStateMutex );
    
    [managementSocket close]; [managementSocket setDelegate: nil];
    [managementSocket release]; managementSocket = nil;
    portNumber = 0;
    pid = 0;
    areDisconnecting = FALSE;
    
    [[NSApp delegate] removeConnection:self];
    
    // Unload tun/tap if not used by any other processes
    if (  connectedWithTap  ) {
        [[NSApp delegate] decrementTapCount];
        connectedWithTap = FALSE;
    }
    if (  connectedWithTun  ) {
        [[NSApp delegate] decrementTunCount];
        connectedWithTun = FALSE;
    }
    [[NSApp delegate] unloadKexts];
    
    // Run the post-disconnect script, if any
    if (  [[configPath pathExtension] isEqualToString: @"tblk"]  ) {
        NSString * postDisconnectScriptPath = [configPath stringByAppendingPathComponent: @"Contents/Resources/post-disconnect.sh"];
        if (  [gFileMgr fileExistsAtPath: postDisconnectScriptPath]  ) {
            NSString * path = [[NSBundle mainBundle] pathForResource: @"openvpnstart" ofType: nil];
            NSArray * startArguments = [self argumentsForOpenvpnstartForNow: YES];
            if (   startArguments == nil
                || [[startArguments objectAtIndex: 5] isEqualToString: @"1"]  ) {
                return;
            }
            NSArray * arguments = [NSArray arrayWithObjects:
                                   @"postDisconnect",
                                   [startArguments objectAtIndex: 1],    // configFile
                                   [startArguments objectAtIndex: 5],    // cfgLocCode
                                   nil];
            
            NSTask * task = [[NSTask alloc] init];
            [task setLaunchPath: path];
            [task setArguments: arguments];
            [task launch];
            [task waitUntilExit];
            [task release];
        }
    }
    
    [self flushDnsCache];

}
    
-(void) flushDnsCache
{
    NSString * key = [displayName stringByAppendingString:@"-doNotFlushCache"];
    if (  ! [gTbDefaults boolForKey: key]  ) {
        BOOL didNotTry = TRUE;
        NSArray * pathArray = [NSArray arrayWithObjects: @"/usr/bin/dscacheutil", @"/usr/sbin/lookupd", nil];
        NSString * path;
        NSEnumerator * arrEnum = [pathArray objectEnumerator];
        while (  path = [arrEnum nextObject]  ) {
            if (  [gFileMgr fileExistsAtPath: path]  ) {
                didNotTry = FALSE;
                NSArray * arguments = [NSArray arrayWithObject: @"-flushcache"];
                NSTask * task = [[NSTask alloc] init];
                [task setLaunchPath: path];
                [task setArguments: arguments];
                [task launch];
                [task waitUntilExit];
                int status = [task terminationStatus];
                [task release];
                if (  status != 0) {
                    [self addToLog: [NSString stringWithFormat: @"*Tunnelblick: Failed to flush the DNS cache; the command was: '%@ -flushcache'", path]];
                } else {
                    [self addToLog: @"*Tunnelblick: Flushed the DNS cache"];
                    break;
                }
            }
        }
        
        if (  didNotTry  ) {
            [self addToLog: @"* Tunnelblick: DNS cache not flushed; did not find needed executable"];
        }
    }
}

- (void) netsocketConnected: (NetSocket*) socket
{
    
    NSParameterAssert(socket == managementSocket);
    
    if (NSDebugEnabled) NSLog(@"Tunnelblick connected to management interface on port %d.", [managementSocket remotePort]);
    
    NS_DURING {
		[managementSocket writeString: @"pid\r\n"           encoding: NSASCIIStringEncoding];
        [managementSocket writeString: @"state on\r\n"      encoding: NSASCIIStringEncoding];    
		[managementSocket writeString: @"state\r\n"         encoding: NSASCIIStringEncoding];
        [managementSocket writeString: @"hold release\r\n"  encoding: NSASCIIStringEncoding];
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

-(void) setStateFromLine: (NSString *) line 
{
    @try {
        NSArray* parameters = [line componentsSeparatedByString: @","];
        NSString *stateString = [parameters objectAtIndex:1];
        if (  [stateString length] > 3  ) {
            NSArray * validStates = [NSArray arrayWithObjects:
                                     @"ADD_ROUTES", @"ASSIGN_IP", @"AUTH", @"CONNECTED",  @"CONNECTING",
                                     @"EXITING", @"GET_CONFIG", @"RECONNECTING", @"RESOLVE", @"SLEEP", @"WAIT", nil];
            if (  [validStates containsObject: stateString]  ) {
                [self processState: stateString dated: [parameters objectAtIndex: 0]];
            }
        }
    } @catch(NSException *exception) {
    }
}

-(void) processState: (NSString *) newState dated: (NSString *) dateTime
{
    if ([newState isEqualToString: @"EXITING"]) {
        [self hasDisconnected];                     // Sets lastState and does processing only once
    } else {
        
        [self setState: newState];
        
        if([newState isEqualToString: @"RECONNECTING"]) {
            [managementSocket writeString: @"hold release\r\n" encoding: NSASCIIStringEncoding];
            
        } else if ([newState isEqualToString: @"CONNECTED"]) {
            NSDate *date; 
            if (  dateTime) {
                date = [NSCalendarDate dateWithTimeIntervalSince1970: [dateTime intValue]];
            } else {
                date = [[[NSDate alloc] init] autorelease];
            }
            
            [[NSApp delegate] addConnection:self];
            [self setConnectedSinceDate: date];
            [self flushDnsCache];
            
        }
    }
}

- (void) processLine: (NSString*) line
{
    isHookedup = TRUE;
    tryingToHookup = FALSE;
    
    if (![line hasPrefix: @">"]) {
        // Output in response to command to OpenVPN
		[self setPIDFromLine:line];
        [self setStateFromLine:line];
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
            [self processState: state dated: nil];
            
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
                        [self disconnectAndWait: [NSNumber numberWithBool: YES] userKnows: YES];      // (User knows about it from the alert)
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
                    if (  [myAuthAgent authenticationWasFromKeychain]  ) {
                        [self addToLog: @"*Tunnelblick: Obtained VPN passphrase from the Keychain"];
                    }
                    NSString *myPassphrase = [myAuthAgent passphrase];
					NSRange tokenNameRange = NSMakeRange(pwrange_need.length, pwrange_password.location - 6 );
					NSString* tokenName = [parameterString substringWithRange: tokenNameRange];
					if (NSDebugEnabled) NSLog(@"tokenName is  '%@'", tokenName);
                    if(  myPassphrase != nil  ){
                        [managementSocket writeString: [NSString stringWithFormat: @"password \"%@\" \"%@\"\r\n", tokenName, escaped(myPassphrase)] encoding:NSISOLatin1StringEncoding]; 
                    } else {
                        [self disconnectAndWait: [NSNumber numberWithBool: YES] userKnows: YES];      // (User requested it by cancelling)
                    }

                } else if ([line rangeOfString: @"Auth"].length) {
                    if (NSDebugEnabled) NSLog(@"Server wants user auth/pass.");
                    [myAuthAgent setAuthMode:@"password"];
                    [myAuthAgent performAuthentication];
                    if (  [myAuthAgent authenticationWasFromKeychain]  ) {
                        [self addToLog: @"*Tunnelblick: Obtained VPN username and password from the Keychain"];
                    }
                    NSString *myPassword = [myAuthAgent password];
                    NSString *myUsername = [myAuthAgent username];
                    if(  (myUsername != nil) && (myPassword != nil)  ){
                        [managementSocket writeString:[NSString stringWithFormat:@"username \"Auth\" \"%@\"\r\n", escaped(myUsername)] encoding:NSISOLatin1StringEncoding];
                        [managementSocket writeString:[NSString stringWithFormat:@"password \"Auth\" \"%@\"\r\n", escaped(myPassword)] encoding:NSISOLatin1StringEncoding];
                    } else {
                        [self disconnectAndWait: [NSNumber numberWithBool: YES] userKnows: YES];      // (User requested it by cancelling)
                    }
                
                } else {
                    NSLog(@"Unrecognized PASSWORD command from OpenVPN management interface has been ignored:\n%@", line);
                }
            }

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


// Returns contents of the log display
-(NSTextStorage *) logStorage
{
    return [logDisplay logStorage];
}

// Adds a message to the log display with the current date/time
-(void)addToLog:(NSString *)text
{
    [logDisplay addToLog: text];
}

// Clears the log
-(void) clearLog
{
    [logDisplay clear];
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
        [self performSelectorOnMainThread: @selector(hasDisconnected) withObject: nil waitUntilDone: NO];
    }
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

    if (   [lastState isEqualToString: @"EXITING"]
        && [requestedState isEqualToString: @"CONNECTED"]
        && ( ! [[NSApp delegate] terminatingAtUserRequest] )  ) {
        TBRunAlertPanelExtended(NSLocalizedString(@"Unexpected disconnection", @"Window title"),
                                [NSString stringWithFormat: NSLocalizedString(@"'%@' has been unexpectedly disconnected.", @"Window text"), [self displayName]],
                                nil, nil, nil,
                                @"skipWarningAboutUnexpectedDisconnections",
                                NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
                                nil);
        requestedState = @"EXITING";
    }
    
    [[NSApp delegate] performSelectorOnMainThread:@selector(setState:) withObject:newState waitUntilDone:NO];
    [delegate performSelector: @selector(connectionStateDidChange:) withObject: self];    
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
        if ([[connection state] isEqualToString:@"CONNECTED"]) commandString = NSLocalizedString(@"Disconnect %@%@", @"Menu item");
        else commandString = NSLocalizedString(@"Connect %@%@", @"Menu item");
        
        // Remove submenu prefix if using submenus
        NSString * itemName = [connection displayName];
        NSRange lastSlashRange = [itemName rangeOfString: @"/" options: NSBackwardsSearch range: NSMakeRange(0, [itemName length] - 1)];
        if (   (lastSlashRange.length != 0)
            && ( ! [gTbDefaults boolForKey: @"doNotShowConnectionSubmenus"])  ) {
            itemName = [itemName substringFromIndex: lastSlashRange.location + 1];
        }
        
        NSString * locationMessage = @"";
        if (  [gConfigDirs count] > 1  ) {
            if (  [[connection configPath] hasPrefix: gDeployPath]  ) {
                locationMessage =  NSLocalizedString(@" (Deployed)", @"Window title");
            } else if (  [[connection configPath] hasPrefix: gSharedPath]  ) {
                locationMessage =  NSLocalizedString(@" (Shared)", @"Window title");
            }
        }
        NSString *itemTitle = [NSString stringWithFormat:commandString, itemName, locationMessage];
        [anItem setTitle:itemTitle];
        if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
            [anItem setToolTip: [connection configPath]];
        }
    }
	return YES;
}

-(int) useDNSStatus
{
	NSString * key = [[self displayName] stringByAppendingString:@"useDNS"];
	id useObj = [gTbDefaults objectForKey:key];
	if (  useObj == nil  ) {
		return 1;   // Preference is not set, so use default value
	} else {
        if (  [[useObj class] isSubclassOfClass: [NSNumber class]]  ) {
            return [useObj intValue];
        } else {
            NSLog(@"Preference '%@' is not a number; it has value %@. Assuming 'Do not set nameserver'", key, useObj);
            return 0;
        }
    }
}

// Returns an array of NSDictionary objects with entries for the 'Set nameserver' popup button for this connection
-(NSArray *) modifyNameserverOptionList
{
    // Figure out whether to use the standard scripts or 'custom' scripts
    // If Deployed, .tblk, or "old" scripts exist, they are considered "custom" scripts
    BOOL custom = FALSE;
    NSString * resourcePath          = [[NSBundle mainBundle] resourcePath];
    
    if (  [configPath hasPrefix: gDeployPath]  ) {
        NSString * deployPath                  = [resourcePath stringByAppendingPathComponent: @"Deploy"];
        NSString * configFile                  = [configPath lastPathComponent];
        NSString * deployScriptPath            = [deployPath stringByAppendingPathComponent:[configFile stringByDeletingPathExtension]];
        NSString * deployUpscriptPath          = [deployScriptPath stringByAppendingPathExtension: @"up.sh"            ];
        NSString * deployUpscriptNoMonitorPath = [deployScriptPath stringByAppendingPathExtension: @"nomonitor.up.sh"  ];
        NSString * deployNewUpscriptPath       = [deployScriptPath stringByAppendingPathExtension: @"up.tunnelblick.sh"];
        if (   [gFileMgr fileExistsAtPath: deployUpscriptPath]
            || [gFileMgr fileExistsAtPath: deployUpscriptNoMonitorPath]
            || [gFileMgr fileExistsAtPath: deployNewUpscriptPath]  ) {
            custom = TRUE;
        }
    } else {
        NSString * upscriptPath          = [resourcePath stringByAppendingPathComponent: @"client.up.osx.sh"          ];
        NSString * upscriptNoMonitorPath = [resourcePath stringByAppendingPathComponent: @"client.nomonitor.up.osx.sh"];
        if (   [gFileMgr fileExistsAtPath: upscriptPath]
            || [gFileMgr fileExistsAtPath: upscriptNoMonitorPath]  ) {
            custom = TRUE;
        }
    }
    
    if (  ! custom  ) {
        if (  [[configPath pathExtension] isEqualToString: @"tblk"]) {
            NSString * scriptPath                   = [configPath stringByAppendingPathComponent: @"Contents/Resources"];
            NSString * tblkUpscriptPath             = [scriptPath stringByAppendingPathComponent: @"up.sh"            ];
            NSString * tblkUpscriptNoMonitorPath    = [scriptPath stringByAppendingPathComponent: @"nomonitor.up.sh"  ];
            NSString * tblkNewUpscriptPath          = [scriptPath stringByAppendingPathComponent: @"up.tunnelblick.sh"];
            if (   [gFileMgr fileExistsAtPath: tblkUpscriptPath]
                || [gFileMgr fileExistsAtPath: tblkUpscriptNoMonitorPath]
                || [gFileMgr fileExistsAtPath: tblkNewUpscriptPath]  ) {
                custom = TRUE;
            }
        }
    }
    
    if (   custom  ) {
        return [[[NSArray alloc] initWithObjects:
                 [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Do not set nameserver",        @"PopUpButton"), @"name", @"0", @"value", nil],
                 [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Set nameserver",               @"PopUpButton"), @"name", @"1", @"value", nil],
                 nil] autorelease];
    } else {
        return [[[NSArray alloc] initWithObjects:
                 [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Do not set nameserver",        @"PopUpButton"), @"name", @"0", @"value", nil],
                 [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Set nameserver",               @"PopUpButton"), @"name", @"1", @"value", nil],
                 [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Set nameserver (3.0b10)",      @"PopUpButton"), @"name", @"3", @"value", nil],
                 [NSDictionary dictionaryWithObjectsAndKeys: [NSString stringWithFormat:
                                                              NSLocalizedString(@"Set nameserver (alternate %d)", @"PopUpButton"), 1] , @"name", @"2", @"value", nil],
                 nil] autorelease];
    }
}

@end
