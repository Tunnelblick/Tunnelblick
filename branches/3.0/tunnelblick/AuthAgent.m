/*
 *  Copyright (c) 2005, 2006, 2007, 2008, 2009 Angelo Laub
 *  Contributions by Jonathan K. Bullard -- 2009
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
#import "TBUserDefaults.h"

extern TBUserDefaults  * gTbDefaults;

@interface AuthAgent()          // PRIVATE METHODS

-(NSString *)   configName;
-(void)         setConfigName:                      (NSString *)value;

-(void)         setPassphrase:                      (NSString *)value;

-(void)         setPassword:                        (NSString *)value;

-(void)         setUsername:                        (NSString *)value;

-(NSArray *)    getUsernameAndPassword;
-(void)         performPasswordAuthentication;
-(void)         performPrivateKeyAuthentication;

@end

@implementation AuthAgent

-(id) initWithConfigName:(NSString *)inConfigName
{
	if (inConfigName == nil) return nil;
    if (self = [super init]) {
        [self setConfigName:inConfigName];
        
        passphrase = nil;
        username   = nil;
        password   = nil;
        
        passphraseKeychain      = [[KeyChain alloc] initWithService:[@"Tunnelblick-Auth-" stringByAppendingString:[self configName]] withAccountName: @"privateKey" ];
        usernameKeychain        = [[KeyChain alloc] initWithService:[@"Tunnelblick-Auth-" stringByAppendingString:[self configName]] withAccountName: @"username"   ];
        passwordKeychain        = [[KeyChain alloc] initWithService:[@"Tunnelblick-Auth-" stringByAppendingString:[self configName]] withAccountName: @"password"   ];

        passphrasePreferenceKey = [[NSString alloc] initWithFormat:@"%@-keychainHasPrivateKey",             [self configName]   ];
        usernamePreferenceKey   = [[NSString alloc] initWithFormat:@"%@-keychainHasUsernameAndPassword",    [self configName]   ];
    }
    return self;
}

-(void) dealloc
{
    [configName                 release];
    
    [passphrase                 release];
    [username                   release];
    [password                   release];
    
    [passphraseKeychain         release];
    [usernameKeychain           release];
    [passwordKeychain           release];

    [passphrasePreferenceKey    release];
    [usernamePreferenceKey      release];

    [super dealloc];
}

// Returns non-zero length private key obtained by asking the user
// Returns nil if user cancelled or other error occured
-(NSString *)askForPrivateKey
{
    if (  ! [authMode isEqualToString:@"privateKey"]  ) {
        NSLog(@"Invalid authmode '%@' in askForPrivateKey", [self authMode]);
        return nil;
    }
    
    /* Dictionary for the panel.  */
    NSMutableDictionary* dict = [[NSMutableDictionary alloc] initWithCapacity:7];
    [dict setObject:[NSString stringWithFormat:@"%@: %@",
                     [self configName],
                     NSLocalizedString(@"Passphrase", @"Window title")]                 forKey:(NSString *)kCFUserNotificationAlertHeaderKey];
    [dict setObject:NSLocalizedString(@"Please enter VPN passphrase.", @"Window text")  forKey:(NSString *)kCFUserNotificationAlertMessageKey];
    if (  [gTbDefaults canChangeValueForKey: passphrasePreferenceKey]  ) {
        [dict setObject:NSLocalizedString(@"Save in Keychain", @"Checkbox text")            forKey:(NSString *)kCFUserNotificationCheckBoxTitlesKey];
    }
    [dict setObject:@""                                                                 forKey:(NSString *)kCFUserNotificationTextFieldTitlesKey];
    [dict setObject:NSLocalizedString(@"OK", @"Button")                                 forKey:(NSString *)kCFUserNotificationDefaultButtonTitleKey];
    [dict setObject:NSLocalizedString(@"Cancel", @"Button")                             forKey:(NSString *)kCFUserNotificationAlternateButtonTitleKey];
    [dict setObject:[NSURL fileURLWithPath:[[NSBundle mainBundle]
                                            pathForResource:@"tunnelblick"
                                            ofType: @"icns"]]                           forKey:(NSString *)kCFUserNotificationIconURLKey];
    
    NSString * passphraseLocal;

    SInt32 error;
    CFUserNotificationRef notification;
    CFOptionFlags response;
    
    // Get a non-blank passphrase from the user (or return nil if cancelled or error)
    BOOL firstTimeThrough = TRUE;
    do {
        if (  firstTimeThrough  ) {
            firstTimeThrough = FALSE;
        } else {
            CFRelease(notification);
            [dict removeObjectForKey: (NSString *)kCFUserNotificationAlertMessageKey];
            [dict setObject:NSLocalizedString(@"The passphrase must not be empty!\nPlease enter VPN passphrase.", @"Window text")
                     forKey:(NSString *)kCFUserNotificationAlertMessageKey];
        }

        notification = CFUserNotificationCreate(NULL, 30, CFUserNotificationSecureTextField(0), &error, (CFDictionaryRef)dict);

        if((error) || (CFUserNotificationReceiveResponse(notification, 0, &response))) {
            CFRelease(notification);    // Couldn't receive a response
            [dict release];
            return nil;
        }
        
        if((response & 0x3) != kCFUserNotificationDefaultResponse) {
            CFRelease(notification);    // User clicked "Cancel"
            [dict release];
            return nil;
        }

        // Get the passphrase from the textfield
        passphraseLocal = [[(NSString*)CFUserNotificationGetResponseValue(notification, kCFUserNotificationTextFieldValuesKey, 0) retain] autorelease];
    } while(  [passphraseLocal length] == 0  );
        
    if (  [gTbDefaults canChangeValueForKey: passphrasePreferenceKey]  ) {
        if((response & CFUserNotificationCheckBoxChecked(0))) {
            [passphraseKeychain deletePassword];
            if([passphraseKeychain setPassword:passphraseLocal] != 0) {
                NSLog(@"Could not store passphrase in Keychain");
            }
            [gTbDefaults setBool: YES forKey: passphrasePreferenceKey];
            [gTbDefaults synchronize];
        }
    }
    
    CFRelease(notification);
    [dict release];
    return passphraseLocal;
}

