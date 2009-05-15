/*
 * Copyright (c) 2004 Angelo Laub
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
		NSString * versionInfo = [NSString stringWithFormat:@"Tunnelblick version %@",[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
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
		[alert addButtonWithTitle:local(@"Connect once")];
		[alert addButtonWithTitle:local(@"Cancel")];
		[alert addButtonWithTitle:[NSString stringWithFormat:local(@"Always allow %@ to connect"),[self configName]]];
		[alert setMessageText:local(@"Connect even though configuration file is not secure?")];
		[alert setInformativeText:[NSString stringWithFormat:local(@"%@ is not secure and Tunnelblick cannot make it secure. Connect anyway?"), cfgPath]];
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
	arguments = [NSArray arrayWithObjects:@"start", configPath, portString, useDNS, nil];
		
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

- disconnect: (id)sender 
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
			NSCalendarDate* date = [NSCalendarDate dateWithTimeIntervalSince1970: [[parameters objectAtIndex: 0] intValue]];
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
                
                NSCalendarDate* date = [NSCalendarDate dateWithTimeIntervalSince1970: [[parameters objectAtIndex: 0] intValue]];
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
                if ([line rangeOfString: @"Need \'Private Key\'"].length) {
					[myAuthAgent setAuthMode:@"privateKey"];
					[myAuthAgent performAuthentication];
					// Server wants a private key:
                    NSString *myPassphrase = [myAuthAgent passphrase];
					if(myPassphrase){
						[managementSocket writeString: [NSString stringWithFormat: @"password \"Private Key\" \"%@\"\r\n",myPassphrase] encoding:NSISOLatin1StringEncoding]; 
					} else {
						[self disconnect:self];
					}
					
					
                }
                else if ([line rangeOfString: @"Failed"].length) {
                    //NSLog(@"Passphrase verification failed.\n");
                    [self disconnect:nil];
                    [NSApp activateIgnoringOtherApps:YES];
					[myAuthAgent deletePassphraseFromKeychain];
                    NSRunAlertPanel(local(@"Passphrase verification failed."),local(@"Please try again"),local(@"Okay"),nil,nil);
                    
                    [self connect:nil];
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
				NSCalendarDate* date = [NSCalendarDate dateWithTimeIntervalSince1970: [[parameters objectAtIndex: 0] intValue]];
				NSString* logLine = [parameters lastObject];
				[self addToLog:logLine atDate:date];
            } 
        
    }
}
	



-(void)addToLog:(NSString *)text atDate:(NSCalendarDate *)date {
	//[logText appendFormat:@"%@: %@\n",[date descriptionWithCalendarFormat:@"%a %m/%d/%y %I:%M %p"],text];
    NSString *dateText = [NSString stringWithFormat:@"%@: %@\n",[date descriptionWithCalendarFormat:@"%a %m/%d/%y %I:%M %p"],text];

    
    [[self logStorage] appendAttributedString: [[[NSAttributedString alloc] initWithString: dateText] autorelease]];
    //NSLog(@"Log now: \n%@", [logStorage string]);
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

//- (IBAction) updateUI
//{
//    NSString *myState = [@"OpenVPN: " stringByAppendingString: NSLocalizedString(lastState, @"")];
//    [[myMenu itemAtIndex:0] setTitle:myState];
//}

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
        if ([[connection state] isEqualToString:@"CONNECTED"]) commandString = local(@"Disconnect");
        else commandString = local(@"Connect");
        
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
