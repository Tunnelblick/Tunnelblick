/*
 * Copyright 2011 Jonathan Bullard
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
#import "InstallWindowController.h"


@implementation InstallWindowController


-(id) init
{
    if (  ![super initWithWindowNibName:@"InstallWindow"]  ) {
        return nil;
    }

    [super showWindow: self];

    return self;
}

-(void) awakeFromNib
{
    [[self window] setTitle: NSLocalizedString(@"Tunnelblick", @"Window title")];
    
    [iconIV setImage: [NSImage imageNamed: @"tb-logo-309x64-2011-06-26"]];
    
    NSString * text = NSLocalizedString(@"Please wait while Tunnelblick is being installed and secured...", @"Window text");
    [mainText setTitle: text];
    
    [[self window] center];
    [[self window] display];
    [self showWindow: self];
    [NSApp activateIgnoringOtherApps: YES];
    [[self window] makeKeyAndOrderFront: self];
}

- (void) dealloc
{
    [iconIV   release];
    [mainText release];
    
	[super dealloc];
}

- (NSString *) description
{
    return [NSString stringWithFormat:@"%@", [self class]];
}

TBSYNTHESIZE_OBJECT_SET(NSTextFieldCell *, mainText, setMainText)
@end