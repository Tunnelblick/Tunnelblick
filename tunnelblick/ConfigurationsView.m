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
 *  distribution); if not, see http://www.gnu.org/licenses/.
 */


#import "ConfigurationsView.h"

#import "helper.h"

#import "LeftNavDataSource.h"
#import "LeftNavViewController.h"
#import "MenuController.h"
#import "MyPrefsWindowController.h"
#import "NSString+TB.h"
#import "TBButton.h"
#import "TBPopUpButton.h"
#import "TBUserDefaults.h"
#import "TunnelblickInfo.h"
#import "UIHelper.h"
#import "VPNConnection.h"

extern NSFileManager  * gFileMgr;
extern MenuController * gMC;
extern TBUserDefaults * gTbDefaults;
extern TunnelblickInfo * gTbInfo;

// A flipped view, so content in a scroll view starts at the top
@interface TBFlippedView : NSView
@end

@implementation TBFlippedView
-(BOOL) isFlipped {
	return YES;
}
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
	[viewSelector        release]; viewSelector        = nil;
	[statusIconView      release]; statusIconView      = nil;
	[statusTitleTF       release]; statusTitleTF       = nil;
	[statusDetailTF      release]; statusDetailTF      = nil;
	
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
	
	BOOL savedDoingSetupOfUI = [gMC doingSetupOfUI];
    [gMC setDoingSetupOfUI: TRUE];
	
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
    
    [outlineView setDataSource: leftNavDataSrc];
    [outlineView setDelegate:   leftNavDataSrc];
	
    [c_o_p_yConfigurationsIntoNewFolderMenuItem setTitle: NSLocalizedString(@"Copy Configuration into a New Folder..."      , @"Menu Item")];
    [moveConfigurationsIntoNewFolderMenuItem setTitle: NSLocalizedString(@"Move Configuration into a New Folder..."      , @"Menu Item")];
	[renameConfigurationMenuItem          setTitle: NSLocalizedString(@"Rename Configuration"                             , @"Menu Item")];
    [duplicateConfigurationMenuItem       setTitle: NSLocalizedString(@"Duplicate Configuration..."                       , @"Menu Item")];
    [makePrivateMenuItem			      setTitle: NSLocalizedString(@"Make Configuration Private..."                    , @"Menu Item")];
    [makeSharedMenuItem                   setTitle: NSLocalizedString(@"Make Configuration Shared..."                     , @"Menu Item")];
    [revertToShadowMenuItem			      setTitle: NSLocalizedString(@"Revert Configuration..."                          , @"Menu Item")];
    [showOnTbMenuMenuItem			      setTitle: NSLocalizedString(@"Show on Tunnelblick Menu"                         , @"Menu Item")];
    [doNotShowOnTbMenuMenuItem		      setTitle: NSLocalizedString(@"Do Not Show on Tunnelblick Menu"                  , @"Menu Item")];
    [editOpenVPNConfigurationFileMenuItem setTitle: NSLocalizedString(@"Edit OpenVPN Configuration File..."               , @"Menu Item")];
    [showOpenvpnLogMenuItem               setTitle: NSLocalizedString(@"Show OpenVPN Log in Finder"                       , @"Menu Item")];
    [removeCredentialsMenuItem            setTitle: NSLocalizedString(@"Delete Configuration's Credentials in Keychain...", @"Menu Item")];
    
    // "editOpenVPNConfigurationFileMenuItem" is initialized in validateDetailsWindowControlsForConnection:
    
    
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
														   @"<p>\"When computer starts\" may only be used with \"Shared\" configurations that do not have credentials (username/password/passphrase)"
														   @" stored in Keychain and do not use the OpenVPN 'auth-user-pass' option without an argument.</p>",
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

                                                           @"<li><strong>Set nameserver (alternate 2)</strong>: Tunnelblick uses an alternate script to"
                                                           @" handle DNS and WINS settings.<br></li>"

                                                           @"<li><strong>Set nameserver (OpenVPN)</strong>: Tunnelblick uses OpenVPN's default script to"
                                                           @" handle DNS settings.<br></li>"

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
    
    NSArray  * versionNames  = gTbInfo.allOpenvpnOpenssslVersions;

    NSMutableArray * ovContent = [NSMutableArray arrayWithCapacity: [versionNames count] + 2];
    
	NSString * folderName = [gTbInfo.defaultOpenvpnOpensslVersion substringFromIndex: [@"openvpn-" length]];
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
	NSString * html = NSLocalizedString(@"<p><strong>Specifies the version of OpenVPN and the SSL software that should be used to"
										@" connect the VPN.</strong>"

										@"<ul>"

										@"<li><strong>The \"Default\" setting</strong> will use the default version of OpenVPN with OpenSSL that is"
										@" included in this version of Tunnelblick. The default may be different in different versions of Tunnelblick.<br></li>"

										@"<li><strong>The \"Latest\" setting</strong> will use the latest version of OpenVPN with OpenSSL that is"
										@" included in this version of Tunnelblick. The latest version may be different in different versions of Tunnelblick.<br></li>"

										@"<li><strong>Any other setting</strong> will use the specified version of OpenVPN and SSL software if they are"
										@" available in this version of Tunnelblick. If not available, the closest match will be used.<br></li>"

										@"</ul>",

										@"HTML info for the 'OpenVPN version' button.");
	if (  [gFileMgr fileExistsAtPath: L_AS_T_OPENVPN]  ) {
		html = [html stringByAppendingString: NSLocalizedString(@"<p>'<strong>Imported</strong>' versions of OpenVPN may be used but were not included in this copy of the Tunnelblick application."
																@" They were imported and installed by a computer administrator.</p>",
																@"HTML info for the 'OpenVPN version' button.")];
	}

	[perConfigOpenvpnVersionButton
	 setTitle: nil
	 infoTitle: attributedStringFromHTML(html)];
	[UIHelper setTitle: nil ofControl: perConfigOpenvpnVersionButton shift: rtl narrow: YES enable: YES];
	
	[self shiftLabelsAndButtonsWtc: wtcWidthChange sdns: sdnsWidthChange pcov: pcovWidthChange loggingLevelWidthChange: loggingLevelWidthChange uponDisconnectWidthChange: udWidthChange uponUnexpectedDisconnectWidthChange: uudWidthChange];
	
	[self normalizeWidthOfConfigurationsButtons];
	
	[monitorNetworkForChangesCheckbox
	 setTitle: NSLocalizedString(@"Monitor network settings", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, Tunnelblick will watch for and react to changes in network"
														   @" settings (for example, changes caused by DHCP renewals or switching Internet connections) to attempt to keep the VPN connected. Tunnelblick's default actions when network"
														   @" settings change usually work well, but you may specify different actions on the 'While Connected' tab of the 'Advanced' settings window.</p>\n"
														   @"<p><strong>When not checked</strong>, Tunnelblick will ignore network changes.</p>\n"
														   @"<p><strong>This checkbox is disabled</strong> when 'Set DNS/WINS' is not set to 'Set nameserver', 'Set nameserver (alternate 1)',"
														   @" 'Set nameserver (alternate 2)', or 'Set nameserver (OpenVPN)'.</p>",
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
	 setTitle: NSLocalizedString(@"Disable IPv6 unless the VPN server is accessed using IPv6", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, IPv6 will be disabled unless the OpenVPN server is being accessed via an IPv6 address.</p>\n"
														   @"<p>Disabling IPv6 is often recommended because many VPN configurations do not guard against information leaks caused by the use"
														   @" of IPv6. Most Internet access works fine without IPv6.</p>\n"
														   @"<p><strong>When not checked</strong>, IPv6 will not be disabled.</p>\n"
														   @"<p><strong>This checkbox is disabled</strong> when using a 'tap' connection because it"
														   @" cannot be enforced on a 'tap' connection, and when 'Set DNS/WINS' is not set to 'Set nameserver',"
														   @" 'Set nameserver (alternate 2)', or 'Set nameserver (OpenVPN)' because only those settings can disable IPv6.</p>",
														   @"HTML info for the 'Disable IPv6 unless the VPN server is accessed using IPv6' checkbox."))];
	
    [disableSecondaryNetworkServicesCheckbox
     setTitle: NSLocalizedString(@"Disable secondary network interfaces", @"Checkbox name")
     infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, all network interfaces except the primary interface will"
                                                           @" be disabled while the VPN is active.</p>\n"
                                                           @"<p>This is recommended because Tunnelblick sets up DNS only on the primary network interface.</p>\n"
                                                           @"<p><strong>When not checked</strong>, secondary network interfaces are not disabled.</p>\n"
                                                           @"<p><strong>This checkbox is disabled</strong> when using a 'tap' connection, and when 'Set DNS/WINS' is not set to 'Set nameserver',"
                                                           @" 'Set nameserver (alternate 2)', or 'Set nameserver (OpenVPN)'.</p>",
                                                           @"HTML info for the 'Disable secondary network interfaces' checkbox.\n\n"))];

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

    LeftNavViewController * oVC = [self outlineViewController];
    NSOutlineView         * oView = [oVC outlineView];
    [oView registerForDraggedTypes: [NSArray arrayWithObject: TB_LEFT_NAV_ITEMS_DRAG_ID]];

	[gMC setDoingSetupOfUI: savedDoingSetupOfUI];
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

TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          c_o_p_yConfigurationsIntoNewFolderMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          moveConfigurationsIntoNewFolderMenuItem)
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
TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,            disableSecondaryNetworkServicesCheckbox)
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



//*********************************************************************************************************
//
// Modern layout: status card, segmented control instead of tabs, Settings tab as a form
//
//*********************************************************************************************************

-(NSBox *) newCardBox {
	
	NSBox * box = [[NSBox alloc] init];
	[box setBoxType: NSBoxCustom];
	[box setTitlePosition: NSNoTitle];
	[box setCornerRadius: 12.0];
	[box setBorderWidth: 1.0];
	[box setBorderColor: [NSColor separatorColor]];
	[box setFillColor: [NSColor controlBackgroundColor]];
	[box setContentViewMargins: NSMakeSize(16.0, 14.0)];
	[box setTranslatesAutoresizingMaskIntoConstraints: NO];
	return box;
}

-(void) setContent: (NSView *) content ofCard: (NSBox *) box {
	
	[content setTranslatesAutoresizingMaskIntoConstraints: NO];
	NSView * contentView = [box contentView];
	[contentView addSubview: content];
	[NSLayoutConstraint activateConstraints: @[[[content topAnchor]      constraintEqualToAnchor: [contentView topAnchor]],
											   [[content bottomAnchor]   constraintEqualToAnchor: [contentView bottomAnchor]],
											   [[content leadingAnchor]  constraintEqualToAnchor: [contentView leadingAnchor]],
											   [[content trailingAnchor] constraintEqualToAnchor: [contentView trailingAnchor]]]];
}

