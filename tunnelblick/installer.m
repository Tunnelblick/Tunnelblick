/*
 *  Copyright (c) 2004, 2005, 2006, 2007, 2008, 2009 Angelo Laub
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
#include <unistd.h>

NSFileManager * gFileMgr;       // [NSFileManager defaultManager]
NSString      * gDeployPath;    // Path to Tunnelblick.app/Contents/Resources/Deploy

void runTask(NSString *launchPath,NSArray *arguments);
void createDir(NSString * d);

// NOTE: THIS PROGRAM MUST BE RUN AS ROOT VIA executeAuthorized
// This program takes three arguments that specify what it is to do:
// If the first is  "1", the user has given permission to recover Deploy from the backup copy.
// If the second is "1", the application's ownership/permissions should be repaired and/or the configuration folder moved and
//                       a symbolic link ~/Library/Application Support/Tunnelblick/Configurations created as ~/Library/openvpn
// If the third  is "1", the Deploy backup will be removed.
// This program also always makes sure that /Library/Application Support/Tunnelblick/Shared exists (it creates it if necessary)

int main(int argc, char *argv[]) 
{
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    gFileMgr = [NSFileManager defaultManager];    
	
    NSString * thisBundle           = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
               gDeployPath          = [thisBundle stringByAppendingPathComponent:@"Deploy"];
    NSString * deployBkupHolderPath = [[[[[@"/Library/Application Support/Tunnelblick/Backup" stringByAppendingPathComponent: thisBundle]
                                          stringByDeletingLastPathComponent]
                                         stringByDeletingLastPathComponent]
                                        stringByDeletingLastPathComponent]
                                       stringByAppendingPathComponent: @"TunnelblickBackup"];
    NSString * deployBackupPath     = [deployBkupHolderPath stringByAppendingPathComponent: @"Deploy"];
    NSString * deployOrigBackupPath = [deployBkupHolderPath stringByAppendingPathComponent: @"OriginalDeploy"];
    NSString * deployPrevBackupPath = [deployBkupHolderPath stringByAppendingPathComponent: @"PreviousDeploy"];
    
    uid_t realUserID  = getuid();   // User ID & Group ID for the real user (i.e., not "root:wheel", which is what we are running as
    gid_t realGroupID = getgid();

    BOOL            isDir;
    
    // We create this file to act as a flag that the installation failed. We delete it before a success return.
    [gFileMgr createFileAtPath: @"/tmp/TunnelblickInstallationFailed.txt" contents: [NSData data] attributes: [NSDictionary dictionary]];
    chown([@"/tmp/TunnelblickInstallationFailed.txt" UTF8String], realUserID, realGroupID);
    
    if (  argc != 4  ) {
        NSLog(@"Tunnelblick Installer: Wrong number of arguments -- expected 3, given %d", argc-1);
        [pool release];
        exit(EXIT_FAILURE);
    }
    
    BOOL okToRecover  = strcmp(argv[1], "1") == 0;
    BOOL needToRepair = strcmp(argv[2], "1") == 0;
    BOOL removeBackup = strcmp(argv[3], "1") == 0;
    
    // Make sure /Library/Application Support/Tunnelblick/Shared exists
    createDir(@"/Library/Application Support/Tunnelblick/Shared");
    
    // If a backup of Resources/Deploy exists, and Resources/Deploy itself does not exist
    // Then restore it from the backup if the user gave permission to do so
    if (   [gFileMgr fileExistsAtPath: deployBackupPath isDirectory: &isDir]
        && isDir  ) {
        if (  ! (   [gFileMgr fileExistsAtPath: gDeployPath isDirectory: &isDir]
                 && isDir  )  ) {
            if (  okToRecover  ) {
                if (  ! [gFileMgr copyPath:deployBackupPath toPath: gDeployPath handler:nil]  ) {
                    NSLog(@"Tunnelblick Installer: Unable to restore %@ from backup", gDeployPath);
                    [pool release];
                    exit(EXIT_FAILURE);
                } else {
                    NSLog(@"Tunnelblick Installer: Restored %@ from backup", gDeployPath);
                }
            }
        }
    }
    
    // If the backup of Deploy should be removed, first remove the folder that holds all
    // three copies, then delete parent folders up the hierarchy if they are empty or only have .DS_Store
    if (  removeBackup  ) {
        if (   [gFileMgr fileExistsAtPath: deployBkupHolderPath isDirectory: &isDir]
            && isDir  ) {
            if (  ! [gFileMgr removeFileAtPath: deployBkupHolderPath handler:nil]  ) {
                NSLog(@"Tunnelblick Installer: Unable to remove %@", deployBkupHolderPath);
                [pool release];
                exit(EXIT_FAILURE);
            }
            NSString * curDir = [deployBkupHolderPath stringByDeletingLastPathComponent];
            do
            {   
                if (   [gFileMgr fileExistsAtPath: curDir isDirectory: &isDir]
                    && isDir  ) {
                    NSArray * contents = [gFileMgr directoryContentsAtPath: curDir];
                    if (  contents  ) {
                        if (  ([contents count] == 0)
                            || (   ([contents count] == 1)
                                && [[contents objectAtIndex:0] isEqualToString:@".DS_Store"]  )
                            ) {
                            if (  ! [gFileMgr removeFileAtPath: curDir handler:nil]  ) {
                                NSLog(@"Tunnelblick Installer: Unable to remove %@", curDir);
                                [pool release];
                                exit(EXIT_FAILURE);
                            }
                        } else {
                            break;
                        }
                        curDir = [curDir stringByDeletingLastPathComponent];
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            } while (  [curDir length] != 0  );
        }
    }
    
    // If need to repair ownership and/or permissions of Tunnelblick.app and/or move the configuration folder, do so:
    if ( needToRepair ) {
        NSString *installerPath         = [thisBundle stringByAppendingPathComponent:@"/installer"];
        NSString *openvpnstartPath      = [thisBundle stringByAppendingPathComponent:@"/openvpnstart"];
        NSString *openvpnPath           = [thisBundle stringByAppendingPathComponent:@"/openvpn"];
        NSString *leasewatchPath        = [thisBundle stringByAppendingPathComponent:@"/leasewatch"];
        NSString *clientUpPath          = [thisBundle stringByAppendingPathComponent:@"/client.up.osx.sh"];
        NSString *clientDownPath        = [thisBundle stringByAppendingPathComponent:@"/client.down.osx.sh"];
        NSString *clientNoMonUpPath     = [thisBundle stringByAppendingPathComponent:@"/client.nomonitor.up.osx.sh"];
        NSString *clientNoMonDownPath   = [thisBundle stringByAppendingPathComponent:@"/client.nomonitor.down.osx.sh"];
        NSString *infoPlistPath         = [[[installerPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"Info.plist"];
        
        // Create arrays of arguments for the chmod command to set permissions as follows:
        //        Info.plist is set to 644
        //        executables and standard scripts are set to 744
        //        For the contents of /Resources/Deploy and its subfolders:
        //            folders are set to 755, certificate & key files are set to 600, shell files are set to 744, all other file are set to 644
        NSMutableArray *chmod600Args = [NSMutableArray arrayWithObject: @"600"];
        NSMutableArray *chmod644Args = [NSMutableArray arrayWithObjects: @"644", infoPlistPath, nil];
        NSMutableArray *chmod744Args = [NSMutableArray arrayWithObjects: @"744",
                                        installerPath, openvpnPath, leasewatchPath,
                                        clientUpPath, clientDownPath, clientNoMonUpPath, clientNoMonDownPath, nil];
        NSMutableArray *chmod755Args = [NSMutableArray arrayWithObject: @"755"];
        NSArray * extensionsFor600Permissions = [NSArray arrayWithObjects: @"cer", @"crt", @"der", @"key", @"p12", @"p7b", @"p7c", @"pem", @"pfx", nil];
        
        NSString * file;
        NSDirectoryEnumerator *dirEnum = [gFileMgr enumeratorAtPath: gDeployPath];
        while (file = [dirEnum nextObject]) {
            NSString * ext  = [file pathExtension];
            NSString * filePath = [gDeployPath stringByAppendingPathComponent: file];
            if (   [gFileMgr fileExistsAtPath: filePath isDirectory: &isDir]
                && isDir  ) {
                [chmod755Args addObject: filePath];
            } else if ( [ext isEqualToString:@"sh"]  ) {
                [chmod744Args addObject: filePath];
            } else if (  [extensionsFor600Permissions containsObject: ext]  ) {
                [chmod600Args addObject: filePath];
            } else {
                [chmod644Args addObject: filePath];
            }
        }
        
        runTask(@"/usr/sbin/chown", [NSArray arrayWithObjects: @"-R", @"root:wheel", thisBundle, infoPlistPath, nil]);
        
        runTask(@"/bin/chmod",      [NSArray arrayWithObjects: @"4111", openvpnstartPath, nil]);
        
        if ( [chmod600Args count] > 1  ) { runTask(@"/bin/chmod", chmod600Args); }
        if ( [chmod644Args count] > 1  ) { runTask(@"/bin/chmod", chmod644Args); }
        if ( [chmod744Args count] > 1  ) { runTask(@"/bin/chmod", chmod744Args); }
        if ( [chmod755Args count] > 1  ) { runTask(@"/bin/chmod", chmod755Args); }
        
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
                            NSLog(@"Tunnelblick Installer: Warning: Tried to change ownership of folder %@, returned status = %d", newConfigDirHolderPath, errno);
                        }
                        if (  [gFileMgr movePath: oldConfigDirPath toPath: newConfigDirPath handler: nil]  ) {
                            if (  [gFileMgr createSymbolicLinkAtPath: oldConfigDirPath pathContent: newConfigDirPath]  ) {
                                NSLog(@"Tunnelblick Installer: Successfully moved configuration folder %@ to %@ and created a symbolic link in its place.", oldConfigDirPath, newConfigDirPath);
                                // Since we're running as root, owner of symbolic link is root:wheel. Try to change to real user:group
                                if (  0 != lchown([oldConfigDirPath UTF8String], realUserID, realGroupID)  ) {
                                    NSLog(@"Tunnelblick Installer: Warning: Tried to change ownership of symbolic link %@, returned status = %d ", oldConfigDirPath, errno);
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
    }
    
    // If Resources/Deploy exists, back it up -- saving the first configuration and the two most recent
    if (   [gFileMgr fileExistsAtPath: gDeployPath isDirectory: &isDir]
        && isDir  ) {
        createDir(deployBkupHolderPath);    // Create the folder that holds the backup folders if it doesn't already exist
        
        if (  ! (   [gFileMgr fileExistsAtPath: deployOrigBackupPath isDirectory: &isDir]
                 && isDir  )  ) {
            if (  ! [gFileMgr copyPath:gDeployPath toPath: deployOrigBackupPath handler:nil]  ) {
                NSLog(@"Tunnelblick Installer: Unable to make original backup of %@", gDeployPath);
                [pool release];
                exit(EXIT_FAILURE);
            }
        }
        
        [gFileMgr removeFileAtPath:deployPrevBackupPath handler:nil];                       // Make original backup. Ignore errors -- original backup may not exist yet
        [gFileMgr movePath: deployBackupPath toPath: deployPrevBackupPath handler: nil];    // Make backup of previous backup. Ignore errors -- previous backup may not exist yet
        
        if (  ! [gFileMgr copyPath:gDeployPath toPath: deployBackupPath handler:nil]  ) {    // Make backup of current
            NSLog(@"Tunnelblick Installer: Unable to make backup of %@", gDeployPath);
            [pool release];
            exit(EXIT_FAILURE);
        }
    }

    // We remove this file to indicate that the installation succeeded because the return code doesn't propogate back to our caller
    [gFileMgr removeFileAtPath: @"/tmp/TunnelblickInstallationFailed.txt" handler: nil];
    
    [pool release];
    exit(EXIT_SUCCESS);
}

void runTask(NSString *launchPath,NSArray *arguments) 
{
	NSTask* task = [[[NSTask alloc] init] autorelease];	
	[task setArguments:arguments];
	[task setLaunchPath:launchPath];
	
	NS_DURING {
		[task launch];
	} NS_HANDLER {
		NSLog(@"Tunnelblick Installer: Exception (%@) raised while launching installer execution of %@: %@", localException, launchPath, arguments);
		exit(EXIT_FAILURE);
	}
    NS_ENDHANDLER
	[task waitUntilExit];
    
    int status = [task terminationStatus];
    
    if (  status != 0  ) {
        NSLog(@"Tunnelblick Installer: Error return code %d from installer execution of %@: %@", status, launchPath, arguments);
        exit(EXIT_FAILURE);
    }
}

// Recursive function to create a directory if it doesn't already exist
void createDir(NSString * dirPath)
{
    BOOL isDir;
    if (   [gFileMgr fileExistsAtPath: dirPath isDirectory: &isDir]
        && isDir  ) {
        return;
    }
    
    createDir([dirPath stringByDeletingLastPathComponent]);
    
    if (  ! [gFileMgr createDirectoryAtPath: dirPath attributes: nil]  ) {
        NSLog(@"Tunnelblick Installer: Unable to create directory %@", dirPath);
    }
    
    return;
}
