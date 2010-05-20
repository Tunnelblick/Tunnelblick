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
#import <Security/AuthSession.h>
#import <signal.h>
#import "openvpnstart.h"
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
extern NSDictionary         * gOpenVPNVersionDict;
extern SecuritySessionId      gSecuritySessionId;
extern unsigned int           gHookupTimeout;

extern NSString * firstPartOfPath(NSString * thePath);

extern NSString * lastPartOfPath(NSString * thePath);

@interface VPNConnection()          // PRIVATE METHODS

-(NSArray *)        argumentsForOpenvpnstartForNow: (BOOL)          forNow;

-(void)             connectToManagementSocket;

-(unsigned int)     getFreePort;

-(void)             killProcess;                                                // Kills the OpenVPN process associated with this connection, if any

-(BOOL)             makePlistFileForAtPath:     (NSString *)        plistPath
                                 withLabel:     (NSString *)        daemonLabel;

-(void)             processLine:                (NSString *)        line;

-(void)             processState:               (NSString *)        newState
                           dated:               (NSString *)        dateTime;

-(void)             setConnectedSinceDate:      (NSDate *)          value;

-(void)             setManagementSocket:        (NetSocket *)       socket;

-(void)             setPort:                    (unsigned int)      inPort; 

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
        logStorage = nil;
		[self addToLog:[[NSApp delegate] openVPNLogHeader] atDate: nil];
        lastState = @"EXITING";
		myAuthAgent = [[AuthAgent alloc] initWithConfigName:[self displayName]];
        tryingToHookup = FALSE;
        isHookedup = FALSE;
        tunOrTap = nil;
        myPipePath = [pipePathFromConfigPath(inPath) copy];
        myPipe = nil;
        myPipeError = FALSE;
        areDisconnecting = FALSE;
        
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
{
    if (  portNumber != 0  ) {
        NSLog(@"Ignoring attempt to 'tryToHookupToPort' for '%@' -- already using port number %d", [self description], portNumber);
        return;
    }
    
    if (  managementSocket  ) {
        NSLog(@"Ignoring attempt to 'tryToHookupToPort' for '%@' -- already using managementSocket", [self description]);
        return;
    }
    
    // Read in the log file, parse the date/time in each line, and add everything to the log
    NSString * actualConfigPath = [self configPath];
    if (  [[actualConfigPath pathExtension] isEqualToString: @"tblk"]  ) {
        actualConfigPath = [actualConfigPath stringByAppendingPathComponent: @"Contents/Resources/config.ovpn"];
    }
    NSString * logPath = constructOpenVPNLogPath(actualConfigPath, inPortNumber);
    NSNumber * logSizeN = [[gFileMgr fileAttributesAtPath: logPath traverseLink: NO] objectForKey: NSFileSize];
    if (  logSizeN  ) {
        long long logSize = [logSizeN  longLongValue];
        if (  logSize > 10000000  ) {
            [self addToLog: [NSString stringWithFormat:@"*Tunnelblick: OpenVPN log file at %@ is too large (%@ bytes) to display\n", logPath, logSizeN] atDate: nil];
        } else if (  logSize != 0  ) {
            NSString * msg = [[NSString alloc] initWithData: [gFileMgr contentsAtPath: logPath] encoding:NSUTF8StringEncoding];
            NSArray * arr = [msg componentsSeparatedByString:@"\n"];
            [msg release];

            [self addToLog: @"*Tunnelblick: ---------- Start of OpenVPN log before Tunnelblick was launched" atDate: nil];
            
            NSMutableAttributedString * msgAS = [[NSMutableAttributedString alloc] init];
            NSString * line;
            const char * cLogLine;
            const char * cRestOfLogLine;
            struct tm cTime;
            char cDateTimeStringBuffer[] = "1234567890123456789012345678901";
            NSEnumerator * e = [arr objectEnumerator];
            while (  line = [e nextObject]  ) {
                cLogLine = [line UTF8String];
                cRestOfLogLine = strptime(cLogLine, "%c", &cTime);
                if (  cRestOfLogLine  ) {
                    size_t timeLen = strftime(cDateTimeStringBuffer, 30, "%Y-%m-%d %H:%M:%S", &cTime);
                    if (  timeLen  ) {
                        line = [NSString stringWithFormat: @"%s%s", cDateTimeStringBuffer, cRestOfLogLine];
                    }
                }

                line = [line stringByAppendingString: @"\n"];
                NSAttributedString * s = [[NSAttributedString alloc] initWithString: line];
                [msgAS appendAttributedString: s];
                [s release];
            }
            [[self logStorage] appendAttributedString: msgAS];
            [msgAS release];
            
            [self addToLog: @"*Tunnelblick: ---------- End of OpenVPN log before Tunnelblick was launched" atDate: nil];
            [self addToLog: @"*Tunnelblick: Start of \"current\" OpenVPN log. May contain entries duplicating some of the above" atDate: nil];
        }
    }
    
    [self setPort: inPortNumber];
    tryingToHookup = TRUE;
    [self connectToManagementSocket];
}

