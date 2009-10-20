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
#import <Security/Security.h>
#import <CoreServices/CoreServices.h>
#import <Foundation/NSDebug.h>
#import <signal.h>
#import "KeyChain.h"
#import "NetSocket.h"
#import "NetSocket+Text.h"
#import "NSApplication+LoginItem.h"
#import "helper.h"
#import "MenuController.h"
#include <sys/param.h>
#include <sys/mount.h>

@interface VPNConnection()          // PRIVATE METHODS

-(void)             addToLog:                   (NSString *)    text            atDate:     (NSCalendarDate *)      date;
-(BOOL)             configNeedsRepair:          (NSString *)    configFile;
-(void)             connectToManagementSocket;
-(BOOL)             copyFile:                   (NSString *)    source          toFile:     (NSString *)            target      usingAuth:  (AuthorizationRef)  authRef;
-(BOOL)             makeSureFolderExistsAtPath: (NSString *)    folderPath      usingAuth:  (AuthorizationRef)      authRef;
-(NSString *)       getConfigToUse:             (NSString *)    cfgPath         orAlt:      (NSString *)            altCfgPath;
-(unsigned int)     getFreePort;
-(void)             killProcess;
-(BOOL)             onRemoteVolume:             (NSString *)    cfgPath;
-(void)             processLine:                (NSString *)    line;
-(BOOL)             repairConfigPermissions:    (NSString *)    configFile      usingAuth:  (AuthorizationRef) authRef;
-(void)             setConnectedSinceDate:      (NSDate *)      value;
-(void)             setManagementSocket:        (NetSocket *)   socket;

@end

@implementation VPNConnection

-(id) initWithConfig:(NSString *)inConfig
{	
    if (self = [super init]) {
        configPath = [inConfig retain];
        portNumber = 0;
		pid = 0;
		connectedSinceDate = [[NSDate alloc] init];
		NSCalendarDate* date = [NSCalendarDate date];
		[self addToLog:[NSString stringWithFormat:@"*Tunnelblick: %@; %@", tunnelblickVersion(), openVPNVersion()] atDate:date];
        lastState = @"EXITING";
		myAuthAgent = [[AuthAgent alloc] initWithConfigName:[self configName]];
    }
    return self;
}

-(NSString *) description
{
	return [NSString stringWithFormat:@"VPN Connection %@", configPath];
}
-(void) setConfigPath:(NSString *)inPath 
{
    if (inPath!=configPath) {
	[configPath release];
	configPath = [inPath retain];
    }
}

-(void)setPort:(unsigned int)inPort 
{
	portNumber = inPort;
}

-(unsigned int)port 
{
    return portNumber;
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
    [logStorage release];
    [self disconnect:self];
    [self setManagementSocket: nil];
    
    [managementSocket release];
    [lastState release];
    [configPath release];
    [connectedSinceDate release];
    [myAuthAgent release];
    [super dealloc];
}


