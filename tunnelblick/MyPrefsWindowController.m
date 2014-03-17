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


#import <asl.h>
#import "MyPrefsWindowController.h"
#import "TBUserDefaults.h"
#import "ConfigurationManager.h"
#import "MenuController.h"
#import "NSApplication+LoginItem.h"
#import "NSFileManager+TB.h"
#import "NSString+TB.h"
#import "helper.h"
#import "ConfigurationsView.h"
#import "GeneralView.h"
#import "AppearanceView.h"
#import "InfoView.h"
#import "UtilitiesView.h"
#import "SettingsSheetWindowController.h"
#import "Sparkle/SUUpdater.h"
#import "MainIconView.h"
#import "easyRsa.h"
#import "LeftNavItem.h"
#import "LeftNavDataSource.h"
#import "LeftNavViewController.h"

extern NSFileManager  * gFileMgr;
extern TBUserDefaults * gTbDefaults;
extern NSString       * gPrivatePath;
extern NSString       * gDeployPath;
extern unsigned         gMaximumLogSize;
extern NSArray        * gProgramPreferences;
extern NSArray        * gConfigurationPreferences;

@interface MyPrefsWindowController()

-(void) setupViews;
-(void) setupConfigurationsView;
-(void) setupGeneralView;
-(void) setupAppearanceView;
-(void) setupUtilitiesView;
-(void) setupInfoView;

-(unsigned) firstDifferentComponent: (NSArray *) a
                                and: (NSArray *) b;

-(NSString *) indent: (NSString *) s
                  by: (unsigned)   n;

-(void) initializeSoundPopUpButtons;

-(void) setCurrentViewName: (NSString *) newName;

-(void) setSelectedWhenToConnectIndex: (NSUInteger) newValue;

-(void) setSoundIndex: (NSUInteger *) index
                   to: (NSUInteger)   newValue
           preference: (NSString *)  preference;

-(void) setupCheckbox: (NSButton *) checkbox
                  key: (NSString *) key
             inverted: (BOOL) inverted;

-(void) setupLeftNavigationToDisplayName: (NSString *) displayNameToSelect;

-(void) setupSetNameserver:           (VPNConnection *) connection;
-(void) setupKeepConnected:           (VPNConnection *) connection;
-(void) setupPerConfigOpenvpnVersion: (VPNConnection *) connection;
-(void) setupNetworkMonitoring:       (VPNConnection *) connection;
-(void) setupSoundPopUpButtons:       (VPNConnection *) connection;

-(void) setupSoundButton: (NSButton *)          button
         arrayController: (NSArrayController *) ac
              preference: (NSString *)          preference;

-(void) setValueForCheckbox: (NSButton *) checkbox
              preferenceKey: (NSString *) preferenceKey
                   inverted: (BOOL)       inverted
                 defaultsTo: (BOOL)       defaultsTo;

-(void) updateConnectionStatusAndTime;

-(void) updateLastCheckedDate;

-(void) validateWhenToConnect: (VPNConnection *) connection;

@end

@implementation MyPrefsWindowController

-(void) dealloc {
	
    [currentViewName                     release]; currentViewName                     = nil;
	[previouslySelectedNameOnLeftNavList release]; previouslySelectedNameOnLeftNavList = nil;
	[leftNavList                         release]; leftNavList = nil;
	[leftNavDisplayNames                 release]; leftNavDisplayNames = nil;
    [settingsSheetWindowController       release]; settingsSheetWindowController = nil;
	
    [super dealloc];
}

+ (NSString *)nibName
// Overrides DBPrefsWindowController method
{
	if (   runningOnSnowLeopardOrNewer()  // 10.5 and lower don't have setDelegate and setDataSource
		&& ( ! [gTbDefaults boolForKey: @"doNotShowOutlineViewOfConfigurations"] )  ) {
		return @"Preferences";
	} else {
		return @"Preferences-pre-10.6";
	}

}


-(void) setupToolbar
{
    [self addView: configurationsPrefsView  label: NSLocalizedString(@"Configurations", @"Window title") image: [NSImage imageNamed: @"Configurations"]];
    [self addView: appearancePrefsView      label: NSLocalizedString(@"Appearance",     @"Window title") image: [NSImage imageNamed: @"Appearance"    ]];
    [self addView: generalPrefsView         label: NSLocalizedString(@"Preferences",    @"Window title") image: [NSImage imageNamed: @"Preferences"   ]];
    [self addView: utilitiesPrefsView       label: NSLocalizedString(@"Utilities",      @"Window title") image: [NSImage imageNamed: @"Utilities"     ]];
    [self addView: infoPrefsView            label: NSLocalizedString(@"Info",           @"Window title") image: [NSImage imageNamed: @"Info"          ]];
    
    [self setupViews];
    
    [[self window] setDelegate: self];
}

static BOOL firstTimeShowingWindow = TRUE;

-(void) setupViews
{
    
    currentFrame = NSMakeRect(0.0, 0.0, 760.0, 390.0);
    
    currentViewName = @"Configurations";
    
    selectedPerConfigOpenvpnVersionIndex                   = UINT_MAX;
    selectedKeyboardShortcutIndex                          = UINT_MAX;
    selectedMaximumLogSizeIndex                            = UINT_MAX;
    selectedAppearanceIconSetIndex                         = UINT_MAX;
    selectedAppearanceConnectionWindowDisplayCriteriaIndex = UINT_MAX;
    selectedAppearanceConnectionWindowScreenIndex          = UINT_MAX;
    
    [self setupConfigurationsView];
    [self setupGeneralView];
    [self setupAppearanceView];
    [self setupUtilitiesView];
    [self setupInfoView];
}


- (IBAction)showWindow:(id)sender 
{
    [super showWindow: sender];
    
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
        } else {
			[[self window] center];
            [[self window] setReleasedWhenClosed: NO];
		}

        firstTimeShowingWindow = FALSE;
    }
}


