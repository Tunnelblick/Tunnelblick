/*
 * Copyright 2016 Jonathan K. Bullard. All rights reserved.
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


#import "DropConfigsView.h"

#import "MenuController.h"
#import "TBUserDefaults.h"
#import "UIHelper.h"

extern  TBUserDefaults * gTbDefaults;

@implementation DropConfigsView

// *******************************************************************************************
// init and dealloc

-(id) initWithFrame: (NSRect) frame {
	
    self = [super initWithFrame: frame];
    if (self) {
        [self registerForDraggedTypes: [NSArray arrayWithObject: NSFilenamesPboardType]];
	}
    
    return self;
}

-(void) dealloc {
    
    [self unregisterDraggedTypes];

    [super dealloc];
}


// *******************************************************************************************
// Drag/Drop Event Handlers 

-(BOOL) canAcceptFileTypesInPasteboard: (NSPasteboard *) pboard {
    
	return [UIHelper canAcceptFileTypesInPasteboard: pboard ];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    
	return [UIHelper draggingEntered: sender];
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    
	return [UIHelper performDragOperation: sender];
}

@end
