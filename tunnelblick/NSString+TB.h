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

#import <Foundation/Foundation.h>


@interface NSString(TB)

-(NSComparisonResult) caseInsensitiveNumericCompare: (NSString*) theString;

-(NSComparisonResult) tunnelblickVersionCompare: (NSString *) theString;

-(BOOL) containsOnlyCharactersInString: (NSString *) allowed;

-(NSString *) pathEdition;

-(NSString *) stringByAppendingPathEdition: (NSString *) edition;

-(NSString *) stringByDeletingPathEdition;

-(unsigned) unsignedIntValue;

@end
