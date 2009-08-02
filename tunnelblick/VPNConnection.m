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

@implementation VPNConnection

-(id) initWithConfig:(NSString *)inConfig
{	
    if (self = [super init]) {
        configPath = [inConfig retain];
        portNumber = 0;
		pid = 0;
		connectedSinceDate = [[NSDate alloc] init];
        //myLogController = [[LogController alloc] initWithSender:self]; 
		NSString * versionInfo = [NSString stringWithFormat:NSLocalizedString(@"Tunnelblick version %@", nil),[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
		NSCalendarDate* date = [NSCalendarDate date];
		[self addToLog:versionInfo atDate:date];
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
    //[myLogController release];
    [lastState release];
    [myMenu release];	
    [configPath release];
    [super dealloc];
}


- (IBAction) connect: (id) sender
{
	NSString *cfgPath = [NSString stringWithFormat:@"%@/Library/openvpn/%@",NSHomeDirectory(),[self configPath]];
	if ([self configNeedsRepair:cfgPath]) {
		if([self repairConfigPermissions:cfgPath] != errAuthorizationSuccess) {
			// user clicked on cancel, so do nothing
			NSLog(@"Connect: Authorization failed.");
			return;
		}
	}
	if([self configNeedsRepair:cfgPath]) {

		NSAlert *alert = [[NSAlert alloc] init];
		[alert addButtonWithTitle:NSLocalizedString(@"Connect once", nil)];
		[alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
		[alert addButtonWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Always allow %@ to connect", nil),[self configName]]];
		[alert setMessageText:NSLocalizedString(@"Connect even though configuration file is not secure?", nil)];
		[alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"%@ is not secure and Tunnelblick cannot make it secure. Connect anyway?", nil), cfgPath]];
		[alert setAlertStyle:NSWarningAlertStyle];
		[[alert window] setFloatingPanel:YES];

		int alertValue = [alert runModal];
		[alert release];
		
		if (alertValue == NSAlertSecondButtonReturn) {		//Cancel
			NSLog(@"Connect: User cancelled connect because configuration file %@ is not secure.",cfgPath);
			return;
		}
		if (alertValue == NSAlertThirdButtonReturn) {		//Connect always - set a per-connection preference, then fall through to connect
			NSString* ignoreConfOwnerOrPermissionErrorKey = [[self configName] stringByAppendingString: @"IgnoreConfOwnerOrPermissionError"];
			[[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithBool: YES] forKey: ignoreConfOwnerOrPermissionErrorKey];
			[[NSUserDefaults standardUserDefaults] synchronize];
		}
															//Connect once -- just fall through to connect
	}

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
	}
    
    NSString *skipCheck = @"1"; //Don't repeat check of config file; we already checked it above and either it's OK or user said to skip the check
    
	arguments = [NSArray arrayWithObjects:@"start", configPath, portString, useDNS, skipCheck, nil];
		
	[task setArguments:arguments];
	NSString *openvpnDirectory = [NSString stringWithFormat:@"%@/Library/openvpn",NSHomeDirectory()];
	[task setCurrentDirectoryPath:openvpnDirectory];
	[task launch];
	[task waitUntilExit];

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
	[task launch];
	[task waitUntilExit];
	pid = 0;
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
			pid = atoi([pidString cString]);			
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
				NSDate *now = [[NSDate alloc] init];
				
                if([state isEqualToString: @"RECONNECTING"]) {
                    [managementSocket writeString: @"hold release\r\n" encoding: NSASCIIStringEncoding];
                } else if ([state isEqualToString: @"CONNECTED"]) {
                    [[NSApp delegate] addConnection:self];
					[self setConnectedSinceDate:now];
                }
            } else if ([command isEqualToString: @"PASSWORD"]) {
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
						[managementSocket writeString: [NSString stringWithFormat: @"password \"%@\" \"%@\"\r\n", tokenName, myPassphrase] encoding:NSISOLatin1StringEncoding]; 
					} else {
						[self disconnect:self];
					}
                }
                else if ([line rangeOfString: @"Failed"].length) {
                    //NSLog(@"Passphrase verification failed.\n");
                    [self disconnect:nil];
                    [NSApp activateIgnoringOtherApps:YES];
					id buttonWithDifferentCredentials = nil;
                    if ([myAuthAgent keychainHasPassphrase]) {
						buttonWithDifferentCredentials = NSLocalizedString(@"Try again with different credentials", nil);
					}
					int alertVal = NSRunAlertPanel(NSLocalizedString(@"Verification failed.", nil),
												   NSLocalizedString(@"The credentials (passphrase or username/password) were not accepted by the remote VPN server.", nil),
												   NSLocalizedString(@"Try again", nil),buttonWithDifferentCredentials,NSLocalizedString(@"Cancel", nil));
					if (alertVal == NSAlertAlternateReturn) {
						[myAuthAgent deletePassphraseFromKeychain];
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
						[managementSocket writeString:[NSString stringWithFormat:@"username \"Auth\" \"%@\"\r\n",myUsername] encoding:NSISOLatin1StringEncoding];
						[managementSocket writeString:[NSString stringWithFormat:@"password \"Auth\" \"%@\"\r\n",myPassword] encoding:NSISOLatin1StringEncoding];
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
					int needButtonReturn = NSRunAlertPanel(tokenName,NSLocalizedString(@"Please insert token", nil),NSLocalizedString(@"OK", nil),NSLocalizedString(@"Cancel", nil),nil);
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

-(void)setMenu:(NSMenu *)inMenu 
{
    [myMenu release];
    myMenu = [inMenu retain];
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
        if ([[connection state] isEqualToString:@"CONNECTED"]) commandString = NSLocalizedString(@"Disconnect", nil);
        else commandString = NSLocalizedString(@"Connect", nil);
        
        NSString *itemTitle = [NSString stringWithFormat:@"%@ '%@'", commandString, [connection configName]];
        [anItem setTitle:itemTitle]; 
	}
	return YES;
}

-(BOOL)configNeedsRepair:(NSString *)configFile 
{
	NSString* ignoreConfOwnerOrPermissionErrorKey = [[self configName] stringByAppendingString: @"IgnoreConfOwnerOrPermissionError"];
	if (  [[NSUserDefaults standardUserDefaults] boolForKey:ignoreConfOwnerOrPermissionErrorKey]  ) {
		return NO;
	}
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSDictionary *fileAttributes = [fileManager fileAttributesAtPath:configFile traverseLink:YES];
	unsigned long perms = [fileAttributes filePosixPermissions];
	NSString *octalString = [NSString stringWithFormat:@"%o",perms];
	NSNumber *fileOwner = [fileAttributes fileOwnerAccountID];
	
	if ( (![octalString isEqualToString:@"644"])  || (![fileOwner isEqualToNumber:[NSNumber numberWithInt:0]])) {
		NSLog(@"File %@ has permissions: %@, is owned by %@ and needs repair...\n",configFile,octalString,fileOwner);
		return YES;
	}
	return NO;
}
-(OSStatus)repairConfigPermissions:(NSString *)configFile
{
	AuthorizationRef authRef = [NSApplication getAuthorizationRef];
	
	NSString *helper = @"/bin/chmod";
	NSArray *arguments = [NSArray arrayWithObjects:@"644",configFile,nil];
	[NSApplication executeAuthorized:helper withArguments:arguments withAuthorizationRef:authRef];
	
	helper = @"/usr/sbin/chown";
	arguments = [NSArray arrayWithObjects:@"root:wheel",configFile,nil];
	
	OSStatus status;
	int i = 0;
	int maxtries = 5;
	for (i=0; i <= maxtries; i++) {
		status = [NSApplication executeAuthorized:helper withArguments:arguments withAuthorizationRef:authRef];
		if(status != errAuthorizationSuccess) goto exit;
		sleep(1);
		if(![self configNeedsRepair:configFile]) {
			break;
		}
	}
	
	
exit:
	AuthorizationFree (authRef, kAuthorizationFlagDefaults);	
	return status;
}


@end
