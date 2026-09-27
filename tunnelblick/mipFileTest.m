/*
 * Compile and run (no Xcode project; this file is not part of Tunnelblick.app):
 *
 *   clang -fobjc-arc -framework Foundation \
 *     -o /tmp/mipFileTest tunnelblick/mipFileTest.m tunnelblick/mipFile.m
 *   /tmp/mipFileTest
 */

#import <Foundation/Foundation.h>
#import "mipFile.h"

static int gFails = 0;

static void expectTrue(BOOL cond, const char * msg)
{
    if (  ! cond  ) {
        fprintf(stderr, "FAIL: %s\n", msg);
        gFails++;
    }
}

int main(void)
{
    @autoreleasepool {
        NSString * path = managementPasswordFilePathInDirectory(@"/tmp/mips", @"MyVPN.tblk");
        expectTrue([path isEqualToString: @"/tmp/mips/MyVPN.tblk.mip"], "plain config name");

        path = managementPasswordFilePathInDirectory(@"/tmp/mips", @"a/b");
        expectTrue([path isEqualToString: @"/tmp/mips/a-Sb.mip"], "slash becomes -S");

        expectTrue(managementPasswordFilePathInDirectory(@"", @"x") == nil, "empty dir");
        expectTrue(managementPasswordFilePathInDirectory(@"/tmp", @"") == nil, "empty name");

        expectTrue(connectOnSystemStartSetupIsComplete(YES, YES), "plist+mip ready");
        expectTrue( ! connectOnSystemStartSetupIsComplete(YES, NO), "plist match without mip is not ready");
        expectTrue( ! connectOnSystemStartSetupIsComplete(NO, YES), "mip without matching plist is not ready");

        NSString * dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [[NSUUID UUID] UUIDString]];
        char * argvStart[] = {
            (char *)"atsystemstart",
            (char *)"1",
            (char *)"start",
            (char *)"Demo.tblk",
            (char *)"1194",
            (char *)"2",
            (char *)"0",
            (char *)"1",
            (char *)"0",
            (char *)"0",
            (char *)"-i",
            (char *)"2.6.14",
            (char *)"abcdefghijklmnopabcdefghijklmnopabcdefghijklmnopabcdefghijklmnop",
            NULL
        };
        int argcStart = 13;
        expectTrue(writeManagementPasswordFileFromAtsystemstartArgs(argcStart, argvStart, dir),
                   "write from start args");
        NSString * written = [dir stringByAppendingPathComponent: @"Demo.tblk.mip"];
        NSData * data = [NSData dataWithContentsOfFile: written];
        NSString * text = data ? [[NSString alloc] initWithData: data encoding: NSASCIIStringEncoding] : nil;
        expectTrue([text isEqualToString: @"abcdefghijklmnopabcdefghijklmnopabcdefghijklmnopabcdefghijklmnop"],
                   "mip contents match last start arg");

        char * argvEmpty[] = {
            (char *)"atsystemstart", (char *)"1", (char *)"start",
            (char *)"Other.tblk", (char *)""
        };
        expectTrue(writeManagementPasswordFileFromAtsystemstartArgs(5, argvEmpty, dir),
                   "empty password is a skip, not a failure");
        expectTrue( ! [[NSFileManager defaultManager] fileExistsAtPath:
                       [dir stringByAppendingPathComponent: @"Other.tblk.mip"]],
                   "empty password does not create a file");

        [[NSFileManager defaultManager] removeItemAtPath: dir error: nil];
    }

    if (  gFails != 0  ) {
        fprintf(stderr, "%d failed\n", gFails);
        return 1;
    }
    fprintf(stdout, "ok\n");
    return 0;
}
