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

#import "NamedPipe.h"

extern NSFileManager * gFileMgr;

@implementation NamedPipe

-(id) initPipeReadingFromPath: (NSString *) path
                sendingDataTo: (SEL)        method
                    whichIsIn: (id)         target
{
    if (    ! (self = [super init])     ) {
        return nil;
    }
    
    if (  ! [target respondsToSelector:method]  ) {
        NSLog(@"Unable to create NamedPipe with path %@ because %@ does not respond to %@", path, target, method);
        return nil;
    }
    
    fileHandleForReading = nil;
    
    inPath = path;
    [inPath retain];
    
    inMethod = method;
    
    inTarget = target;
    [inTarget retain];
    
    [gFileMgr removeFileAtPath:inPath handler:nil];
    
    const char * cPath = [path UTF8String];
    
    // Create the pipe
    if (    ( mkfifo(cPath, 0666) == -1 ) && ( errno != EEXIST )    ){
        NSLog(@"Unable to create named pipe %s", cPath);
        [self destroyPipe];
        return nil;
    }
    
    // We "open()" to get a file descriptor, then get a fileHandle from the returned file descriptor.
    //
    // If we try to get a fileHandle directly via "[NSFileHandle fileHandleForReadingAtPath:]"
    // the process is blocked. Calling "open()" and then getting the fileHandle from the returned
    // file descriptor avoids that blocking.
    //
    // Similarly, if we get a file handle via "[NSFileHandle fileHandleForUpdatingAtPath:]", the
    // process blocks when we do a "[fileHandle release]" or a "[fileHandle closeFile]"
    //
    // Using "initWithFileDescriptor: closeOnDealloc:NO" causes the file NOT to be closed when the fileDescriptor is
    // released. See the comment in "destroyPipe", below.
    //
    // We can't open with the "O_NONBLOCK" option because that causes "readInBackgroundAndNotify" to send continuous
    // notifications that there is data of length zero. That eats up 100% of the CPU (at a low priority, but still...)

    // Get a file descriptor for reading the pipe without blocking
    int fileDescriptor;
    if (    ( fileDescriptor = open(cPath, O_RDWR) ) == -1    ) {
        NSLog(@"Unable to get file descriptor for named pipe %s", cPath);
        [self destroyPipe];
        return nil;
    }
    
    fileHandleForReading = [[NSFileHandle alloc] initWithFileDescriptor:fileDescriptor closeOnDealloc:NO];
    if (  ! fileHandleForReading  ) {
        NSLog(@"Unable to get file handle for named pipe %s", cPath);
        [self destroyPipe];
        return nil;
    }
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(pipeDataReady:)
                                                 name: NSFileHandleReadCompletionNotification
                                               object: fileHandleForReading];
    
    [fileHandleForReading readInBackgroundAndNotify];
    
    return self;
    
}

- (void) dealloc
{
    [self destroyPipe];         // In case pipe wasn't already destroyed
    [super dealloc];
}

// Destroy the pipe and delete it from the filesystem
// destroyPipe works even if it is called for an already-destroyed pipe
-(void) destroyPipe
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // We DON'T close the file with "close()" or "[fileHandleForReading closeFile];" because that blocks the process. 
    // "close()" even blocks if we call "fnctl()" with O_NONBLOCK) first. So we never really close
    // the file descriptor.
    // Also, see the comment in "initPipeReadingFromPath: sendingDataTo: whichIsIn:", above.
    
    [fileHandleForReading release];
    fileHandleForReading = nil;
    
    if (  inPath  ) {
        [gFileMgr removeFileAtPath:inPath handler:nil];
        [inPath release];
        inPath = nil;
    }
    
    [inTarget release];
    inTarget = nil;
}

// This gets called when data is ready in the named pipe
-(void) pipeDataReady: (NSNotification *) n
{
    NSData * data = [[n userInfo] valueForKey:NSFileHandleNotificationDataItem];

    if (  [data length] != 0  ) {

        // If the pipe has been destroyed, inTarget will be nil, so we won't send anything
        [inTarget performSelectorOnMainThread: inMethod 
                                   withObject: data
                                waitUntilDone: NO];
    } else {
        NSLog(@"pipeDataReady: 0 bytes");
    }
    
    // Keep getting more data unless the pipe has been destroyed
    [fileHandleForReading readInBackgroundAndNotify];
}

@end
