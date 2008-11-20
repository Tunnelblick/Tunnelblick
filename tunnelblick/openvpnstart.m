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
#import <sys/sysctl.h>
#import <signal.h>

int loadKexts();

BOOL configNeedsRepair(void);
int startVPN(NSString *pathExtension, NSString *execpath, int port, BOOL useScripts);
void killVPN(pid_t pid);
BOOL isOpenVPN(pid_t pid);
NSString *execpath;
NSString* configPath;

int main(int argc, char** argv)
{
    
	if(argc < 3) {
		fprintf(stdout, "Usage: ./openvpnstart command configName managementPort useScripts\n");
		exit(0);
	}
	
	NSAutoreleasePool *pool = [NSAutoreleasePool new];

	
	char *command = argv[1];
	if(strcmp(command, "kill") == 0) {
		pid_t pid = (pid_t) atoi(argv[2]);
		killVPN(pid);
	} else if(strcmp(command, "start") == 0) {
		NSString *pathExtension = [NSString stringWithUTF8String:argv[2]];
		execpath = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
		if(strlen(argv[3]) > 5 ){
			fprintf(stdout, "Port number too big.\n");
			exit(0);
		} 		
		int port = atoi(argv[3]);
		BOOL useScripts = FALSE;
		if( atoi(argv[4]) == 1 ) useScripts = TRUE;
		startVPN(pathExtension, execpath, port, useScripts);
	}
	
	
	
	[pool release];
	return 0;
}

int startVPN(NSString *pathExtension, NSString *execpath, int port, BOOL useScripts) {

	NSMutableArray* arguments;
	
	
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
	
	// default arguments to openvpn command line
	arguments = [NSMutableArray arrayWithObjects:
				 @"--management-query-passwords",  
				 @"--cd", directoryPath, 
				 @"--daemon", 
				 @"--management-hold", 
				 @"--management", @"127.0.0.1", [NSString stringWithFormat:@"%d",port],  
				 @"--config", configPath,
				 @"--script-security", @"2", // allow us to call the up and down scripts or scripts defined in config
				 nil
				 ];
	
	// conditionally push additional arguments to array
	if(useScripts) {
		[arguments addObjectsFromArray:
		 [NSArray arrayWithObjects:
		  @"--up", upscriptPath,
		  @"--down", downscriptPath,
		  nil
		  ]
		 ];
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
	
	
}

void killVPN(pid_t pid) 
{
	/* only allow to kill openvpn processes */
	if(isOpenVPN(pid)) {
		setuid(0);
		kill(pid, SIGTERM);		
	}
}

BOOL isOpenVPN(pid_t pid) 
{
	BOOL is_openvpn = FALSE;
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
	size_t length;
    int count, i;
    
    int level = 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) return;
    if (!(info = NSZoneMalloc(NULL, length))) return;
    if (sysctl(mib, level, info, &length, NULL, 0) < 0) {
        NSZoneFree(NULL, info);
        return;
    }
    
    count = length / sizeof(struct kinfo_proc);
    for (i = 0; i < count; i++) {
        char* process_name = info[i].kp_proc.p_comm;
        pid_t thisPid = info[i].kp_proc.p_pid;
        if (pid == thisPid) {
			if (strcmp(process_name, "openvpn")==0) {
				is_openvpn = TRUE;
			} else {
				is_openvpn = FALSE;
			}
			break;
		}
    }    
    NSZoneFree(NULL, info);
	return is_openvpn;
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
