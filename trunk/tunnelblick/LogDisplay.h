/*
 * Copyright 2010 Jonathan Bullard
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

#import <Cocoa/Cocoa.h>
#import "UKKQueue/UKKQueue.h"


@interface LogDisplay : NSObject {

    NSString      * configurationPath;
    NSString      * openvpnLogPath;
    NSString      * scriptLogPath;

    NSTextStorage * logStorage;                     // Contains the log being displayed (or that part of log since it was cleared)

    UKKQueue      * monitorQueue;                   // nil, or queue to monitor log files for changes
    
    unsigned long long openvpnLogPosition;          // NSFileHandle offsetInFile we have read up to
    unsigned long long scriptLogPosition;
    
    NSString      * lastOpenvpnEntryTime;           // Date/time of most-recently-inserted entry from OpenVPN log file
    NSString      * lastScriptEntryTime;            // Date/time of most-recently-inserted entry from script log file
    
    NSString      * lastEntryTime;                  // Date/time of last entry in the log window
    
    unsigned        maxLogDisplaySize;              // Maximum number of bytes that we display in the log window
    
    // Used to throttle requests so we don't use too much CPU time processing bursts of changes to the log files
    long            secondWeLastQueuedAChange;      // Seconds since 1/1/2001 that we last queued a request to process a change to a log file
    unsigned        numberOfRequestsInThatSecond;   // Number of requests we've queued in that second
    NSTimer       * watchdogTimer;                  // Timer to queue a request to process a change to a log file
}

-(LogDisplay *)     initWithConfigurationPath:      (NSString *) inConfigPath;

-(void)             addToLog:                       (NSString *) text;

-(void)             clear;

-(NSTextStorage *)  logStorage;

-(void)             startMonitoringLogFiles;
-(void)             stopMonitoringLogFiles;

-(NSString *)       openvpnLogPath;

@end
