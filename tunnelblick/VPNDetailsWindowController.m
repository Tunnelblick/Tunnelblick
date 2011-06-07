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
#import "VPNDetailsWindowController.h"
#import "VPNConnection.h"
#import "MenuController.h"
#import "TBUserDefaults.h"
#import "ConfigurationManager.h"
#import "NSApplication+LoginItem.h"
#import "helper.h"

extern NSMutableArray       * gConfigDirs;
extern NSString             * gDeployPath;
extern NSString             * gPrivatePath;
extern NSString             * gSharedPath;
extern NSFileManager        * gFileMgr;
extern TBUserDefaults       * gTbDefaults;
extern AuthorizationRef       gAuthorization;


@interface VPNDetailsWindowController()  // Private methods

-(void)             copyOrMoveCredentialsFromDisplayName:   (NSString *)        fromDisplayName
                                                      to:   (NSString *)        toDisplayName
                                             moveNotCopy:   (BOOL)              moveNotCopy;

-(int)              firstDifferentComponent:                (NSArray *)         a
                                        and:                (NSArray *)         b;

-(NSString *)       indent:                                 (NSString *)        s
                        by:                                 (int)               n;

-(VPNConnection *)  selectedConnection;

-(void)             setLogWindowTitle;

-(void)             setTitle:                               (NSString *)        newTitle
                   ofControl:                               (id)                theControl;

-(void)             setupLeftNavigationToDisplayName:       (NSString *)        displayNameToSelect;

-(void)             updateConnectionStatusAndTime;

-(void)             validateDetailsWindowControls;

-(void)             validateWhenToConnect: (VPNConnection *) connection;


-(void) initializeStaticContent;
-(void) initializeSoundPopUpButtons;

-(void) setupSettingsFromPreferences;
-(void) setupSoundPopUpButton: (NSPopUpButton *)     button
              arrayController: (NSArrayController *) ac
                   preference: (NSString *)          preference
                    defaultIs: (NSString *)          defaultIs;

-(void) setupCheckbox: (NSButton *) checkbox
                  key: (NSString *) key
             inverted: (BOOL) inverted;

-(BOOL) changeBooleanPreference: (NSString *) key
                             to: (BOOL)       newValue
                       inverted: (BOOL)       inverted;

-(void) setSoundIndex: (NSInteger *) index
                   to: (NSInteger) newValue
           preference: (NSString *) preference;

-(NSInteger)        selectedWhenToConnectIndex;
-(void)             setSelectedWhenToConnectIndex:          (NSInteger)         newValue;

@end


@implementation VPNDetailsWindowController

-(id) init
{
    if (  ![super initWithWindowNibName:@"VPNDetailsWindow"]  ) {
        return nil;
    }
    
    previouslySelectedNameOnLeftNavList = nil;
    leftNavList = nil;
    leftNavDisplayNames = nil;
    selectedLeftNavListIndex = 0;
    settingsSheetWindowController = nil;
    authorization = 0;
    selectedWhenToConnectIndex = 0;
    sortedSounds = nil;
    doNotPlaySounds = FALSE;
    logWindowIsOpen = FALSE;
    
    return self;
}

-(void) dealloc
{
    [previouslySelectedNameOnLeftNavList release];
    [leftNavList                         release];
    [leftNavDisplayNames                 release];
    [settingsSheetWindowController       release];
    [sortedSounds                        release];
    
    [super dealloc];
}


- (void)windowDidResize:(NSNotification *)notification
{
    [whenToConnectPopUpButton sizeToFit];
    [setNameserverPopUpButton sizeToFit];
}


-(void) windowWillClose: (NSNotification *) n
{
    VPNConnection * connection = [self selectedConnection];
    [connection stopMonitoringLogFiles];
    
    if ( [n object] == logWindow ) {
        
        // Close the settings sheet
        [settingsSheetWindowController endSettingsSheet: self];
        
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


// Call this when a configuration was added or deleted
-(void) update
{
    [self setupLeftNavigationToDisplayName: previouslySelectedNameOnLeftNavList];
    
    NSString * newDisplayName = [[self selectedConnection] displayName];
    [settingsSheetWindowController setConfigurationName: newDisplayName];
}


-(void)updateNavigationLabels {
    [self updateConnectionStatusAndTime];
}


-(void) updateConnectionStatusAndTime
{
    VPNConnection* newConnection = [self selectedConnection];
    NSString * state = [newConnection state];
    NSString * localizedStatus = NSLocalizedString(state, @"Connection status");
    if (  [state isEqualToString: @"CONNECTED"]  ) {
        NSString * time = [newConnection connectTimeString];
        [configurationStatusTFC setTitle: [NSString stringWithFormat: @"%@%@",
                                           localizedStatus, time]];
    } else {
        [configurationStatusTFC setTitle: localizedStatus];
    }
    
    [settingsSheetWindowController updateConnectionStatusAndTime];
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
	VPNConnection* connection = [[[NSApp delegate] myVPNConnectionDictionary] objectForKey: [e nextObject]];
    if (  ! connection  ) {
        NSLog(@"Internal program error: openLogWindow: but there are no configurations");
        return;
    }
    
    [NSBundle loadNibNamed: @"VPNDetailsWindow" owner: self];
    
	[logWindow setDelegate:self];
    
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
    
    [self initializeStaticContent];
    
    [self setupLeftNavigationToDisplayName: nil];

    [logWindow display];
    [logWindow makeKeyAndOrderFront: self];
    [NSApp activateIgnoringOtherApps:YES];
    logWindowIsOpen = TRUE;
}

//**********************************************************************************************************************************
-(void) initializeStaticContent
{
    // Main window
    
    [self setTitle: NSLocalizedString(@"Connect"   , @"Button") ofControl: connectButton   ];
    [self setTitle: NSLocalizedString(@"Disconnect", @"Button") ofControl: disconnectButton];
    
    
    // Left split view -- list of configurations and configuration manipulation
    
    [[leftNavTableColumn headerCell] setTitle: NSLocalizedString(@"Configurations", @"Window text")];
    
    [renameConfigurationMenuItem          setTitle: NSLocalizedString(@"Rename Configuration..."                          , @"Menu Item")];
    [duplicateConfigurationMenuItem       setTitle: NSLocalizedString(@"Duplicate Configuration..."                       , @"Menu Item")];
    [editOpenVPNConfigurationFileMenuItem setTitle: NSLocalizedString(@"Edit OpenVPN Configuration File..."               , @"Menu Item")];
    [showOpenvpnLogMenuItem               setTitle: NSLocalizedString(@"Show OpenVPN Log in Finder"                       , @"Menu Item")];
    [removeCredentialsMenuItem            setTitle: NSLocalizedString(@"Delete Configuration's Credentials in Keychain...", @"Menu Item")];
    
    // editOpenVPNConfigurationFileMenuItem, makePrivateOrSharedMenuItem, and showOnTunnelblickMenuMenuItem are initialized in validateDetailsWindowControls
    

    // Right split view - Log tab
    
    [logTabViewItem setLabel: NSLocalizedString(@"Log", @"Window title")];
    
    [self setTitle: NSLocalizedString(@"Copy Log to Clipboard", @"Button") ofControl: copyLogButton   ];
    
    
    // Right split view - Settings tab
    
    [settingsTabViewItem setLabel: NSLocalizedString(@"Settings", @"Window title")];

    [whenToConnectTFC                       setTitle: NSLocalizedString(@"Connect:", @"Window text")];
    [whenToConnectManuallyMenuItem          setTitle: NSLocalizedString(@"Manually"                 , @"Button")];
    [whenToConnectTunnelblickLaunchMenuItem setTitle: NSLocalizedString(@"When Tunnelblick launches", @"Button")];
    [whenToConnectOnComputerStartMenuItem   setTitle: NSLocalizedString(@"When computer starts"     , @"Button")];
    [whenToConnectPopUpButton sizeToFit];
    selectedWhenToConnectIndex = NSNotFound;   // Force a change when first set
    
    [setNameserverTFC setTitle: NSLocalizedString(@"Set DNS/WINS:", @"Window text")];
    // setNameserverPopUpButton is initialized in setupSettingsFromPreferences
    selectedSetNameserverIndex = NSNotFound;   // Force a change when first set
    
    [monitorNetworkForChangesCheckbox setTitle: NSLocalizedString(@"Monitor network settings", @"Checkbox name")];
    
    [alertSoundsBox setTitle: NSLocalizedString(@"Alert sounds", @"Window title")];
    
    [connectionAlertSoundTFC    setTitle: NSLocalizedString(@"Connection:", @"Window text")              ];
    [disconnectionAlertSoundTFC setTitle: NSLocalizedString(@"Unexpected disconnection:", @"Window text")];
    [self initializeSoundPopUpButtons];
    selectedSoundOnConnectIndex     = NSNotFound;
    selectedSoundOnDisconnectIndex  = NSNotFound;    
    
    [self setTitle: NSLocalizedString(@"Advanced..." , @"Button") ofControl: advancedButton  ];
}


-(void) initializeSoundPopUpButtons
{
    // Get all the names of sounds
    NSMutableArray * sounds = [[[NSMutableArray alloc] initWithCapacity: 30] autorelease];
    NSArray * soundDirs = [NSArray arrayWithObjects:
                           [NSHomeDirectory() stringByAppendingString: @"/Library/Sounds"],
                           @"/Library/Sounds",
                           @"/Network/Library/Sounds",
                           @"/System/Library/Sounds",
                           nil];
    NSArray * soundTypes = [NSArray arrayWithObjects: @"aiff", @"wav", nil];
    NSEnumerator * soundDirEnum = [soundDirs objectEnumerator];
    NSString * folder;
    NSString * file;
    while (  folder = [soundDirEnum nextObject]  ) {
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: folder];
        while (  file = [dirEnum nextObject]  ) {
            [dirEnum skipDescendents];
            if (  [soundTypes containsObject: [file pathExtension]]  ) {
                NSString * soundName = [file stringByDeletingPathExtension];
                if (  ! [sounds containsObject: soundName]  ) {
                    [sounds addObject: soundName];
                }
            }
        }
    }
    
    // Sort them
    sortedSounds = [[sounds sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)] retain];
    
    // Create an array of dictionaries of them
    NSMutableArray * soundsDictionaryArray = [NSMutableArray arrayWithCapacity: [sortedSounds count]];
    
    [soundsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys: 
                                       NSLocalizedString(@"None", @"Button"), @"name", 
                                       @"None", @"value", nil]];
    
    int i;
    for (  i=0; i<[sortedSounds count]; i++  ) {
        [soundsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys: 
                                           [sortedSounds objectAtIndex: i], @"name", 
                                           [sortedSounds objectAtIndex: i], @"value", nil]];
    }
    
    [soundOnConnectArrayController    setContent: soundsDictionaryArray];
    [soundOnDisconnectArrayController setContent: soundsDictionaryArray];
}


