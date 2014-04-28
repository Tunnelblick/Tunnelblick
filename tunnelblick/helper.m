/*
 * Copyright 2005, 2006, 2007, 2008, 2009 Angelo Laub
 * Contributions by Jonathan K. Bullard Copyright 2010, 2011
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

#import <unistd.h>
#import <mach/mach_time.h>
#import "defines.h"
#import "helper.h"
#import "TBUserDefaults.h"
#import "NSApplication+SystemVersion.h"
#import "NSApplication+LoginItem.h"
#import "NSFileManager+TB.h"
#import "MenuController.h"
#import "AuthAgent.h"

// PRIVATE FUNCTIONS:
void           localizableStrings       (void);
BOOL           copyOrMoveCredentials    (NSString * fromDisplayName,
                                         NSString * toDisplayName,
                                         BOOL       moveNotCopy);

// The following external, global variables are used by functions in this file and must be declared and set elsewhere before the
// functions in this file are called:
extern NSMutableArray  * gConfigDirs;
extern NSString        * gPrivatePath;
extern NSString        * gDeployPath;
extern NSFileManager   * gFileMgr;
extern TBUserDefaults  * gTbDefaults;

void appendLog(NSString * msg)
{
	NSLog(@"%@", msg);
}

uint64_t nowAbsoluteNanoseconds (void)
{
    // The next three lines were adapted from http://shiftedbits.org/2008/10/01/mach_absolute_time-on-the-iphone/
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    uint64_t nowNs = mach_absolute_time() * info.numer / info.denom;
    return nowNs;
}

BOOL runningABetaVersion (void) {
    NSString * version = [[[NSBundle mainBundle] infoDictionary] objectForKey: @"CFBundleShortVersionString"];
    return ([version rangeOfString: @"beta"].length != 0);
}

BOOL runningOnNewerThan(unsigned majorVersion, unsigned minorVersion)
{
    unsigned major, minor, bugFix;
    [[NSApplication sharedApplication] getSystemVersionMajor:&major minor:&minor bugFix:&bugFix];
    return ( (major > majorVersion) || (minor > minorVersion) );
}

BOOL runningOnTigerOrNewer(void)
{
    return runningOnNewerThan(10, 3);
}

BOOL runningOnLeopardOrNewer(void)
{
    return runningOnNewerThan(10, 4);
}

BOOL runningOnSnowLeopardOrNewer(void)
{
    return runningOnNewerThan(10, 5);
}

BOOL runningOnSnowLeopardPointEightOrNewer(void) {
    
    unsigned major, minor, bugFix;
    [[NSApplication sharedApplication] getSystemVersionMajor:&major minor:&minor bugFix:&bugFix];
    
    if (  major < 10  ) {
        return FALSE;
    }
    
    if (  (major > 10) || (minor > 6)  ) {
        return TRUE;
    }
    
    return (  (minor == 6) && (bugFix > 7)  );
}

BOOL runningOnLionOrNewer(void)
{
    return runningOnNewerThan(10, 6);
}

BOOL runningOnMountainLionOrNewer(void)
{
    return runningOnNewerThan(10, 7);
}

BOOL runningOnMavericksOrNewer(void)
{
    return runningOnNewerThan(10, 8);
}

BOOL mustPlaceIconInStandardPositionInStatusBar(void) {
    
    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    if (  ! [bar respondsToSelector: @selector(_statusItemWithLength:withPriority:)]  ) {
        return YES;
    }
    if (  ! [bar respondsToSelector: @selector(_insertStatusItem:withPriority:)]  ) {
        return YES;
    }
    
    // ***** START OF TEMPORARY CODE UNTIL MAVERICKS BUG IS FIXED
    
    // Mavericks, even as of 10.9.2, doesn't seem to correctly implement _insertStatusItem:withPriority:, so we return "YES" when running on Mavericks
    // The problem is that the status item is inserted sometimes to the left and sometimes to the right of the Spotlight icon, and sometimes it is not inserted at all.
    
    if (  runningOnMavericksOrNewer()  ) {
        return YES;
    }
    
    // ***** END OF TEMPORARY CODE UNTIL MAVERICKS BUG IS FIXED
    
    if (   runningOnMavericksOrNewer()
        && ([[NSScreen screens] count] != 1)  ) {
        
        NSString * spacesPrefsPath = [NSHomeDirectory() stringByAppendingPathComponent: @"/Library/Preferences/com.apple.spaces.plist"];
        NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: spacesPrefsPath];
        if (  dict  ) {
            id obj = [dict objectForKey: @"spans-displays"];
            if (  obj  ) {
                if (  [obj respondsToSelector: @selector(boolValue)]  ) {
                    return ! [obj boolValue];
                } else {
                    NSLog(@"The 'spans-displays' preference from %@ does not respond to boolValue", spacesPrefsPath);
                }
            }
        } else {
            NSLog(@"Unable to load dictionary from %@", spacesPrefsPath);
        }
        
        return YES;
    }
    
    return NO;
}

// Returns an escaped version of a string so it can be sent over the management interface
NSString * escaped(NSString *string)
{
	NSMutableString * stringOut = [[string mutableCopy] autorelease];
	[stringOut replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:NSLiteralSearch range:NSMakeRange(0, [stringOut length])];
	[stringOut replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:NSLiteralSearch range:NSMakeRange(0, [stringOut length])];
	return stringOut;
}

// Returns the path of the configuration folder in which a specified configuration file is contained
// Returns nil if it is not in any configuration folder
NSString * firstPartOfPath(NSString * thePath)
{
    unsigned i;
    for (i=0; i < [gConfigDirs count]; i++) {
        if (  [thePath hasPrefix: [[gConfigDirs objectAtIndex: i] stringByAppendingString: @"/"]]  ) {
            return [[[gConfigDirs objectAtIndex: i] copy] autorelease];
        }
    }
    
    NSString *altPath = [L_AS_T_USERS stringByAppendingPathComponent: NSUserName()];
    if (  [thePath hasPrefix: [altPath stringByAppendingString:@ "/"]]  ) {
        return altPath;
    }
    
    NSLog(@"firstPartOfPath: Path %@ does not have a prefix that is in any gConfigDirs entry", thePath);
    return nil;
}

// The name of the configuration file, but prefixed by any folders it is contained in after /Deploy or /Configurations
//      = configPath less the Deploy or Configurations folder prefix (but including the extension)
// Used for constructing path to shadow copy of the configuration and as an argument to openvpnstart
NSString * lastPartOfPath(NSString * thePath)
{
    return [thePath substringFromIndex: [firstPartOfPath(thePath) length]+1];
}

// Returns the first component of a path
NSString * firstPathComponent(NSString * path)
{
    NSRange slash = [path rangeOfString: @"/"];
    if ( slash.location == 0 ) {
        slash = [[path substringFromIndex: 1] rangeOfString: @"/"];
    }
    if ( slash.location == NSNotFound) {
        slash.location = [path length];
    }
    return [path substringToIndex: slash.location];
}


NSString * displayNameFromPath (NSString * thePath) {
	
	// Returns the display name for a configuration, given a configuration file's path (either a .tblk or a .ovpn)
	
	NSString * last = lastPartOfPath(thePath);
	
	if (  [last hasSuffix: @".tblk"]  ) {							// IS a .tblk
		return [last substringToIndex: [last length] - 5];
	}
	
	if (  [last hasSuffix: @"/Contents/Resources/config.ovpn"]  ) {	// Is IN a .tblk
		return [[[[last stringByDeletingLastPathComponent]	// Remove config.ovpn
				  stringByDeletingLastPathComponent]		// Remove Resources
				 stringByDeletingLastPathComponent]			// Remove Contents
				stringByDeletingPathExtension];				// Remove .tblk
	}
	
	if (   [last hasSuffix: @".ovpn"]								// Is a non-tblk configuration file
		|| [last hasSuffix: @".conf"]  ) {
		return [last substringToIndex: [last length] - 5];
	}
	
	NSLog(@"displayNameFromPath: invalid path '%@'", thePath);
	return nil;
}

// Returns the path of the configuration file within a .tblk, or nil if there is no such configuration file
NSString * configPathFromTblkPath(NSString * path)
{
    NSString * cfgPath = [path stringByAppendingPathComponent:@"Contents/Resources/config.ovpn"];
    BOOL isDir;
    
    if (   [gFileMgr fileExistsAtPath: cfgPath isDirectory: &isDir]
        && (! isDir)  ) {
        return cfgPath;
    }
    
    return nil;
}

//**************************************************************************************************************************
// Function to create a directory with specified permissions
// Recursively creates all intermediate directories (with the same permissions) as needed
// Returns 1 if the directory was created or permissions modified
//         0 if the directory already exists (whether or not permissions could be changed)
//        -1 if an error occurred. A directory was not created, and an error message was put in the log.
int createDir(NSString * dirPath, unsigned long permissions)
{
    NSNumber     * permissionsAsNumber    = [NSNumber numberWithUnsignedLong: permissions];
    NSDictionary * permissionsAsAttribute = [NSDictionary dictionaryWithObject: permissionsAsNumber forKey: NSFilePosixPermissions];
    BOOL isDir;
    
    if (   [gFileMgr fileExistsAtPath: dirPath isDirectory: &isDir]  ) {
        if (  isDir  ) {
            // Don't try to change permissions of /Library/Application Support or ~/Library/Application Support
            if (  [dirPath hasSuffix: @"/Library/Application Support"]  ) {
                return 0;
            }
            NSDictionary * attributes = [gFileMgr tbFileAttributesAtPath: dirPath traverseLink: YES];
            NSNumber * oldPermissionsAsNumber = [attributes objectForKey: NSFilePosixPermissions];
            if (  [oldPermissionsAsNumber isEqualToNumber: permissionsAsNumber] ) {
                return 0;
            }
            if (  [gFileMgr tbChangeFileAttributes: permissionsAsAttribute atPath: dirPath] ) {
                return 1;
            }
            NSLog(@"Warning: Unable to change permissions on %@ from %lo to %lo", dirPath, [oldPermissionsAsNumber longValue], permissions);
            return 0;
        } else {
            NSLog(@"Error: %@ exists but is not a directory", dirPath);
            return -1;
        }
    }
    
    // No such directory. Create its parent directory (recurse) if necessary
    int result = createDir([dirPath stringByDeletingLastPathComponent], permissions);
    if (  result == -1  ) {
        return -1;
    }
    
    // Parent directory exists. Create the directory we want
    if (  ! [gFileMgr tbCreateDirectoryAtPath: dirPath attributes: permissionsAsAttribute] ) {
        if (   [gFileMgr fileExistsAtPath: dirPath isDirectory: &isDir]
            && isDir  ) {
            NSLog(@"Warning: Created directory %@ but unable to set permissions to %lo", dirPath, permissions);
            return 1;
        } else {
            NSLog(@"Error: Unable to create directory %@ with permissions %lo", dirPath, permissions);
            return -1;
        }
    }
    
    return 1;
}

// Returns the path of the .tblk that a configuration file is enclosed within, or nil if the configuration file is not enclosed in a .tblk
NSString * tblkPathFromConfigPath(NSString * path)
{
    NSString * answer = path;
    while (   ! [[answer pathExtension] isEqualToString: @"tblk"]
           && [answer length] != 0
           && ! [answer isEqualToString: @"/"]  ) {
        answer = [answer stringByDeletingLastPathComponent];
    }
    
    if (  [[answer pathExtension] isEqualToString: @"tblk"]  ) {
        return answer;
    }
    
    return nil;
}

// Returns YES if file doesn't exist, or has the specified ownership and permissions
BOOL checkOwnerAndPermissions(NSString * fPath, uid_t uid, gid_t gid, mode_t permsShouldHave)
{
    if (  ! [gFileMgr fileExistsAtPath: fPath]  ) {
        return YES;
    }
    
    NSDictionary *fileAttributes = [gFileMgr tbFileAttributesAtPath:fPath traverseLink:YES];
    unsigned long perms = [fileAttributes filePosixPermissions];
    NSNumber *fileOwner = [fileAttributes fileOwnerAccountID];
    NSNumber *fileGroup = [fileAttributes fileGroupOwnerAccountID];
    
    if (   (perms == permsShouldHave)
        && [fileOwner isEqualToNumber:[NSNumber numberWithInt:(int) uid]]
        && [fileGroup isEqualToNumber:[NSNumber numberWithInt:(int) gid]]) {
        return YES;
    }
    
    NSLog(@"File %@ has permissions: %lo, is owned by %@:%@ and needs repair", fPath, perms, fileOwner, fileGroup);
    return NO;
}

// Returns a string with the version # for Tunnelblick, e.g., "Tunnelbick 3.0b12 (build 157)"
NSString * tunnelblickVersion(NSBundle * bundle)
{
    NSString * infoVersion = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    NSString * infoShort   = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString * infoBuild   = [bundle objectForInfoDictionaryKey:@"Build"];
    
    if (  [[infoVersion class] isSubclassOfClass: [NSString class]] && [infoVersion rangeOfString: @"3.0b"].location == NSNotFound  ) {
        // No "3.0b" in CFBundleVersion, so it is a build number, which means that the CFBundleShortVersionString has what we want
        return [NSString stringWithFormat: @"Tunnelblick %@", infoShort];
    }
    
    // We must construct the string from what we have in infoShort and infoBuild.
    //Strip "Tunnelblick " from the front of the string if it exists (it may not)
    NSString * appVersion = (  [infoShort hasPrefix: @"Tunnelblick "]
                             ? [infoShort substringFromIndex: [@"Tunnelblick " length]]
                             : infoShort);
    
    NSString * appVersionWithoutBuild;
    unsigned parenStart;
    if (  ( parenStart = ([appVersion rangeOfString: @" ("].location) ) == NSNotFound  ) {
        // No " (" in version, so it doesn't have a build # in it
        appVersionWithoutBuild   = appVersion;
    } else {
        // Remove the parenthesized build
        appVersionWithoutBuild   = [appVersion substringToIndex: parenStart];
    }
    
    NSMutableString * version = [NSMutableString stringWithCapacity: 30];
    [version appendString: NSLocalizedString(@"Tunnelblick", @"Window title")];
    if (  appVersionWithoutBuild  ) {
        [version appendFormat: @" %@", appVersionWithoutBuild];
    }
    if (  infoBuild  ) {
        [version appendFormat: @" (build %@)", infoBuild];
    }
    if (  ( ! appVersionWithoutBuild ) &&  ( ! infoBuild) ) {
        [version appendFormat: @" (no version information available)"];
    }
    return (version);
}

// Takes the same arguments as, and is similar to, NSRunAlertPanel
// DOES NOT BEHAVE IDENTICALLY to NSRunAlertPanel:
//   * Stays on top of other windows
//   * Blocks the runloop
//   * Displays the Tunnelblick icon
//   * If title is nil, "Alert" will be used.
//   * If defaultButtonLabel is nil, "OK" will be used.

int TBRunAlertPanel(NSString * title, NSString * msg, NSString * defaultButtonLabel, NSString * alternateButtonLabel, NSString * otherButtonLabel)
{
    return TBRunAlertPanelExtended(title, msg, defaultButtonLabel, alternateButtonLabel, otherButtonLabel, nil, nil, nil, NSAlertDefaultReturn);
}

// Like TBRunAlertPanel but allows a "do not show again" preference key and checkbox, or a checkbox for some other function.
// If the preference is set, the panel is not shown and "notShownReturnValue" is returned.
// If the preference can be changed by the user, and the checkboxResult pointer is not nil, the panel will include a checkbox with the specified label.
// If the preference can be changed by the user, the preference is set if the user checks the box and the button that is clicked corresponds to the notShownReturnValue.
// If the checkboxResult pointer is not nil, the initial value of the checkbox will be set from it, and the value of the checkbox is returned to it.
int TBRunAlertPanelExtended(NSString * title,
                            NSString * msg,
                            NSString * defaultButtonLabel,
                            NSString * alternateButtonLabel,
                            NSString * otherButtonLabel,
                            NSString * doNotShowAgainPreferenceKey,
                            NSString * checkboxLabel,
                            BOOL     * checkboxResult,
							int		   notShownReturnValue)
{
    if (  doNotShowAgainPreferenceKey && [gTbDefaults boolForKey: doNotShowAgainPreferenceKey]  ) {
        return notShownReturnValue;
    }
    
    NSMutableDictionary * dict = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                  msg,  kCFUserNotificationAlertMessageKey,
                                  [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"tunnelblick" ofType: @"icns"]],
                                        kCFUserNotificationIconURLKey,
                                  nil];
    if ( title ) {
        [dict setObject: title
                 forKey: (NSString *)kCFUserNotificationAlertHeaderKey];
    } else {
        [dict setObject: NSLocalizedString(@"Alert", @"Window title")
                 forKey: (NSString *)kCFUserNotificationAlertHeaderKey];
    }
    
    if ( defaultButtonLabel ) {
        [dict setObject: defaultButtonLabel
                 forKey: (NSString *)kCFUserNotificationDefaultButtonTitleKey];
    } else {
        [dict setObject: NSLocalizedString(@"OK", @"Button")
                 forKey: (NSString *)kCFUserNotificationDefaultButtonTitleKey];
    }
    
    if ( alternateButtonLabel ) {
        [dict setObject: alternateButtonLabel
                 forKey: (NSString *)kCFUserNotificationAlternateButtonTitleKey];
    }
    
    if ( otherButtonLabel ) {
        [dict setObject: otherButtonLabel
                 forKey: (NSString *)kCFUserNotificationOtherButtonTitleKey];
    }
    
    if (  checkboxLabel  ) {
        if (   checkboxResult
            || ( doNotShowAgainPreferenceKey && [gTbDefaults canChangeValueForKey: doNotShowAgainPreferenceKey] )
            ) {
            [dict setObject: checkboxLabel forKey:(NSString *)kCFUserNotificationCheckBoxTitlesKey];
        }
    }
    
    SInt32 error = 0;
    CFUserNotificationRef notification = NULL;
    CFOptionFlags response = 0;

    CFOptionFlags checkboxChecked = 0;
    if (  checkboxResult  ) {
        if (  * checkboxResult  ) {
            checkboxChecked = CFUserNotificationCheckBoxChecked(0);
        }
    }
    
    [NSApp activateIgnoringOtherApps:YES];
	
    notification = CFUserNotificationCreate(NULL, 0.0, checkboxChecked, &error, (CFDictionaryRef) dict);
    if (  error  ) {
		NSLog(@"CFUserNotificationCreate() returned with error = %ld; notification = 0x%lX, so TBRunAlertExtended is returning NSAlertErrorReturn",
              (long) error, (long) notification);
        SInt32 status = CFUserNotificationDisplayNotice(60.0,
                                                        kCFUserNotificationStopAlertLevel,
                                                        NULL,
                                                        NULL,
                                                        NULL,
                                                        (CFStringRef) NSLocalizedString(@"Alert", @"Window title"),
                                                        (CFStringRef) [NSString stringWithFormat:
                                                                       NSLocalizedString(@"Tunnelblick could not display a window.\n\n"
                                                                                         @"CFUserNotificationCreate() returned with error = %ld; notification = 0x%lX", @"Window text"),
                                                                       (long) error, (long) notification],
                                                        NULL);
        NSLog(@"CFUserNotificationDisplayNotice() returned %ld", (long) status);
		if (  notification  ) {
			CFRelease(notification);
		}
        [dict release];
        return NSAlertErrorReturn;
    }
    
	SInt32 responseReturnCode = CFUserNotificationReceiveResponse(notification, 0.0, &response);
    
    CFRelease(notification);
    [dict release];
    
    if (  responseReturnCode  ) {
        NSLog(@"CFUserNotificationReceiveResponse() returned %ld with response = %ld, so TBRunAlertExtended is returning NSAlertErrorReturn",
              (long) responseReturnCode, (long) response);
        return NSAlertErrorReturn;
    }
    
    if (  checkboxResult  ) {
        if (  response & CFUserNotificationCheckBoxChecked(0)  ) {
            * checkboxResult = TRUE;
        } else {
            * checkboxResult = FALSE;
        }
    } 

    switch (response & 0x3) {
        case kCFUserNotificationDefaultResponse:
			if (  notShownReturnValue == NSAlertDefaultReturn  ) {
				if (  checkboxLabel  ) {
					if (   doNotShowAgainPreferenceKey
						&& [gTbDefaults canChangeValueForKey: doNotShowAgainPreferenceKey]
						&& ( response & CFUserNotificationCheckBoxChecked(0) )  ) {
						[gTbDefaults setBool: TRUE forKey: doNotShowAgainPreferenceKey];
					}
				}
			}
				
            return NSAlertDefaultReturn;
            
        case kCFUserNotificationAlternateResponse:
			if (  notShownReturnValue == NSAlertAlternateReturn  ) {
				if (  checkboxLabel  ) {
					if (   doNotShowAgainPreferenceKey
						&& [gTbDefaults canChangeValueForKey: doNotShowAgainPreferenceKey]
						&& ( response & CFUserNotificationCheckBoxChecked(0) )  ) {
						[gTbDefaults setBool: TRUE forKey: doNotShowAgainPreferenceKey];
					}
				}
			}
			
            return NSAlertAlternateReturn;
            
        case kCFUserNotificationOtherResponse:
			if (  notShownReturnValue == NSAlertOtherReturn  ) {
				if (  checkboxLabel  ) {
					if (   doNotShowAgainPreferenceKey
						&& [gTbDefaults canChangeValueForKey: doNotShowAgainPreferenceKey]
						&& ( response & CFUserNotificationCheckBoxChecked(0) )  ) {
						[gTbDefaults setBool: TRUE forKey: doNotShowAgainPreferenceKey];
					}
				}
			}
			
            return NSAlertOtherReturn;
            
        default:
            NSLog(@"CFUserNotificationReceiveResponse() returned a response but it wasn't the default, alternate, or other response, so TBRunAlertExtended() is returning NSAlertErrorReturn");
            return NSAlertErrorReturn;
    }
}

BOOL isUserAnAdmin(void)
{
    //Launch "id -Gn" to get a list of names of the groups the user is a member of, and put the result into an NSString:
    
    NSTask * task = [[NSTask alloc] init];
    
    NSString * exePath = @"/usr/bin/id";
    [task setLaunchPath: exePath];
    
    NSArray  *arguments = [NSArray arrayWithObjects: @"-Gn", nil];
    [task setArguments: arguments];
    
    NSPipe * pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    
    NSFileHandle * file = [pipe fileHandleForReading];
    
    [task launch];
    
    NSData * data = [file readDataToEndOfFile];
    
    [task release];
    
    NSString * string1 = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    
    // If the "admin" group appears, the user is a member of the "admin" group, so they are an admin.
    // Group names don't include spaces and are separated by spaces, so this is easy. We just have to
    // handle admin being at the start or end of the output by pre- and post-fixing a space.
    
    NSString * string2 = [NSString stringWithFormat:@" %@ ", [string1 stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    NSRange rng = [string2 rangeOfString:@" admin "];
    [string1 release];
    
    return (rng.location != NSNotFound);
}

NSString * newTemporaryDirectoryPath(void)
{
    //**********************************************************************************************
    // Start of code for creating a temporary directory from http://cocoawithlove.com/2009/07/temporary-files-and-folders-in-cocoa.html
    // Modified to check for malloc returning NULL, use strlcpy, use gFileMgr, and use more readable length for stringWithFileSystemRepresentation
    
    NSString   * tempDirectoryTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent: @"TunnelblickTemporaryDotTblk-XXXXXX"];
    const char * tempDirectoryTemplateCString = [tempDirectoryTemplate fileSystemRepresentation];
    
    size_t bufferLength = strlen(tempDirectoryTemplateCString) + 1;
    char * tempDirectoryNameCString = (char *) malloc( bufferLength );
    if (  ! tempDirectoryNameCString  ) {
        NSLog(@"Unable to allocate memory for a temporary directory name");
        [[NSApp delegate] terminateBecause: terminatingBecauseOfError];
        return nil;
    }
    
    strlcpy(tempDirectoryNameCString, tempDirectoryTemplateCString, bufferLength);
    
    char * dirPath = mkdtemp(tempDirectoryNameCString);
    if (  ! dirPath  ) {
        NSLog(@"Unable to create a temporary directory");
        [[NSApp delegate] terminateBecause: terminatingBecauseOfError];
    }
    
    NSString *tempFolder = [gFileMgr stringWithFileSystemRepresentation: tempDirectoryNameCString
                                                                 length: strlen(tempDirectoryNameCString)];
	// Change from /var to /private/var to avoid using a symlink
	if (  [tempFolder hasPrefix: @"/var/"]  ) {
		NSDictionary * fileAttributes = [gFileMgr tbFileAttributesAtPath: @"/var" traverseLink: NO];
		if (  [[fileAttributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink]  ) {
			if (   ( ! [gFileMgr respondsToSelector: @selector(destinationOfSymbolicLinkAtPath:error:)] )
				|| [[gFileMgr destinationOfSymbolicLinkAtPath: @"/var" error: NULL]
					isEqualToString: @"private/var"]  ) {
					NSString * afterVar = [tempFolder substringFromIndex: 5];
					tempFolder = [@"/private/var" stringByAppendingPathComponent:afterVar];
			} else {
				NSLog(@"Warning: /var is not a symlink to /private/var so it is being left intact");
			}
		}
	}
    
	free(tempDirectoryNameCString);
    
    // End of code from http://cocoawithlove.com/2009/07/temporary-files-and-folders-in-cocoa.html
    //**********************************************************************************************
    
    return [tempFolder retain];
}


// Modified from http://developer.apple.com/library/mac/#documentation/Carbon/Conceptual/ProvidingUserAssitAppleHelp/using_ah_functions/using_ah_functions.html#//apple_ref/doc/uid/TP30000903-CH208-CIHFABIE
OSStatus MyGotoHelpPage (NSString * pagePath, NSString * anchorName)
{
    OSStatus err = noErr;
    
    if (  runningOnSnowLeopardOrNewer()  ) {
        
        CFBundleRef myApplicationBundle = NULL;
        CFStringRef myBookName = NULL;
        
        myApplicationBundle = CFBundleGetMainBundle();
        if (myApplicationBundle == NULL) {
            err = fnfErr;
            goto bail;
        }
        
        myBookName = CFBundleGetValueForInfoDictionaryKey(
                                                          myApplicationBundle,
                                                          CFSTR("CFBundleHelpBookName"));
        if (myBookName == NULL) {
            err = fnfErr;
            goto bail;
        }
        
        if (CFGetTypeID(myBookName) != CFStringGetTypeID()) {
            err = paramErr;
            goto bail;
        }
        
        err = AHGotoPage (myBookName, (CFStringRef) pagePath, (CFStringRef) anchorName);// 5
    } else {
        NSString * fullPath = [[NSBundle mainBundle] pathForResource: pagePath ofType: nil inDirectory: @"help"];
        if (  fullPath  ) {
            err = (  [[NSWorkspace sharedWorkspace] openFile: fullPath]
                   ? 0
                   : fnfErr);
        } else {
            NSLog(@"Unable to locate %@ in 'help' resource folder", pagePath);
            err = fnfErr;
        }
    }
    
bail:
	if ( err != noErr  ) { 
		NSLog(@"Error %ld in MyGotoHelpPage()", (long) err);
	}
	
    return err;
}

NSString * TBGetString(NSString * msg, NSString * nameToPrefill)
{
    NSMutableDictionary* panelDict = [[NSMutableDictionary alloc] initWithCapacity:6];
    [panelDict setObject:NSLocalizedString(@"Name Required", @"Window title") forKey:(NSString *)kCFUserNotificationAlertHeaderKey];
    [panelDict setObject:msg                                                  forKey:(NSString *)kCFUserNotificationAlertMessageKey];
    [panelDict setObject:@""                                                  forKey:(NSString *)kCFUserNotificationTextFieldTitlesKey];
    [panelDict setObject:nameToPrefill                                        forKey:(NSString *)kCFUserNotificationTextFieldValuesKey];
    [panelDict setObject:NSLocalizedString(@"OK", @"Button")                  forKey:(NSString *)kCFUserNotificationDefaultButtonTitleKey];
    [panelDict setObject:NSLocalizedString(@"Cancel", @"Button")              forKey:(NSString *)kCFUserNotificationAlternateButtonTitleKey];
    [panelDict setObject:[NSURL fileURLWithPath:[[NSBundle mainBundle]
                                                 pathForResource:@"tunnelblick"
                                                 ofType: @"icns"]]            forKey:(NSString *)kCFUserNotificationIconURLKey];
    SInt32 error;
    CFUserNotificationRef notification;
    CFOptionFlags response;
    
    // Get a name from the user
    notification = CFUserNotificationCreate(NULL, 30.0, 0, &error, (CFDictionaryRef)panelDict);
    [panelDict release];
    
    if((error) || (CFUserNotificationReceiveResponse(notification, 0.0, &response))) {
        CFRelease(notification);    // Couldn't receive a response
        NSLog(@"Could not get a string from the user.\n\nAn unknown error occured.");
        return nil;
    }
    
    if((response & 0x3) != kCFUserNotificationDefaultResponse) {
        CFRelease(notification);    // User clicked "Cancel"
        return nil;
    }
    
    // Get the new name from the textfield
    NSString * returnString = [(NSString*)CFUserNotificationGetResponseValue(notification, kCFUserNotificationTextFieldValuesKey, 0)
                               stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    CFRelease(notification);
    return returnString;
}


// Call with a message to display and the path of a configuration that will be renamed or installed.
// Returns with nil if cancelled, otherwise the display name of a configuration that sourcePath can be renamed to or installed to
NSString * TBGetDisplayName(NSString * msg,
                            NSString * sourcePath)
{
    NSString * nameToPrefill = [[sourcePath lastPathComponent] stringByDeletingPathExtension];
    NSString * newName = TBGetString(msg, nameToPrefill);
    while (  newName  ) {
        if (  invalidConfigurationName(newName, PROHIBITED_DISPLAY_NAME_CHARACTERS_INCLUDING_SLASH_CSTRING)  ) {
            newName = TBGetString([NSString stringWithFormat:
								   NSLocalizedString(@"Names may not include any of the following characters: %s\n\n%@", @"Window text"),
								   PROHIBITED_DISPLAY_NAME_CHARACTERS_INCLUDING_SLASH_CSTRING,
								   msg],
								  nameToPrefill);
        } else if (  [newName length] == 0  ) {
            newName = TBGetString([NSLocalizedString(@"Please enter a name and click \"OK\" or click \"Cancel\".\n\n", @"Window text") stringByAppendingString: msg], nameToPrefill);
        } else {
            NSString * targetPath = [[[sourcePath stringByDeletingLastPathComponent] stringByAppendingPathComponent: newName] stringByAppendingPathExtension: @"conf"]; // (Don't use the .conf, but may need it for lastPartOfPath)
            NSString * dispNm = [lastPartOfPath(targetPath) stringByDeletingPathExtension];
            if (  nil == [[[NSApp delegate] myConfigDictionary] objectForKey: dispNm]  ) {
                break;
            }
            newName = TBGetString([NSLocalizedString(@"That name is being used.\n\n", @"Window text") stringByAppendingString: msg], nameToPrefill);
        }
    }
    
    return newName;
}

NSString * credentialsGroupFromDisplayName (NSString * displayName)
{
	NSString * allGroup = [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"];
	if (  [allGroup length] != 0  ) {
		return allGroup;
	}
	
	NSString * prefKey = [displayName stringByAppendingString: @"-credentialsGroup"];
	NSString * group = [gTbDefaults stringForKey: prefKey];
	if (  [group length] == 0  ) {
		return nil;
	}
	
	return group;
}	

BOOL copyCredentials(NSString * fromDisplayName, NSString * toDisplayName)
{
    return copyOrMoveCredentials(fromDisplayName, toDisplayName, FALSE);
}

BOOL moveCredentials(NSString * fromDisplayName, NSString * toDisplayName)
{
    return copyOrMoveCredentials(fromDisplayName, toDisplayName, TRUE);
}

BOOL copyOrMoveCredentials(NSString * fromDisplayName, NSString * toDisplayName, BOOL moveNotCopy)
{
	NSString * group = credentialsGroupFromDisplayName(fromDisplayName);
	if (  group  ) {
		return YES;
	}		
		
    NSString * myPassphrase = nil;
    NSString * myUsername = nil;
    NSString * myPassword = nil;
    
    AuthAgent * myAuthAgent = [[[AuthAgent alloc] initWithConfigName: fromDisplayName credentialsGroup: nil] autorelease];
    [myAuthAgent setAuthMode: @"privateKey"];
    if (  [myAuthAgent keychainHasCredentials]  ) {
        [myAuthAgent performAuthentication];
        myPassphrase = [myAuthAgent passphrase];
        if (  moveNotCopy) {
            [myAuthAgent deleteCredentialsFromKeychain];
        }
    }
    [myAuthAgent setAuthMode: @"password"];
    if (  [myAuthAgent keychainHasCredentials]  ) {
        [myAuthAgent performAuthentication];
        myUsername = [myAuthAgent username];
        myPassword   = [myAuthAgent password];
        if (  moveNotCopy) {
            [myAuthAgent deleteCredentialsFromKeychain];
        }
    }
    
    KeyChain * passphraseKeychain = [[KeyChain alloc] initWithService:[@"Tunnelblick-Auth-" stringByAppendingString: toDisplayName] withAccountName: @"privateKey" ];
    KeyChain * usernameKeychain   = [[KeyChain alloc] initWithService:[@"Tunnelblick-Auth-" stringByAppendingString: toDisplayName] withAccountName: @"username"   ];
    KeyChain * passwordKeychain   = [[KeyChain alloc] initWithService:[@"Tunnelblick-Auth-" stringByAppendingString: toDisplayName] withAccountName: @"password"   ];
    
    if (  myPassphrase  ) {
        [passphraseKeychain deletePassword];
        if (  [passphraseKeychain setPassword: myPassphrase] != 0  ) {
            NSLog(@"Could not store passphrase in Keychain");
        }
    }
    if (  myUsername  ) {
        [usernameKeychain deletePassword];
        if (  [usernameKeychain setPassword: myUsername] != 0  ) {
            NSLog(@"Could not store username in Keychain");
        }
    }
    if (  myPassword  ) {
        [passwordKeychain deletePassword];
        if (  [passwordKeychain setPassword: myPassword] != 0  ) {
            NSLog(@"Could not store password in Keychain");
        }
    }
    
    [passphraseKeychain release];
    [usernameKeychain   release];
    [passwordKeychain   release];
     
    return TRUE;
}

NSMutableString * encodeSlashesAndPeriods(NSString * s)
{
    // Encode slashes and periods in the displayName so the result can act as a single component in a file name
    NSMutableString * result = [[s mutableCopy] autorelease];
    [result replaceOccurrencesOfString: @"-" withString: @"--" options: 0 range: NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString: @"." withString: @"-D" options: 0 range: NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString: @"/" withString: @"-S" options: 0 range: NSMakeRange(0, [result length])];
    return result;
}

NSString * copyrightNotice()
{
	[NSDateFormatter setDefaultFormatterBehavior: NSDateFormatterBehavior10_4];
    NSDateFormatter * dateFormat = [[[NSDateFormatter alloc] init] autorelease];
    [dateFormat setDateFormat:@"YYYY"];
    NSString * year = [dateFormat stringFromDate: [NSDate date]];
    return [NSString stringWithFormat:
            NSLocalizedString(@"Copyright © 2004-%@ Angelo Laub and others.", @"Window text"),
            year];
}

BOOL isSanitizedOpenvpnVersion(NSString * s)
{
    unsigned i;
    for (i=0; i<[s length]; i++) {
        unichar ch = [s characterAtIndex: i];
        if ( strchr("01234567890._-abcdefghijklmnopqrstuvwxyz", ch) == NULL  ) {
            NSLog(@"An OpenVPN version string may only contain a-z, 0-9, periods, underscores, and hyphens");
            return NO;
        }
    }
    
    return YES;
}

NSArray * availableOpenvpnVersions (void)
{
    static BOOL haveNotWarned = TRUE;       // Have we warned about ALL the bad folder names already
    BOOL haveWarnedThisTimeThrough = FALSE; // Have we warned about any folder names this time through
    
    // Get a sorted list of the versions
    NSMutableArray * list = [[[NSMutableArray alloc] initWithCapacity: 12] autorelease];
    NSString * dir;
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: [[NSBundle mainBundle] pathForResource: @"openvpn" ofType: nil]];
    while (  (dir = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        if (  [dir hasPrefix: @"openvpn-"]  ) {
            NSString * version = [dir substringFromIndex: [@"openvpn-" length]];
            if (  isSanitizedOpenvpnVersion(version)  ) {
                unsigned i;
                for (  i=0; i<[list count]; i++  ) {
                    if (  [version compare: [list objectAtIndex: i] options: NSNumericSearch] == NSOrderedAscending  ) {
                        [list insertObject: version atIndex: i];
                        break;
                    }
                }
                if (  i == [list count]  ) {
                    [list addObject: version];
                }
            } else {
                if (  haveNotWarned  ) {
                    NSLog(@"OpenVPN version folder names may only contain a-z, 0-9, periods, and hyphens. %@ has been ignored.", dir);
                    haveWarnedThisTimeThrough = TRUE;
                }
            }
        }
    }
    
    if (  haveWarnedThisTimeThrough  ) {
        haveNotWarned = FALSE;
    }
    
    if (  [list count] == 0  ) {
        return nil;
    }
    
    return list;
}

NSString * stringForLog(NSString * outputString, NSString * header)
{
    outputString = [outputString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (  [outputString length] == 0  ) {
		return @"";
	}
	outputString = [header stringByAppendingString: outputString];
    NSMutableString * tempMutableString = [[outputString mutableCopy] autorelease];
    [tempMutableString replaceOccurrencesOfString: @"\n" withString: @"\n     " options: 0 range: NSMakeRange(0, [tempMutableString length])];
	return [NSString stringWithFormat: @"%@\n", tempMutableString];
}

NSString * configLocCodeStringForPath(NSString * configPath) {
    
    unsigned code;
    
    if (  [configPath hasPrefix: [gPrivatePath  stringByAppendingString: @"/"]]  ) {
        code = CFG_LOC_PRIVATE;
        
    } else if (  [configPath hasPrefix: [gDeployPath   stringByAppendingString: @"/"]]  ) {
        code = CFG_LOC_DEPLOY;
    
    } else if (  [configPath hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]  ) {
        code = CFG_LOC_SHARED;
    
    } else if (  [configPath hasPrefix: [[L_AS_T_USERS stringByAppendingPathComponent: NSUserName()] stringByAppendingString: @"/"]]  ) {
        code = CFG_LOC_ALTERNATE;
    
    } else {
        NSLog(@"configLocCodeStringForPath: unknown path %@", configPath);
        [[NSApp delegate] terminateBecause: terminatingBecauseOfError];
        return [NSString stringWithFormat: @"%u", CFG_LOC_MAX + 1];
    }
    
    return [NSString stringWithFormat: @"%u", code];
}

OSStatus runOpenvpnstart(NSArray * arguments, NSString ** stdoutString, NSString ** stderrString)
{
    NSString * path = [[NSBundle mainBundle] pathForResource: @"openvpnstart" ofType: nil];
    if (  ! path  ) {
        NSLog(@"Unable to find openvpnstart");
        return -1;
    }
    
    // Send stdout and stderr to temporary files, and read the files after the task completes
    NSString * dirPath = newTemporaryDirectoryPath();
	
    NSString * stdPath = [dirPath stringByAppendingPathComponent: @"runOpenvpnstartStdOut"];
    if (  [gFileMgr fileExistsAtPath: stdPath]  ) {
        NSLog(@"runOpenvpnstart: File exists at %@", stdPath);
        [dirPath release];
        return -1;
    }
    if (  ! [gFileMgr createFileAtPath: stdPath contents: nil attributes: nil]  ) {
        NSLog(@"runOpenvpnstart: Unable to create %@", stdPath);
        [dirPath release];
        return -1;
    }
    NSFileHandle * stdFileHandle = [[NSFileHandle fileHandleForWritingAtPath: stdPath] retain];
    if (  ! stdFileHandle  ) {
        NSLog(@"runOpenvpnstart: Unable to get NSFileHandle for %@", stdPath);
        [dirPath release];
        return -1;
    }
    
    NSString * errPath = [dirPath stringByAppendingPathComponent: @"runOpenvpnstartErrOut"];
    if (  [gFileMgr fileExistsAtPath: errPath]  ) {
        NSLog(@"runOpenvpnstart: File exists at %@", errPath);
		[stdFileHandle release];
        [dirPath release];
        return -1;
    }
    if (  ! [gFileMgr createFileAtPath: errPath contents: nil attributes: nil]  ) {
        NSLog(@"runOpenvpnstart: Unable to create %@", errPath);
		[stdFileHandle release];
        [dirPath release];
        return -1;
    }
    NSFileHandle * errFileHandle = [[NSFileHandle fileHandleForWritingAtPath: errPath] retain];
    if (  ! errFileHandle  ) {
        NSLog(@"runOpenvpnstart: Unable to get NSFileHandle for %@", errPath);
		[stdFileHandle release];
        [dirPath release];
        return -1;
    }
    
    NSTask * task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath: path];
    [task setArguments:arguments];
    [task setStandardOutput: stdFileHandle];
    [task setStandardError:  errFileHandle];
    [task setCurrentDirectoryPath: @"/tmp"];
    [task launch];
    [task waitUntilExit];
    
    [stdFileHandle closeFile];
    [stdFileHandle release];
    [errFileHandle closeFile];
    [errFileHandle release];
    
	OSStatus status = [task terminationStatus];
    
    NSString * subcommand = ([arguments count] > 0
                             ? [arguments objectAtIndex: 0]
                             : @"(no subcommand!)");
    
    NSFileHandle * file = [NSFileHandle fileHandleForReadingAtPath: stdPath];
    NSData * data = [file readDataToEndOfFile];
    [file closeFile];
    NSString * outputString = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
    if (  stdoutString  ) {
        *stdoutString = outputString;
    } else {
        if (  [outputString length] != 0  ) {
            NSLog(@"openvpnstart stdout from %@:\n%@", subcommand, outputString);
        }
    }
    
    file = [NSFileHandle fileHandleForReadingAtPath: errPath];
    data = [file readDataToEndOfFile];
    [file closeFile];
    outputString = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
    if (  stderrString  ) {
        *stderrString = outputString;
    } else {
        if (  [outputString length] != 0  ) {
            NSLog(@"openvpnstart stderr from %@:\n%@", subcommand, outputString);
        }
    }
	
    if (  ! [gFileMgr tbRemoveFileAtPath: dirPath handler: nil]  ) {
        NSLog(@"Unable to remove temporary folder at %@", dirPath);
    }
    [dirPath release];

    if (   (status != EXIT_SUCCESS)
        && ( ! stderrString)  ) {
        NSLog(@"openvpnstart status from %@: %ld", subcommand, (long) status);
    }
	
    return status;
}

BOOL tunnelblickTestPrivateOnlyHasTblks(void)
{
    NSString * privatePath = [[[[NSHomeDirectory()
                                 stringByAppendingPathComponent: @"Library"]
                                stringByAppendingPathComponent: @"Application Support"]
                               stringByAppendingPathComponent: @"Tunnelblick"]
                              stringByAppendingPathComponent: @"Configurations"];
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: privatePath];
    NSString * file;
    while (  (file = [dirEnum nextObject])  )
	{
        if (  [[file pathExtension] isEqualToString: @"tblk"]  )
		{
            [dirEnum skipDescendents];
        } else {
            if (   [[file pathExtension] isEqualToString: @"ovpn"]
                || [[file pathExtension] isEqualToString: @"conf"]  )
			{
                return NO;
            }
        }
    }
    
    return YES;
}

BOOL tunnelblickTestAppInApplications(void)
{
    NSString * appContainer = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
    return [appContainer isEqualToString: @"/Applications"];
}

BOOL tunnelblickTestDeployed(void)
{
    // Returns TRUE if Deploy folder exists and contains anything
    
 	NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: gDeployPath];
    NSString * file;
    BOOL haveSomethingInDeployFolder = FALSE;
    while (  (file = [dirEnum nextObject])  )
	{
        if (  ! [file hasPrefix: @"."]  )		// Ignore .DS_Store, .svn, etc.
		{
            haveSomethingInDeployFolder = TRUE;
            break;
        }
    }
    
    return haveSomethingInDeployFolder;
}

BOOL tunnelblickTestHasDeployBackups(void)
{
    // Returns TRUE if Deploy backup folder exists
    
    NSString * deployBackupsPath = @"/Library/Application Support/Tunnelblick/Backup";
	BOOL isDir;
	if (   [gFileMgr fileExistsAtPath: deployBackupsPath isDirectory: &isDir]
		&& isDir  ) {
		return YES;
	}
	
	return NO;
}

// This method translates and returns non-literal OpenVPN message.
// It is used to consolidate the use of NS LocalizedString (non-literal-string...) in one place to minimize warnings from genstrings.
//                                        ^ space inserted to keep genstrings from finding this
NSString * localizeNonLiteral(NSString * msg, NSString * type)
{
	(void) type;
	
    return NSLocalizedString(msg, type);
}

// This method is never invoked. It is a place to put strings which are used in the DMG or the .nib or come from OpenVPN
// They are here so that automated tools that deal with strings (such as the "getstrings" command) will include them.
void localizableStrings(void)
{
	// These strings come from "thank you" emails
    NSLocalizedString(@"Thanks for your Tunnelblick donation", @"Window text");
    NSLocalizedString(@"Thank you very much for your donation to the TunnelblickProject.", @"Window text");
	
	
    // This string comes from the "Other Sources/dmgFiles/background.rtf" file, used to generate an image for the DMG
    NSLocalizedString(@"Double-click to begin", @"Text on disk image");
    
    // These strings come from OpenVPN and indicate the status of a connection
    NSLocalizedString(@"ADD_ROUTES",    @"Connection status");
    NSLocalizedString(@"ASSIGN_IP",     @"Connection status");
    NSLocalizedString(@"AUTH",          @"Connection status");
    NSLocalizedString(@"CONNECTED",     @"Connection status");
    NSLocalizedString(@"CONNECTING",    @"Connection status");
    NSLocalizedString(@"EXITING",       @"Connection status");
    NSLocalizedString(@"GET_CONFIG",    @"Connection status");
    NSLocalizedString(@"RECONNECTING",  @"Connection status");
    NSLocalizedString(@"RESOLVE",       @"Connection status");
    NSLocalizedString(@"SLEEP",         @"Connection status");
    NSLocalizedString(@"TCP_CONNECT",   @"Connection status");
    NSLocalizedString(@"UDP_CONNECT",   @"Connection status");
    NSLocalizedString(@"WAIT",          @"Connection status");
}
