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
#import "PassphraseWindowController.h"

@interface PassphraseWindowController() // Private methods

-(void) setTitle: (NSString *) newTitle ofControl: (id) theControl;

@end

@implementation PassphraseWindowController

-(id) initWithDelegate: (id) theDelegate
{
    if (  ![super initWithWindowNibName:@"PassphraseWindow"]  ) {
        return nil;
    }
    
    delegate = [theDelegate retain];    
    return self;
}

-(void) awakeFromNib
{
    [[self window] setTitle: NSLocalizedString(@"Tunnelblick: Passphrase Required", @"Window title")];
    
    [iconIV setImage: [NSApp applicationIconImage]];
    
    NSString * text = [NSString stringWithFormat:
                       NSLocalizedString(@"A passphrase is required to connect to\n  %@", @"Window text"),
                       [[self delegate] displayName]];
    [mainText setTitle: text];
    
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
    if (  [[[self passphrase] stringValue] length] == 0  ) {
        TBRunAlertPanel(NSLocalizedString(@"Please enter VPN passphrase.", @"Window title"),
                        NSLocalizedString(@"The passphrase must not be empty!\nPlease enter VPN passphrase.", @"Window text"),
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
    [cancelButton           release];
    [OKButton               release];
    [passphrase             release];
    [saveInKeychainCheckbox release];
    [delegate               release];
    
	[super dealloc];
}

- (NSString *) description
{
    return [NSString stringWithFormat:@"%@", [self class]];
}

-(NSTextField *) passphrase
{
    return [[passphrase retain] autorelease];
}

-(void) setPassphrase: (NSTextField *) newValue
{
    if (  passphrase != newValue  ) {
        [passphrase release];
        passphrase = [newValue retain];
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
