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


#import "ConfigurationsView.h"

#import "Helper.h"

#import "LeftNavDataSource.h"
#import "MenuController.h"
#import "MyPrefsWindowController.h"
#import "NSString+TB.h"
#import "TBUserDefaults.h"

extern NSFileManager  * gFileMgr;
extern TBUserDefaults * gTbDefaults;


@interface ConfigurationsView() // Private methods

-(void) setTitle: (NSString *) newTitle ofControl: (id) theControl;

@end


@implementation ConfigurationsView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void) dealloc
{
	[super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect {
    // Drawing code here.
	
	(void) dirtyRect;
}

-(void) awakeFromNib {
	
    [self setTitle: NSLocalizedString(@"Connect"   , @"Button") ofControl: connectButton   ];
    [self setTitle: NSLocalizedString(@"Disconnect", @"Button") ofControl: disconnectButton];
    
	BOOL savedDoingSetupOfUI = [[NSApp delegate] doingSetupOfUI];
    [[NSApp delegate] setDoingSetupOfUI: TRUE];
	
    // Left split view -- list of configurations and configuration manipulation
    
	if (   runningOnSnowLeopardOrNewer()  // 10.5 and lower don't have setDelegate and setDataSource
		&& ( ! [gTbDefaults boolForKey: @"doNotShowOutlineViewOfConfigurations"] )  ) {
		[[self leftNavTableScrollView] setHidden: YES];
		[leftNavDataSrc reload];
        NSOutlineView * ov = [ (NSScrollView *)[outlineViewController view] documentView];
        [ov setDataSource: leftNavDataSrc];
        [ov setDelegate:   leftNavDataSrc];
        [ov expandItem: [ov itemAtRow: 0]];
	} else {
		[[[self outlineViewController] view] setHidden: YES];
		[leftNavTableView setDelegate: [[NSApp delegate] logScreen]];
 	}
	
	[[leftNavTableColumn headerCell] setTitle: NSLocalizedString(@"Configurations", @"Window text")];
	
	[renameConfigurationMenuItem          setTitle: NSLocalizedString(@"Rename Configuration..."                          , @"Menu Item")];
    [duplicateConfigurationMenuItem       setTitle: NSLocalizedString(@"Duplicate Configuration..."                       , @"Menu Item")];
    [revertToShadowMenuItem			      setTitle: NSLocalizedString(@"Revert Configuration..."                          , @"Menu Item")];
    [editOpenVPNConfigurationFileMenuItem setTitle: NSLocalizedString(@"Edit OpenVPN Configuration File..."               , @"Menu Item")];
    [showOpenvpnLogMenuItem               setTitle: NSLocalizedString(@"Show OpenVPN Log in Finder"                       , @"Menu Item")];
    [removeCredentialsMenuItem            setTitle: NSLocalizedString(@"Delete Configuration's Credentials in Keychain...", @"Menu Item")];
    
    // editOpenVPNConfigurationFileMenuItem and makePrivateOrSharedMenuItem are initialized in validateDetailsWindowControls
    
    
    // Right split view - Log tab
    
    [logTabViewItem setLabel: NSLocalizedString(@"Log", @"Window title")];
    
    [self setTitle: NSLocalizedString(@"Copy Diagnostic Info to Clipboard", @"Button") ofControl: logToClipboardButton];
    
    
    // Right split view - Settings tab
    
    [settingsTabViewItem setLabel: NSLocalizedString(@"Settings", @"Window title")];
    
    [whenToConnectTFC                       setTitle: NSLocalizedString(@"Connect:", @"Window text")];
    [whenToConnectManuallyMenuItem          setTitle: NSLocalizedString(@"Manually"                 , @"Button")];
    [whenToConnectTunnelBlickLaunchMenuItem setTitle: NSLocalizedString(@"When Tunnelblick launches", @"Button")];
    [whenToConnectOnComputerStartMenuItem   setTitle: NSLocalizedString(@"When computer starts"     , @"Button")];
    [whenToConnectPopUpButton sizeToFit];
    
    [setNameserverTFC setTitle: NSLocalizedString(@"Set DNS/WINS:", @"Window text")];
    // setNameserverPopUpButton is initialized in setupSettingsFromPreferences
    
    [monitorNetworkForChangesCheckbox setTitle: NSLocalizedString(@"Monitor network settings", @"Checkbox name")];
	
    [keepConnectedCheckbox setTitle: NSLocalizedString(@"Keep connected", @"Checkbox name")];
    
    // OpenVPN Version popup. Default depends on version of OS X
    
    [perConfigOpenvpnVersionTFC setTitle: NSLocalizedString(@"OpenVPN version:", @"Window text")];
    
    NSArray  * versions  = [[NSApp delegate] openvpnVersionNames];
    NSUInteger defaultIx = [[NSApp delegate] defaultOpenVPNVersionIx];
    
    NSMutableArray * ovContent = [NSMutableArray arrayWithCapacity: [versions count] + 2];
    
    NSString * ver = [versions objectAtIndex: defaultIx];
    [ovContent addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                          [NSString stringWithFormat: NSLocalizedString(@"Default (%@)", @"Button"), ver], @"name",
                          @"", @"value",    // Empty name means default
                          nil]];
    
    NSUInteger ix;
    for (  ix=0; ix<[versions count]; ix++  ) {
        ver = [versions objectAtIndex: ix];
        [ovContent addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                               ver, @"name",
                               ver, @"value",
                               nil]];
    }
    [ovContent addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                          [NSString stringWithFormat: NSLocalizedString(@"Latest (%@)", @"Button"), [versions lastObject]], @"name",
                          @"-", @"value",    // "-" means latest
                          nil]];
    
    [perConfigOpenvpnVersionArrayController setContent: ovContent];
    [perConfigOpenvpnVersionButton sizeToFit];
    
    [alertSoundsBox setTitle: NSLocalizedString(@"Alert sounds", @"Window title")];
    
    [connectionAlertSoundTFC    setTitle: NSLocalizedString(@"Connection:", @"Window text")              ];
    [disconnectionAlertSoundTFC setTitle: NSLocalizedString(@"Unexpected disconnection:", @"Window text")];
    
    [self setTitle: NSLocalizedString(@"Advanced..." , @"Button") ofControl: advancedButton];
    [advancedButton setEnabled: ! [gTbDefaults boolForKey: @"disableAdvancedButton"]];
	
	[[NSApp delegate] setDoingSetupOfUI: savedDoingSetupOfUI];
}


