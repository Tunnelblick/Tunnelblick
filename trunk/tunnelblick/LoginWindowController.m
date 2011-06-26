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
#import "LoginWindowController.h"

@interface LoginWindowController() // Private methods

-(void) setTitle: (NSString *) newTitle ofControl: (id) theControl;

@end

@implementation LoginWindowController

-(id) initWithDelegate: (id) theDelegate
{
    if (  ![super initWithWindowNibName:@"LoginWindow"]  ) {
        return nil;
    }
    
    delegate = [theDelegate retain];    
    return self;
}

-(void) awakeFromNib
{
    [[self window] setTitle: NSLocalizedString(@"Tunnelblick: Login Required", @"Window title")];
    
    [iconIV setImage: [NSApp applicationIconImage]];
    
    NSString * text = [NSString stringWithFormat:
                       NSLocalizedString(@"A username and password are required to connect to\n  %@", @"Window text"),
                       [[self delegate] displayName]];
    [mainText setTitle: text];
    
    [usernameTFC setTitle: NSLocalizedString(@"Username:", @"Window text")];
    [passwordTFC setTitle: NSLocalizedString(@"Password:", @"Window text")];

    [saveInKeychainCheckbox setTitle: NSLocalizedString(@"Save in Keychain", @"Checkbox name")];

    [self setTitle: NSLocalizedString(@"OK"    , @"Button") ofControl: OKButton ];
    [self setTitle: NSLocalizedString(@"Cancel", @"Button") ofControl: cancelButton ];
    
    [self redisplay];
}

-(void) redisplay
{
    [cancelButton setEnabled: YES];
    [OKButton setEnabled: YES];
    [[self window] center];
    [[self window] display];
    [self showWindow: self];
    [NSApp activateIgnoringOtherApps: YES];
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
    
    // Don't make the control smaller, only larger
    if (  widthChange < 0.0  ) {
        [theControl setFrame: oldRect];
        widthChange = 0.0;
    }
    
    if (  widthChange != 0.0  ) {
        NSRect oldPos;
        
        // Shift the control itself left/right if necessary
        oldPos = [theControl frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [theControl setFrame:oldPos];
        
        // Shift the cancel button if we changed the OK button
        if (   [theControl isEqual: OKButton]  ) {
            oldPos = [cancelButton frame];
            oldPos.origin.x = oldPos.origin.x - widthChange;
            [cancelButton setFrame:oldPos];
        }
    }
}

- (IBAction) cancelButtonWasClicked: sender
{
    [cancelButton setEnabled: NO];
    [OKButton setEnabled: NO];
    [NSApp abortModal];
}

- (IBAction) OKButtonWasClicked: sender
{
    if (   ( [[[self username] stringValue] length] == 0 )
        || ( [[[self password] stringValue] length] == 0 )  ){
        TBRunAlertPanel(NSLocalizedString(@"Please enter a username and password.", @"Window title"),
                        NSLocalizedString(@"The username and the password must not be empty!\nPlease enter VPN username/password combination.", @"Window text"),
                        nil, nil, nil);
        
        [NSApp activateIgnoringOtherApps: YES];
        return;
    }
    [cancelButton setEnabled: NO];
    [OKButton setEnabled: NO];
    [NSApp stopModal];
}

- (void) dealloc
{
    [mainText               release];
    [iconIV                 release];
    [cancelButton           release];
    [OKButton               release];
    [username               release];
    [password               release];
    [usernameTFC            release];
    [passwordTFC            release];
    [saveInKeychainCheckbox release];
    [delegate               release];
    
	[super dealloc];
}

- (NSString *) description
{
    return [NSString stringWithFormat:@"%@", [self class]];
}

-(NSTextField *) username
{
    return [[username retain] autorelease];
}

-(void) setUsername: (NSTextField *) newValue
{
    if (  username != newValue  ) {
        [username release];
        username = [newValue retain];
    }
}


-(NSTextField *) password
{
    return [[password retain] autorelease];
}

-(void) setPassword: (NSTextField *) newValue
{
    if (  password != newValue  ) {
        [password release];
        password = [newValue retain];
    }
}

-(BOOL) saveInKeychain
{
    if (  [saveInKeychainCheckbox state] == NSOnState  ) {
        return TRUE;
    } else {
        return FALSE;
    }
}

-(id) delegate
{
    return [[delegate retain] autorelease];
}

@end
