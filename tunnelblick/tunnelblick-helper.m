/*
 * Copyright 2004, 2005, 2006, 2007, 2008, 2009, 2010, 2011 Angelo Laub
 * Contributions by Dirk Theisen
 * Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2017, 2018. All rights reserved.
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

#import <CoreServices/CoreServices.h>
#import <Foundation/Foundation.h>
#import <sys/acl.h>
#import <sys/mount.h>
#import <sys/param.h>
#import <sys/sysctl.h>
#import <sys/types.h>
#import <sys/xattr.h>
#import <SystemConfiguration/SystemConfiguration.h>

#import "defines.h"
#import "sharedRoutines.h"

#import "NSFileManager+TB.h"
#import "NSString+TB.h"


//**************************************************************************************************************************
NSAutoreleasePool   * pool           = nil;

NSString			* gConfigPath    = nil;     // Path to configuration file
//                                                 in ~/Library/Application Support/Tunnelblick/Configurations/
//                                                 or /Library/Application Support/Tunnelblick/Users/<username>/
//                                                 or /Library/Application Support/Tunnelblick/Shared
//                                                 or /Applications/XXXXX.app/Contents/Resources/Deploy
NSString			* gResourcesPath = nil;     // Path to Tunnelblick.app/Contents/Resources
NSString            * gDeployPath    = nil;     // Path to Tunnelblick.app/Contents/Resources/Deploy
NSString            * gStartArgs     = nil;     // String with an underscore-delimited list of the following arguments to openvpnstart's start
//                                              // subcommand: useScripts, skipScrSec, cfgLocCode, noMonitor, and bitMask

uid_t                 gUidOfUser     = 0;       // User's uid (or 0 if started via 'sudo'
NSString            * gUserName      = nil;
NSString            * gUserHome      = nil;

int                   gPendingRootCounter = 0;  // Number of becomeRoot requests that are pending
//                                              //        incremented by becomeRoot, decremented by stopBeingRoot
//                                              //        when increments to one, become root
//                                              //        when decements to zero, become non-root

//**************************************************************************************************************************

void appendLog(NSString * msg) {
    fprintf(stderr, "%s\n", [msg UTF8String]);
}

    // returnValue: have used 169-246, plus the values in define.h (247-254)
void exitOpenvpnstart(OSStatus returnValue) {
    [pool drain];
    exit(returnValue);
}

void printUsageMessageAndExitOpenvpnstart(void) {
    const char * killStringC;
    if (  ALLOW_OPENVPNSTART_KILL  ) {
        killStringC =
        "./openvpnstart kill   processId\n"
        "               to terminate the 'openvpn' process with the specified processID\n\n";
    } else {
        killStringC = "";
    }
    
    const char * killAllStringC;
    if (  ALLOW_OPENVPNSTART_KILLALL  ) {
        killAllStringC =
        "./openvpnstart killall\n"
        "               to terminate all processes named 'openvpn'\n\n";
    } else {
        killAllStringC = "";
    }
    
    fprintf(stderr,
            "\n\nopenvpnstart usage:\n\n"
            
            // killStringC is inserted here:
            "%s"
            
            // killAllStringC is inserted here:
            "%s"
            
            "./openvpnstart test\n"
            "               always returns success\n\n"
            
			"./openvpnstart re-enable-network-services\n"
			"               to run Tunnelblick's re-enable-network-services.sh script\n\n"
			
            "./openvpnstart route-pre-down\n"
            "               to run Tunnelblick's client.route-pre-down.tunnelblick script\n\n"
            
			"./openvpnstart route-pre-down-k\n"
			"               to run Tunnelblick's client.route-pre-down.tunnelblick script with the '-k' option\n\n"
			
            "./openvpnstart checkSignature\n"
            "               to verify the application's signature using codesign\n\n"
            
            "./openvpnstart deleteLogs\n"
            "               to delete all log files that have the OPENVPNSTART_NOT_WHEN_COMPUTER_STARTS bit set in the bitmask encoded in their filenames.\n\n"
            
			"./openvpnstart expectDisconnect flag\n"
			"               creates (flag = 1) or removes (flag = 0) the file /Library/Application Support/Tunnelblick/expect-disconnect.txt\n\n"
			
            "./openvpnstart loadKexts     [bitMask]\n"
            "               to load .tun and .tap kexts\n\n"
            
            "./openvpnstart unloadKexts   [bitMask]\n"
            "               to unload the .tun and .tap kexts\n\n"
            
            "./openvpnstart secureUpdate name\n"
            "               to secure the specified update folder in /Library/Application Support/Tunnelblick/Tblks.\n\n"
            
            "./openvpnstart down scriptNumber\n"
            "               to run Tunnelblick's scriptNumber down script\n\n"
            
            "./openvpnstart compareShadowCopy      displayName\n"
            "               to compare a private .ovpn, .conf, or .tblk with its secure (shadow) copy\n\n"
            
            "./openvpnstart safeUpdate      displayName\n"
            "               to do a safe update of a secure (shadow) copy of a .tblk from the private copy\n\n"
            
            "./openvpnstart safeUpdateTest      displayName     path\n"
            "               tests if a 'safeUpdate' of a secure (shadow) copy of a .tblk from the private copy can be done using the configuration\n\n"
            
            "./openvpnstart preDisconnect  configName  cfgLocCode\n\n"
            "               to run the pre-disconnect.sh script inside a .tblk.\n\n"
            
            "./openvpnstart deleteLog   configName   cfgLocCode\n"
            "               to delete all log files associated with the configuration\n\n"
            
            "./openvpnstart printSanitizedConfigurationFile   configName   cfgLocCode\n"
            "               to print a configuration file with inline data (such as the data within <cert>...</cert>) removed.\n\n"
            
            "./openvpnstart postDisconnect  configName  cfgLocCode\n\n"
            "               to run the post-disconnect.sh script inside a .tblk.\n\n"
            
            "./openvpnstart connected  configName  cfgLocCode\n\n"
            "               to run the connected.sh script inside a .tblk.\n\n"
            
            "./openvpnstart reconnecting  configName  cfgLocCode\n\n"
            "               to run the reconnecting.sh script inside a .tblk.\n\n"
            
            "./openvpnstart start  configName  mgtPort  [useScripts  [skipScrSec  [cfgLocCode  [noMonitor  [bitMask  [leasewatchOptions [openvpnVersion] ]]  ]  ]  ]  ]\n\n"
            "               to load the net.tunnelblick.tun and/or net.tunnelblick.tap kexts and start OpenVPN with the specified configuration file and options.\n"
            "               foo.tun kext will be unloaded before loading net.tunnelblick.tun, and foo.tap will be unloaded before loading net.tunnelblick.tap.\n\n"
            
            "Where:\n\n"
            
            "scriptNumber is an integer designating what down script to run. (0 = client.down.tunnelblick.sh; 1 = client.1.down.tunnelblick.sh, etc.\n\n"
            
            "processId  is the process ID of the openvpn process to kill\n\n"
            
            "configName is the name of the configuration file (a .conf or .ovpn file, or .tblk package)\n\n"
            
            "mgtPort    is the port number (1-65535) to use for managing the connection if bitMask bit 14 is 1 (i.e., from the GUI)\n"
            "           or 0 to use a free port (starting the search at port 1337) and create a log file encoding the configuration path and port number\n"
            "           or the port number (1-65535) to use a free port (starting the search at the specified port number) and create a log file encoding the configuration path and port number\n\n"
            
            "useScripts has four fields (weird, but backward compatible):\n"
            "           bit 0 is 0 to not run scripts when the tunnel goes up or down (scripts may still be used in the configuration file)\n"
            "                 or 1 to run scripts before connecting and after disconnecting (scripts in the configuration file will be ignored)\n"
            "                (The standard scripts are Tunnelblick.app/Contents/Resources/client.up.tunnelblick.sh & client.down.tunnelblick.sh,\n"
            "                 and client.route-pre-down.tunnelblick.sh if bits 2-7 are zero, but see the cfgLocCode option)\n"
            "           bit 1 is 0 to not use the 'openvpn-down-root.so' plugin\n"
            "                 or 1 to use the 'openvpn-down-root.so' plugin\n"
            "           bits 2-7 specify the script to use. If non-zero, they are converted to a digit, N, used as an added extension to the script file\n"
            "                    name, just before 'nomonitor' if it appears, otherwise just before '.up' or '.down'.\n\n"
            "           bits 8-11 specify the OpenVPN --verb level to set. If bits 8...11 == 12 (0x0C), the verb level is not set\n"
            "                     Note: bits 8-11 are ignored and the --verb level is set to 0 if logging is disabled in bitMask.\n\n"
            "           Examples: useScripts=1 means use client.up.tunnelblick.sh, client.down.tunnelblick.sh, and client.route-pre-down.tunnelblick.sh\n"
            "                     useScripts=3 means use client.up.osx.sh, client.down.osx.sh, and the 'openvpn-down-root.so' plugin "
            "                     useScripts=5 means use client.1.up.osx.sh and client.1.down.osx.sh\n"
            "                     useScripts=9 means use client.2.up.osx.sh and client.2.down.osx.sh\n"
            
            "skipScrSec is 1 to skip sending a '--script-security 2' argument to OpenVPN (versions before 2.1_rc9 don't implement it).\n\n"
            
            "cfgLocCode is 0 to use the standard folder (~/Library/Application Support/Tunnelblick/Configurations) for configuration and other files,\n"
            "              0 is no longer an accepted value. Private configurations may not be used by openvpnstart\n"
            "           or 1 to use the alternate folder (/Library/Application Support/Tunnelblick/Users/<username>)\n"
            "                for configuration files and the standard folder for other files,\n"
            "           or 2 to use the Deploy folder in Tunnelblick.app/Contents/Resources for configuration and other files,\n"
            "                and If 'useScripts' is not 0\n"
            "                    Then If .../Deploy/<configName>.up.sh   exists,           it is used instead of .../Resources/client.up.osx.sh,\n"
            "                     and If .../Deploy/<configName>.down.sh exists,           it is used instead of .../Resources/client.down.osx.sh\n"
            "                     and If .../Deploy/<configName>.route-pre-down.sh exists, it is used instead of .../Resources/client.route-pre-down.tunnelblick.sh\n"
            "           or 3 to use /Library/Application Support/Tunnelblick/Shared\n\n"
            
            "noMonitor  is 0 to monitor the connection for interface configuration changes\n"
            "           or 1 to not monitor the connection for interface configuration changes\n\n"
            
            "bitMask    contains a mask: bit  0 is 1 to unload/load net.tunnelblick.tun (bit 0 is the lowest ordered bit)\n"
            "                            bit  1 is 1 to unload/load net.tunnelblick.tap\n"
            "                            bit  2 is 1 to unload foo.tun\n"
            "                            bit  3 is 1 to unload foo.tap\n"
            "                            bit  4 is 1 to restore settings on a reset of DNS  to pre-VPN settings (restarts connection otherwise)\n"
            "                            bit  5 is 1 to restore settings on a reset of WINS to pre-VPN settings (restarts connection otherwise)\n"
            "                            bit  6 is 1 to indicate a TAP connection is being made; 0 to indicate a TUN connection is being made\n"
            "                            bit  7 is 1 to indicate the domain name should be prepended to the search domains if search domains are not set manually\n"
            "                            bit  8 is 1 to indicate the DNS cache should be flushed after each connection or disconnection\n"
            "                            bit  9 is 1 to indicate the 'redirect-gateway def1' option should be passed to OpenVPN\n"
            "                            bit 10 is 1 to indicate the primary interface should be reset after disconnect (via ifconfig up; ifconfig down)\n"
            "                            bit 11 is 1 to indicate the --mtu-test option should be added to the command line\n"
            "                            bit 12 is 1 to indicate that extra logging should be done by the up script\n"
            "                            bit 13 is 1 to indicate that the default domain ('openvpn') should not be used\n"
            "                            bit 14 is 1 to indicate that the program is not being started when the computer starts\n"
            "                            bit 15 is 1 to indicate that the up script should be started with --route-up instead of --up\n"
            "                            bit 16 is 1 to indicate that the up script should override manual network settings\n"
            "                            bit 17 is 1 to indicate that return from the 'up' script should be delayed until DHCP information has been received in a tap connection\n"
			"                            bit 18 is 1 to indicate that Internet access should not be waited for\n"
			"                            bit 19 is 1 to indicate that IPv6 should be enabled on TAP devices using DHCP\n"
            "                            bit 20 is 1 to indicate that IPv6 should be disabled in all enabled (active) network services for TUN connections\n"
			"                            bit 21 is 1 to indicate that logging should be disabled\n"
			"                            bit 22 is 1 to indicate that network access should be disabled after disconnecting\n"
            "                            Note: Bits 2 and 3 are ignored by the start subcommand (for which foo.tun and foo.tap are unloaded only as needed)\n\n"

            "leasewatchOptions is a string containing characters indicating options for leasewatch.\n\n"
            
            "           If the string starts with '-i', the leasewatch script will be used to monitor network settings.\n"
            "           in which case, it may be followed by any of the following characters in any order:\n"
            "           d - ignore Domain\n"
            "           a - ignore DomainAddresses\n"
            "           s - ignore SearchDomains\n"
            "           n - ignore NetBIOSName\n"
            "           g - ignore Workgroup\n"
            "           w - ignore WINSAddresses\n\n"
            
            "           If the string starts with '-p', the process-network-changes binary will be used to monitor network settings,\n"
            "           in which case, it may be followed by:\n"
            "                     a 't' followed by any of the following characters to restart for the corresponding change,\n"
            "              and/or a 'r' followed by any of the following characters to restore the post-VPN value for the corresponding change \n"
            "                     d - Domain changed to its pre-VPN value\n"
            "                     a - DomainAddresses changed to its pre-VPN value\n"
            "                     s - SearchDomains changed to its pre-VPN value\n"
            "                     n - NetBIOSName changed to its pre-VPN value\n"
            "                     g - Workgroup changed to some other value\n"
            "                     w - WINSAddresses changed to its pre-VPN value\n\n"
            "                     D - Domain changed to some other value\n"
            "                     A - DomainAddresses changed to some other value\n"
            "                     S - SearchDomains changed to some otherN value\n"
            "                     N - NetBIOSName changed to some other value\n"
            "                     G - Workgroup changed to some other value\n"
            "                     W - WINSAddresses changed to some other value\n\n"
            
            "openvpnVersion is a string with the name of the subfolder of /Applications/Tunnelblick.app/Contents/Resources/openvpn\n"
            "               that contains the openvpn and openvpn-down-root.so binaries to be used for the connection. The string may\n"
            "               contain only lower-case letters, hyphen, underscore, period, and the digits 0-9.\n"
            "               If not present, the lowest (in lexicographical order) subfolder of openvpn will be used.\n"
            
            "useScripts, skipScrSec, cfgLocCode, and noMonitor each default to 0.\n"
            "bitMask defaults to 0x03.\n\n"
            
            "If the configuration file's extension is '.tblk', the package is searched for the configuration file, and the OpenVPN '--cd'\n"
            "option is set to the path of the configuration's /Contents/Resources folder.\n\n"
            
            "The normal return code is 0. If an error occurs a message is sent to stderr and a non-zero value is returned.\n\n"
            
            "This executable, openvpn, tap.kext, and tun.kext (and client.up.osx.sh and client.down.osx.sh if they are used)\n"
            "must all be located in /Library/Application Support/Tunnelblick/bin/.\n\n"
            
            "Tunnelblick must have been installed before openvpnstart can be used.\n\n"
            
            "For more information on using Deploy, see the Deployment wiki at https://tunnelblick.net/cCusDeployed.html\n"
            , killStringC, killAllStringC);
    exitOpenvpnstart(OPENVPNSTART_RETURN_SYNTAX_ERROR);      // This exit code is used in the VPNConnection connect: method to inhibit display of this long syntax error message because it means there is an internal Tunnelblick error
}

void becomeRoot(NSString * reason) {
	// Returns as root; complains and exits if can't become root
    // Nests properly, so after "becomeRoot, becomeRoot, stopBeingRoot" are still root until stopBeingRoot is called again

	uid_t uidBefore  = getuid();
	uid_t euidBefore = geteuid();
    
    gPendingRootCounter++;

	if (   (uidBefore  == 0)
		&& (euidBefore == 0)  ) {
		
		// Are root already
		return;
	}
    
    // Not root yet
    if (   (uidBefore  != 0)
        || (euidBefore != gUidOfUser)  ) {
        fprintf(stderr, "becomeRoot (%s) Not root and not non-root: getuid() = %d; geteuid() = %d; gUidOfUser = %d\n",
                [reason UTF8String], uidBefore, euidBefore, gUidOfUser);
        exitOpenvpnstart(204);
    }
    
    int result = seteuid(0);
    
    if (  result != 0  ) {
        fprintf(stderr, "Unable to becomeRoot (%s): seteuid(0) returned %d. getuid() = %d; geteuid() = %d; prior getuid() = %d; prior geteuid() = %d; gUidOfUser = %d\n",
                [reason UTF8String], result, getuid(), geteuid(), uidBefore, euidBefore, gUidOfUser);
        exitOpenvpnstart(204);
    }
    
    if (   (getuid()  != 0)
        || (geteuid() != 0)  ) {
        fprintf(stderr, "Unable to becomeRoot (%s): seteuid(0) returned %d but getuid() = %d; geteuid() = %d; prior getuid() = %d; prior geteuid() = %d; gUidOfUser = %d\n",
                [reason UTF8String], result, getuid(), geteuid(), uidBefore, euidBefore, gUidOfUser);
        exitOpenvpnstart(197);
    }
}

void stopBeingRoot(void) {
	// Returns as the original user; complains and exits if can't
    
	uid_t uidBefore  = getuid();
	uid_t euidBefore = geteuid();
	
    if (  gPendingRootCounter < 1  ) {
        fprintf(stderr, "Unable to stopBeingRoot because gPendingRootCounter = %d. getuid() = %d; geteuid() = %d; gUidOfUser = %d\n",
                gPendingRootCounter, uidBefore, euidBefore, gUidOfUser);
        exitOpenvpnstart(192);
    }
    
    gPendingRootCounter--;

	if (   (uidBefore == 0)
		&& (euidBefore == 0)  ) {
        
        // Are root
        
        // If we were root _before_ the last call to becomeRoot, do nothing
        if (  gPendingRootCounter > 0  ) {
            return;
        }
        
		int result = setuid(0);
		if (  result < 0  ) {
			fprintf(stderr, "Unable to stopBeingRoot: setuid(0) returned %d; getuid() = %d; geteuid() = %d; prior getuid() = %d; prior geteuid() = %d; gUidOfUser = %d\n",
					result, getuid(), geteuid(), uidBefore, euidBefore, gUidOfUser);
			exitOpenvpnstart(206);
		}
		
		result = seteuid(gUidOfUser);
		if (  result < 0  ) {
			fprintf(stderr, "Unable to stopBeingRoot: seteuid(%d) returned %d; getuid() = %d; geteuid() = %d; prior getuid() = %d; prior geteuid() = %d\n",
					gUidOfUser, result, getuid(), geteuid(), uidBefore, euidBefore);
			exitOpenvpnstart(191);
		}
        
        if (   (getuid()  != 0)
            || (geteuid() != gUidOfUser)  ) {
            fprintf(stderr, "Unable to stopBeingRoot: after setuid(0) then seteuid(%d): getuid() = %d; geteuid() = %d; prior getuid() = %d; prior geteuid() = %d\n",
                    gUidOfUser, getuid(), geteuid(), uidBefore, euidBefore);
            exitOpenvpnstart(196);
        }
    } else {
        
        // Are not root
        fprintf(stderr, "Unable to stopBeingRoot because already are not root: getuid() = %d; geteuid() = %d; prior getuid() = %d; prior geteuid() = %d; gUidOfUser = %d\n",
                getuid(), geteuid(), uidBefore, euidBefore, gUidOfUser);
        exitOpenvpnstart(207);
    }
}

void becomeRootToAccessPath(NSString * path, NSString * reason) {
    if (   (   [path hasPrefix: L_AS_T_USERS]
            && (  [path length] > [L_AS_T_USERS length]  )  )
        || ([path rangeOfString: @".tblk/"].location != NSNotFound) ) {
        becomeRoot(reason);
    }
}

void stopBeingRootToAccessPath(NSString * path) {
    if (   (   [path hasPrefix: L_AS_T_USERS]
            && (  [path length] > [L_AS_T_USERS length]  )  )
        || ([path rangeOfString: @".tblk/"].location != NSNotFound)  ) {
        stopBeingRoot();
    }
}

BOOL fileExistsForRootAtPath(NSString * path) {
    BOOL isDir;
    becomeRootToAccessPath(path, [NSString stringWithFormat: @"check file exists: %@", [path lastPathComponent]]);
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath: path isDirectory: &isDir];
    stopBeingRootToAccessPath(path);
    if (   exists
        && isDir  ) {
        fprintf(stderr, "Must not be a directory: %s", [path UTF8String]);
        exitOpenvpnstart(198);
    }
    return exists;
}

BOOL folderExistsForRootAtPath(NSString * path) {
    BOOL isDir;
    becomeRootToAccessPath(path, [NSString stringWithFormat: @"check folder exists: %@", [path lastPathComponent]]);
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath: path isDirectory: &isDir];
    stopBeingRootToAccessPath(path);
    if (   exists
        && ( ! isDir)  ) {
        fprintf(stderr, "Must be a directory: %s", [path UTF8String]);
        exitOpenvpnstart(190);
    }
    return exists;
}

const char * fileSystemRepresentation(NSString * path) {
    
    if (  ! path  ) {
        fprintf(stderr, "Called fileSystemRepresentation with a nil argument");
        exitOpenvpnstart(180);
    }
    
    // The NSString "fileSystemRepresentation" method throws an exception if the path is empty or has characters that can’t be
    // represented in the file system’s encoding, so we catch that exception here and fail.
    
    const char * fsr = NULL;
    
    @try {
        fsr = [path fileSystemRepresentation];
    }
    @catch (NSException * e) {
        NSString * msg = [NSString stringWithFormat: @"Exception occured in fileSystemRepresentation('%@'): %@\n", path, e];
        fprintf(stderr, "%s\n", [msg UTF8String]);
        exitOpenvpnstart(181);
    }
    
    return fsr;
}

BOOL isOnNosuidVolume(NSString * path) {
    
    const char * pathC = fileSystemRepresentation(path);
    struct statfs stats_buf;
    if (  0 == statfs(pathC, &stats_buf)  ) {
        if (  (stats_buf.f_flags & MNT_NOSUID) != 0  ) {
            fprintf(stderr, "%s is on a NOSUID volume\n", pathC);
            return TRUE;
        }
    } else {
        fprintf(stderr, "statfs on %s failed; cannot check if volume is NOSUID\nError was %ld: '%s'\n", pathC, (unsigned long)errno, strerror(errno));
        return TRUE;
    }
    
    return FALSE;
}

//**************************************************************************************************************************

BOOL pathComponentIsNotSecure(NSString * path, mode_t permissionsIfNot002) {
	
	static NSMutableArray * secureComponentsCache = nil;  // cache containing components known to be secure
    //                                                    // entries are strings: "permissionsIfNot002;path"
	
	const char * pathC = fileSystemRepresentation(path);  // (Do some sanity checking on the path and make it easy to fprint as a %s)
    
	NSString * cacheString = [NSString stringWithFormat: @"%ld;%@", (unsigned long) permissionsIfNot002, path];
	
	if (  ! secureComponentsCache  ) {
		secureComponentsCache = [[NSMutableArray alloc] initWithCapacity: 100]; // Never dealloc this
	} else if (  [secureComponentsCache containsObject: cacheString] ) {
		return NO;
	}
	
    becomeRootToAccessPath(path, [NSString stringWithFormat: @"check path component secure: %@", path]);
    BOOL nosuid = isOnNosuidVolume(path);
    NSDictionary * attributes = [[NSFileManager defaultManager] tbFileAttributesAtPath: path traverseLink: NO];
    stopBeingRootToAccessPath(path);
    
    if (  nosuid  ) {
        return YES;
    }
    
    if (  ! attributes  ) {
        fprintf(stderr, "%s does not have attributes (!)\nError was: %s\n", pathC, strerror(errno));
        return YES;
    }
    
    if (  [attributes fileType] == NSFileTypeSymbolicLink  ) {
        fprintf(stderr, "%s is a symlink\n", pathC);
        return YES;
    }
    
    unsigned long owner = [[attributes objectForKey: NSFileOwnerAccountID] unsignedLongValue];
    if (  owner != 0  ) {
        fprintf(stderr, "%s owner is %ld, not 0\n", pathC, owner);
        return YES;
    }
    
    unsigned long groupOwner = [[attributes objectForKey: NSFileGroupOwnerAccountID] unsignedLongValue];
    if (   (groupOwner != 0)
		&& (groupOwner != ADMIN_GROUP_ID)  ) {
        fprintf(stderr, "%s group owner is %ld, not 0 or %ld\n", pathC, groupOwner, (long) ADMIN_GROUP_ID);
        return YES;
    }
    
    mode_t perms = (mode_t) [[attributes objectForKey: NSFilePosixPermissions] shortValue];
    if (  permissionsIfNot002 == 0  ) {
        if (  (perms & S_IWOTH) != 0   ) {
            fprintf(stderr, "%s is writable by other (permissions = 0%lo)\n", pathC, (long) perms);
            return YES;
        }
    } else {
        if (   (perms != permissionsIfNot002)
			&& (   (permissionsIfNot002 != 0755) // On OS X 10.4, kextload/kextunload permissions are 0555 instead of 0755
				|| (perms != 0555)               // On OS X 10.7 & lower, killall permissions are 0555 instead of 0755
				|| (   ( ! [[path lastPathComponent] isEqualToString: @"kextload"  ] )
					&& ( ! [[path lastPathComponent] isEqualToString: @"kextunload"] )
					&& ( ! [[path lastPathComponent] isEqualToString: @"killall"   ] )
					)
				)
			) {
            fprintf(stderr, "%s permissions are 0%lo; they should be 0%lo\n", pathC, (long) perms, (long) permissionsIfNot002);
            return YES;
        }
    }
    
/* Too much variation to implement these (for now) MAY NEED becomeRoot/stopBeingRoot
 
    const char namebuff[1000];
    size_t size = sizeof(namebuff);
    size_t resultSize = listxattr(pathC, (char *) namebuff, size, XATTR_NOFOLLOW);
    if (  resultSize != 0  ) {
        NSMutableString * extendedAtts = [NSMutableString stringWithCapacity: size*2];
        char * p = (char *) namebuff;
        while (  (unsigned long) p < resultSize) {
            [extendedAtts appendFormat: @"\n%s", p];
            p += strlen(p)+1;
        }
        fprintf(stderr, "%s has the following extended attributes:%s\n", pathC, [extendedAtts UTF8String]);
        return YES;  // has extended attributes
    }
    
    acl_t acl = acl_get_file(pathC, ACL_TYPE_EXTENDED);
    if (  acl == (acl_t)NULL  ) {
        fprintf(stderr, "%s is secure\n", pathC);
        return YES;
    }
    char * aclText = acl_to_text(acl, NULL);
    if (  strcmp(aclText, "0: group:everyone deny delete") != 0  ) {
        fprintf(stderr, "%s has the following ACL:\n%s\n", pathC, aclText);
        if (  acl_free(acl)  ) {
            fprintf(stderr, "acl_free returned a non-zero result\n");
        }
        return YES; // has unrecognized ACL
    }
    if (  acl_free(acl)  ) {
        fprintf(stderr, "acl_free returned a non-zero result\n");
        return YES;
    }
 */
    
	[secureComponentsCache addObject: cacheString];
    return NO;
}

