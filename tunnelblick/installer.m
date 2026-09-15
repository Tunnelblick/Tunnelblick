/*
 * Copyright 2004, 2005, 2006, 2007, 2008, 2009 by Angelo Laub
 * Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2018, 2019, 2020, 2021, 2023, 2025, 2026. All rights reserved.

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

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <OpenDirectory/OpenDirectory.h>
#import <pwd.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <sys/xattr.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/SecRandom.h>

#import "defines.h"
#import "sharedRoutines.h"

#import "ConfigurationConverter.h"
#import "ConfigurationParser.h"
#import "NSDate+TB.h"
#import "NSFileManager+TB.h"
#import "NSString+TB.h"
#import "TBUpdaterShared.h"
#import "TBValidator.h"

// NOTE: THIS PROGRAM MUST BE RUN AS ROOT. Tunnelblick runs it by using waitForExecuteAuthorized
//
// This program is called when something needs to be secured.
// It accepts one to three arguments, and always does some standard housekeeping in
// addition to the specific tasks specified by the command line arguments.
//
// Usage:
//
//     installer bitmask
//               (for most operations)
//
//     installer bitmask  targetPath
//               (for delete configuration)
//
//     installer bitmask  sourcePath  usernameMappingString
//               (for import .tblksetup)
//
//     installer bitmask  targetPath  sourcePath
//               (for copy/move configuration)
//
//     installer bitmask  username  sourcePath [subfolder]
//               (for copy to private configuration)
//
//     installer bitmask  sourcePath [subfolder]
//               (for copy to shared configuration)
//
//     installer bitmask  username versionBuild
//               (to install Tunnelblick app version and build versionBuild from /Users/username/Library/Application Support/Tunnelblick/tunnelblick-update.zip)
//
// where
//
//	   bitMask DETERMINES WHAT THE INSTALLER WILL DO (see defines.h for bit assignments)
//
//     targetPath is the path to a configuration (.ovpn or .conf file, or .tblk package) to be secured (or forced-preferences.plist)
//
//     sourcePath is the path to be copied or moved to targetPath before securing targetPath
//
//     username is the short username of the user on whose behalf a configuration is being installed
//
//     usernameMappingString is a string that contains a set of username mapping rules to use when importing a .tblkSetup. It consists
//							 of zero or more separated-by-slashes pairs of username:username. The first username is the username in the
//							 .tblkSetup (from the computer the .tblkSetup was created on). The second is the username on this computer
//							 (the computer the import is being done on).
//
//							 Each username should be the "short" username (e.g. "abcuthbert"), not the "long" username ("A. B. Cuthbert")
//
//							 Example: "abc:def/ghi:jkl" maps user "abc" in the .tblkSetup to computer user "def" and
//									  user "ghi" in the .tblkSetup to computer user "jkl"
//
// This program does the following, in this order:
//
//      (1) Clears the installer log if INSTALLER_CLEAR_LOG is set
//			Creates directories or repairs their ownership/permissions as needed
//			Repairs ownership/permissions of L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH
//			Creates the .mip folder if it does not already exist
//          Updates Tunnelblick kexts in /Library/Extensions (unless kexts are being uninstalled)
//
//      (2) If INSTALLER_COPY_APP is set, this app is copied to /Applications and all extended attributes are removed from the copy and all items within it
//
//      (3) If INSTALLER_SECURE_APP is set, secures Tunnelblick.app by setting the ownership and permissions of its components.
//
//      (4) If requested, copy app to L_AS_T
//
//      (5) Remove L_AS_T_TBLKS
//
//      (6) If INSTALLER_SECURE_TBLKS is set, then secures all .tblk packages in the following folders:
//				/Library/Application Support/Tunnelblick/Shared
//				~/Library/Application Support/Tunnelblick/Configurations
//				/Library/Application Support/Tunnelblick/Users/<username>
//
//      (7) if the operation is INSTALLER_INSTALL_FORCED_PREFERENCES and targetPath is given and is a .plist and there is no secondPath
//             installs the .plist at targetPath in L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH
//             NO LONGER USED BY TUNNELBLICK; KEPT AVAILABLE FOR SCRIPTS BY DEPLOYERS
//
//
//          If the operation is INSTALLER_INSTALL_FORCED_PREFERENCES_XML and the second argument is an XML dictionary,
//          installs the dictionary in L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH
//
//      (8) If the operation is INSTALLER_COPY or INSTALLER_MOVE and both targetPath and sourcePath are given,
//             copies or moves sourcePath to targetPath. Copies unless INSTALLER_MOVE is set.
//
//      (9) If the operation is INSTALLER_DELETE and only targetPath is given,
//             deletes the .ovpn or .conf file or .tblk package at targetPath (also deletes the shadow copy if deleting a private configuration)
//
//     (10) If the operation is INSTALLER_SET_FORCED_PREFERENCE and both arguments are present,
//             sets the forced preference named in second_arg to <true> if value in third_arg is "1", or or deletes it if value in third_arg is "0"
//             (May delete the forced preference file if there are no forced preferences.)
//
//     (11) If the operation is INSTALLER_RENAME_MIP_FILE and both arguments are present,
//             renames the first path (which must be a file in L_AS_T_TEMP) to the second path (which must be a a file in L_AS_T_MIPS).
//
//     (12) If not installing a configuration, sets up tunnelblickd
//
//	   (13) If requested, exports all settings and configurations for all users to a file at targetPath, deleting the file if it already exists
//
//	   (14) If requested, import settings from the .tblkSetup at targetPath
//
//     (15) If requested, install or uninstall kexts
//
//     (16) If requested, update Tunnelblick

// When finished (or if an error occurs), the file at AUTHORIZED_DONE_PATH is written to indicate the program has finished

// The following globals are not modified after they are initialized:
static FILE   * gLogFile;					  // FILE for log
NSFileManager * gFileMgr;                     // NSFileManager.defaultManager
NSString      * gDeployPath;                  // Path to Tunnelblick.app/Contents/Resources/Deploy
static BOOL     renamex_npWorks = NO;         // renamex_np() works as needed for /Applications and L_AS_T, and home folder if it is available

#ifdef TBDebug
static BOOL     gLogFileActions = YES;        // Log all actions on files
#else
static BOOL     gLogFileActions = NO;         // Do not all actions on files
#endif

// The following variables contain info about the user. They may be zero or nil if not needed.
// If invoked by Tunnelblick, they will be set up using the uid from getuid().
// If invoked by sudo or similar (which has getuid() == 0):
//    * If this is the 'install private config' operation, they will be set up using the provided username.
//    * If one of the arguments to installer is a path in the user's home folder or a subfolder, they will
//      be set up for that user.
//    * Otherwise, they will be set to zero or nil.
static uid_t           gUserID = 0;
static gid_t           gGroupID = 0;
static NSString      * gUsername = nil;
NSString             * gPrivatePath = nil;                 // ~/Library/Application Support/Tunnelblick/Configurations
NSString             * gShadowPath = nil;                  // /Library/Application Support/Tunnelblick/Users/<username>
static NSString      * gHomeDirectory = nil;

static NSAutoreleasePool * pool;

static BOOL            gErrorOccurred = FALSE;       // Set if an error occurred

//**************************************************************************************************************************
// FORWARD REFERENCES

void appendLog(NSString * s);

static void copyAppToL_AS_T(NSString * sourcePath);

static void copyOrMoveOneFolderOrTblk(NSString * sourcePath, NSString * targetPath, BOOL moveNotCopy);

static void errorExit(void);

static void errorExitIfAnySymlinkOrDotDotInPath(NSString * path);

static const char * fileSystemRepresentationFromPath(NSString * path);

static NSString * privatePathFromUsername(NSString * username);

static void securelyCreateFolderAndParents(NSString * path);

static void securelyDeleteItem(NSString * path);

static void secureTheApp(NSString * appResourcesPath, BOOL copyToL_AS_T);

static NSString * usernameFromPossiblePrivatePath(NSString * path);

static NSString * userPrivatePath(void);

static NSString * userShadowPath(void);

static uid_t userUID(void);

static NSString * userUsername(void);

//**************************************************************************************************************************
// LOGGING AND ERROR HANDLING

static BOOL openLog(BOOL clearLog) {

    if (  ! [gFileMgr tbRemovePathIfItExists: INSTALLER_OLD_LOG_PATH]  ) {
        NSLog(@"Could not delete %@", INSTALLER_OLD_LOG_PATH);
    }

    if (  [gFileMgr fileExistsAtPath: INSTALLER_LOG_PATH]) {
        if (  ! [gFileMgr tbForceRenamePath:INSTALLER_LOG_PATH toPath: INSTALLER_OLD_LOG_PATH]  ) {
            NSLog(@"Could not rename %@ to %@", INSTALLER_LOG_PATH, INSTALLER_OLD_LOG_PATH);
        }
    }

    BOOL created_L_AS_T = FALSE;
    if (  ! [gFileMgr fileExistsAtPath: L_AS_T]  ) {
        if (  ! createDirWithPermissionAndOwnership(L_AS_T, PERMS_SECURED_FOLDER, 0, 0)  ) {
            errorExit();
        }
        created_L_AS_T = TRUE;
    }

    const char * path = fileSystemRepresentationFromPath(INSTALLER_LOG_PATH);
	
    char * mode = (  clearLog
                   ? "w"
                   : "a");

    gLogFile = fopen(path, mode);

	if (  gLogFile == NULL  ) {
		errorExit();
	}

    return created_L_AS_T;
}

void appendLog(NSString * s) {

    if (  gLogFile != NULL  ) {
        NSString * now = NSDate.date.tunnelblickUserLogRepresentation;
        fprintf(gLogFile, "%s: %s\n", now.UTF8String, s.UTF8String);
    }

    NSLog(@"%@", s);
}

static void errorExit(void) {

#ifdef TBDebug
    Log(@"errorExit(): Stack trace: %@", NSThread.callStackSymbols);
#else
    Log(@"Tunnelblick installer failed");
#endif

    storeAuthorizedDoneFileAndExit(EXIT_FAILURE);
    exit(EXIT_FAILURE); // Never executed but needed to make static analyzer happy
}

//**************************************************************************************************************************
// UTILITY ROUTINES

static NSString * makePathAbsolute(NSString * path) {

    NSString * standardizedPath = [path stringByStandardizingPath];
    NSURL * url = [NSURL fileURLWithPath: standardizedPath];
    url = [url absoluteURL];
    const char * pathC = url.fileSystemRepresentation;
    NSString * absolutePath = [NSString stringWithCString: pathC encoding: NSUTF8StringEncoding];

    return absolutePath;
}

static const char * fileSystemRepresentationFromPath(NSString * path) {

    const char * pathC = path.fileSystemRepresentation;
    if (  ! pathC  ) {
        Log(@"Could not get filesystem representation for %@", path);
        errorExit();
    }

    return pathC;
}

static NSString * thisAppResourcesPath(void) {

    NSString * resourcesPath = [NSProcessInfo.processInfo.arguments[0]  // .app/Contents/Resources/installer
                                stringByDeletingLastPathComponent];     // .app/Contents/Resources
    return resourcesPath;
}

static BOOL isPathPrivate(NSString * path) {

    NSString * absolutePath = makePathAbsolute(path);

    BOOL isPrivate = (  [absolutePath hasPrefix: [[userPrivatePath() stringByDeletingLastPathComponent] stringByAppendingString: @"/"]]
                      );
    return isPrivate;
}

NSString * lastPartOfPath(NSString * path) {

    //
    // Special case: /L_AS_T_TEMP/SecureCopy-<anything>--/
    //
    NSString * secureCopyPrefix = [L_AS_T_TEMP stringByAppendingString: @"/SecureCopy-"];

    if (  [path hasPrefix: secureCopyPrefix] ) {
        // A secure copy of a configuration in L_AS_T_TEMP/SecureCopy-UUID--.
        // Remove everything up to and including "--/"
        NSRange r = [path rangeOfString: @"--/"];
        if (  r.location != NSNotFound  ) {
            path = [path substringFromIndex: r.location + 3];
            return path;
        } else {
            Log(@"lastPartOfPath(): bad path '%@'", path);
            errorExit();
        }
    }

    NSArray * paths = @[gDeployPath,
                        L_AS_T_SHARED,
                        userPrivatePath(),
                        userShadowPath()];
    NSEnumerator * arrayEnum = [paths objectEnumerator];
    NSString * configFolder;
    while (  (configFolder = [arrayEnum nextObject])  ) {
        if (  [path hasPrefix: [configFolder stringByAppendingString: @"/"]]  ) {
            if (  path.length > configFolder.length + 1  ) {
                return [path substringFromIndex: [configFolder length]+1];
            } else {
                Log(@"No display name in path '%@'", path);
                return @"X";
            }
        }
    }

    Log(@"lastPartOfPath(): bad path '%@'", path);
    errorExit();
    return nil; // Satisfy static analyzer
}

static void structureTblkProperly(NSString * path) {

    // If a .tblk doesn't have a Contents folder, makes sure Info.plist is in Contents, and all files in a .tblk except Info.plist are in Contents/Resources.

    if (  [gFileMgr fileExistsAtPath: [path stringByAppendingPathComponent: @"Contents"]]  ) {
        return;
    }

    createDir([path stringByAppendingPathComponent: @"Contents/Resources"], 0700);

    NSMutableArray * sourcePaths = [NSMutableArray arrayWithCapacity: 10];
    NSMutableArray * targetPaths = [NSMutableArray arrayWithCapacity: 10];

    // Create a list of paths of files to be moved and where to move them
    NSString * entry;
    NSDirectoryEnumerator * dirE = [gFileMgr enumeratorAtPath: path];
    [dirE skipDescendants];
    while (  (entry = [dirE nextObject])  ) {
        NSString * fullPath = [path stringByAppendingPathComponent: entry];
        BOOL isDir;
        if (   [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
            && ( ! isDir )  ) {
            if (  [entry isEqualToString: @"Info.plist"]  ) {
                NSString * targetFullPath = [[path stringByAppendingPathComponent: @"/Contents"] stringByAppendingPathComponent: entry];
                if (  ! [fullPath isEqualToString: targetFullPath]) {
                    [sourcePaths addObject: fullPath];
                    [targetPaths addObject: targetFullPath];
                }
            } else {
                NSString * targetEntry = entry;
                if (  [entry hasSuffix: @".ovpn"]  ) {
                    targetEntry = [[entry stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"config.ovpn"];
                }
                NSString * targetFullPath = [[path stringByAppendingPathComponent: @"/Contents/Resources"] stringByAppendingPathComponent: targetEntry];
                if (  ! [fullPath isEqualToString: targetFullPath]) {
                    [sourcePaths addObject: fullPath];
                    [targetPaths addObject: targetFullPath];
                }
            }
        }
    }

    for (  NSUInteger i=0; i<[sourcePaths count]; i++  ) {
        if (  ! [gFileMgr tbMovePath: sourcePaths[i] toPath: targetPaths[i] handler: nil]  ) {
            Log(@"Unable to move %@ to %@", sourcePaths[i], targetPaths[i]);
            errorExit();
        } else {
            Log(@"Moved %@ to %@", sourcePaths[i], targetPaths[i]);
        }
    }
}

static void errorExitIfAnySymlinkOrDotDotInPath(NSString * path) {

    NSArray * components = [path pathComponents];
    if (  [components containsObject: @".."]  ) {
        Log(@"Apparent attack detected: '..' component found in '%@'",path);
        errorExit();
    }

    NSString * curPath = path;
    while (   (curPath.length != 0)
           && ! [curPath isEqualToString: @"/"]  ) {
        if (  [gFileMgr fileExistsAtPath: curPath]  ) {
            NSDictionary * fileAttributes = [gFileMgr tbFileAttributesAtPath: curPath traverseLink: NO];
            if (  [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
                if (  ! [curPath hasSuffix: @"/Tunnelblick.app/Contents/Resources/openvpn/default"]  ) {
                    Log(@"Apparent symlink attack detected: Symlink is at %@, full path being tested is %@", curPath, path);
                    errorExit();
                }
            }
        }

        curPath = [curPath stringByDeletingLastPathComponent];
    }
}

static BOOL pathWritableByUser(NSString * path) {

    return ( ! [path hasPrefix: [L_AS_T stringByAppendingString: @"/"]] );
}

static void errorExitIfWritableByUserInPath(NSString * path) {

    if (  ! pathWritableByUser(path)  ) {
        return;
    }

    Log(@"Apparent attack detected: Path is directly writable by user: %@", path);
    errorExit();
}

static void errorExitIfSymlinksOrDoesNotExistOrIsNotReadableAtPath(NSString * path) {

    if (   [gFileMgr fileExistsAtPath: path]
        && [gFileMgr isReadableFileAtPath: path]  ) {
        errorExitIfAnySymlinkOrDotDotInPath(path);
        return;
    }

    Log(@"File does not exist or is not readable: %@", path);
    errorExit();
}

//**************************************************************************************************************************
// UTILITY ROUTINES FOR FORCED PREFERENCES

static void deleteOrCopyOrRenameForcedPreferencesForDisplayName(NSString * displayName, NSString * _Nullable newDisplayName, BOOL deleteOriginals) {

    // If newDisplayName is nil or is an empty string and "deleteOriginals" is TRUE, deletes any forced preferences that refer to displayName.
    //
    // If newDisplayName is not empty and "deleteOriginals" is TRUE, renames forced preferences that refer to displayName to refer to newDisplayName.
    //
    // If newDisplayName is not empty and "deleteOriginals" is FALSE, copies forced preferences that refer to displayName so they refer to newDisplayName.

    if (   (newDisplayName == nil)
        && (! deleteOriginals)  ) {
        Log(@"deleteOrCopyOrRenameForcedPreferencesForDisplayName: not deleting, copying, or renaming, so nothing to do");
        return;
    }

    if (  ! [gFileMgr fileExistsAtPath: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH]  ) {
        if (  newDisplayName.length == 0  ) {
            Log(@"Not deleting forced preferences for '%@': there are no forced preferences", displayName);
        } else {
            Log(@"Not renaming forced preferences for '%@' to corresponding preferences for '%@': there are no forced preferences",
                displayName, newDisplayName);
        }
        return;
    }

    //
    // Get a dictionary with the forced preferenes
    //
    NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH];
    if ( dict == nil) {
        Log(@"Could not load a dictionary from '%@'", L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);
        errorExit();
    }

    // Make a mutable copy of the dictionary that we'll modify. This avoids enumerating a dictionary that's being modified
    NSMutableDictionary * newDict = [dict.mutableCopy autorelease];

    //
    // Go through all entries in the dictionary, making the requested changes
    //

    __block BOOL madeChanges = FALSE;

    [dict enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key,
                                              id  _Nonnull obj,
                                              BOOL * _Nonnull stop) {

        (void)stop;

        NSString * oldKey = (NSString *)key;

        if (  [oldKey hasSuffix: displayName]  ) {

            //
            // Have an entry that should be changed
            //
            if (  newDisplayName.length != 0  ) {

                //
                // Renaming: add a new forced preference for the new displayName
                //
                NSUInteger lengthOfPrefWithoutName = oldKey.length - displayName.length;

                NSString * newKey = [[oldKey
                                      substringToIndex: lengthOfPrefWithoutName]
                                     stringByAppendingString: newDisplayName];
                [newDict setValue: obj forKey: newKey];
                Log(@"Added forced preference '%@' : '%@'", newKey, obj);
            }

            // Delete the old forced preference if requested
            if (  deleteOriginals  ) {
                [newDict removeObjectForKey: oldKey];
                Log(@"Deleted forced preference '%@' : '%@'", oldKey, obj);
            }

            madeChanges = TRUE;
        }
    }];

    //
    // Write out the modified preferences if anything changed
    //
    if (  madeChanges  ) {
        if (  ! [newDict writeToFile: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH atomically: YES]  ) {
            Log(@"Could not write dictionary to '%@'", L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);
            errorExit();
        }
    } else {
        Log(@"No forced preferences for '%@'", displayName);
    }
}

static void deleteForcedPreferencesForDisplayName(NSString * displayName) {

    deleteOrCopyOrRenameForcedPreferencesForDisplayName(displayName, nil, YES);
}

static void renameForcedPreferencesForDisplayName(NSString * displayName, NSString * newDisplayName) {

    deleteOrCopyOrRenameForcedPreferencesForDisplayName(displayName, newDisplayName, YES);
}

static void copyForcedPreferencesForDisplayName(NSString * displayName, NSString * newDisplayName) {

    deleteOrCopyOrRenameForcedPreferencesForDisplayName(displayName, newDisplayName, NO);
}


//**************************************************************************************************************************
// EXTENDED ATTRIBUTES

void removeExtendedAttributes(NSString * tunnelblickAppPath) {

    // Removes all extended attributes from the directory structure rooted at tunnelblickAppPath

    NSArray * arguments = @[@"-crs", tunnelblickAppPath];
    OSStatus status = runTool(TOOL_PATH_FOR_XATTR, arguments, nil, nil);
    if (  status != EXIT_SUCCESS  ) {
        Log(@"'xattr -crs %@' failed", tunnelblickAppPath);
        errorExit();
    }
}


//**************************************************************************************************************************
// SECURELY* ROUTINES

static void securelySetUserOwnershipAndPermissionsOnFolderAndContents(NSString * targetPath) {

    secureOneFolderMaintainOwnership(targetPath, YES, userUID(), NO);
}

static void securelyKeepRootOwnershipAndSetPermissionsOnFolderAndContents(NSString * targetPath) {

    secureOneFolderMaintainOwnership(targetPath, NO, userUID(), YES);
}

static void securelyDeleteFolder(NSString * path) {

    errorExitIfAnySymlinkOrDotDotInPath(path);

    // Can only rmdir() an empty folder, so empty this folder

    NSDirectoryEnumerator * dirE = [gFileMgr enumeratorAtPath: path];
    [dirE skipDescendants];
    NSString * file;
    while (  (file = dirE.nextObject)  ) {
        NSString * fullPath = [path stringByAppendingPathComponent: file];
        securelyDeleteItem(fullPath);
    }

    // Now that the folder is empty, remove it
    if (  0 != rmdir(fileSystemRepresentationFromPath(path))  ) {
        Log(@"rmdir() failed with error %d ('%s') for path %@", errno, strerror(errno), path);
        errorExit();
    } else if (  gLogFileActions  ) {
        Log(@"FileAction: rmdir()for path '%@'", path);
    }
}

static void securelyDeleteItem(NSString * path) {

    errorExitIfAnySymlinkOrDotDotInPath(path.stringByDeletingLastPathComponent);

    const char * pathC = fileSystemRepresentationFromPath(path);

    struct stat status;

    if (  lstat(pathC, &status) != 0  ) {
        Log(@"lstat() failed with error %d ('%s') for %@", errno, strerror(errno), path);
        errorExit();
    }

    if (   ( ! S_ISLNK(status.st_mode) )
        && S_ISDIR(status.st_mode)  ) {
        securelyDeleteFolder(path);
    } else {
        if (  0 != unlink(pathC)  ) {
            Log(@"unlink() failed with error %d ('%s') for path %@", errno, strerror(errno), path);
            errorExit();
        } else if (  gLogFileActions  ) {
            Log(@"FileAction: unlink()for path '%@'", path);
        }
    }
}

static void securelyDeleteItemIfItExists(NSString * path) {

    errorExitIfAnySymlinkOrDotDotInPath(path);

    if (  ! [gFileMgr fileExistsAtPath: path]  ) {
        return;
    }

    securelyDeleteItem(path);
}

static void securelyRename(NSString * sourcePath, NSString * targetPath) {

    // Securely renames a file or folder, and sets permissions properly if it is in L_AS_T
    //
    // Creates intermediate directories to enclose targetPath if necessary.

    errorExitIfAnySymlinkOrDotDotInPath(sourcePath);
    errorExitIfAnySymlinkOrDotDotInPath(targetPath);

    if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
        securelyDeleteItem(targetPath);
    } else {
        // Create intermediate folders if they don't exist
        NSString * container = [targetPath stringByDeletingLastPathComponent];
        if (  ! [gFileMgr fileExistsAtPath: container]  ) {
            securelyCreateFolderAndParents(container);
        }
    }

    if (  renamex_npWorks  ) {
        if (  0 != renamex_np(fileSystemRepresentationFromPath(sourcePath), fileSystemRepresentationFromPath(targetPath), (RENAME_NOFOLLOW_ANY | RENAME_EXCL))  ){
            Log(@"renamex_np() failed with error %d ('%s') trying to rename %@ to %@",
                       errno, strerror(errno), sourcePath, targetPath);

            // Source and target may be on different volumes. Try moving instead of renaming.
            NSError * err = nil;
            if (  [gFileMgr moveItemAtPath: sourcePath toPath: targetPath error: &err]  ) {
                Log(@"Used NSFileManager to move %@ to %@", sourcePath, targetPath);
            } else {
                Log(@"NSFileManager error moving %@ to %@: %@", sourcePath, targetPath, err);
                errorExit();
            }
        } else if (  gLogFileActions  ) {
            Log(@"FileAction: renamex_np()for path '%@' to '%@'", sourcePath, targetPath);
        }
    } else {
        if (  0 != rename(fileSystemRepresentationFromPath(sourcePath), fileSystemRepresentationFromPath(targetPath))  ){
            Log(@"rename() failed with error %d ('%s') trying to rename %@ to %@",
                errno, strerror(errno), sourcePath, targetPath);
            errorExit();
        } else if (  gLogFileActions  ) {
            Log(@"FileAction: rename()for path '%@' to '%@'", sourcePath, targetPath);
        }
    }

    if (  [targetPath hasPrefix: [L_AS_T stringByAppendingString: @"/"]]  ) {
        securelyKeepRootOwnershipAndSetPermissionsOnFolderAndContents(targetPath);
    }

    if (  ! gLogFileActions  ) {
        Log(@"Renamed %@ to %@", sourcePath, targetPath);
    }
}

static void securelyCreateFileOrDirectoryEntry(BOOL isDir, NSString * path) {

    // Create a file or a directory owned by root with 0700 permissions (permissions will be changed to the correct values later)

    errorExitIfAnySymlinkOrDotDotInPath(path);

    if (  isDir  ) {
        mode_t old_umask = umask(0077);
        int result = mkdir(fileSystemRepresentationFromPath(path), 0700);
        umask(old_umask);
        if (  result != 0  ) {
            Log(@"mkdir() returned error %d ('%s') for path %@", errno, strerror(errno), path);
            errorExit();
        } else if (  gLogFileActions  ) {
            Log(@"FileAction: mkdir()for path'%@'", path);
        }
    } else {
        mode_t old_umask = umask(0077);
        int result = open(fileSystemRepresentationFromPath(path), (O_CREAT | O_EXCL | O_APPEND | O_NOFOLLOW_ANY), 0700);
        umask(old_umask);
        if (  result < 0  ) {
            Log(@"open() returned error %d ('%s') for path %@", errno, strerror(errno), path);
            errorExit();
        } else if (  gLogFileActions  ) {
            Log(@"FileAction: open(perms=0700)for path'%@'", path);
        }
        close(result); // Ignore errors
    }
}

static void securelyCreateFolderAndParents(NSString * path) {

    errorExitIfAnySymlinkOrDotDotInPath(path);

    if (  [gFileMgr fileExistsAtPath: path]  ) {
        return;
    }

    NSString * enclosingFolder = [path stringByDeletingLastPathComponent];
    if (  ! [gFileMgr fileExistsAtPath: enclosingFolder]  ) {
        securelyCreateFolderAndParents(enclosingFolder);
    }

    // Create the folder with the ownership and permissions of the folder that encloses it, but with the current date/time
    NSDictionary * enclosingFolderAttributes = [gFileMgr tbFileAttributesAtPath: enclosingFolder traverseLink: NO];
    NSDate * now = [NSDate date];
    NSDictionary * attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                 now,                                                                   NSFileCreationDate,
                                 now,                                                                   NSFileModificationDate,
                                 [enclosingFolderAttributes objectForKey: NSFileGroupOwnerAccountID],   NSFileGroupOwnerAccountID,
                                 [enclosingFolderAttributes objectForKey: NSFileGroupOwnerAccountName], NSFileGroupOwnerAccountName,
                                 [enclosingFolderAttributes objectForKey: NSFileOwnerAccountID],        NSFileOwnerAccountID,
                                 [enclosingFolderAttributes objectForKey: NSFileOwnerAccountName],      NSFileOwnerAccountName,
                                 [enclosingFolderAttributes objectForKey: NSFilePosixPermissions],      NSFilePosixPermissions,
                                 nil];
    if ( ! [gFileMgr tbCreateDirectoryAtPath: path withIntermediateDirectories: NO attributes: attributes]  ) {
        errorExit();
    }

    Log(@"Created %@ with owner %@:%@ (%@:%@) and permissions 0%lo", path,
               [attributes fileOwnerAccountName], [attributes fileGroupOwnerAccountName],
               [attributes fileOwnerAccountID],   [attributes fileGroupOwnerAccountID],   [attributes filePosixPermissions]);
}

static void securelyCopyDirectly(NSString * sourcePath, NSString * targetPath);

static void securelyCopyFileOrFolderContents(BOOL isDir, NSString * sourcePath, NSString * targetPath) {

    errorExitIfAnySymlinkOrDotDotInPath(sourcePath);
    errorExitIfAnySymlinkOrDotDotInPath(targetPath);

    // Copy the folder contents or the file contents
    if (  isDir  ) {
        NSDirectoryEnumerator * dirE = [gFileMgr enumeratorAtPath: sourcePath];
        NSString * path;
        while (  (path = [dirE nextObject])  ) {
            [dirE skipDescendants];
            NSString * fullSourcePath = [sourcePath stringByAppendingPathComponent: path];
            NSString * fullTargetPath = [targetPath stringByAppendingPathComponent: path];
            //
            // NOTE: RECURSION
            //
            securelyCopyDirectly(fullSourcePath, fullTargetPath);
        }
    } else {
        NSData *data = [NSData dataWithContentsOfFile: sourcePath
                                              options: (NSDataReadingUncached | NSDataReadingMappedIfSafe)
                                                error: nil];
        if (  ! data  ) {
            Log(@"Could not read data from %@", sourcePath);
            errorExit();
        }

        NSFileHandle * fh = [NSFileHandle fileHandleForWritingAtPath: targetPath];
        if (  ! fh  ) {
            Log(@"Could not get file handle to write to %@", targetPath);
            errorExit();
        }

        @try {
            [fh writeData: data];
        } @catch (NSException *exception exception) {
            Log(@"Could not write data (%@) to %@", exception, targetPath);
            [fh release];
            errorExit();
        }@finally {
            if (  gLogFileActions  ) {
                Log(@"FileAction: wrote data with NSFilehandle|writeData: for path'%@'", targetPath);
            }
        }

    }
}

static void securelyCopyDirectly(NSString * sourcePath, NSString * targetPath) {

    // Copies a file, or a folder and its contents, making sure the copy is owned by root:wheel with 0700 permissions.
    //
    // DO NOT USE THIS FUNCTION DIRECTLY: Use securelyCopy() instead.
    //
    // This routine is called only by securelyCopy() and securelyCopyFileOrFolderContents().

    errorExitIfAnySymlinkOrDotDotInPath(sourcePath);
    errorExitIfAnySymlinkOrDotDotInPath(targetPath);

    BOOL isDir;

    if (  ! [gFileMgr fileExistsAtPath: sourcePath isDirectory: &isDir]  ) {
        Log(@"Does not exist: %@", sourcePath);
        errorExit();
    }

    securelyDeleteItemIfItExists(targetPath);

    NSString * container = [targetPath stringByDeletingLastPathComponent];
    if (  ! [gFileMgr fileExistsAtPath: container]  ) {
        securelyCreateFolderAndParents( container);
    }

    securelyCreateFileOrDirectoryEntry(isDir, targetPath);

    securelyCopyFileOrFolderContents(isDir, sourcePath, targetPath);
}

static NSString * openvpnConfigPathFromPath(NSString * path) {

    // Search path for all .ovpn files. Return path if one, nil if none, and errorExit if more than one

    NSString * configPath = nil;

    NSDirectoryEnumerator * dirE = [gFileMgr enumeratorAtPath: path];
    NSString * subPath;
    while (  (subPath = [dirE nextObject])  ) {
        if (  [subPath.lastPathComponent.pathExtension isEqualToString: @"ovpn"]  ) {
            if (  configPath  ) {
                Log(@"Too many .opvn files in '%@'", path);
                errorExit();
            }
            configPath = [path stringByAppendingPathComponent: subPath];
        }
    }

    return configPath;
}

static void securelyCopy(NSString * sourcePath, NSString * targetPath) {

    // Copies a file, or a folder and its contents, making sure the copy is owned by root:wheel with 0700 permissions.
    //
    // Uses an intermediate file or folder and then renames it, so no partial copy has been done if an error occurs.

    errorExitIfAnySymlinkOrDotDotInPath(sourcePath);
    errorExitIfAnySymlinkOrDotDotInPath(targetPath);

    BOOL isDir;

    if (  ! [gFileMgr fileExistsAtPath: sourcePath isDirectory: &isDir]  ) {
        Log(@"Does not exist: %@", sourcePath);
        errorExit();
    }

    NSString * tempPath = [L_AS_T_TEMP stringByAppendingPathComponent: NSUUID.UUID.UUIDString];

    securelyCopyDirectly(sourcePath, tempPath);

    securelyCreateFolderAndParents([targetPath stringByDeletingLastPathComponent]);

    securelyRename(tempPath, targetPath);
}

static void securelyMoveTblkIncludingPrivate(NSString * sourcePath, NSString * targetPath) {

    // Renames or moves one .tblk to another.
    // If renaming, renames the .tblk, and, if it was a shadow copy, then renames the private copy.
    // If moving to shadow, copies the shadow to the private copy.
    // If moving to shared, deletes the private copy.

    errorExitIfAnySymlinkOrDotDotInPath(sourcePath);
    errorExitIfAnySymlinkOrDotDotInPath(targetPath);

    //
    // SHADOW TO SHADOW OR SHARED TO SHARED
    //
    // Simple rename, perhaps creating enclosing folders

    if (   (   [sourcePath hasPrefix: [L_AS_T_SHARED    stringByAppendingString: @"/"]]
            && [targetPath hasPrefix: [L_AS_T_SHARED    stringByAppendingString: @"/"]] )
        || (   [sourcePath hasPrefix: [userShadowPath() stringByAppendingString: @"/"]]
            && [targetPath hasPrefix: [userShadowPath() stringByAppendingString: @"/"]] )  ) {

        Log(@"MOVE SHADOW TO SHADOW OR SHARED TO SHARED '%@' to '%@'", sourcePath, targetPath);

        // Rename the Shared or Shadow copy
        securelyRename(sourcePath, targetPath);
        if (  [sourcePath hasPrefix: [userShadowPath() stringByAppendingString: @"/"]]  ) {
            securelyKeepRootOwnershipAndSetPermissionsOnFolderAndContents(targetPath);
        } else {
            ; // Ownership & permissions are unchanged.
        }

        // If source and target are Shadow copy, rename the Private copy
        if (  [sourcePath hasPrefix: [userShadowPath() stringByAppendingString: @"/"]]  ) {
            NSString * sourcePrivatePath = [userPrivatePath() stringByAppendingPathComponent: lastPartOfPath(sourcePath)];
            NSString * targetPrivatePath = [userPrivatePath() stringByAppendingPathComponent: lastPartOfPath(targetPath)];
            securelyRename(sourcePrivatePath, targetPrivatePath);
            // Ownership & permissions are unchanged.
        }
        return;
    }

    //
    // SHADOW TO SHARED
    //

    if (   [sourcePath hasPrefix: [userShadowPath() stringByAppendingString: @"/"]]
        && [targetPath hasPrefix: [L_AS_T_SHARED    stringByAppendingString: @"/"]]  ) {

        Log(@"MOVE SHADOW TO SHARED '%@' to '%@'", sourcePath, targetPath);

        // Rename the Shadow copy to Shared
        securelyRename(sourcePath, targetPath);
        securelyKeepRootOwnershipAndSetPermissionsOnFolderAndContents(targetPath);

        // Delete the Private copy
        NSString * sourcePrivatePath = [userPrivatePath() stringByAppendingPathComponent: lastPartOfPath(sourcePath)];
        if (  [gFileMgr fileExistsAtPath: sourcePrivatePath]  ) {
            securelyDeleteItem(sourcePrivatePath);
       }
        return;
    }

    //
    // SHARED TO SHADOW
    //
    if (   [sourcePath hasPrefix: [L_AS_T_SHARED    stringByAppendingString: @"/"]]
        && [targetPath hasPrefix: [userShadowPath() stringByAppendingString: @"/"]]  ) {

        Log(@"MOVE SHARED TO SHADOW '%@' to '%@'", sourcePath, targetPath);

        // Rename the Shared copy to Shadow
        securelyRename(sourcePath, targetPath);
        securelyKeepRootOwnershipAndSetPermissionsOnFolderAndContents(targetPath);

        // Copy the (new) Shadow copy to the Private copy
        NSString * targetPrivatePath = [userPrivatePath() stringByAppendingPathComponent: lastPartOfPath(targetPath)];
        securelyCopy(targetPath, targetPrivatePath);
        securelySetUserOwnershipAndPermissionsOnFolderAndContents(targetPrivatePath);
        return;
    }

    //
    // TEMP_COPY TO PRIVATE
    //

    if (   [sourcePath hasPrefix: [L_AS_T_TEMP      stringByAppendingString: @"/"]]
        && [targetPath hasPrefix: [userShadowPath() stringByAppendingString: @"/"]]  ) {

        Log(@"MOVE TEMP COPY TO PRIVATE '%@' to '%@'", sourcePath, targetPath);

        // Rename the copy of the Shadow to the Private copy
        securelyRename(sourcePath, targetPath);
        securelyKeepRootOwnershipAndSetPermissionsOnFolderAndContents(targetPath);

        // Set ownership and permissions on the private copy
        NSString * targetPrivatePath = [userPrivatePath() stringByAppendingPathComponent: lastPartOfPath(targetPath)];
        securelySetUserOwnershipAndPermissionsOnFolderAndContents(targetPrivatePath);
       return;
    }

    Log(@"UNEXPECTED SOURCE AND TARGET COMBINATION FOR MOVE OF\n'%@' to\n'%@'", sourcePath, targetPath);
    errorExit();
}

static BOOL testRenamex_np(NSString * folder) {

    errorExitIfAnySymlinkOrDotDotInPath(folder);

    BOOL oldLogFileActions = gLogFileActions;
    gLogFileActions = NO;

    // Touch two files (delete them first if they exist)
    NSString * test1Path = [folder stringByAppendingPathComponent: @"renamex_np-test-target-1"];
    securelyDeleteItemIfItExists(test1Path);
    if (  ! [gFileMgr createFileAtPath: test1Path contents: nil attributes: nil]  ) {
        Log(@"testRenamex_np: Can't create renamex_np-test-target-1 in %@", folder);
    }
    NSString * test2Path = [folder stringByAppendingPathComponent: @"renamex_np-test-target-2"];
    securelyDeleteItemIfItExists(test2Path);
    if (  ! [gFileMgr createFileAtPath: test2Path contents: nil attributes: nil]  ) {
        Log(@"testRenamex_np: Can't create renamex_np-test-target-2 in %@", folder);
    }

    // Try to rename test1 to test2. This should fail because test2 exists and the RENAME_EXCL option is used
    if (  0 == renamex_np(fileSystemRepresentationFromPath(test1Path), fileSystemRepresentationFromPath(test2Path),(RENAME_NOFOLLOW_ANY | RENAME_EXCL))  ) {
        // renamex_np succeeded but should have failed
        Log(@"renamex_np() test #1 failed for %@", folder);
        securelyDeleteItemIfItExists(test1Path);
        securelyDeleteItemIfItExists(test2Path);
        gLogFileActions = oldLogFileActions;
        return FALSE;
    }

    securelyDeleteItemIfItExists(test2Path);

    // Try to rename test1 to test2. This should now succeed because test2 does not exist
    if (  0 != renamex_np(fileSystemRepresentationFromPath(test1Path), fileSystemRepresentationFromPath(test2Path),(RENAME_NOFOLLOW_ANY | RENAME_EXCL))  ) {
        // renamex_np() failed
        Log(@"renamex_np() test #2 failed for %@", folder);
        securelyDeleteItemIfItExists(test1Path);
        securelyDeleteItemIfItExists(test2Path);
        gLogFileActions = oldLogFileActions;
        return FALSE;
    }

    securelyDeleteItemIfItExists(test2Path);    // test1 was succcesfully renamed to test2, so delete test2

    gLogFileActions = oldLogFileActions;
    return TRUE;
 }

//**************************************************************************************************************************
// USER INFORMATION

static NSString * userUsername(void) {

    if (  gUsername != nil  ) {
        return gUsername;
    }

    Log(@"Tried to access userUsername, which was not set");
    errorExit();
    return nil; // Satisfy analyzer
}

static NSString * userHomeDirectory(void) {

    if (  gHomeDirectory != nil  ) {
        return gHomeDirectory;
    }

    Log(@"Tried to access userHomeDirectory, which was not set");
    errorExit();
    return nil; // Satisfy analyzer
}

static NSString * userPrivatePath(void) {

    if (  gPrivatePath != nil  ) {
        return gPrivatePath;
    }

    Log(@"Tried to access userPrivatePath, which was not set");
    errorExit();
    return nil; // Satisfy analyzer
}

static NSString * userShadowPath(void) {
    if (  gShadowPath != nil  ) {
        return gShadowPath;
    }

    Log(@"Tried to access userShadowPath, which was not set");
    errorExit();
    return nil; // Satisfy analyzer
}

static uid_t userUID(void) {

    if (  gUserID != 0  ) {
        return gUserID;
    }

    Log(@"Tried to access userUID, which was not set");
    errorExit();
    return 0; // Satisfy analyzer
}

static gid_t userGID(void) {

    if (  gGroupID != 0  ) {
        return gGroupID;
    }

    Log(@"Tried to access userGID, which was not set");
    errorExit();
    return 0; // Satisfy analyzer
}

static void getUidAndGidFromUsername(NSString * username, uid_t * uid_ptr, gid_t * gid_ptr) {

    // Modified version of sample code by Matthew Flaschen
    // from https://stackoverflow.com/questions/1009254/programmatically-getting-uid-and-gid-from-username-in-unix

    const char * username_C = [username cStringUsingEncoding: NSASCIIStringEncoding];
    if(  username_C == NULL  ) {
        Log(@"Failed to convert username '%@' to an ASCII username.", username);
        errorExit();
    }

    struct passwd * pwd = calloc(1, sizeof(struct passwd));
    if(  pwd == NULL  ) {
        Log(@"Failed to allocate struct passwd for getpwnam_r.");
        errorExit();
    }

    size_t buffer_len = sysconf(_SC_GETPW_R_SIZE_MAX) * sizeof(char);
    char *buffer = malloc(buffer_len);
    if(  buffer == NULL  ) {
        Log(@"Failed to allocate buffer for getpwnam_r.");
        free(pwd);
        errorExit();
    }

    errno = 0;
    struct passwd * result = pwd;  // getpwnam_r overwrites this copy of pwd but we keep pwd so we can free it later
    int return_status = getpwnam_r(username_C, pwd, buffer, buffer_len, &result);
    if (  return_status != 0  ) {
        Log(@"getpwnam_r returned error %d; errno = %d ('%s')", return_status, errno, strerror(errno));
        free(pwd);
        free(buffer);
        errorExit();
    }
    if(  result == NULL  ) {
        Log(@"getpwnam_r failed to find entry for '%@'. (First argument to installer must be a username.)", username);
        free(pwd);
        free(buffer);
        errorExit();
    }

    *uid_ptr = result->pw_uid;
    *gid_ptr = result->pw_gid;

    free(pwd);
    free(buffer);

    if (  *uid_ptr == 0  ) {
        Log(@"Cannot run installer using username 'root'");
        errorExit();
    }
}

static BOOL usernameIsValid(NSString * username) {

    // Modified from Dave DeLong's updated answer to his own question at
    // https://stackoverflow.com/questions/1303561/list-of-all-users-and-groups

    ODSession * session = ODSession.defaultSession;
    ODNode * root = [ODNode nodeWithSession: session
                                       name: @"/Local/Default"
                                      error: nil];
    ODQuery * q = [ODQuery queryWithNode: root
                          forRecordTypes: kODRecordTypeUsers
                               attribute: nil
                               matchType: 0
                             queryValues: nil
                        returnAttributes: nil
                          maximumResults: 0
                                   error: nil];

    NSArray * results = [q resultsAllowingPartial: NO
                                            error: nil];

    for (  ODRecord * r in results  ) {
        if (  [username isEqualToString: [r recordName]]  ) {
            return YES;
        }
    }

    return NO;
}

static NSString * usernameFromPossiblePrivatePath(NSString * path) {

    NSString * absolutePath = makePathAbsolute(path);

    if (  ! [absolutePath hasPrefix: @"/Users/"]  ) {
        return nil;
    }

    NSRange afterUsersSlash = NSMakeRange([@"/Users/" length], [absolutePath length] - [@"/Users/" length]);
    NSRange slashAfterName = [absolutePath rangeOfString: @"/" options: 0 range: afterUsersSlash];
    if (  slashAfterName.location == NSNotFound  ) {
        slashAfterName.location = absolutePath.length;
    }

    NSString * username = [absolutePath substringWithRange: NSMakeRange(afterUsersSlash.location, slashAfterName.location - afterUsersSlash.location)];
    if (  usernameIsValid(username)  ) {
        return username;
    }

    return nil;
}

static NSString * privatePathFromUsername(NSString * username) {

    NSString * privatePath = [[[[[@"/Users/"
                                  stringByAppendingPathComponent: username]
                                 stringByAppendingPathComponent: @"Library"]
                                stringByAppendingPathComponent: @"Application Support"]
                               stringByAppendingPathComponent: @"Tunnelblick"]
                              stringByAppendingPathComponent: @"Configurations"];
    return privatePath;
}

static void setupUserGlobalsFromGUsername(void) {

    gHomeDirectory = [[@"/Users" stringByAppendingPathComponent: gUsername]
                      retain];
    gPrivatePath = [[[[[gHomeDirectory
                        stringByAppendingPathComponent: @"Library"]
                       stringByAppendingPathComponent: @"Application Support"]
                      stringByAppendingPathComponent: @"Tunnelblick"]
                     stringByAppendingPathComponent: @"Configurations"]
                    retain];
    gShadowPath = [[L_AS_T_USERS
                    stringByAppendingPathComponent: gUsername]
                   retain];
    getUidAndGidFromUsername(gUsername, &gUserID, &gGroupID);
    gGroupID = privateFolderGroup(gPrivatePath);
}

static void setupUserGlobals(int argc, char *argv[], unsigned operation) {

    gUserID = getuid();

    if (  gUserID != 0  ) {
        //
        // Calculate user info from uid
        //
        // (Already have gUserID)
        gUsername = [NSUserName() retain];
        gHomeDirectory = [NSHomeDirectory() retain];
        gPrivatePath = [[[[[gHomeDirectory
                            stringByAppendingPathComponent: @"Library"]
                           stringByAppendingPathComponent: @"Application Support"]
                          stringByAppendingPathComponent: @"Tunnelblick"]
                         stringByAppendingPathComponent: @"Configurations"]
                        retain];
        gShadowPath = [[L_AS_T_USERS
                        stringByAppendingPathComponent: gUsername]
                       retain];
        gGroupID = privateFolderGroup(gPrivatePath);
        Log(@"Determined username '%@' from getuid(): %u", gUsername, gUserID);

    } else if (  operation == INSTALLER_INSTALL_PRIVATE_CONFIG  ) {
        //
        // Calculate user info from username given as an argument
        //

        if (  argc < 3  ) {
            Log(@"Must provide path and username when copying a private configuration");
            errorExit();
        }

        gUsername = [[NSString stringWithCString: argv[2] encoding: NSASCIIStringEncoding] retain];
        if (   ( gUsername == nil )
            || ( ! usernameIsValid(gUsername) )  ) {
            Log(@"Second argument must be a valid username");
            errorExit();
        }

        setupUserGlobalsFromGUsername();
        if (  gUserID == 0  ) {
            Log(@"Could not get uid for user '%@' (determined from second argument)", gUsername);
        } else {
            Log(@"Determined username '%@' from second argument", gUsername);
        }
    } else {
        //
        // Calculate user info from current working directory path if possible
        //
        gUsername = [usernameFromPossiblePrivatePath([gFileMgr currentDirectoryPath]) retain];
        if (  gUsername  ) {
            Log(@"Determined username '%@' from current working directory", gUsername);
            setupUserGlobalsFromGUsername();

        } else {
            //
            // Calculate user info from a private path if one is provided as an argument
            //
            for (  int i=2; i<argc; i++  ) {
                NSString * path = [NSString stringWithCString: argv[i] encoding: NSUTF8StringEncoding];
                gUsername = [usernameFromPossiblePrivatePath(path) retain];
                if (  gUsername  ) {
                    break;
                }
            }

            if (  gUsername  ) {
                Log(@"Determined username '%@' from a path provided as an argument", gUsername);
                setupUserGlobalsFromGUsername();
            } else {
                //
                // Give up: set user info to zeros and nils.
                // For many operations (load kexts, etc.) it isn't needed.
                //
                gUserID = 0;
                gGroupID = 0;
                gUsername = nil;
                gPrivatePath = nil;
                gHomeDirectory = nil;
                Log(@"Unable to determine user. Some operations cannot be performed");
            }
        }
    }
}

//**************************************************************************************************************************
// LAUNCHDAEMON

static BOOL isLaunchDaemonLoaded(void) {
	
	// Must have uid=0 (not merely euid=0) for runTool(launchctl) to work properly
    if (  setuid(0)  ) {
		Log(@"setuid(0) failed; error was %d: '%s'", errno, strerror(errno));
		errorExit();
	}
	if (  setgid(0)  ) {
		Log(@"setgid(0) failed; error was %d: '%s'", errno, strerror(errno));
		errorExit();
	}
 	
	if (  ! [gFileMgr fileExistsAtPath: TUNNELBLICKD_PLIST_PATH]  ) {
		Log(@"No file at %@; assuming tunnelblickd is not loaded", TUNNELBLICKD_PLIST_PATH);
		return NO;
	}
	
	NSString * stdoutString = @"";
	NSString * stderrString = @"";
	NSArray * arguments = [NSArray arrayWithObject: @"list"];
	OSStatus status = runTool(TOOL_PATH_FOR_LAUNCHCTL, arguments, &stdoutString, &stderrString);
	if (   (status != EXIT_SUCCESS)
		|| [stdoutString isEqualToString: @""]  ) {
        
        Log(@"'%@ list' failed or had no output; assuming tunnelblickd is not loaded; error was %d: '%s'\nstdout = '%@'\nstderr='%@'",
                   TOOL_PATH_FOR_LAUNCHCTL, errno, strerror(errno), stdoutString, stderrString);
		return NO;
	}
	
	BOOL result = ([stdoutString rangeOfString: @"net.tunnelblick.tunnelblick.tunnelblickd"].length != 0);
	return result;
}

static void loadLaunchDaemonUsingLaunchctl(void) {
	
	// Must have uid=0 (not merely euid=0) for runTool(launchctl) to work properly
    if (  setuid(0)  ) {
		Log(@"setuid(0) failed; error was %d: '%s'", errno, strerror(errno));
		errorExit();
	}
	if (  setgid(0)  ) {
		Log(@"setgid(0) failed; error was %d: '%s'", errno, strerror(errno));
		errorExit();
	}
 	
	NSString * stdoutString = @"";
	NSString * stderrString = @"";
	
	if (  [gFileMgr fileExistsAtPath: TUNNELBLICKD_PLIST_PATH]  ) {
		NSArray * arguments = [NSArray arrayWithObjects: @"unload", TUNNELBLICKD_PLIST_PATH, nil];
		OSStatus status = runTool(TOOL_PATH_FOR_LAUNCHCTL, arguments, &stdoutString, &stderrString);
		if (  status != EXIT_SUCCESS  ) {
			Log(@"'%@ unload' failed; error was %d: '%s'\nstdout = '%@'\nstderr='%@'",
                       TOOL_PATH_FOR_LAUNCHCTL, errno, strerror(errno), stdoutString, stderrString);
			// Continue even after the error. If we can load, it doesn't matter that we didn't unload.
		}
		
		stdoutString = @"";
		stderrString = @"";
	}
	
	NSArray * arguments = [NSArray arrayWithObjects: @"load", @"-w", TUNNELBLICKD_PLIST_PATH, nil];
	OSStatus status = runTool(TOOL_PATH_FOR_LAUNCHCTL, arguments, &stdoutString, &stderrString);
	if (   (status == EXIT_SUCCESS)
		&& [stdoutString isEqualToString: @""]
		&& [stderrString isEqualToString: @""]  ) {
		Log(@"Used launchctl to load tunnelblickd");
	} else {
		Log(@"'%@ load -w %@' failed; status = %d; errno = %d: '%s'\nstdout = '%@'\nstderr='%@'",
                   TOOL_PATH_FOR_LAUNCHCTL, TUNNELBLICKD_PLIST_PATH, status, errno, strerror(errno), stdoutString, stderrString);
		errorExit();
	}
}

static void loadLaunchDaemonAndSaveHashes (NSDictionary * newPlistContents) {
	
    (void) newPlistContents;

    loadLaunchDaemonUsingLaunchctl();

    // Store the hash of the .plist and the daemon in files owned by root:wheel
    NSDictionary * hashFileAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                         @0, NSFileOwnerAccountID,
                                         @0, NSFileGroupOwnerAccountID,
                                         [NSNumber numberWithInt: PERMS_SECURED_READABLE], NSFilePosixPermissions,
                                         nil];
    
    NSData * plistData = [gFileMgr contentsAtPath: TUNNELBLICKD_PLIST_PATH];
    if (  ! plistData  ) {
        Log(@"Could not find tunnelblickd launchd .plist at '%@'", TUNNELBLICKD_PLIST_PATH);
        errorExit();
    }
    NSString * plistHash = sha256HexStringForData(plistData);
    NSData * plistHashData = [NSData dataWithBytes: [plistHash UTF8String] length: [plistHash length]];
    if (  ! [gFileMgr createFileAtPath: L_AS_T_TUNNELBLICKD_LAUNCHCTL_PLIST_HASH_PATH contents: plistHashData attributes: hashFileAttributes]  ) {
        Log(@"Could not store tunnelblickd launchd .plist hash");
        errorExit();
    }
    
#ifdef TBDebug
    NSString * resourcesPath = thisAppResourcesPath(); // (installer itself is in Resources, so this works)
    NSString * tunnelblickdPath = [resourcesPath stringByAppendingPathComponent: @"tunnelblickd"];
#else
    NSString * tunnelblickdPath = @"/Applications/Tunnelblick.app/Contents/Resources/tunnelblickd";
#endif
    NSData   * daemonData = [gFileMgr contentsAtPath: tunnelblickdPath];
    if (  ! daemonData  ) {
        Log(@"Could not find tunnelblickd at '%@'", tunnelblickdPath);
        errorExit();
    }
    NSString * daemonHash = sha256HexStringForData(daemonData);
    NSData * daemonHashData = [NSData dataWithBytes: [daemonHash UTF8String] length: [daemonHash length]];
    if (  ! [gFileMgr createFileAtPath: L_AS_T_TUNNELBLICKD_HASH_PATH contents: daemonHashData attributes: hashFileAttributes]  ) {
        Log(@"Could not store tunnelblickd hash");
        errorExit();
    }
}

static void setupLaunchDaemon(void) {

    copyAppToL_AS_T(APPLICATIONS_TB_APP);

    // If we are reloading the LaunchDaemon, we make sure it is up-to-date by copying its .plist into /Library/LaunchDaemons

    // Install or replace the tunnelblickd .plist in /Library/LaunchDaemons
    BOOL hadExistingPlist = [gFileMgr fileExistsAtPath: TUNNELBLICKD_PLIST_PATH];
    NSDictionary * newPlistContents = tunnelblickdPlistDictionaryToUse();
    if (  ! newPlistContents  ) {
        Log(@"Unable to get a model for tunnelblickd.plist");
        errorExit();
    }
    if (  hadExistingPlist  ) {
        securelyDeleteItem(TUNNELBLICKD_PLIST_PATH);
    }
    if (  [newPlistContents writeToFile: TUNNELBLICKD_PLIST_PATH atomically: YES] ) {
        if (  ! checkSetOwnership(TUNNELBLICKD_PLIST_PATH, NO, 0, 0)  ) {
            errorExit();
        }
        if (  ! checkSetPermissions(TUNNELBLICKD_PLIST_PATH, PERMS_SECURED_READABLE, YES)  ) {
            errorExit();
        }
        Log(@"%@ %@", (hadExistingPlist ? @"Replaced" : @"Installed"), TUNNELBLICKD_PLIST_PATH);
    } else {
        Log(@"Unable to create %@", TUNNELBLICKD_PLIST_PATH);
        errorExit();
    }

    // Load the new launch daemon so it is used immediately, even before the next system start
    // And save hashes of the tunnelblickd program and it's .plist, so we can detect when they need to be updated
    loadLaunchDaemonAndSaveHashes(newPlistContents);

}

//**************************************************************************************************************************
// KEXTS

static BOOL installOrUpdateOneKext(NSString * initialKextInLibraryExtensionsPath,
                            NSString * kextInAppPath,
                            NSString * finalNameOfKext,
                            BOOL       forceInstall) {

    // Installs a kext (if forceInstall) or updates an existing kext if it exists and is not identical to the copy in this application.
    //
    // Will update the filename of the kext to finalNameOfKext. (This is done because the initial testing of kexts on
    // Apple Silicon (M1) Macs installed kexts named "tun-notarized.kext" and "tap-notarized.kext", which do not contain "tunnelblick"
    // in their names. Including "tunnelblick" in the name of the kexts makes it easier for people to identify them.

    BOOL initialKextExists = [gFileMgr fileExistsAtPath: initialKextInLibraryExtensionsPath];

    if (  ! forceInstall  ) {
        
        if ( ! initialKextExists  ) {
            return NO;
        }
         
        NSString * initialNameOfKext = [initialKextInLibraryExtensionsPath lastPathComponent];

        if (   [initialNameOfKext isEqualToString: finalNameOfKext]
            && [gFileMgr contentsEqualAtPath: initialKextInLibraryExtensionsPath andPath: kextInAppPath]  ) {
            Log(@"Kext is up-to-date: %@", finalNameOfKext);
            return NO;
        }
    }
    
    if (  initialKextExists  ) {
        securelyDeleteItem(initialKextInLibraryExtensionsPath);
    }
    
    NSString * finalPath = [[initialKextInLibraryExtensionsPath stringByDeletingLastPathComponent]
                            stringByAppendingPathComponent: finalNameOfKext];

    if (  [gFileMgr fileExistsAtPath: finalPath]  ) {
        securelyDeleteItem(finalPath);
    }

    securelyCopy(kextInAppPath, finalPath);

    if ( ! checkSetOwnership(finalPath, YES, 0, 0)  ) {
        errorExit();
    }
    
    NSString * verb = (  initialKextExists
                       ? @"Updated"
                       : @"Installed");
    Log(@"%@ %@ in %@", verb, finalNameOfKext, [finalPath stringByDeletingLastPathComponent]);

    return YES;
}

static BOOL secureOneKext(NSString * path) {
    
    // Everything inside a kext should have 0755 permissions except Info.plist, CodeResources, and all contents of _CodeSignature, which should have 0644 permissions

    NSString * itemName;
    NSDirectoryEnumerator * kextEnum = [gFileMgr enumeratorAtPath: path];
    BOOL okSoFar = TRUE;
    while (  (itemName = [kextEnum nextObject])  ) {
        NSString * fullPath = [path stringByAppendingPathComponent: itemName];
        if (   [fullPath hasSuffix: @"/Info.plist"]
            || [fullPath hasSuffix: @"/CodeResources"]
            || [[[fullPath stringByDeletingLastPathComponent] lastPathComponent] isEqualToString: @"_CodeSignature"]  ) {
            okSoFar = checkSetPermissions(fullPath, PERMS_SECURED_READABLE, YES) && okSoFar;
        } else {
            okSoFar = checkSetPermissions(fullPath, PERMS_SECURED_EXECUTABLE, YES) && okSoFar;
        }
    }
    
    return okSoFar;
}

static void updateTheKextCaches(void) {

    // According to the man page for kextcache, kext caches should be updated by executing 'touch /Library/Extensions'; the following is the equivalent:
    if (  utimes(fileSystemRepresentationFromPath(@"/Library/Extensions"), NULL) != 0  ) {
        Log(@"utimes(\"/Library/Extensions\", NULL) failed with error %d ('%s')", errno, strerror(errno));
        errorExit();
    }
}

static BOOL uninstallOneKext(NSString * path) {
    
    if (  ! [gFileMgr fileExistsAtPath: path]  ) {
        return NO;
    }
    
    securelyDeleteItem(path);

    Log(@"Uninstalled %@", path.lastPathComponent);

    return YES;
}

static void uninstallKexts(void) {
    
    BOOL shouldUpdateKextCaches = uninstallOneKext(@"/Library/Extensions/tunnelblick-tun.kext");
    
    shouldUpdateKextCaches = uninstallOneKext(@"/Library/Extensions/tunnelblick-tap.kext") || shouldUpdateKextCaches;

    if (  shouldUpdateKextCaches  ) {
        updateTheKextCaches();
    } else {
        Log(@"There are no kexts to uninstall");
        gErrorOccurred = TRUE;
    }
}

static NSString * kextPathThatExists(NSString * resourcesPath, NSString * nameOne, NSString * nameTwo) {
    
    NSString * nameOnePath = [resourcesPath stringByAppendingPathComponent: nameOne];
    if ( [gFileMgr fileExistsAtPath: nameOnePath]  ) {
        return nameOnePath;
    }

    NSString * nameTwoPath = [resourcesPath stringByAppendingPathComponent: nameTwo];
    if ( [gFileMgr fileExistsAtPath: nameTwoPath]  ) {
        return nameTwoPath;
    }

    return nil;
}

static void installOrUpdateKexts(BOOL forceInstall) {

    // Update or install the kexts at most once each time installer is invoked
    static BOOL haveUpdatedKexts = FALSE;
    
    if (  haveUpdatedKexts  ) {
        return;
    }
    
    BOOL shouldUpdateKextCaches = FALSE;
    
    NSString * resourcesPath = thisAppResourcesPath();


    NSString * tunKextInAppPath = kextPathThatExists(resourcesPath, @"tun-notarized.kext", @"tun.kext");
    NSString * tapKextInAppPath = kextPathThatExists(resourcesPath, @"tap-notarized.kext", @"tap.kext");
    
    if (   ( ! tunKextInAppPath)
        || ( ! tapKextInAppPath)  ) {
        Log(@"Tun or tap kext not found");
        errorExit();
    }
    
    if (   ( ! secureOneKext(tunKextInAppPath) )
        || ( ! secureOneKext(tapKextInAppPath))  ) {
        errorExit();
    }
    
    NSString * tunKextInstallName = @"tunnelblick-tun.kext";
    NSString * tapKextInstallName = @"tunnelblick-tap.kext";

    NSString * tunKextInstallPath = [@"/Library/Extensions" stringByAppendingPathComponent: tunKextInstallName];
    NSString * tapKextInstallPath = [@"/Library/Extensions" stringByAppendingPathComponent: tapKextInstallName];

    NSString * oldTunKextInstallPath = [@"/Library/Extensions" stringByAppendingPathComponent: @"tun-notarized.kext"];
    NSString * oldTapKextInstallPath = [@"/Library/Extensions" stringByAppendingPathComponent: @"tap-notarized.kext"];

    if (   [gFileMgr fileExistsAtPath: oldTunKextInstallPath]
        || [gFileMgr fileExistsAtPath: oldTapKextInstallPath]  ) {

        // Replace the original kexts used for testing on M1 Macs, changing their names to the new names
        shouldUpdateKextCaches = installOrUpdateOneKext(oldTunKextInstallPath, tunKextInAppPath, tunKextInstallName, forceInstall) || shouldUpdateKextCaches;
        shouldUpdateKextCaches = installOrUpdateOneKext(oldTapKextInstallPath, tapKextInAppPath, tapKextInstallName, forceInstall) || shouldUpdateKextCaches;
    } else {

        // Update the standard kexts
        shouldUpdateKextCaches = installOrUpdateOneKext(tunKextInstallPath, tunKextInAppPath, tunKextInstallName, forceInstall) || shouldUpdateKextCaches;
        shouldUpdateKextCaches = installOrUpdateOneKext(tapKextInstallPath, tapKextInAppPath, tapKextInstallName, forceInstall) || shouldUpdateKextCaches;
    }
    
    if (  shouldUpdateKextCaches  ) {
        updateTheKextCaches();
		haveUpdatedKexts = TRUE;
    }
}

//**************************************************************************************************************************
// HIGH LEVEL ROUTINES

static void createSecuredConfigurationsSubfolder(NSString * path) {

    // Use to create and secure an empty configurations subfolder (either Shared or a shadow folder).

    errorExitIfAnySymlinkOrDotDotInPath(path);

    // For anything enclosed by either L_AS_T_TEMP or L_AS_T_USERS/username/, use PERMS_SECURED_OTHER
    mode_t perms = (  (   [path hasPrefix: [L_AS_T_TEMP stringByAppendingString: @"/"]]
                       || (   [path hasPrefix: [L_AS_T_USERS stringByAppendingString: @"/"]]
                           && [path pathComponents].count > 6   )  )
                    ? PERMS_SECURED_OTHER
                    : PERMS_SECURED_FOLDER);

    if (  ! createDirWithPermissionAndOwnership(path, perms, 0, 0)  ) {
        errorExit();
    }
}

static void secureOpenvpnBinariesFolder(NSString * enclosingFolder) {

    if (   ( ! checkSetOwnership(enclosingFolder, YES, 0, 0))
        || ( ! checkSetPermissions(enclosingFolder, PERMS_SECURED_FOLDER, NO))  ) {
        errorExit();
    }

    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: enclosingFolder];
    NSString * folder;
    BOOL isDir;
    while (  (folder = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        NSString * fullPath = [enclosingFolder stringByAppendingPathComponent: folder];
        if (   [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
            && isDir  ) {
            if (  ! checkSetPermissions(fullPath, PERMS_SECURED_FOLDER, YES)  ) {
                errorExit();
            }
            if (  [folder hasPrefix: @"openvpn-"]  ) {
                NSString * thisOpenvpnPath = [fullPath stringByAppendingPathComponent: @"openvpn"];
                if (  ! checkSetPermissions(thisOpenvpnPath, PERMS_SECURED_EXECUTABLE, YES)  ) {
                    errorExit();
                }
                NSString * thisOpenvpnDownRootPath = [fullPath stringByAppendingPathComponent: @"openvpn-down-root.so"];
                if (  ! checkSetPermissions(thisOpenvpnDownRootPath, PERMS_SECURED_ROOT_EXEC, YES)  ) {
                    errorExit();
                }
            }
        }
    }
}

static void setupLibrary_Application_Support_Tunnelblick(void) {
	
	if (  ! createDirWithPermissionAndOwnership(@"/Library/Application Support/Tunnelblick",
												PERMS_SECURED_FOLDER, 0, 0)  ) {
		errorExit();
	}
	
	if (  ! createDirWithPermissionAndOwnership(L_AS_T_LOGS,
												PERMS_SECURED_FOLDER, 0, 0)  ) {
		errorExit();
	}
	
	if (  ! createDirWithPermissionAndOwnership(TUNNELBLICKD_LOG_FOLDER,
												PERMS_SECURED_FOLDER, 0, 0)  ) {
		errorExit();
	}
	
	if (  ! createDirWithPermissionAndOwnership(L_AS_T_SHARED,
												PERMS_SECURED_FOLDER, 0, 0)  ) {
		errorExit();
	}
	
    if (  ! createDirWithPermissionAndOwnership(L_AS_T_MIPS,
                                                PERMS_SECURED_FOLDER, 0, 0)  ) {
        errorExit();
    }

	if (  ! createDirWithPermissionAndOwnership(L_AS_T_EXPECT_DISCONNECT_FOLDER_PATH,
												PERMS_SECURED_FOLDER, 0, 0)  ) {
		errorExit();
	}
	
	if (  ! createDirWithPermissionAndOwnership(L_AS_T_USERS,
												PERMS_SECURED_FOLDER, 0, 0)  ) {
		errorExit();
	}
	
    if (  ! createDirWithPermissionAndOwnership(L_AS_T_TEMP,
                                                PERMS_SECURED_OTHER, 0, 0)  ) {
        errorExit();
    }

	if (  [gFileMgr fileExistsAtPath: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH]  ) {
		errorExitIfAnySymlinkOrDotDotInPath(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);
		if (   ( ! checkSetOwnership(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH, NO, 0, 0))
			|| ( ! checkSetPermissions(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH, PERMS_SECURED_READABLE, NO))  ) {
			errorExit();
		}
	}
	
	if (  [gFileMgr fileExistsAtPath: L_AS_T_OPENVPN]  ) {
		secureOpenvpnBinariesFolder(L_AS_T_OPENVPN);
	}

    if (  ! dealWithDotOldAndHyphenOldApp()  ) {
        errorExit();
    }

    if (  ! removeOldDotMipFile()  ) {
        errorExit();
    }
}

static void setupUser_Library_Application_Support_Tunnelblick(void) {

    if (  gHomeDirectory  ) {

        if (  ! createDirWithPermissionAndOwnership([L_AS_T_USERS stringByAppendingPathComponent: userUsername()],
                                                    PERMS_SECURED_FOLDER, 0, 0)  ) {
            errorExit();
        }

        NSString * userL_AS_T_Path= [[[userHomeDirectory()
                                       stringByAppendingPathComponent: @"Library"]
                                      stringByAppendingPathComponent: @"Application Support"]
                                     stringByAppendingPathComponent: @"Tunnelblick"];

        mode_t permissions = privateFolderPermissions(userL_AS_T_Path);

        if (  ! createDirWithPermissionAndOwnership(userL_AS_T_Path,
                                                    permissions, userUID(), userGID())  ) {
            errorExit();
        }

        if (  ! createDirWithPermissionAndOwnership([userL_AS_T_Path stringByAppendingPathComponent: @"Configurations"],
                                                    permissions, userUID(), userGID())  ) {
            errorExit();
        }

        if (  ! createDirWithPermissionAndOwnership([userL_AS_T_Path stringByAppendingPathComponent: @"TBLogs"],
                                                    permissions, userUID(), userGID())  ) {
            errorExit();
        }
    }
}

static void copyTheApp(void) {

    NSString * sourcePath = [[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];

    errorExitIfAnySymlinkOrDotDotInPath(@"/Applications");

    if (  [sourcePath isEqualToString: APPLICATIONS_TB_APP]  ) {
        Log(@"Not copying app because this copy is already where it should be copied");
    } else {
        if (  [gFileMgr fileExistsAtPath: APPLICATIONS_TB_APP]  ) {
            if (  [gFileMgr fileExistsAtPath: L_AS_T_TB_OLD]  ) {
                securelyDeleteItem(L_AS_T_TB_OLD);
            }
            copyOrMoveOneFolderOrTblk(APPLICATIONS_TB_APP, L_AS_T_TB_OLD, NO);
        }
    }

    copyOrMoveOneFolderOrTblk(sourcePath, APPLICATIONS_TB_APP, NO);

    secureTheApp([[APPLICATIONS_TB_APP
                   stringByAppendingPathComponent: @"Contents"]
                  stringByAppendingPathComponent: @"Resources"],
                 TRUE);

    removeExtendedAttributes(APPLICATIONS_TB_APP);
}

static void copyAppToL_AS_T(NSString * sourcePath) {

    // Don't copy app to L_AS_T more than once per install!
    static BOOL appHasBeenCopiedToL_AS_T = false;

    if (  appHasBeenCopiedToL_AS_T  ) {
        return;
    }

    NSString * targetPath = L_AS_T_TB_APP;

    // If this was an update from Tunnelblick 7.0, the new .app is in L_AS_T and /Applications has a symlink to L_AS_T/Tunnelblick.app
    // In that situation, delete the symlink and swap the source and target, i.e., copy from L_AS_T to /Applications
    // Check  (1) sourcePath is /Applications/Tunnelblick.app
    //        (2) targetPath exists, and
    //        (3) sourcePath is a symlink
    BOOL updateFrom7 = FALSE;
    if (  [sourcePath isEqualToString: APPLICATIONS_TB_APP]  ) {
        if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
            NSError * err = nil;
            NSDictionary * dict = [gFileMgr attributesOfItemAtPath: sourcePath error: &err];
            if (  [dict.fileType isEqualToString: NSFileTypeSymbolicLink]  ) {
                Log(@"Updating from 7.0:");
                // Delete the symlink
                int result = unlink(sourcePath.fileSystemRepresentation);
                if (  result != 0 ) {
                    Log(@"Error %u ('%s') trying to delete symlink at %@", errno, strerror(errno), sourcePath);
                    errorExit();
                }
                Log(@"    Deleted the symlink at %@", sourcePath);
                NSString * temp = targetPath;
                targetPath = sourcePath;
                sourcePath = temp;
                Log(@"    Swapped source and target paths");
                secureTheApp([[sourcePath stringByAppendingPathComponent: @"Contents"]
                              stringByAppendingPathComponent: @"Resources"], NO);
                updateFrom7 = TRUE;
            }
        }
    }

    if (  ! [gFileMgr tbRemovePathIfItExists: targetPath]  ) {
        errorExit();
    }
    if (  [gFileMgr tbCopyItemAtPath: sourcePath toBeOwnedByRootWheelAtPath: targetPath]) {
        Log(@"Copied (C) %@ to %@", sourcePath, targetPath);
        if (  updateFrom7  ) {
            secureTheApp([[targetPath stringByAppendingPathComponent: @"Contents"]
                          stringByAppendingPathComponent: @"Resources"], NO);
            Log(@"Secured %@", targetPath);
        }
        removeExtendedAttributes(targetPath);
    } else {
        Log(@"Unable to copy %@ to %@", sourcePath, targetPath);
        errorExit();
    }

    appHasBeenCopiedToL_AS_T = true;
}

static void secureTheApp(NSString * appResourcesPath, BOOL copyToL_AS_T) {

	NSString *contentsPath				= [appResourcesPath stringByDeletingLastPathComponent];
	NSString *infoPlistPath				= [contentsPath stringByAppendingPathComponent: @"Info.plist"];
	NSString *openvpnstartPath          = [appResourcesPath stringByAppendingPathComponent:@"openvpnstart"                                   ];
	NSString *openvpnPath               = [appResourcesPath stringByAppendingPathComponent:@"openvpn"                                        ];
	NSString *atsystemstartPath         = [appResourcesPath stringByAppendingPathComponent:@"atsystemstart"                                  ];
    NSString *TunnelblickUpdateHelperPath = [appResourcesPath stringByAppendingPathComponent:@"TunnelblickUpdateHelper"                      ];
    NSString *installerPath             = [appResourcesPath stringByAppendingPathComponent:@"installer"                                      ];
	NSString *ssoPath                   = [appResourcesPath stringByAppendingPathComponent:@"standardize-scutil-output"                      ];
	NSString *pncPath                   = [appResourcesPath stringByAppendingPathComponent:@"process-network-changes"                        ];
    NSString *uninstallerScriptPath     = [appResourcesPath stringByAppendingPathComponent:@"tunnelblick-uninstaller.sh"                     ];
    NSString *uninstallerAppleSPath     = [appResourcesPath stringByAppendingPathComponent:@"tunnelblick-uninstaller.applescript"            ];
	NSString *tunnelblickdPath          = [appResourcesPath stringByAppendingPathComponent:@"tunnelblickd"                                   ];
	NSString *tunnelblickHelperPath     = [appResourcesPath stringByAppendingPathComponent:@"tunnelblick-helper"                             ];
	NSString *leasewatchPath            = [appResourcesPath stringByAppendingPathComponent:@"leasewatch"                                     ];
	NSString *leasewatch3Path           = [appResourcesPath stringByAppendingPathComponent:@"leasewatch3"                                    ];
	NSString *pncPlistPath              = [appResourcesPath stringByAppendingPathComponent:@"ProcessNetworkChanges.plist"                    ];
	NSString *leasewatchPlistPath       = [appResourcesPath stringByAppendingPathComponent:@"LeaseWatch.plist"                               ];
	NSString *leasewatch3PlistPath      = [appResourcesPath stringByAppendingPathComponent:@"LeaseWatch3.plist"                              ];
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
	NSString *clientNewAlt4UpPath       = [appResourcesPath stringByAppendingPathComponent:@"client.4.up.tunnelblick.sh"                     ];
	NSString *clientNewAlt4DownPath     = [appResourcesPath stringByAppendingPathComponent:@"client.4.down.tunnelblick.sh"                   ];
    NSString *clientNewAlt5UpPath       = [appResourcesPath stringByAppendingPathComponent:@"client.5.up.tunnelblick.sh"                     ];
    NSString *clientNewAlt5DownPath     = [appResourcesPath stringByAppendingPathComponent:@"client.5.down.tunnelblick.sh"                   ];
	NSString *reactivateTunnelblickPath = [appResourcesPath stringByAppendingPathComponent:@"reactivate-tunnelblick.sh"                      ];
	NSString *reenableNetworkServicesPath = [appResourcesPath stringByAppendingPathComponent:@"re-enable-network-services.sh"				 ];
	NSString *freePublicDnsServersPath  = [appResourcesPath stringByAppendingPathComponent:@"FreePublicDnsServersList.txt"                   ];
	NSString *iconSetsPath              = [appResourcesPath stringByAppendingPathComponent:@"IconSets"                                       ];
	
	NSString *tunnelblickdPlistPath     = [appResourcesPath stringByAppendingPathComponent:[TUNNELBLICKD_PLIST_PATH lastPathComponent]];
	
	NSString *tunnelblickPath = [contentsPath stringByDeletingLastPathComponent];
	
	BOOL okSoFar = checkSetOwnership(tunnelblickPath, YES, 0, 0);
	
	// Check/set all Tunnelblick.app folders to have PERMS_SECURED_FOLDER permissions
	//           everything else to not group- or other-writable and not suid and not sgid

/*	if (  ! makeUnlockedAtPath( tunnelblickPath)  ) {
		okSoFar = FALSE;
	}
*/
	NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: tunnelblickPath];
	NSString * file;
	BOOL isDir;
	while (  (file = dirEnum.nextObject)  ) {
		NSString * fullPath = [tunnelblickPath stringByAppendingPathComponent: file];
		if (   [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
			&& isDir  ) {
			okSoFar = checkSetPermissions(fullPath, PERMS_SECURED_FOLDER, YES) && okSoFar;
		} else {
			NSDictionary * atts = [NSFileManager.defaultManager tbFileAttributesAtPath: fullPath traverseLink: NO];
			unsigned long  perms = [atts filePosixPermissions];
			// Nothing should be writable by group, writable by user, be suid, or be sgid
			unsigned long  permsShouldHave = (perms & ~(S_IWGRP | S_IWOTH | S_ISUID | S_ISGID));
			if (  (perms != permsShouldHave )  ) {
				if (  lchmod(fileSystemRepresentationFromPath(fullPath), permsShouldHave) == 0  ) {
					Log(@"Changed permissions from %lo to %lo on %@",
						(long) perms, (long) permsShouldHave, fullPath);
				} else {
					NSString * fileIsImmutable = (  [atts fileIsImmutable]
												  ? @"; file is immutable"
												  : @"" );

					Log(@"Unable to change permissions (error %ld: '%s'%@) from %lo to %lo on %@",
                        (long)errno, strerror(errno), fileIsImmutable, (long) perms, (long) permsShouldHave, fullPath);
					okSoFar = FALSE;
				}
			}
		}
	}

	okSoFar = checkSetPermissions(infoPlistPath,             PERMS_SECURED_READABLE,   YES) && okSoFar;
	
	okSoFar = checkSetPermissions(openvpnstartPath,          PERMS_SECURED_EXECUTABLE, YES) && okSoFar;
	
    okSoFar = checkSetPermissions(uninstallerAppleSPath,     PERMS_SECURED_READABLE, YES) && okSoFar;
    okSoFar = checkSetPermissions(uninstallerScriptPath,     PERMS_SECURED_EXECUTABLE, YES) && okSoFar;

    okSoFar = checkSetPermissions(atsystemstartPath,         PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
    okSoFar = checkSetPermissions(TunnelblickUpdateHelperPath, PERMS_SECURED_ROOT_EXEC, YES) && okSoFar;

	okSoFar = checkSetPermissions(installerPath,             PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(leasewatchPath,            PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(leasewatch3Path,           PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(pncPath,                   PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(ssoPath,                   PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(tunnelblickdPath,          PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	
	okSoFar = checkSetPermissions(pncPlistPath,              PERMS_SECURED_READABLE,   YES) && okSoFar;
    okSoFar = checkSetPermissions(leasewatchPlistPath,       PERMS_SECURED_READABLE,   YES) && okSoFar;
	okSoFar = checkSetPermissions(leasewatch3PlistPath,      PERMS_SECURED_READABLE,   YES) && okSoFar;
	okSoFar = checkSetPermissions(tunnelblickdPlistPath,     PERMS_SECURED_READABLE,   YES) && okSoFar;
	okSoFar = checkSetPermissions(freePublicDnsServersPath,  PERMS_SECURED_READABLE,   YES) && okSoFar;
	
	okSoFar = checkSetPermissions(clientUpPath,              PERMS_SECURED_ROOT_EXEC,  NO) && okSoFar;
	okSoFar = checkSetPermissions(clientDownPath,            PERMS_SECURED_ROOT_EXEC,  NO) && okSoFar;
	okSoFar = checkSetPermissions(clientNoMonUpPath,         PERMS_SECURED_ROOT_EXEC,  NO) && okSoFar;
	okSoFar = checkSetPermissions(clientNoMonDownPath,       PERMS_SECURED_ROOT_EXEC,  NO) && okSoFar;
	okSoFar = checkSetPermissions(clientNewUpPath,           PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(clientNewDownPath,         PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(clientNewRoutePreDownPath, PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
    okSoFar = checkSetPermissions(clientNewAlt1UpPath,       PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(clientNewAlt1DownPath,     PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(clientNewAlt2UpPath,       PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(clientNewAlt2DownPath,     PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(clientNewAlt3UpPath,       PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(clientNewAlt3DownPath,     PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(clientNewAlt4UpPath,       PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(clientNewAlt4DownPath,     PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
    okSoFar = checkSetPermissions(clientNewAlt5UpPath,       PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
    okSoFar = checkSetPermissions(clientNewAlt5DownPath,     PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(reactivateTunnelblickPath, PERMS_SECURED_EXECUTABLE, YES) && okSoFar;
	okSoFar = checkSetPermissions(reenableNetworkServicesPath, PERMS_SECURED_ROOT_EXEC, YES) && okSoFar;
	
	// Check/set each OpenVPN binary inside Tunnelblick.app and its corresponding openvpn-down-root.so
	secureOpenvpnBinariesFolder(openvpnPath);

	// Secure _CodeSignature if it is present. All of its contents should have 0644 permissions
	NSString * codeSigPath = [contentsPath stringByAppendingPathComponent: @"_CodeSignature"];
	if (   [gFileMgr fileExistsAtPath: codeSigPath isDirectory: &isDir]
		&& isDir  ) {
		dirEnum = [gFileMgr enumeratorAtPath: codeSigPath];
		while (  (file = [dirEnum nextObject])  ) {
			NSString * itemPath = [codeSigPath stringByAppendingPathComponent: file];
			okSoFar = checkSetPermissions(itemPath, PERMS_SECURED_READABLE, YES) && okSoFar;
		}
	}
	
	// Secure kexts
	dirEnum = [gFileMgr enumeratorAtPath: appResourcesPath];
	while (  (file = [dirEnum nextObject])  ) {
		[dirEnum skipDescendents];
		if (  [file hasSuffix: @".kext"]  ) {
			NSString * kextPath = [appResourcesPath stringByAppendingPathComponent: file];
            okSoFar = secureOneKext(kextPath) & okSoFar;
		}
	}
	
	// Secure IconSets
	if (   [gFileMgr fileExistsAtPath: iconSetsPath isDirectory: &isDir]
		&& isDir  ) {
		okSoFar = okSoFar && secureOneFolder(iconSetsPath, NO, 0);
	} else {
		Log(@"Missing IconSets folder, which should be at %@", iconSetsPath);
		errorExit();
	}
	
	// Secure the app's Deploy folder
	if (   [gFileMgr fileExistsAtPath: gDeployPath isDirectory: &isDir]
		&& isDir  ) {
		okSoFar = okSoFar && secureOneFolder(gDeployPath, NO, 0);
	}
	
	okSoFar = checkSetPermissions(tunnelblickHelperPath, PERMS_SECURED_EXECUTABLE, YES) && okSoFar;

	if (  ! okSoFar  ) {
		Log(@"Unable to secure Tunnelblick.app");
		errorExit();
	}

    if (  copyToL_AS_T  ) {
        // Copy the app to L_AS_T. File copies will be clones, so they won't take up much space.
        NSString * appPath = appResourcesPath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;
        copyAppToL_AS_T(appPath);
    }
}

static void secureAllTblks(void) {
	
	NSString * altPath = [L_AS_T_USERS stringByAppendingPathComponent: userUsername()];
	
	// First, copy any .tblks that are in private to alt (unless they are already there)
	NSString * file;
	NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: userPrivatePath()];
	while (  (file = [dirEnum nextObject])  ) {
		if (  [[file pathExtension] isEqualToString: @"tblk"]  ) {
			[dirEnum skipDescendents];
			NSString * privateTblkPath = [userPrivatePath() stringByAppendingPathComponent: file];
			NSString * altTblkPath     = [altPath stringByAppendingPathComponent: file];
			if (  ! [gFileMgr fileExistsAtPath: altTblkPath]  ) {
				if (  ! createDirWithPermissionAndOwnership([altTblkPath stringByDeletingLastPathComponent], PERMS_SECURED_FOLDER, 0, 0)  ) {
					errorExit();
				}
				if (  [gFileMgr tbCopyPath: privateTblkPath toPath: altTblkPath handler: nil]  ) {
					Log(@"Created shadow copy of %@", privateTblkPath);
				} else {
					Log(@"Unable to create shadow copy of %@", privateTblkPath);
					errorExit();
				}
			}
		}
	}
	
	// Now secure shared tblks, private tblks, and shadow copies of private tblks
	
	NSArray * foldersToSecure = [NSArray arrayWithObjects: L_AS_T_SHARED, userPrivatePath(), altPath, nil];
	
	BOOL okSoFar = YES;
	unsigned i;
	for (i=0; i < [foldersToSecure count]; i++) {
		NSString * folderPath = [foldersToSecure objectAtIndex: i];
		BOOL isPrivate = isPathPrivate(folderPath);
		okSoFar = okSoFar && secureOneFolder(folderPath, isPrivate, userUID());
	}
	
	if (  ! okSoFar  ) {
		Log(@"Warning: Unable to secure all .tblk packages");
	}
}

static void installForcedPreferences(NSString * firstPath, NSString * secondPath) {

    // NO LONGER USED BY TUNNELBLICK; KEPT AVAILABLE FOR SCRIPTS BY DEPLOYERS

	if (  secondPath  ) {
		Log(@"Operation is INSTALLER_INSTALL_FORCED_PREFERENCES but secondPath is set");
		errorExit();
	}
	
	if (  [firstPath hasSuffix: @".plist"]  ) {
		// Make sure the .plist is valid
		NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: firstPath];
		if (  ! dict  ) {
			Log(@"Not a valid .plist: %@", firstPath);
			errorExit();
		}
		
		if (  [gFileMgr fileExistsAtPath: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH]  ) {
			errorExitIfAnySymlinkOrDotDotInPath(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);
			makeUnlockedAtPath(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);
            securelyDeleteItem(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);
		} else {
			errorExitIfAnySymlinkOrDotDotInPath([L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH stringByDeletingLastPathComponent]);
		}
		
		if (  [gFileMgr tbCopyPath: firstPath toPath: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH handler: nil]  ) {
			Log(@"copied (D) %@\n    to %@", firstPath, L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);
			if (  checkSetOwnership(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH, NO, 0, 0)  )  {
				if (  ! checkSetPermissions(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH, PERMS_SECURED_READABLE, YES)  )  {
					Log(@"Unable to set permssions of %ld on %@", (long)PERMS_SECURED_READABLE, L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);
					errorExit();
				}
			} else {
				Log(@"Unable to set ownership to root:wheel on %@", L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);
				errorExit();
			}
		} else {
			Log(@"unable to copy %@ to %@", firstPath, L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);
			errorExit();
		}
	} else {
		Log(@"Not a .plist: %@", firstPath);
		errorExit();
	}
}

static NSDictionary * dictionaryFromXML(NSString * xmlString) {

    NSData * data = [xmlString dataUsingEncoding: NSUTF8StringEncoding];
    if (  data == nil  ) {
        Log(@"INSTALLER_INSTALL_FORCED_PREFERENCES_XML: could not decode input as UTF-8");
        errorExit();
    }

    NSError * parseError = nil;
    NSPropertyListFormat format = NSPropertyListXMLFormat_v1_0;

    id propertyList = [NSPropertyListSerialization propertyListWithData: data
                                                                options: NSPropertyListImmutable
                                                                 format: &format
                                                                  error: &parseError];
    if (  propertyList == nil  ) {
        Log(@"INSTALLER_INSTALL_FORCED_PREFERENCES_XML: could not deserialize input as a property list; error was %@", parseError);
        errorExit();
    }

    if (  ! [propertyList isKindOfClass:[NSDictionary class]]  ) {
        Log(@"INSTALLER_INSTALL_FORCED_PREFERENCES_XML: deserialized input is not a dictionary");
        errorExit();
    }

    return (NSDictionary *)propertyList;
}

static void installForcedPreferencesXML(NSString * xmlString) {

    NSDictionary * propertyList = dictionaryFromXML(xmlString);

    NSString * tempPath = L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH ".tmp";

    if (  ! [propertyList writeToFile: tempPath atomically: YES]  ) {
        Log(@"INSTALLER_INSTALL_FORCED_PREFERENCES_XML: could not write to '%@'", tempPath);
        errorExit();
    }

    if (  ! checkSetOwnership(tempPath, NO, 0, 0)  )  {
        [gFileMgr tbRemovePathIfItExists: tempPath];
        Log(@"INSTALLER_INSTALL_FORCED_PREFERENCES_XML: Unable to set ownership to root:wheel on '%@'", tempPath);
        errorExit();
    }

    if (  ! checkSetPermissions(tempPath, PERMS_SECURED_READABLE, YES)  )  {
        [gFileMgr tbRemovePathIfItExists: tempPath];
        Log(@"INSTALLER_INSTALL_FORCED_PREFERENCES_XML: Unable to set permissions of %ld on '%@'",
            (long)PERMS_SECURED_READABLE, tempPath);
        errorExit();
    }

    if (  ! [gFileMgr tbForceRenamePath: tempPath toPath: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH]) {
        errorExit();
    }

    Log(@"Wrote XML to '%@'", L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);

}

static void doFolderRename(NSString * sourcePath, NSString * targetPath) {

    // Renames the source folder to the target folder. Both folders need to be in the same folder.
    //
    // If the source folder is a private folder, the corresponding secure folder is also renamed if it exists.


    if (  ! [gFileMgr fileExistsAtPath: sourcePath]  ) {
        Log(@"rename source does not exist: %@ to %@", sourcePath, targetPath);
        errorExit();
    }
    if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
        Log(@"rename target exists: %@ to %@", sourcePath, targetPath);
        errorExit();
    }
    securelyRename(sourcePath, targetPath);

    if (  [sourcePath hasPrefix: [userPrivatePath() stringByAppendingString: @"/"]]  ) {

        // It's a private path. Rename any existing corresponding shadow path, too
        NSString * secureSourcePath = [[L_AS_T_USERS
                                        stringByAppendingPathComponent: userUsername()]
                                       stringByAppendingPathComponent: lastPartOfPath(sourcePath)];
        NSString * secureTargetPath = [[L_AS_T_USERS
                                        stringByAppendingPathComponent: userUsername()]
                                       stringByAppendingPathComponent: lastPartOfPath(targetPath)];

        if (  [gFileMgr fileExistsAtPath: secureSourcePath]  ) {
            if (  [gFileMgr fileExistsAtPath: secureTargetPath]  ) {
                Log(@"rename target exists: %@ to %@", secureSourcePath, secureTargetPath);
                errorExit();
            }
            securelyRename(secureSourcePath, secureTargetPath);
        }
    }
}

static BOOL containsTunnelblickRootScripts(NSString * tblkPath) {

    NSDirectoryEnumerator * dirE = [gFileMgr enumeratorAtPath: tblkPath];
    NSString * subPath;
    while (  (subPath = [dirE nextObject])  ) {
        if (  ! [subPath hasSuffix: @".user.sh"]  ) {
            if (  [subPath hasSuffix: @".sh"]  ) {
                return YES;
            }
        }
    }

    return NO;
}

static BOOL containsTunnelblickUserScripts(NSString * tblkPath) {

    NSDirectoryEnumerator * dirE = [gFileMgr enumeratorAtPath: tblkPath];
    NSString * subPath;
    while (  (subPath = [dirE nextObject])  ) {
        if (  [subPath hasSuffix: @".user.sh"]  ) {
            return YES;
        }
    }

    return NO;
}

static void copyOrMoveOneFolderOrTblk(NSString * sourcePath, NSString * targetPath, BOOL moveNotCopy) {

	if (   ( ! sourcePath )
		|| ( ! targetPath )  ){
		Log(@"Operation is INSTALLER_COPY or INSTALLER_MOVE but targetPath and/or sourcePath are not set");
		errorExit();
	}
	
    // An empty source path means CREATE A FOLDER at the target path.
    if (  [sourcePath isEqualToString: @""]  ) {
        if (  [targetPath hasSuffix: @".tblk"]  ) {
            Log(@"When source is '', target cannot be a .tblk: %@", targetPath);
            errorExit();
        }

        if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
            Log(@"When source is '', target cannot exist: %@", targetPath);
            errorExit();
        }

        createSecuredConfigurationsSubfolder(targetPath);
        return;
    }

    //
    // Copy or move a folder or .tblk
    //
    BOOL sourceIsTblk = [[sourcePath pathExtension] isEqualToString: @"tblk"];
    BOOL targetIsTblk = [[targetPath pathExtension] isEqualToString: @"tblk"];

	// Make sure we are dealing with two .tblks or two non-tblks
	if (   (   sourceIsTblk
            && ( ! targetIsTblk ))
        || (   targetIsTblk
            && ( ! sourceIsTblk ) )  ) {
		Log(@"Only two .tblks or two folders may be copied or moved: %@ to %@", sourcePath, targetPath);
		errorExit();
	}

    if (  ! sourceIsTblk  ) { // And, by the above, the target is not a .tblk either
        if (   (   [sourcePath isEqualToString: @"/Applications/Tunnelblick.app"]
                && [targetPath isEqualToString: @"/Library/Application Support/Tunnelblick/Tunnelblick-old.app"] )
            || [targetPath isEqualToString: @"/Applications/Tunnelblick.app"]  ) {
            if (  ! [gFileMgr tbRemovePathIfItExists: targetPath] ) {
                Log(@"Error deleting '%@' before copying to it", targetPath);
                errorExit();
            }
            NSError * err = nil;
            if (  ! [gFileMgr copyItemAtPath: sourcePath toPath: targetPath error: &err] ) {
                Log(@"Error copying '%@' to '%@': %@", sourcePath, targetPath, err);
                errorExit();
            }

            return;
        }
        if (  ! moveNotCopy  ) {
            Log(@"Can only move, not **copy**, a folder: %@ to %@", sourcePath, targetPath);
            errorExit();
        }
        BOOL isDir;
        if (   (   [gFileMgr fileExistsAtPath: sourcePath isDirectory: &isDir]
                && isDir)
            && (   ( ! [gFileMgr fileExistsAtPath: targetPath isDirectory: &isDir] )
                && isDir)
            ) {
            doFolderRename(sourcePath, targetPath);
            return;
        } else {
            Log(@"Source does not exist or target does exist for copy or move: %@ to %@", sourcePath, targetPath);
            errorExit();
        }
    }

    //
    // Copy or move a .tblk
    //

    // Should not move or copy to a user-writable path

    if (  pathWritableByUser(targetPath)  ) {
        Log(@"Should not be moving to user-writable path '%@'", targetPath);
        errorExit();
    }

	// Create the enclosing folder(s) if necessary. Owned by root unless if in userPrivatePath(), in which case it is owned by the user
	NSString * enclosingFolder = [targetPath stringByDeletingLastPathComponent];
    createSecuredConfigurationsSubfolder(enclosingFolder);

	// Make sure we can delete the original if we are moving instead of copying
	if (  moveNotCopy  ) {
		if (  ! makeUnlockedAtPath(targetPath)  ) {
			errorExit();
		}
	}

    NSString * sourceDisplayName = [lastPartOfPath(sourcePath) stringByDeletingPathExtension];
    NSString * targetDisplayName = [lastPartOfPath(targetPath) stringByDeletingPathExtension];

    if (  moveNotCopy  ) {
        securelyMoveTblkIncludingPrivate(sourcePath, targetPath);
        renameForcedPreferencesForDisplayName(sourceDisplayName, targetDisplayName);
    } else {
        securelyCopy(sourcePath, targetPath);
        copyForcedPreferencesForDisplayName(sourceDisplayName, targetDisplayName);
    }

    structureTblkProperly(targetPath);

    secureOneFolderMaintainOwnership(targetPath, NO, 0, YES);

    //
    // If copying to Shadow, make a copy in the user's Configurations folder and secure it.
    // (If we moved, the private copy was already moved by securelyMoveTblkIncludingPrivate)
    //

    if (   ( ! moveNotCopy)
        && [targetPath hasPrefix: [L_AS_T_USERS stringByAppendingString: @"/"]]  ) {
        NSString * lastPart = lastPartOfPath(targetPath);
        NSString * privatePath = [userPrivatePath() stringByAppendingPathComponent:lastPart];
        securelyCopy(targetPath, privatePath);
        secureOneFolderMaintainOwnership(privatePath, YES, userUID(), NO);
    }
}

static void deleteOneFolderOrTblk(NSString * firstPath, NSString * secondPath) {

    // Deletes a folder (if firstPath ends in a "/") or a .tblk
    //
    // The path must be in L_AS_T_SHARED or L_AS_T_USERS/<username>

    //
    // Check argument(s)
    //

    if (   ( ! firstPath )
        || secondPath) {
        Log(@"Wrong number of arguments; one argument is required");
        errorExit();
    }

    NSString * path = firstPath;

    errorExitIfAnySymlinkOrDotDotInPath(path);

    NSString * shadowPath = [[L_AS_T_USERS
                              stringByAppendingPathComponent: userUsername()]
                             stringByAppendingPathComponent: @"/"];
    BOOL isShadow = (   [path hasPrefix: [shadowPath stringByAppendingString: @"/"]]
                     && (path.length > shadowPath.length)  );
    NSString * sharedPath = [L_AS_T_SHARED
                             stringByAppendingPathComponent: @"/"];
    BOOL isShared = (   [path hasPrefix: [sharedPath stringByAppendingString: @"/"]]
                     && (path.length > sharedPath.length)  );

    if (   ( ! isShadow )
        && ( ! isShared )  ) {
        Log(@"Not in a deletable location: '%@'", firstPath);
        errorExit();
    }

    //
    // If path has a trailing "/", remove it
    // Otherwise, make sure it is a .tblk
    //

    if (   [path hasSuffix: @"/"]  ) {
        path = [path substringToIndex: path.length - 1];
    } else {
        if (  ! [path hasSuffix: @".tblk"]  ) {
            Log(@"Not a folder or .tblk: '%@'", firstPath);
            errorExit();
        }
    }

    //
    // Delete the item
    //

    securelyDeleteItemIfItExists(path);

    //
    // If the item is a .tblk, delete any private copy and any forced preferences that refer to it
    //
    if (  [path hasSuffix: @".tblk"]  ) {

        if (  [path hasPrefix: [L_AS_T_USERS stringByAppendingString: @"/"]]  ) {
            NSString * lastPart = lastPartOfPath(path);
            NSString * privatePath = [userPrivatePath() stringByAppendingPathComponent: lastPart];
            securelyDeleteItemIfItExists(privatePath);
        }

        NSString * displayName = [[path
                                   substringToIndex: path.length - @".tblk".length]
                                  substringFromIndex: (  isShadow
                                                       ? shadowPath.length + 1
                                                       : sharedPath.length + 1)];

        deleteForcedPreferencesForDisplayName(displayName);
    }
}

static BOOL installerUpdateTunnelblick(NSString * updateSignature, NSString * versionAndBuildString, NSString * username, uid_t uid, gid_t gid, pid_t tunnelblickPid) {

    NSString * zipPath = [[[@"/Users/"
                            stringByAppendingPathComponent: username]
                           stringByAppendingPathComponent: L_AS_T]
                          stringByAppendingPathComponent: @"tunnelblick-update.zip"];

    return updateTunnelblick(zipPath, updateSignature, versionAndBuildString, uid, gid, tunnelblickPid);
}

static BOOL setOrDeleteForcedPreference(NSString * name, NSString * value) {

    // If "value" is "0" the "name" forced preference is removed from the file at
    //    L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH and TRUE is returned.
    //
    // If "value" is "0" and the file doesn't exist, that is logged and TRUE is returned.
    //
    // If "value" is "1" the "name" forced preference is set TRUE in the file and TRUE is returned.
    //
    // Returns FALSE if there is a syntax error.

    NSError * err = nil;

    //
    // Check arguments
    //
    if (   (name.length == 0)
        || (value.length != 1)
        || ( ! [@"01" containsString: value] )  ) {

        return FALSE;
    }

    //
    // Get a URL to access the forced preferences file
    //
    NSURL * fileURL = [NSURL fileURLWithPath: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH
                                 isDirectory: NO];
    if (  ! fileURL  ) {
        Log(@"Failed to create URL with path '%@'",
            L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);
        errorExit();
    }

    //
    // Get a dictionary with the current forced preferences (if any)
    //
    NSMutableDictionary * dict = [[[NSDictionary dictionaryWithContentsOfURL: fileURL
                                                                       error: &err]
                                   mutableCopy]
                                  autorelease];

    if (   (! dict)
        && err
        && ([err.domain isEqualToString: NSCocoaErrorDomain])
        && (err.code != NSFileNoSuchFileError)
        && (err.code != NSFileReadNoSuchFileError)  ) {
        Log(@"Failed to read '%@'; error was %@", fileURL.path, err);
        errorExit();
    }
    BOOL fileExisted = (dict != nil);

    if (  ! fileExisted  ) {
        if (  [value isEqualToString: @"0"]  ) {
            // If the file existed it should be deleted, but it doesn't, so just log that
            // and return success.
            Log(@"'%@' doesn't exist, so not setting '%@' to 0",
                fileURL.path, name);
            return TRUE; // No forced preference to delete
        }
        dict = [NSMutableDictionary dictionaryWithCapacity: 1];
    }

    //
    // Modify the dictionary appropriately
    //
    if (  [value isEqualToString: @"0"]  ) {
        [dict removeObjectForKey: name];
        Log(@"Removed forced preference '%@'", name);
    } else {
        [dict setObject: @YES forKey: name];
        Log(@"Set forced preference '%@' to TRUE", name);
    }

    //
    // If the file exists but shouldn't, delete it and return success.
    //
    if (  fileExisted  ) {
        if (  dict.count == 0  ) {
            if (  ! [gFileMgr removeItemAtURL: fileURL error: &err]  ) {
                Log(@"Failed to delete '%@'; error was %@",
                    fileURL.path, err);
                errorExit();
            }
            Log(@"No forced preferences, so deleted '%@'",
                fileURL.path);
            return TRUE;
        }
    }

    //
    // Write the new dictionary to the file and return success.
    //
    if (  dict.count != 0  ) {
        if  (  ! [dict writeToURL: fileURL atomically: YES]  ) {
            Log(@"Failed to write dictionary to '%@'",
                fileURL.path);
            errorExit();
        }
        if (  fileExisted  ) {
            Log(@"Replaced '%@'", fileURL.path);
        } else {
            Log(@"Created '%@'", fileURL.path);
        }
    }

    return TRUE;
}

static BOOL renameTempFileToMipFile(NSString * sourcePath, NSString * targetPath) {

    // Renames the file at sourcePath to targetPath if source is directly in L_AS_T_TEMP and
    // target is directly in L_AS_T_MIPS.
    //
    // Returns FALSE if there is an argument error.

    //
    // Check arguments
    //

    errorExitIfAnySymlinkOrDotDotInPath(sourcePath);
    errorExitIfAnySymlinkOrDotDotInPath(targetPath);

    if (   ( ! [sourcePath hasPrefix: [L_AS_T_TEMP stringByAppendingString: @"/"]])
        || ( ! [targetPath hasPrefix: [L_AS_T_MIPS stringByAppendingString: @"/"]])  ) {
        return FALSE;
    }

    // Make sure only a filename, no subfolders
    NSString * sourceFilename = [sourcePath substringFromIndex: L_AS_T_TEMP.length + 1];
    NSString * targetFilename = [targetPath substringFromIndex: L_AS_T_MIPS.length + 1];
    if (   [sourceFilename containsString: @"/"]
        || [targetFilename containsString: @"/"]  ) {
        return FALSE;
    }

    //
    // Do the rename
    //

    securelyRename(sourcePath, targetPath);

    return TRUE;
}

//**************************************************************************************************************************
// EXPORT SETUP

static void createExportFolder(NSString * path) {
	
	if (  ! createDirWithPermissionAndOwnership(path, privateFolderPermissions(path), 0, 0)  ) {
		Log(@"Error creating folder %@", path);
		errorExit();
	}
}

static void exportOneUser(NSString * username, NSString * targetUsersPath) {
	
	// Get path to this user's folder in Users, but don't create it unless we need to
	NSString * targetThisUserPath = [targetUsersPath stringByAppendingPathComponent: username];
	BOOL createdTargetThisUserPath = FALSE;
	
	NSString * homeFolder = [@"/Users" stringByAppendingPathComponent: username];
	
	// Copy preferences only if they exist
	NSString * sourcePreferencesPath = [[[homeFolder
										  stringByAppendingPathComponent: @"Library"]
										 stringByAppendingPathComponent: @"Preferences"]
										stringByAppendingPathComponent: @"net.tunnelblick.tunnelblick.plist"];
	NSString * targetPreferencesPath = [targetThisUserPath stringByAppendingPathComponent: @"net.tunnelblick.tunnelblick.plist"];
	if (  [gFileMgr fileExistsAtPath: sourcePreferencesPath]  ) {
		createExportFolder(targetThisUserPath);
		createdTargetThisUserPath = TRUE;
		securelyCopy(sourcePreferencesPath, targetPreferencesPath);
	}
	
	NSString * userL_AS_T = [[[homeFolder
							   stringByAppendingPathComponent: @"Library"]
							  stringByAppendingPathComponent: @"Application Support"]
							 stringByAppendingPathComponent: @"Tunnelblick"];
	
	// Copy Configurations only if it exists
	NSString * sourceConfigurationsPath = [userL_AS_T     stringByAppendingPathComponent: @"Configurations"];
	NSString * targetConfigurationsPath = [targetThisUserPath stringByAppendingPathComponent: @"Configurations"];
	if (  [gFileMgr fileExistsAtPath: sourceConfigurationsPath]  ) {
		if (  ! createdTargetThisUserPath  ) {
			createExportFolder(targetThisUserPath);
			createdTargetThisUserPath = TRUE;
		}
        securelyCopy(sourceConfigurationsPath, targetConfigurationsPath);
	}
	
	// Copy easy-rsa only if it exists
	NSString * sourceEasyrsaPath = [userL_AS_T     stringByAppendingPathComponent: @"easy-rsa"];
	NSString * targetEasyrsaPath = [targetThisUserPath stringByAppendingPathComponent: @"easy-rsa"];
	if (  [gFileMgr fileExistsAtPath: sourceEasyrsaPath]  ) {
		if (  ! createdTargetThisUserPath  ) {
			createExportFolder(targetThisUserPath);
		}
        securelyCopy(sourceEasyrsaPath, targetEasyrsaPath);
	}
}

static void pruneFolderAtPath(NSString * path) {
	
	// Removes subfolders of path if they do not have any contents
	
	NSString * outerName;
	NSDirectoryEnumerator * outerEnum = [gFileMgr enumeratorAtPath: path];
	while (  (outerName = [outerEnum nextObject])  ) {
		[outerEnum skipDescendants];
		NSString * pruneCandidatePath = [path stringByAppendingPathComponent: outerName];
		
		NSDirectoryEnumerator * innerEnum = [gFileMgr enumeratorAtPath: pruneCandidatePath];
		if (  ! [innerEnum nextObject]  ) {
            securelyDeleteItemIfItExists(pruneCandidatePath);
			Log(@"Removed folder because it was empty: %@", pruneCandidatePath);
		}
	}
}

static void exportToPath(NSString * exportPath) {

	// Create a temporary folder, copy stuff into it, make a tar.gz of it at the indicated path, and delete it
	
	NSString * tarPath = [[exportPath stringByAppendingPathExtension: @"tar"] stringByAppendingPathExtension: @"gz"];
	
	// Remove the output file if it already exists
	// (We do this so user doesn't do something with it before we're finished).
    securelyDeleteItemIfItExists(tarPath);

	// Create a temporary folder
	NSString * tempFolderPath = [newTemporaryDirectoryPath() autorelease];
    if (  ! tempFolderPath  ) {
        errorExit();
    }

	NSString * archiveName = [[exportPath lastPathComponent] stringByAppendingPathExtension: @"tblkSetup"];
	
	// Create a subfolder that we will create a .tar.gz of
	NSString * tempOutputFolderPath = [tempFolderPath stringByAppendingPathComponent: archiveName];
	createExportFolder(tempOutputFolderPath);
	
	// Create a folder of user data
	NSString * targetSetupUsersPath = [tempOutputFolderPath stringByAppendingPathComponent: @"Users"];
	createExportFolder(targetSetupUsersPath);
	
	// Copy per-user data
	NSString * username;
	NSDirectoryEnumerator * e = [gFileMgr enumeratorAtPath: @"/Users"];
	while (  (username = [e nextObject])  ) {
		[e skipDescendants];
		NSString * fullPath = [@"/Users" stringByAppendingPathComponent: username];
		BOOL isDir;
		if (   [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
			&& isDir  ) {
			NSString * userL_AS_T = [[[fullPath stringByAppendingPathComponent: @"Library"]
									  stringByAppendingPathComponent: @"Application Support"]
									 stringByAppendingPathComponent: @"Tunnelblick"];
			if (  [gFileMgr fileExistsAtPath: userL_AS_T]  ) {
				exportOneUser(username, targetSetupUsersPath);
			}
		}
	}
	
	// Create a folder of global data
	NSString * targetSetupGlobalPath = [tempOutputFolderPath stringByAppendingPathComponent: @"Global"];
	createExportFolder(targetSetupGlobalPath);
	
	// Copy forced-preferences.plist to Global
	NSString * sourceForcedPreferencesPath = [L_AS_T stringByAppendingPathComponent: @"forced-preferences.plist"];
	if (  [gFileMgr fileExistsAtPath: sourceForcedPreferencesPath]  ) {
		NSString * targetForcedPreferencesPath = [targetSetupGlobalPath stringByAppendingPathComponent: @"forced-preferences.plist"];
        securelyCopy(sourceForcedPreferencesPath, targetForcedPreferencesPath);
	}
	
	// Copy Shared to Global
	NSString * sourceSharedPath            = L_AS_T_SHARED;
	NSString * targetSharedPath            = [targetSetupGlobalPath stringByAppendingPathComponent: @"Shared"];
    securelyCopy(sourceSharedPath, targetSharedPath);
	pruneFolderAtPath(targetSharedPath);
	
	// Copy Users to Global
	NSString * sourceUsersPath             = L_AS_T_USERS;
	NSString * targetUsersPath             = [targetSetupGlobalPath stringByAppendingPathComponent: @"Users"];
    securelyCopy(sourceUsersPath, targetUsersPath);
	pruneFolderAtPath(targetUsersPath);
	
	// Create TBInfo.plist
	NSDictionary * tbInfoPlist = [[NSBundle mainBundle] infoDictionary];
	NSString * bundleVersion = [tbInfoPlist objectForKey: @"CFBundleVersion"];
	NSString * bundleShortVersionString = [tbInfoPlist objectForKey: @"CFBundleShortVersionString"];
	NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
						   @"1",					 @"TBExportVersion",
						   bundleVersion,			 @"TBBundleVersion",
						   bundleShortVersionString, @"TBBundleShortVersionString",
						   [NSDate date],			 @"TBDateCreated",
						   nil];
	NSString * targetTBInfoPlistPath = [tempOutputFolderPath stringByAppendingPathComponent: @"TBInfo.plist"];
	if (  ! [dict writeToFile: targetTBInfoPlistPath atomically: YES]  ){
		Log(@"writeToFile failed for %@", targetTBInfoPlistPath);
		errorExit();
	}
	
	// Create the final target .tar.gz
	NSArray * tarArguments = [NSArray arrayWithObjects:
							  @"-czf",      tarPath,
							  @"-C",        tempFolderPath,
							  @"--exclude", @".*",
							  archiveName,
							  nil];
	
	if (  EXIT_SUCCESS != runTool(TOOL_PATH_FOR_TAR, tarArguments, nil, nil)  ) {
		errorExit();
	}
	
	// Set the ownership and permissions of the .tar.gz so only the real user can access it
	if ( ! checkSetOwnership(tarPath, NO, userUID(), userGID())  ) {
		errorExit();
	}
	if ( ! checkSetPermissions(tarPath, 0700, YES)  ) {
		errorExit();
	}
	
	// Remove the temporary folder
    securelyDeleteItem(tempFolderPath);
}

//**************************************************************************************************************************
//	IMPORT SETUP

static NSString * formattedUserGroup(uid_t uid, gid_t gid) {
	
	// Returns a string with uid:gid padded on the left with spaces to a width of 11
	
	const char * ugC = [[NSString stringWithFormat: @"%d:%d", uid, gid] UTF8String];
	return [NSString stringWithFormat: @"%11s", ugC];
}

static void safeCopyPathToPathAndSetUidAndGid(NSString * sourcePath, NSString * targetPath, uid_t newUid, gid_t newGid) {
	
	NSString * verb = (  [gFileMgr fileExistsAtPath: targetPath]
					   ? @"Overwrote"
					   : @"Copied (E) to");
    securelyCopy(sourcePath, targetPath);
    if ( ! checkSetOwnership(targetPath, YES, newUid, newGid)  ) {
        errorExit();
    }
    
	Log(@"%@ and set ownership to %@: %@", verb, formattedUserGroup(newUid, newGid), targetPath);
}

static void mergeConfigurations(NSString * sourcePath, NSString * targetPath, uid_t uid, gid_t gid, BOOL mergeIconSets) {
	
	// Copies .tblk configurations in the folder at sourcePath into the folder at targetPath, enclosing them in subfolders as necessary,
    // setting their ownership to uid:gid and their permissions appropriately.
	//
	// If "mergeIconSets" is TRUE, handles .TBMenuIcons similarly.
	//
	// This routine is used to merge
	//		.tblkSettings/Global/Users/<user>  to L_AS_T/Users/<user>     (with "mergeIconSets" FALSE)
	//		.tblkSettings/Users/Configurations to ~/L_AS_T/Configurations (with "mergeIconSets" FALSE)
    //      .tblkSettings/Global/Shared        to L_AS_T/Shared           (with "mergeIconSets" TRUE)

    NSString * name;
    NSDirectoryEnumerator * e = [gFileMgr enumeratorAtPath: sourcePath];
    while (  (name = [e nextObject])  ) {

        if (  ! [name hasPrefix: @"."]  ) {
            NSString * sourceFullPath = [sourcePath stringByAppendingPathComponent: name];
            NSString * targetFullPath = [targetPath stringByAppendingPathComponent: name];

            if (   [targetFullPath hasSuffix: @".tblk"]
                || (   mergeIconSets
                    && [targetFullPath hasSuffix: @".TBMenuIcons"] )  ) {

                // Create enclosing folder(s) if necessary
                NSString * folderEnclosingTargetPath = [targetFullPath stringByDeletingLastPathComponent];
                if (  ! [gFileMgr fileExistsAtPath: folderEnclosingTargetPath]  ) {
                    securelyCreateFolderAndParents(folderEnclosingTargetPath);
                }

                // Copy the .tblk or .TBMenuIcons
                safeCopyPathToPathAndSetUidAndGid(sourceFullPath, targetFullPath, uid, gid);
                // Secure the .tblk or .TBMenuIcons
                BOOL isPrivate = isPathPrivate(targetFullPath);
                if (  ! secureOneFolder(targetFullPath, isPrivate, uid)  ) {
                    Log(@"Failed: secureOneFolder('%@', %s, %d)",
                               targetFullPath, CSTRING_FROM_BOOL(isPrivate), uid);
                    errorExit();
                }

                // DO NOT do further processing within the .tblk or .TBMenuIcons folder
                [e skipDescendants];
            }
        }
    }
}

static void mergeGlobalUsersFolder(NSString * tblkSetupPath, NSDictionary * nameMap) {
	
	// Merges the .tblkSetup/Global/Users into /Library/Application Support/Tunnelblick/Users.
	//
	// nameMap contains mappings of name-in-.tblksetup => name-on-this-computer
	//
	// L_AS_T/Users is a folder with a subfolder for each user on the computer that has secured a Tunnelblick "Private" configuration.
	// In each user's subfolder, there is a secured copy (owned by root with appropriate permissions) of each private configuration.
	//
	// To merge .tblkSetup/Global/Users, we add or replace the secured copies of configurations, mapping usernames as instructed.
	
	NSString * inFolder  = [[tblkSetupPath
							 stringByAppendingPathComponent: @"Global"]
                            stringByAppendingPathComponent: @"Users"];
	NSString * outFolder = L_AS_T_USERS;
	
    // Create enclosing folder(s) if necessary
	if (  ! [gFileMgr fileExistsAtPath: outFolder]  ) {
					securelyCreateFolderAndParents(outFolder);
	}
	
	// Do mapping only if necessary
	BOOL useUsernameFromSetupData = ( 0 != [nameMap count] );
	
	NSString * name;
	NSDirectoryEnumerator * e = [gFileMgr enumeratorAtPath: inFolder];
	while (  (name = [e nextObject])  ) {
		[e skipDescendants];
		if (  ! [name hasPrefix: @"."]  ) {
			NSString * newName = (  useUsernameFromSetupData
								  ? [nameMap objectForKey: name]
								  : name);
			if (  ! newName) {
				Log(@"Expected username %@ in .tblkSetup to be mapped to a user on this computer but it isn't", name);
				errorExit();
			}
			
			NSString * sourcePath = [inFolder  stringByAppendingPathComponent: name];
			NSString * targetPath = [outFolder stringByAppendingPathComponent: newName];
			mergeConfigurations(sourcePath, targetPath, 0, 0, NO);
		}
	}
}

static void mergeSetupDataForOneUser(NSString * sourcePath, NSString * newUsername) {

    uid_t newUid;
    gid_t newGid;
    getUidAndGidFromUsername(newUsername, &newUid, &newGid);

	NSString * userHomeFolder = [@"/Users" stringByAppendingPathComponent: newUsername];
	
	NSString * userL_AS_TPath = [[[userHomeFolder
								   stringByAppendingPathComponent: @"Library"]
								  stringByAppendingPathComponent: @"Application Support"]
								 stringByAppendingPathComponent: @"Tunnelblick"];
	
	// Create ~/L_AS_T/to-be-imported.plist, which contains all of the preferences to be imported.
	// The user's preferences will be merged the next time the user launches Tunnelblick.
	NSString * sourcePreferencesPath = [sourcePath stringByAppendingPathComponent: @"net.tunnelblick.tunnelblick.plist"];
	NSString * targetPreferencesPath = [[[[userHomeFolder
										   stringByAppendingPathComponent: @"Library"]
										  stringByAppendingPathComponent: @"Application Support"]
										 stringByAppendingPathComponent: @"Tunnelblick"]
										stringByAppendingPathComponent: @"to-be-imported.plist"];
	safeCopyPathToPathAndSetUidAndGid(sourcePreferencesPath, targetPreferencesPath, newUid, newGid);
	
	// Copy easy-rsa
	safeCopyPathToPathAndSetUidAndGid([sourcePath     stringByAppendingPathComponent: @"easy-rsa"],
									  [userL_AS_TPath stringByAppendingPathComponent: @"easy-rsa"],
									  newUid, newGid);
	
	// Copy the user's "Private" configurations
	NSString * sourceConfigurationsFolderPath = [sourcePath     stringByAppendingPathComponent: @"Configurations"];
	NSString * targetConfigurationsFolderPath = [userL_AS_TPath stringByAppendingPathComponent: @"Configurations"];
	mergeConfigurations(sourceConfigurationsFolderPath, targetConfigurationsFolderPath, newUid, newGid, NO);
}

static void errorExitIfTblkSetupIsNotValid(NSString * tblkSetupPath) {
	
	NSString * tbinfoPlistPath  = [tblkSetupPath stringByAppendingPathComponent: @"TBInfo.plist"             ];
	NSString * globalPath       = [tblkSetupPath stringByAppendingPathComponent: @"Global"                   ];
	NSString * usersPath        = [tblkSetupPath stringByAppendingPathComponent: @"Users"                    ];
	NSString * globalSharedPath = [globalPath    stringByAppendingPathComponent: @"Shared"                   ];
	NSString * globalUsersPath  = [globalPath    stringByAppendingPathComponent: @"Users"                    ];
	NSString * globalForcedPath = [globalPath    stringByAppendingPathComponent: @"forced-preferences.plist" ];
	
	errorExitIfSymlinksOrDoesNotExistOrIsNotReadableAtPath( tblkSetupPath    );
	errorExitIfSymlinksOrDoesNotExistOrIsNotReadableAtPath( tbinfoPlistPath  );
	errorExitIfSymlinksOrDoesNotExistOrIsNotReadableAtPath( globalPath       );
	errorExitIfSymlinksOrDoesNotExistOrIsNotReadableAtPath( usersPath        );
	errorExitIfSymlinksOrDoesNotExistOrIsNotReadableAtPath( globalSharedPath );
	errorExitIfSymlinksOrDoesNotExistOrIsNotReadableAtPath( globalUsersPath  );
	
	if (  [gFileMgr fileExistsAtPath: globalForcedPath]  ) {
		errorExitIfSymlinksOrDoesNotExistOrIsNotReadableAtPath( globalForcedPath );
	}
	
	// Check that the setup data's TBInfo.plist is valid
	NSDictionary * tbInfoPlist = [NSDictionary dictionaryWithContentsOfFile: tbinfoPlistPath];
	if (   ( ! tbInfoPlist)
		|| ( ! [[tbInfoPlist objectForKey: @"TBExportVersion"] isEqualToString: @"1"] )
		|| ( ! [tbInfoPlist objectForKey:  @"TBBundleVersion"] )
		|| ( ! [tbInfoPlist objectForKey:  @"TBBundleShortVersionString"] )
		|| ( ! [tbInfoPlist objectForKey:  @"TBDateCreated"] )  ) {
		Log(@"TBInfo.plist is damaged at %@", tblkSetupPath);
		errorExit();
	}
}

static NSDictionary * nameMapFromString(NSString * usernameMap, NSString * tblkSetupPath) {
	
	// Returns a dictionary mapping usernames in the .tblkSetup to usernames on this computer.
	//
	// usernameMap: a string with separated-by-slashes pairs of username:username
	// The first username is the .tblkSetup, the second is the username on this computer
	
	NSMutableDictionary * dict = [[[NSMutableDictionary alloc] initWithCapacity: 20] autorelease];
	NSArray * namePairs = [usernameMap componentsSeparatedByString: @"\n"];
	NSString * namePair;
	NSEnumerator * e = [namePairs objectEnumerator];
	while (  (namePair = [e nextObject])  ) {
		if (  [namePair length] == 0  ) {
			continue;
		}
		NSArray * names = [namePair componentsSeparatedByString: @":"];
		if (  [names count] != 2  ) {
			Log(@"Format error in name-pair %@", namePair);
			errorExit();
		}
		NSString * sourceName = [names firstObject];
		NSString * targetName = [names lastObject];
		NSString * sourcePath = [[tblkSetupPath
								  stringByAppendingPathComponent: @"Users"]
								 stringByAppendingPathComponent: sourceName];
		NSString * targetPath = [@"/Users" stringByAppendingPathComponent: targetName];
		if (  ! [gFileMgr fileExistsAtPath: sourcePath]  ) {
			Log(@"No data for username %@ exists in this .tblkSetup", targetName);
			errorExit();
		}
		if (  ! [gFileMgr fileExistsAtPath: targetPath]  ) {
			Log(@"No username %@ on this computer", targetName);
			errorExit();
		}
		
		[dict setObject: targetName forKey: sourceName];
	}
	
	return [NSDictionary dictionaryWithDictionary: dict];
}

static void createImportInfoFile(NSString * tblkSetupPath) {
	
	// Put info about this import into a file in L_AS_T (if the file doesn't exist)
	NSString * importInfoFilename = [NSString stringWithFormat: @"Data imported from %@",
									 [[tblkSetupPath lastPathComponent] stringByDeletingPathExtension]];
	NSString * importInfoFilePath = [L_AS_T stringByAppendingPathComponent: importInfoFilename];
	if (  ! [gFileMgr fileExistsAtPath: importInfoFilePath]  ) {
		if (  [gFileMgr createFileAtPath: importInfoFilePath contents: nil attributes: nil]  ) {
            if (  ! checkSetOwnership(importInfoFilePath, NO, 0, 0)  ) {
                errorExit();
            }
			Log(@"Created and set ownership to   %@: %@", formattedUserGroup(0, 0), importInfoFilePath);
		} else {
			Log(@"Could not create %@", importInfoFilePath);
			errorExit();
		}
	} else {
		Log(@"File already exists:               %@", importInfoFilePath);
	}
}

static void mergeForcedPreferences(NSString * sourcePath) {
	
	// Merge forced preferences from the .tblkSetup into this computer's forced preferences, overwriting
	// existing values with new values from the .tblkSetup.
	
	NSString * targetPath = L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH;
	
	if (  [gFileMgr fileExistsAtPath: sourcePath]  ) {
		NSMutableDictionary * existingPreferences = (  [gFileMgr fileExistsAtPath: targetPath]
									   ? [[[NSDictionary dictionaryWithContentsOfFile: targetPath] mutableCopy] autorelease]
									   : [NSMutableDictionary dictionaryWithCapacity: 100]  );
		if (  ! existingPreferences  ) {
			Log(@"Error: could not read %@ (or create NSDictionary)", targetPath);
			errorExit();
		}
		
		NSDictionary * preferencesToMerge = [NSDictionary dictionaryWithContentsOfFile: sourcePath];
		if (  ! preferencesToMerge  ) {
			Log(@"Error: could not read %@  ", sourcePath);
			errorExit();
		}

		BOOL modifiedExistingPreferences = FALSE;
		NSString * key;
		NSEnumerator * e = [preferencesToMerge keyEnumerator];
		while (  (key = [e nextObject])  ) {
			id newValue = [preferencesToMerge objectForKey: key];
			id oldValue = ( [existingPreferences objectForKey: key]);
			if (  oldValue  ) {
				if (  [newValue isNotEqualTo: oldValue]) {
					[existingPreferences setObject: newValue forKey: key];
					modifiedExistingPreferences = TRUE;
					Log(@"Changed forced preference %@ = %@ (was %@)", key, newValue, oldValue);
				}
			} else {
				[existingPreferences setObject: newValue forKey: key];
				modifiedExistingPreferences = TRUE;
				Log(@"Added   forced preference %@ = %@", key, newValue);
			}
		}
		
		if (  modifiedExistingPreferences  ) {
			if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
                errorExitIfAnySymlinkOrDotDotInPath(targetPath);
				makeUnlockedAtPath(targetPath);
			} else {
                errorExitIfAnySymlinkOrDotDotInPath([targetPath stringByDeletingLastPathComponent]);
			}
			if (  ! [existingPreferences writeToFile: targetPath atomically: YES]  ) {
				Log(@"Error: could not write %@", targetPath);
				errorExit();
			}
			if (  ! checkSetOwnership(targetPath, NO, 0, 0)  ) {
				Log(@"Unable to set ownership to root:wheel on %@", targetPath);
				errorExit();
			}
			if (  ! checkSetPermissions(targetPath, PERMS_SECURED_READABLE, YES)  ) {
				Log(@"Unable to set permissions of %ld on %@", (long)PERMS_SECURED_READABLE, targetPath);
				errorExit();
			}
		} else {
			Log(@"Do not need to create or modify             %@  ", targetPath);
		}
	}
}

static void importSetup(NSString * tblkSetupPath, NSString * usernameMap) {
	
	// Verify that input data is valid
	errorExitIfTblkSetupIsNotValid(tblkSetupPath);
	
	NSDictionary * nameMap = nameMapFromString(usernameMap, tblkSetupPath);
	
	NSString * globalPath    = [tblkSetupPath stringByAppendingPathComponent: @"Global"];
	NSString * usersPath     = [tblkSetupPath stringByAppendingPathComponent: @"Users"];
	
	NSString * globalSharedPath = [globalPath stringByAppendingPathComponent: @"Shared"];
	NSString * globalForcedPath = [globalPath stringByAppendingPathComponent: @"forced-preferences.plist"];
	
	createImportInfoFile(tblkSetupPath);
	
	// Merge the forced preferences, overwriting old ones individually
	mergeForcedPreferences(globalForcedPath);
	
	// Merge Shared configurations, overwriting old ones individually
	mergeConfigurations(globalSharedPath, [L_AS_T stringByAppendingPathComponent: @"Shared"], 0, 0, YES);
	
	// Merge into L_AS_T/Users, user-by-user, overwriting old configurations individually
	mergeGlobalUsersFolder(tblkSetupPath, nameMap);
	
	// Copy the per-user info user-by-user, overwriting old configurations individually
	NSString * name;
	NSDirectoryEnumerator * e = [gFileMgr enumeratorAtPath: usersPath];
	while (  (name = [e nextObject])  ) {
		[e skipDescendants];
		if (  ! [name hasPrefix: @"."]  ) {
			NSString * newName = [nameMap objectForKey: name];
			if (  newName  ) {
				mergeSetupDataForOneUser([usersPath stringByAppendingPathComponent: name], newName);
			}
		}
	}
}

//**************************************************************************************************************************
// MAIN PROGRAM

int main(int argc, char *argv[]) {
	pool = [NSAutoreleasePool new];
	
    gFileMgr = NSFileManager.defaultManager;

    if (  argc < 2  ) {
		openLog(FALSE);
        Log(@"1 or more arguments are required");
        errorExit();
	}

    // Set up opsAndFlags and booleans that describe what operations are to be done

    errno = 0;
    char * end = NULL;
    unsigned long parsed = strtoul(argv[1], &end, 0);

    if (   (errno != 0)
        || (end == argv[1])
        || (*end != '\0')
        || (parsed > UINT_MAX)  ) {
        Log(@"Invalid installer bitmask: %s", argv[1]);
        errorExit();
    }
    unsigned opsAndFlags = (unsigned)parsed;

    const unsigned allowedFlags = (  INSTALLER_CLEAR_LOG
                                   | INSTALLER_COPY_APP
                                   | INSTALLER_SECURE_APP
                                   | INSTALLER_SECURE_TBLKS
                                   | INSTALLER_COPY_APP_TO_L_AS_T
                                   | INSTALLER_ALLOW_ROOT_SCRIPTS
                                   | INSTALLER_ALLOW_USER_SCRIPTS
                                   | INSTALLER_REPLACE_DAEMON
                                   | INSTALLER_INSTALL_KEXTS
                                   | INSTALLER_UNINSTALL_KEXTS
                                   | INSTALLER_OPERATION_MASK
                                   );

    unsigned operation = (opsAndFlags & INSTALLER_OPERATION_MASK);
    if (   (operation > INSTALLER_MAX_IMPLEMENTED_OPERATION)
        || ((opsAndFlags & ~allowedFlags) != 0)  ) {
        Log(@"Installer bitmask contains unsupported bits: 0x%08x", opsAndFlags);
        errorExit();
    }

    BOOL doClearLog              = (opsAndFlags & INSTALLER_CLEAR_LOG)          != 0;
    BOOL doCopyApp               = (opsAndFlags & INSTALLER_COPY_APP)           != 0;
    BOOL doSecureApp             = (opsAndFlags & INSTALLER_SECURE_APP)         != 0;
    BOOL doSecureTblks           = (opsAndFlags & INSTALLER_SECURE_TBLKS)       != 0;
    BOOL doCopyAppToL_AS_T       = (opsAndFlags & INSTALLER_COPY_APP_TO_L_AS_T) != 0;
    BOOL doAllowRootScripts      = (opsAndFlags & INSTALLER_ALLOW_ROOT_SCRIPTS) != 0;
    BOOL doAllowUserScripts      = (opsAndFlags & INSTALLER_ALLOW_USER_SCRIPTS) != 0;
    BOOL doForceLoadLaunchDaemon = (opsAndFlags & INSTALLER_REPLACE_DAEMON)     != 0;
    BOOL doInstallKexts          = (opsAndFlags & INSTALLER_INSTALL_KEXTS)      != 0;
    BOOL doUninstallKexts        = (opsAndFlags & INSTALLER_UNINSTALL_KEXTS)    != 0;

    BOOL ignoringInstallKexts = FALSE;
    if (   doInstallKexts
        && doUninstallKexts  ) {
        doInstallKexts = FALSE;
        ignoringInstallKexts = TRUE;
    }

    // Log the arguments installer was started with

    NSString * infoPlistPath = [NSBundle.mainBundle.resourcePath.stringByDeletingLastPathComponent
                                stringByAppendingPathComponent: @"Info.plist"];
    NSDictionary * infoPlist = [NSDictionary dictionaryWithContentsOfFile: infoPlistPath];
    NSString * build = [infoPlist objectForKey: @"CFBundleVersion"];

    NSMutableString * bitMaskDescription = [[[NSMutableString alloc] initWithCapacity: 100] autorelease];

    if (  doClearLog              ) { [bitMaskDescription appendString: @" ClearLog"             ]; }
    if (  doCopyApp               ) { [bitMaskDescription appendString: @" CopyApp"              ]; }
    if (  doSecureApp             ) { [bitMaskDescription appendString: @" SecureApp"            ]; }
    if (  doSecureTblks           ) { [bitMaskDescription appendString: @" SecureTblks"          ]; }
    if (  doCopyAppToL_AS_T       ) { [bitMaskDescription appendString: @" CopyAppToL_AS_T"      ]; }
    if (  doAllowRootScripts      ) { [bitMaskDescription appendString: @" AllowRootScripts"     ]; }
    if (  doAllowUserScripts      ) { [bitMaskDescription appendString: @" AllowUserScripts"     ]; }
    if (  doForceLoadLaunchDaemon ) { [bitMaskDescription appendString: @" LoadLaunchDaemon"     ]; }
    if (  doInstallKexts          ) { [bitMaskDescription appendString: @" InstallKexts"         ]; }
    if (  doUninstallKexts        ) { [bitMaskDescription appendString: @" UninstallKexts"       ]; }

    if (  ignoringInstallKexts    ) { [bitMaskDescription appendString: @" IgnoringInstallKexts" ]; }

    if ( (operation == INSTALLER_COPY) && (argc == 4)           ) { [bitMaskDescription appendString: @" CopyConfig"            ]; }
    if (  operation == INSTALLER_MOVE                           ) { [bitMaskDescription appendString: @" MoveConfig"            ]; }
    if (  operation == INSTALLER_DELETE                         ) { [bitMaskDescription appendString: @" Delete"                ]; }
    if (  operation == INSTALLER_INSTALL_FORCED_PREFERENCES     ) { [bitMaskDescription appendString: @" InstallForcedPrefs"    ]; }
    if (  operation == INSTALLER_EXPORT_ALL                     ) { [bitMaskDescription appendString: @" ExportAll"             ]; }
    if (  operation == INSTALLER_IMPORT                         ) { [bitMaskDescription appendString: @" Import"                ]; }
    if (  operation == INSTALLER_INSTALL_PRIVATE_CONFIG         ) { [bitMaskDescription appendString: @" InstallPrivateConfig"  ]; }
    if (  operation == INSTALLER_INSTALL_SHARED_CONFIG          ) { [bitMaskDescription appendString: @" InstallSharedConfig"   ]; }
    if (  operation == INSTALLER_UPDATE_TUNNELBLICK             ) { [bitMaskDescription appendString: @" UpdateTunnelblick"     ]; }
    if (  operation == INSTALLER_SET_FORCED_PREFERENCE          ) { [bitMaskDescription appendString: @" SetForcedPreference"   ]; }
    if (  operation == INSTALLER_INSTALL_FORCED_PREFERENCES_XML ) { [bitMaskDescription appendString: @" InstallForcedPrefsXML" ]; }
    if (  operation == INSTALLER_RENAME_MIP_FILE                ) { [bitMaskDescription appendString: @" RenameMipFile"         ]; }

    // Remove leading space
    [bitMaskDescription deleteCharactersInRange: NSMakeRange(0, 1)];

    NSMutableString * logString = [NSMutableString stringWithFormat:
                                   @"Tunnelblick installer (build %s) getuid() = %d; geteuid() = %d; getgid() = %d; getegid() = %d\ncurrentDirectoryPath = '%@'; %d arguments:\n",
                                   build.UTF8String, getuid(), geteuid(), getgid(), getegid(), [gFileMgr currentDirectoryPath], argc - 1];
    [logString appendFormat: @"     0x%04x (%@)", opsAndFlags, bitMaskDescription];
    int i;
    for (  i=2; i<argc; i++  ) {
        [logString appendFormat: @"\n     %@", [NSString stringWithUTF8String: argv[i]]];
    }

    BOOL created_L_AS_T = openLog(doClearLog);

    Log(@"%@", logString);

    if (  created_L_AS_T  ) {
        NSDictionary * atts = [gFileMgr tbFileAttributesAtPath: L_AS_T traverseLink: NO];
        unsigned long permissions = [atts filePosixPermissions];
        unsigned long theOwner = [[atts fileOwnerAccountID] unsignedLongValue];
        unsigned long theGroup = [[atts fileGroupOwnerAccountID] unsignedLongValue];
        Log(@"Created directory %@ with owner %lu:%lu and permissions %lo",
                   L_AS_T, (unsigned long)theOwner, (unsigned long)theGroup, (unsigned long)permissions);
    }

    setupLibrary_Application_Support_Tunnelblick();

	NSString * resourcesPath = thisAppResourcesPath(); // (installer itself is in Resources)
    NSArray  * execComponents = [resourcesPath pathComponents];
	if (  [execComponents count] < 3  ) {
        Log(@"too few execComponents; resourcesPath = %@", resourcesPath);
        errorExit();
    }
    
    // We use Deploy located in the Tunnelblick in /Applications, even if we are running from some other location and are copying the application there
#ifndef TBDebug
	gDeployPath = @"/Applications/Tunnelblick.app/Contents/Resources/Deploy";
#else
	gDeployPath = [[resourcesPath stringByAppendingPathComponent: @"Deploy"] retain];
#endif
    
    // Set up globals that have to do with the user
    setupUserGlobals(argc, argv, operation);

    renamex_npWorks = (   testRenamex_np(@"/Applications")
                       && testRenamex_np(L_AS_T)  );
    if (   renamex_npWorks
        && gHomeDirectory  ) {
        NSString * path = [[[[gHomeDirectory
                              stringByAppendingPathComponent: @"Library"]
                             stringByAppendingPathComponent: @"Application Support"]
                            stringByAppendingPathComponent: @"Tunnelblick"]
                           stringByAppendingPathComponent: @"Configurations"];

        renamex_npWorks = testRenamex_np(path);
    }

    // If we copy the .app to /Applications, other changes to the .app affect THAT copy, otherwise they affect the currently running copy
    NSString * appResourcesPath = (  doCopyApp
                                   
                                   ? [[[@"/Applications"
                                        stringByAppendingPathComponent: @"Tunnelblick.app"]
                                       stringByAppendingPathComponent: @"Contents"]
                                      stringByAppendingPathComponent: @"Resources"]
                                   : [[resourcesPath copy] autorelease]);

    NSString * secondArg = nil;
    if (  argc > 2  ) {
        secondArg = [gFileMgr stringWithFileSystemRepresentation: argv[2] length: strlen(argv[2])];
        if (   ( gPrivatePath == nil  )
            || ( ! [secondArg hasPrefix: [gPrivatePath stringByAppendingString: @"/"]])  ) {
            errorExitIfAnySymlinkOrDotDotInPath(secondArg);
        }
    }
    NSString * thirdArg = nil;
    if (  argc > 3  ) {
        thirdArg = [gFileMgr stringWithFileSystemRepresentation: argv[3] length: strlen(argv[3])];
        if (   ( gPrivatePath == nil  )
            || ( ! [thirdArg hasPrefix: [gPrivatePath stringByAppendingString: @"/"]])  ) {
            errorExitIfAnySymlinkOrDotDotInPath(thirdArg);
        }
    }
    
    NSString * fourthArg = nil;
    if (  argc > 4  ) {
        fourthArg = [gFileMgr stringWithFileSystemRepresentation: argv[4] length: strlen(argv[4])];
        if (   ( gPrivatePath == nil  )
            || ( ! [fourthArg hasPrefix: [gPrivatePath stringByAppendingString: @"/"]])  ) {
            errorExitIfAnySymlinkOrDotDotInPath(fourthArg);
        }
    }

    NSString * fifthArg = nil;
    if (  argc > 5  ) {
        fifthArg = [gFileMgr stringWithFileSystemRepresentation: argv[5] length: strlen(argv[5])];
        if (   ( gPrivatePath == nil  )
            || ( ! [fifthArg hasPrefix: [gPrivatePath stringByAppendingString: @"/"]])  ) {
            errorExitIfAnySymlinkOrDotDotInPath(fifthArg);
        }
    }

    //**************************************************************************************************************************
    // (1) Create home directories or repair their ownership/permissions as needed

	setupUser_Library_Application_Support_Tunnelblick();

    securelyDeleteItemIfItExists(@"/Library/Application Support/tunnelblickd");

    // Create or delete L_AS_T_DEBUG_APP_RESOURCES_PATH
#ifdef TBDebug
    // A debug version of Tunnelblick.app can be anywhere, a non-debug version can only be in /Applications.
    // So when securing a debug version, store the absolute path to the app's Resources
    // folder, so tunnelblickd can retrieve it to construct a path to tunnelblick-helper.
    NSError * err;
    BOOL success = [appResourcesPath writeToFile: L_AS_T_DEBUG_APP_RESOURCES_PATH
                                      atomically: YES
                                        encoding: NSUTF8StringEncoding
                                           error: &err];
    if (  success  ) {
        Log(@"Wrote '%@' to %@", appResourcesPath, L_AS_T_DEBUG_APP_RESOURCES_PATH);
    } else {
        Log(@"Could not write %@", L_AS_T_DEBUG_APP_RESOURCES_PATH);
        errorExit();
    }
#else
    // A non-debug version of Tunnelblick.app is always in /Applications by the time it starts using tunnelblickd.
    // A non-debug version of tunnelblickd can thus always find tunnelblick-helper in /Applications/Tunnelblick.app/Contents/Resources.
    if (  [gFileMgr fileExistsAtPath: L_AS_T_DEBUG_APP_RESOURCES_PATH]  ) {
        securelyDeleteItem(L_AS_T_DEBUG_APP_RESOURCES_PATH);
    }
#endif

    //**************************************************************************************************************************
    // (2) If INSTALLER_COPY_APP is set:
    //     Then move /Applications/XXXXX.app to the Trash,
    //          copy this app to /Applications/XXXXX.app,
    //      and secure the copy.

    if (  doCopyApp  ) {
        copyTheApp();
    }
    
	//**************************************************************************************************************************
	// (3) If requested, secure Tunnelblick.app by setting the ownership and permissions of it and all its components

    if ( doSecureApp ) {
		secureTheApp(appResourcesPath, TRUE);
    }

    //**************************************************************************************************************************
    // (4) If requested, copy app to L_AS_T

    if (  doCopyAppToL_AS_T) {
        copyAppToL_AS_T(APPLICATIONS_TB_APP);
    }

    //**************************************************************************************************************************
    // (5) Remove L_AS_T_TBLKS if it exists. It was used by the "old" configuration update mechanism, which has been removed.

    [gFileMgr tbRemovePathIfItExists: L_AS_T_TBLKS];

    
    //**************************************************************************************************************************
    // (6) If requested, secure all .tblk packages

    if (  doSecureTblks  ) {
		secureAllTblks();
    }
    
    //**************************************************************************************************************************
    // (7) Install the .plist at secondArg to L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH
    //
    //     NO LONGER USED BY TUNNELBLICK; KEPT AVAILABLE FOR SCRIPTS BY DEPLOYERS

    if (  operation == INSTALLER_INSTALL_FORCED_PREFERENCES  ) {
		installForcedPreferences(secondArg, thirdArg);
    }
    
    // If the operation is INSTALLER_INSTALL_FORCED_PREFERENCES_XML and the second argument is an XML dictionary,
    // installs the dictionary in L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH

    if (  operation == INSTALLER_INSTALL_FORCED_PREFERENCES_XML  ) {
        if (   thirdArg
            || (secondArg.length == 0)  ) {
            Log(@"Wrong number of arguments for operation INSTALLER_INSTALL_FORCED_PREFERENCES_XML");
            errorExit();
        }

        installForcedPreferencesXML(secondArg);
    }

    //**************************************************************************************************************************
    // (8) If requested, copy or move a single .tblk package or folder,
    //     or install a .tblk (without any nested .tblks).
    //
    //     If installing, the .tblk does not have to be structured properly, installing it will restructure it if necessary.
    //
    // Like the NSFileManager "movePath:toPath:handler" method, we move by copying, then deleting.

    if (   (   (operation == INSTALLER_COPY )
            || (operation == INSTALLER_MOVE)
            )
        && secondArg
        && thirdArg
        && (argc < 5)
        ) {

        //
        // INSTALLER_COPY
        // INSTALLER_MOVE
        //      secondArg  = target
        //      thirdArg   = source (if an empty string, a folder is created at "target")
        //

        NSString * targetPath = secondArg;
        NSString * sourcePath = thirdArg;

        if (  ! [sourcePath isEqualToString: @""]  ) {
            errorExitIfWritableByUserInPath(sourcePath);
            errorExitIfAnySymlinkOrDotDotInPath(sourcePath);
        }

        errorExitIfWritableByUserInPath(targetPath);
        errorExitIfAnySymlinkOrDotDotInPath(targetPath);

        copyOrMoveOneFolderOrTblk(sourcePath, targetPath, (operation == INSTALLER_MOVE));
    }

    if (   operation == INSTALLER_INSTALL_PRIVATE_CONFIG  ) {
        if (   secondArg
            && thirdArg
            && (argc < 6)
            ) {

            //
            // INSTALLER_INSTALL_PRIVATE_CONFIG
            //      secondArg = username (i.e., short username)
            //      thirdArg  = source
            //      fourthArg = subfolder (optional)
            //
            NSString * username   = secondArg;   (void)username; // Not used here. Used in setupUserGlobals()
            NSString * sourcePath = thirdArg;
            NSString * subfolder  = fourthArg;

            errorExitIfAnySymlinkOrDotDotInPath(sourcePath);
            if (  subfolder  ) {
                errorExitIfAnySymlinkOrDotDotInPath(subfolder);
            }

            NSString * targetFolder = (  subfolder
                                       ? [userShadowPath() stringByAppendingPathComponent: subfolder]
                                       : userShadowPath()  );
            securelyCreateFolderAndParents(targetFolder);
            NSString * targetPath = [targetFolder stringByAppendingPathComponent: sourcePath.lastPathComponent];

            copyOrMoveOneFolderOrTblk(sourcePath, targetPath, false); // false = not move (i.e., copy)
        } else {
            Log(@"Wrong number of arguments for INSTALLER_INSTALL_PRIVATE_CONFIG");
            errorExit();
        }
    }
    if (  operation == INSTALLER_INSTALL_SHARED_CONFIG  ) {
        if (   secondArg
            && (argc < 5)
            ) {

            //
            // INSTALLER_INSTALL_SHARED_CONFIG
            //      secondArg = source
            //      thirdArg  = subfolder (optional)
            //

            NSString * sourcePath = secondArg;
            NSString * subfolder  = thirdArg;

            errorExitIfAnySymlinkOrDotDotInPath(sourcePath);
            if (  subfolder  ) {
                errorExitIfAnySymlinkOrDotDotInPath(subfolder);
            }

            NSString * targetFolder = (  subfolder
                                       ? [L_AS_T_SHARED stringByAppendingPathComponent: subfolder]
                                       : L_AS_T_SHARED  );
            securelyCreateFolderAndParents(targetFolder);
            NSString * targetPath = [targetFolder stringByAppendingPathComponent: sourcePath.lastPathComponent];

            copyOrMoveOneFolderOrTblk(sourcePath, targetPath, false); // false = not move (i.e., copy)
        } else {
            Log(@"Wrong number of arguments for INSTALLER_INSTALL_SHARED_CONFIG");
            errorExit();
        }
    }

    //**************************************************************************************************************************
    // (9)
    // If requested, delete a single folder or .tblk package (must be the shared or shadow copy)

    if (  operation == INSTALLER_DELETE  ) {
		deleteOneFolderOrTblk(secondArg, thirdArg);
    }
    
    //**************************************************************************************************************************
    // (10) If the operation is INSTALLER_SET_FORCED_PREFERENCE and both arguments are present,
    //         sets the forced preference named in second_arg to <true> if value in third_arg is "1", or or deletes it if value in third_arg is "0"
    //         (May delete the forced preference file if there are no forced preferences.)

    if (  operation == INSTALLER_SET_FORCED_PREFERENCE  ) {
        if (   fourthArg
            || ( ! setOrDeleteForcedPreference(secondArg, thirdArg)  )  ) {
            Log(@"Invalid arguments to 'set forced preference'");
            errorExit();
        }
    }

    //**************************************************************************************************************************
    // (11) If the operation is INSTALLER_RENAME_MIP_FILE and both arguments are present,
    //         renames the first path (which must be a file in L_AS_T_TEMP) to the second path (which must be a a file in L_AS_T_MIPS).

    if (  operation == INSTALLER_RENAME_MIP_FILE  ) {
        if (   fourthArg
            || ( ! renameTempFileToMipFile(secondArg, thirdArg)  )  ) {
            Log(@"Invalid arguments to 'set forced preference'");
            errorExit();
        }
    }

    ; // STOP HERE IF DEBUGGING INSTALLER ITSELF TO AVOID ERROR SETTING UP tunnelblickd

    //**************************************************************************************************************************
    // (12) Set up tunnelblickd to load when the computer starts

    BOOL installingAConfiguration = (  (argc == 4) || (argc == 5)  ); // (Installing or importing configurations)

    if (  ( ! doForceLoadLaunchDaemon )  ) {
        if (  ! installingAConfiguration  ) {
            if (   needToReplaceLaunchDaemon()
                || ( ! isLaunchDaemonLoaded() )  ) {
                doForceLoadLaunchDaemon = TRUE;
            }
        }
    }
    
    if (  doForceLoadLaunchDaemon  ) {
		setupLaunchDaemon();
    } else {
        if (  ! checkSetOwnership(TUNNELBLICKD_PLIST_PATH, NO, 0, 0)  ) {
            errorExit();
        }
        if (  ! checkSetPermissions(TUNNELBLICKD_PLIST_PATH, PERMS_SECURED_READABLE, YES)  ) {
            errorExit();
        }
    }
	
	//**************************************************************************************************************************
	// (13) If requested, exports all settings and configurations for all users to a file at targetPath, deleting the file if it already exists

	if (   secondArg
		&& ( ! thirdArg   )
		&& (  operation == INSTALLER_EXPORT_ALL)  ) {
		exportToPath(secondArg);
	}
	
	//**************************************************************************************************************************
	// (14) If requested, import settings from the .tblkSetup at secondArg using username mapping in the string in "thirdArg"
	//
	//		NOTE: "thirdArg" is a string that specifies the username mapping to use when importing.

	if (   (operation == INSTALLER_IMPORT)
		&& secondArg
		&& thirdArg  ) {
		importSetup(secondArg, thirdArg);
	}
	
    //**************************************************************************************************************************
    // (15) If requested, uninstall, install kexts, otherwise update them if they are installed

    if (   doUninstallKexts  ) {
        uninstallKexts();
    } else if (   doInstallKexts  ) {
        installOrUpdateKexts(YES);
    } else {
        installOrUpdateKexts(NO);
    }
    
    //**************************************************************************************************************************
    // (16) If requested, update Tunnelblick
    //

    if (  operation == INSTALLER_UPDATE_TUNNELBLICK  ) {
        if (   secondArg
            && thirdArg
            && fourthArg
            && fifthArg) {

            pid_t tunnelblickPid = [fifthArg intValue];
            if (  tunnelblickPid == 0  ) {
                Log(@"Tunnelblick PID cannot be zero for operation INSTALLER_UPDATE_TUNNELBLICK");
                Log(@"Tunnelblick installer finished with errors;");
                gErrorOccurred = TRUE;
            } else if (  ! installerUpdateTunnelblick(secondArg, thirdArg, fourthArg, userUID(), userGID(), tunnelblickPid)  ) {
                gErrorOccurred = TRUE;
            }
        } else {
            Log(@"Missing argument(s); cannot perform INSTALLER_UPDATE_TUNNELBLICK");
            gErrorOccurred = TRUE;
        }
    }

    //**************************************************************************************************************************
    // DONE

    if (  gErrorOccurred  ) {
        Log(@"Tunnelblick installer finished with errors");
        storeAuthorizedDoneFileAndExit(EXIT_FAILURE);
    }

    Log(@"Tunnelblick installer succeeded");
    storeAuthorizedDoneFileAndExit(EXIT_SUCCESS);
}
