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
#import "MenuController.h"
#import "GeneralView.h"
#import "AppearanceView.h"
#import "InfoView.h"


extern TBUserDefaults * gTbDefaults;
extern unsigned         gMaximumLogSize;
extern NSArray        * gProgramPreferences;
extern NSArray        * gConfigurationPreferences;

@interface MyPrefsWindowController()

-(void) setupViews;
-(void) setupGeneralView;
-(void) setupAppearanceView;
-(void) setupInfoView;

-(void) setValueForCheckbox: (NSButton *) checkbox
              preferenceKey: (NSString *) preferenceKey
                   inverted: (BOOL)       inverted
                 defaultsTo: (BOOL)       defaultsTo;

-(void) updateLastCheckedDate;

@end

@implementation MyPrefsWindowController

-(void) setupToolbar
{
    [self addView: generalPrefsView         label: @"General"];
    [self addView: appearancePrefsView      label: @"Appearance"];
    [self addView: infoPrefsView            label: @"Info"];
    
    [self setupViews];
}

-(void) setupViews
{
    selectedKeyboardShortcutIndex = UINT_MAX;
    selectedMaximumLogSizeIndex = UINT_MAX;
    selectedAppearanceIconSetIndex = UINT_MAX;
    selectedAppearanceConnectionWindowDisplayCriteriaIndex = UINT_MAX;
    
    [self setupGeneralView];
    [self setupAppearanceView];
    [self setupInfoView];
}

// Overrides superclass
-(void) oldViewWillDisappear
{
    [infoPrefsView oldViewWillDisappear];
}


// Overrides superclass
-(void) newViewWillAppear
{
    [infoPrefsView newViewWillAppear];
}

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
    id logSizePref = [gTbDefaults objectForKey: @"maximumLogSize"];
    if (  logSizePref  ) {
        if (  [logSizePref respondsToSelector:@selector(intValue)]  ) {
            prefSize = [logSizePref intValue];
        } else {
            NSLog(@"'maximumLogSize' preference is invalid.");
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
            NSLog(@"'maximumLogSize' preference is invalid.");
            break;
        }
    }
    
    if (  logSizeIx == -1  ) {
        NSLog(@"'maximumLogSize' preference value of '%@' is not available", logSizePref);
        logSizeIx = 2;  // Second one should be '102400'
    }
    
    if (  logSizeIx < [list count]  ) {
        [self setSelectedMaximumLogSizeIndex: logSizeIx];
    } else {
        NSLog(@"Invalid selectedMaximumLogSizeIndex %d; maximum is %d", logSizeIx, [list count]-1);
    }
    
    [[generalPrefsView maximumLogSizeButton] setEnabled: [gTbDefaults canChangeValueForKey: @"maximumLogSize"]];
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


-(IBAction) appearanceHelpButtonWasClicked: (id) sender
{
    OSStatus err;
    if (err = MyGotoHelpPage(CFSTR("preferences-appearance.html"), NULL)  ) {
        NSLog(@"Error %d from MyGotoHelpPage()", err);
    }
}


-(unsigned) selectedKeyboardShortcutIndex
{
    return selectedKeyboardShortcutIndex;
}


-(void) setSelectedKeyboardShortcutIndex: (unsigned) newValue
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


-(unsigned) selectedMaximumLogSizeIndex
{
    return selectedMaximumLogSizeIndex;
}


-(void) setSelectedMaximumLogSizeIndex: (unsigned) newValue
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
            [gTbDefaults setObject: newPref forKey: @"maximumLogSize"];
            
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
         [NSDictionary dictionaryWithObjectsAndKeys: @"(None available)", "name", @"", "value", nil];
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

-(unsigned) selectedAppearanceIconSetIndex
{
    return selectedAppearanceIconSetIndex;
}

-(void) setSelectedAppearanceIconSetIndex: (unsigned) newValue
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

-(unsigned) selectedAppearanceConnectionWindowDisplayCriteriaIndex
{
    return selectedAppearanceConnectionWindowDisplayCriteriaIndex;
}


-(void) setSelectedAppearanceConnectionWindowDisplayCriteriaIndex: (unsigned) newValue
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

@end
