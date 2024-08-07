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

#import <Foundation/Foundation.h>

@class TBDownloader;

NS_ASSUME_NONNULL_BEGIN

@class AlertWindowController;
@class TBValidator;

@interface TBUpdater : NSObject

{
    TBValidator * validator;            // Validates signatures
    
    FILE * logFile;

    BOOL isAppUpdate;                   // Flag that this instance is an application updater, not a configuration updater
    //                                  // NOTE: configuration updating code is not yet written

    // Info that varies, depending on whether updating an app or a configuration
    NSString * appcastURLInInfoPlist;   // Info.plist key containing containing the URL for the appcast
    NSString * appcastPubKeyInInfoPlist;// Info.plist key containing containing the public key for the appcast's signature
    NSString * skipBuildPref;           // TBUserDefaults key containing a build to skip updating to
    NSString * appcastURLPref;          // TBUserDefaults key containing the URL for the appcast (must be forced)
    NSString * canDownloadUpdatesAutomaticallyPref;  // TBUserDefaults key, TRUE if can download updates before user clicks "Install"
    NSString * canCheckAutomaticallyPref;// TBUserDefaults key, TRUE if can check for updates automatically
    NSString * nonAdminCanUpdateAppPref;// TBUserDefaults key, TRUE if non-admin can update (must be forced)
    NSString * downloadedUpdateVersionStringPref;   // Preference containing version string for the Tunnelblick.app in downloaded tunnelblick-update.zip
    NSString * downloadedUpdatePath;    // Path to download tunnelblick-update.zip to (subfolder of ~/Library/Application Support/Tunnelblick)

    id         delegate;                // Instance of class to notify (for application, gMC, for connection, ??????)
    
    // Info for an appropriate update, obtained from the appcast (nil if no update is appropriate):
    NSDictionary * updateInfo;

    NSString * currentTunnelblickVersionString; // Info about currently installed Tunnelblick, Mac, and macOS,
    NSString * currentBuild;
    NSString * currentArchitecture;
    NSString * currentMacOSVersion;

    NSDictionary * infoPlistDictionary; // This app's Info.plist data

    NSString * appcastURLString;        // Obtain update information from this URL
    //                                  // (From updateFeedURL preference, which must be forced
    //                                  //  or from SUFeedURL in Info.plist)

    NSString * publicKey;               // Public key for the appcast and update signatures
    //                                  // (From SUPublicDSAKey in Info.plist)

    NSTimer * updateCheckTimer;         // Check for updates when this timer ticks

    NSTimer * debugLogFlushTimer;       // When triggered, the debug log file should be closed and reopened to append.

    NSTimeInterval updateErrorDelay;    // Delay after error in automatic check before trying again
    //                                  // Doubles on every error to a maximum of 300 seconds

    AlertWindowController * windowController;   // Window that asks user if an update should be installed/downloaded

    BOOL appcastDownloadIsForced;       // Appcast is being downloaded because "Check Now" button was clicked (i.e., not automatic check)
    TBDownloader * appcastDownloader;   // Downloader for appcast
    NSMutableData * appcastContents;    // The appcast .rss as downloaded
    long long appcastLength;            // Length of appcast (from connection:didReceiveResponse:)
    //                                  // NOTE: Could be NSURLResponseUnknownLength

    TBDownloader * updateDownloader;    // Downloader for update .zip
    NSMutableData * updateContents;     // The update .zip as downloaded
    double percentDownloaded;           // Percentage of the update that has been downloaded
    //                                  // 0.0 to 99.0 until completely downloaded, then 100.0

    BOOL inhibitUpdating;               // Flag that inhibits all updating activity (e.g. we are uninstalling)

    BOOL updateAvailable;               // An update is available
    BOOL updateAuthorizedByUser;        // User has approved installing the update

    BOOL currentlyChecking;             // Checking for an update
    BOOL currentlyUpdating;             // An update is currently taking place

    BOOL updateWasDownloaded;           // The update .zip has been downloaded

    BOOL notifiedAboutUpdateError;          // We have invoked [gMC tbUpdateErrorOccurredInAppUpdate:]

    BOOL warnedNoPublicKey;                 // Have warned that the public key could not be obtained
    BOOL warnedNoAppcastURL;                // Have warned that the appcast URL could not be obtained
    BOOL warnedNoHttpsInAppcastURL;         // Have warned that the appcast URL did not start with https:
    BOOL warnedNoCurrentTunnelblickVersion; // Have warned that the version of the current Tunnelblick could not be obtained
    BOOL warnedNoCurrentBuild;              // Have warned that the build of the current Tunnelblick could not be obtained
    BOOL warnedNoCurrentArchitecture;       // Have warned that the architecture of the current Tunnelblick could not be obtained
}

-(TBUpdater *) initFor: (NSString *) _type
          withDelegate: (id)         _delegate;

// Stop all updating activity, regardless of preferences (usually when Tunnelblick is about to quit).
-(void) stopAllUpdateActivity;

-(BOOL) currentlyUpdating;

// Invoked to force an update check (even if **automatic** checks are not allowed).
// Presumably triggered by a "Check now" button.
// If an update is available
// Then start downloading the update if that's allowed, invoke the delegate's
//      tbUpdateIsAvailable: indicating an update is available, and display a non-modal
//      window with details about the update and buttons for the user to act.
// If no update is available, displays a non-modal window saying no update is available.
-(void) nonAutomaticCheckIfAnUpdateIsAvailable;

// The settings (preferences) that involve the TBUpdater have changed.
// Triggers an automatic update check
// If an update is available
// Then start downloading the update if that's allowed, and invoke the delegate's
//      tbUpdateIsAvailable: indicating an update is available.
// If no update is available nothing is done.
-(void) updateSettingsHaveChanged;

// Presents a dialog to the user with the current and proposed version info, the
// update notes, and "Install" and "Skip This Update", and "Remind Me Later" buttons.
//
// Note: updating the application results in the termination of this instance
// of the Tunnelblick application.
-(void) offerUpdateAndInstallIfUserAgrees;

@end

NS_ASSUME_NONNULL_END
