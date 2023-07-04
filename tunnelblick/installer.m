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
//
//      (2) (REMOVED)
//      (3) (REMOVED)
//      (4) If INSTALLER_COPY_APP is set, this app is copied to /Applications, discarding all xattrs including the quarantine bit
//      (5) If INSTALLER_SECURE_APP is set, secures Tunnelblick.app by setting the ownership and permissions of its components.
//      (6) If INSTALLER_COPY_APP is set, L_AS_T_TBLKS is pruned by removing all but the highest edition of each container
//      (7) If INSTALLER_SECURE_TBLKS is set, then secures all .tblk packages in the following folders:
//				/Library/Application Support/Tunnelblick/Shared
//				~/Library/Application Support/Tunnelblick/Configurations
//				/Library/Application Support/Tunnelblick/Users/<username>
//
//      (8) if the operation is INSTALLER_INSTALL_FORCED_PREFERENCES and targetPath is given and is a .plist and there is no secondPath
//             installs the .plist at targetPath in L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH
//
//      (9) If the operation is INSTALLER_COPY or INSTALLER_MOVE and both targetPath and sourcePath are given,
//             copies or moves sourcePath to targetPath. Copies unless INSTALLER_MOVE is set.  (Also copies or moves the shadow copy if deleting a private configuration)
//
//     (10) If the operation is INSTALLER_DELETE and only targetPath is given,
//             deletes the .ovpn or .conf file or .tblk package at targetPath (also deletes the shadow copy if deleting a private configuration)
//
//     (11) If not installing a configuration, sets up tunnelblickd
//
//	   (12) If requested, exports all settings and configurations for all users to a file at targetPath, deleting the file if it already exists
//
//	   (13) If requested, import settings from the .tblkSetup at targetPath
//
//     (14) If requested, install or uninstall kexts

// When finished (or if an error occurs), the file at AUTHORIZED_DONE_PATH is written to indicate the program has finished

// The following globals are not modified after they are initialized:
FILE          * gLogFile;					  // FILE for log
NSFileManager * gFileMgr;                     // [NSFileManager defaultManager]
NSString      * gDeployPath;                  // Path to Tunnelblick.app/Contents/Resources/Deploy

// The following variables contain info about the user. They may be zero or nil if not needed.
// If invoked by Tunnelblick, they will be set up using the uid from getuid().
// If invoked by sudo or similar (which has getuid() == 0):
//    * If this is the 'install private config' operation, they will be set up using the provided username.
//    * If one of the arguments to installer is a path in the user's home folder or a subfolder, they will
//      be set up for that user.
//    * Otherwise, they will be set to zero or nil.
uid_t           gUserID = 0;
gid_t           gGroupID = 0;
NSString      * gUsername = nil;
NSString      * gPrivatePath = nil;                 // ~/Library/Application Support/Tunnelblick/Configurations
NSString      * gHomeDirectory = nil;

NSAutoreleasePool * pool;

BOOL            gErrorOccurred = FALSE;       // Set if an error occurred

//**************************************************************************************************************************

// LOGGING AND ERROR HANDLING

void errorExit(void);

void errorExitIfAnySymlinkInPath(NSString * path);

