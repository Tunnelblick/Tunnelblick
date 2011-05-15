/*
 * Copyright 2009, 2010 Jonathan Bullard
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

// Note: this class is DAEMON-SAFE IF it is initialized with "usingUserDefaults" set to NO.
//
// This class is used as a substitute for NSUserDefaults and implements an augmented subset of its methods.
//
// It implements two levels of read-only dictionaries that can override the user's standard preferences,
// a "forced" dictionary and a "secondary" dictionary.
//
// The "forced" dictionary may contain wildcards (i.e, a "*" as the first character in a key).
//
// When looking for the value of a key:
//     If a key is found in the "forced" dictionary or a key matches a wildcard
//     Then the value from the "forced" dictionary is returned.
//
//     Otherwise, if a key is found in the "secondary" dictionary, then the value from it is returned.
//
//     Otherwise, if the class was initialized with "usingUserDefaults" set TRUE
//                then the value from the user's standard preferences is returned.
//     Otherwise, nil is returned.
// 
// THIS CLASS IMPLEMENTS A METHOD NOT FOUND IN NSUserDefaults:
//
//      canChangeValueForKey: (NSString *) key
//
// It returns FALSE if the value of the key is is specified by the "forced dictionary" (including wildcard matches)
//                  or by the "secondary" dictionary, or if the userDefaults preferences are not being used
// It returns TRUE otherwise

@interface TBUserDefaults : NSObject {

    NSDictionary   * forcedDefaults;                // nil, or an NSDictionary of preferences which may contain wildcards   -- used by tunnelblickd and the GUI
    NSDictionary   * secondaryDefaults;             // nil, or an NSDictionary of preferences (from Shared Info.plists)     -- used by tunnelblickd
    NSUserDefaults * userDefaults;                  // nil, or [NSUserDefaults standardUserDefaults]                        -- used by the GUI
}

-(TBUserDefaults *) initWithForcedDictionary:   (NSDictionary *)    inForced
                      andSecondaryDictionary:   (NSDictionary *)    inSecondary
                           usingUserDefaults:   (BOOL)              inUseUserDefaults;

// The following methods are implemented. They are like the corresponding NSUserPreferences methods

-(BOOL)             canChangeValueForKey:       (NSString *)        key;    // Returns TRUE if key can be modified, FALSE if it can't (because it being overridden)

-(BOOL)             boolForKey:                 (NSString *)        key;    // Note: returns [object boolValue], which works only on booleans until OS X 10.5

-(id)               objectForKey:               (NSString *)        key;

-(void)             setBool:                    (BOOL)              value
                     forKey:                    (NSString *)        key;

-(void)             setObject:                  (id)                value
                       forKey:                  (NSString *)        key;

-(void)             removeObjectForKey:         (NSString *)        key;

-(void)             removeAllObjectsWithSuffix: (NSString *)        key;

-(void)             synchronize;

@end
