/*
 * Copyright 2013 Jonathan Bullard
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

#import "LeftNavDataSource.h"
#import "LeftNavItem.h"
#import "MenuController.h"
#import "MyPrefsWindowController.h"
#import "TBUserDefaults.h"
#import "helper.h"
#import "VPNConnection.h"
#import "NSApplication+LoginItem.h"
#import "ConfigurationManager.h"

extern TBUserDefaults * gTbDefaults;
extern NSString       * gDeployPath;

@implementation LeftNavDataSource

-(id) init {
    self = [super init];
    if (self) {
        rowsByDisplayName = [[NSMutableDictionary alloc] initWithCapacity: 100];
    }
    return self;    
}

-(void) dealloc {
    
    [rowsByDisplayName release]; rowsByDisplayName = nil;
    
    [super dealloc];
}

-(NSDictionary *) rowsByDisplayName {
	
	return [[rowsByDisplayName copy] autorelease];	// Non-mutable copy
}

- (BOOL)  keys: (NSArray *) theKeys
       atIndex: (unsigned)  theIx
haveSameParent: (unsigned)  theLevel {
    
    if (  theIx == 0) {
        return YES;
    }
    
    NSString * previousKey = [theKeys objectAtIndex: theIx -1];
    NSString * currentKey  = [theKeys objectAtIndex: theIx];

    NSArray  * previousComponents = [previousKey pathComponents];
    NSArray  * currentComponents  = [currentKey pathComponents];
    
    unsigned j;
    for (  j=0; j<theLevel; j++) {
        if (  ! [[previousComponents objectAtIndex: j] isEqualToString: [currentComponents objectAtIndex: j]]  ) {
            return NO;
        }
    }
    
    return YES;
}

- (void) addItemsFromKeys: (NSArray *)    theKeys
                toParent: (LeftNavItem *) theParent
                 atLevel: (unsigned)      theLevel
            fromIndexPtr: (unsigned *)    theIxPtr
				atRowPtr: (unsigned *)    theRowPtr {

	BOOL firstOfThisParent = TRUE;
    while (  *theIxPtr < [theKeys count]  ) {
        unsigned currentIx = *theIxPtr;
        NSString * displayName = [theKeys objectAtIndex: currentIx];
        NSArray * components = [displayName pathComponents];
        unsigned nComponents = [components count];
		if (   firstOfThisParent
			|| [self keys: theKeys atIndex: currentIx haveSameParent: theLevel]  ) {
			if (  nComponents == theLevel + 1  ) {
				LeftNavItem * item = [[[LeftNavItem alloc] init] autorelease];
				[item setDisplayName:             displayName];
				[item setNameToShowInOutlineView: [components objectAtIndex: theLevel]];
				[item setChildren:                nil];
				[item setParent:                  theParent];
				[[theParent children] addObject: item];
                [rowsByDisplayName setObject: [NSNumber numberWithUnsignedInt: (*theRowPtr)++] forKey: displayName];
				(*theIxPtr)++;
			} else if (  nComponents > theLevel + 1  ) {
				LeftNavItem * item = [[[LeftNavItem alloc] init] autorelease];
				NSMutableString * dispNm = [NSMutableString stringWithCapacity: 1000];
				unsigned i;
				for (  i=0; i<=theLevel; i++  ) {
					[dispNm appendFormat: @"%@/", [components objectAtIndex: i]];
				}
				[item setDisplayName:             dispNm];
				[item setNameToShowInOutlineView: [components objectAtIndex: theLevel]];
				[item setChildren:                [[[NSMutableArray alloc] initWithCapacity: 20] autorelease]];
				[item setParent:                  theParent];
				[[theParent children] addObject: item];
				(*theRowPtr)++;
				[self addItemsFromKeys: theKeys toParent: item atLevel: theLevel+1 fromIndexPtr: theIxPtr atRowPtr: theRowPtr];
			} else {
				(*theIxPtr)++;
			}
		} else {
			break;
		}
		
		firstOfThisParent = FALSE;
	}
}

- (id)        outlineView: (NSOutlineView *) outlineView
displayNameForTableColumn: (NSTableColumn *) tableColumn
                   byItem: (id)              item {
	
	(void) outlineView;
    (void) tableColumn;
    
	id val = ((item == nil)
			  ? @"ROOT ITEM"
			  : [(LeftNavItem *) item displayName]
			  );
	return val;
}	

- (void) reload {
    
    [rowsByDisplayName removeAllObjects];
    
    NSArray * sortedDisplayNames = [[[[NSApp delegate] myConfigDictionary] allKeys]
                                    sortedArrayUsingSelector: @selector(caseInsensitiveNumericCompare:)];
    
    // We create a new rootItem, but will only use it's children variable
    LeftNavItem * newRootItem = [[[LeftNavItem alloc] init] autorelease];
    [newRootItem setDisplayName: nil];  // Not used
    [newRootItem setParent:      nil];  // Not used
    [newRootItem setChildren:    [[[NSMutableArray alloc] initWithCapacity: 20] autorelease]];
    
    // Add all the configurations to the new rootItem (i.e., add them as children of the new rootItem)
    unsigned i = 0;
	unsigned r = 0;
    [self addItemsFromKeys: sortedDisplayNames toParent: newRootItem atLevel: 0 fromIndexPtr: &i atRowPtr: &r];
    
    // Replace the old rootItem's children with the new rootItem's children
    [[LeftNavItem rootItem] setChildren: [newRootItem children]];
}

-(NSInteger) outlineView: (NSOutlineView *) outlineView
  numberOfChildrenOfItem: (id) item {
    
	(void) outlineView;
    
	NSInteger val = ((item == nil)
					 ? 1
					 : [(LeftNavItem *) item numberOfChildren]
					 );
	return val;
}

-(BOOL) outlineView:(NSOutlineView *) outlineView
   isItemExpandable: (id) item {

	(void) outlineView;
	
	BOOL val = ((item == nil)
				? YES
				: ([item numberOfChildren] != -1)
				);
	return val;
}

-(id) outlineView: (NSOutlineView *) outlineView
            child: (NSInteger) index
           ofItem: (id) item {
    
	(void) outlineView;
    
	id val = ((item == nil)
			  ? [LeftNavItem rootItem]
			  : [(LeftNavItem *) item childAtIndex: index]
			  );
	return val;
}

-(id)         outlineView: (NSOutlineView *) outlineView
objectValueForTableColumn: (NSTableColumn *) tableColumn
				   byItem: (id) item {
    
	(void) outlineView;
    (void) tableColumn;
    
	id val = ((item == nil)
				? @"ROOT ITEM"
				: [(LeftNavItem *) item nameToShowInOutlineView]
				);
	return val;
}

-(BOOL) outlineView: (NSOutlineView *) outlineView
   shouldSelectItem: (id) item {
	
	BOOL val = ! [self outlineView: outlineView isItemExpandable: item];
	return val;
}

-(BOOL) outlineView: (NSOutlineView *) outlineView
 shouldCollapseItem: (id) item {
	
	(void) outlineView;
	
	BOOL val = (([outlineView rowForItem: item] == 0)
				? NO
				: YES
				);
	return val;
}

-(void) outlineViewSelectionDidChange: (NSNotification *) notification
{
	(void) notification;
	
	MyPrefsWindowController * mpwc = [[NSApp delegate] logScreen]; 
    [mpwc performSelectorOnMainThread: @selector(selectedLeftNavListIndexChanged) withObject: nil waitUntilDone: NO];
}

-(void) outlineViewItemDidExpand: (NSNotification *) notification {
    id item = [[notification userInfo] valueForKey: @"NSObject"];
    NSString * displayName = [item displayName];
	if (  [displayName length] == 0  ) {
		return;
	}
    NSMutableArray * expandedDisplayNames = [[[gTbDefaults arrayForKey: @"leftNavOutlineViewExpandedDisplayNames"] mutableCopy] autorelease];
    if (  expandedDisplayNames  ) {
		if (  [expandedDisplayNames containsObject: displayName]  ) {
			return;
		}
	} else {
        expandedDisplayNames = [NSMutableArray arrayWithCapacity: 1];
    }
    [expandedDisplayNames addObject: displayName];
    [gTbDefaults setObject: expandedDisplayNames forKey:@"leftNavOutlineViewExpandedDisplayNames"];
}

-(void) outlineViewItemDidCollapse: (NSNotification *) notification {
    id item = [[notification userInfo] valueForKey: @"NSObject"];
    NSString * displayName = [item displayName];
	if (  [displayName length] == 0  ) {
		return;
	}
    NSMutableArray * expandedDisplayNames = [[[gTbDefaults arrayForKey: @"leftNavOutlineViewExpandedDisplayNames"] mutableCopy] autorelease];
    if (  expandedDisplayNames  ) {
		if (  [expandedDisplayNames containsObject: displayName]  ) {
            [expandedDisplayNames removeObject: displayName];
            [gTbDefaults setObject: expandedDisplayNames forKey:@"leftNavOutlineViewExpandedDisplayNames"];
        }
    }
}

- (void)      outlineView: (NSOutlineView *) outlineView
           setObjectValue: (id)              newName
           forTableColumn: (NSTableColumn *) tableColumn
                   byItem: (id)              item {
	
	(void) outlineView;
	(void) tableColumn;
	
    if (  ! [[newName class] isSubclassOfClass: [NSString class]]) {
        NSLog(@"Object '%@' passed to outlineView:setObjectValue:forTableColumn:byItem: is not an NSString, it is a %@", newName, [newName class]);
        return;
    }
	
	if (  invalidConfigurationName(newName, PROHIBITED_DISPLAY_NAME_CHARACTERS_INCLUDING_SLASH_CSTRING)  ) {
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                        [NSString stringWithFormat:
						 NSLocalizedString(@"Names may not include any of the following characters: %s\n\n%@", @"Window text"),
						 PROHIBITED_DISPLAY_NAME_CHARACTERS_INCLUDING_SLASH_CSTRING,
						 @""],
						
						nil, nil, nil);
        return;
    }
	
	NSString      * sourceDisplayName = [item displayName];
    VPNConnection * connection        = [[[NSApp delegate] myVPNConnectionDictionary] objectForKey: sourceDisplayName];
	
    NSString * autoConnectKey = [sourceDisplayName stringByAppendingString: @"autoConnect"];
    NSString * onSystemStartKey = [sourceDisplayName stringByAppendingString: @"-onSystemStart"];
    if (   [gTbDefaults boolForKey: autoConnectKey]
        && [gTbDefaults boolForKey: onSystemStartKey]  ) {
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                        NSLocalizedString(@"You may not rename a configuration which is set to start when the computer starts.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
    if (  ! [connection isDisconnected]  ) {
        TBRunAlertPanel(NSLocalizedString(@"Active connection", @"Window title"),
                        NSLocalizedString(@"You cannot rename a configuration unless it is disconnected.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
    NSString * sourcePath = [connection configPath];
    if (  [sourcePath hasPrefix: [gDeployPath stringByAppendingString: @"/"]]  ) {
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                        NSLocalizedString(@"You may not rename a Deployed configuration.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
    NSString * sourceFolder = [sourcePath stringByDeletingLastPathComponent];
    NSString * sourceLast = [sourcePath  lastPathComponent];
    NSString * sourceExtension = [sourceLast pathExtension];
    
    NSString * targetPath = [sourceFolder stringByAppendingPathComponent: [newName stringByAppendingPathExtension: sourceExtension]];
    NSString * targetDisplayName = [lastPartOfPath(targetPath) stringByDeletingPathExtension];
    
    NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"You have asked to rename '%@' to '%@'.", @"Window text"), sourceDisplayName, targetDisplayName];
    AuthorizationRef authorization = [NSApplication getAuthorizationRef: msg];
    if ( authorization == nil ) {
        return;
    }
    
    if (  [[ConfigurationManager defaultManager] copyConfigPath: sourcePath
                                                         toPath: targetPath
                                                usingAuthRefPtr: &authorization
                                                     warnDialog: YES
                                                    moveNotCopy: YES]  ) {
        
        // We copy "-keychainHasUsernameAndPassword" because it is deleted by moveCredentials
        NSString * key = [[connection displayName] stringByAppendingString: @"-keychainHasUsernameAndPassword"];
        BOOL haveCredentials = [gTbDefaults boolForKey: key];
        
        moveCredentials([connection displayName], targetDisplayName); // Do this so "<source>-keychainHasUsernameAndPassword" preference is used
        
        if (  ! [gTbDefaults movePreferencesFrom: [connection displayName] to: targetDisplayName]  ) {
            TBRunAlertPanel(NSLocalizedString(@"Warning", @"Window title"),
                            NSLocalizedString(@"Warning: One or more preferences could not be renamed. See the Console Log for details.", @"Window text"),
                            nil, nil, nil);
        }
        
        // moveCredentials deleted "-keychainHasUsernameAndPassword" for the from configuration's preferences, so we restore it to the "to" configuration's preferences
        key = [targetDisplayName stringByAppendingString: @"-keychainHasUsernameAndPassword"];
        [gTbDefaults setBool: haveCredentials forKey: key];
        
        [item setNameToShowInOutlineView: newName];
		[item setDisplayName: targetDisplayName];
		
		// We also need to change the name of the configuration that is selected
		NSString * pref = [gTbDefaults stringForKey: @"leftNavSelectedDisplayName"];
		if (  [pref isEqualToString: sourceDisplayName]  ) {
			[gTbDefaults setObject: targetDisplayName forKey: @"leftNavSelectedDisplayName"];
		}
		
		[[[NSApp delegate] logScreen] setPreviouslySelectedNameOnLeftNavList: targetDisplayName];
		
		[[NSApp delegate] updateMenuAndDetailsWindow];
    }
    
    AuthorizationFree(authorization, kAuthorizationFlagDefaults);
}

@end
