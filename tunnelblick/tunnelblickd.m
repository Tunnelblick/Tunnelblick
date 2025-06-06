/*
 * Copyright 2014, 2015, 2016, 2018, 2019 by Jonathan K. Bullard. All rights reserved.
 *
 *  This file is part of Tunnelblick.
 *
 *  Tunnelblick is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  Tunnelblick is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *  or see http://www.gnu.org/licenses/.
 
 
 NOTE: THIS PROGRAM MUST BE RUN AS ROOT. IT IS AN macOS LAUNCHDAEMON
 
 This daemon is used by the Tunnelblick GUI to start and stop OpenVPN instances and perform other activities that require root access.
 
 It is a modified version of SampleD.c, a sample program supplied by Apple.

 It is invoked with no arguments.

 When tunnelblickd detects that it is on the first run since boot:
    1. it checks for the presence of a file, /Library/Application Support/Tunnelblick/restore-secondary.txt.
       if present, tunnelblickd will enable each service listed in a separate line in the file and then delete the file.
    2. tunnelblickd checks for the presence of a file, /Library/Application Support/Tunnelblick/restore-ipv6.txt.
       if present, tunnelblickd will restore IPv6 to "Automatic" for each service listed in a separate line in the file and then delete the file.
    3. It deletes the contents of the folder at L_AS_T_EXPECT_DISCONNECT_FOLDER_PATH.
    4. It deletes /Library/Application Support/Tunnelblick/shutting-down-computer.txt.
 
 */

#import <arpa/inet.h>
#import <asl.h>
#import <errno.h>
#import <fcntl.h>
#import <launch.h>
#import <libgen.h>
#import <netdb.h>
#import <netinet/in.h>
#import <pwd.h>
#import <stdbool.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <syslog.h>
#import <sys/event.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <sys/types.h>
#import <sys/ucred.h>
#import <sys/un.h>

#import <unistd.h>

#import "defines.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static BOOL sigtermReceived = FALSE;

BOOL tunnelblickNotInApplications(aslclient __unused asl,
                                  aslmsg    __unused log_msg) {

    // Returns TRUE if /Applications/Tunnelblick.app does not (or did not) exist for two seconds.

    static BOOL tunnelblickWasNotInApplications = FALSE;

    if (  tunnelblickWasNotInApplications  ) {
        return TRUE;
    }

    // Make sure it doesn't exist for a while, in case it is being replaced
    uint i;
    for (  i=0; i<20; i++  ) {
        if (  [NSFileManager.defaultManager fileExistsAtPath: APPLICATIONS_TB_APP]  ) {
            return FALSE;
        }
        usleep(ONE_TENTH_OF_A_SECOND_IN_MICROSECONDS);
    }

    tunnelblickWasNotInApplications = TRUE;

    return TRUE;
}

static BOOL sanityChecks(aslclient  asl,
                         aslmsg     log_msg) {

    // Make sure we are root:wheel
    if (   (getuid()  != 0)
        || (getgid()  != 0)
        || (geteuid() != 0)
        || (getegid() != 0)
        ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Not root:wheel; our uid = %lu; our euid = %lu; our gid = %lu; our egid = %lu",
                (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
        return FALSE;
    }

#ifndef TBDebug
    // Make sure we are in L_AS_T
    NSString * ourPath = nil;
    NSString * bundlePath = NSBundle.mainBundle.bundlePath;
    if (  [bundlePath.lastPathComponent isEqualToString: @"Resources"]  ) {
        ourPath = [bundlePath stringByAppendingPathComponent: @"tunnelblickd"];
    } else if (  [bundlePath.pathExtension isEqualToString: @"app"]  ) {
        ourPath = [[[bundlePath
                     stringByAppendingPathComponent: @"Contents"]
                    stringByAppendingPathComponent: @"Resources"]
                   stringByAppendingPathComponent: @"tunnelblickd"];
    } else {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Not as expected: bundlePath = %s", bundlePath.UTF8String);
        return FALSE;
    }

    if (  ! [@"/Library/Application Support/Tunnelblick/Tunnelblick.app/Contents/Resources/tunnelblickd" isEqualToString: ourPath]  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "tunnelblickd is not located where expected: %s", ourPath.UTF8String);
        return FALSE;
    }

    if (  tunnelblickNotInApplications(asl, log_msg)  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Tunnelblick is not in /Applications. Removing tunnelblickd .plist");
        [NSFileManager.defaultManager removeItemAtPath: @"/Library/LaunchDaemons/net.tunnelblick.tunnelblick.tunnelblickd.plist" error: nil];
        return FALSE;
    }

    NSString * tunnelblickdInApplicationsPath = @"/Applications/Tunnelblick.app/Contents/Resources/tunnelblickd";
    if (  ! [NSFileManager.defaultManager contentsEqualAtPath: ourPath andPath: tunnelblickdInApplicationsPath]  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "tunnelblickd copies are not identical");
        return FALSE;
    }
