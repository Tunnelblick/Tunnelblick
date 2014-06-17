/*
 * Copyright 2010, 2011, 2012, 2013, 2014 Jonathan K. Bullard. All rights reserved.
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

#import "ConfigurationManager.h"

#import <sys/param.h>
#import <sys/mount.h>
#import <unistd.h>

#import "defines.h"
#import "helper.h"
#import "sharedRoutines.h"

#import "ConfigurationConverter.h"
#import "ListingWindowController.h"
#import "MenuController.h"
#import "NSApplication+LoginItem.h"
#import "NSFileManager+TB.h"
#import "TBUserDefaults.h"
#import "VPNConnection.h"

extern NSMutableArray       * gConfigDirs;
extern NSArray              * gConfigurationPreferences;
extern NSString             * gPrivatePath;
extern NSString             * gDeployPath;
extern NSFileManager        * gFileMgr;
extern TBUserDefaults       * gTbDefaults;
extern AuthorizationRef       gAuthorization;

extern NSString * lastPartOfPath(NSString * thePath);

enum state_t {                      // These are the "states" of the guideState state machine
    entryNoConfigurations,
    entryAddConfiguration,
    stateGoBack,                    // (This can only be a nextState, never an actual state)
    stateHasNoConfigurations,
    stateMakeSampleConfiguration,
    stateMakeEmptyConfiguration,
    stateHasConfigurations,
    stateShowTbInstructions,
};

@interface ConfigurationManager() // PRIVATE METHODS

-(BOOL)         addConfigsFromPath:         (NSString *)                folderPath
                   thatArePackages:         (BOOL)                      onlyPkgs
                            toDict:         (NSMutableDictionary * )    dict
                      searchDeeply:         (BOOL)                      deep;

-(NSString *)   displayNameForPath:         (NSString *)                thePath;

-(NSString *)   getLowerCaseStringForKey:   (NSString *)                key
                            inDictionary:   (NSDictionary *)            dict
                               defaultTo:   (id)                        replacement;

-(void)         guideState:                 (enum state_t)              state;

-(NSString *)   getPackageToInstall:        (NSString *)                thePath
                          errorMsgs:        (NSMutableArray *)          errMsgs;

-(BOOL)         isSampleConfigurationAtPath:(NSString *)                cfgPath
								  errorMsgs: (NSMutableArray *)         errMsgs;

-(NSString *)   makeEmptyTblk:              (NSString *)                thePath;

-(NSArray *) checkOneDotTblkPackage:		(NSString *)				filePath
		   overrideReplaceIdentical:		(NSString *)				overrideReplaceIdentical
			   overrideSharePackage:		(NSString *)				overrideSharePackage
				  overrideUninstall:		(NSString *)				overrideUninstall
                          errorMsgs:        (NSMutableArray *)          errMsgs;

-(NSString *)   parseString:                (NSString *)                cfgContents
                  forOption:                (NSString *)                option;

@end

@implementation ConfigurationManager

+(id)   defaultManager {
    
    return [[[ConfigurationManager alloc] init] autorelease];
}

-(NSMutableDictionary *) getConfigurations {
    
    // Returns a dictionary with information about the configuration files in gConfigDirs.
    // The key for each entry is the display name for the configuration; the object is the path to the configuration file
    // (which may be a .tblk package or a .ovpn or .conf file) for the configuration
    //
    // Only searches folders that are in gConfigDirs.
    //
    // First, it goes through gDeploy looking for packages,
    //           then through gDeploy looking for configs NOT in packages,
    //           then through L_AS_T_SHARED looking for packages (does not look for configs that are not in packages in L_AS_T_SHARED)
    //           then through gPrivatePath looking for packages,
    //           then through gPrivatePath looking for configs NOT in packages
    
    NSMutableDictionary * dict = [[[NSMutableDictionary alloc] init] autorelease];
    BOOL noneIgnored = TRUE;
    
    noneIgnored = [self addConfigsFromPath: gDeployPath  thatArePackages: YES toDict: dict searchDeeply: YES ] && noneIgnored;
    noneIgnored = [self addConfigsFromPath: gDeployPath  thatArePackages:  NO toDict: dict searchDeeply: YES ] && noneIgnored;
    noneIgnored = [self addConfigsFromPath: L_AS_T_SHARED  thatArePackages: YES toDict: dict searchDeeply: YES ] && noneIgnored;
    noneIgnored = [self addConfigsFromPath: gPrivatePath thatArePackages:   YES toDict: dict searchDeeply: YES ] && noneIgnored;
    
    if (  ! noneIgnored  ) {
        TBRunAlertPanelExtended(NSLocalizedString(@"Configuration(s) Ignored", @"Window title"),
                                NSLocalizedString(@"One or more configurations are being ignored. See the Console Log for details.", @"Window text"),
                                nil, nil, nil,
                                @"skipWarningAboutIgnoredConfigurations",          // Preference about seeing this message again
                                NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
                                nil,
								NSAlertDefaultReturn);
    }
    return dict;
}

-(NSString *) extractTblkNameFromPath: (NSString *) path {
    
    // Given a path, returns the name of the .tblk that encloses it (without the .tblk)
    // If path is a .tblk, returns the path (without the .tblk)
    // If path is not a .tblk and is not enclosed in a .tblk, returns the path
    
    // Find ".tblk" so we can ignore it and everything after it
    NSRange rng1 = [path rangeOfString: @".tblk" options: NSBackwardsSearch];
    if (  rng1.location == NSNotFound  ) { // if no ".tblk", don't ignore anything
        rng1.location = [path length];
    }
    
    // Then find the "/" before that so we can include everything after it
    NSRange rng2 = [path rangeOfString: @"/" options: NSBackwardsSearch range: NSMakeRange(0, rng1.location)];
	if (  rng2.location == NSNotFound  ) {
		rng2.location = 0;  // No "/", so include from start of string
	} else {
		rng2.location += 1; // Otherwise, don't include the "/" itself
	}
	
    NSString * returnString = [path substringWithRange: NSMakeRange(rng2.location, rng1.location - rng2.location)];
    return returnString;
}

-(BOOL)  addConfigsFromPath: (NSString *)               folderPath
            thatArePackages: (BOOL)                     onlyPkgs
                     toDict: (NSMutableDictionary *)    dict
               searchDeeply: (BOOL)                     deep {
    
    // Adds configurations to a dictionary based on input parameters
    // Returns TRUE if succeeded, FALSE if one or more configurations were ignored.
    //
    // If searching L_AS_T_SHARED, looks for .ovpn and .conf and ignores them even if searching for packages (so we can complain to the user)
    
    if (  ! [gConfigDirs containsObject: folderPath]  ) {
        return TRUE;
    }
    
    BOOL ignored = FALSE;
    NSString * file;
    
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: folderPath];
	
    if (  deep  ) {
        // Search directory and subdirectories
        while (  (file = [dirEnum nextObject])  ) {
            BOOL addIt = FALSE;
            NSString * fullPath = [folderPath stringByAppendingPathComponent: file];
            NSString * dispName = [lastPartOfPath(fullPath) stringByDeletingPathExtension];
            if (  itemIsVisible(fullPath)  ) {
                NSString * ext = [file pathExtension];
                if (  onlyPkgs  ) {
                    if (  [ext isEqualToString: @"tblk"]  ) {
                        NSString * tbPath = tblkPathFromConfigPath(fullPath);
                        if (  ! tbPath  ) {
                            NSLog(@"Tunnelblick VPN Configuration ignored: No .conf or .ovpn file in %@", fullPath);
							ignored = TRUE;
                        } else {
                            addIt = TRUE;
                        }
                    }
                } else {
                    if (  [fullPath rangeOfString: @".tblk/"].length == 0  ) {  // Ignore .ovpn and .conf in a .tblk
                        if (  [ext isEqualToString: @"ovpn"] || [ext isEqualToString: @"conf"]  ) {
                            addIt = TRUE;
                        }
                    }
                }
            }
            
            if (  addIt  ) {
                if (  invalidConfigurationName(dispName, PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING)  ) {
                    TBShowAlertWindow(NSLocalizedString(@"Name not allowed", @"Window title"),
                                      [NSString stringWithFormat: NSLocalizedString(@"Configuration '%@' will be ignored because its"
                                                                                    @" name contains characters that are not allowed.\n\n"
																			        @"Characters that are not allowed: '%s'\n\n", @"Window text"),
									   dispName, PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING]);
                } else {
                    if (  [dict objectForKey: dispName]  ) {
                        NSLog(@"Tunnelblick Configuration ignored: The name is already being used: %@", fullPath);
                        ignored = TRUE;
                    } else {
                        [dict setObject: fullPath forKey: dispName];
                    }
                    
                }
            }
        }
    } else {
        // Search directory only, not subdirectories.
        while (  (file = [dirEnum nextObject])  ) {
            [dirEnum skipDescendents];
            BOOL addIt = FALSE;
            NSString * fullPath = [folderPath stringByAppendingPathComponent: file];
            NSString * dispName = [file stringByDeletingPathExtension];
            if (  itemIsVisible(fullPath)  ) {
                NSString * ext = [file pathExtension];
                if (  onlyPkgs  ) {
                    if (  [ext isEqualToString: @"tblk"]  ) {
                        NSString * tbPath = configPathFromTblkPath(fullPath);
                        if (  ! tbPath  ) {
                            NSLog(@"Tunnelblick VPN Configuration ignored: No .conf or .ovpn file. Try reinstalling %@", fullPath);
							ignored = TRUE;
                        } else {
                            addIt = TRUE;
                        }
                    }
                } else {
                    if (  [ext isEqualToString: @"ovpn"] || [ext isEqualToString: @"conf"]  ) {
                        addIt = TRUE;
                    }
                }
                if (   [folderPath isEqualToString: L_AS_T_SHARED]
                    && ([ext isEqualToString: @"ovpn"] || [ext isEqualToString: @"conf"])  ) {
                    NSLog(@"Tunnelblick VPN Configuration ignored: Only Tunnelblick VPN Configurations (.tblk packages) may be shared %@", fullPath);
					ignored = TRUE;
                }
            }
            
            if (  addIt  ) {
                if (  [dict objectForKey: dispName]  ) {
                    NSLog(@"Tunnelblick Configuration ignored: The name is already being used: %@", fullPath);
					ignored = TRUE;
                } else {
                    [dict setObject: fullPath forKey: dispName];
                }
            }
        }
    }
    
    return  ! ignored;
}            

-(BOOL) userCanEditConfiguration: (NSString *) filePath {
    
    NSString * extension = [filePath pathExtension];
    if (  ! (   [extension isEqualToString: @"tblk"]
             || [extension isEqualToString: @"ovpn"]
             || [extension isEqualToString: @"conf"]
             )  ) {
        NSLog(@"Internal error: %@ is not a .tblk, .conf, or .ovpn", filePath);
        return NO;
    }
    
    NSString * realPath = (  [extension isEqualToString: @"tblk"]
						   ? [filePath stringByAppendingPathComponent: @"Contents/Resources/config.ovpn"]
						   : [[filePath retain] autorelease]);
    
    // File must exist and we must be able to write to the file and its parent directory
    if (   [gFileMgr fileExistsAtPath:     realPath]
		&& [gFileMgr isWritableFileAtPath: realPath]
        && [gFileMgr isWritableFileAtPath: [realPath stringByDeletingLastPathComponent]]  ) {
        return YES;
    }
    
    return NO;
}

-(void) examineConfigFileForConnection: (VPNConnection *) connection {
    
    // Display the sanitized contents of the configuration file in a window
    
    NSString * configFileContents = [connection sanitizedConfigurationFileContents];
    if (  configFileContents  ) {
        NSString * heading = [NSString stringWithFormat: NSLocalizedString(@"%@ OpenVPN Configuration - Tunnelblick", @"Window title"),[connection displayName]];
        
        // NOTE: The window controller is allocated here, but releases itself when the window is closed.
        //       So _we_ don't release it, and we can overwrite listingWindow with impunity.
        //       (The class variable 'listingWindow' is used to avoid an analyzer warning about a leak.)
        listingWindow = [[ListingWindowController alloc] initWithHeading: heading
                                                                    text: configFileContents];
        [listingWindow showWindow: self];
    } else {
        TBShowAlertWindow(NSLocalizedString(@"Warning", @"Window title"),
                          NSLocalizedString(@"Tunnelblick could not find the configuration file or the configuration file could not be sanitized. See the Console Log for details.", @"Window text"));
    }
}


-(void) editOrExamineConfigurationForConnection: (VPNConnection *) connection {
    
    NSString * targetPath = [connection configPath];
    if ( ! targetPath  ) {
        NSLog(@"editOrExamineConfigurationForConnection: No path for configuration %@", [connection displayName]);
        return;
    }
    
    if (  [self userCanEditConfiguration: targetPath]  ) {
		if (  [[targetPath pathExtension] isEqualToString: @"tblk"]  ) {
			targetPath = [targetPath stringByAppendingPathComponent: @"Contents/Resources/config.ovpn"];
		}
        [connection invalidateConfigurationParse];
        [[NSWorkspace sharedWorkspace] openFile: targetPath withApplication: @"TextEdit"];
    } else {
        [self examineConfigFileForConnection: connection];
    }
}

-(void) shareOrPrivatizeAtPath: (NSString *) path {
    
    // Make a private configuration shared, or a shared configuration private
    
    NSString * source;
    NSString * target;
    NSString * msg;
	
    if (  [[path pathExtension] isEqualToString: @"tblk"]  ) {
        NSString * last = lastPartOfPath(path);
        NSString * name = [last stringByDeletingPathExtension];
        if (  [path hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]  ) {
            NSString * lastButOvpn = [name stringByAppendingPathExtension: @"ovpn"];
            NSString * lastButConf = [name stringByAppendingPathExtension: @"conf"];
            if (   [gFileMgr fileExistsAtPath: [gPrivatePath stringByAppendingPathComponent: last]]
                || [gFileMgr fileExistsAtPath: [gPrivatePath stringByAppendingPathComponent: lastButOvpn]]
                || [gFileMgr fileExistsAtPath: [gPrivatePath stringByAppendingPathComponent: lastButConf]]  ) {
                int result = TBRunAlertPanel(NSLocalizedString(@"Replace Existing Configuration?", @"Window title"),
                                             [NSString stringWithFormat: NSLocalizedString(@"A private configuration named '%@' already exists.\n\nDo you wish to replace it with the shared configuration?", @"Window text"), name],
                                             NSLocalizedString(@"Replace", @"Button"),
                                             NSLocalizedString(@"Cancel" , @"Button"),
                                             nil);
                if (  result != NSAlertDefaultReturn  ) {   // No action if cancelled or error occurred
                    return;
                }
            }
            
            source = [[path copy] autorelease];
            target = [gPrivatePath stringByAppendingPathComponent: last];
            msg = [NSString stringWithFormat: NSLocalizedString(@"You have asked to make the '%@' configuration private, instead of shared.", @"Window text"), name];
        } else if (  [path hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
            source = [[path copy] autorelease];
            target = [L_AS_T_SHARED stringByAppendingPathComponent: last];
            msg = [NSString stringWithFormat: NSLocalizedString(@"You have asked to make the '%@' configuration shared, instead of private.", @"Window text"), name];
        } else {
            NSLog(@"shareOrPrivatizeAtPath: Internal error: path is not private or shared at %@", path);
            return;
        }
        
        AuthorizationRef authRef = [NSApplication getAuthorizationRef: msg];
        if ( authRef == NULL ) {
            return;
        }
        
        [self copyConfigPath: source
                      toPath: target
             usingAuthRefPtr: &authRef
                  warnDialog: YES
                 moveNotCopy: YES];
        
        AuthorizationFree(authRef, kAuthorizationFlagDefaults);
    }
}

-(NSString *)parseConfigurationPath: (NSString *) cfgPath
                      forConnection: (VPNConnection *) connection {
    
    // Parses the configuration file.
    // Gives user the option of adding the down-root plugin if appropriate
    // Returns with device type: "tun" or "tap", or nil if it can't be determined
    // Returns with string "Cancel" if user cancelled
	
    NSString * doNotParseKey = [[connection displayName] stringByAppendingString: @"-doNotParseConfigurationFile"];
    if (  [gTbDefaults boolForKey: doNotParseKey]  ) {
        return nil;
    }
    
    NSString * cfgFile = lastPartOfPath(cfgPath);
    NSString * configLocString = configLocCodeStringForPath(cfgPath);
    NSArray * arguments = [NSArray arrayWithObjects: @"printSanitizedConfigurationFile", cfgFile, configLocString, nil];
    NSString * stdOut;
    NSString * stdErrOut;
    OSStatus status = runOpenvpnstart(arguments, &stdOut, &stdErrOut);
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"Internal failure (%lu) of openvpnstart printSanitizedConfigurationFile %@ %@", (unsigned long)status, cfgFile, configLocString);
        return nil;
    }
    
    NSString * cfgContents = [stdOut copy];
    
    NSString * userOption  = [self parseString: cfgContents forOption: @"user" ];
    if (  [userOption length] == 0  ) {
        userOption = nil;
    }
    NSString * groupOption = [self parseString: cfgContents forOption: @"group"];
    if (  [groupOption length] == 0  ) {
        groupOption = nil;
    }
    NSString * useDownRootPluginKey = [[connection displayName] stringByAppendingString: @"-useDownRootPlugin"];
    NSString * skipWarningKey = [[connection displayName] stringByAppendingString: @"-skipWarningAboutDownroot"];
    if (   ( ! [gTbDefaults boolForKey: useDownRootPluginKey] )
        &&     [gTbDefaults canChangeValueForKey: useDownRootPluginKey]
        && ( ! [gTbDefaults boolForKey: skipWarningKey] )  ) {
        
        NSString * downOption  = [self parseString: cfgContents forOption: @"down" ];
        if (  [downOption length] == 0  ) {
            downOption = nil;
        }

        if (   (userOption || groupOption)
            && (   downOption
                || ([connection useDNSStatus] != 0)  )  ) {
                
                NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"The configuration file for '%@' appears to use the 'user' and/or 'group' options and is using a down script ('Do not set nameserver' not selected, or there is a 'down' option in the configuration file).\n\nIt is likely that restarting the connection (done automatically when the connection is lost) will fail unless the 'openvpn-down-root.so' plugin for OpenVPN is used.\n\nDo you wish to use the plugin?", @"Window text"),
                                  [connection displayName]];
                
                int result = TBRunAlertPanelExtended(NSLocalizedString(@"Use 'down-root' plugin for OpenVPN?", @"Window title"), 
                                                     msg,
                                                     NSLocalizedString(@"Do not use the plugin", @"Button"),
                                                     NSLocalizedString(@"Always use the plugin", @"Button"),
                                                     NSLocalizedString(@"Cancel", @"Button"), 
                                                     skipWarningKey, 
                                                     NSLocalizedString(@"Do not warn about this again for this configuration", @"Checkbox name"), 
                                                     nil,
													 NSAlertDefaultReturn);
                if (  result == NSAlertAlternateReturn  ) {
                    [gTbDefaults setBool: TRUE forKey: useDownRootPluginKey];
                } else if (  result != NSAlertDefaultReturn  ) {   // No action if cancelled or error occurred
                    [cfgContents release];
                    return @"Cancel";
                }
            }
    }
    
    if (   (   [gTbDefaults boolForKey: useDownRootPluginKey]
            && [gTbDefaults canChangeValueForKey: useDownRootPluginKey] )
        && (! (userOption || groupOption))  ) {
        [gTbDefaults removeObjectForKey: useDownRootPluginKey];
        NSLog(@"Removed '%@' preference", useDownRootPluginKey);
    }
    
    NSString * devTypeOption = [[self parseString: cfgContents forOption: @"dev-type"] lowercaseString];
    if (  devTypeOption  ) {
        if (   [devTypeOption isEqualToString: @"tun"]
            || [devTypeOption isEqualToString: @"tap"]  ) {
            [cfgContents release];
            return devTypeOption;
        } else {
            NSLog(@"The configuration file for '%@' contains a 'dev-type' option, but the argument is not 'tun' or 'tap'. It has been ignored", [connection displayName]);
        }
    }
    
    NSArray * reservedOptions = OPENVPN_OPTIONS_THAT_CAN_ONLY_BE_USED_BY_TUNNELBLICK;
    NSString * option;
    NSEnumerator * e = [reservedOptions objectEnumerator];
    while (  (option = [e nextObject])  ) {
        NSString * optionValue = [self parseString: cfgContents forOption: option];
        if (  optionValue  ) {
            NSLog(@"The configuration file for '%@' contains an OpenVPN '%@' option. That option is reserved for use by Tunnelblick. The option will be ignored", [connection displayName], option);
		}
    }
    
    NSArray * windowsOnlyOptions = OPENVPN_OPTIONS_THAT_ARE_WINDOWS_ONLY;
    e = [windowsOnlyOptions objectEnumerator];
    while (  (option = [e nextObject])  ) {
        NSString * optionValue = [self parseString: cfgContents forOption: option];
        if (  optionValue  ) {
            NSLog(@"The OpenVPN configuration file in %@ contains a '%@' option, which is a Windows-only option. It cannot be used on OS X.", [connection displayName], option);
            NSString * msg = [NSString stringWithFormat:
                              NSLocalizedString(@"The OpenVPN configuration file in %@ contains a '%@' option, which is a Windows-only option. It cannot be used on OS X.", @"Window text"),
                              [connection displayName], option];
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick Error", @"Window title"),
                              msg);
            [cfgContents release];
            return nil;
		}
    }
    
    NSString * devOption = [self parseString: cfgContents forOption: @"dev"];
    NSString * devOptionFirst3Chars = [[devOption copy] autorelease];
    if (  [devOption length] > 3  ) {
        devOptionFirst3Chars = [devOption substringToIndex: 3];
    }
    devOptionFirst3Chars = [devOptionFirst3Chars lowercaseString];
	
    if (   ( ! devOption )
        || ( ! (   [devOptionFirst3Chars isEqualToString: @"tun"]
                || [devOptionFirst3Chars isEqualToString: @"tap"]  )  )  ) {
        NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"The configuration file for '%@' does not appear to contain a 'dev tun' or 'dev tap' option. This option may be needed for proper Tunnelblick operation. Consult with your network administrator or the OpenVPN documentation.", @"Window text"),
						  [connection displayName]];
        NSString * skipWarningKey = [[connection displayName] stringByAppendingString: @"-skipWarningAboutNoTunOrTap"];
        TBRunAlertPanelExtended(NSLocalizedString(@"No 'dev tun' or 'dev tap' found", @"Window title"), 
                                msg,
                                nil, nil, nil,
                                skipWarningKey, 
                                NSLocalizedString(@"Do not warn about this again for this configuration", @"Checkbox name"), 
                                nil,
								NSAlertDefaultReturn);
        [cfgContents release];
        return nil;
    }
    [cfgContents release];
    return devOptionFirst3Chars;
}

-(NSString *) parseString: (NSString *) cfgContents
                forOption: (NSString *) option {
    
    // Returns nil if the option is not found in the string that contains the contents of the configuration file
    // Returns an empty string if the option is found but has no parameters
    // Otherwise, returns the first parameter
    
    NSCharacterSet * notWhitespace = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
    NSCharacterSet * notWhitespaceNotNewline = [[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet];
    NSCharacterSet * newline = [NSCharacterSet characterSetWithCharactersInString: @"(\n\r"];
    NSRange mainRng = NSMakeRange(0, [cfgContents length]);
    unsigned int mainEnd = mainRng.length;
    
    unsigned int curPos = 0;
    while (  curPos < mainEnd  ) {
        mainRng.location = curPos;
        mainRng.length = mainEnd - curPos;
        
        // Skip whitespace, including newlines
        NSRange restRng = [cfgContents rangeOfCharacterFromSet: notWhitespaceNotNewline
                                                       options: 0
                                                         range: mainRng];
        if (  restRng.length == 0  ) {
            break;
        } else {
            curPos = restRng.location;
            mainRng.location = restRng.location;
            mainRng.length   = mainEnd - mainRng.location;
        }
		
		NSUInteger startOfLine = mainRng.location;
        
        // If option is next
        NSRange optRng = NSMakeRange(curPos, [option length]);
        if (   (  (optRng.location + optRng.length) <= mainEnd  )
            && [[cfgContents substringWithRange: optRng] caseInsensitiveCompare: option] == NSOrderedSame  ) {
            
            // Skip mandatory whitespace between option and rest of line
            mainRng.location = optRng.location + optRng.length;
            mainRng.length = mainEnd - mainRng.location;
            restRng = [cfgContents rangeOfCharacterFromSet: notWhitespace
                                                   options: 0
                                                     range: mainRng];
			
			// If first thing after whitespace is a LF, then return an empty string
			if (  [[cfgContents substringWithRange: restRng] isEqualToString: @"\n"]  ) {
				return @"";
			}
			
            if (  restRng.location != mainRng.location  ) {
				
				// Whitespace found, so "value" for option is the next token
                mainRng.location = restRng.location;
                mainRng.length = mainEnd - mainRng.location;
                NSRange nlRng = [cfgContents rangeOfCharacterFromSet: newline
                                                             options: 0
                                                               range: mainRng];
				NSRange rolRng; // range of rest of line
                if (  nlRng.length == 0  ) {
                    rolRng = NSMakeRange(mainRng.location, mainEnd - mainRng.location);
                } else {
                    rolRng = NSMakeRange( mainRng.location, nlRng.location - mainRng.location);
                }
				
				NSString * firstCh = [cfgContents substringWithRange: NSMakeRange(rolRng.location, 1)];
				if (   [firstCh isEqualToString: @"\""]
					|| [firstCh isEqualToString: @"'"]  ) {
					
					// quoted token is everything after first quote up to but not including last quote in line
					NSRange endQuoteRng = [cfgContents rangeOfString: firstCh
															 options: NSBackwardsSearch
															   range: rolRng];
					if (  endQuoteRng.location != rolRng.location  ) {
						return [cfgContents substringWithRange: NSMakeRange(rolRng.location + 1, endQuoteRng.location - rolRng.location - 1)];
					}
					
					NSLog(@"Error; unterminated %@ in '%@'",
						  firstCh,
						  [cfgContents substringWithRange:
						   NSMakeRange(startOfLine, rolRng.location + rolRng.length - startOfLine)]);
				}
				
				// normal; token is everything to first whitespace
				NSRange wsRng = [cfgContents rangeOfCharacterFromSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]
															 options: 0
															   range: rolRng];
				if (  wsRng.length == 0  ) {
					return [cfgContents substringWithRange: rolRng];
				} else {
					return [cfgContents substringWithRange:
							NSMakeRange(rolRng.location, wsRng.location - rolRng.location)];
				}
				
				return [cfgContents substringWithRange: rolRng];
            }
            // No whitespace after option, so it is no good (optionXXX)
        }
        
        // Skip to next \n
        restRng = [cfgContents rangeOfCharacterFromSet: newline
                                               options: 0
                                                 range: mainRng];
        if (  restRng.length == 0 ) {
            curPos = mainEnd;
        } else {
            curPos = restRng.location + restRng.length;
        }
    }
	
    return nil;
}

-(BOOL) fileSizeOKAtPath: (NSString *)       path
             inTblkNamed: (NSString *)       tblkName
                 errMsgs: (NSMutableArray *) errMsgs {
    
    NSString * errMsg = fileIsReasonableSize(path);
    if (  errMsg  ) {
        NSLog(@"%@", errMsg);
        [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"There is a problem in %@: %@", "Window text"),
                             tblkName, errMsg]];
        return FALSE;
    }
    
    return  TRUE;
}

-(BOOL) fileReferencesInConfigAreOk: (NSString *)       cfgPath
						  errorMsgs: (NSMutableArray *) errMsgs {
    
	NSString * tblkName = [[[[cfgPath stringByDeletingLastPathComponent]
							 stringByDeletingLastPathComponent]
							stringByDeletingLastPathComponent]
						   lastPathComponent];
    
    if (  ! [self fileSizeOKAtPath: cfgPath inTblkNamed: tblkName errMsgs: errMsgs]  ) {
        return FALSE;
    }
    
    NSData * data = [gFileMgr contentsAtPath: cfgPath];
    NSString * cfgContents = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
    
    NSString * option;

	// First, check for OpenVPN options that cannot be used with Tunnelblick
	NSArray * optionsThatAreNotAllowed = OPENVPN_OPTIONS_THAT_CAN_ONLY_BE_USED_BY_TUNNELBLICK;
    NSEnumerator * e = [optionsThatAreNotAllowed objectEnumerator];
	while (  (option = [e nextObject])  ) {
        if(  [self parseString: cfgContents forOption: option]  ) {
			NSLog(@"The OpenVPN configuration file in %@ contains a '%@' option, which cannot be used with Tunnelblick.",
				  tblkName, option);
			[errMsgs addObject: [NSString stringWithFormat:
								 NSLocalizedString(@"The OpenVPN configuration file in %@ contains a '%@' option, which cannot be used with Tunnelblick.", "Window text"),
								 tblkName, option]];
			return FALSE;
		}
	}
	
	// Next, check for OpenVPN options that are not allowed on OS X
	optionsThatAreNotAllowed = OPENVPN_OPTIONS_THAT_ARE_WINDOWS_ONLY;
    e = [optionsThatAreNotAllowed objectEnumerator];
	while (  (option = [e nextObject])  ) {
        if(  [self parseString: cfgContents forOption: option]  ) {
			NSLog(@"The OpenVPN configuration file in %@ contains a '%@' option, which is a Windows-only option. It cannot be used on OS X.",
				  tblkName, option);
			[errMsgs addObject: [NSString stringWithFormat:
								 NSLocalizedString(@"The OpenVPN configuration file in %@ contains a '%@' option, which is a Windows-only option. It cannot be used on OS X.", "Window text"),
								 tblkName, option]];
			return FALSE;
		}
	}
	
    // List of OpenVPN options that take a file path
    NSArray * optionsWithPath = [NSArray arrayWithObjects:
								 // @"askpass",                    // askpass        'file' not supported since we don't compile with --enable-password-save
								 // @"auth-user-pass",             // auth-user-pass 'file' not supported since we don't compile with --enable-password-save
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
    
    e = [optionsWithPath objectEnumerator];
    while (  (option = [e nextObject])  ) {
        NSString * argument = [self parseString: cfgContents forOption: option];
        if (  argument  ) {
            if (   ([argument rangeOfString: @".."].length != 0)  ) {
				NSLog(@"The OpenVPN configuration file in %@ has a '%@' option with argument '%@' which includes \"..\", which is not allowed.",
					  tblkName, option, argument);
				[errMsgs addObject: [NSString stringWithFormat:
									 NSLocalizedString(@"The OpenVPN configuration file in %@ has a '%@' option with argument '%@' that includes \"..\", which is not allowed.", "Window text"),
									 tblkName, option, argument]];
                return FALSE;
            }
            if (   [argument hasPrefix: @"/"]
                || [argument hasPrefix: @"~"]  ) {
				NSLog(@"The OpenVPN configuration file in %@ has a '%@' option with argument '%@' which begins with \"%@\", which is not allowed.",
					  tblkName, option, argument, [argument substringWithRange: NSMakeRange(0, 1)]);
				[errMsgs addObject: [NSString stringWithFormat:
									  NSLocalizedString(@"The OpenVPN configuration file in %@ has a '%@' option with argument '%@' that begins with \"%@\", which is not allowed.", "Window text"),
									  tblkName, option, argument, [argument substringWithRange: NSMakeRange(0, 1)]]];
                return FALSE;
            }
            if (  ! [argument isEqualToString: @"[inline]"]  ) {
                if (  [argument length] == 0  ) {
                    NSLog(@"The OpenVPN configuration file in %@ has a '%@' option with no argument, which is not allowed.",
                          tblkName, option);
                    [errMsgs addObject: [NSString stringWithFormat:
                                         NSLocalizedString(@"The OpenVPN configuration file in %@ has a '%@' option with no argument, which is not allowed.", "Window text"),
                                         tblkName, option]];
                    return FALSE;
                }
                NSString * newPath = [[cfgPath stringByDeletingLastPathComponent] stringByAppendingPathComponent: [argument lastPathComponent]];
                if (  [gFileMgr fileExistsAtPath: newPath]  ) {
                    if (  [NONBINARY_CONTENTS_EXTENSIONS containsObject: [newPath pathExtension]]  ) {
                        if (  ! [self fileSizeOKAtPath: newPath inTblkNamed: tblkName errMsgs: errMsgs]  ) {
                            return FALSE;
                        }
                        NSString * errorText = errorIfNotPlainTextFileAtPath(newPath, YES, nil); // No comments in these files
                        if (  errorText  ) {
                            NSLog(@"Error in %@ (referenced in %@): %@", newPath, tblkName, errorText);
							[errMsgs addObject: [NSString stringWithFormat:
												 NSLocalizedString(@"The OpenVPN configuration file in '%@' has a '%@' option that references '%@'. That file has a problem:\n\n%@.", "Window text"),
												 [tblkName stringByDeletingPathExtension], option, argument, errorText]];
                            return FALSE;
                        }
                    }
                } else {
                    NSLog(@"The OpenVPN configuration file in %@ has a '%@' option with file '%@' which cannot be found.",
                          tblkName, option, argument);
					[errMsgs addObject: [NSString stringWithFormat:
										 NSLocalizedString(@"The OpenVPN configuration file in '%@' has a '%@' option that references '%@' which cannot be found.\n\nThe file must be included in the Tunnelblick VPN Configuration (.tblk).", "Window text"),
										 [tblkName stringByDeletingPathExtension], option, argument]];
                    return FALSE;
                }
            }
        }
    }
    
    return TRUE;
}

-(NSDictionary *) infoPlistForTblkAtPath: (NSString *) path {
    
    NSString * infoPlistPath = [path stringByAppendingPathComponent:@"/Contents/Info.plist"];
    
    if (  ! [gFileMgr fileExistsAtPath: infoPlistPath]  ) {
        infoPlistPath = [path stringByAppendingPathComponent:@"Info.plist"];
    }
    
    return [NSDictionary dictionaryWithContentsOfFile: infoPlistPath];
}

-(void) openDotTblkPackages: (NSArray *) filePaths
                  usingAuth: (AuthorizationRef) authRef
    skipConfirmationMessage: (BOOL) skipConfirmMsg
          skipResultMessage: (BOOL) skipResultMsg
             notifyDelegate: (BOOL) notifyDelegate {
    
    // The filePaths array entries are NSStrings with the path to a .tblk to install.
    
    // Make sure all files inside each .tblk are reasonable
    NSString * tooBigMsg = nil;
    NSString * path;
    NSEnumerator * e = [filePaths objectEnumerator];
    while (  (path = [e nextObject])  ) {
		tooBigMsg = allFilesAreReasonableIn(path);
        if (  tooBigMsg  ) {
			break;
        }
    }
    if (  tooBigMsg  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick VPN Configuration Installation Error", @"Window title"),
                          [NSString stringWithFormat:
						   NSLocalizedString(@"There was a problem:\n\n"
										     @"%@", "Window text"),
						   tooBigMsg]);
        if (  notifyDelegate  ) {
            [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
        }
        return;
    }
    
    if (  [gTbDefaults boolForKey: @"doNotOpenDotTblkFiles"]  )  {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick VPN Configuration Installation Error", @"Window title"),
                          NSLocalizedString(@"Installation of .tblk packages is not allowed", "Window text"));
        if (  notifyDelegate  ) {
            [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
        }
        return;
    }
    
    BOOL isDeployed = [gFileMgr fileExistsAtPath: gDeployPath];
    BOOL installToPrivateOK = (   (! isDeployed)
                               || (   [gTbDefaults boolForKey: @"usePrivateConfigurationsWithDeployedOnes"]
                                   && ( ! [gTbDefaults canChangeValueForKey: @"usePrivateConfigurationsWithDeployedOnes"])
                                   )  );
    BOOL installToSharedOK = (   (! isDeployed)
                              || (   [gTbDefaults boolForKey: @"useSharedConfigurationsWithDeployedOnes"]
                                  && ( ! [gTbDefaults canChangeValueForKey: @"useSharedConfigurationsWithDeployedOnes"])
                                  )  );
    
    if (  ! installToPrivateOK  ) {
        if (  ! installToSharedOK  ) {
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick VPN Configuration Installation Error", @"Window title"),
                              NSLocalizedString(@"Installation of Tunnelblick VPN Configurations is not allowed because this is a Deployed version of Tunnelblick.", "Window text"));
            if (  notifyDelegate  ) {
                [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
            }
            return;
        }
    }
    
    NSMutableArray * sourceList = [NSMutableArray arrayWithCapacity: [filePaths count]];        // Paths to source of files OK to install
    NSMutableArray * targetList = [NSMutableArray arrayWithCapacity: [filePaths count]];        // Paths to destination to install them
    NSMutableArray * deleteList = [NSMutableArray arrayWithCapacity: [filePaths count]];        // Paths to delete
    NSMutableArray * errMsgs    = [NSMutableArray arrayWithCapacity: 30];                       // Array of strings with error messages
    
    // Go through the array, check each .tblk package, and add it to the install list if it is OK
    NSArray * dest;
    NSMutableArray * innerTblksAlreadyProcessed = [NSMutableArray arrayWithCapacity: 10];
    unsigned i;
    for (i=0; i < [filePaths count]; i++) {
        NSString * path = [filePaths objectAtIndex: i];
        
        NSString * overrideReplaceIdentical = nil;
		NSString * overrideSharePackage     = nil;
		NSString * overrideUninstall        = nil;
		
        // Set up overrides for TBReplaceIdentical, TBSharePackage, and TBUninistall
        if (  [path hasSuffix: @".tblk"]  ) {
            NSDictionary * infoPlist = [self infoPlistForTblkAtPath: path];
            
            overrideReplaceIdentical = [infoPlist objectForKey: @"TBReplaceIdentical"];
			if (  overrideReplaceIdentical  ) {
				NSArray * okValues = [NSArray arrayWithObjects: @"yes", @"no", @"ask", @"force", nil];
				if (  ! [okValues containsObject: overrideReplaceIdentical]  ) {
                    NSLog(@"Configuration installer: The Info.plist in %@ contains an invalid TBReplaceIdentical value of '%@'", path, overrideReplaceIdentical);
                    [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"The Info.plist in '%@' contains an invalid 'TBReplaceIdentical' value of '%@'.\n\nThe value must be 'yes', 'no', 'ask', or 'force'.", @"Window text"), [self extractTblkNameFromPath: path], overrideReplaceIdentical]];
					overrideReplaceIdentical = nil;
				}
			}
			
            overrideSharePackage = [infoPlist objectForKey: @"TBSharePackage"];
			if (  overrideSharePackage  ) {
				NSArray * okValues = [NSArray arrayWithObjects: @"private", @"shared", @"ask", nil];
				if (  ! [okValues containsObject: overrideSharePackage]  ) {
                    NSLog(@"Configuration installer: The Info.plist in %@ contains an invalid TBSharePackage value of '%@'", path, overrideSharePackage);
                    [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"The Info.plist in '%@' contains an invalid 'TBSharePackage' value of '%@'.\n\nThe value must be 'private', 'shared', or 'ask'.", @"Window text"), [self extractTblkNameFromPath: path], overrideSharePackage]];
					overrideSharePackage = nil;
				}
			}
			
            overrideUninstall = [infoPlist objectForKey: @"TBUninstall"];
        }
        
        // Deal with nested .tblks -- i.e., .tblks inside of a .tblk. One level of that is processed.
        // If there are any .tblks inside the .tblk, the .tblk itself is not created, only the inner .tblks
        // The inner .tblks may be inside subfolders of the outer .tblk, in which case they
        // will be installed into subfolders of the private or shared configurations folder.
        NSString * innerFileName;
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: path];
        while (  (innerFileName = [dirEnum nextObject])  ) {
            NSString * fullInnerPath = [path stringByAppendingPathComponent: innerFileName];
            if (   [[innerFileName pathExtension] isEqualToString: @"tblk"]  ) {
                
                // If have already processed a .tblk that contains this one, it is an error
                // because it is a second level of enclosed .tblks.
                // A message is inserted into the log, and the inner-most .tblk is skipped.
                NSString * testPath;
                BOOL nestedTooDeeply = FALSE;
                NSEnumerator * arrayEnum = [innerTblksAlreadyProcessed objectEnumerator];
                while (  (testPath = [arrayEnum nextObject])  ) {
                    if (  [fullInnerPath hasPrefix: testPath]  ) {
                        NSLog(@"Configuration installer: .tblks are nested too deeply (only one level of .tblk in a .tblk is allowed) in %@", path);
                        [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@".tblks are nested too deeply (only one level of .tblk in a .tblk is allowed) in '%@'.", @"Window text"), [self extractTblkNameFromPath: path]]];
                        nestedTooDeeply = TRUE;
                        break;
                    }
                }
                
                if (  ! nestedTooDeeply  ) {
                    // This .tblk is not nested too deeply, so process it
                    dest = [self checkOneDotTblkPackage: fullInnerPath
							   overrideReplaceIdentical: overrideReplaceIdentical
								   overrideSharePackage: overrideSharePackage
									  overrideUninstall: overrideUninstall
                                              errorMsgs: errMsgs];
                    if (  dest  ) {
                        if (  [dest count] == 2  ) {
                            [sourceList addObject: [dest objectAtIndex: 0]];
                            [targetList addObject: [dest objectAtIndex: 1]];
                        } else if (  [dest count] == 1  ) {
                            [deleteList addObject: [dest objectAtIndex: 0]];
                        } else if (  [dest count] > 2  ) {
                            NSLog(@"Configuration installer: Program error, please report this as a bug: Invalid dest = %@ for .tblk %@", dest, fullInnerPath);
                            [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"Program error, please report this as a bug: Invalid dest = %@ for .tblk '%@'.", @"Window text"), dest, fullInnerPath]];
                        }
                    }
                    [innerTblksAlreadyProcessed addObject: fullInnerPath];
                }
            }
        }
        
        if (  [innerTblksAlreadyProcessed count] == 0  ) {
            dest = [self checkOneDotTblkPackage: path
                       overrideReplaceIdentical: nil    // Don't override the .tblk itself!
                           overrideSharePackage: nil
                              overrideUninstall: nil
                                      errorMsgs: errMsgs];
            if (  dest  ) {
                if (  [dest count] == 2  ) {
                    [sourceList addObject: [dest objectAtIndex: 0]];
                    [targetList addObject: [dest objectAtIndex: 1]];
                } else if (  [dest count] == 1  ) {
                    [deleteList addObject: [dest objectAtIndex: 0]];
                } else if (  [dest count] > 2  ) {
                    NSLog(@"Configuration installer: Program error, please report this as a bug: Invalid dest = %@ for .tblk %@", dest, path);
                    [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"Program error, please report this as a bug: Invalid dest = %@ for .tblk '%@'.", @"Window text"), dest, path]];
                }
            }
        } else {
            [innerTblksAlreadyProcessed removeAllObjects];
        }
    }
    
    if (   ([deleteList count] == 0)
        && ([sourceList count] == 0)  ) {
        
        if (  [errMsgs count] == 0  ) {
            if (  notifyDelegate  ) {
                [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyCancel];
				return;
            }
        }
    }
    
    if (  [errMsgs count] != 0  ) {
        NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"One or more configurations could not be installed.\n\n%@", @"Window text"), [errMsgs objectAtIndex: 0]];
		
        if (  [errMsgs count] != 1  ) {
            msg = [msg stringByAppendingString:NSLocalizedString(@"\n\nOther problems were also found, but they are likely to be a result of that problem. See the Console Log for details.", @"Window text")];
        }
        
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick VPN Configuration Installation Error", @"Window title"),
                          msg);
        if (  notifyDelegate  ) {
            [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
        }
        return;
    }
    
    // **************************************************************************************
    // Ask, and then install the packages
    
	NSString * windowHeaderText = ([deleteList count] == 0
								   ? NSLocalizedString(@"Install?", @"Window title")
								   : ([sourceList count] == 0
                                      ? NSLocalizedString(@"Uninstall?", @"Window title")
                                      : NSLocalizedString(@"Install and Uninstall?", @"Window title")
                                      )
                                   );
    
    NSString * windowText = NSLocalizedString(@"Tunnelblick needs to:\n\n", @"Window text");
    
    if (  [deleteList count] == 1  ) {
        windowText = [windowText stringByAppendingString:
					  NSLocalizedString(@"  • Uninstall one configuration\n\n", @"Window text")];
    } else if (  [deleteList count] > 1  ) {
        windowText = [windowText stringByAppendingFormat:
					  NSLocalizedString(@"  • Uninstall %ld configurations\n\n", @"Window text"),
					  (unsigned long) [deleteList count]];
    }
    
    if (  [sourceList count] == 1  ) {
        windowText = [windowText stringByAppendingString:
					  NSLocalizedString(@"  • Install one configuration\n\n", @"Window text")];
    } else if (  [sourceList count] > 0  ) {
        windowText = [windowText stringByAppendingFormat:
					  NSLocalizedString(@"  • Install %ld configurations\n\n", @"Window text"),
					  (unsigned long) [sourceList count]];
    }
    
    AuthorizationRef localAuth = authRef;
    if (  authRef  ) {
        
        // We have an AuthorizationRef, but ask ask the user for confirmation anyway (but don't ask for a password)
        if (   ( ! skipConfirmMsg )  ) {
            int result = TBRunAlertPanel(windowHeaderText,
                                         windowText,
                                         NSLocalizedString(@"OK", @"Button"),       // Default
                                         nil,                                       // Alternate
                                         NSLocalizedString(@"Cancel", @"Button"));  // Other
            if (  result != NSAlertDefaultReturn  ) {   // No action if cancelled or error occurred
                if (  notifyDelegate  ) {
                    [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyCancel];
                }
                
                return;
            }
        }
    } else {
        
        // We don't have an AuthorizationRef, so get one
        localAuth = [NSApplication getAuthorizationRef: windowText];
    }
    
    if (  ! localAuth  ) {
        NSLog(@"Configuration installer: The Tunnelblick VPN Configuration installation was cancelled by the user.");
        if (  notifyDelegate  ) {
            [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyCancel];
        }
        return;
    }
    
    int nErrors = 0;
	
    for (  i=0; i < [deleteList count]; i++  ) {
        NSString * target = [deleteList objectAtIndex: i];
        if (  ! [self deleteConfigPath: target
                       usingAuthRefPtr: &localAuth
                            warnDialog: NO]  ) {
            nErrors++;
        }
    }
    
    for (  i=0; i < [sourceList count]; i++  ) {
        NSString * source = [sourceList objectAtIndex: i];
        NSString * target = [targetList objectAtIndex: i];
		NSString * targetDisplayName = [lastPartOfPath(target) stringByDeletingPathExtension];
		NSDictionary * connDict = [[NSApp delegate] myVPNConnectionDictionary];
		BOOL replacedTblk = (nil != [connDict objectForKey: targetDisplayName]);
        if (  ! [self copyConfigPath: source
                              toPath: target
                     usingAuthRefPtr: &localAuth
                          warnDialog: NO
                         moveNotCopy: NO]  ) {
            nErrors++;
            [gFileMgr tbRemoveFileAtPath:target handler: nil];
        }
        NSRange r = [source rangeOfString: @"/TunnelblickTemporaryDotTblk-"];
        if (  r.length != 0  ) {
            [gFileMgr tbRemoveFileAtPath:[source stringByDeletingLastPathComponent] handler: nil];
        }
        
		if (  replacedTblk  ) {
            // Force a reload of the configuration's preferences using any new TBPreference and TBAlwaysSetPreference items it its Info.plist
            [[NSApp delegate] deleteExistingConfig: targetDisplayName ];
            [[NSApp delegate] addNewConfig: target withDisplayName: targetDisplayName];
            [[[NSApp delegate] logScreen] update];
		}
    }
    
    if (  ! authRef  ) {    // If we weren't given an AuthorizationRef, free the one we got
        AuthorizationFree(localAuth, kAuthorizationFlagDefaults);
    }
    
    if (  nErrors != 0  ) {
        NSString * msg;
        if (  nErrors == 1) {
            msg = NSLocalizedString(@"A configuration was not installed. See the Console log for details.", @"Window text");
        } else {
            msg = [NSString stringWithFormat: NSLocalizedString(@"%d configurations were not installed. See the Console Log for details.", "Window text"),
                   nErrors];
        }
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick VPN Configuration Installation Error", @"Window title"),
                          msg);
        if (  notifyDelegate  ) {
            [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
        }
    } else {
        unsigned nOK = [sourceList count];
        unsigned nUninstalled = [deleteList count];
        NSString * msg;
        if (  nUninstalled == 1  ) {
            msg = NSLocalizedString(@"One Tunnelblick VPN Configuration was uninstalled successfully.", @"Window text");
        } else {
            msg = [NSString stringWithFormat: NSLocalizedString(@"%d Tunnelblick VPN Configurations were uninstalled successfully.", @"Window text"), nUninstalled];
        }
        if (  nOK > 0  ) {
            if (  nOK == 1  ) {
                if (  nUninstalled  == 0  ) {
                    msg = NSLocalizedString(@"One Tunnelblick VPN Configuration was installed successfully.", @"Window text");
                } else {
                    msg = [msg stringByAppendingString:
                           NSLocalizedString(@"\n\nOne Tunnelblick VPN Configuration was installed successfully.", @"Window text")];
                }
            } else {
                if (  nUninstalled  == 0  ) {
                    msg = [NSString stringWithFormat: NSLocalizedString(@"%d Tunnelblick VPN Configurations were installed successfully.", @"Window text"), nOK];
                } else {
                    msg = [msg stringByAppendingString:
                           [NSString stringWithFormat:
                            NSLocalizedString(@"\n\n%d Tunnelblick VPN Configurations were installed successfully.", @"Window text"), nOK]];
                }
            }
        }
        
        if (  ! skipResultMsg  ) {
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick VPN Configuration Installation", @"Window title"),
                              msg);
        }
        if (  notifyDelegate  ) {
            [NSApp replyToOpenOrPrint: NSApplicationDelegateReplySuccess];
        }
    }
}

-(NSArray *) checkOneDotTblkPackage: (NSString *)       filePath
		   overrideReplaceIdentical: (NSString *)       overrideReplaceIdentical
			   overrideSharePackage: (NSString *)       overrideSharePackage
				  overrideUninstall: (NSString *)       overrideUninstall
                          errorMsgs: (NSMutableArray *) errMsgs {
    
    // Checks one .tblk package to make sure it should be installed
    //     Returns an array with [source, dest] paths if it should be installed
    //     Returns an array with [source] if it should be UNinstalled
    //     Returns an empty array if the user cancelled the installation
    //     Returns nil if an error occurred
    // If filePath is a nested .tblk (i.e., a .tblk contained within another .tblk), the destination path will be a subfolder of the private or shared configurations folder
    
    if (   [filePath hasPrefix: [gPrivatePath  stringByAppendingString: @"/"]]
        || [filePath hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]
        || [filePath hasPrefix: [gDeployPath   stringByAppendingString: @"/"]]  ) {
        NSLog(@"Configuration installer: Tunnelblick VPN Configuration is already installed: %@", filePath);
        TBShowAlertWindow(NSLocalizedString(@"Configuration Installation Error", @"Window title"),
                          NSLocalizedString(@"You cannot install a Tunnelblick VPN configuration from an installed copy.\n\nAn administrator can copy the installation and install from the copy.", @"Window text"));
        return nil;
    }
	
    NSString * subfolder = nil;
    NSString * filePathWithoutTblk = [filePath stringByDeletingLastPathComponent];
    NSRange outerTblkRange = [filePathWithoutTblk rangeOfString: @".tblk/"];
    if (  outerTblkRange.length != 0  ) {
        subfolder = [filePathWithoutTblk substringWithRange: NSMakeRange(outerTblkRange.location + outerTblkRange.length, [filePathWithoutTblk length] - outerTblkRange.location - outerTblkRange.length)];
        if (  [subfolder isEqualToString: @"Contents/Resources"]  ) {
            subfolder = nil;
        }
    }
	
    BOOL pkgIsOK = TRUE;     // Assume it is OK to install/uninstall the package
    
    NSString * tryDisplayName;      // Try to use this display name, but deal with conflicts
    tryDisplayName = [[filePath lastPathComponent] stringByDeletingPathExtension];
    
    // Do some preliminary checking to see if this is a well-formed .tblk. Return with path to .tblk to use
    // (which might be a temporary file with a "fixed" version of the .tblk).
    NSString * pathToTblk = [self getPackageToInstall: filePath errorMsgs: errMsgs];
    if (  ! pathToTblk  ) {
        return nil;                     // Error occured
    }
    if (  [pathToTblk length] == 0) {
        return [NSArray array];         // User cancelled
    }
    
    // **************************************************************************************
    // Get the following data from Info.plist (and make sure nothing else is in it except TBPreference*** and TBAlwaysSetPreference***):
    
    NSString * pkgId;
    NSString * pkgVersion;
//  NSString * pkgShortVersionString;
    NSString * pkgPkgVersion;
    NSString * pkgReplaceIdentical;
    NSString * pkgSharePackage;
    BOOL       pkgDoUninstall = FALSE;
    BOOL       pkgUninstallFailOK = FALSE;
    
    NSDictionary * infoDict = [self infoPlistForTblkAtPath: pathToTblk];
    
    if (  infoDict  ) {
        
        pkgId = [self getLowerCaseStringForKey: @"CFBundleIdentifier" inDictionary: infoDict defaultTo: nil];
        
        pkgVersion = [self getLowerCaseStringForKey: @"CFBundleVersion" inDictionary: infoDict defaultTo: nil];
        
        //  pkgShortVersionString = [self getLowerCaseStringForKey: @"CFBundleShortVersionString" inDictionary: infoDict defaultTo: nil];
        
        pkgPkgVersion = [self getLowerCaseStringForKey: @"TBPackageVersion" inDictionary: infoDict defaultTo: nil];
        if (  pkgPkgVersion  ) {
            if (  ! [pkgPkgVersion isEqualToString: @"1"]  ) {
                NSLog(@"Configuration installer: The Info.plist in '%@' contains an invalid 'TBPackageVersion' value of '%@' (only '1' is allowed)", pathToTblk, pkgPkgVersion);
                [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"The Info.plist in '%@' contains an invalid 'TBPackageVersion' value of '%@' (only '1' is allowed).", @"Window text"), [self extractTblkNameFromPath: pathToTblk], pkgPkgVersion]];
                pkgIsOK = FALSE;
            }
        } else {
            NSLog(@"Configuration installer: Missing 'TBPackageVersion' in Info.plist in %@", pathToTblk);
            [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"The Info.plist in '%@' does not contain a 'TBPackageVersion' entry.", @"Window text"), [self extractTblkNameFromPath: pathToTblk]]];
            pkgIsOK = FALSE;
        }
        
        pkgReplaceIdentical = [self getLowerCaseStringForKey: @"TBReplaceIdentical" inDictionary: infoDict defaultTo: @"ask"];
        NSArray * okValues = [NSArray arrayWithObjects: @"no", @"yes", @"force", @"ask", nil];
        if ( ! [okValues containsObject: pkgReplaceIdentical]  ) {
            NSLog(@"Configuration installer: Invalid value '%@' (only 'no', 'yes', 'force', or 'ask' are allowed) for 'TBReplaceIdentical' in Info.plist in %@", pkgReplaceIdentical, pathToTblk);
            [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"The Info.plist in '%@' has an invalid value of '%@' (only 'no', 'yes', 'force', or 'ask' are allowed) for 'TBReplaceIdentical'.", @"Window text"), [self extractTblkNameFromPath: pathToTblk], pkgReplaceIdentical]];
            pkgIsOK = FALSE;
        }
        
        pkgSharePackage = [self getLowerCaseStringForKey: @"TBSharePackage" inDictionary: infoDict defaultTo: @"ask"];
        okValues = [NSArray arrayWithObjects: @"private", @"shared", @"ask", nil];
        if ( ! [okValues containsObject: pkgSharePackage]  ) {
            NSLog(@"Configuration installer: Invalid value '%@' (only 'shared', 'private', or 'ask' are allowed) for 'TBSharePackage' in Info.plist in %@", pkgSharePackage, pathToTblk);
            [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"The Info.plist in '%@' has an invalid value of '%@' (only 'shared', 'private', or 'ask' are allowed) for 'TBSharePackage'.", @"Window text"), [self extractTblkNameFromPath: pathToTblk], pkgSharePackage]];
            pkgIsOK = FALSE;
        }
        
        id obj = [infoDict objectForKey: @"TBUninstall"];
        if (  [obj respondsToSelector:@selector(isEqualToString:)]  ) {
            pkgDoUninstall = TRUE;
            if (  [obj isEqualToString: @"ignoreError"]  ) {
                pkgUninstallFailOK = TRUE;
            }
        }
        
        NSString * key;
        NSArray * validKeys = [NSArray arrayWithObjects: @"CFBundleIdentifier", @"CFBundleVersion", @"CFBundleShortVersionString",
                               @"TBPackageVersion", @"TBReplaceIdentical", @"TBSharePackage", @"TBUninstall", nil];
        NSEnumerator * e = [infoDict keyEnumerator];
        while (  (key = [e nextObject])  ) {
            if (  ! [validKeys containsObject: key]  ) {
                if (   [key hasPrefix: @"TBPreference"]
                    || [key hasPrefix: @"TBAlwaysSetPreference"]  ) {
                    NSString * keySuffix = (  [key hasPrefix: @"TBPreference"]
                                            ? [key substringFromIndex: [@"TBPreference"          length]]
                                            : [key substringFromIndex: [@"TBAlwaysSetPreference" length]]);
                    if (  ! [gConfigurationPreferences containsObject: keySuffix]  ) {
                        NSLog(@"Configuration installer: Unknown preference '%@' in TBPreference or TBAlwaysSetPreference key in Info.plist in %@", keySuffix, pathToTblk);
                        [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"The Info.plist in '%@' has a TBPreference or TBAlwaysSetPreference key which refers to an unknown preference '%@'.", @"Window text"), [self extractTblkNameFromPath: pathToTblk], keySuffix]];
                        pkgIsOK = FALSE;
                    }
                } else {
                    NSLog(@"Configuration installer: Unknown key '%@' in Info.plist in %@", key, pathToTblk);
                    [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"The Info.plist in '%@' has an unknown key '%@'.", @"Window text"), [self extractTblkNameFromPath: pathToTblk], key]];
                    pkgIsOK = FALSE;
                }
            }
        }
    } else {
        // No Info.plist, so use default values
        pkgId                       = nil;
        pkgVersion                  = nil;
        pkgReplaceIdentical         = @"ask";
        pkgSharePackage             = @"ask";
        pkgDoUninstall              = NO;
//        pkgInstallWhenInstalling    = @"ask";
    }
	
	if (  overrideReplaceIdentical  ) {
		if (   pkgReplaceIdentical  ) {
			NSLog(@"Overriding TBReplaceIdentical in %@", filePath);
		}
		pkgReplaceIdentical = [[overrideReplaceIdentical retain] autorelease];
	}
	
	if (  overrideSharePackage  ) {
		if (   pkgSharePackage  ) {
			NSLog(@"Overriding TBSharePackage in %@", filePath);
		}
		pkgSharePackage = [[overrideSharePackage retain] autorelease];
	}
    
	if (  overrideUninstall  ) {
		if (  ! pkgDoUninstall  ) {
			NSLog(@"Overriding absence of TBUninstall in %@", filePath);
		}
		pkgDoUninstall = TRUE;
		if (  [overrideUninstall isEqualToString: @"ignoreError"]  ) {
			pkgUninstallFailOK = TRUE;
		}
	}
    
    // **************************************************************************************
    // Make sure the configuration file is not the sample file
    NSString * pathToConfigFile = [pathToTblk stringByAppendingPathComponent: @"Contents/Resources/config.ovpn"];
    if (   ( ! pkgDoUninstall)
        && [self isSampleConfigurationAtPath: pathToConfigFile errorMsgs: errMsgs]  ) {
        pkgIsOK = FALSE;            // have already informed the user of the problem
    }
    
    // **************************************************************************************
    // Make sure the configuration file is not too large
    if (  ! [self fileSizeOKAtPath: pathToConfigFile inTblkNamed: tryDisplayName errMsgs: errMsgs]  ) {
        pkgIsOK = FALSE;
    }
    // **************************************************************************************
    // Make sure the .tblk contains all key/cert/etc. files that are in the configuration file

	if (   pathToConfigFile
        && ( ! pkgDoUninstall)
		&& ( ! [self fileReferencesInConfigAreOk: pathToConfigFile errorMsgs: errMsgs] )  ) {
        pkgIsOK = FALSE;            // have already informed the user of the problem
    }
    
    if ( ! pkgIsOK  ) {
        return nil;
    }
    
    // **************************************************************************************
    // See if there is a package with the same CFBundleIdentifier and deal with that
    NSString * replacementPath = nil;   // Complete path of package to be uninstalled or that this one is replacing, or nil if not replacing
	
    if (  pkgId  ) {
        NSString * key;
        NSEnumerator * e = [[[NSApp delegate] myConfigDictionary] keyEnumerator];
        while (  (key = [e nextObject])  ) {
            NSString * path = [[[NSApp delegate] myConfigDictionary] objectForKey: key];
            NSString * last = lastPartOfPath(path);
            NSString * oldDisplayFirstPart = firstPathComponent(last);
            if (  [[oldDisplayFirstPart pathExtension] isEqualToString: @"tblk"]  ) {
                NSDictionary * oldInfo = [self infoPlistForTblkAtPath: path];
                NSString * oldVersion = [oldInfo objectForKey: @"CFBundleVersion"];
                NSString * oldIdentifier = [self getLowerCaseStringForKey: @"CFBundleIdentifier" inDictionary: oldInfo defaultTo: nil];
                if (  [oldIdentifier isEqualToString: pkgId]) {
                    if (  [pkgReplaceIdentical isEqualToString: @"no"]  ) {
                        NSLog(@"Configuration installer: Tunnelblick VPN Configuration %@ has NOT been %@installed: TBReplaceOption=NO.",
                              tryDisplayName, (pkgDoUninstall ? @"un" : @""));
                        if (  pkgUninstallFailOK  ) {
                            return [NSArray array];
                        } else {
                            [errMsgs addObject: [NSString stringWithFormat:
                                                 (  pkgDoUninstall
                                                  ? NSLocalizedString(@"Tunnelblick VPN Configuration '%@' has NOT been uninstalled because TBReplaceOption=NO.", @"Window text")
                                                  : NSLocalizedString(@"Tunnelblick VPN Configuration '%@' has NOT been installed because TBReplaceOption=NO.", @"Window text")),
                                                 tryDisplayName]];
                            return nil;
                        }
                    } else if (  [pkgReplaceIdentical isEqualToString: @"force"]  ) {
                        // Fall through to install
                    } else if (  [pkgReplaceIdentical isEqualToString: @"yes"]  ) {
                        if (  [oldVersion compare: pkgVersion options: NSNumericSearch] == NSOrderedDescending  ) {
                            NSLog(@"Configuration installer: Tunnelblick VPN Configuration %@ has NOT been %@installed: it has a lower version number.",
                                  tryDisplayName, (pkgDoUninstall ? @"un" : @""));
                            if (  pkgUninstallFailOK  ) {
                                return [NSArray array];
                            } else {
                                [errMsgs addObject: [NSString stringWithFormat:
                                                     (  pkgDoUninstall
                                                      ? NSLocalizedString(@"Tunnelblick VPN Configuration '%@' has NOT been uninstalled because it has a lower version number.", @"Window text")
                                                      : NSLocalizedString(@"Tunnelblick VPN Configuration '%@' has NOT been installed because it has a lower version number.", @"Window text")),
                                                     tryDisplayName]];
                                return nil;
                            }
                        } else {
                            // Fall through to (un)install
                        }
                    } else if (  [pkgReplaceIdentical isEqualToString: @"ask"]  ) {
                        NSString * msg;
                        replacementPath = [[[NSApp delegate] myConfigDictionary] objectForKey: key];
                        NSString * sharedPrivateDeployed;
                        if (  [replacementPath hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]  ) {
                            sharedPrivateDeployed = NSLocalizedString(@" (Shared)", @"Window title");
                        } else if (  [replacementPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
                            sharedPrivateDeployed = NSLocalizedString(@" (Private)", @"Window title");
                        } else if (  [replacementPath hasPrefix: [gDeployPath stringByAppendingString: @"/"]]  ) {
                            sharedPrivateDeployed = NSLocalizedString(@" (Deployed)", @"Window title");
                        } else {
                            sharedPrivateDeployed = NSLocalizedString(@" (?)", @"Window title");
                        }
                        if (  pkgDoUninstall  ) {
                            msg = [NSString stringWithFormat: NSLocalizedString(@"Do you wish to uninstall '%@'%@ version %@?", @"Window text"),
                                   tryDisplayName,
                                   sharedPrivateDeployed,
                                   oldVersion];
                        } else {
                            if (  [oldVersion compare: pkgVersion options: NSNumericSearch] == NSOrderedSame  ) {
                                msg = [NSString stringWithFormat: NSLocalizedString(@"Do you wish to reinstall '%@'%@ version %@?", @"Window text"),
                                       tryDisplayName,
                                       sharedPrivateDeployed,
                                       pkgVersion];
                            } else {
                                msg = [NSString stringWithFormat: NSLocalizedString(@"Do you wish to replace '%@'%@ version %@ with version %@?", @"Window text"),
                                       tryDisplayName,
                                       sharedPrivateDeployed,
                                       pkgVersion,
                                       oldVersion];
                            }
                        }
                        
                        NSString * header;
                        if (  pkgDoUninstall  ) {
                            header = NSLocalizedString(@"Uninstall Tunnelblick VPN Configuration", @"Window title");
                        } else {
                            header = NSLocalizedString(@"Replace Tunnelblick VPN Configuration", @"Window title");
                        }
						
                        int result = TBRunAlertPanel(header,
                                                     msg,
                                                     NSLocalizedString(@"Replace", @"Button"),  // Default
                                                     NSLocalizedString(@"Cancel", @"Button"),   // Alternate
                                                     nil);
                        if (  result != NSAlertDefaultReturn  ) {   // No action if cancelled or error occurred
                            NSLog(@"Configuration installer: Tunnelblick VPN Configuration %@ (un)installation declined by user.", tryDisplayName);
                            return [NSArray array];
                        }
                    }
                    
                    tryDisplayName = [last stringByDeletingPathExtension];
                    replacementPath = [[[NSApp delegate] myConfigDictionary] objectForKey: key];
                    if (  [replacementPath hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]  ) {
                        pkgSharePackage = @"shared";
                    } else {
                        pkgSharePackage = @"private";
                    }
                    break;
                }
            }
        }
    }
    
    // **************************************************************************************
    // Check for name conflicts if not replacing or uninstalling a package
    if (   (! replacementPath )
        && (! pkgDoUninstall )  ) {
        NSString * curPath;
        while (   (curPath = [[[NSApp delegate] myConfigDictionary] objectForKey: tryDisplayName])
			   || ([tryDisplayName length] == 0)
			   ) {
			if (   [pkgReplaceIdentical isEqualToString: @"force"]
                || [pkgReplaceIdentical isEqualToString: @"yes"]
                ) {
				replacementPath = curPath;
				if (  [replacementPath hasPrefix: [L_AS_T_SHARED stringByAppendingPathComponent: @"/"]]  ) {
					pkgSharePackage = @"shared";
				} else {
					pkgSharePackage = @"private";
				}
                break;
 			}
            NSString * msg;
            if (  [tryDisplayName length] == 0  ) {
                msg = NSLocalizedString(@"The VPN name cannot be empty.\n\nPlease enter a new name.", @"Window text");
            } else {
                msg = [NSString stringWithFormat: NSLocalizedString(@"The VPN name '%@' is already in use.\n\nPlease enter a new name.", @"Window text"), tryDisplayName];
            }
            
            NSMutableDictionary* panelDict = [[NSMutableDictionary alloc] initWithCapacity:6];
            [panelDict setObject:NSLocalizedString(@"Name In Use", @"Window title")   forKey:(NSString *)kCFUserNotificationAlertHeaderKey];
            [panelDict setObject:msg                                                forKey:(NSString *)kCFUserNotificationAlertMessageKey];
            [panelDict setObject:@""                                                forKey:(NSString *)kCFUserNotificationTextFieldTitlesKey];
            [panelDict setObject:NSLocalizedString(@"OK", @"Button")                forKey:(NSString *)kCFUserNotificationDefaultButtonTitleKey];
            [panelDict setObject:NSLocalizedString(@"Cancel", @"Button")            forKey:(NSString *)kCFUserNotificationAlternateButtonTitleKey];
            
            // If neither old nor new .tblks have a CFBundleIdentifier, allow replacement
            // (The situation when they both have a CFBundleIdentifer was processed above)
			NSString * oldCFBundleIdentifier = [[self infoPlistForTblkAtPath: curPath] objectForKey: @"CFBundleIdentifier"];
            if (   ( ! pkgId  )
                && ( ! oldCFBundleIdentifier )
                && ( ! [pkgReplaceIdentical isEqualToString: @"no"])  ) {
                [panelDict setObject:NSLocalizedString(@"Replace Existing Configuration", @"Button") forKey:(NSString *)kCFUserNotificationOtherButtonTitleKey];
            }
            
            [panelDict setObject:[NSURL fileURLWithPath:[[NSBundle mainBundle]
                                                         pathForResource:@"tunnelblick"
                                                         ofType: @"icns"]]               forKey:(NSString *)kCFUserNotificationIconURLKey];
            SInt32 error;
            CFUserNotificationRef notification;
            CFOptionFlags response;
            
            // Get a name from the user
            notification = CFUserNotificationCreate(NULL, 30.0, 0, &error, (CFDictionaryRef)panelDict);
            [panelDict release];
            
            if((error) || (CFUserNotificationReceiveResponse(notification, 0.0, &response))) {
                CFRelease(notification);    // Couldn't receive a response
                NSLog(@"Configuration installer: The Tunnelblick VPN Configuration has NOT been installed.\n\nAn unknown error occured.");
                [errMsgs addObject: NSLocalizedString(@"The Tunnelblick VPN Configuration has NOT been installed.\n\nAn unknown error occured.", @"Window text")];
                return nil;
            }
            
            if((response & 0x3) == kCFUserNotificationOtherResponse) {
                CFRelease(notification);    // User clicked "Replace Existing Configuration"
                replacementPath = curPath;
				if (  [replacementPath hasPrefix: [L_AS_T_SHARED stringByAppendingPathComponent: @"/"]]  ) {
					pkgSharePackage = @"shared";
				} else {
					pkgSharePackage = @"private";
				}
                break;
            }
            
            if((response & 0x3) != kCFUserNotificationDefaultResponse) {
                CFRelease(notification);    // User clicked "Cancel"
                NSLog(@"Configuration installer: Installation of Tunnelblick VPN Package %@ has been cancelled.", tryDisplayName);
                return [NSArray array];
            }
            
            // Get the new name from the textfield
            tryDisplayName = [(NSString*)CFUserNotificationGetResponseValue(notification, kCFUserNotificationTextFieldValuesKey, 0)
                              stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            CFRelease(notification);
            if (  [[tryDisplayName pathExtension] isEqualToString: @"tblk"]  ) {
                tryDisplayName = [tryDisplayName stringByDeletingPathExtension];
            }
        }
    }
    
    if (   pkgIsOK ) {
        if (  pkgDoUninstall  ) {
            if (  ! replacementPath  ) {
                
                NSString * pathSuffix = [(subfolder
										  ? [subfolder stringByAppendingPathComponent: tryDisplayName]
										  : tryDisplayName
										  )
										 stringByAppendingPathExtension: @"tblk"];
				NSString * tblkInPrivate = [gPrivatePath  stringByAppendingPathComponent: pathSuffix];
				NSString * tblkInShared  = [L_AS_T_SHARED stringByAppendingPathComponent: pathSuffix];
				if (  [gFileMgr fileExistsAtPath: tblkInPrivate]  ) {
					replacementPath = tblkInPrivate;
				} else if (  [gFileMgr fileExistsAtPath: tblkInShared]  ) {
					replacementPath = tblkInShared;
				} else {
                    NSLog(@"Configuration installer: Cannot find configuration %@ to be uninstalled.", pathSuffix);
                    if (  pkgUninstallFailOK  ) {
                        return [NSArray array];
                    } else {
                        [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"The '%@' configuration cannot be found.", @"Window text"), tryDisplayName]];
                        return nil;
                    }
                }
            }
            
            return [NSArray arrayWithObject: replacementPath];
        }
        
        // **************************************************************************************
        // Ask if it should be shared or private
        if ( ! replacementPath  ) {
            if (  [pkgSharePackage isEqualToString: @"ask"]  ) {
                BOOL isDeployed = [gFileMgr fileExistsAtPath: gDeployPath];
                BOOL installToPrivateOK = (   (! isDeployed)
                                           || (   [gTbDefaults boolForKey: @"usePrivateConfigurationsWithDeployedOnes"]
                                               && ( ! [gTbDefaults canChangeValueForKey: @"usePrivateConfigurationsWithDeployedOnes"])
                                               )  );
                BOOL installToSharedOK = (   (! isDeployed)
                                          || (   [gTbDefaults boolForKey: @"useSharedConfigurationsWithDeployedOnes"]
                                              && ( ! [gTbDefaults canChangeValueForKey: @"useSharedConfigurationsWithDeployedOnes"])
                                              )  );
                
                int result;
                if (  installToPrivateOK  ) {
                    if (  installToSharedOK  ) {
                        result = TBRunAlertPanel(NSLocalizedString(@"Install Configuration For All Users?", @"Window title"),
                                                 [NSString stringWithFormat: NSLocalizedString(@"Do you wish to install the '%@' configuration so that all users can use it, or so that only you can use it?\n\n", @"Window text"), tryDisplayName],
                                                 NSLocalizedString(@"Only Me", @"Button"),      // Default button
                                                 NSLocalizedString(@"All Users", @"Button"),    // Alternate button
                                                 NSLocalizedString(@"Cancel", @"Button"));      // Other button);
                    } else {
                        NSLog(@"Configuration installer: Forcing install of %@ as private because Deployed version of Tunnelblick and 'useSharedConfigurationsWithDeployedOnes' preference is not forced", tryDisplayName);
                        result = NSAlertDefaultReturn;
                    }
                } else {
                    if (  installToSharedOK  ) {
                        NSLog(@"Configuration installer: Forcing install of %@ as shared because Deployed version of Tunnelblick and 'usePrivateConfigurationsWithDeployedOnes' preference is not forced", tryDisplayName);
                        result = NSAlertAlternateReturn;
                    } else {
                        NSLog(@"Configuration installer: %@ cannot be installed as shared or private because this is a Deployed version of Tunnelblick.", tryDisplayName);
                        [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick VPN Configuration '%@' cannot be installed as shared or private because this is a Deployed version of Tunnelblick.", @"Window text"), tryDisplayName]];
                        return nil;
                    }
                }
                if (  result == NSAlertDefaultReturn  ) {
                    pkgSharePackage = @"private";
                } else if (  result == NSAlertAlternateReturn  ) {
                    pkgSharePackage = @"shared";
                } else {   // No action if cancelled or error occurred
                    NSLog(@"Configuration installer: Installation of Tunnelblick VPN Package %@ has been cancelled.", tryDisplayName);
                    return [NSArray array];
                }
            }
        }
        
        // **************************************************************************************
        // Indicate the package is to be installed
        NSString * tblkName = [tryDisplayName stringByAppendingPathExtension: @"tblk"];
        NSString * pathPrefix;
        if (  [pkgSharePackage isEqualToString: @"private"]  ) {
            pathPrefix = gPrivatePath;
        } else {
            pathPrefix = L_AS_T_SHARED;
        }
        if (  subfolder  ) {
            pathPrefix = [pathPrefix stringByAppendingPathComponent: subfolder];
        }
        return [NSArray arrayWithObjects: pathToTblk, [pathPrefix stringByAppendingPathComponent: tblkName], nil];
    }
    
    return nil;
}

-(NSString *) getLowerCaseStringForKey: (NSString *) key
                          inDictionary: (NSDictionary *) dict
                             defaultTo: (id) replacement {
    
    id retVal;
    retVal = [[dict objectForKey: key] lowercaseString];
    if (  retVal  ) {
        if (  ! [[retVal class] isSubclassOfClass: [NSString class]]  ) {
            NSLog(@"The value for Info.plist key '%@' is not a string. The entry will be ignored.", key);
            return nil;
        }
    } else {
        retVal = replacement;
    }
	
    return retVal;
}

-(NSString *) getPackageToInstall: (NSString *)       thePath
                        errorMsgs: (NSMutableArray *) errMsgs {
    
    // Does simple checks on a .tblk package.
    // If it can be "fixed", returns the path to a temporary copy with the problems fixed.
    // Otherwise, returns nil to indicate an error;
    
    NSString * tblkName = [self extractTblkNameFromPath: thePath];
    
    NSArray * keyAndCrtExtensions = KEY_AND_CRT_EXTENSIONS;
	
    // *******************************************************************************
    // Look through the package and create a list of files in it that should be copied
    // The list consists of paths relative to 'thePath'
    
    NSMutableArray * pkgList = [[NSMutableArray alloc] initWithCapacity: 10];   // NOT autorelease, need through user interactions!!!
    
    // Keep track of the sorts of files that will be copied
    
    unsigned int nConfConfigs = 0;   // # of ".conf" configuration files we've seen
    unsigned int nOvpnConfigs = 0;   // # of ".ovpn" configuration files we've seen
    unsigned int nInfos       = 0;   // # of Info.plist files we've seen
    BOOL isDir;
    
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: thePath];
    NSString * thisItem;
    while (  (thisItem = [dirEnum nextObject])  ) {
        
        NSString * itemPath = [thePath stringByAppendingPathComponent: thisItem];
        
        if (  ! itemIsVisible(itemPath)  ) {
            continue;
        }
        
        NSString * ext = [itemPath pathExtension];
        
        if (   [gFileMgr fileExistsAtPath: itemPath isDirectory: &isDir]
            && ( ! isDir )  ) {
            if (  [ext isEqualToString: @"ovpn"]  ) {
                nOvpnConfigs++;
            } else if (  [ext isEqualToString: @"conf"]  ) {
                nConfConfigs++;
            } else if (  [[itemPath lastPathComponent] isEqualToString: @"Info.plist"]  ) {
                nInfos++;
                if (  nInfos > 1  ) {
                    continue;   // Don't add additional Info.plists to pkgList
                }
            } else if (  [ext isEqualToString: @"sh"]  ) {
                ;
            } else if (  ! [keyAndCrtExtensions containsObject: ext]  ) {
                
                NSMutableString * allowedExtensionsString = [[[NSMutableString alloc] initWithCapacity: 200] autorelease];
                [allowedExtensionsString appendString: @"ovpn, conf, tblk, sh, "];
                unsigned j;
                for (  j=0; j<[keyAndCrtExtensions count]-1; j++) {
                    [allowedExtensionsString appendFormat: @"%@, ", [keyAndCrtExtensions objectAtIndex: j]];
                }
                [allowedExtensionsString appendFormat: @"and %@", [keyAndCrtExtensions lastObject]];
                
                if (  [ext length] == 0  ) {
                    NSLog(@"Configuration installer: File '%@' does not have an extension. Each file in a Tunnelblick VPN Configuration must have an extension. Tunnelblick uses the extension to determine how to secure the file properly.", itemPath);
                    [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick VPN Configuration '%@' contains file '%@', which does not have an extension. Each file in a Tunnelblick VPN Configuration must have an extension. Tunnelblick uses extensions to determine how to secure files properly.\n\nThe extensions that are allowed are: %@.", @"Window text"),
                                         tblkName, [self extractTblkNameFromPath: thisItem], allowedExtensionsString]];
                } else {
                    NSLog(@"Configuration installer: File '%@' has an extension that may not appear in a Tunnelblick VPN Configuration. Tunnelblick uses the extension to determine how to secure the file properly.", itemPath);
                    [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick VPN Configuration '%@' contains file '%@', which has an extension that may not appear in a Tunnelblick VPN Configuration. Tunnelblick uses extensions to determine how to secure files properly.\n\nThe extensions that are allowed are: %@.", @"Window text"),
                                         tblkName, [self extractTblkNameFromPath: thisItem], allowedExtensionsString]];
                }
                
                // Because we copy all files "flat" into the Contents/Resources folder, not into subfolders, we don't allow files with the same names (even if they are in different folders)
                // So we check for duplicate names before inserting items into pkgList
                BOOL skipThisItem = FALSE;
                NSString * subfolderItem;
                NSEnumerator * e = [pkgList objectEnumerator];
                while (  (subfolderItem = [e nextObject])  ) {
                    NSString * fileName = [subfolderItem lastPathComponent];
                    if (  [thisItem isEqualToString: fileName]  ) {
                        NSLog(@"Configuration installer: Tunnelblick VPN Configuration '%@', contains multiple files named '%@'. All file names must be unique, even if they are in different subfolders.", thePath, fileName);
                        [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick VPN Configuration '%@', contains multiple files named '%@'. All file names must be unique, even if they are in different subfolders.", @"Window text"), tblkName, fileName]];
                        skipThisItem = TRUE;
						break;
                    }
                }
				
				if (  skipThisItem  ) {
					continue;
				}
            }

			[pkgList addObject: thisItem];
			
        } else if (  [[itemPath pathExtension] isEqualToString: @"tblk"]  ) {
            NSLog(@"Configuration installer: .tblks are nested too deeply in %@.", thePath);
            [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick VPN Configuration '%@', which is contained within a Tunnelblick VPN Configuration, contains a Tunnelblick VPN Configuration, which is not allowed. Only one level of nesting is allowed.", @"Window text"), tblkName]];
            [dirEnum skipDescendents];
        } else {
            ;  // Folder -- ignore it (but we will process everything inside it)
        }
    }
    
    // *******************************************************************************
    // Do some simple checks
    
    // If empty package, make a sample config
    if (  [pkgList count] == 0  ) {
		[errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick VPN Configuration '%@' is empty.", @"Window text"),
							 tblkName]];
		[pkgList release];
		return @"";
	}
	
    BOOL copyTheConfConfig = FALSE;
    
    if (  nOvpnConfigs != 1  ) {
        
        copyTheConfConfig = TRUE;
        
        if (  nOvpnConfigs > 1  ) {
            NSLog(@"Configuration installer: Tunnelblick VPN Configuration '%@' has more than one OpenVPN configuration file with an 'ovpn' extension. A Tunnelblick VPN Configuration should have exactly one OpenVPN configuration file with an 'ovpn' extension .If it does not, it must have exactly one with a 'conf' extension.", thePath);
            [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick VPN Configuration '%@' has more than one OpenVPN configuration file with an 'ovpn' extension.\n\nA Tunnelblick VPN Configuration should have exactly one OpenVPN configuration file with an 'ovpn' extension. If it does not, it must have exactly one with a 'conf' extension.", @"Window text"), tblkName]];
            [pkgList release];
            return nil;
        }
        if (  nConfConfigs != 1  ) {
            if (  nConfConfigs == 0  ) {
                NSLog(@"Configuration installer: Tunnelblick VPN Configuration '%@' does not have any OpenVPN configuration files with an 'ovpn' or 'conf' extension. A Tunnelblick VPN Configuration should have exactly one OpenVPN configuration file with an 'ovpn' extension .If it does not, it must have exactly one with a 'conf' extension.", thePath);
                [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick VPN Configuration '%@' does not have any OpenVPN configuration files with an 'ovpn' or 'conf' extension.\n\nA Tunnelblick VPN Configuration should have exactly one OpenVPN configuration file with an 'ovpn' extension. If it does not, it must have exactly one with a 'conf' extension.", @"Window text"), tblkName]];
                [pkgList release];
                return nil;
            } else {
                NSLog(@"Configuration installer: Tunnelblick VPN Configuration '%@' has %d OpenVPN configuration files with a 'conf' extension. A Tunnelblick VPN Configuration should have exactly one OpenVPN configuration file with an 'ovpn' extension .If it does not, it must have exactly one with a 'conf' extension.", thePath, nConfConfigs);
                [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick VPN Configuration '%@' does not have any OpenVPN configuration files with a 'ovpn' extension, and has more than one with a 'conf' extension.\n\nA Tunnelblick VPN Configuration should have exactly one OpenVPN configuration file with an 'ovpn' extension .If it does not, it must have exactly one with a 'conf' extension.", @"Window text"), tblkName]];
                [pkgList release];
                return nil;
            }
        }
    }
    
    if (  nInfos > 1  ) {
        NSLog(@"Configuration installer: A Tunnelblick VPN Configuration may have at most one Info.plist, %d Info.plist files were found in %@", nInfos, thePath);
        [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"%d Info.plist files were found in '%@'. A Tunnelblick VPN Configuration may have at most one Info.plist.", @"Window text"), nInfos, tblkName]];
        [pkgList release];
        return nil;
    }

    // *******************************************************************************
	// Create an empty .tblk and copy the files to its Contents/Resources folder
	// Except only one OpenVPN configuration file is copied (and it is copied as "config.ovpn")
    // The Info.plist is copied to Contents.
    // All other files are copied "flat" into the Contents/Resources folder (that is, not into subfolders)

    NSString * emptyTblk = [self makeEmptyTblk: thePath];
    if (  ! emptyTblk  ) {
        [pkgList release];
        return nil;
    }
    
    NSString * emptyResources = [emptyTblk stringByAppendingPathComponent: @"Contents/Resources"];
    unsigned i;
    for (i=0; i < [pkgList count]; i++) {
        NSString * oldPath = [thePath stringByAppendingPathComponent: [pkgList objectAtIndex: i]];
        
        NSString * newPath = nil;
        NSString * ext = [oldPath pathExtension];
        
        if (  [ext isEqualToString: @"ovpn"]  ) {
            newPath = [emptyResources stringByAppendingPathComponent: @"config.ovpn"];
        } else if (   [ext isEqualToString: @"conf"]  ) {
            if ( copyTheConfConfig  ) {
                newPath = [emptyResources stringByAppendingPathComponent: @"config.ovpn"];
            } else {
                continue;   // Skip  copying .conf because we're using a .ovpn
            }
        } else if (  [[oldPath lastPathComponent] isEqualToString: @"Info.plist"]  ) {
            newPath = [[emptyResources stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"Info.plist"];  // Goes in Contents, not Resources
        } else {
            newPath = [emptyResources stringByAppendingPathComponent: [oldPath lastPathComponent]];
        }
        
        BOOL doCopy = TRUE; // Assume we don't remove/replace CR characeters, so we do need to copy the file
        
        // Filter CR characters out of any script files, OpenVPN configuration files, and other non-binary files
        NSString * theExtension = [oldPath pathExtension];
        NSArray * otherExtensions = [NSArray arrayWithObjects: @"sh", @"ovpn", @"conf", nil];
        NSArray * nonBinaryExtensions = NONBINARY_CONTENTS_EXTENSIONS;
        if (   [nonBinaryExtensions containsObject: theExtension]
            || [otherExtensions    containsObject: theExtension]  ) {
            NSData * data = [gFileMgr contentsAtPath: oldPath];
            if (  data  ) {
                NSString * scriptContents = [[[NSString alloc] initWithData: data encoding: NSASCIIStringEncoding] autorelease];
                if (  [scriptContents rangeOfString: @"\r"].length != 0  ) {
                    doCopy = FALSE;
                    NSLog(@"Configuration installer: CR characters are being removed or replaced with LF characters in the installed copy of %@", oldPath);
                    NSMutableString * ms = [[scriptContents mutableCopy] autorelease];
					[ms replaceOccurrencesOfString: @"\r\n"
										withString: @"\n"
										   options: 0
											 range: NSMakeRange(0, [ms length])];
					[ms replaceOccurrencesOfString: @"\r"
										withString: @"\n"
										   options: 0
											 range: NSMakeRange(0, [ms length])];
					data = [ms dataUsingEncoding: NSUTF8StringEncoding];
					if (  ! data  ) {
                        NSLog(@"Configuration installer: Invalid encoding in %@", newPath);
                        [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"The file contains characters that are not UTF-8 encoded: %@", @"Window text"), [newPath lastPathComponent]]];
                        [pkgList release];
                        return nil;
					}
                    if (  ! [gFileMgr createFileAtPath: newPath contents: data attributes: nil]  ) {
                        NSLog(@"Configuration installer: Unable to create file at %@", newPath);
                        [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"Program error, please report this as a bug: Unable to create file at '%@'", @"Window text"), newPath]];
                        [pkgList release];
                        return nil;
                    }
                }
            }
        }
        
        if (  doCopy  ) {
            if (  ! [gFileMgr tbCopyPath: oldPath toPath: newPath handler: nil]  ) {
                NSLog(@"Configuration installer: Unable to copy %@ to %@", oldPath, newPath);
                [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"Program error, please report this as a bug: Unable to copy '%@' to '%@'", @"Window text"), oldPath, newPath]];
                [pkgList release];
                return nil;
            }
        }
    }
    
    // *******************************************************************************
    // Strip any path information from arguments of relevant options in the OpenVPN configuration file
    // (because we took all the files the options reference out of folders and put them into the .tblk)

    NSString * newConfigPath = [emptyResources stringByAppendingPathComponent: @"config.ovpn"];
    
    NSString * tempFilePath = [newTemporaryDirectoryPath() stringByAppendingPathComponent: @"log.txt"];
    FILE * logFile = fopen([tempFilePath fileSystemRepresentation], "w");
    if (  logFile == nil  ) {
        NSLog(@"Configuration installer: unable to create temporary log file '%@'", tempFilePath);
    }
    
    ConfigurationConverter * converter = [[ConfigurationConverter alloc] init];     // NOT autorelease!!!
    
    if (  ! [converter convertConfigPath: newConfigPath
                              outputPath: nil
                                 logFile: logFile
                    includePathNameInLog: NO]  ) {
        fclose(logFile);
        NSData * data = [gFileMgr contentsAtPath: tempFilePath];
        NSString * errText = (  data
                              ? [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease]
                              : @"");
        NSLog(@"Configuration installer: Failed to parse configuration path '%@':\n%@", newConfigPath, errText);
        [errMsgs addObject: [NSString stringWithFormat: NSLocalizedString(@"The OpenVPN configuration file in '%@' could not be processed:\n\n%@", @"Window text"),
                             [self extractTblkNameFromPath: newConfigPath], errText]];
		emptyTblk = nil;	// return error
    } else {
        fclose(logFile);
    }
    
    NSString * tempFolderPath = [tempFilePath stringByDeletingLastPathComponent];
    if (  ! [gFileMgr tbRemoveFileAtPath: tempFolderPath handler: nil]  ) {
        NSLog(@"Configuration installer: unable to delete temporary folder '%@'", tempFolderPath);
    }
    
    [converter release];
    
    [pkgList release];
    return emptyTblk;
}

-(NSString *) makeEmptyTblk: (NSString *) thePath {
    
    // Creates an "empty" .tblk with name taken from input argument, and with Contents/Resources created,
    // in a newly-created temporary folder
    // Returns nil on error, or with the path to the .tblk
    
    NSString * tempFolder = newTemporaryDirectoryPath();
    NSString * tempTblk = [tempFolder stringByAppendingPathComponent: [thePath lastPathComponent]];
    
    NSString * tempResources = [tempTblk stringByAppendingPathComponent: @"Contents/Resources"];
    
    int result = createDir(tempResources, 0755);    // Creates intermediate directory "Contents", too
    
    [tempFolder release];
    
    if (  result == -1  ) {
        return nil;
    }
    
    return tempTblk;
}

-(BOOL) isSampleConfigurationAtPath: (NSString *)       cfgPath
						  errorMsgs: (NSMutableArray *) errMsgs {
    
    NSString * samplePath = [[NSBundle mainBundle] pathForResource: @"openvpn" ofType: @"conf"];
    if (  [[cfgPath pathExtension] isEqualToString: @"tblk"]  ) {
        if (  ! [gFileMgr contentsEqualAtPath: [cfgPath stringByAppendingPathComponent: @"Contents/Resources/config.ovpn"] andPath: samplePath]  ) {
            return FALSE;
        }
    } else {
        if (  ! [gFileMgr contentsEqualAtPath: cfgPath andPath: samplePath]  ) {
            return FALSE;
        }
    }
    
    [errMsgs addObject: NSLocalizedString(@"You have tried to install a configuration file that is a sample"
										  @" configuration file. The configuration file must"
										  @" be modified to connect to a VPN. You may also need other files, such as"
										  @" certificate or key files, to connect to the VPN.\n\n"
										  @"Consult your network administrator or your VPN service provider to obtain"
										  @" configuration and other files or the information you need to modify the"
										  @" sample file.", @"Window text")];
	 return TRUE;
}

-(BOOL) copyConfigPath: (NSString *) sourcePath
                toPath: (NSString *) targetPath
       usingAuthRefPtr: (AuthorizationRef *) authRefPtr
            warnDialog: (BOOL) warn
           moveNotCopy: (BOOL) moveInstead {
    
    // Copies or moves a config file or package and sets ownership and permissions on the target
    // Returns TRUE if succeeded in the copy or move -- EVEN IF THE CONFIG WAS NOT SECURED (an error message was output to the console log).
    // Returns FALSE if failed, having already output an error message to the console log
    
    if (  [sourcePath isEqualToString: targetPath]  ) {
        NSLog(@"You cannot copy or move a configuration to itself. Trying to do that with %@", sourcePath);
        return FALSE;
    }
    
	NSString * errMsg = (  [sourcePath hasSuffix: @".tblk"]
						 ? allFilesAreReasonableIn(sourcePath)
						 : fileIsReasonableSize(sourcePath));
	if (  errMsg  ) {
		NSLog(@"%@", errMsg);
		return FALSE;
	}
    
    unsigned firstArg = (moveInstead
                         ? INSTALLER_MOVE_NOT_COPY
                         : 0);
    NSArray * arguments = [NSArray arrayWithObjects: targetPath, sourcePath, nil];
    
    if (  [[NSApp delegate] runInstaller: firstArg extraArguments: arguments usingAuthRefPtr: authRefPtr message: nil installTblksFirst: nil]  ) {
        return TRUE;
    }
    
	NSString * name = lastPartOfPath(targetPath);
    if (  ! moveInstead  ) {
        NSLog(@"Could not copy configuration file %@ to %@", sourcePath, targetPath);
        if (  warn  ) {
            NSString * title = NSLocalizedString(@"Could Not Copy Configuration", @"Window title");
            NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not copy the '%@' configuration. See the Console Log for details.", @"Window text"), name];
            TBShowAlertWindow(title, msg);
        }
        
        return FALSE;
        
    } else {
        NSLog(@"Could not move configuration file %@ to %@", sourcePath, targetPath);
        if (  warn  ) {
            NSString * title = NSLocalizedString(@"Could Not Move Configuration", @"Window title");
            NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not move the '%@' configuration. See the Console Log for details.", @"Window text"), name];
            TBShowAlertWindow(title, msg);
        }
        
        return FALSE;
    }
}

-(BOOL) deleteConfigPath: (NSString *) targetPath
         usingAuthRefPtr: (AuthorizationRef *) authRefPtr
              warnDialog: (BOOL) warn {
    
    // Deletes a config file or package
    // Returns TRUE if succeeded
    // Returns FALSE if failed, having already output an error message to the console log
    
    unsigned firstArg = INSTALLER_DELETE;
    NSArray * arguments = [NSArray arrayWithObjects: targetPath, nil];
    
    [[NSApp delegate] runInstaller: firstArg extraArguments: arguments usingAuthRefPtr: authRefPtr message: nil installTblksFirst: nil];
    
    if ( [gFileMgr fileExistsAtPath: targetPath]  ) {
        NSString * name = [[targetPath lastPathComponent] stringByDeletingPathExtension];
        NSLog(@"Could not uninstall configuration file %@", targetPath);
        if (  warn  ) {
            NSString * title = NSLocalizedString(@"Could Not Uninstall Configuration", @"Window title");
            NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not uninstall the '%@' configuration. See the Console Log for details.", @"Window text"), name];
            TBShowAlertWindow(title, msg);
        }
        return FALSE;
    }
	
    NSLog(@"Uninstalled configuration file %@", targetPath);
    return TRUE;
}

-(void) haveNoConfigurationsGuide {
    // There are no configurations installed. Guide the user
    
    [self guideState: entryNoConfigurations];
}

-(void) addConfigurationGuide {
    
    // Guide the user through the process of adding a configuration (.tblk or .ovpn/.conf)
    
    [self guideState: entryAddConfiguration];
}

-(void) guideState: (enum state_t) state {
    
    // guideState is sort of a state machine for displaying configuration dialog windows. It has a simple, LIFO history stored in an array to implement a "back" button
    
    enum state_t nextState;
	
    int button;
    
    NSMutableArray * history = [NSMutableArray arrayWithCapacity: 20];  // Contains NSNumbers containing state history
    
    while ( TRUE  ) {
        
        switch (  state  ) {
                
                
            case entryNoConfigurations:
                
                // No configuration files (entry from haveNoConfigurationsGuild)
                button = TBRunAlertPanel(NSLocalizedString(@"Welcome to Tunnelblick", @"Window title"),
                                         NSLocalizedString(@"There are no VPN configurations installed.\n\n"
                                                           "Tunnelblick needs one or more installed configurations to connect to a VPN. "
                                                           "Configurations are installed from files that are usually supplied to you by your network manager "
                                                           "or VPN service provider. The files must be installed to be used.\n\n"
                                                           "Configuration files have extensions of .tblk, .ovpn, or .conf.\n\n"
                                                           "(There may be other files associated with the configuration that have other extensions; ignore them for now.)\n\n"
                                                           "Do you have any configuration files?\n",
                                                           @"Window text"),
                                         NSLocalizedString(@"I have configuration files", @"Button"),       // Default button
                                         NSLocalizedString(@"Quit", @"Button"),                             // Alternate button
                                         NSLocalizedString(@"I DO NOT have configuration files", @"Button") // Other button
                                         );
                
                if (   (button == NSAlertAlternateReturn)   // Quit if quit or error occurred
                    || (button == NSAlertErrorReturn)  ) {
                    [[NSApp delegate] terminateBecause: terminatingBecauseOfQuit];
                }
                
                if (  button == NSAlertDefaultReturn  ) {
                    // User has configuration files and wishes to add them
                    nextState = stateHasConfigurations;
                    break;
                }
                
                // User does not have configuration files
                nextState = stateHasNoConfigurations;
                break;
                
                
            case stateHasNoConfigurations:
                
                // User doesn't have configuration files
                button = TBRunAlertPanel(NSLocalizedString(@"Create and Edit a Sample Configuration?", @"Window title"),
                                         NSLocalizedString(@"Would you like to\n\n"
                                                           "  • Create a sample configuration on the Desktop\n             and\n"
                                                           "  • Open its OpenVPN configuration file in TextEdit so you can modify "
                                                           "it to connect to your VPN?\n\n", @"Window text"),
                                         NSLocalizedString(@"Create sample configuration and edit it", @"Button"),    // Default button
                                         NSLocalizedString(@"Back", @"Button"),                         // Alternate button
                                         nil                                                            // Other button
                                         );
                
                if (  button != NSAlertDefaultReturn  ) {   // Back if user selected Back or error occurred
                    // User selected Back
                    nextState = stateGoBack;
                    break;
                }
                
                // User wants to create sample configuration on Desktop and edit the OpenVPN configuration file in TextEdit
                nextState = stateMakeSampleConfiguration;
                break;
                
                
            case stateMakeSampleConfiguration:
                
                // User wants to create a sample configuration on the Desktop and edit the OpenVPN configuration file in TextEdit
                ; // Weird, but without this semicolon (i.e., empty statement) the compiler generates a syntax error for the next line!
                NSString * sampleConfigFolderName = NSLocalizedString(@"Sample Tunnelblick VPN Configuration", @"Folder name");
                NSString * targetPath = [[NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent: sampleConfigFolderName];
                if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
                    button = TBRunAlertPanel(NSLocalizedString(@"Replace Existing File?", @"Window title"),
                                             [NSString stringWithFormat: NSLocalizedString(@"'%@' already exists on the Desktop.\n\n"
                                                                                           "Would you like to replace it?",
                                                                                           @"Window text"), sampleConfigFolderName],
                                             NSLocalizedString(@"Replace", @"Button"),  // Default button
                                             NSLocalizedString(@"Back", @"Button"),     // Alternate button
                                             nil);                                      // Other button
                    
                    if (  button != NSAlertDefaultReturn  ) {   // Back if user selected Back or error occurred
                        nextState = stateGoBack;
                        break;
                    }
                    
                    [gFileMgr tbRemoveFileAtPath:targetPath handler: nil];
                }
                
                if (  createDir(targetPath, 0755) == -1  ) {
                    NSLog(@"Installation failed. Not able to create %@", targetPath);
                    TBShowAlertWindow(NSLocalizedString(@"Installation failed", @"Window title"),
                                      NSLocalizedString(@"Tunnelblick could not create the empty configuration folder", @"Window text"));
                    return;
                }
                
                NSString * targetConfigPath = [targetPath stringByAppendingPathComponent: @"config.ovpn"];
                
                NSString * sourcePath = [[NSBundle mainBundle] pathForResource: @"openvpn" ofType: @"conf"];
                if (  ! [gFileMgr tbCopyPath: sourcePath toPath: targetConfigPath handler: nil]  ) {
                    NSLog(@"Installation failed. Not able to copy %@ to %@", sourcePath, targetConfigPath);
                    TBShowAlertWindow(NSLocalizedString(@"Installation failed", @"Window title"),
                                      NSLocalizedString(@"Tunnelblick could not create the sample configuration", @"Window text"));
                    return;
                }
                
                [[NSWorkspace sharedWorkspace] openFile: targetPath];
				
                [[NSWorkspace sharedWorkspace] openFile: targetConfigPath withApplication: @"TextEdit"];
                
                // Display guidance about what to do after editing the sample configuration file
                TBShowAlertWindow(NSLocalizedString(@"Sample Configuration Created", @"Window title"),
								  NSLocalizedString(@"The sample configuration folder has been created on your Desktop, and the OpenVPN configuration file has been opened "
													"in TextEdit so you can modify the file for your VPN setup.\n\n"
													"When you have finished editing the OpenVPN configuration file and saved the changes, please\n\n"
													
													"1. Move or copy any key or certificate files associated with the configuration "
													"into the 'Sample Tunnelblick VPN Configuration' folder on your Desktop.\n\n"
													"(This folder has been opened in a Finder window so you can drag the files to it.)\n\n"
													
													"2. Change the folder's name to a name of your choice. "
													"This will be the name that Tunnelblick uses for the configuration.\n\n"
													
													"3. Add .tblk to the end of the folder's name.\n\n"
													
													"4. Double-click the folder to install the configuration.\n\n"
													
													"The new configuration will be available in Tunnelblick immediately.",
													
													@"Window text"));
                return;
                
                
            case entryAddConfiguration:
                // Entry from addConfigurationGuide
                button = TBRunAlertPanel(NSLocalizedString(@"Add a Configuration", @"Window title"),
                                         NSLocalizedString(@"Configurations are usually installed from files that are supplied to you by your network manager "
                                                           "or VPN service provider.\n\n"
                                                           "Configuration files have extensions of .tblk, .ovpn, or .conf.\n\n"
                                                           "(There may be other files associated with the configuration that have other extensions; ignore them for now.)\n\n"
                                                           "Do you have any configuration files?\n",
                                                           @"Window text"),
                                         NSLocalizedString(@"I have configuration files", @"Button"),       // Default button
                                         NSLocalizedString(@"Cancel", @"Button"),                           // Alternate button
                                         NSLocalizedString(@"I DO NOT have configuration files", @"Button") // Other button
                                         );
                
                if (   (button == NSAlertAlternateReturn)   // No action if cancelled or error occurred
                    || (button == NSAlertErrorReturn)  ) {
                    // User selected Cancel
                    return;
                }
                
                if (  button == NSAlertDefaultReturn  ) {
                    // User has configuration files and wishes to add them
                    nextState = stateHasConfigurations;
                    break;
                }
                
                // User does not have configuration files
                nextState = stateHasNoConfigurations;
                break;
                
                
            case stateHasConfigurations:
                
                // User has configuration files and wishes to add them
                button = TBRunAlertPanel(NSLocalizedString(@"Which Type of Configuration Do You Have?", @"Window title"),
                                         NSLocalizedString(@"There are two types of configuration files:\n\n"
                                                           "  • Tunnelblick VPN Configurations (.tblk extension)\n\n"
                                                           "  • OpenVPN Configurations (.ovpn or .conf extension)\n\n"
                                                           "Which type of configuration file do have?\n\n",
                                                           @"Window text"),
                                         NSLocalizedString(@"Tunnelblick VPN Configuration(s)", @"Button"),    // Default button
                                         NSLocalizedString(@"Back", @"Button"),                             // Alternate button
                                         NSLocalizedString(@"OpenVPN Configuration(s)", @"Button")             // Other button
                                         );
                
                if (   (button == NSAlertAlternateReturn)   // User selected Back or error occurred
                    || (button == NSAlertErrorReturn)  ) {
                    nextState = stateGoBack;
                    break;
                }
                
                if (  button == NSAlertOtherReturn) {
                    // User selected OPEPNVPN VPN CONFIGURATION
                    nextState = stateMakeEmptyConfiguration;
                    break;
                }
                
                // User selected TUNNELBLICK VPN CONFIGURATION
                nextState = stateShowTbInstructions;
                break;
                
                
            case stateShowTbInstructions:
				
                // User selected TUNNELBLICK VPN CONFIGURATION
                button = TBRunAlertPanel(NSLocalizedString(@"Installing a Tunnelblick VPN Configuration", @"Window title"),
                                         NSLocalizedString(@"To install a Tunnelblick VPN Configuration (.tblk extension), double-click it.\n\n"
                                                           "The new configuration will be available in Tunnelblick immediately.", @"Window text"),
                                         NSLocalizedString(@"Done", @"Button"),    // Default button
                                         NSLocalizedString(@"Back", @"Button"),  // Alternate button
                                         nil
                                         );
                
                if (  button == NSAlertAlternateReturn  ) {
                    // User selected Back
                    nextState = stateGoBack;
                    break;
                }
                
                // Treat error as "Done"
                
                return;
                
                
            case stateMakeEmptyConfiguration:
                
                // User wants to create an empty configuration
                ; // Weird, but without this semicolon (i.e., empty statement) the compiler generates a syntax error for the next line!
                NSString * emptyConfigFolderName = NSLocalizedString(@"Empty Tunnelblick VPN Configuration", @"Folder name");
                targetPath = [[NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent: emptyConfigFolderName];
                if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
                    button = TBRunAlertPanel(NSLocalizedString(@"Replace Existing File?", @"Window title"),
                                             [NSString stringWithFormat: NSLocalizedString(@"'%@' already exists on the Desktop.\n\n"
                                                                                           "Would you like to replace it?",
                                                                                           @"Window text"), targetPath],
                                             NSLocalizedString(@"Replace", @"Button"),  // Default button
                                             NSLocalizedString(@"Back", @"Button"),     // Alternate button
                                             nil);                                      // Other button
                    
                    if (   (button == NSAlertAlternateReturn)   // User selected Back or error occurred
                        || (button == NSAlertErrorReturn)  ) {
                        nextState = stateGoBack;
                        break;
                    }
                    
                    [gFileMgr tbRemoveFileAtPath:targetPath handler: nil];
                }
                
                if (    createDir(targetPath, 0755) == -1    ) {
                    NSLog(@"Installation failed. Not able to create %@", targetPath);
                    TBShowAlertWindow(NSLocalizedString(@"Installation failed", @"Window title"),
                                      NSLocalizedString(@"Tunnelblick could not create the empty configuration folder", @"Window text"));
                    return;
                }
                
                [[NSWorkspace sharedWorkspace] openFile: targetPath];
                
                button = TBRunAlertPanel(NSLocalizedString(@"An Empty Tunnelblick VPN Configuration Has Been Created", @"Window title"),
                                         NSLocalizedString(@"To install it as a Tunnelblick VPN Configuration:\n\n"
                                                           "1. Move or copy one OpenVPN configuration file (.ovpn or .conf extension) into the 'Empty Tunnelblick "
                                                           "VPN Configuration' folder which has been created on the Desktop.\n\n"
                                                           "2. Move or copy any key or certificate files associated with the configuration into the folder.\n\n"
                                                           "3. Rename the folder to the name you want Tunnelblick to use for the configuration.\n\n"
                                                           "4. Add an extension of .tblk to the end of the name of the folder.\n\n"
                                                           "5. Double-click the folder to install it.\n\n"
                                                           "The new configuration will be available in Tunnelblick immediately.\n\n"
                                                           "(For your convenience, the folder has been opened in a Finder window.)",
                                                           @"Window text"),
                                         NSLocalizedString(@"Done", @"Button"),    // Default button
                                         NSLocalizedString(@"Back", @"Button"),    // Alternate button
                                         nil
                                         );
                if (  button == NSAlertAlternateReturn  ) {
                    // User selected Back
                    nextState = stateGoBack;
                    break;
                }
                
                // Treat error as "Done"
                
                return;
                
                
            default:
                NSLog(@"guideState: invalid state = %d", state);
                return;
        }
        
        if (  nextState == stateGoBack) {
            // Go back
            if (  [history count] == 0  ) {
                NSLog(@"guideState: Back command but no history");
                return;
            }
            enum state_t backState = (enum state_t)[[history lastObject] intValue];
            [history removeLastObject];
            state = backState;
        } else {
            [history addObject: [NSNumber numberWithInt: (int) state]];
            state = nextState;
        }
    } 
}

-(NSString *) displayNameForPath: (NSString *) thePath {
    return [lastPartOfPath(thePath) stringByDeletingPathExtension];
}

@end
