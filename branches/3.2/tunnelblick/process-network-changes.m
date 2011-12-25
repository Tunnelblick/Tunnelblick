/*
 * Copyright 2011 Jonathan Bullard
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

NSAutoreleasePool * gPool;

void appendToLog(NSString * msg);

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

// Set gMsg and call dumpMsg to put a debugging messages to a newly-created file in /tmp
// (This can be done even before gLogPath is set up with the Tunnelblick log)
NSString * gMsg;
void dumpMsg() {
    static int msgNum = 0;
    NSString * filePath = [NSString stringWithFormat: @"/tmp/jkb-%d.txt", msgNum++];
    NSFileManager * fm = [[[NSFileManager alloc] init] autorelease];
    [fm removeFileAtPath: filePath handler: nil];
    [fm createFileAtPath: filePath contents: [NSData dataWithBytes: [gMsg UTF8String] length: [gMsg length]] attributes: nil];    
}    

int main (int argc, const char * argv[])
{
    gPool = [[NSAutoreleasePool alloc] init];
    
    if (  argc != 1  ) {
        fprintf(stderr,
                "Processes network configuration changes for Tunnelblick\n\n"
                
                "Usage:\n\n"
                "    process-network-changes\n\n"
                
                "The 'up.tunnelblick.sh' must have been run before invoking process-network-changes,\n"
                "because it sets a system configuration key with values that are required.\n\n"
                
                
                "Returns 0 if no problems occcurred\n"
                "          otherwise a diagnostic message is output to stderr");
        [gPool drain];
        exit(EXIT_FAILURE);
    }
    
    // Get settings saved by client.up.tunnelblick.sh
    NSString * openvpnSetup = getScKey(@"State:/Network/OpenVPN");
    NSString * logFile = getKeyFromScDictionary(@"ScriptLogFile"    , openvpnSetup);
    NSString * process = getKeyFromScDictionary(@"PID"              , openvpnSetup);
    NSString * psid    = getKeyFromScDictionary(@"Service"          , openvpnSetup);
    NSString * actions = getKeyFromScDictionary(@"IgnoreOptionFlags", openvpnSetup);
//gMsg = [NSString stringWithFormat: @"openvpnSetup = '%@'", openvpnSetup];
//dumpMsg();
//gMsg = [NSString stringWithFormat: @"logFile = '%@'", logFile];
//dumpMsg();
//gMsg = [NSString stringWithFormat: @"process = '%@'", process];
//dumpMsg();
//gMsg = [NSString stringWithFormat: @"psid    = '%@'", psid];
//dumpMsg();
//gMsg = [NSString stringWithFormat: @"actions = '%@'", actions];
//dumpMsg();
    
    gLogPath = [logFile copy];
    
    if (  ! [[actions substringWithRange: NSMakeRange(0, 2)] isEqualToString: @"-a"]  ) {
        appendToLog([NSString stringWithFormat: @"Invalid actions = '%@'; must start with '-a'", actions]);
        [gPool drain];
        exit(EXIT_FAILURE);
    }
    
    // Get current network settings, settings before the VPN was set up, and settings after the VPN was set up
    NSString * current  = [NSString stringWithFormat: @"%@\n%@", getScKey(@"State:/Network/Global/DNS"    ), getScKey(@"State:/Network/Global/SMB"    )];
    NSString * preVpn   = [NSString stringWithFormat: @"%@\n%@", getScKey(@"State:/Network/OpenVPN/OldDNS"), getScKey(@"State:/Network/OpenVPN/OldSMB")];
    NSString * postVpn  = [NSString stringWithFormat: @"%@\n%@", getScKey(@"State:/Network/OpenVPN/DNS"   ), getScKey(@"State:/Network/OpenVPN/SMB"   )];
    
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
    
    // Map between a System Configuration key and the full key to GET to restore a value (i.e., get from pre-VPN value)
    NSDictionary * keysAndGetKeys = [NSDictionary dictionaryWithObjectsAndKeys:
                                     @"State:/Network/OpenVPN/DNS/DomainName:",      @"DomainName",
                                     @"State:/Network/OpenVPN/DNS/ServerAddresses:", @"ServerAddresses",
                                     @"State:/Network/OpenVPN/DNS/SearchDomains:",   @"SearchDomains",
                                     @"State:/Network/OpenVPN/SMB/NetBIOSName:",     @"NetBIOSName",
                                     @"State:/Network/OpenVPN/SMB/WINSAddresses:",   @"WINSAddresses",
                                     @"State:/Network/OpenVPN/SMB/Workgroup:",       @"Workgroup",
                                     nil];
    
    // Map between a System Configuration key and the full key to SET to restore a value (i.e., set current value).
    // NOTE the %@ in the full key; it should be replaced by the 'psid' saved by client.up.tunnelblick.sh before use
    NSDictionary * keysAndSetKeys = [NSDictionary dictionaryWithObjectsAndKeys:
                                     @"State:/Network/Service/%@/DNS/DomainName:",      @"DomainName",
                                     @"State:/Network/Service/%@/DNS/ServerAddresses:", @"ServerAddresses",
                                     @"State:/Network/Service/%@/DNS/SearchDomains:",   @"SearchDomains",
                                     @"State:/Network/Service/%@/SMB/NetBIOSName:",     @"NetBIOSName",
                                     @"State:/Network/Service/%@/SMB/WINSAddresses:",   @"WINSAddresses",
                                     @"State:/Network/Service/%@/SMB/Workgroup:",       @"Workgroup",
                                     nil];
    
    NSString * changes = getChanges(charsAndKeys, current, preVpn, postVpn);
    
    BOOL didSomething = FALSE;
    int i;
    NSString * act = @"";
    for (  i=2; i<[actions length]; i++  ) {
        NSString * ch = [actions substringWithRange: NSMakeRange(i, 1)];
        if (  [ch isEqualToString: @"t"]  ) {
            if (  ! [act isEqualToString: @""] ) {
                appendToLog([NSString stringWithFormat: @"'t' action must come first; actions = '%@'", actions]);
                [gPool drain];
                exit(EXIT_FAILURE);
            }
            act = @"restart";
        } else if  (  [ch isEqualToString: @"r"]  ) {
            act = @"restore";
        } else {
            if (  [act isEqualToString: @""] ) {
                appendToLog([NSString stringWithFormat: @"'t' or 'r' action must come first; actions = '%@'", actions]);
                [gPool drain];
                exit(EXIT_FAILURE);
            }
            NSString * itemName = [charsAndKeys objectForKey: ch];
            if (  ! itemName  ) {
                appendToLog([NSString stringWithFormat: @"Unknown character '%@' in actions = '%@'", ch, actions]);
                [gPool drain];
                exit(EXIT_FAILURE);
            }
            if (  ([changes rangeOfString: ch].length) != 0) {
                if (  [act isEqualToString: @"restart"]  ) {
                    // Restart the connection
                    appendToLog([NSString stringWithFormat: @"%@ changed; sending USR1 to OpenVPN (process ID %@) to restart the connection.", itemName, process]);
                    sleep(1);   // sleep so log entry is displayed before OpenVPN messages about the restart
                    pid_t process_num = [process intValue];
                    kill(process_num, SIGUSR1);
                    [gPool drain];
                    exit(EXIT_SUCCESS);
                } else {
                    // Restore the item
                    scCommand([NSString stringWithFormat:
                               @"open\nget %@\nset %@\nquit\n",
                               [keysAndGetKeys objectForKey: itemName],
                               [[keysAndSetKeys objectForKey: itemName] stringByReplacingOccurrencesOfString: @"%@" withString: psid]]);
                    
                    appendToLog([NSString stringWithFormat: @"%@ changed; restoring it to the post-connection value", itemName, process]);
                    didSomething = TRUE;
                }
            }
        }
    }
    
    if (  ! didSomething  ) {
        appendToLog(@"A system configuration change was ignored because it was not relevant");
    }
    
    [gPool drain];
    exit(EXIT_SUCCESS);
}    

void appendToLog(NSString * msg)
{
    NSCalendarDate * date = [NSCalendarDate date];
    NSString * fullMsg = [NSString stringWithFormat:@"%@ *Tunnelblick process-network-changes: %@\n",[date descriptionWithCalendarFormat:@"%a %b %e %H:%M:%S %Y"], msg];
    NSFileHandle * handle = [NSFileHandle fileHandleForWritingAtPath: gLogPath];
    [handle seekToEndOfFile];
    [handle writeData: [NSData dataWithBytes: [fullMsg UTF8String] length: [fullMsg length]]];
    [handle closeFile];
}

NSString * getChanges(NSDictionary * charsAndKeys, NSString * current, NSString * preVpn, NSString * postVpn)
{
    NSMutableString * changes = [[[NSMutableString alloc] initWithCapacity:12] autorelease];
    
    NSEnumerator * e = [charsAndKeys keyEnumerator];
    NSString * ch;
    while (   (ch = [e nextObject])
           && ( ! [ch isEqualToString: [ch lowercaseString]] )  ) {
        NSString * key  = [charsAndKeys objectForKey: ch];
        NSString * cur  = getKeyFromScDictionary(key, current);
        NSString * pre  = getKeyFromScDictionary(key, preVpn);
        NSString * post = getKeyFromScDictionary(key, postVpn);
        if (  ! [cur isEqualToString: post]  ) {
            if (  [cur isEqualToString: pre]  ) {
                appendToLog([NSString stringWithFormat: @"'%@' changed from\n%@\n to (pre-VPN)\n%@\n", key, post, cur]);
                [changes appendString: ch];
            } else {
                appendToLog([NSString stringWithFormat: @"'%@' changed from\n%@\n to\n%@\n", key, post, cur]);
                [changes appendString: [ch uppercaseString]];
            }
        }        
    }
    
    return changes;
}

NSString * getKeyFromScDictionary(NSString * key, NSString * dictionary)
{
    NSRange r = rangeOfItemInString(key, dictionary);
//gMsg = [NSString stringWithFormat: @"key = '%@'; r = (%d, %d); dict = '%@'", key, r.location, r.length, dictionary];
//dumpMsg();
    if (  r.length != 0  ) {
        NSString * returnKey = trimWhitespace([dictionary substringWithRange: r]);
        if (  [returnKey isEqualToString:
               @"<array> {\n"
               "0 : No\n"
               "1 : such\n"
               "2 : key\n"
               "}"]  ) {
            returnKey = @"";
        }
        return returnKey;        
    }
    return @"";
}

NSString * getScKey(NSString * key)
{
    // Returns a key read via scutil
    
    NSTask* task = [[[NSTask alloc] init] autorelease];
    
    [task setLaunchPath: @"/usr/sbin/scutil"];
    
    NSPipe * errPipe = [[NSPipe alloc] init];
    [task setStandardError: errPipe];
    
    NSPipe * stdPipe = [[NSPipe alloc] init];
    [task setStandardOutput: stdPipe];
    
    NSPipe * inPipe   = [[NSPipe alloc] init];
    NSFileHandle * file = [inPipe fileHandleForWriting];
    NSString * scutilCommands = [NSString stringWithFormat: @"open\nshow %@\nquit\n", key];
    NSData * scutilCommandsAsData = [NSData dataWithBytes: [scutilCommands UTF8String] length: [scutilCommands length]];
    [file writeData: scutilCommandsAsData];
    [file closeFile];
    [task setStandardInput: inPipe];
    
    NSMutableArray * arguments = [NSArray array];
    [task setArguments: arguments];
    
    [task setCurrentDirectoryPath: @"/"];
    [task launch];
    [task waitUntilExit];
    
    NSString * value = @""; // Value we are returning
    
    int status = [task terminationStatus];
    if (  status == 0  ) {
        file = [stdPipe fileHandleForReading];
        NSData * data = [file readDataToEndOfFile];
        [file closeFile];
        NSString * scutilOutput = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
        value = standardizedString(scutilOutput, NSMakeRange(0, [scutilOutput length]));
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
    
    [task setLaunchPath: @"/usr/bin/scutil"];
    
    NSPipe * errPipe = [[NSPipe alloc] init];
    [task setStandardError: errPipe];
    
    NSPipe * stdPipe = [[NSPipe alloc] init];
    [task setStandardOutput: stdPipe];
    
    NSPipe * inPipe   = [[NSPipe alloc] init];
    NSFileHandle * file = [inPipe fileHandleForWriting];
    NSString * scutilCommands = [NSString stringWithFormat: @"open\n%@\nquit\n", command];
    NSData * scutilCommandsAsData = [NSData dataWithBytes: [scutilCommands UTF8String] length: [scutilCommands length]];
    [file writeData: scutilCommandsAsData];
    [file closeFile];
    [task setStandardInput: inPipe];
    
    NSMutableArray * arguments = [NSArray array];
    [task setArguments: arguments];
    
    [task setCurrentDirectoryPath: @"/"];
    [task launch];
    [task waitUntilExit];
    
    int status = [task terminationStatus];
    if (  status != 0  ) {
        file = [errPipe fileHandleForReading];
        NSData * data = [file readDataToEndOfFile];
        [file closeFile];
        NSString * errmsg = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
        appendToLog(errmsg);
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
    while (  line = [lineEnum nextObject]  ) {
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
//gMsg = [NSString stringWithFormat: @"ss = %@\nkey = %@\nrange = (%d,%d)", settingString, key, r.location, r.length];
//dumpMsg();
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
