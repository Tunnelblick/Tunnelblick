/*
 * Copyright (c) 2004-2006 Angelo Laub
 * Contributions by Dirk Theisen
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
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