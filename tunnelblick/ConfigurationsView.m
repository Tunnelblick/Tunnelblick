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


#import "ConfigurationsView.h"

#import "helper.h"

#import "LeftNavDataSource.h"
#import "MenuController.h"
#import "MyPrefsWindowController.h"
#import "NSString+TB.h"
#import "TBButton.h"
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

-(void)    shiftLabelsAndButtonsWtc: (CGFloat) wtcWidthChange
							   sdns: (CGFloat) sdnsWidthChange
							   pcov: (CGFloat) pcovWidthChange
		    loggingLevelWidthChange: (CGFloat) loggingLevelWidthChange
	      uponDisconnectWidthChange: (CGFloat) udWidthChange
uponUnexpectedDisconnectWidthChange: (CGFloat) uudWidthChange {
	
	// Shift all the labels and buttons by the largest width change, so the widest is flush left/right
	
	CGFloat largestWidthChange = wtcWidthChange;
	if (  largestWidthChange < sdnsWidthChange  ) {
		largestWidthChange = sdnsWidthChange;
	}
	if (  largestWidthChange < pcovWidthChange  ) {
		largestWidthChange = pcovWidthChange;
	}
	if (  largestWidthChange < loggingLevelWidthChange  ) {
		largestWidthChange = loggingLevelWidthChange;
	}
	if (  largestWidthChange < udWidthChange  ) {
		largestWidthChange = udWidthChange;
	}
	if (  largestWidthChange < uudWidthChange  ) {
		largestWidthChange = uudWidthChange;
	}
	
	BOOL rtl = [UIHelper languageAtLaunchWasRTL];
	[UIHelper shiftControl: whenToConnectTF               by: largestWidthChange reverse: ! rtl];
	[UIHelper shiftControl: whenToConnectPopUpButton      by: largestWidthChange reverse: ! rtl];
	[UIHelper shiftControl: setNameserverTF               by: largestWidthChange reverse: ! rtl];
	[UIHelper shiftControl: setNameserverPopUpButton      by: largestWidthChange reverse: ! rtl];
	[UIHelper shiftControl: perConfigOpenvpnVersionTF     by: largestWidthChange reverse: ! rtl];
	[UIHelper shiftControl: perConfigOpenvpnVersionButton by: largestWidthChange reverse: ! rtl];
	
	if (  loggingLevelPopUpButton  ) {
		[UIHelper shiftControl: loggingLevelTF            by: largestWidthChange reverse: ! rtl];
		[UIHelper shiftControl: loggingLevelPopUpButton   by: largestWidthChange reverse: ! rtl];
	}
	
	[UIHelper shiftControl: uponDisconnectTF                    by: largestWidthChange reverse: ! rtl];
	[UIHelper shiftControl: uponDisconnectPopUpButton           by: largestWidthChange reverse: ! rtl];

	[UIHelper shiftControl: uponUnexpectedDisconnectTF          by: largestWidthChange reverse: ! rtl];
	[UIHelper shiftControl: uponUnexpectedDisconnectPopUpButton by: largestWidthChange reverse: ! rtl];
}

-(void) normalizeWidthOfConfigurationsButtons {
	
	NSArray * list = [NSArray arrayWithObjects: whenToConnectPopUpButton, setNameserverPopUpButton, perConfigOpenvpnVersionButton, loggingLevelPopUpButton, uponDisconnectPopUpButton, uponUnexpectedDisconnectPopUpButton, nil];
	if (  [list count] > 0  ) {
		[UIHelper makeAllAsWideAsWidest: list shift: [UIHelper languageAtLaunchWasRTL]];
	}
}

