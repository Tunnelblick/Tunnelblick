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

#import "TBUpdater.h"

#import <CommonCrypto/CommonDigest.h>

#import "defines.h"
#import "helper.h"

#import "AlertWindowController.h"
#import "MenuController.h"
#import "NSDate+TB.h"
#import "NSFileManager+TB.h"
#import "NSString+TB.h"
#import "sharedRoutines.h"
#import "SystemAuth.h"
#import "TBDownloader.h"
#import "TBUserDefaults.h"
#import "TBValidator.h"
#import "TunnelblickInfo.h"

// The following external global variables are used by functions in this file and must be declared and set elsewhere before the
// functions in this file are called:
extern NSFileManager  * gFileMgr;
extern MenuController * gMC;
extern BOOL             gShuttingDownTunnelblick;
extern TBUserDefaults * gTbDefaults;
extern TunnelblickInfo * gTbInfo;

//********************************************************************************
//
// Methods this class invokes
//
//      For Tunnelblick.app updates: gMC (on the main thread)
//      For configuration upates, ????????:
//
//          -(void) tbUpdateErrorOccurredInAppUpdate: (NSNumber *) inAppUpdate; (use [inAppUpdate boolValue])
//
//          -(void) tbUpdateIsAvailable: (NSNumber *) isAvailable; (use [isAvailable boolValue])
//
//          -(void) tbUpdateDownloadCompletePercentage: (double) percentage;
//
//          -(void) tbUpdateWillInstallUpdate;
//
//          -(void) tbUpdateDidInstallUpdate;

//********************************************************************************
//
// Preferences this class uses:
//
//      updateCheckAutomatically                     (from checkbox)
//      updateCheckBetas                             (from checkbox)
//      updateCheckInterval                          (defaults to 24 hours, can set via preference)
//      updateFeedURL                                (must be forced)
//
//      TBUpdaterAllowNonAdminToUpdateTunnelblick    (from checkbox, must be forced)
//      TBUpdaterCheckOnlyWhenConnectedToVPN         (from checkbox)
//      TBUpdaterDownloadUpdateWhenAvailable         (from checkbox)
//
//      inhibitOutboundTunneblickTraffic             (from checkbox)
//
//      TBUpdateVersionStringForDownloadedAppUpdate  (used by this class to persist over Tunnelblick relaunches)
//
//
//      SUFeedURL                                    (from Info.plist)

@implementation TBUpdater

//********************************************************************************
//
// Methods in this class that are invoked by MenuController:

-(void) stopAllUpdateActivity {

    // Stop all updating activity, regardless of preferences,
    // usually when Tunnelblick is about to quit.

    [self appendUpdaterLog: @"stopAllUpdateActivity invoked"];

    if (  [NSThread mainThread]  ) {
        [self internalStopAllUpdateActivity];
    } else {
        [self performSelectorOnMainThread: @selector(internalStopAllUpdateActivity)
                               withObject: nil waitUntilDone: NO];
    }
}

-(void) nonAutomaticCheckIfAnUpdateIsAvailable {

    // Invoked to force an update check (even if **automatic** checks are not allowed).
    // Presumably triggered by a "Check now" button.
    // If an update is available
    // Then start downloading the update if that's allowed, invoke the delegate's
    //      tbUpdateIsAvailable: indicating an update is available, and display a non-modal
    //      window with details about the update and buttons for the user to act.
    // If no update is available, displays a non-modal window saying no update is available.

    if (  [NSThread mainThread]  ) {
        [self checkIfAnUpdateIsAvailableForcingCheck: @YES];
    } else {
        [self performSelectorOnMainThread: @selector(checkIfAnUpdateIsAvailableForcingCheck:)
                               withObject: @YES waitUntilDone: NO];
    }
}

-(void) updateSettingsHaveChanged {

    // The settings (preferences) that involve the TBUpdater have changed.
    // Triggers an automatic update check
    // If an update is available
    // Then start downloading the update if that's allowed, and invoke the delegate's
    //      tbUpdateIsAvailable: indicating an update is available.
    // If no update is available nothing is done.

    if (  [NSThread mainThread]  ) {
        [self internalUpdateSettingsHaveChanged];
    } else {
        [self performSelectorOnMainThread: @selector(internalUpdateSettingsHaveChanged)
                               withObject: nil waitUntilDone: NO];
    }
}

-(void) offerUpdateAndInstallIfUserAgrees {

    // Presents a dialog to the user with the current and proposed version info, the
    // update notes, and "Install" and "Skip This Update", and "Remind Me Later" buttons.
    //
    // Note: updating the application results in the termination of this instance
    // of the Tunnelblick application.

    [self appendUpdaterLog: @"offerUpdateAndInstallIfUserAgrees invoked"];

    if (  [NSThread mainThread]  ) {
        [self internalOfferUpdateAndInstallIfUserAgrees];
    } else {
        [self performSelectorOnMainThread: @selector(internalOfferUpdateAndInstallIfUserAgrees)
                               withObject: nil waitUntilDone: NO];
    }

}

//********************************************************************************
//
// dealloc, init, and logging

-(void) dealloc {

    // NOTE: IN THE SAME ORDER AS IN TBUpdater.h

    if (  logFile  ) {
        fclose(logFile);
    }

    [validator release];

    // (isAppUpdate is not an object)
    [appcastURLInInfoPlist release];
    [appcastPubKeyInInfoPlist release];
    [skipBuildPref release];
    [appcastURLPref release];
    [canDownloadUpdatesAutomaticallyPref release];
    [canCheckAutomaticallyPref release];
    [nonAdminCanUpdateAppPref release];
    [downloadedUpdateVersionStringPref release];
    [downloadedUpdatePath release];

    [delegate release];

    [updateInfo release];

    [currentTunnelblickVersionString release];
    [currentBuild release];
    [currentArchitecture release];
    [currentMacOSVersion release];

    [infoPlistDictionary release];

    [appcastURLString release];
    [publicKey release];

    [updateCheckTimer   invalidate];
    [updateCheckTimer   release];
    [debugLogFlushTimer invalidate];
    [debugLogFlushTimer release];

    // (updateErrorDelay is not an object)

    [windowController close];
    [windowController release];

    // (appcastDownloadIsForced is not an object)
    [appcastDownloader release];
    [appcastContents release];
    // (appcastLength is not an object)

    [updateDownloader release];
    [updateContents release];
    // (percentDownloaded is not an object)

    // Other class variables are all BOOLs, not objects

    [super dealloc];
}

-(TBUpdater *) initFor: (NSString *) _type
          withDelegate: (id)         _delegate {

    if (  (self = [super init])  ) {

        delegate = [_delegate retain];

        validator = [[TBValidator alloc] initWithLogger: self];

        // Set class variables for updating either the application or a configuration
        if (  [_type isEqualToString: @"application"] ) {
            isAppUpdate = TRUE;
            appcastURLInInfoPlist = @"SUFeedURL";
            appcastPubKeyInInfoPlist = @"SUPublicDSAKey";
            skipBuildPref = @"TBUpdaterSkipBuild";
            appcastURLPref = @"updateFeedURL";
            canDownloadUpdatesAutomaticallyPref = @"TBUpdaterDownloadUpdateWhenAvailable";
            canCheckAutomaticallyPref=@"updateCheckAutomatically";
            nonAdminCanUpdateAppPref = @"TBUpdaterAllowNonAdminToUpdateTunnelblick";
            downloadedUpdateVersionStringPref = @"TBUpdateVersionStringForDownloadedAppUpdate";
            downloadedUpdatePath = [TUNNELBLICK_UPDATER_ZIP_PATH retain];

        } else if (  [_type isEqualToString: @"configuration"] ) {
            isAppUpdate = FALSE;

            // TODO fill in downloadedUpdatePath, etc. variables
            [self appendUpdaterLog: @"initFor: argument must be 'application' or 'configuration'"];
            return nil;

        } else {
            [self appendUpdaterLog: @"initFor: argument must be 'application' or 'configuration'"];
            return nil;
        }

        [self openLog];

        [self removeObsoleteAppcastAndUpdateInfo];

        // If no URL string for the appcast, inhibit updates
        [self appcastURLString]; // Discard returned value

        [self setupUpdateCheckTimer];

        // Start an automatic update check if appropriate
        [self updateSettingsHaveChanged];
    }

    return self;
}

-(void) openLog {

    if (  [gFileMgr fileExistsAtPath: TUNNELBLICK_UPDATER_LOG_PATH]  ) {
        [gFileMgr tbRemovePathIfItExists: TUNNELBLICK_UPDATER_OLD_LOG_PATH];
        [gFileMgr tbMovePath: TUNNELBLICK_UPDATER_LOG_PATH toPath: TUNNELBLICK_UPDATER_OLD_LOG_PATH handler: nil];
    }

    const char * path = [TUNNELBLICK_UPDATER_LOG_PATH fileSystemRepresentation];

    logFile = fopen(path, "w");
    if (  logFile == NULL  ) {
        NSLog(@"updater: Error %d (%s) trying to open for writing: '%@'",
              errno, strerror(errno), TUNNELBLICK_UPDATER_LOG_PATH);
    }
}

