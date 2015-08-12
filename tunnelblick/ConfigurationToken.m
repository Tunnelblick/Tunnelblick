/*
 * Copyright 2012, 2013 Jonathan K. Bullard. All rights reserved.
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

#import "ConfigurationToken.h"


@implementation ConfigurationToken

-(id) init
{
	self = [super init];
	if (  self  ) {
		range = NSMakeRange(NSNotFound, 0);
		string = nil;
	}
	
	return self;
}

-(id) initWithRange: (NSRange)    theRange
           inString: (NSString *) theString
         lineNumber: (unsigned)   theLineNumber
{
	self = [super init];
	if (  self  ) {
		range      = theRange;
		string     = [theString retain];
        lineNumber = theLineNumber;
	}
	
	return self;
}

-(void) dealloc
{
    [string release]; string = nil;
    
    [super dealloc];
}

-(BOOL) isLinefeed
{
    return [[string substringWithRange: range] isEqualToString: @"\n"];
}

-(NSString *) description
{
	if (  string  ) {
		if (  range.location != NSNotFound  ) {
			NSString * stringToDisplay = [string substringWithRange: range];
			if (  [stringToDisplay isEqualToString: @"\n"]  ) {
				stringToDisplay = @"\\n";
			}
			return [NSString stringWithFormat: @"Token {%lu,%lu}:  '%@'",
					(unsigned long) range.location,
					(unsigned long) range.length,
					stringToDisplay];
		} else {
			return @"ConfigurationToken range not set";
		}
	} else {
		return @"ConfigurationToken string not set";
	}
}

-(NSString *) stringValue
{
    return [string substringWithRange: range];
}

-(NSUInteger) location
{
    return range.location;
}

-(NSUInteger) length
{
    return range.length;
}

-(NSRange) range
{
    return range;
}

-(unsigned) lineNumber
{
    return lineNumber;
}

@end
