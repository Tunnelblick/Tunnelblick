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

// Provides a class method to do processing in the background after
// Tunnelblick has been launched.



#import "PostLaunch.h"

#import "ConfigurationManager.h"
#import "helper.h"
#import "MenuController.h"
#import "NSDate+TB.h"
#import "NSFileManager+TB.h"
#import "NSString+TB.h"
#import "sharedRoutines.h"
#import "TBUserDefaults.h"
#import "TunnelblickInfo.h"
#import "VPNConnection.h"

extern NSFileManager   * gFileMgr;
extern MenuController  * gMC;
extern TBUserDefaults  * gTbDefaults;
extern TunnelblickInfo * gTbInfo;


@implementation PostLaunch

-(PostLaunch *) init {

    self = [super init];
    if ( ! self  ) {
        return nil;
    }

    return self;

}

-(void) dealloc {

    [super dealloc];
}

-(void) doPostLaunchProcessing {

    @autoreleasepool {

        [self warnIfOnSystemStartConfigurationsAreNotConnected];

        [self askAboutSendingCrashReports];

        [self displayMessageAboutRosetta];

        [self displayMessagesAboutOpenSSL_1_1_1];

        [self displayMessagesAboutKextsAndBigSur];

        [self pruneTracesFolder];

    }
}

-(void) warnIfOnSystemStartConfigurationsAreNotConnected {

    // Create a list of configurations that should be connected when the system starts but aren't connected

    NSMutableString * badConfigurations = [[[NSMutableString alloc] initWithCapacity: 1000] autorelease];

    NSEnumerator * e = [gMC.myVPNConnectionDictionary objectEnumerator];
    VPNConnection * conn;
    while (  (conn = [e nextObject])  ) {
        NSString * name = [conn displayName];
        if (   [gTbDefaults boolForKey: [name stringByAppendingString: @"-onSystemStart"]]
            && [gTbDefaults boolForKey: [name stringByAppendingString: @"autoConnect"]]
            && [[conn state] isNotEqualTo: @"CONNECTED"]  ) {
            [badConfigurations appendFormat: @"     %@\n", name];
        }
    }

    if (  [badConfigurations length] != 0  ) {
        TBShowAlertWindowExtended(@"Tunnelblick",
                                  [NSString stringWithFormat:
                                   NSLocalizedString(@"Warning: The following configurations, which should connect when the computer starts, are not connected:\n\n%@\n",
                                                     @"Window text. The %@ will be replaced with a list of the names of configurations, one per line"),
                                   badConfigurations],
                                  @"skipWarningAboutWhenSystemStartsConfigurationsThatAreNotConnected", nil, nil, nil, nil, NO);
    }
}

