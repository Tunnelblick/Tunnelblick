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
//     installer bitmask [ targetPath   [sourcePath] ]
//
// where
//   bitMask (See defines.h for bit assignments) -- DETERMINES WHAT THE INSTALLER WILL DO:
//
//     INSTALLER_COPY_APP:      set to copy this app to /Applications/Tunnelblick.app
//                                  (Any existing /Applications/Tunnelblick.app will be moved to the Trash)
//
//     INSTALLER_COPY_BUNDLE:   set to copy this app's Resources/Tunnelblick Configurations.bundle to /Library/Application Support/Tunnelblick/Configuration Updates
//                                  (Will only be done if this app's Tunnelblick Configurations.bundle's version # is higher, or INSTALLER_COPY_APP is set)
//
//     INSTALLER_SET_VERSION:   set to store bundleVersion as a new value for CFBundleVersion 
//                                       and bundleVersionString as a new value for CFBundleShortVersionString
//                                     in /Library/Application Support/Tunnelblick/Configuration Updates/Tunnelblick Configurations.bundle/Contents/Into.plist
//                                     and remove Contents/Installer of the bundle
//
//     INSTALLER_SECURE_APP:    set to secure Tunnelblick.app and all of its contents and update L_AS_T/Deploy if appropriate
//                                  (also set if INSTALLER_COPY_APP)
//
//     INSTALLER_SECURE_TBLKS:  set to secure all .tblk packages in Configurations, Shared, and the alternate configuration path
//
//     INSTALLER_MOVE_NOT_COPY: set to move, instead of copy, if target path and source path are supplied
//
//     INSTALLER_DELETE:        set to delete target path
//
//
// bundleVersion       is a string to replace the CFBundleVersion
// bundleVersionString is a string to replace the CFBundleShortVersionString
//                                    in /Library/Application Support/Tunnelblick/Configuration Updates/Tunnelblick Configurations.bundle/Contents/Into.plist
//
// targetPath          is the path to a configuration (.ovpn or .conf file, or .tblk package) to be secured
// sourcePath          is the path to be copied or moved to targetPath before securing targetPath
//
// It does the following:
//      (1) IF AND ONLY IF THE FOLLOWING ARE TRUE:
//             INSTALLER_COPY_APP is TRUE
//             There is no Deploy folder in the app
//             There is no /Library/Application Support/Tunnelblick/Backup folder
//             There are no private configurations that are not .tblks
//          THEN this app is copied to /Applications
//      (2) (Removed)
//      (3) Moves the contents of the old configuration folder at ~/Library/openvpn to ~/Library/Application Support/Tunnelblick/Configurations
//      (4) Creates /Library/Application Support/Tunnelblick/Shared if it doesn't exist and makes sure it is secured
//      (5) Creates the log directory if it doesn't exist and makes sure it is secured
//      (6) If INSTALLER_COPY_BUNDLE, if /Resources/Tunnelblick Configurations.bundle exists, copies it to /Library/Application Support/T/Configuration Updates
//      (7) If INSTALLER_SECURE_APP, secures Tunnelblick.app by setting the ownership and permissions of its components.
//      (8) If INSTALLER_COPY_APP or INSTALLER_SECURE_APP, deals with Deploy:
//             * Prunes any duplicate copies of Deploy in L_AS_T/Backup
//             * If exactly one copy of Deploy is in L_AS_T/Backup, copies it to gDeployPath and removes L_AS_T/Backup
//             * Updates the gDeployPath folder from this app if appropriate (using version # or modification date) and secures it
//      (9) If INSTALLER_SECURE_TBLKS, secures all .tblk packages in the following folders:
//           /Library/Application Support/Tunnelblick/Shared
//           ~/Library/Application Support/Tunnelblick/Configurations (actually, these are now "unsecured"!
//           /Library/Application Support/Tunnelblick/Users/<username>
//     (10) If INSTALLER_SET_VERSION is clear and INSTALLER_DELETE is clear and sourcePath is given,
//             copies or moves sourcePath to targetPath. Copies unless INSTALLER_MOVE_NOT_COPY is set.  (Also copies or moves the shadow copy if deleting a private configuration)
//     (11) If INSTALLER_SET_VERSION is clear and INSTALLER_DELETE is clear and targetPath is given,
//             secures the .ovpn or .conf file or a .tblk package at targetPath
//     (12) If INSTALLER_SET_VERSION is clear and INSTALLER_DELETE is set and targetPath is given,
//             deletes the .ovpn or .conf file or .tblk package at targetPath (also deletes the shadow copy if deleting a private configuration)
//     (13) If INSTALLER_SET_VERSION is set, copies the bundleVersion into the CFBundleVersion entry and bundleShortVersionString into the CFBundleShortVersionString entry
//                                           in /Library/Application Support/Tunnelblick/Configuration Updates/Tunnelblick Configurations.bundle/Contents/Into.plist
//
// When finished (or if an error occurs), the file /tmp/tunnelblick-authorized-running is deleted to indicate the program has finished
//
// Notes: (2), (3), (4), and (5) are done each time this command is invoked if they are needed (self-repair).
//        (10) is done when creating a shadow configuration file
//                     or copying a .tblk to install it
//                     or moving a .tblk to make it private or shared
//        (11) is done when repairing a shadow configuration file or after copying or moving a .tblk

NSArray       * gKeyAndCrtExtensions;
NSFileManager * gFileMgr;                     // [NSFileManager defaultManager]
NSString      * gPrivatePath;                 // Path to ~/Library/Application Support/Tunnelblick/Configurations
NSString      * gDeployPath;                  // Path to /Library/Application Support/Tunnelblick/Deploy/<application-name>
NSString      * gAppConfigurationsBundlePath; // Path to Tunnelblick.app/Contents/Resources/Tunnelblick Configurations.bundle (after copy if INSTALLER_COPY_APP is set)
uid_t           gRealUserID;                  // User ID & Group ID for the real user (i.e., not "root:wheel", which is what we are running as)
gid_t           gRealGroupID;
NSAutoreleasePool * pool;

void errorExitIfAnySymlinkInPath(NSString * path, int testPoint);
BOOL checkSetOwnership(NSString * path, BOOL deeply, uid_t uid, gid_t gid);
BOOL checkSetItemOwnership(NSString * path, NSDictionary * atts, uid_t uid, gid_t gid, BOOL traverseLink);
BOOL checkSetPermissions(NSString * path, NSString * permsShouldHave, BOOL fileMustExist);
BOOL createDirWithPermissionAndOwnership(NSString * dirPath, mode_t permissions, uid_t owner, gid_t group);
BOOL createSymLink(NSString * fromPath, NSString * toPath);
void deleteFlagFile(void);
BOOL itemIsVisible(NSString * path);
BOOL secureOneFolder(NSString * path);
BOOL makeFileUnlockedAtPath(NSString * path);
BOOL moveContents(NSString * fromPath, NSString * toPath);
void errorExit();
NSString * firstPartOfPath(NSString * path);
NSString * lastPartOfPath(NSString * path);
void safeCopyOrMovePathToPath(NSString * fromPath, NSString * toPath, BOOL moveNotCopy);
BOOL deleteThingAtPath(NSString * path);
NSArray * pathsForLatestNonduplicateDeployBackups(void);
void secureL_AS_T_DEPLOY();
NSArray * pathsForDeployBackups(void);

