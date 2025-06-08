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


// This program takes three arguments:
//
//   1. The uid of the user who initiated the update.
//      (The updated program will be launched with that uid.)
//
//   2. The gid of the user who initiated the update.
//      (The updated program will be launched with that uid.)
//
//   3. The process ID of the Tunnelblick process which started the update.
//      (All "Tunnelblick" processes except that one are terminated by this program;
//       that process quits after starting the update, so it does not need to be
//       terminated, and should not be terminated.)


// Tunnelblick is updated in three phases:
//
// PHASE 3 IS DONE BY THIS PROGRAM, TunnelblickUpdateHelper, which was copied into
//         Library/Application Support/Tunnelblick by PHASE 2. It:
//
//  * Waits until there is no process named "Tunnelblick" running
//    (terminating any Tunnelblick launched by any other user);
//  * Moves /Applications/Tunnelblick.app to L_AS_/Tunnelblick-old.app
//    (replacing any existing Tunnelblick-old.app);
//  * Renames /Library/Application Support/Tunnelblick/Tunnelblick-new.app to Tunnelblick.app
//  * Copies /Library/Application Support/Tunnelblick/Tunnelblick.app to /Applications;
//  * If necessary, runs THAT .app's installer as root to update tunnelblickd.plist
//    so Tunnelblick is ready to be launched;
//  * Launches the updated /Applications/Tunnelblick.app;
//  * Exits.
//
// PHASE 1 IS DONE BY TUNNELBLICK, primarily in the TBUpdater class. It:
//
//  * Interprets all user interaction;
//  * Obtains update info from tunnelblick.net;
//  * Downloads a .zip of an update. Depending on preferences, the .zip may be downloaded
//    immediately when available, or later, when a user or admin authorizes the update.;
//  * Gets user or admin authorization to update;
//  * Invokes PHASE 2 using installer or openvpnstart/tunnelblickd.
//
// PHASE 2 IS DONE BY THE updateTunnelblick() ROUTINE in TBUpdaterShared.
//
// The routine must run as root, either in installer or in tunnelblick-helper. It:
//
//  * Copies the .zip to /Library/Application Support/Tunnelblick/Tunnelblick.zip so it is owned by root:wheel and is secure;
//  * Verifies the signature of the .zip;
//  * Expands the .zip into /Library/Application Support/Tunnelblick/Tunnelblick.app;
//    so that the .app and everything within it is owned by root:wheel;
//  * Verifies that the .app has reasonable ownership and permissions
//    (i.e. everything owned by root:wheel, nothing with "other" write;
//  * Verifies that the .app is signed properly;
//  * Verifies that the .app is the specified version;
//  * Renames it to L_AS_T/Tunnelblick-new.app;
//  * Copies THIS app's TunnelblickUpdateHelper program into /Library/Application Support/Tunnelblick;
//  * Starts it as root;
//  * Returns indicating success (TRUE) or failure (FALSE), having output
//    appropriate error messages through appendLog().


#import <Foundation/Foundation.h>

#import "defines.h"

#import <sys/sysctl.h>

#import "NSDate+TB.h"
#import "NSFileManager+TB.h"
#import "sharedRoutines.h"


NSFileManager * gFileMgr;    // [NSFileManager defaultManager]
NSString      * gDeployPath; // Path to Tunnelblick.app/Contents/Resources/Deploy

static FILE   * gLogFile;    // FILE for log


// Forward references:
static void errorExit(void);


void appendLog(NSString * s) {

    if (  gLogFile != NULL  ) {
        NSString * now = [[NSDate date] tunnelblickUserLogRepresentation];
        fprintf(gLogFile, "%s: %s\n", [now UTF8String], [s UTF8String]);
    }

    NSLog(@"%@", s);
}

static void openLog(void) {

    if (  [gFileMgr fileExistsAtPath: TUNNELBLICK_UPDATE_HELPER_LOG_PATH]  ) {
        [gFileMgr tbRemovePathIfItExists: TUNNELBLICK_UPDATE_HELPER_OLD_LOG_PATH];
        [gFileMgr tbMovePath: TUNNELBLICK_UPDATE_HELPER_LOG_PATH toPath: TUNNELBLICK_UPDATE_HELPER_OLD_LOG_PATH handler: nil];
    }

    const char * path = [TUNNELBLICK_UPDATE_HELPER_LOG_PATH fileSystemRepresentation];

    gLogFile = fopen(path, "w");

    if (  gLogFile == NULL  ) {
        appendLog([NSString stringWithFormat: @"Unable to open '%@'", TUNNELBLICK_UPDATE_HELPER_LOG_PATH]);
        errorExit();
    }
}

