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


#import <Cocoa/Cocoa.h>
#import "defines.h"

@interface GeneralView : NSView {
    
    IBOutlet NSTextFieldCell    * keyboardShortcutTFC;
    IBOutlet NSTextField        * keyboardShortcutTF;
    IBOutlet NSArrayController  * keyboardShortcutArrayController;
    IBOutlet NSButton           * keyboardShortcutButton;
    
    IBOutlet NSTextFieldCell    * openvpnVersionTFC;
    IBOutlet NSTextField        * openvpnVersionTF;
    IBOutlet NSArrayController  * openvpnVersionArrayController;
    IBOutlet NSButton           * openvpnVersionButton;
    
    IBOutlet NSTextFieldCell    * maxLogDisplaySizeTFC;
    IBOutlet NSTextField        * maxLogDisplaySizeTF;
    IBOutlet NSArrayController  * maximumLogSizeArrayController;
    IBOutlet NSButton           * maximumLogSizeButton;
    
    IBOutlet NSTextFieldCell    * warningsTFC;
    IBOutlet NSTextField        * warningsTF;
    IBOutlet NSButton           * resetDisabledWarningsButton;
    
    IBOutlet NSTextField        * configurationFilesTF;
    IBOutlet NSTextFieldCell    * configurationFilesTFC;
    IBOutlet NSButton           * monitorConfigurationFolderCheckbox;
    
    IBOutlet NSTextFieldCell    * updatesUpdatesTFC;
    IBOutlet NSButton           * updatesCheckAutomaticallyCheckbox;
    IBOutlet NSButton           * updatesCheckNowButton;
    IBOutlet NSTextFieldCell    * updatesLastCheckedTFC;
    
    IBOutlet NSButton           * preferencesGeneralHelpButton;
}

TBPROPERTY_READONLY(NSButton *,          monitorConfigurationFolderCheckbox)

TBPROPERTY_READONLY(NSButton *,          updatesCheckAutomaticallyCheckbox)
TBPROPERTY_READONLY(NSTextFieldCell *,   updatesLastCheckedTFC)

TBPROPERTY_READONLY(NSArrayController *, openvpnVersionArrayController)
TBPROPERTY_READONLY(NSButton *,          openvpnVersionButton)

TBPROPERTY_READONLY(NSArrayController *, keyboardShortcutArrayController)
TBPROPERTY_READONLY(NSButton *,          keyboardShortcutButton)

TBPROPERTY_READONLY(NSArrayController *, maximumLogSizeArrayController)
TBPROPERTY_READONLY(NSButton *,          maximumLogSizeButton)

@end
