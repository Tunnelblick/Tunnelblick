//
//  NSApplication+LoginItem.m
//  MenuCalendar
//
//  Created by Dirk Theisen on Thu Feb 26 2004.
//  Copyright (c) 2004 Objectpark Software. All rights reserved.
//  Modified by Jonathan K. Bullard Sun Jan 17 2010.
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
#import "UKLoginItemRegistry/UKLoginItemRegistry.h"

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

- (int) countOtherInstances
// Returns the number of other instances of a process (cribbed from killOtherInstances, above)
{
    int         myPid = [[NSProcessInfo processInfo] processIdentifier];
    const char* myProcessName = [[[NSProcessInfo processInfo] processName] UTF8String];
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
    size_t length;
    int count, i;
    int returnCount = 0;
    
    // KERN_PROC_ALL has 3 elements, all others have 4
    int level = 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) return (-1);
    // Allocate memory for info structure:
    if (!(info = NSZoneMalloc(NULL, length))) return (-1);
    if (sysctl(mib, level, info, &length, NULL, 0) < 0) {
        NSZoneFree(NULL, info);
        return(-1);
    }
    
    // Calculate number of processes:
    count = length / sizeof(struct kinfo_proc);
    for (i = 0; i < count; i++) {
        char* command = info[i].kp_proc.p_comm;
        pid_t pid = info[i].kp_proc.p_pid;
        //NSLog(@"Found running command: '%s'", command);
        // Test, if this command is called like us:
        if (pid!=myPid && strncmp(myProcessName, command, MAXCOMLEN)==0) {
            returnCount++;
        }
    }    
    NSZoneFree(NULL, info);
    return(returnCount);
}

// Waits up to five seconds for a process to be gone
// (Modified version of NSApplication+LoginItem's killOtherInstances)
- (void) waitUntilNoProcessWithID: (pid_t) pid
{
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
    size_t length;
    int count, i, j;
    BOOL found;
    
    // KERN_PROC_ALL has 3 elements, all others have 4
    int level = 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) {
        return;
    }
    
    for (j=0; j<6; j++) {   // Check six times, one second wait between each = five second maximum wait
        
        if (  j != 0  ) {       // Don't sleep first time through
            sleep(1);
        }
        // Allocate memory for info structure:
        if (!(info = NSZoneMalloc(NULL, length))) return;
        
        if (sysctl(mib, level, info, &length, NULL, 0) < 0) {
            NSZoneFree(NULL, info);
            return;
        }
        
        // Calculate number of processes:
        count = length / sizeof(struct kinfo_proc);
        found = FALSE;
        for (i = 0; i < count; i++) {
            if (  info[i].kp_proc.p_pid == pid  ) {
                found = TRUE;
                break;
            }
            
        }
        NSZoneFree(NULL, info);
        if (  ! found  ) {
            break;
        }
    }
    
    if (  found  ) {
        NSLog(@"Error: Timeout (5 seconds) waiting for OpenVPN process %d to terminate", pid);
    }
}



+ (BOOL)setAutoLaunchPathTiger:(NSString *)itemPath onLogin:(BOOL)doAutoLaunch 
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

+ (BOOL)setAutoLaunchPathLeopard:(NSString *)itemPath onLogin:(BOOL)doAutoLaunch 
{
    if (  doAutoLaunch  ) {
        return [UKLoginItemRegistry addLoginItemWithPath: itemPath hideIt: NO];
    } else {
        return [UKLoginItemRegistry removeLoginItemWithPath: itemPath];
    }
    
    return NO;
}

+ (BOOL)setAutoLaunchPath:(NSString *)itemPath onLogin:(BOOL)doAutoLaunch 
{
    if (  runningOnLeopardOrNewer()  ) {
        return [[self class] setAutoLaunchPathLeopard: itemPath onLogin: doAutoLaunch];
    } else {
        return [[self class] setAutoLaunchPathTiger:   itemPath onLogin: doAutoLaunch];
    }
}

