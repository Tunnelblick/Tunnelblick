/*
 * Copyright 2015 Jonathan K. Bullard. All rights reserved.
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

#import "TBOperationQueue.h"

#import <pthread.h>

#import "helper.h"

#import "MenuController.h"
#import "MyPrefsWindowController.h"
#import "StatusWindowController.h"
#import "VPNConnection.h"

extern MenuController * gMC;
extern BOOL             gShuttingDownTunnelblick;

static NSMutableArray  * queue = nil; // List of operations waiting to be executed

static NSMutableArray  * disableLists = nil; // List of lists of displayNames for which the UI should be disabled

static NSDictionary    * currentOperation = nil;

static pthread_mutex_t   queueMutex = PTHREAD_MUTEX_INITIALIZER;


void get_lock(void) {
    
    int status;
	unsigned count = 0;
    while ( 0 != (status = pthread_mutex_trylock( &queueMutex ))  ) {
        if (  status == EBUSY) {
            // Locked by another thread; try again later
			if (  count++ != 0) {
				NSLog(@"TBOperationQueue|get_lock: queueMutex is locked; will try again in one second");
			}
            sleep(1);
        } else {
            NSLog(@"TBOperationQueue|get_lock: pthread_mutex_trylock( &queueMutex ) failed; status = %ld, errno = %ld; error = '%s'", (long) status, (long) errno, strerror(errno));
            [gMC terminateBecause: terminatingBecauseOfError];
			return;
        }
    }
}

void release_lock(void) {
    
    int status = pthread_mutex_unlock( &queueMutex );
    if (  status != 0  ) {
        NSLog(@"TBOperationQueue|release_lock: pthread_mutex_unlock( &queueMutex ) failed; status = %ld, errno = %ld; error = '%s'", (long) status, (long) errno, strerror(errno));
        [gMC terminateBecause: terminatingBecauseOfError];
		return;
    }
}

void validateDetailsAndStatusWindows(void) {

    // Schedule main thread to enable or disable UI controls
    //    * In the 'VPN Details' window (which also does that for controls in the "Advanced" window)
    //    * In any and all status (notification) windows
	
	if (  gShuttingDownTunnelblick  ) {
		return;
	}
	
    id vpnDetails = [gMC logScreen];
    if (  vpnDetails  ) {
        VPNConnection * connection = [vpnDetails selectedConnection];
		if (  connection  ) {
			[vpnDetails performSelectorOnMainThread: @selector(validateDetailsWindowControlsForConnection:) withObject: connection waitUntilDone: NO];
		}
    }
    
    NSDictionary * dict = [gMC myVPNConnectionDictionary];
    NSEnumerator * e = [dict keyEnumerator];
    NSString * key;
    while (  (key = [e nextObject])  ) {
        VPNConnection * connection = [dict objectForKey: key];
        StatusWindowController * statusWindow = [connection statusScreen];
        if (  statusWindow  ) {
            [statusWindow performSelectorOnMainThread: @selector(enableOrDisableButtons) withObject: nil waitUntilDone: NO];
        }
    }
}

void start_next(void) {
    
    get_lock();
    
    if (  ! currentOperation ) {
        if (  [queue count] > 0  ) {
            // Get the next operation and remove it from the queue
            NSDictionary * temp = [queue objectAtIndex: 0];
            [temp retain];
            [currentOperation release];
            currentOperation = temp;
            
            [queue removeObjectAtIndex: 0];
            
            // Start the operation
			NSString * selectorName = [currentOperation objectForKey: @"selectorName"];
            SEL selector = NSSelectorFromString(selectorName);
            id  target   = [currentOperation objectForKey: @"target"];
            id  object   = [currentOperation objectForKey: @"object"];
            [NSThread detachNewThreadSelector: selector toTarget: target withObject: object];
        }
    }
    
    release_lock();
}

@implementation TBOperationQueue


+(void) addToQueueSelector: (SEL)       selector
                    target: (id)        target
                    object: (id)        object
               disableList: (NSArray *) disableList {
    
    if (  ! [NSThread isMainThread]  ) {
        NSLog(@"addToQueueSelector:target:object:disableList: invoked but not on main thread");
        [gMC terminateBecause: terminatingBecauseOfError];
		return;
    }
	
	if (  ! disableList  ) {
		disableList = [NSArray array];
	}
    
    NSString * selectorName = NSStringFromSelector(selector);
    
    NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                           selectorName, @"selectorName",
                           target,       @"target",
                           object,       @"object",
                           disableList,  @"disableList",
                           nil];
    
    get_lock();
    
    if (  ! queue  ) {
        queue = [[NSMutableArray alloc] initWithCapacity: 4]; // Leave with retain count = 1
    }
    if (  ! disableLists  ) {
        disableLists = [[NSMutableArray alloc] initWithCapacity: 4]; // Leave with retain count = 1
    }
    
    [queue addObject: dict];
    
    [disableLists addObject: disableList];
    
    validateDetailsAndStatusWindows();
    
    release_lock();
    
    start_next();
}

+(void) removeDisableList {
    
    get_lock();
    
    if (  [disableLists count] == 0  ) {
        NSLog(@"TBOperationQueue: operationIsComplete but [disableLists count] == 0");
        [gMC terminateBecause: terminatingBecauseOfError];
    } else {
		[disableLists removeObjectAtIndex: 0];
	}
	
	release_lock();
}

+(void) operationIsComplete {
    
    get_lock();
    
    if (  ! currentOperation  ) {
        NSLog(@"TBOperationQueue: operationIsComplete but no currentOperation");
        [gMC terminateBecause: terminatingBecauseOfError];
    } else {
		validateDetailsAndStatusWindows();
		
		[currentOperation release];
		currentOperation = nil;
	}
	
    release_lock();
    
    start_next();
}

+(BOOL) shouldUIBeEnabledForDisplayName: (NSString *) displayName {
    
    // Returns FALSE if a UI control for a configuration should be disabled because the UI for that configuration is locked for configuration changes.
    // Otherwise returns TRUE.
    
    get_lock();
    
    NSEnumerator * e = [disableLists objectEnumerator];
    NSArray * list;
    while (  (list = [e nextObject])  ) {
        
        if (  [list containsObject: displayName]  ) {
            release_lock();
            return NO; // Disable this configuration
        }
        
        if (   ([list count] == 1)
            && [[list objectAtIndex: 0] isEqualToString: @"*"] ) {
			release_lock();
            return NO; // Disable all configurations
        }
    }
    
    release_lock();
    return YES;
}

@end
