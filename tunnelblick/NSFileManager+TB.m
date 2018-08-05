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

id fmCallStack(void) {
    
    return (  [NSThread respondsToSelector: @selector(callStackSymbols)]
            ? (id) [NSThread callStackSymbols]
            : (id) @"not available");
}
void appendLog(NSString * errMsg);

@implementation NSFileManager (TB)

-(BOOL) tbChangeFileAttributes:(NSDictionary *)attributes atPath:(NSString *)path {
    
    if (  [self respondsToSelector:@selector (setAttributes:ofItemAtPath:error:)]  ) {
        NSError * err = nil;
        BOOL answer = [self setAttributes:attributes ofItemAtPath:path error: &err];
        if (  ! answer  ) {
			NSString * errMsg = [NSString stringWithFormat: @"Error returned from setAttributes: %@ ofItemAtPath: %@; Error was %@; stack trace: %@", attributes, path, err, fmCallStack()];
            appendLog(errMsg);
        }
        return answer;
    }
    
    appendLog(@"No implementation for changeFileAttributes:atPath:");
    return NO;
}


-(BOOL) tbCopyPath:(NSString *)source toPath:(NSString *)destination handler:(id)handler {
    
    (void) handler;
    
    if (  [self respondsToSelector:@selector (copyItemAtPath:toPath:error:)]  ) {
		NSError * err = nil;
        BOOL answer = [self copyItemAtPath:source toPath:destination error: &err];
        if (  ! answer  ) {
			NSString * errMsg = [NSString stringWithFormat: @"Error returned from copyItemAtPath: %@ toPath: %@; Error was %@; stack trace: %@", source, destination, err, fmCallStack()];
            appendLog(errMsg);
        }
        return answer;
    }
    
    appendLog(@"No implementation for copyPath:toPath:handler:");
    return NO;
}


-(BOOL) tbCreateDirectoryAtPath:(NSString *)path attributes:(NSDictionary *)attributes {
    
    if (  [self respondsToSelector:@selector (createDirectoryAtPath:withIntermediateDirectories:attributes:error:)]  ) {
        NSError * err = nil;
        BOOL answer = [self createDirectoryAtPath:path withIntermediateDirectories:NO attributes:attributes error: &err];
        if (  ! answer  ) {
            NSString * errMsg = [NSString stringWithFormat: @"Error returned from createDirectoryAtPath: %@ withIntermediateDirectories: NO attributes: %@; Error was %@; stack trace: %@", path, attributes, err, fmCallStack()];
            appendLog(errMsg);
        }
        return answer;
    }
    
    appendLog(@"No implementation for createDirectoryAtPath:attributes:");
    return NO;
}

-(BOOL) tbCreateSymbolicLinkAtPath:(NSString *)path pathContent:(NSString *)otherPath {
    
    if (  [self respondsToSelector:@selector (createSymbolicLinkAtPath:withDestinationPath:error:)]  ) {
        NSError * err = nil;
        BOOL answer = [self createSymbolicLinkAtPath:path withDestinationPath:otherPath error: &err];
        if (  ! answer  ) {
			NSString * errMsg = [NSString stringWithFormat: @"Error returned from createSymbolicLinkAtPath: %@ withDestinationPath: %@; Error was %@; stack trace: %@", path, otherPath, err, fmCallStack()];
            appendLog(errMsg);
        }
        return answer;
    }
    
    appendLog(@"No implementation for createSymbolicLinkAtPath:pathContent:");
    return NO;
}


-(NSArray *) tbDirectoryContentsAtPath:(NSString *)path {
    
    if (  [self respondsToSelector:@selector (contentsOfDirectoryAtPath:error:)]  ) {
        NSError * err = nil;
        NSArray * answer = [self contentsOfDirectoryAtPath:path error: &err];
        if (  ! answer  ) {
			NSString * errMsg = [NSString stringWithFormat: @"Error returned from contentsOfDirectoryAtPath: %@; Error was %@; stack trace: %@", path, err, fmCallStack()];
            appendLog(errMsg);
        }
        return answer;
    }
    
    appendLog(@"No implementation for directoryContentsAtPath:");
    return nil;
}


