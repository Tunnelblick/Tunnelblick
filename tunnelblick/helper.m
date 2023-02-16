/*
 * Copyright 2005, 2006, 2007, 2008, 2009 Angelo Laub
 * Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021. All rights reserved.
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

#import "helper.h"

#import <mach/mach_time.h>
#import <pthread.h>
#import <Security/Security.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <unistd.h>

#import "defines.h"
#import "sharedRoutines.h"

#import "AlertWindowController.h"
#import "AuthAgent.h"
#import "KeyChain.h"
#import "MenuController.h"
#import "NSApplication+LoginItem.h"
#import "NSDate+TB.h"
#import "NSFileManager+TB.h"
#import "MenuController.h"
#import "TBUserDefaults.h"
#import "UIHelper.h"

// PRIVATE FUNCTIONS:
void           localizableStrings       (void);
BOOL           copyOrMoveCredentials    (NSString * fromDisplayName,
                                         NSString * toDisplayName,
                                         BOOL       moveNotCopy);
NSString     * TBShowWindowCacheKeyConverter(NSString * key, NSString * msg);

// The following external, global variables are used by functions in this file and must be declared and set elsewhere before the
// functions in this file are called:
extern NSMutableArray * gConfigDirs;
extern NSString       * gDeployPath;
extern NSFileManager  * gFileMgr;
extern NSThread       * gMainThread;
extern MenuController * gMC;
extern NSString       * gPrivatePath;
extern BOOL             gShuttingDownTunnelblick;
extern TBUserDefaults * gTbDefaults;

void appendLog(NSString * msg)
{
	NSLog(@"%@", msg);
}

NSString * tracesFolderPath(void) {

	NSString * path = [[[[NSHomeDirectory()
						  stringByAppendingPathComponent: @"Library"]
						 stringByAppendingPathComponent: @"Application Support"]
						stringByAppendingPathComponent: @"Tunnelblick"]
					   stringByAppendingPathComponent: @"TracesLogs"];
	return path;
}

NSString * tracesFilename(NSString * dateTime) {

	NSString * name = [[dateTime substringWithRange: NSMakeRange(0, LENGTH_OF_YYYY_MM_DD)]
					   stringByAppendingPathExtension: @"log"];
	return name;
}

static pthread_mutex_t traceFileMutex = PTHREAD_MUTEX_INITIALIZER;

BOOL lockUsingMutex(pthread_mutex_t * mutex, NSString * mutexName) {

	int status = pthread_mutex_lock(mutex);
	if (  status != 0  ) {
		NSLog(@"pthread_mutex_lock(&%@) failed; status = %ld, errno = %ld", mutexName, (long) status, (long) errno);
		return NO;
	}

	return YES;
}

BOOL unlockUsingMutex(pthread_mutex_t * mutex, NSString * mutexName) {

	int status = pthread_mutex_unlock(mutex);
	if (  status != 0  ) {
		NSLog(@"pthread_mutex_unlock(&%@) failed; status = %ld, errno = %ld", mutexName, (long) status, (long) errno);
		return NO;
	}

	return YES;
}

void pruneTracesFolder() {

	// Does not use gFileMgr, so this can be called before gFileMgr is set up

	NSDate * oneDayAgo = [[NSDate date] dateByAddingTimeInterval: -SECONDS_PER_DAY];
	NSString * earliestAllowedFilenamePrefix = [[oneDayAgo tunnelblickUserLogRepresentationWithoutMicroseconds] substringWithRange: NSMakeRange(0, LENGTH_OF_YYYY_MM_DD)];

	NSString * folderPath = tracesFolderPath();
	NSArray * filenames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: folderPath error: nil];
	NSEnumerator * e = [filenames objectEnumerator];
	NSString * filename;
	while (  filename = [e nextObject]  ) {
		if (  [[filename pathExtension] isEqualToString: @"log"]  ) {
			if (  [[filename lastPathComponent] compare: earliestAllowedFilenamePrefix] == NSOrderedAscending  ) {
				NSString * path = [folderPath stringByAppendingPathComponent: filename];
				if (  [[NSFileManager defaultManager] tbRemoveFileAtPath: path handler: nil]  ) {
					NSLog(@"Removed %@", path);
				}
			}
		}
	}
}

NSString * dumpTraces(void) {

	// Does not use gFileMgr, so this can be called before gFileMgr is set up

	NSMutableString * result = [NSMutableString stringWithCapacity: 100000];

	NSArray * filenames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: tracesFolderPath() error: nil];

	NSArray * sortedFilenames = [filenames sortedArrayUsingComparator:
								 ^NSComparisonResult(NSString * string1, NSString * string2) { return [string1 compare: string2]; }];

	NSEnumerator * e = [sortedFilenames objectEnumerator];
	NSString * filename;
	while (  filename = [e nextObject]  ) {
		NSString * path = [tracesFolderPath() stringByAppendingPathComponent: filename];
		if (  [[path pathExtension] isEqualToString: @"log"]  ) {
			NSData * data = [[NSFileManager defaultManager] contentsAtPath: path];
			// Ignore any error getting the file contents: the file could have been pruned since we created "filenames"
			if (  data  ) {
				NSString * contents = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
				if (  ! contents  ) {
					contents = [NSString stringWithFormat: @"Unable to parse as UTF8: %@\n", path];
				}
				[result appendString: contents];
			}
		}
	}

	return result;
}

void append_tb_trace_routine (const char * source_path, int line_number, NSString * format, ...) {

	// Thread-safe append to the current day's traces log file
	//
	// SHOULD CALLED BY USING THE TBTrace() MACRO, NOT DIRECTLY
	//
	// Does not use gFileMgr, so this can be called before gFileMgr is set up

	// Construct message from format string and arguments
	NSString * dateTime = [[NSDate date] tunnelblickUserLogRepresentation];
	NSString * sourceFileName = [[[[NSString alloc] initWithBytes: source_path
														   length: strlen(source_path)
														 encoding: NSUTF8StringEncoding]
								  autorelease]
								 lastPathComponent];
	va_list arg_list;
	va_start(arg_list, format);
	NSString * message = [[[NSString alloc] initWithFormat: format arguments: arg_list] autorelease];
	va_end(arg_list);
	NSString * fullMessage = [NSString stringWithFormat: @"%@: %@:%u\t%@\n", dateTime, sourceFileName, line_number, message];

	static FILE * trace_file = NULL;
	static NSString * lastTracesFilename = nil;

	if (  ! lockUsingMutex(&traceFileMutex, @"traceFileMutex")  ) {
		return;
	}

	NSString * newTracesFilename = tracesFilename(dateTime);

	if (  ! [lastTracesFilename isEqualToString: newTracesFilename]  ) {
		// It's a new day; close the old day's traces file if necessary
		if (  trace_file != NULL  ) {
			fclose(trace_file);
			trace_file = NULL;
		}

		// Indicate we are using the new day's trace file
		[newTracesFilename retain];
		[lastTracesFilename release];
		lastTracesFilename = newTracesFilename;
	}

	if (  trace_file == NULL  ) {
		// Create folder for traces files if necessary
		NSString * folderPath = tracesFolderPath();
		if (  ! [[NSFileManager defaultManager] fileExistsAtPath: folderPath]  ) {
			if ( ! [[NSFileManager defaultManager] tbCreateDirectoryAtPath: folderPath withIntermediateDirectories: YES attributes: nil]  ) {
				unlockUsingMutex(&traceFileMutex, @"traceFileMutex");
				return;
			}
		}

		const char * path = [[folderPath stringByAppendingPathComponent: lastTracesFilename] UTF8String];

		trace_file = fopen(path, "a");
		if (  trace_file == NULL  ) {
			NSLog(@"appendNote: Unable to open %s", path);
			unlockUsingMutex(&traceFileMutex, @"traceFileMutex");
			return;
		}
	}

	const char * full_message_c = [fullMessage UTF8String];
	size_t full_message_c_len = strlen(full_message_c);
	size_t result = fwrite(full_message_c, 1, full_message_c_len, trace_file);
	if (  result != full_message_c_len) {
		NSLog(@"Wrote only %lu of %lu bytes to %@", result, full_message_c_len, tracesFilename(dateTime));
	}

	if (  fflush(trace_file) != ERR_SUCCESS  ) {
		NSLog(@"fflush() of %@ failed; errno = %d (%s)", tracesFilename(dateTime), errno, strerror(errno));
	}

	unlockUsingMutex(&traceFileMutex, @"traceFileMutex");
}

// The following base64 routines were inspired by an answer by denis2342 to the thread at https://stackoverflow.com/questions/11386876/how-to-encode-and-decode-files-as-base64-in-cocoa-objective-c

static NSData * base64helper(NSData * input, SecTransformRef transform) {
	
	NSData * output = nil;
	
	if (  input  ) {
		if (  transform  ) {
			if (  SecTransformSetAttribute(transform, kSecTransformInputAttributeName, input, NULL)  ) {
				output = [(NSData *)SecTransformExecute(transform, NULL) autorelease];
				if (  ! output  ) {
					appendLog(@"base64helper: SecTransformExecute() returned NULL");
				}
			} else {
				appendLog(@"base64helper: SecTransformSetAttribute() returned FALSE");
			}
		} else {
			appendLog(@"base64helper: transform is nil");
		}
	} else {
		appendLog(@"base64helper: input is nil");
	}
	
	return output;
}

NSString * base64Encode(NSData * input) {
	
	// Returns an empty string on error after logging the reason for the error.
	
	NSString * output = @"";
	
	if (  input  ) {
		SecTransformRef transform = SecEncodeTransformCreate(kSecBase64Encoding, NULL);
		if (  transform != NULL  ) {
			NSData * data = base64helper(input, transform);
			CFRelease(transform);
			if (  data  ) {
				output = [[[NSString alloc] initWithData: data encoding: NSASCIIStringEncoding] autorelease];
			} else {
				appendLog(@"base64Encode: base64helper() returned nil");
			}
		} else {
			appendLog(@"base64Decode: SecEncodeTransformCreate() returned NULL");
		}
	} else {
		appendLog(@"base64Decode: input is nil");
	}
	
	return output;
}

NSData * base64Decode(NSString * input) {
	
	// Returns nil on error after logging the reason for the error.
	
	NSData * output = nil;
	
	if (  input  ) {
		NSData * data = [input dataUsingEncoding: NSASCIIStringEncoding];
		if (  data  ) {
			SecTransformRef transform = SecDecodeTransformCreate(kSecBase64Encoding, NULL);
			if (  transform != NULL  ) {
				output = base64helper(data, transform);
				CFRelease(transform);
			} else {
				appendLog(@"base64Decode: SecEncodeTransformCreate() returned NULL");
			}
		} else {
			appendLog(@"base64Decode: [input dataUsingEncoding: NSASCIIStringEncoding] returned nil");
		}
	} else {
		appendLog(@"base64Decode: input is nil");
	}
	
	return output;
}

uint64_t nowAbsoluteNanoseconds(void)
{
    // The next three lines were adapted from http://shiftedbits.org/2008/10/01/mach_absolute_time-on-the-iphone/
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    uint64_t nowNs = (unsigned long long)mach_absolute_time() * (unsigned long long)info.numer / (unsigned long long)info.denom;
    return nowNs;
}

BOOL runningATunnelblickBeta(void) {

    NSString * version = [[gMC tunnelblickInfoDictionary] objectForKey: @"CFBundleShortVersionString"];
    return [version containsString: @"beta"];
}

BOOL runningWithSIPDisabled(void) {

    if (  ! [gFileMgr fileExistsAtPath: TOOL_PATH_FOR_CSRUTIL]  ) {
        NSLog(@"Assuming SIP is disabled (i.e., is not in effect) because '%@' does not exist", TOOL_PATH_FOR_CSRUTIL);
        return YES;
    }

    NSString * stdOutString = nil;
    NSString * stdErrString = nil;
    OSStatus status = runTool(TOOL_PATH_FOR_CSRUTIL, @[@"status"], &stdOutString, &stdErrString);
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"Error status %d from '%@ status'; assuming SIP is enabled. stdout = '%@'; stderr = '%@'",
              status, TOOL_PATH_FOR_ID, stdOutString, stdErrString);
        return NO;
    }

    BOOL result = FALSE;
    BOOL disabled = [stdOutString containsString: @"System Integrity Protection status: disabled"];
    BOOL enabled  = [stdOutString containsString: @"System Integrity Protection status: enabled"];
    if (   disabled
        && ( ! enabled)  ) {
        result = TRUE;
    } else if (   enabled
               && ( ! disabled) ) {
        result = FALSE;
    } else {
        NSLog(@"Cannot determine SIP status; assuming SIP is enabled. stdout from '%@ status' = '%@'", TOOL_PATH_FOR_CSRUTIL, stdOutString);
        result = FALSE;
    }

    return result;
}

BOOL runningOnMacosBeta(void) {

    NSString * stdOutString = nil;
    NSString * stdErrString = nil;
    OSStatus status = runTool(TOOL_PATH_FOR_SW_VERS, @[@"-buildVersion"], &stdOutString, &stdErrString);
    if (   (status == EXIT_SUCCESS)
        && ([stdOutString length] > 0)  ) {
        NSString * lastCharacter = [stdOutString substringWithRange: NSMakeRange([stdOutString length] - 1, 1)];
        BOOL isLetter = [@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" containsString: lastCharacter];
        return isLetter;
    }

    NSLog(@"Error status %d from 'sw_vers -buildVersion'; stdout = '%@'; stderr = '%@'", status, stdOutString, stdErrString);
    return NO;
}

BOOL runningOnNewerThan(unsigned majorVersion, unsigned minorVersion)
{
    unsigned major, minor, bugFix;
    OSStatus status = getSystemVersion(&major, &minor, &bugFix);
    if (  status != 0) {
        NSLog(@"getSystemVersion() failed");
        [gMC terminateBecause: terminatingBecauseOfError];
        return FALSE;
    }
    
    return (   (major > majorVersion)
			|| (   (major == majorVersion)
				&& (minor >  minorVersion)
				)
			);
}


BOOL runningOnElCapitanOrNewer(void)
{
    return runningOnNewerThan(10, 10);
}

BOOL runningOnSierraOrNewer(void)
{
    return runningOnNewerThan(10, 11);
}

BOOL runningOnHighSierraOrNewer(void)
{
	return runningOnNewerThan(10, 12);
}

BOOL runningOnMojaveOrNewer(void)
{
	return runningOnNewerThan(10, 13);
}

BOOL runningOnCatalinaOrNewer(void)
{
	return runningOnNewerThan(10, 14);
}

BOOL runningOnBigSurOrNewer(void)
{
    return runningOnNewerThan(10, 15); // Handles 11.0, too
}

BOOL runningOnMontereyOrNewer(void) {

    return runningOnNewerThan(11, 99999);
}

BOOL runningOn__Monterey__Successor__OrNewer(void) {
    
    return runningOnNewerThan(12, 99999);
}

BOOL runningOnNewerThanWithBugFix(unsigned majorVersion, unsigned minorVersion, unsigned bugfixVersion)
{
	unsigned major, minor, bugFix;
	OSStatus status = getSystemVersion(&major, &minor, &bugFix);
	if (  status != 0) {
		NSLog(@"getSystemVersion() failed");
		[gMC terminateBecause: terminatingBecauseOfError];
		return FALSE;
	}
	
	return (   (major >  majorVersion)
			|| (   (major == majorVersion)
				&& (   (minor >  minorVersion)
					|| (   (minor == minorVersion
							&& (bugFix > bugfixVersion)
							)
						)
					)
				)
			);
}

BOOL runningOnTen_Fourteen_FiveOrNewer(void)
{
	BOOL result = runningOnNewerThanWithBugFix(10, 14, 4);
	return result;
}

BOOL bothKextsAreInstalled(void) {
    
    BOOL result = (   [gFileMgr fileExistsAtPath: @"/Library/Extensions/tunnelblick-tun.kext"]
                   && [gFileMgr fileExistsAtPath: @"/Library/Extensions/tunnelblick-tap.kext"]  );
    return result;
}

BOOL anyKextsAreLoaded(void) {
    
    NSString * stdoutString = nil;
    NSString * stderrString = nil;
    OSStatus status = runTool(TOOL_PATH_FOR_KEXTSTAT, @[], &stdoutString, &stderrString);
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"Error returned by kextstat = %d; stdout =\n%@\nstderr=\%@", status, stdoutString, stderrString);
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          NSLocalizedString( @"An error occurred getting the list of loaded system extensions.", @"Window text"));
        return NO;
    }
    
    BOOL result = [stdoutString containsString: @"net.tunnelblick."];
    return result;
}

BOOL okToUpdateConfigurationsWithoutAdminApproval(void) {
    BOOL answer = (   [gTbDefaults boolForKey: @"allowNonAdminSafeConfigurationReplacement"]
				   && ( ! [gTbDefaults canChangeValueForKey: @"allowNonAdminSafeConfigurationReplacement"] )
				   );
	return answer;
}

BOOL displaysHaveDifferentSpaces(void) {
    
    NSString * spacesPrefsPath = [NSHomeDirectory() stringByAppendingPathComponent: @"/Library/Preferences/com.apple.spaces.plist"];
    NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: spacesPrefsPath];
    if (  dict  ) {
        id obj = [dict objectForKey: @"spans-displays"];
        if (  obj  ) {
            if (  [obj respondsToSelector: @selector(boolValue)]  ) {
                return ! [obj boolValue];
            } else {
                NSLog(@"The 'spans-displays' preference from %@ does not respond to boolValue", spacesPrefsPath);
            }
        }
    } else {
        NSLog(@"Unable to load dictionary from %@", spacesPrefsPath);
    }
    
    return YES; // Error, so assume displays do have different spaces
}

BOOL mustPlaceIconInStandardPositionInStatusBar(void) {
    
    if (  runningOnSierraOrNewer()  ) {
        return YES;
    }
    
    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    if (  ! [bar respondsToSelector: @selector(_statusItemWithLength:withPriority:)]  ) {
        return YES;
    }
    if (  ! [bar respondsToSelector: @selector(_insertStatusItem:withPriority:)]  ) {
        return YES;
    }
    
    if (   ([[NSScreen screens] count] != 1)
        && displaysHaveDifferentSpaces()  ) {
        return YES;
    }
    
    return NO;
}

BOOL shouldPlaceIconInStandardPositionInStatusBar(void) {
    
    if (  mustPlaceIconInStandardPositionInStatusBar()  ) {
        return YES;
    }
    
    return displaysHaveDifferentSpaces();
}

BOOL localAuthenticationIsAvailable(void) {
    return runningOnSierraOrNewer();
}

NSString * rgbValues(BOOL foreground) {
	
	NSString *osxMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"];
	BOOL darkMode = (   [osxMode isEqualToString: @"dark"]
					 || [osxMode isEqualToString: @"Dark"]  );
	NSString * result = (  foreground
						 ? (  darkMode
							? @"rgb(224,224,224)"
							: @"rgb(36,36,36)")
						 : (  darkMode
							? @"rgb(48,50,52)"
							: @"rgb(236,236,236)"
							)
						 );
	
	return result;
}

NSString * architectureBeingUsed(void) {
    
    char return_string[1000];
    size_t size = 1000;
    if (  sysctlbyname("machdep.cpu.brand_string", &return_string, &size, NULL, 0) == -1  ) {
        NSLog(@"architectureBeingUsed(): Error from sysctlbyname(\"machdep.cpu.brand_string\"): %d (%s), assuming '%@'",
              errno, strerror(errno), ARCH_X86);
        return ARCH_X86;
    }

    BOOL isIntel = (  strstr(return_string, "Intel") != 0  );
    return (  isIntel
            ? ARCH_X86
            : ARCH_ARM);
    
/* Using the sysctl command
    NSString * stdOutString = nil;
    NSString * stdErrString = nil;
    OSStatus status = runTool(TOOL_PATH_FOR_SYSCTL, @[@"-n", @"machdep.cpu.brand_string"], &stdOutString, &stdErrString);
    if (   (status == EXIT_SUCCESS)
        && ([stdOutString length] > 0)  ) {
        return [stdOutString containsString: @"Intel"];
    }

    NSLog(@"Error status %d from 'sysctl -a'; stdout = '%@'; stderr = '%@'", status, stdOutString, stdErrString);
    return NO;
*/

}

