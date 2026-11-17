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
#import "TBTotpCredentials.h"
#import "TBTotpSecretImporter.h"
#import "UIHelper.h"


extern MenuController * gMC;
extern TBUserDefaults * gTbDefaults;

@interface LoginWindowController ()
{
    NSButton    * configureTotpButton;
    NSButton    * clearTotpButton;
    NSTextField * totpHintLabel;
}

-(void) setupTotpLoginControls;
-(void) updateTotpLoginControlsForDisplayName: (NSString *) displayName;
-(void) applyConfigureTotpButtonStyle;
-(void) showTotpSuccessAlertWithTitle: (NSString *) title message: (NSString *) message;

@end

@implementation LoginWindowController

TBSYNTHESIZE_OBJECT_GET(retain, NSTextField       *, username)
TBSYNTHESIZE_OBJECT_GET(retain, NSSecureTextField *, password)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextField       *, visiblePassword)
TBSYNTHESIZE_OBJECT_GET(retain, NSSecureTextField *, securityToken)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextField       *, visibleSecurityToken)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *, saveUsernameInKeychainCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *, savePasswordInKeychainCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, TBButton *, useSecurityTokenCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *, eyeButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *, securityEyeButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSImage *, eyeNormal)
TBSYNTHESIZE_OBJECT_GET(retain, NSImage *, eyeRedSlash)

TBSYNTHESIZE_OBJECT_GET(retain, NSView *, securityTokenView)

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

    CGFloat oldUseSecurityTokenCheckboxWidth = [useSecurityTokenCheckbox frame].size.width;

// The following doesn't work because this is a modal window. That means that it will not trigger UI updates until it is done
//	[useSecurityTokenCheckbox setTitle: NSLocalizedString(@"Security code:", @"Checkbox name. This checkbox allows the user to type in a security code as shown on an authentication device such as a dongle.")
//                             infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>Allows for the additional entry of a security code when checked.</p>\n"
//                                                                                   @"<p>This code is appended to the password during the authentication process. This enables the simultaneous use of authentication devices such as dongles together with the keychain to secure the password.</p>\n",

