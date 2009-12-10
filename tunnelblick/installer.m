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

#include "installer.h"
#include <unistd.h>
//#include <sys/types.h>

// NOTE: THIS PROGRAM MUST BE RUN AS ROOT VIA executeAuthorized
// This program takes three arguments that specify what it is to do:
// If the first is  "1", the user has given permission to recover Deploy from the backup copy.
// If the second is "1", the application's ownership/permissions should be repaired and/or the configuration folder moved and
//                       a symbolic link ~/Library/Application Support/Tunnelblick/Configurations created as ~/Library/openvpn
// If the third  is "1", the Deploy backup will be removed.

int main(int argc, char *argv[]) 
{
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
	NSString * thisBundle           = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
	NSString * deployPath           = [thisBundle stringByAppendingPathComponent:@"Deploy"];
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

    NSFileManager * fMgr                 = [NSFileManager defaultManager];
    BOOL            isDir;
    
    // We create this file to act as a flag that the installation failed. We delete it before a success return.
    [fMgr createFileAtPath: @"/tmp/TunnelblickInstallationFailed.txt" contents: [NSData data] attributes: [NSDictionary dictionary]];
    chown([@"/tmp/TunnelblickInstallationFailed.txt" UTF8String], realUserID, realGroupID);
    
    if (  argc != 4  ) {
        NSLog(@"Tunnelblick Installer: Wrong number of arguments -- expected 3, given %d", argc-1);
        [pool release];
        exit(EXIT_FAILURE);
    }
    
    BOOL okToRecover  = strcmp(argv[1], "1") == 0;
    BOOL needToRepair = strcmp(argv[2], "1") == 0;
    BOOL removeBackup = strcmp(argv[3], "1") == 0;
    
    // If a backup of Resources/Deploy exists, and Resources/Deploy itself does not exist
    // Then restore it from the backup if the user gave permission to do so
    if (  [fMgr fileExistsAtPath: deployBackupPath isDirectory: &isDir] && isDir  ) {
        if (  ! (  [fMgr fileExistsAtPath: deployPath isDirectory: &isDir] && isDir  )  ) {
            if (  okToRecover  ) {
                if (  ! [fMgr copyPath:deployBackupPath toPath: deployPath handler:nil]  ) {
                    NSLog(@"Tunnelblick Installer: Unable to restore %@ from backup", deployPath);
                    [pool release];
                    exit(EXIT_FAILURE);
                } else {
                    NSLog(@"Tunnelblick Installer: Restored %@ from backup", deployPath);
                }
            }
        }
    }
    
    // If the backup of Deploy should be removed, first remove the folder that holds all
    // three copies, then delete parent folders up the hierarchy if they are empty or only have .DS_Store
    if (  removeBackup  ) {
        if (  [fMgr fileExistsAtPath: deployBkupHolderPath isDirectory: &isDir] && isDir  ) {
            if (  ! [fMgr removeFileAtPath: deployBkupHolderPath handler:nil]  ) {
                NSLog(@"Tunnelblick Installer: Unable to remove %@", deployBkupHolderPath);
                [pool release];
                exit(EXIT_FAILURE);
            }
            NSString * curDir = [deployBkupHolderPath stringByDeletingLastPathComponent];
            do
            {   
                if ( [fMgr fileExistsAtPath: curDir isDirectory: &isDir] && isDir  ) {
                    NSArray * contents = [fMgr directoryContentsAtPath: curDir];
                    if (  contents  ) {
                        if (  ([contents count] == 0)
                            || (  ([contents count] == 1) && [[contents objectAtIndex:0] isEqualToString:@".DS_Store"]  )
                            ) {
                            if (  ! [fMgr removeFileAtPath: curDir handler:nil]  ) {
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
    
    // If need to repair ownership and/or permissions and/or move the configuration folder, do so:
    if ( needToRepair ) {
        NSString *installerPath         = [thisBundle stringByAppendingPathComponent:@"/installer"];
        NSString *openvpnstartPath      = [thisBundle stringByAppendingPathComponent:@"/openvpnstart"];
        NSString *openvpnPath           = [thisBundle stringByAppendingPathComponent:@"/openvpn"];
        NSString *leasewatchPath        = [thisBundle stringByAppendingPathComponent:@"/leasewatch"];
        NSString *clientUpPath          = [thisBundle stringByAppendingPathComponent:@"/client.up.osx.sh"];
        NSString *clientDownPath        = [thisBundle stringByAppendingPathComponent:@"/client.down.osx.sh"];
        NSString *clientNoMonUpPath     = [thisBundle stringByAppendingPathComponent:@"/client.nomonitor.up.osx.sh"];
        NSString *clientNoMonDownPath   = [thisBundle stringByAppendingPathComponent:@"/client.nomonitor.down.osx.sh"];
        
        // Create arrays of arguments for the chmod command to set permissions for files in /Resources/Deploy
        // as follows: .crt and .key files are set to 600, shell files are set to 744, ana all other file are set to 644
        NSMutableArray *chmod600Args = [NSMutableArray arrayWithObject: @"600"];
        NSMutableArray *chmod644Args = [NSMutableArray arrayWithObject: @"644"];
        NSMutableArray *chmod744Args = [NSMutableArray arrayWithObjects: @"744",
                                        installerPath, openvpnPath, leasewatchPath,
                                        clientUpPath, clientDownPath, clientNoMonUpPath, clientNoMonDownPath, nil];
        NSArray * extensionsFor600Permissions = [NSArray arrayWithObjects: @"cer", @"crt", @"der", @"key", @"p12", @"p7b", @"p7c", @"pem", @"pfx", nil];
        
        NSArray *dirContents = [[NSFileManager defaultManager] directoryContentsAtPath: deployPath];
        int i;
        for (i=0; i<[dirContents count]; i++) {
            NSString * file = [dirContents objectAtIndex: i];
            NSString * ext  = [file pathExtension];
            if ( [ext isEqualToString:@"sh"]  ) {
                [chmod744Args addObject:[deployPath stringByAppendingPathComponent: file]];
            } else if (  [extensionsFor600Permissions containsObject: ext]  ) {
                [chmod600Args addObject:[deployPath stringByAppendingPathComponent: file]];
            } else {
                [chmod644Args addObject:[deployPath stringByAppendingPathComponent: file]];
            }
        }
        
        runTask(@"/usr/sbin/chown", [NSArray arrayWithObjects: @"-R", @"root:wheel", thisBundle, nil]);
        
        runTask(@"/bin/chmod",      [NSArray arrayWithObjects: @"4111", openvpnstartPath, nil]);
        
        if ( [chmod600Args count] > 1  ) { runTask(@"/bin/chmod", chmod600Args); }
        if ( [chmod644Args count] > 1  ) { runTask(@"/bin/chmod", chmod644Args); }
        if ( [chmod744Args count] > 1  ) { runTask(@"/bin/chmod", chmod744Args); }
        
        // Move configuration folder to new place in file hierarchy if necessary
        NSString * oldConfigDirPath       = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/openvpn"];
        NSString * newConfigDirHolderPath = [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Application Support/Tunnelblick"];
        NSString * newConfigDirPath       = [newConfigDirHolderPath stringByAppendingPathComponent: @"Configurations"];
        
        if (  ! [fMgr fileExistsAtPath: newConfigDirHolderPath]  ) {
            if (  ! [fMgr fileExistsAtPath: newConfigDirPath]  ) {
                NSDictionary * fileAttributes = [fMgr fileAttributesAtPath: oldConfigDirPath traverseLink: NO]; // Want to see if it is a link, so traverseLink:NO
                if (  ! [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
                    if (  [fMgr fileExistsAtPath: oldConfigDirPath isDirectory: &isDir] && isDir  ) {
                        createDir(newConfigDirHolderPath);
                        // Since we're running as root, owner of 'newConfigDirHolderPath' is root:wheel. Try to change to real user:group
                        if (  0 != chown([newConfigDirHolderPath UTF8String], realUserID, realGroupID)  ) {
                            NSLog(@"Tunnelblick Installer: Warning: Tried to change ownership of folder %@, returned status = %d", newConfigDirHolderPath, errno);
                        }
                        if (  [fMgr movePath: oldConfigDirPath toPath: newConfigDirPath handler: nil]  ) {
                            if (  [fMgr createSymbolicLinkAtPath: oldConfigDirPath pathContent: newConfigDirPath]  ) {
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
    NSArray * deployContents = [fMgr directoryContentsAtPath:deployPath];
    if (  deployContents != nil  ) {
        createDir(deployBkupHolderPath);    // Create the folder that holds the backup folders if it doesn't already exist
        
        if (  ! (  [fMgr fileExistsAtPath: deployOrigBackupPath isDirectory: &isDir] && isDir  )  ) {
            if (  ! [fMgr copyPath:deployPath toPath: deployOrigBackupPath handler:nil]  ) {
                NSLog(@"Tunnelblick Installer: Unable to make original backup of %@", deployPath);
                [pool release];
                exit(EXIT_FAILURE);
            }
        }
        
        [fMgr removeFileAtPath:deployPrevBackupPath handler:nil];                       // Make original backup. Ignore errors -- original backup may not exist yet
        [fMgr movePath: deployBackupPath toPath: deployPrevBackupPath handler: nil];    // Make backup of previous backup. Ignore errors -- previous backup may not exist yet
        
        if (  ! [fMgr copyPath:deployPath toPath: deployBackupPath handler:nil]  ) {    // Make backup of current
            NSLog(@"Tunnelblick Installer: Unable to make backup of %@", deployPath);
            [pool release];
            exit(EXIT_FAILURE);
        }
    }

    // We remove this file to indicate that the installation succeeded because the return code doesn't propogate back to our caller
    [fMgr removeFileAtPath: @"/tmp/TunnelblickInstallationFailed.txt" handler: nil];
    
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
void createDir(NSString * d)
{
    NSFileManager * fMgr = [NSFileManager defaultManager];
    BOOL isDir;
    if (  [fMgr fileExistsAtPath: d isDirectory: &isDir] && isDir  ) {
        return;
    }
    
    createDir([d stringByDeletingLastPathComponent]);
    
    if (  ! [fMgr createDirectoryAtPath: d attributes: nil]  ) {
        NSLog(@"Tunnelblick Installer: Unable to create directory %@", d);
    }
    
    return;
}
