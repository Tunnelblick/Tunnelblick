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
extern NSString       * gPrivatePath;
extern TBUserDefaults * gTbDefaults;

@implementation LeftNavDataSource

-(id) init {
    self = [super init];
    if (self) {
        itemsByDisplayName = [[NSMutableDictionary alloc] initWithCapacity: 100];
    }
    return self;    
}

-(void) dealloc {
    
    [itemsByDisplayName release]; itemsByDisplayName = nil;
    
    [super dealloc];
}

-(LeftNavItem *) itemForName: (NSString *) name {

    return [itemsByDisplayName objectForKey: name];
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
                    [itemsByDisplayName setObject: item forKey: displayName];
                    (*theRowPtr)++;
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
                [itemsByDisplayName setObject: item forKey: dispNm];
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
    
    [itemsByDisplayName removeAllObjects];

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

    (void)outlineView;

    NSString * name = [item displayName];
	BOOL val = ! [@"" isEqualToString: name];   // Allow selection of anything except the root item
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
	
    if (  displayNameIsValid(newName, NO)  ) {
        NSString * sourceDisplayName = [item displayName];
        if (  [sourceDisplayName hasSuffix: @"/"]  ) {
            [ConfigurationManager renameFolderInNewThreadWithDisplayName: sourceDisplayName toName: newName];
        } else {
            VPNConnection * connection   = [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] objectForKey: sourceDisplayName];
            if (  ! connection  ) {
                NSLog(@"Tried to rename configuration but no configuration has been selected");
                return;
            }
            NSString * sourcePath = [connection configPath];
            NSString * targetPath = [[[sourcePath stringByDeletingLastPathComponent]
                                      stringByAppendingPathComponent: newName]
                                     stringByAppendingPathExtension: @"tblk"];
            [ConfigurationManager renameConfigurationInNewThreadAtPath: sourcePath toPath: targetPath];
        }
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

    // For folders, we send source and target displayName, for configurations, we send source and target paths
    NSString * sourcePath = nil;
    NSString * targetPath = nil;
    NSString * targetDisplayName = nil;

    // Make sure it is OK to drag the source

    if (  [sourceDisplayName length] == 0  ) {
        // Allow drop to the outermost level (the "Configurations" level)
        sourceDisplayName = @"/";
    }

    BOOL sourceIsFolder = [sourceDisplayName hasSuffix: @"/"];

    if (  sourceIsFolder  ) {

        // Dragging a folder
        if (  copy  ) {
            // TODO: be able to copy a folder
            return nil;
        }

    } else {

        // Dragging a configuration; get the source path
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

    // Make sure it is OK to drop on the target

    targetDisplayName = [item displayName];
    if (  ! targetDisplayName  ) {
        // This happens when dragging past the end of the list. Pretend we are dragging to outermost level
        targetDisplayName = @"/";
    }
    if (  ! [targetDisplayName hasSuffix: @"/"]  ) {
        // Can't drop on configuration (configurations have names that doesn't end in "/")
        return nil;
    }

    // If dragging a folder, get the source and target displayNames.
    // If dragging a configuration, get the source and target paths.

    if (  ! sourceIsFolder  ) {
        // Get the target path, removing the last "/" and everything to its right
        NSRange r = [targetDisplayName rangeOfString: @"/" options: NSBackwardsSearch];
        NSString * prefix = (  (r.location == NSNotFound)
                             ? prefix = @""
                             : [targetDisplayName substringToIndex: r.location]);
        NSString * name = [prefix stringByAppendingPathComponent: [sourceDisplayName lastPathComponent]];
        targetPath = [[firstPartOfPath(sourcePath)
                                  stringByAppendingPathComponent: name]
                                 stringByAppendingPathExtension: @"tblk"];
    }

    NSNumber * copyNotMove     = [NSNumber numberWithBool: copy];
    NSNumber * folderNotConfig = [NSNumber numberWithBool: sourceIsFolder];
    NSDictionary * result = [NSDictionary dictionaryWithObjectsAndKeys:
                             copyNotMove,                    @"copyNotMove",
                             folderNotConfig,                @"folderNotConfig",
                             NSNullIfNil(targetPath),        @"targetPath",
                             NSNullIfNil(sourcePath),        @"sourcePath",
                             NSNullIfNil(targetDisplayName), @"targetDisplayName",
                             NSNullIfNil(sourceDisplayName), @"sourceDisplayName",
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

    BOOL       folderNotConfig   = [[dict objectForKey: @"folderNotConfig"] boolValue];
    NSString * sourcePath  =  [dict objectForKey: @"sourcePath"];
    NSString * targetPath  =  [dict objectForKey: @"targetPath"];
    NSString * sourceDisplayName =  [dict objectForKey: @"sourceDisplayName"];
    NSString * targetDisplayName =  [dict objectForKey: @"targetDisplayName"];

    if (  folderNotConfig  ) {
        if (  [sourceDisplayName isEqualToString: targetDisplayName]  ) {
            // Don't allow drag within a folder; it wouldn't do anything because folders are sorted alphanumerically
            return NSDragOperationNone;
        }
    } else {
        if (  [sourcePath isEqualToString: targetPath]  ) {
            // Don't allow drag within a folder; it wouldn't do anything because folders are sorted alphanumerically
            return NSDragOperationNone;
        }
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

    BOOL       copyNotMove       = [[dict objectForKey: @"copyNotMove"]     boolValue];
    BOOL       folderNotConfig   = [[dict objectForKey: @"folderNotConfig"] boolValue];
    NSString * sourcePath        =  [dict objectForKey: @"sourcePath"];
    NSString * targetPath        =  [dict objectForKey: @"targetPath"];
    NSString * sourceDisplayName =  [dict objectForKey: @"sourceDisplayName"];
    NSString * targetDisplayName =  [dict objectForKey: @"targetDisplayName"];

    // Copy or move the item. If successful, the method will reload the data for the outlineView

    if (  folderNotConfig  ) {
        if (  copyNotMove  ) {
            return false;   // TODO: copy folders
        } else {
            // Instead of moving source to target, we rename source to target/source
            NSString * renameTargetDisplayName = [targetDisplayName stringByAppendingString: sourceDisplayName];
            [ConfigurationManager renameFolderInNewThreadWithDisplayName: sourceDisplayName toName: renameTargetDisplayName];
        }

    } else {
        if (  copyNotMove  ) {
            [ConfigurationManager copyConfigurationInNewThreadPath: sourcePath toPath: targetPath];
        } else {
            [ConfigurationManager moveConfigurationInNewThreadAtPath:  sourcePath toPath: targetPath];
        }
    }
    return TRUE;
}

@end
