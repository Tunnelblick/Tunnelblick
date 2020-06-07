/*
 * Copyright 2011, 2012, 2013, 2014, 2015, 2017, 2018 Jonathan K. Bullard. All rights reserved.
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


#import "UtilitiesView.h"

#import "easyRsa.h"
#import "helper.h"

#import "MenuController.h"
#import "NSFileManager+TB.h"
#import "TBButton.h"
#import "TBUserDefaults.h"
#import "UIHelper.h"

extern NSFileManager  * gFileMgr;
extern MenuController * gMC;
extern TBUserDefaults * gTbDefaults;

@implementation UtilitiesView

-(void) dealloc {
	
    [super dealloc];
}

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    // Drawing code here.
	
	(void) dirtyRect;
}

-(void) setUtilitiesQuitAllOpenVpnButtonTitle: (NSString *) title {
	
	// Set the button's title and adjust the size of the button.
	// If its width changes, shift the button and/or the status text next to it appropriately
	
	CGFloat oldWidth = [utilitiesQuitAllOpenVpnButton frame].size.width;
	[utilitiesQuitAllOpenVpnButton setTitle: title];
	[utilitiesQuitAllOpenVpnButton sizeToFit];
	CGFloat newWidth = [utilitiesQuitAllOpenVpnButton frame].size.width;
	CGFloat widthChange = oldWidth - newWidth;
	
	if (  [gMC languageAtLaunchWasRTL]  ) {
		widthChange = -widthChange;

		NSRect f = [utilitiesQuitAllOpenVpnButton frame];	// Shift the button itself
		f.origin.x -= widthChange;
		[utilitiesQuitAllOpenVpnButton setFrame: f];
	}
	
	NSRect f = [utilitiesQuitAllOpenVpnStatusTF frame];		// Shift the status text next to the button
	f.origin.x -= widthChange;
	[utilitiesQuitAllOpenVpnStatusTF setFrame: f];
}

-(void) awakeFromNib
{
	[utilitiesQuitAllOpenVpnStatusTFC setTitle: @""];
	
	// SET ONE BUTTON TITLE HERE **FIRST** so it adjusts the position of the status text, too.
	// Then when we set it to the same thing (a couple of lines down), it doesn't change its width
	[self setUtilitiesQuitAllOpenVpnButtonTitle: NSLocalizedString(@"Quit All OpenVPN Processes", @"Button")];

	[utilitiesQuitAllOpenVpnButton
	  setTitle: NSLocalizedString(@"Quit All OpenVPN Processes", @"Button")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>Quits all OpenVPN processes, including those which were not"
														   @" started by Tunnelblick. You should use the Tunnelblick 'Disconnect' or 'Disconnect All' buttons and menu commands to disconnect"
														   @" configurations which were connected using Tunnelblick.</p>"
														   @"<p>Clicking this button sends a 'SIGTERM' signal to all processes named 'openvpn'. Normally this will cause OpenVPN to close all"
														   @" connections and quit. If this button does not quit all OpenVPN processes, you may need to use the macOS Activity Monitor"
														   @" application to 'Force Quit' the process.</p>",
														   @"HTML info for the 'Quit All OpenVPN Processes' button."))
	 disabled: ! ALLOW_OPENVPNSTART_KILLALL];
	
	[consoleLogToClipboardButton
	  setTitle: NSLocalizedString(@"Copy Console Log to Clipboard", @"Button")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>Copies the last part of the Console Log to the Clipboard so it may be pasted into an email or other document.</p>"
														   @"<p>The log contains details of Tunnelblick's and OpenVPN's operations. It includes normal status messages"
														   @" and detailed error messages that are too long to present to the user in a normal dialog window.</p>",
														   @"HTML info for the 'Copy Console Log to Clipboard' button."))];
	
	[utilitiesExportTunnelblickSetupButton
	  setTitle: NSLocalizedString(@"Export Tunnelblick Setup", @"Button")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>Exports the Tunnelblick setup, including all configurations and settings"
														   @" for all users of this computer, to a compressed file on the Desktop.</p>"
														   @"<ul><li>Credentials saved in the Keychain are <strong>not</strong> exported.</li>"
														   @"<li>The export may take a long time.</li></ul>",
														   @"HTML info for the 'Export Tunnelblick Setup' button."))];
	
	[utilitiesOpenUninstallInstructionsButton
	  setTitle: NSLocalizedString(@"Open Uninstall Instructions in Browser", @"Button")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>Opens a browser window containing information on the Tunnelblick website about uninstalling Tunnelblick.</p>",
														   @"HTML info for the 'Open Uninstall Instructions in Browser' button."))];
	
	[utilitiesRunEasyRsaButton
	  setTitle: NSLocalizedString(@"Open easy-rsa in Terminal", @"Button")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>Tunnelblick includes a customized version of 'easy-rsa', which is a set of command line scripts written by the OpenVPN developers for creating and maintaining certificates and keys.</p>"
														   @"<p>Clicking this button launches the macOS Terminal application with the working directory set to the folder containing the scripts.</p>"
														   @"<p>The scripts are normally located in the folder at ~/Library/Application Support/Tunnelblick/easy-rsa. An 'easy-rsaPath' preference can contain the path to a folder that Tunnelblick will use instead."
														   @" 'easy-rsaPath' must be an absolute path or start with a '~', and the parent folder of the path must exist. If a folder exists at the path, it will be used;"
														   @" if it does not exist, it will be created and the easy-rsa scripts will be installed into it when Tunnelblick is launched.</p>"
														   @"<p>For information about using easy-rsa, see <a href=\"https://openvpn.net/index.php/open-source/documentation/howto.html#pki\">Setting"
														   @" up your own Certificate Authority (CA) and generating certificates and keys for an OpenVPN server and multiple clients</a> [openvpn.net].</p>"
														   @"<p>For details of Tunnelblick's customizations of easy-rsa, see the README file located in the folder.</p>",
														   @"HTML info for the 'Open easy-rsa in Terminal' button."))];
	
    NSString * easyRsaPathMessage;
    if (  [gTbDefaults stringForKey: @"easy-rsaPath"]  ) {
        easyRsaPathMessage = easyRsaPathToUse(YES);
        if (  ( ! easyRsaPathMessage )  ) {
            easyRsaPathMessage = NSLocalizedString(@"(The 'easy-rsaPath' preference is invalid.)", @"Window text");
            [utilitiesRunEasyRsaButton setEnabled: NO];
        }
    } else {
        easyRsaPathMessage = @"";
    }
    [utilitiesEasyRsaPathTFC setTitle: easyRsaPathMessage];
}

-(void) clearUtilitiesQuitAllOpenvpnStatusText: (NSTimer *) timer {

	(void) timer;
	
	[utilitiesQuitAllOpenvpnStatusTextTimer release];
	utilitiesQuitAllOpenvpnStatusTextTimer = nil;

	[[self utilitiesQuitAllOpenVpnStatusTFC] setTitle: @""];
}

-(void) setUtilitiesQuitAllOpenvpnStatusText: (NSString *) text {
	
	// Sets the status text, then (if it is not empty) clears it fives seconds later.
	
	[utilitiesQuitAllOpenVpnStatusTFC setTitle: text];
	
	[utilitiesQuitAllOpenvpnStatusTextTimer invalidate];
	[utilitiesQuitAllOpenvpnStatusTextTimer release];
	utilitiesQuitAllOpenvpnStatusTextTimer = nil;
	utilitiesQuitAllOpenvpnStatusTextTimer = [[NSTimer scheduledTimerWithTimeInterval: 5.0
																			   target: self
																			 selector: @selector(clearUtilitiesQuitAllOpenvpnStatusText:)
																			 userInfo: nil
																			  repeats: NO]
											  retain];
}

//***************************************************************************************************************
// Getters

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            utilitiesQuitAllOpenVpnButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,	   utilitiesQuitAllOpenVpnStatusTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextField *,		   utilitiesQuitAllOpenVpnStatusTF)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            consoleLogToClipboardButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSProgressIndicator *, consoleLogToClipboardProgressIndicator)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            utilitiesExportTunnelblickSetupButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSProgressIndicator *, utilitiesExportTunnelblickSetupProgressIndicator)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          utilitiesOpenUninstallInstructionsButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          utilitiesRunEasyRsaButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,   utilitiesEasyRsaPathTFC)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          utilitiesHelpButton)

@end
