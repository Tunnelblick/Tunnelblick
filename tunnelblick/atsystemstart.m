/*
 * Copyright 2010, 2011 2012, 2013, 2016 Jonathan K. Bullard. All rights reserved.
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
 // If no error occurs, the file AUTHORIZED_ERROR_PATH is deleted
 * When finished (or if an error occurs), the file AUTHORIZED_RUNNING_PATH is deleted to indicate the program has finished
 *
 * Note: Although this program returns EXIT_SUCCESS or EXIT_FAILURE, that code is not returned to the invoker of executeAuthorized.
 * The code returned by executeAuthorized indicates only success or failure to launch this program. Thus, the invoking program must
 * determine whether or not this program completed its task successfully.
 *
 */

#import <Foundation/Foundation.h>
#import <sys/stat.h>

#import "defines.h"
#import "sharedRoutines.h"

#import "NSFileManager+TB.h"

// Indices into argv[] for items we use. The first is an argument to this program; the other two are arguments to openvpnstart
#define ARG_LOAD_FLAG    1
#define ARG_CFG_FILENAME 3
#define ARG_CFG_LOC      7

NSAutoreleasePool   * pool;
NSString *            gDeployPath;

void        setNoStart(NSString * plistPath);
void        setStart(NSString * plistPath, NSString * daemonDescription, NSString * daemonLabel, int argc, char* argv[]);
NSString *  getWorkingDirectory(int argc, char* argv[]);
void        errorExit(void);
void        deleteFlagFile(NSString * path);