-(NSTextField *) labelWithFont: (NSFont *) font color: (NSColor *) color {
	
	NSTextField * label = [NSTextField labelWithString: @""];
	[label setFont: font];
	[label setTextColor: color];
	[label setLineBreakMode: NSLineBreakByTruncatingTail];
	[label setTranslatesAutoresizingMaskIntoConstraints: NO];
	return label;
}

-(NSView *) newStatusCard {
	
	// Icon, state ("Connected", ...) and traffic of the selected configuration, with the Connect and Disconnect buttons
	// (the existing ones, moved here). Uses only existing localized strings.
	statusIconView = [[NSImageView alloc] init];
	[statusIconView setTranslatesAutoresizingMaskIntoConstraints: NO];
	[statusIconView setSymbolConfiguration: [NSImageSymbolConfiguration configurationWithPointSize: 26.0 weight: NSFontWeightRegular]];
	
	statusTitleTF  = [[self labelWithFont: [NSFont systemFontOfSize: 15.0 weight: NSFontWeightSemibold] color: [NSColor labelColor]] retain];
	statusDetailTF = [[self labelWithFont: [NSFont monospacedDigitSystemFontOfSize: [NSFont smallSystemFontSize] weight: NSFontWeightRegular] color: [NSColor secondaryLabelColor]] retain];
	NSStackView * statusText = [NSStackView stackViewWithViews: @[statusTitleTF]];
	[statusText setOrientation: NSUserInterfaceLayoutOrientationVertical];
	[statusText setAlignment: NSLayoutAttributeLeading];
	[statusText setSpacing: 3.0];
	
	[connectButton    removeFromSuperview];
	[disconnectButton removeFromSuperview];
	[connectButton    setTranslatesAutoresizingMaskIntoConstraints: NO];
	[disconnectButton setTranslatesAutoresizingMaskIntoConstraints: NO];
	[connectButton    setKeyEquivalent: @""];
	[connectButton    setBezelColor: [NSColor controlAccentColor]];
	
	NSStackView * statusRow = [[[NSStackView alloc] init] autorelease];
	[statusRow setOrientation: NSUserInterfaceLayoutOrientationHorizontal];
	[statusRow setAlignment: NSLayoutAttributeCenterY];
	[statusRow setSpacing: 12.0];
	[statusRow addView: statusIconView   inGravity: NSStackViewGravityLeading];
	[statusRow addView: statusText       inGravity: NSStackViewGravityLeading];
	[statusRow addView: connectButton    inGravity: NSStackViewGravityTrailing];
	[statusRow addView: disconnectButton inGravity: NSStackViewGravityTrailing];
	[NSLayoutConstraint activateConstraints: @[[[statusIconView widthAnchor]  constraintEqualToConstant: 34.0],
											   [[statusIconView heightAnchor] constraintEqualToConstant: 34.0],
											   [[statusText centerYAnchor]    constraintEqualToAnchor: [statusIconView centerYAnchor]]]];
	NSBox * statusCard = [self newCardBox];
	[statusCard setContentViewMargins: NSMakeSize(14.0, 10.0)];
	[self setContent: statusRow ofCard: statusCard];
	return statusCard;
}

