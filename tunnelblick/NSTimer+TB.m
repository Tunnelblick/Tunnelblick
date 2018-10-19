/*
 * Copyright (c) 2013, 2014 Jonathan K. Bullard. All rights reserved.
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

//*************************************************************************************************
//
// The NSTimer setTolerance: method was introduced in macOS 10.9 ("Mavericks")

#import "NSTimer+TB.h"

#ifndef MAC_OS_X_VERSION_10_9
    @interface NSTimer (NSTimer_Private)
    - (void) setTolerance: (NSTimeInterval) tolerance;
    @end
#else
    #if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_9
        @interface NSTimer (NSTimer_Private)
        - (void) setTolerance: (NSTimeInterval) tolerance;
        @end
    #endif
#endif

@implementation NSTimer (TB)

-(void) tbSetTolerance: (NSTimeInterval) tolerance {
    
    if (  [self respondsToSelector: @selector(setTolerance:)]  ) {
        if (  tolerance < 0.0  ) {
            NSTimeInterval interval = [self timeInterval];
            if (  interval < 5  ) {
                tolerance = 0.1 * interval;
            } else {
                tolerance = 0.5;
            }
        }
        [self setTolerance: tolerance];
    }
}

@end