-(void) removeObsoleteAppcastAndUpdateInfo {

    // If we have updated past the build specified in the "skipBuildPref" preference, remove the preference.
    NSString * skipBuildInfo = [gTbDefaults stringForKey: self.skipBuildPref];
    if (  skipBuildInfo  ) {
        NSString * thisBuildInfo = [self.infoPlistDictionary objectForKey: @"CFBundleVersion"];
        if (  thisBuildInfo ) {
            if (  [thisBuildInfo caseInsensitiveNumericCompare: skipBuildInfo] != NSOrderedAscending  ) {
                // We have updated to or past the "skipBuild" preference, so remove it.
                [gTbDefaults removeObjectForKey: self.skipBuildPref];
                [self appendUpdaterLog: [NSString stringWithFormat:
                                         @"Removed %@ preference because we are already at or past build %@",
                                         self.skipBuildPref, skipBuildInfo]];
            }
        } else {
            [self appendUpdaterLog: @"Error: Could not get CFBundleVersion from Info.plist"];
        }
    }

    // If we have updated past the update .zip, or we have lost the preference used to store info about
    // that update, delete the preference and remove the .zip and the .app that was expanded from the .zip.
    NSString * downloadedVersionStringInfo = [gTbDefaults stringForKey: self.downloadedUpdateVersionStringPref];
    BOOL zipExists = [gFileMgr fileExistsAtPath: TUNNELBLICK_UPDATER_ZIP_PATH];

    if (   downloadedVersionStringInfo
        || zipExists  ) {

        NSString * thisVersionStringInfo = [self.infoPlistDictionary objectForKey: @"CFBundleShortVersionString"];
        if (  ! thisVersionStringInfo ) {
            [self appendUpdaterLog: @"Error: Could not get CFBundleShortVersionString from Info.plist"];
        }

        BOOL updatedToOrPastDownloadedVersion = (  downloadedVersionStringInfo
                                                 && thisVersionStringInfo
                                                 && ( [thisVersionStringInfo caseInsensitiveNumericCompare: downloadedVersionStringInfo] != NSOrderedAscending )  );
        if (   updatedToOrPastDownloadedVersion
            || ( ! downloadedVersionStringInfo )  ) {

            // We have updated to or past the version whose .zip was downloaded,
            // or we have lost the info about what .zip was downloaded.
            // So remove the preference about the downloaded .zip if it exists
            // and delete the downloaded .zip and the .app that was expanded from it if they exist

            NSString * message = (  updatedToOrPastDownloadedVersion
                                  ? [NSString stringWithFormat: @"Already at or past %@", downloadedVersionStringInfo]
                                  : @"Have lost information about downloaded update"  );
            [self appendUpdaterLog: message];

            if (  downloadedVersionStringInfo  ) {
                [gTbDefaults removeObjectForKey: self.downloadedUpdateVersionStringPref];
                [self appendUpdaterLog: [NSString stringWithFormat: @"Removed %@ preference",
                                         self.downloadedUpdateVersionStringPref]];
            }
            if (  zipExists  ) {
                [gFileMgr tbRemovePathIfItExists: TUNNELBLICK_UPDATER_ZIP_PATH];
                [self appendUpdaterLog: [NSString stringWithFormat: @"Removed %@", TUNNELBLICK_UPDATER_ZIP_PATH]];
            }
        }
    }
}

-(void) setupUpdateCheckTimer {

    NSTimeInterval checkInterval = [gTbDefaults timeIntervalForKey: @"updateCheckInterval"
                                                           default: SECONDS_BETWEEN_CHECKS_FOR_TUNNELBLICK_UPDATES // Default = 24 hours
                                                               min: 60.0 * 60.0                 // Minimum = 1 hour to prevent DOS on the update server
                                                               max: 60.0 * 60.0 * 24.0 * 7];    // Maximum = 1 week

    [self setUpdateCheckTimer: [NSTimer scheduledTimerWithTimeInterval: checkInterval
                                                                target: self
                                                              selector: @selector(updateCheckTimerTick:)
                                                              userInfo: nil
                                                               repeats: YES]];
}

-(void) appendLog: (NSString *) message {

    [self appendUpdaterLog: message];
}

-(void) appendUpdaterLog: (NSString *) message {

    // Append a messsage to the updater log, and schedule the log to be closed and re-opened for append in 1.0 seconds, with a tolerance of 0.2 seconds.

    if (  ! logFile  ) {
        NSLog(@"updater: appendUpdaterLog: No file to append message: %@", message);
        return;
    }

    NSString * finalMessage = [NSString stringWithFormat: @"%@ %@ updater: %@\n", self.now, self.appOrConfig, message];
    NSData * data = [finalMessage dataUsingEncoding: NSUTF8StringEncoding];
    size_t written = fwrite(data.bytes, 1, data.length, logFile);
    if ( written == data.length  ) {
        NSTimer * timer = [NSTimer scheduledTimerWithTimeInterval: 1.0
                                                           target: self
                                                         selector: @selector(closeAndReopenLog)
                                                         userInfo: nil
                                                          repeats: NO];
        [timer setTolerance: 0.2];
        [self setDebugLogFlushTimer: timer];
    } else {
        appendLog([NSString stringWithFormat:
                   @"updater: Could not write %lu bytes (wrote %lu) to '%@'",
                   data.length, written, TUNNELBLICK_UPDATER_LOG_PATH]);
    }
}

-(NSString *) appOrConfig {

    return ( self.isAppUpdate ? @"app" : @"config");
}

-(NSString *) now {

    return  [[NSDate date] tunnelblickUserLogRepresentation];
}

-(void) closeAndReopenLog {

    if (  logFile  ) {
        if (  0 != fclose(logFile)  ) {
            NSLog(@"updater: Error %d (%s) trying to close '%@'",
                  errno, strerror(errno), TUNNELBLICK_UPDATER_LOG_PATH);
        }

        logFile = fopen([TUNNELBLICK_UPDATER_LOG_PATH fileSystemRepresentation], "a");
        if (  ! logFile  ) {
            NSLog(@"updater: Error %d (%s) trying to open for append: '%@'",
                  errno, strerror(errno), TUNNELBLICK_UPDATER_LOG_PATH);
        }
    }
}

//********************************************************************************
//
// Notify MenuController of changes

-(void) notifyErrorMessage: (NSString *) message {

    [self appendUpdaterLog: message];

    if (  self.notifiedAboutUpdateError  ) {
        return;
    }

    [self setNotifiedAboutUpdateError: YES];

    [delegate tbUpdateErrorOccurredInAppUpdate: [NSNumber numberWithBool: self.isAppUpdate]];
}

-(void) notifyTbUpdateIsAvailable: (NSNumber *) isAvailable {

    [delegate tbUpdateIsAvailable: isAvailable];
}

-(void) notifyDownloadCompletePercentage: (double) percentage {

    [delegate tbUpdateDownloadCompletePercentage: percentage];
    [self.windowController.progressInd setDoubleValue: percentage];
    [self.windowController.progressInd setHidden: (percentage == 0.0)];

    if (  percentage == 100.0  ) {
        [self.windowController.defaultButton setTitle: NSLocalizedString(@"Install and Relaunch", @"Button to install an update")];
        BOOL enabled = ( ! self.updateAuthorizedByUser );
        [self.windowController.defaultButton setEnabled: enabled];
    }
}

-(void) notifyWillInstallUpdate {

    [delegate tbUpdateWillInstallUpdate];
}

-(void) notifyDidInstallUpdate {

    [delegate tbUpdateDidInstallUpdate];
}

-(void) notifyFailedToInstallUpdate {

    [delegate tbUpdaterFailedToInstallUpdate];
}

//*****************************************************************************
// DOWNLOADING AND PROCESSING APPCAST

