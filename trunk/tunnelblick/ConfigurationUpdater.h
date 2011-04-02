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


#import <Cocoa/Cocoa.h>
#import "Sparkle/SUUpdater.h"


@interface ConfigurationUpdater : NSObject {
    NSString       * cfgBundlePath;
    SUUpdater      * cfgUpdater;
    NSBundle       * cfgBundle;
    NSURL          * cfgFeedURL;
    NSTimeInterval   cfgCheckInterval;
}

// Sets up the updater for later use
-(void) setup;

// Starts the updater checking for updates
// withUI should be TRUE to present the UI, FALSE to check in the background
-(void) startWithUI: (BOOL) withUI;

@end
