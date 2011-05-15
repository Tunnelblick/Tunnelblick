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
#import "DBPrefsWindowController.h"

@class GeneralView;
@class AppearanceView;
@class InfoView;

@interface MyPrefsWindowController : DBPrefsWindowController {
    
    IBOutlet GeneralView        * generalPrefsView;
    IBOutlet AppearanceView     * appearancePrefsView;
    IBOutlet InfoView           * infoPrefsView;
    
    // For GeneralView
    IBOutlet unsigned             selectedKeyboardShortcutIndex;
    IBOutlet unsigned             selectedMaximumLogSizeIndex;
    
    // For AppearanceView
    IBOutlet unsigned             selectedAppearanceIconSetIndex;
    IBOutlet unsigned             selectedAppearanceConnectionWindowDisplayCriteriaIndex;
}

// Methods for GeneralView

-(IBAction) useShadowCopiesCheckboxWasClicked:            (id) sender;
-(IBAction) monitorConfigurationFolderCheckboxWasClicked: (id) sender;

-(IBAction) updatesCheckAutomaticallyCheckboxWasClicked:  (id) sender;
-(IBAction) updatesCheckNowButtonWasClicked:              (id) sender;

-(unsigned) selectedKeyboardShortcutIndex;
-(void)     setSelectedKeyboardShortcutIndex:             (unsigned) newValue;

-(unsigned) selectedMaximumLogSizeIndex;
-(void)     setSelectedMaximumLogSizeIndex:               (unsigned) newValue;

-(IBAction) resetDisabledWarningsButtonWasClicked:        (id) sender;

-(IBAction) generalHelpButtonWasClicked:                  (id) sender;


// Methods for AppearanceView

-(unsigned) selectedAppearanceIconSetIndex;
-(void)     setSelectedAppearanceIconSetIndex: (unsigned) newValue;

-(IBAction) appearancePlaceIconNearSpotlightCheckboxWasClicked:    (id) sender;

-(IBAction) appearanceDisplayConnectionSubmenusCheckboxWasClicked: (id) sender;
-(IBAction) appearanceDisplayConnectionTimersCheckboxWasClicked:   (id) sender;

-(unsigned) selectedAppearanceConnectionWindowDisplayCriteriaIndex;
-(void)     setSelectedAppearanceConnectionWindowDisplayCriteriaIndex: (unsigned) newValue;

-(IBAction) appearanceHelpButtonWasClicked:                        (id) sender;

@end
