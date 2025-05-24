/*
 * Copyright (c) 2010, 2011, 2012 Jonathan K. Bullard. All rights reserved.
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

//*************************************************************************************************
//
// Tunnelblick was written using many NSFileManager methods that were deprecated in 10.5.
// Such invocations have been changed to instead invoke the methods implemented here.
// (Isolating the deprecated calls in one place should make changes easier to implement.)
//
// In the code below, we use 10.5 methods if they are available, otherwise we use 10.4 methods.
// (If neither are available, we put an entry in the log and return negative results.)

#import "NSFileManager+TB.h"

#import <sys/stat.h>

#import "defines.h"

void appendLog(NSString * errMsg);

@implementation NSFileManager (TB)

-(BOOL) tbChangeFileAttributes: (NSDictionary *) attributes
                        atPath: (NSString * )    path {

    NSError * err = nil;
    if (  ! [self setAttributes: attributes ofItemAtPath: path error: &err]  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from setAttributes: %@ ofItemAtPath: '%@'; Error was %@; stack trace: %@",
                             attributes, path, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    return YES;
}

-(BOOL) tbCreateDirectoryAtPath: (NSString *)     path
	withIntermediateDirectories: (BOOL)           withIntermediateDirectories
					 attributes: (NSDictionary *) attributes {

	NSError * err = nil;
    if (  ! [self createDirectoryAtPath: path withIntermediateDirectories: withIntermediateDirectories attributes: attributes error: &err]  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from createDirectoryAtPath: '%@' withIntermediateDirectories: %s attributes: %@; Error was %@; stack trace: %@",
                             path, ( withIntermediateDirectories ? "YES" : "NO" ), attributes, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    return YES;
}

-(BOOL) tbCreateSymbolicLinkAtPath: (NSString *) path
                       pathContent: (NSString *) otherPath {

    NSError * err = nil;
    if (  ! [self createSymbolicLinkAtPath: path withDestinationPath: otherPath error: &err]  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from createSymbolicLinkAtPath: '%@' withDestinationPath: '%@'; Error was %@; stack trace: %@",
                             path, otherPath, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    return YES;
}

-(NSArray *) tbDirectoryContentsAtPath:(NSString *) path {

    NSError * err = nil;
    NSArray * answer = [self contentsOfDirectoryAtPath:path error: &err];
    if (  ! answer  ) {
        NSString * errMsg = [NSString stringWithFormat: 
                             @"Error returned from contentsOfDirectoryAtPath: '%@'; Error was %@; stack trace: %@",
                             path, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
    }

    return answer;
}

-(NSDictionary *) tbFileAttributesAtPath: (NSString *) path
                            traverseLink: (BOOL)       flag {

    NSError * err = nil;
    NSDictionary * attributes = [self attributesOfItemAtPath:path error: &err];
    if (  ! attributes  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from attributesOfItemAtPath: '%@';\nError was %@; stack trace: %@",
                             path, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return nil;
    }

    unsigned int counter = 0;
    NSString * realPath = nil;
    NSString * newPath  = [[path copy] autorelease];
    while (   flag
           && ( counter++ < 10 )
           && [[attributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink] ) {
        realPath = [self tbPathContentOfSymbolicLinkAtPath: newPath];
        if (  ! realPath  ) {
            return nil;
        }
        if (  ! [realPath hasPrefix: @"/"]  ) {
            realPath = [[newPath stringByDeletingLastPathComponent] stringByAppendingPathComponent: realPath];
        }
        attributes = [self attributesOfItemAtPath:realPath error: &err];
        if (  ! attributes  ) {
            NSString * errMsg = [NSString stringWithFormat:
                                 @"Error returned from attributesOfItemAtPath: '%@';\nOriginal path was' %@'\nLatest path = '%@';\nError was %@; stack trace: %@",
                                 realPath, path, newPath, err, [NSThread callStackSymbols]];
            appendLog(errMsg);
            return nil;
        }

        newPath = [[realPath copy] autorelease];
    }

    if (  counter >= 10  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"tbFileAttributesAtPath detected a symlink loop.\nOriginal path was '%@'\nLast \"Real\" path was '%@', attributes = %@; stack trace: %@",
                             path, realPath, attributes, [NSThread callStackSymbols]];
        appendLog(errMsg);
    }

    return attributes;
}

-(BOOL) tbMovePath: (NSString *) source
            toPath: (NSString *) destination
           handler: (id)         handler {

    (void) handler;
    
    NSError * err = nil;
    if (  ! [self moveItemAtPath: source toPath: destination error: &err]  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from moveItemAtPath: '%@' toPath: '%@'; Error was %@; stack trace: %@",
                             source, destination, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    return YES;
}

-(BOOL) tbCopyPath: (NSString *) source
            toPath: (NSString *) destination
           handler: (id)         handler {

    (void) handler;

    NSError * err = nil;
    if (  ! [self copyItemAtPath:source toPath:destination error: &err]  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from copyItemAtPath: '%@' toPath: '%@'; Error was %@; stack trace: %@",
                             source, destination, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    return YES;
}

-(BOOL) tbRemoveSecureFileAtPathIfItExists: (NSString *) path {

    const char * pathC = [path fileSystemRepresentation];

    struct stat status;

    if (  lstat(pathC, &status) != 0  ) {
        if (  errno == ENOENT  ) {
            return YES;
        }
        appendLog([NSString stringWithFormat: @"lstat() failed with error %d ('%s') for %@; stack trace: %@", errno, strerror(errno), path, [NSThread callStackSymbols]]);
        return NO;
    }

    if (  status.st_nlink != 1  ) {
        appendLog([NSString stringWithFormat: @"Multiple (%u) hard links for %@; stack trace: %@", status.st_nlink, path, [NSThread callStackSymbols]]);
        return NO;
    }

    if (  0 != unlink(pathC)  ) {
        appendLog([NSString stringWithFormat: @"unlink() failed with error %d ('%s') for path %@; stack trace: %@", errno, strerror(errno), path, [NSThread callStackSymbols]]);
        return NO;
    }

    return YES;
}

-(BOOL) tbVerifyFileOwnedByRootWheelIfItExistsAtPath: (NSString *) path {

    const char * pathC = [path fileSystemRepresentation];

    struct stat status;

    if (  lstat(pathC, &status) != 0  ) {
        if (  errno == ENOENT  ) {
            return YES;
        }
        appendLog([NSString stringWithFormat: @"lstat() failed with error %d ('%s') for %@; stack trace: %@", errno, strerror(errno), path, [NSThread callStackSymbols]]);
        return NO;
    }

    if (  (status.st_mode & S_IFMT) !=  S_IFREG  ) {
        appendLog([NSString stringWithFormat: @"Not a regular file: %@; stack trace: %@", path, [NSThread callStackSymbols]]);
        return NO;
    }

    if (   (status.st_uid != 0)
        || (status.st_gid != 0)  ) {
        appendLog([NSString stringWithFormat: @"Owned by %u:%u, not root:wheel: %@; stack trace: %@", status.st_uid, status.st_gid, path, [NSThread callStackSymbols]]);
        return NO;
    }

    return YES;
}

-(BOOL)         tbCopyFileAtPath: (NSString *) source
                          toPath: (NSString *) destination
 ownedByRootWheelWithPermissions: (mode_t)     permissions {

    // Must be invoked as root.
    //
    // Invoker must guarantee:
    //
    //  * If file exists, the file must be owned by root:wheel and not have write permission
    //    for group or other.
    //
    //  * All parent folders of path must be owned by root:wheel or root:admin
    //    and not have write permission for other. (If not, an existing file's ownership
    //    could be changed)
    //
    // These restrictions are needed because we want the file's new contents to have the
    // specified ownership **at all times**:
    //
    //  * If the destination file doesn't exist, open() will create it with the current owner, so
    //    the invoking process must be running as root.
    //
    //  * If the destination file exists, open() will keep its existing owner even when it is
    //    being overwritten, so any existing file must be owned by root:wheel (or root:admin).
    //
    //    To guarantee that the file remains owned by root:wheel (or root:admin), the file's
    //    parent folders must not allow "other" to write. (Write permissions on a parent
    //    folder could rename the file and create a new file with the file's original name.)

    // Nothing owned by root:wheel should be writable by group or other!
    if (  permissions != (permissions & 0755)  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Invalid permissions 0%3o (cannot allow write by group or other) in tbCopyFilePath to '%@'; stack trace: %@",
                             permissions, source, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    const char * destinationC = [destination fileSystemRepresentation];

    NSError * err;

    // Get the data

    NSMutableData * data = [[NSMutableData alloc] initWithContentsOfFile: source
                                                                 options: 0
                                                                   error: &err];
    if (  ! data  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from dataWithContentsOfFile: '%@'; Error was %@; stack trace: %@",
                             source, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    // Write out the data

    int filedes = open(destinationC, O_WRONLY | O_CREAT | O_NOFOLLOW, 0700 );
    if (  filedes == -1  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from open: '%s'; Error was %d (%s); stack trace: %@",
                             destinationC, errno, strerror(errno), [NSThread callStackSymbols]];
        [data release]; data = nil;
        appendLog(errMsg);
        return NO;
    }

    NSUInteger length = [data length];
    const void * bytes = [data bytes];

    ssize_t written = write(filedes, bytes, length);

    [data release]; data = nil;

    if (  (written < 0)  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from write: '%s'; expected to write %lu bytes but wrote %ld bytes; stack trace: %@",
                             destinationC, length, written, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }
    if (  (NSUInteger)written != length  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from write: '%s'; expected to write %ld bytes but wrote %ld bytes; stack trace: %@",
                             destinationC, length, written, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }


    int status = close(filedes);
    if (  status != 0  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from close: '%s'; Error was %d (%s); stack trace: %@",
                             destinationC, errno, strerror(errno), [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    // Set ownership and permissions.
    //
    // root:wheel can't chmod() to get anything other than 0_55 or 0_00 permissions (e.g. 0_44).
    // So because the desired ownership is root:wheel,
    //    if the desired permissions are not 0_55 or 0_00,
    //    then we change the ownership to root:admin, change the permissions, then change the ownership to root:wheel
    //    else we just change the ownership to root:wheel and change the permissions.

    gid_t intermediate_gid = (   (   (0000 == (permissions & 0077))
                                  || (0055 == (permissions & 0077)))
                              ? 0
                              : ADMIN_GROUP_ID);

    status = chown(destinationC, 0, intermediate_gid);
    if (  status != 0  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from chown(0, %d): '%s'; Error was %d (%s); stack trace: %@",
                             intermediate_gid, destinationC, errno, strerror(errno), [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    status = chmod(destinationC, permissions);
    if (  status != 0  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from chmod('%s',0%3o); Error was %d (%s); stack trace: %@",
                             destinationC, permissions, errno, strerror(errno), [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    if (  0 != intermediate_gid  ) {
        status = chown(destinationC, 0, 0);
        if (  status != 0  ) {
            NSString * errMsg = [NSString stringWithFormat:
                                 @"Error returned from chown(0, 0): '%s'; Error was %d (%s); stack trace: %@",
                                 destinationC, errno, strerror(errno), [NSThread callStackSymbols]];
            appendLog(errMsg);
            return NO;
        }
    }

    return YES;
}

-(BOOL)    tbCopyItemAtPath: (NSString *) source
 toBeOwnedByRootWheelAtPath: (NSString *) destination {

    NSDictionary * fileAttributes = [[NSFileManager defaultManager] tbFileAttributesAtPath: source traverseLink: NO];
    if (  ! fileAttributes  ) {
        appendLog([NSString stringWithFormat: @"Cannot get attributes of item at '%@'", source]);
        return NO;
    }

    unsigned long permissions = [fileAttributes filePosixPermissions];
    BOOL isDir = [[fileAttributes fileType] isEqualToString: NSFileTypeDirectory];

    if (  isDir  ) {

        if (  0 != mkdir([destination fileSystemRepresentation], (permissions | 0700))  ) {
            NSString * errMsg = [NSString stringWithFormat:
                                 @"Error returned from mkdir('%@', 0%3lo); Error was %d (%s); stack trace: %@",
                                 destination, (permissions | 0700), errno, strerror(errno), [NSThread callStackSymbols]];
            appendLog(errMsg);
            return NO;
        }

        NSDirectoryEnumerator * dirE = [self enumeratorAtPath: source];
        NSString * file;
        while (  (file = [dirE nextObject])  ) {
            NSString * fullSourcePath = [source stringByAppendingPathComponent: file];
            NSString * fullDestinationPath = [destination stringByAppendingPathComponent: file];

            fileAttributes = [[NSFileManager defaultManager] tbFileAttributesAtPath: fullSourcePath traverseLink: NO];
            if (  ! fileAttributes  ) {
                appendLog([NSString stringWithFormat: @"Cannot get attributes of item at '%@'", fullSourcePath]);
                return NO;
            }

            permissions = [fileAttributes filePosixPermissions];
            isDir = [[fileAttributes fileType] isEqualToString: NSFileTypeDirectory];
            BOOL isSymlink = [[fileAttributes fileType] isEqualToString: NSFileTypeSymbolicLink];

            if (  isDir  ) {
                if (  0 != mkdir([fullDestinationPath fileSystemRepresentation], (permissions | 0700))  ) {
                    NSString * errMsg = [NSString stringWithFormat:
                                         @"Error returned from mkdir('%@', 0%3lo); Error was %d (%s); stack trace: %@",
                                         fullDestinationPath, (permissions | 0700), errno, strerror(errno), [NSThread callStackSymbols]];
                    appendLog(errMsg);
                    return NO;
                }
            } else if (  isSymlink  ) {
                NSError * err;
                NSString * symlinkTarget = [self destinationOfSymbolicLinkAtPath: fullSourcePath error: &err];
                if (  ! symlinkTarget ) {
                    NSString * errMsg = [NSString stringWithFormat:
                                         @"Error returned from destinationOfSymbolicLinkAtPath '%@'; Error %@; stack trace: %@",
                                         fullSourcePath, err, [NSThread callStackSymbols]];
                    appendLog(errMsg);
                    return NO;
                }

                if (  ! [self createSymbolicLinkAtPath: fullDestinationPath withDestinationPath: symlinkTarget error: &err]  ) {
                    NSString * errMsg = [NSString stringWithFormat:
                                         @"Error returned from createSymbolicLinkAtPath '%@' with destination '%@'; Error %@; stack trace: %@",
                                         fullDestinationPath, symlinkTarget, err, [NSThread callStackSymbols]];
                    appendLog(errMsg);
                    return NO;
                }
            } else {
                if (  ! [self tbCopyFileAtPath: fullSourcePath toPath: fullDestinationPath ownedByRootWheelWithPermissions: permissions]  ) {
                    return NO;
                }
            }
        }
    } else {
        return [self tbCopyFileAtPath: source toPath: destination ownedByRootWheelWithPermissions: permissions];
    }

    return YES;
}

-(BOOL) tbRemoveFileAtPath: (NSString *) path
                   handler: (id) handler {

    (void) handler;
    
    NSError * err = nil;
    if (  ! [self removeItemAtPath:path error: &err]  ) {
        NSString * errMsg = [NSString stringWithFormat: 
                             @"Error returned from removeItemAtPath: '%@'; Error was %@; stack trace: %@",
                             path, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    return YES;
}

-(BOOL) tbRemovePathIfItExists: (NSString *) path {
    
    if (  [self fileExistsAtPath: path]  ) {
        NSError * err = nil;
        if (  ! [self removeItemAtPath: path error: &err]  ) {
            NSString * errMsg = [NSString stringWithFormat:
                                 @"remove '%@' failed; error was '%@'; stack trace: %@",
                                 path, err, [NSThread callStackSymbols]];
            appendLog(errMsg);
            return NO;
        }
    }
    
    return YES;
}

-(BOOL) tbForceRenamePath: (NSString *) sourcePath
                   toPath: (NSString *) targetPath {

    int status = rename([sourcePath fileSystemRepresentation], [targetPath fileSystemRepresentation]);
    if (  status != 0  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"rename('%@','%@') failed; status = %ld; errno = %ld; error was '%s'; stack trace: %@",
                             sourcePath, targetPath, (long)status, (long)errno, strerror(errno), [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    return YES;
}

-(BOOL) tbForceMovePath: (NSString *) sourcePath
                 toPath: (NSString *) targetPath {

    if (  ! [self tbRemovePathIfItExists: targetPath]  ) {
        return NO;
    }

    return [self tbMovePath: sourcePath toPath: targetPath handler: nil];
}

-(NSString *) tbPathContentOfSymbolicLinkAtPath: (NSString *) path {

    NSError * err = nil;
    NSString * answer = [self destinationOfSymbolicLinkAtPath:path error: &err];
    if (  ! answer  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from destinationOfSymbolicLinkAtPath: '%@'; Error was %@; stack trace: %@",
                             path, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
    }

    return answer;
}

@end
