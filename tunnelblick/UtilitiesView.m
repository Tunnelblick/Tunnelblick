/*
 * Copyright 2011, 2012, 2013, 2014, 2015 Jonathan K. Bullard. All rights reserved.
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

#import "NSFileManager+TB.h"
#import "TBUserDefaults.h"
#import "UIHelper.h"

extern NSFileManager  * gFileMgr;
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

-(void) awakeFromNib
{
    BOOL rtl = [UIHelper languageAtLaunchWasRTL];
    
    [UIHelper setTitle: NSLocalizedString(@"Quit All OpenVPN Processes"            , @"Button") ofControl: utilitiesKillAllOpenVpnButton            shift: rtl narrow: YES enable: YES];
    [UIHelper setTitle: NSLocalizedString(@"Copy Console Log to Clipboard"         , @"Button") ofControl: consoleLogToClipboardButton              shift: rtl narrow: YES enable: ALLOW_OPENVPNSTART_KILLALL];
    [UIHelper setTitle: NSLocalizedString(@"Open Uninstall Instructions in Browser", @"Button") ofControl: utilitiesOpenUninstallInstructionsButton shift: rtl narrow: YES enable: YES];
    [UIHelper setTitle: NSLocalizedString(@"Open easy-rsa in Terminal"             , @"Button") ofControl: utilitiesRunEasyRsaButton                shift: rtl narrow: YES enable: YES];
    
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

//***************************************************************************************************************
// Getters

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          utilitiesKillAllOpenVpnButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          consoleLogToClipboardButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSProgressIndicator *, consoleLogToClipboardProgressIndicator)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          utilitiesOpenUninstallInstructionsButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          utilitiesRunEasyRsaButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,   utilitiesEasyRsaPathTFC)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          utilitiesHelpButton)

@end
