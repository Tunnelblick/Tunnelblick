/*
 * Copyright 2010, 2011 Jonathan K. Bullard. All rights reserved.
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


/*  ConfigurationManager
 *
 *  This class manipulates configurations (.ovpn and .conf files and .tblk packages)
 *
 *  It has no class variables -- the path to one or more configuration files is specified
 *  as an input parameter for each method.
 *
 *  It takes care of protecting and unprotecting configurations and making shadow copies of them,
 *  and installing .tblk packages
 */

#import "defines.h"
#import "VPNConnection.h"

@interface ConfigurationManager : NSObject {

}

+(id)                       defaultManager;

-(void)                     addConfigurationGuide;

-(void)                     editConfigurationAtPath:    (NSString *)        thePath
                                      forConnection:    (VPNConnection *)   connection;

-(void)                     haveNoConfigurationsGuide;

-(NSMutableDictionary *)    getConfigurations;

-(NSString *)               getConfigurationToUse:      (NSString *)        cfgPath
                                            orAlt:      (NSString *)        altCfgPath;

-(NSString *)               makeTemporarySampleTblkWithName: (NSString *)   name
                                         andKey:        (NSString *)        key;

-(void)                     openDotTblkPackages:        (NSArray *)         filePaths
                                      usingAuth:        (AuthorizationRef)  authRef
                        skipConfirmationMessage:        (BOOL)              skipConfirmMsg
                              skipResultMessage:        (BOOL)              skipResultMsg;

-(NSString *)               parseConfigurationPath:     (NSString *)        cfgPath
                                     forConnection:     (VPNConnection *)   connection;

-(void)                     shareOrPrivatizeAtPath:     (NSString *)        path;

-(BOOL)                     unprotectConfigurationFile: (NSString *)        filePath;

-(BOOL)                     userCanEditConfiguration:   (NSString *)        filePath;
@end
