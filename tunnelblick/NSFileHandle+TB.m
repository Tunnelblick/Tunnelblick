/*
 * Copyright (c) 2024 Jonathan K. Bullard. All rights reserved.
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

// A category of NSFileHandle that implements its methods that we need which are
// available only in macOS 10.15 and higher.
//
// If running on a system that implements the methods, we use the methods
// Otherwise we use older methods that are deprecated. Most of these older methods
// cause an exception rather than returning an error.
//
// When Tunnelblick is built only for macOS 10.15 and higher, we can remove this
// category and do a mass find-and-replace of this category's method names with
// the NSFileHandle method names, e.g. "tbSeekToOffset:error:" => "seekToOffset:error"

#import "NSFileHandle+TB.h"

@implementation NSFileHandle(TBFileHandle)

-(BOOL) tbCloseAndReturnError: (out NSError * _Nullable *) error {

    if (  [self respondsToSelector: @selector(closeAndReturnError:)]  ) {
        // macOS 10.15 and higher
        if (  ! [self closeAndReturnError: error]  ) {
            NSLog(@"FileHandle closeAndReturnError returned error: %@", (id)error);
            return NO;
        }
    } else {
        // macOS below 10.15.
        [self closeFile]; // Raises NSFileHandleOperationException on some errors
    }

    return YES;
}

-(NSData * _Nullable ) tbReadDataToEndOfFileAndReturnError: (out NSError * _Nullable * _Nullable) error {

    NSData * data = nil;

    if (  [self respondsToSelector: @selector(readDataToEndOfFileAndReturnError:)]  ) {
        // macOS 10.15 and higher
        if (  ! (data = [self readDataToEndOfFileAndReturnError: error])  ) {
            NSLog(@"FileHandle readDataToEndOfFileAndReturnError returned error: %@", (id)error);
            return nil;
        }
    } else {
        // macOS below 10.15.
        data = [self availableData]; // Raises NSFileHandleOperationException on some errors
    }

    return data;
}
-(BOOL) tbSeekToEndReturningOffset: (out unsigned long long *) offsetInFile
                             error: (out NSError * _Nullable *) error {

    unsigned long long offset;

    if (  [self respondsToSelector: @selector(seekToEndReturningOffset:error:)]  ) {
        // macOS 10.15 and higher only
        if (  ! [self seekToEndReturningOffset: &offset error: error]  ) {
            NSLog(@"FileHandle seekToEndReturningOffset:error: returned error: %@", (id)error);
            return NO;
        }
    } else {
        // macOS below 10.15.
        [self seekToEndOfFile]; // Might raise NSFileHandleOperationException on some errors
    }

    return YES;
}

-(BOOL) tbSeekToOffset: (unsigned long long) offset
                 error: (out NSError * _Nullable *) error {

    if (  [self respondsToSelector: @selector(seekToOffset:error:)]  ) {
        // macOS 10.15 and higher only
        if (  ! [self seekToOffset: offset error: error]  ) {
            NSLog(@"FileHandle seekToOffset:error: returned error: %@", (id)error);
            return NO;
        }
    } else {
        // macOS below 10.15.
        [self seekToFileOffset: offset]; // Might raise NSFileHandleOperationException on some errors
    }

    return YES;
}

-(BOOL) tbTruncateAtOffset: (unsigned long long) offset
                     error: (out NSError * _Nullable *) error {

    if (  [self respondsToSelector: @selector(truncateAtOffset:error:)]  ) {
        // macOS 10.15 and higher only
        if (  ! [self truncateAtOffset: offset error: error]  ) {
            NSLog(@"FileHandle truncateAtOffset:error: returned error: %@", (id)error);
            return NO;
        }
    } else {
        // macOS below 10.15.
        [self seekToEndOfFile]; // Might raise NSFileHandleOperationException on some errors
    }

    return YES;
}

-(BOOL) tbWriteData: (NSData *) data
              error: (out NSError * _Nullable *) error {

    if (  [self respondsToSelector: @selector(writeData:error:)]  ) {
        // macOS 10.15 and higher only
        if (  ! [self writeData: data error: error]  ) {
            NSLog(@"FileHandle writeData:error: returned error: %@", (id)error);
            return NO;
        }
    } else {
        // macOS below 10.15.
        [self writeData: data]; // Might raise NSFileHandleOperationException on some errors
    }

    return YES;

}

@end