static void errorExit(void) {

    appendLog([NSString stringWithFormat: @"errorExit(): Stack trace: %@", [NSThread callStackSymbols]]);
    exit(EXIT_FAILURE);
}

static pid_t processIDWithName(NSString * name) {

    // Returns 0 if no  process with that name, otherwise returns the process ID for the first process with the name

    const char * nameC = [name UTF8String];

    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
    size_t length;
    unsigned long count, i;

    // KERN_PROC_ALL has 3 elements, all others have 4
    unsigned level = 3;

    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) {
        appendLog([NSString stringWithFormat: @"processIDWithName: sysctl #1 returned error %d: '%s'", errno, strerror(errno)]);
        errorExit();
    }
    // Allocate memory for info structure:
    if (!(info = NSZoneMalloc(NULL, length))) {
        appendLog([NSString stringWithFormat: @"processIDWithName: NSZoneMalloc returned error %d: '%s'", errno, strerror(errno)]);
        errorExit();
    }
    if (sysctl(mib, level, info, &length, NULL, 0) < 0) {
        NSZoneFree(NULL, info);
        appendLog([NSString stringWithFormat: @"processIDWithName: sysctl #2 returned error %d: '%s'", errno, strerror(errno)]);
        errorExit();
    }

    pid_t pid = 0;

    count = length / sizeof(struct kinfo_proc);
    for (i = 0; i < count; i++) {
        char* command = info[i].kp_proc.p_comm;
        if (strncmp(nameC, command, MAXCOMLEN)==0) {
            pid = info[i].kp_proc.p_pid;
            if ( pid != 0  ) {
                break;
            }
        }
    }

    NSZoneFree(NULL, info);

    return pid;
}

static uid_t waitUntilNoProcessWithProcessID(pid_t pid, NSString * name, BOOL sendSIGTERM) {

    // If sendSIGTERM, sends SIGTERM to process with ID pid
    // Waits for process with ID to terminate;
    // Returns process ID of the next process with the specified name (or 0 if no such process)

    if (  pid != 0  ) {

        if (  sendSIGTERM  ) {
            kill(pid, SIGTERM);
            appendLog([NSString stringWithFormat: @"Sent SIGTERM to process %u ('%@')", pid, name]);
        }

        appendLog([NSString stringWithFormat: @"Waiting for process %u ('%@') to finish", pid, name]);

        pid_t nextPid = 0;
        while (  pid != 0  ) {
            usleep(2 * ONE_TENTH_OF_A_SECOND_IN_MICROSECONDS);
            nextPid = processIDWithName(name);
            if (  pid != nextPid  ) {
                break;
            }
        }

        appendLog([NSString stringWithFormat: @"process %u ('%@') has finished", pid, name]);

        return nextPid;
    }

    appendLog([NSString stringWithFormat: @"process %u ('%@') is not running", pid, name]);
    return 0;
}

static void waitUntilNoProcessWithName(NSString * name) {

    // For each process with the specified name, sends SIGTERM to the process and waits for
    // the process to exit.
    //
    // (For simplicity does one process at a time because we assume a small number of processes.
    //  If that changes, it would be faster to get a list of the processes, send SIGTERM to each
    //  of them, then wait until all of them have exited.)

    pid_t pid = processIDWithName(name);

    if (  pid == 0  ) {
        appendLog([NSString stringWithFormat: @"No process named '%@'", name]);
    } else {
        while (  pid != 0  ) {
            pid = waitUntilNoProcessWithProcessID(pid, name, YES);
        }
        appendLog([NSString stringWithFormat: @"All processes named '%@' have finished", name]);
    }
}

