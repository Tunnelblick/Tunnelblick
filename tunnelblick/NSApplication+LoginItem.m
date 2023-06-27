//
//  NSApplication+LoginItem.m
//  MenuCalendar
//
//  Created by Dirk Theisen on Thu Feb 26 2004.
//  Copyright 2004 Objectpark Software. All rights reserved.
//  Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2023. All rights reserved.
//
//  Permission to use, copy, modify, and distribute this software for any
//  purpose with or without fee is hereby granted, provided that the above
//  copyright notice and this permission notice appear in all copies.
// 
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
//  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
//  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
//  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
//  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.


#import "NSApplication+LoginItem.h"

#import <AppKit/AppKit.h>
#import <signal.h>
#import <sys/sysctl.h>
#import <sys/types.h>
#import <sys/stat.h>

#import "defines.h"
#import "helper.h"
#import "sharedRoutines.h"

#import "MenuController.h"
#import "NSArray+cArray.h"
#import "NSFileManager+TB.h"
#import "TBUserDefaults.h"
#import "UKLoginItemRegistry/UKLoginItemRegistry.h"

// The following external, global variable is used by functions in this file and must be declared and set elsewhere before the
// functions in this file are called:
extern NSFileManager  * gFileMgr;
extern TBUserDefaults * gTbDefaults;

@implementation NSApplication (LoginItem)

- (void) killOtherInstances
/*" Tries to terminate (SIGTERM) all other processes that happen to be named like the current running process name. Useful for stopping old versions or duplicates of the running application. "*/
{
    int         myPid = [[NSProcessInfo processInfo] processIdentifier];
    const char* myProcessName = [[[NSProcessInfo processInfo] processName] UTF8String];
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
    size_t length;
    int count, i;
    
    // KERN_PROC_ALL has 3 elements, all others have 4
    unsigned level = 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) return;
    // Allocate memory for info structure:
    if (!(info = NSZoneMalloc(NULL, length))) return;
    if (sysctl(mib, level, info, &length, NULL, 0) < 0) {
        NSZoneFree(NULL, info);
        return;
    }
    
    // Calculate number of processes:
    count = length / sizeof(struct kinfo_proc);
    for (i = 0; i < count; i++) {
        char* command = info[i].kp_proc.p_comm;
        pid_t pid = info[i].kp_proc.p_pid;
        //NSLog(@"Found running command: '%s'", command);
        // Test, if this command is called like us:
        if (pid!=myPid && strncmp(myProcessName, command, MAXCOMLEN)==0) {
            // Actually kill it:
            if (kill(pid, SIGTERM) !=0) {
                NSLog(@"Error while killing process: Error was '%s'", strerror(errno)); 
            }
        }
    }    
    NSZoneFree(NULL, info);
}

- (int) countOtherInstances
// Returns the number of other instances of a process (cribbed from killOtherInstances, above)
{
    int         myPid = [[NSProcessInfo processInfo] processIdentifier];
    const char* myProcessName = [[[NSProcessInfo processInfo] processName] UTF8String];
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
    size_t length;
    int count, i;
    int returnCount = 0;
    
    // KERN_PROC_ALL has 3 elements, all others have 4
    unsigned level = 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) return (-1);
    // Allocate memory for info structure:
    if (!(info = NSZoneMalloc(NULL, length))) return (-1);
    if (sysctl(mib, level, info, &length, NULL, 0) < 0) {
        NSZoneFree(NULL, info);
        NSLog(@"countOtherInstances: sysctl returned error %d: '%s'", errno, strerror(errno));
        return(-1);
    }
    
    // Calculate number of processes:
    count = length / sizeof(struct kinfo_proc);
    for (i = 0; i < count; i++) {
        char* command = info[i].kp_proc.p_comm;
        pid_t pid = info[i].kp_proc.p_pid;
        //NSLog(@"Found running command: '%s'", command);
        // Test, if this command is called like us:
        if (pid!=myPid && strncmp(myProcessName, command, MAXCOMLEN)==0) {
            returnCount++;
        }
    }    
    NSZoneFree(NULL, info);
    return(returnCount);
}

