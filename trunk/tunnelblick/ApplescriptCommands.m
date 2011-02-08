/*
 * Copyright 2011 Jonathan Bullard
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
#import "MenuController.h"
#import "VPNConnection.h"
#import "TBUserDefaults.h"

extern TBUserDefaults  * gTbDefaults;


@implementation ApplescriptConnect

- (id)performDefaultImplementation
{
    NSString * displayName = [self directParameter];
    
    NSDictionary * myVPNConnectionDictionary = [[NSApp delegate] myVPNConnectionDictionary];
    VPNConnection * connection = [myVPNConnectionDictionary objectForKey: displayName];
    
    if (  connection  ) {
        if (  ! [connection isConnected] ) {
            [connection connect: self userKnows: YES];
            return [NSNumber numberWithBool: TRUE];
        }
    }
    
    return [NSNumber numberWithBool: FALSE];
}
@end


@implementation ApplescriptDisconnect

- (id)performDefaultImplementation
{
    NSString * displayName = [self directParameter];
    
    NSDictionary * myVPNConnectionDictionary = [[NSApp delegate] myVPNConnectionDictionary];
    VPNConnection * connection = [myVPNConnectionDictionary objectForKey: displayName];
    
    if (  connection  ) {
        if (  ! [connection isDisconnected]  ) {
            [connection disconnectAndWait: [NSNumber numberWithBool: NO] userKnows: YES];
            return [NSNumber numberWithBool: TRUE];
        }
    }
    
    return [NSNumber numberWithBool: FALSE];
}

@end


@implementation ApplescriptConnectAll

- (id)performDefaultImplementation
{
    NSDictionary * myVPNConnectionDictionary = [[NSApp delegate] myVPNConnectionDictionary];
    NSEnumerator * connEnum = [myVPNConnectionDictionary objectEnumerator];
    VPNConnection * connection;
    int nConnecting = 0;
    while (  connection = [connEnum nextObject]  ) {
        if (  ! [connection isConnected]  ) {
            [connection connect: self userKnows: NO];
            nConnecting++;
        }
    }
    
    return [NSNumber numberWithInt: nConnecting];
}

@end


@implementation ApplescriptDisconnectAll

- (id)performDefaultImplementation
{
    NSDictionary * myVPNConnectionDictionary = [[NSApp delegate] myVPNConnectionDictionary];
    NSEnumerator * connEnum = [myVPNConnectionDictionary objectEnumerator];
    VPNConnection * connection;
    int nDisconnecting = 0;
    while (  connection = [connEnum nextObject]  ) {
        if (  ! [connection isDisconnected]  ) {
            [connection disconnectAndWait: [NSNumber numberWithBool: NO] userKnows: NO];
            nDisconnecting++;
        }
    }
    
    return [NSNumber numberWithInt: nDisconnecting];
}

@end


@implementation ApplescriptDisconnectAllBut

- (id)performDefaultImplementation
{
    NSDictionary * myVPNConnectionDictionary = [[NSApp delegate] myVPNConnectionDictionary];
    NSEnumerator * connEnum = [myVPNConnectionDictionary objectEnumerator];
    VPNConnection * connection;
    int nDisconnecting = 0;
    while (  connection = [connEnum nextObject]  ) {
        if (  ! [connection isDisconnected]  ) {
            NSString* autoConnectkey = [[connection displayName] stringByAppendingString: @"autoConnect"];
            NSString* systemStartkey = [[connection displayName] stringByAppendingString: @"-onSystemStart"];
            if (  ! (   [gTbDefaults boolForKey: autoConnectkey]
                     && [gTbDefaults boolForKey: systemStartkey] )  ) {
                [connection disconnectAndWait: [NSNumber numberWithBool: NO] userKnows: NO];
                nDisconnecting++;
            }
        }
    }
    
    return [NSNumber numberWithInt: nDisconnecting];
}

@end
