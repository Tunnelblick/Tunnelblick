/*
 *  Copyright (c) 2005, 2006, 2007, 2008, 2009 Angelo Laub
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

#import "VPNConnection.h"

NSString     * escaped              (NSString *string);
NSDictionary * getOpenVPNVersion    (void);
NSString     * openVPNVersion       (void);
NSDictionary * parseVersion         (NSString * string);
NSRange        rangeOfDigits        (NSString * s);
int            TBRunAlertPanel      (NSString * title,
                                     NSString * msg,
                                     NSString * defaultButtonLabel,
                                     NSString * alternateButtonLabel,
                                     NSString * otherButtonLabel);
NSString     * tunnelblickVersion   (void);
BOOL           useDNSStatus         (id connection);
