/*
 * Copyright 2024 Jonathan K. Bullard. All rights reserved.
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

// Tunnelblick is updated in three phases:
//
// Phase 1 is done by Tunnelblick, primarily in the TBUpdater class. It:
//
//  * Interprets all user interaction;
//  * Obtains update info from tunnelblick.net;
//  * Downloads a .zip of an update. Depending on preferences, the .zip may be downloaded
//    immediately when available, or later, when a user or admin authorizes the update.;
//  * Gets user or admin authorization to update;
//  * Invokes PHASE 2 using installer or openvpnstart/tunnelblickd.
//
// PHASE 2 IS DONE BY THE updateTunnelblick() ROUTINE IN THIS FILE.
//
// The routine must run as root, either in installer or in tunnelblick-helper. It:
//
//  * Copies the .zip to /Library/Application Support/Tunnelblick/Tunnelblick.zip so it is owned by root:wheel and is secure;
//  * Verifies the signature of the .zip;
//  * Expands the .zip into /Library/Application Support/Tunnelblick/Tunnelblick.app;
//    so that the .app and everything within it is owned by root:wheel;
//  * Verifies that the .app has reasonable ownership and permissions
//    (i.e. everything owned by root:wheel, nothing with "other" write;
//  * Verifies that the .app is signed properly;
//  * Verifies that the .app is the specified version;
//  * Renames it to L_AS_T/Tunnelblick-new.app;
//  * Copies THIS app's TunnelblickUpdateHelper program into /Library/Application Support/Tunnelblick;
//  * Starts it as root;
//  * Returns indicating success (TRUE) or failure (FALSE), having output
//    appropriate error messages through appendLog().
//
// Phase 3 is done by the TunnelblickUpdateHelper program copied into /Library/Application Support/Tunnelblick by phase 2. It:
//
//  * Waits until there is no process named "Tunnelblick" running
//    (terminating any Tunnelblick launched by any other user);
//  * Moves /Applications/Tunnelblick.app to L_AS_T/Tunnelblick-old.app
//    (replacing any existing Tunnelblick-old.app);
//  * Renames /Library/Application Support/Tunnelblick/Tunnelblick-new.app to Tunnelblick.app
//  * Copies /Library/Application Support/Tunnelblick/Tunnelblick.app to /Applications;
//  * If necessary, runs THAT .app's installer as root to update tunnelblickd.plist
//    so Tunnelblick is ready to be launched;
//  * Launches the updated /Applications/Tunnelblick.app;
//  * Exits.

#import "TBUpdaterShared.h"

#import <CommonCrypto/CommonDigest.h>
#import <sys/stat.h>
#import "defines.h"
#import "sharedRoutines.h"

#import "NSFileManager+TB.h"
#import "NSString+TB.h"
#import "TBValidator.h"


void appendLog(NSString * s);

@interface UpdaterSharedLoggerBridge : NSObject
@end

@implementation UpdaterSharedLoggerBridge

// This method is used to log messages from the TBValidator

-(void) appendLog: (NSString *) message {

    appendLog(message);
}
@end


static BOOL copyInsecureZipToSecureZip(NSString * inPath, NSString * outPath) {

    if (  ! [[NSFileManager defaultManager] tbRemovePathIfItExists: outPath]  ) {
        return NO;
    }

    if (  ! [[NSFileManager defaultManager] tbCopyItemAtPath: inPath toBeOwnedByRootWheelAtPath: outPath]  ) {
        return NO;
    }

    appendLog(@"updateTunnelblick: Copied the .zip");
    return YES;
}

static NSDictionary * infoPlistForThisApp(void) {

    NSString * bundlePath = [[NSBundle mainBundle] bundlePath];
    // If invoked from installer
    // Then bundlePath will end in Tunnelblick.app/Contents/Resources so we remove "/Contents/Resources"
    if (  [bundlePath hasSuffix: @"Resources"]  ) {
        bundlePath = [[bundlePath stringByDeletingLastPathComponent]
                      stringByDeletingLastPathComponent];
    }
    NSString * infoPlistPath = [[bundlePath
                                 stringByAppendingPathComponent: @"Contents"]
                                stringByAppendingPathComponent: @"Info.plist"];
    if (  ! infoPlistPath  ) {
        appendLog(@"infoPlistForThisApp: Could not get path for Info.plist");
    }
    NSURL * url = [NSURL fileURLWithPath: infoPlistPath];
    if (  ! url  ) {
        appendLog([NSString stringWithFormat:
                   @"infoPlistForThisApp: Could not get url from %@",
                   infoPlistPath]);
   }
    NSDictionary * infoPlist = [NSDictionary dictionaryWithContentsOfURL: url];
    if (  ! infoPlist  ) {
        appendLog([NSString stringWithFormat:
                   @"infoPlistForThisApp: Could not get dictionary from %@",
                   infoPlistPath]);
    }
    return  infoPlist;
}

static BOOL verifySecureZipSignature(NSString * path, NSString * signature) {

    NSData * data = [[[NSData alloc] initWithContentsOfFile: path] autorelease];
    if (  ! data  ) {
        appendLog([NSString stringWithFormat:
                   @"verifySecureZipSignature: Could not get data from %@",
                   path]);
        return false;
    }

    NSDictionary * infoPlistDict = infoPlistForThisApp();
    NSString * publicKey = [infoPlistDict objectForKey: @"SUPublicDSAKey"];
    if (  ! publicKey  ) {
        appendLog([NSString stringWithFormat:
                   @"verifySecureZipSignature: Could not get public key for this app; dictionary was %@",
                   infoPlistDict]);
        return false;
    }

    UpdaterSharedLoggerBridge * uslb = [[[UpdaterSharedLoggerBridge alloc] init] autorelease];
    TBValidator * validator = [[[TBValidator alloc] initWithLogger: uslb] autorelease];

    BOOL result = [validator validateUpdateData: data
                                  withSignature: signature
                               withPublicDSAKey: publicKey];
    return result;
}

static BOOL checkSecureZipHasValidPaths(NSString * inPath) {

    // Returns TRUE iff all items in the .zip begin with "Tunnelblick.app/"
    // and no files in the .zip have paths that start with a "/" or contain ".."

    NSString * stdOut = nil;
    NSString * stdErr = nil;

    NSArray * arguments = @[@"-t",
                            @"--file", inPath];
    if (  EXIT_SUCCESS != runTool(TOOL_PATH_FOR_TAR, arguments, &stdOut, &stdErr)  ) {
        appendLog([NSString stringWithFormat:
                   @"checkSecureZipHasValidPaths: Cannot check '%@'; stderr = '\n%@'\nstdout = '\n%@'",
                   inPath, stdErr, stdOut]);
        return FALSE;
    }

    // Make sure each filename starts with "Tunnelblick.app/"
    NSArray * filenameList = [stdOut componentsSeparatedByString:@"\n"];
    NSEnumerator * e = [filenameList objectEnumerator];
    NSString * filename;
    while (   (filename = [e nextObject])  ) {
        if (  filename.length != 0  ) {
            if (  ! [filename hasPrefix: @"Tunnelblick.app/"]  ) {
                appendLog([NSString stringWithFormat:
                           @"checkSecureZipHasValidPaths: .zip '%@' is malformed ('%@' does not start with 'Tunnelblick.app/'; File list (stdout) = '\n%@'",
                           inPath, filename, stdOut]);
                return FALSE;
            }
        }
    }

    if (  [stdOut rangeOfString: @".."].length != 0  ) {
        appendLog([NSString stringWithFormat:
                   @"checkSecureZipHasValidPaths: .zip '%@' is malformed (contains '..'; File list (stdout) = '\n%@'",
                   inPath, stdOut]);
        return FALSE;
    }

    appendLog(@"checkSecureZipHasValidPaths: Checked secured .zip for bad paths");
    return TRUE;
}

static BOOL expandSecureZip(NSString * inPath, NSString * outPath) {

    if ( ! [[NSFileManager defaultManager] tbRemovePathIfItExists: outPath]) {
        appendLog([NSString stringWithFormat:
                   @"expandSecureZip: Could not delete existing expanded app at %@",
                  outPath]);
        return FALSE;
    }

    NSArray * arguments = @[@"-x",
                            @"--no-same-owner",
                            @"--keep-old-files",
                            @"--cd",   [outPath stringByDeletingLastPathComponent],
                            @"--file", inPath];
    if (  EXIT_SUCCESS != runTool(TOOL_PATH_FOR_TAR, arguments, nil, nil)  ) {
        appendLog([NSString stringWithFormat:
                   @"expandSecureZip: Cannot expand '%@'",
                   inPath]);
        return FALSE;
    }

    appendLog(@"updateTunnelblick: Expanded secured .zip");
    return TRUE;
}
 
static BOOL deleteSecureZip(NSString * path) {

    if (  [[NSFileManager defaultManager] tbRemoveFileAtPath: path handler: nil]  ) {
        appendLog(@"updateTunnelblick: Deleted secured .zip");
        return TRUE;
    }

    return FALSE;
}

static BOOL verifyReasonableOwnershipAndPermissionsOfOneItem(NSString * path) {

    // Returns YES if item at path is owned by root:wheel or root:admin and "other"
    // does not have any write permission for it.

    NSDictionary * fileAttributes = [[NSFileManager defaultManager] tbFileAttributesAtPath: path traverseLink: NO];
    if (  ! fileAttributes  ) {
        appendLog([NSString stringWithFormat: @"Cannot get attributes of item at '%@'", path]);
        return NO;
    }

    unsigned long perms = [fileAttributes filePosixPermissions];
    NSNumber *fileOwner = [fileAttributes fileOwnerAccountID];
    NSNumber *fileGroup = [fileAttributes fileGroupOwnerAccountID];
    NSNumber *fileHardLinks = [fileAttributes objectForKey: NSFileReferenceCount];

    if (   ( 0 == (perms & 0022) )
        //        && [fileHardLinks isEqualToNumber: @1]
        && [fileOwner isEqualToNumber:     @0]
        && (   [fileGroup isEqualToNumber: @0]
            || [fileGroup isEqualToNumber: @ADMIN_GROUP_ID])) {
        return YES;
    }

    appendLog([NSString stringWithFormat: @"Insecure item at '%@'; owned by %@:%@; permissions = 0%3lo; %@ hard links",
               path, fileOwner, fileGroup, perms, fileHardLinks]);
    return NO;
}

static BOOL verifyReasonableOwnershipAndPermissionsOfItemAndItsParents(NSString * path) {

    // Returns YES if all a path and all parent folders of the path are owned by root:wheel or
    // root:admin and "other" does not have any write permissions.

    NSArray * arr = [path componentsSeparatedByString: @"/"];
    NSEnumerator * e = [arr objectEnumerator];
    NSString * item;
    NSString * last = @"/";
    while (  (item = [e nextObject])  ) {
        if (  item.length != 0  ) {
            item = [last stringByAppendingPathComponent: item];
            last = item;
            if (  ! verifyReasonableOwnershipAndPermissionsOfOneItem(item)  ) {
                return NO;
            }
        }
    }

    return YES;
}

static BOOL verifyReasonableOwnershipAndPermissions(NSString * path) {

    // Returns YES if the path, its parent folders, and its contents if it is a directory
    // are owned by root:wheel or root:admin and "other" does not have any write permissions.

    if (  ! verifyReasonableOwnershipAndPermissionsOfItemAndItsParents(path)  ) {
        return NO;
    }

    NSDirectoryEnumerator * dirE = [[NSFileManager defaultManager] enumeratorAtPath: path];
    NSString * filename;
    while (  (filename = [dirE nextObject])  ) {
        NSString * fullPath = [path stringByAppendingPathComponent: filename];
        if (  ! verifyReasonableOwnershipAndPermissionsOfOneItem(fullPath)  ) {
            return NO;
        }
    }

    appendLog(@"updateTunnelblick: Verified ownership and permissions of .app");
    return YES;
}

static NSString * teamIdentifierAtPath(NSString * path) {

    NSURL * url = [NSURL fileURLWithPath: path];
    if (  ! url  ) {
        appendLog([NSString stringWithFormat:
                   @"teamIdentifierAtPath: Could not create URL from path '%@'",
                   path]);
        return nil;
    }

    SecStaticCodeRef staticCode = NULL;
    OSStatus staticCodeResult = SecStaticCodeCreateWithPath((CFURLRef)url, kSecCSDefaultFlags, &staticCode);
    if (  staticCodeResult != noErr  ) {
        appendLog([NSString stringWithFormat:
                   @"teamIdentifierAtPath: Error %d getting static code",
                   staticCodeResult]);
        if (  staticCode  ) {
            CFRelease(staticCode);
        }
        return nil;
    }

    if (  ! staticCode  ) {
        appendLog(@"teamIdentifierAtPath: noErr was returned, but staticCode was not created");
        return nil;
    }

    CFDictionaryRef cfSigningInfo = NULL;
    OSStatus copySigningInfoCode = SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation, &cfSigningInfo);
    if (  copySigningInfoCode == noErr) {
        CFStringRef cfTeamIdentifier = CFDictionaryGetValue(cfSigningInfo, kSecCodeInfoTeamIdentifier);
        NSString * teamIdentifier = [[[NSString alloc] initWithString: (NSString *)cfTeamIdentifier] autorelease];
        
        if (  cfSigningInfo  ) {
            CFRelease(cfSigningInfo);
        }
        CFRelease(staticCode);

        return teamIdentifier;
    }

    if (  cfSigningInfo  ) {
        CFRelease(cfSigningInfo);
    }

    CFRelease(staticCode);

    appendLog([NSString stringWithFormat:
               @"teamIdentifierAtPath: Error %d copying signing information",
               copySigningInfoCode]);
    return nil;
}

static BOOL verifyCodesignSignature(NSString * path) {

    // Returns YES if the item at path has a valid signature

    if (  ! itemHasValidSignature(path, YES)  ) {
        return  NO;
    }

    appendLog(@"updateTunnelblick: Verified the application signature");
    return YES;
}

static BOOL teamIDsMatch(NSString * path1, NSString * path2) {

    // Returns YES if the items at path1 and path2 are both signed by the same TeamID
    //
    // Assumes both items signatures have already been verified.

    NSString * teamID1  = teamIdentifierAtPath(path1);
    NSString * teamID2  = teamIdentifierAtPath(path2);
    if (   ( ! teamID1 )
        || ( ! teamID2)
        || ( ! [teamID1 isEqualToString: teamID2] )  ) {
        appendLog([NSString stringWithFormat:
                   @"updateTunnelblick: Code signature Team IDs do not match: '%@' and '%@'", teamID1, teamID2]);
        return NO;
    }

    appendLog(@"updateTunnelblick: Verified the code signature Team IDs match");
    return YES;
}

static BOOL verifyVersionAndBuild(NSString * path, NSString * versionBuildString) {

    NSString * plistPath = [[path
                             stringByAppendingPathComponent: @"Contents"]
                            stringByAppendingPathComponent: @"Info.plist"];
    NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: plistPath];
    if (  ! dict  ) {
        appendLog([NSString stringWithFormat: @"verifyVersionAndBuild: Cannot read %@", plistPath]);
        return NO;
    }

    NSString * appVersionBuildString = [dict objectForKey: @"CFBundleShortVersionString"];
    if (  ! appVersionBuildString  ) {
        appendLog([NSString stringWithFormat: @"verifyVersionAndBuild: Cannot get CFBundleShortVersionString from %@", plistPath]);
        return NO;
    }

    if (  ! [appVersionBuildString isEqualToString: versionBuildString]  ) {
        appendLog([NSString stringWithFormat: @"verifyVersionAndBuild: Expected '%@' but have '%@' in %@", versionBuildString, appVersionBuildString, path]);
        return NO;
    }

    appendLog(@"updateTunnelblick: Verified the application version and build");
    return YES;
}

static NSString * buildFromInfoPlistInApp(NSString * path) {

    NSString * plistPath = [[path
                             stringByAppendingPathComponent: @"Contents"]
                            stringByAppendingPathComponent: @"Info.plist"];
    NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: plistPath];
    if (  ! dict  ) {
        appendLog([NSString stringWithFormat: @"buildFromInfoPlistInAppAtPath: Cannot read %@", plistPath]);
        return nil;
    }

    NSString * appVersionBuildString = [dict objectForKey: @"CFBundleVersion"];
    if (  ! appVersionBuildString  ) {
        appendLog([NSString stringWithFormat: @"buildFromInfoPlistInAppAtPath: Cannot get CFBundleVersion from %@", plistPath]);
        return nil;
    }

    return appVersionBuildString;
}

static BOOL verifyNotDowngrading(NSString * updatePath) {

    NSDictionary * infoPlist = infoPlistForThisApp();
    NSString * existingBuild = [infoPlist objectForKey: @"CFBundleVersion"];

    NSString * updateBuild = buildFromInfoPlistInApp(updatePath);

    if (   existingBuild
        && updateBuild  ) {
        if (  [updateBuild caseInsensitiveNumericCompare: existingBuild]  != NSOrderedDescending  ) {
            appendLog([NSString stringWithFormat: @"verifyNotADowngrade: Downgrades are not allowed (from build %@ to build %@)", existingBuild, updateBuild]);
            return NO;
        }
        appendLog(@"updateTunnelblick: Verified not a downgrade");
        return YES;
    }

    return NO;
}

static BOOL moveApp(NSString * path, NSString * newPath) {

    if (  ! [[NSFileManager defaultManager] tbRemovePathIfItExists: newPath]  ) {
        return NO;
    }

    if (  ! [[NSFileManager defaultManager] tbForceRenamePath: path toPath: newPath]  ) {
        return NO;
    }

    appendLog([NSString stringWithFormat:
               @"updateTunnelblick: Moved the application to %@",
              newPath]);
    return YES;
}

static BOOL copyUpdaterProgram(void) {

    NSString * sourcePath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"TunnelblickUpdateHelper"];
    NSString * targetPath = [L_AS_T stringByAppendingPathComponent: @"TunnelblickUpdateHelper"];
    NSError * err;

    if (  ! [[NSFileManager defaultManager] tbRemovePathIfItExists: targetPath]  ) {
        return NO;
    }

    if (  ! [[NSFileManager defaultManager] copyItemAtPath: sourcePath
                                                    toPath: targetPath
                                                     error: &err]  ) {
        appendLog([NSString stringWithFormat: @"Failed to copy %@ to %@; error was %@", sourcePath, targetPath, err]);
        return NO;
    }

    appendLog([NSString stringWithFormat:
               @"updateTunnelblick: Copied %@ into %@",
               [sourcePath lastPathComponent], [targetPath stringByDeletingLastPathComponent]]);
    return YES;
}

static BOOL launchUpdaterProgramAsRoot(uid_t uid, gid_t gid, pid_t pid) {

    NSString * uidString = [NSString stringWithFormat: @"%u", uid];
    NSString * gidString = [NSString stringWithFormat: @"%u", gid];
    NSString * tunnelblickPidString = [NSString stringWithFormat: @"%u", pid];

    if ( 0 != setuid(0)  ) {
        appendLog([NSString stringWithFormat: @"launchUpdaterProgramAsRoot: failed to setuid(0); getuid() = %u; geteuid() = %u; getgid() = %u; getegid() = %u; uidString = '%@'; gidString = '%@'; tunnelblickPidString = '%@'",
                   getuid(), geteuid(), getgid(), getegid(), uidString, gidString, tunnelblickPidString]);
        return NO;
    }

    if ( 0 != setgid(0)  ) {
        appendLog([NSString stringWithFormat: @"launchUpdaterProgramAsRoot: failed to setgid(0); getuid() = %u; geteuid() = %u; getgid() = %u; getegid() = %u; uidString = '%@'; gidString = '%@'; tunnelblickPidString = '%@'",
                   getuid(), geteuid(), getgid(), getegid(), uidString, gidString, tunnelblickPidString]);
        return NO;
    }

    NSString * path = [L_AS_T stringByAppendingPathComponent: @"TunnelblickUpdateHelper"];

    if (  ! startTool(path, @[uidString, gidString, tunnelblickPidString])  ) {
        appendLog([NSString stringWithFormat: @"Failed to create task to launch %@", path]);
        return NO;
    }

    appendLog([NSString stringWithFormat: @"updateTunnelblick: Launched %@", [path lastPathComponent]]);
    return YES;
}

BOOL updateTunnelblick(NSString * insecureZipPath, NSString * updateSignature, NSString * versionBuildString, uid_t uid, gid_t gid, pid_t tunnelblickPid) {

    // THIS ROUTINE PERFORMS THE SECOND PHASE of updating the Tunnelblick .app.
    //
    // It returns TRUE if it succeeded, or FALSE if it fails (having output an error message)

    appendLog([NSString stringWithFormat:
               @"Entered updateTunnelblick():\n"
               @"     zipPath   = '%@'\n"
               @"     signature = '%@'\n"
               @"     version   = '%@'\n"
               @"     uid       = %u\n"
               @"     gid       = %u\n"
               @"     TB pid    = %u",
               insecureZipPath, updateSignature, versionBuildString, uid, gid, tunnelblickPid]);

    NSString * secureZipPath = [L_AS_T stringByAppendingPathComponent: @"Tunnelblick.zip"];

    NSString * secureUpdatedAppPath = [L_AS_T stringByAppendingPathComponent: @"Tunnelblick.app"];

    if (  ! [[NSFileManager defaultManager] tbRemovePathIfItExists: secureZipPath]  ) {
        return FALSE;
    }

    if (  ! copyInsecureZipToSecureZip(insecureZipPath, secureZipPath)  ) {
        return FALSE;
    }

    // The .zip was downloaded from tunnelblick.net using https:, so it should be valid.
    //
    // Usually, we require that it's DSA signature is valid, too,
    // AND we require that the .app was codesigned with the same Team ID that signed the current .app
    //
    // But if the "updateRelaxForgeryRule" preference is forced, we allow an update if either one of those
    // requirements is met:
    //      If the update .zip signature verifies and the .app is codesigned (by _any_ team ID),
    //      Or the update .zip signature did not verify and the .app was codesigned with the same Team ID that codesigned /Applications/Tunnelblick.app.
    //
    // This allows changing the public key or changing the codesigning team ID in an update.
    //
    // BUT it also allows forgeries if either the public key or the codesigning key is compromised.
    //
    // If the preference is not forced
    //      * Both the public key and the codesigning team ID must be compromised to successfully forge an update.
    //      * Neither the public key nor the codesigning team ID can be changed.

    id relaxForgeryRuleObj = [[NSDictionary dictionaryWithContentsOfFile: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH] objectForKey: @"updateRelaxForgeryRule"];
    BOOL relaxForgeryRule = (  [[relaxForgeryRuleObj class] isSubclassOfClass: [NSNumber class]]
                             ? ((NSNumber *)relaxForgeryRuleObj).boolValue
                             : NO);

    BOOL secureZipSignatureVerified = verifySecureZipSignature(secureZipPath, updateSignature);

    if (  secureZipSignatureVerified  ) {
        appendLog(@"updateTunnelblick: The .zip signature was verified");
    } else {
        if (  relaxForgeryRule  ) {
            appendLog(@"updateTunnelblick: The .zip signature was not verified but the 'updateRelaxForgeryRule' preference has been forced, so continuing");
        } else {
            appendLog(@"updateTunnelblick: The .zip signature was not verified and the 'updateRelaxForgeryRule' preference has not been forced, so the update is rejected");
            return FALSE;
        }
    }

    // Either the .zip signature was verified, or we are using the relaxed forgery rule, or both

        if (  ! [[NSFileManager defaultManager] tbRemovePathIfItExists: secureUpdatedAppPath]  ) {
            return FALSE;
        }

        if (  ! checkSecureZipHasValidPaths(secureZipPath)  ) {
            return FALSE;
        }

        if (  ! expandSecureZip(secureZipPath, secureUpdatedAppPath)  ) {
            return FALSE;
        }

        if (  ! deleteSecureZip(secureZipPath)  ) {
            return FALSE;
        }

        if (  ! verifyReasonableOwnershipAndPermissions(secureUpdatedAppPath)  ) {
            return FALSE;
        }

        if (  ! verifyCodesignSignature(secureUpdatedAppPath)  ) {
            return FALSE;
        }

    if (  teamIDsMatch(secureUpdatedAppPath, APPLICATIONS_TB_APP)  ) {
        if (  ! secureZipSignatureVerified  ) {
            appendLog(@"updateTunnelblick: The 'updateRelaxForgeryRule' preference has been forced, so the update is accepted");
        }
    } else {
        if (  secureZipSignatureVerified  ) {
            if (  relaxForgeryRule  ) {
                appendLog(@"updateTunnelblick: The 'updateRelaxForgeryRule' preference has been forced, so the update is accepted");
            } else {
                appendLog(@"updateTunnelblick: The 'updateRelaxForgeryRule' preference has not been forced, so the update is rejected");
                return FALSE;
            }
        } else {
            appendLog(@"updateTunnelblick: The update DSA signature was not valid and the 'updateRelaxForgeryRule' preference has not been forced, so the update is rejected");
            return FALSE;
        }
    }

    if (  ! verifyVersionAndBuild(secureUpdatedAppPath, versionBuildString)  ) {
        return FALSE;
    }

    if (  ! verifyNotDowngrading(secureUpdatedAppPath)  ) {
        return FALSE;
    }

    if (  ! moveApp(secureUpdatedAppPath, L_AS_T_TB_NEW)  ) {
        return FALSE;
    }

    if (  ! copyUpdaterProgram()  ) {
        return FALSE;
    }

    if (  ! launchUpdaterProgramAsRoot(uid, gid, tunnelblickPid)  ) {
        return FALSE;
    }

    appendLog(@"updateTunnelblick: Completed PHASE 2 of the update process");
    return TRUE;
}

