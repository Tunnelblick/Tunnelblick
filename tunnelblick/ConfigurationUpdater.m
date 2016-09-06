/*
 * Copyright 2011, 2012, 2013, 2014, 2015, 2016 Jonathan K. Bullard. All rights reserved.
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


#import "ConfigurationUpdater.h"

#import "defines.h"
#import "helper.h"
#import "sharedRoutines.h"
#import "NSString+TB.h"

#import "ConfigurationManager.h"
#import "ConfigurationMultiUpdater.h"
#import "MenuController.h"
#import "NSFileManager+TB.h"
#import "NSTimer+TB.h"
#import "Sparkle/SUUpdater.h"
#import "TBUserDefaults.h"

extern NSFileManager        * gFileMgr;
extern BOOL                   gShuttingDownWorkspace;
extern TBUserDefaults       * gTbDefaults;

@implementation ConfigurationUpdater

TBSYNTHESIZE_OBJECT_GET(retain, SUUpdater *, cfgUpdater)
TBSYNTHESIZE_OBJECT_GET(retain, NSString  *, cfgBundlePath)
TBSYNTHESIZE_OBJECT_GET(retain, NSString  *, cfgBundleId)
TBSYNTHESIZE_OBJECT_GET(retain, NSString  *, cfgName)

-(NSString *) edition {
	
	return [[[self cfgBundlePath] stringByDeletingLastPathComponent] pathEdition];
}

-(ConfigurationUpdater *) initWithPath: (NSString *) path {
    
    // Returns nil if error
    
    if (  ! [path hasSuffix: @".tblk"]  ) {
        NSLog(@"%@ is not a .tblk", path);
        return nil;
    }
    
    NSBundle * bundle = [NSBundle bundleWithPath: path];
	if (  ! bundle  ) {
        NSLog(@"%@ is not a valid bundle", path);
        return nil;
    }
    
    NSDictionary * infoPlist = [ConfigurationManager plistInTblkAtPath: path];
    
    if (  ! infoPlist  ) {
        NSLog(@"The .tblk at %@ does not contain a valid Info.plist", path);
        return nil;
    }
    
    NSString * bundleId      = [infoPlist objectForKey: @"CFBundleIdentifier"];
    NSString * bundleVersion = [infoPlist objectForKey: @"CFBundleVersion"];
    NSString * feedURLString = [infoPlist objectForKey: @"SUFeedURL"];
    
    if (  ! (   bundleId
             && bundleVersion
             && feedURLString)  ) {
        NSLog(@"Missing CFBundleIdentifier, CFBundleVersion, or SUFeedURL in Info.plist for .tblk at %@", path);
        return nil;
    }
    
    NSURL * feedURL = [NSURL URLWithString: feedURLString];
    if (  ! feedURL  ) {
        NSLog(@"SUFeedURL in Info.plist for .tblk at %@ is not a valid URL", path);
        return nil;
    }
    
    NSTimeInterval interval = 60*60; // One hour (1 hour in seconds = 60 minutes * 60 seconds/minute)
    id checkInterval = [infoPlist objectForKey: @"SUScheduledCheckInterval"];
    if (  checkInterval  ) {
        if (  [checkInterval respondsToSelector: @selector(intValue)]  ) {
            NSTimeInterval i = (NSTimeInterval) [checkInterval intValue];
            if (  i <= 60.0  ) {
                NSLog(@"SUScheduledCheckInterval in Info.plist for the .tblk at %@ is less than 60 seconds; using 60 minutes.", path);
            } else {
                interval = i;
            }
        } else {
            NSLog(@"SUScheduledCheckInterval in Info.plist for the .tblk at %@ is invalid (does not respond to intValue); using 3600 seconds (60 minutes)", path);
        }
    }
    
    if (  (self = [super init])  ) {
        
        cfgBundlePath = [path retain];
        cfgBundleId   = [bundleId retain];
        cfgName       = [[path lastPathComponent] retain];
        
        cfgUpdater    = [[SUUpdater updaterForBundle: [NSBundle bundleWithPath: path]] retain];
        if (  cfgUpdater  ) {
            [cfgUpdater setAutomaticallyChecksForUpdates: NO];      // Don't start checking yet
            [cfgUpdater setAutomaticallyDownloadsUpdates: NO];      // MUST BE 'NO' because "Install" on Quit doesn't work properly
            [cfgUpdater setSendsSystemProfile:            NO];      // See https://answers.edge.launchpad.net/sparkle/+question/88790
            [cfgUpdater setUpdateCheckInterval:           interval];
            [cfgUpdater setDelegate:                      (id)self];
            [cfgUpdater setFeedURL:                       feedURL];
        } else {
            NSLog(@"Unable to create an updater for %@", path);
        }
        
        return self;
    }

    return nil;
}

-(void) dealloc {
    
	[cfgBundlePath release]; cfgBundlePath = nil;
	[cfgBundleId   release]; cfgBundleId   = nil;
	[cfgName       release]; cfgName       = nil;
	[cfgUpdater    release]; cfgUpdater    = nil;
    
    [super dealloc];
}

-(void) startUpdateCheckingWithUI {
	
	if (  [gTbDefaults boolForKey: @"inhibitOutboundTunneblickTraffic"]) {
		return;
	}
	
	[[self cfgUpdater] resetUpdateCycle];
	[[self cfgUpdater] checkForUpdates: self];
	
	TBLog(@"DB-UC", @"Started update check with UI for configuration '%@' (%@); URL = %@", [self cfgBundleId], [self edition], [cfgUpdater feedURL]);
}

-(void) startCheckingWithoutUI {
	
	if (  [gTbDefaults boolForKey: @"inhibitOutboundTunneblickTraffic"]) {
		return;
	}
	
	NSString * action = (  [[self cfgUpdater] automaticallyChecksForUpdates]
						 ? @"Restarted"
						 : @"Started");
	
	[[self cfgUpdater] resetUpdateCycle];
	[[self cfgUpdater] checkForUpdatesInBackground];
	
	TBLog(@"DB-UC", @"%@ update checks without UI for configuration '%@' (%@); URL = %@", action, [self cfgBundleId], [self edition], [cfgUpdater feedURL]);
}

-(void) startUpdateCheckingWithUIThread: (NSNumber *) withUINumber {
    
    // Invoked in a new thread. Waits until the app isn't being updated, then schedules itself to start checking on the main thread, then exits the thread.
    // [withUINumber boolValue] should be TRUE to present the UI, FALSE to check in the background

    NSAutoreleasePool * threadPool = [NSAutoreleasePool new];
    
    if (  ! [withUINumber respondsToSelector: @selector(boolValue)]  ) {
        NSLog(@"startUpdateCheckingWithUIThread: invalid argument '%@' (a '%@' does not respond to 'boolValue')", withUINumber, [withUINumber className]);
		[threadPool drain];
        return;
    }
    
    BOOL withUI = [withUINumber boolValue];
    
    // Wait until the application is not being updated
    SUUpdater * appUpdater = [((MenuController *)[NSApp delegate]) updater];
    while (  [appUpdater updateInProgress]  ) {
        
		if (  [gTbDefaults boolForKey: @"inhibitOutboundTunneblickTraffic"]) {
			[threadPool drain];
			return;
		}
        TBLog(@"DB-UC", @"Delaying start of update checks for configuration '%@' (%@)", [self cfgBundleId], [self edition]);
        sleep(1);
        
    }
    
    if (  withUI  ) {
		[self performSelectorOnMainThread: @selector(startUpdateCheckingWithUI) withObject: nil waitUntilDone: NO];
    } else {
		[self performSelectorOnMainThread: @selector(startCheckingWithoutUI)    withObject: nil waitUntilDone: NO];
    }
    
    [threadPool drain];
}

-(void) startUpdateCheckingWithUI: (NSNumber *) withUI {
	
	if (  ! [gTbDefaults boolForKey: @"inhibitOutboundTunneblickTraffic"]) {
        [NSThread detachNewThreadSelector: @selector(startUpdateCheckingWithUIThread:) toTarget: self withObject: withUI];
    }
}

-(void) stopChecking {
    
	if (  [[self cfgUpdater] automaticallyChecksForUpdates]  ) {
		[[self cfgUpdater] setAutomaticallyChecksForUpdates: NO];
		TBLog(@"DB-UC", @"Stopped update checks for configuration '%@' (%@)", [self cfgBundleId], [self edition]);
	} else {
		TBLog(@"DB-UC", @"Update checks are already stopped for configuration '%@' (%@)", [self cfgBundleId], [self edition]);
	}

}

//************************************************************************************************************
// SUUpdater delegate methods

- (BOOL)updaterShouldPromptForPermissionToCheckForUpdates:(SUUpdater *)bundle {
    
	// Use this to override the default behavior for Sparkle prompting the user about automatic update checks.
    
    (void) bundle;
	
    TBLog(@"DB-UC", @"updaterShouldPromptForPermissionToCheckForUpdates for '%@' (%@ %@)", [self cfgName], [self cfgBundleId], [self edition]);
    return NO;
}

- (BOOL)updaterShouldRelaunchApplication:(SUUpdater *)updater {
	
    // This is an additional delegate method for Tunnelblick.
    // It allows Tunnelblick to return NO and update configurations without relaunching the application.
	
    (void) updater;
	
    TBLog(@"DB-UC", @"updaterShouldRelaunchApplication for '%@' (%@ %@)", [self cfgName], [self cfgBundleId], [self edition]);
	
    if (  gShuttingDownWorkspace  ) {
        return NO;
    }
    
    if (  ! [((MenuController *)[NSApp delegate]) launchFinished]  ) {
        if (  [NSThread isMainThread]  ) {
            NSLog(@"updaterShouldRelaunchApplication: launchFinished = FALSE but are on the main thread, so not waiting for launchFinished");
        } else {
            // We are not on the main thread, so we make sure that Tunneblick has finished launching and the main thread is ready before we proceed to update the configuration.
            while (  [((MenuController *)[NSApp delegate]) launchFinished]  ) {
                sleep(1);
            }
        }
    }
    
	[((MenuController *)[NSApp delegate]) performSelectorOnMainThread: @selector(installConfigurationsUpdateInBundleAtPathMainThread:) withObject: [self cfgBundlePath] waitUntilDone: NO];
	return NO;
}

//
// None of the rest of the delegate methods are used but they show the progress of the update checks
//

-(void)         updater: (SUUpdater *) updater
didFinishLoadingAppcast: (SUAppcast *) appcast {
    
    // Implement this if you want to do some special handling with the appcast once it finishes loading.
    
    (void) updater;
    (void) appcast;
    
    TBLog(@"DB-UC", @"didFinishLoadingAppcast for '%@' (%@ %@)", [self cfgName], [self cfgBundleId], [self edition]);
}

-(void)    updater: (SUUpdater *)    updater
didFindValidUpdate:(SUAppcastItem *) update {
    
    // Sent when a valid update is found by the update driver.
    
    (void) updater;
    (void) update;
    
    TBLog(@"DB-UC", @"didFindValidUpdate for '%@' (%@ %@)", [self cfgName], [self cfgBundleId], [self edition]);
}

-(void) updaterDidNotFindUpdate: (SUUpdater *) update {
    
    // Sent when a valid update is not found.
    
    (void) update;
    
    TBLog(@"DB-UC", @"updaterDidNotFindUpdate for '%@' (%@ %@)", [self cfgName], [self cfgBundleId], [self edition]);
}

- (void)updater:(SUUpdater *)updater willInstallUpdate:(SUAppcastItem *)update {
    
	(void) updater;
    (void) update;
	
    TBLog(@"DB-UC", @"willInstallUpdate for '%@' (%@ %@)", [self cfgName], [self cfgBundleId], [self edition]);
}

- (void)installerFinishedForHost:(id)host {
	
	(void) host;
	
    TBLog(@"DB-UC", @"installerFinishedForHost for '%@' (%@ %@)", [self cfgName], [self cfgBundleId], [self edition]);
}

- (NSString *)pathToRelaunchForUpdater:(SUUpdater *)updater {
    
    // Returns the path which is used to relaunch the client after the update is installed. By default, the path of the host bundle.
    
	(void) updater;
	
    TBLog(@"DB-UC", @"pathToRelaunchForUpdater for '%@' (%@ %@)", [self cfgName], [self cfgBundleId], [self edition]);
	return nil;
}

- (void) updaterWillRelaunchApplication: (SUUpdater *) updater {
    
    // Called immediately before relaunching.
    
    (void) updater;
    
    TBLog(@"DB-UC", @"updaterWillRelaunchApplication for '%@' (%@ %@)", [self cfgName], [self cfgBundleId], [self edition]);
}

@end
