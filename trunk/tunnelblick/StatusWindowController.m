/*
 * Copyright 2011 Jonathan Bullard
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
#import "StatusWindowController.h"
#import "MenuController.h"
#import "TBUserDefaults.h"

TBUserDefaults        * gTbDefaults;            // Our preferences

@interface StatusWindowController() // Private methods

-(void)              initialiseAnim;

-(NSTextFieldCell *) statusTFC;

-(NSTextFieldCell *) nameTFC;

-(void)              setTitle:        (NSString *) newTitle ofControl: (id) theControl;

@end

@implementation StatusWindowController

-(id) initWithDelegate: (id) theDelegate
{
    if (  ![super initWithWindowNibName:@"StatusWindow"]  ) {
        return nil;
    }
    
    name   = @"(unknown connection)";
    status = @"(unknown status)";
    
    thisIsUs = [[NSNumber numberWithBool: TRUE] retain];
    delegate = [theDelegate retain];
    
    return self;
}

-(void) awakeFromNib
{
    if (  thisIsUs  ) {
        [[self window] setTitle: NSLocalizedString(@"Connection Status", @"Window title")];
        
        [self setTitle: NSLocalizedString(@"Cancel" , @"Button") ofControl: cancelButton ];
        
        [[self nameTFC]   setStringValue: name   ];

        [[self statusTFC] setStringValue: status ];
        
        [self initialiseAnim];
        
        [self enableCancelButton];
        
        // The normal frame is centered or comes from preferences
        NSString * normalFrameString = [gTbDefaults objectForKey: @"statusWindowFrame"];
        if (  normalFrameString  ) {
            normalFrame = NSRectFromString(normalFrameString);
            [[self window] setFrame: normalFrame display: YES];
        } else {
            [[self window] center];
            normalFrame = [[self window] frame];
        }
        
        // The icon frame is in the upper-left corner of the screen with the menu bar
        NSRect screen = [[[NSScreen screens] objectAtIndex: 0] frame];
        iconFrame = NSMakeRect(screen.origin.x + screen.size.width - 70.0,
                               screen.origin.y + screen.size.height - 9.0,
                               1.0,
                               1.0); // (... 0, 0) doesn't work on OS X 10.4
        
        // Zoom from the icon frame
        [[self window] setFrame: iconFrame display: YES animate: NO];
        [[self window] display];
        [self showWindow: self];
        [[self window] setFrame: normalFrame display: YES animate: YES];
        [NSApp activateIgnoringOtherApps:YES];
        [[self window] makeKeyAndOrderFront: self];
     }
}

// Sets the title for a control, shifting the origin of the control itself to the left, and the origin of other controls to the left or right to accomodate any change in width.
-(void) setTitle: (NSString *) newTitle ofControl: (id) theControl
{
    NSRect oldRect = [theControl frame];
    [theControl setTitle: newTitle];
    [theControl sizeToFit];
    
    NSRect newRect = [theControl frame];
    float widthChange = newRect.size.width - oldRect.size.width;
    NSRect oldPos;
    
    if (   [theControl isEqual: cancelButton]  ) {  // Shift the control itself left/right if necessary
        oldPos = [theControl frame];
        oldPos.origin.x = oldPos.origin.x - (widthChange/2);
        [theControl setFrame:oldPos];
    }
}

-(void) zoomToIcon
{
    [[self window] setFrame: iconFrame display: YES animate: YES];
}

-(void) zoomToWindow
{
    [[self window] setFrame: normalFrame display: YES animate: YES];
}

-(void) initialiseAnim
{
    if (  theAnim == nil  ) {
        int i;
        // theAnim is an NSAnimation instance variable
        theAnim = [[NSAnimation alloc] initWithDuration:2.0
                                         animationCurve:NSAnimationLinear];
        [theAnim setFrameRate:7.0];
        [theAnim setDelegate:self];
        
        animImages     = [[[NSApp delegate] animImages]     retain];
        connectedImage = [[[NSApp delegate] connectedImage] retain];
        mainImage      = [[[NSApp delegate] mainImage]      retain];

        for (i=1; i<=[animImages count]; i++) {
            NSAnimationProgress p = ((float)i)/((float)[animImages count]);
            [theAnim addProgressMark:p];
        }
        [theAnim setAnimationBlockingMode:  NSAnimationNonblocking];
        [theAnim startAnimation];
    }
}

-(void)animationDidEnd:(NSAnimation*)animation
{
	if (   (![status isEqualToString:@"EXITING"])
        && (![status isEqualToString:@"CONNECTED"])) {
		[theAnim startAnimation];
	}
}

-(void)animation:(NSAnimation *)animation didReachProgressMark:(NSAnimationProgress)progress
{
	if (animation == theAnim) {
        [animationIV performSelectorOnMainThread:@selector(setImage:) withObject:[animImages objectAtIndex:lround(progress * [animImages count]) - 1] waitUntilDone:YES];
	}
}

- (void)windowWillClose:(NSNotification *)n
{
    [gTbDefaults setObject: NSStringFromRect(normalFrame) forKey: @"statusWindowFrame"];
}

-(void) windowDidMove:(NSNotification *)notification
{
    // We save the new position as a preference, but only if the user moved the window.
    // We ignore small movements (5 pixels or fewer), and we ignore the move if the size is not the "normal" size
    // This combination lets us ignore the zooming to/from the icon and the initial setting up of the window
    if (  normalFrame.size.width != 0  ) {
        NSRect currentFrame = [[self window] frame];
        if (   ( abs(  (int) normalFrame.origin.x - (int) currentFrame.origin.x ) > 5)
            && ( abs(  (int) normalFrame.origin.y - (int) currentFrame.origin.y ) > 5)
            && ( currentFrame.size.width == normalFrame.size.width )
            && ( currentFrame.size.height == normalFrame.size.height )) {
            normalFrame.origin.x = currentFrame.origin.x;
            normalFrame.origin.y = currentFrame.origin.y;
        }
    }
}

- (IBAction) cancelButtonWasClicked: sender
{
    [sender setEnabled: NO];
	[[NSApp delegate] statusWindowController: self finishedWithChoice: statusWindowControllerCancelChoice forDisplayName: [[self delegate] name]];
}

- (void) dealloc
{
    [cancelButton   release];
    
    [nameTFC        release];
    [statusTFC      release];
    [animationIV    release];
    
    [name           release];
    [status         release];
    
    [theAnim        release];
    [animImages     release];
    [connectedImage release];
    [mainImage      release];
    
    [thisIsUs       release];
    [delegate       release];
    
	[super dealloc];
}

- (NSString *) description
{
    return [NSString stringWithFormat:@"%@", [self class]];
}

-(NSTextFieldCell *) nameTFC
{
    return [[nameTFC retain] autorelease];
}

-(NSTextFieldCell *) statusTFC
{
    return [[statusTFC retain] autorelease];
}

-(NSString *) name
{
    return [[name retain] autorelease];
}

-(void) setName: (NSString *) newName
{
    if (  name != newName  ) {
        [name release];
        name = [newName retain];
    }
    [[self nameTFC] setStringValue: newName];
}

-(void) setStatus: (NSString *) theStatus
{
    if (  status != theStatus  ) {
        [status release];
        status = [theStatus retain];
    }        
    [[self statusTFC] setStringValue: NSLocalizedString(theStatus, @"Connection status")];
    if (  [theStatus isEqualToString: @"EXITING"]  ) {
        [statusTFC setTextColor: [NSColor redColor]];
        [theAnim stopAnimation];
        [animationIV setImage: mainImage];
    } else if (  [theStatus isEqualToString: @"CONNECTED"]  ) {
        [statusTFC setTextColor: [NSColor redColor]];
        [theAnim stopAnimation];
        [animationIV setImage: connectedImage];
    } else {
        [statusTFC setTextColor: [NSColor blackColor]];
        [theAnim startAnimation];
    }
}

-(void) enableCancelButton
{
    [cancelButton setEnabled: YES];
}

-(id) delegate
{
    return [[delegate retain] autorelease];
}

@end
