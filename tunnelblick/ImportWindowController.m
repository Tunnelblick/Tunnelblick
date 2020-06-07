/*
 * Copyright 2018 Jonathan Bullard
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


#import "ImportWindowController.h"

#import <libkern/OSAtomic.h>

#import "sharedRoutines.h"
#import "UIHelper.h"

#import "MenuController.h"
#import "TBPopUpButton.h"

extern MenuController * gMC;

@interface ImportWindowController ()

@end

@implementation ImportWindowController

TBSYNTHESIZE_OBJECT(retain, NSArray *,        sourceUsernames,     setSourceUsernames)
TBSYNTHESIZE_OBJECT(retain, NSArray *,        targetUsernames,     setTargetUsernames)
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, popUpButtonIndexes,  setPopUpButtonIndexes)
TBSYNTHESIZE_OBJECT(retain, NSString *,       mappingStringTarget, setMappingStringTarget)
TBSYNTHESIZE_OBJECT(retain, NSTableView *,    mainTableView,       setMainTableView)

-(id) init {
	
	self = [super initWithWindowNibName: @"ImportWindow"];
	if (  ! self  ) {
		return nil;
	}
	
	[gMC setShowingImportSetupWindow: TRUE];
	
	alreadyAwakened = FALSE;
	return self;
}

- (void) dealloc {
	
	[sourceUsernames            release];
	[targetUsernames            release];
	[popUpButtonIndexes			release];
	[mappingStringTarget        release];
	
	[super dealloc];
}

-(void) setMappingStringTarget: (id) target selector: (SEL) selector {
	
	[self setMappingStringTarget: target];
	mappingStringSelector = selector;
}

-(void) windowWillClose:(NSNotification *)notification {
	
	(void)notification;
	
	[gMC setShowingImportSetupWindow: FALSE];
}

-(void) cancelOperation: (id) sender {
	
	[self cancelButtonWasClicked: sender];
}

-(IBAction) cancelButtonWasClicked: (NSButton *) sender {
	
	(void)sender;
	
	[[self window] close];
}

-(IBAction) okButtonWasClicked: (NSButton *) sender {

	(void)sender;
	
	NSString * mappingString = [self mappingString];
	
	[mappingStringTarget performSelector: mappingStringSelector withObject: mappingString];

	[[self window] close];
}

-(NSString *) mappingString {
	
	NSMutableString * map = [[[NSMutableString alloc] initWithCapacity: 1000] autorelease];
	
	NSUInteger ix;
	for (  ix=0; ix<[sourceUsernames count]; ix++  ) {
		NSString * sourceName = [sourceUsernames objectAtIndex: ix];
		NSUInteger n = [[popUpButtonIndexes objectAtIndex: ix] unsignedIntegerValue];
		if (  n != 0  ) {
			[map appendFormat: @"%@:%@\n", sourceName, [targetUsernames objectAtIndex: n - 1]];
		}
	}
	
	return [NSString stringWithString: map];
}

-(void) awakeFromNib {

	if (  alreadyAwakened  ) {
		return;
	}
	
	alreadyAwakened = TRUE;
	
	[self setupPopUpButtons];
	
	CGFloat windowHeightChange = [self setupContents];
	
	[self setupTableView];
	
	[mainScrollView setDocumentView: mainTableView];

	[self adjustWindowHeightAfterWindowHeightChange: windowHeightChange];
	
	NSWindow * w = [self window];
	[w setTitle: NSLocalizedString(@"Import a Tunnelblick Setup", @"Window title")];
	[w setDefaultButtonCell: [cancelButton cell]];
	
	[w setReleasedWhenClosed: YES];
	[w center];
	[w display];
	[self showWindow: self];
	
	[NSApp activateIgnoringOtherApps: YES];
	
	[w makeKeyAndOrderFront: self];
}

-(void) setupPopUpButtons {
	
	// Create the popUpButtonIndexes array containing the selected index of the popup button for each sourceUsername
	// Each button has a "(Do not import)" entry first, and then an entry for each targetUsername
	//
	// Selects an entry if it has the same targetUsername as the corresponding sourceUsername, otherwise selects the first entry ("Do not import").
	
	NSMutableArray * buttonIndexes = [[[NSMutableArray alloc] initWithCapacity: [sourceUsernames count]] autorelease];
	NSUInteger ix;
	for (  ix=0; ix<[sourceUsernames count]; ix++  ) {
		NSString * sourceUsername = [sourceUsernames objectAtIndex: ix];
		NSUInteger ix3 = [targetUsernames indexOfObject: sourceUsername];
		if (  ix3 == NSNotFound  ) {
			ix3 = 0; //"(Do not import)"
		} else {
			ix3 = ix3 + 1; // " + 1" to account for the "(Do not import)" entry
		}

		[buttonIndexes addObject: [NSNumber numberWithUnsignedInteger: ix3]];
	}
	
	[self setPopUpButtonIndexes: buttonIndexes];
}

-(CGFloat) setupContents {
	
	// Set up the window content
	
	[okButton setTitle: NSLocalizedString(@"OK", @"Button")];
	[okButton sizeToFit];
	
	[cancelButton setTitle: NSLocalizedString(@"Cancel", @"Button")];
	[cancelButton sizeToFit];

	// mainTextTF changes height. We adjust the window height by the same amount so that mainTableView stays
	// the same height as in the nib. Then in adjustWindowHeightAfterWindowHeightChange: we adjust the window
	// to fit mainTableView for the number of rows of data.

	[mainTextTFC setTitle: NSLocalizedString(@"Select a target user for each user whose setup data you wish to import.",
											 @"Window text")];
	CGFloat oldHeight = [mainTextTF frame].size.height;
	[mainTextTF sizeToFit];
	CGFloat heightChange = [mainTextTF frame].size.height - oldHeight;
	NSRect windowFrame = [[self window] frame];
	windowFrame.size.height += heightChange;
	[[self window] setFrame: windowFrame display: NO];
	return heightChange;
}

-(void)setupTableView {
	
	// Replace the NSTableView in the nib with a newly-generated one
	NSRect tvFrame = [mainTableView bounds];
	[self setMainTableView: [[[NSTableView alloc] initWithFrame: tvFrame] autorelease]];
	
	CGFloat columnWidth = (tvFrame.size.width - 7) / 2; // "7" is width of the NSTableView borders and padding
	
	BOOL rtl = [gMC languageAtLaunchWasRTL];
	
	// First column has sourceUsernames
	NSTableColumn * sourceColumn = [[[NSTableColumn alloc] initWithIdentifier: @"source"] autorelease];
	[sourceColumn setWidth: columnWidth];
	[[sourceColumn headerCell] setStringValue: NSLocalizedString(@"User in setup data",
																 @"Column heading in a table. The \"setup data\" is data from a Tunnelblick installation (configurations and settings) created by the \"Export Tunnelblick Setup\" button on the \"Utilities\" panel of the \"VPN Details\" window.")];
	NSTextAlignment align = (rtl ? NSTextAlignmentLeft : NSTextAlignmentRight);
	[[sourceColumn headerCell] setAlignment: align];
	[[sourceColumn dataCell]   setAlignment: align];
	
	
	// Second column has popup menus with "(Do not import)" and targetUsernames
	NSTableColumn * targetColumn = [[[NSTableColumn alloc] initWithIdentifier: @"target"] autorelease];
	[targetColumn setWidth: columnWidth];
	[[targetColumn headerCell] setStringValue: NSLocalizedString(@"User on this computer", @"Column heading in a table")];
	align = (rtl ? NSTextAlignmentRight : NSTextAlignmentLeft);
	[[targetColumn headerCell] setAlignment: align];
	[[targetColumn dataCell]   setAlignment: align];
	
	NSPopUpButtonCell * popupCell = [[[NSPopUpButtonCell alloc] initTextCell: NSLocalizedString(@"(Do not import)", @"Popup button menu item") pullsDown: NO] autorelease];
	if (  rtl  ) {
		[popupCell setAlignment: NSTextAlignmentRight];
	}
	[popupCell addItemsWithTitles: targetUsernames];
	
	[targetColumn setDataCell: popupCell];

	if (  rtl  ) {
		[mainTableView addTableColumn: targetColumn];
		[mainTableView addTableColumn: sourceColumn];
	} else {
		[mainTableView addTableColumn: sourceColumn];
		[mainTableView addTableColumn: targetColumn];
	}
	
	[mainTableView setRowHeight:10000.0];
	[mainTableView setAutoresizesSubviews:YES];
	
	[mainTableView setAllowsColumnSelection: NO];
	[mainTableView setAllowsMultipleSelection: NO];
	[mainTableView setAllowsEmptySelection: YES];
	
	[mainTableView setDelegate: self];
	[mainTableView setDataSource: (id)self];
}

-(void) adjustWindowHeightAfterWindowHeightChange: (CGFloat) windowHeightChange {
		
	// Adjust window height to reflect changes to the height of mainTableView because the data has a different number
	// of rows than the nib.
	
	NSRect frame = [[self window] frame];
	CGFloat heightChange = 8.0 - windowHeightChange + (24.0 * ((long)[sourceUsernames count] - 9));
	
	frame.size.height += heightChange;
	[[self window] setFrame: frame display: NO];
}

-(NSInteger) numberOfRowsInTableView: (NSTableView *) tableView {
	
	(void)tableView;
	
	return [popUpButtonIndexes count];
}


- (id)           tableView: (NSTableView *)   aTableView
 objectValueForTableColumn: (NSTableColumn *) aTableColumn
					   row: (NSInteger)       rowIndex {
	
	(void)aTableView;
	
	NSString * aString = (  [[aTableColumn identifier] isEqualToString: @"source"]
						  ? [sourceUsernames objectAtIndex: rowIndex]
						  : (  [[aTableColumn identifier] isEqualToString: @"target"]
							 ? [popUpButtonIndexes objectAtIndex: rowIndex]
							 : [NSString stringWithFormat: @"Invalid column identifier '%@'", [aTableColumn identifier]]));

	return aString;
}


-(void)      tableView: (NSTableView *)   tableView
		setObjectValue: (id)              value
		forTableColumn: (NSTableColumn *) tableColumn
				   row: (int)             row {
	
	(void)tableView;
	(void)tableColumn;

	[popUpButtonIndexes replaceObjectAtIndex: row withObject: value];
}

-(CGFloat)tableView: (NSTableView *) tableView heightOfRow:(NSInteger)row {
	
	(void)tableView;
	(void)row;
	
	return 22.0;
}
-(void)tableViewSelectionDidChange:(NSNotification *)notification {
	
	(void)notification;
	
	[mainTableView selectRowIndexes: [NSIndexSet indexSet] byExtendingSelection: NO];
}

@end
