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


#import "MyPrefsWindowController.h"

#import "easyRsa.h"
#import "helper.h"
#import "sharedRoutines.h"

#import "AppearanceView.h"
#import "AuthAgent.h"
#import "ConfigurationManager.h"
#import "ConfigurationsView.h"
#import "GeneralView.h"
#import "InfoView.h"
#import "LeftNavDataSource.h"
#import "LeftNavItem.h"
#import "LeftNavViewController.h"
#import "MainIconView.h"
#import "MenuController.h"
#import "NSApplication+LoginItem.h"
#import "NSFileManager+TB.h"
#import "NSString+TB.h"
#import "SettingsSheetWindowController.h"
#import "Sparkle/SUUpdater.h"
#import "TBOperationQueue.h"
#import "TBUserDefaults.h"
#import "UIHelper.h"
#import "UtilitiesView.h"
#import "VPNConnection.h"

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

-(void) setSelectedWhenToConnectIndex: (NSUInteger) newValue;

-(void) setupPerConfigurationCheckbox: (NSButton *) checkbox
                                  key: (NSString *) key
                             inverted: (BOOL)       inverted
                            defaultTo: (BOOL)       defaultsTo;

-(void) setupSetNameserver:           (VPNConnection *) connection;
-(void) setupRouteAllTraffic:         (VPNConnection *) connection;
-(void) setupCheckIPAddress:          (VPNConnection *) connection;
-(void) setupResetPrimaryInterface:   (VPNConnection *) connection;
-(void) setupDisableIpv6OnTun:                    (VPNConnection *) connection;
-(void) setupPerConfigOpenvpnVersion: (VPNConnection *) connection;
-(void) setupNetworkMonitoring:       (VPNConnection *) connection;

-(void) setValueForCheckbox: (NSButton *) checkbox
              preferenceKey: (NSString *) preferenceKey
                   inverted: (BOOL)       inverted
                 defaultsTo: (BOOL)       defaultsTo;

-(void) updateConnectionStatusAndTime;

-(void) updateLastCheckedDate;

-(void) validateWhenToConnect: (VPNConnection *) connection;

@end

@implementation MyPrefsWindowController

TBSYNTHESIZE_OBJECT_GET(retain, NSMutableArray *, leftNavDisplayNames)

TBSYNTHESIZE_OBJECT(retain, NSString *, previouslySelectedNameOnLeftNavList, setPreviouslySelectedNameOnLeftNavList)

TBSYNTHESIZE_OBJECT_GET(retain, ConfigurationsView *, configurationsPrefsView)

TBSYNTHESIZE_OBJECT_GET(retain, SettingsSheetWindowController *, settingsSheetWindowController)

TBSYNTHESIZE_OBJECT_SET(NSString *, currentViewName, setCurrentViewName)

// Synthesize getters and direct setters:
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedSetNameserverIndex,           setSelectedSetNameserverIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedPerConfigOpenvpnVersionIndex, setSelectedPerConfigOpenvpnVersionIndexDirect)

TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedKeyboardShortcutIndex,        setSelectedKeyboardShortcutIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedMaximumLogSizeIndex,          setSelectedMaximumLogSizeIndexDirect)

TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedAppearanceIconSetIndex,       setSelectedAppearanceIconSetIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedAppearanceConnectionWindowDisplayCriteriaIndex, setSelectedAppearanceConnectionWindowDisplayCriteriaIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedAppearanceConnectionWindowScreenIndex, setSelectedAppearanceConnectionWindowScreenIndexDirect)

TBSYNTHESIZE_NONOBJECT_GET(NSUInteger, selectedWhenToConnectIndex)
TBSYNTHESIZE_NONOBJECT_GET(NSUInteger, selectedLeftNavListIndex)

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
    NSString * name = (  [UIHelper useOutlineViewOfConfigurations]
                       ? @"Preferences"
                       : @"Preferences-Tiger");
    NSString * finalName = [UIHelper appendRTLIfRTLLanguage: name];
	return finalName;
}


-(void) setupToolbar
{
	if (  [UIHelper languageAtLaunchWasRTL]  ) {
		// Add an NSToolbarFlexibleSpaceIdentifier item on the left, to force everything else to the right
		[self addView: (NSView *)[NSNull null]  label: NSToolbarFlexibleSpaceItemIdentifier                  image: (NSImage *)[NSNull null]];
		[self addView: infoPrefsView            label: NSLocalizedString(@"Info",           @"Window title") image: [NSImage imageNamed: @"Info"          ]];
		[self addView: utilitiesPrefsView       label: NSLocalizedString(@"Utilities",      @"Window title") image: [NSImage imageNamed: @"Utilities"     ]];
		[self addView: generalPrefsView         label: NSLocalizedString(@"Preferences",    @"Window title") image: [NSImage imageNamed: @"Preferences"   ]];
		[self addView: appearancePrefsView      label: NSLocalizedString(@"Appearance",     @"Window title") image: [NSImage imageNamed: @"Appearance"    ]];
		[self addView: configurationsPrefsView  label: NSLocalizedString(@"Configurations", @"Window title") image: [NSImage imageNamed: @"Configurations"]];
	} else {
		[self addView: configurationsPrefsView  label: NSLocalizedString(@"Configurations", @"Window title") image: [NSImage imageNamed: @"Configurations"]];
		[self addView: appearancePrefsView      label: NSLocalizedString(@"Appearance",     @"Window title") image: [NSImage imageNamed: @"Appearance"    ]];
		[self addView: generalPrefsView         label: NSLocalizedString(@"Preferences",    @"Window title") image: [NSImage imageNamed: @"Preferences"   ]];
		[self addView: utilitiesPrefsView       label: NSLocalizedString(@"Utilities",      @"Window title") image: [NSImage imageNamed: @"Utilities"     ]];
		[self addView: infoPrefsView            label: NSLocalizedString(@"Info",           @"Window title") image: [NSImage imageNamed: @"Info"          ]];
	}
	
    [self setupViews];
    
    [[self window] setDelegate: self];
}

static BOOL firstTimeShowingWindow = TRUE;

-(void) setupViews
{
    currentFrame = NSMakeRect(0.0, 0.0, 920.0, 390.0); // This is the size of each "view", as loaded from preferences.xib
    
	unsigned int ix = [UIHelper detailsWindowsViewIndexFromPreferencesWithMax: [toolbarIdentifiers count]-1];
	[self setCurrentViewName: [toolbarIdentifiers objectAtIndex: ix]];
    
    [self setSelectedPerConfigOpenvpnVersionIndexDirect:                   tbNumberWithInteger(NSNotFound)];
    [self setSelectedKeyboardShortcutIndexDirect:                          tbNumberWithInteger(NSNotFound)];
    [self setSelectedMaximumLogSizeIndexDirect:                            tbNumberWithInteger(NSNotFound)];
    [self setSelectedAppearanceIconSetIndexDirect:                         tbNumberWithInteger(NSNotFound)];
    [self setSelectedAppearanceConnectionWindowDisplayCriteriaIndexDirect: tbNumberWithInteger(NSNotFound)];
    [self setSelectedAppearanceConnectionWindowScreenIndexDirect:          tbNumberWithInteger(NSNotFound)];
    
    [self setupConfigurationsView];
    [self setupGeneralView];
    [self setupAppearanceView];
    [self setupUtilitiesView];
    [self setupInfoView];
}


-(void) resizeAllViewsExceptCurrent {
    
    NSView * currentView = [toolbarViews objectForKey: currentViewName];
    if (  currentView  ) {
        NSSize newSize = [currentView frame].size;
        if (  newSize.width != 0.0 ) {
            
            NSString * name;
            NSEnumerator * e = [toolbarViews keyEnumerator];
            while (  (name = [e nextObject])  ) {
                if (   [name isNotEqualTo: currentViewName]
                    && [name isNotEqualTo: NSToolbarFlexibleSpaceItemIdentifier]  ) {
                    NSView  * view = [toolbarViews objectForKey: name];
                    NSRect f = [view frame];
                    f.size = newSize;
                    [view setFrameSize:  newSize];
                }
            }
        } else {
            NSLog(@"resizeAllViewsExceptCurrent: [currentView frame].size.width is 0.0 for '%@'", currentViewName);
        }
    } else {
        NSLog(@"resizeAllViewsExceptCurrent: No view in toolbarViews for '%@'", currentViewName);
    }
}


- (IBAction) windowWillAppear
{
    if (  firstTimeShowingWindow  ) {
        // Set the window's position and size from the preferences (saved when window is closed), or center the window
        // Use the preferences only if the preference's version matches the TB version (since window size could be different in different versions of TB)
        NSString * tbVersion = [[[NSApp delegate] tunnelblickInfoDictionary] objectForKey: @"CFBundleVersion"];
        if (  [tbVersion isEqualToString: [gTbDefaults stringForKey:@"detailsWindowFrameVersion"]]    ) {
            NSString * mainFrameString  = [gTbDefaults stringForKey: @"detailsWindowFrame"];
            NSString * leftFrameString  = [gTbDefaults stringForKey: @"detailsWindowLeftFrame"];
			NSString * configurationsTabIdentifier         = [gTbDefaults stringForKey: @"detailsWindowConfigurationsTabIdentifier"];
            if (   mainFrameString != nil  ) {
                
                // Set the new frame for the window
                [[self window] setMinSize: NSMakeSize(760.0, 412.0)]; // WINDOW size, not view size
                [[self window] setMaxSize: NSMakeSize(FLT_MAX, FLT_MAX)];
                NSRect mainFrame = NSRectFromString(mainFrameString);
                [[self window] setFrame: mainFrame display: YES];     // display: YES so stretches properly
                
                // Resize all other views (so they are the same size as the current view (whose size changed if the window size changed)
                [self resizeAllViewsExceptCurrent];
            }
            
            if (  leftFrameString != nil  ) {
                NSRect leftFrame = NSRectFromString(leftFrameString);
                if (  leftFrame.size.width < LEFT_NAV_AREA_MINIMUM_SIZE  ) {
                    leftFrame.size.width = LEFT_NAV_AREA_MINIMUM_SIZE;
                }
                [[configurationsPrefsView leftSplitView] setFrame: leftFrame];
            }
			
			if (  configurationsTabIdentifier  ) {
				[[configurationsPrefsView configurationsTabView] selectTabViewItemWithIdentifier: configurationsTabIdentifier];
			}
        } else {
			[[self window] center];
            [[self window] setReleasedWhenClosed: NO];
		}

        [[self window] setShowsResizeIndicator: YES];

        firstTimeShowingWindow = FALSE;
    } else {
        if (  currentViewName  ) {
            NSView * currentView = [toolbarViews objectForKey: currentViewName];
            if (  currentView  ) {
                if (  [currentView respondsToSelector: @selector(newViewDidAppear:)]  ) {
                    [(id) currentView newViewDidAppear: currentView];
                }
            } else {
                NSLog(@"showWindow: '%@' not found in toolbarViews", currentViewName);
            }
        } else {
            NSLog(@"showWindow: currentViewName is nil");
        }
    }
}


