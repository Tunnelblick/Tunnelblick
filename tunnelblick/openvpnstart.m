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

int     startVPN			(NSString* configFile, int port, BOOL useScripts, BOOL skipScrSec, unsigned cfgLocCode);	//Tries to start an openvpn connection. May complain and exit if can't become root
void    StartOpenVPNWithNoArgs(void);        //Runs OpenVPN with no arguments, to get info including version #

void	killOneOpenvpn		(pid_t pid);	//Returns having killed an openvpn process, or complains and exits
int		killAllOpenvpn		(void);			//Kills all openvpn processes and returns the number of processes that were killed. May complain and exit

void	loadKexts			(void);			//Tries to load kexts -- no indication of failure. May complain and exit if can't become root
void	becomeRoot			(void);			//Returns as root, having setuid(0) if necessary; complains and exits if can't become root

void	getProcesses		(struct kinfo_proc** procs, int* number);	//Fills in process information
BOOL    processExists       (pid_t pid);    //Returns TRUE if the process exists
BOOL	isOpenvpn			(pid_t pid);	//Returns TRUE if process is an openvpn process (i.e., process name = "openvpn")
BOOL	configNeedsRepair	(void);			//Returns NO if configuration file is secure, otherwise complains and exits

NSString *escaped(NSString *string);        // Returns an escaped version of a string so it can be put in a command line

NSString*					execPath;		//Path to folder containing this executable, openvpn, tap.kext, tun.kext, client.up.osx.sh, and client.down.osx.sh
NSString*			        configPath;		//Path to configuration file (in ~/Library/openvpn/ or /Library/Application Support/Tunnelblick/Users/<username>/) or Resources/Deploy
NSAutoreleasePool*			pool;

