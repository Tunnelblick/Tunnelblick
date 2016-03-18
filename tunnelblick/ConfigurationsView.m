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


#import "ConfigurationsView.h"

#import "Helper.h"

#import "LeftNavDataSource.h"
#import "MenuController.h"
#import "MyPrefsWindowController.h"
#import "NSString+TB.h"
#import "TBUserDefaults.h"
#import "UIHelper.h"

extern NSFileManager  * gFileMgr;
extern TBUserDefaults * gTbDefaults;


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

-(void) shiftLabelsAndButtonsWtc: (CGFloat) wtcWidthChange sdns: (CGFloat) sdnsWidthChange pcov: (CGFloat) pcovWidthChange {
	
	// Shift all the labels and buttons by the largest width change, so the widest is flush left/right
	
	CGFloat largestWidthChange = wtcWidthChange;
	if (  largestWidthChange < sdnsWidthChange  ) {
		largestWidthChange = sdnsWidthChange;
	}
	if (  largestWidthChange < pcovWidthChange  ) {
		largestWidthChange = pcovWidthChange;
	}
	
	BOOL rtl = [UIHelper languageAtLaunchWasRTL];
	[UIHelper shiftControl: whenToConnectTF               by: largestWidthChange reverse: ! rtl];
	[UIHelper shiftControl: whenToConnectPopUpButton      by: largestWidthChange reverse: ! rtl];
	[UIHelper shiftControl: setNameserverTF               by: largestWidthChange reverse: ! rtl];
	[UIHelper shiftControl: setNameserverPopUpButton      by: largestWidthChange reverse: ! rtl];
	[UIHelper shiftControl: perConfigOpenvpnVersionTF     by: largestWidthChange reverse: ! rtl];
	[UIHelper shiftControl: perConfigOpenvpnVersionButton by: largestWidthChange reverse: ! rtl];
}

-(void) normalizeWidthOfConfigurationsButtons {
	
	NSArray * list = [NSArray arrayWithObjects: whenToConnectPopUpButton, setNameserverPopUpButton, perConfigOpenvpnVersionButton, nil];
	if (  [list count] > 0  ) {
		[UIHelper makeAllAsWideAsWidest: list shift: [UIHelper languageAtLaunchWasRTL]];
	}
}

