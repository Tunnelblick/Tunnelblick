/*
 * Copyright 2012, 2013, 2014, 2016 Jonathan K. Bullard. All rights reserved.
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

#import <Foundation/Foundation.h>

#import "defines.h"

#import "ConfigurationManager.h"

@interface ConfigurationConverter : NSObject {

	NSString        * outputPath;           // Path to output .tblk to be created or nil to not create a .tblk or copy files
	NSString        * configPath;           // Path to .ovpn or .conf file to be converted
	NSString        * replacingTblkPath;    // Path to the .tblk that this configuration will be replacing (must be a path to a private config or nil)
    NSString        * displayName;          // Display name of the output .tblk
	NSString        * nameForErrorMessages; // nil or displayName or path to use in localized error messages presented to the user
    NSArray *         useExistingFiles;     // If a file is missing and this install is replacing a configuration and the filename is on this list, use the file from the old configuration
    FILE            * logFile;              // Log FILE
	BOOL              fromTblk;				// Include sibling files and files in sibling folders (i.e., config path is in a .tblk
    

	NSMutableString * logString;			// Contains a copy of log entries
	NSMutableString * localizedLogString;	// Contains a copy of log entries that have been localized
	
	NSMutableString * configString;         // String containing contents of input configuration file (modified as we do processing)
    
    NSMutableArray  * tokens;               // Array of ConfigurationTokens
    
    NSMutableArray  * tokensToReplace;      // Array of ranges (actually of ConfigurationTokens, which each contain a range) to be replaced by new strings in configString
    NSMutableArray  * replacementStrings;   // Array of strings to replace the ranges in configString
    NSMutableArray  * linesToCommentOut;    // Array of NSNumbers in configString that should be comment out because they contain a "status", "write-pid", or "replay-persist" option
    
	NSMutableArray  * pathsAlreadyCopied;	// Array of paths of files that have already been copied

	unsigned          inputLineNumber;		// Line number we are parsing in the configuration file
	unsigned          inputIx;				// Index of current parse point in configString
}

-(NSString *) convertConfigPath: (NSString *) theConfigPath
					 outputPath: (NSString *) theOutputPath
              replacingTblkPath: (NSString *) theReplacingTblkPath
                    displayName: (NSString *) theDisplayName
		   nameForErrorMessages: (NSString *) theNameForErrorMessages
               useExistingFiles: (NSArray *)  theUseExistingFiles
						logFile: (FILE *)     theLogFile
					   fromTblk: (BOOL)       theFromTblk;


-(CommandOptionsStatus) commandOptionsStatusForOpenvpnConfigurationAtPath: (NSString *) path
                                                                 fromTblk: (NSString *) theFromTblk;

@end
