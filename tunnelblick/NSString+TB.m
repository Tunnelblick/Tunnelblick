/*
 * Copyright (c) 2011, 2012, 2014, 2018 Jonathan K. Bullard. All rights reserved.
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

#import "NSString+TB.h"


@implementation NSString(TB)

-(NSComparisonResult) caseInsensitiveNumericCompare: (NSString*) theString {
    
    return [self compare: theString options: NSCaseInsensitiveSearch | NSNumericSearch];
}

-(NSComparisonResult) versionCompare: (NSString *) other {

	// Compares two version strings, each of the form a.b.c...
	// Pads on the right with ".0" if necessary, so 1 and 1.0 are considered the same.
	
	// Separate each string into its components
 	NSMutableArray * selfParts  = [[[self  componentsSeparatedByString: @"."] mutableCopy] autorelease];
	NSMutableArray * otherParts = [[[other componentsSeparatedByString: @"."] mutableCopy] autorelease];

	// Force them to have the same number of components by appending ".0" as needed
	while (  [selfParts count] < [otherParts count]  ) {
		[selfParts addObject: @"0"];
	}
	while (  [otherParts count] < [selfParts count]  ) {
		[otherParts addObject: @"0"];
	}

	// Compare the components until there's a mismatch
	NSUInteger ix;
	for (  ix=0; ix<[selfParts count]; ix++  ) {

		NSComparisonResult r = [[selfParts objectAtIndex: ix] compare: [otherParts objectAtIndex: ix] options: NSNumericSearch];
		
		if (  r == NSOrderedSame  ) {

			continue;		// Component is the same, test the next component
		}
		
		return r;			// Component is different, return indicating the difference
	}

	return NSOrderedSame;	// All components are the same
}

-(NSComparisonResult) tunnelblickVersionCompare: (NSString *) other {

	// Compares Tunnelblick version numbers such as 3.4.5 and 3.4.5beta03.
	//
	// (Works for the old 3.0b9 - 3.0b28 version numbers, too, because all of them are 3.0bNN)
	//
	// MAY NOT WORK for a version number that contains 'beta' two or more times, so it logs that. (We don't do that, anyway!)
	
	if (  ! other  ) {
		return NSOrderedDescending;	// Anything is larger than nil
	}
	
	if (  [other isEqualToString: self]  ) {
		return NSOrderedSame;
	}
	
	NSArray * selfParts  = [self  componentsSeparatedByString: @"beta"];
	NSArray * otherParts = [other componentsSeparatedByString: @"beta"];
	NSComparisonResult r = [[selfParts firstObject] versionCompare: [otherParts firstObject]];
	if (  r != NSOrderedSame  ) {
		return r;	// 1 < 2 or 2 > 1
	}
	
	if (   ([selfParts  count] > 2)
		|| ([otherParts count] > 2)  ) {
		NSLog(@"One or more version numbers has 'beta' more than once: '%@' and '%@'", self, other);
	}
	
	// Everything before 'beta' (if it is present) is the same
	
	if (  [selfParts count] == 1  ) {
		if (  [otherParts count] == 1  ) {
			return NSOrderedSame;			// 1.2.3 == 1.2.3 (neither has 'beta')
		}
		
		return NSOrderedDescending;			// 1.2.3 > 1.2.3betaANYTHING
	}
	
	if (  [otherParts count] == 1  ) {
		return NSOrderedAscending;			// 1.2.3betaANYTHING < 1.2.3
	}
	
	// 1.2.3betaABC and 1.2.3betaDEF, so compare ABC to DEF
	return [[selfParts objectAtIndex: 1] compare: [otherParts objectAtIndex: 1] options: NSNumericSearch];
}

-(BOOL) containsOnlyCharactersInString: (NSString *) allowed {
    
    unsigned i;
    for (  i=0; i<[self length]; i++  ) {
        unichar ch = [self characterAtIndex: i];
        if ( strchr([allowed UTF8String], ch) == NULL  ) {
            return NO;
        }
    }
    
    return YES;
}

-(NSString *) pathEdition {
    
    NSRange rng = [self rangeOfString: @"_" options: NSBackwardsSearch];
    if (  rng.length == 0  ) {
        return nil;
    }
    
    NSString * edition = [self substringFromIndex: rng.location + 1];
    
    if (  ! [edition containsOnlyCharactersInString: @"0123456789"]  ) {
        NSLog(@"Invalid edition (illegal characters) in '%@'", self);
        return nil;
    }
    
    if (  [edition length] == 0  ) {
        NSLog(@"Invalid edition (empty string)");
        return nil;
    }
    
    return edition;
}

-(NSString *) stringByAppendingPathEdition: (NSString *) edition {
    
    NSString * s = [[self stringByAppendingString: @"_"] stringByAppendingString: edition];
    return s;
}

-(NSString *) stringByDeletingPathEdition {
    
    NSRange rng = [self rangeOfString: @"_" options: NSBackwardsSearch];
    if (  rng.length == 0  ) {
        return [NSString stringWithString: self];
    }
    
    NSString * edition = [self substringToIndex: rng.location];
    return edition;
}

-(unsigned) unsignedIntValue {
    
    int i = [self intValue];
    if (  i < 0  ) {
        NSLog(@"unsignedIntValue: Negative value %d is invalid in this context", i);
        return UINT_MAX;
    }
    
    return (unsigned) i;
}

@end
