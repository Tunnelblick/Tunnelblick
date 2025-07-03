/*
 * Copyright 2012, 2013, 2014, 2015, 2016, 2018 Jonathan K. Bullard. All rights reserved.
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

#import "ConfigurationParser.h"

#import "TBUserDefaults.h"

#import "VPNConnection.h"


extern NSFileManager  * gFileMgr;
extern TBUserDefaults * gTbDefaults;

@implementation ConfigurationParser

+(ConfigurationParser *) parsedConfigurationForConnection: (VPNConnection *) connection {

    // Returns a parser for the OpenVPN configuration file for connection "connection"
    //
    // Returns nil if an error occurred

    NSString * contents = [connection condensedSanitizedConfigurationFileContents];
    if (  ! contents  ) {
        return nil;
    }

    return [ConfigurationParser parsedConfigurationWithString: contents];
}

+(ConfigurationParser *) parsedConfigurationAtPath: (NSString *) path {

    // Returns a parser for the OpenVPN configuration file at "path"
    //
    // Returns nil if an error occurred

    NSString * contents = [NSString stringWithContentsOfFile: path encoding: NSUTF8StringEncoding error: nil];

    return [ConfigurationParser parsedConfigurationWithString: contents];
}

+(ConfigurationParser *) parsedConfigurationWithString: (NSString *) contents {

    // Returns a parser for OpenVPN configuration file contents in "contents"
    //
    // Returns nil if an error occurred

    NSMutableString * mContents = [[contents mutableCopy] autorelease];

    // Remove sequences of a backslash followed by a LF to merge lines that should be merged
    [mContents replaceOccurrencesOfString: @"\\\n" withString: @"" options: 0 range: NSMakeRange(0, mContents.length)];

    // Make sure configuration ends in a LF
    [mContents appendFormat: @"\n"];

    // Create the parser
    ConfigurationParser * parser = [[[ConfigurationParser alloc] init] autorelease];

    //
    // Parse each non-empty line of the configuration into the "lines" entry
    //
    NSMutableArray * result = nil;

    NSUInteger ix = 0;
    while (  ix < mContents.length  ) {
        NSRange r = [mContents rangeOfString: @"\n" options: 0 range: NSMakeRange(ix, mContents.length - ix)];
        if (  r.length == 0) {
            ix = mContents.length;
        } else {
            NSArray * a = [parser parseOpenVPNConfigurationLine: [mContents substringWithRange: NSMakeRange(ix, r.location - ix)]];
            if (  a  ) {
                if (  ! result  ) {
                    result = [[[NSMutableArray alloc] initWithCapacity: 100] autorelease];
                }
                [result addObject: a];
            }
            ix = r.location + 1;
        }
    }

    [parser setLines: [NSArray arrayWithArray: result]];

    return parser;
}

    -(BOOL) skipWhitespaceAndCommentsInLine: (NSString *)   line
                               fromIndexPtr: (NSUInteger *) ix {

        // Returns TRUE, having updated *ix to point to the first non-whitespace character
        // in line or to the end of the line, whichever comes first,
        //
        // or returns FALSE if an error occurred

        while (  *ix < line.length  ) {

            NSString * ch1 = [line substringWithRange: NSMakeRange( *ix, 1)];

            if (  [WHITESPACE_CHARACTERS_IN_OPENVPN_CONFIGURATION_FILE containsString: ch1]  ) {
                // Whitespace: skip past it
                *ix = *ix + 1;
                continue;
            }

            if (   [ch1 isEqualToString: @";"]
                || [ch1 isEqualToString: @"#"]  ) {
                // Semicolon or hash: skip it and the rest of the line
                *ix = line.length;
                return TRUE;
            }

            if (  *ix == line.length - 1  ) {
                // ch1 is the last character of the line, so it can't be the start
                // of a comment, so we return with ix pointing to it
                return TRUE;
            }

            if (  ! [ch1 isEqualToString: @"/"]  ) {
                // ch1 is not a "/", so it is not the start of a comment, so return
                // with ix pointing to it.
                return TRUE;
            }

            NSString * ch2 = [line substringWithRange: NSMakeRange( *ix + 1, 1)];

            if (  [ch2 isEqualToString: @"/"]  ) {
                // "//" ignore it and the rest of the line
                *ix = line.length;
                return TRUE;
            }

            if (  [ch2 isEqualToString: @"*"]  ) {
                // "/*" ignore it and the rest of the line
                *ix = line.length;
                return TRUE;
            }

            // Have /*, so skip until a */

            NSRange r2 = [line rangeOfString: @"*/" options: 0 range: NSMakeRange(*ix, line.length - *ix)];
            if (  r2.length == 0  ) {
                // Error: /* is not terminated. Skip the rest of the line
                return FALSE;
            } else {
                *ix = r2.location + 2;
            }
        }

        return TRUE;
    }

    -(NSString *) nextTokenInLine: (NSString *)   line
                     fromIndexPtr: (NSUInteger *) ix {

        // Returns a string containing the next token in line starting
        // with the character at *ix,
        //
        // or returns nil if an error occurred or there is no such token

        NSUInteger tokenStartIx = *ix;

        BOOL inBackslash   = FALSE;
        BOOL inSingleQuote = FALSE;
        BOOL inDoubleQuote = FALSE;

        while (  *ix < line.length  ) {

            NSString * ch = [line substringWithRange: NSMakeRange( *ix , 1)];

            *ix += 1;

            if (  inBackslash  ) {
                inBackslash = FALSE;
                continue;
            }

            if (  inSingleQuote  ) {
                if (  [ch isEqualToString: @"'"]) {
                    inSingleQuote = FALSE;
                }
                continue;
            }

            if (  inDoubleQuote  ) {
                if (  [ch isEqualToString: @"\""]) {
                    inDoubleQuote = FALSE;
                }
                continue;
            }

            if (  [ch isEqualToString: @"\\"]  ) {
                inBackslash = TRUE;
                continue;

            }

            if (  [ch isEqualToString: @"'"]  ) {
                inSingleQuote = TRUE;
                continue;

            }

            if (  [ch isEqualToString: @"\""]  ) {
                inDoubleQuote = TRUE;
                continue;
            }

            if (   ( ! inSingleQuote)
                && ( ! inDoubleQuote)  ) {
                if (  [WHITESPACE_CHARACTERS_IN_OPENVPN_CONFIGURATION_FILE containsString: ch]  ) {
                    // Whitespace: end of token; make ix point to the whitespace character
                    *ix -= 1;
                    break;
                }
            }
        }

        if (  *ix == tokenStartIx  ) {
            return nil;
        }

        NSString * token = [line substringWithRange: NSMakeRange(tokenStartIx, *ix - tokenStartIx)];
        return token;
    }

    -(NSArray *) parseOpenVPNConfigurationLine: (NSString *) line {

        // Returns an array containing a string for each option and parameter in the line.
        // or nil if an error occurred or are no options or parameters

        // Do not parse the sanitized placeholder comment
        if (  [line isEqualToString: @"[Security-related line(s) omitted]"]  ) {
            return nil;
        }

        NSMutableArray * arr = [[[NSMutableArray alloc] initWithCapacity:100] autorelease];

        NSUInteger ix = 0; // Current parsing point
        if (  ! [self skipWhitespaceAndCommentsInLine: line fromIndexPtr: &ix]  ) {
            return nil;
        }

        while ( ix < line.length  ) {
            NSString * token = [self nextTokenInLine: line fromIndexPtr: &ix];
            if (  token  ) {
                [arr addObject: token];
            }

            [self skipWhitespaceAndCommentsInLine: line fromIndexPtr: &ix];
        }

        if (  arr.count == 0) {
            arr = nil;
        }

        return arr;
    }

