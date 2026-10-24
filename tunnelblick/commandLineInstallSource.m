/*
 * This file is part of Tunnelblick.
 *
 * Tunnelblick is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2
 * as published by the Free Software Foundation.
 */

#import "commandLineInstallSource.h"

#import "defines.h"

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

    return [stagingDirectory stringByAppendingPathComponent: sourcePath.lastPathComponent];
}