// Returns an array with a non-zero length username and a non-zero length password obtained either from the Keychain or by asking the user
// Returns nil if cancelled by user or error
-(NSArray *)getUsernameAndPassword
{
    if (  ! [authMode isEqualToString:@"password"]  ) {
        NSLog(@"Invalid authmode '%@' in getUsernameAndPassword", [self authMode]);
        return nil;
    }

    NSString * usernameLocal = nil;
    NSString * passwordLocal = nil;

    if (  [gTbDefaults boolForKey:usernamePreferenceKey] && [gTbDefaults canChangeValueForKey: usernamePreferenceKey]  ) { // Using this preference avoids accessing Keychain unless it has something
        usernameLocal= [usernameKeychain password]; // Get username and password from Keychain if they've been saved
        if ( usernameLocal ) {
            passwordLocal = [passwordKeychain password];    // Only try to get password if have username. Avoids second "OK to use Keychain? query if the user says 'no'
        }
    }
    
    if (    ! (  usernameLocal && passwordLocal && ([usernameLocal length] > 0) && ([passwordLocal length] > 0)  )    ) {
        // Ask for username and password

        NSMutableDictionary* dict = [[NSMutableDictionary alloc] initWithCapacity:7];
        [dict setObject:[NSString stringWithFormat:@"%@: %@",
                         [self configName],
                         NSLocalizedString(@"Username and password", @"Window title")]                          forKey:(NSString *)kCFUserNotificationAlertHeaderKey];
        [dict setObject:NSLocalizedString(@"Please enter VPN username/password combination.", @"Window text")   forKey:(NSString *)kCFUserNotificationAlertMessageKey];
        if (  [gTbDefaults canChangeValueForKey: usernamePreferenceKey]  ) {
            [dict setObject:NSLocalizedString(@"Save in Keychain", @"Checkbox text")                                forKey:(NSString *)kCFUserNotificationCheckBoxTitlesKey];
        }
        [dict setObject:[NSArray arrayWithObjects:NSLocalizedString(@"Username:", @"Textbox name"),
                         NSLocalizedString(@"Password:", @"Textbox name"),
                         nil]                                                                                   forKey:(NSString *)kCFUserNotificationTextFieldTitlesKey];
        [dict setObject:NSLocalizedString(@"OK", @"Button")                                                     forKey:(NSString *)kCFUserNotificationDefaultButtonTitleKey];
        [dict setObject:NSLocalizedString(@"Cancel", @"Button")                                                 forKey:(NSString *)kCFUserNotificationAlternateButtonTitleKey];
        [dict setObject:[NSURL fileURLWithPath:[[NSBundle mainBundle]
                                                pathForResource:@"tunnelblick"
                                                ofType: @"icns"]]                           forKey:(NSString *)kCFUserNotificationIconURLKey];
        
        SInt32 error;
        CFOptionFlags response;
        CFUserNotificationRef notification;
        
        // Get a non-blank username and a non-blank password from the user (or return nil if cancelled or error)
        BOOL firstTimeThrough = TRUE;
        do {
            if (  firstTimeThrough  ) {
                firstTimeThrough = FALSE;
            } else {
                CFRelease(notification);
                [dict removeObjectForKey: (NSString *)kCFUserNotificationAlertMessageKey];
                [dict setObject:NSLocalizedString(@"The username and the password must not be empty!\nPlease enter VPN username/password combination.", @"Window text")
                         forKey:(NSString *)kCFUserNotificationAlertMessageKey];
            }
            
            notification = CFUserNotificationCreate(NULL, 0, CFUserNotificationSecureTextField(1), &error, (CFDictionaryRef)dict);
            
            /* If we couldn't receive a response, return NULL. */
            if((error) || (CFUserNotificationReceiveResponse(notification, 0, &response))) {
                CFRelease(notification);
                [dict release];
                return nil;
            }
            
            if((response & 0x3) != kCFUserNotificationDefaultResponse) { //user clicked on cancel
                CFRelease(notification);
                [dict release];
                return nil;
            }
            
            /* Get the username and password from the textfield. */
            usernameLocal = [[(NSString*)CFUserNotificationGetResponseValue(notification, kCFUserNotificationTextFieldValuesKey, 0) retain] autorelease];
            passwordLocal = [[(NSString*)CFUserNotificationGetResponseValue(notification, kCFUserNotificationTextFieldValuesKey, 1) retain] autorelease];
        } while (  [usernameLocal isEqualToString:@""] || [passwordLocal isEqualToString:@""]  );
            
        if (  [gTbDefaults canChangeValueForKey: usernamePreferenceKey]  ) {
            if((response & CFUserNotificationCheckBoxChecked(0))) { // if checkbox is checked, store in keychain
                [usernameKeychain deletePassword];
                if (  [usernameKeychain setPassword:usernameLocal] != 0  ) {
                    NSLog(@"Could not save username in Keychain");
                }
                [passwordKeychain deletePassword];
                if (  [passwordKeychain setPassword:passwordLocal] != 0  ) {
                    NSLog(@"Could not save password in Keychain");
                }
                [gTbDefaults setBool: YES forKey: usernamePreferenceKey];
                [gTbDefaults synchronize];
            }
        }
            
        CFRelease(notification);
        [dict release];
    }

    NSArray * array = [NSArray arrayWithObjects: usernameLocal, passwordLocal, nil];
    return array;
}

