/*
 * Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2018, 2019, 2020, 2021, 2023, 2025, 2026 Jonathan K. Bullard. All rights reserved.
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

#import <Foundation/Foundation.h>

// Forced per-configuration keys are the display name plus a known suffix,
// for example "WorkVPNautoConnect". The suffix is not the display name.

__attribute__((unused))
static inline BOOL forcedPreferenceKeyIsForDisplayName(NSString * key, NSString * displayName, NSArray * knownSuffixes) {

    if (   (key.length == 0)
        || (displayName.length == 0)  ) {
        return NO;
    }
    if (  ! [key hasPrefix: displayName]  ) {
        return NO;
    }
    NSString * suffix = [key substringFromIndex: displayName.length];
    return [knownSuffixes containsObject: suffix];
}
