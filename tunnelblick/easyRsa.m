/*
 * Copyright 2012 Jonathan K. Bullard
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

#include "easyRsa.h"
#include "helper.h"
#include "NSFileManager+TB.h"
#include "TBUserDefaults.h"

extern NSFileManager   * gFileMgr;
extern TBUserDefaults  * gTbDefaults;


void easyRsaInstallFailed(NSString * message)
{
    NSString * fullMessage = [NSString stringWithFormat: NSLocalizedString(@"easy-rsa installation failed: %@", @"Window text"), message];
    NSLog(@"%@", fullMessage);
    TBRunAlertPanel(NSLocalizedString(@"Installation failed", @"Window title"),
                    fullMessage,
                    nil, nil, nil);
}

BOOL usingOurEasyRsa(void) {
	// Returns YES if we are using Tunnelblick's easy-rsa, and should update it
	// and secure it.
	
	NSString * pathFromPrefs = [gTbDefaults objectForKey: @"easy-rsaPath"];
	if (  ! pathFromPrefs  ) {
		return YES;
	}
	
	NSString * pathToUse = easyRsaPathToUse(NO);
	if (  [pathToUse isEqualToString: pathFromPrefs]  ) {
		return NO;
	}
	
	return YES;
}

BOOL propogateModificationDate(NSString * sourceFilePath,
							   NSString * targetFilePath) {
	
	NSDictionary * sourceAttributes = [gFileMgr tbFileAttributesAtPath: sourceFilePath traverseLink: NO];
	if (  ! sourceAttributes  ) {
		easyRsaInstallFailed([NSString stringWithFormat: NSLocalizedString(@"Could not get attributes of %@", @"Window text"), sourceFilePath]);
		return NO;
	}
	NSDate * modificationDate = [sourceAttributes objectForKey: NSFileModificationDate];
	if (  ! modificationDate  ) {
		easyRsaInstallFailed([NSString stringWithFormat: NSLocalizedString(@"Could not get modification date of %@", @"Window text"), sourceFilePath]);
		return NO;
	}
	NSDictionary * targetAttribute = [NSDictionary dictionaryWithObject: modificationDate forKey:NSFileModificationDate];
	if (  ! [gFileMgr tbChangeFileAttributes: targetAttribute atPath: targetFilePath]  ) {
		easyRsaInstallFailed([NSString stringWithFormat:
							  NSLocalizedString(@"Could not set modification date of %@ to %@", @"Window text"),
							  targetFilePath, modificationDate]);
		return NO;
	}
	
	return YES;
}	

void secureEasyRsaAtPath(NSString * easyRsaPath) {
	
    NSArray * readOnlyList = [NSArray arrayWithObjects:
							  @"README",
							  @"TB-version.txt",
							  nil];
	
    NSArray * readWriteList = [NSArray arrayWithObjects:
                               @"openssl-0.9.6.cnf",
                               @"openssl-0.9.8.cnf",
                               @"openssl-1.0.0.cnf",
                               @"vars",
                               nil];
	
	mode_t folderPerms    = 0700;	// also for anything in keys subfolder
	mode_t readwritePerms = 0600;
	mode_t scriptPerms    = 0500;
	mode_t readonlyPerms  = 0400;
	
    NSNumber * desiredOwner = [NSNumber numberWithInt: getuid()];
    
	// Check permissions on the parent folder and change if necessary
	checkSetPermissions(easyRsaPath, folderPerms, YES);
	
    NSString * file;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: easyRsaPath];
    while (  (file = [dirEnum nextObject])  ) {
        NSString * fullPath = [easyRsaPath stringByAppendingPathComponent: file];
        if (  itemIsVisible(fullPath)  ) {
            
            // Check ownership
            NSDictionary * attributesBefore = [gFileMgr tbFileAttributesAtPath: fullPath traverseLink: NO];
            if (  ! [[attributesBefore fileOwnerAccountID] isEqualToNumber: desiredOwner]  ) {
                NSLog(@"Unable to secure %@ because it is owned by %@", fullPath, [attributesBefore fileOwnerAccountName]);
                return;
            }
            
            // Decide on desired permissions
            mode_t desiredPermissions;
			if (  [file hasPrefix: @"keys/"]  ) {
				desiredPermissions = folderPerms;
			} else if (  [readOnlyList containsObject: file]  ) {
				desiredPermissions = readonlyPerms;
			} else if (  [readWriteList containsObject: file]  ) {
                desiredPermissions = readwritePerms;
            } else {
                if (  [[attributesBefore fileType] isEqualToString: NSFileTypeDirectory]  ) {
                    desiredPermissions = folderPerms;
                } else {
                    desiredPermissions = scriptPerms;
                }
            }
            
            // Check permissions and change if necessary
			checkSetPermissions(fullPath, desiredPermissions, YES);
        }
    }
}

void copyEasyRsa(NSString * sourcePath,
				 NSString * targetPath) {
	BOOL isDir;
	if (  [gFileMgr fileExistsAtPath: targetPath isDirectory: &isDir]  ) {
		if (  ! isDir  ) {
			easyRsaInstallFailed([NSString stringWithFormat: NSLocalizedString(@"%@ exists but is not a folder", @"Window text"), targetPath]);
			return;
		}
	} else {
		if (  ! [gFileMgr tbCopyPath: sourcePath toPath: targetPath handler: nil]  ) {
			[gFileMgr tbRemoveFileAtPath: targetPath handler: nil];
			easyRsaInstallFailed([NSString stringWithFormat: NSLocalizedString(@"Could not copy %@ to %@", @"Window text"), sourcePath, targetPath]);
			return;
		}
		
		// Propogate the modification dates
		NSString * file;
		NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: sourcePath];
		while (  (file = [dirEnum nextObject])  ) {
			if (  itemIsVisible(sourcePath)  ) {
				NSString * sourceFilePath = [sourcePath stringByAppendingPathComponent: file];
				NSString * targetFilePath = [targetPath stringByAppendingPathComponent: file];
				propogateModificationDate(sourceFilePath, targetFilePath);
			}
		}
		
		NSLog(@"Copied easy-rsa");
		return;
	}
	
	// Update, not install, so copy individual files only
	
	NSLog(@"Starting update of easy-rsa...");
	
	NSArray * fileList = [NSArray arrayWithObjects:
						  @"build-ca",
						  @"build-dh",
						  @"build-inter",
						  @"build-key",
						  @"build-key-pass",
						  @"build-key-pkcs12",
						  @"build-key-server",
						  @"build-req",
						  @"build-req-pass",
						  @"clean-all",
						  @"inherit-inter",
						  @"list-crl",
						  @"pkitool",
						  @"revoke-full",
						  @"sign-req",
						  @"whichopensslcnf",
						  @"README",
						  @"TB-version.txt",
						  nil];
	
	NSString * file;
	NSEnumerator * e = [fileList objectEnumerator];
	while (  (file = [e nextObject])  ) {
		NSString * sourceFilePath = [sourcePath stringByAppendingPathComponent: file];
		NSString * targetFilePath = [targetPath stringByAppendingPathComponent: file];
        if (   [gFileMgr fileExistsAtPath: targetFilePath]
			&& ( ! [gFileMgr isWritableFileAtPath: targetFilePath] )  ) {
            NSDictionary * fullPermissions = [NSDictionary dictionaryWithObject: [NSNumber numberWithUnsignedLong: (unsigned long) 0700] forKey: NSFilePosixPermissions];
            if (  ! [gFileMgr tbChangeFileAttributes: fullPermissions atPath: targetFilePath]  ) {
				easyRsaInstallFailed([NSString stringWithFormat: NSLocalizedString(@"Could not make %@ deletable", @"Window text"), targetFilePath]);
				return;
            }
        }
		if (  ! [gFileMgr tbRemoveFileAtPath: targetFilePath handler: nil]  ) {
			if (  ! [file isEqualToString: @"TB-version.txt"]  ) {
				easyRsaInstallFailed([NSString stringWithFormat: NSLocalizedString(@"Could not delete %@", @"Window text"), targetFilePath]);
				return;
			}
		}
		if (  ! [gFileMgr tbCopyPath: sourceFilePath toPath: targetFilePath handler: nil]  ) {
			easyRsaInstallFailed([NSString stringWithFormat:
								  NSLocalizedString(@"Could not copy %@ to %@", @"Window text"),
								  sourceFilePath,
								  targetFilePath]);
			return;
		} else {
			propogateModificationDate(sourceFilePath, targetFilePath);
			
			NSLog(@"Updated %@", targetFilePath);
		}
	}
	
	
	NSLog(@"Finished Update of easy-rsa");
}

void installOrUpdateOurEasyRsa(void) {
    
	if (  ! usingOurEasyRsa()) {
		return;
	}
	
    NSString * appEasyRsaPath = [[NSBundle mainBundle] pathForResource: @"easy-rsa-Tunnelblick" ofType: @""];
    if (  ! appEasyRsaPath  ) {
        easyRsaInstallFailed(NSLocalizedString(@"Could not find easy-rsa in Tunnelblick.app", @"Window text"));
        return;
    }
    
	NSString * appEasyRsaVersion = nil;
    NSData * data = [gFileMgr contentsAtPath: [appEasyRsaPath stringByAppendingPathComponent: @"TB-version.txt"]];
	if (  data  ) {
		appEasyRsaVersion = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
		
	}
    if (  ! appEasyRsaVersion  ) {
        easyRsaInstallFailed(NSLocalizedString(@"Could not find easy-rsa version information in Tunnelblick.app", @"Window text"));
        return;
    }
    
    NSString * installedEasyRsaPath = easyRsaPathToUse(NO);
    if (  ! installedEasyRsaPath  ) {
        easyRsaInstallFailed(NSLocalizedString(@"No path to easy-rsa. The most likely cause is a problem with the 'easy-rsaPath' preference", @"Window text"));
        return;
    }
    
    NSString * installedEasyRsaVersion = nil;
    
    if (  [gFileMgr fileExistsAtPath: installedEasyRsaPath]  ) {
        data = [gFileMgr contentsAtPath: [installedEasyRsaPath stringByAppendingPathComponent: @"TB-version.txt"]];
		if (  data  ) {
			installedEasyRsaVersion = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
		}
		
		if (  ! installedEasyRsaVersion  ) {
            installedEasyRsaVersion = @"0";
        }
    } else {
        installedEasyRsaVersion = @"0";
    }
    
    NSComparisonResult result = [installedEasyRsaVersion compare: appEasyRsaVersion options: NSNumericSearch];
    if (  result != NSOrderedAscending  ) {
        return;
    }
    
	copyEasyRsa(appEasyRsaPath,         // source
				installedEasyRsaPath);	// target
	
	
	secureEasyRsaAtPath(installedEasyRsaPath);
}

NSString * easyRsaPathToUse(BOOL mustExistAndBeADir) {
    // Returns the path to the "easy-rsa" folder
    // Note: returns nil if "easy-rsaPath" preference is invalid
    //       returns nil if "mustExistAndBeADir" and it doesn't exist or isn't a directory
    
    NSString * pathFromPrefs = [gTbDefaults objectForKey: @"easy-rsaPath"];
    if (  pathFromPrefs  ) {
        if ( [[pathFromPrefs class] isSubclassOfClass: [NSString class]]  ) {
            pathFromPrefs = [pathFromPrefs stringByExpandingTildeInPath];
            if (  ! [pathFromPrefs hasPrefix: @"/"]  ) {
                NSLog(@"'easy-rsaPath' preference ignored; it must be an absolute path or start with '~'");
                return nil;
            } else {
                BOOL isDir;
                BOOL exists = [gFileMgr fileExistsAtPath: pathFromPrefs isDirectory: &isDir];
                if (  mustExistAndBeADir  ) {
                    if (  exists && isDir  ) {
                        return pathFromPrefs;
                    }
                    return nil;
                }
                if (   (  exists && isDir )
                    || ( ! exists )  ) {
                    return pathFromPrefs;
                } else if (  exists  ) {
                    NSLog(@"'easy-rsaPath' preference ignored; it does not specify a folder");
                    return nil;
                }
            }
        } else {
            NSLog(@"'easy-rsaPath' preference ignored; it must be a string");
            return nil;
        }
    }
    
    // Use default folder
    NSString * path = [[[[NSHomeDirectory() stringByAppendingPathComponent: @"Library"]
                         stringByAppendingPathComponent: @"Application Support"]
                        stringByAppendingPathComponent: @"Tunnelblick"]
                       stringByAppendingPathComponent: @"easy-rsa"];
    if (  mustExistAndBeADir ) {
        BOOL isDir;
        if (   [gFileMgr fileExistsAtPath: path isDirectory: &isDir]
            && isDir  ) {
            return path;
        }
        return nil;
    }
	
    return path;
}

void secureOurEasyRsa(void) {
	
	if (  ! usingOurEasyRsa()) {
		return;
	}
	
	NSString * easyRsaPath = easyRsaPathToUse(YES);
	if (  easyRsaPath  ) {
		secureEasyRsaAtPath(easyRsaPath);
	}
}

void openTerminalWithEasyRsaFolder(NSString * userPath) {

     secureOurEasyRsa();
     
     // Run an AppleScript to open Terminal.app and cd to the easy-rsa folder
     
     NSArray * applescriptProgram = [NSArray arrayWithObjects:
                                     [NSString stringWithFormat: @"set cmd to \"cd \\\"%@\\\"\"", userPath],
                                     @"tell application \"System Events\" to set terminalIsRunning to exists application process \"Terminal\"",
                                     @"tell application \"Terminal\"",
                                     @"     activate",
                                     @"     do script with command cmd",
                                     @"end tell",
                                     nil];
     
     NSMutableArray * arguments = [[[NSMutableArray alloc] initWithCapacity:6] autorelease];
     NSEnumerator * e = [applescriptProgram objectEnumerator];
     NSString * line;
     while (  (line = [e nextObject])  ) {
         [arguments addObject: @"-e"];
         [arguments addObject: line];
     }
     
     NSTask* task = [[[NSTask alloc] init] autorelease];
     [task setLaunchPath: @"/usr/bin/osascript"];
     [task setArguments: arguments];
     [task setCurrentDirectoryPath: @"/tmp"];
     [task launch];
     
}
