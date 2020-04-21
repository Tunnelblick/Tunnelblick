/*
 * Copyright 2015, 2017, 2018 Jonathan K. Bullard. All rights reserved.
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

// THIS FILE IS IDENTICAL TO TBButton.h except for the class and base class and the import of TBPopUpButton.h instead of TBButton.h

#import "helper.h"
#import "sharedRoutines.h"

#import "MAAttachedWindow.h"
#import "MenuController.h"
#import "NSTimer+TB.h"
#import "TBUserDefaults.h"
#import "Tracker.h"
#import "UIHelper.h"

#import "TBButton.h"

extern TBUserDefaults * gTbDefaults;
extern BOOL             gShuttingDownWorkspace;


@implementation TBButton

TBSYNTHESIZE_OBJECT(retain, NSAttributedString *, titleAS,		  setTitleAS)
TBSYNTHESIZE_OBJECT(retain, MAAttachedWindow   *, attachedWindow, setAttachedWindow)
TBSYNTHESIZE_OBJECT(retain, Tracker            *, tracker,        setTracker)

TBSYNTHESIZE_NONOBJECT(CGFloat, startWidth,   setStartWidth)
TBSYNTHESIZE_NONOBJECT(CGFloat, minimumWidth, setMinimumWidth)

-(void) setState: (NSCellStateValue) newState {
	
	[super setState: newState];
}

-(void) awakeFromNib {
	
	// Do nothing
}

-(void) setTitle: (NSString *)           label
	   infoTitle: (NSAttributedString *) infoTitle
		disabled: (BOOL)                 disabled {
	
	if (  infoTitle == nil  ) {
		NSLog(@"setTitle:%@ infoTitle:nil; call stack = %@", label, callStack());
	}
	
	BOOL rtl = [UIHelper languageAtLaunchWasRTL];
	[UIHelper setTitle: label ofControl: self frameHolder: self shift: rtl narrow: YES enable: YES];
	
	NSMutableAttributedString * infoTitleAS = [[infoTitle mutableCopy] autorelease];
	[infoTitleAS addAttribute: NSForegroundColorAttributeName value:[NSColor textColor]           range: NSMakeRange(0, [infoTitleAS length])];
	[infoTitleAS addAttribute: NSBackgroundColorAttributeName value:[NSColor textBackgroundColor] range: NSMakeRange(0, [infoTitleAS length])];
	
	[self setAttributedTitle: infoTitleAS];
	[self setMinimumWidth: 360.0];
	[self setEnabled: ! disabled];
}

-(void) setTitle: (NSString *)           label
	   infoTitle: (NSAttributedString *) infoTitle {
	
	[self setTitle: label
		 infoTitle: infoTitle
		  disabled: NO];
}

-(void) setAttributedTitle: (NSAttributedString *) newTitle {
    
	// Set up tracking ourself (that is, the info button)
	NSTrackingArea * trackingArea = [[[NSTrackingArea alloc] initWithRect: [self bounds]
																  options: NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
																	owner: self
																 userInfo: nil]
									 autorelease];
	[self addTrackingArea: trackingArea];
    [self setTitleAS: newTitle];
}

-(CGFloat) heightForAttributedString: (NSAttributedString *)  myString
                               width: (CGFloat)               myWidth {
    
    // Adapted from http://stackoverflow.com/questions/1992950/nsstring-sizewithattributes-content-rect/1993376#1993376
    
    
    NSTextStorage   *textStorage   = [[[NSTextStorage alloc]   initWithAttributedString:myString] autorelease];
    NSTextContainer *textContainer = [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(myWidth, FLT_MAX)] autorelease];
    NSLayoutManager *layoutManager = [[[NSLayoutManager alloc] init] autorelease];
    [layoutManager addTextContainer:textContainer];
    [textStorage   addLayoutManager:layoutManager];
    [textContainer setLineFragmentPadding:0.0];
    
    (void) [layoutManager glyphRangeForTextContainer:textContainer];
    return [layoutManager usedRectForTextContainer:textContainer].size.height;
}

-(NSSize) sizeForDisplayingAttributedString: (NSAttributedString *) myString
                            firstTrialWidth: (CGFloat)              myWidth
                               minimumWidth: (CGFloat)              myMinWidth
                                   maxWidth: (CGFloat)              maxWidth
                                  maxHeight: (CGFloat)              maxHeight {
    
    // Adapted from http://stackoverflow.com/questions/1992950/nsstring-sizewithattributes-content-rect/1993376#1993376
    
    // Figure out an initial size by adding to the width until the height is reasonable
    CGFloat height;
    while(  TRUE  ) {
        
        height = [self heightForAttributedString: myString width: myWidth];
        TBLog(@"DB-PU", @"at width = %f; height = %f", myWidth, height);
        if (  height >= maxHeight) {
            if (  (myWidth >= maxWidth)) {
                break; // Too much content
            } else {
                myWidth += 100.0;
            }
        } else {
            if (   (  height > (maxHeight * 0.75)  )
                && (  myWidth  < (maxWidth  * 0.75)  )
                ) {
                myWidth += 100.0;
            } else {
                break;
            }
        }
    }
    
    // Now reduce the width as long as the height stays the same
    CGFloat trialWidth = myWidth + 10.0;
    do {
        trialWidth -= 10.0;
        CGFloat trialHeight = [self heightForAttributedString: myString width: myWidth];
        TBLog(@"DB-PU", @"Reducing: at width = %f; height = %f", trialWidth, trialHeight);
        if (  trialHeight > height  ) {
            break;
        }
        myWidth = trialWidth;
    } while(  trialWidth >= myMinWidth+ 10.0  );
    
    TBLog(@"DB-PU", @"will fit: (%f, %f) in (%f, %f)", myWidth, height, maxWidth, maxHeight);
    
    return  NSMakeSize(myWidth, height);
}

-(MAAttachedWindow *) createWindowWithContent: (NSAttributedString *) content
                                    nearPoint: (NSPoint)              nearPoint
                              firstTrialWidth: (CGFloat)              firstTrialWidth
                                 minimumWidth: (CGFloat)              minWidth
                                  outerWindow: (NSWindow *)           outerWindow
                                    trackedBy: (Tracker *)            theTracker {
    
    // Calculate a size for the text, trying a width of 'firstTrialWidth' to start, and adjusting the width as needed
    if (  minWidth == 0.0  ) {
        minWidth = 200.0;
    } else {
        minWidth += 10.0;   // Allow for left & right margins of 5.0 each
    }
    if (  firstTrialWidth == 0.0  ) {
        firstTrialWidth = minWidth;
    }
    firstTrialWidth = MIN(firstTrialWidth, minWidth);
    NSRect originalWindowFrame = [outerWindow frame];
    NSSize newSize = [self sizeForDisplayingAttributedString: content
                                             firstTrialWidth: firstTrialWidth
                                                minimumWidth: minWidth
                                                    maxWidth: originalWindowFrame.size.width
                                                   maxHeight: originalWindowFrame.size.height];
    
    // Create a textview that contains the content and add it to the window
    NSRect tvFrame = NSMakeRect(0.0, 0.0, newSize.width, newSize.height * 1.10); // Add to height of textview so it doesn't need to be scrolled
    NSTextView * tv = [[[NSTextView alloc] initWithFrame: tvFrame] autorelease];
    [tv setSelectable: YES];
    [tv setEditable:   NO];
    [tv setAutomaticQuoteSubstitutionEnabled: YES];
    [tv setAutomaticLinkDetectionEnabled:     YES];
    NSTextStorage * ts = [tv textStorage];
    [ts setAttributedString: content];
    
    // Create a scrollview in a frame sized to contain the textview
    NSRect svFrame = NSMakeRect(0.0, 0.0, 0.0, 0.0);
    svFrame.size = [NSScrollView contentSizeForFrameSize: tvFrame.size
                                   hasHorizontalScroller: YES
                                     hasVerticalScroller: YES
                                              borderType: NSNoBorder];
    
    // Adjust the scrollview width (contentSizeForFrameSize should take it into account but doesn't)
    svFrame.size.width += [NSScroller scrollerWidth];
    
    NSScrollView * sv = [[[NSScrollView alloc] initWithFrame: svFrame] autorelease];
    [sv setBorderType:NSNoBorder];
    [sv setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];     // Set autoresizing mask so scroll view will resize with the window
    [sv setDocumentView: tv];
    
    // Create the attached window and add it as a child of outerWindow
    MAAttachedWindow * aw = [[MAAttachedWindow alloc] initWithView: sv
                                                   attachedToPoint: nearPoint
                                                          inWindow: outerWindow
                                                        atDistance: 5.0];
    
    [aw setViewMargin: 1.0];
    [aw setReleasedWhenClosed: NO];
    
    [outerWindow addChildWindow: aw ordered: NSWindowAbove];
    
    // Track the window
    NSRect bounds = [aw frame];
    bounds.origin.x = 0;
    bounds.origin.y = 0;
    NSTrackingArea * trackingArea = [[[NSTrackingArea alloc] initWithRect: bounds
                                                                  options: NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
                                                                    owner: theTracker
                                                                 userInfo: nil]
                                     autorelease];
    [tv addTrackingArea: trackingArea];
    
    return aw;
}

-(void) removeWindow {
    
    if (  attachedWindow  ) {
        [[self window] removeChildWindow: attachedWindow];
        [attachedWindow close];
         [self setAttachedWindow: nil];
    }
}

-(void) showWindow {
    
    TBLog(@"DB-PU", @">>>>> SHOWING window");
    
    if (  ! titleAS  ) {
        NSLog(@"TBButton|showWindow invoked but content has not been set");
    }
    
    if ( ! attachedWindow  ) {
        NSRect f = [self frame];
        
        NSPoint pointInViewCoordinates = NSMakePoint( f.origin.x + (f.size.width / 2.0), f.origin.y + (f.size.height / 2.0) );
		
		NSWindow * ourWindow = [self window];
		NSPoint pointInWindowCoordinates = [[self superview] convertPoint: pointInViewCoordinates toView: [ourWindow contentView]];
        
        Tracker * t = [[[Tracker alloc] init] autorelease];
        [t setDelegate: self];
        [self setTracker: t];
        
        attachedWindow = [self createWindowWithContent: [self titleAS]
                                             nearPoint: pointInWindowCoordinates
                                       firstTrialWidth: [self startWidth]
                                          minimumWidth: [self minimumWidth]
                                           outerWindow: ourWindow
                                             trackedBy: t];
        
    }
}

-(void) hideWindow {
    
    TBLog(@"DB-PU", @">>>>> HIDING window");
    
    if (  attachedWindow  ) {
        
        BOOL inButton = mouseIsInButtonView;
        BOOL inWindow = [tracker mouseIsInWindow];
        TBLog(@"DB-PU", @"inButton = %@; inWindow = %@", (inButton ? @"YES" : @"NO"), (inWindow ? @"YES" : @"NO"));
        if (   inButton
            || inWindow  ) {
            return;
        }
        
        [self removeWindow];
    }
}

// *******************************************************************************************
// High-Level Event Handlers

-(void) showWindowTimerHandler: (NSTimer *) theTimer {
    
    // Event handler; NOT on MainThread
    
    (void) theTimer;
    
    if (  gShuttingDownWorkspace  ) {  // Don't do anything if computer is shutting down or restarting
        return;
    }
    
    if (  mouseIsInButtonView  ) {
        [self performSelectorOnMainThread: @selector(showWindow) withObject: nil waitUntilDone: NO];
        TBLog(@"DB-PU", @"showWindowTimerHandler: mouse still inside the view; queueing showWindow");
        //} else {
        TBLog(@"DB-PU", @"showWindowTimerHandler: mouse no longer inside the view; NOT queueing showWindow");
    }
}

-(void) hideWindowTimerHandler: (NSTimer *) theTimer {
    
    // Event handler; NOT on MainThread
    
    (void) theTimer;
    
    if (  gShuttingDownWorkspace  ) {  // Don't do anything if computer is shutting down or restarting
        return;
    }
    
    if (  ! mouseIsInButtonView  ) {
        [self performSelectorOnMainThread: @selector(hideWindow) withObject: nil waitUntilDone: NO];
        TBLog(@"DB-PU", @"hideWindowTimerHandler: mouse NOT back inside the view; queueing hideWindow");
        //} else {
        TBLog(@"DB-PU", @"hideWindowTimerHandler: mouse is back inside the view; NOT queueing hideWindow");
    }
}


-(void) showOrHideWindowAfterDelay: (NSTimeInterval) delay
                     fromTimestamp: (NSTimeInterval) timestamp
                          selector: (SEL)            selector {
    
    // Event handlers invoke this; NOT on MainThread
    
    if (  gShuttingDownWorkspace  ) {  // Don't do anything if computer is shutting down or restarting
        return;
    }
    
    NSTimeInterval timeUntilAct;
    if (  timestamp == 0.0  ) {
        timeUntilAct = 0.1;
    } else  {
        uint64_t nowNanoseconds = nowAbsoluteNanoseconds();
        NSTimeInterval nowTimeInterval = (  ((NSTimeInterval) nowNanoseconds) / 1.0e9  );
        timeUntilAct = timestamp + delay - nowTimeInterval;
        TBLog(@"DB-PU", @"showOrHideWindowAfterDelay: delay = %f; timestamp = %f; nowNanoseconds = %llu; nowTimeInterval = %f; timeUntilAct = %f", delay, timestamp, (unsigned long long) nowNanoseconds, nowTimeInterval, timeUntilAct);
        if (  timeUntilAct < 0.1) {
            timeUntilAct = 0.1;
        }
    }
    
    TBLog(@"DB-PU", @"Queueing %s in %f seconds", sel_getName(selector), timeUntilAct);
    NSTimer * timer = [NSTimer scheduledTimerWithTimeInterval: timeUntilAct
                                                       target: self
                                                     selector: selector
                                                     userInfo: nil
                                                      repeats: NO];
    [timer tbSetTolerance: -1.0];
}

-(void) mouseExitedTrackingArea: (NSEvent *) theEvent {
    
    // Event handler; NOT on MainThread
    
    [self showOrHideWindowAfterDelay: 0.7
                       fromTimestamp: ( theEvent ? [theEvent timestamp] : 0.0)
                            selector: @selector(hideWindowTimerHandler:)];

}
// *******************************************************************************************
// Mouse Event Handlers

-(void) mouseEntered: (NSEvent *) theEvent
{
    // Event handler; NOT on MainThread
    
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    TBLog(@"DB-PU", @"Mouse entered TBButton tracking rectangle");
    
    mouseIsInButtonView = TRUE;
    
    [self showOrHideWindowAfterDelay: [gTbDefaults floatForKey: @"delayBeforePopupHelp" default: 1.0 min: 0.0 max: 10.0]
                       fromTimestamp: ( theEvent ? [theEvent timestamp] : 0.0)
                            selector: @selector(showWindowTimerHandler:)];
    
    [super mouseEntered: theEvent];
}

-(void) mouseExited: (NSEvent *) theEvent
{
    // Event handler; NOT on MainThread
    
    TBLog(@"DB-PU", @"Mouse exited TBButton tracking rectangle");
    
    mouseIsInButtonView = FALSE;
    
    [self mouseExitedTrackingArea: theEvent];
    
    [super mouseExited: theEvent];
}

-(void) mouseDown: (NSEvent *) theEvent
{
    // Event handler; NOT on MainThread
    
    TBLog(@"DB-PU", @"Mouse down in  TBButton tracking rectangle");

	[super mouseDown: theEvent];
}

-(void) mouseUp: (NSEvent *) theEvent
{
    // Event handler; NOT on MainThread
    
    TBLog(@"DB-PU", @"Mouse up in TBButton tracking rectangle");
    
	[super mouseUp: theEvent];
}

/*
 
-(void) mouseMoved: (NSEvent *) theEvent
{
    // Event handler; NOT on MainThread
    
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    TBLog(@"DB-PU", @"Mouse moved in  TBButton tracking rectangle");
    
    [super mouseMoved: theEvent];
}

-(void) cursorUpdate:(NSEvent *) theEvent
{
    // Event handler; NOT on MainThread
    
    TBLog(@"DB-PU", @"Cursor update in TBButton tracking rectangle");
    
    [super cursorUpdate: theEvent];
}

 */

// *******************************************************************************************
// deallocator

-(void) dealloc {
    
    [titleAS release];
    
    [attachedWindow release];
    
    [super dealloc];
}

@end
