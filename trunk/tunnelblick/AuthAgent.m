//
//  AuthAgent.m
//  Tunnelblick
//
//  Created by al on 12/22/05.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import "AuthAgent.h"


@implementation AuthAgent

-(id) initWithConfigName:(NSString *)inConfigName
{
	if (inConfigName == nil) return nil;
    if (self = [super init]) {
        [self setConfigName:inConfigName];
    }
    return self;
}


-(NSString *)authenticate
{
    
    /* Dictionary for the panel.  */
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    NSString *question = local(@"Please enter OpenVPN passphrase.");
    [dict setObject:local(@"Passphrase") forKey:(NSString *)kCFUserNotificationAlertHeaderKey];
    [dict setObject:question forKey:(NSString *)kCFUserNotificationAlertMessageKey];
    
    
    [dict setObject:local(@"Add Passphrase To Apple Keychain") forKey:(NSString *)kCFUserNotificationCheckBoxTitlesKey];
    
    [dict setObject:@"" forKey:(NSString *)kCFUserNotificationTextFieldTitlesKey];
    [dict setObject:local(@"Ok") forKey:(NSString *)kCFUserNotificationDefaultButtonTitleKey];
    [dict setObject:local(@"Cancel") forKey:(NSString *)kCFUserNotificationAlternateButtonTitleKey];
    SInt32 error;
    CFUserNotificationRef notification = CFUserNotificationCreate(NULL, 30, CFUserNotificationSecureTextField(0), &error, (CFDictionaryRef)dict);
    CFOptionFlags response;
    /* If we couldn't receive a response, return NULL. */
    if((error) || (CFUserNotificationReceiveResponse(notification, 0, &response)))
    {
        return nil;
    }
    
    if((response & 0x3) != kCFUserNotificationDefaultResponse) // user clicked on cancel
    {
        return nil;
    }
    /* Get the passphrase from the textfield. */
    NSString* passwd = [[(NSString*)CFUserNotificationGetResponseValue(notification, kCFUserNotificationTextFieldValuesKey, 0) retain] autorelease];
    
    if((response & CFUserNotificationCheckBoxChecked(0)))
    {
        if([keyChainManager setPassword:passwd] != 0)
        {
            fprintf(stderr,"Storing in Keychain was unsuccessful\n");
        }
    }
    
    //CFRelease(notification);
    return passwd;
}

-(NSArray *)getAuth
{
    NSString* username = nil;
    NSString* passwd = nil;
    NSArray *array =[NSArray array];
				/* Dictionary for the panel.  */
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    NSString *question = local(@"Please enter OpenVPN username/password combination.");
    [dict setObject:local(@"Passphrase") forKey:(NSString *)kCFUserNotificationAlertHeaderKey];
    [dict setObject:question forKey:(NSString *)kCFUserNotificationAlertMessageKey];
    
    
    [dict setObject:local(@"Add Passphrase To Apple Keychain") forKey:(NSString *)kCFUserNotificationCheckBoxTitlesKey];
    
    [dict setObject:[NSArray arrayWithObjects:local(@"Username:"),local(@"Password:"),nil] forKey:(NSString *)kCFUserNotificationTextFieldTitlesKey];
    [dict setObject:local(@"Ok") forKey:(NSString *)kCFUserNotificationDefaultButtonTitleKey];
    [dict setObject:local(@"Cancel") forKey:(NSString *)kCFUserNotificationAlternateButtonTitleKey];
    NSString *isSetKey = [NSString stringWithFormat:@"%@-usernameIsSet",[self configName]];
	NSString *usernameKey = [NSString stringWithFormat:@"%@-authUsername",[self configName]];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:isSetKey]) { // see if we have set a username and keychain item earlier
        
        
		username =[[NSUserDefaults standardUserDefaults] objectForKey:usernameKey];
		KeyChain *myChainManager = [[[KeyChain alloc] initWithService:@"OpenVPN-Auth" withAccountName:username] autorelease];
		[keyChainManager setAccountName:username];
        passwd = [myChainManager password];
        if(!passwd) {  // password was deleted in keychain so get it anew
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:NO] forKey:isSetKey];
            SInt32 error;
            CFUserNotificationRef notification = CFUserNotificationCreate(NULL, 0, CFUserNotificationSecureTextField(1), &error, (CFDictionaryRef)dict);
            CFOptionFlags response;
            /* If we couldn't receive a response, return NULL. */
            if((error) || (CFUserNotificationReceiveResponse(notification, 0, &response)))
            {
                return nil;
            }
            
            if((response & 0x3) != kCFUserNotificationDefaultResponse) //user clicked on cancel
            {
                return nil;
            }
            /* Get the passphrase from the textfield. */
            passwd = [[(NSString*)CFUserNotificationGetResponseValue(notification, kCFUserNotificationTextFieldValuesKey, 1) retain] autorelease];
            username = [[(NSString*)CFUserNotificationGetResponseValue(notification, kCFUserNotificationTextFieldValuesKey,	0) retain] autorelease];
            if((response & CFUserNotificationCheckBoxChecked(0))) // if checkbox is checked, store in keychain
            {
                /* write authusername to user defaults */
                [[NSUserDefaults standardUserDefaults] setObject:username forKey:usernameKey];
                [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:YES] forKey:isSetKey];
                [[NSUserDefaults standardUserDefaults] synchronize];
                
                [keyChainManager setAccountName:username];
                if([keyChainManager setPassword:passwd] != 0)
                {
                    fprintf(stderr,"Storing in Keychain was unsuccessful\n");
                }
                
            }
        }
        
    }
    else { // username and passwort was never stored in keychain
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:NO] forKey:isSetKey];
        
        SInt32 error;
        CFUserNotificationRef notification = CFUserNotificationCreate(NULL, 0, CFUserNotificationSecureTextField(1), &error, (CFDictionaryRef)dict);
        CFOptionFlags response;
        /* If we couldn't receive a response, return nil. */
        if((error) || (CFUserNotificationReceiveResponse(notification, 0, &response)))
        {
            return nil;
        }
        
        if((response & 0x3) != kCFUserNotificationDefaultResponse)
        {
            return [NSArray array];
        }
        /* Get the passphrase from the textfield. */
        passwd = [[(NSString*)CFUserNotificationGetResponseValue(notification, kCFUserNotificationTextFieldValuesKey, 1) retain] autorelease];
        username = [[(NSString*)CFUserNotificationGetResponseValue(notification, kCFUserNotificationTextFieldValuesKey,	0) retain] autorelease];
        if((response & CFUserNotificationCheckBoxChecked(0))) // if checkbox is checked, store in keychain
        {
            /* write authusername to user defaults */
            [[NSUserDefaults standardUserDefaults] setObject:username forKey:usernameKey];
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:YES] forKey:isSetKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            KeyChain *keyChainManager = [[[KeyChain alloc] initWithService:@"OpenVPN-Auth" withAccountName:username] autorelease];
            if([keyChainManager setPassword:passwd] != 0)
            {
                fprintf(stderr,"Storing in Keychain was unsuccessful\n");
            }
            
        }
    }
    
    if([username length] > 0 && [passwd length] > 0) {
        
        
        
        array = [NSArray arrayWithObjects:username,passwd,nil];
		//CFRelease(notification);
        return array;
    }
    else return nil;
}