-(void) checkIfAnUpdateIsAvailableForcingCheck: (NSNumber *) forced {

    // If currently updating, ignore
    //
    // If currently checking for updates
    //    If this one is forced, re-schedule it
    //    Else ignore

    if (  self.currentlyUpdating  ) {
        [self appendUpdaterLog: [NSString stringWithFormat:
                                 @"checkIfAnUpdateIsAvailableForcingCheck: %s ignored because currently updating",
                                 CSTRING_FROM_BOOL([forced boolValue])]];
        return;
    }

    if (  self.currentlyChecking ) {
        [self appendUpdaterLog: [NSString stringWithFormat:
                                 @"checkIfAnUpdateIsAvailableForcingCheck: %s ignored because currently checking",
                                 CSTRING_FROM_BOOL([forced boolValue])]];
        if (  [forced boolValue]  ) {
            [self appendUpdaterLog: @"checkIfAnUpdateIsAvailableForcingCheck: YES invoked but currentlyChecking = YES, so changing to a forced check"];
            [self setAppcastDownloadIsForced: YES];
        } else {
            [self appendUpdaterLog: @"checkIfAnUpdateIsAvailableForcingCheck: NO invoked but currentlyChecking = YES, so ignoring it and continuing the non-forced check"];
        }
        return;
    }

    if (   ! [forced boolValue]
        && ( ! [self canCheckForUpdates: [forced boolValue]] )  ) {
        [self appendUpdaterLog: @"checkIfAnUpdateIsAvailableForcingCheck: NO ignored because can't check for updates automatically"];
        return;
    }

    [self setCurrentlyChecking: YES];
    [self startDownloadingAppcastForcingCheck: forced];
}

-(BOOL) canCheckForUpdates: (BOOL) forced {

    NSString * name = (  forced
                       ? nil
                       : self.canCheckAutomaticallyPref);

    BOOL result = [self canCheckForUpdatesWithPreferenceName: name];
    return result;
}

-(void) startDownloadingAppcastForcingCheck: (NSNumber *) forced {

    NSString * feedURLString = self.appcastURLString;
    if (  ! feedURLString  ) {
        [self appendUpdaterLog: [NSString stringWithFormat:
                                 @"startDownloadingAppcastForcingCheck: %s: No URL string! (internal error: inhibitUpdating should be false so this method should not be executed)",
                                 CSTRING_FROM_BOOL([forced boolValue])]];
        return;
    }

    [self appendUpdaterLog: [NSString stringWithFormat:
                             @"startDownloadingAppcastForcingCheck: %s: Will load appcast from '%@'",
                             CSTRING_FROM_BOOL([forced boolValue]), feedURLString]];

    appcastDownloader = [[TBDownloader alloc] init];    // RELEASED in appcastDownloadFinishedWithMesssage:
    [appcastDownloader setUrlString: feedURLString];
    [appcastDownloader setDelegate: self];
    [appcastDownloader setFinishedSelector: @selector(appcastDownloadFinishedWithMesssage:)];

    appcastContents = [[NSMutableData alloc] init]; // RELEASED in processDownloadedAppcast

    [appcastDownloader setContents: appcastContents];
    [appcastDownloader setMaximumLength: TB_APPCAST_MAX_FILE_SIZE];

    [self setAppcastDownloadIsForced: [forced boolValue]];

    [appcastDownloader startDownload];
}

-(void) appcastDownloadFinishedWithMesssage: (NSString *) message {

    [self appendUpdaterLog: [NSString stringWithFormat:
                             @"appcastDownloadFinishedWithMesssage: '%@' invoked",
                             message]];

    [self setCurrentlyChecking: NO];

    [self setAppcastDownloader: nil];

    if (  message  ) {
        [self setUpdateContents: nil];
        [self setUpdateWasDownloaded: NO];
        [self notifyDownloadCompletePercentage: 0.0];

        if (  ! [message isEqualToString: @"Cancelled"]  ) {
            [self notifyErrorMessage: message];
            if (  self.appcastDownloadIsForced  ) {
                TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                                  [NSString stringWithFormat:
                                   NSLocalizedString(@"An error occurred trying to get information about updates.\n\n"
                                                     @"For more information, see the log at\n\n"
                                                     @"%@",
                                                     @"Window text. The '%@' will be replaced with a file path such as '/Library/Application Support/filename'"), TUNNELBLICK_UPDATER_LOG_PATH]);
            }
        }

        [self appropriateUpdateIsAvailable: NO errorOccurred: YES];
        return;
    }

    [self processDownloadedAppcast];
}

-(void) processDownloadedAppcast {

    [self appendUpdaterLog: @"processDownloadedAppcast invoked"];

    // Verify the signature
    if (  ! [validator validateAppcastData: self.appcastContents
                          withPublicDSAKey: self.publicKey]  ) {
        goto doneReturnErr;
    }

    // Get the appcast, including signature and <rss version... lines
    NSString * appcast = [[[NSString alloc] initWithData: self.appcastContents encoding: NSUTF8StringEncoding] autorelease];
    if (  ! appcast  ) {
        [self notifyErrorMessage: @"Could not decode appcast as UTF8"];
        goto doneReturnErr;
    }

    [self setAppcastContents: nil];  // ALLOCATED IN startDownloadingAppcastForcingCheck:

    // Get string with everything from the first "<item>" to the last "</item>"
    NSString * itemsString = [self itemsStringFromAppcast: appcast];
    if (  ! itemsString  ) {
        goto doneReturnErr;
    }

    // Get array of dictionaries; each dictionary contains info from one <item>...</item> sequence
    NSArray * itemInfo = [self itemInfoFromItemString: itemsString];
    if (  ! itemInfo  ) {
        goto doneReturnErr;
    }

    // Examine each array entry of item info until we find one that is OK to use

    NSEnumerator * e = [itemInfo objectEnumerator];
    NSDictionary * dict;
    while (  (dict = [e nextObject])  ) {
        if (  [self isUpdateAppropriate: dict]  ) {
            [self setUpdateInfo: dict];
            [self appropriateUpdateIsAvailable: YES
                                 errorOccurred: NO];
            return;
        }
    }

    appendLog(@"No  appropriate update is available");
    [self appropriateUpdateIsAvailable: NO
                         errorOccurred: NO];
    return;

doneReturnErr:

    [self appropriateUpdateIsAvailable: NO
                         errorOccurred: YES];
}

    -(NSString *) itemsStringFromAppcast: (NSString *) appcast {

        // Returns a string with everything from the first <item> to the last </item>
        //
        // Or nil if error, having logged an error message

        NSRange rFirstItem = [appcast rangeOfString: @"<item>"];
        if (  rFirstItem.length == 0  ) {
            [self notifyErrorMessage: @"Could not find first <item> in appcast"];
            return nil;
        }

        NSRange rLastEndItem = [appcast rangeOfString: @"</item>" options: NSBackwardsSearch];
        if (  rLastEndItem.length == 0  ) {
            [self notifyErrorMessage: @"Could not find last </item> in appcast"];
            return nil;
        }

        NSUInteger startFirstItem = rFirstItem.location;
        NSUInteger endLastItem = rLastEndItem.location + @"</item>".length;

        if (  startFirstItem >= endLastItem  ) {
            [self notifyErrorMessage: @"</item> before <item> in appcast"];
            return nil;
        }

        NSRange rItems = NSMakeRange(startFirstItem, endLastItem - startFirstItem);
        NSString * sItems = [appcast substringWithRange: rItems];

        return sItems;
    }

    -(NSArray *) itemInfoFromItemString: string {

        // Return an array of dictionaries; each dictionary contains info from one <item>...</item> sequence

        NSArray * items = [string componentsSeparatedByString: @"<item>"];
        if (  ! items) {
            [self notifyErrorMessage: @"Could not separate appcast by '<item>'"];
            return nil;
        }

        NSMutableArray * itemInfo = [[[NSMutableArray alloc] initWithCapacity: 10] autorelease];
        NSEnumerator * e = [items objectEnumerator];
        NSString * item;
        while (  (item = [e nextObject])  ) {
            if (  item.length != 0  ) {
                NSDictionary * dict = [self parseItem: item];
                if (  ! dict  ) {
                    return nil;
                }
                [itemInfo addObject: dict];
            }
        }

        return itemInfo;
    }

        -(NSDictionary *) parseItem: (NSString *) string {

            // Returns nil if an error occurred.

            NSMutableDictionary * dict = [[[NSMutableDictionary alloc] initWithCapacity: 20] autorelease];

            [self ifNotNilSetObject: [self extractFromString: string after: @"sparkle:shortVersionString=\""   before: @"\""]    forKey: @"versionString" inDictionary: dict];
            [self ifNotNilSetObject: [self extractFromString: string after: @"sparkle:version=\""              before: @"\""]    forKey: @"build"         inDictionary: dict];
            [self ifNotNilSetObject: [self extractFromString: string after: @"sparkle:minimumSystemVersion=\"" before: @"\""]    forKey: @"minOS"         inDictionary: dict];
            [self ifNotNilSetObject: [self extractFromString: string after: @"sparkle:maximumSystemVersion=\"" before: @"\""]    forKey: @"maxOS"         inDictionary: dict];
            [self ifNotNilSetObject: [self extractFromString: string after: @"sparkle:architectures=\""        before: @"\""]    forKey: @"architectures" inDictionary: dict];
            [self ifNotNilSetObject: [self extractFromString: string after: @"url=\""                          before: @"\""]    forKey: @"url"           inDictionary: dict];
            [self ifNotNilSetObject: [self extractFromString: string after: @"sparkle:dsaSignature=\""         before: @"\""]    forKey: @"signature"     inDictionary: dict];
            [self ifNotNilSetObject: [self extractFromString: string after: @"length=\""                       before: @"\""]    forKey: @"lengthString"  inDictionary: dict];
            [self ifNotNilSetObject: [self extractFromString: string after: @"type=\""                         before: @"\""]    forKey: @"type"          inDictionary: dict];
            [self ifNotNilSetObject: [self extractFromString: string after: @"<![CDATA["                       before: @"]]>\n"] forKey: @"notes"         inDictionary: dict];

            if (   ! dict[@"versionString"]
                || ! dict[@"build"]
                //      || ! dict[@"minOS"]         // Optional
                //      || ! dict[@"maxOS"]         // Optional
                //      || ! dict[@"architectures"] // Optional
                || ! dict[@"url"]
                || ! dict[@"signature"]
                || ! dict[@"lengthString"]
                || ! dict[@"type"]
                || ! dict[@"notes"] ) {

                [self notifyErrorMessage: @"Appcast does not contain all required information"];
                return nil;
            }

            long long len = [dict[@"lengthString"] longLongValue];
            if (   (len < MINIMUM_APP_UPDATE_LENGTH)
                || (len > MAXIMUM_APP_UPDATE_LENGTH)  ) {
                [self notifyErrorMessage: [NSString stringWithFormat:
                                           @"Length of update .zip file (%lld) specified in appcast is too small or too big",
                                           len]];
                return nil;
            }

            [dict setObject: [NSNumber numberWithLongLong: len] forKey: @"length"];

            return dict;
        }

            -(void) ifNotNilSetObject: (id)                    object
                               forKey: (NSString *)            key
                         inDictionary: (NSMutableDictionary *) dict {

                if (  object  ) {
                    [dict setObject: object forKey: key];
                }
            }

            -(NSString *) extractFromString: (NSString *) text
                                      after: (NSString *) after
                                     before: (NSString *) before {

                NSRange r1 = [text rangeOfString: after];
                if (  r1.length == 0) {
                    [self notifyErrorMessage: [NSString stringWithFormat: @"Warning: did not find '%@' in appcast", after]];
                    return nil;
                }


                NSUInteger start = r1.location + after.length;
                NSRange restOfText = NSMakeRange(start, text.length - start);
                NSRange r2 = [text rangeOfString: before options: 0 range: restOfText];
                if (  r2.length == 0) {
                    [self notifyErrorMessage: [NSString stringWithFormat:
                                               @"Error finding '%@' which should be after '%@' in appcast",
                                               after, before]];
                    return nil;
                }

                NSString * result = [text substringWithRange: NSMakeRange(start, r2.location - start)];
                return result;
            }

    -(BOOL) isUpdateAppropriate: (NSDictionary *) dict {

        NSString * skipBuild = [gTbDefaults stringForKey: self.skipBuildPref];
        if (   skipBuild
            && [skipBuild isEqualToString: dict[@"build"]]   ) {
            [self appendUpdaterLog: [NSString stringWithFormat: @"isUpdateAppropriate: returning NO -- update build %@ is same as %@ preference",
                                     dict[@"build"], self.skipBuildPref]];
            return NO;
        }


        if (  [self.currentBuild caseInsensitiveNumericCompare: dict[@"build"]] != NSOrderedAscending  ) {
            [self appendUpdaterLog: [NSString stringWithFormat: @"isUpdateAppropriate: returning NO -- current build %@ >= update build %@",
                                     self.currentBuild, dict[@"build"]]];
            return NO;
        }

        if (  dict[@"minOS"]  ) {
            if (  [self.currentMacOSVersion caseInsensitiveNumericCompare: dict[@"minOS"]] == NSOrderedAscending  ) {
                [self appendUpdaterLog: [NSString stringWithFormat: @"isUpdateAppropriate: returning NO -- running on macOS %@; minimum for this update is %@",
                                         self.currentMacOSVersion, dict[@"minOS"]]];
                return NO;
            }
        }

        if (  dict[@"maxOS"]  ) {
            if (  [dict[@"maxOS"] caseInsensitiveNumericCompare: self.currentMacOSVersion] == NSOrderedAscending  ) {
                [self appendUpdaterLog: [NSString stringWithFormat: @"isUpdateAppropriate: returning NO -- running on macOS %@; maximum for this update is %@",
                                         self.currentMacOSVersion, dict[@"maxOS"]]];
                return NO;
            }
        }
        if (  dict[@"architectures"] ) {
            if (  ! [dict[@"architectures"] containsString: self.currentArchitecture]  ) {
                [self appendUpdaterLog: [NSString stringWithFormat:
                                         @"isUpdateAppropriate: returning NO -- running on %@ architecture; not in '%@'",
                                         self.currentArchitecture, dict[@"architectures"]]];
                return NO;
            }
        }

        [self appendUpdaterLog: @"isUpdateAppropriate: returning YES"];
        return YES;
    }

