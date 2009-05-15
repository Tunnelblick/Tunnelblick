/*
 * Copyright (c) 2004 Angelo Laub
 * Fixes by Dirk Theisen <dirk@objectpark.org> 
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

#import "KeyChain.h"

@implementation KeyChain

-(id) initWithService:(NSString *)sName
      withAccountName:(NSString *)aName
{
	if (sName == nil | aName == nil) return nil;
    if (self = [super init]) {
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


- (void) dealloc
{
    [serviceName release];
    [accountName release];
    [super dealloc];
}

- (NSString*) password 
{
    char *passData;
    UInt32 passLength = 0;
    const char* service   = [serviceName UTF8String];
    const char* account   = [accountName UTF8String];
    
    OSStatus status1 = SecKeychainFindGenericPassword(NULL,              // default keychain
                                                      strlen(service),   // length of service name
                                                      service,           // service name
                                                      strlen(account),   // length of account name
                                                      account,           // account name
                                                      &passLength,       // length of password
                                                      (void**)&passData, // address of password data as void **
                                                      NULL               // we need no item reference
                                                      );
    if(passLength && status1 == noErr) {
        NSString *returnPassword = [[[NSString alloc] initWithBytes:passData length:passLength encoding:NSUTF8StringEncoding] autorelease];
        SecKeychainItemFreeContent(NULL,passData);	
        return returnPassword;
    }
    return nil;
}

- (int)setPassword:(NSString *)password
{
    const char *cPassword = [password UTF8String];
    const char* service   = [serviceName UTF8String];
    const char* account   = [accountName UTF8String];
    
    OSStatus status = SecKeychainAddGenericPassword(NULL,		// default keychain
                                                    strlen(service),	// length of service name
                                                    service,		// service name
                                                    strlen(account),	// length of account name
                                                    account,		// account name
                                                    strlen(cPassword),	// length of password
                                                    cPassword,		// pointer to password data
                                                    NULL);		// we need no item reference
    
    return(status);
}
-(void)deletePassword
{
	SecKeychainItemRef itemRef;
    const char* service   = [serviceName UTF8String];
    const char* account   = [accountName UTF8String];
    
    OSStatus status1 = SecKeychainFindGenericPassword(NULL,              // default keychain
                                                      strlen(service),   // length of service name
                                                      service,           // service name
                                                      strlen(account),   // length of account name
                                                      account,           // account name
                                                      NULL,       // length of password
                                                      NULL, // address of password data as void **
                                                      &itemRef               
                                                      );
	if(status1 == noErr) SecKeychainItemDelete(itemRef);
}
@end