-(void) setupLoggingLevelPopUpButton {
	
    NSMutableArray * content = [[NSMutableArray alloc] initWithCapacity: 14];
    
    // First item is "No logging"
    NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                           NSLocalizedString(@"No OpenVPN or Tunnelblick VPN logging" , @"Menu Item"), @"name",
                           [NSNumber numberWithInt: TUNNELBLICK_NO_LOGGING_LEVEL],                     @"value",
                           nil];
    [content addObject: dict];
    
    // Second item is "Set by configuration"
    dict = [NSDictionary dictionaryWithObjectsAndKeys:
            NSLocalizedString(@"OpenVPN logging level set by the configuration" , @"Menu Item"),    @"name",
            [NSNumber numberWithInt: TUNNELBLICK_CONFIG_LOGGING_LEVEL],                             @"value",
            nil];
    [content addObject: dict];
    
    // The rest of the items are the OpenVPN logging levels 1...11
    NSUInteger ix;
    for (  ix=MIN_OPENVPN_LOGGING_LEVEL; ix<=MAX_OPENVPN_LOGGING_LEVEL; ix++  ) {
        NSString * label;
        switch (  ix  ) {
            case 0:
                label = NSLocalizedString(@"OpenVPN level 0 - no output except fatal errors", @"Menu Item");
                break;
                
            case 3:
                label = NSLocalizedString(@"OpenVPN level 3 - normal output", @"Menu Item");
                break;
                
            case 4:
                label = NSLocalizedString(@"OpenVPN level 4 - values for all options", @"Menu Item");
                break;
                
            case 5:
                label = NSLocalizedString(@"OpenVPN level 5 - \"R\" or \"W\" for each packet", @"Menu Item");
                break;
                
            case 6:
                label = NSLocalizedString(@"OpenVPN level 6 - very verbose output", @"Menu Item");
                break;
                
            case 11:
                label = NSLocalizedString(@"OpenVPN level 11 - extremely verbose output", @"Menu Item");
                break;
                
            default:
                label = [NSString stringWithFormat: NSLocalizedString(@"OpenVPN level %lu", @"Menu Item"), ix];
                break;
        }
        dict = [NSDictionary dictionaryWithObjectsAndKeys:
                label,                                @"name",
                [NSNumber numberWithUnsignedInt: ix], @"value",
                nil];
        [content addObject: dict];
    }
    [[self loggingLevelArrayController] setContent: content];
}