-(NSView *) settingsRowWithLabel: (NSTextField *) label control: (NSView *) control {
	
	// A row with the label on the leading side and the control (a pop-up button) on the trailing side
	[label   removeFromSuperview];
	[control removeFromSuperview];
	[label   setTranslatesAutoresizingMaskIntoConstraints: NO];
	[control setTranslatesAutoresizingMaskIntoConstraints: NO];
	[label setAlignment: NSTextAlignmentNatural];
	[label setStringValue: [[label stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @": "]]];
	[label setContentHuggingPriority: NSLayoutPriorityDefaultLow forOrientation: NSLayoutConstraintOrientationHorizontal];
	[label setContentCompressionResistancePriority: NSLayoutPriorityDefaultLow forOrientation: NSLayoutConstraintOrientationHorizontal];
	
	NSStackView * row = [[[NSStackView alloc] init] autorelease];
	[row setOrientation: NSUserInterfaceLayoutOrientationHorizontal];
	[row setAlignment: NSLayoutAttributeFirstBaseline];
	[row setSpacing: 12.0];
	[row addView: label   inGravity: NSStackViewGravityLeading];
	[row addView: control inGravity: NSStackViewGravityTrailing];
	return row;
}

-(NSBox *) settingsCardWithRows: (NSArray *) rows {
	
	NSStackView * stack = [NSStackView stackViewWithViews: rows];
	[stack setOrientation: NSUserInterfaceLayoutOrientationVertical];
	[stack setAlignment: NSLayoutAttributeLeading];
	[stack setSpacing: 10.0];
	NSView * row;
	NSEnumerator * e = [rows objectEnumerator];
	NSMutableArray * constraints = [NSMutableArray array];
	while (  (row = [e nextObject])  ) {
		if (  [row isKindOfClass: [NSStackView class]]  ) {
			[constraints addObject: [[row widthAnchor] constraintEqualToAnchor: [stack widthAnchor]]];
		}
	}
	[NSLayoutConstraint activateConstraints: constraints];
	
	NSBox * card = [[self newCardBox] autorelease];
	[self setContent: stack ofCard: card];
	return card;
}

