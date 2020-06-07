/*
 * Copyright 2013, 2014 Jonathan K. Bullard. All rights reserved.
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

#import "TBPerformer.h"

#import "helper.h"

#import "MenuController.h"
#import "NSTimer+TB.h"

extern MenuController * gMC;

@implementation TBPerformer

-(void) test: (NSDictionary *) dict timer: (NSTimer *) timer {
    
    id         whenArgument1    = [dict objectForKey: @"whenArgument1"];
    id         whenArgument2    = [dict objectForKey: @"whenArgument2"];
    NSString * whenSelectorName = [dict objectForKey: @"whenSelectorName"];
    SEL        whenSelector     = NSSelectorFromString(whenSelectorName);
    
    id         doArgument       = [dict objectForKey: @"doArgument"];
    NSString * doSelectorName   = [dict objectForKey: @"doSelectorName"];
    SEL        doSelector       = NSSelectorFromString(doSelectorName);
    
    if (  [self performSelector: whenSelector withObject: whenArgument1 withObject: whenArgument2]  ) {
        
        [timer invalidate];
        
//        NSLog(@"DEBUG: TBPerformer: test: condition satisfied; performing");
        [self performSelectorOnMainThread: doSelector
                               withObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                            doArgument, @"doArgument",
                                            @YES,       @"satisfied",
                                            nil]
                            waitUntilDone: NO];
    } else {
        
        uint64_t endTimeNanoseconds = [[dict objectForKey: @"endTime"] unsignedLongLongValue];
        
        if (  nowAbsoluteNanoseconds() > endTimeNanoseconds  ) {
            
            // Timed out
            
            [timer invalidate];
            
//            NSLog(@"DEBUG: TBPerformer: test: condition not satisfied but have timed out; performing");
            [self performSelectorOnMainThread: doSelector
                                   withObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                                doArgument, @"doArgument",
                                                @NO,        @"satisfied",
                                                nil]
                                waitUntilDone: NO];
            
        } else if (  ! timer  ) {
            
            // Do not have a timer. Create one and schedule a test every "interval" seconds
            
            NSNumber * intervalNumber   = [dict objectForKey: @"interval"];
            NSTimeInterval interval     = [intervalNumber doubleValue];
            
//            NSLog(@"DEBUG: TBPerformer: test: condition not satisfied and not timed out; scheduling timerTickHandler: every %.1f seconds", interval);
            NSTimer * newTimer = [NSTimer scheduledTimerWithTimeInterval: interval
                                                               target: self
                                                             selector: @selector(timerTickHandler:)
                                                             userInfo: dict
                                                              repeats: YES];
            [newTimer tbSetTolerance: -1.0];
        }
    }
}

-(void) timerTickHandler: (NSTimer *) timer {
//    NSLog(@"DEBUG: timerTickHandler invoked");
    [self test: [timer userInfo] timer: timer];
}

-(void) performSelectorOnMainThread: (SEL)            doSelector
                         withObject: (id)             doArgument
       whenTrueIsReturnedBySelector: (SEL)            whenSelector
                         withObject: (id)             whenArgument1
                         withObject: (id)             whenArgument2
                     orAfterTimeout: (NSTimeInterval) timeout
                          testEvery: (NSTimeInterval) interval {
	
    // Get the current time right away, even if we don't end up using it
    uint64_t startTimeNanoseconds = nowAbsoluteNanoseconds();
    
	if (  ! doArgument  ) {
		NSLog(@"performSelectorOnMainThread:withObject:whenTrueIsReturnedBySelector:.. doArgument cannot be nil");
		[gMC terminateBecause: terminatingBecauseOfError];
	}
	if (  ! whenArgument1  ) {
		NSLog(@"performSelectorOnMainThread:withObject:whenTrueIsReturnedBySelector:.. whenArgument1 cannot be nil");
		[gMC terminateBecause: terminatingBecauseOfError];
	}
	if (  ! whenArgument2  ) {
		NSLog(@"performSelectorOnMainThread:withObject:whenTrueIsReturnedBySelector:.. whenArgument2 cannot be nil");
		[gMC terminateBecause: terminatingBecauseOfError];
	}
    if (  interval < 0.1  ) {
        interval = 0.1;
    }
    if (  timeout < 0.1  ) {
        timeout = 0.1;
    }
    
    // If the condition is satisfied, schedule invoking on main thread and return
    
    if (  [self performSelector: whenSelector withObject: whenArgument1 withObject: whenArgument2]  ) {
		
//        NSLog(@"DEBUG: TBPerformer: condition immediately satisfied; performing");
        [self performSelectorOnMainThread: doSelector
                               withObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                            doArgument, @"doArgument",
                                            @YES,       @"satisfied",
                                            nil]
                            waitUntilDone: NO];
        return;
    }

    // Create a dictionary and invoke test:timer
    
    NSString * whenSelectorName = [NSString stringWithUTF8String: sel_getName(whenSelector)];
    NSString * doSelectorName   = [NSString stringWithUTF8String: sel_getName(doSelector)];
    NSNumber * intervalNumber   = [NSNumber numberWithDouble: interval];
    
    uint64_t timeoutNanoseconds = (uint64_t)(timeout * 1.0e9);
    uint64_t endTimeNanoseconds = startTimeNanoseconds + timeoutNanoseconds;
    
    NSNumber * endTimeNumber    = [NSNumber numberWithUnsignedLongLong: endTimeNanoseconds];
    
    NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
                           doSelectorName,   @"doSelectorName",
                           doArgument,       @"doArgument",
                           whenSelectorName, @"whenSelectorName",
                           whenArgument1,    @"whenArgument1",
                           whenArgument2,    @"whenArgument2",
                           intervalNumber,   @"interval",
                           endTimeNumber,    @"endTime",
                           nil];
    
    [self test: dict timer: nil];
}

@end