BOOL pathIsNotSecure(NSString * path, mode_t terminusPermissions) {
    
    becomeRootToAccessPath(path, [NSString stringWithFormat: @"check for noSuid: %@", path]);
    BOOL noSuid = isOnNosuidVolume(path);
    stopBeingRootToAccessPath(path);
    
    if (  noSuid  ) {
        return YES;
    }
    
#ifdef TBDebug
	if (  [path hasPrefix: [gResourcesPath stringByAppendingString: @"/"]]  ) {
		// Debugging and path is within the app
		// Verify only that the path itself is secure: owned by root:wheel with no user write permissions
        if (  pathComponentIsNotSecure(path, terminusPermissions)  ) {
			fprintf(stderr, "pathIsNotSecure: pathComponentIsNotSecure(%s, 0%lo)\n",
					[path UTF8String],
					(long) terminusPermissions);
            return YES;
        }
		
		return NO;	// the path itself is secure (but perhaps not ancestors)
	}
	
	// Debugging, but not within the app, so fall through to do full testing 
#endif
    
    // Verify that the path is secure: it and all ancestors are owned by root:wheel with no user write permissions
    NSArray  * pathComponents = [path componentsSeparatedByString: @"/"];
	
    unsigned nComponents = [pathComponents count];
    if (  nComponents == 0  ) {
		fprintf(stderr, "pathIsNotSecure: nComponents == 0\n");
        return YES;
    }
    
    if (  ! [[pathComponents objectAtIndex: 0] isEqualToString: @""]  ) {
		fprintf(stderr, "pathIsNotSecure: 1st component != '/'\n%s\n", [[pathComponents objectAtIndex: 0] UTF8String]);
        return YES;
    }
    
    NSMutableString * pathSoFar = [NSMutableString stringWithCapacity: [path length]];
    unsigned i;
    for (i=1; i<nComponents; i++) {
        [pathSoFar appendFormat: @"/%@", [pathComponents objectAtIndex: i]];
        if (  pathComponentIsNotSecure(pathSoFar,
                                       (i == (nComponents - 1))
                                       ? terminusPermissions
                                       : 0)  ) {
			fprintf(stderr, "pathIsNotSecure: pathComponentIsNotSecure(%s, 0%lo)\n",
					[pathSoFar UTF8String],
					(i == (nComponents - 1))
					? (long) terminusPermissions
					: 0L);
            return YES;
        }
    }
    
    return  NO;
}

void exitIfPathIsNotSecure(NSString * path, mode_t permissions, OSStatus statusToReturnIfNotSecure) {
    if (  pathIsNotSecure(path, permissions)  ) {
        fprintf(stderr, "%s is not secured\n", [path UTF8String]);
        exitOpenvpnstart(statusToReturnIfNotSecure);
    }
}

void exitIfNotRootWithPermissions(NSString * fPath, mode_t permsShouldHave) {
	// Exits if file doesn't exist, or does not have the specified ownership and permissions
	
    becomeRootToAccessPath(fPath, [NSString stringWithFormat: @"check for noSuid: %@", fPath]);
    BOOL noSuid = isOnNosuidVolume(fPath);
    stopBeingRootToAccessPath(fPath);
    
    if (  noSuid  ) {
        exitOpenvpnstart(182);
    }

    if (  ! fileExistsForRootAtPath(fPath)  ) {
        fprintf(stderr, "File does not exist: %s", [fPath UTF8String]);
        exitOpenvpnstart(200);
    }
    
    becomeRootToAccessPath(fPath, [NSString stringWithFormat: @"check ownership/permissions of %@", [fPath lastPathComponent]]);
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] tbFileAttributesAtPath:fPath traverseLink:YES];
    stopBeingRootToAccessPath(fPath);
    
    unsigned long perms     =  [fileAttributes filePosixPermissions];
    unsigned long fileOwner = [[fileAttributes fileOwnerAccountID]      unsignedLongValue];
    unsigned long fileGroup = [[fileAttributes fileGroupOwnerAccountID] unsignedLongValue];
    
    if (   (perms == (unsigned long) permsShouldHave)
        && (fileOwner == 0UL)
        && (fileGroup == 0UL)  ) {
        return;
    }
    
    fprintf(stderr, "File %s has permissions: 0%lo and is owned by %ld:%ld and should have permissions 0%lo and be owned by 0:0\n",
            [fPath UTF8String],
            perms, fileOwner, fileGroup,
            (long) permsShouldHave);
    exitOpenvpnstart(201);
}

void exitIfTblkNeedsRepair(void) {
    // There is a SIMILAR function in MenuController: needToSecureFolderAtPath
    //
    // There is a SIMILAR function in sharedRoutines: secureOneFolder, that SECURES a folder and can be used on a .tblk
    //
    ////////
    // NOTES: THIS ROUTINE DOES NOT DEAL WITH PRIVATE CONFIGURATIONS, since you can't connect them
    //        THIS ROUTINE DOES NOT DEAL WIth forced-preferences.plist or .executable files, since they can't appear inside a .tblk that can be connected
    ////////
    
    // If it isn't an existing folder, then it can't be secured!
    if (  ! folderExistsForRootAtPath(gConfigPath)  ) {
        fprintf(stderr, "Configuration file does not exist: %s", [gConfigPath UTF8String]);
        exitOpenvpnstart(202);
    }
    
    // Permissions:
    mode_t folderPerms         = PERMS_SECURED_FOLDER;
    mode_t scriptPerms         = PERMS_SECURED_SCRIPT;
    mode_t publicReadablePerms = PERMS_SECURED_READABLE;
    mode_t otherPerms          = PERMS_SECURED_OTHER;
    
    exitIfPathIsNotSecure(gConfigPath, folderPerms, OPENVPNSTART_RETURN_CONFIG_NOT_SECURED_ERROR);
    
    becomeRootToAccessPath(gConfigPath, [NSString stringWithFormat: @"check if needs repair: %@", [gConfigPath lastPathComponent]]);
    
    NSString * file;
    NSDirectoryEnumerator * dirEnum = [[NSFileManager defaultManager] enumeratorAtPath: gConfigPath];
    BOOL isDir;
	
    while (  (file = [dirEnum nextObject])  ) {
        NSString * filePath = [gConfigPath stringByAppendingPathComponent: file];
        NSString * ext = [file pathExtension];
        
        if (   [[NSFileManager defaultManager] fileExistsAtPath: filePath isDirectory: &isDir]
            && isDir  ) {
            
            exitIfPathIsNotSecure(filePath, folderPerms, OPENVPNSTART_RETURN_CONFIG_NOT_SECURED_ERROR);
            
        } else if ( [ext isEqualToString:@"sh"]  ) {
            exitIfPathIsNotSecure(filePath, scriptPerms, OPENVPNSTART_RETURN_CONFIG_NOT_SECURED_ERROR);
            
        } else if (   [ext isEqualToString: @"strings"]
                   || [[file lastPathComponent] isEqualToString:@"Info.plist"]  ) {
            exitIfPathIsNotSecure(filePath, publicReadablePerms, OPENVPNSTART_RETURN_CONFIG_NOT_SECURED_ERROR);
            
        } else {
            exitIfPathIsNotSecure(filePath, otherPerms, OPENVPNSTART_RETURN_CONFIG_NOT_SECURED_ERROR);
        }
    }
    
    stopBeingRootToAccessPath(gConfigPath);
}

void exitIfOvpnNeedsRepair(void) {
    // If it isn't an existing file, then it can't be secured!
    if (  ! fileExistsForRootAtPath(gConfigPath)  ) {
        fprintf(stderr, "Configuration file does not exist: %s", [gConfigPath UTF8String]);
        exitOpenvpnstart(203);
    }
    
    exitIfPathIsNotSecure(gConfigPath, PERMS_SECURED_OTHER, OPENVPNSTART_RETURN_CONFIG_NOT_SECURED_ERROR);
}

void exitIfPathShouldNotBeRunAsRoot(NSString * path) {
    
    // We allow only certain programs to be run as root. These are:
    //    * Scripts and copies of OpenVPN built into Tunnelblick
    //    * Certain system programs such as kextload and dsacacheutil
    //    * User-supplied scripts inside a .tblk that is located in a shared, deployed, or shandow configuration folder
    //
    // This routine only checks the path string itself. It does not verify there are no symlinks
#ifdef TBDebug
    return;
#endif
    
    BOOL notOk = TRUE;
	
	if (  ! [path isEqualToString: @"INVALID"]  ) {

		if (  [path hasPrefix: @"/A"]  ) {
            NSArray  * pathComponents = [path pathComponents];
            if (   (   [[pathComponents objectAtIndex: 0] isEqualToString: @"/"]
                    && [[pathComponents objectAtIndex: 1] isEqualToString: @"Applications"]
                    && [[pathComponents objectAtIndex: 2] isEqualToString: @"Tunnelblick.app"]
                    && [[pathComponents objectAtIndex: 3] isEqualToString: @"Contents"]
                    && [[pathComponents objectAtIndex: 4] isEqualToString: @"Resources"]
                    && (   (   ([pathComponents count] == 8)
                            && [[pathComponents objectAtIndex: 5] isEqualToString: @"openvpn"]
                            && [[pathComponents objectAtIndex: 6] hasPrefix:       @"openvpn-"]
                            && [[pathComponents objectAtIndex: 7] isEqualToString: @"openvpn"]
                            )
                        || (   ([pathComponents count] == 6)
                            && (   [[pathComponents objectAtIndex: 5] isEqualToString: @"client.down.tunnelblick.sh"]
                                || [[pathComponents objectAtIndex: 5] isEqualToString: @"client.1.down.tunnelblick.sh"]
                                || [[pathComponents objectAtIndex: 5] isEqualToString: @"client.2.down.tunnelblick.sh"]
                                || [[pathComponents objectAtIndex: 5] isEqualToString: @"client.3.down.tunnelblick.sh"]
                                || [[pathComponents objectAtIndex: 5] isEqualToString: @"client.route-pre-down.tunnelblick.sh"]
                                || [[pathComponents objectAtIndex: 5] isEqualToString: @"re-enable-network-services.sh"]
                                )
                            )
                        )
                    )
                ) {
                notOk = FALSE;
            }

		} else if (  [path hasPrefix: @"/s"]  ) {
			if (   [path isEqualToString: TOOL_PATH_FOR_KEXTLOAD    ]
		   	 	|| [path isEqualToString: TOOL_PATH_FOR_KEXTUNLOAD  ]
			    ) {
                notOk = FALSE;
            }

		} else if (  [path hasPrefix: @"/u"]  ) {
			if (   [path isEqualToString: TOOL_PATH_FOR_ARCH     ]
                || [path isEqualToString: TOOL_PATH_FOR_CODESIGN ]
		   	 	|| [path isEqualToString: TOOL_PATH_FOR_KEXTSTAT ]
                || [path isEqualToString: TOOL_PATH_FOR_KILLALL  ]
			    ) {
                notOk = FALSE;
            }
			
		} else if (  [path hasPrefix: @"/L"]  ) {
            if (   (   [path hasSuffix: @".tblk/Contents/Resources/pre-connect.sh"      ]
					|| [path hasSuffix: @".tblk/Contents/Resources/pre-disconnect.sh"   ]
					|| [path hasSuffix: @".tblk/Contents/Resources/post-tun-tap-load.sh"]
					|| [path hasSuffix: @".tblk/Contents/Resources/connected.sh"        ]
					|| [path hasSuffix: @".tblk/Contents/Resources/reconnecting.sh"     ]
					|| [path hasSuffix: @".tblk/Contents/Resources/post-disconnect.sh"  ]
					)
				&& (   (   (gUidOfUser != 0)	// Allow alternate only if not root
						&& [path hasPrefix: [[L_AS_T_USERS
										  stringByAppendingPathComponent: gUserName]
										 stringByAppendingString: @"/"] ])
					|| [path hasPrefix: [L_AS_T_SHARED
										 stringByAppendingString: @"/"] ]
					|| [path hasPrefix: [gDeployPath
										 stringByAppendingString: @"/"] ]
					)  ) {
					notOk = FALSE;
				}
		}
	}
	
    if (  notOk  ) {
        fprintf(stderr, "Path %s may not be run as root\n", [path UTF8String]);
        exitOpenvpnstart(208);
    }
    
	if (  ! fileExistsForRootAtPath(path)  ) {
		fprintf(stderr, "File %s does not exist\n", [path UTF8String]);
		exitOpenvpnstart(209);
	}
}

