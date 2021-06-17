/*
 * Copyright 2011, 2012, 2013, 2016, 2019 Jonathan K. Bullard. All rights reserved.
 *
 *  This file is part of Tunnelblick.
 *
 *  Tunnelblick is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 3
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


#import <Foundation/Foundation.h>
#import <signal.h>

#import "defines.h"
#import "NSDate+TB.h"
#import "NSFileManager+TB.h"

NSAutoreleasePool * gPool;

void appendLog(NSString * msg);

void restoreItems (NSArray  * itemsToRestore,
                   NSString * currentVpnDNS,
                   NSString * currentVpnWINS,
                   NSString * postVpnDNS,
                   NSString * postVpnWINS,
                   NSString * psid,
				   BOOL		  useSetupKeysToo);

NSString * scutilCommandValue(NSString * value);

NSString * getChanges(NSDictionary * charsAndKeys, NSString * current, NSString * preVpn, NSString * postVpn);

NSString * getKeyFromScDictionary(NSString * key, NSString * dictionary);

NSString * getScKey(NSString * key);

void scCommand(NSString * command);

NSString * trimWhitespace(NSString * s);

NSString * settingOfInterest(NSString * settingString, 
                             NSString * key);

NSString * standardizedString(NSString * s,
                              NSRange r);

NSRange rangeOfItemInString(NSString * item,
                            NSString * s);

NSRange rangeOfContentsOfBlock(NSString * s,
                               NSRange r);

NSString * gLogPath;

// Call dumpMsg to put a debugging messages to a newly-created file in /tmp
// (This can be done even before gLogPath is set up with the Tunnelblick log)
void dumpMsg(NSString * msg) {
    static int msgNum = 0;
    NSString * filePath = [NSString stringWithFormat: @"/tmp/Tunnelblick-process-network-changes-%d.txt", msgNum++];
    NSFileManager * fm = [[[NSFileManager alloc] init] autorelease];
    [fm tbRemoveFileAtPath: filePath handler: nil];
    const char * bytes = [msg UTF8String];
    [fm createFileAtPath: filePath contents: [NSData dataWithBytes: bytes length: strlen(bytes)] attributes: nil];
}    

int main (int argc, const char * argv[])
{
	(void) argv;
	
    gPool = [[NSAutoreleasePool alloc] init];
    
    if (  argc != 1  ) {
        fprintf(stderr,
                "Processes network configuration changes for Tunnelblick\n\n"
                
                "Usage:\n\n"
                "    process-network-changes\n\n"
                
                "The 'up.tunnelblick.sh' script must have been run before invoking process-network-changes,\n"
                "because it sets a system configuration key with values that are required by this program.\n\n"
                
                
                "Returns 0 if no problems occcurred\n"
                "          otherwise a diagnostic message is output to stderr");
        [gPool drain];
        exit(EXIT_FAILURE);
    }
    
    // Get settings saved by client.up.tunnelblick.sh
    NSString * openvpnSetup = getScKey(@"State:/Network/OpenVPN");
    NSString * logFile      = getKeyFromScDictionary(@"ScriptLogFile"      , openvpnSetup);
    NSString * process      = getKeyFromScDictionary(@"PID"                , openvpnSetup);
    NSString * psid         = getKeyFromScDictionary(@"Service"            , openvpnSetup);
    NSString * actions      = getKeyFromScDictionary(@"IgnoreOptionFlags"  , openvpnSetup);
    NSString * useSetupKeys = getKeyFromScDictionary(@"bAlsoUsingSetupKeys", openvpnSetup);
    
    gLogPath = [logFile copy];
    
    if (  ! [[actions substringWithRange: NSMakeRange(0, 2)] isEqualToString: @"-p"]  ) {
        appendLog([NSString stringWithFormat: @"Invalid actions = '%@'; must start with '-p'", actions]);
        [gPool drain];
        exit(EXIT_FAILURE);
    }
    
	BOOL useSetupKeysToo = [useSetupKeys isEqualToString: @"true"];

    // Get current network settings, settings before the VPN was set up, and settings after the VPN was set up
    NSString * preVpn      = [NSString stringWithFormat: @"%@\n%@", getScKey(@"State:/Network/OpenVPN/OldDNS"), getScKey(@"State:/Network/OpenVPN/OldSMB")];
    NSString * currentDNS  = getScKey(@"State:/Network/Global/DNS");
    NSString * currentWINS = getScKey(@"State:/Network/Global/SMB");
    NSString * current     = [NSString stringWithFormat: @"%@\n%@", currentDNS, currentWINS];
    NSString * postVpnDNS  = getScKey(@"State:/Network/OpenVPN/DNS");
    NSString * postVpnWINS = getScKey(@"State:/Network/OpenVPN/SMB");
    NSString * postVpn     = [NSString stringWithFormat: @"%@\n%@", postVpnDNS, postVpnWINS];
    
    // Map between characters in 'actions' and System Configuration keys
    NSDictionary * charsAndKeys = [NSDictionary dictionaryWithObjectsAndKeys:
                                   @"DomainName",      @"d",
                                   @"ServerAddresses", @"a",
                                   @"SearchDomains",   @"s",
                                   @"NetBIOSName",     @"n",
                                   @"WINSAddresses",   @"g",
                                   @"Workgroup",       @"w",
                                   @"DomainName",      @"D",
                                   @"ServerAddresses", @"A",
                                   @"SearchDomains",   @"S",
                                   @"NetBIOSName",     @"N",
                                   @"WINSAddresses",   @"G",
                                   @"Workgroup",       @"W",
                                   nil];
    
    NSString * changes = getChanges(charsAndKeys, current, preVpn, postVpn);
    
    unsigned i;
    NSString * act = @"";
    NSMutableArray * itemsToRestore = [NSMutableArray arrayWithCapacity:6];
    for (  i=2; i<[actions length]; i++  ) {
        NSString * ch = [actions substringWithRange: NSMakeRange(i, 1)];
        if (  [ch isEqualToString: @"t"]  ) {
            if (  ! [act isEqualToString: @""] ) {
                appendLog([NSString stringWithFormat: @"'t' action must come first; actions = '%@'", actions]);
                [gPool drain];
                exit(EXIT_FAILURE);
            }
            act = @"restart";
        } else if  (  [ch isEqualToString: @"r"]  ) {
            act = @"restore";
        } else {
            if (  [act isEqualToString: @""] ) {
                appendLog([NSString stringWithFormat: @"'t' or 'r' action must come first; actions = '%@'", actions]);
                [gPool drain];
                exit(EXIT_FAILURE);
            }
            NSString * itemName = [charsAndKeys objectForKey: ch];
            if (  ! itemName  ) {
                appendLog([NSString stringWithFormat: @"Unknown character '%@' in actions = '%@'", ch, actions]);
                [gPool drain];
                exit(EXIT_FAILURE);
            }
            if (  ([changes rangeOfString: ch].length) != 0) {
                if (  [act isEqualToString: @"restart"]  ) {
                    // Restart the connection
                    appendLog([NSString stringWithFormat: @"%@ changed; sending USR1 to OpenVPN (process ID %@) to restart the connection.", itemName, process]);
                    sleep(1);   // sleep so log entry is displayed before OpenVPN messages about the restart
                    pid_t process_num = [process intValue];
                    kill(process_num, SIGUSR1);
                    [gPool drain];
                    exit(EXIT_SUCCESS);
                } else {
                    [itemsToRestore addObject: itemName];// Add the item to the list of items to restore
                }
            }
        }
    }
    
    if (  [itemsToRestore count] == 0  ) {
        if (  [changes length] != 0  ) {
            NSMutableArray * changedItemNames = [[[NSMutableArray alloc] initWithCapacity: 6] autorelease];
            for (i=0; i<[changes length]; i++) {
                NSString * ch = [changes substringWithRange:NSMakeRange(i, 1)];
                NSString * itemName = [charsAndKeys objectForKey: ch];
                if (  ! [changedItemNames containsObject: itemName]  ) {
                    [changedItemNames addObject: itemName];
                }
            }
            NSMutableString * logMessage = [NSMutableString stringWithFormat: @"Ignored change to %@", [changedItemNames objectAtIndex: 0]];
            for (i=1; i<[changedItemNames count]; i++) {
                [logMessage appendFormat: @" and %@", [changedItemNames objectAtIndex: i]];
            }
            appendLog(logMessage);
        }
    } else {
        NSMutableString * restoreList = [[[NSMutableString alloc] initWithCapacity: 100] autorelease];
        for (  i=0; i<[itemsToRestore count]; i++  ) {
            [restoreList appendFormat: @"%@, ", [itemsToRestore objectAtIndex: i]];
        }
        NSString * msg = [NSString stringWithFormat: @"Restoring %@ to post-VPN value%@",
                          [restoreList substringToIndex: [restoreList length] - 2],
                          ([itemsToRestore count] == 1 ? @"" :@"s")];
        appendLog(msg);
        restoreItems(itemsToRestore, currentDNS, currentWINS, postVpnDNS, postVpnWINS, psid, useSetupKeysToo);
    }

    [gPool drain];
    exit(EXIT_SUCCESS);
}    

void appendLog(NSString * msg)
{
    NSString * fullMsg = [NSString stringWithFormat:@"%@ %@process-network-changes: %@\n",
						  [[NSDate date] openvpnMachineReadableLogRepresentation], TB_LOG_PREFIX, msg];
    NSFileHandle * handle = [NSFileHandle fileHandleForWritingAtPath: gLogPath];
    [handle seekToEndOfFile];
    const char * bytes = [fullMsg UTF8String];
    [handle writeData: [NSData dataWithBytes: bytes length: strlen(bytes)]];
    [handle closeFile];
}

void restoreItems (NSArray * itemsToRestore, NSString * currentVpnDNS, NSString * currentVpnWINS, NSString * postVpnDNS, NSString * postVpnWINS, NSString * psid, BOOL useSetupKeysToo)
{
    NSArray * dnsSubkeyList  = [NSArray arrayWithObjects: @"DomainName",  @"ServerAddresses", @"SearchDomains", nil];
    NSArray * winsSubkeyList = [NSArray arrayWithObjects: @"NetBIOSName", @"WINSAddresses",   @"Workgroup",     nil];
    
    // Construct one string with scutil sub-commands to restore DNS settings, and another to restore WINS settings
    NSMutableString * scutilDnsCommands  = [NSMutableString stringWithCapacity:1000];
    NSMutableString * scutilWinsCommands = [NSMutableString stringWithCapacity:1000];

    NSEnumerator * e = [itemsToRestore objectEnumerator];
    NSString * itemKey;
    while (  (itemKey = [e nextObject])  ) {
        if (   [dnsSubkeyList containsObject: itemKey]  ) {
            NSString * value = getKeyFromScDictionary(itemKey, currentVpnDNS);          // Remove current item if it exists
            if (  [value length] != 0  ) {
                [scutilDnsCommands  appendFormat: @"d.remove %@\n", itemKey];
            }
            value = getKeyFromScDictionary(itemKey, postVpnDNS);                        // Restore post-VPN value
            if (  [value length] != 0  ) {
                value = scutilCommandValue(value);
                [scutilDnsCommands  appendFormat: @"d.add %@ %@\n", itemKey, value];
            }
        } else if (   [winsSubkeyList containsObject: itemKey]  ) {
            NSString * value = getKeyFromScDictionary(itemKey, currentVpnWINS);
            if (  [value length] != 0  ) {
                [scutilWinsCommands  appendFormat: @"d.remove %@\n", itemKey];
            }
            value = getKeyFromScDictionary(itemKey, postVpnWINS);
            if (  [value length] != 0  ) {
                value = scutilCommandValue(value);
                [scutilWinsCommands  appendFormat: @"d.add %@ %@\n", itemKey, value];
            }
        }
    }
    
    NSMutableString * scutilCommands  = [NSMutableString stringWithCapacity:1000];

    // Append scutil commands to restore DNS settings
    if (  [scutilDnsCommands length] != 0  ) {
        NSString * scutilKey = [NSString stringWithFormat: @"State:/Network/Service/%@/DNS", psid];
        if (  [postVpnDNS length] == 0) {
            if ( [currentVpnDNS length] != 0  ) {
                [scutilCommands appendFormat: @"remove %@\n", scutilKey];
            }
        } else {
            if ( [currentVpnDNS length] == 0  ) {
                [scutilCommands appendFormat: @"d.init\n%@set %@\n", scutilDnsCommands, scutilKey];
            } else {
                [scutilCommands appendFormat: @"d.init\nget %@\n%@set %@\n", scutilKey, scutilDnsCommands, scutilKey];
            }
        }
        
        if (  useSetupKeysToo  ) {
            scutilKey = [NSString stringWithFormat: @"Setup:/Network/Service/%@/DNS", psid];
            if (  [postVpnDNS length] == 0) {
                if ( [currentVpnDNS length] != 0  ) {
                    [scutilCommands appendFormat: @"remove %@\n", scutilKey];
                }
            } else {
                if ( [currentVpnDNS length] == 0  ) {
                    [scutilCommands appendFormat: @"d.init\n%@set %@\n", scutilDnsCommands, scutilKey];
                } else {
                    [scutilCommands appendFormat: @"d.init\nget %@\n%@set %@\n", scutilKey, scutilDnsCommands, scutilKey];
                }
            }
        }
    }

    //Append scutil commands to restore WINS settings
    if (  [scutilWinsCommands length] != 0  ) {
        NSString * scutilKey = [NSString stringWithFormat: @"State:/Network/Service/%@/SMB", psid];
        if (  [postVpnWINS length] == 0) {
            if ( [currentVpnWINS length] != 0  ) {
                [scutilCommands appendFormat: @"remove %@\n", scutilKey];
            }
        } else {
            if ( [currentVpnWINS length] == 0  ) {
                [scutilCommands appendFormat: @"d.init\n%@set %@\n", scutilWinsCommands, scutilKey];
            } else {
                [scutilCommands appendFormat: @"d.init\nget %@\n%@set %@\n", scutilKey, scutilWinsCommands, scutilKey];
            }
        }
    }
    
    if (  [scutilCommands length] != 0) {
        scCommand(scutilCommands);
    }
}

NSString * scutilCommandValue(NSString * value)
{
    // Convert a value string from what is returned by scutil to what is needed by scutil's d.add subcommand
    // If the value is a scalar, it is just returned as is
    // If the value is an array, items are extracted and returned in a string prefixed by "* " and separated by a space
    
    if (  [value rangeOfString: @"<array>"].length == 0  ) {
        return value;
    }
    
    NSMutableString * resultValue = [[[NSMutableString alloc] initWithCapacity: 90] autorelease];
    [resultValue appendString: @"*"];
    NSString * restOfValue = value;
    NSRange rEOL = [restOfValue rangeOfString: @"\n"];  // Set up to skip the line that contains <array>
    while (  rEOL.length != 0  ) {
        restOfValue = [restOfValue substringFromIndex: rEOL.location + 1];                  // Skip to the next line
        rEOL = [restOfValue rangeOfString: @"\n"];
        NSString * thisValue;                                                               // Isolate the line
        if (  rEOL.length != 0) {
            thisValue = [restOfValue substringWithRange: NSMakeRange(0, rEOL.location)];
        } else {
            thisValue = restOfValue;
        }
        if (   [thisValue isEqualToString: @"}"]            // Done when see the brace that ends the array or an empty line or end of input
            || [thisValue isEqualToString: @""]  ) {
            break;
        }

        NSRange rColon = [thisValue rangeOfString: @": "];
        if (  rColon.length != 0  ) {
            thisValue = [thisValue substringFromIndex: rColon.location + 2];
        }
        [resultValue appendFormat: @" %@", thisValue];
    }

    return resultValue;
}

NSString * getChanges(NSDictionary * charsAndKeys, NSString * current, NSString * preVpn, NSString * postVpn)
{
    NSMutableString * changes = [[[NSMutableString alloc] initWithCapacity:12] autorelease];
    
    NSEnumerator * e = [charsAndKeys keyEnumerator];
    NSString * ch;
    while (  (ch = [e nextObject])  ) {
        if (  [ch isEqualToString: [ch lowercaseString]]  ) {
            NSString * key  = [charsAndKeys objectForKey: ch];
            NSString * cur  = getKeyFromScDictionary(key, current);
            NSString * pre  = getKeyFromScDictionary(key, preVpn);
            NSString * post = getKeyFromScDictionary(key, postVpn);
            if (  ! [cur isEqualToString: post]  ) {
                if (  [cur isEqualToString: pre]  ) {
                    appendLog([NSString stringWithFormat: @"%@ changed from\n%@\n to (pre-VPN)\n%@", key, post, cur]);
                    [changes appendString: ch];
                } else {
                    appendLog([NSString stringWithFormat: @"%@ changed from\n%@\n to\n%@\npre-VPN was\n%@", key, post, cur, pre]);
                    [changes appendString: [ch uppercaseString]];
                }
            }
        }        
    }
    
    return changes;
}

NSString * getKeyFromScDictionary(NSString * key, NSString * dictionary)
{
    NSRange r = rangeOfItemInString(key, dictionary);
    if (  r.length != 0  ) {
        NSString * returnKey = trimWhitespace([dictionary substringWithRange: r]);
        if (   [returnKey isEqualToString:
               @"<array> {\n"
               "0 : No\n"
               "1 : such\n"
               "2 : key\n"
               "}"]
            || [returnKey isEqualToString:
                @"<array> {\n"
                "0 :\n"
                "}"]
            ) {
            returnKey = @"";
        }
        return returnKey;        
    }
    return @"";
}

NSDictionary * getSafeEnvironment(void) {
	
	// (This is a pared-down version of the routine in SharedRoutines)
    //
    // Create our own environment to guard against Shell Shock (BashDoor) and similar vulnerabilities in bash
    //
    // This environment consists of several standard shell variables
    
    NSDictionary * env = [NSDictionary dictionaryWithObjectsAndKeys:
						  STANDARD_PATH,          @"PATH",
						  NSTemporaryDirectory(), @"TMPDIR",
						  NSUserName(),           @"USER",
						  NSUserName(),           @"LOGNAME",
						  NSHomeDirectory(),      @"HOME",
						  TOOL_PATH_FOR_BASH,     @"SHELL",
						  @"unix2003",            @"COMMAND_MODE",
						  nil];
    
    return env;
}

NSString * getScKey(NSString * key)
{
    // Returns a key read via scutil
    
    NSTask* task = [[[NSTask alloc] init] autorelease];
    
    [task setLaunchPath: TOOL_PATH_FOR_SCUTIL];
    
    NSPipe * errPipe = [[NSPipe alloc] init];
    [task setStandardError: errPipe];
    
    NSPipe * stdPipe = [[NSPipe alloc] init];
    [task setStandardOutput: stdPipe];
    
    NSPipe * inPipe   = [[NSPipe alloc] init];
    NSFileHandle * file = [inPipe fileHandleForWriting];
    NSString * scutilCommands = [NSString stringWithFormat: @"open\nshow %@\nquit\n", key];
    const char * bytes = [scutilCommands UTF8String];
    NSData * scutilCommandsAsData = [NSData dataWithBytes: bytes length: strlen(bytes)];
    [file writeData: scutilCommandsAsData];
    [file closeFile];
    [task setStandardInput: inPipe];
    
    NSArray * arguments = [NSArray array];
    [task setArguments: arguments];
    
    [task setCurrentDirectoryPath: @"/private/tmp"];
	[task setEnvironment: getSafeEnvironment()];
    [task launch];
    [task waitUntilExit];
    
    NSString * value = @""; // Value we are returning
    
    int status = [task terminationStatus];
    if (  status == 0  ) {
        file = [stdPipe fileHandleForReading];
        NSData * data = [file readDataToEndOfFile];
        [file closeFile];
        NSString * scutilOutput = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
		if (  scutilOutput == nil  ) {
			value = @"<dictionary> {\nTunnelblickKeyIsNotUTF-8 : true\n}\n";
		} else {
			value = standardizedString(scutilOutput, NSMakeRange(0, [scutilOutput length]));
			if (  [value isEqualToString: @"No such key\n"]  ) {
				value = @"<dictionary> {\nTunnelblickNoSuchKey : true\n}\n";
			}
		}
    }
    
    [errPipe release];
    [stdPipe release];
    [inPipe  release];
    
    return value;
}

void scCommand(NSString * command)
{
    // Executes an scutil command
    
    NSTask* task = [[[NSTask alloc] init] autorelease];
    
    [task setLaunchPath: TOOL_PATH_FOR_SCUTIL];
    
    NSPipe * errPipe = [[NSPipe alloc] init];
    [task setStandardError: errPipe];
    
    NSPipe * stdPipe = [[NSPipe alloc] init];
    [task setStandardOutput: stdPipe];
    
    NSPipe * inPipe   = [[NSPipe alloc] init];
    NSFileHandle * file = [inPipe fileHandleForWriting];
    NSString * scutilCommands = [NSString stringWithFormat: @"open\n%@\nquit\n", command];
    const char * bytes = [scutilCommands UTF8String];
    NSData * scutilCommandsAsData = [NSData dataWithBytes: bytes length: strlen(bytes)];
    [file writeData: scutilCommandsAsData];
    [file closeFile];
    [task setStandardInput: inPipe];
    
    NSArray * arguments = [NSArray array];
    [task setArguments: arguments];
    
    [task setCurrentDirectoryPath: @"/private/tmp"];
	[task setEnvironment: getSafeEnvironment()];
    [task launch];
    [task waitUntilExit];
    
    int status = [task terminationStatus];
    if (  status != 0  ) {
        file = [errPipe fileHandleForReading];
        NSData * data = [file readDataToEndOfFile];
        [file closeFile];
        NSString * errmsg = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
		if (  errmsg == nil  ) {
			appendLog(@"Could not interpret error message as UTF-8");
		} else {
			appendLog(errmsg);
		}
        [errPipe release];
        [stdPipe release];
        [inPipe  release];
        [gPool drain];
        exit(EXIT_FAILURE);
    }
    
    [errPipe release];
    [stdPipe release];
    [inPipe  release];
    
    return;
}

// Returns a string with each instance of whitespace replaced by a single space and whitespace removed from the start and end of each line.
// "Whitespace" includes spaces and tabs.
NSString * standardizedString(NSString * s, NSRange r)
{
    NSCharacterSet * ws = [NSCharacterSet whitespaceCharacterSet];
    NSCharacterSet * notWs = [ws invertedSet];
    
    // Collapse each instance of whitespace to a NUL
    NSMutableString * tempString = [[[s substringWithRange: r] mutableCopy] autorelease];
    NSRange rWS;
    while (  0 != (rWS = [tempString rangeOfCharacterFromSet: ws]).length  ) {
        NSRange rAfterWs = NSMakeRange(rWS.location + 1,
                                       [tempString length] - rWS.location - 1);
        NSRange rNotWs = [tempString rangeOfCharacterFromSet: notWs options: 0 range: rAfterWs];
        if (  rNotWs.length == 0  ) {
            rWS.length = [tempString length] - rWS.location;
        } else {
            rWS.length = rNotWs.location - rWS.location;
        }
        
        [tempString replaceCharactersInRange: rWS withString: @"\x00"];
    }
    
    // Change each NUL character to a single space
    [tempString replaceOccurrencesOfString: @"\x00" withString: @" " options: 0 range: NSMakeRange(0, [tempString length])];
    
    // Trim whitespace from each line
    NSArray * lines = [tempString componentsSeparatedByString: @"\n"];
    NSMutableArray * trimmedLines = [NSMutableArray arrayWithCapacity: [lines count]];
    NSString * line;
    NSEnumerator * lineEnum = [lines objectEnumerator];
    while (  (line = [lineEnum nextObject])  ) {
        [trimmedLines addObject: [line stringByTrimmingCharactersInSet: ws]];
    }
    
    return [trimmedLines componentsJoinedByString: @"\n"];    
}

NSString * trimWhitespace(NSString * s)
{
    NSCharacterSet * ws = [NSCharacterSet whitespaceCharacterSet];
    return [s stringByTrimmingCharactersInSet: ws];
}

NSString * settingOfInterest(NSString * settingString, NSString * key)
{
    NSRange r = rangeOfItemInString(settingString, key);
    NSString * setting = trimWhitespace([settingString substringWithRange: r]);
    
    if (  [setting isEqualToString:
           @"<array> {\n"
           "0 : No\n"
           "1 : such\n"
           "2 : key\n"
           "}"]  ) {
        setting = @"";
    }
    
    return setting;
}

// Returns the range of a specified item in a string
// DOES NOT handle quotation marks.
// DOES handle nested braces.
NSRange rangeOfItemInString(NSString * item, NSString * s)
{
    NSRange rResult = NSMakeRange(NSNotFound, 0);
    
    // Range of item we are looking for
    NSRange rItem = [s rangeOfString: [NSString stringWithFormat: @"%@ : ", item]];
    
    if (  rItem.length != 0  ) {
        
        // Range of the rest of the string
        NSRange rRestOfString;
        rRestOfString.location = rItem.location + rItem.length;
        rRestOfString.length = [s length] - rRestOfString.location;
        
        // Range of the rest of the line, not including the \n which terminates it
        // (If there is no \n in the rest of the string, the range of the rest of the string)
        NSRange rRestOfLine;
        NSRange rNewline = [s rangeOfString: @"\n" options: 0 range: rRestOfString];
        if (  rNewline.length == 0  ) {
            rRestOfLine = rRestOfString;
        } else {
            rRestOfLine = NSMakeRange(rRestOfString.location, rNewline.location - rRestOfString.location);
        }
        
        // Range of a "{" in the rest of the line
        NSRange rOpeningBrace = [s rangeOfString: @"{" options: 0 range: rRestOfLine];
        if (  rOpeningBrace.length != 0  ) {
            rResult = rangeOfContentsOfBlock(s, NSMakeRange(rOpeningBrace.location + 1, [s length] - rOpeningBrace.location - 1));
            // Adjust to start at the end of the item
            unsigned addedLength = rOpeningBrace.location - rRestOfLine.location + 1;
            rResult.location = rResult.location - addedLength;
            rResult.length =  rResult.length + addedLength;
        } else {
            rResult = rRestOfLine;
        }
    }
    
    return rResult;
}

// Given a string containing a block delimited by "{" and "}" and a range starting after the "{"
// Returns the contents of the block up to and including the terminating "}".
// DOES NOT handle quotation marks.
// DOES handle nested braces.

NSRange rangeOfContentsOfBlock(NSString * s, NSRange r)
{
    // Look through the string for a "}", but deal with nested "{...}" properly
    unsigned level = 1;
    NSRange rWorking = r;
    while (  level > 0  ) {
        // Find which is first, a "{" or a "}" 
        NSRange rOpenBrace =  [s rangeOfString: @"{" options: 0 range: rWorking];
        NSRange rCloseBrace = [s rangeOfString: @"}" options: 0 range: rWorking];
        if (  rOpenBrace.length == 0  ) {
            rOpenBrace.location = [s length];
        }
        if (  rCloseBrace.length == 0  ) {
            rCloseBrace.location = [s length];
        }
        if (  rOpenBrace.location == rCloseBrace.location  ) {
            // Neither "{" nor "}" appear -- problem!
            fprintf(stderr, "Unterminated '{' in\n%s", [s UTF8String]);
            [gPool drain];
            exit(EXIT_FAILURE);
        }
        if (  rOpenBrace.location < rCloseBrace.location  ) {
            // "{" comes first -- one level deeper
            level++;
            rWorking.location = rOpenBrace.location + 1;
            rWorking.length = [s length] - rWorking.location;
        } else {
            // "}" comes first -- one level shallower
            level--;
            rWorking.location = rCloseBrace.location + 1;
            rWorking.length = [s length] - rWorking.location;
        }
    }
    
    // Result is the contents up to and including the closing brace
    NSRange rResult = NSMakeRange(r.location, rWorking.location - r.location);
    
    return rResult;
}
