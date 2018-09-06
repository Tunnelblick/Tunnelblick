/*
 * Copyright 2011, 2012, 2013, 2014, 2018 Jonathan K. Bullard. All rights reserved.
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

#import "ListingWindowController.h"

@implementation ListingWindowController

-(id) initWithHeading: (NSString *) theHeading
			     text: (NSString *) theText {
	
	if (  (self = [super initWithWindowNibName:@"ListingWindow"])  ) {
		heading = [theHeading retain];
		text    = [theText    retain];
	}
	
	return self;
}

-(void) dealloc {
	
	[heading release]; heading = nil;
	[text    release]; text    = nil;
	
    [super dealloc];
}

-(void) awakeFromNib {
	
	[[self window] setTitle: heading];
	
	NSMutableAttributedString * textAS = [[[NSMutableAttributedString alloc] initWithString: text] autorelease];
	[textAS addAttribute: NSForegroundColorAttributeName value:[NSColor textColor]           range: NSMakeRange(0, [textAS length])];
	[textAS addAttribute: NSBackgroundColorAttributeName value:[NSColor textBackgroundColor] range: NSMakeRange(0, [textAS length])];
	
	NSTextStorage * ts = [listingView textStorage];
	[ts beginEditing];
	[ts appendAttributedString: textAS];
	[ts endEditing];
	[ts setAlignment: NSLeftTextAlignment range: NSMakeRange(0, [text length])]; // Force left alignment even if an RTL language because this is a configuration file listing
}

-(void) windowWillClose:(NSNotification *) notification {
	
	(void) notification;
	
	[self autorelease];
}

@end
