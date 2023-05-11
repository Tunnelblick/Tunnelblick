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

// NOTE: THIS PROGRAM MUST BE RUN AS ROOT VIA executeAuthorized
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
//     installer bitmask  targetPath  sourcePath
//               (for copy/move configuration)
//
//     installer bitmask  sourcePath  usernameMappingString
//               (for import .tblksetup)
//
//     installer bitmask  username  sourcePath
//               (for copy private configurations)
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
//			Updates old format of updatable configuartions to new format
//          Converts old entries in L_AS_T_TBLKS to the new format, with a bundleId_edition folder enclosing a .tblk
//          Renames /Library/LaunchDaemons/net.tunnelblick.startup.*
//               to                        net.tunnelblick.tunnelblick.startup.*
//          Updates Tunnelblick kexts in /Library/Extensions (unless kexts are being uninstalled)
//
//      (2) (REMOVED)
//      (3) (REMOVED)
//      (4) If INSTALLER_COPY_APP is set, this app is copied to /Applications and the com.apple.quarantine extended attribute is removed from the app and all items within it
//      (5) If INSTALLER_SECURE_APP is set, secures Tunnelblick.app by setting the ownership and permissions of its components.
//      (6) If INSTALLER_COPY_APP is set, L_AS_T_TBLKS is pruned by removing all but the highest edition of each container
//      (7) If INSTALLER_SECURE_TBLKS or INSTALLER_COPY_APP are set
//			or migrated configurations from the old OpenVPN library,
//			or converted non-.tblks to be .tblks:
//			Then secures all .tblk packages in the following folders:
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

// When finished (or if an error occurs), the file /tmp/tunnelblick-authorized-running is deleted to indicate the program has finished

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

// The following variable may be modified by routines to affect later behavior of the program
BOOL            gSecureTblks;				  // Set initially if all .tblks need to be secured.

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
	
	static unsigned int debugLogMessageCounter = 0;
	
	NSString * path = [NSString stringWithFormat: @"/tmp/0-%u-tunnelblick-installer-%@.txt", ++debugLogMessageCounter, string];
	[gFileMgr createFileAtPath: path contents: [NSData data] attributes: nil];
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
    appendLog([NSString stringWithFormat: @"installer: errorExit: Stack trace: %@", callStack()]);
#endif

    // Leave AUTHORIZED_ERROR_PATH to indicate an error occurred
    deleteFlagFile(AUTHORIZED_RUNNING_PATH);
    closeLog();

    [pool drain];
    exit(EXIT_FAILURE);
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
    } else if (  errno != ENOENT  ) { // Ignore no such file
        appendLog([NSString stringWithFormat: @"stat of %@ failed\nError was %d ('%s')", path, errno, strerror(errno)]);
    }
}

void freeAuthRef(AuthorizationRef authRef) {

    if (  authRef != NULL  ) {
        OSStatus status = AuthorizationFree(authRef, kAuthorizationFlagDefaults);
        if (  status != errAuthorizationSuccess  ) {
            appendLog([NSString stringWithFormat: @"AuthorizationFree) returned %ld", (long)status]);
            errorExit();
        }
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
        if (  [username isEqualToString [r recordName]]  ) {
            return YES;
        }
    }

    return NO;
}

