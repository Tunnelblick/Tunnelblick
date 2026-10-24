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
 *  distribution); if not, see http://www.gnu.org/licenses/.
 */


#import "StatusWindowController.h"

#import <pthread.h>

#import "defines.h"
#import "helper.h"

#import "MenuController.h"
#import "NSTimer+TB.h"
#import "TBOperationQueue.h"
#import "TBUserDefaults.h"
#import "UIHelper.h"


extern MenuController * gMC;
extern NSArray        * gRateUnits;
extern BOOL             gShuttingDownWorkspace;
extern TBUserDefaults * gTbDefaults;
extern NSArray        * gTotalUnits;

// The following must be small enough that it's square fits in an NSUInteger
#define NUMBER_OF_STATUS_SCREEN_POSITIONS 4096

static uint8_t statusScreenPositionsInUse[NUMBER_OF_STATUS_SCREEN_POSITIONS];

static pthread_mutex_t statusScreenPositionsInUseMutex = PTHREAD_MUTEX_INITIALIZER;

@interface StatusWindowController()   // Private methods

-(CGFloat) adjustWidthsToLargerOf: (NSTextField *) tf1 and: (NSTextField *) tf2;

-(void) initialiseAnim;

-(void) setSizeAndPosition;

-(void) setUpUnits: (NSTextField *) tf1 cell: (NSTextFieldCell *) tfc1
               and: (NSTextField *) tf2 cell: (NSTextFieldCell *) tfc2
             array: (NSArray *) array;

-(NSTextFieldCell *) statusTFC;

@end

@implementation StatusWindowController

-(id) initWithDelegate: (id) theDelegate
{
    self = [super initWithWindowNibName: [UIHelper appendRTLIfRTLLanguage: @"StatusWindow"]];
    if (  ! self  ) {
        return nil;
    }
    
    [super setShouldCascadeWindows: NO];    // We always set the window's position
    
    name   = @"";
    status = @"";
    
    originalWidth = 0.0;
    currentWidth  = 0.0;
    
    trackingRectTag = 0;
    
    haveLoadedFromNib = FALSE;
    isOpen = FALSE;
    closeAfterFadeOutClosedTheWindow = FALSE;
    closedByRedDot = FALSE;
    
    delegate = [theDelegate retain];
    
    [[NSNotificationCenter defaultCenter] addObserver: self 
                                             selector: @selector(NSWindowWillCloseNotification:) 
                                                 name: NSWindowWillCloseNotification 
                                               object: nil];        
    
    return self;
}

-(void) windowWillClose:(NSNotification *)notification {
    
    // If windowWillClose was invoked BEFORE closeAfterFadeOut closed the window, it means that the user
    // closed the window by clicking on the red dot (close button).
    //
    // If not, it means the window was closed by closeAfterFadeOut because it had timed out after the
    // pointer moved away from the Tunnelblick icon or a VPN status window.
    //
    // We use this to determine if the window was closed by the red dot, in which case we don't show
    // it again until the user connects the configuration.
    
    (void) notification;
    
    closedByRedDot = (! closeAfterFadeOutClosedTheWindow);
}

-(void) startMouseTracking {
    if ( haveLoadedFromNib ) {
        if (  trackingRectTag == 0  ) {
            NSView * windowView = [[self window] contentView];
            NSRect trackingFrame = [windowView frame];
            trackingFrame.size.height += 1000.0;    // Include the title bar in the tracking rectangle (will be clipped)
            
            trackingRectTag = [windowView addTrackingRect: trackingFrame
                                                    owner: self
                                                 userData: nil
                                             assumeInside: NO];
        }
    }
}

-(void) stopMouseTracking {
    if (  trackingRectTag != 0  ) {
        [[[self window] contentView] removeTrackingRect: trackingRectTag];
        trackingRectTag = 0;
    }
}

-(void) enableOrDisableButtons {
	
    if (  ! [TBOperationQueue shouldUIBeEnabledForDisplayName: name]  ) {
		[connectButton    setEnabled: NO];
		[disconnectButton setEnabled: YES];
	} else if (   [status isEqualToString: @"EXITING"]  ) {
		[connectButton    setEnabled: YES];
		[disconnectButton setEnabled: NO];
    } else {
		[connectButton    setEnabled: NO];
		[disconnectButton setEnabled: YES];
    }
    
    // Only the button that can be used is shown
    NSButton * shownButton  = (  [connectButton isEnabled] ? connectButton    : disconnectButton);
    NSButton * hiddenButton = (  [connectButton isEnabled] ? disconnectButton : connectButton);
    [hiddenButton setHidden: YES];
    [shownButton  setHidden: NO];
}

-(CGFloat) widestOf: (NSArray *) strings font: (NSFont *) font {
    
    CGFloat widest = 0.0;
    NSString * string;
    NSEnumerator * e = [strings objectEnumerator];
    while (  (string = [e nextObject])  ) {
        widest = MAX(widest, ceil([string sizeWithAttributes: @{NSFontAttributeName: font}].width));
    }
    return widest + 4.0;
}

