/*
 * Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016 Jonathan K. Bullard. All rights reserved.
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

//*************************************************************************************************
// Misc:

// Set to TRUE to allow Tunnelblick to use openvpnstart's kill and killall subcommands
#define ALLOW_OPENVPNSTART_KILL    TRUE
#define ALLOW_OPENVPNSTART_KILLALL TRUE

// The maximum length of a display name for openvpnstart
#define DISPLAY_NAME_LENGTH_MAX 512

// The maximum 'argc' for openvpnstart
#define OPENVPNSTART_MAX_ARGC 11

// The "admin" and "staff" group IDs
#define ADMIN_GROUP_ID 80
#define STAFF_GROUP_ID 20

// The newline character as a unichar
#define UNICHAR_LF [@"\n" characterAtIndex:0]

// Maximum port number
#define MAX_PORT_NUMBER 65536

// Maximum hotKey index
#define MAX_HOTKEY_IX 12

// Minimum, maximum, and default log size (bytes)
#define MIN_LOG_SIZE_BYTES 10000
#define MAX_LOG_SIZE_BYTES 100000000
#define DEFAULT_LOG_SIZE_BYTES 102400

// Maximum number of entries to keep in the TunnelblickVersionsHistory preference
#define MAX_VERSIONS_IN_HISTORY 10

// Maximum index for the "Set DNS/WINS" dropdown box. Must be equal to the number of entries minus one.
#define MAX_SET_DNS_WINS_INDEX 4

// Header for commands to tunnelblickd that are to be handled by openvpnstart (note that this is a C-string, not an NSString)
#define TUNNELBLICKD_OPENVPNSTART_HEADER_C "openvpnstart: "

//*************************************************************************************************
// Paths:

// NOTE: Several up scripts refer to the log directory without using this header file
#define L_AS_T_LOGS   @"/Library/Application Support/Tunnelblick/Logs"

#define L_AS_T_SHARED @"/Library/Application Support/Tunnelblick/Shared"
#define L_AS_T_USERS  @"/Library/Application Support/Tunnelblick/Users"

#define L_AS_T_TBLKS  @"/Library/Application Support/Tunnelblick/Tblks"

#define L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH   @"/Library/Application Support/Tunnelblick/forced-preferences.plist"

#define L_AS_T_TUNNELBLICKD_HASH_PATH                 @"/Library/Application Support/Tunnelblick/tunnelblickd-hash.txt"
#define L_AS_T_TUNNELBLICKD_LAUNCHCTL_PLIST_HASH_PATH @"/Library/Application Support/Tunnelblick/tunnelblickd-launchctl-plist-hash.txt"

#define PADLOCK_ICON_PATH       @"/tmp/TunnelblickAuthIcon.png"

#define AUTHORIZED_RUNNING_PATH @"/tmp/tunnelblick-authorized-running"
#define AUTHORIZED_ERROR_PATH   @"/tmp/tunnelblick-authorized-error"

// NOTE: some up and down scripts refer to the following path without using this header file
#define DOWN_SCRIPT_NEEDS_TO_BE_RUN_PATH @"/tmp/tunnelblick-downscript-needs-to-be-run.txt"

// NOTE: tunnelblick-uninstaller.sh refers to the installer log path without using this header file
#define INSTALLER_LOG_PATH      @"/tmp/tunnelblick-installer-log.txt"

// NOTE: net.tunnelblick.tunnelblick.tunnelblickd.plist and tunnelblick-uninstaller.sh refer to the tunnelblickd log path without using this header file
// NOTE: The "_C" strings are C-strings, not NSStrings
#define TUNNELBLICKD_LOG_FOLDER @"/var/log/Tunnelblick"
#define TUNNELBLICKD_LOG_PATH_C "/var/log/Tunnelblick/tunnelblickd.log"
#define TUNNELBLICKD_PREVIOUS_LOG_PATH_C "/var/log/Tunnelblick/tunnelblickd.previous.log"

// NOTE: net.tunnelblick.tunnelblick.tunnelblickd.plist and tunnelblick-uninstaller.sh refer to the tunnelblickd socket path without using this header file
#define TUNNELBLICKD_SOCKET_PATH @"/var/run/net.tunnelblick.tunnelblick.tunnelblickd.socket"

// NOTE: tunnelblick-uninstaller.sh refers to the .plist path without using this header file
#define TUNNELBLICKD_PLIST_PATH @"/Library/LaunchDaemons/net.tunnelblick.tunnelblick.tunnelblickd.plist"

#define TOOL_PATH_FOR_ARCH       @"/usr/bin/arch"
#define TOOL_PATH_FOR_BASH       @"/bin/bash"
#define TOOL_PATH_FOR_CODESIGN   @"/usr/bin/codesign"
#define TOOL_PATH_FOR_DISKUTIL   @"/usr/sbin/diskutil"
#define TOOL_PATH_FOR_ID         @"/usr/bin/id"
#define TOOL_PATH_FOR_IFCONFIG   @"/sbin/ifconfig"
#define TOOL_PATH_FOR_KEXTLOAD   @"/sbin/kextload"
#define TOOL_PATH_FOR_KEXTSTAT   @"/usr/sbin/kextstat"
#define TOOL_PATH_FOR_KEXTUNLOAD @"/sbin/kextunload"
#define TOOL_PATH_FOR_KILLALL    @"/usr/bin/killall"
#define TOOL_PATH_FOR_LAUNCHCTL  @"/bin/launchctl"
#define TOOL_PATH_FOR_OSASCRIPT  @"/usr/bin/osascript"
#define TOOL_PATH_FOR_PLUTIL     @"/usr/bin/plutil"
#define TOOL_PATH_FOR_PS         @"/bin/ps"
#define TOOL_PATH_FOR_SCUTIL     @"/usr/sbin/scutil"

// The number of characters in each line of output from "ps -A" that are before the process' command line
#define PS_CHARACTERS_BEFORE_COMMAND  25

// Path with which tools are launched
#define STANDARD_PATH            @"/usr/bin:/bin:/usr/sbin:/sbin"

//*************************************************************************************************
// Characters in a configuration's display name that are not allowed
// Note that \000 - \037 and \177 are also prohibited, and that "(" and ")" _ARE_ allowed.
#define PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING                 "#&;:~|?'\"~<>^[]{}$%*"
#define PROHIBITED_DISPLAY_NAME_CHARACTERS_INCLUDING_SLASH_CSTRING "#&;:~|?'\"~<>^[]{}$%*/"
#define PROHIBITED_DISPLAY_NAME_CHARACTERS_WITHOUT_STAR_CSTRING    "#&;:~|?'\"~<>^[]{}$%"