-(void) askAboutSendingCrashReports {

    NSArray * paths = [self tunnelblickCrashReportPaths];
    if (  paths.count !=  0  ) {

        // Limit to requesting an email from the user to once every 24 hours

        NSDate * lastRequestDate = [gTbDefaults dateForKey: @"dateLastRequestedEmailCrashReports"];
        if (  lastRequestDate  ) {
            NSDate * nextRequestDate = [lastRequestDate dateByAddingTimeInterval: SECONDS_PER_DAY];
            NSComparisonResult result = [[NSDate date] compare: nextRequestDate];
            if (  result == NSOrderedAscending  ) {
                return;
            }
        }

        [gTbDefaults setObject: [NSDate date] forKey: @"dateLastRequestedEmailCrashReports"];

        [self writeCrashReportsTarGzToTheDesktop: paths];
        [self performSelectorOnMainThread: @selector(askAboutSendingCrashReportsOnMainThread) withObject: nil waitUntilDone: NO];
    }
}

    -(NSArray *) tunnelblickCrashReportPaths {

        NSMutableArray * crashReportPaths = [[[NSMutableArray alloc] initWithCapacity: 10] autorelease];

        NSString * reportsPath = [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Logs/DiagnosticReports"];
        NSDirectoryEnumerator * dirE = [gFileMgr enumeratorAtPath: reportsPath];
        NSString * file;
        while (  (file = [dirE nextObject])  ) {
            [dirE skipDescendants];
            if (   [file containsString: @"Tunnelblick"]  ) {
                [crashReportPaths addObject: [reportsPath stringByAppendingPathComponent: file]];
            }
        }

        return crashReportPaths;
    }

    -(void) writeCrashReportsTarGzToTheDesktop: (NSArray *) paths {

        NSString * tarGzPath = [NSHomeDirectory() stringByAppendingPathComponent: @"Desktop/Tunnelblick Error Data.tar.gz"];

        // Remove the output file if it already exists
        // (We do this so user doesn't do something with it before we're finished).
        if (  ! [gFileMgr tbRemovePathIfItExists: tarGzPath]  ) {
            return;
        }

        // Create a temporary folder, and a folder within that to hold the crash files
        NSString * temporaryDirectoryPath = [newTemporaryDirectoryPath() autorelease];
        NSString * tunnelblickErrorDataFolderPath = [temporaryDirectoryPath stringByAppendingPathComponent: @"Tunnelblick Error Data"];
        if (  ! [gFileMgr createDirectoryAtPath: tunnelblickErrorDataFolderPath withIntermediateDirectories: NO attributes: nil error: nil] ) {
            NSLog(@"Unable to create folder to contain crash reports at %@", tunnelblickErrorDataFolderPath);
            return;
        }

        // Copy some of the crash reports
        NSUInteger maxCrashReportsToSend = 10;
        NSEnumerator * e = [paths objectEnumerator];
        NSString * path;
        while (  (path = [e nextObject])  ) {
            NSString * targetPath = [tunnelblickErrorDataFolderPath stringByAppendingPathComponent: [path lastPathComponent]];
            if (  ! [gFileMgr tbCopyPath: path toPath: targetPath handler: nil]  ) {
                NSLog(@"Unable to copy crash report %@ to %@", path, targetPath);
                return;
            }
            if (  --maxCrashReportsToSend == 0 ) {
                break;
            }
        }

        // Create a file with the trace logs
        NSString * traceLogPath = [tunnelblickErrorDataFolderPath stringByAppendingPathComponent: @"TBTrace.log"];
        NSString * traceLog = dumpTraces();
        if (  ! [traceLog writeToFile: traceLogPath atomically: NO encoding: NSUTF8StringEncoding error: nil]  ) {
            NSLog(@"Error writing trace logs to %@", traceLogPath);
        }

        // Create the .tar.gz
        NSArray * arguments = @[@"-cz",
                                @"-f", tarGzPath,
                                @"-C", temporaryDirectoryPath,
                                @"--exclude", @".*",
                                [tunnelblickErrorDataFolderPath lastPathComponent]];
        if (  EXIT_SUCCESS != runToolExtended(TOOL_PATH_FOR_TAR, arguments, nil, nil, nil)  ) {
            NSLog(@"Unable to create .tar.gz of crash reports folder at %@", tunnelblickErrorDataFolderPath);
            return;
        }

        // Delete all of the crash reports (including those that are not sent because there are too many)
        e = [paths objectEnumerator];
        while (  (path = [e nextObject])  ) {
            if (  ! [gFileMgr tbRemoveFileAtPath: path handler: nil]  ) {
                NSLog(@"Unable to delete crash report at %@", path);
                return;
            }
        }

        // Delete the temporary folder
        if (  ! [gFileMgr tbRemoveFileAtPath: temporaryDirectoryPath handler: nil]  ) {
            NSLog(@"Unable to remove temporary folder for crash reports at %@", temporaryDirectoryPath);
        }
    }

    -(void) askAboutSendingCrashReportsOnMainThread {

        NSAttributedString * msg = attributedLightDarkStringFromHTML([NSString stringWithFormat:
                                                                    NSLocalizedString(@"<p>Recently Tunnelblick experienced one or more serious errors.</p>\n\n"
                                                                                        @"<p>Please email %@ and attach the<br>"
                                                                                        "'%@' file that has been created on your Desktop.</p>\n\n"
                                                                                        @"<p>The file contains information that will help the Tunnelblick developers fix the problems that cause such errors. It does not include personal information about you or information about your VPNs.</p>\n\n"
                                                                                        @"<p>If you can, please also describe what Tunnelblick was doing when the error happened.</p>\n\n"
                                                                                        @"<p>Your help in this will benefit all users of Tunnelblick.</p>",
                                                                                        @"Window text. The first '%@' will be replaced with an email address. The second '%@' will be replaced with the name of a file"),
                                                                    @"<a href=\"mailto:developers@tunnelblick.net\">developers@tunnelblick.net</a>",
                                                                    @"Tunnelblick Error Data.tar.gz"]);

        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick Error", @"Window title"),
                        msg);
    }

