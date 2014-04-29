/*
 * Copyright 2011, 2012, 2013, 2014 Jonathan K. Bullard. All rights reserved.
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

typedef enum {
	sharedConfiguration,
    privateConfiguration,
    deployedConfiguration
} ConfigurationType;


@class VPNConnection;


@interface SettingsSheetWindowController : NSWindowController <NSWindowDelegate>
{
    NSString                     * configurationName;
    
    VPNConnection                * connection;
    
    ConfigurationType              configurationType;
    
    BOOL                           showingSettingsSheet;
    
    BOOL                           doNotModifyPreferences;  // Flag used to set PopUpButtons without modifying the preferences they represent
    
    //*****************************************************************************
    
    IBOutlet NSWindow            * settingsSheet;
    
    IBOutlet NSTabView           * tabView;
    
    IBOutlet NSTabViewItem       * connectingAndDisconnectingTabViewItem;
    IBOutlet NSTabViewItem       * whileConnectedTabViewItem;
    IBOutlet NSTabViewItem       * credentialsTabViewItem;
    
    IBOutlet NSTextFieldCell     * configurationNameTFC;
    IBOutlet NSTextFieldCell     * configurationStatusTFC;
    
    
    // For Connecting & Disconnecting tab
    
    IBOutlet NSButton            * checkIPAddressAfterConnectOnAdvancedCheckbox;
    IBOutlet NSButton            * showOnTunnelBlickMenuCheckbox;
    IBOutlet NSButton            * flushDnsCacheCheckbox;
    IBOutlet NSButton            * prependDomainNameCheckbox;
    IBOutlet NSButton            * disconnectOnSleepCheckbox;
    IBOutlet NSButton            * reconnectOnWakeFromSleepCheckbox;
    IBOutlet NSButton            * resetPrimaryInterfaceAfterDisconnectCheckbox;
    
    IBOutlet NSButton            * connectingHelpButton;
    
    IBOutlet NSButton            * disconnectWhenUserSwitchesOutCheckbox;
    IBOutlet NSButton            * reconnectWhenUserSwitchesInCheckbox;
    
    IBOutlet NSTextFieldCell     * ifConnectedWhenUserSwitchedOutTFC;
    IBOutlet NSTextField         * ifConnectedWhenUserSwitchedOutTF;
    
    IBOutlet NSBox               * fastUserSwitchingBox;
    
	IBOutlet NSPopUpButton	     * loadTunPopUpButton;
	IBOutlet NSMenuItem          * loadTunAutomaticallyMenuItem;
	IBOutlet NSMenuItem          * loadTunAlwaysMenuItem;
	IBOutlet NSMenuItem          * loadTunNeverMenuItem;
	
	IBOutlet NSPopUpButton       * loadTapPopUpButton;
	IBOutlet NSMenuItem          * loadTapAutomaticallyMenuItem;
	IBOutlet NSMenuItem          * loadTapAlwaysMenuItem;
	IBOutlet NSMenuItem          * loadTapNeverMenuItem;
    
    // For WhileConnected tab
    
    IBOutlet NSButton            * routeAllTrafficThroughVpnCheckbox;
    IBOutlet NSButton            * runMtuTestCheckbox;
    IBOutlet NSButton            * monitorNetworkForChangesCheckbox;
    
    IBOutlet NSBox               * DnsWinsBox;
    
    // For WhileConnected tab -- When changes to pre-VPN settings
    
    IBOutlet NSButton            * whileConnectedHelpButton;
    
    
    IBOutlet NSTextFieldCell     * networkSettingTFC;
    IBOutlet NSTextFieldCell     * whenChangesToPreVpnValueTFC;
    IBOutlet NSTextFieldCell     * whenChangesToAnythingElseTFC;
    IBOutlet NSTextField         * networkSettingTF;
    IBOutlet NSTextField         * whenChangesToPreVpnValueTF;
    IBOutlet NSTextField         * whenChangesToAnythingElseTF;
    
    IBOutlet NSPopUpButton       * dnsServersPopUpButton;
    IBOutlet NSPopUpButton       * domainPopUpButton;
    IBOutlet NSPopUpButton       * searchDomainPopUpButton;
    IBOutlet NSPopUpButton       * winsServersPopUpButton;
    IBOutlet NSPopUpButton       * netBiosNamePopUpButton;
    IBOutlet NSPopUpButton       * workgroupPopUpButton;
    
    IBOutlet NSPopUpButton       * otherdnsServersPopUpButton;
    IBOutlet NSPopUpButton       * otherdomainPopUpButton;
    IBOutlet NSPopUpButton       * othersearchDomainPopUpButton;
    IBOutlet NSPopUpButton       * otherwinsServersPopUpButton;
    IBOutlet NSPopUpButton       * othernetBiosNamePopUpButton;
    IBOutlet NSPopUpButton       * otherworkgroupPopUpButton;
    
    IBOutlet NSArrayController   * dnsServersArrayController;
    IBOutlet NSArrayController   * domainArrayController;
    IBOutlet NSArrayController   * searchDomainArrayController;
    IBOutlet NSArrayController   * winsServersArrayController;
    IBOutlet NSArrayController   * netBiosNameArrayController;
    IBOutlet NSArrayController   * workgroupArrayController;
    
    IBOutlet NSArrayController   * otherdnsServersArrayController;
    IBOutlet NSArrayController   * otherdomainArrayController;
    IBOutlet NSArrayController   * othersearchDomainArrayController;
    IBOutlet NSArrayController   * otherwinsServersArrayController;
    IBOutlet NSArrayController   * othernetBiosNameArrayController;
    IBOutlet NSArrayController   * otherworkgroupArrayController;
    
    IBOutlet NSInteger             selectedDnsServersIndex;
    IBOutlet NSInteger             selectedDomainIndex;
    IBOutlet NSInteger             selectedSearchDomainIndex;
    IBOutlet NSInteger             selectedWinsServersIndex;
    IBOutlet NSInteger             selectedNetBiosNameIndex;
    IBOutlet NSInteger             selectedWorkgroupIndex;
    
    IBOutlet NSInteger             selectedOtherdnsServersIndex;
    IBOutlet NSInteger             selectedOtherdomainIndex;
    IBOutlet NSInteger             selectedOthersearchDomainIndex;
    IBOutlet NSInteger             selectedOtherwinsServersIndex;
    IBOutlet NSInteger             selectedOthernetBiosNameIndex;
    IBOutlet NSInteger             selectedOtherworkgroupIndex;
    
    IBOutlet NSTextFieldCell     * dnsServersTFC;
    IBOutlet NSTextFieldCell     * domainTFC;
    IBOutlet NSTextFieldCell     * searchDomainTFC;
    IBOutlet NSTextFieldCell     * winsServersTFC;
    IBOutlet NSTextFieldCell     * netBiosNameTFC;
    IBOutlet NSTextFieldCell     * workgroupTFC;
    
    
    // For Credentials tab
	
    IBOutlet NSButton            * allConfigurationsUseTheSameCredentialsCheckbox;
	
	IBOutlet NSBox               * namedCredentialsBox;
    
    IBOutlet NSButton            * credentialsGroupButton;
    IBOutlet NSArrayController   * credentialsGroupArrayController;
	IBOutlet NSInteger             selectedCredentialsGroupIndex;
	
	IBOutlet NSButton            * addNamedCredentialsButton;
	
	IBOutlet NSButton            * removeNamedCredentialsButton;
    NSArray                      * removeNamedCredentialsNames;
}

// General methods

-(void) setConfigurationName: (NSString *) newName;
-(void) setStatus:            (NSString *) newStatus;
-(void) updateConnectionStatusAndTime;

-(void) showSettingsSheet:    (id) sender;
-(void) endSettingsSheet:     (id) sender;

-(void) monitorNetworkForChangesCheckboxChangedForConnection: (VPNConnection *) theConnection;

-(void) setupSettingsFromPreferences;

// Methods for Connecting tab

-(IBAction) checkIPAddressAfterConnectOnAdvancedCheckboxWasClicked: (id) sender;
-(IBAction) showOnTunnelBlickMenuCheckboxWasClicked:          (id) sender;
-(IBAction) flushDnsCacheCheckboxWasClicked:                  (id) sender;
-(IBAction) prependDomainNameCheckboxWasClicked:              (id) sender;
-(IBAction) disconnectOnSleepCheckboxWasClicked:              (id) sender;
-(IBAction) reconnectOnWakeFromSleepCheckboxWasClicked:       (id) sender;
-(IBAction) resetPrimaryInterfaceAfterDisconnectCheckboxWasClicked:   (id) sender;
-(IBAction) routeAllTrafficThroughVpnCheckboxWasClicked:      (id) sender;
-(IBAction) runMtuTestCheckboxWasClicked:                     (id) sender;
-(IBAction) connectingHelpButtonWasClicked:                   (id) sender;

-(IBAction) disconnectWhenUserSwitchesOutCheckboxWasClicked:  (id) sender;
-(IBAction) reconnectWhenUserSwitchesInCheckboxWasClicked:    (id) sender;

-(IBAction) loadTunAutomaticallyMenuItemWasClicked: (id) sender;
-(IBAction) loadTapAutomaticallyMenuItemWasClicked: (id)sender;
-(IBAction) loadTunNeverMenuItemWasClicked:         (id)sender;
-(IBAction) loadTapNeverMenuItemWasClicked:         (id)sender;
-(IBAction) loadTunAlwaysMenuItemWasClicked:        (id)sender;
-(IBAction) loadTapAlwaysMenuItemWasClicked:        (id)sender;
    

// Methods for While Connected tab

-(IBAction)  monitorNetworkForChangesCheckboxWasClicked: (id) sender;

-(IBAction)  whileConnectedHelpButtonWasClicked: (id) sender;

-(NSInteger) selectedDnsServersIndex;
-(void)      setSelectedDnsServersIndex:   (NSInteger) newValue;

-(NSInteger) selectedDomainIndex;
-(void)      setSelectedDomainIndex:       (NSInteger) newValue;

-(NSInteger) selectedSearchDomainIndex;
-(void)      setSelectedSearchDomainIndex: (NSInteger) newValue;

-(NSInteger) selectedWinsServersIndex;
-(void)      setSelectedWinsServersIndex:  (NSInteger) newValue;

-(NSInteger) selectedNetBiosNameIndex;
-(void)      setSelectedNetBiosNameIndex:  (NSInteger) newValue;

-(NSInteger) selectedWorkgroupIndex;
-(void)      setSelectedWorkgroupIndex:    (NSInteger) newValue;

-(NSInteger) selectedOtherdnsServersIndex;
-(void)      setSelectedOtherdnsServersIndex:   (NSInteger) newValue;

-(NSInteger) selectedOtherdomainIndex;
-(void)      setSelectedOtherdomainIndex:       (NSInteger) newValue;

-(NSInteger) selectedOthersearchDomainIndex;
-(void)      setSelectedOthersearchDomainIndex: (NSInteger) newValue;

-(NSInteger) selectedOtherwinsServersIndex;
-(void)      setSelectedOtherwinsServersIndex:  (NSInteger) newValue;

-(NSInteger) selectedOthernetBiosNameIndex;
-(void)      setSelectedOthernetBiosNameIndex:  (NSInteger) newValue;

-(NSInteger) selectedOtherworkgroupIndex;
-(void)      setSelectedOtherworkgroupIndex:    (NSInteger) newValue;


// Methods for Credentials tab

-(IBAction) allConfigurationsUseTheSameCredentialsCheckboxWasClicked: (id) sender;

-(IBAction) addNamedCredentialsButtonWasClicked: (id) sender;

-(IBAction) vpnCredentialsHelpButtonWasClicked: (id) sender;


// Getters & Setters

TBPROPERTY_READONLY(NSButton *, allConfigurationsUseTheSameCredentialsCheckbox)

TBPROPERTY_READONLY(NSBox *, namedCredentialsBox)

TBPROPERTY_READONLY(NSButton *, removeNamedCredentialsButton)
TBPROPERTY(NSArray *,           removeNamedCredentialsNames, setRemoveNamedCredentialsNames)

TBPROPERTY_READONLY(NSButton *,            credentialsGroupButton)
TBPROPERTY_READONLY(NSArrayController *,   credentialsGroupArrayController)
TBPROPERTY(NSUInteger, selectedCredentialsGroupIndex,    setSelectedCredentialsGroupIndex)

TBPROPERTY_READONLY(NSButton *, addNamedCredentialsButton)

TBPROPERTY_READONLY(NSTabViewItem *, connectingAndDisconnectingTabViewItem)
TBPROPERTY_READONLY(NSTabViewItem *, whileConnectedTabViewItem)
TBPROPERTY_READONLY(NSTabViewItem *, credentialsTabViewItem)
TBPROPERTY(VPNConnection *, connection, setConnection)

@end
