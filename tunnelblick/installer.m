/*
 *  installer.c
 *  HotspotShield
 *
 *  Created by Angelo Laub on 7/12/06.
 *  Copyright 2006 __MyCompanyName__. All rights reserved.
 *
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

	NSString *helperPath = [thisBundle stringByAppendingPathComponent:@"/openvpnstart"];
	NSString *openvpnPath = [thisBundle stringByAppendingPathComponent:@"/openvpn"];
	
	runTask(
			@"/usr/sbin/chown",
			[NSArray arrayWithObjects:@"-R",@"root:wheel",thisBundle,nil]
			);

	
	runTask(
			@"/bin/chmod",
			[NSArray arrayWithObjects:@"-R",@"755",tunPath,tapPath,nil]
			);
	
	runTask(
			@"/bin/chmod",
			[NSArray arrayWithObjects:@"744",
				tunExecutable,
				tapExecutable,
				helperPath,
				openvpnPath,
				nil]
			);
	runTask(
			@"/bin/chmod",
			[NSArray arrayWithObjects:@"4111",helperPath,nil]
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
		NSLog(@"Exception raised while executing helper %@: %@",launchPath, localException);
		exit(EXIT_FAILURE);
	}
    NS_ENDHANDLER
	[task waitUntilExit];
}
