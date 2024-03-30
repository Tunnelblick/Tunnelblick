/*
 * Copyright (c) 2010, 2011, 2012 Jonathan K. Bullard. All rights reserved.
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

//*************************************************************************************************
//
// Tunnelblick was written using many NSFileManager methods that were deprecated in 10.5.
// Such invocations have been changed to instead invoke the methods implemented here.
// (Isolating the deprecated calls in one place should make changes easier to implement.)
//
// In the code below, we use 10.5 methods if they are available, otherwise we use 10.4 methods.
// (If neither are available, we put an entry in the log and return negative results.)

#import "NSFileManager+TB.h"

#import "defines.h"

void appendLog(NSString * errMsg);

@implementation NSFileManager (TB)

-(BOOL) tbChangeFileAttributes: (NSDictionary *) attributes
                        atPath: (NSString * )    path {

    NSError * err = nil;
    if (  ! [self setAttributes: attributes ofItemAtPath: path error: &err]  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from setAttributes: %@ ofItemAtPath: '%@'; Error was %@; stack trace: %@",
                             attributes, path, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    return YES;
}


-(BOOL) tbCopyPath: (NSString *) source
            toPath: (NSString *) destination
           handler: (id)         handler {

    (void) handler;
    
    NSError * err = nil;
    if (  ! [self copyItemAtPath:source toPath:destination error: &err]  ) {
        NSString * errMsg = [NSString stringWithFormat: 
                             @"Error returned from copyItemAtPath: '%@' toPath: '%@'; Error was %@; stack trace: %@",
                             source, destination, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    return YES;
}


-(BOOL) tbCreateDirectoryAtPath: (NSString *)     path
	withIntermediateDirectories: (BOOL)           withIntermediateDirectories
					 attributes: (NSDictionary *) attributes {

	NSError * err = nil;
    if (  ! [self createDirectoryAtPath: path withIntermediateDirectories: withIntermediateDirectories attributes: attributes error: &err]  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from createDirectoryAtPath: '%@' withIntermediateDirectories: %s attributes: %@; Error was %@; stack trace: %@",
                             path, CSTRING_FROM_BOOL(withIntermediateDirectories), attributes, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    return YES;
}

-(BOOL) tbCreateSymbolicLinkAtPath: (NSString *) path
                       pathContent: (NSString *) otherPath {

    NSError * err = nil;
    if (  ! [self createSymbolicLinkAtPath: path withDestinationPath: otherPath error: &err]  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from createSymbolicLinkAtPath: '%@' withDestinationPath: '%@'; Error was %@; stack trace: %@",
                             path, otherPath, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    return YES;
}


-(NSArray *) tbDirectoryContentsAtPath:(NSString *) path {

    NSError * err = nil;
    NSArray * answer = [self contentsOfDirectoryAtPath:path error: &err];
    if (  ! answer  ) {
        NSString * errMsg = [NSString stringWithFormat: 
                             @"Error returned from contentsOfDirectoryAtPath: '%@'; Error was %@; stack trace: %@",
                             path, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
    }

    return answer;
}


-(NSDictionary *) tbFileAttributesAtPath: (NSString *) path
                            traverseLink: (BOOL)       flag {

    NSError * err = nil;
    NSDictionary * attributes = [self attributesOfItemAtPath:path error: &err];
    if (  ! attributes  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from attributesOfItemAtPath: '%@';\nError was %@; stack trace: %@",
                             path, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return nil;
    }

    unsigned int counter = 0;
    NSString * realPath = nil;
    NSString * newPath  = [[path copy] autorelease];
    while (   flag
           && ( counter++ < 10 )
           && [[attributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink] ) {
        realPath = [self tbPathContentOfSymbolicLinkAtPath: newPath];
        if (  ! realPath  ) {
            return nil;
        }
        if (  ! [realPath hasPrefix: @"/"]  ) {
            realPath = [[newPath stringByDeletingLastPathComponent] stringByAppendingPathComponent: realPath];
        }
        attributes = [self attributesOfItemAtPath:realPath error: &err];
        if (  ! attributes  ) {
            NSString * errMsg = [NSString stringWithFormat:
                                 @"Error returned from attributesOfItemAtPath: '%@';\nOriginal path was' %@'\nLatest path = '%@';\nError was %@; stack trace: %@",
                                 realPath, path, newPath, err, [NSThread callStackSymbols]];
            appendLog(errMsg);
            return nil;
        }

        newPath = [[realPath copy] autorelease];
    }

    if (  counter >= 10  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"tbFileAttributesAtPath detected a symlink loop.\nOriginal path was '%@'\nLast \"Real\" path was '%@', attributes = %@; stack trace: %@",
                             path, realPath, attributes, [NSThread callStackSymbols]];
        appendLog(errMsg);
    }

    return attributes;
}


-(BOOL) tbMovePath: (NSString *) source
            toPath: (NSString *) destination
           handler: (id)         handler {

    (void) handler;
    
    NSError * err = nil;
    if (  ! [self moveItemAtPath: source toPath: destination error: &err]  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from moveItemAtPath: '%@' toPath: '%@'; Error was %@; stack trace: %@",
                             source, destination, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    return YES;
}


-(BOOL) tbRemoveFileAtPath: (NSString *) path
                   handler: (id) handler {

    (void) handler;
    
    NSError * err = nil;
    if (  ! [self removeItemAtPath:path error: &err]  ) {
        NSString * errMsg = [NSString stringWithFormat: 
                             @"Error returned from removeItemAtPath: '%@'; Error was %@; stack trace: %@",
                             path, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
        return NO;
    }

    return YES;
}

-(BOOL) tbRemovePathIfItExists: (NSString *) path {
    
    if (  [self fileExistsAtPath: path]  ) {
        NSError * err = nil;
        if (  ! [self removeItemAtPath: path error: &err]  ) {
            NSString * errMsg = [NSString stringWithFormat:
                                 @"remove '%@' failed; error was '%@'; stack trace: %@",
                                 path, err, [NSThread callStackSymbols]];
            appendLog(errMsg);
            return NO;
        }
    }
    
    return YES;
}

-(BOOL) tbForceRenamePath: (NSString *) sourcePath
                   toPath: (NSString *) targetPath {

    int status = rename([sourcePath fileSystemRepresentation], [targetPath fileSystemRepresentation]);
    if (  status != 0  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"rename('%@','%@') failed; status = %ld; errno = %ld; error was '%s'; stack trace: %@",
                             sourcePath, targetPath, (long)status, (long)errno, strerror(errno), [NSThread callStackSymbols]];
		appendLog(errMsg);
        return NO;
    }
    
    return YES;
}


-(NSString *) tbPathContentOfSymbolicLinkAtPath: (NSString *) path {

    NSError * err = nil;
    NSString * answer = [self destinationOfSymbolicLinkAtPath:path error: &err];
    if (  ! answer  ) {
        NSString * errMsg = [NSString stringWithFormat:
                             @"Error returned from destinationOfSymbolicLinkAtPath: '%@'; Error was %@; stack trace: %@",
                             path, err, [NSThread callStackSymbols]];
        appendLog(errMsg);
    }

    return answer;
}

@end
