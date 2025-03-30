/*
 * Copyright 2004, 2005, 2006, 2007, 2008, 2009 by Angelo Laub
 * Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2018, 2019, 2020, 2021, 2023. All rights reserved.

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
//     usernamMappingString is a string that contains a set of username mapping rules to use when importing a .tblkSetup. It consists
//							of zero or more separated-by-slashes pairs of username:username. The first username is the username in the
//							.tblkSetup (from the computer the .tblkSetup was created on). The second is the username on this computer
//							(the computer the import is being done on).
//
//							Each username should be the "short" username (e.g. "abcuthbert"), not the "long" username ("A. B. Cuthbert")
//
//							Example: "abc:def/ghi:jkl" maps user "abc" in the .tblkSetup to computer user "def" and
//									 user "ghi" in the .tblkSetup to computer user "jkl"
//
// This program does the following, in this order:
//
//      (1) Clears the installer log if INSTALLER_CLEAR_LOG is set
//			Creates directories or repairs their ownership/permissions as needed
//			Repairs ownership/permissions of L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH
//			Creates the .mip file if it does not already exist
//          Updates Tunnelblick kexts in /Library/Extensions (unless kexts are being uninstalled)

//      (2) If INSTALLER_COPY_APP is set, this app is copied to /Applications and the com.apple.quarantine extended attribute is removed from the app and all items within it

//      (3) If INSTALLER_SECURE_APP is set, secures Tunnelblick.app by setting the ownership and permissions of its components.

//      (4) If INSTALLER_COPY_APP is set, L_AS_T_TBLKS is pruned by removing all but the highest edition of each container

//      (5) If INSTALLER_SECURE_TBLKS is set, then secures all .tblk packages in the following folders:
//				/Library/Application Support/Tunnelblick/Shared
//				~/Library/Application Support/Tunnelblick/Configurations
//				/Library/Application Support/Tunnelblick/Users/<username>
//
//      (6) if the operation is INSTALLER_INSTALL_FORCED_PREFERENCES and targetPath is given and is a .plist and there is no secondPath
//             installs the .plist at targetPath in L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH
//
//      (7) If the operation is INSTALLER_COPY or INSTALLER_MOVE and both targetPath and sourcePath are given,
//             copies or moves sourcePath to targetPath. Copies unless INSTALLER_MOVE is set.  (Also copies or moves the shadow copy if deleting a private configuration)
//
//     (8) If the operation is INSTALLER_DELETE and only targetPath is given,
//             deletes the .ovpn or .conf file or .tblk package at targetPath (also deletes the shadow copy if deleting a private configuration)
//
//     (9) If not installing a configuration, sets up tunnelblickd
//
//	   (10) If requested, exports all settings and configurations for all users to a file at targetPath, deleting the file if it already exists
//
//	   (11) If requested, import settings from the .tblkSetup at targetPath
//
//     (12) If requested, install or uninstall kexts
//
//     (13) If requested, update Tunnelblick

// When finished (or if an error occurs), the file at AUTHORIZED_DONE_PATH is written to indicate the program has finished

// The following globals are not modified after they are initialized:
static FILE          * gLogFile;					  // FILE for log
NSFileManager * gFileMgr;                     // [NSFileManager defaultManager]
NSString      * gDeployPath;                  // Path to Tunnelblick.app/Contents/Resources/Deploy
static BOOL     renamex_npWorks = NO;         // renamex_np() works as needed for /Applications and L_AS_T, and home folder if it is available


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
static NSString      * gHomeDirectory = nil;

static NSAutoreleasePool * pool;

static BOOL            gErrorOccurred = FALSE;       // Set if an error occurred

//**************************************************************************************************************************
// FORWARD REFERENCES

static void errorExit(void);

static void errorExitIfAnySymlinkInPath(NSString * path);

static const char * fileSystemRepresentationFromPath(NSString * path);

static NSString * userPrivatePath(void);

static void securelyDeleteItem(NSString * path);

static NSString * usernameFromPossiblePrivatePath(NSString * path);

static NSString * privatePathFromUsername(NSString * username);

//**************************************************************************************************************************
// LOGGING AND ERROR HANDLING

#ifdef TBDebug
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
static void debugLog(NSString * string) {
#pragma clang diagnostic pop

	// Call this function to create files in /tmp to show progress through this program
	// when there are problems that cause the log not to be available
	// For example, if this installer hangs.
	//
	// "string" is a string identifier indicating where debugLog was called from.
    // "string" must be able to be added as part of a file name, so no ":" or "/" chars, etc.

	static unsigned int debugLogMessageCounter = 0;
    NSString * now = [[NSDate date] tunnelblickUserLogRepresentation];

	NSString * path = [NSString stringWithFormat: @"/tmp/0-%u-tunnelblick-installer-%@-%@.txt", ++debugLogMessageCounter, now, string];
	[gFileMgr createFileAtPath: path contents: [NSData data] attributes: nil];
}
#endif

static void openLog(BOOL clearLog) {

    if (  ! [gFileMgr tbRemovePathIfItExists: INSTALLER_OLD_LOG_PATH]  ) {
        NSLog(@"Could not delete %@", INSTALLER_OLD_LOG_PATH);
    }

    if (  [gFileMgr fileExistsAtPath: INSTALLER_LOG_PATH]) {
        if (  ! [gFileMgr tbForceRenamePath:INSTALLER_LOG_PATH toPath: INSTALLER_OLD_LOG_PATH]  ) {
            NSLog(@"Could not rename %@ to %@", INSTALLER_LOG_PATH, INSTALLER_OLD_LOG_PATH);
        }
    }

    const char * path = fileSystemRepresentationFromPath(INSTALLER_LOG_PATH);
	
    char * mode = (  clearLog
                   ? "w"
                   : "a");

    gLogFile = fopen(path, mode);

	if (  gLogFile == NULL  ) {
		errorExit();
	}
}

void appendLog(NSString * s) {

    if (  gLogFile != NULL  ) {
        NSString * now = [[NSDate date] tunnelblickUserLogRepresentation];
        fprintf(gLogFile, "%s: %s\n", [now UTF8String], [s UTF8String]);
    }

    NSLog(@"%@", s);
}

static void errorExit(void) {

#ifdef TBDebug
    appendLog([NSString stringWithFormat: @"errorExit(): Stack trace: %@", callStack()]);
#else
    appendLog(@"Tunnelblick installer failed");
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
        appendLog([NSString stringWithFormat: @"Could not get filesystem representation for %@", path]);
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

    BOOL isPrivate = (   [absolutePath hasPrefix: @"/Users/"]
                      && [absolutePath hasPrefix: [[userPrivatePath() stringByDeletingLastPathComponent] stringByAppendingString: @"/"]]
                      );
    return isPrivate;
}

static void resolveSymlinksInPath(NSString * targetPath) {

    // There are symlinks in a .tblk for files which are not readable by the user but should be propagated from one configuration to another when installing an updated configuration.
    // These symlinks need to be replaced by the files to which they point.
    //
    // This is safe to do as root because only Tunnelblick or an admin can invoke the installer as root, and Tunnelblick allows only its own symlinks.
    // (Tunnelblick resolves symlinks provided by the user while running as the user.)
    //
    // Because the target is a temporary copy, we replace the symlinks with the file contents in a file owned by root:wheel with permissions 0700, so the file cannot be read except by root.
    // The final, possibly less restrictive, ownership and permissions will be set later.

    if (  ! [targetPath hasSuffix: @".tblk"] ) {
        return;
    }

    NSString * file;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: targetPath];
    while (  (file = [dirEnum nextObject])  ) {
        NSString * fullPath = [targetPath stringByAppendingPathComponent: file];
        NSDictionary * fullPathAttributes = [gFileMgr tbFileAttributesAtPath: fullPath traverseLink: NO];
        if (  [fullPathAttributes fileType] == NSFileTypeSymbolicLink  ) {

            NSString * resolvedPath = [gFileMgr tbPathContentOfSymbolicLinkAtPath: fullPath];
            if (  ! (   [resolvedPath hasPrefix: L_AS_T_SHARED]
                     || [resolvedPath hasPrefix: L_AS_T_TBLKS]
                     || [resolvedPath hasPrefix: L_AS_T_USERS]
                     || [resolvedPath hasPrefix: gDeployPath]
                     )  ) {
                appendLog([NSString stringWithFormat: @"Symlink is not to an allowed path: %@", resolvedPath]);
                errorExit();
            }

            NSData * data = [gFileMgr contentsAtPath: resolvedPath];

            if (  ! data  ) {
                appendLog([NSString stringWithFormat: @"Could not get contents of %@", resolvedPath]);
                errorExit();
            }

            securelyDeleteItem(fullPath);

            NSDictionary * attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                         [NSNumber numberWithInt: 0], NSFileOwnerAccountID,
                                         [NSNumber numberWithInt: 0], NSFileGroupOwnerAccountID,
                                         [NSNumber numberWithInt: 0700], NSFilePosixPermissions,
                                         nil];

            if (  [gFileMgr createFileAtPath: fullPath contents: data attributes: attributes]  ) {
                appendLog([NSString stringWithFormat: @"Replaced symlink at %@\n with copy of %@", fullPath, resolvedPath]);
            } else {
                appendLog([NSString stringWithFormat: @"Could not replace symlink at %@\n     with a copy of %@", fullPath, resolvedPath]);
                errorExit();
            }
        }
    }
}

static NSArray * configurationPathsFromPath(NSString * path) {

    NSString * privatePath = gPrivatePath;
    if (  privatePath == nil  ) {
        NSString * username = usernameFromPossiblePrivatePath(path);
        if (  username != nil  ) {
            privatePath = privatePathFromUsername(username);
        }
    }

    NSArray * paths = [NSArray arrayWithObjects:
                       gDeployPath,
                       L_AS_T_SHARED,
                       privatePath, // May be nil, so must be last
                       nil];
    return paths;
}

NSString * lastPartOfPath(NSString * path) {

    NSArray * paths = configurationPathsFromPath(path);
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

static void pruneL_AS_T_TBLKS(void) {

    // Prune L_AS_T_TblKS by removing all but the highest edition of each container

    NSDictionary * bundleIdEditions = highestEditionForEachBundleIdinL_AS_T(); // Key = bundleId; object = edition

    if (  [bundleIdEditions count] != 0  ) {
        NSString * bundleIdAndEdition;
        NSDirectoryEnumerator * outerDirEnum = [gFileMgr enumeratorAtPath: L_AS_T_TBLKS];
        while (  (bundleIdAndEdition = [outerDirEnum nextObject])  ) {
            [outerDirEnum skipDescendents];
            NSString * containerPath = [L_AS_T_TBLKS stringByAppendingPathComponent: bundleIdAndEdition];
            BOOL isDir;
            if (   ( ! [bundleIdAndEdition hasPrefix: @"."] )
                && ( ! [bundleIdAndEdition hasSuffix: @".tblk"] )
                && [gFileMgr fileExistsAtPath: containerPath isDirectory: &isDir]
                && isDir  ) {
                NSString * bundleId = [bundleIdAndEdition stringByDeletingPathEdition];
                if (  ! bundleId  ) {
                    appendLog([NSString stringWithFormat: @"Container path does not have a bundleId: %@", containerPath]);
                    break;
                }
                NSString * edition  = [bundleIdAndEdition pathEdition];
                if (  ! edition  ) {
                    appendLog([NSString stringWithFormat: @"Container path does not have an edition: %@", containerPath]);
                    break;
                }
                NSString * highestEdition = [bundleIdEditions objectForKey: bundleId];
                if (  ! highestEdition  ) {
                    appendLog(@"New entry in L_AS_T_TBLKS appeared during pruning");
                    break;
                }
                if (  ! [edition isEqualToString: highestEdition]  ) {
                    securelyDeleteItem(containerPath);
                    appendLog([NSString stringWithFormat: @"Pruned L_AS_T_TBLKS by removing %@", containerPath]);
                }
            }
        }
    }
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
        if (   ( ! [entry hasPrefix: @"."] )
            && [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
            && ( ! isDir )  ) {
            if (  [entry isEqualToString: @"Info.plist"]  ) {
                [sourcePaths addObject: fullPath];
                [targetPaths addObject: [[path stringByAppendingPathComponent: @"/Contents"] stringByAppendingPathComponent: entry]];
            } else if (  ! [entry hasPrefix: @"."]  ) {
                NSString * targetEntry = entry;
                if (  [entry hasSuffix: @".ovpn"]  ) {
                    targetEntry = [[entry stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"config.ovpn"];
                }
                [sourcePaths addObject: fullPath];
                [targetPaths addObject: [[path stringByAppendingPathComponent: @"/Contents/Resources"] stringByAppendingPathComponent: targetEntry]];
            }
        }
    }

    for (  NSUInteger i=0; i<[sourcePaths count]; i++  ) {
        if (  ! [gFileMgr tbMovePath: sourcePaths[i] toPath: targetPaths[i] handler: nil]  ) {
            appendLog([NSString stringWithFormat: @"Unable to move %@ to %@", sourcePaths[i], targetPaths[i]]);
            errorExit();
        } else {
            appendLog([NSString stringWithFormat: @"Moved %@ to %@", sourcePaths[i], targetPaths[i]]);
        }
    }
}

static void errorExitIfAnySymlinkInPath(NSString * path) {

    NSString * curPath = path;
    while (   (curPath.length != 0)
           && ! [curPath isEqualToString: @"/"]  ) {
        if (  [gFileMgr fileExistsAtPath: curPath]  ) {
            NSDictionary * fileAttributes = [gFileMgr tbFileAttributesAtPath: curPath traverseLink: NO];
            if (  [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
                if (   ( ! [curPath hasSuffix: @"/Tunnelblick.app/Contents/Resources/openvpn/default"] )
                    && ( [curPath rangeOfString: @"/Tunnelblick.app/Contents/Frameworks/Sparkle.framework/"].length == 0 )
                    ) {
                    appendLog([NSString stringWithFormat: @"Apparent symlink attack detected: Symlink is at %@, full path being tested is %@", curPath, path]);
                    errorExit();
                }
            }
        }

        curPath = [curPath stringByDeletingLastPathComponent];
    }
}

static void errorExitIfSymlinksOrDoesNotExistOrIsNotReadableAtPath(NSString * path) {

    if (   [gFileMgr fileExistsAtPath: path]
        && [gFileMgr isReadableFileAtPath: path]  ) {
        errorExitIfAnySymlinkInPath(path);
        return;
    }

    appendLog([NSString stringWithFormat: @"File does not exist or is not readable: %@", path]);
    errorExit();
}

BOOL removeQuarantineBitWorker(NSString * path) {

    const char * fullPathC = fileSystemRepresentationFromPath(path);
    const char * quarantineBitNameC = "com.apple.quarantine";
    int status = removexattr(fullPathC, quarantineBitNameC, XATTR_NOFOLLOW);
    if (   (status != 0)
        && (errno != ENOATTR)) {
        appendLog([NSString stringWithFormat: @"Failed to remove '%s' from %s; errno = %ld; error was '%s'", quarantineBitNameC, fullPathC, (long)errno, strerror(errno)]);
        return FALSE;
    }

    return TRUE;
}

void removeQuarantineBit(NSString * tunnelblickAppPath) {

    if (  ! removeQuarantineBitWorker(tunnelblickAppPath)  ) {
        goto fail;
    }

    NSDirectoryEnumerator * dirE = [gFileMgr enumeratorAtPath: tunnelblickAppPath];
    NSString * file;
    while (  (file = [dirE nextObject])  ) {
        NSString * fullPath = [tunnelblickAppPath stringByAppendingPathComponent: file];
        if (  ! removeQuarantineBitWorker(fullPath)  ) {
            goto fail;
        }
    }

    appendLog([NSString stringWithFormat: @"Removed any 'com.apple.quarantine' extended attributes from '%@'", tunnelblickAppPath]);
    return;

fail:
    appendLog([NSString stringWithFormat: @"Unable to remove all 'com.apple.quarantine' extended attributes from '%@'", tunnelblickAppPath]);
    errorExit();
}


//**************************************************************************************************************************
// SECURELY* ROUTINES

static void securelyDeleteFolder(NSString * path) {

    errorExitIfAnySymlinkInPath(path);

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
        appendLog([NSString stringWithFormat: @"rmdir() failed with error %d ('%s') for path %@", errno, strerror(errno), path]);
        errorExit();
    }
}

static void securelyDeleteItem(NSString * path) {

    errorExitIfAnySymlinkInPath(path.stringByDeletingLastPathComponent);

    const char * pathC = fileSystemRepresentationFromPath(path);

    struct stat status;

    if (  lstat(pathC, &status) != 0  ) {
        appendLog([NSString stringWithFormat: @"lstat() failed with error %d ('%s') for %@", errno, strerror(errno), path]);
        errorExit();
    }

    if (   ( ! S_ISLNK(status.st_mode) )
        && S_ISDIR(status.st_mode)  ) {
        securelyDeleteFolder(path);
    } else {
        if (  0 != unlink(pathC)  ) {
            appendLog([NSString stringWithFormat: @"unlink() failed with error %d ('%s') for path %@", errno, strerror(errno), path]);
            errorExit();
        }
    }
}

static void securelyDeleteItemIfItExists(NSString * path) {

    errorExitIfAnySymlinkInPath(path);

    if (  ! [gFileMgr fileExistsAtPath: path]  ) {
        return;
    }

    securelyDeleteItem(path);
}

static void securelyRename(NSString * sourcePath, NSString * targetPath) {

    errorExitIfAnySymlinkInPath(sourcePath);
    errorExitIfAnySymlinkInPath(targetPath);

    if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
        securelyDeleteItem(targetPath);
    }

    if (  renamex_npWorks  ) {
        if (  0 != renamex_np(fileSystemRepresentationFromPath(sourcePath), fileSystemRepresentationFromPath(targetPath), (RENAME_NOFOLLOW_ANY | RENAME_EXCL))  ){
            appendLog([NSString stringWithFormat: @"renamex_np() failed with error %d ('%s') trying to rename %@ to %@",
                       errno, strerror(errno), sourcePath, targetPath]);

            // Source and target may be on different volumes. Try moving instead of renaming.
            NSError * err = nil;
            if (  [gFileMgr moveItemAtPath: sourcePath toPath: targetPath error: &err]  ) {
                appendLog([NSString stringWithFormat: @"Used NSFileManager to move %@ to %@", sourcePath, targetPath]);
            } else {
                appendLog([NSString stringWithFormat: @"NSFileManager error moving %@ to %@: %@", sourcePath, targetPath, err]);
                errorExit();
            }
        } else {
            appendLog([NSString stringWithFormat: @"renamex_np() succeeded renaming %@ to %@", sourcePath, targetPath]);
        }
    } else {
        if (  0 != rename(fileSystemRepresentationFromPath(sourcePath), fileSystemRepresentationFromPath(targetPath))  ){
            appendLog([NSString stringWithFormat: @"rename() failed with error %d ('%s') trying to rename %@ to %@",
                       errno, strerror(errno), sourcePath, targetPath]);
            errorExit();
        } else {
            appendLog([NSString stringWithFormat: @"rename() succeeded renaming %@ to %@", sourcePath, targetPath]);
        }
    }
}

static void securelyCreateFileOrDirectoryEntry(BOOL isDir, NSString * path) {

    // Create a file or a directory owned by root with 0700 permissions (permissions will be changed to the correct values later)

    errorExitIfAnySymlinkInPath(path);

    if (  isDir  ) {
        umask(0077);
        int result = mkdir(fileSystemRepresentationFromPath(path), 0700);
        umask(S_IWGRP | S_IWOTH);
        if (  result != 0  ) {
            appendLog([NSString stringWithFormat: @"mkdir() returned error: '%s' for path %@", strerror(errno), path]);
            errorExit();
        }
    } else {
        int result = open(fileSystemRepresentationFromPath(path), (O_CREAT | O_EXCL | O_APPEND | O_NOFOLLOW_ANY), 0700);
        if (  result < 0  ) {
            appendLog([NSString stringWithFormat: @"open() returned error: '%s' for path %@", strerror(errno), path]);
            errorExit();
        }
        close(result); // Ignore errors
    }
}

static void securelyCreateFolderAndParents(NSString * path) {

    errorExitIfAnySymlinkInPath(path);

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

    appendLog([NSString stringWithFormat: @"Created %@ with owner %@:%@ (%@:%@) and permissions 0%lo", path,
               [attributes fileOwnerAccountName], [attributes fileGroupOwnerAccountName],
               [attributes fileOwnerAccountID],   [attributes fileGroupOwnerAccountID],   [attributes filePosixPermissions]]);
}

static void securelySetItemAttributes(BOOL isDir, NSString * sourcePath, NSString * targetPath) {

    errorExitIfAnySymlinkInPath(sourcePath);
    errorExitIfAnySymlinkInPath(targetPath);

    const char * sourcePathC = fileSystemRepresentationFromPath(sourcePath);
    const char * targetPathC = fileSystemRepresentationFromPath(targetPath);

    // Open the item as READ-ONLY (we're not changing it now)
    int fd = open(targetPathC, (O_RDONLY | O_NOFOLLOW_ANY));
    if (  fd == -1  ) {
        appendLog([NSString stringWithFormat: @"Could not open %s", targetPathC]);
        errorExit();
    }

    struct stat status;

    int result = fstat(fd, &status);
    if (   (result != 0)
        || (status.st_uid != 0)
        || (status.st_nlink != (isDir ? 2 : 1))
        || (status.st_mode  != (isDir ? S_IFDIR | 0700 : S_IFREG | 0700))  ) {
        appendLog([NSString stringWithFormat: @"Item has been modified after being created at path %@\nowner = %u; group = %u; nlink = %u; mode = 0%o",
                   targetPath, status.st_uid, status.st_gid, status.st_nlink, status.st_mode]);
        errorExit();
    }

    // Change owner group (owner is already 0)
    result = fchown(fd, 0, 0);
    if (  result != 0  ) {
        appendLog([NSString stringWithFormat: @"lchown() returned error: '%s' for path %s", strerror(errno), targetPathC]);
        errorExit();
    }

    // Change permissions
    NSDictionary * sourceAttributes = [gFileMgr tbFileAttributesAtPath: sourcePath traverseLink: NO];
    mode_t mode = [[sourceAttributes objectForKey: NSFilePosixPermissions] unsignedIntValue];
    result = fchmod(fd, mode);
    if (  result != 0  ) {
        appendLog([NSString stringWithFormat: @"chmod() returned error: '%s' for path %s", strerror(errno), targetPathC]);
        errorExit();
    }

    // Verify ownership, permissions, no hard links, and either a directory or a regular file
    mode = mode | (  isDir
                   ? S_IFDIR
                   : S_IFREG);

    result = lstat(targetPathC, &status);
    if (   (result != 0)
        || (status.st_uid != 0)
        || (status.st_gid != 0)
        || (status.st_nlink != (isDir ? 2 : 1))
        || (status.st_mode  != mode)  ) {
        appendLog([NSString stringWithFormat: @"Failed to modify group and/or permissions at path %@\nowner = %u; group = %u; nlink = %u; mode = 0%o",
                   targetPath, status.st_uid, status.st_gid, status.st_nlink, status.st_mode]);
        errorExit();
    }

    // Copy dates
    // (1) Must convert between timespec returned from stat() and timeval needed by lutimes().
    // (2) Must first uses futimes() with the creation date, which will set the creation date and the modified date
    //     to the supplied date because it is earlier than than the creation date.
    //     Must then use lutimes() to set the modified date.

    // Get creation and modified dates
    result = lstat(sourcePathC, &status);
    if (  result != 0  ) {
        appendLog([NSString stringWithFormat: @"lstat() failed for path %s", sourcePathC]);
        errorExit();
    }
    struct timespec createdTS  = status.st_birthtimespec;
    struct timespec modifiedTS = status.st_mtimespec;

    // Convert creation date format and set creation date
    struct timeval createdTV;
    createdTV.tv_sec  = createdTS.tv_sec;
    createdTV.tv_usec = createdTS.tv_nsec / 1000;
    struct timeval createdTimevals[2] = {createdTV, createdTV};
    result = futimes(fd, createdTimevals);
    if (  result != 0  ) {
        appendLog([NSString stringWithFormat: @"lutimes() #1 failed for %s", targetPathC]);
        errorExit();
    }

    // Convert modified date format and set modified date
    struct timeval modifiedTV;
    modifiedTV.tv_sec  = modifiedTS.tv_sec;
    modifiedTV.tv_usec = modifiedTS.tv_nsec / 1000;
    struct timeval modifiedTimevals[2] = {modifiedTV, modifiedTV};
    result = futimes(fd, modifiedTimevals);
    if (  result != 0  ) {
        appendLog([NSString stringWithFormat: @"lutimes() #1 failed for %s", targetPathC]);
        errorExit();
    }

    close(fd);
}

static void securelyCopyDirectly(NSString * sourcePath, NSString * targetPath);

static void securelyCopyFileOrFolderContents(BOOL isDir, NSString * sourcePath, NSString * targetPath) {

    errorExitIfAnySymlinkInPath(sourcePath);
    errorExitIfAnySymlinkInPath(targetPath);

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
            appendLog([NSString stringWithFormat: @"Could not read data from %@", sourcePath]);
            errorExit();
        }

        NSFileHandle * fh = [NSFileHandle fileHandleForWritingAtPath: targetPath];
        if (  ! fh  ) {
            appendLog([NSString stringWithFormat: @"Could not get file handle to write to %@", targetPath]);
            errorExit();
        }

        @try {
            [fh writeData: data];
        } @catch (NSException *exception exception) {
            appendLog([NSString stringWithFormat: @"Could not write data (%@) to %@", exception, targetPath]);
            [fh release];
            errorExit();
        }
    }
}

static void securelyCopyDirectly(NSString * sourcePath, NSString * targetPath) {

    // Copies a file, or a folder and its contents making sure the copy has the same permissions and dates as the original but is owned by root:wheel.
    //
    // DO NOT USE THIS FUNCTION: Use securelyCopy() instead.
    //
    // This routine is called only by securelyCopy() and securelyCopyFileOrFolderContents().

    errorExitIfAnySymlinkInPath(sourcePath);
    errorExitIfAnySymlinkInPath(targetPath);

    BOOL isDir;

    if (  ! [gFileMgr fileExistsAtPath: sourcePath isDirectory: &isDir]  ) {
        appendLog([NSString stringWithFormat: @"Does not exist: %@", sourcePath]);
        errorExit();
    }

    securelyDeleteItemIfItExists(targetPath);

    securelyCreateFileOrDirectoryEntry(isDir, targetPath);

    // Set final permissions and dates
    securelySetItemAttributes(isDir, sourcePath, targetPath);

    securelyCopyFileOrFolderContents(isDir, sourcePath, targetPath);
}

static void securelyCopy(NSString * sourcePath, NSString * targetPath) {

    // Copies a file, or a folder and its contents, making sure the copy has the same permissions and dates as the original but is owned by root:wheel.
    //
    // Uses an intermediate file or folder and then renames it, so no partial copy has been done if an error occurs.

    errorExitIfAnySymlinkInPath(sourcePath);
    errorExitIfAnySymlinkInPath(targetPath);

    BOOL isDir;

    if (  ! [gFileMgr fileExistsAtPath: sourcePath isDirectory: &isDir]  ) {
        appendLog([NSString stringWithFormat: @"Does not exist: %@", sourcePath]);
        errorExit();
    }

    NSString * tempPath = [L_AS_T stringByAppendingPathComponent: @"installer-temp"];

    securelyCopyDirectly(sourcePath, tempPath);

    securelyRename(tempPath, targetPath);
}

static void securelyMove(NSString * sourcePath, NSString * targetPath) {

    errorExitIfAnySymlinkInPath(sourcePath);
    errorExitIfAnySymlinkInPath(targetPath);

    securelyCopy(sourcePath, targetPath);

    securelyDeleteItem(sourcePath);
}

static BOOL testRenamex_np(NSString * folder) {

    errorExitIfAnySymlinkInPath(folder);

    // Touch two files (delete them first if they exist)
    NSString * test1Path = [folder stringByAppendingPathComponent: @"renamex_np-test-target-1"];
    securelyDeleteItemIfItExists(test1Path);
    if (  ! [gFileMgr createFileAtPath: test1Path contents: nil attributes: nil]  ) {
        appendLog([NSString stringWithFormat: @"testRenamex_np: Can't create renamex_np-test-target-1 in %@", folder]);
    }
    NSString * test2Path = [folder stringByAppendingPathComponent: @"renamex_np-test-target-2"];
    securelyDeleteItemIfItExists(test2Path);
    if (  ! [gFileMgr createFileAtPath: test2Path contents: nil attributes: nil]  ) {
        appendLog([NSString stringWithFormat: @"testRenamex_np: Can't create renamex_np-test-target-2 in %@", folder]);
    }

    // Try to rename test1 to test2. This should fail because test2 exists and the RENAME_EXCL option is used
    if (  0 == renamex_np(fileSystemRepresentationFromPath(test1Path), fileSystemRepresentationFromPath(test2Path),(RENAME_NOFOLLOW_ANY | RENAME_EXCL))  ) {
        // renamex_np succeeded but should have failed
        appendLog([NSString stringWithFormat: @"renamex_np() test #1 failed for %@", folder]);
        securelyDeleteItemIfItExists(test1Path);
        securelyDeleteItemIfItExists(test2Path);
        return FALSE;
    }

    securelyDeleteItemIfItExists(test2Path);

    // Try to rename test1 to test2. This should now succeed because test2 does not exist
    if (  0 != renamex_np(fileSystemRepresentationFromPath(test1Path), fileSystemRepresentationFromPath(test2Path),(RENAME_NOFOLLOW_ANY | RENAME_EXCL))  ) {
        // renamex_np() failed
        appendLog([NSString stringWithFormat: @"renamex_np() test #2 failed for %@", folder]);
        securelyDeleteItemIfItExists(test1Path);
        securelyDeleteItemIfItExists(test2Path);
        return FALSE;
    }

    securelyDeleteItemIfItExists(test2Path);    // test1 was succcesfully renamed to test2, so delete test2

    appendLog([NSString stringWithFormat: @"renamex_np() tests succeeded for %@", folder]);

    return TRUE;
 }

//**************************************************************************************************************************
// USER INFORMATION

static NSString * userUsername(void) {

    if (  gUsername != nil  ) {
        return gUsername;
    }

    appendLog(@"Tried to access userUsername, which was not set");
    errorExit();
    return nil; // Satisfy analyzer
}

static NSString * userHomeDirectory(void) {

    if (  gHomeDirectory != nil  ) {
        return gHomeDirectory;
    }

    appendLog(@"Tried to access userHomeDirectory, which was not set");
    errorExit();
    return nil; // Satisfy analyzer
}

static NSString * userPrivatePath(void) {

    if (  gPrivatePath != nil  ) {
        return gPrivatePath;
    }

    appendLog(@"Tried to access userPrivatePath, which was not set");
    errorExit();
    return nil; // Satisfy analyzer
}

static uid_t userUID(void) {

    if (  gUserID != 0  ) {
        return gUserID;
    }

    appendLog(@"Tried to access userUID, which was not set");
    errorExit();
    return 0; // Satisfy analyzer
}

static gid_t userGID(void) {

    if (  gGroupID != 0  ) {
        return gGroupID;
    }

    appendLog(@"Tried to access userGID, which was not set");
    errorExit();
    return 0; // Satisfy analyzer
}

static void getUidAndGidFromUsername(NSString * username, uid_t * uid_ptr, gid_t * gid_ptr) {

    // Modified version of sample code by Matthew Flaschen
    // from https://stackoverflow.com/questions/1009254/programmatically-getting-uid-and-gid-from-username-in-unix

    const char * username_C = [username cStringUsingEncoding: NSASCIIStringEncoding];
    if(  username_C == NULL  ) {
        appendLog([NSString stringWithFormat: @"Failed to convert username '%@' to an ASCII username.", username]);
        errorExit();
    }

    struct passwd * pwd = calloc(1, sizeof(struct passwd));
    if(  pwd == NULL  ) {
        appendLog(@"Failed to allocate struct passwd for getpwnam_r.");
        errorExit();
    }

    size_t buffer_len = sysconf(_SC_GETPW_R_SIZE_MAX) * sizeof(char);
    char *buffer = malloc(buffer_len);
    if(  buffer == NULL  ) {
        appendLog(@"Failed to allocate buffer for getpwnam_r.");
        free(pwd);
        errorExit();
    }

    errno = 0;
    struct passwd * result = pwd;  // getpwnam_r overwrites this copy of pwd but we keep pwd so we can free it later
    int return_status = getpwnam_r(username_C, pwd, buffer, buffer_len, &result);
    if (  return_status != 0  ) {
        appendLog([NSString stringWithFormat: @"getpwnam_r returned error %d; errno = %d ('%s')", return_status, errno, strerror(errno)]);
        free(pwd);
        free(buffer);
        errorExit();
    }
    if(  result == NULL  ) {
        appendLog([NSString stringWithFormat: @"getpwnam_r failed to find entry for '%s'. (First argument to installer must be a username.)", username_C]);
        free(pwd);
        free(buffer);
        errorExit();
    }

    *uid_ptr = result->pw_uid;
    *gid_ptr = result->pw_gid;

    free(pwd);
    free(buffer);

    if (  *uid_ptr == 0  ) {
        appendLog(@"Cannot run installer using username 'root'");
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
        gGroupID = privateFolderGroup(gPrivatePath);
        appendLog([NSString stringWithFormat: @"Determined username '%@' from getuid(): %u", gUsername, gUserID]);

    } else if (  operation == INSTALLER_INSTALL_PRIVATE_CONFIG  ) {
        //
        // Calculate user info from username given as an argument
        //

        if (  argc < 3  ) {
            appendLog(@"Must provide path and username when copying a private configuration");
            errorExit();
        }

        gUsername = [[NSString stringWithCString: argv[2] encoding: NSASCIIStringEncoding] retain];
        if (   ( gUsername == nil )
            || ( ! usernameIsValid(gUsername) )  ) {
            appendLog(@"Second argument must be a valid username");
            errorExit();
        }

        setupUserGlobalsFromGUsername();
        if (  gUserID == 0  ) {
            appendLog([NSString stringWithFormat: @"Could not get uid for user '%@' (determined from second argument)", gUsername]);
        } else {
            appendLog([NSString stringWithFormat: @"Determined username '%@' from second argument", gUsername]);
        }
    } else {
        //
        // Calculate user info from current working directory path if possible
        //
        gUsername = [usernameFromPossiblePrivatePath([gFileMgr currentDirectoryPath]) retain];
        if (  gUsername  ) {
            appendLog([NSString stringWithFormat: @"Determined username '%@' from current working directory", gUsername]);
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
                appendLog([NSString stringWithFormat: @"Determined username '%@' from a path provided as an argument", gUsername]);
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
                appendLog(@"Unable to determine user. Some operations cannot be performed");
            }
        }
    }
}

//**************************************************************************************************************************
// LAUNCHDAEMON

static BOOL isLaunchDaemonLoaded(void) {
	
	// Must have uid=0 (not merely euid=0) for runTool(launchctl) to work properly
    if (  setuid(0)  ) {
		appendLog([NSString stringWithFormat: @"setuid(0) failed; error was %d: '%s'", errno, strerror(errno)]);
		errorExit();
	}
	if (  setgid(0)  ) {
		appendLog([NSString stringWithFormat: @"setgid(0) failed; error was %d: '%s'", errno, strerror(errno)]);
		errorExit();
	}
 	
	if (  ! [gFileMgr fileExistsAtPath: TUNNELBLICKD_PLIST_PATH]  ) {
		appendLog([NSString stringWithFormat: @"No file at %@; assuming tunnelblickd is not loaded", TUNNELBLICKD_PLIST_PATH]);
		return NO;
	}
	
	NSString * stdoutString = @"";
	NSString * stderrString = @"";
	NSArray * arguments = [NSArray arrayWithObject: @"list"];
	OSStatus status = runTool(TOOL_PATH_FOR_LAUNCHCTL, arguments, &stdoutString, &stderrString);
	if (   (status != EXIT_SUCCESS)
		|| [stdoutString isEqualToString: @""]  ) {
        
        appendLog([NSString stringWithFormat: @"'%@ list' failed or had no output; assuming tunnelblickd is not loaded; error was %d: '%s'\nstdout = '%@'\nstderr='%@'",
                   TOOL_PATH_FOR_LAUNCHCTL, errno, strerror(errno), stdoutString, stderrString]);
		return NO;
	}
	
	BOOL result = ([stdoutString rangeOfString: @"net.tunnelblick.tunnelblick.tunnelblickd"].length != 0);
	return result;
}

static void loadLaunchDaemonUsingLaunchctl(void) {
	
	// Must have uid=0 (not merely euid=0) for runTool(launchctl) to work properly
    if (  setuid(0)  ) {
		appendLog([NSString stringWithFormat: @"setuid(0) failed; error was %d: '%s'", errno, strerror(errno)]);
		errorExit();
	}
	if (  setgid(0)  ) {
		appendLog([NSString stringWithFormat: @"setgid(0) failed; error was %d: '%s'", errno, strerror(errno)]);
		errorExit();
	}
 	
	NSString * stdoutString = @"";
	NSString * stderrString = @"";
	
	if (  [gFileMgr fileExistsAtPath: TUNNELBLICKD_PLIST_PATH]  ) {
		NSArray * arguments = [NSArray arrayWithObjects: @"unload", TUNNELBLICKD_PLIST_PATH, nil];
		OSStatus status = runTool(TOOL_PATH_FOR_LAUNCHCTL, arguments, &stdoutString, &stderrString);
		if (  status != EXIT_SUCCESS  ) {
			appendLog([NSString stringWithFormat: @"'%@ unload' failed; error was %d: '%s'\nstdout = '%@'\nstderr='%@'",
                       TOOL_PATH_FOR_LAUNCHCTL, errno, strerror(errno), stdoutString, stderrString]);
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
		appendLog(@"Used launchctl to load tunnelblickd");
	} else {
		appendLog([NSString stringWithFormat: @"'%@ load -w %@' failed; status = %d; errno = %d: '%s'\nstdout = '%@'\nstderr='%@'",
                   TOOL_PATH_FOR_LAUNCHCTL, TUNNELBLICKD_PLIST_PATH, status, errno, strerror(errno), stdoutString, stderrString]);
		errorExit();
	}
}

static void loadLaunchDaemonAndSaveHashes (NSDictionary * newPlistContents) {
	
    (void) newPlistContents;  // Can remove this if the above lines are un-commmented
    loadLaunchDaemonUsingLaunchctl();
    //	    }
    
    // Store the hash of the .plist and the daemon in files owned by root:wheel
    NSDictionary * hashFileAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                         [NSNumber numberWithUnsignedLong: 0],               NSFileOwnerAccountID,
                                         [NSNumber numberWithUnsignedLong: 0],               NSFileGroupOwnerAccountID,
                                         [NSNumber numberWithShort: PERMS_SECURED_READABLE], NSFilePosixPermissions,
                                         nil];
    
    NSData * plistData = [gFileMgr contentsAtPath: TUNNELBLICKD_PLIST_PATH];
    if (  ! plistData  ) {
        appendLog([NSString stringWithFormat: @"Could not find tunnelblickd launchd .plist at '%@'", TUNNELBLICKD_PLIST_PATH]);
        errorExit();
    }
    NSString * plistHash = sha256HexStringForData(plistData);
    NSData * plistHashData = [NSData dataWithBytes: [plistHash UTF8String] length: [plistHash length]];
    if (  ! [gFileMgr createFileAtPath: L_AS_T_TUNNELBLICKD_LAUNCHCTL_PLIST_HASH_PATH contents: plistHashData attributes: hashFileAttributes]  ) {
        appendLog(@"Could not store tunnelblickd launchd .plist hash");
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
        appendLog([NSString stringWithFormat: @"Could not find tunnelblickd at '%@'", tunnelblickdPath]);
        errorExit();
    }
    NSString * daemonHash = sha256HexStringForData(daemonData);
    NSData * daemonHashData = [NSData dataWithBytes: [daemonHash UTF8String] length: [daemonHash length]];
    if (  ! [gFileMgr createFileAtPath: L_AS_T_TUNNELBLICKD_HASH_PATH contents: daemonHashData attributes: hashFileAttributes]  ) {
        appendLog(@"Could not store tunnelblickd hash");
        errorExit();
    }
}

static void setupLaunchDaemon(void) {

    // If we are reloading the LaunchDaemon, we make sure it is up-to-date by copying its .plist into /Library/LaunchDaemons

    // Install or replace the tunnelblickd .plist in /Library/LaunchDaemons
    BOOL hadExistingPlist = [gFileMgr fileExistsAtPath: TUNNELBLICKD_PLIST_PATH];
    NSDictionary * newPlistContents = tunnelblickdPlistDictionaryToUse();
    if (  ! newPlistContents  ) {
        appendLog(@"Unable to get a model for tunnelblickd.plist");
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
        appendLog([NSString stringWithFormat: @"%@ %@", (hadExistingPlist ? @"Replaced" : @"Installed"), TUNNELBLICKD_PLIST_PATH]);
    } else {
        appendLog([NSString stringWithFormat: @"Unable to create %@", TUNNELBLICKD_PLIST_PATH]);
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
            appendLog([NSString stringWithFormat: @"Kext is up-to-date: %@", finalNameOfKext]);
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
    appendLog([NSString stringWithFormat: @"%@ %@ in %@", verb, finalNameOfKext, [finalPath stringByDeletingLastPathComponent]]);

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
        appendLog([NSString stringWithFormat: @"utimes(\"/Library/Extensions\", NULL) failed with error %d ('%s')", errno, strerror(errno)]);
        errorExit();
    }
}

static BOOL uninstallOneKext(NSString * path) {
    
    if (  ! [gFileMgr fileExistsAtPath: path]  ) {
        return NO;
    }
    
    securelyDeleteItem(path);

    appendLog([NSString stringWithFormat: @"Uninstalled %@", [path lastPathComponent]]);

    return YES;
}

static void uninstallKexts(void) {
    
    BOOL shouldUpdateKextCaches = uninstallOneKext(@"/Library/Extensions/tunnelblick-tun.kext");
    
    shouldUpdateKextCaches = uninstallOneKext(@"/Library/Extensions/tunnelblick-tap.kext") || shouldUpdateKextCaches;

    if (  shouldUpdateKextCaches  ) {
        updateTheKextCaches();
    } else {
        appendLog(@"There are no kexts to uninstall");
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
        appendLog(@"Tun or tap kext not found");
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

static void createAndSecureConfigurationsSubfolder(NSString * path) {

    // Use to create and secure an empty configurations subfolder (either Shared or a private folder). If it is
    // a private folder, the secured copy is also created.
    //
    // A Shared or secured folder is owned by root; a private folder is owned by the user.

    uid_t  own   = 0;
    gid_t  grp   = 0;
    mode_t perms = PERMS_SECURED_FOLDER;

    BOOL private = isPathPrivate(path);
    if (  private  ) {
        own   = userUID();
        grp   = userGID();
        perms = privateFolderPermissions(path);
    }
    errorExitIfAnySymlinkInPath(path);

    if (  ! createDirWithPermissionAndOwnership(path, perms, own, grp)  ) {
        errorExit();
    }

    // If a private folder, create the secure copy, too.
    if (  private  ) {
        NSString * lastPart = lastPartOfPath(path);
        createAndSecureConfigurationsSubfolder([[L_AS_T_USERS
                                                 stringByAppendingPathComponent: userUsername()]
                                                stringByAppendingPathComponent: lastPart]);
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
	
	if (  ! createDirWithPermissionAndOwnership(L_AS_T_TBLKS,
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
	
	if (  [gFileMgr fileExistsAtPath: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH]  ) {
		errorExitIfAnySymlinkInPath(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);
		if (   ( ! checkSetOwnership(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH, NO, 0, 0))
			|| ( ! checkSetPermissions(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH, PERMS_SECURED_READABLE, NO))  ) {
			errorExit();
		}
	}
	
	if (  [gFileMgr fileExistsAtPath: L_AS_T_OPENVPN]  ) {
		secureOpenvpnBinariesFolder(L_AS_T_OPENVPN);
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
	NSString * targetPath  = @"/Applications/Tunnelblick.app";

    errorExitIfAnySymlinkInPath(targetPath);

	if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		if (  [[NSWorkspace sharedWorkspace] performFileOperation: NSWorkspaceRecycleOperation
														   source: @"/Applications"
													  destination: @""
															files: [NSArray arrayWithObject: @"Tunnelblick.app"]
															  tag: nil]  ) {
#pragma clang diagnostic pop
			appendLog([NSString stringWithFormat: @"Moved %@ to the Trash", targetPath]);
		} else {
			appendLog([NSString stringWithFormat: @"Unable to move %@ to the Trash", targetPath]);
			errorExit();
		}
	}

    if (  ! [gFileMgr tbCopyPath: sourcePath toPath: targetPath handler: nil]  ) {
        appendLog([NSString stringWithFormat: @"Unable to copy %@ to %@", sourcePath, targetPath]);
        errorExit();
    } else {
        appendLog([NSString stringWithFormat: @"Copied %@ to %@", sourcePath, targetPath]);
    }
}

static void secureTheApp(NSString * appResourcesPath) {
	
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
	while (  (file = [dirEnum nextObject])  ) {
		NSString * fullPath = [tunnelblickPath stringByAppendingPathComponent: file];
		if (   [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
			&& isDir  ) {
			okSoFar = checkSetPermissions(fullPath, PERMS_SECURED_FOLDER, YES) && okSoFar;
		} else {
			NSDictionary * atts = [[NSFileManager defaultManager] tbFileAttributesAtPath: fullPath traverseLink: NO];
			unsigned long  perms = [atts filePosixPermissions];
			// Nothing should be writable by group, writable by user, be suid, or be sgid
			unsigned long  permsShouldHave = (perms & ~(S_IWGRP | S_IWOTH | S_ISUID | S_ISGID));
			if (  (perms != permsShouldHave )  ) {
				if (  chmod(fileSystemRepresentationFromPath(fullPath), permsShouldHave) == 0  ) {
					appendLog([NSString stringWithFormat: @"Changed permissions from %lo to %lo on %@",
							   (long) perms, (long) permsShouldHave, fullPath]);
				} else {
					NSString * fileIsImmutable = (  [atts fileIsImmutable]
												  ? @"; file is immutable"
												  : @"" );

					appendLog([NSString stringWithFormat: @"Unable to change permissions (error %ld: '%s'%@) from %lo to %lo on %@",
							   (long)errno, strerror(errno), fileIsImmutable, (long) perms, (long) permsShouldHave, fullPath]);
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
		appendLog([NSString stringWithFormat: @"Missing IconSets folder, which should be at %@", iconSetsPath]);
		errorExit();
	}
	
	// Secure the app's Deploy folder
	if (   [gFileMgr fileExistsAtPath: gDeployPath isDirectory: &isDir]
		&& isDir  ) {
		okSoFar = okSoFar && secureOneFolder(gDeployPath, NO, 0);
	}
	
	okSoFar = checkSetPermissions(tunnelblickHelperPath, PERMS_SECURED_EXECUTABLE, YES) && okSoFar;
	
    NSString * appPath = [[appResourcesPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    removeQuarantineBit(appPath);

	if (  ! okSoFar  ) {
		appendLog(@"Unable to secure Tunnelblick.app");
		errorExit();
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
					appendLog([NSString stringWithFormat: @"Created shadow copy of %@", privateTblkPath]);
				} else {
					appendLog([NSString stringWithFormat: @"Unable to create shadow copy of %@", privateTblkPath]);
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
		appendLog([NSString stringWithFormat: @"Warning: Unable to secure all .tblk packages"]);
	}
}

static void installForcedPreferences(NSString * firstPath, NSString * secondPath) {

	if (  secondPath  ) {
		appendLog(@"Operation is INSTALLER_INSTALL_FORCED_PREFERENCES but secondPath is set");
		errorExit();
	}
	
	if (  [firstPath hasSuffix: @".plist"]  ) {
		// Make sure the .plist is valid
		NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: firstPath];
		if (  ! dict  ) {
			appendLog([NSString stringWithFormat: @"Not a valid .plist: %@", firstPath]);
			errorExit();
		}
		
		if (  [gFileMgr fileExistsAtPath: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH]  ) {
			errorExitIfAnySymlinkInPath(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);
			makeUnlockedAtPath(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);
            securelyDeleteItem(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH);
		} else {
			errorExitIfAnySymlinkInPath([L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH stringByDeletingLastPathComponent]);
		}
		
		if (  [gFileMgr tbCopyPath: firstPath toPath: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH handler: nil]  ) {
			appendLog([NSString stringWithFormat: @"copied %@\n    to %@", firstPath, L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH]);
			if (  checkSetOwnership(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH, NO, 0, 0)  )  {
				if (  ! checkSetPermissions(L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH, PERMS_SECURED_READABLE, YES)  )  {
					appendLog([NSString stringWithFormat: @"Unable to set permssions of %ld on %@", (long)PERMS_SECURED_READABLE, L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH]);
					errorExit();
				}
			} else {
				appendLog([NSString stringWithFormat: @"Unable to set ownership to root:wheel on %@", L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH]);
				errorExit();
			}
		} else {
			appendLog([NSString stringWithFormat: @"unable to copy %@ to %@", firstPath, L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH]);
			errorExit();
		}
	} else {
		appendLog([NSString stringWithFormat: @"Not a .plist: %@", firstPath]);
		errorExit();
	}
}

static void doFolderRename(NSString * sourcePath, NSString * targetPath) {

    // Renames the source folder to the target folder. Both folders need to be in the same folder.
    //
    // If the source folder is a private folder, the corresponding secure folder is also renamed if it exists.


    if (  ! [gFileMgr fileExistsAtPath: sourcePath]  ) {
        appendLog([NSString stringWithFormat: @"rename source does not exist: %@ to %@", sourcePath, targetPath]);
        errorExit();
    }
    if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
        appendLog([NSString stringWithFormat: @"rename target exists: %@ to %@", sourcePath, targetPath]);
        errorExit();
    }
    securelyRename(sourcePath, targetPath);
    appendLog([NSString stringWithFormat: @"Renamed %@ to %@", sourcePath, targetPath]);

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
                appendLog([NSString stringWithFormat: @"rename target exists: %@ to %@", secureSourcePath, secureTargetPath]);
                errorExit();
            }
            securelyRename(secureSourcePath, secureTargetPath);
            appendLog([NSString stringWithFormat: @"Renamed %@ to %@", secureSourcePath, secureTargetPath]);
        }
    }
}

static void copyOrMoveOneTblk(NSString * firstPath, NSString * secondPath, BOOL moveNotCopy) {
	
	if (   ( ! firstPath )
		|| ( ! secondPath )  ){
		appendLog(@"Operation is INSTALLER_COPY or INSTALLER_MOVE but firstPath and/or secondPath are not set");
		errorExit();
	}
	
	NSString * sourcePath = [[secondPath copy] autorelease];
	NSString * targetPath = [[firstPath  copy] autorelease];

    // An empty source path means create a folder at the target path.
    if (  [sourcePath isEqualToString: @""]  ) {
        if (  [targetPath hasSuffix: @".tblk"]  ) {
            appendLog([NSString stringWithFormat: @"When source is '', target cannot be a .tblk: %@", targetPath]);
            errorExit();
        }

        if (  [gFileMgr fileExistsAtPath: secondPath]  ) {
            appendLog([NSString stringWithFormat: @"When source is '', target cannot exist: %@", targetPath]);
            errorExit();
        }

        createAndSecureConfigurationsSubfolder(targetPath);
        return;
    }

    BOOL sourceIsTblk = [[sourcePath pathExtension] isEqualToString: @"tblk"];
    BOOL targetIsTblk = [[targetPath pathExtension] isEqualToString: @"tblk"];

	// Make sure we are dealing with two .tblks or two non-tblks
	if (   (   sourceIsTblk
            && ( ! targetIsTblk ))
        || (   targetIsTblk
            && ( ! sourceIsTblk ) )  ) {
		appendLog([NSString stringWithFormat: @"Only two .tblks or two folders may be copied or moved: %@ to %@", sourcePath, targetPath]);
		errorExit();
	}

    if (  ! sourceIsTblk  ) { // And, by the above, the target is not a .tblk either
        if (  ! moveNotCopy  ) {
            appendLog([NSString stringWithFormat: @"Can only move, not **copy**, a folder: %@ to %@", sourcePath, targetPath]);
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
            appendLog([NSString stringWithFormat: @"Source does not exist or target does exist for copy or move: %@ to %@", sourcePath, targetPath]);
            errorExit();
        }
    }

	// Create the enclosing folder(s) if necessary. Owned by root unless if in userPrivatePath(), in which case it is owned by the user
	NSString * enclosingFolder = [targetPath stringByDeletingLastPathComponent];
    createAndSecureConfigurationsSubfolder(enclosingFolder);

	// Make sure we can delete the original if we are moving instead of copying
	if (  moveNotCopy  ) {
		if (  ! makeUnlockedAtPath(targetPath)  ) {
			errorExit();
		}
	}
	
	// Resolve symlinks
	// Do the move or copy
	// Restructure the target if necessary
	// Secure the target
	//
	// If   we MOVED OR COPIED TO PRIVATE
	// Then create a shadow copy of the target and secure the shadow copy
	//
	// If   we MOVED FROM PRIVATE
	// Then delete the shadow copy of the target
	
	resolveSymlinksInPath(sourcePath);
	
    if (  moveNotCopy  ) {
        securelyMove(sourcePath, targetPath);
    } else {
        securelyCopy(sourcePath, targetPath);
    }

    structureTblkProperly(targetPath);

    BOOL targetIsPrivate = isPathPrivate(targetPath);
	uid_t uid = (  targetIsPrivate
				 ? userUID()
				 : 0);
	secureOneFolder(targetPath, targetIsPrivate, uid);

	NSString * lastPartOfTarget = lastPartOfPath(targetPath);
	
	if (   targetIsPrivate  ) {
		
		NSString * shadowTargetPath   = [NSString stringWithFormat: @"%@/%@/%@",
										 L_AS_T_USERS,
										 userUsername(),
										 lastPartOfTarget];
		
		errorExitIfAnySymlinkInPath(shadowTargetPath);
		
		if (  [gFileMgr fileExistsAtPath: shadowTargetPath]  ) {
            securelyDeleteItem(shadowTargetPath);
		}
		
		// Create container for shadow copy
		enclosingFolder = [shadowTargetPath stringByDeletingLastPathComponent];
		BOOL isDir;
		if (   ( ! [gFileMgr fileExistsAtPath: shadowTargetPath isDirectory: &isDir])
			&& isDir  ) {
			errorExitIfAnySymlinkInPath(enclosingFolder);
			createDirWithPermissionAndOwnership(enclosingFolder, PERMS_SECURED_FOLDER, 0, 0);
		}
		
		securelyCopy(targetPath, shadowTargetPath);	// Copy the target because the source may have _moved_ to the target
		
		secureOneFolder(shadowTargetPath, NO, 0);
	}
	
	if (  isPathPrivate(sourcePath)  ) {
		if (  moveNotCopy  ) {
			NSString * lastPartOfSource = lastPartOfPath(sourcePath);
			NSString * shadowSourcePath   = [NSString stringWithFormat: @"%@/%@/%@",
											 L_AS_T_USERS,
											 userUsername(),
											 lastPartOfSource];
			if (  [gFileMgr fileExistsAtPath: shadowSourcePath]  ) {
                securelyDeleteItem(shadowSourcePath);
			}
		}
	}
}

static void deleteOneTblk(NSString * firstPath, NSString * secondPath) {
	
	if (  ! firstPath) {
		appendLog(@"Operation is INSTALLER_DELETE but firstPath is not set");
		errorExit();
	}
	
	if (  secondPath  ) {
		appendLog(@"Operation is INSTALLER_DELETE but secondPath is set");
		errorExit();
	}

    if (  [firstPath hasPrefix: L_AS_T_USERS]  ) {
        appendLog([NSString stringWithFormat: @"Did not delete %@.\nTo delete a shadow copy, delete the user's copy; the shadow copy will be deleted automatically.", firstPath]);
        errorExit();
    }

	if (  [gFileMgr fileExistsAtPath: firstPath]  ) {
		errorExitIfAnySymlinkInPath(firstPath);
		makeUnlockedAtPath(firstPath);
        securelyDeleteItem(firstPath);
		appendLog([NSString stringWithFormat: @"removed %@", firstPath]);

		// Delete shadow copy, too, if it exists
		if (  isPathPrivate(firstPath)  ) {
			NSString * shadowCopyPath = [NSString stringWithFormat: @"%@/%@/%@",
										 L_AS_T_USERS,
										 userUsername(),
										 lastPartOfPath(firstPath)];
			if (  [gFileMgr fileExistsAtPath: shadowCopyPath]  ) {
				errorExitIfAnySymlinkInPath(shadowCopyPath);
				makeUnlockedAtPath(shadowCopyPath);
                securelyDeleteItem(shadowCopyPath);
				appendLog([NSString stringWithFormat: @"removed %@", shadowCopyPath]);
			}
		}
    } else {
        appendLog([NSString stringWithFormat: @"No file to delete at %@", firstPath]);
        gErrorOccurred = TRUE;
	}
}

static BOOL installerUpdateTunnelblick(NSString * updateSignature, NSString * versionAndBuildString, NSString * username, uid_t uid, gid_t gid, pid_t tunnelblickPid) {

    NSString * zipPath = [[[@"/Users/"
                            stringByAppendingPathComponent: username]
                           stringByAppendingPathComponent: L_AS_T]
                          stringByAppendingPathComponent: @"tunnelblick-update.zip"];

    return updateTunnelblick(zipPath, updateSignature, versionAndBuildString, uid, gid, tunnelblickPid);
}

//**************************************************************************************************************************
// EXPORT SETUP

static void createExportFolder(NSString * path) {
	
	if (  ! createDirWithPermissionAndOwnership(path, privateFolderPermissions(path), 0, 0)  ) {
		appendLog([NSString stringWithFormat: @"Error creating folder %@", path]);
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
			appendLog([NSString stringWithFormat: @"Removed folder because it was empty: %@", pruneCandidatePath]);
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
	NSString * tempFolderPath = newTemporaryDirectoryPath();
	
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
		appendLog([NSString stringWithFormat: @"writeToFile failed for %@", targetTBInfoPlistPath]);
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
					   : @"Copied to");
    securelyCopy(sourcePath, targetPath);
    if ( ! checkSetOwnership(targetPath, YES, newUid, newGid)  ) {
        errorExit();
    }
    
	appendLog([NSString stringWithFormat: @"%@ and set ownership to %@: %@", verb, formattedUserGroup(newUid, newGid), targetPath]);
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
                    appendLog([NSString stringWithFormat: @"Failed: secureOneFolder('%@', %s, %d)",
                               targetFullPath, CSTRING_FROM_BOOL(isPrivate), uid]);
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
				appendLog([NSString stringWithFormat: @"Expected username %@ in .tblkSetup to be mapped to a user on this computer but it isn't", name]);
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
		appendLog([NSString stringWithFormat: @"TBInfo.plist is damaged at %@", tblkSetupPath]);
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
			appendLog([NSString stringWithFormat: @"Format error in name-pair %@", namePair]);
			errorExit();
		}
		NSString * sourceName = [names firstObject];
		NSString * targetName = [names lastObject];
		NSString * sourcePath = [[tblkSetupPath
								  stringByAppendingPathComponent: @"Users"]
								 stringByAppendingPathComponent: sourceName];
		NSString * targetPath = [@"/Users" stringByAppendingPathComponent: targetName];
		if (  ! [gFileMgr fileExistsAtPath: sourcePath]  ) {
			appendLog([NSString stringWithFormat: @"No data for username %@ exists in this .tblkSetup", targetName]);
			errorExit();
		}
		if (  ! [gFileMgr fileExistsAtPath: targetPath]  ) {
			appendLog([NSString stringWithFormat: @"No username %@ on this computer", targetName]);
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
			appendLog([NSString stringWithFormat: @"Created and set ownership to   %@: %@", formattedUserGroup(0, 0), importInfoFilePath]);
		} else {
			appendLog([NSString stringWithFormat: @"Could not create %@", importInfoFilePath]);
			errorExit();
		}
	} else {
		appendLog([NSString stringWithFormat: @"File already exists:               %@", importInfoFilePath]);
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
			appendLog([NSString stringWithFormat: @"Error: could not read %@ (or create NSDictionary)", targetPath]);
			errorExit();
		}
		
		NSDictionary * preferencesToMerge = [NSDictionary dictionaryWithContentsOfFile: sourcePath];
		if (  ! preferencesToMerge  ) {
			appendLog([NSString stringWithFormat: @"Error: could not read %@  ", sourcePath]);
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
					appendLog([NSString stringWithFormat: @"Changed forced preference %@ = %@ (was %@)", key, newValue, oldValue]);
				}
			} else {
				[existingPreferences setObject: newValue forKey: key];
				modifiedExistingPreferences = TRUE;
				appendLog([NSString stringWithFormat: @"Added   forced preference %@ = %@", key, newValue]);
			}
		}
		
		if (  modifiedExistingPreferences  ) {
            securelyDeleteItemIfItExists(targetPath);
			if (  ! [existingPreferences writeToFile: targetPath atomically: YES]  ) {
				appendLog([NSString stringWithFormat: @"Error: could not write %@  ", sourcePath]);
				errorExit();
			}
			
		} else {
			appendLog([NSString stringWithFormat: @"Do not need to create or modify             %@  ", targetPath]);
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
	
    gFileMgr = [NSFileManager defaultManager];
	
    setupLibrary_Application_Support_Tunnelblick();

    if (  argc < 2  ) {
		openLog(FALSE);
        appendLog(@"1 or more arguments are required");
        errorExit();
	}

    unsigned opsAndFlags = (unsigned) strtol(argv[1], NULL, 0);

    BOOL doClearLog = (opsAndFlags & INSTALLER_CLEAR_LOG) != 0;
    openLog(doClearLog);

    // Log the arguments installer was started with
    NSMutableString * logString = [NSMutableString stringWithFormat: @"Tunnelblick installer getuid() = %d; geteuid() = %d; getgid() = %d; getegid() = %d\ncurrentDirectoryPath = '%@'; %d arguments:\n",
                                   getuid(), geteuid(), getgid(), getegid(), [gFileMgr currentDirectoryPath], argc - 1];
    [logString appendFormat:@"     0x%04x", opsAndFlags];
    int i;
    for (  i=2; i<argc; i++  ) {
        [logString appendFormat: @"\n     %@", [NSString stringWithUTF8String: argv[i]]];
    }
    appendLog(logString);

    unsigned operation = (opsAndFlags & INSTALLER_OPERATION_MASK);

    // Set up booleans that describe what operations are to be done

    BOOL doCopyApp                = (opsAndFlags & INSTALLER_COPY_APP) != 0;
    BOOL doSecureApp              = (   doCopyApp
								     || ( (opsAndFlags & INSTALLER_SECURE_APP) != 0 )
                                     );
    BOOL doForceLoadLaunchDaemon  = (opsAndFlags & INSTALLER_REPLACE_DAEMON) != 0;
    BOOL doUninstallKexts         = (opsAndFlags & INSTALLER_UNINSTALL_KEXTS) != 0;
    BOOL doSecureTblks            = (opsAndFlags & INSTALLER_SECURE_TBLKS) != 0;

    // Uninstall kexts overrides install kexts
    BOOL doInstallKexts           = (   ( ! doUninstallKexts )
                                     && (opsAndFlags & INSTALLER_INSTALL_KEXTS)  );

	NSString * resourcesPath = thisAppResourcesPath(); // (installer itself is in Resources)
    NSArray  * execComponents = [resourcesPath pathComponents];
	if (  [execComponents count] < 3  ) {
        appendLog([NSString stringWithFormat: @"too few execComponents; resourcesPath = %@", resourcesPath]);
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
            errorExitIfAnySymlinkInPath(secondArg);
        }
    }
    NSString * thirdArg = nil;
    if (  argc > 3  ) {
        thirdArg = [gFileMgr stringWithFileSystemRepresentation: argv[3] length: strlen(argv[3])];
        if (   ( gPrivatePath == nil  )
            || ( ! [thirdArg hasPrefix: [gPrivatePath stringByAppendingString: @"/"]])  ) {
            errorExitIfAnySymlinkInPath(thirdArg);
        }
    }
    
    NSString * fourthArg = nil;
    if (  argc > 4  ) {
        fourthArg = [gFileMgr stringWithFileSystemRepresentation: argv[4] length: strlen(argv[4])];
        if (   ( gPrivatePath == nil  )
            || ( ! [fourthArg hasPrefix: [gPrivatePath stringByAppendingString: @"/"]])  ) {
            errorExitIfAnySymlinkInPath(fourthArg);
        }
    }

    NSString * fifthArg = nil;
    if (  argc > 5  ) {
        fifthArg = [gFileMgr stringWithFileSystemRepresentation: argv[5] length: strlen(argv[5])];
        if (   ( gPrivatePath == nil  )
            || ( ! [fifthArg hasPrefix: [gPrivatePath stringByAppendingString: @"/"]])  ) {
            errorExitIfAnySymlinkInPath(fifthArg);
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
        appendLog([NSString stringWithFormat: @"Wrote '%@' to %@", appResourcesPath, L_AS_T_DEBUG_APP_RESOURCES_PATH]);
    } else {
        appendLog([NSString stringWithFormat: @"Could not write %@", L_AS_T_DEBUG_APP_RESOURCES_PATH]);
        errorExit();
    }
    appendLog([NSString stringWithFormat: @"Wrote '%@' to %@", appResourcesPath, L_AS_T_DEBUG_APP_RESOURCES_PATH]);
#else
    // A non-debug version of Tunnelblick.app is always in /Applications by the time it starts using tunnelblickd.
    // A non-debug version of tunnelblickd can thus always find tunnelblick-helper in /Applications/Tunnelblick.app/Contents/Resources.
    if (  [gFileMgr fileExistsAtPath: L_AS_T_DEBUG_APP_RESOURCES_PATH]  ) {
        securelyDeleteItem(L_AS_T_DEBUG_APP_RESOURCES_PATH);
        appendLog([NSString stringWithFormat: @"Deleted %@", L_AS_T_DEBUG_APP_RESOURCES_PATH]);
    }
#endif

    //**************************************************************************************************************************
    // (2) If INSTALLER_COPY_APP is set:
    //     Then move /Applications/XXXXX.app to the Trash, then copy this app to /Applications/XXXXX.app
    
    if (  doCopyApp  ) {
        // Don't copy the app to /Applications if it's already there.
        // But secure it and do everything else as if it had been copied.
        NSString * appPath = [[resourcesPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        if (  ! [appPath isEqualToString: @"/Applications/Tunnelblick.app"]  ) {
            copyTheApp();
        }
    }
    
	//**************************************************************************************************************************
	// (3) If requested, secure Tunnelblick.app by setting the ownership and permissions of it and all its components

    if ( doSecureApp ) {
		secureTheApp(appResourcesPath);
    }
    
    //**************************************************************************************************************************
    // (4) If INSTALLER_COPY_APP, L_AS_T_TBLKS is pruned by removing all but the highest edition of each container

    if (  doCopyApp  ) {
        pruneL_AS_T_TBLKS();
    }
    
    //**************************************************************************************************************************
    // (5) If requested, secure all .tblk packages

    if (  doSecureTblks  ) {
		secureAllTblks();
    }
    
    //**************************************************************************************************************************
    // (6) Install the .plist at secondArg to L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH
    
    if (  operation == INSTALLER_INSTALL_FORCED_PREFERENCES  ) {
		installForcedPreferences(secondArg, thirdArg);
    }
    
    //**************************************************************************************************************************
    // (7) If requested, install a configuration.
    // Copy or move a single .tblk package (without any nested .tblks).
    // Also moves/coies/creates a shadow copy if a private configuration.
    // Like the NSFileManager "movePath:toPath:handler" method, we move by copying, then deleting.

    if (   secondArg
        && (argc < 6)  ) {
        if (   (   (operation == INSTALLER_COPY )
                || (operation == INSTALLER_MOVE)
                )
            && thirdArg  ) {

            copyOrMoveOneTblk(secondArg, thirdArg, (operation == INSTALLER_MOVE));

        } else if (   (operation == INSTALLER_INSTALL_PRIVATE_CONFIG)
                   && thirdArg  ) {
            if (  argc < 4  ) {
                appendLog(@"installing a private configuration requires a username and a path");
                errorExit();
            }
            NSString * targetPath = userPrivatePath();

            if (  fourthArg  ) {
                targetPath = [targetPath stringByAppendingPathComponent: fourthArg];
                securelyCreateFolderAndParents(targetPath);
            }

            targetPath = [targetPath stringByAppendingPathComponent: [thirdArg lastPathComponent]];

            copyOrMoveOneTblk(targetPath, thirdArg, false);

        } else if (  operation == INSTALLER_INSTALL_SHARED_CONFIG  ) {

            if (  argc < 3  ) {
                appendLog(@"installing a shared configuration requires a path");
                errorExit();
            }

            if (  argc > 4  ) {
                appendLog(@"installing a shared configuration takes at most three arguments");
                errorExit();
            }

            NSString * targetPath;

            if (  thirdArg  ) {
                targetPath = [L_AS_T_SHARED stringByAppendingPathComponent: thirdArg];
                securelyCreateFolderAndParents(targetPath);
            } else {
                targetPath = L_AS_T_SHARED;
            }

            targetPath = [targetPath stringByAppendingPathComponent: [secondArg lastPathComponent]];

            copyOrMoveOneTblk(targetPath, secondArg, false);
        }

    }
    
    //**************************************************************************************************************************
    // (8)
    // If requested, delete a single file or .tblk package (also deletes the shadow copy if deleting a private configuration)
	
    if (  operation == INSTALLER_DELETE  ) {
		deleteOneTblk(secondArg, thirdArg);
    }
    
    //**************************************************************************************************************************
    // (9) Set up tunnelblickd to load when the computer starts
	
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
	// (10) If requested, exports all settings and configurations for all users to a file at targetPath, deleting the file if it already exists

	if (   secondArg
		&& ( ! thirdArg   )
		&& (  operation == INSTALLER_EXPORT_ALL)  ) {
		exportToPath(secondArg);
	}
	
	//**************************************************************************************************************************
	// (11) If requested, import settings from the .tblkSetup at secondArg using username mapping in the string in "thirdArg"
	//
	//		NOTE: "thirdArg" is a string that specifies the username mapping to use when importing.

	if (   (operation == INSTALLER_IMPORT)
		&& secondArg
		&& thirdArg  ) {
		importSetup(secondArg, thirdArg);
	}
	
    //**************************************************************************************************************************
    // (12) If requested, uninstall, install kexts, otherwise update them if they are installed

    if (   doUninstallKexts  ) {
        uninstallKexts();
    } else if (   doInstallKexts  ) {
        installOrUpdateKexts(YES);
    } else {
        installOrUpdateKexts(NO);
    }
    
    //**************************************************************************************************************************
    // (13) If requested, update Tunnelblick
    //

    if (  operation == INSTALLER_UPDATE_TUNNELBLICK  ) {
        if (   secondArg
            && thirdArg
            && fourthArg
            && fifthArg) {

            pid_t tunnelblickPid = [fifthArg intValue];
            if (  tunnelblickPid == 0  ) {
                appendLog(@"Tunnelblick PID cannot be zero for operation INSTALLER_UPDATE_TUNNELBLICK");
                appendLog(@"Tunnelblick installer finished with errors;");
                gErrorOccurred = TRUE;
            } else if (  ! installerUpdateTunnelblick(secondArg, thirdArg, fourthArg, userUID(), userGID(), tunnelblickPid)  ) {
                gErrorOccurred = TRUE;
            }
        } else {
            appendLog(@"Missing argument(s); cannot perform INSTALLER_UPDATE_TUNNELBLICK");
            gErrorOccurred = TRUE;
        }
    }

    //**************************************************************************************************************************
    // DONE

    if (  gErrorOccurred  ) {
        appendLog(@"Tunnelblick installer finished with errors");
        storeAuthorizedDoneFileAndExit(EXIT_FAILURE);
    }

    appendLog(@"Tunnelblick installer succeeded");
    storeAuthorizedDoneFileAndExit(EXIT_SUCCESS);
}
