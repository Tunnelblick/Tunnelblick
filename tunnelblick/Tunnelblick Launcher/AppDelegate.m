/*
 * Copyright 2024 by Jonathan K. Bullard. All rights reserved.

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
 */

// This application is designed to be run each time a user logs in.
//
// It launches Tunnelblick if it is not already running and
// any of the following conditions are met:
//
//      The "launchAtNextLogin" preference is true
//      Network services have been disabled by Tunnelblick
//      A VPN is being or has been connected (i.e., OpenVPN,
//      openvpnstart, or tunnelblick-helper are running).
//
// Then it quits.
//
// Note: this application maintains its own plain-text log file at
//      ~/Library/Application Support/Tunnelblick/TBLogs/Tunenlblick Launcher.log
// The log file is kept small by removing its earliest entries when it gets too large.

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

#import "AppDelegate.h"

#import "../defines.h"
#import "../NSFileHandle+TB.h"
#import "../NSFileManager+TB.h"
#import "../sharedRoutines.h"   // RunTool() is used in this program


//***************************************************************************************************
//
// Preprocesor macros

// Maximum size for the log: 64 lines of 120 bytes = 7,680 bytes.
//
// When exiting this program, if the log file is larger, we shrink it by removing early entries.
//
// Because we shrink the file to half of this size, we will always have at least the last 32 lines or
// so (depending on the size of the lines).
//
// (Note: MUST BE A MULTIPLE OF 2)

#define MAX_LOG_SIZE (64 * 120)

// Macro for logging that accepts a format string optionally followed by other arguments.
// Translates it to call a routine that accepts a single string message.
// (This is a replacement for NSLog() that logs to a file instead of the Console.)

#define LauncherLog(fmt,...) LauncherLogOneString([NSString stringWithFormat: (fmt), ##__VA_ARGS__]);

void LauncherLogOneString(NSString * message);  // The routine that accepts a single string message


//***************************************************************************************************
//
// Routine(s) and external variables which must be defined even though they are not used to avoid
// linker errors caused by undefined identifiers.

// The following routine is referenced in SharedRoutines.m, but not in a routine not used by this program

void appendLog(NSString * msg)
{
    NSLog(@"%@", msg);
}

// The following variable is referenced in SharedRoutines.m, but not in a routine not used by this program

NSString       * gDeployPath = nil;

//***************************************************************************************************
//
// Logging for this program
//
// A large portion of the code for this app -- even larger than the code that implements the app itself --
// does logging. We want to keep a short log of this program's activities in a text file so it is easily
// accessible.
//
// We don't need to deal with race conditions or reentrancy because only this program writes to this log
// file and it only writes to the log file on the main thread.
//
// Because this application is launched only once per login, and only logs one or two
// messages when it is executed, we open/append/close the file for each message.

NSString * LauncherLogPath(void) {

    NSString * path = [[[[[NSHomeDirectory()
                           stringByAppendingPathComponent: @"Library"]
                          stringByAppendingPathComponent: @"Application Support"]
                         stringByAppendingPathComponent: @"Tunnelblick"]
                        stringByAppendingPathComponent: @"TBLogs"]
                       stringByAppendingPathComponent: @"Tunnelblick Launcher.log"];
    return path;
}

void LogErrorInShrink(NSString * description, NSError * err) {

    // Log to the Console in case there is a problem logging to the file
    NSLog(@"ShrinkLauncherLogIfItIsTooLong: Error in '%@': %@", description, err);

    LauncherLog(@"ShrinkLauncherLogIfItIsTooLong: Error in '%@': %@", description, err);
}