// Characters that are allowed in a domain name (and thus, a CFBundleIdentifier)
#define ALLOWED_DOMAIN_NAME_CHARACTERS @".-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

// Characters that are allowed in an OpenVPN version folder name
#define ALLOWED_OPENVPN_VERSION_CHARACTERS @"._-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

//*************************************************************************************************
// Extensions that (for private configurations) require 640 permissions and ownership by Admin group
// (Shared, Deploy, and alternate configurations are 0:0/600)
#define KEY_AND_CRT_EXTENSIONS [NSArray arrayWithObjects: @"cer", @"cert", @"crt", @"der", @"key", @"p12", @"p7b", @"p7c", @"pem", @"crl", @"pfx", @"unknown", nil]

//*************************************************************************************************
// Extensions for files that should be copied when installing a .tblk
#define TBLK_INSTALL_EXTENSIONS [NSArray arrayWithObjects: @"cer", @"cert", @"crt", @"der", @"key", @"p12", @"p7b", @"p7c", @"pem", @"crl", @"pfx", @"sh", @"lproj", @"unknown", nil]

//*************************************************************************************************
// Extensions that indicate that a file is in non-binary format -- ASCII, not binary
// OpenVPN configuration files and script files may have binary characters in comments, single- and double-quotes, and after backslashes.
#define NONBINARY_CONTENTS_EXTENSIONS [NSArray arrayWithObjects: @"crt", @"key", @"pem", @"crl", nil]