-(void) windowWillClose:(NSNotification *)notification
{
	(void) notification;
	
    if (  [currentViewName isEqualToString: @"Info"]  ) {
        [infoPrefsView oldViewWillDisappear: infoPrefsView identifier: @"Info"];
    }
    
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
		NSWindow * w = [view window];
        [w setShowsResizeIndicator: NO];
		windowContentMinSize = [w contentMinSize];	// Don't allow size changes except in 'Configurations' view
		windowContentMaxSize = [w contentMaxSize];	// But remember min & max for when we restore 'Configurations' view
		NSRect f = [w frame];
		NSSize s = [w contentRectForFrameRect: f].size;
        [w setContentMinSize: s];
		[w setContentMaxSize: s];
		
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
		NSWindow * w = [view window];
        [w setShowsResizeIndicator: YES];
		[w setContentMinSize: windowContentMinSize];
		[w setContentMaxSize: windowContentMaxSize];        
        [[self selectedConnection] startMonitoringLogFiles];
    } else {
        [appearancePrefsView setFrame: currentFrame];
        [generalPrefsView    setFrame: currentFrame];        
        [utilitiesPrefsView  setFrame: currentFrame];
        [infoPrefsView       setFrame: currentFrame];
    }
	
	if (  [identifier isEqualToString: @"Preferences"]) {
		// Update our preferences from Sparkle's whenever we show the view
		// (Would be better if Sparkle told us when they changed, but it doesn't)
		[[NSApp delegate] setOurPreferencesFromSparkles];
		[self setupGeneralView];
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
    } else if (   view == utilitiesPrefsView  ) {
        [[self window] makeFirstResponder: [utilitiesPrefsView utilitiesHelpButton]];
    } else if (   view == infoPrefsView  ) {
        [[self window] makeFirstResponder: [infoPrefsView infoHelpButton]];
        NSString * deployedString = (  gDeployPath && [gFileMgr fileExistsAtPath: gDeployPath]
                                     ? NSLocalizedString(@" (Deployed)", @"Window title")
                                     : @"");
        NSString * version = [NSString stringWithFormat: @"%@%@", tunnelblickVersion([NSBundle mainBundle]), deployedString];
        [[infoPrefsView infoVersionTFC] setTitle: version];
    } else {
        NSLog(@"newViewDidAppear:identifier: invoked with unknown view");
    }
}

    -(BOOL) tabView: (NSTabView *) inTabView shouldSelectTabViewItem: (NSTabViewItem *) tabViewItem
{
	(void) inTabView;
	(void) tabViewItem;
		
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


-(BOOL) oneConfigurationIsSelected {
	
	if (   runningOnSnowLeopardOrNewer()
		&& ( ! [gTbDefaults boolForKey: @"doNotShowOutlineViewOfConfigurations"] )  ) {
		LeftNavViewController   * ovc    = [configurationsPrefsView outlineViewController];
		NSOutlineView           * ov     = [ovc outlineView];
		NSIndexSet              * idxSet = [ov selectedRowIndexes];
		return [idxSet count] == 1;
	}
	
	return TRUE;
}

-(void) setupConfigurationsView
{
	
	BOOL savedDoingSetupOfUI = [[NSApp delegate] doingSetupOfUI];
	[[NSApp delegate] setDoingSetupOfUI: TRUE];

    selectedSetNameserverIndex     = NSNotFound;   // Force a change when first set
    selectedWhenToConnectIndex     = NSNotFound;
    selectedPerConfigOpenvpnVersionIndex = NSNotFound;
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
    previouslySelectedNameOnLeftNavList = [[gTbDefaults objectForKey: @"leftNavSelectedDisplayName"] retain];

    authorization = 0;
    doNotPlaySounds = FALSE;
    
    [self initializeSoundPopUpButtons];
    
	[self setupLeftNavigationToDisplayName: previouslySelectedNameOnLeftNavList];
	
    // Right split view
    
    [[configurationsPrefsView configurationsTabView] setDelegate: self];
    
    VPNConnection * connection = [self selectedConnection];
    
    // Right split view - Settings tab

    if (  connection  ) {
    
        [self updateConnectionStatusAndTime];
        
        [self indicateNotWaitingForConnection: [self selectedConnection]];
        [self validateWhenToConnect: [self selectedConnection]];
        
        [self setupSetNameserver:           [self selectedConnection]];
        [self setupKeepConnected:           [self selectedConnection]];
        [self setupNetworkMonitoring:       [self selectedConnection]];
        [self setupPerConfigOpenvpnVersion: [self selectedConnection]];
        [self setupSoundPopUpButtons:       [self selectedConnection]];
        
        // Set up a timer to update connection times
        [[NSApp delegate] startOrStopDurationsTimer];
    }
    
    [self validateDetailsWindowControls];   // Set windows enabled/disabled
	
	[[NSApp delegate] setDoingSetupOfUI: savedDoingSetupOfUI];
}


-(void) setupSetNameserver: (VPNConnection *) connection
{
    
    if (  ! connection  ) {
        return;
    }
    
    if (  ! configurationsPrefsView  ) {
        return;
    }
    
    // Set up setNameserverPopUpButton with localized content that varies with the connection
    NSInteger ix = 0;
    NSArray * content = [connection modifyNameserverOptionList];
    [[configurationsPrefsView setNameserverArrayController] setContent: content];
    [[configurationsPrefsView setNameserverPopUpButton] sizeToFit];
    
    // Select the appropriate Set nameserver entry
    NSString * key = [[connection displayName] stringByAppendingString: @"useDNS"];
    id obj = [gTbDefaults objectForKey: key];
    if (  obj != nil  ) {
        if (  [obj respondsToSelector: @selector(intValue)]  ) {
            ix = [obj intValue];
            if (  (unsigned)ix >= [[[configurationsPrefsView setNameserverArrayController] content] count]  ) {
                NSLog(@"%@ preference ignored: value %ld too large", key, (long) ix);
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
    [self setSelectedSetNameserverIndex: (unsigned)ix];
    [[configurationsPrefsView setNameserverPopUpButton] setEnabled: [gTbDefaults canChangeValueForKey: key]];
    [settingsSheetWindowController setupSettingsFromPreferences];
}

-(void) setupNetworkMonitoring: (VPNConnection *) connection
{
 	(void) connection;
	
   if (  [self forceDisableOfNetworkMonitoring]  ) {
        [[configurationsPrefsView monitorNetworkForChangesCheckbox] setState: NSOffState];
        [[configurationsPrefsView monitorNetworkForChangesCheckbox] setEnabled: NO];
    } else {
        [self setupCheckbox: [configurationsPrefsView monitorNetworkForChangesCheckbox]
                        key: @"-notMonitoringConnection"
                   inverted: YES];
    }
}

-(void) setupKeepConnected: (VPNConnection *) connection
{
 	(void) connection;
	
	[self setupCheckbox: [configurationsPrefsView keepConnectedCheckbox]
					key: @"-keepConnected"
			   inverted: NO];
}

-(void) setupPerConfigOpenvpnVersion: (VPNConnection *) connection
{
    
	if (  ! connection  ) {
        return;
    }
    
    // Select the OpenVPN version
    NSString * key = [[connection displayName] stringByAppendingString: @"-openvpnVersion"];
    NSString * prefVersion = [gTbDefaults objectForKey: key];
    
    NSArrayController * ac = [configurationsPrefsView perConfigOpenvpnVersionArrayController];
    NSArray * list = [ac content];
    
    if (  [list count] < 3  ) {
        return; // Have not set up the list yet
    }
    
    NSString * lastValue = [[list objectAtIndex: [list count] - 2] objectForKey: @"value"]; // don't get "latest (xxx)" -- get last real OpenVPN version number
    
    BOOL warnAndUseLatestVersion = FALSE;
    
    unsigned openvpnVersionIx = UINT_MAX;   // Flag value as not set
    
    if (   ( ! prefVersion )
        || [prefVersion isEqualToString: @""]
            ) {
        openvpnVersionIx = 0;
        
    } else if ( [prefVersion isEqualToString: @"-"]  ) {
        openvpnVersionIx = [list count] - 1;
        
    } else if (  ! isSanitizedOpenvpnVersion(prefVersion)  ) {
        warnAndUseLatestVersion = TRUE;
        
    } else {
        unsigned i;
        for (  i=1; i<[list count]-1; i++  ) {                      // 1st array entry is "default (xxx)", last is "latest (xxx)", so don't try to match them
            NSDictionary * dict = [list objectAtIndex: i];
            NSString * thisValue = [dict objectForKey: @"value"];
            if (  [thisValue isEqualToString: prefVersion]  ) {
                openvpnVersionIx = i;
                break;
            }
        }
        
        if (  openvpnVersionIx == UINT_MAX  ) {
            warnAndUseLatestVersion = TRUE;
        }
    }
    
    if (  warnAndUseLatestVersion  ) {
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                        [NSString stringWithFormat: NSLocalizedString(@"OpenVPN version %@ is not available. Using the latest, version %@", @"Window text"),
                         prefVersion, lastValue],
                        nil, nil, nil);
        [gTbDefaults setObject: @"-" forKey: key];
        openvpnVersionIx = [list count] - 1;
    }
    
    if (  openvpnVersionIx < [list count]  ) {
        [self setSelectedPerConfigOpenvpnVersionIndex: openvpnVersionIx];
    } else {
        NSLog(@"setupPerConfigOpenvpnVersion: Invalid openvpnVersionIx %d; maximum is %ld", openvpnVersionIx, (long) [list count]-1);
    }
    
    [[configurationsPrefsView perConfigOpenvpnVersionButton] setEnabled: [gTbDefaults canChangeValueForKey: key]];
    
}

-(void) setupSoundPopUpButtons: (VPNConnection *) connection
{
	(void) connection;
	
    [self setupSoundButton: [configurationsPrefsView soundOnConnectButton]
           arrayController: [configurationsPrefsView soundOnConnectArrayController]
                preference: @"-tunnelUpSoundName"];
    
    
    [self setupSoundButton: [configurationsPrefsView soundOnDisconnectButton]
           arrayController: [configurationsPrefsView soundOnDisconnectArrayController]
                preference: @"-tunnelDownSoundName"];
}


-(void) setupLeftNavigationToDisplayName: (NSString *) displayNameToSelect
{
    int leftNavIndexToSelect = NSNotFound;
    
    NSMutableArray * currentFolders = [NSMutableArray array]; // Components of folder enclosing most-recent leftNavList/leftNavDisplayNames entry
    NSArray * allConfigsSorted = [[[[NSApp delegate] myVPNConnectionDictionary] allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveNumericCompare:)];
    
    // If the configuration we want to select is gone, don't try to select it
    if (  displayNameToSelect  ) {
        if (  ! [allConfigsSorted containsObject: displayNameToSelect]  ) {
            displayNameToSelect = nil;
        }
	}
	
    // If no display name to select and there are any names, select the first one
	if (  ! displayNameToSelect  ) {
        if (  [allConfigsSorted count] > 0  ) {
            displayNameToSelect = [allConfigsSorted objectAtIndex: 0];
        }
    }
	
	[leftNavList         release];
	[leftNavDisplayNames release];
	leftNavList         = [[NSMutableArray alloc] initWithCapacity: [[[NSApp delegate] myVPNConnectionDictionary] count]];
	leftNavDisplayNames = [[NSMutableArray alloc] initWithCapacity: [[[NSApp delegate] myVPNConnectionDictionary] count]];
	int currentLeftNavIndex = 0;
	
	NSEnumerator* configEnum = [allConfigsSorted objectEnumerator];
    NSString * dispNm;
    while (  (dispNm = [configEnum nextObject])  ) {
        VPNConnection * connection = [[[NSApp delegate] myVPNConnectionDictionary] objectForKey: dispNm];
		NSArray * currentConfig = [dispNm componentsSeparatedByString: @"/"];
		unsigned firstDiff = [self firstDifferentComponent: currentConfig and: currentFolders];
		
		// Track any necessary "outdenting"
		if (  firstDiff < [currentFolders count]  ) {
			// Remove components from the end of currentFolders until we have a match
			unsigned i;
			for (  i=0; i < ([currentFolders count]-firstDiff); i++  ) {
				[currentFolders removeLastObject];
			}
		}
		
		// currentFolders and currentConfig now match, up to but not including the firstDiff-th entry
		
		// Add a "folder" line for each folder in currentConfig starting with the first-Diff-th entry (if any)
		unsigned i;
		for (  i=firstDiff; i < [currentConfig count]-1; i++  ) {
			[leftNavDisplayNames addObject: @""];
			NSString * folderName = [currentConfig objectAtIndex: i];
			[leftNavList         addObject: [self indent: folderName by: i]];
			[currentFolders addObject: folderName];
			++currentLeftNavIndex;
		}
		
		// Add a "configuration" line
		[leftNavDisplayNames addObject: [connection displayName]];
		[leftNavList         addObject: [self indent: [currentConfig lastObject] by: [currentConfig count]-1u]];
		
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
	
	if (   runningOnSnowLeopardOrNewer()  // 10.5 and lower don't have setDelegate and setDataSource
		&& ( ! [gTbDefaults boolForKey: @"doNotShowOutlineViewOfConfigurations"] )  ) {
		
		LeftNavViewController * oVC = [[self configurationsPrefsView] outlineViewController];
        NSOutlineView         * oView = [oVC outlineView];
        LeftNavDataSource     * oDS = [[self configurationsPrefsView] leftNavDataSrc];
        [oDS reload];
		[oView reloadData];
		
		// Expand items that were left expanded previously and get row # we should select (that matches displayNameToSelect)
		
		NSInteger ix = 0;	// Track row # of name we are to display

		NSArray * expandedDisplayNames = [gTbDefaults objectForKey: @"leftNavOutlineViewExpandedDisplayNames"];
        LeftNavViewController * outlineViewController = [configurationsPrefsView outlineViewController];
        NSOutlineView * outlineView = [outlineViewController outlineView];
        [outlineView expandItem: [outlineView itemAtRow: 0]];
        NSInteger r;
        id item;
        for (  r=0; r<[outlineView numberOfRows]; r++) {
            item = [outlineView itemAtRow: r];
            NSString * itemDisplayName = [item displayName];
            if (  [itemDisplayName hasSuffix: @"/"]  ) {
                if (   [expandedDisplayNames containsObject: itemDisplayName]
                    || [displayNameToSelect hasPrefix: itemDisplayName]  ) {
                    [outlineView expandItem: item];
                }
            }
            if (  [displayNameToSelect isEqualToString: itemDisplayName]  ) {
                ix = r;
            }
        }
		
		if (  displayNameToSelect  ) {
			[oView selectRowIndexes: [NSIndexSet indexSetWithIndex: ix] byExtendingSelection: NO];
            [[[configurationsPrefsView outlineViewController] outlineView] scrollRowToVisible: ix];
		}
	}
	
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
            [self setSelectedLeftNavListIndex: (unsigned)leftNavIndexToSelect];
            [[configurationsPrefsView leftNavTableView] scrollRowToVisible: leftNavIndexToSelect];
        }
    } else {
        [self setupSetNameserver:           nil];
        [self setupKeepConnected:           nil];
        [self setupNetworkMonitoring:       nil];
		[self setupPerConfigOpenvpnVersion: nil];
        [self setupSoundPopUpButtons:       nil];
        [self validateDetailsWindowControls];
        [settingsSheetWindowController setConfigurationName: nil];
        
    }
}

// Call this when a configuration was added or deleted
-(void) update
{
    [self setupLeftNavigationToDisplayName: previouslySelectedNameOnLeftNavList];
    
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        NSString * newDisplayName = [connection displayName];
        [settingsSheetWindowController setConfigurationName: newDisplayName];
    } else {
        [[settingsSheetWindowController window] close];
    }
}


-(void)updateNavigationLabels {
    [self updateConnectionStatusAndTime];
}


-(void) updateConnectionStatusAndTime
{
	if (  [super windowHasLoaded]  ) {
		[[self window] setTitle: [self windowTitle: NSLocalizedString(@"Configurations", @"Window title")]];
	}
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
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        NSString * actualKey = [[connection displayName] stringByAppendingString: key];
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
}


-(void) initializeSoundPopUpButtons
{
    NSArray * soundsSorted = [[NSApp delegate] sortedSounds];
    
    // Create an array of dictionaries of sounds. (Don't get the actual sounds, just the names of the sounds)
    NSMutableArray * soundsDictionaryArray = [NSMutableArray arrayWithCapacity: [soundsSorted count]];
    
    [soundsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                       NSLocalizedString(@"No sound", @"Button"), @"name",
                                       @"None", @"value", nil]];
    
    [soundsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                       NSLocalizedString(@"Speak", @"Button"), @"name",
                                       @"Speak", @"value", nil]];
    
    unsigned i;
    for (  i=0; i<[soundsSorted count]; i++  ) {
        [soundsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys: 
                                           [soundsSorted objectAtIndex: i], @"name", 
                                           [soundsSorted objectAtIndex: i], @"value", nil]];
    }
    
    [[configurationsPrefsView soundOnConnectArrayController]    setContent: soundsDictionaryArray];
    [[configurationsPrefsView soundOnDisconnectArrayController] setContent: soundsDictionaryArray];
}


