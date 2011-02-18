//
//  NSApplication+LoginItem.h
//  MenuCalendar
//
//  Created by Dirk Theisen on Thu Feb 26 2004.
//  Copyright 2004 Objectpark Software. All rights reserved.
//  Contributions by Jonathan K. Bullard Copyright 2010, 2011
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

- (void)            killOtherInstances;
- (int)             countOtherInstances;

- (NSMutableArray *)pIdsForOpenVPNProcesses;
- (NSMutableArray *)pIdsForOpenVPNMainProcesses;

- (BOOL)            waitUntilNoProcessWithID:   (pid_t)             pid;

- (BOOL)            setAutoLaunchOnLogin:       (BOOL)              doAutoLaunch;
+ (BOOL)            setAutoLaunchPath:          (NSString *)        path        onLogin: (BOOL) doAutoLaunch;
+ (BOOL)            setAutoLaunchPathTiger:     (NSString *)        path        onLogin: (BOOL) doAutoLaunch;
+ (BOOL)            setAutoLaunchPathLeopard:   (NSString *)        path        onLogin: (BOOL) doAutoLaunch;

+(AuthorizationRef) getAuthorizationRef:        (NSString *)        msg;

+(OSStatus)         executeAuthorized:          (NSString *)        toolPath
                        withArguments:          (NSArray *)         arguments
                 withAuthorizationRef:          (AuthorizationRef)  myAuthorizationRef;

+(BOOL)         waitForExecuteAuthorized:       (NSString *)        toolPath
                           withArguments:       (NSArray *)         arguments
                    withAuthorizationRef:       (AuthorizationRef)  myAuthorizationRef;

@end
