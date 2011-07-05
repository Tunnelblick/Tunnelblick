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


#import "MyPrefsWindowController.h"
#import "TBUserDefaults.h"
#import "ConfigurationManager.h"
#import "MenuController.h"
#import "NSApplication+LoginItem.h"
#import "NSString+TB.h"
#import "helper.h"
#import "ConfigurationsView.h"
#import "GeneralView.h"
#import "AppearanceView.h"
#import "InfoView.h"
#import "SettingsSheetWindowController.h"
#import "Sparkle/SUUpdater.h"


extern NSFileManager  * gFileMgr;
extern TBUserDefaults * gTbDefaults;
extern NSString       * gDeployPath;
extern NSString       * gSharedPath;
extern NSString       * gPrivatePath;
extern unsigned         gMaximumLogSize;
extern NSArray        * gProgramPreferences;
extern NSArray        * gConfigurationPreferences;

@interface MyPrefsWindowController()

-(void) setupViews;
-(void) setupConfigurationsView;
-(void) setupGeneralView;
-(void) setupAppearanceView;
-(void) setupInfoView;

-(BOOL) changeBooleanPreference: (NSString *) key
                             to: (BOOL)       newValue
                       inverted: (BOOL)       inverted;

-(int) firstDifferentComponent: (NSArray *) a
                           and: (NSArray *) b;

-(NSString *) indent: (NSString *) s
                  by: (int)        n;

-(void) setCurrentViewName: (NSString *) newName;

-(void) setSelectedWhenToConnectIndex: (NSInteger) newValue;

-(void) setSoundIndex: (NSInteger *) index
                   to: (NSInteger)   newValue
           preference: (NSString *)  preference;

-(void) setupCheckbox: (NSButton *) checkbox
                  key: (NSString *) key
             inverted: (BOOL) inverted;

-(void) setupLeftNavigationToDisplayName: (NSString *) displayNameToSelect;

-(void) setupSoundButton: (NSButton *)          button
         arrayController: (NSArrayController *) ac
              preference: (NSString *)          preference;

-(void) setValueForCheckbox: (NSButton *) checkbox
              preferenceKey: (NSString *) preferenceKey
                   inverted: (BOOL)       inverted
                 defaultsTo: (BOOL)       defaultsTo;

-(void) updateConnectionStatusAndTime;

-(void) updateLastCheckedDate;

-(void) validateDetailsWindowControls;

-(void) validateWhenToConnect: (VPNConnection *) connection;

@end

@implementation MyPrefsWindowController

-(void) setupToolbar
{
    [self addView: configurationsPrefsView  label: NSLocalizedString(@"Configurations", @"Window title") image: [NSImage imageNamed: @"Configurations"]];
    [self addView: generalPrefsView         label: NSLocalizedString(@"Preferences",    @"Window title") image: [NSImage imageNamed: @"Preferences"   ]];
    [self addView: appearancePrefsView      label: NSLocalizedString(@"Appearance",     @"Window title") image: [NSImage imageNamed: @"Appearance"    ]];
    [self addView: infoPrefsView            label: NSLocalizedString(@"Info",           @"Window title") image: [NSImage imageNamed: @"Info"          ]];
    
    [self setupViews];
    
    [[self window] setDelegate: self];
}

static BOOL firstTimeShowingWindow = TRUE;

-(void) setupViews
{
    
    currentFrame = NSMakeRect(0, 0, 760, 390);
    
    currentViewName = @"Configurations";
    
    selectedKeyboardShortcutIndex                          = UINT_MAX;
    selectedMaximumLogSizeIndex                            = UINT_MAX;
    selectedAppearanceIconSetIndex                         = UINT_MAX;
    selectedAppearanceConnectionWindowDisplayCriteriaIndex = UINT_MAX;
    
    [self setupConfigurationsView];
    [self setupGeneralView];
    [self setupAppearanceView];
    [self setupInfoView];
}


- (IBAction)showWindow:(id)sender 
{
    [super showWindow: sender];
    
    [[self window] center];
    
    if (  firstTimeShowingWindow  ) {
        // Set the window's position from preferences (saved when window is closed)
        // But only if the preference's version matches the TB version (since window size could be different in different versions of TB)
        NSString * tbVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
        if (  [tbVersion isEqualToString: [gTbDefaults objectForKey:@"detailsWindowFrameVersion"]]    ) {
            NSString * mainFrameString  = [gTbDefaults objectForKey: @"detailsWindowFrame"];
            NSString * leftFrameString  = [gTbDefaults objectForKey: @"detailsWindowLeftFrame"];
            if (   mainFrameString != nil  ) {
                NSRect mainFrame = NSRectFromString(mainFrameString);
                [[self window] setFrame: mainFrame display: YES];  // display: YES so stretches properly
            }
            
            if (  leftFrameString != nil  ) {
                NSRect leftFrame = NSRectFromString(leftFrameString);
                if (  leftFrame.size.width < LEFT_NAV_AREA_MINIMUM_SIZE  ) {
                    leftFrame.size.width = LEFT_NAV_AREA_MINIMUM_SIZE;
                }
                [[configurationsPrefsView leftSplitView] setFrame: leftFrame];
            }
        }
        
        firstTimeShowingWindow = FALSE;
    }
}


-(void) windowWillClose:(NSNotification *)notification
{
    [[self selectedConnection] stopMonitoringLogFiles];
    
    // Save the window's frame and the splitView's frame and the TB version in the preferences
    NSString * mainFrameString = NSStringFromRect([[self window] frame]);
    NSString * leftFrameString = nil;
    if (  [[configurationsPrefsView leftSplitView] frame].size.width > (LEFT_NAV_AREA_MINIMAL_SIZE + 5.0)  ) {
        leftFrameString = NSStringFromRect([[configurationsPrefsView leftSplitView] frame]);
    }
    NSString * tbVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    BOOL saveIt = TRUE;
    if (  [tbVersion isEqualToString: [gTbDefaults objectForKey:@"detailsWindowFrameVersion"]]    ) {
        if (   [mainFrameString isEqualToString: [gTbDefaults objectForKey:@"detailsWindowFrame"]]
            && [leftFrameString isEqualToString: [gTbDefaults objectForKey:@"detailsWindowLeftFrame"]]  ) {
            saveIt = FALSE;
        }
    }
    
    if (saveIt) {
        [gTbDefaults setObject: mainFrameString forKey: @"detailsWindowFrame"];
        if (  leftFrameString ) {
            [gTbDefaults setObject: leftFrameString forKey: @"detailsWindowLeftFrame"];
        }
        [gTbDefaults setObject: [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]
                        forKey: @"detailsWindowFrameVersion"];
        [gTbDefaults synchronize];
    }
}


// oldViewWillDisappear and newViewWillAppear do two things:
//
//      1) They fiddle frames to ignore resizing except of Configurations
//      2) They notify infoPrefsView it is appearing/disappearing so it can start/stop its animation

