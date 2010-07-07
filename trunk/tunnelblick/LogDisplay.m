/*
 *  Copyright (c) 2010 Jonathan Bullard
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

#import "defines.h"
#import "LogDisplay.h"
#import "MenuController.h"

extern NSFileManager        * gFileMgr;

@interface LogDisplay() // PRIVATE METHODS

-(void)         appendLine:             (NSString *)            line
            fromOpenvpnLog:             (BOOL)                  isFromOpenvpnLog;

-(void)         insertLine:             (NSString *)            line
            fromOpenvpnLog:             (BOOL)                  isFromOpenvpnLog;

-(void)         didAddLineToLogDisplay;

-(NSString *)   contentsOfPath:         (NSString *)            logPath
                   usePosition:         (unsigned long long *)  logPosition;

-(NSString *)   convertDate:            (NSString *)            line;

-(NSString *)   constructOpenvpnLogPath;
-(NSString *)   constructScriptLogPath;
    
-(NSRange)      rangeOfLineBeforeLineThatStartsAt: (long)       lineStartIndex
                                         inString: (NSString *) text;

-(void)         loadLogs;

-(void)         logChangedAtPath:       (NSString *)            logPath
                     usePosition:       (unsigned long long *)  logPositionPtr
                  fromOpenvpnLog:       (BOOL)                  isFromOpenvpnLog;

-(void)         openvpnLogChanged;
-(void)         scriptLogChanged;

-(NSString *)   nextLineInString:       (NSString * *)          stringPtr
                    fromPosition:       (unsigned *)            positionPtr
                  fromOpenvpnLog:       (BOOL)                  isFromOpenvpnLog;

-(void)         watcher:                (UKKQueue *)            kq
   receivedNotification:                (NSString *)            nm
                forPath:                (NSString *)            fpath;

// Getters and Setters:
-(NSString *)   configurationPath;
-(NSString *)   lastOpenvpnEntryTime;
-(NSString *)   lastScriptEntryTime;
-(NSString *)   openvpnLogPath;
-(NSString *)   scriptLogPath;
-(void)         setLastOpenvpnEntryTime: (NSString *)           newValue;
-(void)         setLastScriptEntryTime: (NSString *)            newValue;
-(void)         setOpenvpnLogPath:      (NSString *)            newValue;
-(void)         setScriptLogPath:       (NSString *)            newValue;

@end

@implementation LogDisplay

-(LogDisplay *) initWithConfigurationPath: (NSString *) inConfigPath;
{
	if (  self = [super init]  ) {
        
        configurationPath = [inConfigPath copy];
        openvpnLogPath = nil;
        scriptLogPath = nil;

        monitorQueue = nil;
        
        lastOpenvpnEntryTime = @"0000-00-00 00:00:00";
        lastScriptEntryTime  = @"0000-00-00 00:00:00";
        
        openvpnLogPosition = 0;
        scriptLogPosition = 0;
        
        logStorage = [[NSTextStorage alloc] init];
        [self clear];
    }
    
    return self;
}

-(void) dealloc
{
    [monitorQueue release];
	[configurationPath release];
    [openvpnLogPath release];
    [scriptLogPath release];
	[logStorage release];
    [lastOpenvpnEntryTime release];
    [lastScriptEntryTime release];
    [super dealloc];
}

// Inserts the current date/time, a message, and a \n to the log display.
-(void)addToLog: (NSString *) text
{
    NSCalendarDate * date = [NSCalendarDate date];
    NSString * dateText = [NSString stringWithFormat:@"%@ %@\n",[date descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S"], text];

	[self insertLine: dateText fromOpenvpnLog: NO];
}

// Clears the log display, displaying only the header line
-(void) clear
{
    [logStorage deleteCharactersInRange: NSMakeRange(0, [logStorage length])];
    [self addToLog: [[NSApp delegate] openVPNLogHeader]];
    nLinesBeingDisplayed = 1;
    
    // Pretend that the line we just displayed came from OpenVPN so we will insert _after_ it
    [self setLastOpenvpnEntryTime: [self lastScriptEntryTime]];
    [self setLastScriptEntryTime: nil];
}

// Starts (or restarts) monitoring newly-created log files.
-(void) startMonitoringLogFiles
{
    openvpnLogPosition = 0;
    scriptLogPosition = 0;
    
    [self setOpenvpnLogPath: [self constructOpenvpnLogPath]];
    [self setScriptLogPath:  [self constructScriptLogPath]];

    [monitorQueue release];
    monitorQueue = [[UKKQueue alloc] init];

    [monitorQueue setDelegate: self];
    [monitorQueue setAlwaysNotify: YES];
    
    [self loadLogs];
    
    [monitorQueue addPathToQueue: [self openvpnLogPath]];
    [monitorQueue addPathToQueue: [self scriptLogPath]];
}

// Does the initial load of the logs, inserting entries from them in the "correct" chronological order.
// The "correct" order is that all OpenVPN log entries for a particular date/time come before
// any script log entries for that same time.
// Since the log files are in chronological order, we can and do append to (rather than insert into) the log display,
// which is much less processing intensive.
-(void) loadLogs
{
    NSString * openvpnString = [self contentsOfPath: [self openvpnLogPath] usePosition: &openvpnLogPosition];
    NSString * scriptString  = [self contentsOfPath: [self scriptLogPath]  usePosition: &scriptLogPosition];
    
    unsigned openvpnStringPosition = 0;
    unsigned scriptStringPosition  = 0;
    
    NSString * oLine = [self nextLineInString: &openvpnString fromPosition: &openvpnStringPosition fromOpenvpnLog: YES];
    NSString * sLine = [self nextLineInString: &scriptString  fromPosition: &scriptStringPosition  fromOpenvpnLog: NO];
    
    NSString * oLineDateTime = @"0000-00-00 00:00:00";
    NSString * sLineDateTime = @"0000-00-00 00:00:00";
    
    while (   (oLine != nil)
           || (sLine != nil)  ) {
        if (  oLine  ) {
            if (  sLine  ) {
                if (  ! [oLine hasPrefix: @" "]  ) {
                    oLineDateTime = [oLine substringToIndex: 19];
                }
                if (  ! [sLine hasPrefix: @" "]  ) {
                    sLineDateTime = [sLine substringToIndex: 19];
                }
                if (  [oLineDateTime compare: sLineDateTime] != NSOrderedDescending ) {
                    [self appendLine: oLine fromOpenvpnLog: YES];
                    oLine = [self nextLineInString: &openvpnString fromPosition: &openvpnStringPosition fromOpenvpnLog: YES];
                } else {
                    [self appendLine: sLine fromOpenvpnLog: NO];
                    sLine = [self nextLineInString: &scriptString fromPosition: &scriptStringPosition fromOpenvpnLog: NO];
                }
            } else {
                [self appendLine: oLine fromOpenvpnLog: YES];
                oLine = [self nextLineInString: &openvpnString fromPosition: &openvpnStringPosition fromOpenvpnLog: YES];
            }
        } else {
            [self appendLine: sLine fromOpenvpnLog: NO];
            sLine = [self nextLineInString: &scriptString fromPosition: &scriptStringPosition fromOpenvpnLog: NO];
        }
    }
}

-(NSString *) contentsOfPath: (NSString *) logPath usePosition: (unsigned long long *) logPosition
{
    // Open file, seek to current position, read to end of file, note new current position, close file
    NSFileHandle * file;
    if (  ! (file = [NSFileHandle fileHandleForReadingAtPath: logPath])  ) {
        NSLog(@"contentsOfPath: no such log file: %@", logPath);
        *logPosition = -1;
        return @"";
    }
    
    [file seekToFileOffset: *logPosition];
    NSData * data = [file readDataToEndOfFile];
    *logPosition = [file offsetInFile];
    [file closeFile];
    
    NSString * scriptLogContents = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
    return scriptLogContents;
}

// Returns the next line from the string
// The date/time in the line (if any) is converted to "YYYY-MM-DD HH:MM:SS" form
// A \n is appended to the line if it doesn't end in one
// If the line is not from the OpenVPN log, and the 1st character after the date/time is not a "*", one is inserted
// If the at the end of the string, nil is returned
-(NSString *) nextLineInString: (NSString * *) stringPtr fromPosition: (unsigned *) positionPtr fromOpenvpnLog: (BOOL) isFromOpenvpnLog
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
    
    if (  isFromOpenvpnLog  ) {
        return [self convertDate: line];
    }

    NSMutableString * newValue = [[[self convertDate: line] mutableCopy] autorelease];
    if (  [newValue length] > 19  ) {
        if (  [[newValue substringWithRange: NSMakeRange(18, 1)] isEqualToString: @" "]  ) {        // (Last digit of seconds)
            if (  ! [[newValue substringWithRange: NSMakeRange(20, 1)] isEqualToString: @"*"]  ) {
                [newValue insertString: @"*" atIndex: 20]; 
            }
        }
    }
        
    return [[newValue copy] autorelease];
}

// If a line starts with the date/time as "Day dd Mon HH:MM:SS YYYY", converts it to start with "YYYY-MM-DD HH:MM:SS "
// Otherwise the line is indented
-(NSString *) convertDate: (NSString *) line
{
    // Convert date/time to YYYY-MM-DD HH:MM:SS
    const char * cLogLine;
    const char * cRestOfLogLine;
    struct tm cTime;
    char cDateTimeStringBuffer[] = "1234567890123456789012345678901";
    cLogLine = [line UTF8String];
    cRestOfLogLine = strptime(cLogLine, "%c", &cTime);
    if (  cRestOfLogLine  ) {
        size_t timeLen = strftime(cDateTimeStringBuffer, 30, "%Y-%m-%d %H:%M:%S", &cTime);
        if (  timeLen  ) {
            line = [NSString stringWithFormat: @"%s%s", cDateTimeStringBuffer, cRestOfLogLine];
        } else {
            line = [NSString stringWithFormat: @"                                        %@", line];
        }
    } else {
        line = [NSString stringWithFormat: @"                                        %@", line];
    }
    
    return line;
}

// Appends a line to the log display
-(void) appendLine: (NSString *) line fromOpenvpnLog: (BOOL) isFromOpenvpnLog
{
    NSAttributedString * msgAS = [[[NSAttributedString alloc] initWithString: line] autorelease];
    [logStorage appendAttributedString: msgAS];
    
    if (  [line length] > 18 ) {
        if (  ! [[line substringWithRange: NSMakeRange(0, 1)] isEqualToString: @"\n"]  ) {
            if (  isFromOpenvpnLog  ) {
                [self setLastOpenvpnEntryTime: [line substringWithRange: NSMakeRange(0, 19)]];
            } else {
                [self setLastScriptEntryTime:  [line substringWithRange: NSMakeRange(0, 19)]];
            }
        }
    }

    [self didAddLineToLogDisplay];
}

// We added a line to the log display -- if already displaying the maximum number of lines then remove a line (i.e. scroll off the top)
-(void) didAddLineToLogDisplay
{
    nLinesBeingDisplayed++;
    if (  nLinesBeingDisplayed > MAX_LOG_DISPLAY_LINES  ) {
        NSString * text = [logStorage string];
        NSRange firstLF  = [text rangeOfString: @"\n"];
        NSRange firstLineRng = NSMakeRange(0, firstLF.location+1);
        [logStorage deleteCharactersInRange: firstLineRng];
        nLinesBeingDisplayed--;
    }
}

// Invoked when either log file has changed.
-(void) watcher: (UKKQueue *) kq receivedNotification: (NSString *) nm forPath: (NSString *) fpath {
    if (  [[[fpath stringByDeletingPathExtension] pathExtension] isEqualToString: @"openvpn"]  ) {
        [self performSelectorOnMainThread: @selector(openvpnLogChanged) withObject: nil waitUntilDone: YES];
    } else {
        [self performSelectorOnMainThread: @selector(scriptLogChanged) withObject: nil waitUntilDone: YES];
    }
}

-(void) openvpnLogChanged
{
    [self logChangedAtPath: [self openvpnLogPath] usePosition: &openvpnLogPosition fromOpenvpnLog: YES];
}

-(void) scriptLogChanged
{
    [self logChangedAtPath: [self scriptLogPath] usePosition: &scriptLogPosition fromOpenvpnLog: NO];
}

-(void) logChangedAtPath: (NSString *) logPath usePosition: (unsigned long long *) logPositionPtr fromOpenvpnLog: (BOOL) isFromOpenvpnLog
{
    // Return without doing anything if an error has occurred
    if (  *logPositionPtr == -1  ) {
        return;
    }
    
    // Return without doing anything if log file doesn't exist
    if (  ! [gFileMgr fileExistsAtPath: logPath]  ) {
        return;
    }
    
    // Go through the log file contents one line at a time
    NSString * logString = [self contentsOfPath: logPath  usePosition: logPositionPtr];
    unsigned logStringPosition = 0;
    
    NSString * line = [self nextLineInString: &logString fromPosition:  &logStringPosition fromOpenvpnLog: isFromOpenvpnLog];
    
    while ( line ) {
        [self insertLine: line fromOpenvpnLog: isFromOpenvpnLog];
        line = [self nextLineInString: &logString fromPosition:  &logStringPosition fromOpenvpnLog: isFromOpenvpnLog];
    }
}

// Inserts a line into the log display at the "correct" position
// The "correct" order is that all OpenVPN log entries for a particular date/time come before
// any script log entries for that same time.
-(void) insertLine: (NSString *) line fromOpenvpnLog: (BOOL) isFromOpenvpnLog
{
    NSString * text = nil;

    NSAttributedString * msgAS = [[[NSAttributedString alloc] initWithString: line] autorelease];

    if (  ! text  ) {
        text = [logStorage string];
    }
    
    NSString * lineDateTime;
    if (   [line length] < 19
        || [[line substringWithRange: NSMakeRange(0, 1)] isEqualToString: @" "]  ) {
        if (  isFromOpenvpnLog  ) {
            lineDateTime = [self lastOpenvpnEntryTime];
        } else {
            lineDateTime = [self lastScriptEntryTime];
        }
    } else {
        lineDateTime = [line substringWithRange: NSMakeRange(0, 19)];
        if (  isFromOpenvpnLog  ) {
            [self setLastOpenvpnEntryTime: lineDateTime];
        } else {
            [self setLastScriptEntryTime:  lineDateTime];
        }
    }

    NSRange textRng = NSMakeRange(0, [text length]);
    
    // Special case: Nothing in log. Just append to it.
    if (  textRng.length == 0  ) {
        [logStorage appendAttributedString: msgAS];
        [self didAddLineToLogDisplay];
        return;
    }
    
    // Search backwards through the display
    NSRange currentLineRng = [self rangeOfLineBeforeLineThatStartsAt: textRng.length inString: text];

    while (  currentLineRng.length != 0  ) {
        NSComparisonResult result = [lineDateTime compare: [text substringWithRange: NSMakeRange(currentLineRng.location, 19)]];
        
        if (  result == NSOrderedDescending  ) {
            [logStorage insertAttributedString: msgAS atIndex: currentLineRng.location + currentLineRng.length];
            [self didAddLineToLogDisplay];
            return;
        }
        
        if (  result == NSOrderedSame  ) {
            BOOL currentFromOpenVPN = TRUE;
            if ( currentLineRng.length > 20  ) {
                currentFromOpenVPN = ! [[text substringWithRange: NSMakeRange(currentLineRng.location+20, 1)] isEqualToString: @"*"];
            }
            if (  ! (isFromOpenvpnLog ^ currentFromOpenVPN)  ) {
                 [logStorage insertAttributedString: msgAS atIndex: currentLineRng.location + currentLineRng.length];
                [self didAddLineToLogDisplay];
                return;
            }
            if (  ! isFromOpenvpnLog  ) {
                [logStorage insertAttributedString: msgAS atIndex: currentLineRng.location + currentLineRng.length];
                [self didAddLineToLogDisplay];
                return;
            }
        }
        
        currentLineRng = [self rangeOfLineBeforeLineThatStartsAt: currentLineRng.location inString: text];
    }
    
    if (  [logStorage length] == 0  ) {
        [logStorage appendAttributedString: msgAS];
    } else {
        [logStorage insertAttributedString: msgAS atIndex: 0];
    }
    [self didAddLineToLogDisplay];
}

// Returns an NSRange for the previous line
// Considers the "previous line" to include all lines with no date/time
-(NSRange) rangeOfLineBeforeLineThatStartsAt: (long) lineStartIndex inString: (NSString *) text
{
    if (  lineStartIndex == 0  ) {
        return NSMakeRange(NSNotFound, 0);
    }
    
    long justPastEnd = lineStartIndex;
    
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
    } while (  [[text substringWithRange: NSMakeRange(currentLineRng.location, 1)] isEqualToString: @" "]  );
    
    return currentLineRng;
}

// Returns a path for a script log file
// It is composed of a prefix, the configuration path with "-" replaced by "--" and "/" replaced by "-S", and an extension of ".script.log"
-(NSString *) constructScriptLogPath
{
    NSMutableString * logPath = [[self configurationPath] mutableCopy];
    if (  [[[self configurationPath] pathExtension] isEqualToString: @"tblk"]) {
        [logPath appendString: @"/Contents/Resources/config.ovpn"];
    }
    [logPath replaceOccurrencesOfString: @"-" withString: @"--" options: 0 range: NSMakeRange(0, [logPath length])];
    [logPath replaceOccurrencesOfString: @"/" withString: @"-S" options: 0 range: NSMakeRange(0, [logPath length])];
    NSString * returnVal = [NSString stringWithFormat: @"%@/%@.script.log", LOG_DIR, logPath];
    [logPath release];
    return returnVal;
}

// Returns a path for an OpenVPN log file.
// It is composed of a prefix, the configuration path with "-" replaced by "--" and "/" replaced by "-S" , and extensions of
//      * an underscore-separated list of the values for useScripts, skipScrSec, cfgLocCode, noMonitor, and bitMask
//      * the port number;
//      * "openvpn"; and
//      * "log"
// So what we actually do is search for a file with the specified encoded configuration path, and return the path to that file.
-(NSString *) constructOpenvpnLogPath
{
    NSMutableString * encodedConfigPath = [[[self configurationPath] mutableCopy] autorelease];
    [encodedConfigPath replaceOccurrencesOfString: @"-" withString: @"--" options: 0 range: NSMakeRange(0, [encodedConfigPath length])];
    [encodedConfigPath replaceOccurrencesOfString: @"/" withString: @"-S" options: 0 range: NSMakeRange(0, [encodedConfigPath length])];
    NSString * logPathPrefix = [NSString stringWithFormat: @"%@/%@", LOG_DIR, encodedConfigPath];

    NSString * filename;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: LOG_DIR];
    while (  filename = [dirEnum nextObject]  ) {
        [dirEnum skipDescendents];
        NSString * oldFullPath = [LOG_DIR stringByAppendingPathComponent: filename];
        if (  [oldFullPath hasPrefix: logPathPrefix]  ) {
            if (   [[filename pathExtension] isEqualToString: @"log"]
                && [[[filename stringByDeletingPathExtension] pathExtension] isEqualToString: @"openvpn"]  ) {
                return [[oldFullPath copy] autorelease];
            }
        }
    }
    NSLog(@"constructOpenvpnLogPath: Cannot find OpenVPN log file for %@", [self configurationPath]);
    return nil;
}

//*********************************************************************************************************
// Getters and Setters:

-(NSString *) configurationPath
{
    return configurationPath;
}

-(NSString *) lastOpenvpnEntryTime
{
    return lastOpenvpnEntryTime;
}

-(NSString *) lastScriptEntryTime
{
    return lastScriptEntryTime;
}

-(NSString *) openvpnLogPath
{
    return openvpnLogPath;
}

-(NSString *) scriptLogPath
{
    return scriptLogPath;
}

-(NSTextStorage *) logStorage
{
    return logStorage;
}

-(void) setLastOpenvpnEntryTime: (NSString *) newValue
{
    [newValue retain];
    [lastOpenvpnEntryTime release];
    lastOpenvpnEntryTime = newValue;
}

-(void) setLastScriptEntryTime: (NSString *) newValue
{
    [newValue retain];
    [lastScriptEntryTime release];
    lastScriptEntryTime = newValue;
}

-(void) setOpenvpnLogPath: (NSString *) newValue
{
    [newValue retain];
    [openvpnLogPath release];
    openvpnLogPath = newValue;
}

-(void) setScriptLogPath: (NSString *) newValue
{
    [newValue retain];
    [scriptLogPath release];
    scriptLogPath = newValue;
}

@end
