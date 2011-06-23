/*
 * Copyright 2010, 2011 Jonathan K. Bullard. All rights reserved.
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
#import <unistd.h>
#import <sys/param.h>
#import <sys/mount.h>
#import "defines.h"
#import "helper.h"
#import "MenuController.h"
#import "NSApplication+LoginItem.h"
#import "TBUserDefaults.h"
#import "NSFileManager+TB.h"

extern NSMutableArray       * gConfigDirs;
extern NSString             * gDeployPath;
extern NSString             * gSharedPath;
extern NSString             * gPrivatePath;
extern NSFileManager        * gFileMgr;
extern TBUserDefaults       * gTbDefaults;

extern NSString * firstPartOfPath(NSString * thePath);
extern NSString * lastPartOfPath(NSString * thePath);
extern BOOL       folderContentsNeedToBeSecuredAtPath(NSString * theDirPath);

enum state_t {                      // These are the "states" of the guideState state machine
    entryNoConfigurations,
    entryAddConfiguration,
    stateGoBack,                    // (This can only be a nextState, never an actual state)
    stateHasNoConfigurations,
    stateMakeSampleConfiguration,
    stateMakeEmptyConfiguration,
    stateOpenPrivateFolder,
    stateHasConfigurations,
    stateShowTbInstructions,
    stateShowOpenVpnInstructions
};

@interface ConfigurationManager() // PRIVATE METHODS

-(BOOL)         addConfigsFromPath:         (NSString *)                folderPath
                   thatArePackages:         (BOOL)                      onlyPkgs
                            toDict:         (NSMutableDictionary * )    dict
                      searchDeeply:         (BOOL)                      deep;

-(BOOL)         checkPermissions:           (NSString *)                permsShouldHave
                         forPath:           (NSString *)                path;

-(BOOL)         configNotProtected:         (NSString *)                configFile;

-(NSString *)   displayNameForPath:         (NSString *)                thePath;

-(NSString *)   getLowerCaseStringForKey:   (NSString *)                key
                            inDictionary:   (NSDictionary *)            dict
                               defaultTo:   (id)                        replacement;

-(void)         guideState:                 (enum state_t)              state;

-(NSString *)   getPackageToInstall:        (NSString *)                thePath
                            withKey:        (NSString *)                key;

-(BOOL)         isSampleConfigurationAtPath:(NSString *)                cfgPath;

-(NSString *)   makeEmptyTblk:              (NSString *)                thePath
                      withKey:              (NSString *)                key;

-(BOOL)         makeSureFolderExistsAtPath: (NSString *)                folderPath
                                 usingAuth: (AuthorizationRef)          authRef;

-(BOOL)         onRemoteVolume:             (NSString *)                cfgPath;

-(NSArray *)    checkOneDotTblkPackage:     (NSString *)                filePath
                              withKey:      (NSString *)                key;

-(BOOL)         protectConfigurationFile:   (NSString *)                configFilePath
                               usingAuth:   (AuthorizationRef)          authRef;

-(NSString *)   parseString:                (NSString *)                cfgContents
                  forOption:                (NSString *)                option;

@end

@implementation ConfigurationManager

+(id)   defaultManager
{
    return [[[ConfigurationManager alloc] init] autorelease];
}

// Returns a dictionary with information about the configuration files in gConfigDirs.
// The key for each entry is the display name for the configuration; the object is the path to the configuration file
// (which may be a .tblk package or a .ovpn or .conf file) for the configuration
//
// Only searches folders that are in gConfigDirs.
//
// First, it goes through gDeploy looking for packages,
//           then through gDeploy looking for configs NOT in packages,
//           then through gSharedPath looking for packages (does not look for configs that are not in packages in gSharedPath)
//           then through gPrivatePath looking for packages,
//           then through gPrivatePath looking for configs NOT in packages
-(NSMutableDictionary *) getConfigurations
{
    NSMutableDictionary * dict = [[[NSMutableDictionary alloc] init] autorelease];
    BOOL noneIgnored = TRUE;
    
    noneIgnored = [self addConfigsFromPath: gDeployPath  thatArePackages: YES toDict: dict searchDeeply: YES ] && noneIgnored;
    noneIgnored = [self addConfigsFromPath: gDeployPath  thatArePackages: NO  toDict: dict searchDeeply: YES ] && noneIgnored;
    noneIgnored = [self addConfigsFromPath: gSharedPath  thatArePackages: YES toDict: dict searchDeeply: YES ] && noneIgnored;
    noneIgnored = [self addConfigsFromPath: gPrivatePath thatArePackages: YES toDict: dict searchDeeply: YES ] && noneIgnored;
    noneIgnored = [self addConfigsFromPath: gPrivatePath thatArePackages: NO  toDict: dict searchDeeply: YES ] && noneIgnored;
    
    if (  ! noneIgnored  ) {
        TBRunAlertPanelExtended(NSLocalizedString(@"Configuration(s) Ignored", @"Window title"),
                                NSLocalizedString(@"One or more configurations are being ignored. See the Console Log for details.", @"Window text"),
                                nil, nil, nil,
                                @"skipWarningAboutIgnoredConfigurations",          // Preference about seeing this message again
                                NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
                                nil);
    }
    return dict;
}

// Adds configurations to a dictionary based on input parameters
// Returns TRUE if succeeded, FALSE if one or more configurations were ignored.
//
// If searching gSharedPath, looks for .ovpn and .conf and ignores them even if searching for packages (so we can complain to the user)
-(BOOL)  addConfigsFromPath: (NSString *)               folderPath
            thatArePackages: (BOOL)                     onlyPkgs
                     toDict: (NSMutableDictionary *)    dict
               searchDeeply: (BOOL)                     deep
{
    if (  ! [gConfigDirs containsObject: folderPath]  ) {
        return TRUE;
    }
    
    BOOL ignored = FALSE;
    NSString * file;
    
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: folderPath];

    if (  deep  ) {
        // Search directory and subdirectories
        while (file = [dirEnum nextObject]) {
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
                if (  [dict objectForKey: dispName]  ) {
                    NSLog(@"Tunnelblick Configuration ignored: The name is already being used: %@", fullPath);
                     ignored = TRUE;
                } else {
                    [dict setObject: fullPath forKey: dispName];
                }
            }
        }
    } else {
        // Search directory only, not subdirectories.
        while (file = [dirEnum nextObject]) {
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
                if (   [folderPath isEqualToString: gSharedPath]
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

-(BOOL) userCanEditConfiguration: (NSString *) filePath
{
    NSString * realPath = filePath;
    if (  [[filePath pathExtension] isEqualToString: @"tblk"]  ) {
        realPath = [filePath stringByAppendingPathComponent: @"Contents/Resources/config.ovpn"];
    }
    
    // Must be able to write to parent directory of the file
    if (  ! [gFileMgr isWritableFileAtPath: [realPath stringByDeletingLastPathComponent]]  ) {
        return NO;
    }
    
    // If it doesn't exist, user can create it
    if (  ! [gFileMgr fileExistsAtPath: realPath]  ) {
        return YES;
    }
    
    // If it is writable, user can edit it
    if (  ! [gFileMgr isWritableFileAtPath: realPath]  ) {
        return YES;
    }
    
    // Otherwise must be admin or we must allow non-admins to edit configurations
    return (   [[NSApp delegate] userIsAnAdmin]
            || ( ! [gTbDefaults boolForKey: @"onlyAdminsCanUnprotectConfigurationFiles"] )   );
}

-(void) editConfigurationAtPath: (NSString *) thePath forConnection: (VPNConnection *) connection
{
    NSString * targetPath = [[thePath copy] autorelease];
    if ( ! targetPath  ) {
        targetPath = [gPrivatePath stringByAppendingPathComponent: @"openvpn.conf"];
    }
    
    NSString * targetConfig;
    if (  [[targetPath pathExtension] isEqualToString: @"tblk"]  ) {
        targetConfig = configPathFromTblkPath(targetPath);
        if (  ! targetConfig  ) {
            NSLog(@"No configuration file in %@", targetPath);
            return;
        }
    } else {
        targetConfig = targetPath;
    }
    
    // To allow users to edit and save a configuration file, we allow the user to unprotect the file before editing. 
    // This is because TextEdit cannot save a file if it is protected (owned by root with 644 permissions).
    // But we only do this if the user can write to the file's parent directory, since TextEdit does that to save
    if (  [gFileMgr fileExistsAtPath: targetConfig]  ) {
        BOOL userCanEdit = [self userCanEditConfiguration: targetConfig];
        BOOL isWritable = [gFileMgr isWritableFileAtPath: targetConfig];
        if (  userCanEdit && (! isWritable)  ) {
            // Ask if user wants to unprotect the configuration file
            int button = TBRunAlertPanelExtended(NSLocalizedString(@"The configuration file is protected", @"Window title"),
                                                 NSLocalizedString(@"You may examine the configuration file, but if you plan to modify it, you must unprotect it now. If you unprotect the configuration file now, you will need to provide an administrator username and password the next time you connect using it.", @"Window text"),
                                                 NSLocalizedString(@"Examine", @"Button"),                  // Default button
                                                 NSLocalizedString(@"Unprotect and Modify", @"Button"),     // Alternate button
                                                 NSLocalizedString(@"Cancel", @"Button"),                   // Other button
                                                 @"skipWarningAboutConfigFileProtectedAndAlwaysExamineIt",  // Preference about seeing this message again
                                                 NSLocalizedString(@"Do not warn about this again, always 'Examine'", @"Checkbox name"),
                                                 nil);
            if (  button == NSAlertOtherReturn  ) {
                return;
            }
            if (  button == NSAlertAlternateReturn  ) {
                if (  ! [[ConfigurationManager defaultManager] unprotectConfigurationFile: targetPath]  ) {
                    int button = TBRunAlertPanel(NSLocalizedString(@"Examine the configuration file?", @"Window title"),
                                                 NSLocalizedString(@"Tunnelblick could not unprotect the configuration file. Details are in the Console Log.\n\nDo you wish to examine the configuration file even though you will not be able to modify it?", @"Window text"),
                                                 NSLocalizedString(@"Cancel", @"Button"),    // Default button
                                                 NSLocalizedString(@"Examine", @"Button"),   // Alternate button
                                                 nil);
                    if (  button != NSAlertAlternateReturn  ) {
                        return;
                    }
                }
            }
        }
    }
    
    [connection invalidateConfigurationParse];
    
    [[NSWorkspace sharedWorkspace] openFile: targetConfig withApplication: @"TextEdit"];
}

// Make a private configuration shared, or a shared configuration private
-(void) shareOrPrivatizeAtPath: (NSString *) path
{
    if (  [[path pathExtension] isEqualToString: @"tblk"]  ) {
        NSString * last = lastPartOfPath(path);
        NSString * name = [last stringByDeletingPathExtension];
        if (  [path hasPrefix: gSharedPath]  ) {
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
                if (  result == NSAlertAlternateReturn  ) {
                    return;
                }
            }
            
            NSString * source = [[path copy] autorelease];
            NSString * target = [gPrivatePath stringByAppendingPathComponent: last];
            NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"You have asked to make the '%@' configuration private, instead of shared.", @"Window text"), name];
            AuthorizationRef authRef = [NSApplication getAuthorizationRef: msg];
            if ( authRef == nil ) {
                NSLog(@"Make private authorization cancelled by user");
                return;
            }
            [self copyConfigPath: source
                          toPath: target
                    usingAuthRef: authRef
                      warnDialog: YES
                     moveNotCopy: YES];
        } else if (  [path hasPrefix: gPrivatePath]  ) {
            NSString * source = [[path copy] autorelease];
            NSString * target = [gSharedPath stringByAppendingPathComponent: last];
            NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"You have asked to make the '%@' configuration shared, instead of private.", @"Window text"), name];
            AuthorizationRef authRef = [NSApplication getAuthorizationRef: msg];
            if ( authRef == nil ) {
                NSLog(@"Make shared authorization cancelled by user");
                return;
            }
            [self copyConfigPath: source
                          toPath: target
                    usingAuthRef: authRef
                      warnDialog: YES
                     moveNotCopy: YES];
        }
    }
}

// Unprotect a configuration file without using authorization by replacing the root-owned
// file with a user-owned writable copy so it can be edited (keep root-owned file as a backup)
// Sets ownership/permissions on the copy to the current user:group/0666 without using authorization
// Invoke with path to .ovpn or .conf file or .tblk package
// Returns TRUE if succeeded
// Returns FALSE if can't find config in .tblk or couldn't change owner/permissions or user doesn't have write access to the parent folder
-(BOOL)unprotectConfigurationFile: (NSString *) filePath
{
    NSString * actualConfigPath = [[filePath copy] autorelease];
    if (  [[actualConfigPath pathExtension] isEqualToString: @"tblk"]  ) {
        NSString * actualPath = configPathFromTblkPath(actualConfigPath);
        if (  ! actualPath  ) {
            NSLog(@"No configuration file in %@", actualConfigPath);
            return FALSE;
        }
        actualConfigPath = actualPath;
    }
    
    NSString * parentFolder = [filePath stringByDeletingLastPathComponent];
    if (  ! [gFileMgr isWritableFileAtPath: parentFolder]  ) {
        NSLog(@"No write permission on configuration file's parent directory %@", parentFolder);
        return FALSE;
    }
    
    // Copy the actual configuration file (the .ovpn or .conf file) to a temporary copy,
    // then delete the original and rename the copy back to the original
    // This changes the ownership from root to the current user
    // Although the documentation for copyPath:toPath:handler: says that the file's ownership and permissions are copied,
    // the ownership of a file owned by root is NOT copied.
    // Instead, the copy's owner is the currently logged-in user:group -- which is *exactly* what we want!
    NSString * configTempPath   = [actualConfigPath stringByAppendingPathExtension:@"temp"];
    [gFileMgr tbRemoveFileAtPath:configTempPath handler: nil];
    
    if (  ! [gFileMgr tbCopyPath: actualConfigPath toPath: configTempPath handler: nil]  ) {
        NSLog(@"Unable to copy %@ to %@", actualConfigPath, configTempPath);
        return FALSE;
    }
    
    if (  ! [gFileMgr tbRemoveFileAtPath: actualConfigPath handler: nil]  ) {
        NSLog(@"Unable to delete %@", actualConfigPath);
        return FALSE;
    }
    
    if (  ! [gFileMgr tbMovePath: configTempPath toPath: actualConfigPath handler: nil]  ) {
        NSLog(@"Unable to rename %@ to %@", configTempPath, actualConfigPath);
        return FALSE;
    }
    
    return TRUE;
}

// Parses the configuration file.
// Gives user the option of adding the down-root plugin if appropriate
// Returns with device type: "tun" or "tap", or nil if it can't be determined
// Returns with string "Cancel" if user cancelled
-(NSString *)parseConfigurationPath: (NSString *) cfgPath forConnection: (VPNConnection *) connection
{
    NSString * doNotParseKey = [[connection displayName] stringByAppendingString: @"-doNotParseConfigurationFile"];
    if (  [gTbDefaults boolForKey: doNotParseKey]  ) {
        return nil;
    }
    
    NSString * actualConfigPath = [[cfgPath copy] autorelease];
    if (  [[cfgPath pathExtension] isEqualToString: @"tblk"]  ) {
        actualConfigPath = [actualConfigPath stringByAppendingPathComponent: @"Contents/Resources/config.ovpn"];
    }
    NSString * cfgContents = [[NSString alloc] initWithData: [gFileMgr contentsAtPath: actualConfigPath] encoding:NSUTF8StringEncoding];
    
    NSString * useDownRootPluginKey = [[connection displayName] stringByAppendingString: @"-useDownRootPlugin"];
    NSString * skipWarningKey = [[connection displayName] stringByAppendingString: @"-skipWarningAboutDownroot"];
    if (   ( ! [gTbDefaults boolForKey: useDownRootPluginKey] )
        &&     [gTbDefaults canChangeValueForKey: useDownRootPluginKey]
        && ( ! [gTbDefaults boolForKey: skipWarningKey] )  ) {
        NSString * userOption  = [self parseString: cfgContents forOption: @"user" ];
        NSString * groupOption = [self parseString: cfgContents forOption: @"group"];
        NSString * downOption  = [self parseString: cfgContents forOption: @"down" ];
        
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
                                                     nil);
                if (  result == NSAlertAlternateReturn  ) {
                    [gTbDefaults setBool: TRUE forKey: useDownRootPluginKey];
                } else if (  result == NSAlertOtherReturn  ) {
                    [cfgContents release];
                    return @"Cancel";
                }
            }
        
        if (   (   [gTbDefaults boolForKey: useDownRootPluginKey]
                && [gTbDefaults canChangeValueForKey: useDownRootPluginKey] )
            && (! (userOption || groupOption))  ) {
            [gTbDefaults removeObjectForKey: useDownRootPluginKey];
            NSLog(@"Removed '%@' preference", useDownRootPluginKey);
        }
    }
    
    NSString * devTypeOption = [[self parseString: cfgContents forOption: @"dev-type"] lowercaseString];
    if (  devTypeOption  ) {
        if (   [devTypeOption isEqualToString: @"tun"]
            || [devTypeOption isEqualToString: @"tap"]  ) {
            return devTypeOption;
        } else {
            NSLog(@"The configuration file for '%@' contains a 'dev-type' option, but the argument is not 'tun' or 'tap'. It has been ignored", [connection displayName]);
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
                                nil);
        [cfgContents release];
        return nil;
    }
    [cfgContents release];
    return devOptionFirst3Chars;
}

-(NSString *) parseString: (NSString *) cfgContents forOption: (NSString *) option
{
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
            if (  restRng.location != mainRng.location  ) {
                // Whitespace found, so "value" for option is the rest of the line (if any)
                mainRng.location = restRng.location;
                mainRng.length = mainEnd - mainRng.location;
                NSRange nlRng = [cfgContents rangeOfCharacterFromSet: newline
                                                             options: 0
                                                               range: mainRng];
                NSRange valRng;
                if (  nlRng.length == 0  ) {
                    valRng = NSMakeRange(mainRng.location, mainEnd - mainRng.location);
                } else {
                    valRng = NSMakeRange( mainRng.location, nlRng.location - mainRng.location);
                }
                return [cfgContents substringWithRange: valRng];
            }
            
            // No whitespace after option, so it is no good (either optionXXX or option\n
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

// The filePaths array entries are NSStrings with the path to a .tblk to install.
-(void) openDotTblkPackages: (NSArray *) filePaths
                  usingAuth: (AuthorizationRef) authRef
    skipConfirmationMessage: (BOOL) skipConfirmMsg
          skipResultMessage: (BOOL) skipResultMsg
{
    if (  [gTbDefaults boolForKey: @"doNotOpenDotTblkFiles"]  )  {
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick VPN Configuration Installation Error", @"Window title"),
                        NSLocalizedString(@"Installation of .tblk packages is not allowed", "Window text"),
                        nil, nil, nil);
        [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
        return;
    }
    
    NSMutableArray * sourceList = [NSMutableArray arrayWithCapacity: [filePaths count]];        // Paths to source of files OK to install
    NSMutableArray * targetList = [NSMutableArray arrayWithCapacity: [filePaths count]];        // Paths to destination to install them
    NSMutableArray * deleteList = [NSMutableArray arrayWithCapacity: [filePaths count]];        // Paths to delete
    NSMutableArray * errList    = [NSMutableArray arrayWithCapacity: [filePaths count]];        // Paths to files not installed
    
    // Go through the array, check each .tblk package, and add it to the install list if it is OK
    int keyIx = 0;  // Key used to create unique temporary copies
    NSArray * dest;
    NSMutableArray * innerTblksAlreadyProcessed = [NSMutableArray arrayWithCapacity: 10];
    int i;
    for (i=0; i < [filePaths count]; i++) {
        NSString * path = [filePaths objectAtIndex: i];
        
        // Deal with nested .tblks -- i.e., .tblks inside of a .tblk. One level of that is processed.
        // If there are any .tblks inside the .tblk, the .tblk itself is not created, only the inner .tblks
        // The inner .tblks may be inside subfolders of the outer .tblk, in which case they
        // will be installed into subfolders of the private or shared configurations folder.
        NSString * innerFileName;
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: path];
        while (  innerFileName = [dirEnum nextObject]  ) {
            NSString * fullInnerPath = [path stringByAppendingPathComponent: innerFileName];
            if (   [[innerFileName pathExtension] isEqualToString: @"tblk"]  ) {
                
                // If have already processed a .tblk that contains this one, it is an error
                // because it is a second level of enclosed .tblks.
                // A message is inserted into the log, and the inner-most .tblk is skipped.
                NSString * testPath;
                BOOL nestedTooDeeply = FALSE;
                NSEnumerator * arrayEnum = [innerTblksAlreadyProcessed objectEnumerator];
                while (  testPath = [arrayEnum nextObject]  ) {
                    if (  [fullInnerPath hasPrefix: testPath]  ) {
                        NSLog(@".tblks nested too deeply (only one level of .tblk in a .tblk is allowed) in %@", path);
                        nestedTooDeeply = TRUE;
                        break;
                    }
                }
                
                if (  ! nestedTooDeeply  ) {
                    // This .tblk is not nested too deeply, so process it
                    dest = [self checkOneDotTblkPackage: fullInnerPath withKey: [NSString stringWithFormat: @"%d", keyIx++]];
                    if (  dest  ) {
                        if (  [dest count] == 2  ) {
                            [sourceList addObject: [dest objectAtIndex: 0]];
                            [targetList addObject: [dest objectAtIndex: 1]];
                        } else if (  [dest count] == 1  ) {
                            [deleteList addObject: [dest objectAtIndex: 0]];
                        } else {
                            NSLog(@"Invalid dest = %@ for .tblk %@ withKey %d", dest, fullInnerPath, keyIx);
                        }
                        
                    } else {
                        [errList addObject: path];
                    }
                    [innerTblksAlreadyProcessed addObject: fullInnerPath];
                }
            }
        }
        
        if (  [innerTblksAlreadyProcessed count] == 0  ) {
            dest = [self checkOneDotTblkPackage: path withKey: [NSString stringWithFormat: @"%d", keyIx++]];
            if (  dest  ) {
                if (  [dest count] == 2  ) {
                    [sourceList addObject: [dest objectAtIndex: 0]];
                    [targetList addObject: [dest objectAtIndex: 1]];
                } else if (  [dest count] == 1  ) {
                    [deleteList addObject: [dest objectAtIndex: 0]];
                } else {
                    NSLog(@"Invalid dest = %@ for .tblk %@ withKey %d", dest, path, keyIx);
                }
            } else {
                [errList addObject: path];
            }
        } else {
            [innerTblksAlreadyProcessed removeAllObjects];
        }
    }
    
    if (   ([sourceList count] == 0)
        && ([deleteList count] == 0)  ) {
        if (  [errList count] != 0  ) {
            TBRunAlertPanel(NSLocalizedString(@"Tunnelblick VPN Configuration Installation Error", @"Window title"),
                            NSLocalizedString(@"There was a problem with one or more configurations. Details are in the Console Log\n\n", @"Window text"),
                            nil, nil, nil);
        }
        return;
    }
    
    NSString * errPrefix;
    if (  [errList count] == 0  ) {
        errPrefix = @"";
    } else {
        if (  [errList count] == 1  ) {
            errPrefix = NSLocalizedString(@"There was a problem with one configuration. Details are in the Console Log\n\n", @"Window text");
        } else {
            errPrefix = [NSString stringWithFormat:
                         NSLocalizedString(@"There was a problem with %d configurations. Details are in the Console Log\n\n", @"Window text"),
                         (unsigned) [errList count]];
        }
    }
    
    NSString * windowText = nil;
    if (  [deleteList count] == 1  ) {
        windowText = NSLocalizedString(@"Do you wish to uninstall one configuration", @"Window text");
    } else if (  [deleteList count] > 1  ) {
        windowText = [NSString stringWithFormat:
                      NSLocalizedString(@"Do you wish to uninstall %d configurations", @"Window text"),
                      (unsigned) [deleteList count]];
    }
    
    if (  [sourceList count] > 0  ) {
        if (  [sourceList count] == 1  ) {
            if (  windowText  ) {
                windowText = [windowText stringByAppendingString:
                              NSLocalizedString(@" and install one configuration", @"Window text")];
            } else {
                // No message if only installing a single configuration
                ;
            }
        } else if (  [sourceList count] > 0  ) {
            if (  windowText  ) {
                windowText = [windowText stringByAppendingString:
                              [NSString stringWithFormat:
                               NSLocalizedString(@" and install %d configurations", @"Window text"),
                               (unsigned) [sourceList count]]];
            } else {
                windowText = [NSString stringWithFormat:
                              NSLocalizedString(@"Do you wish to install %d configurations", @"Window text"),
                              (unsigned) [sourceList count]];
            }
        }
    }
    
    if (  windowText  ) {
        if (   ( ! skipConfirmMsg ) || ( [errList count] != 0 )  ) {
            int result = TBRunAlertPanel(NSLocalizedString(@"Perform installation?", @"Window title"),
                                         [NSString stringWithFormat: @"%@%@?", errPrefix, windowText],
                                         NSLocalizedString(@"OK", @"Button"),       // Default
                                         nil,                                       // Alternate
                                         NSLocalizedString(@"Cancel", @"Button"));  // Other
            if (  result == NSAlertOtherReturn  ) {
                if (  [errList count] == 0  ) {
                    [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyCancel];
                } else {
                    [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
                }
                return;
            }
        }
    }
    
    // **************************************************************************************
    // Install the packages
    
    AuthorizationRef localAuth = authRef;
    if ( ! authRef  ) {    // If we weren't given an AuthorizationRef, get our own
        NSString * msg = NSLocalizedString(@"Tunnelblick needs to install and/or uninstall one or more Tunnelblick VPN Configurations.", @"Window text");
        localAuth = [NSApplication getAuthorizationRef: msg];
    }
    
    if (  ! localAuth  ) {
        NSLog(@"Configuration installer: The Tunnelblick VPN Configuration installation was cancelled by the user.");
        [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyCancel];
        return;
    }
    
    int nErrors = 0;

    for (  i=0; i < [deleteList count]; i++  ) {
        NSString * target = [deleteList objectAtIndex: i];
        if (  ! [self deleteConfigPath: target
                          usingAuthRef: localAuth
                            warnDialog: NO]  ) {
            nErrors++;
        }
    }
    
    for (  i=0; i < [sourceList count]; i++  ) {
        NSString * source = [sourceList objectAtIndex: i];
        NSString * target = [targetList objectAtIndex: i];
        if (  ! [self copyConfigPath: source
                              toPath: target
                        usingAuthRef: localAuth
                          warnDialog: NO
                         moveNotCopy: NO]  ) {
            nErrors++;
            [gFileMgr tbRemoveFileAtPath:target handler: nil];
        }
        NSRange r = [source rangeOfString: @"/TunnelblickTemporaryDotTblk-"];
        if (  r.length != 0  ) {
            [gFileMgr tbRemoveFileAtPath:[source stringByDeletingLastPathComponent] handler: nil];
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
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick VPN Configuration Installation Error", @"Window title"),
                        msg,
                        nil, nil, nil);
        [NSApp replyToOpenOrPrint: NSApplicationDelegateReplyFailure];
    } else {
        int nOK = [sourceList count];
        int nUninstalled = [deleteList count];
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
            TBRunAlertPanel(NSLocalizedString(@"Tunnelblick VPN Configuration Installation", @"Window title"),
                            msg,
                            nil, nil, nil);
        }
        [NSApp replyToOpenOrPrint: NSApplicationDelegateReplySuccess];
    }
}

// Checks one .tblk package to make sure it should be installed
//     Returns an array with [source, dest] paths if it should be installed
//     Returns an array with [source] if it should be UNinstalled
//     Returns an empty array if the user cancelled the installation
//     Returns nil if an error occurred
// If filePath is a nested .tblk (i.e., a .tblk contained within another .tblk), the destination path will be a subfolder of the private or shared configurations folder
-(NSArray *) checkOneDotTblkPackage: (NSString *) filePath withKey: (NSString *) key
{
    if (   [filePath hasPrefix: gPrivatePath]
        || [filePath hasPrefix: gSharedPath]
        || [filePath hasPrefix: gDeployPath]  ) {
        NSLog(@"Configuration installer: Tunnelblick VPN Configuration is already installed: %@", filePath);
        TBRunAlertPanel(NSLocalizedString(@"Configuration Installation Error", @"Window title"),
                        NSLocalizedString(@"You cannot install a Tunnelblick VPN configuration from an installed copy.\n\nAn administrator can copy the installation and install from the copy.", @"Window text"),
                        nil, nil, nil);
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
    NSString * pathToTblk = [self getPackageToInstall: filePath withKey: key];
    if (  ! pathToTblk  ) {
        return nil;                     // Error occured
    }
    if (  [pathToTblk length] == 0) {
        return [NSArray array];         // User cancelled
    }
    
    // **************************************************************************************
    // Get the following data from Info.plist (and make sure nothing else is in it except TBPreference***):
    
    NSString * pkgId;
    NSString * pkgVersion;
//  NSString * pkgShortVersionString;
    NSString * pkgPkgVersion;
    NSString * pkgReplaceIdentical;
    NSString * pkgSharePackage;
    BOOL       pkgDoUninstall = FALSE;
    BOOL       pkgUninstallFailOK = FALSE;
    
    NSString * infoPath = [pathToTblk stringByAppendingPathComponent: @"Contents/Info.plist"];
    NSDictionary * infoDict = [NSDictionary dictionaryWithContentsOfFile: infoPath];
    
    if (  infoDict  ) {
        pkgId = [self getLowerCaseStringForKey: @"CFBundleIdentifier" inDictionary: infoDict defaultTo: nil];
        
        pkgVersion = [self getLowerCaseStringForKey: @"CFBundleVersion" inDictionary: infoDict defaultTo: nil];
        
        //  pkgShortVersionString = [self getLowerCaseStringForKey: @"CFBundleShortVersionString" inDictionary: infoDict defaultTo: nil];
        
        pkgPkgVersion = [self getLowerCaseStringForKey: @"TBPackageVersion" inDictionary: infoDict defaultTo: nil];
        if (  pkgPkgVersion  ) {
            if (  ! [pkgPkgVersion isEqualToString: @"1"]  ) {
                NSLog(@"Configuration installer: Unknown 'TBPackageVersion' = '%@' (only '1' is allowed) in %@", pkgPkgVersion, infoPath);
                pkgIsOK = FALSE;
            }
        } else {
            NSLog(@"Configuration installer: Missing 'TBPackageVersion' in %@", infoPath);
            pkgIsOK = FALSE;
        }
        
        pkgReplaceIdentical = [self getLowerCaseStringForKey: @"TBReplaceIdentical" inDictionary: infoDict defaultTo: @"ask"];
        NSArray * okValues = [NSArray arrayWithObjects: @"no", @"yes", @"force", @"ask", nil];
        if ( ! [okValues containsObject: pkgReplaceIdentical]  ) {
            NSLog(@"Configuration installer: Invalid value '%@' (only 'no', 'yes', 'force', or 'ask' are allowed) for 'TBReplaceIdentical' in %@", pkgReplaceIdentical, infoPath);
            pkgIsOK = FALSE;
        }
        
        pkgSharePackage = [self getLowerCaseStringForKey: @"TBSharePackage" inDictionary: infoDict defaultTo: @"ask"];
        okValues = [NSArray arrayWithObjects: @"private", @"shared", @"ask", nil];
        if ( ! [okValues containsObject: pkgSharePackage]  ) {
            NSLog(@"Configuration installer: Invalid value '%@' (only 'shared', 'private', or 'ask' are allowed) for 'TBSharePackage' in %@", pkgSharePackage, infoPath);
            pkgIsOK = FALSE;
        }
        
        id obj = [infoDict objectForKey: @"TBUninstall"];
        if (  obj != nil  ) {
            pkgDoUninstall = TRUE;
            if (  [obj isEqualToString: @"ignoreError"]  ) {
                pkgUninstallFailOK = TRUE;
            }
        }
        
        NSString * key;
        NSArray * validKeys = [NSArray arrayWithObjects: @"CFBundleIdentifier", @"CFBundleVersion", @"CFBundleShortVersionString",
                               @"TBPackageVersion", @"TBReplaceIdentical", @"TBSharePackage", @"TBUninstall", nil];
        NSEnumerator * e = [infoDict keyEnumerator];
        while (  key = [e nextObject]  ) {
            if (  ! [validKeys containsObject: key]  ) {
                if (  ! [key hasPrefix: @"TBPreference"]  ) {
                    NSLog(@"Configuration installer: Unknown key '%@' in %@", key, infoPath);
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

        
    // **************************************************************************************
    // Make sure there is exactly one configuration file
    NSString * pathToConfigFile = nil;
    int numberOfConfigFiles = 0;
    BOOL haveConfigDotOvpn = FALSE;
    NSString * file;
    NSString * folder = [pathToTblk stringByAppendingPathComponent: @"Contents/Resources"];
    NSDirectoryEnumerator *dirEnum = [gFileMgr enumeratorAtPath: folder];
    while (file = [dirEnum nextObject]) {
        if (  itemIsVisible([folder stringByAppendingPathComponent: file])  ) {
            NSString * ext = [file pathExtension];
            if (  [file isEqualToString: @"config.ovpn"]  ) {
                pathToConfigFile = [folder stringByAppendingPathComponent: @"config.ovpn"];
                haveConfigDotOvpn = TRUE;
                numberOfConfigFiles++;
            } else if (  [ext isEqualToString: @"ovpn"] || [ext isEqualToString: @"conf"]  ) {
                pathToConfigFile = [folder stringByAppendingPathComponent: file];
                numberOfConfigFiles++;
            }
        }
    }
    
    if (  ! haveConfigDotOvpn  ) {
        NSLog(@"Configuration installer: No configuration file '/Contents/Resources/config.ovpn' in %@", tryDisplayName);
        pkgIsOK = FALSE;
    }
    
    if (  numberOfConfigFiles != 1  ) {
        NSLog(@"Configuration installer: Exactly one configuration file is allowed in a .tblk package. %d configuration files were found in %@", numberOfConfigFiles, tryDisplayName);
        pkgIsOK = FALSE;
    }
    
    // **************************************************************************************
    // Make sure the configuration file is not the sample file
    if (   pathToConfigFile
        && ( ! pkgDoUninstall)
        && [self isSampleConfigurationAtPath: pathToConfigFile]  ) {
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
        while (key = [e nextObject]) {
            NSString * path = [[[NSApp delegate] myConfigDictionary] objectForKey: key];
            NSString * last = lastPartOfPath(path);
            NSString * oldDisplayFirstPart = firstPathComponent(last);
            if (  [[oldDisplayFirstPart pathExtension] isEqualToString: @"tblk"]  ) {
                NSDictionary * oldInfo = [NSDictionary dictionaryWithContentsOfFile: [path stringByAppendingPathComponent: @"Contents/Info.plist"]];
                NSString * oldVersion = [oldInfo objectForKey: @"CFBundleVersion"];
                NSString * oldIdentifier = [self getLowerCaseStringForKey: @"CFBundleIdentifier" inDictionary: oldInfo defaultTo: nil];
                if (  [oldIdentifier isEqualToString: pkgId]) {
                    if (  [pkgReplaceIdentical isEqualToString: @"no"]  ) {
                        NSLog(@"Configuration installer: Tunnelblick VPN Configuration %@ has NOT been %@installed: TBReplaceOption=NO.",
                              tryDisplayName, (pkgDoUninstall ? @"un" : @""));
                        if (  pkgUninstallFailOK  ) {
                            return [NSArray array];
                        } else {
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
                                return nil;
                            }
                        } else {
                            // Fall through to (un)install
                        }
                    } else if (  [pkgReplaceIdentical isEqualToString: @"ask"]  ) {
                        NSString * msg;
                        replacementPath = [[[NSApp delegate] myConfigDictionary] objectForKey: key];
                        NSString * sharedPrivateDeployed;
                        if (  [replacementPath hasPrefix: gSharedPath]  ) {
                            sharedPrivateDeployed = NSLocalizedString(@" (Shared)", @"Window title");
                        } else if (  [replacementPath hasPrefix: gPrivatePath]  ) {
                            sharedPrivateDeployed = NSLocalizedString(@" (Private)", @"Window title");
                        } else {
                            sharedPrivateDeployed = NSLocalizedString(@" (Deployed)", @"Window title");
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
                        if (  result == NSAlertAlternateReturn  ) {
                            NSLog(@"Configuration installer: Tunnelblick VPN Configuration %@ (un)installation declined by user.", tryDisplayName);
                            return [NSArray array];
                        }
                    }
                    
                    tryDisplayName = [last stringByDeletingPathExtension];
                    replacementPath = [[[NSApp delegate] myConfigDictionary] objectForKey: key];
                    if (  [replacementPath hasPrefix: gSharedPath]  ) {
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
        while (   ([tryDisplayName length] == 0)
               || [[[NSApp delegate] myConfigDictionary] objectForKey: tryDisplayName]  ) {
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
            [panelDict setObject:[NSURL fileURLWithPath:[[NSBundle mainBundle]
                                                         pathForResource:@"tunnelblick"
                                                         ofType: @"icns"]]               forKey:(NSString *)kCFUserNotificationIconURLKey];
            SInt32 error;
            CFUserNotificationRef notification;
            CFOptionFlags response;
            
            // Get a name from the user
            notification = CFUserNotificationCreate(NULL, 30, 0, &error, (CFDictionaryRef)panelDict);
            [panelDict release];
            
            if((error) || (CFUserNotificationReceiveResponse(notification, 0, &response))) {
                CFRelease(notification);    // Couldn't receive a response
                NSLog(@"Configuration installer: The Tunnelblick VPN Package has NOT been installed.\n\nAn unknown error occured.", tryDisplayName);
                return nil;
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
            if (  replacementPath  ) {
                // **************************************************************************************
                // Indicate the package is to be UNinstalled
                NSString * tblkName = [tryDisplayName stringByAppendingPathExtension: @"tblk"];
                NSString * pathPrefix;
                if (  [pkgSharePackage isEqualToString: @"private"]  ) {
                    pathPrefix = gPrivatePath;
                } else {
                    pathPrefix = gSharedPath;
                }
                if (  subfolder  ) {
                    pathPrefix = [pathPrefix stringByAppendingPathComponent: subfolder];
                }
                return [NSArray arrayWithObject: [pathPrefix stringByAppendingPathComponent: tblkName]];
            } else {
                NSLog(@"Cannot find configuration %@ to be uninstalled.", tryDisplayName);
                if (  pkgUninstallFailOK  ) {
                    return [NSArray array];
                } else {
                    return nil;
                }
            }
        }
        
        // **************************************************************************************
        // Ask if it should be shared or private
        if ( ! replacementPath  ) {
            if (  [pkgSharePackage isEqualToString: @"ask"]  ) {
                int result = TBRunAlertPanel(NSLocalizedString(@"Install Configuration For All Users?", @"Window title"),
                                             [NSString stringWithFormat: NSLocalizedString(@"Do you wish to install the '%@' configuration so that all users can use it, or so that only you can use it?\n\n", @"Window text"), tryDisplayName],
                                             NSLocalizedString(@"Only Me", @"Button"),      //Default button
                                             NSLocalizedString(@"All Users", @"Button"),    // Alternate button
                                             NSLocalizedString(@"Cancel", @"Button"));      // Alternate button);
                if (  result == NSAlertDefaultReturn  ) {
                    pkgSharePackage = @"private";
                } else if (  result == NSAlertAlternateReturn  ) {
                    pkgSharePackage = @"shared";
                } else {
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
            pathPrefix = gSharedPath;
        }
        if (  subfolder  ) {
            pathPrefix = [pathPrefix stringByAppendingPathComponent: subfolder];
        }
        return [NSArray arrayWithObjects: pathToTblk, [pathPrefix stringByAppendingPathComponent: tblkName], nil];
    }
    
    return nil;
}

-(NSString *) getLowerCaseStringForKey: (NSString *) key inDictionary: (NSDictionary *) dict defaultTo: (id) replacement
{
    id retVal;
    retVal = [[dict objectForKey: key] lowercaseString];
    if (  retVal  ) {
        if (  ! [[retVal class] isSubclassOfClass: [NSString class]]  ) {
            NSLog(@"The value for Info.plist key '%@' is not a string. The entry will be ignored.");
            return nil;
        }
    } else {
        retVal = replacement;
    }

    return retVal;
}

// Does simple checks on a .tblk package.
// If it has a single folder at the top level named "Contents", returns the .tblk's path without looking inside "Contents"
// If it can be "fixed", returns the path to a temporary copy with the problems fixed.
// If it is empty, and the user chooses, a path to a temporay copy with the sample configuration file is returned.
// If it is empty, and the user cancels, an empty string (@"") is returned.
// Otherwise, returns nil to indicate an error;
// Can fix the following:
//   * Package contains, or has a single folder which contains, one .ovpn or .conf, zero or one Info.plist, and any number of .key, .crt, etc. files:
//          Moves the .ovpn or .conf to Contents/Resources/config.ovpn
//          Moves the .key, .crt, etc. files to Contents/Resources
-(NSString *) getPackageToInstall: (NSString *) thePath withKey: (NSString *) key;

{
    NSMutableArray * pkgList = [[gFileMgr tbDirectoryContentsAtPath: thePath] mutableCopy];
    if (  ! pkgList  ) {
        return nil;
    }
    
    // Remove invisible files and folders
    int i;
    for (i=0; i < [pkgList count]; i++) {
        if (  ! itemIsVisible([pkgList objectAtIndex: i])  ) {
            [pkgList removeObjectAtIndex: i];
            i--;
        }
    }
    
    // If empty package, make a sample config
    if (  [pkgList count] == 0  ) {
        int result = TBRunAlertPanel(NSLocalizedString(@"Install Sample Configuration?", @"Window Title"),
                                     [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick VPN Configuration '%@' is empty. Do you wish to install a sample configuration with that name?", @"Window text"),
                                      [[thePath lastPathComponent]stringByDeletingPathExtension]],
                                     NSLocalizedString(@"Install Sample", @"Button"),
                                     NSLocalizedString(@"Cancel", @"Button"),
                                     nil);
        if (  result != NSAlertDefaultReturn  ) {
            [pkgList release];
            return @"";
        }

        [pkgList release];
        return [self makeTemporarySampleTblkWithName: [thePath lastPathComponent] andKey: key];
    }
    
    // If the .tblk contains only a single subfolder, "Contents", then return .tblk path
    NSString * firstItem = [pkgList objectAtIndex: 0];
    if (   ([pkgList count] == 1)
        && ( [[firstItem lastPathComponent] isEqualToString: @"Contents"])  ) {
        [pkgList release];
        return [[thePath copy] autorelease];
    }
    
    NSString * searchPath;    // Use this from here on
    
    // If the .tblk contains only a single subfolder (not "Contents"), look in that folder for stuff to put into Contents/Resources
    BOOL isDir;
    if (   ([pkgList count] == 1)
        && [gFileMgr fileExistsAtPath: firstItem isDirectory: &isDir]
        && isDir  ) {
        [pkgList release];
        pkgList = [[gFileMgr tbDirectoryContentsAtPath: firstItem] mutableCopy];
        searchPath = [[firstItem copy] autorelease];
    } else {
        searchPath = [[thePath copy] autorelease];
    }
    
    NSArray * extensionsFor600Permissions = [NSArray arrayWithObjects: @"cer", @"crt", @"der", @"key", @"p12", @"p7b", @"p7c", @"pem", @"pfx", nil];

    // Look through the package and see what's in it
    unsigned int nConfigs = 0;   // # of configuration files we've seen
    unsigned int nInfos   = 0;   // # of Info.plist files we've seen
    unsigned int nTblks   = 0;   // # of *.tblk packages we've seen
    unsigned int nUnknown = 0;   // # of folders or unknown files we've seen
    for (i=0; i < [pkgList count]; i++) {
        NSString * itemPath = [searchPath stringByAppendingPathComponent: [pkgList objectAtIndex: i]];
        NSString * ext = [itemPath pathExtension];
        if (  itemIsVisible(itemPath)  ) {
            if (   [gFileMgr fileExistsAtPath: itemPath isDirectory: &isDir]
                && ( ! isDir )  ) {
                if (   [ext isEqualToString: @"ovpn"] || [ext isEqualToString: @"conf"]  ) {
                    nConfigs++;
                } else if (  [ext isEqualToString: @"tblk"]  ) {
                    nTblks++;
                } else if (  [[itemPath lastPathComponent] isEqualToString: @"Info.plist"]  ) {
                    nInfos++;
                } else if (  [ext isEqualToString: @"sh"]  ) {
                    ;
                } else if (  [extensionsFor600Permissions containsObject: ext]  ) {
                    ;
                } else {
                    nUnknown++;
                }
            } else {
                nUnknown++;
            }
        }
    }
    
    if (  nTblks == 0  ) {
        if ( nConfigs == 0  ) {
            NSLog(@"Must have one configuration in a .tblk, %d were found in %@", nConfigs, searchPath);
            [pkgList release];
            return nil;
        }
        if (  nInfos > 1  ) {
            NSLog(@"Must have at most one Info.plist in a .tblk, %d were found in %@", nInfos, searchPath);
            [pkgList release];
            return nil;
        }
    }
    
    if (  nUnknown != 0  ) {
        NSLog(@"Folder(s) or unrecognized file(s) found in %@", searchPath);
        [pkgList release];
        return nil;
    }
    // Create an empty .tblk and copy stuff in the folder to its Contents/Resources (Copy Info.plist to Contents)
    NSString * emptyTblk = [self makeEmptyTblk: thePath withKey: key];
    if (  ! emptyTblk  ) {
        [pkgList release];
        return nil;
    }
    
    NSString * emptyResources = [emptyTblk stringByAppendingPathComponent: @"Contents/Resources"];

    for (i=0; i < [pkgList count]; i++) {
        NSString * oldPath = [searchPath stringByAppendingPathComponent: [pkgList objectAtIndex: i]];
        NSString * newPath;
        NSString * ext = [oldPath pathExtension];
        if (   [ext isEqualToString: @"ovpn"] || [ext isEqualToString: @"conf"]  ) {
            newPath = [emptyResources stringByAppendingPathComponent: @"config.ovpn"];
        } else if (  [[oldPath lastPathComponent] isEqualToString: @"Info.plist"]  ) {
            newPath = [[emptyResources stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"Info.plist"];
        } else {
            newPath = [emptyResources stringByAppendingPathComponent: [oldPath lastPathComponent]];
        }

        if (  ! [gFileMgr tbCopyPath: oldPath toPath: newPath handler: nil]  ) {
            NSLog(@"Unable to copy %@ to %@", oldPath, newPath);
            [pkgList release];
            return nil;
        }
    }
    
    [pkgList release];
    return emptyTblk;
}

-(NSString *) makeTemporarySampleTblkWithName: (NSString *) name andKey: (NSString *) key
{
    NSString * emptyTblk = [self makeEmptyTblk: name withKey: key];
    if (  ! emptyTblk  ) {
        NSLog(@"Unable to create temporary .tblk");
        return nil;
    }
    
    NSString * source = [[NSBundle mainBundle] pathForResource: @"openvpn" ofType: @"conf"];
    NSString * target = [emptyTblk stringByAppendingPathComponent: @"Contents/Resources/config.ovpn"];
    if (  ! [gFileMgr tbCopyPath: source toPath: target handler: nil]  ) {
        NSLog(@"Unable to copy sample configuration file to %@", target);
        return nil;
    }
    return emptyTblk;
}    

// Creates an "empty" .tblk with name taken from input argument, and with Contents/Resources created,
// in a newly-created temporary folder
// Returns nil on error, or with the path to the .tblk
-(NSString *) makeEmptyTblk: (NSString *) thePath withKey: (NSString *) key
{
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

// Given paths to a configuration (either a .conf or .ovpn file, or a .tblk package) in one of the gConfigDirs
// (~/Library/Application Support/Tunnelblick/Configurations, /Library/Application Support/Tunnelblick/Shared, or /Resources/Deploy,
// and an alternate config in /Library/Application Support/Tunnelblick/Users/<username>/
// Returns the path to use, or nil if can't use either one
-(NSString *) getConfigurationToUse:(NSString *)cfgPath orAlt:(NSString *)altCfgPath
{
    if (  [[ConfigurationManager defaultManager] isSampleConfigurationAtPath: cfgPath]  ) {             // Don't use the sample configuration file
        return nil;
    }
    
    if (  ! [self configNotProtected:cfgPath]  ) {                              // If config is protected
        if (  ! [gTbDefaults boolForKey:@"useShadowConfigurationFiles"]  ) {    //    If not using shadow configuration files
            return cfgPath;                                                     //    Then use it
        } else { 
            NSString * folder = firstPartOfPath(cfgPath);                       //    Or if are using shadow configuration files
            if (  ! [folder isEqualToString: gPrivatePath]  ) {                 //    And in Shared or Deploy (even if using shadow copies)
                return cfgPath;                                                 //    Then use it (we don't need to shadow copy them)
            }
        }
    }
    
    // Repair the configuration file or use the alternate
    AuthorizationRef authRef;
    if (   (! [self onRemoteVolume:cfgPath] )
        && (! [gTbDefaults boolForKey:@"useShadowConfigurationFiles"] )
        && ([cfgPath hasPrefix: gPrivatePath] )  ) {
        
        // We don't use a shadow configuration file
		NSLog(@"Configuration file %@ needs ownership/permissions repair", cfgPath);
        authRef = [NSApplication getAuthorizationRef: NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the configuration file to secure it.", @"Window text")]; // Try to repair regular config
        if ( authRef == nil ) {
            NSLog(@"Repair authorization cancelled by user");
            AuthorizationFree(authRef, kAuthorizationFlagDefaults);	
            return nil;
        }
        if( ! [[ConfigurationManager defaultManager] protectConfigurationFile:cfgPath usingAuth:authRef] ) {
            AuthorizationFree(authRef, kAuthorizationFlagDefaults);
            return nil;
        }
        AuthorizationFree(authRef, kAuthorizationFlagDefaults);                         // Repair worked, so return the regular conf
        return cfgPath;
    } else {
        
        // We should use a shadow configuration file
        if ( [gFileMgr fileExistsAtPath:altCfgPath] ) {                                 // See if alt config exists
            // Alt config exists
            if ( [gFileMgr contentsEqualAtPath:cfgPath andPath:altCfgPath] ) {          // See if files are the same
                // Alt config exists and is the same as regular config
                if ( [self configNotProtected:altCfgPath] ) {                            // Check ownership/permissions
                    // Alt config needs repair
                    NSLog(@"The shadow copy of configuration file %@ needs ownership/permissions repair", cfgPath);
                    authRef = [NSApplication getAuthorizationRef: NSLocalizedString(@"Tunnelblick needs to repair ownership/permissions of the shadow copy of the configuration file to secure it.", @"Window text")]; // Repair if necessary
                    if ( authRef == nil ) {
                        NSLog(@"Repair authorization cancelled by user");
                        AuthorizationFree(authRef, kAuthorizationFlagDefaults);
                        return nil;
                    }
                    if(  ! [[ConfigurationManager defaultManager] protectConfigurationFile:altCfgPath usingAuth:authRef]  ) {
                        AuthorizationFree(authRef, kAuthorizationFlagDefaults);
                        return nil;                                                     // Couldn't repair alt file
                    }
                    AuthorizationFree(authRef, kAuthorizationFlagDefaults);
                }
                return altCfgPath;                                                      // Return the alt config
            } else {
                // Alt config exists but is different
                NSLog(@"The shadow copy of configuration file %@ needs to be updated from the original", cfgPath);
                authRef = [NSApplication getAuthorizationRef: NSLocalizedString(@"Tunnelblick needs to update the shadow copy of the configuration file from the original.", @"Window text")];// Overwrite it with the standard one and set ownership & permissions
                if ( authRef == nil ) {
                    NSLog(@"Authorization for update of shadow copy cancelled by user");
                    AuthorizationFree(authRef, kAuthorizationFlagDefaults);	
                    return nil;
                }
                if ( [self copyConfigPath: cfgPath toPath: altCfgPath usingAuthRef: authRef warnDialog: YES moveNotCopy: NO] ) {
                    AuthorizationFree(authRef, kAuthorizationFlagDefaults);
                    if (  [self configNotProtected: altCfgPath]  ) {
                        NSLog(@"Unable to secure alternate configuration");
                        return nil;
                    }
                    return altCfgPath;                                                  // And return the alt config
                } else {
                    AuthorizationFree(authRef, kAuthorizationFlagDefaults);             // Couldn't overwrite alt file with regular one
                    return nil;
                }
            }
        } else {
            // Alt config doesn't exist. We must create it (and maybe the folders that contain it)
            NSLog(@"Creating shadow copy of configuration file %@", cfgPath);
            
            // Folder creation code below needs alt config to be in /Library/Application Support/Tunnelblick/Users/<username>/xxx.conf
            NSString * altCfgFolderPath  = [altCfgPath stringByDeletingLastPathComponent]; // Strip off xxx.conf to get path to folder that holds it
            //                                                                             // (But leave any subfolders) 
            if (  ! [altCfgFolderPath hasPrefix: [NSString stringWithFormat: @"/Library/Application Support/Tunnelblick/Users", NSUserName()]]  ) {
                NSLog(@"Internal Tunnelblick error: altCfgPath\n%@\nmust be in\n/Library/Application Support/Tunnelblick/Users/<username>", altCfgFolderPath);
                return nil;
            }
            
            authRef = [NSApplication getAuthorizationRef: NSLocalizedString(@"Tunnelblick needs to create a shadow copy of the configuration file.", @"Window text")]; // Create folders if they don't exist:
            if ( authRef == nil ) {
                NSLog(@"Authorization to create a shadow copy of the configuration file cancelled by user.");
                AuthorizationFree(authRef, kAuthorizationFlagDefaults);	
                return nil;
            }
            if ( ! [self makeSureFolderExistsAtPath: altCfgFolderPath usingAuth: authRef] ) {     // /Library/.../<username>/[subdirs...]
                AuthorizationFree(authRef, kAuthorizationFlagDefaults);
                return nil;
            }
            if ( [self copyConfigPath: cfgPath toPath: altCfgPath usingAuthRef: authRef warnDialog: YES moveNotCopy: NO] ) {    // Copy the config to the alt config
                AuthorizationFree(authRef, kAuthorizationFlagDefaults);
                if (  [self configNotProtected: altCfgPath]  ) {
                    NSLog(@"Unable to secure alternate configuration");
                    return nil;
                }
                return altCfgPath;                                                              // Return the alt config
            }
            AuthorizationFree(authRef, kAuthorizationFlagDefaults);                             // Couldn't make alt file
            return nil;
        }
    }
}

-(BOOL) isSampleConfigurationAtPath: (NSString *) cfgPath
{
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
    
    int button = TBRunAlertPanel(NSLocalizedString(@"You cannot use the sample configuration", @"Window title"),
                                 NSLocalizedString(@"You have tried to use a configuration file that is the same as the sample configuration file installed by Tunnelblick. The configuration file must be modified to connect to a VPN. You may also need other files, such as certificate or key files, to connect to the VPN.\n\nConsult your network administrator or your VPN service provider to obtain configuration and other files or the information you need to modify the sample file.\n\nOpenVPN documentation is available at\n\n     http://openvpn.net/index.php/open-source/documentation.html\n", @"Window text"),
                                 NSLocalizedString(@"Cancel", @"Button"),                           // Default button
                                 NSLocalizedString(@"Go to the OpenVPN documentation on the web", @"Button"), // Alternate button
                                 nil);                                                              // No Other button
	
    if( button == NSAlertAlternateReturn ) {
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://openvpn.net/index.php/open-source/documentation.html"]];
	}
    
    return TRUE;
}

// Checks ownership and permisions of .tblk package, or .ovpn or .conf file
// Returns YES if not secure, NO if secure
-(BOOL)configNotProtected:(NSString *)configFile 
{
    if (  [[configFile pathExtension] isEqualToString: @"tblk"]  ) {
        BOOL isDir;
        if (  [gFileMgr fileExistsAtPath: configFile isDirectory: &isDir]
            && isDir  ) {
            return folderContentsNeedToBeSecuredAtPath(configFile);
        } else {
            return YES;
        }
    }
    
    NSDictionary *fileAttributes = [gFileMgr tbFileAttributesAtPath:configFile traverseLink:YES];
    unsigned long perms = [fileAttributes filePosixPermissions];
    NSString *octalString = [NSString stringWithFormat:@"%o",perms];
    NSNumber *fileOwner = [fileAttributes fileOwnerAccountID];
    
    if ( (![octalString isEqualToString:@"644"])  || (![fileOwner isEqualToNumber:[NSNumber numberWithInt:0]])) {
        // NSLog(@"Configuration file %@ has permissions: 0%@, is owned by %@ and needs repair",configFile,octalString,fileOwner);
        return YES;
    }
    return NO;
}

-(BOOL) checkPermissions: (NSString *) permsShouldHave forPath: (NSString *) path
{
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] tbFileAttributesAtPath: path traverseLink:YES];
    unsigned long perms = [fileAttributes filePosixPermissions];
    NSString *octalString = [NSString stringWithFormat:@"%o",perms];
    
    return [octalString isEqualToString: permsShouldHave];
}

// Returns TRUE if a file is on a remote volume or statfs on it fails, FALSE otherwise
-(BOOL) onRemoteVolume:(NSString *)cfgPath
{
    const char * fileName = [gFileMgr fileSystemRepresentationWithPath: cfgPath];
    struct statfs stats_buf;
    
    if (  0 == statfs(fileName, &stats_buf)  ) {
        if (  (stats_buf.f_flags & MNT_LOCAL) == MNT_LOCAL  ) {
            return FALSE;
        }
    } else {
        NSLog(@"statfs on %@ failed; assuming it is a remote volume\nError was '%s'", cfgPath, strerror(errno));
    }
    return TRUE;   // Network volume or error accessing the file's data.
}

// Attempts to protect a configuration file
// Returns TRUE if succeeded, FALSE if failed, having already output an error message to the console log
-(BOOL)protectConfigurationFile: (NSString *) configFilePath usingAuth: (AuthorizationRef) authRef
{
    NSString *launchPath = [[NSBundle mainBundle] pathForResource:@"installer" ofType:nil];

    NSArray * arguments = [NSArray arrayWithObjects: @"0", configFilePath, nil];
    
    NSLog(@"Securing configuration file %@", configFilePath);
    
    BOOL okNow = FALSE; // Assume failure
    int i;
    for (i=0; i<5; i++) {
        if (  i != 0  ) {
            usleep( i * 500000 );
            NSLog(@"Retrying execution of installer");
        }

        if (  [NSApplication waitForExecuteAuthorized: launchPath withArguments: arguments withAuthorizationRef: authRef] ) {
            // Try for up to 6.35 seconds to verify that installer succeeded -- sleeping .05 seconds first, then .1, .2, .4, .8, 1.6,
            // and 3.2 seconds (totals 6.35 seconds) between tries as a cheap and easy throttling mechanism for a heavily loaded computer
            useconds_t sleepTime;
            for (sleepTime=50000; sleepTime < 7000000; sleepTime=sleepTime*2) {
                usleep(sleepTime);
                
                if (  okNow = ( ! [self configNotProtected: configFilePath] ) ) {
                    break;
                }
            }
            
            if (  okNow  ) {
                break;
            } else {
                NSLog(@"Timed out waiting for installer execution to succeed");
            }
        } else {
            NSLog(@"Failed to execute %@: %@", launchPath, arguments);
        }
    }
        
    if (   ( ! okNow )
        && [self configNotProtected: configFilePath]  ) {
        NSLog(@"Could not change ownership and/or permissions of configuration file %@", configFilePath);
        TBRunAlertPanel([NSString stringWithFormat:@"%@: %@",
                         [self displayNameForPath: configFilePath],
                         NSLocalizedString(@"Not connecting", @"Window title")],
                        NSLocalizedString(@"Tunnelblick could not change ownership and permissions of the configuration file to secure it. See the Console Log for details.", @"Window text"),
                        nil,
                        nil,
                        nil);
        return FALSE;
    }
    
    NSLog(@"Secured configuration file %@", configFilePath);
    return TRUE;
}

// Copies or moves a config file or package and sets ownership and permissions on the target
// Returns TRUE if succeeded in the copy or move -- EVEN IF THE CONFIG WAS NOT SECURED (an error message was output to the console log).
// Returns FALSE if failed, having already output an error message to the console log
-(BOOL) copyConfigPath: (NSString *) sourcePath toPath: (NSString *) targetPath usingAuthRef: (AuthorizationRef) authRef warnDialog: (BOOL) warn moveNotCopy: (BOOL) moveInstead
{
    if (  [sourcePath isEqualToString: targetPath]  ) {
        NSLog(@"You cannot copy or move a configuration to itself. Trying to do that with %@", sourcePath);
        return FALSE;
    }
    
    NSString * arg1 = (moveInstead ? [NSString stringWithFormat: @"%u", INSTALLER_MOVE_NOT_COPY] : @"0");
    NSArray * arguments = [NSArray arrayWithObjects: arg1, targetPath, sourcePath, nil];
    NSString *launchPath = [[NSBundle mainBundle] pathForResource:@"installer" ofType:nil];
    
    BOOL okNow = FALSE; // Assume failure
    int i;
    for (i=0; i<5; i++) {
        if (  i != 0  ) {
            usleep( i * 500000 );
            NSLog(@"Retrying execution of installer");
        }
        
        if (  ! [NSApplication waitForExecuteAuthorized: launchPath withArguments: arguments withAuthorizationRef: authRef] ) {
            NSLog(@"Failed to execute %@: %@", launchPath, arguments);
        }
        
        if (  okNow = ( ! [self configNotProtected: targetPath] )  ) {
            break;
        }
    }
    
    if (   ( ! okNow )
        && [self configNotProtected: targetPath]  ) {
        NSString * name = [[sourcePath lastPathComponent] stringByDeletingPathExtension];
        if (  ! moveInstead  ) {
            if (  ! [gFileMgr contentsEqualAtPath: sourcePath andPath: targetPath]  ) {
                NSLog(@"Could not copy configuration file %@ to %@", sourcePath, targetPath);
                if (  warn  ) {
                    NSString * title = NSLocalizedString(@"Could Not Copy Configuration", @"Window title");
                    NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not copy the '%@' configuration. See the Console Log for details.", @"Window text"), name];
                    TBRunAlertPanel(title, msg, nil, nil, nil);
                }
                return FALSE;
            }
        } else {
            if (  ! [gFileMgr fileExistsAtPath: targetPath]  ) {
                NSLog(@"Could not move configuration file %@ to %@", sourcePath, targetPath);
                if (  warn  ) {
                    NSString * title = NSLocalizedString(@"Could Not Move Configuration", @"Window title");
                    NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not move the '%@' configuration. See the Console Log for details.", @"Window text"), name];
                    TBRunAlertPanel(title, msg, nil, nil, nil);
                }
                return FALSE;
            }
        }
        
        NSLog(@"Moved or copied, but could not secure configuration file at %@", targetPath);
        if (  warn  ) {
            NSString * title = NSLocalizedString(@"Could Not Secure Configuration", @"Window title");
            NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not secure the '%@' configuration. See the Console Log for details.", @"Window text"), name];
            TBRunAlertPanel(title, msg, nil, nil, nil);
        }
        return TRUE;    // Copied or moved OK, but not secured
    }
    
    if (  moveInstead  ) {
        NSLog(@"Moved configuration file %@ to %@ and secured the copy", sourcePath, targetPath);
    } else {
        NSLog(@"Copied configuration file %@ to %@ and secured the copy", sourcePath, targetPath);
    }
    
    return TRUE;
}

// Deletes a config file or package
// Returns TRUE if succeeded
// Returns FALSE if failed, having already output an error message to the console log
-(BOOL) deleteConfigPath: (NSString *) targetPath usingAuthRef: (AuthorizationRef) authRef warnDialog: (BOOL) warn
{
    NSString * arg1 = [NSString stringWithFormat: @"%u", INSTALLER_DELETE];
    NSArray * arguments = [NSArray arrayWithObjects: arg1, targetPath, nil];
    NSString *launchPath = [[NSBundle mainBundle] pathForResource:@"installer" ofType:nil];
    
    BOOL okNow = FALSE; // Assume failure
    int i;
    for (i=0; i<5; i++) {
        if (  i != 0  ) {
            usleep( i * 500000 );
            NSLog(@"Retrying execution of installer");
        }
        
        if (  ! [NSApplication waitForExecuteAuthorized: launchPath withArguments: arguments withAuthorizationRef: authRef] ) {
            NSLog(@"Failed to execute %@: %@", launchPath, arguments);
        }
        
        if (  okNow = ( ! [gFileMgr fileExistsAtPath: targetPath] )  ) {
            break;
        }
    }
    
    if (   ( ! okNow )
        && [gFileMgr fileExistsAtPath: targetPath]  ) {
        NSString * name = [[targetPath lastPathComponent] stringByDeletingPathExtension];
        NSLog(@"Could not uninstall configuration file %@", targetPath);
        if (  warn  ) {
            NSString * title = NSLocalizedString(@"Could Not Uninstall Configuration", @"Window title");
            NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"Tunnelblick could not uninstall the '%@' configuration. See the Console Log for details.", @"Window text"), name];
            TBRunAlertPanel(title, msg, nil, nil, nil);
        }
        return FALSE;
    }

    NSLog(@"Uninstalled configuration file %@", targetPath);
    return TRUE;
}

// If the specified folder doesn't exist, uses root to create it so it is owned by root:wheel and has permissions 0755.
// If the folder exists, ownership doesn't matter (as long as we can read/execute it).
// Returns TRUE if the folder already existed or was created successfully, returns FALSE otherwise, having already output an error message to the console log.
-(BOOL) makeSureFolderExistsAtPath:(NSString *)folderPath usingAuth: (AuthorizationRef) authRef
{
    BOOL isDir;
    
    if (   [gFileMgr fileExistsAtPath: folderPath isDirectory: &isDir]
        && isDir  ) {
        return TRUE;
    }
    
    NSString * parentFolderPath = [folderPath stringByDeletingLastPathComponent];
    if (  ! [self makeSureFolderExistsAtPath: parentFolderPath usingAuth: authRef]  ) {
        return FALSE;
    }
    
    NSString *launchPath = @"/bin/mkdir";
	NSArray *arguments = [NSArray arrayWithObject:folderPath];

    BOOL okNow = FALSE; // Assume failure
    int i;
    for (i=0; i<5; i++) {
        if (  i != 0  ) {
            usleep( i * 500000 );
            NSLog(@"Retrying execution of mkdir");
        }
        
        if (  EXIT_SUCCESS == [NSApplication executeAuthorized: launchPath withArguments: arguments withAuthorizationRef: authRef]  ) {
            // Try for up to 6.35 seconds to verify that installer succeeded -- sleeping .05 seconds first, then .1, .2, .4, .8, 1.6,
            // and 3.2 seconds (totals 6.35 seconds) between tries as a cheap and easy throttling mechanism for a heavily loaded computer
            useconds_t sleepTime;
            for (sleepTime=50000; sleepTime < 7000000; sleepTime=sleepTime*2) {
                usleep(sleepTime);
                
                if (  okNow =  (   [gFileMgr fileExistsAtPath:folderPath isDirectory:&isDir] 
                                && isDir )   ){
                    break;
                }
            }
            
            if (  okNow  ) {
                break;
            } else {
                NSLog(@"Timed out waiting for mkdir execution to succeed");
            }
        } else {
            NSLog(@"Failed to execute %@: %@", launchPath, arguments);
        }
    }
    
    if (   okNow
        || (   [gFileMgr fileExistsAtPath: folderPath isDirectory: &isDir]
            && isDir )  ) {
        return TRUE;
    }
    
    NSLog(@"Tunnelblick could not create folder %@ for the alternate configuration.", folderPath);
    TBRunAlertPanel(NSLocalizedString(@"Not connecting", @"Window title"),
                    NSLocalizedString(@"Tunnelblick could not create a folder for the alternate local configuration. See the Console Log for details.", @"Window text"),
                    nil,
                    nil,
                    nil);
    return FALSE;
}

// There are no configurations installed. Guide the user
-(void) haveNoConfigurationsGuide
{
    [self guideState: entryNoConfigurations];
}

// Guide the user through the process of adding a configuration (.tblk or .ovpn/.conf)
-(void) addConfigurationGuide
{
    [self guideState: entryAddConfiguration];
}

// guideState is sort of a state machine for displaying configuration dialog windows. It has a simple, LIFO history stored in an array to implement a "back" button
-(void) guideState: (enum state_t) state
{
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
                
                if (  button == NSAlertAlternateReturn  ) {
                    // User selected QUIT
                    [NSApp setAutoLaunchOnLogin: NO];
                    [NSApp terminate: nil];
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
                                                           "     • Create a sample configuration on the Desktop\n             and\n"
                                                           "     • Open its OpenVPN configuration file in TextEdit so you can modify "
                                                           "it to connect to your VPN?\n\n", @"Window text"),
                                         NSLocalizedString(@"Create sample configuration and edit it", @"Button"),    // Default button
                                         NSLocalizedString(@"Back", @"Button"),                         // Alternate button
                                         nil                                                            // Other button
                                         );
                
                if (  button == NSAlertAlternateReturn  ) {
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
                    
                    if (  button == NSAlertAlternateReturn  ) {
                        // User selected Back
                        nextState = stateGoBack;
                        break;
                    }
                    
                    [gFileMgr tbRemoveFileAtPath:targetPath handler: nil];
                }
                
                if (  createDir(targetPath, 0755) == -1  ) {
                    NSLog(@"Installation failed. Not able to create %@", targetPath);
                    TBRunAlertPanel(NSLocalizedString(@"Installation failed", @"Window title"),
                                    NSLocalizedString(@"Tunnelblick could not create the empty configuration folder", @"Window text"),
                                    nil, nil, nil);
                    return;
                }
                
                NSString * targetConfigPath = [targetPath stringByAppendingPathComponent: @"config.ovpn"];
                
                NSString * sourcePath = [[NSBundle mainBundle] pathForResource: @"openvpn" ofType: @"conf"];
                if (  ! [gFileMgr tbCopyPath: sourcePath toPath: targetConfigPath handler: nil]  ) {
                    NSLog(@"Installation failed. Not able to copy %@ to %@", sourcePath, targetConfigPath);
                    TBRunAlertPanel(NSLocalizedString(@"Installation failed", @"Window title"),
                                    NSLocalizedString(@"Tunnelblick could not create the sample configuration", @"Window text"),
                                    nil, nil, nil);
                    return;
                }
                
                [[NSWorkspace sharedWorkspace] openFile: targetPath];

                [[NSWorkspace sharedWorkspace] openFile: targetConfigPath withApplication: @"TextEdit"];
                
                // Display guidance about what to do after editing the sample configuration file
                TBRunAlertPanel(NSLocalizedString(@"Sample Configuration Created", @"Window title"),
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
                                                  
                                                  @"Window text"),
                                nil, nil, nil);
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
                
                if (  button == NSAlertAlternateReturn  ) {
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
                                                           "     • Tunnelblick VPN Configurations (.tblk extension)\n\n"
                                                           "     • OpenVPN Configurations (.ovpn or .conf extension)\n\n"
                                                           "Which type of configuration file do have?\n\n",
                                                           @"Window text"),
                                         NSLocalizedString(@"Tunnelblick VPN Configuration(s)", @"Button"),    // Default button
                                         NSLocalizedString(@"Back", @"Button"),                             // Alternate button
                                         NSLocalizedString(@"OpenVPN Configuration(s)", @"Button")             // Other button
                                         );
                
                if (  button == NSAlertAlternateReturn  ) {
                    // User selected Back
                    nextState = stateGoBack;
                    break;
                }
                
                if (  button == NSAlertOtherReturn) {
                    // User selected OPEPNVPN VPN CONFIGURATION
                    nextState = stateShowOpenVpnInstructions;
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
                
                return;
                
                
            case stateShowOpenVpnInstructions:
                
                // User selected OPEPNVPN VPN CONFIGURATION
                
                button = TBRunAlertPanel(NSLocalizedString(@"Which Type of Configuration Do You Wish to Create?", @"Window title"),
                                         NSLocalizedString(@"     • With one configuration file at a time, you can "
                                                           "create a Tunnelblick VPN Configuration.\n\n"
                                                           
                                                           "     • With multiple configuration files, you "
                                                           "can place the configuration files (and certificate "
                                                           "and key files if you have them) into Tunnelblick's private configurations folder.\n"
                                                           "This is the traditional way OpenVPN configurations have been used.\n\n"
                                                           
                                                           "Note: Tunnelblick VPN Configurations are preferred, because they may be shared, may be started "
                                                           "when the computer starts, and are secured automatically.", @"Window text"),
                                         NSLocalizedString(@"Create Tunnelblick VPN Configuration", @"Button"), // Default button
                                         NSLocalizedString(@"Back", @"Button"),                                 // Alternate button
                                         NSLocalizedString(@"Open Private Configurations Folder", @"Button")    // Other button
                                         );
                
                if (  button == NSAlertAlternateReturn  ) {
                    // User selected Back
                    nextState = stateGoBack;
                    break;
                }
                
                if (  button == NSAlertOtherReturn  ) {
                    // User wants to open the private configuration folder
                    nextState = stateOpenPrivateFolder;
                    break;
                }
                // User wants to create sample configuration on Desktop and edit the OpenVPN configuration file in TextEdit
                nextState = stateMakeEmptyConfiguration;
                break;
                
                
            case stateOpenPrivateFolder:
            
                // User wants to open the private configuration folder
                [[NSWorkspace sharedWorkspace] openFile: gPrivatePath];

                button = TBRunAlertPanel(NSLocalizedString(@"Private Configuration Folder is Open", @"Window title"),
                                         NSLocalizedString(@"The private configuration folder has been opened in a Finder window.\n\n"
                                                           "Move or copy OpenVPN configuration files and key and certificate files to the folder.\n\n"
                                                           "The new configuration(s) will be available in Tunnelblick immediately.", @"Window text"),
                                         NSLocalizedString(@"Done", @"Button"),    // Default button
                                         NSLocalizedString(@"Back", @"Button"),  // Alternate button
                                         nil
                                         );
                
                if (  button == NSAlertAlternateReturn  ) {
                    // User selected Back
                    nextState = stateGoBack;
                    break;
                }
                
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
                    
                    if (  button == NSAlertAlternateReturn  ) {
                        // User selected Back
                        nextState = stateGoBack;
                        break;
                    }
                    
                    [gFileMgr tbRemoveFileAtPath:targetPath handler: nil];
                }
                
                if (    createDir(targetPath, 0755) == -1    ) {
                    NSLog(@"Installation failed. Not able to create %@", targetPath);
                    TBRunAlertPanel(NSLocalizedString(@"Installation failed", @"Window title"),
                                    NSLocalizedString(@"Tunnelblick could not create the empty configuration folder", @"Window text"),
                                    nil, nil, nil);
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
            int backState = [[history lastObject] intValue];
            [history removeLastObject];
            state = backState;
        } else {
            [history addObject: [NSNumber numberWithInt: state]];
            state = nextState;
        }
    } 
}

-(NSString *) displayNameForPath: (NSString *) thePath
{
    return [lastPartOfPath(thePath) stringByDeletingPathExtension];
}

@end