//*************************************************************************************************
// Extensions for non-configuration files that may have the CR in CR-LF sequences removed, and other CR characters changed to LF
#define CONVERT_CR_CHARACTERS_EXTENSIONS [NSArray arrayWithObjects: @"crt", @"key", @"pem", @"crl", @"sh", nil]

//*************************************************************************************************
// OpenVPN options that are not allowed because they conflict with the operation of Tunnelblick
#define OPENVPN_OPTIONS_THAT_CAN_ONLY_BE_USED_BY_TUNNELBLICK [NSArray arrayWithObjects: @"log", @"log-append", @"syslog", @"management", nil]

//*************************************************************************************************
// OpenVPN options that are not allowed on OS X
#define OPENVPN_OPTIONS_THAT_ARE_WINDOWS_ONLY [NSArray arrayWithObjects: @"allow-nonadmin", @"cryptoapicert", @"dhcp-release", @"dhcp-renew", @"pause-exit", @"register-dns", @"service", @"show-adapters", @"show-net", @"show-net-up", @"show-valid-subnets", @"tap-sleep", @"win-sys", nil]

//*************************************************************************************************
// Tunnelblick and OpenVPN logging levels, stored in the per-configuration "-loggingLevel" preference.
// Levels from 0...11 are passed to OpenVPN in the --verb option and Tunnelblick does logging
// At TUNNELBLICK_CONFIG_LOGGING_LEVEL, Tunnelblick does logging but does not set --verb, so the OpenVPN default or the configuration file setting is used
// At TUNNELBLICK_NO_LOGGING_LEVEL, Tunnelblick does no logging and the OpenVPN log is sent to /dev/null, which overrides any --verb settings
#define MIN_OPENVPN_LOGGING_LEVEL          0
#define MAX_OPENVPN_LOGGING_LEVEL         11
#define TUNNELBLICK_NO_LOGGING_LEVEL      12
#define TUNNELBLICK_CONFIG_LOGGING_LEVEL  13
#define MAX_TUNNELBLICK_LOGGING_LEVEL     13

#define TUNNELBLICK_DEFAULT_LOGGING_LEVEL  3

//*************************************************************************************************
// Permissions for files and folders
//
// These are used in four places:
//       MenuController's function needToSecureFolderAtPath()
//       openvpnstart's   function exitIfTblkNeedsRepair()
//       sharedRoutine's  function secureOneFolder()
//       installer
//
// _PRIVATE... entries are for ~/Library/Application Support/Tunnelblick/Configurations
//                             (These folders are owned by <user>:admin)
//
// _PRIVATE_REMOTE... entries are for ~/Library/Application Support/Tunnelblick/Configurations
//                                when it is on a network volume. (These folders are owned by <user>:staff)
//
// _SECURED... entries are for /Library/Application Support/Tunnelblick/Shared/,
//                             /Library/Application Support/Tunnelblick/Tblks,
//                             /Library/Application Support/Tunnelblick/Users/username/,
//                             /Library/Application Support/Tunnelblick/Backup/
//                             /Applications/XXXXX.app/Contents/Resources/Deploy/
//                             (These folders are owned by root:wheel)
//
// _FOLDER     entries are for folders
// _SCRIPT     entries are for files with the .sh extension
// _EXECUTABLE entries are for files with the .executable extension (in Deploy folders only)
// _READABLE   entries are for files (such as Info.plist files) that should be readable (by owner/group in private configurations, by everyone everywhere else)
// _OTHER      entries are for all other files


