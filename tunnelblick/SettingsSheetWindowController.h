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

typedef enum {
	sharedConfiguration,
    privateConfiguration,
    deployedConfiguration
} ConfigurationType;


@class VPNConnection;
@class TBButton;
@class TBPopUpButton;


@interface SettingsSheetWindowController : NSWindowController <NSWindowDelegate, NSTextFieldDelegate>
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
    IBOutlet NSTabViewItem       * soundTabViewItem;
    
    BOOL                           doNotPlaySounds;                  // Used to inhibit playing sounds while switching configurations
    
    
    // For Connecting & Disconnecting tab
    
    IBOutlet TBButton        * flushDnsCacheCheckbox;
	IBOutlet TBButton        * allowManualNetworkSettingsOverrideCheckbox;
	IBOutlet TBButton        * prependDomainNameCheckbox;
	IBOutlet TBButton        * useRouteUpInsteadOfUpCheckbox;
    IBOutlet TBButton        * enableIpv6OnTapCheckbox;
	IBOutlet TBButton        * keepConnectedCheckbox;
	
	IBOutlet TBPopUpButton	     * loadTunPopUpButton;
	IBOutlet NSMenuItem          * loadTunAutomaticallyMenuItem;
	IBOutlet NSMenuItem          * loadTunAlwaysMenuItem;
	IBOutlet NSMenuItem          * loadTunNeverMenuItem;
	
	IBOutlet TBPopUpButton       * loadTapPopUpButton;
	IBOutlet NSMenuItem          * loadTapAutomaticallyMenuItem;
	IBOutlet NSMenuItem          * loadTapAlwaysMenuItem;
	IBOutlet NSMenuItem          * loadTapNeverMenuItem;
	
    IBOutlet TBButton * authenticateOnConnectCheckbox;
    IBOutlet TBButton        * disconnectOnSleepCheckbox;
    IBOutlet TBButton        * reconnectOnWakeFromSleepCheckbox;
	
	IBOutlet TBButton        * disconnectWhenUserSwitchesOutCheckbox;
	IBOutlet TBButton        * reconnectWhenUserSwitchesInCheckbox;
	
    IBOutlet NSButton            * connectingHelpButton;
    
    IBOutlet NSTextFieldCell     * ifConnectedWhenUserSwitchedOutTFC;
    IBOutlet NSTextField         * ifConnectedWhenUserSwitchedOutTF;
    
    IBOutlet NSTextFieldCell     * ifConnectedWhenComputerWentToSleepTFC;
    IBOutlet NSTextField         * ifConnectedWhenComputerWentToSleepTF;

    IBOutlet NSBox               * fastUserSwitchingBox;
    IBOutlet NSBox               * sleepWakeBox;
    
    // For WhileConnected tab
    
    IBOutlet TBButton        * runMtuTestCheckbox;
    IBOutlet TBButton        * monitorNetworkForChangesCheckbox;
    
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
    
    IBOutlet NSNumber            * selectedDnsServersIndex;
    IBOutlet NSNumber            * selectedDomainIndex;
    IBOutlet NSNumber            * selectedSearchDomainIndex;
    IBOutlet NSNumber            * selectedWinsServersIndex;
    IBOutlet NSNumber            * selectedNetBiosNameIndex;
    IBOutlet NSNumber            * selectedWorkgroupIndex;
    
    IBOutlet NSNumber            * selectedOtherdnsServersIndex;
    IBOutlet NSNumber            * selectedOtherdomainIndex;
    IBOutlet NSNumber            * selectedOthersearchDomainIndex;
    IBOutlet NSNumber            * selectedOtherwinsServersIndex;
    IBOutlet NSNumber            * selectedOthernetBiosNameIndex;
    IBOutlet NSNumber            * selectedOtherworkgroupIndex;
    
    IBOutlet NSTextFieldCell     * dnsServersTFC;
    IBOutlet NSTextField         * dnsServersTF;
    IBOutlet NSTextFieldCell     * domainTFC;
    IBOutlet NSTextField         * domainTF;
    IBOutlet NSTextFieldCell     * searchDomainTFC;
    IBOutlet NSTextField         * searchDomainTF;
    IBOutlet NSTextFieldCell     * winsServersTFC;
    IBOutlet NSTextField         * winsServersTF;
    IBOutlet NSTextFieldCell     * netBiosNameTFC;
    IBOutlet NSTextField         * netBiosNameTF;
    IBOutlet NSTextFieldCell     * workgroupTFC;
    IBOutlet NSTextField         * workgroupTF;
    
    
    // For Credentials tab
	
    IBOutlet TBButton        * allConfigurationsUseTheSameCredentialsCheckbox;
	
	IBOutlet NSBox               * namedCredentialsBox;
    
    IBOutlet NSButton            * credentialsGroupButton;
    IBOutlet NSArrayController   * credentialsGroupArrayController;
	IBOutlet NSNumber            * selectedCredentialsGroupIndex;
	
	IBOutlet NSTextField		 * addNamedCredentialsTF;
	IBOutlet NSTextFieldCell	 * addNamedCredentialsTFC;
	IBOutlet NSButton            * addNamedCredentialsButton;
	
	IBOutlet NSButton            * removeNamedCredentialsButton;
    NSArray                      * removeNamedCredentialsNames;
    
    
    // For Sounds tab
    IBOutlet NSBox               * alertSoundsBox;
    
    IBOutlet NSNumber            * selectedSoundOnConnectIndex;
    IBOutlet NSNumber            * selectedSoundOnDisconnectIndex;

    IBOutlet NSTextFieldCell     * connectionAlertSoundTFC;
    IBOutlet NSTextFieldCell     * disconnectionAlertSoundTFC;
    
    IBOutlet NSButton            * soundOnConnectButton;
    IBOutlet NSButton            * soundOnDisconnectButton;
    
    IBOutlet NSArrayController   * soundOnConnectArrayController;
    IBOutlet NSArrayController   * soundOnDisconnectArrayController;
}

