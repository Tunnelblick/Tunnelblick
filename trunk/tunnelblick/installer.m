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

int main(int argc, char *argv[]) 
{
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	NSString *thisBundle = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
	
	NSString *tunPath = [thisBundle stringByAppendingPathComponent:@"/tun.kext"];
	NSString *tapPath = [thisBundle stringByAppendingPathComponent:@"/tap.kext"];

	NSString *tunExecutable = [tunPath stringByAppendingPathComponent:@"/Contents/MacOS/tun"];
	NSString *tapExecutable = [tapPath stringByAppendingPathComponent:@"/Contents/MacOS/tap"];

	NSString *openvpnstartPath = [thisBundle stringByAppendingPathComponent:@"/openvpnstart"];
	NSString *openvpnPath = [thisBundle stringByAppendingPathComponent:@"/openvpn"];
	
	runTask(
			@"/usr/sbin/chown",
			[NSArray arrayWithObjects:@"-R",@"root:wheel",thisBundle,nil]
			);

	runTask(
			@"/bin/chmod",
			[NSArray arrayWithObjects:@"-R", @"755",tunPath,tapPath,nil]
			);
	
	runTask(
			@"/bin/chmod",
			[NSArray arrayWithObjects:@"744", tunExecutable, tapExecutable, openvpnstartPath, openvpnPath, nil]
			);
    
	runTask(
			@"/bin/chmod",
			[NSArray arrayWithObjects:@"4111",openvpnstartPath,nil]
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
		NSLog(@"Exception raised while executing openvpnstart %@: %@",launchPath, localException);
		exit(EXIT_FAILURE);
	}
    NS_ENDHANDLER
	[task waitUntilExit];
}