- (IBAction) connect: (id) sender
{
	NSString *cfgPath = [NSString stringWithFormat:@"%@/Library/openvpn/%@", NSHomeDirectory(), [self configPath]];
    NSString *altPath = [NSString stringWithFormat:@"/Library/Tunnelblick/%@/%@", NSUserName(), [self configPath]];

    if ( ! (cfgPath = [self getConfigToUse:cfgPath orAlt:altPath]) ) {
        return;
    }

    ignoreOnePasswordRequest = NO;
    
	NSParameterAssert(managementSocket == nil);
	NSString* path = [[NSBundle mainBundle] pathForResource: @"openvpnstart" 
													 ofType: nil];
	[self setPort:[self getFreePort]];
	NSTask* task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath: path]; 
		
	NSString *portString = [NSString stringWithFormat:@"%d",portNumber];
	NSArray *arguments;
		
	NSString *useDNS = @"0";
	if(useDNSStatus(self)) {
		useDNS = @"1";
        usedSetNameserver = TRUE;
	} else {
        usedSetNameserver = FALSE;
    }

    NSString *altCfgLoc = @"0";
    if ( [cfgPath isEqualToString:altPath] ) {
        altCfgLoc = @"1";
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
    
    NSPipe * pipe = [[NSPipe alloc] init];
    [task setStandardError: pipe];
    
    arguments = [NSArray arrayWithObjects:@"start", [self configPath], portString, useDNS, skipScrSec, altCfgLoc, nil];
    
	[task setArguments:arguments];
	NSString *openvpnDirectory = [NSString stringWithFormat:@"%@/Library/openvpn",NSHomeDirectory()];
	[task setCurrentDirectoryPath:openvpnDirectory];
	[task launch];
	[task waitUntilExit];
    
    int status = [task terminationStatus];
    
    if (  status != 0  ) {
        NSString * openvpnstartOutput;
        if (  status == 240  ) {
            openvpnstartOutput = @"Internal Tunnelblick error: openvpnstart syntax error";
        } else {
            NSFileHandle * file = [pipe fileHandleForReading];
            NSData * data = [file readDataToEndOfFile];
            openvpnstartOutput = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
            openvpnstartOutput = [openvpnstartOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        
        [self addToLog:[NSString stringWithFormat:NSLocalizedString(@"*Tunnelblick: openvpnstart status #%d: %@", @"OpenVPN Log message"), status, openvpnstartOutput]
                atDate:[NSCalendarDate date]];
    }
    
    [pipe release];
    
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


- (NSString*) configPath
{
    return [[configPath retain] autorelease];
}

- (NSString*) configName
{
    return [[[[[self configPath] lastPathComponent] stringByDeletingPathExtension] retain] autorelease];
}

- (void) connectToManagementSocket
{
    [self setManagementSocket: [NetSocket netsocketConnectedToHost: @"127.0.0.1" port: portNumber]];   
}

- (IBAction) disconnect: (id)sender 
{
	if(pid > 0) {
		[self killProcess];	
	}
	else {
		if([managementSocket isConnected])
		{
			[managementSocket writeString: @"signal SIGTERM\r\n" encoding: NSASCIIStringEncoding];
		}		
	}
    [[NSApp delegate] removeConnection:self];
    [managementSocket close]; [managementSocket setDelegate: nil];
    [managementSocket release]; managementSocket = nil;
    
    [self setState:@"EXITING"];
    
}



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
	NSString *openvpnDirectory = [NSString stringWithFormat:@"%@/Library/openvpn",NSHomeDirectory()];
	[task setCurrentDirectoryPath:openvpnDirectory];
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
	/* Additional Output, so it's probably a good idea to write this into the log
	   this happens e.g. with buffered log messages after saying log on all
	 */
    if (![line hasPrefix: @">"]) {
		[self setPIDFromLine:line];
		@try {
			NSArray* parameters = [line componentsSeparatedByString: @","];
            NSCalendarDate* date;
            if ( [[parameters objectAtIndex: 0] intValue] == 0) {
                date = [NSCalendarDate date];
            } else {
                date = [NSCalendarDate dateWithTimeIntervalSince1970: [[parameters objectAtIndex: 0] intValue]];
            }
            NSString* logLine = [parameters lastObject];
			[self addToLog:logLine atDate:date];
		} @catch (NSException *exception) {
			
		}
		return;
	} 
		//NSArray* logEntry = [readString componentsSeparatedByString: @","];
        if (NSDebugEnabled) NSLog(@">openvpn: '%@'", line);
        
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
                }
            } else if ([command isEqualToString: @"PASSWORD"]) {
                if (  ignoreOnePasswordRequest  ) {
                    ignoreOnePasswordRequest = NO;
                    [self addToLog:[NSString stringWithFormat:@"*Tunnelblick: Ignoring server request \"%@\"", line] atDate:[NSCalendarDate date]];
                    return;
                }
				// Found password request from server:
                
                // Find out wether the server wants a private key or user/auth:
				
				NSRange pwrange_need = [parameterString rangeOfString: @"Need \'"];
				NSRange pwrange_password = [parameterString rangeOfString: @"\' password"];
                if (pwrange_need.length && pwrange_password.length) {
					// NSRange tokenNameRange = NSMakeRange(pwrange_need.length, [parameterString length] - pwrange_password.location + 1);
					NSRange tokenNameRange = NSMakeRange(pwrange_need.length, pwrange_password.location - 6 );
					NSString* tokenName = [parameterString substringWithRange: tokenNameRange];
					if (NSDebugEnabled) NSLog(@"tokenName is  '%@'", tokenName);
					[myAuthAgent setAuthMode:@"privateKey"];
					[myAuthAgent performAuthentication];
					// Server wants a private key:
                    NSString *myPassphrase = [myAuthAgent passphrase];
					if(myPassphrase){
						[managementSocket writeString: [NSString stringWithFormat: @"password \"%@\" \"%@\"\r\n", tokenName, escaped(myPassphrase)] encoding:NSISOLatin1StringEncoding]; 
					} else {
						[self disconnect:self];
					}
                }
                else if ([line rangeOfString: @"Failed"].length) {
                    if (NSDebugEnabled) NSLog(@"Passphrase verification failed.\n");
                    ignoreOnePasswordRequest = YES;
                    [self disconnect:nil];
                    [NSApp activateIgnoringOtherApps:YES];
					id buttonWithDifferentCredentials = nil;
                    if ([myAuthAgent keychainHasCredentials]) {
						buttonWithDifferentCredentials = NSLocalizedString(@"Try again with different credentials", @"Button");
					}
					int alertVal = TBRunAlertPanel([NSString stringWithFormat:@"%@: %@",
                                                                              [self configName],
                                                                              NSLocalizedString(@"Authentication failed", @"Window title")],
                                                    NSLocalizedString(@"The credentials (passphrase or username/password) were not accepted by the remote VPN server.", @"Window text"),
                                                    NSLocalizedString(@"Try again", @"Button"),
                                                    buttonWithDifferentCredentials,
                                                    NSLocalizedString(@"Cancel", @"Button"));
					if (alertVal == NSAlertAlternateReturn) {
						[myAuthAgent deleteCredentialsFromKeychain];
					}
					if (  (alertVal == NSAlertAlternateReturn) || (alertVal == NSAlertDefaultReturn)  ) {	// i.e., not Other (Cancel) or Error returns
						[self connect:nil];
					}
                }
                else if ([line rangeOfString: @"Auth"].length) { // Server wants user/auth:
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
					
                }
                
            } else if ([command isEqualToString:@"LOG"]) {
                NSArray* parameters = [parameterString componentsSeparatedByString: @","];
                NSCalendarDate* date;
                if ( [[parameters objectAtIndex: 0] intValue] == 0) {
                    date = [NSCalendarDate date];
                } else {
                    date = [NSCalendarDate dateWithTimeIntervalSince1970: [[parameters objectAtIndex: 0] intValue]];
                }
				NSString* logLine = [parameters lastObject];
				[self addToLog:logLine atDate:date];
            }
			else if ([command isEqualToString:@"NEED-OK"]) {
				// NEED-OK: MSG:Please insert TOKEN
				NSRange tokenNameRange = [parameterString rangeOfString: @"MSG:"];
				NSString* tokenName = [parameterString substringFromIndex: tokenNameRange.location+4];
				if ([line rangeOfString: @"Need 'token-insertion-request' confirmation"].length) {
					if (NSDebugEnabled) NSLog(@"Server wants token.");
					int needButtonReturn = TBRunAlertPanel([NSString stringWithFormat:@"%@: %@",
                                                                                      [self configName],
                                                                                      NSLocalizedString(@"Please insert token", @"Window title")],
                                                           [NSString stringWithFormat:NSLocalizedString(@"Please insert token \"%@\", then click \"OK\"", @"Window text"), tokenName],
                                                           nil,
                                                           NSLocalizedString(@"Cancel", @"Button"),
                                                           nil);
					if (needButtonReturn == NSAlertDefaultReturn) {
						if (NSDebugEnabled) NSLog(@"Write need ok.");
						[managementSocket writeString:[NSString stringWithFormat:@"needok 'token-insertion-request' ok\r\n"] encoding:NSISOLatin1StringEncoding];
					} else {
						if (NSDebugEnabled) NSLog(@"Write need cancel.");
						[managementSocket writeString:[NSString stringWithFormat:@"needok 'token-insertion-request' cancel\r\n"] encoding:NSISOLatin1StringEncoding];
					}
				}
			}
        
    }
}
	



