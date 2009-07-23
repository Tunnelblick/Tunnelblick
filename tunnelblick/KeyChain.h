/*
 * Copyright (c) 2004 Angelo Laub
 *
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
#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>
#import <CoreServices/CoreServices.h>


@interface KeyChain : NSObject {
    NSString  * accountName;	
    NSString  * serviceName;
}

-(NSString *)   accountName;
-(void)         deletePassword;
-(id)           initWithService:    (NSString *) serviceName    withAccountName: (NSString *) accountName;
-(NSString *)   password;
-(void)         setAccountName:     (NSString *) value;
-(int)          setPassword:        (NSString *) password;

@end