//  Set up a sound popup button from preferences
-(void) setupSoundButton: (NSButton *)          button
         arrayController: (NSArrayController *) ac
              preference: (NSString *)          preference
{
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        NSUInteger ix = NSNotFound;
        NSString * key = [[connection displayName] stringByAppendingString: preference];
        NSString * soundName = [gTbDefaults objectForKey: key];
        if (   soundName
            && ( ! [soundName isEqualToString: @"None"] )  ) {
            NSArray * listContent = [ac content];
            NSDictionary * dict;
            unsigned i;
            for (  i=0; i<[listContent count]; i++  ) {  // Look for the sound in the array
                dict = [listContent objectAtIndex: i];
                if (  [[dict objectForKey: @"name"] isEqualToString: soundName]  ) {
                    ix = i;
                    break;
                }
            }
            
            if (  ix == NSNotFound  ) {
                NSLog(@"Preference '%@' ignored: sound '%@' was not found", key, soundName);
                ix = 0;
            }
        } else {
            ix = 0;
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
}

-(void) validateDetailsWindowControls
{
    VPNConnection * connection = [self selectedConnection];
    
	[self updateConnectionStatusAndTime];
	
    if (  connection  ) {
        
        [self validateConnectAndDisconnectButtonsForConnection: connection];
        
        // Left split view
        
		[[configurationsPrefsView addConfigurationButton]    setEnabled: [self oneConfigurationIsSelected]];
        [[configurationsPrefsView removeConfigurationButton] setEnabled: [self oneConfigurationIsSelected]];

		
        [[configurationsPrefsView workOnConfigurationPopUpButton] setEnabled: ([self oneConfigurationIsSelected]
																				&& (! [gTbDefaults boolForKey: @"disableWorkOnConfigurationButton"]))];
		[[configurationsPrefsView workOnConfigurationPopUpButton] setAutoenablesItems: YES];
        
        NSString * configurationPath = [connection configPath];
        if (  [configurationPath hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]  ) {
            [[configurationsPrefsView makePrivateOrSharedMenuItem] setTitle: NSLocalizedString(@"Make Configuration Private..."  , @"Menu Item")];
        } else if (  [configurationPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
            [[configurationsPrefsView makePrivateOrSharedMenuItem] setTitle: NSLocalizedString(@"Make Configuration Shared..."  , @"Menu Item")];
        } else {
            [[configurationsPrefsView makePrivateOrSharedMenuItem] setTitle: NSLocalizedString(@"Make Configuration Shared..."  , @"Menu Item")];
        }
        
        if (  [[ConfigurationManager defaultManager] userCanEditConfiguration: [connection configPath]]  ) {
            [[configurationsPrefsView editOpenVPNConfigurationFileMenuItem] setTitle: NSLocalizedString(@"Edit OpenVPN Configuration File...", @"Menu Item")];
        } else {
            [[configurationsPrefsView editOpenVPNConfigurationFileMenuItem] setTitle: NSLocalizedString(@"Examine OpenVPN Configuration File...", @"Menu Item")];
        }
		
        
        // right split view
        
        // Right split view - log tab
        
        [[configurationsPrefsView logToClipboardButton]             setEnabled: ([self oneConfigurationIsSelected]
																				 && (! [gTbDefaults boolForKey: @"disableCopyLogToClipboardButton"]))];
        
        
        // Right split view - settings tab
        
        [[configurationsPrefsView advancedButton]                   setEnabled: YES];
        
        [self validateWhenToConnect: [self selectedConnection]];
        
    } else {
        
        // There is not a connection selected. Don't let the user do anything except add a connection.

		[[configurationsPrefsView addConfigurationButton]           setEnabled: YES];
        [[configurationsPrefsView removeConfigurationButton]        setEnabled: NO];
        [[configurationsPrefsView workOnConfigurationPopUpButton]   setEnabled: NO];
        
        // The "Log" and "Settings" items can't be selected because tabView:shouldSelectTabViewItem: will return NO if there is no selected connection
        
        [[configurationsPrefsView progressIndicator]                setHidden: YES];
        [[configurationsPrefsView logToClipboardButton]             setEnabled: NO];
        
        [[configurationsPrefsView connectButton]                    setEnabled: NO];
        [[configurationsPrefsView disconnectButton]                 setEnabled: NO];
        
        [[configurationsPrefsView whenToConnectPopUpButton]         setEnabled: NO];
        
        [[configurationsPrefsView setNameserverPopUpButton]         setEnabled: NO];
        
        [[configurationsPrefsView monitorNetworkForChangesCheckbox] setEnabled: NO];
        
        [[configurationsPrefsView keepConnectedCheckbox]            setEnabled: NO];
        
        [[configurationsPrefsView perConfigOpenvpnVersionButton]    setEnabled: NO];
        
        [[configurationsPrefsView soundOnConnectButton]             setEnabled: NO];
        [[configurationsPrefsView soundOnDisconnectButton]          setEnabled: NO];
        
        [[configurationsPrefsView advancedButton]                   setEnabled: NO];

    }
}

- (BOOL)validateMenuItem:(NSMenuItem *) anItem
{
	VPNConnection * connection = [self selectedConnection];
	
	if (  [anItem action] == @selector(addConfigurationButtonWasClicked:)  ) {
		return ! [gTbDefaults boolForKey: @"disableAddConfigurationButton"];
		
	} else if (  [anItem action] == @selector(removeConfigurationButtonWasClicked:)  ) {
		return [gTbDefaults boolForKey: @"disableRemoveConfigurationButton"];
		
	} else if (  [anItem action] == @selector(renameConfigurationMenuItemWasClicked:)  ) {
		return ! [gTbDefaults boolForKey: @"disableRenameConfigurationMenuItem"];
		
	} else if (  [anItem action] == @selector(duplicateConfigurationMenuItemWasClicked:)  ) {
		return ! [gTbDefaults boolForKey: @"disableDuplicateConfigurationMenuItem"];
		
	} else if (  [anItem action] == @selector(revertToShadowMenuItemWasClicked:)  ) {
		return (   ( ! [gTbDefaults boolForKey: @"disableRevertToShadowMenuItem"] )
				&& (   [[connection configPath] hasPrefix: [gPrivatePath stringByAppendingString: @"/"]])
				&& ( ! [connection shadowIsIdenticalMakeItSo: NO] )
				);
		
	} else if (  [anItem action] == @selector(makePrivateOrSharedMenuItemWasClicked:)  ) {
		NSString * configurationPath = [connection configPath];
		if (  [configurationPath hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]  ) {
			[[configurationsPrefsView makePrivateOrSharedMenuItem] setTitle: NSLocalizedString(@"Make Configuration Private..."  , @"Menu Item")];
			return ! [gTbDefaults boolForKey: @"disableMakeConfigurationPrivateOrSharedMenuItem"];
		} else if (  [configurationPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
			[[configurationsPrefsView makePrivateOrSharedMenuItem] setTitle: NSLocalizedString(@"Make Configuration Shared..."  , @"Menu Item")];
			return ! [gTbDefaults boolForKey: @"disableMakeConfigurationPrivateOrSharedMenuItem"];
		} else {
			[[configurationsPrefsView makePrivateOrSharedMenuItem] setTitle: NSLocalizedString(@"Make Configuration Shared..."  , @"Menu Item")];
			return NO;
		}
		
	} else if (  [anItem action] == @selector(editOpenVPNConfigurationFileMenuItemWasClicked:)  ) {
		return ! [gTbDefaults boolForKey: @"disableExamineOpenVpnConfigurationFileMenuItem"];
		
	} else if (  [anItem action] == @selector(showOpenvpnLogMenuItemWasClicked:)  ) {
		return (   ( ! [gTbDefaults boolForKey: @"disableShowOpenVpnLogInFinderMenuItem"] )
				&& [[connection configPath] hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]
				);
		
	} else if (  [anItem action] == @selector(removeCredentialsMenuItemWasClicked:)  ) {
		return  ! [gTbDefaults boolForKey: @"disableDeleteConfigurationCredentialsInKeychainMenuItem"];
	
	} else if (  [anItem action] == @selector(whenToConnectManuallyMenuItemWasClicked:)  ) {
		return TRUE;
	
	} else if (  [anItem action] == @selector(whenToConnectTunnelBlickLaunchMenuItemWasClicked:)  ) {
		return TRUE;
	
	} else if (  [anItem action] == @selector(whenToConnectOnComputerStartMenuItemWasClicked:)  ) {
		VPNConnection * conn = [self selectedConnection];
		if (  ! conn  ) {
			return NO;  // No connection selected
		}
		NSString * configurationPath = [conn configPath];
		if (  [configurationPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
			return NO;  // Private paths may not start when computer starts
		}
		if (  ! [[configurationPath pathExtension] isEqualToString: @"tblk"]  ) {
			return NO;  // Only .tblks may start when computer starts
		}
		return YES;
	}

	NSLog(@"MyPrefsWindowController:validateMenuItem: Unknown menuItem %@", [anItem description]);
	return NO;
}


// Overrides superclass method
// If showing the Configurations tab, window title is:
//      configname (Shared/Private/Deployed): Status (hh:mm:ss) - Tunnelblick
// Otherwise, window title is:
//      tabname - Tunnelblick
- (NSString *)windowTitle:(NSString *)currentItemLabel
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
    if (   ( ! theConnection)
		|| ( ! [self oneConfigurationIsSelected])  )  {
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

-(unsigned) firstDifferentComponent: (NSArray *) a and: (NSArray *) b
{
    unsigned retVal = 0;
    unsigned i;
    for (i=0;
         (i < [a count]) 
         && (i < [b count])
         && [[a objectAtIndex: i] isEqual: [b objectAtIndex: i]];
         i++  ) {
        ++retVal;
    }
    
    return retVal;
}


-(NSString *) indent: (NSString *) s by: (unsigned) n
{
    NSString * retVal = [NSString stringWithFormat:@"%*s%@", 3*n, "", s];
    return retVal;
}


-(BOOL) forceDisableOfNetworkMonitoring
{
    NSArray * content = [[configurationsPrefsView setNameserverArrayController] content];
    NSUInteger ix = [self selectedSetNameserverIndex];
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
        unsigned n = [leftNavList count];
        return (int)n;
    }
    
    return 0;
}

-(id) tableView:(NSTableView *) aTableView objectValueForTableColumn:(NSTableColumn *) aTableColumn row: (int) rowIndex
{
    (void) aTableColumn;
    
    if (  aTableView == [configurationsPrefsView leftNavTableView]  ) {
        NSString * s = [leftNavList objectAtIndex: (unsigned)rowIndex];
        return s;
    }
    
    return nil;
}

- (VPNConnection*) selectedConnection
// Returns the connection associated with the currently selected connection or nil on error.
{
    if (  selectedLeftNavListIndex != UINT_MAX  ) {
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
        [connection addToLog: @"*Tunnelblick: Disconnecting; VPN Details… window connect button pressed"];
        [connection connect: sender userKnows: YES];
    } else {
        NSLog(@"connectButtonWasClicked but no configuration selected");
    }
}


-(IBAction) disconnectButtonWasClicked: (id) sender
{
	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        [connection addToLog: @"*Tunnelblick: Disconnecting; VPN Details… window disconnect button pressed"];
        [connection disconnectAndWait: [NSNumber numberWithBool: NO] userKnows: YES];      
    } else {
        NSLog(@"disconnectButtonWasClicked but no configuration selected");
    }
}


-(IBAction) configurationsHelpButtonWasClicked: (id) sender
{
	(void) sender;
	
    MyGotoHelpPage(@"vpn-details.html", nil);
}


// Left side -- navigation and configuration manipulation

-(IBAction) addConfigurationButtonWasClicked: (id) sender
{
	(void) sender;
	
    [[ConfigurationManager defaultManager] addConfigurationGuide];
}


-(IBAction) removeConfigurationButtonWasClicked: (id) sender
{
	(void) sender;
	
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
    
    if (  [configurationPath hasPrefix: [gDeployPath stringByAppendingString: @"/"]]  ) {
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                        NSLocalizedString(@"You may not delete a Deployed configuration.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
	NSString * group = credentialsGroupFromDisplayName(displayName);

	BOOL removeCredentials = TRUE;
	NSString * credentialsNote = @"";
	if (  group  ) {
		if (  1 != [gTbDefaults numberOfConfigsInCredentialsGroup: group]  ) {
			credentialsNote = NSLocalizedString(@"\n\nNote: The configuration's group credentials will not be deleted because other configurations use them.", @"Window text");
			removeCredentials = FALSE;
		}
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
                          NSLocalizedString(@" Configurations may be deleted only by a computer administrator.\n\n Deletion is immediate and permanent. All settings for '%@' will also be deleted permanently.%@%@", @"Window text"),
                          displayName,
						  credentialsNote,
                          notDeletingOtherFilesMsg];
        authorization = [NSApplication getAuthorizationRef: msg];
        if (  authorization == nil) {
            return;
        }
        localAuthorization = TRUE;
    } else {
        int button = TBRunAlertPanel(NSLocalizedString(@"Please Confirm", @"Window title"),
                                     [NSString stringWithFormat:
                                      NSLocalizedString(@"Deleting a configuration is permanent and cannot be undone.\n\nAll settings for the configuration will also be deleted permanently.\n\n%@%@\n\nAre you sure you wish to delete configuration '%@'?", @"Window text"),
                                      credentialsNote,
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
                                                  usingAuthRefPtr: &authorization
                                                       warnDialog: YES]  ) {
        //Remove credentials
		if (  removeCredentials  ) {
			AuthAgent * myAuthAgent = [[[AuthAgent alloc] initWithConfigName: group credentialsGroup: group] autorelease];
			
			[myAuthAgent setAuthMode: @"privateKey"];
			if (  [myAuthAgent keychainHasCredentials]  ) {
				[myAuthAgent deleteCredentialsFromKeychain];
			}
			[myAuthAgent setAuthMode: @"password"];
			if (  [myAuthAgent keychainHasCredentials]  ) {
				[myAuthAgent deleteCredentialsFromKeychain];
			}
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
	(void) sender;
	
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
    
    if (  ! [connection isDisconnected]  ) {
        TBRunAlertPanel(NSLocalizedString(@"Active connection", @"Window title"),
                        NSLocalizedString(@"You cannot rename a configuration unless it is disconnected.", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
    NSString * sourcePath = [connection configPath];
    if (  [sourcePath hasPrefix: [gDeployPath stringByAppendingString: @"/"]]  ) {
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
    
    BOOL localAuthorization = FALSE;
    if (  authorization == nil  ) {
        NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"You have asked to rename '%@' to '%@'.", @"Window text"), sourceDisplayName, targetDisplayName];
        authorization = [NSApplication getAuthorizationRef: msg];
        if ( authorization == nil ) {
            return;
        }
        localAuthorization = TRUE;
    }
    
    if (  [[ConfigurationManager defaultManager] copyConfigPath: sourcePath
                                                         toPath: targetPath
                                                usingAuthRefPtr: &authorization
                                                     warnDialog: YES
                                                    moveNotCopy: YES]  ) {
        
        // We copy "-keychainHasUsernameAndPassword" because it is deleted by moveCredentials
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
		
		// We also need to change the name of the configuration that is selected
		NSString * pref = [gTbDefaults objectForKey: @"leftNavSelectedDisplayName"];
		if (  [pref isEqualToString: sourceDisplayName]  ) {
			[gTbDefaults setObject: targetDisplayName forKey: @"leftNavSelectedDisplayName"];
		}
		
		[[[NSApp delegate] logScreen] setPreviouslySelectedNameOnLeftNavList: targetDisplayName];
		
		[[NSApp delegate] updateMenuAndDetailsWindow];
		
    }
    
    if (  localAuthorization  ) {
        AuthorizationFree(authorization, kAuthorizationFlagDefaults);
        authorization = nil;
    }
}

-(IBAction) duplicateConfigurationMenuItemWasClicked: (id) sender
{
	(void) sender;
	
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
    if (  [source hasPrefix: [gDeployPath stringByAppendingString: @"/"]]  ) {
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
    
    BOOL localAuthorization = FALSE;
    if (  authorization == nil  ) {
        NSString * msg = [NSString stringWithFormat: NSLocalizedString(@"You have asked to duplicate '%@'.", @"Window text"), displayName];
        authorization = [NSApplication getAuthorizationRef: msg];
        if ( authorization == nil ) {
            return;
        }
        localAuthorization = TRUE;
    }
    
    if (  [[ConfigurationManager defaultManager] copyConfigPath: source
                                                         toPath: target
                                                usingAuthRefPtr: &authorization
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
    
    if (  localAuthorization  ) {
        AuthorizationFree(authorization, kAuthorizationFlagDefaults);
        authorization = nil;
    }
}


-(IBAction) makePrivateOrSharedMenuItemWasClicked: (id) sender
{
	(void) sender;
	
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
        return;
    }
    
    NSString * path = [connection configPath];
    if (  ! [[path pathExtension] isEqualToString: @"tblk"]  ) {
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                        NSLocalizedString(@"You cannot make a configuration shared if it is not a Tunnelblick VPN Configuration (.tblk).", @"Window text"),
                        nil, nil, nil);
        return;
    }
    
    if (  ! [connection isDisconnected]  ) {
        NSString * msg = (  [path hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]
                          ? NSLocalizedString(@"You cannot make a configuration private unless it is disconnected.", @"Window text")
                          : NSLocalizedString(@"You cannot make a configuration shared unless it is disconnected.", @"Window text")
                          );
        TBRunAlertPanel(NSLocalizedString(@"Active connection", @"Window title"),
                        msg,
                        nil, nil, nil);
        return;
    }
    
    [[ConfigurationManager defaultManager] shareOrPrivatizeAtPath: path];
}


-(IBAction) revertToShadowMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (  ! connection  ) {
        NSLog(@"revertToShadowMenuItemWasClicked but no configuration has been selected");
        return;
    }
    
	NSString * source = [connection configPath];

    if (  ! [source hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
        TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                        NSLocalizedString(@"You may only revert a private configuration.", @"Window text"),
                        nil, nil, nil);
        return;
    }
	
	if ( [connection shadowIsIdenticalMakeItSo: NO]  ) {
		TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
						[NSString stringWithFormat:
						 NSLocalizedString(@"%@ is already identical to its last secured (shadow) copy.\n\n", @"Window text"),
						 [connection displayName]],
						nil, nil, nil);
        return;
	}
    
	int result = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
								 [NSString stringWithFormat:
								  NSLocalizedString(@"Do you wish to revert the '%@' configuration to its last secured (shadow) copy?\n\n", @"Window text"),
								  [connection displayName]],
								 NSLocalizedString(@"Revert", @"Button"),
								 NSLocalizedString(@"Cancel", @"Button"), nil);
	
	if (  result != NSAlertDefaultReturn  ) {
		return;
	}
    
	NSString * fileName = lastPartOfPath(source);
	NSArray * arguments = [NSArray arrayWithObjects: @"revertToShadow", fileName, nil];
	result = runOpenvpnstart(arguments, nil, nil);
	switch (  result  ) {
			
		case OPENVPNSTART_REVERT_CONFIG_OK:
			TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
							[NSString stringWithFormat:
							 NSLocalizedString(@"%@ has been reverted to its last secured (shadow) copy.\n\n", @"Window text"),
							 [connection displayName]],
							nil, nil, nil);
			break;
			
		case OPENVPNSTART_REVERT_CONFIG_MISSING:
			TBRunAlertPanel(NSLocalizedString(@"Configuration Installation Error", @"Window title"),
							NSLocalizedString(@"The private configuration has never been secured, so you cannot revert to the secured (shadow) copy.", @"Window text"),
							nil, nil, nil);
			break;
			
		default:
			TBRunAlertPanel(NSLocalizedString(@"Configuration Installation Error", @"Window title"),
							NSLocalizedString(@"An error occurred while trying to revert to the secured (shadow) copy. See the Console Log for details.\n\n", @"Window text"),
							nil, nil, nil);
			break;
	}
}


-(IBAction) editOpenVPNConfigurationFileMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (connection  ) {
        [[ConfigurationManager defaultManager] editConfigurationAtPath: [connection configPath] forConnection: connection];
    } else {
        NSLog(@"editOpenVPNConfigurationFileMenuItemWasClicked but no configuration selected");
    }
    
}


-(IBAction) showOpenvpnLogMenuItemWasClicked: (id) sender
{
	(void) sender;
	
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
	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        NSString * name = [connection displayName];
		
		NSString * group = credentialsGroupFromDisplayName(name);
		AuthAgent * myAuthAgent = [[[AuthAgent alloc] initWithConfigName: name credentialsGroup: group] autorelease];
		
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
			NSString * msg;
			if (  group  ) {
				msg =[NSString stringWithFormat: NSLocalizedString(@"Are you sure you wish to delete the credentials (private"
																   @" key or username and password) stored in the Keychain for '%@'"
                                                                   @" credentials?", @"Window text"), group];
			} else {
				msg =[NSString stringWithFormat: NSLocalizedString(@"Are you sure you wish to delete the credentials (private key or username and password) for '%@' that are stored in the Keychain?", @"Window text"), name];
			}
			
            int button = TBRunAlertPanel(NSLocalizedString(@"Please Confirm", @"Window title"),
                                         msg,
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

-(NSString *) listOfFilesInTblkForConnection: (VPNConnection *) connection {
    
    NSString * configPath = [connection configPath];
    NSString * configPathTail = [configPath lastPathComponent];
    
    if (  [configPath hasSuffix: @".tblk"]  ) {
        if (  [configPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
            NSMutableString * fileListString = [[[NSMutableString alloc] initWithCapacity: 500] autorelease];
            NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: configPath];
            NSString * filename;
            while (  (filename = [dirEnum nextObject])  ) {
                if (  ! [filename hasPrefix: @"."]  ) {
					NSString * extension = [filename pathExtension];
					NSArray * extensionsToSkip = KEY_AND_CRT_EXTENSIONS;
					if (   ( ! [extensionsToSkip containsObject: extension])
						&& ( ! [extension isEqualToString: @"ovpn"])  ) {
						NSString * fullPath = [configPath stringByAppendingPathComponent: filename];
						BOOL isDir;
						if (  ! (   [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
								 && isDir)  ) {
							[fileListString appendFormat: @"      %@\n", filename];
						}
					}
				}
			}
            
			return (  ([fileListString length] == 0)
					? [NSString stringWithFormat: @"There are no unusual files in %@\n", configPathTail]
					: [NSString stringWithFormat: @"Unusual files in %@:\n%@", configPathTail, fileListString]);
		} else {
            return [NSString stringWithFormat: @"Cannot list unusual files in %@; not a private configuration\n", configPathTail];
        }
    } else {
        return [NSString stringWithFormat: @"Cannot list unusual files in %@; not a .tblk\n", configPathTail];
    }
}

-(NSString *) tigerConsoleContents {
    
    // Tiger doesn't implement the asl API (or not enough of it). So we get the console log from the file if we are running as an admin
	NSString * consoleRawContents = @""; // stdout (ignore stderr)
	
	if (  isUserAnAdmin()  ) {
		runTool(@"/bin/bash",
                [NSArray arrayWithObjects:
                 @"-c",
                 [NSString stringWithFormat: @"cat /Library/Logs/Console/%d/console.log | grep -i -E 'tunnelblick|openvpn' | tail -n 100", getuid()],
                 nil],
                &consoleRawContents,
                nil);
	} else {
		consoleRawContents = (@"The Console log cannot be obtained because you are not\n"
							  @"logged in as an administrator. To view the Console log,\n"
							  @"please use the Console application in /Applications/Utilities.\n");
	}
	    
    // Replace backslash-n with newline and indent the continuation lines
    NSMutableString * consoleContents = [[consoleRawContents mutableCopy] autorelease];
    [consoleContents replaceOccurrencesOfString: @"\\n"
                                     withString: @"\n                                       " // Note all the spaces in the string
                                        options: 0
                                          range: NSMakeRange(0, [consoleContents length])];

    return consoleContents;
}

-(NSString *) stringFromLogEntry: (NSDictionary *) dict {
    
    // Returns a string with a console log entry, terminated with a LF
    
    NSString * timestampS = [dict objectForKey: [NSString stringWithUTF8String: ASL_KEY_TIME]];
    NSString * senderS    = [dict objectForKey: [NSString stringWithUTF8String: ASL_KEY_SENDER]];
    NSString * pidS       = [dict objectForKey: [NSString stringWithUTF8String: ASL_KEY_PID]];
    NSString * msgS       = [dict objectForKey: [NSString stringWithUTF8String: ASL_KEY_MSG]];
    
    NSDate * dateTime = [NSDate dateWithTimeIntervalSince1970: (NSTimeInterval) [timestampS doubleValue]];
    NSDateFormatter * formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setDateFormat: @"yyyy-MM-dd HH:mm:ss"];

    NSString * timeString = [formatter stringFromDate: dateTime];
    NSString * senderString = [NSString stringWithFormat: @"%@[%@]", senderS, pidS];
    
	// Set up to indent continuation lines by converting newlines to \n (i.e., "backslash n")
	NSMutableString * msgWithBackslashN = [[msgS mutableCopy] autorelease];
	[msgWithBackslashN replaceOccurrencesOfString: @"\n"
									   withString: @"\\n"
										  options: 0
											range: NSMakeRange(0, [msgWithBackslashN length])];
	
    return [NSString stringWithFormat: @"%@ %21@ %@\n", timeString, senderString, msgWithBackslashN];
}

-(NSString *) stringContainingRelevantConsoleLogEntries {
    
    // Returns a string with relevant entries from the Console log
    
	// First, search the log for all entries fewer than six hours old from Tunnelblick or openvpnstart
    // And append them to tmpString
	
	NSMutableString * tmpString = [NSMutableString string];
    
    aslmsg q = asl_new(ASL_TYPE_QUERY);
	time_t sixHoursAgoTimeT = time(NULL) - 6 * 60 * 60;
	const char * sixHoursAgo = [[NSString stringWithFormat: @"%ld", (long) sixHoursAgoTimeT] UTF8String];
    asl_set_query(q, ASL_KEY_TIME, sixHoursAgo, ASL_QUERY_OP_GREATER_EQUAL | ASL_QUERY_OP_NUMERIC);
    aslresponse r = asl_search(NULL, q);
    
    aslmsg m;
    while (NULL != (m = aslresponse_next(r))) {
        
        NSMutableDictionary *tmpDict = [NSMutableDictionary dictionary];
        
        BOOL includeDict = FALSE;
        const char * key;
        const char * val;
        unsigned i;
        for (  i = 0; (NULL != (key = asl_key(m, i))); i++  ) {
            val = asl_get(m, key);
            if (  val  ) {
                NSString * string    = [NSString stringWithUTF8String: val];
                NSString * keyString = [NSString stringWithUTF8String: key];
                [tmpDict setObject: string forKey: keyString];
                
                if (  ! ASL_KEY_SENDER  ) {
                    NSLog(@"stringContainingRelevantConsoleLogEntries: ASL_KEY_SENDER = NULL");
                }
                if (  ! ASL_KEY_MSG  ) {
                    NSLog(@"stringContainingRelevantConsoleLogEntries: ASL_KEY_MSG = NULL");
                }
                if (  [keyString isEqualToString: [NSString stringWithUTF8String: ASL_KEY_SENDER]]  ) {
                    if (   [string isEqualToString: @"Tunnelblick"]
                        || [string isEqualToString: @"openvpnstart"]
                        || [string isEqualToString: @"atsystemstart"]  ) {
                        includeDict = TRUE;
                    }
                } else if (  [keyString isEqualToString: [NSString stringWithUTF8String: ASL_KEY_MSG]]  ) {
                    if (   ([string rangeOfString: @"Tunnelblick"].length != 0)
                        || ([string rangeOfString: @"tunnelblick"].length != 0)  ) {
                        includeDict = TRUE;
                    }
                }
            }
		}
		
		if (  includeDict  ) {
			[tmpString appendString: [self stringFromLogEntry: tmpDict]];
		}
	}
		
	aslresponse_free(r);
	
	// Next, extract the tail of the entries -- the last 200 lines of them
	// (The loop test is "i<201" because we look for the 201-th newline from the end of the string; just after that is the
	//  start of the 200th entry from the end of the string.)
    
	NSRange tsRng = NSMakeRange(0, [tmpString length]);	// range we are looking at currently; start with entire string
    unsigned i;
	unsigned offset = 2;
    BOOL fewerThan200LinesInLog = FALSE;
	for (  i=0; i<201; i++  ) {
		NSRange nlRng = [tmpString rangeOfString: @"\n"	// range of last newline at end of part we are looking at
										 options: NSBackwardsSearch
										   range: tsRng];
		
		if (  nlRng.length == 0  ) {    // newline not found (fewer than 200 lines in tmpString);  set up to start at start of string
			offset = 0;
            fewerThan200LinesInLog = TRUE;
			break;
		}
		
        if (  nlRng.location == 0  ) {  // newline at start of string (shouldn't happen, but...)
			offset = 1;					// set up to start _after_ the newline
            fewerThan200LinesInLog = TRUE;
            break;
        }
        
		tsRng.length = nlRng.location - 1; // change so looking before that newline 
	}
    
    if (  fewerThan200LinesInLog  ) {
        tsRng.length = 0;
    }
    
	NSString * tail = [tmpString substringFromIndex: tsRng.length + offset];
	
	// Finally, indent continuation lines
	NSMutableString * indentedMsg = [[tail mutableCopy] autorelease];
	[indentedMsg replaceOccurrencesOfString: @"\\n"
								 withString: @"\n                                       " // Note all the spaces in the string
									options: 0
									  range: NSMakeRange(0, [indentedMsg length])];
	return indentedMsg;	
}

-(NSString *) getPreferences: (NSArray *) prefsArray prefix: (NSString *) prefix {
    
    NSMutableString * string = [[[NSMutableString alloc] initWithCapacity: 1000] autorelease];
    
    NSUInteger i;
    for (  i=0; i<[prefsArray count]; i++  ) {
        NSString * keySuffix = [prefsArray objectAtIndex: i];
        NSString * key = [prefix stringByAppendingString: keySuffix];
        id obj = [gTbDefaults objectForKey: key];
        if (  obj  ) {
            [string appendFormat: @"%@ = %@%@\n", keySuffix, obj, (  [gTbDefaults canChangeValueForKey: key]
                                                                   ? @""
                                                                   : @" (forced)")];
        }
    }
    
    return string;
}

-(NSString *) nonAppleKextContents {
    
    NSString * kextRawContents = @""; // stdout (ignore stderr)
	
    runTool(@"/bin/bash",
            [NSArray arrayWithObjects:
             @"-c",
             @"kextstat | grep -v com.apple", nil],
            &kextRawContents,
            nil);
    
    return kextRawContents;
}

-(IBAction) logToClipboardButtonWasClicked: (id) sender {

	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
		
		// Get OS and Tunnelblick version info
		NSString * versionContents = [[[NSApp delegate] openVPNLogHeader] stringByAppendingString:
                                      (isUserAnAdmin()
                                       ? @"; Admin user"
                                       : @"; Standard user")];
		
		// Get contents of configuration file
        NSString * configFileContents = [connection sanitizedConfigurationFileContents ];
        if (  ! configFileContents  ) {
            configFileContents = @"(No configuration file found!)";
        }
		
        // Get list of files in .tblk or message explaining why cannot get list
        NSString * tblkFileList = [self listOfFilesInTblkForConnection: connection];
        
        // Get relevant preferences
        NSString * configurationPreferencesContents = [self getPreferences: gConfigurationPreferences prefix: [connection displayName]];
        
        NSString * wildcardPreferencesContents      = [self getPreferences: gConfigurationPreferences prefix: @"*"];
        
        NSString * programPreferencesContents       = [self getPreferences: gProgramPreferences       prefix: @""];
        
		// Get Tunnelblick log
        NSTextStorage * store = [[configurationsPrefsView logView] textStorage];
        NSString * logContents = [store string];
        
		// Get tail of Console log
        NSString * consoleContents = (  runningOnLeopardOrNewer()
                                      ? [self stringContainingRelevantConsoleLogEntries]
                                      : [self tigerConsoleContents]);
        
        NSString * kextContents = [self nonAppleKextContents];
        
		NSString * separatorString = @"================================================================================\n\n";
		
        NSString * output = [NSString stringWithFormat:
							 @"%@\n\n"  // Version info
                             @"\"Sanitized\" configuration file for %@:\n\n%@\n\n%@"
                             @"%@\n%@"  // List of unusual files in .tblk (or message why not listing them)
                             @"Configuration preferences:\n\n%@\n%@"
                             @"Wildcard preferences:\n\n%@\n%@"
                             @"Program preferences:\n\n%@\n%@"
                             @"Tunnelblick Log:\n\n%@\n%@"
                             @"Console Log:\n\n%@\n%@"
                             @"Non-Apple kexts that are loaded:\n\n%@",
                             versionContents,
                             [connection configPath], configFileContents, separatorString,
                             tblkFileList, separatorString,
                             configurationPreferencesContents, separatorString,
                             wildcardPreferencesContents, separatorString,
                             programPreferencesContents, separatorString,
                             logContents, separatorString,
                             consoleContents, separatorString,
                             kextContents];
        
        NSPasteboard * pb = [NSPasteboard generalPasteboard];
        [pb declareTypes: [NSArray arrayWithObject: NSStringPboardType] owner: self];
        [pb setString: output forType: NSStringPboardType];
    } else {
        NSLog(@"logToClipboardButtonWasClicked but no configuration selected");
    }
}


// Settings tab

-(IBAction) whenToConnectManuallyMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    if (  [self selectedConnection]  ) {
        [self setSelectedWhenToConnectIndex: 0];
    } else {
        NSLog(@"whenToConnectManuallyMenuItemWasClicked but no configuration selected");
    }
}


-(IBAction) whenToConnectTunnelBlickLaunchMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    if (  [self selectedConnection]  ) {
        [self setSelectedWhenToConnectIndex: 1];
    } else {
        NSLog(@"whenToConnectTunnelBlickLaunchMenuItemWasClicked but no configuration selected");
    }
}


-(IBAction) whenToConnectOnComputerStartMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    if (  [self selectedConnection]  ) {
        NSString * configurationPath = [[self selectedConnection] configPath];
        if (  [configurationPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
            NSUInteger ix = selectedWhenToConnectIndex;
            selectedWhenToConnectIndex = 2;
            [[configurationsPrefsView whenToConnectPopUpButton] selectItemAtIndex: (int)ix];
            [self setSelectedWhenToConnectIndex: ix];
            TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                            NSLocalizedString(@"Private configurations cannot connect when the computer starts.\n\n"
                                              "First make the configuration shared, then change this setting.", @"Window text"),
                            nil, nil, nil);
        } else if (  ! [[configurationPath pathExtension] isEqualToString: @"tblk"]  ) {
            NSUInteger ix = selectedWhenToConnectIndex;
            selectedWhenToConnectIndex = 2;
            [[configurationsPrefsView whenToConnectPopUpButton] selectItemAtIndex: (int)ix];
            [self setSelectedWhenToConnectIndex: ix];
            TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
                            NSLocalizedString(@"Only a Tunnelblick VPN Configuration (.tblk) can start when the computer starts.", @"Window text"),
                            nil, nil, nil);
        } else {
            [self setSelectedWhenToConnectIndex: 2];
        }
    } else {
        NSLog(@"whenToConnectOnComputerStartMenuItemWasClicked but no configuration selected");
    }
}

-(NSUInteger) selectedPerConfigOpenvpnVersionIndex
{
    return selectedPerConfigOpenvpnVersionIndex;
}

-(void) setSelectedPerConfigOpenvpnVersionIndex: (NSUInteger) newValue
{
    if (  newValue != selectedPerConfigOpenvpnVersionIndex  ) {
        NSArrayController * ac = [configurationsPrefsView perConfigOpenvpnVersionArrayController];
        NSArray * list = [ac content];
        if (  newValue < [list count]  ) {
            selectedPerConfigOpenvpnVersionIndex = newValue;
            
            // Set the preference if this isn't just the initialization
            if (  ! [[NSApp delegate] doingSetupOfUI]  ) {
                NSString * newPreferenceValue = [[list objectAtIndex: newValue] objectForKey: @"value"];
				NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
									   newPreferenceValue, @"NewValue",
									   @"-openvpnVersion", @"PreferenceName",
									   nil];
				[[NSApp delegate] performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
			}
        }
    }
}


// Checkbox was changed by another window
-(void) monitorNetworkForChangesCheckboxChangedForConnection: (VPNConnection *) theConnection
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
    [[NSApp delegate] setBooleanPreferenceForSelectedConnectionsWithKey: @"-notMonitoringConnection"
																	 to: ([sender state] == NSOnState)
															   inverted: YES];
    
    [settingsSheetWindowController monitorNetworkForChangesCheckboxChangedForConnection: [self selectedConnection]];
}

-(IBAction) keepConnectedCheckboxWasClicked: (id) sender
{
    [[NSApp delegate] setBooleanPreferenceForSelectedConnectionsWithKey: @"-keepConnected"
																	 to: ([sender state] == NSOnState)
															   inverted: NO];
}

-(NSUInteger) selectedSoundOnConnectIndex
{
    return selectedSoundOnConnectIndex;
}


-(void) setSelectedSoundOnConnectIndex: (NSUInteger) newValue
{
    [self setSoundIndex: &selectedSoundOnConnectIndex
                     to: newValue
             preference: @"-tunnelUpSoundName"];
}


-(NSUInteger) selectedSoundOnDisconnectIndex
{
    return selectedSoundOnDisconnectIndex;
}


-(void) setSelectedSoundOnDisconnectIndex: (NSUInteger) newValue
{
    [self setSoundIndex: &selectedSoundOnDisconnectIndex
                     to: newValue
             preference: @"-tunnelDownSoundName"];
}

-(IBAction) advancedButtonWasClicked: (id) sender
{
	(void) sender;
	
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
    
    BOOL enableWhenComputerStarts = ! [configurationPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]];
    
    NSString * autoConnectKey = [displayName stringByAppendingString: @"autoConnect"];
    BOOL autoConnect   = [gTbDefaults boolForKey: autoConnectKey];
    NSString * ossKey = [displayName stringByAppendingString: @"-onSystemStart"];
    BOOL onSystemStart = [gTbDefaults boolForKey: ossKey];
    
    BOOL launchdPlistWillConnectOnSystemStart = [connection launchdPlistWillConnectOnSystemStart];
    
    NSUInteger ix = NSNotFound;
    
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
    
    [[configurationsPrefsView whenToConnectPopUpButton] selectItemAtIndex: (int)ix];
    selectedWhenToConnectIndex = ix;
    [[configurationsPrefsView whenToConnectOnComputerStartMenuItem] setEnabled: enableWhenComputerStarts];
    
    BOOL enable = (   [gTbDefaults canChangeValueForKey: autoConnectKey]
                   && [gTbDefaults canChangeValueForKey: ossKey]
				   && [self oneConfigurationIsSelected]);
    [[configurationsPrefsView whenToConnectPopUpButton] setEnabled: enable];
}

