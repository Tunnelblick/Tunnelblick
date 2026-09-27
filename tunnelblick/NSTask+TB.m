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


NSErrorDomain const TBTaskLaunchAndWaitErrorDomain = @"TunnelblickErrorDomain";

static uint64_t TBUptimeNanoseconds(void) {

    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

static BOOL TBSleepForTimeInterval(NSTimeInterval                         interval,
                                   NSError        * _Nullable * _Nullable error) {

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


BOOL TBDrainPipe(NSPipe *pipe, NSMutableData *data, BOOL *eof, NSError **error) {

    /*
     * Reads at most 16 KiB from pipe's read end and appends whatever is available
     * immediately to data.
     *
     * Return values:
     *   YES: Data was appended, no data is presently available, or EOF was reached.
     *   NO:  An error occurred and, if error != NULL, *error describes it.
     *
     * EOF behavior:
     *   - On the first read() that returns 0, sets *eof = YES and returns YES.
     *   - A later invocation with *eof already YES returns NO.
     *
     * Preconditions:
     *   - pipe, data, and eof must be non-NULL.
     *   - pipe must have an open readable fileHandleForReading.
     *
     * Important:
     *   This function changes the read descriptor's status flags by adding
     *   O_NONBLOCK, and leaves that flag enabled. File status flags belong to the
     *   underlying open file description, so other users of the same descriptor
     *   (or duplicated descriptors) observe the nonblocking setting as well.
     */

    enum { kDrainPipeMaximumBytes = 16 * 1024 };

    if (error != NULL) {
        *error = nil;
    }

#define DRAIN_PIPE_FAIL(_code_, _description_, _underlyingError_)   \
do {                                                                \
if (error != NULL) {                                                \
NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];   \
if ((_description_) != nil) {                                       \
[userInfo setObject:(_description_)                                 \
forKey:NSLocalizedDescriptionKey];                                  \
}                                                                   \
if ((_underlyingError_) != nil) {                                   \
[userInfo setObject:(_underlyingError_)                             \
forKey:NSUnderlyingErrorKey];                                       \
}                                                                   \
*error = [NSError errorWithDomain:TBTaskLaunchAndWaitErrorDomain    \
code:(_code_)                                                       \
userInfo:userInfo];                                                 \
}                                                                   \
return NO;                                                          \
} while (0)

    if (pipe == nil) {
        DRAIN_PIPE_FAIL(TBTaskLaunchAndWaitErrorInvalidArgument,
                        @"The pipe argument must not be nil.",
                        nil);
    }

    if (data == nil) {
        DRAIN_PIPE_FAIL(TBTaskLaunchAndWaitErrorInvalidArgument,
                        @"The data argument must not be nil.",
                        nil);
    }

    if (eof == NULL) {
        DRAIN_PIPE_FAIL(TBTaskLaunchAndWaitErrorInvalidArgument,
                        @"The eof argument must not be NULL.",
                        nil);
    }

    /*
     * eof is caller-maintained state. It distinguishes:
     *
     *   read() == 0 for the first time  -> successful EOF notification.
     *   Later drainPipe() invocation    -> programmer/protocol error.
     */
    if (*eof) {
        DRAIN_PIPE_FAIL(TBTaskLaunchAndWaitErrorAlreadyAtEOF,
                        @"drainPipe was called after this pipe had already reached EOF.",
                        nil);
    }

    NSFileHandle *readHandle = [pipe fileHandleForReading];
    if (readHandle == nil) {
        DRAIN_PIPE_FAIL(TBTaskLaunchAndWaitErrorInvalidFileDescriptor,
                        @"The pipe does not provide a reading file handle.",
                        nil);
    }

    /*
     * NSFileHandle's -fileDescriptor can raise an Objective-C exception if
     * its handle is closed. Avoid trying to recover from arbitrary exceptions;
     * this catches only the descriptor lookup so this C-style API can report
     * that specific failure via NSError.
     */
    int fd = -1;
    @try {
        fd = [readHandle fileDescriptor];
    }
    @catch (NSException *exception) {
        NSDictionary *userInfo =
        [NSDictionary dictionaryWithObjectsAndKeys:
         @"The pipe's reading file handle is closed or invalid.",
         NSLocalizedDescriptionKey,
         [exception name], @"NSExceptionName",
         [exception reason] ?: @"", @"NSExceptionReason",
         nil];

        if (error != NULL) {
            *error = [NSError errorWithDomain:TBTaskLaunchAndWaitErrorDomain
                                         code:TBTaskLaunchAndWaitErrorInvalidFileDescriptor
                                     userInfo:userInfo];
        }
        return NO;
    }

    if (fd < 0) {
        DRAIN_PIPE_FAIL(TBTaskLaunchAndWaitErrorInvalidFileDescriptor,
                        @"The pipe has an invalid reading file descriptor.",
                        nil);
    }

    /*
     * read() on a normal pipe blocks if it is empty while a writer is still
     * open. Set O_NONBLOCK once; F_GETFL/F_SETFL preserve all existing file
     * status flags.
     */
    int flags;
    do {
        flags = fcntl(fd, F_GETFL);
    } while (flags == -1 && errno == EINTR);

    if (flags == -1) {
        int savedErrno = errno;
        NSError *underlyingError =
        [NSError errorWithDomain:NSPOSIXErrorDomain
                            code:savedErrno
                        userInfo:nil];

        DRAIN_PIPE_FAIL(TBTaskLaunchAndWaitErrorGetFlagsFailed,
                        @"Could not retrieve the pipe read descriptor's status flags.",
                        underlyingError);
    }

    if ((flags & O_NONBLOCK) == 0) {
        int setFlagsResult;
        do {
            setFlagsResult = fcntl(fd, F_SETFL, flags | O_NONBLOCK);
        } while (setFlagsResult == -1 && errno == EINTR);

        if (setFlagsResult == -1) {
            int savedErrno = errno;
            NSError *underlyingError =
            [NSError errorWithDomain:NSPOSIXErrorDomain
                                code:savedErrno
                            userInfo:nil];

            DRAIN_PIPE_FAIL(TBTaskLaunchAndWaitErrorSetNonBlockingFailed,
                            @"Could not make the pipe read descriptor nonblocking.",
                            underlyingError);
        }
    }

    uint8_t buffer[kDrainPipeMaximumBytes];
    ssize_t byteCount;

    /*
     * Retry only if no bytes were transferred and read was interrupted.
     * Since the descriptor is nonblocking, this loop cannot wait for input.
     */
    do {
        byteCount = read(fd, buffer, sizeof(buffer));
    } while (byteCount == -1 && errno == EINTR);

    if (byteCount > 0) {
        [data appendBytes:buffer length:(NSUInteger)byteCount];
        return YES;
    }

    if (byteCount == 0) {
        *eof = YES;
        return YES;
    }

    /* EAGAIN/EWOULDBLOCK means the pipe is open but presently empty. */
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
        return YES;
    }

    {
        int savedErrno = errno;
        NSError *underlyingError =
        [NSError errorWithDomain:NSPOSIXErrorDomain
                            code:savedErrno
                        userInfo:nil];

        DRAIN_PIPE_FAIL(TBTaskLaunchAndWaitErrorReadFailed,
                        @"Could not read from the pipe.",
                        underlyingError);
    }

#undef DRAIN_PIPE_FAIL
}