//**************************************************************************************************************************
NSString * newTemporaryDirectoryPathInTunnelblickHelper(void) {
    // Code for creating a temporary directory from http://cocoawithlove.com/2009/07/temporary-files-and-folders-in-cocoa.html
    // Modified to check for malloc returning NULL, use strlcpy, use [NSFileManager defaultManager], and use more readable length for stringWithFileSystemRepresentation
    
    NSString   * tempDirectoryTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent: @"TunnelblickTemporaryDotTblk-XXXXXX"];
    const char * tempDirectoryTemplateCString = fileSystemRepresentation(tempDirectoryTemplate);
    
    size_t bufferLength = strlen(tempDirectoryTemplateCString) + 1;
    char * tempDirectoryNameCString = (char *) malloc( bufferLength );
    if (  ! tempDirectoryNameCString  ) {
        fprintf(stderr, "Unable to allocate memory for a temporary directory name\n");
        return nil;
    }
    
    strlcpy(tempDirectoryNameCString, tempDirectoryTemplateCString, bufferLength);
    
    char * dirPath = mkdtemp(tempDirectoryNameCString);
    
    if (  ! dirPath  ) {
        fprintf(stderr, "Unable to create a temporary directory\n");
        free(tempDirectoryNameCString);
        return nil;
    }
    
    NSString *tempFolder = [[NSFileManager defaultManager] stringWithFileSystemRepresentation: tempDirectoryNameCString
                                                                                       length: strlen(tempDirectoryNameCString)];
    free(tempDirectoryNameCString);
    
    return [tempFolder retain];
}

//**************************************************************************************************************************

int runAsRoot(NSString * thePath, NSArray * theArguments, mode_t permissions) {
	// Runs a program as root
	// Returns program's termination status
	
    exitIfPathShouldNotBeRunAsRoot(thePath);
    
    exitIfPathIsNotSecure(thePath, permissions, 210);
    
	NSTask * task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath:thePath];
	[task setArguments:theArguments];
	
    // Send stdout and stderr to temporary files, and read the files after the task completes
    NSString * dirPath = newTemporaryDirectoryPathInTunnelblickHelper();
    if (  ! dirPath  ) {
        fprintf(stderr, "runAsRoot: Failed to create temporary directory");
        return -1;
    }
    NSString * stdPath = [dirPath stringByAppendingPathComponent: @"runAsRootStdOut"];
    if (  [[NSFileManager defaultManager] fileExistsAtPath: stdPath]  ) {
        fprintf(stderr, "runAsRoot: File exists at %s", [stdPath UTF8String]);
        [dirPath release];
        return -1;
    }
    if (  ! [[NSFileManager defaultManager] createFileAtPath: stdPath contents: nil attributes: nil]  ) {
        fprintf(stderr, "runAsRoot: Unable to create %s", [stdPath UTF8String]);
        [dirPath release];
        return -1;
    }
    NSFileHandle * stdFileHandle = [[NSFileHandle fileHandleForWritingAtPath: stdPath] retain];
    if (  ! stdFileHandle  ) {
        fprintf(stderr, "runAsRoot: Unable to get NSFileHandle for %s", [stdPath UTF8String]);
        [dirPath release];
        return -1;
    }
    [task setStandardOutput: stdFileHandle];

    NSString * errPath = [dirPath stringByAppendingPathComponent: @"runAsRootErrOut"];
    if (  [[NSFileManager defaultManager] fileExistsAtPath: errPath]  ) {
        fprintf(stderr, "runAsRoot: File exists at %s", [errPath UTF8String]);
        [dirPath release];
		[stdFileHandle release];
        return -1;
    }
    if (  ! [[NSFileManager defaultManager] createFileAtPath: errPath contents: nil attributes: nil]  ) {
        fprintf(stderr, "runAsRoot: Unable to create %s", [errPath UTF8String]);
        [dirPath release];
		[stdFileHandle release];
        return -1;
    }
    NSFileHandle * errFileHandle = [[NSFileHandle fileHandleForWritingAtPath: errPath] retain];
    if (  ! errFileHandle  ) {
        fprintf(stderr, "runAsRoot: Unable to get NSFileHandle for %s", [errPath UTF8String]);
        [dirPath release];
		[stdFileHandle release];
        return -1;
    }
    [task setStandardError: errFileHandle];
    
    [task setCurrentDirectoryPath: @"/private/tmp"];
    
    [task setEnvironment: getSafeEnvironment()];
    
	becomeRoot([NSString stringWithFormat: @"launch %@", [thePath lastPathComponent]]);
    
	[task launch];
	[task waitUntilExit];
    stopBeingRoot();
	
    [stdFileHandle closeFile];
    [stdFileHandle release];
    [errFileHandle closeFile];
    [errFileHandle release];
    
    NSFileHandle * file = [NSFileHandle fileHandleForReadingAtPath: stdPath];
    NSData * stdData = [file readDataToEndOfFile];
    [file closeFile];
    file = [NSFileHandle fileHandleForReadingAtPath: errPath];
    NSData *errData = [file readDataToEndOfFile];
    [file closeFile];
	
    if (  ! [[NSFileManager defaultManager] tbRemoveFileAtPath: dirPath handler: nil]  ) {
        fprintf(stderr, "Unable to remove temporary folder at %s", [dirPath UTF8String]);
    }
    [dirPath release];

	NSCharacterSet * trimCharacterSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];

	NSString * stdOutput = [[[NSString alloc] initWithData: stdData encoding: NSUTF8StringEncoding] autorelease];
	if (  stdOutput == nil  ) {
		stdOutput = @"Unable to interpret stdout as UTF-8";
	}
    stdOutput = [stdOutput stringByTrimmingCharactersInSet: trimCharacterSet];
	if (  [stdOutput length] != 0  ) {
		fprintf(stderr, "stdout from %s: %s\n", [[thePath lastPathComponent] UTF8String], [stdOutput UTF8String]);
	}
	
	NSString * errOutput = [[[NSString alloc] initWithData: errData encoding: NSUTF8StringEncoding] autorelease];
	if (  errOutput == nil  ) {
		errOutput = @"Unable to interpret stderr as UTF-8";
	}
    errOutput = [errOutput stringByTrimmingCharactersInSet: trimCharacterSet];
	if (  [errOutput length] != 0  ) {
		fprintf(stderr, "stderr from %s: %s\n", [[thePath lastPathComponent] UTF8String], [errOutput UTF8String]);
	}
	
    return [task terminationStatus];
}

//**************************************************************************************************************************

void validateConfigName(NSString * name);
void validateCfgLocCode(unsigned cfgLocCode);

int runScript(NSString * scriptName, int argc, char * argv[]) {
	// Runs one of the following scripts: connected.sh, reconnecting.sh, or post-disconnect.sh
	// Exits on error; otherwise returns the exit code from the script
	
    if (  argc != 4  ) {
        printUsageMessageAndExitOpenvpnstart();
    }
    
    NSString * configName = [NSString stringWithUTF8String: argv[2]];
    unsigned   cfgLocCode =  cvt_atou(argv[3], @"cfgLogCode");
	validateConfigName(configName);
	validateCfgLocCode(cfgLocCode);
    
    if (  ! [configName hasSuffix: @".tblk"]  ) {
        fprintf(stderr, "Only a Tunnelblick VPN Configurations may run the %s script\n", [scriptName UTF8String]);
        exitOpenvpnstart(211);
    }
    
    NSString * configPrefix = nil;

    switch (cfgLocCode) {
        case CFG_LOC_PRIVATE:
            fprintf(stderr, "Invalid cfgLocCode (private not allowed)\n");
            exitOpenvpnstart(212);
            break;
            
        case CFG_LOC_ALTERNATE:
			if (  gUidOfUser == 0) {
				fprintf(stderr, "Invalid cfgLocCode (alternate configuration not allowed when running as root)\n");
				exitOpenvpnstart(195);
			}
            configPrefix = [L_AS_T_USERS stringByAppendingPathComponent: gUserName];
            break;
            
        case CFG_LOC_DEPLOY:
            configPrefix = [[gDeployPath copy] autorelease];
            break;
            
        case CFG_LOC_SHARED:
            configPrefix = L_AS_T_SHARED;
            break;
            
        default:
            fprintf(stderr, "Invalid cfgLocCode (%d)\n", cfgLocCode);
            exitOpenvpnstart(213);
    }
    
    int returnValue = 0;

    NSString * scriptPath = [[[[configPrefix stringByAppendingPathComponent: configName]
                               stringByAppendingPathComponent: @"Contents"]
                              stringByAppendingPathComponent: @"Resources"]
                             stringByAppendingPathComponent: scriptName];
	
	becomeRootToAccessPath(scriptPath, @"Check if script exists");
	BOOL scriptExists = [[NSFileManager defaultManager] fileExistsAtPath: scriptPath];
	stopBeingRootToAccessPath(scriptPath);

	if (  ! scriptExists  ) {
		fprintf(stdout, "No such script exists: %s\n", [scriptPath UTF8String]);
		return 0;
	}
	
    exitIfNotRootWithPermissions(scriptPath, PERMS_SECURED_SCRIPT);

    fprintf(stdout, "Executing %s in %s...\n", [[scriptPath lastPathComponent] UTF8String], [[scriptPath stringByDeletingLastPathComponent] UTF8String]);
    
    returnValue = runAsRoot(scriptPath, [NSArray array], PERMS_SECURED_SCRIPT);
    
    fprintf(stdout, "%s returned with status %d\n", [[scriptPath lastPathComponent] UTF8String], returnValue);
    
    return returnValue;
}

//**************************************************************************************************************************
int runDownScript(unsigned scriptNumber) {
    
    int returnValue = 0;
    
    NSString * scriptPath = [gResourcesPath stringByAppendingPathComponent:
                             (   scriptNumber == 0
                              ?  @"client.down.tunnelblick.sh"
                              : [NSString stringWithFormat: @"client.%d.down.tunnelblick.sh", scriptNumber])];
	
	becomeRootToAccessPath(scriptPath, @"Check if script exists");
	BOOL scriptExists = [[NSFileManager defaultManager] fileExistsAtPath: scriptPath];
	stopBeingRootToAccessPath(scriptPath);
    
	if (  scriptExists  ) {
        
        exitIfNotRootWithPermissions(scriptPath, 0744);
        
        fprintf(stdout, "Executing %s in %s...\n", [[scriptPath lastPathComponent] UTF8String], [[scriptPath stringByDeletingLastPathComponent] UTF8String]);
        returnValue = runAsRoot(scriptPath, [NSArray array], 0744);
        fprintf(stdout, "%s returned with status %d\n", [[scriptPath lastPathComponent] UTF8String], returnValue);
	
    } else {
        
		fprintf(stdout, "Down script #%d does not exist\n", scriptNumber);
		returnValue = 184;
    }
    
    exitOpenvpnstart(returnValue);
    return returnValue; // Avoid analyzer warnings
}

//**************************************************************************************************************************
int runReenableNetworkServices(void) {
    
	int returnValue = 0;
	
	NSString * scriptPath = [gResourcesPath stringByAppendingPathComponent: @"re-enable-network-services.sh"];
	
	becomeRootToAccessPath(scriptPath, @"Check if script exists");
	BOOL scriptExists = [[NSFileManager defaultManager] fileExistsAtPath: scriptPath];
	stopBeingRootToAccessPath(scriptPath);
	
	if (  scriptExists  ) {
		
		exitIfNotRootWithPermissions(scriptPath, 0744);
		
		fprintf(stdout, "Executing %s in %s...\n", [[scriptPath lastPathComponent] UTF8String], [[scriptPath stringByDeletingLastPathComponent] UTF8String]);
		returnValue = runAsRoot(scriptPath, [NSArray array], 0744);
		fprintf(stdout, "%s returned with status %d\n", [[scriptPath lastPathComponent] UTF8String], returnValue);
		
	} else {
		
		fprintf(stdout, "No such script exists: %s\n", [scriptPath UTF8String]);
		returnValue = 184;
	}
	
	exitOpenvpnstart(returnValue);
	return returnValue; // Avoid analyzer warnings
}

//**************************************************************************************************************************
int runRoutePreDownScript(BOOL kOption) {
    
	// Runs the route-pre-down script; includes a "-k" argument to disable network access if kOption is true.
	
    int returnValue = 0;
    
    NSString * scriptPath = [gResourcesPath stringByAppendingPathComponent: @"client.route-pre-down.tunnelblick.sh"];
	
	becomeRootToAccessPath(scriptPath, @"Check if script exists");
	BOOL scriptExists = [[NSFileManager defaultManager] fileExistsAtPath: scriptPath];
	stopBeingRootToAccessPath(scriptPath);
    
	if (  scriptExists  ) {
        
        exitIfNotRootWithPermissions(scriptPath, 0744);
        
        fprintf(stdout, "Executing %s%s in %s...\n", [[scriptPath lastPathComponent] UTF8String], (kOption ? " -k" : ""), [[scriptPath stringByDeletingLastPathComponent] UTF8String]);
		NSArray * arguments = (  kOption
							   ? [NSArray arrayWithObject: @"-k"]
							   : [NSArray array]);
        returnValue = runAsRoot(scriptPath, arguments, 0744);
        fprintf(stdout, "%s returned with status %d\n", [[scriptPath lastPathComponent] UTF8String], returnValue);
        
    } else {
        
		fprintf(stdout, "No such script exists: %s\n", [scriptPath UTF8String]);
		returnValue = 184;
    }
    
    exitOpenvpnstart(returnValue);
    return returnValue; // Avoid analyzer warnings
}