-(NSMutableArray *) pIdsForOpenVPNProcessesOnlyMain: (BOOL) onlyMain {
    
    // Returns an array of NSNumber objects, each with the pid for an OpenVPN process
    // Returns nil on error, empty array if no OpenVPN processes running
    //
    // if onlyMain is TRUE, returns only processes named 'openvpn'
    // else returns process whose names _start_ with 'openvpn' (e.g. 'openvpn-down-root')
    //
    //  (modified version of countOtherInstances, above)
    
    NSMutableArray * retArray = [NSMutableArray arrayWithCapacity: 2];
    const char* processName = "openvpn";
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
    size_t length;
    int count, i;
    
    // KERN_PROC_ALL has 3 elements, all others have 4
    unsigned level = 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) return (nil);
    // Allocate memory for info structure:
    if (!(info = NSZoneMalloc(NULL, length))) return (nil);
    if (sysctl(mib, level, info, &length, NULL, 0) < 0) {
        NSZoneFree(NULL, info);
        return(nil);
    }
    
    // Get each process ID:
    count = length / sizeof(struct kinfo_proc);
    for (i = 0; i < count; i++) {
        char* command = info[i].kp_proc.p_comm;
        pid_t pid = info[i].kp_proc.p_pid;
        if (strncmp(processName, command, MAXCOMLEN)==0) {
            if (   (! onlyMain)
                || (strlen(command) == strlen(processName))  ) {
                [retArray addObject: [NSNumber numberWithInt: (int) pid]];
            }
        }
    }
    NSZoneFree(NULL, info);
    
    return(retArray);
}

// Waits up to five seconds for a process to be gone
// (Modified version of NSApplication+LoginItem's killOtherInstances)
// Returns TRUE if process has terminated, otherwise returns FALSE
- (BOOL) waitUntilNoProcessWithID: (pid_t) pid
{
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
    size_t length;
    int count, i, j;
    BOOL found = FALSE;
    
    // KERN_PROC_ALL has 3 elements, all others have 4
    unsigned level = 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) {
        NSLog(@"Error: waitUntilNoProcessWithID: sysctl call #1: errno = %d\n%s", errno, strerror(errno));
        return FALSE;
    }
    
    for (j=0; j<6; j++) {   // Check six times, one second wait between each = five second maximum wait
        
        if (  j != 0  ) {       // Don't sleep first time through
            sleep(1);
        }
        // Allocate memory for info structure:
        if (  (info = NSZoneMalloc(NULL, length)) != 0  ) {
            
            if (  sysctl(mib, level, info, &length, NULL, 0) == 0  ) {
                // Calculate number of processes:
                count = length / sizeof(struct kinfo_proc);
                found = FALSE;
                for (i = 0; i < count; i++) {
                    if (  info[i].kp_proc.p_pid == pid  ) {
                        found = TRUE;
                        break;
                    }
                    
                }
                
                NSZoneFree(NULL, info);
                
                if (  ! found  ) {
                    return TRUE;
                }
                
            } else {
                NSZoneFree(NULL, info);
                NSLog(@"Error: waitUntilNoProcessWithID: sysctl call #2: length = %lu errno = %ld\n%s", (long) length, (long) errno, strerror(errno));
            }
            
        } else {
            NSLog(@"Error: waitUntilNoProcessWithID: NSZoneMalloc failed");
        }
        
    }
    
    if (  ! found  ) {
        return TRUE;
    }

    NSLog(@"Error: Timeout (5 seconds) waiting for OpenVPN process %d to terminate", pid);
    return FALSE;
}

