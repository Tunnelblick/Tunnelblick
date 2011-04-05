/*
 * Copyright 2005, 2006, 2007, 2008, 2009 Angelo Laub
 * Contributions by Jonathan K. Bullard Copyright 2009, 2010, 2011
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

#import "AuthAgent.h"
#import "helper.h"
#import "TBUserDefaults.h"
#import "LoginWindowController.h"
#import "PassphraseWindowController.h"

extern TBUserDefaults  * gTbDefaults;

@interface AuthAgent()          // PRIVATE METHODS

-(NSString *)   displayName;
-(void)         setDisplayName:                      (NSString *)value;

-(void)         setPassphrase:                      (NSString *)value;

-(void)         setPassword:                        (NSString *)value;

-(void)         setUsername:                        (NSString *)value;

-(void) setUsernameKeychain: (KeyChain *) newKeyChain;
-(void) setPasswordKeychain: (KeyChain *) newKeyChain;
-(void) setPassphrasePreferenceKey: (NSString *) newKey;
-(void) setUsernamePreferenceKey: (NSString *) newKey;

-(NSArray *)    getUsernameAndPassword;
-(void)         performPasswordAuthentication;
-(void)         performPrivateKeyAuthentication;

@end

@implementation AuthAgent

-(id) initWithConfigName:(NSString *)inConfigName
{
	if (inConfigName == nil) return nil;
    if (self = [super init]) {
        [self setDisplayName:inConfigName];
        
        passphrase = nil;
        username   = nil;
        password   = nil;
        
        passphraseKeychain      = [[KeyChain alloc] initWithService:[@"Tunnelblick-Auth-" stringByAppendingString:[self displayName]] withAccountName: @"privateKey" ];
        usernameKeychain        = [[KeyChain alloc] initWithService:[@"Tunnelblick-Auth-" stringByAppendingString:[self displayName]] withAccountName: @"username"   ];
        passwordKeychain        = [[KeyChain alloc] initWithService:[@"Tunnelblick-Auth-" stringByAppendingString:[self displayName]] withAccountName: @"password"   ];

        passphrasePreferenceKey = [[NSString alloc] initWithFormat:@"%@-keychainHasPrivateKey",             [self displayName]   ];
        usernamePreferenceKey   = [[NSString alloc] initWithFormat:@"%@-keychainHasUsernameAndPassword",    [self displayName]   ];
        
        usedUniversalCredentials = NO;
    }
    return self;
}

-(void) dealloc
{
    [[loginScreen window] close];
    
    [loginScreen                release];
    [displayName                release];
    
    [passphrase                 release];
    [username                   release];
    [password                   release];
    [authMode                   release];
    
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
    
    wasFromKeychain = FALSE;
    usedUniversalCredentials = NO;
    
    NSString * passphraseLocal;
    
    if (  ! passphraseScreen  ) {
        passphraseScreen = [[PassphraseWindowController alloc] initWithDelegate: self];
    } else {
        [passphraseScreen redisplay];
    }
    
    // Always clear the password
    [[passphraseScreen passphrase] setStringValue: @""];
    
    NSInteger result = [NSApp runModalForWindow: [passphraseScreen window]];
    
    if (   (result != NSRunStoppedResponse)
        && (result != NSRunAbortedResponse)  ) {
        NSLog(@"Unrecognized response %l from runModalForWindow ignored", (long) result);
    }
    
    if (  result != NSRunStoppedResponse  ) {
        [[passphraseScreen window] close];
        return nil;
    }
    
    passphraseLocal = [[passphraseScreen passphrase] stringValue];
    
    if (  [passphraseScreen saveInKeychain]  ) {
        if (  [gTbDefaults canChangeValueForKey: passphrasePreferenceKey]  ) {
            [passphraseKeychain deletePassword];
            if (  [passphraseKeychain setPassword: passphraseLocal] != 0  ) {
                NSLog(@"Could not store passphrase in Keychain");
            }
            [gTbDefaults setBool: YES forKey: passphrasePreferenceKey];
            [gTbDefaults synchronize];
        }
    }
    
    [[passphraseScreen window] close];

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

    if (   [gTbDefaults boolForKey:usernamePreferenceKey]
        && [gTbDefaults canChangeValueForKey: usernamePreferenceKey]  ) { // Using this preference avoids accessing Keychain unless it has something
        usernameLocal= [usernameKeychain password]; // Get username and password from Keychain if they've been saved
        if ( usernameLocal ) {
            passwordLocal = [passwordKeychain password];    // Only try to get password if have username. Avoids second "OK to use Keychain? query if the user says 'no'
        }
    }
    
    usedUniversalCredentials = NO;
    
    if (   usernameLocal
        && passwordLocal
        && ([usernameLocal length] > 0)
        && ([passwordLocal length] > 0)  ) {
        // Connection-specific credentials
        
    } else if (   [gTbDefaults boolForKey: @"keychainHasUniversalUsernameAndPassword"]  ) {
        // No connection-specific credentials, but universal credentials exist 
        [self setUsernameKeychain: [[KeyChain alloc] initWithService: @"Tunnelblick-AuthUniversal" withAccountName: @"username"]];
        [self setPasswordKeychain: [[KeyChain alloc] initWithService: @"Tunnelblick-AuthUniversal" withAccountName: @"password"]];
        [self setPassphrasePreferenceKey: [[NSString alloc] initWithFormat: @"%@-keychainHasPrivateKey", [self displayName]]];
        [self setUsernamePreferenceKey:   [[NSString alloc] initWithFormat: @"keychainHasUniversalUsernameAndPassword"]];
        usernameLocal= [usernameKeychain password]; // Get username and password from Keychain if they've been saved
        if ( usernameLocal ) {
            passwordLocal = [passwordKeychain password];    // Only try to get password if have username. Avoids second "OK to use Keychain? query if the user says 'no'
        }
        usedUniversalCredentials = YES;
    }
    if (   usernameLocal
        && passwordLocal
        && ([usernameLocal length] > 0)
        && ([passwordLocal length] > 0)  ) {
        
        wasFromKeychain = TRUE;
        
    } else {
        
        // Ask for username and password
        wasFromKeychain = FALSE;
        usedUniversalCredentials = NO;
        
        if (  ! loginScreen  ) {
            loginScreen = [[LoginWindowController alloc] initWithDelegate: self];
        } else {
            [loginScreen redisplay];
        }

        if (   usernameLocal
            && ([usernameLocal length] != 0)  ) {
            [[loginScreen username] setStringValue: usernameLocal];
        }

        // Always clear the password
        [[loginScreen password] setStringValue: @""];
        
        NSInteger result = [NSApp runModalForWindow: [loginScreen window]];
        
        if (   (result != NSRunStoppedResponse)
            && (result != NSRunAbortedResponse)  ) {
            NSLog(@"Unrecognized response %l from runModalForWindow ignored", (long) result);
        }
        
        if (  result != NSRunStoppedResponse  ) {
            [[loginScreen window] close];
            return nil;
        }

        usernameLocal = [[loginScreen username] stringValue];
        passwordLocal = [[loginScreen password] stringValue];
        
        if (  [loginScreen saveInKeychain]  ) {
            if (  [gTbDefaults canChangeValueForKey: usernamePreferenceKey]  ) {
                [usernameKeychain deletePassword];
                if (  [usernameKeychain setPassword: usernameLocal] != 0  ) {
                    NSLog(@"Could not save username in Keychain");
                }
                [passwordKeychain deletePassword];
                if (  [passwordKeychain setPassword: passwordLocal] != 0  ) {
                    NSLog(@"Could not save password in Keychain");
                }
                [gTbDefaults setBool: YES forKey: usernamePreferenceKey];
                [gTbDefaults synchronize];
            }
        }
        
        [[loginScreen window] close];
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
        wasFromKeychain = FALSE;
    } else {
        wasFromKeychain = TRUE;
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
- (NSString *)displayName {
    return [[displayName retain] autorelease];
}

- (void)setDisplayName:(NSString *)value {
    if (displayName != value) {
        [displayName release];
        displayName = [value copy];
    }
}

-(BOOL) authenticationWasFromKeychain {
    return wasFromKeychain;
}

-(BOOL) usedUniversalCredentials
{
    return usedUniversalCredentials;
}

-(void) setUsernameKeychain: (KeyChain *) newKeyChain
{
    if (  usernameKeychain != newKeyChain  ) {
        [usernameKeychain release];
        usernameKeychain = [newKeyChain retain];
    }
}

-(void) setPasswordKeychain: (KeyChain *) newKeyChain
{
    if (  passwordKeychain != newKeyChain  ) {
        [passwordKeychain release];
        passwordKeychain = [newKeyChain retain];
    }
}

-(void) setPassphrasePreferenceKey: (NSString *) newKey
{
    if (  passphrasePreferenceKey != newKey  ) {
        [passphrasePreferenceKey release];
        passphrasePreferenceKey = [newKey retain];
    }
}

-(void) setUsernamePreferenceKey: (NSString *) newKey
{
    if (  usernamePreferenceKey != newKey  ) {
        [usernamePreferenceKey release];
        usernamePreferenceKey = [newKey retain];
    }
}

@end
