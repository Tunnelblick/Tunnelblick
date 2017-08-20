/*
 * Copyright 2011, 2012 Jonathan K. Bullard. All rights reserved.
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

void removeFlagCharacter(NSString * flagChar,
                         NSMutableString * theString,
                         BOOL * flag);

void append(NSString * theName,
            NSString * inString,
            NSMutableString * outString);

NSRange rangeOfItemInString(NSString * item,
                            NSString * s);

NSRange rangeOfContentsOfBlock(NSString * s,
                               NSRange r);

NSString * standardizedString(NSString * s,
                              NSRange r);


NSAutoreleasePool * gPool;

int main (int argc, const char * argv[])
{
    gPool = [[NSAutoreleasePool alloc] init];
    
    BOOL syntaxError = TRUE;
    
    BOOL includeDomainName      = TRUE;
    BOOL includeServerAddresses = TRUE;
    BOOL includeSearchDomains   = TRUE;
    BOOL includeNetBIOSName     = TRUE;
    BOOL includeWINSAddresses   = TRUE;
    BOOL includeWorkgroup       = TRUE;
    
    if (  argc == 1  ) {
        syntaxError = FALSE;
        
    } else if ( argc == 2  ) {
        NSMutableString * optionString = [[[NSString stringWithUTF8String: argv[1]] mutableCopy] autorelease];
        if (  [optionString hasPrefix: @"-i"]  ) {
            removeFlagCharacter(@"d", optionString, &includeDomainName     );
            removeFlagCharacter(@"a", optionString, &includeServerAddresses);
            removeFlagCharacter(@"s", optionString, &includeSearchDomains  );
            removeFlagCharacter(@"n", optionString, &includeNetBIOSName    );
            removeFlagCharacter(@"w", optionString, &includeWINSAddresses  );
            removeFlagCharacter(@"g", optionString, &includeWorkgroup      );
            if (  [optionString isEqualToString: @"-i"]  ) {
                syntaxError = FALSE;
            }
        }
    }
    
    if (  syntaxError  ) {
        fprintf(stderr,
                "Outputs a standardized copy of output from the scutil commmand\n\n"
                
                "Usage:\n\n"
                "    standardize-scutil-output [ -i[d][a][s][n][g][w] ] input\n\n"
                
                "Input: a string containing the output of an scutil command.\n\n"
                
                "Output: string containing the input \"standardized\" as follows\n\n"
                "        * Entries are presented in the following order:\n"
                "                  * DomainName\n"
                "                  * ServerAddresses\n"
                "                  * SearchDomins\n"
                "                  * NetBIOSName\n"
                "                  * WINSAddresses\n"
                "                  * Workgroup\n"
                "        * Each entry is terminated by a \"|\" (Pipe) character\n\n"
                "        * Each instance of whitespace is changed to a single space character\n"
                "        * Leading and trailing whitespace is removed from each line.\n\n"
                
                "The options direct the program to ignore specified entries\n\n"
                
                "If the item does not appear in the string, nothing is output.\n\n"
                
                "Returns 0 if no problems occcurred\n"
                "          else a a diagnostic message is output to stderr");
        [gPool drain];
        exit(EXIT_FAILURE);
    }
    
    // Fill inString with stdin
    NSFileHandle * input = [NSFileHandle fileHandleWithStandardInput];
    NSData *   inputData = [NSData dataWithData:[input readDataToEndOfFile]];
    NSString * tmpString = [[[NSString alloc] initWithData:inputData encoding: NSUTF8StringEncoding] autorelease];
	if (  tmpString == nil  ) {
		tmpString = @"Unable to interpret input data as UTF-8";
	}
    NSString * inString  = standardizedString(tmpString, NSMakeRange(0, [tmpString length]));

// For testing
//    NSMutableString * tmp = [[inString mutableCopy] autorelease];
//    [tmp replaceOccurrencesOfString: @"\\n" withString: @"\n" options: 0 range: NSMakeRange(0, [tmp length])];
//    inString = [NSString stringWithString: tmp];
    
    NSMutableString * outString = [NSMutableString stringWithCapacity: 1000];
    
    if (  includeDomainName     ) append(@"DomainName"     , inString, outString);
    if (  includeServerAddresses) append(@"ServerAddresses", inString, outString);
    if (  includeSearchDomains  ) append(@"SearchDomains"  , inString, outString);
    if (  includeNetBIOSName    ) append(@"NetBIOSName"    , inString, outString);
    if (  includeWINSAddresses  ) append(@"WINSAddresses"  , inString, outString);
    if (  includeWorkgroup      ) append(@"Workgroup"      , inString, outString);
    
    printf("%s", [standardizedString(outString, NSMakeRange(0, [outString length])) UTF8String]);
    
    [gPool drain];
    exit(EXIT_SUCCESS);
}

// If a flag character exists in a specified string, remove it from the string and clear a specified flag
void removeFlagCharacter(NSString * flagChar, NSMutableString * theString, BOOL * flag)
{
    NSRange r = [theString rangeOfString: flagChar];
    if (  r.length != 0  ) {
        [theString deleteCharactersInRange: r];
        *flag = FALSE;
    }
}

void append(NSString * theName, NSString * inString, NSMutableString * outString)
{
    NSRange r = rangeOfItemInString(theName, inString);
    if (  r.length != 0  ) {
        NSString * contents = [inString substringWithRange: r];
        if (  ! [contents isEqualToString:
                 @"<array> {\n"
                 "0 : No\n"
                 "1 : such\n"
                 "2 : key\n"
                 "}"]  ) {
            [outString appendString: [NSString stringWithFormat: @"%@ : %@\n|", theName, contents]];
        }
    }
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