void debugLog(NSString * string) {
	
	// Call this function to create files in /tmp to show progress through this program
	// when there are problems that cause the log not to be available
	// For example, if this installer hangs.
	//
	// "string" is a string identifier indicating where debugLog was called from.
#ifdef TBDebug
	static unsigned int debugLogMessageCounter = 0;
	
	NSString * path = [NSString stringWithFormat: @"/tmp/0-%u-tunnelblick-installer-%@.txt", ++debugLogMessageCounter, string];
	[gFileMgr createFileAtPath: path contents: [NSData data] attributes: nil];
#else
    (void)string;
#endif
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

void errorExit() {

#ifdef TBDebug
    appendLog([NSString stringWithFormat: @"errorExit(): Stack trace: %@", callStack()]);
#else
    appendLog(@"Tunnelblick installer failed");
#endif

    storeAuthorizedDoneFileAndExit(EXIT_FAILURE);
    exit(EXIT_FAILURE); // Never executed but needed to make static analyzer happy
}

void errorExitIfPathIsNotSecure(NSString * targetPath) {

    // Exits if the path or any of its parent folders:
    //          * does not exist; or
    //          * is not a regular file or a directory; or
    //          * has multiple hard links; or
    //          * is not owned by the root:wheel (or root:admin for the /Applications folder);
    //          * is writable by group or other.

    NSError * error;

    NSDictionary * attributes = [gFileMgr attributesOfItemAtPath: targetPath error: &error];
    if (  ! attributes  ) {
        appendLog([NSString stringWithFormat: @"Path is not secure (error %@ getting attributes) %@", [error description], targetPath]);
        errorExit();
    }

    // Everything except the /Applications folder must have owner group wheel
    unsigned long requiredGroup  = (  [targetPath isEqualToString: @"/Applications"]
                                    ? ADMIN_GROUP_ID
                                    : 0);

    // Regular files must have a reference count of 0 (i.e., have no hard links)
    // Directories must have a reference count of 2 (i.e., no extra hard links)
    unsigned long requiredRefCount;
    NSFileAttributeKey fileType = (NSFileAttributeKey)[attributes objectForKey: NSFileType];
    if (  [fileType isEqual: NSFileTypeRegular]) {
        requiredRefCount = 1;
    } else if (  [fileType isEqual: NSFileTypeDirectory]) {
        requiredRefCount = 2;
    } else {
        appendLog([NSString stringWithFormat: @"Path is not secure (not a directory of regular file) %@", targetPath]);
        errorExit();
    }

    unsigned long owner  = [[attributes objectForKey: NSFileOwnerAccountID] unsignedLongValue];
    unsigned long group  = [[attributes objectForKey: NSFileGroupOwnerAccountID] unsignedLongValue];
    unsigned long refCnt = [[attributes objectForKey: NSFileReferenceCount] unsignedLongValue] ;
    short permissions    = [[attributes objectForKey: NSFilePosixPermissions] shortValue];

    if (   (owner != 0)
        || (group != requiredGroup)
        || ((permissions & (S_IWGRP | S_IWOTH)) != 0)
        || (refCnt != requiredRefCount)
        ) {
            appendLog([NSString stringWithFormat: @"Path is not secure - owned by %lu:%lu; permissions = 0%o; referenceCount = %lu (should be 0:%lu, not writable by group or other, %lu): %@",
                       owner, group, permissions, refCnt, requiredGroup, requiredRefCount, targetPath]);
            errorExit();
        }

    if (  targetPath.length != 1  ) {
        NSString * parentPath = [targetPath stringByDeletingLastPathComponent];
        if (  ! parentPath  ) {
            appendLog([NSString stringWithFormat: @"Path is not secure (could not get path to parent) %@", targetPath]);
            errorExit();
        }
        errorExitIfPathIsNotSecure(parentPath);
    }
}

void securelyDeleteItemAtPath(NSString * path) {

    const char * pathC = [path fileSystemRepresentation];

    if (  0 != unlink(pathC)  ) {
        appendLog([NSString stringWithFormat: @"unlink() failed with error %d ('%s') for path %@", errno, strerror(errno), path]);
        errorExit();
    }
}

// USER INFORMATION

NSString * userUsername(void) {

    if (  gUsername != nil  ) {
        return gUsername;
    }

    appendLog(@"Tried to access userUsername, which was not set");
    errorExit();
    return nil; // Satisfy analyzer
}

NSString * userHomeDirectory(void) {

    if (  gHomeDirectory != nil  ) {
        return gHomeDirectory;
    }

    appendLog(@"Tried to access userHomeDirectory, which was not set");
    errorExit();
    return nil; // Satisfy analyzer
}

NSString * userPrivatePath(void) {

    if (  gPrivatePath != nil  ) {
        return gPrivatePath;
    }

    appendLog(@"Tried to access userPrivatePath, which was not set");
    errorExit();
    return nil; // Satisfy analyzer
}

uid_t userUID(void) {

    if (  gUserID != 0  ) {
        return gUserID;
    }

    appendLog(@"Tried to access userUID, which was not set");
    errorExit();
    return 0; // Satisfy analyzer
}

gid_t userGID(void) {

    if (  gGroupID != 0  ) {
        return gGroupID;
    }

    appendLog(@"Tried to access userGID, which was not set");
    errorExit();
    return 0; // Satisfy analyzer
}

void getUidAndGidFromUsername(NSString * username, uid_t * uid_ptr, gid_t * gid_ptr) {

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

BOOL usernameIsValid(NSString * username) {

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

NSString * makePathAbsolute(NSString * path) {

    NSString * standardizedPath = [path stringByStandardizingPath];
    NSURL * url = [NSURL fileURLWithPath: standardizedPath];
    url = [url absoluteURL];
    const char * pathC = [url fileSystemRepresentation];
    NSString * absolutePath = [NSString stringWithCString: pathC encoding: NSUTF8StringEncoding];

    return absolutePath;
}

NSString * usernameFromPossiblePrivatePath(NSString * path) {

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

NSString * privatePathFromUsername(NSString * username) {

    NSString * privatePath = [[[[[@"/Users/"
                                  stringByAppendingPathComponent: username]
                                 stringByAppendingPathComponent: @"Library"]
                                stringByAppendingPathComponent: @"Application Support"]
                               stringByAppendingPathComponent: @"Tunnelblick"]
                              stringByAppendingPathComponent: @"Configurations"];
    return privatePath;
}

void setupUserGlobalsFromGUsername(void) {

    gHomeDirectory = [@"/Users" stringByAppendingPathComponent: gUsername];
    gPrivatePath = [[[[gHomeDirectory
                       stringByAppendingPathComponent: @"Library"]
                      stringByAppendingPathComponent: @"Application Support"]
                     stringByAppendingPathComponent: @"Tunnelblick"]
                    stringByAppendingPathComponent: @"Configurations"];

    getUidAndGidFromUsername(gUsername, &gUserID, &gGroupID);
    gGroupID = privateFolderGroup(gPrivatePath);
}

void setupUserGlobals(int argc, char *argv[], unsigned operation) {

    gUserID = getuid();

    if (  gUserID != 0  ) {
        //
        // Calculate user info from uid
        //
        // (Already have gUserID)
        gUsername = NSUserName();
        gHomeDirectory = NSHomeDirectory();
        gPrivatePath = [[[[gHomeDirectory
                           stringByAppendingPathComponent: @"Library"]
                          stringByAppendingPathComponent: @"Application Support"]
                         stringByAppendingPathComponent: @"Tunnelblick"]
                        stringByAppendingPathComponent: @"Configurations"];
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

        gUsername = [NSString stringWithCString: argv[2] encoding: NSASCIIStringEncoding];
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
        gUsername = usernameFromPossiblePrivatePath([gFileMgr currentDirectoryPath]);
        if (  gUsername  ) {
            appendLog([NSString stringWithFormat: @"Determined username '%@' from current working directory", gUsername]);
            setupUserGlobalsFromGUsername();

        } else {
            //
            // Calculate user info from a private path if one is provided as an argument
            //
            for (  int i=2; i<argc; i++  ) {
                NSString * path = [NSString stringWithCString: argv[i] encoding: NSUTF8StringEncoding];
                gUsername = usernameFromPossiblePrivatePath(path);
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

// MISC

NSString * thisAppResourcesPath(void) {

    NSString * resourcesPath = [NSProcessInfo.processInfo.arguments[0]  // .app/Contents/Resources/installer
                                stringByDeletingLastPathComponent];     // .app/Contents/Resources
    return resourcesPath;
}

BOOL isPathPrivate(NSString * path) {

    NSString * absolutePath = makePathAbsolute(path);

    BOOL isPrivate = (   [absolutePath hasPrefix: @"/Users/"]
                      && [absolutePath hasPrefix: [[userPrivatePath() stringByDeletingLastPathComponent] stringByAppendingString: @"/"]]
                      );
    return isPrivate;
}

void resolveSymlinksInPath(NSString * targetPath) {
	
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
			
			if (  ! [gFileMgr tbRemoveFileAtPath: fullPath handler: nil]  ) {
				appendLog([NSString stringWithFormat: @"Could not remove (before replacing): %@", fullPath]);
				errorExit();
			}
			
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

BOOL isLaunchDaemonLoaded(void) {
	
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

void loadLaunchDaemonUsingLaunchctl(void) {
	
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

void loadLaunchDaemonAndSaveHashes (NSDictionary * newPlistContents) {
	
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

void createFolder(NSString * path) {
	
	errorExitIfAnySymlinkInPath(path);
	
	if (  [gFileMgr fileExistsAtPath: path]  ) {
		return;
	}
	
	NSString * enclosingFolder = [path stringByDeletingLastPathComponent];
	if (  ! [gFileMgr fileExistsAtPath: enclosingFolder]  ) {
		createFolder(enclosingFolder);
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

BOOL deleteThingAtPath(NSString * path) {
	
	errorExitIfAnySymlinkInPath(path);
	makeUnlockedAtPath(path);
	if (  ! [gFileMgr tbRemoveFileAtPath: path handler: nil]  ) {
		return FALSE;
	} else {
		appendLog([NSString stringWithFormat: @"Deleted %@", path]);
	}
	
	return TRUE;
}

void securelyRename(NSString * sourcePath, NSString * targetPath) {

    if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
        securelyDeleteItemAtPath(targetPath);
    }

    if (  0 != renamex_np([sourcePath fileSystemRepresentation], [targetPath fileSystemRepresentation], (RENAME_NOFOLLOW_ANY | RENAME_EXCL))  ){
        appendLog([NSString stringWithFormat: @"renamex_np() failed with error %d ('%s') trying to rename %@ to %@",
                   errno, strerror(errno), sourcePath, targetPath]);
        errorExit();
    }
}

BOOL securelyCreateFileOrDirectoryEntry(BOOL isDir, NSString * targetPath) {

    // Create a file or a directory owned by root with 0700 permissions (permissions will be changed to the correct values later)

    if (  isDir  ) {
        umask(0077);
        int result = mkdir([targetPath fileSystemRepresentation], 0700);
        umask(S_IWGRP | S_IWOTH);
        if (  result != 0  ) {
            appendLog([NSString stringWithFormat: @"mkdir() returned error: '%s' for path %@", strerror(errno), targetPath]);
            return NO;
        }
    } else {
        int result = open([targetPath fileSystemRepresentation], (O_CREAT | O_EXCL | O_APPEND | O_NOFOLLOW_ANY), 0700);
        if (  result < 0  ) {
            appendLog([NSString stringWithFormat: @"open() returned error: '%s' for path %@", strerror(errno), targetPath]);
            return NO;
        }
        close(result); // Ignore errors
    }

    return YES;
}

BOOL securelySetItemAttributes(BOOL isDir, NSString * sourcePath, NSString * targetPath) {

    const char * sourcePathC = [sourcePath fileSystemRepresentation];
    const char * targetPathC = [targetPath fileSystemRepresentation];
    if (   (sourcePathC == NULL)
        || (targetPathC == NULL)  ) {
        appendLog([NSString stringWithFormat: @"Could not get fileSystemRepresentation for path %@ and/or path '%@", sourcePath, targetPath]);
        return NO;
    }

    // Open the item as READ-ONLY (we're not changing it now)
    int fd = open(targetPathC, (O_RDONLY | O_NOFOLLOW_ANY));
    if (  fd == -1  ) {
        appendLog([NSString stringWithFormat: @"Could not open %s", targetPathC]);
        return NO;
    }

    struct stat status;

    int result = fstat(fd, &status);
    if (   (result != 0)
        || (status.st_uid != 0)
        || (status.st_nlink != (isDir ? 2 : 1))
        || (status.st_mode  != (isDir ? S_IFDIR | 0700 : S_IFREG | 0700))  ) {
        appendLog([NSString stringWithFormat: @"Item has been modified after being created at path %@\nowner = %u; group = %u; nlink = %u; mode = 0%o",
                   targetPath, status.st_uid, status.st_gid, status.st_nlink, status.st_mode]);
        return NO;
    }

    // Change owner group (owner is already 0)
    result = fchown(fd, 0, 0);
    if (  result != 0  ) {
        appendLog([NSString stringWithFormat: @"lchown() returned error: '%s' for path %s", strerror(errno), targetPathC]);
        return NO;
    }

    // Change permissions
    NSDictionary * sourceAttributes = [gFileMgr tbFileAttributesAtPath: sourcePath traverseLink: NO];
    mode_t mode = [[sourceAttributes objectForKey: NSFilePosixPermissions] unsignedIntValue];
    result = fchmod(fd, mode);
    if (  result != 0  ) {
        appendLog([NSString stringWithFormat: @"chmod() returned error: '%s' for path %s", strerror(errno), targetPathC]);
        return NO;
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
        return NO;
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
        return NO;
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
        return NO;
    }

    // Convert modified date format and set modified date
    struct timeval modifiedTV;
    modifiedTV.tv_sec  = modifiedTS.tv_sec;
    modifiedTV.tv_usec = modifiedTS.tv_nsec / 1000;
    struct timeval modifiedTimevals[2] = {modifiedTV, modifiedTV};
    result = futimes(fd, modifiedTimevals);
    if (  result != 0  ) {
        appendLog([NSString stringWithFormat: @"lutimes() #1 failed for %s", targetPathC]);
        return NO;
    }

    close(fd);
    return YES;
}

void securelyCopyDirectly(NSString * sourcePath, NSString * targetPath);

void securelyCopyFileOrFolderContents(BOOL isDir, NSString * sourcePath, NSString * targetPath) {

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

void securelyCopyDirectly(NSString * sourcePath, NSString * targetPath) {

    // Copies a file, or a folder and its contents making sure the copy has the same permissions and dates as the original but is owned by root:wheel.
    //
    // DO NOT USE THIS FUNCTION: Use securelyCopy() instead.
    //
    // This routine is called only by securelyCopy() and securelyCopyFileOrFolderContents().

    BOOL isDir;

    if (  ! [gFileMgr fileExistsAtPath: sourcePath isDirectory: &isDir]  ) {
        appendLog([NSString stringWithFormat: @"Does not exist: %@", sourcePath]);
        errorExit();
    }

    if (  ! [gFileMgr tbRemovePathIfItExists: targetPath]  ) {
        appendLog([NSString stringWithFormat: @"Unable to remove %@", targetPath]);
        errorExit();
    }

    if (  ! securelyCreateFileOrDirectoryEntry(isDir, targetPath)  ) {
        errorExit();
    }

    // Set final permissions and dates
    if ( ! securelySetItemAttributes(isDir, sourcePath, targetPath)  ) {
        errorExit();
    }

    securelyCopyFileOrFolderContents(isDir, sourcePath, targetPath);
}

void securelyCopy(NSString * sourcePath, NSString * targetPath) {

    // Copies a file, or a folder and its contents, making sure the copy has the same permissions and dates as the original but is owned by root:wheel.
    //
    // Uses an intermediate file or folder and then renames it, so no partial copy has been done if an error occurs.

    BOOL isDir;

    if (  ! [gFileMgr fileExistsAtPath: sourcePath isDirectory: &isDir]  ) {
        appendLog([NSString stringWithFormat: @"Does not exist: %@", sourcePath]);
        errorExit();
    }

    NSString * tempPath = [L_AS_T stringByAppendingPathComponent: @"installer-temp"];

    errorExitIfPathIsNotSecure(tempPath);

    errorExitIfPathIsNotSecure(targetPath);

    securelyCopyDirectly(sourcePath, tempPath);

    if (  0 != renamex_np([tempPath fileSystemRepresentation], [targetPath fileSystemRepresentation], (RENAME_NOFOLLOW_ANY | RENAME_EXCL))  ){
        appendLog([NSString stringWithFormat: @"renamex_np() failed with error %d ('%s') to rename %@ to %@", errno, strerror(errno), tempPath, targetPath]);
        errorExit();
    }
}

void securelyMove(NSString * sourcePath, NSString * targetPath) {

    securelyCopy(sourcePath, targetPath);

    securelyDeleteItemAtPath(sourcePath);
}

void safeCopyOrMovePathToPath(NSString * sourcePath, NSString * targetPath, BOOL moveNotCopy) {
	
	// Copies or moves a folder, but unlocks everything in the copy (or target, if it is a move)
	
	// Copy the file or package to a ".temp" file/folder first, then rename it
	// This avoids a race condition: folder change handling code runs while copy is being made, so it sometimes can
	// see the .tblk (which has been copied) but not the config.ovpn (which hasn't been copied yet), so it complains.
	NSString * dotTempPath = [targetPath stringByAppendingPathExtension: @"temp"];
	errorExitIfAnySymlinkInPath(dotTempPath);
	if ( [gFileMgr fileExistsAtPath:dotTempPath]  ) {
		[gFileMgr tbRemoveFileAtPath:dotTempPath handler: nil];
	}
	
	createFolder([dotTempPath stringByDeletingLastPathComponent]);
	
	if (  ! [gFileMgr tbCopyPath: sourcePath toPath: dotTempPath handler: nil]  ) {
		appendLog([NSString stringWithFormat: @"Failed to copy %@ to %@", sourcePath, dotTempPath]);
		[gFileMgr tbRemovePathIfItExists: dotTempPath];

		errorExit();
	}
	appendLog([NSString stringWithFormat: @"Copied %@\n    to %@", sourcePath, dotTempPath]);
	
	// Make sure everything in the copy is unlocked
	makeUnlockedAtPath(dotTempPath);
	NSString * file;
	NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: dotTempPath];
	while (  (file = [dirEnum nextObject])  ) {
		makeUnlockedAtPath([dotTempPath stringByAppendingPathComponent: file]);
	}
	
	// Now, if we are doing a move, delete the original file, to avoid a similar race condition that will cause a complaint
	// about duplicate configuration names.
	if (  moveNotCopy  ) {
		errorExitIfAnySymlinkInPath(sourcePath);
		if (  [gFileMgr fileExistsAtPath: sourcePath]  ) {
			makeUnlockedAtPath(sourcePath);
			if (  ! deleteThingAtPath(sourcePath)  ) {
				errorExit();
			}
		}
	}
	
	errorExitIfAnySymlinkInPath(targetPath);
	if ( [gFileMgr fileExistsAtPath:targetPath]  ) {
		makeUnlockedAtPath(targetPath);
        if (  ! [gFileMgr tbRemoveFileAtPath:targetPath handler: nil]  ) {
            errorExit();
        }
	}
	int status = rename([dotTempPath fileSystemRepresentation], [targetPath fileSystemRepresentation]);
	if (  status != 0 ) {
		appendLog([NSString stringWithFormat: @"Failed to rename %@ to %@; error was %d: '%s'", dotTempPath, targetPath, errno, strerror(errno)]);
		[gFileMgr tbRemovePathIfItExists: dotTempPath];

		errorExit();
	}
	
	appendLog([NSString stringWithFormat: @"Renamed %@\n     to %@", dotTempPath, targetPath]);
}

void safeCopyPathToPath(NSString * sourcePath, NSString * targetPath) {
	
	safeCopyOrMovePathToPath(sourcePath, targetPath, NO);
}

BOOL moveContents(NSString * fromPath, NSString * toPath) {
	
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

void errorExitIfAnySymlinkInPath(NSString * path) {
	
	NSString * curPath = path;
	while (   ([curPath length] != 0)
		   && ! [curPath isEqualToString: @"/"]  ) {
		if (  [gFileMgr fileExistsAtPath: curPath]  ) {
			NSDictionary * fileAttributes = [gFileMgr tbFileAttributesAtPath: curPath traverseLink: NO];
			if (  [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
				appendLog([NSString stringWithFormat: @"Apparent symlink attack detected: Symlink is at %@, full path being tested is %@", curPath, path]);
				errorExit();
			}
		}
		
		curPath = [curPath stringByDeletingLastPathComponent];
	}
}

NSArray * configurationPathsFromPath(NSString * path) {

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

NSString * firstPartOfPath(NSString * path) {

    NSArray * paths = configurationPathsFromPath(path);
    NSEnumerator * arrayEnum = [paths objectEnumerator];
    NSString * configFolder;
    while (  (configFolder = [arrayEnum nextObject])  ) {
        if (  [path hasPrefix: [configFolder stringByAppendingString: @"/"]]  ) {
            return configFolder;
        }
    }
    return nil;
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

void createAndSecureFolder(NSString * path) {

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
        createAndSecureFolder([[L_AS_T_USERS
                                stringByAppendingPathComponent: userUsername()]
                               stringByAppendingPathComponent: lastPart]);
    }
}

void secureOpenvpnBinariesFolder(NSString * enclosingFolder) {

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

//**************************************************************************************************************************
// KEXTS

BOOL installOrUpdateOneKext(NSString * initialKextInLibraryExtensionsPath,
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
        if (  ! deleteThingAtPath(initialKextInLibraryExtensionsPath)  ) {
            errorExit();
        }
    }
    
    NSString * finalPath = [[initialKextInLibraryExtensionsPath stringByDeletingLastPathComponent]
                            stringByAppendingPathComponent: finalNameOfKext];

    if (  [gFileMgr fileExistsAtPath: finalPath]  ) {
        if (  ! deleteThingAtPath(finalPath)  ) {
            errorExit();
        }
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

BOOL secureOneKext(NSString * path) {
    
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

void updateTheKextCaches(void) {

    // According to the man page for kextcache, kext caches should be updated by executing 'touch /Library/Extensions'; the following is the equivalent:
    if (  utimes([gFileMgr fileSystemRepresentationWithPath: @"/Library/Extensions"], NULL) != 0  ) {
        appendLog([NSString stringWithFormat: @"utimes(\"/Library/Extensions\", NULL) failed with error %d ('%s')", errno, strerror(errno)]);
        errorExit();
    }
}

BOOL uninstallOneKext(NSString * path) {
    
    if (  ! [gFileMgr fileExistsAtPath: path]  ) {
        return NO;
    }
    
    if (  ! [gFileMgr tbRemoveFileAtPath: path handler: nil]  ) {
        errorExit();
    }

    appendLog([NSString stringWithFormat: @"Uninstalled %@", [path lastPathComponent]]);

    return YES;
}

void uninstallKexts(void) {
    
    BOOL shouldUpdateKextCaches = uninstallOneKext(@"/Library/Extensions/tunnelblick-tun.kext");
    
    shouldUpdateKextCaches = uninstallOneKext(@"/Library/Extensions/tunnelblick-tap.kext") || shouldUpdateKextCaches;

    if (  shouldUpdateKextCaches  ) {
        updateTheKextCaches();
    } else {
        appendLog(@"There are no kexts to uninstall");
        gErrorOccurred = TRUE;
    }
}

NSString * kextPathThatExists(NSString * resourcesPath, NSString * nameOne, NSString * nameTwo) {
    
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

void installOrUpdateKexts(BOOL forceInstall) {

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
// GENERAL

void doInitialWork(BOOL updateKexts) {
	
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
    }

    if (  updateKexts  ) {
        installOrUpdateKexts(NO);
    }
}

void copyTheApp(void) {
	
	NSString * sourcePath = [[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	NSString * targetPath  = @"/Applications/Tunnelblick.app";

	if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
		errorExitIfAnySymlinkInPath(targetPath);
		if (  [[NSWorkspace sharedWorkspace] performFileOperation: NSWorkspaceRecycleOperation
														   source: @"/Applications"
													  destination: @""
															files: [NSArray arrayWithObject: @"Tunnelblick.app"]
															  tag: nil]  ) {
			appendLog([NSString stringWithFormat: @"Moved %@ to the Trash", targetPath]);
		} else {
			appendLog([NSString stringWithFormat: @"Unable to move %@ to the Trash", targetPath]);
			errorExit();
		}
	}

    securelyCopy(sourcePath, targetPath);

    appendLog([NSString stringWithFormat: @"Securely copied %@ to %@", sourcePath, targetPath]);
}

void secureTheApp(NSString * appResourcesPath) {
	
	NSString *contentsPath				= [appResourcesPath stringByDeletingLastPathComponent];
	NSString *infoPlistPath				= [contentsPath stringByAppendingPathComponent: @"Info.plist"];
	NSString *openvpnstartPath          = [appResourcesPath stringByAppendingPathComponent:@"openvpnstart"                                   ];
	NSString *openvpnPath               = [appResourcesPath stringByAppendingPathComponent:@"openvpn"                                        ];
	NSString *atsystemstartPath         = [appResourcesPath stringByAppendingPathComponent:@"atsystemstart"                                  ];
	NSString *installerPath             = [appResourcesPath stringByAppendingPathComponent:@"installer"                          ];
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
	NSString *launchAtLoginPath         = [appResourcesPath stringByAppendingPathComponent:@"Tunnelblick-LaunchAtLogin"                      ];
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
	
	NSString *launchAtLoginPlistPath    = [appResourcesPath stringByAppendingPathComponent:@"net.tunnelblick.tunnelblick.LaunchAtLogin.plist"];
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
				if (  chmod([fullPath fileSystemRepresentation], permsShouldHave) == 0  ) {
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
	
	okSoFar = checkSetPermissions(launchAtLoginPath,         PERMS_SECURED_EXECUTABLE, YES) && okSoFar;

    okSoFar = checkSetPermissions(uninstallerAppleSPath,     PERMS_SECURED_READABLE, YES) && okSoFar;
    okSoFar = checkSetPermissions(uninstallerScriptPath,     PERMS_SECURED_EXECUTABLE, YES) && okSoFar;

    okSoFar = checkSetPermissions(atsystemstartPath,         PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(installerPath,             PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(leasewatchPath,            PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(leasewatch3Path,           PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(pncPath,                   PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(ssoPath,                   PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	okSoFar = checkSetPermissions(tunnelblickdPath,          PERMS_SECURED_ROOT_EXEC,  YES) && okSoFar;
	
	okSoFar = checkSetPermissions(pncPlistPath,              PERMS_SECURED_READABLE,   YES) && okSoFar;
    okSoFar = checkSetPermissions(leasewatchPlistPath,       PERMS_SECURED_READABLE,   YES) && okSoFar;
	okSoFar = checkSetPermissions(leasewatch3PlistPath,      PERMS_SECURED_READABLE,   YES) && okSoFar;
	okSoFar = checkSetPermissions(launchAtLoginPlistPath,    PERMS_SECURED_READABLE,   YES) && okSoFar;
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
	
	if (  ! okSoFar  ) {
		appendLog(@"Unable to secure Tunnelblick.app");
		errorExit();
	}
}

void pruneL_AS_T_TBLKS(void) {
	
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
					if (  ! [gFileMgr tbRemoveFileAtPath: containerPath handler: nil]  ) {
						appendLog([NSString stringWithFormat: @"While pruning L_AS_T_TBLKS, could not remove %@", containerPath]);
						errorExit();
					}
					
					appendLog([NSString stringWithFormat: @"Pruned L_AS_T_TBLKS by removing %@", containerPath]);
				}
			}
		}
	}
}

void secureAllTblks(void) {
	
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

void installForcedPreferences(NSString * firstPath, NSString * secondPath) {

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
			if (  ! [gFileMgr tbRemoveFileAtPath: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH handler: nil]  ) {
				appendLog([NSString stringWithFormat: @"Warning: unable to remove %@", L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH]);
			}
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

void doFolderRename(NSString * sourcePath, NSString * targetPath) {

    // Renames the source folder to the target folder. Both folders need to be in the same folder.
    //
    // If the source folder is a private folder, the corresponding secure folder is also renamed if it exists.
    //
    // Uses rename() so nothing needs be done with ownership/permissions.

    if (  ! [gFileMgr fileExistsAtPath: sourcePath]  ) {
        appendLog([NSString stringWithFormat: @"rename source does not exist: %@ to %@", sourcePath, targetPath]);
        errorExit();
    }
    if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
        appendLog([NSString stringWithFormat: @"rename target exists: %@ to %@", sourcePath, targetPath]);
        errorExit();
    }
    if (  0 == rename([sourcePath fileSystemRepresentation], [targetPath fileSystemRepresentation])  ) {
        appendLog([NSString stringWithFormat: @"Renamed %@ to %@", sourcePath, targetPath]);
    } else {
        appendLog([NSString stringWithFormat: @"Error from rename = %d ('%s') trying to rename %@ to %@",
                   errno, strerror(errno), sourcePath, targetPath]);
        errorExit();
    }

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
            if (  0 == rename([secureSourcePath fileSystemRepresentation], [secureTargetPath fileSystemRepresentation])  ) {
                appendLog([NSString stringWithFormat: @"Renamed %@ to %@", secureSourcePath, secureTargetPath]);
            } else {
                appendLog([NSString stringWithFormat: @"Error from rename = %d ('%s') trying to rename %@ to %@",
                           errno, strerror(errno), secureSourcePath, secureTargetPath]);
                errorExit();
            }
        }
    }
}

void structureTblkProperly(NSString * path) {

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
                [sourcePaths addObject: fullPath];
                [targetPaths addObject: [[path stringByAppendingPathComponent: @"/Contents/Resources"] stringByAppendingPathComponent: entry]];
            }
        }
    }

    for (  NSUInteger i=0; i<[sourcePaths count]; i++  ) {
        if (  ! [gFileMgr tbMovePath: sourcePaths[i] toPath: targetPaths[i] handler: nil]  ) {
            appendLog([NSString stringWithFormat: @"Unable to move %@ to %@", sourcePaths[i], targetPaths[i]]);
            errorExit();
        }
    }
}

void doCopyOrMove(NSString * firstPath, NSString * secondPath, BOOL moveNotCopy) {
	
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

        createAndSecureFolder(targetPath);
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
    createAndSecureFolder(enclosingFolder);

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
	
	safeCopyOrMovePathToPath(sourcePath, targetPath, moveNotCopy);
	
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
			if (  ! deleteThingAtPath(shadowTargetPath)  ) {
				errorExit();
			}
		}
		
		// Create container for shadow copy
		enclosingFolder = [shadowTargetPath stringByDeletingLastPathComponent];
		BOOL isDir;
		if (   ( ! [gFileMgr fileExistsAtPath: shadowTargetPath isDirectory: &isDir])
			&& isDir  ) {
			errorExitIfAnySymlinkInPath(enclosingFolder);
			createDirWithPermissionAndOwnership(enclosingFolder, PERMS_SECURED_FOLDER, 0, 0);
		}
		
		safeCopyPathToPath(targetPath, shadowTargetPath);	// Copy the target because the source may have _moved_ to the target
		
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
				if (  ! deleteThingAtPath(shadowSourcePath)  ) {
					errorExit();
				}
			}
		}
	}
}

void deleteOneTblk(NSString * firstPath, NSString * secondPath) {
	
	if (  ! firstPath) {
		appendLog(@"Operation is INSTALLER_DELETE but firstPath is not set");
		errorExit();
	}
	
	if (  secondPath  ) {
		appendLog(@"Operation is INSTALLER_DELETE but secondPath is set");
		errorExit();
	}
	
	if (  [gFileMgr fileExistsAtPath: firstPath]  ) {
		errorExitIfAnySymlinkInPath(firstPath);
		makeUnlockedAtPath(firstPath);
		if (  ! [gFileMgr tbRemoveFileAtPath: firstPath handler: nil]  ) {
			appendLog([NSString stringWithFormat: @"unable to remove %@", firstPath]);
		} else {
			appendLog([NSString stringWithFormat: @"removed %@", firstPath]);
		}
		
		// Delete shadow copy, too, if it exists
		if (  isPathPrivate(firstPath)  ) {
			NSString * shadowCopyPath = [NSString stringWithFormat: @"%@/%@/%@",
										 L_AS_T_USERS,
										 userUsername(),
										 lastPartOfPath(firstPath)];
			if (  [gFileMgr fileExistsAtPath: shadowCopyPath]  ) {
				errorExitIfAnySymlinkInPath(shadowCopyPath);
				makeUnlockedAtPath(shadowCopyPath);
				if (  ! [gFileMgr tbRemoveFileAtPath: shadowCopyPath handler: nil]  ) {
					appendLog([NSString stringWithFormat: @"unable to remove %@", shadowCopyPath]);
				} else {
					appendLog([NSString stringWithFormat: @"removed %@", shadowCopyPath]);
				}
			}
		}
    } else {
        appendLog([NSString stringWithFormat: @"No file at %@", firstPath]);
	}
}

void setupDaemon(void) {
 
	// If we are reloading the LaunchDaemon, we make sure it is up-to-date by copying its .plist into /Library/LaunchDaemons
	
	// Install or replace the tunnelblickd .plist in /Library/LaunchDaemons
	BOOL hadExistingPlist = [gFileMgr fileExistsAtPath: TUNNELBLICKD_PLIST_PATH];
	NSDictionary * newPlistContents = tunnelblickdPlistDictionaryToUse();
	if (  ! newPlistContents  ) {
		appendLog(@"Unable to get a model for tunnelblickd.plist");
		errorExit();
	}
	if (  hadExistingPlist  ) {
		if (  ! [gFileMgr tbRemoveFileAtPath: TUNNELBLICKD_PLIST_PATH handler: nil]  ) {
			appendLog([NSString stringWithFormat: @"Unable to delete %@", TUNNELBLICKD_PLIST_PATH]);
			errorExit();
		}
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
// EXPORT SETUP

void createExportFolder(NSString * path) {
	
	if (  ! createDirWithPermissionAndOwnership(path, privateFolderPermissions(path), 0, 0)  ) {
		appendLog([NSString stringWithFormat: @"Error creating folder %@", path]);
		errorExit();
	}
}

void exportOneUser(NSString * username, NSString * targetUsersPath) {
	
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
		safeCopyPathToPath(sourcePreferencesPath, targetPreferencesPath);
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
		safeCopyPathToPath(sourceConfigurationsPath, targetConfigurationsPath);
	}
	
	// Copy easy-rsa only if it exists
	NSString * sourceEasyrsaPath = [userL_AS_T     stringByAppendingPathComponent: @"easy-rsa"];
	NSString * targetEasyrsaPath = [targetThisUserPath stringByAppendingPathComponent: @"easy-rsa"];
	if (  [gFileMgr fileExistsAtPath: sourceEasyrsaPath]  ) {
		if (  ! createdTargetThisUserPath  ) {
			createExportFolder(targetThisUserPath);
		}
		safeCopyPathToPath(sourceEasyrsaPath, targetEasyrsaPath);
	}
}

void pruneFolderAtPath(NSString * path) {
	
	// Removes subfolders of path if they do not have any contents
	
	NSString * outerName;
	NSDirectoryEnumerator * outerEnum = [gFileMgr enumeratorAtPath: path];
	while (  (outerName = [outerEnum nextObject])  ) {
		[outerEnum skipDescendants];
		NSString * pruneCandidatePath = [path stringByAppendingPathComponent: outerName];
		
		NSDirectoryEnumerator * innerEnum = [gFileMgr enumeratorAtPath: pruneCandidatePath];
		if (  ! [innerEnum nextObject]  ) {
			if (  ! [gFileMgr tbRemovePathIfItExists: pruneCandidatePath]  ) {
				errorExit();
			}
			
			appendLog([NSString stringWithFormat: @"Removed folder because it was empty: %@", pruneCandidatePath]);
		}
	}
}

void exportToPath(NSString * exportPath) {
	
	// Create a temporary folder, copy stuff into it, make a tar.gz of it at the indicated path, and delete it
	
	NSString * tarPath = [[exportPath stringByAppendingPathExtension: @"tar"] stringByAppendingPathExtension: @"gz"];
	
	// Remove the output file if it already exists
	// (We do this so user doesn't do something with it before we're finished).
	if (  ! [gFileMgr tbRemovePathIfItExists: tarPath]  ) {
		errorExit();
	}
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
		safeCopyPathToPath(sourceForcedPreferencesPath, targetForcedPreferencesPath);
	}
	
	// Copy Shared to Global
	NSString * sourceSharedPath            = L_AS_T_SHARED;
	NSString * targetSharedPath            = [targetSetupGlobalPath stringByAppendingPathComponent: @"Shared"];
	safeCopyPathToPath(sourceSharedPath, targetSharedPath);
	pruneFolderAtPath(targetSharedPath);
	
	// Copy Users to Global
	NSString * sourceUsersPath             = L_AS_T_USERS;
	NSString * targetUsersPath             = [targetSetupGlobalPath stringByAppendingPathComponent: @"Users"];
	safeCopyPathToPath(sourceUsersPath, targetUsersPath);
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
	if (  ! [gFileMgr tbRemoveFileAtPath: tempFolderPath handler: nil]  ) {
		errorExit();
	}
}

//**************************************************************************************************************************
//	IMPORT SETUP

void errorExitIfSymlinksOrDoesNotExistOrIsNotReadableAtPath(NSString * path) {
	
	if (   [gFileMgr fileExistsAtPath: path]
		&& [gFileMgr isReadableFileAtPath: path]  ) {
		errorExitIfAnySymlinkInPath(path);
		return;
	}
	
	appendLog([NSString stringWithFormat: @"File does not exist or is not readable: %@", path]);
	errorExit();
}

NSString * formattedUserGroup(uid_t uid, gid_t gid) {
	
	// Returns a string with uid:gid padded on the left with spaces to a width of 11
	
	const char * ugC = [[NSString stringWithFormat: @"%d:%d", uid, gid] UTF8String];
	return [NSString stringWithFormat: @"%11s", ugC];
}

void safeCopyPathToPathAndSetUidAndGid(NSString * sourcePath, NSString * targetPath, uid_t newUid, gid_t newGid) {
	
	NSString * verb = (  [gFileMgr fileExistsAtPath: targetPath]
					   ? @"Overwrote"
					   : @"Copied to");
	safeCopyPathToPath(sourcePath, targetPath);
    if ( ! checkSetOwnership(targetPath, YES, newUid, newGid)  ) {
        errorExit();
    }
    
	appendLog([NSString stringWithFormat: @"%@ and set ownership to %@: %@", verb, formattedUserGroup(newUid, newGid), targetPath]);
}

void mergeConfigurations(NSString * sourcePath, NSString * targetPath, uid_t uid, gid_t gid, BOOL mergeIconSets) {
	
	// Adds folders in the source folder to the target folder, replacing existing folders in the target folder if they exist, and
	// setting the ownership to uid:gid. If enclosing folders need to be created, set their permissions to permissions.
	//
	// If "mergeIconSets" is TRUE, handles folders named "IconSets" similarly (that is, adding the subfolders of "IconSets",
	// not replacing the entire "IconSets" folder).
	//
	// This routine is used to merge both
	//		.tblkSettings/Global/Users         (with "mergeIconSets" TRUE) and
	//		.tblkSettings/Users/Configurations (with "mergeIconSets" FALSE).
	
	NSString * name;
	NSDirectoryEnumerator * e = [gFileMgr enumeratorAtPath: sourcePath];
	while (  (name = [e nextObject])  ) {
		[e skipDescendants];
		
		if (  ! [name hasPrefix: @"."]  ) {
			
			if (   mergeIconSets
				&& [name isEqualToString: @"IconSets"]  ) {

				// Handle IconSets folder similarly, that is, copy each icon set individually (note use of recursion)
				NSString * sourceIconSetFolderPath = [sourcePath stringByAppendingPathComponent: @"IconSets"];
				NSString * targetIconSetFolderPath = [targetPath stringByAppendingPathComponent: @"IconSets"];
				mergeConfigurations(sourceIconSetFolderPath, targetIconSetFolderPath, uid, gid, NO);

			} else {

				// Create enclosing folder(s) if necessary
				if (  ! [gFileMgr fileExistsAtPath: targetPath]  ) {
					createFolder(targetPath);
				}
				
				NSString * sourceFullPath = [sourcePath stringByAppendingPathComponent: name];
				NSString * targetFullPath = [targetPath stringByAppendingPathComponent: name];
				safeCopyPathToPathAndSetUidAndGid(sourceFullPath, targetFullPath, uid, gid);
			}
		}
	}
}

void mergeGlobalUsersFolder(NSString * tblkSetupPath, NSDictionary * nameMap) {
	
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
							stringByAppendingString: @"Users"];
	NSString * outFolder = L_AS_T_USERS;
	
	// Create enclosing folder(s) if necessary
	if (  ! [gFileMgr fileExistsAtPath: outFolder]  ) {
					createFolder(outFolder);
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

void mergeSetupDataForOneUser(NSString * sourcePath, NSString * newUsername) {

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

void errorExitIfTblkSetupIsNotValid(NSString * tblkSetupPath) {
	
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

NSDictionary * nameMapFromString(NSString * usernameMap, NSString * tblkSetupPath) {
	
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

void createImportInfoFile(NSString * tblkSetupPath) {
	
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

void mergeForcedPreferences(NSString * sourcePath) {
	
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
			if (  ! [gFileMgr tbRemovePathIfItExists: targetPath]  ) {
				errorExit();
			}
			if (  ! [existingPreferences writeToFile: targetPath atomically: YES]  ) {
				appendLog([NSString stringWithFormat: @"Error: could not write %@  ", sourcePath]);
				errorExit();
			}
			
		} else {
			appendLog([NSString stringWithFormat: @"Do not need to create or modify             %@  ", targetPath]);
		}
	}
}

void importSetup(NSString * tblkSetupPath, NSString * usernameMap) {
	
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
//**************************************************************************************************************************

int main(int argc, char *argv[]) {
	pool = [NSAutoreleasePool new];
	
    gFileMgr = [NSFileManager defaultManager];
	
    if (  argc < 2  ) {
		openLog(FALSE);
        appendLog(@"1 or more arguments are required");
        errorExit();
	}

    unsigned opsAndFlags = (unsigned) strtol(argv[1], NULL, 0);

    BOOL doClearLog = (opsAndFlags & INSTALLER_CLEAR_LOG) != 0;
    openLog(doClearLog);

    // Log the arguments installer was started with
    NSMutableString * logString = [NSMutableString stringWithFormat: @"Tunnelblick installer started %@; getuid() = %d; geteuid() = %d; getgid() = %d; getegid() = %d\ncurrentDirectoryPath = '%@'; %d arguments:\n",
                                   [[NSDate date] tunnelblickUserLogRepresentation], getuid(), geteuid(), getgid(), getegid(), [gFileMgr currentDirectoryPath], argc - 1];
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
	NSString * ourAppName = [execComponents objectAtIndex: [execComponents count] - 3];
	if (  [ourAppName hasSuffix: @".app"]  ) {
		ourAppName = [ourAppName substringToIndex: [ourAppName length] - 4];
	}
    
    // We use Deploy located in the Tunnelblick in /Applications, even if we are running from some other location and are copying the application there
#ifndef TBDebug
	gDeployPath = @"/Applications/Tunnelblick.app/Contents/Resources/Deploy";
#else
	gDeployPath = [resourcesPath stringByAppendingPathComponent: @"Deploy"];
#endif
    
    // Set up globals that have to do with the user
    setupUserGlobals(argc, argv, operation);

    // If we copy the .app to /Applications, other changes to the .app affect THAT copy, otherwise they affect the currently running copy
    NSString * appResourcesPath = (  doCopyApp
                                   
                                   ? [[[@"/Applications"
                                        stringByAppendingPathComponent: [ourAppName stringByAppendingPathExtension: @"app"]]
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

    //**************************************************************************************************************************
    // (1) Create directories or repair their ownership/permissions as needed
    //        and do other things that are done each time installer is run
	
	doInitialWork( ! doUninstallKexts );
	
    //**************************************************************************************************************************
    // (2) (REMOVED)
	
    //**************************************************************************************************************************
	// (3) (REMOVED)
	
    //**************************************************************************************************************************
    // (4) If INSTALLER_COPY_APP is set:
    //     Then move /Applications/XXXXX.app to the Trash, then copy this app to /Applications/XXXXX.app
    
    if (  doCopyApp  ) {
		copyTheApp();
    }
    
	//**************************************************************************************************************************
	// (5) If requested, secure Tunnelblick.app by setting the ownership and permissions of it and all its components
    if ( doSecureApp ) {
		secureTheApp(appResourcesPath);
    }
    
    //**************************************************************************************************************************
    // (6) If INSTALLER_COPY_APP, L_AS_T_TBLKS is pruned by removing all but the highest edition of each container
    
    if (  doCopyApp  ) {
        pruneL_AS_T_TBLKS();
    }
    
    //**************************************************************************************************************************
    // (7)
    // If requested, secure all .tblk packages
    if (  doSecureTblks  ) {
		secureAllTblks();
    }
    
    //**************************************************************************************************************************
    // (8) Install the .plist at secondArg to L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH
    
    if (  operation == INSTALLER_INSTALL_FORCED_PREFERENCES  ) {
		installForcedPreferences(secondArg, thirdArg);
    }
    
    //**************************************************************************************************************************
    // (9) If requested, install a configuration.
    // Copy or move a single .tblk package (without any nested .tblks).
    // Also moves/coies/creates a shadow copy if a private configuration.
    // Like the NSFileManager "movePath:toPath:handler" method, we move by copying, then deleting.
    if (   secondArg
        && (argc < 6)  ) {
        if (   (   (operation == INSTALLER_COPY )
                || (operation == INSTALLER_MOVE)
                )
            && thirdArg  ) {

            doCopyOrMove(secondArg, thirdArg, (operation == INSTALLER_MOVE));

        } else if (   (operation == INSTALLER_INSTALL_PRIVATE_CONFIG)
                   && thirdArg  ) {
            if (  argc < 4  ) {
                appendLog(@"installing a private configuration requires a username and a path");
                errorExit();
            }
            NSString * targetPath = userPrivatePath();

            if (  fourthArg  ) {
                targetPath = [targetPath stringByAppendingPathComponent: fourthArg];
                createFolder(targetPath);
            }

            targetPath = [targetPath stringByAppendingPathComponent: [thirdArg lastPathComponent]];

            doCopyOrMove(targetPath, thirdArg, false);

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
                createFolder(targetPath);
            } else {
                targetPath = L_AS_T_SHARED;
            }

            targetPath = [targetPath stringByAppendingPathComponent: [secondArg lastPathComponent]];

            doCopyOrMove(targetPath, secondArg, false);
        }

    }
    
    //**************************************************************************************************************************
    // (10)
    // If requested, delete a single file or .tblk package (also deletes the shadow copy if deleting a private configuration)
	
    if (  operation == INSTALLER_DELETE  ) {
		deleteOneTblk(secondArg, thirdArg);
    }
    
    //**************************************************************************************************************************
    // (11) Set up tunnelblickd to load when the computer starts
	
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
		setupDaemon();
    } else {
        if (  ! checkSetOwnership(TUNNELBLICKD_PLIST_PATH, NO, 0, 0)  ) {
            errorExit();
        }
        if (  ! checkSetPermissions(TUNNELBLICKD_PLIST_PATH, PERMS_SECURED_READABLE, YES)  ) {
            errorExit();
        }
    }
	
	//**************************************************************************************************************************
	// (12) If requested, exports all settings and configurations for all users to a file at targetPath, deleting the file if it already exists
	if (   secondArg
		&& ( ! thirdArg   )
		&& (  operation == INSTALLER_EXPORT_ALL)  ) {
		exportToPath(secondArg);
	}
	
	//**************************************************************************************************************************
	// (13) If requested, import settings from the .tblkSetup at secondArg using username mapping in the string in "thirdArg"
	//
	//		NOTE: "thirdArg" is a string that specifies the username mapping to use when importing.
	if (   (operation == INSTALLER_IMPORT)
		&& secondArg
		&& thirdArg  ) {
		importSetup(secondArg, thirdArg);
	}
	
    //**************************************************************************************************************************
    // (14) If requested, install or uninstall kexts
    if (   doInstallKexts  ) {
        installOrUpdateKexts(YES);
    }
    
    if (   doUninstallKexts  ) {
        uninstallKexts();
    }

    //**************************************************************************************************************************
    // DONE

    if (  gErrorOccurred  ) {
        appendLog(@"Tunnelblick installer finished with errors");
        storeAuthorizedDoneFileAndExit(EXIT_SUCCESS);
    }

    appendLog(@"Tunnelblick installer succeeded");
    storeAuthorizedDoneFileAndExit(EXIT_SUCCESS);
}
