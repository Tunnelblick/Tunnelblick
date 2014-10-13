/*
 * Copyright 2014 Jonathan Bullard
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


#import "ConfigurationMultiUpdater.h"

#import "defines.h"
#import "helper.h"
#import "sharedRoutines.h"

#import "ConfigurationUpdater.h"
#import "NSFileManager+TB.h"
#import "NSString+TB.h"
#import "TBUserDefaults.h"

extern NSFileManager  * gFileMgr;
extern TBUserDefaults * gTbDefaults;
extern BOOL             gShuttingDownWorkspace;

extern void _CFBundleFlushBundleCaches(CFBundleRef bundle) __attribute__((weak_import));

@implementation ConfigurationMultiUpdater

-(ConfigurationUpdater *) addTblkAtPath: (NSString *) path {
    
    NSString * tblkName = [path lastPathComponent];
    NSString * ext  = [tblkName pathExtension];
    
    if (  [ext isEqualToString: @"tblk"]  ) {
        if (   ( [tblkName containsOnlyCharactersInString: ALLOWED_DOMAIN_NAME_CHARACTERS])
            && ( [tblkName rangeOfString: @".."].length == 0)  ) {
            
			// Copy the /Library copy of the updatable .tblk to a per-user copy so it can be secured for the user instead of root
			NSString * updatableTblkPath = [[[[[NSHomeDirectory() stringByAppendingPathComponent: @"Library"]
											   stringByAppendingPathComponent: @"Application Support"]
											  stringByAppendingPathComponent: @"Tunnelblick"]
											 stringByAppendingPathComponent: @"Tblks"]
											stringByAppendingPathComponent: tblkName];
			
			// But not if we are called with the per-user copy
			if (  ! [updatableTblkPath isEqualToString: path]  ) {
				if (  [gFileMgr fileExistsAtPath: updatableTblkPath]  ) {
					if (  ! [gFileMgr tbRemoveFileAtPath: updatableTblkPath handler: nil]  ) {
						NSLog(@"Unable to remove %@", updatableTblkPath);
						return nil;
					}
				}
				NSString * updatableTblkContainerPath = [updatableTblkPath stringByDeletingLastPathComponent];
				if (  createDir(updatableTblkContainerPath, PERMS_PRIVATE_FOLDER) == -1  ) {
					NSLog(@"Unable to create %@", updatableTblkContainerPath);
					return nil;
				}
				if (  [gFileMgr tbCopyPath: path toPath: updatableTblkPath handler: nil]  ) {
					TBLog(@"DB-UC", @"Copied updatable configuration '%@' to local user folder", tblkName);
				} else {
					TBLog(@"DB-UC", @"Unable to copy %@ to %@", path, updatableTblkPath);
					return nil;
				}
			}
            
            // NOTE: Updaters are NOT created with autoRelease. If we auto-released them, they would not be
            // deallocated (and thus stopped) until the end of the current run loop, and that might be later than we want.
            
            ConfigurationUpdater * configUpdater = [[ConfigurationUpdater alloc] initWithPath: updatableTblkPath];
            
            if (  configUpdater  ) {
                [configUpdaters addObject: configUpdater];                  // This will make the retain count 2 because it is retained by configUpdaters
                [configUpdater release];                                    // This will make the retain count 1, because it is still retained by configUpdaters
                return configUpdater;
            } else {
                NSLog(@"Unable to create configuration updater for %@", tblkName);
            }
        } else {
            NSLog(@"addUpdaterForSet: Ignoring updatable '%@' because of illegal characters in its name (not 0-9, a-z, A-Z, '.', or '-') or the name contains '..'", tblkName);
        }
    } else {
        NSLog(@"addUpdaterForSet: Ignoring updatable '%@' because of it is not a .tblk", tblkName);
    }
    
    return nil;
}

-(id) init {
    
    self = [super init];
    if (  self  ) {
        
        //
        // NOTE: Do not use [NSMutableArray arrayWithCapacity:] because we need to control the release more closely than autoRelease allows
        //
        
        configUpdaters = [[NSMutableArray alloc] initWithCapacity: 10];
        
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: L_AS_T_TBLKS];
        NSString * file;
        while (  (file = [dirEnum nextObject])  ) {
            [dirEnum skipDescendents];
            NSString * tblkPath = [L_AS_T_TBLKS stringByAppendingPathComponent: file];
            [self addTblkAtPath: tblkPath];
        }
    }
    
    return self;
}

-(void) dealloc {
    
    [configUpdaters release]; configUpdaters = nil;
    
    [super dealloc];
}

-(void) startAllCheckingWithUI: (BOOL) withUI {
    
    ConfigurationUpdater * configUpdater;
    NSEnumerator * e = [configUpdaters objectEnumerator];
    while (  (configUpdater = [e nextObject])  ) {
        [configUpdater startCheckingWithUI: [NSNumber numberWithBool: withUI]];
    }
}

-(void) restartUpdaterForTblkAtPath: (NSString *) path {
    
    ConfigurationUpdater * configUpdater;
    NSEnumerator * e = [configUpdaters objectEnumerator];
    while (  (configUpdater = [e nextObject])  ) {
        if (  [[configUpdater cfgBundlePath] isEqualToString: path]  ) {
			
			// Remember state so we can restore it
			BOOL checking = [configUpdater checking];
			BOOL withUI   = [configUpdater checkingWithUI];
			
			// Stop checking with that updater
			[configUpdater stopChecking];
			
			NSString * fileName = [path lastPathComponent];
			
			// Remove the old updater
			[configUpdaters removeObject: configUpdater];
			TBLog(@"DB-UC", @"Removed old updater for %@", fileName);
            
            // Flushing the bundle cache is important. If it is not done, Sparkle will get the old .plist info, and think the old configuration is still there
            // If the private call disappears, a workaround would be to uniquely name each temporary bundle we create in addTblkAtPath, using an incrementing serial number
            if (_CFBundleFlushBundleCaches != NULL) {
                TBLog(@"DB-UC", @"Flushing bundle cache for %@", fileName);
                CFBundleRef cfBundle = CFBundleCreate(nil, (CFURLRef)[[NSBundle bundleWithPath: path] bundleURL]);
                _CFBundleFlushBundleCaches(cfBundle);
                CFRelease(cfBundle);
            } else {
                NSLog(@"_CFBundleFlushBundleCaches does not exist on this system");
            }
			
			// Create a new updater
			configUpdater = [self addTblkAtPath: path];
			if (  configUpdater  ) {
                // Restore the updater's state
				if (  checking  ) {
					[configUpdater performSelector: @selector(startCheckingWithUI:) withObject: [NSNumber numberWithBool: withUI] afterDelay: 5.0];
					return;
				}
			} else {
				NSLog(@"Unable to add updatable .tblk at %@", path);
			}
			
			return;
		}
	}
	
	NSLog(@"After restarting the updating, there is no entry in configurationMultiUpdater for %@", path);
    return;
}

-(void) stopAllChecking {
	
	ConfigurationUpdater * configUpdater;
    NSEnumerator * e = [configUpdaters objectEnumerator];
    while (  (configUpdater = [e nextObject])  ) {
		[configUpdater stopChecking];
    }
}

-(void) addUpdaterForTblkAtPath: (NSString *) path
               bundleIdentifier: (NSString *) bundleId {
	
	// See if we already have a ConfigurationUpdater for this bundle ID
	NSString * name = [bundleId stringByAppendingPathExtension: @"tblk"];
	ConfigurationUpdater * configUpdater;
    NSEnumerator * e = [configUpdaters objectEnumerator];
    while (  (configUpdater = [e nextObject])  ) {
		NSString * existingBundlePath = [configUpdater cfgBundlePath];
		NSString * existingName = [existingBundlePath lastPathComponent];
		if (  [existingName isEqualToString: name]  ) {
            [configUpdater performSelector: @selector(startCheckingWithUI:) withObject: [NSNumber numberWithBool: NO] afterDelay: 5.0];
			TBLog(@"DB-UC", @"addUpdatableTblkWithBundleId: Already have a ConfigurationUpdater for '%@', so scheduled it start checkinging for updates in 5 seconds", bundleId);
			return;
		}
    }
	
	// Do not have a ConfigurationUpdater, so create one
	configUpdater = [self addTblkAtPath: path];
	[configUpdater performSelector: @selector(startCheckingWithUI:) withObject: [NSNumber numberWithBool: NO] afterDelay: 5.0];
	TBLog(@"DB-UC", @"addUpdatableTblkWithBundleId: Created new ConfigurationUpdater for '%@' and scheduled it start checkinging for updates in 5 seconds", bundleId);
}

-(void) removeUpdaterForTblkWithBundleIdentifier: (NSString *) bundleId {
	
	NSString * name = [bundleId stringByAppendingPathExtension: @"tblk"];
	NSUInteger ix;
	for (  ix=0; ix<[configUpdaters count]; ix++  ) {
		ConfigurationUpdater * configUpdater = [configUpdaters objectAtIndex: ix];
		NSString * existingBundlePath = [configUpdater cfgBundlePath];
		NSString * existingName = [existingBundlePath lastPathComponent];
		if (  [existingName isEqualToString: name]  ) {
			
			[configUpdater stopChecking];
			TBLog(@"DB-UC", @"removeUpdaterForTblkWithBundleIdentifier: Stopped checking for updates for '%@'", bundleId);
            
			[configUpdaters removeObjectAtIndex: ix];
			TBLog(@"DB-UC", @"removeUpdaterForTblkWithBundleIdentifier: Removed '%@' from configUpdaters", bundleId);
			
			if (  [gFileMgr fileExistsAtPath: existingBundlePath]  ) {
				if (  [gFileMgr tbRemoveFileAtPath: existingBundlePath handler: nil]  ) {
					TBLog(@"DB-UC", @"removeUpdaterForTblkWithBundleIdentifier: Removed %@", existingBundlePath);
				} else {
					NSLog(@"Unable to remove %@", existingBundlePath);
					return;
				}
			} else {
				NSLog(@"removeUpdaterForTblkWithBundleIdentifier: Path does not exist: %@", existingBundlePath);
			}
			
			TBLog(@"DB-UC", @"removeUpdaterForTblkWithBundleIdentifier: Removed ConfigurationUpdater for '%@'", bundleId);
			return;
		}
    }
	
	TBLog(@"DB-UC", @"removeUpdaterForTblkWithBundleIdentifier: Cound not find ConfigurationUpdater for '%@'", bundleId);
}

@end