void ShrinkLauncherLogIfItIsTooLong(void) {

    // Shrinks the log if it is too long by removing the oldest half.
    //
    // Some of the errors this routine detects probably mean that LauncherLog() will
    // also fail, but LogErrorInShrink will output the error messasge to NSLog()
    // first, so if LauncherLog() fails, the error messsage will still be available.

    NSError * err = nil;

    // Get the current size of the log file
    NSFileManager * fm = [NSFileManager defaultManager];
    if (  ! fm  ) {
        LogErrorInShrink(@"defaultManager: returned nil", err);
        return;
    }
    NSString * logPath = LauncherLogPath();
    if (  ! logPath  ) {
        LogErrorInShrink(@"LauncherLogPath() returned nil", err);
        return;
    }
    if (  ! [fm fileExistsAtPath: logPath]  ) {
        return;
    }
    NSDictionary * attributes = [fm attributesOfItemAtPath: logPath error: &err];
    if (  ! attributes  ) {
        LogErrorInShrink(@"attributesOfItemAtPath: returned nil", err);
        return;
    }
    unsigned long long fileSize = [attributes fileSize];

    if (  fileSize < MAX_LOG_SIZE  ) {
        return;
    }

    NSFileHandle * handle = [NSFileHandle fileHandleForUpdatingAtPath: logPath];
    if (  ! handle  ) {
        LogErrorInShrink(@"fileHandleForUpdatingAtPath: returned nil", nil);
        return;
    }

    // Get contents of second half of the file
    unsigned long long desiredSize = (MAX_LOG_SIZE / 2);        // Size we want after shrinking
    unsigned long long seekPoint = (fileSize - desiredSize);    // Seek to that far from the end of the file
    if (  ! [handle tbSeekToOffset: seekPoint error: &err]  ) {
        LogErrorInShrink([NSString stringWithFormat: @"tbSeekToOffset: %llu error: returned error", (fileSize / 2)], err);
        return;
    }
    NSData * data = nil;
    if (  ! (data = [handle tbReadDataToEndOfFileAndReturnError: &err])  ) {
        LogErrorInShrink(@"tbReadDataToEndOfFileAndReturnError: returned error", err);
        return;
    }

    // Remove everything up to and including the first LF (if there is one)
    NSString * contents = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
    if (  ! contents  ) {
        LogErrorInShrink(@"NSString initWithData: returned error", nil);
        return;
    }
    NSString * newContents = contents;
    NSRange firstLF = [contents rangeOfString: @"\n"];
    if (  firstLF.length != 0  ) {
        newContents = [contents substringFromIndex: firstLF.location + 1];
        if (  ! newContents  ) {
            LogErrorInShrink(@"substringFromIndex: returned nil", nil);
            return;
        }
    } else {
        ;   // No LF found, so use the entire contents we read
    }
    data = [newContents dataUsingEncoding: NSUTF8StringEncoding];
    if (  ! data  ) {
        LogErrorInShrink(@"dataUsingEncoding: returned nil", nil);
        return;
    }

    // Write out new contents at the start of the file
    if (  ! [handle tbSeekToOffset: 0 error: &err]  ) {
        LogErrorInShrink(@"tbSeekToOffset: 0 error: returned error", err);
        return;
    }
    if (  ! [handle tbWriteData: data error: &err]  ) {
        LogErrorInShrink(@"tbWriteData:error: returned error", err);
        return;
    }

    // Truncate the file and close it
    unsigned long long newLength = data.length;
    if (  ! [handle tbTruncateAtOffset: newLength error: &err]  ) {
        NSLog(@"Error in tbTruncateAtOffset: %llu error: %@ ", newLength, err);
        return;
    }
    if (  ! [handle tbCloseAndReturnError: &err]  ) {
        NSLog(@"Error in tbCloseAndReturnError: error: %@ ", err);
        return;
    }
}

