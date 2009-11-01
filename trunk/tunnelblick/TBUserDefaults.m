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

#import "TBUserDefaults.h"


@implementation TBUserDefaults

-(TBUserDefaults *) initWithDefaultsDictionary: (NSDictionary *) inDict
{
    if ( ! [super init] ) {
        return nil;
    }
    
    userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults: [[NSMutableDictionary alloc] init]];

    forcedDefaults = [inDict copy];

    return self;
}

-(void) dealloc
{
    [forcedDefaults release];
    
    [super dealloc];
}

-(BOOL) canChangeValueForKey: (NSString *) key     // Returns YES if key's value can be modified, NO if it can't (because it is in Deploy)
{
    if (  ! [forcedDefaults objectForKey: key]  ) {
        return YES;
    }
    
    return NO;
}

-(BOOL) boolForKey: (NSString *) key
{
    if (  ! forcedDefaults  ) {
        return [userDefaults boolForKey: key];
    }
    NSNumber * value = [forcedDefaults objectForKey: key];
    if (  value == nil  ) {
        return [userDefaults boolForKey: key];
    }
    return [value boolValue];
}

-(NSString *) objectForKey: (id) key
{
    if (  ! forcedDefaults  ) {
        return [userDefaults objectForKey: key];
    }
    id value = [forcedDefaults objectForKey: key];
    if (  value == nil  ) {
        return [userDefaults objectForKey: key];
    }
    
    return value;
}

-(void) setBool: (BOOL) value forKey: (NSString *) key
{
    if (  ! [forcedDefaults objectForKey: key]  ) {
        [userDefaults setBool: value forKey: key];
        [userDefaults synchronize];
    }
}

-(void) setObject: (id) value forKey: (NSString *) key
{
    if (  ! [forcedDefaults objectForKey: key]  ) {
        [userDefaults setObject: value forKey: key];
        [userDefaults synchronize];
    }
}

-(void) removeObjectForKey: (NSString *) key
{
    if (  forcedDefaults  ) {
        NSLog(@"removeObjectForKey: invoked while using Resources/Deploy/forced-preferences.plist");
    } else {
        [userDefaults removeObjectForKey: key];
        [userDefaults synchronize];
    }
}


-(void) synchronize
{
        [userDefaults synchronize];    // (Must synchronize preferences that aren't in Resources/Deploy/forced-preferences.plist)
}

@end
