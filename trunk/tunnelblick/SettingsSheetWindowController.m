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
#import "VPNDetailsWindowController.h"


extern NSString             * gPrivatePath;
extern NSFileManager        * gFileMgr;
extern TBUserDefaults       * gTbDefaults;


@interface SettingsSheetWindowController()    // Private methods

//**********************************************************************************************************************************
// Methods that set up static content (content that is the same for all connections)

-(void) initializeStaticContent;

-(void) underlineLabel: tf string: inString alignment: (NSTextAlignment) align;

//**********************************************************************************************************************************
// Methods that set up up content that depends on a connection's settings

// Overall set up
-(void) setupSettingsFromPreferences;

-(void) initializeDnsWinsPopUp: (NSPopUpButton *)     popUpButton
               arrayController: (NSArrayController *) ac;

// Methods for setting up specific types of information

-(void) setupCheckbox: (NSButton *) checkbox
                  key: (NSString *) key
             inverted: (BOOL) inverted;

-(void) setupMonitoringOptions;

-(NSInteger) indexForMonitoringOptionButton: (NSPopUpButton *) button
                              newPreference: (NSString *)      preference
                              oldPreference: (NSString *)      oldPreference;

-(BOOL) changeBooleanPreference: (NSString *) key
                             to: (BOOL)       newValue
                       inverted: (BOOL)       inverted;

-(void) setDnsWinsIndex: (NSInteger *) index
                     to: (NSInteger)   newValue
             preference: (NSString *)  key;

@end


@implementation SettingsSheetWindowController

-(id) init
{
    if (  ![super initWithWindowNibName:@"VPNDetailsWindow"]  ) {
        return nil;
    }
    
    configurationName = nil;
    connection        = nil;

    configurationType = sharedConfiguration;
    
    showingSettingsSheet   = FALSE;
    doNotModifyPreferences = FALSE;
    
    return self;
}


-(void) dealloc
{
    [configurationName release];
    [connection        release];
    
    [super dealloc];
}

-(void) setConfigurationName: (NSString *) newName
{
    if (  ! [configurationName isEqualToString: newName]  ) {
        configurationName = [newName retain];
        
        connection = [[[NSApp delegate] myVPNConnectionDictionary] objectForKey: configurationName];
        
        if (  showingSettingsSheet  ) {
            [self initializeStaticContent];
            [self setupSettingsFromPreferences];
        }
    }
    
    return;
}


-(void) setStatus: (NSString *) newStatus
{
    [configurationStatusTFC setTitle: NSLocalizedString(newStatus, @"Connection status")];
}                                                            


-(void) updateConnectionStatusAndTime
{
    if ( showingSettingsSheet  ) {
        NSString * state = [connection state];
        NSString * localizedStatus = NSLocalizedString(state, @"Connection status");
        if (  [state isEqualToString: @"CONNECTED"]  ) {
            NSString * time = [connection connectTimeString];
            [configurationStatusTFC setTitle: [NSString stringWithFormat: @"%@%@",
                                               localizedStatus, time]];
        } else {
            [configurationStatusTFC setTitle: localizedStatus];
        }
    }    
}

-(void) showSettingsSheet: (id) sender
{
    if (  ! settingsSheet  ) {
        [NSBundle loadNibNamed: @"SettingsSheet" owner: self];
    } else {
        showingSettingsSheet = TRUE;
        [self setupSettingsFromPreferences];
    }
    
    [[self window] display];
    [[self window] makeKeyAndOrderFront: self];
    [NSApp activateIgnoringOtherApps:YES];
    
    /*    NSWindow * parentWindow = [[[NSApp delegate] logScreen] window];
     [NSApp beginSheet: settingsSheet
     modalForWindow: parentWindow
     modalDelegate: nil
     didEndSelector: NULL
     contextInfo: NULL];
     */
}


-(void) endSettingsSheet:  (id) sender
{
    showingSettingsSheet = FALSE;
    [NSApp endSheet: settingsSheet];
    [settingsSheet orderOut: sender];
    [settingsSheet release];
    settingsSheet = nil;
}


-(void) awakeFromNib
{
    showingSettingsSheet = TRUE;
    
    [self initializeStaticContent];
    [self setupSettingsFromPreferences];
}