-(NSStackView *) statisticsRowWithLabel: (NSTextField *) label
                                   rate: (NSTextField *) rate rateUnits: (NSTextField *) rateUnits
                                  total: (NSTextField *) total totalUnits: (NSTextField *) totalUnits {
    
    NSFont * font = [NSFont monospacedDigitSystemFontOfSize: [NSFont smallSystemFontSize] weight: NSFontWeightRegular];
    NSArray * fields = @[label, rate, rateUnits, total, totalUnits];
    NSTextField * field;
    NSEnumerator * e = [fields objectEnumerator];
    while (  (field = [e nextObject])  ) {
        [field setFont: font];
        [field setTextColor: [NSColor labelColor]];
        [field setTranslatesAutoresizingMaskIntoConstraints: NO];
    }
    [label      setTextColor: [NSColor secondaryLabelColor]];
    [total      setTextColor: [NSColor secondaryLabelColor]];
    [totalUnits setTextColor: [NSColor secondaryLabelColor]];
    [label      setAlignment: NSTextAlignmentNatural];
    [rate       setAlignment: NSTextAlignmentRight];
    [total      setAlignment: NSTextAlignmentRight];
    [rateUnits  setAlignment: NSTextAlignmentNatural];
    [totalUnits setAlignment: NSTextAlignmentNatural];
    
    // Fixed widths, so the numbers do not move when they or their units change
    CGFloat numberWidth = [self widestOf: @[@"9.99", @"99.9", @"999"] font: font]; // The widest numbers -[VPNConnection setNumber:...] shows
    [NSLayoutConstraint activateConstraints: @[[[rate       widthAnchor] constraintEqualToConstant: numberWidth],
                                               [[total      widthAnchor] constraintEqualToConstant: numberWidth],
                                               [[rateUnits  widthAnchor] constraintEqualToConstant: [self widestOf: gRateUnits  font: font]],
                                               [[totalUnits widthAnchor] constraintEqualToConstant: [self widestOf: gTotalUnits font: font]]]];
    
    NSStackView * row = [[[NSStackView alloc] init] autorelease];
    [row setOrientation: NSUserInterfaceLayoutOrientationHorizontal];
    [row setSpacing: 3.0];
    [row addView: label      inGravity: NSStackViewGravityLeading];
    [row addView: rate       inGravity: NSStackViewGravityTrailing];
    [row addView: rateUnits  inGravity: NSStackViewGravityTrailing];
    [row addView: total      inGravity: NSStackViewGravityTrailing];
    [row addView: totalUnits inGravity: NSStackViewGravityTrailing];
    [row setCustomSpacing: 10.0 afterView: rateUnits];
    return row;
}

