/*
 * Copyright 2004, 2005, 2006, 2007, 2008, 2009 by Angelo Laub
 * Contributions by Jonathan K. Bullard Copyright 2010, 2011
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

#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import <AppKit/AppKit.h>
#import "defines.h"
#import "NSFileManager+TB.h"
#import "ConfigurationConverter.h"
#import "sharedRoutines.h"

// NOTE: THIS PROGRAM MUST BE RUN AS ROOT VIA executeAuthorized
//
// This program is called when something needs to be secured.
// It accepts two to five arguments, and always does some standard housekeeping in
// addition to the specific tasks specified by the command line arguments.
//
// Usage:
//
//     installer bitMask
//     installer bitMask bundleVersion bundleVersionString
//     installer bitmask targetPath   [sourcePath]
//
// where
//   bitMask (See defines.h for bit assignments) -- DETERMINES WHAT THE INSTALLER WILL DO:
//
//     INSTALLER_COPY_APP:      set to copy this app to /Applications/XXXXX.app
//                                  (Any existing /Applications/XXXXX.app will be moved to the Trash)
//
//     INSTALLER_SECURE_APP:    set to secure Tunnelblick.app and all of its contents and update L_AS_T/Deploy if appropriate
//                                  (also set if INSTALLER_COPY_APP)
//     INSTALLER_COPY_BUNDLE:   set to copy this app's Resources/Tunnelblick Configurations.bundle to /Library/Application Support/Tunnelblick/Configuration Updates
//                                  (Will only be done if this app's Tunnelblick Configurations.bundle's version # is higher, or INSTALLER_COPY_APP is set)
//
//
//     INSTALLER_SECURE_TBLKS:  set to secure all .tblk packages in Configurations, Shared, and the alternate configuration path
//
//	   INSTALLER_CONVERT_NON_TBLKS: set to convert all .ovpn and .conf files (and their associated keys, scripts, etc.) to .tblk packages
//
//	   INSTALLER_MOVE_LIBRARY_OPENVPN: set to move ~/Library/openvpn to ~/Library/Application Support/Tunnelblick
//
//	   INSTALLER_UPDATE_DEPLOY: set to update /Library/Application Support/Deploy/xxx.app/ from the application
//
//     INSTALLER_MOVE_NOT_COPY: set to move, instead of copy, if target path and source path are supplied
//
//     INSTALLER_DELETE:        set to delete target path
//
//     INSTALLER_SET_VERSION:   set to store bundleVersion as a new value for CFBundleVersion 
//                                       and bundleVersionString as a new value for CFBundleShortVersionString
//                                     in /Library/Application Support/Tunnelblick/Configuration Updates/Tunnelblick Configurations.bundle/Contents/Into.plist
//                                     and remove Contents/Installer of the bundle
//
// bundleVersion       is a string to replace the CFBundleVersion
// bundleVersionString is a string to replace the CFBundleShortVersionString
//                                    in /Library/Application Support/Tunnelblick/Configuration Updates/Tunnelblick Configurations.bundle/Contents/Into.plist
//
// targetPath          is the path to a configuration (.ovpn or .conf file, or .tblk package) to be secured
// sourcePath          is the path to be copied or moved to targetPath before securing targetPath
//
// It does the following:
//      (1) ALWAYS creates directories or repair their ownership/permissions as needed
//      (2) if INSTALLER_MOVE_LIBRARY_OPENVPN, moves the contents of the old configuration folder
//          at ~/Library/openvpn to ~/Library/Application Support/Tunnelblick/Configurations
//          and replaces it with a symlink to the new location.
//      (3) If INSTALLER_CONVERT_NON_TBLKS, all private .ovpn or .conf files are converted to .tblks
//      (4) If INSTALLER_COPY_APP, this app is copied to /Applications
//      (5) If INSTALLER_COPY_BUNDLE, if /Resources/Tunnelblick Configurations.bundle exists, copies it to /Library/Application Support/T/Configuration Updates
//      (6) If INSTALLER_SECURE_APP, secures Tunnelblick.app by setting the ownership and permissions of its components.
//      (7) If INSTALLER_COPY_APP or INSTALLER_SECURE_APP, or INSTALLER_UPDATE_DEPLOY, deals with Deploy:
//             * Prunes any duplicate copies of Deploy in L_AS_T/Backup
//             * If exactly one copy of Deploy is in L_AS_T/Backup, copies it to gDeployPath and removes L_AS_T/Backup
//             * Updates the gDeployPath folder from this app if appropriate (using version # or modification date) and secures it
//      (8) If INSTALLER_SECURE_TBLKS, secures all .tblk packages in the following folders:
//           /Library/Application Support/Tunnelblick/Shared
//           ~/Library/Application Support/Tunnelblick/Configurations
//           /Library/Application Support/Tunnelblick/Users/<username>
//
//      (9) If INSTALLER_SET_VERSION is clear and INSTALLER_DELETE is clear and sourcePath is given,
//             copies or moves sourcePath to targetPath. Copies unless INSTALLER_MOVE_NOT_COPY is set.  (Also copies or moves the shadow copy if deleting a private configuration)
//     (10) If INSTALLER_SET_VERSION is clear and INSTALLER_DELETE is clear and targetPath is given,
//             secures the .ovpn or .conf file or a .tblk package at targetPath
//     (11) If INSTALLER_SET_VERSION is clear and INSTALLER_DELETE is set and targetPath is given,
//             deletes the .ovpn or .conf file or .tblk package at targetPath (also deletes the shadow copy if deleting a private configuration)
//     (12) If INSTALLER_SET_VERSION is set, copies the bundleVersion into the CFBundleVersion entry and bundleShortVersionString into the CFBundleShortVersionString entry
//                                           in /Library/Application Support/Tunnelblick/Configuration Updates/Tunnelblick Configurations.bundle/Contents/Into.plist
//
// When finished (or if an error occurs), the file /tmp/tunnelblick-authorized-running is deleted to indicate the program has finished
//
//        (10) is done when creating a shadow configuration file
//                     or copying a .tblk to install it
//                     or moving a .tblk to make it private or shared
//        (11) is done when repairing a shadow configuration file or after copying or moving a .tblk

FILE          * gLogFile;					  // FILE for log
NSFileManager * gFileMgr;                     // [NSFileManager defaultManager]
NSString      * gPrivatePath;                 // Path to ~/Library/Application Support/Tunnelblick/Configurations
NSString      * gDeployPath;                  // Path to /Library/Application Support/Tunnelblick/Deploy/<application-name>
NSString      * gAppConfigurationsBundlePath; // Path to Tunnelblick.app/Contents/Resources/Tunnelblick Configurations.bundle (after copy if INSTALLER_COPY_APP is set)
uid_t           gRealUserID;                  // User ID & Group ID for the real user (i.e., not "root:wheel", which is what we are running as)
gid_t           gRealGroupID;
NSAutoreleasePool * pool;

BOOL makeFileUnlockedAtPath(NSString * path);
BOOL moveContents(NSString * fromPath, NSString * toPath);
NSString * firstPartOfPath(NSString * path);
NSString * lastPartOfPath(NSString * path);
void safeCopyOrMovePathToPath(NSString * fromPath, NSString * toPath, BOOL moveNotCopy);
BOOL deleteThingAtPath(NSString * path);
NSArray * pathsForLatestNonduplicateDeployBackups(void);
void secureL_AS_T_DEPLOY();
NSArray * pathsForDeployBackups(void);
BOOL convertAllPrivateOvpnAndConfToTblk(void);
BOOL tunnelblickTestPrivateOnlyHasTblks(void);

//**************************************************************************************************************************

void errorExit();
void errorExitIfAnySymlinkInPath(NSString * path,
								 int testPoint);

void debugLog(NSString * string) {
	
	// Call this function to create files in /tmp to show progress through this program
	// when there are problems that cause the log not to be available
	// For example, if this installer hangs.
	//
	// "string" is a string identifier indicating where debugLog was called from.
	
	NSString * path = [NSString stringWithFormat: @"/tmp/0-tunnelblick-installer-debug-point-%@.txt", string];
	[[NSFileManager defaultManager] createFileAtPath: path contents: [NSData data] attributes: nil];
}

void openLog(BOOL clearLog) {
    
    const char * path = [INSTALLER_LOG_PATH fileSystemRepresentation];
	
	if (  clearLog  ) {
		gLogFile = fopen(path, "w");
	} else {
		gLogFile = fopen(path, "a");
	}
    
	if (  gLogFile == NULL  ) {
		errorExit();
	}
}

void appendLog(NSString * s) {
    
	if (  gLogFile != NULL  ) {
		fprintf(gLogFile, "%s\n", [s UTF8String]);
	} else {
		NSLog(@"%@", s);
	}
}

void closeLog(void) {
    
	if (  gLogFile != NULL  ) {
		fclose(gLogFile);
	}
}

void deleteFlagFile(NSString * path) {
    
	const char * fsrPath = [path fileSystemRepresentation];
    struct stat sb;
	if (  0 == stat(fsrPath, &sb)  ) {
        if (  (sb.st_mode & S_IFMT) == S_IFREG  ) {
            if (  0 != unlink(fsrPath)  ) {
                appendLog([NSString stringWithFormat: @"Unable to delete %@", path]);
            }
        } else {
            appendLog([NSString stringWithFormat: @"%@ is not a regular file; st_mode = 0%lo", path, (unsigned long) sb.st_mode]);
        }
    } else {
        appendLog([NSString stringWithFormat: @"stat of %@ failed\nError was '%s'", path, strerror(errno)]);
    }
}

void errorExit() {
    
    // Leave AUTHORIZED_ERROR_PATH to indicate an error occurred
    deleteFlagFile(AUTHORIZED_RUNNING_PATH);
	closeLog();
    
    [pool drain];
    exit(EXIT_FAILURE);
}

int main(int argc, char *argv[])
{
	pool = [NSAutoreleasePool new];
    
    if (  (argc < 2)  || (argc > 4)  ) {
		openLog(FALSE);
        appendLog([NSString stringWithFormat: @"Wrong number of arguments -- expected 1 to 3, given %d", argc-1]);
        errorExit();
	}

    unsigned arg1 = (unsigned) strtol(argv[1], NULL, 10);
    
	BOOL clearLog         = (arg1 & INSTALLER_CLEAR_LOG) != 0;
	
    BOOL copyApp          = (arg1 & INSTALLER_COPY_APP) != 0;
	
    BOOL secureApp        = copyApp || ( (arg1 & INSTALLER_SECURE_APP) != 0 );
    BOOL copyBundle       = (arg1 & INSTALLER_COPY_BUNDLE) != 0;
    BOOL secureTblks      = (arg1 & INSTALLER_SECURE_TBLKS) != 0;		// secureTblks will also be set if any private .ovpn or .conf configurations were converted to .tblks
	BOOL convertNonTblks  = (arg1 & INSTALLER_CONVERT_NON_TBLKS) != 0;
	BOOL moveLibOpenvpn   = (arg1 & INSTALLER_MOVE_LIBRARY_OPENVPN) != 0;
	BOOL updateDeploy     = (arg1 & INSTALLER_UPDATE_DEPLOY) != 0;

	
    BOOL setBundleVersion = (arg1 & INSTALLER_SET_VERSION) != 0;
    BOOL moveNotCopy      = (arg1 & INSTALLER_MOVE_NOT_COPY) != 0;
    BOOL deleteConfig     = (arg1 & INSTALLER_DELETE) != 0;
    
    // secureTblks will be set if any private .ovpn or .conf configurations were converted to .tblks
	
	openLog(  clearLog  );
	
	
    // Set gDeployPath from the name of this application without the ".app"
	NSBundle * ourBundle = [NSBundle mainBundle];
	NSString * resourcesPath = [ourBundle bundlePath]; // (installer itself is in Resources)
    NSArray  * execComponents = [resourcesPath pathComponents];
	if (  [execComponents count] < 3  ) {
        appendLog([NSString stringWithFormat: @"too few execComponents; resourcesPath = %@", resourcesPath]);
        errorExit();
    }
	NSString * ourAppName = [execComponents objectAtIndex: [execComponents count] - 3];
	if (  [ourAppName hasSuffix: @".app"]  ) {
		ourAppName = [ourAppName substringToIndex: [ourAppName length] - 4];
	}
	gDeployPath = [[L_AS_T_DEPLOY stringByAppendingPathComponent: ourAppName] copy];
    
	// Log the arguments installer was started with
	unsigned long firstArg = strtoul(argv[1], NULL, 10);
	NSMutableString * argString = [NSMutableString stringWithFormat: @" 0x%04lx", firstArg];
	int i;
	for (  i=2; i<argc; i++  ) {
		[argString appendFormat: @" %@", [NSString stringWithUTF8String: argv[i]]];
	}
	NSCalendarDate * date = [NSCalendarDate date];
	NSString * dateMsg = [date descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S"];
	
	appendLog([NSString stringWithFormat: @"Tunnelblick installer started %@. %d arguments:%@", dateMsg, argc - 1, argString]);
	
    gFileMgr = [NSFileManager defaultManager];
    gPrivatePath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Tunnelblick/Configurations/"] copy];
    
    // If we copy the .app to /Applications, other changes to the .app affect THAT copy, otherwise they affect the currently running copy
    NSString * appResourcesPath = (copyApp
                                   
                                   ? [[[@"/Applications"
                                        stringByAppendingPathComponent: [ourAppName stringByAppendingPathExtension: @"app"]]
                                       stringByAppendingPathComponent: @"Contents"]
                                      stringByAppendingPathComponent: @"Resources"]

                                   : [[resourcesPath copy] autorelease]);
    
    gAppConfigurationsBundlePath    = [appResourcesPath stringByAppendingPathComponent:@"Tunnelblick Configurations.bundle"];

    gRealUserID  = getuid();
    gRealGroupID = getgid();
    
    BOOL isDir;
    
    NSString * firstPath = nil;
    if (  argc > 2  ) {
        firstPath = [gFileMgr stringWithFileSystemRepresentation: argv[2] length: strlen(argv[2])];
        if (  ! [firstPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
            errorExitIfAnySymlinkInPath(firstPath, 10);
        }
    }
    NSString * secondPath = nil;
    if (  argc > 3  ) {
        secondPath = [gFileMgr stringWithFileSystemRepresentation: argv[3] length: strlen(argv[3])];
        if (  ! [secondPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
            errorExitIfAnySymlinkInPath(secondPath, 11);
        }
    }
    
    NSString * bundleVersion            = firstPath;    // 2nd argument has two uses
    NSString * bundleShortVersionString = secondPath;      // 3rd argument has two uses
    if (  setBundleVersion  ) {
        if (  [bundleVersion isEqualToString: @""]  ) {
            bundleVersion = nil;
        }
        if (  [bundleShortVersionString isEqualToString: @""]  ) {
            bundleShortVersionString = nil;
        }
        if (   ( ! bundleVersion )
            || ( ! bundleShortVersionString )  ) {
            appendLog(@"Both a CFBundleVersion and a CFBundleShortVersionString are required to set the bundle version");
        }
    }
	
    //**************************************************************************************************************************
    // (1) Create directories or repair their ownership/permissions as needed
    
    if (  ! createDirWithPermissionAndOwnership(@"/Library/Application Support/Tunnelblick",
                                                0755, 0, 0)  ) {
        errorExit();
    }
    
    if (  [gFileMgr fileExistsAtPath: L_AS_T_DEPLOY]  ) {
        secureL_AS_T_DEPLOY();
    }
    
    if (  ! createDirWithPermissionAndOwnership(L_AS_T_LOGS,
                                                0755, 0, 0)  ) {
        errorExit();
    }
    
    if (  ! createDirWithPermissionAndOwnership(L_AS_T_SHARED,
                                                0755, 0, 0)  ) {
        errorExit();
    }
    
    if (  ! createDirWithPermissionAndOwnership(L_AS_T_USERS,
                                                0750, 0, 0)  ) {
        errorExit();
    }
    
    if (  ! createDirWithPermissionAndOwnership([L_AS_T_USERS
                                                 stringByAppendingPathComponent: NSUserName()],
                                                0750, 0, 0)  ) {
        errorExit();
    }
    
    NSString * userL_AS_T_Path= [[[NSHomeDirectory()
                                   stringByAppendingPathComponent: @"Library"]
                                  stringByAppendingPathComponent: @"Application Support"]
                                 stringByAppendingPathComponent: @"Tunnelblick"];
    
    if (  ! createDirWithPermissionAndOwnership(userL_AS_T_Path,
                                                0750, gRealUserID, ADMIN_GROUP_ID)  ) {
        errorExit();
    }
    
    if (  ! createDirWithPermissionAndOwnership([userL_AS_T_Path
                                                 stringByAppendingPathComponent: @"Configurations"],
                                                0750, gRealUserID, ADMIN_GROUP_ID)  ) {
        errorExit();
    }
    
    //**************************************************************************************************************************
    // (2)
    // Deal with migration to new configuration path
	
	if (  moveLibOpenvpn  ) {
		
		NSString * oldConfigDirPath = [NSHomeDirectory() stringByAppendingPathComponent: @"Library/openvpn"];
		NSString * newConfigDirPath = [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Application Support/Tunnelblick/Configurations"];
		
		// Verify that new configuration folder exists
		if (  [gFileMgr fileExistsAtPath: newConfigDirPath isDirectory: &isDir]  ) {
			if (  isDir  ) {
				// If old configurations folder exists (and is a folder):
				// Move its contents to the new configurations folder and delete it
				NSDictionary * fileAttributes = [gFileMgr tbFileAttributesAtPath: oldConfigDirPath traverseLink: NO];
				if (  ! [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
					if (  [gFileMgr fileExistsAtPath: oldConfigDirPath isDirectory: &isDir]  ) {
						if (  isDir  ) {
							// Move old configurations folder's contents to the new configurations folder and delete the old folder
							if (  moveContents(oldConfigDirPath, newConfigDirPath)  ) {
								appendLog([NSString stringWithFormat: @"Moved contents of %@ to %@", oldConfigDirPath, newConfigDirPath]);
								secureTblks = TRUE; // We may have moved some .tblks, so we should secure them
								// Delete the old configuration folder
								if (  ! [gFileMgr tbRemoveFileAtPath:oldConfigDirPath handler: nil]  ) {
									appendLog([NSString stringWithFormat: @"Unable to remove %@", oldConfigDirPath]);
									errorExit();
								}
							} else {
								appendLog([NSString stringWithFormat: @"Unable to move all contents of %@ to %@", oldConfigDirPath, newConfigDirPath]);
								errorExit();
							}
						} else {
							appendLog([NSString stringWithFormat: @"%@ is not a symbolic link or a folder", oldConfigDirPath]);
							errorExit();
						}
					}
				}
			} else {
				appendLog([NSString stringWithFormat: @"Warning: %@ exists but is not a folder", newConfigDirPath]);
				if ( secureTblks ) {
					errorExit();
				}
			}
		} else {
			appendLog([NSString stringWithFormat: @"Warning: Private configuration folder %@ does not exist", newConfigDirPath]);
			if ( secureTblks ) {
				errorExit();
			}
		}
	}
	
    //**************************************************************************************************************************
	// (3) If INSTALLER_CONVERT_NON_TBLKS, all .ovpn or .conf files are converted to .tblks
	
	if (  convertNonTblks  ) {
		if ( ! tunnelblickTestPrivateOnlyHasTblks()  ) {
			appendLog(@"\nBeginning conversion of .ovpn and .conf configurations to .tblk configurations...");
			
			if (  ! convertAllPrivateOvpnAndConfToTblk()  ) {
				appendLog(@"Conversion of .ovpn and .conf configurations to .tblk configurations failed");
				errorExit();
			}
			
			secureTblks = TRUE;
			appendLog(@"Conversion of .ovpn and .conf configurations to .tblk configurations succeeded\n");
		}
	}
	
    //**************************************************************************************************************************
    // (4)
    // If INSTALLER_COPY_APP is set:
    //    Move /Applications/XXXXX.app to the Trash, then copy this app to /Applications/XXXXX.app
    
    if (  copyApp  ) {
        NSString * currentPath = [[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        NSString * targetPath = [@"/Applications" stringByAppendingPathComponent: [ourAppName stringByAppendingPathExtension: @"app"]];
        if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
            errorExitIfAnySymlinkInPath(targetPath, 1);
            if (  [[NSWorkspace sharedWorkspace] performFileOperation: NSWorkspaceRecycleOperation
                                                               source: @"/Applications"
                                                          destination: @""
                                                                files: [NSArray arrayWithObject: [ourAppName stringByAppendingPathExtension: @"app"]]
                                                                  tag: nil]  ) {
                appendLog([NSString stringWithFormat: @"Moved %@ to the Trash", targetPath]);
            } else {
                appendLog([NSString stringWithFormat: @"Unable to move %@ to the Trash", targetPath]);
                errorExit();
            }
        }
        
        if (  ! [gFileMgr tbCopyPath: currentPath toPath: targetPath handler: nil]  ) {
            appendLog([NSString stringWithFormat: @"Unable to copy %@ to %@", currentPath, targetPath]);
            errorExit();
        } else {
            appendLog([NSString stringWithFormat: @"Copied %@ to %@", currentPath, targetPath]);
        }
    }
    
    //**************************************************************************************************************************
    // (5)
    // If INSTALLER_COPY_BUNDLE is set and the bundle exists and INSTALLER_COPY_APP is set
    //                                                           or the application's bundleVersion is a higher version number
    //    Copy Resources/Tunnelblick Configurations.bundle to /Library/Application Support/Tunnelblick/Configuration Updates
    if (  copyBundle  ) {
        if (   [gFileMgr fileExistsAtPath: gAppConfigurationsBundlePath isDirectory: &isDir]
            && isDir  ) {
            
            BOOL doCopy = FALSE;
            
            if (  [gFileMgr fileExistsAtPath: CONFIGURATION_UPDATES_BUNDLE_PATH]  ) {
                NSString * appPlistPath = [gAppConfigurationsBundlePath stringByAppendingPathComponent: @"Contents/Info.plist"];
                NSString * libPlistPath = [CONFIGURATION_UPDATES_BUNDLE_PATH stringByAppendingPathComponent: @"Contents/Info.plist"];
                NSDictionary * appDict = [NSDictionary dictionaryWithContentsOfFile: appPlistPath];
                NSDictionary * libDict = [NSDictionary dictionaryWithContentsOfFile: libPlistPath];
                NSString * appVersion = [appDict objectForKey: @"CFBundleVersion"];
                NSString * libVersion = [libDict objectForKey: @"CFBundleVersion"];
                if (  appVersion  ) {
                    if (  libVersion  ) {
                        if (   copyApp  ) {
                            doCopy = TRUE;
                        } else {
                            NSComparisonResult result = [appVersion compare: libVersion options: NSNumericSearch];
                            if (   result  == NSOrderedDescending  ) {
                                doCopy = TRUE;
                            }
                        }
                    } else {
                        doCopy = TRUE;  // No version info in library copy
                    }
                } else {
                    appendLog([NSString stringWithFormat: @"No CFBundleVersion in %@", gAppConfigurationsBundlePath]);
                    errorExit();
                }
            } else {
                doCopy = TRUE;  // No existing Tunnelblick Configurations.bundle in /Library...
            }
            
            if (  doCopy  ) {
                // Create the folder that holds Tunnelblick Configurations.bundle if it doesn't already exist
                // This must be writable by all users so Sparkle can store the update there
                NSString * configurationBundleHolderPath = [CONFIGURATION_UPDATES_BUNDLE_PATH stringByDeletingLastPathComponent];
                if (  ! createDirWithPermissionAndOwnership(configurationBundleHolderPath, 0755, 0, 0)  ) {
                    errorExit();
                }
                
                // Copy Tunnelblick Configurations.bundle, overwriting any existing one
                if (  ! makeFileUnlockedAtPath(CONFIGURATION_UPDATES_BUNDLE_PATH)  ) {
                    errorExit();
                }
                if (  [gFileMgr fileExistsAtPath: CONFIGURATION_UPDATES_BUNDLE_PATH]  ) {
                    if (  ! [gFileMgr tbRemoveFileAtPath: CONFIGURATION_UPDATES_BUNDLE_PATH handler: nil]  ) {
                        appendLog([NSString stringWithFormat: @"Unable to delete %@", CONFIGURATION_UPDATES_BUNDLE_PATH]);
                        errorExit();
                    }
                }
                if (  ! [gFileMgr tbCopyPath: gAppConfigurationsBundlePath toPath: CONFIGURATION_UPDATES_BUNDLE_PATH handler: nil]  ) {
                    appendLog([NSString stringWithFormat: @"Unable to copy %@ to %@", gAppConfigurationsBundlePath, CONFIGURATION_UPDATES_BUNDLE_PATH]);
                    errorExit();
                } else {
                    appendLog([NSString stringWithFormat: @"Copied %@ to %@", gAppConfigurationsBundlePath, CONFIGURATION_UPDATES_BUNDLE_PATH]);
                }
                
                // Set ownership and permissions
                if ( ! checkSetOwnership(CONFIGURATION_UPDATES_BUNDLE_PATH, YES, 0, 0)  ) {
                    errorExit();
                }
                if ( ! checkSetPermissions(CONFIGURATION_UPDATES_BUNDLE_PATH, 0755, YES)  ) {
                    errorExit();
                }
            }
        }
    }
    
    //**************************************************************************************************************************
    // (6)
    // If requested, secure Tunnelblick.app by setting ownership of Info.plist and Resources and its contents to root:wheel,
    // and setting permissions as follows:
    //        Info.plist is set to 0644
    //        openvpnstart is set to 04555 (SUID)
    //        openvpn is set to 0755
    //        Other executables and standard scripts are set to 0744
    //        For the contents of /Resources/Deploy and its subfolders:
    //            folders are set to 0755
    //            certificate & key files (various extensions) are set to 0640
    //            shell scripts (*.sh) are set to 0744
    //            all other files are set to 0644
    if ( secureApp ) {
        
        NSString *contentsPath				= [appResourcesPath stringByDeletingLastPathComponent];
        NSString *infoPlistPath				= [contentsPath stringByAppendingPathComponent: @"Info.plist"];
        NSString *deployPath                = [appResourcesPath stringByAppendingPathComponent:@"Deploy"                                         ];
        NSString *openvpnstartPath          = [appResourcesPath stringByAppendingPathComponent:@"openvpnstart"                                   ];
        NSString *openvpnPath               = [appResourcesPath stringByAppendingPathComponent:@"openvpn"                                        ];
        NSString *atsystemstartPath         = [appResourcesPath stringByAppendingPathComponent:@"atsystemstart"                                  ];
        NSString *installerPath             = [appResourcesPath stringByAppendingPathComponent:@"installer"                                      ];
        NSString *ssoPath                   = [appResourcesPath stringByAppendingPathComponent:@"standardize-scutil-output"                      ];
        NSString *pncPath                   = [appResourcesPath stringByAppendingPathComponent:@"process-network-changes"                        ];
        NSString *leasewatchPath            = [appResourcesPath stringByAppendingPathComponent:@"leasewatch"                                     ];
        NSString *leasewatch3Path           = [appResourcesPath stringByAppendingPathComponent:@"leasewatch3"                                    ];
        NSString *clientUpPath              = [appResourcesPath stringByAppendingPathComponent:@"client.up.osx.sh"                               ];
        NSString *clientDownPath            = [appResourcesPath stringByAppendingPathComponent:@"client.down.osx.sh"                             ];
        NSString *clientNoMonUpPath         = [appResourcesPath stringByAppendingPathComponent:@"client.nomonitor.up.osx.sh"                     ];
        NSString *clientNoMonDownPath       = [appResourcesPath stringByAppendingPathComponent:@"client.nomonitor.down.osx.sh"                   ];
        NSString *clientNewUpPath           = [appResourcesPath stringByAppendingPathComponent:@"client.up.tunnelblick.sh"                       ];
        NSString *clientNewDownPath         = [appResourcesPath stringByAppendingPathComponent:@"client.down.tunnelblick.sh"                     ];
        NSString *clientNewRoutePreDownPath = [appResourcesPath stringByAppendingPathComponent:@"client.route-pre-down.tunnelblick.sh"           ];
        NSString *clientNewAlt1UpPath       = [appResourcesPath stringByAppendingPathComponent:@"client.1.up.tunnelblick.sh"                     ];
        NSString *clientNewAlt1DownPath     = [appResourcesPath stringByAppendingPathComponent:@"client.1.down.tunnelblick.sh"                   ];
        NSString *clientNewAlt2UpPath       = [appResourcesPath stringByAppendingPathComponent:@"client.2.up.tunnelblick.sh"                     ];
        NSString *clientNewAlt2DownPath     = [appResourcesPath stringByAppendingPathComponent:@"client.2.down.tunnelblick.sh"                   ];
        NSString *clientNewAlt3UpPath       = [appResourcesPath stringByAppendingPathComponent:@"client.3.up.tunnelblick.sh"                     ];
        NSString *clientNewAlt3DownPath     = [appResourcesPath stringByAppendingPathComponent:@"client.3.down.tunnelblick.sh"                   ];
        
        NSString *tunnelblickPath = [contentsPath stringByDeletingLastPathComponent];
        BOOL okSoFar = checkSetOwnership(tunnelblickPath, YES, 0, 0);
        
        okSoFar = okSoFar && checkSetPermissions(infoPlistPath,             0644, YES);
        
        okSoFar = okSoFar && checkSetPermissions(openvpnPath,               0755, YES);
        
        okSoFar = okSoFar && checkSetPermissions(atsystemstartPath,         0744, YES);
        okSoFar = okSoFar && checkSetPermissions(installerPath,             0744, YES);
        okSoFar = okSoFar && checkSetPermissions(leasewatchPath,            0744, YES);
        okSoFar = okSoFar && checkSetPermissions(leasewatch3Path,           0744, YES);
        okSoFar = okSoFar && checkSetPermissions(pncPath,                   0744, YES);
        okSoFar = okSoFar && checkSetPermissions(ssoPath,                   0744, YES);
        okSoFar = okSoFar && checkSetPermissions(clientUpPath,              0744, NO);
        okSoFar = okSoFar && checkSetPermissions(clientDownPath,            0744, NO);
        okSoFar = okSoFar && checkSetPermissions(clientNoMonUpPath,         0744, NO);
        okSoFar = okSoFar && checkSetPermissions(clientNoMonDownPath,       0744, NO);
        okSoFar = okSoFar && checkSetPermissions(clientNewUpPath,           0744, YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewDownPath,         0744, YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewRoutePreDownPath, 0744, YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt1UpPath,       0744, YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt1DownPath,     0744, YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt2UpPath,       0744, YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt2DownPath,     0744, YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt3UpPath,       0744, YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt3DownPath,     0744, YES);
                
        // Check/set OpenVPN version folders and openvpn and openvpn-down-root.so in them
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: openvpnPath];
        NSString * file;
        BOOL isDir;
        while (  (file = [dirEnum nextObject])  ) {
			[dirEnum skipDescendents];
            NSString * fullPath = [openvpnPath stringByAppendingPathComponent: file];
            if (   [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
                && isDir  ) {
                if (  [file hasPrefix: @"openvpn-"]  ) {
                    okSoFar = okSoFar && checkSetPermissions(fullPath, 0755, YES);
                    
                    NSString * thisOpenvpnPath = [fullPath stringByAppendingPathComponent: @"openvpn"];
                    okSoFar = okSoFar && checkSetPermissions(thisOpenvpnPath, 0755, YES);
                    
                    NSString * thisOpenvpnDownRootPath = [fullPath stringByAppendingPathComponent: @"openvpn-down-root.so"];
                    okSoFar = okSoFar && checkSetPermissions(thisOpenvpnDownRootPath, 0744, NO);
                }
            }
        }
        
        // Check/set the app's Deploy folder
        if (   [gFileMgr fileExistsAtPath: deployPath isDirectory: &isDir]
            && isDir  ) {
            okSoFar = okSoFar && secureOneFolder(deployPath, NO, 0);
        }
		
		// Save this for last, so if something goes wrong, it isn't SUID inside a damaged app
		if (  okSoFar  ) {
			okSoFar = checkSetPermissions(openvpnstartPath, 04555, YES);
		}
		
		if (  ! okSoFar  ) {
            appendLog(@"Unable to secure Tunnelblick.app");
            errorExit();
        }
    }
    
    //**************************************************************************************************************************
    // (7) Deal with Deploy folders
    //     * Secure the old Deploy backups
    //     * If INSTALLER_COPY_APP or INSTALLER_SECURE_APP, deals with Deploy:
    //       * If this app has a Deploy folder, copies it to gDeployPath and secures the copy
    //       * If gDeployPath doesn't exist and there is exactly one unique Deploy backup, copies it to gDeployPath and secures it
    
    if ( copyApp || secureApp || updateDeploy ) {
        
        // Secure the old Deploy backups
        NSArray * deployBackups = pathsForDeployBackups();
		if (  ! deployBackups  ) {
			appendLog(@"Error occurred while looking for Deploy backups");
			errorExit();
		}
		appendLog([NSString stringWithFormat: @"%u Deploy backup folders to secure", [deployBackups count]]);

		BOOL okSoFar = TRUE;
		NSString * folderPath;
		NSEnumerator * e = [deployBackups objectEnumerator];
		while (  (folderPath = [e nextObject])  ) {
			okSoFar = okSoFar && secureOneFolder(folderPath, NO, 0);
		}
		
		if (  ! okSoFar  ) {
			appendLog(@"Unable to secure Deploy backups");
			errorExit();
		}
        
        // If this app has a Deploy folder, copy it to gDeployPath
        NSString * thisAppDeployPath = [[NSBundle mainBundle] pathForResource: @"Deploy" ofType: nil];
        if (  [gFileMgr fileExistsAtPath: thisAppDeployPath]  ) {
            [gFileMgr tbRemoveFileAtPath: gDeployPath handler: nil];
            if (  [gFileMgr tbCopyPath: thisAppDeployPath toPath: gDeployPath handler: nil]  ) {
                appendLog([NSString stringWithFormat: @"Updated Deploy with copy in %@", [[[thisAppDeployPath stringByDeletingLastPathComponent] // delete Deploy
                                                                stringByDeletingLastPathComponent]                    // delete Resources
                                                               stringByDeletingLastPathComponent]]);                  // delete Contents
                appendLog([NSString stringWithFormat: @"Updated Deploy with copy in %@", [[[thisAppDeployPath stringByDeletingLastPathComponent] // delete Deploy
                                                                stringByDeletingLastPathComponent]                    // delete Resources
                                                               stringByDeletingLastPathComponent]]);                  // delete Contents
            } else {
                appendLog([NSString stringWithFormat: @"Error ocurred copying %@ to %@", thisAppDeployPath, gDeployPath]);
                errorExit();
            }
            
            secureL_AS_T_DEPLOY();
            
        } else {
            
            NSArray * backupDeployPathsWithoutDupes = pathsForLatestNonduplicateDeployBackups();
			if (  ! backupDeployPathsWithoutDupes  ) {
				errorExit();
			}
            appendLog([NSString stringWithFormat: @"%u unique Deploy Backups", [backupDeployPathsWithoutDupes count]]);
            
            // If there is only one unique Deploy backup and gDeployPath doesn't exist, copy it to gDeployPath
            if (   ([backupDeployPathsWithoutDupes count] == 1)
                && ( ! [gFileMgr fileExistsAtPath: gDeployPath] )  ) {
                NSString * pathToCopy = [backupDeployPathsWithoutDupes objectAtIndex: 0];
                [gFileMgr tbRemoveFileAtPath: gDeployPath handler: nil];
                if (  [gFileMgr tbCopyPath: pathToCopy toPath: gDeployPath handler: nil]  ) {
                    appendLog([NSString stringWithFormat: @"Copied the only non-duplicate Deploy backup folder %@ to %@", pathToCopy, gDeployPath]);
                } else {
                    appendLog([NSString stringWithFormat: @"Error occurred copying the only Deploy backup folder %@ to %@", pathToCopy, gDeployPath]);
                    errorExit();
                }
                
                secureL_AS_T_DEPLOY();
            }
        }
    }
    
    //**************************************************************************************************************************
    // (8)
    // If requested, secure all .tblk packages
    if (  secureTblks  ) {
        NSString * altPath = [L_AS_T_USERS stringByAppendingPathComponent: NSUserName()];

        // First, copy any .tblks that are in private to alt (unless they are already there)
        NSString * file;
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: gPrivatePath];
        while (  (file = [dirEnum nextObject])  ) {
			if (  [[file pathExtension] isEqualToString: @"tblk"]  ) {
				[dirEnum skipDescendents];
                NSString * privateTblkPath = [gPrivatePath stringByAppendingPathComponent: file];
                NSString * altTblkPath     = [altPath stringByAppendingPathComponent: file];
                if (  ! [gFileMgr fileExistsAtPath: altTblkPath]  ) {
					if (  ! createDirWithPermissionAndOwnership([altTblkPath stringByDeletingLastPathComponent], PERMS_SECURED_PRIVATE_FOLDER, 0, 0)  ) {
						errorExit();
					}
                    if (  [gFileMgr tbCopyPath: privateTblkPath toPath: altTblkPath handler: nil]  ) {
                        appendLog([NSString stringWithFormat: @"Created shadow copy of %@", privateTblkPath]);
                    } else {
                        appendLog([NSString stringWithFormat: @"Unable to create shadow copy of %@", privateTblkPath]);
                        errorExit();
                    }
				}
            }
        }
        
        // Now secure shared tblks, private tblks, and shadow copies of private tblks 
        
        NSArray * foldersToSecure = [NSArray arrayWithObjects: L_AS_T_SHARED, gPrivatePath, altPath, nil];
        
        BOOL okSoFar = YES;
        unsigned i;
        for (i=0; i < [foldersToSecure count]; i++) {
            NSString * folderPath = [foldersToSecure objectAtIndex: i];
            BOOL isPrivate = [folderPath hasPrefix: gPrivatePath];
            okSoFar = okSoFar && secureOneFolder(folderPath, isPrivate, gRealUserID);
		}
        
        if (  ! okSoFar  ) {
            appendLog([NSString stringWithFormat: @"Warning: Unable to secure all .tblk packages"]);
        }
    }
    
    //**************************************************************************************************************************
    // (9)
    // If requested, copy or move a .tblk package (also move/copy/create a shadow copy if a private configuration)
    // Like the NSFileManager "movePath:toPath:handler" method, we move by copying, then deleting, because we may be moving
    // from one disk to another (e.g., home folder on network to local hard drive)
    if (   secondPath
        && ( ! deleteConfig )
        && ( ! setBundleVersion )  ) {
		
		NSString * sourcePath = [[secondPath copy] autorelease];
		NSString * targetPath = [[firstPath  copy] autorelease];
        
        // Make sure we are dealing with .tblks
        if (  ! [[sourcePath pathExtension] isEqualToString: @"tblk"]  ) {
            appendLog([NSString stringWithFormat: @"Only .tblks may be copied or moved: Not a .tblk: %@", sourcePath]);
            errorExit();
        }
        if (  ! [[targetPath pathExtension] isEqualToString: @"tblk"]  ) {
            appendLog([NSString stringWithFormat: @"Only .tblks may be copied or moved: Not a .tblk: %@", targetPath]);
            errorExit();
        }

        // Create the enclosing folder(s) if necessary. Owned by root unless if in gPrivatePath, in which case it is owned by the user
        NSString * enclosingFolder = [targetPath stringByDeletingLastPathComponent];
        uid_t  own   = 0;
        gid_t  grp   = 0;
		mode_t perms;
		if (  [targetPath hasPrefix: [L_AS_T_USERS stringByAppendingString: @"/"]]  ) {
			perms = PERMS_SECURED_PRIVATE_FOLDER;
		} else {
			perms = PERMS_SECURED_PUBLIC_FOLDER;
		}
        if (  [targetPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
            own   = gRealUserID;
            grp   = ADMIN_GROUP_ID;
			perms = PERMS_PRIVATE_PRIVATE_FOLDER;
        }
        errorExitIfAnySymlinkInPath(enclosingFolder, 2);
        
        if (  ! createDirWithPermissionAndOwnership(enclosingFolder, perms, own, grp)  ) {
            errorExit();
        }
        
        // Make sure we can delete the original if we are moving instead of copying
        if (  moveNotCopy  ) {
            if (  ! makeFileUnlockedAtPath(targetPath)  ) {
                errorExit();
            }
        }
        
        // Do the move or copy
        //
        // If   we MOVED OR COPIED TO PRIVATE
        // Then secure the target
		//      create a shadow copy of the target and secure the shadow copy
        // Else secure the target
        //
        // If   we MOVED FROM PRIVATE
        // Then delete the shadow copy of the source

        safeCopyOrMovePathToPath(sourcePath, targetPath, moveNotCopy);
        
		NSString * lastPartOfTarget = lastPartOfPath(targetPath);
		
        if (   [targetPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
			secureOneFolder(targetPath, YES, getuid());
			
            NSString * shadowTargetPath   = [NSString stringWithFormat: @"%@/%@/%@",
                                             L_AS_T_USERS,
                                             NSUserName(),
                                             lastPartOfTarget];
            
            BOOL deletedOldShadowCopy = FALSE;
			if (  [gFileMgr fileExistsAtPath: shadowTargetPath]  ) {
				if (  ! deleteThingAtPath(shadowTargetPath)  ) {
					errorExit();
				}
                
                deletedOldShadowCopy = TRUE;
			}
			
			safeCopyOrMovePathToPath(targetPath, shadowTargetPath, FALSE);
            secureOneFolder(shadowTargetPath, NO, 0);
            if (  deletedOldShadowCopy  ) {
                appendLog([NSString stringWithFormat: @"Updated secure (shadow) copy of %@", lastPartOfTarget]);
            } else {
                appendLog([NSString stringWithFormat: @"Created secure (shadow) copy of %@", lastPartOfTarget]);
            }
            
        } else {
            secureOneFolder(targetPath, NO, 0);
        }
        
        if (  [sourcePath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
            if (  moveNotCopy  ) {
                NSString * lastPartOfSource = lastPartOfPath(sourcePath);
                NSString * shadowSourcePath   = [NSString stringWithFormat: @"%@/%@/%@",
                                                 L_AS_T_USERS,
                                                 NSUserName(),
                                                 lastPartOfSource];
                if (  ! deleteThingAtPath(shadowSourcePath)  ) {
                    errorExit();
                }
				appendLog([NSString stringWithFormat: @"Deleted secure (shadow) copy of %@", lastPartOfSource]);
            }
        }
    }
    
    
    //**************************************************************************************************************************
    // (10)
    // If requested, secure a single file or .tblk package
    if (   firstPath
        && ( ! secondPath )
        && ( ! deleteConfig )
        && ( ! setBundleVersion )  ) {
        
        // Make sure we are dealing with .tblks
        if (  ! [[firstPath pathExtension] isEqualToString: @"tblk"]  ) {
            appendLog([NSString stringWithFormat: @"Only .tblks may be copied or moved: Not a .tblk: %@", firstPath]);
            errorExit();
        }

        BOOL okSoFar = TRUE;
        NSString * ext = [firstPath pathExtension];
        if (  [ext isEqualToString: @"ovpn"] || [ext isEqualToString: @"conf"]  ) {
            if (  [firstPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
                okSoFar = okSoFar && checkSetOwnership(firstPath, NO, gRealUserID, gRealGroupID);
            } else {
                okSoFar = okSoFar && checkSetOwnership(firstPath, NO, 0, 0);
            }
            okSoFar = okSoFar && checkSetPermissions(firstPath, 0644, YES);
        } else if (  [ext isEqualToString: @"tblk"]  ) {
            BOOL isPrivate = [firstPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]];
            okSoFar = okSoFar && secureOneFolder(firstPath, isPrivate, gRealUserID);
        } else {
            appendLog([NSString stringWithFormat: @"trying to secure unknown item at %@", firstPath]);
            errorExit();
        }
        if (  ! okSoFar  ) {
            appendLog([NSString stringWithFormat: @"unable to secure %@", firstPath]);
            errorExit();
        }
    }
    
    //**************************************************************************************************************************
    // (11)
    // If requested, delete a single file or .tblk package (also deletes the shadow copy if deleting a private configuration)
    if (   firstPath
        && deleteConfig
        && ( ! setBundleVersion )  ) {
        NSString * ext = [firstPath pathExtension];
        if (  [ext isEqualToString: @"tblk"]  ) {
            if (  [gFileMgr fileExistsAtPath: firstPath]  ) {
                errorExitIfAnySymlinkInPath(firstPath, 6);
                if (  ! [gFileMgr tbRemoveFileAtPath: firstPath handler: nil]  ) {
                    appendLog([NSString stringWithFormat: @"unable to remove %@", firstPath]);
                } else {
                    appendLog([NSString stringWithFormat: @"removed %@", firstPath]);
                }
                
                // Delete shadow copy, too, if it exists
                if (  [firstPartOfPath(firstPath) isEqualToString: gPrivatePath]  ) {
                    appendLog([NSString stringWithFormat: @"DEBUG 005: firstPath prefix DID match:\n     %@\n     %@", firstPath, gPrivatePath]);
                    NSString * shadowCopyPath = [NSString stringWithFormat: @"%@/%@/%@",
                                                 L_AS_T_USERS,
                                                 NSUserName(),
                                                 lastPartOfPath(firstPath)];
                    if (  [gFileMgr fileExistsAtPath: shadowCopyPath]  ) {
                        errorExitIfAnySymlinkInPath(shadowCopyPath, 7);
                        if (  ! [gFileMgr tbRemoveFileAtPath: shadowCopyPath handler: nil]  ) {
                            appendLog([NSString stringWithFormat: @"unable to remove %@", shadowCopyPath]);
                        } else {
                            appendLog([NSString stringWithFormat: @"removed %@", shadowCopyPath]);
                        }
                    }
                } else {
                    appendLog([NSString stringWithFormat: @"DEBUG 005: firstPath prefix DID NOT match:\n     %@\n     %@", firstPath, gPrivatePath]);
                }
            }
        } else {
            appendLog([NSString stringWithFormat: @"trying to remove unknown item at %@", firstPath]);
            errorExit();
        }
    }
    
    //**************************************************************************************************************************
    // (12) If requested, copies the bundleVersion into the CFBundleVersion entry
    //                           and bundleShortVersionString into the CFBundleShortVersionString
    //                               in /Library/Application Support/Tunnelblick/Configuration Updates/Tunnelblick Configurations.bundle/Contents/Into.plist
    //                    and removes /Library/Application Support/Tunnelblick/Configuration Updates/Tunnelblick Configurations.bundle/Contents/Resources/Install
    //
    //                    This is done after installing updated .tblks so that Sparkle will not try to update again and we won't try to install the updates again
    
    if (  setBundleVersion  ) {
        if (  [gFileMgr fileExistsAtPath: CONFIGURATION_UPDATES_BUNDLE_PATH]  ) {
            NSString * libPlistPath = [CONFIGURATION_UPDATES_BUNDLE_PATH stringByAppendingPathComponent: @"Contents/Info.plist"];
            NSMutableDictionary * libDict = [NSDictionary dictionaryWithContentsOfFile: libPlistPath];
            
            BOOL changed = FALSE;
            
            NSString * libVersion = [libDict objectForKey: @"CFBundleVersion"];
            if (  libVersion  ) {
                if (  ! [libVersion isEqualToString: bundleVersion]  ) {
                    [libDict removeObjectForKey: @"CFBundleVersion"];
                    [libDict setObject: bundleVersion forKey: @"CFBundleVersion"];
                    changed = TRUE;
                    appendLog([NSString stringWithFormat: @"Tunnelblick Configurations.bundle CFBundleVersion has been set to %@", bundleVersion]);
                } else {
                    appendLog([NSString stringWithFormat: @"Tunnelblick Configurations.bundle CFBundleVersion is %@", bundleVersion]);
                }
            } else {
                appendLog([NSString stringWithFormat: @"no CFBundleVersion in %@", libPlistPath]);
            }
            
            libVersion = [libDict objectForKey: @"CFBundleShortVersionString"];
            if (  libVersion  ) {
                if (  ! [libVersion isEqualToString: bundleShortVersionString]  ) {
                    [libDict removeObjectForKey: @"CFBundleShortVersionString"];
                    [libDict setObject: bundleShortVersionString forKey: @"CFBundleShortVersionString"];
                    changed = TRUE;
                    appendLog([NSString stringWithFormat: @"Tunnelblick Configurations.bundle CFBundleShortVersionString has been set to %@", bundleShortVersionString]);
                } else {
                    appendLog([NSString stringWithFormat: @"Tunnelblick Configurations.bundle CFBundleShortVersionString is %@", bundleShortVersionString]);
                }
            } else {
                appendLog([NSString stringWithFormat: @"no CFBundleShortVersionString in %@", libPlistPath]);
            }
            
            if (  changed  ) {
                [libDict writeToFile: libPlistPath atomically: YES];
            }

            NSString * installFolderPath = [CONFIGURATION_UPDATES_BUNDLE_PATH stringByAppendingPathComponent: @"Contents/Resources/Install"];
            if (  [gFileMgr fileExistsAtPath: installFolderPath]  ) {
                if (  ! [gFileMgr tbRemoveFileAtPath: installFolderPath handler: nil]  ) {
                    appendLog([NSString stringWithFormat: @"unable to remove %@", installFolderPath]);
                } else {
                    appendLog([NSString stringWithFormat: @"removed %@", installFolderPath]);
                }
            }
                
        } else {
            appendLog([NSString stringWithFormat: @"could not find %@", CONFIGURATION_UPDATES_BUNDLE_PATH]);
        }
    }
    
    
    //**************************************************************************************************************************
    // DONE
    
    deleteFlagFile(AUTHORIZED_ERROR_PATH);
    deleteFlagFile(AUTHORIZED_RUNNING_PATH);
	closeLog();
    
    [pool release];
    exit(EXIT_SUCCESS);
}

//**************************************************************************************************************************
void safeCopyOrMovePathToPath(NSString * fromPath, NSString * toPath, BOOL moveNotCopy)
{
    // Copy the file or package to a ".temp" file/folder first, then rename it
    // This avoids a race condition: folder change handling code runs while copy is being made, so it sometimes can
    // see the .tblk (which has been copied) but not the config.ovpn (which hasn't been copied yet), so it complains.
    NSString * dotTempPath = [toPath stringByAppendingPathExtension: @"temp"];
    errorExitIfAnySymlinkInPath(dotTempPath, 3);
    [gFileMgr tbRemoveFileAtPath:dotTempPath handler: nil];
    if (  ! [gFileMgr tbCopyPath: fromPath toPath: dotTempPath handler: nil]  ) {
        appendLog([NSString stringWithFormat: @"Failed to copy %@ to %@", fromPath, dotTempPath]);
        [gFileMgr tbRemoveFileAtPath:dotTempPath handler: nil];
        errorExit();
    } else {
		appendLog([NSString stringWithFormat: @"Copied %@ to %@", fromPath, dotTempPath]);
	}
    
    // Now, if we are doing a move, delete the original file, to avoid a similar race condition that will cause a complaint
    // about duplicate configuration names.
    if (  moveNotCopy  ) {
        errorExitIfAnySymlinkInPath(fromPath, 4);
        if (  ! deleteThingAtPath(fromPath)  ) {
            errorExit();
        }
    }
    
    errorExitIfAnySymlinkInPath(toPath, 5);
    [gFileMgr tbRemoveFileAtPath:toPath handler: nil];
    if (  ! [gFileMgr tbMovePath: dotTempPath toPath: toPath handler: nil]  ) {
        appendLog([NSString stringWithFormat: @"Failed to rename %@ to %@", dotTempPath, toPath]);
        [gFileMgr tbRemoveFileAtPath:dotTempPath handler: nil];
        errorExit();
    } else {
        appendLog([NSString stringWithFormat: @"%@ %@ to %@", (moveNotCopy ? @"Moved" : @"Copied"), dotTempPath, toPath]);
    }
}

//**************************************************************************************************************************
BOOL deleteThingAtPath(NSString * path)
{
    errorExitIfAnySymlinkInPath(path, 8);
    if (  ! [gFileMgr tbRemoveFileAtPath: path handler: nil]  ) {
        appendLog([NSString stringWithFormat: @"Failed to delete %@", path]);
        return FALSE;
    } else {
        appendLog([NSString stringWithFormat: @"Deleted %@", path]);
    }
    
    return TRUE;
}


//**************************************************************************************************************************
BOOL moveContents(NSString * fromPath, NSString * toPath)
{
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: fromPath];
    NSString * file;
    while (  (file = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        if (  ! [file hasPrefix: @"."]  ) {
            NSString * fullFromPath = [fromPath stringByAppendingPathComponent: file];
            NSString * fullToPath   = [toPath   stringByAppendingPathComponent: file];
            if (  [gFileMgr fileExistsAtPath: fullToPath]  ) {
                appendLog([NSString stringWithFormat: @"Unable to move %@ to %@ because the destination already exists", fullFromPath, fullToPath]);
                return NO;
            } else {
                if (  ! [gFileMgr tbMovePath: fullFromPath toPath: fullToPath handler: nil]  ) {
                    appendLog([NSString stringWithFormat: @"Unable to move %@ to %@", fullFromPath, fullToPath]);
                    return NO;
                }
            }
        }
    }
    
    return YES;
}

//**************************************************************************************************************************
BOOL makeFileUnlockedAtPath(NSString * path)
{
    // Make sure the copy is unlocked
    NSDictionary * curAttributes;
    NSDictionary * newAttributes = [NSDictionary dictionaryWithObject: [NSNumber numberWithInt:0] forKey: NSFileImmutable];
    
    unsigned i;
    unsigned maxTries = 5;
    for (i=0; i <= maxTries; i++) {
        curAttributes = [gFileMgr tbFileAttributesAtPath: path traverseLink:YES];
        if (  ! [curAttributes fileIsImmutable]  ) {
            break;
        }
        [gFileMgr tbChangeFileAttributes: newAttributes atPath: path];
        sleep(1);
    }
    
    if (  [curAttributes fileIsImmutable]  ) {
        appendLog([NSString stringWithFormat: @"Failed to unlock %@ in %d attempts", path, maxTries]);
        return FALSE;
    }
    return TRUE;
}

void errorExitIfAnySymlinkInPath(NSString * path, int testPoint)
{
    NSString * curPath = path;
    while (   curPath
           && ! [curPath isEqualToString: @"/"]  ) {
        if (  [gFileMgr fileExistsAtPath: curPath]  ) {
            NSDictionary * fileAttributes = [gFileMgr tbFileAttributesAtPath: curPath traverseLink: NO];
            if (  [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
                appendLog([NSString stringWithFormat: @"Apparent symlink attack detected at test point %d: Symlink is at %@, full path being tested is %@", testPoint, curPath, path]);
                errorExit();
            }
        }
        
        curPath = [curPath stringByDeletingLastPathComponent];
    }
}

NSString * firstPartOfPath(NSString * path)
{
    NSArray * paths = [NSArray arrayWithObjects:
                       gPrivatePath,
                       gDeployPath,
                       L_AS_T_SHARED, nil];
    NSEnumerator * arrayEnum = [paths objectEnumerator];
    NSString * configFolder;
    while (  (configFolder = [arrayEnum nextObject])  ) {
        if (  [path hasPrefix: [configFolder stringByAppendingString: @"/"]]  ) {
            return configFolder;
        }
    }
    return nil;
}

NSString * lastPartOfPath(NSString * path)
{
    NSArray * paths = [NSArray arrayWithObjects:
                       gPrivatePath,
                       gDeployPath,
                       L_AS_T_SHARED, nil];
    NSEnumerator * arrayEnum = [paths objectEnumerator];
    NSString * configFolder;
    while (  (configFolder = [arrayEnum nextObject])  ) {
        if (  [path hasPrefix: [configFolder stringByAppendingString: @"/"]]  ) {
            if (  [path length] > [configFolder length]  ) {
                return [path substringFromIndex: [configFolder length]+1];
            } else {
                appendLog([NSString stringWithFormat: @"No display name in path '%@'", path]);
                return @"X";
            }
        }
    }
    return nil;
}

void secureL_AS_T_DEPLOY()
{
    appendLog([NSString stringWithFormat: @"Securing %@", L_AS_T_DEPLOY]);
    if (  checkSetOwnership(L_AS_T_DEPLOY, YES, 0, 0)  ) {
        if (  checkSetPermissions(L_AS_T_DEPLOY, 0755, YES)  ) {
            if (  secureOneFolder(L_AS_T_DEPLOY, NO, 0)  ) {
                appendLog([NSString stringWithFormat: @"Secured %@", L_AS_T_DEPLOY]);
            } else {
                appendLog([NSString stringWithFormat: @"Unable to secure %@", L_AS_T_DEPLOY]);
                errorExit();
            }
        } else {
            appendLog([NSString stringWithFormat: @"Unable to set permissions on %@", L_AS_T_DEPLOY]);
            errorExit();
        }
    } else {
        appendLog([NSString stringWithFormat: @"Unable to set ownership on %@ and its contents", L_AS_T_DEPLOY]);
        errorExit();
    }
}

// Returns array of paths to Deploy backups. The paths end in the folder that contains TunnelblickBackup
NSArray * pathsForDeployBackups(void)
{
    NSMutableArray * result = [NSMutableArray arrayWithCapacity: 10];
	NSString * deployBackupPath = L_AS_T_BACKUP;
    NSMutableString * path = [NSMutableString stringWithCapacity: 1000];
	BOOL isDir;
	NSString * file;
	NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: deployBackupPath];
	while (  (file = [dirEnum nextObject])  ) {
		[dirEnum skipDescendents];
		NSString * fullPath = [deployBackupPath stringByAppendingPathComponent: file];
		if (   [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
			&& isDir
			&& itemIsVisible(fullPath)  ) {
            // Chase down this folder chain until we see the Deploy folder, then save the
            // path to and including the Deploy folder
            NSString * file2;
            NSDirectoryEnumerator * dirEnum2 = [gFileMgr enumeratorAtPath: fullPath];
            while (  (file2 = [dirEnum2 nextObject])  ) {
                NSString * fullPath2 = [fullPath stringByAppendingPathComponent: file2];
                if (   [gFileMgr fileExistsAtPath: fullPath2 isDirectory: &isDir]
                    && isDir
                    && itemIsVisible(fullPath)  ) {
                    NSArray * pathComponents = [fullPath2 pathComponents];
                    if (   [[pathComponents objectAtIndex: [pathComponents count] - 1] isEqualToString: @"Deploy"]
                        && [[pathComponents objectAtIndex: [pathComponents count] - 2] isEqualToString: @"TunnelblickBackup"]
                        ) {
                        unsigned i;
                        for (  i=0; i<[pathComponents count]; i++  ) {
                            [path appendString: [pathComponents objectAtIndex: i]];
							if (   (i != 0)
								&& (i != [pathComponents count] - 1)  ) {
								[path appendString: @"/"];
							}
                        }
                        break;
                    }
                }
            }
            if (  [path hasPrefix: [fullPath stringByAppendingString: @"/"]]  ) {
                [result addObject: [NSString stringWithString: path]];
            } else {
                appendLog([NSString stringWithFormat: @"Unrecoverable error dealing with Deploy backups"]);
                return  nil;
            }
            [path setString: @""];
        }
    }
    
    return result;
}

// Returns nil on error, or a possibly empty array with paths of the latest non-duplicate Deploy backups that can be used by a copy of Tunnelblick
NSArray * pathsForLatestNonduplicateDeployBackups(void)
{
    // Get a list of paths to Deploys that may include duplicates (identical Deploys)
    NSArray * listWithDupes = pathsForDeployBackups();
    if (  ! listWithDupes  ) {
        return nil;
    }
    
    if (  [listWithDupes count] == 0  ) {
        return listWithDupes;
    }
    
    // Get a list of those paths that have a Tunnelblick that can use them (even if it has been renamed)
    NSMutableArray * listThatTunnelblickCanUseWithDupes = [NSMutableArray arrayWithCapacity: [listWithDupes count]];
    unsigned i;
    for (  i=0; i<[listWithDupes count]; i++) {
        NSString * backupPath = [listWithDupes objectAtIndex: i];
        NSString * pathToDirWithTunnelblick = [[[backupPath substringFromIndex: [L_AS_T_BACKUP length]]
                                                stringByDeletingLastPathComponent]	// Remove Deploy
                                               stringByDeletingLastPathComponent];		// Remove TunnelblickBackup];
        
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: pathToDirWithTunnelblick];
        NSString * file;
        while (  (file = [dirEnum nextObject])  ) {
            [dirEnum skipDescendents];
            if (  [[file pathExtension] isEqualToString: @"app"]  ) {
                NSString * openvpnstartPath = [[[[pathToDirWithTunnelblick
                                                  stringByAppendingPathComponent: file]
                                                 stringByAppendingPathComponent: @"Contents"]
                                                stringByAppendingPathComponent: @"Resources"]
                                               stringByAppendingPathComponent: @"openvpnstart"];
                if (  [gFileMgr fileExistsAtPath: openvpnstartPath]  ) {
                    [listThatTunnelblickCanUseWithDupes addObject: backupPath];
                }
            }
        }
    }
    
    NSMutableArray * pathsToRemove = [NSMutableArray arrayWithCapacity: 10];
    NSMutableArray * results       = [NSMutableArray arrayWithCapacity: 10];
    
    for (  i=0; i<[listThatTunnelblickCanUseWithDupes count]; i++  ) {
        
        // For each path in listThatTunnelblickCanUseWithDupes, find the path to the latest Deploy which is identical to it and put that in results
        
        NSString * latestPath = [listThatTunnelblickCanUseWithDupes objectAtIndex: i];
        NSDate   * latestDate = [[gFileMgr tbFileAttributesAtPath: latestPath traverseLink: NO] objectForKey: NSFileModificationDate];
        if (  ! latestDate  ) {
            appendLog([NSString stringWithFormat: @"No last modified date for %@", latestPath]);
            return nil;
        }
        
        unsigned j;
        for (  j=0; j<[listThatTunnelblickCanUseWithDupes count]; j++  ) {
            
            // Look for a folder which is identical but has a later date
            
            if (  i != j  ) {
                NSString * thisPath = [listThatTunnelblickCanUseWithDupes objectAtIndex: j];
                if ( ! [results containsObject: thisPath]  ) {
                    if (  ! [pathsToRemove containsObject: thisPath]  ) {
                        if (  [gFileMgr contentsEqualAtPath: latestPath andPath: thisPath]  ) {
                            NSDate   * thisDate = [[gFileMgr tbFileAttributesAtPath: thisPath traverseLink: NO] objectForKey: NSFileModificationDate];
                            if ( ! thisDate  ) {
                                appendLog([NSString stringWithFormat: @"No last modified date for %@", thisPath]);
                                return nil;
                            }
                            if (  [latestDate compare: thisDate] == NSOrderedAscending  ) {
                                // Have a later version of the same
                                latestPath = thisPath;
                                latestDate = thisDate;
                            }
                        }
                    }
                }
            }
            
            [results addObject: latestPath];
			[pathsToRemove addObject: latestPath];
        }
    }
    
    return results;
}

BOOL tunnelblickTestPrivateOnlyHasTblks(void)
{
	NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: gPrivatePath];
	NSString * file;
	while (  (file = [dirEnum nextObject])  ) {
		if (  [[file pathExtension] isEqualToString: @"tblk"]  ) {
			[dirEnum skipDescendents];
		} else {
			if (   [[file pathExtension] isEqualToString: @"ovpn"]
				|| [[file pathExtension] isEqualToString: @"conf"]  ) {
				return NO;
			}
		}
	}
	
	return YES;
}

BOOL copyTblksToNewFolder(NSString * newFolder)
{
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: gPrivatePath];
    NSString * file;
    
    while (  (file = [dirEnum nextObject])  ) {
        NSString * inPath = [gPrivatePath stringByAppendingPathComponent: file];
        if (  itemIsVisible(inPath)  ) {
            if (  [[file pathExtension] isEqualToString: @"tblk"]  ) {
                NSString * outPath = [newFolder stringByAppendingPathComponent: file];
				NSString * outPathFolder = [outPath stringByDeletingLastPathComponent];
				if (  ! createDirWithPermissionAndOwnership(outPathFolder, PERMS_PRIVATE_PRIVATE_FOLDER, gRealUserID, ADMIN_GROUP_ID)  ) {
                    appendLog([NSString stringWithFormat: @"Unable to create %@", outPathFolder]);
                    return FALSE;
				}
                if (  ! [gFileMgr tbCopyPath: inPath toPath: outPath handler: nil]  ) {
                    appendLog([NSString stringWithFormat: @"Unable to copy %@ to %@", inPath, outPath]);
                    return FALSE;
                } else {
                    appendLog([NSString stringWithFormat: @"Copied %@", file]);
				}
                
                [dirEnum skipDescendents];
            }
        }
    }
    
    return TRUE;
}

BOOL convertAllPrivateOvpnAndConfToTblk(void)
{
    NSString * newFolder = [[gPrivatePath stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"NewConfigurations"];
    NSString * logPath = [newFolder stringByAppendingPathComponent: @"Conversion.log"];
    
    [gFileMgr tbRemoveFileAtPath: logPath   handler: nil];
    [gFileMgr tbRemoveFileAtPath: newFolder handler: nil];
    
	ConfigurationConverter * converter = [[ConfigurationConverter alloc] init];
	
	BOOL haveDoneConversion = FALSE;
	
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: gPrivatePath];
    NSString * file;
    while (  (file = [dirEnum nextObject])  ) {
        NSString * inPath = [gPrivatePath stringByAppendingPathComponent: file];
		NSString * ext = [file pathExtension];
        if (  itemIsVisible(inPath)  ) {
            if (  [ext isEqualToString: @"tblk"]  ) {
                [dirEnum skipDescendents];
            } else if (   [ext isEqualToString: @"ovpn"]
                       ||  [ext isEqualToString: @"conf"]  ) {
                NSString * fileWithoutExtension = [file stringByDeletingPathExtension];
                NSString * outTblkPath = [newFolder stringByAppendingPathComponent:
										  [fileWithoutExtension stringByAppendingPathExtension: @"tblk"]];
                NSString * outTblkPathButInExistingConfigurationsFolder = [gPrivatePath stringByAppendingPathComponent:
										  [fileWithoutExtension stringByAppendingPathExtension: @"tblk"]];
                if (   [gFileMgr fileExistsAtPath: outTblkPath]
					|| [gFileMgr fileExistsAtPath: outTblkPathButInExistingConfigurationsFolder]  ) {
					fileWithoutExtension = [[fileWithoutExtension stringByAppendingString: @" from "]
											stringByAppendingString: ext];
					outTblkPath = [newFolder stringByAppendingPathComponent:
								   [fileWithoutExtension stringByAppendingPathExtension: @"tblk"]];
					outTblkPathButInExistingConfigurationsFolder = [gPrivatePath stringByAppendingPathComponent:
																	[fileWithoutExtension stringByAppendingPathExtension: @"tblk"]];
					if (   [gFileMgr fileExistsAtPath: outTblkPath]
						|| [gFileMgr fileExistsAtPath: outTblkPathButInExistingConfigurationsFolder]  ) {
						appendLog([NSString stringWithFormat: @"Unable to construct name for a .tblk for %@", file]);
						[converter release];
						return FALSE;
					}
				}
				NSString * inConfPath = [gPrivatePath stringByAppendingPathComponent: file];
                
				if (  ! createDirWithPermissionAndOwnership(newFolder, PERMS_PRIVATE_SELF, gRealUserID, ADMIN_GROUP_ID)  ) {
                    appendLog([NSString stringWithFormat: @"Unable to create %@", newFolder]);
					[converter release];
                    return FALSE;
                };
                
				BOOL convertedOK = [converter convertConfigPath: inConfPath
													 outputPath: outTblkPath
													    logFile: gLogFile];
                if (  ! convertedOK  ) {
                    appendLog([NSString stringWithFormat: @"Unable to convert %@ to a Tunnelblick private Configuration", inConfPath]);
                    [converter release];
                    return FALSE;
                }
				
				haveDoneConversion = TRUE;
            }
        }
    }
	
	[converter release];
    
	if (  haveDoneConversion  ) {
		if ( ! copyTblksToNewFolder(newFolder)  ) {
            appendLog(@"Unable to copy existing private .tblk configurations");
            return FALSE;
		}
		
		NSDateFormatter * f = [[[NSDateFormatter alloc] init] autorelease];
		[f setFormatterBehavior: NSDateFormatterBehavior10_4];
		[f setDateFormat: @"yyyy-MM-dd hh.mm.ss"];
		NSString * dateTimeString = [f stringFromDate: [NSDate date]];
		
		NSString * oldFolder = [[newFolder stringByDeletingLastPathComponent]
								stringByAppendingPathComponent:
								[NSString stringWithFormat: @"Configurations before conversion %@", dateTimeString]];
		if (  [gFileMgr tbMovePath: gPrivatePath toPath: oldFolder handler: nil]  ) {
			if  (  [gFileMgr tbMovePath: newFolder toPath: gPrivatePath handler: nil]  ) {
                return TRUE;
			} else {
				[gFileMgr tbMovePath: oldFolder toPath: gPrivatePath handler: nil]; // Try to restore original setup
				appendLog([NSString stringWithFormat: @"Unable to rename %@ to %@", newFolder, gPrivatePath]);
                return FALSE;
			}
		} else {
			appendLog([NSString stringWithFormat: @"Unable to rename %@ to %@", gPrivatePath, oldFolder]);
			return FALSE;
		}
	} else {
        appendLog(@"No private .ovpn or .conf configurations to be converted");
		[gFileMgr tbRemoveFileAtPath: newFolder handler: nil];
    }
    
    return TRUE;
}