- (BOOL)            wait: (int)        waitSeconds
     untilNoProcessNamed: (NSString *) processName {

    // Waits up to a specified time for there to be no processes with a specified name
    // (Modified version of NSApplication+LoginItem's killOtherInstances)
    // Returns TRUE if process has terminated, otherwise returns FALSE

    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
    size_t length;
    int count, i, j;
    const char * processNameCString = [processName UTF8String];
    
    // KERN_PROC_ALL has 3 elements, all others have 4
    unsigned level = 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) {
        NSLog(@"Error: wait:untilNoProcessNamed: sysctl call #1: errno = %d\n%s", errno, strerror(errno));
        return FALSE;
    }
    
    for (j=0; j<(waitSeconds+1); j++) {   // Check with a one second wait between each test
        
        if (  j != 0  ) {       // Don't sleep first time through
            sleep(1);
        }
        // Allocate memory for info structure:
        if (  (info = NSZoneMalloc(NULL, length)) != 0  ) {
            
            if (  sysctl(mib, level, info, &length, NULL, 0) == 0  ) {
                // Calculate number of processes:
                count = length / sizeof(struct kinfo_proc);
                BOOL found = FALSE;
                for (i = 0; i < count; i++) {
                    char* command = info[i].kp_proc.p_comm;
                    if (strncmp(processNameCString, command, MAXCOMLEN)==0) {
                        found = TRUE;
                        break;
                    }
                }
                
                NSZoneFree(NULL, info);
                
                if (  ! found  ) {
                    return TRUE;
                }
                
            } else {
                NSZoneFree(NULL, info);
                NSLog(@"Error: wait:untilNoProcessNamed: sysctl call #2: length = %lu errno = %ld\n%s", (long) length, (long) errno, strerror(errno));
            }
            
        } else {
            NSLog(@"Error: wait:untilNoProcessNamed: NSZoneMalloc failed");
        }
    }
    
    NSLog(@"Error: Timeout wait:untilNoProcessNamed: '%@' to terminate", processName);
    return FALSE;
}

-(NSArray *) pidsOfProcessesWithPrefix: (NSString *) prefix {
    
    // Returns an array with the PID of each process whose command line start with the given prefix.
    // For example, "/Applications/Tunnelblick.app/Contents/Resources/openvpn" would return the PID of any running
    // instance of "openvpnstart" as well as the PID of each instance of Tunnelblick's OpenVPN
    //
    // Returns nil if there are no such processes
    
    // Run "ps -A" to get info on all processess
    NSString * stdoutString = nil;
    NSArray  * arguments = [NSArray arrayWithObject: @"-A"];
    OSStatus status = runTool(TOOL_PATH_FOR_PS, arguments, &stdoutString, nil);
    if (  status != 0  ) {
        NSLog(@"Assuming none of our OpenVPN processes are running because '%@ -Gn' returned status %ld", TOOL_PATH_FOR_PS, (long)status);
        return 0;
    }
    
    // Go through the info and populate the list
    NSMutableArray * list = [[[NSMutableArray alloc] init] autorelease];
    NSArray * lines = [stdoutString componentsSeparatedByString: @"\n"];
    NSString * line;
    NSEnumerator * e = [lines objectEnumerator];
    while (  (line = [e nextObject])  ) {
        if (  [line length] > PS_CHARACTERS_BEFORE_COMMAND  ) {
			NSString * command = [line substringFromIndex: PS_CHARACTERS_BEFORE_COMMAND];
			if (  [command hasPrefix: prefix]  ) {
				unsigned pid = cvt_atou([line UTF8String], @"Process ID");
				[list addObject: [NSNumber numberWithUnsignedInt: pid]];
			}
		}
	}
    
    if (  [list count] == 0  ) {
        return nil;
    }
    return list;
}

-(void) haveDealtWithOldLoginItem  {
    
    // Invoked on main thread because gTbDefaults may not be thread-safe
	
	[gTbDefaults setBool: TRUE forKey: @"haveDealtWithOldLoginItem"];
}