-(void) relayoutContent {
    
    // Icon, name and state in a row with the Connect or Disconnect button, and the traffic statistics in a rounded box
    // below. The controls are the ones from the nib (other code updates them), laid out again.
    NSView * contentView = [[self window] contentView];
    NSTextField * nameTF   = (NSTextField *) [configurationNameTFC controlView];
    NSTextField * statusTF = (NSTextField *) [statusTFC            controlView];
    NSArray * keep = @[nameTF, statusTF, animationIV, connectButton, disconnectButton,
                       inTF, inRateTF, inRateUnitsTF, inTotalTF, inTotalUnitsTF,
                       outTF, outRateTF, outRateUnitsTF, outTotalTF, outTotalUnitsTF];
    NSView * view;
    NSEnumerator * e = [keep objectEnumerator];
    while (  (view = [e nextObject])  ) {
        [[view retain] autorelease];
        [view removeFromSuperview];
        [view setTranslatesAutoresizingMaskIntoConstraints: NO];
    }
    NSVisualEffectView * background = nil;
    e = [[[[contentView subviews] copy] autorelease] objectEnumerator];
    while (  (view = [e nextObject])  ) {
        if (  [view isKindOfClass: [NSVisualEffectView class]]  ) {
            background = (NSVisualEffectView *) view;
        } else {
            [view removeFromSuperview];
        }
    }
    
    [nameTF   setFont: [NSFont systemFontOfSize: [NSFont systemFontSize] weight: NSFontWeightSemibold]];
    [nameTF   setTextColor: [NSColor labelColor]];
    [nameTF   setAlignment: NSTextAlignmentNatural];
    [statusTF setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize]]];
    [statusTF setAlignment: NSTextAlignmentNatural];
    [[nameTF cell] setLineBreakMode: NSLineBreakByTruncatingTail];
    
    NSStackView * text = [NSStackView stackViewWithViews: @[nameTF, statusTF]];
    [text setOrientation: NSUserInterfaceLayoutOrientationVertical];
    [text setAlignment: NSLayoutAttributeLeading];
    [text setSpacing: 1.0];
    
    // A long name is truncated: the window must not grow, because it was positioned (near the menu bar icon, or stacked
    // with other status windows) for its size
    NSTextField * label;
    NSEnumerator * labelEnum = [@[nameTF] objectEnumerator];
    while (  (label = [labelEnum nextObject])  ) {
        [[label cell] setLineBreakMode: NSLineBreakByTruncatingTail];
        [[label cell] setWraps: NO];
        [label setContentCompressionResistancePriority: NSLayoutPriorityDefaultLow forOrientation: NSLayoutConstraintOrientationHorizontal];
        [label setContentHuggingPriority: NSLayoutPriorityDefaultLow forOrientation: NSLayoutConstraintOrientationHorizontal];
    }
    [text setContentCompressionResistancePriority: NSLayoutPriorityDefaultLow forOrientation: NSLayoutConstraintOrientationHorizontal];
    
    // The window is sized and positioned once, so it cannot grow when the state changes. To keep it narrow, the state
    // can use more than one line: the text is as wide as there is room for next to the icon and the button (or as wide
    // as the name, up to a limit), and there is room for as many lines as the longest state (with a connection time)
    // needs.
    NSArray * states = @[@"ADD_ROUTES", @"ASSIGN_IP", @"AUTH", @"CONNECTED", @"CONNECTING", @"DISCONNECTING", @"EXITING",
                         @"GET_CONFIG", @"NETWORK_ACCESS", @"PASSWORD_WAIT", @"PRIVATE_KEY_WAIT", @"RECONNECTING", @"RESOLVE",
                         @"SLEEP", @"TCP_CONNECT", @"UDP_CONNECT", @"WAIT"];
    NSMutableArray * texts = [NSMutableArray arrayWithCapacity: [states count]];
    NSString * state;
    NSEnumerator * stateEnum = [states objectEnumerator];
    while (  (state = [stateEnum nextObject])  ) {
        [texts addObject: [NSString stringWithFormat: @"%@ 00:00:00", localizeNonLiteral(state, @"Connection status")]];
    }
    // (awakeFromNib sets the same titles later; they are needed now to know how wide the buttons are)
    [connectButton    setControlSize: NSControlSizeSmall];
    [disconnectButton setControlSize: NSControlSizeSmall];
    [connectButton    setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize]]];
    [disconnectButton setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize]]];
    [connectButton    setTitle: NSLocalizedString(@"Connect",    @"Button")];
    [disconnectButton setTitle: NSLocalizedString(@"Disconnect", @"Button")];
    CGFloat buttonWidth = MAX([connectButton fittingSize].width, [disconnectButton fittingSize].width);
    CGFloat textWidth = MAX(260.0 - 32.0 - 10.0 - 10.0 - buttonWidth,                                     // Room in the narrowest window
                            MIN([self widestOf: @[(localName ? localName : @"")] font: [nameTF font]], 250.0)); // The name, up to a limit
    [[[text widthAnchor] constraintEqualToConstant: textWidth] setActive: YES];
    // Room for as many lines (up to three) as the longest state needs at that width
    CGFloat neededHeight = 0.0;
    NSString * stateText;
    NSEnumerator * textEnum = [texts objectEnumerator];
    while (  (stateText = [textEnum nextObject])  ) {
        NSRect bounds = [stateText boundingRectWithSize: NSMakeSize(textWidth - 4.0, 10000.0)
                                                options: NSStringDrawingUsesLineFragmentOrigin
                                             attributes: @{NSFontAttributeName: [statusTF font]}];
        neededHeight = MAX(neededHeight, ceil(NSHeight(bounds)));
    }
    CGFloat lineHeight = ceil([[statusTF font] ascender] - [[statusTF font] descender] + [[statusTF font] leading]);
    NSInteger lines = MIN(3, MAX(1, (NSInteger) round(neededHeight / lineHeight)));
    [[statusTF cell] setWraps: YES];
    [[statusTF cell] setLineBreakMode: NSLineBreakByWordWrapping];
    [statusTF setMaximumNumberOfLines: lines];
    [statusTF setPreferredMaxLayoutWidth: textWidth];
    // (The height is reserved below, on the row, so a short state is centered vertically with the name)
    CGFloat reservedTextHeight = ceil([[nameTF font] ascender] - [[nameTF font] descender] + [[nameTF font] leading]) + 1.0 + (lines * lineHeight) + 2.0;
    
    [animationIV setImageScaling: NSImageScaleProportionallyUpOrDown];
    NSStackView * header = [[[NSStackView alloc] init] autorelease];
    [header setOrientation: NSUserInterfaceLayoutOrientationHorizontal];
    [header setAlignment: NSLayoutAttributeCenterY];
    [header setSpacing: 10.0];
    [header addView: animationIV      inGravity: NSStackViewGravityLeading];
    [header addView: text             inGravity: NSStackViewGravityLeading];
    [header addView: connectButton    inGravity: NSStackViewGravityTrailing];
    [header addView: disconnectButton inGravity: NSStackViewGravityTrailing];
    [header setClippingResistancePriority: NSLayoutPriorityDefaultLow forOrientation: NSLayoutConstraintOrientationHorizontal];
    [[[header heightAnchor] constraintGreaterThanOrEqualToConstant: reservedTextHeight] setActive: YES];
    
    NSStackView * inRow  = [self statisticsRowWithLabel: inTF  rate: inRateTF  rateUnits: inRateUnitsTF  total: inTotalTF  totalUnits: inTotalUnitsTF];
    NSStackView * outRow = [self statisticsRowWithLabel: outTF rate: outRateTF rateUnits: outRateUnitsTF total: outTotalTF totalUnits: outTotalUnitsTF];
    NSStackView * rows = [NSStackView stackViewWithViews: @[inRow, outRow]];
    [rows setOrientation: NSUserInterfaceLayoutOrientationVertical];
    [rows setSpacing: 3.0];
    [rows setTranslatesAutoresizingMaskIntoConstraints: NO];
    NSBox * statisticsBox = [[[NSBox alloc] init] autorelease];
    [statisticsBox setBoxType: NSBoxCustom];
    [statisticsBox setTitlePosition: NSNoTitle];
    [statisticsBox setBorderWidth: 0.0];
    [statisticsBox setCornerRadius: 8.0];
    [statisticsBox setFillColor: [NSColor quaternaryLabelColor]];
    [statisticsBox setContentViewMargins: NSMakeSize(10.0, 6.0)];
    [statisticsBox setTranslatesAutoresizingMaskIntoConstraints: NO];
    [[statisticsBox contentView] addSubview: rows];
    NSView * boxContent = [statisticsBox contentView];
    
    NSStackView * card = [NSStackView stackViewWithViews: @[header, statisticsBox]];
    [card setOrientation: NSUserInterfaceLayoutOrientationVertical];
    [card setSpacing: 10.0];
    [card setTranslatesAutoresizingMaskIntoConstraints: NO];
    [contentView addSubview: card];
    
    [NSLayoutConstraint activateConstraints: @[[[animationIV widthAnchor]      constraintEqualToConstant: 32.0],
                                               [[animationIV heightAnchor]     constraintEqualToConstant: 32.0],
                                               [[header widthAnchor]           constraintEqualToAnchor: [card widthAnchor]],
                                               [[statisticsBox widthAnchor]    constraintEqualToAnchor: [card widthAnchor]],
                                               [[inRow  widthAnchor]           constraintEqualToAnchor: [rows widthAnchor]],
                                               [[outRow widthAnchor]           constraintEqualToAnchor: [rows widthAnchor]],
                                               [[rows topAnchor]               constraintEqualToAnchor: [boxContent topAnchor]],
                                               [[rows bottomAnchor]            constraintEqualToAnchor: [boxContent bottomAnchor]],
                                               [[rows leadingAnchor]           constraintEqualToAnchor: [boxContent leadingAnchor]],
                                               [[rows trailingAnchor]          constraintEqualToAnchor: [boxContent trailingAnchor]],
                                               [[card topAnchor]               constraintEqualToAnchor: [contentView topAnchor]      constant: 12.0],
                                               [[card leadingAnchor]           constraintEqualToAnchor: [contentView leadingAnchor]  constant: 14.0],
                                               [[card trailingAnchor]          constraintEqualToAnchor: [contentView trailingAnchor] constant: -14.0],
                                               [[card bottomAnchor]            constraintEqualToAnchor: [contentView bottomAnchor]   constant: -12.0],
                                               [[card widthAnchor]             constraintGreaterThanOrEqualToConstant: 260.0]]];
    
    // The window is as big as the new layout
    [contentView layoutSubtreeIfNeeded];
    NSSize size = [card fittingSize];
    NSRect frame = [[self window] frame];
    CGFloat newHeight = size.height + 24.0;
    frame.origin.y += NSHeight(frame) - newHeight;
    frame.size = NSMakeSize(MAX(size.width + 28.0, 288.0), newHeight);
    [[self window] setFrame: frame display: NO];
    (void) background;
}