// Overrides superclass
-(void) oldViewWillDisappear: (NSView *) view identifier: (NSString *) identifier
{
    if (  [view respondsToSelector: @selector(oldViewWillDisappear:identifier:)]  ) {
        [(id) view oldViewWillDisappear: view identifier: identifier];
    }
    
    [self setCurrentViewName: nil];
    
    // If switching FROM Configurations, save the frame for later and remove resizing indicator
    //                                   and stop monitoring the log
    if (   [identifier isEqualToString: @"Configurations"]  ) {
        currentFrame = [view frame];
        [[view window] setShowsResizeIndicator: NO];
        
        [[self selectedConnection] stopMonitoringLogFiles];
    }
}


// Overrides superclass
-(void) newViewWillAppear: (NSView *) view identifier: (NSString *) identifier
{
    if (  [view respondsToSelector: @selector(newViewWillAppear:identifier:)]  ) {
        [(id) view newViewWillAppear: view identifier: identifier];
    }
    
    [self setCurrentViewName: identifier];
    
    // If switching TO Configurations, restore its last frame (even if user resized the window)
    //                                 and start monitoring the log
    // Otherwise, restore all other views' frames to the Configurations frame
    if (   [identifier isEqualToString: @"Configurations"]  ) {
        [view setFrame: currentFrame];
        [[view window] setShowsResizeIndicator: YES];
        
        [[self selectedConnection] startMonitoringLogFiles];
    } else {
        [appearancePrefsView setFrame: currentFrame];
        [generalPrefsView    setFrame: currentFrame];        
        [infoPrefsView       setFrame: currentFrame];
    }
}

// Overrides superclass
-(void) newViewDidAppear: (NSView *) view
{
    if        (   view == configurationsPrefsView  ) {
        [[self window] makeFirstResponder: [configurationsPrefsView leftNavTableView]];
    } else if (   view == generalPrefsView  ) {
        [[self window] makeFirstResponder: [generalPrefsView keyboardShortcutButton]];
    } else if (   view == appearancePrefsView  ) {
        [[self window] makeFirstResponder: [appearancePrefsView appearanceIconSetButton]];
    } else if (   view == infoPrefsView  ) {
        [[self window] makeFirstResponder: [infoPrefsView infoHelpButton]];
    } else {
        NSLog(@"newViewDidAppear:identifier: invoked with unknown view");
    }
}

    -(BOOL) tabView: (NSTabView *) inTabView shouldSelectTabViewItem: (NSTabViewItem *) tabViewItem
{
    if (  [self selectedConnection]  ) {
        return YES;
    }
    
    return NO;
}

-(void) tabView: (NSTabView *) inTabView didSelectTabViewItem: (NSTabViewItem *) tabViewItem
{
    if (  inTabView == [configurationsPrefsView configurationsTabView]  ) {
        if (  tabViewItem == [configurationsPrefsView logTabViewItem]  ) {
            [[self selectedConnection] startMonitoringLogFiles];
        } else {
            [[self selectedConnection] stopMonitoringLogFiles];
        }
    }
}

//***************************************************************************************************************

