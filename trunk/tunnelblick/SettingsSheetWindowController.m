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


#import "SettingsSheetWindowController.h"
#import "defines.h"
#import "TBUserDefaults.h"
#import "MenuController.h"
#import "ConfigurationManager.h"
#import "helper.h"
#import "MyPrefsWindowController.h"


extern NSString             * gPrivatePath;
extern NSFileManager        * gFileMgr;
extern TBUserDefaults       * gTbDefaults;


@interface SettingsSheetWindowController()    // Private methods

//**********************************************************************************************************************************
// Methods that set up static content (content that is the same for all connections)

-(void) initializeStaticContent;

//**********************************************************************************************************************************
// Methods that set up up content that depends on a connection's settings

// Overall set up
-(void) setupSettingsFromPreferences;

// Methods for setting up specific types of information

-(void) setupCheckbox: (NSButton *) checkbox
                  key: (NSString *) key
             inverted: (BOOL) inverted;

-(void) setupMonitoringOptions;

-(NSInteger) indexForMonitoringOptionButton: (NSPopUpButton *) button
                              newPreference: (NSString *)      preference
                              oldPreference: (NSString *)      oldPreference
                      leasewatchOptionsChar: (NSString *)      leasewatchOptionsChar;

-(BOOL) changeBooleanPreference: (NSString *) key
                             to: (BOOL)       newValue
                       inverted: (BOOL)       inverted;

-(void) setDnsWinsIndex: (NSInteger *) index
                     to: (NSInteger)   newValue
             preference: (NSString *)  key;

@end


@implementation SettingsSheetWindowController

-(id) init {
    self = [super initWithWindowNibName:@"SettingsSheet"];
    if (  ! self  ) {
        return nil;
    }
    
    configurationName = nil;
    connection        = nil;

    configurationType = sharedConfiguration;
    
    showingSettingsSheet   = FALSE;
    doNotModifyPreferences = FALSE;
    
    return self;
}

-(void) dealloc {
    [configurationName release];
    [connection        release];
    [removeNamedCredentialsNames release];
    
    [super dealloc];
}

-(void) setConfigurationName: (NSString *) newName {
    if (  ! [configurationName isEqualToString: newName]  ) {
        [configurationName release];
        configurationName = [newName retain];
        
        [self setConnection: [[[NSApp delegate] myVPNConnectionDictionary] objectForKey: configurationName]];
        
        if (  showingSettingsSheet  ) {
            [self initializeStaticContent];
            [self setupSettingsFromPreferences];
        }
    }
    
    return;
}

-(void) setStatus: (NSString *) newStatus {
    [configurationStatusTFC setTitle: localizeNonLiteral(newStatus, @"Connection status")];
}                                                            

-(void) updateConnectionStatusAndTime {
    if ( showingSettingsSheet  ) {
        NSString * state = [connection state];
        NSString * localizedStatus = localizeNonLiteral(state, @"Connection status");
        if (  [state isEqualToString: @"CONNECTED"]  ) {
            NSString * time = [connection connectTimeString];
            [configurationStatusTFC setTitle: [NSString stringWithFormat: @"%@%@",
                                               localizedStatus, time]];
        } else {
            [configurationStatusTFC setTitle: localizedStatus];
        }
    }    
}

- (void) setupCredentialsGroupButton {
	selectedCredentialsGroupIndex = NSNotFound;
	
	NSInteger ix = 0;
	NSString * prefKey = [[connection displayName] stringByAppendingString: @"-credentialsGroup"];
	NSString * group = [gTbDefaults objectForKey: prefKey];
	if (   group
		&& (  [group length] != 0 )  ) {
        NSArray * listContent = [credentialsGroupArrayController content];
        NSDictionary * dict;
        unsigned i;
        for (  i=0; i<[listContent count]; i++  ) { 
            dict = [listContent objectAtIndex: i];
            if (  [[dict objectForKey: @"value"] isEqualToString: group]  ) {
                ix = (int)i;
                break;
            }
        }
        
        if (  ix == NSNotFound  ) {
            NSLog(@"Preference '%@' ignored: credentials group '%@' was not found", prefKey, group);
        }
	}
	
	[self setSelectedCredentialsGroupIndex: (unsigned) ix];
	[credentialsGroupButton          setEnabled: (   ( ! [gTbDefaults objectForKey: @"namedCredentialsThatAllConfigurationsUse"] )
												  && [gTbDefaults canChangeValueForKey: prefKey])];
	
}

- (void) setupPrependDomainNameCheckbox {
    // Select the appropriate Set nameserver entry
    int ix = 1; // Default is 'Set nameserver'
    NSString * key = [configurationName stringByAppendingString: @"useDNS"];
    id obj = [gTbDefaults objectForKey: key];
	if (  [obj respondsToSelector: @selector(intValue)]  ) {
		ix = [obj intValue];
	}
    
    if (  ix == 1  ) {
        [self setupCheckbox: prependDomainNameCheckbox
                        key: @"-prependDomainNameToSearchDomains"
                   inverted: NO];
    } else {
        [prependDomainNameCheckbox setState: NSOffState];
        [prependDomainNameCheckbox setEnabled: NO];
    }
}

-(void) setupFlushDNSCheckbox {
    // Select the appropriate Set nameserver entry
    int ix = 1; // Default is 'Set nameserver'
    NSString * key = [configurationName stringByAppendingString: @"useDNS"];
    id obj = [gTbDefaults objectForKey: key];
	if (  [obj respondsToSelector: @selector(intValue)]  ) {
		ix = [obj intValue];
	}
    
    if (  ix == 1  ) {
        [self setupCheckbox: flushDnsCacheCheckbox
                        key: @"-doNotFlushCache"
                   inverted: YES];
    } else {
        [flushDnsCacheCheckbox setState: NSOffState];
        [flushDnsCacheCheckbox setEnabled: NO];
    }
}

- (void) setupReconnectOnWakeFromSleepCheckbox {
    [self setupCheckbox: reconnectOnWakeFromSleepCheckbox
                    key: @"-doNotReconnectOnWakeFromSleep"
               inverted: YES];
}

- (void) setupRouteAllTrafficThroughVpnCheckbox {
    [self setupCheckbox: routeAllTrafficThroughVpnCheckbox
                    key: @"-routeAllTrafficThroughVpn"
               inverted: NO];
}

-(void) showSettingsSheet: (id) sender {
	(void) sender;
	
    if (  ! settingsSheet  ) {
        [super showWindow: self];
    } else {
        showingSettingsSheet = TRUE;
        [self setupSettingsFromPreferences];
    }
    
    [[self window] display];
    [[self window] makeKeyAndOrderFront: self];
    [NSApp activateIgnoringOtherApps:YES];
}