-(void) windowWillClose:(NSNotification *)notification
{
	(void) notification;
	
    if (  currentViewName  ) {
        NSView * currentView = [toolbarViews objectForKey: currentViewName];
        if (  currentView  ) {
            if (  [currentView respondsToSelector: @selector(oldViewWillDisappear:identifier:)]  ) {
                [(id) currentView oldViewWillDisappear: currentView identifier: currentViewName];
            }
        } else {
            NSLog(@"windowWillClose: '%@' not found in toolbarViews", currentViewName);
        }
    } else {
        NSLog(@"windowWillClose: currentViewName is nil");
    }
    
    [[self selectedConnection] stopMonitoringLogFiles];
    
    // Save the window's frame and the splitView's frame and the TB version in the preferences
    NSString * mainFrameString = NSStringFromRect([[self window] frame]);
    NSString * leftFrameString = nil;
    if (  [[configurationsPrefsView leftSplitView] frame].size.width > (LEFT_NAV_AREA_MINIMAL_SIZE + 5.0)  ) {
        leftFrameString = NSStringFromRect([[configurationsPrefsView leftSplitView] frame]);
    }
	NSString * configurationsTabIdentifier = [[[configurationsPrefsView configurationsTabView] selectedTabViewItem] identifier];
    NSString * tbVersion = [[[NSApp delegate] tunnelblickInfoDictionary] objectForKey: @"CFBundleVersion"];
	unsigned int viewIx = [toolbarIdentifiers indexOfObject: currentViewName];
    BOOL saveIt = TRUE;
	unsigned int defaultViewIx = [UIHelper detailsWindowsViewIndexFromPreferencesWithMax: [toolbarIdentifiers count]-1];
	
    if (  [tbVersion isEqualToString: [gTbDefaults stringForKey:@"detailsWindowFrameVersion"]]    ) {
        if (   [mainFrameString             isEqualToString: [gTbDefaults stringForKey:@"detailsWindowFrame"]]
            && [leftFrameString             isEqualToString: [gTbDefaults stringForKey:@"detailsWindowLeftFrame"]]
			&& [configurationsTabIdentifier isEqualToString: [gTbDefaults stringForKey:@"detailsWindowConfigurationsTabIdentifier"]]
			&& (viewIx == defaultViewIx )  ) {
            saveIt = FALSE;
		}
	}
    
    if (saveIt) {
        [gTbDefaults setObject: mainFrameString forKey: @"detailsWindowFrame"];
        if (  leftFrameString ) {
            [gTbDefaults setObject: leftFrameString forKey: @"detailsWindowLeftFrame"];
        }
		[gTbDefaults setObject: [NSNumber numberWithUnsignedInt: viewIx] forKey: @"detailsWindowViewIndex"];
		if (  configurationsTabIdentifier  ) {
			[gTbDefaults setObject: configurationsTabIdentifier forKey: @"detailsWindowConfigurationsTabIdentifier"];
        }
        [gTbDefaults setObject: tbVersion forKey: @"detailsWindowFrameVersion"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}


// Overrides superclass
-(void) oldViewWillDisappear: (NSView *) view identifier: (NSString *) identifier
{
    if (  [view respondsToSelector: @selector(oldViewWillDisappear:identifier:)]  ) {
        [(id) view oldViewWillDisappear: view identifier: identifier];
    }
    
    if (   view == configurationsPrefsView  ) {
        [[self selectedConnection] stopMonitoringLogFiles];
    }
    
    // Resize all other views (so they are the same size as the current view -- in case the window was resized)
    [self resizeAllViewsExceptCurrent];
}

// Overrides superclass
-(void) newViewWillAppear: (NSView *) view identifier: (NSString *) identifier
{
    if (  [view respondsToSelector: @selector(newViewWillAppear:identifier:)]  ) {
        [(id) view newViewWillAppear: view identifier: identifier];
    }
    
    if (   view == configurationsPrefsView  ) {
        [[self selectedConnection] startMonitoringLogFiles];
    } else if (  view == generalPrefsView  ) {
		// Update our preferences from Sparkle's whenever we show the view
		// (Would be better if Sparkle told us when they changed, but it doesn't)
		[((MenuController *)[NSApp delegate]) setOurPreferencesFromSparkles];
		[self setupGeneralView];
	}
    
    // Track the name of the view currently being shown, so other methods can access the view
    [self setCurrentViewName: identifier];
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
		[infoPrefsView newViewDidAppear: infoPrefsView];	// Trigger the scrolling
    } else {
        NSLog(@"newViewDidAppear: invoked with unknown view");
    }
    
    // Save the current view in preferences so clicking "VPN Details..." will reload it.
    unsigned int viewIx = [toolbarIdentifiers indexOfObject: currentViewName];
    [gTbDefaults setObject: [NSNumber numberWithUnsignedInt: viewIx] forKey: @"detailsWindowViewIndex"];
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
	
	if (  [UIHelper useOutlineViewOfConfigurations]  ) {
		LeftNavViewController   * ovc    = [configurationsPrefsView outlineViewController];
		NSOutlineView           * ov     = [ovc outlineView];
		NSIndexSet              * idxSet = [ov selectedRowIndexes];
		return [idxSet count] == 1;
	}
	
	return TRUE;
}

-(void) setupConfigurationsView
{
	
	BOOL savedDoingSetupOfUI = [((MenuController *)[NSApp delegate]) doingSetupOfUI];
	[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: TRUE];

    [self setSelectedSetNameserverIndexDirect:           tbNumberWithInteger(NSNotFound)];   // Force a change when first set
    [self setSelectedPerConfigOpenvpnVersionIndexDirect: tbNumberWithInteger(NSNotFound)];
    selectedWhenToConnectIndex     = NSNotFound;

    selectedLeftNavListIndex = 0;
    
    [leftNavList                          release];
    leftNavList                         = nil;
    [leftNavDisplayNames                  release];
    leftNavDisplayNames                 = nil;
    [settingsSheetWindowController        release];
    settingsSheetWindowController       = nil;
    [previouslySelectedNameOnLeftNavList  release];
    previouslySelectedNameOnLeftNavList = [[gTbDefaults stringForKey: @"leftNavSelectedDisplayName"] retain];

    authorization = 0;
    
	[self setupLeftNavigationToDisplayName: previouslySelectedNameOnLeftNavList];
	
    // Right split view
    
    [[configurationsPrefsView configurationsTabView] setDelegate: self];
    
    VPNConnection * connection = [self selectedConnection];
    
    // Right split view - Settings tab

    if (  connection  ) {
    
        [self updateConnectionStatusAndTime];
        
        [self indicateNotWaitingForLogDisplay: [self selectedConnection]];
        [self validateWhenToConnect: [self selectedConnection]];
        
        [self setupSetNameserver:           [self selectedConnection]];
        [self setupRouteAllTraffic:         [self selectedConnection]];
        [self setupCheckIPAddress:          [self selectedConnection]];
        [self setupResetPrimaryInterface:   [self selectedConnection]];
        [self setupDisableIpv6OnTun:                    [self selectedConnection]];
        [self setupNetworkMonitoring:       [self selectedConnection]];
        [self setupPerConfigOpenvpnVersion: [self selectedConnection]];
        
        // Set up a timer to update connection times
        [((MenuController *)[NSApp delegate]) startOrStopUiUpdater];
    }
    
    [self validateDetailsWindowControls];   // Set windows enabled/disabled
	
	[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: savedDoingSetupOfUI];
}


-(BOOL) usingSetNameserver {
    NSString * name = [[self selectedConnection] displayName];
	if (  ! name  ) {
		return NO;
	}
	
    NSString * key = [name stringByAppendingString: @"useDNS"];
    unsigned ix = [gTbDefaults unsignedIntForKey: key
                                         default: 1
                                             min: 0
                                             max: MAX_SET_DNS_WINS_INDEX];
    return (ix == 1);
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
    NSArray * content = [connection modifyNameserverOptionList];
    [[configurationsPrefsView setNameserverArrayController] setContent: content];
    
    // Select the appropriate Set nameserver entry
    NSString * key = [[connection displayName] stringByAppendingString: @"useDNS"];

    unsigned arrayCount = [[[configurationsPrefsView setNameserverArrayController] content] count];
    if (  (arrayCount - 1) > MAX_SET_DNS_WINS_INDEX) {
        NSLog(@"MAX_SET_DNS_WINS_INDEX = %u but there are %u entries in the array", (unsigned)MAX_SET_DNS_WINS_INDEX, arrayCount);
        [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
    }
    
    NSInteger ix = [gTbDefaults unsignedIntForKey: key
                                default: 1
                                    min: 0
                                    max: MAX_SET_DNS_WINS_INDEX];
    
    [[configurationsPrefsView setNameserverPopUpButton] selectItemAtIndex: ix];
    [self setSelectedSetNameserverIndex: tbNumberWithInteger(ix)];
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
        [self setupPerConfigurationCheckbox: [configurationsPrefsView monitorNetworkForChangesCheckbox]
                                        key: @"-notMonitoringConnection"
                                   inverted: YES
                                  defaultTo: NO];
    }
}

-(void) setupRouteAllTraffic: (VPNConnection *) connection
{
    (void) connection;
    
    [self setupPerConfigurationCheckbox: [configurationsPrefsView routeAllTrafficThroughVpnCheckbox]
                                    key: @"-routeAllTrafficThroughVpn"
                               inverted: NO
                              defaultTo: NO];
}

-(void) setupCheckIPAddress: (VPNConnection *) connection
{
    (void) connection;
    
    if (  [gTbDefaults boolForKey: @"inhibitOutboundTunneblickTraffic"]  ) {
        [[configurationsPrefsView checkIPAddressAfterConnectOnAdvancedCheckbox] setState:   NSOffState];
        [[configurationsPrefsView checkIPAddressAfterConnectOnAdvancedCheckbox] setEnabled: NO];
    } else {
        [self setupPerConfigurationCheckbox: [configurationsPrefsView checkIPAddressAfterConnectOnAdvancedCheckbox]
                                        key: @"-notOKToCheckThatIPAddressDidNotChangeAfterConnection"
                                   inverted: YES
                                  defaultTo: NO];
    }
}

-(void) setupResetPrimaryInterface: (VPNConnection *) connection
{
    (void) connection;
    
    if (  [self usingSetNameserver]  ) {
        [self setupPerConfigurationCheckbox: [configurationsPrefsView resetPrimaryInterfaceAfterDisconnectCheckbox]
                                        key: @"-resetPrimaryInterfaceAfterDisconnect"
                                   inverted: NO
                                  defaultTo: NO];
    } else {
        [[configurationsPrefsView resetPrimaryInterfaceAfterDisconnectCheckbox] setState:   NSOffState];
        [[configurationsPrefsView resetPrimaryInterfaceAfterDisconnectCheckbox] setEnabled: NO];
    }
}

-(void) setupDisableIpv6OnTun: (VPNConnection *) connection
{
    (void) connection;
    
	NSString * type = [connection tapOrTun];
    if (   ( ! [type isEqualToString: @"tap"] )
		&& [self usingSetNameserver]  ) {
        [self setupPerConfigurationCheckbox: [configurationsPrefsView disableIpv6OnTunCheckbox]
                                        key: @"-doNotDisableIpv6onTun"
                                   inverted: YES
                                  defaultTo: NO];
		
	} else {
		[[configurationsPrefsView disableIpv6OnTunCheckbox] setState:   NSOffState];
		[[configurationsPrefsView disableIpv6OnTunCheckbox] setEnabled: NO];
	}
}

-(void) setupPerConfigOpenvpnVersion: (VPNConnection *) connection
{
    
	if (  ! connection  ) {
        return;
    }
    
    NSArrayController * ac = [configurationsPrefsView perConfigOpenvpnVersionArrayController];
    NSArray * list = [ac content];
    
    if (  [list count] < 3  ) {
        return; // Have not set up the list yet
    }
    
    NSUInteger versionIx    = [connection getOpenVPNVersionIxToUse];
    
    NSString * key = [[connection displayName] stringByAppendingString: @"-openvpnVersion"];
    NSString * prefVersion = [gTbDefaults stringForKey: key];
    NSUInteger listIx = 0;                              // Default to the first entry -- "Default (x.y.z)"

    if (  [prefVersion length] == 0  ) {
        // Use default; if actually using it, show we are using default (1st entry), otherwise show what we are using
        if (  versionIx == 0  ) {
            listIx = 0;
        } else {
            listIx = versionIx + 1; // + 1 to skip over the 1st entry (default)
        }
    } else if (  [prefVersion isEqualToString: @"-"]  ) {
        // Use latest. If we are actually using it, show we are using latest (last entry), otherwise show what we are using
        NSArray  * versionNames = [((MenuController *)[NSApp delegate]) openvpnVersionNames];
        if (  versionIx == [versionNames count] - 1  ) {
            listIx = versionIx + 2; // + 2 to skip over the 1st entry (default) and the specific entry, to get to "Latest (version)"
        } else {
            listIx = versionIx + 1; // + 1 to skip over the 1st entry (default)
        }
    } else {
        // Using a specific version, but show what we are actually using instead
        listIx = versionIx + 1; // + 1 to skip over the 1st entry (default)
    }
    
    [self setSelectedPerConfigOpenvpnVersionIndex: tbNumberWithInteger(listIx)];
    
    [[configurationsPrefsView perConfigOpenvpnVersionButton] setEnabled: [gTbDefaults canChangeValueForKey: key]];
}

-(void) setupLeftNavigationToDisplayName: (NSString *) displayNameToSelect
{
    NSUInteger leftNavIndexToSelect = NSNotFound;
    
    NSMutableArray * currentFolders = [NSMutableArray array]; // Components of folder enclosing most-recent leftNavList/leftNavDisplayNames entry
    NSArray * allConfigsSorted = [[[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveNumericCompare:)];
    
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
	leftNavList         = [[NSMutableArray alloc] initWithCapacity: [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] count]];
	leftNavDisplayNames = [[NSMutableArray alloc] initWithCapacity: [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] count]];
	int currentLeftNavIndex = 0;
	
	NSEnumerator* configEnum = [allConfigsSorted objectEnumerator];
    NSString * dispNm;
    while (  (dispNm = [configEnum nextObject])  ) {
        VPNConnection * connection = [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] objectForKey: dispNm];
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
	
	if (  [UIHelper useOutlineViewOfConfigurations]  ) {
		
		LeftNavViewController * oVC = [[self configurationsPrefsView] outlineViewController];
        NSOutlineView         * oView = [oVC outlineView];
        LeftNavDataSource     * oDS = [[self configurationsPrefsView] leftNavDataSrc];
        [oDS reload];
		[oView reloadData];
		
		// Expand items that were left expanded previously and get row # we should select (that matches displayNameToSelect)
		
		NSInteger ix = 0;	// Track row # of name we are to display

		NSArray * expandedDisplayNames = [gTbDefaults arrayForKey: @"leftNavOutlineViewExpandedDisplayNames"];
        LeftNavViewController * outlineViewController = [configurationsPrefsView outlineViewController];
        NSOutlineView * outlineView = [outlineViewController outlineView];
        [outlineView expandItem: [outlineView itemAtRow: 0]];
        NSInteger r;
        for (  r=0; r<[outlineView numberOfRows]; r++) {
            id item = [outlineView itemAtRow: r];
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
        [self setupSetNameserver:            nil];
        [self setupRouteAllTraffic:          nil];
        [self setupCheckIPAddress:           nil];
        [self setupResetPrimaryInterface:    nil];
        [self setupDisableIpv6OnTun:                     nil];
        [self setupNetworkMonitoring:        nil];
		[self setupPerConfigOpenvpnVersion:  nil];
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


-(void) updateConnectionStatusAndTime
{
	if (  [super windowHasLoaded]  ) {
		[[self window] setTitle: [self windowTitle: NSLocalizedString(@"Configurations", @"Window title")]];
	}
}

-(void) indicateWaitingForDiagnosticInfoToClipboard
{
    [[configurationsPrefsView diagnosticInfoToClipboardProgressIndicator] startAnimation: self];
	[[configurationsPrefsView diagnosticInfoToClipboardProgressIndicator] setHidden: NO];
	[[configurationsPrefsView diagnosticInfoToClipboardButton] setEnabled: NO];
}


-(void) indicateNotWaitingForDiagnosticInfoToClipboard
{
	[[configurationsPrefsView diagnosticInfoToClipboardProgressIndicator] stopAnimation: self];
	[[configurationsPrefsView diagnosticInfoToClipboardProgressIndicator] setHidden: YES];
    [[configurationsPrefsView diagnosticInfoToClipboardButton] setEnabled: (   [self oneConfigurationIsSelected]
																			&& (! [gTbDefaults boolForKey: @"disableCopyLogToClipboardButton"]))];
}

-(void) indicateWaitingForConsoleLogToClipboard
{
    [[utilitiesPrefsView consoleLogToClipboardProgressIndicator] startAnimation: self];
	[[utilitiesPrefsView consoleLogToClipboardProgressIndicator] setHidden: NO];
	[[utilitiesPrefsView consoleLogToClipboardButton] setEnabled: NO];
}


-(void) indicateNotWaitingForConsoleLogToClipboard
{
	[[utilitiesPrefsView consoleLogToClipboardProgressIndicator] stopAnimation: self];
	[[utilitiesPrefsView consoleLogToClipboardProgressIndicator] setHidden: YES];
    [[utilitiesPrefsView consoleLogToClipboardButton] setEnabled: YES];
}

-(void) indicateWaitingForKillAllOpenVPN
{
    [[utilitiesPrefsView killAllOpenVPNProgressIndicator] startAnimation: self];
    [[utilitiesPrefsView killAllOpenVPNProgressIndicator] setHidden: NO];
    [[utilitiesPrefsView utilitiesKillAllOpenVpnButton]   setEnabled: NO];
}


-(void) indicateNotWaitingForKillAllOpenVPN
{
    [[utilitiesPrefsView killAllOpenVPNProgressIndicator] stopAnimation: self];
    [[utilitiesPrefsView killAllOpenVPNProgressIndicator] setHidden: YES];
    [[utilitiesPrefsView utilitiesKillAllOpenVpnButton]   setEnabled: YES];
}

-(void) indicateWaitingForLogDisplay: (VPNConnection *) theConnection
{
    if (  theConnection == [self selectedConnection]  ) {
        [[configurationsPrefsView logDisplayProgressIndicator] startAnimation: self];
        [[configurationsPrefsView logDisplayProgressIndicator] setHidden: NO];
    }
}


-(void) indicateNotWaitingForLogDisplay: (VPNConnection *) theConnection
{
    if (  theConnection == [self selectedConnection]  ) {
        [[configurationsPrefsView logDisplayProgressIndicator] stopAnimation: self];
        [[configurationsPrefsView logDisplayProgressIndicator] setHidden: YES];
    }
}

// Set a checkbox from preferences
-(void) setupPerConfigurationCheckbox: (NSButton *) checkbox
                                  key: (NSString *) key
                             inverted: (BOOL)       inverted
                            defaultTo: (BOOL)       defaultsTo
{
    if (  checkbox  ) {
        VPNConnection * connection = [self selectedConnection];
        if (  connection  ) {
            NSString * actualKey = [[connection displayName] stringByAppendingString: key];
            BOOL state = (  defaultsTo
						  ? [gTbDefaults boolWithDefaultYesForKey: actualKey]
						  : [gTbDefaults boolForKey: actualKey]);
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
}


-(void) validateDetailsWindowControls
{
    VPNConnection * connection = [self selectedConnection];
    
	[self updateConnectionStatusAndTime];
	
    if (   connection
        && ([TBOperationQueue shouldUIBeEnabledForDisplayName: [connection displayName]] )  ) {
        
        [self validateConnectAndDisconnectButtonsForConnection: connection];
        
		// diagnosticInfoToClipboardProgressIndicator is controlled by indicateWaitingForDiagnosticInfoToClipboard and indicateNotWaitingForDiagnosticInfoToClipboard
		[[configurationsPrefsView diagnosticInfoToClipboardButton] setEnabled: (   [[configurationsPrefsView diagnosticInfoToClipboardProgressIndicator] isHidden]
																				&& [self oneConfigurationIsSelected])];
		
        // Left split view
        
		[[configurationsPrefsView addConfigurationButton]    setEnabled: TRUE];
		
        [[configurationsPrefsView removeConfigurationButton] setEnabled: (   [self oneConfigurationIsSelected]
																		  || (   connection
																			  && [UIHelper useOutlineViewOfConfigurations]))];
		
		[[configurationsPrefsView workOnConfigurationPopUpButton] setEnabled: ( ! [gTbDefaults boolForKey: @"disableWorkOnConfigurationButton"] )];
		[[configurationsPrefsView workOnConfigurationPopUpButton] setAutoenablesItems: YES];
        
        NSString * configurationPath = [connection configPath];
        [[configurationsPrefsView makePrivateMenuItem] setEnabled: [configurationPath hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]];
        [[configurationsPrefsView makeSharedMenuItem]  setEnabled: [configurationPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]];
        if (  [ConfigurationManager userCanEditConfiguration: [connection configPath]]  ) {
            [[configurationsPrefsView editOpenVPNConfigurationFileMenuItem] setTitle: NSLocalizedString(@"Edit OpenVPN Configuration File...", @"Menu Item")];
        } else {
            [[configurationsPrefsView editOpenVPNConfigurationFileMenuItem] setTitle: NSLocalizedString(@"Examine OpenVPN Configuration File...", @"Menu Item")];
        }
        
        // Right split view - log tab
        
        
        // Right split view - settings tab
        
        [self validateWhenToConnect:        connection];
		
		[self setupPerConfigOpenvpnVersion: connection];
		
		[self setupSetNameserver:           connection];
        
		[self setupNetworkMonitoring:       connection];
		[self setupRouteAllTraffic:         connection];
        [self setupDisableIpv6OnTun:        connection];
        [self setupCheckIPAddress:          connection];
        [self setupResetPrimaryInterface:   connection];
 		
        [[configurationsPrefsView advancedButton] setEnabled: YES];
        [settingsSheetWindowController            setupSettingsFromPreferences];
        
    } else {
        
        // There is not a connection selected or it should have its UI controls disabled. Don't let the user do anything except add a configuration or disconnect one.

		[[configurationsPrefsView addConfigurationButton]           setEnabled: YES];
        [[configurationsPrefsView removeConfigurationButton]        setEnabled: NO];
        [[configurationsPrefsView workOnConfigurationPopUpButton]   setEnabled: NO];
        
        // The "Log" and "Settings" items can't be selected because tabView:shouldSelectTabViewItem: will return NO if there is no selected connection
        
        [[configurationsPrefsView logDisplayProgressIndicator]      setHidden: YES];

        [[configurationsPrefsView diagnosticInfoToClipboardButton]  setEnabled: NO];
		// diagnosticInfoToClipboardProgressIndicator is controlled by indicateWaitingForDiagnosticInfoToClipboard and indicateNotWaitingForDiagnosticInfoToClipboard
        
        [[configurationsPrefsView connectButton]                    setEnabled: NO];
        [[configurationsPrefsView disconnectButton]                 setEnabled: ( connection ? YES : NO)];
        
        [[configurationsPrefsView whenToConnectPopUpButton]         setEnabled: NO];
        
        [[configurationsPrefsView setNameserverPopUpButton]         setEnabled: NO];
        
        [[configurationsPrefsView monitorNetworkForChangesCheckbox]             setEnabled: NO];
        [[configurationsPrefsView routeAllTrafficThroughVpnCheckbox]            setEnabled: NO];
        [[configurationsPrefsView checkIPAddressAfterConnectOnAdvancedCheckbox] setEnabled: NO];
        [[configurationsPrefsView resetPrimaryInterfaceAfterDisconnectCheckbox] setEnabled: NO];
        [[configurationsPrefsView disableIpv6OnTunCheckbox]                     setEnabled: NO];
        
        [[configurationsPrefsView perConfigOpenvpnVersionButton]    setEnabled: NO];
        
        [[configurationsPrefsView advancedButton]                   setEnabled: NO];
        [settingsSheetWindowController                              setupSettingsFromPreferences];
    }
}

-(NSArray *) displayNamesOfSelection {
    
    if (  [UIHelper useOutlineViewOfConfigurations]  ) {
        
        NSMutableArray * displayNames = [[[NSMutableArray alloc] init] autorelease];
        
        LeftNavViewController   * ovc    = [configurationsPrefsView outlineViewController];
        NSOutlineView           * ov     = [ovc outlineView];
        NSIndexSet              * idxSet = [ov selectedRowIndexes];
        if  (  [idxSet count] != 0  ) {
            
#ifdef TBAnalyzeONLY
#warning "NOT AN EXECUTABLE -- ANALYZE ONLY but does not fully analyze code in removeSelectedConfigurations"
            (void) idxSet;
#else
            [idxSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
                (void) stop;
                LeftNavItem * item = [ov itemAtRow: idx];
                NSString * name = [item displayName];
                if (  [name length] != 0  ) {	// Ignore folders; just process configurations
                    [displayNames addObject: name];
                }
            }];
#endif
        }
        
        return [NSArray arrayWithArray: displayNames];
    } else {
        VPNConnection * connection = [self selectedConnection];
        NSString * name = [connection displayName];
        if (  name  ) {
            return [NSArray arrayWithObject: name];
        } else {
            return nil;
        }
    }
}

-(BOOL) isAnySelectedConfigurationPrivate {
	
	NSArray * displayNames = [self displayNamesOfSelection];
	NSString * displayName;
	NSEnumerator * e = [displayNames objectEnumerator];
	while (  (displayName = [e nextObject])  ) {
		NSString * path = [[[NSApp delegate] myConfigDictionary] objectForKey: displayName];
		if (  ! path  ) {
			NSLog(@"isAnySelectedConfigurationPrivate: Internal error: No configuration for '%@'", displayName);
		}
		if (  [path hasPrefix: [gPrivatePath stringByAppendingPathComponent: @"/"]]  ) {
			return TRUE;
		}
	}
	
	return FALSE;
}

-(BOOL) isAnySelectedConfigurationShared {
	
	NSArray * displayNames = [self displayNamesOfSelection];
	NSString * displayName;
	NSEnumerator * e = [displayNames objectEnumerator];
	while (  (displayName = [e nextObject])  ) {
		NSString * path = [[[NSApp delegate] myConfigDictionary] objectForKey: displayName];
		if (  ! path  ) {
			NSLog(@"isAnySelectedConfigurationShared: Internal error: No configuration for '%@'", displayName);
		}
		if (  [path hasPrefix: [L_AS_T_SHARED stringByAppendingPathComponent: @"/"]]  ) {
			return TRUE;
		}
	}
	
	return FALSE;
}

-(BOOL) isAnySelectedConfigurationNotDeployed {
	
	NSArray * displayNames = [self displayNamesOfSelection];
	NSString * displayName;
	NSEnumerator * e = [displayNames objectEnumerator];
	while (  (displayName = [e nextObject])  ) {
		NSString * path = [[[NSApp delegate] myConfigDictionary] objectForKey: displayName];
		if (  ! path  ) {
			NSLog(@"isAnySelectedConfigurationShared: Internal error: No configuration for '%@'", displayName);
		}
		if (  ! [path hasPrefix: @"/Application/Tunnelblick.app/Contents/Resources/Deploy/"]  ) {
			return TRUE;
		}
	}
	
	return FALSE;
}

-(BOOL) isAnySelectedConfigurationCredentialed {
	
	NSArray * displayNames = [self displayNamesOfSelection];
	NSString * displayName;
	NSEnumerator * e = [displayNames objectEnumerator];
	while (  (displayName = [e nextObject])  ) {

		NSString * group = credentialsGroupFromDisplayName(displayName);
		AuthAgent * myAuthAgent = [[[AuthAgent alloc] initWithConfigName: displayName credentialsGroup: group] autorelease];
		
		[myAuthAgent setAuthMode: @"privateKey"];
		if (  [myAuthAgent keychainHasAnyCredentials]  ) {
			return TRUE;
		}
		
		[myAuthAgent setAuthMode: @"password"];
		if (  [myAuthAgent keychainHasAnyCredentials]  ) {
			return TRUE;
		}
	}		
	
	return FALSE;
}

-(BOOL) isAnySelectedConfigurationDoNotShowOnTbMenu {
	
	NSArray * displayNames = [self displayNamesOfSelection];
	NSString * displayName;
	NSEnumerator * e = [displayNames objectEnumerator];
	while (  (displayName = [e nextObject])  ) {
		NSString * key = [displayName stringByAppendingString: @"-doNotShowOnTunnelblickMenu"];
		if (  [gTbDefaults boolForKey: key]  ) {
			return TRUE;
		}
	}
	
	return FALSE;
}

-(BOOL) isAnySelectedConfigurationShowOnTbMenu {
	
	NSArray * displayNames = [self displayNamesOfSelection];
	NSString * displayName;
	NSEnumerator * e = [displayNames objectEnumerator];
	while (  (displayName = [e nextObject])  ) {
		NSString * key = [displayName stringByAppendingString: @"-doNotShowOnTunnelblickMenu"];
		if (  ! [gTbDefaults boolForKey: key]  ) {
			return TRUE;
		}
	}
	
	return FALSE;
}

- (BOOL)validateMenuItem:(NSMenuItem *) anItem
{
	VPNConnection * connection = [self selectedConnection];
	
	if (  [anItem action] == @selector(addConfigurationButtonWasClicked:)  ) {
		return ! [gTbDefaults boolForKey: @"disableAddConfigurationButton"];
	}
	
	if (  [anItem action] == @selector(removeConfigurationButtonWasClicked:)  ) {
		return (   ( ! [gTbDefaults boolForKey: @"disableRemoveConfigurationButton"] )
				&& [self isAnySelectedConfigurationNotDeployed]);
	}
	
	if (  [anItem action] == @selector(renameConfigurationMenuItemWasClicked:)  ) {
		return (   ( ! [gTbDefaults boolForKey: @"disableRenameConfigurationMenuItem"] )
				&& ( [self isAnySelectedConfigurationNotDeployed])
				&& [self oneConfigurationIsSelected] );
	}
	
	if (  [anItem action] == @selector(duplicateConfigurationMenuItemWasClicked:)  ) {
		return (   (! [gTbDefaults boolForKey: @"disableDuplicateConfigurationMenuItem"] )
				&& [self isAnySelectedConfigurationNotDeployed]
				&& [self oneConfigurationIsSelected] );
	}
	
	if (  [anItem action] == @selector(makePrivateMenuItemWasClicked:)  ) {
		return [self isAnySelectedConfigurationShared];
	}
	
	if (  [anItem action] == @selector(makeSharedMenuItemWasClicked:)  ) {
		return [self isAnySelectedConfigurationPrivate];
		
	}
	if (  [anItem action] == @selector(revertToShadowMenuItemWasClicked:)  ) {
		return (   ( ! [gTbDefaults boolForKey: @"disableRevertToShadowMenuItem"] )
				&& (   [[connection configPath] hasPrefix: [gPrivatePath stringByAppendingString: @"/"]])
				&& ( ! [connection shadowCopyIsIdentical] )  );
	}
	
	if (  [anItem action] == @selector(showOnTbMenuMenuItemWasClicked:)  ) {
		return [self isAnySelectedConfigurationDoNotShowOnTbMenu];
	}
	
	if (  [anItem action] == @selector(doNotShowOnTbMenuMenuItemWasClicked:)  ) {
		return [self isAnySelectedConfigurationShowOnTbMenu];
	}
	
	if (  [anItem action] == @selector(editOpenVPNConfigurationFileMenuItemWasClicked:)  ) {
		return (   ( ! [gTbDefaults boolForKey: @"disableExamineOpenVpnConfigurationFileMenuItem"] )
				&& [self oneConfigurationIsSelected]);
	}
	
	if (  [anItem action] == @selector(showOpenvpnLogMenuItemWasClicked:)  ) {
		NSString * path = [[self selectedConnection] openvpnLogPath];
		return (   ( ! [gTbDefaults boolForKey: @"disableShowOpenVpnLogInFinderMenuItem"] )
				&& [[connection configPath] hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]
				&& [self oneConfigurationIsSelected]
				&& path
				&&[gFileMgr fileExistsAtPath: [[self selectedConnection] openvpnLogPath]]);
	}
	
	if (  [anItem action] == @selector(removeCredentialsMenuItemWasClicked:)  ) {
		return (   ( ! [gTbDefaults boolForKey: @"disableDeleteConfigurationCredentialsInKeychainMenuItem"] )
				&& [self isAnySelectedConfigurationCredentialed] );
	}
	
	if (  [anItem action] == @selector(whenToConnectManuallyMenuItemWasClicked:)  ) {
		return TRUE;
	}
	
	if (  [anItem action] == @selector(whenToConnectTunnelBlickLaunchMenuItemWasClicked:)  ) {
		return TRUE;
	}
	
	if (  [anItem action] == @selector(whenToConnectOnComputerStartMenuItemWasClicked:)  ) {
		return [[self selectedConnection] mayConnectWhenComputerStarts];
	}
	
	NSLog(@"MyPrefsWindowController:validateMenuItem: Unknown menuItem %@", [anItem description]);
	return NO;
}


// Overrides superclass method
// If showing the Configurations tab, window title is:
//      configname (Shared/Private/Deployed): Status (hh:mm:ss) - Tunnelblick
// Otherwise, window title is:
//      tabname - Tunnelblick
-(NSString *) windowTitle: (NSString *) currentItemLabel
{
	(void) currentItemLabel;
	
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *appName = [[NSFileManager defaultManager] displayNameAtPath: bundlePath];
    if (  [appName hasSuffix: @".app"]  ) {
        appName = [appName substringToIndex: [appName length] - 4];
    }
    
    NSString * windowLabel = [NSString stringWithFormat: @"%@ - Tunnelblick", localizeNonLiteral(currentViewName, @"Window title")];

    if (  [currentViewName isEqualToString: NSLocalizedString(@"Configurations", @"Window title")]  ) {
        VPNConnection * connection = [self selectedConnection];
        if (  connection  ) {
            NSString * status = localizeNonLiteral([connection state], @"Connection status");
            NSString * connectionTimeString = @"";
            if (   [connection isConnected]
                && [gTbDefaults boolWithDefaultYesForKey: @"showConnectedDurations"]  ) {
				connectionTimeString = [connection connectTimeString];
            }
            windowLabel = [NSString stringWithFormat: NSLocalizedString(@"%@%@: %@%@ - %@", @"Window title for the VPN Details window when showing the 'Configurations' panel. The 1st %@ is name of the configuration, 2nd is either ' (Private)' or ' (Shared)', 3rd is the status of the connection, 4th is the amount of time the configuration has been connected, 5th is the name of the application (usually 'Tunnelblick'). Some of these may be ommitted under certain circumstances"), [connection localizedName], [connection displayLocation], status, connectionTimeString, appName];
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
															 && ( ! [gTbDefaults boolForKey: disableConnectButtonKey] )
															 && [TBOperationQueue shouldUIBeEnabledForDisplayName: displayName])];
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
    NSUInteger ix = tbUnsignedIntegerValue(selectedSetNameserverIndex);
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
    if (  selectedLeftNavListIndex != NSNotFound  ) {
        if (  selectedLeftNavListIndex < [leftNavDisplayNames count]  ) {
            NSString * dispNm = [leftNavDisplayNames objectAtIndex: selectedLeftNavListIndex];
            if (  dispNm != nil) {
                VPNConnection* connection = [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] objectForKey: dispNm];
                if (  connection  ) {
                    return connection;
                }
                NSArray *allConnections = [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] allValues];
                if (  [allConnections count] != 0  ) {
                    return [allConnections objectAtIndex:0];
                }
                return nil;
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
		NSString * oldRequestedState = [connection requestedState];
        [connection startDisconnectingUserKnows: [NSNumber numberWithBool: YES]];
        if (  [oldRequestedState isEqualToString: @"EXITING"]  ) {
			[connection displaySlowDisconnectionDialogLater];
        }
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
	
    [ConfigurationManager addConfigurationGuideInNewThread];
}


-(IBAction) makePrivateMenuItemWasClicked: (id) sender
{
    (void) sender;
    
    NSArray * displayNames = [self displayNamesOfSelection];
    
    if (  [displayNames count] != 0  ) {
		[ConfigurationManager makeConfigurationsPrivateInNewThreadWithDisplayNames: displayNames];
    }
}

-(IBAction) makeSharedMenuItemWasClicked: (id) sender
{
    (void) sender;
    
    NSArray * displayNames = [self displayNamesOfSelection];
    
    if (  [displayNames count] != 0  ) {
		[ConfigurationManager makeConfigurationsSharedInNewThreadWithDisplayNames: displayNames];
    }
}

-(IBAction) removeConfigurationButtonWasClicked: (id) sender
{
    (void) sender;
    
    NSArray * displayNames = [self displayNamesOfSelection];
    
    if (  [displayNames count] != 0  ) {
		[ConfigurationManager removeConfigurationsInNewThreadWithDisplayNames: displayNames];
    }

}

-(IBAction) renameConfigurationMenuItemWasClicked: (id) sender
{
	(void) sender;

	NSString * sourceDisplayName = [[self selectedConnection] displayName];
	if (  sourceDisplayName  ) {
		[ConfigurationManager renameConfigurationInNewThreadWithDisplayName: sourceDisplayName];
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
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString(@"You may not duplicate a configuration which is set to start when the computer starts.", @"Window text"));
        return;
    }
    
    NSString * sourcePath = [connection configPath];
    if (  [sourcePath hasPrefix: [gDeployPath stringByAppendingString: @"/"]]  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString(@"You may not duplicate a Deployed configuration.", @"Window text"));
        return;
    }
    
    // Get a target path like the finder: "xxx copy.ext", "xxx copy 2.ext", "xxx copy 3.ext", etc.
    NSString * sourceFolder = [sourcePath stringByDeletingLastPathComponent];
    NSString * sourceLast = [sourcePath lastPathComponent];
    NSString * sourceLastName = [sourceLast stringByDeletingPathExtension];
    NSString * sourceExtension = [sourceLast pathExtension];
    NSString * targetName;
    NSString * targetPath;
    int copyNumber;
    for (  copyNumber=1; copyNumber<100; copyNumber++  ) {
        if (  copyNumber == 1) {
            targetName = [sourceLastName stringByAppendingString: NSLocalizedString(@" copy", @"Suffix for a duplicate of a file")];
        } else {
            targetName = [sourceLastName stringByAppendingFormat: NSLocalizedString(@" copy %d", @"Suffix for a duplicate of a file"), copyNumber];
        }
        
        targetPath = [[sourceFolder stringByAppendingPathComponent: targetName] stringByAppendingPathExtension: sourceExtension];
        if (  ! [gFileMgr fileExistsAtPath: targetPath]  ) {
            break;
        }
    }
    
    if (  copyNumber > 99  ) {
        TBShowAlertWindow(NSLocalizedString(@"Warning", @"Window title"),
                          NSLocalizedString(@"Too many duplicate configurations already exist.", @"Window text"));
        return;
    }
    
    [ConfigurationManager duplicateConfigurationInNewThreadPath: sourcePath toPath: targetPath];
}

-(IBAction) revertToShadowMenuItemWasClicked: (id) sender
{
	(void) sender;
	
	NSArray * displayNames = [self displayNamesOfSelection];
    
    if (  [displayNames count] != 0  ) {
		[ConfigurationManager revertToShadowInNewThreadWithDisplayNames: displayNames];
    }
}

-(IBAction) showOnTbMenuMenuItemWasClicked: (id) sender
{
    (void) sender;
	
	NSArray * displayNames = [self displayNamesOfSelection];
    NSString * displayName;
	NSEnumerator * e = [displayNames objectEnumerator];
	while (  (displayName = [e nextObject])  ) {
		NSString * key = [displayName stringByAppendingString: @"-doNotShowOnTunnelblickMenu"];
		[gTbDefaults removeObjectForKey: key];
	}
	
	[[NSApp delegate] changedDisplayConnectionSubmenusSettings];
}

-(IBAction) doNotShowOnTbMenuMenuItemWasClicked: (id) sender
{
	(void) sender;
	
	NSArray * displayNames = [self displayNamesOfSelection];
	NSString * displayName;
	NSEnumerator * e = [displayNames objectEnumerator];
	while (  (displayName = [e nextObject])  ) {
		NSString * key = [displayName stringByAppendingString: @"-doNotShowOnTunnelblickMenu"];
		[gTbDefaults setBool: YES forKey: key];
	}
	
	[[NSApp delegate] changedDisplayConnectionSubmenusSettings];
}

-(IBAction) editOpenVPNConfigurationFileMenuItemWasClicked: (id) sender
{
	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (connection  ) {
        [ConfigurationManager editOrExamineConfigurationForConnection: connection];
    } else {
        NSLog(@"editOpenVPNConfigurationFileMenuItemWasClicked but no configuration selected");
    }
    
    [connection invalidateConfigurationParse];
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
            TBShowAlertWindow(NSLocalizedString(@"File not found", @"Window title"),
                              NSLocalizedString(@"The OpenVPN log does not yet exist or has been deleted.", @"Window text"));
        }
    } else {
        NSLog(@"showOpenvpnLogMenuItemWasClicked but no configuration selected");
    }
}


-(IBAction) removeCredentialsMenuItemWasClicked: (id) sender
{
	(void) sender;
    
    NSArray * displayNames = [self displayNamesOfSelection];
    
    if (  [displayNames count] != 0  ) {
		[ConfigurationManager removeCredentialsInNewThreadWithDisplayNames: displayNames];
    }
}	
	

// Log tab

-(IBAction) diagnosticInfoToClipboardButtonWasClicked: (id) sender {

	(void) sender;
	
	[self indicateWaitingForDiagnosticInfoToClipboard];
	
	[ConfigurationManager putDiagnosticInfoOnClipboardInNewThreadForDisplayName: [[self selectedConnection] displayName]];
	
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
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                              NSLocalizedString(@"Private configurations cannot connect when the computer starts.\n\n"
                                                "First make the configuration shared, then change this setting.", @"Window text"));
        } else if (  ! [[configurationPath pathExtension] isEqualToString: @"tblk"]  ) {
            NSUInteger ix = selectedWhenToConnectIndex;
            selectedWhenToConnectIndex = 2;
            [[configurationsPrefsView whenToConnectPopUpButton] selectItemAtIndex: (int)ix];
            [self setSelectedWhenToConnectIndex: ix];
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                              NSLocalizedString(@"Only a Tunnelblick VPN Configuration (.tblk) can start when the computer starts.", @"Window text"));
        } else if (  ! [[self selectedConnection] mayConnectWhenComputerStarts]  ) {
            NSUInteger ix = selectedWhenToConnectIndex;
            selectedWhenToConnectIndex = 2;
            [[configurationsPrefsView whenToConnectPopUpButton] selectItemAtIndex: (int)ix];
            [self setSelectedWhenToConnectIndex: ix];
            TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                              NSLocalizedString(@"A configuration which requires a passphrase (private key) or a username and password cannot start when the computer starts.", @"Window text"));
        } else {
            [self setSelectedWhenToConnectIndex: 2];
        }
    } else {
        NSLog(@"whenToConnectOnComputerStartMenuItemWasClicked but no configuration selected");
    }
}

