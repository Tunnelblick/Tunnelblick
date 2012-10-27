/*
 * Copyright (c) 2010 Jonathan Bullard
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


@implementation NSFileManager (TB)

-(BOOL) tbChangeFileAttributes:(NSDictionary *)attributes atPath:(NSString *)path
{
    if (  [self respondsToSelector:@selector (setAttributes:ofItemAtPath:error:)]  ) {
        return [self setAttributes:attributes ofItemAtPath:path error:NULL];
    } else if (  [self respondsToSelector:@selector (changeFileAttributes:atPath:)]  ) {
        return [self changeFileAttributes:attributes atPath:path];
    } else {
        NSLog(@"No implementation for changeFileAttributes:atPath:");
        return NO;
    }
}


-(BOOL) tbCopyPath:(NSString *)source toPath:(NSString *)destination handler:(id)handler
{
    if (  [self respondsToSelector:@selector (copyItemAtPath:toPath:error:)]  ) {
        return [self copyItemAtPath:source toPath:destination error:NULL];
    } else if (  [self respondsToSelector:@selector (copyPath:toPath:handler:)]  ) {
        return [self copyPath:source toPath:destination handler:handler];
    } else {
        NSLog(@"No implementation for copyPath:toPath:handler:");
        return NO;
    }
}


-(BOOL) tbCreateDirectoryAtPath:(NSString *)path attributes:(NSDictionary *)attributes
{
    if (  [self respondsToSelector:@selector (createDirectoryAtPath:attributes:)]  ) {
        return [self createDirectoryAtPath:path attributes:attributes];
    } else if (  [self respondsToSelector:@selector (createDirectoryAtPath:withIntermediateDirectories:attributes:error:)]  ) {
        return [self createDirectoryAtPath:path withIntermediateDirectories:NO attributes:attributes error:NULL];
    } else {
        NSLog(@"No implementation for createDirectoryAtPath:attributes:");
        return NO;
    }
}

-(BOOL) tbCreateSymbolicLinkAtPath:(NSString *)path pathContent:(NSString *)otherPath
{
    if (  [self respondsToSelector:@selector (createSymbolicLinkAtPath:pathContent:)]  ) {
        return [self createSymbolicLinkAtPath:path pathContent:otherPath];
    } else if (  [self respondsToSelector:@selector (createSymbolicLinkAtPath:withDestinationPath:error:)]  ) {
        return [self createSymbolicLinkAtPath:path withDestinationPath:otherPath error:NULL];
    } else {
        NSLog(@"No implementation for createSymbolicLinkAtPath:pathContent:");
        return NO;
    }
}


-(NSArray *) tbDirectoryContentsAtPath:(NSString *)path
{
    if (  [self respondsToSelector:@selector (directoryContentsAtPath:)]  ) {
        return [self directoryContentsAtPath:path];
    } else if (  [self respondsToSelector:@selector (contentsOfDirectoryAtPath:error:)]  ) {
        return [self contentsOfDirectoryAtPath:path error:NULL];
    } else {
        NSLog(@"No implementation for directoryContentsAtPath:");
        return nil;
    }
}


-(NSDictionary *) tbFileAttributesAtPath:(NSString *)path traverseLink:(BOOL)flag
{
    if (  [self respondsToSelector:@selector (fileAttributesAtPath:traverseLink:)]  ) {
        return [self fileAttributesAtPath:path traverseLink:flag];
    } else if (  [self respondsToSelector:@selector (attributesOfItemAtPath:error:)]  ) {
        // Apple documents say this will not traverse the last link in 10.5 and 10.6, but
        // has a note that "This behavior may change in a future version of the Mac OS X."
        // If it doesn't traverse the last link, and we want it to, we can -- and do --
        // traverse it in the code below.
        // But if it is a link, and we don't want to traverse it, and OS X TRAVERSES IT,
        // then we'll have to go to using BSD file access to implement this
        NSDictionary * attributes = [self attributesOfItemAtPath:path error: NULL];
        while (   flag
            && [[attributes objectForKey: NSFileType] isEqualToString: NSFileTypeSymbolicLink] ) {
            NSString * realPath = [self tbPathContentOfSymbolicLinkAtPath:path];
            attributes = [self attributesOfItemAtPath:realPath error:NULL];
        }
        return attributes;
    } else {
        NSLog(@"No implementation for fileAttributesAtPath:traverseLink:");
        return nil;
    }
}


-(BOOL) tbMovePath:(NSString *)source toPath:(NSString *)destination handler:(id)handler
{
    if (  [self respondsToSelector:@selector (movePath:toPath:handler:)]  ) {
        return [self movePath:source toPath:destination handler:handler];
    } else if (  [self respondsToSelector:@selector (moveItemAtPath:toPath:error:)]  ) {
        // The apple docs are vague about what this does compared to movePath:toPath:handler:.
        // So we hope it works the same. (Regarding same-device moves, for example.)
        return [self moveItemAtPath:source toPath:destination error:NULL];
    } else {
        NSLog(@"No implementation for movePath:toPath:handler:");
        return NO;
    }
}


-(BOOL) tbRemoveFileAtPath:(NSString *)path handler:(id)handler
{
    if (  [self respondsToSelector:@selector (removeFileAtPath:handler:)]  ) {
        return [self removeFileAtPath:path handler:nil];
    } else if (  [self respondsToSelector:@selector (removeItemAtPath:error:)]  ) {
        return [self removeItemAtPath:path error:NULL];
    } else {
        NSLog(@"No implementation for removeFileAtPath:handler:");
        return NO;
    }
}


-(NSString *) tbPathContentOfSymbolicLinkAtPath:(NSString *)path
{
    if (  [self respondsToSelector:@selector (pathContentOfSymbolicLinkAtPath:)]  ) {
        return [self pathContentOfSymbolicLinkAtPath:path];
    } else if (  [self respondsToSelector:@selector (destinationOfSymbolicLinkAtPath:error:)]  ) {
        return [self destinationOfSymbolicLinkAtPath:path error:NULL];
    } else {
        NSLog(@"No implementation for pathContentOfSymbolicLinkAtPath:");
        return nil;
    }
}
@end