int main(int argc, char *argv[]) 
{
	pool = [NSAutoreleasePool new];
    
    NSBundle * ourBundle = [NSBundle mainBundle];
	NSString * resourcesPath = [ourBundle bundlePath];
    NSArray  * execComponents = [resourcesPath pathComponents];
    if (  [execComponents count] < 3  ) {
        NSLog(@"Tunnelblick: too few execComponents; resourcesPath = %@", resourcesPath);
        errorExit();
    }
	NSString * ourAppName = [execComponents objectAtIndex: [execComponents count] - 1];
	if (  [ourAppName hasSuffix: @".app"]  ) {
		ourAppName = [ourAppName substringToIndex: [ourAppName length] - 4];
	}
	gDeployPath = [[L_AS_T_DEPLOY stringByAppendingPathComponent: ourAppName] copy];
    
	
#ifdef TBDebug
    NSLog(@"Tunnelblick: WARNING: This is an insecure copy of installer to be used for debugging only!");
#else
    if (   ([execComponents count] != 5)
        || [[execComponents objectAtIndex: 0] isNotEqualTo: @"/"]
        || [[execComponents objectAtIndex: 1] isNotEqualTo: @"Applications"]
        //                                                  Allow any name for Tunnelblick.app
        || [[execComponents objectAtIndex: 3] isNotEqualTo: @"Contents"]
        || [[execComponents objectAtIndex: 4] isNotEqualTo: @"Resources"]
        ) {
        NSLog(@"Tunnelblick must be in /Applications (bundlePath = %@", resourcesPath);
        errorExit();
    }
#endif
    
    gKeyAndCrtExtensions = KEY_AND_CRT_EXTENSIONS;
    gFileMgr = [NSFileManager defaultManager];
    gPrivatePath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Tunnelblick/Configurations/"] copy];
    
    if (  (argc < 2)  || (argc > 4)  ) {
        NSLog(@"Tunnelblick: Wrong number of arguments -- expected 1 to 3, given %d", argc-1);
        errorExit();
    }
    
    unsigned arg1 = (unsigned) strtol(argv[1], NULL, 10);
    BOOL copyApp          = arg1 & INSTALLER_COPY_APP;
    BOOL secureTblks      = arg1 & INSTALLER_SECURE_TBLKS;
    BOOL moveNotCopy      = arg1 & INSTALLER_MOVE_NOT_COPY;
    BOOL copyBundle       = arg1 & INSTALLER_COPY_BUNDLE;
    BOOL setBundleVersion = arg1 & INSTALLER_SET_VERSION;
    BOOL deleteConfig     = arg1 & INSTALLER_DELETE;
    
    // secureApp if asked specifically or copying app
    BOOL secureApp = (arg1 & INSTALLER_SECURE_APP) || copyApp;
	
    // If we copy the .app to /Applications, other changes to the .app affect THAT copy, otherwise they affect the currently running copy
    NSString * appResourcesPath;
    if (  copyApp  ) {
        appResourcesPath = @"/Applications/Tunnelblick.app/Contents/Resources";
    } else {
        appResourcesPath = [[gFileMgr stringWithFileSystemRepresentation: argv[0] length: strlen(argv[0])] stringByDeletingLastPathComponent];
    }
    
    gAppConfigurationsBundlePath    = [appResourcesPath stringByAppendingPathComponent:@"Tunnelblick Configurations.bundle"];

    gRealUserID  = getuid();
    gRealGroupID = getgid();
    
    BOOL isDir;
    
    NSString * firstPath = nil;
    if (  argc > 2  ) {
        firstPath = [gFileMgr stringWithFileSystemRepresentation: argv[2] length: strlen(argv[2])];
        if (  ! [firstPath hasPrefix: gPrivatePath]  ) {
            errorExitIfAnySymlinkInPath(firstPath, 10);
        }
    }
    NSString * secondPath = nil;
    if (  argc > 3  ) {
        secondPath = [gFileMgr stringWithFileSystemRepresentation: argv[3] length: strlen(argv[3])];
        if (  ! [secondPath hasPrefix: gPrivatePath]  ) {
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
            NSLog(@"Tunnelblick: Both a CFBundleVersion and a CFBundleShortVersionString are required to set the bundle version");
        }
    }
	
    //**************************************************************************************************************************
    // (1)
    // If INSTALLER_COPY_APP is set:
    //    Move /Applications/Tunnelblick.app to the Trash, then copy this app to /Applications/Tunnelblick.app
    
    if (  copyApp  ) {
        NSString * currentPath = [[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        NSString * targetPath = @"/Applications/Tunnelblick.app";
        if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
            errorExitIfAnySymlinkInPath(targetPath, 1);
            if (  [[NSWorkspace sharedWorkspace] performFileOperation: NSWorkspaceRecycleOperation
                                                               source: @"/Applications"
                                                          destination: @""
                                                                files: [NSArray arrayWithObject:@"Tunnelblick.app"]
                                                                  tag: nil]  ) {
                NSLog(@"Tunnelblick: Moved %@ to the Trash", targetPath);
            } else {
                NSLog(@"Tunnelblick: Unable to move %@ to the Trash", targetPath);
                errorExit();
            }
        }
        
        if (  ! [gFileMgr tbCopyPath: currentPath toPath: targetPath handler: nil]  ) {
            NSLog(@"Tunnelblick: Unable to copy %@ to %@", currentPath, targetPath);
            errorExit();
        } else {
            NSLog(@"Tunnelblick: Copied %@ to %@", currentPath, targetPath);
        }
    }
        
    //**************************************************************************************************************************
	// (2) (Removed)
	
    //**************************************************************************************************************************
    // (3)
    // Deal with migration to new configuration path
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
                            NSLog(@"Tunnelblick: Moved contents of %@ to %@", oldConfigDirPath, newConfigDirPath);
                            secureTblks = TRUE; // We may have moved some .tblks, so we should secure them
                            // Delete the old configuration folder
                            if (  ! [gFileMgr tbRemoveFileAtPath:oldConfigDirPath handler: nil]  ) {
                                NSLog(@"Tunnelblick: Unable to remove %@", oldConfigDirPath);
                                errorExit();
                            }
                        } else {
                            NSLog(@"Tunnelblick: Unable to move all contents of %@ to %@", oldConfigDirPath, newConfigDirPath);
                            errorExit();
                        }
                    } else {
                        NSLog(@"Tunnelblick: %@ is not a symbolic link or a folder", oldConfigDirPath);
                        errorExit();
                    }
                }
            }
        } else {
            NSLog(@"Tunnelblick: Warning: %@ exists but is not a folder", newConfigDirPath);
            if ( secureTblks ) {
                errorExit();
            }
        }
    } else {
        NSLog(@"Tunnelblick: Warning: Private configuration folder %@ does not exist", newConfigDirPath);
        if ( secureTblks ) {
            errorExit();
        }
    }
    
    //**************************************************************************************************************************
    // (4)
    // Create /Library/Application Support/Tunnelblick/Shared if it does not already exist, and make sure it is owned by root with 755 permissions
    
    if (  ! createDirWithPermissionAndOwnership(L_AS_T_SHARED, 0755, 0, 0)  ) {
        errorExit();
    }
    
    //**************************************************************************************************************************
    // (5)
    // Create log directory if it does not already exist, and make sure it is owned by root with 755 permissions
    
    if (  ! createDirWithPermissionAndOwnership(LOG_DIR, 0755, 0, 0)  ) {
        errorExit();
    }
    
    //**************************************************************************************************************************
    // (6)
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
                    NSLog(@"Tunnelblick: No CFBundleVersion in %@", gAppConfigurationsBundlePath);
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
                        NSLog(@"Tunnelblick: Unable to delete %@", CONFIGURATION_UPDATES_BUNDLE_PATH);
                        errorExit();
                    }
                }
                if (  ! [gFileMgr tbCopyPath: gAppConfigurationsBundlePath toPath: CONFIGURATION_UPDATES_BUNDLE_PATH handler: nil]  ) {
                    NSLog(@"Tunnelblick: Unable to copy %@ to %@", gAppConfigurationsBundlePath, CONFIGURATION_UPDATES_BUNDLE_PATH);
                    errorExit();
                } else {
                    NSLog(@"Tunnelblick: Copied %@ to %@", gAppConfigurationsBundlePath, CONFIGURATION_UPDATES_BUNDLE_PATH);
                }
                
                // Set ownership and permissions
                if ( ! checkSetOwnership(CONFIGURATION_UPDATES_BUNDLE_PATH, YES, 0, 0)  ) {
                    errorExit();
                }
                if ( ! checkSetPermissions(CONFIGURATION_UPDATES_BUNDLE_PATH, @"755", YES)  ) {
                    errorExit();
                }
            }
        }
    }
    
    //**************************************************************************************************************************
    // (7)
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
        
        okSoFar = okSoFar && checkSetPermissions(infoPlistPath,             @"644", YES);
        
        okSoFar = okSoFar && checkSetPermissions(openvpnPath,               @"755", YES);
        
        okSoFar = okSoFar && checkSetPermissions(atsystemstartPath,         @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(installerPath,             @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(leasewatchPath,            @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(leasewatch3Path,           @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(pncPath,                   @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(ssoPath,                   @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(clientUpPath,              @"744", NO);
        okSoFar = okSoFar && checkSetPermissions(clientDownPath,            @"744", NO);
        okSoFar = okSoFar && checkSetPermissions(clientNoMonUpPath,         @"744", NO);
        okSoFar = okSoFar && checkSetPermissions(clientNoMonDownPath,       @"744", NO);
        okSoFar = okSoFar && checkSetPermissions(clientNewUpPath,           @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewDownPath,         @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewRoutePreDownPath, @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt1UpPath,       @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt1DownPath,     @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt2UpPath,       @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt2DownPath,     @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt3UpPath,       @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewAlt3DownPath,     @"744", YES);
                
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
                    okSoFar = okSoFar && checkSetPermissions(fullPath, @"755", YES);
                    
                    NSString * thisOpenvpnPath = [fullPath stringByAppendingPathComponent: @"openvpn"];
                    okSoFar = okSoFar && checkSetPermissions(thisOpenvpnPath, @"755", YES);
                    
                    NSString * thisOpenvpnDownRootPath = [fullPath stringByAppendingPathComponent: @"openvpn-down-root.so"];
                    okSoFar = okSoFar && checkSetPermissions(thisOpenvpnDownRootPath, @"744", NO);
                }
            }
        }
        
        // Check/set the app's Deploy folder
        if (   [gFileMgr fileExistsAtPath: deployPath isDirectory: &isDir]
            && isDir  ) {
            okSoFar = okSoFar && secureOneFolder(deployPath);
        }
		
		// Save this for last, so if something goes wrong, it isn't SUID inside a damaged app
		if (  okSoFar  ) {
			okSoFar = checkSetPermissions(openvpnstartPath, @"4555", YES);
		}
		
		if (  ! okSoFar  ) {
            NSLog(@"Tunnelblick: Unable to secure Tunnelblick.app");
            errorExit();
        }
    }
    
    //**************************************************************************************************************************
    // (8) Deal with Deploy folders
    //     * Secure the old Deploy backups
    //     * If INSTALLER_COPY_APP or INSTALLER_SECURE_APP, deals with Deploy:
    //       * If this app has a Deploy folder, copies it to gDeployPath and secures the copy
    //       * If gDeployPath doesn't exist and there is exactly one unique Deploy backup, copies it to gDeployPath and secures it
    
    if ( secureApp ) {
        
        // Secure the old Deploy backups
        NSArray * deployBackups = pathsForDeployBackups();
		if (  ! deployBackups  ) {
			NSLog(@"Tunnelblick: Error occurred while looking for Deploy backups");
			errorExit();
		}
		NSLog(@"Tunnelblick: %u Deploy backup folders to secure", [deployBackups count]);

		BOOL okSoFar = TRUE;
		NSString * folderPath;
		NSEnumerator * e = [deployBackups objectEnumerator];
		while (  (folderPath = [e nextObject])  ) {
			okSoFar = okSoFar && secureOneFolder(folderPath);
		}
		
		if (  ! okSoFar  ) {
			NSLog(@"Tunnelblick: Unable to secure Deploy backups");
			errorExit();
		}
        
        // If this app has a Deploy folder, copy it to gDeployPath
        NSString * thisAppDeployPath = [[NSBundle mainBundle] pathForResource: @"Deploy" ofType: nil];
        if (  [gFileMgr fileExistsAtPath: thisAppDeployPath]  ) {
            [gFileMgr tbRemoveFileAtPath: gDeployPath handler: nil];
            if (  [gFileMgr tbCopyPath: thisAppDeployPath toPath: gDeployPath handler: nil]  ) {
                NSLog(@"Tunnelblick: Updated Deploy with copy in %@", [[[thisAppDeployPath stringByDeletingLastPathComponent] // delete Deploy
                                                                stringByDeletingLastPathComponent]                    // delete Resources
                                                               stringByDeletingLastPathComponent]);                  // delete Contents
                NSLog(@"Tunnelblick: Updated Deploy with copy in %@", [[[thisAppDeployPath stringByDeletingLastPathComponent] // delete Deploy
                                                                stringByDeletingLastPathComponent]                    // delete Resources
                                                               stringByDeletingLastPathComponent]);                  // delete Contents
            } else {
                NSLog(@"Tunnelblick: Error ocurred copying %@ to %@", thisAppDeployPath, gDeployPath);
                errorExit();
            }
            
            secureL_AS_T_DEPLOY();
            
        } else {
            
            NSArray * backupDeployPathsWithoutDupes = pathsForLatestNonduplicateDeployBackups();
			if (  ! backupDeployPathsWithoutDupes  ) {
				errorExit();
			}
            NSLog(@"Tunnelblick: %u unique Deploy Backups", [backupDeployPathsWithoutDupes count]);
            
            // If there is only one unique Deploy backup and gDeployPath doesn't exist, copy it to gDeployPath
            if (   ([backupDeployPathsWithoutDupes count] == 1)
                && ( ! [gFileMgr fileExistsAtPath: gDeployPath] )  ) {
                NSString * pathToCopy = [backupDeployPathsWithoutDupes objectAtIndex: 0];
                [gFileMgr tbRemoveFileAtPath: gDeployPath handler: nil];
                if (  [gFileMgr tbCopyPath: pathToCopy toPath: gDeployPath handler: nil]  ) {
                    NSLog(@"Tunnelblick: Copied the only non-duplicate Deploy backup folder %@ to %@", pathToCopy, gDeployPath);
                } else {
                    NSLog(@"Tunnelblick: Error occurred copying the only Deploy backup folder %@ to %@", pathToCopy, gDeployPath);
                    errorExit();
                }
                
                secureL_AS_T_DEPLOY();
            }
        }
    }
    
    //**************************************************************************************************************************
    // (9)
    // If requested, secure all .tblk packages
    if (  secureTblks  ) {
        NSString * altPath     = [L_AS_T_USERS stringByAppendingPathComponent: NSUserName()];

        // First, copy any .tblks that are in private to alt (unless they are already there)
        NSString * file;
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: gPrivatePath];
        while (  (file = [dirEnum nextObject])  ) {
			if (  [[file pathExtension] isEqualToString: @"tblk"]  ) {
				[dirEnum skipDescendents];
                NSString * privateTblkPath = [gPrivatePath stringByAppendingPathComponent: file];
                NSString * altTblkPath     = [altPath stringByAppendingPathComponent: file];
                if (  ! [gFileMgr fileExistsAtPath: altTblkPath]  ) {
					if (  ! createDirWithPermissionAndOwnership([altTblkPath stringByDeletingLastPathComponent], 0755, 0, 0)  ) {
						errorExit();
					}
                    if (  [gFileMgr tbCopyPath: privateTblkPath toPath: altTblkPath handler: nil]  ) {
                        NSLog(@"Tunnelblick: Created shadow backup of %@", privateTblkPath);
                    } else {
                        NSLog(@"Tunnelblick: Unable to create shadow backup of %@", privateTblkPath);
                        errorExit();
                    }
				}
            }
        }
        
        // Now secure Shared tblks, and shadow copies of private tblks, 
        
        NSArray * foldersToSecure = [NSArray arrayWithObjects: L_AS_T_SHARED, gPrivatePath, altPath, nil];
        
        BOOL okSoFar = YES;
        unsigned i;
        for (i=0; i < [foldersToSecure count]; i++) {
            NSString * folderPath = [foldersToSecure objectAtIndex: i];
            if (  [folderPath hasPrefix: gPrivatePath]  ) {
                okSoFar = okSoFar && checkSetOwnership(folderPath, NO, gRealUserID, gRealGroupID);
            } else {
                okSoFar = okSoFar && checkSetOwnership(folderPath, NO, 0, 0);
            }
            dirEnum = [gFileMgr enumeratorAtPath: folderPath];
            while (  (file = [dirEnum nextObject])  ) {
                NSString * filePath = [folderPath stringByAppendingPathComponent: file];
                if (  itemIsVisible(filePath)  ) {
                    if (   [gFileMgr fileExistsAtPath: filePath isDirectory: &isDir]
                        && isDir
                        && [[file pathExtension] isEqualToString: @"tblk"]  ) {
                        okSoFar = okSoFar && secureOneFolder(filePath);
                    }
				}
			}
		}
        
        if (  ! okSoFar  ) {
            NSLog(@"Tunnelblick: Warning: Unable to secure all .tblk packages");
        }
    }
    
    //**************************************************************************************************************************
    // (10)
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
            NSLog(@"Only .tblks may be copied or moved: Not a .tblk: %@", sourcePath);
            errorExit();
        }
        if (  ! [[targetPath pathExtension] isEqualToString: @"tblk"]  ) {
            NSLog(@"Only .tblks may be copied or moved: Not a .tblk: %@", targetPath);
            errorExit();
        }

        // Create the enclosing folder(s) if necessary. Owned by root unless if in gPrivatePath, in which case it is owned by the user
        NSString * enclosingFolder = [targetPath stringByDeletingLastPathComponent];
        uid_t own = 0;
        gid_t grp = 0;
        if (  [targetPath hasPrefix: gPrivatePath]  ) {
            own = gRealUserID;
            grp = gRealGroupID;
        }
        errorExitIfAnySymlinkInPath(enclosingFolder, 2);
        
        if (  ! createDirWithPermissionAndOwnership(enclosingFolder, 0755, own, grp)  ) {
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
        // Then create a shadow copy of the target and secure it
        // Else secure the target
        //
        // If   we MOVED FROM PRIVATE
        // Then delete the shadow copy of the source

        safeCopyOrMovePathToPath(sourcePath, targetPath, moveNotCopy);
        
        NSString * firstPartOfTarget = firstPartOfPath(targetPath);
        if (   [firstPartOfTarget isEqualToString: gPrivatePath]  ) {
            NSString * lastPartOfTarget = lastPartOfPath(targetPath);
            NSString * shadowTargetPath   = [NSString stringWithFormat: @"%@/%@/%@",
                                             L_AS_T_USERS,
                                             NSUserName(),
                                             lastPartOfTarget];
            if (  ! deleteThingAtPath(shadowTargetPath)  ) {
                errorExit();
            }
            safeCopyOrMovePathToPath(targetPath, shadowTargetPath, FALSE);
            secureOneFolder(shadowTargetPath);
        } else {
            secureOneFolder(targetPath);
        }
        
        NSString * firstPartOfSource = firstPartOfPath(sourcePath);
        if (  [firstPartOfSource isEqualToString: gPrivatePath]  ) {
            if (  moveNotCopy  ) {
                NSString * lastPartOfSource = lastPartOfPath(sourcePath);
                NSString * shadowSourcePath   = [NSString stringWithFormat: @"%@/%@/%@",
                                                 L_AS_T_USERS,
                                                 NSUserName(),
                                                 lastPartOfSource];
                if (  ! deleteThingAtPath(shadowSourcePath)  ) {
                    errorExit();
                }
            }
        }
    }
    
    
    //**************************************************************************************************************************
    // (11)
    // If requested, secure a single file or .tblk package
    if (   firstPath
        && ( ! secondPath )
        && ( ! deleteConfig )
        && ( ! setBundleVersion )  ) {
        
        // Make sure we are dealing with .tblks
        if (  ! [[firstPath pathExtension] isEqualToString: @"tblk"]  ) {
            NSLog(@"Only .tblks may be copied or moved: Not a .tblk: %@", firstPath);
            errorExit();
        }

        BOOL okSoFar = TRUE;
        NSString * ext = [firstPath pathExtension];
        if (  [ext isEqualToString: @"ovpn"] || [ext isEqualToString: @"conf"]  ) {
            if (  [firstPath hasPrefix: gPrivatePath]  ) {
                okSoFar = okSoFar && checkSetOwnership(firstPath, NO, gRealUserID, gRealGroupID);
            } else {
                okSoFar = okSoFar && checkSetOwnership(firstPath, NO, 0, 0);
            }
            okSoFar = okSoFar && checkSetPermissions(firstPath, @"644", YES);
        } else if (  [ext isEqualToString: @"tblk"]  ) {
            okSoFar = okSoFar && secureOneFolder(firstPath);
        } else {
            NSLog(@"Tunnelblick: trying to secure unknown item at %@", firstPath);
            errorExit();
        }
        if (  ! okSoFar  ) {
            NSLog(@"Tunnelblick: unable to secure %@", firstPath);
            errorExit();
        }
    }
    
    //**************************************************************************************************************************
    // (12)
    // If requested, delete a single file or .tblk package (also deletes the shadow copy if deleting a private configuration)
    if (   firstPath
        && deleteConfig
        && ( ! setBundleVersion )  ) {
        NSString * ext = [firstPath pathExtension];
        if (  [ext isEqualToString: @"tblk"]  ) {
            if (  [gFileMgr fileExistsAtPath: firstPath]  ) {
                errorExitIfAnySymlinkInPath(firstPath, 6);
                if (  ! [gFileMgr tbRemoveFileAtPath: firstPath handler: nil]  ) {
                    NSLog(@"Tunnelblick: unable to remove %@", firstPath);
                } else {
                    NSLog(@"Tunnelblick: removed %@", firstPath);
                }
                
                // Delete shadow copy, too, if it exists
                if (  [firstPartOfPath(firstPath) isEqualToString: gPrivatePath]  ) {
                    NSLog(@"DEBUG 005: firstPath prefix DID match:\n     %@\n     %@", firstPath, gPrivatePath);
                    NSString * shadowCopyPath = [NSString stringWithFormat: @"%@/%@/%@",
                                                 L_AS_T_USERS,
                                                 NSUserName(),
                                                 lastPartOfPath(firstPath)];
                    if (  [gFileMgr fileExistsAtPath: shadowCopyPath]  ) {
                        errorExitIfAnySymlinkInPath(shadowCopyPath, 7);
                        if (  ! [gFileMgr tbRemoveFileAtPath: shadowCopyPath handler: nil]  ) {
                            NSLog(@"Tunnelblick: unable to remove %@", shadowCopyPath);
                        } else {
                            NSLog(@"Tunnelblick: removed %@", shadowCopyPath);
                        }
                    }
                } else {
                    NSLog(@"DEBUG 005: firstPath prefix DID NOT match:\n     %@\n     %@", firstPath, gPrivatePath);
                }
            }
        } else {
            NSLog(@"Tunnelblick: trying to remove unknown item at %@", firstPath);
            errorExit();
        }
    }
    
    //**************************************************************************************************************************
    // (13) If requested, copies the bundleVersion into the CFBundleVersion entry
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
                    NSLog(@"Tunnelblick: Tunnelblick Configurations.bundle CFBundleVersion has been set to %@", bundleVersion);
                } else {
                    NSLog(@"Tunnelblick: Tunnelblick Configurations.bundle CFBundleVersion is %@", bundleVersion);
                }
            } else {
                NSLog(@"Tunnelblick: no CFBundleVersion in %@", libPlistPath);
            }
            
            libVersion = [libDict objectForKey: @"CFBundleShortVersionString"];
            if (  libVersion  ) {
                if (  ! [libVersion isEqualToString: bundleShortVersionString]  ) {
                    [libDict removeObjectForKey: @"CFBundleShortVersionString"];
                    [libDict setObject: bundleShortVersionString forKey: @"CFBundleShortVersionString"];
                    changed = TRUE;
                    NSLog(@"Tunnelblick: Tunnelblick Configurations.bundle CFBundleShortVersionString has been set to %@", bundleShortVersionString);
                } else {
                    NSLog(@"Tunnelblick: Tunnelblick Configurations.bundle CFBundleShortVersionString is %@", bundleShortVersionString);
                }
            } else {
                NSLog(@"Tunnelblick: no CFBundleShortVersionString in %@", libPlistPath);
            }
            
            if (  changed  ) {
                [libDict writeToFile: libPlistPath atomically: YES];
            }

            NSString * installFolderPath = [CONFIGURATION_UPDATES_BUNDLE_PATH stringByAppendingPathComponent: @"Contents/Resources/Install"];
            if (  [gFileMgr fileExistsAtPath: installFolderPath]  ) {
                if (  ! [gFileMgr tbRemoveFileAtPath: installFolderPath handler: nil]  ) {
                    NSLog(@"Tunnelblick: unable to remove %@", installFolderPath);
                } else {
                    NSLog(@"Tunnelblick: removed %@", installFolderPath);
                }
            }
                
        } else {
            NSLog(@"Tunnelblick: could not find %@", CONFIGURATION_UPDATES_BUNDLE_PATH);
        }
    }
    
    
    //**************************************************************************************************************************
    // DONE
    
    deleteFlagFile();
    
    [pool release];
    exit(EXIT_SUCCESS);
}

