/*
 * Copyright 2011, 2012, 2013, 2014, 2015, 2016, 2018 Jonathan K. Bullard. All rights reserved.
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


#import "DBPrefsWindowController.h"

#import "defines.h"

@class ConfigurationsView;
@class GeneralView;
@class AppearanceView;
@class InfoView;
@class UtilitiesView;
@class VPNConnection;
@class SettingsSheetWindowController;

@interface MyPrefsWindowController : DBPrefsWindowController <NSTextViewDelegate, NSWindowDelegate, NSTabViewDelegate, NSTableViewDelegate>
{   
    NSString                      * currentViewName;
    NSRect                          currentFrame;
    
    IBOutlet ConfigurationsView   * configurationsPrefsView;
    IBOutlet GeneralView          * generalPrefsView;
    IBOutlet AppearanceView       * appearancePrefsView;
    IBOutlet InfoView             * infoPrefsView;
    IBOutlet UtilitiesView        * utilitiesPrefsView;
    
    NSTimer                       * lockTheLockIconTimer;
    NSDate                        * lockTimeoutDate;
    BOOL                            lockIconIsUnlocked;
    
    NSString                      * previouslySelectedNameOnLeftNavList;
    
    NSMutableArray                * leftNavList;                      // Items in the left navigation list as displayed to the user
    //                                                             Each item is a string with either
    //                                                             a folder name (possibly indented) or
    //                                                             a connection name (possibly indented)
    
    NSMutableArray                * leftNavDisplayNames;              // A string for each item in leftNavList
    //                                                             Each item is a string with either
    //                                                             An empty string (corresponding to a folder name entry in leftNavList) or
    //                                                             The full display name for the corresponding connection
    
    SettingsSheetWindowController * settingsSheetWindowController;
    
    AuthorizationRef               authorization;                    // Authorization reference for Shared/Deployed configuration manipulation
    
    NSUInteger                     selectedWhenToConnectIndex;
    
    NSUInteger                     selectedLeftNavListIndex;
    IBOutlet NSNumber            * selectedSetNameserverIndex;
    IBOutlet NSNumber            * selectedPerConfigOpenvpnVersionIndex;
    IBOutlet NSNumber            * selectedLoggingLevelIndex;
    
    
    // For GeneralView
    IBOutlet NSNumber            * selectedKeyboardShortcutIndex;
    IBOutlet NSNumber            * selectedMaximumLogSizeIndex;
    
    // For AppearanceView
    IBOutlet NSNumber            * selectedAppearanceIconSetIndex;
    IBOutlet NSNumber            * selectedAppearanceConnectionWindowDisplayCriteriaIndex;
    IBOutlet NSNumber            * selectedAppearanceConnectionWindowScreenIndex;
	
	// For UtilitiesView
	BOOL						   cancelUtilitiesQuitAllOpenVpn;
}


// Methods used by MenuController or others to update the window

-(void) update;
-(BOOL) forceDisableOfNetworkMonitoring;

-(void) selectedLeftNavListIndexChanged;

-(void) indicateWaitingForLogDisplay:                         (VPNConnection *) theConnection;
-(void) indicateNotWaitingForConsoleLogToClipboard;
-(void) indicateNotWaitingForUtilitiesExportTunnelblickSetup;
-(void) indicateNotWaitingForDiagnosticInfoToClipboard;
-(void) indicateNotWaitingForLogDisplay:                      (VPNConnection *) theConnection;
-(void) hookedUpOrStartedConnection:                          (VPNConnection *) theConnection;
-(void) lockTheLockIcon;
-(void) validateWhenConnectingForConnection:                  (VPNConnection *) theConnection;
-(void) validateConnectAndDisconnectButtonsForConnection:     (VPNConnection *) theConnection;
-(void) validateDetailsWindowControls;
-(void) monitorNetworkForChangesCheckboxChangedForConnection: (VPNConnection *) theConnection;
-(void) setupAppearanceConnectionWindowScreenButton;
-(void) setupAppearancePlaceIconNearSpotlightCheckbox;
-(void) setupLeftNavigationToDisplayName:                     (NSString *) displayName;

// Used by LogDisplay to scroll to the current point in the log
-(NSTextView *) logView;

// Methods for ConfigurationsView

- (VPNConnection*) selectedConnection;

-(IBAction) addConfigurationButtonWasClicked:         (id)  sender;
-(IBAction) removeConfigurationButtonWasClicked:      (id)  sender;

-(IBAction) renameConfigurationMenuItemWasClicked:    (id) sender;
-(IBAction) duplicateConfigurationMenuItemWasClicked: (id) sender;
-(IBAction) makePrivateMenuItemWasClicked:            (id) sender;
-(IBAction) makeSharedMenuItemWasClicked:             (id) sender;
-(IBAction) revertToShadowMenuItemWasClicked:         (id) sender;
-(IBAction) showOnTbMenuMenuItemWasClicked:           (id) sender;
-(IBAction) doNotShowOnTbMenuMenuItemWasClicked:      (id) sender;
-(IBAction) editOpenVPNConfigurationFileMenuItemWasClicked: (id) sender;
-(IBAction) showOpenvpnLogMenuItemWasClicked:         (id)  sender;
-(IBAction) removeCredentialsMenuItemWasClicked:      (id) sender;

-(IBAction) disconnectButtonWasClicked:               (id)  sender;
-(IBAction) connectButtonWasClicked:                  (id)  sender;

-(IBAction) diagnosticInfoToClipboardButtonWasClicked:(id)  sender;

-(IBAction) configurationsHelpButtonWasClicked:       (id)  sender;

-(IBAction) monitorNetworkForChangesCheckboxWasClicked:             (NSButton *) sender;
-(IBAction) routeAllTrafficThroughVpnCheckboxWasClicked:            (NSButton *) sender;
-(IBAction) checkIPAddressAfterConnectOnAdvancedCheckboxWasClicked: (NSButton *) sender;
-(IBAction) disableIpv6OnTunCheckboxWasClicked:                     (NSButton *) sender;

-(IBAction) whenToConnectManuallyMenuItemWasClicked:          (id) sender;
-(IBAction) whenToConnectTunnelBlickLaunchMenuItemWasClicked: (id) sender;
-(IBAction) whenToConnectOnComputerStartMenuItemWasClicked:   (id) sender;

-(IBAction) advancedButtonWasClicked:                         (id) sender;


// Methods for GeneralView

-(IBAction) inhibitOutboundTBTrafficCheckboxWasClicked: (NSButton *) sender;
-(IBAction) generalAdminApprovalForKeyAndCertificateChangesCheckboxWasClicked: (NSButton *) sender;
-(IBAction) updatesCheckAutomaticallyCheckboxWasClicked:         (NSButton *) sender;
-(IBAction) updatesCheckForBetaUpdatesCheckboxWasClicked:        (NSButton *) sender;
-(IBAction) updatesCheckNowButtonWasClicked:                     (id) sender;

-(IBAction) resetDisabledWarningsButtonWasClicked:        (id) sender;

-(IBAction) generalHelpButtonWasClicked:                  (id) sender;


// Methods for AppearanceView

-(IBAction) appearancePlaceIconNearSpotlightCheckboxWasClicked:    (NSButton *) sender;

-(IBAction) appearanceDisplayConnectionSubmenusCheckboxWasClicked: (NSButton *) sender;
-(IBAction) appearanceDisplayConnectionTimersCheckboxWasClicked:   (NSButton *) sender;

-(IBAction) appearanceDisplaySplashScreenCheckboxWasClicked:       (NSButton *) sender;

-(IBAction) appearanceDisplayStatisticsWindowsCheckboxWasClicked:  (NSButton *) sender;

-(IBAction) appearanceDisplayStatisticsWindowWhenDisconnectedCheckboxWasClicked: (NSButton *) sender;

-(IBAction) appearanceHelpButtonWasClicked:                        (id) sender;


// Method for InfoView
-(IBAction) infoHelpButtonWasClicked: (id) sender;


// Methods for UtiltiesView

-(IBAction) utilitiesQuitAllOpenVpnButtonWasClicked:      (id) sender;

-(IBAction) utilitiesRunEasyRsaButtonWasClicked:          (id) sender;

-(IBAction) consoleLogToClipboardButtonWasClicked:        (id) sender;

-(IBAction) utilitiesExportTunnelblickSetupButtonWasClicked: (id) sender;

-(IBAction) utilitiesHelpButtonWasClicked:                (id) sender;

-(IBAction) utilitiesOpenUninstallInstructionsButtonWasClicked: (id) sender;

// Getters & Setters

TBPROPERTY_READONLY(NSMutableArray *, leftNavDisplayNames)

TBPROPERTY_READONLY(ConfigurationsView *, configurationsPrefsView)

TBPROPERTY(NSString *, previouslySelectedNameOnLeftNavList, setPreviouslySelectedNameOnLeftNavList)

TBPROPERTY_READONLY(NSUInteger, selectedWhenToConnectIndex)

TBPROPERTY_READONLY(SettingsSheetWindowController *, settingsSheetWindowController)

TBPROPERTY(NSUInteger, selectedLeftNavListIndex,             setSelectedLeftNavListIndex)

TBPROPERTY(NSNumber *, selectedSetNameserverIndex,           setSelectedSetNameserverIndex)
TBPROPERTY(NSNumber *, selectedPerConfigOpenvpnVersionIndex, setSelectedPerConfigOpenvpnVersionIndex)
TBPROPERTY(NSNumber *, selectedLoggingLevelIndex,            setSelectedLoggingLevelIndex)

TBPROPERTY(NSNumber *, selectedKeyboardShortcutIndex, setSelectedKeyboardShortcutIndex)
TBPROPERTY(NSNumber *, selectedMaximumLogSizeIndex,   setSelectedMaximumLogSizeIndex)

TBPROPERTY(NSNumber *, selectedAppearanceIconSetIndex,                         setSelectedAppearanceIconSetIndex)
TBPROPERTY(NSNumber *, selectedAppearanceConnectionWindowDisplayCriteriaIndex, setSelectedAppearanceConnectionWindowDisplayCriteriaIndex)
TBPROPERTY(NSNumber *, selectedAppearanceConnectionWindowScreenIndex,          setSelectedAppearanceConnectionWindowScreenIndex)

@end
