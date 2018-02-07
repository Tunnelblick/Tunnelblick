/*
 * Copyright 2011, 2012, 2013, 2015, 2017, 2018 Jonathan K. Bullard. All rights reserved.
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

@class TBButton;

@interface UtilitiesView : NSView {

    IBOutlet TBButton            * utilitiesKillAllOpenVpnButton;
	IBOutlet NSProgressIndicator * killAllOpenVPNProgressIndicator;
    
    IBOutlet TBButton            * consoleLogToClipboardButton;
	IBOutlet NSProgressIndicator * consoleLogToClipboardProgressIndicator;

    IBOutlet TBButton           * utilitiesOpenUninstallInstructionsButton;
	
    IBOutlet TBButton           * utilitiesRunEasyRsaButton;
    IBOutlet NSTextFieldCell    * utilitiesEasyRsaPathTFC;
 
    IBOutlet NSButton           * utilitiesHelpButton;
}

TBPROPERTY_READONLY(TBButton *,            utilitiesKillAllOpenVpnButton)
TBPROPERTY_READONLY(NSProgressIndicator *, killAllOpenVPNProgressIndicator)

TBPROPERTY_READONLY(TBButton *,            consoleLogToClipboardButton)
TBPROPERTY_READONLY(NSProgressIndicator *, consoleLogToClipboardProgressIndicator)

TBPROPERTY_READONLY(TBButton *,        utilitiesOpenUninstallInstructionsButton)

TBPROPERTY_READONLY(TBButton *,        utilitiesRunEasyRsaButton)

TBPROPERTY_READONLY(NSButton *,        utilitiesHelpButton)

@end
