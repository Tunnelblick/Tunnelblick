/*
 * Copyright 2013, 2014 Jonathan K. Bullard. All rights reserved.
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

#import "LeftNavViewController.h"

@implementation TBSidebarOutlineView

// While hidesSelection is set, the selected rows are drawn as not selected. The selection itself is not changed.

-(void) updateRowViewsSelection {
    NSInteger row;
    for (  row = 0; row < [self numberOfRows]; row++  ) {
        NSTableRowView * rowView = [self rowViewAtRow: row makeIfNecessary: NO];
        if (  rowView  ) {
            [rowView setSelected: (   ( ! hidesSelection )
                                   && [self isRowSelected: row])];
        }
    }
}

-(void) setHidesSelection: (BOOL) newValue {
    if (  hidesSelection != newValue  ) {
        hidesSelection = newValue;
        [self updateRowViewsSelection];
    }
}

-(void) didAddRowView: (NSTableRowView *) rowView forRow: (NSInteger) row {
    [super didAddRowView: rowView forRow: row];
    if (  hidesSelection  ) {
        [rowView setSelected: NO];
    }
}

-(void) selectRowIndexes: (NSIndexSet *) indexes byExtendingSelection: (BOOL) extend {
    [super selectRowIndexes: indexes byExtendingSelection: extend];
    if (  hidesSelection  ) {
        [self updateRowViewsSelection];
    }
}

@end

@implementation LeftNavViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
	
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void) dealloc {
	
    [super dealloc];
}

TBSYNTHESIZE_OBJECT(retain, NSOutlineView *, outlineView, setOutlineView )

@end

