//
//  NSApplication+LoginItem.m
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


#import <AppKit/AppKit.h>
#import <sys/sysctl.h>
#import <sys/types.h>
#import <sys/stat.h>
#import <signal.h>
#import "NSApplication+LoginItem.h"
#import "NSArray+cArray.h"
#import "UKLoginItemRegistry/UKLoginItemRegistry.h"
#import "helper.h"
#import "defines.h"
#import "MenuController.h"

// The following external, global variable is used by functions in this file and must be declared and set elsewhere before the
// functions in this file are called:
extern NSFileManager * gFileMgr;

@interface NSApplication (LoginItemPrivate)

+ (BOOL)            setAutoLaunchPath:          (NSString *)        path        onLogin: (BOOL) doAutoLaunch;
+ (BOOL)            setAutoLaunchPathTiger:     (NSString *)        path        onLogin: (BOOL) doAutoLaunch;
+ (BOOL)            setAutoLaunchPathLeopard:   (NSString *)        path        onLogin: (BOOL) doAutoLaunch;

@end

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
    unsigned level = 3;
    
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
                NSLog(@"Error while killing process: Error was '%s'", strerror(errno)); 
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
    unsigned level = 3;
    
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

// Returns an array of NSNumber objects, each with the pid for an OpenVPN process
// Returns nil on error, empty array if no OpenVPN processes running
//  (modified version of countOtherInstances, above)
-(NSMutableArray *) pIdsForOpenVPNProcesses
{
    NSMutableArray * retArray = [NSMutableArray arrayWithCapacity: 2];
    const char* processName = "openvpn";
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
    size_t length;
    int count, i;
    
    // KERN_PROC_ALL has 3 elements, all others have 4
    unsigned level = 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) return (nil);
    // Allocate memory for info structure:
    if (!(info = NSZoneMalloc(NULL, length))) return (nil);
    if (sysctl(mib, level, info, &length, NULL, 0) < 0) {
        NSZoneFree(NULL, info);
        return(nil);
    }
    
    // Get each process ID:
    count = length / sizeof(struct kinfo_proc);
    for (i = 0; i < count; i++) {
        char* command = info[i].kp_proc.p_comm;
        pid_t pid = info[i].kp_proc.p_pid;
        if (strncmp(processName, command, MAXCOMLEN)==0) {
            [retArray addObject: [NSNumber numberWithInt: (int) pid]];
        }
    }    
    NSZoneFree(NULL, info);
    
    return(retArray);
}

// Like pIdsForOpenVPNProcesses, but only returns main OpenVPN processes, not down-root processes
-(NSMutableArray *) pIdsForOpenVPNMainProcesses
{
    NSMutableArray * inPids = [NSApp pIdsForOpenVPNProcesses];
    NSMutableArray * outPids = [NSMutableArray arrayWithCapacity: [inPids count]];
    
    if (  [inPids count] == 0  ) {
        return inPids;
    }
    
    unsigned i;
    for (  i=0; i < [inPids count]; i++  ) {
        NSNumber * pidAsNSNumber = [inPids objectAtIndex: i];
        unsigned pid = [pidAsNSNumber unsignedIntValue];
        
        NSTask * task = [[[NSTask alloc] init] autorelease];
        NSPipe * stdPipe = [[[NSPipe alloc] init] autorelease];
        
        [task setLaunchPath: @"/bin/ps"];
        [task setArguments:  [NSArray arrayWithObjects: @"-o", @"rss=", @"-p", [NSString stringWithFormat: @"%u", pid], nil]];
        [task setStandardOutput: stdPipe];
        
        [task launch];
        [task waitUntilExit];
        OSStatus status = [task terminationStatus];
        
        // Get output from ps command
        NSFileHandle * file = [stdPipe fileHandleForReading];
        NSData * data = [file readDataToEndOfFile];
        [file closeFile];
        NSString * psOutput = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
        psOutput = [psOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if (   status == EXIT_SUCCESS  ) {
            if (  [psOutput length] != 0  ) {
                unsigned sizeInKB = cvt_atou([psOutput UTF8String], @"sizeInKB (pIdsForOpenVPNMainProcesses: psOutput");
                if (  sizeInKB >= 1024  ) {  // Assumes OpenVPN itself is >= 1024KB, and openvpn-down-root.so is < 1024KB. In OpenVPN 2.1.4 they are 2300KB and 244KB, respectively
                    [outPids addObject: pidAsNSNumber];
                }
            } else {
                NSLog(@"'/bin/ps -o rss= -p %u' failed -- no output from the command", pid);
            }
        } else {
            NSLog(@"'/bin/ps -o rss= -p %u' failed with error %d\n'%s'", pid, errno, strerror(errno));
        }
    }
    
    return outPids;
}

// Waits up to five seconds for a process to be gone
// (Modified version of NSApplication+LoginItem's killOtherInstances)
// Returns TRUE if process has terminated, otherwise returns FALSE
- (BOOL) waitUntilNoProcessWithID: (pid_t) pid
{
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc* info;
    size_t length;
    int count, i, j;
    BOOL found = FALSE;
    
    // KERN_PROC_ALL has 3 elements, all others have 4
    unsigned level = 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) {
        NSLog(@"Error: waitUntilNoProcessWithID: sysctl call #1: errno = %d\n%s", errno, strerror(errno));
        return FALSE;
    }
    
    for (j=0; j<6; j++) {   // Check six times, one second wait between each = five second maximum wait
        
        if (  j != 0  ) {       // Don't sleep first time through
            sleep(1);
        }
        // Allocate memory for info structure:
        if (  (info = NSZoneMalloc(NULL, length)) != 0  ) {
            
            if (  sysctl(mib, level, info, &length, NULL, 0) == 0  ) {
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
                    return TRUE;
                }
                
            } else {
                NSZoneFree(NULL, info);
                NSLog(@"Error: waitUntilNoProcessWithID: sysctl call #2: length = %lu errno = %ld\n%s", (long) length, (long) errno, strerror(errno));
            }
            
        } else {
            NSLog(@"Error: waitUntilNoProcessWithID: NSZoneMalloc failed");
        }
        
    }
    
    if (  ! found  ) {
        return TRUE;
    }

    NSLog(@"Error: Timeout (5 seconds) waiting for OpenVPN process %d to terminate", pid);
    return FALSE;
}


