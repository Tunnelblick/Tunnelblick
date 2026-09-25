/*
 * Copyright (c) 2026 Jonathan K. Bullard. All rights reserved.
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
 *  distribution); if not, see http://www.gnu.org/licenses/.
 */

//*************************************************************************************************

#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN

// The following two timeouts should not be very large to avoid overflows
#define TB_TASK_LAUNCH_AND_WAIT_MAX_TERMINATION_TIMEOUT 600.0
#define TB_TASK_LAUNCH_AND_WAIT_MAX_SIGKILL_TIMEOUT     600.0

#define TB_TASK_LAUNCH_AND_WAIT_MAX_POLLING_INTERVAL     10.0
#define TB_TASK_LAUNCH_AND_WAIT_DEFAULT_POLLING_INTERVAL  1.0

FOUNDATION_EXPORT NSErrorDomain const TBTaskLaunchAndWaitErrorDomain;

typedef NS_ENUM(NSInteger, TBTaskLaunchAndWaitErrorCode) {
    TBTaskLaunchAndWaitErrorNonFiniteInterval                       = 1000,
    TBTaskLaunchAndWaitErrorKillBeforeTermination                   = 1001,
    TBTaskLaunchAndWaitErrorInvalidProcessIdentifierCannotBeKilled  = 1002,
    TBTaskLaunchAndWaitErrorSentSIGKILL                             = 1003,
    TBTaskLaunchAndWaitErrorKillFailedButTaskIsRunning              = 1004,
    TBTaskLaunchAndWaitErrorExitedAfterTerminationRequest           = 1005,
    TBTaskLaunchAndWaitErrorExternalSignal                          = 1006,
    TBTaskLaunchAndWaitErrorUnknownTerminationReason                = 1007,
    TBTaskLaunchAndWaitErrorInvalidInternalSleepInterval            = 1008,
};

@interface NSTask(TB)

// Launches task.
// If terminationTimeout is greater than 0.0, a request will be made to terminate the task after terminationTimeout seconds.
// If killTimeout is greater than 0.0, SIGKILL will be sent to the task after killTimeout seconds.
// Polls the task status every pollingInterval seconds.
//
// Returns YES and sets *error to nil if error is not NULL only if the launch succeeded and then
//             terminated with NSTaskTerminationReasonExit, regardless of the task's terminationStatus.
//
// Returns NO otherwise, with an NSError * stored in *error if error is not NULL.
//
// NOTES:
//      1. terminationTimeout, killTimeout, and pollingInterval must be finite.
//      2. A terminationTimeout less than or equal to 0.0 disables termination requests.
//      3. If a terminationTimeout is greater than TB_TASK_LAUNCH_AND_WAIT_MAX_TERMINATION_TIMEOUT, it will be limited to that value.
//      4. A killTimeout less than or equal to 0.0 disables SIGKILL escalation.
//      5. If a killTimeout is greater than TB_TASK_LAUNCH_AND_WAIT_MAX_SIGKILL_TIMEOUT, it will be limited to that value.
//      6. If both terminationTimeout and killTimeout are greater than 0.0, killTimeout must be greater than terminationTimeout;
//         otherwise the method returns NO, and, if error is not NULL, with *error set to an NSError in the TBTaskLaunchAndWaitErrorDomain
//         with a code of TBTaskLaunchAndWaitErrorKillBeforeTermination.
//      7. If pollingInterval is less than or equal to 0.0, it is replaced with TB_TASK_LAUNCH_AND_WAIT_DEFAULT_POLLING_INTERVAL.
//      8. If pollingInterval exceeds TB_TASK_LAUNCH_AND_WAIT_MAX_POLLING_INTERVAL, it is limited to that value.
//      9. Timeout accounting uses CLOCK_UPTIME_RAW, so system sleep does not count toward terminationTimeout or killTimeout
//         and the method may return much later than the timeouts if the system sleeps for a long time.
//     10. Termination will be attempted no earlier than terminationTimeout seconds after launch, at the first subsequent polling check.
//     11. SIGKILL will be attempted, if possible, no earlier than killTimeout seconds after launch, at the first subsequent polling check.
//     12. SIGKILL is sent directly to the NSTask process identifier. Descendant processes are not individually signaled by this
//         call and may outlive the task.
//     13. If the task does not terminate by the time it should be killed and no process identifier is available,
//         NO will be returned, and, if error is not NULL, with *error set to an NSError in the TBTaskLaunchAndWaitErrorDomain
//         with a code of TBTaskLaunchAndWaitErrorInvalidProcessIdentifierCannotBeKilled. This means that the task may still be running.
//     14. If an attempted SIGKILL fails other than with ESRCH, NO will be returned and, if error is not NULL, with *error set
//         to an NSError in the NSPOSIXErrorDomain. The NSError code is the errno value returned by kill().
//     15. If an attempted SIGKILL fails with ESRCH and the task is still running, NO will be returned, and, if error is not NULL,
//         with *error set to an NSError in the TBTaskLaunchAndWaitErrorDomain with a code of TBTaskLaunchAndWaitErrorKillFailedButTaskIsRunning.
//     16. Timeout actions are checked once per polling interval and may occur later than their
//         configured deadlines by approximately the polling interval plus scheduler latency.

-(BOOL) tbLaunchAndWaitUntilDoneWithTerminationTimeout: (NSTimeInterval)                  terminationTimeout
                                           killTimeout: (NSTimeInterval)                  killTimeout
                                       pollingInterval: (NSTimeInterval)                  pollingInterval
                                                 error: (NSError * _Nullable * _Nullable) error;
@end

NS_ASSUME_NONNULL_END
