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

TBSYNTHESIZE_OBJECT_GET(retain, NSScrollView    *, sizingSV)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextView      *, sizingTV)

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

-(CGFloat) setupHeadline {

    // Sets up the headline and returns the window width change needed to fit the headline

    NSTextField     * tf =  [self headlineTF];
    NSTextFieldCell * tfc = [self headlineTFC];

    [tfc setFont: [NSFont boldSystemFontOfSize: 16.0]];

    BOOL rtl = [UIHelper languageAtLaunchWasRTL];
    CGFloat widthChange = [UIHelper setTitle: [self headline] ofControl: tfc frameHolder: tf shift: rtl narrow: NO enable: YES];
    return widthChange;
}

-(void) setupProgressInd {

    [self.progressInd setMinValue: 0.0];
    [self.progressInd setMaxValue: 100.0];
    [self.progressInd setDoubleValue: self.initialPercentage];
    [self.progressInd setHidden: (self.initialPercentage == 0.0)];
}

-(void) changeWindow: (NSWindow *) window
            heightBy: (CGFloat)    heightChange {

    NSRect winFrame = window.frame;
    winFrame.size.height += heightChange;
    winFrame.origin.y -= heightChange;
    [window setFrame: winFrame display: YES animate: YES];
}

-(void) resizeWindow: (NSWindow *)           window
          scrollView: (NSScrollView *)       scrollView
            textView: (NSTextView *)         textView
 forAttributedString: (NSAttributedString *) attrString {

    // Hide the vertical scrollers and don't offset scroll view contents.
    sizingSV.hasVerticalScroller = NO;
    [sizingSV setContentInsets: NSEdgeInsetsZero];
    scrollView.hasVerticalScroller = NO;
    [scrollView setContentInsets: NSEdgeInsetsZero];

    // Put the attributed string in a hidden NSTextView which isn't in the window
    // (so it doesn't change the window size) and whose height isn't constrained.
    // Then calculate the height change when the text view is sized to fit.
    CGFloat oldTvHeight = sizingTV.frame.size.height;
    [sizingTV.textStorage setAttributedString: attrString];
    [sizingTV.layoutManager ensureLayoutForTextContainer: sizingTV.textContainer];
    [sizingTV sizeToFit];
    CGFloat newTvHeight = sizingTV.frame.size.height;
    CGFloat heightChange = newTvHeight - oldTvHeight;

    // Store the attributed string in the text view that will be displayed
    [textView.textStorage setAttributedString: attrString];
    [textView.layoutManager ensureLayoutForTextContainer: textView.textContainer];

    [self changeWindow: window heightBy: heightChange];
}

-(void) setupMessageAndCheckbox {

	// Set the string
	NSString * msg = self.message;
	NSAttributedString * msgAS = (   msg
								  ? [[[NSAttributedString alloc] initWithString: msg] autorelease]
								  : [self messageAS]);
	if (  ! msgAS  ) {
		msgAS = [[[NSAttributedString alloc] initWithString: NSLocalizedString(@"Program error, please see the Console log.", @"Window text")] autorelease];
		NSLog(@"AlertWindowController: no message or messageAS; stack trace: %@", callStack());
	}

    // Remove trailing linefeeds
    NSMutableAttributedString * mutableAS = [[msgAS mutableCopy] autorelease];
    while (  [[mutableAS string] hasSuffix: @"\n"]  ) {
        [mutableAS deleteCharactersInRange: NSMakeRange([[mutableAS string] length] - 1, 1)];
    }
    msgAS = [[[NSAttributedString alloc] initWithAttributedString: mutableAS] autorelease];

    // Put the string into the NSTextView, and resize the height of the window, the scrollView, and the textView so the text fits without scrolling
    NSWindow * w = self.window;
    NSScrollView * sv = self.messageSV;
    NSTextView * tv = self.messageTV;
    CGFloat oldWindowHeight = w.frame.size.height;
    [self resizeWindow: w scrollView: sv textView: tv forAttributedString: msgAS];
    CGFloat newWindowHeight = w.frame.size.height;
    CGFloat heightChange = oldWindowHeight - newWindowHeight;

    // Scroll to the top of the view
    [tv scrollPoint: NSMakePoint(0.0, 0.0)];

    // Set up the checkbox (if any) and move it within the window to adjust for the change in the window's height
	[self setupCheckboxWithHeightChange: - heightChange];
}

-(void) setupCheckboxWithHeightChange: (CGFloat) heightChange {

	if (   (   (! preferenceToSetTrue)
            || [preferenceToSetTrue hasSuffix: @"-NotAnActualPreference"]
            )
		&& ( ! (   preferenceName
				&& preferenceValue))) {
		[doNotWarnAgainCheckbox setHidden: TRUE];
		return;
	}
	
	NSRect frame = [doNotWarnAgainCheckbox frame];
	frame.origin.y -= heightChange;
	[doNotWarnAgainCheckbox setFrame: frame];
	
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

-(void) widenWindowBy: (CGFloat) widthChange {

    // Widen the window by widthChange if widthChange is positive.

    if (  widthChange > 0.0  ) {
        NSWindow * w = [self window];
        NSRect windowFrame = [w frame];
        windowFrame.size.width += widthChange;
        [w setFrame: windowFrame display: NO];
    }
}

-(void) awakeFromNib {
	
    [[self window] setDelegate: self];
    
    [iconIV setImage: [NSImage imageNamed: @"NSApplicationIcon"]];
    
    // Widen the window to account for wider headline
	CGFloat widthChange = [self setupHeadline];
    [self widenWindowBy: widthChange];

    [self setupProgressInd];

    BOOL rtl = [UIHelper languageAtLaunchWasRTL];

    if (  ! defaultButtonTitle  ) {
        [self setDefaultButtonTitle: NSLocalizedString(@"OK", @"Button")];
    }

    widthChange = [UIHelper setTitle: defaultButtonTitle ofControl: [self defaultButton] shift: ( !rtl ) narrow: NO enable: YES];
    [UIHelper shiftControl: self.alternateButton by: (- widthChange) reverse: ( ! rtl)];

    if (  self.alternateButtonTitle  ) {
        [UIHelper setTitle: self.alternateButtonTitle   ofControl: self.alternateButton   shift: ( !rtl ) narrow: NO enable: YES];
        [self.alternateButton setHidden: NO];
    }

    if (  self.otherButtonTitle  ) {
        [UIHelper setTitle: self.otherButtonTitle ofControl: self.otherButton shift: ( rtl ) narrow: NO enable: YES];
        [self.otherButton setHidden: NO];
    }

	NSWindow * w = [self window];
    
    [w setTitle: NSLocalizedString(@"Tunnelblick", @"Window title")];
    
	[w setDefaultButtonCell: [self.defaultButton cell]];

    if (   self.responseTarget  ) {
        if (  self.alternateResponseSelector  ) {
            [self.alternateButton setHidden: FALSE];
        }
        if (  self.otherResponseSelector  ) {
            [self.otherButton setHidden: FALSE];
        }
    }

    [self setupMessageAndCheckbox];

	[w center];
    [w display];
    [self showWindow: self];
    [w makeKeyAndOrderFront: nil];

    [gMC activateIgnoringOtherApps];

    [w makeKeyAndOrderFront: self];
}
@end