-(void)addToLog:(NSString *)text atDate:(NSCalendarDate *)date {
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
    if (NSDebugEnabled) NSLog(@"Socket disconnected...\n");
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
        
        NSString *itemTitle = [NSString stringWithFormat:@"%@ '%@'", commandString, [connection configName]];
        [anItem setTitle:itemTitle]; 
	}
	return YES;
}

-(BOOL)configNeedsRepair:(NSString *)configFile 
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSDictionary *fileAttributes = [fileManager fileAttributesAtPath:configFile traverseLink:YES];
	unsigned long perms = [fileAttributes filePosixPermissions];
	NSString *octalString = [NSString stringWithFormat:@"%o",perms];
	NSNumber *fileOwner = [fileAttributes fileOwnerAccountID];
	
	if ( (![octalString isEqualToString:@"644"])  || (![fileOwner isEqualToNumber:[NSNumber numberWithInt:0]])) {
		NSLog(@"Configuration file %@ has permissions: 0%@, is owned by %@ and needs repair...\n",configFile,octalString,fileOwner);
		return YES;
	}
	return NO;
}

// Given paths to the regular config in ~/Library/openvpn, and an alternate config in /Library/Tunnelblick/<username>/
// Returns the path to use, or nil if can't use either one
-(NSString *) getConfigToUse:(NSString *)cfgPath orAlt:(NSString *)altCfgPath
{
    if (  ! [self configNeedsRepair:cfgPath]  ) {                                                       // If config doesn't need repair
        if (  ! [[NSUserDefaults standardUserDefaults] boolForKey:@"useShadowConfigurationFiles"]  ) {  // And not using shadow configuration files
            return cfgPath;                                                                             // Then use it
        }
    }
    
    // Repair the configuration file or use the alternate
    AuthorizationRef authRef;
    if (    ! ( [self onRemoteVolume:cfgPath]
             || [[NSUserDefaults standardUserDefaults] boolForKey:@"useShadowConfigurationFiles"] )    ) {
        // Config is on non-remote volume and we are not supposed to use a shadow configuration file
        authRef = [NSApplication getAuthorizationRef];                                  // Try to repair regular config
        if ( authRef == nil ) {
            //NSLog(@"Not connecting: Authorization cancelled by user.");
            AuthorizationFree(authRef, kAuthorizationFlagDefaults);	
            return nil;
        }
        if( ! [self repairConfigPermissions:cfgPath usingAuth:authRef] ) {
            AuthorizationFree(authRef, kAuthorizationFlagDefaults);
            return nil;
        }
        AuthorizationFree(authRef, kAuthorizationFlagDefaults);                         // Repair worked, so return the regular conf
        return cfgPath;
    } else {
        // Config is on remote volume or we should use a shadow configuration file
        NSFileManager * fMgr = [NSFileManager defaultManager];                          // See if alt config exists
        if ( [fMgr fileExistsAtPath:altCfgPath] ) {
            // Alt config exists
            if ( [fMgr contentsEqualAtPath:cfgPath andPath:altCfgPath] ) {              // See if files are the same
                // Alt config exists and is the same as regular config
                if ( [self configNeedsRepair:altCfgPath] ) {                            // Check ownership/permissions
                    // Alt config needs repair
                    authRef = [NSApplication getAuthorizationRef];                      // Repair if necessary
                    if ( authRef == nil ) {
                        //NSLog(@"Not connecting: Authorization cancelled by user.");
                        AuthorizationFree(authRef, kAuthorizationFlagDefaults);
                        return nil;
                    }
                    if(  ! [self repairConfigPermissions:altCfgPath usingAuth:authRef]  ) {
                        AuthorizationFree(authRef, kAuthorizationFlagDefaults);
                        return nil;                                                     // Couldn't repair alt file
                    }
                    AuthorizationFree(authRef, kAuthorizationFlagDefaults);
                }
                return altCfgPath;                                                      // Return the alt config
            } else {
                // Alt config exists but is different
                authRef = [NSApplication getAuthorizationRef];                          // Overwrite it with the standard one and set ownership & permissions
                if ( authRef == nil ) {
                    //NSLog(@"Not connecting: Authorization cancelled by user.");
                    AuthorizationFree(authRef, kAuthorizationFlagDefaults);	
                    return nil;
                }
                if ( [self copyFile:cfgPath toFile:altCfgPath usingAuth:authRef] ) {
                    AuthorizationFree(authRef, kAuthorizationFlagDefaults);
                    return altCfgPath;                                                  // And return the alt config
                } else {
                    AuthorizationFree(authRef, kAuthorizationFlagDefaults);             // Couldn't overwrite alt file with regular one
                    return nil;
                }
            }
        } else {
            // Alt config doesn't exist. We must create it (and maybe the folders that it is in)
            NSString * libTbUserFolderPath = [altCfgPath          stringByDeletingLastPathComponent];   // Assumes alt config is in /Library/Tunnelblick/<username>/
            NSString * libTbFolderPath     = [libTbUserFolderPath stringByDeletingLastPathComponent];
            NSAssert([[libTbFolderPath stringByDeletingLastPathComponent] isEqualToString:@"/Library"], @"altCfgPath is not in /Library/xxx/yyy/");

            if (  ! [[NSUserDefaults standardUserDefaults] boolForKey:@"useShadowConfigurationFiles"]  ) {
                // Get user's permission to proceed
                NSString * longMsg = NSLocalizedString(@"Configuration file %@ is on a remote volume . Tunnelblick requires configuration files to be on a local volume for security reasons\n\nDo you want Tunnelblick to create and use a local copy of the configuration file in %@?\n\n(You will need an administrator name and password.)\n", @"Window text");
                int alertVal = TBRunAlertPanel([NSString stringWithFormat:@"%@: %@",
                                                                          [self configName],
                                                                          NSLocalizedString(@"Create local copy of configuration file?", @"Window title")],
                                               [NSString stringWithFormat:longMsg, cfgPath, libTbUserFolderPath],
                                               NSLocalizedString(@"Create copy", @"Button"),
                                               nil,
                                               NSLocalizedString(@"Cancel", @"Button"));
                if (  alertVal == NSAlertOtherReturn  ) {                                       // Cancel
                    return nil;
                }
            }

            authRef = [NSApplication getAuthorizationRef];                                      // Create folders if they don't exist:
            if ( authRef == nil ) {
                //NSLog(@"Not connecting: Authorization cancelled by user.");
                AuthorizationFree(authRef, kAuthorizationFlagDefaults);	
                return nil;
            }
            if ( ! [self makeSureFolderExistsAtPath:libTbFolderPath usingAuth:authRef] ) {      //        /Library/Tunnelblick
                AuthorizationFree(authRef, kAuthorizationFlagDefaults);
                return nil;
            }
            if ( ! [self makeSureFolderExistsAtPath:libTbUserFolderPath usingAuth:authRef] ) {  //       /Library/Tunnelblick/<username>
                AuthorizationFree(authRef, kAuthorizationFlagDefaults);
                return nil;
            }
            if ( [self copyFile:cfgPath toFile:altCfgPath usingAuth:authRef] ) {                // Copy the config to the alt config
                AuthorizationFree(authRef, kAuthorizationFlagDefaults);
                return altCfgPath;                                                              // Return the alt config
            }
            AuthorizationFree(authRef, kAuthorizationFlagDefaults);                             // Couldn't make alt file
            return nil;
        }
    }
}