NSString * usernameFromPossiblePrivatePath(NSString * path) {

    if (  ! [path hasPrefix: @"/Users/"]  ) {
        return nil;
    }

    NSRange afterUsersSlash = NSMakeRange([@"/Users/" length], [path length] - [@"/Users/" length]);
    NSRange slashAfterName = [path rangeOfString: @"/" options: 0 range: afterUsersSlash];
    if (  slashAfterName.location == NSNotFound  ) {
        return nil;
    }

    NSString * username = [path substringWithRange: NSMakeRange([@"/Users/" length], slashAfterName.location)];
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

    if (  gUserID == 0  ) {
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
    } else if (   operation == INSTALLER_INSTALL_PRIVATE_CONFIG  ) {
        //
        // Calculate user info from username given as an argument
        //

        if (  argc != 3  ) {
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

    } else {
        //
        // Calculate user info from a private path if one is provided as an argument
        //
        for (  int i=2; i<argc; i++  ) {
            gUsername = usernameFromPossiblePrivatePath([NSString stringWithCString: argv[i] encoding: NSUTF8StringEncoding]);
            if (  gUsername  ) {
                break;
            }
        }

        if (  gUsername != nil  ) {
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
        }
    }
}

// MISC

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

BOOL removeQuarantineBitWorker(NSString * path) {
    
    const char * fullPathC = [path fileSystemRepresentation];
    const char * quarantineBitNameC = "com.apple.quarantine";
    int status = removexattr(fullPathC, quarantineBitNameC, XATTR_NOFOLLOW);
    if (   (status != 0)
        && (errno != ENOATTR)) {
        appendLog([NSString stringWithFormat: @"Failed to remove '%s' from %s; errno = %ld; error was '%s'", quarantineBitNameC, fullPathC, (long)errno, strerror(errno)]);
        return FALSE;
    }
    
    return TRUE;
}

BOOL removeQuarantineBit(void) {
    
    NSString * tbPath = @"/Applications/Tunnelblick.app";
    
    if (  ! removeQuarantineBitWorker(tbPath)  ) {
        return FALSE;
    }
    
    NSDirectoryEnumerator * dirE = [gFileMgr enumeratorAtPath: tbPath];
    NSString * file;
    while (  (file = [dirE nextObject])  ) {
        NSString * fullPath = [tbPath stringByAppendingPathComponent: file];
        if (  ! removeQuarantineBitWorker(fullPath)  ) {
            return FALSE;
        }
    }
    
    return TRUE;
}

void loadLaunchDaemonUsingSMJobSubmit(NSDictionary * newPlistContents) {

    (void)newPlistContents; // REMOVE if we ever use this routine!

    /* DISABLED BECAUSE THIS IS NOT AVAILABLE ON 10.4 and 10.5
     *
     * UPDATE 2016-07-03: SMJobSubmit is now deprecated, but we are leaving the code in so that if 'launchctl load' stops working, we can try using it
     *
     * When/if this is enabled, must add the ServiceManagement framework, too, via the following line at the start of this file:
     *
     *      #import <ServiceManagement/ServiceManagement.h>
     *
     * That framework is not on 10.4, and the SMJobSubmit() function is not available on 10.5


	// Obtain the right to change the system launchd domain
	AuthorizationItem right;
	right.name = kSMRightModifySystemDaemons;
	right.valueLength = 0;
	right.value = NULL;
	right.flags = 0;
	
	AuthorizationRights requestedRights;
	requestedRights.count = 1;
	requestedRights.items = &right;
	
	AuthorizationRef authRef = NULL;
	
	OSStatus status = AuthorizationCreate(&requestedRights,
										  kAuthorizationEmptyEnvironment,
										  (  kAuthorizationFlagDefaults
										   | kAuthorizationFlagExtendRights),
										  &authRef);
	if (  errAuthorizationSuccess != status  ) {
		appendLog([NSString stringWithFormat: @"Unable to create an AuthorizationRef with the 'kSMRightModifySystemDaemons' right; status = %d", status]);
		freeAuthRef(authRef);
		errorExit();
	}
	
	// Unload the existing LaunchDaemon if if is loaded
	NSString * daemonLabel = @"net.tunnelblick.tunnelblick.tunnelblickd";
	CFErrorRef removeError = NULL;
	if (  ! SMJobRemove(kSMDomainSystemLaunchd, (CFStringRef)daemonLabel, authRef, TRUE , &removeError)) {	// TRUE = do not return until removed
		if (  CFErrorGetCode(removeError) != kSMErrorJobNotFound ) {
			appendLog([NSString stringWithFormat: @"Unable to unload %@; error: %@", daemonLabel, (NSError *)removeError]);
			if (  removeError  ) CFRelease(removeError);
			freeAuthRef(authRef);
			errorExit();
		}
		appendLog([NSString stringWithFormat: @"Do not need to unload old %@", daemonLabel]);
	} else {
		appendLog([NSString stringWithFormat: @"Unloaded old %@", daemonLabel]);
	}
	if (  removeError  ) CFRelease(removeError);
	
	// Load the new daemon
	CFDictionaryRef cfPlist = (CFDictionaryRef)[NSDictionary dictionaryWithDictionary: newPlistContents];
	CFErrorRef submitError = NULL;
	if (  ! SMJobSubmit(kSMDomainSystemLaunchd, cfPlist, authRef, &submitError)  ) {
		appendLog([NSString stringWithFormat: @"SMJobSubmit failed to load %@; error: %@", daemonLabel, (NSError *)submitError]);
		if (  submitError  ) CFRelease(submitError);
		freeAuthRef(authRef);
		errorExit();
	} else {
		appendLog([NSString stringWithFormat: @"Loaded new %@", daemonLabel]);
	}
	if (  submitError  ) CFRelease(submitError);
	
	freeAuthRef(authRef);

    */
}

void loadLaunchDaemonAndSaveHashes (NSDictionary * newPlistContents) {
	
	// 'runningOnSnowLeopardOrNewer' is not in sharedRoutines, so we don't use it -- we load the launch daemon the old way, with 'launchctl load'
	// Left the new code in to make it easy to implement the new way -- with 'SMJobSubmit()' on 10.6.8 and higher -- in case a later version of macOS messes with 'launchctl load'
	// To implement the new way, too, move 'runningOnSnowLeopardOrNewer' to sharedRoutines and un-comment the code below to use 'loadLaunchDaemonUsingSMJobSubmit'.
    //
    // UPDATE 2016-07-03: By now (when we are removing 10.4 and 10.5 code), SMJobSubmit is deprecated (thanks, Apple!), so we aren't bothering to use it,
    // we are still using 'launchctl load'.
    
    //      if (  runningOnSnowLeopardOrNewer()  ) {
    //          loadLaunchDaemonUsingSMJobSubmit(newPlistContents);
    // 	    } else {
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
    NSBundle * ourBundle = [NSBundle mainBundle];
    NSString * resourcesPath = [ourBundle bundlePath]; // (installer itself is in Resources, so this works)
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
		if ( [gFileMgr fileExistsAtPath:dotTempPath]  ) {
			[gFileMgr tbRemoveFileAtPath:dotTempPath handler: nil];
		}
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
		if ( [gFileMgr fileExistsAtPath:dotTempPath]  ) {
			[gFileMgr tbRemoveFileAtPath:dotTempPath handler: nil];
		}
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

    BOOL private = [path hasPrefix: [[userPrivatePath() stringByDeletingLastPathComponent] stringByAppendingString: @"/"]];
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

    // safeCopyPathToPath will replace any existing kext
    safeCopyPathToPath(kextInAppPath, finalPath);
    
    if ( ! checkSetOwnership(finalPath, YES, 0, 0)  ) {
        errorExit();
    }
    
    NSString * verb = (  initialKextExists
                       ? @"Updated"
                       : @"Installed");
    appendLog([NSString stringWithFormat: @"%@ %@ in %@", verb, finalNameOfKext, [finalPath stringByDeletingLastPathComponent]]);

    return YES;
}

//**************************************************************************************************************************
// KEXTS

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
    
    return YES;
}