NSString * architecturesForExecutable(NSString * path) {
    
    // Run "file <path>" to get a list of architectures that can run the executable at <path>
    NSString * stdoutString = nil;
    OSStatus status = runTool(TOOL_PATH_FOR_FILE, @[path], &stdoutString, nil);
    if (  status != 0  ) {
        NSLog(@"Assuming '%@' can run on '%@' because 'file' returned error status %ld", path, ARCH_ALL, (long)status);
        return ARCH_ALL ;
    }
    
    NSString * archs = @"";
    
    BOOL haveX86 = [stdoutString containsString: @"Mach-O 64-bit executable x86_64"];
    BOOL haveArm = [stdoutString containsString: @"Mach-O 64-bit executable arm64"];
    if (  haveX86  ) {
        if (  haveArm  ) {
            archs = ARCH_ALL;
        } else {
            archs = ARCH_X86;
        }
    } else if (  haveArm  ) {
        archs = ARCH_ARM;
    }
    
    return archs;
}

BOOL thisArchitectureSupportsBinaryAtPath(NSString * path) {

    // We don't support running Arm binaries under Rosetta (even if macOS does)
    // because (A) running Tunnelblick under Rosetta is unnecessary and (B) we warn
    // about it.

    NSString * archs = architecturesForExecutable(path);
    NSString * currentArch = architectureBeingUsed();

    if (  [currentArch isEqualToString: ARCH_ARM]) {
        return [archs containsString: ARCH_ARM];
    } else if (  [currentArch isEqualToString: ARCH_X86]) {
        return [archs containsString: ARCH_X86];
    }

    NSLog(@"Tunnelblick does not recognize the current architecture '%@'."
          @" Assuming cannot run binary (which supports only '%@') at %@\n"
          @"Using Rosetta = %s; Tunnelblick supports = %@ and %@",
          currentArch, archs, path,
          CSTRING_FROM_BOOL(processIsTranslated()), ARCH_X86, ARCH_ARM);
    return NO;
}

