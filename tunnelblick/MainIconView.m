/*
 * Copyright 2012, 2013, 2015 Jonathan K. Bullard. All rights reserved.
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


#import "MainIconView.h"

#import "MenuController.h"
#import "TBUserDefaults.h"

extern  TBUserDefaults * gTbDefaults;
extern BOOL              gShuttingDownWorkspace;

@implementation MainIconView

// *******************************************************************************************
// General Methods

-(void) mouseDownMainThread: (NSEvent *) theEvent
{
    // Invoked in the main thread only
	
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
	// Detect a triple-click:
	//        First click comes here and pops up the menu
	//        Second click pops the menu back (it does not come here)
	//        Third click comes here and (if within 1 second of first click) opens VPN Details… window
	NSTimeInterval thisTime = [theEvent timestamp];
	if (  (mainIconLastClickTime + 1.0) > thisTime  ) {
		[((MenuController *)[NSApp delegate]) openPreferencesWindow: self];
	} else {
		NSStatusItem * statusI = [((MenuController *)[NSApp delegate]) statusItem];
		NSMenu       * menu    = [((MenuController *)[NSApp delegate]) myVPNMenu];
		[statusI popUpStatusItemMenu: menu];
	}
	
	mainIconLastClickTime = thisTime;
}

-(void) removeTrackingRectangle {
	
    if (  mainIconTrackingRectTagIsValid  ) {
        [self removeTrackingRect: mainIconTrackingRectTag];
        mainIconTrackingRectTagIsValid = FALSE;
        TBLog(@"DB-SI", @"Removed main tracking rectangle for MainIconView 0x%lX", (long)self)
    }
}

-(void) setOrRemoveTrackingRect
{
	[self removeTrackingRectangle];
    
	if (  ! [gTbDefaults boolForKey: @"doNotShowNotificationWindowOnMouseover"]  ) {
        NSRect frame = [self frame];
        NSRect trackingRect = NSMakeRect(frame.origin.x + 1.0f, frame.origin.y, frame.size.width - 1.0f, frame.size.height);
        mainIconTrackingRectTag = [self addTrackingRect: trackingRect
                                                  owner: self
                                               userData: nil
                                           assumeInside: NO];
        mainIconTrackingRectTagIsValid = TRUE;
        TBLog(@"DB-SI", @"setOrRemoveTrackingRect: Added main tracking rectangle 0x%lX (%f,%f, %f, %f) for MainIconView 0x%lX",
              (long) mainIconTrackingRectTag, trackingRect.origin.x, trackingRect.origin.y, trackingRect.size.width, trackingRect.size.height,(long) self)
	}
}


-(void) changedDoNotShowNotificationWindowOnMouseover
{
    TBLog(@"DB-SI", @"changedDoNotShowNotificationWindowOnMouseover: for MainIconView 0x%lX entered", (long)self);
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

-(void) dealloc {
    
    [self removeTrackingRectangle];
    
    [((MenuController *)[NSApp delegate]) mouseExitedMainIcon: self event: nil];
    
    [super dealloc];
}


// *******************************************************************************************
// Event Handlers

-(void) mouseEntered: (NSEvent *) theEvent
{
    // Event handler; NOT on MainThread
    // Mouse entered the tracking area of the Tunnelblick icon
	
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    TBLog(@"DB-SI", @"Mouse entered tracking rectangle  for MainIconView 0x%lX", (long)self);
    [((MenuController *)[NSApp delegate]) mouseEnteredMainIcon: self event: theEvent];
}

-(void) mouseExited: (NSEvent *) theEvent
{
    // Event handler; NOT on MainThread
    // Mouse exited the tracking area of the Tunnelblick icon
	
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    TBLog(@"DB-SI", @"Mouse exited tracking rectangle for MainIconView 0x%lX", (long)self);
    [((MenuController *)[NSApp delegate]) mouseExitedMainIcon: self event: theEvent];
}

-(void) mouseDown: (NSEvent *) theEvent
{
    // Event handler; NOT on MainThread

    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    TBLog(@"DB-SI", @"Mouse down in MainIconView 0x%lX", (long)self);
    [self performSelectorOnMainThread: @selector(mouseDownMainThread:) withObject: theEvent waitUntilDone: NO];
}

-(void) mouseUp: (NSEvent *) theEvent
{
    // Event handler; NOT on MainThread
	
	(void) theEvent;	// We don't do anything
	
    TBLog(@"DB-SI", @"Mouse up in MainIconView 0x%lX", (long)self);
}

@end