- (BOOL) setAutoLaunchOnLogin: (BOOL) doAutoLaunch
{
    NSString* itemPath = [[[NSProcessInfo processInfo] arguments] objectAtIndex: 0];
    // Remove suffix /Contents/MacOS/AppName
    itemPath = [itemPath stringByDeletingLastPathComponent];
    itemPath = [itemPath stringByDeletingLastPathComponent];
    itemPath = [itemPath stringByDeletingLastPathComponent];
    return [[self class] setAutoLaunchPath: itemPath onLogin: doAutoLaunch];
}

+(AuthorizationRef)getAuthorizationRef: (NSString *) msg {
	OSStatus myStatus;
	AuthorizationFlags myFlags = kAuthorizationFlagDefaults;
	AuthorizationRef myAuthorizationRef;
    
    // Add an icon and a prompt to the authorization dialog
    //
    // One would think that we could use an icon in Resources, but that doesn't work. Apparently if the path is too long
    // the icon won't be displayed. It works if the icon is in /tmp. In addition, it seems to require a 32x32 png.
    // We create the icon dynamically so if the main Tunnelblick icon changes, the authorization dialog will show the new icon.

    NSString * tmpAuthIconPath = @"/tmp/TunnelblickAuthIcon.png";
    
    // START OF CODE adapted from comment 7 on http://cocoadev.com/forums/comments.php?DiscussionID=1215    //
                                                                                                            //
    NSImage *saveIcon = [[NSWorkspace sharedWorkspace] iconForFile: [[NSBundle mainBundle] bundlePath]];    //
                                                                                                            //
    NSImage *smallSave = [[[NSImage alloc] initWithSize:NSMakeSize(32, 32)] autorelease];                   //
    // Get it's size down to 32x32                                                                          //
    [smallSave lockFocus];                                                                                  //
    [saveIcon drawInRect:NSMakeRect(0, 0, 32, 32)                                                           //
                fromRect:NSMakeRect(0, 0, saveIcon.size.width, saveIcon.size.height)                        //
               operation:NSCompositeSourceOver                                                              //
                fraction:1.0];                                                                              //
                                                                                                            //
    [smallSave unlockFocus];                                                                                //
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[smallSave TIFFRepresentation]];             //
                                                                                                            //
    [[rep representationUsingType:NSPNGFileType properties:nil] writeToFile:tmpAuthIconPath atomically:NO]; //
                                                                                                            //
    // END OF CODE adapted from comment 7 on http://cocoadev.com/forums/comments.php?DiscussionID=1215      //
    
    const char *iconPathC = [tmpAuthIconPath fileSystemRepresentation];
    size_t iconPathLength = iconPathC ? strlen(iconPathC) : 0;

    // Prefix the prompt with a space so it is indented, like the rest of the dialog, and follow it with two newlines
    char * promptC = (char *) [[NSString stringWithFormat: @" %@\n\n", msg] UTF8String];
    size_t promptLength = strlen(promptC);
    
    AuthorizationItem environmentItems[] = {
        {kAuthorizationEnvironmentPrompt, promptLength, (void*)promptC, 0},
        {kAuthorizationEnvironmentIcon, iconPathLength, (void*)iconPathC, 0}
    };
    
    AuthorizationEnvironment myEnvironment = {2, environmentItems};
    
	myStatus = AuthorizationCreate(NULL, &myEnvironment, myFlags, &myAuthorizationRef);
	if (myStatus != errAuthorizationSuccess)
		return nil;
	AuthorizationItem myItems = {kAuthorizationRightExecute, 0,
		NULL, 0};
	AuthorizationRights myRights = {1, &myItems};
	myFlags = kAuthorizationFlagDefaults |
		kAuthorizationFlagInteractionAllowed |
		kAuthorizationFlagPreAuthorize |
		kAuthorizationFlagExtendRights;
	myStatus = AuthorizationCopyRights (myAuthorizationRef,&myRights, &myEnvironment, myFlags, NULL );
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
