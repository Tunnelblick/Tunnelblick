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
 *  distribution); if not, see http://www.gnu.org/licenses/.
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
#import "UIHelper.h"
#import "VPNConnection.h"

extern NSString       * gDeployPath;
extern MenuController * gMC;
extern NSString       * gPrivatePath;
extern TBUserDefaults * gTbDefaults;

// A cell in the list of configurations: the icon is on a small rounded "chip", which is lighter while the row is selected.

@interface TBLeftNavCellView : NSTableCellView {
    NSView * chip;
}
-(void) setChip: (NSView *) newChip;
@end

@implementation TBLeftNavCellView

-(void) setChip: (NSView *) newChip {
    chip = newChip; // Not retained: it is a subview
}

-(void) updateChipColor {
    BOOL emphasized = ([self backgroundStyle] == NSBackgroundStyleEmphasized);
    NSColor * color = (  emphasized
                       ? [NSColor colorWithWhite: 1.0 alpha: 0.22]
                       : [NSColor quaternaryLabelColor]);
    [self setWantsLayer: YES];
    [[chip layer] setBackgroundColor: [color CGColor]];
    [[self imageView] setContentTintColor: (  emphasized
                                            ? [NSColor whiteColor]
                                            : [NSColor secondaryLabelColor])];
}

-(void) setBackgroundStyle: (NSBackgroundStyle) backgroundStyle {
    [super setBackgroundStyle: backgroundStyle];
    [self updateChipColor];
}

-(void) viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateChipColor]; // Layer colors do not follow dark/light mode by themselves
}

@end


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
            localName = [gMC localizedNameForDisplayName: displayName];
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
    NSArray * sortedNames = [[gMC logScreen] leftNavDisplayNames];
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

// The list is view-based: each configuration or folder shows an icon and its name, and each configuration shows a dot:
// green when connected, orange between connected and disconnected, gray when disconnected.

static NSString * const LeftNavHeaderCellIdentifier = @"LeftNavHeaderCell";
static NSString * const LeftNavItemCellIdentifier   = @"LeftNavItemCell";
static NSString * const LeftNavStatusDotIdentifier  = @"LeftNavStatusDot";

-(NSColor *) statusColorForItem: (LeftNavItem *) item {
    
    NSString * displayName = [item displayName];
    if (   ([displayName length] == 0)
        || [displayName hasSuffix: @"/"]  ) {
        return nil; // Root or folder
    }
    
    VPNConnection * connection = [gMC connectionForDisplayName: displayName];
    if (  [connection isConnected]  ) {
        return [NSColor systemGreenColor];
    }
    if (   connection
        && ( ! [connection isDisconnected] )  ) {
        return [NSColor systemOrangeColor];
    }
    return (  connection
            ? [NSColor tertiaryLabelColor]
            : nil);
}

-(void) updateStatusDotInCell: (NSTableCellView *) cell forItem: (LeftNavItem *) item {
    
    NSView * dot = nil;
    NSView * view;
    NSEnumerator * e = [[cell subviews] objectEnumerator];
    while (  (view = [e nextObject])  ) {
        if (  [[view identifier] isEqualToString: LeftNavStatusDotIdentifier]  ) {
            dot = view;
        }
    }
    
    NSColor * color = [self statusColorForItem: item];
    [dot setHidden: (color == nil)];
    [[dot layer] setBackgroundColor: [color CGColor]];
}

