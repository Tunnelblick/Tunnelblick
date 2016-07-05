/*
 * Copyright 2015 Jonathan K. Bullard. All rights reserved.
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


@interface UIHelper : NSObject

// Used to set up buttons that are flush right to something

+(NSString *)   appendRTLIfRTLLanguage: (NSString *) string;

+(unsigned int) detailsWindowsViewIndexFromPreferencesWithCount: (unsigned int) count;

+(void)         makeAllAsWideAsWidest: (NSArray *) list
								shift: (BOOL)      shift;

+(BOOL)         languageAtLaunchWasRTL;

+(CGFloat)      setTitle: (NSString *) newTitle
			   ofControl: (id)         theControl
			 frameHolder: (id)         frameHolder
				   shift: (BOOL)       shift
				  narrow: (BOOL)       narrow
				  enable: (BOOL)       enable;

+(CGFloat)      setTitle: (NSString *) newTitle
			   ofControl: (id)         theControl
				   shift: (BOOL)       shift 
				  narrow: (BOOL)       narrow
				  enable: (BOOL)       enabled;

+(void)         shiftControl: (id) theControl by: (CGFloat) amount reverse: (BOOL) reverse;

+(void)         showAlertWindow: (NSDictionary *) dict;

+(void)         showSuccessNotificationTitle: (NSString *) title
                                         msg: (NSString *) msg;

@end

