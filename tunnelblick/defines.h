/*
 * Copyright 2010, 2011 Jonathan Bullard
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

// The admin group ID
#define ADMIN_GROUP_ID 80

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

//*************************************************************************************************
// Paths:

// NOTE: Several up scripts refer to the log directory without using this header file
#define L_AS_T_LOGS   @"/Library/Application Support/Tunnelblick/Logs"

#define L_AS_T_SHARED @"/Library/Application Support/Tunnelblick/Shared"
#define L_AS_T_USERS  @"/Library/Application Support/Tunnelblick/Users"

#define AUTHORIZED_RUNNING_PATH @"/tmp/tunnelblick-authorized-running"
#define AUTHORIZED_ERROR_PATH   @"/tmp/tunnelblick-authorized-error"

#define CONFIGURATION_UPDATES_BUNDLE_PATH  @"/Library/Application Support/Tunnelblick/Configuration Updates/Tunnelblick Configurations.bundle"

// NOTE: some up and down scripts refer to the following path without using this header file
#define DOWN_SCRIPT_NEEDS_TO_BE_RUN_PATH @"/tmp/tunnelblick-downscript-needs-to-be-run.txt"

// NOTE: tunnelblick-uninstaller.sh refers to the installer log path without using this header file
#define INSTALLER_LOG_PATH      @"/tmp/tunnelblick-installer-log.txt"

#define TOOL_PATH_FOR_CODESIGN @"/usr/bin/codesign"
#define TOOL_PATH_FOR_KEXTSTAT @"/usr/sbin/kextstat"
#define TOOL_PATH_FOR_PLUTIL   @"/usr/bin/plutil"

//*************************************************************************************************
// Characters in a configuration's display name that are not allowed
// Note that \000 - \037 and \177 are also prohibited, and that "(" and ")" _ARE_ allowed.
#define PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING                 "#&;:~|*?'\"~<>^[]{}$%"
#define PROHIBITED_DISPLAY_NAME_CHARACTERS_INCLUDING_SLASH_CSTRING "#&;:~|*?'\"~<>^[]{}$%/"

//*************************************************************************************************
// Extensions that (for private configurations) require 640 permissions and ownership by Admin group
// (Shared, Deploy, and alternate configurations are 0:0/600)
#define KEY_AND_CRT_EXTENSIONS [NSArray arrayWithObjects: @"cer", @"cert", @"crt", @"der", @"key", @"p12", @"p7b", @"p7c", @"pem", @"crl", @"pfx", nil]

//*************************************************************************************************
// Extensions that indicate that a file is in non-binary format -- ASCII, not binary
// OpenVPN configuration files and script files may have binary characters in comments, single- and double-quotes, and after backslashes.
#define NONBINARY_CONTENTS_EXTENSIONS [NSArray arrayWithObjects: @"crt", @"key", @"pem", @"crl", nil]

//*************************************************************************************************
// OpenVPN options that are not allowed because they conflict with the operation of Tunnelblick
#define OPENVPN_OPTIONS_THAT_ARE_PROHIBITED [NSArray arrayWithObjects: @"log", @"log-append", @"syslog", @"management", nil]

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
//                             (These folders are owned by <user>:Admin)
//
// _SECURED... entries are for /Library/Application Support/Tunnelblick/Shared/,
//                             /Library/Application Support/Tunnelblick/Users/username/,
//                             /Library/Application Support/Tunnelblick/Backup/
//                             /Applications/XXXXX.app/Contents/Resources/Deploy/
//                             (These folders are owned by root:wheel)
//
// _SELF           entries are for the folder itself (if not a .tblk folder
// _TBLK_FOLDER    entries are for folders with the .tblk extension and their subfolders
// _PRIVATE_FOLDER entries are for folders IN .../Users/username/
// _PUBLIC_FOLDER  entries are for all other folders
// _SCRIPT         entries are for files with the .sh extension
// _EXECUTABLE     entries are for files with the .executable extension (in Deploy folders only)
// _OTHER          entries are for all other files


#define PERMS_PRIVATE_SELF           0750
#define PERMS_PRIVATE_TBLK_FOLDER    0750
#define PERMS_PRIVATE_PRIVATE_FOLDER 0750
#define PERMS_PRIVATE_PUBLIC_FOLDER  0750
#define PERMS_PRIVATE_SCRIPT         0740
#define PERMS_PRIVATE_EXECUTABLE     0740
#define PERMS_PRIVATE_FORCED_PREFS   0740
#define PERMS_PRIVATE_OTHER          0640

#define PERMS_SECURED_SELF           0755
#define PERMS_SECURED_TBLK_FOLDER    0750
#define PERMS_SECURED_PRIVATE_FOLDER 0750
#define PERMS_SECURED_PUBLIC_FOLDER  0755
#define PERMS_SECURED_SCRIPT         0700
#define PERMS_SECURED_EXECUTABLE     0711
#define PERMS_SECURED_FORCED_PREFS   0644
#define PERMS_SECURED_OTHER          0600


//*************************************************************************************************
// Values for the location of the configuration file (cfgLocCode argument to openvpnstart) 
#define CFG_LOC_PRIVATE   0
#define CFG_LOC_ALTERNATE 1
#define CFG_LOC_DEPLOY    2
#define CFG_LOC_SHARED    3
#define CFG_LOC_MAX       3


//*************************************************************************************************
// Bit masks for bitMask parameter of openvpnstart's start, loadkexts, and unloadkexts sub-commands
#define OPENVPNSTART_OUR_TUN_KEXT              0x0001u
#define OPENVPNSTART_OUR_TAP_KEXT              0x0002u

#define OPENVPNSTART_KEXTS_MASK_LOAD_DEFAULT   0x0003u
#define OPENVPNSTART_KEXTS_MASK_LOAD_MAX       0x0003u

#define OPENVPNSTART_FOO_TUN_KEXT              0x0004u
#define OPENVPNSTART_FOO_TAP_KEXT              0x0008u

#define OPENVPNSTART_KEXTS_MASK_UNLOAD_DEFAULT 0x0003u
#define OPENVPNSTART_KEXTS_MASK_UNLOAD_MAX     0x000Fu

#define OPENVPNSTART_RESTORE_ON_DNS_RESET      0x0010u
#define OPENVPNSTART_RESTORE_ON_WINS_RESET     0x0020u
#define OPENVPNSTART_USE_TAP                   0x0040u
#define OPENVPNSTART_PREPEND_DOMAIN_NAME       0x0080u
#define OPENVPNSTART_FLUSH_DNS_CACHE           0x0100u
#define OPENVPNSTART_USE_REDIRECT_GATEWAY_DEF1 0x0200u
#define OPENVPNSTART_RESET_PRIMARY_INTERFACE   0x0400u
#define OPENVPNSTART_TEST_MTU                  0x0800u
#define OPENVPNSTART_EXTRA_LOGGING             0x1000u
#define OPENVPNSTART_NO_DEFAULT_DOMAIN         0x2000u

#define OPENVPNSTART_START_BITMASK_MAX         0x3FFFu


//*************************************************************************************************
// Bit masks (and a shift count) for useScripts parameter of openvpnstart's start sub-command
#define OPENVPNSTART_USE_SCRIPTS_RUN_SCRIPTS        0x01
#define OPENVPNSTART_USE_SCRIPTS_USE_DOWN_ROOT      0x02

// (Mask first, then shift right)
#define OPENVPNSTART_USE_SCRIPTS_SCRIPT_MASK        0xFC
#define OPENVPNSTART_USE_SCRIPTS_SCRIPT_SHIFT_COUNT    2

#define OPENVPNSTART_USE_SCRIPTS_MAX                0xFF


//*************************************************************************************************
// Error return codes for openvpnstart
#define OPENVPNSTART_COMPARE_CONFIG_SAME             0
#define OPENVPNSTART_NO_SUCH_OPENVPN_PROCESS         248
#define OPENVPNSTART_REVERT_CONFIG_OK				 249
#define OPENVPNSTART_REVERT_CONFIG_MISSING			 250
#define OPENVPNSTART_COULD_NOT_START_OPENVPN         251
#define OPENVPNSTART_COMPARE_CONFIG_DIFFERENT        252
#define OPENVPNSTART_RETURN_SYNTAX_ERROR             253
#define OPENVPNSTART_RETURN_CONFIG_NOT_SECURED_ERROR 254


//*************************************************************************************************
// Bit masks for bitMask parameter of installer

#define INSTALLER_CLEAR_LOG				0x0001u

#define INSTALLER_COPY_APP              0x0002u

#define INSTALLER_SECURE_APP            0x0004u
#define INSTALLER_COPY_BUNDLE           0x0008u
#define INSTALLER_SECURE_TBLKS          0x0010u
#define INSTALLER_CONVERT_NON_TBLKS     0x0020u
#define INSTALLER_MOVE_LIBRARY_OPENVPN  0x0040u

#define INSTALLER_MOVE_NOT_COPY         0x1000u
#define INSTALLER_DELETE                0x2000u
#define INSTALLER_SET_VERSION           0x4000u


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
// Debugging macro to NSLog if a specified preference is TRUE
#define TBLog(preference_key, ...)     if (  [gTbDefaults boolForKey: preference_key] || [gTbDefaults boolForKey: @"DB-ALL"]  ) NSLog(@"DB: " __VA_ARGS__);

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