-(void) setSelectedPerConfigOpenvpnVersionIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedPerConfigOpenvpnVersionIndex]]  ) {
        NSArrayController * ac = [configurationsPrefsView perConfigOpenvpnVersionArrayController];
        NSArray * list = [ac content];
        if (  tbUnsignedIntegerValue(newValue) < [list count]  ) {
            
            [self setSelectedPerConfigOpenvpnVersionIndexDirect: newValue];
            
            // Set the preference if this isn't just the initialization
            if (  ! [((MenuController *)[NSApp delegate]) doingSetupOfUI]  ) {
                NSString * newPreferenceValue = [[list objectAtIndex: tbUnsignedIntegerValue(newValue)] objectForKey: @"value"];
				NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
									   newPreferenceValue, @"NewValue",
									   @"-openvpnVersion", @"PreferenceName",
									   nil];
				[((MenuController *)[NSApp delegate]) performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
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

-(IBAction) monitorNetworkForChangesCheckboxWasClicked: (NSButton *) sender
{
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-notMonitoringConnection"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: YES];
    
    [settingsSheetWindowController monitorNetworkForChangesCheckboxChangedForConnection: [self selectedConnection]];
}

-(IBAction) routeAllTrafficThroughVpnCheckboxWasClicked: (NSButton *) sender {
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-routeAllTrafficThroughVpn"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: NO];
}

-(IBAction) checkIPAddressAfterConnectOnAdvancedCheckboxWasClicked: (NSButton *) sender
{
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-notOKToCheckThatIPAddressDidNotChangeAfterConnection"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: YES];
}

-(IBAction) resetPrimaryInterfaceAfterDisconnectCheckboxWasClicked: (NSButton *) sender {
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-resetPrimaryInterfaceAfterDisconnect"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: NO];
}

-(IBAction) disableIpv6OnTunCheckboxWasClicked: (NSButton *) sender
{
    [((MenuController *)[NSApp delegate]) setBooleanPreferenceForSelectedConnectionsWithKey: @"-doNotDisableIpv6onTun"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: YES];
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
    
    NSString * displayName = [connection displayName];
    
    BOOL enableWhenComputerStarts = [connection mayConnectWhenComputerStarts];
    
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
                // All is OK -- prefs say to connect when system starts and launchd .plist agrees and it isn't a private configuration and has no credentials
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
            // Private configuration or has credentials
            if (  ! launchdPlistWillConnectOnSystemStart  ) {
                // Prefs, but not launchd, says will connnect on system start but it is a private configuration or has credentials
                NSLog(@"Preferences for '%@' say it should connect when the computer starts but it is a private configuration or has credentials. Attempting to repair preferences...", displayName);
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
                    NSLog(@"Preferences for '%@' say it should connect when the computer starts and a launchd .plist exists for that, but it is a private configuration or has credentials. User cancelled attempt to repair.", displayName);
                    ix = 2;
                } else {
                    NSLog(@"Preferences for '%@' say it should connect when the computer starts and a launchd .plist exists for that, but it is a private configuration or has credentials. The launchd .plist has been removed. Attempting to repair preferences...", displayName);
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
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          [NSString stringWithFormat: 
                           NSLocalizedString(@"Tunnelblick failed to repair problems with preferences for '%@'. Details are in the Console Log", @"Window text"),
                           [[NSApp delegate] localizedNameForDisplayName: displayName]]);
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


-(void) setSelectedSetNameserverIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedSetNameserverIndex]]  ) {
        if (  ! [((MenuController *)[NSApp delegate]) doingSetupOfUI]  ) {
			NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                   newValue, @"NewValue",
								   @"useDNS", @"PreferenceName",
								   nil];
			[((MenuController *)[NSApp delegate]) performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
			
			// Must set the key now (even though setPreferenceForSelectedConfigurationsWithDict: will set it later) so the rest of the code in this method runs with the new setting
            NSString * actualKey = [[[self selectedConnection] displayName] stringByAppendingString: @"useDNS"];
            [gTbDefaults setObject: newValue forKey: actualKey];
        }
		
		// Must set the key above (even though setPreferenceForSelectedConfigurationsWithDict: will set it later) so the following code works with the new setting

        [self setSelectedSetNameserverIndexDirect: newValue];
        
        // If script doesn't support monitoring, indicate it is off and disable it
        if (   (tbUnsignedIntegerValue(newValue) > 2)
            || (tbUnsignedIntegerValue(newValue) == 0)
            || ([[[configurationsPrefsView setNameserverArrayController] content] count] < 4)  ) {
            [[configurationsPrefsView monitorNetworkForChangesCheckbox] setState: NSOffState];
            [[configurationsPrefsView monitorNetworkForChangesCheckbox] setEnabled: NO];
        } else {
            [self setupPerConfigurationCheckbox: [configurationsPrefsView monitorNetworkForChangesCheckbox]
                                            key: @"-notMonitoringConnection"
                                       inverted: YES
                                      defaultTo: NO];
        }
		
		// Set up IPv6 and reset of primary interface
		[self setupDisableIpv6OnTun: [self selectedConnection]];
		[self setupResetPrimaryInterface: [self selectedConnection]];
		
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
	
	if (  [UIHelper useOutlineViewOfConfigurations]  ) {  // 10.5 and lower don't have setDelegate and setDataSource
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
	
	[self validateDetailsWindowControls];
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
		
		BOOL savedDoingSetupOfUI = [((MenuController *)[NSApp delegate]) doingSetupOfUI];
		[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: TRUE];
		
        [self setupSetNameserver:           newConnection];
        [self setupRouteAllTraffic:         newConnection];
        [self setupCheckIPAddress:          newConnection];
        [self setupResetPrimaryInterface:   newConnection];
        [self setupDisableIpv6OnTun:                    newConnection];
        [self setupNetworkMonitoring:       newConnection];
		[self setupPerConfigOpenvpnVersion: newConnection];
        
        [self validateDetailsWindowControls];
		
		[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: savedDoingSetupOfUI];
                
        [dispNm retain];
        [previouslySelectedNameOnLeftNavList release];
        previouslySelectedNameOnLeftNavList = dispNm;
        [gTbDefaults setObject: dispNm forKey: @"leftNavSelectedDisplayName"];
        
        [settingsSheetWindowController setConfigurationName: dispNm];
        
        [newConnection startMonitoringLogFiles];
    }
}

//***************************************************************************************************************

-(void) setupUpdatesCheckboxes {
	
    // Set values for the update checkboxes
	
	if (  [gTbDefaults boolForKey:@"inhibitOutboundTunneblickTraffic"]  ) {
		NSButton * checkbox = [generalPrefsView updatesCheckAutomaticallyCheckbox];
		[checkbox setState:   NSOffState];
		[checkbox setEnabled: NO];
		
	} else {
		[self setValueForCheckbox: [generalPrefsView updatesCheckAutomaticallyCheckbox]
					preferenceKey: @"updateCheckAutomatically"
						 inverted: NO
					   defaultsTo: FALSE];
    }
	
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

}

-(void) setupUpdatesAdminApprovalForKeyAndCertificateChangesCheckbox {
	
    NSButton * checkbox = [generalPrefsView generalAdminApprovalForKeyAndCertificateChangesCheckbox];
    [checkbox setState: (  okToUpdateConfigurationsWithoutAdminApproval()
                         ? NSOffState
                         : NSOnState)];
}

-(void) setupGeneralView
{
	[((MenuController *)[NSApp delegate]) setOurPreferencesFromSparkles]; // Sparkle may have changed it's preferences so we update ours
    
	[self setupUpdatesAdminApprovalForKeyAndCertificateChangesCheckbox];
	
	[self setValueForCheckbox: [generalPrefsView inhibitOutboundTBTrafficCheckbox]
				preferenceKey: @"inhibitOutboundTunneblickTraffic"
					 inverted: NO
				   defaultsTo: FALSE];
	
	[self setupUpdatesCheckboxes];
	
    // Select the keyboard shortcut
    
    unsigned kbsCount = [[[generalPrefsView keyboardShortcutArrayController] content] count];
    unsigned kbsIx = [gTbDefaults unsignedIntForKey: @"keyboardShortcutIndex"
                                            default: 1 /* F1  key */
                                                min: 0 /* (none) */
                                                max: kbsCount];
    
    [self setSelectedKeyboardShortcutIndex: [NSNumber numberWithUnsignedInt: kbsIx]];
    
    [[generalPrefsView keyboardShortcutButton] setEnabled: [gTbDefaults canChangeValueForKey: @"keyboardShortcutIndex"]];
    
    // Select the log size
    
    unsigned prefSize = gMaximumLogSize;
    
    NSUInteger logSizeIx = NSNotFound;
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
            listValueSize = NSNotFound;
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
    
    if (  logSizeIx == NSNotFound  ) {
        NSLog(@"'maxLogDisplaySize' preference value of %u is not available", prefSize);
        logSizeIx = 2;  // Second one should be '102400'
    }
    
    if (  logSizeIx < [list count]  ) {
        [self setSelectedMaximumLogSizeIndex: tbNumberWithUnsignedInteger(logSizeIx)];
    } else {
        NSLog(@"Invalid selectedMaximumLogSizeIndex %lu; maximum is %ld", (unsigned long)logSizeIx, (long) [list count]-1);
    }
    
    [[generalPrefsView maximumLogSizeButton] setEnabled: [gTbDefaults canChangeValueForKey: @"maxLogDisplaySize"]];
}

-(void) updateLastCheckedDate
{
    NSDate * lastCheckedDate = [gTbDefaults dateForKey: @"SULastCheckTime"];
    NSString * lastChecked = (  lastCheckedDate
                              ? [lastCheckedDate descriptionWithCalendarFormat: @"%Y-%m-%d %H:%M" timeZone: nil locale: [[NSUserDefaults standardUserDefaults] dictionaryRepresentation]]
                              : NSLocalizedString(@"(Never checked)", @"Window text"));
    [[generalPrefsView updatesLastCheckedTFC] setTitle: [NSString stringWithFormat:
                                                         NSLocalizedString(@"Last checked: %@", @"Window text"),
                                                         lastChecked]];
}


-(IBAction) updatesSendProfileInfoCheckboxWasClicked: (NSButton *) sender
{
    SUUpdater * updater = [((MenuController *)[NSApp delegate]) updater];
    if (  [updater respondsToSelector: @selector(setSendsSystemProfile:)]  ) {
        [((MenuController *)[NSApp delegate]) setOurPreferencesFromSparkles]; // Sparkle may have changed it's preferences so we update ours
        BOOL newValue = [sender state] == NSOnState;
        [gTbDefaults setBool: newValue forKey: @"updateSendProfileInfo"];
        [updater setSendsSystemProfile: newValue];
    } else {
        NSLog(@"'Send anonymous profile information when checking' change ignored because Sparkle Updater does not respond to setSendsSystemProfile:");
    }
}


-(IBAction) inhibitOutboundTBTrafficCheckboxWasClicked: (NSButton *) sender
{
	[gTbDefaults setBool: [sender state] forKey: @"inhibitOutboundTunneblickTraffic"];
	
	[self setupUpdatesCheckboxes];
	[self setupCheckIPAddress: nil];
	
    SUUpdater * updater = [((MenuController *)[NSApp delegate]) updater];
    if (  [updater respondsToSelector: @selector(setAutomaticallyChecksForUpdates:)]  ) {
        [((MenuController *)[NSApp delegate]) setOurPreferencesFromSparkles]; // Sparkle may have changed it's preferences so we update ours
 		[((MenuController *)[NSApp delegate]) setupUpdaterAutomaticChecks];
    } else {
        NSLog(@"'Inhibit automatic update checking and IP address checking' change ignored because the updater does not respond to setAutomaticallyChecksForUpdates:");
	}
}


-(IBAction) generalAdminApprovalForKeyAndCertificateChangesCheckboxWasClicked: (NSButton *) sender
{
    BOOL newState = [sender state];
    
    NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH];
    NSMutableDictionary * newDict = (  dict
                                     ? [NSMutableDictionary dictionaryWithDictionary: dict]
                                     : [NSMutableDictionary dictionaryWithCapacity: 1]);
    
    [newDict setObject: [NSNumber numberWithBool: ( ! newState) ] forKey: @"allowNonAdminSafeConfigurationReplacement"];
    
    NSString * tempDictionaryPath = [newTemporaryDirectoryPath() stringByAppendingPathComponent: @"forced-preferences.plist"];
    OSStatus status = (  tempDictionaryPath
                       ? (  [newDict writeToFile: tempDictionaryPath atomically: YES]
                          ? 0
                          : -1)
                       : -1);
    if (  status == EXIT_SUCCESS  ) {
        NSString * message = NSLocalizedString(@"Tunnelblick needs to change a setting that may only be changed by a computer administrator.", @"Window text");
        status = [[NSApp delegate] runInstaller: INSTALLER_INSTALL_FORCED_PREFERENCES
                                 extraArguments: [NSArray arrayWithObject: tempDictionaryPath]
                                usingAuthRefPtr: nil
                                        message: message
                              installTblksFirst: nil];
    }
    
    [gFileMgr tbRemovePathIfItExists: [tempDictionaryPath stringByDeletingLastPathComponent]];  // Ignore error; it has been logged
    
    if (  status == 0  ) {
        NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH];
        [gTbDefaults setPrimaryDefaults: dict];
    } else {
		if (  status != 1  ) { // that is, "status != cancelled by user"
			TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
							  NSLocalizedString(@"Tunnelblick was unable to make the change. See the Console Log for details.", @"Window text"));
        }
		
        // We have to restore the checkbox value, but not until after all processing of the ...WasClicked event is finished, because after
        // this method returns, it changes the checkbox value to reflect the user's click. To undo that, we delay changing the value for 0.2 seconds.
        [self performSelector: @selector(setupUpdatesAdminApprovalForKeyAndCertificateChangesCheckbox) withObject: nil afterDelay: 0.2];
    }
}