-(void)performPasswordAuthentication
{
    [self setUsername:nil];
    [self setPassword:nil];

    if (  ! [authMode isEqualToString:@"password"]  ) {
        NSLog(@"Invalid authmode '%@' in performPasswordAuthentication", [self authMode]);
        return;
    }
    
	NSArray *authArray = [self getUsernameAndPassword];
	if([authArray count]) {                
		NSString *usernameLocal = [authArray objectAtIndex:0];
		NSString *passwordLocal = [authArray objectAtIndex:1];
		[self setUsername:usernameLocal];
		[self setPassword:passwordLocal];
	}
}
-(void)performPrivateKeyAuthentication
{
    if (  ! [authMode isEqualToString:@"privateKey"]  ) {
        NSLog(@"Invalid authmode '%@' in performPrivateKeyAuthentication", [self authMode]);
        return;
    }
    
    NSString *passphraseLocal = nil;
    if (  [gTbDefaults boolForKey:passphrasePreferenceKey] && [gTbDefaults canChangeValueForKey: passphrasePreferenceKey]  ) { // Get saved privateKey from Keychain if it has been saved
        passphraseLocal = [passphraseKeychain password];
    }
    
    if (passphraseLocal == nil) {
        passphraseLocal = [self askForPrivateKey];
    }
    [self setPassphrase:passphraseLocal];
}

