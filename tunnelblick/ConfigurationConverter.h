/*
 * Copyright 2012 Jonathan K. Bullard. All rights reserved.
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


/*  ConfigurationConverter
 *
 *  This class converts OpenVPN configurations (.ovpn and .conf files) to Tunnelblick VPN Configurations (.tblk packages)
 */

#import <Cocoa/Cocoa.h>
#import "defines.h"

@interface ConfigurationConverter : NSObject {

	NSString        * outputPath;           // Path to output .tblk to be created or nil to not create a .tblk or copy files
	NSString        * configPath;           // Path to .ovpn or .conf file to be converted
	FILE            * logFile;              // Log FILE
    BOOL              includePathNameInLog; // Whether or not to include the path name in log entries
    
	NSMutableString * configString;         // String containing contents of input configuration file (modified as we do processing)
    
    NSMutableArray  * tokens;               // Array of ConfigurationTokens
    
    NSMutableArray  * tokensToReplace;      // Array of ranges (actually of ConfigurationTokens) to be replaced by new strings in configString
    NSMutableArray  * replacementStrings;   // Array of strings to replace the ranges in configString

	unsigned          inputLineNumber;		// Line number we are parsing in the configuration file
	unsigned          inputIx;				// Index of current parse point in configString
}

-(BOOL) convertConfigPath: (NSString *) theConfigPath
               outputPath: (NSString *) theOutputPath
                  logFile: (FILE *)     theLogFile
     includePathNameInLog: (BOOL)       includePathNameInLog;

@end