+(void) addAppAsLoginItem {

    // This method is a modified version of a method at http://cocoatutorial.grapewave.com/2010/02/creating-andor-removing-a-login-item/
    
	NSString * appPath = [[NSBundle mainBundle] bundlePath];
    
	// This will retrieve the path for the application
	// For example, /Applications/test.app
	CFURLRef url = (CFURLRef)[NSURL fileURLWithPath: appPath];
    
    if (  url  ) {
        // Create a reference to the shared file list.
        // We are adding it to the current user only.
        // If we want to add it all users, use
        // kLSSharedFileListGlobalLoginItems instead of
        //kLSSharedFileListSessionLoginItems
        LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
        
        if (  loginItems  ) {
            //Insert an item to the list.
            LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(loginItems,
                                                                         kLSSharedFileListItemLast, NULL, NULL,
                                                                         url, NULL, NULL);
            if (  item  ){
                CFRelease(item);
            } else {
                NSLog(@"addAppAsLoginItem: LSSharedFileListInsertItemURL() returned NULL");
            }
            
            CFRelease(loginItems);
        } else {
            NSLog(@"addAppAsLoginItem: LSSharedFileListCreate() returned NULL");
        }
    } else {
        NSLog(@"addAppAsLoginItem: [NSURL fileURLWithPath: @\"%@\"] returned NULL", appPath);
    }
}

+(void) deleteAppFromLoginItems {
    
    // This method is a modified version of a method at http://cocoatutorial.grapewave.com/2010/02/creating-andor-removing-a-login-item/
    
	NSString * appPath = [[NSBundle mainBundle] bundlePath];
    
    // Create a reference to the shared file list.
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    
    if (  loginItems  ) {
        UInt32 seedValue;
        //Retrieve the list of Login Items and cast them to
        // a NSArray so that it will be easier to iterate.
        NSArray * loginItemsArray = (NSArray *)LSSharedFileListCopySnapshot(loginItems, &seedValue);
        
        if (  loginItemsArray  ) {
            unsigned i;
            for (  i=0 ; i<[loginItemsArray count]; i++  ) {
                LSSharedFileListItemRef itemRef = (LSSharedFileListItemRef)[loginItemsArray objectAtIndex:i];
                if (  itemRef  ) {
                    //Resolve the item with URL
                    CFURLRef url = NULL;
                    OSStatus status = LSSharedFileListItemResolve(itemRef, 0, &url, NULL);
                    if (  status == noErr  ) {
                        NSString * urlPath = [(NSURL*)url path];
                        if (  [urlPath isEqualToString: appPath]  ){
                            status = LSSharedFileListItemRemove(loginItems,itemRef);
                            if (  status != noErr  ) {
                                NSLog(@"deleteAppFromLoginItems: LSSharedFileListItemRemove returned status = %ld for loginItem for %@", (long) status, appPath);
                            }
                        }
                    } else {
                        NSLog(@"deleteAppFromLoginItems: LSSharedFileListItemResolve returned status = %ld; url is %@",
                              (long) status, (url ? @"not NULL" : @"NULL"));
                    }
                    if (  url  ) {
                        CFRelease(url);
                        url = NULL;
                    }
                } else {
                    NSLog(@"deleteAppFromLoginItems: loginItemsArray contains a NULL object");
                }
            }
            CFRelease((CFArrayRef)loginItemsArray);
        } else {
            NSLog(@"deleteAppFromLoginItems: LSSharedFileListCopySnapshot() returned NULL");
        }
    } else {
        NSLog(@"deleteAppFromLoginItems: LSSharedFileListCreate() returned NULL");
    }
}