//**********************************************************************************************************************************
-(void) initializeStaticContent
{    
    [configurationNameTFC setTitle: [NSString stringWithFormat: @"%@:", configurationName]];
    
    
    // For Connecting tab
    
    [scanConfigurationFileCheckbox             setTitle: NSLocalizedString(@"Scan configuration file for problems before connecting", @"Checkbox name")];
    [useTunTapDriversCheckbox                  setTitle: NSLocalizedString(@"Use Tunnelblick tun/tap drivers"                       , @"Checkbox name")];
    [flushDnsCacheCheckbox                     setTitle: NSLocalizedString(@"Flush DNS cache after connecting or disconnecting"     , @"Checkbox name")];
    
    
    [fastUserSwitchingBox                   setTitle: NSLocalizedString(@"Fast User Switching"                  , @"Window text")];
    
    [disconnectWhenUserSwitchesOutCheckbox  setTitle: NSLocalizedString(@"Disconnect when user switches out", @"Checkbox name")];
    [reconnectWhenUserSwitchesInCheckbox    setTitle: NSLocalizedString(@"Reconnect when user switches in"  , @"Checkbox name")];
    
    [ifConnectedWhenUserSwitchedOutTFC      setTitle: NSLocalizedString(@"(if connected when user switched out)", @"Window text")];
    
    
    // For WhileConnected tab
    
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
    
}