-(IBAction) updatesCheckAutomaticallyCheckboxWasClicked: (NSButton *) sender
{
    SUUpdater * updater = [((MenuController *)[NSApp delegate]) updater];
    if (  [updater respondsToSelector: @selector(setAutomaticallyChecksForUpdates:)]  ) {
        [((MenuController *)[NSApp delegate]) setOurPreferencesFromSparkles]; // Sparkle may have changed it's preferences so we update ours
		
        [gTbDefaults setBool: [sender state] forKey: @"updateCheckAutomatically"];
		[((MenuController *)[NSApp delegate]) setupUpdaterAutomaticChecks];
    } else {
        NSLog(@"'Automatically Check for Updates' change ignored because the updater does not respond to setAutomaticallyChecksForUpdates:");
    }
}


-(IBAction) updatesCheckForBetaUpdatesCheckboxWasClicked: (NSButton *) sender
{
    [gTbDefaults setBool: [sender state] forKey: @"updateCheckBetas"];
    
    [((MenuController *)[NSApp delegate]) changedCheckForBetaUpdatesSettings];
}


-(IBAction) updatesCheckNowButtonWasClicked: (id) sender
{
	(void) sender;
	
    [((MenuController *)[NSApp delegate]) checkForUpdates: self];
    [self updateLastCheckedDate];
}


