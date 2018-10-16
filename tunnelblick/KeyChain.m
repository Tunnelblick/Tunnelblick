/*
 * Copyright 2004 Angelo Laub
 * Fixes by Dirk Theisen <dirk@objectpark.org> 
* Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2016, 2018. All rights reserved.

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

#import "KeyChain.h"

#import <Security/Security.h>

#import "helper.h"

@implementation KeyChain

-(void) logNonstatusMessage: (NSString *) message {
	
	appendLog([NSString stringWithFormat: @"%@: service = '%@'; account = '%@'",
			   message, serviceName, accountName]);
}

-(void) logStatus: (OSStatus) status message: (NSString *) message {
	
	CFStringRef cfS = SecCopyErrorMessageString(status, NULL);
	NSString * statusString = [[(__bridge NSString *)cfS copy] autorelease];
	CFRelease(cfS);
	
	appendLog([NSString stringWithFormat: @"%@: service = '%@'; account = '%@'; status was %d: '%@'",
			   message, serviceName, accountName, status, statusString]);
}

-(id) initWithService:(NSString *)sName
      withAccountName:(NSString *)aName
{
	if (  (sName == nil)
		| (aName == nil)  ) {
        return nil;
	}
	
    if (  (self = [super init])  ) {
        serviceName = [sName retain];
        accountName = [aName retain];
    }
	
    return self;
}

- (NSString *)accountName {
    return [[accountName retain] autorelease];
}

- (void)setAccountName:(NSString *)value {
    if (accountName != value) {
        [accountName release];
        accountName = [value copy];
    }
}


- (void) dealloc {
    
    [accountName release]; accountName = nil;
    [serviceName release]; serviceName = nil;
    
    [super dealloc];
}

- (NSString*) password 
{
	// Returns nil if the user cancelled (if asked for authorization to access the Keychain),
	// Returns an empty string if the Keychain cannot be accessed or the password is empty or does not exist,
	// Otherwise, returns the password.
	
	char *passData;
    UInt32 passLength = 0;
    const char* service   = [serviceName UTF8String];
    const char* account   = [accountName UTF8String];
    
    OSStatus status = SecKeychainFindGenericPassword(NULL,              // default keychain
                                                     strlen(service),   // length of service name
                                                     service,           // service name
                                                     strlen(account),   // length of account name
                                                     account,           // account name
                                                     &passLength,       // length of password
                                                     (void**)&passData, // address of password data as void **
                                                     NULL               // we need no item reference
                                                     );
    if (  status == errSecSuccess  ) {
        if (  passLength != 0) {
            NSString *returnPassword = [[[NSString alloc] initWithBytes:passData length:passLength encoding:NSUTF8StringEncoding] autorelease];
            SecKeychainItemFreeContent(NULL,passData);
			if (  returnPassword == nil  ) {
				[self logNonstatusMessage:@"Keychain item was not UTF-8; returning an empty password"];
				return @"";
			}
            return returnPassword;
        } else {
            SecKeychainItemFreeContent(NULL,passData);
            [self logNonstatusMessage:@"Empty Keychain item retrieved successfully"];
			return @"";
        }
    } else {
        if (  status == errSecUserCanceled  ) {
            [self logStatus: status message: @"Access to the Keychain was cancelled by the user"];
			return nil;
        } else {
            [self logStatus: status message:@"Can't retrieve Keychain item"];
			return @"";
        }
    }
}

- (int)setPassword:(NSString *)password
{
    if (  ! password  ) {
        [self logNonstatusMessage: @"Can't add nil Keychain item"];
        return -1;
    }
    
    const char * cPassword = [password UTF8String];
    const char * service   = [serviceName UTF8String];
    const char * account   = [accountName UTF8String];
    
    OSStatus status = SecKeychainAddGenericPassword(NULL,              // default keychain
                                                    strlen(service),   // length of service name
                                                    service,           // service name
                                                    strlen(account),   // length of account name
                                                    account,           // account name
                                                    strlen(cPassword), // length of password
                                                    cPassword,         // pointer to password data
                                                    NULL);             // we need no item reference
    
    if (  status != errSecSuccess  ) {
        [self logStatus: status message: @"Can't add Keychain item"];
    }
    
    return(status);
}

-(void)deletePassword
{
	SecKeychainItemRef itemRef;
    const char* service   = [serviceName UTF8String];
    const char* account   = [accountName UTF8String];
    
    OSStatus status = SecKeychainFindGenericPassword(NULL,             // default keychain
                                                      strlen(service), // length of service name
                                                      service,         // service name
                                                      strlen(account), // length of account name
                                                      account,         // account name
                                                      NULL,            // length of password
                                                      NULL,            // address of password data as void **
                                                      &itemRef               
                                                      );
	if (  status == errSecSuccess  ) {
        status = SecKeychainItemDelete(itemRef);
        if (  status != errSecSuccess  ) {
            [self logStatus: status message: @"Can't delete Keychain item"];
        }
    } else {
		[self logStatus: status message: @"Can't find Keychain item to delete"];
    }
}
@end
