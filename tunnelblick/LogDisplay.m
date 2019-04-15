/*
 * Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019 Jonathan K. Bullard. All rights reserved.
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

#import "LogDisplay.h"

#import <pthread.h>

#import "defines.h"
#import "helper.h"

#import "ConfigurationsView.h"
#import "MenuController.h"
#import "MyPrefsWindowController.h"
#import "NSDate+TB.h"
#import "NSFileManager+TB.h"
#import "NSString+TB.h"
#import "NSTimer+TB.h"
#import "TBUserDefaults.h"
#import "UKKQueue/UKKQueue.h"
#import "VPNConnection.h"

#define NUMBER_OF_LINES_TO_KEEP_AT_START_OF_LOG 10
#define NUMBER_OF_LINES_TO_KEEP_AS_TUNNELBLICK_ENTRIES_AT_START_OF_LOG 3

extern NSFileManager        * gFileMgr;
extern TBUserDefaults       * gTbDefaults;
extern BOOL                   gShuttingDownWorkspace;
extern unsigned               gMaximumLogSize;

@interface LogDisplay() // PRIVATE METHODS

-(void)         appendLine:             (NSString *)            line
            fromOpenvpnLog:             (BOOL)                  isFromOpenvpnLog
        fromTunnelblickLog:             (BOOL)                  isFromTunnelblickLog;

-(void)         insertLine:             (NSString *)            line
  beforeTunnelblickEntries:             (BOOL)                  beforeTunnelblickEntries
      beforeOpenVPNEntries:             (BOOL)                  beforeOpenVPNEntries
            fromOpenVPNLog:             (BOOL)                  isfromOpenVPNLog
        fromTunnelblickLog:             (BOOL)                  isFromTunnelblickLog;

-(void)         didAddLineToLogDisplay;

-(NSString *)   contentsOfPath:         (NSString *)            logPath
                   usePosition:         (unsigned long long *)  logPosition;

-(NSString *)   convertDateInLine:      (NSString *)            line
			      messageFlagsPtr:      (NSUInteger *)			messageFlagsPtr;

-(NSString *)   constructOpenvpnLogPath;
-(NSString *)   constructScriptLogPath;
    
-(NSUInteger)   indexAfter:             (NSUInteger)            n
                    string:             (NSString *)            s
                  inString:             (NSString *)            text
                     range:             (NSRange)               r;

-(NSRange)      rangeOfLineBeforeLineThatStartsAt: (unsigned long) lineStartIndex
                                         inString: (NSString *)    text
                                            after: (unsigned long) start;

-(void)    loadLogsWithInitialContents: (NSAttributedString *)  initialContents
         skipToStartOfLineInOpenvpnLog: (BOOL)                  skipToStartOfLineInOpenvpnLog;

-(void)         logChangedAtPath:       (NSString *)            logPath
                     usePosition:       (unsigned long long *)  logPositionPtr
                  fromOpenvpnLog:       (BOOL)                  isFromOpenvpnLog;

-(NSTextStorage *) logStorage;

-(void)         openvpnLogChanged;
-(void)         scriptLogChanged;

-(NSString *)   nextLineInTunnelblickString: (NSString * *)     stringPtr
                               fromPosition: (unsigned *)       positionPtr;

-(NSString *)   nextLineInScriptString: (NSString * *)          stringPtr
                    fromPosition:       (unsigned *)            positionPtr;

-(NSString *)   nextLinesInOpenVPNString:(NSString * *)         stringPtr
                    fromPosition:       (unsigned *)            positionPtr;

-(void)         pruneLog;

-(void)         watcher:                (UKKQueue *)            kq
   receivedNotification:                (NSString *)            nm
                forPath:                (NSString *)            fpath;

@end

@implementation LogDisplay

static pthread_mutex_t logStorageMutex = PTHREAD_MUTEX_INITIALIZER;

TBSYNTHESIZE_OBJECT(retain, NSMutableString *,      tbLog,                  setTbLog)
TBSYNTHESIZE_OBJECT(retain, NSAttributedString *,   savedLog,               setSavedLog)
TBSYNTHESIZE_OBJECT(retain, NSString *,             configurationPath,      setConfigurationPath)
TBSYNTHESIZE_OBJECT(retain, NSString *,             openvpnLogPath,         setOpenvpnLogPath)
TBSYNTHESIZE_OBJECT(retain, NSString *,             scriptLogPath,          setScriptLogPath)
TBSYNTHESIZE_OBJECT(retain, VPNConnection *,        connection,             setConnection)
TBSYNTHESIZE_OBJECT(retain, UKKQueue *,             monitorQueue,           setMonitorQueue)
TBSYNTHESIZE_OBJECT(retain, NSTimer *,              watchdogTimer,          setWatchdogTimer)

TBSYNTHESIZE_OBJECT_GET(retain, NSString *,         lastOpenvpnEntryTime)
TBSYNTHESIZE_OBJECT_GET(retain, NSString *,         lastScriptEntryTime)
TBSYNTHESIZE_OBJECT_GET(retain, NSString *,         lastEntryTime)


-(void) setLastOpenvpnEntryTime: (NSString *) newTime {
	
	if (  [lastOpenvpnEntryTime compare: newTime] == NSOrderedAscending  ) {
		[newTime retain];
		[lastOpenvpnEntryTime release];
		lastOpenvpnEntryTime = newTime;
	}
}

-(void) setLastScriptEntryTime: (NSString *) newTime {
	
	if (  [lastScriptEntryTime compare: newTime] == NSOrderedAscending  ) {
		[newTime retain];
		[lastScriptEntryTime release];
		lastScriptEntryTime = newTime;
	}
}

-(void) setLastEntryTime: (NSString *) newTime {
	
	if (  [lastEntryTime compare: newTime] == NSOrderedAscending  ) {
		[newTime retain];
		[lastEntryTime release];
		lastEntryTime = newTime;
	}
}

// Returns the NSLogStorage object for the NSTextView that contains the log
// BUT only if it is the log for this configuration. (If not, returns nil.)
-(NSTextStorage *) logStorage
{
    MyPrefsWindowController * wc = [((MenuController *)[NSApp delegate]) logScreen];
    if (  wc  ) {
        if (  [self connection] == [wc selectedConnection]  ) {
            ConfigurationsView      * cv = [wc configurationsPrefsView];
            NSTextView              * lv = [cv logView];
            NSTextStorage           * ts = [lv textStorage];
            return ts;
        }
    }
    
    return nil;
}

+(NSColor *) redColorForHighlighting {
	
	return [NSColor colorWithCalibratedRed: 1.0 green: 0.0 blue: 0.0 alpha: 0.4];
}

+(NSColor *) yellowColorForHighlighting {
	
	return [NSColor colorWithCalibratedRed: 1.0 green: 1.0 blue: 0.0 alpha: 0.4];
}

+(NSColor *) blueColorForHighlighting {
	
	return [NSColor colorWithCalibratedRed: 0.0 green: 1.0 blue: 1.0 alpha: 0.2];
}

+(NSColor *) darkBlueColorForFont {
	
	return [NSColor colorWithCalibratedRed: 0.0 green: 0.0 blue: 1.0 alpha: 1.0];
}

// Highlights errors with red, warnings with yellow, and notes with blue
// Renders Tunnelblick log entries in blue text and OpenVPN entries in black text
-(NSMutableAttributedString *) attributedStringFromLine: (NSString *) line fromTunnelblick: (BOOL) fromTunnelblick {
    
    NSMutableAttributedString * string = [[[NSMutableAttributedString alloc] initWithString: line] autorelease];
    
    NSRange lineRange = NSMakeRange(0, [line length]);

	[string addAttribute: NSForegroundColorAttributeName value:[NSColor textColor]           range: lineRange];
	[string addAttribute: NSBackgroundColorAttributeName value:[NSColor textBackgroundColor] range: lineRange];
	
    NSRange issueRange = [line rangeOfString: @"NOTE:" options: NSCaseInsensitiveSearch];
    if (  issueRange.length != 0  ) {
        [string addAttribute: NSBackgroundColorAttributeName value: [LogDisplay blueColorForHighlighting]   range: lineRange];
    }
    
    issueRange = [line rangeOfString: @"WARNING:" options: NSCaseInsensitiveSearch];
    if (  issueRange.length != 0  ) {
        [string addAttribute: NSBackgroundColorAttributeName value: [LogDisplay yellowColorForHighlighting] range: lineRange];
    }
    
    issueRange = [line rangeOfString: @"ERROR:" options: NSCaseInsensitiveSearch];
    if (  issueRange.length != 0  ) {
        [string addAttribute: NSBackgroundColorAttributeName value: [LogDisplay redColorForHighlighting]    range: lineRange];
    }
    
    issueRange = [line rangeOfString: @"no default was specified by either --route-gateway or --ifconfig options" options: NSCaseInsensitiveSearch];
    if (  issueRange.length != 0  ) {
        [string addAttribute: NSBackgroundColorAttributeName value: [LogDisplay redColorForHighlighting]    range: lineRange];
    }
    
	if (  fromTunnelblick  ) {
		[string addAttribute: NSForegroundColorAttributeName value: [LogDisplay darkBlueColorForFont]       range: lineRange];
	}
	
	if (  ! warnedAboutUserGroupAlready  ) {
		issueRange = [line rangeOfString: @"must be root to alter routing table" options: NSCaseInsensitiveSearch];
		if (  issueRange.length != 0  ) {
			[self performSelectorOnMainThread: @selector(warnAboutUserGroup) withObject: nil waitUntilDone: NO];
			warnedAboutUserGroupAlready = TRUE;
		}
	}
	
    return string;
}

-(void) warnAboutUserGroup {
	
	TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
					  attributedLightDarkStringFromHTML([NSString stringWithFormat: NSLocalizedString(@"<font face=\"Helvetica,Arial,sans-serif\"><p>The network setup was not restored properly after disconnecting from %@.</p>"
																									  @"<p>This problem is usually caused by using the 'user nobody' and/or 'group nobody' OpenVPN options.</p>"
																									  @"<p>To restore the network setup, you should restart your computer.</p>"
																									  @"<p>To prevent this error in the future, remove the 'user nobody' and 'group nobody' lines from your"
																									  @" OpenVPN configuration file.</p>"
																									  @"<p>See <a href=\"https://tunnelblick.net/cUserAndGroupOptions.html\">User and Group OpenVPN"
																									  @" Options</a> [tunnelblick.net] for more information.</p></font>\n\n",
																									  @"Window text. The %@ is the name of a VPN configuration."),
														 [connection localizedName]]));
}

-(void) popupAWarningForProblemSeenInLogLine: (NSString *) line {
	
	NSString * message = messageIfProblemInLogLine(line);
	if (  message  ) {
		[connection addMessageToDisplayIfConnectionFails: message];
	}
}

-(BOOL) loggingIsDisabled {
    
    NSString * key = [[[self connection] displayName] stringByAppendingString: @"-loggingLevel"];
    NSUInteger logPreference = [gTbDefaults unsignedIntForKey: key
                                                      default: TUNNELBLICK_DEFAULT_LOGGING_LEVEL
                                                          min: MIN_OPENVPN_LOGGING_LEVEL
                                                          max: MAX_TUNNELBLICK_LOGGING_LEVEL];
    return (logPreference == TUNNELBLICK_NO_LOGGING_LEVEL);
}

-(void) insertLogEntry: (NSDictionary *) dict {
    
    // MUST call with logStorageMutex locked
    //
    // Inserts an entry into the log. If this log is currently being displayed, do it on the main thread.
    
    MyPrefsWindowController * wc = [((MenuController *)[NSApp delegate]) logScreen];
    
    if (  [self connection] == [wc selectedConnection]  ) {
        if (  ! [NSThread isMainThread]  ) {
            [self performSelectorOnMainThread: @selector(insertLogEntry:) withObject: dict waitUntilDone: NO];
        }
    }
    
    NSString * line  = [dict objectForKey: @"line"];
    NSNumber * index = [dict objectForKey: @"index"];
    
    ConfigurationsView      * cv = [wc configurationsPrefsView];
    NSTextView              * tv = [cv logView];
    NSTextStorage           * ts = [tv textStorage];
    if (  ! ts  ) {
        NSLog(@"insertLogEntry: no ts");
        return;
    }
    
    // If the end of the log is visible before we insert the line, we will scroll to keep the end visible after inserting the line
    NSRect visRect = [tv visibleRect];
	NSRect bounds  = [tv bounds];
	CGFloat bottomYOfVisible  = visRect.origin.y + visRect.size.height;
	CGFloat bottomYOfContents = bounds.origin.y  + bounds.size.height;
	CGFloat heightBelowVisible = bottomYOfContents - bottomYOfVisible;
	BOOL scrollToEnd = (heightBelowVisible < 100.0);
    
    // Testing has determined that several conditions must be met for the log to display properly:
    //      (1) Must be running on the main thread
    //      (2) Must add only one line to the NSTextStorage at a time
    //      (3) If scrolling to the end of the log, must scroll each time a line is added, before any other lines are added
    // If these conditions are not all met, the display does not always update properly.
    
    NSUInteger ix = [index unsignedIntegerValue];
    
    NSArray * lines = [line componentsSeparatedByString: @"\n"];
    NSUInteger lineCount = [lines count];
    if (  [line hasSuffix: @"\n"]  ) {
        lineCount--;
    }
    
	BOOL fromTunnelblick = ([line rangeOfString: TB_LOG_PREFIX].length != 0);

    NSUInteger i;
    for (  i=0; i < lineCount; i++) {
        NSString * singleLine = [[lines objectAtIndex: i] stringByAppendingString: @"\n"];
        [ts beginEditing];
		[self popupAWarningForProblemSeenInLogLine: singleLine];
		NSMutableAttributedString * string = [self attributedStringFromLine: singleLine fromTunnelblick: fromTunnelblick];
		[ts insertAttributedString: string atIndex: ix];
        [ts endEditing];
        ix = ix + [singleLine length];
        
        if (  scrollToEnd  ) {
            [tv scrollRangeToVisible: NSMakeRange([[ts string] length], 0)];
        }
    }

    [tv setNeedsDisplay: YES];  // Shouldn't be needed, but if not done the NSTextView sometimes becomes blank
}

-(void) insertLogEntry: (NSString *) line atIndex: (NSUInteger) index {
    
    // MUST call with logStorageMutex locked
    //
    // Inserts a line into the log. If this log is currently being displayed, do it on the main thread.
    
    NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                           line,                               @"line",
                           [NSNumber numberWithUnsignedInteger: index], @"index",
                           nil];
    [self insertLogEntry: dict];
}

-(LogDisplay *) initWithConfigurationPath: (NSString *) inConfigPath
{
	if (  (self = [super init])  ) {
        
        savedLog = nil;
        configurationPath = [inConfigPath copy];
        openvpnLogPath = nil;
        scriptLogPath = nil;

        monitorQueue = nil;
        connection = nil;
        watchdogTimer = nil;
        
        lastEntryTime        = @"0000-00-00 00:00:00";
        lastOpenvpnEntryTime = @"0000-00-00 00:00:00";
        lastScriptEntryTime  = @"0000-00-00 00:00:00";
        
        openvpnLogPosition = 0;
        scriptLogPosition  = 0;
        
        logsHaveBeenLoaded = FALSE;
        
        ignoreChangeRequests = FALSE;
        OSStatus status = pthread_mutex_init( &makingChangesMutex, NULL);
        if (  status != EXIT_SUCCESS  ) {
            NSLog(@"logDisplay:initWithConfigurationPath: pthread_mutex_init( &makingChangesMutex ) failed; status = %ld", (long) status);
            return nil;
        }
        
        tbLog = [[NSMutableString alloc] init];
    }
    
    return self;
}

-(void) dealloc {
	
	[tbLog                release]; tbLog                = nil;
    [savedLog             release]; savedLog             = nil;
	[configurationPath    release]; configurationPath    = nil;
    [openvpnLogPath       release]; openvpnLogPath       = nil;
    [scriptLogPath        release]; scriptLogPath        = nil;
	[connection           release]; connection           = nil;
	[monitorQueue         release]; monitorQueue         = nil;
    [lastOpenvpnEntryTime release]; lastOpenvpnEntryTime = nil;
    [lastScriptEntryTime  release]; lastScriptEntryTime  = nil;
	[lastEntryTime        release]; lastEntryTime        = nil;
    [watchdogTimer invalidate];
	[watchdogTimer        release]; watchdogTimer        = nil;
	
    [super dealloc];
}

// Inserts the current date/time, a message, and a \n to the log display.
-(void) addToLog: (NSString *) text
{
    if (   gShuttingDownWorkspace
        || [self loggingIsDisabled]  ) {
        return;
    }
    
    NSString * dateText = [NSString stringWithFormat:@"%@ %@\n",[[NSDate date] tunnelblickUserLogRepresentation], text];
    
    BOOL fromTunnelblick = [text hasPrefix: TB_LOG_PREFIX];
    
    if (   [self logStorage]
        && [self monitorQueue]  ) {
        [self insertLine: dateText beforeTunnelblickEntries: NO beforeOpenVPNEntries: NO fromOpenVPNLog: NO fromTunnelblickLog: fromTunnelblick];
    } else {
        if (  fromTunnelblick  ) {
            [[self tbLog] appendString: dateText];
        }
    }

}

// Clears the log so it shows only the header line
-(void) clear
{
    if (  gShuttingDownWorkspace  ) {
        return;
    }
	
	warnedAboutUserGroupAlready = FALSE;
    
    if (  ! [NSThread isMainThread]  ) {
        [self performSelectorOnMainThread: @selector(clear) withObject: nil waitUntilDone: NO];
        return;
    }
    
	lastEntryTime        = @"0000-00-00 00:00:00";
	lastOpenvpnEntryTime = @"0000-00-00 00:00:00";
	lastScriptEntryTime  = @"0000-00-00 00:00:00";
	
    NSString * message = (  [self loggingIsDisabled]
                          ? NSLocalizedString(@"(Logging is disabled.)", @"Window text -- appears in log display when logging is disabled\n")
                          : [[((MenuController *)[NSApp delegate]) openVPNLogHeader] stringByAppendingString: @"\n"]);

	message = [NSString stringWithFormat: @"%@ %@", [[NSDate date] tunnelblickUserLogRepresentation], message];
	
    // Clear the log in the display if it is being shown
    OSStatus status = pthread_mutex_lock( &logStorageMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"logDisplay:clear: pthread_mutex_lock( &logStorageMutex ) failed; status = %ld", (long) status);
        return;
    }
    NSTextStorage * logStore = [self logStorage];
    if (  logStore  ) {
        [logStore beginEditing];
        if (  [logStore length]  ) {
            [logStore deleteCharactersInRange: NSMakeRange(0, [logStore length])];
        }
        [logStore endEditing];
    }
    pthread_mutex_unlock( &logStorageMutex );
    
    // Clear the Tunnelblick log entries, too
    [[self tbLog] deleteCharactersInRange: NSMakeRange(0, [[self tbLog] length])];
    
    // And the saved log (if we have one)
    if (  savedLog  ) {
        [self setSavedLog: [[[NSAttributedString alloc] init] autorelease]];    // Not nil, which is a flag that we are displaying this log
    }
    
    // We "clear" the OpenVPN and script logs by indicating that we should start writing from the beginning of them 
    openvpnLogPosition = 0;
    scriptLogPosition  = 0;
    
    // As if doing addLog, but done even if logging is disabled so the "(Logging is disabled.)" message is shown
    if (   logStore
        && [self monitorQueue]  ) {
        [self insertLine: message beforeTunnelblickEntries: NO beforeOpenVPNEntries: NO fromOpenVPNLog: NO fromTunnelblickLog: YES];
    } else {
        [[self tbLog] setString: message];
    }
}

// Starts (or restarts) monitoring newly-created log files.
-(void) startMonitoringLogFiles
{
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    [self setMonitorQueue: [[[UKKQueue alloc] init] autorelease]];
    
    [[self monitorQueue] setDelegate: self];
    [[self monitorQueue] setAlwaysNotify: YES];
    
    [self setOpenvpnLogPath: [self constructOpenvpnLogPath]];
    [self setScriptLogPath:  [self constructScriptLogPath]];

    if (   ( ! logsHaveBeenLoaded)
        || [self savedLog]  ) {
        // Not displaying the log, so load it up from tbLog and the two log files
        
        // The OpenVPN log may be huge (verb level 9 can generates several megabyte per second)
        //  so we only scan the last part -- only the last MAX_LOG_DISPLAY_SIZE bytes
        NSNumber * fileSizeAsNumber;
        unsigned long long fileSize = 0;
        if (  [self openvpnLogPath]  ) {
            NSDictionary * attributes = [gFileMgr tbFileAttributesAtPath: [self openvpnLogPath] traverseLink: NO];
            if (  (fileSizeAsNumber = [attributes objectForKey:NSFileSize])  ) {
                fileSize = [fileSizeAsNumber unsignedLongLongValue];
            }
        }
        
        BOOL skipToStartOfLineInOpenvpnLog = FALSE;
        unsigned long long amountToExamine = gMaximumLogSize;
        if (   ( fileSize > amountToExamine )
            && ( (fileSize - openvpnLogPosition) > amountToExamine)  ) {
            openvpnLogPosition = fileSize - amountToExamine;
            skipToStartOfLineInOpenvpnLog = TRUE;
        }
        
        [self loadLogsWithInitialContents: [self savedLog] skipToStartOfLineInOpenvpnLog: skipToStartOfLineInOpenvpnLog];
        
        [savedLog release];
        savedLog = nil;
        
        logsHaveBeenLoaded = TRUE;
    }
    
    ignoreChangeRequests = FALSE;
    
    if (  [self openvpnLogPath]  ) {
        [[self monitorQueue] addPathToQueue: [self openvpnLogPath]];
    }
    if (  [self scriptLogPath]  ) {
        [[self monitorQueue] addPathToQueue: [self scriptLogPath]];
    }
}

// Stops monitoring newly-created log files.
-(void) stopMonitoringLogFiles
{
    if (  ! [self monitorQueue]  ) {
        return;
    }

    [self setMonitorQueue: nil];

    // Process any existing log changes before we stop monitoring
    [self performSelectorOnMainThread: @selector(openvpnLogChanged) withObject: nil waitUntilDone: NO];
    [self performSelectorOnMainThread: @selector(scriptLogChanged)  withObject: nil waitUntilDone: NO];

    // MUTEX LOCK to change ignoreChangeRequests (so we know that no changes will be processed after we change ignoreChangeRequests
    OSStatus status = pthread_mutex_lock( &makingChangesMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"logDisplay:stopMonitoringLogFiles: pthread_mutex_lock( &makingChangesMutex ) failed; status = %ld", (long) status);
        return;
    }
    ignoreChangeRequests = TRUE;
    
    NSTextStorage * logStore = [self logStorage];
    NSRange  r = NSMakeRange(0, [logStore length]);
    [self setSavedLog: [logStore attributedSubstringFromRange: r]];
    
    pthread_mutex_unlock( &makingChangesMutex );
}

-(void) outputLogFiles {
	[self openvpnLogChanged];
	[self scriptLogChanged];
}

-(void) loadLogsWithInitialContents: (NSDictionary *) dict {

    // Does the initial load of the logs, inserting entries from them in the "correct" chronological order.
    //
    // The "correct" order is that all OpenVPN log entries for a particular date/time come before
    // any script log entries for that same time.
    //
    // However, the first three lines of the log are from Tunnelblick, and we keep them at the start of the log
    //
    // And, if skipToStartOfLineInOpenVPNLog is set and we haven't loaded anything yet, we load from the _start_ of the OpenVPN log until
    // we have NUMBER_OF_LINES_TO_KEEP_AT_START_OF_LOG lines in the log. Then we skip the OpenVPN log pointer ahead.
    //
    // Since the log files are in chronological order, we always (in this method) append to (rather than insert into) the log display,
    // which is much less processing intensive.
    
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    NSTextStorage * logStore = [self logStorage];
    if (  ! logStore  ) {
        NSLog(@"logDisplay:loadLogsWithInitialContents:skipToStartOfLineInOpenvpnLog: invoked but not displaying log for that connection");
        return;             // Don't do anything if we aren't displaying the log for this connection
    }
    
    if (  ! [NSThread isMainThread]  ) {
        [self performSelectorOnMainThread: @selector(loadLogsWithInitialContents:) withObject: dict waitUntilDone: NO];
        return;
    }
    
    NSAttributedString * initialContents               = [dict objectForKey: @"contents"];
    BOOL                 skipToStartOfLineInOpenvpnLog = [[dict objectForKey: @"skip"] boolValue];
    
    [[((MenuController *)[NSApp delegate]) logScreen] indicateWaitingForLogDisplay: [self connection]];
    
    // Save, then clear, the current contents of the tbLog
    NSString * tunnelblickString = [[self tbLog] copy];
    [[self tbLog] deleteCharactersInRange: NSMakeRange(0, [[self tbLog] length])];
    
    // Load the initial contents of the display
    OSStatus status = pthread_mutex_lock( &logStorageMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"logDisplay:loadLogsWithInitialContents:skipToStartOfLineInOpenvpnLog: pthread_mutex_lock( &logStorageMutex ) failed; status = %ld", (long) status);
        [tunnelblickString release];
        return;
    }
    [logStore beginEditing];
    [logStore deleteCharactersInRange: NSMakeRange(0, [logStore length])];
    if (  initialContents  ) {        
        [logStore appendAttributedString: initialContents];
    }
    [logStore endEditing];
    pthread_mutex_unlock( &logStorageMutex );
    
    NSString * scriptString  = @"";
    if (  [self scriptLogPath]  ) {
        scriptString  = [self contentsOfPath: [self scriptLogPath]  usePosition: &scriptLogPosition];
    }
    
    unsigned long long savedOpenVPNLogPosition = openvpnLogPosition; // used if we skipToStartOfLineInOpenvpnLog
   
    NSString * openvpnString = @"";
    if (  [self openvpnLogPath]  ) {
        if (  skipToStartOfLineInOpenvpnLog  ) {
            openvpnLogPosition = 0;
        }
        openvpnString = [self contentsOfPath: [self openvpnLogPath] usePosition: &openvpnLogPosition];
    }
    
    unsigned tunnelblickStringPosition = 0;
    unsigned openvpnStringPosition     = 0;
    unsigned scriptStringPosition      = 0;
    
    
    NSString * tLine = [self nextLineInTunnelblickString: &tunnelblickString fromPosition: &tunnelblickStringPosition];
    NSString * oLine = [self nextLinesInOpenVPNString:    &openvpnString     fromPosition: &openvpnStringPosition    ];
    NSString * sLine = [self nextLineInScriptString:      &scriptString      fromPosition: &scriptStringPosition     ];
    
    NSString * tLineDateTime = @"0000-00-00 00:00:00";
    NSString * oLineDateTime = @"0000-00-00 00:00:00";
    NSString * sLineDateTime = @"0000-00-00 00:00:00";
    
    int numLinesLoaded = 0;
    int numTLinesToEnterFirst = NUMBER_OF_LINES_TO_KEEP_AS_TUNNELBLICK_ENTRIES_AT_START_OF_LOG;  // Counts down as we enter each tLine
    
    BOOL haveSkippedAhead = FALSE;
    while (   (tLine != nil)
           || (oLine != nil)
           || (sLine != nil)  ) {
        
        if (  gShuttingDownWorkspace  ) {
            [tunnelblickString release];
            return;
        }
        
        if (  numLinesLoaded++ == NUMBER_OF_LINES_TO_KEEP_AT_START_OF_LOG  ) {
            if (   skipToStartOfLineInOpenvpnLog
                && ( ! haveSkippedAhead )  ) {
                // We have loaded up the first part of the log. Skip the OpenVPN log ahead
                haveSkippedAhead = TRUE;
                if (  savedOpenVPNLogPosition < [openvpnString length]  ) {
                    unsigned savedPosition = (unsigned)savedOpenVPNLogPosition;
                    NSRange s = NSMakeRange(savedPosition, [openvpnString length] - savedPosition);
                    NSRange r = [openvpnString rangeOfString: @"\n" options: 0 range: s];
                    if (  r.location != NSNotFound  ) {
                        openvpnStringPosition = r.location + 1;
                    }
                }
            }
        }
        
        if (  tLine  ) {
            if (  [tLine length] > TB_LOG_DATE_TIME_WIDTH  ) {
                if (  ! [tLine hasPrefix: @" "]  ) {
                    tLineDateTime = [tLine substringToIndex: TB_LOG_DATE_TIME_WIDTH];
                }
            }            
        }
        if (  oLine  ) {
            if (  [oLine length] > TB_LOG_DATE_TIME_WIDTH  ) {
                if (  ! [oLine hasPrefix: @" "]  ) {
                    oLineDateTime = [oLine substringToIndex: TB_LOG_DATE_TIME_WIDTH];
                }
            }
        }
        if (  sLine  ) {
            if (  [sLine length] > TB_LOG_DATE_TIME_WIDTH  ) {
                if (  ! [sLine hasPrefix: @" "]  ) {
                    sLineDateTime = [sLine substringToIndex: TB_LOG_DATE_TIME_WIDTH];
                }
            }
            
        }
        
        if (  tLine  ) {
           if (  numTLinesToEnterFirst != 0) {
                [self appendLine: tLine fromOpenvpnLog: NO fromTunnelblickLog: YES];
                tLine = [self nextLineInTunnelblickString: &tunnelblickString
                                             fromPosition: &tunnelblickStringPosition];
                numTLinesToEnterFirst--;
            } else {
                if (  oLine  ) {
                    if (  sLine  ) {
                        // Have tLine, oLine, and sLine
                        if (  [tLineDateTime compare: oLineDateTime] != NSOrderedDescending ) {
                            if (  [tLineDateTime compare: sLineDateTime] != NSOrderedDescending ) {
                                [self appendLine: tLine fromOpenvpnLog: NO fromTunnelblickLog: YES];
                                tLine = [self nextLineInTunnelblickString: &tunnelblickString
                                                             fromPosition: &tunnelblickStringPosition];
                            } else {
                                [self appendLine: sLine fromOpenvpnLog: NO fromTunnelblickLog: NO];
                                sLine = [self nextLineInScriptString: &scriptString
                                                        fromPosition: &scriptStringPosition];
                            }
                        } else {
                            if (  [oLineDateTime compare: sLineDateTime] != NSOrderedDescending ) {
                                [self appendLine: oLine fromOpenvpnLog: YES fromTunnelblickLog: NO];
                                oLine = [self nextLinesInOpenVPNString: &openvpnString
                                                          fromPosition: &openvpnStringPosition];
                            } else {
                                [self appendLine: sLine fromOpenvpnLog: NO fromTunnelblickLog: NO];
                                sLine = [self nextLineInScriptString: &scriptString
                                                        fromPosition: &scriptStringPosition];
                            }
                        }
                    } else {
                        // Have tLine and oLine but not sLine
                        if (  [tLineDateTime compare: oLineDateTime] != NSOrderedDescending ) {
                            [self appendLine: tLine fromOpenvpnLog: NO fromTunnelblickLog: YES];
                            tLine = [self nextLineInTunnelblickString: &tunnelblickString
                                                         fromPosition: &tunnelblickStringPosition];
                        } else {
                            [self appendLine: oLine fromOpenvpnLog: YES fromTunnelblickLog: NO];
                            oLine = [self nextLinesInOpenVPNString: &openvpnString
                                                      fromPosition: &openvpnStringPosition];
                        }
                    }
                } else {
                    // Have tLine, don't have oLine
                    if (  sLine  ) {
                        // Have tLine and sLine but not oLine
                        if (  [tLineDateTime compare: sLineDateTime] != NSOrderedDescending ) {
                            [self appendLine: tLine fromOpenvpnLog: NO fromTunnelblickLog: YES];
                            tLine = [self nextLineInTunnelblickString: &tunnelblickString
                                                         fromPosition: &tunnelblickStringPosition];
                        } else {
                            [self appendLine: sLine fromOpenvpnLog: NO fromTunnelblickLog: NO];
                            sLine = [self nextLineInScriptString: &scriptString
                                                    fromPosition: &scriptStringPosition];
                        }
                    } else {
                        // Only have tLine
                        [self appendLine: tLine fromOpenvpnLog: NO fromTunnelblickLog: YES];
                        tLine = [self nextLineInTunnelblickString: &tunnelblickString
                                                     fromPosition: &tunnelblickStringPosition];
                    }
                }
            }
        } else {
            // Don't have tLine
            if (  oLine  ) {
                if (  sLine  ) {
                    // Have oLine and sLine but not tLine
                    if (  [oLineDateTime compare: sLineDateTime] != NSOrderedDescending ) {
                        [self appendLine: oLine fromOpenvpnLog: YES fromTunnelblickLog: NO];
                        oLine = [self nextLinesInOpenVPNString: &openvpnString
                                                  fromPosition: &openvpnStringPosition];
                    } else {
                        [self appendLine: sLine fromOpenvpnLog: NO fromTunnelblickLog: NO];
                        sLine = [self nextLineInScriptString: &scriptString
                                                fromPosition: &scriptStringPosition];
                    }
                } else {
                    // Only have oLine
                    [self appendLine: oLine fromOpenvpnLog: YES fromTunnelblickLog: NO];
                    oLine = [self nextLinesInOpenVPNString: &openvpnString
                                              fromPosition: &openvpnStringPosition];
                }
            } else {
                // Only have sLine
                if (  sLine  ) {
                    [self appendLine: sLine fromOpenvpnLog: NO fromTunnelblickLog: NO];
                    sLine = [self nextLineInScriptString: &scriptString
                                            fromPosition: &scriptStringPosition];
                }
            }
        }
    }
    
    if (  skipToStartOfLineInOpenvpnLog  ) {
        [self pruneLog];
    }
    
    [tunnelblickString release];
    
    [[((MenuController *)[NSApp delegate]) logScreen] indicateNotWaitingForLogDisplay: [self connection]];
}

-(void) loadLogsWithInitialContents: (NSAttributedString *) initialContents
      skipToStartOfLineInOpenvpnLog: (BOOL)                 skipToStartOfLineInOpenvpnLog {
    
    // Does the initial load of the logs, inserting entries from them in the "correct" chronological order.
    //
    // The "correct" order is that all OpenVPN log entries for a particular date/time come before
    // any script log entries for that same time.
    //
    // However, the first three lines of the log are from Tunnelblick, and we keep them at the start of the log
    //
    // And, if skipToStartOfLineInOpenVPNLog is set and we haven't loaded anything yet, we load from the _start_ of the OpenVPN log until
    // we have NUMBER_OF_LINES_TO_KEEP_AT_START_OF_LOG lines in the log. Then we skip the OpenVPN log pointer ahead.
    //
    // Since the log files are in chronological order, we always (in this method) append to (rather than insert into) the log display,
    // which is much less processing intensive.
    
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                           initialContents,                                          @"contents",
                           [NSNumber numberWithBool: skipToStartOfLineInOpenvpnLog], @"skip",
                           nil];
    
    [self loadLogsWithInitialContents: dict];
}

-(NSUInteger) indexAfter: (NSUInteger) n string: (NSString *) s inString: (NSString *) text range: (NSRange) r
{
    // Find the n-th string
    NSRange rStartAt = r;
    NSRange rLf;
    unsigned i = 0;
    while (   ( NSNotFound != (rLf = [text rangeOfString: s options: 0 range: rStartAt] ).location )
           && (i++ < n)  ) {
        rStartAt.location = rLf.location + 1;
        rStartAt.length   = [text length] - rStartAt.location;
    }
    
    return rStartAt.location;
}

-(NSString *) contentsOfPath: (NSString *) logPath usePosition: (unsigned long long *) logPosition
{
    // Open file, seek to current position, read to end of file, note new current position, close file
    NSFileHandle * file;
    if (  logPath  ) {
        if (  ! (file = [NSFileHandle fileHandleForReadingAtPath: logPath])  ) {
            *logPosition = 0;
            return @"";
        }
    } else {
        *logPosition = 0;
        return @"";
    }

        
    [file seekToFileOffset: *logPosition];
    NSData * data = [file readDataToEndOfFile];
    *logPosition = [file offsetInFile];
    [file closeFile];
    
    if (  ! data  ) {
        NSLog(@"readDataToEndOfFile returned nil from position %llu for path=%@", *logPosition, logPath);
        return @"";
    }
    NSString * scriptLogContents = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
    if (  ! scriptLogContents  ) {
        NSLog(@"contentsOfPath:usePosition:fileHandleForReadingAtPath: initWithData: returned nil with data of length %lld from position %lld for path=%@", (long long) [data length], *logPosition, logPath);
        unsigned i;
        char * b = (char *) [data bytes];
        NSMutableString * s = [NSMutableString stringWithCapacity: 2 * [data length]];
        for ( i=0; i<[data length]; i++ ) {
            [s appendFormat: @"%c", b[i]];
        }
        NSLog(@"Data was: %@", s);
        scriptLogContents = @"";
    }
    return scriptLogContents;
}

// Returns the next line from the string of a tunnelblick log
// A \n is appended to the line if it doesn't end in one
// If the at the end of the string, nil is returned
-(NSString *) nextLineInTunnelblickString: (NSString * *) stringPtr fromPosition: (unsigned *) positionPtr
{
    NSString * line;
    unsigned stringLength = [*stringPtr length];
    NSRange stringRng = NSMakeRange(*positionPtr, stringLength - *positionPtr);
    NSRange lfRng = [*stringPtr rangeOfString: @"\n" options: 0 range: stringRng];
    if ( lfRng.location == NSNotFound) {
        if (  [*stringPtr length] != *positionPtr  ) {
            line = [*stringPtr substringWithRange: stringRng];
            line = [line stringByAppendingString: @"\n"];
            *positionPtr = stringLength;
        } else {
            return nil;
        }
    } else {
        NSRange lineRng = NSMakeRange(*positionPtr, lfRng.location + 1 - *positionPtr);
        line = [*stringPtr substringWithRange: lineRng];
        *positionPtr += lineRng.length;
    }
    
    return line;
}

// Returns the next line from the string of a script log
// The date/time in the line (if any) is converted to tunnelblickUserLogRepresentation
// A \n is appended to the line if it doesn't end in one
// If the line is not from the OpenVPN log, and the 1st character after the date/time is not a "*", one is inserted
// If the at the end of the string, nil is returned
-(NSString *) nextLineInScriptString: (NSString * *) stringPtr fromPosition: (unsigned *) positionPtr
{
    NSString * line;
    unsigned stringLength = [*stringPtr length];
    NSRange stringRng = NSMakeRange(*positionPtr, stringLength - *positionPtr);
    NSRange lfRng = [*stringPtr rangeOfString: @"\n" options: 0 range: stringRng];
    if ( lfRng.location == NSNotFound) {
        if (  [*stringPtr length] != *positionPtr  ) {
            line = [*stringPtr substringWithRange: stringRng];
            line = [line stringByAppendingString: @"\n"];
            *positionPtr = stringLength;
        } else {
            return nil;
        }
    } else {
        NSRange lineRng = NSMakeRange(*positionPtr, lfRng.location + 1 - *positionPtr);
        line = [*stringPtr substringWithRange: lineRng];
        *positionPtr += lineRng.length;
    }
    
    NSMutableString * newValue = [[[self convertDateInLine: line messageFlagsPtr: nil] mutableCopy] autorelease];
    if (  [newValue length] > TB_LOG_DATE_TIME_WIDTH + 1  ) {
        if (  [[newValue substringWithRange: NSMakeRange(TB_LOG_DATE_TIME_WIDTH - 1, 1)] isEqualToString: @" "]  ) {  // (Last digit of microseconds)
            if (  ! [[newValue substringWithRange: NSMakeRange(TB_LOG_DATE_TIME_WIDTH + 1, 1)] isEqualToString: @"*"]  ) {
                [newValue insertString: @"*" atIndex: TB_LOG_DATE_TIME_WIDTH + 1];
            }
        }
    }
    
    return [[newValue copy] autorelease];
}

// Returns the next lines from the string of an OpenVPN log that all have the same date/time
// The date/time in the line (if any) is converted to tunnelblickUserLogRepresentation
// A \n is appended to the lines if it doesn't end in one
// If at the end of the string, nil is returned
-(NSString *) nextLinesInOpenVPNString: (NSString * *) stringPtr fromPosition: (unsigned *) positionPtr
{
    NSMutableString * linesToReturn = [NSMutableString stringWithCapacity: 2000];
    unsigned lengthOfLinesUsed = 0;
    
    NSRange substringRng = NSMakeRange(*positionPtr, [*stringPtr length] - *positionPtr);
    
    NSString * originalLine;
    NSString * line;
    NSRange lfRng;
    BOOL firstLine = TRUE;
    NSString * dateTimeToAccept = nil;
    while (  NSNotFound != (lfRng = [*stringPtr rangeOfString: @"\n" options: 0 range: substringRng]).location  ) {
        
        if (  lfRng.location == substringRng.location  ) {
            lengthOfLinesUsed++;        // Just ignore empty lines
            substringRng.location++;
            substringRng.length--;
        } else {
            originalLine = [*stringPtr substringWithRange: NSMakeRange(substringRng.location, lfRng.location - substringRng.location + 1)];
			NSUInteger messageFlags = 0;
            line = [self convertDateInLine: originalLine messageFlagsPtr: &messageFlags];
            BOOL hasDateTime = ! [[line substringWithRange: NSMakeRange(0, 1)] isEqualToString: @" "];
            
            if (  firstLine) {
                if (  hasDateTime  ) {
                    dateTimeToAccept = [line substringWithRange: NSMakeRange(0, TB_LOG_DATE_TIME_WIDTH)];
                }
                
            } else {
                if (  dateTimeToAccept  ) {
                    if (  ! [dateTimeToAccept isEqualToString: [line substringWithRange: NSMakeRange(0, TB_LOG_DATE_TIME_WIDTH)]]  ) {
                        break;
                    }
                } else {
                    if (  hasDateTime  ) {
                        break;
                    }
                }
            }
            
            firstLine = FALSE;
            
            [linesToReturn appendString: line];
            
            unsigned originalLineLength = [originalLine length];
            lengthOfLinesUsed     += originalLineLength;
            substringRng.location += originalLineLength;
            substringRng.length   -= originalLineLength;
        }
    }
    
    unsigned lengthOfLines = [linesToReturn length];
    
    if (  lengthOfLines == 0  ) {
        return nil;
    }
    
    *positionPtr += lengthOfLinesUsed;
    
    return linesToReturn;
}

-(NSUInteger) logDateTimeLength: (NSString *) line {
	
	// Examines the start of line for a date/time and returns the length of the date/time as follows:
	//
	//		 0 if the start of the line is not a date/time
	//		17 if the date/time is of the form "iiiiiiiiii.ffffff " (seconds.microseconds since 1/1/1970)
	//		23 if the date/time is of the form "Sat Mar  9 08:10:08 2019 "
	//		24 if the date/time is of the form "Sat Mar 19 08:10:08 2019 "
	//                                          0123456789012345678901234
	if (  [line length] > 17  ) {
		NSString * dateTimeWithSeconds = [line substringWithRange: NSMakeRange(0, 10)];
		if ( [dateTimeWithSeconds containsOnlyCharactersInString: @"0123456789"]  ) {
			NSString * microseconds = [line substringWithRange: NSMakeRange(11, 6)];
			if ( [microseconds containsOnlyCharactersInString: @"0123456789"]  ) {
				if (  [[line substringWithRange: NSMakeRange(10, 1)] isEqualToString: @"."]  ) {
					if (  [[line substringWithRange: NSMakeRange(17, 1)] isEqualToString: @" "]  ) {
						return 17;
					}
				}
			}
		}
		
		if (  [line length] > 23  ) {
			if (   [[line substringWithRange: NSMakeRange(3,  1)] isEqualToString: @" "]
				&& [[line substringWithRange: NSMakeRange(7,  1)] isEqualToString: @" "]
				&& [[line substringWithRange: NSMakeRange(9,  1)] isEqualToString: @" "]
				&& [[line substringWithRange: NSMakeRange(12, 1)] isEqualToString: @":"]
				&& [[line substringWithRange: NSMakeRange(15, 1)] isEqualToString: @":"]
				&& [[line substringWithRange: NSMakeRange(18, 1)] isEqualToString: @" "]
				&& [[line substringWithRange: NSMakeRange(23, 1)] isEqualToString: @" "]
				)  {
				return 23;
			}
			
			if (  [line length] > 24  ) {
				if (   [[line substringWithRange: NSMakeRange(3,  1)] isEqualToString: @" "]
					&& [[line substringWithRange: NSMakeRange(7,  1)] isEqualToString: @" "]
					&& [[line substringWithRange: NSMakeRange(10, 1)] isEqualToString: @" "]
					&& [[line substringWithRange: NSMakeRange(13, 1)] isEqualToString: @":"]
					&& [[line substringWithRange: NSMakeRange(16, 1)] isEqualToString: @":"]
					&& [[line substringWithRange: NSMakeRange(19, 1)] isEqualToString: @" "]
					&& [[line substringWithRange: NSMakeRange(24, 1)] isEqualToString: @" "]
					) {
					return 24;
				}
			}
		}
	}
	
	return 0;
}

-(NSString *) convertDateInLine: (NSString *)   line
			    messageFlagsPtr: (NSUInteger *) messageFlagsPtr {
	
	// If line starts with the date/time , returns the line starting with the tunnelblickUserLogRepresentation of the date/time
	// else returns the line indented by TB_LOG_DATE_TIME_WIDTH + 1 spaces
	
	NSUInteger dateLength = [self logDateTimeLength: line];
	
	NSString * oldDate    = [line substringWithRange: NSMakeRange(0, dateLength)];
	NSString * restOfLine = [line substringFromIndex: dateLength];
	
	NSString * newDate;
	
	switch (dateLength) {
			
		case 0:
			
			// Line doesn't start with a date/time; indent it
			newDate = [@"" stringByPaddingToLength: TB_LOG_DATE_TIME_WIDTH + 1 withString: @" " startingAtIndex: 0];
			break;
			
		case 17:
			
			newDate = [[NSDate dateWithOpenvpnMachineReadableLogRepresentation: oldDate] tunnelblickUserLogRepresentation];
			
			// Extract message flags and remove them from the message
			if (  messageFlagsPtr) {
				if (  [restOfLine length] > 2  ) {
					restOfLine = [restOfLine substringFromIndex: 1];	// Skip space
					*messageFlagsPtr = [restOfLine unsignedIntValue];
					NSUInteger secondSpaceIx = [restOfLine rangeOfString: @" "].location;
					if (  secondSpaceIx != NSNotFound  ) {
						restOfLine = [restOfLine substringFromIndex: secondSpaceIx];
					}
				}
			}
			
			break;
			
		case 24:
			
			{
				NSDateFormatter * dateFormat = [[[NSDateFormatter alloc] init] autorelease];
				[dateFormat setDateFormat:@"EEE MMM dd HH:mm:ss yyyy"];
				NSDate * newDateD = [dateFormat dateFromString: oldDate];
				if (  newDateD  ) {
					newDate = [newDateD tunnelblickUserLogRepresentation];
				} else {
					NSLog(@"convertDateInLine: Invalid date:\n'%@'; expected format\n'%@'; line was:\n%@", oldDate, [dateFormat dateFormat], line);
					newDate = [[oldDate copy] autorelease];
				}
			}
			
			break;
			
  default:
			NSLog(@"convertDateInLine: Error: invalid dateLength %lu in line '%@'", (unsigned long)dateLength, line);
			newDate = [[oldDate copy] autorelease];
	}
	
	NSString * result = [NSString stringWithFormat: @"%@%@", newDate, restOfLine];
	return result;
}

// Appends a line to the log display
-(void) appendLine: (NSString *) line fromOpenvpnLog: (BOOL) isFromOpenvpnLog fromTunnelblickLog: (BOOL) isFromTunnelblickLog
{
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    OSStatus status = pthread_mutex_lock( &logStorageMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &logStorageMutex ) failed; status = %ld", (long) status);
        return;
    }
    NSTextStorage * logStore = [self logStorage];
    if (  logStore  ) {
        
        [logStore beginEditing];

        NSArray * lines = [line componentsSeparatedByString: @"\n"];
        NSUInteger lineCount = [lines count];
        if (  [line hasSuffix: @"\n"]  ) {
            lineCount--;
        }
        
		BOOL fromTunnelblick = ([line rangeOfString: TB_LOG_PREFIX].length != 0);
		
        NSUInteger i;
        for (  i=0; i < lineCount; i++) {
            NSString * singleLine = [[lines objectAtIndex: i] stringByAppendingString: @"\n"];
			[self popupAWarningForProblemSeenInLogLine: singleLine];
            NSMutableAttributedString * string = [self attributedStringFromLine: singleLine fromTunnelblick: fromTunnelblick];
            [logStore appendAttributedString: string];
        }
        
        [logStore endEditing];

        pthread_mutex_unlock( &logStorageMutex );
    } else {
        pthread_mutex_unlock( &logStorageMutex );
        if (  isFromTunnelblickLog  ) {
            [[self tbLog] appendString: line];
        }        
    }
    
    if (  [line length] > TB_LOG_DATE_TIME_WIDTH - 1  ) {
        if (  ! [[line substringWithRange: NSMakeRange(0, 1)] isEqualToString: @"\n"]  ) {
            if (  isFromOpenvpnLog  ) {
                [self setLastOpenvpnEntryTime: [line substringWithRange: NSMakeRange(0, TB_LOG_DATE_TIME_WIDTH)]];
            } else {
                [self setLastScriptEntryTime:  [line substringWithRange: NSMakeRange(0, TB_LOG_DATE_TIME_WIDTH)]];
            }
        }
    }

    [self didAddLineToLogDisplay];
}

// We added a line to the log display -- if already displaying the maximum number of lines then remove some lines (i.e. scroll off the top)
-(void) didAddLineToLogDisplay
{
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    if (  [[self logStorage] length] > gMaximumLogSize  ) {
        [self pruneLog];
    }
}

-(void) pruneLog
{
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    if (  ! [NSThread isMainThread]  ) {
        [self performSelectorOnMainThread: @selector(pruneLog) withObject: nil waitUntilDone: NO];
        return;
    }
    
    // Find the tenth LF, and remove starting after that, to preserve the first ten lines of the log

    OSStatus status = pthread_mutex_lock( &logStorageMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &logStorageMutex ) failed; status = %ld", (long) status);
        return;
    }
    NSTextStorage * logStore = [self logStorage];
    if (  logStore  ) {
        [logStore beginEditing];
        
        NSString * text = [logStore string];
        
        // Remove 10% of the contents of the display, or 100 chars, whichever is greater
        NSUInteger charsToRemove = [text length] / 10;
        if (  charsToRemove < 100  ) {
            charsToRemove = 100;
        }
        
        NSUInteger start = [self indexAfter: NUMBER_OF_LINES_TO_KEEP_AT_START_OF_LOG
                                     string: @"\n" inString: text range: NSMakeRange(0, [text length])];
        
        if (  start != NSNotFound  ) {
            // Find the first LF after the stuff we need to delete and delete up to that
            NSUInteger end = [self indexAfter: 1 string: @"\n" inString: text range: NSMakeRange(start + charsToRemove, [text length] - start - charsToRemove)];
            if (  end != NSNotFound  ) {
                if (  start < end  ) {
                    NSRange rangeToDelete = NSMakeRange(start, end - start);
                    NSString * replacementLine = [NSString stringWithFormat: @"\n%@ %@Some entries have been removed because the log is too long\n\n",
												  [@"" stringByPaddingToLength: TB_LOG_DATE_TIME_WIDTH withString: @" " startingAtIndex: 0],
												  TB_LOG_PREFIX];
                    [logStore replaceCharactersInRange: rangeToDelete withString: replacementLine];
                }
            }
        }
            
        [logStore endEditing];
    }
    
    pthread_mutex_unlock( &logStorageMutex );
}

// Invoked when either log file has changed.
-(void) watcher: (UKKQueue *) kq receivedNotification: (NSString *) nm forPath: (NSString *) fpath
{
	(void) kq;
	(void) nm;
	
    if (  gShuttingDownWorkspace || ignoreChangeRequests  ) {
        return;
    }
    
    // Do some primitive throttling -- only queue three requests per second
    long rightNow = (long)floor([NSDate timeIntervalSinceReferenceDate]);
    if (  rightNow == secondWeLastQueuedAChange  ) {
        numberOfRequestsInThatSecond++;
        if (  numberOfRequestsInThatSecond > 3) {
            if (  ! [self watchdogTimer]  ) {
                // Set a timer to queue a request later. (This will happen at most once per second.)
                [watchdogTimer invalidate];
                [self setWatchdogTimer: [NSTimer scheduledTimerWithTimeInterval: (NSTimeInterval) 1.0
                                                                         target: self
                                                                       selector: @selector(watchdogTimedOutHandler:)
                                                                       userInfo: fpath
                                                                        repeats: NO]];
                [watchdogTimer tbSetTolerance: -1.0];
            }
            return;
        }
    } else {
        secondWeLastQueuedAChange    = rightNow;
        numberOfRequestsInThatSecond = 0;
    }

    if (  [self monitorQueue]  ) {
        if (  [[[fpath stringByDeletingPathExtension] pathExtension] isEqualToString: @"openvpn"]  ) {
            [self performSelectorOnMainThread: @selector(openvpnLogChanged) withObject: nil waitUntilDone: YES];
        } else {
            [self performSelectorOnMainThread: @selector(scriptLogChanged) withObject: nil waitUntilDone: YES];
        }
    }
}

-(void) watchdogTimedOutHandler: (NSTimer *) timer
{
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    [self setWatchdogTimer: nil];
    
    NSString * fpath = [timer userInfo];
    
    if (  [self monitorQueue]  ) {
        if (  [[[fpath stringByDeletingPathExtension] pathExtension] isEqualToString: @"openvpn"]  ) {
            [self performSelectorOnMainThread: @selector(openvpnLogChanged) withObject: nil waitUntilDone: YES];
        } else {
            [self performSelectorOnMainThread: @selector(scriptLogChanged) withObject: nil waitUntilDone: YES];
        }
    }

}

-(void) openvpnLogChanged
{
    if (  ! ignoreChangeRequests  ) {
        [self logChangedAtPath: [self openvpnLogPath] usePosition: &openvpnLogPosition fromOpenvpnLog: YES];
    }
}

-(void) scriptLogChanged
{
    if (  ! ignoreChangeRequests  ) {
        [self logChangedAtPath: [self scriptLogPath] usePosition: &scriptLogPosition fromOpenvpnLog: NO];
    }
}

-(void) logChangedAtPath: (NSString *) logPath usePosition: (unsigned long long *) logPositionPtr fromOpenvpnLog: (BOOL) isFromOpenvpnLog
{
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    // Return without doing anything if log file doesn't exist
    if (   ( ! logPath )
        || ( ! [gFileMgr fileExistsAtPath: logPath])  ) {
        return;
    }
    
    // MUTEX LOCK for the rest of this method
    OSStatus status = pthread_mutex_lock( &makingChangesMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &makingChangesMutex ) failed; status = %ld", (long) status);
        return;
    }
    
    if (  ignoreChangeRequests  ) {
        pthread_mutex_unlock( &makingChangesMutex );
        return;
    }
        
    // Go through the log file contents one line at a time
    NSString * logString = [self contentsOfPath: logPath  usePosition: logPositionPtr];
    if (  ! logString  ) {
        NSLog(@"logString is nil in logChangedAtPath: %@ usePosition: %llu fromOpenvpnLog: %s", logPath, *logPositionPtr, CSTRING_FROM_BOOL(isFromOpenvpnLog));
        pthread_mutex_unlock( &makingChangesMutex );
        return;
    }
    unsigned logStringPosition = 0;
    
    NSString * line;
    if (  isFromOpenvpnLog  ) {
        line = [self nextLinesInOpenVPNString: &logString fromPosition:  &logStringPosition];
    } else {
        line = [self nextLineInScriptString:   &logString fromPosition:  &logStringPosition];
    }
    
    while ( line ) {
        if (  gShuttingDownWorkspace  ) {
            pthread_mutex_unlock( &makingChangesMutex );
            return;
        }
        
        [self insertLine: line beforeTunnelblickEntries: isFromOpenvpnLog beforeOpenVPNEntries: NO fromOpenVPNLog: isFromOpenvpnLog fromTunnelblickLog: NO];
        if (  isFromOpenvpnLog  ) {
            line = [self nextLinesInOpenVPNString: &logString fromPosition:  &logStringPosition];
        } else {
            line = [self nextLineInScriptString:   &logString fromPosition:  &logStringPosition];
        }
    }
    
    pthread_mutex_unlock( &makingChangesMutex );
}

// Inserts a line into the log display at the "correct" position
// The "correct" order is that all OpenVPN log entries for a particular date/time come before
// any script log entries for that same time.
-(void)       insertLine: (NSString *) line
beforeTunnelblickEntries: (BOOL) beforeTunnelblickEntries
    beforeOpenVPNEntries: (BOOL) beforeOpenVPNEntries
          fromOpenVPNLog: (BOOL) isFromOpenVPNLog
      fromTunnelblickLog: (BOOL) isFromTunnelblickLog
{
    (void) isFromTunnelblickLog;
    
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    OSStatus status = pthread_mutex_lock( &logStorageMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &logStorageMutex ) failed; status = %ld", (long) status);
        return;
    }
    NSTextStorage * logStore = [self logStorage];
    if (  logStore  ) {
        NSString * text = [logStore string];
        
        NSString * lineTime;
        if (   [line length] < TB_LOG_DATE_TIME_WIDTH
            || [[line substringWithRange: NSMakeRange(0, 1)] isEqualToString: @" "]  ) {
            if (  isFromOpenVPNLog  ) {
                lineTime = [self lastOpenvpnEntryTime];
            } else {
                lineTime = [self lastScriptEntryTime];
            }
        } else {
            lineTime = [line substringWithRange: NSMakeRange(0, TB_LOG_DATE_TIME_WIDTH)];
            if (  isFromOpenVPNLog  ) {
                [self setLastOpenvpnEntryTime: lineTime];
            } else {
                [self setLastScriptEntryTime:  lineTime];
            }
        }
        
        NSRange textRng = NSMakeRange(0, [text length]);
        
        // Special case: Nothing in log. Just append to it.
        if (  textRng.length == 0  ) {
            [self insertLogEntry: line atIndex: textRng.length];
            pthread_mutex_unlock( &logStorageMutex );
            
            [self setLastEntryTime: lineTime];
            [self didAddLineToLogDisplay];
            return;
        }
        
        // Special case: time is the same or greater than last entry in the log. Just append to it.
        NSComparisonResult result = [[self lastEntryTime] compare: lineTime];
        if (  result != NSOrderedDescending  ) {
            [self insertLogEntry: line atIndex: textRng.length];
            pthread_mutex_unlock( &logStorageMutex );
            
            [self setLastEntryTime: lineTime];
            [self didAddLineToLogDisplay];
            return;
        }
        
        // Find the end of the NUMBER_OF_LINES_TO_KEEP_AS_TUNNELBLICK_ENTRIES_AT_START_OF_LOG-th line
        unsigned long start = (unsigned long) [self indexAfter: NUMBER_OF_LINES_TO_KEEP_AS_TUNNELBLICK_ENTRIES_AT_START_OF_LOG
                                     string: @"\n" inString: text range: NSMakeRange(0, [text length])];
        if (  start == NSNotFound  ) {
            start = [text length];  // Don't have three lines yet, so don't insert before any of them
        }

        // Search backwards through the display
        NSRange currentLineRng = [self rangeOfLineBeforeLineThatStartsAt: textRng.length inString: text after: start];
        unsigned numberOfLinesSkippedBackward = 0;
        
        while (  currentLineRng.length != 0  ) {
            NSComparisonResult result = (  [text length] < (currentLineRng.location + TB_LOG_DATE_TIME_WIDTH)
                                         ? NSOrderedAscending
                                         : [lineTime compare: [text substringWithRange: NSMakeRange(currentLineRng.location, TB_LOG_DATE_TIME_WIDTH)]]);
            
            if (  result == NSOrderedDescending  ) {
                
                [self insertLogEntry: line atIndex: currentLineRng.location + currentLineRng.length];
                pthread_mutex_unlock( &logStorageMutex );
                
                [self didAddLineToLogDisplay];
                return;
            }
            
            if (   (result == NSOrderedSame)
                && ( ! (beforeTunnelblickEntries && beforeOpenVPNEntries) )  ) {
                BOOL currentFromOpenVPN = TRUE;
                if ( currentLineRng.length > TB_LOG_DATE_TIME_WIDTH + 1  ) {
                    currentFromOpenVPN = ! [[text substringWithRange: NSMakeRange(currentLineRng.location + TB_LOG_DATE_TIME_WIDTH + 1, 1)] isEqualToString: @"*"];
                }
                if (  ! (beforeTunnelblickEntries ^ currentFromOpenVPN)  ) {
                    if (  numberOfLinesSkippedBackward == 0  ) {
                        [self insertLogEntry: line atIndex: textRng.length];
                        pthread_mutex_unlock( &logStorageMutex );
                        
                        [self setLastEntryTime: lineTime];
                        [self didAddLineToLogDisplay];
                        return;
                    } else {
                        [self insertLogEntry: line atIndex: currentLineRng.location + currentLineRng.length];
                        pthread_mutex_unlock( &logStorageMutex );
                        
                        [self didAddLineToLogDisplay];
                        return;
                    }
                }
                if (  ! beforeTunnelblickEntries  ) {
                    if (  numberOfLinesSkippedBackward == 0  ) {
                        [self insertLogEntry: line atIndex: textRng.length];
                        pthread_mutex_unlock( &logStorageMutex );
                        
                        [self setLastEntryTime: lineTime];
                        [self didAddLineToLogDisplay];
                        return;
                    } else {
                        [self insertLogEntry: line atIndex: currentLineRng.location + currentLineRng.length];
                        pthread_mutex_unlock( &logStorageMutex );
                        
                        [self didAddLineToLogDisplay];
                        return;
                    }
                }
            }
            
            currentLineRng = [self rangeOfLineBeforeLineThatStartsAt: currentLineRng.location inString: text after: start];
            numberOfLinesSkippedBackward++;
        }
        
        [self insertLogEntry: line atIndex: currentLineRng.location];
		pthread_mutex_unlock( &logStorageMutex );
    }
    
    [self didAddLineToLogDisplay];
}

// Returns an NSRange for the previous line
// Considers the "previous line" to include all lines with no date/time
-(NSRange) rangeOfLineBeforeLineThatStartsAt: (unsigned long) lineStartIndex inString: (NSString *) text after: (unsigned long) start
{
    if (  lineStartIndex <= start  ) {
        return NSMakeRange(start, 0);
    }
    
    unsigned long justPastEnd = lineStartIndex;
    
    NSRange currentLineRng;
    do {
        NSRange LfRng = [text rangeOfString: @"\n" options: NSBackwardsSearch range: NSMakeRange(0, lineStartIndex - 1)];
        if (  LfRng.length == 0  ) {
            // Only one line in log
            currentLineRng = NSMakeRange(0, justPastEnd);
            return currentLineRng;
        }
        // More than one line in log
        currentLineRng = NSMakeRange(LfRng.location + 1, justPastEnd - LfRng.location - 1);
        lineStartIndex = currentLineRng.location;
    } while (   (currentLineRng.length == 1)
			 || [[text substringWithRange: NSMakeRange(currentLineRng.location, 1)] isEqualToString: @" "]  );
    
    return currentLineRng;
}

// Returns a path for a script log file
// It is composed of a prefix, the configuration path with "-" replaced by "--" and "/" replaced by "-S", and an extension of ".script.log"
//
// If the configuration file is in the home folder, we pretend it is in /Users/username instead (just for the purpose
// of creating the filename -- we never try to access /Users/username...). We do this because
// the scripts have access to the username, but don't have access to the actual location of the home folder, and the home
// folder may be located in a non-standard location (on a remote volume for example).
-(NSString *) constructScriptLogPath
{
    NSMutableString * logBase;
    if (  [[self configurationPath] hasPrefix: [NSHomeDirectory() stringByAppendingString: @"/"]]  ) {
        logBase = [[[NSString stringWithFormat: @"/Users/%@%@", NSUserName(), [[self configurationPath] substringFromIndex: [NSHomeDirectory() length]]] mutableCopy] autorelease];
    } else {
        logBase = [[[self configurationPath] mutableCopy] autorelease];
    }
    
    if (  [[[self configurationPath] pathExtension] isEqualToString: @"tblk"]) {
        [logBase appendString: @"/Contents/Resources/config.ovpn"];
    }
    
    [logBase replaceOccurrencesOfString: @"-" withString: @"--" options: 0 range: NSMakeRange(0, [logBase length])];
    [logBase replaceOccurrencesOfString: @"/" withString: @"-S" options: 0 range: NSMakeRange(0, [logBase length])];
    NSString * returnVal = [NSString stringWithFormat: @"%@/%@.script.log", L_AS_T_LOGS, logBase];
    return returnVal;
}

// Returns a path for an OpenVPN log file.
// It is composed of a prefix, the configuration path with "-" replaced by "--" and "/" replaced by "-S" , and extensions of
//      * an underscore-separated list of the values for useScripts, skipScrSec, cfgLocCode, noMonitor, and bitMask
//      * the port number;
//      * "openvpn"; and
//      * "log"
// So what we actually do is search for a file with the specified encoded configuration path, and return the path to that file.
//
// If the configuration file is in the home folder, we pretend it is in /Users/username instead (just for the purpose
// of creating the filename -- we never try to access /Users/username...). We do this because
// the scripts have access to the username, but don't have access to the actual location of the home folder, and the home
// folder may be located in a non-standard location (on a remote volume for example).
-(NSString *) constructOpenvpnLogPath
{
    NSMutableString * logBase;
    if (  [[self configurationPath] hasPrefix: NSHomeDirectory()]  ) {
        logBase = [[[NSString stringWithFormat: @"/Users/%@%@", NSUserName(), [[self configurationPath] substringFromIndex: [NSHomeDirectory() length]]] mutableCopy] autorelease];
    } else {
        logBase = [[[self configurationPath] mutableCopy] autorelease];
    }
    
    if (  [[logBase pathExtension] isEqualToString: @"tblk"]  ) {
        [logBase appendString: @"/Contents/Resources/config.ovpn"];
    }
    
    [logBase replaceOccurrencesOfString: @"-" withString: @"--" options: 0 range: NSMakeRange(0, [logBase length])];
    [logBase replaceOccurrencesOfString: @"/" withString: @"-S" options: 0 range: NSMakeRange(0, [logBase length])];
    NSString * logPathPrefix = [NSString stringWithFormat: @"%@/%@", L_AS_T_LOGS, logBase];

    NSString * filename;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: L_AS_T_LOGS];
    while (  (filename = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        NSString * oldFullPath = [L_AS_T_LOGS stringByAppendingPathComponent: filename];
        if (  [oldFullPath hasPrefix: logPathPrefix]  ) {
            if (   [[filename pathExtension] isEqualToString: @"log"]
                && [[[filename stringByDeletingPathExtension] pathExtension] isEqualToString: @"openvpn"]  ) {
                return [[oldFullPath copy] autorelease];
            }
        }
    }
    
    return nil;
}

@end