-(void) appropriateUpdateIsAvailable: (BOOL) isAvailable
                       errorOccurred: (BOOL) errorOccurred {

    [self appendUpdaterLog: [NSString stringWithFormat:
                             @"appropriateUpdateIsAvailable: %s errorOccurred: %s invoked",
                             CSTRING_FROM_BOOL(isAvailable), CSTRING_FROM_BOOL(errorOccurred)]];

    if (  errorOccurred  ) {
        if (  self.appcastDownloadIsForced  ) {
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                              [NSString stringWithFormat:
                               NSLocalizedString(@"An error occurred trying to get information about updates.\n\n"
                                                 @"For more information, see the log at\n\n"
                                                 @"%@",
                                                 @"Window text. The '%@' will be replaced with a file path such as '/Library/Application Support/filename'"), TUNNELBLICK_UPDATER_LOG_PATH]);
        }
        return;
    }

    [gTbDefaults setObject: [NSDate date] forKey: @"SULastCheckTime"];

    if (  ! isAvailable  ) {
        if (  self.appcastDownloadIsForced  ) {
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                              NSLocalizedString(@"Tunnelblick is up to date", @"Window text"));
        }
        return;
    }

    if (  self.canDownloadUpdatesAutomatically  ) {
        [self startDownloadingUpdate];
    }

    [self appendUpdaterLog: [NSString stringWithFormat:
                             @"appropriateUpdateIsAvailable: %s errorOccurred: %s invoking notifyTbUpdateIsAvailable: YES in one second",
                             CSTRING_FROM_BOOL(isAvailable), CSTRING_FROM_BOOL(errorOccurred)]];

    [self performSelector: @selector(notifyTbUpdateIsAvailable:)
               withObject: @YES
               afterDelay: 1.0];

    if (  self.appcastDownloadIsForced  ) {
        [self internalOfferUpdateAndInstallIfUserAgrees];
    }
}

//*****************************************************************************
// USER INTERACTION

-(void) internalOfferUpdateAndInstallIfUserAgrees {

    if (  self.currentlyUpdating  ) {
        [self appendUpdaterLog: [NSString stringWithFormat:
                                 @"internalOfferUpdateAndInstallIfUserAgrees invoked but currentlyUpdating is TRUE; stack trace = %@",
                                 callStack()]];
        return;
    } 

    [self appendUpdaterLog: @"internalOfferUpdateAndInstallIfUserAgrees invoked"];

    if (  self.inhibitUpdating  ) {
        [self appendUpdaterLog: @"Ignoring internalOfferUpdateAndInstallIfUserAgrees because inhibitUpdating is TRUE"];
        return;
    }

    NSString * headline = NSLocalizedString(@"A new version of Tunnelblick is available", @"Window title");

    NSString * introMessage = (  isAppUpdate
                               ? [NSString stringWithFormat:
                                  NSLocalizedString(@"<p><strong>Tunnelblick %@ is now available – you have %@.</strong></p>\n\n",
                                                    @"HTML window text\nThe two %@ are descriptions of Tunnelblick versions (e.g. '4.0.1 (build 5971)'"),
                                  self.updateInfo[@"versionString"], self.currentTunnelblickVersionString]
                               : [NSString stringWithFormat:
                                  NSLocalizedString(@"<p><strong>VPN Configuration %@ is now available – you have %@.</strong></p>\n\n",
                                                    @"Window text\nThe two %@ are descriptions of configuration versions (e.g. '1.2.3'"),
                                  self.updateInfo[@"versionString"], self.currentTunnelblickVersionString]);

    NSString * adminMessage = (   ( ! [gTbDefaults canChangeValueForKey: self.nonAdminCanUpdateAppPref] )
                               && [gTbDefaults boolForKey: self.nonAdminCanUpdateAppPref]
                               ? @""
                               : NSLocalizedString(@"<p><strong>A computer administrator's authorization is required to install this update.</strong></p>\n", @"HTML window text"));

    NSString * disconnectMessage = (  self.areConnectedToVPN
                                    ? NSLocalizedString(@"<hr><p><strong>One or more VPNs may be disconnected before the update.</strong></p>\n", @"HTML window text")
                                    : @"");

    NSString * wouldYouMessage = NSLocalizedString(@"<hr><p><strong>Would you like to update to the new version now?</strong></p>\n", @"HTML window text");

    NSString * htmlMessage = [NSString stringWithFormat:
                              @"%@\n%@\n<hr>\n%@\n%@\n%@",
                              introMessage, updateInfo[@"notes"], adminMessage, disconnectMessage, wouldYouMessage];

    NSAttributedString * message =  attributedLightDarkStringFromHTML(htmlMessage);
    if (  ! message) {
        [self notifyErrorMessage: @"error in format of update notes"];
        return;
    }

    if (  [self showAlertWindowWithHeadline: headline
                                    message: message]  ) {
        return;
    }

    // AlertWindowController isn't working, fall back on TBRunAlertPanel

    int result = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                                 htmlMessage,
                                 NSLocalizedString(@"Install",           @"Button to install an update"),  // Default
                                 NSLocalizedString(@"Skip This Version", @"Button to skip a particular update"),  // Alternate
                                 NSLocalizedString(@"Remind Me Later",   @"Button to be reminded about an update")); // Other

    switch (  result  ) {

        case NSAlertDefaultReturn:
            [self installUpdate];
            break;

        case NSAlertAlternateReturn:
            [self skipThisVersion];
            break;

        case NSAlertOtherReturn:
            [self remindLater];
            break;

        default: // Error; already logged
            ;
    }
}

