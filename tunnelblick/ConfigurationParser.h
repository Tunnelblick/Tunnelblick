/*
 * Copyright 2025 Jonathan K. Bullard. All rights reserved.
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


/*  ConfigurationParser
 *
 *  This class parses and searches OpenVPN configuration files
 */

#import <Foundation/Foundation.h>

#import "defines.h"

@class VPNConnection;


@interface ConfigurationParser : NSObject {

    NSArray * lines;    // Array of arrays, each of which contain the tokens for a line in the OpenVPN configuration file
}

+(ConfigurationParser *) parsedConfigurationForConnection: (VPNConnection *) connection;

+(ConfigurationParser *) parsedConfigurationAtPath: (NSString *) path;

-(BOOL) doesNotContainAnyUnsafeOptions;

-(BOOL) containsDnsScript;
-(BOOL) containsDnsUpdownForce;
-(BOOL) containsDnsUpdownDisable;
-(BOOL) containsDnsUpdownCommand;

@end
