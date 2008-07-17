/*
 * Copyright (c) 2004 Angelo Laub
 * Fixes by Dirk Theisen <dirk@objectpark.org> 
 * 
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
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
-(id) initWithService:(NSString *)sName
{
	if (sName == nil) return nil;
    if (self = [super init]) {
        serviceName = [sName retain];
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
-(void)deletePassword;
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
	//SecKeychainItemFreeContent(NULL,passData);
}
@end