-(NSTableCellView *) newItemCellWithIdentifier: (NSString *) identifier {
    
    TBLeftNavCellView * cell = [[TBLeftNavCellView alloc] initWithFrame: NSMakeRect(0.0, 0.0, 200.0, 24.0)];
    [cell setIdentifier: identifier];
    
    NSView * chip = [[[NSView alloc] init] autorelease];
    [chip setWantsLayer: YES];
    [[chip layer] setCornerRadius: 6.0];
    [chip setTranslatesAutoresizingMaskIntoConstraints: NO];
    [cell addSubview: chip];
    [cell setChip: chip];
    
    NSImageView * imageView = [[[NSImageView alloc] init] autorelease];
    [imageView setTranslatesAutoresizingMaskIntoConstraints: NO];
    [imageView setSymbolConfiguration: [NSImageSymbolConfiguration configurationWithPointSize: 11.0 weight: NSFontWeightSemibold]];
    [cell addSubview: imageView];
    [cell setImageView: imageView];
    
    NSTextField * textField = [NSTextField labelWithString: @""];
    [textField setTranslatesAutoresizingMaskIntoConstraints: NO];
    [textField setLineBreakMode: NSLineBreakByTruncatingTail];
    [textField setEditable: YES];
    [textField setDelegate: (id <NSTextFieldDelegate>) self];
    [[textField cell] setSendsActionOnEndEditing: YES];
    [textField setContentCompressionResistancePriority: NSLayoutPriorityDefaultLow forOrientation: NSLayoutConstraintOrientationHorizontal];
    [cell addSubview: textField];
    [cell setTextField: textField];
    
    NSView * dot = [[[NSView alloc] init] autorelease];
    [dot setIdentifier: LeftNavStatusDotIdentifier];
    [dot setWantsLayer: YES];
    [[dot layer] setCornerRadius: 4.0];
    [dot setTranslatesAutoresizingMaskIntoConstraints: NO];
    [dot setHidden: YES];
    [cell addSubview: dot];
    
    [NSLayoutConstraint activateConstraints: @[[[chip leadingAnchor]       constraintEqualToAnchor: [cell leadingAnchor] constant: 0.0],
                                               [[chip centerYAnchor]       constraintEqualToAnchor: [cell centerYAnchor]],
                                               [[chip widthAnchor]         constraintEqualToConstant: 22.0],
                                               [[chip heightAnchor]        constraintEqualToConstant: 22.0],
                                               [[imageView centerXAnchor]  constraintEqualToAnchor: [chip centerXAnchor]],
                                               [[imageView centerYAnchor]  constraintEqualToAnchor: [chip centerYAnchor]],
                                               [[textField leadingAnchor]  constraintEqualToAnchor: [chip trailingAnchor] constant: 8.0],
                                               [[textField centerYAnchor]  constraintEqualToAnchor: [cell centerYAnchor]],
                                               [[dot leadingAnchor]        constraintGreaterThanOrEqualToAnchor: [textField trailingAnchor] constant: 6.0],
                                               [[dot trailingAnchor]       constraintEqualToAnchor: [cell trailingAnchor] constant: -8.0],
                                               [[dot centerYAnchor]        constraintEqualToAnchor: [cell centerYAnchor]],
                                               [[dot widthAnchor]          constraintEqualToConstant: 8.0],
                                               [[dot heightAnchor]         constraintEqualToConstant: 8.0]]];
    if (  [UIHelper languageAtLaunchWasRTL]  ) {
        [UIHelper setRightToLeftLayoutIn: cell containersOnly: NO];
    }
    return cell;
}

-(NSView *) outlineView: (NSOutlineView *) outlineView
     viewForTableColumn: (NSTableColumn *) tableColumn
                   item: (id)              item {
    
    (void) tableColumn;
    
    NSString * name = [(LeftNavItem *) item nameToShowInOutlineView];
    
    if (  [outlineView rowForItem: item] == 0  ) {
        NSTableCellView * header = [outlineView makeViewWithIdentifier: LeftNavHeaderCellIdentifier owner: self];
        if (  ! header  ) {
            header = [[[NSTableCellView alloc] initWithFrame: NSMakeRect(0.0, 0.0, 200.0, 20.0)] autorelease];
            [header setIdentifier: LeftNavHeaderCellIdentifier];
            NSTextField * textField = [NSTextField labelWithString: @""];
            [textField setTranslatesAutoresizingMaskIntoConstraints: NO];
            [textField setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize] weight: NSFontWeightSemibold]];
            [textField setTextColor: [NSColor secondaryLabelColor]];
            [header addSubview: textField];
            [header setTextField: textField];
            [NSLayoutConstraint activateConstraints: @[[[textField leadingAnchor]  constraintEqualToAnchor: [header leadingAnchor]],
                                                       [[textField trailingAnchor] constraintLessThanOrEqualToAnchor: [header trailingAnchor]],
                                                       [[textField centerYAnchor]  constraintEqualToAnchor: [header centerYAnchor]]]];
            if (  [UIHelper languageAtLaunchWasRTL]  ) {
                [UIHelper setRightToLeftLayoutIn: header containersOnly: NO];
            }
        }
        [[header textField] setStringValue: (name ? name : @"")];
        return header;
    }
    
    NSTableCellView * cell = [outlineView makeViewWithIdentifier: LeftNavItemCellIdentifier owner: self];
    if (  ! cell  ) {
        cell = [[self newItemCellWithIdentifier: LeftNavItemCellIdentifier] autorelease];
    }
    
    BOOL isFolder = ([(LeftNavItem *) item numberOfChildren] != -1);
    [[cell imageView] setImage: [NSImage imageWithSystemSymbolName: (isFolder ? @"folder.fill" : @"shield.fill")
                                          accessibilityDescription: nil]];
    [[cell textField] setStringValue: (name ? name : @"")];
    [self updateStatusDotInCell: cell forItem: item];
    return cell;
}

