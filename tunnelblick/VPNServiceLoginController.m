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

#import "VPNServiceLoginController.h"

#import "VPNServiceDefines.h"

#import "VPNService.h"

#import "MenuController.h"
extern MenuController * gMC;

@interface VPNServiceLoginController() // Private methods

-(NSTextFieldCell *) emailAddressTFC;
-(NSTextFieldCell *) passwordTFC;
-(NSTextField *) emailAddressTF;
-(NSTextField *) passwordTF;

-(BOOL)         emailIsVerified;
-(void)         setTitle: (NSString *) newTitle ofControl: (id) theControl;
-(NSString *)   emailAddress;
-(NSString *)   password;
-(NSButton *)   quitBackButton;
-(id)           delegate;

@end

@implementation VPNServiceLoginController

-(id) initWithDelegate: (id) theDelegate quitButton: (BOOL) showQuit
{
    if (  ![super initWithWindowNibName:@"VPNServiceLogin"]  ) {
        return nil;
    }
    
    quitButtonNotBackButton = showQuit;
    
    delegate = [theDelegate retain];
    
    return self;
}

-(void) awakeFromNib
{
    [[self window] setTitle: NSLocalizedString(@"Login", @"Window title  VPNService")];
    
    NSString * imagePath = [[NSBundle mainBundle] pathForResource: @"VPNService-Intro" ofType: @"png"];
    [introIV setImage: [[[NSImage alloc] initWithContentsOfFile: imagePath] autorelease]];
    
    [self setTitle: NSLocalizedString(@"Login", @"Button VPNService") ofControl: loginButton ];
    
    if (  quitButtonNotBackButton  ) {
        [self setTitle: NSLocalizedString(@"Quit",  @"Button VPNService") ofControl: quitBackButton ];
    } else {
        [self setTitle: NSLocalizedString(@"Back",  @"Button VPNService") ofControl: quitBackButton ];
    }
    
    [[self emailAddressTFC] setStringValue: NSLocalizedString(@"Email address:", @"Window text VPNService")];
    [[self passwordTFC]     setStringValue: NSLocalizedString(@"Password:",      @"Window text VPNService")];
    
    [[self emailAddressTF] setStringValue: [[self delegate] emailAddress]];
    [[self passwordTF]     setStringValue: [[self delegate] password    ]];
    
    [[self window] center];
    [gMC activateIgnoringOtherApps];
    [[self window] makeKeyAndOrderFront: self];
}

-(void) showQuitButton: (BOOL) showQuit
{
    if (  showQuit  ) {
        [self setTitle: NSLocalizedString(@"Quit",  @"Button VPNService") ofControl: quitBackButton ];
    } else {
        [self setTitle: NSLocalizedString(@"Back",  @"Button VPNService") ofControl: quitBackButton ];
    }

    [[self emailAddressTF] setStringValue: [[self delegate] emailAddress]];
    [[self passwordTF]     setStringValue: [[self delegate] password    ]];
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
    
    if (   [theControl isEqual: loginButton]  ) {  // Shift the control itself left/right if necessary
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

-(BOOL) emailIsVerified
{
    if (  [self emailAddress] != @""  ) {
        NSString * msg = [[self delegate] userExistsAndIsActive: [self emailAddress]];
        if (  [msg isEqualToString: @"YES"]  ) {
            return YES;
        }
        if (  [msg isEqualToString: @"NO"]  ) {
            TBRunAlertPanel(NSLocalizedString(@"Email not verified", @"Window title  VPNService"),
                            NSLocalizedString(@"The email address has not been verified.\n\nYou will not be able to"
                                              @" login and use the VPN until the email address has been verified by"
                                              @" following the instructions in an email sent to you by Tunnelblick"
                                              @" when you registered for the service.", @"Window text VPNService"),
                            nil,nil,nil);
            [gMC activateIgnoringOtherApps];
            return NO;
        }
        
        TBRunAlertPanel(NSLocalizedString(@"Email not verified", @"Window title  VPNService"),
                        [NSString stringWithFormat: NSLocalizedString(@"Your account status could not be verified:\n     %@.", @"Window text VPNService"), msg],
                        nil,nil,nil);
        [gMC activateIgnoringOtherApps];
        return NO;
    }
    
    NSLog(@"emailIsVerified: invoked with an empty string in emailAddress");
    return NO;
}

- (IBAction) loginButtonWasClicked: sender
{
    [[self delegate] setEmailAddress: [self emailAddress]];
    [[self delegate] setPassword:     [self password]];
    if (   ([[self emailAddress   ] length] != 0)
        && ([[self password       ] length] != 0)  ) {
        if (  [self emailIsVerified]  ) {
            [[self delegate] vpnServiceLogin: self finishedWithChoice: VPNServiceLoginLoginChoice];
        }
    } else {
        TBRunAlertPanel(NSLocalizedString(@"Entries required", @"Window title  VPNService"),
                        NSLocalizedString(@"You must enter an email address and password to login.", @"Window text VPNService"),
                        nil,nil,nil);
        [gMC activateIgnoringOtherApps];
    }
}

- (IBAction) quitBackButtonWasClicked: sender
{
    if (  [[[self quitBackButton] title] isEqualToString: @"Quit"]  ) {
        [[self delegate] vpnServiceLogin: self finishedWithChoice: VPNServiceLoginQuitChoice];
    } else {
        [[self delegate] vpnServiceLogin: self finishedWithChoice: VPNServiceLoginBackChoice];
    }
}

-(NSString *) emailAddress
{
    return [emailAddressTF stringValue];
}

-(NSString *) password
{
    return [passwordTF stringValue];
}

-(NSTextFieldCell *) emailAddressTFC
{
    return [[emailAddressTFC retain] autorelease];
}

-(NSTextFieldCell *) passwordTFC
{
    return [[passwordTFC retain] autorelease];
}

-(NSTextField *) emailAddressTF
{
    return [[emailAddressTF retain] autorelease];
}

-(NSTextField *) passwordTF
{
    return [[passwordTF retain] autorelease];
}

-(NSButton *) quitBackButton
{
    return [[quitBackButton retain] autorelease];
}

-(id) delegate
{
    return [[delegate retain] autorelease];
}

@end

#endif
