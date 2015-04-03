/*
 * Copyright 2011, 2012, 2013 Jonathan K. Bullard. All rights reserved.
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


#import "LoginWindowController.h"

#import "helper.h"

#import "MenuController.h"
#import "TBUserDefaults.h"
#import "AuthAgent.h"


extern TBUserDefaults * gTbDefaults;

@interface LoginWindowController() // Private methods

-(void) setTitle: (NSString *) newTitle ofControl: (id) theControl;

@end

@implementation LoginWindowController

TBSYNTHESIZE_OBJECT(retain, NSTextField *,       username, setUsername)
TBSYNTHESIZE_OBJECT(retain, NSSecureTextField *, password, setPassword)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *, saveUsernameInKeychainCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *, savePasswordInKeychainCheckbox)

-(id) initWithDelegate: (id) theDelegate
{
    self = [super initWithWindowNibName:@"LoginWindow"];
    if (  ! self  ) {
        return nil;
    }
    
	[[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidChangeScreenParametersNotificationHandler:)
                                                 name: NSApplicationDidChangeScreenParametersNotification
                                               object: nil];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(wokeUpFromSleepHandler:)
                                                               name: NSWorkspaceDidWakeNotification
                                                             object: nil];
    
    delegate = [theDelegate retain];
    return self;
}

-(void) awakeFromNib
{
    [[self window] setTitle: NSLocalizedString(@"Tunnelblick: Login Required", @"Window title")];
    
    [iconIV setImage: [NSApp applicationIconImage]];
    
	NSString * displayName = [[self delegate] displayName];
    NSString * localName = [((MenuController *)[NSApp delegate]) localizedNameForDisplayName: displayName];
	NSString * group = credentialsGroupFromDisplayName(displayName);
	NSString * text;
    if (  group  ) {
		text = [NSString stringWithFormat: NSLocalizedString(@"A username and password are required to connect to\n  %@\n(using '%@' credentials)", @"Window text"),
				localName, group];
    } else {
        text = [NSString stringWithFormat: NSLocalizedString(@"A username and password are required to connect to\n  %@", @"Window text"),
                localName];
    }
    
    [mainText setTitle: text];
    
    [usernameTFC setTitle: NSLocalizedString(@"Username:", @"Window text")];
    [passwordTFC setTitle: NSLocalizedString(@"Password:", @"Window text")];

    [saveUsernameInKeychainCheckbox setTitle: NSLocalizedString(@"Save in Keychain", @"Checkbox name")];
    [savePasswordInKeychainCheckbox setTitle: NSLocalizedString(@"Save in Keychain", @"Checkbox name")];

    [self setTitle: NSLocalizedString(@"OK"    , @"Button") ofControl: OKButton];
    [self setTitle: NSLocalizedString(@"Cancel", @"Button") ofControl: cancelButton];
    
    [self redisplay];
}

-(void) redisplayIfShowing
{
    if (  [delegate showingLoginWindow]  ) {
        [self redisplay];
    } else {
        NSLog(@"Cancelled redisplay of login window because it is no longer showing");
    }
}

-(void) redisplay
{
    // If we have saved a username, load the textbox with it and check the "Save in Keychain" checkbox for it
	NSString * displayName = [[self delegate] displayName];
    NSString * usernamePreferenceKey             = [displayName stringByAppendingString: @"-keychainHasUsername"];
    BOOL haveSavedUsername = (   [gTbDefaults boolForKey: usernamePreferenceKey]
							  && [gTbDefaults canChangeValueForKey: usernamePreferenceKey] );
	NSString * usernameLocal = [delegate usernameFromKeychain];
	if (  [usernameLocal length] == 0  ) {
		usernameLocal = @"";
	}
	[[self username] setStringValue: usernameLocal];
	BOOL enableSaveUsernameCheckbox = (  haveSavedUsername
									   ? NSOnState
									   : NSOffState);
    [[self saveUsernameInKeychainCheckbox] setState: enableSaveUsernameCheckbox];
	
    // Always clear the password textbox and set up its "Save in Keychain" checkbox
	[[self password] setStringValue: @""];
	[[self savePasswordInKeychainCheckbox] setState:   NSOffState];
	[[self savePasswordInKeychainCheckbox] setEnabled: enableSaveUsernameCheckbox];
	
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
 	(void) sender;
	
   [cancelButton setEnabled: NO];
    [OKButton setEnabled: NO];
    [NSApp abortModal];
}

- (IBAction) OKButtonWasClicked: sender
{
	(void) sender;
	
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

-(IBAction) saveUsernameInKeychainCheckboxWasClicked: (id) sender {
	
	(void) sender;
	
	if (  [saveUsernameInKeychainCheckbox state] == NSOnState  ) {
		[[self savePasswordInKeychainCheckbox] setState:   NSOffState];
		[[self savePasswordInKeychainCheckbox] setEnabled: YES];
	} else {
		[[self savePasswordInKeychainCheckbox] setState:   NSOffState];
		[[self savePasswordInKeychainCheckbox] setEnabled: NO];
	}
}


-(void) applicationDidChangeScreenParametersNotificationHandler: (NSNotification *) n
{
 	(void) n;
    
	if (   [delegate showingLoginWindow]
		&& (! [gTbDefaults boolForKey: @"doNotRedisplayLoginOrPassphraseWindowAtScreenChangeOrWakeFromSleep"])  ) {
		NSLog(@"LoginWindowController: applicationDidChangeScreenParametersNotificationHandler: requesting redisplay of login window");
        [self performSelectorOnMainThread: @selector(redisplayIfShowing) withObject: nil waitUntilDone: NO];
	}
}

-(void) wokeUpFromSleepHandler: (NSNotification *) n
{
 	(void) n;
    
	if (   [delegate showingLoginWindow]
		&& (! [gTbDefaults boolForKey: @"doNotRedisplayLoginOrPassphraseWindowAtScreenChangeOrWakeFromSleep"])  ) {
		NSLog(@"LoginWindowController: didWakeUpFromSleepHandler: requesting redisplay of login window");
        [self performSelectorOnMainThread: @selector(redisplayIfShowing) withObject: nil waitUntilDone: NO];
	}
}

- (void) dealloc {
    
    [delegate release]; delegate = nil;
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver: self];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    
	[super dealloc];
}

- (NSString *) description
{
    return [NSString stringWithFormat:@"%@", [self class]];
}

-(BOOL) isSaveUsernameInKeychainChecked
{
    return (  [saveUsernameInKeychainCheckbox state] == NSOnState  );
}
		  
-(BOOL) isSavePasswordInKeychainChecked
{
    return (  [savePasswordInKeychainCheckbox state] == NSOnState  );
}

-(id) delegate
{
    return [[delegate retain] autorelease];
}

@end
