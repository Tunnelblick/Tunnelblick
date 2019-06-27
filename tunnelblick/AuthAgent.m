/*
 * Copyright 2005, 2006, 2007, 2008, 2009 Angelo Laub
 * Contributions by Jonathan K. Bullard Copyright 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2019. All rights reserved.
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

#import "KeyChain.h"
#import "LoginWindowController.h"
#import "PassphraseWindowController.h"
#import "TBUserDefaults.h"
#import "VPNConnection.h"

extern TBUserDefaults  * gTbDefaults;

@interface AuthAgent()          // PRIVATE METHODS

-(NSString *)   displayName;
-(void)         setDisplayName:                (NSString *)value;

-(NSString *)   group;
-(void)         setGroup:                      (NSString *)value;

-(NSString *)   credentialsName;
-(void)         setCredentialsName:            (NSString *)value;

-(NSArray *)    getUsernameAndPassword;
-(void)         performPasswordAuthentication;
-(void)         performPrivateKeyAuthentication;

@end

@implementation AuthAgent

TBSYNTHESIZE_OBJECT(retain, NSString *, authMode,        setAuthMode)
TBSYNTHESIZE_OBJECT(retain, NSString *, username,        setUsername)
TBSYNTHESIZE_OBJECT(retain, NSString *, password,        setPassword)
TBSYNTHESIZE_OBJECT(retain, NSString *, passphrase,      setPassphrase)
TBSYNTHESIZE_OBJECT(retain, NSString *, displayName,     setDisplayName)
TBSYNTHESIZE_OBJECT(retain, NSString *, group,           setGroup)
TBSYNTHESIZE_OBJECT(retain, NSString *, credentialsName, setCredentialsName)

TBSYNTHESIZE_NONOBJECT_GET( BOOL,       authenticationWasFromKeychain)
TBSYNTHESIZE_NONOBJECT_GET( BOOL,       showingLoginWindow)
TBSYNTHESIZE_NONOBJECT_GET( BOOL,       showingPassphraseWindow)

-(id) initWithConfigName: (NSString *)inConfigName
		credentialsGroup: (NSString *)inGroup
{
	if (  ! inConfigName  ) return nil;
	
    if (  (self = [super init])  ) {
		
        passphrase = nil;
        username   = nil;
        password   = nil;
        
		NSString * allUseGroup = [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"];
		if (  allUseGroup  ) {
			inGroup = allUseGroup;
		}
		
        displayName = [inConfigName copy];
        group = [inGroup copy];
        
		NSString * prefix;
        if (  inGroup  ) {
			prefix = @"Tunnelblick-Auth-Group-";
            credentialsName = [group copy];
        } else {
			prefix = @"Tunnelblick-Auth-";
            credentialsName = [displayName copy];
        }
		
        passphraseKeychain      = [[KeyChain alloc] initWithService:[prefix stringByAppendingString:[self credentialsName]] withAccountName: @"privateKey" ];
        usernameKeychain        = [[KeyChain alloc] initWithService:[prefix stringByAppendingString:[self credentialsName]] withAccountName: @"username"   ];
        passwordKeychain        = [[KeyChain alloc] initWithService:[prefix stringByAppendingString:[self credentialsName]] withAccountName: @"password"   ];

		passphrasePreferenceKey            = [[NSString alloc] initWithFormat: @"%@-keychainHasPrivateKey",          [self credentialsName]];
        usernamePreferenceKey              = [[NSString alloc] initWithFormat: @"%@-keychainHasUsername",            [self credentialsName]];
        usernameAndPasswordPreferenceKey   = [[NSString alloc] initWithFormat: @"%@-keychainHasUsernameAndPassword", [self credentialsName]];
		
		showingLoginWindow      = FALSE;
		showingPassphraseWindow = FALSE;
    }
    return self;
}

-(void) dealloc
{
    [[loginScreen window]       close];
    [[passphraseScreen window]  close];
    
    [loginScreen                release]; loginScreen             = nil;
    [passphraseScreen           release]; passphraseScreen        = nil;
    [authMode                   release]; authMode                = nil;
    [displayName                release]; displayName             = nil;
    [group                      release]; group                   = nil;
    [credentialsName            release]; credentialsName         = nil;
    
    [passphrase                 release]; passphrase              = nil;
    [username                   release]; username                = nil;
    [password                   release]; password                = nil;
    
    [passphraseKeychain         release]; passphraseKeychain      = nil;
    [usernameKeychain           release]; usernameKeychain        = nil;
    [passwordKeychain           release]; passwordKeychain        = nil;

    [passphrasePreferenceKey    release]; passphrasePreferenceKey = nil;
    [usernamePreferenceKey      release]; usernameAndPasswordPreferenceKey   = nil;
    [usernameAndPasswordPreferenceKey release]; usernameAndPasswordPreferenceKey   = nil;

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
    
    authenticationWasFromKeychain = FALSE;
    
    NSString * passphraseLocal;
    
    if (  ! passphraseScreen  ) {
        passphraseScreen = [[PassphraseWindowController alloc] initWithDelegate: self];
    } else {
        [passphraseScreen redisplay];
    }
    
    // Always clear the passphrase
    [[passphraseScreen passphrase] setStringValue: @""];
    
	showingPassphraseWindow = TRUE;
    NSInteger result = [NSApp runModalForWindow: [passphraseScreen window]];
    showingPassphraseWindow = FALSE;
    
    if (   (result != NSRunStoppedResponse)
        && (result != NSRunAbortedResponse)  ) {
        NSLog(@"Unrecognized response %ld from runModalForWindow ignored", (long) result);
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
        }
    }
    
    [[passphraseScreen window] close];

    return passphraseLocal;
}

-(BOOL) usernameIsInKeychain {
    
    return (   (   [gTbDefaults boolForKey:usernameAndPasswordPreferenceKey]
                && [gTbDefaults canChangeValueForKey:usernameAndPasswordPreferenceKey])
            || (   [gTbDefaults boolForKey:usernamePreferenceKey]
                && [gTbDefaults canChangeValueForKey:usernamePreferenceKey]));
}

-(BOOL) passwordIsInKeychain {
    
    return (   [gTbDefaults boolForKey:usernameAndPasswordPreferenceKey]
            && [gTbDefaults canChangeValueForKey:usernameAndPasswordPreferenceKey] );
}

-(NSString *) usernameFromKeychain {
    
    if (  [self usernameIsInKeychain]  ) {
        return [usernameKeychain password];
    }
    
    return nil;
}

-(NSString *) passwordFromKeychain {

    if (  [self passwordIsInKeychain]  ) {
        return [passwordKeychain password];
    }

    return nil;
}

// Returns an array with a username and password obtained from the Keychain or by asking the user
// Returns nil if cancelled by user or error
-(NSArray *)getUsernameAndPassword
{
    if (  ! [authMode isEqualToString:@"password"]  ) {
        NSLog(@"Invalid authmode '%@' in getUsernameAndPassword", [self authMode]);
        return nil;
    }

    authenticationWasFromKeychain = TRUE;   // Assuming this
    
    NSString * usernameLocal = nil;
    NSString * passwordLocal = nil;

    if (  [self usernameIsInKeychain]  ) {
        usernameLocal = [usernameKeychain password];
		if (  ! usernameLocal  ) {
			NSLog(@"User did not allow access to the Keychain to get VPN username");
		} else if (  [usernameLocal isEqualToString: @""]  ) {
			[gTbDefaults removeObjectForKey: usernameAndPasswordPreferenceKey];
			[gTbDefaults removeObjectForKey: usernamePreferenceKey];
			NSLog(@"Keychain did not contain VPN username as expected; removed %@ and %@ preferences", usernamePreferenceKey, usernameAndPasswordPreferenceKey);
			usernameLocal = nil;
		}
    }
    if (  [self passwordIsInKeychain]  ) {
        passwordLocal = [passwordKeychain password];
        if (  ! passwordLocal  ) {
            NSLog(@"User did not allow access to the Keychain to get VPN password");
        } else if (  [passwordLocal isEqualToString: @""]  ) {
			[gTbDefaults removeObjectForKey: usernameAndPasswordPreferenceKey];
			NSLog(@"Keychain did not contain VPN password as expected; removed %@ preference", usernameAndPasswordPreferenceKey);
			passwordLocal = nil;
        }
    }

    NSString * key = [[self displayName] stringByAppendingString: @"-alwaysShowLoginWindow"];
    if (   (! passwordLocal)
        || (! usernameLocal)
        || [gTbDefaults boolForKey: key]  ) {
        
        // Ask for password and username

        authenticationWasFromKeychain = FALSE;
        
        if (  ! loginScreen  ) {
            loginScreen = [[LoginWindowController alloc] initWithDelegate: self];
		} else {
			[loginScreen redisplay];
		}
        
		showingLoginWindow = TRUE;
        NSInteger result = [NSApp runModalForWindow: [loginScreen window]];
		showingLoginWindow = FALSE;
        
        if (   (result != NSRunStoppedResponse)
            && (result != NSRunAbortedResponse)  ) {
            NSLog(@"Unrecognized response %ld from runModalForWindow ignored", (long) result);
        }
        
        if (  result != NSRunStoppedResponse  ) {
            [[loginScreen window] close];
            return nil;
        }

        usernameLocal = [[loginScreen username] stringValue];
        passwordLocal = [[loginScreen password] stringValue];
        
        if (  ! usernameLocal  ) {
            NSLog(@"username is nil for Keychain '%@'", [usernameKeychain description]);
            usernameLocal = @"";
        }
        if (  ! passwordLocal  ) {
            NSLog(@"password is nil for Keychain '%@'", [usernameKeychain description]);
            passwordLocal = @"";
        }
        
        if (   [loginScreen isSaveUsernameInKeychainChecked]  ) {
            
            if (   [loginScreen isSavePasswordInKeychainChecked]  ) {
                
                // Saving both username and password
                if (  [gTbDefaults canChangeValueForKey: usernameAndPasswordPreferenceKey]  ) {
                    [usernameKeychain deletePassword];
                    if (  [usernameKeychain setPassword: usernameLocal] != 0  ) {
                        NSLog(@"Could not save username in Keychain '%@'", [usernameKeychain description]);
                    }
                    [passwordKeychain deletePassword];
                    if (  [passwordKeychain setPassword: passwordLocal] != 0  ) {
                        NSLog(@"Could not save password in Keychain '%@'", [passwordKeychain description]);
                    }
                    [gTbDefaults setBool: YES forKey: usernameAndPasswordPreferenceKey];
                    [gTbDefaults removeObjectForKey:  usernamePreferenceKey];
                }
            } else {
                
                // Save only the username
                if (  [gTbDefaults canChangeValueForKey: usernamePreferenceKey]  ) {
                    [usernameKeychain deletePassword];
                    [passwordKeychain deletePassword];
                    if (  [usernameKeychain setPassword: usernameLocal] != 0  ) {
                        NSLog(@"Could not save username in Keychain '%@'", [usernameKeychain description]);
                    }
                    [gTbDefaults setBool: YES forKey: usernamePreferenceKey];
                    [gTbDefaults removeObjectForKey:  usernameAndPasswordPreferenceKey];
                }
            }
        } else {

            // Not saving username or password, so delete them
            if (  [gTbDefaults canChangeValueForKey: usernamePreferenceKey]  ) {
                [usernameKeychain deletePassword];
                [passwordKeychain deletePassword];
                [gTbDefaults removeObjectForKey: usernamePreferenceKey];
                [gTbDefaults removeObjectForKey: usernameAndPasswordPreferenceKey];
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
        if (  ! passphraseLocal  ) {
			NSLog(@"User did not allow access to the Keychain to get passphrase");
            [self setPassphrase: nil];
            return;
        }
    }
    
    if (  [passphraseLocal length] == 0  ) {
        [gTbDefaults removeObjectForKey: passphrasePreferenceKey];
        passphraseLocal = [self askForPrivateKey];
        authenticationWasFromKeychain = FALSE;
    } else {
        authenticationWasFromKeychain = TRUE;
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

-(BOOL)deleteCredentialsFromKeychainIncludingUsername:  (BOOL) includeUsername
{
    if (  [authMode isEqualToString: @"privateKey"]  ) {
        if (  [gTbDefaults boolForKey:passphrasePreferenceKey]  ) { // Delete saved privateKey from Keychain if it has been saved
            [passphraseKeychain deletePassword];
            [gTbDefaults removeObjectForKey: passphrasePreferenceKey];
        }
    }
    else if (  [authMode isEqualToString: @"password"]  ) {
        if (  includeUsername  ) {
            if (   [gTbDefaults boolForKey: usernamePreferenceKey]
                || [gTbDefaults boolForKey: usernameAndPasswordPreferenceKey]  ) { // Delete saved username and password from Keychain if they've been saved
                [usernameKeychain deletePassword];
                [passwordKeychain deletePassword];
                [gTbDefaults removeObjectForKey: usernamePreferenceKey];
                [gTbDefaults removeObjectForKey: usernameAndPasswordPreferenceKey];
            }
        }
        if (   [gTbDefaults boolForKey: usernameAndPasswordPreferenceKey]  ) {      // Delete saved password from Keychain if it has been saved
            [passwordKeychain deletePassword];
            [gTbDefaults removeObjectForKey:  usernameAndPasswordPreferenceKey];    // and indicate that only the username is saved
            [gTbDefaults setBool: YES forKey: usernamePreferenceKey];
        }
    }
    else {
        NSLog(@"Invalid authMode '%@' in deleteCredentialsFromKeychainIncludingUsername:", [self authMode]);
		return NO;
    }

	return YES;
}

-(void) deletePassphrase {
    
    if (  [gTbDefaults boolForKey:passphrasePreferenceKey]  ) {                 // Delete saved privateKey from Keychain if it has been saved
        [passphraseKeychain deletePassword];
        [gTbDefaults removeObjectForKey: passphrasePreferenceKey];
    }
}

-(void) deletePassword {
    
    if (   [gTbDefaults boolForKey: usernameAndPasswordPreferenceKey]  ) {      // Delete saved password from Keychain if it has been saved
        [passwordKeychain deletePassword];
        [gTbDefaults removeObjectForKey:  usernameAndPasswordPreferenceKey];    // and indicate that only the username is saved
        [gTbDefaults setBool: YES forKey: usernamePreferenceKey];
    }
}

-(BOOL) saveUsername: (NSString *) theUsername {

	[usernameKeychain setPassword: theUsername];
	if (  ! [gTbDefaults boolForKey: usernameAndPasswordPreferenceKey]  ) {
		[gTbDefaults setBool: YES forKey: usernamePreferenceKey];
	}

	return YES;
}

-(BOOL) savePassword: (NSString *) thePassword {

	if (   [gTbDefaults boolForKey: usernamePreferenceKey]
		|| [gTbDefaults boolForKey: usernameAndPasswordPreferenceKey]  ) {
		[passwordKeychain setPassword: thePassword];
		if (   [gTbDefaults boolForKey: usernamePreferenceKey]  ) {
			[gTbDefaults removeObjectForKey: usernamePreferenceKey];
		}

		[gTbDefaults setBool: YES forKey: usernameAndPasswordPreferenceKey];
		return YES;
	}

	NSLog(@"Attempt to save password for %@ ignored because the username has not been set", displayName);
	return NO;
}

-(BOOL) savePassphrase: (NSString *) thePassphrase {

	[passphraseKeychain setPassword: thePassphrase];
	[gTbDefaults setBool: YES forKey: passphrasePreferenceKey];
	return YES;
}

-(BOOL) keychainHasPassphrase
{
	return [gTbDefaults boolForKey: passphrasePreferenceKey];
}

-(BOOL) keychainHasUsername
{
	return [gTbDefaults boolForKey: usernamePreferenceKey];
}

-(BOOL) keychainHasUsernameAndPassword
{
	return [gTbDefaults boolForKey: usernameAndPasswordPreferenceKey];
}

-(BOOL) keychainHasAnyCredentials
{
    if (  [authMode isEqualToString: @"privateKey"]  ) {
        return [gTbDefaults boolForKey: passphrasePreferenceKey];
	}
	
    if (  [authMode isEqualToString: @"password"]  ) {
        return (   [gTbDefaults boolForKey: usernamePreferenceKey]
				|| [gTbDefaults boolForKey: usernameAndPasswordPreferenceKey]  );
	}
	
    NSLog(@"Invalid authMode '%@' in keychainHasAnyCredentials", [self authMode]);
    return NO;
}

@end
