/*
 * Copyright 2012, 2013, 2014, 2015, 2016 Jonathan K. Bullard. All rights reserved.
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

// The routines contained in this module may be used by any of the components
// of Tunnelblick. Most of them are used by Tunnelblick itself and installer, openvpnstart, and atsystemstart.
//
// If these routines are used by a target, the target must itself define appendLog(NSString * msg), which should
// append the message to the target's log.


#import "sharedRoutines.h"

#import <netinet/in.h>
#import <sys/mount.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/types.h>
#import <sys/un.h>
#import <CommonCrypto/CommonDigest.h>

#import "defines.h"

#import "NSFileManager+TB.h"
#import "NSString+TB.h"


extern NSString * gDeployPath;

// External reference that must be defined in Tunnelblick, installer, and any other target using this module
void appendLog(NSString * msg);	// Appends a string to the log


BOOL isValidIPAdddress(NSString * ipAddress) {
	
	if (  [ipAddress containsOnlyCharactersInString: @"0123456789."]  ) {
		NSArray * quads = [ipAddress componentsSeparatedByString: @"."];
		if (   ( [quads count] == 4 )
			&& ( [[quads objectAtIndex: 0] unsignedIntValue] < 256 )
			&& ( [[quads objectAtIndex: 1] unsignedIntValue] < 256 )
			&& ( [[quads objectAtIndex: 2] unsignedIntValue] < 256 )
			&& ( [[quads objectAtIndex: 3] unsignedIntValue] < 256 )
			) {
			return TRUE;
		}
	}
	
	return FALSE;
}

// Returns YES if file doesn't exist, or has the specified ownership and permissions
BOOL checkOwnerAndPermissions(NSString * fPath, uid_t uid, gid_t gid, mode_t permsShouldHave)
{
    if (  ! [[NSFileManager defaultManager] fileExistsAtPath: fPath]  ) {
        return YES;
    }
    
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] tbFileAttributesAtPath:fPath traverseLink:YES];
    unsigned long perms = [fileAttributes filePosixPermissions];
    NSNumber *fileOwner = [fileAttributes fileOwnerAccountID];
    NSNumber *fileGroup = [fileAttributes fileGroupOwnerAccountID];
    
    if (   (perms == permsShouldHave)
        && [fileOwner isEqualToNumber:[NSNumber numberWithInt:(int) uid]]
        && [fileGroup isEqualToNumber:[NSNumber numberWithInt:(int) gid]]) {
        return YES;
    }
    
    appendLog([NSString stringWithFormat: @"File %@ is owned by %@:%@ with permissions: %lo but must be owned by %ld:%ld with permissions %lo",
          fPath, fileOwner, fileGroup, perms, (long)uid, (long)gid, (long)permsShouldHave]);
    return NO;
}

NSDictionary * tunnelblickdPlistDictionaryToUse(void) {
    
    NSString * resourcesPath = [[NSBundle mainBundle] resourcePath];
    NSString * plistPath = [resourcesPath stringByAppendingPathComponent: [TUNNELBLICKD_PLIST_PATH lastPathComponent]];
    NSDictionary * plistContents = [NSDictionary dictionaryWithContentsOfFile: plistPath];

#ifndef TBDebug
    return plistContents;
#else
    NSString * daemonPath = [resourcesPath stringByAppendingPathComponent: @"tunnelblickd"];
    NSMutableDictionary * plistContentsM = [[plistContents mutableCopy] autorelease];
    [plistContentsM setObject: daemonPath                     forKey: @"Program"];
    [plistContentsM setObject: [NSNumber numberWithBool: YES] forKey: @"Debug"];
    return [NSDictionary dictionaryWithDictionary: plistContentsM];
#endif
}

NSData * tunnelblickdPlistDataToUse(void) {
    
    NSDictionary * plistContents = tunnelblickdPlistDictionaryToUse();
    if (  ! plistContents  ) {
        return nil;
    }
    
    NSData * data = [NSPropertyListSerialization dataFromPropertyList: plistContents
                                                               format: NSPropertyListXMLFormat_v1_0
                                                     errorDescription: nil];
    return data;
}

NSString * tunnelblickdPathInApp(void) {
    
    NSString * resourcesPath = [[NSBundle mainBundle] resourcePath];
    NSString * path = [resourcesPath stringByAppendingPathComponent: @"tunnelblickd"];
    return path;
}

NSString * sha256HexStringForData (NSData * data) {
    
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    
    if (  data  ) {
        uint8_t digest[CC_SHA256_DIGEST_LENGTH];
        if (  CC_SHA256(data.bytes, data.length, digest)  ) {
            int i;
            for (  i = 0; i < CC_SHA256_DIGEST_LENGTH; i++  ) {
                [output appendFormat:@"%02x", digest[i]];
            }
        }
    }
    
    return output;
}

NSString * hashForTunnelblickdProgramInApp(void) {
    
    NSData * data = [[NSFileManager defaultManager] contentsAtPath: tunnelblickdPathInApp()];
    if (  ! data  ) {
        return nil;
    }
    
    return sha256HexStringForData(data);
}

NSString * hashForTunnelblickdPlistToUse(void) {
    
    NSString * result = sha256HexStringForData(tunnelblickdPlistDataToUse());
    return result;
}

BOOL needToReplaceLaunchDaemon(void) {
    
    // Compares the saved hashes of the tunnelblickd launchctl .plist and the tunnelblickd program with newly-calculated hashes to see if
    // the .plist or program have changed. That can happen when a Sparkle update replaces the Tunnelblick application.
    //
    // If the .plist or program have changed or have bad ownership/permissions,
    //    or one or both hashes don't exist or have bad ownership/permissions,
    //    or the .plist in /Library/LaunchDaemons doesn't exist or doesn't match the new .plist,
    //    or the socket used to communicate with tunnelblickd doesn't exist,
    // then we need to reload tunnelblickd to finish the update.
    //
    // DOES NOT check if tunnelblickd is actually **loaded** -- that requires root access and is done separately by "installer". But if all the
    // other requirements are met, it is likely that tunnelblickd is loaded.
    
    NSFileManager * fm =  [NSFileManager defaultManager];
    NSData * previousDaemonHashData = nil;
    NSData * previousPlistHashData = nil;
    BOOL daemonOk = FALSE;
	
	BOOL tunnelblickdHashOK = (   [fm fileExistsAtPath:    L_AS_T_TUNNELBLICKD_HASH_PATH]
							   && checkOwnerAndPermissions(L_AS_T_TUNNELBLICKD_HASH_PATH, 0, 0, PERMS_SECURED_READABLE)
							   && (  (previousDaemonHashData = [fm contentsAtPath: L_AS_T_TUNNELBLICKD_HASH_PATH]).length != 0  ));
	
	BOOL launchctlPlistHashOK = (   [fm fileExistsAtPath:    L_AS_T_TUNNELBLICKD_LAUNCHCTL_PLIST_HASH_PATH]
								 && checkOwnerAndPermissions(L_AS_T_TUNNELBLICKD_LAUNCHCTL_PLIST_HASH_PATH, 0, 0, PERMS_SECURED_READABLE)
								 && (  (previousPlistHashData = [fm contentsAtPath: L_AS_T_TUNNELBLICKD_LAUNCHCTL_PLIST_HASH_PATH]).length != 0  ));
	
	BOOL tunnelblickdPlistOK = (   [fm fileExistsAtPath:    TUNNELBLICKD_PLIST_PATH]
								&& checkOwnerAndPermissions(TUNNELBLICKD_PLIST_PATH,  0, 0, PERMS_SECURED_READABLE));

	BOOL socketOK = [fm fileExistsAtPath: TUNNELBLICKD_SOCKET_PATH];
	
	if (   tunnelblickdHashOK
		&& launchctlPlistHashOK
		&& tunnelblickdPlistOK
		&& socketOK  ) {
		NSString * previousDaemonHash = [[[NSString alloc] initWithData: previousDaemonHashData encoding: NSUTF8StringEncoding] autorelease];
        NSString * previousPlistHash  = [[[NSString alloc] initWithData: previousPlistHashData  encoding: NSUTF8StringEncoding] autorelease];
        NSDictionary * activePlist    = [NSDictionary dictionaryWithContentsOfFile: TUNNELBLICKD_PLIST_PATH];
		BOOL daemonHashesMatch  = [previousDaemonHash isEqual: hashForTunnelblickdProgramInApp()];
		BOOL plistHashesMatch   = [previousPlistHash  isEqual: hashForTunnelblickdPlistToUse()];
		BOOL activePlistMatches = [activePlist        isEqual: tunnelblickdPlistDictionaryToUse()];
		
		daemonOk =  (   daemonHashesMatch
					 && plistHashesMatch
                     && activePlistMatches  );
		if (  ! daemonOk  ) {
			NSString * msg = [NSString stringWithFormat: @"Need to replace and/or reload 'tunnelblickd':\n"
							  @"    daemonHashesMatch  = %@\n"
							  @"    plistHashesMatch   = %@\n"
							  @"    activePlistMatches = %@",
							  (daemonHashesMatch  ? @"YES" : @"NO"),
							  (plistHashesMatch	  ? @"YES" : @"NO"),
							  (activePlistMatches ? @"YES" : @"NO")];
			appendLog(msg);
		}
	}
	
    if (  ! daemonOk  ) {
		NSString * msg = [NSString stringWithFormat: @"Need to replace and/or reload 'tunnelblickd':\n"
						  @"    tunnelblickdHashOK   = %@\n"
						  @"    launchctlPlistHashOK = %@\n"
						  @"    tunnelblickdPlistOK  = %@\n"
						  @"    socketOK             = %@",
						  (tunnelblickdHashOK	? @"YES" : @"NO"),
						  (launchctlPlistHashOK	? @"YES" : @"NO"),
						  (tunnelblickdPlistOK	? @"YES" : @"NO"),
						  (socketOK				? @"YES" : @"NO")];
		appendLog(msg);
        return TRUE;
    }
	
    return FALSE;
}

OSStatus getSystemVersion(unsigned * major, unsigned * minor, unsigned * bugFix) {
    
    // There seems to be no good way to do this because Gestalt() was deprecated in 10.8 and although it can give correct
    // results in 10.10, it displays an annoying message in the Console log. So we do it this way, suggested in
    // a comment by Jonathan Grynspan at
    // https://stackoverflow.com/questions/11072804/how-do-i-determine-the-os-version-at-runtime-in-os-x-or-ios-without-using-gesta
    
    // Get the version as a string, e.g. "10.8.3"
    NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: @"/System/Library/CoreServices/SystemVersion.plist"];
    if (  dict  ) {
        NSString * productVersion = [dict objectForKey:@"ProductVersion"];
        
        NSArray * parts = [productVersion componentsSeparatedByString: @"."];
        if (   ([parts count] == 3)
			|| ([parts count] == 2)  ) {
            NSString * majorS  = [parts objectAtIndex: 0];
            NSString * minorS  = [parts objectAtIndex: 1];
            NSString * bugFixS = (  [parts count] == 3
								  ? [parts objectAtIndex: 2]
								  : @"0");
            if (   ([majorS  length] != 0)
                && ([minorS  length] != 0)
                && ([bugFixS length] != 0)
                ) {
                int majorI  = [majorS  intValue];
                int minorI  = [minorS  intValue];
                int bugFixI = [bugFixS intValue];
                if (   (majorI  == 10)
                    && (minorI  >= 0)
                    && (bugFixI >= 0)
                    ) {
                    *major  = (unsigned)majorI;
                    *minor  = (unsigned)minorI;
                    *bugFix = (unsigned)bugFixI;
                    return EXIT_SUCCESS;
                } else {
                    appendLog([NSString stringWithFormat: @"getSystemVersion: invalid 'ProductVersion': '%@'; majorI = %d; minorI = %d; bugFixI = %d",
                               productVersion, majorI, minorI, bugFixI]);
                }
            } else {
                appendLog([NSString stringWithFormat: @"getSystemVersion: invalid 'ProductVersion' (one or more empty fields): '%@'", productVersion]);
            }
        } else {
            appendLog([NSString stringWithFormat: @"getSystemVersion: invalid 'ProductVersion' (not n.n.n): '%@'", productVersion]);
        }
    } else {
        appendLog(@"getSystemVersion: could not get dictionary from /System/Library/CoreServices/SystemVersion.plist");
    }
    
    return EXIT_FAILURE;
}

unsigned cvt_atou(const char * s, NSString * description)
{
    int i;
    unsigned u;
    i = atoi(s);
    if (  i < 0  ) {
        appendLog([NSString stringWithFormat: @"Negative values are not allowed for %@", description]);
    }
    u = (unsigned) i;
    return u;
}

id callStack(void) {
    
    return (  [NSThread respondsToSelector: @selector(callStackSymbols)]
            ? (id) [NSThread callStackSymbols]
            : (id) @"not available");
}

BOOL isSanitizedOpenvpnVersion(NSString * s) {
    
    return (   [s containsOnlyCharactersInString: ALLOWED_OPENVPN_VERSION_CHARACTERS]
            && ( 0 == [s rangeOfString: @".."].length )
            && (! [s hasSuffix: @"."])
            && (! [s hasPrefix: @"."])  );
}

BOOL isOnRemoteVolume(NSString * path) {
    
    if (  ! [[NSFileManager defaultManager] fileExistsAtPath: path]  ) {
        // If a parent directory exists, see if it is on a remote volume
        NSString * parent = [[[path copy] autorelease] stringByDeletingLastPathComponent];
        while (   ( [parent length] > 1 )
               && ( ! [[NSFileManager defaultManager] fileExistsAtPath: parent] )  ) {
            parent = [parent stringByDeletingLastPathComponent];
        }
        if ([  parent length] > 1  ) {
            return isOnRemoteVolume(parent);
        }
        appendLog(@"isOnRemoteVolume: No parents for path");
        return NO;
    }
    
    const char * pathC = [path fileSystemRepresentation];
    struct statfs stats_buf;
    
    if (  0 == statfs(pathC, &stats_buf)  ) {
        if (  (stats_buf.f_flags & MNT_LOCAL) == 0  ) {
            return TRUE;
        }
    } else {
        appendLog([NSString stringWithFormat: @"statfs on %@ failed; cannot check if volume is remote\nError was %ld: '%s'\n",
                   path, (unsigned long)errno, strerror(errno)]);
    }
    
    return FALSE;
}

mode_t privateFolderPermissions(NSString * path) {
    
    return (  isOnRemoteVolume(path)
            ? PERMS_PRIVATE_REMOTE_FOLDER
            : PERMS_PRIVATE_FOLDER);
}

gid_t privateFolderGroup(NSString * path) {
    
    return (  isOnRemoteVolume(path)
            ? STAFF_GROUP_ID
            : ADMIN_GROUP_ID);
}

int createDir(NSString * dirPath, unsigned long permissions) {
	
	//**************************************************************************************************************************
	// Function to create a directory with specified permissions
	// Recursively creates all intermediate directories (with the same permissions) as needed
	// Returns 1 if the directory was created or permissions modified
	//         0 if the directory already exists (whether or not permissions could be changed)
	//        -1 if an error occurred. A directory was not created, and an error message was put in the log.
	
    NSNumber     * permissionsAsNumber    = [NSNumber numberWithUnsignedLong: permissions];
    NSDictionary * permissionsAsAttribute = [NSDictionary dictionaryWithObject: permissionsAsNumber forKey: NSFilePosixPermissions];
    BOOL isDir;
    
    if (   [[NSFileManager defaultManager] fileExistsAtPath: dirPath isDirectory: &isDir]  ) {
        if (  isDir  ) {
            // Don't try to change permissions of /Library/Application Support or ~/Library/Application Support
            if (  [dirPath hasSuffix: @"/Library/Application Support"]  ) {
                return 0;
            }
            NSDictionary * attributes = [[NSFileManager defaultManager] tbFileAttributesAtPath: dirPath traverseLink: YES];
            NSNumber * oldPermissionsAsNumber = [attributes objectForKey: NSFilePosixPermissions];
            if (  [oldPermissionsAsNumber isEqualToNumber: permissionsAsNumber] ) {
                return 0;
            }
            if (  [[NSFileManager defaultManager] tbChangeFileAttributes: permissionsAsAttribute atPath: dirPath] ) {
                unsigned long oldPermissions = [oldPermissionsAsNumber unsignedLongValue];
                appendLog([NSString stringWithFormat: @"Changed permissions from %lo to %lo on %@", oldPermissions, permissions, dirPath]);
                return 1;
            }
            appendLog([NSString stringWithFormat: @"Warning: Unable to change permissions from %lo to %lo on %@", [oldPermissionsAsNumber longValue], permissions, dirPath]);
            return 0;
        } else {
            appendLog([NSString stringWithFormat: @"Error: %@ exists but is not a directory", dirPath]);
            return -1;
        }
    }
    
    // No such directory. Create its parent directory (recurse) if necessary
    if (  createDir([dirPath stringByDeletingLastPathComponent], permissions) == -1  ) {
        return -1;
    }
    
    // Parent directory exists. Create the directory we want
    if (  ! [[NSFileManager defaultManager] tbCreateDirectoryAtPath: dirPath attributes: permissionsAsAttribute] ) {
        if (   [[NSFileManager defaultManager] fileExistsAtPath: dirPath isDirectory: &isDir]
            && isDir  ) {
            appendLog([NSString stringWithFormat: @"Warning: Created directory %@ but unable to set permissions to %lo", dirPath, permissions]);
            return 1;
        } else {
            appendLog([NSString stringWithFormat: @"Error: Unable to create directory %@ with permissions %lo", dirPath, permissions]);
            return -1;
        }
    }
    
    return 1;
}

BOOL checkSetItemOwnership(NSString * path, NSDictionary * atts, uid_t uid, gid_t gid, BOOL traverseLink)
{
	// NOTE: THIS ROUTINE MAY ONLY BE USED FROM installer BECAUSE IT REQUIRES ROOT PERMISSIONS.
	//       It is included in sharedRoutines because when ConfigurationConverter's processPathRange()
	//       function is called from installer, it calls createDirWithPermissionAndOwnership(), which
	//       uses checkSetOwnership(), which uses checkSetItemOwnership().
	
	// Changes ownership of a single item to the specified user/group if necessary.
	// Returns YES if changed, NO if not changed

    uid_t oldUid = (uid_t) [[atts fileOwnerAccountID]      unsignedIntValue];
    gid_t oldGid = (gid_t) [[atts fileGroupOwnerAccountID] unsignedIntValue];

	if (  ! (   [[atts fileOwnerAccountID]      isEqualToNumber: [NSNumber numberWithInt: (int) uid]]
			 && [[atts fileGroupOwnerAccountID] isEqualToNumber: [NSNumber numberWithInt: (int) gid]]  )  ) {
		if (  [atts fileIsImmutable]  ) {
			appendLog([NSString stringWithFormat: @"Unable to change ownership of %@ from %d:%d to %d:%d because it is locked",
                       path, (int) oldUid, (int) oldGid, (int) uid, (int) gid]);
			return NO;
		}
		
		int result = 0;
		if (   traverseLink
			|| ( ! [[atts objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink] )
			) {
			result = chown([path fileSystemRepresentation], uid, gid);
		} else {
			result = lchown([path fileSystemRepresentation], uid, gid);
		}
        
		if (  result != 0  ) {
			appendLog([NSString stringWithFormat: @"Unable to change ownership of %@ from %d:%d to %d:%d\nError was '%s'",
                       path, (int) oldUid, (int) oldGid, (int) uid, (int) gid, strerror(errno)]);
			return NO;
		}
		return YES;
	}
    
	return NO;
}

BOOL checkSetOwnership(NSString * path, BOOL deeply, uid_t uid, gid_t gid)
{
	// NOTE: THIS ROUTINE MAY ONLY BE USED FROM installer BECAUSE IT REQUIRES ROOT PERMISSIONS.
	//       It is included in sharedRoutines because when ConfigurationConverter's processPathRange()
	//       function is called from installer, it calls createDirWithPermissionAndOwnership(), which
	//       uses checkSetOwnership().
	
	// Changes ownership of a file or folder to the specified user/group if necessary.
	// If "deeply" is TRUE, also changes ownership on all contents of a folder (except invisible items)
	// Returns YES on success, NO on failure
	
    BOOL changedBase = FALSE;
    BOOL changedDeep = FALSE;
    
    if (  ! [[NSFileManager defaultManager] fileExistsAtPath: path]  ) {
        appendLog([NSString stringWithFormat: @"checkSetOwnership: '%@' does not exist", path]);
        return NO;
    }
    
    NSDictionary * atts = [[NSFileManager defaultManager] tbFileAttributesAtPath: path traverseLink: YES];
    uid_t oldUid = (uid_t) [[atts fileOwnerAccountID]      unsignedIntValue];
    gid_t oldGid = (gid_t) [[atts fileGroupOwnerAccountID] unsignedIntValue];

    if (  ! (   [[atts fileOwnerAccountID]      isEqualToNumber: [NSNumber numberWithUnsignedInt: uid]]
             && [[atts fileGroupOwnerAccountID] isEqualToNumber: [NSNumber numberWithUnsignedInt: gid]]  )  ) {
        if (  [atts fileIsImmutable]  ) {
            appendLog([NSString stringWithFormat: @"Unable to change ownership of %@ from %d:%d to %d:%d because it is locked",
                       path, (int) oldUid, (int) oldGid, (int) uid, (int) gid]);
			return NO;
		}
        
        if (  chown([path fileSystemRepresentation], uid, gid) != 0  ) {
            appendLog([NSString stringWithFormat: @"Unable to change ownership of %@ from %d:%d to %d:%d\nError was '%s'",
                       path, (int) oldUid, (int) oldGid, (int) uid, (int) gid, strerror(errno)]);
            return NO;
        }
        
        changedBase = TRUE;
    }
    
    if (  deeply  ) {
        NSString * file;
        NSDirectoryEnumerator * dirEnum = [[NSFileManager defaultManager] enumeratorAtPath: path];
        while (  (file = [dirEnum nextObject])  ) {
            NSString * filePath = [path stringByAppendingPathComponent: file];
			atts = [[NSFileManager defaultManager] tbFileAttributesAtPath: filePath traverseLink: NO];
			changedDeep = checkSetItemOwnership(filePath, atts, uid, gid, NO) || changedDeep;
			if (  [[atts objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
				changedDeep = checkSetItemOwnership(filePath, atts, uid, gid, YES) || changedDeep;
			} else {
			}
        }
    }
    
    if (  changedBase ) {
        if (  changedDeep  ) {
            appendLog([NSString stringWithFormat: @"Changed ownership of %@ and its contents from %d:%d to %d:%d",
                       path, (int) oldUid, (int) oldGid, (int) uid, (int) gid]);
        } else {
            appendLog([NSString stringWithFormat: @"Changed ownership of %@ from %d:%d to %d:%d",
                       path, (int) oldUid, (int) oldGid, (int) uid, (int) gid]);
        }
    } else {
        if (  changedDeep  ) {
            appendLog([NSString stringWithFormat: @"Changed ownership of the contents of %@ from %d:%d to %d:%d",
                       path, (int) oldUid, (int) oldGid, (int) uid, (int) gid]);
        }
    }
    
    return YES;
}

BOOL checkSetPermissions(NSString * path, mode_t permsShouldHave, BOOL fileMustExist)
{
	// Changes permissions on a file or folder (but not the folder's contents) to specified values if necessary
	// Returns YES on success, NO on failure
	// Also returns YES if no such file or folder and 'fileMustExist' is FALSE
	
    if (  ! [[NSFileManager defaultManager] fileExistsAtPath: path]  ) {
        if (  fileMustExist  ) {
			appendLog([NSString stringWithFormat: @"File '%@' must exist but does not", path]);
            return NO;
        }
        return YES;
    }
	
    NSDictionary * atts = [[NSFileManager defaultManager] tbFileAttributesAtPath: path traverseLink: NO];
    unsigned long  perms = [atts filePosixPermissions];
    
    if (  perms == permsShouldHave  ) {
        return YES;
    }
    
    if (  [atts fileIsImmutable]  ) {
        appendLog([NSString stringWithFormat: @"Cannot change permissions from %lo to %lo because item is locked: %@", (long) perms, (long) permsShouldHave, path]);
        return NO;
    }
    
    if (  chmod([path fileSystemRepresentation], permsShouldHave) != 0  ) {
        appendLog([NSString stringWithFormat: @"Unable to change permissions from %lo to %lo on %@", (long) perms, (long) permsShouldHave, path]);
        return NO;
    }
	
    appendLog([NSString stringWithFormat: @"Changed permissions from %lo to %lo on %@", (long) perms, (long) permsShouldHave, path]);
    return YES;
}

BOOL createDirWithPermissionAndOwnershipWorker(NSString * dirPath, mode_t permissions, uid_t owner, gid_t group, unsigned level)
{
	// Function to create a directory with specified ownership and permissions
	// Recursively creates all intermediate directories (with the same ownership and permissions) as needed
	// Returns YES if the directory existed with the specified ownership and permissions or has been created with them
	
    // Don't try to create or set ownership or permissions on
    //       /Library/Application Support
    //   or ~/Library/Application Support
    if (  [dirPath hasSuffix: @"/Library/Application Support"]  ) {
        return YES;
    }
    
    BOOL isDir;
    
    if (  ! (   [[NSFileManager defaultManager] fileExistsAtPath: dirPath isDirectory: &isDir]
             && isDir )  ) {
        // No such directory. Create its parent directory if necessary
        NSString * parentPath = [dirPath stringByDeletingLastPathComponent];
        if (  ! createDirWithPermissionAndOwnershipWorker(parentPath, permissions, owner, group, level+1)  ) {
            return NO;
        }
        
        // Parent directory exists. Create the directory we want
        if (  mkdir([dirPath fileSystemRepresentation], permissions) != 0  ) {
            appendLog([NSString stringWithFormat: @"Unable to create directory %@ with permissions %lo", dirPath, (long) permissions]);
            return NO;
        }
		
        NSDictionary * atts = [[NSFileManager defaultManager] tbFileAttributesAtPath: dirPath traverseLink: NO];
        unsigned long theOwner = [[atts fileOwnerAccountID] unsignedLongValue];
        unsigned long theGroup = [[atts fileGroupOwnerAccountID] unsignedLongValue];
        appendLog([NSString stringWithFormat: @"Created directory %@ with owner %lu:%lu and permissions %lo",
                   dirPath, (unsigned long) theOwner, (unsigned long) theGroup, (long) permissions]);
    }
	
    
    // Directory exists. Check/set ownership and permissions if this is level 0
    
    if (  level == 0 ) {
        if (  ! checkSetOwnership(dirPath, NO, owner, group)  ) {
            return NO;
        }
        if (  ! checkSetPermissions(dirPath, permissions, YES)  ) {
            return NO;
        }
    }
    
    return YES;
}

BOOL createDirWithPermissionAndOwnership(NSString * dirPath, mode_t permissions, uid_t owner, gid_t group)
{
    return createDirWithPermissionAndOwnershipWorker(dirPath, permissions, owner, group, 0);
}

NSString * fileIsReasonableSize(NSString * path) {
    
    // Returns nil if a regular file and 10MB or smaller, otherwise returns a localized string with an error messsage
    // (Caller should log any error message)
    
    if (  ! path  ) {
        return [NSString stringWithFormat: NSLocalizedString(@"An internal Tunnelblick error occurred%@%@", @"Window text"),
                @": fileIsReasonableSize: path is nil", @""]; // (Empty string 2nd arg so we can use commmon error message that takes two args)
    }
    
    NSDictionary * atts = [[NSFileManager defaultManager] tbFileAttributesAtPath: path traverseLink: NO];
    if (  ! atts  ) {
        return [NSString stringWithFormat: NSLocalizedString(@"An internal Tunnelblick error occurred%@%@", @"Window text"),
                @": fileIsReasonableSize: Cannot get attributes: ", path];
    }
    
    NSString * fileType = [atts objectForKey: NSFileType];
    if (  ! fileType  ) {
        return [NSString stringWithFormat: NSLocalizedString(@"An internal Tunnelblick error occurred%@%@", @"Window text"),
                @": fileIsReasonableSize: Cannot get type: ", path];
    }
    if (  ! [fileType isEqualToString: NSFileTypeRegular]  ) {
        return [NSString stringWithFormat: NSLocalizedString(@"An internal Tunnelblick error occurred%@%@", @"Window text"),
                @": fileIsReasonableSize: Not a regular file:  ", path];
    }
    
    NSNumber * sizeAsNumber = [atts objectForKey: NSFileSize];
    if (  ! sizeAsNumber  ) {
        return [NSString stringWithFormat: NSLocalizedString(@"An internal Tunnelblick error occurred%@%@", @"Window text"),
                @": fileIsReasonableSize: Cannot get size: ", path];
    }
    
    unsigned long long size = [sizeAsNumber unsignedLongLongValue];
    if (  size > 10485760ull  ) {
        return [NSString stringWithFormat: NSLocalizedString(@"File is too large: %@", @"Window text"), path];
    }
    
    return nil;
}

NSString * fileIsReasonableAt(NSString * path) {
    
    // Returns nil or a localized error message

    if (  ! path  ) {
        NSString * errMsg = [NSString stringWithFormat: NSLocalizedString(@"An internal Tunnelblick error occurred%@%@", @"Window text"),
                             @": allFilesAreReasonableIn: path is nil", @""]; // (Empty string 2nd arg so we can use commmon error message that takes two args)
        appendLog(errMsg);
        return errMsg;
    }
    
	if (  invalidConfigurationName(path, PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING)  ) {
		NSString * errMsg = [NSString stringWithFormat: NSLocalizedString(@"Path '%@' contains characters that are not allowed.\n\n"
                                                                          @"Characters that are not allowed: '%s'\n\n", @"Window text"),
                             path, PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING];
        appendLog(errMsg);
        return errMsg;
	}
    
    NSDictionary * atts = [[NSFileManager defaultManager] tbFileAttributesAtPath: path traverseLink: NO];
    if (  ! atts  ) {
        NSString * errMsg = [NSString stringWithFormat: NSLocalizedString(@"An internal Tunnelblick error occurred%@%@", @"Window text"),
                             @": allFilesAreReasonableIn: Cannot get attributes: ", path];
        appendLog(errMsg);
        return errMsg;
    }
    
    NSString * fileType = [atts objectForKey: NSFileType];
    if (  ! fileType  ) {
        NSString * errMsg = [NSString stringWithFormat: NSLocalizedString(@"An internal Tunnelblick error occurred%@%@", @"Window text"),
                             @": allFilesAreReasonableIn: Cannot get type: ", path];
        appendLog(errMsg);
        return errMsg;
    }
    
    if (  [fileType isEqualToString: NSFileTypeRegular]  ) {
        NSString * errMsg = fileIsReasonableSize(path);
        if (  errMsg  ) {
            appendLog(errMsg);
            return errMsg;
        }
    } else if (   ( ! [fileType isEqualToString: NSFileTypeDirectory])
               && ( ! [fileType isEqualToString: NSFileTypeSymbolicLink]  )  ) {
        NSString * errMsg = [NSString stringWithFormat: NSLocalizedString(@"An internal Tunnelblick error occurred%@%@", @"Window text"),
                             @": allFilesAreReasonableIn: Not a regular file, folder, or symlink: ", path];
        appendLog(errMsg);
        return errMsg;
    }
    
    return nil;
}

NSString * allFilesAreReasonableIn(NSString * path) {
	
    // Returns nil if a configuration file (.conf or .ovpn), or all files in a folder, are 10MB or smaller, have safe paths, and are readable.
    // Returns a localized string with an error messsage otherwise.
    
    if (  ! path  ) {
        NSString * errMsg = [NSString stringWithFormat: NSLocalizedString(@"An internal Tunnelblick error occurred%@%@", @"Window text"),
                             @": allFilesAreReasonableIn: path is nil", @""]; // (Empty string 2nd arg so we can use commmon error message that takes two args)
        appendLog(errMsg);
        return errMsg;
    }
    
	if (  invalidConfigurationName(path, PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING)  ) {
		NSString * errMsg = [NSString stringWithFormat: NSLocalizedString(@"Path '%@' contains characters that are not allowed.\n\n"
                                                                          @"Characters that are not allowed: '%s'\n\n", @"Window text"),
				path, PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING];
        appendLog(errMsg);
        return errMsg;
	}
    
    NSString * ext = [path pathExtension];
    
    // Process .ovpn and .conf files
    if (   [ext isEqualToString: @"ovpn"]
        || [ext isEqualToString: @"conf"]  ) {
        return fileIsReasonableAt(path);
    }
    
    // Process a folder
    BOOL isDir = FALSE;
    if (   [[NSFileManager defaultManager] fileExistsAtPath: path isDirectory: &isDir]
        && ( ! isDir)  ) {
        NSString * errMsg = [NSString stringWithFormat: NSLocalizedString(@"An internal Tunnelblick error occurred%@%@", @"Window text"),
                             @": allFilesAreReasonableIn: Not a folder, .conf, or .ovpn: ", path];
        appendLog(errMsg);
        return errMsg;
    }
    
    NSString * file;
    NSDirectoryEnumerator * dirEnum = [[NSFileManager defaultManager] enumeratorAtPath: path];
    if (  ! dirEnum  ) {
		NSString * errMsg = [NSString stringWithFormat: NSLocalizedString(@"An internal Tunnelblick error occurred%@%@", @"Window text"),
                             @": allFilesAreReasonableIn: Cannot get enumeratorAtPath: ", path];
        appendLog(errMsg);
        return errMsg;
    }
    
    while (  (file = [dirEnum nextObject])  ) {
        NSString * msg = fileIsReasonableAt([path stringByAppendingPathComponent: file]);
        if (  msg  ) {
            return msg;
        }
    }
    
    return nil;
}

NSDictionary * highestEditionForEachBundleIdinL_AS_T(void) {
	
	// Returns a dictionary with keys = bundle IDs that appear in L_AS_T.
	// The object for each key is a string with the highest edition of that bundle that appears in L_AS_T.
	
	NSMutableDictionary * bundleIdEditions = [[[NSMutableDictionary alloc] initWithCapacity: 10] autorelease]; // Key = bundleId; object = edition
    
	NSDirectoryEnumerator * outerDirEnum = [[NSFileManager defaultManager] enumeratorAtPath: L_AS_T_TBLKS];
    NSString * bundleIdAndEdition;
    while (  (bundleIdAndEdition = [outerDirEnum nextObject])  ) {
        [outerDirEnum skipDescendents];
        NSString * containerPath = [L_AS_T_TBLKS stringByAppendingPathComponent: bundleIdAndEdition];
        BOOL isDir;
        if (   ( ! [bundleIdAndEdition hasPrefix: @"."] )
            && ( ! [bundleIdAndEdition hasSuffix: @".tblk"] )
            && [[NSFileManager defaultManager] fileExistsAtPath: containerPath isDirectory: &isDir]
            && isDir  ) {
            NSString * bundleId = [bundleIdAndEdition stringByDeletingPathEdition];
            if (  ! bundleId  ) {
                appendLog([NSString stringWithFormat: @"Container path does not have a bundleId: %@", containerPath]);
                continue;
            }
            NSString * edition  = [bundleIdAndEdition pathEdition];
            if (  ! edition  ) {
                appendLog([NSString stringWithFormat: @"Container path does not have an edition: %@", containerPath]);
				continue;
            }
            NSString * highestEdition = [bundleIdEditions objectForKey: bundleId];
            if (   ( ! highestEdition)
                || ( [highestEdition compare: edition options: NSNumericSearch] == NSOrderedAscending )  ) {
                [bundleIdEditions setObject: edition forKey: bundleId];
            }
        } else {
            if (  ! [containerPath hasSuffix: @".tblk"]  ) {
				appendLog([NSString stringWithFormat: @"Container path is invisible or not a folder: %@", containerPath]);
			}
        }
    }
	
	return bundleIdEditions;
}

unsigned int getFreePort(unsigned int startingPort)
{
	// Returns a free port or 0 if no free port is available
	
    if (  startingPort > 65535  ) {
        appendLog([NSString stringWithFormat: @"getFreePort: startingPort must be < 65536; it was %u", startingPort]);
        return 0;
    }
    
    unsigned int resultPort = startingPort - 1;

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (  fd == -1  ) {
        return 0;
    }
    
    int result = 0;
    
    do {
        struct sockaddr_in address;
        unsigned len = sizeof(struct sockaddr_in);
        if (  len > UCHAR_MAX  ) {
            appendLog([NSString stringWithFormat: @"getFreePort: sizeof(struct sockaddr_in) is %u, which is > UCHAR_MAX -- can't fit it into address.sin_len", len]);
            close(fd);
            return 0;
        }
        if (  resultPort >= 65535  ) {
            appendLog([NSString stringWithFormat: @"getFreePort: cannot get a free port between %u and 65536", startingPort - 1]);
            close(fd);
            return 0;
        }
        resultPort++;
        
        address.sin_len = (unsigned char)len;
        address.sin_family = AF_INET;
        address.sin_port = htons(resultPort);
        address.sin_addr.s_addr = htonl(0x7f000001); // 127.0.0.1, localhost
        
        memset(address.sin_zero,0,sizeof(address.sin_zero));
        
        result = bind(fd, (struct sockaddr *)&address,sizeof(address));
        
    } while (result!=0);
    
    close(fd);
    
    return resultPort;
}

BOOL invalidConfigurationName(NSString * name, const char badCharsC[])
{
	unsigned i;
	for (  i=0; i<[name length]; i++  ) {
		unichar c = [name characterAtIndex: i];
		if (   (c < 0x0020)
			|| (c == 0x007F)
			|| (c == 0x00FF)  ) {
			return YES;
		}
	}
	
	const char * nameC          = [name UTF8String];
	
	return (   ( [name length] == 0)
            || ( [name hasPrefix: @"."] )
            || ( [name rangeOfString: @".."].length != 0)
            || ( NULL != strpbrk(nameC, badCharsC) )
            );
}

BOOL itemIsVisible(NSString * path)
{
	// Returns YES if the final component of a path does NOT start  with a period
    
    return ! [[path lastPathComponent] hasPrefix: @"."];
}

BOOL secureOneFolder(NSString * path, BOOL isPrivate, uid_t theUser)
{
    // Makes sure that ownership/permissions of a FOLDER AND ITS CONTENTS are secure (a .tblk, or the shared, Deploy, private, or alternate config folder)
    //
    // 'theUser' is used only if 'isPrivate' is TRUE. It should be the uid of the user who should own the folder and its contents.
    //
    // Returns YES if successfully secured everything, otherwise returns NO
    //
    // There is a SIMILAR function in openvpnstart: exitIfTblkNeedsRepair
    //
    // There is a SIMILAR function in MenuController: needToSecureFolderAtPath
    
	uid_t user;
	gid_t group;
	
    // Permissions:
    mode_t folderPerms;         //  For folders
    mode_t scriptPerms;         //  For files with .sh extensions
    mode_t executablePerms;     //  For files with .executable extensions (only appear in a Deploy folder
    mode_t publicReadablePerms; //  For files named forced-preferences (only appear in a Deploy folder) or Info.plist
    mode_t otherPerms;          //  For all other files
    
    if (  isPrivate  ) {
		user  = theUser;     // Private files are owned by <user>
        if (  user == 0  ) {
            appendLog(@"Tunnelblick internal error: secureOneFolder: No user");
            return NO;
        }
        
        if (  isOnRemoteVolume(path)  ) {
            group = STAFF_GROUP_ID;
            folderPerms         = PERMS_PRIVATE_REMOTE_FOLDER;
            scriptPerms         = PERMS_PRIVATE_REMOTE_SCRIPT;
            executablePerms     = PERMS_PRIVATE_REMOTE_EXECUTABLE;
            publicReadablePerms = PERMS_PRIVATE_REMOTE_READABLE;
            otherPerms          = PERMS_PRIVATE_REMOTE_OTHER;
        } else {
            group = ADMIN_GROUP_ID;
            folderPerms         = PERMS_PRIVATE_FOLDER;
            scriptPerms         = PERMS_PRIVATE_SCRIPT;
            executablePerms     = PERMS_PRIVATE_EXECUTABLE;
            publicReadablePerms = PERMS_PRIVATE_READABLE;
            otherPerms          = PERMS_PRIVATE_OTHER;
        }
    } else {
        user  = 0;          // Secured files are owned by root:wheel
        group = 0;
		folderPerms         = PERMS_SECURED_FOLDER;
        scriptPerms         = PERMS_SECURED_SCRIPT;
        executablePerms     = PERMS_SECURED_EXECUTABLE;
        publicReadablePerms = PERMS_SECURED_READABLE;
        otherPerms          = PERMS_SECURED_OTHER;
    }

    BOOL result = checkSetOwnership(path, YES, user, group);
    
    result = result && checkSetPermissions(path, folderPerms, YES);
    
    BOOL isDir;
    NSString * file;
    NSDirectoryEnumerator * dirEnum = [[NSFileManager defaultManager] enumeratorAtPath: path];
	
    while (  (file = [dirEnum nextObject])  ) {
        
        NSString * filePath = [path stringByAppendingPathComponent: file];
        NSString * ext  = [file pathExtension];
        
        if (   [[NSFileManager defaultManager] fileExistsAtPath: filePath isDirectory: &isDir]
            && isDir  ) {
            result = result && checkSetPermissions(filePath, folderPerms, YES);
            
        } else if ( [ext isEqualToString: @"sh"]  ) {
            result = result && checkSetPermissions(filePath, scriptPerms, YES);
            
        } else if (   [ext isEqualToString: @"strings"]
                   || [ext isEqualToString: @"png"]
                   || [[file lastPathComponent] isEqualToString:@"Info.plist"]  ) {
            result = result && checkSetPermissions(filePath, publicReadablePerms, YES);
            
		} else if (  [path hasPrefix: gDeployPath]  ) {
            if (   [filePath hasPrefix: [gDeployPath stringByAppendingPathComponent: @"Welcome"]]
                || [[file lastPathComponent] isEqualToString:@"forced-preferences.plist"]  ) {
                result = result && checkSetPermissions(filePath, publicReadablePerms, YES);
                
            } else if (  [ext isEqualToString:@"executable"]  ) {
                result = result && checkSetPermissions(filePath, executablePerms, YES);
            } else {
                result = result && checkSetPermissions(filePath, otherPerms, YES);
            }
        } else {
            result = result && checkSetPermissions(filePath, otherPerms, YES);
        }
    }
    
	return result;
}

NSData * availableDataOrError(NSFileHandle * file) {
	
	// This routine is a modified version of a method from http://dev.notoptimal.net/search/label/NSTask
	// Slightly modified version of Chris Suter's category function used as a private function
    
    NSDate * timeout = [NSDate dateWithTimeIntervalSinceNow: 2.0];
    
	for (;;) {
		
		NSDate * now = [NSDate date];
        if (  [now compare: timeout] == NSOrderedDescending  ) {
            appendLog(@"availableDataOrError: Taking a long time checking for data from a pipe");
            timeout = [NSDate dateWithTimeIntervalSinceNow: 2.0];
        }
		
		@try {
			return [file availableData];
		} @catch (NSException *e) {
			if ([[e name] isEqualToString:NSFileHandleOperationException]) {
				if ([[e reason] isEqualToString: @"*** -[NSConcreteFileHandle availableData]: Interrupted system call"]) {
					continue;
				}
				return nil;
			}
			@throw;
		}
	}
}

NSDictionary * getSafeEnvironment(bool includeIV_GUI_VER) {
    
    // Create our own environment to guard against Shell Shock (BashDoor) and similar vulnerabilities in bash
    // (Even if bash is not being launched directly, whatever is being launched could invoke bash;
	//  for example, openvpnstart launches openvpn which can invoke bash for scripts)
    //
    // This environment consists of several standard shell variables
    // If specified, we add the 'IV_GUI_VER' environment variable,
    //                          which is set to "<bundle-id><space><build-number><space><human-readable-version>"
    //
	// A modified version of this routine is in process-network-changes
    // A modified version of this routine is in tunnelblickd
	
    NSMutableDictionary * env = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                 STANDARD_PATH,          @"PATH",
                                 NSTemporaryDirectory(), @"TMPDIR",
                                 NSUserName(),           @"USER",
                                 NSUserName(),           @"LOGNAME",
                                 NSHomeDirectory(),      @"HOME",
                                 TOOL_PATH_FOR_BASH,     @"SHELL",
                                 @"unix2003",            @"COMMAND_MODE",
                                 nil];
    
    if (  includeIV_GUI_VER  ) {
        // We get the Info.plist contents as follows because NSBundle's objectForInfoDictionaryKey: method returns the object as it was at
        // compile time, before the TBBUILDNUMBER is replaced by the actual build number (which is done in the final run-script that builds Tunnelblick)
        // By constructing the path, we force the objects to be loaded with their values at run time.
        NSString * plistPath    = [[[[NSBundle mainBundle] bundlePath]
                                    stringByDeletingLastPathComponent] // Remove /Resources
                                   stringByAppendingPathComponent: @"Info.plist"];
        NSDictionary * infoDict = [NSDictionary dictionaryWithContentsOfFile: plistPath];
        NSString * bundleId     = [infoDict objectForKey: @"CFBundleIdentifier"];
        NSString * buildNumber  = [infoDict objectForKey: @"CFBundleVersion"];
        NSString * fullVersion  = [infoDict objectForKey: @"CFBundleShortVersionString"];
        NSString * guiVersion   = [NSString stringWithFormat: @"%@ %@ %@", bundleId, buildNumber, fullVersion];
        
        [env setObject: guiVersion forKey: @"IV_GUI_VER"];
    }
    
    return [NSDictionary dictionaryWithDictionary: env];
}

NSString * newTemporaryDirectoryPath(void)
{
    //**********************************************************************************************
    // Start of code for creating a temporary directory from http://cocoawithlove.com/2009/07/temporary-files-and-folders-in-cocoa.html
    // Modified to check for malloc returning NULL, use strlcpy, and use more readable length for stringWithFileSystemRepresentation
    
    NSString   * tempDirectoryTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent: @"Tunnelblick-XXXXXX"];
    const char * tempDirectoryTemplateCString = [tempDirectoryTemplate fileSystemRepresentation];
    
    size_t bufferLength = strlen(tempDirectoryTemplateCString) + 1;
    char * tempDirectoryNameCString = (char *) malloc( bufferLength );
    if (  ! tempDirectoryNameCString  ) {
        appendLog(@"Unable to allocate memory for a temporary directory name");
        exit(-1);
    }
    
    strlcpy(tempDirectoryNameCString, tempDirectoryTemplateCString, bufferLength);
    
    char * dirPath = mkdtemp(tempDirectoryNameCString);
    if (  ! dirPath  ) {
        appendLog(@"Unable to create a temporary directory");
        exit(-1);
    }
    
    NSString *tempFolder = [[NSFileManager defaultManager] stringWithFileSystemRepresentation: tempDirectoryNameCString
                                                                                       length: strlen(tempDirectoryNameCString)];
    // Change from /var to /private/var to avoid using a symlink
    if (  [tempFolder hasPrefix: @"/var/"]  ) {
        NSDictionary * fileAttributes = [[NSFileManager defaultManager] tbFileAttributesAtPath: @"/var" traverseLink: NO];
        if (  [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
            if ( [[[NSFileManager defaultManager] tbPathContentOfSymbolicLinkAtPath: @"/var"] isEqualToString: @"private/var"]  ) {
                NSString * afterVar = [tempFolder substringFromIndex: 5];
                tempFolder = [@"/private/var" stringByAppendingPathComponent:afterVar];
            } else {
                appendLog(@"Warning: /var is a symlink but not to /private/var so it is being left intact");
            }
        }
    }
    
    free(tempDirectoryNameCString);
    
    // End of code from http://cocoawithlove.com/2009/07/temporary-files-and-folders-in-cocoa.html
    //**********************************************************************************************
    
    return [tempFolder retain];
}


OSStatus runTool(NSString * launchPath,
                 NSArray  * arguments,
                 NSString * * stdOutStringPtr,
                 NSString * * stdErrStringPtr) {
	
	// Runs a command or script, returning the execution status of the command, stdout, and stderr
	
    // Send stdout and stderr to files in a temporary directory
    
    NSString * tempDir    = [newTemporaryDirectoryPath() autorelease];
    
    NSString * stdOutPath = [tempDir stringByAppendingPathComponent: @"stdout.txt"];
    NSString * stdErrPath = [tempDir stringByAppendingPathComponent: @"stderr.txt"];
    
	if (  ! [[NSFileManager defaultManager] createFileAtPath: stdOutPath contents: [NSData data] attributes: nil]  ) {
        appendLog([NSString stringWithFormat: @"Catastrophic error: Could not get create %@", stdOutPath]);
        exit(EXIT_FAILURE);
	}
	if (  ! [[NSFileManager defaultManager] createFileAtPath: stdErrPath contents: [NSData data] attributes: nil]  ) {
        appendLog([NSString stringWithFormat: @"Catastrophic error: Could not get create %@", stdErrPath]);
        exit(EXIT_FAILURE);
	}
    
    NSFileHandle * outFile = [NSFileHandle fileHandleForWritingAtPath: stdOutPath];
    if (  ! outFile  ) {
        appendLog(@"Catastrophic error: Could not get file handle for stdout.txt");
        exit(EXIT_FAILURE);
    }
    NSFileHandle * errFile = [NSFileHandle fileHandleForWritingAtPath: stdErrPath];
    if (  ! errFile  ) {
        appendLog(@"Catastrophic error: Could not get file handle for stderr.txt");
        exit(EXIT_FAILURE);
    }
    
    NSTask * task = [[[NSTask alloc] init] autorelease];
    if (  ! task  ) {
        appendLog(@"Catastrophic error: Could not create NSTask instance");
        exit(EXIT_FAILURE);
    }
    
    [task setLaunchPath: launchPath];
    [task setArguments:  arguments];
    [task setCurrentDirectoryPath: @"/private/tmp"];
    [task setStandardOutput: outFile];
    [task setStandardError:  errFile];
    [task setEnvironment: getSafeEnvironment([[launchPath lastPathComponent] isEqualToString: @"openvpn"])];
    
    [task launch];
    
    [task waitUntilExit];
    
	OSStatus status = [task terminationStatus];
	
    [outFile closeFile];
    [errFile closeFile];
    
    NSString * stdOutString = [NSString stringWithContentsOfFile: stdOutPath encoding: NSUTF8StringEncoding error: nil];
    NSString * stdErrString = [NSString stringWithContentsOfFile: stdErrPath encoding: NSUTF8StringEncoding error: nil];
    
    [[NSFileManager defaultManager] tbRemoveFileAtPath: tempDir handler: nil]; // Ignore errors; there is nothing we can do about them
    
    NSString * message = nil;
    
	if (  stdOutStringPtr  ) {
        *stdOutStringPtr = [[stdOutString retain] autorelease];
    } else if (   (status != EXIT_SUCCESS)
               && (0 != [stdOutString length])  )  {
        message = [NSString stringWithFormat: @"stdout = '%@'", stdOutString];
    }
	
	if (  stdErrStringPtr  ) {
		*stdErrStringPtr = [[stdErrString retain] autorelease];
    } else if (   (status != EXIT_SUCCESS)
               && (0 != [stdErrString length])  )  {
        message = [NSString stringWithFormat: @"%@stderr = '%@'", (message ? @"\n" : @""), stdErrString];
	}
    
    if (  message  ) {
        appendLog([NSString stringWithFormat: @"'%@' returned status = %ld\n%@", [launchPath lastPathComponent], (long)status, message]);
    }
    
	return status;
}

void startTool(NSString * launchPath,
			   NSArray  * arguments) {
	
	// Launches a command or script, returning immediately
	
    NSTask * task = [[[NSTask alloc] init] autorelease];
    
    [task setLaunchPath: launchPath];
    [task setArguments:  arguments];
    [task setCurrentDirectoryPath: @"/private/tmp"];
    [task setEnvironment: getSafeEnvironment([[launchPath lastPathComponent] isEqualToString: @"openvpn"])];
    
    [task launch];
}

// Returns with a bitmask of kexts that are loaded that can be unloaded
// Launches "kextstat" to get the list of loaded kexts, and does a simple search
unsigned getLoadedKextsMask(void) {
    
    NSString * stdOutString = nil;
    
    OSStatus status = runTool(TOOL_PATH_FOR_KEXTSTAT,
                              [NSArray array],
                              &stdOutString,
                              nil);
    if (  status != noErr  ) {
        appendLog([NSString stringWithFormat: @"kextstat returned status %ld", (long) status]);
        return 0;
    }
    
    unsigned bitMask = 0;
    
    if (  [stdOutString rangeOfString: @"foo.tap"].length != 0  ) {
        bitMask = OPENVPNSTART_FOO_TAP_KEXT;
    }
    if (  [stdOutString rangeOfString: @"foo.tun"].length != 0  ) {
        bitMask = bitMask | OPENVPNSTART_FOO_TUN_KEXT;
    }
    if (  [stdOutString rangeOfString: @"net.tunnelblick.tap"].length != 0  ) {
        bitMask = bitMask | OPENVPNSTART_OUR_TAP_KEXT;
    }
    if (  [stdOutString rangeOfString: @"net.tunnelblick.tun"].length != 0  ) {
        bitMask = bitMask | OPENVPNSTART_OUR_TUN_KEXT;
    }
    
    return bitMask;
}

NSArray * tokensFromConfigurationLine(NSString * line) {
	// Returns an array of whitespace-separated tokens from one line of
	// a configuration file, skipping comments.
    //
    // Ignores errors such as unbalanced quotes or a backslash at the end of the line
    
    NSMutableArray * tokens = [[[NSMutableArray alloc] initWithCapacity: 10]  autorelease];
    
    BOOL inSingleQuote = FALSE;
    BOOL inDoubleQuote = FALSE;
    BOOL inBackslash   = FALSE;
    BOOL inToken       = FALSE;
    
    // No token so far
	NSRange tokenRange = NSMakeRange(NSNotFound, 0);
    
    unsigned inputIx = 0;
	while (  inputIx < [line length]  ) {
        
		unichar c = [line characterAtIndex: inputIx];
        
        // If have started token, mark the end of the token as the current position (for now)
        if (  inToken  ) {
            tokenRange.length = inputIx - tokenRange.location;
        }
        
        inputIx++;
        
        if ( inBackslash  ) {
            inBackslash = FALSE;
            continue;
        }
        
		if (  inDoubleQuote  ) {
			if (  c == '"'  ) {
                tokenRange.length++;  // double-quote marks end of token and is part of the token
                [tokens addObject: [line substringWithRange: tokenRange]];
                inDoubleQuote = FALSE;
                inToken = FALSE;
                tokenRange = NSMakeRange(NSNotFound, 0);
            }
            
            continue;
        }
        
        if (  inSingleQuote  ) {
            if (  c == '\''  ) {
                tokenRange.length++;  // single-quote marks end of token and is part of the token
                [tokens addObject: [line substringWithRange: tokenRange]];
                inSingleQuote = FALSE;
                inToken = FALSE;
                tokenRange = NSMakeRange(NSNotFound, 0);
            }
            
            continue;
        }
		
		if (  [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember: c]  ) {
			if (  inToken  ) {
                [tokens addObject: [line substringWithRange: tokenRange]];  // whitespace marks end of token but is not part of the token
                inToken = FALSE;
                tokenRange = NSMakeRange(NSNotFound, 0);
                continue;
			} else {
				continue;           // whitespace comes before token, so just skip past it
			}
		}
		
		if (   (c == '#')
			|| (c == ';')  ) {
            if (  inToken  ) {
                [tokens addObject: [line substringWithRange: tokenRange]];  // comment marks end of token but is not part of the token
                inToken = FALSE;
                tokenRange = NSMakeRange(NSNotFound, 0);
            }
            break;
		}
		
        if (  c == '"'  ) {
            if (  inToken  ) {
                inputIx--;          // next time through, start with double-quote
                [tokens addObject: [line substringWithRange: tokenRange]];  // double-quote marks end of token but is not part of the token
                inToken = FALSE;
                tokenRange = NSMakeRange(NSNotFound, 0);
                continue;
            }
            
            inDoubleQuote = TRUE;				// processing a double-quote string
			tokenRange.location = inputIx - 1;  // This is the start of the token
			tokenRange.length   = 1;
			inToken = TRUE;
			continue;
            
        } else if (  c == '\''  ) {
            if (   inToken  ) {
                inputIx--;						// next time through, start with single-quote
                [tokens addObject: [line substringWithRange: tokenRange]];  // single-quote marks end of token
                inToken = FALSE;
                tokenRange = NSMakeRange(NSNotFound, 0);
                continue;
            }
            
            inSingleQuote = TRUE;				// processing a single-quote string
			tokenRange.location = inputIx - 1;  // This is the start of the token
			tokenRange.length   = 1;
			inToken = TRUE;
            continue;
            
        } else if (  c == '\\'  ) {
            inBackslash = TRUE;
        } else {
            if (  inToken  ) {
                tokenRange.length = inputIx - tokenRange.location; // Have started token: include this character in it
            } else {
                tokenRange.location = inputIx - 1;                 // Have NOT started token: this is the start of the token
                tokenRange.length   = 1;
                inToken = TRUE;
            }
		}
    }
    
    if ( inToken  ) {
        [tokens addObject: [line substringWithRange: tokenRange]];  // single-quote marks end of token
    }
    
    return tokens;
}

NSString * lineAfterRemovingNulCharacters(NSString * line, NSMutableString * outputString) {
	
	NSMutableString * outputLine = [[[NSMutableString alloc] initWithCapacity: [line length]] autorelease];
	unsigned i;
	for (  i=0; i<[line length]; i++  ) {
		NSString * chs = [line substringWithRange: NSMakeRange(i, 1)];
		if (  ! [chs isEqualToString: @"\0"]  ) {
			[outputLine appendString: chs];
		}
	}
	
	if (  [line length] != [outputLine length]  ) {
        [outputString appendString: @" [At least one NUL character has been removed from the next line]\n"];
    }
    
	return [NSString stringWithString: outputLine];
}

OSStatus runTunnelblickd(NSString * command, NSString ** stdoutString, NSString ** stderrString) {
    
    int sockfd;
    int n;
    
    const char * requestToServer = [[NSString stringWithFormat: @"%s%@", TUNNELBLICKD_OPENVPNSTART_HEADER_C, command] UTF8String];
    const char * socketPath = [TUNNELBLICKD_SOCKET_PATH UTF8String];
    
#define SOCKET_BUF_SIZE 1024
	char buffer[SOCKET_BUF_SIZE];
    
    struct sockaddr_un socket_data;
    
    // Create a Unix domain socket as a stream
    sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (  sockfd < 0  ) {
        appendLog([NSString stringWithFormat: @"runTunnelblickd: Error creating Unix domain socket; errno = %u; error was '%s'", errno, strerror(errno)]);
        goto error2;
    }
    
    // Connect to the tunnelblickd server's socket
    bzero((char *) &socket_data, sizeof(socket_data));
    socket_data.sun_len    = sizeof(socket_data);
    socket_data.sun_family = AF_UNIX;
    if (  sizeof(socket_data.sun_path) <= strlen(socketPath)  ) {
        appendLog([NSString stringWithFormat: @"runTunnelblickd: socketPath is %lu bytes long but there is only room for %lu bytes in socket_data.sun_path", strlen(socketPath), sizeof(socket_data.sun_path)]);
        goto error1;
    }
    memmove((char *)&socket_data.sun_path, (char *)socketPath, strlen(socketPath));
    if (  connect(sockfd, (struct sockaddr *)&socket_data, sizeof(socket_data)  ) < 0) {
        appendLog([NSString stringWithFormat: @"runTunnelblickd: Error connecting to tunnelblickd server socket; errno = %u; error was '%s'", errno, strerror(errno)]);
        goto error1;
    }
    
    // Send our request to the socket
    const char * buf_ptr = requestToServer;
    size_t bytes_to_write = strlen(requestToServer);
    while (  bytes_to_write != 0  ) {
        n = write(sockfd, buf_ptr, bytes_to_write);
        if (  n < 0  ) {
            appendLog([NSString stringWithFormat: @"runTunnelblickd: Error writing to tunnelblickd server socket; errno = %u; error was '%s'", errno, strerror(errno)]);
            goto error1;
        }
        
        buf_ptr += n;
        bytes_to_write -= n;
//		appendLog([NSString stringWithFormat: @"runTunnelblickd: Wrote %lu bytes to tunnelblickd server socket: '%@'", (unsigned long)n, command]);
    }
    
    // Receive from the socket until we receive a \0
    // Must receive all data within 30 seconds or we assume tunnelblickd is not responding properly and abort
    
    // Set the socket to use non-blocking I/O (but we've already done the output, so we're really just doing non-blocking input)
    if (  -1 == fcntl(sockfd, F_SETFL,  O_NONBLOCK)  ) {
        appendLog([NSString stringWithFormat: @"runTunnelblickd: Error from fcntl(sockfd, F_SETFL,  O_NONBLOCK) with tunnelblickd server socket; errno = %u; error was '%s'", errno, strerror(errno)]);
        goto error1;
    }
    
    // Build up output as NSMutableData and convert to a string when it is complete.
    NSMutableData * data = [NSMutableData dataWithCapacity: 4096];
    BOOL foundZeroByte = FALSE;
    
    NSDate * timeoutDate = [NSDate dateWithTimeIntervalSinceNow: 30.0];
	useconds_t sleepTimeMicroseconds = 10000;	// First sleep is 0.10 seconds; each sleep thereafter will be doubled, up to 5.0 seconds
	
    while (  [(NSDate *)[NSDate date] compare: timeoutDate] == NSOrderedAscending  ) {
        bzero((char *)buffer, SOCKET_BUF_SIZE);
        n = read(sockfd, (char *)buffer, SOCKET_BUF_SIZE - 1);
        if (   (n == -1)
            && (errno == EAGAIN)  ) {
			sleepTimeMicroseconds *= 2;
			if (  sleepTimeMicroseconds > 5000000  ) {
				sleepTimeMicroseconds = 5000000;
                appendLog([NSString stringWithFormat: @"runTunnelblickd: no data available from tunnelblickd socket; sleeping %f seconds...", ((float)sleepTimeMicroseconds)/1000000.0]);
			}
            usleep(sleepTimeMicroseconds);
            continue;
        } else if (  n < 0  ) {
            appendLog([NSString stringWithFormat: @"runTunnelblickd: Error reading from tunnelblickd socket; status = %d; errno = %u; error was '%s'", n, errno, strerror(errno)]);
            goto error1;
        }
        
        if (  n > 0  ) {
            NSData * newData = [NSData dataWithBytes: buffer length: n];
            [data appendData: newData];
            buffer[n] = '\0';
            if (  strchr(buffer, '\0') != (buffer + n)  ) {
                if (  strchr(buffer, '\0') != (buffer + n - 1)  ) {
                    appendLog(@"runTunnelblickd: Data from tunnelblickd after the zero byte that should terminate the data");
                    goto error1;
                }
                foundZeroByte = TRUE;
                break;
            }
        }
    }
    
    shutdown(sockfd, SHUT_RDWR);
    close(sockfd);
    
    if (  ! foundZeroByte  ) {
        appendLog([NSString stringWithFormat: @"runTunnelblickd: tunnelblickd is not responding; received %lu bytes", [data length]]);
        goto error2;
    }
    
    NSString * output = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    if (  ! output  ) {
        appendLog([NSString stringWithFormat: @"runTunnelblickd: Data from tunnelblickd was not valid UTF-8; data was '%@'", data]);
        goto error2;
    }
    NSRange rngNl = [output rangeOfString: @"\n"];
    if (  rngNl.length == 0  ) {
        appendLog([NSString stringWithFormat: @"Invalid output from tunnelblickd: no newline; full output = '%@'", output]);
        goto error2;
    }
    NSString * header = [output substringWithRange: NSMakeRange(0, rngNl.location)];
    NSArray * headerComponents = [header componentsSeparatedByString: @" "];
    if (  [headerComponents count] != 3) {
        appendLog([NSString stringWithFormat: @"Invalid output from tunnelblickd: header line does not have three components; full output = '%@'", output]);
        goto error2;
    }
    OSStatus status = [((NSString *)[headerComponents objectAtIndex: 0]) intValue];
    int   stdOutLen = [((NSString *)[headerComponents objectAtIndex: 1]) intValue];
    int   stdErrLen = [((NSString *)[headerComponents objectAtIndex: 2]) intValue];
    NSRange stdOutRng = NSMakeRange(rngNl.location + 1, stdOutLen);
    NSRange stdErrRng = NSMakeRange(rngNl.location + 1 + stdOutLen, stdErrLen);
    NSString * stdOutContents = [output substringWithRange: stdOutRng];
    NSString * stdErrContents = [output substringWithRange: stdErrRng];
//    appendLog([NSString stringWithFormat: @"runTunnelblickd: Output from tunnelblickd server: status = %d\nstdout = '%@'\nstderr = '%@'", status, stdOutContents, stdErrContents]);
    if (  stdoutString ) {
        *stdoutString = stdOutContents;
    }
    if (  stderrString ) {
        *stderrString = stdErrContents;
    }
    
    return status;
    
error1:
    shutdown(sockfd, SHUT_RDWR);
    close(sockfd);
    
error2:
    return -1;
}

NSString * sanitizedConfigurationContents(NSString * cfgContents) {
    
    
    NSArray * lines = [cfgContents componentsSeparatedByString: @"\n"];
    
    NSMutableString * outputString = [[[NSMutableString alloc] initWithCapacity: [cfgContents length]] autorelease];
    
    NSArray * beginInlineKeys = [NSArray arrayWithObjects:
                                 @"<auth-user-pass>",
								 @"<ca>",
                                 @"<cert>",
                                 @"<dh>",
                                 @"<extra-certs>",
                                 @"<key>",
                                 @"<pkcs12>",
                                 @"<secret>",
                                 @"<tls-auth>",
                                 nil];
    
    NSArray * endInlineKeys = [NSArray arrayWithObjects:
							   @"</auth-user-pass>",
                               @"</ca>",
                               @"</cert>",
                               @"</dh>",
                               @"</extra-certs>",
                               @"</key>",
                               @"</pkcs12>",
                               @"</secret>",
                               @"</tls-auth>",
                               nil];
    
    unsigned i;
    for (  i=0; i<[lines count]; i++  ) {
        
        NSString * line = lineAfterRemovingNulCharacters([lines objectAtIndex: i], outputString);
        
        [outputString appendFormat: @"%@\n", line];
        
        // We NEVER want to include anything that looks like certificate/key info, even if it is commented out.
        // So we omit anything that looks like an inline key or certificate.
        // So we will ignore everything after a COMMMENT that includes '-----BEGIN' until a line that includes '-----END'.
        // So if no '-----END' appears, we will end up ignoring the rest of the file, even if it is NOT commented out.
        
        if (  [line rangeOfString: @"-----BEGIN"].length != 0  ) {
            // Have something that looks like a certificate or key; skip to the end of it and insert a message about it.
            unsigned beginLineNumber = i;   // Line number of '-----BEGIN'
            BOOL foundEnd = FALSE;
			for (  i=i+1; i<[lines count]; i++  )  {
                line = lineAfterRemovingNulCharacters([lines objectAtIndex: i], outputString);
				if (  (foundEnd  = ([line rangeOfString: @"-----END"].length != 0))  ) {
                    if (  i != (beginLineNumber + 1)  ) {
                        [outputString appendFormat: @" [Lines that appear to be security-related have been omitted]\n"];
                    }
                    [outputString appendFormat: @"%@\n", line];
					break;
				}
            }
            if (  ! foundEnd  ) {
                appendLog([NSString stringWithFormat: @"Tunnelblick: Error parsing configuration at line %u; unterminated '-----BEGIN' at line %u\n", i+1, beginLineNumber+1]);
                if (  i != (beginLineNumber + 1)  ) {
                    [outputString appendFormat: @" [Lines that appear to be security-related have been omitted]\n"];
                }
                // Because we are at the end of the file, we ignore the error
            }
        } else {
            
            NSArray * tokens = tokensFromConfigurationLine(line);
            
            if (  ! tokens  ) {
                appendLog([NSString stringWithFormat: @"Tunnelblick: Error parsing configuration at line %u\n", i+1]);
                return nil;
            }
            
            if (  [tokens count] > 0  ) {
                NSString * firstToken = [tokens objectAtIndex: 0];
                if (  [firstToken hasPrefix: @"<"]  ) {
                    NSUInteger j;
                    if (  (j = [beginInlineKeys indexOfObject: firstToken]) != NSNotFound  ) {
                        unsigned beginLineNumber = i;
						BOOL foundEnd = FALSE;
                        for (  i=i+1; i<[lines count]; i++  ) {
                            
                            line = lineAfterRemovingNulCharacters([lines objectAtIndex: i], outputString);
                            
                            tokens = tokensFromConfigurationLine(line);
                            
                            if (  ! tokens  ) {
                                appendLog([NSString stringWithFormat: @"Tunnelblick: Error parsing configuration at line %u\n", i+1]);
                                return nil;
                            }
                            
                            if (  [tokens count] > 0  ) {
                                if (  (foundEnd = [[tokens objectAtIndex: 0] isEqualToString: [endInlineKeys objectAtIndex: j]])  ) {
									if (  i != (beginLineNumber + 1)  ) {
										[outputString appendFormat: @" [Security-related line(s) omitted]\n"];
									}
                                    [outputString appendFormat: @"%@\n", line];
                                    break;
                                }
                            }
                        }
                        
                        if (  ! foundEnd  ) {
                            appendLog([NSString stringWithFormat: @"Tunnelblick: Error parsing configuration at line %u; unterminated %s at line %u\n", i+1, [[beginInlineKeys objectAtIndex: j] UTF8String], beginLineNumber+1]);
                            return nil;
                        }
                    }
                }
            }
        }
    }
    
    return [NSString stringWithString: outputString];
}
