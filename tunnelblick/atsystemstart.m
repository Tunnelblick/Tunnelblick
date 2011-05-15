/*
 * Copyright 2010, 2011 Jonathan K. Bullard
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

/* This program must be run as root via executeAuthorized so it can make modifications to /Library/LaunchDaemons.
 *
 * It sets up to either run, or not run, openvpnstart with specified arguments at system startup.
 * It does this by placing, or removing, a .plist file in /Library/LaunchDaemons
 *
 * This command is called with its own single argument followed by the arguments to run "openvpnstart start" with
 * If the first argument is "1", this program will set up to RUN openvpnstart at system startup with the rest of the arguments.
 * If the first argument is "0", this program will set up to NOT RUN openvpnstart at system startup with the rest of the arguments.
 *
 * When finished (or if an error occurs), the file /tmp/tunnelblick-authorized-running is deleted to indicate the program has finished
 *
 * Note: Although this program returns EXIT_SUCCESS or EXIT_FAILURE, that code is not returned to the invoker of executeAuthorized.
 * The code returned by executeAuthorized indicates only success or failure to launch this program. Thus, the invoking program must
 * determine whether or not this program completed its task successfully.
 *
 */

#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import "defines.h"
#import "NSFileManager+TB.h"

// Indices into argv[] for items we use. The first is an argument to this program; the other two are arguments to openvpnstart
#define ARG_LOAD_FLAG    1
#define ARG_CFG_FILENAME 3
#define ARG_CFG_LOC      7

NSAutoreleasePool   * pool;

void        setNoStart(NSString * plistPath);
void        setStart(NSString * plistPath, NSString * daemonDescription, NSString * daemonLabel, int argc, char* argv[]);
NSString *  getWorkingDirectory(int argc, char* argv[]);
void        errorExit(void);
void        deleteFlagFile(void);

//**************************************************************************************************************************
int main(int argc, char* argv[])
{
    pool = [[NSAutoreleasePool alloc] init];
    
    // Validate our arguments
    if (   (argc < 5)
        || (argc > 11)
        || (   ( strcmp(argv[ARG_LOAD_FLAG], "0") != 0 )
            && ( strcmp(argv[ARG_LOAD_FLAG], "1") != 0 )
            )
        ) {
        NSLog(@"Tunnelblick atsystemstart: Argument #%d must be 0 or 1 and there must be between 5 to 11 (inclusive) arguments altogether. argc = %d; argv[%d] = '%s'", ARG_LOAD_FLAG, argc, ARG_LOAD_FLAG, argv[ARG_LOAD_FLAG]);
        errorExit();
    }
    
    // Get a description and label for the daemon, and the path for the .plist
    NSString * displayName = [[NSString stringWithUTF8String: argv[ARG_CFG_FILENAME]] stringByDeletingPathExtension];
    
    NSString * daemonDescription = [NSString stringWithFormat: @"Processes Tunnelblick 'Connect when system starts' for VPN configuration '%@'", displayName];
    
    // Create a name for the daemon, consisting of the display name but with "path" characters (slashes and periods) escaped.
    // This is done because a display name might look like "abc/def.ghi/jkl" and we need something that can be a single path component without an extension.
    NSMutableString * sanitizedDaemonName = [[displayName mutableCopy] autorelease];
    [sanitizedDaemonName replaceOccurrencesOfString: @"-" withString: @"--" options: 0 range: NSMakeRange(0, [sanitizedDaemonName length])];
    [sanitizedDaemonName replaceOccurrencesOfString: @"." withString: @"-D" options: 0 range: NSMakeRange(0, [sanitizedDaemonName length])];
    [sanitizedDaemonName replaceOccurrencesOfString: @"/" withString: @"-S" options: 0 range: NSMakeRange(0, [sanitizedDaemonName length])];
    
    NSString * daemonLabel = [NSString stringWithFormat: @"net.tunnelblick.startup.%@", sanitizedDaemonName];
    
    NSString * plistPath = [NSString stringWithFormat: @"/Library/LaunchDaemons/%@.plist", daemonLabel];
    
    if (  strcmp(argv[ARG_LOAD_FLAG], "0") == 0  ) {
        setNoStart(plistPath);
    } else {
        setStart(plistPath, daemonDescription, daemonLabel, argc, argv);
    }
    
    deleteFlagFile();

    [pool drain];
    exit(EXIT_SUCCESS);
}

