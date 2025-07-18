/*
 * Copyright 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021 Jonathan K. Bullard. All rights reserved.
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
#import "ConfigurationParser.h"
#import "ConfigurationsView.h"
#import "GeneralView.h"
#import "InfoView.h"
#import "LeftNavDataSource.h"
#import "LeftNavItem.h"
#import "LeftNavViewController.h"
#import "MenuController.h"
#import "NSApplication+LoginItem.h"
#import "NSDate+TB.h"
#import "NSFileManager+TB.h"
#import "NSString+TB.h"
#import "SettingsSheetWindowController.h"
#import "Sparkle/SUUpdater.h"
#import "SystemAuth.h"
#import "TBButton.h"
#import "TBOperationQueue.h"
#import "TBPopUpButton.h"
#import "TBUserDefaults.h"
#import "TunnelblickInfo.h"
#import "UIHelper.h"
#import "UtilitiesView.h"
#import "VPNConnection.h"

extern NSArray        * gConfigurationPreferences;
extern NSString       * gDeployPath;
extern NSFileManager  * gFileMgr;
extern unsigned         gMaximumLogSize;
extern MenuController * gMC;
extern NSString       * gPrivatePath;
extern NSArray        * gProgramPreferences;
extern TBUserDefaults * gTbDefaults;
extern TunnelblickInfo * gTbInfo;

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

-(void) setupPerConfigurationCheckbox: (TBButton *) checkbox
                                  key: (NSString *) key
                             inverted: (BOOL)       inverted
                            defaultTo: (BOOL)       defaultsTo;

-(void) setupSetNameserver:           (VPNConnection *) connection;
-(void) setupLoggingLevel:            (VPNConnection *) connection;
-(void) setupRouteAllTraffic:         (VPNConnection *) connection;
-(void) setupCheckIPAddress:          (VPNConnection *) connection;
-(void) setupDisableIpv6OnTun:                    (VPNConnection *) connection;
-(void) setupPerConfigOpenvpnVersion: (VPNConnection *) connection;
-(void) setupNetworkMonitoring:       (VPNConnection *) connection;

-(void) setValueForCheckbox: (TBButton *) checkbox
              preferenceKey: (NSString *) preferenceKey
                   inverted: (BOOL)       inverted
                 defaultsTo: (BOOL)       defaultsTo;

-(void) updateConnectionStatusAndTime;

-(void) updateLastCheckedDate;

@end

@implementation MyPrefsWindowController

TBSYNTHESIZE_OBJECT(retain, NSString *, previouslySelectedNameOnLeftNavList, setPreviouslySelectedNameOnLeftNavList)

TBSYNTHESIZE_OBJECT(retain, NSTimer *,  lockTheLockIconTimer,                setLockTheLockIconTimer)

TBSYNTHESIZE_OBJECT_GET(retain, ConfigurationsView *, configurationsPrefsView)

TBSYNTHESIZE_OBJECT_GET(retain, SettingsSheetWindowController *, settingsSheetWindowController)

TBSYNTHESIZE_OBJECT_SET(NSString *, currentViewName, setCurrentViewName)

// Synthesize getters and direct setters:
TBSYNTHESIZE_OBJECT(retain, NSDate   *, lockTimeoutDate,                      setLockTimeoutDate)

TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedSetNameserverIndex,           setSelectedSetNameserverIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedPerConfigOpenvpnVersionIndex, setSelectedPerConfigOpenvpnVersionIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedLoggingLevelIndex,            setSelectedLoggingLevelIndexDirect)

TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedKeyboardShortcutIndex,        setSelectedKeyboardShortcutIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedMaximumLogSizeIndex,          setSelectedMaximumLogSizeIndexDirect)

TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedAppearanceIconSetIndex,       setSelectedAppearanceIconSetIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedAppearanceConnectionWindowDisplayCriteriaIndex, setSelectedAppearanceConnectionWindowDisplayCriteriaIndexDirect)
TBSYNTHESIZE_OBJECT(retain, NSNumber *, selectedAppearanceConnectionWindowScreenIndex, setSelectedAppearanceConnectionWindowScreenIndexDirect)

TBSYNTHESIZE_NONOBJECT_GET(NSUInteger, selectedWhenToConnectIndex)

-(void) dealloc {
	
    [lockTheLockIconTimer invalidate];
    [lockTheLockIconTimer                release];
    TBLog(@"DB-AA", @"MyPrefsWindowController|dealloc: Invalidated the lock timer");
    
    [currentViewName                     release];
	[previouslySelectedNameOnLeftNavList release];
	[leftNavDisplayNames                 release];
    [settingsSheetWindowController       release];
	
    [super dealloc];
}

+ (NSString *)nibName {
    
// Overrides DBPrefsWindowController method
    NSString * name = [UIHelper appendRTLIfRTLLanguage: @"Preferences"];
	return name;
}

-(void) lockTheLockIcon {
    
    // Invoked when the window closes or authorization for lock times out
    
    if (  ! [NSThread isMainThread]  ) {
        NSLog(@"lockTheLockIcon invoked but not on main thread; stack trace = %@", callStack());
        [gMC terminateBecause: terminatingBecauseOfError];
        return;
    }
    
    [lockTheLockIconTimer invalidate];
    TBLog(@"DB-AA", @"lockTheLockIcon: Invalidated the lock timer");
    
    NSToolbarItem *item = [toolbarItems objectForKey: @"lockIcon"];
    
    if (  lockIconIsUnlocked  ) {
        
        // Icon is unlocked; lock it and release the authorization
        lockIconIsUnlocked = FALSE;
        [item setImage: [NSImage imageNamed: @"Lock"]];
        [item setLabel: NSLocalizedString(@"Enter admin mode", @"Toolbar text for 'Lock' icon")];
        [SystemAuth setLockSystemAuth: nil];
        TBLog(@"DB-AA", @"lockTheLockIcon: Locked the lock icon and set lockSystemAuth to nil");
    }
}

-(void) setLockLabelWithTimeLeft {
    
   NSTimeInterval timeLeft = [[self lockTimeoutDate] timeIntervalSinceDate: [NSDate date]];
    if (  timeLeft < 0.0 ) {
        timeLeft = 0.0;
    }
    NSTimeInterval minutes = floor(timeLeft / 60.0);
    NSTimeInterval seconds = round(timeLeft - (minutes * 60.0));
    if (  seconds >= 60.0  ) {
        seconds -= 60.0;
        minutes += 1.0;
    }
    NSString * timeLeftString = [NSString stringWithFormat: @"%01.0f:%02.0f", minutes, seconds];
    
    NSToolbarItem * item = [toolbarItems objectForKey: @"lockIcon"];
    [item setLabel: [NSString stringWithFormat: NSLocalizedString(@"Admin mode %@ remaining", @"Toolbar text for 'Lock' item"),
                     timeLeftString]];
}

-(void) lockIconTimerTick {
    
    NSTimeInterval timeLeft = [[self lockTimeoutDate] timeIntervalSinceDate: [NSDate date]];
    if (  timeLeft <= 0.5  ) {
        [lockTheLockIconTimer invalidate];
        [self performSelectorOnMainThread: @selector(lockTheLockIcon) withObject: nil waitUntilDone: NO];
    } else {
        [self performSelectorOnMainThread: @selector(setLockLabelWithTimeLeft) withObject: nil waitUntilDone: NO];
    }
}


-(void) enableLockIcon: (SystemAuth *) sa {
    
    // Invoked when the user has given (sa != nil) or cancelled (sa == nil) an authorization
    
    if (  ! [NSThread isMainThread]  ) {
        NSLog(@"enableLockIcon invoked but not on main thread; stack trace = %@", callStack());
        [gMC terminateBecause: terminatingBecauseOfError];
        return;
    }
    
    NSToolbarItem * item = [toolbarItems objectForKey: @"lockIcon"];
    if (  sa  ) {
        [SystemAuth setLockSystemAuth: sa];
        
        // Set up a timer to change the icon to be "locked" and release the authorization when the authorization is scheduled to time out
        NSTimer * timer = [NSTimer scheduledTimerWithTimeInterval: 1.0 target: self selector: @selector(lockIconTimerTick) userInfo: nil repeats: YES];
        [lockTheLockIconTimer invalidate];
        [self setLockTheLockIconTimer: timer];
        [self setLockTimeoutDate: [[NSDate date] dateByAddingTimeInterval: 300.00]];
        
        [item setImage: [NSImage imageNamed: @"Lock-open"]];
        [self setLockLabelWithTimeLeft];
        lockIconIsUnlocked = TRUE;
        if (  ! [[self window] isVisible]  ) {
            NSLog(@"enableLockIcon: displaying 'VPN Details' window because an authorization was obtained.");
            [self showWindow: nil];
            [gMC activateIgnoringOtherApps];

        }
        
        TBLog(@"DB-AA", @"enableLockIcon: Unlocked the lock icon, set lockSystemAuth, and set a timer to relock the lock icon in five minutes");
    } else {
        [item setLabel: NSLocalizedString(@"Enter admin mode", @"Toolbar text for 'Lock' item")];
        [gMC activateIgnoringOtherApps];
    }
    
    TBLog(@"DB-AA", @"enableLockIcon: Enabling the lock icon");
    [item setEnabled: YES];
}

-(void) toggleLockItemGetAuthThread {
    
    // NOTE: RUNS IN A SEPARATE THREAD so Tunnelblick is not blocked waiting for the user
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    NSString * prompt = NSLocalizedString(@"Tunnelblick Admin Mode\n\n Temporarily allow changes that require a computer administrator's authorization.\n\n The session expires after five minutes or when the 'VPN Details' window is closed.", @"Window text");
    SystemAuth * sa = [[SystemAuth newAuthWithPrompt: prompt] autorelease];
    if (  sa  ) {
        // We update the UI in the main thread to avoid having the task finish when there are still pending CoreAnimation tasks to complete
        TBLog(@"DB-AA", @"toggleLockItemGetAuthTask: Received authorization; requesting main thread enable the lock icon and show lock icon as opened");
    } else {
        sa = nil;
        TBLog(@"DB-AA", @"toggleLockItemGetAuthTask: Authorization was cancelled; requesting main thread enable the lock icon");
    }
    
    [self performSelectorOnMainThread: @selector(enableLockIcon:) withObject: sa waitUntilDone: NO];
    
    [pool drain];
}

-(void) toggleLockItem {
    
    // Executes only on main thread, when user clicks the lock icon in the "VPN Details" window
    
    NSToolbarItem *item = [toolbarItems objectForKey: @"lockIcon"];
    
    // Ignore this click if we are already processing a click
    if (  ! [item isEnabled]  ) {
        return;
    }

    if (  lockIconIsUnlocked  ) {
        
        // Lock icon is showing "Unlocked"
        lockIconIsUnlocked = FALSE;
        [item setImage: [NSImage imageNamed: @"Lock"]];
        [item setLabel: NSLocalizedString(@"Enter admin mode", @"Toolbar text for 'Lock' item")];
        [lockTheLockIconTimer invalidate];
        [SystemAuth setLockSystemAuth: nil];
        TBLog(@"DB-AA", @"toggleLockItem:  Locked the lock icon, invalidated the lock icon timeout timer, and set lockAuthRef to nil");
        
    } else {
        
        // Lock icon is showing "Locked"
        TBLog(@"DB-AA", @"toggleLockItem: Disabling the lock icon");
        [item setEnabled: NO];
        [item setLabel: NSLocalizedString(@"Authorizing...", @"Toolbar text for 'Lock' item indicating Tunnelblick is waiting for a computer administrator to authorize a request.")];
        TBLog(@"DB-AA", @"toggleLockItem: Creating thread to request authorization to unlock the lock icon");
        [NSThread detachNewThreadSelector: @selector(toggleLockItemGetAuthThread) toTarget: self withObject: nil];
    }
}

-(BOOL) validateToolbarItem: (NSToolbarItem *) toolbarItem
{
    
    return [toolbarItem isEnabled] ;
}

-(void) addLockIcon {

    NSString * identifier = @"lockIcon";
    [toolbarIdentifiers addObject: identifier];
    
    [toolbarViews setObject: [NSNull null] forKey:identifier];

    NSToolbarItem * item = [[[NSToolbarItem alloc] initWithItemIdentifier: identifier] autorelease];
    [item setLabel: NSLocalizedString(@"Enter admin mode", @"Toolbar text for 'Lock' item")];
    [item setImage: [NSImage imageNamed: @"Lock"]];
    [item setTarget: self];
	[item setAction: @selector(toggleLockItem)];
    [item setEnabled: YES];
	
	[toolbarItems setObject: item forKey: identifier];
}

-(void) setupToolbar
{
	if (  [UIHelper languageAtLaunchWasRTL]  ) {
		// Add an NSToolbarFlexibleSpaceIdentifier item on the left, to force the primary toolbar buttons to the right
		[self addLockIcon];
		[self addView: (NSView *)[NSNull null]  label: NSToolbarFlexibleSpaceItemIdentifier                  image: nil];
		[self addView: infoPrefsView            label: NSLocalizedString(@"Info",           @"Window title") image: [NSImage imageNamed: NSImageNameInfo              ]];
		[self addView: utilitiesPrefsView       label: NSLocalizedString(@"Utilities",      @"Window title") image: [NSImage imageNamed: NSImageNameAdvanced          ]];
		[self addView: generalPrefsView         label: NSLocalizedString(@"Preferences",    @"Window title") image: [NSImage imageNamed: NSImageNamePreferencesGeneral]];
		[self addView: appearancePrefsView      label: NSLocalizedString(@"Appearance",     @"Window title") image: [NSImage imageNamed: NSImageNameColorPanel        ]];
		[self addView: configurationsPrefsView  label: NSLocalizedString(@"Configurations", @"Window title") image: [NSImage imageNamed: NSImageNameNetwork           ]];
	} else {
		[self addView: configurationsPrefsView  label: NSLocalizedString(@"Configurations", @"Window title") image: [NSImage imageNamed: NSImageNameNetwork           ]];
		[self addView: appearancePrefsView      label: NSLocalizedString(@"Appearance",     @"Window title") image: [NSImage imageNamed: NSImageNameColorPanel        ]];
		[self addView: generalPrefsView         label: NSLocalizedString(@"Preferences",    @"Window title") image: [NSImage imageNamed: NSImageNamePreferencesGeneral]];
		[self addView: utilitiesPrefsView       label: NSLocalizedString(@"Utilities",      @"Window title") image: [NSImage imageNamed: NSImageNameAdvanced          ]];
		[self addView: infoPrefsView            label: NSLocalizedString(@"Info",           @"Window title") image: [NSImage imageNamed: NSImageNameInfo              ]];
		[self addView: (NSView *)[NSNull null]  label: NSToolbarFlexibleSpaceItemIdentifier                  image: nil];
		[self addLockIcon];
	}
	
    [self setupViews];
    
    [[self window] setDelegate: self];
}

static BOOL firstTimeShowingWindow = TRUE;

-(void) setupViews
{
    currentFrame = NSMakeRect(0.0, 0.0, 920.0, 390.0); // This is the size of each "view", as loaded from preferences.xib
    
	unsigned int ix = [UIHelper detailsWindowsViewIndexFromPreferencesWithCount: [toolbarIdentifiers count]];
	[self setCurrentViewName: [toolbarIdentifiers objectAtIndex: ix]];
    
    [self setSelectedPerConfigOpenvpnVersionIndexDirect:                   [NSNumber numberWithInteger: NSNotFound]];
    [self setSelectedKeyboardShortcutIndexDirect:                          [NSNumber numberWithInteger: NSNotFound]];
    [self setSelectedMaximumLogSizeIndexDirect:                            [NSNumber numberWithInteger: NSNotFound]];
    [self setSelectedAppearanceIconSetIndexDirect:                         [NSNumber numberWithInteger: NSNotFound]];
    [self setSelectedAppearanceConnectionWindowDisplayCriteriaIndexDirect: [NSNumber numberWithInteger: NSNotFound]];
    [self setSelectedAppearanceConnectionWindowScreenIndexDirect:          [NSNumber numberWithInteger: NSNotFound]];
    
    [self setupConfigurationsView];
    [self setupGeneralView];
    [self setupAppearanceView];
    [self setupUtilitiesView];
    [self setupInfoView];
}


-(void) resizeAllViewsExceptCurrent {
    
    if (   currentViewName
        && [currentViewName isNotEqualTo: NSToolbarFlexibleSpaceItemIdentifier]
        && [currentViewName isNotEqualTo: @"lockIcon"]) {
        NSView * currentView = [toolbarViews objectForKey: currentViewName];
        if (  currentView  ) {
            NSSize newSize = [currentView frame].size;
            if (  newSize.width != 0.0 ) {
                
                NSString * name;
                NSEnumerator * e = [toolbarViews keyEnumerator];
                while (  (name = [e nextObject])  ) {
                    if (   [name isNotEqualTo: currentViewName]
                        && [name isNotEqualTo: NSToolbarFlexibleSpaceItemIdentifier]
                        && [name isNotEqualTo: @"lockIcon"]  ) {
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
}


- (IBAction) windowWillAppear
{
    if (  firstTimeShowingWindow  ) {
        // Set the window's position and size from the preferences (saved when window is closed), or center the window
        // Use the preferences only if the preference's version matches the TB version (since window size could be different in different versions of TB)
        NSString * tbVersion = [[gMC tunnelblickInfoDictionary] objectForKey: @"CFBundleVersion"];
        if (  [tbVersion isEqualToString: [gTbDefaults stringForKey:@"detailsWindowFrameVersion"]]    ) {
            NSString * mainFrameString  = [gTbDefaults stringForKey: @"detailsWindowFrame"];
            NSString * leftFrameString  = [gTbDefaults stringForKey: @"detailsWindowLeftFrame"];
			NSString * configurationsTabIdentifier         = [gTbDefaults stringForKey: @"detailsWindowConfigurationsTabIdentifier"];
            if (   mainFrameString != nil  ) {
                
                // Set the new frame for the window
                [[self window] setMinSize: NSMakeSize(760.0, 452.0)]; // WINDOW size, not view size
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
                // Set a very narrow frame, then set the frame to be the correct width
                // This is necessary because otherwise macOS truncates a long name and follows it with "..." as if the name column was narrow,
                // even if the name column is very wide and could show the entire name. Setting the name column to be very narrow, then making
                // it the correct width tricks macOS into displaying it correctly.
                NSRect narrowLeftFrame = leftFrame;
                narrowLeftFrame.size.width = 10;
                NSView * v = [configurationsPrefsView leftSplitView];
                [v setFrame: narrowLeftFrame];
                [v setFrame: leftFrame];
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
	
    [self lockTheLockIcon];
    
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
    NSString * tbVersion = [[gMC tunnelblickInfoDictionary] objectForKey: @"CFBundleVersion"];
	unsigned int viewIx = [toolbarIdentifiers indexOfObject: currentViewName];
    BOOL saveIt = TRUE;
	unsigned int defaultViewIx = [UIHelper detailsWindowsViewIndexFromPreferencesWithCount: [toolbarIdentifiers count]];
	
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
    
    if (    (view == configurationsPrefsView)
        &&  [[configurationsPrefsView configurationsTabView] selectedTabViewItem] == [configurationsPrefsView logTabViewItem]  ) {
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
    
    if (  view == generalPrefsView  ) {
		[self setupGeneralView];
	}
    
    // Track the name of the view currently being shown, so other methods can access the view
    [self setCurrentViewName: identifier];
}

// Overrides superclass
-(void) newViewDidAppear: (NSView *) view
{
    if (   view == configurationsPrefsView  ) {
        [[self window] makeFirstResponder: nil];
        if (  [[configurationsPrefsView configurationsTabView] selectedTabViewItem] == [configurationsPrefsView logTabViewItem]  ) {
            [[self selectedConnection] startMonitoringLogFiles];
        }

    } else if (   view == generalPrefsView  ) {
        [[self window] makeFirstResponder: [generalPrefsView keyboardShortcutButton]];
    } else if (   view == appearancePrefsView  ) {
        [[self window] makeFirstResponder: [appearancePrefsView appearanceIconSetButton]];
    } else if (   view == utilitiesPrefsView  ) {
        [[self window] makeFirstResponder: [utilitiesPrefsView utilitiesHelpButton]];
    } else if (   view == infoPrefsView  ) {
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
	
    LeftNavViewController   * ovc    = [configurationsPrefsView outlineViewController];
    NSOutlineView           * ov     = [ovc outlineView];
    NSIndexSet              * idxSet = [ov selectedRowIndexes];
    return [idxSet count] == 1;
}

-(BOOL) oneOrMoreConfigurationsAreSelected {

    LeftNavViewController   * ovc    = [configurationsPrefsView outlineViewController];
    NSOutlineView           * ov     = [ovc outlineView];
    NSIndexSet              * idxSet = [ov selectedRowIndexes];
    return ([idxSet count] > 0);
}

-(void) setupConfigurationsView
{
	
	BOOL savedDoingSetupOfUI = [gMC doingSetupOfUI];
	[gMC setDoingSetupOfUI: TRUE];

    [self setSelectedSetNameserverIndexDirect:           [NSNumber numberWithInteger: NSNotFound]];   // Force a change when first set
    [self setSelectedPerConfigOpenvpnVersionIndexDirect: [NSNumber numberWithInteger: NSNotFound]];
    [self setSelectedLoggingLevelIndexDirect:            [NSNumber numberWithInteger: NSNotFound]];
    selectedWhenToConnectIndex     = NSNotFound;

    [leftNavDisplayNames                  release];
    leftNavDisplayNames                 = nil;
    [settingsSheetWindowController        release];
    settingsSheetWindowController       = nil;

    [self setPreviouslySelectedNameOnLeftNavList: [gTbDefaults stringForKey: @"leftNavSelectedDisplayName"]];

	[self setupLeftNavigationToDisplayName: previouslySelectedNameOnLeftNavList];
	
    // Right split view
    
    [[configurationsPrefsView configurationsTabView] setDelegate: self];
    
    // Right split view - Settings tab

    VPNConnection * connection = [self selectedConnection];

    if (  connection  ) {
    
        [self indicateNotWaitingForLogDisplay: connection];

        // Set up a timer to update connection times
        [gMC startOrStopUiUpdater];
    }
    
    [self validateDetailsWindowControlsForConnection: connection];
	
	[gMC setDoingSetupOfUI: savedDoingSetupOfUI];
}


-(BOOL) useDnsScriptCanPerformFunction: (NSArray *) isSmart {
    NSString * name = [[self selectedConnection] displayName];
	if (  ! name  ) {
		return NO;
	}
	
    NSString * key = [name stringByAppendingString: @"useDNS"];
    unsigned ix = [gTbDefaults unsignedIntForKey: key
                                         default: 1
                                             min: 0
                                             max: MAX_SET_DNS_WINS_INDEX];
    NSNumber * ixNumber = [NSNumber numberWithUnsignedInt: ix];
    return [isSmart containsObject: ixNumber];
}

-(void) setupSetNameserver: (VPNConnection *) connection
{
    
    if (  ! connection  ) {
        return;
    }
    
    if (  ! configurationsPrefsView  ) {
        return;
    }
	
    if (  [self selectedConnection] != connection  ) {
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
        [gMC terminateBecause: terminatingBecauseOfError];
    }
    
    NSInteger ix = [gTbDefaults unsignedIntForKey: key
                                default: 1
                                    min: 0
                                    max: MAX_SET_DNS_WINS_INDEX];

    // If the OpenVPN configuration includes dns-script or dns-updown force, set Set DNS/WINS to "Set nameserver (OpenVPN)" unless it is set to "Do not set nameserver"
    ConfigurationParser * parser = [ConfigurationParser parsedConfigurationForConnection: connection];
    if (   parser.containsDnsUpdownForce
        || parser.containsDnsScript  ) {
        if (   (ix != USEDNS_DO_NOT_SET_NAMESERVER)
            && (ix != USEDNS_SET_NAMESERVER_OPENVPN)  ) {
            ix = USEDNS_SET_NAMESERVER_OPENVPN;
            NSLog(@"Set DNS/WINS to 'Set nameserver (OpenVPN)' because dns-updown force appears in the OpenVPN configuration file");
        }
    }

    [[configurationsPrefsView setNameserverPopUpButton] selectItemAtIndex: ix];
    [self setSelectedSetNameserverIndexDirect: [NSNumber numberWithInteger: ix]];
    [[configurationsPrefsView setNameserverPopUpButton] setEnabled: [gTbDefaults canChangeValueForKey: key]];
    [settingsSheetWindowController setupSettingsFromPreferences];
}

-(void) setupLoggingLevel: (VPNConnection *) connection
{
    
    if (  ! connection  ) {
        return;
    }
    
    if (  ! configurationsPrefsView  ) {
        return;
    }
	
    NSString * key = [[connection displayName] stringByAppendingString: @"-loggingLevel"];
    NSInteger ix = [gTbDefaults unsignedIntForKey: key
                                          default: TUNNELBLICK_DEFAULT_LOGGING_LEVEL
                                              min: MIN_OPENVPN_LOGGING_LEVEL
                                              max: MAX_TUNNELBLICK_LOGGING_LEVEL];
    if (  ix == TUNNELBLICK_NO_LOGGING_LEVEL  ) {
        ix = 0;
    } else if (  ix == TUNNELBLICK_CONFIG_LOGGING_LEVEL  ) {
        ix = 1;
    } else {
        ix = ix + 2;
    }
    
    [[configurationsPrefsView loggingLevelPopUpButton] selectItemAtIndex: ix];
    [[configurationsPrefsView loggingLevelPopUpButton] setEnabled: [gTbDefaults canChangeValueForKey: key]];
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

-(void) setupAnUponDisconnectPopUpButton: (id)              button // Can be NSPopUpButton or TBPopUpButton
							  connection: (VPNConnection *) connection
							  unexpected: (BOOL)            unexpected
{
	
// Two boolean preferences are used to create three settings:
	//
	//
	// ! reset & ! disable => Do nothing
	//   reset & ! disable => Reset
	// ! reset &   disable => Disable on disconnect
	//   reset &   disable => (should not happen; if it does, the reset preference will be removed)
	
	if (  ! connection  ) {
		return;
	}
	
	if (  ! configurationsPrefsView  ) {
		return;
	}
	
	NSString * displayName = [connection displayName];
	NSString * resetKey    = (  unexpected
							  ? [displayName stringByAppendingString: @"-resetPrimaryInterfaceAfterUnexpectedDisconnect"]
							  : [displayName stringByAppendingString: @"-resetPrimaryInterfaceAfterDisconnect"]);
	NSString * disableKey = (  unexpected
							 ? [displayName stringByAppendingString: @"-disableNetworkAccessAfterUnexpectedDisconnect"]
							 : [displayName stringByAppendingString: @"-disableNetworkAccessAfterDisconnect"]);
	NSInteger reset   = ( [gTbDefaults boolForKey: resetKey]   ? 1 : 0);
	NSInteger disable = ( [gTbDefaults boolForKey: disableKey] ? 1 : 0);

	if (  ( reset + (disable * 2) ) > 2  ) {
		reset = 0;
		[gTbDefaults setBool: FALSE forKey: resetKey];
	}
	
	NSInteger ix = reset + (disable * 2);
	[button selectItemAtIndex: ix];
	[button setEnabled: (   [gTbDefaults canChangeValueForKey: resetKey]
						 && [gTbDefaults canChangeValueForKey: disableKey])];
}

-(void) setupUponUnexpectedDisconnectPopUpButton: (VPNConnection *) connection
{
	[self setupAnUponDisconnectPopUpButton: [configurationsPrefsView uponUnexpectedDisconnectPopUpButton] connection: connection unexpected: YES];
}

-(void) setupUponDisconnectPopUpButton: (VPNConnection *) connection
{
	[self setupAnUponDisconnectPopUpButton: [configurationsPrefsView uponDisconnectPopUpButton] connection: connection unexpected: NO];
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

-(void) setupDisableIpv6OnTun: (VPNConnection *) connection
{
    (void) connection;
    
	NSString * type = [connection tapOrTun];
    if (   ( ! [type isEqualToString: @"tap"] )
        && [self useDnsScriptCanPerformFunction: USEDNS_SCRIPTS_THAT_CAN_DISABLE_IPV6_ON_TUN]  ) {
        [self setupPerConfigurationCheckbox: [configurationsPrefsView disableIpv6OnTunCheckbox]
                                        key: @"-doNotDisableIpv6onTun"
                                   inverted: YES
                                  defaultTo: NO];
		
	} else {
		[[configurationsPrefsView disableIpv6OnTunCheckbox] setState:   NSOffState];
		[[configurationsPrefsView disableIpv6OnTunCheckbox] setEnabled: NO];
	}
}

-(void) setupDisableSecondaryNetworkServices: (VPNConnection *) connection
{
    (void) connection;

    NSString * type = [connection tapOrTun];
    if (   ( ! [type isEqualToString: @"tap"] )
        && [self useDnsScriptCanPerformFunction: USEDNS_SCRIPTS_THAT_CAN_DISABLE_SECONDARY_NETWORK_SERVICES]  ) {
        [self setupPerConfigurationCheckbox: [configurationsPrefsView disableSecondaryNetworkServicesCheckbox]
                                        key: @"-disableSecondaryNetworkServices"
                                   inverted: NO
                                  defaultTo: NO];

    } else {
        [[configurationsPrefsView disableSecondaryNetworkServicesCheckbox] setState:   NSOffState];
        [[configurationsPrefsView disableSecondaryNetworkServicesCheckbox] setEnabled: NO];
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
    
    NSString * key = [[connection displayName] stringByAppendingString: @"-openvpnVersion"];
    NSString * prefVersion = [gTbDefaults stringForKey: key];
    NSUInteger listIx;                              // Default to the first entry -- "Default (x.y.z)"

	NSArray  * versionNames = gTbInfo.allOpenvpnOpenssslVersions;
	NSUInteger versionIx = [connection getOpenVPNVersionIxToUseConnecting: NO];
    if (  [prefVersion length] == 0  ) {
		if (  versionIx == [connection defaultVersionIxFromVersionNames: versionNames]  ) {
			listIx = 0;
		} else {
			listIx = versionIx + 1; // + 1 to skip over the 1st entry (default)
		}
	} else {
		if (  versionIx == NSNotFound  ) {
			listIx = 0; // Don't have a version of OpenVPN that will work with this configuration, so display it as using the default version of OpenVPN
		} else if (  [prefVersion isEqualToString: @"-"]  ) {
			// Use latest. If we are actually using it, show we are using latest (last entry), otherwise show what we are using
			if (  versionIx == [versionNames count] - 1  ) {
				listIx = versionIx + 2; // + 2 to skip over the 1st entry (default) and the specific entry, to get to "Latest (version)"
			} else {
				listIx = versionIx + 1; // + 1 to skip over the 1st entry (default)
			}
		} else {
			// Using a specific version, but show what we are actually using instead
			listIx = versionIx + 1; // + 1 to skip over the 1st entry (default)
		}
	}
	
    [self setSelectedPerConfigOpenvpnVersionIndex: [NSNumber numberWithInteger: listIx]];
    
    [[configurationsPrefsView perConfigOpenvpnVersionButton] setEnabled: [gTbDefaults canChangeValueForKey: key]];
}


-(NSArray *) leftNavDisplayNames {

    // Returns a sorted array of the names that appear in the left navigation list. The array consists of
    // the displayName for each configuration that is visible to the user, plus the names of folders that
    // do not contain configurations but are in the configuration folders being displayed (if only shared
    // or only private configurations are being displayed).
    //
    //  * Configurations are indicated by a name that does not end in "/"
    //  * Empty folders are indicated by a name that ends in "/".
    //
    // This is done by creating an array with displayNames and then adding the names of empty folders.
    //
    // Empty folders in Shared, the user's private folder and the secure copy are included.
    //
    // NOTE: This list has an entry for each configuation and each empty folder.

    if (  leftNavDisplayNames  ) {
        return [NSArray arrayWithArray: leftNavDisplayNames];
    }

    // displayName of each the configurations that may be visible to the user
    NSArray * displayNames = [[gMC myConfigDictionary] allKeys];

    // This will be our result, and will include the empty folders
    NSMutableArray * allNames = [displayNames mutableCopy];

    [self addEmptyFoldersFrom: gPrivatePath to: allNames];
    [self addEmptyFoldersFrom: L_AS_T_SHARED to: allNames];
    [self addEmptyFoldersFrom: [L_AS_T_USERS stringByAppendingPathComponent: NSUserName()] to: allNames];

    NSArray * result = [allNames sortedArrayUsingSelector: @selector(caseInsensitiveNumericCompare:)];

    [allNames release];

    leftNavDisplayNames = [result retain];

    return result;
}

-(void) addEmptyFoldersFrom: (NSString *) folder to: (NSMutableArray *) list {

    TBLog(@"DB-PO", @"Adding empty folders from %@", folder);
    NSDirectoryEnumerator * dirE = [gFileMgr enumeratorAtPath: folder];
    NSString * file;
    while ( (file = [dirE nextObject])  ) {
        if (   [file hasSuffix: @".tblk"]
            || [[file lastPathComponent] isEqualToString: @"IconSets"]  ) {
            [dirE skipDescendants];
        } else {
            NSString * fullPath = [folder stringByAppendingPathComponent: file];
            if (  [self isDirAndHasNoTblksInItselfOrSubdirsAndHasNoSubdirs: fullPath]  ) {
                NSString * dirnameSlash = [file stringByAppendingString: @"/"];
                if (  ! [list containsObject: dirnameSlash]  ) {
                    [list addObject: dirnameSlash];
                    TBLog(@"DB-PO", @"     added empty folder '%@'", file);
                }
            }
        }
    }
}

-(BOOL) isDirAndHasNoTblksInItselfOrSubdirsAndHasNoSubdirs: (NSString *) path {

    BOOL isDir;
    if (   [gFileMgr fileExistsAtPath: path isDirectory: &isDir]
        && isDir  ) {
        NSDirectoryEnumerator * dirE = [gFileMgr enumeratorAtPath: path];
        NSString * file;
        while ( (file = [dirE nextObject])  ) {
            [dirE skipDescendants];
            if (  [file hasSuffix: @".tblk"]  ) {
                return FALSE;
            }
            NSString * fullPath = [path stringByAppendingPathComponent: file];
            if (   [gFileMgr fileExistsAtPath: fullPath isDirectory: &isDir]
                && isDir  ) {
                return FALSE;
            }
        }
    } else {
        return FALSE;
    }
    
    return TRUE;
}

-(void) reloadDataFor: (NSOutlineView *) oView {
    
    if (  [NSThread isMainThread]  ) {
        [oView reloadData];
    } else {
        [self performSelectorOnMainThread: @selector(reloadDataFor:) withObject: oView waitUntilDone: NO];
    }
}

-(void) setupLeftNavigationToDisplayName: (NSString *) displayNameToSelect
{
    NSMutableArray * currentFolders = [NSMutableArray array]; // Components of folder enclosing most-recent leftNavDisplayNames entry

    // If no display name to select and there are any connections, select the first one
	if (  ! displayNameToSelect  ) {
        NSArray * list = [[gMC myVPNConnectionDictionary] allKeys];
        if (  [list count] > 0  ) {
            displayNameToSelect = [list objectAtIndex: 0];
        }
    }

    // Clear leftNavDisplayNames and get a fresh copy
    [leftNavDisplayNames release];
    leftNavDisplayNames = nil;
    NSArray * leftNavNames = [self leftNavDisplayNames];

    // Clear leftNavList and re-create it from leftNavNames (which may include empty folders)
	int currentLeftNavIndex = 0;
	
	NSEnumerator* leftNavEnum = [leftNavNames objectEnumerator];
    NSString * leftNavName;
    while (  (leftNavName = [leftNavEnum nextObject])  ) {

		NSArray * currentConfig = [leftNavName componentsSeparatedByString: @"/"];
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
			NSString * folderName = [currentConfig objectAtIndex: i];
            if (  [folderName length] > 0  ) {
                [currentFolders addObject: folderName];
                ++currentLeftNavIndex;
            }
		}
		
		// Add a "configuration" line
        if (  ! [leftNavName hasSuffix: @"/"]  ) {
            ++currentLeftNavIndex;
        }
	}
	
    LeftNavViewController * oVC = [[self configurationsPrefsView] outlineViewController];
    NSOutlineView         * oView = [oVC outlineView];
    LeftNavDataSource     * oDS = [[self configurationsPrefsView] leftNavDataSrc];
    [oDS reload];
    [self reloadDataFor: oView];
    
    // Expand items that were left expanded previously and get row # we should select (that matches displayNameToSelect)
    
    NSInteger row = -1;	// Track row # of name we are to display
    
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
            row = r;
        }
    }

    // If no row to select, get it from preferences.
    // This happens when a folder is renamed; the preferences are updated but our 'displayNameToSelect' variable is not.
    if (  row == -1  ) {
        NSString * name = [gTbDefaults stringForKey: @"leftNavSelectedDisplayName"];
        if (  name  ) {
            row = [self rowForName: name];
            if (  row == -1  ) {
                [self performSelector: @selector(selectLeftNavName:) withObject: name  afterDelay: 0.2];
                return;
            }
        }
    }

    if (  row == -1  ) {
        NSString * name = [gTbDefaults stringForKey: @"lastConnectedDisplayName"];
        if (  name  ) {
            row = [self rowForName: name];
        }
    }

    if (   (row == -1)
        && (currentLeftNavIndex > 0)  ) {
        row = 0;
    }

    if (  row == -1  ) {
        [self validateDetailsWindowControlsForConnection: nil];
        [settingsSheetWindowController setConfigurationName: nil];
    } else {
        [oView selectRowIndexes: [NSIndexSet indexSetWithIndex: row] byExtendingSelection: NO];
        [[[configurationsPrefsView outlineViewController] outlineView] scrollRowToVisible: row];
        [self setPreviouslySelectedNameOnLeftNavList: nil]; // Force change
        [self setSelectedLeftNavListIndex: row];
    }
}

-(void) selectLeftNavName: (NSString *) name {

    NSInteger row = [self rowForName: name];
    if (  row == -1) {
        NSString * lastConnectedName = [gTbDefaults stringForKey: @"lastConnectedDisplayName"];
        if (  name  ) {
            row = [self rowForName: lastConnectedName];
        }
    }

    if (  row != -1  ) {
        LeftNavViewController * oVC = [[self configurationsPrefsView] outlineViewController];
        NSOutlineView * oView = [oVC outlineView];
        [oView selectRowIndexes: [NSIndexSet indexSetWithIndex: row] byExtendingSelection: NO];
        [[[configurationsPrefsView outlineViewController] outlineView] scrollRowToVisible: row];
        [self setPreviouslySelectedNameOnLeftNavList: nil]; // Force change
        [self setSelectedLeftNavListIndex: row];
    }
}

// Call this when a configuration was added or deleted
-(void) update
{
    [self setupLeftNavigationToDisplayName: previouslySelectedNameOnLeftNavList];
    
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
		[self validateDetailsWindowControlsForConnection: connection];
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
    [[configurationsPrefsView diagnosticInfoToClipboardButton] setEnabled: (! [gTbDefaults boolForKey: @"disableCopyLogToClipboardButton"])];
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

-(void) indicateWaitingForUtilitiesExportTunnelblickSetup
{
	[[utilitiesPrefsView utilitiesExportTunnelblickSetupProgressIndicator] startAnimation: self];
	[[utilitiesPrefsView utilitiesExportTunnelblickSetupProgressIndicator] setHidden: NO];
	[[utilitiesPrefsView utilitiesExportTunnelblickSetupButton] setEnabled: NO];
}


-(void) indicateNotWaitingForUtilitiesExportTunnelblickSetup
{
	[[utilitiesPrefsView utilitiesExportTunnelblickSetupProgressIndicator] stopAnimation: self];
	[[utilitiesPrefsView utilitiesExportTunnelblickSetupProgressIndicator] setHidden: YES];
	[[utilitiesPrefsView utilitiesExportTunnelblickSetupButton] setEnabled: YES];
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
-(void) setupPerConfigurationCheckbox: (TBButton *) checkbox
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


-(void) validateDetailsWindowControlsForConnection: (VPNConnection *) connection {

	[self updateConnectionStatusAndTime];
	
    if (   connection
        && ([TBOperationQueue shouldUIBeEnabledForDisplayName: [connection displayName]] )  ) {
        
        [self validateConnectAndDisconnectButtonsForConnection: connection];
        
		// diagnosticInfoToClipboardProgressIndicator is controlled by indicateWaitingForDiagnosticInfoToClipboard and indicateNotWaitingForDiagnosticInfoToClipboard
		[[configurationsPrefsView diagnosticInfoToClipboardButton] setEnabled: [[configurationsPrefsView diagnosticInfoToClipboardProgressIndicator] isHidden]];
		
        // Left split view
        
		[[configurationsPrefsView addConfigurationButton]    setEnabled: TRUE];
		
        [[configurationsPrefsView removeConfigurationButton] setEnabled: [self oneOrMoreConfigurationsAreSelected]];
		
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
        
        [connection validateWhenToConnect];

		[self setupPerConfigOpenvpnVersion:				connection];
		
		[self setupSetNameserver:						connection];
		[self setupLoggingLevel:						connection];
        
		[self setupNetworkMonitoring:					connection];
		[self setupRouteAllTraffic:						connection];
		[self setupUponDisconnectPopUpButton:			connection];
		[self setupUponUnexpectedDisconnectPopUpButton:	connection];
        [self setupDisableIpv6OnTun:					connection];
        [self setupCheckIPAddress:						connection];
        [self setupDisableSecondaryNetworkServices:     connection];

        [[configurationsPrefsView advancedButton] setEnabled: ! [gTbDefaults boolForKey: @"disableAdvancedButton"]];
        [settingsSheetWindowController            setupSettingsFromPreferences];
        
    } else {
        
        // There is not a connection selected or it should have its UI controls disabled. Don't let the user do anything except add a configuration or disconnect one.

        BOOL enableRemoveButton = (   [self oneOrMoreConfigurationsAreSelected]
                                   && [TBOperationQueue shouldUIBeEnabledForDisplayName: nil]);

		[[configurationsPrefsView addConfigurationButton]           setEnabled: YES];
        [[configurationsPrefsView removeConfigurationButton]        setEnabled: enableRemoveButton];
        [[configurationsPrefsView workOnConfigurationPopUpButton]   setEnabled: NO];
        
        // The "Log" and "Settings" items can't be selected because tabView:shouldSelectTabViewItem: will return NO if there is no selected connection
        
        [[configurationsPrefsView logDisplayProgressIndicator]      setHidden: YES];

        [[configurationsPrefsView diagnosticInfoToClipboardButton]  setEnabled: YES];
		// diagnosticInfoToClipboardProgressIndicator is controlled by indicateWaitingForDiagnosticInfoToClipboard and indicateNotWaitingForDiagnosticInfoToClipboard
        
        [[configurationsPrefsView connectButton]                    setEnabled: NO];
        [[configurationsPrefsView disconnectButton]                 setEnabled: ( connection ? YES : NO)];
        
        [[configurationsPrefsView whenToConnectPopUpButton]         setEnabled: NO];
        
        [[configurationsPrefsView setNameserverPopUpButton]         setEnabled: NO];
        
        [[configurationsPrefsView loggingLevelPopUpButton]          setEnabled: NO];
        
		[[configurationsPrefsView uponDisconnectPopUpButton]        setEnabled: NO];
		[[configurationsPrefsView uponUnexpectedDisconnectPopUpButton]          setEnabled: NO];

        [[configurationsPrefsView monitorNetworkForChangesCheckbox]             setEnabled: NO];
        [[configurationsPrefsView routeAllTrafficThroughVpnCheckbox]            setEnabled: NO];
        [[configurationsPrefsView checkIPAddressAfterConnectOnAdvancedCheckbox] setEnabled: NO];
        [[configurationsPrefsView disableIpv6OnTunCheckbox]                     setEnabled: NO];
        [[configurationsPrefsView disableSecondaryNetworkServicesCheckbox]     setEnabled: NO];

        [[configurationsPrefsView perConfigOpenvpnVersionButton]    setEnabled: NO];
        
        [[configurationsPrefsView advancedButton]                   setEnabled: NO];
        [settingsSheetWindowController                              setupSettingsFromPreferences];
    }
}

-(NSArray *) displayNamesOfSelection {
    
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
            if (  [name length] != 0  ) {
                [displayNames addObject: name];
            }
        }];
#endif
    }
    
    return [NSArray arrayWithArray: displayNames];
}

-(BOOL) isAnySelectedConfigurationPrivate {
	
	NSArray * displayNames = [self displayNamesOfSelection];
	NSString * displayName;
	NSEnumerator * e = [displayNames objectEnumerator];
	while (  (displayName = [e nextObject])  ) {
		NSString * path = [[gMC myConfigDictionary] objectForKey: displayName];
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
		NSString * path = [[gMC myConfigDictionary] objectForKey: displayName];
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
		NSString * path = [[gMC myConfigDictionary] objectForKey: displayName];
		if (  ! path  ) {
			NSLog(@"isAnySelectedConfigurationShared: Internal error: No configuration for '%@'", displayName);
		}
		if (  ! [path hasPrefix: @"/Application/Tunnelblick.app/Contents/Resources/Deploy/"]  ) {
			return TRUE;
		}
	}
	
	return FALSE;
}

-(BOOL) isAnySelectedConfigurationDeployed {

    NSArray * displayNames = [self displayNamesOfSelection];
    NSString * displayName;
    NSEnumerator * e = [displayNames objectEnumerator];
    while (  (displayName = [e nextObject])  ) {
        NSString * path = [[gMC myConfigDictionary] objectForKey: displayName];
        if (  ! path  ) {
            NSLog(@"isAnySelectedConfigurationShared: Internal error: No configuration for '%@'", displayName);
        }
        if (  [path hasPrefix: @"/Application/Tunnelblick.app/Contents/Resources/Deploy/"]  ) {
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
    SEL selector = [anItem action];

	if (  selector == @selector(addConfigurationButtonWasClicked:)  ) {
		return ! [gTbDefaults boolForKey: @"disableAddConfigurationButton"];
	}
	
	if (  selector == @selector(removeConfigurationButtonWasClicked:)  ) {
		return (   ( ! [gTbDefaults boolForKey: @"disableRemoveConfigurationButton"] )
				&& [self isAnySelectedConfigurationNotDeployed]);
	}
	
	if (  selector == @selector(renameConfigurationMenuItemWasClicked:)  ) {
		return (   ( ! [gTbDefaults boolForKey: @"disableRenameConfigurationMenuItem"] )
				&& ( [self isAnySelectedConfigurationNotDeployed])
				&& [self oneConfigurationIsSelected] );
	}
	
	if (  selector == @selector(duplicateConfigurationMenuItemWasClicked:)  ) {
		return (   (! [gTbDefaults boolForKey: @"disableDuplicateConfigurationMenuItem"] )
				&& [self isAnySelectedConfigurationNotDeployed]
				&& [self oneConfigurationIsSelected] );
	}
	
	if (  selector == @selector(makePrivateMenuItemWasClicked:)  ) {
		return [self isAnySelectedConfigurationShared];
	}
	
	if (  selector == @selector(makeSharedMenuItemWasClicked:)  ) {
		return [self isAnySelectedConfigurationPrivate];
		
	}
	if (  selector == @selector(revertToShadowMenuItemWasClicked:)  ) {
		return (   ( ! [gTbDefaults boolForKey: @"disableRevertToShadowMenuItem"] )
				&& (   [[connection configPath] hasPrefix: [gPrivatePath stringByAppendingString: @"/"]])
				&& ( ! [connection shadowCopyIsIdentical] )  );
	}
	
    if (  selector == @selector(c_o_p_yConfigurationsIntoNewFolderMenuItemWasClicked:)  ) {
        NSString * title = (  [self oneConfigurationIsSelected]
                            ? NSLocalizedString(@"Copy Configuration into a New Folder...",  @"Menu item")
                            : NSLocalizedString(@"Copy Configurations into a New Folder...", @"Menu item"));
        [[configurationsPrefsView c_o_p_yConfigurationsIntoNewFolderMenuItem] setTitle: title];
        return (  ! [gTbDefaults boolForKey: @"disableCopyConfigurationsIntoNewFolderMenuItem"]  );
    }

    if (  selector == @selector(moveConfigurationsIntoNewFolderMenuItemWasClicked:)  ) {
        NSString * title = (  [self oneConfigurationIsSelected]
                            ? NSLocalizedString(@"Move Configuration into a New Folder...",  @"Menu item")
                            : NSLocalizedString(@"Move Configurations into a New Folder...", @"Menu item"));
        [[configurationsPrefsView moveConfigurationsIntoNewFolderMenuItem] setTitle: title];
        return (  ! [gTbDefaults boolForKey: @"disableMoveConfigurationsIntoNewFolderMenuItem"] );
    }

	if (  selector == @selector(showOnTbMenuMenuItemWasClicked:)  ) {
		return [self isAnySelectedConfigurationDoNotShowOnTbMenu];
	}
	
	if (  selector == @selector(doNotShowOnTbMenuMenuItemWasClicked:)  ) {
		return [self isAnySelectedConfigurationShowOnTbMenu];
	}
	
	if (  selector == @selector(editOpenVPNConfigurationFileMenuItemWasClicked:)  ) {
		return (   ( ! [gTbDefaults boolForKey: @"disableExamineOpenVpnConfigurationFileMenuItem"] )
				&& [self oneConfigurationIsSelected]);
	}
	
	if (  selector == @selector(showOpenvpnLogMenuItemWasClicked:)  ) {
		NSString * path = [[self selectedConnection] openvpnLogPath];
		return (   ( ! [gTbDefaults boolForKey: @"disableShowOpenVpnLogInFinderMenuItem"] )
				&& [[connection configPath] hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]
				&& [self oneConfigurationIsSelected]
				&& path
				&&[gFileMgr fileExistsAtPath: [[self selectedConnection] openvpnLogPath]]);
	}
	
	if (  selector == @selector(removeCredentialsMenuItemWasClicked:)  ) {
		return (   ( ! [gTbDefaults boolForKey: @"disableDeleteConfigurationCredentialsInKeychainMenuItem"] )
				&& [self isAnySelectedConfigurationCredentialed] );
	}
	
	if (  selector == @selector(whenToConnectManuallyMenuItemWasClicked:)  ) {
		return TRUE;
	}
	
	if (  selector == @selector(whenToConnectTunnelBlickLaunchMenuItemWasClicked:)  ) {
		return TRUE;
	}
	
	if (  selector == @selector(whenToConnectOnComputerStartMenuItemWasClicked:)  ) {
		return [[self selectedConnection] mayConnectWhenComputerStarts];
	}
	
	if (   ( selector == @selector(uponDisconnectDoNothingMenuItemWasClicked:) )
		|| ( selector == @selector(uponDisconnectResetPrimaryInterfaceMenuItemWasClicked:) )
		|| ( selector == @selector(uponDisconnectDisableNetworkAccessMenuItemWasClicked:) )
		|| ( selector == @selector(uponUnexpectedDisconnectDoNothingMenuItemWasClicked:) )
		|| ( selector == @selector(uponUnexpectedDisconnectResetPrimaryInterfaceMenuItemWasClicked:) )
		|| ( selector == @selector(uponUnexpectedDisconnectDisableNetworkAccessMenuItemWasClicked:) )
	   ) {
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
-(NSString *) windowTitle: (NSString *) currentItemLabel
{
	(void) currentItemLabel;
   
    NSString * windowLabel = localizeNonLiteral(currentViewName, @"Window title");
    return windowLabel;
}


-(void) hookedUpOrStartedConnection: (VPNConnection *) theConnection
{
    if (   theConnection
        && ( theConnection == [self selectedConnection] )  ) {
        if (   [currentViewName isEqualToString: NSLocalizedString(@"Configurations", @"Window title")]
            && [[configurationsPrefsView configurationsTabView] selectedTabViewItem] == [configurationsPrefsView logTabViewItem]  ) {
            [theConnection startMonitoringLogFiles];
        }
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
	
	[self updateConnectionStatusAndTime];
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
	// Some up/down scripts do not implement network monitoring, so we disable the checkbox if one of them is selected in "Set DNS/WINS"
    NSArray * content = [[configurationsPrefsView setNameserverArrayController] content];
    NSUInteger ix = [selectedSetNameserverIndex unsignedIntegerValue];
    if (   ([content count] <= MAX_SET_DNS_WINS_INDEX)
        || (ix == 0)		// Do not set nameserver
		|| (ix == 2)		// Set nameserver (3.1)		-- client.1.up.tunnelblick.sh and client.1.down.tunnelblick.sh
        || (ix == 3)  ) {	// Set nameserver (3.0b10)	-- client.2.up.tunnelblick.sh and client.2.down.tunnelblick.sh
        return TRUE;
    } else {
        return FALSE;
    }
}

- (VPNConnection*) selectedConnection {

    // Returns the connection associated with the currently selected connection or nil on error.

    VPNConnection * connection = [gMC connectionForDisplayName: previouslySelectedNameOnLeftNavList];
    return connection;
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
	(void) sender;
	
    VPNConnection * connection = [self selectedConnection];
    if (  connection  ) {
        [connection addToLog: @"Disconnecting; VPN Details… window disconnect button pressed"];
		NSString * oldRequestedState = [connection requestedState];
        [connection performSelectorOnMainThread: @selector(startDisconnectingUserKnows:) withObject: @YES waitUntilDone: NO];
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

-(void) cacheSanitizedConfigFileContentsForDisplayNames: (NSArray *) displayNames {

    NSEnumerator * enu = [displayNames objectEnumerator];
    NSString * displayName;
    while (  (displayName = [enu nextObject])  ) {
        VPNConnection * connection = [[gMC myVPNConnectionDictionary] objectForKey: displayName];
        [connection sanitizedConfigurationFileContents];
    }
}

-(IBAction) makePrivateMenuItemWasClicked: (id) sender
{
    (void) sender;
    
    NSArray * displayNames = [self displayNamesOfSelection];
    
    if (  [displayNames count] != 0  ) {
        [self cacheSanitizedConfigFileContentsForDisplayNames: displayNames];
		[ConfigurationManager makeConfigurationsPrivateInNewThreadWithDisplayNames: displayNames];
    }
}

-(IBAction) makeSharedMenuItemWasClicked: (id) sender
{
    (void) sender;
    
    NSArray * displayNames = [self displayNamesOfSelection];
    
    if (  [displayNames count] != 0  ) {
        [self cacheSanitizedConfigFileContentsForDisplayNames: displayNames];
		[ConfigurationManager makeConfigurationsSharedInNewThreadWithDisplayNames: displayNames];
    }
}

-(IBAction) removeConfigurationButtonWasClicked: (id) sender
{
    (void) sender;
    
    NSArray * displayNames = [self displayNamesOfSelection];
    
    if (  [displayNames count] != 0  ) {
		[ConfigurationManager removeConfigurationsOrFoldersInNewThreadWithDisplayNames: displayNames];
    }

}

-(IBAction) renameConfigurationMenuItemWasClicked: (id) sender
{
	(void) sender;

    NSOutlineView * outlineView = [ (NSScrollView *)[[configurationsPrefsView outlineViewController] view] documentView];
    [outlineView editColumn: 0
                        row: [outlineView selectedRow]
                  withEvent: nil
                     select: YES];
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
    NSString * targetPath = pathWithNumberSuffixIfItemExistsAtPath(sourcePath, YES);
    if (  targetPath  ) {
        [ConfigurationManager duplicateConfigurationInNewThreadPath: sourcePath toPath: targetPath];
    }
}

-(IBAction) revertToShadowMenuItemWasClicked: (id) sender
{
	(void) sender;
	
	NSArray * displayNames = [self displayNamesOfSelection];
    
    if (  [displayNames count] != 0  ) {
		[ConfigurationManager revertToShadowInNewThreadWithDisplayNames: displayNames];
    }
}

-(IBAction) c_o_p_yConfigurationsIntoNewFolderMenuItemWasClicked: (id) sender
{
    (void) sender;

    VPNConnection * connection = [self selectedConnection];
    if (  ! connection  ) {
        NSLog(@"c_o_p_yConfigurationsIntoNewFolderMenuItemWasClicked but no configuration has been selected");
        return;
    }

    NSArray * displayNames = [self displayNamesOfSelection];

    [ConfigurationManager copyConfigurationsIntoNewFolderInNewThread: displayNames];
}

-(IBAction) moveConfigurationsIntoNewFolderMenuItemWasClicked: (id) sender
{
    (void) sender;

    VPNConnection * connection = [self selectedConnection];
    if (  ! connection  ) {
        NSLog(@"moveConfigurationsIntoNewFolderMenuItemWasClicked but no configuration has been selected");
        return;
    }

    NSArray * displayNames = [self displayNamesOfSelection];

    [ConfigurationManager moveConfigurationsIntoNewFolderInNewThread: displayNames];
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
	
	[gMC recreateMainMenuClearCache: YES];
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
	
	[gMC recreateMainMenuClearCache: YES];
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

	NSString * logContents = [[[[[gMC logScreen] configurationsPrefsView] logView] textStorage] string];
	[ConfigurationManager putDiagnosticInfoOnClipboardInNewThreadForDisplayName: [[self selectedConnection] displayName] log: logContents];
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
                              NSLocalizedString(@"A configuration which requires a passphrase (private key) or a username and password cannot connect when the computer starts.", @"Window text"));
        } else {
            [self setSelectedWhenToConnectIndex: 2];
        }
    } else {
        NSLog(@"whenToConnectOnComputerStartMenuItemWasClicked but no configuration selected");
    }
}

-(void) setupPerConfigOpenvpnVersionAfterDelay {
	
	VPNConnection * connection = [self selectedConnection];
	[self performSelector: @selector(setupPerConfigOpenvpnVersion:) withObject: connection afterDelay: 0.1];
}

-(void) setSelectedPerConfigOpenvpnVersionIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedPerConfigOpenvpnVersionIndex]]  ) {
        NSArrayController * ac = [configurationsPrefsView perConfigOpenvpnVersionArrayController];
        NSArray * list = [ac content];
        if (  [newValue unsignedIntegerValue] < [list count]  ) {
            
            [self setSelectedPerConfigOpenvpnVersionIndexDirect: newValue];
            
            // Set the preference if this isn't just the initialization
            if (  ! [gMC doingSetupOfUI]  ) {
                NSString * newPreferenceValue = [[list objectAtIndex: [newValue unsignedIntegerValue]] objectForKey: @"value"];
				NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
									   newPreferenceValue, @"NewValue",
									   @"-openvpnVersion", @"PreferenceName",
									   nil];
				[gMC performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
				[self performSelectorOnMainThread: @selector(setupPerConfigOpenvpnVersionAfterDelay) withObject: nil waitUntilDone: NO];
			}
        }
    }
}

-(void) uponADisconnectReset: (BOOL) reset
					 disable: (BOOL) disable
				  unexpected: (BOOL) unexpected {
	
	NSString * resetKey   = (  unexpected
							 ? @"-resetPrimaryInterfaceAfterUnexpectedDisconnect"
							 : @"-resetPrimaryInterfaceAfterDisconnect");
	NSString * disableKey = (  unexpected
							 ? @"-disableNetworkAccessAfterUnexpectedDisconnect"
							 : @"-disableNetworkAccessAfterDisconnect");
	
	[gMC setBooleanPreferenceForSelectedConnectionsWithKey: resetKey   to: reset   inverted: NO];
	[gMC setBooleanPreferenceForSelectedConnectionsWithKey: disableKey to: disable inverted: NO];

}

-(void) restoreAnUponDisconnectCheckboxState: (NSNumber *) unexpected {
	
	SEL selector = (  [unexpected boolValue]
					? @selector(setupUponUnexpectedDisconnectPopUpButton:)
					: @selector(setupUponDisconnectPopUpButton:));
	[self performSelectorOnMainThread: selector withObject: [self selectedConnection] waitUntilDone: YES];
}

-(BOOL) okToDisableNetworkAccessOnDisconnectForUnexpected: (BOOL) unexpected {
	
	// Do not do this if any of the selected configurations include the 'user' or 'group' options.
	
	// Create a list of the selected connections (if any) that have 'user' and/or 'group' options
	NSMutableString * listString = [[[NSMutableString alloc] initWithCapacity: 1000] autorelease];

	NSMutableString * cancelled = [[[NSMutableString alloc] initWithCapacity:100] autorelease]; // Empty unless operation has been cancelled by user
								   
	LeftNavViewController   * ovc    = [configurationsPrefsView outlineViewController];
	NSOutlineView           * ov     = [ovc outlineView];
	NSIndexSet              * idxSet = [ov selectedRowIndexes];
	if  (  [idxSet count] != 0  ) {
		[idxSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
			(void) stop;
			
			LeftNavItem * item = [ov itemAtRow: idx];
			NSString * displayName = [item displayName];
			if (   ([displayName length] != 0)
                && ( ! [displayName hasSuffix: @"/"] )  ) {	// Ignore folders; just process configurations

				VPNConnection * connection = [gMC connectionForDisplayName: displayName];
				if (  ! connection  ) {
					NSLog(@"Error: no connection for displayName '%@'", displayName);
					[gMC terminateBecause: terminatingBecauseOfError];
					[cancelled appendString: @"X"];
				} else {

					if (   [connection configurationIsSecureOrMatchesShadowCopy]
						|| [connection makeShadowCopyMatchConfiguration]  ) {
						if (  [connection userOrGroupOptionExistsInConfiguration]  ) {
							[listString appendFormat: @"          %@\n", displayName];
						}
					} else {
						[cancelled appendString: @"X"];
					}
				}
			}
		}];
	} else {
		NSLog(@"okToDisableNetworkAccessOnDisconnectForUnexpected: No configuration is selected");
	}

	if (  [cancelled length] != 0  ) {
		// Revert to the prior state because we canceled changing it to 'Disable network access on disconnect'
		[self performSelector: @selector(restoreAnUponDisconnectCheckboxState:) withObject: [NSNumber numberWithBool: unexpected] afterDelay: 0.2];
		return NO;
	}
	
	// If any of the selected configurations have a 'user' and/or 'group' option, complain and restore the original setting.
	if (  [listString length] != 0  ) {
		TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
						  [NSString stringWithFormat: NSLocalizedString(@"Network access cannot be disabled after disconnecting for some or all"
																		@" of the selected configurations because they include 'user'"
																		@" and/or 'group' options. Those options will cause OpenVPN"
																		@" to not be running as root during disconnection, so it will"
																		@" not be able to disable network access.\n\n"
																		@"The configurations that contain 'user' and/or 'group' are:\n\n%@\n\n", @"Window text; the %@ will be replaced by a list of configuration names."),
						   listString]);
		[self performSelector: @selector(restoreAnUponDisconnectCheckboxState:) withObject: [NSNumber numberWithBool: unexpected] afterDelay: 0.2];
		return NO;
	}
	
	return YES;
}

-(IBAction) uponDisconnectDoNothingMenuItemWasClicked: (id) sender
{
	(void) sender;
	
	[self uponADisconnectReset: NO disable: NO unexpected: NO];
}

-(IBAction) uponDisconnectResetPrimaryInterfaceMenuItemWasClicked: (id) sender
{
	(void) sender;
	
	[self uponADisconnectReset: YES disable: NO unexpected: NO];
}

-(IBAction) uponDisconnectDisableNetworkAccessMenuItemWasClicked: (id) sender
{
	(void) sender;
	
	if (  [self okToDisableNetworkAccessOnDisconnectForUnexpected: NO]  ) {
		[self uponADisconnectReset: NO disable: YES unexpected: NO];
	}
}

-(IBAction) uponUnexpectedDisconnectDoNothingMenuItemWasClicked: (id) sender
{
	(void) sender;
	
	[self uponADisconnectReset: NO disable: NO unexpected: YES];
}

-(IBAction) uponUnexpectedDisconnectResetPrimaryInterfaceMenuItemWasClicked: (id) sender
{
	(void) sender;
	
	[self uponADisconnectReset: YES disable: NO unexpected: YES];
}

-(IBAction) uponUnexpectedDisconnectDisableNetworkAccessMenuItemWasClicked: (id) sender
{
	(void) sender;
	
	if (  [self okToDisableNetworkAccessOnDisconnectForUnexpected: YES]  ) {
		[self uponADisconnectReset: NO disable: YES unexpected: YES];
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
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-notMonitoringConnection"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: YES];
    
    [settingsSheetWindowController monitorNetworkForChangesCheckboxChangedForConnection: [self selectedConnection]];
}

-(IBAction) routeAllTrafficThroughVpnCheckboxWasClicked: (NSButton *) sender {
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-routeAllTrafficThroughVpn"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: NO];
}

-(IBAction) checkIPAddressAfterConnectOnAdvancedCheckboxWasClicked: (NSButton *) sender
{
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-notOKToCheckThatIPAddressDidNotChangeAfterConnection"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: YES];

    // If turning on IP address checking, clear the number of successful IP address checks.
    NSArray * names = [self displayNamesOfSelection];
    NSString * name;
    NSEnumerator * e = [names objectEnumerator];
    while (  (name = [e nextObject])  ) {
        if (  ([sender state] == NSOnState)  ) {
            [gTbDefaults removeObjectForKey: [name stringByAppendingString: @"-consecutiveSuccessfulIPAddressChanges"]];
        }
    }
}

-(IBAction) disableIpv6OnTunCheckboxWasClicked: (NSButton *) sender
{
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-doNotDisableIpv6onTun"
                                                                                         to: ([sender state] == NSOnState)
                                                                                   inverted: YES];
}

-(IBAction) disableSecondaryNetworkServicesCheckboxWasClicked: (NSButton *) sender
{
    [gMC setBooleanPreferenceForSelectedConnectionsWithKey: @"-disableSecondaryNetworkServices"
                                                        to: ([sender state] == NSOnState)
                                                  inverted: NO];
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

-(void) rawSetWhenToConnect {
    
    VPNConnection * connection = [self selectedConnection];
    if (  ! connection  ) {
        return;
    }
    
    NSString * displayName = [connection displayName];
    
    BOOL enableWhenComputerStarts = [connection mayConnectWhenComputerStarts];
    
    NSString * autoConnectKey = [displayName stringByAppendingString: @"autoConnect"];
    NSString * ossKey         = [displayName stringByAppendingString: @"-onSystemStart"];
    BOOL       autoConnect    = [gTbDefaults boolForKey: autoConnectKey];
    
    BOOL launchdPlistWillConnectOnSystemStart = [connection launchdPlistWillConnectOnSystemStart];
    
    // Set index of 'When computer starts' drop-down according to what will actually happen
    NSUInteger ix = (  launchdPlistWillConnectOnSystemStart
                     ? 2
                     : (  autoConnect
                        ? 1
                        : 0));
    [[configurationsPrefsView whenToConnectPopUpButton] selectItemAtIndex: (int)ix];
    selectedWhenToConnectIndex = ix;
    [[configurationsPrefsView whenToConnectOnComputerStartMenuItem] setEnabled: enableWhenComputerStarts];
    
    BOOL enable = (   [gTbDefaults canChangeValueForKey: autoConnectKey]
                   && [gTbDefaults canChangeValueForKey: ossKey]
                   && [self oneConfigurationIsSelected]);
    [[configurationsPrefsView whenToConnectPopUpButton] setEnabled: enable];
}

-(void) validateWhenToConnect: (VPNConnection *) connection {
    
    // Verifies that
    //       * The autoConnect and -onSystemStart preferences
    //       * The configuration location (private/shared/deployed)
    //       * Any launchd .plist for the configuration
    // are all consistent.
    // Does this by modifying the preferences to reflect the existence of the launchd .plist if necessary
    // Then sets the index for the 'Connect when' drop-down appropriately
    //
    // Returns TRUE normally, or FALSE if there was a problem setting the preferences (because of forced preferences, presumably)
    
    if (  ! connection  ) {
        return;
    }
    
    NSString * displayName = [connection displayName];
    
    BOOL enableWhenComputerStarts = [connection mayConnectWhenComputerStarts];
    
    NSString * autoConnectKey = [displayName stringByAppendingString: @"autoConnect"];
    NSString * ossKey         = [displayName stringByAppendingString: @"-onSystemStart"];
    BOOL       autoConnect    = [gTbDefaults boolForKey: autoConnectKey];
    BOOL       onSystemStart  = [gTbDefaults boolForKey: ossKey];
    
    BOOL launchdPlistWillConnectOnSystemStart = [connection launchdPlistWillConnectOnSystemStart];
    
    //Keep track of what we need to do with the preferences
    BOOL changeToManual = FALSE;
    BOOL changeToWhenComputerStarts = FALSE;
    
    if (  autoConnect && onSystemStart  ) {
        if (  launchdPlistWillConnectOnSystemStart  ) {
            if (  ! enableWhenComputerStarts  ) {
                NSLog(@"Warning: ''%@' may not be set to connect 'When computer starts'", displayName);
                changeToManual = TRUE;
            }
        } else {
            NSLog(@"Warning: ''%@' will not connect 'When computer starts' because the launchd .plist does not exist", displayName);
            changeToManual = TRUE;
        }
    } else {
        if (  launchdPlistWillConnectOnSystemStart  ) {
            NSLog(@"Warning: ''%@' will connect 'When computer starts' because the .plist exists", displayName);
            if (  ! enableWhenComputerStarts  ) {
                NSLog(@"Warning: ''%@' will connect 'When computer starts' but that should not be enabled", displayName);
            }
            changeToWhenComputerStarts = TRUE;
        }
    }
    
   if (  changeToManual  ) {
        [gTbDefaults removeObjectForKey: autoConnectKey];
        [gTbDefaults removeObjectForKey: ossKey];
        autoConnect   = [gTbDefaults boolForKey: autoConnectKey];
        onSystemStart = [gTbDefaults boolForKey: ossKey];
        if (  autoConnect || onSystemStart  ) {
            NSLog(@"Warning: Failed to set '%@' to connect manually; 'When computer starts' is %@enabled", displayName, (enableWhenComputerStarts ? @"" : @"NOT "));
        } else {
            NSLog(@"Warning: Set '%@' to connect manually because 'When computer starts' is not available and/or the launchd .plist did not exist", displayName);
        }
    } else if (  changeToWhenComputerStarts  )  {
        [gTbDefaults setBool: TRUE forKey: autoConnectKey];
        [gTbDefaults setBool: TRUE forKey: ossKey];
        autoConnect   = [gTbDefaults boolForKey: autoConnectKey];
        onSystemStart = [gTbDefaults boolForKey: ossKey];
       if (  autoConnect && onSystemStart  ) {
            NSLog(@"Warning: Set '%@' to connect 'When computer starts' because the launchd .plist exists; 'When computer starts is %@enabled", displayName, (enableWhenComputerStarts ? @"" : @"NOT "));
        } else {
            NSLog(@"Warning: Failed to set preferences of '%@' to connect 'When computer starts'", displayName);
        }
    }
    
    [self rawSetWhenToConnect];
    return;
}


-(void) authorizeAndSetWhenToConnect: (VPNConnection *) connection
{
    // RUNS IN NON-MAIN THREAD so authorization dialog doesn't block main thread
    //
    // Makes sure that
    //       * The autoConnect and -onSystemStart preferences
    //       * The configuration location (private/shared/deployed)
    //       * Any launchd .plist for the configuration
    // are all consistent.
    // Does this by creating/deleting a launchd .plist if it can (i.e., if the user authorizes it)
    // Otherwise may modify the preferences to reflect the existence of the launchd .plist
    
    if (  ! connection  ) {
        return;
    }
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    NSString * displayName = [connection displayName];
    
    BOOL enableWhenComputerStarts = [connection mayConnectWhenComputerStarts];
    
    NSString * autoConnectKey = [displayName stringByAppendingString: @"autoConnect"];
    BOOL autoConnect   = [gTbDefaults boolForKey: autoConnectKey];
    NSString * ossKey = [displayName stringByAppendingString: @"-onSystemStart"];
    BOOL onSystemStart = [gTbDefaults boolForKey: ossKey];
    
    BOOL launchdPlistWillConnectOnSystemStart = [connection launchdPlistWillConnectOnSystemStart];
    
    //Keep track of what we've done for an alert to the user
    BOOL failedToFixPreferences = FALSE;
    
    if (  autoConnect && onSystemStart  ) {
        if (  enableWhenComputerStarts  ) {
            if (  launchdPlistWillConnectOnSystemStart  ) {
                // All is OK -- prefs say to connect when system starts and launchd .plist agrees and it isn't a private configuration and has no credentials
            } else {
                // No launchd .plist -- try to create one
                if (  [connection checkConnectOnSystemStart: TRUE]  ) {
                    // Made it connect when computer starts
                } else {
                    // User cancelled attempt to make it connect when computer starts
                    NSLog(@"Preferences for '%@' say it should connect when the computer starts but it does not have a launchd .plist and the user did not authorize creating a .plist. Attempting to repair preferences...", displayName);
                    [gTbDefaults setBool: FALSE forKey: autoConnectKey];
                    if (  ! [gTbDefaults boolForKey: autoConnectKey]  ) {
                        NSLog(@"Successfully set '%@' preference to FALSE", autoConnectKey);
                    } else {
                        NSLog(@"Unable to set '%@' preference to FALSE", autoConnectKey);
                        failedToFixPreferences = TRUE;
                    }
                    [gTbDefaults setBool: FALSE forKey: ossKey];
                    if (  ! [gTbDefaults boolForKey: ossKey]  ) {
                        NSLog(@"Successfully set '%@' preference to FALSE", ossKey);
                    } else {
                        NSLog(@"Unable to set '%@' preference to FALSE", ossKey);
                        failedToFixPreferences = TRUE;
                    }
                }
            }
        } else {
            // Private configuration or has credentials
            if (  ! launchdPlistWillConnectOnSystemStart  ) {
                // Prefs, but not launchd, says will connnect on system start but it is a private configuration or has credentials
                NSLog(@"Preferences for '%@' say it should connect when the computer starts but it is a private configuration or has credentials. Attempting to repair preferences...", displayName);
                [gTbDefaults setBool: FALSE forKey: autoConnectKey];
                if (  ! [gTbDefaults boolForKey: autoConnectKey]  ) {
                    NSLog(@"Successfully set '%@' preference to FALSE", autoConnectKey);
                } else {
                    NSLog(@"Unable to set '%@' preference to FALSE", autoConnectKey);
                    failedToFixPreferences = TRUE;
                }
                [gTbDefaults setBool: FALSE forKey: ossKey];
                if (  ! [gTbDefaults boolForKey: ossKey]  ) {
                    NSLog(@"Successfully set '%@' preference to FALSE", ossKey);
                } else {
                    NSLog(@"Unable to set '%@' preference to FALSE", ossKey);
                    failedToFixPreferences = TRUE;
                }
            } else {
                // Prefs and launchd says connect on user start but private configuration, so can't. Try to remove the launchd .plist
                if (  [connection checkConnectOnSystemStart: FALSE]  ) {
                    // User cancelled attempt to make it NOT connect when computer starts
                    NSLog(@"Preferences for '%@' say it should connect when the computer starts and a launchd .plist exists for that, but it is a private configuration or has credentials. User cancelled attempt to repair.", displayName);
                } else {
                    NSLog(@"Preferences for '%@' say it should connect when the computer starts and a launchd .plist exists for that, but it is a private configuration or has credentials. The launchd .plist has been removed. Attempting to repair preferences...", displayName);
                    [gTbDefaults setBool: FALSE forKey: autoConnectKey];
                    if (  ! [gTbDefaults boolForKey: autoConnectKey]  ) {
                        NSLog(@"Successfully set '%@' preference to FALSE", autoConnectKey);
                    } else {
                        NSLog(@"Unable to set '%@' preference to FALSE", autoConnectKey);
                        failedToFixPreferences = TRUE;
                    }
                    [gTbDefaults setBool: FALSE forKey: ossKey];
                    if (  ! [gTbDefaults boolForKey: ossKey]  ) {
                        NSLog(@"Successfully set '%@' preference to FALSE", ossKey);
                    } else {
                        NSLog(@"Unable to set '%@' preference to FALSE", ossKey);
                        failedToFixPreferences = TRUE;
                    }
                }
            }
        }
    } else {
        // Manual or when Tunnelblick is launched
        if (  launchdPlistWillConnectOnSystemStart  ) {
            // launchd .plist exists but prefs are not connect when computer starts. Attempt to remove .plist
            if (  [connection checkConnectOnSystemStart: FALSE]  ) {
                // User cancelled attempt to make it NOT connect when computer starts
                NSLog(@"Preferences for '%@' say it should NOT connect when the computer starts but a launchd .plist exists for that and the user cancelled an attempt to remove the .plist. Attempting to repair preferences.", displayName);
                if (  ! [gTbDefaults boolForKey: autoConnectKey]  ) {
                    [gTbDefaults setBool: TRUE forKey: autoConnectKey];
                    if (  [gTbDefaults boolForKey: autoConnectKey]  ) {
                        NSLog(@"Successfully set '%@' preference to TRUE", autoConnectKey);
                    } else {
                        NSLog(@"Unable to set '%@' preference to TRUE", autoConnectKey);
                        failedToFixPreferences = TRUE;
                    }
                }
                if (  ! [gTbDefaults boolForKey: ossKey]  ) {
                    [gTbDefaults setBool: TRUE forKey: ossKey];
                    if (  [gTbDefaults boolForKey: ossKey]  ) {
                        NSLog(@"Successfully set '%@' preference to TRUE", ossKey);
                    } else {
                        NSLog(@"Unable to set '%@' preference to TRUE", ossKey);
                        failedToFixPreferences = TRUE;
                    }
                }
            } else {
                NSLog(@"Preferences for '%@' say it should NOT connect when the computer starts and a launchd .plist existed but has been removed.", displayName);
            }
        }
    }
    
    if (  failedToFixPreferences  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          [NSString stringWithFormat:
                           NSLocalizedString(@"Tunnelblick failed to repair problems with preferences for '%@'. Details are in the Console Log", @"Window text"),
                           [gMC localizedNameForDisplayName: displayName]]);
    }
    
    [connection performSelectorOnMainThread: @selector(validateWhenToConnect) withObject: nil waitUntilDone: NO];

    [pool drain];
}

-(void) setSelectedWhenToConnectIndex: (NSUInteger) newValue
{
    VPNConnection * connection = [self selectedConnection];
    NSUInteger oldValue = selectedWhenToConnectIndex;
    if (  newValue != oldValue  ) {
        NSString * configurationName = [connection displayName];
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
        
        if (   (oldValue != 2)
            && (newValue != 2)  ) {
            [connection validateWhenToConnect];
        } else {
             [[configurationsPrefsView whenToConnectPopUpButton] selectItemAtIndex: (int)oldValue];
            selectedWhenToConnectIndex = oldValue;
            TBLog(@"DB-AA", @"setSelectedWhenToConnectIndex: authorization needed, so detaching new thread to do that");
            [NSThread detachNewThreadSelector: @selector(authorizeAndSetWhenToConnect:) toTarget: self withObject: connection];
        }
    }
}


-(void) setSelectedSetNameserverIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedSetNameserverIndex]]  ) {
        if (  ! [gMC doingSetupOfUI]  ) {
			NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                   newValue, @"NewValue",
								   @"useDNS", @"PreferenceName",
								   nil];
			[gMC performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
			
			// Must set the key now (even though setPreferenceForSelectedConfigurationsWithDict: will set it later) so the rest of the code in this method runs with the new setting
            NSString * actualKey = [[[self selectedConnection] displayName] stringByAppendingString: @"useDNS"];
            [gTbDefaults setObject: newValue forKey: actualKey];
        }
		
		// Must set the key above (even though setPreferenceForSelectedConfigurationsWithDict: will set it later) so the following code works with the new setting

        [self setSelectedSetNameserverIndexDirect: newValue];
        
		[self setupNetworkMonitoring: [self selectedConnection]];
		
        [self setupDisableSecondaryNetworkServices: [self selectedConnection]];

		// Set up IPv6 and reset of primary interface
		[self setupDisableIpv6OnTun: [self selectedConnection]];
		
        [settingsSheetWindowController monitorNetworkForChangesCheckboxChangedForConnection: [self selectedConnection]];
        [settingsSheetWindowController setupSettingsFromPreferences];
    }
}

-(void) setSelectedLoggingLevelIndex: (NSNumber *) newValue
{
    NSNumber * oldValue = [self selectedLoggingLevelIndex];
    
    if (  [newValue isNotEqualTo: oldValue]  ) {
        
        VPNConnection * connection = [self selectedConnection];
        
        if (  ! [gMC doingSetupOfUI]  ) {
            NSNumber * preferenceValue = (  [newValue isEqualToNumber: [NSNumber numberWithUnsignedInt: 0]]
                                          ? [NSNumber numberWithUnsignedInt: TUNNELBLICK_NO_LOGGING_LEVEL]
                                          : ( [newValue isEqualToNumber: [NSNumber numberWithUnsignedInt: 1]]
                                             ? [NSNumber numberWithUnsignedInt: TUNNELBLICK_CONFIG_LOGGING_LEVEL]
                                             : [NSNumber numberWithUnsignedInt: [newValue unsignedIntValue] - 2]));
			NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                   preferenceValue,  @"NewValue",
								   @"-loggingLevel", @"PreferenceName",
								   nil];
			[gMC performSelectorOnMainThread: @selector(setPreferenceForSelectedConfigurationsWithDict:) withObject: dict waitUntilDone: NO];
			
			// Must set the key now (even though setPreferenceForSelectedConfigurationsWithDict: will set it later) so the rest of the code in this method runs with the new setting
            NSString * actualKey = [[connection displayName] stringByAppendingString: @"-loggingLevel"];
            [gTbDefaults setObject: preferenceValue forKey: actualKey];
        }
		
		// Must set the key above (even though setPreferenceForSelectedConfigurationsWithDict: will set it later) so the following code works with the new setting
		
        [self setSelectedLoggingLevelIndexDirect: newValue];
        
        // Clear logs if going to/from no logging and we are currently disconnected
        if (   [newValue isEqualToNumber: [NSNumber numberWithInt: 0]]
            || [oldValue isEqualToNumber: [NSNumber numberWithInt: 0]]  ) {
            if (  [connection isDisconnected]  ) {
                NSArray * arguments = [NSArray arrayWithObjects: @"deleteLog", [connection displayName], configLocCodeStringForPath([connection configPath]), nil];
                runOpenvpnstart(arguments, nil, nil);
                [connection clearLog];
            }
        }
    }
}

-(NSInteger) rowForName: (NSString *) name {

    if ( ! name  ) {
        return -1;
    }

    ConfigurationsView      * cv   = [self configurationsPrefsView];
    LeftNavDataSource       * ds   = [cv leftNavDataSrc];
    LeftNavItem             * item = [ds itemForName: name];

    LeftNavViewController   * ovc  = [cv outlineViewController];
    NSOutlineView           * ov   = [ovc outlineView];
    NSInteger                 row  = (  ov
                                      ? [ov rowForItem: item]
                                      : -1);
    return row;
}

-(NSString *) nameForRow: (NSInteger) row {

    if (  row == -1  ) {
        return nil;
    }

    NSOutlineView     * oV   = [[configurationsPrefsView outlineViewController] outlineView];
    LeftNavItem       * item = [oV itemAtRow: row];
    NSString          * name = [item displayName];
    return name;
}

-(void) forceSelectionOfRow: (NSInteger) row {

    NSOutlineView * oV = [[configurationsPrefsView outlineViewController] outlineView];
    NSIndexSet * ixs = [NSIndexSet indexSetWithIndex: row];
    [oV selectRowIndexes: ixs byExtendingSelection: NO];
}

-(void) tableViewSelectionDidChange:(NSNotification *)notification
{
	(void) notification;
	
    [self performSelectorOnMainThread: @selector(selectedLeftNavListIndexChanged) withObject: nil waitUntilDone: NO];
}

-(void) selectedLeftNavListIndexChanged
{
    NSInteger n = [[[configurationsPrefsView outlineViewController] outlineView] selectedRow];
    [self setSelectedLeftNavListIndex: n];
}

-(void) setSelectedLeftNavListIndex: (NSUInteger) newValue
{
    NSString * newName = [self nameForRow: newValue];

    if (  [newName isEqualToString: previouslySelectedNameOnLeftNavList]  ) {
        return;
    }

    if (  ! newName  ) {
        newName = [self nameForRow: 1];
        if (  ! newName  ) {
            NSLog(@"setSelectedLeftNavListIndex: Could not get nameForRow: 1");
            return;
        }

        [self forceSelectionOfRow: 1];
        return;
    }

    VPNConnection * newConnection = [gMC connectionForDisplayName: newName];

    VPNConnection * oldConnection = [gMC connectionForDisplayName: previouslySelectedNameOnLeftNavList];

    [oldConnection stopMonitoringLogFiles];

    [self setPreviouslySelectedNameOnLeftNavList: newName];
    [gTbDefaults setObject: newName forKey: @"leftNavSelectedDisplayName"];

    BOOL showingLogTab = (   [currentViewName isEqualToString: NSLocalizedString(@"Configurations", @"Window title")]
                          && [[configurationsPrefsView configurationsTabView] selectedTabViewItem] == [configurationsPrefsView logTabViewItem]);

    if (  showingLogTab  ) {
        [newConnection startMonitoringLogFiles];
    }

    [settingsSheetWindowController setConfigurationName: newName];

    BOOL savedDoingSetupOfUI = [gMC doingSetupOfUI];
    [gMC setDoingSetupOfUI: TRUE];

    [self validateDetailsWindowControlsForConnection: newConnection];

    [gMC setDoingSetupOfUI: savedDoingSetupOfUI];
}

//***************************************************************************************************************

-(void) setupCheckForBetasCheckbox {

	BOOL forceBeta = [gTbInfo runningATunnelblickBeta];
	BOOL beta = ( forceBeta
				 ? YES
				 : [gTbDefaults boolForKey: @"updateCheckBetas"]);
	
	TBButton * checkbox = [generalPrefsView updatesCheckForBetaUpdatesCheckbox];
	[checkbox setState: (  beta
						 ? NSOnState
						 : NSOffState)];
	[checkbox setEnabled: ! forceBeta];
}

-(void) setupUpdatesCheckboxes {
	
    // Set values for the update checkboxes
	
    BOOL userCanUpdate = (   [gTbInfo userIsAnAdmin]
                          || ( ! [gTbDefaults boolForKey:@"onlyAdminCanUpdate"])  );

	if (   ( ! userCanUpdate )
        || [gTbDefaults boolForKey:@"inhibitOutboundTunneblickTraffic"]  ) {
		TBButton * checkbox = [generalPrefsView updatesCheckAutomaticallyCheckbox];
		[checkbox setState:   NSOffState];
		[checkbox setEnabled: NO];
        
        checkbox = [generalPrefsView updatesCheckOnlyWhenInVPNCheckbox];
        [checkbox setState:   NSOffState];
        [checkbox setEnabled: NO];

        checkbox = [generalPrefsView updatesDownloadWhenAvailableCheckbox];
        [checkbox setState:   NSOffState];
        [checkbox setEnabled: NO];

	} else {
		[self setValueForCheckbox: [generalPrefsView updatesCheckAutomaticallyCheckbox]
					preferenceKey: @"updateCheckAutomatically"
						 inverted: NO
					   defaultsTo: FALSE];
        [self setValueForCheckbox: [generalPrefsView updatesCheckOnlyWhenInVPNCheckbox]
                    preferenceKey: @"TBUpdaterCheckOnlyWhenConnectedToVPN"
                         inverted: NO
                       defaultsTo: FALSE];
        [self setValueForCheckbox: [generalPrefsView updatesDownloadWhenAvailableCheckbox]
                    preferenceKey: @"TBUpdaterDownloadUpdateWhenAvailable"
                         inverted: NO
                       defaultsTo: FALSE];
    }
	
	[self setupCheckForBetasCheckbox];
	
    // Set the last update date/time
    [self updateLastCheckedDate];

}

-(void) setupUpdatesAdminApprovalForKeyAndCertificateChangesCheckbox {
	
    TBButton * checkbox = [generalPrefsView generalAdminApprovalForKeyAndCertificateChangesCheckbox];
    [checkbox setState: (  okToUpdateConfigurationsWithoutAdminApproval()
                         ? NSOffState
                         : NSOnState)];
}

-(void) setupUpdatesAdminApprovalForAppUpdatesCheckbox {

    TBButton * checkbox = [generalPrefsView updatesAdminApprovalForAppUpdatesCheckbox];
    [checkbox setState: (  okToUpdateAppWithoutAdminApproval()
                         ? NSOffState
                         : NSOnState)];
}

-(void) setupGeneralView
{
	[self setupUpdatesAdminApprovalForKeyAndCertificateChangesCheckbox];
    [self setupUpdatesAdminApprovalForAppUpdatesCheckbox];

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
    NSUInteger i;
    for (  i=0; i<[list count]; i++  ) {
        NSDictionary * dict = [list objectAtIndex: i];
        NSString * listValue = [dict objectForKey: @"value"];
        NSUInteger listValueSize;
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
        [self setSelectedMaximumLogSizeIndex: [NSNumber numberWithUnsignedInteger: logSizeIx]];
    } else {
        NSLog(@"Invalid selectedMaximumLogSizeIndex %lu; maximum is %ld", (unsigned long)logSizeIx, (long) [list count]-1);
    }
    
    [[generalPrefsView maximumLogSizeButton] setEnabled: [gTbDefaults canChangeValueForKey: @"maxLogDisplaySize"]];
}

-(void) updateLastCheckedDate
{
    NSDate * lastCheckedDate = [gTbDefaults dateForKey: @"SULastCheckTime"];
    NSString * lastChecked = (  lastCheckedDate
                              ? [lastCheckedDate tunnelblickUserLogRepresentationWithoutMicroseconds]
                              : NSLocalizedString(@"(Never checked)", @"Window text"));
    [[generalPrefsView updatesLastCheckedTFC] setTitle: [NSString stringWithFormat:
                                                         NSLocalizedString(@"Last checked: %@", @"Window text"),
                                                         lastChecked]];
}


-(IBAction) inhibitOutboundTBTrafficCheckboxWasClicked: (NSButton *) sender
{
	[gTbDefaults setBool: [sender state] forKey: @"inhibitOutboundTunneblickTraffic"];
	
	[self setupUpdatesCheckboxes];
	[self setupCheckIPAddress: nil];
	
    [gMC updateSettingsHaveChanged];
}


-(void) finishAdminApprovalCheckboxWasClickedHelper: (NSMutableDictionary *) dict {

    // Runs in main thread

    OSStatus status = [dict[@"status"] intValue];

    if (   (status != 0)      // status 0 means succeeded
        && (status != 1)  ) { // status 1 means cancelled by user
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString(@"Tunnelblick was unable to make the change. See the Console Log for details.", @"Window text"));
    }

    TBButton * checkbox = dict[@"button"];
    if (  checkbox == [generalPrefsView generalAdminApprovalForKeyAndCertificateChangesCheckbox]  ) {
        [self setupUpdatesAdminApprovalForKeyAndCertificateChangesCheckbox];
    } else {
        [self setupUpdatesAdminApprovalForAppUpdatesCheckbox];
    }
    [checkbox setEnabled: YES];
}

-(void) adminApprovalCheckboxWasClickedHelperThread: (NSMutableDictionary *) dict {

    // Runs in a separate thread so user authorization doesn't hang the main thread
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    NSString * forcedPreferencesDictionaryPath = [dict objectForKey: @"tempDictionaryPath"];

    NSString * message = NSLocalizedString(@"Tunnelblick needs to change a setting that may only be changed by a computer administrator.", @"Window text");
    SystemAuth * auth = [SystemAuth newAuthWithPrompt: message];
    if (  auth  ) {
        NSInteger status = [gMC runInstaller: INSTALLER_INSTALL_FORCED_PREFERENCES
                              extraArguments: [NSArray arrayWithObject: forcedPreferencesDictionaryPath]
                             usingSystemAuth: auth
                                installTblks: nil];
        [auth release];
        
        [dict setObject:[NSNumber numberWithLong: (long)status] forKey: @"status"];
    } else {
        OSStatus status = 1; // User cancelled installation
        [dict setObject: [NSNumber numberWithInt: status] forKey: @"status"];
    }

    [self performSelectorOnMainThread: @selector(finishAdminApprovalCheckboxWasClickedHelper:) withObject: dict waitUntilDone: NO];

    [gFileMgr tbRemovePathIfItExists: [forcedPreferencesDictionaryPath stringByDeletingLastPathComponent]];  // Ignore error; it has been logged
    
    [pool drain];
}

-(void) adminApprovalCheckboxWasClickedHelperButton: (TBButton *) checkbox preferenceName: (NSString *) preferenceName {

    if (  [checkbox isEnabled]  ) {
        [checkbox setEnabled: NO];
    } else {
        return;
    }

    BOOL newState = [checkbox state];

    NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH];
    NSMutableDictionary * newDict = (  dict
                                     ? [NSMutableDictionary dictionaryWithDictionary: dict]
                                     : [NSMutableDictionary dictionaryWithCapacity: 1]);

    [newDict setObject: [NSNumber numberWithBool: ( ! newState) ] forKey: preferenceName];

    NSString * tempDictionaryPath = [newTemporaryDirectoryPath() stringByAppendingPathComponent: @"forced-preferences.plist"];
    OSStatus status = (  tempDictionaryPath
                       ? (  [newDict writeToFile: tempDictionaryPath atomically: YES]
                          ? 0
                          : -1)
                       : -1);
    if (  status == 0  ) {
        NSMutableDictionary * threadDict = [@{@"button": checkbox,
                                              @"preferenceName": preferenceName,
                                              @"tempDictionaryPath": tempDictionaryPath}
                                             mutableCopy];

        [NSThread detachNewThreadSelector: @selector(adminApprovalCheckboxWasClickedHelperThread:) toTarget: self withObject: threadDict];
    }

    // We must restore the checkbox value because the change hasn't been made yet. However, we can't restore it until after all processing of the
    // ...WasClicked event is finished, because after this method returns, further processing changes the checkbox value to reflect the user's click.
    // To undo that afterwards, we delay changing the value for 0.2 seconds.
    SEL setupCheckbox = (  (checkbox == [generalPrefsView generalAdminApprovalForKeyAndCertificateChangesCheckbox])
                         ? @selector(setupUpdatesAdminApprovalForKeyAndCertificateChangesCheckbox)
                         : @selector(setupUpdatesAdminApprovalForAppUpdatesCheckbox));
    [self performSelector: setupCheckbox withObject: nil afterDelay: 0.2];
}

-(IBAction) generalAdminApprovalForKeyAndCertificateChangesCheckboxWasClicked: (NSButton *) sender
{
    [self adminApprovalCheckboxWasClickedHelperButton: [generalPrefsView generalAdminApprovalForKeyAndCertificateChangesCheckbox]
                                       preferenceName: @"allowNonAdminSafeConfigurationReplacement"];
}


-(IBAction) updatesCheckAutomaticallyCheckboxWasClicked: (NSButton *) sender
{
    [gTbDefaults setBool: [sender state] forKey: @"updateCheckAutomatically"];
    [gMC updateSettingsHaveChanged];
    [gMC setupUpdaterAutomaticChecks];
}

-(IBAction) updatesCheckAndDownloadOnlyWhenInVPNCheckboxWasClicked: (NSButton *) sender {
    [gTbDefaults setBool: [sender state] forKey: @"TBUpdaterCheckOnlyWhenConnectedToVPN"];
    [gMC updateSettingsHaveChanged];
}

-(IBAction) updatesDownloadWhenAvailableCheckboxWasClicked: (NSButton *) sender {

    [gTbDefaults setBool: [sender state] forKey: @"TBUpdaterDownloadUpdateWhenAvailable"];
    [gMC updateSettingsHaveChanged];
}

-(IBAction) updatesAdminApprovalForAppUpdatesCheckboxWasClicked: (NSButton *) sender {

    [self adminApprovalCheckboxWasClickedHelperButton: [generalPrefsView updatesAdminApprovalForAppUpdatesCheckbox]
                                       preferenceName: @"TBUpdaterAllowNonAdminToUpdateTunnelblick"];
}

-(IBAction) updatesCheckForBetaUpdatesCheckboxWasClicked: (NSButton *) sender
{
    [gTbDefaults setBool: [sender state] forKey: @"updateCheckBetas"];
}


-(IBAction) updatesCheckNowButtonWasClicked: (id) sender
{
	(void) sender;
	
    [gMC checkForUpdates: self];
    [gMC setLastCheckNow: [NSDate date]];
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

    TBShowAlertWindowClearCache();
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
        if (  [newValue unsignedIntegerValue] < [list count]  ) {
            
            [self setSelectedKeyboardShortcutIndexDirect: newValue];
            
            // Select the new size
            [ac setSelectionIndex: [newValue unsignedIntegerValue]];
            
            // Set the preference
            [gTbDefaults setObject: newValue forKey: @"keyboardShortcutIndex"];
            
            // Set the value we use
            [gMC setHotKeyIndex: [newValue unsignedIntValue]];
        }
    }
}    

-(void) setSelectedMaximumLogSizeIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedMaximumLogSizeIndex]]  ) {
        NSArrayController * ac = [generalPrefsView maximumLogSizeArrayController];
        NSArray * list = [ac content];
        if (  [newValue unsignedIntegerValue] < [list count]  ) {
            
            // Set the index
            [self setSelectedMaximumLogSizeIndexDirect: newValue];
            
            // Select the new size
            [ac setSelectionIndex: [newValue unsignedIntegerValue]];
            
            // Set the preference
            NSString * newPref = [[list objectAtIndex: [newValue unsignedIntegerValue]] objectForKey: @"value"];
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
    NSUInteger i;
    NSUInteger iconSetIx = NSNotFound;
    NSUInteger defaultIconSetIx = NSNotFound;
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
        [self setSelectedAppearanceIconSetIndex: [NSNumber numberWithUnsignedInteger: 0u]];
    } else {
        [self setSelectedAppearanceIconSetIndex: [NSNumber numberWithUnsignedInteger: iconSetIx]];
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
        [self setSelectedAppearanceConnectionWindowDisplayCriteriaIndex: [NSNumber numberWithUnsignedInteger: displayCriteriaIx]];
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
	
    [self setSelectedAppearanceConnectionWindowScreenIndexDirect: [NSNumber numberWithUnsignedInteger: NSNotFound]];
	
    NSArray * screens = [gMC screenList];
    
    if (   ([screens count] < 2)
		|| ([[self selectedAppearanceConnectionWindowDisplayCriteriaIndex] isEqualTo: [NSNumber numberWithUnsignedInteger: 0u]]  )  ) {
        
		// Show the default screen, but don't change the preference
		BOOL wereDoingSetupOfUI = [gMC doingSetupOfUI];
		[gMC setDoingSetupOfUI: TRUE];
        [self setSelectedAppearanceConnectionWindowScreenIndex: [NSNumber numberWithUnsignedInteger: 0u]];
		[gMC setDoingSetupOfUI: wereDoingSetupOfUI];
		
        [[appearancePrefsView appearanceConnectionWindowScreenButton] setEnabled: NO];
		
    } else {
		
        unsigned displayNumberFromPrefs = [gTbDefaults unsignedIntForKey: @"statusDisplayNumber" default: 0 min: 0 max: UINT_MAX];
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
        
        [self setSelectedAppearanceConnectionWindowScreenIndex: [NSNumber numberWithUnsignedInteger: screenIxToSelect]];
        
        [[appearancePrefsView appearanceConnectionWindowScreenButton] setEnabled: [gTbDefaults canChangeValueForKey: @"statusDisplayNumber"]];
    }
}

-(void) setupAppearanceView
{
	[self setupAppearanceIconSetButton];
    
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
    [gMC recreateMainMenuClearCache: YES];
}

-(IBAction) appearanceDisplayConnectionTimersCheckboxWasClicked: (NSButton *) sender
{
    [gTbDefaults setBool: [sender state]  forKey:@"showConnectedDurations"];
    [gMC changedDisplayConnectionTimersSettings];
}

-(IBAction) appearanceDisplaySplashScreenCheckboxWasClicked: (NSButton *) sender
{
	[gTbDefaults setBool: ! [sender state] forKey:@"doNotShowSplashScreen"];
}

-(IBAction) appearanceDisplayStatisticsWindowsCheckboxWasClicked: (NSButton *) sender
{
	[gTbDefaults setBool: ! [sender state] forKey:@"doNotShowNotificationWindowOnMouseover"];
}

-(IBAction) appearanceDisplayStatisticsWindowWhenDisconnectedCheckboxWasClicked: (NSButton *) sender
{
	[gTbDefaults setBool: ! [sender state] forKey:@"doNotShowDisconnectedNotificationWindows"];
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
        if (  [newValue unsignedIntegerValue] < [list count]  ) {
            
            [self setSelectedAppearanceIconSetIndexDirect: newValue];
            
            // Select the new index
            [ac setSelectionIndex: [newValue unsignedIntegerValue]];
            
            // Set the preference
            if (  [newValue unsignedIntegerValue] != NSNotFound  ) {
                // Set the preference
                NSString * iconSetName = [[[list objectAtIndex: [newValue unsignedIntegerValue]] objectForKey: @"value"] lastPathComponent];
                if (  [iconSetName isEqualToString: @"TunnelBlick.TBMenuIcons"]  ) {
                    [gTbDefaults removeObjectForKey: @"menuIconSet"];
                } else {
                    [gTbDefaults setObject: iconSetName forKey: @"menuIconSet"];
                }
            }
            
            // Start using the new setting
			if (  ! [gMC loadMenuIconSet]  ) {
				NSLog(@"Unable to load the Menu icon set");
				[gMC terminateBecause: terminatingBecauseOfError];
			}
        }
    }
}


-(void) setSelectedAppearanceConnectionWindowDisplayCriteriaIndex: (NSNumber *) newValue
{
    if (  [newValue isNotEqualTo: [self selectedAppearanceConnectionWindowDisplayCriteriaIndex]]  ) {
        NSArrayController * ac = [appearancePrefsView appearanceConnectionWindowDisplayCriteriaArrayController];
        NSArray * list = [ac content];
        if (  [newValue unsignedIntegerValue] < [list count]  ) {
            
            [self setSelectedAppearanceConnectionWindowDisplayCriteriaIndexDirect: newValue];
            
            // Select the new index
            [ac setSelectionIndex: [newValue unsignedIntegerValue]];
            
            // Set the preference
            NSDictionary * dict = [list objectAtIndex: [newValue unsignedIntegerValue]];
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
        if (  [newValue unsignedIntegerValue] < [list count]  ) {
            
            [self setSelectedAppearanceConnectionWindowScreenIndexDirect: newValue];
            
            // Select the new size
            [ac setSelectionIndex: [newValue unsignedIntegerValue]];
            
            // Set the preference if this isn't just the initialization
            if (  ! [gMC doingSetupOfUI]  ) {
                // Set the preference
                NSNumber * displayNumber = [[list objectAtIndex: [newValue unsignedIntegerValue]] objectForKey: @"value"];
				[gTbDefaults setObject: displayNumber forKey: @"statusDisplayNumber"];
            }
        }
    }
}

//***************************************************************************************************************

-(void) setupInfoView
{
}

//***************************************************************************************************************

-(void) setupUtilitiesView
{
}

-(void) setupInstallOrUninstallKextsButton {
    
    [utilitiesPrefsView setupInstallOrUninstallKextsButton];
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

-(IBAction) utilitiesUninstallButtonWasClicked: (id) sender
{
	(void) sender;
	
	[gMC performSelectorOnMainThread: @selector(uninstall) withObject: nil waitUntilDone: NO];
}

-(IBAction) utilitiesInstallKextsButtonWasClicked: (id) sender
{
    (void) sender;
    
    [gMC performSelectorOnMainThread: @selector(installOrUninstallKexts) withObject: nil waitUntilDone: NO];
}

-(void) notifyAboutOpenvpnProcessesQuit: (NSString *) message {
	
	[utilitiesPrefsView setUtilitiesQuitAllOpenvpnStatusText: message];
	
	// Restore the "Quit All OpenVPN Processes" button to normal
	NSButton * button = [utilitiesPrefsView utilitiesQuitAllOpenVpnButton];
	[button setAction: @selector(utilitiesQuitAllOpenVpnButtonWasClicked:)];
	[button setEnabled: YES];
	[utilitiesPrefsView setUtilitiesQuitAllOpenVpnButtonTitle: NSLocalizedString(@"Quit All OpenVPN Processes", @"Button")];
}

-(void) terminateAllOpenvpnProcessesThread {
	
	// Tries to terminate all processes named "openvpn" once per second using "openvpnstart killall".
	// Keeps trying until the user cancels or there are no processes named "openvpn".
	// Notifies user of progress and of the result in the status area next to the "Quit All OpenVPN Processes" button.
	// (Note that the status area is erased five seconds after being changed.)
	
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	NSString * message;
	
	if (  [[NSApp pIdsForOpenVPNProcessesOnlyMain: YES] count] == 0  ) {

		message = NSLocalizedString(@"There are no OpenVPN processes running", @"Window text");
	
	} else {
		
		NSUInteger i = 0;
		while (  ! cancelUtilitiesQuitAllOpenVpn  ) {

			if (  [[NSApp pIdsForOpenVPNProcessesOnlyMain: YES] count] == 0  ) {
 				break;
			}
			
			// The first time through, and thereafter every tenth time through (about once per second):
			//     * Try to terminate all "openvpn" processes
			//	   * Release memory (otherwise it accumlates because of the use of pIdsForOpenVPNProcessesOnlyMain)
			
			if (  (i % 10)  == 0  ) {
				TBLog(@"DB-TO", @"terminateAllOpenvpnProcessesThread: will run 'openvpnstart killall'; stack trace: %@", callStack());
				runOpenvpnstart([NSArray arrayWithObject: @"killall"], nil, nil);
				
				[pool drain];
				pool = [[NSAutoreleasePool alloc] init];
			}
			
			usleep(ONE_TENTH_OF_A_SECOND_IN_MICROSECONDS);

			i++;
		}
		
		message = (  ( [[NSApp pIdsForOpenVPNProcessesOnlyMain: YES] count] == 0 )
				   ? NSLocalizedString(@"All OpenVPN processes have quit", @"Window text")
				   : NSLocalizedString(@"Cancelled trying to quit all OpenVPN processes", @"Window text"));
		TBLog(@"DB-TO", @"terminateAllOpenvpnProcessesThread: %@", message);
	}
	
	[self performSelectorOnMainThread: @selector(notifyAboutOpenvpnProcessesQuit:) withObject: message waitUntilDone: NO];
		
	[pool drain];
}

-(IBAction) utilitiesQuitAllOpenVpnCancelButtonWasClicked: (id) sender
{
	(void) sender;
	
	cancelUtilitiesQuitAllOpenVpn = YES;
	[[utilitiesPrefsView utilitiesQuitAllOpenVpnButton] setEnabled: NO];
}

-(IBAction) utilitiesQuitAllOpenVpnButtonWasClicked: (id) sender
{
	(void) sender;
	
	if (  ! ALLOW_OPENVPNSTART_KILLALL  ) {
		return;
	}
	
	if ( [[NSApp pIdsForOpenVPNProcessesOnlyMain: YES] count] == 0  ) {
		[utilitiesPrefsView setUtilitiesQuitAllOpenvpnStatusText: NSLocalizedString(@"There are no OpenVPN processes running", @"Window text")];
	} else {
		// Change the button to a "Cancel" button
		TBButton * button = [utilitiesPrefsView utilitiesQuitAllOpenVpnButton];
		[button setTitle: NSLocalizedString(@"Cancel", @"Button")];
		[button setAction: @selector(utilitiesQuitAllOpenVpnCancelButtonWasClicked:)];

		[utilitiesPrefsView setUtilitiesQuitAllOpenvpnStatusText: NSLocalizedString(@"Trying to quit all OpenVPN processes...", @"Window text")];
		
		cancelUtilitiesQuitAllOpenVpn = NO;
		[NSThread detachNewThreadSelector: @selector(terminateAllOpenvpnProcessesThread) toTarget: self withObject: nil];
	}
}

-(IBAction) consoleLogToClipboardButtonWasClicked: (id) sender {
	
	(void) sender;
	
	[self indicateWaitingForConsoleLogToClipboard];
	
	[ConfigurationManager putConsoleLogOnClipboardInNewThread];
}

-(IBAction) utilitiesExportTunnelblickSetupButtonWasClicked: (id) sender
{
	(void) sender;
	
	[self indicateWaitingForUtilitiesExportTunnelblickSetup];

	[ConfigurationManager exportTunnelblickSetupInNewThread];
}

-(IBAction) utilitiesHelpButtonWasClicked: (id) sender
{
	(void) sender;
	
    MyGotoHelpPage(@"preferences-utilities.html", nil);
}

//***************************************************************************************************************

-(void) setValueForCheckbox: (TBButton *) checkbox
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
