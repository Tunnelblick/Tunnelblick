/*
 * This file is part of Tunnelblick.
 *
 * Tunnelblick is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2
 * as published by the Free Software Foundation.
 */

#import "commandLineInstallSource.h"

#import "defines.h"

#import <errno.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

static BOOL commandLineInstallPathHasPrefix(NSString * path, NSString * root) {

    if (   path.length == 0
        || root.length == 0  ) {
        return NO;
    }

    return [path hasPrefix: [root stringByAppendingString: @"/"]];
}

BOOL commandLineInstallSourceIsInsideSecureTree(NSString * sourcePath) {

    return (   commandLineInstallPathHasPrefix(sourcePath, L_AS_T_TEMP)
            || commandLineInstallPathHasPrefix(sourcePath, L_AS_T_USERS)
            || commandLineInstallPathHasPrefix(sourcePath, L_AS_T_SHARED) );
}

NSString * commandLineInstallStagedSourcePath(NSString * sourcePath, NSString * stagingDirectory) {

    if (  sourcePath.length == 0  ) {
        return nil;
    }

    if (  commandLineInstallSourceIsInsideSecureTree(sourcePath)  ) {
        return sourcePath;
    }

    if (  stagingDirectory.length == 0  ) {
        return nil;
    }

    NSString * name = sourcePath.lastPathComponent;
    if (   name.length == 0
        || [name isEqualToString: @"/"]
        || [name containsString: @"/"]
        || ( ! [sourcePath.pathExtension isEqualToString: @"tblk"] )  ) {
        return nil;
    }

    return [stagingDirectory stringByAppendingPathComponent: name];
}

NSData * commandLineInstallContentsOfRegularFile(NSString * path) {

    // dataWithContentsOfFile: follows a symlink swapped in after a path check.
    // Open the leaf with O_NOFOLLOW and keep that file descriptor.
    if (  path.length == 0  ) {
        return nil;
    }

    const char * pathC = path.fileSystemRepresentation;
    if (  pathC == NULL  ) {
        return nil;
    }

    int fd = open(pathC, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (  fd < 0  ) {
        return nil;
    }

    struct stat status;
    if (   fstat(fd, &status) != 0
        || ( ! S_ISREG(status.st_mode) )  ) {
        close(fd);
        return nil;
    }

    NSMutableData * data = [NSMutableData data];
    char buffer[16 * 1024];
    for (;;) {
        ssize_t count = read(fd, buffer, sizeof buffer);
        if (  count == 0  ) {
            break;
        }
        if (  count < 0  ) {
            if (  errno == EINTR  ) {
                continue;
            }
            close(fd);
            return nil;
        }
        [data appendBytes: buffer length: (NSUInteger)count];
    }

    close(fd);
    return data;
}