-(void) endSettingsSheet:  (id) sender {
    showingSettingsSheet = FALSE;
    [NSApp endSheet: settingsSheet];
    [settingsSheet orderOut: sender];
    [settingsSheet release];
    settingsSheet = nil;
}

-(void) awakeFromNib {
    showingSettingsSheet = TRUE;
    
    [self initializeStaticContent];
    [self setupSettingsFromPreferences];
}

//**********************************************************************************************************************************

-(void) setTitle: (NSString *) newTitle ofControl: (id) theControl {
	// Sets the title for a control, shifting the origin of the control itself to the left.

    NSRect oldRect = [theControl frame];
    [theControl setTitle: newTitle];
    [theControl sizeToFit];
    
    NSRect newRect = [theControl frame];
    float widthChange = newRect.size.width - oldRect.size.width;
    NSRect oldPos;
    
    if (   [theControl isEqual: addNamedCredentialsButton]  ) {
        oldPos = [theControl frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [theControl setFrame:oldPos];
    }
}

-(void) underlineLabel: tf string: inString alignment: (NSTextAlignment) align {
    NSMutableAttributedString* attrString = [[NSMutableAttributedString alloc] initWithString: inString];
    NSRange range = NSMakeRange(0, [attrString length]);
    
    [attrString beginEditing];
    
    // make the text appear with an underline
    [attrString addAttribute:
     NSUnderlineStyleAttributeName value:[NSNumber numberWithInt:NSSingleUnderlineStyle] range:range];
    
    // make the text appear flush-right
    [attrString setAlignment: align range: range];
    
    [attrString endEditing];
    
    [tf setAttributedStringValue: attrString];
    [attrString release];
}

-(void) initializeDnsWinsPopUp: (NSPopUpButton *) popUpButton arrayController: (NSArrayController *) ac {
    NSArray * content = [NSArray arrayWithObjects:
                         [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Ignore"            , @"Button"), @"name", @"ignore" , @"value", nil],
                         [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Restore"           , @"Button"), @"name", @"restore", @"value", nil],
                         [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Restart connection", @"Button"), @"name", @"restart", @"value", nil],
                         nil];
    [ac setContent: content];
    
    /*
     if (  popUpButton == dnsServersPopUpButton  ) {
     
     // When resize this control, shift the columns that are to its right either left or right to match the size change
     NSRect oldRect = [popUpButton frame];
     [popUpButton sizeToFit];
     NSRect newRect = [popUpButton frame];
     float widthChange = newRect.size.width - oldRect.size.width;
     
     NSArray * stuffToShift = [NSArray arrayWithObjects:
     whenChangesToAnythingElseTF,
     otherdnsServersPopUpButton,
     otherdomainPopUpButton,
     othersearchDomainPopUpButton,
     otherwinsServersPopUpButton,
     othernetBiosNamePopUpButton,
     otherworkgroupPopUpButton,
     nil];
     NSEnumerator * arrayEnum = [stuffToShift objectEnumerator];
     id control;
     while (  (control = [arrayEnum nextObject])  ) {
     NSRect oldPos;
     oldPos = [control frame];
     oldPos.origin.x = oldPos.origin.x + widthChange;
     [control setFrame:oldPos];
     }
     } else {
     */
    [popUpButton sizeToFit];
    /*
     }
     */
}

-(void) initializeStaticContent {
    [configurationNameTFC setTitle: [NSString stringWithFormat: @"%@:", configurationName]];
    
    // For Connecting tab
	
    [connectingAndDisconnectingTabViewItem  setLabel: NSLocalizedString(@"Connecting & Disconnecting", @"Window title")];
     
    [scanConfigurationFileCheckbox          setTitle: NSLocalizedString(@"Scan configuration file for problems before connecting", @"Checkbox name")];
    [useTunTapDriversCheckbox               setTitle: NSLocalizedString(@"Use Tunnelblick tun/tap drivers"                       , @"Checkbox name")];
    [flushDnsCacheCheckbox                  setTitle: NSLocalizedString(@"Flush DNS cache after connecting or disconnecting"     , @"Checkbox name")];
    [prependDomainNameCheckbox              setTitle: NSLocalizedString(@"Prepend domain name to search domains"                 , @"Checkbox name")];
    [reconnectOnWakeFromSleepCheckbox       setTitle: NSLocalizedString(@"Reconnect when computer wakes from sleep (if connected when computer went to sleep)", @"Checkbox name")];
    [routeAllTrafficThroughVpnCheckbox      setTitle: NSLocalizedString(@"Route all traffic through the VPN", @"Checkbox name")];
    
    
    [fastUserSwitchingBox                   setTitle: NSLocalizedString(@"Fast User Switching"                  , @"Window text")];
    
    [disconnectWhenUserSwitchesOutCheckbox  setTitle: NSLocalizedString(@"Disconnect when user switches out", @"Checkbox name")];
    [reconnectWhenUserSwitchesInCheckbox    setTitle: NSLocalizedString(@"Reconnect when user switches in"  , @"Checkbox name")];
    
    [ifConnectedWhenUserSwitchedOutTFC      setTitle: NSLocalizedString(@"(if connected when user switched out)", @"Window text")];
    
    
    // For WhileConnected tab
    
    [whileConnectedTabViewItem        setLabel: NSLocalizedString(@"While Connected", @"Window title")];

    [monitorNetworkForChangesCheckbox setTitle: NSLocalizedString(@"Monitor network settings", @"Checkbox name")];
    
    [self underlineLabel: networkSettingTF            string: NSLocalizedString(@"Network setting"              , @"Window text") alignment: NSRightTextAlignment];
    [self underlineLabel: whenChangesToPreVpnValueTF  string: NSLocalizedString(@"When changes to pre-VPN value", @"Window text") alignment: NSLeftTextAlignment ];
    [self underlineLabel: whenChangesToAnythingElseTF string: NSLocalizedString(@"When changes to anything else", @"Window text") alignment: NSLeftTextAlignment ];
    
    [dnsServersTFC   setTitle: NSLocalizedString(@"DNS servers:"  , @"Window text")];
    [domainTFC       setTitle: NSLocalizedString(@"Domain:"       , @"Window text")];
    [searchDomainTFC setTitle: NSLocalizedString(@"Search domain:", @"Window text")];
    [winsServersTFC  setTitle: NSLocalizedString(@"WINS servers:" , @"Window text")];
    [netBiosNameTFC  setTitle: NSLocalizedString(@"NetBIOS name:" , @"Window text")];
    [workgroupTFC    setTitle: NSLocalizedString(@"Workgroup:"    , @"Window text")];
    
    [self initializeDnsWinsPopUp: dnsServersPopUpButton   arrayController: dnsServersArrayController   ];
    [self initializeDnsWinsPopUp: domainPopUpButton       arrayController: domainArrayController       ];
    [self initializeDnsWinsPopUp: searchDomainPopUpButton arrayController: searchDomainArrayController ];
    [self initializeDnsWinsPopUp: winsServersPopUpButton  arrayController: winsServersArrayController  ];
    [self initializeDnsWinsPopUp: netBiosNamePopUpButton  arrayController: netBiosNameArrayController  ];
    [self initializeDnsWinsPopUp: workgroupPopUpButton    arrayController: workgroupArrayController    ];

    [self initializeDnsWinsPopUp: otherdnsServersPopUpButton   arrayController: otherdnsServersArrayController  ];
    [self initializeDnsWinsPopUp: otherdomainPopUpButton       arrayController: otherdomainArrayController      ];
    [self initializeDnsWinsPopUp: othersearchDomainPopUpButton arrayController: othersearchDomainArrayController];
    [self initializeDnsWinsPopUp: otherwinsServersPopUpButton  arrayController: otherwinsServersArrayController ];
    [self initializeDnsWinsPopUp: othernetBiosNamePopUpButton  arrayController: othernetBiosNameArrayController ];
    [self initializeDnsWinsPopUp: otherworkgroupPopUpButton    arrayController: otherworkgroupArrayController   ];
    
	
	// For Credentials tab, everything depends on preferences; there is nothing static
	
}

//**********************************************************************************************************************************
-(void) setupSettingsFromPreferences {
    NSString * programName;
    if (  [configurationName isEqualToString: NSLocalizedString(@"Tunnelblick", @"Window title")]  ) {
        programName = @"";
    } else {
        programName = [NSString stringWithFormat: @" - Tunnelblick"];
    }
    [settingsSheet setTitle: [NSString stringWithFormat: NSLocalizedString(@"%@ Advanced Settings%@", @"Window title"), configurationName, programName]];
    
    [self setStatus: [connection state]];
    
    // For Connecting tab
    
	[self setupCredentialsGroupButton];
	
    [self setupCheckbox: scanConfigurationFileCheckbox
                    key: @"-doNotParseConfigurationFile"
               inverted: YES];
    
    // useTunTapDriversCheckbox
    NSString * key = [configurationName stringByAppendingString: @"-loadTapKext"];
    BOOL loadTap               = [gTbDefaults boolForKey: key];
    BOOL canChangeLoadTap      = [gTbDefaults canChangeValueForKey: key];
    
    key = [configurationName stringByAppendingString: @"-loadTunKext"];
    BOOL loadTun               = [gTbDefaults boolForKey: key];
    BOOL canChangeLoadTun      = [gTbDefaults canChangeValueForKey: key];
    
    key = [configurationName stringByAppendingString: @"-doNotLoadTapKext"];
    BOOL doNotLoadTap          = [gTbDefaults boolForKey: key];
    BOOL canChangeDoNotLoadTap = [gTbDefaults canChangeValueForKey: key];
    
    key = [configurationName stringByAppendingString: @"-doNotLoadTunKext"];
    BOOL doNotLoadTun          = [gTbDefaults boolForKey: key];
    BOOL canChangeDoNotLoadTun = [gTbDefaults canChangeValueForKey: key];
    
    int state = NSMixedState;
    if (  loadTap && loadTun  ) {
        if (  (! doNotLoadTap) && (! doNotLoadTun)  ) {
            state = NSOnState;
        }
    } else if (  (! loadTap) && (! loadTun)  ) {
        if (  doNotLoadTap  && doNotLoadTun  ) {
            state = NSOffState;
        } else if (  (! doNotLoadTap) && (! doNotLoadTun)  ) {
            state = NSOnState;
        }
    }
    [useTunTapDriversCheckbox setState: state];
    
    if (   (state != NSMixedState)
        && canChangeLoadTap && canChangeLoadTun && canChangeDoNotLoadTap && canChangeDoNotLoadTun  ) {
        [useTunTapDriversCheckbox setEnabled: TRUE];
    } else {
        [useTunTapDriversCheckbox setEnabled: FALSE];
    }
    
    [self setupPrependDomainNameCheckbox];
    
    [self setupFlushDNSCheckbox];
    
    [self setupReconnectOnWakeFromSleepCheckbox];
    
    [self setupRouteAllTrafficThroughVpnCheckbox];
    
    [self setupCheckbox: disconnectWhenUserSwitchesOutCheckbox
                    key: @"-doNotDisconnectOnFastUserSwitch"
               inverted: YES];
    
    [self setupCheckbox: reconnectWhenUserSwitchesInCheckbox
                    key: @"-doNotReconnectOnFastUserSwitch"
               inverted: YES];
    
    
    // For WhileConnected tab
    if (  [[[NSApp delegate] logScreen] forceDisableOfNetworkMonitoring]  ) {
        [monitorNetworkForChangesCheckbox setState: NSOffState];
        [monitorNetworkForChangesCheckbox setEnabled: NO];
    } else {
        [self setupCheckbox: monitorNetworkForChangesCheckbox
                        key: @"-notMonitoringConnection"
                   inverted: YES];
    }
    
    [self setupMonitoringOptions];
	
	
	// For VPN Credentials tab
	
	[self setRemoveNamedCredentialsNames: [gTbDefaults sortedCredentialsGroups]];
	
    [credentialsTabViewItem setLabel:
	 NSLocalizedString(@"VPN Credentials", @"Window title")];
	
	[namedCredentialsBox
	 setTitle: NSLocalizedString(@"Named Credentials", @"Window text")];
	
	[self setTitle: NSLocalizedString(@"Add Credentials...", @"Window text")
		 ofControl: addNamedCredentialsButton];
	
    // Create a menu for the Remove Credentials pull-down button
    NSMenu * removeCredentialMenu = [[[NSMenu alloc] init] autorelease];
	NSMenuItem * item = [[[NSMenuItem alloc] initWithTitle: NSLocalizedString(@"Remove Credentials", @"Button")
													action: @selector(removeNamedCredentialsCommand:)
											 keyEquivalent: @""] autorelease];	
	[item setTag: 0];
	[item setTarget: self];
	[removeCredentialMenu addItem: item];
    
	// Create an array of dictionaries of credentials groups, with both name and value = name of group
 	NSMutableArray * groupsDictionaryArray = [NSMutableArray arrayWithCapacity: [removeNamedCredentialsNames count]];
	NSString * groupName = [gTbDefaults objectForKey: @"namedCredentialsThatAllConfigurationsUse"];
	if (  groupName  ) {
		[groupsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys:
										   [NSString stringWithFormat:
											NSLocalizedString(@"This configuration uses %@ credentials", @"Button"),
											groupName], @"name",
										   groupName, @"value", nil]];
	} else {
		[groupsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys:
										   NSLocalizedString(@"This configuration has its own separate credentials", @"Button"), @"name",
										   @"", @"value", nil]];
	}
	unsigned i;
	for (  i=0; i<[removeNamedCredentialsNames count]; i++  ) {
        NSString * groupName = [removeNamedCredentialsNames objectAtIndex: i];
		[groupsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys:
										   [NSString stringWithFormat:
											NSLocalizedString(@"This configuration uses %@ credentials", @"Button"),
											groupName], @"name",
										   groupName, @"value", nil]];
        
		NSMenuItem * item = [[[NSMenuItem alloc] initWithTitle: groupName
                                                        action: @selector(removeNamedCredentialsCommand:)
                                                 keyEquivalent: @""] autorelease];
        [item setTag: (int) i];
		[item setTarget: self];
        [removeCredentialMenu addItem: item];
	}
	
	NSString * prefKey = [[connection displayName] stringByAppendingString: @"-credentialsGroup"];
	[credentialsGroupArrayController setContent: groupsDictionaryArray];
	[credentialsGroupButton          sizeToFit];
	[credentialsGroupButton          setEnabled: (   ( ! [gTbDefaults objectForKey: @"namedCredentialsThatAllConfigurationsUse"] )
												  && [gTbDefaults canChangeValueForKey: prefKey])];
	
    
    [removeNamedCredentialsButton setMenu: removeCredentialMenu];
	[removeNamedCredentialsButton setEnabled: ! [gTbDefaults objectForKey: @"namedCredentialsThatAllConfigurationsUse"]];
	
	NSString * groupAllConfigurationsUse = [removeNamedCredentialsNames objectAtIndex: 0];
	if (  ! groupAllConfigurationsUse  ) {
		groupAllConfigurationsUse = NSLocalizedString(@"Common", @"Credentials name");
	}
	
	[self setupCredentialsGroupButton];
	
	NSString * groupFromPrefs = [gTbDefaults objectForKey: @"namedCredentialsThatAllConfigurationsUse"];
	if (  groupFromPrefs  ) {
		[allConfigurationsUseTheSameCredentialsCheckbox setState: NSOnState];
		[credentialsGroupButton       setEnabled: NO];
		[addNamedCredentialsButton    setEnabled: NO];
		[removeNamedCredentialsButton setEnabled: NO];
		
	} else {
		[allConfigurationsUseTheSameCredentialsCheckbox setState: NSOffState];
		[credentialsGroupButton       setEnabled: YES];
		[addNamedCredentialsButton    setEnabled: YES];
		[removeNamedCredentialsButton setEnabled: YES];
	}
	
	[allConfigurationsUseTheSameCredentialsCheckbox setTitle: [NSString stringWithFormat:
															   NSLocalizedString(@"All configurations use %@ credentials", @"Window text"),
															   groupAllConfigurationsUse]];
	[allConfigurationsUseTheSameCredentialsCheckbox sizeToFit];
}

-(void) setupMonitoringOptions {
    if (   connection
        && ( ! [[[NSApp delegate] logScreen] forceDisableOfNetworkMonitoring] )
        && ( ! [gTbDefaults boolForKey: [configurationName stringByAppendingString: @"-notMonitoringConnection"]] )  ) {
        
        [dnsServersPopUpButton   setEnabled: YES];
        [domainPopUpButton       setEnabled: YES];
        [searchDomainPopUpButton setEnabled: YES];
        [winsServersPopUpButton  setEnabled: YES];
        [netBiosNamePopUpButton  setEnabled: YES];
        [workgroupPopUpButton    setEnabled: YES];
        
        [otherdnsServersPopUpButton   setEnabled: YES];
        [otherdomainPopUpButton       setEnabled: YES];
        [othersearchDomainPopUpButton setEnabled: YES];
        [otherwinsServersPopUpButton  setEnabled: YES];
        [othernetBiosNamePopUpButton  setEnabled: YES];
        [otherworkgroupPopUpButton    setEnabled: YES];
        
        // *********************************************************************************
        // We DO NOT want to modify the underlying preferences, just the display to the user
        BOOL oldDoNotModifyPreferences = doNotModifyPreferences;
        doNotModifyPreferences = TRUE;
        
        [dnsServersPopUpButton selectItemAtIndex:   [self indexForMonitoringOptionButton: dnsServersPopUpButton   newPreference: @"-changeDNSServersAction"   oldPreference: @"-doNotRestoreOnDnsReset"  leasewatchOptionsChar: @"a"]];
        [domainPopUpButton selectItemAtIndex:       [self indexForMonitoringOptionButton: domainPopUpButton       newPreference: @"-changeDomainAction"       oldPreference: @"-doNotRestoreOnDnsReset"  leasewatchOptionsChar: @"d"]];
        [searchDomainPopUpButton selectItemAtIndex: [self indexForMonitoringOptionButton: searchDomainPopUpButton newPreference: @"-changeSearchDomainAction" oldPreference: @"-doNotRestoreOnDnsReset"  leasewatchOptionsChar: @"s"]];
        [winsServersPopUpButton selectItemAtIndex:  [self indexForMonitoringOptionButton: winsServersPopUpButton  newPreference: @"-changeWINSServersAction"  oldPreference: @"-doNotRestoreOnWinsReset" leasewatchOptionsChar: @"w"]];
        [netBiosNamePopUpButton selectItemAtIndex:  [self indexForMonitoringOptionButton: netBiosNamePopUpButton  newPreference: @"-changeNetBIOSNameAction"  oldPreference: @"-doNotRestoreOnWinsReset" leasewatchOptionsChar: @"n"]];
        [workgroupPopUpButton selectItemAtIndex:    [self indexForMonitoringOptionButton: workgroupPopUpButton    newPreference: @"-changeWorkgroupAction"    oldPreference: @"-doNotRestoreOnWinsReset" leasewatchOptionsChar: @"g"]];
        
        [otherdnsServersPopUpButton selectItemAtIndex:   [self indexForMonitoringOptionButton: otherdnsServersPopUpButton   newPreference: @"-changeOtherDNSServersAction"   oldPreference: nil leasewatchOptionsChar: @"a"]];
        [otherdomainPopUpButton selectItemAtIndex:       [self indexForMonitoringOptionButton: otherdomainPopUpButton       newPreference: @"-changeOtherDomainAction"       oldPreference: nil leasewatchOptionsChar: @"d"]];
        [othersearchDomainPopUpButton selectItemAtIndex: [self indexForMonitoringOptionButton: othersearchDomainPopUpButton newPreference: @"-changeOtherSearchDomainAction" oldPreference: nil leasewatchOptionsChar: @"s"]];
        [otherwinsServersPopUpButton selectItemAtIndex:  [self indexForMonitoringOptionButton: otherwinsServersPopUpButton  newPreference: @"-changeOtherWINSServersAction"  oldPreference: nil leasewatchOptionsChar: @"w"]];
        [othernetBiosNamePopUpButton selectItemAtIndex:  [self indexForMonitoringOptionButton: othernetBiosNamePopUpButton  newPreference: @"-changeOtherNetBIOSNameAction"  oldPreference: nil leasewatchOptionsChar: @"n"]];
        [otherworkgroupPopUpButton selectItemAtIndex:    [self indexForMonitoringOptionButton: otherworkgroupPopUpButton    newPreference: @"-changeOtherWorkgroupAction"    oldPreference: nil leasewatchOptionsChar: @"g"]];
        
        [self setSelectedDnsServersIndex:   [self indexForMonitoringOptionButton: dnsServersPopUpButton   newPreference: @"-changeDNSServersAction"   oldPreference: @"-doNotRestoreOnDnsReset"  leasewatchOptionsChar: @"a"]];
        [self setSelectedDomainIndex:       [self indexForMonitoringOptionButton: domainPopUpButton       newPreference: @"-changeDomainAction"       oldPreference: @"-doNotRestoreOnDnsReset"  leasewatchOptionsChar: @"d"]];
        [self setSelectedSearchDomainIndex: [self indexForMonitoringOptionButton: searchDomainPopUpButton newPreference: @"-changeSearchDomainAction" oldPreference: @"-doNotRestoreOnDnsReset"  leasewatchOptionsChar: @"s"]];
        [self setSelectedWinsServersIndex:  [self indexForMonitoringOptionButton: winsServersPopUpButton  newPreference: @"-changeWINSServersAction"  oldPreference: @"-doNotRestoreOnWinsReset" leasewatchOptionsChar: @"w"]];
        [self setSelectedNetBiosNameIndex:  [self indexForMonitoringOptionButton: netBiosNamePopUpButton  newPreference: @"-changeNetBIOSNameAction"  oldPreference: @"-doNotRestoreOnWinsReset" leasewatchOptionsChar: @"n"]];
        [self setSelectedWorkgroupIndex:    [self indexForMonitoringOptionButton: workgroupPopUpButton    newPreference: @"-changeWorkgroupAction"    oldPreference: @"-doNotRestoreOnWinsReset" leasewatchOptionsChar: @"g"]];
        
        [self setSelectedOtherdnsServersIndex:   [self indexForMonitoringOptionButton: otherdnsServersPopUpButton   newPreference: @"-changeOtherDNSServersAction"   oldPreference: nil leasewatchOptionsChar: @"a"]];
        [self setSelectedOtherdomainIndex:       [self indexForMonitoringOptionButton: otherdomainPopUpButton       newPreference: @"-changeOtherDomainAction"       oldPreference: nil leasewatchOptionsChar: @"d"]];
        [self setSelectedOthersearchDomainIndex: [self indexForMonitoringOptionButton: othersearchDomainPopUpButton newPreference: @"-changeOtherSearchDomainAction" oldPreference: nil leasewatchOptionsChar: @"s"]];
        [self setSelectedOtherwinsServersIndex:  [self indexForMonitoringOptionButton: otherwinsServersPopUpButton  newPreference: @"-changeOtherWINSServersAction"  oldPreference: nil leasewatchOptionsChar: @"w"]];
        [self setSelectedOthernetBiosNameIndex:  [self indexForMonitoringOptionButton: othernetBiosNamePopUpButton  newPreference: @"-changeOtherNetBIOSNameAction"  oldPreference: nil leasewatchOptionsChar: @"n"]];
        [self setSelectedOtherworkgroupIndex:    [self indexForMonitoringOptionButton: otherworkgroupPopUpButton    newPreference: @"-changeOtherWorkgroupAction"    oldPreference: nil leasewatchOptionsChar: @"g"]];
        
        doNotModifyPreferences = oldDoNotModifyPreferences;
        
        NSString * leasewatchOptionsKey = [configurationName stringByAppendingString: @"-leasewatchOptions"];
        NSString * leasewatchOptions = [gTbDefaults objectForKey: leasewatchOptionsKey];
        if (  leasewatchOptions  ) {
            [dnsServersPopUpButton   setEnabled: NO];
            [domainPopUpButton       setEnabled: NO];
            [searchDomainPopUpButton setEnabled: NO];
            [winsServersPopUpButton  setEnabled: NO];
            [netBiosNamePopUpButton  setEnabled: NO];
            [workgroupPopUpButton    setEnabled: NO];
            
            [otherdnsServersPopUpButton   setEnabled: NO];
            [otherdomainPopUpButton       setEnabled: NO];
            [othersearchDomainPopUpButton setEnabled: NO];
            [otherwinsServersPopUpButton  setEnabled: NO];
            [othernetBiosNamePopUpButton  setEnabled: NO];
            [otherworkgroupPopUpButton    setEnabled: NO];
        }
        
        
        // *********************************************************************************
        
    } else {
        
        // *********************************************************************************
        // We DO NOT want to modify the underlying preferences, just the display to the user
        BOOL oldDoNotModifyPreferences = doNotModifyPreferences;
        doNotModifyPreferences = TRUE;
        
        [dnsServersPopUpButton   selectItemAtIndex: 0];
        [domainPopUpButton       selectItemAtIndex: 0];
        [searchDomainPopUpButton selectItemAtIndex: 0];
        [winsServersPopUpButton  selectItemAtIndex: 0];
        [netBiosNamePopUpButton  selectItemAtIndex: 0];
        [workgroupPopUpButton    selectItemAtIndex: 0];
        
        [otherdnsServersPopUpButton   selectItemAtIndex: 0];
        [otherdomainPopUpButton       selectItemAtIndex: 0];
        [othersearchDomainPopUpButton selectItemAtIndex: 0];
        [otherwinsServersPopUpButton  selectItemAtIndex: 0];
        [othernetBiosNamePopUpButton  selectItemAtIndex: 0];
        [otherworkgroupPopUpButton    selectItemAtIndex: 0];
        
        [self setSelectedDnsServersIndex:   0];
        [self setSelectedDomainIndex:       0];
        [self setSelectedSearchDomainIndex: 0];
        [self setSelectedWinsServersIndex:  0];
        [self setSelectedNetBiosNameIndex:  0];
        [self setSelectedWorkgroupIndex:    0];
        
        [self setSelectedOtherdnsServersIndex:   0];
        [self setSelectedOtherdomainIndex:       0];
        [self setSelectedOthersearchDomainIndex: 0];
        [self setSelectedOtherwinsServersIndex:  0];
        [self setSelectedOthernetBiosNameIndex:  0];
        [self setSelectedOtherworkgroupIndex:    0];
        
        doNotModifyPreferences = oldDoNotModifyPreferences;
        // *********************************************************************************
        
        [dnsServersPopUpButton   setEnabled: NO];
        [domainPopUpButton       setEnabled: NO];
        [searchDomainPopUpButton setEnabled: NO];
        [winsServersPopUpButton  setEnabled: NO];
        [netBiosNamePopUpButton  setEnabled: NO];
        [workgroupPopUpButton    setEnabled: NO];
        
        [otherdnsServersPopUpButton   setEnabled: NO];
        [otherdomainPopUpButton       setEnabled: NO];
        [othersearchDomainPopUpButton setEnabled: NO];
        [otherwinsServersPopUpButton  setEnabled: NO];
        [othernetBiosNamePopUpButton  setEnabled: NO];
        [otherworkgroupPopUpButton    setEnabled: NO];
    }
}

-(NSInteger) indexForMonitoringOptionButton: (NSPopUpButton *) button
                              newPreference: (NSString *)      preference
                              oldPreference: (NSString *)      oldPreference
                      leasewatchOptionsChar: (NSString *)      leasewatchOptionsChar {
    NSString * monitorKey = [configurationName stringByAppendingString: @"-notMonitoringConnection"];

    BOOL ignoringBecauseOfLeasewatchOptions = FALSE;
    NSString * leasewatchOptionsKey = [configurationName stringByAppendingString: @"-leasewatchOptions"];
    NSString * leasewatchOptions = [gTbDefaults objectForKey: leasewatchOptionsKey];
    if (  leasewatchOptions  ) {
        if (  [leasewatchOptions rangeOfString: leasewatchOptionsChar].length != 0) {
            ignoringBecauseOfLeasewatchOptions = TRUE;
        }
    }
    
    NSString * defaultValue;
    NSString * actualKey = [configurationName stringByAppendingString: preference];
    
    NSString * oldActualKey = nil;
    if (  oldPreference  ) {
        oldActualKey = [configurationName stringByAppendingString: oldPreference];
    }
    
    [button setEnabled: (   [gTbDefaults canChangeValueForKey: actualKey]
                         && [gTbDefaults canChangeValueForKey: monitorKey]   )];
    
    if (  ignoringBecauseOfLeasewatchOptions  ) {
        return 0;
    }
    
    if (  oldActualKey  ) {
        if (  [gTbDefaults boolForKey: oldActualKey]  ) {
            defaultValue = @"restart";
        } else {
            defaultValue = @"restore";
        }
    } else {
		defaultValue = @"restart";
	}

    NSString * value = nil;
    id obj = [gTbDefaults objectForKey: actualKey];
    if (  obj != nil  ) {
        if (  [[obj class] isSubclassOfClass: [NSString class]]  ) {
            value = (NSString *) obj;
            if (  [value isEqualToString: @"ignore"]  ) {
                return 0;
            } else if (  [value isEqualToString: @"restore"]  ) {
                return 1;
            } else if (  [value isEqualToString: @"restart"]  ) {
                return 2;
            } else {
                NSLog(@"%@ preference '%@' ignored: invalid value; must be 'ignore', 'restore', or 'restart'", actualKey, value);
            }
        } else {
            NSLog(@"%@ preference ignored: invalid value; must be a string", actualKey);
        }
    }
    
    if (  [defaultValue isEqualToString: @"ignore"]  ) {
        return 0;
    } else if (  [defaultValue isEqualToString: @"restore"]  ) {
        return 1;
    } else if (  [defaultValue isEqualToString: @"restart"]  ) {
        return 2;
    } else {
        NSLog(@"Tunnelblick PROGRAM ERROR -- %@ preference default of '%@' ignored", actualKey, defaultValue);
        return 0;
    }
}

// Methods for Connecting & Disconnecting tab

-(IBAction) reconnectWhenUnexpectedDisconnectCheckboxWasClicked: (id) sender {
    // This preference is NOT IMPLEMENTED, nor is there a checkbox in the .xib
    
    [self changeBooleanPreference: @"-doNotReconnectOnUnexpectedDisconnect"
                               to: ([sender state] == NSOnState)
                         inverted: YES];
}


-(IBAction) scanConfigurationFileCheckboxWasClicked: (id) sender {
    [self changeBooleanPreference: @"-doNotParseConfigurationFile"
                               to: ([sender state] == NSOnState)
                         inverted: YES];
}


-(IBAction) useTunTapDriversCheckboxWasClicked: (id) sender {
    BOOL value = ([sender state] == NSOnState);
    [self changeBooleanPreference: @"-loadTapKext"
                               to: value
                         inverted: NO];
    [self changeBooleanPreference: @"-doNotLoadTapKext"
                               to: value
                         inverted: YES];
    [self changeBooleanPreference: @"-loadTunKext"
                               to: value
                         inverted: NO];
    [self changeBooleanPreference: @"-doNotLoadTunKext"
                               to: value
                         inverted: YES];
}


-(IBAction) flushDnsCacheCheckboxWasClicked: (id) sender {
    [self changeBooleanPreference: @"-doNotFlushCache"
                               to: ([sender state] == NSOnState)
                         inverted: YES];
}


-(IBAction) prependDomainNameCheckboxWasClicked:(id)sender {
    [self changeBooleanPreference: @"-prependDomainNameToSearchDomains"
                               to: ([sender state] == NSOnState)
                         inverted: NO];
}


-(IBAction) reconnectOnWakeFromSleepCheckboxWasClicked:(id)sender {
    [self changeBooleanPreference: @"-doNotReconnectOnWakeFromSleep"
                               to: ([sender state] == NSOnState)
                         inverted: YES];
}


-(IBAction) routeAllTrafficThroughVpnCheckboxWasClicked:(id)sender {
    [self changeBooleanPreference: @"-routeAllTrafficThroughVpn"
                               to: ([sender state] == NSOnState)
                         inverted: NO];
}


-(BOOL) changeBooleanPreference: (NSString *) key
                             to: (BOOL)       newValue
                       inverted: (BOOL)       inverted {
    NSString * actualKey = [configurationName stringByAppendingString: key];
    BOOL state = (inverted ? ! newValue : newValue);
    [gTbDefaults setBool: state forKey: actualKey];
    return state;
}

-(IBAction) connectingHelpButtonWasClicked: (id) sender {
	(void) sender;
	
    OSStatus err;
    if ((err = MyGotoHelpPage(CFSTR("vpn-details-advanced-connecting-disconnecting.html"), NULL))  ) {
        NSLog(@"Error %ld from MyGotoHelpPage()", (long) err);
    }
}


-(IBAction) disconnectWhenUserSwitchesOutCheckboxWasClicked: (id) sender  {
    [self changeBooleanPreference: @"-doNotDisconnectOnFastUserSwitch"
                               to: ([sender state] == NSOnState)
                         inverted: YES];
}


-(IBAction) reconnectWhenUserSwitchesInCheckboxWasClicked: (id) sender {
    [self changeBooleanPreference: @"-doNotReconnectOnFastUserSwitch"
                               to: ([sender state] == NSOnState)
                         inverted: YES];
}


// Methods for While Connecting tab

-(void) monitorNetworkForChangesCheckboxChangedForConnection: (VPNConnection *) theConnection {
    // Checkbox was changed by another window
    
    if (   connection
        && (connection == theConnection)  ) {
        if (  [[[NSApp delegate] logScreen] forceDisableOfNetworkMonitoring]  ) {
            [monitorNetworkForChangesCheckbox setState: NSOffState];
            [monitorNetworkForChangesCheckbox setEnabled: NO];
        } else {
            NSString * key = [configurationName stringByAppendingString: @"-notMonitoringConnection"];
            BOOL monitoring = [gTbDefaults boolForKey: key];
            int state = (monitoring ? NSOffState : NSOnState);
            [monitorNetworkForChangesCheckbox setState: state];
            [monitorNetworkForChangesCheckbox setEnabled: YES];
        }
        
        [self setupMonitoringOptions];
    }
}

-(IBAction) monitorNetworkForChangesCheckboxWasClicked: (id) sender {
    [self changeBooleanPreference: @"-notMonitoringConnection"
                               to: ([sender state] == NSOnState)
                         inverted: YES];
    
    [self setupMonitoringOptions];
    
    [[[NSApp delegate] logScreen] monitorNetworkForChangesCheckboxChangedForConnection: connection];
}

-(NSInteger) selectedDnsServersIndex {
    return selectedDnsServersIndex;
}

-(void) setSelectedDnsServersIndex: (NSInteger) newValue {
    [self setDnsWinsIndex: &selectedDnsServersIndex to: newValue preference: @"-changeDNSServersAction"];
}

-(NSInteger) selectedDomainIndex {
    return selectedDomainIndex;
}

-(void) setSelectedDomainIndex: (NSInteger) newValue {
    [self setDnsWinsIndex: &selectedDomainIndex to: newValue preference: @"-changeDomainAction"];
}

-(NSInteger) selectedSearchDomainIndex {
    return selectedSearchDomainIndex;
}

-(void) setSelectedSearchDomainIndex: (NSInteger) newValue {
    [self setDnsWinsIndex: &selectedSearchDomainIndex to: newValue preference: @"-changeSearchDomainAction"];
}

-(NSInteger) selectedWinsServersIndex {
    return selectedWinsServersIndex;
}

-(void) setSelectedWinsServersIndex: (NSInteger) newValue {
    [self setDnsWinsIndex: &selectedWinsServersIndex to: newValue preference: @"-changeWINSServersAction"];
}

-(NSInteger) selectedNetBiosNameIndex {
    return selectedNetBiosNameIndex;
}

-(void) setSelectedNetBiosNameIndex: (NSInteger) newValue {
    [self setDnsWinsIndex: &selectedNetBiosNameIndex to: newValue preference: @"-changeNetBIOSNameAction"];
}

-(NSInteger) selectedWorkgroupIndex {
    return selectedWorkgroupIndex;
}

-(void) setSelectedWorkgroupIndex: (NSInteger) newValue {
    [self setDnsWinsIndex: &selectedWorkgroupIndex to: newValue preference: @"-changeWorkgroupAction"];
}

-(NSInteger) selectedOtherdnsServersIndex {
    return selectedDnsServersIndex;
}

-(void) setSelectedOtherdnsServersIndex: (NSInteger) newValue {
    [self setDnsWinsIndex: &selectedDnsServersIndex to: newValue preference: @"-changeOtherDNSServersAction"];
}

-(NSInteger) selectedOtherdomainIndex {
    return selectedDomainIndex;
}

-(void) setSelectedOtherdomainIndex: (NSInteger) newValue {
    [self setDnsWinsIndex: &selectedDomainIndex to: newValue preference: @"-changeOtherDomainAction"];
}

-(NSInteger) selectedOthersearchDomainIndex {
    return selectedSearchDomainIndex;
}

-(void) setSelectedOthersearchDomainIndex: (NSInteger) newValue {
    [self setDnsWinsIndex: &selectedSearchDomainIndex to: newValue preference: @"-changeOtherSearchDomainAction"];
}

-(NSInteger) selectedOtherwinsServersIndex {
    return selectedWinsServersIndex;
}

-(void) setSelectedOtherwinsServersIndex: (NSInteger) newValue {
    [self setDnsWinsIndex: &selectedWinsServersIndex to: newValue preference: @"-changeOtherWINSServersAction"];
}

-(NSInteger) selectedOthernetBiosNameIndex {
    return selectedNetBiosNameIndex;
}

-(void) setSelectedOthernetBiosNameIndex: (NSInteger) newValue {
    [self setDnsWinsIndex: &selectedNetBiosNameIndex to: newValue preference: @"-changeOtherNetBIOSNameAction"];
}

-(NSInteger) selectedOtherworkgroupIndex {
    return selectedWorkgroupIndex;
}

-(void) setSelectedOtherworkgroupIndex: (NSInteger) newValue {
    [self setDnsWinsIndex: &selectedWorkgroupIndex to: newValue preference: @"-changeOtherWorkgroupAction"];
}

-(void) setDnsWinsIndex: (NSInteger *) index
                     to: (NSInteger)   newValue
             preference: (NSString *)  key {
    if (  ! doNotModifyPreferences  ) {
        NSString * newSetting = nil;
        switch (  newValue  ) {
            case 0:
                newSetting = @"ignore";
                break;
            case 1:
                newSetting = @"restore";
                break;
            case 2:
                newSetting = @"restart";
                break;
            default:
                NSLog(@"setDnsWinsIndex: ignoring invalid value %ld", (long) newValue);
        }
        if (  newSetting != nil  ) {
            NSString * defaultValue;
            if (  [key hasPrefix: @"-changeOther"]  ) {
                defaultValue = @"restart";
            } else {
                defaultValue = @"restore";
            }
            
            NSString * actualKey = [configurationName stringByAppendingString: key];
            if (  [newSetting isEqualToString: defaultValue]  ) {
                [gTbDefaults removeObjectForKey: actualKey];
            } else {
                [gTbDefaults setObject: newSetting forKey: actualKey];
            }
        }
    }
    
    *index = newValue;
}

-(NSUInteger) selectedCredentialsGroupIndex {
	return (unsigned)selectedCredentialsGroupIndex;
}

-(void) setSelectedCredentialsGroupIndex: (NSUInteger) newValue {
    NSArray * contents = [credentialsGroupArrayController content];
    NSUInteger size = [contents count];
    if (  newValue < size  ) {
        NSString * prefKey = [configurationName stringByAppendingString: @"-credentialsGroup"];
        if (  newValue == 0) {
			[gTbDefaults removeObjectForKey: prefKey];
        } else {
            NSString * groupValue = [[contents objectAtIndex: newValue] objectForKey: @"value"];
			NSArray * groups = [gTbDefaults sortedCredentialsGroups];
            if (  [groups containsObject: groupValue]  ) {
				[gTbDefaults setObject: groupValue forKey: prefKey];
			} else {
                NSLog(@"'%@' credentials are not available", groupValue);
            }
        }
		selectedCredentialsGroupIndex = (int)newValue;
		[connection initializeAuthAgent];
		
    } else if (  size != 0  ) {
        NSLog(@"setSelectedCredentialsGroupIndex: %ld but there are only %ld sounds", (long) newValue, (long) size);
    }
}

-(void) bringToFront2
{
	NSLog(@"activate/makeKeyAndOrderFront; window = %@", [self window]);
	[NSApp activateIgnoringOtherApps: YES];
	[[self window] display];
	[self showWindow: self];
	[[self window] makeKeyAndOrderFront: self];
}

-(void) bringToFront1
{
	[self performSelectorOnMainThread: @selector(bringToFront2) withObject: nil waitUntilDone: NO];
}

-(void) removeNamedCredentialsCommand: (id) sender {
    unsigned ix = (unsigned)[sender tag];
    NSString * groupName = [removeNamedCredentialsNames objectAtIndex: ix];
	int result = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
								 [NSString stringWithFormat:
								  NSLocalizedString(@"Do you wish to delete the %@ credentials?", @"Window text"),
								  groupName],
								 NSLocalizedString(@"Cancel", @"Button"),    // Default button
								 NSLocalizedString(@"Delete", @"Button"),    // Alternate button
								 nil);
	
	if (  result == NSAlertDefaultReturn  ) {
		return;
	}
    
	NSString * errMsg = [gTbDefaults removeNamedCredentialsGroup: groupName];
	if (  errMsg  ) {
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                        [NSString stringWithFormat:
						 NSLocalizedString(@"The credentials named %@ could not be removed:\n\n%@", @"Window text"),
						 groupName,
						 errMsg],
                        nil, nil, nil);
	} else {
		[self initializeStaticContent];
		[self setupSettingsFromPreferences];
		[self performSelectorOnMainThread: @selector(bringToFront1) withObject: nil waitUntilDone: NO];
	}
}

