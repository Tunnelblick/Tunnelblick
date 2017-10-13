/*
 * Copyright 2011, 2012, 2013, 2014, 2015, 2017 Jonathan K. Bullard. All rights reserved.
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


#import "GeneralView.h"

#import "helper.h"

#import "MenuController.h"
#import "TBButton.h"
#import "TBUserDefaults.h"
#import "UIHelper.h"


extern TBUserDefaults * gTbDefaults;

@implementation GeneralView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    return self;
}

-(void) dealloc {
	
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect {
    // Drawing code here.
	
	(void) dirtyRect;
}

-(void) awakeFromNib
{
    // Keyboard Shortcuts popup
    // We allow F1...F12 as keyboard shortcuts (or no shortcut) so the menu isn't too long (and MacBook keyboards only go that high, anyway)
    [keyboardShortcutTFC setTitle: NSLocalizedString(@"Keyboard shortcut:", @"Window text")];
    const unichar cmdOptionChars[] = {0x2318,' ',0x2325};
    NSString * cmdOptionString = [NSString stringWithCharacters: cmdOptionChars
                                                         length: sizeof cmdOptionChars / sizeof * cmdOptionChars];
    NSMutableArray * kbsContent = [NSMutableArray arrayWithCapacity: 12];
    [kbsContent addObject: [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"No keyboard shortcut", @"Button"), @"name", [NSNumber numberWithUnsignedInt: 0], @"value", nil]];
    unsigned i;
    for (  i=0; i<12; i++  ) {
        [kbsContent addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                // Display <cmd><option>F1 (Command-Option-F1)...; Value is 0...11
                                [NSString stringWithFormat: 
                                 NSLocalizedString(@"%@ F%d (Command-Option-F%d)", @"Button"), cmdOptionString, i+1, i+1], @"name",
                                [NSNumber numberWithUnsignedInt: i], @"value",
                                nil]];
    }
    
    BOOL rtl = [UIHelper languageAtLaunchWasRTL];
    
    [keyboardShortcutArrayController setContent: kbsContent];
    [UIHelper setTitle: nil ofControl: keyboardShortcutButton shift: rtl narrow: YES enable: YES];
    
    // Log display size popup
    // We allow specific log display sizes
    [maxLogDisplaySizeTFC               setTitle: NSLocalizedString(@"Maximum log display size:", @"Window text")];
    NSArray * mlsContent = [NSArray arrayWithObjects:
                            [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString( @"10 KB", @"Button"), @"name", [NSNumber numberWithUnsignedInt:       10*1024], @"value", nil],
                            [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"100 KB", @"Button"), @"name", [NSNumber numberWithUnsignedInt:      100*1024], @"value", nil],
                            [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(  @"1 MB", @"Button"), @"name", [NSNumber numberWithUnsignedInt:     1024*1024], @"value", nil],
                            [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString( @"10 MB", @"Button"), @"name", [NSNumber numberWithUnsignedInt:  10*1024*1024], @"value", nil],
                            nil];
    [maximumLogSizeArrayController setContent: mlsContent];
    [UIHelper setTitle: nil ofControl: maximumLogSizeButton shift: rtl narrow: YES enable: YES];
    
    [warningsTFC setTitle: NSLocalizedString(@"Warnings:", @"Window text")];

	[resetDisabledWarningsButton
	 setTitle: NSLocalizedString(@"Reset Disabled Warnings", @"Button")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>Restores warnings that have been inhibited by a 'Do not warn about this again' checkbox.</p>",
														   @"HTML info for the 'Reset Disabled Warnings' button."))
	 disabled: [gTbDefaults boolForKey: @"disableResetDisabledWarningsButton"]];
	
	[tbInternetAccessTFC setTitle: NSLocalizedString(@"Tunnelblick Internet Use:", @"Window text")];
	
	[inhibitOutboundTBTrafficCheckbox
	 setTitle: NSLocalizedString(@"Inhibit automatic update checking and IP Address checking", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, no automatic checking for updates or checking for IP address changes will be done, regardless of other settings."
														   @" Note: both of these activities access the Tunnelblick website.</p>\n"
														   @"<p><strong>When not checked</strong>, automatic checking for updates will be done if enabled below, and checking for IP address changes will be done"
														   @" when connecting a configuration if the configuration's setting to do so is enabled.</p>"
														   @"<p>See <a href=\"https://tunnelblick.net/cPrivacy.html\">Privacy and Security</a> [tunnelblick.net] for details.</p>"
														   @"<p>&nbsp;</p>",
														   @"HTML info for the 'Inhibit automatic update checking and IP Address checking' checkbox."))];
	
	[generalConfigurationChangesTFC setTitle: NSLocalizedString(@"Configuration changes:", @"Window text")];
	
	[generalAdminApprovalForKeyAndCertificateChangesCheckbox
	 setTitle: NSLocalizedString(@"Require administrator authorization for key and certificate changes", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, Tunnelblick will require a computer administrator's authorization to make changes to key and certificate files.</p>\n"
														   @"<p><strong>When not checked</strong>, a standard user will allowed to make changes to key and certificate files.</p>"
														   @"<p><strong>Note: A computer administrator's authorization is required to change this setting.</strong></p>",
														   @"HTML info for the 'Require administrator authorization for key and certificate changes' checkbox."))];
	
	[updatesUpdatesTFC setTitle: NSLocalizedString(@"Updates:", @"Window text")];
	
	[updatesCheckAutomaticallyCheckbox
	 setTitle: NSLocalizedString(@"Check for updates automatically", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, Tunnelblick will check for updates when launched and periodically thereafter.</p>"
														   @"<p><strong>This checkbox is disabled</strong> and un-checked when 'Inhibit automatic update checking and IP Address checking' is checked.</p>",
														   @"HTML info for the 'Check for updates automatically' checkbox."))];
	
	[updatesCheckForBetaUpdatesCheckbox
	 setTitle: NSLocalizedString(@"Check for updates to beta versions", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, Tunnelblick will check for updates to beta versions.</p>\n"
														   @"<p><strong>When not checked</strong>, Tunnelblick will check for updates to stable versions.</p>"
														   @"<p><strong>This checkbox is disabled</strong> and checked when using a beta version.</p>",
														   @"HTML info for the 'Check for updates to beta versions' checkbox."))];
	
	[updatesCheckNowButton
	 setTitle: NSLocalizedString(@"Check Now", @"Button")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>Checks for updates to the Tunnelblick application.</p>"
														   @"<p>Accesses the Tunnelblick website; for more details see <a href=\"https://tunnelblick.net/cPrivacy.html\">Privacy and Security</a> [tunnelblick.net].</p>"
														   @"<p>Also checks for updates to configurations if your VPN service provider implements that feature.</p>",
														   @"HTML info for the 'Check Now' button."))
	 disabled: [gTbDefaults boolForKey: @"disableCheckNowButton"]];
}


//***************************************************************************************************************
// Getters

TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *, keyboardShortcutArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          keyboardShortcutButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *, maximumLogSizeArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          maximumLogSizeButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,   tbInternetAccessTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextField *,       tbInternetAccessTF)
TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,          inhibitOutboundTBTrafficCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,   generalConfigurationChangesTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextField *,       generalConfigurationChangesTF)
TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,          generalAdminApprovalForKeyAndCertificateChangesCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,   updatesUpdatesTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextField *,       updatesUpdatesTF)
TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,          updatesCheckAutomaticallyCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,          updatesCheckForBetaUpdatesCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,          updatesCheckNowButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,   updatesLastCheckedTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextField *,       updatesLastCheckedTF)

@end
