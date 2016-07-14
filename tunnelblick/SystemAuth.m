/*
 * Copyright 2016 Jonathan K. Bullard
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


#import "SystemAuth.h"

#import <pthread.h>

#import "helper.h"
#import "MenuController.h"
#import "NSApplication+LoginItem.h"
#import "MyPrefsWindowController.h"
#import "sharedRoutines.h"
#import "TBUserDefaults.h"


// This is the SystemAuth for the "lock" icon in the VPN Details window. It is set/cleared using +setLockSystemAuth:
static SystemAuth * lockSystemAuth = nil;

// The mutex that controls access to lockAuthRef
static pthread_mutex_t  lockAuthRefMutex = PTHREAD_MUTEX_INITIALIZER;

extern TBUserDefaults  * gTbDefaults;

@implementation SystemAuth


TBSYNTHESIZE_OBJECT(retain, NSString *, prompt, setPrompt)

+(void) createAuthorizationIcon {
    
    // Creates a small icon that appears as part of the padlock icon that OS X shows the user.
    //
    // One would think that we could use an icon in Resources, but that doesn't work. Apparently if the path is too long
    // the icon won't be displayed. It works if the icon is in /tmp. (Not if it is in NSTemporaryDirectory() -- path too long.)
    // In addition, it seems to require a 32x32 png.
    //
    // We create the icon dynamically so that if the Tunnelblick app icon changes, the authorization dialog will show the new icon.
    //
    // The image manipulation code was adapted from comment 7 on http://cocoadev.com/forums/comments.php?DiscussionID=1215
    
    NSImage * saveIcon = [[NSWorkspace sharedWorkspace] iconForFile: [[NSBundle mainBundle] bundlePath]];
    
    NSImage * smallSave = [[[NSImage alloc] initWithSize: NSMakeSize(32.0, 32.0)] autorelease];
    
    // Get it's size down to 32x32
    [smallSave lockFocus];
    [saveIcon drawInRect: NSMakeRect(0.0, 0.0, 32.0, 32.0)
                fromRect: NSMakeRect(0.0, 0.0, saveIcon.size.width, saveIcon.size.height)
               operation: NSCompositeSourceOver
                fraction: 1.0];
    [smallSave unlockFocus];
    
    // Get PNG representation as NSData
    NSBitmapImageRep * rep = [NSBitmapImageRep imageRepWithData: [smallSave TIFFRepresentation]];
    NSData * data = [rep representationUsingType: NSPNGFileType
                                      properties: [NSDictionary dictionary]];
    
    // Save PNG file
    [data writeToFile: PADLOCK_ICON_PATH atomically: NO];
}

+(AuthorizationRef) getAuthorizationRefWithPrompt: (NSString *) prompt {
    
    // Does the first part of obtaining a usable AuthorizationRef: creates the ref.
    // DOES NOT check that the ref can do anything, and DOES NOT interact with the user.
    //
    // Returns an AuthorizationRef, or NULL on error
    
    // Create the authorization environment, consisting of the icon and a prompt
    // Prefix the prompt with a space so it is indented, like the rest of the dialog, and follow it with two newlines
    [SystemAuth createAuthorizationIcon];
    const char * iconPathC      = [PADLOCK_ICON_PATH fileSystemRepresentation];
    char *       promptC        = (char *) [[NSString stringWithFormat: @" %@\n\n", prompt] UTF8String];
    AuthorizationItem environmentItems[] = {
        {kAuthorizationEnvironmentPrompt, strlen(promptC),   (void*)promptC,   0},
        {kAuthorizationEnvironmentIcon,   strlen(iconPathC), (void*)iconPathC, 0} };
    AuthorizationEnvironment environment = {2, environmentItems};
    
    AuthorizationFlags       flags = kAuthorizationFlagDefaults;
    AuthorizationRef         authorizationRef;
    
    OSStatus status = AuthorizationCreate(NULL, &environment, flags, &authorizationRef);
    if (status != errAuthorizationSuccess) {
        TBLog(@"DB-AA", @"SystemAuth|getAuthorizationRefWithPrompt: Error status %ld from AuthorizationCreate", (long)status);
        return NULL;
    }
    
    TBLog(@"DB-AA", @"SystemAuth|getAuthorizationRefWithPrompt: returning AuthorizationRef");
    return authorizationRef;
}


+(OSStatus)checkAuthorizationRef: (AuthorizationRef) myAuthorizationRef
                          prompt: (NSString *)       prompt
              interactionAllowed: (BOOL)             interactionAllowed
             reactivationAllowed: (BOOL)             reactivationAllowed {
    
    // Does the second part of obtaining a usable AuthorizationRef: tries to actually obtain the authorization.
    // If ref has already been authorized (not merely created) and has not timed out, no user interaction is needed.
    // Will interact (ask user for username/password) only if "interactionAllowed" is TRUE.
    // So this can check if a ref has timed out, by invoking with "interactionAllowed" set to FALSE.
    //
    // Returns the OSStatus returned by "AuthorizationCopyRights"
    
    // Create the authorization environment, consisting of the icon and a prompt
    // Prefix the prompt with a space so it is indented, like the rest of the dialog, and follow it with two newlines
    [SystemAuth createAuthorizationIcon];
    const char * iconPathC      = [PADLOCK_ICON_PATH fileSystemRepresentation];
    char *       promptC        = (char *) [[NSString stringWithFormat: @" %@\n\n", prompt] UTF8String];
    AuthorizationItem environmentItems[] = {
        {kAuthorizationEnvironmentPrompt, strlen(promptC),   (void*)promptC,   0},
        {kAuthorizationEnvironmentIcon,   strlen(iconPathC), (void*)iconPathC, 0} };
    AuthorizationEnvironment environment = {2, environmentItems};
    
    AuthorizationItem        items  = {kAuthorizationRightExecute, 0, NULL, 0};
    AuthorizationRights      rights = {1, &items};
    AuthorizationFlags       flags  = (  kAuthorizationFlagDefaults
                                       | kAuthorizationFlagPreAuthorize
                                       | kAuthorizationFlagExtendRights);
    if (  interactionAllowed  ) {
        flags |= kAuthorizationFlagInteractionAllowed;
    }
    
    OSStatus status = AuthorizationCopyRights(myAuthorizationRef, &rights, &environment, flags, NULL );
    
    // Reactivate Tunnelblick only when allowed and interacting with the user.
    //
    // DO NOT ALLOW REACTIVATION WHEN INSTALLING OR SECURING THE TUNNELBLICK APPLICATION ITSELF.
    //
    // A. We reactivate Tunnelblick to make sure the authorization window shows up at the front of other windows.
    //
    // B. When installing/securing Tunnelblick, we don't need to reactivate because we have just
    //    been activated (because we have just been launched).
    //
    // C. If we do reactivate when installing, it causes a race:
    //       1. The reactivation creates a system thread to do the work.
    //       2. The user cancels the installation, which terminates this instance of Tunnelblick.
    //       3. The reactivation thread reactivates Tunnelblick by creating a new instance of Tunnelblick.
    //          (On some versions of OS X, this just causes a failure in the reactivation thread and logs messages about that.)
    
    if (   interactionAllowed
        && reactivationAllowed  ) {
        [((MenuController *)[NSApp delegate]) reactivateTunnelblick];
    }
    
    TBLog(@"DB-AA", @"SystemAuth|checkAuthorizationRef:prompt:interactionAllowed:%@ AuthorizationCopyRights returned status %ld", (interactionAllowed ? @"YES" : @"NO"), (long)status);
    
    return status;
}

-(AuthorizationRef) authRefDirect {
    
    return authRef;
}

+(BOOL) haveValidLockSystemAuth {
    
    if (  ! lockSystemAuth  ) {
        return NO;
    }
    
    int lockStatus = pthread_mutex_lock( &lockAuthRefMutex );
    if (  lockStatus != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &lockAuthRefMutex ) failed; status = %ld, errno = %ld", (long) lockStatus, (long) errno);
    }
    
    OSStatus status = [SystemAuth checkAuthorizationRef: [lockSystemAuth authRefDirect]
                                                 prompt: [lockSystemAuth prompt]
                                     interactionAllowed: NO
                                    reactivationAllowed: NO];
    
    BOOL ok = (status == errAuthorizationSuccess);
    
    if (  ! ok  ) {
        // Lock has timed out or has some other error
        TBLog(@"DB-AA", @"SystemAuth|haveValidLockSystemAuth: Lock has timed out or has some other error; requesting lock icon show as locked");
        [[((MenuController *)[NSApp delegate]) logScreen] performSelectorOnMainThread: @selector(lockTheLockIcon) withObject: nil waitUntilDone: NO];
    }
    
    lockStatus = pthread_mutex_unlock( &lockAuthRefMutex );
    if (  lockStatus != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &lockAuthRefMutex ) failed; status = %ld, errno = %ld", (long) lockStatus, (long) errno);
    }
    
    TBLog(@"DB-AA", @"SystemAuth|haveValidLockSystemAuth: Returning %@", (ok ? @"YES" : @"NO"));
    return ok;
}

-(SystemAuth *) initWithPrompt: (NSString *) thePrompt reactivateOk: (BOOL) reactivateOk {
    
    self = [super init];
    if (  ! self  ) {
        NSLog(@"SystemAuth|initWithPrompt: [super init] returned nil; stack trace = %@", callStack());
        return nil;
    }
    
    [self setPrompt: thePrompt];
    
    allowReactivation = reactivateOk;
    
    if (  [SystemAuth haveValidLockSystemAuth ] ) {
        NSString * expandedPrompt = [NSString stringWithFormat: @"%@\n\n Note: Tunnelblick is in administrator mode, so a computer administrator username and password are not required.", prompt];
        int result = TBRunAlertPanelExtended(NSLocalizedString(@"Tunnelblick", @"Window title"),
                                             expandedPrompt,
                                             NSLocalizedString(@"OK", @"Button"),     // Default button
                                             NSLocalizedString(@"Cancel", @"Button"), // Alternate button
                                             nil,
                                             @"skipWarningAboutPreAuthorizedActivity",
                                             NSLocalizedString(@"Do not show this type of warning again", @"Checkbox name"),
                                             nil,
                                             NSAlertDefaultReturn);
        if (  allowReactivation  ) {
            [NSApp activateIgnoringOtherApps:YES];
        }
        
        if (  result != NSAlertDefaultReturn  ) {
            TBLog(@"DB-AA", @"SystemAuth|initWithPrompt: user declined to use the lock authorization");
            authRef = NULL;
            authRefIsFromLock = FALSE;
        } else {
            authRef =  NULL;
            authRefIsFromLock = TRUE;
            TBLog(@"DB-AA", @"SystemAuth|initWithPrompt: authRef from lock)");
        }
    } else {
        authRef = [SystemAuth getAuthorizationRefWithPrompt: prompt];
        authRefIsFromLock = FALSE;
        (void)[self authRef]; // Force user interaction
        TBLog(@"DB-AA", @"SystemAuth|initWithPrompt: authRef from user interaction");
    }
    
    return self;
}

-(void) dealloc {
    
    if (   (! authRefIsFromLock)
        && (authRef != NULL)  ) {
        TBLog(@"DB-AA", @"SystemAuth|dealloc: freeing AuthorizationRef");
        AuthorizationFree(authRef, kAuthorizationFlagDefaults);
    }
    
    [super dealloc];
}

-(BOOL) authRefIsFromLock {
    
    return authRefIsFromLock;
}

//*************************************************************************************************************************
//
// PUBLIC METHODS

+(SystemAuth *) newAuthWithPrompt: (NSString *) prompt {
    
    // Returns nil if the user cancelled
    
    if (  [NSThread isMainThread]  ) {
        TBLog(@"DB-AA", @"SystemAuth|newAuthWithPrompt: Warning: Running on main thread; stack trace = %@", callStack());
    }
    
    SystemAuth * sa = [[SystemAuth alloc] initWithPrompt: prompt reactivateOk: YES];
    
    if (   [sa authRefIsFromLock]
        || ([sa authRefDirect] != NULL)  ) {
        return sa;
    }
    
    [sa release];
    return nil; // User cancelled
}

+(SystemAuth *) newAuthWithoutReactivationWithPrompt: (NSString *) prompt {
    
    // Returns nil if the user cancelled
    
    if (  [NSThread isMainThread]  ) {
        TBLog(@"DB-AA", @"SystemAuth|newAuthWithPrompt: Warning: Running on main thread; stack trace = %@", callStack());
    }
    
    SystemAuth * sa = [[SystemAuth alloc] initWithPrompt: prompt reactivateOk: NO];
    
    if (   [sa authRefIsFromLock]
        || ([sa authRefDirect] != NULL)  ) {
        return sa;
    }
    
    [sa release];
    return nil; // User cancelled
}

-(AuthorizationRef) authRef {
    
    // To avoid reactivating Tunnelblick unnecessarily, we try to check the authorization without user interaction first, and
    // only check allowing user interaction if that fails. Such failures should only happen when the authorization has timed out.
    
    if (  authRefIsFromLock  ) {
        AuthorizationRef lockRef = [lockSystemAuth authRefDirect];
        OSStatus status = [SystemAuth checkAuthorizationRef: lockRef
                                                     prompt: [self prompt]
                                         interactionAllowed: NO
                                        reactivationAllowed: NO];
        if (  status == errAuthorizationSuccess  ) {
            TBLog(@"DB-AA", @"SystemAuth|authRef: returning authRef from lock");
            NSLog(@"Authorizing an operation without admin username/password because Tunnelblick is in administrator mode");
            return lockRef;
        }
        
        // Authorization from the lock icon isn't good any more
        // If this isn't the lockSystemAuth itself, we change this SystemAuth to a new SystemAuth
        // We don't release the lock's AuthorizationRef because that is done when MyPrefsWindowController|lockTheLockIcon releases the lock's SystemAuth
        if (  self != lockSystemAuth  )  {
            TBLog(@"DB-AA", @"SystemAuth|authRef: Authorization from the lock icon isn't good and this is not the lock SystemAuth, so we are changing this SystemAuth to a not-from-lock SystemAuth and requesting lock icon show as locked");
            authRefIsFromLock = FALSE;
            authRef = [SystemAuth getAuthorizationRefWithPrompt: prompt];
            [[((MenuController *)[NSApp delegate]) logScreen] performSelectorOnMainThread: @selector(lockTheLockIcon) withObject: nil waitUntilDone: NO];
            if (  authRef == NULL  ) {
                NSLog(@"SystemAuth|authRef: getAuthorizationRefWithPrompt returned NULL so returning NULL");
                return NULL;
            }
        } else {
            TBLog(@"DB-AA", @"SystemAuth|authRef: Authorization from the lock icon isn't good and this is the lock SystemAuth, so we are requesting lock icon show as locked and returning NULL");
            [[((MenuController *)[NSApp delegate]) logScreen] performSelectorOnMainThread: @selector(lockTheLockIcon) withObject: nil waitUntilDone: NO];
            return NULL;
        }
    }
    
    if (  authRef == NULL  ) {
        TBLog(@"DB-AA", @"SystemAuth|authRef: authRef is NULL, so returning NULL");
        return NULL;
    }
    OSStatus status = [SystemAuth checkAuthorizationRef: authRef
                                                 prompt: [self prompt]
                                     interactionAllowed: NO
                                    reactivationAllowed: NO];
    
    if (  status != errAuthorizationSuccess  ) {
        status = [SystemAuth checkAuthorizationRef: authRef
                                            prompt: [self prompt]
                                interactionAllowed: YES
                               reactivationAllowed: allowReactivation];
    }
    
    if (  status != errAuthorizationSuccess  ) {
        if (  authRef != NULL  ) {
            TBLog(@"DB-AA", @"SystemAuth|authRef: status from checkAuthorizationRef was %ld; freeing authRef, setting it to NULL and returning NULL", (long)status);
            AuthorizationFree(authRef, kAuthorizationFlagDefaults);
            authRef = NULL;
            return NULL;
        }
    }
    
    TBLog(@"DB-AA", @"SystemAuth|authRef: returning authRef from user intreraction");
    return authRef;
}

+(void) setLockSystemAuth: (SystemAuth *) newAuth {
    
    if (  ! [NSThread isMainThread]  ) {
        NSLog(@"SystemAuth|setLockSystemAuth: Not running on main thread; stack trace = %@", callStack());
        [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
        return;
    }
    
    int status = pthread_mutex_lock( &lockAuthRefMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &lockAuthRefMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
    }
    
    BOOL ok = TRUE;
    
    if (  newAuth  ) {
        if (  lockSystemAuth  ) {
            NSLog(@"SystemAuth|setLockSystemAuth: but lockAuth is already set; stack trace = %@", callStack());
            ok = FALSE;
        } else {
            lockSystemAuth = [newAuth retain];
            TBLog(@"DB-AA", @"SystemAuth|setLockSystemAuth: set lockSystemAuth");
        }
    } else {
        if (  lockSystemAuth  ) {
            [lockSystemAuth release];
            TBLog(@"DB-AA", @"SystemAuth|setLockSystemAuth: nil, so released lockSystemAuth");
            lockSystemAuth = nil;
        } else {
            TBLog(@"DB-AA", @"SystemAuth|setLockSystemAuth: nil, but lockSystemAuth is already nil; stack trace = %@", callStack());
        }
    }
    
    status = pthread_mutex_unlock( &lockAuthRefMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &lockAuthRefMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
    }
    
    if (  ! ok  ) {
        [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
    }
}

@end