-(void) modernizeWindow {
    
    // A card without a title bar (the title is not shown) on a native material, instead of a utility panel with a title bar.
    // The window keeps the size of its content, so the stacking and positioning of status windows does not change.
    NSWindow * window = [self window];
    NSRect contentRect = [window contentRectForFrameRect: [window frame]];
    [window setStyleMask: [window styleMask] | NSWindowStyleMaskFullSizeContentView];
    [window setTitlebarAppearsTransparent: YES];
    [window setTitleVisibility: NSWindowTitleHidden];
    [[window standardWindowButton: NSWindowCloseButton]       setHidden: YES];
    [[window standardWindowButton: NSWindowMiniaturizeButton] setHidden: YES];
    [[window standardWindowButton: NSWindowZoomButton]        setHidden: YES];
    [window setFrame: contentRect display: NO];
    
    NSView * contentView = [window contentView];
    NSVisualEffectView * background = [[[NSVisualEffectView alloc] initWithFrame: [contentView bounds]] autorelease];
    [background setMaterial: NSVisualEffectMaterialPopover];
    [background setBlendingMode: NSVisualEffectBlendingModeBehindWindow];
    [background setState: NSVisualEffectStateActive];
    [background setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];
    [contentView addSubview: background positioned: NSWindowBelow relativeTo: nil];
    
    [statusTFC setDrawsBackground: NO];
    
    [self relayoutContent];
}

-(void) restore
{
    if (  closedByRedDot  ) {
        return;
    }
    
    closeAfterFadeOutClosedTheWindow = FALSE;
    [self enableOrDisableButtons];
    [self startMouseTracking];
    [self setSizeAndPosition];
    [[self window] display];
    [self showWindow: self];
    [self fadeIn];
}

