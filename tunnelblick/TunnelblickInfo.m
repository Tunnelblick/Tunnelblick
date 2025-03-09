/*
 * Copyright by Jonathan K. Bullard Copyright 2024. All rights reserved.
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

// Provides instance methods to access information about a Tunnelblick.app,
// the system, and the user.

#import <sys/sysctl.h>

#import "TunnelblickInfo.h"

#import "helper.h"
#import "MenuController.h"
#import "NSFileManager+TB.h"
#import "sharedRoutines.h"
#import "TBUserDefaults.h"

extern TBUserDefaults * gTbDefaults;
extern NSFileManager  * gFileMgr;
extern MenuController * gMC;

@implementation TunnelblickInfo

-(TunnelblickInfo *) initForAppAtPath: (NSString *) path {

    if ( (self = [super init])  ) {

        if (  ! path  ) {
            path = [[NSBundle mainBundle] bundlePath];
        } else {

            // Quick check that it looks like a Tunnelblick.app: does it have tunnelblickd?
            NSString * tunnelblickdPath = [path stringByAppendingPathComponent:
                                           @"Contents/Resources/tunnelblickd"];
            if (  ! [gFileMgr fileExistsAtPath: tunnelblickdPath]) {
                return nil; // Not a Tunnelblick.app
            }
        }

        appPath = [path retain];
    }

    return self;
}

TBSYNTHESIZE_OBJECT_GET(retain, NSString *, appPath)

-(NSDictionary *) infoDictionary {

    if (  ! infoDictionary  ) {

        NSString * InfoPlistPath = [self.appPath stringByAppendingPathComponent: @"Contents/Info.plist" ];
        NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: InfoPlistPath];
        if (  ! dict  ) {
            NSLog(@"ERROR: Could not read %@", InfoPlistPath);
            [gMC terminateBecause: terminatingBecauseOfError];
            return @{}; // Satisfy static analyzer
        }

        infoDictionary = [dict retain];
    }

    return [[infoDictionary copy] autorelease];
}

-(NSString *) tunnelblickBuildString {

    if (  ! tunnelblickBuildString  ) {
        NSString * buildString = [self.infoDictionary objectForKey: @"CFBundleVersion"];
        if (  ! buildString  ) {
            NSLog(@"ERROR: Could not get CFBundleVersion");
            [gMC terminateBecause: terminatingBecauseOfError];
            return @""; // Satisfy static analyzer
        }

        tunnelblickBuildString = [buildString retain];
    }

    return [[tunnelblickBuildString copy] autorelease];
}

-(BOOL) runningATunnelblickBeta {

    if (  ! runningATunnelblickBeta  ) {

        NSString * version = [self tunnelblickVersionString];
        BOOL isBeta = [version containsString: @"beta"];

        runningATunnelblickBeta = [[NSNumber numberWithBool: isBeta] copy];
    }

    return runningATunnelblickBeta.boolValue;
}

-(NSString *) tunnelblickVersionString {

    if (  ! tunnelblickVersionString  ) {
        NSString * versionString = [self.infoDictionary objectForKey: @"CFBundleShortVersionString"];
        if (  ! versionString  ) {
            NSLog(@"ERROR: Could not get CFBundleShortVersionString");
            [gMC terminateBecause: terminatingBecauseOfError];
            return @""; // Satisfy static analyzer
        }

        tunnelblickVersionString = [versionString retain];
    }

    return [[tunnelblickVersionString copy] autorelease];
}

-(NSString *) forcedPreferenceStringOrInfoPlistStringForKey: (NSString *) key {

    // The forced preference's value for the key will be returned if it is present
    // and the value is a string, otherwise the Info.plist's value for the key will
    // be returned if it is present and the value is a string.
    // Otherwise, logs an error, terminates Tunnelblick, and returns nil.

    NSString * value = [gTbDefaults forcedStringForKey: key];

    if (  ! value) {
        id thing = [self.infoDictionary objectForKey: key];
        value = valueIfStringOtherwiseNil(thing);
        if (  ! value  ) {
            NSLog(@"ERROR: Could not find '%@' as a string in forced preferences or Info.plist", key);
            [gMC terminateBecause: terminatingBecauseOfError];
        }
    }

    return value;
}

-(BOOL)   isString: (NSString *) urlString
  aValidURLWithKey: (NSString *) key {

    // Returns YES if urlString is a valid URL.
    // Otherwise, logs an error, terminates Tunnelblick, and returns NO.

    NSURL * url = [NSURL URLWithString: urlString];
    if (  ! url  ) {
        NSLog(@"Error: Unable to make %@ (%@) into a URL", key, urlString);
        [gMC terminateBecause: terminatingBecauseOfError];
        return NO;
    }

    return YES;
}

-(nullable NSString *) updateTunnelblickAppcastURLString {

    // Appcast URL string for updating the Tunnelblick application,
    // including a -b or -s suffix for the beta or stable version.
    //
    // Cannot be cached because it depends on the "updateCheckBetas" preference,
    // which can change at any time.

    NSString * urlString = [gTbDefaults forcedStringForKey: @"updateFeedURL"];
    if (  ! urlString  ) {
        urlString = [self forcedPreferenceStringOrInfoPlistStringForKey: @"SUFeedURL"];
    }

    BOOL checkBeta = (   self.runningATunnelblickBeta
                      || [gTbDefaults boolForKey: @"updateCheckBetas"]);

    urlString = [self modifiedURLString: urlString forBeta: checkBeta];

    return urlString;
}

-(nullable NSString *) modifiedURLString: (nullable NSString *) urlString
                                 forBeta: (BOOL)                forBeta {

    // Returns a URL string with a "-b" or "-s" inserted to get the
    // beta or stable version of an appcast.

    if (  ! [urlString hasPrefix: @"https://"]  ) {
        if (  urlString) {
            NSLog(@"URL not 'https://': %@", urlString);
        }
        return nil;
    }

    // Strip https:// because stringByDeletingPathExtension changes the "//" to "/"
    urlString = [urlString substringFromIndex: @"https://".length];

    // Modify to insert "-b" or "-s" to get beta or stable update version
    // And restore "https://"
    NSString * urlWithoutExtension = [urlString stringByDeletingPathExtension];
    NSString * suffix = (  forBeta
                         ? @"-b"
                         : @"-s");
    urlString = [NSString stringWithFormat:
                 @"https://%@%@.%@",
                 urlWithoutExtension, suffix, urlString.pathExtension];

    return urlString;
}

-(NSString *) updatePublicDSAKey {

    // Info.plist SUPublicDSAKey value, which may be overridden by a forced preference

    if (  ! updatePublicDSAKey  ) {

        NSString * key = [self forcedPreferenceStringOrInfoPlistStringForKey: @"SUPublicDSAKey"];
        updatePublicDSAKey = [key retain];
    }

    return [[updatePublicDSAKey copy] autorelease];
}

-(NSString *) ipCheckURLString {

    // String from forced preference IPCheckURL (which is a string) if present, otherwise
    // string from Info.plist IPCheckURL (also a string).

    if (  ! ipCheckURLString  ) {
        NSString * urlString = [self forcedPreferenceStringOrInfoPlistStringForKey: @"IPCheckURL"];
        if (   urlString
            && [self isString: urlString aValidURLWithKey: @"IPCheckURL"]  ) {
            ipCheckURLString = [urlString retain];
        }
    }

    return [[ipCheckURLString copy] autorelease];
}

-(NSURL    *) ipCheckURL {

    // URL from forced preference IPCheckURL (which is a string) if present, otherwise
    // URL from Info.plist IPCheckURL (also a string).

    if (  ! ipCheckURL  ) {
        NSString * urlString = [self forcedPreferenceStringOrInfoPlistStringForKey: @"IPCheckURL"];
        if (  urlString  ) {
            NSURL * url = [NSURL URLWithString: urlString];
            if (  url  ) {
                ipCheckURL = [url retain];
            } else {
                NSLog(@"Error: Unable to make IPCheckURL (%@) into a URL", urlString);
                [gMC terminateBecause: terminatingBecauseOfError];
            }
        }
    }

    return [[ipCheckURL copy] autorelease];
}
-(void) setUpOpenVPNNames: (NSMutableArray *) nameArray
         fromFolderAtPath: (NSString *)       openvpnDirPath
                   suffix: (NSString *)       suffix {

    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: openvpnDirPath];
    NSString * dirName;
    while (  (dirName = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        if (   ( [dirName hasPrefix: @"openvpn-"] )  ) {
            NSString * versionWithSslSuffix = [dirName substringFromIndex: [@"openvpn-" length]];
            NSArray * parts = [versionWithSslSuffix componentsSeparatedByString: @"-"];
            NSString * versionWithoutSslSuffix = [parts objectAtIndex: 0];

            NSString * openvpnPath = [[openvpnDirPath stringByAppendingPathComponent: dirName ]
                                      stringByAppendingPathComponent: @"openvpn"];

            // Skip this binary if it cannot be run on this processor
            if (  ! thisArchitectureSupportsBinaryAtPath(openvpnPath)) {
                NSLog(@"This Mac cannot run the program at '%@'", openvpnPath);
                continue;
            }

            // Use ./openvpn --version to get the version information
            NSString * stdoutString = @"";
            NSString * stderrString = @"";
            OSStatus status = runTool(openvpnPath, [NSArray arrayWithObject: @"--version"], &stdoutString, &stderrString);
            if (   (status != EXIT_SUCCESS)
                && (status != 1)  ) {    //OpenVPN returns a status of 1 when the --version option is used
                NSLog(@"openvpnstart returned %lu trying to run '%@ --version'; stderr was '%@'; stdout was '%@'",
                      (unsigned long)status, openvpnPath, stderrString, stdoutString);
                [gMC terminateBecause: terminatingBecauseOfError];
                return;
            }

            NSRange rng1stSpace = [stdoutString rangeOfString: @" "];
            if (  rng1stSpace.length != 0  ) {
                NSRange rng2ndSpace = [stdoutString rangeOfString: @" " 
                                                          options: 0
                                                            range: NSMakeRange(rng1stSpace.location + 1, [stdoutString length] - rng1stSpace.location - 1)];
                if ( rng2ndSpace.length != 0  ) {
                    NSString * versionString = [stdoutString
                                                substringWithRange: NSMakeRange(rng1stSpace.location + 1, rng2ndSpace.location - rng1stSpace.location -1)];
                    if (  ! [versionString isEqualToString: versionWithoutSslSuffix]  ) {
                        NSLog(@"OpenVPN version ('%@') reported by the program is not consistent with the version ('%@') derived from the name of folder '%@' in %@",
                              versionString, versionWithoutSslSuffix, dirName, openvpnDirPath);
                        [gMC terminateBecause: terminatingBecauseOfError];
                        return;
                    }
                    [nameArray addObject: [versionWithSslSuffix stringByAppendingString: suffix]];
                    continue;
                }
            }

            NSLog(@"Error getting info from '%@ --version': stdout was '%@'", openvpnPath, stdoutString);
            [gMC terminateBecause: terminatingBecauseOfError];
            return;
        }
    }

    return;
}

-(NSArray *) allOpenvpnOpenssslVersions {

    if (  ! allOpenvpnOpenssslVersions ) {

        // The names are the folder names in Tunnelblick.app/Contents/Resources/openvpn and /Library/Application Support/Tunnelblick/Openvpn
        // that hold openvpn binaries, except that names from /Library... are suffixed by SUFFIX_FOR_OPENVPN_BINARY_IN_L_AS_T_OPENVPN
        // so they can be distinguished from the others.

        NSMutableArray * versions = [[[NSMutableArray alloc] initWithCapacity: 5] autorelease];

        // Get names from Tunnelblick.app/Contents/Resources/openvpn
        NSString * dirPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"openvpn"];
        [self setUpOpenVPNNames: versions
               fromFolderAtPath: dirPath
                         suffix: @""];

        // Add the names from /Library/Application Support/Tunnelblick/Openvpn if it exists
        dirPath = L_AS_T_OPENVPN;
        if (   [gFileMgr fileExistsAtPath: dirPath]  ) {
            [self setUpOpenVPNNames: versions
                   fromFolderAtPath: dirPath
                             suffix: SUFFIX_FOR_OPENVPN_BINARY_IN_L_AS_T_OPENVPN]; // Suffix indicates openvpn binary external to Tunnelblick
        }

        if (  versions.count == 0  ) {
            NSLog(@"There are no versions of OpenVPN in this copy of Tunnelblick or in /Library/Application Support/Tunnelblick/Openvpn");
            [gMC terminateBecause: terminatingBecauseOfError];
            return @[]; // Satisfy static analyzer
        }

        // Sort the array
        allOpenvpnOpenssslVersions = [[versions sortedArrayUsingSelector: @selector(localizedCaseInsensitiveCompare:)] copy];
    }

    return [[allOpenvpnOpenssslVersions copy] autorelease];
}

-(NSString *) defaultOpenvpnOpensslVersion {

    if (  ! defaultOpenvpnOpensslVersion ) {

        NSString * defaultVersionPath = [self.appPath stringByAppendingPathComponent:
                                         @"Contents/Resources/openvpn/default"];
        NSError * err = nil;
        NSString * defaultTargetPath = [gFileMgr destinationOfSymbolicLinkAtPath: defaultVersionPath
                                                                           error: &err];
        if (  ! defaultTargetPath  ) {
            NSLog(@"ERROR: Could not find symlink at %@", defaultVersionPath);
            [gMC terminateBecause: terminatingBecauseOfError];
            return @""; // Satisfy static analyzer
        }

        defaultOpenvpnOpensslVersion = [[[defaultTargetPath pathComponents] firstObject] copy];
    }

    return [[defaultOpenvpnOpensslVersion copy] autorelease];
}

-(NSString *) latestOpenvpnOpensslVersion {

    if (  ! latestOpenvpnOpensslVersion ) {

        NSArray * openvpnVersions = self.allOpenvpnOpenssslVersions;
        latestOpenvpnOpensslVersion = [[openvpnVersions lastObject] copy];
    }

    return [[latestOpenvpnOpensslVersion copy] autorelease];
}

-(NSString *) architectureBeingUsed {

    if (  ! architectureBeingUsed  ) {

        NSString * arch;

        char return_string[1000];
        size_t size = 1000;
        if (  sysctlbyname("machdep.cpu.brand_string", &return_string, &size, NULL, 0) == -1  ) {
            NSLog(@"architectureBeingUsed: Error from sysctlbyname(\"machdep.cpu.brand_string\"): %d (%s), assuming '%@'",
                  errno, strerror(errno), ARCH_X86);
            arch = ARCH_X86;
        } else {
            BOOL isIntel = (  strstr(return_string, "Intel") != 0  );
            arch = (  isIntel
                    ? ARCH_X86
                    : ARCH_ARM);
        }

        architectureBeingUsed = [arch retain];
    }

    return [[architectureBeingUsed copy] autorelease];
}

-(BOOL) runningWithSIPDisabled {

    if (  ! runningWithSIPDisabled  ) {

        BOOL isDisabled = YES;

        if (  ! [gFileMgr fileExistsAtPath: TOOL_PATH_FOR_CSRUTIL]  ) {
            NSLog(@"Assuming SIP is disabled (i.e., is not in effect) because '%@' does not exist", TOOL_PATH_FOR_CSRUTIL);
        } else {

            NSString * stdOutString = nil;
            NSString * stdErrString = nil;
            OSStatus status = runTool(TOOL_PATH_FOR_CSRUTIL, @[@"status"], &stdOutString, &stdErrString);
            if (  status != EXIT_SUCCESS  ) {
                NSLog(@"Error status %d from '%@ status'; assuming SIP is enabled. stdout = '%@'; stderr = '%@'",
                      status, TOOL_PATH_FOR_ID, stdOutString, stdErrString);
                isDisabled = NO;
            } else {

                BOOL disabled = [stdOutString containsString: @"System Integrity Protection status: disabled"];
                BOOL enabled  = [stdOutString containsString: @"System Integrity Protection status: enabled"];
                if (   disabled
                    && ( ! enabled)  ) {
                    isDisabled = YES;
                } else if (   enabled
                           && ( ! disabled) ) {
                    isDisabled = NO;
                } else {
                    NSLog(@"Cannot determine SIP status; assuming SIP is enabled. stdout from '%@ status' = '%@'", TOOL_PATH_FOR_CSRUTIL, stdOutString);
                    isDisabled = NO;
                }
            }
        }

        runningWithSIPDisabled = [[NSNumber numberWithBool: isDisabled] copy];
    }

    return runningWithSIPDisabled.boolValue;
}

-(NSString *) systemVersionString {

    // Returns a string like "14.6.1", i.e., the numeric version (not including a name such as "Sonoma")

    if (  ! systemVersionString  ) {

        NSOperatingSystemVersion  osVersion =[[NSProcessInfo processInfo] operatingSystemVersion];
        NSString * versionString = [NSString stringWithFormat:@"%ld.%ld.%ld",
                                    osVersion.majorVersion, osVersion.minorVersion, osVersion.patchVersion];

        systemVersionString = [versionString copy];
    }

    return [[systemVersionString copy] autorelease];
}

-(NSArray *) systemSounds {

    if (  ! systemSounds  ) {

        // Get all the names of sounds
        NSMutableArray * sounds = [[[NSMutableArray alloc] initWithCapacity: 30] autorelease];
        NSArray * soundDirs = [NSArray arrayWithObjects:
                               [NSHomeDirectory() stringByAppendingString: @"/Library/Sounds"],
                               @"/Library/Sounds",
                               @"/Network/Library/Sounds",
                               @"/System/Library/Sounds",
                               nil];
        NSArray * soundTypes = [NSArray arrayWithObjects: @"aiff", @"wav", nil];
        NSEnumerator * soundDirEnum = [soundDirs objectEnumerator];
        NSString * folder;
        NSString * file;
        while (  (folder = [soundDirEnum nextObject])  ) {
            NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: folder];
            while (  (file = [dirEnum nextObject])  ) {
                [dirEnum skipDescendents];
                if (  [soundTypes containsObject: [file pathExtension]]  ) {
                    NSString * soundName = [file stringByDeletingPathExtension];
                    if (  ! [sounds containsObject: soundName]  ) {
                        [sounds addObject: soundName];
                    }
                }
            }
        }

        systemSounds = [[sounds sortedArrayUsingSelector: @selector(localizedCaseInsensitiveCompare:)] copy];
    }

    return [[systemSounds copy] autorelease];
}

-(BOOL) systemVersionCanLoadKexts {

    BOOL result = [self.systemVersionString compare: LOWEST_MACOS_THAT_CANNOT_LOAD_KEXTS]  == NSOrderedAscending;
    return result;
}

-(BOOL) runningOnMacOSBeta {

    if (  ! runningOnMacOSBeta  ) {

        BOOL onBeta = NO;
        NSString * stdOutString = nil;
        NSString * stdErrString = nil;
        OSStatus status = runTool(TOOL_PATH_FOR_SW_VERS, @[@"-buildVersion"], &stdOutString, &stdErrString);
        if (   (status != EXIT_SUCCESS)
            || ([stdOutString length] == 0)  ) {
            NSLog(@"Error status %d from 'sw_vers -buildVersion'; stdout = '%@'; stderr = '%@'", status, stdOutString, stdErrString);
            [gMC terminateBecause: terminatingBecauseOfError];
            return NO; // Satisfy static analyzer
        }

        NSString * lastCharacter = [stdOutString substringWithRange: NSMakeRange([stdOutString length] - 1, 1)];
        onBeta = [@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" containsString: lastCharacter];

        runningOnMacOSBeta = [[NSNumber numberWithBool: onBeta] copy];
    }

    return runningOnMacOSBeta.boolValue;
}

-(NSDictionary *) nvramContents {

    static NSDictionary * contents = nil;

    if (  contents  ) {
        return [[contents retain] autorelease];
    }

    // Get contents

    kern_return_t               result;
    mach_port_t                 masterPort;
    static io_registry_entry_t  gOptionsRef;

    result = IOMasterPort(bootstrap_port, &masterPort);
    if (result != KERN_SUCCESS) {
        NSLog(@"nvramContents: Error getting the IOMaster port: %s", mach_error_string(result));
        return nil;
    }

    gOptionsRef = IORegistryEntryFromPath(masterPort, "IODeviceTree:/options");
    if (gOptionsRef == 0) {
        NSLog(@"nvramContents: NVRAM is not supported on this system");
        return nil;
    }

    // Get dictionary with NVRAM contents
    CFMutableDictionaryRef dictCF;

    result = IORegistryEntryCreateCFProperties(gOptionsRef, &dictCF, 0, 0);
    if (result != KERN_SUCCESS) {
        NSLog(@"nvramContents: Error getting the NVRAM: %s", mach_error_string(result));
    }

    NSDictionary * dict = (__bridge NSMutableDictionary *)dictCF;

    NSMutableDictionary * dictM = [[NSMutableDictionary alloc] initWithCapacity: [dict count]];
    [dict enumerateKeysAndObjectsUsingBlock: ^(id key, id obj, BOOL *stop) {
        [dictM setObject: obj forKey: key];
        (void)stop;
    }];
    contents = [[NSDictionary dictionaryWithDictionary: dictM] retain];

    [dictM release];
    CFRelease(dictCF);
    IOObjectRelease(gOptionsRef);

    return contents;
}

-(BOOL) runningOnOCLP {

    if (  ! runningOnOCLP  ) {

        NSDictionary * nvram = [self nvramContents];
        BOOL onOCLP = [nvram doesContain: @"4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version"];

        runningOnOCLP = [[NSNumber numberWithBool: onOCLP] copy];
    }

    return runningOnOCLP.boolValue;
}

-(BOOL) runningInDarkMode {

    // Cannot be cached
    
    NSString *osxMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"];
    BOOL darkMode = (   [osxMode isEqualToString: @"dark"]
                     || [osxMode isEqualToString: @"Dark"]  );
    return darkMode;
}

-(BOOL) userIsAnAdmin {

    if (  ! userIsAnAdmin  ) {

        BOOL isAdmin = NO; // Assume not an admin

        // Run "id -Gn" to get a list of names of the groups the user is a member of
        NSString * stdoutString = nil;
        NSArray  * arguments = [NSArray arrayWithObject: @"-Gn"];
        OSStatus status = runTool(TOOL_PATH_FOR_ID, arguments, &stdoutString, nil);
        if (   (status != 0)
            || (! stdoutString)) {
            NSLog(@"Assuming user is not an administrator because '%@ -Gn' returned status %ld or it's output was empty", TOOL_PATH_FOR_ID, (long)status);
        } else {

            // If the "admin" group appears in the output, the user is a member of the "admin" group, so they are an admin.
            // Group names don't include spaces and are separated by spaces, so this is easy. We just have to
            // handle admin being at the start or end of the output by pre- and post-fixing a space.

            NSString * groupNames = [NSString stringWithFormat:@" %@ ", stdoutString];
            NSRange rng = [groupNames rangeOfString:@" admin "];
            isAdmin = (rng.location != NSNotFound);
        }

        userIsAnAdmin = [[NSNumber numberWithBool: isAdmin] copy];
    }

    return userIsAnAdmin.boolValue;
}

@end