-(IBAction) resetDisabledWarningsButtonWasClicked: (id) sender
{
	(void) sender;
	
    NSString * key;
    NSEnumerator * arrayEnum = [gProgramPreferences objectEnumerator];
    while (   (key = [arrayEnum nextObject])  ) {
        if (  [key hasPrefix: @"skipWarning"]  ) {
            if (  [gTbDefaults preferenceExistsForKey: key]  ) {
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


-(void) setSelectedKeyboardShortcutIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedKeyboardShortcutIndex]]  ) {
        NSArrayController * ac = [generalPrefsView keyboardShortcutArrayController];
        NSArray * list = [ac content];
        if (  tbUnsignedIntegerValue(newValue) < [list count]  ) {
            
            [self setSelectedKeyboardShortcutIndexDirect: newValue];
            
            // Select the new size
            [ac setSelectionIndex: tbUnsignedIntegerValue(newValue)];
            
            // Set the preference
            [gTbDefaults setObject: newValue forKey: @"keyboardShortcutIndex"];
            
            // Set the value we use
            [((MenuController *)[NSApp delegate]) setHotKeyIndex: [newValue unsignedIntValue]];
        }
    }
}    

-(void) setSelectedMaximumLogSizeIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedMaximumLogSizeIndex]]  ) {
        NSArrayController * ac = [generalPrefsView maximumLogSizeArrayController];
        NSArray * list = [ac content];
        if (  tbUnsignedIntegerValue(newValue) < [list count]  ) {
            
            // Set the index
            [self setSelectedMaximumLogSizeIndexDirect: newValue];
            
            // Select the new size
            [ac setSelectionIndex: tbUnsignedIntegerValue(newValue)];
            
            // Set the preference
            NSString * newPref = [[list objectAtIndex: tbUnsignedIntegerValue(newValue)] objectForKey: @"value"];
            [gTbDefaults setObject: newPref forKey: @"maxLogDisplaySize"];
            
            // Set the value we use
            gMaximumLogSize = [newPref unsignedIntValue];
        }
    }
}