// Sets the frame for the window so the entire title (localized name of connection) is visible
// and the window is in the upper-right corner of the screen
-(void) setSizeAndPosition
{
    if (  originalWidth == 0.0  ) {
        originalWidth = [NSWindow minFrameWidthWithTitle: [[self window] title] styleMask: NSHUDWindowMask];
    }

    NSWindow * panel = [self window];
    NSRect panelFrame = [panel frame];
    
    if (  [panel titleVisibility] == NSWindowTitleHidden  ) {
        // The window is as big as its layout needs (see -relayoutContent)
        NSView * contentView = [panel contentView];
        [contentView layoutSubtreeIfNeeded];
        NSSize fittingSize = [contentView fittingSize];
        panelFrame.size = NSMakeSize(MAX(fittingSize.width, 288.0), fittingSize.height);
    }
    
    // Adjust the width of the window to fit the complete title
    // But never make it smaller than the original window, or larger than will fit on the screen
    NSRect screen = [[[NSScreen screens] objectAtIndex: [gMC statusScreenIndex]] visibleFrame];   // Use the screen on which we are displaying status windows
    if (  currentWidth == 0.0  ) {
        currentWidth = [NSWindow minFrameWidthWithTitle: [panel title] styleMask: NSHUDWindowMask];
    }
    
    CGFloat newWidth = [NSWindow minFrameWidthWithTitle: localName styleMask: NSHUDWindowMask];
    if (  newWidth < originalWidth  ) {
        newWidth = originalWidth;
    }
    CGFloat sizeChange = (CGFloat) newWidth - currentWidth;
    if (   (sizeChange > 0.0)
        && ([panel titleVisibility] != NSWindowTitleHidden)  )  { // (When the title is not shown, the layout sized the window)
        if (  newWidth < (screen.size.width - 20.0)  ) {
            panelFrame.size.width = newWidth;
        } else {
            panelFrame.size.width = screen.size.width;
        }
    }
    
    // The panels are stacked top to bottom, right to left, like this:
    //
    //              10         5         0
    //              11         6         1
    //              12         7         2
    //              13         8         3
    //              14         9         4
    //
    // But the number in each column and row needs to be calculated.
    
    double verticalScreenSize = screen.size.height - 10.0;  // Size we can use on the screen
    NSUInteger screensWeCanStackVertically = (unsigned) (verticalScreenSize / (panelFrame.size.height + 5));
    if (  screensWeCanStackVertically < 1  ) {
        screensWeCanStackVertically = 1;
    } else if (  screensWeCanStackVertically > NUMBER_OF_STATUS_SCREEN_POSITIONS  ) {
        NSLog(@"Limiting screensWeCanStackVertically to %ld (was %ld)", (long) NUMBER_OF_STATUS_SCREEN_POSITIONS, (long) screensWeCanStackVertically);
        screensWeCanStackVertically = NUMBER_OF_STATUS_SCREEN_POSITIONS;
    }
    
    double horizontalScreenSize = screen.size.width - 10.0;  // Size we can use on the screen
    NSUInteger screensWeCanStackHorizontally = (unsigned) (horizontalScreenSize / (panelFrame.size.width + 5));
    if (  screensWeCanStackHorizontally < 1  ) {
        screensWeCanStackHorizontally = 1;
    } else if (  screensWeCanStackHorizontally > NUMBER_OF_STATUS_SCREEN_POSITIONS  ) {
        NSLog(@"Limiting screensWeCanStackHorizontally to %ld (was %ld)", (long) NUMBER_OF_STATUS_SCREEN_POSITIONS, (long) screensWeCanStackHorizontally);
        screensWeCanStackHorizontally = NUMBER_OF_STATUS_SCREEN_POSITIONS;
    }
    
    // Make sure we can keep track of all of the screen positions we stack. (We can keep track of a maximum of NUMBER_OF_STATUS_SCREEN_POSITIONS positions.)
    // Note that no overflow occurs in the following multiplication because each operand is <= NUMBER_OF_STATUS_SCREEN_POSITIONS, which is a realtively small number.
    if (  (screensWeCanStackVertically * screensWeCanStackHorizontally) > NUMBER_OF_STATUS_SCREEN_POSITIONS  ) {
        NSUInteger newValue = NUMBER_OF_STATUS_SCREEN_POSITIONS / screensWeCanStackVertically;
        NSLog(@"Limiting screensWeCanStackHorizontally to %ld (was %ld) because screensWeCanStackVertically is %ld", (long) newValue, (long) screensWeCanStackHorizontally, (long) screensWeCanStackVertically);
        screensWeCanStackHorizontally = newValue;
    }
    
    // Figure out what position number to try to get:
    NSUInteger startPositionNumber;
    if (   [gMC mouseIsInsideAnyView]
        && (   [gTbDefaults boolForKey: @"placeIconInStandardPositionInStatusBar"] )
        && ( ! [gTbDefaults boolForKey: @"doNotShowNotificationWindowOnMouseover"] )
        && ( ! [gTbDefaults boolForKey: @"doNotShowNotificationWindowBelowIconOnMouseover"] )  ) {
        
        MainIconView * view = [gMC ourMainIconView];
		NSPoint iconOrigin  = [[view window] convertBaseToScreen: NSMakePoint(0.0, 0.0)];
        
        for ( startPositionNumber=0; startPositionNumber<screensWeCanStackVertically * screensWeCanStackHorizontally; startPositionNumber+=screensWeCanStackVertically ) {
            double horizontalOffset = (panelFrame.size.width  + 5.0) * ((startPositionNumber / screensWeCanStackVertically) % screensWeCanStackHorizontally);
            double panelOriginX = screen.origin.x + screen.size.width - panelFrame.size.width  - 10.0 - horizontalOffset; 
            if (  panelOriginX < iconOrigin.x  ) {
                break;
            }
        }
        if (  startPositionNumber >= screensWeCanStackVertically * screensWeCanStackHorizontally  ) {
            startPositionNumber = 0;
        }
    } else {
        startPositionNumber = 0;
    }
    
    // Put the window in the lowest available position number equal to or greater than startPositionNumber, wrapping around
    // to position 0, 1, 2, etc. if we didn't start at position 0

    statusScreenPosition = NSNotFound;
    
    pthread_mutex_lock( &statusScreenPositionsInUseMutex );
    
    NSUInteger positionNumber;
    for (  positionNumber=startPositionNumber; positionNumber<NUMBER_OF_STATUS_SCREEN_POSITIONS; positionNumber++  ) {
        if (  statusScreenPositionsInUse[positionNumber] == 0  ) {
            break;
        }
    }
    
    if (  positionNumber < NUMBER_OF_STATUS_SCREEN_POSITIONS  ) {
        statusScreenPositionsInUse[positionNumber] = 1;
        statusScreenPosition = positionNumber;
    } else {
        if (  startPositionNumber != 0  ) {
            for (  positionNumber=0; positionNumber<startPositionNumber; positionNumber++  ) {
                if (  statusScreenPositionsInUse[positionNumber] == 0  ) {
                    break;
                }
            }
            
            if (  positionNumber < startPositionNumber  ) {
                statusScreenPositionsInUse[positionNumber] = 1;
                statusScreenPosition = positionNumber;
            }
        }
    }
    
    pthread_mutex_unlock( &statusScreenPositionsInUseMutex );

    // If all positions are filled, wrap back around to startPositionNumber and put it on top of another window but offset by (10, 10)
    double screenOverlapVerticalOffset;
    double screenOverlapHorizontalOffset;
    
    if (  statusScreenPosition == NSNotFound  ) {
        statusScreenPosition = startPositionNumber;
        screenOverlapVerticalOffset   = 10.0;
        screenOverlapHorizontalOffset = 10.0;
    } else {
        screenOverlapVerticalOffset   = 0.0;
        screenOverlapHorizontalOffset = 0.0;
    }
    
    double verticalOffset   = (panelFrame.size.height + 5.0) *  (positionNumber % screensWeCanStackVertically);
    double horizontalOffset = (panelFrame.size.width  + 5.0) * ((positionNumber / screensWeCanStackVertically) % screensWeCanStackHorizontally);
    
    double verticalPosition   = screen.origin.y + screen.size.height - panelFrame.size.height - 10.0 - verticalOffset   + screenOverlapVerticalOffset;
    double horizontalPosition = screen.origin.x + screen.size.width  - panelFrame.size.width  - 10.0 - horizontalOffset + screenOverlapHorizontalOffset;
    
    // Put the window in the upper-right corner of the screen but offset in X and Y by the position number    
    NSRect onScreenRect = NSMakeRect((float)horizontalPosition, (float)verticalPosition, panelFrame.size.width, panelFrame.size.height);
    
    [panel setFrame: onScreenRect display: YES];
    currentWidth = onScreenRect.size.width;
}