//                                                                                   @"HTML Info for security code checkbox"))];

	[useSecurityTokenCheckbox setTitle: NSLocalizedString(@"Security code:", @"Checkbox name. This checkbox allows the user to type in a security code as shown on an authentication device such as a dongle.")];
	[useSecurityTokenCheckbox sizeToFit];

    [self setupTotpLoginControls];

	[savePasswordInKeychainCheckbox setState:   NSOffState];
    [savePasswordInKeychainCheckbox setEnabled: NO];

    BOOL rtl = [UIHelper languageAtLaunchWasRTL];
    
    CGFloat widthChange = [UIHelper setTitle: NSLocalizedString(@"OK", @"Button") ofControl: OKButton     shift: ( !rtl ) narrow: NO enable: YES];
    
    [UIHelper setTitle: NSLocalizedString(@"Cancel", @"Button")                   ofControl: cancelButton shift: ( !rtl ) narrow: NO enable: YES];
    
    // Adjust position of Cancel button if the OK button got bigger or smaller
    [UIHelper shiftControl: cancelButton by: widthChange reverse: rtl];

	// If a LTR language and the "Token:" checkbox got smaller, shift it to the right,
	// so it is flush right, like the "Username:" and "Password" labels.
	// In an RTL language, it doesn't need to shift; it is already flush left
	if (  ! rtl )  {
		NSRect frame = [useSecurityTokenCheckbox frame];
		widthChange = oldUseSecurityTokenCheckboxWidth - frame.size.width;
		if (  widthChange > 0.0  ) {
			frame.origin.x += widthChange;
			[useSecurityTokenCheckbox setFrame: frame];
		}
	}

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

	NSString * key = [displayName stringByAppendingString: @"-loginWindowSecurityTokenCheckboxIsChecked"];
    NSString * totpCode = [TBTotpCredentials currentTotpCodeForDisplayName: displayName];
    if (  totpCode  ) {
        [[self useSecurityTokenCheckbox] setState: NSOnState];
    } else {
        [[self useSecurityTokenCheckbox] setState:( [gTbDefaults boolForKey:key] ? NSOnState : NSOffState)];
    }
	[[self securityEyeButton] setEnabled:[gTbDefaults boolForKey:key] || ( totpCode != nil )];
	[[self securityEyeButton] setHidden:![gTbDefaults boolForKey:key] && ( totpCode == nil )];
    if (  totpCode  ) {
        [self setInputBoxAndSecurityToken: totpCode exposed: FALSE];
    } else {
        [self setInputBoxAndSecurityToken:@"" exposed: FALSE];
    }

    key = [displayName stringByAppendingString: @"-loginWindowSecurityTokenIsHidden"];
    [[self securityTokenView] setHidden:[gTbDefaults boolForKey:key]];

    [self updateTotpLoginControlsForDisplayName: displayName];

    [cancelButton setEnabled: YES];
    [OKButton setEnabled: YES];
    [[self window] center];
    [[self window] setCollectionBehavior: NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary];
    [[self window] display];
    [self showWindow: self];
    [gMC activateIgnoringOtherApps];
    [[self window] makeKeyAndOrderFront: self];
	
	NSTextField * itemToSelect = (  ([usernameLocal length] == 0)
								  ? [self username]
								  : (  ([passwordLocal length] == 0)
									 ? [self password]
									 : [self securityToken]));
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
	
	// If the password or token is exposed, copy it from the NSTextBox to the NSSecureTextBox
	if (  [[eyeButton image] isEqual: eyeRedSlash]  ) {
		[[self password] setStringValue: [visiblePassword stringValue]];
	}
    if (  [[securityEyeButton image] isEqual: eyeRedSlash]  ) {
        [[self securityToken] setStringValue: [visibleSecurityToken stringValue]];
    }

    const char * usernameC = [escaped(  [[self username] stringValue]  ) UTF8String];
    const char * passwordC = [escaped(  [[self password] stringValue]  ) UTF8String];
    const char * securityTokenC = (  [self useSecurityTokenChecked]
                                   ? [escaped(  [[self securityToken] stringValue]  ) UTF8String]
                                   : "" );

    if (   (strlen(usernameC) == 0)
        || (strlen(usernameC) > MAX_LENGTH_OF_QUOTED_MANGEMENT_INTERFACE_PARAMETER)
        || ((strlen(passwordC) + strlen(securityTokenC)) > MAX_LENGTH_OF_QUOTED_MANGEMENT_INTERFACE_PARAMETER)  ) {
        [UIHelper shakeWindow: self.window];
        return;
    }

	NSString * key = [[delegate displayName] stringByAppendingString: @"-loginWindowSecurityTokenCheckboxIsChecked"];
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

