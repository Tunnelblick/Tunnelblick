/*
 * Copyright 2026 Jonathan K. Bullard. All rights reserved.
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
 *  distribution); if not, see http://www.gnu.org/licenses/.
 */

#import "mipFile.h"

#import <stdio.h>
#import <string.h>
#import <sys/stat.h>
#import <unistd.h>

#define ARG_CFG_FILENAME 3

NSString * managementPasswordFilePathInDirectory(NSString * directory, NSString * configName)
{
    if (  ([directory length] == 0) || ([configName length] == 0)  ) {
        return nil;
    }

    NSMutableString * name = [[[configName stringByAppendingPathExtension: @"mip"] mutableCopy] autorelease];
    [name replaceOccurrencesOfString: @"/" withString: @"-S" options: 0 range: NSMakeRange(0, [name length])];
    return [directory stringByAppendingPathComponent: name];
}

BOOL writeManagementPasswordFileInDirectory(NSString * directory, NSString * configName, NSString * contents)
{
    if (  ([directory length] == 0) || ([configName length] == 0) || ([contents length] == 0)  ) {
        return YES;
    }

    NSFileManager * fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (  ! [fm fileExistsAtPath: directory isDirectory: &isDir]  ) {
        NSError * err = nil;
        if (  ! [fm createDirectoryAtPath: directory withIntermediateDirectories: YES attributes: nil error: &err]  ) {
            return NO;
        }
        if (  chmod([directory fileSystemRepresentation], 0755) != 0  ) {
            return NO;
        }
    } else if (  ! isDir  ) {
        return NO;
    }

    NSString * path = managementPasswordFilePathInDirectory(directory, configName);
    if (  path == nil  ) {
        return NO;
    }

    const char * path_c = [path fileSystemRepresentation];
    mode_t old_umask = umask(0077);
    FILE * file = fopen(path_c, "w");
    if (  file == NULL  ) {
        umask(old_umask);
        return NO;
    }
    umask(old_umask);

    const char * contents_c = [contents cStringUsingEncoding: NSASCIIStringEncoding];
    if (  contents_c == NULL  ) {
        fclose(file);
        return NO;
    }
    size_t len = strlen(contents_c);
    size_t written = fwrite(contents_c, 1, len, file);
    if (  written != len  ) {
        fclose(file);
        return NO;
    }
    if (  fclose(file) != 0  ) {
        return NO;
    }
    return YES;
}

BOOL writeManagementPasswordFileFromAtsystemstartArgs(int argc, char * argv[], NSString * directory)
{
    if (   (argc <= ARG_CFG_FILENAME)
        || (argv == NULL)
        || (strcmp(argv[2], "start") != 0)
        || (strlen(argv[argc - 1]) == 0)  ) {
        return YES;
    }

    NSString * configName = [NSString stringWithUTF8String: argv[ARG_CFG_FILENAME]];
    NSString * contents   = [NSString stringWithUTF8String: argv[argc - 1]];
    if (  (configName == nil) || (contents == nil)  ) {
        return NO;
    }
    return writeManagementPasswordFileInDirectory(directory, configName, contents);
}

BOOL connectOnSystemStartSetupIsComplete(BOOL plistMatches, BOOL mipExists)
{
    return plistMatches && mipExists;
}