-(void) awakeFromNib {
	
	BOOL savedDoingSetupOfUI = [((MenuController *)[NSApp delegate]) doingSetupOfUI];
    [((MenuController *)[NSApp delegate]) setDoingSetupOfUI: TRUE];
	
	BOOL rtl = [UIHelper languageAtLaunchWasRTL];
	
	CGFloat widthChange = [UIHelper setTitle: NSLocalizedString(@"Connect", @"Button") ofControl: connectButton shift: ( !rtl ) narrow: YES enable: YES];
	[UIHelper shiftControl: disconnectButton by: (- widthChange) reverse: ( !    rtl)];
	
	[UIHelper setTitle: NSLocalizedString(@"Disconnect", @"Button") ofControl: disconnectButton shift: ( !rtl) narrow: YES enable: YES];
    
	[diagnosticInfoToClipboardButton
	 setTitle: nil
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>Copies information to the Clipboard to help diagnose problems.</p>"
														   @"<p>The information includes software versions and settings, the OpenVPN configuration file,"
														   @" network settings and more.</p>"
														   @"<p>Sensitive certificate information is not included, but data such as IP addresses and URLs"
														   @" which <em>may</em> be confidential are included. You should examine the information and"
														   @" remove anything you want kept secret before sending it in an email or posting it publicly.</p>",
														   @"HTML info for the 'Copy Diagnostic Info to Clipboard' button."))];
	[UIHelper setTitle: NSLocalizedString(@"Copy Diagnostic Info to Clipboard", @"Button") ofControl: diagnosticInfoToClipboardButton shift: rtl narrow: YES enable: YES];
    
	
    // Left split view -- list of configurations and configuration manipulation
    
	if (  rtl  ) {
		[leftNavTableTFC setAlignment: NSRightTextAlignment]; // Set the text in the list of configurations to be right aligned
	}
	
    NSOutlineView * outlineView = [ (NSScrollView *)[outlineViewController view] documentView];
    
    if (  rtl  ) {
        
        // Put the outlineView's disclosure triangle on the right instead of on the left
        if (  [outlineView respondsToSelector: @selector(setUserInterfaceLayoutDirection:)]  ) {
            [outlineView setUserInterfaceLayoutDirection: NSUserInterfaceLayoutDirectionRightToLeft];
        }
    }
    
    [leftNavDataSrc reload];
    [outlineView setDataSource: leftNavDataSrc];
    [outlineView setDelegate:   leftNavDataSrc];
    [outlineView expandItem: [outlineView itemAtRow: 0]];
	
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
	[whenToConnectPopUpButton
	 setTitle: nil
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>Specifies when Tunnelblick should connect to the VPN.</strong></p>"
														   @"<p>\"When computer starts\" may only be used with \"Shared\" configurations.</p>",
														   @"HTML info for the 'Connect' button."))];
    [UIHelper setTitle: nil ofControl: whenToConnectPopUpButton shift: rtl narrow: YES enable: YES];
    
	CGFloat sdnsWidthChange = [UIHelper setTitle: NSLocalizedString(@"Set DNS/WINS:", @"Window text") ofControl: setNameserverTFC frameHolder: setNameserverTF shift: ( !rtl ) narrow: YES enable: YES];
	[setNameserverPopUpButton
	 setTitle: nil
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>Specifies what (if anything) Tunnelblick does to modify DNS settings while the"
														   @" VPN is connected.</strong> The choices are:"
														   
														   @"<ul>"
														   
														   @"<li><strong>Do not set nameserver</strong>: Nothing is done.<br></li>"
														   
														   @"<li><strong>Set nameserver</strong>: Tunnelblick uses its standard script to handle DNS"
														   @" and WINS settings. This is usually the best choice. It changes DNS and WINS settings"
														   @" according to instructions provided by OpenVPN. DNS and WINS settings that have been"
														   @" set manually will not be changed unless \"Allow changes to manually-set network"
														   @" settings\" has been selected in the \"Advanced\" settings window<br></li>"
														   
														   @"<li><strong>Set nameserver (3.1)</strong>: Tunnelblick uses the script from Tunnelblick 3.1"
														   @" to handle DNS and WINS settings.<br></li>"
														   
														   @"<li><strong>Set nameserver (3.0b10)</strong>: Tunnelblick uses the script from Tunnelblick"
														   @" 3.0b10 to handle DNS and WINS settings.<br></li>"
														   
														   @"<li><strong>Set nameserver (alternate 1)</strong>: Tunnelblick uses an alternate script to"
														   @" handle DNS and WINS settings.<br></li>"
														   
														   @"</ul>",
														   
														   @"HTML info for the 'Set DNS/WINS' button."))];
	[UIHelper setTitle: nil ofControl: setNameserverPopUpButton shift: rtl narrow: YES enable: YES];
    // setNameserverPopUpButton is modified in setupSetNameserver to reflect per-configuration settings
	
	CGFloat loggingLevelWidthChange = 0.0;
	if (  loggingLevelPopUpButton  ) {
		loggingLevelWidthChange = [UIHelper setTitle: NSLocalizedString(@"VPN log level:", @"Window text") ofControl: loggingLevelTFC frameHolder: loggingLevelTF shift: ( !rtl ) narrow: YES enable: YES];
		[self setupLoggingLevelPopUpButton];
		[loggingLevelPopUpButton
		 setTitle: nil
		 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>Specifies the amount of logging that is done by Tunnelblick and OpenVPN.</p>",
															   @"HTML info for the 'VPN log level' button."))];
		[UIHelper setTitle: nil ofControl: loggingLevelPopUpButton shift: rtl narrow: YES enable: YES];
	}
	
	CGFloat udWidthChange = [UIHelper setTitle: NSLocalizedString(@"On expected disconnect:", @"Window text") ofControl: uponDisconnectTFC frameHolder: uponDisconnectTF shift: ( !rtl  ) narrow: YES enable: YES];
	[uponDisconnectDoNothingMenuItem setTitle:             NSLocalizedString(@"Do nothing",			     @"Button")];
	[uponDisconnectResetPrimaryInterfaceMenuItem setTitle: NSLocalizedString(@"Reset primary interface", @"Button")];
	[uponDisconnectDisableNetworkAccessMenuItem  setTitle: NSLocalizedString(@"Disable network access",  @"Button")];
	[uponDisconnectPopUpButton
	 setTitle: nil
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>Specifies what Tunnelblick does when the VPN disconnects <em>as"
														   @" expected</em></strong> (for example, a \"Disconnect\" menu item or button is clicked). The"
														   @" choices are:</p>"
														   
														   @"<ul>"
														   
														   @"<li><strong>Do nothing</strong><br></li>"
														   
														   @"<li><strong>Reset primary interface</strong>: Tunnelblick resets the primary network interface"
														   @" by issuing 'ipconfig down; ipconfig up' commands to the interface. This can"
														   @" be helpful when a configuration fails to restore network settings properly after a"
														   @" disconnection.<br></li>"
														   
														   @"<li><strong>Disable network access (\"Kill Switch\")</strong>: Tunnelblick"
														   @" cuts off all network access (local and Internet) by turning off Wi-Fi and"
														   @" disabling all other network services. This can help ensure that nothing leaks out"
														   @" of the computer except through the VPN. If Tunnelblick has disabled network"
														   @" access a menu command to re-enable all access that was disabled will be"
														   @" available from the Tunnelblick icon in the menu bar. You can also re-enable"
														   @" Wi-Fi by turning it on, or re-enable other network services in System"
														   @" Preferences : Network. <strong>This setting may not work properly when more"
														   @" than one VPN is connected simultaneously.</strong></li>"
														   
														   @"</ul>",
														   
														   @"HTML info for the 'On expected disconnect' button."))];
	[UIHelper setTitle: nil ofControl: uponDisconnectPopUpButton shift: rtl narrow: YES enable: YES];

	CGFloat uudWidthChange = [UIHelper setTitle: NSLocalizedString(@"On unexpected disconnect:", @"Window text") ofControl: uponUnexpectedDisconnectTFC frameHolder: uponUnexpectedDisconnectTF shift: ( !rtl  ) narrow: YES enable: YES];
	[uponUnexpectedDisconnectDoNothingMenuItem             setTitle: NSLocalizedString(@"Do nothing",			   @"Button")];
	[uponUnexpectedDisconnectResetPrimaryInterfaceMenuItem setTitle: NSLocalizedString(@"Reset primary interface", @"Button")];
	[uponUnexpectedDisconnectDisableNetworkAccessMenuItem  setTitle: NSLocalizedString(@"Disable network access",  @"Button")];
	[uponUnexpectedDisconnectPopUpButton
	 setTitle: nil
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>Specifies what Tunnelblick does when the VPN <em>unexpectedly</em>"
														   @" disconnects</strong> (for example, if OpenVPN crashes or loses its connection"
														   @" to the VPN and is set up to stop when that happens). The choices are:</p>"
														   
														   @"<ul>"
														   
														   @"<li><strong>Do nothing</strong><br></li>"
														   
														   @"<li><strong>Reset primary interface</strong>: Tunnelblick resets the primary network interface"
														   @" by issuing 'ipconfig down; ipconfig up' commands to the interface. This can"
														   @" be helpful when a configuration fails to restore network settings properly after a"
														   @" disconnection.<br></li>"
														   
														   @"<li><strong>Disable network access (\"Kill Switch\")</strong>: Tunnelblick"
														   @" cuts off all network access (local and Internet) by turning off Wi-Fi and"
														   @" disabling all other network services. This can help ensure that nothing leaks out"
														   @" of the computer except through the VPN. If Tunnelblick has disabled network"
														   @" access a menu command to re-enable all access that was disabled will be"
														   @" available from the Tunnelblick icon in the menu bar. You can also re-enable"
														   @" Wi-Fi by turning it on, or re-enable other network services in System"
														   @" Preferences : Network. <strong>This setting may not work properly when more"
														   @" than one VPN is connected simultaneously.</strong></li>"
														   
														   @"</ul>",
														   
														   @"HTML info for the 'On unexpected disconnect' button."))];
	[UIHelper setTitle: nil ofControl: uponUnexpectedDisconnectPopUpButton shift: rtl narrow: YES enable: YES];

	
    // OpenVPN Version popup.
    
    CGFloat pcovWidthChange = [UIHelper setTitle: NSLocalizedString(@"OpenVPN version:", @"Window text") ofControl: perConfigOpenvpnVersionTFC frameHolder: perConfigOpenvpnVersionTF shift: ( !rtl ) narrow: YES enable: YES];
    
    NSArray  * versionNames  = [((MenuController *)[NSApp delegate]) openvpnVersionNames];
    
    NSMutableArray * ovContent = [NSMutableArray arrayWithCapacity: [versionNames count] + 2];
    
	NSString * folderName = defaultOpenVpnFolderName();
	if (  [folderName hasPrefix: @"openvpn-"]  ) {
		folderName = [folderName substringFromIndex: [@"openvpn-" length]];
	} else {
		NSLog(@"defaultOpenVpnFolderName() result '%@' did not start with 'openvpn-", folderName);
	}
	NSString * displayedVersion = displayNameForOpenvpnName(folderName, nil);
	if (  displayedVersion) {
		[ovContent addObject:[NSDictionary dictionaryWithObjectsAndKeys:
							  [NSString stringWithFormat: NSLocalizedString(@"Default (%@)", @"Button"), displayedVersion], @"name",
							  @"", @"value",    // Empty name means default
							  nil]];
	}
	
    NSUInteger ix;
    for (  ix=0; ix<[versionNames count]; ix++  ) {
        NSString * ver = [versionNames objectAtIndex: ix];
        NSString * name = displayNameForOpenvpnName(ver, nil);
        if (  name  ) {
            [ovContent addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                   name, @"name",
                                   ver,  @"value",
                                   nil]];
        }
    }
	displayedVersion = displayNameForOpenvpnName([versionNames lastObject], nil);
	if (  displayedVersion  ) {
		[ovContent addObject:[NSDictionary dictionaryWithObjectsAndKeys:
							  [NSString stringWithFormat: NSLocalizedString(@"Latest (%@)", @"Button"), displayedVersion], @"name",
							  @"-", @"value",    // "-" means latest
							  nil]];
	}
    
    [perConfigOpenvpnVersionArrayController setContent: ovContent];
	[perConfigOpenvpnVersionButton
	 setTitle: nil
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>Specifies the version of OpenVPN and the SSL software that should be used to"
														   @" connect the VPN.</strong>"
														   
														   @"<ul>"
														   
														   @"<li><strong>The \"Default\" setting</strong> will use the default version of OpenVPN with OpenSSL that is"
														   @" included in this version of Tunnelblick. The default may be different in different versions of Tunnelblick.<br></li>"

														   @"<li><strong>The \"Latest\" setting</strong> will use the latest version of OpenVPN with LibreSSL that is"
														   @" included in this version of Tunnelblick. The latest version may be different in different versions of Tunnelblick.<br></li>"
														   
														   @"<li><strong>Any other setting</strong> will use the specified version of OpenVPN and SSL software if they are"
														   @" available in this version of Tunnelblick. If not available, the closest match will be used.<br></li>"
														   
														   @"</ul>",

														   @"HTML info for the 'OpenVPN version' button."))];
	[UIHelper setTitle: nil ofControl: perConfigOpenvpnVersionButton shift: rtl narrow: YES enable: YES];
	
	[self shiftLabelsAndButtonsWtc: wtcWidthChange sdns: sdnsWidthChange pcov: pcovWidthChange loggingLevelWidthChange: loggingLevelWidthChange uponDisconnectWidthChange: udWidthChange uponUnexpectedDisconnectWidthChange: uudWidthChange];
	
	[self normalizeWidthOfConfigurationsButtons];
	
	[monitorNetworkForChangesCheckbox
	 setTitle: NSLocalizedString(@"Monitor network settings", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, Tunnelblick will watch for and react to changes in network"
														   @" settings (for example, changes caused by DHCP renewals or switching Internet connections) to attempt to keep the VPN connected. Tunnelblick's default actions when network"
														   @" settings change usually work well, but you may specify different actions on the 'While Connected' tab of the 'Advanced' settings window.</p>\n"
														   @"<p><strong>When not checked</strong>, Tunnelblick will ignore network changes.</p>\n"
														   @"<p><strong>This checkbox is disabled</strong> when 'Set DNS/WINS' is not set to 'Set nameserver' or 'Set nameserver (3.1)'.</p>",
														   @"HTML info for the 'Monitor network settings' checkbox."))];
	
	[routeAllTrafficThroughVpnCheckbox
	 setTitle: NSLocalizedString(@"Route all IPv4 traffic through the VPN", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, Tunnelblick will instruct OpenVPN to route all IPv4 traffic through the VPN server.</p>\n"
														   @"<p><strong>When not checked</strong>, by default OpenVPN will use the VPN only for traffic that"
														   @" is destined for the VPN's network. All other traffic will use the normal Internet connection without going through the VPN."
														   @" OpenVPN's default behavior may be changed by the OpenVPN configuration or the VPN server and cause all IPv4"
														   @" traffic to be routed through the VPN server as if this checkbox had been checked. </p>\n",
														   @"HTML info for the 'Route all IPv4 traffic through the VPN' checkbox."))];
	
	[disableIpv6OnTunCheckbox
	 setTitle: NSLocalizedString(@"Disable IPv6 unless the VPN server is accessed using IPv6 (tun only)", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, IPv6 will be disabled unless the OpenVPN server is being accessed via an IPv6 address.</p>\n"
														   @"<p>Disabling IPv6 is often recommended because many VPN configurations do not guard against information leaks caused by the use"
														   @" of IPv6. Most Internet access works fine without IPv6.</p>\n"
														   @"<p><strong>When not checked</strong>, IPv6 will not be disabled.</p>\n"
														   @"<p><strong>This checkbox is disabled</strong> when using a 'tap' connection because it"
														   @" cannot be enforced on a 'tap' connection.</p>",
														   @"HTML info for the 'Disable IPv6 unless the VPN server is accessed using IPv6 (tun only)' checkbox."))];
	
	[checkIPAddressAfterConnectOnAdvancedCheckbox
	 setTitle: NSLocalizedString(@"Check if the apparent public IP address changed after connecting", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, Tunnelblick will determine the computer's apparent public IP"
														   @" address before and after the VPN is connected and warn if the IP address does not change.</p>\n"
														   @"<p>The tunnelblick.net website will be accessed to perform this function. The access is usually done via https:"
														   @" using the tunnelblick.net name, except that if that access fails, access is attempted using http:"
														   @" and the IP address of the website.</p>\n"
														   @"<p><strong>When not checked</strong>, Tunnelblick does not check for IP address changes and"
														   @" does not warn if the IP address does not change after the VPN is connected.</p>\n",
														   @"HTML info for the 'Check if the apparent public IP address changed after connecting' checkbox."))];
	
	[advancedButton
	 setTitle: NSLocalizedString(@"Advanced...", @"Button")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>Opens a window with additional settings.</p>"
														   @"<p>Any changes will be applied to all configurations that are selected in the 'VPN Details' window.</p>",
														   @"HTML info for the 'Advanced...' button."))
	 disabled: [gTbDefaults boolForKey: @"disableAdvancedButton"]];
	
	[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: savedDoingSetupOfUI];
}


