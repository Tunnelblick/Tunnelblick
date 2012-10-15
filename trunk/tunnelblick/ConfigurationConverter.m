/*
 * Copyright 2012 Jonathan K. Bullard. All rights reserved.
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

#import <stdio.h>
#import "ConfigurationConverter.h"
#import "helper.h"
#import "NSFileManager+TB.h"
#import "ConfigurationToken.h"
#import "sharedRoutines.h"


extern NSFileManager * gFileMgr;
extern NSString      * gPrivatePath;

NSArray * optionsWithPath;					// List of OpenVPN options that take a file path as an argument
NSArray * optionsWithCommand;				// List of OpenVPN options that take a command as an argument
NSArray * optionsWithArgsThatAreOptional;   // List of OpenVPN options for which the path or command is optional

@implementation ConfigurationConverter

-(id) init
{
	self = [super init];
	if (  self  ) {
		logFile = NULL;
	}
	
	return self;	
}

-(void) dealloc
{
    [configPath         release];
    [outputPath         release];
    [configString       release];
    [tokens             release];
    [tokensToReplace  release];
    [replacementStrings release];
    
    [super dealloc];
}

-(NSString *) nameToDisplayFromPath: path
{
	if (  [path hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
		return [path substringFromIndex: [gPrivatePath length] + 1];
	} else {
		return path;
	}
}

-(void) logMessage: (NSString *) msg
{
	NSString * fullMsg;
	if (  inputLineNumber != 0  ) {
		fullMsg = [NSString stringWithFormat: @"%@ line %u: %@", [self nameToDisplayFromPath: configPath], inputLineNumber, msg];
	} else {
		fullMsg = [NSString stringWithFormat: @"%@: %@", [self nameToDisplayFromPath: configPath], msg];
	}
	if (  logFile == NULL  ) {
		NSLog(@"%@", fullMsg);
	} else {
		fprintf(logFile, "%s\n", [fullMsg UTF8String]);
	}
}

-(void) skipToNextLine
{
    NSRange r = [configString rangeOfString: @"\n" options: 0 range: NSMakeRange(inputIx, [configString length] - inputIx)];
    if (  r.location == NSNotFound  ) {
        inputIx = [configString length];    // point past end of string
    } else {
        inputIx = r.location + 1;  // point past newline character
        inputLineNumber++;
    }
}

-(NSRange) nextTokenInLine
{
    BOOL inSingleQuote = FALSE;
    BOOL inDoubleQuote = FALSE;
    BOOL inBackslash   = FALSE;
    BOOL inToken       = FALSE;
    
    // Assume no token
	NSRange returnRange = NSMakeRange(NSNotFound, 0);
    
	while (  inputIx < [configString length]  ) {
        
		unichar c = [configString characterAtIndex: inputIx];
        
        // If have started token, mark the end of the token as the current position -- before this character (for now)
        if (  returnRange.location != NSNotFound  ) {
            returnRange.length = inputIx - returnRange.location;
        }
        
        inputIx++;
        
        if ( inBackslash  ) {
            inBackslash = FALSE;
            continue;
        }
        
		if (  inDoubleQuote  ) {
			if (  c == '"'  ) {
                returnRange.length++;	// double-quote marks end of token and is part of the token
                return returnRange;
            }
            if (  c == UNICHAR_LF  ) {
                [self logMessage: [NSString stringWithFormat: @"Unbalanced double-quote"]];
				inputIx--;				// back up so newline will be processed by skipToNextLine
				return returnRange;     // newline marks end of token but is not part of the token
            }
            
            continue;
        }
        
        if (  inSingleQuote  ) {
            if (  c == '\''  ) {
                returnRange.length++;  // single-quote marks end of token and is part of the token
                return returnRange;
            }
            if (  c == UNICHAR_LF  ) {
                [self logMessage: [NSString stringWithFormat: @"Unbalanced single-quote"]];
				inputIx--;				// back up so newline will be processed by skipToNextLine
				return returnRange;     // newline marks end of token but is not part of the token
            }
            
            continue;
        }
		
		if (  c == UNICHAR_LF  ) {
			inputIx--;				// back up so newline will be processed by skipToNextLine
			return returnRange;     // newline marks end of token but is not part of the token
		}
		
		if (  [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember: c]  ) {
			if (  returnRange.location == NSNotFound  ) {
				continue;           // whitespace comes before token, so just skip past it
			} else {
				return returnRange; // whitespace marks end of token but is not part of the token
			}
		}
		
		if (  c == '#'  ) {
			inputIx--;		// Skip to, but not over, the next newline (if any)
			do {
				inputIx++;
				if (  inputIx >= [configString length]  ) {
					break;
				}
				c = [configString characterAtIndex: inputIx];
			} while (  c != UNICHAR_LF  );
			return returnRange;         // comment marks end of token (if any) but is not part of the token
		}
		
        if (  c == '"'  ) {
            if (  inToken  ) {
                inputIx--;              // next time through, start with double-quote
                return returnRange;     // double-quote marks end of token but is not part of the token
            }
            
            inDoubleQuote = TRUE;       // processing a double-quote string
            inToken = TRUE;
            continue;
            
        } else if (  c == '\''  ) {
            if (   inToken  ) {
                inputIx--;                  // next time through, start with single-quote
                return returnRange;     // single-quote marks end of token
            }
            
            inSingleQuote = TRUE;       // processing a single-quote string
            inToken       = TRUE;
            continue;
            
        } else if (  c == '\\'  ) {
            inBackslash = TRUE;
			continue;
        }
        
        inToken = TRUE;
        
        // If haven't started token, this is the start of the token
        if (  returnRange.location == NSNotFound  ) {
            returnRange.location = inputIx - 1;
            returnRange.length   = 1;
        }
    }
    
    if (  inBackslash  ) {
        [self logMessage: [NSString stringWithFormat: @"Backslash at end of line is being ignored"]];
    }
    if (  inSingleQuote  ) {
        [self logMessage: [NSString stringWithFormat: @"Single-quote missing in line; one is assumed"]];
    }
    if (  inDoubleQuote  ) {
        [self logMessage: [NSString stringWithFormat: @"Double-quote missing in line; one is assumed"]];
    }
    return returnRange;
}

-(NSArray *) getTokensFromString: (NSString *) string
{
	NSMutableArray * arr = [NSMutableArray arrayWithCapacity: 300];
	
	inputIx = 0;
	inputLineNumber = 1;
	
	while (  inputIx < [string length]  ) {
		NSRange r = [self nextTokenInLine];
		if (  r.location == NSNotFound  ) {
			while (  inputIx++ < [string length]  ) {
				if (  [[string substringWithRange: NSMakeRange(inputIx - 1, 1)] isEqualToString: @"\n"]  ) {
					break;
				}
			}
			[arr addObject: [[[ConfigurationToken alloc] initWithRange:NSMakeRange(inputIx - 1, 1) inString: string] autorelease]];
		} else {
			[arr addObject: [[[ConfigurationToken alloc] initWithRange: r inString: string] autorelease]];
		}
	}
	
	return arr;
}

-(BOOL) processPathRange: (NSRange) rng removeBackslashes: (BOOL) removeBackslashes
{
	NSString * inPathString = [configString substringWithRange: rng];
	NSString * inPath = [[inPathString copy] autorelease];
	if (  removeBackslashes  ) {
		NSMutableString * path = [[inPath mutableCopy] autorelease];	
		unsigned slashIx;
		while (  (slashIx = [path rangeOfString: @"\\"].location) != NSNotFound  ) {
			[path deleteCharactersInRange: NSMakeRange(slashIx, 1)];
		}
		inPath = [NSString stringWithString: path];
	}
	
	NSString * file = [inPath lastPathComponent];
	
    if (  outputPath  ) {

		if (  ! (   [inPath hasPrefix: @"/"]
				 || [inPath hasPrefix: @"~"]  )  ) {
			inPath = [firstPartOfPath(configPath) stringByAppendingPathComponent: inPath];
		}
				
		NSString * tblkResourcesPath = [[outputPath stringByAppendingPathComponent: @"Contents"]
                                        stringByAppendingPathComponent: @"Resources"];
        NSString * outPath = [tblkResourcesPath stringByAppendingPathComponent: file];
        
        if (  ! createDirWithPermissionAndOwnership(tblkResourcesPath, PERMS_PRIVATE_TBLK_FOLDER, getuid(), ADMIN_GROUP_ID)  ) {
            [self logMessage: [NSString stringWithFormat: @"Unable to create %@", inPath]];
        }
        
        if (  [gFileMgr tbCopyPath: inPath toPath: outPath handler: nil]  ) {
            [self logMessage: [NSString stringWithFormat: @"Copied %@", [self nameToDisplayFromPath: inPath]]];
        } else {
            [self logMessage: [NSString stringWithFormat: @"Unable to copy file at '%@' to '%@'", inPath, outPath]];
            return FALSE;
        }
        
        NSString * ext = [outPath pathExtension];
        if (  [ext isEqualToString: @"sh"]  ) {
            checkSetPermissions(outPath, PERMS_PRIVATE_SCRIPT, YES);
        } else {
            checkSetPermissions(outPath, PERMS_PRIVATE_OTHER,  YES);
        }
    }
	
	if (  ! [inPathString isEqualToString: file]  ) {
		[tokensToReplace  addObject: [[[ConfigurationToken alloc] initWithRange: rng inString: configString] autorelease]];
		[replacementStrings addObject: file];
    }
	
    return TRUE;
}

-(BOOL) convertConfigPath: (NSString *) theConfigPath
               outputPath: (NSString *) theOutputPath
                  logFile: (FILE *)     theLogFile
{
    // Converts a configuration file for use in a .tblk by removing all path information from ca, cert, etc. options.
    //
	// If outputPath is specified, it is created as a .tblk and the configuration file and keys and certificates are copied into it.
    // If outputPath is nil, the configuration file's contents are replaced after removing path information.
    //
	// If logFile is nil, NSLog is used
	
    configPath   = [theConfigPath copy];
    outputPath   = [theOutputPath copy];
    logFile      = theLogFile;
	
	tokensToReplace  = [[NSMutableArray alloc] initWithCapacity: 8];
	replacementStrings = [[NSMutableArray alloc] initWithCapacity: 8];
	
    NSString * s = [[NSString alloc] initWithContentsOfFile: configPath encoding: NSASCIIStringEncoding error: NULL];
    configString = [s mutableCopy];
    [s release];
    tokens = [[self getTokensFromString: configString] copy];
	
    // List of OpenVPN options that take a script file path
    optionsWithPath = [NSArray arrayWithObjects:
					   @"dh",
					   @"ca",
					   @"capath",
					   @"cert",
					   @"extra-certs",
					   @"key",
					   @"pkcs12",
					   @"crl-verify",
					   @"tls-auth",
					   @"secret",
					   @"replay-persist",
					   @"askpass",
					   @"management-user-password-file",
					   @"tls-export-cert",
					   @"client-connect",
					   @"client-disconnect",
					   @"--auth-user-pass-verify",
					   nil];
    
    // List of OpenVPN options that take a command
	optionsWithCommand = [NSArray arrayWithObjects:
						  @"tle-verify",
						  @"auth-user-pass-verify",
						  @"auth-user-pass",
						  @"up",
						  @"down",
						  @"ipchange",
						  @"route-up",
						  @"route-pre-down",
						  @"learn-address",
						  nil];
	
	optionsWithArgsThatAreOptional = [NSArray arrayWithObjects:
									  @"auth-user-pass",
									  nil];
    
    inputIx         = 0;
    inputLineNumber = 1;
    
    unsigned tokenIx = 0;
    while (  tokenIx < [tokens count]  ) {
        
        ConfigurationToken * firstToken = [tokens objectAtIndex: tokenIx++];
        
        if (  ! [firstToken isLinefeed]  ) {
            ConfigurationToken * secondToken = nil;
            if (  tokenIx < [tokens count]  ) {
                secondToken = [tokens objectAtIndex: tokenIx];
                if (  [secondToken isLinefeed]  ) {
                    secondToken = nil;
                }
            }
            
            if (  [optionsWithPath containsObject: [firstToken stringValue]]  ) {
                if (  secondToken  ) {
                    if (  ! [self processPathRange: [secondToken range] removeBackslashes: NO]  ) {
                        return FALSE;
                    }
                    tokenIx++;
                } else {
                    if (  ! [optionsWithArgsThatAreOptional containsObject: [firstToken stringValue]]  ) {
                        [self logMessage: [NSString stringWithFormat: @"Expected path not found for '%@'", firstToken]];
                        return FALSE;
                    }
                }
            } else if (  [optionsWithCommand containsObject: [firstToken stringValue]]  ) {
                if (  secondToken  ) {
                    // remove leading/trailing single- or double-quotes
					NSRange r2 = [secondToken range];
                    if (   (   [[configString substringWithRange: NSMakeRange(r2.location, 1)] isEqualToString: @"\""]
                            && [[configString substringWithRange: NSMakeRange(r2.location + r2.length - 1, 1)] isEqualToString: @"\""]  )
                        || (   [[configString substringWithRange: NSMakeRange(r2.location, 1)] isEqualToString: @"'"]
                            && [[configString substringWithRange: NSMakeRange(r2.location + r2.length - 1, 1)] isEqualToString: @"'"]  )  )
                    {
                        r2.location++;
                        r2.length -= 2;
                    }
                    
                    // copy the file and change the path in the configuration string if necessary
                    if (  [self processPathRange: r2 removeBackslashes: YES]  ) {
                        [self logMessage: [NSString stringWithFormat: @"Copied '%@'", firstToken]];
                    } else {
                        return FALSE;
                    }
                    
                    tokenIx++;
                    
                } else {
                    if (  ! [optionsWithArgsThatAreOptional containsObject: [firstToken stringValue]]  ) {
                        [self logMessage: [NSString stringWithFormat: @"Expected command not found for '%@'", firstToken]];
                        return FALSE;
                    }
                }
            }
		}
	}
	
	// Modify the configuration file string, from the end to the start (earlier ranges aren't affected by later changes)
    unsigned i;
    for (  i=[tokensToReplace count]; i > 0; i--  ) {
        [configString replaceCharactersInRange: [[tokensToReplace objectAtIndex: i - 1] range] withString: [replacementStrings objectAtIndex: i - 1]];
    }
	
	// Write out the (possibly modified) configuration file
	NSString * outputConfigPath;
    if (  outputPath  ) {
        outputConfigPath= [[[outputPath stringByAppendingPathComponent: @"Contents"]
                            stringByAppendingPathComponent: @"Resources"]
                           stringByAppendingPathComponent: @"config.ovpn"];
        NSDictionary * attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSNumber numberWithUnsignedLong: (unsigned long) getuid()],            NSFileOwnerAccountID,
                                     [NSNumber numberWithUnsignedLong: (unsigned long) ADMIN_GROUP_ID],      NSFileGroupOwnerAccountID,
                                     [NSNumber numberWithUnsignedLong: (unsigned long) PERMS_PRIVATE_OTHER], NSFilePosixPermissions,
                                     nil];
        if (  [gFileMgr createFileAtPath: outputConfigPath
                                contents: [NSData dataWithBytes: [configString UTF8String]
                                                         length: [configString length]]
                              attributes: attributes]  ) {
            [self logMessage: @"Copied OpenVPN configuration file"];
        } else {
            [self logMessage: @"Unable to copy OpenVPN configuration file"];
            return FALSE;
        }
    } else if (  [tokensToReplace count] != 0  ) {
        FILE * outFile = fopen([configPath fileSystemRepresentation], "w");
        if (  outFile  ) {
			if (  fwrite([configString UTF8String], [configString length], 1, outFile) != 1  ) {
				[self logMessage: @"Unable to write to configuration file for modification"];
				return FALSE;
			}
			
			fclose(outFile);
			inputLineNumber = 0; // Inhibit display of line number
			[self logMessage: @"Modified configuration file to remove path information"];
		} else {
			[self logMessage: @"Unable to open configuration file for modification"];
			return FALSE;
		}
	} else {
		[self logMessage: @"Did not need to modify configuration file; no path information to remove"];
	}
	
	return TRUE;
}

@end