void setNoStart(NSString * plistPath)
{
    NSFileManager * fm = [NSFileManager defaultManager];
    if (  [fm tbPathContentOfSymbolicLinkAtPath: plistPath] == nil  ) {
        if (  [fm fileExistsAtPath: plistPath]  ) {
            if ( ! [fm tbRemoveFileAtPath: plistPath handler: nil]  ) {
                NSLog(@"Tunnelblick atsystemstart: Unable to delete existing plist file %@", plistPath);
                errorExit();
            }
        } else {
            NSLog(@"Tunnelblick atsystemstart: Does not exist, so cannot delete %@", plistPath);
            errorExit();
        }
    } else {
        NSLog(@"Tunnelblick atsystemstart: Symbolic link not allowed at %@", plistPath);
        errorExit();
    }
}

void setStart(NSString * plistPath, NSString * daemonDescription, NSString * daemonLabel, int argc, char* argv[])
{
    // Note: When creating the .plist, we don't use the "Program" key, because we want the first argument to be the path to the program,
    // so openvpnstart can know where it is, so it can find other Tunnelblick compenents.
    
    NSString * openvpnstartPath = [[NSBundle mainBundle] pathForResource: @"openvpnstart" ofType: nil];
    
    NSMutableArray * arguments = [NSMutableArray arrayWithObject: openvpnstartPath];
    int i;
    for (i=2; i<argc; i++) {
        [arguments addObject: [NSString stringWithUTF8String: argv[i]]];
    }
    
    NSString * workingDirectory = getWorkingDirectory(argc, argv);
    
    NSDictionary * plistDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                daemonLabel,                    @"Label",
                                arguments,                      @"ProgramArguments",
                                workingDirectory,               @"WorkingDirectory",
                                daemonDescription,              @"ServiceDescription",
                                [NSNumber numberWithBool: YES], @"onDemand",
                                [NSNumber numberWithBool: YES], @"RunAtLoad",
                                nil];
    
    if (  [[NSFileManager defaultManager] tbPathContentOfSymbolicLinkAtPath: plistPath] != nil  ) {
        NSLog(@"Tunnelblick atsystemstart: Symbolic link not allowed at %@", plistPath);
        errorExit();
    }
    
    if (  ! [plistDict writeToFile: plistPath atomically: YES]  ) {
        NSLog(@"Tunnelblick atsystemstart: Unable to write plist file %@", plistPath);
        errorExit();
    }
}

NSString * getWorkingDirectory(int argc, char* argv[])
{
    NSString * cfgFile = [NSString stringWithUTF8String: argv[ARG_CFG_FILENAME]];

    NSString * extension = [cfgFile pathExtension];
    if (  ! [extension isEqualToString: @"tblk"]) {
        NSLog(@"Tunnelblick atsystemstart: Only Tunnelblick VPN Configurations (.tblk packages) may connect when the computer starts\n");
        errorExit();
    }
    
    NSString * cfgPath = nil;
    
    unsigned  cfgLocCode = 0;
    if (  argc > ARG_CFG_LOC  ) {
        cfgLocCode = atoi(argv[ARG_CFG_LOC]);
    }
    
    if (  cfgLocCode == CFG_LOC_DEPLOY  ) {
        NSString * deployDirectory = [[NSBundle mainBundle] pathForResource: @"Deploy" ofType: nil];
        cfgPath = [deployDirectory stringByAppendingPathComponent: cfgFile];
    } else if (cfgLocCode == CFG_LOC_SHARED  ) {
        cfgPath = [@"/Library/Application Support/Tunnelblick/Shared" stringByAppendingPathComponent: cfgFile];
    } else {
        NSLog(@"Tunnelblick atsystemstart: Invalid cfgLocCode = %d", cfgLocCode);
        errorExit();
    }
    
    NSString * workingDirectory = [cfgPath stringByAppendingPathComponent: @"Contents/Resources"];
    return workingDirectory;
}

void errorExit(void)
{
    deleteFlagFile();
    
    [pool drain];
    exit(EXIT_FAILURE);
}

void deleteFlagFile(void)
{
    char * path = "/tmp/tunnelblick-authorized-running";
    struct stat sb;
	if (  0 == stat(path, &sb)  ) {
        if (  (sb.st_mode & S_IFMT) == S_IFREG  ) {
            if (  0 != unlink(path)  ) {
                NSLog(@"Tunnelblick atsystemstart: Unable to delete %s", path);
            }
        } else {
            NSLog(@"Tunnelblick atsystemstart: %s is not a regular file; st_mode = 0%o", path, sb.st_mode);
        }
    } else {
        NSLog(@"Tunnelblick atsystemstart: stat of %s failed\nError was '%s'", path, strerror(errno));
    }
}