-(void) closeAlertWindow {

    if (  windowController  ) {
        NSWindow * w = [windowController window];
        [w close];
        [self setWindowController: nil];
        [self appendUpdaterLog: @"Window closed and released"];
    } else {
        [self appendUpdaterLog: @"Window is nil, so not closed and released"];
    }
}

-(BOOL) showAlertWindowWithHeadline: (NSString *) headline
                            message: (NSAttributedString *) message {

    if (  windowController  ) {
        [self closeAlertWindow];
    }

    windowController = [[AlertWindowController alloc] init];
    if (  ! windowController  ) {
        return NO;
    }

    [self setupAlreadyDownloadedUpdateInfo];

    [windowController setHeadline: headline];
    [windowController setMessageAS: message];

    [windowController setResponseTarget: self];

    [windowController setDefaultResponseSelector:   @selector(userAuthorizedUpdate)];
    [windowController setAlternateResponseSelector: @selector(remindLater)];
    [windowController setOtherResponseSelector:     @selector(skipThisVersion)];

    NSString * downloadAndInstallOrInstallAndRestart = (  self.updateWasDownloaded
                                                        ? NSLocalizedString(@"Install and Relaunch", @"Button to install an update")
                                                        : NSLocalizedString(@"Download and Install", @"Button to install an update"));
    if (  self.updateWasDownloaded  ) {
        [windowController setInitialPercentage: 100.0];
    } else {
        [windowController setInitialPercentage: 0.0];
    }

    [windowController setDefaultButtonTitle:   downloadAndInstallOrInstallAndRestart];
    [windowController setAlternateButtonTitle: NSLocalizedString(@"Remind Me Later",   @"Button to be reminded about an update")];
    [windowController setOtherButtonTitle:     NSLocalizedString(@"Skip This Version", @"Button to skip a particular update")];

    NSWindow * win = [windowController window];
    [win center];
    [windowController showWindow:  nil];
    [win makeKeyAndOrderFront: nil];
    [gMC activateIgnoringOtherApps];

    return YES;
}

-(void) userAuthorizedUpdate {

    [self setUpdateAuthorizedByUser: YES];

    [self appendUpdaterLog: [NSString stringWithFormat: @"User agreed to update to %@", self.updateInfo[@"versionString"]]];

    if (  self.inhibitUpdating  ) {
        [self appendUpdaterLog: @"userAuthorizedUpdate but inhibitUpdating = TRUE"];
        [self.updateDownloader stopDownload];
        return;
    }

    if (  [gTbDefaults boolForKey: @"inhibitOutboundTunneblickTraffic"]  ) {
        [self appendUpdaterLog: @"userAuthorizedUpdate but inhibitOutboundTunneblickTraffic preference = TRUE"];
        [self.updateDownloader stopDownload];
       return;
    }

    if (  ! self.updateWasDownloaded  ) {
        if (  ! self.updateDownloader ) {
            [self appendUpdaterLog: @"userAuthorizedUpdate but update has not been downloaded and is not being downloaded yet. Will start download."];
            [self startDownloadingUpdate];
        }
        [self.windowController setDefaultResponseSelector: @selector(cancelDownload)];
        [self.windowController.defaultButton setTitle: NSLocalizedString(@"Cancel", @"Button")];
        [self.windowController.defaultButton setEnabled: YES];
        return;
    }

    [self appendUpdaterLog: @"userAuthorizedUpdate and update has been downloaded. Will start installation."];
    [self installUpdate];
}

-(void) skipThisVersion {

    [self closeAlertWindow];

    [self appendUpdaterLog: [NSString stringWithFormat:
                             @"User wants to skip the update to Tunnelblick %@",
                             self.updateInfo[@"versionString"]]];
    [gTbDefaults setObject: self.updateInfo[@"build"] forKey: self.skipBuildPref];

    [self.updateDownloader stopDownload];

    if (  [gTbDefaults objectForKey: self.downloadedUpdateVersionStringPref]  ) {
        [gTbDefaults removeObjectForKey: self.downloadedUpdateVersionStringPref];
    }
    [gFileMgr tbRemovePathIfItExists: self.downloadedUpdatePath];

    [self notifyTbUpdateIsAvailable: @NO];
}

-(void) remindLater {

    [self closeAlertWindow];

    [self appendUpdaterLog: [NSString stringWithFormat:
                             @"User wants to be reminded later about the update to %@",
                             self.updateInfo[@"versionString"]]];

    [self notifyTbUpdateIsAvailable: @NO];
}

-(void) cancelDownload {

    [self.updateDownloader stopDownload];

    // Discard anything that's downloaded
    [gTbDefaults removeObjectForKey: self.downloadedUpdateVersionStringPref];
    [self setupAlreadyDownloadedUpdateInfo];

    [self closeAlertWindow];
}

//*****************************************************************************
// DOWNLOADING UPDATE

-(void) startDownloadingUpdate {

    if (  self.updateDownloader ) {
        [self appendUpdaterLog: [NSString stringWithFormat:
                                 @"startDownloadingUpdate invoked but self.updateDownloader exists; stack trace = %@",
                                 callStack()]];
        return;
    }

    [self appendUpdaterLog: @"startDownloadingUpdate"];

    // If we have already downloaded this version we don't need to download it again
    if (  [self setupAlreadyDownloadedUpdateInfo]  ) {
        if (  self.updateAuthorizedByUser  ) {
            [self appendUpdaterLog: @"startDownloadingUpdate: have already downloaded the update and received authorization by the user, so installing the update"];
            [self installUpdate];
        } else {
            [self appendUpdaterLog: @"startDownloadingUpdate: have already downloaded update but not yet received authorization from the user, so returning"];
        }
        return;
    }

    if (  ! updateContents  ) {
        updateContents = [[NSMutableData alloc] initWithCapacity: [self.updateInfo[@"length"] longLongValue]];
    }

    updateDownloader = [[TBDownloader alloc] init];

    [updateDownloader setUrlString: self.updateInfo[@"url"]];
    [updateDownloader setDelegate: self];
    [updateDownloader setFinishedSelector: @selector(updateDownloadFinishedWithMesssage:)];
    [updateDownloader setContents: self.updateContents];

    [updateDownloader setProgressSelector: @selector(updateProgress:)];
    [updateDownloader setExpectedLength: [self.updateInfo[@"length"] longLongValue]];
    [updateDownloader setMaximumLength: TB_UPDATE_MAX_ZIP_FILE_SIZE];

    [updateDownloader startDownload];
}

-(void) updateProgress: (NSNumber *) progress {

    [self notifyDownloadCompletePercentage: [progress doubleValue]];
}