// Returns TRUE if a file is on a remote volume or statfs on it fails, FALSE otherwise
-(BOOL) onRemoteVolume:(NSString *)cfgPath
{
    const char * fileName = [cfgPath UTF8String];
    struct statfs stats_buf;
    int status;

    if (  0 == (status = statfs(fileName, &stats_buf))  ) {
        if (  (stats_buf.f_flags & MNT_LOCAL) == MNT_LOCAL  ) {
            return FALSE;
        }
    } else {
        NSLog(@"statfs returned error %d; treating %@ as if it were on a remote volume", status, cfgPath);
    }
    return TRUE;   // Network volume or error accessing the file's data.
}

// Copies a config file and sets ownership and permissions
// Returns TRUE if succeeded, FALSE if failed, having already output an error message to the console log
-(BOOL) copyFile:(NSString *)source toFile: (NSString *) target usingAuth: (AuthorizationRef) authRef
{
    NSFileManager * fMgr;
	int i;
	int maxtries = 5;
    
	// Copy the file
    NSString *helper = @"/bin/cp";
	NSArray *arguments = [NSArray arrayWithObjects:@"-f", @"-p", source, target, nil];
	
	for (i=0; i <= maxtries; i++) {
        [NSApplication executeAuthorized:helper withArguments:arguments withAuthorizationRef:authRef];
        fMgr = [NSFileManager defaultManager];
        if ( [fMgr contentsEqualAtPath:source andPath:target] ) {
            break;
        }
        sleep(1);
    }
    if ( ! [fMgr contentsEqualAtPath:source andPath:target] ) {
        NSLog(@"Tunnelblick could not copy the config file %@ to the alternate local location %@ in %d attempts.", source, target, maxtries);
    TBRunAlertPanel([NSString stringWithFormat:@"%@: %@",
                                               [self configName],
                                               NSLocalizedString(@"Not connecting", @"Window title")],
                    NSLocalizedString(@"Tunnelblick could not copy the configuration file to the alternate local location. See the Console Log for details.", @"Window text"),
                    nil,
                    nil,
                    nil);
        return FALSE;
    }

    // Make sure the file is unlocked (if not, can't change ownership)
    NSDictionary * curAttributes;
    NSDictionary * newAttributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0] forKey:NSFileImmutable];
    
	for (i=0; i <= maxtries; i++) {
        curAttributes = [fMgr fileAttributesAtPath:target traverseLink:NO];
        if (  ! [curAttributes fileIsImmutable]  ) {
            break;
        }
        [fMgr changeFileAttributes:newAttributes atPath:target];
        sleep(1);
    }
    if (  [curAttributes fileIsImmutable]  ) {
         NSLog(@"Unlocking alternate configuration file %@ failed in %d attempts", target, maxtries);
    }
    
    // Set the file's ownership and permissions
    if (  [self configNeedsRepair:target]  ) {
        if (  ! [self repairConfigPermissions:target usingAuth:authRef]  ) {
            return FALSE;
        }
    }
    return TRUE;
}