-(void) underlineLabel: tf string: inString alignment: (NSTextAlignment) align
{
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



-(void) initializeDnsWinsPopUp: (NSPopUpButton *) popUpButton arrayController: (NSArrayController *) ac
{
    NSArray * content = [NSArray arrayWithObjects:
                         [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Ignore"             , @"Button"), @"name", @"ignore" , @"value", nil],
                         [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Restore", @"Button"), @"name", @"restore", @"value", nil],
                         [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Restart connection" , @"Button"), @"name", @"restart", @"value", nil],
                         nil];
    [ac setContent: content];
    
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
        while (  control = [arrayEnum nextObject]  ) {
            NSRect oldPos;
            oldPos = [control frame];
            oldPos.origin.x = oldPos.origin.x + widthChange;
            [control setFrame:oldPos];
        }
    } else {
        [popUpButton sizeToFit];
    }
}

//**********************************************************************************************************************************
-(void) setupSettingsFromPreferences
{
    NSString * programName;
    if (  [configurationName isEqualToString: @"Tunnelblick"]  ) {
        programName = @"";
    } else {
        programName = [NSString stringWithFormat: @" - Tunnelblick"];
    }
    [settingsSheet setTitle: [NSString stringWithFormat: @"%@ Advanced Settings%@", configurationName, programName]];
    
    [self setStatus: [connection state]];
    
    // For Connecting tab
    
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
    
    [self setupCheckbox: flushDnsCacheCheckbox
                    key: @"-doNotFlushCache"
               inverted: YES];
    
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
}

-(void) setupMonitoringOptions
{
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
        
        [dnsServersPopUpButton selectItemAtIndex:   [self indexForMonitoringOptionButton: dnsServersPopUpButton   newPreference: @"-changeDNSServersAction"   oldPreference: @"-doNotRestoreOnDnsReset"]];
        [domainPopUpButton selectItemAtIndex:       [self indexForMonitoringOptionButton: domainPopUpButton       newPreference: @"-changeDomainAction"       oldPreference: @"-doNotRestoreOnDnsReset"]];
        [searchDomainPopUpButton selectItemAtIndex: [self indexForMonitoringOptionButton: searchDomainPopUpButton newPreference: @"-changeSearchDomainAction" oldPreference: @"-doNotRestoreOnDnsReset"]];
        [winsServersPopUpButton selectItemAtIndex:  [self indexForMonitoringOptionButton: winsServersPopUpButton  newPreference: @"-changeWINSServersAction"  oldPreference: @"-doNotRestoreOnWinsReset"]];
        [netBiosNamePopUpButton selectItemAtIndex:  [self indexForMonitoringOptionButton: netBiosNamePopUpButton  newPreference: @"-changeNetBIOSNameAction"  oldPreference: @"-doNotRestoreOnWinsReset"]];
        [workgroupPopUpButton selectItemAtIndex:    [self indexForMonitoringOptionButton: workgroupPopUpButton    newPreference: @"-changeWorkgroupAction"    oldPreference: @"-doNotRestoreOnWinsReset"]];
        
        [otherdnsServersPopUpButton selectItemAtIndex:   [self indexForMonitoringOptionButton: otherdnsServersPopUpButton   newPreference: @"-changeOtherDNSServersAction"   oldPreference: nil]];
        [otherdomainPopUpButton selectItemAtIndex:       [self indexForMonitoringOptionButton: otherdomainPopUpButton       newPreference: @"-changeOtherDomainAction"       oldPreference: nil]];
        [othersearchDomainPopUpButton selectItemAtIndex: [self indexForMonitoringOptionButton: othersearchDomainPopUpButton newPreference: @"-changeOtherSearchDomainAction" oldPreference: nil]];
        [otherwinsServersPopUpButton selectItemAtIndex:  [self indexForMonitoringOptionButton: otherwinsServersPopUpButton  newPreference: @"-changeOtherWINSServersAction"  oldPreference: nil]];
        [othernetBiosNamePopUpButton selectItemAtIndex:  [self indexForMonitoringOptionButton: othernetBiosNamePopUpButton  newPreference: @"-changeOtherNetBIOSNameAction"  oldPreference: nil]];
        [otherworkgroupPopUpButton selectItemAtIndex:    [self indexForMonitoringOptionButton: otherworkgroupPopUpButton    newPreference: @"-changeOtherWorkgroupAction"    oldPreference: nil]];
        
        [self setSelectedDnsServersIndex:   [self indexForMonitoringOptionButton: dnsServersPopUpButton   newPreference: @"-changeDNSServersAction"   oldPreference: @"-doNotRestoreOnDnsReset"]];
        [self setSelectedDomainIndex:       [self indexForMonitoringOptionButton: domainPopUpButton       newPreference: @"-changeDomainAction"       oldPreference: @"-doNotRestoreOnDnsReset"]];
        [self setSelectedSearchDomainIndex: [self indexForMonitoringOptionButton: searchDomainPopUpButton newPreference: @"-changeSearchDomainAction" oldPreference: @"-doNotRestoreOnDnsReset"]];
        [self setSelectedWinsServersIndex:  [self indexForMonitoringOptionButton: winsServersPopUpButton  newPreference: @"-changeWINSServersAction"  oldPreference: @"-doNotRestoreOnWinsReset"]];
        [self setSelectedNetBiosNameIndex:  [self indexForMonitoringOptionButton: netBiosNamePopUpButton  newPreference: @"-changeNetBIOSNameAction"  oldPreference: @"-doNotRestoreOnWinsReset"]];
        [self setSelectedWorkgroupIndex:    [self indexForMonitoringOptionButton: workgroupPopUpButton    newPreference: @"-changeWorkgroupAction"    oldPreference: @"-doNotRestoreOnWinsReset"]];
        
        [self setSelectedOtherdnsServersIndex:   [self indexForMonitoringOptionButton: otherdnsServersPopUpButton   newPreference: @"-changeOtherDNSServersAction"   oldPreference: nil]];
        [self setSelectedOtherdomainIndex:       [self indexForMonitoringOptionButton: otherdomainPopUpButton       newPreference: @"-changeOtherDomainAction"       oldPreference: nil]];
        [self setSelectedOthersearchDomainIndex: [self indexForMonitoringOptionButton: othersearchDomainPopUpButton newPreference: @"-changeOtherSearchDomainAction" oldPreference: nil]];
        [self setSelectedOtherwinsServersIndex:  [self indexForMonitoringOptionButton: otherwinsServersPopUpButton  newPreference: @"-changeOtherWINSServersAction"  oldPreference: nil]];
        [self setSelectedOthernetBiosNameIndex:  [self indexForMonitoringOptionButton: othernetBiosNamePopUpButton  newPreference: @"-changeOtherNetBIOSNameAction"  oldPreference: nil]];
        [self setSelectedOtherworkgroupIndex:    [self indexForMonitoringOptionButton: otherworkgroupPopUpButton    newPreference: @"-changeOtherWorkgroupAction"    oldPreference: nil]];
        
        doNotModifyPreferences = oldDoNotModifyPreferences;
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
{
    NSString * monitorKey = [configurationName stringByAppendingString: @"-notMonitoringConnection"];
    
    NSString * defaultValue;
    NSString * actualKey = [configurationName stringByAppendingString: preference];
    
    NSString * oldActualKey = nil;
    if (  oldPreference  ) {
        oldActualKey = [configurationName stringByAppendingString: oldPreference];
    }
    
    [button setEnabled: (   [gTbDefaults canChangeValueForKey: actualKey]
                         && [gTbDefaults canChangeValueForKey: monitorKey]   )];
    
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


// Methods for Connecting tab

-(IBAction) reconnectWhenUnexpectedDisconnectCheckboxWasClicked: (id) sender
{
    [self changeBooleanPreference: @"-doNotReconnectOnUnexpectedDisconnect"
                               to: ([sender state] == NSOnState)
                         inverted: YES];
}


-(IBAction) scanConfigurationFileCheckboxWasClicked: (id) sender
{
    [self changeBooleanPreference: @"-doNotParseConfigurationFile"
                               to: ([sender state] == NSOnState)
                         inverted: YES];
}


-(IBAction) useTunTapDriversCheckboxWasClicked: (id) sender
{
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


-(IBAction) flushDnsCacheCheckboxWasClicked: (id) sender
{
    [self changeBooleanPreference: @"-doNotFlushCache"
                               to: ([sender state] == NSOnState)
                         inverted: YES];
}


-(BOOL) changeBooleanPreference: (NSString *) key
                             to: (BOOL)       newValue
                       inverted: (BOOL)       inverted
{
    NSString * actualKey = [configurationName stringByAppendingString: key];
    BOOL state = (inverted ? ! newValue : newValue);
    [gTbDefaults setBool: state forKey: actualKey];
    return state;
}


-(IBAction) connectingHelpButtonWasClicked: (id) sender
{
    OSStatus err;
    if (err = MyGotoHelpPage(CFSTR("vpn-details-advanced-connecting-disconnecting.html"), NULL)  ) {
        NSLog(@"Error %d from MyGotoHelpPage()", err);
    }
}


-(IBAction) disconnectWhenUserSwitchesOutCheckboxWasClicked: (id) sender
{
    [self changeBooleanPreference: @"-doNotDisconnectOnFastUserSwitch"
                               to: ([sender state] == NSOnState)
                         inverted: YES];
}


-(IBAction) reconnectWhenUserSwitchesInCheckboxWasClicked: (id) sender
{
    [self changeBooleanPreference: @"-doNotReconnectOnFastUserSwitch"
                               to: ([sender state] == NSOnState)
                         inverted: YES];
}


// Methods for While Connecting tab

// Checkbox was changed by another window
-(void) monitorNetworkForChangesCheckboxChangedForConnection: (VPNConnection *) theConnection;
{
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


-(IBAction) monitorNetworkForChangesCheckboxWasClicked: (id) sender
{
    [self changeBooleanPreference: @"-notMonitoringConnection"
                               to: ([sender state] == NSOnState)
                         inverted: YES];
    
    [self setupMonitoringOptions];
    
    [[[NSApp delegate] logScreen] monitorNetworkForChangesCheckboxChangedForConnection: connection];
}


-(NSInteger) selectedDnsServersIndex
{
    return selectedDnsServersIndex;
}


-(void) setSelectedDnsServersIndex: (NSInteger) newValue
{
    [self setDnsWinsIndex: &selectedDnsServersIndex to: newValue preference: @"-changeDNSServersAction"];
}


-(NSInteger) selectedDomainIndex
{
    return selectedDomainIndex;
}


-(void) setSelectedDomainIndex: (NSInteger) newValue
{
    [self setDnsWinsIndex: &selectedDomainIndex to: newValue preference: @"-changeDomainAction"];
}

-(NSInteger) selectedSearchDomainIndex
{
    return selectedSearchDomainIndex;
}

-(void) setSelectedSearchDomainIndex: (NSInteger) newValue
{
    [self setDnsWinsIndex: &selectedSearchDomainIndex to: newValue preference: @"-changeSearchDomainAction"];
}

-(NSInteger) selectedWinsServersIndex
{
    return selectedWinsServersIndex;
}


-(void) setSelectedWinsServersIndex: (NSInteger) newValue
{
    [self setDnsWinsIndex: &selectedWinsServersIndex to: newValue preference: @"-changeWINSServersAction"];
}

-(NSInteger) selectedNetBiosNameIndex
{
    return selectedNetBiosNameIndex;
}


-(void) setSelectedNetBiosNameIndex: (NSInteger) newValue
{
    [self setDnsWinsIndex: &selectedNetBiosNameIndex to: newValue preference: @"-changeNetBIOSNameAction"];
}

-(NSInteger) selectedWorkgroupIndex
{
    return selectedWorkgroupIndex;
}


-(void) setSelectedWorkgroupIndex: (NSInteger) newValue
{
    [self setDnsWinsIndex: &selectedWorkgroupIndex to: newValue preference: @"-changeWorkgroupAction"];
}


-(NSInteger) selectedOtherdnsServersIndex
{
    return selectedDnsServersIndex;
}


-(void) setSelectedOtherdnsServersIndex: (NSInteger) newValue
{
    [self setDnsWinsIndex: &selectedDnsServersIndex to: newValue preference: @"-changeOtherDNSServersAction"];
}


-(NSInteger) selectedOtherdomainIndex
{
    return selectedDomainIndex;
}


-(void) setSelectedOtherdomainIndex: (NSInteger) newValue
{
    [self setDnsWinsIndex: &selectedDomainIndex to: newValue preference: @"-changeOtherDomainAction"];
}

-(NSInteger) selectedOthersearchDomainIndex
{
    return selectedSearchDomainIndex;
}

-(void) setSelectedOthersearchDomainIndex: (NSInteger) newValue
{
    [self setDnsWinsIndex: &selectedSearchDomainIndex to: newValue preference: @"-changeOtherSearchDomainAction"];
}

-(NSInteger) selectedOtherwinsServersIndex
{
    return selectedWinsServersIndex;
}


-(void) setSelectedOtherwinsServersIndex: (NSInteger) newValue
{
    [self setDnsWinsIndex: &selectedWinsServersIndex to: newValue preference: @"-changeOtherWINSServersAction"];
}

-(NSInteger) selectedOthernetBiosNameIndex
{
    return selectedNetBiosNameIndex;
}


-(void) setSelectedOthernetBiosNameIndex: (NSInteger) newValue
{
    [self setDnsWinsIndex: &selectedNetBiosNameIndex to: newValue preference: @"-changeOtherNetBIOSNameAction"];
}

-(NSInteger) selectedOtherworkgroupIndex
{
    return selectedWorkgroupIndex;
}


-(void) setSelectedOtherworkgroupIndex: (NSInteger) newValue
{
    [self setDnsWinsIndex: &selectedWorkgroupIndex to: newValue preference: @"-changeOtherWorkgroupAction"];
}


// set a DNS/WINS change index
-(void) setDnsWinsIndex: (NSInteger *) index
                     to: (NSInteger)   newValue
             preference: (NSString *)  key
{
    if (  newValue != *index  ) {
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
                    NSLog(@"setDnsWinsIndex: ignoring invalid value %d", newValue);
            }
            if (  newSetting != nil  ) {
                NSString * defaultValue;
                if (  [key rangeOfString: @"-changeOther"].length != 0  ) {
                    defaultValue = @"restart";
                } else {
                    defaultValue = @"restore";
                }
                
                NSString * actualKey = [configurationName stringByAppendingString: key];
                if (  ! [newSetting isEqualToString: defaultValue]  ) {
                    [gTbDefaults setObject: newSetting forKey: actualKey];
                } else {
                    [gTbDefaults removeObjectForKey: actualKey];
                }
                
            }
        }
        
        *index = newValue;
    }
}


-(IBAction) whileConnectedHelpButtonWasClicked: (id) sender
{
}


// General methods

// Set a checkbox from preferences
-(void) setupCheckbox: (NSButton *) checkbox
                  key: (NSString *) key
             inverted: (BOOL) inverted
{
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


@end