-(void) addPopUpRowWithLabel: (NSTextField *) label control: (NSView *) control to: (NSMutableArray *) rows {
	
	if (  label && control  ) {
		[rows addObject: [self settingsRowWithLabel: label control: control]];
	}
}

-(void) addCheckbox: (NSButton *) checkbox to: (NSMutableArray *) rows {
	
	if (  checkbox  ) {
		[checkbox removeFromSuperview];
		[checkbox setTranslatesAutoresizingMaskIntoConstraints: NO];
		[rows addObject: checkbox];
	}
}

-(void) modernizeSettingsTab {
	
	// The Settings tab becomes a form with three cards (connecting, network, disconnecting). The controls are the existing
	// ones (with their outlets and bindings).
	
	NSMutableArray * connectionRows = [NSMutableArray array];
	[self addPopUpRowWithLabel: whenToConnectTF            control: whenToConnectPopUpButton     to: connectionRows];
	[self addPopUpRowWithLabel: perConfigOpenvpnVersionTF  control: perConfigOpenvpnVersionButton to: connectionRows];
	[self addPopUpRowWithLabel: loggingLevelTF             control: loggingLevelPopUpButton      to: connectionRows];
	
	NSMutableArray * networkRows = [NSMutableArray array];
	[self addPopUpRowWithLabel: setNameserverTF control: setNameserverPopUpButton to: networkRows];
	[self addCheckbox: monitorNetworkForChangesCheckbox              to: networkRows];
	[self addCheckbox: routeAllTrafficThroughVpnCheckbox             to: networkRows];
	[self addCheckbox: disableIpv6OnTunCheckbox                      to: networkRows];
	[self addCheckbox: disableSecondaryNetworkServicesCheckbox       to: networkRows];
	[self addCheckbox: checkIPAddressAfterConnectOnAdvancedCheckbox  to: networkRows];
	
	NSMutableArray * disconnectRows = [NSMutableArray array];
	[self addPopUpRowWithLabel: uponUnexpectedDisconnectTF control: uponUnexpectedDisconnectPopUpButton to: disconnectRows];
	[self addPopUpRowWithLabel: uponDisconnectTF           control: uponDisconnectPopUpButton           to: disconnectRows];
	
	[advancedButton removeFromSuperview];
	[advancedButton setTranslatesAutoresizingMaskIntoConstraints: NO];
	
	NSView * settingsView = [settingsTabViewItem view];
	[[[[settingsView subviews] copy] autorelease] makeObjectsPerformSelector: @selector(removeFromSuperview)];
	
	NSMutableArray * sections = [NSMutableArray array];
	NSMutableArray * cards    = [NSMutableArray array];
	NSArray * groups = @[connectionRows, networkRows, disconnectRows];
	NSArray * rows;
	NSEnumerator * e = [groups objectEnumerator];
	while (  (rows = [e nextObject])  ) {
		if (  [rows count] != 0  ) {
			NSBox * card = [self settingsCardWithRows: rows];
			[sections addObject: card];
			[cards addObject: card];
		}
	}
	if (  advancedButton  ) {
		[sections addObject: advancedButton];
	}
	
	NSStackView * form = [NSStackView stackViewWithViews: sections];
	[form setOrientation: NSUserInterfaceLayoutOrientationVertical];
	[form setAlignment: NSLayoutAttributeLeading];
	[form setSpacing: 14.0];
	[form setTranslatesAutoresizingMaskIntoConstraints: NO];
	NSBox * card;
	e = [cards objectEnumerator];
	while (  (card = [e nextObject])  ) {
		[[[card widthAnchor] constraintEqualToAnchor: [form widthAnchor]] setActive: YES];
	}
	
	// In a scroll view, because the form can be taller than the window
	TBFlippedView * documentView = [[[TBFlippedView alloc] initWithFrame: [settingsView bounds]] autorelease];
	[documentView setTranslatesAutoresizingMaskIntoConstraints: NO];
	[documentView addSubview: form];
	NSScrollView * scrollView = [[[NSScrollView alloc] initWithFrame: [settingsView bounds]] autorelease];
	[scrollView setDrawsBackground: NO];
	[scrollView setHasVerticalScroller: YES];
	[scrollView setAutohidesScrollers: YES];
	[scrollView setBorderType: NSNoBorder];
	[scrollView setDocumentView: documentView];
	[scrollView setTranslatesAutoresizingMaskIntoConstraints: NO];
	[settingsView addSubview: scrollView];
	NSClipView * clipView = [scrollView contentView];
	[NSLayoutConstraint activateConstraints: @[[[scrollView topAnchor]        constraintEqualToAnchor: [settingsView topAnchor]],
											   [[scrollView bottomAnchor]     constraintEqualToAnchor: [settingsView bottomAnchor]],
											   [[scrollView leadingAnchor]    constraintEqualToAnchor: [settingsView leadingAnchor]],
											   [[scrollView trailingAnchor]   constraintEqualToAnchor: [settingsView trailingAnchor]],
											   [[documentView topAnchor]      constraintEqualToAnchor: [clipView topAnchor]],
											   [[documentView leadingAnchor]  constraintEqualToAnchor: [clipView leadingAnchor]],
											   [[documentView trailingAnchor] constraintEqualToAnchor: [clipView trailingAnchor]],
											   [[form topAnchor]              constraintEqualToAnchor: [documentView topAnchor]      constant: 4.0],
											   [[form leadingAnchor]          constraintEqualToAnchor: [documentView leadingAnchor]  constant: 4.0],
											   [[form trailingAnchor]         constraintEqualToAnchor: [documentView trailingAnchor] constant: -4.0],
											   [[form bottomAnchor]           constraintEqualToAnchor: [documentView bottomAnchor]   constant: -8.0]]];
}