-(void) refreshStatusInOutlineView: (NSOutlineView *) outlineView {
    
    // Called when a connection's status changes
    NSInteger row;
    for (  row = 1; row < [outlineView numberOfRows]; row++  ) {
        NSTableCellView * cell = [outlineView viewAtColumn: 0 row: row makeIfNecessary: NO];
        if (  cell  ) {
            [self updateStatusDotInCell: cell forItem: [outlineView itemAtRow: row]];
        }
    }
}

-(void) controlTextDidEndEditing: (NSNotification *) notification {
    
    // A configuration or folder name was edited in place
    NSTextField * textField = [notification object];
    NSOutlineView * outlineView = nil;
    NSView * view = [textField superview];
    while (  view  ) {
        if (  [view isKindOfClass: [NSOutlineView class]]  ) {
            outlineView = (NSOutlineView *) view;
            break;
        }
        view = [view superview];
    }
    
    NSInteger row = [outlineView rowForView: textField];
    if (  row < 1  ) {
        return;
    }
    
    LeftNavItem * item = [outlineView itemAtRow: row];
    NSString * newName = [textField stringValue];
    NSString * oldName = [item nameToShowInOutlineView];
    if (   ([newName length] == 0)
        || [newName isEqualToString: oldName]  ) {
        [textField setStringValue: (oldName ? oldName : @"")];
        return;
    }
    
    [self outlineView: outlineView setObjectValue: newName forTableColumn: nil byItem: item];
}

-(BOOL) outlineView: (NSOutlineView *) outlineView
        isGroupItem: (id) item {
    
    // The root item is shown as the heading of the list
    return ([outlineView rowForItem: item] == 0);
}