-(void) displayMessageAboutRosetta {

    if (  processIsTranslated()  ) {
        NSDictionary * dict = @{@"headline" : NSLocalizedString(@"Do not run using Rosetta...", @"Headline for warning"),
                                @"message"  : attributedLightDarkStringFromHTML(NSLocalizedString(@"<p>Tunnelblick should not be run using Rosetta.</p>\n"
                                @"<p>For more information, see <a href=\"https://tunnelblick.net/cUsingRosetta.html\">Tunnelblick and Rosetta</a> [tunnelblick.net].</p>",
                                @"HTML warning message")),
                                @"preferenceKey" : @"skipWarningAboutRosetta"};
        [gMC performSelectorOnMainThread: @selector(addWarningNote:) withObject: dict waitUntilDone: NO];
    }
}

-(void) displayMessagesAboutOpenSSL_1_1_1 {

    // Get a list of configurations that use OpenSSL 1.1.1.
    NSMutableArray * list = [[[NSMutableArray alloc] initWithCapacity: 100] autorelease];
    NSArray * displayNames = [[gMC.myVPNConnectionDictionary allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveNumericCompare:)];
    NSEnumerator * e = [displayNames objectEnumerator];
    NSString * displayName;
    while (  (displayName = [e nextObject])  ) {
        NSString * value = [gTbDefaults stringForKey: [displayName stringByAppendingString: @"-openvpnVersion"]];
        if (  [value containsString: @"-openssl-1.1.1"]  ) {
            [list addObject: displayName];
        }
    }

    if (  list.count == 0  ) {
        return;                 // Nothing to warn about
    }

    // Construct an HTML warning about the problematic configurations
    NSMutableString * html = [[[NSMutableString alloc] initWithCapacity: 1000] autorelease];

    // Header
    [html appendString: NSLocalizedString(@"<p>One or more VPN configurations use OpenVPN with OpenSSL 1.1.1, which contains\n"
                                          @"   known security vulnerabilities for which fixes are not publicly available.</p>\n"
                                          @"<p>We recommend that you update the following configuration(s) to\n"
                                          @"   use OpenVPN with a newer version of OpenSSL:</p>\n\n"
                                          @"<p>\n",
                                          @"HTML warning message")];

    // List of problematic configurations
    e = [list objectEnumerator];
    while (  (displayName = [e nextObject])  ) {
        [html appendFormat: @"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;%@<br>\n", displayName];
    }

    // Trailer
    [html appendString: NSLocalizedString(@"</p>\n"
                                          @"<p>For more information, see\n"
                                          @"   <a href=\"https://tunnelblick.net/cUsingOldVersionsOfOpenVPNOrOpenSSL.html\">Using\n"
                                          @"   Old Versions of OpenVPN or OpenSSL</a> [tunnelblick.net].</p>",
                                          @"HTML warning message")];

    // Add the warning
    NSDictionary * dict = @{@"headline" : NSLocalizedString(@"Insecure version of OpenSSL being used...", @"Headline for warning"),
                            @"message"  : attributedLightDarkStringFromHTML(html),
                            @"preferenceKey" : @"skipWarningAboutOpenSSL_1_1_1"};
    [gMC performSelectorOnMainThread: @selector(addWarningNote:) withObject: dict waitUntilDone: NO];
}