-(void) setSelectedWhenToConnectIndex: (NSUInteger) newValue
{
    NSUInteger oldValue = selectedWhenToConnectIndex;
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
                NSLog(@"Attempt to set 'when to connect' to %ld ignored", (long) newValue);
                break;
        }
        selectedWhenToConnectIndex = newValue;
        [self validateWhenToConnect: [self selectedConnection]];
        
        NSUInteger ix = 0;
        if (  [gTbDefaults boolForKey: autoConnectKey]  ) {
            if (  [gTbDefaults boolForKey: onSystemStartKey]  ) {
                ix = 2;
            } else {
                ix = 1;
            }
        }
        if (  ix != newValue  ) {   // If weren't able to change it, restore old value
            if (  oldValue == NSNotFound  ) {
                oldValue = 0;
            }
            [self setSelectedWhenToConnectIndex: oldValue];
            selectedWhenToConnectIndex = oldValue;
        }
    }
}


-(void) setSelectedSetNameserverIndex: (NSUInteger) newValue
{
    if (  newValue != selectedSetNameserverIndex  ) {
        if (  ! [[NSApp delegate] doingSetupOfUI]  ) {
			NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
								   [NSNumber numberWithUnsignedInt: newValue], @"NewValue",
								   @"useDNS", @"PreferenceName",
								   nil];
			[[NSApp delegate] performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
			
			// Must set the key now (even though setPreferenceForSelectedConfigurationsWithDict: will set it later) so the rest of the code in this method runs with the new setting
            NSString * actualKey = [[[self selectedConnection] displayName] stringByAppendingString: @"useDNS"];
            [gTbDefaults setObject: [NSNumber numberWithUnsignedInt: newValue] forKey: actualKey];
        }
		
		// Must set the key above (even though setPreferenceForSelectedConfigurationsWithDict: will set it later) so the following code works with the new setting

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
        }
		
        [settingsSheetWindowController monitorNetworkForChangesCheckboxChangedForConnection: [self selectedConnection]];
        [settingsSheetWindowController setupSettingsFromPreferences];
    }
}