-(void) awakeFromNib
{
    [self modernizeWindow];
    [self setStatus: status forName: name connectedSince: connectedSince];

    [inTFC  setTitle: NSLocalizedString(@"In:", @"Window text")];
    [outTFC setTitle: NSLocalizedString(@"Out:", @"Window text")];
    [self adjustWidthsToLargerOf: inTF and: outTF];
    
    [self setUpUnits: inRateUnitsTF  cell: inRateUnitsTFC  and: outRateUnitsTF  cell: outRateUnitsTFC  array: gRateUnits];
    [self setUpUnits: inTotalUnitsTF cell: inTotalUnitsTFC and: outTotalUnitsTF cell: outTotalUnitsTFC array: gTotalUnits];
    
	[connectButton    setTitle: NSLocalizedString(@"Connect",    @"Button")];
	[disconnectButton setTitle: NSLocalizedString(@"Disconnect", @"Button")];
	
	// Remember frame of disconnect button so we can shift it left or right
	CGFloat oldDisconnectWidth = [disconnectButton frame].size.width;
	
	// Size both buttons to the max size of either button
	[connectButton    sizeToFit];
	[disconnectButton sizeToFit];
	CGFloat cWidth = [connectButton    frame].size.width;
	CGFloat dWidth = [disconnectButton frame].size.width;
	if (  cWidth > dWidth  ) {
		NSRect f = [disconnectButton frame];
		f.size.width = cWidth;
		f.origin.x = f.origin.x + (oldDisconnectWidth - cWidth);
		[disconnectButton setFrame: f];
	} else if (  dWidth > cWidth) {
		NSRect f = [connectButton frame];
		f.size.width = dWidth;
		[connectButton setFrame: f];
		f = [disconnectButton frame];
		f.origin.x = f.origin.x + (oldDisconnectWidth - dWidth);
		[disconnectButton setFrame: f];
	}
	
    [self setSizeAndPosition];
    [[self window] setTitle: NSLocalizedString(@"Tunnelblick", @"Window title")];
    
    NSView * windowView = [[self window] contentView];
    NSRect trackingFrame = [windowView frame];
    trackingFrame.size.height += 1000.0;    // Include the title bar in the tracking rectangle (will be clipped)
    
    trackingRectTag = [windowView addTrackingRect: trackingFrame
                                            owner: self
                                         userData: nil
                                     assumeInside: NO];
    
    [self showWindow: self];
    [self initialiseAnim];
	haveLoadedFromNib = TRUE;
    [self fadeIn];
}

-(CGFloat) adjustWidthsToLargerOf: (NSTextField *) tf1 and: (NSTextField *) tf2 {
    
    CGFloat widthBeforeAdjustment = [tf1 frame].size.width;
    CGFloat adjustment;
    [tf1 sizeToFit];
    [tf2 sizeToFit];
    NSRect size1 = [tf1 frame];
    NSRect size2 = [tf2 frame];
    
    if (  size1.size.width > size2.size.width  ) {
        adjustment = size1.size.width - widthBeforeAdjustment; 
        size2.size.width = size1.size.width;
    } else {
        adjustment = size2.size.width - widthBeforeAdjustment; 
        size1.size.width = size2.size.width;
    }
	
    size1.origin.x = size1.origin.x - adjustment;
    size2.origin.x = size2.origin.x - adjustment;
	
	[tf1 setFrame: size1];
	[tf2 setFrame: size2];
    
	return adjustment;
}

