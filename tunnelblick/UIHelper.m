/*
 * Copyright 2015, 2016, 2018 Jonathan K. Bullard. All rights reserved.
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

#import <Quartz/Quartz.h>

#import "helper.h"
#import "sharedRoutines.h"

#import "MenuController.h"
#import "TBUserDefaults.h"
#import "UIHelper.h"

extern MenuController * gMC;
extern TBUserDefaults * gTbDefaults;

@implementation UIHelper

+(NSString *) appendRTLIfRTLLanguage: (NSString *) string {
    
    if (  [gMC languageAtLaunchWasRTL]  ) {
        return [string stringByAppendingString: @"-RTL"];
    }
    
    return string;
}

+(unsigned int) detailsWindowsViewIndexFromPreferencesWithCount: (unsigned int) count {
    
    // "count" is the [toolbarIdentifiers count]. The views are in the same order for all languages,
    // followed by the lock icon, which has no view.
	
	return [gTbDefaults unsignedIntForKey: @"detailsWindowViewIndex" default: 0 min: 0 max: count - 2];
}

+(BOOL) languageAtLaunchWasRTL {
    
    return [gMC languageAtLaunchWasRTL];
}

+(NSString *) imgTagForImageName: (NSString *) imageName
                           width: (NSInteger)  width
                          height: (NSInteger)  height {
    
    NSURL * url = [[NSBundle mainBundle] URLForImageResource: imageName];
    NSString * tag = [NSString stringWithFormat: @"<img src=\"%@\" width=\"%ld\" height=\"%ld\">",
                      [url absoluteString], (long)width, (long)height];
    return tag;
}


+(void) makeAllAsWideAsWidest: (NSArray *) list
						shift: (BOOL)      shift {
	
	// Changes the width of a set of buttons so they are all as wide as the widest one.
	//
	// If "shift" is TRUE, shifts each button as needed to keep it flush right
	
	// Find the width of the largest button
	CGFloat largestWidth = -1.0;
	NSEnumerator * e = [list objectEnumerator];
	NSButton * button;
	while (  (button = [e nextObject])  ) {
		CGFloat thisWidth = [button frame].size.width;
		if (  thisWidth > largestWidth  ) {
			largestWidth = thisWidth;
		}
	}
	
	// Adjust the buttons
	if (  largestWidth != -1.0  ) {
		e = [list objectEnumerator];
		while (  (button = [e nextObject])  ) {
			CGFloat thisWidth = [button frame].size.width;
			CGFloat change = thisWidth - largestWidth;
			if (  change != 0.0) {
				NSRect frame = [button frame];
				frame.size.width = frame.size.width - change;
				[button setFrame: frame];
				if (  shift  ) {
					[UIHelper shiftControl: button by: change reverse: YES];
				}
			}
		}
	}
}

+(CGFloat) setTitle: (NSString *) newTitle
		  ofControl: (id)         theControl
	    frameHolder: (id)         frameHolder
			  shift: (BOOL)       shift
			 narrow: (BOOL)       narrow
			 enable: (BOOL)       enable {
	
    // Sets up UI elements that are flush right or flush left and need to be resized.
    //
    // Optionally sets the title of a control, then adjusts its size, optionally shifts it right or left to keep
    // the right or left edge of the control in the same place, and then sets it enabled or disabled.
    //
    // If 'newTitle' is given, setTitle is performed on 'theControl'.
    // All sizing activity is performed on 'frameHolder'.
    // For an NSButton, 'theControl' and 'frameHolder' will be the same.
    // For text, 'theControl' will be an NSTextFieldCell and 'frameholder' will be an NSTextField
    //
    // If 'newTitle' is nil, the title is not set, but everything else is done. (Used for pop-down buttons.)
    //
    // An element that is flush right in an LTR language is flush left in an RTL language, so the 'shift'
    // argument is usually either [UIHelper languageAtLaunchWasRTL] or its logical inverse.
    // This is, 'shift' is TRUE for something that is flush right in an LTR language, or flush left in an RTL language.
    //
    // If 'narrow' is true, then the control is allowed to become narrower. (Set FALSE for "OK" buttons and other small buttons.)
    //
    // Returns the change in size of the control (positive if the control got larger, negative if it got smaller).
    
    if (   ( ! theControl )
		|| ( ! frameHolder )  ) {
        NSLog(@"setTitle:ofControl:shift:setEnabled: control and/or frameControl is nil; title is '%@'", newTitle);
        [gMC terminateBecause: terminatingBecauseOfError];
        return 0.0; // Make static analyzer happy
    }
    
    CGFloat widthChange = 0.0;
    
    NSRect oldFrame = [frameHolder frame];
    
    if (  newTitle  ) {
        [theControl setTitle: newTitle];
    }
    
    [frameHolder sizeToFit];
    
    NSRect newFrame = [frameHolder frame];
    if (  ! narrow  ) {
        if (  newFrame.size.width < oldFrame.size.width  ) {
            newFrame.size.width = oldFrame.size.width;
            [frameHolder setFrame: newFrame];
        }
    }
    
    widthChange = newFrame.size.width - oldFrame.size.width;    // + if control got bigger, - if got smaller
    
    if (  shift  ) {
        newFrame.origin.x = newFrame.origin.x - widthChange;    // shift control left if got bigger, right if got smaller
        [frameHolder setFrame:newFrame];
    }
    
    [theControl setEnabled: enable];
    
    return widthChange;
}

+(CGFloat) setTitle: (NSString *) newTitle
          ofControl: (id)         theControl
              shift: (BOOL)       shift
             narrow: (BOOL)       narrow
             enable: (BOOL)       enable {
    
    return [UIHelper setTitle: newTitle ofControl: theControl frameHolder: theControl shift: shift narrow: narrow enable: enable];
}

+(void) shiftControl: (id)      theControl
                  by: (CGFloat) amount
             reverse: (BOOL)    reverse {
    
    // Optionally shifts a control right (if amount is negative) or left (if amount is positive)
    // If "reverse" is TRUE, moves in the opposite direction
    
    if (  ! theControl  ) {
        NSLog(@"shift:control:by: control is nil");
        [gMC terminateBecause: terminatingBecauseOfError];
        return; // Make static analyzer happy
    }
    
    if (  reverse  ) {
        amount = - amount;
    }
    
    NSRect newFrame = [theControl frame];
    newFrame.origin.x = newFrame.origin.x - amount;
    [theControl setFrame:newFrame];
}

+(void) performOnMainThreadDictionary: (NSDictionary *) dict {
	
	SEL selector = NSSelectorFromString([dict objectForKey: @"selectorName"]);
	id  target   = [dict objectForKey: @"target"];
	id  object   = [dict objectForKey: @"object"];
	[target performSelectorOnMainThread: selector withObject: object waitUntilDone: NO];
}

+(void) performSelectorName: (NSString *) selectorName
					 target: (id)         target
				 withObject: (NSObject *) object
	 onMainThreadAfterDelay: (NSTimeInterval) delay {
	
	if (   ( ! selectorName )
		|| ( ! target )  ) {
		NSLog(@"Error: performSelectorName: %@ target: %@ withObject: %@ onMainThreadAfterDelay %f",
			  selectorName, target, object, delay);
		[gMC terminateBecause: terminatingBecauseOfError];
		return;
	}
	
	if (  ! object  ) {
		object = [NSNull null];
	}
	
	NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
						   selectorName, @"selectorName",
						   target,		 @"target",
						   object,       @"object",
						   nil];
	
	[self performSelector: @selector(performOnMainThreadDictionary:) withObject: dict afterDelay: delay];
}

+(BOOL) canAcceptFileTypesInPasteboard: (NSPasteboard *) pboard {
	
	// Accept a single .tblkSetup or multiple configurations but don't accept a mix or multiple .tblkSetups
	
	NSArray * configExtensions = [NSArray arrayWithObjects: @"ovpn", @"conf", @"tblk", nil];
	
	NSString * type = [pboard availableTypeFromArray: [NSArray arrayWithObject: NSFilenamesPboardType]];
	if (  ! [type isEqualToString: NSFilenamesPboardType]  ) {
		TBLog(@"DB-SI", @"canAcceptFileTypesInPasteboard: returning NO because no 'NSFilenamesPboardType' entries are available in the pasteboard.");
		return NO;
	}
	
	NSArray * paths = [pboard propertyListForType: NSFilenamesPboardType];
	NSUInteger i;
	BOOL haveSetup         = FALSE;
	BOOL haveConfiguration = FALSE;
	for (  i=0; i<[paths count]; i++  ) {
		NSString * path = [paths objectAtIndex:i];
		if (  [configExtensions containsObject: [path pathExtension]]  ) {
			if (  haveSetup  ) {
				TBLog(@"DB-SI", @"canAcceptFileTypesInPasteboard: have seen a .tblkSetup, so returning NO for '%@' in '%@'", [path lastPathComponent], [path stringByDeletingLastPathComponent]);
				return NO;
			}
			haveConfiguration = TRUE;
			TBLog(@"DB-SI", @"canAcceptFileTypesInPasteboard: acceptable: '%@' in '%@'", [path lastPathComponent], [path stringByDeletingLastPathComponent]);
		} else if (  [[path pathExtension] isEqualToString: @"tblkSetup"]  ) {
			if (  haveConfiguration  ) {
				TBLog(@"DB-SI", @"canAcceptFileTypesInPasteboard: have seen a configuration, so returning NO for '%@' in '%@'", [path lastPathComponent], [path stringByDeletingLastPathComponent]);
				return NO;
			}
			if (  [gMC showingImportSetupWindow]  ) {
				TBLog(@"DB-SI", @"canAcceptFileTypesInPasteboard: already importing a .tblksetup, so returning NO for '%@' in '%@'", [path lastPathComponent], [path stringByDeletingLastPathComponent]);
				return NO;
			}
			if (  haveSetup  ) {
				TBLog(@"DB-SI", @"canAcceptFileTypesInPasteboard: have seen a .tblkSetup, so returning NO for '%@' in '%@'", [path lastPathComponent], [path stringByDeletingLastPathComponent]);
				return NO;
			}
			haveSetup = TRUE;
			TBLog(@"DB-SI", @"canAcceptFileTypesInPasteboard: acceptable: '%@' in '%@'", [path lastPathComponent], [path stringByDeletingLastPathComponent]);
		} else {
			TBLog(@"DB-SI", @"canAcceptFileTypesInPasteboard: unknown extension, so returning NO for '%@' in '%@'", [path lastPathComponent], [path stringByDeletingLastPathComponent]);
			return NO;
		}
	}
	
	TBLog(@"DB-SI", @"canAcceptFileTypesInPasteboard: returning 'YES'");
	return YES;
}

+(NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
	
	NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
	NSPasteboard * pboard = [sender draggingPasteboard];
	
	if (  [[pboard types] containsObject: NSFilenamesPboardType]  ) {
		if (  [self canAcceptFileTypesInPasteboard: pboard]  ) {
			if (  sourceDragMask & NSDragOperationCopy  ) {
				TBLog(@"DB-SI", @"draggingEntered: returning YES");
				return NSDragOperationCopy;
			} else {
				TBLog(@"DB-SI", @"draggingEntered: returning NO because source does not allow copy operation");
			}
		}
	}
	
	TBLog(@"DB-SI", @"draggingEntered: returning NO");
	return NSDragOperationNone;
}

+(BOOL) performDragOperation:(id <NSDraggingInfo>)sender {
	
	NSPasteboard *pboard = [sender draggingPasteboard];
	
	if ( [[pboard types] containsObject: NSFilenamesPboardType] ) {
		NSArray * files = [pboard propertyListForType:NSFilenamesPboardType];
			
			[self performSelectorName:@"openFiles:" target: gMC withObject: files onMainThreadAfterDelay: 0.5];
		
		TBLog(@"DB-SI", @"performDragOperation: returning YES");
		return YES;
	}
	
	TBLog(@"DB-SI", @"performDragOperation: returning NO because pasteboard does not contain 'NSFilenamesPboardType'");
	return NO;
}

+(void) showAlertWindow: (NSDictionary *) dict {
    
    // This method is invoked on the main thread by TBShowAlertWindow() when it is called but is not running on the main thread
    
    if (  ! [NSThread isMainThread]  ) {
        NSLog(@"[UIHelper showAlertWindow] was invoked but not on the main thread; stack trace: %@", NSThread.callStackSymbols);
        [self performSelectorOnMainThread: @selector(showAlertWindow:)  withObject: dict waitUntilDone: NO];
        return;
    }

	TBShowAlertWindowExtended(nilIfNSNull([dict objectForKey: @"title"]),
							  nilIfNSNull([dict objectForKey: @"msg"]),
							  nilIfNSNull([dict objectForKey: @"preferenceToSetTrue"]),
							  nilIfNSNull([dict objectForKey: @"preferenceName"]),
							  nilIfNSNull([dict objectForKey: @"preferenceValue"]),
							  nilIfNSNull([dict objectForKey: @"checkboxTitle"]),
							  nilIfNSNull([dict objectForKey: @"checkboxInfoTitle"]),
							             [[dict objectForKey: @"checkboxIsOn"] boolValue]);
}

+(void) showSuccessNotificationTitle: (NSString *) title
                                 msg: (NSString *) msg {
    
    NSUserNotification * notification = [[[NSUserNotification alloc] init] autorelease];
    if (  ! notification  ) {
        NSLog(@"Cannot create NSUserNotification");
        TBShowAlertWindow(title, msg);
        return;
    }
    
    [notification setTitle:           title];
    [notification setInformativeText: msg];
    [notification setSoundName:       @"NSUserNotificationDefaultSoundName"];
    
    NSUserNotificationCenter * center = [NSUserNotificationCenter defaultUserNotificationCenter];
    if (  ! center  ) {
        NSLog(@"Cannot create NSUserNotificationCenter");
        TBShowAlertWindow(title, msg);
        return;
    }
    
    [center deliverNotification: notification];

}

// The following method is a modified version of the code at http://stackoverflow.com/questions/10517386/how-to-give-nswindow-a-shake-effect-as-saying-no-as-in-login-failure-window/23491643#23491643

+(void)shakeWindow: (NSWindow *) w {
    
    static int   numberOfShakes  = 3;
    static float durationOfShake = 0.5f;
    static float vigourOfShake   = 0.02f;
    
    CGRect frame=[w frame];
    CAKeyframeAnimation * shakeAnimation = [CAKeyframeAnimation animation];
    
    CGMutablePathRef shakePath = CGPathCreateMutable();
    
    CGPathMoveToPoint(shakePath, NULL, NSMinX(frame), NSMinY(frame));
    for (  NSInteger index = 0; index < numberOfShakes; index++  ){
        CGPathAddLineToPoint(shakePath, NULL, NSMinX(frame) - frame.size.width * vigourOfShake, NSMinY(frame));
        CGPathAddLineToPoint(shakePath, NULL, NSMinX(frame) + frame.size.width * vigourOfShake, NSMinY(frame));
    }
    CGPathCloseSubpath(shakePath);
    shakeAnimation.path = shakePath;
    shakeAnimation.duration = durationOfShake;
    
    [w setAnimations:[NSDictionary dictionaryWithObject: shakeAnimation forKey:@"frameOrigin"]];
    [[w animator] setFrameOrigin:[w frame].origin];
    
    CGPathRelease(shakePath);
}

+(void) setUpDialogHeadline: (NSTextField *) textField
                       width: (CGFloat)       width {

    // Shows the text of a dialog's headline like an alert's message text: bold, wrapped to the width,
    // and without the indentation some localized texts use at the start of a line

    NSTextFieldCell * cell = [textField cell];
    [cell setFont: [NSFont boldSystemFontOfSize: [NSFont systemFontSize]]];
    [cell setScrollable: NO];
    [cell setWraps: YES];
    [cell setLineBreakMode: NSLineBreakByWordWrapping];
    [textField setPreferredMaxLayoutWidth: width];
    NSString * text = [textField stringValue];
    [textField setStringValue: [text stringByReplacingOccurrencesOfString: @"\n[ \t]+"
                                                               withString: @"\n"
                                                                  options: NSRegularExpressionSearch
                                                                    range: NSMakeRange(0, [text length])]];
}

+(NSView *) viewOverlaying: (NSView *) firstView
                      with: (NSView *) secondView {

    // Returns a view that holds both views on top of each other, filling it (e.g. a secure text field and the
    // plain text field that shows the same text when it is exposed; only one of them is shown at a time)

    NSView * container = [[[NSView alloc] init] autorelease];
    NSView * view;
    NSEnumerator * e = [@[firstView, secondView] objectEnumerator];
    while (  (view = [e nextObject])  ) {
        [container addSubview: view];
        [view setTranslatesAutoresizingMaskIntoConstraints: NO];
        [NSLayoutConstraint activateConstraints: @[[[view leadingAnchor]  constraintEqualToAnchor: [container leadingAnchor]],
                                                   [[view trailingAnchor] constraintEqualToAnchor: [container trailingAnchor]],
                                                   [[view topAnchor]      constraintEqualToAnchor: [container topAnchor]],
                                                   [[view bottomAnchor]   constraintEqualToAnchor: [container bottomAnchor]]]];
    }
    return container;
}

+(void) setRightToLeftLayoutIn: (NSView *) view
                containersOnly: (BOOL)     containersOnly {

    // Lays out a view and its subviews from right to left (with containersOnly, only the stack views and grid views).
    //
    // AppKit lays out Tunnelblick from left to right even for right-to-left languages, which use right-to-left versions
    // of the nibs instead. Views that are built in code (and laid out with stack views and leading/trailing constraints)
    // are mirrored with this. A view's layout direction is not inherited by its subviews, so views that are added later
    // (such as table cells) must be set up when they are created.

    if (   ( ! containersOnly )
        || [view isKindOfClass: [NSStackView class]]
        || [view isKindOfClass: [NSGridView class]]  ) {
        [view setUserInterfaceLayoutDirection: NSUserInterfaceLayoutDirectionRightToLeft];
    }
    NSView * subview;
    NSEnumerator * e = [[view subviews] objectEnumerator];
    while (  (subview = [e nextObject])  ) {
        [UIHelper setRightToLeftLayoutIn: subview containersOnly: containersOnly];
    }
}

+(void) layOutDialogWindow: (NSWindow *)    window
                      icon: (NSImageView *) icon
                 bodyViews: (NSArray *)     bodyViews
                 bodyWidth: (CGFloat)       bodyWidth
             leadingButton: (NSButton *)    leadingButton
           trailingButtons: (NSArray *)     trailingButtons {

    // Lays out a dialog like a standard macOS alert: the icon on the leading side, the body views stacked next to it,
    // and the buttons in a row along the bottom (leadingButton at the leading edge, trailingButtons at the trailing edge,
    // with the default button last). The window gets no visible title and is sized to fit its content.
    //
    // The views are moved out of their nib positions into stack views, so the layout also works for right-to-left languages.
    // Hidden views take no space. Like an alert, the window has no title bar buttons; the caller handles the Escape key.

    [window setStyleMask: ([window styleMask] | NSWindowStyleMaskFullSizeContentView) & ~NSWindowStyleMaskResizable];
    [window setTitlebarAppearsTransparent: YES];
    [window setTitleVisibility: NSWindowTitleHidden];
    [[window standardWindowButton: NSWindowCloseButton]       setHidden: YES];
    [[window standardWindowButton: NSWindowMiniaturizeButton] setHidden: YES];
    [[window standardWindowButton: NSWindowZoomButton]        setHidden: YES];

    [icon setImageScaling: NSImageScaleProportionallyUpOrDown];
    [icon setTranslatesAutoresizingMaskIntoConstraints: NO];
    [NSLayoutConstraint activateConstraints: @[[[icon widthAnchor]  constraintEqualToConstant: 64.0],
                                               [[icon heightAnchor] constraintEqualToConstant: 64.0]]];

    NSStackView * body = [NSStackView stackViewWithViews: bodyViews];
    [body setOrientation: NSUserInterfaceLayoutOrientationVertical];
    [body setAlignment: NSLayoutAttributeLeading];
    [body setSpacing: 10.0];
    [[[body widthAnchor] constraintEqualToConstant: bodyWidth] setActive: YES];

    NSStackView * top = [NSStackView stackViewWithViews: @[icon, body]];
    [top setOrientation: NSUserInterfaceLayoutOrientationHorizontal];
    [top setAlignment: NSLayoutAttributeTop];
    [top setSpacing: 16.0];

    NSStackView * buttonRow = [[[NSStackView alloc] init] autorelease];
    [buttonRow setOrientation: NSUserInterfaceLayoutOrientationHorizontal];
    [buttonRow setSpacing: 12.0];
    NSMutableArray * allButtons = [NSMutableArray arrayWithArray: trailingButtons];
    if (  leadingButton  ) {
        [buttonRow addView: leadingButton inGravity: NSStackViewGravityLeading];
        [allButtons addObject: leadingButton];
    }
    NSButton * button;
    NSEnumerator * e = [trailingButtons objectEnumerator];
    while (  (button = [e nextObject])  ) {
        [buttonRow addView: button inGravity: NSStackViewGravityTrailing];
    }
    e = [allButtons objectEnumerator];
    while (  (button = [e nextObject])  ) {
        [[[button widthAnchor] constraintGreaterThanOrEqualToConstant: 80.0] setActive: YES];
    }

    NSStackView * root = [NSStackView stackViewWithViews: @[top, buttonRow]];
    [root setOrientation: NSUserInterfaceLayoutOrientationVertical];
    [root setAlignment: NSLayoutAttributeLeading];
    [root setSpacing: 20.0];
    [root setTranslatesAutoresizingMaskIntoConstraints: NO];
    [NSLayoutConstraint activateConstraints: @[[[buttonRow widthAnchor] constraintEqualToAnchor: [root widthAnchor]],
                                               [[top widthAnchor] constraintLessThanOrEqualToAnchor: [root widthAnchor]]]];

    if (  [UIHelper languageAtLaunchWasRTL]  ) {
        [UIHelper setRightToLeftLayoutIn: root containersOnly: YES];
    }

    NSView * contentView = [window contentView];
    [contentView addSubview: root];
    [NSLayoutConstraint activateConstraints: @[[[root leftAnchor]   constraintEqualToAnchor: [contentView leftAnchor]   constant:  20.0],
                                               [[root rightAnchor]  constraintEqualToAnchor: [contentView rightAnchor]  constant: -20.0],
                                               [[root topAnchor]    constraintEqualToAnchor: [contentView topAnchor]    constant:  20.0],
                                               [[root bottomAnchor] constraintEqualToAnchor: [contentView bottomAnchor] constant: -20.0]]];

    [contentView layoutSubtreeIfNeeded];
    [window setContentSize: [contentView fittingSize]];
}

@end