void uninstallKexts(void) {
    
    BOOL shouldUpdateKextCaches = uninstallOneKext(@"/Library/Extensions/tunnelblick-tun.kext");
    
    shouldUpdateKextCaches = uninstallOneKext(@"/Library/Extensions/tunnelblick-tap.kext") || shouldUpdateKextCaches;

    if (  shouldUpdateKextCaches  ) {
        updateTheKextCaches();
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
    
    NSString * thisAppPath = [[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    NSString * resourcesPath = [[thisAppPath stringByAppendingPathComponent: @"Contents"] stringByAppendingPathComponent: @"Resources"];

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
	
	if (  ! createDirWithPermissionAndOwnership([L_AS_T_USERS stringByAppendingPathComponent: userUsername()],
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

	// Delete *.mip files (used before using the Mips folder)
    NSDirectoryEnumerator  * dirEnum = [gFileMgr enumeratorAtPath: L_AS_T];
	NSString * fileName;
	while (  (fileName = [dirEnum nextObject])  ) {
		[dirEnum skipDescendants];
		if (  [fileName hasSuffix: @".mip"]  ) {
            NSString * fullPath = [L_AS_T stringByAppendingPathComponent: fileName];
            if (  [gFileMgr tbRemoveFileAtPath: fullPath handler: nil]  ) {
                appendLog([NSString stringWithFormat: @"Deleted obsolete file '%@'", fullPath]);
            } else {
                appendLog([NSString stringWithFormat: @"Cannot delete obsolete file '%@'", fullPath]);
            }
		}
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

	// Rename /Library/LaunchDaemons/net.tunnelblick.startup.*
	//     to                        net.tunnelblick.tunnelblick.startup.*
	
	dirEnum = [gFileMgr enumeratorAtPath: @"/Library/LaunchDaemons"];
	NSString * file;
	NSString * oldPrefix = @"net.tunnelblick.startup.";
	NSString * newPrefix = @"net.tunnelblick.tunnelblick.startup.";
	while (  (file = [dirEnum nextObject])  ) {
		[dirEnum skipDescendents];
		if (  [file hasPrefix:  oldPrefix]) {
			NSString * newFile = [newPrefix stringByAppendingString: [file substringFromIndex: [oldPrefix length]]];
			NSString * newPath = [@"/Library/LaunchDaemons" stringByAppendingPathComponent: newFile];
			NSString * oldPath = [@"/Library/LaunchDaemons" stringByAppendingPathComponent: file];
			if (  0 == rename([oldPath fileSystemRepresentation], [newPath fileSystemRepresentation])  ) {
				appendLog([NSString stringWithFormat: @"Renamed %@ to %@", oldPath, newFile]);
			} else {
				appendLog([NSString stringWithFormat: @"Unable to rename %@ to %@; error = '%s' (%ld)",
						   oldPath, newFile, strerror(errno), (long)errno]);
				errorExit();
			}
			
		}
	}
    
    if (  updateKexts  ) {
        installOrUpdateKexts(NO);
    }
}

void copyTheApp(void) {
	
	NSString * currentPath = [[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
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
	
	if (  ! [gFileMgr tbCopyPath: currentPath toPath: targetPath handler: nil]  ) {
		appendLog([NSString stringWithFormat: @"Unable to copy %@ to %@", currentPath, targetPath]);
		errorExit();
	} else {
		appendLog([NSString stringWithFormat: @"Copied %@ to %@", currentPath, targetPath]);
	}
	
	if (  ! removeQuarantineBit()  ) {
		appendLog(@"Unable to remove all 'com.apple.quarantine' extended attributes");
		errorExit();
	} else {
		appendLog(@"Removed any 'com.apple.quarantine' extended attributes");
	}
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
		BOOL isPrivate = [folderPath hasPrefix: userPrivatePath()];
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
        if (   ( ! [entry hasPrefix @"."] )
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

    BOOL targetIsPrivate = [targetPath hasPrefix: [userPrivatePath() stringByAppendingString: @"/"]];
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
		
		BOOL deletedOldShadowCopy = FALSE;
		if (  [gFileMgr fileExistsAtPath: shadowTargetPath]  ) {
			if (  ! deleteThingAtPath(shadowTargetPath)  ) {
				errorExit();
			}
			
			deletedOldShadowCopy = TRUE;
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
		
		if (  deletedOldShadowCopy  ) {
			appendLog([NSString stringWithFormat: @"Updated secure (shadow) copy of %@", lastPartOfTarget]);
		} else {
			appendLog([NSString stringWithFormat: @"Created secure (shadow) copy of %@", lastPartOfTarget]);
		}
	}
	
	if (  [sourcePath hasPrefix: [userPrivatePath() stringByAppendingString: @"/"]]  ) {
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
			appendLog([NSString stringWithFormat: @"Deleted secure (shadow) copy of %@", lastPartOfSource]);
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
		if (  [firstPartOfPath(firstPath) isEqualToString: userPrivatePath()]  ) {
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
	
    if (  (argc < 2)  || (argc > 4)  ) {
		openLog(FALSE);
        appendLog([NSString stringWithFormat: @"Wrong number of arguments -- expected 1 to 3, given %d", argc-1]);
        errorExit();
	}

    unsigned arg1 = (unsigned) strtol(argv[1], NULL, 10);
	
	BOOL doClearLog               = (arg1 & INSTALLER_CLEAR_LOG) != 0;
    BOOL doCopyApp                = (arg1 & INSTALLER_COPY_APP) != 0;
    BOOL doSecureApp              =    doCopyApp
								    || ( (arg1 & INSTALLER_SECURE_APP)   != 0 );
    BOOL doForceLoadLaunchDaemon  = (arg1 & INSTALLER_REPLACE_DAEMON) != 0;
    BOOL doUninstallKexts         = (arg1 & INSTALLER_UNINSTALL_KEXTS) != 0;
    
    // Uinstall kexts overrides install kexts
    BOOL doInstallKexts           = (   ( ! doUninstallKexts )
                                     && ((arg1 & INSTALLER_INSTALL_KEXTS) != 0)  );

	unsigned int operation = (arg1 & INSTALLER_OPERATION_MASK);
	
	// Note: gSecureTblks will also be set to TRUE later if any private .ovpn or .conf configurations were converted to .tblks
	gSecureTblks = (   doCopyApp
						 || ( (arg1 & INSTALLER_SECURE_TBLKS) != 0 ) );

	openLog(  doClearLog  );
	
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
    
    // We use Deploy located in the Tunnelblick in /Applications, even if we are running from some other location and are copying the application there
#ifndef TBDebug
	gDeployPath = @"/Applications/Tunnelblick.app/Contents/Resources/Deploy";
#else
	gDeployPath = [resourcesPath stringByAppendingPathComponent: @"Deploy"];
#endif
    

	// Log the arguments installer was started with
	unsigned long firstArg = strtoul(argv[1], NULL, 10);
	NSMutableString * argString = [NSMutableString stringWithFormat: @" 0x%04lx", firstArg];
	int i;
	for (  i=2; i<argc; i++  ) {
		[argString appendFormat: @"\n     %@", [NSString stringWithUTF8String: argv[i]]];
	}
	NSString * dateMsg = [[NSDate date] tunnelblickUserLogRepresentation];
	
	appendLog([NSString stringWithFormat: @"Tunnelblick installer started %@. %d arguments:%@", dateMsg, argc - 1, argString]);
	
    gPrivatePath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Tunnelblick/Configurations/"] copy];
    
    // If we copy the .app to /Applications, other changes to the .app affect THAT copy, otherwise they affect the currently running copy
    NSString * appResourcesPath = (doCopyApp
                                   
                                   ? [[[@"/Applications"
                                        stringByAppendingPathComponent: [ourAppName stringByAppendingPathExtension: @"app"]]
                                       stringByAppendingPathComponent: @"Contents"]
                                      stringByAppendingPathComponent: @"Resources"]

                                   : [[resourcesPath copy] autorelease]);
    
    gRealUserID  = getuid();
    gRealGroupID = getgid();

	appendLog([NSString stringWithFormat: @"getuid() = %ld; getgid() = %ld; geteuid() = %ld; getegid() = %ld",
			   (long)gRealUserID, (long)gRealGroupID, (long)geteuid(), (long)getegid()]);

    NSString * firstArg = nil;
    if (  argc > 2  ) {
        firstArg = [gFileMgr stringWithFileSystemRepresentation: argv[2] length: strlen(argv[2])];
        if (   ( gPrivatePath == nil  )
            || ( ! [firstArg hasPrefix: [gPrivatePath stringByAppendingString: @"/"]])  ) {
            errorExitIfAnySymlinkInPath(firstArg);
        }
    }
    NSString * secondArg = nil;
    if (  argc > 3  ) {
        secondArg = [gFileMgr stringWithFileSystemRepresentation: argv[3] length: strlen(argv[3])];
        if (   ( gPrivatePath == nil  )
            || ( ! [secondArg hasPrefix: [gPrivatePath stringByAppendingString: @"/"]])  ) {
        }
    }
    
    //**************************************************************************************************************************
    // (1) Create directories or repair their ownership/permissions as needed
    //        and convert old entries in L_AS_T_TBLKS to the new format, with an bundleId_edition folder enclosing a .tblk
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
    if (  gSecureTblks  ) {
		secureAllTblks();
    }
    
    //**************************************************************************************************************************
    // (8) Install the .plist at firstArg to L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH
    
    if (  operation == INSTALLER_INSTALL_FORCED_PREFERENCES  ) {
		installForcedPreferences(firstArg, secondArg);
    }
    
    //**************************************************************************************************************************
    // (9)
    // If requested, copy or move a .tblk package (also move/copy/create a shadow copy if a private configuration)
    // Like the NSFileManager "movePath:toPath:handler" method, we move by copying, then deleting, because we may be moving
    // from one disk to another (e.g., home folder on network to local hard drive)
	if (   (   (operation == INSTALLER_COPY )
		    || (operation == INSTALLER_MOVE)
            || (operation == INSTALLER_INSTALL_PRIVATE_CONFIG)
			)
		&& firstArg
		&& secondArg  ) {

        if (  operation == INSTALLER_INSTALL_PRIVATE_CONFIG  ) {
            if thirdArg
        }

		doCopyOrMove(firstArg, secondArg, (operation == INSTALLER_MOVE));
    } else {
        if (  operation == INSTALLER_INSTALL_PRIVATE_CONFIG  ) {
            if ( argc < 4) {
                appendLog(@"install private configuration requires a username and a path");
                errorExit();
            }
            NSString * username = firstArg;
            if (  ! [username isEqualToString: gUsername]  ) {
                appendLog(@"install private configuration cannot be done for a different user");
                errorExit();
            }

            doCopyOrMove(firstArg, secondArg, false);
        }
    }
    
    //**************************************************************************************************************************
    // (10)
    // If requested, delete a single file or .tblk package (also deletes the shadow copy if deleting a private configuration)
	
    if (  operation == INSTALLER_DELETE  ) {
		deleteOneTblk(firstArg, secondArg);
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
	if (   firstArg
		&& ( ! secondArg   )
		&& (  operation == INSTALLER_EXPORT_ALL)  ) {
		exportToPath(firstArg);
	}
	
	//**************************************************************************************************************************
	// (13) If requested, import settings from the .tblkSetup at firstArg using username mapping in the string in "secondArg"
	//
	//		NOTE: "secondArg" is a string that specifies the username mapping to use when importing.
	if (   (operation == INSTALLER_IMPORT)
		&& firstArg
		&& secondArg  ) {
		importSetup(firstArg, secondArg);
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
    
	appendLog(@"Tunnelblick installer finished without error");
	
    deleteFlagFile(AUTHORIZED_ERROR_PATH);      // Important to delete error flag file first, to avoid race conditions
    deleteFlagFile(AUTHORIZED_RUNNING_PATH);
	closeLog();
    
    [pool release];
    exit(EXIT_SUCCESS);
}
