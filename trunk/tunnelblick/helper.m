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

#import "defines.h"
#import "helper.h"
#import "TBUserDefaults.h"
#import "NSApplication+SystemVersion.h"
#import "NSApplication+LoginItem.h"
#import "NSFileManager+TB.h"
#import "MenuController.h"
#import "AuthAgent.h"

// PRIVATE FUNCTIONS:
NSDictionary * parseVersion             (NSString * string);
NSRange        rangeOfDigits            (NSString * s);
void           localizableStrings       (void);
BOOL           copyOrMoveCredentials    (NSString * fromDisplayName,
                                         NSString * toDisplayName,
                                         BOOL moveNotCopy);

// The following external, global variables are used by functions in this file and must be declared and set elsewhere before the
// functions in this file are called:
extern NSMutableArray  * gConfigDirs;
extern NSString        * gPrivatePath;
extern NSFileManager   * gFileMgr;
extern TBUserDefaults  * gTbDefaults;
extern NSDictionary    * gOpenVPNVersionDict;  

BOOL runningOnTigerOrNewer()
{
    unsigned major, minor, bugFix;
    [[NSApplication sharedApplication] getSystemVersionMajor:&major minor:&minor bugFix:&bugFix];
    return ( (major > 10) || (minor > 3) );
}

BOOL runningOnLeopardOrNewer()
{
    unsigned major, minor, bugFix;
    [[NSApplication sharedApplication] getSystemVersionMajor:&major minor:&minor bugFix:&bugFix];
    return ( (major > 10) || (minor > 4) );
}

BOOL runningOnSnowLeopardOrNewer()
{
    unsigned major, minor, bugFix;
    [[NSApplication sharedApplication] getSystemVersionMajor:&major minor:&minor bugFix:&bugFix];
    return ( (major > 10) || (minor > 5) );
}

// Returns an escaped version of a string so it can be sent over the management interface
NSString * escaped(NSString *string)
{
	NSMutableString * stringOut = [[string mutableCopy] autorelease];
	[stringOut replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:NSLiteralSearch range:NSMakeRange(0, [string length])];
	[stringOut replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:NSLiteralSearch range:NSMakeRange(0, [string length])];
	return stringOut;
}

// Returns the path of the configuration folder in which a specified configuration file is contained
// Returns nil if it is not in any configuration folder
NSString * firstPartOfPath(NSString * thePath)
{
    int i;
    for (i=0; i < [gConfigDirs count]; i++) {
        if (  [thePath hasPrefix: [gConfigDirs objectAtIndex: i]]  ) {
            return [[[gConfigDirs objectAtIndex: i] copy] autorelease];
        }
    }
    
    NSString *altPath = [NSString stringWithFormat:@"/Library/Application Support/Tunnelblick/Users/%@", NSUserName()];
    if (  [thePath hasPrefix: altPath]  ) {
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
            NSLog(@"Warning: Created directory %@ but unable to set permissions to %lu", dirPath, permissions);
            return 1;
        } else {
            NSLog(@"Error: Unable to create directory %@ with permissions %lu", dirPath, permissions);
            return -1;
        }
    }
    
    return 1;
}