// If the specified folder doesn't exist, uses root to create it so it is owned by root:wheel and has permissions 0755.
// If the folder exists, ownership doesn't matter (as long as we can read/execute it).
// Returns TRUE if the folder already existed or was created successfully, returns FALSE otherwise, having already output an error message to the console log.
-(BOOL) makeSureFolderExistsAtPath:(NSString *)folderPath usingAuth: (AuthorizationRef) authRef
{
	NSFileManager * fMgr = [NSFileManager defaultManager];
    BOOL isDir;

    if (  [fMgr fileExistsAtPath:folderPath isDirectory:&isDir] && isDir  ) {
        return TRUE;
    }
    
    NSString *helper = @"/bin/mkdir";
	NSArray *arguments = [NSArray arrayWithObjects:folderPath, nil];
    OSStatus status;
	int i = 0;
	int maxtries = 5;
    
	for (i=0; i <= maxtries; i++) {
		status = [NSApplication executeAuthorized:helper withArguments:arguments withAuthorizationRef:authRef];
		if (  [fMgr fileExistsAtPath:folderPath isDirectory:&isDir] && isDir  ) {
			break;
		}
		sleep(1);
	}

    if (    ! (  [fMgr fileExistsAtPath:folderPath isDirectory:&isDir] && isDir  )    ) {
        NSLog(@"Tunnelblick could not create folder %@ for the alternate configuration in %d attempts. OSStatus %ld.", folderPath, maxtries, status);
        TBRunAlertPanel([NSString stringWithFormat:@"%@: %@",
                                                    [self configName],
                                                    NSLocalizedString(@"Not connecting", @"Window title")],
                        NSLocalizedString(@"Tunnelblick could not create a folder for the alternate local configuration. See the Console Log for details.", @"Window text"),
                        nil,
                        nil,
                        nil);
        return FALSE;
    }
    return TRUE;
}