#endif

    return TRUE;
}

static void signal_handler(int signalNumber) {
	
	if (  signalNumber == SIGTERM  ) {
		sigtermReceived = TRUE;
	}
}

static NSDictionary * getSafeEnvironment(NSString * userName,
								  NSString * userHome) {
    
    // Create our own environment to guard against Shell Shock (BashDoor) and similar vulnerabilities in bash
    // (Even if bash is not being launched directly, whatever is being launched could invoke bash;
	//  for example, tunnelblick-helper launches openvpn which can invoke bash for scripts)
	
    NSDictionary * env = [NSDictionary dictionaryWithObjectsAndKeys:
                          STANDARD_PATH,          @"PATH",
                          NSTemporaryDirectory(), @"TMPDIR",
                          userName,               @"USER",
                          userName,               @"LOGNAME",
                          userHome,               @"HOME",
                          TOOL_PATH_FOR_BASH,     @"SHELL",
                          @"unix2003",            @"COMMAND_MODE",
                          nil];
    
    return env;
}

static void becomeTheClient(uid_t      client_euid,
                            gid_t      client_egid,
                            aslclient  asl,
                            aslmsg     log_msg) {

    // Pretend we are the client while running tunnelblick-helper
    if (  getegid() == client_egid  ) {
        asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "becomeTheClient: setegid(%lu) unnecessary: uid = %lu; euid = %lu; gid = %lu; egid = %lu",
                (unsigned long)client_egid, (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
    } else if (  setegid(client_egid)  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "becomeTheClient: setegid(%lu) failed; uid = %lu; euid = %lu; gid = %lu; egid = %lu; error = %m",
                (unsigned long)client_egid, (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
    }
    if (  geteuid() == client_euid  ) {
        asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "becomeTheClient: seteuid(%lu) unnecessary; uid = %lu; euid = %lu; gid = %lu; egid = %lu",
                (unsigned long)client_euid, (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
        ;
    } else if (  seteuid(client_euid)  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "becomeTheClient: seteuid(%lu) failed; uid = %lu; euid = %lu; gid = %lu; egid = %lu; error = %m",
                (unsigned long)client_euid, (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
    }
}

static void becomeRoot(aslclient  asl,
                       aslmsg     log_msg) {

    if (   geteuid() == 0  ) {
        asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "becomeRoot: seteuid(0) unnecessary; uid = %lu; euid = %lu; gid = %lu; egid = %lu",
                (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
    } else if (  seteuid(0)  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "becomeRoot: seteuid(0) failed; uid = %lu; euid = %lu; gid = %lu; egid = %lu; error = %m",
                (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
    }
    if (   getegid() == 0  ) {
        asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "becomeRoot: setegid(0) unnecessary; uid = %lu; euid = %lu; gid = %lu; egid = %lu",
                (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
    } else if (  setegid(0)  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "becomeRoot: setegid(0) failed; uid = %lu; euid = %lu; gid = %lu; egid = %lu; error = %m",
                (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
    }
}

static NSFileHandle *  getStdOutOrStdErrFileHandle(NSString * path,
                                                   aslclient  asl,
                                                   aslmsg     log_msg) {

    NSFileHandle * outFile = nil;

    if (  [[NSFileManager defaultManager] fileExistsAtPath: path]  ) {
        if (  0 != unlink([path fileSystemRepresentation])  ) {
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not unlink %s; errno = %ld; error was '%s'", [path UTF8String], (long)errno, strerror(errno));
        }
    }

    if (  ! [[NSFileManager defaultManager] createFileAtPath: path contents: [NSData data] attributes: nil]  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not create %s", [path UTF8String]);
    } else {
        outFile = [NSFileHandle fileHandleForWritingAtPath: path];
        if (  ! outFile  ) {
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not get file handle for %s", [path UTF8String]);
        }
    }

    return outFile;
}

static NSString * getContentsThenDeleteFileAtPath(NSString * path,
                                           aslclient  asl,
                                           aslmsg     log_msg) {

    NSString * string = [NSString stringWithContentsOfFile: path encoding: NSUTF8StringEncoding error: nil];
    if (  string == nil  ) {
        string = [NSString stringWithFormat: @"Could not interpret as UTF-8 %@", path];
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not interpret as UTF-8: %s", [path UTF8String]);
    }

    if (  0 != unlink([path fileSystemRepresentation])  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not unlink %s; errno = %ld; error was '%s'", [path UTF8String], (long)errno, strerror(errno));
    }

    return string;
}

static OSStatus runTool(uid_t      client_euid,
                        gid_t      client_egid,
                        NSString * userName,
                        NSString * userHome,
                        NSString * launchPath,
                        NSArray  * arguments,
                        NSString * * stdOutStringPtr,
                        NSString * * stdErrStringPtr,
                        aslclient  asl,
                        aslmsg     log_msg) {

	// Runs a command or script, returning the execution status of the command, stdout, and stderr
	
    NSFileHandle * outFile = getStdOutOrStdErrFileHandle(TUNNELBLICKD_STDOUT_PATH, asl, log_msg);
    NSFileHandle * errFile = getStdOutOrStdErrFileHandle(TUNNELBLICKD_STDERR_PATH, asl, log_msg);

    NSTask * task = [[[NSTask alloc] init] autorelease];
    
    [task setLaunchPath:           launchPath];
    [task setArguments:            arguments];
    [task setCurrentDirectoryPath: @"/private/tmp"];
    [task setEnvironment:          getSafeEnvironment(userName, userHome)];
    [task setStandardOutput:       outFile];
    [task setStandardError:        errFile];

    if (   (client_euid != 0)
        || (client_egid != 0)  ) {
        becomeTheClient(client_euid, client_egid, asl, log_msg);
    }
        [task launch];

        [task waitUntilExit];

        OSStatus status = [task terminationStatus];

    if (   (client_euid != 0)
        || (client_egid != 0)  ) {
        becomeRoot(asl, log_msg);
    }

    [outFile closeFile];
    [errFile closeFile];
    
    NSString * stdOutString = getContentsThenDeleteFileAtPath(TUNNELBLICKD_STDOUT_PATH, asl, log_msg);
    NSString * stdErrString = getContentsThenDeleteFileAtPath(TUNNELBLICKD_STDERR_PATH, asl, log_msg);

    NSString * message = nil;
    
    if (  stdOutStringPtr  ) {
        *stdOutStringPtr = [[stdOutString retain] autorelease];
    } else if (   (status != EXIT_SUCCESS)
               && (0 != [stdOutString length])  )  {
        message = [NSString stringWithFormat: @"stdout = '%@'\n", stdOutString];
    }
    
    if (  stdErrStringPtr  ) {
        *stdErrStringPtr = [[stdErrString retain] autorelease];
    } else if (   (status != EXIT_SUCCESS)
               && (0 != [stdErrString length])  )  {
        message = [NSString stringWithFormat: @"%@stderr = '%@'", (message ? message : @""), stdErrString];
    }
    
    if (  message  ) {
        asl_log(asl, log_msg, ASL_LEVEL_WARNING, "'%s' returned status = %ld\n%s", [[launchPath lastPathComponent] UTF8String], (long)status, [message UTF8String]);
    }
    
    return status;
}

static void updateApproximateLastBootInfo(BOOL	            infoFileExists,
								   NSTimeInterval   approximateMostRecentReboot,
								   NSString       * approximateLastRebootInfoPath,
								   aslclient        asl,
								   aslmsg           log_msg) {

	if (  infoFileExists  ) {
		NSError * error;
		if (  ! [[NSFileManager defaultManager] removeItemAtPath: approximateLastRebootInfoPath error: &error]  ) {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not delete %s; error = %s",
					[approximateLastRebootInfoPath UTF8String], [[error description] UTF8String]);
		} else {
			asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Deleted %s", [approximateLastRebootInfoPath UTF8String]);
		}
	}

	const char * approximateMostRecentRebootStringC = [[NSString stringWithFormat: @"%f", approximateMostRecentReboot] UTF8String];
	if (  !  [[NSFileManager defaultManager] createFileAtPath: approximateLastRebootInfoPath
													 contents: [NSData dataWithBytes: approximateMostRecentRebootStringC
																			  length: strlen(approximateMostRecentRebootStringC)]
												   attributes: nil]  ) {
		asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not create %s", [approximateLastRebootInfoPath UTF8String]);
	} else {
		asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Wrote %s", [approximateLastRebootInfoPath UTF8String]);
	}
}

static BOOL isFirstRunAfterBoot(aslclient  asl,
						 aslmsg     log_msg) {

	// Consider this to be the first run after boot if
	//
	//	(A) L_AS_T/last-reboot-info.txt does not exist;
	//  or
	//	(B) The time-since-1970 in that file is approximately the same as the time-since-1970 of the most recent boot.

	// This is only an __approximation__ of the time-since-1970 of the reboot
	// because [NSDate date] and systemUptime are not accessed simultaneously
	NSTimeInterval approximateMostRecentReboot = [[[NSDate date]
												   dateByAddingTimeInterval: ( - [[NSProcessInfo processInfo] systemUptime] )]
												  timeIntervalSince1970];

	BOOL firstRunAfterBoot = FALSE;
	BOOL infoFileExists;
	NSError * error;
	NSString * approximateLastRebootInfoPath = [L_AS_T stringByAppendingPathComponent: @"last-reboot-info.txt"];

	if (  (infoFileExists = [[NSFileManager defaultManager] fileExistsAtPath: approximateLastRebootInfoPath])  ) {
		NSTimeInterval approximateLastKnownReboot = (NSTimeInterval)[[NSString stringWithContentsOfFile: approximateLastRebootInfoPath
																					encoding: NSUTF8StringEncoding
																					   error: &error] doubleValue];

		NSTimeInterval timeDifference = fabs( approximateLastKnownReboot - approximateMostRecentReboot );

		asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "approximateLastKnownReboot = %f; approximateMostRecentReboot = %f; difference = %f",
				approximateLastKnownReboot, approximateMostRecentReboot, timeDifference);

		// Assuming the time between [NSDate date] and systemUpTime is less than five seconds
		//      and the time between reboots is more than five seconds.
		if (  timeDifference < 5.0 ) {
			asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "This reboot time is approximately the same as the last reboot time; not first run after rebooting");
		} else {
			asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "This reboot time is very different from the last reboot time; first run after rebooting");
			firstRunAfterBoot = TRUE;
		}
	} else {
		asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "last-reboot-info.txt doesn't exist; this is the first run");
		firstRunAfterBoot = TRUE; // Because file doesn't exist
	}

	if (  firstRunAfterBoot  ) {
		updateApproximateLastBootInfo(infoFileExists, approximateMostRecentReboot, approximateLastRebootInfoPath, asl, log_msg);
	}

	return firstRunAfterBoot;
}

static void restoreSecondary(aslclient  asl,
                       aslmsg     log_msg) {

    NSString * path = @"/Library/Application Support/Tunnelblick/restore-secondary.txt";

    if (  ! [[NSFileManager defaultManager] fileExistsAtPath: path]  ) {
        asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "restore-secondary.txt does not exist");
        return;
    }

    NSError * error;
    NSString * servicesString = [NSString stringWithContentsOfFile: path
                                                          encoding: NSUTF8StringEncoding
                                                             error: &error];

    if (  [[NSFileManager defaultManager] removeItemAtPath: path error: &error]) {
        asl_log(asl, log_msg, ASL_LEVEL_INFO, "Deleted %s", [path UTF8String]);
    } else {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not delete %s; error was %s", [path UTF8String], [[error description] UTF8String]);
        // Fall through to continue even though the error happened to report that file can't be read or to restore the secondary services if it can be read
    }

    if (  ! servicesString  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not read %s; error was %s", [path UTF8String], [[error description] UTF8String]);
        return;
    }

    NSArray * services = [servicesString componentsSeparatedByString: @"\n"];
    if (  services  ) {
        NSString * service;
        NSEnumerator * e = [services objectEnumerator];
        BOOL processed_a_service = FALSE;
        while (  (service = [e nextObject])  ) {
            if (  [service length] != 0  ) {
                processed_a_service = TRUE;
                NSArray * arguments = @[@"-setnetworkserviceenabled", service, @"on"];
                OSStatus status = runTool(0, 0, @"root", @"wheel", TOOL_PATH_FOR_NETWORKSETUP, arguments, nil, nil, asl, log_msg);
                if (  status == 0  ) {
                    asl_log(asl, log_msg, ASL_LEVEL_INFO, "Re-enabled %s", [service UTF8String]);
                } else {
                    asl_log(asl, log_msg, ASL_LEVEL_ERR, "Failed with status %d while trying to re-enable %s", status, [service UTF8String]);
                }
            }
        }
        if (  ! processed_a_service  ) {
            asl_log(asl, log_msg, ASL_LEVEL_WARNING, "%s exists but does not include any service names. Contents = '%s'",
                    [path UTF8String], [servicesString UTF8String]);
        }
    } else {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not parse into separate lines: '%s'", [servicesString UTF8String]);
    }
}

static void restoreIpv6(aslclient  asl,
				 aslmsg     log_msg) {

	NSString * path = @"/Library/Application Support/Tunnelblick/restore-ipv6.txt";

	if (  ! [[NSFileManager defaultManager] fileExistsAtPath: path]  ) {
		asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "restore-ipv6.txt does not exist");
		return;
	}

	NSError * error;
	NSString * servicesString = [NSString stringWithContentsOfFile: path
														  encoding: NSUTF8StringEncoding
															 error: &error];

	if (  [[NSFileManager defaultManager] removeItemAtPath: path error: &error]) {
		asl_log(asl, log_msg, ASL_LEVEL_INFO, "Deleted %s", [path UTF8String]);
	} else {
		asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not delete %s; error was %s", [path UTF8String], [[error description] UTF8String]);
		// Fall through to continue even though the error happened to report that file can't be read or to restore IPv6 if it can be read
	}

	if (  ! servicesString  ) {
		asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not read %s; error was %s", [path UTF8String], [[error description] UTF8String]);
		return;
	}

	NSArray * services = [servicesString componentsSeparatedByString: @"\n"];
	if (  services  ) {
		NSString * service;
		NSEnumerator * e = [services objectEnumerator];
		BOOL processed_a_service = FALSE;
		while (  (service = [e nextObject])  ) {
			if (  [service length] != 0  ) {
				processed_a_service = TRUE;
				NSArray * arguments = [NSArray arrayWithObjects: @"-setv6automatic", service, nil];
				OSStatus status = runTool(0, 0, @"root", @"wheel", TOOL_PATH_FOR_NETWORKSETUP, arguments, nil, nil, asl, log_msg);
				if (  status == 0  ) {
					asl_log(asl, log_msg, ASL_LEVEL_INFO, "Restored IPv6 to 'Automatic' for %s", [service UTF8String]);
				} else {
					asl_log(asl, log_msg, ASL_LEVEL_ERR, "Failed with status %d while trying to restore IPv6 to 'Automatic' for %s", status, [service UTF8String]);
				}
			}
		}
		if (  ! processed_a_service  ) {
			asl_log(asl, log_msg, ASL_LEVEL_WARNING, "%s exists but does not include any service names. Contents = '%s'",
					[path UTF8String], [servicesString UTF8String]);
		}
	} else {
		asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not parse into separate lines: '%s'", [servicesString UTF8String]);
	}
}

static void clearExpectedDisconnectFolder(aslclient  asl,
								   aslmsg     log_msg) {

	NSString * file;
	NSDirectoryEnumerator * dirEnum = [[NSFileManager defaultManager] enumeratorAtPath: L_AS_T_EXPECT_DISCONNECT_FOLDER_PATH];
	BOOL haveDeletedSomething = FALSE;
	while (  (file = [dirEnum nextObject])  ) {
		[dirEnum skipDescendants];
		NSString * fullPath = [L_AS_T_EXPECT_DISCONNECT_FOLDER_PATH stringByAppendingPathComponent: file];
		NSError * error;
		if (  [[NSFileManager defaultManager] removeItemAtPath: fullPath error: &error]  ) {
			haveDeletedSomething = TRUE;
		} else {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "Error while trying to delete %s: %s", [fullPath UTF8String], [[error description] UTF8String]);
		}
	}

	if (  haveDeletedSomething  ) {
		asl_log(asl, log_msg, ASL_LEVEL_INFO, "Cleared contents of %s", [L_AS_T_EXPECT_DISCONNECT_FOLDER_PATH UTF8String]);
	} else {
		asl_log(asl, log_msg, ASL_LEVEL_INFO, "Nothing to clear in %s", [L_AS_T_EXPECT_DISCONNECT_FOLDER_PATH UTF8String]);
	}
}

