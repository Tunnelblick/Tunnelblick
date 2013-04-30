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


#import "defines.h"
#import "DBPrefsWindowController.h"

@class ConfigurationsView;
@class GeneralView;
@class AppearanceView;
@class InfoView;
@class UtilitiesView;
@class VPNConnection;
@class SettingsSheetWindowController;

@interface MyPrefsWindowController : DBPrefsWindowController <NSTextStorageDelegate, NSWindowDelegate, NSTabViewDelegate, NSTableViewDelegate>
{   
    NSString                      * currentViewName;
    NSRect                          currentFrame;
    
    IBOutlet ConfigurationsView   * configurationsPrefsView;
    IBOutlet GeneralView          * generalPrefsView;
    IBOutlet AppearanceView       * appearancePrefsView;
    IBOutlet InfoView             * infoPrefsView;
    IBOutlet UtilitiesView        * utilitiesPrefsView;
    
	NSSize                          windowContentMinSize;	// Saved when switch FROM Configurations view
	NSSize                          windowContentMaxSize;   // And restored when switch back
	//												        // (In other views, set min = max so can't change size)
	
    // For ConfigurationsView
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
    
    BOOL                           doNotPlaySounds;                  // Used to inhibit playing sounds while switching configurations
    
    NSUInteger                     selectedWhenToConnectIndex;
    
    NSUInteger                     selectedLeftNavListIndex;
    IBOutlet NSUInteger            selectedSetNameserverIndex;
    IBOutlet NSUInteger            selectedSoundOnConnectIndex;
    IBOutlet NSUInteger            selectedSoundOnDisconnectIndex;    
    
    
    // For GeneralView
    IBOutlet NSUInteger            selectedOpenvpnVersionIndex;
    IBOutlet NSUInteger            selectedKeyboardShortcutIndex;
    IBOutlet NSUInteger            selectedMaximumLogSizeIndex;
    
    // For AppearanceView
    IBOutlet NSUInteger            selectedAppearanceIconSetIndex;
    IBOutlet NSUInteger            selectedAppearanceConnectionWindowDisplayCriteriaIndex;
}


// Methods used by MenuController to update the window

-(void) update;
-(void) updateNavigationLabels;
-(BOOL) forceDisableOfNetworkMonitoring;

-(void) indicateWaitingForConnection:                         (VPNConnection *) theConnection;
-(void) indicateNotWaitingForConnection:                      (VPNConnection *) theConnection;
-(void) hookedUpOrStartedConnection:                          (VPNConnection *) theConnection;
-(void) validateWhenConnectingForConnection:                  (VPNConnection *) theConnection;
-(void) validateConnectAndDisconnectButtonsForConnection:     (VPNConnection *) theConnection;
-(void) monitorNetworkForChangesCheckboxChangedForConnection: (VPNConnection *) theConnection;
-(void) doLogScrollingForConnection:                          (VPNConnection *) theConnection;

// Used by LogDisplay to scroll to the current point in the log
-(NSTextView *) logView;

// Methods for ConfigurationsView

- (VPNConnection*) selectedConnection;

-(void) setSelectedLeftNavListIndexFromDisplayName: (NSString *) displayName;

-(IBAction) addConfigurationButtonWasClicked:         (id)  sender;
-(IBAction) removeConfigurationButtonWasClicked:      (id)  sender;

-(IBAction) renameConfigurationMenuItemWasClicked:    (id) sender;
-(IBAction) duplicateConfigurationMenuItemWasClicked: (id) sender;
-(IBAction) makePrivateOrSharedMenuItemWasClicked:    (id) sender;
-(IBAction) revertToShadowMenuItemWasClicked:         (id) sender;
-(IBAction) editOpenVPNConfigurationFileMenuItemWasClicked: (id) sender;
-(IBAction) showOpenvpnLogMenuItemWasClicked:         (id)  sender;
-(IBAction) removeCredentialsMenuItemWasClicked:      (id) sender;

-(IBAction) disconnectButtonWasClicked:               (id)  sender;
-(IBAction) connectButtonWasClicked:                  (id)  sender;

