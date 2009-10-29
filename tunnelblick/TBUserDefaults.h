/*
 * Copyright (c) 2009 Jonathan Bullard
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#import <Cocoa/Cocoa.h>

// This class is used to override the user's standard preferences if the Resources/Deploy folder
// is being used for configurations and it contains a "forced-preferences.plist" file.
//
// Preferences in that file are read-only.
//
// If Resources/Deploy is not being used for configurations,
// or it doesn't contain "forced-preferences.plist",
// or a particular preference is not specified in that file,
// Then the user's standard preferences are used.
// 
// THIS CLASS IMPLEMENTS A METHOD NOT FOUND IN NSUserDefaults:
//
//      canChangeValueForKey:
//
// It returns TRUE if the user's standard preference for that key will be used (because the value can be modified)
// It returns FALSE if the preference is contained in /Resources/Deploy/forced-preferences.plist (because the value cannot be modified)

@interface TBUserDefaults : NSObject {

    NSDictionary   * forcedDefaults;                // Preferences from Deploy
    NSUserDefaults * userDefaults;                  // [NSUserDefaults standardUserDefaults]

}

-(TBUserDefaults *) initWithDefaultsDictionary: (NSDictionary *)    inDict;     // Sets up to override user's standard preferences (if nil, standard user's preferences will be used)

-(BOOL)             canChangeValueForKey:   (NSString *)            key;        // Returns TRUE if key can be modified, FALSE if it can't (because it being overridden)

// These are just like the corresponding NSUserPreferences methods
-(BOOL)             boolForKey:             (NSString *)            key;
-(NSString *)       objectForKey:           (id)                    key;

-(void)             setBool:                (BOOL)                  value   forKey: (NSString *)    key;
-(void)             setObject:              (id)                    value   forKey: (NSString *)    key;

-(void)             removeObjectForKey:     (NSString *)            key;

-(void)             synchronize;

@end
