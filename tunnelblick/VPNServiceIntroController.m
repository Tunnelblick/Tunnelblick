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

#import "VPNServiceIntroController.h"

#import "VPNServiceDefines.h"

#import "VPNService.h"

#import "MenuController.h"
extern MenuController * gMC;

@interface VPNServiceIntroController() // Private methods

-(NSTextFieldCell *) introTFC;

-(id)                delegate;
-(void)              setTitle: (NSString *) newTitle ofControl: (id) theControl;

@end

@implementation VPNServiceIntroController

-(id) initWithDelegate: (id) theDelegate
{
    if (  ![super initWithWindowNibName:@"VPNServiceIntro"]  ) {
        return nil;
    }
    
    delegate = [theDelegate retain];
    
    return self;
}

-(void) awakeFromNib
{
    [[self window] setTitle: NSLocalizedString(@"Tunnelblick - Free VPN", @"Window title  VPNService")];
    
    NSString * imagePath = [[NSBundle mainBundle] pathForResource: @"VPNService-Intro" ofType: @"png"];
    [introIV setImage: [[[NSImage alloc] initWithContentsOfFile: imagePath] autorelease]];
    
    [self setTitle: NSLocalizedString(@"Quit"                   , @"Button VPNService") ofControl: quitButton          ];
    [self setTitle: NSLocalizedString(@"Create a Free Account"  , @"Button VPNService") ofControl: createAccountButton ];
    [self setTitle: NSLocalizedString(@"Login",                   @"Button VPNService") ofControl: loginButton         ];
    
    [[self introTFC] setStringValue: NSLocalizedString(@"Tunnelblick allows you to explore the Internet freely without restrictions "
                                                       "while simultaneously securing your Internet connection.", @"Window text VPNService")];
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
    
    if (   [theControl isEqual: loginButton]                      // Shift the control itself left/right if necessary
        || [theControl isEqual: createAccountButton]  ) {
        oldPos = [theControl frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [theControl setFrame:oldPos];
    }
    
    if (  [theControl isEqual: createAccountButton]  )  {        // If the createAccountButton button changes, shift the loginButton button left/right
        oldPos = [loginButton frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [loginButton setFrame:oldPos];
    }
}

- (void) dealloc {
    
    [delegate release]; delegate = nil;
    
	[super dealloc];
}

-(NSString *) description
{
    return [NSString stringWithFormat:@"%@", [self class]];
}

-(IBAction) createAccountButtonWasClicked: sender
{
	[[self delegate] vpnServiceIntro: self finishedWithChoice: VPNServiceIntroCreateAccountChoice];
}

-(IBAction) loginButtonWasClicked: sender
{
	[[self delegate] vpnServiceIntro: self finishedWithChoice: VPNServiceIntroLoginChoice];
}

-(IBAction) quitButtonWasClicked: sender
{
	[[self delegate] vpnServiceIntro: self finishedWithChoice: VPNServiceIntroQuitChoice];
}

-(id) delegate
{
    return [[delegate retain] autorelease];
}

-(NSTextFieldCell *) introTFC
{
    return [[introTFC retain] autorelease];
}

@end

#endif
