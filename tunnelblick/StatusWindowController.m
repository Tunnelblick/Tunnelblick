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


#import <pthread.h>
#import "defines.h"
#import "StatusWindowController.h"
#import "MenuController.h"
#import "TBUserDefaults.h"
#import "helper.h"


TBUserDefaults * gTbDefaults;         // Our preferences

static NSUInteger statusScreenPositionsInUse = 0;
static pthread_mutex_t statusScreenPositionsInUseMutex = PTHREAD_MUTEX_INITIALIZER;

@interface StatusWindowController()   // Private methods

-(void)              initialiseAnim;

-(void)              setSizeAndPosition;

-(NSTextFieldCell *) statusTFC;

-(void)              setTitle:        (NSString *) newTitle ofControl: (id) theControl;

@end

@implementation StatusWindowController

-(id) initWithDelegate: (id) theDelegate
{
    if (  ![super initWithWindowNibName:@"StatusWindow"]  ) {
        return nil;
    }
    
    [super setShouldCascadeWindows: NO];    // We always set the window's position
    
    name   = @"";
    status = @"";
    
    originalWidth = 0.0;
    currentWidth  = 0.0;
    
    isOpen = FALSE;
    
    delegate = [theDelegate retain];
    
    return self;
}

-(void) restore
{
    [cancelButton setEnabled: YES];
    [self setSizeAndPosition];
    [[self window] display];
    [self showWindow: self];
    [self fadeIn];
}

// Sets the frame for the window so the entire title (name of connection) is visible
// and the window is in the upper-right corner of the screen
-(void) setSizeAndPosition
{
    if (  originalWidth == 0.0  ) {
        originalWidth = [NSWindow minFrameWidthWithTitle: [[self window] title] styleMask: NSHUDWindowMask];
    }

    NSWindow * panel = [self window];
    NSRect panelFrame = [panel frame];
    
    // Adjust the width of the window to fit the complete title
    // But never make it smaller than the original window, or larger than will fit on the screen
    NSRect screen = [[[NSScreen screens] objectAtIndex: 0] visibleFrame];
    if (  currentWidth == 0.0  ) {
        currentWidth = [NSWindow minFrameWidthWithTitle: [panel title] styleMask: NSHUDWindowMask];
    }
    CGFloat newWidth = [NSWindow minFrameWidthWithTitle: name styleMask: NSHUDWindowMask];
    if (  newWidth < originalWidth  ) {
        newWidth = originalWidth;
    }
    CGFloat sizeChange = (CGFloat) newWidth - currentWidth;
    if (  sizeChange > 0.0  )  {
        if (  newWidth < (screen.size.width - 20.0)  ) {
            panelFrame.size.width = newWidth;
        } else {
            panelFrame.size.width = screen.size.width;
        }
    }
    
    // Put the window in the lowest available position number

    pthread_mutex_lock( &statusScreenPositionsInUseMutex );
    
    NSUInteger maxNumberOfPositions = 32; // JKB
    NSUInteger inUse = statusScreenPositionsInUse;
    NSUInteger mask  = 1;
    NSUInteger positionNumber;
    for (  positionNumber=0; positionNumber<maxNumberOfPositions; positionNumber++  ) {
        if (  (inUse & 1) == 0  ) {
            break;
        }
        inUse = inUse >> 1;
        mask  = mask  << 1;
    }
    
    if (  positionNumber < maxNumberOfPositions  ) {
        statusScreenPositionsInUse = statusScreenPositionsInUse | mask;
        statusScreenPosition = positionNumber;
    } else {
        statusScreenPosition = NSNotFound;
    }
    
    pthread_mutex_unlock( &statusScreenPositionsInUseMutex );
    
    // Stack the screens top to bottom, right to left
    
    double verticalScreenSize = screen.size.height - 10.0;  // Size we can use on the screen
    NSUInteger screensWeCanStackVertically = verticalScreenSize / (panelFrame.size.height + 5);
    if (  screensWeCanStackVertically < 1  ) {
        screensWeCanStackVertically = 1;
    }
    
    double horizontalScreenSize = screen.size.width - 10.0;  // Size we can use on the screen
    NSUInteger screensWeCanStackHorizontally = horizontalScreenSize / (panelFrame.size.width + 5);
    if (  screensWeCanStackHorizontally < 1  ) {
        screensWeCanStackHorizontally = 1;
    }
    
    double verticalOffset   = (panelFrame.size.height + 5.0) *  (positionNumber % screensWeCanStackVertically);
    double horizontalOffset = (panelFrame.size.width  + 5.0) * ((positionNumber / screensWeCanStackVertically) % screensWeCanStackHorizontally);
    
    double verticalPosition   = screen.origin.y + screen.size.height - panelFrame.size.height - 10.0 - verticalOffset;
    double horizontalPosition = screen.origin.x + screen.size.width  - panelFrame.size.width  - 10.0 - horizontalOffset;
    
    
    // Put the window in the upper-right corner of the screen but offset in Y by the position number    
    NSRect normalFrame = NSMakeRect(horizontalPosition,
                                    verticalPosition,
                                    panelFrame.size.width,
                                    panelFrame.size.height);
    
    [panel setFrame: normalFrame display: YES];
    currentWidth = normalFrame.size.width;
}

