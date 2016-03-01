/*
 * Copyright 2004 Angelo Laub
 * Fixes by Dirk Theisen <dirk@objectpark.org> 
* Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2016. All rights reserved.

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

-(id) initWithService:(NSString *)sName
      withAccountName:(NSString *)aName
{
	if (  (sName == nil)
        | (aName == nil)  )
        return nil;
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
	// Returns a password if it exists.
	// Returns an empty string if the Keychain can be accessed but the password is empty or does not exist
	// Returns nil if the Keychain can't be accessed (user cancelled)
	
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
    if (  status == noErr  ) {
        if (  passLength != 0) {
            NSString *returnPassword = [[[NSString alloc] initWithBytes:passData length:passLength encoding:NSUTF8StringEncoding] autorelease];
            SecKeychainItemFreeContent(NULL,passData);
            NSLog(@"Keychain item retrieved successfully for service = '%@' account = '%@'", serviceName, accountName);
            return returnPassword;            
        } else {
            SecKeychainItemFreeContent(NULL,passData);
            NSLog(@"Zero-length Keychain item retrieved for service = '%@' account = '%@'", serviceName, accountName);
			return @"";
        }
    } else {
        if (  status == errKCItemNotFound  ) {
            NSLog(@"Can't retrieve Keychain item for service = '%@' account = '%@' because it does not exist", serviceName, accountName);
			return @"";
        } else if (   (status == errSecAuthFailed)  // -128 found by user experimentation -- not in Keychain Services Reference or CSSM references,
                   || (status == -128)  ) {         // but it is 'userCanceledErr' in OS 9 and earlier (!)
            NSLog(@"Can't retrieve Keychain item for service = '%@' account = '%@' because access to the Keychain was cancelled by the user", serviceName, accountName);
			return nil;
        } else {
            // Apple docs are inconsistent; Xcode says SecCopyErrorMessageString is available on 10.5+, Keychain Services Reference says 10.3+, so we play it safe
			if (  runningOnLeopardOrNewer()  ) {
                CFStringRef errMsg = SecCopyErrorMessageString(status, NULL);
				NSLog(@"Can't retrieve Keychain item for service = '%@' account = '%@'; status was %ld; error was '%@'", serviceName, accountName, (long) status, (NSString *)errMsg);
				if (  errMsg  ) {
                    CFRelease(errMsg);
                }
            } else {
				NSLog(@"Can't retrieve Keychain item for service = '%@' account = '%@'; status was %ld", serviceName, accountName, (long) status);
			}
			return @"";
        }
    }
}

- (int)setPassword:(NSString *)password
{
    if (  ! password  ) {
        NSLog(@"Attempt to add nil Keychain item for service = '%@' account = '%@'", serviceName, accountName);
        return -1;
    }
    
    const char *cPassword = [password UTF8String];
    const char* service   = [serviceName UTF8String];
    const char* account   = [accountName UTF8String];
    
    OSStatus status = SecKeychainAddGenericPassword(NULL,              // default keychain
                                                    strlen(service),   // length of service name
                                                    service,           // service name
                                                    strlen(account),   // length of account name
                                                    account,           // account name
                                                    strlen(cPassword), // length of password
                                                    cPassword,         // pointer to password data
                                                    NULL);             // we need no item reference
    
    if (  status != noErr  ) {
        NSLog(@"Can't add Keychain item for service = '%@' account = '%@'; status was %ld; error was %ld:\n'%s'", serviceName, accountName, (long) status, (long) errno, strerror(errno));
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
	if (  status == noErr  ) {
        status = SecKeychainItemDelete(itemRef);
        if (  status != noErr  ) {
            NSLog(@"Can't delete Keychain item for service = '%@' account = '%@' after finding it; status was %ld; error was %ld:\n'%s'", serviceName, accountName, (long) status, (long) errno, strerror(errno));
        }
    } else {
        if (  status == errKCItemNotFound  ) {
            NSLog(@"Can't find Keychain item to delete for service = '%@' account = '%@' because it does not exist", serviceName, accountName);
        } else {
            NSLog(@"Can't find Keychain item to delete for service = '%@' account = '%@'; status was %ld; error was %ld:\n'%s'", serviceName, accountName, (long) status, (long) errno, strerror(errno));
        }
    }
}
@end
