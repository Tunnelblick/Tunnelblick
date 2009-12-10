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

//Tries to start an openvpn connection. May complain and exit if can't become root or if OpenVPN returns with error
int     startVPN			(NSString* configFile, int port, unsigned useScripts, BOOL skipScrSec, unsigned cfgLocCode, BOOL noMonitor);

void    StartOpenVPNWithNoArgs(void);        //Runs OpenVPN with no arguments, to get info including version #

void	killOneOpenvpn		(pid_t pid);	//Returns having killed an openvpn process, or complains and exits
int		killAllOpenvpn		(void);			//Kills all openvpn processes and returns the number of processes that were killed. May complain and exit
void    waitUntilAllGone    (void);         //Waits until all OpenVPN processes are gone or five seconds, whichever comes first

void	loadKexts			(void);			//Tries to load kexts. May complain and exit if can't become root or if can't load kexts
void	unloadKexts			(void);			//Tries to UNload kexts. May complain and exit if can't become root or if can't unload kexts
void	becomeRoot			(void);			//Returns as root, having setuid(0) if necessary; complains and exits if can't become root

void	getProcesses		(struct kinfo_proc** procs, int* number);	//Fills in process information
BOOL    processExists       (pid_t pid);    //Returns TRUE if the process exists
BOOL	isOpenvpn			(pid_t pid);	//Returns TRUE if process is an openvpn process (i.e., process name = "openvpn")
BOOL	configNeedsRepair	(void);			//Returns NO if configuration file is secure, otherwise complains and exits

NSString *escaped(NSString *string);        // Returns an escaped version of a string so it can be put after an --up or --down option in the OpenVPN command line

