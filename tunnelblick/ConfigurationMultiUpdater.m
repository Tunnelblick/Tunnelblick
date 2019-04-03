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

@implementation ConfigurationMultiUpdater

TBSYNTHESIZE_OBJECT_GET(retain, NSMutableArray *, configUpdaters)


+(NSArray *) pathsForMasterStubTblkContainersWithBundleIdentifier: (NSString *) bundleId {
    
    NSMutableArray * paths = [NSMutableArray arrayWithCapacity: 10];
    
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: L_AS_T_TBLKS];
    NSString * bundleIdAndEdition;
    while (  (bundleIdAndEdition = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        NSString * containerPath = [L_AS_T_TBLKS stringByAppendingPathComponent: bundleIdAndEdition];
        BOOL isDir;
        if (   ( ! [bundleIdAndEdition hasPrefix: @"."] )
            && ( ! [bundleIdAndEdition hasSuffix: @".tblk"] )
            && [gFileMgr fileExistsAtPath: containerPath isDirectory: &isDir]
            && isDir  ) {
            NSString * thisBundleId = [bundleIdAndEdition stringByDeletingPathEdition];
            if (  [bundleId isEqualToString: thisBundleId]  ) {
                [paths addObject: containerPath];
            }
        }
    }
    
    return [NSArray arrayWithArray: paths];
}

+(NSDictionary *) highestEditionNumber {
	
    // Find the highest edition number for each bundleId_edition folder in L_AS_T_TBLKS
    NSMutableDictionary * bundleIdVersions = [[[NSMutableDictionary alloc] initWithCapacity: 10] autorelease]; // Key = bundleId; object = edition
    
    NSDirectoryEnumerator * outerDirEnum = [gFileMgr enumeratorAtPath: L_AS_T_TBLKS];
    NSString * bundleIdAndEdition;
    while (  (bundleIdAndEdition = [outerDirEnum nextObject])  ) {
        [outerDirEnum skipDescendents];
        NSString * containerPath = [L_AS_T_TBLKS stringByAppendingPathComponent: bundleIdAndEdition];
        BOOL isDir;
        if (   ( ! [bundleIdAndEdition hasPrefix: @"."] )
            && ( ! [bundleIdAndEdition hasSuffix: @".tblk"] )
            && [gFileMgr fileExistsAtPath: containerPath isDirectory: &isDir]
            && isDir  ) {
            NSString * bundleId = [bundleIdAndEdition stringByDeletingPathEdition];
            NSString * edition  = [bundleIdAndEdition pathEdition];
            NSString * highestEdition = [bundleIdVersions objectForKey: bundleId];
            if (   ( ! highestEdition)
                || ( [highestEdition compare: edition options: NSNumericSearch] == NSOrderedAscending )  ) {
                [bundleIdVersions setObject: edition forKey: bundleId];
            }
        }
    }
    
	return [NSDictionary dictionaryWithDictionary: bundleIdVersions];
}

-(id) init {
    
    self = [super init];
    if (  ! self  ) {
        return nil;
    }
    
	NSDictionary * bundleIdVersions = [ConfigurationMultiUpdater highestEditionNumber];
    
	// Create a ConfigurationUpdater for the highest edition of each bundleId and put it into configUpdaters
    configUpdaters = [[NSMutableArray alloc] initWithCapacity: 10]; // Entries: ConfigurationUpdater *
    
    NSEnumerator * e = [bundleIdVersions keyEnumerator];
    NSString * bundleId;
    while (  (bundleId = [e nextObject])  ) {
        NSString * edition = [bundleIdVersions objectForKey: bundleId];
        NSString * bundleIdAndEdition = [bundleId stringByAppendingPathEdition: edition];
        NSString * containerPath = [L_AS_T_TBLKS stringByAppendingPathComponent: bundleIdAndEdition];
        NSDirectoryEnumerator * innerDirEnum = [gFileMgr enumeratorAtPath: containerPath];
        NSString * name;
        while (  (name = [innerDirEnum nextObject])  ) {
            [innerDirEnum skipDescendents];
            if (  [name hasSuffix: @".tblk"]  ) {
                NSString * masterPath = [containerPath stringByAppendingPathComponent: name];
                ConfigurationUpdater * configUpdater = [[[ConfigurationUpdater alloc] initWithPath: masterPath] autorelease];
                if (  configUpdater  ) {
                    [configUpdaters addObject: configUpdater];
                    TBLog(@"DB-UC", @"Added configuration updater for '%@' (%@)", bundleId, edition);
                } else {
                    NSLog(@"Could not create a new ConfigurationUpdater with path '%@'", masterPath);
                    return nil;
                }
            }
        }
    }
    
    return self;
}

