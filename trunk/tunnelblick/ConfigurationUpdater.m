/*
 * Copyright 2011, 2012, 2013, 2014 Jonathan K. Bullard. All rights reserved.
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
TBSYNTHESIZE_NONOBJECT(         BOOL,        checking,       setChecking)
TBSYNTHESIZE_NONOBJECT(         BOOL,        checkingWithUI, setCheckingWithUI)


-(ConfigurationUpdater *) initWithPath: (NSString *) path {
    
    // Returns nil if not a valid bundle at 'path' or no valid Info.plist in the bundle, or no valid SUFeedURL or no CFBundleVersion in the Info.plist
    
    NSString * plistPath = [[path stringByAppendingPathComponent: @"Contents"]
                            stringByAppendingPathComponent: @"Info.plist"];
    NSDictionary * infoPlist = [NSDictionary dictionaryWithContentsOfFile: plistPath];
    if (  ! infoPlist  ) {
        NSLog(@"%@ exists, but does not contain a valid Info.plist", path);
        return nil;
    }
    
    id obj = [infoPlist objectForKey: @"CFBundleIdentifier"];
    if (   ( ! obj)
        || ( ! [[obj class] isSubclassOfClass: [NSString class]])  ) {
        NSLog(@"%@ does not contain a CFBundleIdentifier string", plistPath);
        return nil;
    }
    obj = [infoPlist objectForKey: @"CFBundleVersion"];
    if (   ( ! obj)
        || ( ! [[obj class] isSubclassOfClass: [NSString class]])  ) {
        NSLog(@"%@ does not contain CFBundleVersion string", plistPath);
        return nil;
    }
    
    obj = [infoPlist objectForKey: @"SUFeedURL"];
    if (   ( ! obj)
        || ( ! [[obj class] isSubclassOfClass: [NSString class]])  ) {
        NSLog(@"%@ does not contain SUFeedURL string", plistPath);
        return nil;
    }
    NSURL * feedURL = [NSURL URLWithString: (NSString *) obj];
    if (  ! feedURL  ) {
        NSLog(@"SUFeedURL in %@ is not a valid URL", plistPath);
        return nil;
    }
    
    NSTimeInterval interval = 60*60; // One hour (1 hour in seconds = 60 minutes * 60 seconds/minute)
    id checkInterval = [infoPlist objectForKey: @"SUScheduledCheckInterval"];
    if (  checkInterval  ) {
        if (  [checkInterval respondsToSelector: @selector(intValue)]  ) {
            NSTimeInterval i = (NSTimeInterval) [checkInterval intValue];
            if (  i <= 60.0  ) {
                NSLog(@"SUScheduledCheckInterval in %@ is less than 60 seconds; using 60 minutes.", plistPath);
            } else {
                interval = i;
            }
        } else {
            NSLog(@"SUScheduledCheckInterval in %@ is invalid; using 60 minutes", plistPath);
        }
    }
    
    NSBundle * bundle = [NSBundle bundleWithPath: path];
	if (  ! bundle  ) {
        NSLog(@"%@ is not a valid bundle", path);
        return nil;
    }
    
    if (  (self = [super init])  ) {
        cfgBundlePath  = [path retain];
        cfgUpdater     = [SUUpdater updaterForBundle: bundle];
        cancelling     = FALSE;
		checking       = FALSE;
		checkingWithUI = FALSE;
        
        [cfgUpdater setDelegate:                      self];
        [cfgUpdater setFeedURL:                       feedURL];
        [cfgUpdater setUpdateCheckInterval:           interval];
        [cfgUpdater setAutomaticallyChecksForUpdates: NO];      // Don't start checking yet
        [cfgUpdater setAutomaticallyDownloadsUpdates: NO];      // MUST BE 'NO' because "Install" on Quit doesn't work properly
        [cfgUpdater setSendsSystemProfile:            NO];      // See https://answers.edge.launchpad.net/sparkle/+question/88790
        
        return self;
    }

    return nil;
}

-(void) dealloc {
    
	[cfgBundlePath release]; cfgBundlePath = nil;
    [cfgUpdater    release]; cfgUpdater    = nil;
    
    [super dealloc];
}

-(NSString *) cfgBundleIdentifier {
    
    return [[cfgBundlePath lastPathComponent] stringByDeletingPathExtension];
}

-(void) startCheckingWithUI {
	
	[self setChecking:       YES];
	[self setCheckingWithUI: YES];
	
	TBLog(@"DB-UC", @"Starting update check with UI for configuration '%@'; URL = %@", [self cfgBundleIdentifier], [cfgUpdater feedURL]);
    
	[cfgUpdater checkForUpdates: self];
	[cfgUpdater resetUpdateCycle];
}

-(void) startCheckingWithoutUI {
	
	[self setChecking:       YES];
	[self setCheckingWithUI: NO];
	
	TBLog(@"DB-UC", @"Starting update check without UI for configuration '%@'; URL = %@", [self cfgBundleIdentifier], [cfgUpdater feedURL]);
    
	[cfgUpdater checkForUpdatesInBackground];
	[cfgUpdater resetUpdateCycle];
}

-(void) startCheckingWithUIThread: (NSNumber *) withUINumber {
    
    // Waits until the app is not being updated, then starts the updater checking for updates
    // [withUINumber boolValue] should be TRUE to present the UI, FALSE to check in the background
    //
    // Invoked in a new thread. Waits until the app isn't being updated, then schedules itself to start checking on the main thread, then exits the thread.

    NSAutoreleasePool * threadPool = [NSAutoreleasePool new];
    
    if (  [gTbDefaults boolForKey: @"inhibitOutboundTunneblickTraffic"]) {
		[threadPool drain];
        return;
    }
    
    if (  ! [withUINumber respondsToSelector: @selector(boolValue)]  ) {
        NSLog(@"startCheckingWithUIThread: invalid argument '%@' (a '%@' does not respond to 'boolValue')", withUINumber, [withUINumber className]);
		[threadPool drain];
        return;
    }
    BOOL withUI = [withUINumber boolValue];
    
    // Wait until the application is not being updated
    SUUpdater * appUpdater = [[NSApp delegate] updater];
    while (  [appUpdater updateInProgress]  ) {
        TBLog(@"DB-UC", @"Delaying start of update check for configuration set %@", [self cfgBundleIdentifier]);
        sleep(1);
    }
    
    if (  withUI  ) {
		[self performSelectorOnMainThread: @selector(startCheckingWithUI)    withObject: nil waitUntilDone: NO];
    } else {
		[self performSelectorOnMainThread: @selector(startCheckingWithoutUI) withObject: nil waitUntilDone: NO];
    }
    
    [threadPool drain];
}

-(void) startCheckingWithUI: (NSNumber *) withUI {
	
	[NSThread detachNewThreadSelector: @selector(startCheckingWithUIThread:) toTarget: self withObject: withUI];
}

-(void) stopChecking {
    
	[cfgUpdater setAutomaticallyChecksForUpdates: NO];
	TBLog(@"DB-UC", @"Removed Sparkle updater for %@", [cfgBundlePath lastPathComponent]);
}

//************************************************************************************************************
// SUUpdater delegate methods

- (BOOL)updaterShouldPromptForPermissionToCheckForUpdates:(SUUpdater *)bundle {
    
	// Use this to override the default behavior for Sparkle prompting the user about automatic update checks.
    
    (void) bundle;
	
    TBLog(@"DB-UC", @"cfgUpdater 0x%lx: updaterShouldPromptForPermissionToCheckForUpdates", (unsigned long)self);
    return NO;
}

- (BOOL)updaterShouldRelaunchApplication:(SUUpdater *)updater {
	
    // This is an additional delegate method for Tunnelblick.
    // It allows Tunnelblick to return NO and update configurations without relaunching the application.
	
    (void) updater;
	
    TBLog(@"DB-UC", @"cfgUpdater 0x%lx: updaterShouldRelaunchApplication", (unsigned long)self);
	
    if (   gShuttingDownWorkspace
        || cancelling  ) {
        return NO;
    }
    
	[[NSApp delegate] performSelectorOnMainThread: @selector(installConfigurationsUpdateInBundleAtPathHandler:) withObject: [self cfgBundlePath] waitUntilDone: NO];
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
    
    TBLog(@"DB-UC", @"cfgUpdater 0x%lx: didFinishLoadingAppcast", (unsigned long)self);
}

-(void)    updater: (SUUpdater *)    updater
didFindValidUpdate:(SUAppcastItem *) update {
    
    // Sent when a valid update is found by the update driver.
    
    (void) updater;
    (void) update;
    
    TBLog(@"DB-UC", @"cfgUpdater 0x%lx: didFindValidUpdate", (unsigned long)self);
}

-(void) updaterDidNotFindUpdate: (SUUpdater *) update {
    
    // Sent when a valid update is not found.
    
    (void) update;
    
    TBLog(@"DB-UC", @"cfgUpdater 0x%lx: updaterDidNotFindUpdate", (unsigned long)self);
}

- (void)updater:(SUUpdater *)updater willInstallUpdate:(SUAppcastItem *)update {
    
	(void) updater;
    (void) update;
	
    TBLog(@"DB-UC", @"cfgUpdater 0x%lx: willInstallUpdate", (unsigned long)self);
}

- (void)installerFinishedForHost:(SUHost *)host {
	
	(void) host;
	
    TBLog(@"DB-UC", @"cfgUpdater 0x%lx: installerFinishedForHost", (unsigned long)self);
}

- (NSString *)pathToRelaunchForUpdater:(SUUpdater *)updater {
    
    // Returns the path which is used to relaunch the client after the update is installed. By default, the path of the host bundle.
    
	(void) updater;
	
    TBLog(@"DB-UC", @"cfgUpdater 0x%lx: pathToRelaunchForUpdater", (unsigned long)self);
	return nil;
}

- (void) updaterWillRelaunchApplication: (SUUpdater *) updater {
    
    // Called immediately before relaunching.
    
    (void) updater;
    
    TBLog(@"DB-UC", @"cfgUpdater 0x%lx: updaterWillRelaunchApplication", (unsigned long)self);
}

@end
