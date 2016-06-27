/*
 * Copyright 2012, 2013, 2014 Jonathan K. Bullard. All rights reserved.
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

#import "easyRsa.h"

#import "defines.h"
#import "helper.h"
#import "sharedRoutines.h"

#import "NSFileManager+TB.h"
#import "TBUserDefaults.h"

extern NSFileManager   * gFileMgr;
extern TBUserDefaults  * gTbDefaults;


BOOL secureOurEasyRsa (void);


void easyRsaInstallFailed(NSString * message)
{
    NSString * fullMessage = [NSString stringWithFormat: NSLocalizedString(@"easy-rsa installation failed: %@", @"Window text"), message];
    NSLog(@"%@", fullMessage);
    TBShowAlertWindow(NSLocalizedString(@"Installation failed", @"Window title"),
                      fullMessage);
}

BOOL usingOurEasyRsa(void) {
	// Returns YES if we are using Tunnelblick's easy-rsa, and should update it
	// and secure it.
	
	NSString * pathFromPrefs = [gTbDefaults stringForKey: @"easy-rsaPath"];
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

BOOL secureEasyRsaAtPath(NSString * easyRsaPath) {
	
    NSArray * readOnlyList = [NSArray arrayWithObjects:
							  @"README",
							  @"TB-version.txt",
                              @"v3version.txt",
                              
							  @"EasyRSA-3/ChangeLog",
							  @"EasyRSA-3/COPYING",
							  @"EasyRSA-3/KNOWN_ISSUES",
							  @"EasyRSA-3/README",
							  @"EasyRSA-3/README.quickstart.md",
                              
							  @"EasyRSA-3/doc/EasyRSA-Advanced.md",
							  @"EasyRSA-3/doc/EasyRSA-Readme.md",
                              @"EasyRSA-3/doc/EasyRSA-Upgrade-Notes.md",
							  @"EasyRSA-3/doc/Hacking.md",
							  @"EasyRSA-3/doc/Intro-To-PKI.md",
							  @"EasyRSA-3/doc/TODO",
                              
							  @"EasyRSA-3/easyrsa3/x509-types/ca",
							  @"EasyRSA-3/easyrsa3/x509-types/client",
							  @"EasyRSA-3/easyrsa3/x509-types/COMMON",
							  @"EasyRSA-3/easyrsa3/x509-types/server",
							  @"EasyRSA-3/easyrsa3/vars.example",
                              
							  @"EasyRSA-3/Licensing/gpl-2.0.txt",
							  nil];
	
    NSArray * readWriteList = [NSArray arrayWithObjects:
                               @"openssl-0.9.6.cnf",
                               @"openssl-0.9.8.cnf",
                               @"openssl-1.0.0.cnf",
                               @"vars",
							   @"EasyRSA-3/easyrsa3/openssl-1.0.cnf",
                               nil];
	
	mode_t folderPerms    = 0700;	// also for anything in keys subfolder
	mode_t readwritePerms = 0600;
	mode_t scriptPerms    = 0500;
	mode_t readonlyPerms  = 0400;
	
    NSNumber * desiredOwner = [NSNumber numberWithInt: getuid()];
    
	// Check permissions on the parent folder and change if necessary
	if ( ! checkSetPermissions(easyRsaPath, folderPerms, YES)  ) {
		easyRsaInstallFailed([NSString stringWithFormat: NSLocalizedString(@"Unable to secure %@", @"Window text"), easyRsaPath]);
		return NO;
	}
	
    NSString * file;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: easyRsaPath];
    while (  (file = [dirEnum nextObject])  ) {
        NSString * fullPath = [easyRsaPath stringByAppendingPathComponent: file];
        if (  itemIsVisible(fullPath)  ) {
            
            // Check ownership
            NSDictionary * attributesBefore = [gFileMgr tbFileAttributesAtPath: fullPath traverseLink: NO];
            if (  ! [[attributesBefore fileOwnerAccountID] isEqualToNumber: desiredOwner]  ) {
                easyRsaInstallFailed([NSString stringWithFormat: NSLocalizedString(@"Unable to secure %@ because it is owned by %@", @"Window text"), fullPath, [attributesBefore fileOwnerAccountName]]);
                return NO;
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
			if ( ! checkSetPermissions(fullPath, desiredPermissions, YES)  ) {
                easyRsaInstallFailed([NSString stringWithFormat: NSLocalizedString(@"Unable to secure %@", @"Window text"), fullPath]);
				return NO;
			}
        }
    }
	
	return YES;
}

BOOL copyEasyRsa(NSString * sourcePath,
				 NSString * targetPath) {
	BOOL isDir;
	if (  [gFileMgr fileExistsAtPath: targetPath isDirectory: &isDir]  ) {
		if (  ! isDir  ) {
			easyRsaInstallFailed([NSString stringWithFormat: NSLocalizedString(@"%@ exists but is not a folder", @"Window text"), targetPath]);
			return NO;
		}
	} else {
		if (  ! [gFileMgr tbCopyPath: sourcePath toPath: targetPath handler: nil]  ) {
			[gFileMgr tbRemoveFileAtPath: targetPath handler: nil];
			easyRsaInstallFailed([NSString stringWithFormat: NSLocalizedString(@"Could not copy %@ to %@", @"Window text"), sourcePath, targetPath]);
			return NO;
		}
		
		// Propogate the modification dates
		NSString * file;
		NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: sourcePath];
		while (  (file = [dirEnum nextObject])  ) {
			if (  itemIsVisible(sourcePath)  ) {
				NSString * sourceFilePath = [sourcePath stringByAppendingPathComponent: file];
				NSString * targetFilePath = [targetPath stringByAppendingPathComponent: file];
				if ( ! propogateModificationDate(sourceFilePath, targetFilePath)  ) {
                    // (Already did easyRsaInstallFailed)
                    return NO;
                }
			}
		}
		
		NSLog(@"Copied easy-rsa");
		return YES;
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
                          
                          @"EasyRSA-3/ChangeLog",
                          @"EasyRSA-3/COPYING",
                          @"EasyRSA-3/KNOWN_ISSUES",
                          @"EasyRSA-3/README",
                          @"EasyRSA-3/README.quickstart.md",
                          
                          @"EasyRSA-3/doc/EasyRSA-Advanced.md",
                          @"EasyRSA-3/doc/EasyRSA-Readme.md",
                          @"EasyRSA-3/doc/EasyRSA-Upgrade-Notes.md",
                          @"EasyRSA-3/doc/Hacking.md",
                          @"EasyRSA-3/doc/Intro-To-PKI.md",
                          @"EasyRSA-3/doc/TODO",
                          
                          @"EasyRSA-3/easyrsa3/x509-types/ca",
                          @"EasyRSA-3/easyrsa3/x509-types/client",
                          @"EasyRSA-3/easyrsa3/x509-types/COMMON",
                          @"EasyRSA-3/easyrsa3/x509-types/server",
                          @"EasyRSA-3/easyrsa3/vars.example",
                          
                          @"EasyRSA-3/Licensing/gpl-2.0.txt",

						  @"EasyRSA-3/easyrsa3/openssl-1.0.cnf",
						  @"EasyRSA-3/easyrsa3/easyrsa",
                          
                          @"v3version.txt",
						  @"TB-version.txt",
						  nil];
	
	NSString * file;
	NSEnumerator * e = [fileList objectEnumerator];
	while (  (file = [e nextObject])  ) {
		NSString * sourceFilePath = [sourcePath stringByAppendingPathComponent: file];
		NSString * targetFilePath = [targetPath stringByAppendingPathComponent: file];
		
		// If the target specifies a path, make sure that all folders in that path have been created
		NSString * pathInfo  = [file stringByDeletingLastPathComponent];
		if (  [pathInfo length] != 0  ) {
			NSString * targetDirPath  = [targetFilePath stringByDeletingLastPathComponent];
			if (  ! [gFileMgr fileExistsAtPath: targetDirPath]  ) {
				if (  createDir(targetDirPath, 0700l) == -1  ) {
					easyRsaInstallFailed([NSString stringWithFormat: NSLocalizedString(@"Could not create %@", @"Window text"), targetDirPath]);
					return NO;
				}
			}
		}
		
		NSString * action;
        if (  [gFileMgr fileExistsAtPath: targetFilePath]  ) {
			action = @"Updated";
			if (  [gFileMgr contentsEqualAtPath: sourceFilePath andPath: targetFilePath]  ) {
				continue;
			}
			if (  ! [gFileMgr tbRemoveFileAtPath: targetFilePath handler: nil]  ) {
                easyRsaInstallFailed([NSString stringWithFormat: NSLocalizedString(@"Could not delete %@", @"Window text"), targetFilePath]);
                return NO;
			}
			
		} else {
			action = @"Created";
		}
		
		if (  ! [gFileMgr tbCopyPath: sourceFilePath toPath: targetFilePath handler: nil]  ) {
			easyRsaInstallFailed([NSString stringWithFormat:
								  NSLocalizedString(@"Could not copy %@ to %@", @"Window text"),
								  sourceFilePath,
								  targetFilePath]);
			return NO;
		} else {
			propogateModificationDate(sourceFilePath, targetFilePath);
			
			NSLog(@"%@ %@", action, targetFilePath);
		}
	}
	
	NSLog(@"Finished Update of easy-rsa");
	return YES;
}

BOOL installOrUpdateOurEasyRsa(void) {
    
	if (  ! usingOurEasyRsa()) {
		return YES;
	}
	
    NSString * appEasyRsaPath = [[NSBundle mainBundle] pathForResource: @"easy-rsa-tunnelblick" ofType: @""];
    if (  ! appEasyRsaPath  ) {
        easyRsaInstallFailed(NSLocalizedString(@"Could not find easy-rsa in Tunnelblick.app", @"Window text"));
        return NO;
    }
    
	NSString * appEasyRsaVersion = nil;
    NSData * data = [gFileMgr contentsAtPath: [appEasyRsaPath stringByAppendingPathComponent: @"TB-version.txt"]];
	if (  data  ) {
		appEasyRsaVersion = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
		
	}
    if (  ! appEasyRsaVersion  ) {
        easyRsaInstallFailed(NSLocalizedString(@"Could not find easy-rsa version information in Tunnelblick.app", @"Window text"));
        return NO;
    }
    
    NSString * installedEasyRsaPath = easyRsaPathToUse(NO);
    if (  ! installedEasyRsaPath  ) {
        easyRsaInstallFailed(NSLocalizedString(@"No path to easy-rsa. The most likely cause is a problem with the 'easy-rsaPath' preference", @"Window text"));
        return NO;
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
        return YES;
    }
    
	if (  ! copyEasyRsa(appEasyRsaPath,             // source
						installedEasyRsaPath)  ) {	// target
		return NO;
	}
	
	return secureEasyRsaAtPath(installedEasyRsaPath);
}

NSString * easyRsaPathToUse(BOOL mustExistAndBeADir) {
    // Returns the path to the "easy-rsa" folder
    // Note: returns nil if "easy-rsaPath" preference is invalid
    //       returns nil if "mustExistAndBeADir" and it doesn't exist or isn't a directory
    
    NSString * pathFromPrefs = [gTbDefaults stringForKey: @"easy-rsaPath"];
    if (  pathFromPrefs  ) {
        pathFromPrefs = [pathFromPrefs stringByExpandingTildeInPath];
        if (  ! [pathFromPrefs hasPrefix: @"/"]  ) {
            easyRsaInstallFailed(NSLocalizedString(@"'easy-rsaPath' preference ignored; it must be an absolute path or start with '~'", @"Window text"));
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
                easyRsaInstallFailed(NSLocalizedString(@"'easy-rsaPath' preference ignored; it does not specify a folder", @"Window text"));
                return nil;
            }
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

BOOL secureOurEasyRsa(void) {
	
	if (  ! usingOurEasyRsa()) {
		return YES;
	}
	
	NSString * easyRsaPath = easyRsaPathToUse(YES);
	if (  easyRsaPath  ) {
		if ( ! secureEasyRsaAtPath(easyRsaPath)  ) {
            // (Already did easyRsaInstallFailed)
            return NO;
        }
	}
    
    return YES;
}

BOOL openTerminalWithEasyRsaFolder(NSString * userPath) {
	
    if ( ! secureOurEasyRsa()  ) {
        // (Already did easyRsaInstallFailed)
        return NO;
    }
    
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
	
	startTool(TOOL_PATH_FOR_OSASCRIPT, arguments);
	return YES;
}