-(void) tableViewSelectionDidChange:(NSNotification *)notification
{
	(void) notification;
	
    [self performSelectorOnMainThread: @selector(selectedLeftNavListIndexChanged) withObject: nil waitUntilDone: NO];
}

-(void) selectedLeftNavListIndexChanged
{
    int n;
	
	if (   runningOnSnowLeopardOrNewer()  // 10.5 and lower don't have setDelegate and setDataSource
		&& ( ! [gTbDefaults boolForKey: @"doNotShowOutlineViewOfConfigurations"] )  ) {
		n = [[[configurationsPrefsView outlineViewController] outlineView] selectedRow];
		NSOutlineView * oV = [[configurationsPrefsView outlineViewController] outlineView];
		LeftNavItem * item = [oV itemAtRow: n];
		LeftNavDataSource * oDS = (LeftNavDataSource *) [oV dataSource];
		NSString * displayName = [oDS outlineView: oV displayNameForTableColumn: nil byItem: item];
		NSDictionary * dict = [oDS rowsByDisplayName];
		NSNumber * ix = [dict objectForKey: displayName];
		if (  ix  ) {
			n = [ix intValue];
		} else {
            return; // No configurations
		}
	} else {
		n = [[configurationsPrefsView leftNavTableView] selectedRow];
	}
		
    [self setSelectedLeftNavListIndex: (unsigned) n];
}

