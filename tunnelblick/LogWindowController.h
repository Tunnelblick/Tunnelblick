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

@class VPNConnection;


@interface LogWindowController : NSWindowController <NSTextStorageDelegate,NSWindowDelegate>

{
    IBOutlet NSWindow       * logWindow;

    IBOutlet NSTabView      * tabView;
    IBOutlet NSSplitView    * splitView;
    IBOutlet NSView         * leftSplitView;
    IBOutlet NSView         * rightSplitView;
    IBOutlet NSTableView    * leftNavListView;
    IBOutlet NSTableColumn  * leftNavTableColumn;
    
    IBOutlet NSPopUpButton  * modifyNameserverPopUpButton;
    IBOutlet id               onLaunchRadioButton;
    IBOutlet id               onSystemStartRadioButton;
    IBOutlet NSButton       * autoConnectCheckbox;
    IBOutlet NSButton       * monitorConnnectionCheckbox;
    IBOutlet NSButton       * editButton;
    IBOutlet NSButton       * shareButton;
    IBOutlet NSButton       * connectButton;
    IBOutlet NSButton       * disconnectButton;
    
    IBOutlet NSProgressIndicator * progressIndicator;

    IBOutlet NSArrayController * modifyNameserverPopUpButtonArrayController;

    NSMutableArray          * leftNavList;                  // Items in the left navigation list as displayed to the user
    //                                                         Each item is a string with either
    //                                                         a folder name (possibly indented) or
    //                                                         a connection name (possibly indented)

    NSMutableArray          * leftNavDisplayNames;          // A string for each item in leftNavList
    //                                                         Each item is a string with either
    //                                                         An empty string (corresponding to a folder name entry in leftNavList) or
    //                                                         The full display name for the corresponding connection
    
    NSString                * oldSelectedConnectionName;    // The name of the selected connection (if any) before a making a private configuration public or vice-versa
    //                                                         so the program can re-select. nil after re-selecting it
    
    int                       selectedLeftNavListIndex;     // Index of the selected item in the left navigation list
    
    int                       selectedModifyNameserverIndex;// Holds index of the selected 'Set nameserver' option

    BOOL                      logWindowIsOpen;              // Indicates if Details window is being displayed
    
    BOOL                      logWindowIsUsingTabs;         // Indicates Details window is using tabs (and not using left-navigation)
    
}

// Button and checkbox actions
-(IBAction)         autoConnectPrefButtonWasClicked:        (id)                sender;
-(IBAction)         connectButtonWasClicked:                (id)                sender;
-(IBAction)         disconnectButtonWasClicked:             (id)                sender;
-(IBAction)         editConfigButtonWasClicked:             (id)                sender;
-(IBAction)         monitorConnectionPrefButtonWasClicked:  (id)                sender;
-(IBAction)         onLaunchRadioButtonWasClicked:          (id)                sender;
-(IBAction)         onSystemStartRadioButtonWasClicked:     (id)                sender;
-(IBAction)         shareConfigButtonWasClicked:            (id)                sender;

// General methods
-(void)             connectionHasTerminated:                (VPNConnection *)   connection;
-(void)             hookedUpOrStartedConnection:            (VPNConnection *)   connection;
-(void)             indicateWaiting;
-(void)             indicateNotWaiting;
-(void)             openLogWindow;
-(void)             update;
-(void)             updateNavigationLabels;
-(void)             validateWhenConnectingForConnection:    (VPNConnection *)   connection;
-(void)             validateConnectAndDisconnectButtonsForConnection: (VPNConnection *) connection;

// Getters and Setters
-(int)              selectedModifyNameserverIndex;
-(void)             setSelectedModifyNameserverIndex:       (int)               newValue;

-(int)              selectedLeftNavListIndex;
-(void)             setSelectedLeftNavListIndex:            (int)               newValue;
@end