//**************************************************************************************************************************
int main(int argc, char* argv[])
{
    pool = [[NSAutoreleasePool alloc] init];
    
    NSBundle * ourBundle     = [NSBundle mainBundle];
    NSString * resourcesPath = [ourBundle bundlePath];
    NSArray  * execComponents = [resourcesPath pathComponents];
    if (  [execComponents count] < 3  ) {
        NSLog(@"Tunnelblick: too few execComponents; resourcesPath = %@", resourcesPath);
        errorExit();
    }
	gDeployPath = [[resourcesPath stringByAppendingPathComponent: @"Deploy"] copy];
	
#ifdef TBDebug
    NSLog(@"Tunnelblick: WARNING: This is an insecure copy of atsystemstart to be used for debugging only!");
#else
    if (   ([execComponents count] != 5)
        || [[execComponents objectAtIndex: 0] isNotEqualTo: @"/"]
        || [[execComponents objectAtIndex: 1] isNotEqualTo: @"Applications"]
        //                                                  Allow any name for Tunnelblick.app
        || [[execComponents objectAtIndex: 3] isNotEqualTo: @"Contents"]
        || [[execComponents objectAtIndex: 4] isNotEqualTo: @"Resources"]
        ) {
        NSLog(@"Tunnelblick must be in /Applications (bundlePath = %@)", resourcesPath);
        errorExit();
    }
#endif
    
    // Validate our arguments
    if (   (argc < 5)
        || (argc > OPENVPNSTART_MAX_ARGC+1)
        || (   ( strcmp(argv[ARG_LOAD_FLAG], "0") != 0 )
            && ( strcmp(argv[ARG_LOAD_FLAG], "1") != 0 )
            )
        ) {
        NSLog(@"Tunnelblick atsystemstart: Argument #%d must be 0 or 1 and there must be between 5 to %d (inclusive) arguments altogether. argc = %d; argv[%d] = '%s'", ARG_LOAD_FLAG, OPENVPNSTART_MAX_ARGC+1, argc, ARG_LOAD_FLAG, argv[ARG_LOAD_FLAG]);
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
    
    NSString * daemonLabel = [NSString stringWithFormat: @"net.tunnelblick.tunnelblick.startup.%@", sanitizedDaemonName];
    
    NSString * plistPath = [NSString stringWithFormat: @"/Library/LaunchDaemons/%@.plist", daemonLabel];
    
    if (  strcmp(argv[ARG_LOAD_FLAG], "0") == 0  ) {
        setNoStart(plistPath);
    } else {
        setStart(plistPath, daemonDescription, daemonLabel, argc, argv);
    }
    
    deleteFlagFile(AUTHORIZED_RUNNING_PATH);
    deleteFlagFile(AUTHORIZED_ERROR_PATH);

    [pool drain];
    exit(EXIT_SUCCESS);
}

void appendLog(NSString * msg)
{
    NSLog(@"%@", msg);
}

void setNoStart(NSString * plistPath)
{
    NSFileManager * fm = [NSFileManager defaultManager];
    if (  [fm fileExistsAtPath: plistPath]  ) {
        if ( ! [fm tbRemoveFileAtPath: plistPath handler: nil]  ) {
            NSLog(@"Tunnelblick atsystemstart: Unable to delete existing plist file %@", plistPath);
        }
    } else {
        NSLog(@"Tunnelblick atsystemstart: Does not exist, so cannot delete %@", plistPath);
        errorExit();
    }
}

void setStart(NSString * plistPath, NSString * daemonDescription, NSString * daemonLabel, int argc, char* argv[])
{
    // Note: When creating the .plist, we don't use the "Program" key, because we want the first argument to be the path to the program,
    // so openvpnstart can know where it is, so it can find other Tunnelblick compenents.
    
    NSString * openvpnstartPath = [[NSBundle mainBundle] pathForResource: @"openvpnstart" ofType: nil];
    
    NSMutableArray * arguments = [NSMutableArray arrayWithObject: openvpnstartPath];
    unsigned i;
    for (i=2; i< (unsigned) argc; i++) {
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
    
    NSFileManager * fm = [NSFileManager defaultManager];
    if (  [fm fileExistsAtPath: plistPath]  ) {
        if (  [fm tbPathContentOfSymbolicLinkAtPath: plistPath] != nil  ) {
            NSLog(@"Tunnelblick atsystemstart: Symbolic link not allowed at %@", plistPath);
            errorExit();
        }
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
        cfgLocCode = cvt_atou(argv[ARG_CFG_LOC], @"cfgLocCode");
    }
    
    if (  cfgLocCode == CFG_LOC_DEPLOY  ) {
        cfgPath = [gDeployPath stringByAppendingPathComponent: cfgFile];
        if (  ! [[NSFileManager defaultManager] fileExistsAtPath: cfgPath]  ) {
            NSLog(@"Tunnelblick atsystemstart: Configuration does not exist: %@",cfgPath);
            errorExit();
        }
    } else if (cfgLocCode == CFG_LOC_SHARED  ) {
        cfgPath = [L_AS_T_SHARED stringByAppendingPathComponent: cfgFile];
    } else {
        NSLog(@"Tunnelblick atsystemstart: Invalid cfgLocCode = %d", cfgLocCode);
        errorExit();
    }
    
    NSString * workingDirectory = [cfgPath stringByAppendingPathComponent: @"Contents/Resources"];
    return workingDirectory;
}

void deleteFlagFile(NSString * path) {
    
	const char * fsrPath = [path fileSystemRepresentation];
    struct stat sb;
	if (  0 == stat(fsrPath, &sb)  ) {
        if (  (sb.st_mode & S_IFMT) == S_IFREG  ) {
            if (  0 != unlink(fsrPath)  ) {
                appendLog([NSString stringWithFormat: @"Unable to delete %@", path]);
            }
        } else {
            appendLog([NSString stringWithFormat: @"%@ is not a regular file; st_mode = 0%lo", path, (unsigned long) sb.st_mode]);
        }
    } else {
        appendLog([NSString stringWithFormat: @"stat of %@ failed\nError was '%s'", path, strerror(errno)]);
    }
}

void errorExit() {
    
    deleteFlagFile(AUTHORIZED_RUNNING_PATH);
    
    [pool drain];
    exit(EXIT_FAILURE);
}


