/*
 * Copyright 2009, 2010, 2011, 2012, 2013 Jonathan K. Bullard. All rights reserved.
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

#import "TBTextView.h"

#import "MenuController.h"
#import "NSApplication+LoginItem.h"

@implementation TBTextView

#pragma mark Keyboard Events

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)resignFirstResponder
{
    return YES;
}

- (BOOL)becomeFirstResponder
{
    return YES;
}

- (BOOL)performKeyEquivalent:(NSEvent *)event
{
	// Note: Command-Q is not sent to this function
	
    if (  ([event modifierFlags] & NSDeviceIndependentModifierFlagsMask) == NSCommandKeyMask  ) {
        NSString * c = [event charactersIgnoringModifiers];

        if (         [c isEqual: @"c"]  ) {     // Command-C - Copy to pasteboard
            [super copy:nil];
            return YES;
            
        } else if (  [c isEqual: @"x"]  ) {     // Command-X - Cut to pasteboard
            [super cut:nil];
            return YES;
            
        } else if (  [c isEqual: @"v"]  ) {     // Command-V - Paste from pasteboard
            [super paste:nil];
            return YES;
            
        } else if (  [c isEqual: @"a"]  ) {     // Command-A - Select all
            [super selectAll:nil];
            return YES;
            
        } else if (  [c isEqual: @"m"]  ) {     // Command-M - Miniaturize
            NSArray *windows = [NSApp windows];
            NSEnumerator *e = [windows objectEnumerator];
            NSWindow *window = nil;
            while (  (window = [e nextObject])  ) {
                if (  [[window title] hasPrefix: NSLocalizedString(@"Details - Tunnelblick",  @"Window title")]  ) {
                    [window miniaturize:nil];
                    return YES;
                }
            }
            
        } else if (  [c isEqual: @"w"]  ) {     // Command-W - Close window
            NSArray *windows = [NSApp windows];
            NSEnumerator *e = [windows objectEnumerator];
            NSWindow *window = nil;
            while (  (window = [e nextObject])  ) {
                if (  [[window title] hasPrefix: NSLocalizedString(@"Details - Tunnelblick",  @"Window title")]  ) {
                    [window performClose:nil];
                    return YES;
                }
            }
        }
    }

    return NO;
}

@end