static void removeShutdownFlagFile(aslclient  asl,
							 aslmsg     log_msg) {

	NSError * error;
	NSString * path = @"/Library/Application Support/Tunnelblick/shutting-down-computer.txt";

	if (  [[NSFileManager defaultManager] fileExistsAtPath: path]  ) {
		if (  [[NSFileManager defaultManager] removeItemAtPath: path error: &error]  ) {
			asl_log(asl, log_msg, ASL_LEVEL_INFO, "Deleted %s", [path UTF8String]);
		} else {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "Error removing %s: %s", [path UTF8String], [[error description] UTF8String]);
		}
	}
}

int main(void) {

	NSAutoreleasePool * pool = [NSAutoreleasePool new];
	
    unsigned int event_count = 0;
	
	struct sigaction action;
    
    struct sockaddr_storage ss;
	
    socklen_t       slen          = sizeof(ss);
	aslclient       asl           = NULL;
	aslmsg          log_msg       = NULL;
    int             retval        = EXIT_FAILURE;
	struct timespec timeout       = {  30, 0  };	// TimeOut value (macOS supplies a 30 second value if there is no TimeOut entry in the launchd .plist)
    struct kevent   kev_init;
    struct kevent   kev_listener;
    launch_data_t   sockets_dict,
					checkin_response,
					checkin_request,
					listening_fd_array;
    size_t          i;
    int             kq;
    
	static const char * command_header = TUNNELBLICKD_OPENVPNSTART_HEADER_C;
	
    // Create a new ASL log
    asl = asl_open("tunnelblickd", "Daemon", ASL_OPT_STDERR);
	if (  asl == NULL  ) {
        goto done;
	}
    log_msg = asl_new(ASL_TYPE_MSG);
	if (  log_msg == NULL  ) {
        goto done;;
	}
	if (  asl_set(log_msg, ASL_KEY_SENDER, "tunnelblickd") != 0  ) {
		goto done;
	}
		
    asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Started tunnelblickd");

    if (  ! sanityChecks(asl, log_msg)  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Terminating tunnelblickd because sanityChecks() failed");
        goto done;
    }

	if (  isFirstRunAfterBoot(asl, log_msg)  ) {

		// This is the first time tunnelblickd has run since a reboot:
		//
        //    (A) Re-enable each service listed in /L_AS_T/restore-secondary.txt, then delete the file.
        //
		// 	  (B) Restore IPv6 to "Automatic" for each service listed in /L_AS_T/restore-ipv6.txt, then delete the file.
		//
		//	  (C) Delete everything in /Library/Application Support/Tunnelblick/expect-disconnect/
		//
		//	  (D) Delete /Library/Application Support/Tunnelblick/shutting-down-computer.txt if it exists

        restoreSecondary(asl, log_msg);

		restoreIpv6(asl, log_msg);

		clearExpectedDisconnectFolder(asl, log_msg);

		removeShutdownFlagFile(asl, log_msg);

	} else {
		asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "tunnelblickd invoked but not first run after reboot");
	}

	// Create a new kernel event queue that we'll use for our notification.
	// Note the use of the '%m' formatting character.
	// ASL will replace %m with the error string associated with the current value of errno.
	if (  -1 == (kq = kqueue())  ) {
		asl_log(asl, log_msg, ASL_LEVEL_ERR, "kqueue(): %m");
		goto done;
	}

    // Register ourselves with launchd.
    if (  NULL == (checkin_request = launch_data_new_string(LAUNCH_KEY_CHECKIN))  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "launch_data_new_string(\"" LAUNCH_KEY_CHECKIN "\") Unable to create string.");
        goto done;
    }
    
    if (  (checkin_response = launch_msg(checkin_request)) == NULL  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "launch_msg(\"" LAUNCH_KEY_CHECKIN "\") IPC failure: %m");
        goto done;
    }
    
    if (  LAUNCH_DATA_ERRNO == launch_data_get_type(checkin_response)  ) {
        errno = launch_data_get_errno(checkin_response);
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Check-in failed: %m");
        goto done;
    }
	
	// If the .plist and macOS did not specify a TimeOut, default to 30 seconds
	launch_data_t timeoutValue = launch_data_dict_lookup(checkin_response, LAUNCH_JOBKEY_TIMEOUT);
	if (  timeoutValue != NULL) {
		timeout.tv_sec = launch_data_get_integer(timeoutValue);
	}
    
    launch_data_t the_label = launch_data_dict_lookup(checkin_response, LAUNCH_JOBKEY_LABEL);
    if (  NULL == the_label  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "No label found");
        goto done;
    }
    
    // Retrieve the dictionary of Socket entries in the config file
    sockets_dict = launch_data_dict_lookup(checkin_response, LAUNCH_JOBKEY_SOCKETS);
    if (  NULL == sockets_dict  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "No sockets found on which to answer requests!");
        goto done;
    }
    
    if (  launch_data_dict_get_count(sockets_dict) > 1) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Too many sockets! This daemon supports only one socket.");
		goto done;
    }
    
    // Get the dictionary value from the key "MyListenerSocket", as defined in the .plist file.
    listening_fd_array = launch_data_dict_lookup(sockets_dict, "Listener");
    if (  NULL == listening_fd_array  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "No socket named 'Listener' found in launchd .plist to answer requests on!");
        goto done;
    }
    
    // Initialize a new kernel event.  This will trigger when a connection occurs on our listener socket.
    for (  i = 0; i < launch_data_array_get_count(listening_fd_array); i++  ) {
		launch_data_t this_listening_fd = launch_data_array_get_index(listening_fd_array, i);
        EV_SET(&kev_init, launch_data_get_fd(this_listening_fd), EVFILT_READ, EV_ADD, 0, 0, NULL);
        if (  -1 == kevent(kq, &kev_init, 1, NULL, 0, NULL)  ) {
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "Error from kevent(): %m");
            goto done;
		}
    }
    
    launch_data_free(checkin_response);
    