NSAttributedString * attributedStringFromHTML(NSString * html) {
    
    NSData * htmlData = [html dataUsingEncoding: NSUTF8StringEncoding];
	if ( htmlData == nil  ) {
		NSLog(@"attributedStringFromHTML: cannot get dataUsingEncoding: NSUTF8StringEncoding; stack trace = %@", callStack());
		return nil;
	}
	
	NSAttributedString * as = [[[NSAttributedString alloc]
								initWithHTML: htmlData options: @{NSTextEncodingNameDocumentOption: @"UTF-8"} documentAttributes: nil]
							   autorelease];
    return as;
}

NSAttributedString * attributedLightDarkStringFromHTML(NSString * html) {
	
	NSString * withSpan = [NSString stringWithFormat: @"<span style=\"color:%@;background-color:%@\">%@</span>",
							rgbValues(YES), rgbValues(NO), html];
	
	NSAttributedString * result = attributedStringFromHTML(withSpan);
	return result;
}

// Returns an escaped version of a string so it can be sent over the management interface
NSString * escaped(NSString *string)
{
	NSMutableString * stringOut = [[string mutableCopy] autorelease];
	[stringOut replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:NSLiteralSearch range:NSMakeRange(0, [stringOut length])];
	[stringOut replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:NSLiteralSearch range:NSMakeRange(0, [stringOut length])];
	return stringOut;
}

// Returns the path of the configuration folder in which a specified configuration file is contained
// Returns nil if it is not in any configuration folder
NSString * firstPartOfPath(NSString * thePath)
{
    unsigned i;
    for (i=0; i < [gConfigDirs count]; i++) {
        if (  [thePath hasPrefix: [[gConfigDirs objectAtIndex: i] stringByAppendingString: @"/"]]  ) {
            return [[[gConfigDirs objectAtIndex: i] copy] autorelease];
        }
    }
    
    NSString *altPath = [L_AS_T_USERS stringByAppendingPathComponent: NSUserName()];
    if (  [thePath hasPrefix: [altPath stringByAppendingString:@ "/"]]  ) {
        return altPath;
    }
    
    return nil;
}

// The name of the configuration file, but prefixed by any folders it is contained in after /Deploy or /Configurations
//      = configPath less the Deploy or Configurations folder prefix (but including the extension)
// Used for constructing path to shadow copy of the configuration and as an argument to openvpnstart
NSString * lastPartOfPath(NSString * thePath)
{
    return [thePath substringFromIndex: [firstPartOfPath(thePath) length]+1];
}

// Returns the first component of a path
NSString * firstPathComponent(NSString * path)
{
    NSRange slash = [path rangeOfString: @"/"];
    if ( slash.location == 0 ) {
        slash = [[path substringFromIndex: 1] rangeOfString: @"/"];
    }
    if ( slash.location == NSNotFound) {
        slash.location = [path length];
    }
    return [path substringToIndex: slash.location];
}

NSString * pathWithNumberSuffixIfItemExistsAtPath(NSString * path, BOOL includeCopyInNewName) {

    // Returns the path if it does not exist.
    // Otherwise, returns a path that does not exist: "path 2", "path 3", etc.
    //
    // If includeCopyInNewName is TRUE, return "path copy", "path copy 2", "path copy 3", etc.
    //
    // Returns nil if path is not an absolute path, or too many copies already exist

    if (  ! [path hasPrefix: @"/"]  ) {
        NSLog(@"pathWithNumberSuffixIfItemExistsAtPath: path is not absolute: %@", path);
        return nil;
    }

    BOOL pathWasTblk = [path hasSuffix: @".tblk"];

    NSString * pathWithoutExtension = (  pathWasTblk
                                       ? [path stringByDeletingPathExtension]
                                       : path);

    NSString * dotExtension = (  pathWasTblk
                               ? @".tblk"
                               : @"");

    int count = 0;
    NSString * newPath = [[path retain] autorelease];

    while (  [gFileMgr fileExistsAtPath: newPath]  ) {
        if (  count++ > 99  ) {
            TBShowAlertWindow(NSLocalizedString(@"Warning", @"Window title"),
                              NSLocalizedString(@"Too many copies already exist.", @"Window text. 'Copies' refers to copies of a configuration or a folder of configurations."));
            return nil;
        }

        NSString * copySuffix = (  includeCopyInNewName
                                 ? (  (count == 1)
                                    ? NSLocalizedString(@" copy", @"Suffix for the first copy of a file as is made by Finder's Command-click 'duplicate' command.")
                                    : [NSString stringWithFormat: NSLocalizedString(@" copy %d", @"Suffix for an additional copy of a file as is made by Finder's Command-click 'duplicate' command."), count])
                                 : [NSString stringWithFormat: @" %d", (count + 1)]);

        newPath = [[pathWithoutExtension stringByAppendingString: copySuffix] stringByAppendingString: dotExtension];
    }

    return newPath;
}

NSString * secureTblkPathForTblkPath(NSString * path) {

    if (  [path hasSuffix: @".tblk"]  ) {
        if (   [path hasPrefix: L_AS_T_SHARED]
            || [path hasPrefix: L_AS_T_USERS]
            || [path hasPrefix: gDeployPath]  ) {
            return path;
        }

        if (  [path hasPrefix: gPrivatePath]  ) {
            NSString * suffix = lastPartOfPath(path);
            return [[L_AS_T_USERS
                     stringByAppendingPathComponent: NSUserName()]
                    stringByAppendingPathComponent: suffix];
        }
    }

    NSLog(@"secureTblkPathForTblkPath(): bad input path '%@'", path);
    [gMC terminateBecause: terminatingBecauseOfError];
    return nil;
}

NSString * displayNameFromPath (NSString * thePath) {
	
	// Returns the display name for a configuration, given a configuration file's path (either a .tblk or a .ovpn)
	
	NSString * last = lastPartOfPath(thePath);
	
	if (  [last hasSuffix: @".tblk"]  ) {							// IS a .tblk
		return [last substringToIndex: [last length] - 5];
	}
	
	if (  [last hasSuffix: @"/Contents/Resources/config.ovpn"]  ) {	// Is IN a .tblk
		return [[[[last stringByDeletingLastPathComponent]	// Remove config.ovpn
				  stringByDeletingLastPathComponent]		// Remove Resources
				 stringByDeletingLastPathComponent]			// Remove Contents
				stringByDeletingPathExtension];				// Remove .tblk
	}
	
	if (   [last hasSuffix: @".ovpn"]								// Is a non-tblk configuration file
		|| [last hasSuffix: @".conf"]  ) {
		return [last substringToIndex: [last length] - 5];
	}
	
	NSLog(@"displayNameFromPath: invalid path '%@'", thePath);
	return nil;
}

// Returns the path of the configuration file within a .tblk, or nil if there is no such configuration file
NSString * configPathFromTblkPath(NSString * path)
{
    NSString * cfgPath = [path stringByAppendingPathComponent:@"Contents/Resources/config.ovpn"];
    BOOL isDir;
    
    if (   [gFileMgr fileExistsAtPath: cfgPath isDirectory: &isDir]
        && (! isDir)  ) {
        return cfgPath;
    }
    
    return nil;
}

// Returns the path of the .tblk that a configuration file is enclosed within, or nil if the configuration file is not enclosed in a .tblk
NSString * tblkPathFromConfigPath(NSString * path)
{
    NSString * answer = path;
    while (   ! [[answer pathExtension] isEqualToString: @"tblk"]
           && [answer length] != 0
           && ! [answer isEqualToString: @"/"]  ) {
        answer = [answer stringByDeletingLastPathComponent];
    }
    
    if (  [[answer pathExtension] isEqualToString: @"tblk"]  ) {
        return answer;
    }
    
    return nil;
}

NSString * configPathFromDisplayName(NSString * name) {

    // If the displayName is for a configuration that appears in the left navigation, returns the path to the .tblk.
    // If the path is for a folder that exists in Shared, private, or secured, returns an empty string.
    // Otherwise returns nil.

    // Return the path if it is a .tblk that appears in the left navigation
    NSString * path = [[gMC myConfigDictionary] objectForKey: name];
    if (  path  ) {
        return path;
    }

    // If it's a shared folder, private folder, or secured folder, return @"", else return nil
    BOOL isDir;
    NSString * testPath = [gPrivatePath stringByAppendingPathComponent: name];
    if (   [gFileMgr fileExistsAtPath: testPath isDirectory: &isDir]
        && isDir  ) {
        return @"";
    }

    testPath = [L_AS_T_SHARED stringByAppendingPathComponent: name];
    if (   [gFileMgr fileExistsAtPath: testPath isDirectory: &isDir]
        && isDir  ) {
        return @"";
    }

    testPath = [[L_AS_T_USERS stringByAppendingPathComponent: NSUserName()]
                stringByAppendingPathComponent: name];
    if (   [gFileMgr fileExistsAtPath: testPath isDirectory: &isDir]
        && isDir  ) {
        return @"";
    }

    return nil;
}

BOOL displayNameIsValid(NSString * newName, BOOL doBeepOnError) {

    // Make sure there are no prohibited characters in the name
    if (  invalidConfigurationName(newName, PROHIBITED_DISPLAY_NAME_CHARACTERS_INCLUDING_SLASH_CSTRING)  ) {
        TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
                          [NSString stringWithFormat:
                           NSLocalizedString(@"Names may not include any of the following characters: %s\n\n%@", @"Window text"),
                           PROHIBITED_DISPLAY_NAME_CHARACTERS_INCLUDING_SLASH_WITH_SPACES_CSTRING, @""]);
        if (  doBeepOnError  ) {
            NSBeep();
        }
        return NO;
    }

    return YES;
}

