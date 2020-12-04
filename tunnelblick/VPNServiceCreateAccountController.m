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

#import "VPNServiceCreateAccountController.h"

#import "VPNServiceDefines.h"

#import "VPNService.h"

#import "MenuController.h"
extern MenuController * gMC;

@interface VPNServiceCreateAccountController() // Private methods

-(NSTextFieldCell *) createAccountTFC;

-(NSTextFieldCell *) emailAddressTFC;
-(NSTextFieldCell *) passwordTFC;
-(NSTextFieldCell *) passwordConfirmTFC;

-(NSTextField *) emailAddressTF;
-(NSTextField *) passwordTF;
-(NSTextField *) passwordConfirmTF;

-(NSString *)    passwordConfirm;

-(void)          setTitle: (NSString *) newTitle ofControl: (id) theControl;

-(id)            delegate;

@end

@implementation VPNServiceCreateAccountController

-(id) initWithDelegate: (id) theDelegate cancelButton: (BOOL) showCancelButton
{
    if (  ![super initWithWindowNibName:@"VPNServiceCreateAccount"]  ) {
        return nil;
    }
    
    cancelNotBackButton = showCancelButton;
    
    delegate = [theDelegate retain];
    
    return self;
}

-(void) awakeFromNib
{
    [[self window] setTitle: NSLocalizedString(@"Register with Tunnelblick", @"Window title  VPNService")];
    
    if (  cancelNotBackButton  ) {
        [self setTitle: NSLocalizedString(@"Cancel" , @"Button VPNService") ofControl: cancelBackButton ];
    } else {
        [self setTitle: NSLocalizedString(@"Back"   , @"Button VPNService") ofControl: cancelBackButton ];
    }
    [self setTitle:     NSLocalizedString(@"Next"   , @"Button VPNService") ofControl: nextButton ];
    
    [[self createAccountTFC]   setStringValue: NSLocalizedString(@"To create your free Tunnelblick account we need your email address"
                                                                 " and a password of your choosing.", @"Window text VPNService")];
    
    [[self emailAddressTFC]    setStringValue: NSLocalizedString(@"Email address:",    @"Window text VPNService")];
    [[self passwordTFC]        setStringValue: NSLocalizedString(@"Password:",         @"Window text VPNService")];
    [[self passwordConfirmTFC] setStringValue: NSLocalizedString(@"Confirm password:", @"Window text VPNService")];
    
    [[self emailAddressTF]    setStringValue: [[self delegate] emailAddress]];
    [[self passwordTF]        setStringValue: [[self delegate] password]];
    [[self passwordConfirmTF] setStringValue: [[self delegate] password]];
    
    [[self window] center];
    [gMC activateIgnoringOtherApps];
    [[self window] makeKeyAndOrderFront: self];
}

-(void) showCancelButton: (BOOL) showCancel
{
    cancelNotBackButton = showCancel;
    
    if (  showCancel  ) {
        [self setTitle: NSLocalizedString(@"Cancel",  @"Button VPNService") ofControl: cancelBackButton ];
    } else {
        [self setTitle: NSLocalizedString(@"Back",    @"Button VPNService") ofControl: cancelBackButton ];
    }
    
    [[self emailAddressTF]    setStringValue: [[self delegate] emailAddress]];
    [[self passwordTF]        setStringValue: [[self delegate] password]];
    [[self passwordConfirmTF] setStringValue: [[self delegate] password]];
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
    
    if (  [theControl isEqual: nextButton]  ) {  // Shift the control itself left/right if necessary
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
    NSString * reason;
    
    if (   ([[self emailAddress   ] length] != 0)
        && ([[self password       ] length] != 0)
        && ([[self passwordConfirm] length] != 0)  ) {
        if (  [[self password] isEqualToString: [self passwordConfirm]]) {
            [[self delegate] setEmailAddress: [self emailAddress]];
            [[self delegate] setEmailAddress: [self emailAddress]];
            if (  ! (reason = [[self delegate] checkRegistation])  ) {
                [[self delegate] setEmailAddress: [self emailAddress]];
                [[self delegate] setPassword: [self password]];
                [[self delegate] vpnServiceCreateAccount: self finishedWithChoice: VPNServiceCreateAccountNextChoice];
            } else {
                TBRunAlertPanel(NSLocalizedString(@"Cannot register", @"Window title  VPNService"),
                                reason,
                                nil,nil,nil);
                [gMC activateIgnoringOtherApps];
            }
        } else {
            TBRunAlertPanel(NSLocalizedString(@"Password entries must match", @"Window title  VPNService"),
                            NSLocalizedString(@"The password entries must match to proceed.", @"Window text VPNService"),
                            nil,nil,nil);
            [gMC activateIgnoringOtherApps];
        }
    } else {
        TBRunAlertPanel(NSLocalizedString(@"Entries required", @"Window title  VPNService"),
                        NSLocalizedString(@"You must enter an email address, password, and password confirmation to proceed.", @"Window text VPNService"),
                        nil,nil,nil);
        [gMC activateIgnoringOtherApps];
    }
}

- (IBAction) cancelBackButtonWasClicked: sender
{
    if (  [self cancelNotBackButton]  ) {
        [[self delegate] vpnServiceCreateAccount: self finishedWithChoice: VPNServiceCreateAccountCancelChoice];
    } else {
        [[self delegate] vpnServiceCreateAccount: self finishedWithChoice: VPNServiceCreateAccountBackChoice];
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

-(NSString *) passwordConfirm
{
    return [passwordConfirmTF stringValue];
}

-(NSTextFieldCell *) createAccountTFC
{
    return [[createAccountTFC retain] autorelease];
}

-(NSTextFieldCell *) emailAddressTFC
{
    return [[emailAddressTFC retain] autorelease];
}

-(NSTextFieldCell *) passwordTFC
{
    return [[passwordTFC retain] autorelease];
}

-(NSTextFieldCell *) passwordConfirmTFC
{
    return [[passwordConfirmTFC retain] autorelease];
}

-(NSTextField *) emailAddressTF
{
    return [[emailAddressTF retain] autorelease];
}

-(NSTextField *) passwordTF
{
    return [[passwordTF retain] autorelease];
}

-(NSTextField *) passwordConfirmTF
{
    return [[passwordConfirmTF retain] autorelease];
}

-(BOOL)       cancelNotBackButton
{
    return cancelNotBackButton;
}

-(id) delegate
{
    return [[delegate retain] autorelease];
}

@end

#endif
