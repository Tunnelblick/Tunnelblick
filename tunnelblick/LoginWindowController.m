/*
 * Copyright 2011, 2012, 2013, 2015, 2016 Jonathan K. Bullard. All rights reserved.
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

#import "AuthAgent.h"
#import "MenuController.h"
#import "TBUserDefaults.h"
#import "UIHelper.h"


extern TBUserDefaults * gTbDefaults;

@implementation LoginWindowController

TBSYNTHESIZE_OBJECT(retain, NSTextField *,       username, setUsername)
TBSYNTHESIZE_OBJECT(retain, NSSecureTextField *, password, setPassword)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *, saveUsernameInKeychainCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *, savePasswordInKeychainCheckbox)

-(id) initWithDelegate: (id) theDelegate
{
    self = [super initWithWindowNibName: [UIHelper appendRTLIfRTLLanguage: @"LoginWindow"]];
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

-(BOOL) connectWhenSystemStarts {
    
	NSString * displayName = [[self delegate] displayName];
    NSString * autoConnectKey   = [displayName stringByAppendingString: @"autoConnect"];
    NSString * onSystemStartKey = [displayName stringByAppendingString: @"-onSystemStart"];
    return (   [gTbDefaults boolForKey: autoConnectKey]
            && [gTbDefaults boolForKey: onSystemStartKey] );
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

    [savePasswordInKeychainCheckbox setState:   NSOffState];
    [savePasswordInKeychainCheckbox setEnabled: NO];

    BOOL rtl = [UIHelper languageAtLaunchWasRTL];
    
    CGFloat widthChange = [UIHelper setTitle: NSLocalizedString(@"OK", @"Button") ofControl: OKButton     shift: ( !rtl ) narrow: NO enable: YES];
    
    [UIHelper setTitle: NSLocalizedString(@"Cancel", @"Button")                   ofControl: cancelButton shift: ( !rtl ) narrow: NO enable: YES];
    
    // Adjust position of Cancel button if the OK button got bigger or smaller
    [UIHelper shiftControl: cancelButton by: widthChange reverse: rtl];
    
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
    // If we have saved a username, load the textbox with it and check the "Save in Keychain" checkbox for it (unless this is a "when computer starts" configuration)
	NSString * displayName = [[self delegate] displayName];
    BOOL usernameWasSavedBefore = (   keychainHasUsernameWithoutPasswordForDisplayName(displayName)
                                   || keychainHasUsernameAndPasswordForDisplayName(displayName));
	NSString * usernameLocal = [delegate usernameFromKeychain];
	if (  [usernameLocal length] == 0  ) {
		usernameLocal = @"";
	}
	[[self username] setStringValue: usernameLocal];
	BOOL enableSaveUsernameCheckbox = ! [self connectWhenSystemStarts];
    
    BOOL setSaveUsernameCheckbox = enableSaveUsernameCheckbox && usernameWasSavedBefore;

    [[self saveUsernameInKeychainCheckbox] setState:   ( setSaveUsernameCheckbox ? NSOnState : NSOffState )];  // Defaults to "checked" if have already saved username and not "connect when system starts"
    [[self saveUsernameInKeychainCheckbox] setEnabled: enableSaveUsernameCheckbox];
	
    // Always clear the password textbox and set up its "Save in Keychain" checkbox
	[[self password] setStringValue: @""];
	[[self savePasswordInKeychainCheckbox] setState:   NSOffState];               // Defaults to "not checked"
	[[self savePasswordInKeychainCheckbox] setEnabled: setSaveUsernameCheckbox];  // Enabled only if saving username

    [cancelButton setEnabled: YES];
    [OKButton setEnabled: YES];
    [[self window] center];
    [[self window] display];
    [self showWindow: self];
    [NSApp activateIgnoringOtherApps: YES];
    [[self window] makeKeyAndOrderFront: self];
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
	
    const char * usernameC = [[[self username] stringValue] UTF8String];
    const char * passwordC = [[[self password] stringValue] UTF8String];
    if (   (strlen(usernameC) == 0)
        || (strlen(usernameC) > MAX_LENGTH_OF_MANGEMENT_INTERFACE_PARAMETER)
        || (strlen(passwordC) > MAX_LENGTH_OF_MANGEMENT_INTERFACE_PARAMETER)) {
        [UIHelper shakeWindow: self.window];
        return;
    }
    [cancelButton setEnabled: NO];
    [OKButton setEnabled: NO];
    [NSApp stopModal];
}

-(IBAction) saveUsernameInKeychainCheckboxWasClicked: (id) sender {
	
	(void) sender;
	
	if (  (   ([saveUsernameInKeychainCheckbox state] == NSOnState)
           && ( ! [self connectWhenSystemStarts])) ) {
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