-(void) setSelectedLeftNavListIndex: (NSUInteger) newValue
{
    if (  newValue != selectedLeftNavListIndex  ) {
        
        // Don't allow selection of a "folder" row, only of a "configuration" row
        while (  [[leftNavDisplayNames objectAtIndex: (unsigned) newValue] length] == 0) {
            ++newValue;
        }
        
        if (  selectedLeftNavListIndex != NSNotFound  ) {
            VPNConnection * connection = [self selectedConnection];
            [connection stopMonitoringLogFiles];
        }
        
        selectedLeftNavListIndex = newValue;
        [[configurationsPrefsView leftNavTableView] selectRowIndexes: [NSIndexSet indexSetWithIndex: (unsigned) newValue] byExtendingSelection: NO];
        
		// Set name and status of the new connection in the window title.
		VPNConnection* newConnection = [self selectedConnection];
        NSString * dispNm = [newConnection displayName];
		
		BOOL savedDoingSetupOfUI = [[NSApp delegate] doingSetupOfUI];
		[[NSApp delegate] setDoingSetupOfUI: TRUE];
		
        [self setupSetNameserver:           newConnection];
        [self setupKeepConnected:           newConnection];
        [self setupNetworkMonitoring:       newConnection];
		[self setupPerConfigOpenvpnVersion: newConnection];
        [self setupSoundPopUpButtons:       newConnection];
        
        [self validateDetailsWindowControls];
		
		[[NSApp delegate] setDoingSetupOfUI: savedDoingSetupOfUI];
                
        [dispNm retain];
        [previouslySelectedNameOnLeftNavList release];
        previouslySelectedNameOnLeftNavList = dispNm;
        [gTbDefaults setObject: dispNm forKey: @"leftNavSelectedDisplayName"];
        
        [settingsSheetWindowController setConfigurationName: dispNm];
        
        [newConnection startMonitoringLogFiles];
    }
}

TBSYNTHESIZE_NONOBJECT_GET(NSUInteger, selectedWhenToConnectIndex)
TBSYNTHESIZE_NONOBJECT_GET(NSUInteger, selectedSetNameserverIndex)
TBSYNTHESIZE_NONOBJECT_GET(NSUInteger, selectedLeftNavListIndex)

//***************************************************************************************************************