// Sets the title for a control, shifting the origin of the control itself to the left, and the origin of other controls to the left or right to accomodate any change in width.
-(void) setTitle: (NSString *) newTitle ofControl: (id) theControl
{
    NSRect oldRect = [theControl frame];
    
    [theControl setTitle: newTitle];
    [theControl sizeToFit];
    
    NSRect newRect = [theControl frame];
    float widthChange = newRect.size.width - oldRect.size.width;
    NSRect oldPos;
    
    if (   [theControl isEqual: connectButton]              // Shift the control itself left/right if necessary
        || [theControl isEqual: disconnectButton]
        || [theControl isEqual: advancedButton]  ) {
        oldPos = [theControl frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [theControl setFrame:oldPos];
	}
    
    if (  [theControl isEqual: connectButton]  )  {          // If the Connect button changes, shift the Disconnect button left/right
        oldPos = [disconnectButton frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [disconnectButton setFrame:oldPos];
    }
}

//***************************************************************************************************************
// Getters

TBSYNTHESIZE_OBJECT_GET(retain, NSView *,              leftSplitView)

TBSYNTHESIZE_OBJECT_GET(retain, LeftNavViewController *, outlineViewController)
TBSYNTHESIZE_OBJECT_GET(retain, LeftNavDataSource *,   leftNavDataSrc)

TBSYNTHESIZE_OBJECT_GET(retain, NSScrollView *,        leftNavTableScrollView)
TBSYNTHESIZE_OBJECT_GET(retain, NSTableView *,         leftNavTableView)
TBSYNTHESIZE_OBJECT_GET(retain, NSTableColumn *,       leftNavTableColumn)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            addConfigurationButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            removeConfigurationButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSPopUpButton *,       workOnConfigurationPopUpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *,   workOnConfigurationArrayController)

TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          renameConfigurationMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          duplicateConfigurationMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          makePrivateOrSharedMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          revertToShadowMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          editOpenVPNConfigurationFileMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          showOpenvpnLogMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          removeCredentialsMenuItem)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            configurationsHelpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            disconnectButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            connectButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSTabView *,           configurationsTabView)

TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,       logTabViewItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextView *,          logView)

TBSYNTHESIZE_OBJECT_GET(retain, NSProgressIndicator *, progressIndicator)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            logToClipboardButton)


TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,       settingsTabViewItem)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,     whenToConnectTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSPopUpButton *,       whenToConnectPopUpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          whenToConnectManuallyMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          whenToConnectTunnelBlickLaunchMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          whenToConnectOnComputerStartMenuItem)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextField *,         setNameserverTF)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,     setNameserverTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSPopUpButton *,       setNameserverPopUpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *,   setNameserverArrayController)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            monitorNetworkForChangesCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            keepConnectedCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *,   perConfigOpenvpnVersionArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            perConfigOpenvpnVersionButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSBox *,               alertSoundsBox)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,     connectionAlertSoundTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,     disconnectionAlertSoundTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            soundOnConnectButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            soundOnDisconnectButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *,   soundOnConnectArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *,   soundOnDisconnectArrayController)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          advancedButton)

@end
