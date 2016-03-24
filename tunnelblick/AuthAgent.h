/*
 * Copyright 2005, 2006, 2007, 2008, 2009 Angelo Laub
 * Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2015, 2016. All rights reserved.
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

// TO USE an AuthAgent:
// 1. Create it via "initWithConfigName:"
// 2. Specify an authorization mode via "setAuth:"
// 3. Use "performAuthentication" to get credentials
// 4. Access the passphrase or username & password via their "getters"
//
// You may change the authorization mode at any time, but you then need to
// do a "performAuthentication" to get the appropriate credential(s) so that
// they will be returned by the "getters"

#import "defines.h"

@class KeyChain;
@class LoginWindowController;
@class PassphraseWindowController;

@interface AuthAgent : NSObject
{
    LoginWindowController * loginScreen;            // The window for logging into the VPN
    PassphraseWindowController * passphraseScreen;  // The window for logging into the VPN
    
    NSString * authMode;                    // Either @"privateKey" or @"password", depending on type of authentication desired
	NSString * displayName;                 // Name of configuration file (filename EXCLUDING the extension)
    NSString * group;						// nil or name of credentials group
    NSString * credentialsName;             // Name of a group, or the displayName if no group
	
    // Passphrase for "privateKey" authentication, username & password for "password" authentication
    // The appropriate ones are set by the performAuthentication method, and come either from the keychain, or from asking the user for them
	NSString * passphrase;
	NSString * password;
	NSString * username;

    // Keychains to access passphrase, username, and password, respectively, if they are stored in the Keychain
    // We create these at initialization of each AuthAgent, and keep them around for efficiency and to make the code easier
    KeyChain * passphraseKeychain;
    KeyChain * usernameKeychain;
    KeyChain * passwordKeychain;
    
    // These preferences have two functions:
    //      * If not forced, they are used by Tunnelblick to indicate that the corresponding item is stored in the Keychain. This allows Tunnelblick
    //                to avoid accessing the Keychain unnecessarily, since Keychain accesses can require user approval.
    //      * If they are forced (with any value), they prevent Tunnelblick from offerring to store the corresponding item in the Keychain.
    //
    // These are keys for the preferences.
    NSString * passphrasePreferenceKey;
    NSString * usernameAndPasswordPreferenceKey;
    NSString * usernamePreferenceKey;
    
    BOOL authenticationWasFromKeychain;     // Last performAuthentication data came from the Keychain
	BOOL showingLoginWindow;
	BOOL showingPassphraseWindow;
}

// PUBLIC METHODS:
// (Private method interfaces are in AuthAgent.m)

-(id)           initWithConfigName:                 (NSString *)inConfigName
				credentialsGroup:					(NSString *)inGroup;

-(void)         deleteCredentialsFromKeychainIncludingUsername: (BOOL) includeUsername;
-(void)         deletePassphrase;
-(void)         deletePassword;

-(BOOL)         keychainHasPassphrase;
-(BOOL)         keychainHasUsername;
-(BOOL)         keychainHasUsernameAndPassword;
-(BOOL)         keychainHasAnyCredentials;

-(void)         performAuthentication;

-(NSString *)   usernameFromKeychain;

TBPROPERTY(NSString *, authMode,        setAuthMode)
TBPROPERTY(NSString *, username,        setUsername)
TBPROPERTY(NSString *, password,        setPassword)
TBPROPERTY(NSString *, passphrase,      setPassphrase)

TBPROPERTY_READONLY(NSString *, displayName)
TBPROPERTY_READONLY(BOOL,       authenticationWasFromKeychain)
TBPROPERTY_READONLY(BOOL,       showingLoginWindow)
TBPROPERTY_READONLY(BOOL,       showingPassphraseWindow)


@end