//**********************************************************************************************************************************
-(void) setupSettingsFromPreferences
{
    VPNConnection * connection = [self selectedConnection];
    
    if (  ! connection  ) {
        return;
    }
    
    
    // Window
    
	[self setLogWindowTitle];
    
    
    // Right split view
    
    // The configuration's name was put in configurationNameTFC by setupLeftNavigationToDisplayName, above
    
    [self updateConnectionStatusAndTime];
    
    // Right split view - Log tab
    
    NSTextStorage * store = [connection logStorage];
    [[logView layoutManager] replaceTextStorage: store];
    
    [self indicateNotWaiting];
    
    
    // Right split view - Settings tab
    
    [self validateWhenToConnect: [self selectedConnection]];
    
    // Set up setNameserverPopUpButton with localized content that varies with the connection
    NSInteger ix = 0;
    NSArray * content = [connection modifyNameserverOptionList];
    [setNameserverArrayController setContent: content];
    [setNameserverPopUpButton sizeToFit];
    
    // Select the appropriate entry
    NSString * key = [[[self selectedConnection] displayName] stringByAppendingString: @"useDNS"];
    id obj = [gTbDefaults objectForKey: key];
    if (  obj != nil  ) {
        if (  [obj respondsToSelector: @selector(intValue)]  ) {
            ix = (NSInteger) [obj intValue];
            if (  ix >= [[setNameserverArrayController content] count]  ) {
                NSLog(@"%@ preference ignored: value %d too large", key, ix);
                ix = 0;
            }
        } else {
            NSLog(@"%@ preference ignored: invalid value; must be a number", key);
        }
    } else {
        // Default is "Set namserver"
        ix = 1;
    }
    
    [setNameserverPopUpButton selectItemAtIndex: ix];
    [self setSelectedSetNameserverIndex: ix];
    [setNameserverPopUpButton setEnabled: [gTbDefaults canChangeValueForKey: key]];
    
    if (  [self forceDisableOfNetworkMonitoring]  ) {
        [monitorNetworkForChangesCheckbox setState: NSOffState];
        [monitorNetworkForChangesCheckbox setEnabled: NO];
    } else {
        [self setupCheckbox: monitorNetworkForChangesCheckbox
                        key: @"-notMonitoringConnection"
                   inverted: YES];
        [monitorNetworkForChangesCheckbox setEnabled: YES];
    }
    
    [self setupSoundPopUpButton: soundOnConnectPopUpButton
                arrayController: soundOnConnectArrayController
                     preference: @"-tunnelUpSoundName"
                      defaultIs: @"Glass"];
    
    
    [self setupSoundPopUpButton: soundOnDisconnectPopUpButton
                arrayController: soundOnDisconnectArrayController
                     preference: @"-tunnelDownSoundName"
                      defaultIs: @"Basso"];
    
    // Set up a timer to update connection times
    [[NSApp delegate] startOrStopDurationsTimer];
    
	[self validateDetailsWindowControls];   // Set windows enabled/disabled
}

-(BOOL) forceDisableOfNetworkMonitoring
{
    NSArray * content = [setNameserverArrayController content];
    NSInteger ix = [self selectedSetNameserverIndex];
    if (   ([content count] < 4)
        || (ix > 2)
        || (ix == 0)  ) {
        return TRUE;
    } else {
        return FALSE;
    }
}


