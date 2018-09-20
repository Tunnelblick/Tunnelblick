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

/*  ImportWindowController
 *
 *  This class controls the window for mapping usernames when importing a .tblkSetup
 *
 */

#import "defines.h"

@class TBPopUpButton;

@interface ImportWindowController : NSWindowController <NSWindowDelegate,NSTableViewDelegate> {

	NSArray						* sourceUsernames;			// Usernames in .tblkSetup -- left column
	NSArray						* targetUsernames;			// Usernames on this computer -- each right column popup button has each of these plus a "(Do not import)"
	
	NSMutableArray				* popUpButtonIndexes;		// Index into the popup button for each sourceUsername
	
	id							  mappingStringTarget;		// Target and selector to send a mapping string when user clicks the "OK" button
	SEL							  mappingStringSelector;
	
	BOOL						  alreadyAwakened;			// Have already done awakeFromNib. (It gets invoked multiple times, each time a table cell view is requested.)
	
	IBOutlet NSTextField        * mainTextTF;
	IBOutlet NSTextFieldCell    * mainTextTFC;
	
	IBOutlet NSScrollView       * mainScrollView;
	
	IBOutlet NSTableView		* mainTableView;
	IBOutlet NSTableColumn      * mainTableSourceColumn;
	IBOutlet NSTableColumn      * mainTableTargetColumn;
	
	
	IBOutlet NSButton			* cancelButton;
	
	IBOutlet NSButton			* okButton;
}

-(IBAction) cancelButtonWasClicked: (NSButton *) sender;

-(IBAction) okButtonWasClicked: (NSButton *) sender;

// Sets the target/selector for setting a mapping string.
// When the "OK" button is clicked, this target/selector is used to set the mapping string.
-(void) setMappingStringTarget: (id) target selector: (SEL) selector;


-(NSInteger) numberOfRowsInTableView: (NSTableView *) tableView;
-(id)        tableView: (NSTableView *) tableView objectValueForTableColumn:               (NSTableColumn *) tableColumn row: (NSInteger) row;
-(void)      tableView: (NSTableView *) tableview setObjectValue: (id) obj forTableColumn: (NSTableColumn *) tableColumn row: (int) row;

TBPROPERTY(NSArray *,        sourceUsernames,    setSourceUsernames)
TBPROPERTY(NSArray *,        targetUsernames,    setTargetUsernames)
TBPROPERTY(NSMutableArray *, popUpButtonIndexes, setPopUpButtonIndexes)

@end