-(void) awakeFromNib
{
    [[self statusTFC] setStringValue: status ];
    [[self statusTFC] setTextColor: [NSColor whiteColor]];
    
    [self setTitle: NSLocalizedString(@"Cancel" , @"Button") ofControl: cancelButton ];
    
    [cancelButton setEnabled: YES];
    
    if (  ! runningOnLeopardOrNewer()  ) {
        [[self window] setBackgroundColor: [NSColor blackColor]];
        [[self window] setAlphaValue: 0.77];
    }
    
    [self setSizeAndPosition];
    [[self window] setTitle: @"Tunnelblick"];
    [self showWindow: self];
    [self initialiseAnim];
    [self fadeIn];
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

-(void) initialiseAnim
{
    if (  theAnim == nil  ) {
        int i;
        // theAnim is an NSAnimation instance variable
        theAnim = [[NSAnimation alloc] initWithDuration:2.0
                                         animationCurve:NSAnimationLinear];
        [theAnim setFrameRate:7.0];
        [theAnim setDelegate:self];
        
        for (i=1; i<=[[[NSApp delegate] largeAnimImages] count]; i++) {
            NSAnimationProgress p = ((float)i)/((float)[[[NSApp delegate] largeAnimImages] count]);
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
        [animationIV performSelectorOnMainThread:@selector(setImage:) withObject:[[[NSApp delegate] largeAnimImages] objectAtIndex:lround(progress * [[[NSApp delegate] largeAnimImages] count]) - 1] waitUntilDone:YES];
	}
}

-(void) fadeIn
{
	if (  ! isOpen  ) {
		[NSApp activateIgnoringOtherApps: YES];
		[[self window] makeKeyAndOrderFront: self];
        NSWindow * window = [self window];
        if (   [window respondsToSelector: @selector(animator)]
            && [[window animator] respondsToSelector: @selector(setAlphaValue:)]  ) {
            [[window animator] setAlphaValue: 1.0];
        }
		isOpen = YES;
	}
}

-(void) fadeOut
{
	if (  isOpen  ) {
        NSWindow * window = [self window];
        if (   [window respondsToSelector: @selector(animator)]
            && [[window animator] respondsToSelector: @selector(setAlphaValue:)]  ) {
            [[window animator] setAlphaValue:0.0];
        } else {
            [window close];
        }

		isOpen = NO;
        
        if (  statusScreenPosition != NSNotFound  ) {
            pthread_mutex_lock( &statusScreenPositionsInUseMutex );
            statusScreenPositionsInUse = statusScreenPositionsInUse & ( ~ (1 << statusScreenPosition));
            pthread_mutex_unlock( &statusScreenPositionsInUseMutex );
        }
	}
}

- (IBAction) cancelButtonWasClicked: sender
{
    [sender setEnabled: NO];
	[[NSApp delegate] statusWindowController: self finishedWithChoice: statusWindowControllerCancelChoice forDisplayName: [self name]];
}

- (void) dealloc
{
    [cancelButton   release];
    
    [statusTFC      release];
    [animationIV    release];
    
    [name           release];
    [status         release];
    
    [theAnim        release];    
    [delegate       release];
    
	[super dealloc];
}

- (NSString *) description
{
    return [NSString stringWithFormat:@"%@", [self class]];
}

-(NSTextFieldCell *) statusTFC
{
    return [[statusTFC retain] autorelease];
}

-(NSTextFieldCell *) configurationNameTFC
{
    return [[configurationNameTFC retain] autorelease];
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
}

-(void) setStatus: (NSString *) theStatus forName: (NSString *) theName
{
    if (  status != theStatus  ) {
        [status release];
        status = [theStatus retain];
    }
    
    [self setName: theName];
    
    [configurationNameTFC setStringValue: theName];
    [statusTFC            setStringValue: localizeNonLiteral(theStatus, @"Connection status")];
    
    if (   [theStatus isEqualToString: @"EXITING"]  ) {
        [configurationNameTFC setTextColor: [NSColor redColor]];
        [statusTFC            setTextColor: [NSColor redColor]];
        [theAnim stopAnimation];
        [animationIV setImage: [[NSApp delegate] largeMainImage]];
    } else if (  [theStatus isEqualToString: @"CONNECTED"]  ) {
        [configurationNameTFC setTextColor: [NSColor greenColor]];
        [statusTFC            setTextColor: [NSColor greenColor]];
        [theAnim stopAnimation];
        [animationIV setImage: [[NSApp delegate] largeConnectedImage]];
    } else {
        [configurationNameTFC setTextColor: [NSColor yellowColor]];
        [statusTFC            setTextColor: [NSColor yellowColor]];
        [theAnim startAnimation];
    }
}

-(id) delegate
{
    return [[delegate retain] autorelease];
}

@end
