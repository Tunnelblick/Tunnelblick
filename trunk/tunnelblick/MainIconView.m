/*
 * Copyright 2012 Jonathan Bullard
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


#include "MainIconView.h"
#include "MenuController.h"
#include "TBUserDefaults.h"

extern  TBUserDefaults * gTbDefaults;

@implementation MainIconView

// *******************************************************************************************
// General Methods

-(void) mouseDownMainThread: (NSEvent *) theEvent
{
    // Invoked in the main thread only
	
    NSStatusItem * statusI = [[NSApp delegate] statusItem];
	NSMenu       * menu    = [[NSApp delegate] myVPNMenu];
    [statusI popUpStatusItemMenu: menu];
}

-(void) setOrRemoveTrackingRect
{
	if (  [gTbDefaults boolForKey: @"doNotShowNotificationWindowOnMouseover"]  ) {
        if (  mainIconTrackingRectTagIsValid  ) {
            [self removeTrackingRect: mainIconTrackingRectTag];
			mainIconTrackingRectTagIsValid = FALSE;
        }
	} else {
        if (  ! mainIconTrackingRectTagIsValid  ) {
			NSRect frame = [self frame];
			NSRect trackingRect = NSMakeRect(frame.origin.x + 1.0, frame.origin.y, frame.size.width - 1.0, frame.size.height);
			mainIconTrackingRectTag = [self addTrackingRect: trackingRect
													  owner: self
												   userData: nil
											   assumeInside: NO];
			mainIconTrackingRectTagIsValid = TRUE;
		}
	}
}	


-(void) changedDoNotShowNotificationWindowOnMouseover
{
	[self setOrRemoveTrackingRect];
}


// *******************************************************************************************
// init and dealloc

-(id) initWithFrame: (NSRect) frame
{
	
    self = [super initWithFrame: frame];
    if (self) {
		mainIconTrackingRectTagIsValid = FALSE;
	}
	
    return self;
}

-(void) dealloc
{
    if (  mainIconTrackingRectTagIsValid  ) {
        [self removeTrackingRect: mainIconTrackingRectTag];
		mainIconTrackingRectTagIsValid = FALSE;
    }
    
    [[NSApp delegate] mouseExitedMainIcon: self event: nil];
    [super dealloc];
}


// *******************************************************************************************
// Event Handlers

-(void) mouseEntered: (NSEvent *) theEvent
{
    // Event handler; NOT on MainThread
    // Mouse entered the tracking area of the Tunnelblick icon
	
    [[NSApp delegate] mouseEnteredMainIcon: self event: theEvent];
}

-(void) mouseExited: (NSEvent *) theEvent
{
    // Event handler; NOT on MainThread
    // Mouse exited the tracking area of the Tunnelblick icon
	
    [[NSApp delegate] mouseExitedMainIcon: self event: theEvent];
}

-(void) mouseDown: (NSEvent *) theEvent
{
    // Event handler; NOT on MainThread
    [self performSelectorOnMainThread: @selector(mouseDownMainThread:) withObject: theEvent waitUntilDone: NO];
}

-(void) mouseUp: (NSEvent *) theEvent
{
    // Event handler; NOT on MainThread
	
    ;   // We needn't do anything
}

@end