//***************************************************************************************************************

-(void) setupAppearanceIconSetButton {
	
    NSString * defaultIconSetName = @"TunnelBlick.TBMenuIcons";
    
    NSString * iconSetToUse = [gTbDefaults stringForKey: @"menuIconSet"];
    if (  ! iconSetToUse  ) {
        iconSetToUse = defaultIconSetName;
    }
    
    // Search popup list for the specified filename and the default
    NSArray * icsContent = [[appearancePrefsView appearanceIconSetArrayController] content];
    unsigned i;
    NSUInteger iconSetIx = NSNotFound;
    unsigned defaultIconSetIx = NSNotFound;
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
	
    if (  iconSetIx == NSNotFound) {
        iconSetIx = defaultIconSetIx;
    }
    
    if (  iconSetIx == NSNotFound  ) {
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
    
    if (  iconSetIx == NSNotFound  ) {
		[NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"(None available)", @"Button"), @"name", @"", @"value", nil];
        [self setSelectedAppearanceIconSetIndex: tbNumberWithUnsignedInteger(0)];
    } else {
        [self setSelectedAppearanceIconSetIndex: tbNumberWithUnsignedInteger(iconSetIx)];
    }
    
    [[appearancePrefsView appearanceIconSetButton] setEnabled: [gTbDefaults canChangeValueForKey: @"menuIconSet"]];
}