BOOL itemIsVisible(NSString * path)
{
    if (  [path hasPrefix: @"."]  ) {
        return NO;
    }
    NSRange rng = [path rangeOfString:@"/."];
    if (  rng.length != 0) {
        return NO;
    }
    return YES;
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

BOOL folderContentsNeedToBeSecuredAtPath(NSString * theDirPath)
{
    NSArray * extensionsFor600Permissions = [NSArray arrayWithObjects: @"cer", @"crt", @"der", @"key", @"p12", @"p7b", @"p7c", @"pem", @"pfx", nil];
    NSString * file;
    BOOL isDir;
    
    // If it isn't an existing folder, then it can't be secured!
    if (  ! (   [gFileMgr fileExistsAtPath: theDirPath isDirectory: &isDir]
             && isDir )  ) {
        return YES;
    }
    
    uid_t realUid = getuid();
    gid_t realGid = getgid();
    NSDirectoryEnumerator *dirEnum = [gFileMgr enumeratorAtPath: theDirPath];
    while (file = [dirEnum nextObject]) {
        NSString * filePath = [theDirPath stringByAppendingPathComponent: file];
        if (  itemIsVisible(filePath)  ) {
            NSString * ext  = [file pathExtension];
            if (   [gFileMgr fileExistsAtPath: filePath isDirectory: &isDir]
                && isDir  ) {
                if (  [filePath hasPrefix: gPrivatePath]  ) {
                    if (   [ext isEqualToString: @"tblk"]
                        || [filePath hasSuffix: @".tblk/Contents/Resources"]  ) {
                        if (  ! checkOwnerAndPermissions(filePath, realUid, realGid, @"755")  ) {   // .tblk and .tblk/Contents/Resource in private folder owned by user
                            return YES;
                        }
                    } else {
                        if (  ! checkOwnerAndPermissions(filePath, 0, 0, @"755")  ) {               // other folders owned by root
                            return YES;
                        }
                    }
                } else {
                    if (  ! checkOwnerAndPermissions(filePath, 0, 0, @"755")  ) {   // other folders are 755
                        return YES; // NSLog already called
                    }
                }
            } else if ( [ext isEqualToString:@"executable"]  ) {
                if (  ! checkOwnerAndPermissions(filePath, 0, 0, @"755")  ) {       // executable files for custom menu commands are 755
                    return YES; // NSLog already called
                }
            } else if ( [ext isEqualToString:@"sh"]  ) {
                if (  ! checkOwnerAndPermissions(filePath, 0, 0, @"744")  ) {       // shell scripts are 744
                    return YES; // NSLog already called
                }
            } else if (  [extensionsFor600Permissions containsObject: ext]  ) {     // keys, certs, etc. are 600
                if (  ! checkOwnerAndPermissions(filePath, 0, 0, @"600")  ) {
                    return YES; // NSLog already called
                }
            } else { // including .conf and .ovpn
                if (  ! checkOwnerAndPermissions(filePath, 0, 0,  @"644")  ) {      // everything else is 644
                    return YES; // NSLog already called
                }
            }
        }
    }
    return NO;
}

// Returns YES if file doesn't exist, or has the specified ownership and permissions
BOOL checkOwnerAndPermissions(NSString * fPath, uid_t uid, gid_t gid, NSString * permsShouldHave)
{
    if (  ! [gFileMgr fileExistsAtPath: fPath]  ) {
        return YES;
    }
    
    NSDictionary *fileAttributes = [gFileMgr tbFileAttributesAtPath:fPath traverseLink:YES];
    unsigned long perms = [fileAttributes filePosixPermissions];
    NSString *permissionsOctal = [NSString stringWithFormat:@"%o",perms];
    NSNumber *fileOwner = [fileAttributes fileOwnerAccountID];
    NSNumber *fileGroup = [fileAttributes fileGroupOwnerAccountID];
    
    if (   [permissionsOctal isEqualToString: permsShouldHave]
        && [fileOwner isEqualToNumber:[NSNumber numberWithInt:(int) uid]]
        && [fileGroup isEqualToNumber:[NSNumber numberWithInt:(int) gid]]) {
        return YES;
    }
    
    NSLog(@"File %@ has permissions: %@, is owned by %@:%@ and needs repair", fPath, permissionsOctal, fileOwner, fileGroup);
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
    NSString * appVersion;
    if (  [infoShort hasPrefix: @"Tunnelblick "]  ) {
        appVersion = [infoShort substringFromIndex: [@"Tunnelblick " length]];
    } else {
        appVersion = infoShort;
    }
    
    NSString * appVersionWithoutBuild;
    int parenStart;
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

// Returns a string with the version # for OpenVPN, e.g., "OpenVPN 2 (2.1_rc15)"
NSString * openVPNVersion(void)
{
    NSDictionary * OpenVPNV = gOpenVPNVersionDict;
    NSString * version      = [NSString stringWithFormat:@"OpenVPN %@",
                               [OpenVPNV objectForKey:@"full"]
                              ];
    return ([NSString stringWithString: version]);
}

// Returns a dictionary from parseVersion with version info about OpenVPN
NSDictionary * getOpenVPNVersion(void)
{
    //Launch "openvpnstart OpenVPNInfo", which launches openvpn (as root) with no arguments to get info, and put the result into an NSString:
    
    NSTask * task = [[NSTask alloc] init];
    
    NSString * exePath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"openvpnstart"];
    [task setLaunchPath: exePath];
    
    NSArray  *arguments = [NSArray arrayWithObjects: @"OpenVPNInfo", nil];
    [task setArguments: arguments];
    
    NSPipe * pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    
    NSFileHandle * file = [pipe fileHandleForReading];
    
    [task launch];
    
    NSData * data = [file readDataToEndOfFile];
    
    [task release];
    
    NSString * string = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    
    // Now extract the version. String should look like "OpenVPN <version> <more-stuff>" with a spaces on the left and right of the version
    
    NSArray * arr = [string componentsSeparatedByString:@" "];
    [string release];
    string = @"Unknown";
    if (  [arr count] > 1  ) {
        if (  [[arr objectAtIndex:0] isEqual:@"OpenVPN"]  ) {
            if (  [[arr objectAtIndex:1] length] < 100  ) {     // No version # should be as long as this arbitrary number!
                string = [arr objectAtIndex:1];
            }
        }
    }
    
    return (  [[parseVersion(string) copy] autorelease]  );
}

// Given a string with a version number, parses it and returns an NSDictionary with full, preMajor, major, preMinor, minor, preSuffix, suffix, and postSuffix fields
//              full is the full version string as displayed by openvpn when no arguments are given.
//              major, minor, and suffix are strings of digits (may be empty strings)
//              The first string of digits goes in major, the second string of digits goes in minor, the third string of digits goes in suffix
//              preMajor, preMinor, preSuffix and postSuffix are strings that come before major, minor, and suffix, and after suffix (may be empty strings)
//              if no digits, everything goes into preMajor
NSDictionary * parseVersion( NSString * string)
{
    NSRange r;
    NSString * s = string;
    
    NSString * preMajor     = @"";
    NSString * major        = @"";
    NSString * preMinor     = @"";
    NSString * minor        = @"";
    NSString * preSuffix    = @"";
    NSString * suffix       = @"";
    NSString * postSuffix   = @"";
    
    r = rangeOfDigits(s);
    if (r.length == 0) {
        preMajor = s;
    } else {
        preMajor = [s substringToIndex:r.location];
        major = [s substringWithRange:r];
        s = [s substringFromIndex:r.location+r.length];
        
        r = rangeOfDigits(s);
        if (r.length == 0) {
            preMinor = s;
        } else {
            preMinor = [s substringToIndex:r.location];
            minor = [s substringWithRange:r];
            s = [s substringFromIndex:r.location+r.length];
            
            r = rangeOfDigits(s);
            if (r.length == 0) {
                preSuffix = s;
             } else {
                 preSuffix = [s substringToIndex:r.location];
                 suffix = [s substringWithRange:r];
                 postSuffix = [s substringFromIndex:r.location+r.length];
            }
        }
    }
    
//NSLog(@"full = '%@'; preMajor = '%@'; major = '%@'; preMinor = '%@'; minor = '%@'; preSuffix = '%@'; suffix = '%@'; postSuffix = '%@'    ",
//      string, preMajor, major, preMinor, minor, preSuffix, suffix, postSuffix);
    return (  [NSDictionary dictionaryWithObjectsAndKeys:
               [[string copy] autorelease], @"full",
               [[preMajor copy] autorelease], @"preMajor",
               [[major copy] autorelease], @"major",
               [[preMinor copy] autorelease], @"preMinor",
               [[minor copy] autorelease], @"minor",
               [[preSuffix copy] autorelease], @"preSuffix",
               [[suffix copy] autorelease], @"suffix",
               [[postSuffix copy] autorelease], @"postSuffix",
               nil]  );
}


// Examines an NSString for the first decimal digit or the first series of decimal digits
// Returns an NSRange that includes all of the digits
NSRange rangeOfDigits(NSString * s)
{
    NSRange r1, r2;
    // Look for a digit
    r1 = [s rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet] ];
    if ( r1.length == 0 ) {
        
        // No digits, return that they were not found
        return (r1);
    } else {
        
        // r1 has range of the first digit. Look for a non-digit after it
        r2 = [[s substringFromIndex:r1.location] rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]];
        if ( r2.length == 0) {
           
            // No non-digits after the digits, so return the range from the first digit to the end of the string
            r1.length = [s length] - r1.location;
            return (r1);
        } else {
            
            // Have some non-digits, so the digits are between r1 and r2
            r1.length = r1.location + r2.location - r1.location;
            return (r1);
        }
    }
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
    return TBRunAlertPanelExtended(title, msg, defaultButtonLabel, alternateButtonLabel, otherButtonLabel, nil, nil, nil);
}

