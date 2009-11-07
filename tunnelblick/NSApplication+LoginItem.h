//
//  NSApplication+LoginItem.h
//  MenuCalendar
//
//  Created by Dirk Theisen on Thu Feb 26 2004.
//  Copyright (c) 2004 Objectpark Software. All rights reserved.
//
//  Permission to use, copy, modify, and distribute this software for any
//  purpose with or without fee is hereby granted, provided that the above
//  copyright notice and this permission notice appear in all copies.
// 
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
//  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
//  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
//  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
//  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.


#import <Security/Security.h>

@interface NSApplication (LoginItem)

- (void) killOtherInstances;

+ (BOOL) setAutoLaunchPath:(NSString *)path onLogin: (BOOL) doAutoLaunch;

- (BOOL) setAutoLaunchOnLogin: (BOOL) doAutoLaunch;

+(AuthorizationRef)getAuthorizationRef: msg;

+(OSStatus) executeAuthorized:(NSString *)toolPath withArguments:(NSArray *)arguments withAuthorizationRef:(AuthorizationRef) myAuthorizationRef;

@end