-(void) awakeFromNib {
	
	BOOL savedDoingSetupOfUI = [((MenuController *)[NSApp delegate]) doingSetupOfUI];
    [((MenuController *)[NSApp delegate]) setDoingSetupOfUI: TRUE];
	
	BOOL rtl = [UIHelper languageAtLaunchWasRTL];
	
	CGFloat widthChange = [UIHelper setTitle: NSLocalizedString(@"Connect", @"Button") ofControl: connectButton shift: ( !rtl ) narrow: YES enable: YES];
	[UIHelper shiftControl: disconnectButton by: (- widthChange) reverse: ( !    rtl)];
	
	[UIHelper setTitle: NSLocalizedString(@"Disconnect", @"Button") ofControl: disconnectButton shift: ( !rtl) narrow: YES enable: YES];
    
	[UIHelper setTitle: NSLocalizedString(@"Copy Diagnostic Info to Clipboard", @"Button") ofControl: diagnosticInfoToClipboardButton shift: rtl narrow: YES enable: YES];
    
	
    // Left split view -- list of configurations and configuration manipulation
    
	NSTableColumn     * tableColumn = [self leftNavTableColumn];
	NSTableHeaderCell * tableCell = [tableColumn headerCell];
	[tableCell setTitle: NSLocalizedString(@"Configurations", @"Window text")];
	if (  rtl  ) {
		[tableCell       setAlignment: NSRightTextAlignment]; // Set the text in the header for the list of configurations (Tiger only) to be right aligned
		[leftNavTableTFC setAlignment: NSRightTextAlignment]; // Set the text in the list of configurations to be right aligned
	}
	
	if (  [UIHelper useOutlineViewOfConfigurations]  ) {
		
        NSOutlineView * outlineView = [ (NSScrollView *)[outlineViewController view] documentView];
		
		if (  rtl  ) {
			
			// Put the outlineView's disclosure triangle on the right instead of on the left
			if (  [outlineView respondsToSelector: @selector(setUserInterfaceLayoutDirection:)]  ) {
				
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
				
				// NSUserInterfaceLayoutDirection is not available in Xcode 3.2.2
				
				enum {
					NSUserInterfaceLayoutDirectionLeftToRight = 0,
					NSUserInterfaceLayoutDirectionRightToLeft = 1
				};
				typedef NSInteger NSUserInterfaceLayoutDirection;
				
				NSUserInterfaceLayoutDirection rightToLeftLayoutDirection = NSUserInterfaceLayoutDirectionRightToLeft;
				
				NSMethodSignature* signature = [[outlineView class] instanceMethodSignatureForSelector: @selector(setUserInterfaceLayoutDirection:)];
				NSInvocation* invocation = [NSInvocation invocationWithMethodSignature: signature];
				[invocation setTarget: outlineView];
				[invocation setSelector: @selector(setUserInterfaceLayoutDirection:)];
				[invocation setArgument: &rightToLeftLayoutDirection atIndex: 2];
				[invocation invoke];
				
#else		
				
				[outlineView setUserInterfaceLayoutDirection: NSUserInterfaceLayoutDirectionRightToLeft];
				
#endif
			}
		}
		
		[leftNavDataSrc reload];
        [outlineView setDataSource: leftNavDataSrc];
        [outlineView setDelegate:   leftNavDataSrc];
        [outlineView expandItem: [outlineView itemAtRow: 0]];

	} else {
	
		MyPrefsWindowController * wc = [((MenuController *)[NSApp delegate]) logScreen];
		[leftNavTableView setDelegate: wc];
 	}
	
	[renameConfigurationMenuItem          setTitle: NSLocalizedString(@"Rename Configuration..."                          , @"Menu Item")];
    [duplicateConfigurationMenuItem       setTitle: NSLocalizedString(@"Duplicate Configuration..."                       , @"Menu Item")];
    [makePrivateMenuItem			      setTitle: NSLocalizedString(@"Make Configuration Private..."                    , @"Menu Item")];
    [makeSharedMenuItem                   setTitle: NSLocalizedString(@"Make Configuration Shared..."                     , @"Menu Item")];
    [revertToShadowMenuItem			      setTitle: NSLocalizedString(@"Revert Configuration..."                          , @"Menu Item")];
    [showOnTbMenuMenuItem			      setTitle: NSLocalizedString(@"Show on Tunnelblick Menu"                         , @"Menu Item")];
    [doNotShowOnTbMenuMenuItem		      setTitle: NSLocalizedString(@"Do Not Show on Tunnelblick Menu"                  , @"Menu Item")];
    [editOpenVPNConfigurationFileMenuItem setTitle: NSLocalizedString(@"Edit OpenVPN Configuration File..."               , @"Menu Item")];
    [showOpenvpnLogMenuItem               setTitle: NSLocalizedString(@"Show OpenVPN Log in Finder"                       , @"Menu Item")];
    [removeCredentialsMenuItem            setTitle: NSLocalizedString(@"Delete Configuration's Credentials in Keychain...", @"Menu Item")];
    
    // "editOpenVPNConfigurationFileMenuItem" is initialized in validateDetailsWindowControls
    
    
    // Right split view - Log tab
    
    [logTabViewItem setLabel: NSLocalizedString(@"Log", @"Window title")];
    
    // Right split view - Settings tab
    
    [settingsTabViewItem setLabel: NSLocalizedString(@"Settings", @"Window title")];
    
    CGFloat wtcWidthChange = [UIHelper setTitle: NSLocalizedString(@"Connect:", @"Window text") ofControl: whenToConnectTFC frameHolder: whenToConnectTF shift: ( !rtl  ) narrow: YES enable: YES];
    [whenToConnectManuallyMenuItem          setTitle: NSLocalizedString(@"Manually"                 , @"Button")];
    [whenToConnectTunnelBlickLaunchMenuItem setTitle: NSLocalizedString(@"When Tunnelblick launches", @"Button")];
    [whenToConnectOnComputerStartMenuItem   setTitle: NSLocalizedString(@"When computer starts"     , @"Button")];
    [UIHelper setTitle: nil ofControl: whenToConnectPopUpButton shift: rtl narrow: YES enable: YES];
    
	CGFloat sdnsWidthChange = [UIHelper setTitle: NSLocalizedString(@"Set DNS/WINS:", @"Window text") ofControl: setNameserverTFC frameHolder: setNameserverTF shift: ( !rtl ) narrow: YES enable: YES];
	[UIHelper setTitle: nil ofControl: setNameserverPopUpButton shift: rtl narrow: YES enable: YES];
    // setNameserverPopUpButton is modified in setupSetNameserver to reflect per-configuration settings
	
    [monitorNetworkForChangesCheckbox             setTitle: NSLocalizedString(@"Monitor network settings",                                         @"Checkbox name")];
    [routeAllTrafficThroughVpnCheckbox            setTitle: NSLocalizedString(@"Route all IPv4 traffic through the VPN",                           @"Checkbox name")];
    [checkIPAddressAfterConnectOnAdvancedCheckbox setTitle: NSLocalizedString(@"Check if the apparent public IP address changed after connecting", @"Checkbox name")];
    [resetPrimaryInterfaceAfterDisconnectCheckbox setTitle: NSLocalizedString(@"Reset the primary interface after disconnecting" ,                 @"Checkbox name")];
    [disableIpv6OnTunCheckbox                     setTitle: NSLocalizedString(@"Disable IPv6 (tun only)",                                          @"Checkbox name")];
    
    // OpenVPN Version popup. Default depends on version of OS X
    
    CGFloat pcovWidthChange = [UIHelper setTitle: NSLocalizedString(@"OpenVPN version:", @"Window text") ofControl: perConfigOpenvpnVersionTFC frameHolder: perConfigOpenvpnVersionTF shift: ( !rtl ) narrow: YES enable: YES];
    
    NSArray  * versions  = [((MenuController *)[NSApp delegate]) openvpnVersionNames];
    NSUInteger defaultIx = [((MenuController *)[NSApp delegate]) defaultOpenVPNVersionIx];
    
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
	[UIHelper setTitle: nil ofControl: perConfigOpenvpnVersionButton shift: rtl narrow: YES enable: YES];
	
	[self shiftLabelsAndButtonsWtc: wtcWidthChange sdns: sdnsWidthChange pcov: pcovWidthChange];
	
	[self normalizeWidthOfConfigurationsButtons];
	
	[UIHelper setTitle: NSLocalizedString(@"Advanced..." , @"Button") ofControl: advancedButton shift: rtl narrow: YES enable: ( ! [gTbDefaults boolForKey: @"disableAdvancedButton"])];
	
	[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: savedDoingSetupOfUI];
}