-(void) setupAppearanceConnectionWindowDisplayCriteriaButton {
	
    NSString * displayCriteria = [gTbDefaults stringForKey: @"connectionWindowDisplayCriteria"];
    if (  ! displayCriteria  ) {
        displayCriteria = @"showWhenConnecting";
    }
    
    NSUInteger displayCriteriaIx = NSNotFound;
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
    if (  displayCriteriaIx == NSNotFound  ) {
        NSLog(@"'connectionWindowDisplayCriteria' preference value of '%@' is not available", displayCriteria);
        displayCriteriaIx = 0;  // First one should be 'showWhenConnecting'
    }
    
    if (  displayCriteriaIx < [list count]  ) {
        [self setSelectedAppearanceConnectionWindowDisplayCriteriaIndex: tbNumberWithUnsignedInteger(displayCriteriaIx)];
    } else {
        NSLog(@"Invalid displayCriteriaIx %lu; maximum is %ld", (unsigned long)displayCriteriaIx, (long) [list count]-1);
    }
    
    [[appearancePrefsView appearanceConnectionWindowDisplayCriteriaButton] setEnabled: [gTbDefaults canChangeValueForKey: @"connectionWindowDisplayCriteria"]];
}

-(void) setupDisplayStatisticsWindowCheckbox {
    if (  [[gTbDefaults stringForKey: @"connectionWindowDisplayCriteria"] isEqualToString: @"neverShow"] ) {
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
    if (  [[gTbDefaults stringForKey: @"connectionWindowDisplayCriteria"] isEqualToString: @"neverShow"] ) {
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
	
    [self setSelectedAppearanceConnectionWindowScreenIndexDirect: tbNumberWithUnsignedInteger(NSNotFound)];
	
    NSArray * screens = [((MenuController *)[NSApp delegate]) screenList];
    
    if (   ([screens count] < 2)
		|| ([[self selectedAppearanceConnectionWindowDisplayCriteriaIndex] isEqualTo: tbNumberWithUnsignedInteger(0)]  )  ) {
        
		// Show the default screen, but don't change the preference
		BOOL wereDoingSetupOfUI = [((MenuController *)[NSApp delegate]) doingSetupOfUI];
		[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: TRUE];
        [self setSelectedAppearanceConnectionWindowScreenIndex: tbNumberWithUnsignedInteger(0)];
		[((MenuController *)[NSApp delegate]) setDoingSetupOfUI: wereDoingSetupOfUI];
		
        [[appearancePrefsView appearanceConnectionWindowScreenButton] setEnabled: NO];
		
    } else {
		
        unsigned displayNumberFromPrefs = [gTbDefaults unsignedIntForKey: @"statusDisplayNumber" default: 0 min: 0 max: NSNotFound];
        NSUInteger screenIxToSelect;
        if (  displayNumberFromPrefs == 0 ) {
            screenIxToSelect = 0;   // Screen to use was not specified, use default screen
        } else {
            screenIxToSelect = NSNotFound;
            unsigned i;
            for (  i=0; i<[screens count]; i++) {
                NSDictionary * dict = [screens objectAtIndex: i];
                unsigned displayNumber = [[dict objectForKey: @"DisplayNumber"] unsignedIntValue];
                if (  displayNumber == displayNumberFromPrefs  ) {
                    screenIxToSelect = i+1;
                    break;
                }
            }
            
            if (  screenIxToSelect == NSNotFound) {
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
        
        [self setSelectedAppearanceConnectionWindowScreenIndex: tbNumberWithUnsignedInteger(screenIxToSelect)];
        
        [[appearancePrefsView appearanceConnectionWindowScreenButton] setEnabled: [gTbDefaults canChangeValueForKey: @"statusDisplayNumber"]];
    }
}

-(void) setupAppearancePlaceIconNearSpotlightCheckbox {
    
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
    
}

-(void) setupAppearanceView
{
	[self setupAppearanceIconSetButton];
    
    [self setupAppearancePlaceIconNearSpotlightCheckbox];

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

-(IBAction) appearanceDisplayConnectionSubmenusCheckboxWasClicked: (NSButton *) sender
{
    [gTbDefaults setBool: ! [sender state] forKey:@"doNotShowConnectionSubmenus"];
    [((MenuController *)[NSApp delegate]) changedDisplayConnectionSubmenusSettings];
}

-(IBAction) appearanceDisplayConnectionTimersCheckboxWasClicked: (NSButton *) sender
{
    [gTbDefaults setBool: [sender state]  forKey:@"showConnectedDurations"];
    [((MenuController *)[NSApp delegate]) changedDisplayConnectionTimersSettings];
}

-(IBAction) appearanceDisplaySplashScreenCheckboxWasClicked: (NSButton *) sender
{
	[gTbDefaults setBool: ! [sender state] forKey:@"doNotShowSplashScreen"];
}

-(IBAction) appearancePlaceIconNearSpotlightCheckboxWasClicked: (NSButton *) sender
{
	[gTbDefaults setBool: ! [sender state] forKey:@"placeIconInStandardPositionInStatusBar"];
    [((MenuController *)[NSApp delegate]) moveStatusItemIfNecessary];
}

-(IBAction) appearanceDisplayStatisticsWindowsCheckboxWasClicked: (NSButton *) sender
{
	[gTbDefaults setBool: ! [sender state] forKey:@"doNotShowNotificationWindowOnMouseover"];
    [[((MenuController *)[NSApp delegate]) ourMainIconView] changedDoNotShowNotificationWindowOnMouseover];
}

-(IBAction) appearanceDisplayStatisticsWindowWhenDisconnectedCheckboxWasClicked: (NSButton *) sender
{
	[gTbDefaults setBool: ! [sender state] forKey:@"doNotShowDisconnectedNotificationWindows"];
    [[((MenuController *)[NSApp delegate]) ourMainIconView] changedDoNotShowNotificationWindowOnMouseover];
}

-(IBAction) appearanceHelpButtonWasClicked: (id) sender
{
	(void) sender;
	
    MyGotoHelpPage(@"preferences-appearance.html", nil);
}

-(void) setSelectedAppearanceIconSetIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedAppearanceIconSetIndex]]  ) {
        NSArrayController * ac = [appearancePrefsView appearanceIconSetArrayController];
        NSArray * list = [ac content];
        if (  tbUnsignedIntegerValue(newValue) < [list count]  ) {
            
            [self setSelectedAppearanceIconSetIndexDirect: newValue];
            
            // Select the new index
            [ac setSelectionIndex: tbUnsignedIntegerValue(newValue)];
            
            // Set the preference
            if (  tbUnsignedIntegerValue(newValue) != NSNotFound  ) {
                // Set the preference
                NSString * iconSetName = [[[list objectAtIndex: tbUnsignedIntegerValue(newValue)] objectForKey: @"value"] lastPathComponent];
                if (  [iconSetName isEqualToString: @"TunnelBlick.TBMenuIcons"]  ) {
                    [gTbDefaults removeObjectForKey: @"menuIconSet"];
                } else {
                    [gTbDefaults setObject: iconSetName forKey: @"menuIconSet"];
                }
            }
            
            // Start using the new setting
			if (  ! [((MenuController *)[NSApp delegate]) loadMenuIconSet]  ) {
				NSLog(@"Unable to load the Menu icon set");
				[((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
			}
        }
    }
}


-(void) setSelectedAppearanceConnectionWindowDisplayCriteriaIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedAppearanceConnectionWindowDisplayCriteriaIndex]]  ) {
        NSArrayController * ac = [appearancePrefsView appearanceConnectionWindowDisplayCriteriaArrayController];
        NSArray * list = [ac content];
        if (  tbUnsignedIntegerValue(newValue) < [list count]  ) {
            
            [self setSelectedAppearanceConnectionWindowDisplayCriteriaIndexDirect: newValue];
            
            // Select the new index
            [ac setSelectionIndex: tbUnsignedIntegerValue(newValue)];
            
            // Set the preference
            NSDictionary * dict = [list objectAtIndex: tbUnsignedIntegerValue(newValue)];
            NSString * preferenceValue = [dict objectForKey: @"value"];
            [gTbDefaults setObject: preferenceValue forKey: @"connectionWindowDisplayCriteria"];
            
            [self setupDisplayStatisticsWindowCheckbox];
            [self setupDisplayStatisticsWindowWhenDisconnectedCheckbox];
			[self setupAppearanceConnectionWindowScreenButton];
        }
    }
}


