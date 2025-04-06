/*
 * Copyright 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020 Jonathan K. Bullard. All rights reserved.
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
#import "helper.h"
#import "sharedRoutines.h"

#import "ConfigurationManager.h"
#import "MenuController.h"
#import "MyPrefsWindowController.h"
#import "NSFileManager+TB.h"
#import "TBButton.h"
#import "TBOperationQueue.h"
#import "TBPopUpButton.h"
#import "TBUserDefaults.h"
#import "UIHelper.h"
#import "VPNConnection.h"
#import "SystemAuth.h"
#import "TunnelblickInfo.h"

extern NSFileManager  * gFileMgr;
extern MenuController * gMC;
extern NSString       * gPrivatePath;
extern TBUserDefaults * gTbDefaults;
extern TunnelblickInfo * gTbInfo;

@interface SettingsSheetWindowController()    // Private methods

//**********************************************************************************************************************************
// Methods that set up static content (content that is the same for all connections)

-(void) initializeStaticContent;

//**********************************************************************************************************************************
// Methods that set up up content that depends on a connection's settings

// Overall set up
-(void) setupSettingsFromPreferences;

// Methods for setting up specific types of information

-(void) setupCheckbox: (TBButton *) checkbox
                  key: (NSString *)     key
             inverted: (BOOL)           inverted;

-(void) setupMonitoringOptions;

-(NSInteger) indexForMonitoringOptionButton: (NSPopUpButton *) button
                              newPreference: (NSString *)      preference
                              oldPreference: (NSString *)      oldPreference
                      leasewatchOptionsChar: (NSString *)      leasewatchOptionsChar;
@end


@implementation SettingsSheetWindowController

TBSYNTHESIZE_NONOBJECT_GET(BOOL, showingSettingsSheet)

TBSYNTHESIZE_OBJECT(retain, VPNConnection *, connection,                setConnection)

TBSYNTHESIZE_OBJECT(retain, NSArray *,  removeNamedCredentialsNames,    setRemoveNamedCredentialsNames)

TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedDnsServersIndex,        setSelectedDnsServersIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedDomainIndex,            setSelectedDomainIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedSearchDomainIndex,      setSelectedSearchDomainIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedWinsServersIndex,       setSelectedWinsServersIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedNetBiosNameIndex,       setSelectedNetBiosNameIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedWorkgroupIndex,         setSelectedWorkgroupIndexDirect)

TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedOtherdnsServersIndex,   setSelectedOtherdnsServersIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedOtherdomainIndex,       setSelectedOtherdomainIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedOthersearchDomainIndex, setSelectedOthersearchDomainIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedOtherwinsServersIndex,  setSelectedOtherwinsServersIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedOthernetBiosNameIndex,  setSelectedOthernetBiosNameIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedOtherworkgroupIndex,    setSelectedOtherworkgroupIndexDirect)

TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedCredentialsGroupIndex,  setSelectedCredentialsGroupIndexDirect)

TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedSoundOnConnectIndex,          setSelectedSoundOnConnectIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedSoundOnDisconnectIndex,       setSelectedSoundOnDisconnectIndexDirect)

TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,     connectingAndDisconnectingTabViewItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,     whileConnectedTabViewItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,     credentialsTabViewItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,     soundTabViewItem)

TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,      allConfigurationsUseTheSameCredentialsCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSBox *,             namedCredentialsBox)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          credentialsGroupButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *, credentialsGroupArrayController)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          addNamedCredentialsButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          removeNamedCredentialsButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSBox *,             alertSoundsBox)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,   connectionAlertSoundTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,   disconnectionAlertSoundTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          soundOnConnectButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          soundOnDisconnectButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *, soundOnConnectArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *, soundOnDisconnectArrayController)

-(id) init {
    self = [super initWithWindowNibName: [UIHelper appendRTLIfRTLLanguage: @"SettingsSheet"]];
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
	
	[configurationName           release]; configurationName           = nil;
	[connection                  release]; connection                  = nil;
	[removeNamedCredentialsNames release]; removeNamedCredentialsNames = nil;
	
	[super dealloc];
}

-(void) setConfigurationName: (NSString *) newName {
    
    if (  ! [configurationName isEqualToString: newName]  ) {
        [configurationName release];
        configurationName = [newName retain];
		
		if (  newName  ) {
			[self setConnection: [gMC connectionForDisplayName: configurationName]];
		} else {
			[self setConnection: nil];
		}
		
		if (  showingSettingsSheet  ) {
			[self initializeStaticContent];
			[self setupSettingsFromPreferences];
		}
	}
}


-(BOOL) usingSmartSetNameserverScript {
    
    if (  ! configurationName  ) {
        return FALSE;
    }
    
    NSString * key = [configurationName stringByAppendingString: @"useDNS"];
    unsigned ix = [gTbDefaults unsignedIntForKey: key
                                         default: 1
                                             min: 0
                                             max: MAX_SET_DNS_WINS_INDEX];
    return (ix == 1) || (ix == 5);
}

- (void) setupCredentialsGroupButton {
    
    if (  ! configurationName  ) {
        return;
    }
    
	BOOL savedDoingSetupOfUI = [gMC doingSetupOfUI];
	[gMC setDoingSetupOfUI: TRUE];
	
	[self setSelectedCredentialsGroupIndexDirect: [NSNumber numberWithUnsignedInteger: NSNotFound]];
	
	NSInteger ix = 0;
	NSString * prefKey = [configurationName stringByAppendingString: @"-credentialsGroup"];
	NSString * group = [gTbDefaults stringForKey: prefKey];
	if (   [group length] != 0  ) {
        NSArray * listContent = [credentialsGroupArrayController content];
        NSDictionary * dict;
        unsigned i;
        ix = NSNotFound;
        for (  i=0; i<[listContent count]; i++  ) { 
            dict = [listContent objectAtIndex: i];
            if (  [[dict objectForKey: @"value"] isEqualToString: group]  ) {
                ix = (int)i;
                break;
            }
        }
        
        if (  ix == NSNotFound  ) {
            NSLog(@"Preference '%@' ignored: credentials group '%@' was not found", prefKey, group);
            ix = 0;
        }
	}
	
	[self setSelectedCredentialsGroupIndex: [NSNumber numberWithUnsignedInteger: ix]];
	[credentialsGroupButton setEnabled: (   ( ! [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"] )
                                         && [gTbDefaults canChangeValueForKey: prefKey])];
	
	[gMC setDoingSetupOfUI: savedDoingSetupOfUI];
}

- (void) setupPrependDomainNameCheckbox {
    
    if (  ! configurationName  ) {
        return;
    }
    
    if (  [self usingSmartSetNameserverScript]  ) {
        [self setupCheckbox: prependDomainNameCheckbox
                        key: @"-prependDomainNameToSearchDomains"
                   inverted: NO];
    } else {
        [prependDomainNameCheckbox setState:   NSOffState];
        [prependDomainNameCheckbox setEnabled: NO];
    }
}

-(void) setupFlushDNSCheckbox {
    
    if (  ! configurationName  ) {
        return;
    }
    
    if (  [self usingSmartSetNameserverScript]  ) {
        [self setupCheckbox: flushDnsCacheCheckbox
                        key: @"-doNotFlushCache"
                   inverted: YES];
    } else {
        [flushDnsCacheCheckbox setState:   NSOffState];
        [flushDnsCacheCheckbox setEnabled: NO];
    }
}

-(void) setupAllowManualNetworkSettingsOverrideCheckbox {
	
	if (  ! configurationName  ) {
		return;
	}
	
	if (  [self usingSmartSetNameserverScript]  ) {
		[self setupCheckbox: allowManualNetworkSettingsOverrideCheckbox
						key: @"-allowChangesToManuallySetNetworkSettings"
				   inverted: NO];
	} else {
		[allowManualNetworkSettingsOverrideCheckbox setState:   NSOffState];
		[allowManualNetworkSettingsOverrideCheckbox setEnabled: NO];
	}
}

-(void) setupKeepConnectedCheckbox {
    
    if (  ! configurationName  ) {
        return;
    }
    
    [self setupCheckbox: keepConnectedCheckbox
                    key: @"-keepConnected"
               inverted: NO];
}

-(void) setupEnableIpv6OnTapCheckbox {
    
    if (  ! configurationName  ) {
        return;
    }
    
    NSString * type = [connection tapOrTun];
    if (   (   ( ! type )
			|| [type containsString: @"tun"]  )
		|| ( ! [self usingSmartSetNameserverScript] )  ) {
        [enableIpv6OnTapCheckbox setState: NSOffState];
        [enableIpv6OnTapCheckbox setEnabled: NO];
    } else {
        [self setupCheckbox: enableIpv6OnTapCheckbox
                        key: @"-enableIpv6OnTap"
                   inverted: NO];
    }
}

-(void) setupUseRouteUpInsteadOfUpCheckbox {
    
    if (  ! configurationName  ) {
        return;
    }
    
	[self setupCheckbox: useRouteUpInsteadOfUpCheckbox
					key: @"-useUpInsteadOfRouteUp"
			   inverted: YES];
}

- (void) setupDisconnectOnSleepCheckbox {
    
    if (  ! connection  ) {
        return;
    }
    
    [self setupCheckbox: disconnectOnSleepCheckbox
                    key: @"-doNotDisconnectOnSleep"
               inverted: YES];
}

- (void) setupReconnectOnWakeFromSleepCheckbox {
    
    if (  ! connection  ) {
        return;
    }
    
    if (  [gTbDefaults boolForKey: [[connection displayName] stringByAppendingString: @"-doNotDisconnectOnSleep"]] ) {
        [reconnectOnWakeFromSleepCheckbox setState:   NSOffState];
        [reconnectOnWakeFromSleepCheckbox setEnabled: NO];
    } else {
        [self setupCheckbox: reconnectOnWakeFromSleepCheckbox
                        key: @"-doNotReconnectOnWakeFromSleep"
                   inverted: YES];
    }
}

- (void) setupRunMtuTestCheckbox {
    
    if (  ! connection  ) {
        return;
    }
    
    [self setupCheckbox: runMtuTestCheckbox
                    key: @"-runMtuTest"
               inverted: NO];
}

- (void) setupTunOrTapButton: (TBPopUpButton *) button key: (NSString *) rawPreferenceKey {
	
    if (  ! connection  ) {
        return;
    }
    
	NSString * key   = [configurationName stringByAppendingString: rawPreferenceKey];
	NSString * value = [gTbDefaults stringForKey: key];

    NSInteger index; // 0 = automatic; 1 = always; 2 = never
    
	if (  [value length] == 0  ) {
		index = 0;
	} else if (  [value isEqualToString: @"always"]  ) {
		index = 1;
	} else if (  [value isEqualToString: @"never"]  ) {
		index = 2;
	} else {
		NSLog(@"setupTunTapButton: Value '%@' for preference '%@' is invalid; assuming 'always'", value, key);
		index = 1;
	}

    // Some future version of macOS may not allow installing our kexts, and presumably won't allow loading/unloading of them.
    // But let users override and try to install/load/unload kexts by setting the "tryToLoadKextsOnThisVersionOfMacOS" preference to true

    BOOL enabled = TRUE;

    if (  ! gTbInfo.systemVersionCanLoadKexts  ) {
        if (  index != 2  ) {
            if (  ! [gTbDefaults boolForKey: @"tryToLoadKextsOnThisVersionOfMacOS"]  ) {
                NSLog(@"Not loading kexts on this version of macOS, so showing 'never' and ignoring '%@' for '%@' for '%@' and disabling the button", value, rawPreferenceKey, key);
                index = 2;
                enabled = FALSE;
            }
        }
    }

    [button selectItemAtIndex: index];
    [button setEnabled: enabled];
}

-(void) setupTunTapButtons {
	[self setupTunOrTapButton: loadTunPopUpButton key: @"-loadTun"];
	[self setupTunOrTapButton: loadTapPopUpButton key: @"-loadTap"];
}

//  Set up a sound popup button from preferences
-(void) setupSoundButton: (NSButton *)          button
         arrayController: (NSArrayController *) ac
              preference: (NSString *)          preference {
    if (   connection
		&& button
		&& ac
		&& preference  ) {
        NSUInteger ix = NSNotFound;
        NSString * key = [[connection displayName] stringByAppendingString: preference];
        NSString * soundName = [gTbDefaults stringForKey: key];
        if (   soundName
            && ( ! [soundName isEqualToString: @"None"] )  ) {
            NSArray * listContent = [ac content];
            NSDictionary * dict;
            unsigned i;
            for (  i=0; i<[listContent count]; i++  ) {  // Look for the sound in the array
                dict = [listContent objectAtIndex: i];
                if (  [[dict objectForKey: @"name"] isEqualToString: soundName]  ) {
                    ix = i;
                    break;
                }
            }
            
            if (  ix == NSNotFound  ) {
                NSLog(@"Preference '%@' ignored: sound '%@' was not found", key, soundName);
                ix = 0;
            }
        } else {
            ix = 0;
        }
        
        //******************************************************************************
        // Don't play sounds because we are just setting the button from the preferences
        BOOL oldDoNotPlaySounds = doNotPlaySounds;
        doNotPlaySounds = TRUE;
        
        if (  button == [self soundOnConnectButton]) {
            [self setSelectedSoundOnConnectIndex:    [NSNumber numberWithUnsignedInteger: ix]];
        } else {
            [self setSelectedSoundOnDisconnectIndex: [NSNumber numberWithUnsignedInteger: ix]];
        }
        
        doNotPlaySounds = oldDoNotPlaySounds;
        //******************************************************************************
        
        BOOL enable = [gTbDefaults canChangeValueForKey: key];
        [button setEnabled: enable];
    } else {
        [[self soundOnConnectButton]             setEnabled: NO];
        [[self soundOnDisconnectButton]          setEnabled: NO];
    }
}

-(void) setupSoundPopUpButtons {
    
    [self setupSoundButton: [self soundOnConnectButton]
           arrayController: [self soundOnConnectArrayController]
                preference: @"-tunnelUpSoundName"];
    
    
    [self setupSoundButton: [self soundOnDisconnectButton]
           arrayController: [self soundOnDisconnectArrayController]
                preference: @"-tunnelDownSoundName"];
}


-(void) showSettingsSheet: (id) sender {
	(void) sender;
	
    if (  ! settingsSheet  ) {
        [super showWindow: self];
    } else {
        showingSettingsSheet = TRUE;
    }
    
    [[self window] display];
    [[self window] makeKeyAndOrderFront: self];
    [gMC activateIgnoringOtherApps];
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
	NSString * advancedTabIdentifier = [gTbDefaults stringForKey: @"AdvancedWindowTabIdentifier"];
	if (  advancedTabIdentifier  ) {
		[tabView selectTabViewItemWithIdentifier: advancedTabIdentifier];
	}
	
    [[self window] setReleasedWhenClosed: NO];
}

-(void) windowWillClose:(NSNotification *)notification {
	
	(void)notification;
	
	NSString * advancedTabIdentifier = [[tabView selectedTabViewItem] identifier];
	if (  ! [advancedTabIdentifier isEqualToString: [gTbDefaults stringForKey: @"AdvancedWindowTabIdentifier"]]  ) {
		[gTbDefaults setObject: advancedTabIdentifier forKey: @"AdvancedWindowTabIdentifier"];
        [[NSUserDefaults standardUserDefaults] synchronize];
	}
}


//**********************************************************************************************************************************

-(void) underlineLabel: tf string: inString alignment: (NSTextAlignment) align {
	
    NSMutableAttributedString* attrString = [[NSMutableAttributedString alloc] initWithString: inString];
    NSRange range = NSMakeRange(0, [attrString length]);
    
    [attrString beginEditing];
    
    // make the text appear with an underline
    [attrString addAttribute:
     NSUnderlineStyleAttributeName value:[NSNumber numberWithInt:NSSingleUnderlineStyle] range:range];
    
    // make the text appear flush-right or flush-left
    [attrString setAlignment: align range: range];
    
    [attrString endEditing];
    
    [tf setAttributedStringValue: attrString];
    [attrString release];
}

-(CGFloat) initializeDnsWinsPopUp: (NSPopUpButton *) popUpButton arrayController: (NSArrayController *) ac {
    NSArray * content = [NSArray arrayWithObjects:
                         [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Ignore"            , @"Button"), @"name", @"ignore" , @"value", nil],
                         [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Restore"           , @"Button"), @"name", @"restore", @"value", nil],
                         [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Restart connection", @"Button"), @"name", @"restart", @"value", nil],
                         nil];
    [ac setContent: content];
    
	BOOL rtl = [UIHelper languageAtLaunchWasRTL];
	CGFloat widthChange = [UIHelper setTitle: nil ofControl: popUpButton shift: rtl narrow: YES enable: YES];
	return widthChange;
}

-(void) initializeSoundPopUpButtons {
	
    NSArray * soundsSorted = [gMC sortedSounds];
    
    // Create an array of dictionaries of sounds. (Don't get the actual sounds, just the names of the sounds)
    NSMutableArray * soundsDictionaryArray = [NSMutableArray arrayWithCapacity: [soundsSorted count]];
    
    [soundsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                       NSLocalizedString(@"No sound", @"Button"), @"name",
                                       @"None", @"value", nil]];
    
    [soundsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                       NSLocalizedString(@"Speak", @"Button"), @"name",
                                       @"Speak", @"value", nil]];
    
    unsigned i;
    for (  i=0; i<[soundsSorted count]; i++  ) {
        [soundsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                           [soundsSorted objectAtIndex: i], @"name",
                                           [soundsSorted objectAtIndex: i], @"value", nil]];
    }
    
	NSArrayController * connectController = [self soundOnConnectArrayController];
    [connectController setContent: soundsDictionaryArray];
	NSArrayController * disconnectController = [self soundOnDisconnectArrayController];
    [disconnectController setContent: soundsDictionaryArray];
	
	BOOL rtl = [UIHelper languageAtLaunchWasRTL];
	
	[UIHelper setTitle: nil ofControl: soundOnConnectButton    shift: rtl narrow: YES enable: YES];
	[UIHelper setTitle: nil ofControl: soundOnDisconnectButton shift: rtl narrow: YES enable: YES];
	
	NSArray * list = [NSArray arrayWithObjects: soundOnConnectButton, soundOnDisconnectButton, nil];
	[UIHelper makeAllAsWideAsWidest: list shift: rtl];
}

-(void) initializeStaticContent {
    
    // For Connecting tab
	
	BOOL rtl = [UIHelper languageAtLaunchWasRTL];
	
    [connectingAndDisconnectingTabViewItem setLabel: NSLocalizedString(@"Connecting & Disconnecting", @"Window title")];
    
	[flushDnsCacheCheckbox
	  setTitle: NSLocalizedString(@"Flush DNS cache after connecting or disconnecting", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>The DNS cache contains copies of DNS (Domain Name System) information.</p>\n"
														   @"<p><strong>When checked</strong>, the DNS cache will be flushed (cleared) after"
														   @" connecting or disconnecting. All DNS lookups will be performed by the name server specified by the VPN setup.</p>\n"
														   @"<p><strong>When not checked</strong>, the DNS cache will not be flushed. This can cause problems if"
														   @" there are name conflicts between the name server specified by the VPN setup and the pre-VPN name server and if pre-VPN entries have been cached.</p>",
														   @"HTML info for the 'Flush DNS cache after connecting or disconnecting' checkbox."))];
	
	[allowManualNetworkSettingsOverrideCheckbox
	 setTitle: NSLocalizedString(@"Allow changes to manually-set network settings", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, network settings which were set manually may be changed when the VPN connects. This will only happen if changes are specified by options in the OpenVPN configuration file or from the OpenVPN server.</p>\n"
														   @"<p><strong>When not checked</strong>, network settings which were set manually will not be changed when the VPN connects.</p>",
														   @"HTML info for the 'Allow changes to manually-set network settings' checkbox."))];
	
	[prependDomainNameCheckbox
	  setTitle: NSLocalizedString(@"Prepend domain name to search domains", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, the VPN-specified domain name will be added to the start of the search domain list.</p>\n"
														   @"<p><strong>When not checked</strong>, the search domain list will be replaced by the VPN-specified domain name.</p>",
														   @"HTML info for the 'Prepend domain name to search domains' checkbox."))];
	
	[useRouteUpInsteadOfUpCheckbox
	  setTitle: NSLocalizedString(@"Set DNS after routes are set", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, OpenVPN will modify DNS and other settings after"
														   @" it sets up routing for the VPN instead of before setting up the routing.</p>\n"
														   @"<p><strong>When not checked</strong>, OpenVPN will modify DNS and other settings before it sets up"
														   @" routing for the VPN, instead of after setting up the routing. This can cause DNS failures"
														   @" or delays if the routes take a long time to set up -- for example, if there are many routes to set up.</p>\n",
														   @"HTML info for the 'Set DNS after routes are set' checkbox."))];
	
	[enableIpv6OnTapCheckbox
	  setTitle: NSLocalizedString(@"Enable IPv6 (tap only)", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, IPv6 will be enabled.</p>\n"
														   @"<p><strong>When not checked</strong>, IPv6 will not be enabled.</p>\n"
														   @"<p>Disabling IPv6 is often recommended because many VPN configurations do not guard against information leaks caused by the use"
														   @" of IPv6. Most Internet access works fine without IPv6.</p>\n"
														   @"<p><strong>This checkbox is disabled</strong> for Tun configurations.</p>",
														   @"HTML info for the 'Enable IPv6 (tap only)' checkbox."))];
    
	[keepConnectedCheckbox
	  setTitle: NSLocalizedString(@"Keep connected", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, if OpenVPN exits unexpectedly (crashes), Tunnelblick will attempt to connect the VPN again.</p>\n"
														   @"<p><strong>When not checked</strong>, Tunnelblick will not try to connect the VPN if OpenVPN exits unexpectedly.</p>\n",
														   @"HTML info for the 'Keep connected' checkbox."))];
	
	[loadTunAutomaticallyMenuItem setTitle: NSLocalizedString(@"Load Tun driver automatically", @"Button")];
	[loadTunAlwaysMenuItem        setTitle: NSLocalizedString(@"Always load Tun driver",        @"Button")];
	[loadTunNeverMenuItem         setTitle: NSLocalizedString(@"Never load Tun driver",         @"Button")];
	
	[loadTapAutomaticallyMenuItem setTitle: NSLocalizedString(@"Load Tap driver automatically", @"Button")];
	[loadTapAlwaysMenuItem        setTitle: NSLocalizedString(@"Always load Tap driver",        @"Button")];
	[loadTapNeverMenuItem         setTitle: NSLocalizedString(@"Never load Tap driver",         @"Button")];
	
    [loadTunPopUpButton setTitle: nil
                       infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>A 'tun' device driver is needed for Tun connections. Usually the system's Tun driver is used,"
                                                                             @" but Tunnelblick also includes its own Tun driver. If you have installed a different Tun driver, Tunnelblick may not be able to load its driver.</p>\n"
                                                                             @"<p>OpenVPN will use the system's driver unless the OpenVPN configuration includes the 'dev-type tun' option.</p>\n"
                                                                             @"<p>You can choose if and when Tunnelblick loads its Tun driver:</p>\n"
                                                                             @"<p><strong>Load Tun driver automatically</strong>: Tunnelblick loads its driver if it is needed and unloads it when it is no longer needed."
                                                                             @" (Tunnelblick will only load its driver if the OpenVPN configuration includes the 'dev-type tun' option.)</p>\n"
                                                                             @"<p><strong>Always load Tun driver</strong>: Tunnelblick loads its driver when it connects this configuration, and unloads it when it is no longer needed.</p>\n"
                                                                             @"<p><strong>Never load Tun driver</strong>: Tunnelblick never loads its driver.</p>\n"
                                                                             @"<p><strong>This checkbox is disabled</strong> for Tap configurations and on versions of macOS which do not allow Tunnelblick to load its Tun driver."
                                                                             @" For more information, see <a href=\"https://tunnelblick.net/cTunTapConnections.html\">Tun and Tap VPNs on macOS [tunnelblick.net]</a>.</p>",
                                                                             @"HTML info for the 'Load Tun driver' popdown list."))];
	[UIHelper setTitle: nil
			 ofControl: loadTunPopUpButton
				 shift: [UIHelper languageAtLaunchWasRTL]
				narrow: YES
				enable: YES];

	[loadTapPopUpButton setTitle: nil
					   infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>A 'tap' device driver is needed for Tap connections. Tunnelblick includes its own Tap driver because the system does not include one."
																			 @" If you have installed a different Tap driver, Tunnelblick may not be able to load its driver.</p>"
																			 @"<p>You can choose if and when Tunnelblick loads its driver:</p>\n"
																			 @"<p><strong>Load Tap driver automatically</strong>: Tunnelblick loads its driver if it is needed and unloads it when it is no longer needed.</p>\n"
																			 @"<p><strong>Always load Tap driver</strong>: Tunnelblick loads its driver when it connects this configuration, and unloads it when it is no longer needed.</p>\n"
																			 @"<p><strong>Never load Tap driver</strong>: Tunnelblick never loads its driver.</p>\n"
                                                                             @"<p><strong>This checkbox is disabled</strong> for Tun configurations and on versions of macOS which do not allow Tunnelblick to load its Tap driver."
                                                                             @" For more information, see <a href=\"https://tunnelblick.net/cTunTapConnections.html\">Tun and Tap VPNs on macOS [tunnelblick.net]</a>.</p>",
																			 @"HTML info for the 'Load Tap driver' popdown list."))];
	[UIHelper setTitle: nil
			 ofControl: loadTapPopUpButton
				 shift: [UIHelper languageAtLaunchWasRTL]
				narrow: YES
				enable: YES];
	
	[sleepWakeBox setTitle: NSLocalizedString(@"Computer sleep/wake",                        @"Window text")];
	[ifConnectedWhenComputerWentToSleepTFC setTitle: NSLocalizedString(@"(if connected when computer went to sleep)", @"Window text")];
	
	[fastUserSwitchingBox setTitle: NSLocalizedString(@"Fast User Switching",                   @"Window text")];
	[ifConnectedWhenUserSwitchedOutTFC setTitle: NSLocalizedString(@"(if connected when user switched out)", @"Window text")];
	
	[disconnectOnSleepCheckbox
	  setTitle: NSLocalizedString(@"Disconnect when computer goes to sleep", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, the VPN will be disconnected when the computer goes to sleep.</p>\n"
														   @"<p><strong>When not checked</strong>, the VPN will stay connected when the computer goes to sleep.</p>",
														   @"HTML info for the 'Disconnect when computer goes to sleep' checkbox."))];
    [authenticateOnConnectCheckbox setTitle: NSLocalizedString(@"Authenticate before connecting", @"Checkbox name")
                                  infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, you will be required to authenticate yourself before connecting. You can authenticate yourself by using your password or, if available, TouchID or FaceID.</p>\n"
                                                                                        @"<p><strong>When not checked</strong>, no authentication will be required before connecting.</p>\n"
                                                                                        @"<p><strong>This checkbox is disabled</strong> if you are using a version of macOS that does not support it.</p>"
                                                                                        @"<p><strong>Note: A computer administrator's authorization is required to change this setting.</strong></p>",
                                                                                        @"HTML info for the 'Authenticate before connecting' checkbox."))];
	
	[reconnectOnWakeFromSleepCheckbox
	  setTitle: NSLocalizedString(@"Reconnect when computer wakes up", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, the VPN will be reconnected when the computer wakes up if it was disconnected when the computer went to sleep.</p>\n"
														   @"<p><strong>When not checked</strong>, the VPN will not be reconnected when the computer wakes up.</p>",
														   @"HTML info for the 'Reconnect when computer wakes up' checkbox."))];
	
	[disconnectWhenUserSwitchesOutCheckbox
	  setTitle: NSLocalizedString(@"Disconnect when user switches out", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, the VPN will be disconnected when switching to another user.</p>\n"
														   @"<p><strong>When not checked</strong>, the VPN will not be disconnected when switching to another user.</p>",
														   @"HTML info for the 'Disconnect when user switches out' checkbox."))];
	
	[reconnectWhenUserSwitchesInCheckbox
	  setTitle: NSLocalizedString(@"Reconnect when user switches in", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, the VPN will be reconnected when switching back to the current user if it was disconnected when a switch to another user was done.</p>\n"
														   @"<p><strong>When not checked</strong>, the VPN will not be reconnected when switching back to the current user.</p>",
														   @"HTML info for the 'Reconnect when user switches in' checkbox."))];
	
	// For WhileConnected tab
	
	[runMtuTestCheckbox
	  setTitle: NSLocalizedString(@"Run MTU maximum size test after connecting", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, OpenVPN will run a test to determine the"
														   @" maximum MTU size for the connection. The test starts each time a connection is made,"
														   @" and can take several minutes. Test results appear in the Tunnelblick log.</p>\n",
														   @"HTML info for the 'Run MTU maximum size test after connecting' checkbox."))];
	
	[whileConnectedTabViewItem setLabel: NSLocalizedString(@"While Connected", @"Window title")];
	
	[monitorNetworkForChangesCheckbox
	  setTitle: NSLocalizedString(@"Monitor network settings", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, Tunnelblick will watch for and react to changes in network"
														   @" settings (for example, changes caused by DHCP renewals or switching Internet connections) to attempt to keep the VPN connected. Tunnelblick's default actions when network"
														   @" settings change usually work well, but you may specify different actions on the 'While Connected' tab of the 'Advanced' settings window.</p>\n"
														   @"<p><strong>When not checked</strong>, Tunnelblick will ignore network changes.</p>\n"
														   @"<p><strong>This checkbox is disabled</strong> when 'Set DNS/WINS' is not set to 'Set nameserver' or 'Set nameserver (3.1)'.</p>",
														   @"HTML info for the 'Monitor network settings' checkbox."))];
	
	NSTextAlignment alignmentForNetworkSettingString = (  rtl
														? NSLeftTextAlignment
														: NSRightTextAlignment);
	NSTextAlignment alignmentForOtherStrings = (  rtl
												? NSRightTextAlignment
												: NSLeftTextAlignment);
    [self underlineLabel: networkSettingTF            string: NSLocalizedString(@"Network setting"              , @"Window text") alignment: alignmentForNetworkSettingString];
    [self underlineLabel: whenChangesToPreVpnValueTF  string: NSLocalizedString(@"When changes to pre-VPN value", @"Window text") alignment: alignmentForOtherStrings];
    [self underlineLabel: whenChangesToAnythingElseTF string: NSLocalizedString(@"When changes to anything else", @"Window text") alignment: alignmentForOtherStrings];
    
    [dnsServersTFC   setTitle: NSLocalizedString(@"DNS servers:"  , @"Window text")];
    [domainTFC       setTitle: NSLocalizedString(@"Domain:"       , @"Window text")];
    [searchDomainTFC setTitle: NSLocalizedString(@"Search domain:", @"Window text")];
    [winsServersTFC  setTitle: NSLocalizedString(@"WINS servers:" , @"Window text")];
    [netBiosNameTFC  setTitle: NSLocalizedString(@"NetBIOS name:" , @"Window text")];
    [workgroupTFC    setTitle: NSLocalizedString(@"Workgroup:"    , @"Window text")];
    
	
	// Resize the row labels and shift everything left or right appropriately
	NSArray * leftTfList = [NSArray arrayWithObjects: networkSettingTF,  dnsServersTF,  domainTF,  searchDomainTF,  winsServersTF,  netBiosNameTF,  workgroupTF,  nil];
	NSArray * leftTcList = [NSArray arrayWithObjects: networkSettingTFC, dnsServersTFC, domainTFC, searchDomainTFC, winsServersTFC, netBiosNameTFC, workgroupTFC, nil];
	
	CGFloat largestWidthChange = 0.0;  // (Make static analyzer happy)
	BOOL haveOne = FALSE;
	NSUInteger ix;
	for (  ix=0; ix<[leftTfList count]; ix++  ) {
		CGFloat widthChange = [UIHelper setTitle: nil ofControl: [leftTcList objectAtIndex: ix] frameHolder: [leftTfList objectAtIndex: ix] shift: ! rtl narrow: YES enable: YES];
		if (  haveOne  ) {
			if (  widthChange > largestWidthChange  ) {
				largestWidthChange = widthChange;
			}
		} else {
			largestWidthChange = widthChange;
			haveOne = TRUE;
		}
	}
	
	for (  ix=0; ix<[leftTfList count]; ix++  ) {
		[UIHelper shiftControl: [leftTfList objectAtIndex: ix] by: largestWidthChange reverse: ! rtl];
	}
	
	NSArray * middleTfList    = [NSArray arrayWithObjects: whenChangesToPreVpnValueTF,  dnsServersPopUpButton,      domainPopUpButton,      searchDomainPopUpButton,      winsServersPopUpButton,      netBiosNamePopUpButton,      workgroupPopUpButton,      nil];
	NSArray * rightmostTfList = [NSArray arrayWithObjects: whenChangesToAnythingElseTF, otherdnsServersPopUpButton, otherdomainPopUpButton, othersearchDomainPopUpButton, otherwinsServersPopUpButton, othernetBiosNamePopUpButton, otherworkgroupPopUpButton, nil];
	
	for (  ix=0; ix<[middleTfList count]; ix++  ) {
		[UIHelper shiftControl: [middleTfList objectAtIndex: ix] by: largestWidthChange reverse: ! rtl];
	}
	
	for (  ix=0; ix<[rightmostTfList count]; ix++  ) {
		[UIHelper shiftControl: [rightmostTfList objectAtIndex: ix] by: largestWidthChange reverse: ! rtl];
	}
	
	
	// Resize the middle column label and buttons, and shift the rightmost column left or right appropriately
	
	CGFloat middleHeaderWidthChange = [UIHelper setTitle: nil ofControl: whenChangesToPreVpnValueTF shift: rtl narrow: YES enable: YES];
	
    CGFloat middleColumnWidthChange = [self initializeDnsWinsPopUp: dnsServersPopUpButton arrayController: dnsServersArrayController];
    [self initializeDnsWinsPopUp: domainPopUpButton       arrayController: domainArrayController       ];
    [self initializeDnsWinsPopUp: searchDomainPopUpButton arrayController: searchDomainArrayController ];
    [self initializeDnsWinsPopUp: winsServersPopUpButton  arrayController: winsServersArrayController  ];
    [self initializeDnsWinsPopUp: netBiosNamePopUpButton  arrayController: netBiosNameArrayController  ];
    [self initializeDnsWinsPopUp: workgroupPopUpButton    arrayController: workgroupArrayController    ];

	CGFloat widthChange = (  (middleHeaderWidthChange > middleColumnWidthChange)
						   ? - middleHeaderWidthChange
						   : - middleColumnWidthChange);
	
	// (Shift the right-most column by the size change of the middle column)
	
	for (  ix=0; ix<[rightmostTfList count]; ix++  ) {
		[UIHelper shiftControl: [rightmostTfList objectAtIndex: ix] by: widthChange reverse: rtl];
	}
	
    [self initializeDnsWinsPopUp: otherdnsServersPopUpButton   arrayController: otherdnsServersArrayController  ];
    [self initializeDnsWinsPopUp: otherdomainPopUpButton       arrayController: otherdomainArrayController      ];
    [self initializeDnsWinsPopUp: othersearchDomainPopUpButton arrayController: othersearchDomainArrayController];
    [self initializeDnsWinsPopUp: otherwinsServersPopUpButton  arrayController: otherwinsServersArrayController ];
    [self initializeDnsWinsPopUp: othernetBiosNamePopUpButton  arrayController: othernetBiosNameArrayController ];
    [self initializeDnsWinsPopUp: otherworkgroupPopUpButton    arrayController: otherworkgroupArrayController   ];
    
	
	//
	// ***** For Credentials tab, everything depends on preferences; there is nothing static
	//
	
    // For Sound tab
    
    [alertSoundsBox setTitle: NSLocalizedString(@"Alert sounds", @"Window title")];
    
    [connectionAlertSoundTFC    setTitle: NSLocalizedString(@"Connection:", @"Window text")              ];
    [disconnectionAlertSoundTFC setTitle: NSLocalizedString(@"Unexpected disconnection:", @"Window text")];
	
	[self initializeSoundPopUpButtons];
}

//**********************************************************************************************************************************

-(void) disableEverything {
    
    // Connecting & Disconnecting tab
    
    [flushDnsCacheCheckbox						setEnabled: NO];
	[allowManualNetworkSettingsOverrideCheckbox	setEnabled: NO];
    [prependDomainNameCheckbox					setEnabled: NO];
	
    [useRouteUpInsteadOfUpCheckbox         setEnabled: NO];
    [enableIpv6OnTapCheckbox               setEnabled: NO];
    [keepConnectedCheckbox                 setEnabled: NO];
    
    [loadTunPopUpButton                    setEnabled: NO];
    [loadTapPopUpButton                    setEnabled: NO];
    
    [disconnectOnSleepCheckbox             setEnabled: NO];
    [reconnectOnWakeFromSleepCheckbox      setEnabled: NO];
    
    [disconnectWhenUserSwitchesOutCheckbox setEnabled: NO];
    [reconnectWhenUserSwitchesInCheckbox   setEnabled: NO];
    [authenticateOnConnectCheckbox                 setEnabled: NO];
    
    // While Connected tab
    
    [runMtuTestCheckbox                    setEnabled: NO];
    
    [monitorNetworkForChangesCheckbox      setEnabled: NO];

    [dnsServersPopUpButton                 setEnabled: NO];
    [domainPopUpButton                     setEnabled: NO];
    [searchDomainPopUpButton               setEnabled: NO];
    [winsServersPopUpButton                setEnabled: NO];
    [netBiosNamePopUpButton                setEnabled: NO];
    [workgroupPopUpButton                  setEnabled: NO];
    
    [otherdnsServersPopUpButton            setEnabled: NO];
    [otherdomainPopUpButton                setEnabled: NO];
    [othersearchDomainPopUpButton          setEnabled: NO];
    [otherwinsServersPopUpButton           setEnabled: NO];
    [othernetBiosNamePopUpButton           setEnabled: NO];
    [otherworkgroupPopUpButton             setEnabled: NO];
    
    // VPN Credentials tab
    
    [allConfigurationsUseTheSameCredentialsCheckbox setEnabled: NO];
    [credentialsGroupButton                setEnabled: NO];
    [removeNamedCredentialsButton          setEnabled: NO];
	[addNamedCredentialsTF				   setEnabled: NO];
    [addNamedCredentialsButton             setEnabled: NO];
    
    // Sounds tab
    
    [soundOnConnectButton                  setEnabled: NO];
    [soundOnDisconnectButton               setEnabled: NO];
}

-(void) enableEverything {
    
    // Connecting & Disconnecting tab
    
    [flushDnsCacheCheckbox						setEnabled: YES];
	[allowManualNetworkSettingsOverrideCheckbox	setEnabled: YES];
    [prependDomainNameCheckbox					setEnabled: YES];
    [useRouteUpInsteadOfUpCheckbox				setEnabled: YES];
    [enableIpv6OnTapCheckbox					setEnabled: YES];
    [keepConnectedCheckbox						setEnabled: YES];
    [self setupUpdatesAuthenticateOnConnectCheckbox];
    
    [loadTunPopUpButton                    setEnabled: YES];
    [loadTapPopUpButton                    setEnabled: YES];
    
    [disconnectOnSleepCheckbox             setEnabled: YES];
    [reconnectOnWakeFromSleepCheckbox      setEnabled: YES];
    
    [disconnectWhenUserSwitchesOutCheckbox setEnabled: YES];
    [reconnectWhenUserSwitchesInCheckbox   setEnabled: YES];
    
    // While Connected tab
    
    [runMtuTestCheckbox                    setEnabled: YES];
    
    [monitorNetworkForChangesCheckbox      setEnabled: YES];
    
    [dnsServersPopUpButton                 setEnabled: YES];
    [domainPopUpButton                     setEnabled: YES];
    [searchDomainPopUpButton               setEnabled: YES];
    [winsServersPopUpButton                setEnabled: YES];
    [netBiosNamePopUpButton                setEnabled: YES];
    [workgroupPopUpButton                  setEnabled: YES];
    
    [otherdnsServersPopUpButton            setEnabled: YES];
    [otherdomainPopUpButton                setEnabled: YES];
    [othersearchDomainPopUpButton          setEnabled: YES];
    [otherwinsServersPopUpButton           setEnabled: YES];
    [othernetBiosNamePopUpButton           setEnabled: YES];
    [otherworkgroupPopUpButton             setEnabled: YES];
    
    // VPN Credentials tab
    
    [allConfigurationsUseTheSameCredentialsCheckbox setEnabled: YES];
    [credentialsGroupButton                setEnabled: YES];
    [removeNamedCredentialsButton          setEnabled: YES];
    [addNamedCredentialsButton             setEnabled: (   ([[addNamedCredentialsTF stringValue] length] != 0)
                                                        && ([[addNamedCredentialsTF stringValue] length] <= MAX_LENGTH_OF_CREDENTIALS_NAME)
                                                        && ( ! [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"] )
                                                        )];
    
    // Sounds tab
    
    [soundOnConnectButton                  setEnabled: YES];
    [soundOnDisconnectButton               setEnabled: YES];
}

-(void) setupSettingsFromPreferences {
    
	BOOL savedDoingSetupOfUI = [gMC doingSetupOfUI];
	[gMC setDoingSetupOfUI: TRUE];
	
    NSString * programName;
    if (  [configurationName isEqualToString: NSLocalizedString(@"Tunnelblick", @"Window title")]  ) {
        programName = @"";
    } else {
        programName = [NSString stringWithFormat: @" - Tunnelblick"];
    }

    if (   ( ! connection )
        || ( ![TBOperationQueue shouldUIBeEnabledForDisplayName: configurationName] )  ) {
        [settingsSheet setTitle: [NSString stringWithFormat: NSLocalizedString(@"Advanced Settings%@", @"Window title. The '%@' is a space followed by the name of the program (usually 'Tunnelblick')"), programName]];
        [self disableEverything];
        [gMC setDoingSetupOfUI: savedDoingSetupOfUI];
        return;
    }
	
	NSString * localName = [gMC localizedNameForDisplayName: configurationName];
	NSString * privateSharedDeployed = [connection displayLocation];
    [settingsSheet setTitle: [NSString stringWithFormat: NSLocalizedString(@"%@%@ Disconnected - Advanced Settings%@", @"Window title"), localName, privateSharedDeployed, programName]];
    
    [self enableEverything]; // Some items may be individually disabled later
    
	[self setupCredentialsGroupButton]; // May not need to, but set up this first, so it is set up for the rest
	
    // For Connecting tab
    
    [self setupFlushDNSCheckbox];
	[self setupAllowManualNetworkSettingsOverrideCheckbox];
    [self setupKeepConnectedCheckbox];
    [self setupEnableIpv6OnTapCheckbox];
    [self setupPrependDomainNameCheckbox];
    [self setupDisconnectOnSleepCheckbox];
    [self setupReconnectOnWakeFromSleepCheckbox];
	[self setupUseRouteUpInsteadOfUpCheckbox];
    [self setupUpdatesAuthenticateOnConnectCheckbox];

    [self setupCheckbox: disconnectWhenUserSwitchesOutCheckbox
                    key: @"-doNotDisconnectOnFastUserSwitch"
               inverted: YES];
    
    [self setupCheckbox: reconnectWhenUserSwitchesInCheckbox
                    key: @"-doNotReconnectOnFastUserSwitch"
               inverted: YES];
    
	[self setupTunTapButtons];
    
    // For WhileConnected tab
    
    [self setupRunMtuTestCheckbox];
    
    if (  [[gMC logScreen] forceDisableOfNetworkMonitoring]  ) {
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
	
    [credentialsTabViewItem setLabel: NSLocalizedString(@"VPN Credentials", @"Window title")];
	
	[namedCredentialsBox
	 setTitle: NSLocalizedString(@"Named Credentials", @"Window text")];
	
	[UIHelper setTitle: NSLocalizedString(@"Add Credentials", @"Window text")
							ofControl: addNamedCredentialsButton
								shift: [UIHelper languageAtLaunchWasRTL]
							   narrow: YES
							   enable: NO];
    
	[addNamedCredentialsTFC setTitle: @""];
	[addNamedCredentialsTF  setDelegate: self];
	
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
	NSString * groupName = [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"];
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
        NSString * groupName2 = [removeNamedCredentialsNames objectAtIndex: i];
		[groupsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys:
									 [NSString stringWithFormat:
											NSLocalizedString(@"This configuration uses %@ credentials", @"Button"),
											groupName2], @"name",
									 groupName2, @"value", nil]];
        
		NSMenuItem * item2 = [[[NSMenuItem alloc] initWithTitle: groupName2
                                                         action: @selector(removeNamedCredentialsCommand:)
                                                  keyEquivalent: @""] autorelease];
        [item2 setTag: (int) i];
		[item2 setTarget: self];
        [removeCredentialMenu addItem: item2];
	}
	
	NSString * prefKey = [[connection displayName] stringByAppendingString: @"-credentialsGroup"];
	[credentialsGroupArrayController setContent: groupsDictionaryArray];
	[UIHelper setTitle: nil
							ofControl: credentialsGroupButton
								shift: [UIHelper languageAtLaunchWasRTL]
							   narrow: YES
							   enable: (   ( ! [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"] )
										&& [gTbDefaults canChangeValueForKey: prefKey])];
	
    [removeNamedCredentialsButton setMenu: removeCredentialMenu];
	[UIHelper setTitle: nil
							ofControl: removeNamedCredentialsButton
								shift: [UIHelper languageAtLaunchWasRTL]
							   narrow: YES
							   enable: ( ! [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"])];
	
	NSString * groupAllConfigurationsUse = [removeNamedCredentialsNames objectAtIndex: 0];
	if (  ! groupAllConfigurationsUse  ) {
		groupAllConfigurationsUse = NSLocalizedString(@"Common", @"Credentials name");
	}
	
	[self setupCredentialsGroupButton];
	
	NSString * groupFromPrefs = [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"];
	if (  groupFromPrefs  ) {
		[allConfigurationsUseTheSameCredentialsCheckbox setState: NSOnState];
		[credentialsGroupButton       setEnabled: NO];
		[addNamedCredentialsTF        setEnabled: NO];
		[addNamedCredentialsButton    setEnabled: NO];
		[removeNamedCredentialsButton setEnabled: NO];
		
	} else {
		[allConfigurationsUseTheSameCredentialsCheckbox setState: NSOffState];
		[credentialsGroupButton       setEnabled: YES];
		[addNamedCredentialsTF        setEnabled: YES];
        [addNamedCredentialsButton    setEnabled: (   ([[addNamedCredentialsTF stringValue] length] != 0)
                                                   && ([[addNamedCredentialsTF stringValue] length] <= MAX_LENGTH_OF_CREDENTIALS_NAME)  )];
		[removeNamedCredentialsButton setEnabled: YES];
	}
	
	[allConfigurationsUseTheSameCredentialsCheckbox
	  setTitle: [NSString stringWithFormat: NSLocalizedString(@"All configurations use %@ credentials", @"Window text"), groupAllConfigurationsUse]
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, all configurations will share the same username, password, and/or private key.</p>\n",
														   @"HTML info for the 'All configurations use ___ credentials' checkbox."))];
	
    // Sounds tab
	
    doNotPlaySounds = FALSE;
    
	[soundTabViewItem setLabel: NSLocalizedString(@"Sounds", @"Window title")];
    [self setSelectedSoundOnConnectIndexDirect:          [NSNumber numberWithInteger: NSNotFound]];
    [self setSelectedSoundOnDisconnectIndexDirect:       [NSNumber numberWithInteger: NSNotFound]];
	[self setupSoundPopUpButtons];

	
	[gMC setDoingSetupOfUI: savedDoingSetupOfUI];
}

-(void) setupMonitoringOptions {
	
	BOOL savedDoingSetupOfUI = [gMC doingSetupOfUI];
	[gMC setDoingSetupOfUI: TRUE];
	
    if (   connection
        && ( ! [[gMC logScreen] forceDisableOfNetworkMonitoring] )
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
        
        [self setSelectedDnsServersIndex:   [NSNumber numberWithUnsignedInteger: [self indexForMonitoringOptionButton: dnsServersPopUpButton   newPreference: @"-changeDNSServersAction"   oldPreference: @"-doNotRestoreOnDnsReset"  leasewatchOptionsChar: @"a"]]];
        [self setSelectedDomainIndex:       [NSNumber numberWithUnsignedInteger: [self indexForMonitoringOptionButton: domainPopUpButton       newPreference: @"-changeDomainAction"       oldPreference: @"-doNotRestoreOnDnsReset"  leasewatchOptionsChar: @"d"]]];
        [self setSelectedSearchDomainIndex: [NSNumber numberWithUnsignedInteger: [self indexForMonitoringOptionButton: searchDomainPopUpButton newPreference: @"-changeSearchDomainAction" oldPreference: @"-doNotRestoreOnDnsReset"  leasewatchOptionsChar: @"s"]]];
        [self setSelectedWinsServersIndex:  [NSNumber numberWithUnsignedInteger: [self indexForMonitoringOptionButton: winsServersPopUpButton  newPreference: @"-changeWINSServersAction"  oldPreference: @"-doNotRestoreOnWinsReset" leasewatchOptionsChar: @"w"]]];
        [self setSelectedNetBiosNameIndex:  [NSNumber numberWithUnsignedInteger: [self indexForMonitoringOptionButton: netBiosNamePopUpButton  newPreference: @"-changeNetBIOSNameAction"  oldPreference: @"-doNotRestoreOnWinsReset" leasewatchOptionsChar: @"n"]]];
        [self setSelectedWorkgroupIndex:    [NSNumber numberWithUnsignedInteger: [self indexForMonitoringOptionButton: workgroupPopUpButton    newPreference: @"-changeWorkgroupAction"    oldPreference: @"-doNotRestoreOnWinsReset" leasewatchOptionsChar: @"g"]]];
        
        [self setSelectedOtherdnsServersIndex:   [NSNumber numberWithUnsignedInteger: [self indexForMonitoringOptionButton: otherdnsServersPopUpButton   newPreference: @"-changeOtherDNSServersAction"   oldPreference: nil leasewatchOptionsChar: @"a"]]];
        [self setSelectedOtherdomainIndex:       [NSNumber numberWithUnsignedInteger: [self indexForMonitoringOptionButton: otherdomainPopUpButton       newPreference: @"-changeOtherDomainAction"       oldPreference: nil leasewatchOptionsChar: @"d"]]];
        [self setSelectedOthersearchDomainIndex: [NSNumber numberWithUnsignedInteger: [self indexForMonitoringOptionButton: othersearchDomainPopUpButton newPreference: @"-changeOtherSearchDomainAction" oldPreference: nil leasewatchOptionsChar: @"s"]]];
        [self setSelectedOtherwinsServersIndex:  [NSNumber numberWithUnsignedInteger: [self indexForMonitoringOptionButton: otherwinsServersPopUpButton  newPreference: @"-changeOtherWINSServersAction"  oldPreference: nil leasewatchOptionsChar: @"w"]]];
        [self setSelectedOthernetBiosNameIndex:  [NSNumber numberWithUnsignedInteger: [self indexForMonitoringOptionButton: othernetBiosNamePopUpButton  newPreference: @"-changeOtherNetBIOSNameAction"  oldPreference: nil leasewatchOptionsChar: @"n"]]];
        [self setSelectedOtherworkgroupIndex:    [NSNumber numberWithUnsignedInteger: [self indexForMonitoringOptionButton: otherworkgroupPopUpButton    newPreference: @"-changeOtherWorkgroupAction"    oldPreference: nil leasewatchOptionsChar: @"g"]]];
        
        doNotModifyPreferences = oldDoNotModifyPreferences;
        
        NSString * leasewatchOptionsKey = [configurationName stringByAppendingString: @"-leasewatchOptions"];
        NSString * leasewatchOptions = [gTbDefaults stringForKey: leasewatchOptionsKey];
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
        
        [self setSelectedDnsServersIndex:   [NSNumber numberWithUnsignedInteger: 0u]];
        [self setSelectedDomainIndex:       [NSNumber numberWithUnsignedInteger: 0u]];
        [self setSelectedSearchDomainIndex: [NSNumber numberWithUnsignedInteger: 0u]];
        [self setSelectedWinsServersIndex:  [NSNumber numberWithUnsignedInteger: 0u]];
        [self setSelectedNetBiosNameIndex:  [NSNumber numberWithUnsignedInteger: 0u]];
        [self setSelectedWorkgroupIndex:    [NSNumber numberWithUnsignedInteger: 0u]];
        
        [self setSelectedOtherdnsServersIndex:   [NSNumber numberWithUnsignedInteger: 0u]];
        [self setSelectedOtherdomainIndex:       [NSNumber numberWithUnsignedInteger: 0u]];
        [self setSelectedOthersearchDomainIndex: [NSNumber numberWithUnsignedInteger: 0u]];
        [self setSelectedOtherwinsServersIndex:  [NSNumber numberWithUnsignedInteger: 0u]];
        [self setSelectedOthernetBiosNameIndex:  [NSNumber numberWithUnsignedInteger: 0u]];
        [self setSelectedOtherworkgroupIndex:    [NSNumber numberWithUnsignedInteger: 0u]];
        
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
	
	[gMC setDoingSetupOfUI: savedDoingSetupOfUI];
}

-(NSInteger) indexForMonitoringOptionButton: (NSPopUpButton *) button
                              newPreference: (NSString *)      preference
                              oldPreference: (NSString *)      oldPreference
                      leasewatchOptionsChar: (NSString *)      leasewatchOptionsChar {
    NSString * monitorKey = [configurationName stringByAppendingString: @"-notMonitoringConnection"];

    BOOL ignoringBecauseOfLeasewatchOptions = FALSE;
    NSString * leasewatchOptionsKey = [configurationName stringByAppendingString: @"-leasewatchOptions"];
    NSString * leasewatchOptions = [gTbDefaults stringForKey: leasewatchOptionsKey];
    if (  leasewatchOptions  ) {
        if (  [leasewatchOptions containsString: leasewatchOptionsChar]  ) {
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

    NSString * value = [gTbDefaults stringForKey: actualKey];
    if (  value  ) {
        if (  [value isEqualToString: @"ignore"]  ) {
			return 0;
		} else if (  [value isEqualToString: @"restore"]  ) {
			return 1;
		} else if (  [value isEqualToString: @"restart"]  ) {
			return 2;
		} else {
			NSLog(@"%@ preference '%@' ignored: invalid value; must be 'ignore', 'restore', or 'restart'", actualKey, value);
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
- (IBAction)authenticateOnConnectWasClicked:(NSButton *)sender {
    TBButton * checkbox = authenticateOnConnectCheckbox;
    if (  [checkbox isEnabled]  ) {
        [checkbox setEnabled: NO];
    } else {
         return;
    }
    
    BOOL newState = [sender state];
    NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH];
    NSMutableDictionary * newDict = (  dict
                                     ? [NSMutableDictionary dictionaryWithDictionary: dict]
                                     : [NSMutableDictionary dictionaryWithCapacity: 1]);
    
    [newDict setObject: [NSNumber numberWithBool: (newState) ] forKey: [configurationName stringByAppendingFormat:@"-authenticateOnConnect"]];
    
    NSString * tempDictionaryPath = [newTemporaryDirectoryPath() stringByAppendingPathComponent: @"forced-preferences.plist"];
    OSStatus status = (  tempDictionaryPath
                       ? (  [newDict writeToFile: tempDictionaryPath atomically: YES]
                          ? 0
                          : -1)
                       : -1);
    if (  status == 0  ) {
        [NSThread detachNewThreadSelector: @selector(secureAuthThread:) toTarget: self withObject: tempDictionaryPath];
    }
    
    // We must restore the checkbox value because the change hasn't been made yet. However, we can't restore it until after all processing of the
    // ...WasClicked event is finished, because after this method returns, further processing changes the checkbox value to reflect the user's click.
    // To undo that afterwards, we delay changing the value for 0.2 seconds.
    [self performSelector: @selector(setupUpdatesAuthenticateOnConnectCheckbox) withObject: nil afterDelay: 0.2];
}
-(void) secureAuthThread: (NSString *) forcedPreferencesDictionaryPath {
    // Runs in a separate thread so user authorization doesn't hang the main thread
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    NSString * message = NSLocalizedString(@"Tunnelblick needs to change a setting that may only be changed by a computer administrator.", @"Window text");
    SystemAuth * auth = [SystemAuth newAuthWithPrompt: message];
    if (  auth  ) {
        NSInteger status = [gMC runInstaller: INSTALLER_INSTALL_FORCED_PREFERENCES
                              extraArguments: [NSArray arrayWithObject: forcedPreferencesDictionaryPath]
                             usingSystemAuth: auth
                                installTblks: nil];
        [auth release];
        
        [self performSelectorOnMainThread: @selector(finishAuthenticating:) withObject: [NSNumber numberWithLong: (long)status] waitUntilDone: NO];
    } else {
        OSStatus status = 1; // User cancelled installation
        [self performSelectorOnMainThread: @selector(finishAuthenticating:) withObject: [NSNumber numberWithInt: status] waitUntilDone: NO];
    }
    
    [gFileMgr tbRemovePathIfItExists: [forcedPreferencesDictionaryPath stringByDeletingLastPathComponent]];  // Ignore error; it has been logged
    
    [pool drain];
}

-(void) finishAuthenticating: (NSNumber *) statusNumber {
    OSStatus status = [statusNumber intValue];
     
     if (  status == 0  ) {
         NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH];
         [gTbDefaults setPrimaryDefaults: dict];
     } else {
         if (  status != 1  ) { // status != cancelled by user (i.e., there was an error)
             TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                               NSLocalizedString(@"Tunnelblick was unable to make the change. See the Console Log for details.", @"Window text"));
         }
     }
    [self setupUpdatesAuthenticateOnConnectCheckbox];
}

-(void) setupUpdatesAuthenticateOnConnectCheckbox {
    NSString *key = [configurationName stringByAppendingString:@"-authenticateOnConnect"];
    TBButton * checkbox = authenticateOnConnectCheckbox;
    [checkbox setEnabled:YES];
    [checkbox setState: (  [gTbDefaults isTrueReadOnlyForKey: key]
                         ? NSOnState
                         : NSOffState)];
}

-(IBAction) reconnectWhenUnexpectedDisconnectCheckboxWasClicked: (NSButton *) sender {
    
    // This preference is NOT IMPLEMENTED, nor is there a checkbox in the .xib
    
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-doNotReconnectOnUnexpectedDisconnect"
																	 to: ([sender state] == NSOnState)
                                                               inverted: YES];
}


-(IBAction) flushDnsCacheCheckboxWasClicked: (NSButton *) sender {
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-doNotFlushCache"
																	 to: ([sender state] == NSOnState)
                                                               inverted: YES];
}


-(IBAction) allowManualNetworkSettingsOverrideCheckboxWasClicked: (NSButton *) sender {
	[gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-allowChangesToManuallySetNetworkSettings"
																						 to: ([sender state] == NSOnState)
																				   inverted: NO];
}


-(IBAction) keepConnectedCheckboxWasClicked: (NSButton *) sender {
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-keepConnected"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: NO];
}


-(IBAction) enableIpv6OnTapCheckboxWasClicked: (NSButton *) sender {
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-enableIpv6OnTap"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: NO];
}


-(IBAction) useRouteUpInsteadOfUpCheckboxWasClicked:(NSButton *)sender {
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-useUpInsteadOfRouteUp"
																	 to: ([sender state] == NSOnState)
                                                               inverted: YES];
}


-(IBAction) prependDomainNameCheckboxWasClicked: (NSButton *)sender {
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-prependDomainNameToSearchDomains"
																	 to: ([sender state] == NSOnState)
                                                               inverted: NO];
}


-(IBAction) disconnectOnSleepCheckboxWasClicked: (NSButton *)sender {
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-doNotDisconnectOnSleep"
																	 to: ([sender state] == NSOnState)
                                                               inverted: YES];
    [self setupReconnectOnWakeFromSleepCheckbox];
}


-(IBAction) reconnectOnWakeFromSleepCheckboxWasClicked: (NSButton *) sender {
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-doNotReconnectOnWakeFromSleep"
																	 to: ([sender state] == NSOnState)
                                                               inverted: YES];
}


-(IBAction) runMtuTestCheckboxWasClicked: (NSButton *) sender {
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-runMtuTest"
																	 to: ([sender state] == NSOnState)
                                                               inverted: NO];
}

-(void) setTunTapKey: (NSString *) key
		 value: (NSString *) value {
    
	if ( ! [gMC doingSetupOfUI]  ) {
		NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
						 value,  @"NewValue",
						 key,    @"PreferenceName",
						 nil];
		[gMC performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
	}
}

-(IBAction) loadTunAutomaticallyMenuItemWasClicked: (id) sender {
    (void) sender;
    
    [self setTunTapKey: @"-loadTun" value: @""];
}

-(IBAction) loadTapAutomaticallyMenuItemWasClicked: (id)sender {
    (void) sender;
    
    [self setTunTapKey: @"-loadTap" value: @""];
}

-(IBAction) loadTunNeverMenuItemWasClicked: (id)sender {
    (void) sender;
    
    [self setTunTapKey: @"-loadTun" value: @"never"];
}

-(IBAction) loadTapNeverMenuItemWasClicked: (id)sender {
    (void) sender;
    
    [self setTunTapKey: @"-loadTap" value: @"never"];
}

-(IBAction) loadTunAlwaysMenuItemWasClicked: (id)sender {
    (void) sender;
    
    [self setTunTapKey: @"-loadTun" value: @"always"];
}

-(IBAction) loadTapAlwaysMenuItemWasClicked: (id)sender {
    (void) sender;
    
    [self setTunTapKey: @"-loadTap" value: @"always"];
}

-(IBAction) connectingHelpButtonWasClicked: (id) sender {
	(void) sender;
	
    MyGotoHelpPage(@"vpn-details-advanced-connecting-disconnecting.html", nil);
}


-(IBAction) disconnectWhenUserSwitchesOutCheckboxWasClicked: (NSButton *) sender  {
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-doNotDisconnectOnFastUserSwitch"
																	 to: ([sender state] == NSOnState)
														 inverted: YES];
}


-(IBAction) reconnectWhenUserSwitchesInCheckboxWasClicked: (NSButton *) sender {
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-doNotReconnectOnFastUserSwitch"
																	 to: ([sender state] == NSOnState)
														 inverted: YES];
}


// Methods for While Connecting tab

-(void) monitorNetworkForChangesCheckboxChangedForConnection: (VPNConnection *) theConnection {
    // Checkbox was changed by another window
    
    if (   connection
        && (connection == theConnection)  ) {
        if (  [[gMC logScreen] forceDisableOfNetworkMonitoring]  ) {
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

-(IBAction) monitorNetworkForChangesCheckboxWasClicked: (NSButton *) sender {
    
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-notMonitoringConnection"
																	 to: ([sender state] == NSOnState)
														 inverted: YES];
    
    [self setupMonitoringOptions];
    
    [[gMC logScreen] monitorNetworkForChangesCheckboxChangedForConnection: connection];
}

-(void) setDnsWinsIndexTo: (NSNumber *)   newValue
               preference: (NSString *)   key {
    
    if (  ! doNotModifyPreferences  ) {
        NSString * newSetting = nil;
        switch (  [newValue unsignedIntegerValue]  ) {
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
                NSLog(@"setDnsWinsIndex: ignoring invalid value %ld", (long) [newValue unsignedIntegerValue]);
        }
        if (  newSetting != nil  ) {
            NSString * defaultValue = (  [key hasPrefix: @"-changeOther"]
                                       ? @"restart"
                                       : @"restore");
            
			if ( ! [gMC doingSetupOfUI]  ) {
				NSString * newStringValue = (  [newSetting isEqualToString: defaultValue]
                                             ? @""
                                             : newSetting
                                             );
				NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                       newStringValue,  @"NewValue",
                                       key,    @"PreferenceName",
                                       nil];
				[gMC performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
			}
		}
    }
}

-(void) setSelectedDnsServersIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeDNSServersAction"];
    [self setSelectedDnsServersIndexDirect: newValue];
}

-(void) setSelectedDomainIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeDomainAction"];
    [self setSelectedDomainIndexDirect: newValue];
}

-(void) setSelectedSearchDomainIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeSearchDomainAction"];
    [self setSelectedSearchDomainIndexDirect: newValue];
}

-(void) setSelectedWinsServersIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeWINSServersAction"];
    [self setSelectedWinsServersIndexDirect: newValue];
}

-(void) setSelectedNetBiosNameIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeNetBIOSNameAction"];
    [self setSelectedNetBiosNameIndexDirect: newValue];
}

-(void) setSelectedWorkgroupIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeWorkgroupAction"];
    [self setSelectedWorkgroupIndexDirect: newValue];
}

-(void) setSelectedOtherdnsServersIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeOtherDNSServersAction"];
    [self setSelectedOtherdnsServersIndexDirect: newValue];
}

-(void) setSelectedOtherdomainIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeOtherDomainAction"];
    [self setSelectedOtherdomainIndexDirect: newValue];
}

-(void) setSelectedOthersearchDomainIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeOtherSearchDomainAction"];
    [self setSelectedOthersearchDomainIndexDirect: newValue];
}

-(void) setSelectedOtherwinsServersIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeOtherWINSServersAction"];
    [self setSelectedOtherwinsServersIndexDirect: newValue];
}

-(void) setSelectedOthernetBiosNameIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeOtherNetBIOSNameAction"];
    [self setSelectedOthernetBiosNameIndexDirect: newValue];
}

-(void) setSelectedOtherworkgroupIndex: (NSNumber *) newValue {
    
    [self setDnsWinsIndexTo: newValue preference: @"-changeOtherWorkgroupAction"];
    [self setSelectedOtherworkgroupIndexDirect: newValue];
}

-(void) setSelectedCredentialsGroupIndex: (NSNumber *) newValue {
	
    NSArray * contents = [credentialsGroupArrayController content];
    if (  [newValue unsignedIntegerValue] < [contents count]  ) {
		NSString * groupValue = nil;
        if (  [newValue unsignedIntegerValue] == 0) {
			groupValue = @"";
        } else {
            NSString * groupName = [[contents objectAtIndex: [newValue unsignedIntegerValue]] objectForKey: @"value"];
			NSArray * groups = [gTbDefaults sortedCredentialsGroups];
            if (  [groups containsObject: groupName]  ) {
				groupValue = groupName;
			} else {
		  NSLog(@"setSelectedCredentialsGroupIndex: '%@' credentials are not available", groupName);
            }
        }
		
		if (  groupValue  ) {
			if (  ! [gMC doingSetupOfUI]  ) {
				NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
								 groupValue, @"NewValue",
								 @"-credentialsGroup", @"PreferenceName",
								 nil];
				[gMC performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
			}
		}
		
		[self setSelectedCredentialsGroupIndexDirect: newValue];
		[connection initializeAuthAgent];
		
    } else if (  [contents count] != 0  ) {
        NSLog(@"setSelectedCredentialsGroupIndex: %ld but there are only %ld groups", (long) [newValue unsignedIntegerValue], (long) ([contents count] - 1));
    }
}

-(void) setupSoundIndexTo: (NSUInteger) newValue
               preference: (NSString *) preference
{
    NSArray * contents = [[self soundOnConnectArrayController] content];
    NSUInteger size = [contents count];
    if (  newValue < size  ) {
        NSString * newName;
        NSSound  * newSound;
        BOOL       speakIt = FALSE;
        if (  newValue == 0) {
            newName = @"None";
            newSound = nil;
        } else if (  newValue == 1) {
            newName = @"Speak";
            newSound = nil;
            if (  ! doNotPlaySounds  ) {
                if (  [preference hasSuffix: @"tunnelUpSoundName"]  ) {
                    [connection speakActivity: @"connected"];
                } else {
                    [connection speakActivity: @"disconnected"];
                }
            }
            speakIt = TRUE;
        } else {
            newName = [[contents objectAtIndex: newValue] objectForKey: @"name"];
            newSound = [NSSound soundNamed: newName];
            if (  newSound  ) {
                if (  ! doNotPlaySounds  ) {
                    [newSound play];
                }
            } else {
                NSLog(@"Sound '%@' is not available", newName);
            }
        }
        
        
        if ( ! [gMC doingSetupOfUI]  ) {
            NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                   newName, @"NewValue",
                                   preference, @"PreferenceName",
                                   nil];
            [gMC performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
        }
        if (  [preference hasSuffix: @"tunnelUpSoundName"]  ) {
            [connection setTunnelUpSound: newSound];
            [connection setSpeakWhenConnected: speakIt];
        } else {
            [connection setTunnelDownSound: newSound];
            [connection setSpeakWhenDisconnected: speakIt];
        }
    } else if (  size != 0  ) {
        NSLog(@"setSelectedSoundIndex: %ld but there are only %ld sounds", (long) newValue, (long) size);
    }
}

-(void) setSelectedSoundOnConnectIndex: (NSNumber *) newValue
{
    [self setupSoundIndexTo: [newValue unsignedIntegerValue] preference: @"-tunnelUpSoundName"];
    
    [self setSelectedSoundOnConnectIndexDirect: newValue];
}


-(void) setSelectedSoundOnDisconnectIndex: (NSNumber *) newValue
{
    [self setupSoundIndexTo: [newValue unsignedIntegerValue] preference: @"-tunnelDownSoundName"];
    
    [self setSelectedSoundOnDisconnectIndexDirect: newValue];
}

-(void) bringToFront2
{
    [gMC activateIgnoringOtherApps];
	[[self window] display];
	[self showWindow: self];
	[[self window] makeKeyAndOrderFront: self];
}

-(void) bringToFront1
{
	[self performSelectorOnMainThread: @selector(bringToFront2) withObject: nil waitUntilDone: NO];
}

-(void) updateStaticContentSetupSettingsAndBringToFront {
    
    [self initializeStaticContent];
    [self setupSettingsFromPreferences];
    [self bringToFront1];
}

-(void) removeNamedCredentialsCommand: (id) sender {
    
    unsigned ix = (unsigned)[sender tag];
    NSString * groupName = [removeNamedCredentialsNames objectAtIndex: ix];
    [ConfigurationManager removeCredentialsGroupInNewThreadWithName: groupName];
}

-(IBAction) allConfigurationsUseTheSameCredentialsCheckboxWasClicked: (NSButton *) sender {
	NSString * prefKey = @"namedCredentialsThatAllConfigurationsUse";
	if (  [gTbDefaults canChangeValueForKey: prefKey]  ) {
		if (  [sender state] == NSOffState) {
			[gTbDefaults removeObjectForKey: prefKey];
		} else {
			NSString * name = [removeNamedCredentialsNames objectAtIndex: 0];
			[gTbDefaults setObject: name forKey: prefKey];
		}
		[self setupSettingsFromPreferences];
        NSDictionary * connections = [gMC myVPNConnectionDictionary];
        NSEnumerator * e = [connections objectEnumerator];
        VPNConnection * conn;
        while (  (conn = [e nextObject])  ) {
            [conn initializeAuthAgent];
        }
	} else {
		NSLog(@"allConfigurationsUseTheSameCredentialsCheckboxWasClicked: but the '%@' preference is forced.", prefKey);
	}
}

-(void) controlTextDidChange: (NSNotification *) n {
	
	(void) n;
	
	[addNamedCredentialsButton setEnabled: (   ([[addNamedCredentialsTF stringValue] length] != 0)
                                            && ([[addNamedCredentialsTF stringValue] length] <= MAX_LENGTH_OF_CREDENTIALS_NAME)  )];
}

-(IBAction) addNamedCredentialsButtonWasClicked: (id) sender {
	
	(void) sender;
	
	NSString * newName = [addNamedCredentialsTF stringValue];
	if (  [newName length] > 0  ) {
		if (  invalidConfigurationName(newName, PROHIBITED_DISPLAY_NAME_CHARACTERS_INCLUDING_SLASH_CSTRING)  ) {
			TBShowAlertWindow(NSLocalizedString(@"Warning!", @"Window title"),
							  [NSString stringWithFormat:
							  NSLocalizedString(@"Names may not include any of the following characters: %s", @"Window text"),
							  PROHIBITED_DISPLAY_NAME_CHARACTERS_INCLUDING_SLASH_WITH_SPACES_CSTRING]);
		} else {
			NSString * errMsg = [gTbDefaults addNamedCredentialsGroup: newName];
			if (  errMsg  ) {
				TBShowAlertWindow(NSLocalizedString(@"Warning!", @"Window title"),
								  [NSString stringWithFormat:
								   NSLocalizedString(@"The credentials named %@ could not be added:\n\n%@", @"Window text"),
								   newName,
								   errMsg]);
			} else {
				[self initializeStaticContent];  // Update list of names in credentialsGroupButton
				[self setupSettingsFromPreferences];
			}
			return;
		}
	}
}

-(IBAction) addNamedCredentialsReturnWasTyped: (id) sender {
	
	(void) sender;
	
    // Don't do anything. This is invoked when then user switches away from the Credentials tab, and we don't want
    // to add a new credentials group when that happens, only when the user clicks the button
    // [self addNamedCredentialsButtonWasClicked: sender];
	
}

-(IBAction) whileConnectedHelpButtonWasClicked: (id) sender {
	(void) sender;
	
    MyGotoHelpPage(@"vpn-details-advanced-connecting-disconnecting.html", nil);
}

-(IBAction) vpnCredentialsHelpButtonWasClicked: (id) sender {
	(void) sender;
	
    MyGotoHelpPage(@"vpn-details-advanced-connecting-disconnecting.html", nil);
}

// General methods

// Set a checkbox from preferences
-(void) setupCheckbox: (TBButton *) checkbox
                  key: (NSString *) key
             inverted: (BOOL)       inverted {
    
    if (  checkbox  ) {
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
}


@end