#define PERMS_PRIVATE_FOLDER     0750
#define PERMS_PRIVATE_SCRIPT     0740
#define PERMS_PRIVATE_EXECUTABLE 0740
#define PERMS_PRIVATE_READABLE   0740
#define PERMS_PRIVATE_OTHER      0740

#define PERMS_PRIVATE_REMOTE_FOLDER     0700
#define PERMS_PRIVATE_REMOTE_SCRIPT     0700
#define PERMS_PRIVATE_REMOTE_EXECUTABLE 0700
#define PERMS_PRIVATE_REMOTE_READABLE   0700
#define PERMS_PRIVATE_REMOTE_OTHER      0700

#define PERMS_SECURED_FOLDER     0755
#define PERMS_SECURED_SCRIPT     0700
#define PERMS_SECURED_EXECUTABLE 0755
#define PERMS_SECURED_ROOT_EXEC  0744
#define PERMS_SECURED_READABLE   0644
#define PERMS_SECURED_OTHER      0700


//*************************************************************************************************
// Values for the location of the configuration file (cfgLocCode argument to openvpnstart) 
#define CFG_LOC_PRIVATE   0
#define CFG_LOC_ALTERNATE 1
#define CFG_LOC_DEPLOY    2
#define CFG_LOC_SHARED    3
#define CFG_LOC_MAX       3


//*************************************************************************************************
// Bit masks for bitMask parameter of openvpnstart's start, loadkexts, and unloadkexts sub-commands
#define OPENVPNSTART_OUR_TUN_KEXT              0x00000001u
#define OPENVPNSTART_OUR_TAP_KEXT              0x00000002u

#define OPENVPNSTART_KEXTS_MASK_LOAD_DEFAULT   (OPENVPNSTART_OUR_TUN_KEXT | OPENVPNSTART_OUR_TAP_KEXT)
#define OPENVPNSTART_KEXTS_MASK_LOAD_MAX       (OPENVPNSTART_OUR_TUN_KEXT | OPENVPNSTART_OUR_TAP_KEXT)

#define OPENVPNSTART_FOO_TUN_KEXT              0x00000004u
#define OPENVPNSTART_FOO_TAP_KEXT              0x00000008u

#define OPENVPNSTART_KEXTS_MASK_UNLOAD_DEFAULT (OPENVPNSTART_FOO_TUN_KEXT | OPENVPNSTART_FOO_TAP_KEXT)
#define OPENVPNSTART_KEXTS_MASK_UNLOAD_MAX     (OPENVPNSTART_OUR_TUN_KEXT | OPENVPNSTART_OUR_TAP_KEXT | OPENVPNSTART_FOO_TUN_KEXT | OPENVPNSTART_FOO_TAP_KEXT)

#define OPENVPNSTART_RESTORE_ON_DNS_RESET      0x00000010u
#define OPENVPNSTART_RESTORE_ON_WINS_RESET     0x00000020u
#define OPENVPNSTART_USE_TAP                   0x00000040u
#define OPENVPNSTART_PREPEND_DOMAIN_NAME       0x00000080u
#define OPENVPNSTART_FLUSH_DNS_CACHE           0x00000100u
#define OPENVPNSTART_USE_REDIRECT_GATEWAY_DEF1 0x00000200u
#define OPENVPNSTART_RESET_PRIMARY_INTERFACE   0x00000400u
#define OPENVPNSTART_TEST_MTU                  0x00000800u
#define OPENVPNSTART_EXTRA_LOGGING             0x00001000u
#define OPENVPNSTART_NO_DEFAULT_DOMAIN         0x00002000u
#define OPENVPNSTART_NOT_WHEN_COMPUTER_STARTS  0x00004000u
#define OPENVPNSTART_USE_ROUTE_UP_NOT_UP       0x00008000u
//                                             0x00010000u  UNUSED, was OPENVPNSTART_USE_I386_OPENVPN
#define OPENVPNSTART_WAIT_FOR_DHCP_IF_TAP      0x00020000u
#define OPENVPNSTART_DO_NOT_WAIT_FOR_INTERNET  0x00040000u
#define OPENVPNSTART_ENABLE_IPV6_ON_TAP        0x00080000u
#define OPENVPNSTART_DISABLE_IPV6_ON_TUN       0x00100000u
#define OPENVPNSTART_DISABLE_LOGGING           0x00200000u
// DUPLICATE THE HIGHEST VALUE BELOW           vvvvvvvvvvv
#define OPENVPNSTART_HIGHEST_BITMASK_BIT       0x00200000u