//**************************************************************************************************************************
int checkSignature(void) {
    
    if (  ! [[NSFileManager defaultManager] fileExistsAtPath: TOOL_PATH_FOR_CODESIGN]  ) {  // If codesign binary doesn't exist, complain and assume it is NOT valid
        fprintf(stdout, "Assuming digital signature invalid because '%s' does not exist", [TOOL_PATH_FOR_CODESIGN UTF8String]);
        exitOpenvpnstart(183);
    }
    
    NSString * appPath =[[gResourcesPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]; // Remove /Contents/Resources
    NSArray * arguments = [NSArray arrayWithObjects: @"-v", appPath, nil];
    mode_t permissionsForCodesign = 0755;
    int returnValue = runAsRoot(TOOL_PATH_FOR_CODESIGN, arguments, permissionsForCodesign);
    exitOpenvpnstart(returnValue);
    return returnValue; // Avoid analyzer warnings
}

NSString *escaped(NSString *string) {
	// Returns an escaped version of a string so it can be put after an --up or --down option in the OpenVPN command line
	
    if (  [string rangeOfString: @" "].length == 0  ) {
        return [[string copy] autorelease];
    } else {
        return [NSString stringWithFormat:@"\"%@\"", string];
    }
}

NSString * configPathFromTblkPath(NSString * path) {
	// Returns the path of the configuration file within a .tblk, or nil if there is no such configuration file
	
    NSString * cfgPath = [path stringByAppendingPathComponent:@"Contents/Resources/config.ovpn"];
    if (   fileExistsForRootAtPath(cfgPath)  ) {
        return cfgPath;
    }

    return nil;
}

NSString * openvpnToUsePath (NSString * openvpnFolderPath, NSString * openvpnVersion) {
	// Returns the path to the openvpn executable to be used.
	// Arguments are the path to ...Resources/Contents/openvpn" and the name of the version to be used.
    BOOL noSuchVersion = FALSE;
    NSString * openvpnPath;
    if (   openvpnVersion  
        && ( [openvpnVersion length] > 0 )
		&& ( ! [openvpnVersion isEqualToString: @"-"] )  ) {
        NSString * openvpnFolderName = [@"openvpn-" stringByAppendingString: openvpnVersion];
        openvpnPath = [[openvpnFolderPath stringByAppendingPathComponent: openvpnFolderName] // Folder with version to be used
                       stringByAppendingPathComponent: @"openvpn"];                        // openvpn binary
        BOOL isDir;
        if (   [[NSFileManager defaultManager] fileExistsAtPath: openvpnPath isDirectory: &isDir]
            && (! isDir)  ) {
            return openvpnPath;
        }
        
        noSuchVersion = TRUE;
    }
    
    // No version specified or highest version specified or not known; find the lowest and highest versions (in NSNumericSearch order)
    NSString * lowestDirSoFar = nil;
    NSString * highestDirSoFar = nil;
    NSString * dir;
    NSDirectoryEnumerator * dirEnum = [[NSFileManager defaultManager] enumeratorAtPath: openvpnFolderPath];
    while (  (dir = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        if (  [dir hasPrefix: @"openvpn-"]  ) {
            if (   ( ! lowestDirSoFar )
                || ( [dir compare: lowestDirSoFar options: NSNumericSearch] == NSOrderedAscending )  ) {
                lowestDirSoFar = dir;
            }
            if (   ( ! highestDirSoFar )
                || ( [dir compare: highestDirSoFar options: NSNumericSearch] == NSOrderedDescending )  ) {
                highestDirSoFar = dir;
            }
        }
    }
    
    if (  ! lowestDirSoFar  ) {
        fprintf(stderr, "%s does not have any versions of OpenVPN\n", [openvpnFolderPath UTF8String]);
        exitOpenvpnstart(214);
    }
	
	NSString * dirToUse = ([openvpnVersion isEqualToString: @"-"]
						   ? highestDirSoFar
						   : lowestDirSoFar);
    
    if (  noSuchVersion  ) {
        fprintf(stderr, "OpenVPN version '%s' is not included in this copy of Tunnelblick, using version %s.\n",
                [openvpnVersion UTF8String],
                [[lowestDirSoFar substringFromIndex: [@"openvpn-" length]] UTF8String]);
    }
    
    openvpnPath = [[openvpnFolderPath stringByAppendingPathComponent: dirToUse] // Folder with version to be used
                   stringByAppendingPathComponent: @"openvpn"];                        // openvpn binary
    
    return openvpnPath;
}

NSString * TunTapSuffixToUse(void) {
    
    // Return tun/tap suffix appropriate for OS version:
    //        * Snow Leopard - Mountain Lion UNSIGNED 2011-11-01 version
    //        * Mavericks and higher           SIGNED current version
    
    NSString * suffixToReturn;

    OSStatus err;
    unsigned major, minor, bugFix;
    if (  EXIT_SUCCESS == (err = getSystemVersion(&major, &minor, &bugFix))  ) {
        if ( minor < 9) {
            suffixToReturn = @"-20111101.kext";
        } else {
            suffixToReturn = @"-signed.kext";
        }
    } else {
        fprintf(stderr, "Unable to determine OS version; using signed Tuntap kexts. Error status returned = %ld", (long) err);
        suffixToReturn = @"-signed.kext";
    }
    
    return suffixToReturn;
}

//**************************************************************************************************************************
int getProcesses(struct kinfo_proc** procs, unsigned * number) {
	//Fills in process information
	
	int					mib[4]	= { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct	kinfo_proc* info;
	size_t				length;
    unsigned			level	= 3;
    
    if (sysctl(mib, level, NULL, &length, NULL, 0) < 0) return -1;
    if (!(info = malloc(length))) return -1;
    if (sysctl(mib, level, info, &length, NULL, 0) < 0) {
        free(info);
        return -1;
    }
    
	*procs = info;
	*number = length / sizeof(struct kinfo_proc);
    return 0;
}

void secureUpdate(NSString * name) {
    
    // Secures an update in L_AS_T_TBLKS
    
    if (  ! [name containsOnlyCharactersInString: ALLOWED_DOMAIN_NAME_CHARACTERS @"_"]  ) {
        fprintf(stderr, "Invalid name for secureUpdate\n");
        exitOpenvpnstart(175);
    }
    
    NSString * path = [L_AS_T_TBLKS stringByAppendingPathComponent: name];
    BOOL isDir;
    if (  ! (   [[NSFileManager defaultManager] fileExistsAtPath: path isDirectory: &isDir]
             && isDir )  ) {
        fprintf(stderr, "Folder does not exist for secureUpdate\n");
        exitOpenvpnstart(176);
    }
    
	becomeRoot([NSString stringWithFormat: @"Secure %@", path]);
	BOOL ok = secureOneFolder(path, NO, 0);
	stopBeingRoot();
	
    if (  ! ok  ) {
        fprintf(stderr, "Folder could not be secured by secureUpdate\n");
        exitOpenvpnstart(177);
    }
}

void killOneOpenvpn(pid_t pid) {
    
	// Sends SIGTERM to the specified openvpn process, or complains and exits with an error
	
    if (  ! ALLOW_OPENVPNSTART_KILL  ) {
        fprintf(stderr, "The kill command is not allowed\n");
        exitOpenvpnstart(216);
    }
    
    unsigned count = 0;
    struct kinfo_proc * info = NULL;
    
    if (  getProcesses(&info, &count) == 0 ) {
        unsigned i;
        for (  i = 0; i < count; i++  ) {
            
            pid_t process_pid  = info[i].kp_proc.p_pid;
            if (  pid == process_pid  ) {
                
                char* process_name = info[i].kp_proc.p_comm;
                if (  strcmp(process_name, "openvpn") == 0  ) {
                    
                    free(info);
                    
                    becomeRoot(@"kill one specified OpenVPN process");
                    BOOL didKill = (  kill(pid, SIGTERM) == 0  );
                    stopBeingRoot();
                    
                    if (  didKill  ) {
                        return;
                    }
                    
                    if (  errno == ESRCH  ) {
                        fprintf(stderr, "killOneOpenvpn(%lu): kill() failed: Process does not exist\n", (unsigned long) pid);
                        exitOpenvpnstart(OPENVPNSTART_NO_SUCH_OPENVPN_PROCESS);
                    }
                    
                    fprintf(stderr, "killOneOpenvpn(%lu): kill() failed; errno %d: %s\n", (unsigned long) pid, errno, strerror(errno));
                    exitOpenvpnstart(218);
                }
            }
        }
        
        free(info);
        
        fprintf(stderr, "killOneOpenvpn(%lu): Process does not exist\n", (unsigned long) pid);
        exitOpenvpnstart(OPENVPNSTART_NO_SUCH_OPENVPN_PROCESS);
    } else {
        fprintf(stderr, "killOneOpenvpn(%lu): Unable to get process information via getProcesses()", (unsigned long) pid);
        exitOpenvpnstart(219);
    }
}

void killAllOpenvpn(void) {
	//Kills all processes named 'openvpn'
	
    if (  ! ALLOW_OPENVPNSTART_KILLALL  ) {
        fprintf(stderr, "The killall command is no longer allowed\n");
        exitOpenvpnstart(220);
    }
    
    NSArray  * arguments = [NSArray arrayWithObject: @"openvpn"];
    runAsRoot(TOOL_PATH_FOR_KILLALL, arguments, 0755);
}

//**************************************************************************************************************************
NSString * constructLogBase(NSString * configurationFile, unsigned cfgLocCode) {
    // Get a "standardized" path to the configuration file to construct the name of the log file
    // This standardized path is used only for constructing the name of the log file, and is NOT used as a path to get to anything.
    //
    // We use this standardized path to construct the name because scripts have access to the username, but don't have access to the
    // actual location of the home folder, and the home folder may be located in a non-standard location (on a remote volume for example).
    // So scripts can construct the name of the log file, and from that, the path to the log file, using only the username.
    //
    // For shadow copies or private configurations, the path is constructed from a "standardized" path to the private config file:
    //      /Users/_USERNAME_/Library/Application Support/Tunnelblick/Configurations/Folder/Subfolder/config.ovpn
    //
    // If the configuration file is a .tblk, the path to the actual configuration file inside it is used.
	
    NSString * configPrefix = nil;
    switch (cfgLocCode) {
        case CFG_LOC_PRIVATE:
        case CFG_LOC_ALTERNATE:
			if (  gUidOfUser == 0  ) {
				fprintf(stderr, "Invalid cfgLocCode (private or alternate configuration  but no user ID is avalable)\n");
				exitOpenvpnstart(194);
			}
			// THIS IS NOT USED AS A PATHNAME. SEE NOTE ABOVE.
            configPrefix = [NSString stringWithFormat: @"/Users/%@/Library/Application Support/Tunnelblick/Configurations", gUserName];
            break;
        case CFG_LOC_DEPLOY:
            configPrefix = [[gDeployPath copy] autorelease];
            break;
        case CFG_LOC_SHARED:
            configPrefix = L_AS_T_SHARED;
            break;
        default:
            fprintf(stderr, "Invalid cfgLocCode = %u\n", cfgLocCode);
            exit(EXIT_FAILURE);
    }
    
    NSMutableString * base = [[[configPrefix stringByAppendingPathComponent: configurationFile] mutableCopy] autorelease];
    if (  [[base pathExtension] isEqualToString: @"tblk"]  ) {
        [base appendString: @"/Contents/Resources/config.ovpn"];
    }
    
    [base replaceOccurrencesOfString: @"-" withString: @"--" options: 0 range: NSMakeRange(0, [base length])];
    [base replaceOccurrencesOfString: @"/" withString: @"-S" options: 0 range: NSMakeRange(0, [base length])];
	
    return [[base copy] autorelease];
}

NSString * constructOpenVPNLogPath(NSString * configurationFile, unsigned cfgLocCode, NSString * openvpnstartArgString, unsigned port) {
	// Returns a path for an OpenVPN log file.
	// It is composed of a prefix, the configuration path with "-" replaced by "--" and "/" replaced by "-S", and extensions of
	//      * an underscore-separated list of the values for useScripts, skipScrSec, cfgLocCode, noMonitor, and bitMask
	//      * the port number; and
	//      * "log"
	//
	// If the configuration file is in the home folder, we pretend it is in /Users/username instead (just for the purpose
	// of creating the filename -- we never try to access /Users/username...). We do this because
	// the scripts have access to the username, but don't have access to the actual location of the home folder, and the home
	// folder may be located in a non-standard location (on a remote volume for example).
	
    NSString * logBase = constructLogBase(configurationFile, cfgLocCode);
    NSString * returnVal = [NSString stringWithFormat: @"%@/%@.%@.%d.openvpn.log", L_AS_T_LOGS, logBase, openvpnstartArgString, port];
    return returnVal;
}

NSString * constructScriptLogPath(NSString * configurationFile, unsigned cfgLocCode) {
	// Returns a path for a script log file.
	// It is composed of a prefix, the configuration path with "-" replaced by "--" and "/" replaced by "-S", and an extension of "log"
	//
	// If the configuration file is in the home folder, we pretend it is in /Users/username instead (just for the purpose
	// of creating the filename -- we never try to access /Users/username...). We do this because
	// the scripts have access to the username, but don't have access to the actual location of the home folder, and the home
	// folder may be located in a non-standard location (on a remote volume for example).
	// It is composed of a prefix, the configuration path with "-" replaced by "--" and "/" replaced by "-S", and an extensions of "script.log"
	
    NSString * logBase = constructLogBase(configurationFile, cfgLocCode);
    NSString * returnVal = [NSString stringWithFormat: @"%@/%@.script.log", L_AS_T_LOGS, logBase];
    return returnVal;
}

NSString * createOpenVPNLog(NSString* configurationFile, unsigned cfgLocCode, unsigned port) {
	// Sets up the OpenVPN log file. The filename itself encodes the configuration file path, openvpnstart arguments, and port info.
	// The log file is created with permissions allowing everyone read/write access. (OpenVPN truncates the file, so the ownership and permissions are preserved.)
	
    NSString * logPath = constructOpenVPNLogPath(configurationFile, cfgLocCode, gStartArgs, port);
    NSDictionary * logAttributes = [NSDictionary dictionaryWithObject: [NSNumber numberWithUnsignedLong: 0666] forKey: NSFilePosixPermissions];
    
	becomeRoot(@"create OpenVPN log file");
    BOOL created = [[NSFileManager defaultManager] createFileAtPath: logPath contents: [NSData data] attributes: logAttributes];
    stopBeingRoot();
	
    if (  ! created  ) {
        NSString * msg = [NSString stringWithFormat: @"Warning: Failed to create OpenVPN log file at %@ with attributes %@", logPath, logAttributes];
        fprintf(stderr, "%s\n", [msg UTF8String]);
        exitOpenvpnstart(222);
    }
    
    return logPath;
}

NSString * createScriptLog(NSString* configurationFile, unsigned cfgLocCode) {
	// Sets up a new script log file. The filename itself encodes the configuration file path.
	// The log file is created with permissions allowing everyone read/write access
	
    NSString * logPath = constructScriptLogPath(configurationFile, cfgLocCode);
    NSDictionary * logAttributes = [NSDictionary dictionaryWithObject: [NSNumber numberWithUnsignedLong: 0666] forKey: NSFilePosixPermissions];

    NSCalendarDate * date = [NSCalendarDate date];
    NSString * dateCmdLine = [NSString stringWithFormat:@"%@ *Tunnelblick: openvpnstart starting OpenVPN\n",[date descriptionWithCalendarFormat:@"%a %b %e %H:%M:%S %Y"]];
    const char * bytes = [dateCmdLine UTF8String];
    NSData * dateCmdLineAsData = [NSData dataWithBytes: bytes length: strlen(bytes)];
    
	becomeRoot(@"create script log file");
    BOOL created = [[NSFileManager defaultManager] createFileAtPath: logPath contents: dateCmdLineAsData attributes: logAttributes];
    stopBeingRoot();
	
    if (  ! created  ) {
        NSString * msg = [NSString stringWithFormat: @"Failed to create scripts log file at %@ with attributes %@", logPath, logAttributes];
        fprintf(stderr, "%s\n", [msg UTF8String]);
    }
    
    return logPath;
}

void deleteAllLogFiles() {
	
	// Deletes all log files associated with OpenVPN log files that have the OPENVPNSTART_NOT_WHEN_COMPUTER_STARTS bit set in the bitmask encoded in their filenames
    // Also deletes all log files that have a "last modified" date earlier than one week ago
	
	// Make a list of filename prefixes for files that can be deleted
	NSMutableArray * prefixes = [NSMutableArray arrayWithCapacity: 10];
    NSString * filename;
    NSDirectoryEnumerator * dirEnum = [[NSFileManager defaultManager] enumeratorAtPath: L_AS_T_LOGS];
    while (  (filename = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
		
        // Add OpenVPN log files that have the "OPENVPNSTART_NOT_WHEN_COMPUTER_STARTS" bit set
		if (  [filename hasSuffix: @".openvpn.log"]  ) {
			NSString * withStartArgs = [[[filename stringByDeletingPathExtension]   // Remove .log
										 stringByDeletingPathExtension]				// Remove .openvpn
										stringByDeletingPathExtension];				// Remove port
			NSString * startArgsString = [withStartArgs pathExtension];
			NSArray * startArgs = [startArgsString componentsSeparatedByString: @"_"];
			if (  [startArgs count] != OPENVPNSTART_LOGNAME_ARG_COUNT  ) {
				fprintf(stderr, "Expected %lu encoded start arguments but found %lu in '%s' for OpenVPN log file %s\n",
						(unsigned long)[startArgs count], (unsigned long)OPENVPNSTART_LOGNAME_ARG_COUNT, [startArgsString UTF8String], [filename UTF8String]);
				exitOpenvpnstart(178);
			}
			unsigned bitMask = (unsigned)[[startArgs objectAtIndex: OPENVPNSTART_LOGNAME_ARG_BITMASK_IX] intValue];
			if (  0 != (bitMask & OPENVPNSTART_NOT_WHEN_COMPUTER_STARTS)  ) {
				NSString * prefix = [withStartArgs stringByDeletingPathExtension];    // Remove openvpnstartArgs
				[prefixes addObject: prefix];
			}
		}
        
        // Add any file that has not been modified in the last week
        NSString * fullPath = [L_AS_T_LOGS stringByAppendingPathComponent: filename];
        NSDictionary * dict = [[NSFileManager defaultManager] tbFileAttributesAtPath: fullPath traverseLink: NO];
        NSDate * modificationDate = [dict fileModificationDate];
        NSDate * oneWeekAgo = [NSDate dateWithTimeIntervalSinceNow: -7.0 * 24.0 * 60.0 * 60.0 ];
        NSComparisonResult result = [modificationDate compare: oneWeekAgo];
        if (  result == NSOrderedAscending  ) {
            [prefixes addObject: filename];
        }
	}
	
	// Delete all files that have one of those prefixes
	dirEnum = [[NSFileManager defaultManager] enumeratorAtPath: L_AS_T_LOGS];
    while (  (filename = [dirEnum nextObject])  ) {
		[dirEnum skipDescendents];
		
		// If filename is prefixed by one of the basenames, delete the file
		NSString * prefix;
		NSEnumerator * e = [prefixes objectEnumerator];
		while (  (prefix = [e nextObject])  ) {
			if (  [filename hasPrefix: prefix]  ) {
				NSString * fullPath = [L_AS_T_LOGS stringByAppendingPathComponent: filename];
				becomeRoot(@"delete a log file");
				BOOL ok = [[NSFileManager defaultManager] tbRemoveFileAtPath: fullPath handler: nil];
				stopBeingRoot();
				if (  ! ok  ) {
					fprintf(stderr, "Error occurred trying to delete log file %s\n", [fullPath UTF8String]);
				}
				continue;
			}
		}
	}
}

void deleteLogFiles(NSString * configurationFile, unsigned cfgLocCode) {
	// Deletes OpenVPN log files and script log files associated with a specified configuration file and location code
	
	becomeRoot(@"delete log files");
    
    // Delete ALL log files for the specified configuration file and location code
    NSString * logPath = constructScriptLogPath(configurationFile, cfgLocCode);
    NSString * logPathPrefix = [[logPath stringByDeletingPathExtension] stringByDeletingPathExtension];     // Remove .script.log
    
    NSString * filename;
    NSDirectoryEnumerator * dirEnum = [[NSFileManager defaultManager] enumeratorAtPath: L_AS_T_LOGS];
    while (  (filename = [dirEnum nextObject])  ) {
        [dirEnum skipDescendents];
        if (  [[filename pathExtension] isEqualToString: @"log"]  ) {
            NSString * oldFullPath = [L_AS_T_LOGS stringByAppendingPathComponent: filename];
            if (  [oldFullPath hasPrefix: logPathPrefix]  ) {
                if (  ! [[NSFileManager defaultManager] tbRemoveFileAtPath:oldFullPath handler: nil]  ) {
                    fprintf(stderr, "Error occurred trying to delete log file %s\n", [oldFullPath UTF8String]);
                }
            }
        }
    }
	
	stopBeingRoot();
}

void expectDisconnect(unsigned int flag) {
	
	if (  flag == 0  ) {
		becomeRoot(@"Delete expect-disconnect.txt");
		[[NSFileManager defaultManager] tbRemovePathIfItExists: L_AS_T_EXPECT_DISCONNECT_PATH];
		stopBeingRoot();
	} else if (  flag == 1  ) {
		becomeRoot(@"Create expect-disconnect.txt");
		if (  ! [[NSFileManager defaultManager] fileExistsAtPath:L_AS_T_EXPECT_DISCONNECT_PATH]  ) {
			[[NSFileManager defaultManager] createFileAtPath: L_AS_T_EXPECT_DISCONNECT_PATH contents: nil attributes: nil];
		}

		stopBeingRoot();
	}
}

//**************************************************************************************************************************

void compareShadowCopy (NSString * fileName) {
	// Compares the specified private configuration .tblk with its shadow copy.
	// Returns the results as one of the following result codes:
    //      OPENVPNSTART_COMPARE_CONFIG_SAME
    //      OPENVPNSTART_COMPARE_CONFIG_DIFFERENT
	
	if (  gUidOfUser == 0  ) {
		fprintf(stderr, "Invalid cfgLocCode (compareShadowCopy not allowed when running as root)\n");
		exitOpenvpnstart(193);
	}
	
    NSString * privatePrefix = [gUserHome stringByAppendingPathComponent:@"/Library/Application Support/Tunnelblick/Configurations"];
    NSString * shadowPrefix  = [L_AS_T_USERS stringByAppendingPathComponent: gUserName];
    
    NSString * privatePath = [[privatePrefix stringByAppendingPathComponent: fileName] stringByAppendingPathExtension: @"tblk"];
    NSString * shadowPath  = [[shadowPrefix  stringByAppendingPathComponent: fileName] stringByAppendingPathExtension: @"tblk"];
    
    if (  folderExistsForRootAtPath(privatePath)  ) {
        if (  folderExistsForRootAtPath(shadowPath)  ) {
            becomeRoot(@"check if config contents are equal");
            BOOL areEqual = [[NSFileManager defaultManager] contentsEqualAtPath: privatePath andPath: shadowPath];
            stopBeingRoot();
            if (  areEqual  ) {
                exitOpenvpnstart(OPENVPNSTART_COMPARE_CONFIG_SAME);
            }
		} else {
			fprintf(stderr, "Shadow configuration does not exist: %s", [shadowPath UTF8String]);
		}
	} else {
		fprintf(stderr, "Private configuration does not exist: %s", [privatePath UTF8String]);
	}
	
	exitOpenvpnstart(OPENVPNSTART_COMPARE_CONFIG_DIFFERENT);
}

void revertToShadow (NSString * fileName) {
	// Compares the specified private configuration .tblk with its shadow copy.
	// Returns the results as one of the following result codes:
    //      OPENVPNSTART_COMPARE_CONFIG_SAME
    //      OPENVPNSTART_COMPARE_CONFIG_DIFFERENT
	
	if (  gUidOfUser == 0  ) {
		fprintf(stderr, "Invalid cfgLocCode (revertToShadow not allowed when running as root)\n");
		exitOpenvpnstart(188);
	}
	
    NSString * privatePrefix = [gUserHome     stringByAppendingPathComponent: @"Library/Application Support/Tunnelblick/Configurations"];
	NSString * privatePath   = [privatePrefix stringByAppendingPathComponent: fileName];
	
    NSString * shadowPrefix  = [L_AS_T_USERS stringByAppendingPathComponent: gUserName];
    NSString * shadowPath    = [shadowPrefix stringByAppendingPathComponent: fileName];
    
	NSString * createdReplaced = @"Created";
	if (   folderExistsForRootAtPath(shadowPath)  ) {
		if (  folderExistsForRootAtPath(privatePath)  ) {
			createdReplaced = @"Replaced";
            becomeRoot(@"remove config that is being replaced");
			BOOL removed = [[NSFileManager defaultManager] tbRemoveFileAtPath: privatePath handler: nil];
            stopBeingRoot();
            if (  ! removed  ) {
				fprintf(stderr, "Unable to delete %s\n", [privatePath UTF8String]);
				exitOpenvpnstart(246);
			}
		}
        becomeRoot(@"copy config");
		BOOL copied = [[NSFileManager defaultManager] tbCopyPath: shadowPath toPath: privatePath handler: nil];
        stopBeingRoot();
        if (  copied  ) {
			fprintf(stderr, "%s %s\n", [createdReplaced UTF8String], [privatePath UTF8String]);
            becomeRoot(@"secure reverted .tblk");
			BOOL secured = secureOneFolder(privatePath, YES, gUidOfUser);
            stopBeingRoot();
            if (  secured  ) {
                exitOpenvpnstart(OPENVPNSTART_REVERT_CONFIG_OK);
            } else {
                exitOpenvpnstart(199);  // Already logged an error message
            }
		} else {
			fprintf(stderr, "Unable to copy %s to %s\n", [shadowPath UTF8String], [privatePath UTF8String]);
			exitOpenvpnstart(226);
		}
	} else {
		fprintf(stderr, "No secured (shadow) copy of a .tblk at %s\n", [shadowPath UTF8String]);
		exitOpenvpnstart(OPENVPNSTART_REVERT_CONFIG_MISSING);
	}
}

void printSanitizedConfigurationFile(NSString * configFile, unsigned cfgLocCode) {
    NSString * configPrefix = nil;
    switch (cfgLocCode) {
        case CFG_LOC_PRIVATE:
        case CFG_LOC_ALTERNATE:
			if (  gUidOfUser == 0  ) {
				fprintf(stderr, "Invalid cfgLocCode (printSanitizedConfigurationFile on a private or alternate configuration not allowed when running as root)\n");
				exitOpenvpnstart(205);
			}
			
            configPrefix = [[[[gUserHome stringByAppendingPathComponent: @"Library"]
                              stringByAppendingPathComponent: @"Application Support"]
                             stringByAppendingPathComponent: @"Tunnelblick"]
                            stringByAppendingPathComponent: @"Configurations"];
            break;
        case CFG_LOC_DEPLOY:
            configPrefix = [[gDeployPath copy] autorelease];
            break;
        case CFG_LOC_SHARED:
            configPrefix = L_AS_T_SHARED;
            break;
        default:
            fprintf(stderr, "Invalid cfgLocCode = %u\n", cfgLocCode);
            exit(EXIT_FAILURE);
    }
    
    NSString * configSuffix = @"";
    if (  [[configFile pathExtension] isEqualToString: @"tblk"]  ) {
        configSuffix = @"Contents/Resources/config.ovpn";
    }
    
    NSString * actualConfigPath = [[configPrefix
                                    stringByAppendingPathComponent: configFile]
                                   stringByAppendingPathComponent: configSuffix];
    
    becomeRootToAccessPath(actualConfigPath, @"get config contents");
    NSData * data = [[NSFileManager defaultManager] contentsAtPath: actualConfigPath];
    stopBeingRootToAccessPath(actualConfigPath);
    
    if (  ! data  ) {
        fprintf(stderr, "No configuration file at %s\n", [actualConfigPath UTF8String]);
        exit(EXIT_FAILURE);
    }
    
    NSString * cfgContents = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
	if (  ! cfgContents  ) {
		fprintf(stderr, "Could not interpret the configuration file at %s as UTF-8\n", [actualConfigPath UTF8String]);
		exit(EXIT_FAILURE);
	}
	
    NSString * sanitizedCfgContents = sanitizedConfigurationContents(cfgContents);
    if (  ! sanitizedCfgContents  ) {
        fprintf(stderr, "There was a problem in the configuration file at %s\n", [actualConfigPath UTF8String]);
        exit(EXIT_FAILURE);
    }
    
    fprintf(stdout, "%s", [sanitizedCfgContents UTF8String]);
    exit(EXIT_SUCCESS);
}

//**************************************************************************************************************************

void loadKexts(unsigned int bitMask) {
	//Tries to load kexts. May complain and exit if can't become root or if can't load kexts
	
    if (  ( bitMask & (OPENVPNSTART_OUR_TAP_KEXT | OPENVPNSTART_OUR_TUN_KEXT) ) == 0  ) {
        return;
    }
    
    NSMutableArray*	arguments = [NSMutableArray arrayWithCapacity: 2];
    if (  (bitMask & OPENVPNSTART_OUR_TAP_KEXT) != 0  ) {
        NSString * tapkext = [@"tap" stringByAppendingString: TunTapSuffixToUse()];
        NSString * tapPath = [gResourcesPath stringByAppendingPathComponent: tapkext];
        BOOL isDir;
        if (   ! (   [[NSFileManager defaultManager] fileExistsAtPath: tapPath isDirectory: &isDir]
                  && isDir)  ) {
            fprintf(stderr, "%s not found\n", [tapkext UTF8String]);
            exitOpenvpnstart(224);
        }
        [arguments addObject: tapPath];
        fprintf(stderr, "Loading %s\n", [tapkext UTF8String]);
    }
    if (  (bitMask & OPENVPNSTART_OUR_TUN_KEXT) != 0  ) {
        NSString * tunkext = [@"tun" stringByAppendingString: TunTapSuffixToUse()];
        NSString * tunPath = [gResourcesPath stringByAppendingPathComponent: tunkext];
        BOOL isDir;
        if (   ! (   [[NSFileManager defaultManager] fileExistsAtPath: tunPath isDirectory: &isDir]
                  && isDir)  ) {
            fprintf(stderr, "%s not found\n", [tunkext UTF8String]);
            exitOpenvpnstart(225);
        }
        [arguments addObject: tunPath];
        fprintf(stderr, "Loading %s\n", [tunkext UTF8String]);
    }
    
    int status;
    unsigned i;
    for (i=0; i < 5; i++) {
        status = runAsRoot(TOOL_PATH_FOR_KEXTLOAD, arguments, 0755);
        if (  status == 0  ) {
            break;
        }
        sleep(1);
    }
    if (  status != 0  ) {
        fprintf(stderr, "Unable to load net.tunnelblick.tun and/or net.tunnelblick.tap kexts in 5 tries. Status = %d\n", status);
        exitOpenvpnstart(OPENVPNSTART_COULD_NOT_LOAD_KEXT);
    }
}

void unloadKexts(unsigned int bitMask) {
	// Tries to UNload kexts. Will complain and exit if can't become root
	// We ignore errors because this is a non-critical function, and the unloading fails if a kext is in use
	
    if (  ( bitMask & (OPENVPNSTART_OUR_TAP_KEXT | OPENVPNSTART_OUR_TUN_KEXT | OPENVPNSTART_FOO_TAP_KEXT | OPENVPNSTART_FOO_TUN_KEXT) ) == 0  ) {
        return;
    }
    
    NSMutableArray*	arguments = [NSMutableArray arrayWithCapacity: 10];
    
    [arguments addObject: @"-q"];
    
    if (  (bitMask & OPENVPNSTART_OUR_TAP_KEXT) != 0  ) {
        [arguments addObjectsFromArray: [NSArray arrayWithObjects: @"-b", @"net.tunnelblick.tap", nil]];
    }
    if (  (bitMask & OPENVPNSTART_OUR_TUN_KEXT) != 0  ) {
        [arguments addObjectsFromArray: [NSArray arrayWithObjects: @"-b", @"net.tunnelblick.tun", nil]];
    }
    if (  (bitMask & OPENVPNSTART_FOO_TAP_KEXT) != 0  ) {
        [arguments addObjectsFromArray: [NSArray arrayWithObjects: @"-b", @"foo.tap", nil]];
    }
    if (  (bitMask & OPENVPNSTART_FOO_TUN_KEXT) != 0  ) {
        [arguments addObjectsFromArray: [NSArray arrayWithObjects: @"-b", @"foo.tun", nil]];
    }
    
    runAsRoot(TOOL_PATH_FOR_KEXTUNLOAD, arguments, 0755);
}

//**************************************************************************************************************************

BOOL safeUpdateWorker(NSString * sourcePath, NSString * targetPath, BOOL doUpdate) {
    
    // Either does a "safe" (certs/keys only) non-admin-authorized update of the shadow copy or tests that such an update can be done
    
    NSFileManager * fm = [NSFileManager defaultManager];
    
    NSString * sourceContentsPath  = [sourcePath         stringByAppendingPathComponent: @"Contents"];
    NSString * sourceResourcesPath = [sourceContentsPath stringByAppendingPathComponent: @"Resources"];
    NSString * sourceInfoPlistPath = [sourceContentsPath stringByAppendingPathComponent: @"Info.plist"];
    
    NSString * targetContentsPath  = [targetPath         stringByAppendingPathComponent: @"Contents"];
    NSString * targetResourcesPath = [targetContentsPath stringByAppendingPathComponent: @"Resources"];
    NSString * targetInfoPlistPath = [targetContentsPath stringByAppendingPathComponent: @"Info.plist"];
    
    if (  [fm fileExistsAtPath: sourceInfoPlistPath]  ) {
        if (  [fm fileExistsAtPath: targetInfoPlistPath]  ) {
            if (  ! [fm contentsEqualAtPath: sourceInfoPlistPath andPath: targetInfoPlistPath]  ) {
                fprintf(stderr, "'Info.plist' in the new configuration at %s is not identical to the same file in the old configuration at %s\n", [sourcePath UTF8String], [targetPath UTF8String]);
                return  FALSE;
            }
        } else {
            fprintf(stderr, "'Info.plist' exists in the new configuration at %s but does not exist in the old configuration at %s\n", [sourcePath UTF8String], [targetPath UTF8String]);
            return FALSE;
        }
    }
    
    NSArray * extensionsForKeysAndCerts = KEY_AND_CRT_EXTENSIONS;
    
    NSDirectoryEnumerator * dirE = [fm enumeratorAtPath: sourceResourcesPath];
    NSString * name;
    while (  (name = [dirE nextObject])  ) {
        
        // Ignore invisible files (such as .DS_Store)
        if (  [name hasPrefix: @"."]  ) {
            continue;
        }
        
        NSString * sourceFullPath = [sourceResourcesPath stringByAppendingPathComponent: name];
        NSString * targetFullPath = [targetResourcesPath stringByAppendingPathComponent: name];
        
        // File must exist in the shadow copy
        if (  ! [fm fileExistsAtPath: targetFullPath]  ) {
            fprintf(stderr, "'%s' exists in the new configuration at %s but does not exist in the old configuration at %s\n", [name UTF8String], [sourcePath UTF8String], [targetPath UTF8String]);
            return FALSE;
        }
        
        if (  [extensionsForKeysAndCerts containsObject: [name pathExtension]]  ) {
            
            // If a key/cert file and we are actually doing the update, replace the file
            if (  doUpdate  ) {
                if (  ! [fm tbRemoveFileAtPath: targetFullPath handler: nil]  ) {
                    return FALSE;
                }
                if (  ! [fm tbCopyPath: sourceFullPath toPath: targetFullPath handler: nil]  ) {
                    return FALSE;
                }
            }
        } else {
            
            // Not a key/cert file, it must be identical to the shadow copy
            if (  ! [fm contentsEqualAtPath: sourceFullPath andPath: targetFullPath]  ) {
                fprintf(stderr, "'%s' in the new configuration at %s is not identical to the same file in the old configuration at %s\n", [name UTF8String], [sourcePath UTF8String], [targetPath UTF8String]);
                return FALSE;
            }
        }
    }
    
    return TRUE;
}

void safeUpdate(NSString * displayName, BOOL doUpdate) {
    
    // If doUpdate is TRUE:  Secures the private configuration, tests that a non-admin-authorized update may be done from it, and does the update
    // If doUpdate is FALSE: Tests that a non-admin-authorized update of a configuration may be done

    if (  gUidOfUser == 0  ) {
        fprintf(stderr, "safeUpdate/safeUpdateTest not allowed when running as root\n");
        exit(OPENVPNSTART_UPDATE_SAFE_NOT_OK);
    }
    
    // Make sure an admin has authorized safe updates
    id obj = [[NSDictionary dictionaryWithContentsOfFile: L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH] objectForKey:@"allowNonAdminSafeConfigurationReplacement"];
    if (  ! (   [obj respondsToSelector: @selector(boolValue)]
             && [obj boolValue])  ) {
        fprintf(stderr, "safeUpdate/safeUpdateTest not been approved by an administrator\n");
        exit(OPENVPNSTART_UPDATE_SAFE_NOT_OK);
    }
    
    NSString * sourcePrefix = [gUserHome     stringByAppendingPathComponent: @"Library/Application Support/Tunnelblick/Configurations"];
    NSString * sourcePath   = [[sourcePrefix stringByAppendingPathComponent: displayName] stringByAppendingPathExtension: @"tblk"];
    
    NSString * targetPrefix  = [L_AS_T_USERS stringByAppendingPathComponent: gUserName];
    NSString * targetPath    = [[targetPrefix stringByAppendingPathComponent: displayName] stringByAppendingPathExtension: @"tblk"];
    
    if (  doUpdate  ) {
        
        // Secure the private copy by making it owned by root:wheel and writable only by the owner
        // (So we know that the source can't be modified between testing and updating)
        becomeRoot(@"secure private folder before safeUpdate");
        BOOL ok = secureOneFolder(sourcePath, NO, 0);
        stopBeingRoot();
        if (  ! ok  ) {
            fprintf(stderr, "Unable to secure privatefolder %s\n", [sourcePath UTF8String]);
            exit(OPENVPNSTART_UPDATE_SAFE_NOT_OK);
        }
        
        // Make sure it is OK to update
        becomeRoot(@"do safeUpdateTest before safeUpdate");
        ok = safeUpdateWorker(sourcePath, targetPath, NO);
        stopBeingRoot();
        if (  ! ok  ) {
            fprintf(stderr, "SafeUpdate test failed; source = %s; target = %s\n", [sourcePath UTF8String], [targetPath UTF8String]);
            exit(OPENVPNSTART_UPDATE_SAFE_NOT_OK);
        }

        // Do the actual update
        becomeRoot(@"do safeUpdate");
        ok = safeUpdateWorker(sourcePath, targetPath, YES);
        stopBeingRoot();
        if (  ! ok  ) {
            fprintf(stderr, "SafeUpdate failed; source = %s; target = %s\n", [sourcePath UTF8String], [targetPath UTF8String]);
            exit(OPENVPNSTART_UPDATE_SAFE_NOT_OK);
        }
        
        // Restore normal security on the user's private configuration
        becomeRoot(@"normal security on the user's private configuration");
        ok = secureOneFolder(sourcePath, YES, gUidOfUser);
        stopBeingRoot();
        if (  ! ok  ) {
            fprintf(stderr, "Unable to restore normal security on folder %s\n", [sourcePath UTF8String]);
            exit(OPENVPNSTART_UPDATE_SAFE_NOT_OK);
        }
        
    } else {
        // Test if it is OK to update
        becomeRoot(@"do safeUpdateTest");
        BOOL ok = safeUpdateWorker(sourcePath, targetPath, NO);
        stopBeingRoot();
        if (  ! ok  ) {
            fprintf(stderr, "SafeUpdateTest failed; source = %s; target = %s\n", [sourcePath UTF8String], [targetPath UTF8String]);
            exit(OPENVPNSTART_UPDATE_SAFE_NOT_OK);
        }
    }
    
    exit(OPENVPNSTART_UPDATE_SAFE_OK);
}

//**************************************************************************************************************************
int startVPN(NSString * configFile,
             unsigned   port,
             unsigned   useScripts,
             BOOL       skipScrSec,
             unsigned   cfgLocCode,
             BOOL       noMonitor,
             unsigned   bitMask,
             NSString * leasewatchOptions,
             NSString * openvpnVersion) {
    
	// Tries to start an openvpn connection (up to ten times if not starting from GUI).
    // Returns OPENVPNSTART_COULD_NOT_START_OPENVPN (having output a message to stderr) if any other error occurs
	
	NSString * openvpnPath  = openvpnToUsePath([gResourcesPath stringByAppendingPathComponent: @"openvpn"], openvpnVersion);    
    NSString * downRootPath = [[openvpnPath stringByDeletingLastPathComponent]
                               stringByAppendingPathComponent: @"openvpn-down-root.so"];
    
    NSString * scriptNumString;
    unsigned scriptNum = (useScripts & OPENVPNSTART_USE_SCRIPTS_SCRIPT_MASK) >> OPENVPNSTART_USE_SCRIPTS_SCRIPT_SHIFT_COUNT;
    if (  scriptNum == 0) {
        scriptNumString = @"";
    } else {
        scriptNumString = [NSString stringWithFormat: @"%u.", scriptNum];
    }
    
    NSString * upscriptPath              = [gResourcesPath stringByAppendingPathComponent: [NSString stringWithFormat: @"client.%@up.osx.sh",                     scriptNumString]];
    NSString * downscriptPath            = [gResourcesPath stringByAppendingPathComponent: [NSString stringWithFormat: @"client.%@down.osx.sh",                   scriptNumString]];
    NSString * upscriptNoMonitorPath	 = [gResourcesPath stringByAppendingPathComponent: [NSString stringWithFormat: @"client.%@nomonitor.up.osx.sh",           scriptNumString]];
    NSString * downscriptNoMonitorPath	 = [gResourcesPath stringByAppendingPathComponent: [NSString stringWithFormat: @"client.%@nomonitor.down.osx.sh",         scriptNumString]];
    
    NSString * newUpscriptPath           = [gResourcesPath stringByAppendingPathComponent: [NSString stringWithFormat: @"client.%@up.tunnelblick.sh",             scriptNumString]];
    NSString * newDownscriptPath         = [gResourcesPath stringByAppendingPathComponent: [NSString stringWithFormat: @"client.%@down.tunnelblick.sh",           scriptNumString]];
    NSString * newRoutePreDownscriptPath = [gResourcesPath stringByAppendingPathComponent: [NSString stringWithFormat: @"client.%@route-pre-down.tunnelblick.sh", scriptNumString]];
    NSString * standardRoutePreDownscriptPath = [[newRoutePreDownscriptPath copy] autorelease];
    
    NSString * tblkPath = nil;  // Path to .tblk, or nil if configuration is .conf or .ovpn.
    
    NSString * cdFolderPath = nil;
    
    // Do not disable logging if starting when computer starts
    if (  (bitMask & OPENVPNSTART_NOT_WHEN_COMPUTER_STARTS) == 0  ) {
        bitMask = bitMask & ( ~ OPENVPNSTART_DISABLE_LOGGING );
        fprintf(stderr, "Warning: The bitMask setting to disable OpenVPN logging is being ignored because the configuration is starting when the computer starts");
    }
    // Determine path to the configuration file and the --cd folder
    switch (cfgLocCode) {
        case CFG_LOC_PRIVATE:
            fprintf(stderr, "Private configurations may no longer be connected directly. Use a secure (shadow) copy of a private configuration.");   // Shouldn't get this far!
            exitOpenvpnstart(227);
            break;
            
        case CFG_LOC_ALTERNATE:
			if (  gUidOfUser == 0  ) {
				fprintf(stderr, "Invalid cfgLocCode (alternate configuration not allowed when running as root)\n");
				exitOpenvpnstart(189);
			}
						
            cdFolderPath = [NSString stringWithFormat:@"%@/%@", L_AS_T_USERS, gUserName];  // Will be set below BECAUSE this is a .tblk.
            gConfigPath  = [[cdFolderPath stringByAppendingPathComponent: configFile] copy];
            break;
            
        case CFG_LOC_DEPLOY:
            cdFolderPath = [[gDeployPath copy] autorelease]; // Will be set below IF this is a .tblk.
            gConfigPath  = [[gDeployPath stringByAppendingPathComponent: configFile] copy];
            break;
            
        case CFG_LOC_SHARED:
            if (  ! [[configFile pathExtension] isEqualToString: @"tblk"]) {
                fprintf(stderr, "Only Tunnelblick VPN Configurations (.tblk packages) may connect from /Library/Application Support/Tunnelblick/Shared\n");
                exitOpenvpnstart(228);
            }
            cdFolderPath = L_AS_T_SHARED; // Will be set below BECAUSE this is a .tblk.
            gConfigPath  = [[L_AS_T_SHARED stringByAppendingPathComponent: configFile] copy];
            break;
            
        default:
            fprintf(stderr, "Syntax error: Invalid cfgLocCode (%d)\n", cfgLocCode);
            exitOpenvpnstart(OPENVPNSTART_RETURN_SYNTAX_ERROR);
    }
    
    if (  [[gConfigPath pathExtension] isEqualToString: @"tblk"]) {
        
        // A .tblk package: check that it is secured, override any code above that sets directoryPath, and set the actual configuration path
        exitIfTblkNeedsRepair();
        
        tblkPath = [[gConfigPath copy] autorelease];
        NSString * cfg = configPathFromTblkPath(gConfigPath);
        if (  ! cfg  ) {
            fprintf(stderr, "Unable to find configuration file in %s\n", [gConfigPath UTF8String]);
            exitOpenvpnstart(229);
        }
        cdFolderPath = [gConfigPath stringByAppendingPathComponent: @"Contents/Resources"];
        gConfigPath = [cfg copy];
    } else {
        exitIfOvpnNeedsRepair();
        if (  ! [gConfigPath hasPrefix: [gDeployPath stringByAppendingString: @"/"]]  ) { // Not a .tblk, so check that it is Deployed
            fprintf(stderr, "Configuration is not Deployed and not a .tblk\n");
            exitOpenvpnstart(230);
        }
    }
    
    if (  port == 0  ) {
        port = getFreePort(1337);   // If port number is zero, preserve old default behavior: start looking for a free port starting with 1337
    } else if (  (bitMask & OPENVPNSTART_NOT_WHEN_COMPUTER_STARTS) != 0  ) {
        port = getFreePort(port);   // If no GUI, start looking for a free port with the specified starting port number
    }                               // Otherwise, use the specified port
    if (  port == 0  ) {
        fprintf(stderr, "Unable to find a free port to connect to the management interface\n");
        exitOpenvpnstart(248);
    }
    
    // Delete old OpenVPN log files and script log files for this configuration
    deleteLogFiles(configFile, cfgLocCode);
    
    // If not logging, send the log to /dev/null and set verb level to 0
    // If logging, create a new, empty OpenVPN log file (we create the script log later) and use the verb level encoded in useScripts
    //             but don't set the verb level if it should be left to the configuration file or the OpenVPN default level.
    NSString * logPath    = @"/dev/null";
    NSString * verbString = @"0";
    if (  (bitMask & OPENVPNSTART_DISABLE_LOGGING) == 0  ) {
        logPath = createOpenVPNLog(configFile, cfgLocCode, port);
        unsigned verbLevel = (  (useScripts & OPENVPNSTART_VERB_LEVEL_SCRIPT_MASK) >> OPENVPNSTART_VERB_LEVEL_SHIFT_COUNT  );
        if (  verbLevel == TUNNELBLICK_CONFIG_LOGGING_LEVEL  ) {
            verbString = nil;
        } else {
            verbString = [NSString stringWithFormat: @"%u", verbLevel];
        }
    }
    
    // Set up the arguments that go in the OpenVPN command line
    
    // Specify daemon and log path first, so the config file cannot override them, and specify the working directory for the config
	NSMutableArray* arguments = [NSMutableArray arrayWithObjects:
								 
                                 // Specify daemon and log path first, so the config file cannot override them, and specify the working directory for the config
                                 @"--daemon",
                                 @"--log",        logPath,
								 @"--cd",         cdFolderPath,
                                 nil];
    
	// Set IV_GUI_VER using the "--setenv" option
	// We get the Info.plist contents as follows because NSBundle's objectForInfoDictionaryKey: method returns the object as it was at
	// compile time, before the TBBUILDNUMBER is replaced by the actual build number (which is done in the final run-script that builds Tunnelblick)
	// By constructing the path, we force the objects to be loaded with their values at run time.
	NSString * plistPath    = [[[[NSBundle mainBundle] bundlePath]
								stringByDeletingLastPathComponent] // Remove /Resources
							   stringByAppendingPathComponent: @"Info.plist"];
	NSDictionary * infoDict = [NSDictionary dictionaryWithContentsOfFile: plistPath];
	NSString * bundleId     = [infoDict objectForKey: @"CFBundleIdentifier"];
	NSString * buildNumber  = [infoDict objectForKey: @"CFBundleVersion"];
	NSString * fullVersion  = [infoDict objectForKey: @"CFBundleShortVersionString"];
	NSString * guiVersion   = [NSString stringWithFormat: @"\"%@ %@ %@\"", bundleId, buildNumber, fullVersion];
	[arguments addObject: @"--setenv"];
	[arguments addObject: @"IV_GUI_VER"];
	[arguments addObject: guiVersion];
	
    // Optionally specify verb level before the configuration file, so the configuration file can override it while it is being processed
    if (  verbString  ) {
        [arguments addObject: @"--verb"];
        [arguments addObject: verbString];
    }
    
    // Process options in the configuration file
    [arguments addObject: @"--config"];
    [arguments addObject: gConfigPath];
    
    // Optionally specify verb level after the configuration file, so we override it
    if (  verbString  ) {
        [arguments addObject: @"--verb"];
        [arguments addObject: verbString];
    }
    
    // Set the working directory again, in case it was changed in the configuration file
    [arguments addObject: @"--cd"];
    [arguments addObject: cdFolderPath];
    
    // Specify the --mangement option and the rest of the options after the config file, so they override any correspondng options in it
    [arguments addObject: @"--management"];
    [arguments addObject: @"127.0.0.1"];
    [arguments addObject: [NSString stringWithFormat:@"%u", port]];
	
	NSString * themipName = mipName();
	if (  ! themipName  ) {
		fprintf(stderr, "Unable to find .mip\n");
		exitOpenvpnstart(169);
	}
	[arguments addObject: [L_AS_T stringByAppendingPathComponent: [themipName stringByAppendingString: @".mip"]]];
    
	if (  (bitMask & OPENVPNSTART_TEST_MTU) != 0  ) {
        [arguments addObject: @"--mtu-test"];
    }
    
	if (  (bitMask & OPENVPNSTART_NOT_WHEN_COMPUTER_STARTS) != 0  ) {
        [arguments addObject: @"--management-query-passwords"];
        [arguments addObject: @"--management-hold"];
    }
    
    if (  (bitMask & OPENVPNSTART_USE_REDIRECT_GATEWAY_DEF1) != 0  ) {
        [arguments addObject: @"--redirect-gateway"];
        [arguments addObject: @"def1"];
    }
    
    if( ! skipScrSec ) {        // permissions must allow us to call the up and down scripts or scripts defined in config
        [arguments addObject: @"--script-security"];
        [arguments addObject: @"2"];
    }
    
    // Figure out which scripts to use (if any)
    // For backward compatibility, we only use the "new" (-tunnelblick-argument-capable) scripts if there are no old scripts
    // This would normally be the case, but if someone's custom build inserts replacements for the old scripts, we will use the replacements instead of the new scripts
    
    if(  (useScripts & OPENVPNSTART_USE_SCRIPTS_RUN_SCRIPTS) != 0  ) {  // 'Set nameserver' specified, so use our standard scripts or Deploy/<config>.up.sh and Deploy/<config>.down.sh
        if (  cfgLocCode == CFG_LOC_DEPLOY  ) {
            NSString * deployScriptPath                 = [gDeployPath    stringByAppendingPathComponent: [configFile stringByDeletingPathExtension]];
            NSString * deployUpscriptPath               = [deployScriptPath stringByAppendingPathExtension: [NSString stringWithFormat: @"%@up.sh",                         scriptNumString]];
            NSString * deployDownscriptPath             = [deployScriptPath stringByAppendingPathExtension: [NSString stringWithFormat: @"%@down.sh",                       scriptNumString]];
            NSString * deployUpscriptNoMonitorPath      = [deployScriptPath stringByAppendingPathExtension: [NSString stringWithFormat: @"%@nomonitor.up.sh",               scriptNumString]];
            NSString * deployDownscriptNoMonitorPath    = [deployScriptPath stringByAppendingPathExtension: [NSString stringWithFormat: @"%@nomonitor.down.sh",             scriptNumString]];
            NSString * deployNewUpscriptPath            = [deployScriptPath stringByAppendingPathExtension: [NSString stringWithFormat: @"%@up.tunnelblick.sh",             scriptNumString]];
            NSString * deployNewDownscriptPath          = [deployScriptPath stringByAppendingPathExtension: [NSString stringWithFormat: @"%@down.tunnelblick.sh",           scriptNumString]];
            NSString * deployNewRoutePreDownscriptPath  = [deployScriptPath stringByAppendingPathExtension: [NSString stringWithFormat: @"%@route-pre-down.tunnelblick.sh", scriptNumString]];
            
            if (  noMonitor  ) {
                if (  [[NSFileManager defaultManager] fileExistsAtPath: deployUpscriptNoMonitorPath]  ) {
                    upscriptPath = deployUpscriptNoMonitorPath;
                } else if (  [[NSFileManager defaultManager] fileExistsAtPath: deployUpscriptPath]  ) {
                    upscriptPath = deployUpscriptPath;
                } else if (  [[NSFileManager defaultManager] fileExistsAtPath: upscriptNoMonitorPath]  ) {
                    upscriptPath = upscriptNoMonitorPath;
                } else if (  [[NSFileManager defaultManager] fileExistsAtPath: deployNewUpscriptPath]  ) {
                    upscriptPath = deployNewUpscriptPath;
                } else {
                    upscriptPath = newUpscriptPath;
                }
                if (  [[NSFileManager defaultManager] fileExistsAtPath: deployDownscriptNoMonitorPath]  ) {
                    downscriptPath = deployDownscriptNoMonitorPath;
                } else if (  [[NSFileManager defaultManager] fileExistsAtPath: deployDownscriptPath]  ) {
                    downscriptPath = deployDownscriptPath;
                } else if (  [[NSFileManager defaultManager] fileExistsAtPath: downscriptNoMonitorPath]  ) {
                    downscriptPath = downscriptNoMonitorPath;
                } else if (  [[NSFileManager defaultManager] fileExistsAtPath: deployNewDownscriptPath]  ) {
                    downscriptPath = deployNewDownscriptPath;
                } else {
                    downscriptPath = newDownscriptPath;
                }
                if (  [[NSFileManager defaultManager] fileExistsAtPath: deployNewRoutePreDownscriptPath]  ) {
                    newRoutePreDownscriptPath = deployNewRoutePreDownscriptPath;
                }
            } else {
                if (  [[NSFileManager defaultManager] fileExistsAtPath: deployUpscriptPath]  ) {
                    upscriptPath = deployUpscriptPath;
                } else if (  [[NSFileManager defaultManager] fileExistsAtPath: upscriptPath]  ) {
                    ;
                } else if (  [[NSFileManager defaultManager] fileExistsAtPath: deployNewUpscriptPath]  ) {
                    upscriptPath = deployNewUpscriptPath;
                } else {
                    upscriptPath = newUpscriptPath;
                }
                if (  [[NSFileManager defaultManager] fileExistsAtPath: deployDownscriptPath]  ) {
                    downscriptPath = deployDownscriptPath;
                } else if (  [[NSFileManager defaultManager] fileExistsAtPath: downscriptPath]  ) {
                    ;
                } else if (  [[NSFileManager defaultManager] fileExistsAtPath: deployNewDownscriptPath]  ) {
                    downscriptPath = deployNewDownscriptPath;
                } else {
                    downscriptPath = newDownscriptPath;
                }
                if (  [[NSFileManager defaultManager] fileExistsAtPath: deployNewRoutePreDownscriptPath]  ) {
                    newRoutePreDownscriptPath = deployNewRoutePreDownscriptPath;
                }
            }
        } else {
            if (  noMonitor  ) {
                if (  [[NSFileManager defaultManager] fileExistsAtPath: upscriptNoMonitorPath]  ) {
                    upscriptPath = upscriptNoMonitorPath;
                } else {
                    upscriptPath = newUpscriptPath;
                }
                if (  [[NSFileManager defaultManager] fileExistsAtPath: downscriptNoMonitorPath]  ) {
                    downscriptPath = downscriptNoMonitorPath;
                } else {
                    downscriptPath = newDownscriptPath;
                }
            } else {
                if (  [[NSFileManager defaultManager] fileExistsAtPath: upscriptPath]  ) {
                    ;
                } else {
                    upscriptPath = newUpscriptPath;
                }
                if (  [[NSFileManager defaultManager] fileExistsAtPath: downscriptPath]  ) {
                    ;
                } else {
                    downscriptPath = newDownscriptPath;
                }
            }
            
        }
        
        // BUT MAY OVERRIDE THE ABOVE if there are scripts in the .tblk
        if (  tblkPath  ) {
            NSString * tblkUpscriptPath              = [cdFolderPath stringByAppendingPathComponent: [NSString stringWithFormat: @"%@up.sh",                         scriptNumString]];
            NSString * tblkDownscriptPath            = [cdFolderPath stringByAppendingPathComponent: [NSString stringWithFormat: @"%@down.sh",                       scriptNumString]];
            NSString * tblkUpscriptNoMonitorPath     = [cdFolderPath stringByAppendingPathComponent: [NSString stringWithFormat: @"%@nomonitor.up.sh",               scriptNumString]];
            NSString * tblkDownscriptNoMonitorPath   = [cdFolderPath stringByAppendingPathComponent: [NSString stringWithFormat: @"%@nomonitor.down.sh",             scriptNumString]];
            NSString * tblkNewUpscriptPath           = [cdFolderPath stringByAppendingPathComponent: [NSString stringWithFormat: @"%@up.tunnelblick.sh",             scriptNumString]];
            NSString * tblkNewDownscriptPath         = [cdFolderPath stringByAppendingPathComponent: [NSString stringWithFormat: @"%@down.tunnelblick.sh",           scriptNumString]];
            NSString * tblkNewRoutePreDownscriptPath = [cdFolderPath stringByAppendingPathComponent: [NSString stringWithFormat: @"%@route-pre-down.tunnelblick.sh", scriptNumString]];
            
            if (  noMonitor  ) {
                if (  fileExistsForRootAtPath(tblkUpscriptNoMonitorPath)  ) {
                    upscriptPath = tblkUpscriptNoMonitorPath;
                } else if (  fileExistsForRootAtPath(tblkNewUpscriptPath)  ) {
                    upscriptPath = tblkNewUpscriptPath;
                }
                if (  fileExistsForRootAtPath(tblkDownscriptNoMonitorPath)  ) {
                    downscriptPath = tblkDownscriptNoMonitorPath;
                } else if (  fileExistsForRootAtPath(tblkNewDownscriptPath)  ) {
                    downscriptPath = tblkNewDownscriptPath;
                }
            } else {
                if (  fileExistsForRootAtPath(tblkUpscriptPath)  ) {
                    upscriptPath = tblkUpscriptPath;
                } else if (  fileExistsForRootAtPath(tblkNewUpscriptPath)  ) {
                    upscriptPath = tblkNewUpscriptPath;
                }
                if (  fileExistsForRootAtPath(tblkDownscriptPath)  ) {
                    downscriptPath = tblkDownscriptPath;
                } else if (  fileExistsForRootAtPath(tblkNewDownscriptPath)  ) {
                    downscriptPath = tblkNewDownscriptPath;
                }
            }
            if (  fileExistsForRootAtPath(tblkNewRoutePreDownscriptPath)  ) {
                newRoutePreDownscriptPath = tblkNewRoutePreDownscriptPath;
            }
        }
        
        // Process script options if scripts are "new" scripts
        NSMutableString * scriptOptions = [[[NSMutableString alloc] initWithCapacity: 16] autorelease];
        
        if (  (bitMask & OPENVPNSTART_ENABLE_IPV6_ON_TAP) != 0  ) {
            [scriptOptions appendString: @" -6"];   // TAP using DHCP only
        }
        
        if (  (bitMask & OPENVPNSTART_DISABLE_IPV6_ON_TUN) != 0  ) {
            [scriptOptions appendString: @" -9"];   // TUN only
        }
        
        if (  (bitMask & OPENVPNSTART_USE_TAP) != 0  ) {
            [scriptOptions appendString: @" -a"];   // TAP only
        }
        
        if (  (bitMask & OPENVPNSTART_WAIT_FOR_DHCP_IF_TAP) != 0  ) {
			[scriptOptions appendString: @" -b"];
        }
        
        if (  (bitMask & OPENVPNSTART_RESTORE_ON_DNS_RESET) != 0  ) {
            [scriptOptions appendString: @" -d"];
        }
        
        if (  (bitMask & OPENVPNSTART_FLUSH_DNS_CACHE) != 0  ) {
            [scriptOptions appendString: @" -f"];
        }
        
        if (  (bitMask & OPENVPNSTART_DISABLE_INTERNET_ACCESS) != 0  ) {
            [scriptOptions appendString: @" -k"];
        }
        
		if (  (bitMask & OPENVPNSTART_DISABLE_INTERNET_ACCESS_UNEXPECTED) != 0  ) {
			[scriptOptions appendString: @" -ku"];
		}
		
        if (  ((bitMask & OPENVPNSTART_EXTRA_LOGGING) != 0) && ((bitMask & OPENVPNSTART_DISABLE_LOGGING) == 0)  ) {
            [scriptOptions appendString: @" -l"];
        }
        
        if (  ! noMonitor  ) {
            [scriptOptions appendString: @" -m"];
        }
        
        if (  (bitMask & OPENVPNSTART_NO_DEFAULT_DOMAIN) != 0  ) {
            [scriptOptions appendString: @" -n"];
        }
        
		if (  (bitMask & OPENVPNSTART_OVERRIDE_MANUAL_NETWORK_SETTINGS) != 0  ) {
			[scriptOptions appendString: @" -o"];
		}
		
        if (  (bitMask & OPENVPNSTART_PREPEND_DOMAIN_NAME) != 0  ) {
            [scriptOptions appendString: @" -p"];
        }
        
        if (  (bitMask & OPENVPNSTART_RESET_PRIMARY_INTERFACE) != 0  ) {
            [scriptOptions appendString: @" -r"];
        }
        
		if (  (bitMask & OPENVPNSTART_RESET_PRIMARY_INTERFACE_UNEXPECTED) != 0  ) {
			[scriptOptions appendString: @" -ru"];
		}
		
        if (  (bitMask & OPENVPNSTART_RESTORE_ON_WINS_RESET) != 0  ) {
            [scriptOptions appendString: @" -w"];
        }
        
#ifdef TBDebug
        NSString * appPath = [[gResourcesPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        [scriptOptions appendString: [@" -t" stringByAppendingString: appPath]];
#endif
        
        if (  [leasewatchOptions length] > 2  ) {
            [scriptOptions appendString: @" "];
            [scriptOptions appendString: leasewatchOptions];
        }
        
        NSString * upscriptCommand           = escaped(upscriptPath);   // Must escape these since they are the first part of a command line
        NSString * downscriptCommand         = escaped(downscriptPath);
        NSString * routePreDownscriptCommand = escaped(newRoutePreDownscriptPath);
        
        if (   scriptOptions
            && ( [scriptOptions length] != 0 )  ) {
            
            if (  [upscriptPath hasSuffix: @"tunnelblick.sh"]  ) {
                upscriptCommand   = [upscriptCommand   stringByAppendingString: scriptOptions];
            } else {
                fprintf(stderr, "Warning: up script %s is not new version; not using '%s' options\n", [upscriptPath UTF8String], [scriptOptions UTF8String]);
            }
            
            if (  [downscriptPath hasSuffix: @"tunnelblick.sh"]  ) {
                downscriptCommand = [downscriptCommand stringByAppendingString: scriptOptions];
            } else {
                fprintf(stderr, "Warning: down script %s is not new version; not using '%s' options\n", [downscriptPath UTF8String], [scriptOptions UTF8String]);
            }
            
            routePreDownscriptCommand = [routePreDownscriptCommand stringByAppendingString: scriptOptions];
        }
        
        if (   ([upscriptCommand length] > 199  )
            || ([downscriptCommand length] > 199  )) {
            fprintf(stderr, "Warning: Path for up and/or down script is very long. OpenVPN truncates the command line that starts each script to 255 characters, which may cause problems. Examine the OpenVPN log in Tunnelblick's \"VPN Details...\" window carefully.\n");
        }
        
		NSString * upOrRouteUpOption = (  ((bitMask & OPENVPNSTART_USE_ROUTE_UP_NOT_UP) != 0)
                                        ? @"--route-up"
                                        : @"--up");
        if (  (useScripts & OPENVPNSTART_USE_SCRIPTS_USE_DOWN_ROOT) != 0  ) {
            [arguments addObjectsFromArray: [NSArray arrayWithObjects:
                                             upOrRouteUpOption, upscriptCommand,
                                             @"--plugin", downRootPath, downscriptCommand,
                                             nil
                                             ]
             ];
        } else {
            [arguments addObjectsFromArray: [NSArray arrayWithObjects:
                                             upOrRouteUpOption, upscriptCommand,
                                             @"--down", downscriptCommand,
                                             nil
                                             ]
             ];
        }
        
        if (  fileExistsForRootAtPath(newRoutePreDownscriptPath)  ) {
            BOOL customRoutePreDownScript = ! [newRoutePreDownscriptPath isEqualToString: standardRoutePreDownscriptPath];
            NSString * versionToUse = [[openvpnPath
                                        stringByDeletingLastPathComponent]     // remove "openvpn", the executable
                                       lastPathComponent];                     // isolate "openvpn-XXXX"
            
            NSMutableString * tempMutableString = [[versionToUse mutableCopy] autorelease];
            [tempMutableString replaceOccurrencesOfString: @"openvpn-" withString: @"" options: 0 range: NSMakeRange(0, [tempMutableString length])];
            versionToUse = [NSString stringWithString: tempMutableString];
            
            BOOL openvpnHasRoutePreDown = (NSOrderedDescending == [[versionToUse substringToIndex: 3] compare: @"2.2"]);
            if (   customRoutePreDownScript
                && (  ! openvpnHasRoutePreDown )  ) {
                fprintf(stderr, "Your 'Tunnelblick VPN Configuration' or 'Deployed' configuration includes a 'route-pre-down.tunnelblick.sh' file,"
                        " which requires OpenVPN's '--route-pre-down' option. That option is not available in OpenVPN version %s, it is only available"
                        " in OpenVPN version 2.3alpha1 and higher.", [versionToUse UTF8String]);
                exitOpenvpnstart(231);
            }
            
            if (  openvpnHasRoutePreDown ) {
                if (  (useScripts & OPENVPNSTART_USE_SCRIPTS_USE_DOWN_ROOT) != 0  ) {
                    if (  customRoutePreDownScript  ) {
                        fprintf(stderr, "Warning: Tunnelblick is using 'openvpn-down-root.so', so the custom route-pre-down script will not"
                                " be executed as root unless the 'user' and 'group' options are removed from the OpenVPN configuration file.");
                    } else {
						if (   ((bitMask & OPENVPNSTART_DISABLE_INTERNET_ACCESS) != 0)
							|| ((bitMask & OPENVPNSTART_DISABLE_INTERNET_ACCESS_UNEXPECTED) != 0)  ) {
							fprintf(stderr, "Error: Tunnelblick is using 'openvpn-down-root.so', so 'Disable network access after disconnecting'"
									" will not work because the 'route-pre-down script' will not be executed as root. Remove the 'user' and 'group' options"
									" from the OpenVPN configuration file to allow 'Disable network access after disconnecting' to work.");
							exitOpenvpnstart(170);
						} else {
							fprintf(stderr, "Warning: Tunnelblick is using 'openvpn-down-root.so', so the route-pre-down script will not be used."
									" You can override this by providing a custom route-pre-down script (which may be a copy of Tunnelblick's standard"
									" route-pre-down script) in a Tunnelblick VPN Configuration. However, that script will not be executed as root"
									" unless the 'user' and 'group' options are removed from the OpenVPN configuration file. If the 'user' and 'group'"
									" options are removed, then you don't need to use a custom route-pre-down script.");
						}
					}
                } else {
                    if (   customRoutePreDownScript
						|| ((bitMask & OPENVPNSTART_USE_TAP) != 0)
						|| ((bitMask & OPENVPNSTART_DISABLE_INTERNET_ACCESS) != 0)
						|| ((bitMask & OPENVPNSTART_DISABLE_INTERNET_ACCESS_UNEXPECTED) != 0)
					   ) {
						[arguments addObjectsFromArray: [NSArray arrayWithObjects:
														 @"--route-pre-down", routePreDownscriptCommand,
														 nil
														 ]
						 ];
					}
                }
            }
        }
    }
    
    if (  (bitMask & OPENVPNSTART_DISABLE_LOGGING) == 0  ) {
        createScriptLog(configFile, cfgLocCode); // Create a new script log
    }
	
    if (  tblkPath  ) {
        
        NSString * preConnectFolder = [tblkPath         stringByAppendingPathComponent: @"Contents/Resources"];
        NSString * preConnectPath   = [preConnectFolder stringByAppendingPathComponent: @"pre-connect.sh"];
        
        if (   fileExistsForRootAtPath(preConnectPath)  ) {
            exitIfNotRootWithPermissions(preConnectPath, PERMS_SECURED_SCRIPT);
            
            fprintf(stderr, "Executing pre-connect.sh in %s...\n", [preConnectFolder UTF8String]);
            
            int result = runAsRoot(preConnectPath, [NSArray array], PERMS_SECURED_SCRIPT);
            
            fprintf(stderr, "Status %d returned by pre-connect.sh in %s\n", result, [preConnectFolder UTF8String]);
            
            if (  result != 0 ) {
                exitOpenvpnstart(232);
            }
		}
    }
	
    // Unload foo.tun/tap iff we are loading the new net.tunnelblick.tun/tap and foo.tun/tap are loaded
    unsigned unloadMask  = 0;
    unsigned loadedKexts = getLoadedKextsMask();
    
    if (  (bitMask & OPENVPNSTART_OUR_TAP_KEXT) != 0  ) {
        if (  (loadedKexts & OPENVPNSTART_FOO_TAP_KEXT) != 0  ) {
            unloadMask = OPENVPNSTART_FOO_TAP_KEXT;
        }
    }
    if (  (bitMask & OPENVPNSTART_OUR_TUN_KEXT) != 0  ) {
        if (  (loadedKexts & OPENVPNSTART_FOO_TUN_KEXT) != 0  ) {
            unloadMask = unloadMask | OPENVPNSTART_FOO_TUN_KEXT;
        }
    }
    if (  unloadMask != 0  ) {
        unloadKexts( unloadMask );
    }
    
    // Load the new net.tunnelblick.tun/tap if bitMask says to and they aren't already loaded
    unsigned loadMask = bitMask & (OPENVPNSTART_OUR_TAP_KEXT | OPENVPNSTART_OUR_TUN_KEXT);
    if (  (loadedKexts & OPENVPNSTART_OUR_TAP_KEXT) != 0   ) {
        loadMask = loadMask & ( ~ OPENVPNSTART_OUR_TAP_KEXT );
    }
    if (  (loadedKexts & OPENVPNSTART_OUR_TUN_KEXT) != 0  ) {
        loadMask = loadMask & ( ~ OPENVPNSTART_OUR_TUN_KEXT );
    }
    if (  loadMask != 0  ) {
        loadKexts(loadMask);
    }
    
    if (  tblkPath  ) {
        NSString * postTunTapFolder = [tblkPath         stringByAppendingPathComponent: @"Contents/Resources"];
        NSString * postTunTapPath   = [postTunTapFolder stringByAppendingPathComponent: @"post-tun-tap-load.sh"];
        
        if (  fileExistsForRootAtPath(postTunTapPath)  ) {
            exitIfNotRootWithPermissions(postTunTapPath, PERMS_SECURED_SCRIPT);
            
            fprintf(stderr, "Executing post-tun-tap-load.sh in %s...\n", [postTunTapFolder UTF8String]);
            
            int result = runAsRoot(postTunTapPath, [NSArray array], PERMS_SECURED_SCRIPT);
            
            fprintf(stderr, "Status %d returned by post-tun-tap-load.sh in %s\n", result, [postTunTapFolder UTF8String]);
            
            if (  result != 0 ) {
                exitOpenvpnstart(234);
            }
		}
    }
	
    int status;
    
    // If launching OpenVPN when the computer starts, delay until the Internet can be reached
    // Test for that by checking the reachability of the program update server (so rebranded versions check for their own update servers)
    if (   ((bitMask & OPENVPNSTART_NOT_WHEN_COMPUTER_STARTS) == 0)
		&& ((bitMask & OPENVPNSTART_DO_NOT_WAIT_FOR_INTERNET) == 0)  ) {
		NSString * infoPlistPath = [[gResourcesPath stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"Info.plist"];
		NSDictionary * infoPlist = [NSDictionary dictionaryWithContentsOfFile: infoPlistPath];
		NSString * feedURLString = [infoPlist objectForKey: @"SUFeedURL"];
		if (  feedURLString  ) {
			NSURL * feedURL = [NSURL URLWithString: feedURLString];
			NSString * host = [feedURL host];
			if (  host  ) {
				
                NSDate * timeoutDate = [NSDate dateWithTimeIntervalSinceNow: 30.0];
				do {
					SCNetworkReachabilityRef target = SCNetworkReachabilityCreateWithName(NULL, [host UTF8String]);
					SCNetworkReachabilityFlags flags = 0;
					BOOL canDetermineReachability = (  SCNetworkReachabilityGetFlags(target, &flags)
													 ? TRUE
													 : FALSE);
					
					CFRelease(target);
					if (   canDetermineReachability
						&& ((flags & kSCNetworkReachabilityFlagsReachable) != 0)
						&& ((flags & kSCNetworkReachabilityFlagsConnectionRequired) == 0)  ) {
						appendLog([NSString stringWithFormat: @"The Internet (host '%@') is reachable; flags = 0x%lx", host, (unsigned long)flags]);
						break;
					}
                    NSDate * now = [NSDate date];
                    if (  [now compare: timeoutDate] == NSOrderedDescending  ) {
						appendLog(@"Timed out waiting for the Internet to be reachable");
						break;
					}
					appendLog([NSString stringWithFormat: @"Waiting for the Internet (host '%@') to become reachable (%@ determine reachability; flags = 0x%lx)...",
							   host, (canDetermineReachability ? @"Can" : @"Cannot"), (unsigned long)flags]);
					sleep(1);
				}
				while (  TRUE  );
			} else {
				appendLog([NSString stringWithFormat: @"Not delaying until the Internet is available because the SUFeedURL ('%@') in Info.plist could not be parsed for a host", [feedURL absoluteString]]);
			}
		} else {
			appendLog(@"Not delaying until the Internet is available because there is no Info.plist or there is no SUFeedURL entry in it");
		}
	}
    
    status = runAsRoot(openvpnPath, arguments, 0755);
    
    NSMutableString * displayCmdLine = [NSMutableString stringWithFormat: @"     %@\n", openvpnPath];
    unsigned i;
    for (i=0; i<[arguments count]; i++) {
        [displayCmdLine appendString: [NSString stringWithFormat: @"     %@\n", [arguments objectAtIndex: i]]];
    }
    
    if (  status != 0  ) {
        NSString * logContents = @"";
        if (  (bitMask & OPENVPNSTART_DISABLE_LOGGING) == 0  ) {
            // Get the OpenVPN log contents and then delete both log files
            NSData * logData = [[NSFileManager defaultManager] contentsAtPath: logPath];
            
            if (  logData  ) {
                logContents = [[[NSString alloc] initWithData: logData encoding: NSUTF8StringEncoding] autorelease];
                if (  ! logContents  ) {
                    logContents = @"(Could not decode log contents)";
                }
            }
            
            NSMutableString * tempMutableString = [[[@"\n" stringByAppendingString:(NSString *) logContents] mutableCopy] autorelease];
            [tempMutableString replaceOccurrencesOfString: @"\n" withString: @"\n     " options: 0 range: NSMakeRange(0, [tempMutableString length])];
            logContents = [NSString stringWithString: tempMutableString];
            
            deleteLogFiles(configFile, cfgLocCode);
        } else {
            logContents = @"(Logging was disabled)";
        }
        
        fprintf(stderr, "OpenVPN returned with status %d, errno = %ld:\n"
                "     %s\n\n"
                "Command used to start OpenVPN (one argument per displayed line):\n\n"
                "%s\n"
                "Contents of the OpenVPN log:\n"
                "%s\n"
                "More details may be in the Console Log's \"All Messages\"\n",
                status, (long) errno, strerror(errno), [displayCmdLine UTF8String], [logContents UTF8String]);
        
        return OPENVPNSTART_COULD_NOT_START_OPENVPN;
    
    } else {
        fprintf(stderr, "OpenVPN started successfully. Command used to start OpenVPN (one argument per displayed line):\n\n"
                "%s\n",
                [displayCmdLine UTF8String]);
    }
    
    return 0;
}

//**************************************************************************************************************************
void validateConfigName(NSString * name) {
    
    if (  [name length] == 0  ) {
        fprintf(stderr, "Configuration name is empty\n");
        exitOpenvpnstart(172);
    }
    
    BOOL haveBadChar = FALSE;
	unsigned i;
	for (  i=0; i<[name length]; i++  ) {
		unichar c = [name characterAtIndex: i];
		if (   (c < 0x0020)
			|| (c == 0x007F)
			|| (c == 0x00FF)  ) {
            haveBadChar = TRUE;
            break;
		}
	}
	
	const char * nameC          = [name UTF8String];
	const char   badCharsC[]    = PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING;
	
	if (   haveBadChar
        || ( [name hasPrefix: @"."] )
        || ( [name rangeOfString: @".."].length != 0)
        || ( NULL != strpbrk(nameC, badCharsC) )
		) {
        fprintf(stderr, "Configuration name has one or more prohibited characters or character sequences\n");
        exitOpenvpnstart(237);
	}
}

void validatePort(unsigned port) {
    if (  port > 65535  ) {
        fprintf(stderr, "port value of %u is too large\n", port);
        printUsageMessageAndExitOpenvpnstart();
    }
}

void validateUseScripts(unsigned useScripts) {
    if (  useScripts & OPENVPNSTART_USE_SCRIPTS_RUN_SCRIPTS  ) {
        if (  useScripts > OPENVPNSTART_USE_SCRIPTS_MAX  ) {
            fprintf(stderr, "useScripts value of %u is too large\n", useScripts);
            printUsageMessageAndExitOpenvpnstart();
        }
    } else {
        if (  useScripts & OPENVPNSTART_USE_SCRIPTS_USE_DOWN_ROOT  ) {
            fprintf(stderr, "useScripts requests the use of openvpn-down-root.so but specifies no scripts should be used\n");
            printUsageMessageAndExitOpenvpnstart();
        }
    }
}

void validateCfgLocCode(unsigned cfgLocCode) {
    
    switch (  cfgLocCode  ) {
            
        case CFG_LOC_PRIVATE:
            fprintf(stderr, "cfgLocCode = private; private configurations are not allowed -- use the alternate location instead\n");
            exitOpenvpnstart(239);
            break;
            
        case CFG_LOC_ALTERNATE:
            if (  gUidOfUser == 0  ) {
                fprintf(stderr, "cfgLocCode = alternate but no user ID is available\n");
                exitOpenvpnstart(187);
            }
            break;
            
        case CFG_LOC_DEPLOY:
            if (  ! [[NSFileManager defaultManager] fileExistsAtPath: gDeployPath]  ) {
                fprintf(stderr, "cfgLocCode = deployed but this is not a Deployed version of Tunnelblick\n");
                exitOpenvpnstart(185);
            }
            break;
            
        case CFG_LOC_SHARED:
            break;
            
        default:
            fprintf(stderr, "cfgLocCode %u is invalid\n", cfgLocCode);
            exitOpenvpnstart(238);
            break;
    }
}

void validateBitmask(unsigned bitMask) {
    if (  (OPENVPNSTART_HIGHEST_BITMASK_BIT << 1) <= bitMask   ) {
        fprintf(stderr, "bitMask value of %x is too large; highest bitMask bit is %u\n", bitMask, OPENVPNSTART_HIGHEST_BITMASK_BIT);
        printUsageMessageAndExitOpenvpnstart();
    }
}

void validateLeasewatchOptions(NSString * leasewatchOptions) {
    if (  [leasewatchOptions length] != 0  ) {
        if (  [leasewatchOptions hasPrefix: @"-i"]  ) {
            NSCharacterSet * optionCharacterSet = [NSCharacterSet characterSetWithCharactersInString: @"dasngw"];
            NSRange r = [[leasewatchOptions substringFromIndex: 2] rangeOfCharacterFromSet: [optionCharacterSet invertedSet]];
            if (  r.length != 0  ) {
                leasewatchOptions = nil;
            }
        } else if (  [leasewatchOptions hasPrefix: @"-p"]  ) {
            NSCharacterSet * optionCharacterSet = [NSCharacterSet characterSetWithCharactersInString: @"trdasngwDASNGW"];
            NSRange r = [[leasewatchOptions substringFromIndex: 2] rangeOfCharacterFromSet: [optionCharacterSet invertedSet]];
            if (  r.length != 0  ) {
                leasewatchOptions = nil;
            }
        } else {
            leasewatchOptions =nil;
        }
    } else {
        leasewatchOptions =nil;
    }
    
    if (  ! leasewatchOptions  ) {
        fprintf(stderr, "Invalid leasewatchOptions\n");
        exitOpenvpnstart(240);
    }
}

void validateOpenvpnVersion(NSString * s) {
    
    if (  ! isSanitizedOpenvpnVersion(s)  ) {
        fprintf(stderr, "the openvpnVersion argument may only contain a-z, A-Z, 0-9, periods, underscores, and hyphens\n");
        exitOpenvpnstart(241);
    }
}

void validateEnvironment(void) {
	
	NSDictionary * env = [[NSProcessInfo processInfo] environment];
	
	// Check that the PATH starts with known system directories
	NSString * envPath = [env objectForKey:@"PATH"];	
    if (  envPath  ) {
		if (  ! [envPath hasPrefix: STANDARD_PATH]  ) {
			fprintf(stderr, "the PATH environment variable must start with '%s'; it is '%s'\n", [STANDARD_PATH UTF8String], [envPath UTF8String]);
			exitOpenvpnstart(177);
		}
	} else {
		fprintf(stderr, "the PATH environment variable is missing; it must be '%s'\n", [envPath UTF8String]);
		exitOpenvpnstart(176);
	}
	
	// Check some other environment variables for exact matches but allow them to be undefined
	NSDictionary * envVarsList = [NSDictionary dictionaryWithObjectsAndKeys:
								  NSTemporaryDirectory(), @"TMPDIR",
								  NSUserName(),           @"USER",
								  NSUserName(),           @"LOGNAME",
								  NSHomeDirectory(),      @"HOME",
								  TOOL_PATH_FOR_BASH,     @"SHELL",
								  @"unix2003",            @"COMMAND_MODE",
								  nil];
	
	BOOL errorFound = FALSE;
	NSEnumerator * e = [envVarsList keyEnumerator];
	NSString * key;
	while (  (key = [e nextObject])  ) {
		NSString * valueInEnv = [env objectForKey: key];
		if (   valueInEnv  ) {
			NSString * goodValue = [envVarsList objectForKey: key];
			if (  ! [valueInEnv isEqualToString: goodValue]  ) {
				fprintf(stderr, "If present, the %s environment variable must be set to '%s'; it is '%s'\n", [key UTF8String], [goodValue UTF8String], [valueInEnv UTF8String]);
				errorFound = TRUE;
			}
		}
	}
	
	if (  errorFound  ) {
		fprintf(stderr, "Complete environment = %s\n", [[env description] UTF8String]);
		exitOpenvpnstart(173);
	}
}

//**************************************************************************************************************************
int main(int argc, char * argv[]) {
    pool = [[NSAutoreleasePool alloc] init];
	
    // Tunnelblick starts this program one of the following two ways:
    //
    // This program is started by tunnelblickd: It is entered with uid = 0;   euid = <user-id>; gid = 0; egid = <group-id>
    //
    // where <user-id> and <group-id> are the user/group of the user who sent a request to tunnelblickd (possibly 0:0)
    //
    // This program may also be startd via 'sudo' in Terminal, in which chase uid = euid = gid = egid = 0.
    // If run via via 'sudo', this program may not run any subcommands that require access to the user's data (such as 'revertToShadow').
    //
    // We don't do anything with the group, but we manipulate the uid and euid to get access to protected files (as root).
    //
	// The uid and euid are set as follows in this program:
    //     When running as root:     uid == 0 and euid == 0
    //     When running as non-root: uid == 0 and euid == <user-id> (which may be 0, as noted above)
    
    uid_t originalUid  = getuid();	// Save user's uid, euid, short name, and home folder for later
    uid_t originalEuid = geteuid();
	gUserName = [NSUserName() copy];
	gUserHome = [NSHomeDirectory() copy];
	
    if (  originalUid == 0  ) {
        // Started by tunnelblickd or 'sudo'
        gUidOfUser = originalEuid; // User's uid or 0 if started by 'sudo'
    } else if (  originalEuid == 0  ) {
        gUidOfUser = originalUid;  // User's uid
    } else {
        fprintf(stderr, "uid is not 0 and euid is not 0 --Tunnelblick has probably not been secured. Secure it by launching Tunnelblick.");
        exitOpenvpnstart(174);
    }

    gPendingRootCounter = 1;    // Set up as root initially
    if (  setuid(0) != 0  ) {
        fprintf(stderr, "setuid(0) failed; Tunnelblick has probably not been secured. Secure it by launching Tunnelblick.");
    }

    
    stopBeingRoot();			// Stop being root
	
    NSBundle * ourBundle = [NSBundle mainBundle];
    gResourcesPath  = [[ourBundle bundlePath] copy];
    NSArray  * execComponents = [gResourcesPath pathComponents];
    if (  [execComponents count] < 3  ) {
        fprintf(stderr, "Too few execComponents; gResourcesPath = %s", [gResourcesPath UTF8String]);
        exitOpenvpnstart(242);
    }
	gDeployPath = [[gResourcesPath stringByAppendingPathComponent: @"Deploy"] copy];
	
#ifdef TBDebug
	NSMutableString * args = [NSMutableString stringWithCapacity: 1000];
	if (  argc > 0  ) {
		int ix;
		for (  ix=1; ix<argc; ix++  ) {
			[args appendFormat: @" %s", argv[ix]];
		}
	}
    fprintf(stderr, "WARNING: This is an insecure copy of tunnelblick-helper to be used for debugging only!\nopenvpnstart arguments: %s\n", [args UTF8String]);
#else
    if (   ([execComponents count] != 5)
        || [[execComponents objectAtIndex: 0] isNotEqualTo: @"/"]
        || [[execComponents objectAtIndex: 1] isNotEqualTo: @"Applications"]
        //                                                  Allow any name for Tunnelblick.app
        || [[execComponents objectAtIndex: 3] isNotEqualTo: @"Contents"]
        || [[execComponents objectAtIndex: 4] isNotEqualTo: @"Resources"]
        ) {
        fprintf(stderr, "Tunnelblick must be in /Applications (bundlePath = %s)\n", [gResourcesPath UTF8String]);
        exitOpenvpnstart(243);
    }
    NSString * ourPath = [gResourcesPath stringByAppendingPathComponent: @"tunnelblick-helper"];
    if (  pathIsNotSecure(ourPath, PERMS_SECURED_EXECUTABLE)  ) {
        fprintf(stderr, "tunnelblick-helper and the path to it have not been secured\n"
                "You must have installed Tunnelblick to use tunnelblick-helper\n");
        exitOpenvpnstart(244);
    }
#endif
	
	validateEnvironment();
	
    // Process arguments
    
    BOOL	syntaxError	= TRUE;
    int     retCode = 0;

	// Verify that all arguments are valid UTF-8 strings
	int ix;
	for (  ix=0; ix<argc; ix++  ) {
		const char * arg = argv[ix];
		if (   (arg == NULL)
			|| ([NSString stringWithUTF8String: arg] == NULL)  ) {
			fprintf(stderr, "Invalid argument #%d (0 = command; 1 = first actual argument)\n", ix);
			exitOpenvpnstart(171);
		}
	}

    if (  argc > 1  ) {
		char * command = argv[1];
		
		if ( ALLOW_OPENVPNSTART_KILLALL && (strcmp(command, "killall") == 0) ) {
			if (  argc == 2  ) {
				killAllOpenvpn();
				syntaxError = FALSE;
			}
		
        } else if (  strcmp(command, "test") == 0  ) {
            if (  argc == 2  ) {
				syntaxError = FALSE;
			}
            
        } else if (  strcmp(command, "re-enable-network-services") == 0  ) {
            if (  argc == 2  ) {
				runReenableNetworkServices();
				syntaxError = FALSE;
			}
            
        } else if (  strcmp(command, "route-pre-down") == 0  ) {
            if (  argc == 2  ) {
				runRoutePreDownScript(false);
				syntaxError = FALSE;
			}
            
		} else if (  strcmp(command, "route-pre-down-k") == 0  ) {
			if (  argc == 2  ) {
				runRoutePreDownScript(true);
				syntaxError = FALSE;
			}
			
        } else if (  strcmp(command, "checkSignature") == 0  ) {
            if (  argc == 2  ) {
				checkSignature();
				syntaxError = FALSE;
			}
            
        } else if ( strcmp(command, "deleteLogs") == 0 ) {
			if (argc == 2) {
                deleteAllLogFiles();
                syntaxError = FALSE;
            }
            
		} else if (  strcmp(command, "expectDisconnect") == 0  ) {
			if (  argc == 3  ) {
				unsigned int flag = cvt_atou(argv[2], @"flag");
				if (   (flag == 0)
					|| (flag == 1)  ) {
					expectDisconnect(flag);
					syntaxError = FALSE;
				}
			}
		} else if (  strcmp(command, "loadKexts") == 0  ) {
			if (  argc == 2  ) {
                loadKexts(OPENVPNSTART_KEXTS_MASK_LOAD_DEFAULT);
				syntaxError = FALSE;
            } else if (  argc == 3  ) {
                unsigned int kextMask = cvt_atou(argv[2], @"kext mask");
                if (  kextMask <= OPENVPNSTART_KEXTS_MASK_LOAD_MAX  ) {
                    if (  kextMask == 0  ) {
                        kextMask = OPENVPNSTART_KEXTS_MASK_LOAD_DEFAULT;
                    }
                    loadKexts(kextMask);
                    syntaxError = FALSE;
                }
			}
            
		} else if ( strcmp(command, "unloadKexts") == 0 ) {
			if (  argc == 2  ) {
                unloadKexts(OPENVPNSTART_KEXTS_MASK_UNLOAD_DEFAULT);
				syntaxError = FALSE;
            } else if (  argc == 3  ) {
                unsigned int kextMask = cvt_atou(argv[2], @"kext mask");
                if (  kextMask < OPENVPNSTART_KEXTS_MASK_UNLOAD_MAX  ) {
                    if (  kextMask == 0  ) {
                        kextMask = OPENVPNSTART_KEXTS_MASK_UNLOAD_DEFAULT;
                    }
                    unloadKexts(kextMask);
                    syntaxError = FALSE;
                }
			}
            
        } else if ( strcmp(command, "secureUpdate") == 0) {
			if (argc == 3) {
                NSString * name = [NSString stringWithUTF8String: argv[2]];
                secureUpdate(name); // Will validate its own argument
				syntaxError = FALSE;
			}
            
        } else if ( ALLOW_OPENVPNSTART_KILL && (strcmp(command, "kill") == 0) ) {
			if (argc == 3) {
				pid_t pid = (pid_t) atoi(argv[2]);
				killOneOpenvpn(pid);
				syntaxError = FALSE;
			}
            
        } else if (  strcmp(command, "down") == 0  ) {
            if (  argc == 3  ) {
                unsigned scriptNumber = atoi(argv[2]);
				runDownScript(scriptNumber);
				syntaxError = FALSE;
			}
            
        } else if ( strcmp(command, "compareShadowCopy") == 0 ) {
			if (argc == 3  ) {
				NSString* fileName = [NSString stringWithUTF8String:argv[2]];
                validateConfigName(fileName);
                compareShadowCopy(fileName);
                // compareShadowCopy() should never return (it does exit() with its own exit codes)
                // but just in case, we force a syntax error by NOT setting syntaxError FALSE
            }
            
        } else if ( strcmp(command, "revertToShadow") == 0 ) {
			if (argc == 3  ) {
				NSString* fileName = [NSString stringWithUTF8String:argv[2]];
                validateConfigName(fileName);
                revertToShadow(fileName);
                // revertToShadow() should never return (it does exit() with its own exit codes)
                // but just in case, we force a syntax error by NOT setting syntaxError FALSE
            }
            
        } else if ( strcmp(command, "safeUpdate") == 0 ) {
            if (argc == 3  ) {
                NSString* fileName = [NSString stringWithUTF8String:argv[2]];
                validateConfigName(fileName);
                safeUpdate(fileName, YES);
                // safeUpdate() should never return (it does exit() with its own exit codes)
                // but just in case, we force a syntax error by NOT setting syntaxError FALSE
            }
            
        } else if ( strcmp(command, "safeUpdateTest") == 0 ) {
            if (argc == 3  ) {
                NSString* fileName = [NSString stringWithUTF8String:argv[2]];
                validateConfigName(fileName);
                safeUpdate(fileName, NO);
                // safeUpdateTest() should never return (it does exit() with its own exit codes)
                // but just in case, we force a syntax error by NOT setting syntaxError FALSE
            }
            
        } else if ( strcmp(command, "deleteLog") == 0 ) {
            if (argc == 4) {
                NSString* configFile = [NSString stringWithUTF8String:argv[2]];
                unsigned cfgLocCode = cvt_atou(argv[3], @"cfgLocCode");
                validateConfigName(configFile);
                if (  cfgLocCode == CFG_LOC_PRIVATE  ) {
                    cfgLocCode = CFG_LOC_ALTERNATE;
                }
                validateCfgLocCode(cfgLocCode);
                deleteLogFiles(configFile, cfgLocCode);
                syntaxError = FALSE;
            }
            
        } else if ( strcmp(command, "printSanitizedConfigurationFile") == 0 ) {
			if (argc == 4) {
                NSString* configFile = [NSString stringWithUTF8String:argv[2]];
                unsigned cfgLocCode = cvt_atou(argv[3], @"cfgLocCode");
                validateConfigName(configFile);
				if (  cfgLocCode == CFG_LOC_PRIVATE  ) {
					cfgLocCode = CFG_LOC_ALTERNATE;
				}
				validateCfgLocCode(cfgLocCode);
                printSanitizedConfigurationFile(configFile, cfgLocCode);
                // printSanitizedConfigurationFile() should never return (it does exit() with its own exit codes)
                // but just in case, we force an error by NOT setting syntaxError FALSE
            }
            
        } else if ( strcmp(command, "postDisconnect") == 0) {
            // runScript validates its own arguments
            retCode = runScript(@"post-disconnect.sh", argc, argv);
            syntaxError = FALSE;
            
        } else if ( strcmp(command, "preDisconnect") == 0) {
            // runScript validates its own arguments
            retCode = runScript(@"pre-disconnect.sh", argc, argv);
            syntaxError = FALSE;
            
        } else if ( strcmp(command, "connected") == 0) {
            // runScript validates its own arguments
            retCode = runScript(@"connected.sh", argc, argv);
            syntaxError = FALSE;
            
        } else if ( strcmp(command, "reconnecting") == 0) {
            // runScript validates its own arguments
            retCode = runScript(@"reconnecting.sh", argc, argv);
            syntaxError = FALSE;
            
		} else if( strcmp(command, "start") == 0 ) {
            
            NSString * configFile = @"X";
            unsigned   port = 0;
            unsigned   useScripts = 0;
            BOOL       skipScrSec = FALSE;
            unsigned   cfgLocCode = 0;
            BOOL       noMonitor  = FALSE;
            unsigned   bitMask = OPENVPNSTART_KEXTS_MASK_LOAD_DEFAULT;
            NSString * leasewatchOptions = @"-i";
            NSString * openvpnVersion = @"";
            
			if (  (argc > 3) && (argc <= OPENVPNSTART_MAX_ARGC)  ) {
                
                if (  strlen(argv[3]) <= DISPLAY_NAME_LENGTH_MAX                      ) configFile = [NSString stringWithUTF8String:argv[2]];
                if (  (argc >  3) && (strlen(argv[ 3]) <  6)                          ) port = cvt_atou(argv[3], @"port");
                if (  (argc >  4) && (strlen(argv[ 4]) <  6)                          ) useScripts = cvt_atou(argv[4], @"useScripts");
                if (  (argc >  5) && (strlen(argv[ 5]) <  6) && (atoi(argv[5]) == 1)  ) skipScrSec = TRUE;
                if (  (argc >  6) && (strlen(argv[ 6]) <  6)                          ) cfgLocCode = cvt_atou(argv[6], @"cfgLocCode");
                if (  (argc >  7) && (strlen(argv[ 7]) <  6) && (atoi(argv[7]) == 1)  ) noMonitor  = TRUE;
                if (  (argc >  8) && (strlen(argv[ 8]) < 10)                          ) bitMask = cvt_atou(argv[8], @"bitMask");
                if (  (argc >  9) && (strlen(argv[ 9]) < 16)                          ) leasewatchOptions = [NSString stringWithUTF8String: argv[9]]; 
                if (  (argc > 10) && (strlen(argv[10]) < 32)                          ) openvpnVersion    = [NSString stringWithUTF8String: argv[10]];
                
                validateConfigName(configFile);
                validatePort(port);
                validateUseScripts(useScripts);
                validateCfgLocCode(cfgLocCode);
                validateBitmask(bitMask);
                validateLeasewatchOptions(leasewatchOptions);
                validateOpenvpnVersion(openvpnVersion);
				
                gStartArgs = [[NSString stringWithFormat: @"%u_%u_%u_%u_%u", useScripts, skipScrSec, cfgLocCode, noMonitor, bitMask] copy];
                if (  OPENVPNSTART_LOGNAME_ARG_COUNT != 5  ) {
                    fprintf(stderr, "openvpnstart internal error: openvpnstart expected OPENVPNSTART_LOGNAME_ARG_COUNT to be 5, but it is %u\n", OPENVPNSTART_LOGNAME_ARG_COUNT);

                    exitOpenvpnstart(179);
                }
				
                // Try to start OpenVPN.
                //
                // Retry up to 10 times IF OpenVPN fails and openvpnstart is not using the GUI.
                //
                // If the failure was caused by a race condition with several processes detecting the same free port and then trying to use it,
                // retrying should solve the problem because it will:
                //          (1) get a different free port (because the port that failed to bind is in use); and
                //          (2) be unlikely to try to find a free port at the same time as another process because of the random delay.
                //
                // If the problem is caused by some other transient difficulty, retrying may solve that problem, too.
                
                unsigned i;
                for (  i=0; i<10; i++  ) {
                    
                    if (  i != 0  ) {
                        // Delay for a random time of up to 1.048576 seconds.
                        // Use a delay that is a power of two to avoid modulo bias (arc4random_uniform is available only on OS X 10.7 and higher)
                        
                        uint32_t randomDelayMicroseconds = arc4random() % (1024*1024);
                        fprintf(stderr, "Trying to start OpenVPN again, after a delay of %lu microseconds...\n",
                                (unsigned long) randomDelayMicroseconds);

                        usleep(randomDelayMicroseconds);
                    }
                    
                    retCode = startVPN(configFile,
                                       port,
                                       useScripts,
                                       skipScrSec,
                                       cfgLocCode,
                                       noMonitor,
                                       bitMask,
                                       leasewatchOptions,
                                       openvpnVersion);
                    
                    if (   (retCode == 0)               // If succeeded, return indicating that success
                        || ((bitMask & OPENVPNSTART_NOT_WHEN_COMPUTER_STARTS) != 0)  ) {// If failed and are using the GUI, return the failure
                        break;
                    }

                    //                                  // Otherwise (failed and started at system start without a GUI), try again up to 10 times
                }
                
                syntaxError = FALSE;
            }
        }
    }
    
	if (syntaxError) {
        printUsageMessageAndExitOpenvpnstart();
	}
	
	[pool drain];
	exit(retCode);
}
