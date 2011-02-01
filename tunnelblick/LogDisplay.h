/*
 *  Copyright 2010 Jonathan Bullard
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
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
    
    unsigned        nLinesBeingDisplayed;
    
    NSString      * lastOpenvpnEntryTime;           // Date/time of most-recently-inserted entry from OpenVPN log file
    NSString      * lastScriptEntryTime;            // Date/time of most-recently-inserted entry from script log file
}

-(LogDisplay *)     initWithConfigurationPath:      (NSString *) inConfigPath;

-(void)             addToLog:                       (NSString *) text;

-(void)             clear;

-(NSTextStorage *)  logStorage;

-(void)             startMonitoringLogFiles;

@end