//*************************************************************************************************
// Bit masks (and shift counts) for useScripts parameter of openvpnstart's start sub-command
#define OPENVPNSTART_USE_SCRIPTS_RUN_SCRIPTS        0x01
#define OPENVPNSTART_USE_SCRIPTS_USE_DOWN_ROOT      0x02

// (Mask first, then shift right)
#define OPENVPNSTART_USE_SCRIPTS_SCRIPT_MASK        0x00FC
#define OPENVPNSTART_USE_SCRIPTS_SCRIPT_SHIFT_COUNT      2

#define OPENVPNSTART_VERB_LEVEL_SCRIPT_MASK         0x0F00
#define OPENVPNSTART_VERB_LEVEL_SHIFT_COUNT              8

#define OPENVPNSTART_USE_SCRIPTS_MAX                0x0FFF


//*************************************************************************************************
// Error return codes for openvpnstart
#define OPENVPNSTART_COMPARE_CONFIG_SAME             0
#define OPENVPNSTART_REVERT_CONFIG_OK				 0
#define OPENVPNSTART_UPDATE_SAFE_OK                  0
#define OPENVPNSTART_NO_SUCH_OPENVPN_PROCESS         248
#define OPENVPNSTART_UPDATE_SAFE_NOT_OK              249
#define OPENVPNSTART_REVERT_CONFIG_MISSING			 250
#define OPENVPNSTART_COULD_NOT_START_OPENVPN         251
#define OPENVPNSTART_COMPARE_CONFIG_DIFFERENT        252
#define OPENVPNSTART_RETURN_SYNTAX_ERROR             253
#define OPENVPNSTART_RETURN_CONFIG_NOT_SECURED_ERROR 254

//*************************************************************************************************
// Indices of arguments that are included in the in 'openvpnstartArgs' part of the name of OpenVPN log files
// The arguments are all positive integers and are separated by '_' characters for easy parsing via componentsSeparatedByString
#define OPENVPNSTART_LOGNAME_ARG_USE_SCRIPTS_IX  0
#define OPENVPNSTART_LOGNAME_ARG_SkIP_SCR_SEC_IX 1
#define OPENVPNSTART_LOGNAME_ARG_CFG_LOC_CODE_IX 2
#define OPENVPNSTART_LOGNAME_ARG_NO_MONITOR_IX   3
#define OPENVPNSTART_LOGNAME_ARG_BITMASK_IX      4

#define OPENVPNSTART_LOGNAME_ARG_COUNT 5

// Indices of the actual arguments to openvpnstart
#define OPENVPNSTART_ARG_START_KEYWORD_IX 0
#define OPENVPNSTART_ARG_CONFIG_FILE_IX   1
#define OPENVPNSTART_ARG_PORT_IX          2
#define OPENVPNSTART_ARG_USE_SCRIPTS_IX   3
#define OPENVPNSTART_ARG_SkIP_SCR_SEC_IX  4
#define OPENVPNSTART_ARG_CFG_LOC_CODE_IX  5
#define OPENVPNSTART_ARG_NO_MONITOR_IX    6
#define OPENVPNSTART_ARG_BITMASK_IX       7


//*************************************************************************************************
// Bit masks for bitMask parameter of installer

#define INSTALLER_CLEAR_LOG				     0x0001u

#define INSTALLER_COPY_APP                   0x0002u