-(void) stopTryingToHookup
{
    if (   tryingToHookup
        && ( ! isHookedup  )  ) {
        tryingToHookup = FALSE;
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
            [gFileMgr removeFileAtPath: plistPath handler: nil];
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
            [gFileMgr removeFileAtPath: plistPath handler: nil];
            return NO;
        } else {
            NSLog(@"NOT connect '%@' when computer starts cancelled by user", [self displayName]);
            [gFileMgr removeFileAtPath: plistPath handler: nil];
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
            if (  ! [gFileMgr removeFileAtPath: flagPath handler: nil]  ) {
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
    
    if (  ! [gFileMgr removeFileAtPath: flagPath handler: nil]  ) {
        NSLog(@"Unable to remove temporary file %@", flagPath);
    }

    if (  ! [gFileMgr removeFileAtPath: plistPath handler: nil]  ) {
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
    
    [gFileMgr removeFileAtPath: plistPath handler: nil];
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
    [tunOrTap release];
    [configPath release];
    [displayName release];
    [connectedSinceDate release];
    [myAuthAgent release];
    [myPipePath release];
    [myPipe release];
    [myPipeBuffer release];
    [super dealloc];
}

-(void) invalidateConfigurationParse
{
    [tunOrTap release];
    tunOrTap = nil;
}

- (void) connect: (id) sender
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
    
    authenticationFailed = NO;
    
    areDisconnecting = FALSE;
    myPipeError = FALSE;
    
    [managementSocket close];
    [managementSocket setDelegate: nil];
    [managementSocket release];
    managementSocket = nil;
    
	NSArray *arguments = [self argumentsForOpenvpnstartForNow: YES];
    if (  arguments == nil  ) {
        return;
    }
		
	NSTask* task = [[[NSTask alloc] init] autorelease];
    
	NSString* path = [[NSBundle mainBundle] pathForResource: @"openvpnstart" ofType: nil];
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
    [self addToLog: logText atDate: nil];

    NSMutableArray * escapedArguments = [NSMutableArray arrayWithCapacity:[arguments count]];
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
    
	[self connectToManagementSocket];
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
    
    NSString *useDNS = @"0";
	if(useDNSStatus(self)) {
        NSString * useDownRootPluginKey = [[self displayName] stringByAppendingString: @"-useDownRootPlugin"];
        if (  [gTbDefaults boolForKey: useDownRootPluginKey]  ) {
            useDNS = @"2";
        } else {
            useDNS = @"1";
        }
        if (  forNow  ) {
            usedSetNameserver = TRUE;
        }
	} else {
        if (  forNow  ) {
            usedSetNameserver = FALSE;
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
    if (  [useDNS isEqualToString: @"0"] || [gTbDefaults boolForKey: noMonitorKey]  ) {
        noMonitor = @"1";
    }

    int bitMask = 0;
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
    
    NSString * onSystemStartKey = [[self displayName] stringByAppendingString: @"-onSystemStart"];
    if (   (! forNow )
        || [gTbDefaults boolForKey: onSystemStartKey]  ) {
        bitMask = bitMask | CREATE_LOG_FILE;
    }
    
    NSString * bitMaskString = [NSString stringWithFormat: @"%d", bitMask];
    
    NSArray * args = [NSArray arrayWithObjects:
                      @"start", [[lastPartOfPath(cfgPath) copy] autorelease], portString, useDNS, skipScrSec, altCfgLoc, noMonitor, bitMaskString, nil];
    return args;
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
		[self disconnect: sender];
	} else {
		[self connect: sender];
	}
}


- (void) connectToManagementSocket
{
    [self setManagementSocket: [NetSocket netsocketConnectedToHost: @"127.0.0.1" port: portNumber]];   
}

- (void) disconnect: (id)sender 
{
    if (  [self isDisconnected]  ) {
        NSLog(@"Ignored disconnect: because already disconnected");
        return;
    }
    
    if (  ! areDisconnecting  ) {
        areDisconnecting = TRUE;
        
        pid_t savedPid = 0;
        if(pid > 0) {
            savedPid = pid;
            [self killProcess];
            [NSApp waitUntilNoProcessWithID: savedPid];
        } else {
            if([managementSocket isConnected]) {
                [managementSocket writeString: @"signal SIGTERM\r\n" encoding: NSASCIIStringEncoding];
                sleep(5);       // Wait five seconds for OpenVPN to disappear after it sends terminating log output
            }
        }
        
        [self emptyPipe];
        
        if (  ! [managementSocket peekData]  ) {
            [managementSocket close]; [managementSocket setDelegate: nil];
            [managementSocket release]; managementSocket = nil;
            if (  [myPipeBuffer length] == 0  ) {
                [self destroyPipe];
                [self addToLog:@"*Tunnelblick: Destroyed pipe for scripts - disconnecting and no managmentSocket data available" atDate: nil];
            }
        }
        
        [[NSApp delegate] removeConnection:self];
        [self setState:@"EXITING"];
        [[NSApp delegate] unloadKexts];
        
    } else {
        NSLog(@"disconnect: while disconnecting or disconnected");
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
    
    // We also give the path to the actual config file, so that any log file associated with it will be deleted, too
    // (We leave the pipe alone so it can output any disconnection info -- it is deleted only when Tunnelblick quits)
    NSString * actualConfigPath = [self configPath];
    if (  [[actualConfigPath pathExtension] isEqualToString: @"tblk"]  ) {
        actualConfigPath = [actualConfigPath stringByAppendingPathComponent: @"Contents/Resources/config.ovpn"];
    }
    
	NSArray *arguments = [NSArray arrayWithObjects:@"kill", pidString, actualConfigPath, nil];
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
		[managementSocket writeString: @"pid\r\n"           encoding: NSASCIIStringEncoding];
        [managementSocket writeString: @"state on\r\n"      encoding: NSASCIIStringEncoding];    
		[managementSocket writeString: @"state\r\n"         encoding: NSASCIIStringEncoding];
        [managementSocket writeString: @"log on all\r\n"    encoding: NSASCIIStringEncoding];
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
                                     @"EXITING", @"GET_CONFIG", @"RECONNECTING", @"SLEEP", @"WAIT", nil];
            if (  [validStates containsObject: stateString]  ) {
                [self processState: stateString dated: [parameters objectAtIndex: 0]];
            }
        }
    } @catch(NSException *exception) {
    }
}

-(void) processState: (NSString *) newState dated: (NSString *) dateTime
{
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
        
    } else if ([newState isEqualToString: @"EXITING"]) {
        [managementSocket close]; [managementSocket setDelegate: nil];
        [managementSocket release]; managementSocket = nil;
        portNumber = 0;
    }
}