+ (BOOL)setAutoLaunchPathTiger:(NSString *)itemPath onLogin:(BOOL)doAutoLaunch
{
    NSMutableArray *loginItems;
    unsigned i;
    
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
    BOOL alreadyWillLaunch = ( -1 != [UKLoginItemRegistry indexForLoginItemWithPath: itemPath]);
    
    if (  doAutoLaunch  ) {
        if (  alreadyWillLaunch  ) {
            return YES;
        }        
        return [UKLoginItemRegistry addLoginItemWithPath: itemPath hideIt: NO];

    } else {
        if (  alreadyWillLaunch  ) {
            return [UKLoginItemRegistry removeLoginItemWithPath: itemPath];
        }
        return YES;
    }
}

+ (BOOL)setAutoLaunchPath:(NSString *)itemPath onLogin:(BOOL)doAutoLaunch 
{
    if (  runningOnLeopardOrNewer()  ) {
        return [[self class] setAutoLaunchPathLeopard: itemPath onLogin: doAutoLaunch];
    } else {
        return [[self class] setAutoLaunchPathTiger:   itemPath onLogin: doAutoLaunch];
    }
}

- (void) setAutoLaunchOnLogin: (BOOL) doAutoLaunch
{
    // Before Mavericks, setAutoLaunchPath:onLogin: worked. According to the docs,
    // the new methods addAppAsLoginItem and deleteAppFromLoginItems should
    // work on Leopard and higher, but to "not fix what ain't broken", we only use
    // the new methods on Mavericks.
    if (  runningOnMavericksOrNewer()  ) {
        if (  doAutoLaunch) {
            [[self class] addAppAsLoginItem];
        } else {
            [[self class] deleteAppFromLoginItems];
        }
    }
    
    NSString* appPath = [[NSBundle mainBundle] bundlePath];
    [[self class] setAutoLaunchPath: appPath onLogin: doAutoLaunch];
}

+(AuthorizationRef)getAuthorizationRef: (NSString *) msg {
	OSStatus myStatus;
	AuthorizationFlags myFlags = kAuthorizationFlagDefaults;
	AuthorizationRef myAuthorizationRef;
    
    // Add an icon and a prompt to the authorization dialog
    //
    // One would think that we could use an icon in Resources, but that doesn't work. Apparently if the path is too long
    // the icon won't be displayed. It works if the icon is in /tmp. (Not if it is in NSTemporaryDirectory() -- path too long.)
    // In addition, it seems to require a 32x32 png.
    // We create the icon dynamically so if the main Tunnelblick icon changes, the authorization dialog will show the new icon.

    NSString * tmpAuthIconPath = @"/tmp/TunnelblickAuthIcon.png";
    
    // START OF CODE adapted from comment 7 on http://cocoadev.com/forums/comments.php?DiscussionID=1215    //
                                                                                                            //
    NSImage *saveIcon = [[NSWorkspace sharedWorkspace] iconForFile: [[NSBundle mainBundle] bundlePath]];    //
                                                                                                            //
	NSImage *smallSave = [[[NSImage alloc] initWithSize:NSMakeSize(32.0, 32.0)] autorelease];             //
    // Get it's size down to 32x32                                                                          //
    [smallSave lockFocus];                                                                                  //
    [saveIcon drawInRect:NSMakeRect(0.0, 0.0, 32.0, 32.0)                                               //
                fromRect:NSMakeRect(0.0, 0.0, saveIcon.size.width, saveIcon.size.height)  //
               operation:NSCompositeSourceOver                                                              //
                fraction:1.0];                                                                             //
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
	return myAuthorizationRef;
}