-(void) modernizeLogTab {
	
	// The log is in a rounded card like the rest of the window, with some space around the text
	NSScrollView * scrollView = [logView enclosingScrollView];
	[scrollView setBorderType: NSNoBorder];
	[scrollView setWantsLayer: YES];
	[[scrollView layer] setCornerRadius: 12.0];
	[[scrollView layer] setMasksToBounds: YES];
	[[scrollView layer] setBorderWidth: 1.0];
	[self updateLogBorderColor];
	[logView setTextContainerInset: NSMakeSize(8.0, 8.0)];
	[logView setBackgroundColor: [NSColor controlBackgroundColor]];
	[scrollView setBackgroundColor: [NSColor controlBackgroundColor]];
	
	// The log view fills its tab
	NSView * logTab = [logTabViewItem view];
	NSRect frame = [logTab bounds];
	[scrollView setFrame: frame];
	[scrollView setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];
}

-(void) updateLogBorderColor {
	
	// Layer colors do not follow light and dark mode by themselves
	NSScrollView * scrollView = [logView enclosingScrollView];
	[[self effectiveAppearance] performAsCurrentDrawingAppearance: ^{
		[[scrollView layer] setBorderColor: [[NSColor separatorColor] CGColor]];
	}];
}

-(void) viewDidChangeEffectiveAppearance {
	
	[super viewDidChangeEffectiveAppearance];
	[self updateLogBorderColor];
}

