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
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *  or see http://www.gnu.org/licenses/.
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

-(void) setupHeadline {
    
	NSTextField     * tf =  [self headlineTF];
	NSTextFieldCell * tfc = [self headlineTFC];

	[tfc setFont: [NSFont boldSystemFontOfSize: 12.0]];
	
	BOOL rtl = [UIHelper languageAtLaunchWasRTL];
	CGFloat widthChange = [UIHelper setTitle: [self headline] ofControl: tfc frameHolder: tf shift: rtl narrow: NO enable: YES];

	// If title doesn't fit window, adjust the window width so it does
    if (  widthChange > 0.0  ) {
		NSWindow * w = [self window];
		NSRect windowFrame = [w frame];
        windowFrame.size.width += widthChange;
		[w setFrame: windowFrame display: NO];
    }
}

-(void) setupProgressInd {

    [self.progressInd setMinValue: 0.0];
    [self.progressInd setMaxValue: 100.0];
    [self.progressInd setDoubleValue: self.initialPercentage];
    [self.progressInd setHidden: (self.initialPercentage == 0.0)];
}

float heightForStringDrawing(NSString *myString,
							 NSFont *myFont,
							 float myWidth) {
	
	// From http://stackoverflow.com/questions/1992950/nsstring-sizewithattributes-content-rect/1993376#1993376
	
	NSTextStorage *textStorage = [[[NSTextStorage alloc] initWithString:myString] autorelease];
	NSTextContainer *textContainer = [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(myWidth, FLT_MAX)] autorelease];
	
	NSLayoutManager *layoutManager = [[[NSLayoutManager alloc] init] autorelease];
	[layoutManager addTextContainer:textContainer];
	[textStorage addLayoutManager:layoutManager];
	[textStorage addAttribute:NSFontAttributeName value:myFont
						range:NSMakeRange(0, [textStorage length])];
	[textContainer setLineFragmentPadding:0.0];
	
	(void) [layoutManager glyphRangeForTextContainer:textContainer];
	return [layoutManager
			usedRectForTextContainer:textContainer].size.height;
}

-(void) setupMessageAndCheckbox {
	
	NSTextView * tv = [self messageTV];
	
	// Calculate the change in height required to fit the text
	NSRect tvFrame = [tv frame];
	NSFont * font = [NSFont systemFontOfSize: 11.9];
	NSString * messageS = (  message
						   ? [[message copy] autorelease]
						   : [messageAS string]);
    NSString * msgWithLfLfX = (  [messageS hasSuffix: @"\n\n"]
                               ? messageS
                               : [messageS stringByAppendingString: @"\n\nX"]);
    CGFloat newHeight = heightForStringDrawing(msgWithLfLfX, font, tvFrame.size.width);
	
	CGFloat heightChange = newHeight - tvFrame.size.height;
    CGFloat heightChangePlus = 1.1 * heightChange;

	// Adjust the window for the new height
	NSWindow * w = [self window];
	[w setShowsResizeIndicator: NO];
	NSRect wFrame = [w frame];
	wFrame.size.height += heightChangePlus;
	wFrame.origin.y -= heightChangePlus;
	[w setFrame: wFrame display: NO];
	
	// Adjust the scroll view for the new height
	NSScrollView * sv = [self messageSV];
	[sv setBorderType: NSNoBorder];
	[sv setHasVerticalScroller: NO];
	NSRect svFrame = [sv frame];
	svFrame.size.height += heightChangePlus;
	svFrame.origin.y    -= heightChangePlus;
	[sv setFrame: svFrame];


	// Adjust the text view for the new height
	tvFrame.size.height = newHeight;
	tvFrame.origin.y -= heightChange;
	[tv setFrame: tvFrame];
	
	// Set the string
	NSString * msg = [self message];
	NSAttributedString * msgAS = (   msg
								  ? [[[NSAttributedString alloc] initWithString: msg] autorelease]
								  : [self messageAS]);
	if (  ! msgAS  ) {
		msgAS = [[[NSAttributedString alloc] initWithString: NSLocalizedString(@"Program error, please see the Console log.", @"Window text")] autorelease];
		NSLog(@"AlertWindowController: no message or messageAS; stack trace: %@", callStack());
	}
	
	// To get the correct background for the entire last line, make the text end in a single newline.
	NSMutableAttributedString * mAS = [[msgAS mutableCopy] autorelease];
	while (  [[mAS string] hasSuffix: @"\n"]  ) {
		[mAS deleteCharactersInRange: NSMakeRange([[mAS string] length] - 1, 1)];
	}
	[mAS appendAttributedString: [[[NSAttributedString alloc] initWithString: @"\n" attributes: nil] autorelease]];

	[[tv textStorage] setAttributedString: mAS];
	
	// Make the cursor disappear
	[tv setSelectedRange: NSMakeRange([msg length] + 1, 0)];
	
	[self setupCheckboxWithHeightChange: heightChange];
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

-(void) awakeFromNib {
	
    [[self window] setDelegate: self];
    
    [iconIV setImage: [NSImage imageNamed: @"NSApplicationIcon"]];
    
	[self setupHeadline];
    
	[self setupMessageAndCheckbox];
	
    [self setupProgressInd];

    BOOL rtl = [UIHelper languageAtLaunchWasRTL];

    if (  ! defaultButtonTitle  ) {
        [self setDefaultButtonTitle: NSLocalizedString(@"OK", @"Button")];
    }
    CGFloat widthChange = [UIHelper setTitle: defaultButtonTitle ofControl: [self defaultButton] shift: ( !rtl ) narrow: NO enable: YES];
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

	[w center];
    [w display];
    [self showWindow: self];
    [w makeKeyAndOrderFront: nil];

    [gMC activateIgnoringOtherApps];

    [w makeKeyAndOrderFront: self];
}
@end