-(void) updateDownloadFinishedWithMesssage: (NSString *) message {

    if (  ! self.updateDownloader ) {
        [self appendUpdaterLog: [NSString stringWithFormat:
                                 @"updateDownloadFinishedWithMesssage: '%@' invoked but self.updateDownloader exists",
                                 message]];
        return;
    }

    [self appendUpdaterLog: [NSString stringWithFormat:
                             @"updateDownloadFinishedWithMesssage: '%@' invoked",
                             message]];

    [updateDownloader release];
    updateDownloader= nil;

    if (  message  ) {
        if (  [message isEqualToString: @"Cancelled"]  ) {
            [self setUpdateContents: nil];
            [self setUpdateWasDownloaded: NO];
            [self notifyDownloadCompletePercentage: 0.0];
            return;
        }

        [self notifyErrorMessage: message];
        goto updateDownloadFailed;
    }

    // Write out the update
    if (  ! [self.updateContents writeToFile: self.downloadedUpdatePath atomically: NO]  ) {
        [self notifyErrorMessage: [NSString stringWithFormat:
                                   @"connectionDidFinishLoading: Could not write update file to %@",
                                   self.downloadedUpdatePath]];
        goto updateDownloadFailed;
    }

    // Remember we have downloaded the update
    [gTbDefaults setObject: self.updateInfo[@"versionString"] forKey: self.downloadedUpdateVersionStringPref];

    [self setUpdateWasDownloaded: YES];

    [self notifyDownloadCompletePercentage: 100.0];

    if (  self.updateAuthorizedByUser  ) {
        [self appendUpdaterLog: @"connectionDidFinishLoading: User has authorized update, so installing it"];
        [self installUpdate];
    } else {
        [self appendUpdaterLog: @"connectionDidFinishLoading: User has not authorized update"];
    }

    return;

updateDownloadFailed:

    [self setUpdateContents: nil];
    [self setUpdateWasDownloaded: NO];
    [self notifyDownloadCompletePercentage: 0.0];

    if (  windowController  ) {
        [self closeAlertWindow];
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          [NSString stringWithFormat:
                           NSLocalizedString(@"An error occurred trying to download the update.\n\n"
                                             @"For more information, see the log at\n\n"
                                             @"%@",
                                             @"Window text. The '%@' will be replaced with a file path such as '/Library/Application Support/filename'"), TUNNELBLICK_UPDATER_LOG_PATH]);
    }
}

-(BOOL) setupAlreadyDownloadedUpdateInfo {

    // Returns YES if the most-recent update has already been downloaded

    if (  self.updateDownloader  ) {
        [self appendUpdaterLog: @"setupAlreadyDownloadedUpdateInfo but self.updateDownloader exists"];
        goto returnNO;
    }

    NSString * downloadedVersionString = [gTbDefaults objectForKey: self.downloadedUpdateVersionStringPref];
    if (  ! downloadedVersionString  ) {
        if (  [gFileMgr fileExistsAtPath: self.downloadedUpdatePath]  ) {
            [self appendUpdaterLog: [NSString stringWithFormat:
                                     @"%@ preference preference does not exist; removing an already-downloaded update",
                                     self.downloadedUpdateVersionStringPref]];
            [gFileMgr tbRemovePathIfItExists: self.downloadedUpdatePath];
        }
        goto returnNO;
    }

    if (  ! [downloadedVersionString isEqualToString: self.updateInfo[@"versionString"]]  ) {
        [self appendUpdaterLog: [NSString stringWithFormat:
                                 @"%@ preference is '%@', not the current (%@); removing the preference and any already-downloaded update",
                                 self.downloadedUpdateVersionStringPref, downloadedVersionString, self.updateInfo[@"versionString"]]];
        [gTbDefaults removeObjectForKey: self.downloadedUpdateVersionStringPref];
        [gFileMgr tbRemovePathIfItExists: self.downloadedUpdatePath];
        goto returnNO;
    }

    if (  ! [gFileMgr fileExistsAtPath: self.downloadedUpdatePath]  ) {
        [self appendUpdaterLog: [NSString stringWithFormat:
                                 @"%@ preference is '%@' but no downloaded file exists; removing the preference",
                                 self.downloadedUpdateVersionStringPref, downloadedVersionString]];
        [gTbDefaults removeObjectForKey: self.downloadedUpdateVersionStringPref];
        goto returnNO;
    }

    // HAVE ALREADY downloaded this version

    [self appendUpdaterLog: [NSString stringWithFormat:
                             @"     setupAlreadyDownloadedUpdateInfo returning YES; will use already downloaded %@",
                             downloadedVersionString]];
    [self setUpdateWasDownloaded: YES];
    [self notifyDownloadCompletePercentage: 100.0];
    return YES;

returnNO:

    [self appendUpdaterLog: @"     setupAlreadyDownloadedUpdateInfo returning NO"];
    [self setUpdateWasDownloaded: NO];
    [self notifyDownloadCompletePercentage: 0.0];
    return NO;
}

//*****************************************************************************
// INSTALLING UPDATE

-(void) installUpdate {

    // Delay so the progress indicator can show the update has been completely downloaded
    [self performSelector: @selector(installUpdateWithoutDelay) withObject: nil afterDelay: 0.5];
}

-(void) installUpdateWithoutDelay {

    if (  ! self.updateAuthorizedByUser  ) {
        [self notifyErrorMessage: @"installUpdate but user hasn't agreed yet"];
        [self notifyFailedToInstallUpdate];
        return;
    } else {
        [self appendUpdaterLog: @"installUpdate invoked"];
    }

    if (  ! self.updateWasDownloaded  ) {
        [self notifyErrorMessage: @"installUpdate but update not downloaded"];
        [self notifyFailedToInstallUpdate];
        return;
    }

    // Get the update .zip's contents  and verify it is the correct size
    NSData * data = [NSData dataWithContentsOfFile: self.downloadedUpdatePath];
    if (  ! data  ) {
        [self notifyErrorMessage: [NSString stringWithFormat:
                                   @"Failed to install update: Could not read '%@'",
                                   self.downloadedUpdatePath]];
        [self notifyFailedToInstallUpdate];
        return;
    }

    if (  (long long)data.length != [self.updateInfo[@"length"] longLongValue]  ) {
        [self notifyErrorMessage: [NSString stringWithFormat:
                                   @"Failed to install update: The update .zip file was %lu bytes; should be %lld bytes.",
                                   (unsigned long)data.length, [self.updateInfo[@"length"] longLongValue]]];
        [self notifyFailedToInstallUpdate];
        return;
    }

    pid_t tunnelblickPid = [[NSProcessInfo processInfo] processIdentifier];
    if (  tunnelblickPid == 0  ) {
        [self notifyErrorMessage: @"Failed to install update: Tunnelblick processs ID is 0"];
        [self notifyFailedToInstallUpdate];
        return;
    }
    NSString * tunnelblickPidString = [NSString stringWithFormat: @"%u", tunnelblickPid];

    [self notifyWillInstallUpdate];

    [self setCurrentlyUpdating: YES];

    int result;
    if (   ( ! [gTbDefaults canChangeValueForKey: self.nonAdminCanUpdateAppPref] )
        && [gTbDefaults boolForKey: self.nonAdminCanUpdateAppPref]  ) {
        result = [self installUsingOpenvpnstartWithTunnelblickPid: tunnelblickPidString];
    } else {
        result = [self installUsingInstallerWithTunnelblickPid: tunnelblickPidString];
    }

    if (  result == 0  ) { // Success

        [self removeDownloadedUpdate];
        [self appendUpdaterLog: @"installUpdate PHASES 1 and 2 completed and downloaded .zip removed"];
        [self notifyDidInstallUpdate];

    } else if (  result == 1  ) {   // User cancelled
        [self setCurrentlyUpdating: NO];
        [self setUpdateAuthorizedByUser: NO];
        [self closeAlertWindow];
    } else {                        // Error
        [self setCurrentlyUpdating: NO];
        [self setUpdateAuthorizedByUser: NO];
        [self notifyErrorMessage: @"Failed to install update: Error in installer or tunnelblick-helper"];
        [self notifyFailedToInstallUpdate];
    }
}

-(int) installUsingInstallerWithTunnelblickPid: (NSString *) tunnelblickPidString {

    [self appendUpdaterLog: [NSString stringWithFormat:
                             @"installUsingInstallerWithTunnelblickPid: %@ invoked",
                             tunnelblickPidString]];

    NSString * message = NSLocalizedString(@"Tunnelblick needs a computer administrator's authorization to update.\n\n"
                                           @"Tunnelblick will be relaunched after the update.",
                                           @"Window text");
    SystemAuth * auth = [[SystemAuth newAuthWithPrompt: message] autorelease];

    NSInteger result = [gMC runInstaller: INSTALLER_UPDATE_TUNNELBLICK
                          extraArguments: @[self.updateInfo[@"signature"], self.updateInfo[@"versionString"], NSUserName(), tunnelblickPidString]
                         usingSystemAuth: auth
                            installTblks: nil];

    NSString * installerLog = [[[NSString alloc]
                                initWithContentsOfFile: @"/Library/Application Support/Tunnelblick/tunnelblick-installer-log.txt"] autorelease];
    if (  ! installerLog  ) {
        appendLog(@"Warning: Could not get contents of /Library/Application Support/Tunnelblick/tunnelblick-installer-log.txt");
        installerLog = @"";
    }

    switch (  result  ) {

        case 0:
            [self appendUpdaterLog:
             [NSString stringWithFormat:
              @"installUsingInstallerWithTunnelblickPid: returning 0 (success). Log = '\n%@'",
              installerLog]];
            break;

        case 1:
            [self appendUpdaterLog:
             [NSString stringWithFormat:
              @"installUsingInstallerWithTunnelblickPid: returning 1 (user cancelled). Log = '\n%@'",
              installerLog]] ;
            break;

        default:
            [self appendUpdaterLog:
             [NSString stringWithFormat:
              @"installUsingInstallerWithTunnelblickPid: returning %ld (failed). Log = '\n%@'",
              (long)result, installerLog]];
    }

    return result;
}

