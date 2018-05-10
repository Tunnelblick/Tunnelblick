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

extern BOOL              gShuttingDownWorkspace;
extern TBUserDefaults  * gTbDefaults;

@implementation AlertWindowController


TBSYNTHESIZE_OBJECT(retain, NSString *,			  headline,			      setHeadline)
TBSYNTHESIZE_OBJECT(retain, NSString *,			  message,			      setMessage)
TBSYNTHESIZE_OBJECT(retain, NSAttributedString *, messageAS,		      setMessageAS)
TBSYNTHESIZE_OBJECT(retain, NSString *,			  preferenceToSetTrue,    setPreferenceToSetTrue)
TBSYNTHESIZE_OBJECT(retain, NSString *,			  checkboxTitle,          setCheckboxTitle)
TBSYNTHESIZE_OBJECT(retain, NSAttributedString *, checkboxInfoTitle,      setCheckboxInfoTitle)
TBSYNTHESIZE_OBJECT(retain, TBButton *,           doNotWarnAgainCheckbox, setDoNotWarnAgainCheckbox)
TBSYNTHESIZE_NONOBJECT(BOOL,                      checkboxIsChecked,      setCheckboxIsChecked)

TBSYNTHESIZE_OBJECT_GET(retain, NSImageView     *, iconIV)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextField     *, headlineTF)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *, headlineTFC)

TBSYNTHESIZE_OBJECT_GET(retain, NSScrollView    *, messageSV)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextView      *, messageTV)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton        *, okButton)

-(id) init
{
    self = [super initWithWindowNibName: [UIHelper appendRTLIfRTLLanguage: @"AlertWindow"]];
    if (  ! self  ) {
        return nil;
    }
    
	[self retain];		// Retain ourself. windowWillClose will release ourself.
    return self;
}

- (void) dealloc {
    
    [headline			    release]; headline				 = nil;
    [message			    release]; message				 = nil;
	[messageAS			    release]; messageAS				 = nil;
	[doNotWarnAgainCheckbox release]; doNotWarnAgainCheckbox = nil;
	[preferenceToSetTrue    release]; preferenceToSetTrue	 = nil;
	[checkboxTitle          release]; checkboxTitle			 = nil;
	[checkboxInfoTitle      release]; checkboxInfoTitle		 = nil;
	
	[super dealloc];
}

-(void) windowWillClose: (NSNotification *) notification {
	
    (void) notification;

	if (  preferenceToSetTrue  ) {
		if (  [doNotWarnAgainCheckbox state] == NSOnState  ) {
			[gTbDefaults setBool: TRUE forKey: preferenceToSetTrue];
		}
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
	
	// Adjust the window for the new height
	NSWindow * w = [self window];
	[w setShowsResizeIndicator: NO];
	NSRect wFrame = [w frame];
	wFrame.size.height += heightChange;
	wFrame.origin.y -= heightChange;
	[w setFrame: wFrame display: NO];
	
	// Adjust the scroll view for the new height
	NSScrollView * sv = [self messageSV];
	[sv setBorderType: NSNoBorder];
	[sv setHasVerticalScroller: NO];
	NSRect svFrame = [sv frame];
	svFrame.size.height += heightChange;
	svFrame.origin.y    -= heightChange;
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
	[[tv textStorage] setAttributedString: msgAS];
	
	// Make the cursor disappear
	[tv setSelectedRange: NSMakeRange([msg length] + 1, 0)];
	
	[self setupCheckboxWithHeightChange: heightChange];
}

-(void) setupCheckboxWithHeightChange: (CGFloat) heightChange {
	
	if (  ! preferenceToSetTrue  ) {
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

-(void) awakeFromNib {
	
    [[self window] setDelegate: self];
    
    [iconIV setImage: [NSImage imageNamed: @"NSApplicationIcon"]];
    
	[self setupHeadline];
    
	[self setupMessageAndCheckbox];
	
    BOOL rtl = [UIHelper languageAtLaunchWasRTL];
    [UIHelper setTitle: NSLocalizedString(@"OK", @"Button") ofControl: [self okButton] shift: ( !rtl ) narrow: NO enable: YES];
    
	NSWindow * w = [self window];
    
    [w setTitle: NSLocalizedString(@"Tunnelblick", @"Window title")];
    
	[w setDefaultButtonCell: [okButton cell]];
	
	[w center];
    [w display];
    [self showWindow: self];
    
	[NSApp activateIgnoringOtherApps: YES];
	
    [w makeKeyAndOrderFront: self];
}
@end