static void moveAppToOldAndNewToL_AS_T_App(void) {

    // Move /Applications/Tunnelblick.app to L_AS_T/Tunnelblick-old.app
    if (  [gFileMgr tbForceMovePath: APPLICATIONS_TB_APP toPath: L_AS_T_TB_OLD]  ){
        appendLog([NSString stringWithFormat: @"Moved %@ to %@", APPLICATIONS_TB_APP, L_AS_T_TB_OLD]);
    } else {
        appendLog(@"Failed to update Tunnelblick");
        errorExit();
    }

    // Move .new to .app
    if (  [gFileMgr tbMovePath: L_AS_T_TB_NEW toPath: L_AS_T_TB_APP handler: nil]  ){
        appendLog([NSString stringWithFormat: @"Moved %@ to %@", L_AS_T_TB_NEW, L_AS_T_TB_APP]);
    } else {
        // Try to get Tunnelblick.app back
        if (  [gFileMgr tbForceMovePath: L_AS_T_TB_OLD toPath: APPLICATIONS_TB_APP]  ){
            appendLog([NSString stringWithFormat: @"Restored %@", APPLICATIONS_TB_APP]);
        } else {
            appendLog([NSString stringWithFormat: @"Could not restore %@ to %@", L_AS_T_TB_OLD, APPLICATIONS_TB_APP]);
        }

        appendLog(@"Failed to update Tunnelblick");
        errorExit();
    }
}

static void copyL_AS_T_AppToApplications(void) {

    if (  ! [gFileMgr tbRemovePathIfItExists: APPLICATIONS_TB_APP]  ) {
        errorExit();
    }

    // Copy app to /Applicatoins
    if (  [gFileMgr tbCopyItemAtPath: L_AS_T_TB_APP toBeOwnedByRootWheelAtPath: APPLICATIONS_TB_APP]  ) {
        appendLog([NSString stringWithFormat: @"Copied %@ to %@", L_AS_T_TB_APP, APPLICATIONS_TB_APP]);
    } else {
        errorExit();
    }
}

static void updateTunnelblickdPlist(void) {

    // Update and reload the tunnelblickd .plist.

    NSString * bitMask = [NSString stringWithFormat: @"%d", INSTALLER_REPLACE_DAEMON];

    NSArray * arguments = @[bitMask];

    NSString * stdoutString = @"";
    NSString * stderrString = @"";
    OSStatus status = runTool(@"/Applications/Tunnelblick.app/Contents/Resources/installer", arguments, &stdoutString, &stderrString);

    NSString * message = @"";
    if (  stdoutString.length != 0  ) {
        message = [NSString stringWithFormat: @"stdout = '\n%@'\n", stdoutString];
    }
    if (  stderrString.length != 0  ) {
        message = [NSString stringWithFormat: @"%@stderr = '\n%@'", message, stderrString];
    }
    if (  message.length != 0  ) {
        message = [NSString stringWithFormat: @"status from installer(INSTALLER_REPLACE_DAEMON) = %d; %@", status, message];
    } else if (  status != 0  ) {
        message = [NSString stringWithFormat: @"status from installer(INSTALLER_REPLACE_DAEMON) = %d", status];
    }

    if (  message.length != 0  ) {
        appendLog(message);
    } else {
        appendLog(@"Updated tunnelblickd .plist and reloaded it");
    }

    if (  status != 0  ) {
        // Try to get Tunnelblick.app back
        if (  ! [gFileMgr tbRemoveFileAtPath: APPLICATIONS_TB_APP handler: nil]  ) {
            appendLog(@"Failed to update tunnelblickd.plist and could not delete /Applications/Tunnelblick.app before restoring the old version");
            errorExit();
        }
        if (  ! [gFileMgr tbForceRenamePath: @"/Applications/Tunnelblick-old.app" toPath: APPLICATIONS_TB_APP]  ) {
            appendLog(@"Failed to update tunnelblickd.plist and could not restore /Applications/Tunnelblick.app");
            errorExit();
        }
        appendLog(@"Failed to update tunnelblickd.plistinstaller failed but restored the original /Applications/Tunnelblick.app");
        // OK to return because we've restored the original app, so the original app will be relaunched.
    }
}