//    asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Initialization complete");
    
    // Set up SIGTERM handler
    action.sa_handler = signal_handler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    if (  sigaction(SIGTERM, &action, NULL)  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "Failed to set signal handler for SIGTERM");
        goto done;
    }
	
	// Loop processing kernel events.
    for (;;) {

		if (  event_count++ > 100  ) {
			// After processing 100 events, force a new tunnelblickd process to avoid problems caused by memory leaks
			retval = EXIT_SUCCESS;
			goto done;
		}
		
		[pool drain];
		pool = [NSAutoreleasePool new];
		
        FILE *the_stream;
        int  filedesc;
		int nbytes;

		char buffer[SOCKET_BUF_SIZE];
		
        // Get the next event from the kernel event queue.
        if (  -1 == (filedesc = kevent(kq, NULL, 0, &kev_listener, 1, &timeout))  ) {
			if (   sigtermReceived
				&& (errno == EINTR)  ) {
				asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "SIGTERM received; exiting");
				retval = EXIT_SUCCESS;
				goto done;
			}
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "Error from kevent(): %m");
            goto done;
        } else if (  0 == filedesc  ) {
            asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Timed out; exiting");
			
			// If the current log file is too large, start it over
			asl_close(asl);
			struct stat st;
			int stat_result = stat(TUNNELBLICKD_LOG_PATH_C, &st);
			if (  0 == stat_result  ) {
				if (  st.st_size > 100000  ) {
					// Log file is large; replace any existing old log with it and start anew
					rename(TUNNELBLICKD_LOG_PATH_C, TUNNELBLICKD_PREVIOUS_LOG_PATH_C);
				}
			}
            retval = EXIT_SUCCESS;
			goto done;
        }