// General methods

-(void) setConfigurationName: (NSString *) newName;

-(void) showSettingsSheet:    (id) sender;
-(void) endSettingsSheet:     (id) sender;

-(void) monitorNetworkForChangesCheckboxChangedForConnection: (VPNConnection *) theConnection;

-(void) updateStaticContentSetupSettingsAndBringToFront;

-(void) setupSettingsFromPreferences;

// Methods for Connecting tab
-(IBAction) authenticateOnConnectWasClicked:                        (NSButton *) sender;
-(IBAction) flushDnsCacheCheckboxWasClicked:                        (NSButton *) sender;
-(IBAction) allowManualNetworkSettingsOverrideCheckboxWasClicked:   (NSButton *) sender;
-(IBAction) keepConnectedCheckboxWasClicked:                        (NSButton *) sender;
-(IBAction) enableIpv6OnTapCheckboxWasClicked:                      (NSButton *) sender;
-(IBAction) useRouteUpInsteadOfUpCheckboxWasClicked:                (NSButton *) sender;
-(IBAction) prependDomainNameCheckboxWasClicked:                    (NSButton *) sender;
-(IBAction) disconnectOnSleepCheckboxWasClicked:                    (NSButton *) sender;
-(IBAction) reconnectOnWakeFromSleepCheckboxWasClicked:             (NSButton *) sender;
-(IBAction) runMtuTestCheckboxWasClicked:                           (NSButton *) sender;
-(IBAction) connectingHelpButtonWasClicked:                         (id)         sender;

-(IBAction) disconnectWhenUserSwitchesOutCheckboxWasClicked:  (NSButton *) sender;
-(IBAction) reconnectWhenUserSwitchesInCheckboxWasClicked:    (NSButton *) sender;

-(IBAction) loadTunAutomaticallyMenuItemWasClicked: (id) sender;
-(IBAction) loadTapAutomaticallyMenuItemWasClicked: (id)sender;
-(IBAction) loadTunNeverMenuItemWasClicked:         (id)sender;
-(IBAction) loadTapNeverMenuItemWasClicked:         (id)sender;
-(IBAction) loadTunAlwaysMenuItemWasClicked:        (id)sender;
-(IBAction) loadTapAlwaysMenuItemWasClicked:        (id)sender;
    

// Methods for While Connected tab

-(IBAction)  monitorNetworkForChangesCheckboxWasClicked: (NSButton *) sender;

-(IBAction)  whileConnectedHelpButtonWasClicked: (id) sender;

-(NSNumber *) selectedDnsServersIndex;
-(void)      setSelectedDnsServersIndex:   (NSNumber *) newValue;

