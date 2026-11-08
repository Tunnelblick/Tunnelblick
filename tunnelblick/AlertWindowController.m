/*
 * Copyright 2014, 2015, 2018 Jonathan Bullard
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

#import "AlertWindowController.h"

#import "defines.h"
#import "helper.h"
#import "sharedRoutines.h"

#import "MenuController.h"
#import "TBButton.h"
#import "TBUserDefaults.h"
#import "UIHelper.h"

extern MenuController  * gMC;
extern TBUserDefaults  * gTbDefaults;

@implementation AlertWindowController


TBSYNTHESIZE_OBJECT(retain, NSString *,			  headline,			      setHeadline)
TBSYNTHESIZE_NONOBJECT(double,                    initialPercentage,      setInitialPercentage)
TBSYNTHESIZE_OBJECT(retain, NSString *,			  message,			      setMessage)
TBSYNTHESIZE_OBJECT(retain, NSAttributedString *, messageAS,		      setMessageAS)
TBSYNTHESIZE_OBJECT(retain, NSString *,			  preferenceToSetTrue,    setPreferenceToSetTrue)
TBSYNTHESIZE_OBJECT(retain, NSString *,			  preferenceName,         setPreferenceName)
TBSYNTHESIZE_OBJECT(retain, id,					  preferenceValue,        setPreferenceValue)
TBSYNTHESIZE_OBJECT(retain, NSString *,			  checkboxTitle,          setCheckboxTitle)
TBSYNTHESIZE_OBJECT(retain, NSAttributedString *, checkboxInfoTitle,      setCheckboxInfoTitle)
TBSYNTHESIZE_NONOBJECT(BOOL,                      checkboxIsChecked,      setCheckboxIsChecked)

TBSYNTHESIZE_OBJECT(retain, id,                   responseTarget,          setResponseTarget)
TBSYNTHESIZE_NONOBJECT(SEL,                       defaultResponseSelector, setDefaultResponseSelector)
TBSYNTHESIZE_NONOBJECT(SEL,                       alternateResponseSelector,setAlternateResponseSelector)
TBSYNTHESIZE_NONOBJECT(SEL,                       otherResponseSelector,   setOtherResponseSelector)
TBSYNTHESIZE_NONOBJECT(SEL,                       windowWillCloseSelector, setWindowWillCloseSelector)
TBSYNTHESIZE_OBJECT(retain, NSString *,           defaultButtonTitle,      setDefaultButtonTitle)
TBSYNTHESIZE_OBJECT(retain, NSString *,           alternateButtonTitle,    setAlternateButtonTitle)
TBSYNTHESIZE_OBJECT(retain, NSString *,           otherButtonTitle,        setOtherButtonTitle)

TBSYNTHESIZE_OBJECT_GET(retain, NSImageView     *, iconIV)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextField     *, headlineTF)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *, headlineTFC)

TBSYNTHESIZE_OBJECT_GET(retain, NSScrollView    *, messageSV)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextView      *, messageTV)
TBSYNTHESIZE_OBJECT_GET(retain, NSProgressIndicator *, progressInd)


TBSYNTHESIZE_OBJECT_GET(retain, TBButton        *, doNotWarnAgainCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton        *, defaultButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton        *, alternateButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton        *, otherButton)

-(id) init {
    self = [super initWithWindowNibName: [UIHelper appendRTLIfRTLLanguage: @"AlertWindow"]];
    if (  ! self  ) {
        return nil;
    }

    [self retain];		// Retain ourself. windowWillClose will release ourself.
    return self;
}

-(void) dealloc {

    [headline			    release]; headline				 = nil;
    [message			    release]; message				 = nil;
    [messageAS			    release]; messageAS				 = nil;
    [preferenceToSetTrue    release]; preferenceToSetTrue	 = nil;
    [preferenceName         release]; preferenceName         = nil;
    [preferenceValue        release]; preferenceValue        = nil;
    [checkboxTitle          release]; checkboxTitle			 = nil;
    [checkboxInfoTitle      release]; checkboxInfoTitle		 = nil;
    [responseTarget         release]; responseTarget         = nil;
    [defaultButtonTitle     release]; defaultButtonTitle     = nil;
    [alternateButtonTitle   release]; alternateButtonTitle   = nil;
    [otherButtonTitle       release]; otherButtonTitle       = nil;

    [super dealloc];
}

-(void) windowWillClose: (NSNotification *) notification {

    (void) notification;

    if (  [doNotWarnAgainCheckbox state] == NSOnState  ) {
        if (   preferenceToSetTrue
            && ( ! [preferenceToSetTrue hasSuffix: @"-NotAnActualPreference"] )  ) {
            [gTbDefaults setBool: TRUE forKey: preferenceToSetTrue];
        }

        if (   preferenceName
            && preferenceValue  ) {
            [gTbDefaults setObject: preferenceValue forKey: preferenceName];
        }

        [gMC recreateMenu];
    }

    if (  self.windowWillCloseSelector  ) {
        [self.responseTarget performSelectorOnMainThread: self.windowWillCloseSelector withObject: nil waitUntilDone: NO];
    }

    [self autorelease];
}

#define ALERT_BODY_WIDTH 360.0

-(void) setupHeadline {

    [headlineTF setStringValue: (  headline ? headline : @"")];
    [UIHelper setUpDialogHeadline: headlineTF width: ALERT_BODY_WIDTH];
}

-(void) setupProgressInd {

    [self.progressInd setMinValue: 0.0];
    [self.progressInd setMaxValue: 100.0];
    [self.progressInd setDoubleValue: self.initialPercentage];
    [self.progressInd setHidden: (self.initialPercentage == 0.0)];
    [[[self.progressInd widthAnchor] constraintEqualToConstant: ALERT_BODY_WIDTH] setActive: YES];
}

-(NSAttributedString *) messageAttributedString {

	NSString * msg = self.message;
	NSAttributedString * msgAS = (   msg
								  ? [[[NSAttributedString alloc] initWithString: msg
                                                                     attributes: @{NSFontAttributeName: [NSFont systemFontOfSize: [NSFont systemFontSize] - 1.0]}]
                                     autorelease]
								  : [self messageAS]);
	if (  ! msgAS  ) {
		msgAS = [[[NSAttributedString alloc] initWithString: NSLocalizedString(@"Program error, please see the Console log.", @"Window text")] autorelease];
		NSLog(@"AlertWindowController: no message or messageAS; stack trace: %@", NSThread.callStackSymbols);
	}

    NSMutableAttributedString * mutableAS = [[msgAS mutableCopy] autorelease];

    // Remove trailing linefeeds
    while (  [[mutableAS string] hasSuffix: @"\n"]  ) {
        [mutableAS deleteCharactersInRange: NSMakeRange([[mutableAS string] length] - 1, 1)];
    }

    // Show the text like other macOS alerts: in the system font, with the most-used size scaled to the alert's text size,
    // gray (uncolored) text in the label color, and without a background color, so it looks right in light and dark mode.
    // (Text from HTML has fixed colors for the appearance at the time it was created, and a background color.)
    useSystemFontInAttributedString(mutableAS);
    NSRange all = NSMakeRange(0, [mutableAS length]);
    NSCountedSet * sizes = [NSCountedSet set];
    [mutableAS enumerateAttribute: NSFontAttributeName inRange: all options: 0 usingBlock: ^(id value, NSRange range, BOOL * stop) {
        (void) stop;
        NSUInteger i;
        for (  i = 0; i < range.length; i++  ) {
            [sizes addObject: [NSNumber numberWithDouble: (  value ? [(NSFont *) value pointSize] : 0.0  )]];
        }
    }];
    CGFloat mostUsedSize = 0.0;
    NSUInteger mostUsedCount = 0;
    NSNumber * size;
    NSEnumerator * e = [sizes objectEnumerator];
    while (  (size = [e nextObject])  ) {
        if (  [sizes countForObject: size] > mostUsedCount  ) {
            mostUsedCount = [sizes countForObject: size];
            mostUsedSize  = [size doubleValue];
        }
    }
    CGFloat scale = (  (mostUsedSize > 0.0) ? (([NSFont systemFontSize] - 1.0) / mostUsedSize) : 1.0  );
    [mutableAS enumerateAttribute: NSFontAttributeName inRange: all options: 0 usingBlock: ^(id value, NSRange range, BOOL * stop) {
        (void) stop;
        if (  value  ) {
            NSFont * font = (NSFont *) value;
            [mutableAS addAttribute: NSFontAttributeName
                              value: [NSFont fontWithDescriptor: [font fontDescriptor] size: round([font pointSize] * scale)]
                              range: range];
        }
    }];
    [mutableAS enumerateAttribute: NSForegroundColorAttributeName inRange: all options: 0 usingBlock: ^(id value, NSRange range, BOOL * stop) {
        (void) stop;
        NSColor * rgb = [(NSColor *) value colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
        BOOL isGray = (   rgb
                       && (fabs([rgb redComponent]   - [rgb greenComponent]) < 0.05)
                       && (fabs([rgb greenComponent] - [rgb blueComponent])  < 0.05)  );
        if (   ( ! value )
            || isGray  ) {
            [mutableAS addAttribute: NSForegroundColorAttributeName value: [NSColor labelColor] range: range];
        }
    }];
    [mutableAS removeAttribute: NSBackgroundColorAttributeName range: all];

    return mutableAS;
}

-(void) setupMessageAndCheckbox {

    // The message is shown without a frame or background, as tall as it needs to be (up to half the screen height, then it scrolls)
    NSScrollView * sv = self.messageSV;
    NSTextView   * tv = self.messageTV;
    [sv setBorderType: NSNoBorder];
    [sv setDrawsBackground: NO];
    [sv setHasHorizontalScroller: NO];
    [tv setDrawsBackground: NO];
    [tv setTextContainerInset: NSZeroSize];
    [[tv textContainer] setLineFragmentPadding: 0.0];
    [[tv textContainer] setWidthTracksTextView: YES];
    // Size the scroll view before the text view, so a later resizing of the scroll view (and with it, autoresizing of
    // the text view) does not change the width the text was measured for
    [sv setFrameSize: NSMakeSize(ALERT_BODY_WIDTH, NSHeight([sv frame]))];
    [tv setMinSize: NSMakeSize(0.0, 0.0)];
    [tv setFrameSize: NSMakeSize([sv contentSize].width, NSHeight([tv frame]))];

    [[tv textStorage] setAttributedString: [self messageAttributedString]];
    [[tv layoutManager] ensureLayoutForTextContainer: [tv textContainer]];
    CGFloat textHeight = ceil(NSHeight([[tv layoutManager] usedRectForTextContainer: [tv textContainer]]));
    CGFloat maxHeight  = floor(NSHeight([[NSScreen mainScreen] visibleFrame]) / 2.0);
    [sv setHasVerticalScroller: (textHeight > maxHeight)];
    [NSLayoutConstraint activateConstraints: @[[[sv widthAnchor]  constraintEqualToConstant: ALERT_BODY_WIDTH],
                                               [[sv heightAnchor] constraintEqualToConstant: MIN(textHeight, maxHeight)]]];
    [tv scrollPoint: NSMakePoint(0.0, 0.0)];

	[self setupCheckbox];
}

-(void) setupCheckbox {

	if (   (   (! preferenceToSetTrue)
            || [preferenceToSetTrue hasSuffix: @"-NotAnActualPreference"]
            )
		&& ( ! (   preferenceName
				&& preferenceValue))) {
		[doNotWarnAgainCheckbox setHidden: TRUE];
		return;
	}
	
	NSAttributedString * infoTitle = (  checkboxInfoTitle
									  ? checkboxInfoTitle
									  : attributedStringFromHTML([NSString stringWithFormat:
															   NSLocalizedString(@"<p><strong>When checked</strong>, Tunnelblick will not show this warning again.</p>\n"
																				 @"<p><strong>When not checked</strong>, Tunnelblick will show this warning again.</p>\n",
																				 @"HTML info for the 'Do not warn about this again' checkbox.")]));
	NSString * checkboxText = (  checkboxTitle
							   ? checkboxTitle
							   : NSLocalizedString(@"Do not warn about this again", @"Checkbox"));
	
	[doNotWarnAgainCheckbox setTitle: checkboxText
						   infoTitle: infoTitle];
	
	[doNotWarnAgainCheckbox setState: (  checkboxIsChecked
									   ? NSOnState
									   : NSOffState)];
}

-(IBAction) defaultButtonWasClicked: (id)  sender {

    if (  defaultResponseSelector  ) {
        [self.responseTarget performSelectorOnMainThread: self.defaultResponseSelector withObject: nil waitUntilDone: NO];
        [self.progressInd setHidden: NO];
        [self.defaultButton setEnabled: NO];
        [self.alternateButton setEnabled: NO];
        [self.otherButton setEnabled: NO];
        return;
    }

    [self setWindowWillCloseSelector: NULL];
    [self.window close];
}

-(void) cancelOperation: (id) sender {

    // The Escape key closes the window, as its close button did (the window has no title bar buttons)
    (void) sender;
    [self.window close];
}

-(IBAction) alternateButtonWasClicked: (id)  sender {

    if (  alternateResponseSelector  ) {
        [self.responseTarget performSelectorOnMainThread: self.alternateResponseSelector withObject: nil waitUntilDone: NO];
    }
    [self setWindowWillCloseSelector: NULL];
    [self.window close];
}

-(IBAction) otherButtonWasClicked: (id)  sender {

    if (  otherResponseSelector  ) {
        [self.responseTarget performSelectorOnMainThread: self.otherResponseSelector withObject: nil waitUntilDone: NO];
    }
    [self setWindowWillCloseSelector: NULL];
    [self.window close];
}

-(void) awakeFromNib {
	
    [[self window] setDelegate: self];
    
    [iconIV setImage: [NSImage imageNamed: @"NSApplicationIcon"]];
    
    [self setupHeadline];
    [self setupProgressInd];

    if (  ! defaultButtonTitle  ) {
        [self setDefaultButtonTitle: NSLocalizedString(@"OK", @"Button")];
    }
    [self.defaultButton setTitle: defaultButtonTitle];

    if (  self.alternateButtonTitle  ) {
        [self.alternateButton setTitle: self.alternateButtonTitle];
        [self.alternateButton setHidden: NO];
    }

    if (  self.otherButtonTitle  ) {
        [self.otherButton setTitle: self.otherButtonTitle];
        [self.otherButton setHidden: NO];
    }

    if (   self.responseTarget  ) {
        if (  self.alternateResponseSelector  ) {
            [self.alternateButton setHidden: FALSE];
        }
        if (  self.otherResponseSelector  ) {
            [self.otherButton setHidden: FALSE];
        }
    }

    [self setupMessageAndCheckbox];

	NSWindow * w = [self window];
    
    [w setTitle: NSLocalizedString(@"Tunnelblick", @"Window title")];
    
    NSMutableArray * bodyViews = [NSMutableArray arrayWithObjects: headlineTF, messageSV, nil];
    if (  progressInd  ) { // (The right-to-left version of the window has no progress indicator)
        [bodyViews addObject: progressInd];
    }
    [bodyViews addObject: doNotWarnAgainCheckbox];

    [UIHelper layOutDialogWindow: w
                            icon: iconIV
                       bodyViews: bodyViews
                       bodyWidth: ALERT_BODY_WIDTH
                   leadingButton: self.otherButton
                 trailingButtons: @[self.alternateButton, self.defaultButton]];

	[w setDefaultButtonCell: [self.defaultButton cell]];

	[w center];
    [w display];
    [self showWindow: self];
    [w makeKeyAndOrderFront: nil];

    [gMC activateIgnoringOtherApps];

    [w makeKeyAndOrderFront: self];
}
@end
