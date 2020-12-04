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

#import "VPNServiceWelcomeController.h"

#import "VPNServiceDefines.h"

#import "VPNService.h"

#import "MenuController.h"
extern MenuController * gMC;

@interface VPNServiceWelcomeController() // Private methods

-(NSTextFieldCell *) welcomeTFC;

-(void)              setTitle: (NSString *) newTitle ofControl: (id) theControl;

-(id)                delegate;

@end

@implementation VPNServiceWelcomeController

-(id) initWithDelegate: (id) theDelegate
{
    if (  ![super initWithWindowNibName:@"VPNServiceWelcome"]  ) {
        return nil;
    }
    
    delegate = [theDelegate retain];
    
    return self;
}

-(void) awakeFromNib
{
    [[self window] setTitle: NSLocalizedString(@"Welcome!", @"Window title  VPNService")];
    
    [self setTitle: NSLocalizedString(@"Next" , @"Button VPNService") ofControl: nextButton ];
    
    [[self welcomeTFC] setStringValue: NSLocalizedString(@"Congratulations! Your account has been created."
                                                         " You should receive an email from Tunnelblick soon."
                                                         " Follow the instructions in the email to verify your"
                                                         " email address and then click 'Next'.", @"Window text VPNService")];
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
    
    if (   [theControl isEqual: nextButton]  ) {  // Shift the control itself left/right if necessary
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

- (IBAction) nextButtonWasClicked: sender
{
	[[self delegate] vpnServiceWelcome: self finishedWithChoice: VPNServiceWelcomeNextChoice];
}

-(NSTextFieldCell *) welcomeTFC
{
    return [[welcomeTFC retain] autorelease];
}

-(id) delegate
{
    return [[delegate retain] autorelease];
}

@end

#endif
