/*
 * Copyright 2011 Jonathan Bullard
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
#import "MenuController.h"
#import "NSFileManager+TB.h"
#import "helper.h"

extern NSFileManager        * gFileMgr;

@implementation ConfigurationUpdater

-(ConfigurationUpdater *) init
{
    // Returns nil if no bundle to be updated, or no valid Info.plist in the bundle, or no valid feedURL or no CFBundleVersion in the Info.plist
    
    NSBundle * bundle = [NSBundle bundleWithPath: CONFIGURATION_UPDATES_BUNDLE_PATH];
	if (  bundle  ) {
        NSString * plistPath = [CONFIGURATION_UPDATES_BUNDLE_PATH stringByAppendingPathComponent: @"Contents/Info.plist"];
        NSDictionary * infoPlist = [NSDictionary dictionaryWithContentsOfFile: plistPath];
        if ( infoPlist  ) {
            NSString *  feedURLString = [infoPlist objectForKey: @"SUFeedURL"];
            if (   feedURLString  ) {
                NSURL * feedURL = [NSURL URLWithString: feedURLString];
                if (  feedURL  ) {
                    if (  [infoPlist objectForKey: @"CFBundleVersion"]) {
                        
                        // Check configurations every hour as a default (Sparkle default is every 24 hours)
                        NSTimeInterval interval = 60*60; // Default is one hour
                        id checkInterval = [infoPlist objectForKey: @"SUScheduledCheckInterval"];
                        if (  checkInterval  ) {
                            if (  [checkInterval respondsToSelector: @selector(intValue)]  ) {
                                NSTimeInterval i = (NSTimeInterval) [checkInterval intValue];
                                if (  i == 0  ) {
                                    NSLog(@"SUScheduledCheckInterval in %@ is invalid or zero", plistPath);
                                } else {
                                    interval = i;
                                }
                            } else {
                                NSLog(@"SUScheduledCheckInterval in %@ is invalid", plistPath);
                            }
                        }
                        
                        // Copy the bundle to a temporary folder (so it is writable by the updater, which runs as a user)
                        NSString * tempBundlePath = [[newTemporaryDirectoryPath() autorelease]
                                                     stringByAppendingPathComponent: [CONFIGURATION_UPDATES_BUNDLE_PATH lastPathComponent]];
                        
                        if (   [gFileMgr tbCopyPath: CONFIGURATION_UPDATES_BUNDLE_PATH toPath: tempBundlePath handler: nil]  ) {
                            NSBundle * tempBundle = [NSBundle bundleWithPath: tempBundlePath];
                            if (  tempBundle  ) {
                                if (  self = [super init]  ) {
                                    cfgBundlePath = [tempBundlePath retain];
                                    cfgBundle = [tempBundle retain];
                                    cfgUpdater = [[SUUpdater updaterForBundle: cfgBundle] retain];
                                    cfgFeedURL = [feedURL copy];
                                    cfgCheckInterval = interval;
                                    
                                    [cfgUpdater setDelegate:                      self];
                                    
                                    [cfgUpdater setAutomaticallyChecksForUpdates: YES];
                                    [cfgUpdater setFeedURL:                       cfgFeedURL];
                                    [cfgUpdater setUpdateCheckInterval:           cfgCheckInterval];
                                    [cfgUpdater setAutomaticallyDownloadsUpdates: NO];                  // MUST BE 'NO' because "Install" on Quit doesn't work properly
                                    //  [cfgUpdater setSendsSystemProfile:            NO];
                                    
                                    return self;
                                }
                            } else {
                                NSLog(@"%@ is not a valid bundle", tempBundlePath);
                            }
                        } else {
                            NSLog(@"Unable to copy %@ to a temporary folder", CONFIGURATION_UPDATES_BUNDLE_PATH);
                        }
                        
                    } else {
                        NSLog(@"%@ does not contain CFBundleVersion", plistPath);
                    }
                    
                } else {
                    NSLog(@"SUFeedURL in %@ is not a valid URL", plistPath); 
                }
                
            } else {
                NSLog(@"%@ does not contain SUFeedURL", plistPath);
            }
        } else {
            NSLog(@"%@ exists, but does not contain a valid Info.plist", CONFIGURATION_UPDATES_BUNDLE_PATH);
        }
    }
    
    return nil;
}

-(void) dealloc
{
    [cfgBundlePath release];
    [cfgUpdater release];
    [cfgBundle release];
    [cfgFeedURL release];
    [super dealloc];
}

-(void) setup
{
}

-(void) startWithUI: (BOOL) withUI
{
    static double waitTime = 0.5;
    SUUpdater * appUpdater = [[NSApp delegate] updater];
    if (  [appUpdater updateInProgress]  ) {
        // The app itself is being updated, so we wait a while and try again
        // We wait 1, 2, 4, 8, 16, 32, 60, 60, 60... seconds
        waitTime = waitTime * 2;
        if (  waitTime > 60.0  ) {
            waitTime = 60.0;
        }
        [NSTimer scheduledTimerWithTimeInterval: (NSTimeInterval) waitTime
                                         target: self
                                       selector: @selector(startFromTimerHandler:)
                                       userInfo: [NSNumber numberWithBool: withUI]
                                        repeats: NO];
        return;
        waitTime = 0.5;
    }
    
    [cfgUpdater resetUpdateCycle];
    if (  withUI  ) {
        [cfgUpdater checkForUpdates: self];
    } else {
        [cfgUpdater checkForUpdatesInBackground];
    }
}

-(void) startFromTimerHandler: (NSTimer *) timer
{
    [self startWithUI: [[timer userInfo] boolValue]];
}
     
//************************************************************************************************************
// SUUpdater delegate methods

// Use this to override the default behavior for Sparkle prompting the user about automatic update checks.
- (BOOL)updaterShouldPromptForPermissionToCheckForUpdates:(SUUpdater *)bundle
{
    NSLog(@"cfgUpdater: updaterShouldPromptForPermissionToCheckForUpdates");
    return NO;
}

// Returns the path which is used to relaunch the client after the update is installed. By default, the path of the host bundle.
- (NSString *)pathToRelaunchForUpdater:(SUUpdater *)updater
{
    return [[NSBundle mainBundle] bundlePath];
}


// Return YES to delay the relaunch until you do some processing; invoke the given NSInvocation to continue.
- (BOOL)updater:(SUUpdater *)updater shouldPostponeRelaunchForUpdate:(SUAppcastItem *)update untilInvoking:(NSInvocation *)invocation
{
    [[NSApp delegate] saveConnectionsToRestoreOnRelaunch];
    [[NSApp delegate] installConfigurationsUpdateInBundleAtPathHandler: cfgBundlePath];
    return NO;
}

//************************************************************************************************************
/*/ Use for debugging by deleting the asterisk in this line

// Sent when a valid update is found by the update driver.
- (void)updater:(SUUpdater *)updater didFindValidUpdate:(SUAppcastItem *)update
{
    NSLog(@"cfgUpdater: didFindValidUpdate");
}

// Sent when a valid update is not found.
- (void)updaterDidNotFindUpdate:(SUUpdater *)update
{
    NSLog(@"cfgUpdater: updaterDidNotFindUpdate");
}

// Implement this if you want to do some special handling with the appcast once it finishes loading.
- (void)updater:(SUUpdater *)updater didFinishLoadingAppcast:(SUAppcast *)appcast
{
    NSLog(@"cfgUpdater: didFinishLoadingAppcast");
}

// Sent immediately before installing the specified update.
- (void)updater:(SUUpdater *)updater willInstallUpdate:(SUAppcastItem *)update
{
    NSLog(@"cfgUpdater: willInstallUpdate");
}

// Called immediately before relaunching.
- (void)updaterWillRelaunchApplication:(SUUpdater *)updater
{
    NSLog(@"cfgUpdater: updaterWillRelaunchApplication");
}
// */

@end