-(void) setupConfigurationsView
{
    selectedSetNameserverIndex     = NSNotFound;   // Force a change when first set
    selectedWhenToConnectIndex     = NSNotFound;
    selectedSoundOnConnectIndex    = NSNotFound;
    selectedSoundOnDisconnectIndex = NSNotFound;    

    selectedLeftNavListIndex = 0;
    
    [leftNavList                          release];
    leftNavList                         = nil;
    [leftNavDisplayNames                  release];
    leftNavDisplayNames                 = nil;
    [settingsSheetWindowController        release];
    settingsSheetWindowController       = nil;
    [previouslySelectedNameOnLeftNavList  release];
    previouslySelectedNameOnLeftNavList = nil;

    authorization = 0;
    doNotPlaySounds = FALSE;
    
    [self setupLeftNavigationToDisplayName: nil];   // MUST DO THIS FIRST SO A CONFIGURATION IS SELECTED
    
    // Right split view
    
    [[configurationsPrefsView configurationsTabView] setDelegate: self];
    
    VPNConnection * connection = [self selectedConnection];
    
    // Right split view - Settings tab

    if (  connection  ) {
    
        [self updateConnectionStatusAndTime];
        
        // Right split view - Log tab
        
        [self indicateNotWaitingForConnection: [self selectedConnection]];
        
        
        [self validateWhenToConnect: [self selectedConnection]];
        
        // Set up setNameserverPopUpButton with localized content that varies with the connection
        NSInteger ix = 0;
        NSArray * content = [connection modifyNameserverOptionList];
        [[configurationsPrefsView setNameserverArrayController] setContent: content];
        [[configurationsPrefsView setNameserverPopUpButton] sizeToFit];
        
        // Select the appropriate Set nameserver entry
        NSString * key = [[[self selectedConnection] displayName] stringByAppendingString: @"useDNS"];
        id obj = [gTbDefaults objectForKey: key];
        if (  obj != nil  ) {
            if (  [obj respondsToSelector: @selector(intValue)]  ) {
                ix = (NSInteger) [obj intValue];
                if (  ix >= [[[configurationsPrefsView setNameserverArrayController] content] count]  ) {
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
        
        [[configurationsPrefsView setNameserverPopUpButton] selectItemAtIndex: ix];
        [self setSelectedSetNameserverIndex: ix];
        [[configurationsPrefsView setNameserverPopUpButton] setEnabled: [gTbDefaults canChangeValueForKey: key]];
        
        if (  [self forceDisableOfNetworkMonitoring]  ) {
            [[configurationsPrefsView monitorNetworkForChangesCheckbox] setState: NSOffState];
            [[configurationsPrefsView monitorNetworkForChangesCheckbox] setEnabled: NO];
        } else {
            [self setupCheckbox: [configurationsPrefsView monitorNetworkForChangesCheckbox]
                            key: @"-notMonitoringConnection"
                       inverted: YES];
            [[configurationsPrefsView monitorNetworkForChangesCheckbox] setEnabled: YES];
        }
        
        [self setupSoundButton: [configurationsPrefsView soundOnConnectButton]
               arrayController: [configurationsPrefsView soundOnConnectArrayController]
                    preference: @"-tunnelUpSoundName"];
        
        
        [self setupSoundButton: [configurationsPrefsView soundOnDisconnectButton]
               arrayController: [configurationsPrefsView soundOnDisconnectArrayController]
                    preference: @"-tunnelDownSoundName"];
        
        // Set up a timer to update connection times
        [[NSApp delegate] startOrStopDurationsTimer];
    }
    
    [self validateDetailsWindowControls];   // Set windows enabled/disabled
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
    NSArray * allConfigsSorted = [[[[NSApp delegate] myVPNConnectionDictionary] allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveNumericCompare:)];
    
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
            [leftNavList         addObject: [self indent: folderName by: firstDiff+i]];
            [currentFolders addObject: folderName];
            ++currentLeftNavIndex;
        }
        
        // Add a "configuration" line
        [leftNavDisplayNames addObject: [connection displayName]];
        [leftNavList         addObject: [self indent: [currentConfig lastObject] by: [currentConfig count]-1]];
        
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
    
    [[configurationsPrefsView leftNavTableView] reloadData];
    
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
            [[configurationsPrefsView leftNavTableView] scrollRowToVisible: leftNavIndexToSelect];
        }
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
    NSString * localizedStatus = localizeNonLiteral(state, @"Connection status");
    if (  [state isEqualToString: @"CONNECTED"]  ) {
        NSString * time = [newConnection connectTimeString];
        [[configurationsPrefsView configurationStatusTFC] setTitle: [NSString stringWithFormat: @"%@%@",
                                           localizedStatus, time]];
    } else {
        [[configurationsPrefsView configurationStatusTFC] setTitle: localizedStatus];
    }
    
    [[self window] setTitle: [self windowTitle: NSLocalizedString(@"Configurations", @"Window title")]];
    
    [settingsSheetWindowController updateConnectionStatusAndTime];
}

-(void) doLogScrollingForConnection: (VPNConnection *) theConnection
{
    if (  theConnection == [self selectedConnection]  ) {
        NSTextView * textView = [[[NSApp delegate] logScreen] logView];
        [textView scrollRangeToVisible: NSMakeRange([[textView string] length], 0)];
    }
}

-(void) indicateWaitingForConnection: (VPNConnection *) theConnection
{
    if (  theConnection == [self selectedConnection]  ) {
        [[configurationsPrefsView progressIndicator] startAnimation: self];
        [[configurationsPrefsView progressIndicator] setHidden: NO];
    }
}


-(void) indicateNotWaitingForConnection: (VPNConnection *) theConnection
{
    if (  theConnection == [self selectedConnection]  ) {
        [[configurationsPrefsView progressIndicator] stopAnimation: self];
        [[configurationsPrefsView progressIndicator] setHidden: YES];
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
-(void) setupSoundButton: (NSButton *)          button
         arrayController: (NSArrayController *) ac
              preference: (NSString *)          preference
{
    NSUInteger ix = NSNotFound;
    NSString * key = [[[self selectedConnection] displayName] stringByAppendingString: preference];
    NSString * soundName = [gTbDefaults objectForKey: key];
    if (  soundName  ) {
        if (  ! [soundName isEqualToString: @"None"]  ) {
            ix = [[configurationsPrefsView sortedSounds] indexOfObject: soundName];
            if (  ix == NSNotFound  ) {
                if (  [[configurationsPrefsView sortedSounds] count] > 0  ) {
                    NSString * substituteSoundName = [[configurationsPrefsView sortedSounds] objectAtIndex: 0];
                    NSLog(@"Preference '%@' '%@' is not available, using sound '%@'", key, soundName, substituteSoundName);
                    ix = 1;
                } else {
                    NSLog(@"Preference '%@' '%@' ignored, no sounds are available", key, soundName);
                }
            } else {
                ix = ix + 1;
            }
        }
    }
    
    if (  ix == NSNotFound  ) {
        ix = 0;
    }
    
    if (  button == [configurationsPrefsView soundOnConnectButton]  ) {
        [self setSelectedSoundOnConnectIndex: ix];
    } else {
        [self setSelectedSoundOnDisconnectIndex: ix];
    }
    
    //******************************************************************************
    // Don't play sounds because we are just setting the button from the preferences
    BOOL oldDoNotPlaySounds = doNotPlaySounds;
    doNotPlaySounds = TRUE;
    
    if (  button == [configurationsPrefsView soundOnConnectButton]) {
        [self setSelectedSoundOnConnectIndex: ix];
    } else {
        [self setSelectedSoundOnDisconnectIndex: ix];
    }
    
    doNotPlaySounds = oldDoNotPlaySounds;
    //******************************************************************************
    
    BOOL enable = [gTbDefaults canChangeValueForKey: key];
    [button setEnabled: enable];
}

-(void) validateDetailsWindowControls
{
    VPNConnection * connection = [self selectedConnection];
    
    [self validateConnectAndDisconnectButtonsForConnection: connection];
    
    if (  connection  ) {
        
        // Left split view
        
        [[configurationsPrefsView renameConfigurationMenuItem]     setEnabled: YES];
        [[configurationsPrefsView duplicateConfigurationMenuItem]  setEnabled: YES];
        
        NSString * configurationPath = [connection configPath];
        if (  [configurationPath hasPrefix: gSharedPath]  ) {
            [[configurationsPrefsView makePrivateOrSharedMenuItem] setTitle: NSLocalizedString(@"Make Configuration Private..."  , @"Menu Item")];
            [[configurationsPrefsView makePrivateOrSharedMenuItem] setEnabled: YES];
        } else if (  [configurationPath hasPrefix: gPrivatePath]  ) {
            [[configurationsPrefsView makePrivateOrSharedMenuItem] setTitle: NSLocalizedString(@"Make Configuration Shared..."  , @"Menu Item")];
            [[configurationsPrefsView makePrivateOrSharedMenuItem] setEnabled: YES];
        } else {
            [[configurationsPrefsView makePrivateOrSharedMenuItem] setTitle: NSLocalizedString(@"Make Configuration Shared..."  , @"Menu Item")];
            [[configurationsPrefsView makePrivateOrSharedMenuItem] setEnabled: NO];
        }
        
        if (  [[ConfigurationManager defaultManager] userCanEditConfiguration: [connection configPath]]  ) {
            [[configurationsPrefsView editOpenVPNConfigurationFileMenuItem] setTitle: NSLocalizedString(@"Edit OpenVPN Configuration File...", @"Menu Item")];
        } else {
            [[configurationsPrefsView editOpenVPNConfigurationFileMenuItem] setTitle: NSLocalizedString(@"Examine OpenVPN Configuration File...", @"Menu Item")];
        }
        [[configurationsPrefsView editOpenVPNConfigurationFileMenuItem]     setEnabled: YES];
        
        NSString * key = [[connection displayName] stringByAppendingString: @"-doNotShowOnTunnelblickMenu"];
        if (  [gTbDefaults boolForKey: key]  ) {
            [[configurationsPrefsView showOnTunnelblickMenuMenuItem] setTitle: NSLocalizedString(@"Show Configuration on Tunnelblick Menu"  , @"Menu Item")];
        } else {
            [[configurationsPrefsView showOnTunnelblickMenuMenuItem] setTitle: NSLocalizedString(@"Hide Configuration on Tunnelblick Menu"  , @"Menu Item")];
        }
        
        [[configurationsPrefsView removeConfigurationButton]            setEnabled: YES];
        [[configurationsPrefsView workOnConfigurationPopUpButton]       setEnabled: YES];
        
        // right split view
        
        // Right split view - log tab
        
        [[configurationsPrefsView logToClipboardButton]                 setEnabled: YES];
        
        
        // Right split view - settings tab
        
        [[configurationsPrefsView advancedButton]                       setEnabled: YES];
        
        [self validateWhenToConnect: [self selectedConnection]];
        
    } else {
        
        [[configurationsPrefsView configurationNameTFC]   setTitle: @""];
        [[configurationsPrefsView configurationStatusTFC] setTitle: @""];
        
        [[configurationsPrefsView removeConfigurationButton]            setEnabled: NO];
        [[configurationsPrefsView workOnConfigurationPopUpButton]       setEnabled: NO];
        
        // The "Log" and "Settings" items can't be selected because tabView:shouldSelectTabViewItem: will return NO if there is no selected connection
        
        [[configurationsPrefsView progressIndicator]                    setHidden: YES];
        [[configurationsPrefsView logToClipboardButton]                 setEnabled: NO];
        
        [[configurationsPrefsView connectButton]                        setEnabled: NO];
        [[configurationsPrefsView disconnectButton]                     setEnabled: NO];
    }
}



// Overrides superclass method
// If showing the Configurations tab, window title is:
//      configname (Shared/Private/Deployed): Status (hh:mm:ss) - Tunnelblick
// Otherwise, window title is:
//      tabname - Tunnelblick
- (NSString *)windowTitle:(NSString *)currentItemLabel;
{
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *appName = [[NSFileManager defaultManager] displayNameAtPath: bundlePath];
    if (  [appName hasSuffix: @".app"]  ) {
        appName = [appName substringToIndex: [appName length] - 4];
    }
    
    NSString * windowLabel = [NSString stringWithFormat: @"%@ - Tunnelblick", localizeNonLiteral(currentViewName, @"Window title")];

    if (  [currentViewName isEqualToString: @"Configurations"]  ) {
        VPNConnection * connection = [self selectedConnection];
        if (   connection
            && [currentItemLabel isEqualToString: @"Configurations"]  ) {
            NSString * status = localizeNonLiteral([connection state], @"Connection status");
            NSString * connectionTimeString = [connection connectTimeString];
            if (   [connection isConnected]
                && [gTbDefaults boolForKey: @"showConnectedDurations"]  ) {
                
            }
            windowLabel = [NSString stringWithFormat: @"%@%@: %@%@ - %@", [connection displayName], [connection displayLocation], status, connectionTimeString, appName];
        }
    }
    
    return windowLabel;
}


-(void) hookedUpOrStartedConnection: (VPNConnection *) theConnection
{
    if (   theConnection
        && ( theConnection == [self selectedConnection] )  ) {
        [theConnection startMonitoringLogFiles];
    }
}


-(void) validateWhenConnectingForConnection: (VPNConnection *) theConnection
{
    if (  theConnection  ) {
        [self validateWhenToConnect: theConnection];
    }
}


-(void) validateConnectAndDisconnectButtonsForConnection: (VPNConnection *) theConnection
{
    if (  ! theConnection  )  {
        [[configurationsPrefsView connectButton]    setEnabled: NO];
        [[configurationsPrefsView disconnectButton] setEnabled: NO];
        return;
    }
    
    if ( theConnection != [self selectedConnection]  ) {
        return;
    }
    
    NSString * displayName = [theConnection displayName];
    NSString * disableConnectButtonKey    = [displayName stringByAppendingString: @"-disableConnectButton"];
    NSString * disableDisconnectButtonKey = [displayName stringByAppendingString: @"-disableDisconnectButton"];
    BOOL disconnected = [theConnection isDisconnected];
    [[configurationsPrefsView connectButton]    setEnabled: (   disconnected
                                   && ( ! [gTbDefaults boolForKey: disableConnectButtonKey] )  )];
    [[configurationsPrefsView disconnectButton] setEnabled: (   ( ! disconnected )
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


-(BOOL) forceDisableOfNetworkMonitoring
{
    NSArray * content = [[configurationsPrefsView setNameserverArrayController] content];
    NSInteger ix = [self selectedSetNameserverIndex];
    if (   ([content count] < 4)
        || (ix > 2)
        || (ix == 0)  ) {
        return TRUE;
    } else {
        return FALSE;
    }
}

-(int)numberOfRowsInTableView:(NSTableView *)aTableView
{
    if (  aTableView == [configurationsPrefsView leftNavTableView]  ) {
        int n = [leftNavList count];
        return n;
    }
    
    return 0;
}

-(id) tableView:(NSTableView *) aTableView objectValueForTableColumn:(NSTableColumn *) aTableColumn row:(int) rowIndex
{
    if (  aTableView == [configurationsPrefsView leftNavTableView]  ) {
        NSString * s = [leftNavList objectAtIndex: rowIndex];
        return s;
    }
    
    return nil;
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


-(IBAction) configurationsHelpButtonWasClicked: (id) sender
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
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
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
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
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
                          NSLocalizedString(@" Configurations may be deleted only by a computer administrator.\n\n Deletion is immediate and permanent. All settings for '%@' will also be deleted permanently.%@", @"Window text"),
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
        
        [gTbDefaults removePreferencesFor: displayName];
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
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                        NSLocalizedString(@"You may not rename a configuration which is set to start when the computer starts.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
    NSString * sourcePath = [connection configPath];
    if (  [sourcePath hasPrefix: gDeployPath]  ) {
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                        NSLocalizedString(@"You may not rename a Deployed configuration.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
    NSString * sourceFolder = [sourcePath stringByDeletingLastPathComponent];
    NSString * sourceLast = [sourcePath  lastPathComponent];
    NSString * sourceExtension = [sourceLast pathExtension];
    
    // Get the new name
    
    NSString * prompt = [NSString stringWithFormat: NSLocalizedString(@"Please enter a new name for '%@'.", @"Window text"), [sourceDisplayName lastPathComponent]];
    NSString * newName = TBGetDisplayName(prompt, sourcePath);
    
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
        
        // We copy "-keychainHasUsernameAndPassword" because it is delete by moveCredentials
        NSString * key = [[connection displayName] stringByAppendingString: @"-keychainHasUsernameAndPassword"];
        BOOL haveCredentials = [gTbDefaults boolForKey: key];
        
        moveCredentials([connection displayName], targetDisplayName); // Do this so "<source>-keychainHasUsernameAndPassword" preference is used
        
        if (  ! [gTbDefaults movePreferencesFrom: [connection displayName] to: targetDisplayName]  ) {
            TBRunAlertPanel(NSLocalizedString(@"Warning", @"Window title"),
                            NSLocalizedString(@"Warning: One or more preferences could not be renamed. See the Console Log for details.", @"Window text"),
                            nil, nil, nil);
        }
        
        // moveCredentials deleted "-keychainHasUsernameAndPassword" for the from configuration's preferences, so we restore it to the "to" configuration's preferences
        key = [targetDisplayName stringByAppendingString: @"-keychainHasUsernameAndPassword"];
        [gTbDefaults setBool: haveCredentials forKey: key];
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
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                        NSLocalizedString(@"You may not duplicate a configuration which is set to start when the computer starts.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
    NSString * source = [connection configPath];
    if (  [source hasPrefix: gDeployPath]  ) {
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
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
            targetName = [sourceLastName stringByAppendingString: NSLocalizedString(@" copy", @"Suffix for a duplicate of a file")];
        } else {
            targetName = [sourceLastName stringByAppendingFormat: NSLocalizedString(@" copy %d", @"Suffix for a duplicate of a file"), copyNumber];
        }
        
        target = [[sourceFolder stringByAppendingPathComponent: targetName] stringByAppendingPathExtension: sourceExtension];
        if (  ! [gFileMgr fileExistsAtPath: target]  ) {
            break;
        }
    }
    
    if (  copyNumber > 99  ) {
        TBRunAlertPanel(NSLocalizedString(@"Warning", @"Window title"),
                        NSLocalizedString(@"Too many duplicate configurations already exist.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
    NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"You have asked to duplicate '%@'.", @"Window text"), displayName];
    AuthorizationRef authRef = [NSApplication getAuthorizationRef: msg];
    if ( authRef == nil ) {
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
        
        copyCredentials([connection displayName], targetDisplayName);
    }
}


-(IBAction) makePrivateOrSharedMenuItemWasClicked: (id) sender
{
    VPNConnection * connection = [self selectedConnection];
    if (  ! connection  ) {
        NSLog(@"makePrivateOrSharedMenuItemWasClicked but no configuration has been selected");
        return;
    }
    
    NSString * displayName = [connection displayName];
    NSString * autoConnectKey = [displayName stringByAppendingString: @"autoConnect"];
    NSString * onSystemStartKey = [displayName stringByAppendingString: @"-onSystemStart"];
    if (   [gTbDefaults boolForKey: autoConnectKey]
        && [gTbDefaults boolForKey: onSystemStartKey]  ) {
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                        NSLocalizedString(@"You cannot make a configuration private if it is set to start when the computer starts.", @"Window text"),
                        nil, nil, nil);
    } else {
        NSString * disableShareConfigKey = [[[self selectedConnection] displayName] stringByAppendingString:@"disableShareConfigurationButton"];
        if (  ! [gTbDefaults boolForKey: disableShareConfigKey]  ) {
            NSString * path = [[self selectedConnection] configPath];
            if (  [[path pathExtension] isEqualToString: @"tblk"]  ) {
                [[ConfigurationManager defaultManager] shareOrPrivatizeAtPath: path];
            } else {
                TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                                NSLocalizedString(@"You cannot make a configuration shared if it is not a Tunnelblick VPN Configuration (.tblk).", @"Window text"),
                                nil, nil, nil);
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
            [[configurationsPrefsView showOnTunnelblickMenuMenuItem] setTitle: NSLocalizedString(@"Hide Configuration on Tunnelblick Menu"      , @"Menu Item")];
            [gTbDefaults removeObjectForKey: key];
        } else {
            [[configurationsPrefsView showOnTunnelblickMenuMenuItem] setTitle: NSLocalizedString(@"Show Configuration on Tunnelblick Menu"      , @"Menu Item")];
            [gTbDefaults setBool: TRUE forKey: key];
        }
        [[NSApp delegate] changedDisplayConnectionSubmenusSettings];
    } else {
        NSLog(@"showOnTunnelblickMenuMenuItemWasClicked but no configuration selected");
    }
    
}


-(IBAction) editOpenVPNConfigurationFileMenuItemWasClicked: (id) sender
{
    VPNConnection * connection = [self selectedConnection];
    if (connection  ) {
        [[ConfigurationManager defaultManager] editConfigurationAtPath: [connection configPath] forConnection: connection];
    } else {
        NSLog(@"editOpenVPNConfigurationFileMenuItemWasClicked but no configuration selected");
    }
    
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

-(IBAction) logToClipboardButtonWasClicked: (id) sender
{
    if (  [self selectedConnection]  ) {
        NSTextStorage * store = [[configurationsPrefsView logView] textStorage];
        NSPasteboard * pb = [NSPasteboard generalPasteboard];
        [pb declareTypes: [NSArray arrayWithObject: NSStringPboardType] owner: self];
        [pb setString: [store string] forType: NSStringPboardType];
    } else {
        NSLog(@"logToClipboardButtonWasClicked but no configuration selected");
    }
}


// Settings tab

-(IBAction) whenToConnectManuallyMenuItemWasClicked: (id) sender
{
    if (  [self selectedConnection]  ) {
        [self setSelectedWhenToConnectIndex: 0];
    } else {
        NSLog(@"whenToConnectManuallyMenuItemWasClicked but no configuration selected");
    }
}


-(IBAction) whenToConnectTunnelblickLaunchMenuItemWasClicked: (id) sender
{
    if (  [self selectedConnection]  ) {
        [self setSelectedWhenToConnectIndex: 1];
    } else {
        NSLog(@"whenToConnectTunnelblickLaunchMenuItemWasClicked but no configuration selected");
    }
}


-(IBAction) whenToConnectOnComputerStartMenuItemWasClicked: (id) sender
{
    if (  [self selectedConnection]  ) {
        NSString * configurationPath = [[self selectedConnection] configPath];
        BOOL enableWhenComputerStarts = ! [configurationPath hasPrefix: gPrivatePath];
        if (  enableWhenComputerStarts  ) {
            [self setSelectedWhenToConnectIndex: 2];
        } else {
            NSInteger ix = selectedWhenToConnectIndex;
            selectedWhenToConnectIndex = 2;
            [[configurationsPrefsView whenToConnectPopUpButton] selectItemAtIndex: ix];
            [self setSelectedWhenToConnectIndex: ix];
            TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                            NSLocalizedString(@"Private configurations cannot connect when the computer starts.\n\n"
                                              "First make the configuration shared, then change this setting.", @"Window text"),
                            nil, nil, nil);
        }
    } else {
        NSLog(@"whenToConnectOnComputerStartMenuItemWasClicked but no configuration selected");
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
        [[configurationsPrefsView monitorNetworkForChangesCheckbox] setState: state];
    }
}

-(IBAction) monitorNetworkForChangesCheckboxWasClicked: (id) sender
{
    if (  [self selectedConnection]  ) {
        [self changeBooleanPreference: @"-notMonitoringConnection"
                                   to: ([sender state] == NSOnState)
                             inverted: YES];
        
        [settingsSheetWindowController monitorNetworkForChangesCheckboxChangedForConnection: [self selectedConnection]];
    } else {
        NSLog(@"monitorNetworkForChangesCheckboxWasClicked but no configuration selected");
    }
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
        NSLog(@"advancedButtonWasClicked but no configuration selected");
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
    
    [[configurationsPrefsView whenToConnectPopUpButton] selectItemAtIndex: ix];
    [[configurationsPrefsView whenToConnectOnComputerStartMenuItem] setEnabled: enableWhenComputerStarts];
    
    BOOL enable = (   [gTbDefaults canChangeValueForKey: autoConnectKey]
                   && [gTbDefaults canChangeValueForKey: ossKey]          );
    [[configurationsPrefsView whenToConnectPopUpButton] setEnabled: enable];
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
            || ([[[configurationsPrefsView setNameserverArrayController] content] count] < 4)  ) {
            [[configurationsPrefsView monitorNetworkForChangesCheckbox] setState: NSOffState];
            [[configurationsPrefsView monitorNetworkForChangesCheckbox] setEnabled: NO];
        } else {
            [self setupCheckbox: [configurationsPrefsView monitorNetworkForChangesCheckbox]
                            key: @"-notMonitoringConnection"
                       inverted: YES];
            [[configurationsPrefsView monitorNetworkForChangesCheckbox] setEnabled: YES];
        }
        [settingsSheetWindowController monitorNetworkForChangesCheckboxChangedForConnection: [self selectedConnection]];
        
    }
}

-(void) tableViewSelectionDidChange:(NSNotification *)notification
{
    [self performSelectorOnMainThread: @selector(selectedLeftNavListIndexChanged) withObject: nil waitUntilDone: NO];
}

-(void) selectedLeftNavListIndexChanged
{
    int n = [[configurationsPrefsView leftNavTableView] selectedRow];
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
        [[configurationsPrefsView leftNavTableView] selectRowIndexes: [NSIndexSet indexSetWithIndex: newValue] byExtendingSelection: NO];
        
        VPNConnection* newConnection = [self selectedConnection];
        NSString * dispNm = [newConnection displayName];
        [[configurationsPrefsView configurationNameTFC] setTitle: [NSString stringWithFormat: @"%@:", dispNm]];
        [[self window] setTitle: [self windowTitle: NSLocalizedString(@"Configurations", @"Window title")]];
        
        NSString * status = localizeNonLiteral([newConnection state], @"Connection status");
        [[configurationsPrefsView configurationStatusTFC] setTitle: status];
        
        [self validateDetailsWindowControls];
        [newConnection startMonitoringLogFiles];
        
        [previouslySelectedNameOnLeftNavList release];
        previouslySelectedNameOnLeftNavList = [dispNm retain];
        
        [settingsSheetWindowController setConfigurationName: dispNm];
        
        [newConnection startMonitoringLogFiles];
    }
}

TBSYNTHESIZE_NONOBJECT_GET(NSInteger, selectedWhenToConnectIndex)
TBSYNTHESIZE_NONOBJECT_GET(NSInteger, selectedSetNameserverIndex)
TBSYNTHESIZE_NONOBJECT_GET(NSInteger, selectedLeftNavListIndex)


//***************************************************************************************************************

-(void) setupGeneralView
{
    // Select values for the configurations checkboxes
    
    [self setValueForCheckbox: [generalPrefsView useShadowCopiesCheckbox]
                preferenceKey: @"useShadowConfigurationFiles"
                     inverted: NO
                   defaultsTo: FALSE];
    
    [self setValueForCheckbox: [generalPrefsView monitorConfigurationFolderCheckbox]
                preferenceKey: @"doNotMonitorConfigurationFolder"
                     inverted: YES
                   defaultsTo: FALSE];
    
    // Select value for the update automatically checkbox and set the last update date/time
    [self setValueForCheckbox: [generalPrefsView updatesCheckAutomaticallyCheckbox]
                preferenceKey: @"updateCheckAutomatically"
                     inverted: NO
                   defaultsTo: TRUE];
    
    
    // Set the last update date/time
    [self updateLastCheckedDate];

    
    // Select the keyboard shortcut
    
    unsigned kbsIx = 1; // F1 is the default
    NSNumber * ixNumber = [gTbDefaults objectForKey: @"keyboardShortcutIndex"];
    unsigned kbsCount = [[[generalPrefsView keyboardShortcutArrayController] content] count];
    if (   ixNumber  ) {
        unsigned ix = [ixNumber unsignedIntValue];
        if (  ix < kbsCount  ) {
            kbsIx = ix;
        }
    }
    if (  kbsIx < kbsCount  ) {
        [self setSelectedKeyboardShortcutIndex: kbsIx];
    }
    
    [[generalPrefsView keyboardShortcutButton] setEnabled: [gTbDefaults canChangeValueForKey: @"keyboardShortcutIndex"]];
    
    // Select the log size
    
    unsigned prefSize = 102400;
    id logSizePref = [gTbDefaults objectForKey: @"maxLogDisplaySize"];
    if (  logSizePref  ) {
        if (  [logSizePref respondsToSelector:@selector(intValue)]  ) {
            prefSize = [logSizePref intValue];
        } else {
            NSLog(@"'maxLogDisplaySize' preference is invalid.");
        }
    }
    
    int logSizeIx = -1;
    NSArrayController * ac = [generalPrefsView maximumLogSizeArrayController];
    NSArray * list = [ac content];
    int i;
    for (  i=0; i<[list count]; i++  ) {
        NSDictionary * dict = [list objectAtIndex: i];
        NSString * listValue = [dict objectForKey: @"value"];
        unsigned listValueSize;
        if (  [listValue respondsToSelector:@selector(intValue)]  ) {
            listValueSize = [listValue intValue];
        } else {
            NSLog(@"'value' entry in %@ is invalid.", dict);
            listValueSize = UINT_MAX;
        }
        
        if (  listValueSize == prefSize  ) {
            logSizeIx = i;
            break;
        }
        
        if (  listValueSize > prefSize  ) {
            logSizeIx = i;
            NSLog(@"'maxLogDisplaySize' preference is invalid.");
            break;
        }
    }
    
    if (  logSizeIx == -1  ) {
        NSLog(@"'maxLogDisplaySize' preference value of '%@' is not available", logSizePref);
        logSizeIx = 2;  // Second one should be '102400'
    }
    
    if (  logSizeIx < [list count]  ) {
        [self setSelectedMaximumLogSizeIndex: logSizeIx];
    } else {
        NSLog(@"Invalid selectedMaximumLogSizeIndex %d; maximum is %d", logSizeIx, [list count]-1);
    }
    
    [[generalPrefsView maximumLogSizeButton] setEnabled: [gTbDefaults canChangeValueForKey: @"maxLogDisplaySize"]];
}


-(void) updateLastCheckedDate
{
    NSDate * lastCheckedDate = [gTbDefaults objectForKey: @"SULastCheckTime"];
    NSString * lastChecked = [lastCheckedDate descriptionWithCalendarFormat: @"%Y-%m-%d %H:%M" timeZone: nil locale: [[NSUserDefaults standardUserDefaults] dictionaryRepresentation]];
    if (  ! lastChecked  ) {
        lastChecked = NSLocalizedString(@"(Never checked)", @"Window text");
    }
    [[generalPrefsView updatesLastCheckedTFC] setTitle: [NSString stringWithFormat:
                                                         NSLocalizedString(@"Last checked: %@", @"Window text"),
                                                         lastChecked]];
}


-(IBAction) useShadowCopiesCheckboxWasClicked: (id) sender
{
	if (  [sender state]  ) {
		[gTbDefaults setBool: TRUE  forKey:@"useShadowConfigurationFiles"];
	} else {
		[gTbDefaults setBool: FALSE forKey:@"useShadowConfigurationFiles"];
	}
}


-(IBAction) monitorConfigurationFolderCheckboxWasClicked: (id) sender
{
	if (  [sender state]  ) {
		[gTbDefaults setBool: FALSE forKey:@"doNotMonitorConfigurationFolder"];
	} else {
		[gTbDefaults setBool: TRUE  forKey:@"doNotMonitorConfigurationFolder"];
	}
    
    [[NSApp delegate] changedMonitorConfigurationFoldersSettings];
}


-(IBAction) updatesCheckAutomaticallyCheckboxWasClicked: (id) sender
{
    SUUpdater * updater = [[NSApp delegate] updater];
    if (  [updater respondsToSelector: @selector(setAutomaticallyChecksForUpdates:)]  ) {
        [[NSApp delegate] setupSparklePreferences]; // Sparkle may have changed it's preferences so we update ours
        if (  ! [gTbDefaults boolForKey:@"updateCheckAutomatically"]  ) {
            // Was OFF, trying to change to ON
            if (  [[NSApp delegate] appNameIsTunnelblickWarnUserIfNot: NO]  ) {
                [gTbDefaults setBool: TRUE forKey: @"updateCheckAutomatically"];
                [updater setAutomaticallyChecksForUpdates: YES];
            } else {
                NSLog(@"'Automatically Check for Updates' change ignored because the name of the application has been changed");
            }
        } else {
            // Was ON, change to OFF
            [gTbDefaults setBool: FALSE forKey: @"updateCheckAutomatically"];
            [updater setAutomaticallyChecksForUpdates: NO];
        }
    } else {
        NSLog(@"'Automatically Check for Updates' change ignored because Sparkle Updater does not respond to setAutomaticallyChecksForUpdates:");
    }
}


-(IBAction) updatesCheckNowButtonWasClicked: (id) sender
{
    [[NSApp delegate] checkForUpdates: self];
    [self updateLastCheckedDate];
}


-(IBAction) resetDisabledWarningsButtonWasClicked: (id) sender
{
    NSString * key;
    NSEnumerator * arrayEnum = [gProgramPreferences objectEnumerator];
    while (   key = [arrayEnum nextObject]  ) {
        if (  [key hasPrefix: @"skipWarning"]  ) {
            if (  [gTbDefaults objectForKey: key]  ) {
                if (  [gTbDefaults canChangeValueForKey: key]  ) {
                    [gTbDefaults removeObjectForKey: key];
                }
            }
        }
    }
    
    arrayEnum = [gConfigurationPreferences objectEnumerator];
    while (   key = [arrayEnum nextObject]  ) {
        if (  [key hasPrefix: @"-skipWarning"]  ) {
            [gTbDefaults removeAllObjectsWithSuffix: key];
        }
    }
}


-(IBAction) generalHelpButtonWasClicked: (id) sender
{
    OSStatus err;
    if (err = MyGotoHelpPage(CFSTR("preferences-general.html"), NULL)  ) {
        NSLog(@"Error %d from MyGotoHelpPage()", err);
    }
}


-(NSInteger) selectedKeyboardShortcutIndex
{
    return selectedKeyboardShortcutIndex;
}


-(void) setSelectedKeyboardShortcutIndex: (NSInteger) newValue
{
    if (  newValue != selectedKeyboardShortcutIndex  ) {
        NSArrayController * ac = [generalPrefsView keyboardShortcutArrayController];
        NSArray * list = [ac content];
        if (  newValue < [list count]  ) {
            selectedKeyboardShortcutIndex = newValue;
            
            // Select the new size
            NSArrayController * ac = [generalPrefsView keyboardShortcutArrayController];
            [ac setSelectionIndex: newValue];
            
            // Set the preference
            [gTbDefaults setObject: [NSNumber numberWithUnsignedInt: newValue] forKey: @"keyboardShortcutIndex"];
            
            // Set the value we use
            [[NSApp delegate] setHotKeyIndex: newValue];
        }
    }
}    


-(NSInteger) selectedMaximumLogSizeIndex
{
    return selectedMaximumLogSizeIndex;
}


-(void) setSelectedMaximumLogSizeIndex: (NSInteger) newValue
{
    if (  newValue != selectedMaximumLogSizeIndex  ) {
        NSArrayController * ac = [generalPrefsView maximumLogSizeArrayController];
        NSArray * list = [ac content];
        if (  newValue < [list count]  ) {
            selectedMaximumLogSizeIndex = newValue;
            
            // Select the new size
            NSArrayController * ac = [generalPrefsView maximumLogSizeArrayController];
            [ac setSelectionIndex: newValue];
            
            // Set the preference
            NSString * newPref = [[list objectAtIndex: newValue] objectForKey: @"value"];
            [gTbDefaults setObject: newPref forKey: @"maxLogDisplaySize"];
            
            // Set the value we use
            gMaximumLogSize = [newPref intValue];
        }
    }
}

//***************************************************************************************************************

-(void) setupAppearanceView
{
    // Select value for icon set popup
    
    NSString * defaultIconSetName    = @"TunnelBlick.TBMenuIcons";
    
    NSString * iconSetToUse = [gTbDefaults objectForKey: @"menuIconSet"];
    if (  ! iconSetToUse  ) {
        iconSetToUse = defaultIconSetName;
    }
    
    // Search popup list for the specified filename and the default
    NSArray * icsContent = [[appearancePrefsView appearanceIconSetArrayController] content];
    int i;
    int iconSetIx = -1;
    int defaultIconSetIx = -1;
    for (  i=0; i< [icsContent count]; i++  ) {
        NSDictionary * dict = [icsContent objectAtIndex: i];
        NSString * fileName = [dict objectForKey: @"value"];
        if (  [fileName isEqualToString: iconSetToUse]  ) {
            iconSetIx = i;
        }
        if (  [fileName isEqualToString: defaultIconSetName]  ) {
            defaultIconSetIx = i;
        }
    }

    if (  iconSetIx == -1) {
        iconSetIx = defaultIconSetIx;
    }
    
    if (  iconSetIx == -1  ) {
        if (  [icsContent count] > 0) {
            if (  [iconSetToUse isEqualToString: defaultIconSetName]) {
                NSLog(@"Could not find '%@' icon set or default icon set; using first set found", iconSetToUse);
                iconSetIx = 1;
            } else {
                NSLog(@"Could not find '%@' icon set; using default icon set", iconSetToUse);
                iconSetIx = defaultIconSetIx;
            }
        } else {
            NSLog(@"Could not find any icon sets");
        }
    }
    
    if (  iconSetIx == -1  ) {
         [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"(None available)", @"Button"), "name", @"", "value", nil];
        [self setSelectedAppearanceIconSetIndex: 0];
    } else {
        [self setSelectedAppearanceIconSetIndex: iconSetIx];
    }
    
    [[appearancePrefsView appearanceIconSetButton] setEnabled: [gTbDefaults canChangeValueForKey: @"menuIconSet"]];

    // Set up the checkboxes
    
    [self setValueForCheckbox: [appearancePrefsView appearanceDisplayConnectionSubmenusCheckbox]
                preferenceKey: @"doNotShowConnectionSubmenus"
                     inverted: YES
                   defaultsTo: FALSE];
    
    [self setValueForCheckbox: [appearancePrefsView appearanceDisplayConnectionTimersCheckbox]
                preferenceKey: @"showConnectedDurations"
                     inverted: NO
                   defaultsTo: FALSE];
    
    [self setValueForCheckbox: [appearancePrefsView appearancePlaceIconNearSpotlightCheckbox]
                preferenceKey: @"placeIconInStandardPositionInStatusBar"
                     inverted: YES
                   defaultsTo: FALSE];
    
    // Set up connection window display criteria
    
    NSString * displayCriteria = [gTbDefaults objectForKey: @"connectionWindowDisplayCriteria"];
    if (  ! displayCriteria  ) {
        displayCriteria = @"showWhenConnecting";
    }
    
    int displayCriteriaIx = -1;
    NSArrayController * ac = [appearancePrefsView appearanceConnectionWindowDisplayCriteriaArrayController];
    NSArray * list = [ac content];
    for (  i=0; i<[list count]; i++  ) {
        NSDictionary * dict = [list objectAtIndex: i];
        NSString * preferenceValue = [dict objectForKey: @"value"];
        if (  [preferenceValue isEqualToString: displayCriteria]  ) {
            displayCriteriaIx = i;
            break;
        }
    }
    if (  displayCriteriaIx == -1  ) {
        NSLog(@"'connectionWindowDisplayCriteria' preference value of '%@' is not available", displayCriteria);
        displayCriteriaIx = 0;  // First one should be 'showWhenConnecting'
    }
    
    if (  displayCriteriaIx < [list count]  ) {
        [self setSelectedAppearanceConnectionWindowDisplayCriteriaIndex: displayCriteriaIx];
    } else {
        NSLog(@"Invalid displayCriteriaIx %d; maximum is %d", displayCriteriaIx, [list count]-1);
    }
    
    [[appearancePrefsView appearanceConnectionWindowDisplayCriteriaButton] setEnabled: [gTbDefaults canChangeValueForKey: @"connectionWindowDisplayCriteria"]];
}


-(IBAction) appearanceDisplayConnectionSubmenusCheckboxWasClicked: (id) sender
{
	if (  [sender state]  ) {
		[gTbDefaults setBool: FALSE forKey:@"doNotShowConnectionSubmenus"];
	} else {
		[gTbDefaults setBool: TRUE  forKey:@"doNotShowConnectionSubmenus"];
	}
    
    [[NSApp delegate] changedDisplayConnectionSubmenusSettings];
}

-(IBAction) appearanceDisplayConnectionTimersCheckboxWasClicked: (id) sender
{
	if (  [sender state]  ) {
		[gTbDefaults setBool: TRUE  forKey:@"showConnectedDurations"];
	} else {
		[gTbDefaults setBool: FALSE forKey:@"showConnectedDurations"];
	}
    
    [[NSApp delegate] changedDisplayConnectionTimersSettings];
}

-(IBAction) appearancePlaceIconNearSpotlightCheckboxWasClicked: (id) sender
{
	if (  [sender state]  ) {
		[gTbDefaults setBool: FALSE forKey:@"placeIconInStandardPositionInStatusBar"];
	} else {
		[gTbDefaults setBool: TRUE  forKey:@"placeIconInStandardPositionInStatusBar"];
	}
    
    // Start using the new setting
    [[NSApp delegate] createStatusItem];
}

-(IBAction) appearanceHelpButtonWasClicked: (id) sender
{
    OSStatus err;
    if (err = MyGotoHelpPage(CFSTR("preferences-appearance.html"), NULL)  ) {
        NSLog(@"Error %d from MyGotoHelpPage()", err);
    }
}


-(NSInteger) selectedAppearanceIconSetIndex
{
    return selectedAppearanceIconSetIndex;
}

-(void) setSelectedAppearanceIconSetIndex: (NSInteger) newValue
{
    if (  newValue != selectedAppearanceIconSetIndex  ) {
        NSArrayController * ac = [appearancePrefsView appearanceIconSetArrayController];
        NSArray * list = [ac content];
        if (  newValue < [list count]  ) {
            selectedAppearanceIconSetIndex = newValue;
            
            // Select the new index
            [ac setSelectionIndex: newValue];
            
            // Set the preference
            NSString * iconSetName = [[[list objectAtIndex: newValue] objectForKey: @"value"] lastPathComponent];
            [gTbDefaults setObject: iconSetName forKey: @"menuIconSet"];
            
            // Start using the new setting
            [[NSApp delegate] loadMenuIconSet];
        }
    }
}

-(NSInteger) selectedAppearanceConnectionWindowDisplayCriteriaIndex
{
    return selectedAppearanceConnectionWindowDisplayCriteriaIndex;
}


-(void) setSelectedAppearanceConnectionWindowDisplayCriteriaIndex: (NSInteger) newValue
{
    if (  newValue != selectedAppearanceConnectionWindowDisplayCriteriaIndex  ) {
        NSArrayController * ac = [appearancePrefsView appearanceConnectionWindowDisplayCriteriaArrayController];
        NSArray * list = [ac content];
        if (  newValue < [list count]  ) {
            selectedAppearanceConnectionWindowDisplayCriteriaIndex = newValue;
            
            // Select the new index
            [ac setSelectionIndex: newValue];
            
            // Set the preference
            NSDictionary * dict = [list objectAtIndex: newValue];
            NSString * preferenceValue = [dict objectForKey: @"value"];
            [gTbDefaults setObject: preferenceValue forKey: @"connectionWindowDisplayCriteria"];
            
            // Start using the new setting
        }
    }
}

-(IBAction) infoHelpButtonWasClicked: (id) sender
{
    OSStatus err;
    if (err = MyGotoHelpPage(CFSTR("info.html"), NULL)  ) {
        NSLog(@"Error %d from MyGotoHelpPage()", err);
    }
}


//***************************************************************************************************************

-(void) setupInfoView
{
}

//***************************************************************************************************************

-(void) setValueForCheckbox: (NSButton *) checkbox
              preferenceKey: (NSString *) preferenceKey
                   inverted: (BOOL)       inverted
                 defaultsTo: (BOOL)       defaultsTo
{
    int value = defaultsTo;
    if (  inverted  ) {
        value = ! value;
    }
    
    id obj = [gTbDefaults objectForKey: preferenceKey];
    if (  obj != nil  ) {
        if (  [obj respondsToSelector: @selector(intValue)]  ) {
            if (  inverted  ) {
                value = ( [obj intValue] == 0 );
            } else {
                value = ( [obj intValue] != 0 );
            }
        } else {
            NSLog(@"'%@' preference value is '%@', which is not recognized as TRUE or FALSE", preferenceKey, obj);
        }
    }
    [checkbox setState: value];
    [checkbox setEnabled: [gTbDefaults canChangeValueForKey: preferenceKey]];
}

-(void) setSoundIndex: (NSInteger *) index
                   to: (NSInteger)   newValue
           preference: (NSString *)  preference
{
    if (  newValue != *index  ) {
        NSInteger size = [[configurationsPrefsView sortedSounds] count];
        if (  newValue < size + 1  ) {
            if (  *index != NSNotFound  ) {
                NSString * key = [[[self selectedConnection] displayName] stringByAppendingString: preference];
                NSString * newName;
                if (  newValue == 0) {
                    newName = @"None";
                    VPNConnection * connection = [self selectedConnection];
                    if (  [preference hasSuffix: @"tunnelUpSoundName"]  ) {
                        [connection setTunnelUpSound: nil];
                    } else {
                        [connection setTunnelDownSound: nil];
                    }
                } else {
                    newName = [[configurationsPrefsView sortedSounds] objectAtIndex: newValue - 1];
                    NSSound * sound = [NSSound soundNamed: newName];
                    if (  sound  ) {
                        VPNConnection * connection = [self selectedConnection];
                        if (  [preference hasSuffix: @"tunnelUpSoundName"]  ) {
                            [connection setTunnelUpSound: sound];
                        } else {
                            [connection setTunnelDownSound: sound];
                        }
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

-(NSTextView *) logView
{
    return [configurationsPrefsView logView];
}

TBSYNTHESIZE_OBJECT_GET(retain, ConfigurationsView *, configurationsPrefsView)

TBSYNTHESIZE_OBJECT_SET(NSString *, currentViewName, setCurrentViewName)

@end
