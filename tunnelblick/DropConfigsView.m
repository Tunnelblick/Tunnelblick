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
    
    NSArray * acceptedExtensions = [NSArray arrayWithObjects: @"ovpn", @"conf", @"tblk", nil];
    
    NSString * type = [pboard availableTypeFromArray: [NSArray arrayWithObject: NSFilenamesPboardType]];
    if (  ! [type isEqualToString: NSFilenamesPboardType]  ) {
        TBLog(@"DB-DD", @"DropConfigsView/acceptedExtensions: returning NO because no 'NSFilenamesPboardType' entries are available in the pasteboard.");
        return NO;
    }
    
    NSArray * paths = [pboard propertyListForType: NSFilenamesPboardType];
    NSUInteger i;
    for (  i=0; i<[paths count]; i++  ) {
        NSString * path = [paths objectAtIndex:i];
        if (  ! [acceptedExtensions containsObject: [path pathExtension]]  ) {
            TBLog(@"DB-DD", @"DropConfigsView/acceptedExtensions: returning NO for '%@' in '%@'", [path lastPathComponent], [path stringByDeletingLastPathComponent]);
            return NO;
        } else {
            TBLog(@"DB-DD", @"DropConfigsView/acceptedExtensions: acceptable: '%@' in '%@'", [path lastPathComponent], [path stringByDeletingLastPathComponent]);
        }
    }
    
    return YES;
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    
    NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
    NSPasteboard * pboard = [sender draggingPasteboard];
    
    if (  [[pboard types] containsObject: NSFilenamesPboardType]  ) {
        if (  [self canAcceptFileTypesInPasteboard: pboard]  ) {
            if (  sourceDragMask & NSDragOperationCopy  ) {
                TBLog(@"DB-DD", @"DropConfigsView/draggingEntered: returning YES");
                return NSDragOperationCopy;
            } else {
                TBLog(@"DB-DD", @"DropConfigsView/draggingEntered: returning NO because source does not allow copy operation");
            }
        }
    }
    
    TBLog(@"DB-DD", @"DropConfigsView/draggingEntered: returning NO");
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    
    NSPasteboard *pboard = [sender draggingPasteboard];
    
    if ( [[pboard types] containsObject: NSFilenamesPboardType] ) {
        NSArray * files = [pboard propertyListForType:NSFilenamesPboardType];
        [((MenuController *)[NSApp delegate]) performSelectorOnMainThread: @selector(openFiles:) withObject: files waitUntilDone: NO];
        TBLog(@"DB-DD", @"DropConfigsView/performDragOperation: returning YES");
        return YES;
    }
    
    TBLog(@"DB-DD", @"DropConfigsView/performDragOperation: returning NO because pasteboard does not contain 'NSFilenamesPboardType'");
    return NO;
}

@end
