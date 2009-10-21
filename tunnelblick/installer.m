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

int main(int argc, char *argv[]) 
{
	NSAutoreleasePool *pool = [NSAutoreleasePool new];

	NSString *thisBundle = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
	
	NSString *openvpnstartPath = [thisBundle stringByAppendingPathComponent:@"/openvpnstart"];
	NSString *openvpnPath      = [thisBundle stringByAppendingPathComponent:@"/openvpn"];
	NSString *leasewatchPath   = [thisBundle stringByAppendingPathComponent:@"/leasewatch"];
	NSString *clientUpPath     = [thisBundle stringByAppendingPathComponent:@"/client.up.osx.sh"];
	NSString *clientDownPath   = [thisBundle stringByAppendingPathComponent:@"/client.down.osx.sh"];
    
    // After we set ownership of everything to root:wheel, we must restore the original ownership of .key and .crt files
    // so they can be copied to ~/Library/openvpn. Their permissions usually set to owner=r/w, others=none, so to copy them
    // in createDefaultConfig..., which runs as the user, the owner must be the user, not root
    
    // Construct an array with args to chown for the restore. First arg is user:group
    uid_t usr = getuid();
    gid_t grp = getgid();
    NSMutableArray *restoreArgs = [NSMutableArray arrayWithObject: [NSString stringWithFormat:@"%d:%d", usr, grp]];
    
    //The rest of the args to chown are paths to all of the .crt and .key files in Resources
    NSArray *dirContents = [[NSFileManager defaultManager] directoryContentsAtPath: thisBundle];
    int i;
    for (i=0; i<[dirContents count]; i++) {
        NSString * file = [dirContents objectAtIndex: i];
        if ( [[file pathExtension] isEqualToString:@"crt"] || [[file pathExtension] isEqualToString:@"key"]  ) {
            [restoreArgs addObject:[thisBundle stringByAppendingPathComponent: file]];
        }
    }

	runTask(
			@"/usr/sbin/chown",
			[NSArray arrayWithObjects:@"-R",@"root:wheel",thisBundle,nil]
			);

    if (  [restoreArgs count] > 1  ) {
        runTask(
                @"/usr/sbin/chown",
                restoreArgs
                );
    }
        
	runTask(
			@"/bin/chmod",
			[NSArray arrayWithObjects:@"4111",openvpnstartPath,nil]
			);
	
	runTask(
			@"/bin/chmod",
			[NSArray arrayWithObjects:@"744", openvpnPath, leasewatchPath, clientUpPath, clientDownPath, nil]
			);
    
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
		NSLog(@"Exception raised while executing installer %@: %@(%@)",launchPath, arguments, localException);
		exit(EXIT_FAILURE);
	}
    NS_ENDHANDLER
	[task waitUntilExit];
}
