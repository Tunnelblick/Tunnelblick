/*
 * Copyright 2013, 2014, 2015, 2020 Jonathan K. Bullard. All rights reserved.
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

#import "helper.h"
#import "sharedRoutines.h"

#import "ConfigurationManager.h"
#import "LeftNavItem.h"
#import "LeftNavViewController.h"
#import "MenuController.h"
#import "MyPrefsWindowController.h"
#import "NSApplication+LoginItem.h"
#import "NSString+TB.h"
#import "TBUserDefaults.h"
#import "VPNConnection.h"

extern NSString       * gDeployPath;
extern TBUserDefaults * gTbDefaults;

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
	
	return [NSDictionary dictionaryWithDictionary: rowsByDisplayName];	// Non-mutable copy
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
        NSString * localName;
        if (  [displayName hasSuffix: @"/"]  ) {
            localName = [displayName substringToIndex: [displayName length] -1];
        } else if ( [displayName length] == 0  ) {
            localName = @"";
        } else  {
            localName = [((MenuController *)[NSApp delegate]) localizedNameForDisplayName: displayName];
        }
        NSArray * components = [displayName pathComponents];
        unsigned nComponents = [components count];
        TBLog(@"DB-PO", @"ncomponents = %u; displayName = '%@'; localName = '%@'; row = %d; ix = %d; currentIx = %d; theLevel = %d",
              nComponents, displayName, localName, *theRowPtr, *theIxPtr, currentIx, theLevel);
		if (   firstOfThisParent
			|| [self keys: theKeys atIndex: currentIx haveSameParent: theLevel]  ) {
			if (  nComponents == theLevel + 1  ) {
                NSString * name = [components objectAtIndex: theLevel];
                if (  ! [name isEqualToString: @"/"]  ) {
                    LeftNavItem * item = [[[LeftNavItem alloc] init] autorelease];
                    [item setDisplayName:             displayName];
                    [item setNameToShowInOutlineView: name];
                    [item setChildren:                nil];
                    [item setParent:                  theParent];
                    [[theParent children] addObject: item];
                    TBLog(@"DB-PO", @"#1: Added displayName = '%@'; name = '%@'; row = %d; ix = %d", displayName, name, *theRowPtr, *theIxPtr);
                    [rowsByDisplayName setObject: [NSNumber numberWithUnsignedInt: (*theRowPtr)++] forKey: displayName];
                } else {
                    TBLog(@"DB-PO", @"Not adding \"/\"");
                }

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
                TBLog(@"DB-PO", @"#2: Added '%@'; dispNm = '%@'; row = %d; ix = %d; currentIx = %d",
                      dispNm, [components objectAtIndex: theLevel], *theRowPtr, *theIxPtr, currentIx);
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

    // We create a new rootItem, but will only use it's children variable
    LeftNavItem * newRootItem = [[[LeftNavItem alloc] init] autorelease];
    [newRootItem setDisplayName: nil];  // Not used
    [newRootItem setParent:      nil];  // Not used
    [newRootItem setChildren:    [[[NSMutableArray alloc] initWithCapacity: 20] autorelease]];
    
    // Add all the configurations and empty folders to the new rootItem (i.e., add them as children of the new rootItem)
    NSArray * sortedNames = [[(MenuController *)[NSApp delegate] logScreen] leftNavDisplayNames];
    TBLog(@"DB-PO", @"sortedNames = %@",sortedNames);
    unsigned i = 0;
	unsigned r = 0;
    [self addItemsFromKeys: sortedNames toParent: newRootItem atLevel: 0 fromIndexPtr: &i atRowPtr: &r];
    
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
	
	MyPrefsWindowController * mpwc = [((MenuController *)[NSApp delegate]) logScreen];
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
	
	NSString * sourceDisplayName = [item displayName];
    VPNConnection * connection   = [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] objectForKey: sourceDisplayName];
    if (  ! connection  ) {
        NSLog(@"Tried to rename configuration but no configuration has been selected");
        return;
    }

    NSString * sourcePath = [connection configPath];
    NSString * targetPath = standardizedPathForRename(sourcePath, newName, YES);
    if (  targetPath  ) {
        [ConfigurationManager renameConfigurationInNewThreadAtPath: sourcePath toPath: targetPath];
    }
}

-(NSDictionary *) infoForDropInfo: (id < NSDraggingInfo >) info
                             item: (id)                    item {

    // Return a dictionary of info about a drop.
    // Returns nil if should not do the drop.

    // If the Option key is down, this is a copy instead of a move
    NSEvent * event = [NSApp currentEvent];
    if (  ! event  ) {
        NSLog(@"infoForDropInfo:item: Could not get event");
        return nil;
    }
    NSEventModifierFlags flags = [event modifierFlags];
    BOOL copy = (flags & 0x80000) != 0;   // Option key (Left = 0x80120, Right = 0x80140)

    // Get the source displayName and path
    NSPasteboard * pb = [info draggingPasteboard];
    NSArray * pbItems = [pb pasteboardItems];
    if (  [pbItems count] != 1  ) {
        // Can only drag one item at a time. TODO: drag multiple items at a time
        return nil;
    }
    NSPasteboardItem * pbItem = [pbItems firstObject];
    NSString * sourceDisplayName = [pbItem stringForType: TB_LEFT_NAV_ITEMS_DRAG_ID];
    if (  ! sourceDisplayName  ) {
        NSLog(@"infoForDropInfo:item: Could not get stringForType for pbItem = %@ in pbItems = %@ from pb = %@", pbItem, pbItems, pb);
        return nil;
    }
    NSString * sourcePath = nil;
    if (   [sourceDisplayName isEqualToString: @""]
        || [sourceDisplayName hasSuffix: @"/"]  ) {
        // TODO: be able to drag a folder
        return nil;
    } else {
        // Dragging a configuration
        NSDictionary * configs = [((MenuController *)[NSApp delegate]) myConfigDictionary];
        sourcePath = [configs objectForKey: sourceDisplayName];
        if (  ! sourcePath  ) {
            NSLog(@"infoForDropInfo:item: Could not get configuration path for '%@' from myConfigDictionary = %@", sourceDisplayName, configs);
            return nil;
        }
        if (   [sourcePath hasPrefix: gDeployPath]
            && ( ! copy  )  ) {
            NSLog(@"Can't move a Deployed configuration (but can copy it)");
            return nil;
        }
    }

    // Get the target displayName and path
    // Remove the last "/" and everything to its right
    NSString * name = [item displayName];
    if (  ! name  ) {
        // This happens when dragging past the end of the list
        return nil;
    }
    if (   ( [name length] != 0 )
        && ( ! [name hasSuffix: @"/"] )
        ) {
        // Can't drop on configuration (configurations have names that doesn't end in "/")
        return nil;
    }
    NSRange r = [name rangeOfString: @"/" options: NSBackwardsSearch];
    NSString * prefix = (  (r.location == NSNotFound)
                         ? prefix = @""
                         : [name substringToIndex: r.location]);

    NSString * targetDisplayName = [prefix stringByAppendingPathComponent: [sourceDisplayName lastPathComponent]];

    NSString * targetPath = [[firstPartOfPath(sourcePath)
                              stringByAppendingPathComponent: targetDisplayName]
                             stringByAppendingPathExtension: @"tblk"];

    NSNumber * copyNotMove = [NSNumber numberWithBool: copy];
    NSDictionary * result = [NSDictionary dictionaryWithObjectsAndKeys:
                             copyNotMove,       @"copyNotMove",
                             targetPath,        @"targetPath",
                             sourcePath,        @"sourcePath",
                             nil];
    return result;
}

-(id <NSPasteboardWriting>) outlineView: (NSOutlineView *) outlineView
                pasteboardWriterForItem: (id)              item {

    (void)outlineView;

    NSString * stringRep = [item displayName];
    if (  ! stringRep) {
        NSLog(@"targetPathWithCopySuffixFromTargetPath:sourcePath:copy: Could not get displayName from item = %@", item);
        return nil;
    }

    NSPasteboardItem * pboardItem = [[[NSPasteboardItem alloc] init] autorelease];

    [pboardItem setString: stringRep forType: TB_LEFT_NAV_ITEMS_DRAG_ID];

    return pboardItem;
}

-(NSDragOperation)outlineView: (NSOutlineView *)        outlineView
                 validateDrop: (id < NSDraggingInfo >) info
                 proposedItem: (id)                    item
           proposedChildIndex: (NSInteger)             index {

    (void)outlineView;
    (void)index;

    NSDictionary * dict = [self infoForDropInfo: info item: item];

    if (  ! dict  ) {
        return NSDragOperationNone;
    }

    NSString * sourcePath  =  [dict objectForKey: @"sourcePath"];
    NSString * targetPath  =  [dict objectForKey: @"targetPath"];
    if (  [sourcePath isEqualToString: targetPath]  ) {
        // Don't allow drag within a folder; it wouldn't do anything because folders are sorted alphanumerically
        return NSDragOperationNone;
    }

    if (  [[dict objectForKey: @"copyNotMove"] boolValue]  ) {
       return NSDragOperationCopy;
    } else {
        return NSDragOperationMove;
    }
}


-(BOOL) outlineView: (NSOutlineView *)        outlineView
         acceptDrop: (id < NSDraggingInfo >) info
               item: (id)                    item
         childIndex: (NSInteger)             index {

    (void)outlineView;
    (void)index;

    NSDictionary * dict = [self infoForDropInfo: info item: item];

    if (  ! dict  ) {
        return NO;
    }

    BOOL       copyNotMove = [[dict objectForKey: @"copyNotMove"] boolValue];
    NSString * sourcePath  =  [dict objectForKey: @"sourcePath"];
    NSString * targetPath  =  [dict objectForKey: @"targetPath"];

    // Copy or move the item. If successful, the method will reload the data for the outlineView

    if (  copyNotMove  ) {
        [ConfigurationManager copyConfigurationInNewThreadPath: sourcePath toPath: targetPath];
    } else {
        [ConfigurationManager moveConfigurationInNewThreadAtPath:  sourcePath toPath: targetPath];
    }

    return TRUE;
}

@end