// Returns a string with the version # for Tunnelblick, e.g., "Tunnelbick 3.0b12 (build 157)"
NSString * tunnelblickVersion(NSBundle * bundle)
{
    NSString * infoVersion = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    NSString * infoShort   = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString * infoBuild   = [bundle objectForInfoDictionaryKey:@"Build"];
    
    if (  [[infoVersion class] isSubclassOfClass: [NSString class]] && [infoVersion rangeOfString: @"3.0b"].location == NSNotFound  ) {
        // No "3.0b" in CFBundleVersion, so it is a build number, which means that the CFBundleShortVersionString has what we want
        return [NSString stringWithFormat: @"Tunnelblick %@", infoShort];
    }
    
    // We must construct the string from what we have in infoShort and infoBuild.
    //Strip "Tunnelblick " from the front of the string if it exists (it may not)
    NSString * appVersion = (  [infoShort hasPrefix: @"Tunnelblick "]
                             ? [infoShort substringFromIndex: [@"Tunnelblick " length]]
                             : infoShort);
    
    NSString * appVersionWithoutBuild;
    NSUInteger parenStart;
    if (  ( parenStart = ([appVersion rangeOfString: @" ("].location) ) == NSNotFound  ) {
        // No " (" in version, so it doesn't have a build # in it
        appVersionWithoutBuild   = appVersion;
    } else {
        // Remove the parenthesized build
        appVersionWithoutBuild   = [appVersion substringToIndex: parenStart];
    }
    
    NSMutableString * version = [NSMutableString stringWithCapacity: 30];
    [version appendString: NSLocalizedString(@"Tunnelblick", @"Window title")];
    if (  appVersionWithoutBuild  ) {
        [version appendFormat: @" %@", appVersionWithoutBuild];
    }
    if (  infoBuild  ) {
        [version appendFormat: @" (build %@)", infoBuild];
    }
    if (  ( ! appVersionWithoutBuild ) &&  ( ! infoBuild) ) {
        [version appendFormat: @" (no version information available)"];
    }
    return (version);
}

NSString * defaultOpenVpnFolderName (void) {
	
	// Returns the name of the folder in Resources/openvpn that contains the version of OpenVPN to use as a default.
	// The name will be of the form openvpn-A.B.C-openssl-D.E.F
	//
	// Use the default version of OpenVPN, from the "default" link
	NSString * defaultLinkPath = [[[NSBundle mainBundle] bundlePath]
								  stringByAppendingPathComponent: @"/Contents/Resources/openvpn/default"];
	NSString * defaultLinkTarget = [[gFileMgr tbPathContentOfSymbolicLinkAtPath: defaultLinkPath]
									stringByDeletingLastPathComponent];
	return defaultLinkTarget;
}

// List of preferencesToSetTrue for all windows we have shown since launch.
// Used to only show each window once.
static NSMutableArray * showAlertWindowAlreadyShownWindowPreferencesCache = nil;

AlertWindowController * TBShowAlertWindowExtended(NSString * title,
												  id				   msg, // NSString or NSAttributedString only
												  NSString			 * preferenceToSetTrue,
												  NSString			 * preferenceName,
												  id				   preferenceValue,
												  NSString			 * checkboxTitle,
												  NSAttributedString * checkboxInfoTitle,
												  BOOL				   checkboxIsOn) {
	
	// Displays an alert window and returns the window controller immediately, so it doesn't block the thread. (Or nil may returned, see below.)
	//
	// The window controller is returned so that it can be closed programmatically if there is a change to the
	// conditions that caused the window to be opened.
	//
	// (Note: the alert window is always displayed on the main thread, regarless of what thread this routine is called on.)
	//
	// The "msg" argument can be an NSString or an NSAttributedString.
    //
	// If "preferenceToSetTrue" is not nil:
	//
	//		If the preferences is true, no alert window will be displayed, and nil will be returned;
	//
	//		Otherwise:
	//
	//			A checkbox will be displayed and the corresponding preference will be set TRUE when the window is closed if the checkbox
	//			had a check in it at the time the window was closed (via the "OK" button, the close button, or the ESC key).
	//
	//			The title of the checkbox will be the string in "checkboxTitle", the infoTitle will be the string in
	//			"checkboxInfoTitle", and the checkbox will be checked if "checkboxIsOn" is true.
	//
	//			If nil, "checkboxTitle" defaults to "Do not warn about this again".
	//			If nil, "checkboxInfoTitle" defaults to
	//				    "When checked, Tunnelblick will not show this warning again. When not checked, Tunnelblick will show this warning again."
	//
	// If "preferenceName" and "preferenceValue" are both not nil:
	//
	//		A checkbox will be displayed and the preference "preferenceName" will be set to the preferenceValue when the window is
	//		closed if the checkbox had a check in it at the time the window was closed (via the "OK" button, the close button, or the ESC key).
	//
	//			The title of the checkbox will be the string in "checkboxTitle", the infoTitle will be the string in
	//			"checkboxInfoTitle", and the checkbox will be checked if "checkboxIsOn" is true.
	//
	//			If nil, "checkboxTitle" defaults to "Do not warn about this again".
	//			If nil, "checkboxInfoTitle" defaults to
	//				    "When checked, Tunnelblick will not show this warning again. When not checked, Tunnelblick will show this warning again."

	// Always show the alert window on the main thread
	if ( ! [NSThread isMainThread]  ) {
		NSDictionary * dict =  [NSDictionary dictionaryWithObjectsAndKeys:
								NSNullIfNil(title),               @"title",
								NSNullIfNil(msg),                 @"msg",
								NSNullIfNil(preferenceToSetTrue), @"preferenceToSetTrue",
								NSNullIfNil(preferenceName),	  @"preferenceName",
								NSNullIfNil(preferenceValue),	  @"preferenceName",
								NSNullIfNil(checkboxTitle),       @"checkboxTitle",
								NSNullIfNil(checkboxInfoTitle),   @"checkboxInfoTitle",
								[NSNumber numberWithBool: checkboxIsOn], @"checkboxIsOn",
								nil];
        [UIHelper performSelectorOnMainThread: @selector(showAlertWindow:) withObject: dict waitUntilDone: NO];
        return nil;
    }

	// If user has previously checked "Do not warn about this again", or if the window for this preference has already been shown,
    // then don't do anything and return nil
	if (  preferenceToSetTrue  ) {
        preferenceToSetTrue = TBShowWindowCacheKeyConverter(preferenceToSetTrue, msg);
        if (  [showAlertWindowAlreadyShownWindowPreferencesCache containsObject: preferenceToSetTrue]  ) {
            return nil;
        }

        if (  [gTbDefaults boolForKey: preferenceToSetTrue]  ) {
            return nil;
        }
        
        if ( ! showAlertWindowAlreadyShownWindowPreferencesCache  ) {
            showAlertWindowAlreadyShownWindowPreferencesCache = [[NSMutableArray alloc] initWithCapacity: 10];
        }

        [showAlertWindowAlreadyShownWindowPreferencesCache addObject: preferenceToSetTrue];
	}

	AlertWindowController * awc = [[[AlertWindowController alloc] init] autorelease];

	[awc setHeadline:			 title];
	[awc setPreferenceToSetTrue: (  [preferenceToSetTrue hasSuffix: @"-NotAnActualPreference"]
                                  ? nil
                                  : preferenceToSetTrue)];
	[awc setPreferenceName:      preferenceName];
	[awc setPreferenceValue:     preferenceValue];
	[awc setCheckboxTitle:       checkboxTitle];
	[awc setCheckboxInfoTitle:   checkboxInfoTitle];
	[awc setCheckboxIsChecked:   checkboxIsOn];
	
	if (  [[msg class] isSubclassOfClass: [NSString class]]  ) {
		if ( runningOnNewerThanWithBugFix(10, 14, 4)  ) {
			// Surround the msg with a span that sets text foreground/background colors for light or dark mode
			NSMutableString * ms = [[[NSMutableString alloc]
									 initWithFormat:
									 @"<span style=\"color:%@;background-color:%@\">%@</span>",
									 rgbValues(YES), rgbValues(NO), msg]
									autorelease];
			// Do simplest possible conversion of text to HTML by replacing newlines with <br>
			//    and multiple spaces with multiple &nbsp;
			[ms replaceOccurrencesOfString: @"\n" withString: @"<br>" options: 0 range: NSMakeRange(0, [ms length])];
			[ms replaceOccurrencesOfString: @"  " withString: @"&nbsp;&nbsp;" options: 0 range: NSMakeRange(0, [ms length])];
			NSAttributedString * result = attributedStringFromHTML(ms);
			[awc setMessageAS: result];
		} else {
			[awc setMessage: msg];
		}
	} else if (  [[msg class] isSubclassOfClass: [NSAttributedString class]]  ) {
		[awc setMessageAS: msg];
	} else {
		NSLog(@"TBShowAlertWindow invoked with invalid message type %@; stack trace: %@", [msg className], callStack());
		[awc setMessageAS: [[[NSAttributedString alloc] initWithString: NSLocalizedString(@"Program error, please see the Console log.", @"Window text")] autorelease]];
	}
	
	NSWindow * win = [awc window];
    [win center];
	[awc showWindow:  nil];
	[win makeKeyAndOrderFront: nil];
    [gMC activateIgnoringOtherApps];
	return awc;
}

void TBShowAlertWindowClearCache(void) {

    [showAlertWindowAlreadyShownWindowPreferencesCache release];
    showAlertWindowAlreadyShownWindowPreferencesCache = nil;
    [gMC recreateMenu];
}

void TBShowAlertWindowRemoveFromCache(NSString * preferenceKey, NSString * msg) {

    preferenceKey = TBShowWindowCacheKeyConverter(preferenceKey, msg);
    [showAlertWindowAlreadyShownWindowPreferencesCache removeObject: preferenceKey];
}

NSString * TBShowWindowCacheKeyConverter(NSString * key, id msg) {

    // msg must be an NSString* or an NSAttributedString*

    if (  [key isEqualToString: @"-NotAnActualPreference"]  ) {
        // Special case: create a fake preference prefixed with a hash of the message. This lets us show each window only once.
        const char * msgC = (  [[msg class] isSubclassOfClass: [NSAttributedString class]]
                             ? [[msg string] UTF8String]
                             : [msg UTF8String]);
        NSData * data = [NSData dataWithBytes: msgC length: strlen(msgC)];
        NSString * hash = sha256HexStringForData(data);
        key = [hash stringByAppendingString: @"-NotAnActualPreference"];
    }

    return key;
}

AlertWindowController * TBShowAlertWindow (NSString * title,
										   id         msg) {
	
	return TBShowAlertWindowExtended(title, msg, nil, nil, nil, nil, nil, NO);

}

AlertWindowController * TBShowAlertWindowOnce (NSString * title,
                                               id         msg) {

    return TBShowAlertWindowExtended(title, msg, @"-NotAnActualPreference", nil, nil, nil, nil, NO);
    
}

