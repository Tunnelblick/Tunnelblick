/*
 * Copyright 2014, 2015 by Jonathan K. Bullard. All rights reserved.
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
 
 
 NOTE: THIS PROGRAM MUST BE RUN AS ROOT. IT IS AN OS X LAUNCHDAEMON
 
 This daemon is used by the Tunnelblick GUI to start and stop OpenVPN instances and perform other activities that require root access.
 
 It is a modified version of SampleD.c, a sample program supplied by Apple.
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

static BOOL sigtermReceived = FALSE;

static void signal_handler(int signalNumber) {
	
	if (  signalNumber == SIGTERM  ) {
		sigtermReceived = TRUE;
	}
}

NSData * availableDataOrError(NSFileHandle * file,
                              aslclient      asl,
                              aslmsg         log_msg) {
	
	// This routine is a modified version of a method from http://dev.notoptimal.net/search/label/NSTask
	// Slightly modified version of Chris Suter's category function used as a private function
    
    NSDate * timeout = [NSDate dateWithTimeIntervalSinceNow: 2.0];
    
	for (;;) {
		
		NSDate * now = [NSDate date];
        if (  [now compare: timeout] == NSOrderedDescending  ) {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "availableDataOrError: Taking a long time checking for data from a pipe");
            timeout = [NSDate dateWithTimeIntervalSinceNow: 2.0];
        }
		
		@try {
			return [file availableData];
		} @catch (NSException *e) {
			if ([[e name] isEqualToString:NSFileHandleOperationException]) {
				if ([[e reason] isEqualToString: @"*** -[NSConcreteFileHandle availableData]: Interrupted system call"]) {
					continue;
				}
				return nil;
			}
			@throw;
		}
	}
}

NSDictionary * getSafeEnvironment(NSString * userName,
								  NSString * userHome,
								  bool includeIV_GUI_VER) {
    
    // Create our own environment to guard against Shell Shock (BashDoor) and similar vulnerabilities in bash
    // (Even if bash is not being launched directly, whatever is being launched could invoke bash;
	//  for example, tunnelblick-helper launches openvpn which can invoke bash for scripts)
    //
    // This environment consists of several standard shell variables
    // If specified, we add the 'IV_GUI_VER' environment variable,
    //                          which is set to "<bundle-id><space><build-number><space><human-readable-version>"
    //
	// A pared-down version of this routine is in process-network-changes
	
    NSMutableDictionary * env = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                 STANDARD_PATH,          @"PATH",
                                 NSTemporaryDirectory(), @"TMPDIR",
                                 userName,               @"USER",
                                 userName,               @"LOGNAME",
                                 userHome,               @"HOME",
                                 TOOL_PATH_FOR_BASH,     @"SHELL",
                                 @"unix2003",            @"COMMAND_MODE",
                                 nil];
    
    if (  includeIV_GUI_VER  ) {
        // We get the Info.plist contents as follows because NSBundle's objectForInfoDictionaryKey: method returns the object as it was at
        // compile time, before the TBBUILDNUMBER is replaced by the actual build number (which is done in the final run-script that builds Tunnelblick)
        // By constructing the path, we force the objects to be loaded with their values at run time.
        NSString * plistPath    = [[[[NSBundle mainBundle] bundlePath]
                                    stringByDeletingLastPathComponent] // Remove /Resources
                                   stringByAppendingPathComponent: @"Info.plist"];
        NSDictionary * infoDict = [NSDictionary dictionaryWithContentsOfFile: plistPath];
        NSString * bundleId     = [infoDict objectForKey: @"CFBundleIdentifier"];
        NSString * buildNumber  = [infoDict objectForKey: @"CFBundleVersion"];
        NSString * fullVersion  = [infoDict objectForKey: @"CFBundleShortVersionString"];
        NSString * guiVersion   = [NSString stringWithFormat: @"%@ %@ %@", bundleId, buildNumber, fullVersion];
        
        [env setObject: guiVersion forKey: @"IV_GUI_VER"];
    }
    
    return [NSDictionary dictionaryWithDictionary: env];
}

OSStatus runTool(NSString * userName,
				 NSString * userHome,
				 NSString * launchPath,
                 NSArray  * arguments,
                 NSString * * stdOutStringPtr,
                 NSString * * stdErrStringPtr,
                 aslclient  asl,
                 aslmsg     log_msg) {
	
	// Runs a command or script, returning the execution status of the command, stdout, and stderr
	
    NSTask * task = [[[NSTask alloc] init] autorelease];
    
    [task setLaunchPath: launchPath];
    [task setArguments:  arguments];
    
    [task setCurrentDirectoryPath: @"/private/tmp"];
    
	NSPipe * stdOutPipe = nil;
	NSPipe * errOutPipe = nil;
	
	if (  stdOutStringPtr  ) {
		stdOutPipe = [NSPipe pipe];
		[task setStandardOutput: stdOutPipe];
	}
    
    if (  stdErrStringPtr  ) {
		errOutPipe = [NSPipe pipe];
		[task setStandardError: errOutPipe];
	}
	
    [task setCurrentDirectoryPath: @"/tmp"];
    [task setEnvironment: getSafeEnvironment(userName, userHome, [[launchPath lastPathComponent] isEqualToString: @"openvpn"])];
    
    [task launch];
	
	// The following loop drains the pipes as the task runs, so a pipe doesn't get full and block the task
    
	NSFileHandle * outFile = [stdOutPipe fileHandleForReading];
	NSFileHandle * errFile = [errOutPipe fileHandleForReading];
	
	NSMutableData * stdOutData = (stdOutStringPtr ? [[NSMutableData alloc] initWithCapacity: 16000] : nil);
	NSMutableData * errOutData = (stdErrStringPtr ? [[NSMutableData alloc] initWithCapacity: 16000] : nil);
	
    BOOL taskIsActive = [task isRunning];
	NSData * outData = availableDataOrError(outFile, asl, log_msg);
	NSData * errData = availableDataOrError(errFile, asl, log_msg);
    
    NSDate * timeout = [NSDate dateWithTimeIntervalSinceNow: 5.0];
    
	while (   ([outData length] > 0)
		   || ([errData length] > 0)
		   || taskIsActive  ) {
        
		if (  [outData length] > 0  ) {
            [stdOutData appendData: outData];
		}
		if (  [errData length] > 0  ) {
            [errOutData appendData: errData];
		}
        
 		NSDate * now = [NSDate date];
        if (  [now compare: timeout] == NSOrderedDescending  ) {
            asl_log(asl, log_msg, ASL_LEVEL_ERR, "runTool: Taking a long time executing '%s'", [launchPath fileSystemRepresentation]);
            timeout = [NSDate dateWithTimeIntervalSinceNow: 5.0];
        }
        
        usleep(100000); // Wait 0.1 seconds
		
        taskIsActive = [task isRunning];
		outData = availableDataOrError(outFile, asl, log_msg);
		errData = availableDataOrError(errFile, asl, log_msg);
	}
	
	[outFile closeFile];
	[errFile closeFile];
	
    [task waitUntilExit];
    
	OSStatus status = [task terminationStatus];
	
	if (  stdOutStringPtr  ) {
		*stdOutStringPtr = [[[NSString alloc] initWithData: stdOutData encoding: NSUTF8StringEncoding] autorelease];
	}
    [stdOutData release];
	
	if (  stdErrStringPtr  ) {
		*stdErrStringPtr = [[[NSString alloc] initWithData: errOutData encoding: NSUTF8StringEncoding] autorelease];
	}
    [errOutData release];
    
	return status;
}

int main(void) {
	
	struct sigaction action;
    
    struct sockaddr_storage ss;
	
    socklen_t       slen          = sizeof(ss);
	aslclient       asl           = NULL;
	aslmsg          log_msg       = NULL;
    int             retval        = EXIT_FAILURE;
	struct timespec timeout       = {  30, 0  };	// TimeOut value (OS X supplies a 30 second value if there is no TimeOut entry in the launchd .plist)
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
    log_msg = asl_new(ASL_TYPE_MSG);
    asl_set(log_msg, ASL_KEY_SENDER, "tunnelblickd");
    
    // Create a new kernel event queue that we'll use for our notification.
    // Note the use of the '%m' formatting character.
	// ASL will replace %m with the error string associated with the current value of errno.
    if (  -1 == (kq = kqueue())  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "kqueue(): %m");
        goto done;
    }
	
	// Make sure we are root:wheel
	if (   (getuid()  != 0)
		|| (getgid()  != 0)
		|| (geteuid() != 0)
		|| (getegid() != 0)
		) {
		asl_log(asl, log_msg, ASL_LEVEL_ERR, "Not root:wheel; our uid = %lu; our euid = %lu; our gid = %lu; our egid = %lu",
				(unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
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
	
	// If the .plist and OS X did not specify a TimeOut, default to 30 seconds
	launch_data_t timeoutValue = launch_data_dict_lookup(checkin_response, LAUNCH_JOBKEY_TIMEOUT);
	if (  timeoutValue != NULL) {
		timeout.tv_sec = launch_data_get_integer(timeoutValue);
	}
    
    launch_data_t the_label = launch_data_dict_lookup(checkin_response, LAUNCH_JOBKEY_LABEL);
    if (  NULL == the_label  ) {
        asl_log(asl, log_msg, ASL_LEVEL_ERR, "No label found");
        goto done;
    }
    
    asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Started %s", launch_data_get_string(the_label));
    
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
        FILE *the_stream;
        int  filedesc;
		int nbytes;

#define SOCKET_BUF_SIZE 1024

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
            return EXIT_SUCCESS;
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

		
//		asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Received %lu bytes from client including a terminating NL: '%s'", (unsigned long)nbytes, buffer);
		
		//***************************************************************************************
		//***************************************************************************************
		// Process the request by calling tunnelblick-helper and sending its status and output to the client
		
		NSAutoreleasePool * pool = [NSAutoreleasePool new];
		
        // Get the client's username from the client's euid
        struct passwd *ss = getpwuid(client_euid);
        NSString * userName = [NSString stringWithCString: ss->pw_name encoding: NSUTF8StringEncoding];
        NSString * userHome = [NSString stringWithCString: ss->pw_dir  encoding: NSUTF8StringEncoding];
		
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
			retval = EXIT_FAILURE;
			[pool drain];
			goto done;
		}
		NSString * command      = [NSString stringWithUTF8String: buffer + strlen(command_header)];		// Skip over the header
		NSArray  * arguments    = [command componentsSeparatedByString: @"\t"];
		NSString * stdoutString = nil;
		NSString * stderrString = nil;
		
		NSMutableString * commandToDisplay = [NSMutableString stringWithString: command];
		[commandToDisplay replaceOccurrencesOfString: @"\t" withString: @" " options: 0 range: NSMakeRange(0, [commandToDisplay length])];
		
		// Pretend we are the client while running tunnelblick-helper
		if (  getegid() == client_egid  ) {
//			asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Before running tunnelblick-helper, setegid(%lu) unnecessary: uid = %lu; euid = %lu; gid = %lu; egid = %lu",
//					(unsigned long)client_egid, (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
			;
		} else if (  setegid(client_egid)  ) {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "Before running tunnelblick-helper, setegid(%lu) failed; uid = %lu; euid = %lu; gid = %lu; egid = %lu; error = %m",
					(unsigned long)client_egid, (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
//		} else {
//			asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Before running tunnelblick-helper, setegid(%lu) succeeded: uid = %lu; euid = %lu; gid = %lu; egid = %lu",
//					(unsigned long)client_egid, (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
		}
		if (  geteuid() == client_euid  ) {
//			asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Before running tunnelblick-helper, seteuid(%lu) unnecessary; uid = %lu; euid = %lu; gid = %lu; egid = %lu",
//					(unsigned long)client_euid, (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
			;
		} else if (  seteuid(client_euid)  ) {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "Before running tunnelblick-helper, seteuid(%lu) failed; uid = %lu; euid = %lu; gid = %lu; egid = %lu; error = %m",
					(unsigned long)client_euid, (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
//		} else {
//			asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Before running tunnelblick-helper, seteuid(%lu) succeeded; uid = %lu; euid = %lu; gid = %lu; egid = %lu",
//					(unsigned long)client_euid, (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
		}
		
//		asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "Launching tunnelblick-helper as uid 0, euid = %lu, gid = 0, and egid = %lu; user '%s' with home folder '%s'",
//				(unsigned long)client_euid, (unsigned long)client_egid, [userName UTF8String], [userHome UTF8String]);
		
		OSStatus status = runTool(userName, userHome, tunnelblickHelperPath, arguments, &stdoutString, &stderrString, asl, log_msg);
		
		// Resume being root:wheel if needed
		if (   geteuid() == 0  ) {
//			asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "After running tunnelblick-helper, seteuid(0) unnecessary; uid = %lu; euid = %lu; gid = %lu; egid = %lu",
//					(unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
			;
		} else if (  seteuid(0)  ) {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "After running tunnelblick-helper with command '%s', seteuid(0) failed; uid = %lu; euid = %lu; gid = %lu; egid = %lu; error = %m",
					[commandToDisplay UTF8String], (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
			retval = EXIT_FAILURE;
			[pool drain];
			goto done;
		} else {
//			asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "After running tunnelblick-helper, seteuid(0) succeeded; uid = %lu; euid = %lu; gid = %lu; egid = %lu",
//					(unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
			;
		}
		if (   getegid() == 0  ) {
//			asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "After running tunnelblick-helper, setegid(0) unnecessary; uid = %lu; euid = %lu; gid = %lu; egid = %lu",
//					(unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
			;
		} else if (  setegid(0)  ) {
			asl_log(asl, log_msg, ASL_LEVEL_ERR, "After running tunnelblick-helper with command '%s', setegid(0) failed; uid = %lu; euid = %lu; gid = %lu; egid = %lu; error = %m",
					[commandToDisplay UTF8String], (unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
			retval = EXIT_FAILURE;
			[pool drain];
			goto done;
//		} else {
//			asl_log(asl, log_msg, ASL_LEVEL_DEBUG, "After running tunnelblick-helper, setegid(0) succeeded; uid = %lu; euid = %lu; gid = %lu; egid = %lu",
//					(unsigned long)getuid(), (unsigned long)geteuid(), (unsigned long)getgid(), (unsigned long)getegid());
		}
        
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
		
		[pool drain];
		pool = nil;
		
		//***************************************************************************************
		//***************************************************************************************
	}
	
done:
    asl_close(asl);
	return retval;
}