-(void) setUpUnits: (NSTextField *) tf1 cell: (NSTextFieldCell *) tfc1
               and: (NSTextField *) tf2 cell: (NSTextFieldCell *) tfc2
             array: (NSArray *) array {
    
    // Find the maximum width of the units
	NSRect oldFrame = [tf1 frame];	// Save original size
    CGFloat maxWidth = 0.0;
    NSString * unitsName;
    NSEnumerator * e = [array objectEnumerator];
    while (  (unitsName = [e nextObject])  ) {
        [tfc1 setTitle: unitsName];
        [tf1 sizeToFit];
        NSRect f = [tf1 frame];
        if (  f.size.width > maxWidth  ) {
            maxWidth = f.size.width;
        }
    }
	[tf1 setFrame: oldFrame];	// Restore original size
    
    // Set the width of both text fields to the maximum
	BOOL rtf = [UIHelper languageAtLaunchWasRTL];
	if (  rtf  ) {
		// RTL rates are right-justified, so we adjust the origin when we adjust the size
		
		NSRect f = [tf1 frame];
		CGFloat widthChange = maxWidth - f.size.width;
		f.size.width = maxWidth;
		f.origin.x -= widthChange;
		[tf1 setFrame: f];
		
		f = [tf2 frame];
		widthChange = maxWidth - f.size.width;
		f.size.width = maxWidth;
		f.origin.x -= widthChange;
		[tf2 setFrame: f];
	} else {
		NSRect f = [tf1 frame];
		f.size.width = maxWidth;
		[tf1 setFrame: f];
		f = [tf2 frame];
		f.size.width = maxWidth;
		[tf2 setFrame: f];
	}
	
    // Set the text fields to the first entry in the array
    [tfc1 setTitle: [array objectAtIndex: 0]];
    [tfc2 setTitle: [array objectAtIndex: 0]];
}

-(void) initialiseAnim
{
    if (  theAnim == nil  ) {
        unsigned i;
        // theAnim is an NSAnimation instance variable
        theAnim = [[NSAnimation alloc] initWithDuration:2.0
                                         animationCurve:NSAnimationLinear];
        [theAnim setFrameRate:7.0];
        [theAnim setDelegate:self];
        
        for (i=1; i<=[[gMC largeAnimImages] count]; i++) {
            NSAnimationProgress p = ((float)i)/((float)[[gMC largeAnimImages] count]);
            [theAnim addProgressMark: p];
        }
		
        [theAnim setAnimationBlockingMode:  NSAnimationNonblocking];
		
        if (  [status isEqualToString:@"EXITING"]  ) {
            [animationIV setImage: [gMC largeMainImage]];
        } else if (  [status isEqualToString:@"CONNECTED"]  ) {
            [animationIV setImage: [gMC largeConnectedImage]];
		} else {
			[theAnim startAnimation];
		}
    }
}

-(void)animationDidEnd:(NSAnimation*)animation
{
	if (  animation != theAnim  ) {
		return;
	}
	
	if (   (![status isEqualToString:@"EXITING"])
        && (![status isEqualToString:@"CONNECTED"])) {
		[theAnim startAnimation];
	}
}

-(void)animation:(NSAnimation *)animation didReachProgressMark:(NSAnimationProgress)progress
{
	if (animation == theAnim) {
        [animationIV performSelectorOnMainThread:@selector(setImage:) withObject:[[gMC largeAnimImages] objectAtIndex:(unsigned) lround(progress * [[gMC largeAnimImages] count]) - 1] waitUntilDone:YES];
	}
}

-(void) fadeIn
{
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    [self startMouseTracking];
    
	if (  ! isOpen  ) {
        if (  closedByRedDot  ) {
            return;
        }
        NSWindow * window = [self window];
		
        [window makeKeyAndOrderFront: self];
        
        if (   [window respondsToSelector: @selector(animator)]
            && [[window animator] respondsToSelector: @selector(setAlphaValue:)]  ) {
            [[window animator] setAlphaValue: 1.0];
        }
		
        isOpen = YES;
    }
}

-(void) fadeOut
{
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
	if (  isOpen  ) {
        NSWindow * window = [self window];
        
        if (   [window respondsToSelector: @selector(animator)]
            && [[window animator] respondsToSelector: @selector(setAlphaValue:)]  ) {
            [[window animator] setAlphaValue:0.0];
        } else {
            [window close];
        }

		isOpen = NO;
        
        if (  statusScreenPosition != NSNotFound  ) {
            pthread_mutex_lock( &statusScreenPositionsInUseMutex );
            statusScreenPositionsInUse[statusScreenPosition] = 0;
            statusScreenPosition = NSNotFound;
            pthread_mutex_unlock( &statusScreenPositionsInUseMutex );
        }
        
        NSTimer * timer = [NSTimer scheduledTimerWithTimeInterval: (NSTimeInterval) 0.2   // Wait for the window to become transparent
                                                           target: self
                                                         selector: @selector(closeAfterFadeOutHandler:)
                                                         userInfo: nil
                                                          repeats: NO];
        [timer tbSetTolerance: -1.0];
	}
    
    [self stopMouseTracking];
}

