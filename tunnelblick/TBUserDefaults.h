/*
 * Copyright 2009, 2010, 2011, 2012, 2013, 2014, 2015 Jonathan K. Bullard. All rights reserved.
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

// This class is used as a substitute for NSUserDefaults and implements an augmented subset of its methods.
//
// It implements two levels of read-only dictionaries that can override the user's standard preferences; a "primary" dictionary and a "forced" dictionary.
// These dictionaries may contain wildcards (i.e, a "*" as the first character in a key).
//
// When looking for a value for a key:
//
//     If the key is found in the "primary" dictionary or the suffix of the key matches the rest of an entry in the "primary" dictionary that begins with '*'
//     then the value from the "primary" dictionary is returned.
//
//     Otherwise, if the key is found in the "forced" dictionary  or the suffix of the key matches the rest of an entry in the "forced" dictionary that begins with '*'
//     then the value from the "forced" dictionary is returned.
//
//     Otherwise, if a key is found in the user's preferences,
//     then the value from the user's preferences is returned.
//
//     Otherwise, nil is returned.
// 
// THIS CLASS IMPLEMENTS SEVERAL METHODS NOT FOUND IN NSUserDefaults

#import "defines.h"

@interface TBUserDefaults : NSObject {
    
    NSDictionary   * primaryDefaults; // nil, or an NSDictionary of preferences from L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH
    
    NSDictionary   * forcedDefaults;  // nil, or an NSDictionary of preferences from /Deploy/forced-preferences.plist
    
    NSUserDefaults * userDefaults;    // [NSUserDefaults standardUserDefaults]
}

-(TBUserDefaults *) initWithPrimaryDictionary: (NSDictionary *) inPrimary
                        andDeployedDictionary: (NSDictionary *) inForced;

// The following methods are implemented. They are like the corresponding NSUserPreferences methods

-(BOOL) boolForKey:                 (NSString *)        key;

-(id)   objectForKey:               (NSString *)        key;

-(void) setBool:                    (BOOL)              value
         forKey:                    (NSString *)        key;

-(void) setObject:                  (id)                value
           forKey:                  (NSString *)        key;

-(void) removeObjectForKey:         (NSString *)        key;

// The following methods are extensions used by Tunnelblick

-(BOOL) canChangeValueForKey:                 (NSString *) key;    // Returns TRUE if key can be modified, FALSE if it can't (because it being overridden)

-(NSString *) forcedStringForKey:             (NSString *) key;    // Returns the value of a forced preference if it is a string, nil otherwise

-(BOOL) isTrueForcedForKey:                   (NSString *) key;    // Returns TRUE if a preference for the key is forced to TRUE, false otherwise

-(BOOL) copyPreferencesFrom:                  (NSString *) sourceDisplayName
                         to:                  (NSString *) targetDisplayName;

-(BOOL) movePreferencesFrom:                  (NSString *) sourceDisplayName
                         to:                  (NSString *) targetDisplayName;

-(BOOL) removePreferencesFor:                 (NSString *) displayName;

-(void) removeAllObjectsWithSuffix:           (NSString *) key;

-(void) replacePrefixOfPreferenceValuesThatHavePrefix: (NSString *) old with: (NSString *) new;

-(NSArray *) valuesForPreferencesSuffixedWith:(NSString *) key;

-(void) scanForUnknownPreferencesInDictionary: (NSDictionary *) dict
                                  displayName: (NSString *) dictName;

-(BOOL) preferenceExistsForKey:   (NSString * ) key;

-(BOOL) boolWithDefaultYesForKey: (NSString *) key;

-(NSString *) stringForKey:       (NSString *) key;

-(NSArray *) arrayForKey:         (NSString *) key;

-(NSDate *) dateForKey:           (NSString *) key;

-(float) floatForKey: (NSString *) key
             default: (float)      defaultValue
                 min: (float)      minValue
                 max: (float)      maxValue;

-(NSTimeInterval) timeIntervalForKey: (NSString *)     key
                             default: (NSTimeInterval) defaultValue
                                 min: (NSTimeInterval) minValue
                                 max: (NSTimeInterval) maxValue;

-(unsigned) unsignedIntForKey: (NSString *) key
                      default: (unsigned)   defaultValue
                          min: (unsigned)   minValue
                          max: (unsigned)   maxValue;

-(unsigned long long) unsignedLongLongForKey: (NSString *)         key
                                     default: (unsigned long long) defaultValue
                                         min: (unsigned long long) minValue
                                         max: (unsigned long long) maxValue;

-(unsigned) numberOfConfigsInCredentialsGroup: (NSString *) groupName;

-(NSString *) removeNamedCredentialsGroup: (NSString *) groupName;

-(NSString *) addNamedCredentialsGroup: (NSString *) groupName;

-(NSArray *) sortedCredentialsGroups;

TBPROPERTY_WRITEONLY(NSDictionary *, primaryDefaults, setPrimaryDefaults)

@end
