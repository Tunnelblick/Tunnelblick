/*
 * Copyright 2010, 2011, 2012, 2013, 2018 Jonathan K. Bullard. All rights reserved.
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

#import "defines.h"

@class UKKQueue;
@class VPNConnection;


@interface LogDisplay : NSObject {
    
    NSMutableString * tbLog;                        // Entries from the Tunnelblick log (as opposed to the OpenVPN or script logs)
    //                                              // This includes only entries that have NOT been displayed in the NSTextStorage
    //                                              // object -- that is, only entries that have not been displayed to the user
    
    NSAttributedString * savedLog;                  // Contains the log display when the log is not being shown to the user
    //                                              // (either because the VPN Details… window is not being shown, or because a
    //                                              // different configuration's log is being shown).
    //                                              // Contains the contents of the NSTextStorage (the display the user sees) when
    //                                              // configuration's log is being shown.
    
    NSString      * configurationPath;
    NSString      * openvpnLogPath;
    NSString      * scriptLogPath;
    
    VPNConnection * connection;
    
    NSTimer       * logMonitoringTimer;             // Timer fires periodically to check for changes to the log files

    unsigned long long openvpnLogPosition;          // NSFileHandle offsetInFile we have read up to
    unsigned long long scriptLogPosition;

    unsigned long long connectionLogEntrySizeLimit;        // Maximum # of bytes to add to the log while connected
    unsigned long long connectionLogInitialLoadMultiplier; // Maximum # of bytes to load the log from initially
                                                           // = connectionLogInitialLoadMultiplier * connectionLogEntrySizeLimit

    NSTimeInterval  connectionLogTickInterval;      // # of seconds between each check to see if the log files changed

    NSString      * lastOpenvpnEntryTime;           // Date/time of most-recently-inserted entry from OpenVPN log file
    NSString      * lastScriptEntryTime;            // Date/time of most-recently-inserted entry from script log file
    
    NSString      * lastEntryTime;                  // Date/time of last entry in the log window
    
    BOOL            logsHaveBeenLoaded;             // Causes the initial load of the logs
    
    BOOL            ignoreChangeRequests;           // We use this flag and mutex to insure that when we ask to ignore change requests
    pthread_mutex_t makingChangesMutex;             // we will not be in the middle of making changes, and will not start any changes.
    //                                              // This must be done so we know we have processed all changes in the log display when
    //                                              // we get the display contents to swap for a different connection's log display.
    //                                              // (Don't need to lock the mutex when we are saying NOT to ignore requests.)
    
	BOOL			warnedAboutUserGroupAlready;	// Used to warn about this only once per connection/disconnection.
}

-(LogDisplay *)     initWithConfigurationPath:      (NSString *) inConfigPath;

-(void)             addToLog:                       (NSString *) text;

-(void)             clear;

-(void)             startMonitoringLogFiles;

-(void)             stopMonitoringLogFiles;

-(void)				outputLogFiles;

TBPROPERTY_READONLY(NSString *, openvpnLogPath)

TBPROPERTY(VPNConnection *, connection, setConnection)

@end