// Alow several alert panels to be open at any one time, keeping track of them in AlertRefs.
// TBCloseAllAlertPanels closes all of them when Tunnelblick quits.
// TBRunAlertPanelExtended manages them otherwise.

static NSMutableArray * AlertRefs = nil;

// NSMutableArray is not thread safe, so we use the following lock when accessing it:
static pthread_mutex_t alertRefsMutex = PTHREAD_MUTEX_INITIALIZER;

void LockAlertRefs(void) {
    
    // NOTE: Returns even if an error occurred getting the lock
    
    OSStatus status = pthread_mutex_lock( &alertRefsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_lock( &alertRefsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
    }
}

void UnlockAlertRefs(void) {
    
    // NOTE: Returns even if an error occurred getting the lock
    
   int status = pthread_mutex_unlock( &alertRefsMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"pthread_mutex_unlock( &alertRefsMutex ) failed; status = %ld, errno = %ld", (long) status, (long) errno);
    }
}

void TBCloseAllAlertPanels (void) {
    // Handle the unlikely event that AlertRefs is in the process of being modified.
    // Try to lock them for modification up to four times with 100ms sleeps between tries
    unsigned nTries = 0;
    OSStatus status;
    while (  TRUE  ) {
        status = pthread_mutex_trylock( &alertRefsMutex );
        if (  status == 0  ) {
            break;
        }
        if (   (nTries++ > 2)
            || (status != EBUSY)  ) {
            NSLog(@"pthread_mutex_trylock( &alertRefsMutex ) failed on try #%d; status = %ld", nTries, (long)status);
            return;
        }
        
        usleep(ONE_TENTH_OF_A_SECOND_IN_MICROSECONDS);
        continue;
    }
    
    NSUInteger ix;
    for (  ix=0; ix<[AlertRefs count]; ix++  ) {
        CFUserNotificationRef ref = (CFUserNotificationRef)[AlertRefs objectAtIndex: ix];
        if (  ref  ) {
            SInt32 result = CFUserNotificationCancel(ref);
            TBLog(@"DB-SD", @"TBCloseAllAlertPanels: Cancelled alert panel %@ with result %ld", (ref ? @"non-0" : @"0"), (unsigned long) result);
        }
    }
    
    UnlockAlertRefs();
}

void IfShuttingDownAndNotMainThreadSleepForeverAndNeverReturn(void) {
    
    if (  [NSThread isMainThread]  ) {
        TBLog(@"DB-SD", @"IfShuttingDownAndNotMainThreadSleepForeverAndNeverReturn invoked but on main thread, so returning.");
        return;
    }
    
    if (  ! gShuttingDownTunnelblick  ) {
        TBLog(@"DB-SD", @"IfShuttingDownAndNotMainThreadSleepForeverAndNeverReturn invoked but not shutting down, so returning.");
        return;
    }
    
    TBLog(@"DB-SD", @"Shutting down Tunnelblick, so this thread will never return from TBRunAlertPanel()");
    while (  TRUE  ) {
        sleep(1);
    }
}

// Takes the same arguments as, and is similar to, NSRunAlertPanel
// DOES NOT BEHAVE IDENTICALLY to NSRunAlertPanel:
//   * Stays on top of other windows
//   * Blocks the runloop
//   * Displays the Tunnelblick icon
//   * If title is nil, "Alert" will be used.
//   * If defaultButtonLabel is nil, "OK" will be used.

int TBRunAlertPanel(NSString * title, NSString * msg, NSString * defaultButtonLabel, NSString * alternateButtonLabel, NSString * otherButtonLabel)
{
    return TBRunAlertPanelExtendedPlus(title, msg, defaultButtonLabel, alternateButtonLabel, otherButtonLabel, nil, nil, nil, NSAlertDefaultReturn, nil, nil);
}

int TBRunAlertPanelExtended(NSString * title,
                            NSString * msg,
                            NSString * defaultButtonLabel,
                            NSString * alternateButtonLabel,
                            NSString * otherButtonLabel,
                            NSString * doNotShowAgainPreferenceKey,
                            NSString * checkboxLabel,
                            BOOL     * checkboxResult,
							int		   notShownReturnValue)
{
	NSArray * checkboxLabels = (  checkboxLabel
								 ? [NSArray arrayWithObject: checkboxLabel]
								 : nil);
	NSArray * checkboxResults = (  checkboxResult
								 ? [NSArray arrayWithObject: [NSNumber numberWithBool: *checkboxResult]]
								 : nil);
	int result = TBRunAlertPanelExtendedPlus(title, msg, defaultButtonLabel, alternateButtonLabel, otherButtonLabel,
									   doNotShowAgainPreferenceKey,
									   checkboxLabels,
									   &checkboxResults, notShownReturnValue, nil, nil);
	if (  checkboxResult  ) {
		*checkboxResult = [[checkboxResults firstObject] boolValue];
	}
	
	return result;
}

// Like TBRunAlertPanel but allows a "do not show again" preference key and checkbox, or a checkbox for some other function, and a target/selector which is polled to cancel the panel.
// If the "do not show again" preference has been set, the panel is not shown and "notShownReturnValue" is returned.
// If the preference can be changed by the user, and the checkboxResults pointer is not nil, the panel will include checkboxes with the specified labels.
// If the preference can be changed by the user, the preference is set if the user checks the box and the button that is clicked corresponds to the notShownReturnValue.
// If the checkboxResults pointer is not nil, the initial value of the checkbox(es) will be set from it, and the values of the checkboxes is returned to it.
// Every 0.2 seconds while the panel is being shown, this routine invokes [shouldCancelTarget performSelector: shouldCancelSelector] and cancels the dialog if it returns @YES.