//**************************************************************************************************************************

void deleteFlagFile(void)
{
    char * path = "/tmp/tunnelblick-authorized-running";
    struct stat sb;
	if (  0 == stat(path, &sb)  ) {
        if (  (sb.st_mode & S_IFMT) == S_IFREG  ) {
            if (  0 != unlink(path)  ) {
                NSLog(@"Tunnelblick: Unable to delete %s", path);
            }
        } else {
            NSLog(@"Tunnelblick: %s is not a regular file; st_mode = 0%lo", path, (unsigned long) sb.st_mode);
        }
    } else {
        NSLog(@"Tunnelblick: stat of %s failed\nError was '%s'", path, strerror(errno));
    }
}

//**************************************************************************************************************************
void errorExit()
{
    deleteFlagFile();

    [pool release];
    exit(EXIT_FAILURE);
}


//**************************************************************************************************************************
void safeCopyOrMovePathToPath(NSString * fromPath, NSString * toPath, BOOL moveNotCopy)
{
    // Copy the file or package to a ".partial" file/folder first, then rename it
    // This avoids a race condition: folder change handling code runs while copy is being made, so it sometimes can
    // see the .tblk (which has been copied) but not the config.ovpn (which hasn't been copied yet), so it complains.
    NSString * dotPartialPath = [toPath stringByAppendingPathExtension: @"partial"];
    errorExitIfAnySymlinkInPath(dotPartialPath, 3);
    [gFileMgr tbRemoveFileAtPath:dotPartialPath handler: nil];
    if (  ! [gFileMgr tbCopyPath: fromPath toPath: dotPartialPath handler: nil]  ) {
        NSLog(@"Tunnelblick: Failed to copy %@ to %@", fromPath, dotPartialPath);
        [gFileMgr tbRemoveFileAtPath:dotPartialPath handler: nil];
        errorExit();
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
    if (  ! [gFileMgr tbMovePath: dotPartialPath toPath: toPath handler: nil]  ) {
        NSLog(@"Tunnelblick: Failed to rename %@ to %@", dotPartialPath, toPath);
        [gFileMgr tbRemoveFileAtPath:dotPartialPath handler: nil];
        errorExit();
    } else {
        NSLog(@"Tunnelblick: %@ %@ to %@", (moveNotCopy ? @"Moved" : @"Copied"), fromPath, toPath);
    }
}

//**************************************************************************************************************************
BOOL deleteThingAtPath(NSString * path)
{
    errorExitIfAnySymlinkInPath(path, 8);
    if (  ! [gFileMgr tbRemoveFileAtPath: path handler: nil]  ) {
        NSLog(@"Tunnelblick: Failed to delete %@", path);
        return FALSE;
    } else {
        NSLog(@"Tunnelblick: Deleted %@", path);
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
                NSLog(@"Tunnelblick: Unable to move %@ to %@ because the destination already exists", fullFromPath, fullToPath);
                return NO;
            } else {
                if (  ! [gFileMgr tbMovePath: fullFromPath toPath: fullToPath handler: nil]  ) {
                    NSLog(@"Tunnelblick: Unable to move %@ to %@", fullFromPath, fullToPath);
                    return NO;
                }
            }
        }
    }
    
    return YES;
}

