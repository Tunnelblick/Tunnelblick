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

#import "NSTask+TB.h"

#import <errno.h>
#import <math.h>
#import <signal.h>
#import <string.h>
#import <time.h>
#import <unistd.h>

NSErrorDomain const TBTaskLaunchAndWaitErrorDomain = @"TunnelblickErrorDomain";

static uint64_t TBUptimeNanoseconds(void) {

    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

static BOOL TBSleepForTimeInterval(NSTimeInterval                         interval,
                                   NSError        * _Nullable * _Nullable error)
{
    if (   ( ! isfinite(interval))
        || (interval < 0.0)  ) {
        if (  error != NULL  ) {
            *error = [NSError errorWithDomain: TBTaskLaunchAndWaitErrorDomain
                                         code: TBTaskLaunchAndWaitErrorInvalidInternalSleepInterval
                                     userInfo: @{
                NSLocalizedDescriptionKey :
                    @"Sleep interval must be finite and nonnegative."
            }];
        }
        return NO;
    }

    if (  interval == 0.0  ) {
        return YES;
    }

    NSTimeInterval integralSeconds;
    NSTimeInterval fractionalSeconds = modf(interval, &integralSeconds);

    /*
     * Keep tv_nsec in [0, 999999999], despite possible floating-point
     * rounding near the next whole second.
     */
    long nanoseconds = (long)(fractionalSeconds * (NSTimeInterval)NSEC_PER_SEC);

    if (  nanoseconds >= (long)NSEC_PER_SEC  ) {
        integralSeconds += 1.0;
        nanoseconds = 0;
    }

    struct timespec remaining = {
        .tv_sec = (time_t)integralSeconds,
        .tv_nsec = nanoseconds
    };

    while (  nanosleep(&remaining, &remaining) != 0  ) {
        int savedErrno = errno;

        if (  savedErrno != EINTR  ) {
            if (  error != NULL  ) {
                *error = [NSError errorWithDomain: NSPOSIXErrorDomain
                                             code: savedErrno
                                         userInfo: @{
                    NSLocalizedDescriptionKey :
                        [NSString stringWithFormat:
                         @"nanosleep failed: %s",
                         strerror(savedErrno)]
                }];
            }
            return NO;
        }

        /*
         * On EINTR, nanosleep stored the unslept remainder in `remaining`.
         * Loop to complete the caller's requested total sleep duration.
         */
    }

    return YES;
}

static uint64_t TBSecondsToNanoseconds(NSTimeInterval seconds) {

    return (uint64_t)(seconds * (NSTimeInterval)NSEC_PER_SEC);

}

@implementation NSTask(TB)

-(BOOL) tbLaunchAndWaitUntilDoneWithTerminationTimeout: (NSTimeInterval)                   terminationTimeout
                                           killTimeout: (NSTimeInterval)                   killTimeout
                                       pollingInterval: (NSTimeInterval)                   pollingInterval
                                                 error:  (NSError * _Nullable * _Nullable) error {

    uint64_t startNS;
    uint64_t elapsedNS;

    BOOL     requestedTerm = NO;
    BOOL     sentKill      = NO;
    int      processID;
    uint64_t terminationTimeoutNS;
    uint64_t killTimeoutNS;

    if (   ( ! isfinite(killTimeout))
        || ( ! isfinite(terminationTimeout))
        || ( ! isfinite(pollingInterval))  ) {
        if (  error != NULL  ) {
            *error = [NSError errorWithDomain: TBTaskLaunchAndWaitErrorDomain
                                         code: TBTaskLaunchAndWaitErrorNonFiniteInterval
                                     userInfo:  @{
                NSLocalizedDescriptionKey :
                    @"killTimeout, terminationTimeout, and pollingInterval must be finite."
            }];
        }
        return NO;
    }

    if (  killTimeout < 0.0  ) {
        killTimeout = 0.0;
    } else if (  killTimeout > TB_TASK_LAUNCH_AND_WAIT_MAX_SIGKILL_TIMEOUT  )  {
        killTimeout = TB_TASK_LAUNCH_AND_WAIT_MAX_SIGKILL_TIMEOUT;
    }

    if (  terminationTimeout < 0.0  ) {
        terminationTimeout = 0.0;
    } else if (  terminationTimeout > TB_TASK_LAUNCH_AND_WAIT_MAX_TERMINATION_TIMEOUT  ) {
        terminationTimeout = TB_TASK_LAUNCH_AND_WAIT_MAX_TERMINATION_TIMEOUT;
    }

    if (  pollingInterval <= 0.0  ) {
        pollingInterval = TB_TASK_LAUNCH_AND_WAIT_DEFAULT_POLLING_INTERVAL;
    } else if (pollingInterval > TB_TASK_LAUNCH_AND_WAIT_MAX_POLLING_INTERVAL) {
        pollingInterval = TB_TASK_LAUNCH_AND_WAIT_MAX_POLLING_INTERVAL;
    }

    if (   (terminationTimeout > 0.0)
        && (killTimeout > 0.0)
        && (killTimeout <= terminationTimeout)  ) {
        if (  error != NULL  ) {
            *error = [NSError errorWithDomain: TBTaskLaunchAndWaitErrorDomain
                                         code: TBTaskLaunchAndWaitErrorKillBeforeTermination
                                     userInfo:  @{
                NSLocalizedDescriptionKey :
                    @"killTimeout is equal to or less than terminationTimeout."
            }];
        }
        return NO;
    }

    terminationTimeoutNS = (  (terminationTimeout > 0.0)
                            ? TBSecondsToNanoseconds(terminationTimeout)
                            : 0);

    killTimeoutNS = (  (killTimeout > 0.0)
                     ? TBSecondsToNanoseconds(killTimeout)
                     : 0);

    if (  error != NULL  ) {
        *error = nil;
    }

    if (  ! [self launchAndReturnError: error]  ) {
        return NO;
    }

    startNS = TBUptimeNanoseconds();

    while (  self.isRunning  ) {

        elapsedNS = TBUptimeNanoseconds() - startNS;

        if (   (terminationTimeoutNS != 0)
            && (elapsedNS >= terminationTimeoutNS)
            && self.isRunning  ) {
            terminationTimeoutNS = 0;
            requestedTerm = YES;
            [self terminate];
        }

        if (   (killTimeoutNS != 0)
            && (elapsedNS >= killTimeoutNS)
            && self.isRunning  ) {

            processID = [self processIdentifier];
            if (  processID < 1  ) {
                if (  error != NULL  ) {
                    *error = [NSError errorWithDomain: TBTaskLaunchAndWaitErrorDomain
                                                 code: TBTaskLaunchAndWaitErrorInvalidProcessIdentifierCannotBeKilled
                                             userInfo:  @{
                        NSLocalizedDescriptionKey :
                            @"Task does not have a valid process identifier so it cannot be killed."
                    }];
                }
                return NO;
            }

            // Minimize the time between checking if the task is still running and killing it to minimize the TOCTOU problem
            if (  self.isRunning  ) {
                killTimeoutNS = 0;
                int result = kill(processID, SIGKILL);
                if (  result == 0  ) {
                    sentKill = YES;
                } else {
                    int savedErrno = errno;
                    if (  savedErrno != ESRCH  ) {
                        if (  error != NULL  ) {
                            *error = [NSError errorWithDomain: NSPOSIXErrorDomain
                                                         code: savedErrno
                                                     userInfo:  @{
                                NSLocalizedDescriptionKey :
                                    [NSString stringWithFormat:
                                     @"kill(%d) returned error %d ('%s')", processID, savedErrno, strerror(savedErrno)]
                            }];
                        }
                        return NO;
                    } else {
                        if (  self.isRunning  ) {
                            if (  error != NULL  ) {
                                *error = [NSError errorWithDomain: TBTaskLaunchAndWaitErrorDomain
                                                             code: TBTaskLaunchAndWaitErrorKillFailedButTaskIsRunning
                                                         userInfo:  @{
                                    NSLocalizedDescriptionKey :
                                        [NSString stringWithFormat:
                                         @"Task is still running but kill(%d) returned error %d ('%s')",
                                         processID, savedErrno, strerror(savedErrno)]
                                }];
                            }
                            return NO;
                        }
                        
                        // ESRCH and the task is no longer running: fall through.
                    }
                }
            }
        }

        if (  self.isRunning  ) {
            if (  ! TBSleepForTimeInterval(pollingInterval, error)  ) {
                return NO;
            }
        }
    }

    NSTaskTerminationReason reason = self.terminationReason;
    switch (  reason  ) {

        case NSTaskTerminationReasonExit:
            return YES;

        case NSTaskTerminationReasonUncaughtSignal:
            if (  sentKill  ) {
                if (  error != NULL  ) {
                    *error = [NSError errorWithDomain: TBTaskLaunchAndWaitErrorDomain
                                                 code: TBTaskLaunchAndWaitErrorSentSIGKILL
                                             userInfo:  @{
                        NSLocalizedDescriptionKey :
                            @"Task terminated due to an uncaught signal after this method successfully sent SIGKILL to its PID."
                    }];
                }
            } else if (  requestedTerm  ) {
                if (  error != NULL  ) {
                    *error = [NSError errorWithDomain: TBTaskLaunchAndWaitErrorDomain
                                                 code: TBTaskLaunchAndWaitErrorExitedAfterTerminationRequest
                                             userInfo:  @{
                        NSLocalizedDescriptionKey :
                            @"Task terminated due to an uncaught signal after this method requested termination."
                    }];
                }
            } else {
                if (  error != NULL  ) {
                    *error = [NSError errorWithDomain: TBTaskLaunchAndWaitErrorDomain
                                                 code: TBTaskLaunchAndWaitErrorExternalSignal
                                             userInfo:  @{
                        NSLocalizedDescriptionKey :
                            @"Task terminated due to an uncaught signal not sent by this method."
                    }];
                }
            }
            return NO;

        default:
            if (  error != NULL  ) {
                *error = [NSError errorWithDomain: TBTaskLaunchAndWaitErrorDomain
                                             code: TBTaskLaunchAndWaitErrorUnknownTerminationReason
                                         userInfo:  @{
                    NSLocalizedDescriptionKey :
                        [NSString stringWithFormat:
                         @"Task terminated with unknown NSTaskTerminationReason %ld", (long)reason]
                }];
            }
            return NO;
    }
}

@end
