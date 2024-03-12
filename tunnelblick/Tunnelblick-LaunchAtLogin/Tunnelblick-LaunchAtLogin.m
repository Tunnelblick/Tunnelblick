/*
 * Copyright 2023 by Jonathan K. Bullard. All rights reserved.

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

// Launch Tunnelblick if:
//    A. Tunnelblick has disabled network access; or
//    B. The 'launchAtNextLogin' preference is "1"; or
//    C. OpenVPN is running or is about to be run.
//
// The 'launchAtNextLogin' preference is set to "1" when you launch Tunnelblick if the 'doNotLaunchOnLogin' preference is not "1".
// The 'launchAtNextLogin' preference is set to "0" when you quit Tunnelblick and you are not logging out.


#import <Foundation/Foundation.h>

#import "../defines.h"
#import "../NSFileManager+TB.h"
#import "../sharedRoutines.h"

void launchTunnelblick(void) {

    startTool(TOOL_PATH_FOR_OPEN, @[@"/Applications/Tunnelblick.app"]);
}

NSString * GetProcesses(void) {
    // Returns a string with the output from the 'ps -f -u 0' command, which lists all root processes and
    // the command line arguments each process was started with.

    NSString * stdOutString = @"";
    NSString * stdErrString = @"";

    OSStatus status = runTool(TOOL_PATH_FOR_PS, @[@"-f", @"-u", @"0"], &stdOutString, &stdErrString);
    if (  status != EXIT_SUCCESS ) {
        NSLog(@"Nonzero status %d from 'ps -f -u 0'; stderr = '%@'", status, stdErrString);
    } else if (  [stdErrString length] != 0 ) {
        NSLog(@"status from 'ps -f -u 0' was 0, but stderr '%@'", stdErrString);
    }

    if (  [stdOutString length] == 0 ) {
        NSLog(@"Empty stdout from 'ps -f -u 0");
    }

    return stdOutString;
}


int main(int argc, const char * argv[]) {
    @autoreleasepool {

        (void)argc;
        (void)argv;

        if (  [[NSFileManager defaultManager] fileExistsAtPath: L_AS_T_DISABLED_NETWORK_SERVICES_PATH]  ) {
           launchTunnelblick();
        } else {

            NSUserDefaults * defaults = [[[NSUserDefaults alloc] initWithSuiteName: @"net.tunnelblick.tunnelblick"] autorelease];
            BOOL launchAtLoginPreference = [[defaults objectForKey: @"launchAtNextLogin"] boolValue];
            if (  launchAtLoginPreference  ) {
                launchTunnelblick();
            } else {

                NSString * processes = GetProcesses();

                BOOL openvpn_is_running = [processes containsString: @"setenv TUNNELBLICK_CONFIG_FOLDER"];
                if (  openvpn_is_running  ) {
                    launchTunnelblick();
                } else {

                    BOOL helper_is_running = [processes containsString: @"tunnelblick-helper"];
                    if (  helper_is_running  ) {
                        launchTunnelblick();
                    } else {

                        BOOL openvpnstart_is_running = [processes containsString: @"openvpnstart"];
                        if (  openvpnstart_is_running  ) {
                            launchTunnelblick();
                        }
                    }
                }
            }
        }

    }

    return 0;
}

// The following routine is referenced in SharedRoutines.m, but in a routine not used by this program
void appendLog(NSString * msg)
{
    NSLog(@"%@", msg);
}

// The following variable is referenced in SharedRoutines.m, but in a routine not used by this program

NSString       * gDeployPath = nil;
