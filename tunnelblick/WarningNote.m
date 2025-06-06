/*
 * Copyright 2020 Jonathan K. Bullard. All rights reserved.
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

#import "WarningNote.h"

#import "helper.h"

#import "MenuController.h"

extern MenuController * gMC;

@implementation WarningNote

-(WarningNote *) initWithHeadline: (NSString *)           theHeadline
                          message: (NSAttributedString *) theMessage
                    preferenceKey: (NSString *)           thePreferenceKey {

    self = [super init];
    if (  self  ) {
        headline      = [theHeadline retain];
        message       = [theMessage retain];
        preferenceKey = [thePreferenceKey retain];
    }

    return self;
}

-(NSString *) headline {

    return [[headline retain] autorelease];
}

-(NSString *) preferenceKey {

    return [[preferenceKey retain] autorelease];
}


-(void) showWarning: (id) sender {

    (void) sender;
    
    TBShowAlertWindowExtended(NSLocalizedString(@"Tunnelblick", @"Window title"), message, preferenceKey, preferenceKey, @1, nil, nil, NO);

    BOOL appUpdate = [preferenceKey isEqualToString: @"-skipWarningAboutAppUpdateError"];
    BOOL vpnUpdate = [preferenceKey isEqualToString: @"-skipWarningAboutVpnUpdateError"];

    if (   appUpdate
        || vpnUpdate  ) {
        [gMC tbUpdateClearErrorInAppUpdate: [NSNumber numberWithBool: appUpdate]];
    }

    TBShowAlertWindowRemoveFromCache(preferenceKey, [message string]);
}

-(void) dealloc {
    
    [headline      release];
    [message       release];
    [preferenceKey release];
    [index         release];
    
    [super dealloc];
}

@end