// Attempts to set ownership/permissions on a config file to root/0644
// Returns TRUE if succeeded, FALSE if failed, having already output an error message to the console log
-(BOOL)repairConfigPermissions:(NSString *)configFilePath usingAuth:(AuthorizationRef)authRef
{
	OSStatus status;
	int i = 0;
	int maxtries = 5;
	NSFileManager * fileManager = [NSFileManager defaultManager];
    NSDictionary * fileAttributes;
    unsigned long perms;
	NSString * octalString;
    NSNumber * fileOwner;
	
	// Try to set permissions
	NSString * helper = @"/bin/chmod";
	NSArray * arguments = [NSArray arrayWithObjects:@"644", configFilePath, nil];
	for (i=0; i <= maxtries; i++) {
		status = [NSApplication executeAuthorized:helper withArguments:arguments withAuthorizationRef:authRef];
        fileAttributes = [fileManager fileAttributesAtPath:configFilePath traverseLink:NO];
        perms = [fileAttributes filePosixPermissions];
        octalString = [NSString stringWithFormat:@"%lo",perms];
        if (  [octalString isEqualToString:@"644"]  ) {
            break;
        }
		sleep(1);
	}
    if (  ! [octalString isEqualToString:@"644"]  ) {
         NSLog(@"Unable to change permissions of configuration file %@ from 0%@ to 0644 in %d attempts; OSStatus = @ld", configFilePath, octalString, maxtries, status);
    }
    
	// Try to set ownership
    helper = @"/usr/sbin/chown";
	arguments = [NSArray arrayWithObjects:@"root:wheel", configFilePath, nil];

	for (i=0; i <= maxtries; i++) {
		status = [NSApplication executeAuthorized:helper withArguments:arguments withAuthorizationRef:authRef];
        fileAttributes = [fileManager fileAttributesAtPath:configFilePath traverseLink:NO];
        fileOwner = [fileAttributes fileOwnerAccountID];
        if (  [fileOwner isEqualToNumber:[NSNumber numberWithInt:0]]  ) {
            break;
        }
		sleep(1);
	}
    if (  ! [fileOwner isEqualToNumber:[NSNumber numberWithInt:0]]  ) {
        NSLog(@"Unable to change ownership of configuration file %@ from %@ to 0 in %d attempts. OSStatus = @ld", configFilePath, fileOwner, maxtries, status);
    }
    
    if (  [self configNeedsRepair:configFilePath]  ) {
        TBRunAlertPanel([NSString stringWithFormat:@"%@: %@",
                                                   [self configName],
                                                   NSLocalizedString(@"Not connecting", @"Window title")],
                        NSLocalizedString(@"Tunnelblick could not repair ownership and permissions of the configuration file. See the Console Log for details.", @"Window text"),
                        nil,
                        nil,
                        nil);
        return NO;
    }
    
    return YES;
}

    @end
