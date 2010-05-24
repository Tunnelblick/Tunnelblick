/*
 *  Copyright (c) 2004, 2005, 2006, 2007, 2008, 2009, 2010 by Angelo Laub
 *  Contributions by Jonathan K. Bullard
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#import <Foundation/Foundation.h>
#import <Security/AuthSession.h>

// NOTE: THIS PROGRAM MUST BE RUN AS ROOT VIA executeAuthorized
//
// This program is called when something needs to be secured.
// It accepts two to four arguments, and always does some standard housekeeping in
// addition to the specific tasks specified by the command line arguments.
//
// Usage:
//
//     installer secureTheApp  secureAllPackages   [ targetPathToSecure   [sourcePath]  [moveFlag] ]
//
// where
//     secureTheApp      is "0", or "1" to secure Tunnelblick.app and all of its contents
//     secureAllPackages is "0", or "1" to secure all .tblk packages in Configurations, Shared, and the alternate configuration path
//     targetPath        is the path to a configuration (.ovpn or .conf file, or .tblk package) to be secured
//     sourcePath        is the path to be copied or moved to targetPath before securing targetPath
//     moveFlag          is "0" to copy, "1" to move
//
// It does the following:
//      (1) Restores the /Deploy folder from the backup copy if it does not exist and a backup copy does,
//      (2) Moves the configuration folder from /Library/openvpn to ~/Library/Application Support/Tunnelblick/Configurations
//                and creates a symbolic link in its place (if this has not been done already)
//      (3) Creates ~/Library/Application Support/Tunnelblick/Configurations if it does not already exist
//      (4) Creates /Library/Application Support/Tunnelblick/Shared if it doesn't exist and makes sure it is secured
//      (5) _Iff_ the 1st command line argument is "1", secures Tunnelblick.app by setting the ownership and permissions of its components
//      (6) _Iff_ the 1st command line argument is "1", makes a backup of the /Deploy folder if it exists
//      (7) _Iff_ the 2nd command line argument is "1", secures all .tblk packages in the following folders:
//           /Library/Application Support/Tunnelblick/Shared
//           /Library/Application Support/Tunnelblick/Users/<username>
//           ~/Library/Application Support/Tunnelblick/Configurations
//      (8) _Iff_ the 4th command line argument is given, copies or moves sourcePath to targetPath (copies unless moveFlag = @"1")
//      (9) _Iff_ the 3rd command line argument is given, secures the .ovpn or .conf file or a .tblk package at that path
//
// Notes: (1), (2), (3), and (4) are done each time this command is invoked if they are needed (self-repair).
//        (5) needs to be (and will be) done at first launch after Tunnelblick.app is updated
//        (6) needs to be (and will be) done whenever Tunnelblick.app or Deploy is changed
//        (8) is done when creating a shadow configuration file
//                    or copying a .tblk to install it
//                    or moving a .tblk to make it private or shared
//        (9) is done when repairing a shadow configuration file or after copying or moving a .tblk

NSArray       * extensionsFor600Permissions;
NSFileManager * gFileMgr;       // [NSFileManager defaultManager]
NSString      * gPrivatePath;   // Path to ~/Library/Application Support/Tunnelblick/Configurations
NSString      * gSharedPath;    // Path to /Library/Application Support/Tunnelblick/Shared
NSString      * gDeployPath;    // Path to Tunnelblick.app/Contents/Resources/Deploy

uid_t realUserID;               // User ID & Group ID for the real user (i.e., not "root:wheel", which is what we are running as)
gid_t realGroupID;

BOOL checkSetOwnership(NSString * path, BOOL recurse, uid_t uid, gid_t gid);
BOOL checkSetPermissions(NSString * path, NSString * permsShouldHave, BOOL fileMustExist);
BOOL createDir(NSString * d);
BOOL itemIsVisible(NSString * path);
BOOL secureOneFolder(NSString * path);
BOOL makeFileUnlockedAtPath(NSString * path);

int main(int argc, char *argv[]) 
{
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    extensionsFor600Permissions = [NSArray arrayWithObjects: @"cer", @"crt", @"der", @"key", @"p12", @"p7b", @"p7c", @"pem", @"pfx", nil];
    gFileMgr = [NSFileManager defaultManager];
    gPrivatePath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Tunnelblick/Configurations/"] copy];
    gSharedPath = [@"/Library/Application Support/Tunnelblick/Shared" copy];
    
	NSString * thisBundle           = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
	gDeployPath                     = [thisBundle stringByAppendingPathComponent:@"Deploy"];
    NSString * deployBkupHolderPath = [[[[[@"/Library/Application Support/Tunnelblick/Backup" stringByAppendingPathComponent: thisBundle]
                                          stringByDeletingLastPathComponent]
                                         stringByDeletingLastPathComponent]
                                        stringByDeletingLastPathComponent]
                                       stringByAppendingPathComponent: @"TunnelblickBackup"];
    NSString * deployBackupPath     = [deployBkupHolderPath stringByAppendingPathComponent: @"Deploy"];
    NSString * deployOrigBackupPath = [deployBkupHolderPath stringByAppendingPathComponent: @"OriginalDeploy"];
    NSString * deployPrevBackupPath = [deployBkupHolderPath stringByAppendingPathComponent: @"PreviousDeploy"];
    
    realUserID  = getuid();
    realGroupID = getgid();
    
    BOOL isDir;
    
    // We create a file to act as a flag that the installation failed. We delete it before a success return.
    // We do this because under certain circumstances (on Tiger?), [task terminationStatus] doesn't return the correct value
    // We make it owned by the regular user so the Tunnelblick program that started us can delete it after dealing with the error
    // The filename includes the session ID to support fast user switching
    OSStatus error;
    SecuritySessionId mySession;
    SessionAttributeBits sessionInfo;
    error = SessionGetInfo(callerSecuritySession, &mySession, &sessionInfo);
    if (  error != 0  ) {
        mySession = 0;
    }
    NSString * installFailureFlagFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                             [NSString stringWithFormat:@"TunnelblickInstallationFailed-%d.txt", mySession]];

    [gFileMgr createFileAtPath: installFailureFlagFilePath contents: [NSData data] attributes: [NSDictionary dictionary]];
    chown([installFailureFlagFilePath UTF8String], realUserID, realGroupID);
    
    if (  (argc < 3)  || (argc > 6)  ) {
        NSLog(@"Tunnelblick Installer: Wrong number of arguments -- expected 2 or 3, given %d", argc-1);
        [pool release];
        exit(EXIT_FAILURE);
    }
    
    BOOL secureApp     = strcmp(argv[1], "1") == 0;
    BOOL secureTblks   = strcmp(argv[2], "1") == 0;
    
    NSString * singlePathToSecure = nil;
    if (  argc > 3  ) {
        singlePathToSecure = [NSString stringWithUTF8String: argv[3]];
    }
    NSString * singlePathToCopy = nil;
    if (  argc > 4  ) {
        singlePathToCopy = [NSString stringWithUTF8String: argv[4]];
    }
    BOOL moveNotCopy = FALSE;
    if (  argc > 5  ) {
        moveNotCopy = strcmp(argv[5], "1") == 0;
    }
    
    //**************************************************************************************************************************
    // (1)
    // If Resources/Deploy does not exist, but a backup of it does exist (happens when Tunnelblick.app has been updated)
    // Then restore it from the backup
    if (   [gFileMgr fileExistsAtPath: deployBackupPath isDirectory: &isDir]
        && isDir  ) {
        if (  ! (   [gFileMgr fileExistsAtPath: gDeployPath isDirectory: &isDir]
                 && isDir  )  ) {
            if (  ! [gFileMgr copyPath: deployBackupPath toPath: gDeployPath handler:nil]  ) {
                NSLog(@"Tunnelblick Installer: Unable to restore %@ from backup", gDeployPath);
                [pool release];
                exit(EXIT_FAILURE);
            }

            NSLog(@"Tunnelblick Installer: Restored %@ from backup", gDeployPath);
        }
    }
    
    //**************************************************************************************************************************
    // (2)
    // Move configuration folder to new place in file hierarchy if necessary
    NSString * oldConfigDirPath       = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/openvpn"];
    NSString * newConfigDirHolderPath = [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Application Support/Tunnelblick"];
    NSString * newConfigDirPath       = [newConfigDirHolderPath stringByAppendingPathComponent: @"Configurations"];
    
    if (  ! [gFileMgr fileExistsAtPath: newConfigDirHolderPath]  ) {
        if (  ! [gFileMgr fileExistsAtPath: newConfigDirPath]  ) {
            NSDictionary * fileAttributes = [gFileMgr fileAttributesAtPath: oldConfigDirPath traverseLink: NO]; // Want to see if it is a link, so traverseLink:NO
            if (  ! [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
                if (   [gFileMgr fileExistsAtPath: oldConfigDirPath isDirectory: &isDir]
                    && isDir  ) {
                    createDir(newConfigDirHolderPath);
                    // Since we're running as root, owner of 'newConfigDirHolderPath' is root:wheel. Try to change to real user:group
                    if (  0 != chown([newConfigDirHolderPath UTF8String], realUserID, realGroupID)  ) {
                        NSLog(@"Tunnelblick Installer: Warning: Tried to change ownership of folder %@\nError was '%s'", newConfigDirHolderPath, strerror(errno));
                    }
                    if (  [gFileMgr movePath: oldConfigDirPath toPath: newConfigDirPath handler: nil]  ) {
                        if (  [gFileMgr createSymbolicLinkAtPath: oldConfigDirPath pathContent: newConfigDirPath]  ) {
                            NSLog(@"Tunnelblick Installer: Successfully moved configuration folder %@ to %@ and created a symbolic link in its place.", oldConfigDirPath, newConfigDirPath);
                            // Since we're running as root, owner of symbolic link is root:wheel. Try to change to real user:group
                            if (  0 != lchown([oldConfigDirPath UTF8String], realUserID, realGroupID)  ) {
                                NSLog(@"Tunnelblick Installer: Warning: Tried to change ownership of symbolic link %@\nError was '%s'", oldConfigDirPath, strerror(errno));
                            }
                        } else {
                            NSLog(@"Tunnelblick Installer: Successfully moved configuration folder %@ to %@.", oldConfigDirPath, newConfigDirPath);
                            NSLog(@"Tunnelblick Installer: Error: Unable to create symbolic link to %@ at %@", newConfigDirPath, oldConfigDirPath);
                            [pool release];
                            exit(EXIT_FAILURE);
                        }
                    } else {
                        NSLog(@"Tunnelblick Installer: Error occurred while moving configuration folder %@ to %@", oldConfigDirPath, newConfigDirPath);
                        [pool release];
                        exit(EXIT_FAILURE);
                    }
                } else {
                    // oldConfigDirPath doesn't exist or isn't a folder, so we do nothing 
                }
                
            } else {
                // oldConfigDirPath is a symbolic link, so we do nothing
            }
        } else {
            // newConfigDirPath exists, so we do nothing
        }
        
    } else {
        // newConfigDirHolderPath exists, so we do nothing
    }
    
    //**************************************************************************************************************************
    // (3)
    // Create ~/Library/Application Support/Tunnelblick/Configurations if it does not already exist, and make it owned by the user, not root, with 755 permissions
    
    if (  createDir(gPrivatePath)  ) {
        NSLog(@"Tunnelblick Installer: Created %@", gPrivatePath);
    }
    
    BOOL okSoFar = checkSetOwnership(gPrivatePath, FALSE, realUserID, realGroupID);
    okSoFar = okSoFar && checkSetPermissions(gPrivatePath, @"755", YES);
    if (  ! okSoFar  ) {
        NSLog(@"Tunnelblick Installer: Unable to change ownership and permissions to %d:%d and 0755 on %@", (int) realUserID, (int) realGroupID, gPrivatePath);
        [pool release];
        exit(EXIT_FAILURE);
    }
    
    //**************************************************************************************************************************
    // (4)
    // Create /Library/Application Support/Tunnelblick/Shared if it does not already exist, and make sure it is owned by root with 755 permissions
    
    if (  createDir(gSharedPath)  ) {
        NSLog(@"Tunnelblick Installer: Created %@", gSharedPath);
    }
    
    okSoFar = checkSetOwnership(gSharedPath, FALSE, 0, 0);
    okSoFar = okSoFar && checkSetPermissions(gSharedPath, @"755", YES);
    if (  ! okSoFar  ) {
        NSLog(@"Tunnelblick Installer: Unable to secure %@", gSharedPath);
        [pool release];
        exit(EXIT_FAILURE);
    }
    
    //**************************************************************************************************************************
    // (5)
    // If requested, secure Tunnelblick.app by setting ownership of Info.plist and Resources and its contents to root:wheel,
    // and setting permissions as follows:
    //        Info.plist is set to 0644
    //        openvpnstart is set to 04111 (SUID, execute only)
    //        Other executables and standard scripts are set to 0744
    //        For the contents of /Resources/Deploy and its subfolders:
    //            folders are set to 0755
    //            certificate & key files (various extensions) are set to 0600
    //            shell scripts (*.sh) are set to 0744
    //            all other files are set to 0644
    if ( secureApp ) {
        
        NSString *installerPath         = [thisBundle stringByAppendingPathComponent:@"installer"];
        NSString *openvpnstartPath      = [thisBundle stringByAppendingPathComponent:@"openvpnstart"];
        NSString *openvpnPath           = [thisBundle stringByAppendingPathComponent:@"openvpn"];
        NSString *atsystemstartPath     = [thisBundle stringByAppendingPathComponent:@"atsystemstart"];
        NSString *leasewatchPath        = [thisBundle stringByAppendingPathComponent:@"leasewatch"];
        NSString *clientUpPath          = [thisBundle stringByAppendingPathComponent:@"client.up.osx.sh"];
        NSString *clientDownPath        = [thisBundle stringByAppendingPathComponent:@"client.down.osx.sh"];
        NSString *clientNoMonUpPath     = [thisBundle stringByAppendingPathComponent:@"client.nomonitor.up.osx.sh"];
        NSString *clientNoMonDownPath   = [thisBundle stringByAppendingPathComponent:@"client.nomonitor.down.osx.sh"];
        NSString *infoPlistPath         = [[thisBundle stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"Info.plist"];
        NSString *clientNewUpPath       = [thisBundle stringByAppendingPathComponent:@"client.up.tunnelblick.sh"];
        NSString *clientNewDownPath     = [thisBundle stringByAppendingPathComponent:@"client.down.tunnelblick.sh"];
        
        BOOL okSoFar = YES;
        okSoFar = okSoFar && checkSetOwnership(infoPlistPath, NO, 0, 0);
        
        okSoFar = okSoFar && checkSetOwnership(thisBundle, YES, 0, 0);
        
        okSoFar = okSoFar && checkSetPermissions(openvpnstartPath,    @"4111", YES);
        
        okSoFar = okSoFar && checkSetPermissions(infoPlistPath,       @"644", YES);
        
        okSoFar = okSoFar && checkSetPermissions(installerPath,       @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(openvpnPath,         @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(atsystemstartPath,   @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(leasewatchPath,      @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(clientUpPath,        @"744", NO);
        okSoFar = okSoFar && checkSetPermissions(clientDownPath,      @"744", NO);
        okSoFar = okSoFar && checkSetPermissions(clientNoMonUpPath,   @"744", NO);
        okSoFar = okSoFar && checkSetPermissions(clientNoMonDownPath, @"744", NO);
        okSoFar = okSoFar && checkSetPermissions(clientNewUpPath,     @"744", YES);
        okSoFar = okSoFar && checkSetPermissions(clientNewDownPath,   @"744", YES);
        
        if (   [gFileMgr fileExistsAtPath: gDeployPath isDirectory: &isDir]
            && isDir  ) {
            okSoFar = okSoFar && checkSetPermissions(gDeployPath,     @"755", YES);
            okSoFar = okSoFar && secureOneFolder(gDeployPath);
        }
        
        if (  ! okSoFar  ) {
            NSLog(@"Tunnelblick Installer: Unable to secure Tunnelblick.app");
            [pool release];
            exit(EXIT_FAILURE);
        }
    }
    
    //**************************************************************************************************************************
    // (6)
    // If Resources/Deploy exists, back it up -- saving the first configuration and the two most recent
    if ( secureApp ) {
        
        if (   [gFileMgr fileExistsAtPath: gDeployPath isDirectory: &isDir]
            && isDir  ) {
            createDir(deployBkupHolderPath);    // Create the folder that holds the backup folders if it doesn't already exist
            
            if (  ! (   [gFileMgr fileExistsAtPath: deployOrigBackupPath isDirectory: &isDir]
                     && isDir  )  ) {
                if (  ! [gFileMgr copyPath: gDeployPath toPath: deployOrigBackupPath handler:nil]  ) {
                    NSLog(@"Tunnelblick Installer: Unable to make original backup of %@", gDeployPath);
                    [pool release];
                    exit(EXIT_FAILURE);
                }
            }
            
            [gFileMgr removeFileAtPath:deployPrevBackupPath handler:nil];                       // Make original backup. Ignore errors -- original backup may not exist yet
            [gFileMgr movePath: deployBackupPath toPath: deployPrevBackupPath handler: nil];    // Make backup of previous backup. Ignore errors -- previous backup may not exist yet
            
            if (  ! [gFileMgr copyPath: gDeployPath toPath: deployBackupPath handler:nil]  ) {  // Make backup of current
                NSLog(@"Tunnelblick Installer: Unable to make backup of %@", gDeployPath);
                [pool release];
                exit(EXIT_FAILURE);
            }
        }
    }
        
    //**************************************************************************************************************************
    // (7)
    // If requested, secure all .tblk packages at the top level of folders:
    if (  secureTblks  ) {
        NSString * sharedPath  = @"/Library/Application Support/Tunnelblick/Shared";
        NSString * libraryPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Tunnelblick/Configurations/"];
        NSString * altPath     = [NSString stringWithFormat:@"/Library/Application Support/Tunnelblick/Users/%@", NSUserName()];
        
        NSArray * foldersToSecure = [NSArray arrayWithObjects: libraryPath, sharedPath, altPath, nil];
        
        BOOL okSoFar = YES;
        int i;
        for (i=0; i < [foldersToSecure count]; i++) {
            NSString * folderPath = [foldersToSecure objectAtIndex: i];
            NSString * file;
            NSArray * dirContents = [gFileMgr directoryContentsAtPath: folderPath];
            int j;
            for (j=0; j < [dirContents count]; j++) {
                file = [dirContents objectAtIndex: j];
                NSString * filePath = [folderPath stringByAppendingPathComponent: file];
                if (  itemIsVisible(filePath)  ) {
                    if (   [gFileMgr fileExistsAtPath: filePath isDirectory: &isDir]
                        && isDir
                        && [[file pathExtension] isEqualToString: @"tblk"]  ) {
                        if (  [filePath hasPrefix: gPrivatePath]  ) {
                            okSoFar = okSoFar && checkSetOwnership(filePath, NO, realUserID, realGroupID);
                        } else {
                            okSoFar = okSoFar && checkSetOwnership(filePath, NO, 0, 0);
                        }
                        okSoFar = okSoFar && checkSetPermissions(filePath, @"755", YES);
                        okSoFar = okSoFar && secureOneFolder(filePath);
                    }
                }
            }
        }
        
        if (  ! okSoFar  ) {
            NSLog(@"Tunnelblick Installer: Unable to secure all .tblk packages");
            [pool release];
            exit(EXIT_FAILURE);
        }
    }
    
    //**************************************************************************************************************************
    // (8)
    // If requested, copy or move a single file or .tblk package
    // Like the NSFileManager "movePath:toPath:handler" method, we move by copying, then deleting, because we may be moving
    // from one disk to another (e.g., home folder on network to local hard drive)
    if (  singlePathToCopy  ) {
        // Copy the file or package to a ".partial" file/folder first, then rename it
        // This avoids a race condition: folder change handling code runs while copy is being made, so it sometimes can
        // see the .tblk (which has been copied) but not the config.ovpn (which hasn't been copied yet), so it complains.
        NSString * dotPartialPath = [singlePathToSecure stringByAppendingPathExtension: @"partial"];
        [gFileMgr removeFileAtPath: dotPartialPath handler: nil];
        if (  ! [gFileMgr copyPath: singlePathToCopy toPath: dotPartialPath handler: nil]  ) {
            NSLog(@"Tunnelblick Installer: Failed to copy %@ to %@", singlePathToCopy, dotPartialPath);
            [gFileMgr removeFileAtPath: dotPartialPath handler: nil];
            [pool release];
            exit(EXIT_FAILURE);
        }
        
        BOOL errorHappened = FALSE; // Use this to defer error exit until after renaming xxx.partial to xxx
        
        // Now, if we are doing a move, delete the original file, to avoid a similar race condition that will cause a complaint
        // about duplicate configuration names.
        if (  moveNotCopy  ) {
            if (  ! [gFileMgr removeFileAtPath: singlePathToCopy handler: nil]  ) {
                NSLog(@"Tunnelblick Installer: Failed to delete %@", singlePathToCopy);
                errorHappened = TRUE;
            }
        }

        [gFileMgr removeFileAtPath: singlePathToSecure handler: nil];
        if (  ! [gFileMgr movePath: dotPartialPath toPath: singlePathToSecure handler: nil]  ) {
            NSLog(@"Tunnelblick Installer: Failed to rename %@ to %@", dotPartialPath, singlePathToSecure);
            [gFileMgr removeFileAtPath: dotPartialPath handler: nil];
            [pool release];
            exit(EXIT_FAILURE);
        }
        
        if (  errorHappened  ) {
            [pool release];
            exit(EXIT_FAILURE);
        }

        if (  ! makeFileUnlockedAtPath(singlePathToSecure)  ) {
            [pool release];
            exit(EXIT_FAILURE);
        }
    }
    
    //**************************************************************************************************************************
    // (9)
    // If requested, secure a single file or .tblk package
    if (  singlePathToSecure  ) {
        BOOL okSoFar = TRUE;
        NSString * ext = [singlePathToSecure pathExtension];
        if (  [ext isEqualToString: @"conf"] || [ext isEqualToString: @"ovpn"]  ) {
            okSoFar = okSoFar && checkSetOwnership(singlePathToSecure, NO, 0, 0);
            okSoFar = okSoFar && checkSetPermissions(singlePathToSecure, @"644", YES);
        } else if (  [ext isEqualToString: @"tblk"]  ) {
            if (  [singlePathToSecure hasPrefix: gPrivatePath]  ) {
                okSoFar = okSoFar && checkSetOwnership(singlePathToSecure, NO, realUserID, realGroupID);
            } else {
                okSoFar = okSoFar && checkSetOwnership(singlePathToSecure, YES, 0, 0);
            }
            okSoFar = okSoFar && checkSetPermissions(singlePathToSecure, @"755", YES);
            okSoFar = okSoFar && secureOneFolder(singlePathToSecure);
        } else {
            NSLog(@"Tunnelblick Installer: trying to secure unknown item at %@", singlePathToSecure);
            [pool release];
            exit(EXIT_FAILURE);
        }
        if (  ! okSoFar  ) {
            NSLog(@"Tunnelblick Installer: unable to secure %@", singlePathToSecure);
            [pool release];
            exit(EXIT_FAILURE);
        }
    }
    
    // We remove this file to indicate that the installation succeeded because the return code doesn't propogate back to our caller
    [gFileMgr removeFileAtPath: installFailureFlagFilePath handler: nil];
    
    [pool release];
    exit(EXIT_SUCCESS);
}

BOOL makeFileUnlockedAtPath(NSString * path)
{
    // Make sure the copy is unlocked
    NSDictionary * curAttributes;
    NSDictionary * newAttributes = [NSDictionary dictionaryWithObject: [NSNumber numberWithInt:0] forKey: NSFileImmutable];
    
    int i;
    int maxTries = 5;
    for (i=0; i <= maxTries; i++) {
        curAttributes = [gFileMgr fileAttributesAtPath: path traverseLink:YES];
        if (  ! [curAttributes fileIsImmutable]  ) {
            break;
        }
        [gFileMgr changeFileAttributes: newAttributes atPath: path];
        sleep(1);
    }
    
    if (  [curAttributes fileIsImmutable]  ) {
        NSLog(@"Tunnelblick Installer: Failed to unlock configuration %@ in %d attempts", path, maxTries);
        return FALSE;
    }
    return TRUE;
}

//**************************************************************************************************************************
// Changes ownership of a file or folder if necessary to the specified user/group.
// If "recurse" is TRUE, also changes ownership on all contents of a folder (except invisible items)
// Returns YES on success, NO on failure
BOOL checkSetOwnership(NSString * path, BOOL recurse, uid_t uid, gid_t gid)
{
    NSDictionary * atts = [[NSFileManager defaultManager] fileAttributesAtPath: path traverseLink: YES];
    if (   [[atts fileOwnerAccountID]      isEqualToNumber: [NSNumber numberWithInt: uid]]
        && [[atts fileGroupOwnerAccountID] isEqualToNumber: [NSNumber numberWithInt: gid]]  ) {
        return YES;
    }
    
    if (  [atts fileIsImmutable]  ) {
        NSLog(@"Tunnelblick Installer: Unable to change ownership because item is locked: %@", path);
        return NO;
    }
    
    if (  chown([path UTF8String], uid, gid) != 0  ) {
        NSLog(@"Tunnelblick Installer: Unable to change ownership to %d:%d on %@\nError was '%s'", (int) uid, (int) gid, path, strerror(errno));
        return NO;
    }
    
    NSString * recurseNote = @"";
    
    if (  recurse  ) {
        recurseNote = @" and its contents";
        NSString * file;
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: path];
        while ( file = [dirEnum nextObject]  ) {
            if (  itemIsVisible(file)  ) {
                NSString * filePath = [path stringByAppendingPathComponent: file];
                atts = [[NSFileManager defaultManager] fileAttributesAtPath: filePath traverseLink: YES];
                if (   ! [[atts fileOwnerAccountID]      isEqualToNumber: [NSNumber numberWithInt: uid]]
                    || ! [[atts fileGroupOwnerAccountID] isEqualToNumber: [NSNumber numberWithInt: gid]]  ) {
                    if (  chown([filePath UTF8String], uid, gid) != 0  ) {
                        NSLog(@"Tunnelblick Installer: Unable to change ownership to %d:%d on %@\nError was '%s'", (int) uid, (int) gid, filePath, strerror(errno));
                        return NO;
                    }
                }
            }
        }
    }
    
    NSLog(@"Tunnelblick Installer: Changed ownership to %d:%d on %@%@", (int) uid, (int) gid,  path, recurseNote);
    return YES;
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

    NSDictionary *atts = [gFileMgr fileAttributesAtPath: path traverseLink:YES];
    unsigned long perms = [atts filePosixPermissions];
    NSString *octalPerms = [NSString stringWithFormat:@"%o",perms];
    
    if (   [octalPerms isEqualToString: permsShouldHave]  ) {
        return YES;
    }
    
    if (  [atts fileIsImmutable]  ) {
        NSLog(@"Tunnelblick Installer: Cannot change permissions because item is locked: %@", path);
        return NO;
    }
    
    int permsInt;
    if      (  [permsShouldHave isEqualToString:  @"755"]  ) permsInt = 0755;
    else if (  [permsShouldHave isEqualToString:  @"744"]  ) permsInt = 0744;
    else if (  [permsShouldHave isEqualToString:  @"644"]  ) permsInt = 0644;
    else if (  [permsShouldHave isEqualToString:  @"600"]  ) permsInt = 0600;
    else if (  [permsShouldHave isEqualToString: @"4111"]  ) permsInt = 04111;
    else {
        NSLog(@"Tunnelblick Installer: invalid permsShouldHave = '%@' in checkSetPermissions function", permsShouldHave);
        return NO;
    }
    
    NSDictionary * attsToSet = [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInt: permsInt], NSFilePosixPermissions, nil];
    if (  ! [gFileMgr changeFileAttributes: attsToSet atPath: path]  ) {
        NSLog(@"Tunnelblick Installer: Unable to change permissions to 0%@ on %@",
              permsShouldHave,
              path);
        return NO;
    } else {
        NSLog(@"Tunnelblick Installer: Changed permissions to 0%@ on %@", permsShouldHave, path);
    }
    
    return YES;
}

//**************************************************************************************************************************
// Recursive function to create a directory if it doesn't already exist
// Returns YES if directory was created, NO if it already existed
BOOL createDir(NSString * d)
{
    BOOL isDir;
    if (   [gFileMgr fileExistsAtPath: d isDirectory: &isDir]
        && isDir  ) {
        return NO;
    }
    
    createDir([d stringByDeletingLastPathComponent]);
    
    if (  ! [gFileMgr createDirectoryAtPath: d attributes: nil]  ) {
        NSLog(@"Tunnelblick Installer: Unable to create directory %@", d);
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
// Makes sure that ownership/permissions of the CONTENTS of a specified folder (either /Deploy or a .tblk package) are secure
// If necessary, changes ownership on all *contents* of of the folder to root:wheel, except /Contents/Resources folders and .tblk folders
// in the ~/Library/.../Configurations folder are changed to be owned by the user so the user can edit the configuration file
// If necessary, changes permissions on *contents* of the folder as follows
//         invisible files (those with _any_ path component that starts with a period) are not changed
//         folders are set to 755
//         shell scripts are set to 744
//         certificate & key files are set to 600
//         all other visible files are set to 644
// DOES NOT change ownership or permissions on the folder itself
// Returns YES if successfully secured everything, otherwise returns NO
BOOL secureOneFolder(NSString * path)
{
    BOOL result = YES;
    BOOL isDir;
    NSString * file;
    NSFileManager * gFileMgr = [NSFileManager defaultManager];
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: path];
    while (file = [dirEnum nextObject]) {
        NSString * filePath = [path stringByAppendingPathComponent: file];
        if (  itemIsVisible(filePath)  ) {
            NSString * ext  = [file pathExtension];
            if (   [filePath hasSuffix: @".tblk/Contents/Resources"]
                || [ext isEqualToString: @"tblk"]  ) {
                if (  [filePath hasPrefix: gPrivatePath]  ) {
                    result = result && checkSetOwnership(filePath, NO, realUserID, realGroupID);
                } else {
                    result = result && checkSetOwnership(filePath, NO, 0, 0);
                }
            } else {
                result = result && checkSetOwnership(filePath, NO, 0, 0);
            }
            if (   [gFileMgr fileExistsAtPath: filePath isDirectory: &isDir]
                && isDir  ) {
                result = result && checkSetPermissions(filePath, @"755", YES);           // Folders are 755
            } else if ( [ext isEqualToString:@"sh"]  ) {
                result = result && checkSetPermissions(filePath, @"744", YES);           // Scripts are 744
            } else if (  [extensionsFor600Permissions containsObject: ext]  ) {
                result = result && checkSetPermissions(filePath, @"600", YES);           // Keys and certificates are 600
            } else {
                result = result && checkSetPermissions(filePath, @"644", YES);           // Everything else is 644
            }
        }
    }
    
    return result;
}