-(void) installModernLayout {
	
	// Take the controls we keep out of the old layout, then remove the old layout
	NSArray * keep = @[configurationsTabView, connectButton, disconnectButton, configurationsHelpButton,
					   diagnosticInfoToClipboardButton, diagnosticInfoToClipboardProgressIndicator];
	[keep makeObjectsPerformSelector: @selector(retain)];
	[keep makeObjectsPerformSelector: @selector(removeFromSuperview)];
	[[[[self subviews] copy] autorelease] makeObjectsPerformSelector: @selector(removeFromSuperview)];
	
	// The tab view (Log, Settings) without tabs
	[configurationsTabView setTabViewType: NSNoTabsNoBorder];
	[self modernizeLogTab];
	[self modernizeSettingsTab];
	[configurationsTabView setTranslatesAutoresizingMaskIntoConstraints: NO];
	
	// The segmented control that chooses the tab
	NSMutableArray * labels = [NSMutableArray array];
	NSTabViewItem * item;
	NSEnumerator * e = [[configurationsTabView tabViewItems] objectEnumerator];
	while (  (item = [e nextObject])  ) {
		[labels addObject: [item label]];
	}
	viewSelector = [[NSSegmentedControl segmentedControlWithLabels: labels
													  trackingMode: NSSegmentSwitchTrackingSelectOne
															target: self
															action: @selector(viewSelectorWasClicked:)] retain];
	[viewSelector setTranslatesAutoresizingMaskIntoConstraints: NO];
	[self updateViewSelector];
	
	// Footer: help and diagnostic info
	[configurationsHelpButton                   setTranslatesAutoresizingMaskIntoConstraints: NO];
	[diagnosticInfoToClipboardButton            setTranslatesAutoresizingMaskIntoConstraints: NO];
	[diagnosticInfoToClipboardProgressIndicator setTranslatesAutoresizingMaskIntoConstraints: NO];
	NSStackView * footer = [NSStackView stackViewWithViews: @[configurationsHelpButton, diagnosticInfoToClipboardButton, diagnosticInfoToClipboardProgressIndicator]];
	[footer setOrientation: NSUserInterfaceLayoutOrientationHorizontal];
	[footer setSpacing: 10.0];
	[footer setTranslatesAutoresizingMaskIntoConstraints: NO];
	
	NSView * statusCard = [[self newStatusCard] autorelease];
	
	[self addSubview: statusCard];
	[self addSubview: viewSelector];
	[self addSubview: configurationsTabView];
	[self addSubview: footer];
	[NSLayoutConstraint activateConstraints: @[[[statusCard topAnchor]                 constraintEqualToAnchor: [self topAnchor] constant: 14.0],
											   [[statusCard leadingAnchor]             constraintEqualToAnchor: [self leadingAnchor]  constant: 20.0],
											   [[statusCard trailingAnchor]            constraintEqualToAnchor: [self trailingAnchor] constant: -20.0],
											   [[viewSelector topAnchor]               constraintEqualToAnchor: [statusCard bottomAnchor] constant: 14.0],
											   [[viewSelector centerXAnchor]           constraintEqualToAnchor: [self centerXAnchor]],
											   [[configurationsTabView topAnchor]      constraintEqualToAnchor: [viewSelector bottomAnchor] constant: 14.0],
											   [[configurationsTabView leadingAnchor]  constraintEqualToAnchor: [self leadingAnchor]  constant: 20.0],
											   [[configurationsTabView trailingAnchor] constraintEqualToAnchor: [self trailingAnchor] constant: -20.0],
											   [[footer topAnchor]                     constraintEqualToAnchor: [configurationsTabView bottomAnchor] constant: 12.0],
											   [[footer leadingAnchor]                 constraintEqualToAnchor: [self leadingAnchor]  constant: 20.0],
											   [[footer trailingAnchor]                constraintLessThanOrEqualToAnchor: [self trailingAnchor] constant: -20.0],
											   [[footer bottomAnchor]                  constraintEqualToAnchor: [self bottomAnchor] constant: -14.0]]];
	
	[keep makeObjectsPerformSelector: @selector(release)];
}