//***************************************************************************************************************
// Getters

TBSYNTHESIZE_OBJECT_GET(retain, NSView *,              leftSplitView)

TBSYNTHESIZE_OBJECT_GET(retain, LeftNavViewController *, outlineViewController)
TBSYNTHESIZE_OBJECT_GET(retain, LeftNavDataSource *,   leftNavDataSrc)

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
TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,            diagnosticInfoToClipboardButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSProgressIndicator *, diagnosticInfoToClipboardProgressIndicator)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            disconnectButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            connectButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSTabView *,           configurationsTabView)

TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,       logTabViewItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextView *,          logView)

TBSYNTHESIZE_OBJECT_GET(retain, NSProgressIndicator *, logDisplayProgressIndicator)


TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,       settingsTabViewItem)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,     whenToConnectTFC)
TBSYNTHESIZE_OBJECT_GET(retain, TBPopUpButton *,       whenToConnectPopUpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          whenToConnectManuallyMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          whenToConnectTunnelBlickLaunchMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          whenToConnectOnComputerStartMenuItem)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextField *,         setNameserverTF)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,     setNameserverTFC)
TBSYNTHESIZE_OBJECT_GET(retain, TBPopUpButton *,       setNameserverPopUpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *,   setNameserverArrayController)

TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,            monitorNetworkForChangesCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,            routeAllTrafficThroughVpnCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,            disableIpv6OnTunCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,            checkIPAddressAfterConnectOnAdvancedCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *,   perConfigOpenvpnVersionArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, TBPopUpButton *,       perConfigOpenvpnVersionButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextField *,         loggingLevelTF)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,     loggingLevelTFC)
TBSYNTHESIZE_OBJECT_GET(retain, TBPopUpButton *,       loggingLevelPopUpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *,   loggingLevelArrayController)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,     uponDisconnectTFC)
TBSYNTHESIZE_OBJECT_GET(retain, TBPopUpButton *,       uponDisconnectPopUpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          uponDisconnectDoNothingMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          uponDisconnectResetPrimaryInterfaceMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          uponDisconnectDisableNetworkAccessMenuItem)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,     uponUnexpectedDisconnectTFC)
TBSYNTHESIZE_OBJECT_GET(retain, TBPopUpButton *,       uponUnexpectedDisconnectPopUpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          uponUnexpectedDisconnectDoNothingMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          uponUnexpectedDisconnectResetPrimaryInterfaceMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          uponUnexpectedDisconnectDisableNetworkAccessMenuItem)

TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,            advancedButton)

@end
