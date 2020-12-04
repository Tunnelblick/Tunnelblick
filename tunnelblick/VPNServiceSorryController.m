/*
 * Copyright 2011, 2012, 2013, 2014 Jonathan K. Bullard. All rights reserved.
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

#ifdef INCLUDE_VPNSERVICE

#import "VPNServiceSorryController.h"

#import "VPNServiceDefines.h"

#import "VPNService.h"

#import "MenuController.h"
extern MenuController * gMC;

@interface VPNServiceSorryController() // Private methods

-(NSTextFieldCell *) sorryTFC;

-(void)              setTitle: (NSString *) newTitle ofControl: (id) theControl;

-(NSString *) vpnServiceReasonForRegistrationFailure;

-(id)                delegate;

@end

@implementation VPNServiceSorryController

-(id) initWithDelegate: (id) theDelegate
{
    if (  ! ( self = [super initWithWindowNibName:@"VPNServiceSorry"] )  ) {
        return nil;
    }
    
    delegate = [theDelegate retain];
    
    return self;
}

-(void) awakeFromNib
{
    [[self window] setTitle: NSLocalizedString(@"Sorry", @"Window title  VPNService")];
    
    [self setTitle: NSLocalizedString(@"Quit", @"Button VPNService") ofControl: quitButton];
    [self setTitle: NSLocalizedString(@"Back", @"Button VPNService") ofControl: backButton];
    
    [[self sorryTFC] setStringValue: [NSString stringWithFormat: NSLocalizedString(@"Sorry, but your request for an account could not be processed:\n     %@", @"Window text VPNService"),
                                      [self vpnServiceReasonForRegistrationFailure]]];
    [[self window] center];
    [gMC activateIgnoringOtherApps];
    [[self window] makeKeyAndOrderFront: self];
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
    
    if (   [theControl isEqual: quitButton]  ) {         // Shift the control itself left/right if necessary
        oldPos = [theControl frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [theControl setFrame:oldPos];
    }
}

- (void) dealloc {
    
    [delegate release]; delegate = nil;
    
    [super dealloc];
}

- (NSString *) description
{
    return [NSString stringWithFormat:@"%@", [self class]];
}

- (IBAction) backButtonWasClicked: sender
{
	[[self delegate] vpnServiceSorry: self finishedWithChoice: VPNServiceSorryBackChoice];
}

-(IBAction) quitButtonWasClicked: sender
{
	[[self delegate] vpnServiceSorry: self finishedWithChoice: VPNServiceSorryQuitChoice];
}

-(NSTextFieldCell *) sorryTFC
{
    return [[sorryTFC retain] autorelease];
}

-(NSString *) vpnServiceReasonForRegistrationFailure
{
    return [delegate reasonForRegistrationFailure];
}

-(id) delegate
{
    return [[delegate retain] autorelease];
}

@end

#endif
