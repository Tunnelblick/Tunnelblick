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

@implementation ConfigurationConverter

-(id) init {
	self = [super init];
	if (  self  ) {
		logFile = NULL;
	}
	
	return self;	
}

-(void) dealloc {
    [configPath         release];
    [outputPath         release];
    [configString       release];
    [tokens             release];
    [tokensToReplace  release];
    [replacementStrings release];
    
    [super dealloc];
}

-(NSString *) nameToDisplayFromPath: path {
	if (  [path hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
		return [path substringFromIndex: [gPrivatePath length] + 1];
	} else {
        return [path lastPathComponent];
	}
}

-(void) logMessage: (NSString *) msg {
	NSString * name = [self nameToDisplayFromPath: configPath];
	NSString * pathString = (  includePathNameInLog
							 ? [name stringByAppendingString: @": "]
							 : @"");
	NSString * fullMsg = (  inputLineNumber == 0
						  ? [NSString stringWithFormat: @"%@%@", pathString, msg]
						  : [NSString stringWithFormat: @"%@line %u: %@", pathString, inputLineNumber, msg]);
	if (  logFile == NULL  ) {
		NSLog(@"%@", fullMsg);
	} else {
		fprintf(logFile, "%s\n", [fullMsg UTF8String]);
	}
}

-(NSRange) nextTokenInLine {
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
                return returnRange;		// double-quote marks end of token but is not part of the token
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
                return returnRange;  // single-quote marks end of token but is not part of the token
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
			// If haven't started token, whatever is next is the start of the token
			if (  returnRange.location == NSNotFound  ) {
				returnRange.location = inputIx;
				returnRange.length   = 0;
			}
            continue;
            
        } else if (  c == '\''  ) {
            if (   inToken  ) {
                inputIx--;                  // next time through, start with single-quote
                return returnRange;     // single-quote marks end of token
            }
            
            inSingleQuote = TRUE;       // processing a single-quote string
            inToken       = TRUE;
			// If haven't started token, whatever is next is the start of the token
			if (  returnRange.location == NSNotFound  ) {
				returnRange.location = inputIx;
				returnRange.length   = 0;
			}
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

-(NSMutableArray *) getTokens {
	NSMutableArray * arr = [NSMutableArray arrayWithCapacity: 300];
	
	inputIx = 0;
	unsigned lineNum = 1;
	
	while (  inputIx < [configString length]  ) {
		NSRange r = [self nextTokenInLine];
		if (  r.location == NSNotFound  ) {
			while (  inputIx++ < [configString length]  ) {
				if (  [[configString substringWithRange: NSMakeRange(inputIx - 1, 1)] isEqualToString: @"\n"]  ) {
					lineNum++;
					break;
				}
			}
			[arr addObject: [[[ConfigurationToken alloc] initWithRange:NSMakeRange(inputIx - 1, 1)
                                                              inString: configString
                                                            lineNumber: lineNum] autorelease]];
		} else {
			[arr addObject: [[[ConfigurationToken alloc] initWithRange: r
                                                              inString: configString
                                                            lineNumber: lineNum] autorelease]];
		}
	}
	
	return arr;
}

-(NSArray *) getTokensFromPath: (NSString *) theConfigPath
                    lineNumber: (unsigned)   theLineNumber
                        string: (NSString *) theString
                    outputPath: (NSString *) theOutputPath
                       logFile: (FILE *)     theLogFile {

    configPath      = [theConfigPath copy];
    inputLineNumber = theLineNumber;
    configString    = [theString copy];
    outputPath      = [theOutputPath copy];
    logFile         = theLogFile;
    
    inputIx         = 0;
    
	tokensToReplace    = [[NSMutableArray alloc] initWithCapacity: 8];
	replacementStrings = [[NSMutableArray alloc] initWithCapacity: 8];

    NSMutableArray * tokensToReturn = [self getTokens];
    return tokensToReturn;
}

-(BOOL) processPathRange: (NSRange) rng
	   removeBackslashes: (BOOL) removeBackslashes
        needsShExtension: (BOOL) needsShExtension {
    
    // Get raw from the configuration file itself
	NSString * inPathString = [configString substringWithRange: rng];
	if (  removeBackslashes  ) {
		NSMutableString * path = [inPathString mutableCopy];
		[path replaceOccurrencesOfString: @"\\" withString: @"" options: 0 range: NSMakeRange(0, [path length])];
		inPathString = [NSString stringWithString: path];
		[path release];
	}
	
    // Process that path into an absolute path for use to use to access the file
	NSString * inPath = [[inPathString copy] autorelease];
	if (  ! [inPath hasPrefix: @"/"]  ) {
		if (  [inPath hasPrefix: @"~"]  ) {
			inPath = [inPath stringByExpandingTildeInPath];
		} else {
			NSString * prefix = (  [configPath hasPrefix: @"/private/"]
								 ? [configPath stringByDeletingLastPathComponent]
								 : firstPartOfPath(configPath));
			if (  ! prefix  ) {
				prefix = [configPath stringByDeletingLastPathComponent];
			}
			inPath = [prefix stringByAppendingPathComponent: [inPath lastPathComponent]];
		}
	}
	
    NSString * errMsg = fileIsReasonableSize(inPath);
    if (  errMsg  ) {
        [self logMessage: errMsg];
        return FALSE;
    }
    
	NSString * file = [inPath lastPathComponent];
	
    // Make sure the file has an extension that Tunnelblick can secure properly
    NSString * fileWithNeededExtension = [[file copy] autorelease];
    NSString * extension = [file pathExtension];
    if (   needsShExtension  ) {
        if (  ! [extension isEqualToString: @"sh"]  ) {
            fileWithNeededExtension = [file stringByAppendingPathExtension: @"sh"];
			inPath = [inPath stringByAppendingPathExtension: @"sh"];
            [self logMessage: [NSString stringWithFormat: @"Added '.sh' extension to %@ so it will be secured properly", file]];
        }
        
        NSString * errorMsg = errorIfNotPlainTextFileAtPath(inPath, NO, @"#");  // Scripts use '#' to start comments
        if (  errorMsg  ) {
            [self logMessage: [NSString stringWithFormat: @"File %@: %@", [inPath lastPathComponent], errorMsg]];
            return FALSE;
        }
    } else {
        if (   ( ! extension)
            || ( ! [KEY_AND_CRT_EXTENSIONS containsObject: extension] )  ) {
            fileWithNeededExtension = [file stringByAppendingPathExtension: @"key"];
            [self logMessage: [NSString stringWithFormat: @"Added a 'key' extension to %@ so it will be secured properly", file]];
        }
    }
    
    if (  outputPath  ) {

        NSString * outPath = [[[outputPath stringByAppendingPathComponent: @"Contents"]
                               stringByAppendingPathComponent: @"Resources"]
                              stringByAppendingPathComponent: fileWithNeededExtension];
        
		unsigned linkCounter = 0;
        while (   [[[gFileMgr tbFileAttributesAtPath: inPath traverseLink: NO] objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]
			   && (linkCounter++ < 20)  ) {
            NSString * newInPath = [gFileMgr tbPathContentOfSymbolicLinkAtPath: inPath];
            if (  newInPath  ) {
                [self logMessage: [NSString stringWithFormat: @"Resolved symbolic link at '%@' to '%@'", inPath, newInPath]];
                inPath = [[newInPath copy] autorelease];
            } else {
                [self logMessage: [NSString stringWithFormat: @"Could not resolve symbolic link at %@", inPath]];
                return FALSE;
            }
		}
		
		if (  [[[gFileMgr tbFileAttributesAtPath: inPath traverseLink: NO] objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
			[self logMessage: [NSString stringWithFormat: @"Symbolic links nested too deeply. Gave up at %@", inPath]];
			return FALSE;
		}

		if (  ! [gFileMgr fileExistsAtPath: outPath]  ) {
			if (  [gFileMgr tbCopyPath: inPath toPath: outPath handler: nil]  ) {
				[self logMessage: [NSString stringWithFormat: @"Copied %@", [self nameToDisplayFromPath: inPath]]];
			} else {
				[self logMessage: [NSString stringWithFormat: @"Unable to copy file at '%@' to '%@'",
								   inPath, outPath]];
				return FALSE;
			}
		} else if (  [gFileMgr contentsEqualAtPath: inPath andPath: outPath ]) {
			[self logMessage: [NSString stringWithFormat: @"Skipped copying %@ because a file with that name and contents has already been copied.",
							   [self nameToDisplayFromPath: inPath]]];
		} else {
			[self logMessage: [NSString stringWithFormat: @"Unable to copy file at '%@' to '%@' because the same name is used for different contents",
							   inPath, outPath]];
			return FALSE;
		}
		
        NSString * ext = [outPath pathExtension];
        if (  [ext isEqualToString: @"sh"]  ) {
            checkSetPermissions(outPath, PERMS_PRIVATE_SCRIPT, YES);
        } else {
            checkSetPermissions(outPath, PERMS_PRIVATE_OTHER,  YES);
        }
    }
	
	if (  ! [inPathString isEqualToString: fileWithNeededExtension]  ) {
		[tokensToReplace  addObject: [[[ConfigurationToken alloc]
                                       initWithRange: rng
                                       inString:      configString
                                       lineNumber:    inputLineNumber] autorelease]];
		NSMutableString * temp = [fileWithNeededExtension mutableCopy];
		[temp replaceOccurrencesOfString: @" " withString: @"\\ " options: 0 range: NSMakeRange(0, [temp length])];
		[replacementStrings addObject: [NSString stringWithString: temp]];
		[temp release];
    }
	
    return TRUE;
}

-(BOOL) convertConfigPath: (NSString *) theConfigPath
               outputPath: (NSString *) theOutputPath
                  logFile: (FILE *)     theLogFile
     includePathNameInLog: (BOOL)       theIncludePathNameInLog {
    
    // Converts a configuration file for use in a .tblk by removing all path information from ca, cert, etc. options.
    //
	// If outputPath is specified, it is created as a .tblk and the configuration file and keys and certificates are copied into it.
    // If outputPath is nil, the configuration file's contents are replaced after removing path information.
    //
	// If logFile is nil, NSLog is used
	
    configPath           = [theConfigPath copy];
    outputPath           = [theOutputPath copy];
    logFile              = theLogFile;
    includePathNameInLog = theIncludePathNameInLog;
	
    inputIx         = 0;
    inputLineNumber = 0;
    
	tokensToReplace    = [[NSMutableArray alloc] initWithCapacity: 8];
	replacementStrings = [[NSMutableArray alloc] initWithCapacity: 8];
	
    NSString * errorMsg = fileIsReasonableSize(theConfigPath);
    if (  errorMsg  ) {
        [self logMessage: errorMsg];
        return FALSE;
    }
    
    errorMsg = errorIfNotPlainTextFileAtPath(theConfigPath, YES, @"#;"); // Config files use # and ; to start comments
    if (  errorMsg  ) {
        [self logMessage: errorMsg];
        return FALSE;
    }
    
    configString = [[[[NSString alloc] initWithContentsOfFile: configPath encoding: NSASCIIStringEncoding error: NULL] autorelease] mutableCopy];
    
    // Append newline to file if it doesn't aleady end in one (simplifies parsing)
    if (  ! [configString hasSuffix: @"\n"]  ) {
        [configString appendString: @"\n"];
    }
    
    tokens = [[self getTokens] copy];
	
    // List of OpenVPN options that take a file path
    NSArray * optionsWithPath = [NSArray arrayWithObjects:
//					             @"askpass",                       // askpass        'file' not supported since we don't compile with --enable-password-save
//								 @"auth-user-pass",				   // auth-user-pass 'file' not supported since we don't compile with --enable-password-save
								 @"ca",
								 @"cert",
								 @"dh",
								 @"extra-certs",
								 @"key",
								 @"pkcs12",
								 @"crl-verify",                    // Optional 'direction' argument
								 @"secret",                        // Optional 'direction' argument
								 @"tls-auth",                      // Optional 'direction' argument
								 nil];
    
    // List of OpenVPN options that take a command
	NSArray * optionsWithCommand = [NSArray arrayWithObjects:
									@"tls-verify",
									@"auth-user-pass-verify",
									@"client-connect",
									@"client-disconnect",
									@"up",
									@"down",
									@"ipchange",
									@"route-up",
									@"route-pre-down",
									@"learn-address",
									nil];
	
	NSArray * optionsWithArgsThatAreOptional = [NSArray arrayWithObjects:
									            @"auth-user-pass",                // Optional 'file' argument not supported since we don't compile with --enable-password-save
												@"crl-verify",                    // Optional 'direction' argument
												@"secret",                        // Optional 'direction' argument
												@"tls-auth",                      // Optional 'direction' argument after 'file' argument
												nil];
    
    NSArray * beginInlineKeys = [NSArray arrayWithObjects:
                                 @"<ca>",
                                 @"<cert>",
                                 @"<dh>",
                                 @"<extra-certs>",
                                 @"<key>",
                                 @"<pkcs12>",
                                 @"<secret>",
                                 @"<tls-auth>",
                                 nil];
    
    NSArray * endInlineKeys = [NSArray arrayWithObjects:
                               @"</ca>",
                               @"</cert>",
                               @"</dh>",
                               @"</extra-certs>",
                               @"</key>",
                               @"</pkcs12>",
                               @"</secret>",
                               @"</tls-auth>",
                               nil];
    
    // List of OpenVPN options that cannot appear in a Tunnelblick VPN Configuration unless the file they reference has an absolute path
    NSArray * optionsThatRequireAnAbsolutePath = [NSArray arrayWithObjects:
                                                  @"log",
                                                  @"log-append",
                                                  @"status",
                                                  @"write-pid",
                                                  @"replay-persist",
                                                  nil];
    
    // Create the .tblk/Contents/Resources folder
    if (  outputPath  ) {
		NSString * tblkResourcesPath = [[outputPath stringByAppendingPathComponent: @"Contents"]
                                        stringByAppendingPathComponent: @"Resources"];
        if (  ! createDirWithPermissionAndOwnership(tblkResourcesPath, PERMS_PRIVATE_TBLK_FOLDER, getuid(), ADMIN_GROUP_ID)  ) {
            [self logMessage: [NSString stringWithFormat: @"Unable to create %@ owned by %ld:%ld with %lo permissions",
                               tblkResourcesPath, (long) getuid(), (long) ADMIN_GROUP_ID, (long) PERMS_PRIVATE_OTHER]];
        }
    }
    
    unsigned tokenIx = 0;
    while (  tokenIx < [tokens count]  ) {
        
        ConfigurationToken * firstToken = [tokens objectAtIndex: tokenIx++];
        inputLineNumber = [firstToken lineNumber];
        
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
                    if (  ! [[configString substringWithRange: r2] isEqualToString: @"[inline]"]  ) {
                        if (  ! [self processPathRange: r2 removeBackslashes: YES needsShExtension: NO]  ) {
                            return FALSE;
                        }
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
					NSRange r2 = [secondToken range];
                    
                    // The second token is a command, which consists of a path and arguments, so we must parse the command
                    // to extract the path, then use that extracted path
                    NSString * command = [[configString substringWithRange: [secondToken range]] stringByAppendingString: @"\n"];
                    ConfigurationConverter * converter = [[ConfigurationConverter alloc] init];
                    NSArray * commandTokens = [converter getTokensFromPath: configPath lineNumber: inputLineNumber string: command outputPath: outputPath logFile: logFile];
                    [converter release];
                    
                    // Set the length of the path of the command
                    NSRange r3 = [[commandTokens objectAtIndex: 0] range];
                    r2.length = r3.length;
                    
                    // copy the file and change the path in the configuration string if necessary
                    if (  ! [self processPathRange: r2 removeBackslashes: YES needsShExtension: YES]  ) {
                        return FALSE;
                    }
                    
                    tokenIx++;
                    
                } else {
                    if (  ! [optionsWithArgsThatAreOptional containsObject: [firstToken stringValue]]  ) {
                        [self logMessage: [NSString stringWithFormat: @"Expected command not found for '%@'", firstToken]];
                        return FALSE;
                    }
                }
            } else if (  [beginInlineKeys containsObject: [firstToken stringValue]]  ) {
                NSString * startTokenStringValue = [firstToken stringValue];
                BOOL foundEnd = FALSE;
                ConfigurationToken * token;
                while (  tokenIx < [tokens count]  ) {
                    token = [tokens objectAtIndex: tokenIx++];
                    if (  [token isLinefeed]  ) {
                        if (  tokenIx < [tokens count]  ) {
                            token = [tokens objectAtIndex: tokenIx];
                            if (  [endInlineKeys containsObject: [token stringValue]] ) {
                                foundEnd = TRUE;
                                break;
                            }
                        }
                    }
                }
                
                if (  ! foundEnd ) {
                    [self logMessage: [NSString stringWithFormat: @"%@ was not terminated", startTokenStringValue]];
                    return FALSE;
                }
            } else if (  [optionsThatRequireAnAbsolutePath containsObject: [firstToken stringValue]]  ) {
                if (  ! [[secondToken stringValue] hasPrefix: @"/" ]  ) {
                    [self logMessage: [NSString stringWithFormat: @"The '%@' option is not allowed in an OpenVPN configuration file that is in a Tunnelblick VPN Configuration unless the file it references is specified with an absolute path.", [firstToken stringValue]]];
                    return FALSE;
                }
            }
            
            // Skip to end of line
            while (  tokenIx < [tokens count]  ) {
                if (  [[tokens objectAtIndex: tokenIx++] isLinefeed]  ) {
                    break;
                }
            }
		}
	}
	
	// Modify the configuration file string, from the end to the start (earlier ranges aren't affected by later changes)
    unsigned i;
    for (  i=[tokensToReplace count]; i > 0; i--  ) {
        [configString replaceCharactersInRange: [[tokensToReplace objectAtIndex: i - 1] range] withString: [replacementStrings objectAtIndex: i - 1]];
    }
	
	// Inhibit display of line number
	inputLineNumber = 0;

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
            [self logMessage: @"Converted OpenVPN configuration"];
        } else {
            [self logMessage: @"Unable to convert OpenVPN configuration"];
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