// Like TBRunAlertPanel but allows a "do not show again" preference key and checkbox, or a checkbox for some other function.
// If the preference is set, the panel is not shown and "NSAlertDefaultReturn" is returned.
// If the preference can be changed by the user, or the checkboxResult pointer is not nil, the panel will include a checkbox with the specified label.
// If the preference can be changed by the user, the preference is set if the user checks the box and the default button is clicked.
// If the checkboxResult pointer is not nil, the initial value of the checkbox will be set from it, and the value of the checkbox is returned to it.
int TBRunAlertPanelExtended(NSString * title,
                            NSString * msg,
                            NSString * defaultButtonLabel,
                            NSString * alternateButtonLabel,
                            NSString * otherButtonLabel,
                            NSString * doNotShowAgainPreferenceKey,
                            NSString * checkboxLabel,
                            BOOL     * checkboxResult)
{
    if (  doNotShowAgainPreferenceKey && [gTbDefaults boolForKey: doNotShowAgainPreferenceKey]  ) {
        return NSAlertDefaultReturn;
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
    
    SInt32 error;
    CFUserNotificationRef notification;
    CFOptionFlags response;

    CFOptionFlags checkboxChecked = 0;
    if (  checkboxResult  ) {
        if (  * checkboxResult  ) {
            checkboxChecked = CFUserNotificationCheckBoxChecked(0);
        }
    }
    
    [NSApp activateIgnoringOtherApps:YES];
    notification = CFUserNotificationCreate(NULL, 0, checkboxChecked, &error, (CFDictionaryRef) dict);
    
    if(  error || CFUserNotificationReceiveResponse(notification, 0, &response)  ) {
        CFRelease(notification);
        [dict release];
        return NSAlertErrorReturn;     // Couldn't receive a response
    }
    
    CFRelease(notification);
    [dict release];
    
    if (  checkboxResult  ) {
        if (  response & CFUserNotificationCheckBoxChecked(0)  ) {
            * checkboxResult = TRUE;
        } else {
            * checkboxResult = FALSE;
        }
    } 

    switch (response & 0x3) {
        case kCFUserNotificationDefaultResponse:
           if (  checkboxLabel  ) {
               if (   doNotShowAgainPreferenceKey
                   && [gTbDefaults canChangeValueForKey: doNotShowAgainPreferenceKey]
                   && ( response & CFUserNotificationCheckBoxChecked(0) )  ) {
                   [gTbDefaults setBool: TRUE forKey: doNotShowAgainPreferenceKey];
                   [gTbDefaults synchronize];
               }
           }
           
           return NSAlertDefaultReturn;
            
        case kCFUserNotificationAlternateResponse:
            return NSAlertAlternateReturn;
            
        case kCFUserNotificationOtherResponse:
            return NSAlertOtherReturn;
            
        default:
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
        [NSApp setAutoLaunchOnLogin: NO];
        [NSApp terminate: nil];
    }
    
    strlcpy(tempDirectoryNameCString, tempDirectoryTemplateCString, bufferLength);
    
    char * dirPath = mkdtemp(tempDirectoryNameCString);
    if (  ! dirPath  ) {
        NSLog(@"Unable to create a temporary directory");
        [NSApp setAutoLaunchOnLogin: NO];
        [NSApp terminate: nil];
    }
    
    NSString *tempFolder = [gFileMgr stringWithFileSystemRepresentation: tempDirectoryNameCString
                                                                 length: strlen(tempDirectoryNameCString)];
    free(tempDirectoryNameCString);
    
    // End of code from http://cocoawithlove.com/2009/07/temporary-files-and-folders-in-cocoa.html
    //**********************************************************************************************
    
    return [tempFolder retain];
}


// Modified from http://developer.apple.com/library/mac/#documentation/Carbon/Conceptual/ProvidingUserAssitAppleHelp/using_ah_functions/using_ah_functions.html#//apple_ref/doc/uid/TP30000903-CH208-CIHFABIE
OSStatus MyGotoHelpPage (CFStringRef pagePath, CFStringRef anchorName)
{
    OSStatus err = fnfErr;
    
    if (  FALSE && runningOnSnowLeopardOrNewer()  ) {   // DISABLE THIS -- IT DOESN'T WORK CONSISTENTLY
        
        CFBundleRef myApplicationBundle = NULL;
        CFStringRef myBookName = NULL;
        
        myApplicationBundle = CFBundleGetMainBundle();// 1
        if (myApplicationBundle == NULL) {err = fnfErr; goto bail;}// 2
        
        myBookName = CFBundleGetValueForInfoDictionaryKey(// 3
                                                          myApplicationBundle,
                                                          CFSTR("CFBundleHelpBookName"));
        
        if (myBookName == NULL) {err = fnfErr; goto bail;}
        
        if (CFGetTypeID(myBookName) != CFStringGetTypeID()) {// 4
            err = paramErr;
            goto bail;
        }
        
        err = AHGotoPage (myBookName, pagePath, anchorName);// 5
    } else {
        NSString * pagePathS = (NSString *) pagePath;
        NSString * fullPath = [[NSBundle mainBundle] pathForResource: pagePathS ofType: nil inDirectory: @"help"];
        if (  fullPath  ) {
            err = ( [[NSWorkspace sharedWorkspace] openFile: fullPath] ) 
            ? 0
            : fnfErr;
        } else {
            NSLog(@"Unable to locate %@ in 'help' resource folder", pagePathS);
        }
    }
    
bail:
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
    notification = CFUserNotificationCreate(NULL, 30, 0, &error, (CFDictionaryRef)panelDict);
    [panelDict release];
    
    if((error) || (CFUserNotificationReceiveResponse(notification, 0, &response))) {
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
        NSRange rng = [newName rangeOfString: @"/"];
        if (  rng.length != 0) {
            newName = TBGetString([@"Names must not contain slashes (\"/\") --only enter that part of the name that comes after any slashes\n\n" stringByAppendingString: msg], nameToPrefill);
        } else if (  [newName length] == 0  ) {
            newName = TBGetString([@"Please enter a name and click \"OK\" or click \"Cancel\".\n\n" stringByAppendingString: msg], nameToPrefill);
        } else {
            NSString * targetPath = [[[sourcePath stringByDeletingLastPathComponent] stringByAppendingPathComponent: newName] stringByAppendingPathExtension: @"conf"]; // (Don't use the .conf, but may need it for lastPartOfPath)
            NSString * dispNm = [lastPartOfPath(targetPath) stringByDeletingPathExtension];
            if (  nil == [[[NSApp delegate] myConfigDictionary] objectForKey: dispNm]  ) {
                break;
            }
            newName = TBGetString([@"That name is being used.\n\n" stringByAppendingString: msg], nameToPrefill);
        }
    }
    
    return newName;
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
    NSString * myPassphrase = nil;
    NSString * myUsername = nil;
    NSString * myPassword = nil;
    
    AuthAgent * myAuthAgent = [[[AuthAgent alloc] initWithConfigName: fromDisplayName] autorelease];
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

// This method translates and returns non-literal OpenVPN message.
// It is used to consolidate the use of NSLocalizedString(non-literal-string...) in one place to minimize warnings from genstrings.
NSString * localizeNonLiteral(NSString * msg, NSString * type)
{
    return NSLocalizedString(msg, type);
}

// This method is never invoked. It is a place to put strings which are used in the DMG or the .nib or come from OpenVPN
// They are here so that automated tools that deal with strings (such as the "getstrings" command) will include them.
void localizableStrings(void)
{
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