//        asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Received file descriptor %d", filedesc);
		
        // Accept an incoming connection.
        if (  -1 == (filedesc = accept(kev_listener.ident, (struct sockaddr *)&ss, &slen))  ) {
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "Error from accept(): %m");
            continue; /* this isn't fatal */
        }
//		asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Connection established");
		
		// Get the client's credentials
		uid_t client_euid;
		gid_t client_egid;
		if (  0 != getpeereid(filedesc, &client_euid, &client_egid)  ) {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not obtain peer credentials from unix domain socket: %m; our uid = %lu; our euid = %lu; our gid = %lu; our egid = %lu",
					(unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
			continue; // this isn't fatal
		} else {
//			asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Peer euid = %lu; egid = %lu; our uid = %lu; our euid = %lu; our gid = %lu; our egid = %lu",
//					(unsigned long)client_euid, (unsigned long)client_egid, (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
			;
		}
        
		// Get the request from the client
		nbytes = read(filedesc, buffer, SOCKET_BUF_SIZE - 1);
		if (  0 == nbytes  ) {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "0 bytes from read()");
			continue; // this isn't fatal
		} else if (  nbytes < 0  ) {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "Error from read(): &m");
			continue; // this isn't fatal
		} else if (  SOCKET_BUF_SIZE - 1 == nbytes   ) {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "Too many bytes read; maximum is %lu", (unsigned long)(SOCKET_BUF_SIZE - 2));
			continue; // this isn't fatal
		}
		
		buffer[nbytes] = '\0';	// Terminate so the request is a string
		
        // Ignore request unless it starts with a valid header and is terminated by a \n
		if (  0 != strncmp(buffer, command_header, strlen(command_header))  ) {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "Received %lu bytes from client but did it did not start with a valid header; received '%s'", (unsigned long)nbytes, buffer);
			continue; // this isn't fatal
		}
        char * nlPtr = strchr(buffer, '\n');
		if (   (nlPtr == NULL)
			|| (nlPtr != (buffer + nbytes - 1))
			) {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "Received %lu bytes from client but did not receive a LF at the end; received '%s'", (unsigned long)nbytes, buffer);
			continue; // this isn't fatal
		}
		
		// Remove the LF at the end of the request
		buffer[nbytes - 1] = '\0';

		// Make sure the string is a valid UTF-8 string
		if (  [NSString stringWithUTF8String: buffer] == NULL  ) {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "Received %lu bytes from client but they were not a valid UTF-8 string", (unsigned long)nbytes);
			goto done;
		}
		
		