int main(int argc, char* argv[])
{
    pool = [[NSAutoreleasePool alloc] init];
	
	BOOL	syntaxError	= TRUE;
    int     retCode = 0;
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
			if (  (argc > 3) && (argc < 8)  ) {
				NSString* configFile = [NSString stringWithUTF8String:argv[2]];
				if(strlen(argv[3]) < 6 ) {
					unsigned int port = atoi(argv[3]);
					if (port<=65535) {
						BOOL useScripts = FALSE; if( (argc > 4) && (atoi(argv[4]) == 1) ) useScripts = TRUE;
						BOOL skipScrSec = FALSE; if( (argc > 5) && (atoi(argv[5]) == 1) ) skipScrSec = TRUE;
						int  cfgLocCode = 0;     if( (argc > 6) )                         cfgLocCode  = atoi(argv[6]);
						if (cfgLocCode < 3) {
                            retCode = startVPN(configFile, port, useScripts, skipScrSec, cfgLocCode);
                            syntaxError = FALSE;
                        }
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
				"\t./openvpnstart start  configName  mgtPort  [useScripts  [skipScrSec  [cfgLocCode]  ]  ]\n\n"
				
				"Where:\n"
				"\tprocessId  is the process ID of the openvpn process to kill\n"
				"\tconfigName is the name of the configuration file\n"
				"\tmgtPort    is the port number (0-65535) to use for managing the connection\n"
				"\tuseScripts is 1 to run the client.up.osx.sh script before connecting, and client.down.osx.sh after disconnecting\n"
				"\t           (The scripts are in Tunnelblick.app/Contents/Resources/)\n"
                "\tskipScrSec is 1 to skip sending a '--script-security 2' argument to OpenVPN (versions before 2.1_rc9 don't implement it).\n"
                "\tcfgLocCode is 0 to use the standard configuration folder (~/Library/openvpn),\n"
                "\t           or 1 to use the alternate configuration folder (/Library/Application Support/Tunnelblick/Users/<username>),\n"
                "\t           or 2 to use the Resources/Deploy folder of the application as the configuration folder.\n\n"
				
				"useScripts, skipScrSec, and cfgLocCode each default to 0.\n\n"
				
				"The normal return code is 0. If an error occurs a message is sent to stderr and a code of 2 is returned.\n\n"
				
				"This executable must be in the same folder as openvpn, tap.kext, and tun.kext (and client.up.osx.sh and client.down.osx.sh if they are used).\n\n"
				
				"Tunnelblick must have been run and an administrator password entered at least once before openvpnstart can be used.\n"
				);
		[pool drain];
		exit(240);      // This exit code (240) is used in the VPNConnection connect: method to inhibit display of this long syntax error message
	}
	
	[pool drain];
	exit(retCode);
}

//Tries to start an openvpn connection -- no indication of failure. May complain and exit if can't become root
int startVPN(NSString* configFile, int port, BOOL useScripts, BOOL skipScrSec, unsigned cfgLocCode)
{
	NSString*	directoryPath	= [NSHomeDirectory() stringByAppendingPathComponent:@"/Library/openvpn"];
	NSString*	openvpnPath		= [execPath stringByAppendingPathComponent: @"openvpn"];
	NSString*	upscriptPath	= [execPath stringByAppendingPathComponent: @"client.up.osx.sh"];
	NSString*	downscriptPath	= [execPath stringByAppendingPathComponent: @"client.down.osx.sh"];
    NSString*   deployDirPath   = [execPath stringByAppendingPathComponent: @"Deploy"];

	switch (cfgLocCode) {
        case 0:
            configPath = [directoryPath stringByAppendingPathComponent:configFile];
            break;
            
        case 1:
            configPath = [NSString stringWithFormat:@"/Library/Application Support/Tunnelblick/Users/%@/%@", NSUserName(), configFile];
            break;
            
        case 2:
            configPath = [deployDirPath stringByAppendingPathComponent:configFile];
            directoryPath = deployDirPath;
            break;
            
        default:
            NSLog(@"Tunnelblick internal error: invalid cfgLocCode in startVPN()");
            exit(251);
            break;
    }

    if(configNeedsRepair()) {
		[pool drain];
		exit(241);
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
		  @"--up", escaped(upscriptPath),
		  @"--down", escaped(downscriptPath),
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
    
    int retCode = [task terminationStatus];
    if (  retCode != 0  ) {
        if (  retCode != 1  ) {
            fprintf(stderr, "Error: OpenVPN returned with status %d\n", retCode);
        } else {
            fprintf(stderr, "Error: OpenVPN returned with status %d. Possible error in configuration file. See \"All Messages\" in Console for details\n", retCode);
        }
        [pool drain];
		exit(242);
    }
    return 0;
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
	
    if (  ! processExists(pid)  ) {
        fprintf(stderr, "Error: Process %d does not exist\n", pid);
        [pool drain];
        exit(243);
    }
        
	if(isOpenvpn(pid)) {
		becomeRoot();
		didnotKill = kill(pid, SIGTERM);
		if (didnotKill) {
			fprintf(stderr, "Error: Unable to kill openvpn process %d\n", pid);
			[pool drain];
			exit(244);
		}
	} else {
		fprintf(stderr, "Error: Process %d is not an openvpn process\n", pid);
		[pool drain];
		exit(245);
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
		exit(246);
	}
	
	return(nKilled);
}

//Tries to load kexts. May complain and exit if can't become root or if can't load kexts
void loadKexts(void)
{
	NSString*	tapPath		= [execPath stringByAppendingPathComponent: @"tap.kext"];
	NSString*	tunPath		= [execPath stringByAppendingPathComponent: @"tun.kext"];
	NSTask*		task		= [[[NSTask alloc] init] autorelease];
	NSArray*	arguments	= [NSArray arrayWithObjects:@"-q", tapPath, tunPath, nil];
	
	[task setLaunchPath:@"/sbin/kextload"];
	
	[task setArguments:arguments];
	
	becomeRoot();
	[task launch];
	[task waitUntilExit];

    int status = [task terminationStatus];
    if (  status != 0  ) {
        fprintf(stderr, "Error: Unable to load tun and tap kexts. Status = %d\n", status);
        [pool drain];
        exit(247);
    }
}

//Returns as root, having setuid(0) if necessary; complains and exits if can't become root
void becomeRoot(void)
{
	if (getuid()  != 0) {
		if (  setuid(0)  ) {
			fprintf(stderr, "Error: Unable to become root\n"
							"You must have run Tunnelblick and entered an administrator password at least once to use openvpnstart\n");
			[pool drain];
			exit(248);
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

//Returns TRUE if process exists, otherwise returns FALSE
BOOL processExists(pid_t pid)
{
	BOOL				does_exist	= FALSE;
	int					count		= 0,
	i			= 0;
	struct kinfo_proc*	info		= NULL;
	
	getProcesses(&info, &count);
    for (i = 0; i < count; i++) {
        pid_t thisPid = info[i].kp_proc.p_pid;
        if (pid == thisPid) {
				does_exist = TRUE;
            break;
        }
    }    
    free(info);
	return does_exist;
}

//Returns NO if configuration file is secure, otherwise complains and exits
BOOL configNeedsRepair(void)
{
	NSFileManager*	fileManager		= [NSFileManager defaultManager];
	NSDictionary*	fileAttributes	= [fileManager fileAttributesAtPath:configPath traverseLink:YES];

	if (fileAttributes == nil) {
		fprintf(stderr, "Error: %s does not exist\n", [configPath UTF8String]);
		[pool drain];
		exit(249);
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
		exit(250);
	}
	return NO;
}

// Returns an escaped version of a string so it can be put following an --up or --down option in the OpenVPN command line
NSString *escaped(NSString *string)
{
	return [NSString stringWithFormat:@"\"%@\"", string];
}

