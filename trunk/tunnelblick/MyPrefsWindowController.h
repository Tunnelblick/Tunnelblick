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


#import <Cocoa/Cocoa.h>
#import "defines.h"
#import "DBPrefsWindowController.h"

@class ConfigurationsView;
@class GeneralView;
@class AppearanceView;
@class InfoView;
@class VPNConnection;
@class SettingsSheetWindowController;

@interface MyPrefsWindowController : DBPrefsWindowController <NSTextStorageDelegate, NSWindowDelegate, NSTabViewDelegate>
{   
    NSString                      * currentViewName;
    NSRect                          currentFrame;
    
    IBOutlet ConfigurationsView   * configurationsPrefsView;
    IBOutlet GeneralView          * generalPrefsView;
    IBOutlet AppearanceView       * appearancePrefsView;
    IBOutlet InfoView             * infoPrefsView;
    
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
    
    NSInteger                      selectedWhenToConnectIndex;
    
    NSInteger                      selectedLeftNavListIndex;
    IBOutlet NSInteger             selectedSetNameserverIndex;
    IBOutlet NSInteger             selectedSoundOnConnectIndex;
    IBOutlet NSInteger             selectedSoundOnDisconnectIndex;    
    
    
    // For GeneralView
    IBOutlet NSInteger             selectedKeyboardShortcutIndex;
    IBOutlet NSInteger             selectedMaximumLogSizeIndex;
    
    // For AppearanceView
    IBOutlet NSInteger             selectedAppearanceIconSetIndex;
    IBOutlet NSInteger             selectedAppearanceConnectionWindowDisplayCriteriaIndex;
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

-(IBAction) addConfigurationButtonWasClicked:         (id)  sender;
-(IBAction) removeConfigurationButtonWasClicked:      (id)  sender;

-(IBAction) renameConfigurationMenuItemWasClicked:    (id) sender;
-(IBAction) duplicateConfigurationMenuItemWasClicked: (id) sender;
-(IBAction) makePrivateOrSharedMenuItemWasClicked:    (id) sender;
-(IBAction) showOnTunnelblickMenuMenuItemWasClicked:  (id) sender;
-(IBAction) editOpenVPNConfigurationFileMenuItemWasClicked:      (id) sender;
-(IBAction) showOpenvpnLogMenuItemWasClicked:         (id)  sender;
-(IBAction) removeCredentialsMenuItemWasClicked:      (id) sender;

-(IBAction) disconnectButtonWasClicked:          (id)  sender;
-(IBAction) connectButtonWasClicked:             (id)  sender;

-(IBAction) logToClipboardButtonWasClicked:             (id)  sender;

-(IBAction) configurationsHelpButtonWasClicked: (id)  sender;

-(IBAction) monitorNetworkForChangesCheckboxWasClicked: (id) sender;

-(IBAction) whenToConnectManuallyMenuItemWasClicked:          (id) sender;
-(IBAction) whenToConnectTunnelblickLaunchMenuItemWasClicked: (id) sender;
-(IBAction) whenToConnectOnComputerStartMenuItemWasClicked:   (id) sender;

-(IBAction) advancedButtonWasClicked:                         (id) sender;


// Methods for GeneralView

-(IBAction) useShadowCopiesCheckboxWasClicked:            (id) sender;
-(IBAction) monitorConfigurationFolderCheckboxWasClicked: (id) sender;

-(IBAction) updatesCheckAutomaticallyCheckboxWasClicked:  (id) sender;
-(IBAction) updatesCheckNowButtonWasClicked:              (id) sender;

-(IBAction) resetDisabledWarningsButtonWasClicked:        (id) sender;

-(IBAction) generalHelpButtonWasClicked:                  (id) sender;


// Methods for AppearanceView

-(IBAction) appearancePlaceIconNearSpotlightCheckboxWasClicked:    (id) sender;

-(IBAction) appearanceDisplayConnectionSubmenusCheckboxWasClicked: (id) sender;
-(IBAction) appearanceDisplayConnectionTimersCheckboxWasClicked:   (id) sender;

-(IBAction) appearanceHelpButtonWasClicked:                        (id) sender;


// Method for InfoView
-(IBAction) infoHelpButtonWasClicked: (id) sender;


// Getters & Setters

TBPROPERTY_READONLY(ConfigurationsView *, configurationsPrefsView)

TBPROPERTY_READONLY(NSInteger, selectedWhenToConnectIndex)

TBPROPERTY(NSInteger, selectedLeftNavListIndex,       setSelectedLeftNavListIndex)
TBPROPERTY(NSInteger, selectedSetNameserverIndex,     setSelectedSetNameserverIndex)
TBPROPERTY(NSInteger, selectedSoundOnConnectIndex,    setSelectedSoundOnConnectIndex)
TBPROPERTY(NSInteger, selectedSoundOnDisconnectIndex, setSelectedSoundOnDisconnectIndex)

TBPROPERTY(NSInteger, selectedKeyboardShortcutIndex, setSelectedKeyboardShortcutIndex)
TBPROPERTY(NSInteger, selectedMaximumLogSizeIndex,   setSelectedMaximumLogSizeIndex)

TBPROPERTY(NSInteger, selectedAppearanceIconSetIndex,                         setSelectedAppearanceIconSetIndex)
TBPROPERTY(NSInteger, selectedAppearanceConnectionWindowDisplayCriteriaIndex, setSelectedAppearanceConnectionWindowDisplayCriteriaIndex)

@end
