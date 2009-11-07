//
//  NSApplication+LoginItem.m
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


#import <AppKit/AppKit.h>
#import <sys/sysctl.h>
#import <sys/types.h>
#import <signal.h>
#import "NSApplication+LoginItem.h"
#import "NSArray+cArray.h"

@implementation NSApplication (LoginItem)

- (void) killOtherInstances
/*" Tries to terminate (SIGTERM) all other processes that happen to be named like the current running process name. Useful for stopping old versions or duplicates of the running application. "*/
{
    int         myPid = [[NSProcessInfo processInfo] processIdentifier];
    const char* myProcessName = [[[NSProcessInfo processInfo] processName] UTF8String];
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
    size_t length;
    int count, i;
    
    // KERN_PROC_ALL has 3 elements, all others have 4
    int level = 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) return;
    // Allocate memory for info structure:
    if (!(info = NSZoneMalloc(NULL, length))) return;
    if (sysctl(mib, level, info, &length, NULL, 0) < 0) {
        NSZoneFree(NULL, info);
        return;
    }
    
    // Calculate number of processes:
    count = length / sizeof(struct kinfo_proc);
    for (i = 0; i < count; i++) {
        char* command = info[i].kp_proc.p_comm;
        pid_t pid = info[i].kp_proc.p_pid;
        //NSLog(@"Found running command: '%s'", command);
        // Test, if this command is called like us:
        if (pid!=myPid && strncmp(myProcessName, command, MAXCOMLEN)==0) {
            // Actually kill it:
            if (kill(pid, SIGTERM) !=0) {
                NSLog(@"Error while killing process: %s", strerror(errno)); 
            }
        }
    }    
    NSZoneFree(NULL, info);
}

+ (BOOL)setAutoLaunchPath:(NSString *)itemPath onLogin:(BOOL)doAutoLaunch 
/*" Changes the login window preferences to launch the current application when the user logs in. Returns YES, when the setting has been changed. NO, if no change was necessary. "*/
{
    NSMutableArray *loginItems;
    int i;
    
    // Read the loginwindow preferences:
    loginItems = [(id) CFPreferencesCopyValue((CFStringRef)@"AutoLaunchedApplicationDictionary", 
                                              (CFStringRef)@"loginwindow", 
                                              kCFPreferencesCurrentUser, 
                                              kCFPreferencesAnyHost) autorelease];
    
    loginItems = [[loginItems mutableCopy] autorelease];
    
    // Look, if the application is in the loginItems already:    
    for (i = 0; i < [loginItems count]; i++) 
    {
        NSDictionary *item;
        
        item = [loginItems objectAtIndex:i];
        if ([[[item objectForKey:@"Path"] lastPathComponent] isEqualToString:[itemPath lastPathComponent]]) 
        {
            [loginItems removeObjectAtIndex:i];
            i--; // stay on position
        }
    }
        
    if (doAutoLaunch) 
    {
        NSDictionary *loginDict;
        
        loginDict = [NSDictionary dictionaryWithObjectsAndKeys:
            itemPath, @"Path", 
            [NSNumber numberWithBool:NO], @"Hide", 
            nil, nil];
        [loginItems addObject:loginDict];
    } 
    
    // Write the loginwindow preferences:
    CFPreferencesSetValue((CFStringRef)@"AutoLaunchedApplicationDictionary", 
                          loginItems, 
                          (CFStringRef)@"loginwindow", 
                          kCFPreferencesCurrentUser, 
                          kCFPreferencesAnyHost);
    
    CFPreferencesSynchronize((CFStringRef) @"loginwindow", 
                             kCFPreferencesCurrentUser, 
                             kCFPreferencesAnyHost);
    return YES;    
}

- (BOOL) setAutoLaunchOnLogin: (BOOL) doAutoLaunch
/*" Changes the login window preferences to launch the current application when the user logs in. Returns YES, when the setting has been changed. NO, if no change was necessary. "*/
{
    NSString* itemPath = [[[NSProcessInfo processInfo] arguments] objectAtIndex: 0];
    // Remove suffix /Contents/MacOS/AppName
    itemPath = [itemPath stringByDeletingLastPathComponent];
    itemPath = [itemPath stringByDeletingLastPathComponent];
    itemPath = [itemPath stringByDeletingLastPathComponent];
    return [[self class] setAutoLaunchPath: itemPath onLogin: doAutoLaunch];
}

+(AuthorizationRef)getAuthorizationRef: msg {
	OSStatus myStatus;
	AuthorizationFlags myFlags = kAuthorizationFlagDefaults;
	AuthorizationRef myAuthorizationRef;
	myStatus = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,
								   myFlags, &myAuthorizationRef);
	if (myStatus != errAuthorizationSuccess)
		return nil;
	AuthorizationItem myItems = {kAuthorizationRightExecute, 0,
		NULL, 0};
	AuthorizationRights myRights = {1, &myItems};
	myFlags = kAuthorizationFlagDefaults |
		kAuthorizationFlagInteractionAllowed |
		kAuthorizationFlagPreAuthorize |
		kAuthorizationFlagExtendRights;
	myStatus = AuthorizationCopyRights (myAuthorizationRef,&myRights, NULL, myFlags, NULL );
	if (myStatus != errAuthorizationSuccess)
		return nil;
	
	//AuthorizationFree (myAuthorizationRef, kAuthorizationFlagDefaults);
	if (myStatus) printf("Status: %ld\n", myStatus);
	return myAuthorizationRef;
}
+(OSStatus) executeAuthorized:(NSString *)toolPath withArguments:(NSArray *)arguments withAuthorizationRef:(AuthorizationRef) myAuthorizationRef {
	const char * myToolPath = [toolPath UTF8String];
	char **myArguments = [arguments cArray];
	OSStatus myStatus;
	AuthorizationFlags myFlags = kAuthorizationFlagDefaults;
	// 13
	myStatus = AuthorizationExecuteWithPrivileges
		// 14
		(myAuthorizationRef, myToolPath, myFlags, myArguments,
		 // 15
		 NULL);
	free(myArguments);
	return myStatus;
}

@end
