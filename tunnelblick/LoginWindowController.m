/*
 * Copyright 2011, 2012, 2013, 2015, 2016, 2019, 2021 Jonathan K. Bullard. All rights reserved.
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


extern MenuController * gMC;
extern TBUserDefaults * gTbDefaults;

@implementation LoginWindowController

TBSYNTHESIZE_OBJECT_GET(retain, NSTextField       *, username)
TBSYNTHESIZE_OBJECT_GET(retain, NSSecureTextField *, password)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextField       *, visiblePassword)
TBSYNTHESIZE_OBJECT_GET(retain, NSSecureTextField *, securityToken)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextField       *, visibleSecurityToken)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *, saveUsernameInKeychainCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *, savePasswordInKeychainCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, TBButton *, useSecurityTokenCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *, alwaysShowLoginWindowCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *, eyeButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *, securityEyeButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSImage *, eyeNormal)
TBSYNTHESIZE_OBJECT_GET(retain, NSImage *, eyeRedSlash)

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
    
    eyeNormal   = [[NSImage imageNamed: @"eyeNormal"]   retain];
    eyeRedSlash = [[NSImage imageNamed: @"eyeRedSlash"] retain];

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
    NSString * localName = [gMC localizedNameForDisplayName: displayName];
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

    [saveUsernameInKeychainCheckbox setTitle: NSLocalizedString(@"Save in Keychain",        @"Checkbox name")];
    [savePasswordInKeychainCheckbox setTitle: NSLocalizedString(@"Save in Keychain",        @"Checkbox name")];
    [useSecurityTokenCheckbox setTitle: NSLocalizedString(@"Token", @"Checkbox name")
														 infoTitle: attributedStringFromHTML(NSLocalizedString(
																												  @"<p>Allows for the additional entry of a security token when checked.</p>\n"
																												  @"<p>This token is appended to the password during the authentication process. This enables the simultaneous use of authentication devices (dongels) together with the the keychain to secure the password.</p>\n",
																												  @"HTML Info for security token checkbox"))];
	  [alwaysShowLoginWindowCheckbox  setTitle: NSLocalizedString(@"Always show this window", @"Checkbox name")];

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
	
    NSString * passwordLocal = [delegate passwordFromKeychain];
    if (  passwordLocal  ) {
		// Password is in the Keychain, so don't show the eye button
		[[self eyeButton] setEnabled: NO];
		[[self eyeButton] setHidden:  YES];
	} else {
		// Password is not in the Keychain, so set it to an empty string and show the eye button
		passwordLocal = @"";
		[[self eyeButton] setEnabled: YES];
		[[self eyeButton] setHidden:  NO];
	}
	
	[self setInputBoxAndImageAndPassword: passwordLocal exposed: NO];

	[[self savePasswordInKeychainCheckbox] setState:   (  ([passwordLocal length] == 0)
                                                        ? NSOffState
                                                        : NSOnState)];
	[[self savePasswordInKeychainCheckbox] setEnabled: setSaveUsernameCheckbox];  // Enabled only if saving username

	NSString * key = [[delegate displayName] stringByAppendingString: @"-alwaysShowLoginWindow"];
	[[self alwaysShowLoginWindowCheckbox] setState: (  [gTbDefaults boolForKey: key]
													 ? NSOnState
													 : NSOffState)];
	[[self alwaysShowLoginWindowCheckbox] setEnabled: TRUE];
	
	key = [[delegate displayName] stringByAppendingString: @"-loginWindowSecurityTokenCheckboxIsChecked"];
	[[self useSecurityTokenCheckbox] setState:( [gTbDefaults boolForKey:key] ? NSOnState : NSOffState)];
	[[self securityToken] setEnabled:[gTbDefaults boolForKey:key]];
	[[self visibleSecurityToken] setEnabled:[gTbDefaults boolForKey:key]];
	[[self securityEyeButton] setEnabled:[gTbDefaults boolForKey:key]];
	[[self securityEyeButton] setHidden:![gTbDefaults boolForKey:key]];
	[self setInputBoxAndSecurityToken:@"" exposed: FALSE];

    [cancelButton setEnabled: YES];
    [OKButton setEnabled: YES];
    [[self window] center];
    [[self window] display];
    [self showWindow: self];
    [gMC activateIgnoringOtherApps];
    [[self window] makeKeyAndOrderFront: self];
	
	NSTextField * itemToSelect = (  ([usernameLocal length] == 0)
								  ? [self username]
								  : [self password]);
	[itemToSelect selectText: self];
	[[self window] setInitialFirstResponder: itemToSelect];
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
	
	// If the password is exposed, copy it from the NSTextBox to the NSSecureTextBox
	if (  [[eyeButton image] isEqual: eyeRedSlash]  ) {
		[[self password] setStringValue: [visiblePassword stringValue]];
	}

    const char * usernameC = [escaped(  [[self username] stringValue]  ) UTF8String];
    const char * passwordC = [escaped(  [[self password] stringValue]  ) UTF8String];
    const char * securityTokenC = (  [self useSecurityTokenChecked]
                                   ? [escaped(  [[self securityToken] stringValue]  ) UTF8String]
                                   : "" );

    if (   (strlen(usernameC) == 0)
        || (strlen(usernameC) > MAX_LENGTH_OF_QUOTED_MANGEMENT_INTERFACE_PARAMETER)
        || ((strlen(passwordC) + strlen(securityTokenC)) > MAX_LENGTH_OF_QUOTED_MANGEMENT_INTERFACE_PARAMETER)
				|| ([self useSecurityTokenChecked] && strlen(securityTokenC) == 0)) {
        [UIHelper shakeWindow: self.window];
        return;
    }

	NSString * key = [[delegate displayName] stringByAppendingString: @"-alwaysShowLoginWindow"];
	[gTbDefaults setBool: [self isAlwaysShowLoginWindowChecked] forKey: key];
	
	key = [[delegate displayName] stringByAppendingString: @"-loginWindowSecurityTokenCheckboxIsChecked"];
	[gTbDefaults setBool: [self useSecurityTokenChecked] forKey: key];

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

-(IBAction) useSecurityTokenCheckboxWasClicked: (id) sender {
    (void) sender;
    BOOL isEnabled = [useSecurityTokenCheckbox state] == NSOnState;

    [securityToken setEnabled:isEnabled];
    [visibleSecurityToken setEnabled:isEnabled];
    [securityEyeButton setEnabled:isEnabled];
    [securityEyeButton setHidden:!isEnabled];
    [[self securityToken] setStringValue:@""];
    [[self visibleSecurityToken] setStringValue:@""];
}

-(void) exposePasswordAndSetImage {

    [[self password] setHidden:  TRUE];
    [[self password] setEnabled: FALSE];

    [[self visiblePassword] setHidden:  FALSE];
    [[self visiblePassword] setEnabled: TRUE];

    [[self username] setNextKeyView: [self visiblePassword]];

    [[self eyeButton] setImage: eyeRedSlash];
}

-(void) hidePasswordAndSetImage {

    [[self visiblePassword] setHidden:  TRUE];
    [[self visiblePassword] setEnabled: FALSE];

    [[self password] setHidden:  FALSE];
    [[self password] setEnabled: TRUE];

    [[self username] setNextKeyView: [self password]];

    [[self eyeButton] setImage: eyeNormal];
}

-(void) setInputBoxAndImageAndPassword: (NSString *) pw exposed: (BOOL) exposed {

    if (  exposed  ) {
        [[self visiblePassword] setStringValue: pw];
        [self exposePasswordAndSetImage];
    } else {
        [[self password] setStringValue: pw];
        [self hidePasswordAndSetImage];
    }
}

-(void) setInputBoxAndSecurityToken: (NSString *) token exposed: (BOOL) exposed {

    if (  exposed  ) {
        [[self visibleSecurityToken] setStringValue: token];
        [[self securityEyeButton] setImage: eyeRedSlash];
    } else {
        [[self securityToken] setStringValue: token];
        [[self securityEyeButton] setImage: eyeNormal];
    }
    [[self securityToken] setHidden: exposed];
		[[self securityToken] setEnabled: !exposed];
    [[self visibleSecurityToken] setHidden: !exposed];
	  [[self visibleSecurityToken] setEnabled: exposed];
}

-(IBAction) eyeButtonWasClicked: (id) sender {

    if (  [[eyeButton image] isEqual: eyeNormal]  ) {

        // Make password visible and swap the eye image
        NSString * pw = [[self password] stringValue];
        [self setInputBoxAndImageAndPassword: pw exposed: YES];

    } else {

        // Make password invisible and swap the eye image
        NSString * pw = [[self visiblePassword] stringValue];
        [self setInputBoxAndImageAndPassword: pw exposed: NO];
    }
    
    (void) sender;
}

-(IBAction) securityEyeButtonWasClicked: (id) sender {

		if (  [[securityEyeButton image] isEqual: eyeNormal]  ) {

				// Make token visible and swap the eye image
				NSString * token = [[self securityToken] stringValue];
				[self setInputBoxAndSecurityToken: token exposed: YES];

		} else {

				// Make token invisible and swap the eye image
				NSString * token = [[self visibleSecurityToken] stringValue];
        [self setInputBoxAndSecurityToken: token exposed: NO];
		}
		
		(void) sender;
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

-(BOOL) useSecurityTokenChecked
{
	return (  [useSecurityTokenCheckbox state] == NSOnState  );
}

-(BOOL) isAlwaysShowLoginWindowChecked
{
	return (  [alwaysShowLoginWindowCheckbox state] == NSOnState  );
}

-(id) delegate
{
    return [[delegate retain] autorelease];
}

@end
