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

typedef enum
{
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
    
    IBOutlet NSTextFieldCell     * configurationNameTFC;
    IBOutlet NSTextFieldCell     * configurationStatusTFC;
    
    
    // For Connecting tab
    
    IBOutlet NSButton            * scanConfigurationFileCheckbox;
    IBOutlet NSButton            * useTunTapDriversCheckbox;
    IBOutlet NSButton            * flushDnsCacheCheckbox;
    
    IBOutlet NSButton            * connectingHelpButton;
    
    
    // For Disconnecting tab
    
    IBOutlet NSButton            * disconnectWhenUserSwitchesOutCheckbox;
    IBOutlet NSButton            * reconnectWhenUserSwitchesInCheckbox;
    
    IBOutlet NSTextFieldCell     * ifConnectedWhenUserSwitchedOutTFC;
    
    IBOutlet NSBox               * fastUserSwitchingBox;
    
    
    // For WhileConnected tab
    
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
}

// General methods

-(void) setConfigurationName: (NSString *) newName;
-(void) setStatus:            (NSString *) newStatus;
-(void) updateConnectionStatusAndTime;

-(void) showSettingsSheet:    (id) sender;
-(void) endSettingsSheet:     (id) sender;

-(void) monitorNetworkForChangesCheckboxChangedForConnection: (VPNConnection *) theConnection;

// Methods for Connecting tab

TBPROPERTY_READONLY(NSTabViewItem *, connectingAndDisconnectingTabViewItem)

-(IBAction) scanConfigurationFileCheckboxWasClicked:             (id) sender;
-(IBAction) useTunTapDriversCheckboxWasClicked:                  (id) sender;
-(IBAction) flushDnsCacheCheckboxWasClicked:                     (id) sender;

-(IBAction) connectingHelpButtonWasClicked:                      (id) sender;

-(IBAction) disconnectWhenUserSwitchesOutCheckboxWasClicked:  (id) sender;
-(IBAction) reconnectWhenUserSwitchesInCheckboxWasClicked:    (id) sender;


// Methods for While Connecting tab

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

@end
