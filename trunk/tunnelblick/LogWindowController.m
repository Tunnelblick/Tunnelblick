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
#import "LogWindowController.h"
#import "VPNConnection.h"
#import "TBUserDefaults.h"
#import "ConfigurationManager.h"
#import "MenuController.h"

extern NSMutableArray       * gConfigDirs;
extern NSString             * gPrivatePath;
extern NSString             * gSharedPath;
extern NSFileManager        * gFileMgr;
extern TBUserDefaults       * gTbDefaults;
extern AuthorizationRef       gAuthorization;


@interface LogWindowController() // PRIVATE METHODS

-(int)              firstDifferentComponent:                (NSArray *)         a
                                        and:                (NSArray *)         b;

-(void)             fixWhenConnectingButtons;

-(NSString *)       indent:                                 (NSString *)        s
                        by:                                 (int)               n;

-(void)             saveMonitorConnectionCheckboxState:     (BOOL)              inBool;

-(void)             saveOnSystemStartRadioButtonState:      (BOOL)              onSystemStart
                                        forConnection:      (VPNConnection *)   connection;

-(void)             saveAutoLaunchCheckboxState:            (BOOL)              inBool;

-(void)             saveUseNameserverPopupButtonState:      (unsigned)          inValue;

-(VPNConnection *)  selectedConnection;

-(NSTextView *)     selectedLogView;

-(void)             setLogWindowTitle;

-(void)             setTitle:                               (NSString *)        newTitle
                   ofControl:                               (id)                theControl;

-(NSString *)       timeLabelForConnection:                 (VPNConnection *)   connection;

-(void)             validateDetailsWindowControls;

@end

@implementation LogWindowController

-(id) init
{
    if (  ![super initWithWindowNibName:@"LoginWindow"]  ) {
        return nil;
    }
    
    oldSelectedConnectionName = nil;

    return self;
}

-(void) update
{
    // Add or remove configurations from the Log window (if it is open) by closing and reopening it
    BOOL logWindowWasOpen = logWindowIsOpen;
    BOOL logWindowWasUsingTabs = logWindowIsUsingTabs;
    [logWindow close];
    [logWindow release];
    logWindow = nil;
    logWindowIsOpen = FALSE;
    if (  logWindowWasOpen  ) {
        [self openLogWindow];
        if (   logWindowWasUsingTabs
            && ( ! logWindowIsUsingTabs)  ) {
            [logWindow close];          // Have to do open/close/open or the leftNavList doesn't paint properly
            [logWindow release];        //
            logWindow = nil;            //
            logWindowIsOpen = FALSE;    //
            [self openLogWindow];  //
        }
    } else {
        oldSelectedConnectionName = nil;
    }
}

-(void) indicateWaiting
{
    [progressIndicator startAnimation: self];
}

-(void) indicateNotWaiting
{
    [progressIndicator stopAnimation: self];
}

-(void) connectionHasTerminated: (VPNConnection *) connection
{
    if (   connection
        && ( connection == [self selectedConnection] )  ) {
        [connection stopMonitoringLogFiles];
    }
}

-(void) hookedUpOrStartedConnection: (VPNConnection *) connection
{
    if (   connection
        && ( connection == [self selectedConnection] )  ) {
        [connection startMonitoringLogFiles];
    }
}

// Validates (disables or enables) the Connect and Disconnect buttons in the Details... window
-(void) validateConnectAndDisconnectButtonsForConnection: (VPNConnection *) connection
{
    if (   ( ! connection )
        || ( connection != [self selectedConnection] )  ) {
        return;
    }
    
    NSString * displayName = [connection displayName];
    
    NSString * disableConnectButtonKey    = [displayName stringByAppendingString: @"-disableConnectButton"];
    NSString * disableDisconnectButtonKey = [displayName stringByAppendingString: @"-disableDisconnectButton"];
    [connectButton setEnabled: (   [connection isDisconnected]
                                && ( ! [gTbDefaults boolForKey: disableConnectButtonKey] )  )];
    [disconnectButton setEnabled:(   ( ! [connection isDisconnected] )
                                  && ( ! [gTbDefaults boolForKey: disableDisconnectButtonKey] )  )];
}

// Updates the "when Tunnelblick launches" and "when the computer starts" radio buttons for the specified connection if it is being displayed
-(void) validateWhenConnectingForConnection: (VPNConnection *) connection
{
    if (   ( ! connection )
        || ( connection != [self selectedConnection] )  ) {
        return;
    }
    
    NSString * displayName      = [connection displayName];
    NSString * autoConnectKey   = [displayName stringByAppendingString:@"autoConnect"];
    NSString * onSystemStartKey = [displayName stringByAppendingString: @"-onSystemStart"];
    
    if (   [gTbDefaults boolForKey:autoConnectKey]  ) {
        if (  [gTbDefaults boolForKey: onSystemStartKey]  ) {
            if (  [[connection configPath] hasPrefix: gPrivatePath]  ) {
                // onSystemStart pref, but this is a private configuration, so force the pref off
                if (  [gTbDefaults canChangeValueForKey: onSystemStartKey]  ) {
                    [gTbDefaults setBool: FALSE forKey: onSystemStartKey];  // Shouldn't be set, so clear it
                    [self saveOnSystemStartRadioButtonState: TRUE forConnection: connection];
                    NSLog(@"The '-onSystemStart' preference was set but it has been cleared because '%@' is a private configuration", displayName);
                } else {
                    NSLog(@"The '-onSystemStart' preference for '%@' is being forced, but will be ignored because it is a private configuration", displayName);
                }
            } else {
                [self saveOnSystemStartRadioButtonState: TRUE forConnection: connection];
            }
        } else {
            [self saveOnSystemStartRadioButtonState: FALSE forConnection: connection];
        }
    } else {
        [self saveOnSystemStartRadioButtonState: FALSE forConnection: connection];
    }
    
    if (   [gTbDefaults boolForKey:autoConnectKey]
        && [gTbDefaults canChangeValueForKey: autoConnectKey]
        && [gTbDefaults canChangeValueForKey: onSystemStartKey]  ) {
        if (  [[connection configPath] hasPrefix: gPrivatePath]  ) {
            [onSystemStartRadioButton setEnabled: NO];
            [onLaunchRadioButton      setEnabled: NO];
        } else {
            [onSystemStartRadioButton setEnabled: YES];
            [onLaunchRadioButton      setEnabled: YES];
        }
        
        if (   [gTbDefaults boolForKey: autoConnectKey]
            && [gTbDefaults boolForKey: onSystemStartKey]  ) {
            [autoConnectCheckbox         setEnabled: NO];        // Disable other controls for daemon connections because otherwise
            [modifyNameserverPopUpButton setEnabled: NO];        // we have to update the daemon's .plist to reflect changes, and
            [monitorConnnectionCheckbox  setEnabled: NO];        // that requires admin authorization for each change
            [shareButton                 setEnabled: NO];
        }
    } else {
        [onLaunchRadioButton      setEnabled: NO];
        [onSystemStartRadioButton setEnabled: NO];
    }
}    