-(int) installUsingOpenvpnstartWithTunnelblickPid: (NSString *) tunnelblickPidString {

    [self appendUpdaterLog: @"installUpdate installing using openvpnstart..."];

    NSArray * arguments = @[@"updateTunnelblickApp",
                            self.updateInfo[@"signature"],
                            NSUserName(),
                            self.updateInfo[@"versionString"],
                            tunnelblickPidString];

    NSString * stdoutString = nil;
    NSString * stderrString = @"";
    OSStatus status = runOpenvpnstart(arguments, &stdoutString, &stderrString);
    NSString * message = @"";
    if (  stdoutString.length != 0  ) {
        message = [NSString stringWithFormat: @"stdout from runOpenvpnstart = '\n%@'\n", stdoutString];
    }
    if (  stderrString.length != 0  ) {
        message = [NSString stringWithFormat: @"%@stderr from runOpenvpnstart = '%@'\n", message, stderrString];
    }
    if (  message.length == 0  ) {
        [self appendUpdaterLog: [NSString stringWithFormat: @"status from runOpenvpnstart(updateTunnelblickApp) = %d", status]];
    } else {
        [self appendUpdaterLog: [NSString stringWithFormat: @"status from runOpenvpnstart(updateTunnelblickApp) = %d;\n%@", status, message]];
    }

    return status;
}

-(void) removeDownloadedUpdate {

    [gTbDefaults removeObjectForKey: self.downloadedUpdateVersionStringPref];
    [gFileMgr tbRemovePathIfItExists: self.downloadedUpdatePath];
    NSString * filename = (  isAppUpdate
                           ? @"Tunnelblick.app"
                           : @"WhoKnows");
    NSString * expandedPath = [[self.downloadedUpdatePath
                                stringByDeletingLastPathComponent]
                               stringByAppendingPathComponent: filename];
    [gFileMgr tbRemovePathIfItExists: expandedPath];
}

//*****************************************************************************
// MISCELLANEOUS

-(void) internalStopAllUpdateActivity {

    [self appendUpdaterLog: @"internalStopAllUpdateActivity invoked"];

    [self setInhibitUpdating: TRUE];

    [self.updateCheckTimer invalidate];
    [self setUpdateCheckTimer: nil];

    [self.appcastDownloader stopDownload];
    [self.updateDownloader  stopDownload];

    [self setCurrentlyChecking: NO];
}

-(void) internalUpdateSettingsHaveChanged {

    if (  self.currentlyUpdating  ) {
        [self appendUpdaterLog: @"internalUpdateSettingsHaveChanged being ignored because we are currently updating"];
        return;
    }

    if (  self.currentlyChecking  ) {
        [self appendUpdaterLog: @"internalUpdateSettingsHaveChanged so current update check is being stopped"];
        [self.appcastDownloader stopDownload];
        return;
    }

    [self checkIfAnUpdateIsAvailableForcingCheck: @NO];
}

-(void) updateCheckTimerTick: (NSTimer *) timer {

    if (  ! [NSThread mainThread]  ) {
        [self performSelectorOnMainThread: @selector(updateCheckTimerTick:) withObject: nil waitUntilDone: NO];
        [self appendUpdaterLog: [NSString stringWithFormat:
                                 @"updateCheckTimerTick: Not on main thread; stack trace = %@",
                                 callStack()]];
        return;
    }

    [self appendUpdaterLog: @"updateCheckTimerTick: invoked"];

    [self checkIfAnUpdateIsAvailableForcingCheck: @NO];
}

-(BOOL) canCheckForUpdatesWithPreferenceName: (nullable NSString *) preferenceName {

    if (  preferenceName  ) {
        if (  ! [gTbDefaults boolForKey: preferenceName]  ) {
            return NO;
        }
    }

    BOOL inhibitedByPref = [gTbDefaults boolForKey: @"inhibitOutboundTunneblickTraffic"];
    BOOL onlyWhenOnVPN = [gTbDefaults boolForKey: @"TBUpdaterCheckOnlyWhenConnectedToVPN"];
    BOOL result = (   ( ! gShuttingDownTunnelblick )
                   && ( ! self.inhibitUpdating )
                   && ( ! inhibitedByPref )
                   && (   ( ! onlyWhenOnVPN )
                       || self.areConnectedToVPN));

    [self appendUpdaterLog: [NSString stringWithFormat:
                             @"canCheckForUpdatesWithPreferenceName: %@ returning %s\n"
                             @"gShuttingDownTunnelblick = %s; inhibitUpdating = %s; inhibitOutboundTunneblickTraffic preference = %s; TBUpdaterCheckOnlyWhenConnectedToVPN = %s; connected to VPN = %s",
                             preferenceName, CSTRING_FROM_BOOL(result),
                             CSTRING_FROM_BOOL(gShuttingDownTunnelblick), CSTRING_FROM_BOOL(self.inhibitUpdating), CSTRING_FROM_BOOL(inhibitedByPref),
                             CSTRING_FROM_BOOL(onlyWhenOnVPN), CSTRING_FROM_BOOL(self.areConnectedToVPN)]];
    return result;
}

-(BOOL) canDownloadUpdatesAutomatically {

    if (  ! [gTbDefaults boolForKey: self.canDownloadUpdatesAutomaticallyPref]  ) {
        return NO;
    }

    BOOL inhibitedByPref = [gTbDefaults boolForKey: @"inhibitOutboundTunneblickTraffic"];
    BOOL result = (   ( ! gShuttingDownTunnelblick )
                   && ( ! self.inhibitUpdating )
                   && ( ! inhibitedByPref )
                   );

    [self appendUpdaterLog: [NSString stringWithFormat:
                             @"canDownloadUpdatesAutomatically: %@ returning %s; gShuttingDownTunnelblick = %s; inhibitUpdating = %s; inhibitOutboundTunneblickTraffic preference = %s",
                             self.canDownloadUpdatesAutomaticallyPref, CSTRING_FROM_BOOL(result),
                             CSTRING_FROM_BOOL(gShuttingDownTunnelblick), CSTRING_FROM_BOOL(self.inhibitUpdating), CSTRING_FROM_BOOL(inhibitedByPref)]];
    return result;
}

-(BOOL) areConnectedToVPN {

    unsigned nConnections = gMC.connectionArray.count;

    BOOL result = (nConnections > 0);
    return result;
}

//********************************************************************************
//
// Getters and Setters

-(NSString *) publicKey {

    if (  ! publicKey  ) {
        publicKey = [[self.infoPlistDictionary objectForKey: appcastPubKeyInInfoPlist] retain];
        if (  ! publicKey  ) {
            if (  ! self.warnedNoPublicKey  ) {
                [self notifyErrorMessage: @"Cannot get public key"];
                [self setWarnedNoPublicKey: TRUE];
                [self setInhibitUpdating: TRUE];
            }
        }

    }

    return [[publicKey retain] autorelease];
}