-(void) closeAfterFadeOutHandler: (NSTimer *) timer
{
	(void) timer;
	
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
	[self performSelectorOnMainThread: @selector(closeAfterFadeOut:) withObject: nil waitUntilDone: NO];
}

-(void) closeAfterFadeOut: (NSDictionary *) dict
{
	(void) dict;
	
    if ( [[self window] alphaValue] == 0.0 ) {
        closeAfterFadeOutClosedTheWindow = TRUE;
        [[self window] close];
    } else {
        NSTimer * timer = [NSTimer scheduledTimerWithTimeInterval: (NSTimeInterval) 0.2   // Wait for the window to become transparent
                                                           target: self
                                                         selector: @selector(closeAfterFadeOutHandler:)
                                                         userInfo: nil
                                                          repeats: NO];
        [timer tbSetTolerance: -1.0];
    }

}

- (IBAction) connectButtonWasClicked: sender
{
    [sender setEnabled: NO];
	[gMC statusWindowController: self
                          finishedWithChoice: statusWindowControllerConnectChoice
                              forDisplayName: [self name]];
}

- (IBAction) disconnectButtonWasClicked: sender
{
    [sender setEnabled: NO];
	[gMC statusWindowController: self
                          finishedWithChoice: statusWindowControllerDisconnectChoice
                              forDisplayName: [self name]];
}

- (void) dealloc {
	
    [self stopMouseTracking];
    
    [gMC mouseExitedStatusWindow: self event: nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver: self]; 
	
	[name           release]; name           = nil;
    [localName      release]; localName      = nil;
	[status         release]; status         = nil;
	[connectedSince release]; connectedSince = nil;
	[theAnim        release]; theAnim        = nil;
	[delegate       release]; delegate       = nil;
	
	[super dealloc];
}

- (NSString *) description
{
    return [NSString stringWithFormat:@"%@", [self class]];
}

-(NSTextFieldCell *) statusTFC
{
    return [[statusTFC retain] autorelease];
}

-(NSTextFieldCell *) configurationNameTFC
{
    return [[configurationNameTFC retain] autorelease];
}

-(void) setStatus: (NSString *) theStatus forName: (NSString *) theName connectedSince: (NSString *) theTime
{
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
    [self setName: theName]; // Also sets "localName"
    [self setStatus: theStatus];
    [self setConnectedSince: (  (   theTime
                                 && ( ! [theStatus isEqualToString: @"EXITING"])   )
                              ? [NSString stringWithFormat: @" %@", theTime]
                              : @"")];
    
    [configurationNameTFC setStringValue: localName];
    [statusTFC            setStringValue: [NSString stringWithFormat: @"%@%@",
                                           localizeNonLiteral(theStatus, @"Connection status"),
                                           [self connectedSince]]];
    
    if (   [theStatus isEqualToString: @"EXITING"]  ) {
        [statusTFC            setTextColor: NSColor.secondaryLabelColor];
        [theAnim stopAnimation];
        [animationIV setImage: [gMC largeMainImage]];
        
    } else if (  [theStatus isEqualToString: @"CONNECTED"]  ) {
        [statusTFC            setTextColor: NSColor.systemGreenColor];
        [theAnim stopAnimation];
        [animationIV setImage: [gMC largeConnectedImage]];

    } else {
        [statusTFC            setTextColor: NSColor.systemOrangeColor];
        [theAnim startAnimation];
    }
	
	[self enableOrDisableButtons];
}

-(id) delegate
{
    return [[delegate retain] autorelease];
}

-(NSString *) name {
    return [[name retain] autorelease];
}

-(void) setName:(NSString *)newValue {
    if (  ! [name isEqualToString: newValue]  ) {
        [newValue retain];
        [name release];
        name = newValue;
        [self setLocalName: [delegate localizedName]];
    }
}

// *******************************************************************************************
// Getters & Setters

TBSYNTHESIZE_OBJECT(retain, NSString *, localName,      setLocalName)
TBSYNTHESIZE_OBJECT(retain, NSString *, status,         setStatus)
TBSYNTHESIZE_OBJECT(retain, NSString *, connectedSince, setConnectedSince)

-(BOOL) haveLoadedFromNib {
    return haveLoadedFromNib;
}

TBSYNTHESIZE_NONOBJECT_GET(BOOL, isOpen)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *, inTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *, inRateTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *, inRateUnitsTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *, inTotalTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *, inTotalUnitsTFC)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *, outTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *, outRateTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *, outRateUnitsTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *, outTotalTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *, outTotalUnitsTFC)

TBSYNTHESIZE_NONOBJECT(BOOL, closedByRedDot, setClosedByRedDot)

// Event Handlers
-(void) mouseEntered: (NSEvent *) theEvent {
    // Event handler; NOT on MainThread
    // Mouse entered the tracking area of the Tunnelblick icon

	[super mouseEntered: theEvent];
    [gMC mouseEnteredStatusWindow: self event: theEvent];
}

-(void) mouseExited: (NSEvent *) theEvent {
    // Event handler; NOT on MainThread
    // Mouse exited the tracking area of the Tunnelblick icon
    
	[super mouseExited: theEvent];
    [gMC mouseExitedStatusWindow: self event: theEvent];
}

-(void) NSWindowWillCloseNotification: (NSNotification *) n {
    // Event handler; NOT on MainThread
    
	if (  [n object] == [self window]  ) {
		[gMC mouseExitedStatusWindow: self event: nil];
	}
}

@end
