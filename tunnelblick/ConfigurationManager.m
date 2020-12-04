/*
 * Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2018, 2019, 2020 Jonathan K. Bullard. All rights reserved.
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

#import <asl.h>
#import <sys/param.h>
#import <sys/mount.h>
#import <unistd.h>

#import "defines.h"
#import "helper.h"
#import "sharedRoutines.h"

#import "AuthAgent.h"
#import "ConfigurationConverter.h"
#import "ConfigurationMultiUpdater.h"
#import "ListingWindowController.h"
#import "MenuController.h"
#import "MyPrefsWindowController.h"
#import "NSApplication+LoginItem.h"
#import "NSDate+TB.h"
#import "NSFileManager+TB.h"
#import "NSString+TB.h"
#import "SettingsSheetWindowController.h"
#import "SystemAuth.h"
#import "TBOperationQueue.h"
#import "TBUserDefaults.h"
#import "UIHelper.h"
#import "VPNConnection.h"

extern NSMutableArray       * gConfigDirs;
extern NSArray              * gConfigurationPreferences;
extern NSArray              * gProgramPreferences;
extern NSString             * gPrivatePath;
extern NSString             * gDeployPath;
extern NSFileManager        * gFileMgr;
extern MenuController       * gMC;

extern TBUserDefaults       * gTbDefaults;

extern NSString * lastPartOfPath(NSString * thePath);

enum state_t {                      // These are the "states" of the guideState state machine
    entryNoConfigurations,
    entryAddConfiguration,
    stateGoBack,                    // (This can only be a nextState, never an actual state)
    stateHasNoConfigurations,
    stateMakeSampleConfiguration,
    stateHasConfigurations,
};

@implementation ConfigurationManager

TBSYNTHESIZE_OBJECT(retain, NSString *, applyToAllSharedPrivate, setApplyToAllSharedPrivate)
TBSYNTHESIZE_OBJECT(retain, NSString *, applyToAllUninstall,     setApplyToAllUninstall)
TBSYNTHESIZE_OBJECT(retain, NSString *, applyToAllReplaceSkip,   setApplyToAllReplaceSkip)

TBSYNTHESIZE_OBJECT(retain, NSMutableString *, errorLog,         setErrorLog)

TBSYNTHESIZE_OBJECT(retain, NSString *, tempDirPath,             setTempDirPath)

TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, installSources,    setInstallSources)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, installTargets,    setInstallTargets)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, replaceSources,    setReplaceSources)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, replaceTargets,    setReplaceTargets)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, noAdminSources,    setNoAdminSources)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, noAdminTargets,    setNoAdminTargets)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, updateSources,     setUpdateSources)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, updateTargets,     setUpdateTargets)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, deletions,         setDeletions)

TBSYNTHESIZE_NONOBJECT(BOOL, inhibitCheckbox,        setInhibitCheckbox)
TBSYNTHESIZE_NONOBJECT(BOOL, installToSharedOK,      setInstallToSharedOK)
TBSYNTHESIZE_NONOBJECT(BOOL, installToPrivateOK,     setInstallToPrivateOK)
TBSYNTHESIZE_NONOBJECT(BOOL, multipleConfigurations, setMultipleConfigurations)

+(id)   manager {
    
    return [[[ConfigurationManager alloc] init] autorelease];
}

-(void) dealloc {
    
    [applyToAllSharedPrivate release];
    [applyToAllUninstall     release];
    [applyToAllReplaceSkip   release];
    [tempDirPath             release];
	[errorLog			     release];
    [installSources          release];
    [installTargets          release];
    [replaceSources          release];
    [replaceTargets          release];
    [noAdminSources          release];
    [noAdminTargets          release];
    [updateSources           release];
    [updateTargets           release];
    [deletions               release];
    
    // listingWindow IS NOT RELEASED because it needs to exist after this instance of ConfigurationManager is gone. It releases itself when the window closes.
    
    [super dealloc];
}

+(NSString *) checkForSampleConfigurationAtPath: (NSString *) cfgPath {
    
    // Returns nil or a localized error message
    
    NSString * samplePath = [[NSBundle mainBundle] pathForResource: @"openvpn" ofType: @"conf"];
    if (  [gFileMgr fileExistsAtPath: cfgPath]  ) {
        if (  ! [gFileMgr contentsEqualAtPath: cfgPath andPath: samplePath]  ) {
            return nil;
        }
    } else {
        return [NSString stringWithFormat: NSLocalizedString(@"Cannot find configuration file at %@", @"Window text"), cfgPath];
    }
    
    return [NSString stringWithFormat: NSLocalizedString(@"You have tried to install a configuration file that is a sample"
                                                         @" configuration file. The configuration file must"
                                                         @" be modified to connect to a VPN. You may also need other files, such as"
                                                         @" certificate or key files, to connect to the VPN.\n\n"
                                                         @"Consult your network administrator or your VPN service provider to obtain"
                                                         @" configuration and other files or the information you need to modify the"
                                                         @" sample file.\n\n"
                                                         @"The configuration file is at\n%@\n\n", @"Window text"), cfgPath];
    return nil;
}

+(BOOL) bundleIdentifierIsValid: (id) bundleIdentifier {
    
    // Returns TRUE if the CFBundleVersion is a valid version number, FALSE otherwise
    
    return (   [[bundleIdentifier class] isSubclassOfClass: [NSString class]]
            && ([bundleIdentifier length] != 0)
			&& [bundleIdentifier containsOnlyCharactersInString: ALLOWED_DOMAIN_NAME_CHARACTERS]
            && ( 0 == [bundleIdentifier rangeOfString: @".."].length )
            && ( ! [bundleIdentifier hasSuffix: @"."])
            && ( ! [bundleIdentifier hasPrefix: @"."])  );
}

+(BOOL) bundleVersionIsValid: (id) bundleVersion {
    
    // Returns TRUE if the CFBundleVersion is a valid version number, FALSE otherwise
	
	if (   [[bundleVersion class] isSubclassOfClass: [NSString class]]
        && [bundleVersion containsOnlyCharactersInString: @"01234567890."]
		&& ([bundleVersion length] != 0)
		&& ( ! [bundleVersion hasPrefix: @"."])
		&& ( ! [bundleVersion hasSuffix: @"."]) ) {
		
		return TRUE;
	}
	
	return FALSE;
}

+(NSString *) rawTunnelblickVersion {
	
	// Returns '3.5beta02' from 'Tunnelblick 3.5beta02 (build...'
	
	NSString * thisTunnelblickVersion = tunnelblickVersion([NSBundle mainBundle]);
	if (  [thisTunnelblickVersion hasPrefix: @"Tunnelblick "]  ) {
		thisTunnelblickVersion = [thisTunnelblickVersion substringFromIndex: [@"Tunnelblick " length]];
	} else {
		NSLog(@"Invalid Tunnelblick version (not prefixed by 'Tunnelblick '): '%@'", thisTunnelblickVersion);
	}
	
	NSRange r = [thisTunnelblickVersion rangeOfString: @" "];
	if (  r.length == 0  ) {
		NSLog(@"Invalid Tunnelblick version (no space after 'Tunnelblick '): '%@'", thisTunnelblickVersion);
		r.location = [thisTunnelblickVersion length];
	}
	
	return [thisTunnelblickVersion substringToIndex: r.location];
}

+(NSString *) checkTunnelblickVersionAgainstInfoPlist: (NSDictionary *) plist displayName: (NSString *) displayName {
	
	// Returns nil if:
	//         The .plist is nil; or
	//		   The version of Tunnelblick is within all TBMinimumTunnelblickVersion and TBMaximumTunnelblickVersion limits in the .plist.
	// Otherwise returns a localized error string.
	
	if (  ! plist  ) {
		return nil;
	}
	
	NSEnumerator * e = [plist keyEnumerator];
	NSString * key;
	while (  (key = [e nextObject])  ) {
		
		if (  [key isEqualToString: @"TBMinimumTunnelblickVersion"]  ) {
			NSString * minimumTunnelblickVersion = [plist objectForKey: key];
			NSString * thisTunnelblickVersion = [self rawTunnelblickVersion];
			if (  [minimumTunnelblickVersion tunnelblickVersionCompare: thisTunnelblickVersion] == NSOrderedDescending) {
				return [NSString stringWithFormat: NSLocalizedString(@"Configuration '%@' requires Tunnelblick %@ or higher; you are using Tunnelblick %@.\n\n"
																	 @"You must update Tunnelblick to install this configuration.",
																	 @"Window text. The first '%@' will be the name of a configuration; the other two '%@' will each be a version number such as '3.5.4' or '3.5.3beta02'"),
						displayName, minimumTunnelblickVersion, thisTunnelblickVersion];
			};
			
		} else if (  [key isEqualToString: @"TBMaximumTunnelblickVersion"]  ) {
			NSString * maximumTunnelblickVersion = [plist objectForKey: key];
			NSString * thisTunnelblickVersion = [self rawTunnelblickVersion];
			if (  [maximumTunnelblickVersion tunnelblickVersionCompare: thisTunnelblickVersion] == NSOrderedAscending) {
				return [NSString stringWithFormat: NSLocalizedString(@"Configuration '%@' requires Tunnelblick %@ or lower; you are using Tunnelblick %@.",
																	 @"Window text. The first '%@' will be the name of a configuration; the other two '%@' will each be a version number such as '3.5.4' or '3.5.3beta02'"),
						displayName, maximumTunnelblickVersion, thisTunnelblickVersion];
			};
		}
	}
	
	return nil; // Info.plist does not require a different Tunnelblick version
}

+(NSString *) checkPlistEntries: (NSDictionary *) dict
                       fromPath: (NSString *)     path {
    
    // Returns nil or a localized error message
    
    if (  dict  ) {
        NSArray * stringKeys    = [NSArray arrayWithObjects:       // List of keys for string values
                                   @"CFBundleIdentifier",
                                   @"CFBundleVersion",
                                   @"CFBundleShortVersionString",
                                   @"TBPackageVersion",
                                   @"TBReplaceIdentical",
                                   @"TBSharePackage",
                                   @"SUFeedURL",
                                   @"SUPublicDSAKey",
                                   nil];
		
		NSArray * booleanKeys   = [NSArray arrayWithObjects:
                                   @"SUAllowsAutomaticUpdates",
                                   @"SUEnableAutomaticChecks",
                                   @"SUEnableSystemProfiling",
                                   @"SUShowReleaseNotes",
								   @"TBAppcastRequiresDSASignature",
                                   nil];
		
		NSArray * numberKeys    = [NSArray arrayWithObjects:
                                   @"SUScheduledCheckInterval",
                                   nil];
		
        NSArray * arrayKeys     = [NSArray arrayWithObjects:
                                   @"TBKeepExistingFilesList",
                                   nil];
        
        NSArray * replaceValues = [NSArray arrayWithObjects:    // List of valid values for TBReplaceIdentical
                                   @"ask",
                                   @"yes",
                                   @"no",
                                   @"force",
                                   nil];
        
        NSArray * shareValues   = [NSArray arrayWithObjects:      // List of valid values for TBSharePackage
                                   @"ask",
                                   @"private",
                                   @"shared",
                                   @"deploy",
                                   nil];
        
		BOOL hasTBPackageVersion = NO;
        NSString * key;
        NSEnumerator * e = [dict keyEnumerator];
        while (  (key = [e nextObject])  ) {
            if (  [stringKeys containsObject: key]  ) {
                id obj = [dict objectForKey: key];
                if (  ! [[obj class] isSubclassOfClass: [NSString class]]  ) {
                    return [NSString stringWithFormat: NSLocalizedString(@"Non-string value for '%@' in %@", @"Window text - First %@ is the name of a Key, second %@ is the path to an Info.plist file"), key, path];
                }
				NSString * value = (NSString *)obj;
                if (  [key isEqualToString: @"TBPackageVersion"]  ) {
                    if (  ! [value isEqualToString: @"1"]  ) {
                        return [NSString stringWithFormat: NSLocalizedString(@"Invalid value '%@' for '%@' in %@", @"Window text - First %@ is the value of a key, second %@ is the name of the key, third %@ is the path to the Info.plist file containing the key/value pair"), value, key, path];
                    }
					hasTBPackageVersion = TRUE;
                    
                } else if (  [key isEqualToString: @"CFBundleIdentifier"]  ) {
                    if (  ! [ConfigurationManager bundleIdentifierIsValid: value]  ) {
                        return [NSString stringWithFormat: NSLocalizedString(@"Invalid value '%@' for '%@' in %@", @"Window text - First %@ is the value of a key, second %@ is the name of the key, third %@ is the path to the Info.plist file containing the key/value pair"), value, key, path];
                    }
                    
                } else if (  [key isEqualToString: @"CFBundleVersion"]  ) {
                    if (  ! [ConfigurationManager bundleVersionIsValid: value]  ) {
                        return [NSString stringWithFormat: NSLocalizedString(@"Invalid value '%@' for '%@' in %@", @"Window text - First %@ is the value of a key, second %@ is the name of the key, third %@ is the path to the Info.plist file containing the key/value pair"), value, key, path];
                    }
                    
                    
                } else if (  [key isEqualToString: @"TBReplaceIdentical"]  ) {
                    if (  ! [replaceValues containsObject: value]  ) {
                        return [NSString stringWithFormat: NSLocalizedString(@"Unknown value '%@' for '%@' in %@", @"Window text - First %@ is the value of a key, second %@ is the name of the key, third %@ is the path to the Info.plist file containing the key/value pair"), value, key, path];
                    }
                    
                } else if (  [key isEqualToString: @"TBSharePackage"]  ) {
                    if (  ! [shareValues containsObject: value]  ) {
                        return [NSString stringWithFormat: NSLocalizedString(@"Unknown value '%@' for '%@' in %@", @"Window text - First %@ is the value of a key, second %@ is the name of the key, third %@ is the path to the Info.plist file containing the key/value pair"), value, key, path];
                    }
                } else if (  [key isEqualToString: @"SUFeedURL"]  ) {
					if (  ! [NSURL URLWithString: value]  ) {
                        return [NSString stringWithFormat: NSLocalizedString(@"Value '%@' for '%@' is not a valid URL in %@", @"Window text - First %@ is the value of a key, second %@ is the name of the key, third %@ is the path to the Info.plist file containing the key/value pair"), value, key, path];
                    }
                } // Don't test values for the other string keys; as long as they are strings we will install the .plist
            } else if (  [booleanKeys containsObject: key]  ) {
                id obj = [dict objectForKey: key];
                if (  ! [obj respondsToSelector: @selector(boolValue)]  ) {
                    return [NSString stringWithFormat: NSLocalizedString(@"Non-boolean value for '%@' in %@", @"Window text - First %@ is the name of a Key, second %@ is the path to an Info.plist file"), key, path];
                }
			} else if (  [numberKeys containsObject: key]  ) {
				id obj = [dict objectForKey: key];
				if (  ! [obj respondsToSelector: @selector(intValue)]  ) {
					return [NSString stringWithFormat: NSLocalizedString(@"Non-integer value for '%@' in %@", @"Window text - First %@ is the name of a Key, second %@ is the path to an Info.plist file"), key, path];
				}
			} else if (  [arrayKeys containsObject: key]  ) {
				id obj = [dict objectForKey: key];
				if (  obj  ) {
                    if (  ! [obj respondsToSelector: @selector(objectEnumerator)]  ) {
						return [NSString stringWithFormat: NSLocalizedString(@"Non-array value for '%@' in %@", @"Window text - First %@ is the name of a Key, second %@ is the path to an Info.plist file"), key, path];
					}
					id item;
					NSEnumerator * itemEnum = [obj objectEnumerator];
					while (  (item = [itemEnum nextObject])  ) {
						if (  ! [[item class] isSubclassOfClass: [NSString class]] ) {
							return [NSString stringWithFormat: NSLocalizedString(@"Non-string value for an item in '%@' in %@", @"Window text - First %@ is the name of a Key, second %@ is the path to an Info.plist file"), key, path];
						}
					}
				}
			} else if (  [key hasPrefix: @"TBPreference"]  ) {
				NSString * pref = [key substringFromIndex: [@"TBPreference" length]];
				if (  ! [gConfigurationPreferences containsObject: pref]  ) {
					return [NSString stringWithFormat: NSLocalizedString(@"A TBPreference or TBAlwaysSetPreference key refers to an unknown preference '%@' in %@", @"Window text"), pref, path];
				}
			} else if (  [key hasPrefix: @"TBAlwaysSetPreference"]  ) {
				NSString * pref = [key substringFromIndex: [@"TBAlwaysSetPreference" length]];
				if (  ! [gConfigurationPreferences containsObject: pref]  ) {
					return [NSString stringWithFormat: NSLocalizedString(@"A TBPreference or TBAlwaysSetPreference key refers to an unknown preference '%@' in %@", @"Window text"), pref, path];
				}
			} else if (   ( ! [key isEqualToString: @"TBUninstall"] )
					   && ( ! [key isEqualToString: @"TBMinimumTunnelblickVersion"] )
					   && ( ! [key isEqualToString: @"TBMaximumTunnelblickVersion"] )
					   && ( ! [key isEqualToString: @"TBConfigurationUpdateURL"] )  ) {
                return [NSString stringWithFormat: NSLocalizedString(@"Unknown key '%@' in %@", @"Window text"), key, path];
            }
        }
		
		if (  ! hasTBPackageVersion  ) {
			return [NSString stringWithFormat: NSLocalizedString(@"No 'TBPackageVersion' in %@", @"Window text"), path];
		}
    }
	
    return nil;
}

+(id) plistOrErrorMessageInTblkAtPath: (NSString *) path {
    
    // Returns an NSDictionary with the contents of the .plist
    // or     an NSString with an error message, or
    // or      nil if there is no .plist, or
    
    NSString * directPath     = [path stringByAppendingPathComponent: @"Info.plist"];
    NSString * inContentsPath = [path stringByAppendingPathComponent: @"Contents/Info.plist"];
    BOOL       haveDirect     = [gFileMgr fileExistsAtPath: directPath];
    BOOL       haveInContents = [gFileMgr fileExistsAtPath: inContentsPath];
    
    NSString * plistPath;
    if (  haveDirect  ) {
        if (  haveInContents  ) {
            return [NSString stringWithFormat: @"Conflict: Both %@ and .../Contents/Info.plist exist", directPath];
        }
        plistPath = directPath;
    } else {
        if (  haveInContents  ) {
            plistPath = inContentsPath;
        } else {
            return nil;
        }
    }
    
    NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: plistPath];
    if (  ! dict  ) {
        return [NSString stringWithFormat: @"%@ is corrupted and cannot be processed", plistPath];
    }
    
    NSString * result = [ConfigurationManager checkPlistEntries: dict fromPath: plistPath];
    if (  result  ) {
        return result;
    }
    
    return dict;
}

+(NSDictionary *) plistInTblkAtPath: (NSString *) path {
    
    // Returns an NSDictionary with the contents of the plist
    // or nil if there is a problem (an error message was logged)
    
    id obj = [ConfigurationManager plistOrErrorMessageInTblkAtPath: path];
    if (   ( ! obj)
        || [[obj class] isSubclassOfClass: [NSDictionary class]]  ) {
        return (NSDictionary *) obj;
    }
    
    NSLog(@"Ignoring Info.plist:\n%@", obj);
    return nil;
}

+(BOOL)  addConfigsFromPath: (NSString *)               folderPath
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
                    TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                                      [NSString stringWithFormat: NSLocalizedString(@"Configuration '%@' will be ignored because its"
                                                                                    @" name contains characters that are not allowed.\n\n"
																			        @"Characters that are not allowed: '%s'\n\n", @"Window text"),
									   dispName, PROHIBITED_DISPLAY_NAME_CHARACTERS_WITH_SPACES_CSTRING]);
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

+(NSMutableDictionary *) getConfigurations {
    
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
    
    noneIgnored = [ConfigurationManager addConfigsFromPath: gDeployPath  thatArePackages: YES toDict: dict searchDeeply: YES ] && noneIgnored;
    noneIgnored = [ConfigurationManager addConfigsFromPath: gDeployPath  thatArePackages:  NO toDict: dict searchDeeply: YES ] && noneIgnored;
    noneIgnored = [ConfigurationManager addConfigsFromPath: L_AS_T_SHARED  thatArePackages: YES toDict: dict searchDeeply: YES ] && noneIgnored;
    noneIgnored = [ConfigurationManager addConfigsFromPath: gPrivatePath thatArePackages:   YES toDict: dict searchDeeply: YES ] && noneIgnored;
    
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

+(BOOL) userCanEditConfiguration: (NSString *) filePath {
    
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

+(NSString *) condensedConfigFileContentsFromString: (NSString *) fullString {
	
	// Returns a string from an OpenVPN configuration file with empty lines and comments removed
	
	NSArray * lines = [fullString componentsSeparatedByString: @"\n"];
	
	NSMutableString * outString = [[[NSMutableString alloc] initWithCapacity: [fullString length]] autorelease];
	NSString * line;
	NSEnumerator * e = [lines objectEnumerator];
	while (  (line = [e nextObject])  ) {
		line = [line stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (  [line length] != 0  ) {
			NSString * firstChar = [line substringToIndex: 1];
			if (   ( ! [firstChar isEqualToString: @";"] )
				&& ( ! [firstChar isEqualToString: @"#"] )  ) {
				[outString appendFormat: @"%@\n", line];
			}
		}
	}
	
	return [NSString stringWithString: outString];
}

-(void) examineConfigFileForConnection: (VPNConnection *) connection {
    
    // Display the sanitized contents of the configuration file in a window
    
    NSString * configFileContents = [connection sanitizedConfigurationFileContents];
    if (  configFileContents  ) {
        NSString * heading = [NSString stringWithFormat: NSLocalizedString(@"%@ OpenVPN Configuration - Tunnelblick", @"Window title"),[connection localizedName]];
        
        // NOTE: The window controller is allocated here, but releases itself when the window is closed.
        //       So _we_ don't release it, and we can overwrite listingWindow with impunity.
        //       (The instance variable 'listingWindow' is used to avoid an analyzer warning about a leak.)
        listingWindow = [[ListingWindowController alloc] initWithHeading: heading
                                                                    text: configFileContents];
        [listingWindow showWindow: self];
    }
}

+(void) editOrExamineConfigurationForConnection: (VPNConnection *) connection {
    
    NSString * targetPath = [connection configPath];
    if ( ! targetPath  ) {
        NSLog(@"editOrExamineConfigurationForConnection: No path for configuration %@", [connection displayName]);
        return;
    }
    
    if (  [ConfigurationManager userCanEditConfiguration: targetPath]  ) {
		if (  [[targetPath pathExtension] isEqualToString: @"tblk"]  ) {
			targetPath = [targetPath stringByAppendingPathComponent: @"Contents/Resources/config.ovpn"];
		}
        [connection invalidateConfigurationParse];
        [[NSWorkspace sharedWorkspace] openFile: targetPath withApplication: @"TextEdit"];
    } else {
        [[ConfigurationManager manager] examineConfigFileForConnection: connection];
    }
}

+(NSString *) parseString: (NSString *) cfgContents
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

+(NSString *)parseConfigurationForConnection: (VPNConnection *) connection
							 hasAuthUserPass: (BOOL *)          hasAuthUserPass
						  authRetryParameter: (NSString **)	    authRetryParameter
                            allowInteraction: (BOOL)            allowInteraction {
	
    // Parses the configuration file.
    // Sets *hasAuthUserPass TRUE if configuration has a 'auth-user-pass' option with no arguments; FALSE otherwise
	// Sets *authRetryParameter (which must be nil) to the first parameter of an 'auth-retry' option if it appears in the file
    // Gives user the option of adding the down-root plugin if appropriate
    // Returns with device type: "tun", "tap", "utun", or nil if it can't be determined
    // Returns with string "Cancel" if user cancelled
	
    NSString * doNotParseKey = [[connection displayName] stringByAppendingString: @"-doNotParseConfigurationFile"];
    if (  [gTbDefaults boolForKey: doNotParseKey]  ) {
        return nil;
    }
    
    NSString * cfgContents = [connection condensedSanitizedConfigurationFileContents];
	if (  ! cfgContents  ) {
		return nil;
	}
    
    // Set hasAuthUserPass TRUE if auth-user-pass appears and has no parameters
    if (  hasAuthUserPass  ) {
        NSString * authUserPassOption = [ConfigurationManager parseString: cfgContents forOption: @"auth-user-pass" ];
        *hasAuthUserPass = (  authUserPassOption
                            ? ([authUserPassOption length] == 0)
                            : NO);
    }

	// Set authRetryParameter
    if (  authRetryParameter  ) {
        NSString * theAuthRetryParameter = [ConfigurationManager parseString: cfgContents forOption: @"auth-retry" ];
        if (  *authRetryParameter  ) {
            NSLog(@"parseConfigurationForConnection: *authRetryParameter is not nil, so it is not being set to %@", theAuthRetryParameter);
        } else {
            *authRetryParameter = theAuthRetryParameter;
        }
    }
    
    NSString * userOption  = [ConfigurationManager parseString: cfgContents forOption: @"user" ];
    if (  [userOption length] == 0  ) {
        userOption = nil;
    }
    NSString * groupOption = [ConfigurationManager parseString: cfgContents forOption: @"group"];
    if (  [groupOption length] == 0  ) {
        groupOption = nil;
    }
    NSString * useDownRootPluginKey = [[connection displayName] stringByAppendingString: @"-useDownRootPlugin"];
    NSString * skipWarningKey = [[connection displayName] stringByAppendingString: @"-skipWarningAboutDownroot"];
    if (   allowInteraction
        && ( ! [gTbDefaults boolForKey: useDownRootPluginKey] )
        &&     [gTbDefaults canChangeValueForKey: useDownRootPluginKey]
        && ( ! [gTbDefaults boolForKey: skipWarningKey] )  ) {
        
        NSString * downOption  = [ConfigurationManager parseString: cfgContents forOption: @"down" ];
        if (  [downOption length] == 0  ) {
            downOption = nil;
        }
        
        if (   (userOption || groupOption)
            && (   downOption
                || ([connection useDNSStatus] != 0)  )  ) {
                
                NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"The configuration file for '%@' appears to use the 'user' and/or 'group' options and is using a down script ('Do not set nameserver' not selected, or there is a 'down' option in the configuration file).\n\nIt is likely that restarting the connection (done automatically when the connection is lost) will fail unless the 'openvpn-down-root.so' plugin for OpenVPN is used.\n\nDo you wish to use the plugin?", @"Window text"),
                                  [connection localizedName]];
                
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
    
    NSArray * reservedOptions = OPENVPN_OPTIONS_THAT_CAN_ONLY_BE_USED_BY_TUNNELBLICK;
    NSString * option;
    NSEnumerator * e = [reservedOptions objectEnumerator];
    while (  (option = [e nextObject])  ) {
        NSString * optionValue = [ConfigurationManager parseString: cfgContents forOption: option];
        if (  optionValue  ) {
            NSLog(@"The configuration file for '%@' contains an OpenVPN '%@' option. That option is reserved for use by Tunnelblick. The option will be ignored", [connection displayName], option);
		}
    }
    
    if (  allowInteraction  ) {
        NSArray * windowsOnlyOptions = OPENVPN_OPTIONS_THAT_ARE_WINDOWS_ONLY;
        e = [windowsOnlyOptions objectEnumerator];
        while (  (option = [e nextObject])  ) {
            NSString * optionValue = [ConfigurationManager parseString: cfgContents forOption: option];
            if (  optionValue  ) {
                NSLog(@"The OpenVPN configuration file in %@ contains a '%@' option, which is a Windows-only option. It cannot be used on macOS.", [connection displayName], option);
                NSString * msg = [NSString stringWithFormat:
                                  NSLocalizedString(@"The OpenVPN configuration file in %@ contains a '%@' option, which is a Windows-only option. It cannot be used on macOS.", @"Window text"),
                                  [connection localizedName], option];
                TBShowAlertWindow(NSLocalizedString(@"Tunnelblick Error", @"Window title"),
                                  msg);
            }
        }
    }
    
    // If there is a "dev-node" entry, return that device type (tun, utun, tap)
	NSString * devNodeOption = [ConfigurationManager parseString: cfgContents forOption: @"dev-node"];
	if (  devNodeOption  ) {
		if (  [devNodeOption hasPrefix: @"tun"]  ) {
			return @"tun";
		}
		if (  [devNodeOption hasPrefix: @"utun"]  ) {
			return @"utun";
		}
		if (  [devNodeOption hasPrefix: @"tap"]  ) {
			return @"tap";
		}
		NSLog(@"The configuration file for '%@' contains a 'dev-node' option, but the argument does not begin with 'tun', 'tap', or 'utun'", [connection displayName]);
	}
    
    // If there is a "dev-type" entry, return that device type (tun or tap)
    NSString * devTypeOption = [ConfigurationManager parseString: cfgContents forOption: @"dev-type"];
    if (  devTypeOption  ) {
        if (  [devTypeOption isEqualToString: @"tun"]  ) {
            return @"utun";
        }
        if (  [devTypeOption isEqualToString: @"tap"]  ) {
            return @"tap";
        }
        NSLog(@"The configuration file for '%@' contains 'dev-type %@'. Ony 'dev-type tun' and 'dev-type tap' are allowed", devTypeOption, [connection displayName]);
    }
    
    // If there is a "dev" entry, return that device type for 'tap' or 'utun' but for 'tun', return 'utun'
    NSString * devOption = [ConfigurationManager parseString: cfgContents forOption: @"dev"];
    if (  devOption  ) {
		if (   [devOption hasPrefix: @"tun"]
            || [devOption hasPrefix: @"utun"]  ) {
			return @"utun";
		}
		if (  [devOption hasPrefix: @"tap"]  ) {
			return @"tap";
		}

        if (  allowInteraction  ) {
            NSLog(@"The configuration file for '%@' contains a 'dev' option, but the argument does not begin with 'tun', 'tap', or 'utun'", [connection displayName]);
            NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"The configuration file for '%@' does not appear to contain a 'dev tun', 'dev utun', or 'dev tap' option. This option may be needed for proper Tunnelblick operation. Consult with your network administrator or the OpenVPN documentation.", @"Window text"),
                              [connection localizedName]];
            skipWarningKey = [[connection displayName] stringByAppendingString: @"-skipWarningAboutNoTunOrTap"];
            TBRunAlertPanelExtended(NSLocalizedString(@"No 'dev tun', 'dev utun', or 'dev tap' found", @"Window title"),
                                    msg,
                                    nil, nil, nil,
                                    skipWarningKey,
                                    NSLocalizedString(@"Do not warn about this again for this configuration", @"Checkbox name"),
                                    nil,
                                    NSAlertDefaultReturn);
        }
    }
    
    return nil;
}

+(NSString *)parseConfigurationForConnection: (VPNConnection *) connection
                             hasAuthUserPass: (BOOL *)          hasAuthUserPass
                          authRetryParameter: (NSString **)	    authRetryParameter {

    return [self parseConfigurationForConnection: connection
                                 hasAuthUserPass: hasAuthUserPass
                              authRetryParameter: authRetryParameter
                                allowInteraction: YES];
}

+(NSString *) parseConfigurationForTunTapForConnection: (VPNConnection *) connection {

    // Returns the type of connection the configuration will use: 'tun', 'tap', 'utun'
    // Returns nil if the the type could not be deterimined.
    //
    // Does not interact with the user.

    BOOL hasAuthUserPass = NO;
    NSString * authRetryParameter = nil;

    return [self parseConfigurationForConnection: connection
                                 hasAuthUserPass: &hasAuthUserPass
                              authRetryParameter: &authRetryParameter
                                allowInteraction: NO];
}

+(BOOL) deleteConfigOrFolderAtPath: (NSString *)   targetPath
                   usingSystemAuth: (SystemAuth *) auth
                        warnDialog: (BOOL)         warn {

    // Deletes a config file or package or a folder
    // Returns TRUE if succeeded
    // Returns FALSE if failed, having already output an error message to the console log
    
    // If it is a .tblk and has a SUFeedURL, CFBundleVersion, and CFBundleIdentifier Info.plist entries, remember the CFBundleIdentifier for later
    NSString * bundleId = nil;
    if (  [targetPath hasSuffix: @".tblk"]  ) {
        NSDictionary * infoDict = [ConfigurationManager plistInTblkAtPath: targetPath];
        if (   [infoDict objectForKey: @"SUFeedURL"]
            && [infoDict objectForKey: @"CFBundleVersion"]  ) {
            bundleId = [infoDict objectForKey: @"CFBundleIdentifier"];
        }
    }
    
    NSArray * arguments = [NSArray arrayWithObject: targetPath];
    
    NSInteger result = [gMC runInstaller: INSTALLER_DELETE
                                                           extraArguments: arguments
                                                          usingSystemAuth: auth
                                                             installTblks: nil];
    if (  result != 0  ) {
        NSLog(@"Error while deleting %@", targetPath);
        return FALSE;
    }

    NSString * localName = lastPartOfPath(targetPath);
    if (  [localName hasSuffix: @".tblk"]  ) {
        localName = [gMC
                    localizedNameForDisplayName:  [localName stringByDeletingPathExtension]];
    }

    if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
        NSLog(@"Could not remove %@", targetPath);
        if (  warn  ) {
            NSString * title = NSLocalizedString(@"Tunnelblick", @"Window title");
            NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not remove %@. See the Console Log for details.", @"Window text. The '%@' refers to a configuration or a folder of configurations."), localName];
            TBShowAlertWindow(title, msg);
        }
        return FALSE;
    }
	
    NSLog(@"Deleted '%@'", targetPath);

    if (  ! [targetPath hasSuffix: @".tblk"]  ) {
        return TRUE;
    }


    if (  bundleId  ) {
        
          // Stop updating any configurations with this bundleId
		[[gMC myConfigMultiUpdater] stopUpdateCheckingForAllStubTblksWithBundleIdentifier: bundleId];
		
        // Delete all master stub .tblk containers with this bundleId
        NSArray * stubTblkPaths = [ConfigurationMultiUpdater pathsForMasterStubTblkContainersWithBundleIdentifier: bundleId];
        NSString * containerPath;
        NSEnumerator * e = [stubTblkPaths objectEnumerator];
        while (  (containerPath = [e nextObject])) {
            arguments = [NSArray arrayWithObject: containerPath];
            result = [gMC runInstaller: INSTALLER_DELETE
                                                         extraArguments: arguments
                                                        usingSystemAuth: auth
                                                           installTblks: nil];
            if (  result != 0  ) {
                NSLog(@"Error while uninstalling master \"stub\" .tblk for '%@' at path %@", bundleId, containerPath);
                return FALSE;
            }
            if (  [gFileMgr fileExistsAtPath: containerPath]  ) {
                NSLog(@"Could not delete \"stub\" .tblk container %@", containerPath);
                if (  warn  ) {
                    NSString * title = NSLocalizedString(@"Could Not Uninstall Configuration", @"Window title");
                    NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not completely remove the '%@' configuration. See the Console Log for details.", @"Window text"), localName];
                    TBShowAlertWindow(title, msg);
                }
                return FALSE;
            } else {
                NSLog(@"Uninstalled master \"stub\" .tblk for %@", bundleId);
            }
        }
    }
    
    return TRUE;
}

+(void) guideState: (enum state_t) state {
    
    // guideState is sort of a state machine for displaying configuration dialog windows. It has a simple, LIFO history stored in an array to implement a "back" button
    
    enum state_t nextState;
	
    int button;
    
    NSMutableArray * history = [NSMutableArray arrayWithCapacity: 20];  // Contains NSNumbers containing state history
    
    while ( TRUE  ) {
        
        switch (  state  ) {
                
                
            case entryNoConfigurations:
                
                // No configuration files (entry from haveNoConfigurationsGuild)
                button = TBRunAlertPanelExtendedPlus(NSLocalizedString(@"Welcome to Tunnelblick", @"Window title"),
                                                     NSLocalizedString(@"There are no VPN configurations installed.\n\n"
                                                                       "Tunnelblick needs one or more installed configurations to connect to a VPN. "
                                                                       "Configurations are installed from files that are usually supplied to you by your network manager "
                                                                       "or VPN service provider. The files must be installed to be used.\n\n"
                                                                       "Configuration files have extensions of .tblk, .ovpn, or .conf.\n\n"
                                                                       "(There may be other files associated with the configuration that have other extensions; ignore them for now.)\n\n"
                                                                       "Do you have any configuration files?\n",
                                                                       @"Window text"),
                                                     NSLocalizedString(@"I have configuration files", @"Button"),        // Default button
                                                     NSLocalizedString(@"Quit", @"Button"),                              // Alternate button
                                                     NSLocalizedString(@"I DO NOT have configuration files", @"Button"), // Other button
                                                     nil, nil, nil, FALSE,
                                                     gMC, @selector(haveConfigurations)); // Abort this dialog if we have configurations
                
                if (  button == NSAlertAlternateReturn  ) {
                    [gMC terminateBecause: terminatingBecauseOfQuit];
                    return;
                } else if (  button == NSAlertErrorReturn  ) {
                    return;
                } else if (  button == NSAlertDefaultReturn  ) {
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
													
													"2. Change the name of the configuration file to a name of your choice (do not change the file's extension). "
													"This will be the name that Tunnelblick uses for the configuration.\n\n"
													
													"3. To install the configuration, drag the configuration file and drop it on the Tunnelblick icon in the menu bar or on the list of configurations in the 'Configurations' tab of the 'VPN Details' window.",
													
													@"Window text"));
                return;
                
                
            case entryAddConfiguration:
            case stateHasConfigurations:
                TBShowAlertWindow(NSLocalizedString(@"Add a Configuration", @"Window title"),
                                  [NSString stringWithFormat: @"%@",
                                   NSLocalizedString(@"Configurations are installed from files that are supplied to you by your network manager "
                                                     "or VPN service provider.\n\n"
                                                     "Configuration files have extensions of .tblk, .ovpn, or .conf.\n\n"
                                                     "(There may be other files associated with the configuration that have other extensions; ignore them.)\n\n"
                                                     "To install a configuration file, drag and drop it on the Tunnelblick icon in the menu bar or on the list of configurations in the 'Configurations' tab of the 'VPN Details' window.\n\n"
                                                     "To install multiple configuration files at one time, select all the files and then drag and drop all of them.",
                                                     @"Window text")]);
								   
                
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

// *********************************************************************************************
// Configuration installation methods

-(NSString *) confirmReplace: (NSString *) localizedName
                          in: (NSString *) sharedOrPrivate {
    
    // Returns "skip" if user want to skip this one configuration
    // Returns "cancel" if user cancelled
    // Returns "shared" or "private" to indicate where the configuration should be replaced
    // Otherwise, returns a localized error message
    
    if (  [[self applyToAllSharedPrivate] isEqualToString: sharedOrPrivate]  ) {
        return sharedOrPrivate;
    }
    
    int result = TBRunAlertPanel(NSLocalizedString(@"Replace VPN Configuration?", @"Window title"),
                                 [NSString stringWithFormat: NSLocalizedString(@"Do you wish to replace the '%@' configuration?\n\n", @"Window text"), localizedName],
                                 NSLocalizedString(@"Replace"  , @"Button"),    // Default button
                                 NSLocalizedString(@"Skip"     , @"Button"),    // Alternate button
                                 NSLocalizedString(@"Cancel"   , @"Button"));   // Other button
    switch (  result  ) {
            
        case NSAlertDefaultReturn:
            return sharedOrPrivate;
            
        case NSAlertAlternateReturn:
            return @"skip";
            
        case NSAlertOtherReturn:
            return @"cancel";
            
        default:
            return NSLocalizedString(@"TBRunAlertPanel returned an error", @"Window text");
    }
}

-(NSString *) askSharedOrPrivateForConfig: (NSString *) localizedName {
    
    // Returns "cancel" if user cancelled
    // Returns "shared" or "private" to indicate user's choice of where to install
    // Anything else is a localized error message
    //
    // Sets *shareAllPtr or *privateAllPtr if the user checked the corresponding checkbox
    
    NSString * allSharedPrivate = [self applyToAllSharedPrivate];
    if (  allSharedPrivate  ) {
        return allSharedPrivate;
    }
    
    BOOL applyToAllCheckboxChecked = FALSE;
    
    NSString * applyToAllCheckboxLabel = (  ! [self inhibitCheckbox]
                                          ? NSLocalizedString(@"Apply to all", @"Checkbox name")
                                          : nil);
    
    BOOL * applyToAllCheckboxCheckedPtr = (  ! [self inhibitCheckbox]
                                           ? &applyToAllCheckboxChecked
                                           : nil);
    
    int result = TBRunAlertPanelExtended(NSLocalizedString(@"Install Configuration For All Users?", @"Window title"),
                                         [NSString stringWithFormat: NSLocalizedString(@"Do you wish to install the '%@' configuration so that all users can use it, or so that only you can use it?\n\n", @"Window text"), localizedName],
                                         NSLocalizedString(@"Only Me"  , @"Button"),    // Default button
                                         NSLocalizedString(@"All Users", @"Button"),    // Alternate button
                                         NSLocalizedString(@"Cancel"   , @"Button"),    // Other button
                                         nil,
                                         applyToAllCheckboxLabel,
                                         applyToAllCheckboxCheckedPtr,
                                         NSAlertDefaultReturn);
    
    switch (  result  ) {
            
        case NSAlertDefaultReturn:
            if (  applyToAllCheckboxChecked  ) {
                [self setApplyToAllSharedPrivate: @"private"];
            }
            return @"private";
            
        case NSAlertAlternateReturn:
            if (  applyToAllCheckboxChecked  ) {
                [self setApplyToAllSharedPrivate: @"shared"];
            }
            return @"shared";
            
        case NSAlertOtherReturn:
            return @"cancel";
            
        default:
            return NSLocalizedString(@"TBRunAlertPanel returned an error", @"Window text");
    }
}

-(NSString *) pathOfTblkToReplaceWithBundleIdentifier: (NSString *) bundleIdentifier {
    
    
    NSArray * dirList = [NSArray arrayWithObjects: gDeployPath, L_AS_T_SHARED, gPrivatePath, nil];
    
    NSString * folderPath;
    NSEnumerator * e = [dirList objectEnumerator];
    while (  (folderPath = [e nextObject])  ) {
        
        NSString * filename;
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: folderPath];
        while (  (filename = [dirEnum nextObject])  ) {
            if (  [filename hasSuffix: @".tblk"]  ) {
				[dirEnum skipDescendents];
				NSString * fullPath = [folderPath stringByAppendingPathComponent: filename];
                NSDictionary * fileInfoPlist = [ConfigurationManager plistInTblkAtPath: fullPath];
                NSString * fileCfBundleIdentifier = [fileInfoPlist objectForKey: @"CFBundleIdentifier"];
                if (  [fileCfBundleIdentifier isEqualToString: bundleIdentifier]  ) {
                    return fullPath;
                }
            }
        }
    }
    
    return nil;
}

-(NSString *) targetPathToReplaceForDisplayName: (NSString *)     displayName
                                       inFolder: (NSString *)     folder
                                  infoPlistDict: (NSDictionary *) infoPlistDict
                              replacingTblkPath: (NSString *)     replacingTblkPath
                             cfBundleIdentifier: (NSString *)     cfBundleIdentifier
                                cfBundleVersion: (NSString *)     cfBundleVersion {
    
    // Uses cfBundleIdentifier and cfBundleVersion to check for a configuration that should be replaced.
    //
    // Returns nil if should decide replacement some other way
    // Returns "skip" to skip this one configuration
    // Returns "cancel" if user cancelled
    // Returns a string beginning with "/" containing the path to which the .tblk should be installed
    // Anything else that is returned is a localized error message
    
    if (  ! (   cfBundleIdentifier
             && cfBundleVersion)  ) {
        return nil;
    }
    
    NSString * file;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: folder];
    while (  (file = [dirEnum nextObject])  ) {
        NSString * ext = [file pathExtension];
        if (  [ext isEqualToString: @"tblk"]  ) {
            
            [dirEnum skipDescendents];
            
            NSString * fullPath = [folder stringByAppendingPathComponent: file];
            
            NSDictionary * plist = [ConfigurationManager plistOrErrorMessageInTblkAtPath: fullPath];
            if (  [[plist class] isSubclassOfClass: [NSString class]]  ) {
                return (NSString *)plist;
            }
            if (  ! plist  ) {
                return nil;
            }
            
            NSString * cfBI   = [plist objectForKey: @"CFBundleIdentifier"];
            NSString * cfBV   = [plist objectForKey: @"CFBundleVersion"];
            if (  ! (   cfBI
                     && cfBV)  ) {
                continue;
            }
            
            if (  [cfBI isNotEqualTo: cfBundleIdentifier]  ) {
                continue;
            }
            
            BOOL doUninstall = (nil != [infoPlistDict objectForKey: @"TBUninstall"]);
            
			if (  doUninstall  ) {
				return fullPath;
			}
			
            NSString * localName = [gMC localizedNameforDisplayName: displayName tblkPath: fullPath];

			NSString * tbReplaceIdentical = [infoPlistDict objectForKey: @"TBReplaceIdentical"];
			
			if (  [tbReplaceIdentical isEqualToString: @"no"]  ) {
				NSLog(@"Tunnelblick VPN Configuration %@ will NOT be installed: TBReplaceOption=NO.", displayName);
				TBShowAlertWindow(@"Tunnelblick", 
								  [NSString stringWithFormat: NSLocalizedString(@"VPN Configuration %@ will NOT be installed because the configuration already exists and should not be replaced.", @"Window text"), localName]);
				return @"skip";
				
			}
			
			if (  [tbReplaceIdentical isEqualToString: @"yes"]  ) {
				if (  [cfBV compare: cfBundleVersion options: NSNumericSearch] == NSOrderedDescending  ) {
					NSLog(@"VPN Configuration %@ will NOT be installed: it has a lower version number.", displayName);
					TBShowAlertWindow(@"Tunnelblick", 
									  [NSString stringWithFormat: NSLocalizedString(@"VPN Configuration %@ will NOT be installed because it has a lower version number.", @"Window text"), localName]);
					return @"skip";
				}
			}
			
            if (   replacingTblkPath
                && ( ! [replacingTblkPath isEqualToString: fullPath] )  ) {
                return [NSString stringWithFormat:
                         NSLocalizedString(@"targetPathToReplaceForDisplayName: %@ was found to replace the configuration with CFBundleIdentifer %@, but earlier, %@ was found to replace it.", @"Window text"),
                        fullPath, cfBundleIdentifier, replacingTblkPath];
            }
            
            if (  [tbReplaceIdentical isEqualToString: @"ask"]  ) {
                
                NSString * msg;
                NSString * buttonName;
                if (  [cfBV compare: cfBundleVersion options: NSNumericSearch] == NSOrderedSame  ) {
					msg = [NSString stringWithFormat: NSLocalizedString(@"Do you wish to reinstall '%@' version %@?", @"Window text"),
						   localName,
						   cfBundleVersion];
					buttonName = NSLocalizedString(@"Reinstall", @"Button");
				} else {
					msg = [NSString stringWithFormat: NSLocalizedString(@"Do you wish to replace '%@' version %@ with version %@?", @"Window text"),
						   localName,
						   cfBundleVersion,
						   cfBV];
					buttonName = NSLocalizedString(@"Replace", @"Button");
				}
                
                int result = TBRunAlertPanel(NSLocalizedString(@"VPN Configuration Installation", @"Window title"),
                                             msg,
                                             buttonName,                                    // Default button
                                             NSLocalizedString(@"Skip"     , @"Button"),    // Alternate button
                                             NSLocalizedString(@"Cancel"   , @"Button"));   // Other button
                switch (  result  ) {
                        
                    case NSAlertDefaultReturn:
                        return fullPath;
                        
                    case NSAlertAlternateReturn:
                        return @"skip";
                        
                    case NSAlertOtherReturn:
                        return @"cancel";
                        
                    default:
                        return NSLocalizedString(@"TBRunAlertPanel returned an error", @"Window text");
                }
            }
			
            // Fell through, so tbReplaceIdentical == "force", so do the (un)install
            return fullPath;
        }
    }
    
    return nil;
}

-(NSString *) targetPathForDisplayName: (NSString *)     displayName
                         infoPlistDict: (NSDictionary *) infoPlistDict
                     replacingTblkPath: (NSString *)     replacingTblkPath
                    cfBundleIdentifier: (NSString *)     cfBundleIdentifier
                       cfBundleVersion: (NSString *)     cfBundleVersion {
    
    // Uses cfBundleIdentifier and cfBundleVersion to check for a configuration that should be replaced.
    //
    // Returns nil if should decide replacement using the displayName
    // Returns "skip" to skip this one configuration
    // Returns "cancel" if user cancelled
    // Returns a string beginning with "/" containing the path to which the .tblk should be installed
    // Anything else that is returned is a localized error message
    
    NSString * path;
	
	BOOL doUninstall = (nil != [infoPlistDict objectForKey: @"TBUninstall"]);

	if (  ! doUninstall  ) {
		path = [self targetPathToReplaceForDisplayName: displayName
											  inFolder: gDeployPath
										 infoPlistDict: infoPlistDict
									 replacingTblkPath: replacingTblkPath
									cfBundleIdentifier: cfBundleIdentifier
									   cfBundleVersion: cfBundleVersion];
		if (  path  ) {
			return path;
		}
	}
	
    path = [self targetPathToReplaceForDisplayName: displayName
                                          inFolder: L_AS_T_SHARED
                                     infoPlistDict: infoPlistDict
                                 replacingTblkPath: replacingTblkPath
                                cfBundleIdentifier: cfBundleIdentifier
                                   cfBundleVersion: cfBundleVersion];
    if (  path  ) {
        return path;
    }
    
    path = [self targetPathToReplaceForDisplayName: displayName
                                          inFolder: gPrivatePath
                                     infoPlistDict: infoPlistDict
                                 replacingTblkPath: replacingTblkPath
                                cfBundleIdentifier: cfBundleIdentifier
                                   cfBundleVersion: cfBundleVersion];
    return path;
}

-(NSString *) targetPathForDisplayName: (NSString *)     displayName
                         infoPlistDict: (NSDictionary *) infoPlistDict
                     replacingTblkPath: (NSString *)     replacingTblkPath
							  fromPath: (NSString *)     replacementTblkPath {
    
    // Returns "skip" if user want to skip this one configuration
    // Returns "cancel" if user cancelled
    // Returns a string beginning with "/" containing the path to which the .tblk should be installed
    // Anything else that is returned is a localized error message
    //
    // Note: infoPlistDict can be nil
    
    // If the Info.plist for this .tblk has CFBundleIdentifier and CFBundleVersion entries
    //    then see if we should replace based on them
    NSString * cfBundleIdentifier = [infoPlistDict objectForKey: @"CFBundleIdentifier"];
    NSString * cfBundleVersion    = [infoPlistDict objectForKey: @"CFBundleVersion"];
    if (   cfBundleIdentifier
        && cfBundleVersion  ) {
        NSString * result = [self targetPathForDisplayName: displayName
                                             infoPlistDict: infoPlistDict
                                         replacingTblkPath: replacingTblkPath
                                        cfBundleIdentifier: cfBundleIdentifier
                                           cfBundleVersion: cfBundleVersion];
        if (  result  ) {
            return result;
        }
    }
    
    // Otherwise, see if we should replace based on the displayName
    NSString * nameWithTblkExtension = [displayName stringByAppendingPathExtension: @"tblk"];
    NSString * fileInSharedPath      = [L_AS_T_SHARED stringByAppendingPathComponent: nameWithTblkExtension];
    NSString * fileInPrivatePath     = [gPrivatePath  stringByAppendingPathComponent: nameWithTblkExtension];
    
    BOOL replaceShared  = [gFileMgr fileExistsAtPath: fileInSharedPath];
    BOOL replacePrivate = [gFileMgr fileExistsAtPath: fileInPrivatePath];
    
    if (   replacePrivate
        && ( ! [self installToPrivateOK])  ) {
        return NSLocalizedString(@"You are not allowed to replace a private configuration", @"Window text");
    }
    if (   replaceShared
        && ( ! [self installToSharedOK])  ) {
        return NSLocalizedString(@"You are not allowed to replace a shared configuration", @"Window text");
    }
    
    NSString * tbSharePackage     = [infoPlistDict objectForKey: @"TBSharePackage"];
    NSString * tbReplaceIdentical = [infoPlistDict objectForKey: @"TBReplaceIdentical"];
    
	NSString * localizedName = [gMC localizedNameforDisplayName: displayName tblkPath: replacementTblkPath];
	
    NSString * sharedOrPrivate;
    if (   replaceShared
        && replacePrivate  ) {
        if (   (   [tbSharePackage isEqualToString: @"shared"]
                || [tbSharePackage isEqualToString: @"private"] )
            && (  ! [tbReplaceIdentical isEqualToString: @"ask"] )
            ) {
            sharedOrPrivate = tbSharePackage;
        } else {
            sharedOrPrivate =  [self askSharedOrPrivateForConfig: localizedName];
        }
    } else  if (  replacePrivate  ) {
        if (  ! [tbReplaceIdentical isEqualToString: @"ask"]  ) {
            sharedOrPrivate = @"private";
        } else {
            sharedOrPrivate = [self confirmReplace: localizedName in: @"private"];
        }
    } else if (  replaceShared  ) {
        if (  ! [tbReplaceIdentical isEqualToString: @"ask"]  ) {
            sharedOrPrivate = @"shared";
        } else {
            sharedOrPrivate = [self confirmReplace: localizedName in: @"shared"];
        }
    } else {
		id obj = [infoPlistDict objectForKey: @"TBUninstall"];
		if (  obj  ) {
			return nil;	// Uninstalling but no such configuration
		}
        if (  [self installToPrivateOK]  ) {
            if (  [self installToSharedOK]  ) {
                if (   [tbSharePackage isEqualToString: @"private"]
                    || [tbSharePackage isEqualToString: @"shared"] ) {
                    sharedOrPrivate = tbSharePackage;
                } else {
                    sharedOrPrivate =  [self askSharedOrPrivateForConfig: localizedName];
                }
            } else {
                sharedOrPrivate = @"private";
            }
        } else {
            if (  [self installToSharedOK]  ) {
                sharedOrPrivate =  @"shared";
            } else {
                sharedOrPrivate =  NSLocalizedString(@"Cannot install configurations to either shared or private locations", @"Window text");
            }
        }
    }
    
    NSString * displayNameWithTblkExtension = [displayName stringByAppendingPathExtension: @"tblk"];
    NSString * targetPath = nil;
    if (  [sharedOrPrivate isEqualToString: @"private"]  ) {
        targetPath = [gPrivatePath  stringByAppendingPathComponent: displayNameWithTblkExtension];
    } else if (  [sharedOrPrivate isEqualToString: @"shared"]  ) {
        targetPath = [L_AS_T_SHARED stringByAppendingPathComponent: displayNameWithTblkExtension];
    } else {
        targetPath = sharedOrPrivate; // Error or user cancelled or said to skip
    }
    
    return targetPath;
}

-(NSString *) convertOvpnOrConfAtPath: (NSString *) path
                         toTblkAtPath: (NSString *) toPath
                    replacingTblkPath: (NSString *) replacingTblkPath
                          displayName: (NSString *) theDisplayName
				 nameForErrorMessages: (NSString *) nameForErrorMessages
                     useExistingFiles: (NSArray *)  useExistingFiles
							 fromTblk: (BOOL)       fromTblk {
    
    // Returns nil or a localized string with an error message or the conversion log
    
    NSString * result = [ConfigurationManager checkForSampleConfigurationAtPath: path];
    if (  result  ) {
        return result;
    }
    
    NSString * ext  = [path pathExtension];
    if (   [ext isEqualToString: @"ovpn"]
        || [ext isEqualToString: @"conf"]  ) {
        
        // Convert the .ovpn or .conf to a .tblk
        ConfigurationConverter * converter = [[ConfigurationConverter alloc] init];
        NSString * result2 = [converter convertConfigPath: path
                                               outputPath: toPath
                                        replacingTblkPath: replacingTblkPath
                                              displayName: theDisplayName
                                     nameForErrorMessages: nameForErrorMessages
                                         useExistingFiles: useExistingFiles
                                                  logFile: NULL
                                                 fromTblk: fromTblk];
        [converter release];
        
		return result2;
    } else {
        return [NSString stringWithFormat: NSLocalizedString(@"Not a .ovpn or .conf: %@", @"Window text"), path];
    }
}

-(NSString *) convertInnerTblkAtPath: (NSString *)     innerFilePath
                       outerTblkPath: (NSString *)     outerTblkPath
                  outerTblkInfoPlist: (NSDictionary *) outerTblkInfoPlist
                         displayName: (NSString *)     displayName
                 isInAnUpdatableTblk: (BOOL)           isInAnUpdatableTblk {
    
    // Converts a .tblk or .ovpn/.conf at outerTblkPath/innerFilePath to a .tblk
    //
    // Returns nil, "cancel" or "skip" to indicate the user cancelled or wants to skip this configuration, or a string with a localized error message.
    
    
    NSString * fullPath = [outerTblkPath stringByAppendingPathComponent: innerFilePath];
    
    NSDictionary * mergedInfoPlist = [NSDictionary dictionaryWithDictionary: outerTblkInfoPlist];
    NSString * configPath = [NSString stringWithString: fullPath];
    
    if (  [[fullPath pathExtension] isEqualToString: @"tblk" ]  ) {
        
        // Get the inner .tblk's .plist (if any)
        id obj = [ConfigurationManager plistOrErrorMessageInTblkAtPath: fullPath];
        if (  [[obj class] isSubclassOfClass: [NSString class]]  ) {
            return (NSString *) obj;
        }
        if (  isInAnUpdatableTblk  ) {
            if (  ! obj  ) {
                return [NSString stringWithFormat: NSLocalizedString(@"Missing Info.plist for\n\n%@\n\n"
                                                                     @"This VPN Configuration is enclosed in an updatable outer VPN Configuration, so it must include an Info.plist.", @"Window text"), fullPath];
            }
        }
        NSDictionary * innerTblkInfoPlist = (NSDictionary *)obj;
        
        // Create a merged .plist -- outer with entries replaced by inner
        if (  outerTblkInfoPlist  ) {
			NSArray * allowedInnerPlistReplacementKeys = [NSArray arrayWithObjects:
														  @"CFBundleIdentifier",
														  @"CFBundleVersion",
														  @"CFBundleShortVersionString",
														  @"TBMinimumTunnelblickVersion",
														  @"TBMaximumTunnelblickVersion",
                                                          @"TBPackageVersion",
                                                          @"TBReplaceIdentical",
                                                          @"TBSharePackage",
                                                          @"TBKeepExistingFilesList",
                                                          @"TBUninstall",
                                                          nil];
            
            NSString * innerBundleIdentifier = nil;
            NSString * innerBundleVersion    = nil;
			
            NSMutableDictionary * mDict = [[outerTblkInfoPlist mutableCopy] autorelease];
            NSEnumerator * e = [innerTblkInfoPlist keyEnumerator];
            NSString * key;
            while (  (key = [e nextObject])  ) {
				id obj2 = [innerTblkInfoPlist objectForKey: key];
                if (  [key isEqualToString: @"CFBundleIdentifier"]  ) {
                    innerBundleIdentifier = (NSString *)obj2;
					[mDict setObject: obj2 forKey: key];
                } else if (  [key isEqualToString: @"CFBundleVersion"]  ) {
                    innerBundleVersion    = (NSString *)obj2;
					[mDict setObject: obj2 forKey: key];
				} else if (  [key hasPrefix: @"SU"]  ) {
					return [NSString stringWithFormat: NSLocalizedString(@"\"%@\" in the Info.plist for\n\n%@\n\nis not allowed because the Info.plist for an \"inner\" .tblk may not contain \"updatable\" .tblk entries.", @"Window text"), key, fullPath];
				} else 	if (   [allowedInnerPlistReplacementKeys containsObject: key]
							|| [key hasPrefix: @"TBPreference"]
							|| [key hasPrefix: @"TBAlwaysSetPreference"]  ) {
					[mDict setObject: obj2 forKey: key];
				} else if (  [key isEqualToString: @"TBMinimumTunnelblickVersion"]  ) {
					[mDict setObject: obj2 forKey: key];
				} else if (  [key isEqualToString: @"TBMaximumTunnelblickVersion"]  ) {
					[mDict setObject: obj2 forKey: key];
				} else if (  ! [[mDict objectForKey: key] isEqualTo: obj2 ]) {
					return [NSString stringWithFormat: NSLocalizedString(@"\"%@\" in the Info.plist for\n\n%@\n\nis not allowed in an \"inner\" .tblk or conflicts with the same entry in an \"outer\" .tblk.", @"Window text"), key, fullPath];
				}
			}
            
            if ( isInAnUpdatableTblk  ) {
                if (  ! (   innerBundleIdentifier
                         && innerBundleVersion)  )  {
                    return [NSString stringWithFormat: NSLocalizedString(@"Missing CFBundleIdentifier or CFBundleVersion in Info.plist for\n\n%@\n\n"
                                                                         @"This VPN Configuration is enclosed in an updatable outer VPN Configuration, so it must include its own CFBundleIdentifier and CFBundleVersion.", @"Window text"), fullPath];
                }
            }
            
            mergedInfoPlist = [NSDictionary dictionaryWithDictionary: mDict];
        } else {
            mergedInfoPlist = innerTblkInfoPlist;
        }
        
		// Make sure this version of Tunnelblick is within any minimum or maximum required by the plist
		NSString * errorMessage = [ConfigurationManager checkTunnelblickVersionAgainstInfoPlist: mergedInfoPlist displayName: innerFilePath];
		if (  errorMessage  ) {
			return errorMessage;
		}
		
        // Get a relative path to the configuration file. If both a ".ovpn" and a ".conf" file exist, use the ".ovpn" file
        
        // (Put all the config files in a list, then look at the list)
        NSMutableArray * configFiles = [NSMutableArray arrayWithCapacity: 2];
        NSString * file;
        NSDirectoryEnumerator * innerEnum = [gFileMgr enumeratorAtPath: fullPath];
        while (  (file = [innerEnum nextObject])  ) {
            NSString * ext = [file pathExtension];
            if (   [ext isEqualToString: @"ovpn"]
                || [ext isEqualToString: @"conf"]
                ) {
                [configFiles addObject: file];
            } else if (  [ext isEqualToString: @"tblk"]  ) {
                return [NSString stringWithFormat: NSLocalizedString(@"A Tunnelblick VPN Configuration is nested too deeply in '%@'", @"Window text"), fullPath];
            }
        }
        
        NSString * configFile;
        if (  [configFiles count] == 0  ) {
            return [NSString stringWithFormat: NSLocalizedString(@"There is not an OpenVPN configuration file in '%@'", @"Window text"), fullPath];
        }
        if (  [configFiles count] == 1  ) {
            configFile = [configFiles objectAtIndex: 0];
            
        } else if (  [configFiles count] == 2  ) {
            NSString * first  = [configFiles objectAtIndex: 0];
            NSString * second = [configFiles objectAtIndex: 1];
            if (  [[first stringByDeletingPathExtension] isEqualToString: [second stringByDeletingPathExtension]]  ) {
                configFile = (  [[first pathExtension] isEqualToString: @"ovpn"]
                              ? first
                              : second);
            } else {
                return [NSString stringWithFormat: NSLocalizedString(@"Too many configuration files in '%@'", @"Window text"), fullPath];
            }
            
        } else {
            return [NSString stringWithFormat: NSLocalizedString(@"Too many configuration files in '%@'", @"Window text"), fullPath];
        }
        
        configPath = [fullPath stringByAppendingPathComponent: configFile];
    }
    
    // Do the conversion
    NSString * displayNameWithTblkExtension = [displayName stringByAppendingPathExtension: @"tblk"];
    NSString * outTblkPath = [[self tempDirPath] stringByAppendingPathComponent: displayNameWithTblkExtension];
    NSArray * useExistingFiles = [mergedInfoPlist objectForKey: @"TBKeepExistingFilesList"];
    
    NSString  * replacingTblkPath = [self pathOfTblkToReplaceWithBundleIdentifier: [mergedInfoPlist objectForKey: @"CFBundleIdentifier"]];
    
    // Warn if the configuration is connected and contains scripts. If the scripts are replaced with new ones, that could cause problems.
    if (  replacingTblkPath  ) {
        BOOL warnConfigurationIsConnected = FALSE;
        NSDictionary * configDict = [gMC myConfigDictionary];
        NSEnumerator * keyEnum = [configDict keyEnumerator];
        NSString * key;
        while (  (key = [keyEnum nextObject])  ) {
            if (  [key isEqualToString: replacingTblkPath]  ) {
                VPNConnection * connection = [configDict objectForKey: key];
                if (  ! [connection isDisconnected]  ) {
                    
                    NSString * file;
                    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: replacingTblkPath];
                    while (  (file = [dirEnum nextObject])  ) {
                        if (  [file hasSuffix: @".sh"]) {
                            warnConfigurationIsConnected = TRUE;
                            break;
                        }
                    }
                }
                
                break;
            }
        }
        
        if (  warnConfigurationIsConnected  ) {
            NSString * localName = [gMC localizedNameforDisplayName: displayName tblkPath: replacingTblkPath];
            int result = TBRunAlertPanel(NSLocalizedString(@"VPN Configuration Installation", @"Window title"),
                                         [NSString stringWithFormat:
                                          NSLocalizedString(@"Configuration '%@' contains one or more scripts which may cause problems if you replace or uninstall the configuration while it is connected.\n\n"
                                                            @"Do you wish to replace the configuration?",
                                                            @"Window text"),
                                          localName],
                                         NSLocalizedString(@"Replace", @"Button"),   // Default button
                                         NSLocalizedString(@"Cancel",  @"Button"),   // Alternate button
                                         nil);                                       // Other button
            if (  result == NSAlertAlternateReturn  ) {
				return @"cancel";
            }
        }
    }
    
    NSString * result = [self convertOvpnOrConfAtPath: configPath
                                         toTblkAtPath: outTblkPath
                                    replacingTblkPath: replacingTblkPath
                                          displayName: displayName
								 nameForErrorMessages: (  [self multipleConfigurations]
                                                        ? displayName
                                                        : nil)
                                     useExistingFiles: useExistingFiles
											 fromTblk: YES];
    if (  result  ) {
        return result;
    }
    
    NSString * targetPath = [self targetPathForDisplayName: displayName
                                             infoPlistDict: mergedInfoPlist
                                         replacingTblkPath: replacingTblkPath
												  fromPath: fullPath];
	
	BOOL uninstall = (  [mergedInfoPlist objectForKey: @"TBUninstall"]
					  ? TRUE
					  : FALSE);
    if (  targetPath  ) {
        if (  [targetPath hasPrefix: @"/"]  ) {
            // It is a path
			if (  uninstall  ) {
				[[self deletions] addObject: targetPath];
			} else {
				if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
					[[self replaceSources] addObject: outTblkPath];
					[[self replaceTargets] addObject: targetPath];
				} else {
					[[self installSources] addObject: outTblkPath];
					[[self installTargets] addObject: targetPath];
				}
			}
			
        } else {
            return  targetPath; // Error or user cancelled or said to skip this one
        }
	} else {
		if (  uninstall  ) {
            NSString * localName = [gMC localizedNameforDisplayName: displayName tblkPath: fullPath];
			return [NSString stringWithFormat: NSLocalizedString(@"Cannot uninstall configuration '%@' because it is not installed.", @"Window text"), localName];
		}
    }
    
    return nil;
}

-(id) updatablePlistIn: (NSString *) path {
	
	// Returns nil or, if the .tblk at path is updatable, its .plist, or if there is an error in the .plist, a string with the localized error message
	
	id obj = [ConfigurationManager plistOrErrorMessageInTblkAtPath: path];
	
	// Not updatable if no .plist
	if (  ! obj  ) {
		return nil;
	}
	
	// Not updatable if .plist contains errors
	if (  ! [[obj class] isSubclassOfClass: [NSDictionary class]]  ) {
		return obj;
	}
	
	NSDictionary * plist = (NSDictionary *)obj;
	
	// Not updatable if doesn't have CFBundleIdentifier, CFBundleVersion, and SUFeedURL
    if (  ! (   [plist objectForKey: @"CFBundleIdentifier"]
             && [plist objectForKey: @"CFBundleVersion"]
             && [plist objectForKey: @"SUFeedURL"]
             )  ) {
        return nil;
    }
    
	// It is updatable; return its .plist
	return plist;
}

-(NSString *) convertOuterTblk: (NSString *) outerTblkPath
			   haveOvpnOrConfs: (BOOL)       haveOvpnOrConfs {
    
    // Returns nil, or "cancel" if the user cancelled, or a string with a localized error message.
    
    // A .tblk (or a subfolder within it) can have both a .conf and a .ovpn file, in which case we ignore the .conf and only process the .ovpn
    // We do that by building a list of all of the .conf and .ovpn files as we iterate through the outer .tblk's directory structure
    // Then, after we've finished that, we create a new list without any .conf files that have corresponding .ovpn files.
    // Finally, we iterate over that array processing the .tblk, .ovpn, and .conf files.
    
	
	BOOL thisIsTheLastTblk = [self inhibitCheckbox];  // This outer .tblk is the last .tblk in the tblkPaths array
	
    // Get, and check, the .plist for this outer .tblk if there is one
    id obj = [ConfigurationManager plistOrErrorMessageInTblkAtPath: outerTblkPath];
    if (  [[obj class] isSubclassOfClass: [NSString class]]  ) {
        return (NSString *) obj;
    }
    NSDictionary * outerTblkPlist = (NSDictionary *)obj;
    
	obj = [self updatablePlistIn: outerTblkPath];
	if (  obj  ) {
		if (  ! [[obj class] isSubclassOfClass: [NSDictionary class]]  ) {
			return (NSString *)obj; // An error message
		}
    }
	NSDictionary * outerUpdatablePlist = (NSDictionary *)obj;
		
	// Make sure this version of Tunnelblick is within any minimum or maximum required by the configuration's .plist
	NSString * errorMessage = [ConfigurationManager checkTunnelblickVersionAgainstInfoPlist: outerTblkPlist displayName: [outerTblkPath lastPathComponent]];
	if (  errorMessage  ) {
		return errorMessage;
	}
	
	// Build lists of .tblks and of .ovpn/.conf files
    NSMutableArray * ovpnAndConfInnerFilePartialPaths = [NSMutableArray arrayWithCapacity: 100];
    NSMutableArray * tblkInnerFilePartialPaths        = [NSMutableArray arrayWithCapacity: 100];
    
    NSString * innerFilePartialPath;
    NSDirectoryEnumerator * outerEnum = [gFileMgr enumeratorAtPath: outerTblkPath];
    while (  (innerFilePartialPath = [outerEnum nextObject])  ) {
        NSString * ext = [innerFilePartialPath pathExtension];
        if (  [ext isEqualToString: @"tblk"]  ) {
            [outerEnum skipDescendents]; // Don't look inside the .tblk
            [tblkInnerFilePartialPaths addObject: innerFilePartialPath];
            
        } else if (   [ext isEqualToString: @"ovpn"]
                   || [ext isEqualToString: @"conf"]  ) {
			// If already have a .ovpn, ignore a .conf.
			// If already have a .conf, replace it with the .conf
			// If don't have either, add this one
			NSString * oppositeWithExtension = (  [ext isEqualToString: @"ovpn"]
												? [[innerFilePartialPath stringByDeletingPathExtension] stringByAppendingPathExtension: @"conf"]
												: [[innerFilePartialPath stringByDeletingPathExtension] stringByAppendingPathExtension: @"ovpn"]);
			if (  [ovpnAndConfInnerFilePartialPaths containsObject: oppositeWithExtension]  ) {
				if (  [ext isEqualToString: @"ovpn"]  ) {
					[ovpnAndConfInnerFilePartialPaths removeObject: oppositeWithExtension];
					[ovpnAndConfInnerFilePartialPaths addObject: innerFilePartialPath];
				}
			} else {
				[ovpnAndConfInnerFilePartialPaths addObject: innerFilePartialPath];
			}
        }
    }
    
    // Remove .conf files from the list if the corresponding .ovpn file is on the list
    NSEnumerator * e = [ovpnAndConfInnerFilePartialPaths objectEnumerator];
    while (  (innerFilePartialPath = [e nextObject])  ) {
        NSString * withoutExt = [innerFilePartialPath stringByDeletingPathExtension];
        NSString * ovpnFilePath = [withoutExt stringByAppendingPathExtension: @"ovpn"];
        NSString * confFilePath = [withoutExt stringByAppendingPathExtension: @"conf"];
        if (   [ovpnAndConfInnerFilePartialPaths containsObject: ovpnFilePath]
            && [ovpnAndConfInnerFilePartialPaths containsObject: confFilePath]  ) {
            [ovpnAndConfInnerFilePartialPaths removeObject: confFilePath];
        }
    }
    
    // Complain if nothing to convert
	if (   ([tblkInnerFilePartialPaths       count] == 0)
		&& ([ovpnAndConfInnerFilePartialPaths count] == 0)  ) {
		if (  [self multipleConfigurations]  ) {
			return [NSString stringWithFormat: NSLocalizedString(@"In %@:\n\nThere are no OpenVPN configurations to install.", @"Window text"), outerTblkPath];
		} else {
			return NSLocalizedString(@"There are no OpenVPN configurations to install.", @"Window text");
		}
	}
	
    // Convert .ovpn/.conf files
    NSUInteger ix;
    for (  ix=0; ix<[ovpnAndConfInnerFilePartialPaths count]; ix++  ) {
        
        [self setInhibitCheckbox: (   thisIsTheLastTblk
								   && ( ! haveOvpnOrConfs)
                                   && ( ix == [ovpnAndConfInnerFilePartialPaths count] - 1)
								   && ( [tblkInnerFilePartialPaths count] == 0)   )];
		
        NSString * configPartialPath = [ovpnAndConfInnerFilePartialPaths objectAtIndex: ix];
        
		NSString * result =[self convertInnerTblkAtPath: configPartialPath
										  outerTblkPath: outerTblkPath
									 outerTblkInfoPlist: outerTblkPlist
                                            displayName: (  ([ovpnAndConfInnerFilePartialPaths count] > 1)
                                                          ? [configPartialPath stringByDeletingPathExtension]
                                                          : [[outerTblkPath lastPathComponent] stringByDeletingPathExtension])
                                    isInAnUpdatableTblk: (outerUpdatablePlist != nil)];
        if (   result  ) {
            if (  [result isEqualToString: @"skip"]  ) {
                return nil;
            }
            return result;
        }
    }
    
	// Convert .tblks
    for (  ix=0; ix<[tblkInnerFilePartialPaths count]; ix++  ) {
        
        [self setInhibitCheckbox: (   thisIsTheLastTblk
								   && ( ! haveOvpnOrConfs)
								   && (ix == [tblkInnerFilePartialPaths count] - 1)  )];
		
        innerFilePartialPath   = [tblkInnerFilePartialPaths objectAtIndex: ix];
        NSString * displayName = [innerFilePartialPath stringByDeletingPathExtension];
		if (  [displayName hasPrefix: @"Contents/Resources"]  ) {
			displayName = [displayName substringFromIndex: [@"Contents/Resources" length]];
		}
        
        NSString * result = [self convertInnerTblkAtPath: innerFilePartialPath
                                           outerTblkPath: outerTblkPath
                                      outerTblkInfoPlist: outerTblkPlist
                                             displayName: displayName
                                     isInAnUpdatableTblk: (outerUpdatablePlist != nil)];
        if (   result  ) {
            if (  [result isEqualToString: @"skip"]  ) {
                continue;
            }
            return result;
        }
    }
	
	// If this outer .tblk is an updatable .tblk, create a "stub" .tblk and add it to 'updateSources' and 'updateTargets'
    if (  outerUpdatablePlist  ) {
		// Create a stub .tblk in the temporary folder's "Updatables" subfolder.
		// A stub consists of an Info.plist file and a "uninstalled" file inside a "Contents" folder inside a .tblk.
        // A "Resources" folder inside the "Contents" folder may contain a DSA key file if there is one.
        
        // Get the path at which to create the stub .tblk.
		NSString * cfBI = [outerUpdatablePlist objectForKey: @"CFBundleIdentifier"];
		NSString * tblkName = [cfBI stringByAppendingPathExtension: @"tblk"];
		NSString * tblkStubPath = [[[self tempDirPath] stringByAppendingPathComponent: @"Updatables"]
								   stringByAppendingPathComponent: tblkName];
        
        // Make sure we haven't processed a configuration with that CFBundleIdentifier already
		if (  [gFileMgr fileExistsAtPath: tblkStubPath]  ) {
            return [NSString stringWithFormat: NSLocalizedString(@"Updatable configuration '%@' was not stored as updatable because that CFBundleIdentifier has already been processed\n", @"Window text"), cfBI];
		}
		
        // Create the Contents directory
		NSString * contentsPath = [tblkStubPath stringByAppendingPathComponent: @"Contents"];
		if (  createDir(contentsPath, PERMS_SECURED_FOLDER) == -1 ) {
            return [NSString stringWithFormat: NSLocalizedString(@"Updatable configuration '%@' was not stored as updatable because 'Contents' in the stub .tblk could not be created\n", @"Window text"), cfBI];
		}
		
        // Copy the Info.plist into the Contents directory and set its permissions
		NSString * plistPath = [contentsPath stringByAppendingPathComponent: @"Info.plist"];
		if (  ! [outerUpdatablePlist writeToFile: plistPath atomically: YES]  ) {
            return [NSString stringWithFormat: NSLocalizedString(@"Updatable configuration '%@' was not stored as updatable because its Info.plist could not be stored in the stub .tblk\n", @"Window text"), cfBI];
		}
        NSDictionary * attributes = [NSDictionary dictionaryWithObject: [NSNumber numberWithInt: PERMS_SECURED_READABLE] forKey: NSFilePosixPermissions];
		if (  ! [gFileMgr tbChangeFileAttributes: attributes atPath: plistPath]  ) {
            return [NSString stringWithFormat: NSLocalizedString(@"Failed to set permissions on %@\n", @"Window text"), plistPath];
        }
		
		// Create the "uninstalled" file in the Contents directory
		NSString * uninstalledFilePath = [contentsPath stringByAppendingPathComponent: @"installed"];
		if (  ! [gFileMgr createFileAtPath: uninstalledFilePath contents: [NSData data] attributes: attributes]  ) {
            return [NSString stringWithFormat: NSLocalizedString(@"Configuration '%@' is not updatable because it could not be marked as 'updatable'.\n", @"Window text"), cfBI];
		}
		
        // Make sure that the update will be done via https: and that it will be digitally signed
		id obj3 = [outerUpdatablePlist objectForKey: @"SUFeedURL"];
		BOOL doesNotUseHttps = (  ! (   [[obj3 class] isSubclassOfClass: [NSString class]]
									 && [(NSString *)obj3 hasPrefix: @"https://"]  )  );
		BOOL willNotBeSigned = ! [outerUpdatablePlist objectForKey: @"SUPublicDSAKey"];
		if (   doesNotUseHttps
			|| willNotBeSigned  ) {
			return [NSString stringWithFormat: NSLocalizedString(@"Updatable configuration '%@' was not stored as updatable because the Info.plist did not have an 'SUPublicDSAKey' entry or its 'SUFeedURL' entry did not specify the use of https:\n", @"Window text"), cfBI];
        }

		NSString * targetPath = [[L_AS_T_TBLKS stringByAppendingPathComponent: cfBI]
                                 stringByAppendingPathComponent: [outerTblkPath lastPathComponent]];
		[[self updateSources] addObject: tblkStubPath];
		[[self updateTargets] addObject: targetPath];
	}
    
    return nil;
}

-(NSString *) setupToInstallTblks: (NSArray *)  tblkPaths
				  haveOvpnOrConfs: (BOOL)       haveOvpnOrConfs {
    
    // Converts non-normalized .tblks to normalized .tblks (with Contents/Resources) in the temporary folder at tempDirPath
    // Adds paths of .tblks that are to be UNinstalled to the 'deletions' array
    // Adds paths of .tblks that are to be installed to the 'installSources', 'replaceSources', or 'noAdminSources' arrays and
    // targets (in private or shared) to the 'installTargets', 'replaceTargets', or 'noAdminTargets' arrays
    //
    // Returns nil      if converted with no problem
    // Returns "cancel" if the user cancelled
    // Returns "skip"   if the user skipped the last configuration
    // Otherwise returns a string with a localized error message
    
    NSUInteger ix;
    for (  ix=0; ix<[tblkPaths count]; ix++  ) {
        
        // If there are no more configurations to set up, don't show the 'Apply to all' checkbox
        [self setInhibitCheckbox: (ix == [tblkPaths count] - 1)];
        
        NSString * path = [tblkPaths objectAtIndex: ix];
        
        NSString * result = [self convertOuterTblk: path haveOvpnOrConfs: haveOvpnOrConfs];
        if (   result
            && [result isNotEqualTo: @"skip"]  ) {
			return result;
        }
    }
    
    return nil;
}

-(NSString *) setupToInstallOvpnsAndConfs: (NSArray *)  ovpnPaths {
    
    // Converts .ovpns and/or .confs to normalized .tblks (with Contents/Resources) in the temporary folder at tempDirPath
    // Adds paths of .tblks that are to be installed to the 'installSources', 'replaceSources', or 'noAdminSources' arrays and
    // targets (in private or shared) to the 'installTargets', 'replaceTargets', or 'noAdminTargets' arrays
    //
    // Returns nil      if converted with no problem
    // Returns "cancel" if the user cancelled
    // Returns "skip"   if the user skipped the last configuration
    // Otherwise returns a string with a localized error message
    
    NSUInteger ix;
    for (  ix=0; ix<[ovpnPaths count]; ix++  ) {
        
        // If there are no more configurations to set up, don't show the 'Apply to all' checkbox
        [self setInhibitCheckbox: (ix == [ovpnPaths count] - 1)];
        
        NSString * path = [ovpnPaths objectAtIndex: ix];
		NSString * fileName = [path lastPathComponent];
		NSString * displayName = [fileName stringByDeletingPathExtension];
		NSString * displayNameWithTblkExtension = [displayName stringByAppendingPathExtension: @"tblk"];
		NSString * outTblkPath = [[self tempDirPath] stringByAppendingPathComponent: displayNameWithTblkExtension];
		
		// Do the conversion
        NSString * result = [self convertOvpnOrConfAtPath: path
                                             toTblkAtPath: outTblkPath
                                        replacingTblkPath: nil
                                              displayName: nil
                                     nameForErrorMessages: (  [self multipleConfigurations]
                                                            ? displayName
                                                            : nil)
                                         useExistingFiles: nil
                                                 fromTblk: NO];
        
        if (  result  ) {
			return result;
        }
		
        NSString * targetPath = [self targetPathForDisplayName: displayName
                                                 infoPlistDict: nil
                                             replacingTblkPath: nil
													  fromPath: outTblkPath];
        if (  targetPath  ) {
            if (  [targetPath hasPrefix: @"/"]  ) {
                // It is a path
				if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
					[[self replaceSources] addObject: outTblkPath];
					[[self replaceTargets] addObject: targetPath];
				} else {
					[[self installSources] addObject: outTblkPath];
					[[self installTargets] addObject: targetPath];
				}
            } else if (  [targetPath isNotEqualTo: @"skip"]  ) {
                return targetPath; // Error or user cancelled
            }
        }
    }
    
 	return nil;
}

-(BOOL) checkFilesAreReasonable: (NSArray *) paths {
    
    NSString * tooBigMsg = nil;
    NSString * path;
    NSEnumerator * e = [paths objectEnumerator];
    while (  (path = [e nextObject])  ) {
		tooBigMsg = allFilesAreReasonableIn(path);
        if (  tooBigMsg  ) {
			break;
        }
    }
    if (  tooBigMsg  ) {
        TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation Error", @"Window title"),
                          [NSString stringWithFormat:
						   NSLocalizedString(@"There was a problem:\n\n"
										     @"%@", "Window text"),
						   tooBigMsg]);
        return FALSE;
    }
    
    return TRUE;
}

-(void) cleanupInstallAndNotifyDelegate: (BOOL)                       notifyDelegate
                    delegateNotifyValue: (NSApplicationDelegateReply) delegateNotifyValue {
    
    NSString * path = [self tempDirPath];
	if (  [gFileMgr fileExistsAtPath: path]  ) {
		if (  ! [gFileMgr tbRemoveFileAtPath: path handler: nil]  ) {
			NSLog(@"Unable to delete directory %@", path);
		}
	}
    
    if (  notifyDelegate  ) {
        [gMC replyToOpenOrPrint: [NSNumber numberWithInt: delegateNotifyValue]];
    }
}

+(BOOL) copyConfigPath: (NSString *)   sourcePath
                toPath: (NSString *)   targetPath
       usingSystemAuth: (SystemAuth *) auth
            warnDialog: (BOOL)         warn
           moveNotCopy: (BOOL)         moveInstead
               noAdmin: (BOOL)         noAdmin {
    
    // Copies or moves a config file or package and sets ownership and permissions on the target
    // Returns TRUE if succeeded in the copy or move -- EVEN IF THE CONFIG WAS NOT SECURED (an error message was output to the console log).
    // Returns FALSE if failed or cancelled by the user, having already output an error message to the console log
    //
    // If "noAdmin" is TRUE, "moveInstead" is FALSE, it is a private config, and safeUpdate is allowed, uses "openvpnstart safeUpdate" to
    //    update only keys and certificates in the configuration
    // Otherwise, installer is used to replace the configuration.
    
    if (  [sourcePath isEqualToString: targetPath]  ) {
        NSLog(@"You cannot copy or move a configuration to itself. Trying to do that with %@", sourcePath);
        return FALSE;
    }
    
	NSString * errMsg = allFilesAreReasonableIn(sourcePath);
	if (  errMsg  ) {
		NSLog(@"%@", errMsg);
		return FALSE;
	}
    
    NSString * displayName = [lastPartOfPath(targetPath) stringByDeletingPathExtension];
	
    if (   noAdmin
        && ( ! moveInstead)
        && okToUpdateConfigurationsWithoutAdminApproval()
        && [targetPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {

        BOOL privateTargetExists = [gFileMgr fileExistsAtPath: targetPath];

        // Back up the user's private copy of the configuration if it exists
        NSString * backupOfTargetPath  = [targetPath stringByAppendingPathExtension: @"backup"];
        if (  privateTargetExists  ) {
            if (  ! [gFileMgr tbForceRenamePath: targetPath toPath: backupOfTargetPath]  ) {
                return FALSE;
            }
        }

        // Copy the replacement to the private copy for the safeUpdate
        if (  ! [gFileMgr tbCopyPath: sourcePath toPath: targetPath handler: nil]  ) {
            // Restore old private copy if there was one, or delete the one we created
           if (  privateTargetExists  ) {
                [gFileMgr tbForceRenamePath: backupOfTargetPath toPath: sourcePath];
            } else {
                [gFileMgr tbRemovePathIfItExists: targetPath];
            }
            return FALSE;
        }

       // Do the safeUpdate
        NSArray * arguments = [NSArray arrayWithObjects:
                               @"safeUpdate",
                               displayNameFromPath(targetPath),
                               nil];
        OSStatus status = runOpenvpnstart(arguments, nil, nil);
        if (  status == OPENVPNSTART_UPDATE_SAFE_OK  ) {
            // safeUpdate was done so don't need to inform user if can't remove .old file (that will be logged)
            [gFileMgr tbRemovePathIfItExists: backupOfTargetPath];
            return TRUE;
        }

        // Couldn't do safeUpdate, so restore old private copy if there was one, or delete the one we created
        if (  privateTargetExists  ) {
            [gFileMgr tbForceRenamePath: backupOfTargetPath toPath: sourcePath];
        } else {
            [gFileMgr tbRemovePathIfItExists: targetPath];
        }

        NSLog(@"Could not do 'safeUpdate' of configuration file %@ to %@", sourcePath, targetPath);
        if (  warn  ) {
			NSString * localName = [gMC localizedNameForDisplayName: displayName];
            NSString * title = NSLocalizedString(@"Could Not Replace Configuration", @"Window title");
            NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not replace the '%@' configuration. See the Console Log for details.", @"Window text"), localName];
            TBShowAlertWindow(title, msg);
        }
        
        return FALSE;
    }
    
    if (  noAdmin  ) {
        NSLog(@"Could not do a safeUpdate; will try a normal from %@ to %@", sourcePath, targetPath);
    }
    
    unsigned firstArg = (moveInstead
                         ? INSTALLER_MOVE
                         : INSTALLER_COPY);
    NSArray * arguments = [NSArray arrayWithObjects: targetPath, sourcePath, nil];
    
    NSInteger installerResult = [gMC runInstaller: firstArg
                                                                    extraArguments: arguments
                                                                   usingSystemAuth: auth
                                                                      installTblks: nil];
	if (  installerResult == 0  ) {
        return TRUE;
    }
	
	if (  installerResult == 1  ) {
		return FALSE;
	}
    
    if (  ! moveInstead  ) {
        NSLog(@"Could not copy configuration file %@ to %@", sourcePath, targetPath);
        if (  warn  ) {
			NSString * localName = [gMC localizedNameForDisplayName: displayName];
            NSString * title = NSLocalizedString(@"Could Not Copy Configuration", @"Window title");
            NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not copy the '%@' configuration. See the Console Log for details.", @"Window text"), localName];
            TBShowAlertWindow(title, msg);
        }
        
        return FALSE;
        
    } else {
        NSLog(@"Could not move configuration file %@ to %@", sourcePath, targetPath);
        if (  warn  ) {
			NSString * localName = [gMC localizedNameForDisplayName: displayName];
            NSString * title = NSLocalizedString(@"Could Not Move Configuration", @"Window title");
            NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not move the '%@' configuration. See the Console Log for details.", @"Window text"), localName];
            TBShowAlertWindow(title, msg);
        }
        
        return FALSE;
    }
}

-(NSArray *) connectedConfigurationDisplayNames {
    
    // Returns an array with display names of .tblk replacements, updates, or deletions that are currently connected, or nil on error
    
    NSMutableArray * list = [[[NSMutableArray alloc] init] autorelease];
    
    NSArray * targetList = [NSArray arrayWithObjects: [self replaceTargets], [self updateTargets], [self deletions], nil];
    NSArray * currentList;
    NSEnumerator * listE = [targetList objectEnumerator];
    while (  (currentList = [listE nextObject])  ) {
        NSString * path;
        NSEnumerator * e = [currentList objectEnumerator];
        while (  (path = [e nextObject])  ) {
            NSDictionary * configDict = [gMC myConfigDictionary];
            NSArray * names = [configDict allKeysForObject: path];
            if (  [names count] != 1  ) {
                return [NSArray array];
            }
            VPNConnection * connection = [gMC connectionForDisplayName:  [names objectAtIndex: 0]];
            if (  ! [[connection state] isEqualToString: @"EXITING"]  ) {
                [list addObject: [names objectAtIndex: 0]];
            }
        }
    }
    
    return [NSArray arrayWithArray: list];
}

-(void) disconnect: (NSArray *) displayNames {
    
    // Disconnect configurations that are to be installed/uninstalled/replaced
    
    NSString * name;
    NSEnumerator * e = [displayNames objectEnumerator];
    while (  (name = [e nextObject])  ) {
        NSDictionary * dict = [gMC myVPNConnectionDictionary];
        VPNConnection * connection = [dict objectForKey: name];
        if (  connection  ) {
            if (  ! [[connection state] isEqualToString: @"EXITING"]  ) {
                NSLog(@"Starting disconnection of '%@'", [connection displayName]);
                [connection startDisconnectingUserKnows: @YES];
            }
        } else {
            NSLog(@"No entry for '%@' in myVPNConnectionDictionary = '%@'", [connection displayName], dict);
        }
    }
    
    // Wait for the VPN to be completely disconnected
    e = [displayNames objectEnumerator];
    while (  (name = [e nextObject])  ) {
        VPNConnection * connection = [gMC connectionForDisplayName: name];
        [connection waitUntilCompletelyDisconnected];
     }
}

-(void) reconnect: (NSArray *) displayNames {
    
    // Reconnect configurations that were disconnected because of install/uninstall/replace
    
    NSString * name;
    NSEnumerator * e = [displayNames objectEnumerator];
    while (  (name = [e nextObject])  ) {
        VPNConnection * connection = [gMC connectionForDisplayName: name];
        if (  connection  ) {
            NSLog(@"Starting reconnection of '%@'", name);
            [connection performSelector: @selector(connectOnMainThreadUserKnows:) withObject: @YES afterDelay: 1.0];
        } else {
            NSLog(@"Skipping reconnection of '%@' because it has been uninstalled", name);
        }
    }
}

-(void) setupNonAdminReplacementsFromSources: (NSMutableArray * ) sources targets: (NSMutableArray *) targets {

    // "sources" contains paths to the new configurations
    // "targets" contains paths to the existing configuration or to where the configuration should be installed
    
    // Only do this is if it is allowed by a forced preference
    if (  ! okToUpdateConfigurationsWithoutAdminApproval()  ) {
        return;
    }

    // Move objects to noAdminSources and noAdminTargets if they can be installed or replaced without admin authorization
    NSUInteger ix;
    for (  ix=0; ix<[sources count]; ix++  ) {
        NSString * sourcePath   = [sources objectAtIndex: ix];
        NSString * targetPath   = [targets objectAtIndex: ix];

        // Only do this for private configs
        if (  ! [targetPath hasPrefix: [gPrivatePath stringByAppendingPathComponent: @"/"]]  ) {
            continue;
        }

        // Rename the private config, replace it with the new config, see if a safeUpdate will work, then restore the original private config
        BOOL targetExisted = [gFileMgr fileExistsAtPath: targetPath];
        NSString * targetBackup = [targetPath stringByAppendingPathExtension: @"old"];
        if (  targetExisted  ) {
            if (  ! [gFileMgr tbForceRenamePath: targetPath toPath: targetBackup]  ) {
                continue;
            }
        }

        if (  ! [gFileMgr tbCopyPath: sourcePath toPath: targetPath handler: nil]  ) {
            if (  targetExisted  ) {
                [gFileMgr tbForceRenamePath: targetBackup toPath: targetPath];
            }
            continue;
        }

        NSString * displayName = [lastPartOfPath(targetPath) stringByDeletingPathExtension];
        NSArray * arguments = [NSArray arrayWithObjects:
                               @"safeUpdateTest",
                               displayName,
                               nil];
        OSStatus status = runOpenvpnstart(arguments, nil, nil);
        if (  status == OPENVPNSTART_UPDATE_SAFE_OK  ) {
            [noAdminSources addObject: sourcePath];
            [noAdminTargets addObject: targetPath];
            [sources removeObject: sourcePath];
            [targets removeObject: targetPath];
        }

        if (  targetExisted  ) {
            if (  [gFileMgr fileExistsAtPath: targetBackup]  ) {
                [gFileMgr tbForceRenamePath: targetBackup toPath: targetPath];
            }
        } else {
            [gFileMgr tbRemovePathIfItExists: targetPath];
        }
    }
}

-(void) setupNonAdminReplacements {

    // Moves paths from installSources/Targets and replaceSources/Targets to noAdminSources/Targets if they can use non-admin-authorized safeUpdate
    
    // Only do this is if it is allowed by a forced preference
    if (  okToUpdateConfigurationsWithoutAdminApproval()  ) {
        [self setupNonAdminReplacementsFromSources: replaceSources targets: replaceTargets];
        [self setupNonAdminReplacementsFromSources: installSources targets: installTargets];
    }
}

-(NSApplicationDelegateReply) doUninstallslReplacementsInstallsSkipConfirmMsg: (BOOL) skipConfirmMsg
																skipResultMsg: (BOOL) skipResultMsg {
    
	// Does the work to uninstall, replace, and/or install configurations from the 'deletions', 'installSource', 'replaceSource', etc. arrays
	//
	// Returns the value that the delegate should use as an argument to '[NSApp replyToOpenOrPrint:]' (whether or not it will be needed)
	
    [self setupNonAdminReplacements];
    
    NSUInteger nToUninstall = [[self deletions]      count];
    NSUInteger nToInstall   = [[self installSources] count];
    NSUInteger nToReplace   = [[self replaceSources] count];
    NSUInteger nSafe        = [[self noAdminSources] count];
    
    NSArray * connectedTargetDisplayNames = [self connectedConfigurationDisplayNames];
    
    // If there's nothing to do, just return as if the user cancelled
	if (  (nToUninstall + nToInstall + nToReplace + nSafe) == 0  ) {
		return NSApplicationDelegateReplyCancel;
	}
    
    NSString * uninstallMsg = (  (nToUninstall == 0)
                               ? @""
                               : (  (nToUninstall == 1)
                                  ? NSLocalizedString(@"    • Uninstall one configuration\n", @"Window text: 'Tunnelblick needs to: *'")
                                  : [NSString stringWithFormat: NSLocalizedString(@"    • Uninstall %lu configurations\n\n", @"Window text: 'Tunnelblick needs to: *'"), (unsigned long)nToUninstall]));
    NSString * replaceMsg   = (  (nToReplace == 0)
                               ? @""
                               : (  (nToReplace == 1)
                                  ? NSLocalizedString(@"    • Replace one configuration\n", @"Window text: 'Tunnelblick needs to: *'")
                                  : [NSString stringWithFormat: NSLocalizedString(@"    • Replace %lu configurations\n\n", @"Window text: 'Tunnelblick needs to: *'"), (unsigned long)nToReplace]));
    NSString * safeMsg     = (  (nSafe == 0)
                               ? @""
                               : (  (nSafe == 1)
                                  ? NSLocalizedString(@"    • Install or replace one \"safe\" configuration (administrator authorization not required)\n", @"Window text: 'Tunnelblick needs to: *'")
                                  : [NSString stringWithFormat: NSLocalizedString(@"    • Install or replace %lu \"safe\" configurations (administrator authorization not required)\n\n", @"Window text: 'Tunnelblick needs to: *'"), (unsigned long)nSafe]));
    NSString * installMsg   = (  (nToInstall == 0)
                               ? @""
                               : (  (nToInstall == 1)
                                  ? NSLocalizedString(@"    • Install one configuration\n", @"Window text: 'Tunnelblick needs to: *'")
                                  : [NSString stringWithFormat: NSLocalizedString(@"    • Install %lu configurations\n\n", @"Window text: 'Tunnelblick needs to: *'"), (unsigned long)nToInstall]));
    NSString * disconnectMsg = (  ([connectedTargetDisplayNames count] == 0)
                                ? @""
                                :  NSLocalizedString(@"\n\nNOTE: One or more of the configurations are currently connected. They will be disconnected, installs/replacements/uninstalls will be performed, and the configurations will be reconnected unless they have been uninstalled.\n\n", @"Window text"));
    
    NSString * authMsg = [NSString stringWithFormat: @"%@\n%@%@%@%@%@", NSLocalizedString(@"Tunnelblick needs to:\n", @"Window text"), uninstallMsg, replaceMsg, installMsg, safeMsg, disconnectMsg];
    
    // Get a SystemAuth WITH A RETAIN COUNT OF 1, from MenuController's startupInstallAuth, the lock, or from a user interaction
    SystemAuth * auth = [[gMC startupInstallAuth] retain];
 	if (   ( (nToUninstall + nToInstall + nToReplace) != 0)
        && ( ! auth )  ) {
        auth = [SystemAuth newAuthWithPrompt: authMsg];
        if (   ! auth  ) {
			return NSApplicationDelegateReplyCancel;
        }
	} else {
        
        if (  ! skipConfirmMsg  ) {
            int result = TBRunAlertPanel(NSLocalizedString(@"VPN Configuration Installation", @"Window title"),
                                         authMsg,
                                         NSLocalizedString(@"OK",      @"Button"),   // Default button
                                         NSLocalizedString(@"Cancel",  @"Button"),   // Alternate button
                                         nil);                                       // Other button
            if (  result == NSAlertAlternateReturn  ) {
				[auth release];
				return NSApplicationDelegateReplyCancel;
            }
        }
    }
    
    // Disconnect any configurations that are being replaced or uninstalled
    [self disconnect: connectedTargetDisplayNames];
    
    // Do the actual installs and uninstalls
    
    NSUInteger nUninstallErrors = 0;
    NSUInteger nInstallErrors   = 0;
	NSUInteger nReplaceErrors   = 0;
    NSUInteger nSafeErrors      = 0;
	NSUInteger nUpdateErrors    = 0;
    
	NSMutableString * installerErrorMessages = [NSMutableString stringWithCapacity: 1000];
    
	NSUInteger ix;
	
    // Un-install .tblks in 'deletions'
	for (  ix=0; ix<[[self deletions] count]; ix++  ) {
		
		NSString * target = [[self deletions] objectAtIndex: ix];
		
        if (  ! [ConfigurationManager deleteConfigOrFolderAtPath: target
                                                 usingSystemAuth: auth
                                                      warnDialog: NO]  ) {
			nUninstallErrors++;
			NSString * targetDisplayName   = [lastPartOfPath(target) stringByDeletingPathExtension];
            NSString * targetLocalizedName = [gMC localizedNameforDisplayName: targetDisplayName tblkPath: target];
			[installerErrorMessages appendString: [NSString stringWithFormat: NSLocalizedString(@"Unable to uninstall the '%@' configuration\n", @"Window text"), targetLocalizedName]];
		}
	}
    
    // Install .tblks in 'installSources' to 'installTargets'
    for (  ix=0; ix<[[self installSources] count]; ix++  ) {
        
        NSString * source = [[self installSources] objectAtIndex: ix];
        NSString * target = [[self installTargets] objectAtIndex: ix];
        if (  ! [ConfigurationManager copyConfigPath: source
											  toPath: target
                                     usingSystemAuth: auth
										  warnDialog: NO
										 moveNotCopy: NO
                                             noAdmin: NO]  ) {
            nInstallErrors++;
            NSString * targetDisplayName = [lastPartOfPath(target) stringByDeletingPathExtension];
            NSString * targetLocalizedName = [gMC localizedNameforDisplayName: targetDisplayName tblkPath: target];
            [installerErrorMessages appendString: [NSString stringWithFormat: NSLocalizedString(@"Unable to install the '%@' configuration\n", @"Window text"), targetLocalizedName]];
        }
    }
    
    // Install .tblks in 'replaceSources' to 'replaceTargets'
    for (  ix=0; ix<[[self replaceSources] count]; ix++  ) {
        
        NSString * source = [[self replaceSources] objectAtIndex: ix];
        NSString * target = [[self replaceTargets] objectAtIndex: ix];
        NSString * targetDisplayName = [lastPartOfPath(target) stringByDeletingPathExtension];
        
        if (  [ConfigurationManager copyConfigPath: source
											toPath: target
                                   usingSystemAuth: auth
										warnDialog: NO
                                       moveNotCopy: NO
                                           noAdmin: NO]  ) {
			
            VPNConnection * connection = [gMC connectionForDisplayName: targetDisplayName];
            if (  connection  ) {
                // Force a reload of the configuration's preferences using any new TBPreference and TBAlwaysSetPreference items in its Info.plist
				[connection reloadPreferencesFromTblk];
                [[gMC logScreen] update];
            }
            
        } else {
            nReplaceErrors++;
            NSString * targetLocalizedName = [gMC localizedNameforDisplayName: targetDisplayName tblkPath: target];
            [installerErrorMessages appendString: [NSString stringWithFormat: NSLocalizedString(@"Unable to replace the '%@' configuration\n", @"Window text"), targetLocalizedName]];
        }
    }
	
    // Do "safe" installs/updates from .tblks in 'noAdminSources' to 'noAdminTargets'
    for (  ix=0; ix<[[self noAdminSources] count]; ix++  ) {
        
        NSString * source = [[self noAdminSources] objectAtIndex: ix];
        NSString * target = [[self noAdminTargets] objectAtIndex: ix];
        NSString * targetDisplayName = [lastPartOfPath(target) stringByDeletingPathExtension];
        
        if (  [ConfigurationManager copyConfigPath: source
                                            toPath: target
                                   usingSystemAuth: auth
                                        warnDialog: NO
                                       moveNotCopy: NO
                                           noAdmin: YES]  ) {
            
            VPNConnection * connection = [gMC connectionForDisplayName: targetDisplayName];
            if (  connection  ) {
                // Force a reload of the configuration's preferences using any new TBPreference and TBAlwaysSetPreference items in its Info.plist
                [connection reloadPreferencesFromTblk];
                [[gMC logScreen] update];
            }
            
        } else {
            nSafeErrors++;
            NSString * targetLocalizedName = [gMC localizedNameforDisplayName: targetDisplayName tblkPath: target];
            [installerErrorMessages appendString: [NSString stringWithFormat: NSLocalizedString(@"Unable to install or replace the '%@' configuration\n", @"Window text"), targetLocalizedName]];
        }
    }
    
	// Copy updatable stub .tblks into L_AS_T_TBLKS
    
    // We need to modify target paths to insert the edition number (a unique integer).
    // So it changes from   /something/.../com.example.something/something
    //                 to   /something/.../com.example.something_EDITION/something
    // We set each new edition number to one more than the highest existing edition number
    
    // So first, we find the highest existing edition number
    NSString * highestEdition = nil;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: L_AS_T_TBLKS];
    NSString * file;
    while (  (file = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        if (   ( ! [file hasPrefix: @"."] )
            && ( ! [file hasSuffix: @".tblk"] )  ) {
            NSString * edition = [file pathEdition];
            if (   ( [edition length] != 0 )
                && (   ( ! highestEdition )
                    || [edition caseInsensitiveNumericCompare: highestEdition] == NSOrderedDescending )  ) {
                    highestEdition = edition;
                }
        }
    }
	if (  ! highestEdition  ) {
		highestEdition = @"-1";
	}
    
    // Now go through and copy the stub .tblks, modifying each target path as we go
    
    for (  ix=0; ix<[[self updateSources] count]; ix++  ) {
        
        NSString * source = [[self updateSources] objectAtIndex: ix];
        NSString * target = [[self updateTargets] objectAtIndex: ix];
        
        // Insert the new edition into the target path as a suffix to the next-to-last path component
        
        NSString * targetLast        = [target lastPathComponent];
        NSString * targetWithoutLast = [target stringByDeletingLastPathComponent];
        NSString * bundleId          = [targetWithoutLast lastPathComponent];
        
        highestEdition = [NSString stringWithFormat: @"%u", (unsigned)[highestEdition intValue] + 1];
        
        target = [[targetWithoutLast
                   stringByAppendingFormat: @"_%@", highestEdition]
                  stringByAppendingPathComponent: targetLast];
        
		NSArray * arguments = [NSArray arrayWithObjects: target, source, nil];
		NSInteger installerResult = [gMC runInstaller: INSTALLER_COPY
                                                                        extraArguments: arguments
                                                                       usingSystemAuth: auth
                                                                          installTblks: nil];
		if (  installerResult == 0  ) {
 			[[gMC myConfigMultiUpdater] stopUpdateCheckingForAllStubTblksWithBundleIdentifier: bundleId];
            [[gMC myConfigMultiUpdater] performSelectorOnMainThread:@selector(addUpdateCheckingForStubTblkAtPath:) withObject: target waitUntilDone: YES];
        } else {
            nUpdateErrors++;
            [installerErrorMessages appendString: [NSString stringWithFormat: NSLocalizedString(@"Unable to store updatable configuration stub at %@\n", @"Window text"), target]];
        }
	}
    
    // Release the authorization we have been using
    
    [auth release];
    
	if (  [connectedTargetDisplayNames count] != 0  ) {
		[self performSelectorOnMainThread: @selector(reconnect:) withObject: connectedTargetDisplayNames waitUntilDone: NO];
	}
	
	// Construct and display a window with the results of the uninstalls/replacements/installs
	
	NSUInteger nTotalErrors = nUninstallErrors + nInstallErrors + nReplaceErrors + nUpdateErrors;
	
	if (   (nTotalErrors != 0)
		|| ( ! skipResultMsg )  ) {
		
		NSString * msg = nil;
		
		NSUInteger nNetUninstalls   = nToUninstall - nUninstallErrors;
		NSUInteger nNetInstalls     = nToInstall   - nInstallErrors;
		NSUInteger nNetReplacements = nToReplace   - nReplaceErrors;
        NSUInteger nNetSafes        = nSafe        - nSafeErrors;

		uninstallMsg = (  (nNetUninstalls == 0)
						? @""
						: (  (nNetUninstalls == 1)
						   ? NSLocalizedString(@"     • Uninstalled one configuration\n\n", @"Window text: 'Tunnelblick successfully: *'")
						   : [NSString stringWithFormat: NSLocalizedString(@"     • Uninstalled %lu configurations\n\n", @"Window text: 'Tunnelblick successfully: *'"), (unsigned long)nNetUninstalls]));
		replaceMsg   = (  (nNetReplacements == 0)
						? @""
						: (  (nNetReplacements == 1)
						   ? NSLocalizedString(@"     • Replaced one configuration\n\n", @"Window text: 'Tunnelblick successfully: *'")
						   : [NSString stringWithFormat: NSLocalizedString(@"     • Replaced %lu configurations\n\n", @"Window text: 'Tunnelblick successfully: *'"), (unsigned long)nNetReplacements]));
        safeMsg      = (  (nNetSafes == 0)
                        ? @""
                        : (  (nNetSafes == 1)
                           ? NSLocalizedString(@"     • Installed or replaced one \"safe\" configuration\n\n", @"Window text: 'Tunnelblick successfully: *'")
                           : [NSString stringWithFormat: NSLocalizedString(@"     • Installed or replaced %lu \"safe\" configurations\n\n", @"Window text: 'Tunnelblick successfully: *'"), (unsigned long)nNetSafes]));
		installMsg   = (  (nNetInstalls == 0)
						? @""
						: (  (nNetInstalls == 1)
						   ? NSLocalizedString(@"     • Installed one configuration\n\n", @"Window text: 'Tunnelblick successfully: *'")
						   : [NSString stringWithFormat: NSLocalizedString(@"     • Installed %lu configurations\n\n", @"Window text: 'Tunnelblick successfully: *'"), (unsigned long)nNetInstalls]));
		
		NSString * headerMsg  = (  ([uninstallMsg length] + [replaceMsg length] + [installMsg length]) == 0
								 ? @""
								 : NSLocalizedString(@"Tunnelblick successfully:\n\n", @"Window text: '* Installed/Replaced/Uninstalled'"));
		
		if (  nTotalErrors == 0  ) {
			msg = [NSString stringWithFormat: @"%@%@%@%@%@", headerMsg, uninstallMsg, replaceMsg, installMsg, safeMsg];
            if (  [msg length] != 0  ) {
                [UIHelper showSuccessNotificationTitle: NSLocalizedString(@"VPN Configuration Installation", @"Window title") msg: msg];
            }
		} else {
			msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick encountered errors with %lu configurations:\n\n%@%@%@%@%@%@", @"Window text"),
				   (unsigned long)nTotalErrors, installerErrorMessages, headerMsg, uninstallMsg, replaceMsg, installMsg, safeMsg];
            TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation", @"Window title"), msg);
		}
		
	}
	
    return (  nTotalErrors == 0
			? NSApplicationDelegateReplySuccess
			: NSApplicationDelegateReplyFailure);
}

-(BOOL) multipleInstallableConfigurations: (NSArray *) filePaths {
	
	// Returns TRUE if there are multiple configurations to be installed from paths in filePaths
	// Returns FALSE if there is only one configuration to be installed.
	//
	// Note: if there is a .conf and a .ovpn in the same folder, only one will be installed; this method takes that into account
	
	NSString * firstConfigPath = nil;
	NSString * mainPath;
	NSEnumerator * e = [filePaths objectEnumerator];
	while (  (mainPath = [e nextObject])  ) {
		
		NSString * ext = [mainPath pathExtension];
		
		if (   [ext isEqualToString: @"ovpn"]
			|| [ext isEqualToString: @"conf"]  ) {
			NSString * fullPathWithoutExtension = [mainPath stringByDeletingPathExtension];
			if (  firstConfigPath  ) {
				if (  ! [firstConfigPath isEqualToString: fullPathWithoutExtension]  ) {
					return TRUE;
				}
			} else {
				firstConfigPath = fullPathWithoutExtension;
			}
		}
		
		NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: mainPath];
		NSString * file;
		while (  (file = [dirEnum nextObject])  ) {
			
			ext = [file pathExtension];
			
			if (   [ext isEqualToString: @"ovpn"]
				|| [ext isEqualToString: @"conf"]  ) {
				NSString * fullPathWithoutExtension = [[mainPath stringByAppendingPathComponent: file] stringByDeletingPathExtension];
				if (  firstConfigPath  ) {
					if (  ! [firstConfigPath isEqualToString: fullPathWithoutExtension]  ) {
						return TRUE;
					}
				} else {
					firstConfigPath = fullPathWithoutExtension;
				}
				
			}
		}
	}
	
	return FALSE;
}
		   
-(void) installConfigurations: (NSArray *) filePaths
      skipConfirmationMessage: (BOOL)      skipConfirmMsg
            skipResultMessage: (BOOL)      skipResultMsg
               notifyDelegate: (BOOL)      notifyDelegate
             disallowCommands: (BOOL)      disallowCommands {
    
    // The filePaths array entries are paths to a .tblk, .ovpn, or .conf to install.
    
    if (  [filePaths count] == 0) {
        if (  notifyDelegate  ) {
            [gMC replyToOpenOrPrint: [NSNumber numberWithInt: NSApplicationDelegateReplySuccess]];
        }
        
        return;
    }
    
    if (  ! [self checkFilesAreReasonable: filePaths]  ) {
        if (  notifyDelegate  ) {
            [gMC replyToOpenOrPrint: [NSNumber numberWithInt: NSApplicationDelegateReplyFailure]];
        }
        
        return;
    }
    
    if (  disallowCommands  ) {
        
        if (  ! [NSThread isMainThread]  ) {
            NSLog(@"installConfigurations...disallowCommands: YES but not on main thread; stack trace: %@", callStack());
            if (  notifyDelegate  ) {
                [gMC replyToOpenOrPrint: [NSNumber numberWithInt: NSApplicationDelegateReplyFailure]];
            }
            
            return;
        }
        CommandOptionsStatus status = [ConfigurationManager commandOptionsInConfigurationsAtPaths: filePaths];
        if (  status == CommandOptionsError  ) {
            if (  notifyDelegate  ) {
                [gMC replyToOpenOrPrint: [NSNumber numberWithInt: NSApplicationDelegateReplyFailure]];
            }
            
            return;
        }
        if ( status != CommandOptionsNo  ) {
			if (  status == CommandOptionsUserScript  ) {
				int userAction = TBRunAlertPanelExtended(NSLocalizedString(@"Tunnelblick", @"Window title"),
														 NSLocalizedString(@"One or more VPN configurations that are being updated include programs which"
																		   @" will run when you connect to a VPN. These programs are part of the configuration"
																		   @" and are not part of the Tunnelblick application.\n\n"
																		   @"You should install these configurations only if you trust their author.\n\n"
																		   @"Do you trust the author of the configurations and wish to install them?\n\n",
																		   @"Window text"),
														 NSLocalizedString(@"Cancel",  @"Button"), // Default
														 NSLocalizedString(@"Install", @"Button"), // Alternate
														 nil,                                      // Other
														 @"skipWarningAboutInstallsWithUserCommands",
														 NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
														 nil,
														 NSAlertAlternateReturn);
				if (  userAction == NSAlertAlternateReturn  ) {
					[ConfigurationManager installConfigurationsInNewThreadShowMessagesNotifyDelegateWithPaths: filePaths];
				}
			} else {
				int userAction = TBRunAlertPanelExtended(NSLocalizedString(@"Tunnelblick", @"Window title"),
														 NSLocalizedString(@"One or more VPN configurations that are being updated include programs which"
																		   @" will run as root when you connect to a VPN. These programs are part of the configuration"
																		   @" and are not part of the Tunnelblick application. They are able to TAKE"
																		   @" COMPLETE CONTROL OF YOUR COMPUTER.\n\n"
																		   @"YOU SHOULD NOT INSTALL THESE CONFIGURATIONS UNLESS YOU TRUST THEIR AUTHOR.\n\n"
																		   @"Do you trust the author of the configurations and wish to install them?\n\n",
																		   @"Window text"),
														 NSLocalizedString(@"Cancel",  @"Button"), // Default
														 NSLocalizedString(@"Install", @"Button"), // Alternate
														 nil,                                      // Other
														 @"skipWarningAboutInstallsWithCommands",
														 NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
														 nil,
														 NSAlertAlternateReturn);
				if (  userAction == NSAlertAlternateReturn  ) {
					userAction = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
												 NSLocalizedString(@"Are you sure you wish to install configurations which can TAKE"
																   @" COMPLETE CONTROL OF YOUR COMPUTER?\n\n",
																   @"Window text"),
												 NSLocalizedString(@"Cancel",  @"Button"), // Default
												 NSLocalizedString(@"Install", @"Button"), // Alternate
												 nil);                                     // Other
					if (  userAction == NSAlertAlternateReturn  ) {
						[ConfigurationManager installConfigurationsInNewThreadShowMessagesNotifyDelegateWithPaths: filePaths];
					}
				}
			}
			
			if (  notifyDelegate  ) {
                [gMC replyToOpenOrPrint: [NSNumber numberWithInt: NSApplicationDelegateReplyFailure]];
            }
				
            return;
        }
    }
		
    // Set up instance variables that we use
		
    BOOL isDeployed = [gFileMgr fileExistsAtPath: gDeployPath];
    [self setInstallToPrivateOK: (   (! isDeployed)
                                  || (   [gTbDefaults boolForKey: @"usePrivateConfigurationsWithDeployedOnes"]
                                      && ( ! [gTbDefaults canChangeValueForKey: @"usePrivateConfigurationsWithDeployedOnes"])
                                      )
                                  )];
    [self setInstallToSharedOK: (   (! isDeployed)
                                 || (   [gTbDefaults boolForKey: @"useSharedConfigurationsWithDeployedOnes"]
                                     && ( ! [gTbDefaults canChangeValueForKey: @"useSharedConfigurationsWithDeployedOnes"])
                                     )
                                 )];
    if (   [gTbDefaults boolForKey: @"doNotOpenDotTblkFiles"]
        || (   ( ! [self installToPrivateOK] )
            && ( ! [self installToSharedOK]  )
            )
        ) {
        TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation Error", @"Window title"),
                          NSLocalizedString(@"Installing configurations is not allowed", "Window text"));
        if (  notifyDelegate  ) {
            [gMC replyToOpenOrPrint: [NSNumber numberWithInt: NSApplicationDelegateReplyFailure]];
        }
        return;
    }
    
    installSources =   [[NSMutableArray alloc]  initWithCapacity: 100];
    installTargets =   [[NSMutableArray alloc]  initWithCapacity: 100];
    replaceSources =   [[NSMutableArray alloc]  initWithCapacity: 100];
    replaceTargets =   [[NSMutableArray alloc]  initWithCapacity: 100];
    noAdminSources =   [[NSMutableArray alloc]  initWithCapacity: 100];
    noAdminTargets =   [[NSMutableArray alloc]  initWithCapacity: 100];
    updateSources  =   [[NSMutableArray alloc]  initWithCapacity: 100];
    updateTargets  =   [[NSMutableArray alloc]  initWithCapacity: 100];
    deletions      =   [[NSMutableArray alloc]  initWithCapacity: 100];
    
    errorLog       =   [[NSMutableString alloc] initWithCapacity: 1000];
    
    [self setInhibitCheckbox:        FALSE];
    [self setMultipleConfigurations: [self multipleInstallableConfigurations: filePaths]];
	
    NSString * path = [newTemporaryDirectoryPath() autorelease];
    if (  ! [gFileMgr tbRemoveFileAtPath: path handler: nil]  ) {
        NSLog(@"Unable to delete %@", path);
        if (  notifyDelegate  ) {
            [gMC replyToOpenOrPrint: [NSNumber numberWithInt: NSApplicationDelegateReplyFailure]];
        }
        return;
    }
    if (  createDir(path, privateFolderPermissions(path)) == -1  ) {
        NSLog(@"Unable to create %@", path);
        if (  notifyDelegate  ) {
            [gMC replyToOpenOrPrint: [NSNumber numberWithInt: NSApplicationDelegateReplyFailure]];
        }
        return;
    }
    [self setTempDirPath: path];
    
    //
    //
    // From here on, we need to use cleanupInstallAndNotifyDelegate: so the temporary directory is removed
    //
    //
    
    // Separate the file list into .tblks and .ovpn/.conf
    NSMutableArray * tblkPaths = [NSMutableArray arrayWithCapacity: [filePaths count]];
    NSMutableArray * ovpnPaths = [NSMutableArray arrayWithCapacity: [filePaths count]];
	NSString * file;
	NSEnumerator * e = [filePaths objectEnumerator];
	while (  (file = [e nextObject])  ) {
		NSString * ext = [file pathExtension];
		if (  [ext isEqualToString: @"tblk"]  ) {
            [tblkPaths addObject: file];
		} else if (   [ext isEqualToString: @"ovpn"]
				   || [ext isEqualToString: @"conf"]  ) {
			[ovpnPaths addObject: file];
		}  // Ignore anything else
	}
    
    // Set up to install .tblk packages
    if (  [tblkPaths count] != 0  ) {
        NSString * result = [self setupToInstallTblks: tblkPaths haveOvpnOrConfs: ([ovpnPaths count] != 0)];
        if (  result  ) {
            if ( [result isEqualToString: @"cancel"]  ) {
				[self cleanupInstallAndNotifyDelegate: notifyDelegate delegateNotifyValue: NSApplicationDelegateReplyCancel];
				return;
			} else if (  [result isNotEqualTo: @"skip"]  ) {
				TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation Error", @"Window title"),
								  [NSString stringWithFormat:
								   NSLocalizedString(@"Installation failed:\n\n%@", "Window text"),
								   result]);
				[self cleanupInstallAndNotifyDelegate: notifyDelegate delegateNotifyValue: NSApplicationDelegateReplyFailure];
				return;
			}
        }
    }
    
    // Set up to install .ovpn and .conf files
	if (  [ovpnPaths count] != 0  ) {
        NSString * result = [self setupToInstallOvpnsAndConfs: ovpnPaths];
        if (  result  ) {
            if ( [result isEqualToString: @"cancel"]  ) {
				[self cleanupInstallAndNotifyDelegate: notifyDelegate delegateNotifyValue: NSApplicationDelegateReplyCancel];
				return;
			} else if (  [result isNotEqualTo: @"skip"]  ) {
				TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation Error", @"Window title"),
								  [NSString stringWithFormat:
								   NSLocalizedString(@"Installation failed:\n\n%@", "Window text"),
								   result]);
				[self cleanupInstallAndNotifyDelegate: notifyDelegate delegateNotifyValue: NSApplicationDelegateReplyFailure];
				return;
			}
        }
    }
	
	// Do the uninstalls/replacements/uninstalls
	NSApplicationDelegateReply reply = [self doUninstallslReplacementsInstallsSkipConfirmMsg: skipConfirmMsg
																			   skipResultMsg: skipResultMsg];
	
    [self cleanupInstallAndNotifyDelegate: notifyDelegate delegateNotifyValue: reply];
	
    return;
}

-(void) installConfigurations: (NSArray *) filePaths
                 skipMessages: (BOOL)      skipMessages
               notifyDelegate: (BOOL)      notifyDelegate
             disallowCommands: (BOOL)      disallowCommands
{
     [[ConfigurationManager manager] installConfigurations: filePaths
                                  skipConfirmationMessage: skipMessages
                                        skipResultMessage: skipMessages
                                            notifyDelegate: notifyDelegate
                                          disallowCommands: disallowCommands];
}

+(BOOL) isConfigurationSetToConnectWhenComputerStartsAtPath: (NSString *) path {
    
    NSString * displayName = lastPartOfPath(path);
    NSString * autoConnectKey = [displayName stringByAppendingString: @"autoConnect"];
    NSString * onSystemStartKey = [displayName stringByAppendingString: @"-onSystemStart"];
    if (   [gTbDefaults boolForKey: autoConnectKey]
        && [gTbDefaults boolForKey: onSystemStartKey]  ) {
        return YES;
    }
    
    return NO;
}

+(BOOL) isConfigurationUpdatableAtPath: (NSString *) path {
    
    NSString * infoPlistPath = [[path stringByAppendingPathComponent: @"Contents"] stringByAppendingPathComponent: @"Info.plist"];
    NSString * fileName = [[[NSDictionary dictionaryWithContentsOfFile: infoPlistPath] objectForKey: @"CFBundleIdentifier"] stringByAppendingPathExtension: @"tblk"];
    if (  fileName  ) {
        BOOL isUpdatable = FALSE;
        BOOL isDir;
        NSString * bundleIdAndEdition;
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: L_AS_T_TBLKS];
        while (  (bundleIdAndEdition = [dirEnum nextObject])  ) {
            [dirEnum skipDescendents];
            NSString * containerPath = [L_AS_T_TBLKS stringByAppendingPathComponent: bundleIdAndEdition];
            if (   ( ! [bundleIdAndEdition hasPrefix: @"."] )
                && ( ! [bundleIdAndEdition hasSuffix: @".tblk"] )
                && [[NSFileManager defaultManager] fileExistsAtPath: containerPath isDirectory: &isDir]
                && isDir  ) {
                NSString * name;
                NSDirectoryEnumerator * innerEnum = [gFileMgr enumeratorAtPath: containerPath];
                while (  (name = [innerEnum nextObject] )  ) {
                    if (  [name isEqualToString: fileName]  ) {
                        isUpdatable = TRUE;
                        break;
                    }
                }
            }
        }
        if (  isUpdatable  ) {
            return YES;
        }
    }
    
    return NO;
}

+(BOOL) okToRemoveOneConfigurationOrFolderWithDisplayName: (NSString *) displayName {
    
    if (  ! [displayName hasSuffix: @"/"]  ) {

        // It's a configuration
        VPNConnection * connection = [gMC connectionForDisplayName: displayName];
        if (  ! connection  ) {
            NSLog(@"okToRemoveConfigurationWithDisplayNames: Cannot get VPNConnection object for display name '%@'", displayName);
            return NO;
        }

        NSString * configurationPath = [connection configPath];
        if (  ! [connection isDisconnected]  ) {
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                              NSLocalizedString(@"You may not remove a configuration unless it is disconnected.", @"Window text"));
            return NO;
        }
        if (  [ConfigurationManager isConfigurationSetToConnectWhenComputerStartsAtPath: configurationPath]  ) {
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                              NSLocalizedString(@"You may not remove a configuration which is set to start when the computer starts.", @"Window text"));
            return NO;
        }

        if (  [configurationPath hasPrefix: [gDeployPath stringByAppendingString: @"/"]]  ) {
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                              NSLocalizedString(@"You may not remove a Deployed configuration.", @"Window text"));
            return NO;
        }

        return YES;
    }

    NSString * dirPath = configPathFromDisplayName(displayName);
    if (  ! [@"" isEqualToString: dirPath]  ) {
        NSLog(@"Display name '%@' is not a folder or it doesn't exist in the shared, private, or secured folders", displayName);
        return NO; // It doesn't exist in shared or private, or it's not a folder
    }

    // It's a folder. If it has no configurations inside it, or inside it's subfolders, we can delete it.

    // Because it is a folder, it could exist in the shared, private and/or secured folders, so we need to look in all three

    BOOL haveConfigurations = FALSE;
    NSArray * folders = [NSArray arrayWithObjects: gPrivatePath, L_AS_T_SHARED, [L_AS_T_USERS stringByAppendingPathComponent: NSUserName()], nil];
    NSEnumerator * e  = [folders objectEnumerator];
    NSString * path;
    while (  (path = [e nextObject])  ) {
        NSDirectoryEnumerator * dirE = [gFileMgr enumeratorAtPath: path];
        NSString * file;
        while (  (file = [dirE nextObject])  ) {
            if (   [file hasPrefix: displayName]
                && [file hasSuffix: @".tblk"]  ) {
                haveConfigurations = TRUE;
                break;
            }
        }
    }

    if (  haveConfigurations  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString(@"You may not remove a folder unless it is empty.", @"Window text"));
        return NO;
    }

    return YES;
}

+(void) removeConfigurationsOrFoldersWithDisplayNamesWorker: (NSArray *) displayNames
                                            usingSystemAuth: (SystemAuth *) auth {

    BOOL ok = TRUE;
    NSString * displayName;
    NSEnumerator * e = [displayNames objectEnumerator];
    while (  (displayName = [e nextObject])  ) {

        NSString * path;
        BOOL isFolder = [displayName hasSuffix: @"/"];
        if (  isFolder  ) {
            // Do for shared and private folders. (installer will delete secure folder corresponding to private folder)
            NSArray * folders = [NSArray arrayWithObjects: L_AS_T_SHARED, gPrivatePath, nil];
            NSEnumerator * e2 = [folders objectEnumerator];
            NSString * folder;
            while (   ok
                   && (folder = [e2 nextObject])  ) {
                NSString * path2 = [folder stringByAppendingPathComponent: displayName];
                if (   [gFileMgr fileExistsAtPath: path2]  ) {
                    ok = [ConfigurationManager deleteConfigOrFolderAtPath: path2
                                                          usingSystemAuth: auth
                                                               warnDialog: YES];
                }
            }

            [gTbDefaults replacePrefixOfPreferenceValuesThatHavePrefix: displayName with: nil];
            
        } else {
            VPNConnection * connection = [gMC connectionForDisplayName: displayName];
            if (  ! connection  ) {
                NSLog(@"removeConfigurationsOrFoldersWithDisplayNamesWorker: Cannot get VPNConnection object for display name '%@'", displayName);
                ok = FALSE;
            }

            if (  ok  ) {
                path = [connection configPath];
                ok = [ConfigurationManager deleteConfigOrFolderAtPath: path
                                                      usingSystemAuth: auth
                                                           warnDialog: YES];
                if (  ok  ) {
                    NSString * group = credentialsGroupFromDisplayName(displayName);
                    if (   group
                        && [gTbDefaults numberOfConfigsInCredentialsGroup: group] > 1  ) {
                        group = nil;
                    }
                    if (  group  ) {
                        AuthAgent * myAuthAgent = [[[AuthAgent alloc] initWithConfigName: group credentialsGroup: group] autorelease];

                        [myAuthAgent setAuthMode: @"privateKey"];
                        if (  [myAuthAgent keychainHasAnyCredentials]  ) {
                            [myAuthAgent deleteCredentialsFromKeychainIncludingUsername: YES];
                        }
                        [myAuthAgent setAuthMode: @"password"];
                        if (  [myAuthAgent keychainHasAnyCredentials]  ) {
                            [myAuthAgent deleteCredentialsFromKeychainIncludingUsername: YES];
                        }
                    }
                    
                    [gTbDefaults removePreferencesFor: displayName];
                }
            }
        }

        if (  ! ok  ) {
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                              NSLocalizedString(@"There was a problem deleting one or more configurations or folders. See the Console Log for details.", @"Window text"));
            return;
        }
    }
}

+(void) changeToShared: (BOOL)         shared
              fromPath: (NSString *)   path
       usingSystemAuth: (SystemAuth *) auth {
    
    NSString * rawName = lastPartOfPath(path);
    NSString * displayName = [rawName stringByDeletingPathExtension];
    NSString * targetPath;
    
    if (  [path hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
        targetPath = [L_AS_T_SHARED stringByAppendingPathComponent: rawName];
    } else if (  [path hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]  ) {
        targetPath = [gPrivatePath stringByAppendingPathComponent: rawName];
    } else {
        NSLog(@"changeToSharedFromPath: Internal error: path is not private or shared at %@", path);
        return;
    }
    
    if (  [gFileMgr fileExistsAtPath: targetPath]  ) {
		NSString * localName = [gMC localizedNameForDisplayName: displayName];
        NSString * message = (  shared
                              ? [NSString stringWithFormat: NSLocalizedString(@"A shared configuration named '%@' already exists.\n\nDo you wish to replace it with the private configuration?", @"Window text"), localName]
                              : [NSString stringWithFormat: NSLocalizedString(@"A private configuration named '%@' already exists.\n\nDo you wish to replace it with the shared configuration?", @"Window text"), localName]);
        int result = TBRunAlertPanel(NSLocalizedString(@"Replace VPN Configuration?", @"Window title"),
                                     message,
                                     NSLocalizedString(@"Replace", @"Button"),
                                     NSLocalizedString(@"Cancel" , @"Button"),
                                     nil);
        if (  result != NSAlertDefaultReturn  ) {   // No action if cancelled or error occurred
            return;
        }
    }
    
    [ConfigurationManager copyConfigPath: path
								  toPath: targetPath
                         usingSystemAuth: auth
							  warnDialog: YES
                             moveNotCopy: YES
                                 noAdmin: NO];
    
    VPNConnection * connection = [gMC connectionForDisplayName: displayName];
    if (  ! connection  ) {
        NSLog(@"changeToSharedFromPath: Internal error: cannot find connection for '%@', unable to ", displayName);
    }
    
    [connection invalidateConfigurationParse];
}

+(void) makeConfigurationsShared: (BOOL)      shared
                    displayNames: (NSArray *) displayNames {
    
    // Check that all configurations are shared or private, and create an array with display names to change
    NSMutableArray * pathsToModify = [[[NSMutableArray alloc] init] autorelease];
    
    // Make sure all of the configurations are either private or shared currently
    NSDictionary * dict = [gMC myConfigDictionary];
    NSString * displayName;
    NSEnumerator * e = [displayNames objectEnumerator];
    while (  (displayName = [e nextObject])  ) {
        NSString * path = [dict objectForKey: displayName];
		NSString * localName = [gMC localizedNameForDisplayName: displayName];
		if (  [path hasPrefix: [L_AS_T_SHARED stringByAppendingPathComponent: @"/"]]  ) {
			if (  ! shared  ) {
				if (  [ConfigurationManager isConfigurationSetToConnectWhenComputerStartsAtPath: path]  ) {
					TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
									  [NSString  stringWithFormat: NSLocalizedString(@"You cannot make the '%@' configuration private because it is set to start when the computer starts.", @"Window text"), localName]);
					return;
				}						
				if (   [ConfigurationManager isConfigurationUpdatableAtPath: path]  ) {
					TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
									  [NSString  stringWithFormat: NSLocalizedString(@"You cannot make the '%@' configuration private or shared because it is an updatable configuration.\n\n"
																					 @"Note that a Tunnelblick VPN Configuration that is updatable cannot be made private or shared; only the configurations within it can be made private or shared.", @"Window text"), localName]);
					return;  // User has been notified already
				}
				[pathsToModify addObject: path];
			}
		} else if (  [path hasPrefix: [gPrivatePath stringByAppendingPathComponent: @"/"]]  ) {
			if (  shared  ) {
				if (  [ConfigurationManager isConfigurationUpdatableAtPath: path]  ) {
					TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                                      [NSString  stringWithFormat: NSLocalizedString(@"You cannot make the '%@' configuration private or shared because it is an updatable configuration.\n\n"
                                                                                     @"Note that a Tunnelblick VPN Configuration that is updatable cannot be made private or shared; only the configurations within it can be made private or shared.", @"Window text"), localName]);
					return;  // User has been notified already
				}
				[pathsToModify addObject: path];
			}
		}
    }
    
    if (  [pathsToModify count] == 0  ) {
        return;
    }
    
	NSString * localName = nil;
	if (  [pathsToModify count] == 1  ) {
		localName = [gMC localizedNameForDisplayName: [lastPartOfPath([pathsToModify objectAtIndex: 0]) stringByDeletingPathExtension]];
	}
    NSString * prompt = (  ([pathsToModify count] == 1)
                         ? (  shared
                            ? [NSString  stringWithFormat: NSLocalizedString(@"Tunnelblick needs authorization to make the '%@' configuration shared.", @"Window text"), localName]
                            : [NSString  stringWithFormat: NSLocalizedString(@"Tunnelblick needs authorization to make the '%@' configuration private.", @"Window text"), localName])
                         : ( shared
                            ? [NSString  stringWithFormat: NSLocalizedString(@"Tunnelblick needs authorization to make %ld configurations shared.",  @"Window text"), (unsigned long)[pathsToModify count]]
                            : [NSString  stringWithFormat: NSLocalizedString(@"Tunnelblick needs authorization to make %ld configurations private.", @"Window text"),  (unsigned long)[pathsToModify count]]));

    SystemAuth * auth = [SystemAuth newAuthWithPrompt: prompt];
    if (   ! auth  ) {
        return;
    }
    
    // Change each entry in pathsToModify to shared or private
    NSString * path;
    e = [pathsToModify objectEnumerator];
    while (  (path = [e nextObject])  ) {
        [ConfigurationManager changeToShared: shared
                                    fromPath: path
                             usingSystemAuth: auth];
    }
    
    [auth release];
}

+(BOOL) revertOneConfigurationToShadowWithDisplayName: (NSString *) displayName {
	
	BOOL errorFound = FALSE;
	NSString * fileName = [displayName stringByAppendingPathExtension: @"tblk"];
	NSArray  * arguments = [NSArray arrayWithObjects: @"revertToShadow", fileName, nil];
	OSStatus result = runOpenvpnstart(arguments, nil, nil);
	switch (  result  ) {
			
		case OPENVPNSTART_REVERT_CONFIG_OK:
			break;
			
		case OPENVPNSTART_REVERT_CONFIG_MISSING:
			TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation Error", @"Window title"),
							  NSLocalizedString(@"The private configuration has never been secured, so you cannot revert to the secured (shadow) copy.", @"Window text"));
			errorFound = TRUE;
			break;
			
		default:
			TBShowAlertWindow(NSLocalizedString(@"VPN Configuration Installation Error", @"Window title"),
							  NSLocalizedString(@"An error occurred while trying to revert to the secured (shadow) copy. See the Console Log for details.\n\n", @"Window text"));
			errorFound = TRUE;
			break;
	}
    
	VPNConnection * connection = [gMC connectionForDisplayName: displayName];
	if (  connection  ) {
		[connection invalidateConfigurationParse];
	} else {
		NSLog(@"Internal error: revertOneConfigurationToShadowWithDisplayName: no connection for '%@'", displayName);
	}
	
	return (! errorFound);
}

+(void) revertToShadowWithDisplayNames: (NSArray *) displayNames {
    
	NSMutableArray * displayNamesToRevert = [[[NSMutableArray alloc] init] autorelease];
	NSString * displayName;
	NSEnumerator * e = [displayNames objectEnumerator];
	while (  (displayName = [e nextObject])  ) {
		VPNConnection * connection = [gMC connectionForDisplayName: displayName];
		if (  connection  ) {
			NSString * source = [connection configPath];
			if (  [source hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
				if (  ! [connection shadowCopyIsIdentical]  ) {
					[displayNamesToRevert addObject: displayName];
				}
			}
		} else {
			NSLog(@"Internal Error: revertToShadowWithDisplayNames: No connection for '%@'", displayName);
		}
	}
	
	if (  [displayNamesToRevert count] == 0  ) {
		return;
	}
	
	NSString * message = (  ([displayNamesToRevert count] == 1)
						  ? [NSString stringWithFormat:
							 NSLocalizedString(@"Do you wish to revert the '%@' configuration to its last secured (shadow) copy?\n\n", @"Window text"), [gMC localizedNameForDisplayName: [displayNamesToRevert objectAtIndex: 0]]]
						  : [NSString stringWithFormat:
							 NSLocalizedString(@"Do you wish to revert %ld configurations to their last secured (shadow) copy?\n\n", @"Window text"), (unsigned long)[displayNamesToRevert count]]);
	
	int result = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
								 message,
								 NSLocalizedString(@"Revert", @"Button"),
								 NSLocalizedString(@"Cancel", @"Button"), nil);
	
	[gMC reactivateTunnelblick];
	
	if (  result != NSAlertDefaultReturn  ) {
		return;
	}
    
	BOOL ok = TRUE;
	e = [displayNamesToRevert objectEnumerator];
	while (  (displayName = [e nextObject])  ) {
		ok = ok && [self revertOneConfigurationToShadowWithDisplayName: displayName];
	}
	
	if (  ok  ) {
		NSString * message2 = (  ([displayNamesToRevert count] == 1)
                               ? [NSString stringWithFormat:
                                  NSLocalizedString(@"%@ has been reverted to its last secured (shadow) copy.\n\n", @"Window text"), [gMC localizedNameForDisplayName: [displayNamesToRevert objectAtIndex: 0]]]
                               : [NSString stringWithFormat:
                                  NSLocalizedString(@"%ld configurations have been reverted to their last secured (shadow) copy.\n\n", @"Window text"), (unsigned long)[displayNamesToRevert count]]);

		[UIHelper showSuccessNotificationTitle: NSLocalizedString(@"Tunnelblick", @"Window title") msg: message2];
	}
}

+(void) removeConfigurationsOrFoldersWithDisplayNames: (NSArray *) displayNames {
    
    // Make sure we can remove all of the configurations or folders
    NSEnumerator * e = [displayNames objectEnumerator];
    NSString * displayName;
    while (  (displayName = [e nextObject])  ) {
        if (  ! [ConfigurationManager okToRemoveOneConfigurationOrFolderWithDisplayName: displayName]) {
            return;
        }
    }
    
    NSString * prompt = NSLocalizedString(@"Tunnelblick needs authorization to remove one or more configurations"
                                          @" or folders.\n\n Removal is permanent and cannot be undone."
                                          @" Settings for removed configurations will also be removed permanently.", @"Window text");
    SystemAuth * auth = [SystemAuth newAuthWithPrompt: prompt];
    if (   ! auth  ) {
        return;
    }
    [ConfigurationManager removeConfigurationsOrFoldersWithDisplayNamesWorker: displayNames
                                                              usingSystemAuth: auth];

    [auth release];
}

+(void) removeCredentialsWithDisplayNames: (NSArray *) displayNames {
	
	NSMutableArray * displayNamesToProcess = [[[NSMutableArray alloc] init] autorelease];
	NSMutableArray * groupNamesToProcess = [[[NSMutableArray alloc] init] autorelease];
	
	NSString * displayName;
	NSEnumerator * e = [displayNames objectEnumerator];
	while (  (displayName = [e nextObject] )  ) {
		
		NSString * group = credentialsGroupFromDisplayName(displayName);
		AuthAgent * myAuthAgent = [[[AuthAgent alloc] initWithConfigName: displayName credentialsGroup: group] autorelease];
		
        [myAuthAgent setAuthMode: @"privateKey"];
        if (  [myAuthAgent keychainHasAnyCredentials]  ) {
			[displayNamesToProcess addObject: displayName];
            [groupNamesToProcess addObject: (  group
                                             ? group
                                             : (NSString *)[NSNull null])];
			continue;
		}
		
        [myAuthAgent setAuthMode: @"password"];
        if (  [myAuthAgent keychainHasAnyCredentials]  ) {
			[displayNamesToProcess addObject: displayName];
			[groupNamesToProcess addObject: (  group
											 ? group
											 : (NSString *)[NSNull null])];
		}
	}
	
	if (  [displayNamesToProcess count] == 0  ) {
		NSString * message = (  ( [displayNames count] == 1 )
							  ? [NSString stringWithFormat:
								 NSLocalizedString(@"'%@' does not have any credentials (private key or username and password) stored in the Keychain.", @"Window text"),
								 [gMC localizedNameForDisplayName: [displayNames objectAtIndex: 0]]]
							  : [NSString stringWithFormat:
								 NSLocalizedString(@"None of the %ld selected configurations have any credentials (private key or username and password) stored in the Keychain.", @"Window text"),
								 (unsigned long)[displayNames count]]);
		TBShowAlertWindow(NSLocalizedString(@"No Credentials", @"Window title"), message);
		return;
	}
	
	NSString * message = (  ([displayNamesToProcess count] == 1)
						  ? (  ([groupNamesToProcess objectAtIndex: 0] != [NSNull null])
							 ? [NSString stringWithFormat: NSLocalizedString(@"Are you sure you wish to delete the credentials (private key and/or username and password) stored in the Keychain for '%@' credentials?", @"Window text"), [groupNamesToProcess objectAtIndex: 0]]
							 : [NSString stringWithFormat: NSLocalizedString(@"Are you sure you wish to delete the credentials (private key and/or username and password) for '%@' that are stored in the Keychain?", @"Window text"),    [gMC localizedNameForDisplayName: [displayNamesToProcess objectAtIndex: 0]]])
						  
						  : [NSString stringWithFormat: NSLocalizedString(@"Are you sure you wish to delete the credentials (private key and/or username and password) for %ld configurations that are stored in the Keychain?", @"Window text"), [displayNamesToProcess count]]);
	
	int button = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
								 message,
								 NSLocalizedString(@"Cancel", @"Button"),             // Default button
								 NSLocalizedString(@"Delete Credentials", @"Button"), // Alternate button
								 nil);
	
	if (  button != NSAlertAlternateReturn  ) {
		return;
	}
	
	unsigned ix;
	for (  ix=0; ix<[displayNamesToProcess count]; ix++  ) {
		displayName = [displayNamesToProcess objectAtIndex: ix];
		NSString * groupName   = [groupNamesToProcess   objectAtIndex: ix];
		if (  [groupName isEqual: (NSString *)[NSNull null]]  ) {
			groupName = nil;
		}
		AuthAgent * myAuthAgent = [[[AuthAgent alloc] initWithConfigName: displayName credentialsGroup: groupName] autorelease];
		
        [myAuthAgent setAuthMode: @"privateKey"];
        if (  [myAuthAgent keychainHasAnyCredentials]  ) {
			[myAuthAgent deleteCredentialsFromKeychainIncludingUsername: YES];
		}
		
        [myAuthAgent setAuthMode: @"password"];
        if (  [myAuthAgent keychainHasAnyCredentials]  ) {
			[myAuthAgent deleteCredentialsFromKeychainIncludingUsername: YES];
		}
	}
}

+(void) removeCredentialsGroupWithName: (NSString *) groupName {
    
    
    int result = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                                 [NSString stringWithFormat: NSLocalizedString(@"Do you wish to delete the %@ credentials?", @"Window text"), groupName],
                                 NSLocalizedString(@"Cancel", @"Button"),    // Default button
                                 NSLocalizedString(@"Delete", @"Button"),    // Alternate button
                                 nil);
    
    if (  result != NSAlertAlternateReturn  ) {
        return;
    }
    
    NSString * errMsg = [gTbDefaults removeNamedCredentialsGroup: groupName];
    if (  errMsg  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          [NSString stringWithFormat:
                           NSLocalizedString(@"The credentials named %@ could not be removed:\n\n%@", @"Window text"),
                           groupName,
                           errMsg]);
    } else {
        SettingsSheetWindowController * wc = [[gMC logScreen] settingsSheetWindowController];
        [wc performSelectorOnMainThread: @selector(updateStaticContentSetupSettingsAndBringToFront) withObject: nil waitUntilDone: NO];
    }
}

+(void) duplicateConfigurationFromPath: (NSString *)         sourcePath
                                toPath: (NSString *)         targetPath {
    
    NSString * sourceDisplayName = [lastPartOfPath(sourcePath) stringByDeletingPathExtension];
    NSString * targetDisplayName = [lastPartOfPath(targetPath) stringByDeletingPathExtension];
    
    NSString * prompt = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick needs authorization to duplicate the '%@' configuration.", @"Window text"), sourceDisplayName];
    SystemAuth * auth = [SystemAuth newAuthWithPrompt: prompt];
    if (   ! auth  ) {
        return;
    }
    
    if (  [ConfigurationManager copyConfigPath: sourcePath
										toPath: targetPath
							   usingSystemAuth: auth
									warnDialog: YES
                                   moveNotCopy: NO
                                       noAdmin: NO]  ) {
        
        if (  ! [gTbDefaults copyPreferencesFrom: sourceDisplayName to: targetDisplayName]  ) {
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                              NSLocalizedString(@"Warning: One or more settings could not be duplicated. See the Console Log for details.", @"Window text"));
        }
        
        copyCredentials(sourceDisplayName, targetDisplayName);
    }
    
    [auth release];
}

+(NSString *) pathToUseIfItemAtPathExists: (NSString *) path stopNotCancel: (BOOL) stopNotCancel {

    if (  ! [gFileMgr fileExistsAtPath: path]  ) {
        return [[path retain] autorelease];
    }

    NSString * msg = [NSString stringWithFormat:
                      NSLocalizedString(@"A configuration named '%@' already exists in this location.\n"
                                       @"Do you want to replace it with the one you're moving or copying?", @"Window text"), lastPartOfPath(path)];

    NSString * cancelOrStopButtonText = (  stopNotCancel
                                         ? NSLocalizedString(@"Stop", @"Button. In a dialog that says a file already exists in a new location. Usually this button would be labelled 'Cancel', but it is labelled 'Stop' if one or more of a series of copies or moves of files or folders has already been done.")
                                         : NSLocalizedString(@"Cancel", @"Button."));

    int  result = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                                  msg,
                                  cancelOrStopButtonText,   // Default
                                  NSLocalizedString(@"Keep Both", @"Button. In a dialog that says a file already exists in a new location."),   // Alternate
                                  NSLocalizedString(@"Replace",   @"Button. In a dialog that says a file already exists in a new location."));  // Other
    switch (  result  ) {

        case NSAlertDefaultReturn:
            // User cancelled, do nothing
            return nil;
            break;

        case NSAlertAlternateReturn:
            // Keep both, so create a new path with a name suffixed by a number, e.g. "Config 2"
            return pathWithNumberSuffixIfItemExistsAtPath(path, NO);
            break;

        case NSAlertOtherReturn:
            // Replace, so just use same path
            return [[path retain] autorelease];
            break;

        default:
            NSLog(@"pathToUseIfItemAtPathExists: TBRunAlertPanel returned %d", result);
            TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                                          NSLocalizedString(@"An error occurred. Please try again.", @"Window text"),
                            nil, nil, nil);
            break;
    }

    return nil;
}

+(BOOL) createConfigurationFolderAtPath: (NSString *) path usingSystemAuth: (SystemAuth *) auth {

    NSArray * arguments = [NSArray arrayWithObjects: path, @"", nil];
    NSInteger installerResult = [gMC runInstaller: INSTALLER_COPY
                                                                    extraArguments: arguments
                                                                   usingSystemAuth: auth
                                                                      installTblks: nil];
    if (  installerResult != 0  ) {
        NSLog(@"Could not create configuration folder '%@'", path);
        return FALSE;
    }

    return TRUE;
}

+(BOOL) createConfigurationFoldersForDisplayName: (NSString *) targetDisplayName usingSystemAuth: (SystemAuth *) auth {

    // Creates shared, private, and secured configuration folders with the specified display name
    NSString * sharedPath = [L_AS_T_SHARED stringByAppendingPathComponent: targetDisplayName];
    if (  ! [gFileMgr fileExistsAtPath: sharedPath]  ) {
        if (  ! [self createConfigurationFolderAtPath: sharedPath usingSystemAuth: auth]  ) {
            return FALSE;
        }
    }

    NSString * privatePath = [gPrivatePath stringByAppendingPathComponent: targetDisplayName];
    if (  ! [gFileMgr fileExistsAtPath: privatePath]  ) {
        return [self createConfigurationFolderAtPath: privatePath usingSystemAuth: auth];
    }

    return TRUE;
}

+(BOOL) verifyCanDoMoveOrRenameFromPath: (NSString *) sourcePath name: (NSString *) sourceName {

    VPNConnection * connection = [gMC connectionForDisplayName: sourceName];
    if (  ! connection  ) {
        NSLog(@"verifyCanDoMoveOrRenameFromPath: No '%@' configuration exists", sourceName);
        return FALSE;
    }

    if (  ! [connection isDisconnected]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Active connection", @"Window title"),
                          NSLocalizedString(@"You cannot rename or move a configuration unless it is disconnected.", @"Window text"));
        return FALSE;
    }

    if (  [ConfigurationManager isConfigurationSetToConnectWhenComputerStartsAtPath: sourcePath]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString(@"You cannot rename or move a configuration which is set to start when the computer starts.", @"Window text"));
        return FALSE;
    }

    if (  [sourcePath hasPrefix: [gDeployPath stringByAppendingString: @"/"]]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString(@"You cannot rename or move a Deployed configuration.", @"Window text"));
        return FALSE;
    }

    return TRUE;
}

+(BOOL) moveOrCopyCredentialsAndSettingsFrom: (NSString *) sourceDisplayName to: (NSString *) targetDisplayName moveNotCopy: (BOOL) moveNotCopy {

    BOOL problemWithSettings = FALSE;;

    if (  moveNotCopy  ) {

        // Save status of "-keychainHasUsernameAndPassword", "-keychainHasUsername", and "-keychainHasPrivateKey" because they are deleted by moveCredentials()
        BOOL havePwCredentials = keychainHasUsernameAndPasswordForDisplayName(sourceDisplayName);
        BOOL haveUnCredentials = keychainHasUsernameWithoutPasswordForDisplayName(sourceDisplayName);
        BOOL havePkCredentials = keychainHasPrivateKeyForDisplayName(sourceDisplayName);

        moveCredentials(sourceDisplayName, targetDisplayName);

        problemWithSettings = ( ! [gTbDefaults movePreferencesFrom: sourceDisplayName to: targetDisplayName] );

       if (  havePwCredentials  ) {
            [gTbDefaults setBool: TRUE forKey: [targetDisplayName stringByAppendingString: @"-keychainHasUsernameAndPassword"]];
        }
        if (  haveUnCredentials  ) {
            [gTbDefaults setBool: TRUE forKey: [targetDisplayName stringByAppendingString: @"-keychainHasUsername"]];
        }
        if (  havePkCredentials  ) {
            [gTbDefaults setBool: TRUE forKey: [targetDisplayName stringByAppendingString: @"-keychainHasPrivateKey"]];
        }

    } else {

        copyCredentials(sourceDisplayName, targetDisplayName);
        problemWithSettings = ( ! [gTbDefaults copyPreferencesFrom: sourceDisplayName to: targetDisplayName] );
    }

    return ( ! problemWithSettings );
}

+(void) copyOrMoveConfigurationsIntoNewFolder: (NSArray *) displayNames moveNotCopy: (BOOL) moveNotCopy {

    NSString * firstDisplayName = [displayNames firstObject];
    if (  ! firstDisplayName  ) {
        NSLog(@"copyOrMoveConfigurationsIntoNewFolder: no names");
        return;
    }

    NSDictionary * pathsDictionary = [gMC myConfigDictionary];

    NSString * firstSourcePath = [pathsDictionary objectForKey: firstDisplayName];
    if (  ! firstSourcePath  ) {
        NSLog(@"copyOrMoveConfigurationsIntoNewFolder: no configPath for %@", firstDisplayName);
        return;
    }

    NSString * untitledFolderName = NSLocalizedString(@"untitled folder", @"File name of a newly-created folder");
    NSString * newPath = [[firstSourcePath stringByDeletingLastPathComponent] stringByAppendingPathComponent: untitledFolderName];
    NSString * targetFolderPath = pathWithNumberSuffixIfItemExistsAtPath(newPath, NO);
    if (  ! targetFolderPath  ) {
        return; // Error, couldn't get a path
    }

    NSString * prompt = NSLocalizedString(@"Tunnelblick needs authorization to copy or move configurations.", @"Window text");
    SystemAuth * auth = [SystemAuth newAuthWithPrompt: prompt];
    if (   ! auth  ) {
        return;
    }

    NSString * sourceName;
    NSEnumerator * e = [displayNames objectEnumerator];
    while (  (sourceName = [e nextObject]  )  ) {

        NSString * sourcePath = [pathsDictionary objectForKey: sourceName];
        if (  ! firstDisplayName  ) {
            NSLog(@"copyOrMoveConfigurationsIntoNewFolder: no configPath for %@", sourceName);
            return;
        }

        NSString * targetPath = [targetFolderPath stringByAppendingPathComponent: [sourcePath lastPathComponent]];
        NSNumber * moveNotCopyNumber = [NSNumber numberWithBool: moveNotCopy];
        NSMutableString * result = [[[NSMutableString alloc] initWithCapacity: 1000] autorelease];
        NSDictionary * dict2 = [NSDictionary dictionaryWithObjectsAndKeys:
                                sourcePath,        @"sourcePath",
                                targetPath,        @"targetPath",
                                auth,              @"auth",
                                @YES,              @"warnDialog",
                                moveNotCopyNumber, @"moveNotCopy",
                                @NO,               @"noAdmin",
                                result,            @"result",
                                nil];
        [gMC
         performSelectorOnMainThread: @selector(moveOrCopyOneConfigurationUsingConfigurationManager:) withObject: dict2 waitUntilDone: YES];
        if ( [result length] != 0  ) {
            break;
        }
    }

    [auth release];
}

+(void) renameConfigurationFolder: (NSDictionary *) dict {

    NSString   * sourceDisplayName = [dict objectForKey: @"sourceDisplayName"];
    NSString   * targetDisplayName = [dict objectForKey: @"targetDisplayName"];
    SystemAuth * auth              = [dict objectForKey: @"auth"];

    // Move folders in both Shared and private (installer will copy private to secure if appropriate)
    NSArray * folders = [NSArray arrayWithObjects: L_AS_T_SHARED, gPrivatePath, nil];
    NSEnumerator * e = [folders objectEnumerator];
    NSString * folder;
    while (  (folder = [e nextObject])  ) {
        NSString * fullSourcePath = [folder stringByAppendingPathComponent: sourceDisplayName];
        NSString * fullTargetPath = [folder stringByAppendingPathComponent: targetDisplayName];

        if (   [gFileMgr fileExistsAtPath: fullSourcePath]  ) {
            if (  ! [gFileMgr fileExistsAtPath: fullTargetPath]  ) {
                NSArray * arguments = [NSArray arrayWithObjects: fullTargetPath, fullSourcePath, nil];
                NSInteger installerResult = [gMC runInstaller: INSTALLER_MOVE
                                                                                extraArguments: arguments
                                                                               usingSystemAuth: auth
                                                                                  installTblks: nil];
                if (  installerResult != 0  ) {
                    NSLog(@"Could not rename folder '%@' to '%@'", fullSourcePath, fullTargetPath);
                }
            } else {
                NSLog(@"Item exists at '%@'", fullTargetPath);
            }
        }
    }

    // Move preferences and credentials of configurations that have, in effect, been moved by the rename.

    BOOL ok = TRUE;

    NSArray * configurations = [[gMC myConfigDictionary] allValues];
    e = [configurations objectEnumerator];
    NSString * path;
    while (  (path = [e nextObject])  ) {
        NSString * thisSourceLastPart = lastPartOfPath(path);
        if (  [thisSourceLastPart hasPrefix: sourceDisplayName]  ) {
            NSString * thisSourceDisplayName = [thisSourceLastPart stringByDeletingPathExtension];
            NSString * thisSourceDisplayNameAfterSourceDisplayName = [thisSourceDisplayName substringFromIndex: [sourceDisplayName length]];
            NSString * thisTargetDisplayName = [targetDisplayName stringByAppendingPathComponent: thisSourceDisplayNameAfterSourceDisplayName];
            ok = ok && [self moveOrCopyCredentialsAndSettingsFrom: thisSourceDisplayName to: thisTargetDisplayName moveNotCopy: YES];
        }
    }

    // Change the preference *values* that reference the old folder to reference the new one
    [gTbDefaults replacePrefixOfPreferenceValuesThatHavePrefix: sourceDisplayName with: targetDisplayName];

    [gMC configurationsChangedForceLeftNavigationUpdate];
}

+(void) renameConfiguration: (NSDictionary *) dict {

    NSString   * sourcePath = [dict objectForKey: @"sourcePath"];
    NSString   * targetPath = [dict objectForKey: @"targetPath"];
    SystemAuth * auth       = [dict objectForKey: @"auth"];

    if (  [self copyConfigPath: sourcePath
                        toPath: targetPath
               usingSystemAuth: auth
                    warnDialog: YES
                   moveNotCopy: YES
                       noAdmin: NO]  ) {

        NSString * sourceName = [lastPartOfPath(sourcePath) stringByDeletingPathExtension];
        NSString * targetName = [lastPartOfPath(targetPath) stringByDeletingPathExtension];
        [self moveOrCopyCredentialsAndSettingsFrom: sourceName to: targetName moveNotCopy: YES];

    } else {
		TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
						  NSLocalizedString(@"Rename failed; see the Console Log for details.", @"Window text"));
	}
}

+(NSArray *) displayNamesFromPaths: (NSArray *) paths {
    
    NSMutableArray * displayNames = [[[NSMutableArray alloc] init] autorelease];
    NSString * path;
    NSEnumerator * e = [paths objectEnumerator];
    while (  (path = [e nextObject])  ) {
        NSString * displayName = (  firstPartOfPath(path)
                                  ? [lastPartOfPath(path)     stringByDeletingPathExtension]
                                  : [[path lastPathComponent] stringByDeletingPathExtension]);
        [displayNames addObject: displayName];
    }
    
    return [NSArray arrayWithArray: displayNames];
}

+(NSDictionary *) getInfoPlistForDisplayName: (NSString*) displayName {

	// Get the Info.plist from the shadow configuration
	NSString * infoPlistPath = [[[[[L_AS_T_USERS
									stringByAppendingPathComponent: NSUserName()]
								   stringByAppendingPathComponent: displayName]
								  stringByAppendingPathExtension: @"tblk"]
								 stringByAppendingPathComponent: @"Contents"]
								stringByAppendingPathComponent: @"Info.plist"];
	if (  ! [gFileMgr fileExistsAtPath: infoPlistPath]  ) {
		TBLog(@"DB-UC", @"getInfoPlist: No Info.plist for %@", displayName);
		return nil;
	}

	NSDictionary * infoPlist = [NSDictionary dictionaryWithContentsOfFile: infoPlistPath];
	if (  ! infoPlist  ) {
		NSLog(@"getInfoPlist: Info.plist for %@ cannot be read and parsed", displayName);
		return nil;
	}

	return infoPlist;
}

+(NSData *) getDataFromUrlString: (NSString *) urlString {

	NSString * escapedUrlString = [urlString stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
	if (  ! escapedUrlString  ) {
		NSLog(@"getDataFromUrlString: UpdateURL entry cannot be percent-escaped: %@", urlString);
		return nil;
	}

	NSURL * updateUrl = [NSURL URLWithString: escapedUrlString];
	if (  ! updateUrl  ) {
		NSLog(@"getDataFromUrlString: UpdateURL cannot be parsed: %@", urlString);
		return nil;
	}

	TBLog(@"DB-UC", @"getDataFromUrlString: Attempting to fetch '%@'", urlString);
	NSURLRequest * urlRequest = [NSURLRequest requestWithURL: updateUrl
												 cachePolicy: NSURLRequestReloadIgnoringLocalAndRemoteCacheData
											 timeoutInterval: 30.0];
	if (  ! urlRequest  ) {
		NSLog(@"getDataFromUrlString: Unable to create URL request with URL from %@", urlString);
		return nil;
	}

	NSHTTPURLResponse * urlResponse = nil;
	NSError * urlError = nil;
	NSData * urlData = [NSURLConnection sendSynchronousRequest: urlRequest
											 returningResponse: &urlResponse
														 error: &urlError];
	if (  ! urlData  ) {
		NSLog(@"getDataFromUrlString: Unable to connect within 30 seconds to %@\nError was %@", urlString, urlError);
		return nil;
	}

	NSUInteger statusCode = 0;
	if (  (statusCode = [urlResponse statusCode]) != 200  ) {
		NSLog(@"getDataFromUrlString: Response code %lu ('%@') to GET %@\nError was %@",
			  (unsigned long)statusCode, [NSHTTPURLResponse localizedStringForStatusCode: statusCode], urlString, urlError);
		return nil;
	}

	TBLog(@"DB-UC", @"getDataFromUrlString: Fetched %lu bytes from '%@'", [urlData length], urlString);
	return urlData;
}

+(NSData *) getDataFromUrlUsingKey: (NSString *)     key
					  inDictionary: (NSDictionary *) dict
						withSuffix: (NSString *)     suffix {

	NSString * urlString = [dict objectForKey: key];
	if (  ! urlString  ) {
		TBLog(@"DB-UC",@"getDataFromUrlUsingKey: No %@ key", key);
		return nil;
	}

	if (  ! [urlString hasPrefix: @"https://"]  ) {
		NSLog(@"Configuration update URL is not https:// (%@)", urlString);
		return nil;
	}

	NSData * data = [self getDataFromUrlString: [urlString stringByAppendingString: suffix]];

	return data;
}

+(NSString *) getStringFromUrlUsingKey: (NSString *)	 key
						  inDictionary: (NSDictionary *) dict
							withSuffix: (NSString *)	 suffix {

	NSData * data = [self getDataFromUrlUsingKey: key inDictionary: dict withSuffix: (NSString *) suffix];
	if (  ! data  ) {
		return nil;
	}

	NSString * string = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
	if (  ! string  ) {
		NSLog(@"getStringFromUrlUsingKey: Can't get object for %@", key);
		return nil;
	}

	TBLog(@"DB-UC", @"getStringFromUrlUsingKey: Obtained '%@'", string);
	return string;
}

+(NSDictionary *) getUpdateInfoForDisplayName: (NSString *) displayName {

	// If an update is available, returns the URL string for the .zip file containing the update

	NSDictionary * infoPlist = [ConfigurationManager getInfoPlistForDisplayName: displayName];
	if (  ! infoPlist  ) {
		TBLog(@"DB-UC",@"configurationUpdateDataForDisplayName: No Info.plist for %@", displayName);
		return nil;
	}

	NSString * currentVersionString = [infoPlist objectForKey: @"CFBundleVersion"];
	if (  ! currentVersionString  ) {
		TBLog(@"DB-UC",@"configurationUpdateData: No CFBundleVersion");
		return nil;
	}

	NSString * updateVersionString = [ConfigurationManager getStringFromUrlUsingKey: @"TBConfigurationUpdateURL"
																	   inDictionary: infoPlist
																		 withSuffix: @"/version.txt"];
	if (  ! updateVersionString  ) {
		TBLog(@"DB-UC",@"configurationUpdateData: No data from ConfigurationUpdate version");
		return nil;
	}

	if (  [updateVersionString tunnelblickVersionCompare: currentVersionString] != NSOrderedDescending) {
		TBLog(@"DB-UC",@"configurationUpdateData: Configuration is up to date: current = '%@'; update = '%@'", currentVersionString, updateVersionString);
		return nil;
	}

	TBLog(@"DB-UC", @"configurationUpdateData: Update is available; current = '%@'; update = '%@'", currentVersionString, updateVersionString);

	NSString * zipURLString = [[infoPlist objectForKey: @"TBConfigurationUpdateURL"] stringByAppendingString: @"/config.tblk.zip"];

	return [NSDictionary dictionaryWithObjectsAndKeys:
			updateVersionString, @"updateVersionString",
			zipURLString, 		 @"updateZipURLString", nil];
}

+(NSString *) updatePathForDisplayName: (NSString *)     displayName
							updateInfo: (NSDictionary *) updateInfo {

	// Copy the update into the unsecured copy of the configuration

	// Get the update data
	NSString * updateZipURLString = [updateInfo objectForKey: @"updateZipURLString"];
	NSData * zipData = [ConfigurationManager getDataFromUrlString: updateZipURLString];
	if (  ! zipData  ) {
		TBLog(@"DB-UC",@"No update is available for %@ at %@", displayName, updateZipURLString);
		return nil;
	}

	// Store the update data in a temporary .zip file
	NSString * zipPath = [newTemporaryDirectoryPath()
						  stringByAppendingPathComponent: @"configuration-update.zip"];
	if (  ! [gFileMgr createFileAtPath: zipPath contents: zipData attributes: nil]  ) {
		NSLog(@"Unable to create %lu bytes of data at %@", [zipData length], zipPath);
		return nil;
	}

	// Expand the .zip into a temporary folder
	//
	// macOS doesn't have any built-in system call to expand .zip files but does have a tar command
	// that does, so rather than add a dependancy just to expand the file, we accept the performance
	// degradation of calling an external program to do the expansion.
	
	NSString * targetFolderPath = [[newTemporaryDirectoryPath()
									stringByAppendingPathComponent: displayName]
								   stringByAppendingPathExtension: @"tblk"];
	if (  ! [gFileMgr tbCreateDirectoryAtPath: targetFolderPath withIntermediateDirectories: YES attributes: nil]  ) {
		[gFileMgr tbRemoveFileAtPath: [zipPath          stringByDeletingLastPathComponent] handler: nil];
		[gFileMgr tbRemoveFileAtPath: [targetFolderPath stringByDeletingLastPathComponent] handler: nil];
		return nil;
	}
	NSArray * arguments = [NSArray arrayWithObjects:
						   @"-x",
						   @"--exclude",          @"__MACOSX",
						   @"--strip-components", @"1",
						   @"-C",                 targetFolderPath,
						   @"-f",                 zipPath,
						   nil];
	if (  EXIT_SUCCESS == runTool(TOOL_PATH_FOR_TAR, arguments, nil, nil)  ) {

		[gFileMgr tbRemoveFileAtPath: [zipPath stringByDeletingLastPathComponent] handler: nil];

		// Get a list of files or folders that start with a period, then delete them
		NSString * file;
		NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: targetFolderPath];
		NSMutableArray * filesToDelete = [[[NSMutableArray alloc] initWithCapacity: 10] autorelease];
		while (  (file = [dirEnum nextObject])  ) {
			if (   [file hasPrefix: @"."]
				|| ([file rangeOfString: @"/."].length != 0)  ) {
				[dirEnum skipDescendants];
				[filesToDelete addObject: file];
			}
		}
		NSEnumerator * e = [filesToDelete objectEnumerator];
		while (  (file = [e nextObject])  ) {
			NSString * fullPath = [targetFolderPath stringByAppendingPathComponent: file];
			if (  [gFileMgr tbRemoveFileAtPath: fullPath handler: nil]  ) {
				TBLog(@"DB-UC", @"Removed invisible file or folder %@", fullPath)
			}
		}

		// Check that the version number in the configuration in the .zip is as expected
		NSString * targetInfoPlistPath = [[targetFolderPath
										   stringByAppendingPathComponent: @"Contents"]
										  stringByAppendingPathComponent: @"Info.plist"];
		NSDictionary * newInfoPlist = [NSDictionary dictionaryWithContentsOfFile: targetInfoPlistPath];
		NSString * newVersion = [newInfoPlist objectForKey: @"CFBundleVersion"];
		NSString * expectedVersion = [updateInfo objectForKey: @"updateVersionString"];
		if (  ! [newVersion isEqualToString: expectedVersion]  ) {
			NSLog(@"Update configuration is version %@; expected version %@", newVersion, expectedVersion);
			[gFileMgr tbRemoveFileAtPath: [targetFolderPath stringByDeletingLastPathComponent] handler: nil];
			return nil;
		}

		return targetFolderPath;
	}

	NSLog(@"Error expanding file (%lu bytes long) at %@", [zipData length], zipPath);
	[gFileMgr tbRemoveFileAtPath: [targetFolderPath stringByDeletingLastPathComponent] handler: nil];
	return nil;
}

+(BOOL) makeShadowCopyMatchConfigurationWithDisplayName: (NSString *)	  displayName
											 updateInfo: (NSDictionary *) updateInfo
											thenConnect: (BOOL)			  thenConnect
											  userKnows: (BOOL)			  userKnows {

	// Returns TRUE if updated or skipped update or secured or reverted.
	// Returns FALSE only user cancelled or an error occurred.

	int result;

	if (  updateInfo  ) {
		result = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
								 [NSString stringWithFormat: NSLocalizedString(@"An update to the %@ VPN configuration is available.\n\n"
																			   @"Do you wish to update the configuration?\n\n",
																			   @"Window text; the %@ will be replaced by the name of a configuration."), displayName],
								 NSLocalizedString(@"Update",		    @"Button. 'Update' refers to the update of a configuration."),  // Default
								 NSLocalizedString(@"Cancel",		    @"Button"),  // Alternate
								 NSLocalizedString(@"Skip this Update", @"Button. 'Update' refers to the update of a configuration.")); // Other
	} else {
		result = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
								 [NSString stringWithFormat: NSLocalizedString(@"The %@ VPN configuration has been modified since it was last secured.\n\n"
																			   @"Do you wish to secure the modified configuration or revert to the last secured configuration?\n\n",
																			   @"Window text; the %@ will be replaced by the name of a configuration."), displayName],
								 NSLocalizedString(@"Secure the Configuration",		   @"Button"),  // Default
								 NSLocalizedString(@"Cancel",						   @"Button"),  // Alternate
								 NSLocalizedString(@"Revert to the Last Secured Copy", @"Button")); // Other
	}

	switch (  result  ) {

		case NSAlertAlternateReturn: // Cancel
			TBLog(@"DB-UC",@"Cancelled updating or securing for %@", displayName);
			return NO;
			break;

		case NSAlertDefaultReturn: // Update or Secure the Configuration
			TBLog(@"DB-UC",@"Updating or securing %@", displayName);
			if (  updateInfo  ) {

				NSString * updatePath = [ConfigurationManager updatePathForDisplayName: displayName updateInfo: updateInfo];
				if (  updatePath == nil  ) {
					TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
									  [NSString stringWithFormat:
									   NSLocalizedString(@"Could not obtain the updated version of configuration '%@'. See the Console Log for details.", @"Window text."), displayName]);
					return NO;
				}
				NSString * unsecuredPrivatePath = [[gPrivatePath
													stringByAppendingPathComponent: displayName]
												   stringByAppendingPathExtension: @"tblk"];
				if (  ! [gFileMgr tbForceRenamePath: updatePath toPath: unsecuredPrivatePath]  ) {
					return NO;
				}
				[gFileMgr tbRemoveFileAtPath:  [updatePath stringByDeletingLastPathComponent] handler: nil];
				if (  ! [ConfigurationManager createShadowCopyWithDisplayName: displayName]  ) {
					return NO;
				}
				if (  thenConnect  ) {
					VPNConnection * connection = [gMC connectionForDisplayName: displayName];
					[connection connectOnMainThreadUserKnows: [NSNumber numberWithBool: userKnows]];
				}
				return YES;
			} else {
				return [ConfigurationManager createShadowCopyWithDisplayName: displayName];
			}
			break;

		case NSAlertOtherReturn: // Skip the Update or Revert to the Last Secured Copy
			if (  updateInfo  ) {
				TBLog(@"DB-UC",@"Skipping an update for %@", displayName);
				if (  thenConnect  ) {
					VPNConnection * connection = [gMC connectionForDisplayName: displayName];
					[connection setSkipConfigurationUpdateCheckOnce: TRUE];
					[connection connectOnMainThreadUserKnows: [NSNumber numberWithBool: userKnows]];
				}
				return YES;
			} else {
				TBLog(@"DB-UC",@"Reverting %@", displayName);
				BOOL reverted = [ConfigurationManager revertOneConfigurationToShadowWithDisplayName: displayName];
				if (  reverted  ) {
					if (  thenConnect  ) {
						VPNConnection * connection = [gMC connectionForDisplayName: displayName];
						[connection connectOnMainThreadUserKnows: [NSNumber numberWithBool: userKnows]];
					}
				}
				return reverted;

			}
			break;

		default:
			NSLog(@"Unexpected result from TBRunAlertPanel: %d", result);
			return NO;
	}
}

+(BOOL) createShadowCopyWithDisplayName: (NSString *) displayName {
    
	// Try without admin approval first
	if (  okToUpdateConfigurationsWithoutAdminApproval()  ) {

		NSArray * arguments = [NSArray arrayWithObjects: @"safeUpdate", displayName, nil];
		OSStatus status = runOpenvpnstart(arguments, nil, nil);

		switch (  status  ) {

			case OPENVPNSTART_UPDATE_SAFE_OK:
				return YES;
				break;

			case OPENVPNSTART_UPDATE_SAFE_NOT_OK:
				// Fall through to do admin-authorized copy
				break;

			default:
				NSLog(@"doSafeUpdateOfConfigWithDisplayName: safeUpdateTest of '%@' returned unknown code %d", displayName, status);
				// Fall through to do admin-authorized copy
				break;
		}
	}

	// Get admin approval because it isn't a "safe" update

    NSString * prompt = NSLocalizedString(@"Tunnelblick needs to create or update a secure (shadow) copy of the configuration file.", @"Window text");
    SystemAuth * auth = [[SystemAuth newAuthWithPrompt: prompt] autorelease];
    if (   ! auth  ) {
        return NO;
    }
    
    NSString * cfgPath = [[gMC myConfigDictionary] objectForKey: displayName];
    if (  cfgPath  ) {
        NSString * altCfgPath = [[L_AS_T_USERS stringByAppendingPathComponent: NSUserName()]
                                 stringByAppendingPathComponent: lastPartOfPath(cfgPath)];
        
        if ( [ConfigurationManager copyConfigPath: cfgPath
                                           toPath: altCfgPath
                                  usingSystemAuth: auth
                                       warnDialog: YES
                                      moveNotCopy: NO
                                          noAdmin: NO] ) {    // Copy the config to the alt config
            NSLog(@"Created or updated secure (shadow) copy of configuration file %@", cfgPath);
			return YES;
        } else {
            NSLog(@"Unable to create or update secure (shadow) copy of configuration file %@", cfgPath);
        }
    } else {
        NSLog(@"createShadowCopyWithDisplayName: No configuration path for '%@'", displayName);
    }
    
	return NO;
}


+(NSString *) listOfFilesInTblkForConnection: (VPNConnection *) connection {
    
    NSString * configPath = [connection configPath];
    NSString * configPathTail = [configPath lastPathComponent];
    
    if (  [configPath hasSuffix: @".tblk"]  ) {
		NSArray * keyAndCrtExtensions = KEY_AND_CRT_EXTENSIONS;
        NSMutableString * fileListString = [[[NSMutableString alloc] initWithCapacity: 10000] autorelease];
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: configPath];
        NSString * filename;
        while (  (filename = [dirEnum nextObject])  ) {
			BOOL isDir;
			if (   [gFileMgr fileExistsAtPath: [configPath stringByAppendingPathComponent: filename] isDirectory: &isDir]
				&& ( ! isDir )  ) {
				NSString * extension  = [filename pathExtension];
				
				// Obfuscate key and certificate filenames by truncating them after the first three characters
				if (  [keyAndCrtExtensions containsObject: extension]  ) {
					NSString * folderName = [filename stringByDeletingLastPathComponent];
					if (  [folderName length] != 0  ) {
						folderName = [folderName stringByAppendingString: @"/"];
					}
					NSString * filenameOnly = [[filename lastPathComponent] stringByDeletingPathExtension];
					NSString * filenameOnlyObfuscated = (  ([filenameOnly length] > 3)
														 ? [[filenameOnly substringToIndex: 3] stringByAppendingString: @"…"]
														 : filenameOnly);
					[fileListString appendFormat: @"      %@%@.%@\n", folderName, filenameOnlyObfuscated, extension];
				} else {
					[fileListString appendFormat: @"      %@\n", filename];
				}
			}
		}

        return (  ([fileListString length] == 0)
                ? [NSString stringWithFormat: @"There are no files in %@\n", configPathTail]
                : [NSString stringWithFormat: @"Files in %@:\n%@", configPathTail, fileListString]);
    } else {
        return [NSString stringWithFormat: @"Cannot list files in %@; not a .tblk\n", configPathTail];
    }
}

+(NSString *) stringFromLogEntry: (NSDictionary *) dict {
    
    // Returns a string with a console log entry, terminated with a LF
    
    NSString * timestampS = [dict objectForKey: [NSString stringWithUTF8String: ASL_KEY_TIME]];
	NSString * nSecondsS  = [dict objectForKey: [NSString stringWithUTF8String: ASL_KEY_TIME_NSEC]];
    NSString * senderS    = [dict objectForKey: [NSString stringWithUTF8String: ASL_KEY_SENDER]];
    NSString * pidS       = [dict objectForKey: [NSString stringWithUTF8String: ASL_KEY_PID]];
    NSString * msgS       = [dict objectForKey: [NSString stringWithUTF8String: ASL_KEY_MSG]];
    
	if (  [nSecondsS length] > 9  ) {
		NSLog(@"ASL_KEY_TIME_NSEC is longer than 9 characters!!!");
		[gMC terminateBecause: terminatingBecauseOfError];
		return @"";
	}
	
	NSString * timeWithNs = [NSString stringWithFormat: @"%@.%@%@",
							 timestampS,
							 [@"000000000" substringFromIndex: [nSecondsS length]],
							 nSecondsS];
    NSDate * dateTime = [NSDate dateWithTimeIntervalSince1970: (NSTimeInterval) [timeWithNs doubleValue]];
	NSString * timeString = [dateTime tunnelblickUserLogRepresentation];

    NSString * senderString = [NSString stringWithFormat: @"%@[%@]", senderS, pidS];
    
	// Set up to indent continuation lines by converting newlines to \n (i.e., "backslash n")
	NSMutableString * msgWithBackslashN = [[msgS mutableCopy] autorelease];
	[msgWithBackslashN replaceOccurrencesOfString: @"\n"
									   withString: @"\\n"
										  options: 0
											range: NSMakeRange(0, [msgWithBackslashN length])];
	
    return [NSString stringWithFormat: @"%@ %21@ %@\n", timeString, senderString, msgWithBackslashN];
}

+(NSString *) stringContainingRelevantConsoleLogEntries {
    
    // Returns a string with relevant entries from the Console log
    
	// First, search the log for all entries fewer than six hours old from Tunnelblick or openvpnstart
    // And append them to tmpString
	
	NSMutableString * tmpString = [NSMutableString string];
    
    aslmsg q = asl_new(ASL_TYPE_QUERY);
	time_t sixHoursAgoTimeT = time(NULL) - 6 * 60 * 60;
	const char * sixHoursAgo = [[NSString stringWithFormat: @"%ld", (long) sixHoursAgoTimeT] UTF8String];
    asl_set_query(q, ASL_KEY_TIME, sixHoursAgo, ASL_QUERY_OP_GREATER_EQUAL | ASL_QUERY_OP_NUMERIC);
    aslresponse r = asl_search(NULL, q);
    
    aslmsg m;
    while (NULL != (m = aslresponse_next(r))) {
        
        NSMutableDictionary *tmpDict = [NSMutableDictionary dictionary];
        
        BOOL includeDict = FALSE;
        const char * key;
        const char * val;
        unsigned i;
        for (  i = 0; (NULL != (key = asl_key(m, i))); i++  ) {
            val = asl_get(m, key);
            if (  val  ) {
                NSString * string    = [NSString stringWithUTF8String: val];
                NSString * keyString = [NSString stringWithUTF8String: key];
                if (  ! string  ) {
                    NSLog(@"stringContainingRelevantConsoleLogEntries: string = nil; keyString = '%@'", keyString);
                    continue;
                }
                if (  ! keyString  ) {
                    NSLog(@"stringContainingRelevantConsoleLogEntries: keyString = nil; string = '%@'", string);
                    continue;
                }
                [tmpDict setObject: string forKey: keyString];
                
                if (  [keyString isEqualToString: [NSString stringWithUTF8String: ASL_KEY_SENDER]]  ) {
                    if (   [string isEqualToString: @"Tunnelblick"]
                        || [string isEqualToString: @"atsystemstart"]
                        || [string isEqualToString: @"installer"]
                        || [string isEqualToString: @"openvpnstart"]
                        || [string isEqualToString: @"process-network-changes"]
                        || [string isEqualToString: @"standardize-scutil-output"]
                        || [string isEqualToString: @"tunnelblickd"]
                        || [string isEqualToString: @"tunnelblick-helper"]
                        ) {
                        includeDict = TRUE;
                    }
                } else if (  [keyString isEqualToString: [NSString stringWithUTF8String: ASL_KEY_MSG]]  ) {
                    if (   ([string rangeOfString: @"Tunnelblick"].length != 0)
                        || ([string rangeOfString: @"tunnelblick"].length != 0)
                        || ([string rangeOfString: @"Tunnel" "blick"].length != 0)      // Include non-rebranded references to Tunnelblick
                        || ([string rangeOfString: @"atsystemstart"].length != 0)
                        || ([string rangeOfString: @"installer"].length != 0)
                        || ([string rangeOfString: @"openvpnstart"].length != 0)
                        || ([string rangeOfString: @"Saved crash report for openvpn"].length != 0)
                        || ([string rangeOfString: @"process-network-changes"].length != 0)
                        || ([string rangeOfString: @"standardize-scutil-output"].length != 0)
                        ) {
						if (  [string rangeOfString: @"Google Software Update installer"].length == 0  ) {
							includeDict = TRUE;
						}
                    }
                }
            }
		}
		
		if (  includeDict  ) {
			[tmpString appendString: [ConfigurationManager stringFromLogEntry: tmpDict]];
		}
	}
	
	aslresponse_free(r);
	
	// Next, extract the tail of the entries -- the last 200 lines of them
	// (The loop test is "i<201" because we look for the 201-th newline from the end of the string; just after that is the
	//  start of the 200th entry from the end of the string.)
    
	NSRange tsRng = NSMakeRange(0, [tmpString length]);	// range we are looking at currently; start with entire string
    unsigned i;
	unsigned offset = 2;
    BOOL fewerThan200LinesInLog = FALSE;
	for (  i=0; i<201; i++  ) {
		NSRange nlRng = [tmpString rangeOfString: @"\n"	// range of last newline at end of part we are looking at
										 options: NSBackwardsSearch
										   range: tsRng];
		
		if (  nlRng.length == 0  ) {    // newline not found (fewer than 200 lines in tmpString);  set up to start at start of string
			offset = 0;
            fewerThan200LinesInLog = TRUE;
			break;
		}
		
        if (  nlRng.location == 0  ) {  // newline at start of string (shouldn't happen, but...)
			offset = 1;					// set up to start _after_ the newline
            fewerThan200LinesInLog = TRUE;
            break;
        }
        
		tsRng.length = nlRng.location - 1; // change so looking before that newline 
	}
    
    if (  fewerThan200LinesInLog  ) {
        tsRng.length = 0;
    }
    
	NSString * tail = [tmpString substringFromIndex: tsRng.length + offset];
	
	// Finally, indent continuation lines
	NSMutableString * indentedMsg = [[tail mutableCopy] autorelease];
	[indentedMsg replaceOccurrencesOfString: @"\\n"
								 withString: @"\n                                       " // Note all the spaces in the string
									options: 0
									  range: NSMakeRange(0, [indentedMsg length])];
	return indentedMsg;	
}

+(NSString *) getPreferences: (NSArray *) prefsArray prefix: (NSString *) prefix {
    
    NSMutableString * string = [[[NSMutableString alloc] initWithCapacity: 1000] autorelease];
    
    NSEnumerator * e = [prefsArray objectEnumerator];
    NSString * keySuffix;
    while (  (keySuffix = [e nextObject])  ) {
        NSString * key = [prefix stringByAppendingString: keySuffix];
		id obj = [gTbDefaults objectForKey: key];
		if (  obj  ) {
			if (  [key isEqualToString: @"installationUID"]  ) {
				[string appendFormat: @"%@ (not shown)\n", key];
			} else {
				[string appendFormat: @"%@ = %@%@\n", keySuffix, obj, (  [gTbDefaults canChangeValueForKey: key]
																	   ? @""
																	   : @" (forced)")];
			}
		}
    }
    
    return [NSString stringWithString: string];
}

+(NSString *) stringWithIfconfigOutput {
    
    NSString * ifconfigOutput = @""; // stdout (ignore stderr)
	
    OSStatus status = runTool(TOOL_PATH_FOR_IFCONFIG,
                              [NSArray array],
                              &ifconfigOutput,
                              nil);
    
    if (  status != EXIT_SUCCESS) {
        return [NSString stringWithFormat: @"An error occurred while trying to execute 'ifconfig'; output was '%@'", ifconfigOutput];
    }
    
    return ifconfigOutput;
}
+(NSString *) nonAppleKextContents {
    
    NSString * kextRawContents = @""; // stdout (ignore stderr)
	
    OSStatus status = runTool(TOOL_PATH_FOR_BASH,
                              [NSArray arrayWithObjects:
                               @"-c",
                               [TOOL_PATH_FOR_KEXTSTAT stringByAppendingString: @" | grep -v com.apple"],
                               nil],
                              &kextRawContents,
                              nil);
    
    if (  status != EXIT_SUCCESS) {
        return [NSString stringWithFormat: @"An error occurred while trying to execute 'bash', 'kextstat', or 'grep'; output was '%@'", kextRawContents];
    }
    
    return kextRawContents;
}

+(NSString *) gitInfo {
    
    NSDictionary * dict = [gMC tunnelblickInfoDictionary];
    
    NSString * gitMessage;
    NSString * hashValue = [dict objectForKey: @"TBGitHash"];
    if (  [hashValue isEqualToString: @"TBGITHASH"]  ) {
        gitMessage = @"No git information is available\n";
    } else {
        NSString * statusValue = [dict objectForKey: @"TBGitStatus"];
        gitMessage = (  [statusValue isEqualToString: @""]
                      ? [NSString stringWithFormat: @"git commit %@\n", hashValue]
                      : [NSString stringWithFormat: @"git commit %@ + uncommitted changes:\n%@\n", hashValue, statusValue]);
    }
    
    return gitMessage;
}

+(NSString *) networkServicesInfo {

	NSString * listOfServices = @""; // stdout (ignore stderr)
	OSStatus status = runTool(TOOL_PATH_FOR_NETWORKSETUP,
							  [NSArray arrayWithObject: @"-listallnetworkservices"],
							  &listOfServices,
							  nil);
	if (  status != EXIT_SUCCESS  ) {
		return [NSString stringWithFormat: @"An error occurred while trying to execute '%@ -listallnetworkservices'; output was '%@'", TOOL_PATH_FOR_NETWORKSETUP, listOfServices];
	}
	
	NSString * wifiInterfaceName = @""; // stdout (ignore stderr)
	runTool(TOOL_PATH_FOR_BASH,
			[NSArray arrayWithObjects:
			 @"-c",
			 [TOOL_PATH_FOR_NETWORKSETUP stringByAppendingString: @" -listallhardwareports | awk '$3==\"Wi-Fi\" {getline; print $2}' | tr -d '\\n'"],
			 nil],
			&wifiInterfaceName,
			nil);
	if (  [wifiInterfaceName length] == 0  ) {
		runTool(TOOL_PATH_FOR_BASH,
				[NSArray arrayWithObjects:
				 @"-c",
				 [TOOL_PATH_FOR_NETWORKSETUP stringByAppendingString: @" -listallhardwareports | awk '$3==\"AirPort\" {getline; print $2}' | tr -d '\\n'"],
				 nil],
				&wifiInterfaceName,
				nil);
	}

	NSString * wifiPowerStatus = @""; // stdout (ignore stderr)
	if (  [wifiInterfaceName length] == 0  ) {
		wifiPowerStatus = @"There are no network services named 'Wi-Fi' or 'AirPort'";
	} else {
		status = runTool(TOOL_PATH_FOR_NETWORKSETUP,
						 [NSArray arrayWithObjects: @"-getairportpower", wifiInterfaceName, nil],
						 &wifiPowerStatus,
						 nil);
		
		if (  status != EXIT_SUCCESS  ) {
			return [NSString stringWithFormat: @"An error occurred while trying to execute '%@ -getairportpower %@'; output was '%@'", TOOL_PATH_FOR_NETWORKSETUP, wifiInterfaceName, wifiPowerStatus];
		}
		
	}
	
	return [listOfServices stringByAppendingFormat: @"\n%@", wifiPowerStatus];
}

+(id) getForcedPreferencesAtPath: (NSString *) path {

    if (  [gFileMgr fileExistsAtPath: path]  ) {
        NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: path];
        if (  dict  ) {
            return dict;
        } else {
            return @"(File cannot be parsed)";
        }
    } else {
        return @"(None)";
    }
}


+(void) putDiagnosticInfoOnClipboardWithDisplayName: (NSString *) displayName log: (NSString *) logContents {
	
	NSPasteboard * pb = [NSPasteboard generalPasteboard];
	[pb declareTypes: [NSArray arrayWithObject: NSStringPboardType] owner: self];

	VPNConnection * connection = [gMC connectionForDisplayName: displayName];
    if (  connection  ) {
		
		[pb setString: @"You pasted too soon! The Tunnelblick diagnostic info was not yet available on the Clipboard when you pasted. Try to paste again.\n" forType: NSStringPboardType];

		// Get OS and Tunnelblick version info
		NSString * versionContents = [[gMC openVPNLogHeader] stringByAppendingString:
                                      (isUserAnAdmin()
                                       ? @"; Admin user\n"
                                       : @"; Standard user\n")];
        
        NSString * gitInfo = [self gitInfo];
		
         NSString * translationInfo = (  processIsTranslated()
                                      ? @"The Tunnelblick.app process is being translated\n"
                                      : @"The Tunnelblick.app process is not being translated\n");

        NSString * sipStatusInfo = (  runningWithSIPDisabled()
                                    ? @"System Integrity Protection is DISABLED\n"
                                    : @"System Integrity Protection is enabled\n");

        // Get contents of configuration file
        NSString * condensedConfigFileContents = [connection condensedSanitizedConfigurationFileContents ];
		if (  ! condensedConfigFileContents  ) {
			condensedConfigFileContents = @"(No configuration file found or configuration file could not be sanitized. See the Console Log for details.)";
		}
		
        // Get list of files in .tblk or message explaining why cannot get list
        NSString * tblkFileList = [ConfigurationManager listOfFilesInTblkForConnection: connection];

		// Get contents of kext policy database if available
		NSString * kextPolicyData = @"Kext Policy database not available (available only on macOS High Sierra and later)";
		if (  runningOnHighSierraOrNewer()  ) {
			NSString * stdOut = @"";
			NSString * stdErr = @"";
			int status = runOpenvpnstart(@[@"printTunnelblickKextPolicy"], &stdOut, &stdErr);
			if (   (status == 0)
				&& [stdErr length] == 0  ) {
				kextPolicyData = stdOut;
			} else {
				kextPolicyData = [NSString stringWithFormat:
								  @"Error status %d attempting to access the Kext Policy database\nstdout =\n%@\nstderr =\n%@",
								  status, stdOut, stdErr];
			}
		}

        // Get relevant preferences
        NSString * configurationPreferencesContents = [ConfigurationManager getPreferences: gConfigurationPreferences prefix: [connection displayName]];
        
        NSString * wildcardPreferencesContents      = [ConfigurationManager getPreferences: gConfigurationPreferences prefix: @"*"];
        
        NSString * programPreferencesContents       = [ConfigurationManager getPreferences: gProgramPreferences       prefix: @""];
        
        id primaryForcedPreferencesContents = [ConfigurationManager getForcedPreferencesAtPath: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH];

        id deployedForcedPreferencesContents = [ConfigurationManager getForcedPreferencesAtPath: [gDeployPath stringByAppendingPathComponent: @"forced-preferences.plist"]];

		if (  ! logContents  ) {
			logContents = @"(Unavailable)\n";
		}

		// Get list of network services and status of Wi-Fi
		NSString * networkServicesContents = [ConfigurationManager networkServicesInfo];
		
        // Get output of "ifconfig"
        NSString * ifconfigOutput = [self stringWithIfconfigOutput];
        
		// Get tail of Console log
        NSString * consoleContents = [self stringContainingRelevantConsoleLogEntries];
        
        NSString * kextContents = [self nonAppleKextContents];

		NSString * quitLogContents = [self stringWithFileContentsOrNotFound: TUNNELBLICK_QUIT_LOG_PATH];

		NSString * downLogContents = [self stringWithFileContentsOrNotFound: [L_AS_T stringByAppendingPathComponent: @"DownLog.txt"]];

		NSString * previousDownLogContents = [self stringWithFileContentsOrNotFound: [L_AS_T stringByAppendingPathComponent: @"DownLog.previous.txt"]];

		NSString * separatorString = @"================================================================================\n\n";
		
        NSString * output = [NSString stringWithFormat:
							 @"%@%@%@%@\n"  // Version info
                             @"Configuration %@\n\n"
                             @"\"Sanitized\" condensed configuration file for %@:\n\n%@\n\n%@"
                             @"%@\n%@"  // List of unusual files in .tblk (or message why not listing them)
							 @"Tunnelblick Kext Policy Data:\n\n%@\n%@"
                             @"Configuration preferences:\n\n%@\n%@"
                             @"Wildcard preferences:\n\n%@\n%@"
                             @"Program preferences:\n\n%@\n%@"
                             @"Forced preferences:\n\n%@\n\n%@"
                             @"Deployed forced preferences:\n\n%@\n\n%@"
                             @"Tunnelblick Log:\n\n%@\n%@"
							 @"Down log:\n\n%@\n%@"
							 @"Previous down log:\n\n%@\n%@"
							 @"Network services:\n\n%@\n%@"
                             @"ifconfig output:\n\n%@\n%@"
							 @"Non-Apple kexts that are loaded:\n\n%@\n%@"
							 @"Quit Log:\n\n%@\n%@"
							 @"Console Log:\n\n%@\n",
                             versionContents, gitInfo, translationInfo, sipStatusInfo,
                             [connection localizedName],
							 [connection configPath], condensedConfigFileContents, separatorString,
                             tblkFileList, separatorString,
							 kextPolicyData, separatorString,
                             configurationPreferencesContents, separatorString,
                             wildcardPreferencesContents, separatorString,
                             programPreferencesContents, separatorString,
                             primaryForcedPreferencesContents, separatorString,
                             deployedForcedPreferencesContents, separatorString,
                             logContents, separatorString,
							 downLogContents, separatorString,
							 previousDownLogContents, separatorString,
							 networkServicesContents, separatorString,
                             ifconfigOutput, separatorString,
							 kextContents, separatorString,
							 quitLogContents, separatorString,
                             consoleContents];
        
        pb = [NSPasteboard generalPasteboard];
        [pb declareTypes: [NSArray arrayWithObject: NSStringPboardType] owner: self];
        [pb setString: output forType: NSStringPboardType];
    } else {
		[pb setString: @"No diagnostic info is available because no configuration has been selected.\n" forType: NSStringPboardType];
        NSLog(@"diagnosticInfoToClipboardButtonWasClicked but no configuration selected");
    }
	
}

+(NSString *) stringWithFileContentsOrNotFound: (NSString *) filePath {

	NSString * s = [NSString stringWithContentsOfFile: filePath
											 encoding: NSUTF8StringEncoding
												error: nil];
	if ( ! s ) {
		s = @"(Not found)";
	}

	return s;
}

+(void) terminateAllOpenVPN {
    
	// Sends SIGTERM to all OpenVPN processes every second until all have terminated.
	// Aborts and returns after about 60 seconds even if they have not terminated.
	
	TBLog(@"DB-TO", @"terminateAllOpenVPN invoked");
	
	if (  ! ALLOW_OPENVPNSTART_KILLALL  ) {
		NSLog(@"terminateAllOpenVPN returning immediately because ALLOW_OPENVPNSTART_KILLALL is FALSE");
		return;
	}
	
	NSUInteger numberOfOpenvpnProcesses = [[NSApp pIdsForOpenVPNProcessesOnlyMain: YES] count];
	
	if (  numberOfOpenvpnProcesses == 0  ) {
		TBLog(@"DB-TO", @"terminateAllOpenVPN returning immediately because there are no OpenVPN processes");
		return;
	}

	NSUInteger i;
	for (  i=0; i<600; i++  ) { // 600 loops @ 0.1 seconds each = 60 seconds (approximately)
		
		numberOfOpenvpnProcesses = [[NSApp pIdsForOpenVPNProcessesOnlyMain: YES] count];
		if (  numberOfOpenvpnProcesses == 0  ) {
			TBLog(@"DB-TO", @"terminateAllOpenVPN detected no OpenVPN processes");
			break;
		}
		
		// The first time through, and about every second thereafter, try to kill all "openvpn" processes
		if (  (i % 10)  == 0  ) {
			TBLog(@"DB-TO", @"terminateAllOpenVPN will run openvpnstart to 'killall'");
			runOpenvpnstart([NSArray arrayWithObject: @"killall"], nil, nil);
		}
		
		usleep(100000);	// 0.1 seconds
	}
	
	if (  numberOfOpenvpnProcesses == 0  ) {
		TBLog(@"DB-TO", @"terminateAllOpenVPN succeeded; there are no OpenVPN processes");
	} else {
		NSLog(@"Could not kill %ld OpenVPN processes within 60 seconds", (long)numberOfOpenvpnProcesses);
	}
}

+(void) terminateOpenVPNWithProcessId: (NSNumber *) processIDAsNumber {
    
	// Sends SIGTERM to the specified OpenVPN process every second until it has terminated.
	// Aborts and returns after about 60 seconds even if the process has not terminated.
	
	TBLog(@"DB-TO", @"terminateOpenVPNWithProcessId: %@ invoked'", processIDAsNumber);
	
	if (  ! ALLOW_OPENVPNSTART_KILL  ) {
		NSLog(@"killOneOpenVPN returning immediately because ALLOW_OPENVPNSTART_KILL is FALSE. Cannot kill OpenVPN process with ID %@", processIDAsNumber);
		return;
	}
	
	BOOL processExists = [[NSApp pIdsForOpenVPNProcessesOnlyMain: YES] containsObject: processIDAsNumber];
	
	if (  ! processExists  ) {
		TBLog(@"DB-TO", @"killOneOpenVPN returning immediately because there is no OpenVPN process with ID %@", processIDAsNumber);
		return;
	}
	
	NSUInteger i;
	for (  i=0; i<600; i++  ) { // 600 loops @ 0.1 seconds each = 60 seconds (approximately)
		
		processExists = [[NSApp pIdsForOpenVPNProcessesOnlyMain: YES] containsObject: processIDAsNumber];
		if (  ! processExists  ) {
			TBLog(@"DB-TO", @"killOneOpenVPN detected no OpenVPN process with ID %@", processIDAsNumber);
			break;
		}
		
		// The first time, and about every second thereafter, try to kill all "openvpn" processes
		if (  (i % 10)  == 0  ) {
			TBLog(@"DB-TO", @"killOneOpenVPN will run openvpnstart to 'kill' %@", processIDAsNumber);
			NSArray * arguments = [NSArray arrayWithObjects: @"kill", [NSString stringWithFormat: @"%@", processIDAsNumber], nil];
			runOpenvpnstart(arguments, nil, nil);
		}
		
		usleep(100000);	// 0.1 seconds
	}
	
	if (  ! processExists  ) {
		TBLog(@"DB-TO", @"killOneOpenVPN succeeded; there is no OpenVPN process with ID %@", processIDAsNumber);
	} else {
		NSLog(@"Could not kill OpenVPN process %@ within 60 seconds", processIDAsNumber);
	}
}


+(void) terminateOpenVPNWithManagmentSocketForConnection: (VPNConnection *) connection {
    
	// Sends 'signal SIGTERM' through the management socket for a connection every second until the process has terminated.
	// Aborts and returns after about 60 seconds even if the process has not terminated.
	
	TBLog(@"DB-TO", @"terminateOpenVPNWithManagmentSocketForConnection for '%@' invoked'", [connection displayName]);
	
	if (  sizeof(pid_t) != 4  ) {
		NSLog(@"sizeof(pid_t) is %lu, not 4!", sizeof(pid_t));
		[gMC terminateBecause: terminatingBecauseOfError];
		return;
	}
	pid_t pid = [connection pid];
	NSNumber * processIDAsNumber = [NSNumber numberWithInt: pid];
	if (  pid  <= 0  ) {
		NSLog(@"terminateOpenVPNWithManagmentSocketForConnection for '%@' returning immediately because the configuration's process ID, %@, is <= 0", [connection displayName], processIDAsNumber);
		return;
	}

	BOOL processExists = [[NSApp pIdsForOpenVPNProcessesOnlyMain: YES] containsObject: processIDAsNumber];
	
	if (  ! processExists  ) {
		TBLog(@"DB-TO", @"terminateOpenVPNWithManagmentSocketForConnection for '%@' returning immediately because there is no OpenVPN process %@", [connection displayName], processIDAsNumber);
		return;
	}
	
	NSUInteger i;
	for (  i=0; i<600; i++  ) { // 600 loops @ 0.1 seconds each = 60 seconds (approximately)
		
		processExists = [[NSApp pIdsForOpenVPNProcessesOnlyMain: YES] containsObject: processIDAsNumber];
		if (  ! processExists  ) {
			TBLog(@"DB-TO", @"terminateOpenVPNWithManagmentSocketForConnection for '%@' detected no OpenVPN process with ID %@", [connection displayName], processIDAsNumber);
			break;
		}
		
		// The first time, and about every second thereafter, write 'signal SIGTERM' to the connection's management socket
		if (  (i % 10)  == 0  ) {
			TBLog(@"DB-TO", @"terminateOpenVPNWithManagmentSocketForConnection for '%@': will write 'signal SIGTERM' to the management socket", [connection displayName]);
			[connection performSelectorOnMainThread: @selector(sendSigtermToManagementSocket) withObject: nil waitUntilDone: NO];
		}
		
		usleep(100000);	// 0.1 seconds
	}
	
	if (  ! processExists  ) {
		TBLog(@"DB-TO", @"terminateOpenVPNWithManagmentSocketForConnection for '%@'  succeeded; there is no OpenVPN process %@", [connection displayName], processIDAsNumber);
	} else {
		NSLog(@"terminateOpenVPNWithManagmentSocketForConnection for '%@': OpenVPN process %@ did not terminate within 60 seconds", [connection displayName], processIDAsNumber);
	}
}

+(void) putConsoleLogOnClipboard {

	// Get OS and Tunnelblick version info
	NSString * versionContents = [[gMC openVPNLogHeader] stringByAppendingString:
								  (isUserAnAdmin()
								   ? @"; Admin user"
								   : @"; Standard user")];
	
	// Get tail of Console log
    NSString * consoleContents = [ConfigurationManager stringContainingRelevantConsoleLogEntries];
	
	NSString * output = [NSString stringWithFormat:
						 @"%@\n\nConsole Log:\n\n%@",
						 versionContents, consoleContents];
	
	NSPasteboard * pb = [NSPasteboard generalPasteboard];
	[pb declareTypes: [NSArray arrayWithObject: NSStringPboardType] owner: self];
	[pb setString: output forType: NSStringPboardType];
}

+(BOOL) exportTunnelblickSetup {
	
	NSString * message = NSLocalizedString(@"Tunnelblick needs authorization to read Tunnelblick data belonging to other users of this computer"
										   @" so it can export all Tunnelblick data.\n\n"
										   @"Please note:\n\n"
										   @"     1. Credentials saved in the Keychain will NOT be exported.\n\n"
										   @"     2. The export may take a long time.\n\n", @"Window text");
	SystemAuth * auth = [[SystemAuth newAuthWithPrompt: message] autorelease];
	if (  auth  ) {
		
		// Construct a name for the output file: "Tunnelblick Setup 2018-08-01 01.15.35". (The .tblkSetup extension will be added by the installer)
		NSString * dateTimeString = [[NSDate date] tunnelblickFilenameRepresentation];
		NSString * filename = [NSString stringWithFormat:
							   NSLocalizedString(@"Tunnelblick Setup %@",
												 @"This is the name of a file created by the 'Export Tunnelblick Setup' button."
												 @" The %@ will be replaced by a date/time such as '2018-07-28 16:22:18'"),
							   dateTimeString];
		
		// Put the output file on the user's Desktop
		NSString * targetPath = [[NSHomeDirectory()
								  stringByAppendingPathComponent: @"Desktop"]
								 stringByAppendingPathComponent: filename];
		
		NSInteger result = [gMC runInstaller: INSTALLER_EXPORT_ALL
															   extraArguments: [NSArray arrayWithObject: targetPath]
															  usingSystemAuth: auth
																 installTblks: nil];
		if (  result != 0  ) {
			NSLog(@"Error while exporting to %@", targetPath);
		}
		
		return result;
	}
	
	return NO;
}

// ************************************************************************
// PRIVATE CLASS METHODS THAT MUST BE INVOKED ON NEW THREADS
//
// "lockForConfigurationChanges" must be done before invoking these methods except for guideStateThread:
// ************************************************************************

+(void) guideStateThread: (NSNumber *) guideState {
	
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    [ConfigurationManager guideState: [guideState intValue]];
	
    [pool drain];
}

+(void) makeConfigurationsPrivateWithDisplayNamesOperation: (NSArray *) displayNames {
	
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    [ConfigurationManager makeConfigurationsShared: NO displayNames: displayNames];
    
    [TBOperationQueue removeDisableList];
    
    [gMC performSelectorOnMainThread: @selector(configurationsChanged) withObject: nil waitUntilDone: NO];
	
    [TBOperationQueue operationIsComplete];
    
    [pool drain];
}

+(void) makeConfigurationsSharedWithDisplayNamesOperation: (NSArray *) displayNames {
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    [ConfigurationManager makeConfigurationsShared: YES displayNames: displayNames];
    
    [TBOperationQueue removeDisableList];
    
    [gMC performSelectorOnMainThread: @selector(configurationsChanged) withObject: nil waitUntilDone: NO];
	
    [TBOperationQueue operationIsComplete];
	
    [pool drain];
}

+(void) removeConfigurationsOrFoldersWithDisplayNamesOperation: (NSArray *) displayNames {
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    [ConfigurationManager removeConfigurationsOrFoldersWithDisplayNames: displayNames];
    
    [TBOperationQueue removeDisableList];
    
    [gMC performSelectorOnMainThread: @selector(configurationsChangedForceLeftNavigationUpdate) withObject: nil waitUntilDone: NO];
	
    [TBOperationQueue operationIsComplete];
    
    [pool drain];
}

+(void) revertToShadowWithDisplayNamesOperation: (NSArray *) displayNames {
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	[ConfigurationManager revertToShadowWithDisplayNames: displayNames];
    
    [TBOperationQueue removeDisableList];
    
    [TBOperationQueue operationIsComplete];
    
    [pool drain];
}

+(void) removeCredentialsWithDisplayNamesOperation: (NSArray *) displayNames {
	
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	[ConfigurationManager removeCredentialsWithDisplayNames: displayNames];
    
    [TBOperationQueue removeDisableList];
    
    [TBOperationQueue operationIsComplete];
    
    [pool drain];
}

+(void) removeCredentialsGroupWithNameOperation: (NSString *) groupName {
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    [ConfigurationManager removeCredentialsGroupWithName: groupName];
    
    [TBOperationQueue removeDisableList];
    
    [TBOperationQueue operationIsComplete];
    
    [pool drain];
}


+(void) makeShadowCopyMatchConfigurationInNewThreadWithDisplayNameOperation: (NSDictionary *) dict {

	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

	NSString	 * displayName = [dict objectForKey:  @"displayName"];
	NSDictionary * updateInfo  = nilIfNSNull( [dict objectForKey:  @"updateInfo"] );
	BOOL		   thenConnect = [[dict objectForKey: @"thenConnect"] boolValue];
	BOOL		   userKnows   = [[dict objectForKey: @"userKnows"] boolValue];

	[ConfigurationManager makeShadowCopyMatchConfigurationWithDisplayName: displayName updateInfo: updateInfo thenConnect: thenConnect userKnows: userKnows];

	[TBOperationQueue removeDisableList];

	[TBOperationQueue operationIsComplete];

	[pool drain];
}

+(void) copyConfigurationsIntoNewFolderOperation: (NSArray *) displayNames {

    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    [ConfigurationManager copyOrMoveConfigurationsIntoNewFolder: displayNames moveNotCopy: FALSE];

    [TBOperationQueue removeDisableList];

   [gMC performSelectorOnMainThread: @selector(configurationsChangedForceLeftNavigationUpdate) withObject: nil waitUntilDone: NO];

    [TBOperationQueue operationIsComplete];
    
    [pool drain];
}

+(void) moveConfigurationsIntoNewFolderOperation: (NSArray *) displayNames {

    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    [ConfigurationManager copyOrMoveConfigurationsIntoNewFolder: displayNames moveNotCopy: TRUE];

    [TBOperationQueue removeDisableList];

    [gMC performSelectorOnMainThread: @selector(configurationsChangedForceLeftNavigationUpdate) withObject: nil waitUntilDone: NO];

    [TBOperationQueue operationIsComplete];
    
    [pool drain];
}

+(void) renameConfigurationWithPathsOperation: (NSDictionary *) dict {
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	NSString * sourcePath = [dict objectForKey: @"sourcePath"];
	NSString * targetPath = [dict objectForKey: @"targetPath"];

    if (  ! [[sourcePath stringByDeletingLastPathComponent] isEqualToString: [targetPath stringByDeletingLastPathComponent]]  ) {
        NSLog(@"renameConfigurationWithPathsOperation: Cannot rename different paths.\n"
              @"     Source = '%@'\n     Target = '%@'", sourcePath, targetPath);
        [TBOperationQueue removeDisableList];
        [TBOperationQueue operationIsComplete];
        [pool drain];
        return;
    }

    NSString * sourceName = [lastPartOfPath(sourcePath) stringByDeletingPathExtension];
    if (  ! [self verifyCanDoMoveOrRenameFromPath: sourcePath name: sourceName]  ) {
        [TBOperationQueue removeDisableList];
        [TBOperationQueue operationIsComplete];
        [pool drain];
        return;
    }

	NSString * targetDisplayName = [lastPartOfPath(targetPath) stringByDeletingPathExtension];
	if (  [self anyConfigurationFolderContainsDisplayName: targetDisplayName]  ) {
        NSString * localName = [gMC localizedNameForDisplayName: targetDisplayName];
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          [NSString stringWithFormat: NSLocalizedString(@"'%@' already exists.", @"Window text. '%@' is the name of a folder or a configuration."), localName]);
    } else {

        NSString * prompt = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick needs authorization to rename configuration '%@' to '%@'.", @"Window text"), sourceName, [targetPath lastPathComponent]];
        SystemAuth * auth = [SystemAuth newAuthWithPrompt: prompt];
        if (  auth ) {
            NSDictionary * dict2 = [NSDictionary dictionaryWithObjectsAndKeys:
                                    sourcePath, @"sourcePath",
                                    targetPath, @"targetPath",
                                    auth,       @"auth",
                                    nil];
            [gMC performSelectorOnMainThread: @selector(renameConfigurationUsingConfigurationManager:) withObject: dict2 waitUntilDone: YES];
            [auth release];
        }
	}
    
    [TBOperationQueue removeDisableList];
    
    [gMC performSelectorOnMainThread: @selector(configurationsChangedForceLeftNavigationUpdate) withObject: nil waitUntilDone: YES];

    [TBOperationQueue operationIsComplete];

    [pool drain];
}

+(BOOL) anyConfigurationFolderContainsDisplayName: (NSString *) name {

    NSString * nameWithoutSlashOrTblk = (  [name hasSuffix: @"/"]
                                         ? [name substringToIndex: [name length] - 1]
                                         : (  [name hasSuffix: @".tblk"]
                                            ? [name stringByDeletingPathExtension]
                                            : name));
    NSString * nameWithDotTblk = [nameWithoutSlashOrTblk stringByAppendingPathExtension: @"tblk"];


    BOOL result = (   [gFileMgr fileExistsAtPath: [gPrivatePath stringByAppendingPathComponent: nameWithoutSlashOrTblk]]
                   || [gFileMgr fileExistsAtPath: [gPrivatePath stringByAppendingPathComponent: nameWithDotTblk]]
                   || [gFileMgr fileExistsAtPath: [L_AS_T_SHARED stringByAppendingPathComponent: nameWithoutSlashOrTblk]]
                   || [gFileMgr fileExistsAtPath: [L_AS_T_SHARED stringByAppendingPathComponent: nameWithDotTblk]]
                   || [gFileMgr fileExistsAtPath: [[L_AS_T_USERS stringByAppendingPathComponent: NSUserName()]
                                                   stringByAppendingPathComponent: nameWithoutSlashOrTblk]]
                   || [gFileMgr fileExistsAtPath: [[L_AS_T_USERS stringByAppendingPathComponent: NSUserName()]
                                                   stringByAppendingPathComponent: nameWithDotTblk]]  );

    return result;
}

+(void) renameFolderWithDisplayNameOperation: (NSDictionary *) dict {

    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    NSString * sourceDisplayName = [dict objectForKey: @"sourceDisplayName"];
    NSString * targetDisplayName = [dict objectForKey: @"targetDisplayName"];

    if (  [self anyConfigurationFolderContainsDisplayName: targetDisplayName]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          [NSString stringWithFormat: NSLocalizedString(@"'%@' already exists.", @"Window text. '%@' is the name of a folder or a configuration."), [targetDisplayName substringToIndex: [targetDisplayName length] - 1]]);
    } else {
        NSString * prompt;
        NSString * sourceNameForPrompt = [sourceDisplayName substringToIndex: [sourceDisplayName length] - 1];
        NSString * folderEnclosingSource = [sourceDisplayName stringByDeletingLastPathComponent];
        NSString * folderEnclosingTarget = [targetDisplayName stringByDeletingLastPathComponent];
        if (  [folderEnclosingSource isEqualToString: folderEnclosingTarget]  ) {
            prompt = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick needs authorization to rename folder '%@' to '%@'.", @"Window text"), [sourceDisplayName lastPathComponent], [targetDisplayName lastPathComponent]];
        } else if (  [folderEnclosingTarget isEqualToString: @""]  ) {
            prompt = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick needs authorization to move folder '%@'.", @"Window text"), sourceNameForPrompt];
        } else {
            prompt = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick needs authorization to move folder '%@' into folder '%@'.", @"Window text"), sourceNameForPrompt, folderEnclosingTarget];
        }
        SystemAuth * auth = [SystemAuth newAuthWithPrompt: prompt];
        if (  auth ) {

            NSDictionary * dict3 = [NSDictionary dictionaryWithObjectsAndKeys:
                                    sourceDisplayName, @"sourceDisplayName",
                                    targetDisplayName, @"targetDisplayName",
                                    auth,              @"auth",
                                    nil];
            [gMC performSelectorOnMainThread:@selector(renameConfigurationFolderUsingConfigurationManager:) withObject: dict3 waitUntilDone: YES];
            [auth release];

        }
    }

    [TBOperationQueue removeDisableList];

    [TBOperationQueue operationIsComplete];

    [pool drain];
}

+(void) duplicateConfigurationWithPathsOperation: (NSDictionary *) dict {
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	NSString * sourcePath = [dict objectForKey: @"sourcePath"];
	NSString * targetPath = [dict objectForKey: @"targetPath"];
    
    [ConfigurationManager duplicateConfigurationFromPath: sourcePath
												  toPath: targetPath];
    
    [TBOperationQueue removeDisableList];
    
    [gMC performSelectorOnMainThread: @selector(configurationsChangedForceLeftNavigationUpdate) withObject: nil waitUntilDone: NO];
	
    [TBOperationQueue operationIsComplete];
    
    [pool drain];
}

+(void) createConfigurationFoldersForDisplayNamesOperation: (NSDictionary *) dict {

    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    NSString * sourceDisplayName = [dict objectForKey:  @"sourceDisplayName"];
    NSString * targetDisplayName = [dict objectForKey:  @"targetDisplayName"];

    NSString * prompt = [NSString stringWithFormat:
                         NSLocalizedString(@"Tunnelblick needs authorization to copy folder '%@'.", @"Window text"),
                         sourceDisplayName];
    SystemAuth * auth = [SystemAuth newAuthWithPrompt: prompt];
    if (   ! auth  ) {
        [TBOperationQueue removeDisableList];
        [TBOperationQueue operationIsComplete];
        [pool drain];
        return;
    }

    if (  ! [self createConfigurationFoldersForDisplayName: targetDisplayName usingSystemAuth: auth]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          [NSString stringWithFormat:
                           NSLocalizedString(@"Tunnelblick could not copy folder '%@'. See the Console Log for details.", @"Window text"),
                           sourceDisplayName]);
    }

    [auth release];

    [TBOperationQueue removeDisableList];

    [gMC performSelectorOnMainThread: @selector(configurationsChangedForceLeftNavigationUpdate) withObject: nil waitUntilDone: NO];

    [TBOperationQueue operationIsComplete];

    [pool drain];
}

+(void) moveOrCopyConfigurationsWithPathsOperation: (NSDictionary *) dict {

    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    NSArray * sourcePaths = [dict objectForKey:  @"sourcePaths"];
    NSArray * targetPaths = [dict objectForKey:  @"targetPaths"];
    NSNumber * moveNotCopyNumber = [dict objectForKey: @"moveNotCopy"];

    if (  [sourcePaths count] != [targetPaths count]  ) {
        NSLog(@"moveOrCopyConfigurationsWithPathsOperation: [sourcePaths count] != [targetPaths count]; sourcePaths = %@\ntargetPaths=%@", sourcePaths, targetPaths);
        [TBOperationQueue removeDisableList];
        [TBOperationQueue operationIsComplete];
        [pool drain];
        return;
    }

    NSString * prompt = NSLocalizedString(@"Tunnelblick needs authorization to copy or move configurations.", @"Window text");
    SystemAuth * auth = [SystemAuth newAuthWithPrompt: prompt];
    if (   ! auth  ) {
        [TBOperationQueue removeDisableList];
        [TBOperationQueue operationIsComplete];
        [pool drain];
        return;
    }

    NSUInteger i;
    for (  i=0; i<[sourcePaths count]; i++  ) {
        NSString * sourcePath = [sourcePaths objectAtIndex: i];
        NSString * targetPath = [targetPaths objectAtIndex: i];

        // If the target exists, offer to replace or keep both copies
        targetPath = [self pathToUseIfItemAtPathExists: targetPath stopNotCancel: (i>0)];
        if (  ! targetPath  ) {
            break;
        }

        NSMutableString * result = [[[NSMutableString alloc] initWithCapacity: 1000] autorelease];
        NSDictionary * dict2 = [NSDictionary dictionaryWithObjectsAndKeys:
                                sourcePath,        @"sourcePath",
                                targetPath,        @"targetPath",
                                auth,              @"auth",
                                @YES,              @"warnDialog",
                                moveNotCopyNumber, @"moveNotCopy",
                                @NO,               @"noAdmin",
                                result,            @"result",
                                nil];
        [gMC
         performSelectorOnMainThread: @selector(moveOrCopyOneConfigurationUsingConfigurationManager:) withObject: dict2 waitUntilDone: YES];
        if ( [result length] != 0  ) {
            break;
        }
    }

    [auth release];

    [TBOperationQueue removeDisableList];

    [gMC performSelectorOnMainThread: @selector(configurationsChangedForceLeftNavigationUpdate) withObject: nil waitUntilDone: NO];

    [TBOperationQueue operationIsComplete];
    
    [pool drain];
}

+(void) moveOrCopyOneConfiguration: (NSDictionary *) dict {

    NSString   *      sourcePath  =  [dict objectForKey: @"sourcePath"];
    NSString   *      targetPath  =  [dict objectForKey: @"targetPath"];
    SystemAuth *      auth        =  [dict objectForKey: @"auth"];
    NSMutableString * result      =  [dict objectForKey: @"result"];
    BOOL              warnDialog  = [[dict objectForKey: @"warnDialog"]  boolValue];
    BOOL              moveNotCopy = [[dict objectForKey: @"moveNotCopy"] boolValue];
    BOOL              noAdmin     = [[dict objectForKey: @"noAdmin"]     boolValue];

    BOOL ok = [self copyConfigPath: sourcePath
                            toPath: targetPath
                   usingSystemAuth: auth
                        warnDialog: warnDialog
                       moveNotCopy: moveNotCopy
                           noAdmin: noAdmin];
    if (  ok  ) {
        NSString * sourceDisplayName = displayNameFromPath(sourcePath);
        NSString * targetDisplayName = displayNameFromPath(targetPath);
        if (  ! [self moveOrCopyCredentialsAndSettingsFrom: sourceDisplayName to: targetDisplayName moveNotCopy: moveNotCopy]  ) {
            TBShowAlertWindow(NSLocalizedString(@"Warning", @"Window title"),
                              NSLocalizedString(@"Warning: One or more settings could not be copied. See the Console Log for details.", @"Window text"));
            [result appendString: @"/"];
        }
    } else {
        [result appendString: @"/"];
    }
}

+(void) installConfigurationsShowMessagesNotifyDelegateOperation: (NSArray *) filePaths {
	
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    [[ConfigurationManager manager] installConfigurations: filePaths
                                             skipMessages: NO
                                           notifyDelegate: YES
                                         disallowCommands: NO];
    
    [TBOperationQueue removeDisableList];
    
    [gMC performSelectorOnMainThread: @selector(configurationsChangedForceLeftNavigationUpdate) withObject: nil waitUntilDone: NO];
    
    [TBOperationQueue operationIsComplete];
    
    [pool drain];
}

+(void) putDiagnosticInfoOnClipboardOperation: (NSDictionary *) dict {
	
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

	NSString * displayName = [dict objectForKey: @"displayName"];
	NSString * logContents = nilIfNSNull([dict objectForKey: @"logContents"]);

    [ConfigurationManager putDiagnosticInfoOnClipboardWithDisplayName: displayName log: logContents];
    
    [TBOperationQueue removeDisableList];
    
	[[gMC logScreen] performSelectorOnMainThread: @selector(indicateNotWaitingForDiagnosticInfoToClipboard) withObject: nil waitUntilDone: NO];
	
    [TBOperationQueue operationIsComplete];
    
    [pool drain];
}

+(void) terminateAllOpenVPNOperation {
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    [ConfigurationManager terminateAllOpenVPN];
    
    [TBOperationQueue removeDisableList];
    
    [TBOperationQueue operationIsComplete];
    
    [pool drain];
}

+(void) terminateOpenVPNWithProcessIdOperation: (NSNumber *) processIDAsNumber {
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
	[ConfigurationManager terminateOpenVPNWithProcessId: processIDAsNumber];
	
    [TBOperationQueue removeDisableList];
    
    [TBOperationQueue operationIsComplete];
    
    [pool drain];
}

+(void) terminateOpenVPNWithManagmentSocketInNewThreadOperation: (VPNConnection *) connection {
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
	[ConfigurationManager terminateOpenVPNWithManagmentSocketForConnection: connection];
	
    [TBOperationQueue removeDisableList];
    
    [TBOperationQueue operationIsComplete];
    
    [pool drain];
}

+(void) putConsoleLogOnClipboardOperation {
	
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    [ConfigurationManager putConsoleLogOnClipboard];
    
    [TBOperationQueue removeDisableList];
    
	[[gMC logScreen] performSelectorOnMainThread: @selector(indicateNotWaitingForConsoleLogToClipboard) withObject: nil waitUntilDone: NO];
	
    [TBOperationQueue operationIsComplete];
    
    [pool drain];
}

+(void) exportTunnelblickSetupOperation {
	
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	[ConfigurationManager exportTunnelblickSetup];
	
	[TBOperationQueue removeDisableList];
	
	[[gMC logScreen]
	 performSelectorOnMainThread: @selector(indicateNotWaitingForUtilitiesExportTunnelblickSetup)
				      withObject: nil
	               waitUntilDone: NO];
	
	[TBOperationQueue operationIsComplete];
	
	[pool drain];
}

+(void) installConfigurationsShowMessagesDoNotNotifyDelegateOperation: (NSArray *) filePaths {
	
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    [[ConfigurationManager manager] installConfigurations: filePaths
                                             skipMessages: NO
                                           notifyDelegate: NO
                                         disallowCommands: NO];
    
    [TBOperationQueue removeDisableList];
    
    [gMC performSelectorOnMainThread: @selector(configurationsChangedForceLeftNavigationUpdate) withObject: nil waitUntilDone: NO];
    
    [TBOperationQueue operationIsComplete];
	
    [pool drain];
}

// ************************************************************************
// CLASS METHODS USED EXTERNALLY
// ************************************************************************

+(void) haveNoConfigurationsGuideInNewThread {
    
	[NSThread detachNewThreadSelector: @selector(guideStateThread:) toTarget: [ConfigurationManager class] withObject: [NSNumber numberWithInt: entryNoConfigurations]];
}

+(void) addConfigurationGuideInNewThread {
    
	[NSThread detachNewThreadSelector: @selector(guideStateThread:) toTarget: [ConfigurationManager class] withObject: [NSNumber numberWithInt: entryAddConfiguration]];
}

+(void) makeConfigurationsPrivateInNewThreadWithDisplayNames: (NSArray *)  displayNames {
	
    [TBOperationQueue addToQueueSelector: @selector(makeConfigurationsPrivateWithDisplayNamesOperation:)
                                  target: [ConfigurationManager class]
                                  object: displayNames
                             disableList: displayNames];
}

+(void) makeConfigurationsSharedInNewThreadWithDisplayNames: (NSArray *)  displayNames {
	
    [TBOperationQueue addToQueueSelector: @selector(makeConfigurationsSharedWithDisplayNamesOperation:)
                                  target: [ConfigurationManager class]
                                  object: displayNames
                             disableList: displayNames];
}

+(void) removeConfigurationsOrFoldersInNewThreadWithDisplayNames: (NSArray *)  displayNames {
	
    [TBOperationQueue addToQueueSelector: @selector(removeConfigurationsOrFoldersWithDisplayNamesOperation:)
                                  target: [ConfigurationManager class]
                                  object: displayNames
                             disableList: [NSArray arrayWithObject: @"*"]];
}

+(void) revertToShadowInNewThreadWithDisplayNames: (NSArray *)  displayNames {
	
    [TBOperationQueue addToQueueSelector: @selector(revertToShadowWithDisplayNamesOperation:)
                                  target: [ConfigurationManager class]
                                  object: displayNames
                             disableList: displayNames];
}

+(void) removeCredentialsInNewThreadWithDisplayNames: (NSArray *)  displayNames {
	
    [TBOperationQueue addToQueueSelector: @selector(removeCredentialsWithDisplayNamesOperation:)
                                  target: [ConfigurationManager class]
                                  object: displayNames
                             disableList: displayNames];
}

+(void) removeCredentialsGroupInNewThreadWithName: (NSString *)  groupName {
	
    [TBOperationQueue addToQueueSelector: @selector(removeCredentialsGroupWithNameOperation:)
                                  target: [ConfigurationManager class]
                                  object: groupName
                             disableList: [NSArray arrayWithObject: @"*"]];
}

+(void) makeShadowCopyMatchConfigurationInNewThreadWithDisplayName: (NSString *)	 displayName
														updateInfo: (NSDictionary *) updateInfo
													   thenConnect: (BOOL)			 thenConnect
														 userKnows: (BOOL)			 userKnows {

	NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
						   displayName,							   @"displayName",
						   NSNullIfNil(updateInfo),				   @"updateInfo",
						   [NSNumber numberWithBool: thenConnect], @"thenConnect",
						   [NSNumber numberWithBool: userKnows],   @"userKnows",
						   nil];

	[TBOperationQueue addToQueueSelector: @selector(makeShadowCopyMatchConfigurationInNewThreadWithDisplayNameOperation:)
								  target: [ConfigurationManager class]
								  object: dict
							 disableList: [NSArray arrayWithObject: displayName]];
}

+(void) copyConfigurationsIntoNewFolderInNewThread: (NSArray *) displayNames {

    [TBOperationQueue addToQueueSelector: @selector(copyConfigurationsIntoNewFolderOperation:)
                                  target: [ConfigurationManager class]
                                  object: displayNames
                             disableList: displayNames];
}

+(void) moveConfigurationsIntoNewFolderInNewThread: (NSArray *) displayNames {

    [TBOperationQueue addToQueueSelector: @selector(moveConfigurationsIntoNewFolderOperation:)
                                  target: [ConfigurationManager class]
                                  object: displayNames
                             disableList: displayNames];
}

+(void) renameConfigurationInNewThreadAtPath: (NSString *) sourcePath
									  toPath: (NSString *) targetPath {
	
	NSArray * paths = [NSArray arrayWithObjects: sourcePath, targetPath, nil];
	NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
						   sourcePath, @"sourcePath",
						   targetPath, @"targetPath",
						   nil];
    
    [TBOperationQueue addToQueueSelector: @selector(renameConfigurationWithPathsOperation:)
                                  target: [ConfigurationManager class]
                                  object: dict
                             disableList: [ConfigurationManager displayNamesFromPaths: paths]];
}

+(void) renameFolderInNewThreadWithDisplayName: (NSString *) sourceDisplayName
                                 toDisplayName: (NSString *) targetDisplayName {

    NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                           sourceDisplayName, @"sourceDisplayName",
                           targetDisplayName, @"targetDisplayName",
                           nil];

    [TBOperationQueue addToQueueSelector: @selector(renameFolderWithDisplayNameOperation:)
                                  target: [ConfigurationManager class]
                                  object: dict
                             disableList: [NSArray arrayWithObject: @"*"]];
}

+(void) copyFolderInNewThreadWithDisplayName: (NSString *) sourceDisplayName toDisplayName: (NSString *) targetDisplayName {

    // Build arrays of source and target paths, then send them to moveOrCopyConfigurationsWithPathsOperation:

    NSMutableArray * sourcePaths = [[[NSMutableArray alloc] initWithCapacity: 10] autorelease];
    NSMutableArray * targetPaths = [[[NSMutableArray alloc] initWithCapacity: 10] autorelease];

    NSArray * configurations = [[gMC myConfigDictionary] allValues];
    NSEnumerator * e = [configurations objectEnumerator];
    NSString * thisSourcePath;
    while (  (thisSourcePath = [e nextObject])  ) {
        NSString * thisSourceLastPart = lastPartOfPath(thisSourcePath);
        if (  [thisSourceLastPart hasPrefix: sourceDisplayName]  ) {
            NSString * thisSourceDisplayName = [thisSourceLastPart stringByDeletingPathExtension];
            NSString * thisSourceDisplayNameAfterSourceDisplayName = [thisSourceDisplayName substringFromIndex: [sourceDisplayName length]];
            NSString * thisTargetDisplayName = [targetDisplayName stringByAppendingPathComponent: thisSourceDisplayNameAfterSourceDisplayName];
            NSString * thisTargetPath = [[firstPartOfPath(thisSourcePath)
                                          stringByAppendingPathComponent: thisTargetDisplayName]
                                         stringByAppendingPathExtension: @"tblk"];
            [sourcePaths addObject: thisSourcePath];
            [targetPaths addObject: thisTargetPath];
        }
    }

    if (  [sourcePaths count] == 0  ) {

        NSString * sharedPath  = [L_AS_T_SHARED stringByAppendingPathComponent: targetDisplayName];
        NSString * privatePath = [[L_AS_T_USERS
                                   stringByAppendingPathComponent: NSUserName()]
                                  stringByAppendingPathComponent: targetDisplayName];
        if (   [gFileMgr fileExistsAtPath: sharedPath]
            && [gFileMgr fileExistsAtPath: privatePath]  ) {
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                              [NSString stringWithFormat:
                               NSLocalizedString(@"'%@' already exists.", @"Window text. '%@' is the name of a folder or a configuration."),
                               targetDisplayName]);
            return;
        }

        NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                               sourceDisplayName, @"sourceDisplayName",
                               targetDisplayName, @"targetDisplayName",
                               nil];

        [TBOperationQueue addToQueueSelector: @selector(createConfigurationFoldersForDisplayNamesOperation:)
                                      target: [ConfigurationManager class]
                                      object: dict
                                 disableList: [NSArray arrayWithObject: @"*"]];
        return;
    }

    NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                           sourcePaths, @"sourcePaths",
                           targetPaths, @"targetPaths",
                           @NO,         @"moveNotCopy",
                           nil];

    [TBOperationQueue addToQueueSelector: @selector(moveOrCopyConfigurationsWithPathsOperation:)
                                  target: [ConfigurationManager class]
                                  object: dict
                             disableList: [NSArray arrayWithObject: @"*"]];
}

+(void) duplicateConfigurationInNewThreadPath: (NSString *) sourcePath
									   toPath: (NSString *) targetPath {
	
	NSArray * paths = [NSArray arrayWithObjects: sourcePath, targetPath, nil];
	NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
						   sourcePath, @"sourcePath",
						   targetPath, @"targetPath",
						   nil];

    [TBOperationQueue addToQueueSelector: @selector(duplicateConfigurationWithPathsOperation:)
                                  target: [ConfigurationManager class]
                                  object: dict
                             disableList: [ConfigurationManager displayNamesFromPaths: paths]];
}

+(void) moveOrCopyConfigurationsInNewThreadAtPaths: (NSArray *) sourcePaths
                                           toPaths: (NSArray *) targetPaths
                                       moveNotCopy: (BOOL)      moveNotCopy {

    NSNumber * move = [NSNumber numberWithBool: moveNotCopy];

    NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                           sourcePaths, @"sourcePaths",
                           targetPaths, @"targetPaths",
                           move,        @"moveNotCopy",
                           nil];

    [TBOperationQueue addToQueueSelector: @selector(moveOrCopyConfigurationsWithPathsOperation:)
                                  target: [ConfigurationManager class]
                                  object: dict
                             disableList: [NSArray arrayWithObject: @"*"]];
}

+(void) installConfigurationsUpdateInBundleInMainThreadAtPath: (NSString *) path {
    
    NSArray * components = [path componentsSeparatedByString: @"/"];
    if (   ( [components count] !=  7)
        || ( ! [path hasPrefix: L_AS_T_TBLKS])
        ) {
        NSLog(@"Configuration update installer: Not installing configurations update: Invalid path to update");
    } else {
        
        // Secure the update (which makes Info.plist readable by everyone and all folders searchable by everyone)
        NSArray * args = [NSArray arrayWithObjects:
                          @"secureUpdate",
                          [components objectAtIndex: 5],
                          nil];
        OSStatus status = runOpenvpnstart(args, nil, nil);
        if (  status != 0  ) {
            NSLog(@"Could not secure the update; openvpnstart status was %ld", (long)status);
        }
        
        // Install the updated configurations
        TBLog(@"DB-UC", @"Installing updated configurations at '%@'", path);
        [[ConfigurationManager manager] installConfigurations: [NSArray arrayWithObject: path]
                                                 skipMessages: YES
                                               notifyDelegate: YES
                                             disallowCommands: YES];
    }
    
    [gMC configurationsChanged];
    
    [gMC startCheckingForConfigurationUpdates];
}

+(void) putDiagnosticInfoOnClipboardInNewThreadForDisplayName: (NSString *) displayName log: (NSString *) logContents {
    
	NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
						   displayName, 			 @"displayName",
						   NSNullIfNil(logContents), @"logContents",
						   nil];

    [TBOperationQueue addToQueueSelector: @selector(putDiagnosticInfoOnClipboardOperation:)
                                  target: [ConfigurationManager class]
                                  object: dict
                             disableList: [NSArray arrayWithObject: displayName]];
}

+(void) terminateAllOpenVPNInNewThread {
    
	TBLog(@"DB-TO", @"terminateAllOpenVPNInNewThread invoked; stack trace: %@", callStack());
	
    [TBOperationQueue addToQueueSelector: @selector(terminateAllOpenVPNOperation)
                                  target: [ConfigurationManager class]
                                  object: nil
                             disableList: [NSArray array]];
}

+(void) terminateOpenVPNWithProcessIdInNewThread: (NSNumber *) processIdAsNumber {
	
	TBLog(@"DB-TO", @"terminateOpenVPNWithProcessIdInNewThread: %@ invoked; stack trace: %@", processIdAsNumber, callStack());
	
	[TBOperationQueue addToQueueSelector: @selector(terminateOpenVPNWithProcessIdOperation:)
								  target: [ConfigurationManager class]
								  object: processIdAsNumber
							 disableList: [NSArray array]];
}


+(void) terminateOpenVPNWithManagmentSocketInNewThread: (VPNConnection *) connection {
	
	TBLog(@"DB-TO", @"terminateOpenVPNWithManagmentSocketInNewThread '%@' invoked; stack trace: %@", [connection displayName], callStack());
	
	[TBOperationQueue addToQueueSelector: @selector(terminateOpenVPNWithManagmentSocketInNewThreadOperation:)
								  target: [ConfigurationManager class]
								  object: connection
							 disableList: [NSArray array]];
}

+(void) putConsoleLogOnClipboardInNewThread {
    
    [TBOperationQueue addToQueueSelector: @selector(putConsoleLogOnClipboardOperation)
                                  target: [ConfigurationManager class]
                                  object: nil
                             disableList: [NSArray array]];
}

+(void) exportTunnelblickSetupInNewThread {
	
	// We are exporting everything, so disable ALL configurations
	NSArray * disableList = [[gMC myVPNConnectionDictionary] allKeys];
	
	[TBOperationQueue addToQueueSelector: @selector(exportTunnelblickSetupOperation)
								  target: [ConfigurationManager class]
								  object: nil
							 disableList: disableList];
}

+(void) installConfigurationsInNewThreadShowMessagesNotifyDelegateWithPaths: (NSArray *)  paths {
	
    [TBOperationQueue addToQueueSelector: @selector(installConfigurationsShowMessagesNotifyDelegateOperation:)
                                  target: [ConfigurationManager class]
                                  object: paths
                             disableList: [ConfigurationManager displayNamesFromPaths: paths]];
}

+(void) installConfigurationsInNewThreadShowMessagesDoNotNotifyDelegateWithPaths: (NSArray *)  paths {
	
    [TBOperationQueue addToQueueSelector: @selector(installConfigurationsShowMessagesDoNotNotifyDelegateOperation:)
                                  target: [ConfigurationManager class]
                                  object: paths
                             disableList: [ConfigurationManager displayNamesFromPaths: paths]];
}

+(void) installConfigurationsInCurrentMainThreadDoNotShowMessagesDoNotNotifyDelegateWithPaths: (NSArray *)  paths {
    
    if (  ! [NSThread isMainThread]  ) {
        NSLog(@"installConfigurationsInCurrentMainThreadDoNotShowMessagesDoNotNotifyDelegateWithPaths: not running on main thread");
        [gMC terminateBecause: terminatingBecauseOfError];
    }
    
    [[ConfigurationManager manager] installConfigurations: paths
                                             skipMessages: YES
                                           notifyDelegate: NO
                                         disallowCommands: NO];
    
    [gMC configurationsChangedForceLeftNavigationUpdate];
}

+(CommandOptionsStatus) commandOptionsInOpenvpnConfigurationAtPath: (NSString *) path
                                                          fromTblk: (NSString *) tblkPath {
    
    ConfigurationConverter * converter = [[[ConfigurationConverter alloc] init] autorelease];
    CommandOptionsStatus status = [converter commandOptionsStatusForOpenvpnConfigurationAtPath: path
                                                                                      fromTblk: tblkPath];
    if (  status != CommandOptionsNo  ) {
        NSString * returnDescription = (  (status == CommandOptionsError)
                                        ? @"error occurred"
                                        : (  (status == CommandOptionsYes)
                                           ? @"unsafe option(s) or run-as-root scripts found"
                                           : (  (status == CommandOptionsUnknown)
                                              ? @"unknown option(s) found"
                                              : (  (status == CommandOptionsUserScript)
											     ? @"user scripts found"
												 : @"invalid status"))));
        NSLog(@"commandOptionsStatusForOpenvpnConfigurationAtPath:forTblk: returned '%@' for %@", returnDescription, path);
    }
    
    return status;
}

+(CommandOptionsStatus) commandOptionsInOneConfigurationAtPath: (NSString *) path {
    
    NSString * extension = [path pathExtension];
    
    if (   [extension isEqualToString: @"ovpn"]
        || [extension isEqualToString: @"conf"]  ) {
        return [ConfigurationManager commandOptionsInOpenvpnConfigurationAtPath: path fromTblk: nil];
    }
    
    if (  ! [extension isEqualToString: @"tblk"]  ) {
        NSLog(@"Configuration is not an .ovpn, .conf, or .tblk at %@", path);
        return CommandOptionsError;
    }
    
    BOOL haveUnknown = FALSE;
	BOOL haveUserScript = FALSE;
    
    NSString * file;
    NSDirectoryEnumerator * dirE = [gFileMgr enumeratorAtPath: path];
    while (  (file = [dirE nextObject])  ) {
        
        extension = [file pathExtension];
        
        if (  [extension isEqualToString: @"sh"]  ) {
            NSLog(@"commandOptionsInOneConfigurationAtPath: '.sh' files found in %@", path);
			if (  shouldRunScriptAsUserAtPath(file)  ) {
				haveUserScript = TRUE;
			} else {
				return CommandOptionsYes;
			}
        }
        
		NSString * fullPath = [path stringByAppendingPathComponent: file];
        if (   [extension isEqualToString: @"ovpn"]
            || [extension isEqualToString: @"conf"]  ) {
            CommandOptionsStatus status = [ConfigurationManager commandOptionsInOpenvpnConfigurationAtPath: fullPath fromTblk: path];
            if (  status != CommandOptionsNo   ) {
                if (  status == CommandOptionsUnknown  ) {
                    haveUnknown = TRUE;
                } else {
                    return status;
                }
            }
        }
    }
    
    return (  haveUnknown
			? CommandOptionsUnknown
			: (  haveUserScript
			   ? CommandOptionsUserScript
			   : CommandOptionsNo  ));
}

+(CommandOptionsStatus) commandOptionsInConfigurationsAtPaths: (NSArray *) paths {
    
    BOOL haveUnknown = FALSE;
	BOOL haveUserScript = FALSE;
    NSString * path;
    NSEnumerator * e = [paths objectEnumerator];
    while (  (path = [e nextObject])  ) {
        CommandOptionsStatus status = [ConfigurationManager commandOptionsInOneConfigurationAtPath: path];
        if (  status != CommandOptionsNo   ) {
            if (  status == CommandOptionsUnknown  ) {
                haveUnknown = TRUE;
            } else if (  status == CommandOptionsUserScript  ){
				haveUserScript = TRUE;
			} else {
                return status;
            }
        }
    }
    
    return (  haveUnknown
			? CommandOptionsUnknown
			: (  haveUserScript
			   ? CommandOptionsUserScript
			   : CommandOptionsNo ));
}

@end
