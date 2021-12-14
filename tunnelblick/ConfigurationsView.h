/*
 * Copyright 2011, 2012, 2013, 2014, 2015, 2016, 2017 Jonathan K. Bullard. All rights reserved.
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
@class TBButton;
@class TBPopUpButton;

@interface ConfigurationsView : NSView
{    
    IBOutlet NSView              * leftSplitView;
    
    IBOutlet LeftNavViewController * outlineViewController; // Used only Preferences and Preferences-RTL -- that is, only when
    IBOutlet LeftNavDataSource   * leftNavDataSrc;			//      [UIHelper useOutlineViewOfConfigurations]

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

    IBOutlet NSMenuItem          * c_o_p_yConfigurationsIntoNewFolderMenuItem;
    IBOutlet NSMenuItem          * moveConfigurationsIntoNewFolderMenuItem;

    IBOutlet NSMenuItem          * showOnTbMenuMenuItem;
    IBOutlet NSMenuItem          * doNotShowOnTbMenuMenuItem;

    IBOutlet NSMenuItem          * editOpenVPNConfigurationFileMenuItem;
    IBOutlet NSMenuItem          * showOpenvpnLogMenuItem;
    IBOutlet NSMenuItem          * removeCredentialsMenuItem;
    
    IBOutlet NSButton            * configurationsHelpButton;
	
    IBOutlet TBButton            * diagnosticInfoToClipboardButton;
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
    IBOutlet TBPopUpButton       * whenToConnectPopUpButton;
    IBOutlet NSMenuItem          * whenToConnectManuallyMenuItem;
    IBOutlet NSMenuItem          * whenToConnectTunnelBlickLaunchMenuItem;
    IBOutlet NSMenuItem          * whenToConnectOnComputerStartMenuItem;
    
    IBOutlet NSTextField         * setNameserverTF;
    IBOutlet NSTextFieldCell     * setNameserverTFC;
    IBOutlet TBPopUpButton       * setNameserverPopUpButton;
    IBOutlet NSArrayController   * setNameserverArrayController;
    
    IBOutlet NSTextField        * perConfigOpenvpnVersionTF;
    IBOutlet NSTextFieldCell    * perConfigOpenvpnVersionTFC;
    IBOutlet NSArrayController  * perConfigOpenvpnVersionArrayController;
    IBOutlet TBPopUpButton      * perConfigOpenvpnVersionButton;
   
    IBOutlet NSTextField         * loggingLevelTF;
    IBOutlet NSTextFieldCell     * loggingLevelTFC;
    IBOutlet TBPopUpButton       * loggingLevelPopUpButton;
    IBOutlet NSArrayController   * loggingLevelArrayController;
    
	IBOutlet NSTextField		 * uponDisconnectTF;
	IBOutlet NSTextFieldCell     * uponDisconnectTFC;
	IBOutlet TBPopUpButton       * uponDisconnectPopUpButton;
	IBOutlet NSMenuItem          * uponDisconnectDoNothingMenuItem;
	IBOutlet NSMenuItem          * uponDisconnectResetPrimaryInterfaceMenuItem;
	IBOutlet NSMenuItem          * uponDisconnectDisableNetworkAccessMenuItem;
	
	IBOutlet NSTextField		 * uponUnexpectedDisconnectTF;
	IBOutlet NSTextFieldCell     * uponUnexpectedDisconnectTFC;
	IBOutlet TBPopUpButton       * uponUnexpectedDisconnectPopUpButton;
	IBOutlet NSMenuItem          * uponUnexpectedDisconnectDoNothingMenuItem;
	IBOutlet NSMenuItem          * uponUnexpectedDisconnectResetPrimaryInterfaceMenuItem;
	IBOutlet NSMenuItem          * uponUnexpectedDisconnectDisableNetworkAccessMenuItem;
	
    IBOutlet TBButton            * monitorNetworkForChangesCheckbox;
    IBOutlet TBButton            * routeAllTrafficThroughVpnCheckbox;
	IBOutlet TBButton            * disableIpv6OnTunCheckbox;
    IBOutlet TBButton            * disableSecondaryNetworkServicesCheckbox;
    IBOutlet TBButton            * checkIPAddressAfterConnectOnAdvancedCheckbox;
	
    IBOutlet TBButton            * advancedButton;
}

// Getters

TBPROPERTY_READONLY(NSView *,              leftSplitView)

TBPROPERTY_READONLY(LeftNavViewController *, outlineViewController)
TBPROPERTY_READONLY(LeftNavDataSource *,   leftNavDataSrc)

TBPROPERTY_READONLY(NSTextFieldCell *,     leftNavTableTFC)

TBPROPERTY_READONLY(NSButton *,            addConfigurationButton)
TBPROPERTY_READONLY(NSButton *,            removeConfigurationButton)
TBPROPERTY_READONLY(NSPopUpButton *,       workOnConfigurationPopUpButton)
TBPROPERTY_READONLY(NSArrayController *,   workOnConfigurationArrayController)

TBPROPERTY_READONLY(NSMenuItem *,          c_o_p_yConfigurationsIntoNewFolderMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          moveConfigurationsIntoNewFolderMenuItem)
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
TBPROPERTY_READONLY(TBButton *,            diagnosticInfoToClipboardButton)
TBPROPERTY_READONLY(NSProgressIndicator *, diagnosticInfoToClipboardProgressIndicator)
TBPROPERTY_READONLY(NSButton *,            connectButton)

TBPROPERTY_READONLY(NSTabView *,           configurationsTabView)

TBPROPERTY_READONLY(NSTabViewItem *,       logTabViewItem)
TBPROPERTY_READONLY(NSTextView *,          logView)

TBPROPERTY_READONLY(NSProgressIndicator *, logDisplayProgressIndicator)

TBPROPERTY_READONLY(NSTabViewItem *,       settingsTabViewItem)

TBPROPERTY_READONLY(NSTextFieldCell *,     whenToConnectTFC)
TBPROPERTY_READONLY(TBPopUpButton *,       whenToConnectPopUpButton)
TBPROPERTY_READONLY(NSMenuItem *,          whenToConnectManuallyMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          whenToConnectTunnelBlickLaunchMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          whenToConnectOnComputerStartMenuItem)

TBPROPERTY_READONLY(NSTextField *,         setNameserverTF)
TBPROPERTY_READONLY(NSTextFieldCell *,     setNameserverTFC)
TBPROPERTY_READONLY(TBPopUpButton *,       setNameserverPopUpButton)
TBPROPERTY_READONLY(NSArrayController *,   setNameserverArrayController)

TBPROPERTY_READONLY(NSTextFieldCell *,     uponDisconnectTFC)
TBPROPERTY_READONLY(TBPopUpButton *,       uponDisconnectPopUpButton)
TBPROPERTY_READONLY(NSMenuItem *,          uponDisconnectDoNothingMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          uponDisconnectResetPrimaryInterfaceMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          uponDisconnectDisableNetworkAccessMenuItem)

TBPROPERTY_READONLY(NSTextFieldCell *,     uponUnexpectedDisconnectTFC)
TBPROPERTY_READONLY(TBPopUpButton *,       uponUnexpectedDisconnectPopUpButton)
TBPROPERTY_READONLY(NSMenuItem *,          uponUnexpectedDisconnectDoNothingMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          uponUnexpectedDisconnectResetPrimaryInterfaceMenuItem)
TBPROPERTY_READONLY(NSMenuItem *,          uponUnexpectedDisconnectDisableNetworkAccessMenuItem)

TBPROPERTY_READONLY(TBButton *,            monitorNetworkForChangesCheckbox)
TBPROPERTY_READONLY(TBButton *,            routeAllTrafficThroughVpnCheckbox)
TBPROPERTY_READONLY(TBButton *,            disableIpv6OnTunCheckbox)
TBPROPERTY_READONLY(TBButton *,            disableSecondaryNetworkServicesCheckbox)
TBPROPERTY_READONLY(TBButton *,            checkIPAddressAfterConnectOnAdvancedCheckbox)

TBPROPERTY_READONLY(NSArrayController *,   perConfigOpenvpnVersionArrayController)
TBPROPERTY_READONLY(TBPopUpButton *,       perConfigOpenvpnVersionButton)

TBPROPERTY_READONLY(NSTextField *,         loggingLevelTF)
TBPROPERTY_READONLY(NSTextFieldCell *,     loggingLevelTFC)
TBPROPERTY_READONLY(TBPopUpButton *,       loggingLevelPopUpButton)
TBPROPERTY_READONLY(NSArrayController *,   loggingLevelArrayController)

TBPROPERTY_READONLY(TBButton *,            advancedButton)

@end