-(NSNumber *) selectedDomainIndex;
-(void)      setSelectedDomainIndex:       (NSNumber *) newValue;

-(NSNumber *) selectedSearchDomainIndex;
-(void)      setSelectedSearchDomainIndex: (NSNumber *) newValue;

-(NSNumber *) selectedWinsServersIndex;
-(void)      setSelectedWinsServersIndex:  (NSNumber *) newValue;

-(NSNumber *) selectedNetBiosNameIndex;
-(void)      setSelectedNetBiosNameIndex:  (NSNumber *) newValue;

-(NSNumber *) selectedWorkgroupIndex;
-(void)      setSelectedWorkgroupIndex:    (NSNumber *) newValue;

-(NSNumber *) selectedOtherdnsServersIndex;
-(void)      setSelectedOtherdnsServersIndex:   (NSNumber *) newValue;

-(NSNumber *) selectedOtherdomainIndex;
-(void)      setSelectedOtherdomainIndex:       (NSNumber *) newValue;

-(NSNumber *) selectedOthersearchDomainIndex;
-(void)      setSelectedOthersearchDomainIndex: (NSNumber *) newValue;

-(NSNumber *) selectedOtherwinsServersIndex;
-(void)      setSelectedOtherwinsServersIndex:  (NSNumber *) newValue;

-(NSNumber *) selectedOthernetBiosNameIndex;
-(void)      setSelectedOthernetBiosNameIndex:  (NSNumber *) newValue;

-(NSNumber *) selectedOtherworkgroupIndex;
-(void)      setSelectedOtherworkgroupIndex:    (NSNumber *) newValue;

-(NSNumber *) selectedCredentialsGroupIndex;
-(void)      setSelectedCredentialsGroupIndex:    (NSNumber *) newValue;


// Methods for Credentials tab

-(IBAction) allConfigurationsUseTheSameCredentialsCheckboxWasClicked: (NSButton *) sender;

-(IBAction) addNamedCredentialsButtonWasClicked: (id) sender;
-(IBAction) addNamedCredentialsReturnWasTyped: (id) sender;

-(IBAction) vpnCredentialsHelpButtonWasClicked: (id) sender;


// Getters & Setters

TBPROPERTY_READONLY(BOOL, showingSettingsSheet)

TBPROPERTY_READONLY(TBButton *, allConfigurationsUseTheSameCredentialsCheckbox)

TBPROPERTY_READONLY(NSBox *, namedCredentialsBox)

TBPROPERTY_READONLY(NSButton *, removeNamedCredentialsButton)
TBPROPERTY(NSArray *,           removeNamedCredentialsNames, setRemoveNamedCredentialsNames)

TBPROPERTY_READONLY(NSButton *,            credentialsGroupButton)
TBPROPERTY_READONLY(NSArrayController *,   credentialsGroupArrayController)

TBPROPERTY_READONLY(NSButton *, addNamedCredentialsButton)

TBPROPERTY(NSNumber *, selectedSoundOnConnectIndex,          setSelectedSoundOnConnectIndex)
TBPROPERTY(NSNumber *, selectedSoundOnDisconnectIndex,       setSelectedSoundOnDisconnectIndex)

TBPROPERTY_READONLY(NSBox           *,     alertSoundsBox)
TBPROPERTY_READONLY(NSTextFieldCell *,     connectionAlertSoundTFC)
TBPROPERTY_READONLY(NSTextFieldCell *,     disconnectionAlertSoundTFC)
TBPROPERTY_READONLY(NSButton *,            soundOnConnectButton)
TBPROPERTY_READONLY(NSButton *,            soundOnDisconnectButton)
TBPROPERTY_READONLY(NSArrayController *,   soundOnConnectArrayController)
TBPROPERTY_READONLY(NSArrayController *,   soundOnDisconnectArrayController)

TBPROPERTY_READONLY(NSTabViewItem *, connectingAndDisconnectingTabViewItem)
TBPROPERTY_READONLY(NSTabViewItem *, whileConnectedTabViewItem)
TBPROPERTY_READONLY(NSTabViewItem *, credentialsTabViewItem)
TBPROPERTY_READONLY(NSTabViewItem *, soundTabViewItem)

TBPROPERTY(VPNConnection *, connection, setConnection)

@end
