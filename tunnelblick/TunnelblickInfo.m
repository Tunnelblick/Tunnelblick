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


#import "TunnelblickInfo.h"

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

-(NSString *) infoPlistStringOrPreferenceString: (NSString *) name {

    // "name" is the key for an item in Info.plist, which is also
    // the key for an optional item in forced preferences.
    //
    // The forced preference's value will be used if it the key is present,
    // otherwise the Info.plist's value will be used.

    NSString * urlString = nil;
    if (  ! [gTbDefaults canChangeValueForKey: name]  ) {
        urlString = [gTbDefaults stringForKey: name];
    }

    if (  ! urlString) {
        urlString = [self.infoDictionary objectForKey: name];
    }

    if (  ! urlString  ) {
        NSLog(@"ERROR: Could not get %@", name);
        [gMC terminateBecause: terminatingBecauseOfError];
    }

    return urlString;
}

-(void) crashIfNotAValidURL: (NSString *) urlString {

    NSURL * url = [NSURL URLWithString: urlString];
    if (  ! url  ) {
        NSLog(@"Unable to make into a URL: %@", urlString);
        [gMC terminateBecause: terminatingBecauseOfError];
    }
}

-(NSString *) updateFeedURLString {

    // Info.plist SUFeedURL value, which may be overridden by a forced preference

    if (  ! updateFeedURLString  ) {

        NSString * urlString = [self infoPlistStringOrPreferenceString: @"SUFeedURL"];
        [self crashIfNotAValidURL: urlString];
        updateFeedURLString = [urlString retain];
    }

    return [[updateFeedURLString copy] autorelease];
}

-(NSString *) updatePublicDSAKey {

    // Info.plist SUPublicDSAKey value, which may be overridden by a forced preference

    if (  ! updatePublicDSAKey  ) {

        NSString * key = [self infoPlistStringOrPreferenceString: @"SUPublicDSAKey"];
        updatePublicDSAKey = [key retain];
    }

    return [[updatePublicDSAKey copy] autorelease];
}

-(NSString *) ipCheckURLString {

    // Info.plist IPCheckURL value, which may be overridden by a forced preference

    if (  ! ipCheckURLString  ) {
        NSString * urlString = [self infoPlistStringOrPreferenceString: @"IPCheckURL"];
        ipCheckURLString = [urlString retain];
        [self crashIfNotAValidURL: urlString];
    }

    return [[ipCheckURLString copy] autorelease];
}

-(NSArray *) allOpenvpnOpenssslVersions {

    if (  ! allOpenvpnOpenssslVersions ) {

        NSMutableArray * versions = [[NSMutableArray alloc] initWithCapacity: 6];

        NSString * openvpnFolderPath = [self.appPath stringByAppendingPathComponent:
                                        @"Contents/Resources/openvpn"];
        NSDirectoryEnumerator * dirE = [gFileMgr enumeratorAtPath: openvpnFolderPath];
        NSString * name = nil;
        while (  (name = [dirE nextObject])  ) {
            if (  ! [name isEqualToString: @"default"]  ) {
                [dirE skipDescendants];
                [versions addObject: name];
            }
        }

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

        NSArray * openvpnVersions = [self allOpenvpnOpenssslVersions];
        latestOpenvpnOpensslVersion = [[openvpnVersions lastObject] copy];
    }

    return [[latestOpenvpnOpensslVersion copy] autorelease];
}

-(void) getSystemVersionMajor: (unsigned *) major
                        minor: (unsigned *) minor
                       bugFix: (unsigned *) bugFix {

    OSStatus status = getSystemVersion(major, minor, bugFix);
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"ERROR: Could not get macOS version info");
        [gMC terminateBecause: terminatingBecauseOfError];
    }
}


-(NSString *) systemVersionString {

    if (  ! systemVersionString  ) {

        unsigned major, minor, bugfix;

        [self getSystemVersionMajor: &major
                              minor: &minor
                             bugFix: &bugfix];

        NSString * versionString = [NSString stringWithFormat:@"%d.%d.%d", major, minor, bugfix];

        systemVersionString = [versionString copy];
    }

    return [[systemVersionString copy] autorelease];
}

-(BOOL) isSystemVersionAtLeastMajor: (unsigned) major
                              minor: (unsigned) minor
                             bugfix: (unsigned) bugfix {

    unsigned systemMajor, systemMinor, SystemBugfix;

    getSystemVersion(&systemMajor, &systemMinor, &SystemBugfix);

    if (  major > systemMajor) {
        return YES;
    }
    if (  major < systemMajor) {
        return NO;
    }
    if (  minor >systemMinor) {
        return YES;
    }
    if (  minor < systemMinor) {
        return NO;
    }
    if (  bugfix >= systemMajor) {
        return YES;
    }
    
    return NO;
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
