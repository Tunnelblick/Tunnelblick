/*
 * Copyright 2018 Jonathan K. Bullard. All rights reserved.
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

/*  SetupImporter
 *
 *  This class imports data from a .tblkSetup
 *
 */

#import "SetupImporter.h"

#import "helper.h"
#import "sharedRoutines.h"

#import "ImportWindowController.h"
#import "MenuController.h"
#import "SystemAuth.h"

extern NSFileManager * gFileMgr;

@implementation SetupImporter

-(SetupImporter *) initWithTblkSetupFiles: (NSArray *) files {
	
	if (   ([files count] != 1)
		|| [[(tblkSetupPath = [[files firstObject] retain]) pathExtension] isNotEqualTo: @"tblkSetup"]
		|| ( ! [gFileMgr fileExistsAtPath: tblkSetupPath] )  ) {
		NSLog(@"Error: ConfigurationManager/importTunnelblickSetup not invoked with only one .tblkSetup file which exists: %@", files);
		return nil;
	}
	
	return self;
}

-(void) dealloc {
	
	[tblkSetupPath        release];
	[usernameMap          release];
	[usersInThisTblkSetup release];
	[usersOnThisComputer  release];
	[windowController     release];

	[super dealloc];
}

-(BOOL) import {
	
	// If we don't have usernameMap, get one
	if ( ! usernameMap  ) {
		
		// If there is a username-mapping.txt file, use it, otherwise, query the user
		NSString * usernameMapPath = [tblkSetupPath stringByAppendingPathComponent: @"username-map.txt"];
		if (  [gFileMgr fileExistsAtPath: usernameMapPath]  ) {
			
			NSData * usernameMapData = [gFileMgr contentsAtPath: usernameMapPath];
			if (  ! usernameMapData  ) {
				NSLog(@"Unable to read %@", usernameMapPath);
				return NO;
			}
			NSString * usernameMapString = [[[NSString alloc] initWithData: usernameMapData encoding: NSUTF8StringEncoding] autorelease];
			if (  ! usernameMapString  ) {
				NSLog(@"Unable to read as UTF-8: %@", usernameMapPath);
				return NO;
			}
			
			usernameMap = [[self normalizeUsernameMapString: usernameMapString from: usernameMapPath] retain];
			if (  ! usernameMap  ) {
				return NO;
			}
			
		} else if (  [[self usersOnThisComputer] count] <= MAX_NUMBER_OF_TARGET_USERNAMES_FOR_IMPORT_WINDOW  ) {
			
			windowController = [[ImportWindowController alloc] init];
			[windowController setSourceUsernames: [self usersInThisTblkSetup]];
			[windowController setTargetUsernames: [self usersOnThisComputer]];
			[windowController setMappingStringTarget: self selector: @selector(importOKButtonWasClicked:)];
			[windowController showWindow: nil];
			[[windowController window] makeKeyAndOrderFront: self];
			
			// Return now without starting the import; this "import" method will be invoked again
			// (by importOKButtonWasClicked:) with usernameMap set if the user sets up mappings and clicks "OK".
			return YES; // We've accepted the input (although the user may cancel)
			
		} else {
			
			TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
							  attributedStringFromHTML([NSString stringWithFormat:
														NSLocalizedString(@"<font face=\"Helvetica,Arial,sans-serif\">"
																		  @"<p>To import a Tunnelblick setup on a computer that has more than %u user accounts, you must create"
																		  @" a text file that specifies the data to be imported.</p>\n"
																		  @"<p>For more information, see <a href=\"https://tunnelblick.net/cExportingAndImportingTunnelblickSetups.html\">https://tunnelblick.net/cExportingAndImportingTunnelblickSetups.html</a>.</p>"
																		  @"</font>",
																		  @"HTML error message. The  '%u' will be replaced a number such as '32'."),
														MAX_NUMBER_OF_TARGET_USERNAMES_FOR_IMPORT_WINDOW]));
			return  NO;
		}
	}
	
	NSArray * installerArguments = @[tblkSetupPath, usernameMap];
	
	NSString * message = NSLocalizedString(@"Tunnelblick needs authorization to secure the imported data.", @"Window text");
	SystemAuth * auth = [[SystemAuth newAuthWithPrompt: message] autorelease];
	if (  auth  ) {
		NSInteger result = [((MenuController *)[NSApp delegate]) runInstaller: INSTALLER_IMPORT
															   extraArguments: installerArguments
															  usingSystemAuth: auth
																 installTblks: nil];
		if (  result != 0  ) {
			[self notifyAboutImportProblem: [NSString stringWithFormat: @"Error while importing %@", tblkSetupPath]];
			return NO;
		}
		
		return YES;
	}
	
	return NO;
}