-(void) deleteOurLoginItemLeopardOrNewer {
    
	// This is a modified version of a method from http://blog.originate.com/blog/2013/10/07/answers-to-common-questions-in-cocoa-development/
	
    NSURL * ourURL = [NSURL fileURLWithPath: @"/Applications/Tunnelblick.app/"];
    
	OSStatus status;
	LSSharedFileListItemRef existingItem = NULL;
	
	LSSharedFileListRef lsLoginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
	if (  lsLoginItems  ) {
		UInt32 seed = 0U;
		CFArrayRef lsLoginItemsSnapshot = LSSharedFileListCopySnapshot(lsLoginItems, &seed);
		NSArray * currentLoginItems = (NSArray *)lsLoginItemsSnapshot;
		if (  currentLoginItems  ) {
			NSUInteger ix;
			for (  ix=0; ix<[currentLoginItems count]; ix++  ) {
				LSSharedFileListItemRef item = (LSSharedFileListItemRef)[currentLoginItems objectAtIndex: ix];
				
				UInt32 resolutionFlags = kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes;
				CFURLRef URL = NULL;
				status = LSSharedFileListItemResolve(item, resolutionFlags, &URL, /*outRef*/ NULL);
				if (  status == noErr  ) {
					if (  ! URL  ) {
						NSLog(@"deleteOurLoginItem: loginItemsArray contains a NULL object");
					}
					BOOL foundIt = CFEqual(URL, (CFTypeRef)(ourURL));
					
					if (  foundIt  ) {
						existingItem = item;
						break;
					}
				} else if (  status != -35 /* nsvErr -- no such volume */  ) {
					NSLog(@"deleteOurLoginItem: LSSharedFileListItemResolve returned status = %ld for item; url was %@",
						  (long) status, ((URL == NULL) ? @"NULL" : @"not NULL"));
				}
				if (  URL  ) {
					CFRelease(URL);
				}
			}
			
			if (   existingItem == NULL  ) {
				NSLog(@"No old login item to remove");
                [self performSelectorOnMainThread: @selector(haveDealtWithOldLoginItem) withObject: nil waitUntilDone: NO];
            } else {
				status = LSSharedFileListItemRemove(lsLoginItems, existingItem);
				if (  status == noErr  ) {
					NSLog(@"Successfully removed the old login item");
                    [self performSelectorOnMainThread: @selector(haveDealtWithOldLoginItem) withObject: nil waitUntilDone: NO];
                } else {
					NSLog(@"deleteOurLoginItem: LSSharedFileListItemRemove returned status = %ld for loginItem for %@", (long) status, ourURL);
				}
			}
			
			CFRelease(lsLoginItemsSnapshot);
			
		} else {
            NSLog(@"deleteOurLoginItem: LSSharedFileListCopySnapshot() returned NULL");
		}
		
		CFRelease(lsLoginItems);
		
	} else {
        NSLog(@"deleteOurLoginItem: LSSharedFileListCreate() returned NULL");
	}
}

-(void) deleteOurLoginItemLeopardOrNewerThread {
	
	// This runs in a separate thread because deleteOurLoginItemLeopardAndUp can stall for a long time on network access
	// to a non-existing network resource (even though kLSSharedFileListDoNotMountVolumes is specified).
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
    [self deleteOurLoginItemLeopardOrNewer];
	
    [pool drain];
}