//***************************************************************************************************************
// Getters

TBSYNTHESIZE_OBJECT_GET(retain, NSView *,              leftSplitView)

TBSYNTHESIZE_OBJECT_GET(retain, LeftNavViewController *, outlineViewController)
TBSYNTHESIZE_OBJECT_GET(retain, LeftNavDataSource *,   leftNavDataSrc)

TBSYNTHESIZE_OBJECT_GET(retain, NSTableView *,         leftNavTableView)
TBSYNTHESIZE_OBJECT_GET(retain, NSTableColumn *,       leftNavTableColumn)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,     leftNavTableTFC)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            addConfigurationButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            removeConfigurationButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSPopUpButton *,       workOnConfigurationPopUpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *,   workOnConfigurationArrayController)

TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          renameConfigurationMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          duplicateConfigurationMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          makePrivateMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          makeSharedMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          revertToShadowMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          showOnTbMenuMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          doNotShowOnTbMenuMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          editOpenVPNConfigurationFileMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          showOpenvpnLogMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          removeCredentialsMenuItem)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            configurationsHelpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            diagnosticInfoToClipboardButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSProgressIndicator *, diagnosticInfoToClipboardProgressIndicator)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            disconnectButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            connectButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSTabView *,           configurationsTabView)

TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,       logTabViewItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextView *,          logView)

TBSYNTHESIZE_OBJECT_GET(retain, NSProgressIndicator *, logDisplayProgressIndicator)


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
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            routeAllTrafficThroughVpnCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            checkIPAddressAfterConnectOnAdvancedCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            resetPrimaryInterfaceAfterDisconnectCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            disableIpv6OnTunCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *,   perConfigOpenvpnVersionArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            perConfigOpenvpnVersionButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          advancedButton)

@end