-(void) setupGeneralView
{
	[[NSApp delegate] setOurPreferencesFromSparkles]; // Sparkle may have changed it's preferences so we update ours
	
    // Set values for the update checkboxes
    [self setValueForCheckbox: [generalPrefsView updatesCheckAutomaticallyCheckbox]
                preferenceKey: @"updateCheckAutomatically"
                     inverted: NO
                   defaultsTo: FALSE];
    
    [self setValueForCheckbox: [generalPrefsView updatesCheckForBetaUpdatesCheckbox]
                preferenceKey: @"updateCheckBetas"
                     inverted: NO
                   defaultsTo: runningABetaVersion()];
    
    [self setValueForCheckbox: [generalPrefsView updatesSendProfileInfoCheckbox]
                preferenceKey: @"updateSendProfileInfo"
                     inverted: NO
                   defaultsTo: FALSE];
    
    // Set the last update date/time
    [self updateLastCheckedDate];

    // Select the keyboard shortcut
    
    unsigned kbsCount = [[[generalPrefsView keyboardShortcutArrayController] content] count];
    unsigned kbsIx = [gTbDefaults unsignedIntForKey: @"keyboardShortcutIndex"
                                            default: 1 /* F1  key */
                                                min: 0 /* (none) */
                                                max: kbsCount];
    
    [self setSelectedKeyboardShortcutIndex: kbsIx];
    
    [[generalPrefsView keyboardShortcutButton] setEnabled: [gTbDefaults canChangeValueForKey: @"keyboardShortcutIndex"]];
    
    // Select the log size
    
    unsigned prefSize = gMaximumLogSize;
    
    NSUInteger logSizeIx = UINT_MAX;
    NSArrayController * ac = [generalPrefsView maximumLogSizeArrayController];
    NSArray * list = [ac content];
    unsigned i;
    for (  i=0; i<[list count]; i++  ) {
        NSDictionary * dict = [list objectAtIndex: i];
        NSString * listValue = [dict objectForKey: @"value"];
        unsigned listValueSize;
        if (  [listValue respondsToSelector:@selector(intValue)]  ) {
            listValueSize = [listValue unsignedIntValue];
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
    
    if (  logSizeIx == UINT_MAX  ) {
        NSLog(@"'maxLogDisplaySize' preference value of %ud is not available", prefSize);
        logSizeIx = 2;  // Second one should be '102400'
    }
    
    if (  logSizeIx < [list count]  ) {
        [self setSelectedMaximumLogSizeIndex: logSizeIx];
    } else {
        NSLog(@"Invalid selectedMaximumLogSizeIndex %lu; maximum is %ld", (unsigned long)logSizeIx, (long) [list count]-1);
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


-(IBAction) updatesSendProfileInfoCheckboxWasClicked: (id) sender
{
    SUUpdater * updater = [[NSApp delegate] updater];
    if (  [updater respondsToSelector: @selector(setSendsSystemProfile:)]  ) {
        [[NSApp delegate] setOurPreferencesFromSparkles]; // Sparkle may have changed it's preferences so we update ours
        BOOL newValue = [sender state] == NSOnState;
        [gTbDefaults setBool: newValue forKey: @"updateSendProfileInfo"];
        [updater setSendsSystemProfile: newValue];
    } else {
        NSLog(@"'Send anonymous profile info' change ignored because Sparkle Updater does not respond to setSendsSystemProfile:");
    }
}


-(IBAction) updatesCheckAutomaticallyCheckboxWasClicked: (id) sender
{
 	(void) sender;
	
   SUUpdater * updater = [[NSApp delegate] updater];
    if (  [updater respondsToSelector: @selector(setAutomaticallyChecksForUpdates:)]  ) {
        [[NSApp delegate] setOurPreferencesFromSparkles]; // Sparkle may have changed it's preferences so we update ours
        if (  ! [gTbDefaults boolForKey:@"updateCheckAutomatically"]  ) {
            // Was OFF, trying to change to ON
            [gTbDefaults setBool: TRUE forKey: @"updateCheckAutomatically"];
            [updater setAutomaticallyChecksForUpdates: YES];
        } else {
            // Was ON, change to OFF
            [gTbDefaults setBool: FALSE forKey: @"updateCheckAutomatically"];
            [updater setAutomaticallyChecksForUpdates: NO];
        }
    } else {
        NSLog(@"'Automatically Check for Updates' change ignored because Sparkle Updater does not respond to setAutomaticallyChecksForUpdates:");
    }
}


-(IBAction) updatesCheckForBetaUpdatesCheckboxWasClicked: (id) sender
{
    [gTbDefaults setBool: [sender state] forKey: @"updateCheckBetas"];
    
    [[NSApp delegate] changedCheckForBetaUpdatesSettings];
}


-(IBAction) updatesCheckNowButtonWasClicked: (id) sender
{
	(void) sender;
	
    [[NSApp delegate] checkForUpdates: self];
    [self updateLastCheckedDate];
}


-(IBAction) resetDisabledWarningsButtonWasClicked: (id) sender
{
	(void) sender;
	
    NSString * key;
    NSEnumerator * arrayEnum = [gProgramPreferences objectEnumerator];
    while (   (key = [arrayEnum nextObject])  ) {
        if (  [key hasPrefix: @"skipWarning"]  ) {
            if (  [gTbDefaults objectForKey: key]  ) {
                if (  [gTbDefaults canChangeValueForKey: key]  ) {
                    [gTbDefaults removeObjectForKey: key];
                }
            }
        }
    }
    
    arrayEnum = [gConfigurationPreferences objectEnumerator];
    while (  (key = [arrayEnum nextObject])  ) {
        if (  [key hasPrefix: @"-skipWarning"]  ) {
            [gTbDefaults removeAllObjectsWithSuffix: key];
        }
    }
}


-(IBAction) generalHelpButtonWasClicked: (id) sender
{
	(void) sender;
	
    MyGotoHelpPage(@"preferences-general.html", nil);
}


-(NSUInteger) selectedKeyboardShortcutIndex
{
    return selectedKeyboardShortcutIndex;
}


-(void) setSelectedKeyboardShortcutIndex: (NSUInteger) newValue
{
    if (  newValue != selectedKeyboardShortcutIndex  ) {
        NSArrayController * ac = [generalPrefsView keyboardShortcutArrayController];
        NSArray * list = [ac content];
        if (  newValue < [list count]  ) {
            selectedKeyboardShortcutIndex = newValue;
            
            // Select the new size
            [ac setSelectionIndex: newValue];
            
            // Set the preference
            [gTbDefaults setObject: [NSNumber numberWithUnsignedInt: newValue] forKey: @"keyboardShortcutIndex"];
            
            // Set the value we use
            [[NSApp delegate] setHotKeyIndex: newValue];
        }
    }
}    


-(NSUInteger) selectedMaximumLogSizeIndex
{
    return selectedMaximumLogSizeIndex;
}


-(void) setSelectedMaximumLogSizeIndex: (NSUInteger) newValue
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
            gMaximumLogSize = [newPref unsignedIntValue];
        }
    }
}

//***************************************************************************************************************

-(void) setupAppearanceIconSetButton {
	
    NSString * defaultIconSetName    = @"TunnelBlick.TBMenuIcons";
    
    NSString * iconSetToUse = [gTbDefaults objectForKey: @"menuIconSet"];
    if (  ! iconSetToUse  ) {
        iconSetToUse = defaultIconSetName;
    }
    
    // Search popup list for the specified filename and the default
    NSArray * icsContent = [[appearancePrefsView appearanceIconSetArrayController] content];
    unsigned i;
    unsigned iconSetIx = UINT_MAX;
    unsigned defaultIconSetIx = UINT_MAX;
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
	
    if (  iconSetIx == UINT_MAX) {
        iconSetIx = defaultIconSetIx;
    }
    
    if (  iconSetIx == UINT_MAX  ) {
        if (  [icsContent count] > 0) {
            if (  [iconSetToUse isEqualToString: defaultIconSetName]) {
                NSLog(@"Could not find '%@' icon set or default icon set; using first set found", iconSetToUse);
                iconSetIx = 0;
            } else {
                NSLog(@"Could not find '%@' icon set; using default icon set", iconSetToUse);
                iconSetIx = defaultIconSetIx;
            }
        } else {
            NSLog(@"Could not find any icon sets");
        }
    }
    
    if (  iconSetIx == UINT_MAX  ) {
		[NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"(None available)", @"Button"), @"name", @"", @"value", nil];
        [self setSelectedAppearanceIconSetIndex: 0];
    } else {
        [self setSelectedAppearanceIconSetIndex: iconSetIx];
    }
    
    [[appearancePrefsView appearanceIconSetButton] setEnabled: [gTbDefaults canChangeValueForKey: @"menuIconSet"]];
}

-(void) setupAppearanceConnectionWindowDisplayCriteriaButton {
	
    NSString * displayCriteria = [gTbDefaults objectForKey: @"connectionWindowDisplayCriteria"];
    if (  ! displayCriteria  ) {
        displayCriteria = @"showWhenConnecting";
    }
    
    NSUInteger displayCriteriaIx = UINT_MAX;
    NSArrayController * ac = [appearancePrefsView appearanceConnectionWindowDisplayCriteriaArrayController];
    NSArray * list = [ac content];
	unsigned i;
    for (  i=0; i<[list count]; i++  ) {
        NSDictionary * dict = [list objectAtIndex: i];
        NSString * preferenceValue = [dict objectForKey: @"value"];
        if (  [preferenceValue isEqualToString: displayCriteria]  ) {
            displayCriteriaIx = i;
            break;
        }
    }
    if (  displayCriteriaIx == UINT_MAX  ) {
        NSLog(@"'connectionWindowDisplayCriteria' preference value of '%@' is not available", displayCriteria);
        displayCriteriaIx = 0;  // First one should be 'showWhenConnecting'
    }
    
    if (  displayCriteriaIx < [list count]  ) {
        [self setSelectedAppearanceConnectionWindowDisplayCriteriaIndex: displayCriteriaIx];
    } else {
        NSLog(@"Invalid displayCriteriaIx %lu; maximum is %ld", (unsigned long)displayCriteriaIx, (long) [list count]-1);
    }
    
    [[appearancePrefsView appearanceConnectionWindowDisplayCriteriaButton] setEnabled: [gTbDefaults canChangeValueForKey: @"connectionWindowDisplayCriteria"]];
}

-(void) setupDisplayStatisticsWindowCheckbox {
    if (  [[gTbDefaults objectForKey: @"connectionWindowDisplayCriteria"] isEqualToString: @"neverShow"] ) {
        [[appearancePrefsView appearanceDisplayStatisticsWindowsCheckbox] setState: NSOffState];
        [[appearancePrefsView appearanceDisplayStatisticsWindowsCheckbox] setEnabled: NO];
    } else {
        [self setValueForCheckbox: [appearancePrefsView appearanceDisplayStatisticsWindowsCheckbox]
                    preferenceKey: @"doNotShowNotificationWindowOnMouseover"
                         inverted: YES
                       defaultsTo: FALSE];
    }
}    
    
-(void) setupDisplayStatisticsWindowWhenDisconnectedCheckbox {
    if (  [[gTbDefaults objectForKey: @"connectionWindowDisplayCriteria"] isEqualToString: @"neverShow"] ) {
        [[appearancePrefsView appearanceDisplayStatisticsWindowsWhenDisconnectedCheckbox] setState: NSOffState];
        [[appearancePrefsView appearanceDisplayStatisticsWindowsWhenDisconnectedCheckbox] setEnabled: NO];
    } else {
        [self setValueForCheckbox: [appearancePrefsView appearanceDisplayStatisticsWindowsWhenDisconnectedCheckbox]
                    preferenceKey: @"doNotShowDisconnectedNotificationWindows"
                         inverted: YES
                       defaultsTo: FALSE];
    }
}

-(void) setupAppearanceConnectionWindowScreenButton {
	
    selectedAppearanceConnectionWindowScreenIndex = UINT_MAX;
	
    NSArray * screens = [[NSApp delegate] screenList];
    
    if (   ([screens count] < 2)
		|| (selectedAppearanceConnectionWindowDisplayCriteriaIndex == 0)  ) {
        
		// Show the default screen, but don't change the preference
		BOOL wereDoingSetupOfUI = [[NSApp delegate] doingSetupOfUI];
		[[NSApp delegate] setDoingSetupOfUI: TRUE];
        [self setSelectedAppearanceConnectionWindowScreenIndex: 0];
		[[NSApp delegate] setDoingSetupOfUI: wereDoingSetupOfUI];
		
        [[appearancePrefsView appearanceConnectionWindowScreenButton] setEnabled: NO];
		
    } else {
		
        unsigned displayNumberFromPrefs = [gTbDefaults unsignedIntForKey: @"statusDisplayNumber" default: 0 min: 0 max: UINT_MAX];
        unsigned screenIxToSelect;
        if (  displayNumberFromPrefs == 0 ) {
            screenIxToSelect = 0;   // Screen to use was not specified, use default screen
        } else {
            screenIxToSelect = UINT_MAX;
            unsigned i;
            for (  i=0; i<[screens count]; i++) {
                NSDictionary * dict = [screens objectAtIndex: i];
                unsigned displayNumber = [[dict objectForKey: @"DisplayNumber"] unsignedIntValue];
                if (  displayNumber == displayNumberFromPrefs  ) {
                    screenIxToSelect = i+1;
                    break;
                }
            }
            
            if (  screenIxToSelect == UINT_MAX) {
                NSLog(@"Display # is not available, using default");
                screenIxToSelect = 0;
            }
        }
        
		NSArrayController * ac = [appearancePrefsView appearanceConnectionWindowScreenArrayController];
		NSArray * list = [ac content];
        if (  screenIxToSelect >= [list count]  ) {
            NSLog(@"Invalid screenIxToSelect %lu; maximum is %ld", (unsigned long)screenIxToSelect, (long) [list count]-1);
            screenIxToSelect = 0;
        }
        
        [self setSelectedAppearanceConnectionWindowScreenIndex: screenIxToSelect];
        
        [[appearancePrefsView appearanceConnectionWindowScreenButton] setEnabled: [gTbDefaults canChangeValueForKey: @"statusDisplayNumber"]];
    }
}

