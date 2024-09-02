/*
 * Copyright by Jonathan K. Bullard Copyright 2024. All rights reserved.
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

// Provides instance methods to access information about a Tunnelblick.app,
// the system, and the user.


#import "defines.h"


NS_ASSUME_NONNULL_BEGIN

@interface TunnelblickInfo : NSObject {

    NSString * appPath;

    NSDictionary * infoDictionary;
    
    NSString * tunnelblickBuildString;
    NSString * tunnelblickVersionString;

    NSArray  * allOpenvpnOpenssslVersions;
    NSString * defaultOpenvpnOpensslVersion;
    NSString * latestOpenvpnOpensslVersion;

    NSString * updateFeedURLString;
    NSString * updatePublicDSAKey;

    NSString * ipCheckURLString;

    NSString * systemVersionString;

    NSArray  * systemSounds;

    NSNumber * runningOnMacOSBeta;

    NSNumber * runningOnOCLP;

    NSNumber * userIsAnAdmin;
}

-(TunnelblickInfo *) initForAppAtPath: (nullable NSString *) path;

// INFO ABOUT TUNNELBLICK.APP

-(NSString *) appPath;

-(NSDictionary *) infoDictionary;

-(NSString *) tunnelblickBuildString;
-(NSString *) tunnelblickVersionString;

-(NSArray *) allOpenvpnOpenssslVersions;
-(NSString *) defaultOpenvpnOpensslVersion;
-(NSString *) latestOpenvpnOpensslVersion;

// INFO ABOUT TUNNELBLICK.APP which might be overridden by a forced preference

-(NSString *) updateFeedURLString;
-(NSString *) updatePublicDSAKey;

-(NSString *) ipCheckURLString;

// INFO ABOUT THE SYSTEM

-(NSString *) systemVersionString;

-(NSArray *) systemSounds;

-(BOOL) runningOnMacOSBeta;

-(BOOL) runningOnOCLP;

// INFO ABOUT THE USER

-(BOOL) userIsAnAdmin;

@end

NS_ASSUME_NONNULL_END