-(BOOL) doesNotContainAnyUnsafeOptions {

    NSEnumerator * e = [self.lines objectEnumerator];
    NSArray * arr;
    while (  (arr = e.nextObject)  ) {
        if (  [OPENVPN_OPTIONS_THAT_ARE_UNSAFE containsObject: arr.firstObject]  ) {
            return NO;
        }
    }

    if (  [self containsDnsUpdownCommand]  ) {
        return NO;
    }

    return YES;
}

-(BOOL) containsDnsScript {

    // Returns TRUE iff the OpenVPN configuration file includes the dns-updown force option

    NSArray * arr = [self entriesWithOptionName: @"dns-script"];
    return (arr.count != 0);
}

-(BOOL) containsDnsUpdownForce {

    NSArray * arr = [self entriesWithOptionName: @"dns-updown" andFirstParameter: @"force"];
    return (arr.count != 0);
}

-(BOOL) containsDnsUpdownDisable {

    NSArray * arr = [self entriesWithOptionName: @"dns-updown" andFirstParameter: @"disable"];
    return (arr.count != 0);
}

-(BOOL) containsDnsUpdownCommand {

    NSArray * entries = [self entriesWithOptionName: @"dns-updown"];
    NSEnumerator * e = entries.objectEnumerator;
    NSString * name;
    while (  (name = [e nextObject])  ) {
        if (   [name isNotEqualTo: @"force"]
            && [name isNotEqualTo: @"disable"]  ) {
            return TRUE;
        }
    }

    return FALSE;
}

-(NSArray *) entries {

    // Returns an array containing an array of strings containing each option and its parameters
    //
    // or nil if there are such no options or parameters

    return self.lines;
}

-(NSArray *) entriesWithOptionName: (NSString *) name {

    // Returns an array containing an array of strings containing each option and its parameters
    // for each option whose name matches name,
    //
    // or nil if there are such no options or parameters

    return [self entriesWithOptionName: name
                     andFirstParameter: nil];
}

-(NSArray *) entriesWithOptionName: (NSString *) name
                 andFirstParameter: (NSString *) first {

    // Returns an array containing an array of strings containing each option and its parameters
    // for each option whose name matches name and first parameter matches first,
    //
    // or nil if there are no such options or parameters.
    //
    // If first == nil, only the option's name must match name.

    NSMutableArray * result = nil;

    NSArray * arr;
    NSEnumerator * en = [self.lines objectEnumerator];
    while (  (arr = en.nextObject)  ) {
        if (   (arr.count > 0)
            && [name isEqualToString: arr[0]]  ) {
            if (   (   (arr.count > 1)
                    && [first isEqualToString: arr[1]]
                    )
                || ( ! first ) ) {
                if (  ! result  ) {
                    result = [[[NSMutableArray alloc] initWithCapacity: 100] autorelease];
                }
                [result addObject: arr];
            }
        }
    }

    return result;
}

TBSYNTHESIZE_OBJECT(retain, NSArray *, lines, setLines)

@end