-(NSDictionary *) tbFileAttributesAtPath:(NSString *)path traverseLink:(BOOL)flag {
    
    if (  [self respondsToSelector:@selector (attributesOfItemAtPath:error:)]  ) {
        NSError * err = nil;
        NSDictionary * attributes = [self attributesOfItemAtPath:path error: &err];
        if (  ! attributes  ) {
			NSString * errMsg = [NSString stringWithFormat: @"Error returned from attributesOfItemAtPath: %@;\nError was %@; stack trace: %@", path, err, fmCallStack()];
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
				NSString * errMsg = [NSString stringWithFormat: @"Error returned from tbPathContentOfSymbolicLinkAtPath: %@;\nOriginal path = %@; stack trace: %@", newPath, path, fmCallStack()];
                appendLog(errMsg);
				return nil;
			}
			if (  ! [realPath hasPrefix: @"/"]  ) {
				realPath = [[newPath stringByDeletingLastPathComponent] stringByAppendingPathComponent: realPath];
			}
            attributes = [self attributesOfItemAtPath:realPath error: &err];
            if (  ! attributes  ) {
				NSString * errMsg = [NSString stringWithFormat: @"Error returned from attributesOfItemAtPath: %@;\nOriginal path was %@\nLatest path = %@;\nError was %@; stack trace: %@", realPath, path, newPath, err, fmCallStack()];
                appendLog(errMsg);
                return nil;
            }
            newPath = [[realPath copy] autorelease];
        }
		if (  counter >= 10  ) {
			NSString * errMsg = [NSString stringWithFormat: @"tbFileAttributesAtPath detected a symlink loop.\nOriginal path was %@\nLast \"Real\" path was %@, attributes = %@; stack trace: %@", path, realPath, attributes, fmCallStack()];
            appendLog(errMsg);
		}
        return attributes;
    }
    
    appendLog(@"No implementation for fileAttributesAtPath:traverseLink:");
    return nil;
}


-(BOOL) tbMovePath:(NSString *)source toPath:(NSString *)destination handler:(id)handler {
    
    (void) handler;
    
    if (  [self respondsToSelector:@selector (moveItemAtPath:toPath:error:)]  ) {
        // The apple docs are vague about what this does compared to movePath:toPath:handler:.
        // So we hope it works the same. (Regarding same-device moves, for example.)
        NSError * err = nil;
        BOOL answer = [self moveItemAtPath:source toPath:destination error: &err];
        if (  ! answer  ) {
			NSString * errMsg = [NSString stringWithFormat: @"Error returned from moveItemAtPath: %@ toPath: %@; Error was %@; stack trace: %@", source, destination, err, fmCallStack()];
            appendLog(errMsg);
        }
        return answer;
    }
    
    appendLog(@"No implementation for movePath:toPath:handler:");
    return NO;
}


-(BOOL) tbRemoveFileAtPath:(NSString *)path handler:(id)handler {
    
    (void) handler;
    
    if (  [self respondsToSelector:@selector (removeItemAtPath:error:)]  ) {
        NSError * err = nil;
        BOOL answer = [self removeItemAtPath:path error: &err];
        if (  ! answer  ) {
			NSString * errMsg = [NSString stringWithFormat: @"Error returned from removeItemAtPath: %@; Error was %@; stack trace: %@", path, err, fmCallStack()];
            appendLog(errMsg);
        }
        return answer;
    }
    
    appendLog(@"No implementation for removeFileAtPath:handler:");
    return NO;
}

-(BOOL) tbRemovePathIfItExists: (NSString *) path {
    
    if (  [self fileExistsAtPath: path]  ) {
        if (  ! [self tbRemoveFileAtPath: path handler: nil]  ) {
            return NO;
        }
    }
    
    return YES;
}

-(BOOL) tbForceRenamePath: (NSString *) sourcePath toPath: (NSString *) targetPath {
    
	if (  ! [self tbRemovePathIfItExists: targetPath]  ) {
        return NO;
	}
	
    int status = rename([sourcePath fileSystemRepresentation], [targetPath fileSystemRepresentation]);
    if (  status != 0  ) {
        NSString * errMsg = [NSString stringWithFormat: @"rename(%@,%@) failed; status = %ld; errno = %ld; error was '%s'; stack trace: %@", sourcePath, targetPath, (long)status, (long)errno, strerror(errno), fmCallStack()];
		appendLog(errMsg);
        return NO;
    }
    
    return YES;
}


-(NSString *) tbPathContentOfSymbolicLinkAtPath:(NSString *)path {
    
    if (  [self respondsToSelector:@selector (destinationOfSymbolicLinkAtPath:error:)]  ) {
		NSError * err = nil;
		NSString * answer = [self destinationOfSymbolicLinkAtPath:path error: &err];
		if (  ! answer  ) {
			NSString * errMsg = [NSString stringWithFormat: @"Error returned from destinationOfSymbolicLinkAtPath: %@; Error was %@; stack trace: %@", path, err, fmCallStack()];
            appendLog(errMsg);
		}
        return answer;
    }
    
    appendLog(@"No implementation for pathContentOfSymbolicLinkAtPath:");
    return nil;
}

@end
