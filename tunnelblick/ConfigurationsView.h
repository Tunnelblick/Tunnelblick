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

@interface ConfigurationsView : NSView
{    
    IBOutlet NSView              * leftSplitView;
    
    IBOutlet NSTableView         * leftNavTableView;
    IBOutlet NSTableColumn       * leftNavTableColumn;
    
    IBOutlet NSButton            * addConfigurationButton;
    IBOutlet NSButton            * removeConfigurationButton;
    IBOutlet NSPopUpButton       * workOnConfigurationPopUpButton;
    IBOutlet NSArrayController   * workOnConfigurationArrayController;
    
    IBOutlet NSMenuItem          * renameConfigurationMenuItem;
    IBOutlet NSMenuItem          * duplicateConfigurationMenuItem;
    IBOutlet NSMenuItem          * makePrivateOrSharedMenuItem;
    IBOutlet NSMenuItem          * showOnTunnelblickMenuMenuItem;
    IBOutlet NSMenuItem          * editOpenVPNConfigurationFileMenuItem;
    IBOutlet NSMenuItem          * showOpenvpnLogMenuItem;
    IBOutlet NSMenuItem          * removeCredentialsMenuItem;
    
    IBOutlet NSTextFieldCell     * configurationNameTFC;
    IBOutlet NSTextFieldCell     * configurationStatusTFC;
    
    IBOutlet NSButton            * configurationsHelpButton;
    IBOutlet NSButton            * disconnectButton;
    IBOutlet NSButton            * connectButton;
    
    IBOutlet NSTabView           * configurationsTabView;
    // Log tab
    
    IBOutlet NSTabViewItem       * logTabViewItem;
    IBOutlet NSTextView          * logView;
    
    IBOutlet NSProgressIndicator * progressIndicator;
    
    IBOutlet NSButton            * logToClipboardButton;
    
    // Settings tab
    
    IBOutlet NSTabViewItem       * settingsTabViewItem;
    
    IBOutlet NSTextFieldCell     * whenToConnectTFC;
    IBOutlet NSPopUpButton       * whenToConnectPopUpButton;
    IBOutlet NSMenuItem          * whenToConnectManuallyMenuItem;
    IBOutlet NSMenuItem          * whenToConnectTunnelblickLaunchMenuItem;
    IBOutlet NSMenuItem          * whenToConnectOnComputerStartMenuItem;
    
    IBOutlet NSTextField         * setNameserverTF;
    IBOutlet NSTextFieldCell     * setNameserverTFC;
    IBOutlet NSPopUpButton       * setNameserverPopUpButton;
    IBOutlet NSArrayController   * setNameserverArrayController;
    
    IBOutlet NSButton            * monitorNetworkForChangesCheckbox;
    
    IBOutlet NSBox               * alertSoundsBox;
    
    IBOutlet NSTextFieldCell     * connectionAlertSoundTFC;
    IBOutlet NSTextFieldCell     * disconnectionAlertSoundTFC;
    IBOutlet NSButton            * soundOnConnectButton;
    IBOutlet NSButton            * soundOnDisconnectButton;
    IBOutlet NSArrayController   * soundOnConnectArrayController;
    IBOutlet NSArrayController   * soundOnDisconnectArrayController;
    
    IBOutlet NSButton            * advancedButton;    
}

// Getters

TBPROPERTY_READONLY(NSView *,              leftSplitView)
TBPROPERTY_READONLY(NSTableView *,         leftNavTableView)
TBPROPERTY_READONLY(NSTableColumn *,       leftNavTableColumn)

TBPROPERTY_READONLY(NSButton *,            addConfigurationButton)
TBPROPERTY_READONLY(NSButton *,            removeConfigurationButton)
TBPROPERTY_READONLY(NSPopUpButton *,       workOnConfigurationPopUpButton)
TBPROPERTY_READONLY(NSArrayController *,   workOnConfigurationArrayController)

TBPROPERTY_READONLY(NSMenuItem *,          renameConfigurationMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          duplicateConfigurationMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          makePrivateOrSharedMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          showOnTunnelblickMenuMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          editOpenVPNConfigurationFileMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          showOpenvpnLogMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          removeCredentialsMenuItem)

TBPROPERTY_READONLY(NSTextFieldCell *,     configurationNameTFC)
TBPROPERTY_READONLY(NSTextFieldCell *,     configurationStatusTFC)

TBPROPERTY_READONLY(NSButton *,            configurationsHelpButton)
TBPROPERTY_READONLY(NSButton *,            disconnectButton)
TBPROPERTY_READONLY(NSButton *,            connectButton)

TBPROPERTY_READONLY(NSTabView *,           configurationsTabView)

TBPROPERTY_READONLY(NSTabViewItem *,       logTabViewItem)
TBPROPERTY_READONLY(NSTextView *,          logView)

TBPROPERTY_READONLY(NSProgressIndicator *, progressIndicator)
TBPROPERTY_READONLY(NSButton *,            logToClipboardButton)

TBPROPERTY_READONLY(NSTabViewItem *,       settingsTabViewItem)

TBPROPERTY_READONLY(NSTextFieldCell *,     whenToConnectTFC)
TBPROPERTY_READONLY(NSPopUpButton *,       whenToConnectPopUpButton)
TBPROPERTY_READONLY(NSMenuItem *,          whenToConnectManuallyMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          whenToConnectTunnelblickLaunchMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          whenToConnectOnComputerStartMenuItem)

TBPROPERTY_READONLY(NSMenuItem *,          setNameserverTF)
TBPROPERTY_READONLY(NSMenuItem *,          setNameserverTFC)
TBPROPERTY_READONLY(NSPopUpButton *,       setNameserverPopUpButton)
TBPROPERTY_READONLY(NSArrayController *,   setNameserverArrayController)

TBPROPERTY_READONLY(NSButton *,            monitorNetworkForChangesCheckbox)

TBPROPERTY_READONLY(NSBox *,               alertSoundsBox)

TBPROPERTY_READONLY(NSTextFieldCell *,     connectionAlertSoundTFC)
TBPROPERTY_READONLY(NSTextFieldCell *,     disconnectionAlertSoundTFC)
TBPROPERTY_READONLY(NSButton *,            soundOnConnectButton)
TBPROPERTY_READONLY(NSButton *,            soundOnDisconnectButton)
TBPROPERTY_READONLY(NSArrayController *,   soundOnConnectArrayController)
TBPROPERTY_READONLY(NSArrayController *,   soundOnDisconnectArrayController)

TBPROPERTY_READONLY(NSButton *,            advancedButton)

@end