-(void) importOKButtonWasClicked: (NSString *) mappingString {
	
	usernameMap = [[self normalizeUsernameMapString: mappingString from: @"User input"] retain];
	if (  usernameMap  ) {
		[self import];
	}
}

-(NSString *) normalizeUsernameMapString: (NSString *) usernameMapString from: (NSString *) usernameMapPath {
	
	// Checks a usernameMap string and returns it normalized (omits blank lines and whitespace around names).
	// Returns nil if an error occurred.
	
	NSArray * sourceNames = [self usersInThisTblkSetup];
	NSArray * targetNames = [self usersOnThisComputer];
	
	NSMutableString * map = [[[NSMutableString alloc] initWithCapacity: 10000] autorelease];
	NSArray * usernameMapLines = [usernameMapString componentsSeparatedByString: @"\n"];
	NSUInteger lineNumber = 0;
	NSString * line;
	NSEnumerator * e = [usernameMapLines objectEnumerator];
	while (  (line = [e nextObject])  ) {
		
		lineNumber++;
		
		if (  [line length] == 0  ) {
			continue;
		}
		
		NSArray * names = [line componentsSeparatedByString: @":"];
		if (  [names count] != 2  ) {
			NSLog(@"Don't have two names separated by a \"\" at line %lu of %@", (unsigned long)lineNumber, usernameMapPath);
			[self notifyAboutImportProblem: [NSString stringWithFormat: @"Don't have two names separated by a \"\" at line %lu of %@", (unsigned long)lineNumber, usernameMapPath]];
			return nil;
		}
		NSString * sourceName = [[names firstObject] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		NSString * targetName = [[names lastObject]  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (  ! [sourceNames containsObject: sourceName]  ) {
			[self notifyAboutImportProblem: [NSString stringWithFormat: @"No data for user \"%@\" in %@", sourceName, usernameMapPath]];
			return nil;
		}
		if (  ! [targetNames containsObject: targetName]  ) {
			[self notifyAboutImportProblem: [NSString stringWithFormat: @"User \"%@\" does not exist on this computer (reading from %@)", targetName, usernameMapPath]];
			return nil;
		}
		[map appendFormat: @"%@:%@\n", sourceName, targetName];
	}
	
	return [NSString stringWithString: map];
}

-(void) notifyAboutImportProblem: (NSString *) errorMessage {
	
	NSLog(@"%@", errorMessage);
	
	TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
					  NSLocalizedString(@"There were problems importing Tunnelblick settings.\n\n"
										@"See the Console log for details.", @"Window text"));
}

-(NSArray *) usersOnThisComputer {
	
	if (  ! usersOnThisComputer  ) {
		
		NSMutableArray * result = [[[NSMutableArray alloc] initWithCapacity: 10] autorelease];
		
		NSString * name;
		NSDirectoryEnumerator * e = [gFileMgr enumeratorAtPath: @"/Users"];
		while (  (name = [e nextObject])  ) {
			[e skipDescendants];
			if (  ! [name hasPrefix: @"."]  ) {
				if (   ( getUidFromName(name) != 0 )
					&& ( getGidFromName(name) != 0 )  ) {
					[result addObject: name];
				}
			}
		}
		
		usersOnThisComputer = [[result sortedArrayUsingSelector: @selector(localizedStandardCompare:)] retain];
	}
	
	return [[usersOnThisComputer retain] autorelease];
}

-(NSArray *) usersInThisTblkSetup {
	
	if (  ! usersInThisTblkSetup  ) {

		NSMutableArray * result = [[[NSMutableArray alloc] initWithCapacity: 10] autorelease];
		
		NSString * name;
		NSDirectoryEnumerator * e = [gFileMgr enumeratorAtPath: [tblkSetupPath
																 stringByAppendingPathComponent: @"Users"]];
		while (  (name = [e nextObject])  ) {
			[e skipDescendants];
			if (  ! [name hasPrefix: @"."]  ) {
				[result addObject: name];
			}
		}
		
		e = [gFileMgr enumeratorAtPath: [[tblkSetupPath
										  stringByAppendingPathComponent: @"Global"]
										 stringByAppendingPathComponent: @"Users"]];
		while (  (name = [e nextObject])  ) {
			[e skipDescendants];
			if (  ! [name hasPrefix: @"."]  ) {
				if (  ! [result containsObject: name]  ) {
					[result addObject: name];
				}
			}
		}
		
		usersInThisTblkSetup = [[result sortedArrayUsingSelector: @selector(localizedStandardCompare:)] retain];
	}
	
	return [[usersInThisTblkSetup retain] autorelease];
}

@end