-(void) displayMessagesAboutKextsAndBigSur {

    BOOL alwaysLoadTap     = [self oneOrMoreConfigurationsHavePreferenceSetToAlwaysLoad: @"tap"];
    BOOL alwaysLoadTun     = [self oneOrMoreConfigurationsHavePreferenceSetToAlwaysLoad: @"tun"];
    BOOL configNeedsTap    = [self oneOrMoreConfigurationsMustLoad: @"tap"];
    BOOL configNeedsTun    = [self oneOrMoreConfigurationsMustLoad: @"tun"];

    [self displayMessageAboutBigSurAndKextsAlwaysLoadTap: alwaysLoadTap
                                           alwaysLoadTun: alwaysLoadTun
                                          configNeedsTap: configNeedsTap
                                          configNeedsTun: configNeedsTun];
}

    -(BOOL) oneOrMoreConfigurationsHavePreferenceSetToAlwaysLoad: (NSString * ) tapOrTun {

        NSString * preferenceSuffix = (  [tapOrTun isEqualToString: @"tun"]
                                       ? @"-loadTun"
                                       : @"-loadTap");

        NSArray * displayNames = [[gMC.myVPNConnectionDictionary allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveNumericCompare:)];
        NSEnumerator * e = [displayNames objectEnumerator];
        NSString * displayName;
        BOOL returnStatus = FALSE;
        while (  (displayName = [e nextObject])  ) {
            NSString * key = [displayName stringByAppendingString: preferenceSuffix];
            NSString * value = [gTbDefaults stringForKey: key];
            if (  [value isEqualToString: @"always"]  ) {
                NSLog(@"Configuration '%@' has a setting which requires the '%@' system extension to always be loaded when connecting", displayName, tapOrTun);
                returnStatus = TRUE;
            }
        }

        return returnStatus;
    }

    -(BOOL) oneOrMoreConfigurationsMustLoad: (NSString * ) tapOrTun {

        NSArray * displayNames = [[gMC.myVPNConnectionDictionary allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveNumericCompare:)];
        NSEnumerator * e = [displayNames objectEnumerator];
        NSString * displayName;
        BOOL returnStatus = FALSE;
        while (  (displayName = [e nextObject])  ) {
            VPNConnection * connection = [gMC.myVPNConnectionDictionary objectForKey: displayName];
            if (  [self mustLoad: tapOrTun forConnection: connection]  ) {
                NSLog(@"Configuration '%@' requires a '%@' system extension", [connection localizedName], tapOrTun);
                returnStatus = TRUE;
            }
        }

        return returnStatus;
    }

    -(BOOL) mustLoad: (NSString *)      requirement
       forConnection: (VPNConnection *) connection {

        // requirement must be "tun" or "tap". Returns true if the configuration requires the specified kext.

        if (   [connection.tapOrTun isEqualToString: requirement]  ) {
            return YES;
        }

        return NO;
    }

    -(void) displayMessageAboutBigSurAndKextsAlwaysLoadTap: (BOOL) alwaysLoadTap
                                             alwaysLoadTun: (BOOL) alwaysLoadTun
                                            configNeedsTap: (BOOL) configNeedsTap
                                            configNeedsTun: (BOOL) configNeedsTun {

        BOOL needtapOrTun = (   alwaysLoadTap
                             || alwaysLoadTun
                             || configNeedsTap
                             || configNeedsTun);

        NSString * willNotConnect = @"";
        NSString * fixWillNotConnect = @"";

        if (  needtapOrTun  ) {

            if (   ( ! gTbInfo.systemVersionCanLoadKexts )
                && ( ! [gTbDefaults boolForKey: @"tryToLoadKextsOnThisVersionOfMacOS"] )  ) {
                willNotConnect   = NSLocalizedString(@"<p><strong>One or more of your configurations will not be able to connect.</strong></p>\n"
                                                     @"<p>The configuration(s) require a system extension but this version of macOS does not allow Tunnelblick to use its system extensions.</p>\n",
                                                     @"HTML text. May be combined with other paragraphs.");

                fixWillNotConnect = NSLocalizedString(@"<p>You can set the 'tryToLoadKextsOnThisVersionOfMacOS' Tunnelblick preference so it will attempt to load its system extensions.</p>\n",
                                                      @"HTML text. May be combined with other paragraphs.");
            }

            NSString * futureNotConnect = NSLocalizedString(@"<p><strong>One or more of your configurations will not be able to connect</strong> on future versions of macOS.</p>\n"
                                                            @"<p>The configuration(s) require a system extension but future versions of macOS will not allow Tunnelblick to use its system extensions.</p>\n",
                                                            @"HTML text. May be combined with other paragraphs.");

            NSString * mayModify        = NSLocalizedString(@"<p><strong>You can modify the configurations so that they will be able to connect.</strong></p>\n",
                                                            @"HTML text. May be combined with other paragraphs.");

            NSString * seeConsoleLog    = NSLocalizedString(@"<p>The Console Log shows which configurations will not be able to connect.</p>\n",
                                                            @"HTML text. May be combined with other paragraphs.");

            NSString * futureInfo       = NSLocalizedString(@"<p>See <a href=\"https://tunnelblick.net/cTunTapConnections.html\">The Future of Tun and Tap VPNs on macOS</a> [tunnelblick.net] for more information.</p>\n",
                                                            @"HTML text. May be combined with other paragraphs.");

            NSMutableString * htmlMessage = [[[NSMutableString alloc] initWithCapacity: 1000] autorelease];
            NSString * preferenceName = nil; // Will replace with appropriate name for the message that is being displayed

            if (   ! gTbInfo.systemVersionCanLoadKexts
                && ( ! [gTbDefaults boolForKey: @"tryToLoadKextsOnThisVersionOfMacOS"] )  ) {
                [htmlMessage appendString: willNotConnect];
                [htmlMessage appendString: fixWillNotConnect];
                preferenceName = @"skipWarningAboutBigSur1";
            } else {
                [htmlMessage appendString: futureNotConnect];
                preferenceName = @"skipWarningAboutBigSur2";
            }

            if (  ! configNeedsTap  ) {
                [htmlMessage appendString: mayModify];
                preferenceName = [preferenceName stringByAppendingString: @"m"];
            }

            [htmlMessage appendString: seeConsoleLog];

            [htmlMessage appendString: futureInfo];

            NSDictionary * dict = @{@"headline" : NSLocalizedString(@"Problem using future versions of macOS...",
                                    @"Menu item. Translate it to be as short as possible. When clicked, will display the full warning."),
                                    @"message"  : attributedLightDarkStringFromHTML(htmlMessage),
                                    @"preferenceKey" : preferenceName};
            [gMC performSelectorOnMainThread: @selector(addWarningNote:) withObject: dict waitUntilDone: NO];
        }
    }

-(void) pruneTracesFolder {

    NSDate * oneDayAgo = [[NSDate date] dateByAddingTimeInterval: -SECONDS_PER_DAY];
    NSString * earliestAllowedFilenamePrefix = [[oneDayAgo tunnelblickUserLogRepresentationWithoutMicroseconds]
                                                substringWithRange: NSMakeRange(0, LENGTH_OF_YYYY_MM_DD)];

    NSString * folderPath = tracesFolderPath();
    NSArray * filenames = [gFileMgr contentsOfDirectoryAtPath: folderPath error: nil];
    NSEnumerator * e = [filenames objectEnumerator];
    NSString * filename;
    while (  filename = [e nextObject]  ) {
        if (  [[filename pathExtension] isEqualToString: @"log"]  ) {
            if (  [[filename lastPathComponent] compare: earliestAllowedFilenamePrefix] == NSOrderedAscending  ) {
                NSString * path = [folderPath stringByAppendingPathComponent: filename];
                if (  [gFileMgr tbRemoveFileAtPath: path handler: nil]  ) {
                    NSLog(@"Removed %@", path);
                }
            }
        }
    }
}


@end