-(NSString *) appcastURLString {

    // Returns the string representation for the appcast URL, modified to insert "-b" or "-s" to get beta or stable update version

    if (  ! appcastURLString  ) {

        NSString * urlString = nil;

        // If the 'updateFeedURL' preference is being forced, use it
        if (  ! [gTbDefaults canChangeValueForKey: self.appcastURLPref]  ) {
            urlString = [gTbDefaults stringForKey: self.appcastURLPref];
            if (  urlString  ) {
                if (  [NSURL URLWithString: urlString]  ) {
                    [self appendUpdaterLog: [NSString stringWithFormat:
                                             @"Using %@ forced preference '%@'",
                                             self.appcastURLPref, urlString]];
                } else {
                    [self appendUpdaterLog: [NSString stringWithFormat:
                                             @"Ignoring %@ preference '%@' from 'forced-preferences.plist' because it could not be converted to a URL",
                                             self.appcastURLPref, urlString]];
                    urlString = nil;
                }
            }
        }

        // Otherwise, use the SUFeedURL entry in Info.plist
        if (  ! urlString  ) {
            urlString = [self.infoPlistDictionary objectForKey: self.appcastURLInInfoPlist];
            if (  urlString ) {
                if (  ! [[urlString class] isSubclassOfClass: [NSString class]]  ) {
                    [self appendUpdaterLog:  [NSString stringWithFormat:
                                              @"Ignoring %@ in Info.plist because it is not a string",
                                              self.appcastURLInInfoPlist]];
                    urlString = nil;
                }
                if (  ! [NSURL URLWithString: urlString]  ) {
                    [self appendUpdaterLog: [NSString stringWithFormat:
                                             @"Ignoring %@ in Info.plist because it could not be converted to a URL: %@",
                                             self.appcastURLInInfoPlist,
                                             urlString]];
                    urlString = nil;
                }
            } else {
                [self appendUpdaterLog: @"Missing 'SUFeedURL' item in Info.plist"];
            }
        }

        if (  ! urlString  ) {
            if (  ! self.warnedNoAppcastURL  ) {
                [self notifyErrorMessage: @"Error finding URL for checking updates"];
                [self setWarnedNoAppcastURL: TRUE];
                [self setInhibitUpdating: TRUE];
                return nil;
            }
        }

        // Add -b or -s before extension (for beta or stable version, respectively)
        //
        // Strip https:// and add it back in later because stringByDeletingPathExtension changes the "//" to "/"
        if (  [urlString hasPrefix: @"https://"]  ) {
            urlString = [urlString substringFromIndex: @"https://".length];
        } else {
            if (  ! self.warnedNoHttpsInAppcastURL  ) {
                [self notifyErrorMessage: [NSString stringWithFormat:
                                           @"Tunnelblick appcast URL does not start with 'https://': %@",
                                           urlString]];
                [self setWarnedNoHttpsInAppcastURL: TRUE];
                [self setInhibitUpdating: TRUE];
            }

            return nil;
        }

        NSString * urlWithoutExtension = urlString.stringByDeletingPathExtension;
        NSString * suffix = (  runningATunnelblickBeta()
                             ? @"-b"
                             : @"-s");
        urlString = [NSString stringWithFormat:
                     @"https://%@%@.%@",
                     urlWithoutExtension, suffix, urlString.pathExtension];

        appcastURLString = [urlString retain];
    }

    return [[appcastURLString retain] autorelease];
}

-(NSString *) currentTunnelblickVersionString {

    if (  ! currentTunnelblickVersionString  ) {
        currentTunnelblickVersionString = [tunnelblickVersion([NSBundle mainBundle]) retain];
        if (  ! currentTunnelblickVersionString  ) {
            if (  ! self.warnedNoCurrentTunnelblickVersion  ) {
                [self notifyErrorMessage: @"Error getting Tunnelblick version"];
                [self setWarnedNoCurrentTunnelblickVersion: TRUE];
                [self setInhibitUpdating: TRUE];
            }
        }
    }

    return [[currentTunnelblickVersionString retain] autorelease];
}

-(NSString *) currentBuild {

    if (  ! currentBuild  ) {
        currentBuild = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] retain];
        if (  ! currentBuild  ) {
            if (  ! self.warnedNoCurrentBuild  ) {
                [self notifyErrorMessage: @"Error getting Tunnelblick build number"];
                [self setWarnedNoCurrentBuild: TRUE];
                [self setInhibitUpdating: TRUE];
            }
        }

        return [[currentBuild retain] autorelease];
    }

    return [[currentBuild retain] autorelease];
}

-(NSString *) currentArchitecture {

    if (  ! currentArchitecture  ) {

        currentArchitecture = [architectureBeingUsed() retain];
        if (  ! currentArchitecture) {
            if (  ! self.warnedNoCurrentArchitecture  ) {
                [self notifyErrorMessage: @"Error getting architecture being used"];
                [self setWarnedNoCurrentArchitecture: TRUE];
                [self setInhibitUpdating: TRUE];
            }
        }
    }

    return [[currentArchitecture retain] autorelease];
}

-(NSString *) currentMacOSVersion {

    if (  ! currentMacOSVersion  ) {

        currentMacOSVersion = [[gTbInfo systemVersionString] retain];
    }

    return [[currentMacOSVersion retain] autorelease];
}

-(void) setUpdateCheckTimer: (NSTimer *) newValue {

    // Special-case setting the timer because it must be invalidated before it is released.

    [newValue retain];
    [updateCheckTimer invalidate];
    [updateCheckTimer release];
    updateCheckTimer = newValue;
}

-(NSTimer *) updateCheckTimer {

    return [[updateCheckTimer retain] autorelease];
}

-(void) setDebugLogFlushTimer: (NSTimer *) timer {

    [timer retain];
    [debugLogFlushTimer invalidate];
    [debugLogFlushTimer release];
    debugLogFlushTimer = timer;
}

-(NSDictionary *) infoPlistDictionary {

    if (  ! infoPlistDictionary  ) {
        infoPlistDictionary = [[gMC tunnelblickInfoDictionary] retain];
    }

    return [[infoPlistDictionary retain] autorelease];
}

// Information about a particular update
TBSYNTHESIZE_OBJECT(retain, NSDictionary *, updateInfo, setUpdateInfo)

TBSYNTHESIZE_OBJECT_GET(retain, NSString *, skipBuildPref)
TBSYNTHESIZE_OBJECT_GET(retain, NSString *, appcastURLPref)
TBSYNTHESIZE_OBJECT_GET(retain, NSString *, canDownloadUpdatesAutomaticallyPref)
TBSYNTHESIZE_OBJECT_GET(retain, NSString *, canCheckAutomaticallyPref)
TBSYNTHESIZE_OBJECT_GET(retain, NSString *, appcastURLInInfoPlist)
TBSYNTHESIZE_OBJECT_GET(retain, NSString *, appcastPubKeyInInfoPlist)
TBSYNTHESIZE_OBJECT_GET(retain, NSString *, delegate)
TBSYNTHESIZE_OBJECT_GET(retain, NSString *, downloadedUpdatePath)
TBSYNTHESIZE_OBJECT_GET(retain, NSString *, downloadedUpdateVersionStringPref)
TBSYNTHESIZE_OBJECT_GET(retain, NSString *, nonAdminCanUpdateAppPref)

// Information about appcast currently being downloaded
TBSYNTHESIZE_OBJECT(retain, NSMutableData   *, appcastContents,         setAppcastContents)
TBSYNTHESIZE_OBJECT(retain, TBDownloader    *, appcastDownloader,       setAppcastDownloader)
TBSYNTHESIZE_NONOBJECT(long long,              appcastLength,           setAppcastLength)
TBSYNTHESIZE_NONOBJECT(BOOL,                   appcastDownloadIsForced, setAppcastDownloadIsForced)

// Information about update currently being downloaded
TBSYNTHESIZE_OBJECT(retain, NSMutableData*, updateContents,   setUpdateContents)
TBSYNTHESIZE_OBJECT(retain, TBDownloader *, updateDownloader, setUpdateDownloader)

// Other
TBSYNTHESIZE_OBJECT_GET(retain, NSTimer      *, debugLogFlushTimer)

TBSYNTHESIZE_OBJECT(retain, AlertWindowController *, windowController, setWindowController)

TBSYNTHESIZE_NONOBJECT(NSTimeInterval, updateErrorDelay, setUpdateErrorDelay)

TBSYNTHESIZE_NONOBJECT(BOOL, notifiedAboutUpdateError,    setNotifiedAboutUpdateError)

TBSYNTHESIZE_NONOBJECT(BOOL, updateAuthorizedByUser,      setUpdateAuthorizedByUser)
TBSYNTHESIZE_NONOBJECT(BOOL, updateWasDownloaded,         setUpdateWasDownloaded)

TBSYNTHESIZE_NONOBJECT(BOOL, inhibitUpdating,             setInhibitUpdating)

TBSYNTHESIZE_NONOBJECT(BOOL, currentlyChecking,           setCurrentlyChecking)
TBSYNTHESIZE_NONOBJECT(BOOL, currentlyUpdating,           setCurrentlyUpdating)

TBSYNTHESIZE_NONOBJECT(BOOL, warnedNoPublicKey,           setWarnedNoPublicKey)
TBSYNTHESIZE_NONOBJECT(BOOL, warnedNoAppcastURL,          setWarnedNoAppcastURL)
TBSYNTHESIZE_NONOBJECT(BOOL, warnedNoHttpsInAppcastURL,   setWarnedNoHttpsInAppcastURL)
TBSYNTHESIZE_NONOBJECT(BOOL, warnedNoCurrentTunnelblickVersion, setWarnedNoCurrentTunnelblickVersion)
TBSYNTHESIZE_NONOBJECT(BOOL, warnedNoCurrentBuild,        setWarnedNoCurrentBuild)
TBSYNTHESIZE_NONOBJECT(BOOL, warnedNoCurrentArchitecture, setWarnedNoCurrentArchitecture)

TBSYNTHESIZE_NONOBJECT(double,    percentDownloaded, setPercentDownloaded)
TBSYNTHESIZE_NONOBJECT_GET(BOOL,  isAppUpdate)

@end