-(void) setSelectedAppearanceConnectionWindowScreenIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedAppearanceConnectionWindowScreenIndex]]  ) {
        NSArrayController * ac = [appearancePrefsView appearanceConnectionWindowScreenArrayController];
        NSArray * list = [ac content];
        if (  tbUnsignedIntegerValue(newValue) < [list count]  ) {
            
            [self setSelectedAppearanceConnectionWindowScreenIndexDirect: newValue];
            
            // Select the new size
            [ac setSelectionIndex: tbUnsignedIntegerValue(newValue)];
            
            // Set the preference if this isn't just the initialization
            if (  ! [((MenuController *)[NSApp delegate]) doingSetupOfUI]  ) {
                // Set the preference
                NSNumber * displayNumber = [[list objectAtIndex: tbUnsignedIntegerValue(newValue)] objectForKey: @"value"];
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
	
    [self indicateWaitingForKillAllOpenVPN];
    
    [ConfigurationManager killAllOpenVPNInNewThread];
}

-(IBAction) consoleLogToClipboardButtonWasClicked: (id) sender {
	
	(void) sender;
	
	[self indicateWaitingForConsoleLogToClipboard];
	
	[ConfigurationManager putConsoleLogOnClipboardInNewThread];
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
    if (  checkbox  ) {
        BOOL value = (  defaultsTo
                      ? [gTbDefaults boolWithDefaultYesForKey: preferenceKey]
                      : [gTbDefaults boolForKey: preferenceKey]
                      );
        
        if (  inverted  ) {
            value = ! value;
        }
        
        [checkbox setState: (  value
                             ? NSOnState
                             : NSOffState)];
        [checkbox setEnabled: [gTbDefaults canChangeValueForKey: preferenceKey]];
    }
}

-(NSTextView *) logView
{
    return [configurationsPrefsView logView];
}

@end