- (void) processLine: (NSString*) line
{
    isHookedup = TRUE;
    tryingToHookup = FALSE;
    
    // Take the first opportunity to hook up to the pipe that the scripts output to the OpenVPN Log with
    if (  ( ! myPipe ) && ( ! myPipeError )  ) {
        myPipeBuffer = [[NSMutableString alloc] initWithCapacity: 10000];
        myPipe = [[NamedPipe alloc] initPipeReadingFromPath: myPipePath
                                              sendingDataTo: @selector(appendDataToLog:)
                                                  whichIsIn: self];
        if (  myPipe  ) {
            [self addToLog: @"*Tunnelblick: Attached to pipe for scripts" atDate: nil];
        } else {
            NSLog(@"Unable to initialize pipe %@ for up/down/leasewatch scripts to write to OpenVPN Log", myPipePath);
            myPipeError = TRUE;
        }
    }
    
    if (![line hasPrefix: @">"]) {
        // Output in response to command to OpenVPN. Could be the PID command, or additional log output from LOG ON ALL
		[self setPIDFromLine:line];
        [self setStateFromLine:line];
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
        if (   ( ! areDisconnecting )
            && ( ! [self isDisconnected]  )  ) {
            [self performSelectorOnMainThread: @selector(disconnect:) withObject: nil waitUntilDone: NO];
        }
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
    if (  myPipe  ) {
        [self emptyPipe];
        sleep(1);
        [myPipe destroyPipe];
        [myPipe release];
        [myPipeBuffer release];
        myPipe = nil;
        myPipeBuffer = nil;
    }
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
    if (  areDisconnecting  ) {
        if (  [myPipeBuffer length] == 0  ) {
            [self destroyPipe];
            [self addToLog:@"*Tunnelblick: Destroyed pipe for scripts - disconnecting and buffer became empty" atDate: nil];
        }
    }
}

@end