int TBRunAlertPanelExtendedPlus (NSString * title,
                                 NSString * msg,
                                 NSString * defaultButtonLabel,
                                 NSString * alternateButtonLabel,
                                 NSString * otherButtonLabel,
                                 NSString * doNotShowAgainPreferenceKey,
								 NSArray  * checkboxLabels,
								 NSArray  * * checkboxResults,
                                 int		notShownReturnValue,
                                 id         shouldCancelTarget,
                                 SEL        shouldCancelSelector)
{
    
    if (  (shouldCancelTarget && shouldCancelSelector)  ) {
        if (  ! [shouldCancelTarget respondsToSelector: shouldCancelSelector]  ) {
            NSLog(@"TBRunAlertPanelExtendedPlus: '%@' does not respond to '%@'; call stack = %@",
                  [shouldCancelTarget class], NSStringFromSelector(shouldCancelSelector), callStack());
        }
    }
    
    if (  doNotShowAgainPreferenceKey && [gTbDefaults boolForKey: doNotShowAgainPreferenceKey]  ) {
        return notShownReturnValue;
    }
    
    NSMutableDictionary * dict = [[[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                   msg,  kCFUserNotificationAlertMessageKey,
                                   [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"tunnelblick" ofType: @"icns"]],
                                   kCFUserNotificationIconURLKey,
                                   nil] autorelease];
    if ( title ) {
        [dict setObject: title
                 forKey: (NSString *)kCFUserNotificationAlertHeaderKey];
    } else {
        [dict setObject: NSLocalizedString(@"Alert", @"Window title")
                 forKey: (NSString *)kCFUserNotificationAlertHeaderKey];
    }
    
    if ( defaultButtonLabel ) {
        [dict setObject: defaultButtonLabel
                 forKey: (NSString *)kCFUserNotificationDefaultButtonTitleKey];
    } else {
        [dict setObject: NSLocalizedString(@"OK", @"Button")
                 forKey: (NSString *)kCFUserNotificationDefaultButtonTitleKey];
    }
    
    if ( alternateButtonLabel ) {
        [dict setObject: alternateButtonLabel
                 forKey: (NSString *)kCFUserNotificationAlternateButtonTitleKey];
    }
    
    if ( otherButtonLabel ) {
        [dict setObject: otherButtonLabel
                 forKey: (NSString *)kCFUserNotificationOtherButtonTitleKey];
    }
    
    if (  checkboxLabels  ) {
        if (   checkboxResults
            || ( doNotShowAgainPreferenceKey && [gTbDefaults canChangeValueForKey: doNotShowAgainPreferenceKey] )
            ) {
            [dict setObject: checkboxLabels forKey:(NSString *)kCFUserNotificationCheckBoxTitlesKey];
        }
    }
    
    SInt32 error = 0;
    CFOptionFlags response = 0;

    CFOptionFlags checkboxesChecked = 0;
    if (  checkboxResults  ) {
		NSUInteger i;
		for (  i=0; (  (i<[checkboxLabels count]) && (i < 8)  ); i++  ) {
			if (  [[*checkboxResults objectAtIndex: i] boolValue]  ) {
				checkboxesChecked |= CFUserNotificationCheckBoxChecked(i);
			}
		}
    }
    
    [gMC activateIgnoringOtherApps];
    
    CFUserNotificationRef panelRef = CFUserNotificationCreate(NULL, 0.0, checkboxesChecked, &error, (CFDictionaryRef) dict);

    if (   error
        || (panelRef == NULL)
        ) {
        
		NSLog(@"CFUserNotificationCreate() returned with error = %ld; notification = %@, so TBRunAlertExtended is terminating Tunnelblick after attempting to display an error window using CFUserNotificationDisplayNotice",
              (long) error, (panelRef ? @"non-0" : @"0"));
        if (  panelRef != NULL  ) {
            CFRelease(panelRef);
            panelRef = NULL;
        }
        
        // Try showing a regular window (but it will disappear when Tunnelblick terminates)
        TBShowAlertWindow(NSLocalizedString(@"Alert", @"Window title"),
                          [NSString stringWithFormat:
                           NSLocalizedString(@"Tunnelblick could not display a window.\n\n"
                                             @"CFUserNotificationCreate() returned with error = %ld; notification = %@", @"Window text"),
                           (long) error, (panelRef ? @"non-0" : @"0")]);
        
        // Try showing a modal alert window
        SInt32 status = CFUserNotificationDisplayNotice(60.0,
                                                        kCFUserNotificationStopAlertLevel,
                                                        NULL,
                                                        NULL,
                                                        NULL,
                                                        (CFStringRef) NSLocalizedString(@"Alert", @"Window title"),
                                                        (CFStringRef) [NSString stringWithFormat:
                                                                       NSLocalizedString(@"Tunnelblick could not display a window.\n\n"
                                                                                         @"CFUserNotificationCreate() returned with error = %ld; notification = %@", @"Window text"),
                                                                       (long) error, (panelRef ? @"non-0" : @"0")],
                                                        NULL);
        NSLog(@"CFUserNotificationDisplayNotice() returned %ld", (long) status);
        if (  panelRef != NULL  ) {
            CFRelease(panelRef);
            panelRef = NULL;
        }
        [gMC terminateBecause: terminatingBecauseOfError];
        return NSAlertErrorReturn; // Make the Xcode code analyzer happy
    }
    
    // Save the notification ref in our array
    LockAlertRefs();
    if (  ! AlertRefs  ) {
        AlertRefs = [[NSMutableArray alloc] initWithCapacity: 8];
    }
    [AlertRefs addObject: (id)panelRef];
    TBLog(@"DB-SD", @"TBRunAlertPanelExtended saved %@ in AlertRefs; AlertRefs = %@", (panelRef ? @"non-0" : @"0"), AlertRefs);
    UnlockAlertRefs();
    
    // Loop waiting for either a response or a shutdown of Tunnelblick
    SInt32 responseReturnCode = -1;
    while (  TRUE  ) {
        responseReturnCode = CFUserNotificationReceiveResponse(panelRef, 0.2, &response);
        if ( responseReturnCode == 0  ) {  // The user clicked a button
            break;
        }
        
        // A timeout occurred.
        // If we should cancel this panel or we are shutting down Tunnelblick, cancel the panel. Otherwise, continue waiting.
        
        BOOL cancel = (  (shouldCancelTarget && shouldCancelSelector)
                       ? [((NSNumber *)[shouldCancelTarget performSelector: shouldCancelSelector]) boolValue]
                      : FALSE);
        if (   cancel
            || gShuttingDownTunnelblick  ) {
            SInt32 result = CFUserNotificationCancel(panelRef);
            TBLog(@"DB-SD", @"Cancelled alert panel %@ with result %ld", (panelRef ? @"non-0" : @"0"), (unsigned long) result);
            if (  result != 0  ) {
                TBLog(@"DB-SD", @"Cancel of alert panel %@ failed, so simulating it", (panelRef ? @"non-0" : @"0"));
                responseReturnCode = 0;
                response = kCFUserNotificationCancelResponse;
                break;
            }
        }
    }
    
    TBLog(@"DB-SD", @"CFUserNotificationReceiveResponse returned %ld; response = %ld for panel %@; AlertRefs; AlertRefs = %@", (long)responseReturnCode, (long)response, (panelRef ? @"non-0" : @"0"), AlertRefs);
    
    if (  panelRef != NULL  ) {
        // Remove from AlertRefs
        LockAlertRefs();
        [AlertRefs removeObject: (id)panelRef];
        TBLog(@"DB-SD", @"TBRunAlertPanelExtended removed %@ from AlertRefs; AlertRefs = %@", (panelRef ? @"non-0" : @"0"), AlertRefs);
        UnlockAlertRefs();
        CFRelease(panelRef);
        panelRef = NULL;
    }
    
    IfShuttingDownAndNotMainThreadSleepForeverAndNeverReturn();
    
    if (  checkboxResults  ) {
        NSMutableArray * cbResults = [[NSMutableArray alloc] initWithCapacity:8];
        NSUInteger i;
		for (  i=0; (  (i<[checkboxLabels count]) && (i < 8)  ); i++  ) {
			[cbResults addObject: [NSNumber numberWithBool: ((response & CFUserNotificationCheckBoxChecked(i)) != 0)]];
        }
		*checkboxResults = [[cbResults copy] autorelease];
    }

    // If we are shutting down Tunnelblick, force the response to be "Cancel"
    if (   gShuttingDownTunnelblick
        && (response != kCFUserNotificationCancelResponse)  ) {
        TBLog(@"DB-SD", @"Shutting down Tunnelblick, so forcing the alert window response to be cancelled");
        response = kCFUserNotificationCancelResponse;
    }
    
    switch (response & 0x3) {
        case kCFUserNotificationDefaultResponse:
			if (  notShownReturnValue == NSAlertDefaultReturn  ) {
				if (  checkboxLabels  ) {
					if (   doNotShowAgainPreferenceKey
						&& [gTbDefaults canChangeValueForKey: doNotShowAgainPreferenceKey]
						&& ( response & CFUserNotificationCheckBoxChecked(0) )  ) {
						[gTbDefaults setBool: TRUE forKey: doNotShowAgainPreferenceKey];
					}
				}
			}
				
            return NSAlertDefaultReturn;
            
        case kCFUserNotificationAlternateResponse:
			if (  notShownReturnValue == NSAlertAlternateReturn  ) {
				if (  checkboxLabels  ) {
					if (   doNotShowAgainPreferenceKey
						&& [gTbDefaults canChangeValueForKey: doNotShowAgainPreferenceKey]
						&& ( response & CFUserNotificationCheckBoxChecked(0) )  ) {
						[gTbDefaults setBool: TRUE forKey: doNotShowAgainPreferenceKey];
					}
				}
			}
			
            return NSAlertAlternateReturn;
            
        case kCFUserNotificationOtherResponse:
			if (  notShownReturnValue == NSAlertOtherReturn  ) {
				if (  checkboxLabels  ) {
					if (   doNotShowAgainPreferenceKey
						&& [gTbDefaults canChangeValueForKey: doNotShowAgainPreferenceKey]
						&& ( response & CFUserNotificationCheckBoxChecked(0) )  ) {
						[gTbDefaults setBool: TRUE forKey: doNotShowAgainPreferenceKey];
					}
				}
			}
			
            return NSAlertOtherReturn;
            
        default:
            TBLog(@"DB-SD", @"CFUserNotificationReceiveResponse() returned a cancel response");
            IfShuttingDownAndNotMainThreadSleepForeverAndNeverReturn();
            return NSAlertErrorReturn;
    }
}

BOOL processIsTranslated(void) {

    // Adapted from https://developer.apple.com/documentation/apple_silicon/about_the_rosetta_translation_environment

    int ret = 0;
    size_t size = sizeof(ret);
    if (  sysctlbyname("sysctl.proc_translated", &ret, &size, NULL, 0) == -1  ) {
        if (errno == ENOENT) {
            return NO;
        }

        NSLog(@"Error from sysctlbyname: %d", ret);
        return NO;
    }
    
    return (BOOL) ret;
}

