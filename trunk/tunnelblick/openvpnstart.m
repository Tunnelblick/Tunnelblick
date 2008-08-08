/*
 * Copyright (c) 2004-2006 Angelo Laub
 * Contributions by Dirk Theisen
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2
 * as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program (see the file COPYING included with this
 * distribution); if not, write to the Free Software Foundation, Inc.,
 * 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */



#import <Foundation/Foundation.h>
#import <Foundation/NSDebug.h>
#import <sys/types.h>
#import <sys/stat.h>
#import <unistd.h>

int loadKexts();

BOOL configNeedsRepair(void);

NSString *execpath;
NSString* configPath;
int main(int argc, char** argv)
{
    
	if(argc != 4) {
		printf("Wrong number of arguments.\nUsage: ./openvpnstart configName managementPort\n");
		exit(0);
	}
	
	if(strlen(argv[2]) > 5 ){
		printf("Port number too big.\n");
		exit(0);
	} 
	
	
	BOOL useScripts = FALSE;
	if( atoi(argv[3]) == 1 ) useScripts = TRUE; 
	
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	NSArray* arguments;
	NSString *pathExtension = [NSString stringWithUTF8String:argv[1]];
	execpath = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
	NSString* directoryPath = [NSHomeDirectory() stringByAppendingPathComponent:@"/Library/openvpn"];
	configPath = [directoryPath stringByAppendingPathComponent:pathExtension];
	NSString* openvpnPath = [execpath stringByAppendingPathComponent: @"openvpn"];
	NSMutableString* upscriptPath = [[execpath stringByAppendingPathComponent: @"client.up.osx.sh"] mutableCopy];
	NSMutableString* downscriptPath = [[execpath stringByAppendingPathComponent: @"client.down.osx.sh"] mutableCopy];
	[upscriptPath replaceOccurrencesOfString:@" " withString:@"\\ " options:NSLiteralSearch range:NSMakeRange(0,[upscriptPath length])];
	[downscriptPath replaceOccurrencesOfString:@" " withString:@"\\ " options:NSLiteralSearch range:NSMakeRange(0,[downscriptPath length])];
	
	if(configNeedsRepair()) {
		NSLog(@"Config File needs to be owned by root:wheel and must not be world writeable.");
		exit(2);
	}
	
	// security: convert to int so we can be sure it's a number
	int port = atoi(argv[2]);
	
	if(useScripts) {
		arguments = [NSArray arrayWithObjects: 
					 @"--management-query-passwords",  
					 @"--cd", directoryPath, 
					 @"--daemon", 
					 @"--up", upscriptPath,
					 @"--down", downscriptPath, 
					 @"--management-hold", 
					 @"--management", @"127.0.0.1", [NSString stringWithFormat:@"%d",port],  
					 @"--config", configPath,
					 @"--script-security", @"2", // allow us to call the up and down scripts
					 nil];
	} else {
		arguments = [NSArray arrayWithObjects: 
					 @"--management-query-passwords",  
					 @"--cd", directoryPath, 
					 @"--daemon", 
					 @"--management-hold", 
					 @"--management", @"127.0.0.1", [NSString stringWithFormat:@"%d",port],  
					 @"--config", configPath,
					 nil];
	}
	loadKexts();
	NSTask* task = [[[NSTask alloc] init] autorelease];
	
	[task setLaunchPath:openvpnPath];
	
	[task setArguments:arguments];
	
	setuid(0);
	[task launch];
	[task waitUntilExit];
	[upscriptPath release];
	[downscriptPath release];
	[pool release];
	
	return 0;
}

int loadKexts() {
	NSString *tapPath = [execpath stringByAppendingPathComponent: @"tap.kext"];
	NSString *tunPath = [execpath stringByAppendingPathComponent: @"tun.kext"];
	NSTask* task = [[[NSTask alloc] init] autorelease];
	NSArray *arguments = [NSArray arrayWithObjects:tapPath, tunPath, nil];
	[task setLaunchPath:@"/sbin/kextload"];
	
	[task setArguments:arguments];
	
	setuid(0);
	[task launch];
	[task waitUntilExit];
	
	return 0;
}

BOOL configNeedsRepair(void)
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSDictionary *fileAttributes = [fileManager fileAttributesAtPath:configPath traverseLink:YES];
	unsigned long perms = [fileAttributes filePosixPermissions];
	NSString *octalString = [NSString stringWithFormat:@"%o",perms];
	NSNumber *fileOwner = [fileAttributes fileOwnerAccountID];
	
	if ( (![octalString isEqualToString:@"644"])  || (![fileOwner isEqualToNumber:[NSNumber numberWithInt:0]])) {
		NSLog(@"File %@ has permissions: %@, is owned by %@ and needs repair...\n",configPath,octalString,fileOwner);
		return YES;
	}
	return NO;
	
}