/*
 * Copyright (c) 2019 Jonathan K. Bullard. All rights reserved.
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

#import "NSDate+TB.h"

#import "defines.h"

@implementation NSDate(TB)

+(NSDate *) dateWithOpenvpnMachineReadableLogRepresentation: (NSString *) seconds {
	
	// Returns a date from a string containing the number of seconds since the epoch.
	//
	// Example input: "1551973883.714408"

	NSTimeInterval value = [seconds doubleValue];
	NSDate * date = [NSDate dateWithTimeIntervalSince1970: value];
	
	return date;
}

-(NSString *) openvpnMachineReadableLogRepresentation {
	
	// Returns a.b where a is the ten-digit integer seconds since the epoch,
	//               and b is the six digit integer microseconds
	//         (example: "1551973883.714408")
	
	NSTimeInterval sinceEpoch = [self timeIntervalSince1970];
	NSString * date = [NSString stringWithFormat: @"%010.6f", sinceEpoch];
	
	return date;
}

-(NSString *) tunnelblickUserLogRepresentationWithoutMicroseconds {
	
	// Returns yyyy-mm-dd hh:mm:ss (example: "2019-03-08 07:28:20")
	
	NSDateFormatter * df = [[[NSDateFormatter alloc] init] autorelease];
    [df setLocale: [NSLocale localeWithLocaleIdentifier: @"en_US_POSIX"]];
	[df setDateFormat: @"yyyy-MM-dd HH:mm:ss"];
	NSString * date = [df stringFromDate: self];
	
	return date;
}

-(NSString *) tunnelblickUserLogRepresentationWithMicroseconds {
	
	// Returns yyyy-mm-dd hh:mm:ss.SSSSSS (example: "2019-03-08 07:28:20.003447")
	//
	// There's a problem with NSDateFormatter: it truncates to milliseconds
	// (see https://stackoverflow.com/questions/23684727/nsdateformatter-milliseconds-bug).
	//
	// This is probably because the double that holds dates is only good for 15 to 17
	// significant decimal digits precision (2^−53 ≈ 1.11 × 10^−16). With a 10-digit number
	// of seconds, only five digits are left for the fraction of a second. But for our
	// purposes (displaying log entries) the exact microsecond value isn't important and
	// it seems to make more sense to show microseconds than 1/100,000 seconds.
	//
	// We use NSDateFormatter only for the date and time with seconds part of the output,
	// and create our own representation of the microseconds.
	
	// Isolate the fractional part of the seconds, then get microseconds (rounded)
	NSTimeInterval integerPart;
	NSTimeInterval fractionalPart = modf([self timeIntervalSince1970], &integerPart);
	NSUInteger microseconds = round(fractionalPart * 1000000.0);
	
	NSString * date = [NSString stringWithFormat: @"%@.%06lu",
					   [self tunnelblickUserLogRepresentationWithoutMicroseconds],
					   microseconds];
	
	return date;
}

-(NSString *) tunnelblickUserLogRepresentation {

	return (  (TB_LOG_DATE_TIME_WIDTH == 19)
			? [self tunnelblickUserLogRepresentationWithoutMicroseconds]
			: [self tunnelblickUserLogRepresentationWithMicroseconds]
			);
}

-(NSString *) tunnelblickFilenameRepresentation {

	NSMutableString * withColons = [[[self tunnelblickUserLogRepresentation] mutableCopy] autorelease];
	[withColons replaceOccurrencesOfString: @":" withString: @"." options: 0 range: NSMakeRange(0, [withColons length])];
	
	return [[withColons copy] autorelease];
}

@end
