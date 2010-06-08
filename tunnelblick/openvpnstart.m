/*
 * Copyright (c) 2004, 2005, 2006, 2007, 2008, 2009, 2010 Angelo Laub
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

#import "openvpnstart.h"
#import <Foundation/Foundation.h>
#import <sys/sysctl.h>
#import <netinet/in.h>
#import <sys/stat.h>

//Tries to start an openvpn connection. May complain and exit if can't become root or if OpenVPN returns with error
int     startVPN			(NSString* configFile, int port, unsigned useScripts, BOOL skipScrSec, unsigned cfgLocCode, BOOL noMonitor, unsigned int bitMask);
int     setupLog            (NSString* logPath); // Sets up the OpenVPN log file (for "without GUI" operation), which encodes the configuration file path and port info into the filename
NSString * createOpenVPNLog (NSString* configurationPath, int port);
BOOL    deleteLogFiles      (NSString * configurationPath);
int     runAsRoot           (NSString * thePath, NSArray * theArguments);
BOOL    createPipeForConfigAtPath (NSString * inPath);
NSString * constructOpenVPNLogPath (NSString * configurationPath, int port);

void    startOpenVPNWithNoArgs(void);        //Runs OpenVPN with no arguments, to get info including version #

void	killOneOpenvpn		(pid_t pid);	//Returns having killed an openvpn process, or complains and exits
int		killAllOpenvpn		(void);			//Kills all openvpn processes and returns the number of processes that were killed. May complain and exit
void    waitUntilAllGone    (void);         //Waits until all OpenVPN processes are gone or five seconds, whichever comes first

void	loadKexts			(unsigned int bitMask);	//Tries to load kexts. May complain and exit if can't become root or if can't load kexts
void	unloadKexts			(unsigned int bitMask);	//Tries to UNload kexts. Will complain and exit if can't become root
void	becomeRoot			(void);			//Returns as root, having setuid(0) if necessary; complains and exits if can't become root

void	getProcesses		(struct kinfo_proc** procs, int* number);	//Fills in process information
BOOL    processExists       (pid_t pid);    //Returns TRUE if the process exists
unsigned int getFreePort    (void);         //Returns a free port

BOOL	isOpenvpn			(pid_t pid);	//Returns TRUE if process is an openvpn process (i.e., process name = "openvpn")
BOOL	configNeedsRepair	(void);			//Returns NO if configuration file is secure, otherwise complains and exits
BOOL    checkOwnerAndPermissions (NSString * fPath, // Returns YES if file doesn't exist, or has the specified ownership and permissions
                                  uid_t      uid,
                                  gid_t      gid,
                                  NSString * permsShouldHave);

BOOL    itemIsVisible       (NSString * path); // Returns NO if path or any component of path is invisible (compenent starts with a '.')

NSString * configPathFromTblkPath(NSString * path);
NSString *escaped(NSString *string);        // Returns an escaped version of a string so it can be put after an --up or --down option in the OpenVPN command line

NSAutoreleasePool   * pool;
NSString			* configPath;   //Path to configuration file (in ~/Library/Application Support/Tunnelblick/Configurations/ or /Library/Application Support/Tunnelblick/Users/<username>/) or Resources/Deploy
NSString			* execPath;     //Path to folder containing this executable, openvpn, tap.kext, tun.kext, client.up.osx.sh, and client.down.osx.sh
NSFileManager       * gFileMgr;

//**************************************************************************************************************************
int main(int argc, char* argv[])
{
    pool = [[NSAutoreleasePool alloc] init];

    gFileMgr = [NSFileManager defaultManager];
    
	BOOL	syntaxError	= TRUE;
    int     retCode = 0;
    execPath = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];

    if (  ! checkOwnerAndPermissions([NSString stringWithUTF8String: argv[0]], 0, 0, @"4111")  ) {
        fprintf(stderr, "openvpnstart has not been secured\n"
                "You must have run Tunnelblick and entered an administrator password at least once to use openvpnstart\n");
        [pool drain];
        exit(235);
    }

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
                loadKexts(0);
				syntaxError = FALSE;
            } else if (  argc == 3 ) {
                unsigned int bitMask = atoi(argv[2]);
                if (  bitMask < 4  ) {
                    loadKexts(bitMask);
                    syntaxError = FALSE;
                }
			}
            
		} else if( strcmp(command, "unloadKexts") == 0 ) {
			if (argc == 2) {
                unloadKexts(0);
				syntaxError = FALSE;
            } else if (  argc == 3 ) {
                unsigned int bitMask = atoi(argv[2]);
                if (  bitMask < 16  ) {
                    unloadKexts(bitMask);
                    syntaxError = FALSE;
                }
			}
            
		} else if( strcmp(command, "OpenVPNInfo") == 0 ) {
			if (argc == 2) {
                startOpenVPNWithNoArgs();
				syntaxError = FALSE;
			}
            
        } else if( strcmp(command, "kill") == 0 ) {
			if (argc == 3) {
				pid_t pid = (pid_t) atoi(argv[2]);
				killOneOpenvpn(pid);
				syntaxError = FALSE;
			} else if (argc == 4) {
				pid_t pid = (pid_t) atoi(argv[2]);
				killOneOpenvpn(pid);
                deleteLogFiles( [NSString stringWithUTF8String: argv[3]] );
				syntaxError = FALSE;
			}
            
        } else if( strcmp(command, "postDisconnect") == 0) {
            if (  argc == 4) {
				NSString* configFile = [NSString stringWithUTF8String:argv[2]];
                unsigned  cfgLocCode = atoi(argv[3]);
                NSString * configPrefix = nil;
                switch (cfgLocCode) {
                    case 0:
                        configPrefix = [NSHomeDirectory() stringByAppendingPathComponent:@"/Library/Application Support/Tunnelblick/Configurations"];
                        break;
                    case 1:
                        configPrefix = [NSString stringWithFormat:@"/Library/Application Support/Tunnelblick/Users/%@", NSUserName()];
                        break;
                    case 2:
                        configPrefix = [execPath stringByAppendingPathComponent: @"Deploy"];
                        break;
                    case 3:
                        configPrefix = [NSString stringWithString: @"/Library/Application Support/Tunnelblick/Shared"];
                        break;
                    default:
                        break;
                }
                if (  configPrefix  ) {
                    syntaxError = FALSE;
                    configPath = [configPrefix stringByAppendingPathComponent: configFile];
                    configPath = [configPath stringByAppendingPathComponent: @"Contents/Resources/post-disconnect.sh"];
                    if (  [gFileMgr fileExistsAtPath: configPath]  ) {
                        if (  checkOwnerAndPermissions(configPath, 0, 0, @"744")  ) {
                            runAsRoot(configPath, [NSArray array]);
                        } else {
                            fprintf(stderr, "Error: %s is not secured\n", [configPath UTF8String]);
                        }
                    } else {
                        fprintf(stderr, "Error: openvpnstart postDisconnect cannot find file %s\n", [configPath UTF8String]);
                    }

                }
            }
		} else if( strcmp(command, "start") == 0 ) {
			if (  (argc > 3) && (argc < 10)  ) {
				NSString* configFile = [NSString stringWithUTF8String:argv[2]];
				if(strlen(argv[3]) < 6 ) {
					unsigned int port = atoi(argv[3]);
					if (port<=65535) {
						unsigned  useScripts = 0;     if(  argc > 4  )                         useScripts = atoi(argv[4]);
						BOOL      skipScrSec = FALSE; if( (argc > 5) && (atoi(argv[5]) == 1) ) skipScrSec = TRUE;
						unsigned  cfgLocCode = 0;     if(  argc > 6  )                         cfgLocCode = atoi(argv[6]);
						BOOL      noMonitor  = FALSE; if( (argc > 7) && (atoi(argv[7]) == 1) ) noMonitor  = TRUE;
						unsigned int bitMask = 0;     if(  argc > 8  )                         bitMask    = atoi(argv[8]);
						if (   (cfgLocCode < 4)
                            && (bitMask < 1024)  ) {
                            retCode = startVPN(configFile, port, useScripts, skipScrSec, cfgLocCode, noMonitor, bitMask);
                            syntaxError = FALSE;
                        }
					}
				}
			}
		}
	}

	if (syntaxError) {
		fprintf(stderr,
                "\n\nopenvpnstart usage:\n\n"
				
				"./openvpnstart OpenVPNInfo\n"
				"               to get information about OpenVPN\n\n"
                
				"./openvpnstart loadKexts     [bitMask]\n"
				"               to load .tun and .tap kexts\n\n"
                
				"./openvpnstart unloadKexts   [bitMask]\n"
				"               to unload the .tun and .tap kexts\n\n"
                
				"./openvpnstart killall\n"
				"               to terminate all processes named 'openvpn'\n\n"
                
				"./openvpnstart kill   processId   [configPath]\n"
				"               to terminate the 'openvpn' process with the specified processID and optionally delete the log file associated with the processs\n\n"
                
				"./openvpnstart start  configName  mgtPort  [useScripts  [skipScrSec  [cfgLocCode  [noMonitor  [bitMask  ]  ]  ]  ]  ]\n\n"
				"               to load tun.kext and tap.kext and start OpenVPN with the specified configuration file and options.\n\n"
				
				"./openvpnstart postDisconnect  configName  cfgLocCode\n\n"
				"               to run the post-disconnect.sh script inside a .tblk.\n\n"
				
				"Where:\n\n"
                
				"processId  is the process ID of the openvpn process to kill\n\n"
                
				"configPath is the full path to the configuration file, so that the log file associated with the configuration can be deleted\n\n"
                
				"configName is the name of the configuration file (a .conf or .ovpn file, or .tblk package)\n\n"
                
				"mgtPort    is the port number (0-65535) to use for managing the connection\n"
                "           or 0 to use a free port and create a log file encoding the configuration path and port number\n\n"
                
				"useScripts is 0 to not use scripts when the tunnel goes up or down (scripts may still be used in the configuration file)\n"
                "           or 1 to run scripts before connecting and after disconnecting\n"
				"                (The scripts are usually Tunnelblick.app/Contents/Resources/client.up.osx.sh & client.down.osx.sh, but see the cfgLocCode option)\n"
                "           or 2 to run the scripts, and also use the 'openvpn-down-root.so' plugin\n\n"
                
                "skipScrSec is 1 to skip sending a '--script-security 2' argument to OpenVPN (versions before 2.1_rc9 don't implement it).\n\n"
                
                "cfgLocCode is 0 to use the standard folder (~/Library/Application Support/Tunnelblick/Configurations) for configuration and other files,\n"
                "           or 1 to use the alternate folder (/Library/Application Support/Tunnelblick/Users/<username>)\n"
                "                for configuration files and the standard folder for other files,\n"
                "           or 2 to use the Resources/Deploy folder for configuration and other files,\n"
                "                except that if Resources/Deploy contains only .conf, .ovpn, .up.sh, .down.sh and forced-preferences.plist files\n"
                "                            then ~/Library/Application Support/Tunnelblick/Configurations will be used for all other files (such as .crt and .key files)\n"
                "                and If 'useScripts' is 1 or 2\n"
                "                    Then If Resources/Deploy/<configName>.up.sh   exists, it is used instead of Resources/client.up.osx.sh,\n"
                "                     and If Resources/Deploy/<configName>.down.sh exists, it is used instead of Resources/client.down.osx.sh\n"
                "           or 3 to use /Library/Application Support/Tunnelblick/Shared\n\n"
                
                "noMonitor  is 0 to monitor the connection for interface configuration changes\n"
                "           or 1 to not monitor the connection for interface configuration changes\n\n"
                
                "bitMask    contains a mask: bit 0 is 1 to unload/load net.tunnelblick.tun (bit 0 is the lowest ordered bit)\n"
                "                            bit 1 is 1 to unload/load net.tunnelblick.tap\n"
                "                            bit 2 is 1 to unload foo.tun\n"
                "                            bit 3 is 1 to unload foo.tap\n"
                "                            bit 4 is 1 to create a log file in /tmp with the configuration path and port number encoded in the filename\n"
                "                                          (Bit 4 is used only by the 'start' command; for the 'connect when system starts' feature)\n"
                "                                          (Bit 4 is forced to 1 if mgtPort = 0)\n"
                "                            bit 5 is 1 to restore settings on a reset of DNS  to pre-VPN settings (restarts connection otherwise)\n"
                "                            bit 6 is 1 to restore settings on a reset of WINS to pre-VPN settings (restarts connection otherwise)\n\n"
                
				"useScripts, skipScrSec, cfgLocCode, and noMonitor each default to 0.\n"
                "bitMask defaults to 0x03.\n\n"
                
                "If the configuration file's extension is '.tblk', the package is searched for the configuration file, and the OpenVPN '--cd'\n"
                "option is set to the path of the configuration's /Contents/Resources folder.\n\n"
				
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

//**************************************************************************************************************************
//Tries to start an openvpn connection. May complain and exit if can't become root or if OpenVPN returns with error
int startVPN(NSString* configFile, int port, unsigned useScripts, BOOL skipScrSec, unsigned cfgLocCode, BOOL noMonitor, unsigned int bitMask)
{
	NSString*	openvpnPath             = [execPath stringByAppendingPathComponent: @"openvpn"];
	NSString*	upscriptPath            = [execPath stringByAppendingPathComponent: @"client.up.osx.sh"];
	NSString*	downscriptPath          = [execPath stringByAppendingPathComponent: @"client.down.osx.sh"];
	NSString*	downRootPath            = [execPath stringByAppendingPathComponent: @"openvpn-down-root.so"];
    NSString*   deployDirPath           = [execPath stringByAppendingPathComponent: @"Deploy"];
	NSString*	upscriptNoMonitorPath	= [execPath stringByAppendingPathComponent: @"client.nomonitor.up.osx.sh"];
	NSString*	downscriptNoMonitorPath	= [execPath stringByAppendingPathComponent: @"client.nomonitor.down.osx.sh"];
	NSString*	newUpscriptPath         = [execPath stringByAppendingPathComponent: @"client.up.tunnelblick.sh"];
	NSString*	newDownscriptPath       = [execPath stringByAppendingPathComponent: @"client.down.tunnelblick.sh"];
    
    NSString * tblkPath = nil;  // Path to .tblk, or nil if configuration is .conf or .ovpn.
    
    NSString * cdFolderPath;
    
    if (  bitMask == 0  ) {
        bitMask = OUR_TAP_KEXT | OUR_TUN_KEXT;
    }

    // Determine path to the configuration file and the --cd folder
	switch (cfgLocCode) {
        case 0:
            cdFolderPath = [NSHomeDirectory() stringByAppendingPathComponent:@"/Library/Application Support/Tunnelblick/Configurations"];
            configPath = [cdFolderPath stringByAppendingPathComponent:configFile];
            break;
            
        case 1:
            cdFolderPath = [NSHomeDirectory() stringByAppendingPathComponent:@"/Library/Application Support/Tunnelblick/Configurations"];
            configPath = [NSString stringWithFormat:@"/Library/Application Support/Tunnelblick/Users/%@/%@", NSUserName(), configFile];
            break;
            
        case 2:
            cdFolderPath = [NSHomeDirectory() stringByAppendingPathComponent:@"/Library/Application Support/Tunnelblick/Configurations"];
            configPath = [deployDirPath stringByAppendingPathComponent: configFile];
            // If Deploy contains anything other than *.conf, *.ovpn, *.up.sh, *.down.sh, *.tblk, and forced-preferences.plist files
            // Then use Deploy as the --cd directory (but this is overridden later for .tblks)
            BOOL onlyThoseFiles = TRUE;   // Assume Deploy contains only those files
            NSString *file;
            NSDirectoryEnumerator *dirEnum = [gFileMgr enumeratorAtPath: deployDirPath];
            while (file = [dirEnum nextObject]) {
                if (  itemIsVisible([deployDirPath stringByAppendingPathComponent: file])  ) {
                    NSString * ext = [file pathExtension];
                    if (  [file isEqualToString:@"forced-preferences.plist"]  ) {
                        // forced-preferences.plist is OK
                    } else if (  [ext isEqualToString: @"ovpn"] || [ext isEqualToString: @"conf"] || [ext isEqualToString: @"tblk"]  ) {
                        // *.conf and *.ovpn and *.tblk are OK
                    } else {
                        // Not forced-preferences.plist, *.conf, *.ovpn, *.tblk
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
                            // not forced-preferences.plist, *.conf, *.ovpn, .tblk, or *.sh -- probably *.crt or *.key
                            onlyThoseFiles = FALSE;
                            break;
                        }
                    }
                }
            }
            
            if (  ! onlyThoseFiles  ) {
                cdFolderPath = deployDirPath;   // We override this later if a configuration is a .tblk package
            }
            break;
            
        case 3:
            if (  ! [[configFile pathExtension] isEqualToString: @"tblk"]) {
                fprintf(stderr, "Only Tunnelblick VPN Configurations (.tblk packages) may connect from /Library/Application Support/Tunnelblick/Shared\n");
                [pool drain];
                exit(237);
            }
            configPath = [@"/Library/Application Support/Tunnelblick/Shared" stringByAppendingPathComponent: configFile];
            cdFolderPath = @"/tmp";     // Will be set below since this is a .tblk. Set to /tmp to catch error if that doesn't happen for some reason
            break;
            
        default:
            fprintf(stderr, "Syntax error: Invalid cfgLocCode (%d)\n", cfgLocCode);
            [pool drain];
            exit(238);
    }
    
    // If this is a .tblk package, OVERRIDE any code above that sets directoryPath, and set the actual configuration path
    if (  [[configPath pathExtension] isEqualToString: @"tblk"]) {
        tblkPath = [[configPath copy] autorelease];
        NSString * cfg = configPathFromTblkPath(configPath);
        if (  ! cfg  ) {
            fprintf(stderr, "Unable to find configuration file in %s\n", [cfg UTF8String]);
            [pool drain];
            exit(236);
        }
        cdFolderPath = [configPath stringByAppendingPathComponent: @"Contents/Resources"];
        configPath = [cfg copy];
    }
    
    if(configNeedsRepair()) {
		[pool drain];
		exit(241);
	}
    
    BOOL withoutGUI = FALSE;
    if ( port == 0) {
        withoutGUI = TRUE;
        port = getFreePort();
    }

    NSString * logPath;
    if (   ( (bitMask & CREATE_LOG_FILE) != 0 )
        || withoutGUI  ) {
        logPath = createOpenVPNLog(configPath, port);
    }
        
    // default arguments to openvpn command line
	NSMutableArray* arguments = [NSMutableArray arrayWithObjects:
								 @"--cd", cdFolderPath,
								 @"--daemon", 
								 @"--management", @"127.0.0.1", [NSString stringWithFormat:@"%d", port],  
								 @"--config", configPath,
								 nil];
    
	// conditionally push additional arguments to array
    
	if ( withoutGUI ) {
        // We tell  OpenVPN to put the log into a file whose name encodes the path to the configuration file and the port # for the
        // OpenVPN management interface. This enables the GUI to associate a management port with a configuration file. The GUI can then
        // query the management interface for a process ID and other info, and can control the connection.
        [arguments addObjectsFromArray: [NSArray arrayWithObjects:
                                         @"--log", logPath,
                                         nil]];
   } else {
        [arguments addObjectsFromArray: [NSArray arrayWithObjects:
                                         @"--management-query-passwords",
                                         @"--management-hold",
                                         nil]];
    }
    
    if( ! skipScrSec ) {        // permissions must allow us to call the up and down scripts or scripts defined in config
		[arguments addObjectsFromArray: [NSArray arrayWithObjects: @"--script-security", @"2", nil]];
    }
    
    // Figure out which scripts to use (if any)
    // For backward compatibility, we only use the "new" (-tunnelblick-argument-capable) scripts if there are no old scripts
    // This would normally be the case, but if someone's custom build inserts replacements for the old scripts, we will use the replacements instead of the new scripts
    
    if(  useScripts != 0  ) {  // 'Set nameserver' specified, so use our standard scripts or Deploy/<config>.up.sh and Deploy/<config>.down.sh
        if (  cfgLocCode == 2  ) {
            NSString * deployScriptPath                 = [deployDirPath stringByAppendingPathComponent: [configFile stringByDeletingPathExtension]];
            NSString * deployUpscriptPath               = [deployScriptPath stringByAppendingPathExtension:@"up.sh"];
            NSString * deployDownscriptPath             = [deployScriptPath stringByAppendingPathExtension:@"down.sh"];
            NSString * deployUpscriptNoMonitorPath      = [deployScriptPath stringByAppendingPathExtension:@"nomonitor.up.sh"];
            NSString * deployDownscriptNoMonitorPath    = [deployScriptPath stringByAppendingPathExtension:@"nomonitor.down.sh"];
            NSString * deployNewUpscriptPath            = [deployScriptPath stringByAppendingPathExtension:@"up.tunnelblick.sh"];
            NSString * deployNewDownscriptPath          = [deployScriptPath stringByAppendingPathExtension:@"down.tunnelblick.sh"];
            
            if (  noMonitor  ) {
                if (  [gFileMgr fileExistsAtPath: deployUpscriptNoMonitorPath]  ) {
                    upscriptPath = deployUpscriptNoMonitorPath;
                } else if (  [gFileMgr fileExistsAtPath: deployUpscriptPath]  ) {
                    upscriptPath = deployUpscriptPath;
                } else if (  [gFileMgr fileExistsAtPath: upscriptNoMonitorPath]  ) {
                    upscriptPath = upscriptNoMonitorPath;
                } else if (  [gFileMgr fileExistsAtPath: deployNewUpscriptPath]  ) {
                    upscriptPath = deployNewUpscriptPath;
                } else {
                    upscriptPath = newUpscriptPath;
                }
                if (  [gFileMgr fileExistsAtPath: deployDownscriptNoMonitorPath]  ) {
                    downscriptPath = deployDownscriptNoMonitorPath;
                } else if (  [gFileMgr fileExistsAtPath: deployDownscriptPath]  ) {
                    downscriptPath = deployDownscriptPath;
                } else if (  [gFileMgr fileExistsAtPath: downscriptNoMonitorPath]  ) {
                    downscriptPath = downscriptNoMonitorPath;
                } else if (  [gFileMgr fileExistsAtPath: deployNewDownscriptPath]  ) {
                    downscriptPath = deployNewDownscriptPath;
                } else {
                    downscriptPath = newDownscriptPath;
                }
            } else {
                if (  [gFileMgr fileExistsAtPath: deployUpscriptPath]  ) {
                    upscriptPath = deployUpscriptPath;
                } else if (  [gFileMgr fileExistsAtPath: upscriptPath]  ) {
                    ;
                } else if (  [gFileMgr fileExistsAtPath: deployNewUpscriptPath]  ) {
                    upscriptPath = deployNewUpscriptPath;
                } else {
                    upscriptPath = newUpscriptPath;
                }
                if (  [gFileMgr fileExistsAtPath: deployDownscriptPath]  ) {
                    downscriptPath = deployDownscriptPath;
                } else if (  [gFileMgr fileExistsAtPath: downscriptPath]  ) {
                    ;
                } else if (  [gFileMgr fileExistsAtPath: deployNewDownscriptPath]  ) {
                    downscriptPath = deployNewDownscriptPath;
                } else {
                    downscriptPath = newDownscriptPath;
                }
            }
        } else {
            if (  noMonitor  ) {
                if (  [gFileMgr fileExistsAtPath: upscriptNoMonitorPath]  ) {
                    upscriptPath = upscriptNoMonitorPath;
                } else {
                    upscriptPath = newUpscriptPath;
                }
                if (  [gFileMgr fileExistsAtPath: downscriptNoMonitorPath]  ) {
                    downscriptPath = downscriptNoMonitorPath;
                } else {
                    downscriptPath = newDownscriptPath;
                }
            } else {
                if (  [gFileMgr fileExistsAtPath: upscriptPath]  ) {
                    ;
                } else {
                    upscriptPath = newUpscriptPath;
                }
                if (  [gFileMgr fileExistsAtPath: downscriptPath]  ) {
                    ;
                } else {
                    downscriptPath = newDownscriptPath;
                }
            }

        }
        
        // BUT MAY OVERRIDE THE ABOVE if there are scripts in the .tblk
        if (  [[configPath pathExtension] isEqualToString: @"tblk"]) {
            NSString * tblkUpscriptPath             = [cdFolderPath stringByAppendingPathComponent: @"up.sh"];
            NSString * tblkDownscriptPath           = [cdFolderPath stringByAppendingPathComponent: @"down.sh"];
            NSString * tblkUpscriptNoMonitorPath    = [cdFolderPath stringByAppendingPathComponent: @"nomonitor.up.sh"];
            NSString * tblkDownscriptNoMonitorPath  = [cdFolderPath stringByAppendingPathComponent: @"nomonitor.down.sh"];
            NSString * tblkNewUpscriptPath          = [cdFolderPath stringByAppendingPathComponent: @"up.tunnelblick.sh"];
            NSString * tblkNewDownscriptPath        = [cdFolderPath stringByAppendingPathComponent: @"down.tunnelblick.sh"];
            if (  noMonitor  ) {
                if (  [gFileMgr fileExistsAtPath: tblkUpscriptNoMonitorPath]  ) {
                    upscriptPath = tblkUpscriptNoMonitorPath;
                } else if (  [gFileMgr fileExistsAtPath: tblkNewUpscriptPath]  ) {
                    upscriptPath = tblkNewUpscriptPath;
                }
                if (  [gFileMgr fileExistsAtPath: tblkDownscriptNoMonitorPath]  ) {
                    downscriptPath = tblkDownscriptNoMonitorPath;
                } else if (  [gFileMgr fileExistsAtPath: tblkNewDownscriptPath]  ) {
                    downscriptPath = tblkNewDownscriptPath;
                }
            } else {
                if (  [gFileMgr fileExistsAtPath: tblkUpscriptPath]  ) {
                    upscriptPath = tblkUpscriptPath;
                } else if (  [gFileMgr fileExistsAtPath: tblkNewUpscriptPath]  ) {
                    upscriptPath = tblkNewUpscriptPath;
                }
                if (  [gFileMgr fileExistsAtPath: tblkDownscriptPath]  ) {
                    downscriptPath = tblkDownscriptPath;
                } else if (  [gFileMgr fileExistsAtPath: tblkNewDownscriptPath]  ) {
                    downscriptPath = tblkNewDownscriptPath;
                }
            }
        }
        
        // Process script options if scripts are "new" scripts
        NSMutableString * scriptOptions = [[NSMutableString alloc] initWithCapacity: 16];

        if (  ! noMonitor  ) {
            [scriptOptions appendString: @" -m"];
        }
        
        if (  (bitMask & RESTORE_ON_WINS_RESET) != 0  ) {
            [scriptOptions appendString: @" -w"];
        }
        if (  (bitMask & RESTORE_ON_DNS_RESET) != 0  ) {
            [scriptOptions appendString: @" -d"];
        }
        
        NSString * upscriptCommand   = escaped(upscriptPath);   // Must escape these since they are the first part of a command line
        NSString * downscriptCommand = escaped(downscriptPath);
        if (   scriptOptions
            && ( [scriptOptions length] != 0 )  ) {
            
            if (  [upscriptPath hasSuffix: @"tunnelblick.sh"]  ) {
                upscriptCommand   = [upscriptCommand   stringByAppendingString: scriptOptions];
            } else {
                fprintf(stderr, "Warning: up script %@ is not new version; not using '%@' options\n", upscriptPath, scriptOptions);
            }
            
            if (  [downscriptPath hasSuffix: @"tunnelblick.sh"]  ) {
                downscriptCommand = [downscriptCommand stringByAppendingString: scriptOptions];
            } else {
                fprintf(stderr, "Warning: down script %@ is not new version; not using '%@' options\n", downscriptPath, scriptOptions);
            }
        }
            
        if (   ([upscriptCommand length] > 199  )
            || ([downscriptCommand length] > 199  )) {
            fprintf(stderr, "Warning: Path for up and/or down script is very long. OpenVPN truncates the command line that starts each script to 255 characters, which may cause problems. Examine the OpenVPN log in Tunnelblick's \"Details...\" window carefully.");
        }
        [scriptOptions release];
        
        if (  useScripts == 2  ) {
            [arguments addObjectsFromArray: [NSArray arrayWithObjects:
                                             @"--up", upscriptCommand,
                                             @"--plugin", downRootPath, downscriptCommand,
                                             @"--up-restart",
                                             nil
                                             ]
             ];
        } else if (  useScripts == 1  ) {
            [arguments addObjectsFromArray: [NSArray arrayWithObjects:
                                             @"--up", upscriptCommand,
                                             @"--down", downscriptCommand,
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
    
    if (  tblkPath  ) {
        NSString * preConnectPath = [tblkPath stringByAppendingPathComponent: @"Contents/Resources/pre-connect.sh"];
        if (  [gFileMgr fileExistsAtPath: preConnectPath]  ) {
            if (  ! checkOwnerAndPermissions(preConnectPath, 0, 0, @"744")  ) {
                fprintf(stderr, "Error: %s has not been secured", [preConnectPath UTF8String]);
                [pool drain];
                exit(234);
            }
            int result = runAsRoot(preConnectPath, [NSArray array]);
            if (  result != 0 ) {
                fprintf(stderr, "Error: %s failed with return code %d", [preConnectPath UTF8String], result);
                [pool drain];
                exit(233);
            }
        }
    }
    
    if (  ! createPipeForConfigAtPath(configPath)  ) {
        fprintf(stderr, "Warning: Unable to create pipe for script output for %s\n", [configPath UTF8String]);
    }
    
    loadKexts(  bitMask & (OUR_TAP_KEXT | OUR_TUN_KEXT)  );
    
	NSTask* task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath:openvpnPath];
	[task setArguments:arguments];
    
    NSMutableString * cmdLine = [NSMutableString stringWithString: openvpnPath];
    int i;
    for (i=0; i<[arguments count]; i++) {
        [cmdLine appendFormat: @" %@", [arguments objectAtIndex: i]];
    }
    printf("%s", [cmdLine UTF8String]);
	
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

//**************************************************************************************************************************
//Starts OpenVPN with no arguments, to obtain version and usage info. May complain and exit if can't become root
void startOpenVPNWithNoArgs(void)
{
	NSString* openvpnPath = [execPath stringByAppendingPathComponent: @"openvpn"];
    runAsRoot(openvpnPath, [NSArray array]);
}

//**************************************************************************************************************************
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

//**************************************************************************************************************************
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

//**************************************************************************************************************************
// Sets up the OpenVPN log file (for "withoutGUI" operation), which encodes the configuration file path and port info into the filename
// Given the name of this file, this function deletes other versions of it (same configuration file path but encoding any port number),
// and creates the file with permissions so that anyone may read it. (OpenVPN truncates the file, so the ownership and permissions
// are preserved.)
NSString * createOpenVPNLog(NSString* configurationPath, int port)
{
    deleteLogFiles(configurationPath);
    
    NSString * logPath = constructOpenVPNLogPath(configurationPath, port);
    
    NSDictionary * logAttributes = [NSDictionary dictionaryWithObject: [NSNumber numberWithUnsignedLong: 0744] forKey: NSFilePosixPermissions];
    
    if (  ! [gFileMgr createFileAtPath: logPath contents: [NSData data] attributes: logAttributes]  ) {
        NSString * msg = [NSString stringWithFormat: @"Warning: Failed to create OpenVPN log file at %@ with attributes %@", logPath, logAttributes];
        fprintf(stderr, [msg UTF8String]);
    }
    
    return logPath;
}

/// Returns a path for an OpenVPN log file.
// It is composed of a prefix, the configuration path with "-" replaced by "--" and "/" replaced by "-S" , and extensions of the port number and "log".
NSString * constructOpenVPNLogPath(NSString * configurationPath, int port)
{
    NSMutableString * logPath = [configurationPath mutableCopy];
    [logPath replaceOccurrencesOfString: @"-" withString: @"--" options: 0 range: NSMakeRange(0, [logPath length])];
    [logPath replaceOccurrencesOfString: @"/" withString: @"-S" options: 0 range: NSMakeRange(0, [logPath length])];
    NSString * returnVal = [NSString stringWithFormat: @"/tmp/tunnelblick%@.%d.log", logPath, port];
    [logPath release];
    return returnVal;
}

//**************************************************************************************************************************
// Deletes OpenVPN log files associated with a specified configuration file
BOOL deleteLogFiles(NSString * configurationPath)
{
    BOOL errHappened = FALSE;
    
    NSString * logPath = constructOpenVPNLogPath(configurationPath, 0); // Port # doesn't matter because we strip it off
    
    NSString * logPathPrefix = [[logPath stringByDeletingPathExtension] stringByDeletingPathExtension];     // Remove .<port #>.log
    
    NSString * filename;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: @"/tmp"];
    while (  filename = [dirEnum nextObject]  ) {
        [dirEnum skipDescendents];
        NSString * oldFullPath = [@"/tmp" stringByAppendingPathComponent: filename];
        if (  [oldFullPath hasPrefix: logPathPrefix]  ) {
            if (  [[filename pathExtension] isEqualToString: @"log"]) {
                if (  [gFileMgr removeFileAtPath: oldFullPath handler: nil]  ) {
                    NSString * msg = [NSString stringWithFormat: @"Deleted OpenVPN log file %@\n", oldFullPath];
                    fprintf(stderr, [msg UTF8String]);
                } else {
                    NSString * msg = [NSString stringWithFormat: @"Error occurred trying to delete OpenVPN log file %@\n", oldFullPath];
                    fprintf(stderr, [msg UTF8String]);
                    errHappened = TRUE;
                }

            }
        }
    }

    return errHappened;
}

//**************************************************************************************************************************
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

//**************************************************************************************************************************
//Tries to load kexts. May complain and exit if can't become root or if can't load kexts
void loadKexts(unsigned int bitMask)
{
    if (  bitMask == 0  ) {
        bitMask = OUR_TAP_KEXT | OUR_TUN_KEXT;
    }
    
    NSMutableArray*	arguments = [NSMutableArray arrayWithCapacity: 2];
    
    if (  OUR_TAP_KEXT & bitMask  ) {
        [arguments addObject: [execPath stringByAppendingPathComponent: @"tap.kext"]];
    }
    if (  OUR_TUN_KEXT & bitMask  ) {
        [arguments addObject: [execPath stringByAppendingPathComponent: @"tun.kext"]];
    }
    
	NSTask * task = [[[NSTask alloc] init] autorelease];

    [task setLaunchPath:@"/sbin/kextload"];
    
    [task setArguments:arguments];
    becomeRoot();

    int status;
    int i;
    for (i=0; i < 5; i++) {
        [task launch];
        [task waitUntilExit];
        
        status = [task terminationStatus];
        if (  status == 0  ) {
            break;
        }
        sleep(1);
    }
    if (  status != 0  ) {
        fprintf(stderr, "Error: Unable to load net.tunnelblick.tun and/or net.tunnelblick.tap kexts in 5 tries. Status = %d\n", status);
        [pool drain];
        exit(247);
    }
}

//**************************************************************************************************************************
// Tries to UNload kexts. Will complain and exit if can't become root
// We ignore errors because this is a non-critical function, and the unloading fails if a kext is in use
void unloadKexts(unsigned int bitMask)
{
    if (  bitMask == 0  ) {
        bitMask = OUR_TAP_KEXT | OUR_TUN_KEXT;
    }
    
    NSMutableArray*	arguments = [NSMutableArray arrayWithCapacity: 10];
    
    [arguments addObject: @"-q"];
    
    if (  OUR_TAP_KEXT & bitMask  ) {
        [arguments addObjectsFromArray: [NSArray arrayWithObjects: @"-b", @"net.tunnelblick.tap", nil]];
    }
    if (  OUR_TUN_KEXT & bitMask  ) {
        [arguments addObjectsFromArray: [NSArray arrayWithObjects: @"-b", @"net.tunnelblick.tun", nil]];
    }
    if (  FOO_TAP_KEXT & bitMask  ) {
        [arguments addObjectsFromArray: [NSArray arrayWithObjects: @"-b", @"foo.tap", nil]];
    }
    if (  FOO_TUN_KEXT & bitMask  ) {
        [arguments addObjectsFromArray: [NSArray arrayWithObjects: @"-b", @"foo.tun", nil]];
    }
    
    runAsRoot(@"/sbin/kextunload", arguments);
}

//**************************************************************************************************************************
// Returns as root, having setuid(0) if necessary; complains and exits if can't become root
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

//**************************************************************************************************************************
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

//**************************************************************************************************************************
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

//**************************************************************************************************************************
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

//**************************************************************************************************************************
//Returns NO if configuration file is secure, otherwise complains and exits
BOOL configNeedsRepair(void)
{
	NSDictionary*	fileAttributes	= [gFileMgr fileAttributesAtPath:configPath traverseLink:YES];
    
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

//**************************************************************************************************************************
// Returns an escaped version of a string so it can be put after an --up or --down option in the OpenVPN command line
NSString *escaped(NSString *string)
{
    if (  [string rangeOfString: @" "].length == 0  ) {
        return [[string copy] autorelease];
    } else {
        return [NSString stringWithFormat:@"\"%@\"", string];
    }
}

// Returns the path of the configuration file within a .tblk, or nil if there is no such configuration file
NSString * configPathFromTblkPath(NSString * path)
{
    NSString * cfgPath = [path stringByAppendingPathComponent:@"Contents/Resources/config.ovpn"];
    BOOL isDir;
    
    if (   [gFileMgr fileExistsAtPath: cfgPath isDirectory: &isDir]
        && (! isDir)  ) {
        return cfgPath;
    }

    return nil;
}

//**************************************************************************************************************************
// Returns NO if path or any component of path is invisible (compenent starts with a '.') 
BOOL itemIsVisible(NSString * path)
{
    if (  [path hasPrefix: @"."]  ) {
        return NO;
    }
    NSRange rng = [path rangeOfString:@"/."];
    if (  rng.length != 0) {
        return NO;
    }
    return YES;
}

//**************************************************************************************************************************
// Returns a free port
unsigned int getFreePort(void)
{
    unsigned int resultPort = 1336; // start port	
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    int result = 0;
    
    do {		
        struct sockaddr_in address;
        int len = sizeof(struct sockaddr_in);
        resultPort++;
        
        address.sin_len = len;
        address.sin_family = AF_INET;
        address.sin_port = htons(resultPort);
        address.sin_addr.s_addr = htonl(0x7f000001); // 127.0.0.1, localhost
        
        memset(address.sin_zero,0,sizeof(address.sin_zero));
        
        result = bind(fd, (struct sockaddr *)&address,sizeof(address));
        
    } while (result!=0);
    
    close(fd);
    
    return resultPort;
}

BOOL createPipeForConfigAtPath(NSString * inPath)
{
    NSMutableString * realCfgPathWithDashes;
    if (  [[inPath pathExtension] isEqualToString: @"tblk"]  ) {
        realCfgPathWithDashes = [[configPathFromTblkPath(inPath) mutableCopy] autorelease];
    } else {
        realCfgPathWithDashes = [[inPath mutableCopy] autorelease];
    }
    [realCfgPathWithDashes replaceOccurrencesOfString: @"/" withString: @"-" options: 0 range: NSMakeRange(0, [realCfgPathWithDashes length])];
    if (  ! realCfgPathWithDashes  ) {
        realCfgPathWithDashes = @"";
    }
    NSString * path = [NSString stringWithFormat: @"/tmp/tunnelblick%@.logpipe", realCfgPathWithDashes];
    
    [gFileMgr removeFileAtPath: path handler: nil];
    
    const char * cPath = [path UTF8String];
    
    // Create the pipe
    if (    ( mkfifo(cPath, 0666) == -1 ) && ( errno != EEXIST )    ) {
        return NO;
    }
    
    if (  chmod(cPath, 0666)  ) {
        return NO;
    }
    return YES;
}

// Runs a program after becoming root
// Returns program's termination status
int runAsRoot(NSString * thePath, NSArray * theArguments)
{
	NSTask* task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath:thePath];
	[task setArguments:theArguments];
	
	becomeRoot();
	[task launch];
	[task waitUntilExit];
    
    return [task terminationStatus];
}

// Returns YES if file doesn't exist, or has the specified ownership and permissions
BOOL checkOwnerAndPermissions(NSString * fPath, uid_t uid, gid_t gid, NSString * permsShouldHave)
{
    if (  ! [gFileMgr fileExistsAtPath: fPath]  ) {
        return YES;
    }
    
    NSDictionary *fileAttributes = [gFileMgr fileAttributesAtPath:fPath traverseLink:YES];
    unsigned long perms = [fileAttributes filePosixPermissions];
    NSString *octalString = [NSString stringWithFormat:@"%o",perms];
    NSNumber *fileOwner = [fileAttributes fileOwnerAccountID];
    NSNumber *fileGroup = [fileAttributes fileGroupOwnerAccountID];
    
    if (   [octalString isEqualToString: permsShouldHave]
        && [fileOwner isEqualToNumber:[NSNumber numberWithInt:(int) uid]]
        && [fileGroup isEqualToNumber:[NSNumber numberWithInt:(int) gid]]) {
        return YES;
    }
    
    return NO;
}