-(void) setupTotpLoginControls
{
    NSView * contentView = [[self window] contentView];

    if (  ! totpHintLabel  ) {
        totpHintLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(20, 2, 420, 14)];
        [totpHintLabel setBezeled: NO];
        [totpHintLabel setEditable: NO];
        [totpHintLabel setDrawsBackground: NO];
        [totpHintLabel setTextColor: [NSColor secondaryLabelColor]];
        [totpHintLabel setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize] - 1]];
        [[totpHintLabel cell] setWraps: YES];
        [[totpHintLabel cell] setScrollable: NO];
        [totpHintLabel setStringValue: NSLocalizedString(@"You can also manage this in Options → Advanced → VPN Credentials.", @"Window text")];
        [contentView addSubview: totpHintLabel];
    }

    if (  ! configureTotpButton  ) {
        configureTotpButton = [[NSButton alloc] initWithFrame: NSMakeRect(20, 18, 220, 22)];
        [configureTotpButton setBezelStyle: NSBezelStyleInline];
        [configureTotpButton setButtonType: NSButtonTypeMomentaryPushIn];
        [configureTotpButton setBordered: NO];
        [configureTotpButton setTarget: self];
        [configureTotpButton setAction: @selector(configureTotpButtonWasClicked:)];
        [contentView addSubview: configureTotpButton];
    }
    [self applyConfigureTotpButtonStyle];

    if (  ! clearTotpButton  ) {
        clearTotpButton = [[NSButton alloc] initWithFrame: NSMakeRect(250, 18, 180, 22)];
        [clearTotpButton setBezelStyle: NSBezelStyleInline];
        [clearTotpButton setButtonType: NSButtonTypeMomentaryPushIn];
        [clearTotpButton setBordered: NO];
        [clearTotpButton setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize]]];
        [clearTotpButton setTitle: NSLocalizedString(@"Clear Automatic Security Code", @"Button")];
        [clearTotpButton setTarget: self];
        [clearTotpButton setAction: @selector(clearTotpButtonWasClicked:)];
        [contentView addSubview: clearTotpButton];
    }
}

-(void) applyConfigureTotpButtonStyle
{
    NSString * title = NSLocalizedString(@"Configure automatic security code…", @"Button");
    NSMutableAttributedString * attrTitle = [[[NSMutableAttributedString alloc] initWithString: title] autorelease];
    NSRange fullRange = NSMakeRange(0, [attrTitle length]);
    [attrTitle addAttribute: NSForegroundColorAttributeName value: [NSColor systemRedColor] range: fullRange];
    [attrTitle addAttribute: NSFontAttributeName value: [NSFont systemFontOfSize: 12.0] range: fullRange];
    [attrTitle addAttribute: NSUnderlineStyleAttributeName value: [NSNumber numberWithInt: NSUnderlineStyleSingle] range: fullRange];
    [configureTotpButton setAttributedTitle: attrTitle];
}

-(void) updateTotpLoginControlsForDisplayName: (NSString *) displayName
{
    if (  ! configureTotpButton  ) {
        return;
    }

    NSString * credentialsName = [TBTotpCredentials credentialsNameForDisplayName: displayName];
    BOOL hasSecret = [TBTotpCredentials keychainHasTotpSecretForCredentialsName: credentialsName];
    [clearTotpButton setHidden: ! hasSecret];
    [clearTotpButton setEnabled: hasSecret];
    [self applyConfigureTotpButtonStyle];
}

-(void) showTotpSuccessAlertWithTitle: (NSString *) title message: (NSString *) message
{
    TBRunAlertPanel(title, message, nil, nil, nil);
}

-(IBAction) clearTotpButtonWasClicked: (id) sender
{
    (void) sender;

    int result = TBRunAlertPanel(NSLocalizedString(@"Clear Automatic Security Code", @"Window title"),
                                 NSLocalizedString(@"Are you sure you want to remove the automatic security code secret?", @"Window text"),
                                 NSLocalizedString(@"Clear", @"Button"),
                                 NSLocalizedString(@"Cancel", @"Button"),
                                 nil);
    if (  result != NSAlertDefaultReturn  ) {
        return;
    }

    NSString * displayName = [[self delegate] displayName];
    [TBTotpCredentials deleteTotpSecretForDisplayName: displayName];
    [self redisplay];
    [self showTotpSuccessAlertWithTitle: NSLocalizedString(@"Cleared", @"Window title")
                                message: NSLocalizedString(@"The automatic security code secret has been removed.", @"Window text")];
}