+(OSStatus) executeAuthorized:(NSString *)toolPath withArguments:(NSArray *)arguments withAuthorizationRef:(AuthorizationRef) myAuthorizationRef {
	const char * myToolPath = [gFileMgr fileSystemRepresentationWithPath: toolPath];
	char **myArguments = [arguments cArray];
	OSStatus myStatus;
	AuthorizationFlags myFlags = kAuthorizationFlagDefaults;
	// 13
	myStatus = AuthorizationExecuteWithPrivileges
		// 14
		(myAuthorizationRef, myToolPath, myFlags, myArguments,
		 // 15
		 NULL);
	freeCArray(myArguments);
    if (  myStatus != 0  ) {
        NSLog(@"AuthorizationExecuteWithPrivileges returned status = %ld", (long) myStatus);
    }
	return myStatus;
}

+(BOOL) createFlagFile: (NSString *) path {
    
    int fd = open([path fileSystemRepresentation], O_RDONLY | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
    if (fd < 0) {
        NSLog(@"Unable to create flag file %@\nError was '%s'", path, strerror(errno));
        return NO;
    } else {
        if (  0 != close(fd)  ) {
            NSLog(@"Unable to close flag file %@ with file descriptor %d\nError was '%s'", path, fd, strerror(errno));
            return NO;
        }
    }
    
    return YES;
}

+(wfeaReturnValue) waitForExecuteAuthorized: (NSString *)       toolPath
                              withArguments: (NSArray *)        arguments
                       withAuthorizationRef: (AuthorizationRef) myAuthorizationRef {
    
    // Creates a "running" and an "error" flag file, runs executeAuthorized, then waits for up to 12.75 seconds for the "running" flag file to disappear
    
    if (   ( ! [self createFlagFile: AUTHORIZED_RUNNING_PATH] )
        || ( ! [self createFlagFile: AUTHORIZED_ERROR_PATH]   )  ) {
        unlink([AUTHORIZED_RUNNING_PATH fileSystemRepresentation]);
        unlink([AUTHORIZED_ERROR_PATH fileSystemRepresentation]);
        return wfeaExecAuthFailed;
    }
    
    if (  EXIT_SUCCESS != [NSApplication executeAuthorized: toolPath withArguments: arguments withAuthorizationRef: myAuthorizationRef]  ) {
        if (  0 != unlink([AUTHORIZED_RUNNING_PATH fileSystemRepresentation])  ) {
            NSLog(@"Unable to delete %@", AUTHORIZED_RUNNING_PATH);
        }
        if (  0 != unlink([AUTHORIZED_ERROR_PATH fileSystemRepresentation])  ) {
            NSLog(@"Unable to delete %@", AUTHORIZED_ERROR_PATH);
        }
        return wfeaExecAuthFailed;
    }
    
    // Wait for up to 12.75 seconds for the program to finish -- sleeping .05 seconds first, then .1, .2, .4, .8, 1.6, 3.2, and 6.4
    // seconds (totals 12.75 seconds) between tries as a cheap and easy throttling mechanism for a heavily loaded computer
    useconds_t sleepTime;
    struct stat sb;
    for (sleepTime=50000; sleepTime < 13000000; sleepTime=sleepTime*2) {
        usleep(sleepTime);
        
        if (  0 != stat([AUTHORIZED_RUNNING_PATH fileSystemRepresentation], &sb)  ) {
            // running flag file has been deleted, indicating we're done
			if (  0 == stat([AUTHORIZED_ERROR_PATH fileSystemRepresentation], &sb)  ) {
                // error flag file exists, so there was an error
				if (  0 != unlink([AUTHORIZED_ERROR_PATH fileSystemRepresentation])  ) {
					NSLog(@"Unable to delete %@", AUTHORIZED_ERROR_PATH);
				}
				
				return wfeaFailure;
			}
			
            return wfeaSuccess;
        }
    }
    
    NSLog(@"Timed out waiting for %@ to disappear indicting %@ finished", AUTHORIZED_RUNNING_PATH, [toolPath lastPathComponent]);
    if (  0 != unlink([AUTHORIZED_RUNNING_PATH fileSystemRepresentation])  ) {
        NSLog(@"Unable to delete %@", AUTHORIZED_RUNNING_PATH);
    }
    if (  0 != unlink([AUTHORIZED_ERROR_PATH fileSystemRepresentation])  ) {
        NSLog(@"Unable to delete %@", AUTHORIZED_ERROR_PATH);
    }
    
    return wfeaTimedOut;
}

@end