void LauncherLogOneString(NSString * message) {

    // Appends a message and a LF to the log after prefixing it with the date and time.

    NSError * err = nil;

    NSString * logPath = LauncherLogPath();
    if (  ! logPath  ) {
        NSLog(@"Could not get log path");
        return;
    }

    NSDateFormatter * df = [[[NSDateFormatter alloc] init] autorelease];
    [df setLocale: [NSLocale localeWithLocaleIdentifier: @"en_US_POSIX"]];
    [df setDateFormat: @"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString * dateTime = [df stringFromDate: [NSDate date]];
    if (  ! dateTime  ) {
        dateTime = @"0000-00-00 00:00:00.000";   // No need to log this error, the problem will be obvious
    }
    NSString * fullMessage = [NSString stringWithFormat: @"%@ %@\n", dateTime, message];

    NSFileHandle * handle = [NSFileHandle fileHandleForUpdatingAtPath: logPath];
    if (  handle  ){
        unsigned long long offset = 0;
        if (  ! [handle tbSeekToEndReturningOffset: &offset error: &err]  ) {
            NSLog(@"Error in tbSeekToEndReturningOffset: error: %@ ", err);
            return;
        }
        if (  ! [handle tbWriteData: [fullMessage dataUsingEncoding: NSUTF8StringEncoding] error: &err]  ) {
            NSLog(@"Error in tbWriteData: error: %@ ", err);
            return;
        }

        if (  ! [handle tbCloseAndReturnError: &err]  ) {
            NSLog(@"Error in tbCloseAndReturnError: error: %@ ", err);
            return;
        }
    } else {
        [fullMessage writeToFile: logPath
                      atomically: NO
                        encoding: NSUTF8StringEncoding
                           error: nil];
    }
}

//***************************************************************************************************
//
// Other routines used by this program

void launchTunnelblick(NSString * message) {

    LauncherLog(@"%@", message);
    startTool(TOOL_PATH_FOR_OPEN, @[APPLICATIONS_TB_APP]);
}

NSString * GetProcesses(void) {

    // Returns a string with the output from the 'ps -f -u 0' command, which lists all root processes and
    // the command line arguments each process was started with.
    //
    // Returns nil if an error occurred

    NSString * stdOutString = nil;
    NSString * stdErrString = nil;

    // Construct parameter for ps -U option to get process info for root (0) and the current user (e.g., "0,501")
    uid_t uid = getuid();
    NSString * uOptionValue = [NSString stringWithFormat: @"0,%u", uid];

    OSStatus status = runTool(TOOL_PATH_FOR_PS, @[@"-f", @"-U", uOptionValue], &stdOutString, &stdErrString);
    if (  status != EXIT_SUCCESS ) {
        LauncherLog(@"Nonzero status %d from 'ps -f -u 0'; stderr = '%@'; stdout = '%@'", status, stdErrString, stdOutString);
        stdOutString = nil;
    } else if (  [stdErrString length] != 0 ) {
        LauncherLog(@"status from 'ps -f -u 0' was 0, but stderr = '%@'; stdout = '%@'", stdErrString, stdOutString);
        stdOutString = nil;
    } else if (  [stdOutString length] == 0 ) {
        LauncherLog(@"Empty stdout from 'ps -f -u 0");
        stdOutString = nil;
    }

    return stdOutString;
}

@implementation AppDelegate

//***************************************************************************************************
// Housekeeping methods

-(void) dealloc {

    [super dealloc];
}

-(BOOL) applicationSupportsSecureRestorableState:(NSApplication *)app {
    return NO;
}

//***************************************************************************************************
//
// Main part of the application. All the work is done in this method.
//
// It launches Tunnelblick if appropriate, then terminates the execution of this application.

-(void) applicationDidFinishLaunching: (NSNotification *)aNotification {

    NSString * processes = GetProcesses();
    if (  ! processes  ) {
        goto finished; // Have already logged an error
    }

    BOOL tunnelblick_is_running = [processes containsString: @"/Applications/Tunnelblick.app/Contents/MacOS/Tunnelblick"];
    if (  tunnelblick_is_running  ) {
        LauncherLog(@"Not launching Tunnelblick because it is already runnning");
        goto finished;
    }

    NSUserDefaults * defaults = [[[NSUserDefaults alloc]
                                  initWithSuiteName: @"net.tunnelblick.tunnelblick"]
                                 autorelease];

    id prefObj = [defaults objectForKey: @"launchAtNextLogin"];
    if (  [prefObj respondsToSelector: @selector(boolValue)]  ) {
        BOOL launchAtLoginPreference = [prefObj boolValue];
        if (  launchAtLoginPreference  ) {
            launchTunnelblick(@"Launching Tunnelblick because launchAtNextLogin is true");
            goto finished;
        }
    } else {
        LauncherLog(@"'launchAtNextLogin' preference does not respond to 'boolValue'");
    }

    BOOL openvpn_is_running = [processes containsString: @"setenv TUNNELBLICK_CONFIG_FOLDER"];
    if (  openvpn_is_running  ) {
        launchTunnelblick(@"Launching Tunnelblick because OpenVPN is running ('setenv TUNNELBLICK_CONFIG_FOLDER' was detected in processes)");
        goto finished;
    }

    BOOL helper_is_running = [processes containsString: @"tunnelblick-helper"];
    if (  helper_is_running  ) {
        launchTunnelblick(@"Launching Tunnelblick because tunnelblick-helper is running");
        goto finished;
    }

    BOOL openvpnstart_is_running = [processes containsString: @"openvpnstart"];
    if (  openvpnstart_is_running  ) {
        launchTunnelblick(@"Launching Tunnelblick because openvpnstart is running");
        goto finished;
    }

    NSFileManager * fm = [NSFileManager defaultManager];
    if (  ! fm  ) {
        LauncherLog(@"Cannot get default NSFileManager");
        goto finished;
    }

    if (  [fm fileExistsAtPath: L_AS_T_DISABLED_NETWORK_SERVICES_PATH]  ) {
        launchTunnelblick(@"Launching Tunnelblick because network services are disabled");
        goto finished;
    }

    LauncherLog(@"Not launching Tunnelblick because no reasons to launch were found");

finished:

    ShrinkLauncherLogIfItIsTooLong();

    [NSApp terminate: self];
}

@end