BOOL isUserAnAdmin(void)
{
    // Run "id -Gn" to get a list of names of the groups the user is a member of
	NSString * stdoutString = nil;
	NSArray  * arguments = [NSArray arrayWithObject: @"-Gn"];
	OSStatus status = runTool(TOOL_PATH_FOR_ID, arguments, &stdoutString, nil);
	if (  status != 0  ) {
		NSLog(@"Assuming user is not an administrator because '%@ -Gn' returned status %ld", TOOL_PATH_FOR_ID, (long)status);
		return NO;
	}
	
    // If the "admin" group appears in the output, the user is a member of the "admin" group, so they are an admin.
    // Group names don't include spaces and are separated by spaces, so this is easy. We just have to
    // handle admin being at the start or end of the output by pre- and post-fixing a space.
    
    NSString * groupNames = [NSString stringWithFormat:@" %@ ", [stdoutString stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    NSRange rng = [groupNames rangeOfString:@" admin "];
    return (rng.location != NSNotFound);
}

// Modified from http://developer.apple.com/library/mac/#documentation/Carbon/Conceptual/ProvidingUserAssitAppleHelp/using_ah_functions/using_ah_functions.html#//apple_ref/doc/uid/TP30000903-CH208-CIHFABIE
OSStatus MyGotoHelpPage (NSString * pagePath, NSString * anchorName)
{
    OSStatus err = noErr;
    
    CFBundleRef myApplicationBundle = NULL;
    CFStringRef myBookName = NULL;
    
    myApplicationBundle = CFBundleGetMainBundle();
    if (myApplicationBundle == NULL) {
        err = fnfErr;
        goto bail;
    }
    
    myBookName = CFBundleGetValueForInfoDictionaryKey(
                                                      myApplicationBundle,
                                                      CFSTR("CFBundleHelpBookName"));
    if (myBookName == NULL) {
        err = fnfErr;
        goto bail;
    }
    
    if (CFGetTypeID(myBookName) != CFStringGetTypeID()) {
        err = paramErr;
        goto bail;
    }
    
    err = AHGotoPage (myBookName, (CFStringRef) pagePath, (CFStringRef) anchorName);// 5
    
bail:
	if ( err != noErr  ) {
		NSLog(@"Error %ld in MyGotoHelpPage()", (long) err);
	}
	
    return err;
}

NSString * credentialsGroupFromDisplayName (NSString * displayName)
{
	NSString * allGroup = [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"];
	if (  [allGroup length] != 0  ) {
		return allGroup;
	}
	
	NSString * prefKey = [displayName stringByAppendingString: @"-credentialsGroup"];
	NSString * group = [gTbDefaults stringForKey: prefKey];
	if (  [group length] == 0  ) {
		return nil;
	}
	
	return group;
}	

BOOL keychainHasPrivateKeyForDisplayName(NSString * name) {
    
    NSString * key = [name stringByAppendingString: @"-keychainHasPrivateKey"];
    return (   [gTbDefaults boolForKey: key]
            && [gTbDefaults canChangeValueForKey: key]
            );
}

BOOL keychainHasUsernameWithoutPasswordForDisplayName(NSString * name) {
    
    NSString * key = [name stringByAppendingString: @"-keychainHasUsername"];
    return (   [gTbDefaults boolForKey: key]
            && [gTbDefaults canChangeValueForKey: key]
            );
}

BOOL keychainHasUsernameAndPasswordForDisplayName(NSString * name) {
    
    NSString * key = [name stringByAppendingString: @"-keychainHasUsernameAndPassword"];
    return (   [gTbDefaults boolForKey: key]
            && [gTbDefaults canChangeValueForKey: key]
            );
}

BOOL copyCredentials(NSString * fromDisplayName, NSString * toDisplayName)
{
    return copyOrMoveCredentials(fromDisplayName, toDisplayName, FALSE);
}

BOOL moveCredentials(NSString * fromDisplayName, NSString * toDisplayName)
{
    return copyOrMoveCredentials(fromDisplayName, toDisplayName, TRUE);
}

BOOL copyOrMoveCredentials(NSString * fromDisplayName, NSString * toDisplayName, BOOL moveNotCopy)
{
    // DOES NOT COPY OR MOVE THE PREFERENCES ASSOCIATED WITH THE CREDENTIALS
    
	NSString * group = credentialsGroupFromDisplayName(fromDisplayName);
	if (  group  ) {
		return YES;
	}		
		
    BOOL haveFromPassphrase              = keychainHasPrivateKeyForDisplayName(fromDisplayName);
    BOOL haveFromUsernameAndPassword     = keychainHasUsernameAndPasswordForDisplayName(fromDisplayName);
    BOOL haveFromUsernameWithoutPassword = keychainHasUsernameWithoutPasswordForDisplayName(fromDisplayName);

    if (   haveFromPassphrase
        || haveFromUsernameAndPassword
        || haveFromUsernameWithoutPassword  ) {
        
        NSString * myPassphrase = nil;
        NSString * myUsername = nil;
        NSString * myPassword = nil;
        
        AuthAgent * myAuthAgent = [[[AuthAgent alloc] initWithConfigName: fromDisplayName credentialsGroup: nil] autorelease];
        
        if (  haveFromPassphrase  ) {
            [myAuthAgent setAuthMode: @"privateKey"];
            [myAuthAgent performAuthenticationAllowingInteraction: NO];
            myPassphrase = [myAuthAgent passphrase];
            if (  moveNotCopy) {
                [myAuthAgent deleteCredentialsFromKeychainIncludingUsername: YES];
            }
        }
        
        if (   haveFromUsernameAndPassword
            || haveFromUsernameWithoutPassword  ) {
            [myAuthAgent setAuthMode: @"password"];
            [myAuthAgent performAuthenticationAllowingInteraction: NO];
            myUsername = [myAuthAgent username];
            if (  haveFromUsernameAndPassword  ) {
                myPassword = [myAuthAgent password];
            }
            if (  moveNotCopy) {
                [myAuthAgent deleteCredentialsFromKeychainIncludingUsername: YES];
            }
        }
        
        if (   myPassphrase
            && [gTbDefaults canChangeValueForKey: [toDisplayName stringByAppendingString: @"%@-keychainHasPrivateKey"]]  ) {
            KeyChain * passphraseKeychain = [[KeyChain alloc] initWithService:[@"Tunnelblick-Auth-" stringByAppendingString: toDisplayName] withAccountName: @"privateKey" ];
            [passphraseKeychain deletePassword];
            if (  [passphraseKeychain setPassword: myPassphrase] != 0  ) {
                NSLog(@"Could not store passphrase in Keychain");
            }
            [passphraseKeychain release];
        }
        
        if (   myUsername
            && (   [gTbDefaults canChangeValueForKey: [toDisplayName stringByAppendingString: @"%@-keychainHasUsername"]]
                || [gTbDefaults canChangeValueForKey: [toDisplayName stringByAppendingString: @"%@-keychainHasUsernameAndPassword"]]
                )  ) {
            KeyChain * usernameKeychain   = [[KeyChain alloc] initWithService:[@"Tunnelblick-Auth-" stringByAppendingString: toDisplayName] withAccountName: @"username"   ];
            [usernameKeychain deletePassword];
            if (  [usernameKeychain setPassword: myUsername] != 0  ) {
                NSLog(@"Could not store username in Keychain");
            }
            [usernameKeychain   release];
        }
        
        if (   myPassword
           && [gTbDefaults canChangeValueForKey: [toDisplayName stringByAppendingString: @"%@-keychainHasUsernameAndPassword"]]  ) {
            KeyChain * passwordKeychain   = [[KeyChain alloc] initWithService:[@"Tunnelblick-Auth-" stringByAppendingString: toDisplayName] withAccountName: @"password"   ];
            [passwordKeychain deletePassword];
            if (  [passwordKeychain setPassword: myPassword] != 0  ) {
                NSLog(@"Could not store password in Keychain");
            }
            [passwordKeychain   release];
        }
    }
    
    return TRUE;
}

NSMutableString * encodeSlashesAndPeriods(NSString * s)
{
    // Encode slashes and periods in the displayName so the result can act as a single component in a file name
    NSMutableString * result = [[s mutableCopy] autorelease];
    [result replaceOccurrencesOfString: @"-" withString: @"--" options: 0 range: NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString: @"." withString: @"-D" options: 0 range: NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString: @"/" withString: @"-S" options: 0 range: NSMakeRange(0, [result length])];
    return result;
}

NSString * copyrightNotice()
{
    NSDateFormatter * dateFormat = [[[NSDateFormatter alloc] init] autorelease];
    [dateFormat setLocale: [NSLocale localeWithLocaleIdentifier: @"en_US_POSIX"]];
    [dateFormat setDateFormat:@"YYYY"];
    NSString * year = [dateFormat stringFromDate: [NSDate date]];
    return [NSString stringWithFormat:
            NSLocalizedString(@"Copyright © 2004-%@ Angelo Laub, Jonathan Bullard, and others.", @"Window text"),
            year];
}

NSString * stringForLog(NSString * outputString, NSString * header)
{
    outputString = [outputString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (  [outputString length] == 0  ) {
		return @"";
	}
	outputString = [header stringByAppendingString: outputString];
    NSMutableString * tempMutableString = [[outputString mutableCopy] autorelease];
    [tempMutableString replaceOccurrencesOfString: @"\n" withString: @"\n     " options: 0 range: NSMakeRange(0, [tempMutableString length])];
	return [[tempMutableString copy] autorelease];
}

NSString * configLocCodeStringForPath(NSString * configPath) {
    
    unsigned code;
    
    if (  [configPath hasPrefix: [gPrivatePath  stringByAppendingString: @"/"]]  ) {
        code = CFG_LOC_PRIVATE;
        
    } else if (  [configPath hasPrefix: [gDeployPath   stringByAppendingString: @"/"]]  ) {
        code = CFG_LOC_DEPLOY;
    
    } else if (  [configPath hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]  ) {
        code = CFG_LOC_SHARED;
    
    } else if (  [configPath hasPrefix: [[L_AS_T_USERS stringByAppendingPathComponent: NSUserName()] stringByAppendingString: @"/"]]  ) {
        code = CFG_LOC_ALTERNATE;
    
    } else {
        NSLog(@"configLocCodeStringForPath: unknown path %@", configPath);
        [gMC terminateBecause: terminatingBecauseOfError];
        return [NSString stringWithFormat: @"%u", CFG_LOC_MAX + 1];
    }
    
    return [NSString stringWithFormat: @"%u", code];
}

OSStatus runOpenvpnstart(NSArray * arguments, NSString ** stdoutString, NSString ** stderrString)
{
	// Make sure no arguments include a \t or \0
	NSUInteger i;
	for (  i=0; i<[arguments count]; i++  ) {
        NSString * arg = [arguments objectAtIndex: i];
		if (   [arg containsString: @"\t"]
            || [arg containsString: @"\0"]  ) {
			NSLog(@"runOpenvpnstart: Argument %lu contains one or more HTAB (ASCII 0x09) or NULL (ASCII (0x00) characters. They are not allowed in arguments. Arguments = %@", (unsigned long)i, arguments);
			return -1;
		}
	}
    
    OSStatus status = -1;
	NSString * myStdoutString = nil;
	NSString * myStderrString = nil;
    
    NSString * command = [[arguments componentsJoinedByString: @"\t"] stringByAppendingString: @"\n"];
    status = runTunnelblickd(command, &myStdoutString, &myStderrString);
    
    NSString * subcommand = ([arguments count] > 0
                             ? [arguments objectAtIndex: 0]
                             : @"(no subcommand!)");
    
    NSMutableString * logMsg = [NSMutableString stringWithCapacity: 100 + [myStdoutString length] + [myStderrString length]];
    
    if (  stdoutString  ) {
        *stdoutString = myStdoutString;
    } else {
        if (  [myStdoutString length] != 0  ) {
            [logMsg appendFormat: @"tunnelblickd stdout:\n'%@'\n", myStdoutString];
        }
    }
    
    if (  stderrString  ) {
        *stderrString = myStderrString;
    } else {
        if (  [myStderrString length] != 0  ) {
            [logMsg appendFormat: @"tunnelblickd stderr:\n'%@'\n", myStderrString];
        }
    }
    
#ifdef TBDebug
	NSString * header = [NSString stringWithFormat: @"tunnelblickd status from %@: %ld\nArguments:\n%@\n", subcommand, (long) status, arguments];
	[logMsg insertString: header atIndex: 0];
	NSLog(@"%@", logMsg);
#else
	if (  status != EXIT_SUCCESS ) {
		NSString * header = [NSString stringWithFormat: @"tunnelblickd status from %@: %ld\n", subcommand, (long) status];
		[logMsg insertString: header atIndex: 0];
		NSLog(@"%@", logMsg);
	}
#endif
	
    return status;
}

BOOL tunnelblickTestPrivateOnlyHasTblks(void)
{
    NSString * privatePath = [[[[NSHomeDirectory()
                                 stringByAppendingPathComponent: @"Library"]
                                stringByAppendingPathComponent: @"Application Support"]
                               stringByAppendingPathComponent: @"Tunnelblick"]
                              stringByAppendingPathComponent: @"Configurations"];
    NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: privatePath];
    NSString * file;
    while (  (file = [dirEnum nextObject])  )
	{
        if (  [[file pathExtension] isEqualToString: @"tblk"]  )
		{
            [dirEnum skipDescendents];
        } else {
            if (   [[file pathExtension] isEqualToString: @"ovpn"]
                || [[file pathExtension] isEqualToString: @"conf"]  )
			{
                return NO;
            }
        }
    }
    
    return YES;
}

BOOL tunnelblickTestAppInApplications(void)
{
    NSString * appContainer = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
    return [appContainer isEqualToString: @"/Applications"];
}

BOOL tunnelblickTestDeployed(void)
{
    // Returns TRUE if Deploy folder exists and contains anything
    
 	NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: gDeployPath];
    NSString * file;
    BOOL haveSomethingInDeployFolder = FALSE;
    while (  (file = [dirEnum nextObject])  )
	{
        if (  ! [file hasPrefix: @"."]  )		// Ignore .DS_Store, .svn, etc.
		{
            haveSomethingInDeployFolder = TRUE;
            break;
        }
    }
    
    return haveSomethingInDeployFolder;
}

BOOL tunnelblickTestHasDeployBackups(void)
{
    // Returns TRUE if Deploy backup folder exists
    
    NSString * deployBackupsPath = @"/Library/Application Support/Tunnelblick/Backup";
	BOOL isDir;
	if (   [gFileMgr fileExistsAtPath: deployBackupsPath isDirectory: &isDir]
		&& isDir  ) {
		return YES;
	}
	
	return NO;
}

// This method translates and returns non-literal OpenVPN message.
// It is used to consolidate the use of NS LocalizedString (non-literal-string...) in one place to minimize warnings from genstrings.
//                                        ^ space inserted to keep genstrings from finding this
NSString * localizeNonLiteral(NSString * msg, NSString * type)
{
	(void) type;
	
    return NSLocalizedString(msg, type);
}

// This method is never invoked. It is a place to put strings which are used in the DMG or the .nib or come from OpenVPN
// They are here so that automated tools that deal with strings (such as the "getstrings" command) will include them.
void localizableStrings(void)
{
	// These strings come from "thank you" emails
    NSLocalizedString(@"Thanks for your Tunnelblick donation", @"Window text");
    NSLocalizedString(@"Thank you very much for your donation to the TunnelblickProject.", @"Window text");
	
	
    // This string comes from the "Other Sources/dmgFiles/background.rtf" file, used to generate an image for the DMG
    NSLocalizedString(@"Double-click to begin", @"Text on disk image");
    
    // These strings come from OpenVPN and indicate the status of a connection
    NSLocalizedString(@"ADD_ROUTES",    @"Connection status");
    NSLocalizedString(@"ASSIGN_IP",     @"Connection status");
    NSLocalizedString(@"AUTH",          @"Connection status");
    NSLocalizedString(@"CONNECTED",     @"Connection status");
    NSLocalizedString(@"CONNECTING",    @"Connection status");
    NSLocalizedString(@"EXITING",       @"Connection status");
    NSLocalizedString(@"GET_CONFIG",    @"Connection status");
    NSLocalizedString(@"RECONNECTING",  @"Connection status");
    NSLocalizedString(@"RESOLVE",       @"Connection status");
    NSLocalizedString(@"SLEEP",         @"Connection status");
    NSLocalizedString(@"TCP_CONNECT",   @"Connection status");
    NSLocalizedString(@"UDP_CONNECT",   @"Connection status");
    NSLocalizedString(@"WAIT",          @"Connection status");
	
	// These strings also indicate the status of a connection, but they are set by Tunnelblick itself, not OpenVPN
	NSLocalizedString(@"PASSWORD_WAIT",    @"Connection status");
	NSLocalizedString(@"PRIVATE_KEY_WAIT", @"Connection status");
    NSLocalizedString(@"DISCONNECTING",    @"Connection status");
	NSLocalizedString(@"NETWORK_ACCESS",   @"Connection status");
}

BOOL itemHasValidSignature(NSString * path, BOOL deepCheck) {
    
    NSURL * urlToCheck = [NSURL fileURLWithPath: path];
    
    CFErrorRef errorCF = NULL;
    SecStaticCodeRef staticCode = NULL;
    
    OSStatus status = SecStaticCodeCreateWithPath((__bridge CFURLRef)urlToCheck, kSecCSDefaultFlags, &staticCode);
    if (status != errSecSuccess) {
        NSLog(@"SecStaticCodeCreateWithPath() failed with status = %d for path %@", status, path);
        goto done;
    }
    
    SecCSFlags flags = kSecCSDefaultFlags | kSecCSStrictValidate | kSecCSCheckAllArchitectures;
    if ( deepCheck  ) {
        flags = flags | kSecCSCheckNestedCode;
    }
    
    status = SecStaticCodeCheckValidityWithErrors(staticCode, flags, NULL, &errorCF);
    
    if (status != errSecSuccess) {
        if (status == errSecCSUnsigned) {
            NSLog(@"Error: Item is not digitally signed at path = %@", path);
        } else if (status == errSecCSReqFailed) {
            NSLog(@"Error: The item failed the code requirements check at path = %@\nError = '%@'", path, (__bridge NSError *)errorCF);
        } else {
            NSLog(@"Error: The item failed the digital signature check (status = %ld) at path = %@\nError = '%@'", (long)status, path, (__bridge NSError *)errorCF);
        }
    }
    
done:
    if (staticCode) {
        CFRelease(staticCode);
    }
    if (errorCF) {
        CFRelease(errorCF);
    }
    
    return (status == errSecSuccess);
}

BOOL appHasValidSignature(void) {
    
    NSString * appPath = [[NSBundle mainBundle] bundlePath];
    
    if (   itemHasValidSignature(appPath, YES)
        && itemHasValidSignature([appPath stringByAppendingPathComponent:
                                  @"/Contents/Frameworks/Sparkle.framework/Versions/A/Resources/TunnelblickUpdater.app/Contents/MacOS/fileop"], NO)
        ) {
        return YES;
    }
    
    return NO;
}

NSString * displayNameForOpenvpnName(NSString * openvpnName, NSString * nameToReturnIfError) {
	
	// OpenVPN binaries are held in folders in the 'openvpn' folder in Resources.
	// The name of the folder includes the version of OpenVPN and the name and version of the SSL/TLS library it is linked to.
	// The folder name must have a prefix of 'openvpn-' followed by the version number, followed by a '-' and a library name, followed by a '-' and a library version number.
	// The folder name must not contain any spaces, but underscores will be shown as spaces to the user, and "known" library names will be upper-cased appropriately.
	// The version numbers and library name cannot contain '-' characters.
	// Example: a folder named 'openvpn-1.2.3_git_master_123abcd-libressl-4.5.6' will be shown to the user as "123 git master 123abcd - LibreSSL v4.5.6"
	//
	// NOTE: This method's input openvpnName is the part of the folder name _after_ 'openvpn-' except that if it is located in L_AS_T/openvpn it must be suffixed with SUFFIX_FOR_OPENVPN_BINARY_IN_L_AS_T_OPENVPN.
	
	NSArray * parts = [openvpnName componentsSeparatedByString: @"-"];
	
	NSString * name;
	
	if (   [parts count] == 3  ) {
		NSMutableString * mName = [[[NSString stringWithFormat: NSLocalizedString(@"%@ - %@ v%@", @"An entry in the drop-down list of OpenVPN versions that are available on the 'Settings' tab. "
																				  "The first %@ is an OpenVPN version number, e.g. '2.3.10'. The second %@ is an SSL library name, e.g. 'LibreSSL'. The third %@ is the SSL library version, e.g. 1.0.1a"),
									 [parts objectAtIndex: 0], [parts objectAtIndex: 1], [parts objectAtIndex: 2]]
									mutableCopy] autorelease];
		[mName replaceOccurrencesOfString: @"openssl"   withString: @"OpenSSL"   options: 0 range: NSMakeRange(0, [mName length])];
		[mName replaceOccurrencesOfString: @"libressl"  withString: @"LibreSSL"  options: 0 range: NSMakeRange(0, [mName length])];
		[mName replaceOccurrencesOfString: @"mbedtls"   withString: @"mbed TLS"  options: 0 range: NSMakeRange(0, [mName length])];
		[mName replaceOccurrencesOfString: @"boringssl" withString: @"BoringSSL" options: 0 range: NSMakeRange(0, [mName length])];
		[mName replaceOccurrencesOfString: @"_"         withString: @" "         options: 0 range: NSMakeRange(0, [mName length])];
		name = [NSString stringWithString: mName];
	} else {
		name = [[nameToReturnIfError retain] autorelease];
	}

	if (  [name hasSuffix: SUFFIX_FOR_OPENVPN_BINARY_IN_L_AS_T_OPENVPN]  ) {
		name = [NSString stringWithFormat: NSLocalizedString(@"%@ (non-Tunnelblick)",@"Window text. The '%@' is the name of an OpenVPN and SSL binary, e.g. 'OpenVPN 2.4.8 OpenSSL 1.1.1'"),
				[name substringToIndex: [name length] - [SUFFIX_FOR_OPENVPN_BINARY_IN_L_AS_T_OPENVPN length]]];
	}
	
	return name;
}

NSString * messageIfProblemInLogLine(NSString * line) {
	
	NSArray * messagesToWarnAbout = [NSArray arrayWithObjects:
									 @"WARNING: Your certificate is not yet valid!",
									 @"WARNING: Your certificate has expired!",
									 @"Unrecognized option or missing parameter(s)",
									 @"Unrecognized option or missing or extra parameter(s)",
									 @"error=certificate has expired:",
									 nil];
	
	NSArray * correspondingInfo = [NSArray arrayWithObjects:
								   @"",
								   @"",
								   NSLocalizedString(@"\n\n"
													 @"This error means that an option that is contained in the OpenVPN configuration file or was"
													 @" \"pushed\" by the OpenVPN server:\n\n"
													 @"     • has been misspelled,\n\n"
													 @"     • has missing or extra arguments, or\n\n"
													 @"     • is not implemented by the version of OpenVPN which is being used for this configuration."
													 @" It may be a new option that is not implemented in an old version of OpenVPN, or an old option"
													 @" that has been removed in a new version of OpenVPN. You can choose what version of OpenVPN to use"
													 @" with this configuration in the \"Settings\" tab of the \"Configurations\" panel of Tunnelblick's"
													 @" \"VPN Details\" window.\n\n"
													 @"See the VPN log in the \"Log\" tab of the \"Configurations\" panel of Tunnelblick's"
													 @" \"VPN Details\" window for details.",
													 
													 @"Window text"),
								   NSLocalizedString(@"\n\n"
													 @"This error means that an option that is contained in the OpenVPN configuration file or was"
													 @" \"pushed\" by the OpenVPN server:\n\n"
													 @"     • has been misspelled,\n\n"
													 @"     • has missing or extra arguments, or\n\n"
													 @"     • is not implemented by the version of OpenVPN which is being used for this configuration."
													 @" It may be a new option that is not implemented in an old version of OpenVPN, or an old option"
													 @" that has been removed in a new version of OpenVPN. You can choose what version of OpenVPN to use"
													 @" with this configuration in the \"Settings\" tab of the \"Configurations\" panel of Tunnelblick's"
													 @" \"VPN Details\" window.\n\n"
													 @"See the VPN log in the \"Log\" tab of the \"Configurations\" panel of Tunnelblick's"
													 @" \"VPN Details\" window for details.",
													 
													 @"Window text"),
								   /* The line containging 'One or more' in the following message should not be changed without changing the copy of it in LogDisplay.m */
								   NSLocalizedString(@"\n\n"
													 @"One or more of the certificates used to secure this configuration have expired.\n\n"
													 @"See the VPN log in the \"Log\" tab of the \"Configurations\" panel of Tunnelblick's"
													 @" \"VPN Details\" window for details.",
													 
													 @"Window text"),
								   nil];
	
	if (  [messagesToWarnAbout count] != [correspondingInfo count]  ) {
		NSLog(@"messageForProblemsSeenInLogLine: messagesToWarnAbout and correspondingInfo do not have the same number of entries");
		[gMC terminateBecause: terminatingBecauseOfError];
		return nil;
	}
	
	NSUInteger ix;
	for (  ix=0; ix<[messagesToWarnAbout count]; ix++  ) {
		
		NSString * message = [messagesToWarnAbout objectAtIndex: ix];
		if (  [line containsString: message]  ) {
			
			NSString * moreInfo = (  ([correspondingInfo count] >= ix)
								   ? [correspondingInfo objectAtIndex: ix]
								   : @"");
			
			return [NSString stringWithFormat:
					NSLocalizedString(@"The OpenVPN log contains the following message: \n\n\"%@\".%@",
									  @"Window text. The first '%@' will be replaced by an OpenVPN warning or error message (in English) such as 'WARNING: Your certificate is not yet valid!'. The second '%@' will be replaced with an empty string or an already-translated comment that explains the warning or error in more detail."),
					message, moreInfo];
		}
	}
	
	return nil;
}