-(IBAction) allConfigurationsUseTheSameCredentialsCheckboxWasClicked: (id) sender {
	NSString * prefKey = @"namedCredentialsThatAllConfigurationsUse";
	if (  [gTbDefaults canChangeValueForKey: prefKey]  ) {
		if (  [sender state] == NSOffState) {
			[gTbDefaults removeObjectForKey: prefKey];
		} else {
			NSString * name = [removeNamedCredentialsNames objectAtIndex: 0];
			[gTbDefaults setObject: name forKey: prefKey];
		}
		[self setupSettingsFromPreferences];
	} else {
		NSLog(@"allConfigurationsUseTheSameCredentialsCheckboxWasClicked: but the '%@' preference is forced.", prefKey);
	}
}

-(IBAction) addNamedCredentialsButtonWasClicked: (id) sender {
	(void) sender;
	
	NSString * msg = NSLocalizedString(@"Please enter a name for the credentials:\n\n", @"Window text");
	NSString * newName = @"";
	while (  newName  ) {
		newName = TBGetString(msg, newName);
		if (   newName
			&& ([newName length] > 0)  ) {
			if (  invalidConfigurationName(newName)  ) {
				msg = [NSString stringWithFormat:
					   NSLocalizedString(@"Names may not include any of the following characters: %s\n\nPlease enter a name for the new credentials:\n\n", @"Window text"),
					   PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING];
			} else {
				NSString * errMsg = [gTbDefaults addNamedCredentialsGroup: newName];
				if (  errMsg  ) {
					TBRunAlertPanel(NSLocalizedString(@"Warning!", @"Window title"),
                                    [NSString stringWithFormat:
                                     NSLocalizedString(@"The credentials named %@ could not be added:\n\n%@", @"Window text"),
                                     newName,
                                     errMsg],
                                    nil, nil, nil);
				} else {
					[self initializeStaticContent];
					[self setupSettingsFromPreferences];
				}
				
				[self performSelectorOnMainThread: @selector(bringToFront1) withObject: nil waitUntilDone: NO];
				return;
			}
		}
	}
}