static void launchUpdatedProgram(uid_t uid, gid_t gid) {

    appendLog([NSString stringWithFormat:
               @"Launching the updated Tunnelblick as %u:%u...",
               uid, gid]);

    // Drop privileges to run Tunnelblick as the user.
    // NOTE: We do not need to restore root privileges for the rest of the execution of this program.

    if (  setgid(gid)  ) {
        appendLog([NSString stringWithFormat: @"launchUpdatedProgram:Failed to setgid(%u); getuid() = %u; geteuid() = %u; getgid() = %u; getegid() = %u; uid = %u; gid = %u",
                   gid, getuid(), geteuid(), getgid(), getegid(), uid, gid]);
        errorExit();
    }
    if (  setuid(uid)  ) {
        appendLog([NSString stringWithFormat: @"launchUpdatedProgram: Failed to setuid(%u); getuid() = %u; geteuid() = %u; getgid() = %u; getegid() = %u; uid = %u; gid = %u",
                   uid, getuid(), geteuid(), getgid(), getegid(), uid, gid]);
        errorExit();
    }
    if (  setegid(gid)  ) {
        appendLog([NSString stringWithFormat: @"launchUpdatedProgram:Failed to setegid(%u); getuid() = %u; geteuid() = %u; getgid() = %u; getegid() = %u; uid = %u; gid = %u",
                   gid, getuid(), geteuid(), getgid(), getegid(), uid, gid]);
        errorExit();
    }
    if (  seteuid(uid)  ) {
        appendLog([NSString stringWithFormat: @"launchUpdatedProgram: Failed to seteuid(%u); getuid() = %u; geteuid() = %u; getgid() = %u; getegid() = %u; uid = %u; gid = %u",
                   uid, getuid(), geteuid(), getgid(), getegid(), uid, gid]);
        errorExit();
    }

    // From here on, can't log to the file because we're not root

    gLogFile = NULL;

    // Launch the updated Tunnelblick
    NSTask * task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath: TOOL_PATH_FOR_OPEN];
    [task setArguments:  @[@"-a",
                           APPLICATIONS_TB_APP]];
    [task setCurrentDirectoryPath: @"/private/tmp"];
    [task setEnvironment: getSafeEnvironment(nil, 0, nil)];
    [task launchAndReturnError: nil];
}

int main(int argc, const char * argv[]) {

    @autoreleasepool {

        gFileMgr = [NSFileManager defaultManager];

        openLog();

        // Process arguments to get uid, gid, and process id of Tunnelblick process that started this program
        if (  argc != 4  ) {
            appendLog([NSString stringWithFormat: @"Given %d arguments; need 4", argc]);
            errorExit();
        }
        uid_t uid = (unsigned) strtol(argv[1], NULL, 0);
        gid_t gid = (unsigned) strtol(argv[2], NULL, 0);
        pid_t pid = (unsigned) strtol(argv[3], NULL, 0);

        appendLog([NSString stringWithFormat: @"TunnelblickUpdateHelper entered as %d:%d (effective %d:%d) with arguments: uid = %u; gid = %u; Tunnelblick pid = %u",
                   getuid(), getgid(), geteuid(), getegid(), uid, gid, pid]);

        if (   (uid == 0)
            || (gid == 0)
            || (pid == 0)) {
            appendLog(@"No argument may be 0");
            errorExit();
        }

        // Wait for the Tunnelblick process which started the update process to quit.
        // (Don't SIGTERM it because we want it to complete everything before we update.)
        waitUntilNoProcessWithProcessID(pid, @"Tunnelblick", NO);

        // SIGTERM any other Tunnelblick proceses (e.g. other logged-in users) and
        // wait for them to finish.
        waitUntilNoProcessWithName(@"Tunnelblick");

        // SIGTERM the tunnelblickd proceses and wait for it to finish.
        // (tunnelblickd keeps running for 30 seconds after doing something, waiting for more to do,
        //  so we SIGTERM it to cut that delay.)
        waitUntilNoProcessWithName(@"tunnelblickd");

        if (  ! dealWithDotOldAndHyphenOldApp()  ) {
            errorExit();
        }

        if (  ! removeOldDotMipFile()  ) {
            errorExit();
        }

        moveAppToOldAndNewToL_AS_T_App();

        copyL_AS_T_AppToApplications();

        updateTunnelblickdPlist();

        launchUpdatedProgram(uid, gid);

        return 0;
    }
}
