/*
 * Copyright (c) 2004, 2005, 2006, 2007, 2008, 2009 Angelo Laub
 * Contributions by Dirk Theisen and Jonathan K. Bullard
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

void	startVPN			(NSString* configFile, int port, BOOL useScripts, BOOL skipScrSec);	//Tries to start an openvpn connection. May complain and exit if can't become root
void    StartOpenVPNWithNoArgs(void);        //Runs OpenVPN with no arguments, to get info including version #

void	killOneOpenvpn		(pid_t pid);	//Returns having killed an openvpn process, or complains and exits
int		killAllOpenvpn		(void);			//Kills all openvpn processes and returns the number of processes that were killed. May complain and exit

void	loadKexts			(void);			//Tries to load kexts -- no indication of failure. May complain and exit if can't become root
void	becomeRoot			(void);			//Returns as root, having setuid(0) if necessary; complains and exits if can't become root

void	getProcesses		(struct kinfo_proc** procs, int* number);	//Fills in process information
BOOL	isOpenvpn			(pid_t pid);	//Returns TRUE if process is an openvpn process (i.e., process name = "openvpn")
BOOL	configNeedsRepair	(void);			//Returns NO if configuration file is secure, otherwise complains and exits

NSString*					execPath;		//Path to folder containing this executable, openvpn, tap.kext, tun.kext, client.up.osx.sh, and client.down.osx.sh
NSString*					configPath;		//Path to configuration file (in ~/Library/openvpn)
NSAutoreleasePool*			pool;

int main(int argc, char* argv[])
{
    pool = [[NSAutoreleasePool alloc] init];
	
	BOOL	syntaxError	= TRUE;
    
    execPath = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
	
    if (argc > 1) {
		char* command = argv[1];
		if( strcmp(command, "killall") == 0 ) {
			if (argc == 2) {
				int nKilled;
				nKilled = killAllOpenvpn();
				if (nKilled) {
					printf("%d openvpn processes killed\n", nKilled);
				}
				syntaxError = FALSE;
			}
		} else if( strcmp(command, "OpenVPNInfo") == 0 ) {
			if (argc == 2) {
                StartOpenVPNWithNoArgs();
				syntaxError = FALSE;
			}
            
        } else if( strcmp(command, "kill") == 0 ) {
			if (argc == 3) {
				pid_t pid = (pid_t) atoi(argv[2]);
				killOneOpenvpn(pid);
				syntaxError = FALSE;
			}
		} else if( strcmp(command, "start") == 0 ) {
			if (  (argc > 3) && (argc < 7)  ) {
				NSString* configFile = [NSString stringWithUTF8String:argv[2]];
				if(strlen(argv[3]) < 6 ) {
					unsigned int port = atoi(argv[3]);
					if (port<=65535) {
						BOOL useScripts = FALSE; if( (argc > 4) && (atoi(argv[4]) == 1) ) useScripts = TRUE;
						BOOL skipScrSec = FALSE; if( (argc > 5) && (atoi(argv[5]) == 1) ) skipScrSec = TRUE;
						startVPN(configFile, port, useScripts, skipScrSec);
						syntaxError = FALSE;
					}
				}
			}
		}
	}
	
	if (syntaxError) {
		fprintf(stderr, "openvpnstart usage:\n\n"
				
				"\t./openvpnstart OpenVPNInfo\n"
				"\t./openvpnstart killall\n"
				"\t./openvpnstart kill   processId\n"
				"\t./openvpnstart start  configName  mgtPort  [useScripts  [skipScrSec]  ]\n\n"
				
				"Where:\n"
				"\tprocessId  is the process ID of the openvpn process to kill\n"
				"\tconfigName is the name of the configuration file (which must be in ~/Library/openvpn)\n"
				"\tmgtPort    is the port number (0-65535) to use for managing the connection\n"
				"\tuseScripts is 1 to run the client.up.osx.sh script before connecting, and client.down.osx.sh after disconnecting\n"
				"\t           (The scripts are in Tunnelblick.app/Contents/Resources/)\n"
                "\tskipScrSec is 1 to skip sending a '--script-security 2' argument to OpenVPN (versions before 2.1_rc9 don't implement it).\n\n"
				
				"useScripts and skipScrSec each default to 0.\n\n"
				
				"The normal return code is 0. If an error occurs a message is sent to stderr and a code of 2 is returned.\n\n"
				
				"This executable must be in the same folder as openvpn, tap.kext, and tun.kext (and client.up.osx.sh and client.down.osx.sh if they are used).\n\n"
				
				"Tunnelblick must have been run and an administrator password entered at least once before openvpnstart can be used.\n"
				);
		[pool drain];
		exit(2);
	}
	
	[pool drain];
	exit(0);
}

//Tries to start an openvpn connection -- no indication of failure. May complain and exit if can't become root
void startVPN(NSString* configFile, int port, BOOL useScripts, BOOL skipScrSec)
{
	NSString*			directoryPath	= [NSHomeDirectory() stringByAppendingPathComponent:@"/Library/openvpn"];
    configPath		= [directoryPath stringByAppendingPathComponent:configFile];
	NSString*			openvpnPath		= [execPath stringByAppendingPathComponent: @"openvpn"];
	NSMutableString*	upscriptPath	= [[execPath stringByAppendingPathComponent: @"client.up.osx.sh"] mutableCopy];
	NSMutableString*	downscriptPath	= [[execPath stringByAppendingPathComponent: @"client.down.osx.sh"] mutableCopy];
	[upscriptPath replaceOccurrencesOfString:@" " withString:@"\\ " options:NSLiteralSearch range:NSMakeRange(0, [upscriptPath length])];
	[downscriptPath replaceOccurrencesOfString:@" " withString:@"\\ " options:NSLiteralSearch range:NSMakeRange(0, [downscriptPath length])];
	
	if(configNeedsRepair()) {
		[pool drain];
		exit(2);
	}
	
	// default arguments to openvpn command line
	NSMutableArray* arguments = [NSMutableArray arrayWithObjects:
								 @"--management-query-passwords",  
								 @"--cd", directoryPath, 
								 @"--daemon", 
								 @"--management-hold", 
								 @"--management", @"127.0.0.1", [NSString stringWithFormat:@"%d", port],  
								 @"--config", configPath,
								 nil
								 ];
	
	// conditionally push additional arguments to array
    
	if( ! skipScrSec ) {        // permissions must allow us to call the up and down scripts or scripts defined in config
		[arguments addObjectsFromArray: [NSArray arrayWithObjects: @"--script-security", @"2", nil]];
    }
    
    if(useScripts) {        // 'Set nameserver' specified, so use our standard scripts
		[arguments addObjectsFromArray:
		 [NSArray arrayWithObjects:
		  @"--up", upscriptPath,
		  @"--down", downscriptPath,
          @"--up-restart",
		  nil
          ]
         ];
	}
    
	loadKexts();
	
	NSTask* task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath:openvpnPath];
	[task setArguments:arguments];
	
	becomeRoot();
	[task launch];
	[task waitUntilExit];
    
	[upscriptPath release];
	[downscriptPath release];
}

//Starts OpenVPN with no arguments, to obtain version and usage info. May complain and exit if can't become root
void StartOpenVPNWithNoArgs(void)
{
	NSString* openvpnPath = [execPath stringByAppendingPathComponent: @"openvpn"];
	NSMutableArray* arguments = [NSMutableArray array];

	NSTask* task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath:openvpnPath];
	[task setArguments:arguments];
	
	becomeRoot();
	[task launch];
	[task waitUntilExit];
}

//Returns having killed an openvpn process, or complains and exits
void killOneOpenvpn(pid_t pid)
{
	int didnotKill;
	
	if(isOpenvpn(pid)) {
		becomeRoot();
		didnotKill = kill(pid, SIGTERM);
		if (didnotKill) {
			fprintf(stderr, "Error: Unable to kill openvpn process %d\n", pid);
			[pool drain];
			exit(2);
		}
	} else {
		fprintf(stderr, "Error: Process %d is not an openvpn process\n", pid);
		[pool drain];
		exit(2);
	}
}

//Kills all openvpn processes and returns the number of processes that were killed. May complain and exit if can't become root or some openvpn processes can't be killed
int killAllOpenvpn(void)
{
	int	count		= 0,
		i			= 0,
		nKilled		= 0,		//# of openvpn processes succesfully killed
		nNotKilled	= 0,		//# of openvpn processes not killed
		didnotKill;				//return value from kill() -- zero indicates killed successfully
	
	struct kinfo_proc*	info	= NULL;
	
	getProcesses(&info, &count);
	
	for (i = 0; i < count; i++) {
		char* process_name = info[i].kp_proc.p_comm;
		pid_t pid = info[i].kp_proc.p_pid;
		if(strcmp(process_name, "openvpn") == 0) {
			becomeRoot();
			didnotKill = kill(pid, SIGTERM);
			if (didnotKill) {
				fprintf(stderr, "Error: Unable to kill openvpn process %d\n", pid);
				nNotKilled++;
			} else {
				nKilled++;
			}
		}
	}
	
	free(info);
	
	if (nNotKilled) {
		// An error message for each openvpn process that wasn't killed has already been output
		[pool drain];
		exit(2);
	}
	
	return(nKilled);
}

//Tries to load kexts -- no indication of failure. May complain and exit if can't become root
void loadKexts(void)
{
	NSString*	tapPath		= [execPath stringByAppendingPathComponent: @"tap.kext"];
	NSString*	tunPath		= [execPath stringByAppendingPathComponent: @"tun.kext"];
	NSTask*		task		= [[[NSTask alloc] init] autorelease];
	NSArray*	arguments	= [NSArray arrayWithObjects:tapPath, tunPath, nil];
	
	[task setLaunchPath:@"/sbin/kextload"];
	
	[task setArguments:arguments];
	
	becomeRoot();
	[task launch];
	[task waitUntilExit];
}

//Returns as root, having setuid(0) if necessary; complains and exits if can't become root
void becomeRoot(void)
{
	if (getuid()  != 0) {
		if (  setuid(0)  ) {
			fprintf(stderr, "Error: Unable to become root\n"
							"You must have run Tunnelblick and entered an administrator password at least once to use openvpnstart\n");
			[pool drain];
			exit(2);
		}
	}
}

//Fills in process information
void getProcesses(struct kinfo_proc** procs, int* number)
{
	int					mib[4]	= { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct	kinfo_proc* info;
	size_t				length;
    int					level	= 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) return;
    if (!(info = malloc(length))) return;
    if (sysctl(mib, level, info, &length, NULL, 0) < 0) {
        free(info);
        return;
    }
	*procs = info;
	*number = length / sizeof(struct kinfo_proc);
}

//Returns TRUE if process is an openvpn process (i.e., process name = "openvpn"), otherwise returns FALSE
BOOL isOpenvpn(pid_t pid)
{
	BOOL				is_openvpn	= FALSE;
	int					count		= 0,
	i			= 0;
	struct kinfo_proc*	info		= NULL;
	
	getProcesses(&info, &count);
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
    free(info);
	return is_openvpn;
}

//Returns NO if configuration file is secure, otherwise complains and exits
BOOL configNeedsRepair(void)
{
	NSFileManager*	fileManager		= [NSFileManager defaultManager];
	NSDictionary*	fileAttributes	= [fileManager fileAttributesAtPath:configPath traverseLink:YES];

	if (fileAttributes == nil) {
		fprintf(stderr, "Error: %s does not exist\n", [configPath UTF8String]);
		[pool drain];
		exit(2);
	}
	
	unsigned long	perms			= [fileAttributes filePosixPermissions];
	NSString*		octalString		= [NSString stringWithFormat:@"%o", perms];
	NSNumber*		fileOwner		= [fileAttributes fileOwnerAccountID];
	
	if ( (![octalString isEqualToString:@"644"])  || (![fileOwner isEqualToNumber:[NSNumber numberWithInt:0]])) {
		NSString* errMsg = [NSString stringWithFormat:@"Error: File %@ is owned by %@ and has permissions %@\n"
							"Configuration files must be owned by root:wheel with permissions 0644\n",
							configPath, fileOwner, octalString];
		fprintf(stderr, [errMsg UTF8String]);
		[pool drain];
		exit(2);
	}
	return NO;
}
