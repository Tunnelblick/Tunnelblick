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
#import "TBInfoButton.h"
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

-(void) shiftLabelsAndButtonsWtc: (CGFloat) wtcWidthChange
                            sdns: (CGFloat) sdnsWidthChange
                            pcov: (CGFloat) pcovWidthChange
         loggingLevelWidthChange: (CGFloat) loggingLevelWidthChange {
	
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
}

-(void) normalizeWidthOfConfigurationsButtons {
	
	NSArray * list = [NSArray arrayWithObjects: whenToConnectPopUpButton, setNameserverPopUpButton, perConfigOpenvpnVersionButton, loggingLevelPopUpButton, nil];
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
                label = NSLocalizedString(@"OpenVPN level 4 - also outputs values for all options", @"Menu Item");
                break;
                
            case 5:
                label = NSLocalizedString(@"OpenVPN level 5 - also outputs \"R\" or \"W\" for each packet", @"Menu Item");
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

-(NSString *) displayNameForOpenvpnName: (NSString *) openvpnName {
    
    // OpenVPN binaries are held in folders in the 'openvpn' folder in Resources.
	// The name of the folder includes the version of OpenVPN and the name and version of the SSL/TLS library it is linked to.
    // The folder name must have a prefix of 'openvpn-' followed by the version number, followed by a '-' and a library name, followed by a '-' and a library version number.
    // The folder name must not contain any spaces, but underscores will be shown as spaces to the user, and "known" library names will be upper-cased appropriately.
    // The version numbers and library name cannot contain '-' characters.
    // Example: a folder named 'openvpn-1.2.3_git_master_123abcd-libressl-4.5.6' will be shown to the user as "123 git master 123abcd - LibreSSL v4.5.6"
    //
    // NOTE: This method's input openvpnName is the part of the folder name _after_ 'openvpn-'
    
    NSArray * parts = [openvpnName componentsSeparatedByString: @"-"];
    
    NSString * name;

    if (   [parts count] == 3  ) {
        NSMutableString * mName = [[[NSString stringWithFormat: NSLocalizedString(@"%@ - %@ v%@", @"An entry in the drop-down list of OpenVPN versions that are available on the 'Settings' tab. "
																				  "The first %@ is an OpenVPN version number, e.g. '2.3.10'. The second %@ is an SSL library name, e.g. 'LibreSSL'. The third %@ is the SSL library version, e.g. 1.0.1a"),
                                    [parts objectAtIndex: 0], [parts objectAtIndex: 1], [parts objectAtIndex: 2]]
                                   mutableCopy] autorelease];
		[mName replaceOccurrencesOfString: @"openssl"   withString: @"OpenSSL"   options: 0 range: NSMakeRange(0, [mName length])];
		[mName replaceOccurrencesOfString: @"libressl"  withString: @"LibreSSL"  options: 0 range: NSMakeRange(0, [mName length])];
		[mName replaceOccurrencesOfString: @"mbedtls"   withString: @"mbed TLS"  options: 0 range: NSMakeRange(0, [mName length])];
		[mName replaceOccurrencesOfString: @"boringssl" withString: @"BoringSSL" options: 0 range: NSMakeRange(0, [mName length])];
		[mName replaceOccurrencesOfString: @"_"         withString: @" "         options: 0 range: NSMakeRange(0, [mName length])];
        name = [NSString stringWithString: mName];
    } else {
        NSLog(@"Invalid name (must have 3 '-') for an OpenVPN folder: 'openvpn-%@'.", openvpnName);
        name = nil;
    }

    return name;
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
    
	if (  rtl  ) {
		[leftNavTableTFC setAlignment: NSRightTextAlignment]; // Set the text in the list of configurations to be right aligned
	}
	
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
	
	CGFloat loggingLevelWidthChange = 0.0;
	if (  loggingLevelPopUpButton  ) {
		loggingLevelWidthChange = [UIHelper setTitle: NSLocalizedString(@"VPN log level:", @"Window text") ofControl: loggingLevelTFC frameHolder: loggingLevelTF shift: ( !rtl ) narrow: YES enable: YES];
		[self setupLoggingLevelPopUpButton];
		[UIHelper setTitle: nil ofControl: loggingLevelPopUpButton shift: rtl narrow: YES enable: YES];
	}
	
    // OpenVPN Version popup. Default depends on version of OS X
    
    CGFloat pcovWidthChange = [UIHelper setTitle: NSLocalizedString(@"OpenVPN version:", @"Window text") ofControl: perConfigOpenvpnVersionTFC frameHolder: perConfigOpenvpnVersionTF shift: ( !rtl ) narrow: YES enable: YES];
    
    NSArray  * versionNames  = [((MenuController *)[NSApp delegate]) openvpnVersionNames];
    
    NSMutableArray * ovContent = [NSMutableArray arrayWithCapacity: [versionNames count] + 2];
    
    NSString * ver = [versionNames objectAtIndex: 0];
    [ovContent addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                          [NSString stringWithFormat: NSLocalizedString(@"Default (%@)", @"Button"), [self displayNameForOpenvpnName: ver]], @"name",
                          @"", @"value",    // Empty name means default
                          nil]];
    
    NSUInteger ix;
    for (  ix=0; ix<[versionNames count]; ix++  ) {
        ver = [versionNames objectAtIndex: ix];
        NSString * name = [self displayNameForOpenvpnName: ver];
        if (  name  ) {
            [ovContent addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                   name, @"name",
                                   ver,  @"value",
                                   nil]];
        }
    }
    [ovContent addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                          [NSString stringWithFormat: NSLocalizedString(@"Latest (%@)", @"Button"), [self displayNameForOpenvpnName: [versionNames lastObject]]], @"name",
                          @"-", @"value",    // "-" means latest
                          nil]];
    
    [perConfigOpenvpnVersionArrayController setContent: ovContent];
	[UIHelper setTitle: nil ofControl: perConfigOpenvpnVersionButton shift: rtl narrow: YES enable: YES];
	
	[self shiftLabelsAndButtonsWtc: wtcWidthChange sdns: sdnsWidthChange pcov: pcovWidthChange loggingLevelWidthChange: loggingLevelWidthChange];
	
	[self normalizeWidthOfConfigurationsButtons];
	
	CGFloat change = [UIHelper setTitle: NSLocalizedString(@"Monitor network settings", @"Checkbox name")
							  ofControl: monitorNetworkForChangesCheckbox
								  shift: rtl
								 narrow: YES
								 enable: YES];
	[UIHelper shiftControl: infoButtonForMonitorNetworkForChangesCheckbox by: change reverse: ! rtl];
	NSAttributedString * infoTitle = attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, Tunnelblick will watch for and react to changes in network"
																				@" settings (for example, changes caused by DHCP renewals or switching Internet connections) to attempt to keep the VPN connected. Tunnelblick's default actions when network"
																				@" settings change usually work well, but you may specify different actions on the 'While Connected' tab of the 'Advanced' settings window.</p>\n"
																				@"<p><strong>When not checked</strong>, Tunnelblick will ignore network changes.</p>\n"
																				@"<p><strong>This checkbox is disabled</strong> when 'Set DNS/WINS' is not set to 'Set nameserver' or 'Set nameserver (3.1)'.</p>",
																				@"HTML info for the 'Monitor network settings' checkbox."));
	[infoButtonForMonitorNetworkForChangesCheckbox setAttributedTitle: infoTitle];
	[infoButtonForMonitorNetworkForChangesCheckbox setMinimumWidth:    360.0];
	
	change = [UIHelper setTitle: NSLocalizedString(@"Route all IPv4 traffic through the VPN", @"Checkbox name")
					  ofControl: routeAllTrafficThroughVpnCheckbox
						  shift: rtl
						 narrow: YES
						 enable: YES];
	[UIHelper shiftControl: infoButtonForRouteAllTrafficThroughVpnCheckbox by: change reverse: ! rtl];
	infoTitle = attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, Tunnelblick will instruct OpenVPN to route all IPv4 traffic through the VPN server.</p>\n"
														   @"<p><strong>When not checked</strong>, by default OpenVPN will use the VPN only for traffic that"
														   @" is destined for the VPN's network. All other traffic will use the normal Internet connection without going through the VPN."
														   @" OpenVPN's default behavior may be changed by the OpenVPN configuration or the VPN server and cause all IPv4"
														   @" traffic to be routed through the VPN server as if this checkbox had been checked. </p>\n",
														   @"HTML info for the 'Route all IPv4 traffic through the VPN' checkbox."));
	[infoButtonForRouteAllTrafficThroughVpnCheckbox setAttributedTitle: infoTitle];
	[infoButtonForRouteAllTrafficThroughVpnCheckbox setMinimumWidth: 360.0];
	
	change = [UIHelper setTitle: NSLocalizedString(@"Disable IPv6 (tun only)", @"Checkbox name")
					  ofControl: disableIpv6OnTunCheckbox
						  shift: rtl
						 narrow: YES
						 enable: YES];
	[UIHelper shiftControl: infoButtonForDisableIpv6OnTunCheckbox by: change reverse: ! rtl];
	infoTitle = attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, IPv6 will be disabled.</p>\n"
														   @"<p>Disabling IPv6 is often recommended because many VPN configurations do not guard against information leaks caused by the use"
														   @" of IPv6. Most Internet access works fine without IPv6.</p>\n"
														   @"<p><strong>When not checked</strong>, IPv6 will not be disabled.</p>\n"
														   @"<p><strong>This checkbox is disabled</strong> when using a 'tap' connection because it"
														   @" cannot be enforced on a 'tap' connection .</p>",
														   @"HTML info for the 'Disable IPv6 (tun only)' checkbox."));
	[infoButtonForDisableIpv6OnTunCheckbox setAttributedTitle: infoTitle];
	[infoButtonForDisableIpv6OnTunCheckbox setMinimumWidth: 360.0];
	
	change = [UIHelper setTitle: NSLocalizedString(@"Check if the apparent public IP address changed after connecting", @"Checkbox name")
					  ofControl: checkIPAddressAfterConnectOnAdvancedCheckbox
						  shift: rtl
						 narrow: YES
						 enable: YES];
	[UIHelper shiftControl: infoButtonForCheckIPAddressAfterConnectOnAdvancedCheckbox by: change reverse: ! rtl];
	infoTitle = attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, Tunnelblick will determine the computer's apparent public IP"
														   @" address before and after the VPN is connected and warn if the IP address does not change.</p>\n"
														   @"<p>The tunnelblick.net website will be accessed to perform this function. The access is usually done via https:"
														   @" using the tunnelblick.net name, except that if that access fails, access is attempted using http:"
														   @" and the IP address of the website.</p>\n"
														   @"<p><strong>When not checked</strong>, Tunnelblick does not check for IP address changes and"
														   @" does not warn if the IP address does not change after the VPN is connected.</p>\n",
														   @"HTML info for the 'Check if the apparent public IP address changed after connecting' checkbox."));
	[infoButtonForCheckIPAddressAfterConnectOnAdvancedCheckbox setAttributedTitle: infoTitle];
	[infoButtonForCheckIPAddressAfterConnectOnAdvancedCheckbox setMinimumWidth: 360.0];
	
	change = [UIHelper setTitle: NSLocalizedString(@"Reset the primary interface after disconnecting", @"Checkbox name")
					  ofControl: resetPrimaryInterfaceAfterDisconnectCheckbox
						  shift: rtl
						 narrow: YES
						 enable: YES];
	[UIHelper shiftControl: infoButtonForResetPrimaryInterfaceAfterDisconnectCheckbox by: change reverse: ! rtl];
	infoTitle = attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, Tunnelblick will reset the primary network interface after the"
														   @" VPN is disconnected. This can work around problems caused by some misconfigured VPN servers"
														   @" and by some OpenVPN configuration errors.</p>\n"
														   @"<p><strong>When not checked</strong>, Tunnelblick will not reset the primary network interface.</p>\n"
														   @"<p><strong>This checkbox is disabled</strong> when 'Set DNS/WINS' is not set to 'Set nameserver'.</p>",
														   @"HTML info for the 'Reset the primary interface after disconnecting' checkbox."));
	[infoButtonForResetPrimaryInterfaceAfterDisconnectCheckbox setAttributedTitle: infoTitle];
	[infoButtonForResetPrimaryInterfaceAfterDisconnectCheckbox setMinimumWidth: 360.0];
	
	[UIHelper setTitle: NSLocalizedString(@"Advanced..." , @"Button") ofControl: advancedButton shift: rtl narrow: YES enable: ( ! [gTbDefaults boolForKey: @"disableAdvancedButton"])];
	
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
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            disableIpv6OnTunCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            checkIPAddressAfterConnectOnAdvancedCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            resetPrimaryInterfaceAfterDisconnectCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, TBInfoButton *,        infoButtonForMonitorNetworkForChangesCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, TBInfoButton *,        infoButtonForRouteAllTrafficThroughVpnCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, TBInfoButton *,        infoButtonForDisableIpv6OnTunCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, TBInfoButton *,        infoButtonForCheckIPAddressAfterConnectOnAdvancedCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, TBInfoButton *,        infoButtonForResetPrimaryInterfaceAfterDisconnectCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *,   perConfigOpenvpnVersionArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            perConfigOpenvpnVersionButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextField *,         loggingLevelTF)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,     loggingLevelTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSPopUpButton *,       loggingLevelPopUpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *,   loggingLevelArrayController)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          advancedButton)

@end