-(void)performAuthentication
{
	if([[self authMode] isEqualToString:@"privateKey"]) {
		[self performPrivateKeyAuthentication];
	}
    else if([[self authMode] isEqualToString:@"password"]) {
        [self performPasswordAuthentication];
	}
    else {
        NSLog(@"Invalid authMode '%@' in performAuthentication", [self authMode]);
    }
}

-(void)deleteCredentialsFromKeychain 
{
    if (  [authMode isEqualToString: @"privateKey"]  ) {
        if (  [gTbDefaults boolForKey:passphrasePreferenceKey]  ) { // Delete saved privateKey from Keychain if it has been saved
            [passphraseKeychain deletePassword];
            [gTbDefaults removeObjectForKey: passphrasePreferenceKey];
            [gTbDefaults synchronize];
        }
    }
    else if (  [authMode isEqualToString: @"password"]  ) {
        if (  [gTbDefaults boolForKey:usernamePreferenceKey]  ) { // Delete saved username and password from Keychain if they've been saved
            [usernameKeychain deletePassword];
            [passwordKeychain deletePassword];
            [gTbDefaults removeObjectForKey: usernamePreferenceKey];
            [gTbDefaults synchronize];
        }
    }        
    else {
        NSLog(@"Invalid authMode '%@' in deleteCredentialsFromKeychain", [self authMode]);
    }
}

-(BOOL) keychainHasCredentials
{
    if (  [authMode isEqualToString: @"privateKey"]  ) {
        if (  [gTbDefaults boolForKey:passphrasePreferenceKey]  ) { // Get saved privateKey from Keychain if it has been saved
            NSString * passphraseLocal = [passphraseKeychain password];
            if (    passphraseLocal && ( [passphraseLocal length] > 0 )    ) {
                return YES;
            } else {
                return NO;
            }
        } else {
            return NO;
        }
    }
    else if (  [authMode isEqualToString: @"password"]  ) {
        if (  [gTbDefaults boolForKey:usernamePreferenceKey]  ) { // Get username and password from Keychain if they've been saved
            NSString * usernameLocal = [usernameKeychain password];
            NSString * passwordLocal = [passwordKeychain password];
            if (    usernameLocal && passwordLocal && ([usernameLocal length] > 0) && ([passwordLocal length] > 0)    ) {
                return YES;
            } else {
                return NO;
            }
        } else {
            return NO;
        }
    }

    NSLog(@"Invalid authMode '%@' in keychainHasCredentials", [self authMode]);
    return NO;
}

- (NSString *)authMode {
    return [[authMode retain] autorelease];
}

- (void)setAuthMode:(NSString *)value {
    if (authMode != value) {
        [authMode release];
        authMode = [value copy];
    }
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

@end
