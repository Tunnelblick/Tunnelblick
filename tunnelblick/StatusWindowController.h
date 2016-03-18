/*
 * Copyright 2011, 2012, 2013, 2015, 2016 Jonathan K. Bullard. All rights reserved.
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

@interface StatusWindowController : NSWindowController <NSAnimationDelegate,NSWindowDelegate>
{
    
    IBOutlet NSButton        * connectButton;
    IBOutlet NSButton        * disconnectButton;
    IBOutlet NSTextFieldCell * configurationNameTFC;
    IBOutlet NSTextFieldCell * statusTFC;
    IBOutlet NSImageView     * animationIV;
    
    IBOutlet NSView          * statisticsView;
    IBOutlet NSTextFieldCell * inTFC;
    IBOutlet NSTextFieldCell * inRateTFC;
    IBOutlet NSTextFieldCell * inRateUnitsTFC;
    IBOutlet NSTextFieldCell * inTotalTFC;
    IBOutlet NSTextFieldCell * inTotalUnitsTFC;

    IBOutlet NSTextFieldCell * outTFC;
    IBOutlet NSTextFieldCell * outRateTFC;
    IBOutlet NSTextFieldCell * outRateUnitsTFC;
    IBOutlet NSTextFieldCell * outTotalTFC;
    IBOutlet NSTextFieldCell * outTotalUnitsTFC;
    
    IBOutlet NSTextField     * inTF;
    IBOutlet NSTextField     * inRateTF;
    IBOutlet NSTextField     * inRateUnitsTF;
    IBOutlet NSTextField     * inTotalTF;
    IBOutlet NSTextField     * inTotalUnitsTF;
    
    IBOutlet NSTextField     * outTF;
    IBOutlet NSTextField     * outRateTF;
    IBOutlet NSTextField     * outRateUnitsTF;
    IBOutlet NSTextField     * outTotalTF;
    IBOutlet NSTextField     * outTotalUnitsTF;
    
    NSUInteger                 statusScreenPosition; // Position of status window (0, 1, 2...)
    //                                               // Corresponds to an entry in the statusScreenPositionsInUse array,
    //                                               // which is a static variable defined at the start of StatusWindowController.m
    
    NSString                 * name;            // Name we are displaying - displayName of configuration
    NSString                 * localName;       // localizedName of configuration
    NSString                 * status;          // Status (e.g., "EXITING") of the configuration
    NSString                 * connectedSince;  // Time has been connected
    
    NSTrackingRectTag          trackingRectTag; // Used to track mouseEntered and mouseExited events for the window's view
    
    NSAnimation              * theAnim;         // For animation in the window
    
    CGFloat                    originalWidth;   // Width of window frame with original title ("XXXX...")
    CGFloat                    currentWidth;    // Width of window frame currently
    
    BOOL                       isOpen;          // Flag for animating window fade-in and fade-out

    BOOL                       closedByRedDot;  // Flag that windowWillClose was invoked BEFORE closeAfterFadeOut.
    //                                          // That means that window was closed by the red dot (close button).
    
    BOOL                       closeAfterFadeOutClosedTheWindow; // Used to implement closedByRedDot
    
    BOOL                       haveLoadedFromNib;
    
    id                         delegate;
}

-(id)         initWithDelegate:       (id)         theDelegate;

-(void)       enableOrDisableButtons;

-(IBAction)   connectButtonWasClicked: (id)        sender;

-(IBAction)   disconnectButtonWasClicked: (id)     sender;

-(id)         delegate;

-(void)       fadeIn;
-(void)       fadeOut;

-(void)       restore;

-(void)       setStatus:              (NSString *) theStatus
                forName:              (NSString *) theName
         connectedSince:              (NSString *) time;

TBPROPERTY(NSString *, name,           setName)
TBPROPERTY(NSString *, localName,      setLocalName)
TBPROPERTY(NSString *, status,         setStatus)
TBPROPERTY(NSString *, connectedSince, setConnectedSince)
TBPROPERTY(BOOL,       closedByRedDot, setClosedByRedDot)

TBPROPERTY_READONLY(BOOL, haveLoadedFromNib)
TBPROPERTY_READONLY(BOOL, isOpen)

TBPROPERTY_READONLY(NSTextFieldCell *, statusTFC)

TBPROPERTY_READONLY(NSTextFieldCell *, inTFC)
TBPROPERTY_READONLY(NSTextFieldCell *, inRateTFC)
TBPROPERTY_READONLY(NSTextFieldCell *, inRateUnitsTFC)
TBPROPERTY_READONLY(NSTextFieldCell *, inTotalTFC)
TBPROPERTY_READONLY(NSTextFieldCell *, inTotalUnitsTFC)

TBPROPERTY_READONLY(NSTextFieldCell *, outTFC)
TBPROPERTY_READONLY(NSTextFieldCell *, outRateTFC)
TBPROPERTY_READONLY(NSTextFieldCell *, outRateUnitsTFC)
TBPROPERTY_READONLY(NSTextFieldCell *, outTotalTFC)
TBPROPERTY_READONLY(NSTextFieldCell *, outTotalUnitsTFC)

@end