- (NSString *)username {
    return [[username retain] autorelease];
}

- (void)setUsername:(NSString *)value {
    if (username != value) {
        [username release];
        username = [value copy];
    }
}

- (NSString *)password {
	if([[self authMode] isEqualToString:@"password"]) {
		return [[password retain] autorelease];
	} else {
		return nil;
	}
}

- (void)setPassword:(NSString *)value {
    if (password != value) {
        [password release];
        password = [value copy];
    }
}

- (NSString *)passphrase {
    return [[passphrase retain] autorelease];
}

- (void)setPassphrase:(NSString *)value {
    if (passphrase != value) {
        [passphrase release];
        passphrase = [value copy];
    }
}
- (NSString *)configName {
    return [[configName retain] autorelease];
}

- (void)setConfigName:(NSString *)value {
    if (configName != value) {
        [configName release];
        configName = [value copy];
    }
}


-(void)performPasswordAuthentication {
	NSArray *authArray;
//	while((authArray = [self getAuth]) == nil) {
//		if ([authArray count]==0) break;
//	}
	//do {
		authArray = [self getAuth];

	if([authArray count]) {                
		NSMutableString *username = [[authArray objectAtIndex:0] mutableCopy];
		NSMutableString *passwd = [[authArray objectAtIndex:1] mutableCopy];
//		[username replaceOccurrencesOfString:@" " withString:@"\\ " options:NSLiteralSearch range:NSMakeRange(0, [username length])];
//		[passwd replaceOccurrencesOfString:@" " withString:@"\\ " options:NSLiteralSearch range:NSMakeRange(0, [passwd length])];
		[self setUsername:username];
		[self setPassword:passwd];

	}
	else {
		[self setPassword:nil];
	}
}
-(void)performPrivateKeyAuthentication {
	if (NSDebugEnabled) NSLog(@"Server wants private key passphrase.");
	id keyChainManager = [[[KeyChain alloc] initWithService:@"OpenVPN" withAccountName:[@"OpenVPN-" stringByAppendingString:[self configName]]] autorelease];
	
	NSMutableString *passphrase = [[keyChainManager password] mutableCopy];
	if (passphrase == nil) {
		if (NSDebugEnabled) NSLog(@"Passphrase not set, setting...\n");
		do {
			passphrase = [[self authenticate] mutableCopy];
		} while([passphrase isEqualToString:@""]);
	}
//	[passphrase replaceOccurrencesOfString:@" " withString:@"\\ " options:NSLiteralSearch range:NSMakeRange(0, [passphrase length])];
	[self setPassphrase:passphrase];
}

-(void)performAuthentication
{
	if([[self authMode] isEqualToString:@"password"]) {
		[self performPasswordAuthentication];
	} else {
		[self performPrivateKeyAuthentication];
	}
}
- (NSString *)authMode {
    return [[authMode retain] autorelease];
}

- (void)setAuthMode:(NSString *)value {
    if (authMode != value) {
        [authMode release];
        authMode = [value copy];
		if([authMode isEqualToString:@"privateKey"]) {
			keyChainManager = [[KeyChain alloc] initWithService:@"OpenVPN" withAccountName:[@"OpenVPN-" stringByAppendingString:[self configName]]];
		} else {
			keyChainManager = [[KeyChain alloc] initWithService:@"OpenVPN-Auth"];
		}
    }
}

-(void)deletePassphraseFromKeychain 
{
	[keyChainManager deletePassword];
}

@end