#define INSTALLER_SECURE_APP                 0x0004u
//                                           0x0008u  UNUSED, was "INSTALLER_HELPER_IS_TO_BE_SUID"
#define INSTALLER_SECURE_TBLKS               0x0010u
#define INSTALLER_CONVERT_NON_TBLKS          0x0020u
#define INSTALLER_MOVE_LIBRARY_OPENVPN       0x0040u
#define INSTALLER_INSTALL_FORCED_PREFERENCES 0x0080u
#define INSTALLER_REPLACE_DAEMON             0x0100u

#define INSTALLER_MOVE_NOT_COPY              0x1000u
#define INSTALLER_DELETE                     0x2000u


//*************************************************************************************************
// Size to use to minimize the left navigation area when it is inactive
#define LEFT_NAV_AREA_MINIMAL_SIZE 8.0

//*************************************************************************************************
// Minimum size of the left navigation area when it is active
#define LEFT_NAV_AREA_MINIMUM_SIZE 40.0

//*************************************************************************************************
// Maximum number of tabs to allow when left up to the program
#define MAX_TABS_LIMIT 8

//*************************************************************************************************
// Return values for StatusWindowController
typedef enum
{
	statusWindowControllerDisconnectChoice,
    statusWindowControllerConnectChoice,
} StatusWindowControllerChoice;


//*************************************************************************************************
#define CSTRING_FROM_BOOL(arg) (  (arg) ? "YES" : "NO"  )


//*************************************************************************************************
// Debugging macro to NSLog if a specified preference is TRUE
#define TBLog(preference_key, ...)     if (  [gTbDefaults boolForKey: preference_key] || [gTbDefaults boolForKey: @"DB-ALL"]  ) NSLog(preference_key @": "  __VA_ARGS__);

//*************************************************************************************************
// Tiger-compatible macros that implement something like @property and @synthesize
//
// The 'type' argument is the type of the variable
// The 'name' and 'setname' arguments are the name of the variable and the name with initial capital prefixed by set
// The 'copyRetain' argument is either copy or retain
//
// Note that objects and non-objects use different TBSYNTHESIZE... macros

#define TBPROPERTY(type, name, setname) \
-(type) name;                           \
-(void) setname: (type) newValue;       \


#define TBPROPERTY_READONLY(type, name) \
-(type) name;                           \


#define TBPROPERTY_WRITEONLY(type, name, setname) \
-(void) setname: (type) newValue;                 \



#define TBSYNTHESIZE_OBJECT(copyRetain, type, name, setname) \
-(type) name                                                 \
{                                                            \
return [[name copyRetain] autorelease];                  \
}                                                            \
\
-(void) setname: (type) newValue                             \
{                                                            \
[newValue retain];                                       \
[name release];                                          \
name = newValue;                                         \
}                                                            \


#define TBSYNTHESIZE_OBJECT_GET(copyRetain, type, name) \
-(type) name                                            \
{                                                       \
return [[name copyRetain] autorelease];             \
}                                                       \


#define TBSYNTHESIZE_OBJECT_SET(type, name, setname) \
-(void) setname: (type) newValue                     \
{                                                    \
[newValue retain];                               \
[name release];                                  \
name = newValue;                                 \
}                                                    \




#define TBSYNTHESIZE_NONOBJECT(type, name, setname) \
-(type) name                                        \
{                                                   \
return name;                                    \
}                                                   \
\
-(void) setname: (type) newValue                    \
{                                                   \
name = newValue;                                \
}


#define TBSYNTHESIZE_NONOBJECT_GET(type, name) \
-(type) name                                   \
{                                              \
return name;                               \
}                                              \


#define TBSYNTHESIZE_NONOBJECT_SET(type, name, setname) \
-(void) setname: (type) newValue                        \
{                                                       \
name = newValue;                                    \
}                                                       \


//*************************************************************************************************
// Comment out (with "//") the following line to EXclude the VPNService feature
//#define INCLUDE_VPNSERVICE 1