@implementation NSTask(TB)

-(BOOL) tbLaunchAndWaitUntilDoneWithTerminationTimeout: (NSTimeInterval)                   terminationTimeout
                                           killTimeout: (NSTimeInterval)                   killTimeout
                                       pollingInterval: (NSTimeInterval)                   pollingInterval
                                                stdOut: (NSString * _Nullable * _Nullable) stdOut
                                                stdErr: (NSString * _Nullable * _Nullable) stdErr
                                                 error: (NSError  * _Nullable * _Nullable) error {

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

    //
    // Set up pipes for stdout and stderr, mutable data objects to hold output from them, and EOF indicators for them
    //

    NSPipe * stdoutPipe = nil;
    NSMutableData * stdoutData = nil;
    BOOL stdoutEOF = YES;
    BOOL stdoutErrorOccurred = NO;
    if (  stdOut != NULL  ) {
        stdoutPipe = [[[NSPipe alloc] init] autorelease];
        [self setStandardOutput: stdoutPipe];
        stdoutData = [[NSMutableData alloc] init];
        stdoutEOF = NO;
    }

    NSPipe * stderrPipe = nil;
    NSMutableData * stderrData = nil;
    BOOL stderrEOF = YES;
    BOOL stderrErrorOccurred = NO;
    if (  stdErr != NULL  ) {
        stderrPipe = [[[NSPipe alloc] init] autorelease];
        [self setStandardError: stderrPipe];
        stderrData = [[NSMutableData alloc] init];
        stderrEOF = NO;
    }

    if (  error != NULL  ) {
        *error = nil;
    }

    if (  ! [self launchAndReturnError: error]  ) {
        [stdoutData release];
        [stderrData release];
        return NO;
    }

    startNS = TBUptimeNanoseconds();

    BOOL errorOccurred = NO;

    while (  self.isRunning  ) {

        elapsedNS = TBUptimeNanoseconds() - startNS;

        //
        // Read from pipes and append to stoutData and stdErrData
        //

        if (  stdoutPipe  ) {
            stdoutErrorOccurred = ! TBDrainPipe(stdoutPipe, stdoutData, &stdoutEOF, error);
            if (  stdoutErrorOccurred  ) {
                errorOccurred = YES;
                break;
            }
        }
        if (  stderrPipe  ) {
            stderrErrorOccurred = ! TBDrainPipe(stderrPipe, stderrData, &stderrEOF, error);
            if (  stderrErrorOccurred  ) {
                errorOccurred = YES;
                break;
            }
        }

        //
        // Deal with timeouts
        //

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
                errorOccurred = YES;
                break;
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
                        errorOccurred = YES;
                        break;
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
                            errorOccurred = YES;
                            break;
                        }
                        
                        // ESRCH and the task is no longer running: fall through.
                    }
                }
            }
        }

        if (  self.isRunning  ) {
            if (  ! TBSleepForTimeInterval(pollingInterval, error)  ) {
                errorOccurred = YES;
                break;
            }
        }
    }

    if (   errorOccurred
        && ( ! requestedTerm )  ) {
        requestedTerm = YES;
        [self terminate];
    }

    //
    // Drain the pipes, and store and release the data
    //
    // Ignore errors draining the pipes if there has already been an error

    NSError * savedError = nil;
    if (   error  ) {
        savedError = *error;
    }

    // After the task exits, a child that inherited the pipe can leave it
    // open. TBDrainPipe returns success on EAGAIN, so this loop must sleep
    // and give up instead of spinning.
    uint64_t drainDeadlineNS = TBUptimeNanoseconds() + TBSecondsToNanoseconds(2.0);

    while (   (   stdoutPipe
               && ( ! stdoutEOF )
               && ( ! stdoutErrorOccurred)  )
           || (   stderrPipe
               && ( ! stderrEOF )
               && ( ! stderrErrorOccurred )  )  ) {

        if (  TBUptimeNanoseconds() >= drainDeadlineNS  ) {
            break;
        }

        NSUInteger stdoutBefore = (stdoutData ? [stdoutData length] : 0);
        NSUInteger stderrBefore = (stderrData ? [stderrData length] : 0);
        BOOL stdoutWasEOF = stdoutEOF;
        BOOL stderrWasEOF = stderrEOF;

        if (   stdoutPipe
            && ( ! stdoutEOF )
            && ( ! stdoutErrorOccurred)  ) {
            stdoutErrorOccurred = ! TBDrainPipe(stdoutPipe, stdoutData, &stdoutEOF, error);
        }

        if (   stderrPipe
            && ( ! stderrEOF )
            && ( ! stderrErrorOccurred )  ) {
            stderrErrorOccurred = ! TBDrainPipe(stderrPipe, stderrData, &stderrEOF, error);
        }

        BOOL progressed = (   (stdoutEOF != stdoutWasEOF)
                           || (stderrEOF != stderrWasEOF)
                           || (stdoutData && ([stdoutData length] != stdoutBefore))
                           || (stderrData && ([stderrData length] != stderrBefore))  );
        if (   ( ! progressed )
            && ( ! stdoutErrorOccurred )
            && ( ! stderrErrorOccurred )  ) {
            if (  ! TBSleepForTimeInterval(0.05, error)  ) {
                break;
            }
        }
    }

    if (   error
        && savedError  ) {
        *error = [[savedError retain] autorelease];
    }

    if (   stdOut
        && stdoutData) {
        *stdOut = [[[NSString alloc] initWithData: stdoutData encoding: NSUTF8StringEncoding] autorelease];
    }
    if (  stdoutData) {
        [stdoutData release];
    }

    if (   stdErr
        && stderrData  ) {
        *stdErr = [[[NSString alloc] initWithData: stderrData encoding: NSUTF8StringEncoding] autorelease];
    }
    if (  stderrData) {
        [stderrData release];
    }

    //
    // If an error occurred, return NO now
    //

    if (   errorOccurred
        || stdoutErrorOccurred
        || stderrErrorOccurred  ) {
        return NO;
    }

    //
    // Return YES or NO
    //

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
