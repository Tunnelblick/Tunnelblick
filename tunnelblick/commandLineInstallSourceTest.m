/*
 * This file is part of Tunnelblick.
 *
 * Tunnelblick is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2
 * as published by the Free Software Foundation.
 */

#import "commandLineInstallSource.h"

#import "defines.h"

#import <unistd.h>

static int gFailures = 0;

static void expectTrue(BOOL condition, const char * message) {

    if (  ! condition  ) {
        fprintf(stderr, "FAIL: %s\n", message);
        gFailures++;
    }
}

int main(void) {

    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    NSString * desktop = @"/Users/jane/Desktop/Office.tblk";
    NSString * staging = [L_AS_T_TEMP stringByAppendingPathComponent: @"CommandLineInstall-test"];
    NSString * staged = commandLineInstallStagedSourcePath(desktop, staging);

    expectTrue(commandLineInstallSourceIsInsideSecureTree(desktop) == NO,
               "a Desktop configuration is not already in a secure tree");
    expectTrue([staged hasPrefix: [staging stringByAppendingString: @"/"]],
               "an external configuration is copied under the staging directory");
    expectTrue([staged.lastPathComponent isEqualToString: @"Office.tblk"],
               "the staged copy keeps the configuration's filename");

    NSString * tempEvil = @"/Library/Application Support/Tunnelblick/TempEvil/Office.tblk";
    NSString * stagedEvil = commandLineInstallStagedSourcePath(tempEvil, staging);
    expectTrue(commandLineInstallSourceIsInsideSecureTree(tempEvil) == NO,
               "TempEvil is not the Temp directory");
    expectTrue([stagedEvil hasPrefix: [staging stringByAppendingString: @"/"]],
               "TempEvil is staged instead of treated as Temp");

    NSString * alreadyTemp = [L_AS_T_TEMP stringByAppendingPathComponent: @"Office.tblk"];
    NSString * alreadyUsers = [[L_AS_T_USERS stringByAppendingPathComponent: @"jane"]
                               stringByAppendingPathComponent: @"Office.tblk"];
    NSString * alreadyShared = [L_AS_T_SHARED stringByAppendingPathComponent: @"Office.tblk"];

    expectTrue([commandLineInstallStagedSourcePath(alreadyTemp, staging) isEqualToString: alreadyTemp],
               "a Temp source is not staged again");
    expectTrue([commandLineInstallStagedSourcePath(alreadyUsers, staging) isEqualToString: alreadyUsers],
               "a Users source is not staged again");
    expectTrue([commandLineInstallStagedSourcePath(alreadyShared, staging) isEqualToString: alreadyShared],
               "a Shared source is not staged again");
    expectTrue(commandLineInstallStagedSourcePath(nil, staging) == nil,
               "a nil source stays nil");
    expectTrue(commandLineInstallStagedSourcePath(@"", staging) == nil,
               "an empty source stays nil");
    expectTrue(commandLineInstallStagedSourcePath(@"/", staging) == nil,
               "the root directory is not a configuration filename");
    expectTrue(commandLineInstallStagedSourcePath(@"//", staging) == nil,
               "a doubled root path is not a configuration filename");
    expectTrue(commandLineInstallStagedSourcePath(@"/dev/zero", staging) == nil,
               "a device path is not staged");
    expectTrue(commandLineInstallStagedSourcePath(@"/Users/jane/Desktop/Office.ovpn", staging) == nil,
               "a bare .ovpn file is not staged");

    NSString * regularPath = @"/tmp/tb-f044-regular-file";
    NSString * linkPath = @"/tmp/tb-f044-regular-link";
    unlink(regularPath.UTF8String);
    unlink(linkPath.UTF8String);
    expectTrue([@"hello" writeToFile: regularPath atomically: NO encoding: NSUTF8StringEncoding error: nil],
               "wrote a regular file");
    expectTrue(symlink(regularPath.UTF8String, linkPath.UTF8String) == 0,
               "created a symlink to the regular file");
    NSData * regularBytes = commandLineInstallContentsOfRegularFile(regularPath);
    NSData * linkBytes = commandLineInstallContentsOfRegularFile(linkPath);
    expectTrue([regularBytes isEqualToData: [@"hello" dataUsingEncoding: NSUTF8StringEncoding]],
               "a regular file is read");
    expectTrue(linkBytes == nil,
               "a symlink is not followed");
    expectTrue(commandLineInstallContentsOfRegularFile(@"/dev/zero") == nil,
               "a device is not read");
    unlink(regularPath.UTF8String);
    unlink(linkPath.UTF8String);

    [pool drain];

    if (  gFailures != 0  ) {
        fprintf(stderr, "%d failure(s)\n", gFailures);
        return 1;
    }

    printf("ok\n");
    return 0;
}