-(IBAction) logToClipboardButtonWasClicked:           (id)  sender;

-(IBAction) configurationsHelpButtonWasClicked:       (id)  sender;

-(IBAction) monitorNetworkForChangesCheckboxWasClicked: (id) sender;

-(IBAction) showOnTunnelBlickMenuCheckboxWasClicked:    (id) sender;

-(void)		validateDetailsWindowControls;

-(IBAction) whenToConnectManuallyMenuItemWasClicked:          (id) sender;
-(IBAction) whenToConnectTunnelBlickLaunchMenuItemWasClicked: (id) sender;
-(IBAction) whenToConnectOnComputerStartMenuItemWasClicked:   (id) sender;

-(IBAction) advancedButtonWasClicked:                         (id) sender;


// Methods for GeneralView

-(IBAction) monitorConfigurationFolderCheckboxWasClicked: (id) sender;

-(IBAction) checkIPAddressAfterConnectCheckboxWasClicked: (id) sender;

-(IBAction) updatesCheckAutomaticallyCheckboxWasClicked:  (id) sender;
-(IBAction) updatesCheckNowButtonWasClicked:              (id) sender;

-(IBAction) resetDisabledWarningsButtonWasClicked:        (id) sender;

-(IBAction) generalHelpButtonWasClicked:                  (id) sender;


// Methods for AppearanceView

-(IBAction) appearancePlaceIconNearSpotlightCheckboxWasClicked:    (id) sender;

-(IBAction) appearanceDisplayConnectionSubmenusCheckboxWasClicked: (id) sender;
-(IBAction) appearanceDisplayConnectionTimersCheckboxWasClicked:   (id) sender;

-(IBAction) appearanceDisplaySplashScreenCheckboxWasClicked:       (id) sender;

-(IBAction) appearanceDisplayStatisticsWindowCheckboxWasClicked:   (id) sender;

-(IBAction) appearanceDisplayStatisticsWindowWhenDisconnectedCheckboxWasClicked: (id) sender;

-(IBAction) appearanceHelpButtonWasClicked:                        (id) sender;


// Method for InfoView
-(IBAction) infoHelpButtonWasClicked: (id) sender;


// Methods for UtiltiesView

-(IBAction) utilitiesKillAllOpenVpnButtonWasClicked:      (id) sender;

-(IBAction) utilitiesRunEasyRsaButtonWasClicked:          (id) sender;

-(IBAction) utilitiesCopyConsoleLogButtonWasClicked:      (id) sender;

-(IBAction) utilitiesHelpButtonWasClicked:                (id) sender;


// Getters & Setters

TBPROPERTY_READONLY(ConfigurationsView *, configurationsPrefsView)

TBPROPERTY_READONLY(NSUInteger, selectedWhenToConnectIndex)

TBPROPERTY(NSUInteger, selectedLeftNavListIndex,       setSelectedLeftNavListIndex)
TBPROPERTY(NSUInteger, selectedSetNameserverIndex,     setSelectedSetNameserverIndex)
TBPROPERTY(NSUInteger, selectedSoundOnConnectIndex,    setSelectedSoundOnConnectIndex)
TBPROPERTY(NSUInteger, selectedSoundOnDisconnectIndex, setSelectedSoundOnDisconnectIndex)

TBPROPERTY(NSUInteger, selectedOpenvpnVersionIndex,   setSelectedOpenvpnVersionIndex)
TBPROPERTY(NSUInteger, selectedKeyboardShortcutIndex, setSelectedKeyboardShortcutIndex)
TBPROPERTY(NSUInteger, selectedMaximumLogSizeIndex,   setSelectedMaximumLogSizeIndex)

TBPROPERTY(NSUInteger, selectedAppearanceIconSetIndex,                         setSelectedAppearanceIconSetIndex)
TBPROPERTY(NSUInteger, selectedAppearanceConnectionWindowDisplayCriteriaIndex, setSelectedAppearanceConnectionWindowDisplayCriteriaIndex)

@end
