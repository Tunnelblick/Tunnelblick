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
NSString * commandLineInstallStagedSourcePath(NSString * sourcePath, NSString * stagingDirectory);