-(IBAction) whileConnectedHelpButtonWasClicked: (id) sender {
	(void) sender;
	
    OSStatus err;
    if ((err = MyGotoHelpPage(CFSTR("vpn-details-advanced-connecting-disconnecting.html"), NULL))  ) {
        NSLog(@"Error %ld from MyGotoHelpPage()", (long) err);
    }
}

-(IBAction) vpnCredentialsHelpButtonWasClicked: (id) sender {
	(void) sender;
	
    OSStatus err;
    if ((err = MyGotoHelpPage(CFSTR("vpn-details-advanced-connecting-disconnecting.html"), NULL))  ) {
        NSLog(@"Error %ld from MyGotoHelpPage()", (long) err);
    }
}

// General methods

// Set a checkbox from preferences
-(void) setupCheckbox: (NSButton *) checkbox
                  key: (NSString *) key
             inverted: (BOOL) inverted {
    NSString * actualKey = [configurationName stringByAppendingString: key];
    BOOL state = [gTbDefaults boolForKey: actualKey];
    if (  inverted  ) {
        state = ! state;
    }
    if (  state  ) {
        [checkbox setState: NSOnState];
    } else {
        [checkbox setState: NSOffState];
    }
    
    BOOL enable = [gTbDefaults canChangeValueForKey: actualKey];
    [checkbox setEnabled: enable];
}

TBSYNTHESIZE_OBJECT(retain, VPNConnection *,         connection, setConnection)
TBSYNTHESIZE_OBJECT(retain, NSArray *,               removeNamedCredentialsNames, setRemoveNamedCredentialsNames)

TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,     connectingAndDisconnectingTabViewItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,     whileConnectedTabViewItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,     credentialsTabViewItem)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *, allConfigurationsUseTheSameCredentialsCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSBox *, namedCredentialsBox)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          credentialsGroupButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *, credentialsGroupArrayController)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *, addNamedCredentialsButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            removeNamedCredentialsButton)

@end
