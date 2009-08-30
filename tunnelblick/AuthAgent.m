/*
 *  Copyright (c) 2005, 2006, 2007, 2008, 2009 Angelo Laub
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

#import "AuthAgent.h"
#import "helper.h"

NSString *escaped(NSString *string) {
	NSMutableString * stringOut = [[string mutableCopy] autorelease];
	[stringOut replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:NSLiteralSearch range:NSMakeRange(0, [string length])];
	[stringOut replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:NSLiteralSearch range:NSMakeRange(0, [string length])];
	return stringOut;
}

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
    NSString *question = NSLocalizedString(@"Please enter VPN passphrase.", nil);
    [dict setObject:NSLocalizedString(@"Passphrase", nil) forKey:(NSString *)kCFUserNotificationAlertHeaderKey];
    [dict setObject:question forKey:(NSString *)kCFUserNotificationAlertMessageKey];
    [dict setObject:NSLocalizedString(@"Save in Keychain", nil) forKey:(NSString *)kCFUserNotificationCheckBoxTitlesKey];
    [dict setObject:@"" forKey:(NSString *)kCFUserNotificationTextFieldTitlesKey];
    [dict setObject:NSLocalizedString(@"OK", nil) forKey:(NSString *)kCFUserNotificationDefaultButtonTitleKey];
    [dict setObject:NSLocalizedString(@"Cancel", nil) forKey:(NSString *)kCFUserNotificationAlternateButtonTitleKey];
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
        [self loadKeyChainManager];
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
    NSString* usernameLocal = nil;
    NSString* passwd = nil;
    NSArray *array =[NSArray array];
				/* Dictionary for the panel.  */
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    NSString *question = NSLocalizedString(@"Please enter VPN username/password combination.", nil);
    [dict setObject:NSLocalizedString(@"Username and password", nil) forKey:(NSString *)kCFUserNotificationAlertHeaderKey];
    [dict setObject:question forKey:(NSString *)kCFUserNotificationAlertMessageKey];
    [dict setObject:NSLocalizedString(@"Save in Keychain", nil) forKey:(NSString *)kCFUserNotificationCheckBoxTitlesKey];
    [dict setObject:[NSArray arrayWithObjects:NSLocalizedString(@"Username:", nil),NSLocalizedString(@"Password:", nil),nil] forKey:(NSString *)kCFUserNotificationTextFieldTitlesKey];
    [dict setObject:NSLocalizedString(@"OK", nil) forKey:(NSString *)kCFUserNotificationDefaultButtonTitleKey];
    [dict setObject:NSLocalizedString(@"Cancel", nil) forKey:(NSString *)kCFUserNotificationAlternateButtonTitleKey];
    NSString *isSetKey = [NSString stringWithFormat:@"%@-usernameIsSet",[self configName]];
	NSString *usernameKey = [NSString stringWithFormat:@"%@-authUsername",[self configName]];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:isSetKey]) { // see if we have set a username and keychain item earlier
		usernameLocal =[[NSUserDefaults standardUserDefaults] objectForKey:usernameKey];
        [self loadKeyChainManager];
		[keyChainManager setAccountName:usernameLocal];
        passwd = [keyChainManager password];
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
            usernameLocal = [[(NSString*)CFUserNotificationGetResponseValue(notification, kCFUserNotificationTextFieldValuesKey,	0) retain] autorelease];
            if((response & CFUserNotificationCheckBoxChecked(0))) // if checkbox is checked, store in keychain
            {
                /* write authusername to user defaults */
                [[NSUserDefaults standardUserDefaults] setObject:usernameLocal forKey:usernameKey];
                [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:YES] forKey:isSetKey];
                [[NSUserDefaults standardUserDefaults] synchronize];
                
                [keyChainManager setAccountName:usernameLocal];
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
        usernameLocal = [[(NSString*)CFUserNotificationGetResponseValue(notification, kCFUserNotificationTextFieldValuesKey,	0) retain] autorelease];
        if((response & CFUserNotificationCheckBoxChecked(0))) // if checkbox is checked, store in keychain
        {
            /* write authusername to user defaults */
            [[NSUserDefaults standardUserDefaults] setObject:usernameLocal forKey:usernameKey];
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:YES] forKey:isSetKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            [self loadKeyChainManager];
            if([keyChainManager setPassword:passwd] != 0)
            {
                fprintf(stderr,"Storing in Keychain was unsuccessful\n");
            }
            
        }
    }
    
    if([usernameLocal length] > 0 && [passwd length] > 0) {
        array = [NSArray arrayWithObjects:usernameLocal,passwd,nil];
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
		NSString *usernameLocal = [authArray objectAtIndex:0];
		NSString *passwd = [authArray objectAtIndex:1];
		[self setUsername:escaped(usernameLocal)];
		[self setPassword:escaped(passwd)];

	}
	else {
		[self setPassword:nil];
	}
}
-(void)performPrivateKeyAuthentication {
	if (NSDebugEnabled) NSLog(@"Server wants private key passphrase.");
	[self loadKeyChainManager];
	
	NSString *passphraseLocal = [keyChainManager password];
	if (passphraseLocal == nil) {
		if (NSDebugEnabled) NSLog(@"Passphrase not set, setting...\n");
		do {
			passphraseLocal = [self authenticate];
		} while([passphraseLocal isEqualToString:@""]);
	}
	[self setPassphrase:escaped(passphraseLocal)];
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
        [keyChainManager release];
        keyChainManager = nil;
        [self loadKeyChainManager];
    }
}

-(void)deletePassphraseFromKeychain 
{
	[self loadKeyChainManager];

	[keyChainManager deletePassword];
}

-(BOOL) keychainHasPassphrase
{
	[self loadKeyChainManager];

	if ([keyChainManager password] == nil) {
		return NO;
	} else {
		return YES;
	}
}

-(void) loadKeyChainManager
{
	if (keyChainManager == nil) {
		if([authMode isEqualToString:@"privateKey"]) {
			keyChainManager = [[KeyChain alloc] initWithService:@"OpenVPN" withAccountName:[@"OpenVPN-" stringByAppendingString:[self configName]]];
		} else {
			keyChainManager = [[KeyChain alloc] initWithService:[@"OpenVPN-Auth-" stringByAppendingString:[self configName]] withAccountName:username];
		}
	}
}
@end
