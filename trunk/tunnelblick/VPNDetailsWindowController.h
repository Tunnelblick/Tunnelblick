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
#import "SettingsSheetWindowController.h"


@class VPNConnection;


@interface VPNDetailsWindowController : NSWindowController <NSTextStorageDelegate, NSWindowDelegate>
{
    NSString                * previouslySelectedNameOnLeftNavList;
    
    NSMutableArray          * leftNavList;                      // Items in the left navigation list as displayed to the user
    //                                                             Each item is a string with either
    //                                                             a folder name (possibly indented) or
    //                                                             a connection name (possibly indented)
    
    NSMutableArray          * leftNavDisplayNames;              // A string for each item in leftNavList
    //                                                             Each item is a string with either
    //                                                             An empty string (corresponding to a folder name entry in leftNavList) or
    //                                                             The full display name for the corresponding connection
    
    int                       selectedLeftNavListIndex;         // Index of the selected item in the left navigation list
    
    SettingsSheetWindowController * settingsSheetWindowController;
    
    AuthorizationRef          authorization;                    // Authorization reference for Shared/Deployed configuration manipulation
    
    NSInteger                 selectedWhenToConnectIndex;
    
    NSArray                 * sortedSounds;
    
    BOOL                      doNotPlaySounds;                  // Used to inhibit playing sounds while switching configurations
        
    BOOL                      logWindowIsOpen;                  // True if window is open, false otherwise
    
    // For window
    
    IBOutlet NSWindow            * logWindow;
    
    IBOutlet NSSplitView         * splitView;
    IBOutlet NSView              * leftSplitView;
    
    IBOutlet NSTableView         * leftNavTableView;
    IBOutlet NSTableHeaderView   * leftNavListHeaderView;
    IBOutlet NSTableColumn       * leftNavTableColumn;
    
    IBOutlet NSButton            * addConfigurationButton;
    IBOutlet NSButton            * removeConfigurationButton;
    IBOutlet NSPopUpButton       * workOnConfigurationPopUpButton;
    IBOutlet NSArrayController   * workOnConfigurationArrayController;
    
    IBOutlet NSMenuItem          * renameConfigurationMenuItem;
    IBOutlet NSMenuItem          * duplicateConfigurationMenuItem;
    IBOutlet NSMenuItem          * makePrivateOrSharedMenuItem;
    IBOutlet NSMenuItem          * showOnTunnelblickMenuMenuItem;
    IBOutlet NSMenuItem          * editOpenVPNConfigurationFileMenuItem;
    IBOutlet NSMenuItem          * showOpenvpnLogMenuItem;
    IBOutlet NSMenuItem          * removeCredentialsMenuItem;
    
    IBOutlet NSTextFieldCell     * configurationNameTFC;
    IBOutlet NSTextFieldCell     * configurationStatusTFC;
    
    IBOutlet NSButton            * generalHelpButton;
    IBOutlet NSButton            * disconnectButton;
    IBOutlet NSButton            * connectButton;
    
    // Log tab
    
    IBOutlet NSTabViewItem       * logTabViewItem;
    IBOutlet NSTextView          * logView;
    IBOutlet NSScrollView        * logScrollView;
    
    IBOutlet NSProgressIndicator * progressIndicator;
    
    IBOutlet NSButton            * copyLogButton;
    
    // Settings tab
    
    IBOutlet NSTabViewItem       * settingsTabViewItem;

    IBOutlet NSTextField         * whenToConnectTF;
    IBOutlet NSTextFieldCell     * whenToConnectTFC;
    IBOutlet NSPopUpButton       * whenToConnectPopUpButton;
    IBOutlet NSMenuItem          * whenToConnectManuallyMenuItem;
    IBOutlet NSMenuItem          * whenToConnectTunnelblickLaunchMenuItem;
    IBOutlet NSMenuItem          * whenToConnectOnComputerStartMenuItem;
    
    IBOutlet NSTextField         * setNameserverTF;
    IBOutlet NSTextFieldCell     * setNameserverTFC;
    IBOutlet NSPopUpButton       * setNameserverPopUpButton;
    IBOutlet NSArrayController   * setNameserverArrayController;
    IBOutlet NSInteger             selectedSetNameserverIndex;
    
    IBOutlet NSButton            * monitorNetworkForChangesCheckbox;
    
    IBOutlet NSBox               * alertSoundsBox;
    
    IBOutlet NSTextField         * connectionAlertSoundTF;
    IBOutlet NSTextFieldCell     * connectionAlertSoundTFC;
    IBOutlet NSTextField         * disconnectionAlertSoundTF;
    IBOutlet NSTextFieldCell     * disconnectionAlertSoundTFC;
    IBOutlet NSPopUpButton       * soundOnConnectPopUpButton;
    IBOutlet NSPopUpButton       * soundOnDisconnectPopUpButton;
    IBOutlet NSArrayController   * soundOnConnectArrayController;
    IBOutlet NSArrayController   * soundOnDisconnectArrayController;
    IBOutlet NSInteger             selectedSoundOnConnectIndex;
    IBOutlet NSInteger             selectedSoundOnDisconnectIndex;
    
    IBOutlet NSButton            * advancedButton;    
    
}

// General methods

-(void)             openLogWindow;
-(void)             hookedUpOrStartedConnection:                          (VPNConnection *)   connection;
-(void)             indicateWaiting;
-(void)             indicateNotWaiting;
-(void)             update;
-(void)             updateNavigationLabels;
-(void)             validateWhenConnectingForConnection:                  (VPNConnection *) theConnection;
-(void)             validateConnectAndDisconnectButtonsForConnection:     (VPNConnection *) theConnection;
-(void)             monitorNetworkForChangesCheckboxChangedForConnection: (VPNConnection *) theConnection;
-(BOOL)             forceDisableOfNetworkMonitoring;

// Methods for window

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

-(IBAction) copyLogButtonWasClicked:             (id)  sender;

-(IBAction) generalHelpButtonWasClicked:         (id)  sender;

-(IBAction) monitorNetworkForChangesCheckboxWasClicked: (id) sender;

-(IBAction) whenToConnectManuallyMenuItemWasClicked:          (id) sender;
-(IBAction) whenToConnectTunnelblickLaunchMenuItemWasClicked: (id) sender;
-(IBAction) whenToConnectOnComputerStartMenuItemWasClicked:   (id) sender;
-(IBAction) advancedButtonWasClicked:                         (id)  sender;

-(void)     setSelectedLeftNavListIndex:         (int) newValue;

-(NSInteger) selectedSetNameserverIndex;
-(void)     setSelectedSetNameserverIndex:       (NSInteger) newValue;

-(NSInteger) selectedSoundOnConnectIndex;
-(void)     setSelectedSoundOnConnectIndex:      (NSInteger) newValue;

-(NSInteger) selectedSoundOnDisconnectIndex;
-(void)     setSelectedSoundOnDisconnectIndex:   (NSInteger) newValue;

@end