// Validates (sets and disables or enables) all of the controls in the Details... window (including the Connect and Disconnect buttons)
-(void) validateDetailsWindowControls
{
    VPNConnection* connection = [self selectedConnection];
    
    NSString * displayName = [connection displayName];
    
    [self validateConnectAndDisconnectButtonsForConnection: connection];
    
	// The "Edit configuration" button is also the "Examine Configuration" button so first we indicate which it is
    if (  [[ConfigurationManager defaultManager] userCanEditConfiguration: [connection configPath]]  ) {
        [self setTitle: NSLocalizedString(@"Edit configuration", @"Button") ofControl: editButton];
    } else {
        [self setTitle: NSLocalizedString(@"Examine configuration", @"Button") ofControl: editButton];
    }
    
    NSString *disableEditConfigKey = [displayName stringByAppendingString:@"disableEditConfiguration"];
    if (  [gTbDefaults boolForKey:disableEditConfigKey]  ) {
        [editButton setEnabled: NO];
    } else {
        [editButton setEnabled: YES];
    }
    
	// The "Share configuration" button is also the "Make configuration private" button and it is only active when it is a .tblk configuration
    NSString *disableShareConfigKey = [displayName stringByAppendingString:@"disableShareConfigurationButton"];
    if (  ! [gTbDefaults boolForKey: disableShareConfigKey]  ) {
        NSString * path = [[self selectedConnection] configPath];
        if (  [[path pathExtension] isEqualToString: @"tblk"]  ) {
            if (  [path hasPrefix: gSharedPath]  ) {
                [self setTitle: NSLocalizedString(@"Make configuration private", @"Button") ofControl: shareButton];
                [shareButton setEnabled: YES];
            } else if (  [path hasPrefix: gPrivatePath]  ) {
                [self setTitle: NSLocalizedString(@"Share configuration"       , @"Button") ofControl: shareButton];
                [shareButton setEnabled: YES];
            } else {
                // Deployed, so we don't offer to share it or make it private
                [self setTitle: NSLocalizedString(@"Share configuration"       , @"Button") ofControl: shareButton];
                [shareButton setEnabled: NO];
            }
        } else {
            [self setTitle: NSLocalizedString(@"Share configuration"           , @"Button") ofControl: shareButton];
            [shareButton setEnabled: NO];
        }
    } else {
        [shareButton setEnabled: NO];
    }
    
    // Set up the 'Set nameserver' popup button with localized values
    [modifyNameserverPopUpButtonArrayController setContent: [connection modifyNameserverOptionList]];
    
    // If the width of the 'Set nameserver' popup button changes, shift the 'Monitor connection' checkbox left or right as needed
    NSRect oldRect = [modifyNameserverPopUpButton frame];
    [modifyNameserverPopUpButton sizeToFit];
    NSRect newRect = [modifyNameserverPopUpButton frame];
    float widthChange = newRect.size.width - oldRect.size.width;
    NSRect oldPos = [monitorConnnectionCheckbox frame];
    oldPos.origin.x = oldPos.origin.x + widthChange;
    [monitorConnnectionCheckbox setFrame:oldPos];
    
    int index = -1;
	NSString *useDNSKey = [displayName stringByAppendingString:@"useDNS"];
    int useDNSPreferenceValue = [connection useDNSStatus];
    NSString * useDNSStringValue = [NSString stringWithFormat: @"%d", useDNSPreferenceValue];
    NSArray * setNameserverEntries = [modifyNameserverPopUpButtonArrayController content];
    int i;
    for (i=0; i<[setNameserverEntries count]; i++) {
        NSDictionary * dictForEntry = [setNameserverEntries objectAtIndex: i];
        if (  [[dictForEntry objectForKey: @"value"] isEqualToString: useDNSStringValue]  ) {
            index = i;
            break;
        }
    }
    if (  index == -1  ) {
        NSLog(@"Invalid value for '%@' preference. Using 'Do not set nameserver'", useDNSKey);
        index = 0;
    }
    
    // ***** Duplicate the effect of [self setSelectedModifyNameserverIndex: index] but without calling ourselves
    if (  index != selectedModifyNameserverIndex  ) {
        selectedModifyNameserverIndex = index;
        [modifyNameserverPopUpButton selectItemAtIndex: index];
        [self saveUseNameserverPopupButtonState: (unsigned) index];
        //[self validateDetailsWindowControls]; DO NOT DO THIS -- recurses infinitely. That is why we do this duplicate code instead of invoking setSelectedModifyNameserverIndex:
    }
    // ***** End duplication of the effect of [self setSelectedModifyNameserverIndex: index] but without calling ourselves
    
    [modifyNameserverPopUpButton setNeedsDisplay]; // Workaround for bug in OS X 10.4.11 ("Tiger") that causes misdraws
    [monitorConnnectionCheckbox  setNeedsDisplay];
    
    if (  [gTbDefaults canChangeValueForKey: useDNSKey]  ) {
        [modifyNameserverPopUpButton setEnabled: YES];
    } else {
        [modifyNameserverPopUpButton setEnabled: NO];
	}
	
	NSString *notMonitorConnectionKey = [displayName stringByAppendingString:@"-notMonitoringConnection"];
    if (   [gTbDefaults canChangeValueForKey: notMonitorConnectionKey]
        && (   ([connection useDNSStatus] == 1)
            || ([connection useDNSStatus] == 4) )  ) {
            [monitorConnnectionCheckbox setEnabled: YES];
        } else {
            [monitorConnnectionCheckbox setEnabled: NO];
        }
    
	if(   ( ! [gTbDefaults boolForKey:notMonitorConnectionKey] )
       && (   ([connection useDNSStatus] == 1)
           || ([connection useDNSStatus] == 4) )  ) {
           [monitorConnnectionCheckbox setState:NSOnState];
       } else {
           [monitorConnnectionCheckbox setState:NSOffState];
       }
    
    NSString *autoConnectKey = [displayName stringByAppendingString:@"autoConnect"];
    if (  [gTbDefaults canChangeValueForKey: autoConnectKey]  ) {
        [autoConnectCheckbox setEnabled: YES];
    } else {
        [autoConnectCheckbox setEnabled: NO];
    }
	if (  [gTbDefaults boolForKey: autoConnectKey]  ) {
		[autoConnectCheckbox setState:NSOnState];
	} else {
		[autoConnectCheckbox setState:NSOffState];
	}
	
    if (  ! [connection tryingToHookup]  ) {
        [self validateWhenConnectingForConnection: connection];     // May disable other controls if 'when computer connects' is selected
    }
}
-(void)updateNavigationLabels
{
    if (  ! logWindowIsOpen  ) {
        return;
    }
    
    if (  logWindowIsUsingTabs  ) {
        NSArray *keyArray = [[[[NSApp delegate] myVPNConnectionDictionary] allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
        NSArray *myConnectionArray = [[[NSApp delegate] myVPNConnectionDictionary] objectsForKeys:keyArray notFoundMarker:[NSNull null]];
        NSEnumerator *connectionEnumerator = [myConnectionArray objectEnumerator];
        VPNConnection *connection;
        int i = 0;
        while(connection = [connectionEnumerator nextObject]) {
            NSString * label = [self timeLabelForConnection: connection];
            [[tabView tabViewItemAtIndex:i] setLabel: label];
            i++;
        }
    } else {
        NSString * dispName = [leftNavDisplayNames objectAtIndex: selectedLeftNavListIndex];
        VPNConnection  * connection = [[[NSApp delegate] myVPNConnectionDictionary] objectForKey: dispName];
        NSString * label = [self timeLabelForConnection: connection];
        [[tabView tabViewItemAtIndex:0] setLabel: label];
	}
}

-(NSString *) timeLabelForConnection: (VPNConnection *) connection
{ 
    NSString * cState = [connection state];
    NSString * cTimeS = @"";
    
    // Get connection duration if preferences say to 
    if (   [gTbDefaults boolForKey:@"showConnectedDurations"]
        && [cState isEqualToString: @"CONNECTED"]    ) {
        NSDate * csd = [connection connectedSinceDate];
        NSTimeInterval ti = [csd timeIntervalSinceNow];
        long cTimeL = (long) round(-ti);
        if ( cTimeL >= 0 ) {
            if ( cTimeL < 3600 ) {
                cTimeS = [NSString stringWithFormat:@" %li:%02li", cTimeL/60, cTimeL%60];
            } else {
                cTimeS = [NSString stringWithFormat:@" %li:%02li:%02li", cTimeL/3600, (cTimeL/60) % 60, cTimeL%60];
            }
        }
    }
    return [NSString stringWithFormat:@"%@ (%@%@)",[connection displayName], NSLocalizedString(cState, nil), cTimeS];
}

- (void) tabView: (NSTabView*) inTabView willSelectTabViewItem: (NSTabViewItem*) tabViewItem
{
    VPNConnection * connection = [self selectedConnection];
    [connection stopMonitoringLogFiles];
    
    NSView* view = [[inTabView selectedTabViewItem] view];
    [tabViewItem setView: view];
    [[[self selectedLogView] textStorage] setDelegate: nil];
}

- (void) tabView: (NSTabView*) inTabView didSelectTabViewItem: (NSTabViewItem*) tabViewItem
{
    VPNConnection* newConnection = [self selectedConnection];
    
    NSTextView* logView = [self selectedLogView];
    [logView setEditable: NO];
    [[logView layoutManager] replaceTextStorage: [newConnection logStorage]];
	[logView scrollRangeToVisible: NSMakeRange([[logView string] length]-1, 0)];
	
    [[logView textStorage] setDelegate: self];
    
    [self setLogWindowTitle];
    
    selectedModifyNameserverIndex = -1; // Won't match any valid value, so when first set it will trigger a change notice
    
    [self validateDetailsWindowControls];

    [newConnection startMonitoringLogFiles];
}

- (void) setLogWindowTitle
{
    NSString * name = [[self selectedConnection] displayName];
    if (  [name isEqualToString: @"Tunnelblick"]  ) {
        name = @"";
    } else {
        name = [NSString stringWithFormat: @" - %@", name];
    }
    
    [logWindow setTitle: [NSString stringWithFormat: @"%@%@%@",
                          NSLocalizedString(@"Details - Tunnelblick", @"Window title"),
                          name,
                          [[self selectedConnection] displayLocation]]];
	
}

- (void) textStorageDidProcessEditing: (NSNotification*) aNotification
{
    NSNotification *notification = [NSNotification notificationWithName: @"LogDidChange" 
                                                                 object: [self selectedLogView]];
    [[NSNotificationQueue defaultQueue] enqueueNotification: notification 
                                               postingStyle: NSPostWhenIdle
                                               coalesceMask: NSNotificationCoalescingOnName | NSNotificationCoalescingOnSender 
                                                   forModes: nil];
}

- (void) logNeedsScrollingHandler: (NSNotification*) aNotification
{
    [self performSelectorOnMainThread: @selector(doLogScrolling:) withObject: [aNotification object] waitUntilDone: NO];
}

-(void) doLogScrolling: (NSTextView *) textView
{
    [textView scrollRangeToVisible: NSMakeRange([[textView string] length]-1, 0)];
}

- (NSTextView*) selectedLogView
{
    NSTextView* result = [[[[[tabView selectedTabViewItem] view] subviews] lastObject] documentView];
    return result;
}

- (VPNConnection*) selectedConnection
/*" Returns the connection associated with the currently selected log tab or nil on error. "*/
{
    NSString* dispNm;
    if (  logWindowIsUsingTabs  ) {
        if (![tabView selectedTabViewItem]) {
            [tabView selectFirstTabViewItem: nil];
        }
        dispNm = [[tabView selectedTabViewItem] identifier];
    } else {
        dispNm = [leftNavDisplayNames objectAtIndex: selectedLeftNavListIndex];
    }
    
    VPNConnection* connection = [[[NSApp delegate] myVPNConnectionDictionary] objectForKey: dispNm];
    NSArray *allConnections = [[[NSApp delegate] myVPNConnectionDictionary] allValues];
    if(connection) return connection;
    else if([allConnections count]) return [allConnections objectAtIndex:0] ; 
    else return nil;
}

-(void) openLogWindow
{
    if (logWindow != nil) {
        [logWindow makeKeyAndOrderFront: self];
        [NSApp activateIgnoringOtherApps:YES];
        logWindowIsOpen = TRUE;
        
        if (  ! [[NSApp delegate] showDurationsTimer]  ) {  // Start the timer used to update the duration displays
            [[NSApp delegate] startOrStopDurationsTimer];
        }
        
        return;
    }
    
    NSArray * allConfigsSorted = [[[[NSApp delegate] myVPNConnectionDictionary] allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
	NSEnumerator* e = [allConfigsSorted objectEnumerator];
	NSTabViewItem* initialItem;
	VPNConnection* connection = [[[NSApp delegate] myVPNConnectionDictionary] objectForKey: [e nextObject]];
    if (  ! connection  ) {
        NSLog(@"Internal program error: openLogWindow: but there are no configurations");
        return;
    }
    
    [NSBundle loadNibNamed: @"LogWindow" owner: self]; // also sets tabView etc.
    
    int maxNumberOfTabs = 8;
    id obj = [gTbDefaults objectForKey: @"maximumNumberOfTabs"];
    if (  obj  ) {
        if (  [obj respondsToSelector: @selector(intValue)]  ) {
            maxNumberOfTabs = [obj intValue];
        } else {
            NSLog(@"'maximumNumberOfTabs' preference is being ignored because it is not a number");
        }
    }
    
    logWindowIsUsingTabs = (  [[[NSApp delegate] myVPNConnectionDictionary] count] <= maxNumberOfTabs  );
    
    // Set the window's size and position from preferences (saved when window is closed)
    // But only if the preference's version matches the TB version (since window size could be different in different versions of TB)
    NSString * tbVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    if (  [tbVersion isEqualToString: [gTbDefaults objectForKey:@"detailsWindowFrameVersion"]]    ) {
        NSString * frameString = [gTbDefaults objectForKey: @"detailsWindowFrame"];
        if (  frameString != nil  ) {
            [logWindow setFrameFromString:frameString];
        }
        frameString = [gTbDefaults objectForKey: @"detailsWindowLeftFrame"];
        if (  frameString != nil  ) {
            NSRect frame;
            frame = NSRectFromString(frameString);
            if (  frame.size.width < LEFT_NAV_AREA_MINIMUM_SIZE  ) {
                frame.size.width = LEFT_NAV_AREA_MINIMUM_SIZE;
            }
            [leftSplitView setFrame: frame];
        }
    }
    
    initialItem = [tabView tabViewItemAtIndex: 0];
    NSString * dispNm = [connection displayName];
    [initialItem setIdentifier: dispNm];
    [initialItem setLabel:      dispNm];
    
    int leftNavIndexToSelect = 0;
    
    if (  logWindowIsUsingTabs  ) {
        // Make the left navigation area very small
        NSRect frameRect = [leftSplitView frame];
        frameRect.size.width = LEFT_NAV_AREA_MINIMAL_SIZE;
        [leftSplitView setFrame: frameRect];
        [leftSplitView display];
        
        int curTabIndex = 0;
        [tabView selectTabViewItemAtIndex:0];
        BOOL haveSelectedAConnection = ! [connection isDisconnected];
        while (connection = [[[NSApp delegate] myVPNConnectionDictionary] objectForKey: [e nextObject]]) {
            NSTabViewItem* newItem = [[NSTabViewItem alloc] init];
            dispNm = [connection displayName];
            [newItem setIdentifier: dispNm];
            [newItem setLabel:      dispNm];
            [tabView addTabViewItem: newItem];
            [newItem release];
            ++curTabIndex;
            if (  oldSelectedConnectionName  ) {
                if (  [dispNm isEqualToString: oldSelectedConnectionName]  ) {
                    [tabView selectTabViewItemAtIndex:curTabIndex];
                    haveSelectedAConnection = YES;
                    oldSelectedConnectionName = nil;
                }
            } else if (   ( ! haveSelectedAConnection )
                       && ( ! [connection isDisconnected] )  ) {
                [tabView selectTabViewItemAtIndex:curTabIndex];
                haveSelectedAConnection = YES;
            }
        }
    } else {
        [leftNavList         release];
        [leftNavDisplayNames release];
        leftNavList         = [[NSMutableArray alloc] initWithCapacity: [[[NSApp delegate] myVPNConnectionDictionary] count]];
        leftNavDisplayNames = [[NSMutableArray alloc] initWithCapacity: [[[NSApp delegate] myVPNConnectionDictionary] count]];
        int curTabIndex = 0;
        BOOL haveSelectedAConnection = ! [connection isDisconnected];
        NSMutableArray * currentFolders = [NSMutableArray array]; // Components of folder enclosing most-recent leftNavList/leftNavDisplayNames entry
        NSEnumerator* configEnum = [allConfigsSorted objectEnumerator];
        while (connection = [[[NSApp delegate] myVPNConnectionDictionary] objectForKey: [configEnum nextObject]]) {
            dispNm = [connection displayName];
            NSArray * currentConfig = [dispNm componentsSeparatedByString: @"/"];
            int firstDiff = [self firstDifferentComponent: currentConfig and: currentFolders];
            
            // Track any necessary "outdenting"
            if (  firstDiff < [currentFolders count]  ) {
                // Remove components from the end of currentFolders until we have a match
                int i;
                for (  i=0; i < ([currentFolders count]-firstDiff); i++  ) {
                    [currentFolders removeLastObject];
                }
            }
            
            // currentFolders and currentConfig now match, up to but not including the firstDiff-th entry
            
            // Add a "folder" line for each folder in currentConfig starting with the first-Diff-th entry (if any)
            int i;
            for (  i=firstDiff; i < [currentConfig count]-1; i++  ) {
                [leftNavDisplayNames addObject: @""];
                NSString * folderName = [currentConfig objectAtIndex: i];
                [leftNavList         addObject: [NSString stringWithString: 
                                                 [self indent: folderName by: firstDiff+i]]];
                [currentFolders addObject: folderName];
                ++curTabIndex;
            }
            
            // Add a "configuration" line
            [leftNavDisplayNames addObject: [NSString stringWithString: [connection displayName]]];
            [leftNavList         addObject: [NSString stringWithString: 
                                             [self indent: [currentConfig lastObject] by: [currentConfig count]-1]]];
            
            if (  oldSelectedConnectionName  ) {
                if (  [dispNm isEqualToString: oldSelectedConnectionName]  ) {
                    [self setSelectedLeftNavListIndex: curTabIndex];
                    haveSelectedAConnection = YES;
                    oldSelectedConnectionName = nil;
                }
            } else if (   ( ! haveSelectedAConnection )
                       && ( ! [connection isDisconnected] )  ) {
                leftNavIndexToSelect = curTabIndex;
                haveSelectedAConnection = YES;
            }
            ++curTabIndex;
        }
    }
    
	[logWindow setDelegate:self];
    
	[self setLogWindowTitle];
    
	// Localize buttons and checkboxes, shifting their neighbors left or right as needed
    // NOTE: We don't localize the contents of modifyNameserverPopUpButton because they are localized when they are inserted into it by
    //       validateDetailsWindowControls, which also does any necessary shifting of its neighbor, the 'Monitor connection' checkbox.
    
    [self setTitle: NSLocalizedString(@"Edit configuration"         , @"Button")        ofControl: editButton                 ];
    [self setTitle: NSLocalizedString(@"Share configuration"        , @"Button")        ofControl: shareButton                ];
    [self setTitle: NSLocalizedString(@"Connect"                    , @"Button")        ofControl: connectButton              ];
    [self setTitle: NSLocalizedString(@"Disconnect"                 , @"Button")        ofControl: disconnectButton           ];
    [self setTitle: NSLocalizedString(@"Monitor connection"         , @"Checkbox name") ofControl: monitorConnnectionCheckbox ];
    [self setTitle: NSLocalizedString(@"Automatically connect"      , @"Checkbox name") ofControl: autoConnectCheckbox        ];
    [self setTitle: NSLocalizedString(@"when Tunnelblick launches"  , @"Checkbox name") ofControl: onLaunchRadioButton        ];
    [self setTitle: NSLocalizedString(@"when computer starts"       , @"Checkbox name") ofControl: onSystemStartRadioButton   ];
    
	VPNConnection * myConnection = [self selectedConnection];
	NSTextStorage * store = [myConnection logStorage];
    
    [[[self selectedLogView] layoutManager] replaceTextStorage: store];
	
    if (  logWindowIsUsingTabs  ) {
        [self tabView:tabView didSelectTabViewItem:initialItem];
    } else {
        [leftNavListView reloadData];
        selectedLeftNavListIndex = -1;  // Force a change
        [self setSelectedLeftNavListIndex: leftNavIndexToSelect];
        [leftNavListView scrollRowToVisible: leftNavIndexToSelect];
    }
    
    [self updateNavigationLabels];
    
    // Set up a timer to update the tab labels with connections' duration times
    [[NSApp delegate] startOrStopDurationsTimer];
	
    [logWindow display];
    [logWindow makeKeyAndOrderFront: self];
    [NSApp activateIgnoringOtherApps:YES];
    logWindowIsOpen = TRUE;
}

-(int) firstDifferentComponent: (NSArray *) a and: (NSArray *) b
{
    int retVal = 0;
    int i;
    for (i=0;
         (i < [a count]) 
         && (i < [b count])
         && [[a objectAtIndex: i] isEqual: [b objectAtIndex: i]];
         i++  ) {
        ++retVal;
    }
    
    return retVal;
}

-(NSString *) indent: (NSString *) s by: (int) n
{
    NSString * retVal = [NSString stringWithFormat:@"%*s%@", 3*n, "", s];
    return retVal;
}

-(int)numberOfRowsInTableView:(NSTableView *)aTableView
{
    if (  aTableView == leftNavListView  ) {
        int n = [leftNavList count];
        return n;
    }
    
    return 0;
}

-(id) tableView:(NSTableView *) aTableView objectValueForTableColumn:(NSTableColumn *) aTableColumn row:(int) rowIndex
{
    if (  aTableView == leftNavListView  ) {
        NSString * s = [leftNavList objectAtIndex: rowIndex];
        return s;
    }
    
    return nil;
}

// Sets the title for a control, shifting the origin of the control itself to the left, and the origin of other controls to the left or right to accomodate any change in width.
-(void) setTitle: (NSString *) newTitle ofControl: (id) theControl
{
    NSRect oldRect = [theControl frame];
	
    if (   [theControl isEqual: onLaunchRadioButton]
        || [theControl isEqual: onSystemStartRadioButton]  ) {
        id cell = [theControl cellAtRow: 0 column: 0];
        [cell setTitle: newTitle];
    } else {
        [theControl setTitle: newTitle];
    }
    [theControl sizeToFit];
    
    NSRect newRect = [theControl frame];
    float widthChange = newRect.size.width - oldRect.size.width;
    NSRect oldPos;
    
    if (   [theControl isEqual: connectButton]                      // Shift the control itself left/right if necessary
        || [theControl isEqual: disconnectButton]  ) {
        oldPos = [theControl frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [theControl setFrame:oldPos];
    }
    
    if (  [theControl isEqual: editButton]  )  {             // If the Edit button changes, shift the Share button right/left
        oldPos = [shareButton frame];
        oldPos.origin.x = oldPos.origin.x + widthChange;
        [shareButton setFrame:oldPos];
    } else if (  [theControl isEqual: connectButton]  )  {          // If the Connect button changes, shift the Disconnect button left/right
        oldPos = [disconnectButton frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [disconnectButton setFrame:oldPos];
    } else if (  [theControl isEqual: autoConnectCheckbox]  ) {     // If the Auto Connect checkbox changes, shift the On Launch and On Computer Startup buttons left/right
        oldPos = [onLaunchRadioButton frame];
        oldPos.origin.x = oldPos.origin.x + widthChange;
        [onLaunchRadioButton setFrame:oldPos];
        oldPos = [onSystemStartRadioButton frame];
        oldPos.origin.x = oldPos.origin.x + widthChange;
        [onSystemStartRadioButton setFrame:oldPos];
    } else if (  [theControl isEqual: onLaunchRadioButton]  ) {     // If the On Launch checkbox changes, shift the On Computer Startup button left/right
        oldPos = [onSystemStartRadioButton frame];
        oldPos.origin.x = oldPos.origin.x + widthChange;
        [onSystemStartRadioButton setFrame:oldPos];
    } else if (  [theControl isEqual: onLaunchRadioButton]  ) {     // If the On Launch radio button changes, shift the On System Startup button left/right
        oldPos = [onSystemStartRadioButton frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [onSystemStartRadioButton setFrame:oldPos];
    }
}

// Invoked when the Details... window (logWindow) will close
- (void)windowWillClose:(NSNotification *)n
{
    VPNConnection * connection = [self selectedConnection];
    [connection stopMonitoringLogFiles];

    if ( [n object] == logWindow ) {
        // Stop and release the timer used to update the duration displays
        if (  [[NSApp delegate] showDurationsTimer]  ) {
            [[NSApp delegate] startOrStopDurationsTimer];
        }
        
        // Save the window's size and position in the preferences and save the TB version that saved them, BUT ONLY IF anything has changed
        NSString * mainFrame = [logWindow stringWithSavedFrame];
        NSString * leftFrame = nil;
        if (  [leftSplitView frame].size.width > (LEFT_NAV_AREA_MINIMAL_SIZE + 5.0)  ) {
            leftFrame = NSStringFromRect([leftSplitView frame]);
        }
        NSString * tbVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
        BOOL saveIt = TRUE;
        if (  [tbVersion isEqualToString: [gTbDefaults objectForKey:@"detailsWindowFrameVersion"]]    ) {
            if (   [mainFrame isEqualToString: [gTbDefaults objectForKey:@"detailsWindowFrame"]]
                && [leftFrame isEqualToString: [gTbDefaults objectForKey:@"detailsWindowLeftFrame"]]  ) {
                saveIt = FALSE;
            }
        }
        
        if (saveIt) {
            [gTbDefaults setObject: mainFrame forKey: @"detailsWindowFrame"];
            if (  leftFrame  ) {
                [gTbDefaults setObject: leftFrame forKey: @"detailsWindowLeftFrame"];
            }
            [gTbDefaults setObject: [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]
                            forKey: @"detailsWindowFrameVersion"];
            [gTbDefaults synchronize];
        }
        logWindowIsOpen = FALSE;
    }
}

-(IBAction) autoConnectPrefButtonWasClicked: (id) sender
{
	if([sender state]) {
		[self saveAutoLaunchCheckboxState:TRUE];
	} else {
		[self saveAutoLaunchCheckboxState:FALSE];
	}
    [self validateDetailsWindowControls];
}

- (IBAction)connectButtonWasClicked:(id)sender
{
    [[self selectedConnection] connect: sender userKnows: YES]; 
}

- (IBAction)disconnectButtonWasClicked:(id)sender
{
    [[self selectedConnection] disconnectAndWait: [NSNumber numberWithBool: YES] userKnows: YES];      
}

-(IBAction) editConfigButtonWasClicked: (id) sender
{
    VPNConnection * connection = [self selectedConnection];
	[[ConfigurationManager defaultManager] editConfigurationAtPath: [connection configPath] forConnection: connection];
}

-(IBAction) monitorConnectionPrefButtonWasClicked: (id) sender
{
	if([sender state]) {
		[self saveMonitorConnectionCheckboxState:TRUE];
	} else {
		[self saveMonitorConnectionCheckboxState:FALSE];
	}
    [self validateDetailsWindowControls];
}

-(IBAction) onLaunchRadioButtonWasClicked: (id) sender
{
	if([[sender cellAtRow: 0 column: 0] state]) {
		[self saveOnSystemStartRadioButtonState: FALSE forConnection: [self selectedConnection]];
	} else {
		[self saveOnSystemStartRadioButtonState: TRUE forConnection: [self selectedConnection]];
	}
    [self performSelectorOnMainThread:@selector(fixWhenConnectingButtons) withObject:nil waitUntilDone:NO];
}

-(IBAction) onSystemStartRadioButtonWasClicked: (id) sender
{
	if([[sender cellAtRow: 0 column: 0] state]) {
        // Warn user if .tblk and contains scripts that may not run if connecting when computer starts
        NSString * basePath = [[self selectedConnection] configPath];
        if (  [[basePath pathExtension] isEqualToString: @"tblk"]  ) {
            NSString * connectedPath      = [basePath stringByAppendingPathComponent: @"Contents/Resources/connected.sh"];
            NSString * reconnectingPath   = [basePath stringByAppendingPathComponent: @"Contents/Resources/reconnecting.sh"];
            NSString * postDisconnectPath = [basePath stringByAppendingPathComponent: @"Contents/Resources/post-disconnect.sh"];
            if (   [gFileMgr fileExistsAtPath: connectedPath]
                || [gFileMgr fileExistsAtPath: reconnectingPath]
                || [gFileMgr fileExistsAtPath: postDisconnectPath]  ) {
                int result = TBRunAlertPanelExtended(NSLocalizedString(@"Warning!", @"Window title"),
                                                     NSLocalizedString(@"This Tunnelblick VPN Configuration contains one or more event notification scripts which will not be executed unless Tunnelblick is running at the time the event happens.\n\nIf this configuration connects when the computer starts, these scripts may not be executed.\n\nDo you wish to have this configuration connect when the computer starts?", @"Window text"),
                                                     NSLocalizedString(@"Connect When Computer Starts", @"Button"),
                                                     NSLocalizedString(@"Cancel", @"Button"),
                                                     nil,
                                                     @"skipWarningAboutOnComputerStartAndTblkScripts",
                                                     NSLocalizedString(@"Do not ask again, always connect", @"Checkbox name"),
                                                     nil);
                if (  result == NSAlertAlternateReturn  ) {
                    [self performSelectorOnMainThread:@selector(fixWhenConnectingButtons) withObject:nil waitUntilDone:NO];
                    return;
                }
            }
        }
		[self saveOnSystemStartRadioButtonState: TRUE forConnection: [self selectedConnection]];
	} else {
		[self saveOnSystemStartRadioButtonState: FALSE forConnection: [self selectedConnection]];
	}
    [self performSelectorOnMainThread:@selector(fixWhenConnectingButtons) withObject:nil waitUntilDone:NO];
}

-(IBAction) shareConfigButtonWasClicked: (id) sender
{
    NSString * disableShareConfigKey = [[[self selectedConnection] displayName] stringByAppendingString:@"disableShareConfigurationButton"];
    if (  ! [gTbDefaults boolForKey: disableShareConfigKey]  ) {
        NSString * path = [[self selectedConnection] configPath];
        if (  [[path pathExtension] isEqualToString: @"tblk"]  ) {
            int result;
            if (  [path hasPrefix: gSharedPath]  ) {
                result = TBRunAlertPanel(NSLocalizedString(@"Make Configuration Private?", @"Window title"),
                                         NSLocalizedString(@"This configuration is shared with all other users of this computer.\n\nDo you wish to make it private, so that only you can use it?", @"Window title"),
                                         NSLocalizedString(@"Make configuration private", @"Button"),   // Default button
                                         NSLocalizedString(@"Cancel", @"Button"),                       // Alternate button
                                         nil);
                
            } else if (  [path hasPrefix: gPrivatePath]  ) {
                result = TBRunAlertPanel(NSLocalizedString(@"Share Configuration?", @"Window title"),
                                         NSLocalizedString(@"This configuration is private -- only you can use it.\n\nDo you wish to make it shared, so that all other users of this computer can use it?", @"Window title"),
                                         NSLocalizedString(@"Share configuration", @"Button"),  // Default button
                                         NSLocalizedString(@"Cancel", @"Button"),               // Alternate button
                                         nil);
            } else {
                // Deployed, so can't share or make private
                return;
            }
            
            if (  result == NSAlertDefaultReturn  ) {
                oldSelectedConnectionName = [[self selectedConnection] displayName];
                [[ConfigurationManager defaultManager] shareOrPrivatizeAtPath: path];
            }
        }
    }
}

-(void)saveMonitorConnectionCheckboxState:(BOOL)inBool
{
	VPNConnection* connection = [self selectedConnection];
	if(connection != nil) {
		NSString* key = [[connection displayName] stringByAppendingString: @"-notMonitoringConnection"];
        if (  [gTbDefaults boolForKey: key] != (! inBool)  ) {
            [gTbDefaults setObject: [NSNumber numberWithBool: ! inBool] forKey: key];
            [gTbDefaults synchronize];
            if (  ! [connection isDisconnected]  ) {
                TBRunAlertPanel(NSLocalizedString(@"Configuration Change", @"Window title"),
                                NSLocalizedString(@"The change will take effect the next time you connect.", @"Window text"),
                                nil, nil, nil);
            }
        }
    }
}

-(void)saveUseNameserverPopupButtonState:(unsigned)inValue
{
	VPNConnection* connection = [self selectedConnection];
	if(connection != nil) {
        // Look up new value for preference
        NSArray * setNameserverEntries = [modifyNameserverPopUpButtonArrayController content];
        NSDictionary * dictForEntry = [setNameserverEntries objectAtIndex: inValue];
        id obj = [dictForEntry objectForKey: @"value"];
        int i = 0;
        if (  obj  ) {
            if (  [obj respondsToSelector: @selector(intValue)]  ) {
                i = [obj intValue];
            } else {
                NSLog(@"Invalid value for 'modifyNameserverPopUpButtonArrayController' entry; using 'Do not set nameserver'");
            }
        }
        NSNumber * num = [NSNumber numberWithInt: i];
        
		NSString* key = [[connection displayName] stringByAppendingString: @"useDNS"];
        obj = [gTbDefaults objectForKey: key];
        BOOL saveIt = FALSE;
        if (  ! obj  ) {                                                // If no preference
            if (  inValue != 1  ) {                                     // and the new one is not 1
                saveIt = TRUE;                                          // Then save the new one
            }
        } else {
            if (   ( ! [[obj class] isSubclassOfClass: [num class]] )   // If preference is not a number
                || ( ! [num isEqualToNumber: obj] )  ) {                // Or is not equal to the new one
                saveIt = TRUE;                                          // Then save the new one
            }
        }
        
        if (  saveIt  ) {
            [gTbDefaults setObject: num forKey: key];
            [gTbDefaults synchronize];
            if (  ! [connection isDisconnected]  ) {
                TBRunAlertPanel(NSLocalizedString(@"Configuration Change", @"Window title"),
                                NSLocalizedString(@"The change will take effect the next time you connect.", @"Window text"),
                                nil, nil, nil);
            }
        }
    }
}

-(void)saveAutoLaunchCheckboxState:(BOOL)inBool
{
	VPNConnection* connection = [self selectedConnection];
	if(connection != nil) {
		NSString* autoConnectKey = [[connection displayName] stringByAppendingString: @"autoConnect"];
		[gTbDefaults setObject: [NSNumber numberWithBool: inBool] forKey: autoConnectKey];
		[gTbDefaults synchronize];
	}
}

-(void)saveOnSystemStartRadioButtonState: (BOOL) onSystemStart
                           forConnection: (VPNConnection *) connection
{
	if(connection != nil) {
        NSString * name = [connection displayName];
        BOOL coss = [connection checkConnectOnSystemStart: onSystemStart withAuth: gAuthorization];
		NSString* systemStartkey = [name stringByAppendingString: @"-onSystemStart"];
        if (  [gTbDefaults boolForKey: systemStartkey] != coss  ) {
            if (  [gTbDefaults canChangeValueForKey: systemStartkey]  ) {
                [gTbDefaults setBool: coss forKey: systemStartkey];
                [gTbDefaults synchronize];
                NSLog(@"The '%@' preference was changed to %@", systemStartkey, (coss ? @"TRUE" : @"FALSE") );
            } else {
                NSLog(@"The '%@' preference could not be changed to %@ because it is a forced preference", systemStartkey, (coss ? @"TRUE" : @"FALSE") );
            }
        }
        
        NSString * autoConnectKey = [name stringByAppendingString: @"autoConnect"];
        BOOL col = ( ! coss ) && [gTbDefaults boolForKey: autoConnectKey];
        
        [[onLaunchRadioButton      cellAtRow: 0 column: 0]  setState: (int) col];
        [[onSystemStartRadioButton cellAtRow: 0 column: 0]  setState: (int) coss];
	}
}

// We use this to get around a problem with our use of the "when Tunnelblick launches" and "when the computer starts" radio buttons.
// If the user clicks the button but then cancels, OS X changes the state of the button _after_ our WasClicked handler. So
// we set both buttons to the way they should be _after_ OS X makes that change.
-(void) fixWhenConnectingButtons
{
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        NSString* key = [[connection displayName] stringByAppendingString: @"-onSystemStart"];
        BOOL preferenceValue = [gTbDefaults boolForKey: key];
        [[onSystemStartRadioButton cellAtRow: 0 column: 0]  setState:   preferenceValue];
        [[onLaunchRadioButton      cellAtRow: 0 column: 0]  setState: ! preferenceValue];
        [self validateDetailsWindowControls];
    }
}

-(int) selectedModifyNameserverIndex
{
    return selectedModifyNameserverIndex;
}

-(void) setSelectedModifyNameserverIndex: (int) newValue
{
    // We duplicate this code in validateDetailsWindowControls but without calling itself
    if (  newValue != selectedModifyNameserverIndex  ) {
        selectedModifyNameserverIndex = newValue;
        [modifyNameserverPopUpButton selectItemAtIndex: newValue];
        [self saveUseNameserverPopupButtonState: (unsigned) newValue];
        [self validateDetailsWindowControls];   // The code in validateDetailsWindowControls DOES NOT do this
    }
}

-(int) selectedLeftNavListIndex
{
    return selectedLeftNavListIndex;
}

-(void) tableViewSelectionDidChange:(NSNotification *)notification
{
    [self performSelectorOnMainThread: @selector(selectedLeftNavListIndexChanged) withObject: nil waitUntilDone: NO];
}

-(void) selectedLeftNavListIndexChanged
{
    int n = [leftNavListView selectedRow];
    [self setSelectedLeftNavListIndex: n];
}

-(void) setSelectedLeftNavListIndex: (int) newValue
{
    if (  newValue != selectedLeftNavListIndex  ) {
        
        // Don't allow selection of a "folder" row, only of a "configuration" row
        while (  [[leftNavDisplayNames objectAtIndex: newValue] length] == 0) {
            ++newValue;
        }
        
        selectedLeftNavListIndex = newValue;
        [leftNavListView selectRowIndexes: [NSIndexSet indexSetWithIndex: newValue] byExtendingSelection: NO];
        NSString * label = [[leftNavList objectAtIndex: newValue] stringByTrimmingCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @" "]];
        [[tabView tabViewItemAtIndex:0] setLabel: label];
        
        [[[self selectedLogView] textStorage] setDelegate: nil];
        VPNConnection* newConnection = [self selectedConnection];
        NSTextView* logView = [self selectedLogView];
        [logView setEditable: NO];
        [[logView layoutManager] replaceTextStorage: [newConnection logStorage]];
        [logView scrollRangeToVisible: NSMakeRange([[logView string] length]-1, 0)];
        [[logView textStorage] setDelegate: self];
        [self setLogWindowTitle];
        [self validateDetailsWindowControls];
        [newConnection startMonitoringLogFiles];
    }
}

-(void) dealloc
{
    [onLaunchRadioButton release];
    [onSystemStartRadioButton release];
    [autoConnectCheckbox release];
    [connectButton release];
    [disconnectButton release];
    [editButton release];
    [logWindow release];
    [monitorConnnectionCheckbox release];
    [shareButton release];
    [tabView release];
    [modifyNameserverPopUpButton release];
    [splitView release];
    [leftSplitView release];
    [rightSplitView release];
    [leftNavListView release];
    [leftNavTableColumn release];    
    [modifyNameserverPopUpButtonArrayController release];
    [leftNavList release];
    [leftNavDisplayNames release];
    [oldSelectedConnectionName release];
    
    [super dealloc];
}

@end
