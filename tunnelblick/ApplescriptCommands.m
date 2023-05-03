/*
 * Copyright 2011, 2012, 2013, 2014, 2019, 2020, 2023 Jonathan K. Bullard. All rights reserved.
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


#import "ApplescriptCommands.h"

#import "AuthAgent.h"
#import "ConfigurationManager.h"
#import "MenuController.h"
#import "TBUserDefaults.h"
#import "VPNConnection.h"

extern NSFileManager   * gFileMgr;
extern MenuController  * gMC;
extern TBUserDefaults  * gTbDefaults;


@implementation ApplescriptConnect

- (id)performDefaultImplementation
{
    NSString * displayName = [self directParameter];
    
    VPNConnection * connection = [gMC connectionForDisplayName: displayName];
    
    if (  connection  ) {
        if (  ! [connection isConnected] ) {
            [connection connect: self userKnows: YES];
            return @YES;
        }
    }
    
    return @NO;
}
@end


@implementation ApplescriptDisconnect

- (id)performDefaultImplementation
{
    NSString * displayName = [self directParameter];
    
    VPNConnection * connection = [gMC connectionForDisplayName: displayName];

    if (  connection  ) {
        if (  ! [connection isDisconnected]  ) {
            [connection addToLog: @"Disconnecting; AppleScript 'disconnect' invoked"];
            [connection performSelectorOnMainThread: @selector(startDisconnectingUserKnows:) withObject: @YES waitUntilDone: NO];
            return @YES;
        }
    }
    
    return @NO;
}

@end


@implementation ApplescriptConnectAll

- (id)performDefaultImplementation
{
    NSDictionary * myVPNConnectionDictionary = [gMC myVPNConnectionDictionary];
    NSEnumerator * connEnum = [myVPNConnectionDictionary objectEnumerator];
    VPNConnection * connection;
    int nConnecting = 0;
    while (  (connection = [connEnum nextObject])  ) {
        if (  ! [connection isConnected]  ) {
            [connection connect: self userKnows: YES];
            nConnecting++;
        }
    }
    
    return [NSNumber numberWithInt: nConnecting];
}

@end


@implementation ApplescriptDisconnectAll

- (id)performDefaultImplementation
{
    NSDictionary * myVPNConnectionDictionary = [gMC myVPNConnectionDictionary];
    NSEnumerator * connEnum = [myVPNConnectionDictionary objectEnumerator];
    VPNConnection * connection;
    int nDisconnecting = 0;
    while (  (connection = [connEnum nextObject])  ) {
        if (  ! [connection isDisconnected]  ) {
            [connection addToLog: @"Disconnecting; AppleScript 'disconnect all' invoked"];
            [connection performSelectorOnMainThread: @selector(startDisconnectingUserKnows:) withObject: @YES waitUntilDone: NO];
            nDisconnecting++;
        }
    }
    
    return [NSNumber numberWithInt: nDisconnecting];
}

@end


@implementation ApplescriptDisconnectAllBut

- (id)performDefaultImplementation
{
    NSDictionary * myVPNConnectionDictionary = [gMC myVPNConnectionDictionary];
    NSEnumerator * connEnum = [myVPNConnectionDictionary objectEnumerator];
    VPNConnection * connection;
    int nDisconnecting = 0;
    while (  (connection = [connEnum nextObject])  ) {
        if (  ! [connection isDisconnected]  ) {
            NSString* autoConnectkey = [[connection displayName] stringByAppendingString: @"autoConnect"];
            NSString* systemStartkey = [[connection displayName] stringByAppendingString: @"-onSystemStart"];
            if (  ! (   [gTbDefaults boolForKey: autoConnectkey]
                     && [gTbDefaults boolForKey: systemStartkey] )  ) {
                [connection addToLog:@"Disconnecting; AppleScript 'disconnect all except when computer starts' invoked"];
                [connection performSelectorOnMainThread: @selector(startDisconnectingUserKnows:) withObject: @NO waitUntilDone: NO];
                nDisconnecting++;
            }
        }
    }
    
    return [NSNumber numberWithInt: nDisconnecting];
}

@end


@implementation ApplescriptQuit

- (id)performDefaultImplementation
{
    [gMC performSelectorOnMainThread: @selector(quit:) withObject: nil waitUntilDone: NO];
    return [NSNumber numberWithInt: 0];
}

@end


@implementation ApplescriptHaveChangedOpenvpnConfigurationFileFor

- (id)performDefaultImplementation {
	
	NSString * displayName = [self directParameter];
	
	[gMC openvpnConfigurationFileChangedForDisplayName: displayName];
	return [NSNumber numberWithInt: 0];
}

@end


@implementation ApplescriptHaveAddedAndOrRemovedOneOrMoreConfigurations

- (id)performDefaultImplementation {
	
	[gMC updateMenuAndDetailsWindowForceLeftNavigation: YES];
	return [NSNumber numberWithInt: 0];
}

@end


@implementation ApplescriptSaveUsername

- (id)performDefaultImplementation
{
	NSString * username = [self directParameter];

	NSDictionary * evaluatedArguments = [self evaluatedArguments];
	NSString * displayName = [evaluatedArguments objectForKey: @"for"];
	VPNConnection * connection = [gMC connectionForDisplayName: displayName];
	AuthAgent * authAgent = [connection authAgent];

	if (  authAgent  ) {
		BOOL ok = [authAgent saveUsername: username];
		return [NSNumber numberWithBool: ok];
	}

	return @NO;
}

@end


@implementation ApplescriptSavePassword

- (id)performDefaultImplementation
{
	NSString * password = [self directParameter];

	NSDictionary * evaluatedArguments = [self evaluatedArguments];
	NSString * displayName = [evaluatedArguments objectForKey: @"for"];
    VPNConnection * connection = [gMC connectionForDisplayName: displayName];
	AuthAgent * authAgent = [connection authAgent];

	if (  authAgent  ) {
		BOOL ok = [authAgent savePassword: password];
		return [NSNumber numberWithBool: ok];
	}

	NSLog(@"");
	return @NO;
}

@end

@implementation ApplescriptSavePassphrase

- (id)performDefaultImplementation
{
	NSString * passphrase = [self directParameter];

	NSDictionary * evaluatedArguments = [self evaluatedArguments];
	NSString * displayName = [evaluatedArguments objectForKey: @"for"];
    VPNConnection * connection = [gMC connectionForDisplayName: displayName];

	AuthAgent * authAgent = [connection authAgent];

	if (  authAgent  ) {
		BOOL ok = [authAgent savePassphrase: passphrase];
		return [NSNumber numberWithBool: ok];
	}

	return @NO;
}

@end

@implementation ApplescriptDeleteAllCredentials

- (id)performDefaultImplementation
{
	NSString * displayName = [self directParameter];

    VPNConnection * connection = [gMC connectionForDisplayName: displayName];
	AuthAgent * authAgent = [connection authAgent];

	if (  authAgent  ) {
		[authAgent deletePassphrase];
		[authAgent setAuthMode: @"password"];
		BOOL ok = [authAgent deleteCredentialsFromKeychainIncludingUsername: YES];
		return [NSNumber numberWithBool: ok];
	}

	return @NO;
}

@end

@implementation ApplescriptInstallPrivateConfigurations

- (id)performDefaultImplementation
{
    NSAppleEventDescriptor * listDescriptor = self.directParameter;
    if (  listDescriptor.descriptorType != typeAEList  ) {
        NSLog(@"install private configurations: Argument must be a list of strings with POSIX paths");
        return [NSNumber numberWithBool: FALSE];
    }

    NSInteger numberOfItems = listDescriptor.numberOfItems;
    if (  numberOfItems == 0  ) {
        NSLog(@"install private configurations: Nothing to install");
        return [NSNumber numberWithBool: FALSE];
    }

    NSMutableArray * paths = [NSMutableArray arrayWithCapacity: numberOfItems];

    for (  NSInteger i=1; i<=numberOfItems; i++  ) {

        NSAppleEventDescriptor * itemDescriptor = [listDescriptor descriptorAtIndex: i];
        NSString * path = itemDescriptor.stringValue;
        if (  path == nil  ) {
            NSLog(@"install private configurations: All entries in the argument list must be strings.");
            return [NSNumber numberWithBool: FALSE];
        }

        if (   [path.pathExtension isEqualToString: @"ovpn"]
            || [path.pathExtension isEqualToString: @"tblk"]  ) {
            if (  ! [gFileMgr fileExistsAtPath: path]  ) {
                NSLog(@"install private configurations: No .tblk or .ovpn at %@", path);
                return [NSNumber numberWithBool: FALSE];
            }
        } else {
            NSLog(@"install private configurations: Unknown extension (not .tblk or .ovpn): %@", path);
            return [NSNumber numberWithBool: FALSE];
        }

        [paths addObject: path];
    }

    BOOL result = [ConfigurationManager InstallPrivateConfigurations: paths];

    if (  result  ) {
        [gMC updateMenuAndDetailsWindowForceLeftNavigation: YES];
    }

    return [NSNumber numberWithBool: result];
}

@end