//		asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Received %lu bytes from client including a terminating NL: '%s'", (unsigned long)nbytes, buffer);
		
		//***************************************************************************************
		//***************************************************************************************
		// Process the request by calling tunnelblick-helper and sending its status and output to the client
		
        // Get the client's username from the client's euid
        struct passwd *pw = getpwuid(client_euid);
        NSString * userName = [NSString stringWithCString: pw->pw_name encoding: NSUTF8StringEncoding];
		if (  userName == nil  ) {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not interpret username as UTF-8");
			goto done;
		}
        NSString * userHome = [NSString stringWithCString: pw->pw_dir  encoding: NSUTF8StringEncoding];
		if (  userHome == nil  ) {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not interpret userhome as UTF-8");
			goto done;
		}
		
		// Set up to have tunnelblick-helper to do the work
		NSString * tunnelblickHelperPath;
		NSString * bundlePath = [[NSBundle mainBundle] bundlePath];
		if (  [[bundlePath lastPathComponent] isEqualToString: @"Resources"]  ) {
			tunnelblickHelperPath = [bundlePath stringByAppendingPathComponent: @"tunnelblick-helper"];
		} else if (  [[bundlePath pathExtension] isEqualToString: @"app"]  ) {
			tunnelblickHelperPath = [[[bundlePath stringByAppendingPathComponent: @"Contents"]
									  stringByAppendingPathComponent: @"Resources"]
									 stringByAppendingPathComponent: @"tunnelblick-helper"];
		} else {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "Invalid bundlePath = '%s'", [bundlePath UTF8String]);
			goto done;
		}
		NSString * command      = [NSString stringWithUTF8String: buffer + strlen(command_header)];		// Skip over the header
		NSArray  * arguments    = [command componentsSeparatedByString: @"\t"];
		NSString * stdoutString = nil;
		NSString * stderrString = nil;
		
		NSMutableString * commandToDisplay = [NSMutableString stringWithString: command];
		[commandToDisplay replaceOccurrencesOfString: @"\t" withString: @" " options: 0 range: NSMakeRange(0, [commandToDisplay length])];

        OSStatus status = runTool(client_euid, client_egid, userName, userHome, tunnelblickHelperPath, arguments, &stdoutString, &stderrString, asl, log_msg);

        if (  status != 0  ) {
            // Log the status from executing the command
            asl_log(asl, log_msg, ASL_LEVEL_NOTICE, "Status = %ld from tunnelblick-helper command '%s'", (long) status, [commandToDisplay UTF8String]);
        }
		
		// Send the status, stdout, and stderr to the client as a UTF-8-encoded string which is terminated by a \0.
		//
		// The header of the string consists of the signed status, the unsigned length of the stdout string,
		// the unsigned length of the stderr string, and a newline. (The numbers are each separated by one space.)
		//
		// The stdout string follows the header, the stderr string follows the stdout string, and a \0 follows that.
		
		const char * headerC = [[NSString stringWithFormat: @"%ld %lu %lu\n",
								 (long)status, (unsigned long)[stdoutString length], (unsigned long)[stderrString length]]
								UTF8String];
		the_stream = fdopen(filedesc, "r+");
		if (  the_stream  ) {
			fprintf(the_stream, "%s%s%s%c", headerC, [stdoutString UTF8String], [stderrString UTF8String], '\0');
			fclose(the_stream);
//			asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Responded to client; header = %s", headerC);
		} else {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "Could not open stream to output to client");
			close(filedesc);  // This isn't fatal
		}
		
		//***************************************************************************************
		//***************************************************************************************
	}

done:
	if (  asl != NULL ) {
		asl_close(asl);
	}

	[pool drain];
	
	return retval;
}
#pragma clang diagnostic pop