-(IBAction) configureTotpButtonWasClicked: (id) sender
{
    (void) sender;

    NSString * displayName = [[self delegate] displayName];

    NSAlert * alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText: NSLocalizedString(@"Configure Automatic Security Code", @"Window title")];
    [alert setInformativeText: NSLocalizedString(@"Paste a Google Authenticator otpauth:// URI or Base32 secret. The root secret is stored in the macOS Keychain on this computer. Anyone with access to this computer or the secret can generate your security codes. Do not share the QR code or secret with others.", @"Window text")];
    [alert addButtonWithTitle: NSLocalizedString(@"Save", @"Button")];
    [alert addButtonWithTitle: NSLocalizedString(@"Import QR Image…", @"Button")];
    [alert addButtonWithTitle: NSLocalizedString(@"Cancel", @"Button")];

    NSTextField * input = [[[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 360, 22)] autorelease];
    [input setStringValue: @""];
    [alert setAccessoryView: input];

    NSInteger response = [alert runModal];
    if (  response == NSAlertSecondButtonReturn  ) {
        NSOpenPanel * panel = [NSOpenPanel openPanel];
        [panel setCanChooseFiles: YES];
        [panel setCanChooseDirectories: NO];
        [panel setAllowsMultipleSelection: NO];
        [panel setAllowedFileTypes: @[@"png", @"jpg", @"jpeg", @"gif", @"bmp", @"tif", @"tiff"]];
        if (  [panel runModal] == NSModalResponseOK  ) {
            NSString * path = [[panel URL] path];
            NSString * importError = nil;
            NSString * secret = [TBTotpSecretImporter secretFromQRImageAtPath: path error: &importError];
            if (  secret  ) {
                if (  [TBTotpCredentials saveTotpSecret: secret forDisplayName: displayName]  ) {
                    [self redisplay];
                    [self showTotpSuccessAlertWithTitle: NSLocalizedString(@"Import Successful", @"Window title")
                                                message: NSLocalizedString(@"The TOTP secret from the QR code has been saved.", @"Window text")];
                } else {
                    TBRunAlertPanel(NSLocalizedString(@"Error", @"Window title"),
                                    NSLocalizedString(@"Could not save the TOTP secret to the Keychain.", @"Window text"),
                                    nil, nil, nil);
                }
            } else {
                TBRunAlertPanel(NSLocalizedString(@"Import Failed", @"Window title"),
                                importError ? importError : NSLocalizedString(@"Could not import the QR code.", @"Window text"),
                                nil, nil, nil);
            }
        }
        return;
    }

    if (  response != NSAlertFirstButtonReturn  ) {
        return;
    }

    NSString * error = nil;
    NSString * secret = [TBTotpSecretImporter secretFromPastedString: [input stringValue] error: &error];
    if (  ! secret  ) {
        TBRunAlertPanel(NSLocalizedString(@"Invalid Secret", @"Window title"),
                        error ? error : NSLocalizedString(@"The secret could not be saved.", @"Window text"),
                        nil, nil, nil);
        return;
    }

    if (  ! [TBTotpCredentials saveTotpSecret: secret forDisplayName: displayName]  ) {
        TBRunAlertPanel(NSLocalizedString(@"Error", @"Window title"),
                        NSLocalizedString(@"Could not save the TOTP secret to the Keychain.", @"Window text"),
                        nil, nil, nil);
        return;
    }

    [self redisplay];
    [self showTotpSuccessAlertWithTitle: NSLocalizedString(@"Configuration Successful", @"Window title")
                                message: NSLocalizedString(@"Automatic security code has been enabled for this credentials group.", @"Window text")];
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
    BOOL useToken = [self useSecurityTokenChecked];
    [[self securityToken] setHidden: exposed];
    [[self securityToken] setEnabled: !exposed && useToken];
    [[self visibleSecurityToken] setHidden: !exposed];
    [[self visibleSecurityToken] setEnabled: exposed && useToken];
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
    [configureTotpButton release]; configureTotpButton = nil;
    [clearTotpButton release]; clearTotpButton = nil;
    [totpHintLabel release]; totpHintLabel = nil;
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

-(id) delegate
{
    return [[delegate retain] autorelease];
}

@end
