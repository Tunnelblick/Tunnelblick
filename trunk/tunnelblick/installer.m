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

// This program takes one optional argument.
// If there is an argument, and it is "1", the user has given permission to recover Deploy from the backup copy.
// Otherwise, the user has NOT given such permission.
int main(int argc, char *argv[]) 
{
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
	NSString      * thisBundle       = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
	NSString      * deployPath       = [thisBundle stringByAppendingPathComponent:@"Deploy"];
    NSString      * deployBackupPath = [[[[[[@"/Library/Application Support/Tunnelblick/Backup" stringByAppendingPathComponent: thisBundle]
                                            stringByDeletingLastPathComponent]
                                           stringByDeletingLastPathComponent]
                                          stringByDeletingLastPathComponent]
                                         stringByAppendingPathComponent: @"TunnelblickBackup"]
                                        stringByAppendingPathComponent: @"Deploy"];
    NSFileManager * fMgr             = [NSFileManager defaultManager];
    BOOL            isDir;
    
    // If a backup of Resources/Deploy exists, and Resources/Deploy itself does not exist, then restore it from the backup if the user gave permission to do so
    if (  [fMgr fileExistsAtPath: deployBackupPath isDirectory: &isDir] && isDir  ) {
        if (  ! (  [fMgr fileExistsAtPath: deployPath isDirectory: &isDir] && isDir  )  ) {
            if (  (argc > 1)  && (strcmp(argv[1], "1") == 0)  ) {
                if (  ! [fMgr copyPath:deployBackupPath toPath: deployPath handler:nil]  ) {
                    NSLog(@"Tunnelblick Installer: Unable to restore %@ from backup", deployPath);
                    exit(EXIT_FAILURE);
                } else {
                    NSLog(@"Tunnelblick Installer: Restored %@ from backup", deployPath);
                }
            }
        }
    }
    
	NSString *installerPath    = [thisBundle stringByAppendingPathComponent:@"/installer"];
	NSString *openvpnstartPath = [thisBundle stringByAppendingPathComponent:@"/openvpnstart"];
	NSString *openvpnPath      = [thisBundle stringByAppendingPathComponent:@"/openvpn"];
	NSString *leasewatchPath   = [thisBundle stringByAppendingPathComponent:@"/leasewatch"];
	NSString *clientUpPath     = [thisBundle stringByAppendingPathComponent:@"/client.up.osx.sh"];
	NSString *clientDownPath   = [thisBundle stringByAppendingPathComponent:@"/client.down.osx.sh"];
    
    // Create arrays of arguments for the chmod command to set permissions for files in /Resources/Deploy
    // as follows: .crt and .key files are set to 600, shell files are set to 744, ana all other file are set to 644
    NSMutableArray *chmod600Args = [NSMutableArray arrayWithObject: @"600"];
    NSMutableArray *chmod644Args = [NSMutableArray arrayWithObject: @"644"];
    NSMutableArray *chmod744Args = [NSMutableArray arrayWithObject: @"744"];
    
    NSArray *dirContents = [[NSFileManager defaultManager] directoryContentsAtPath: deployPath];
    int i;
    for (i=0; i<[dirContents count]; i++) {
        NSString * file = [dirContents objectAtIndex: i];
        NSString * ext  = [file pathExtension];
        if ( [ext isEqualToString:@"crt"] || [ext  isEqualToString:@"key"]  ) {
            [chmod600Args addObject:[deployPath stringByAppendingPathComponent: file]];
        } else if ( [ext isEqualToString:@"sh"]  ) {
            [chmod744Args addObject:[deployPath stringByAppendingPathComponent: file]];
        } else {
            [chmod644Args addObject:[deployPath stringByAppendingPathComponent: file]];
        }
    }
    
	runTask(@"/usr/sbin/chown",
			[NSArray arrayWithObjects:@"-R",@"root:wheel",thisBundle,nil]
			);
    
	runTask(@"/bin/chmod",
			[NSArray arrayWithObjects: @"4111", openvpnstartPath, nil]
			);
	
	runTask(@"/bin/chmod",
			[NSArray arrayWithObjects:@"744", openvpnPath, leasewatchPath, clientUpPath, clientDownPath, nil]
			);
    
	if ( [chmod600Args count] > 1  ) {
        runTask(@"/bin/chmod",
                chmod600Args
                );
    }
    
	if ( [chmod644Args count] > 1  ) {
        runTask(@"/bin/chmod",
                chmod644Args
                );
    }
    
    if ( [chmod744Args count] > 1  ) {
        runTask(@"/bin/chmod",
                chmod744Args
                );
    }
    
    // We have protected everything. Give this installer suid.
    runTask(@"/bin/chmod",
			[NSArray arrayWithObjects: @"4111", installerPath, nil]
			);
	
    // Backup Resources/Deploy if it exists, saving the first configuration and the two most recent
    NSString * deployOrigBackupPath = [[deployBackupPath stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"OriginalDeploy"];
    NSString * deployPrevBackupPath = [[deployBackupPath stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"PreviousDeploy"];
    NSArray  * deployContents       = [fMgr directoryContentsAtPath:deployPath];
    if (  deployContents != nil  ) {
        createDir([deployBackupPath stringByDeletingLastPathComponent]);                // If it doesn't exist, create the folder that holds the backup folders
        
        if (  ! (  [fMgr fileExistsAtPath: deployOrigBackupPath isDirectory: &isDir] && isDir  )  ) {
            if (  ! [fMgr copyPath:deployPath toPath: deployOrigBackupPath handler:nil]  ) {
                NSLog(@"Tunnelblick Installer: Unable to make original backup of %@", deployPath);
                exit(EXIT_FAILURE);
            }
        }
        
        [fMgr removeFileAtPath:deployPrevBackupPath handler:nil];                       // Ignore errors -- LastBackup may not exist yet
        [fMgr movePath: deployBackupPath toPath: deployPrevBackupPath handler: nil];    // Make backup of previous. Ignore errors -- previous may not exist yet
        
        if (  ! [fMgr copyPath:deployPath toPath: deployBackupPath handler:nil]  ) {    // Make backup of current
            NSLog(@"Tunnelblick Installer: Unable to make backup of %@", deployPath);
            exit(EXIT_FAILURE);
        }
    }
	
    [pool release];
	return 0;
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
