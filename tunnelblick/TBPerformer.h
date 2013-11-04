/*
 * Copyright 2013 Jonathan Bullard
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


@interface TBPerformer : NSObject {
    
}

-(void) performSelectorOnMainThread: (SEL)            doSelector
                         withObject: (id)             doArgument
       whenTrueIsReturnedBySelector: (SEL)            whenSelector
                         withObject: (id)             whenArgument1
                         withObject: (id)             whenArgument2
                     orAfterTimeout: (NSTimeInterval) timeout
                          testEvery: (NSTimeInterval) interval;

// Invokes a method with an object as an argument on the main thread when a test is either satisified or
// has not been satisfied within a specified timeout period, whichever comes first.
//
// The test for the condition is a method with two arguments, each of which must be objects and cannot be nil.
//
// Both the timeout period and the test interval are specified in seconds.

@end