-(void) setupNewAutoLaunchOnLogin {
    
    // Set up the new mechanism for controlling whether Tunnelblick is launched when the user logs in.
    
    // If the 'haveDealtWithOldLoginItem' preference does not exist, we should remove the Tunnelblick login item if there is one.
    // When the old login item has been dealt with, the haveDealtWithOldLoginItem method will be invoked, which will set the preference.
    
    if (  ! [gTbDefaults objectForKey: @"haveDealtWithOldLoginItem"]  ) {
		NSLog(@"Launching a thread to remove the old login item (if any) so we can use the new mechanism that controls Tunnelblick's launch on login");
        [NSThread detachNewThreadSelector: @selector(deleteOurLoginItemLeopardOrNewerThread) toTarget: NSApp withObject: nil];
    }
	
    // If the installed 'net.tunnelblick.tunnelblick.LaunchAtLogin.plist' is not the same as ours, update it.
    
#ifdef TBDebug
	NSLog(@"DEBUG VERSION DOES NOT UPDATE LaunchAtLogin.plist.");
#else
    NSString * ourPlistPath = @"/Applications/Tunnelblick.app/Contents/Resources/net.tunnelblick.tunnelblick.LaunchAtLogin.plist";
    NSString * launchAgentsPath = [[NSHomeDirectory() stringByAppendingPathComponent: @"Library"]
								   stringByAppendingPathComponent: @"LaunchAgents"];
	NSString * installedPlistPath = [launchAgentsPath stringByAppendingPathComponent: @"net.tunnelblick.tunnelblick.LaunchAtLogin.plist"];
    if (  ! [gFileMgr contentsEqualAtPath: ourPlistPath andPath: installedPlistPath]  ) {
		if (  [gFileMgr fileExistsAtPath: installedPlistPath]  ) {
			[gFileMgr tbRemoveFileAtPath: installedPlistPath handler: nil];
		}
		if (   ( createDir(launchAgentsPath, 0700) == -1  )
			|| ( ! [gFileMgr tbCopyPath: ourPlistPath toPath: installedPlistPath handler: nil] )  ) {
            NSLog(@"Failed to copy: %@ to %@", ourPlistPath, installedPlistPath);
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                              NSLocalizedString(@"Tunnelblick could not be configured to automatically launch itself after you log in.\n\n"
                                                @"See the Console log for details.", @"Window text"));
        } else {
            NSLog(@"Copied our 'net.tunnelblick.tunnelblick.LaunchAtLogin.plist' into ~/Library/LaunchAgents");
        }
    }
#endif
}

+(OSStatus) executeAuthorized:(NSString *)toolPath withArguments:(NSArray *)arguments withAuthorizationRef:(AuthorizationRef) myAuthorizationRef {
	const char * myToolPath = [gFileMgr fileSystemRepresentationWithPath: toolPath];
	char **myArguments = [arguments cArray];
	OSStatus myStatus;
	AuthorizationFlags myFlags = kAuthorizationFlagDefaults;
	myStatus = AuthorizationExecuteWithPrivileges(myAuthorizationRef, myToolPath, myFlags, myArguments, NULL);
	freeCArray(myArguments);
    if (  myStatus != 0  ) {
        NSLog(@"AuthorizationExecuteWithPrivileges returned status = %ld", (long) myStatus);
    }
	return myStatus;
}

struct authorizedDoneData {
    BOOL errorOccurred;
    time_t epochTime;
};

+(BOOL) parseAuthorizedDoneFile: (struct authorizedDoneData *) dataPtr {

    // Get contents of AUTHORIZED_DONE_PATH file:
    //      1st character is "B" for bad, "G" for good,
    //      the rest of the contents is a deciaml representation in ASCII of the epoch time that the tool finished.

    NSString * contents = [NSString stringWithContentsOfFile: AUTHORIZED_DONE_PATH encoding: NSUTF8StringEncoding error: nil];
    if (  [contents length] < 6  ) {
        TBLog(@"DB-AA", @"File does not exist or is too short: %@", AUTHORIZED_DONE_PATH);
        return FALSE;
    }

    if (   ( ! [contents hasPrefix: @"G"] )
        && ( ! [contents hasPrefix: @"B"] )  ) {
        NSLog(@"File does not start with 'G' or 'B': %@", AUTHORIZED_DONE_PATH);
        return FALSE;
    }

    time_t epochTime  = strtol([[contents substringFromIndex: 1] UTF8String], NULL, 10);
    if (   (epochTime == 0)
        || (epochTime == LONG_MIN)
        || (epochTime == LONG_MAX)  ) {
        NSLog(@"Time cannot be parsed in file: %@", AUTHORIZED_DONE_PATH);
        return FALSE;
    }

    (*dataPtr).errorOccurred = [contents hasPrefix: @"B"];
    (*dataPtr).epochTime = epochTime;
    return TRUE;
}

