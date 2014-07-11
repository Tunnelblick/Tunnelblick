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

// The routines contained in this module may be used by any of the components
// of Tunnelblick. Most of them are used by Tunnelblick itself and installer, openvpnstart, and atsystemstart.
//
// If these routines are used by a target, the target must itself define appendLog(NSString * msg), which should
// append the message to the target's log.


#import "sharedRoutines.h"

#import <netinet/in.h>
#import <sys/stat.h>
#import <sys/types.h>

#import "defines.h"

#import "NSFileManager+TB.h"
#import "NSString+TB.h"


extern NSString * gDeployPath;

// External reference that must be defined in Tunnelblick, installer, and any other target using this module
void appendLog(NSString * msg);	// Appends a string to the log


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

BOOL isSanitizedOpenvpnVersion(NSString * s) {
    
    return (   [s containsOnlyCharactersInString: ALLOWED_OPENVPN_VERSION_CHARACTERS]
            && ( 0 == [s rangeOfString: @".."].length )
            && (! [s hasSuffix: @"."])
            && (! [s hasPrefix: @"."])  );
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
                return 1;
            }
            NSLog(@"Warning: Unable to change permissions on %@ from %lo to %lo", dirPath, [oldPermissionsAsNumber longValue], permissions);
            return 0;
        } else {
            NSLog(@"Error: %@ exists but is not a directory", dirPath);
            return -1;
        }
    }
    
    // No such directory. Create its parent directory (recurse) if necessary
    int result = createDir([dirPath stringByDeletingLastPathComponent], permissions);
    if (  result == -1  ) {
        return -1;
    }
    
    // Parent directory exists. Create the directory we want
    if (  ! [[NSFileManager defaultManager] tbCreateDirectoryAtPath: dirPath attributes: permissionsAsAttribute] ) {
        if (   [[NSFileManager defaultManager] fileExistsAtPath: dirPath isDirectory: &isDir]
            && isDir  ) {
            NSLog(@"Warning: Created directory %@ but unable to set permissions to %lo", dirPath, permissions);
            return 1;
        } else {
            NSLog(@"Error: Unable to create directory %@ with permissions %lo", dirPath, permissions);
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
        NSLog(@"checkSetOwnership: '%@' does not exist", path);
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
    
    if (  ! [[NSFileManager defaultManager] isReadableFileAtPath: path]  ) {
		NSString * errMsg = [NSString stringWithFormat: NSLocalizedString(@"You do not have permission to read '%@'.\n\n", @"Window text"),
                             path];
        appendLog(errMsg);
        return errMsg;
    }
    
    if (  [fileType isEqualToString: NSFileTypeRegular]  ) {
        NSString * errMsg = fileIsReasonableSize(path);
        if (  errMsg  ) {
            appendLog(errMsg);
            return errMsg;
        }
    } else if (  ! [fileType isEqualToString: NSFileTypeDirectory]  ) {
        NSString * errMsg = [NSString stringWithFormat: NSLocalizedString(@"An internal Tunnelblick error occurred%@%@", @"Window text"),
                             @": allFilesAreReasonableIn: Not a folder or regular file: ", path];
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
                                                             @"Characters that are not allowed: '%s'\n\n.", @"Window text"),
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

unsigned int getFreePort(void)
{
	// Returns a free port or 0 if no free port is available
	
    unsigned int resultPort = 1336; // start port

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (  fd == -1  ) {
        return 0;
    }
    
    int result = 0;
    
    do {
        struct sockaddr_in address;
        unsigned len = sizeof(struct sockaddr_in);
        if (  len > UCHAR_MAX  ) {
            fprintf(stderr, "getFreePort: sizeof(struct sockaddr_in) is %u, which is > UCHAR_MAX -- can't fit it into address.sin_len", len);
            close(fd);
            return 0;
        }
        if (  resultPort == 65535  ) {
            fprintf(stderr, "getFreePort: cannot get a free port between 1335 and 65536");
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
    mode_t selfPerms;           //  For the folder itself (if not a .tblk)
    mode_t tblkFolderPerms;     //  For a .tblk itself and any subfolders
    mode_t privateFolderPerms;  //  For folders in /Library/Application Support/Tunnelblick/Users/...
    mode_t publicFolderPerms;   //  For all other folders
    mode_t scriptPerms;         //  For files with .sh extensions
    mode_t executablePerms;     //  For files with .executable extensions (only appear in a Deploy folder
    mode_t forcedPrefsPerms;    //  For files named forced-preferences (only appear in a Deploy folder
    mode_t otherPerms;          //  For all other files
    
    if (  isPrivate  ) {
        // Private files are owned by <user>:admin
		user  = theUser;
        if (  user == 0  ) {
            appendLog(@"Tunnelblick internal error: secureOneFolder: No user");
            return NO;
        }
		group = ADMIN_GROUP_ID;
        if (  [[path pathExtension] isEqualToString: @"tblk"]  ) {
            selfPerms   = PERMS_PRIVATE_TBLK_FOLDER;
        } else {
            selfPerms   = PERMS_PRIVATE_SELF;
        }
        tblkFolderPerms    = PERMS_PRIVATE_TBLK_FOLDER;
		privateFolderPerms = PERMS_PRIVATE_PRIVATE_FOLDER;
        publicFolderPerms  = PERMS_PRIVATE_PUBLIC_FOLDER;
        scriptPerms        = PERMS_PRIVATE_SCRIPT;
        executablePerms    = PERMS_PRIVATE_EXECUTABLE;
        forcedPrefsPerms   = PERMS_PRIVATE_FORCED_PREFS;
        otherPerms         = PERMS_PRIVATE_OTHER;
    } else {
        user  = 0;                      // Secured files are owned by root:wheel
        group = 0;
		if (  [[path pathExtension] isEqualToString: @"tblk"]  ) {
			selfPerms   = PERMS_SECURED_TBLK_FOLDER;
        } else {
            selfPerms   = PERMS_SECURED_SELF;
        }
        tblkFolderPerms    = PERMS_SECURED_TBLK_FOLDER;
		privateFolderPerms = PERMS_SECURED_PRIVATE_FOLDER;
        publicFolderPerms  = PERMS_SECURED_PUBLIC_FOLDER;
        scriptPerms        = PERMS_SECURED_SCRIPT;
        executablePerms    = PERMS_SECURED_EXECUTABLE;
        forcedPrefsPerms   = PERMS_SECURED_FORCED_PREFS;
        otherPerms         = PERMS_SECURED_OTHER;
    }
    
	if (  [path hasPrefix: L_AS_T_USERS]  ) {
		selfPerms = PERMS_SECURED_PRIVATE_FOLDER;
	} else if (  [path hasPrefix: L_AS_T_TBLKS]  ) {
		selfPerms   = PERMS_SECURED_PUBLIC_FOLDER;
	}
	
    BOOL result = checkSetOwnership(path, YES, user, group);
    
    result = result && checkSetPermissions(path, selfPerms, YES);
    
    BOOL isDir;
    NSString * file;
    NSDirectoryEnumerator * dirEnum = [[NSFileManager defaultManager] enumeratorAtPath: path];
	
    while (  (file = [dirEnum nextObject])  ) {
        NSString * filePath = [path stringByAppendingPathComponent: file];
        if (  itemIsVisible(filePath)  ) {
            
            NSString * ext  = [file pathExtension];
            
            if (   [ext isEqualToString: @"tblk"]
				&& ( ! [path hasPrefix: L_AS_T_TBLKS] )  ) {
                result = result && checkSetPermissions(filePath, tblkFolderPerms, YES);
                
            } else if (   [[NSFileManager defaultManager] fileExistsAtPath: filePath isDirectory: &isDir]
                       && isDir  ) {
                
                // Special case: folders in L_AS_T_TBLKS are visible to all users, even though they are inside a .tblk
                if (  [filePath hasPrefix: [L_AS_T_TBLKS stringByAppendingString: @"/"] ]  ) {
                    result = result && checkSetPermissions(filePath, publicFolderPerms, YES);
                
                // Folders inside a .tblk anywhere else are visible only to the owner & group
                } else if (  [filePath rangeOfString: @".tblk/"].location != NSNotFound  ) {
                    result = result && checkSetPermissions(filePath, tblkFolderPerms, YES);
                    
                } else if (   [filePath hasPrefix: @"/Applications/Tunnelblick.app/Contents/Resources/Deploy/"]
                           || [filePath hasPrefix: [gDeployPath   stringByAppendingString: @"/"]]
						   || [filePath hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]  ) {
                    result = result && checkSetPermissions(filePath, publicFolderPerms, YES);
                    
                } else {
                    result = result && checkSetPermissions(filePath, privateFolderPerms, YES);
				}
                
            } else if ( [ext isEqualToString:@"sh"]  ) {
				result = result && checkSetPermissions(filePath, scriptPerms, YES);
                
            } else if ( [ext isEqualToString:@"executable"]  ) {
				result = result && checkSetPermissions(filePath, executablePerms, YES);
                
            // Files within L_AS_T_TBLKS are visible to all users (even if they are in a .tblk)
            } else if (   [file isEqualToString:@"forced-preferences.plist"]
                       || [filePath hasPrefix: [L_AS_T_TBLKS  stringByAppendingString: @"/"]]
                       ) {
				result = result && checkSetPermissions(filePath, forcedPrefsPerms, YES);
                
            } else {
				result = result && checkSetPermissions(filePath, otherPerms, YES);
            }
        }
    }
    
	return result;
}

NSData * availableDataOrError(NSFileHandle * file) {
	
	// This routine is a modified version of a method from http://dev.notoptimal.net/search/label/NSTask
	// Slightly modified version of Chris Suter's category function used as a private function
    
	for (;;) {
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

OSStatus runTool(NSString * launchPath,
                 NSArray  * arguments,
                 NSString * * stdOut,
                 NSString * * stdErr) {
	
	// Runs a command or script, returning the execution status of the command, stdout, and stderr
	
	NSTask * task = [[NSTask alloc] init];
    
    [task setLaunchPath: launchPath];
    [task setArguments:  arguments];
    
	NSPipe * stdOutPipe = nil;
	NSPipe * errOutPipe = nil;
	
	if (  stdOut  ) {
		stdOutPipe = [NSPipe pipe];
		[task setStandardOutput: stdOutPipe];
	}
    
    if (  stdErr  ) {
		errOutPipe = [NSPipe pipe];
		[task setStandardError: errOutPipe];
	}
	
    [task launch];
	
	// The following is a heavily modified version of code from http://dev.notoptimal.net/search/label/NSTask
    
	NSFileHandle * outFile = [stdOutPipe fileHandleForReading];
	NSFileHandle * errFile = [errOutPipe fileHandleForReading];
	
	NSString * stdOutString = @"";
	NSString * stdErrString = @"";
	
	NSData * outData = availableDataOrError(outFile);
	NSData * errData = availableDataOrError(errFile);
	while (   ([outData length] > 0)
		   || ([errData length] > 0)
		   || [task isRunning]  ) {
        
		if (  [outData length] > 0  ) {
			stdOutString = [stdOutString stringByAppendingString: [[[NSString alloc] initWithData: outData encoding:NSUTF8StringEncoding] autorelease]];
		}
		if (  [errData length] > 0  ) {
			stdErrString = [stdErrString stringByAppendingString: [[[NSString alloc] initWithData: errData encoding:NSUTF8StringEncoding] autorelease]];
		}
		
		outData = availableDataOrError(outFile);
		errData = availableDataOrError(errFile);
	}
	
	[outFile closeFile];
	[errFile closeFile];
	
	// End of code from http://dev.notoptimal.net/search/label/NSTask
    
    [task waitUntilExit];
    
	OSStatus status = [task terminationStatus];
	
	if (  stdOut  ) {
		*stdOut = stdOutString;
	}
	
	if (  stdErr  ) {
		*stdErr = stdErrString;
	}
	
    [task release];
    
	return status;
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
