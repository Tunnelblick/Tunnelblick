/*
 * Copyright 2013 Jonathan Bullard
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

#import "LeftNavItem.h"

@implementation LeftNavItem

static LeftNavItem * rootItem = nil;

+ (LeftNavItem *) rootItem {
	if (rootItem == nil) {
		rootItem = [[LeftNavItem alloc] init];
        [rootItem setDisplayName: @""];
        [rootItem setNameToShowInOutlineView: NSLocalizedString(@"Configurations", @"Window text")];
        [rootItem setParent:      nil];
        [rootItem setChildren:    [[[NSMutableArray alloc] initWithCapacity: 20] autorelease]];
	}
	
	return rootItem;
}

- (void) dealloc {
	
    [nameToShowInOutlineView release];
    [displayName             release];
    [parent                  release];
    [children                release];
    
    [super dealloc];
}

- (NSInteger)numberOfChildren{
    if (  ! children  ) {
        return -1;
    }
    return [children count];
}

- (LeftNavItem *)childAtIndex:(NSUInteger)n {
    return [children objectAtIndex: n];
}

TBSYNTHESIZE_OBJECT(retain, NSString *,       displayName,             setDisplayName             )
TBSYNTHESIZE_OBJECT(retain, NSString *,       nameToShowInOutlineView, setNameToShowInOutlineView )
TBSYNTHESIZE_OBJECT(retain, LeftNavItem *,    parent,                  setParent                  )
TBSYNTHESIZE_OBJECT(retain, NSMutableArray *, children,                setChildren                )

@end