//**************************************************************************************************************************
BOOL createSymLink(NSString * fromPath, NSString * toPath)
{
    if (  [gFileMgr tbCreateSymbolicLinkAtPath: fromPath pathContent: toPath]  ) {
        // Since we're running as root, owner of symbolic link is root:wheel. Try to change to real user:group
        if (  0 != lchown([gFileMgr fileSystemRepresentationWithPath: fromPath], gRealUserID, gRealGroupID)  ) {
            NSLog(@"Tunnelblick: Error: Unable to change ownership of symbolic link %@\nError was '%s'", fromPath, strerror(errno));
            return NO;
        } else {
            NSLog(@"Tunnelblick: Successfully created a symbolic link from %@ to %@", fromPath, toPath);
            return YES;
        }
    }

    NSLog(@"Tunnelblick: Error: Unable to create symbolic link from %@ to %@", fromPath, toPath);
    return NO;
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
        NSLog(@"Tunnelblick: Failed to unlock %@ in %d attempts", path, maxTries);
        return FALSE;
    }
    return TRUE;
}

//**************************************************************************************************************************
// Changes ownership of a file or folder to the specified user/group if necessary.
// If "deeply" is TRUE, also changes ownership on all contents of a folder (except invisible items)
// Returns YES on success, NO on failure
BOOL checkSetOwnership(NSString * path, BOOL deeply, uid_t uid, gid_t gid)
{
    BOOL changedBase = FALSE;
    BOOL changedDeep = FALSE;
    
    NSDictionary * atts = [[NSFileManager defaultManager] tbFileAttributesAtPath: path traverseLink: YES];
    if (  ! (   [[atts fileOwnerAccountID]      isEqualToNumber: [NSNumber numberWithInt: uid]]
             && [[atts fileGroupOwnerAccountID] isEqualToNumber: [NSNumber numberWithInt: gid]]  )  ) {
        if (  [atts fileIsImmutable]  ) {
            NSLog(@"Tunnelblick: Unable to change ownership of %@ to %d:%d because it is locked",
                  path,
                  (int) uid,
                  (int) gid);
            return NO;
        }
        
        if (  chown([gFileMgr fileSystemRepresentationWithPath: path], uid, gid) != 0  ) {
            NSLog(@"Tunnelblick: Unable to change ownership of %@ to %d:%d\nError was '%s'",
                  path,
                  (int) uid,
                  (int) gid,
                  strerror(errno));
            return NO;
        }
        
        changedBase = TRUE;
    }
    
    if (  deeply  ) {
        NSString * file;
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: path];
        while (  (file = [dirEnum nextObject])  ) {
            NSString * filePath = [path stringByAppendingPathComponent: file];
            if (  itemIsVisible(filePath)  ) {
                atts = [[NSFileManager defaultManager] tbFileAttributesAtPath: filePath traverseLink: NO];
				changedDeep = checkSetItemOwnership(filePath, atts, uid, gid, NO) || changedDeep;
				if (  [[atts objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
					changedDeep = checkSetItemOwnership(filePath, atts, uid, gid, YES) || changedDeep;
				} else {
				}
            }
        }
    }
    
    if (  changedBase ) {
        if (  changedDeep  ) {
            NSLog(@"Tunnelblick: Changed ownership of %@ and its contents to %d:%d",
                  path,
                  (int) uid,
                  (int) gid);
        } else {
            NSLog(@"Tunnelblick: Changed ownership of %@ to %d:%d",
                  path,
                  (int) uid,
                  (int) gid);
        }
    } else {
        if (  changedDeep  ) {
            NSLog(@"Tunnelblick: Changed ownership of the contents of %@ to %d:%d",
                  path,
                  (int) uid,
                  (int) gid);
        }
    }
    
    return YES;
}

//**************************************************************************************************************************
// Changes ownership of a single item to the specified user/group if necessary.
// Returns YES if changed, NO if not changed
BOOL checkSetItemOwnership(NSString * path, NSDictionary * atts, uid_t uid, gid_t gid, BOOL traverseLink)
{
	if (  ! (   [[atts fileOwnerAccountID]      isEqualToNumber: [NSNumber numberWithInt: (int) uid]]
			 && [[atts fileGroupOwnerAccountID] isEqualToNumber: [NSNumber numberWithInt: (int) gid]]  )  ) {
		if (  [atts fileIsImmutable]  ) {
			NSLog(@"Tunnelblick: Unable to change ownership of %@ to %d:%d because it is locked",
				  path,
				  (int) uid,
				  (int) gid);
			return NO;
		}
		
		int result = 0;
		if (   traverseLink
			|| ( ! [[atts objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink] )
			) {
			result = chown([gFileMgr fileSystemRepresentationWithPath: path], uid, gid);
		} else {
			result = lchown([gFileMgr fileSystemRepresentationWithPath: path], uid, gid);
		}

		if (  result != 0  ) {
			NSLog(@"Tunnelblick: Unable to change ownership of %@ to %d:%d\nError was '%s'",
				  path,
				  (int) uid,
				  (int) gid,
				  strerror(errno));
			return NO;
		}
		
		return YES;
	}

	return NO;
}

//**************************************************************************************************************************
// Changes permissions on a file or folder (but not the folder's contents) to specified values if necessary
// Returns YES on success, NO on failure
// Also returns YES if no such file or folder and 'fileMustExist' is FALSE
BOOL checkSetPermissions(NSString * path, NSString * permsShouldHave, BOOL fileMustExist)
{
    if (  ! [gFileMgr fileExistsAtPath: path]  ) {
        if (  fileMustExist  ) {
            return NO;
        }
        return YES;
    }

    NSDictionary *atts = [gFileMgr tbFileAttributesAtPath: path traverseLink:YES];
    unsigned long perms = [atts filePosixPermissions];
    NSString *octalPerms = [NSString stringWithFormat:@"%lo",perms];
    
    if (   [octalPerms isEqualToString: permsShouldHave]  ) {
        return YES;
    }
    
    if (  [atts fileIsImmutable]  ) {
        NSLog(@"Tunnelblick: Cannot change permissions because item is locked: %@", path);
        return NO;
    }
    
    mode_t permsMode;
    if      (  [permsShouldHave isEqualToString:  @"755"]  ) permsMode =  0755;
    else if (  [permsShouldHave isEqualToString:  @"744"]  ) permsMode =  0744;
    else if (  [permsShouldHave isEqualToString:  @"644"]  ) permsMode =  0644;
    else if (  [permsShouldHave isEqualToString:  @"640"]  ) permsMode =  0640;
    else if (  [permsShouldHave isEqualToString:  @"600"]  ) permsMode =  0600;
    else if (  [permsShouldHave isEqualToString: @"4555"]  ) permsMode = 04555;
    else {
        NSLog(@"Tunnelblick: invalid permsShouldHave = '%@' in checkSetPermissions function", permsShouldHave);
        return NO;
    }
    
    if (  chmod([gFileMgr fileSystemRepresentationWithPath: path], permsMode) != 0  ) {
        NSLog(@"Tunnelblick: Unable to change permissions to 0%@ on %@", permsShouldHave, path);
        return NO;
    }

    NSLog(@"Tunnelblick: Changed permissions to 0%@ on %@", permsShouldHave, path);
    return YES;
}

void errorExitIfAnySymlinkInPath(NSString * path, int testPoint)
{
    NSString * curPath = path;
    while (   curPath
           && ! [curPath isEqualToString: @"/"]  ) {
        if (  [gFileMgr fileExistsAtPath: curPath]  ) {
            NSDictionary * fileAttributes = [gFileMgr tbFileAttributesAtPath: curPath traverseLink: NO];
            if (  [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
                NSLog(@"Tunnelblick: Apparent symlink attack detected at test point %d: Symlink is at %@, full path being tested is %@", testPoint, curPath, path);
                errorExit();
            }
        }
        
        curPath = [curPath stringByDeletingLastPathComponent];
    }
}

//**************************************************************************************************************************
// Function to create a directory with specified ownership and permissions
// Recursively creates all intermediate directories (with the same ownership and permissions) as needed
// Returns YES if the directory existed with the specified ownership and permissions or has been created with them
BOOL createDirWithPermissionAndOwnership(NSString * dirPath, mode_t permissions, uid_t owner, gid_t group)
{
    // Don't try to create or set ownership or permissions on
    //       /Library/Application Support
    //   or ~/Library/Application Support
    if (  [dirPath hasSuffix: @"/Library/Application Support"]  ) {
        return YES;
    }
    
    BOOL isDir;
    
    if (  ! (   [gFileMgr fileExistsAtPath: dirPath isDirectory: &isDir]
             && isDir )  ) {
        // No such directory. Create its parent directory if necessary
        NSString * parentPath = [dirPath stringByDeletingLastPathComponent];
        if (  ! createDirWithPermissionAndOwnership(parentPath, permissions, owner, group)  ) {
            return NO;
        }
        
        // Parent directory exists. Create the directory we want
        if (  mkdir([gFileMgr fileSystemRepresentationWithPath: dirPath], (mode_t) permissions) != 0  ) {
            NSLog(@"Tunnelblick: Unable to create directory %@", dirPath);
            return NO;
        }

        NSLog(@"Tunnelblick: Created directory %@", dirPath);
    }

    
    // Directory exists. Check/set ownership and permissions
    if (  ! checkSetOwnership(dirPath, NO, owner, group)  ) {
        return NO;
    }
    NSString * permissionsAsString = [NSString stringWithFormat: @"%lo", (long) permissions];
    if (  ! checkSetPermissions(dirPath, permissionsAsString, YES)  ) {
        return NO;
    }
    
    return YES;
}

//**************************************************************************************************************************
// Returns YES if path to an item has no components starting with a period
BOOL itemIsVisible(NSString * path)
{
    if (  [path hasPrefix: @"."]  ) {
        return NO;
    }
    NSRange rng = [path rangeOfString:@"/."];
    if (  rng.length != 0) {
        return NO;
    }
    return YES;
}

//**************************************************************************************************************************
// Makes sure that ownership/permissions of a FOLDER AND ITS CONTENTS are secure (a .tblk or /Shared, /Deploy, private, or alternate config folder)
// For private config folder, all that is done is to make sure that everything is owned by <user>:<group> except that all keys and certificates inside a .tblk are <user>:admin/640
// For others:
//      If necessary, changes ownership of the folder and contents to root:wheel or <user>:<group> or <user>:admin
//      If necessary, changes permissions on the folder to 775
//      If necessary, changes permissions on CONTENTS of the folder as follows
//              invisible files (those with _any_ path component that starts with a period) are not changed
//              folders and executables are set to 755
//              shell scripts are set to 744
//              certificate & key files are set to 640
//              all other visible files are set to 644
// Returns YES if successfully secured everything, otherwise returns NO
BOOL secureOneFolder(NSString * path)
{
    BOOL result = YES;
    BOOL isDir;
    NSString * file;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: path];
	
    if (  [path hasPrefix: gPrivatePath]  ) {                                               // If a private folder
        if (  [[path pathExtension] isEqualToString: @"tblk"]  ) {                          // and it is a .tblk
            NSString * contentsPath = [path stringByAppendingPathComponent: @"Contents"];   // and its "Contents" folder is owned by root
            NSDictionary * dict = [gFileMgr attributesOfItemAtPath: contentsPath
															 error: nil];
            if (  [[dict fileOwnerAccountID ] unsignedLongValue] ==  0) {                   // then an earlier version of Tunnelblick "protected" it (not very well!)
                result = result && checkSetOwnership(path,                                  //      so we give ownership of the .tblk and its contents to the user
                                                     YES, gRealUserID, gRealGroupID);       //
                result = result && checkSetPermissions(path, @"755", YES);                  //         and set permissions on the .tblk itself
				while (  (file = [dirEnum nextObject])  ) {									//         and set ownership and permissions on folders, keys & certs only
					NSString * filePath = [path stringByAppendingPathComponent: file];
					if (  itemIsVisible(filePath)  ) {
						NSString * ext  = [file pathExtension];
						if (   [gFileMgr fileExistsAtPath: filePath isDirectory: &isDir]
							&& isDir  ) {
							result = result && checkSetPermissions(filePath, @"755", YES);
						} else if (  [gKeyAndCrtExtensions containsObject: ext]  ) {
							result = result && checkSetOwnership(filePath,                  //      Keys and certificates are 640 for private configurations
																 NO,
																 gRealUserID,
																 ADMIN_GROUP_ID);           //      (and are owned by <user>:admin)
							result = result && checkSetPermissions(filePath, @"640", YES);
						}
					}
				}
            } else {
                return YES; // Not owned by root                                             // else we don't do anything
            }
        } else {
			NSLog(@"%@ is not a .tblk", path);
			return NO; // Not a .tblk
		}

    } else {
        errorExitIfAnySymlinkInPath(path, 9);                                               // If a protected folder, verify that this is an actual protected folder
        result = result && checkSetOwnership(path, YES, 0, 0);                              // and make sure it and its contents are owned by root:wheel
        result = result && checkSetPermissions(path, @"755", YES);
		
		while (  (file = [dirEnum nextObject])  ) {
			NSString * filePath = [path stringByAppendingPathComponent: file];
			if (  itemIsVisible(filePath)  ) {
				NSString * ext  = [file pathExtension];
				if (  [ext isEqualToString: @"tblk"]  ) {
					result = result && secureOneFolder(filePath);                           // NOTE: RECURSION
					[dirEnum skipDescendents];
				} else {
					if (   [gFileMgr fileExistsAtPath: filePath isDirectory: &isDir]        // Set permissions as follows:
						&& isDir  ) {
						result = result && checkSetPermissions(filePath, @"755", YES);      //      Folders are 755
					} else if ( [ext isEqualToString:@"executable"]  ) {
						result = result && checkSetPermissions(filePath, @"755", YES);      //      Executable files for custom menu commands are 755
					} else if ( [ext isEqualToString:@"sh"]  ) {
						result = result && checkSetPermissions(filePath, @"744", YES);      //      Scripts are 744
					} else if (  [gKeyAndCrtExtensions containsObject: ext]  ) {
						if (  [path hasPrefix: gPrivatePath]  ) {
							result = result && checkSetOwnership(filePath,                  //      Keys and certificates are 640 for private configurations
																 NO,
																 gRealUserID,
																 ADMIN_GROUP_ID);           //      (and are owned by <user>:admin)
							result = result && checkSetPermissions(filePath, @"640", YES);
						} else {
							result = result && checkSetPermissions(filePath, @"600", YES);  //      Keys and certificates are 600 for others
						}
					} else {
						result = result && checkSetPermissions(filePath, @"644", YES);      //      Everything else is 644
					}
				}
			}
		}
	}
	
    return result;
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
        if (  [path hasPrefix: configFolder]  ) {
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
        if (  [path hasPrefix: configFolder]  ) {
            if (  [path length] > [configFolder length]  ) {
                return [path substringFromIndex: [configFolder length]+1];
            } else {
                NSLog(@"No display name in path '%@'", path);
                return @"X";
            }
        }
    }
    return nil;
}

void secureL_AS_T_DEPLOY()
{
    NSLog(@"Tunnelblick: Securing %@", L_AS_T_DEPLOY);
    if (  checkSetOwnership(L_AS_T_DEPLOY, YES, 0, 0)  ) {
        if (  checkSetPermissions(L_AS_T_DEPLOY, @"755", YES)  ) {
            if (  secureOneFolder(L_AS_T_DEPLOY)  ) {
                NSLog(@"Tunnelblick: Secured %@", L_AS_T_DEPLOY);
            } else {
                NSLog(@"Tunnelblick: Unable to secure %@", L_AS_T_DEPLOY);
                errorExit();
            }
        } else {
            NSLog(@"Tunnelblick: Unable to set permissions on %@", L_AS_T_DEPLOY);
            errorExit();
        }
    } else {
        NSLog(@"Tunnelblick: Unable to set ownership on %@ and its contents", L_AS_T_DEPLOY);
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
            if (  [path hasPrefix: fullPath]  ) {
                [result addObject: [NSString stringWithString: path]];
            } else {
                NSLog(@"Unrecoverable error dealing with Deploy backups");
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
        NSDate   * latestDate = [[gFileMgr attributesOfItemAtPath: latestPath error: nil] objectForKey: NSFileModificationDate];
        if (  ! latestDate  ) {
            NSLog(@"No last modified date for %@", latestPath);
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
                            NSDate   * thisDate = [[gFileMgr attributesOfItemAtPath: thisPath error: nil] objectForKey: NSFileModificationDate];
                            if ( ! thisDate  ) {
                                NSLog(@"No last modified date for %@", thisPath);
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