-(BOOL)             outlineView: (NSOutlineView *) outlineView
  shouldShowOutlineCellForItem: (id) item {
    
    // The root item cannot be collapsed, so it does not get a disclosure triangle
    return ([outlineView rowForItem: item] != 0);
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
	
	MyPrefsWindowController * mpwc = [gMC logScreen];
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

    if ( [newName hasSuffix: @".tblk"]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString(@"A folder name cannot end in '.tblk'", @"Window text."));
        return;
    }

    if (  displayNameIsValid(newName, NO)  ) {
        NSString * sourceDisplayName = [item displayName];
        if (  [sourceDisplayName hasSuffix: @"/"]  ) {
            NSString * targetDisplayName = [[[sourceDisplayName stringByDeletingLastPathComponent]
                                             stringByAppendingPathComponent: newName]
                                            stringByAppendingString: @"/"];
            [ConfigurationManager renameFolderInNewThreadWithDisplayName: sourceDisplayName toDisplayName: targetDisplayName];
        } else {
            VPNConnection * connection   = [gMC connectionForDisplayName: sourceDisplayName];
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

    // Get the source displayNames and paths
    NSString * sourceDisplayName = nil;
    NSPasteboard * pb = [info draggingPasteboard];
    NSArray * pbItems = [pb pasteboardItems];
    NSMutableArray * sourceDisplayNames = [[[NSMutableArray alloc] initWithCapacity: [pbItems count]] autorelease];
    BOOL haveAFolder = FALSE;
    BOOL haveAConfig = FALSE;
    NSUInteger i;
    for (  i=0; i<[pbItems count]; i++  ) {

        NSPasteboardItem * pbItem = [pbItems objectAtIndex: i];
        sourceDisplayName = [pbItem stringForType: TB_LEFT_NAV_ITEMS_DRAG_ID];
        if (  ! sourceDisplayName  ) {
            NSLog(@"infoForDropInfo:item: Could not get stringForType for pbItem = %@ in pbItems = %@ from pb = %@", pbItem, pbItems, pb);
            return nil;
        }

        BOOL isFolder = [sourceDisplayName hasSuffix: @"/"];

        if (   (   isFolder
                && haveAConfig )
            || (   ( ! isFolder )
                && haveAFolder )
            ) {
            TBLog(@"DB-D2", @"Dragging configurations and folders simultanously is not allowed");
            return nil;
        }

        if (   isFolder
            && haveAFolder  ) {
            TBLog(@"DB-D2", @"Dragging more than one folder at a time is not allowed");
            return nil;
        }

        if (  [sourceDisplayName isEqualToString: @""]  ) {
            TBLog(@"DB-D2", @"Dragging the 'Configurations' header line is not allowed");
            return nil;
        }
        
        haveAFolder = haveAFolder || isFolder;
        haveAConfig = haveAConfig || ( ! isFolder);

        [sourceDisplayNames addObject: sourceDisplayName];
    }

    // Make sure it is OK to drag the source

    if (  [sourceDisplayNames count] == 0  ) {
        TBLog(@"DB-D2", @"No sources selected");
        return nil;
    }

    // For folders, we send source and target displayName, for configurations, we send source and target paths
    NSMutableArray * sourcePaths = nil;
    NSMutableArray * targetPaths = nil;

    BOOL sourceIsFolder = haveAFolder;

    if (  sourceIsFolder  ) {

        // Dragging a folder
        if (   copy
            && ( [sourceDisplayNames count] > 1 )  ) {
            TBLog(@"DB-D2", @"Copying multiple folders is not currently implemented");
            return nil;
        }

        sourceDisplayName = [sourceDisplayNames firstObject];

    } else {

        // Dragging one or more configurations; get the source paths
        sourcePaths = [[[NSMutableArray alloc] initWithCapacity: [sourceDisplayNames count]] autorelease];
        NSDictionary * configs = [gMC myConfigDictionary];

        for (  i=0; i<[sourceDisplayNames count]; i++  ) {
            NSString * sourceDisplayName2 = [sourceDisplayNames objectAtIndex: i];
            NSString * sourcePath = [configs objectForKey: sourceDisplayName2];
            if (  ! sourcePath  ) {
                NSLog(@"infoForDropInfo:item: Could not get path for configuration '%@' from myConfigDictionary = %@", sourceDisplayName2, configs);
                return nil;
            }

            if (   [sourcePath hasPrefix: gDeployPath]
                && ( ! copy  )  ) {
                NSLog(@"Can't move a Deployed configuration (but can copy it)");
                return nil;
            }

            [sourcePaths addObject: sourcePath];
        }
    }

    // Make sure it is OK to drop on the target

    NSString * targetDisplayName = nil;

    NSString * targetDisplayNameWithoutLastComponent = [item displayName];
    if (  ! targetDisplayNameWithoutLastComponent  ) {
        TBLog(@"DB-D2", @"Dropping to the left of the list (off the list)");
        return nil;
    }

    BOOL targetIsFolder = (   [targetDisplayNameWithoutLastComponent isEqualToString: @""] // "Configurations" header or below the bottom of the list
                           || [targetDisplayNameWithoutLastComponent hasSuffix: @"/"]);

    if (  ! targetIsFolder  ) {
        TBLog(@"DB-D2", @"Dropping on configurations is not allowed");
        return nil;
    }

    // Target is a folder

    if (  sourceIsFolder  ) {
        if (  [targetDisplayNameWithoutLastComponent hasPrefix: sourceDisplayName]  ) {
            TBLog(@"DB-D2", @"Copying or moving a folder onto itself or into one of its subfolders is not allowed");
            return nil;
        }
    }

    for (  i=0; i<[sourceDisplayNames count]; i++  ) {
        NSString * sourceDisplayName3 = [sourceDisplayNames objectAtIndex: i];
        NSString * folderEnclosingSource = [sourceDisplayName3 stringByDeletingLastPathComponent];
        if (  [sourceDisplayName3 hasSuffix: @"/"]) {
            folderEnclosingSource = [folderEnclosingSource stringByAppendingString: @"/"];
        }
        if (  [targetDisplayNameWithoutLastComponent isEqualToString: folderEnclosingSource]  ) {
            TBLog(@"DB-D2", @"Moving or copying a folder or a configuration into the folder that it is already in is not allowed");
            return nil;
        }
    }

    // Append the last path component of the source to the target displayName to get the target displayName
    NSMutableArray * targetDisplayNames = [[[NSMutableArray alloc] initWithCapacity: [sourceDisplayNames count]] autorelease];
    for (  i=0; i<[sourceDisplayNames count]; i++  ) {
        NSString * sourceDisplayName4 = [sourceDisplayNames objectAtIndex: i];
        targetDisplayName = [[targetDisplayNameWithoutLastComponent
                              stringByAppendingPathComponent: [sourceDisplayName4 lastPathComponent]]
                             stringByAppendingString: (  sourceIsFolder
                                                       ? @"/"
                                                       : @"")];
        [targetDisplayNames addObject: targetDisplayName];
    }


    // If dragging a folder, use the source displayName that is already set and set the targetPath.
    // If dragging one or more configurations, use the source paths already set and set the target paths.

    if (  sourceIsFolder  ) {
        targetDisplayName = [targetDisplayNames firstObject];
    } else {
        targetPaths = [[[NSMutableArray alloc] initWithCapacity: [sourceDisplayNames count]] autorelease];
        for (  i=0; i<[sourceDisplayNames count]; i++  ) {
            NSString * targetDisplayName5 = [targetDisplayNames objectAtIndex: i];
            NSString * targetPath = [[firstPartOfPath([sourcePaths objectAtIndex: i])
                                      stringByAppendingPathComponent: targetDisplayName5]
                                     stringByAppendingPathExtension: @"tblk"];
            [targetPaths addObject: targetPath];
        }
    }

    NSNumber * moveNotCopy     = [NSNumber numberWithBool: ( ! copy )];
    NSNumber * folderNotConfig = [NSNumber numberWithBool: sourceIsFolder];
    NSDictionary * result = [NSDictionary dictionaryWithObjectsAndKeys:
                             moveNotCopy,                    @"moveNotCopy",
                             folderNotConfig,                @"folderNotConfig",
                             NSNullIfNil(targetPaths),       @"targetPaths",
                             NSNullIfNil(sourcePaths),       @"sourcePaths",
                             NSNullIfNil(targetDisplayName), @"targetDisplayName",
                             NSNullIfNil(sourceDisplayName), @"sourceDisplayName",
                             nil];

    if (  sourceIsFolder  ) {
        TBLog(@"DB-D2", @"folder %s; cpy %s; srcNames = '%@'; tgtNames = '%@'", CSTRING_FROM_BOOL(sourceIsFolder), CSTRING_FROM_BOOL(copy), sourceDisplayNames, targetDisplayNames);
    } else {
        TBLog(@"DB-D2", @"folder %s; cpy %s; srcPaths = '%@'; tgtPaths = '%@'", CSTRING_FROM_BOOL(sourceIsFolder), CSTRING_FROM_BOOL(copy), sourcePaths, targetPaths);
    }

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

    BOOL draggingWithinFolder = FALSE;
    if (  folderNotConfig  ) {
        NSString * sourceDisplayName =  [dict objectForKey: @"sourceDisplayName"];
        NSString * targetDisplayName =  [dict objectForKey: @"targetDisplayName"];
        if (  [sourceDisplayName isEqualToString: targetDisplayName]  ) {
            draggingWithinFolder = TRUE;
        }
    } else {
        NSArray * sourcePaths =  [dict objectForKey: @"sourcePaths"];
        NSArray * targetPaths =  [dict objectForKey: @"targetPaths"];
        NSUInteger i;
        for (  i=0; i<[sourcePaths count]; i++  ) {
            NSString * sourcePath = [sourcePaths objectAtIndex: i];
            NSString * targetPath = [targetPaths objectAtIndex: i];
            if (  [sourcePath isEqualToString: targetPath]  ) {
                draggingWithinFolder = TRUE;
                break;
            }
        }
    }
    if (  draggingWithinFolder  ) {
        TBLog(@"DB-D2", @"Dragging within a folder is not allowed");
        return NSDragOperationNone;
    }

    if (  [[dict objectForKey: @"moveNotCopy"] boolValue]  ) {
        return NSDragOperationMove;
    } else {
        return NSDragOperationCopy;
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

    BOOL       moveNotCopy       = [[dict objectForKey: @"moveNotCopy"]     boolValue];
    BOOL       folderNotConfig   = [[dict objectForKey: @"folderNotConfig"] boolValue];
    NSArray  * sourcePaths       =  [dict objectForKey: @"sourcePaths"];
    NSArray  * targetPaths       =  [dict objectForKey: @"targetPaths"];
    NSString * sourceDisplayName =  [dict objectForKey: @"sourceDisplayName"];
    NSString * targetDisplayName =  [dict objectForKey: @"targetDisplayName"];

    // Copy or move the item. If successful, the method will reload the data for the outlineView

    if (  folderNotConfig  ) {
        if (  moveNotCopy  ) {
            // Instead of moving source to target, we rename source to target/source
            [ConfigurationManager renameFolderInNewThreadWithDisplayName: sourceDisplayName toDisplayName: targetDisplayName];
        } else {
            [ConfigurationManager copyFolderInNewThreadWithDisplayName: sourceDisplayName toDisplayName: targetDisplayName];
        }

    } else {
        [ConfigurationManager moveOrCopyConfigurationsInNewThreadAtPaths: sourcePaths toPaths: targetPaths moveNotCopy: moveNotCopy];
    }
    return TRUE;
}

@end
