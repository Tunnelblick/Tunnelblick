/*
 * This file is part of Tunnelblick.
 *
 * Tunnelblick is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2
 * as published by the Free Software Foundation.
 */

#import <Foundation/Foundation.h>

// YES when sourcePath is already under Temp, Users, or Shared.
// The comparison includes the trailing slash, so TempEvil does not match Temp.
BOOL commandLineInstallSourceIsInsideSecureTree(NSString * sourcePath);

// An external source must be copied into stagingDirectory before the script
// gate reads it. A source that is already inside a secure tree is returned
// unchanged. stagingDirectory is ignored in that case.
// An external path whose last component is not a .tblk name returns nil.
// That includes "/", "//", and device paths such as /dev/zero.
NSString * commandLineInstallStagedSourcePath(NSString * sourcePath, NSString * stagingDirectory);

// Bytes of a regular file. Nil when the path is missing, not a regular file,
// or a symlink. Does not follow a symlink.
NSData * commandLineInstallContentsOfRegularFile(NSString * path);