NSString*					execPath;		//Path to folder containing this executable, openvpn, tap.kext, tun.kext, client.up.osx.sh, and client.down.osx.sh
NSString*			        configPath;		//Path to configuration file (in ~/Library/Application Support/Tunnelblick/Configurations/ or /Library/Application Support/Tunnelblick/Users/<username>/) or Resources/Deploy
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
		} else if( strcmp(command, "loadKexts") == 0 ) {
			if (argc == 2) {
                loadKexts();
				syntaxError = FALSE;
			}
            
		} else if( strcmp(command, "unloadKexts") == 0 ) {
			if (argc == 2) {
                unloadKexts();
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
			if (  (argc > 3) && (argc < 9)  ) {
				NSString* configFile = [NSString stringWithUTF8String:argv[2]];
				if(strlen(argv[3]) < 6 ) {
					unsigned int port = atoi(argv[3]);
					if (port<=65535) {
						unsigned  useScripts = 0;     if(  argc > 4  )                         useScripts = atoi(argv[4]);
						BOOL      skipScrSec = FALSE; if( (argc > 5) && (atoi(argv[5]) == 1) ) skipScrSec = TRUE;
						unsigned  cfgLocCode = 0;     if(  argc > 6  )                         cfgLocCode = atoi(argv[6]);
						BOOL      noMonitor  = FALSE; if( (argc > 7) && (atoi(argv[7]) == 1) ) noMonitor = TRUE;
						if (cfgLocCode < 3) {
                            retCode = startVPN(configFile, port, useScripts, skipScrSec, cfgLocCode, noMonitor);
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
				"\t./openvpnstart loadKexts\n"
				"\t./openvpnstart unloadKexts\n"
				"\t./openvpnstart killall\n"
				"\t./openvpnstart kill   processId\n"
				"\t./openvpnstart start  configName  mgtPort  [useScripts  [skipScrSec  [cfgLocCode]  ]  ]\n\n"
				
				"Where:\n"
				"\tprocessId  is the process ID of the openvpn process to kill\n"
				"\tconfigName is the name of the configuration file\n"
				"\tmgtPort    is the port number (0-65535) to use for managing the connection\n"
				"\tuseScripts is 0 to not use scripts when the tunnel goes up or down (scripts may still be used in the configuration file)\n"
                "\t           or 1 to run scripts before connecting and after disconnecting\n"
				"\t                (The scripts are usually Tunnelblick.app/Contents/Resources/client.up.osx.sh & client.down.osx.sh, but see the cfgLocCode option)\n"
                "\t           or 2 to run the scripts, and also use the 'openvpn-down-root.so' plugin\n"
                "\tskipScrSec is 1 to skip sending a '--script-security 2' argument to OpenVPN (versions before 2.1_rc9 don't implement it).\n"
                "\tcfgLocCode is 0 to use the standard folder (~/Library/Application Support/Tunnelblick/Configurations) for configuration and other files,\n"
                "\t           or 1 to use the alternate folder (/Library/Application Support/Tunnelblick/Users/<username>)\n"
                "                  for configuration files and the standard folder for other files,\n"
                "\t           or 2 to use the Resources/Deploy folder for configuration and other files,\n"
                "\t                except that if Resources/Deploy contains only .conf, .ovpn, .up.sh, .down.sh and forced-preferences.plist files\n"
                "\t                            then ~/Library/Application Support/Tunnelblick/Configurations will be used for all other files (such as .crt and .key files)\n"
                "\t                and If 'useScripts' is 1 or 2\n"
                "\t                    Then If Resources/Deploy/<configName>.up.sh   exists, it is used instead of Resources/client.up.osx.sh,\n"
                "\t                     and If Resources/Deploy/<configName>.down.sh exists, it is used instead of Resources/client.down.osx.sh\n"
                "\tnoMonitor  is 0 to monitor the connection for interface configuration changes\n"
                "\t           or 1 to not monitor the connection for interface configuration changes\n\n"

				"useScripts, skipScrSec, cfgLocCode, and noMonitor each default to 0.\n\n"
				
				"The normal return code is 0. If an error occurs a message is sent to stderr and a code of 2 is returned.\n\n"
				
				"This executable must be in the same folder as openvpn, tap.kext, and tun.kext (and client.up.osx.sh and client.down.osx.sh if they are used).\n\n"
				
				"Tunnelblick must have been run and an administrator password entered at least once before openvpnstart can be used.\n\n"
                
                "For more information on using Resources/Deploy, see the Deployment wiki at http://code.google.com/p/tunnelblick/wiki/DeployingTunnelblick\n"
				);
		[pool drain];
		exit(240);      // This exit code (240) is used in the VPNConnection connect: method to inhibit display of this long syntax error message
	}
	
	[pool drain];
	exit(retCode);
}

//Tries to start an openvpn connection. May complain and exit if can't become root or if OpenVPN returns with error
int startVPN(NSString* configFile, int port, unsigned useScripts, BOOL skipScrSec, unsigned cfgLocCode, BOOL noMonitor)
{
	NSString*	directoryPath	= [NSHomeDirectory() stringByAppendingPathComponent:@"/Library/Application Support/Tunnelblick/Configurations"];
	NSString*	openvpnPath             = [execPath stringByAppendingPathComponent: @"openvpn"];
	NSString*	upscriptPath            = [execPath stringByAppendingPathComponent: @"client.up.osx.sh"];
	NSString*	downscriptPath          = [execPath stringByAppendingPathComponent: @"client.down.osx.sh"];
	NSString*	downRootPath            = [execPath stringByAppendingPathComponent: @"openvpn-down-root.so"];
    NSString*   deployDirPath           = [execPath stringByAppendingPathComponent: @"Deploy"];
	NSString*	upscriptNoMonitorPath	= [execPath stringByAppendingPathComponent: @"client.nomonitor.up.osx.sh"];
	NSString*	downscriptNoMonitorPath	= [execPath stringByAppendingPathComponent: @"client.nomonitor.down.osx.sh"];

    NSFileManager * fMgr = [NSFileManager defaultManager];

	switch (cfgLocCode) {
        case 0:
            configPath = [directoryPath stringByAppendingPathComponent:configFile];
            break;
            
        case 1:
            configPath = [NSString stringWithFormat:@"/Library/Application Support/Tunnelblick/Users/%@/%@", NSUserName(), configFile];
            break;
            
        case 2:
            configPath = [deployDirPath stringByAppendingPathComponent:configFile];

            // If Deploy contains anything other than *.conf, *.ovpn, *.up.sh, *.down.sh, and forced-preferences.plist files
            // Then use Deploy as the --cd directory
            BOOL onlyThoseFiles = TRUE;   // Assume Deploy contains only those files
            NSString *file;
            NSDirectoryEnumerator *dirEnum = [fMgr enumeratorAtPath: deployDirPath];
            while (file = [dirEnum nextObject]) {
                NSString * ext = [file pathExtension];
                if (  [file isEqualToString:@"forced-preferences.plist"]  || [file isEqualToString:@".DS_Store"]  ) {
                    // forced-preferences.plist and .DS_Store are OK
                } else if (  [ext isEqualToString: @"conf"] || [ext isEqualToString: @"ovpn"]  ) {
                    // *.conf and *.ovpn are OK
                } else {
                    // Not forced-preferences.plist, .DS_Store, *.conf, or *.ovpn
                    if (  [ext isEqualToString: @"sh"]  ) {
                        NSString * secondExt = [[file stringByDeletingPathExtension] pathExtension];
                        if (  [secondExt isEqualToString: @"up"] || [secondExt isEqualToString: @"down"]  ) {
                            // *.up.sh and *.down.sh are OK
                        } else {
                            // *.sh file, but not *.up.sh or *.down.sh
                            onlyThoseFiles = FALSE;
                            break;
                        }
                    } else {
                        // not forced-preferences.plist, .DS_Store, *.conf, *.ovpn, or *.sh -- probably *.crt or *.key
                        onlyThoseFiles = FALSE;
                        break;
                    }
                }
            }

            if (  ! onlyThoseFiles  ) {
                directoryPath = deployDirPath;
            }
            break;
            
        default:
            fprintf(stderr, "Syntax error: Invalid cfgLocCode (%d)\n", cfgLocCode);
            [pool drain];
            exit(238);
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
    
    if(  useScripts != 0  ) {  // 'Set nameserver' specified, so use our standard scripts or Deploy/<config>.up.sh and Deploy/<config>.down.sh
        if (  cfgLocCode == 2  ) {
            NSString * deployScriptPath = [deployDirPath stringByAppendingPathComponent: [configFile stringByDeletingPathExtension]];
            NSString * deployUpscriptPath   = [[deployScriptPath stringByAppendingPathExtension:@"up"]   stringByAppendingPathExtension:@"sh"];
            NSString * deployDownscriptPath = [[deployScriptPath stringByAppendingPathExtension:@"down"] stringByAppendingPathExtension:@"sh"];
            NSString * deployUpscriptNoMonitorPath   = [[[deployScriptPath stringByAppendingPathExtension:@"nomonitor"]
                                                         stringByAppendingPathExtension:@"up"] stringByAppendingPathExtension:@"sh"];
            NSString * deployDownscriptNoMonitorPath = [[[deployScriptPath stringByAppendingPathExtension:@"nomonitor"]
                                                         stringByAppendingPathExtension:@"down"] stringByAppendingPathExtension:@"sh"];
            
            if (  noMonitor  ) {
                if (  [fMgr fileExistsAtPath: deployUpscriptNoMonitorPath]  ) {
                    upscriptPath = deployUpscriptNoMonitorPath;
                } else if (  [fMgr fileExistsAtPath: deployUpscriptPath]  ) {
                    upscriptPath = deployUpscriptPath;
                } else {
                    upscriptPath = upscriptNoMonitorPath;
                }
                if (  [fMgr fileExistsAtPath: deployDownscriptNoMonitorPath]  ) {
                    downscriptPath = deployDownscriptNoMonitorPath;
                } else if (  [fMgr fileExistsAtPath: deployDownscriptPath]  ) {
                    downscriptPath = deployDownscriptPath;
                } else {
                    downscriptPath = downscriptNoMonitorPath;
                }
            } else {
                if (  [fMgr fileExistsAtPath: deployUpscriptPath]  ) {
                    upscriptPath = deployUpscriptPath;
                }
                if (  [fMgr fileExistsAtPath: deployDownscriptPath]  ) {
                    downscriptPath = deployDownscriptPath;
                }
            }

        } else {
            if (  noMonitor  ) {
                upscriptPath = upscriptNoMonitorPath;
                downscriptPath = downscriptNoMonitorPath;
            }
        }
        if (  useScripts == 2  ) {
            [arguments addObjectsFromArray: [NSArray arrayWithObjects:
                                             @"--up", escaped(upscriptPath),
                                             @"--plugin", downRootPath, escaped(downscriptPath),    // escaped because it is a shell command, not just a path
                                             @"--up-restart",
                                             nil
                                             ]
             ];
        } else if (  useScripts == 1  ) {
            [arguments addObjectsFromArray: [NSArray arrayWithObjects:
                                             @"--up", escaped(upscriptPath),        // escaped because it is a shell command, not just a path
                                             @"--down", escaped(downscriptPath),    // escaped because it is a shell command, not just a path
                                             @"--up-restart",
                                             nil
                                             ]
             ];
        } else {
            fprintf(stderr, "Syntax error: Invalid useScripts parameter (%d)\n", useScripts);
            [pool drain];
            exit(251);
            
        }
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
	
    waitUntilAllGone();

	if (nNotKilled) {
		// An error message for each openvpn process that wasn't killed has already been output
		[pool drain];
		exit(246);
	}
	
	return(nKilled);
}

//Waits until all OpenVPN processes are gone or five seconds, whichever comes first
void waitUntilAllGone(void)
{
    int count   = 0,
        i       = 0,
        j       = 0;
    
    BOOL found  = FALSE;
    
	struct kinfo_proc*	info	= NULL;
	
    for (j=0; j<6; j++) {   // Try up to six times, with one second _between_ each try -- max five seconds total
        
        if (j != 0) {       // Don't sleep the first time through
            sleep(1);
        }
        
        getProcesses(&info, &count);
        
        found = FALSE;
        for (i = 0; i < count; i++) {
            char* process_name = info[i].kp_proc.p_comm;
            if(strcmp(process_name, "openvpn") == 0) {
                found = TRUE;
                break;
            }
        }
        
        free(info);
        
        if (! found) {
            break;
        }
    }
    
    if (found) {
        fprintf(stderr, "Error: Timeout (5 seconds) waiting for openvpn process(es) to terminate\n");
    }
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

//Tries to UNload kexts. May complain and exit if can't become root or if can't unload kexts
void unloadKexts(void)
{
	NSString*	tapPath		= [execPath stringByAppendingPathComponent: @"tap.kext"];
	NSString*	tunPath		= [execPath stringByAppendingPathComponent: @"tun.kext"];
	NSTask*		task		= [[[NSTask alloc] init] autorelease];
	NSArray*	arguments	= [NSArray arrayWithObjects: tapPath, tunPath, nil];
	
	[task setLaunchPath:@"/sbin/kextunload"];
	
	[task setArguments:arguments];
	
	becomeRoot();
	[task launch];
	[task waitUntilExit];
    
    int status = [task terminationStatus];
    if (  status != 0  ) {
        fprintf(stderr, "Error: Unable to unload tun and tap kexts. Status = %d\n", status);
        [pool drain];
        exit(239);
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

// Returns an escaped version of a string so it can be put after an --up or --down option in the OpenVPN command line
NSString *escaped(NSString *string)
{
	return [NSString stringWithFormat:@"\"%@\"", string];
}

