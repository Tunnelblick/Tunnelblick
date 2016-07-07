/*
 * Copyright 2015 Jonathan K. Bullard. All rights reserved.
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

#import "defines.h"

#import "Tracker.h"
#import "TBInfoButton.h"


@class TBUserDefaults;
extern TBUserDefaults * gTbDefaults;

@implementation Tracker

TBSYNTHESIZE_NONOBJECT_GET(BOOL, mouseIsInWindow)

TBSYNTHESIZE_OBJECT(retain, id, delegate, setDelegate)

// *******************************************************************************************
// Mouse Event Handlers

-(void) mouseEntered: (NSEvent *) theEvent {
    
    // Event handler; NOT on MainThread
    
    (void)theEvent;
    
    TBLog(@"DB-PU", @"Mouse entered tracked area");
    
    mouseIsInWindow = TRUE;
}

-(void) mouseExited: (NSEvent *) theEvent {
    
    // Event handler; NOT on MainThread
    
    TBLog(@"DB-PU", @"Mouse exited tracked area");
    
    mouseIsInWindow = FALSE;
    
    [delegate mouseExitedTrackingArea: theEvent];
}

// *******************************************************************************************
// deallocator

-(void) dealloc {
    
    [delegate release];
    
    [super dealloc];
}

@end
