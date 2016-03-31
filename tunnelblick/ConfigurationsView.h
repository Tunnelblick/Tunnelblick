/*
 * Copyright 2011, 2012, 2013, 2014, 2015, 2016 Jonathan K. Bullard. All rights reserved.
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

@class LeftNavViewController;
@class LeftNavDataSource;

@interface ConfigurationsView : NSView
{    
    IBOutlet NSView              * leftSplitView;
    
    IBOutlet LeftNavViewController * outlineViewController; // Used only Preferences and Preferences-RTL -- that is, only when
    IBOutlet LeftNavDataSource   * leftNavDataSrc;			//      [UIHelper useOutlineViewOfConfigurations]

	IBOutlet NSTableView         * leftNavTableView;        // Used only in Preferences-Tiger and Preferences-Tiger-RTL
	IBOutlet NSTableColumn       * leftNavTableColumn;      // -- that is, only when ! [UIHelper useOutlineViewOfConfigurations]
	
	IBOutlet NSTextFieldCell     * leftNavTableTFC;			// Cell used for all table entries; aligned right for RTL languages
	
    IBOutlet NSButton            * addConfigurationButton;
    IBOutlet NSButton            * removeConfigurationButton;
    IBOutlet NSPopUpButton       * workOnConfigurationPopUpButton;
    IBOutlet NSArrayController   * workOnConfigurationArrayController;
    
    IBOutlet NSMenuItem          * renameConfigurationMenuItem;
    IBOutlet NSMenuItem          * duplicateConfigurationMenuItem;
    IBOutlet NSMenuItem          * makePrivateMenuItem;
    IBOutlet NSMenuItem          * makeSharedMenuItem;
	IBOutlet NSMenuItem          * revertToShadowMenuItem;

    IBOutlet NSMenuItem          * showOnTbMenuMenuItem;
    IBOutlet NSMenuItem          * doNotShowOnTbMenuMenuItem;

    IBOutlet NSMenuItem          * editOpenVPNConfigurationFileMenuItem;
    IBOutlet NSMenuItem          * showOpenvpnLogMenuItem;
    IBOutlet NSMenuItem          * removeCredentialsMenuItem;
    
    IBOutlet NSButton            * configurationsHelpButton;
	
    IBOutlet NSButton            * diagnosticInfoToClipboardButton;
    IBOutlet NSProgressIndicator * diagnosticInfoToClipboardProgressIndicator;
    
    IBOutlet NSButton            * disconnectButton;
    IBOutlet NSButton            * connectButton;
    
    IBOutlet NSTabView           * configurationsTabView;
	
    // Log tab
    
    IBOutlet NSTabViewItem       * logTabViewItem;
    IBOutlet NSTextView          * logView;
    
    IBOutlet NSProgressIndicator * logDisplayProgressIndicator;
    
    // Settings tab
    
    IBOutlet NSTabViewItem       * settingsTabViewItem;
    
	IBOutlet NSTextField		 * whenToConnectTF;
    IBOutlet NSTextFieldCell     * whenToConnectTFC;
    IBOutlet NSPopUpButton       * whenToConnectPopUpButton;
    IBOutlet NSMenuItem          * whenToConnectManuallyMenuItem;
    IBOutlet NSMenuItem          * whenToConnectTunnelBlickLaunchMenuItem;
    IBOutlet NSMenuItem          * whenToConnectOnComputerStartMenuItem;
    
    IBOutlet NSTextField         * setNameserverTF;
    IBOutlet NSTextFieldCell     * setNameserverTFC;
    IBOutlet NSPopUpButton       * setNameserverPopUpButton;
    IBOutlet NSArrayController   * setNameserverArrayController;
    
    IBOutlet NSTextField        * perConfigOpenvpnVersionTF;
    IBOutlet NSTextFieldCell    * perConfigOpenvpnVersionTFC;
    IBOutlet NSArrayController  * perConfigOpenvpnVersionArrayController;
    IBOutlet NSButton           * perConfigOpenvpnVersionButton;
   
    IBOutlet NSTextField         * loggingLevelTF;
    IBOutlet NSTextFieldCell     * loggingLevelTFC;
    IBOutlet NSPopUpButton       * loggingLevelPopUpButton;
    IBOutlet NSArrayController   * loggingLevelArrayController;
    
    IBOutlet NSButton            * monitorNetworkForChangesCheckbox;
    IBOutlet NSButton            * routeAllTrafficThroughVpnCheckbox;
    IBOutlet NSButton            * checkIPAddressAfterConnectOnAdvancedCheckbox;
    IBOutlet NSButton            * resetPrimaryInterfaceAfterDisconnectCheckbox;
    IBOutlet NSButton            * disableIpv6OnTunCheckbox;
    
    IBOutlet NSButton            * advancedButton;    
}

// Getters

TBPROPERTY_READONLY(NSView *,              leftSplitView)

TBPROPERTY_READONLY(LeftNavViewController *, outlineViewController)
TBPROPERTY_READONLY(LeftNavDataSource *,   leftNavDataSrc)

TBPROPERTY_READONLY(NSTableView *,         leftNavTableView)
TBPROPERTY_READONLY(NSTableColumn *,       leftNavTableColumn)

TBPROPERTY_READONLY(NSTextFieldCell *,     leftNavTableTFC)

TBPROPERTY_READONLY(NSButton *,            addConfigurationButton)
TBPROPERTY_READONLY(NSButton *,            removeConfigurationButton)
TBPROPERTY_READONLY(NSPopUpButton *,       workOnConfigurationPopUpButton)
TBPROPERTY_READONLY(NSArrayController *,   workOnConfigurationArrayController)

TBPROPERTY_READONLY(NSMenuItem *,          renameConfigurationMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          duplicateConfigurationMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          makePrivateMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          makeSharedMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          revertToShadowMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          showOnTbMenuMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          doNotShowOnTbMenuMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          editOpenVPNConfigurationFileMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          showOpenvpnLogMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          removeCredentialsMenuItem)

TBPROPERTY_READONLY(NSButton *,            configurationsHelpButton)
TBPROPERTY_READONLY(NSButton *,            disconnectButton)
TBPROPERTY_READONLY(NSButton *,            diagnosticInfoToClipboardButton)
TBPROPERTY_READONLY(NSProgressIndicator *, diagnosticInfoToClipboardProgressIndicator)
TBPROPERTY_READONLY(NSButton *,            connectButton)

TBPROPERTY_READONLY(NSTabView *,           configurationsTabView)

TBPROPERTY_READONLY(NSTabViewItem *,       logTabViewItem)
TBPROPERTY_READONLY(NSTextView *,          logView)

TBPROPERTY_READONLY(NSProgressIndicator *, logDisplayProgressIndicator)

TBPROPERTY_READONLY(NSTabViewItem *,       settingsTabViewItem)

TBPROPERTY_READONLY(NSTextFieldCell *,     whenToConnectTFC)
TBPROPERTY_READONLY(NSPopUpButton *,       whenToConnectPopUpButton)
TBPROPERTY_READONLY(NSMenuItem *,          whenToConnectManuallyMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          whenToConnectTunnelBlickLaunchMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          whenToConnectOnComputerStartMenuItem)

TBPROPERTY_READONLY(NSTextField *,         setNameserverTF)
TBPROPERTY_READONLY(NSTextFieldCell *,     setNameserverTFC)
TBPROPERTY_READONLY(NSPopUpButton *,       setNameserverPopUpButton)
TBPROPERTY_READONLY(NSArrayController *,   setNameserverArrayController)

TBPROPERTY_READONLY(NSButton *,            monitorNetworkForChangesCheckbox)
TBPROPERTY_READONLY(NSButton *,            routeAllTrafficThroughVpnCheckbox)
TBPROPERTY_READONLY(NSButton *,            checkIPAddressAfterConnectOnAdvancedCheckbox)
TBPROPERTY_READONLY(NSButton *,            resetPrimaryInterfaceAfterDisconnectCheckbox)
TBPROPERTY_READONLY(NSButton *,            disableIpv6OnTunCheckbox)

TBPROPERTY_READONLY(NSArrayController *,   perConfigOpenvpnVersionArrayController)
TBPROPERTY_READONLY(NSButton *,            perConfigOpenvpnVersionButton)

TBPROPERTY_READONLY(NSTextField *,         loggingLevelTF)
TBPROPERTY_READONLY(NSTextFieldCell *,     loggingLevelTFC)
TBPROPERTY_READONLY(NSPopUpButton *,       loggingLevelPopUpButton)
TBPROPERTY_READONLY(NSArrayController *,   loggingLevelArrayController)

TBPROPERTY_READONLY(NSButton *,            advancedButton)

@end