-(void) dealloc {
    
    [configUpdaters release]; configUpdaters = nil;
    
    [super dealloc];
}

-(void) startAllUpdateCheckingWithUI: (BOOL) withUI {
    
	if (  [gTbDefaults boolForKey: @"inhibitOutboundTunneblickTraffic"]  ) {
		NSLog(@"Not checking for configuration updates because inhibitOutboundTunneblickTraffic is true");
		return;
	}
	
    ConfigurationUpdater * configUpdater;
    NSEnumerator * e = [[self configUpdaters] objectEnumerator];
    while (  (configUpdater = [e nextObject])  ) {
		
		// Only start checking for the highest edition of each bundle ID
		NSString * bundleId = [configUpdater cfgBundleId];
		NSDictionary * bundleIdVersions = [ConfigurationMultiUpdater highestEditionNumber];
		NSString * highestEdition = [bundleIdVersions objectForKey: bundleId];
		NSString * bundlePath = [configUpdater cfgBundlePath];
		NSString * containerPath = [bundlePath stringByDeletingLastPathComponent];
		NSString * bundleEdition = [containerPath pathEdition];
		if (  [bundleEdition isEqualToString: highestEdition]  ) {
			[configUpdater startUpdateCheckingWithUI: [NSNumber numberWithBool: withUI]];
		}
	}
}

-(void) stopAllUpdateChecking {
	
	ConfigurationUpdater * configUpdater;
    NSEnumerator * e = [[self configUpdaters] objectEnumerator];
    while (  (configUpdater = [e nextObject])  ) {
		[configUpdater stopChecking];
    }
}

-(void) addUpdateCheckingForStubTblkAtPath: (NSString *) path {
	
	// Create a new ConfigurationUpdater, add it to the list, and start it checking for updates without a UI in five seconds
	
    ConfigurationUpdater * configUpdater = [[[ConfigurationUpdater alloc] initWithPath: path] autorelease];
    if (  configUpdater  ) {
        [[self configUpdaters] addObject: configUpdater];
	    [configUpdater performSelector: @selector(startUpdateCheckingWithUI:) withObject: @NO afterDelay: 5.0];
        NSString * bundleIdAndEdition = [[path stringByDeletingLastPathComponent] lastPathComponent];
        NSString * bundleId           = [bundleIdAndEdition stringByDeletingPathEdition];
        NSString * edition            = [bundleIdAndEdition pathEdition];
		TBLog(@"DB-UC", @"Added configuration updater for '%@' (%@) and scheduled it to start checking for updates in 5 seconds", bundleId, edition);
    } else {
        TBLog(@"DB-UC", @"addUpdateCheckingForStubTblkAtPath: Could not create a new ConfigurationUpdater with path '%@'", path);
    }
}

-(void) stopUpdateCheckingForAllStubTblksWithBundleIdentifier: (NSString *) bundleId {
	
	BOOL stopped = FALSE;
	NSUInteger ix;
	for (  ix=0; ix<[[self configUpdaters] count]; ix++  ) {
		ConfigurationUpdater * configUpdater = [[self configUpdaters] objectAtIndex: ix];
		NSString * thisBundleId = [configUpdater cfgBundleId];
		if (  [thisBundleId isEqualToString: bundleId]  ) {
            [configUpdater stopChecking];
			stopped = TRUE;
		}
    }
	
	if (  ! stopped  ) {
		TBLog(@"DB-UC", @"Did not need to stop update checking for configuration '%@' because it does not have an entry in the configUpdaters array.", bundleId);
	}
}

-(void) stopUpdateCheckingForAllStubTblksLikeTheOneAtPath: (NSString *) path {
    
    NSString * bundleId = [[[path stringByDeletingLastPathComponent] lastPathComponent] stringByDeletingPathEdition];
    [self stopUpdateCheckingForAllStubTblksWithBundleIdentifier: bundleId];
}

@end
