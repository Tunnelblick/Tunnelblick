/*
 * Copyright 2026 Jonathan K. Bullard. All rights reserved.
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
 *  distribution); if not, see http://www.gnu.org/licenses/.
 */

#import <Foundation/Foundation.h>

NSString * managementPasswordFilePathInDirectory(NSString * directory, NSString * configName);

// Returns YES if the file was written, or if there was nothing to write.
// Returns NO if a write was attempted and failed.
BOOL writeManagementPasswordFileInDirectory(NSString * directory, NSString * configName, NSString * contents);

// argv is atsystemstart's argv: [1]=0|1, [2]=start, [3]=config, last=password.
BOOL writeManagementPasswordFileFromAtsystemstartArgs(int argc, char * argv[], NSString * directory);

BOOL connectOnSystemStartSetupIsComplete(BOOL plistMatches, BOOL mipExists);