-(void) setupAppearanceView
{
	[self setupAppearanceIconSetButton];

    if (   mustPlaceIconInStandardPositionInStatusBar()  ) {
        NSButton * checkbox = [appearancePrefsView appearancePlaceIconNearSpotlightCheckbox];
        [checkbox setState:   NO];
        [checkbox setEnabled: NO];
    } else {
        [self setValueForCheckbox: [appearancePrefsView appearancePlaceIconNearSpotlightCheckbox]
                    preferenceKey: @"placeIconInStandardPositionInStatusBar"
                         inverted: YES
                       defaultsTo: FALSE];
    }
    
    [self setValueForCheckbox: [appearancePrefsView appearanceDisplayConnectionSubmenusCheckbox]
                preferenceKey: @"doNotShowConnectionSubmenus"
                     inverted: YES
                   defaultsTo: FALSE];
    
    [self setValueForCheckbox: [appearancePrefsView appearanceDisplayConnectionTimersCheckbox]
                preferenceKey: @"showConnectedDurations"
                     inverted: NO
                   defaultsTo: FALSE];
    
    [self setValueForCheckbox: [appearancePrefsView appearanceDisplaySplashScreenCheckbox]
                preferenceKey: @"doNotShowSplashScreen"
                     inverted: YES
                   defaultsTo: FALSE];
    
	[self setupAppearanceConnectionWindowDisplayCriteriaButton];
    
    // Note: setupAppearanceConnectionWindowScreenButton,
    //       setupDisplayStatisticsWindowCheckbox, and
    //       setupAppearanceDisplayStatisticsWindowsWhenDisconnectedCheckbox
	// are invoked by setSelectedAppearanceConnectionWindowDisplayCriteriaIndex,
	//                which is invoked by setupAppearanceConnectionWindowDisplayCriteriaButton
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

-(IBAction) appearanceDisplaySplashScreenCheckboxWasClicked: (id) sender
{
	if (  [sender state]  ) {
		[gTbDefaults setBool: FALSE forKey:@"doNotShowSplashScreen"];
	} else {
		[gTbDefaults setBool: TRUE  forKey:@"doNotShowSplashScreen"];
	}
}

-(IBAction) appearancePlaceIconNearSpotlightCheckboxWasClicked: (id) sender
{
	if (  [sender state]  ) {
		[gTbDefaults setBool: FALSE forKey:@"placeIconInStandardPositionInStatusBar"];
	} else {
		[gTbDefaults setBool: TRUE  forKey:@"placeIconInStandardPositionInStatusBar"];
	}
    
    // Start using the new setting
    [[NSApp delegate] recreateStatusItemAndMenu];
}

-(IBAction) appearanceDisplayStatisticsWindowsCheckboxWasClicked: (id) sender
{
	if (  [sender state]  ) {
		[gTbDefaults setBool: FALSE forKey:@"doNotShowNotificationWindowOnMouseover"];
	} else {
		[gTbDefaults setBool: TRUE  forKey:@"doNotShowNotificationWindowOnMouseover"];
	}
    [[[NSApp delegate] ourMainIconView] changedDoNotShowNotificationWindowOnMouseover];
}

-(IBAction) appearanceDisplayStatisticsWindowWhenDisconnectedCheckboxWasClicked: (NSButton *) sender
{
	if (  [sender state]  ) {
		[gTbDefaults setBool: FALSE forKey:@"doNotShowDisconnectedNotificationWindows"];
	} else {
		[gTbDefaults setBool: TRUE  forKey:@"doNotShowDisconnectedNotificationWindows"];
	}
    [[[NSApp delegate] ourMainIconView] changedDoNotShowNotificationWindowOnMouseover];
}

-(IBAction) appearanceHelpButtonWasClicked: (id) sender
{
	(void) sender;
	
    MyGotoHelpPage(@"preferences-appearance.html", nil);
}

-(NSUInteger) selectedAppearanceIconSetIndex
{
    return selectedAppearanceIconSetIndex;
}

-(void) setSelectedAppearanceIconSetIndex: (NSUInteger) newValue
{
    if (  newValue != selectedAppearanceIconSetIndex  ) {
        NSArrayController * ac = [appearancePrefsView appearanceIconSetArrayController];
        NSArray * list = [ac content];
        if (  newValue < [list count]  ) {
            // Select the new index
            [ac setSelectionIndex: newValue];
            
            if (  selectedAppearanceIconSetIndex != UINT_MAX  ) {
                // Set the preference
                NSString * iconSetName = [[[list objectAtIndex: newValue] objectForKey: @"value"] lastPathComponent];
                if (  [iconSetName isEqualToString: @"TunnelBlick.TBMenuIcons"]  ) {
                    [gTbDefaults removeObjectForKey: @"menuIconSet"];
                } else {
                    [gTbDefaults setObject: iconSetName forKey: @"menuIconSet"];
                }
            }
            
            selectedAppearanceIconSetIndex = newValue;
            
            // Start using the new setting
			if (  ! [[NSApp delegate] loadMenuIconSet]  ) {
				NSLog(@"Unable to load the Menu icon set");
				[[NSApp delegate] terminateBecause: terminatingBecauseOfError];
			}
        }
    }
}


-(NSUInteger) selectedAppearanceConnectionWindowDisplayCriteriaIndex
{
    return selectedAppearanceConnectionWindowDisplayCriteriaIndex;
}


-(void) setSelectedAppearanceConnectionWindowDisplayCriteriaIndex: (NSUInteger) newValue
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
            
            [self setupDisplayStatisticsWindowCheckbox];
            [self setupDisplayStatisticsWindowWhenDisconnectedCheckbox];
			[self setupAppearanceConnectionWindowScreenButton];
        }
    }
}


-(NSUInteger) selectedAppearanceConnectionWindowScreenIndex
{
    return selectedAppearanceConnectionWindowScreenIndex;
}

-(void) setSelectedAppearanceConnectionWindowScreenIndex: (NSUInteger) newValue
{
    if (  newValue != selectedAppearanceConnectionWindowScreenIndex  ) {
        NSArrayController * ac = [appearancePrefsView appearanceConnectionWindowScreenArrayController];
        NSArray * list = [ac content];
        if (  newValue < [list count]  ) {
            selectedAppearanceConnectionWindowScreenIndex = newValue;
            
            // Select the new size
            [ac setSelectionIndex: newValue];
            
            // Set the preference if this isn't just the initialization
            if (  ! [[NSApp delegate] doingSetupOfUI]  ) {
                // Set the preference
                NSNumber * displayNumber = [[list objectAtIndex: newValue] objectForKey: @"value"];
				[gTbDefaults setObject: displayNumber forKey: @"statusDisplayNumber"];
            }
        }
    }
}


-(IBAction) infoHelpButtonWasClicked: (id) sender
{
	(void) sender;
	
    MyGotoHelpPage(@"info.html", nil);
}


//***************************************************************************************************************

-(void) setupInfoView
{
}

//***************************************************************************************************************

-(void) setupUtilitiesView
{
}

-(IBAction) utilitiesRunEasyRsaButtonWasClicked: (id) sender
{
	(void) sender;
	
    NSString * userPath = easyRsaPathToUse(YES);
    if (  ! userPath  ) {
        NSLog(@"utilitiesRunEasyRsaButtonWasClicked: no easy-rsa folder!");
        [[utilitiesPrefsView utilitiesRunEasyRsaButton] setEnabled: NO];
        return;
    }
    
    openTerminalWithEasyRsaFolder(userPath);
}

-(IBAction) utilitiesOpenUninstallInstructionsButtonWasClicked: (id) sender
{
	(void) sender;
	
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.tunnelblick.net/uninstall.html"]];
}

-(IBAction) utilitiesKillAllOpenVpnButtonWasClicked: (id) sender
{
	(void) sender;
	
	if (  ! ALLOW_OPENVPNSTART_KILLALL  ) {
		return;
	}
	
    NSArray  * arguments = [NSArray arrayWithObject: @"killall"];
    OSStatus status = runOpenvpnstart(arguments, nil, nil);
    if (  status == EXIT_SUCCESS  ) {
        TBRunAlertPanel(NSLocalizedString(@"Warning!", @"Window title"),
                        NSLocalizedString(@"All OpenVPN process were terminated.", @"Window title"),
                        nil, nil, nil);
    } else {
        TBRunAlertPanel(NSLocalizedString(@"Warning!", @"Window title"),
                        NSLocalizedString(@"One or more OpenVPN processes could not be terminated.", @"Window title"),
                        nil, nil, nil);
    }
}

-(IBAction) utilitiesCopyConsoleLogButtonWasClicked: (id) sender {
	
	(void) sender;
	
	// Get OS and Tunnelblick version info
	NSString * versionContents = [[[NSApp delegate] openVPNLogHeader] stringByAppendingString:
								  (isUserAnAdmin()
								   ? @"; Admin user"
								   : @"; Standard user")];
	
	// Get tail of Console log
	NSString * consoleContents;
	if (  runningOnLeopardOrNewer()  ) {
		consoleContents = [self stringContainingRelevantConsoleLogEntries];
	} else {
		consoleContents = [self tigerConsoleContents];
	}
	
	NSString * output = [NSString stringWithFormat:
						 @"%@\n\nConsole Log:\n\n%@",
						 versionContents, consoleContents];
	
	NSPasteboard * pb = [NSPasteboard generalPasteboard];
	[pb declareTypes: [NSArray arrayWithObject: NSStringPboardType] owner: self];
	[pb setString: output forType: NSStringPboardType];
}

-(IBAction) utilitiesHelpButtonWasClicked: (id) sender
{
	(void) sender;
	
    MyGotoHelpPage(@"preferences-utilities.html", nil);
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

-(void) setSoundIndex: (NSUInteger *) index
                   to: (NSUInteger)   newValue
           preference: (NSString *)   preference
{
    NSArray * contents = [[configurationsPrefsView soundOnConnectArrayController] content];
    NSUInteger size = [contents count];
    if (  newValue < size  ) {
        VPNConnection * connection = [self selectedConnection];
        NSString * newName;
        NSSound  * newSound;
		BOOL       speakIt = FALSE;
        if (  newValue == 0) {
            newName = @"None";
            newSound = nil;
		} else if (  newValue == 1) {
			newName = @"Speak";
			newSound = nil;
			if (  ! doNotPlaySounds  ) {
				if (  [preference hasSuffix: @"tunnelUpSoundName"]  ) {
					[connection speakActivity: @"connected"];
				} else {
					[connection speakActivity: @"disconnected"];
				}
			}			
			speakIt = TRUE;
        } else {
            newName = [[contents objectAtIndex: newValue] objectForKey: @"name"];
            newSound = [NSSound soundNamed: newName];
            if (  newSound  ) {
                if (  ! doNotPlaySounds  ) {
                    [newSound play];
                }
            } else {
                NSLog(@"Sound '%@' is not available", newName);
            }
        }
        
		
		if ( ! [[NSApp delegate] doingSetupOfUI]  ) {
			NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
								   newName, @"NewValue",
								   preference, @"PreferenceName",
								   nil];
			[[NSApp delegate] performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
		}
        if (  [preference hasSuffix: @"tunnelUpSoundName"]  ) {
            [connection setTunnelUpSound: newSound];
			[connection setSpeakWhenConnected: speakIt];
        } else {
            [connection setTunnelDownSound: newSound];
			[connection setSpeakWhenDisconnected: speakIt];
        }

        *index = newValue;
        
    } else if (  size != 0  ) {
        NSLog(@"setSelectedSoundIndex: %ld but there are only %ld sounds", (long) newValue, (long) size);
    }
}

-(NSTextView *) logView
{
    return [configurationsPrefsView logView];
}

TBSYNTHESIZE_OBJECT_GET(retain, NSMutableArray *, leftNavDisplayNames)

TBSYNTHESIZE_OBJECT(retain, NSString *, previouslySelectedNameOnLeftNavList, setPreviouslySelectedNameOnLeftNavList)

TBSYNTHESIZE_OBJECT_GET(retain, ConfigurationsView *, configurationsPrefsView)

TBSYNTHESIZE_OBJECT_SET(NSString *, currentViewName, setCurrentViewName)

@end