+(wfeaReturnValue) waitForExecuteAuthorized: (NSString *)       toolPath
                              withArguments: (NSArray *)        arguments
                       withAuthorizationRef: (AuthorizationRef) myAuthorizationRef {

    // IMPORTANT: WITHIN TUNNELBLICK, THE TOOL MUST BE STARTED *ONLY* BY THIS ROUTINE. Otherwise, this routine could spuriously detect that the tool was done even though
    //            it was actually some other invocation of the tool that was complete.
    //
    //
    // executeAuthorized returns immediately, either with an error or having started the tool but not having waited for the tool to complete.
    //
    // However, this routine must wait until the tool is finished to continue.
    //
    // So when the tool is finished, it creates or updates the file at AUTHORIZED_DONE_PATH to indicate that it has finished. The information
    // in the file allows this routine to determine if the tool has finished _this_ request (not some earlier request) and whether the tool
    // succeeded or failed.

    time_t epochTimeAtStart = time(NULL);

    // Wait to start the tool until it is later than epochTimeAtStart
    // That way we know that the time the tool finishes will be > epochTimeAtStart
    while (  time(NULL) == epochTimeAtStart  ) {
        usleep(ONE_TENTH_OF_A_SECOND_IN_MICROSECONDS);
    }

    if (  EXIT_SUCCESS != [NSApplication executeAuthorized: toolPath withArguments: arguments withAuthorizationRef: myAuthorizationRef]  ) {
        return wfeaExecAuthFailed;
    }
    
    // Wait for up to about 30 seconds for the program to finish -- sleeping .05 seconds first, then .1, .2, .4, .8, .8, .8... seconds between tries as a cheap and easy throttling mechanism for a heavily loaded computer
    
    useconds_t sleepTimeMicroseconds = (ONE_TENTH_OF_A_SECOND_IN_MICROSECONDS / 2); // First sleep time is 0.050 seconds
    for (;;) {
        
        if (  time(NULL) > (epochTimeAtStart + 30)  ) {
            break;
        }
        
        usleep(sleepTimeMicroseconds);
        if (  sleepTimeMicroseconds < (8 * ONE_TENTH_OF_A_SECOND_IN_MICROSECONDS)  ) {
            sleepTimeMicroseconds *= 2;
        }

        struct authorizedDoneData data;
        BOOL result = [self parseAuthorizedDoneFile: &data];
        if ( ! result ) {
            TBLog(@"DB-AA", @"File does not exist or is invalid: %@", AUTHORIZED_DONE_PATH);
            continue;
        }

        if (  data.epochTime <= epochTimeAtStart  ) {
            TBLog(@"DB-AA", @"File was last modified before the tool was started");
            continue;
        }

        // The tool finished after we started it, so it was our invocation of it that finished
        wfeaReturnValue status = (  data.errorOccurred
                                  ? wfeaExecAuthFailed
                                  : wfeaSuccess);
        TBLog(@"DB-AA", @"waitForExecuteAuthorized: returning %@", (data.errorOccurred ? @"wfeaExecAuthFailed" : @"wfeaSuccess"));
        return (status);
    }
    
    NSLog(@"Timed out waiting for %@ to be created or modified indicting %@ finished", AUTHORIZED_DONE_PATH, [toolPath lastPathComponent]);
    return wfeaTimedOut;
}

@end