-(void) setupLeftNavigationToDisplayName: (NSString *) displayNameToSelect
{
    int leftNavIndexToSelect = NSNotFound;
    
    [leftNavList         release];
    [leftNavDisplayNames release];
    leftNavList         = [[NSMutableArray alloc] initWithCapacity: [[[NSApp delegate] myVPNConnectionDictionary] count]];
    leftNavDisplayNames = [[NSMutableArray alloc] initWithCapacity: [[[NSApp delegate] myVPNConnectionDictionary] count]];
    int currentLeftNavIndex = 0;
    NSMutableArray * currentFolders = [NSMutableArray array]; // Components of folder enclosing most-recent leftNavList/leftNavDisplayNames entry
    NSArray * allConfigsSorted = [[[[NSApp delegate] myVPNConnectionDictionary] allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
    
    // If the configuration we want to select is gone, don't try to select it
    if (  displayNameToSelect  ) {
        if (  ! [allConfigsSorted containsObject: displayNameToSelect]  ) {
            displayNameToSelect = nil;
        }
    }
    
    NSEnumerator* configEnum = [allConfigsSorted objectEnumerator];
    VPNConnection * connection;
    while (connection = [[[NSApp delegate] myVPNConnectionDictionary] objectForKey: [configEnum nextObject]]) {
        NSString * dispNm = [connection displayName];
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
            ++currentLeftNavIndex;
        }
        
        // Add a "configuration" line
        [leftNavDisplayNames addObject: [NSString stringWithString: [connection displayName]]];
        [leftNavList         addObject: [NSString stringWithString: 
                                         [self indent: [currentConfig lastObject] by: [currentConfig count]-1]]];
        
        if (  displayNameToSelect  ) {
            if (  [displayNameToSelect isEqualToString: [connection displayName]]  ) {
                leftNavIndexToSelect = currentLeftNavIndex;
            }
        } else if (   ( leftNavIndexToSelect == NSNotFound )
                   && ( ! [connection isDisconnected] )  ) {
            leftNavIndexToSelect = currentLeftNavIndex;
        }
        ++currentLeftNavIndex;
    }

    [leftNavTableView reloadData];
    
    // If there are any entries in the list
    // Select the entry that was selected previously, or the first that was not disconnected, or the first
    if (  currentLeftNavIndex > 0  ) {
        if (  leftNavIndexToSelect == NSNotFound  ) {
            if (  [leftNavList count]  ) {
                leftNavIndexToSelect = 0;
            }
        }
        if (  leftNavIndexToSelect != NSNotFound  ) {
            selectedLeftNavListIndex = NSNotFound;  // Force a change
            [self setSelectedLeftNavListIndex: leftNavIndexToSelect];
            [leftNavTableView scrollRowToVisible: leftNavIndexToSelect];
        }
    }
}

// Set a checkbox from preferences
-(void) setupCheckbox: (NSButton *) checkbox
                  key: (NSString *) key
             inverted: (BOOL) inverted
{
    NSString * actualKey = [[[self selectedConnection] displayName] stringByAppendingString: key];
    BOOL state = [gTbDefaults boolForKey: actualKey];
    if (  inverted  ) {
        state = ! state;
    }
    if (  state  ) {
        [checkbox setState: NSOnState];
    } else {
        [checkbox setState: NSOffState];
    }
    
    BOOL enable = [gTbDefaults canChangeValueForKey: actualKey];
    [checkbox setEnabled: enable];
}


//  Set a sound popup button from preferences
-(void) setupSoundPopUpButton: (NSPopUpButton *)     button
              arrayController: (NSArrayController *) ac
                   preference: (NSString *)          preference
                    defaultIs: (NSString *)          defaultIs
{
    NSUInteger ix = NSNotFound;
    NSString * key = [[[self selectedConnection] displayName] stringByAppendingString: preference];
    NSString * soundName = [gTbDefaults objectForKey: key];
    if (  soundName  ) {
        if (  ! [soundName isEqualToString: @"None"]  ) {
            ix = [sortedSounds indexOfObject: soundName];
            if (  ix == NSNotFound  ) {
                if (  [sortedSounds count] > 0  ) {
                    NSString * substituteSoundName = [sortedSounds objectAtIndex: 0];
                    NSLog(@"Preference '%@' '%@' is not available, using sound '%@'", key, soundName, substituteSoundName);
                    [button selectItemAtIndex: 0];
                } else {
                    NSLog(@"Preference '%@' '%@' ignored, no sounds are available", key, soundName);
                }
            } else {
                ix = ix + 1;
            }
        }
        
    } else {
        ix = [sortedSounds indexOfObject: defaultIs];
        if (  ix == NSNotFound  ) {
            if (  [sortedSounds count] > 0  ) {
                NSString * substituteSoundName = [sortedSounds objectAtIndex: 0];
                NSLog(@"Default sound '%@' for preference '%@' is not available, using sound '%@'", defaultIs, key, substituteSoundName);
                [button selectItemAtIndex: 0];
            } else {
                NSLog(@"Ignoring '%@' preference because no sounds are available", key);
            }
        } else {
            ix = ix + 1;
        }
    }
    
    if (  ix == NSNotFound  ) {
        ix = 0;
    }
    
    [button selectItemAtIndex: ix];
    
    //******************************************************************************
    // Don't play sounds because we are just setting the button from the preferences
    BOOL oldDoNotPlaySounds = doNotPlaySounds;
    doNotPlaySounds = TRUE;
    
    if (  button == soundOnConnectPopUpButton) {
        [self setSelectedSoundOnConnectIndex: ix];
    } else {
        [self setSelectedSoundOnDisconnectIndex: ix];
    }
    
    doNotPlaySounds = oldDoNotPlaySounds;
    //******************************************************************************
    
    BOOL enable = [gTbDefaults canChangeValueForKey: key];
    [button setEnabled: enable];
}


-(int)numberOfRowsInTableView:(NSTableView *)aTableView
{
    if (  aTableView == leftNavTableView  ) {
        int n = [leftNavList count];
        return n;
    }
    
    return 0;
}

-(id) tableView:(NSTableView *) aTableView objectValueForTableColumn:(NSTableColumn *) aTableColumn row:(int) rowIndex
{
    if (  aTableView == leftNavTableView  ) {
        NSString * s = [leftNavList objectAtIndex: rowIndex];
        return s;
    }
    
    return nil;
}

-(void) indicateWaiting
{
    [progressIndicator startAnimation: self];
    [progressIndicator setHidden: NO];
}


-(void) indicateNotWaiting
{
    [progressIndicator stopAnimation: self];
    [progressIndicator setHidden: YES];
}


-(void) hookedUpOrStartedConnection: (VPNConnection *) connection
{
    if (   connection
        && ( connection == [self selectedConnection] )  ) {
        [connection startMonitoringLogFiles];
    }
}


-(void) validateWhenConnectingForConnection: (VPNConnection *) connection
{
    if (  connection  ) {
        [self validateWhenToConnect: connection];
    }
}


-(void) validateConnectAndDisconnectButtonsForConnection: (VPNConnection *) connection
{
    if (  ! connection  )  {
        [connectButton    setEnabled: NO];
        [disconnectButton setEnabled: NO];
        return;
    }
        
    if ( connection != [self selectedConnection]  ) {
        return;
    }
    
    NSString * displayName = [connection displayName];
    NSString * disableConnectButtonKey    = [displayName stringByAppendingString: @"-disableConnectButton"];
    NSString * disableDisconnectButtonKey = [displayName stringByAppendingString: @"-disableDisconnectButton"];
    BOOL disconnected = [connection isDisconnected];
    [connectButton    setEnabled: (   disconnected
                                   && ( ! [gTbDefaults boolForKey: disableConnectButtonKey] )  )];
    [disconnectButton setEnabled: (   ( ! disconnected )
                                   && ( ! [gTbDefaults boolForKey: disableDisconnectButtonKey] )  )];
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


- (void) setLogWindowTitle
{
    VPNConnection * connection = [self selectedConnection];
    NSString * configName = [connection displayName];
    NSString * programName;
    if (  [configName isEqualToString: @"Tunnelblick"]  ) {
        programName = @"";
    } else {
        programName = [NSString stringWithFormat: @" - Tunnelblick"];
    }
    NSString * location = [connection displayLocation];
    [logWindow setTitle: [NSString stringWithFormat: @"%@%@%@", configName, location, programName]];
}


- (void) textStorageDidProcessEditing: (NSNotification*) aNotification
{
    NSNotification *notification = [NSNotification notificationWithName: @"LogDidChange" 
                                                                 object: logView];
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


- (VPNConnection*) selectedConnection
// Returns the connection associated with the currently selected connection or nil on error.
{
    if (  selectedLeftNavListIndex >= 0  ) {
        if (  selectedLeftNavListIndex < [leftNavDisplayNames count]  ) {
            NSString * dispNm = [leftNavDisplayNames objectAtIndex: selectedLeftNavListIndex];
            if (  dispNm != nil) {
                VPNConnection* connection = [[[NSApp delegate] myVPNConnectionDictionary] objectForKey: dispNm];
                if (  connection  ) {
                    return connection;
                }
                NSArray *allConnections = [[[NSApp delegate] myVPNConnectionDictionary] allValues];
                if (  [allConnections count]  ) {
                    return [allConnections objectAtIndex:0];
                }
                else return nil;
            }
        }
    }
        
    return nil;
}

// Sets the title for a control, shifting the origin of the control itself to the left, and the origin of other controls to the left or right to accomodate any change in width.
-(void) setTitle: (NSString *) newTitle ofControl: (id) theControl
{
    NSRect oldRect = [theControl frame];
    
    [theControl setTitle: newTitle];
    [theControl sizeToFit];
    
    NSRect newRect = [theControl frame];
    float widthChange = newRect.size.width - oldRect.size.width;
    NSRect oldPos;
    
    if (   [theControl isEqual: connectButton]              // Shift the control itself left/right if necessary
        || [theControl isEqual: disconnectButton]
        || [theControl isEqual: copyLogButton]
        || [theControl isEqual: advancedButton]  ) {
        oldPos = [theControl frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [theControl setFrame:oldPos];
    }
    
    if (  [theControl isEqual: connectButton]  )  {          // If the Connect button changes, shift the Disconnect button left/right
        oldPos = [disconnectButton frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [disconnectButton setFrame:oldPos];
    }
}


-(void) validateDetailsWindowControls
{
    VPNConnection * connection = [self selectedConnection];
    
    [self validateConnectAndDisconnectButtonsForConnection: connection];
    
    if (  connection  ) {
        
        // Left split view
        
        [renameConfigurationMenuItem          setEnabled: YES];
        [duplicateConfigurationMenuItem       setEnabled: YES];

        NSString * configurationPath = [connection configPath];
        if (  [configurationPath hasPrefix: gSharedPath]  ) {
            [makePrivateOrSharedMenuItem setTitle: NSLocalizedString(@"Make Configuration Private..."  , @"Menu Item")];
            [makePrivateOrSharedMenuItem setEnabled: YES];
        } else if (  [configurationPath hasPrefix: gPrivatePath]  ) {
            [makePrivateOrSharedMenuItem setTitle: NSLocalizedString(@"Make Configuration Shared..."  , @"Menu Item")];
            [makePrivateOrSharedMenuItem setEnabled: YES];
        } else {
            [makePrivateOrSharedMenuItem setTitle: NSLocalizedString(@"Make Configuration Shared..."  , @"Menu Item")];
            [makePrivateOrSharedMenuItem setEnabled: NO];
        }
        
        if (  [[ConfigurationManager defaultManager] userCanEditConfiguration: [connection configPath]]  ) {
            [editOpenVPNConfigurationFileMenuItem setTitle: NSLocalizedString(@"Edit OpenVPN Configuration File...", @"Menu Item")];
        } else {
            [editOpenVPNConfigurationFileMenuItem setTitle: NSLocalizedString(@"Examine OpenVPN Configuration File...", @"Menu Item")];
        }
        [editOpenVPNConfigurationFileMenuItem setEnabled: YES];
        
        NSString * key = [[connection displayName] stringByAppendingString: @"-doNotShowOnTunnelblickMenu"];
        if (  [gTbDefaults boolForKey: key]  ) {
            [showOnTunnelblickMenuMenuItem setTitle: NSLocalizedString(@"Show Configuration on Tunnelblick Menu"  , @"Menu Item")];
        } else {
            [showOnTunnelblickMenuMenuItem setTitle: NSLocalizedString(@"Hide Configuration on Tunnelblick Menu"  , @"Menu Item")];
        }

        [editOpenVPNConfigurationFileMenuItem setEnabled: YES];
        [showOpenvpnLogMenuItem               setEnabled: YES];
        [removeCredentialsMenuItem            setEnabled: YES];
        
        
        // right split view
        
        // Right split view - log tab

        [copyLogButton                        setEnabled: YES];

        
        // Right split view - settings tab
        
        [advancedButton                       setEnabled: YES];
        
        [self validateWhenToConnect: [self selectedConnection]];
        
    } else {
        [makePrivateOrSharedMenuItem          setTitle: NSLocalizedString(@"Make Configuration Shared..."  , @"Menu Item")];
        [showOnTunnelblickMenuMenuItem        setTitle: NSLocalizedString(@"Hide Configuration on Tunnelblick Menu"  , @"Menu Item")];
        [editOpenVPNConfigurationFileMenuItem setTitle: NSLocalizedString(@"Edit OpenVPN configuration file...", @"Menu Item")];

        [connectButton                        setEnabled: NO];
        [disconnectButton                     setEnabled: NO];
        [advancedButton                       setEnabled: NO];
        [copyLogButton                        setEnabled: NO];
        
        [renameConfigurationMenuItem          setEnabled: NO];
        [duplicateConfigurationMenuItem       setEnabled: NO];        
        [makePrivateOrSharedMenuItem          setEnabled: NO];
        [showOnTunnelblickMenuMenuItem        setEnabled: NO];
        [editOpenVPNConfigurationFileMenuItem setEnabled: NO];
        [showOpenvpnLogMenuItem               setEnabled: NO];
        [removeCredentialsMenuItem            setEnabled: NO];        
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
    int n = [leftNavTableView selectedRow];
    [self setSelectedLeftNavListIndex: n];
}

-(void) setSelectedLeftNavListIndex: (int) newValue
{
    if (  newValue != selectedLeftNavListIndex  ) {
        
        // Don't allow selection of a "folder" row, only of a "configuration" row
        while (  [[leftNavDisplayNames objectAtIndex: newValue] length] == 0) {
            ++newValue;
        }
        
        if (  selectedLeftNavListIndex != NSNotFound  ) {
            VPNConnection * connection = [self selectedConnection];
            [connection stopMonitoringLogFiles];
        }
        
        selectedLeftNavListIndex = newValue;
        [leftNavTableView selectRowIndexes: [NSIndexSet indexSetWithIndex: newValue] byExtendingSelection: NO];
        
        VPNConnection* newConnection = [self selectedConnection];
        NSString * dispNm = [newConnection displayName];
        [configurationNameTFC setTitle: [NSString stringWithFormat: @"%@:", dispNm]];
        
        NSString * status = NSLocalizedString([newConnection state], "Connection status");
        [configurationStatusTFC setTitle: status];
        
        [[logView textStorage] setDelegate: nil];
        [logView setEditable: NO];
        [[logView layoutManager] replaceTextStorage: [newConnection logStorage]];
        [logView scrollRangeToVisible: NSMakeRange([[logView string] length]-1, 0)];
        [[logView textStorage] setDelegate: self];

        
        [self setupSettingsFromPreferences];
        [self validateDetailsWindowControls];
        [newConnection startMonitoringLogFiles];
        
        [previouslySelectedNameOnLeftNavList release];
        previouslySelectedNameOnLeftNavList = [dispNm retain];
        
        [settingsSheetWindowController setConfigurationName: dispNm];
    }
}

// Makes sure that
//       * The autoConnect and -onSystemStart preferences
//       * The configuration location (private/shared/deployed)
//       * Any launchd .plist for the configuration
// are all consistent.
// Does this by creating/deleting a launchd .plist if it can (i.e., if the user authorizes it)
// Otherwise may modify the preferences to reflect the existence of the launchd .plist
-(void) validateWhenToConnect: (VPNConnection *) connection
{
    if (  ! connection  ) {
        return;
    }
    
    NSString * configurationPath = [connection configPath];
    NSString * displayName = [connection displayName];
    
    BOOL enableWhenComputerStarts = ! [configurationPath hasPrefix: gPrivatePath];
    
    NSString * autoConnectKey = [displayName stringByAppendingString: @"autoConnect"];
    BOOL autoConnect   = [gTbDefaults boolForKey: autoConnectKey];
    NSString * ossKey = [displayName stringByAppendingString: @"-onSystemStart"];
    BOOL onSystemStart = [gTbDefaults boolForKey: ossKey];
    
    BOOL launchdPlistWillConnectOnSystemStart = [connection launchdPlistWillConnectOnSystemStart];
    
    NSInteger ix = NSNotFound;
    
    //Keep track of what we've done for an alert to the user
    BOOL fixedPreferences       = FALSE;
    BOOL failedToFixPreferences = FALSE;
    BOOL fixedPlist             = FALSE;
    BOOL cancelledFixPlist      = FALSE;
    
    if (  autoConnect && onSystemStart  ) {
        if (  enableWhenComputerStarts  ) {
            if (  launchdPlistWillConnectOnSystemStart  ) {
                // All is OK -- prefs say to connect when system starts and launchd .plist agrees and it isn't a private configuration
                ix = 2;
            } else {
                // No launchd .plist -- try to create one
                if (  [connection checkConnectOnSystemStart: TRUE withAuth: nil]  ) {
                    // Made it connect when computer starts
                    fixedPlist = TRUE;
                    ix = 2;
                } else {
                    // User cancelled attempt to make it connect when computer starts
                    cancelledFixPlist = TRUE;
                    NSLog(@"Preferences for '%@' say it should connect when the computer starts but it does not have a launchd .plist and the user did not authorize creating a .plist. Attempting to repair preferences...", displayName);
                    [gTbDefaults setBool: FALSE forKey: autoConnectKey];
                    if (  ! [gTbDefaults boolForKey: autoConnectKey]  ) {
                        NSLog(@"Succesfully set '%@' preference to FALSE", autoConnectKey);
                        fixedPreferences = TRUE;
                    } else {
                        NSLog(@"Unable to set '%@' preference to FALSE", autoConnectKey);
                        failedToFixPreferences = TRUE;
                    }
                    [gTbDefaults setBool: FALSE forKey: ossKey];
                    if (  ! [gTbDefaults boolForKey: ossKey]  ) {
                        NSLog(@"Succesfully set '%@' preference to FALSE", ossKey);
                        fixedPreferences = TRUE;
                    } else {
                        NSLog(@"Unable to set '%@' preference to FALSE", ossKey);
                        failedToFixPreferences = TRUE;
                    }
                    ix = 0;  // It IS going to start when computer starts, so show that to user
                }
            }
        } else {
            // Private configuration
            if (  ! launchdPlistWillConnectOnSystemStart  ) {
                // Prefs, but not launchd, says will connnect on system start but it is a private configuration
                NSLog(@"Preferences for '%@' say it should connect when the computer starts but it is a private configuration. Attempting to repair preferences...", displayName);
                [gTbDefaults setBool: FALSE forKey: autoConnectKey];
                if (  ! [gTbDefaults boolForKey: autoConnectKey]  ) {
                    NSLog(@"Succesfully set '%@' preference to FALSE", autoConnectKey);
                    fixedPreferences = TRUE;
                } else {
                    NSLog(@"Unable to set '%@' preference to FALSE", autoConnectKey);
                    failedToFixPreferences = TRUE;
                }
                [gTbDefaults setBool: FALSE forKey: ossKey];
                if (  ! [gTbDefaults boolForKey: ossKey]  ) {
                    NSLog(@"Succesfully set '%@' preference to FALSE", ossKey);
                    fixedPreferences = TRUE;
                } else {
                    NSLog(@"Unable to set '%@' preference to FALSE", ossKey);
                    failedToFixPreferences = TRUE;
                }
                ix = 0;
            } else {
                // Prefs and launchd says connect on user start but private configuration, so can't. Try to remove the launchd .plist
                if (  [connection checkConnectOnSystemStart: FALSE withAuth: nil]  ) {
                    // User cancelled attempt to make it NOT connect when computer starts
                    cancelledFixPlist = TRUE;
                    NSLog(@"Preferences for '%@' say it should connect when the computer starts and a launchd .plist exists for that, but it is a private configuration. User cancelled attempt to repair.", displayName);
                    ix = 2;
                } else {
                    NSLog(@"Preferences for '%@' say it should connect when the computer starts and a launchd .plist exists for that, but it is a private configuration. The launchd .plist has been removed. Attempting to repair preferences...", displayName);
                    [gTbDefaults setBool: FALSE forKey: autoConnectKey];
                    if (  ! [gTbDefaults boolForKey: autoConnectKey]  ) {
                        NSLog(@"Succesfully set '%@' preference to FALSE", autoConnectKey);
                        fixedPreferences = TRUE;
                    } else {
                        NSLog(@"Unable to set '%@' preference to FALSE", autoConnectKey);
                        failedToFixPreferences = TRUE;
                    }
                    [gTbDefaults setBool: FALSE forKey: ossKey];
                    if (  ! [gTbDefaults boolForKey: ossKey]  ) {
                        NSLog(@"Succesfully set '%@' preference to FALSE", ossKey);
                        fixedPreferences = TRUE;
                    } else {
                        NSLog(@"Unable to set '%@' preference to FALSE", ossKey);
                        failedToFixPreferences = TRUE;
                    }
                    ix = 0;
                }
            }
        }
    } else {
        // Manual or when Tunnelblick is launched
        if (  launchdPlistWillConnectOnSystemStart  ) {
            // launchd .plist exists but prefs are not connect when computer starts. Attempt to remove .plist
            if (  [connection checkConnectOnSystemStart: FALSE withAuth: nil]  ) {
                // User cancelled attempt to make it NOT connect when computer starts
                cancelledFixPlist = TRUE;
                NSLog(@"Preferences for '%@' say it should NOT connect when the computer starts but a launchd .plist exists for that and the user cancelled an attempt to remove the .plist. Attempting to repair preferences.", displayName);
                if (  ! [gTbDefaults boolForKey: autoConnectKey]  ) {
                    [gTbDefaults setBool: TRUE forKey: autoConnectKey];
                    if (  [gTbDefaults boolForKey: autoConnectKey]  ) {
                        NSLog(@"Succesfully set '%@' preference to TRUE", autoConnectKey);
                        fixedPreferences = TRUE;
                    } else {
                        NSLog(@"Unable to set '%@' preference to TRUE", autoConnectKey);
                        failedToFixPreferences = TRUE;
                    }
                }
                if (  ! [gTbDefaults boolForKey: ossKey]  ) {
                    [gTbDefaults setBool: TRUE forKey: ossKey];
                    if (  [gTbDefaults boolForKey: ossKey]  ) {
                        NSLog(@"Succesfully set '%@' preference to TRUE", ossKey);
                        fixedPreferences = TRUE;
                    } else {
                        NSLog(@"Unable to set '%@' preference to TRUE", ossKey);
                        failedToFixPreferences = TRUE;
                    }
                }
                ix = 2;
            } else {
                NSLog(@"Preferences for '%@' say it should NOT connect when the computer starts and a launchd .plist existed but has been removed.", displayName);
            }
        }
    }
    
    if (  ix == NSNotFound  ) {
        ix = 0;
        if (  [gTbDefaults boolForKey: autoConnectKey]  ) {
            if (  [gTbDefaults boolForKey: ossKey]  ) {
                ix = 2;
            } else {
                ix = 1;
            }
        }
    }
    
    if (  failedToFixPreferences  ) {
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                        [NSString stringWithFormat: 
                         NSLocalizedString(@"Tunnelblick failed to repair problems with preferences for '%@'. Details are in the Console Log", @"Window text"),
                         displayName],
                        nil, nil, nil);
    }
    if (  fixedPreferences || cancelledFixPlist || fixedPlist) {
        ; // Avoid analyzer warnings about unused variables
    }
    
    [whenToConnectPopUpButton selectItemAtIndex: ix];
    [whenToConnectOnComputerStartMenuItem setEnabled: enableWhenComputerStarts];
    
    BOOL enable = (   [gTbDefaults canChangeValueForKey: autoConnectKey]
                   && [gTbDefaults canChangeValueForKey: ossKey]          );
    [whenToConnectPopUpButton setEnabled: enable];
}


// User Interface

// Window

-(IBAction) connectButtonWasClicked: (id) sender
{
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        [connection connect: sender userKnows: YES]; 
    } else {
        NSLog(@"connectButtonWasClicked but no configuration selected");
    }
}


-(IBAction) disconnectButtonWasClicked: (id) sender
{
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        [connection disconnectAndWait: [NSNumber numberWithBool: YES] userKnows: YES];      
    } else {
        NSLog(@"disconnectButtonWasClicked but no configuration selected");
    }
}


-(IBAction) generalHelpButtonWasClicked: (id) sender
{
    OSStatus err;
    if (err = MyGotoHelpPage(CFSTR("vpn-details.html"), NULL)  ) {
        NSLog(@"Error %d from MyGotoHelpPage()", err);
    }
}


// Left side -- navigation and configuration manipulation

-(IBAction) addConfigurationButtonWasClicked: (id) sender
{
    [[ConfigurationManager defaultManager] addConfigurationGuide];
}


-(IBAction) removeConfigurationButtonWasClicked: (id) sender
{
    VPNConnection * connection = [self selectedConnection];
    
    if (  ! connection  ) {
        NSLog(@"removeConfigurationButtonWasClicked but no configuration selected");
        return;
    }
    
    
    NSString * displayName = [connection displayName];
    NSString * autoConnectKey = [displayName stringByAppendingString: @"autoConnect"];
    NSString * onSystemStartKey = [displayName stringByAppendingString: @"-onSystemStart"];
    if (   [gTbDefaults boolForKey: autoConnectKey]
        && [gTbDefaults boolForKey: onSystemStartKey]  ) {
        TBRunAlertPanel(@"Tunnelblick",
                        NSLocalizedString(@"You may not delete a configuration which is set to start when the computer starts.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
    if (  ! [connection isDisconnected]  ) {
        TBRunAlertPanel(NSLocalizedString(@"Active connection", @"Window title"),
                        NSLocalizedString(@"You may not delete a configuration unless it is disconnected.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
    NSString * configurationPath = [connection configPath];
    
    if (  [configurationPath hasPrefix: gDeployPath]  ) {
        TBRunAlertPanel(@"Tunnelblick",
                        NSLocalizedString(@"You may not delete a Deployed configuration.", @"Window text"),
                        nil, nil, nil);
        return;
    }
        
    NSString * notDeletingOtherFilesMsg;
    NSString * ext = [configurationPath pathExtension];
    if (  [ext isEqualToString: @"tblk"]  ) {
        notDeletingOtherFilesMsg = @"";
    } else {
        notDeletingOtherFilesMsg = NSLocalizedString(@"\n\n Note: Files associated with the configuration, such as key or certificate files, will not be deleted.", @"Window text");
    }
    
    BOOL localAuthorization = FALSE;
    if (  authorization == nil  ) {
        // Get an AuthorizationRef and use executeAuthorized to run the installer to delete the file
        NSString * msg = [NSString stringWithFormat: 
                          NSLocalizedString(@" Configurations may be deleted only by a computer administrator.\n\n Deletion is immediate and permanent. All settings for the configuration will also be deleted permanently.%@", @"Window text"),
                          displayName,
                          notDeletingOtherFilesMsg];
        authorization = [NSApplication getAuthorizationRef: msg];
        if (  authorization == nil) {
            return;
        }
        localAuthorization = TRUE;
    } else {
        int button = TBRunAlertPanel(NSLocalizedString(@"Please Confirm", @"Window title"),
                                     [NSString stringWithFormat:
                                      NSLocalizedString(@"Deleting a configuration is permanent and cannot be undone.\n\nAll settings for the configuration will also be deleted permanently.\n\n%@\n\nAre you sure you wish to delete configuration '%@'?", @"Window text"),
                                      notDeletingOtherFilesMsg,
                                      displayName],
                                     NSLocalizedString(@"Cancel", @"Button"),    // Default button
                                     NSLocalizedString(@"Delete", @"Button"),    // Alternate button
                                     nil);
        if (  button != NSAlertAlternateReturn) {
            if (  localAuthorization  ) {
                AuthorizationFree(authorization, kAuthorizationFlagDefaults);
                authorization = nil;
            }
            return;
        }
    }
    
    if (  [[ConfigurationManager defaultManager] deleteConfigPath: configurationPath
                                                     usingAuthRef: authorization
                                                       warnDialog: YES]  ) {
        [gTbDefaults removePreferencesFor: displayName];
        
        //Remove credentials
        AuthAgent * myAuthAgent = [[[AuthAgent alloc] initWithConfigName: displayName] autorelease];
        [myAuthAgent setAuthMode: @"privateKey"];
        if (  [myAuthAgent keychainHasCredentials]  ) {
            [myAuthAgent deleteCredentialsFromKeychain];
        }
        [myAuthAgent setAuthMode: @"password"];
        if (  [myAuthAgent keychainHasCredentials]  ) {
            [myAuthAgent deleteCredentialsFromKeychain];
        }
    }
    
    if (  localAuthorization  ) {
        AuthorizationFree(authorization, kAuthorizationFlagDefaults);
        authorization = nil;
    }
}


-(IBAction) renameConfigurationMenuItemWasClicked: (id) sender
{
    VPNConnection * connection = [self selectedConnection];
    if (  ! connection  ) {
        NSLog(@"renameConfigurationMenuItemWasClicked but no configuration has been selected");
        return;
    }
    
    NSString * sourceDisplayName = [connection displayName];
    NSString * autoConnectKey = [sourceDisplayName stringByAppendingString: @"autoConnect"];
    NSString * onSystemStartKey = [sourceDisplayName stringByAppendingString: @"-onSystemStart"];
    if (   [gTbDefaults boolForKey: autoConnectKey]
        && [gTbDefaults boolForKey: onSystemStartKey]  ) {
        TBRunAlertPanel(@"Tunnelblick",
                        NSLocalizedString(@"You may not rename a configuration which is set to start when the computer starts.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
    NSString * sourcePath = [connection configPath];
    if (  [sourcePath hasPrefix: gDeployPath]  ) {
        TBRunAlertPanel(@"Tunnelblick",
                        NSLocalizedString(@"You may not rename a Deployed configuration.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
    NSString * sourceFolder = [sourcePath stringByDeletingLastPathComponent];
    NSString * sourceLast = [sourcePath  lastPathComponent];
    NSString * sourceExtension = [sourceLast pathExtension];
    
    // Get the new name
    NSString * newName = TBGetDisplayName(@"Please enter the new name.", sourcePath);

    if (  ! newName  ) {
        return;             // User cancelled
    }
    
    NSString * targetPath = [sourceFolder stringByAppendingPathComponent: newName];
    NSArray * goodExtensions = [NSArray arrayWithObjects: @"tblk", @"ovpn", @"conf", nil];
    NSString * newExtension = [newName pathExtension];
    if (  ! [goodExtensions containsObject: newExtension]  ) {
        targetPath = [targetPath stringByAppendingPathExtension: sourceExtension];
    }
    
    NSString * targetDisplayName = [lastPartOfPath(targetPath) stringByDeletingPathExtension];
    NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"You have asked to rename '%@' to '%@'.", @"Window text"), sourceDisplayName, targetDisplayName];
    AuthorizationRef authRef = [NSApplication getAuthorizationRef: msg];
    if ( authRef == nil ) {
        NSLog(@"Rename of configuration cancelled by user");
        return;
    }
    
    if (  [[ConfigurationManager defaultManager] copyConfigPath: sourcePath
                                                         toPath: targetPath
                                                   usingAuthRef: authRef
                                                     warnDialog: YES
                                                    moveNotCopy: YES]  ) {
        
        if (  ! [gTbDefaults movePreferencesFrom: [connection displayName] to: targetDisplayName]  ) {
            TBRunAlertPanel(NSLocalizedString(@"Warning", @"Window title"),
                            NSLocalizedString(@"Warning: One or more preferences could not be renamed. See the Console Log for details.", @"Window text"),
                            nil, nil, nil);
        }
        
        [self copyOrMoveCredentialsFromDisplayName: [connection displayName] to: targetDisplayName moveNotCopy: YES];
    }
}

-(IBAction) duplicateConfigurationMenuItemWasClicked: (id) sender
{
    VPNConnection * connection = [self selectedConnection];
    if (  ! connection  ) {
        NSLog(@"duplicateConfigurationMenuItemWasClicked but no configuration has been selected");
        return;
    }
    
    NSString * displayName = [connection displayName];
    NSString * autoConnectKey = [displayName stringByAppendingString: @"autoConnect"];
    NSString * onSystemStartKey = [displayName stringByAppendingString: @"-onSystemStart"];
    if (   [gTbDefaults boolForKey: autoConnectKey]
        && [gTbDefaults boolForKey: onSystemStartKey]  ) {
        TBRunAlertPanel(@"Tunnelblick",
                        NSLocalizedString(@"You may not duplicate a configuration which is set to start when the computer starts.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
    NSString * source = [connection configPath];
    if (  [source hasPrefix: gDeployPath]  ) {
        TBRunAlertPanel(@"Tunnelblick",
                        NSLocalizedString(@"You may not duplicate a Deployed configuration.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
    // Get a target path like the finder: "xxx copy.ext", "xxx copy 2.ext", "xxx copy 3.ext", etc.
    NSString * sourceFolder = [source stringByDeletingLastPathComponent];
    NSString * sourceLast = [source lastPathComponent];
    NSString * sourceLastName = [sourceLast stringByDeletingPathExtension];
    NSString * sourceExtension = [sourceLast pathExtension];
    NSString * targetName;
    NSString * target;
    int copyNumber;
    for (  copyNumber=1; copyNumber<100; copyNumber++  ) {
        if (  copyNumber == 1) {
            targetName = [sourceLastName stringByAppendingString: @" copy"];
        } else {
            targetName = [sourceLastName stringByAppendingFormat: @" copy %d", copyNumber];
        }
        
        target = [[sourceFolder stringByAppendingPathComponent: targetName] stringByAppendingPathExtension: sourceExtension];
        if (  ! [gFileMgr fileExistsAtPath: target]  ) {
            break;
        }
    }
    
    if (  copyNumber > 99  ) {
        TBRunAlertPanel(NSLocalizedString(@"Warning", @"Window title"),
                        NSLocalizedString(@"Too may duplicate configurations already exist.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
    NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"You have asked to duplicate '%@'.", @"Window text"), displayName];
    AuthorizationRef authRef = [NSApplication getAuthorizationRef: msg];
    if ( authRef == nil ) {
        NSLog(@"Duplication of configuration cancelled by user");
        return;
    }
    
    if (  [[ConfigurationManager defaultManager] copyConfigPath: source
                                                         toPath: target
                                                   usingAuthRef: authRef
                                                     warnDialog: YES
                                                    moveNotCopy: NO]  ) {
        
        NSString * targetDisplayName = [lastPartOfPath(target) stringByDeletingPathExtension];
        if (  ! [gTbDefaults copyPreferencesFrom: displayName to: targetDisplayName]  ) {
            TBRunAlertPanel(NSLocalizedString(@"Warning", @"Window title"),
                            NSLocalizedString(@"Warning: One or more preferences could not be duplicated. See the Console Log for details.", @"Window text"),
                            nil, nil, nil);
        }
        
        [self copyOrMoveCredentialsFromDisplayName: [connection displayName] to: targetDisplayName moveNotCopy: NO];

    }
}


-(IBAction) makePrivateOrSharedMenuItemWasClicked: (id) sender
{
    NSString * displayName = [[self selectedConnection] displayName];
    NSString * autoConnectKey = [displayName stringByAppendingString: @"autoConnect"];
    NSString * onSystemStartKey = [displayName stringByAppendingString: @"-onSystemStart"];
    if (   [gTbDefaults boolForKey: autoConnectKey]
        && [gTbDefaults boolForKey: onSystemStartKey]  ) {
        TBRunAlertPanel(@"Tunnelblick",
                        NSLocalizedString(@"You cannot make a configuration which is set to start when the computer starts to be private.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
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
                [[ConfigurationManager defaultManager] shareOrPrivatizeAtPath: path];
            }
        }
    }
}


-(IBAction) showOnTunnelblickMenuMenuItemWasClicked: (id) sender
{
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        NSString * key = [[connection displayName] stringByAppendingString: @"-doNotShowOnTunnelblickMenu"];
        if (  [gTbDefaults boolForKey: key]  ) {
            [showOnTunnelblickMenuMenuItem setTitle: NSLocalizedString(@"Hide Configuration on Tunnelblick Menu"      , @"Menu Item")];
            [gTbDefaults removeObjectForKey: key];
        } else {
            [showOnTunnelblickMenuMenuItem setTitle: NSLocalizedString(@"Show Configuration on Tunnelblick Menu"      , @"Menu Item")];
            [gTbDefaults setBool: TRUE forKey: key];
        }
    } else {
        NSLog(@"showOnTunnelblickMenuMenuItemWasClicked but no configuration selected");
    }
    
}


-(IBAction) editOpenVPNConfigurationFileMenuItemWasClicked: (id) sender
{
    VPNConnection * connection = [self selectedConnection];
	[[ConfigurationManager defaultManager] editConfigurationAtPath: [connection configPath] forConnection: connection];
}


-(IBAction) showOpenvpnLogMenuItemWasClicked: (id) sender
{
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        NSString * path = [connection openvpnLogPath];
        BOOL result = FALSE;
        if (  path  ) {
            result = [[NSWorkspace sharedWorkspace] selectFile: path inFileViewerRootedAtPath: @""];
        }
        if (  ! result  ) {
            TBRunAlertPanel(NSLocalizedString(@"File not found", @"Window title"),
                            NSLocalizedString(@"The OpenVPN log does not yet exist or has been deleted.", @"Window text"),
                            nil, nil, nil);
        }
    } else {
        NSLog(@"showOpenvpnLogMenuItemWasClicked but no configuration selected");
    }
}


-(IBAction) removeCredentialsMenuItemWasClicked: (id) sender
{
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        NSString * name = [connection displayName];
        AuthAgent * myAuthAgent = [[[AuthAgent alloc] initWithConfigName: name] autorelease];
        
        BOOL hasCredentials = FALSE;
        [myAuthAgent setAuthMode: @"privateKey"];
        if (  [myAuthAgent keychainHasCredentials]  ) {
            hasCredentials = TRUE;
        }
        [myAuthAgent setAuthMode: @"password"];
        if (  [myAuthAgent keychainHasCredentials]  ) {
            hasCredentials = TRUE;
        }
        
        if (  hasCredentials  ) {
            int button = TBRunAlertPanel(NSLocalizedString(@"Please Confirm", @"Window title"),
                                         [NSString stringWithFormat: NSLocalizedString(@"Are you sure you wish to delete the credentials (private key or username and password) for '%@' that are stored in the Keychain?", @"Window text"), name],
                                         NSLocalizedString(@"Cancel", @"Button"),             // Default button
                                         NSLocalizedString(@"Delete Credentials", @"Button"), // Alternate button
                                         nil);
            
            if (  button == NSAlertAlternateReturn  ) {
                [myAuthAgent setAuthMode: @"privateKey"];
                if (  [myAuthAgent keychainHasCredentials]  ) {
                    [myAuthAgent deleteCredentialsFromKeychain];
                }
                [myAuthAgent setAuthMode: @"password"];
                if (  [myAuthAgent keychainHasCredentials]  ) {
                    [myAuthAgent deleteCredentialsFromKeychain];
                }
            }
        } else {
            TBRunAlertPanel(NSLocalizedString(@"No Credentials", @"Window title"),
                            [NSString stringWithFormat:
                             NSLocalizedString(@"'%@' does not have any credentials (private key or username and password) stored in the Keychain.", @"Window text"),
                             name],
                            nil, nil, nil);
        }
        
    } else {
        NSLog(@"removeCredentialsMenuItemWasClicked but no configuration selected");
    }
}


// Log tab

-(IBAction) copyLogButtonWasClicked: (id) sender
{
    NSTextStorage * store = [logView textStorage];
    NSPasteboard * pb = [NSPasteboard generalPasteboard];
    [pb declareTypes: [NSArray arrayWithObject: NSStringPboardType] owner: self];
    [pb setString: [store string] forType: NSStringPboardType];
}


// Settings tab

-(IBAction) whenToConnectManuallyMenuItemWasClicked: (id) sender
{
    [self setSelectedWhenToConnectIndex: 0];
}


-(IBAction) whenToConnectTunnelblickLaunchMenuItemWasClicked: (id) sender
{
    [self setSelectedWhenToConnectIndex: 1];
}


-(IBAction) whenToConnectOnComputerStartMenuItemWasClicked: (id) sender
{
    NSString * configurationPath = [[self selectedConnection] configPath];
    BOOL enableWhenComputerStarts = ! [configurationPath hasPrefix: gPrivatePath];
    if (  enableWhenComputerStarts  ) {
        [self setSelectedWhenToConnectIndex: 2];
    } else {
        NSInteger ix = selectedWhenToConnectIndex;
        selectedWhenToConnectIndex = 2;
        [whenToConnectPopUpButton selectItemAtIndex: ix];
        [self setSelectedWhenToConnectIndex: ix];
        TBRunAlertPanel(@"Tunnelblick",
                        NSLocalizedString(@"Private configurations cannot connect when the computer starts.\n\n"
                                          "First make the configuration shared, then change this setting.", @"Window text"),
                        nil, nil, nil);
    }
}


-(NSInteger) selectedWhenToConnectIndex
{
    return selectedWhenToConnectIndex;
}


-(void) setSelectedWhenToConnectIndex: (NSInteger) newValue
{
    NSInteger oldValue = selectedWhenToConnectIndex;
    if (  newValue != oldValue  ) {
        NSString * configurationName = [[self selectedConnection] displayName];
        NSString * autoConnectKey   = [configurationName stringByAppendingString: @"autoConnect"];
        NSString * onSystemStartKey = [configurationName stringByAppendingString: @"-onSystemStart"];
        switch (  newValue  ) {
            case 0:
                [gTbDefaults setBool: FALSE forKey: autoConnectKey];
                [gTbDefaults setBool: FALSE forKey: onSystemStartKey];
                break;
            case 1:
                [gTbDefaults setBool: TRUE  forKey: autoConnectKey];
                [gTbDefaults setBool: FALSE forKey: onSystemStartKey];
                break;
            case 2:
                [gTbDefaults setBool: TRUE forKey: autoConnectKey];
                [gTbDefaults setBool: TRUE forKey: onSystemStartKey];
                break;
            default:
                NSLog(@"Attempt to set 'when to connect' to %d ignored", newValue);
                break;
        }
        selectedWhenToConnectIndex = newValue;
        [self validateWhenToConnect: [self selectedConnection]];
        
        int ix = 0;
        if (  [gTbDefaults boolForKey: autoConnectKey]  ) {
            if (  [gTbDefaults boolForKey: onSystemStartKey]  ) {
                ix = 2;
            } else {
                ix = 1;
            }
        }
        if (  ix != newValue  ) {   // If weren't able to change it, restore old value
            [self setSelectedWhenToConnectIndex: oldValue];
        }
        selectedWhenToConnectIndex = ix;
    }
}


-(NSInteger) selectedSetNameserverIndex
{
    return selectedSetNameserverIndex;
}


-(void) setSelectedSetNameserverIndex: (NSInteger) newValue
{
    if (  newValue != selectedSetNameserverIndex  ) {
        if (  selectedSetNameserverIndex != NSNotFound  ) {
            NSString * actualKey = [[[self selectedConnection] displayName] stringByAppendingString: @"useDNS"];
            [gTbDefaults setObject: [NSNumber numberWithInt: newValue] forKey: actualKey];
        }
        selectedSetNameserverIndex = newValue;
        
        // If script doesn't support monitoring, indicate it is off and disable it
        if (   (newValue > 2)
            || (newValue == 0)
            || ([[setNameserverArrayController content] count] < 4)  ) {
            [monitorNetworkForChangesCheckbox setState: NSOffState];
            [monitorNetworkForChangesCheckbox setEnabled: NO];
        } else {
            [self setupCheckbox: monitorNetworkForChangesCheckbox
                            key: @"-notMonitoringConnection"
                       inverted: YES];
            [monitorNetworkForChangesCheckbox setEnabled: YES];
        }
        [settingsSheetWindowController monitorNetworkForChangesCheckboxChangedForConnection: [self selectedConnection]];

    }
}

// Checkbox was changed by another window
-(void) monitorNetworkForChangesCheckboxChangedForConnection: (VPNConnection *) theConnection;
{
    VPNConnection * connection = [self selectedConnection];
    if (   connection
        && (connection == theConnection)  ) {
        NSString * displayName = [connection displayName];
        NSString * key = [displayName stringByAppendingString: @"-notMonitoringConnection"];
        BOOL checked = [gTbDefaults boolForKey: key];
        int state = (checked ? NSOffState : NSOnState);
        [monitorNetworkForChangesCheckbox setState: state];
    }
}


-(IBAction) monitorNetworkForChangesCheckboxWasClicked: (id) sender
{
    [self changeBooleanPreference: @"-notMonitoringConnection"
                               to: ([sender state] == NSOnState)
                         inverted: YES];
    
    [settingsSheetWindowController monitorNetworkForChangesCheckboxChangedForConnection: [self selectedConnection]];
}


-(NSInteger) selectedSoundOnConnectIndex
{
    return selectedSoundOnConnectIndex;
}


-(void) setSelectedSoundOnConnectIndex: (NSInteger) newValue
{
    [self setSoundIndex: &selectedSoundOnConnectIndex
                     to: newValue
             preference: @"-tunnelUpSoundName"];
}


-(NSInteger) selectedSoundOnDisconnectIndex
{
    return selectedSoundOnDisconnectIndex;
}


-(void) setSelectedSoundOnDisconnectIndex: (NSInteger) newValue
{
    [self setSoundIndex: &selectedSoundOnDisconnectIndex
                     to: newValue
             preference: @"-tunnelDownSoundName"];
}

-(IBAction) advancedButtonWasClicked: (id) sender
{
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        if (  settingsSheetWindowController == nil  ) {
            settingsSheetWindowController = [[SettingsSheetWindowController alloc] init];
        }
        
        NSString * name = [connection displayName];
        [settingsSheetWindowController setConfigurationName: name];
        [settingsSheetWindowController showSettingsSheet: self];
    } else {
        NSLog(@"settingsButtonWasClicked but no configuration selected");
    }
}


// Methods used above

-(void) copyOrMoveCredentialsFromDisplayName: (NSString *) fromDisplayName
                                          to: (NSString *) toDisplayName
                                 moveNotCopy: (BOOL)       moveNotCopy
{
    NSString * myPassphrase = nil;
    NSString * myUsername = nil;
    NSString * myPassword = nil;
    
    AuthAgent * myAuthAgent = [[[AuthAgent alloc] initWithConfigName: fromDisplayName] autorelease];
    [myAuthAgent setAuthMode: @"privateKey"];
    if (  [myAuthAgent keychainHasCredentials]  ) {
        myPassphrase = [myAuthAgent passphrase];
        if (  moveNotCopy) {
            [myAuthAgent deleteCredentialsFromKeychain];
        }
    }
    [myAuthAgent setAuthMode: @"password"];
    if (  [myAuthAgent keychainHasCredentials]  ) {
        myUsername = [myAuthAgent username];
        myPassword   = [myAuthAgent password];
        if (  moveNotCopy) {
            [myAuthAgent deleteCredentialsFromKeychain];
        }
    }
    
    myAuthAgent = [[[AuthAgent alloc] initWithConfigName: toDisplayName] autorelease];
    if (  myPassphrase  ) {
        [myAuthAgent setAuthMode: @"privateKey"];
        [myAuthAgent setPassphrase: myPassphrase];
    }
    if (  myPassword  ) {
        [myAuthAgent setAuthMode: @"password"];
        [myAuthAgent setPassword: myPassword];
    }
    if (  myUsername  ) {
        [myAuthAgent setAuthMode: @"password"];
        [myAuthAgent setPassphrase: myUsername];
    }        
}


-(BOOL) changeBooleanPreference: (NSString *) key
                             to: (BOOL)       newValue
                       inverted: (BOOL)       inverted
{
    NSString * actualKey = [[[self selectedConnection] displayName] stringByAppendingString: key];
    BOOL state = (inverted ? ! newValue : newValue);
    [gTbDefaults setBool: state forKey: actualKey];
    return state;
}


-(void) setSoundIndex: (NSInteger *) index to: (NSInteger) newValue preference: (NSString *) preference
{
    if (  newValue != *index  ) {
        NSInteger size = [sortedSounds count];
        if (  newValue < size + 1  ) {
            if (  *index != NSNotFound  ) {
                NSString * key = [[[self selectedConnection] displayName] stringByAppendingString: preference];
                NSString * newName;
                if (  newValue == 0) {
                    newName = @"None";
                } else {
                    newName = [sortedSounds objectAtIndex: newValue - 1];
                    NSSound * sound = [NSSound soundNamed: newName];
                    if (  sound  ) {
                        if (  ! doNotPlaySounds  ) {
                            [sound play];
                        }
                    } else {
                        NSLog(@"Sound '%@' is not available", newName);
                    }
                }
                [gTbDefaults setObject: newName forKey: key];
            }
            *index = newValue;
        } else {
            NSLog(@"setSelectedSoundIndex: %d but there are only %d entries", newValue, size);
        }
    }
}


@end
