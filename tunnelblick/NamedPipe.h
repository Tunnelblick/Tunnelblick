/*
 * Copyright (c) 2009 Jonathan K. Bullard
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

@interface NamedPipe : NSObject {
    NSString      * inPath;                 // Path for pipe we're reading from
    NSFileHandle  * fileHandleForReading;   // File handle for reading from the pipe
    SEL             inMethod;               // Selector for method we're sending data to
    id              inTarget;               // Receiver of inMethod
}

-(id)               initPipeReadingFromPath: (NSString *) path
                              sendingDataTo: (SEL)        method
                                  whichIsIn: (id)         target;

-(void)             destroyPipe;            // Automatically invoked if an NSPipe is dealloc-ed

@end