-(void) viewSelectorWasClicked: (id) sender {
	
	(void) sender;
	
	[configurationsTabView selectTabViewItemAtIndex: [viewSelector selectedSegment]];
	[self updateViewSelector]; // In case the tab view's delegate did not allow the change
}

-(void) updateViewSelector {
	
	NSTabViewItem * selected = [configurationsTabView selectedTabViewItem];
	if (  selected  ) {
		[viewSelector setSelectedSegment: [configurationsTabView indexOfTabViewItem: selected]];
	}
}

-(void) updateStatusForConnection: (VPNConnection *) connection {
	
	if (  ! statusTitleTF  ) {
		return;
	}
	
	NSString * state = [connection state];
	NSString * symbol;
	NSColor  * tint;
	BOOL connected = [connection isConnected];
	if (  connected  ) {
		symbol = @"checkmark.shield.fill";
		tint   = [NSColor systemGreenColor];
	} else if (   connection
			   && ( ! [connection isDisconnected] )  ) {
		symbol = @"arrow.triangle.2.circlepath";
		tint   = [NSColor systemOrangeColor];
	} else {
		symbol = @"shield.slash";
		tint   = [NSColor secondaryLabelColor];
	}
	[statusIconView setImage: [NSImage imageWithSystemSymbolName: symbol accessibilityDescription: nil]];
	[statusIconView setContentTintColor: tint];
	
	[statusTitleTF setStringValue: (  state
									? localizeNonLiteral(state, @"Connection status")
									: @"")];
	
	// While connected, the traffic ("In: 412 KB/s (1.2 GB)   Out: ...") is shown below the state
	NSString * detail = @"";
	NSDictionary * statistics = (  connected
								 ? [connection statisticsForDisplay]
								 : nil);
	if (  statistics  ) {
		detail = [NSString stringWithFormat: @"%@ %@ %@ (%@ %@)     %@ %@ %@ (%@ %@)",
				  NSLocalizedString(@"In:", @"Window text"),
				  [statistics objectForKey: @"inRate"],   [statistics objectForKey: @"inRateUnits"],
				  [statistics objectForKey: @"inTotal"],  [statistics objectForKey: @"inTotalUnits"],
				  NSLocalizedString(@"Out:", @"Window text"),
				  [statistics objectForKey: @"outRate"],  [statistics objectForKey: @"outRateUnits"],
				  [statistics objectForKey: @"outTotal"], [statistics objectForKey: @"outTotalUnits"]];
	}
	[statusDetailTF setStringValue: detail];
	
	// The detail line is only in the stack view when it has text, so the title is centered when it doesn't
	NSStackView * statusText = (NSStackView *)[statusTitleTF superview];
	BOOL showDetail = ([detail length] != 0);
	if (   showDetail
		&& ( ! [[statusText arrangedSubviews] containsObject: statusDetailTF] )  ) {
		[statusText addArrangedSubview: statusDetailTF];
	} else if (   ( ! showDetail )
			   && [[statusText arrangedSubviews] containsObject: statusDetailTF]  ) {
		[statusText removeArrangedSubview: statusDetailTF];
		[statusDetailTF removeFromSuperview];
	}
	[statusText setNeedsLayout: YES];  // The stack view does not always lay out its remaining view again by itself
	[statusText layoutSubtreeIfNeeded];
}


@end
