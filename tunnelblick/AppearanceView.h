/*
 * Copyright 2011, 2012, 2013, 2016 Jonathan K. Bullard. All rights reserved.
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

@class TBInfoButton;

@interface AppearanceView : NSView {
    
    IBOutlet NSTextFieldCell    * appearanceIconTFC;
    IBOutlet NSArrayController  * appearanceIconSetArrayController;
    IBOutlet NSButton           * appearanceIconSetButton;
    IBOutlet NSButton           * appearancePlaceIconNearSpotlightCheckbox;
    IBOutlet TBInfoButton       * infoButtonForAppearancePlaceIconNearSpotlightCheckbox;
    
    IBOutlet NSTextFieldCell    * appearanceMenuTFC;
    IBOutlet NSButton           * appearanceDisplayConnectionSubmenusCheckbox;
    IBOutlet NSButton           * appearanceDisplayConnectionTimersCheckbox;
    
    IBOutlet NSTextFieldCell    * appearanceSplashTFC;
    IBOutlet NSButton           * appearanceDisplaySplashScreenCheckbox;

    IBOutlet NSTextFieldCell    * appearanceConnectionWindowDisplayCriteriaTFC;
    IBOutlet NSArrayController  * appearanceConnectionWindowDisplayCriteriaArrayController;
    IBOutlet NSButton           * appearanceConnectionWindowDisplayCriteriaButton;
    
    IBOutlet NSArrayController  * appearanceConnectionWindowScreenArrayController;
    IBOutlet NSButton           * appearanceConnectionWindowScreenButton;
    
    IBOutlet NSButton           * appearanceDisplayStatisticsWindowsCheckbox;
    IBOutlet NSButton           * appearanceDisplayStatisticsWindowsWhenDisconnectedCheckbox;
    
    IBOutlet NSButton           * appearanceHelpButton;
}

TBPROPERTY_READONLY(NSArrayController *, appearanceIconSetArrayController)
TBPROPERTY_READONLY(NSButton *,          appearanceIconSetButton)
TBPROPERTY_READONLY(NSButton *,          appearancePlaceIconNearSpotlightCheckbox)
TBPROPERTY_READONLY(TBInfoButton *,      infoButtonForAppearancePlaceIconNearSpotlightCheckbox)

TBPROPERTY_READONLY(NSButton *,          appearanceDisplayConnectionSubmenusCheckbox)
TBPROPERTY_READONLY(NSButton *,          appearanceDisplayConnectionTimersCheckbox)

TBPROPERTY_READONLY(NSButton *,          appearanceDisplaySplashScreenCheckbox)

TBPROPERTY_READONLY(NSArrayController *, appearanceConnectionWindowDisplayCriteriaArrayController)
TBPROPERTY_READONLY(NSButton *,          appearanceConnectionWindowDisplayCriteriaButton)

TBPROPERTY_READONLY(NSArrayController *, appearanceConnectionWindowScreenArrayController)
TBPROPERTY_READONLY(NSButton *,          appearanceConnectionWindowScreenButton)

TBPROPERTY_READONLY(NSButton *,          appearanceDisplayStatisticsWindowsCheckbox)
TBPROPERTY_READONLY(NSButton *,          appearanceDisplayStatisticsWindowsWhenDisconnectedCheckbox)

@end
