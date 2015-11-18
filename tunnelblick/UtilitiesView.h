/*
 * Copyright 2011, 2012, 2013, 2015 Jonathan K. Bullard. All rights reserved.
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

@interface UtilitiesView : NSView {

    IBOutlet NSButton           * utilitiesKillAllOpenVpnButton;
    
    IBOutlet NSButton           * consoleLogToClipboardButton;
	IBOutlet NSProgressIndicator * consoleLogToClipboardProgressIndicator;

    IBOutlet NSButton           * utilitiesOpenUninstallInstructionsButton;
	
    IBOutlet NSButton           * utilitiesRunEasyRsaButton;
    IBOutlet NSTextFieldCell    * utilitiesEasyRsaPathTFC;
 
    IBOutlet NSButton           * utilitiesHelpButton;
}

TBPROPERTY_READONLY(NSButton *,        utilitiesKillAllOpenVpnButton)

TBPROPERTY_READONLY(NSButton *,        consoleLogToClipboardButton)
TBPROPERTY_READONLY(NSProgressIndicator *, consoleLogToClipboardProgressIndicator)

TBPROPERTY_READONLY(NSButton *,        utilitiesOpenUninstallInstructionsButton)

TBPROPERTY_READONLY(NSButton *,        utilitiesRunEasyRsaButton)

TBPROPERTY_READONLY(NSButton *,        utilitiesHelpButton)

@end
