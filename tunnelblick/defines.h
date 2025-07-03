/*
 * Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2023 Jonathan K. Bullard. All rights reserved.
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

#define LOWEST_MACOS_THAT_CANNOT_LOAD_KEXTS @"9999.99"

// Set to TRUE to allow Tunnelblick to use openvpnstart's kill and killall subcommands
#define ALLOW_OPENVPNSTART_KILL    TRUE
#define ALLOW_OPENVPNSTART_KILLALL TRUE

// The maximum length of a display name for openvpnstart
#define DISPLAY_NAME_LENGTH_MAX 512

// The maximum 'argc' for openvpnstart
#define OPENVPNSTART_MAX_ARGC 12

// The "admin" and "staff" group IDs
#define ADMIN_GROUP_ID 80
#define STAFF_GROUP_ID 20

// The newline character as a unichar
#define UNICHAR_LF [@"\n" characterAtIndex:0]

// Range of ports to be used to connect to the OpenVPN management interface.
// We chose one dynamic/private/ephemeral port per connection at random within this range.
// (See https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml)
#define MIN_MANAGMENT_INTERFACE_PORT_NUMBER 49152
#define MAX_MANAGMENT_INTERFACE_PORT_NUMBER 65535

// Maximum length of a response from https://tunnelblick.net/ipinfo
// Will be IP,port#,IP. An IPv6 addresses takes up to 39 bytes, port# up to five, and two commas separating the three items, so 78 + 5 + 2 = 85 bytes.
// So we use 90 to give ourself some breathing room (to allow CR-LF at the end, for example, although ipinfo currently doesn't return one).
#define TUNNELBLICK_DOT_NET_IPINFO_RESPONSE_MAX_LENGTH 90

// Maximum sizes in bytes for an appcast and an update .zip. Only used as sanity check, so very generous:
// (In early 2024, appcasts were a few KB, update .zips were about 20 MB)
#define TB_APPCAST_MAX_FILE_SIZE ( (long long)(1024 * 1024) )
#define TB_UPDATE_MAX_ZIP_FILE_SIZE ( (long long)(80 * 1024 * 1024) )

// Minimum and maximum length of an update to Tunnelblick (size of .zip file).
// Used to make sure we don't try to download too little or too much.
// Tunnelblick 5.0.1beta02 is about 18 MB.
#define MINIMUM_APP_UPDATE_LENGTH ( 10*1024*1024)
#define MAXIMUM_APP_UPDATE_LENGTH ( 50*1024*1024)

#define SECONDS_PER_DAY ( 24 * 60 * 60 )

#define SECONDS_BETWEEN_CHECKS_FOR_TUNNELBLICK_UPDATES (24*60*60.0)

#define ONE_TENTH_OF_A_SECOND_IN_MICROSECONDS 100000

#define LENGTH_OF_YYYY_MM_DD ( 4 + 1 + 2 + 1 + 2 )

// Number of characters/columns taken up by the date & time in the Tunnelblick log
//    If == 19, microseconds are not included (e.g., "2019-03-08 09:30:15")
//    If == 26, microseconds are included     (e.g., "2019-03-08 09:30:15.123456")
//              OTHER VALUES WILL CAUSE PROBLEMS
#define TB_LOG_DATE_TIME_WIDTH 26

// Prefix log entries from Tunnelblick itself (as opposed to OpenVPN) with this string.
#define TB_LOG_PREFIX @"*Tunnelblick: "

// Suffix added to an OpenVPN name to indicate it is in L_AS_T_OPENVPN instead of in Tunnelblick.app/Contents/Resources/openvpn
#define SUFFIX_FOR_OPENVPN_BINARY_IN_L_AS_T_OPENVPN @"EXTERNAL"

// Maximum hotKey index
#define MAX_HOTKEY_IX 12

// Socket buffer size for tunnelblickd. password + prefix + command must fit in this
#define SOCKET_BUF_SIZE 2048

// Limited because we create a popup button which lists all of them
#define MAX_NUMBER_OF_TARGET_USERNAMES_FOR_IMPORT_WINDOW 64

// Minimum, maximum, and default log size (bytes)
#define MIN_LOG_SIZE_BYTES 10000
#define MAX_LOG_SIZE_BYTES 100000000
#define DEFAULT_LOG_SIZE_BYTES 102400

// Maximum length in bytes of a parameter to the OpenVPN management interface (e.g., username, password, passphrase)
#define MAX_LENGTH_OF_MANGEMENT_INTERFACE_PARAMETER   255

// This maximum is four bytes less, to account for enclosing the parameter in escaped double-quotes (  \"username\" is sent)
#define MAX_LENGTH_OF_QUOTED_MANGEMENT_INTERFACE_PARAMETER   (MAX_LENGTH_OF_MANGEMENT_INTERFACE_PARAMETER - 4)

#define MAX_LENGTH_OF_CREDENTIALS_NAME 200
#define MAX_LENGTH_OF_DISPLAY_NAME     400

// Maximum number of entries to keep in the TunnelblickVersionsHistory preference
#define MAX_VERSIONS_IN_HISTORY 10

// Values for useDNS preference, also used as indices for the "Set DNS/WINS" dropdown box

#define USEDNS_DO_NOT_SET_NAMESERVER    0
#define USEDNS_SET_NAMSERVER            1
#define USEDNS_SET_NAMESERVER_3_1       2
#define USEDNS_SET_NAMESERVER_3_0_B10   3
#define USEDNS_SET_NAMESERVER_ALT_1     4
#define USEDNS_SET_NAMESERVER_ALT_2     5
#define USEDNS_SET_NAMESERVER_OPENVPN   6

// Maximum index for the "Set DNS/WINS" dropdown box. Must be equal to the number of entries minus 1.
#define MAX_SET_DNS_WINS_INDEX 6

// Mapping from useDNS preference to 'up' and 'down' script names (-1 means don't use a script)
#define MAP_USEDNS_TO_UP_DOWN_SCRIPT_NUMBER   {-1, 0, 1, 2, 3, 4, 5}

// Header for commands to tunnelblickd that are to be handled by openvpnstart (note that this is a C-string, not an NSString)
#define TUNNELBLICKD_OPENVPNSTART_HEADER_C "openvpnstart: "

// Drag ID for drag and drop of items in the list of configurations in the "Preferences" panel of the "VPN Details" window
#define TB_LEFT_NAV_ITEMS_DRAG_ID @"net.tunnelblick.tunnelblick.leftnav.drag"

// String containing all whitespace characters in an OpenVPN configuration file
#define WHITESPACE_CHARACTERS_IN_OPENVPN_CONFIGURATION_FILE @"\t\n\r "

//*************************************************************************************************
// Paths:

#define APPLICATIONS_TB_APP   @"/Applications/Tunnelblick.app"

#define L_AS_T        @"/Library/Application Support/Tunnelblick"

#define L_AS_T_TB_APP   @"/Library/Application Support/Tunnelblick/Tunnelblick.app"
#define L_AS_T_TB_OLD   @"/Library/Application Support/Tunnelblick/Tunnelblick-old.app"
#define L_AS_T_TB_NEW   @"/Library/Application Support/Tunnelblick/Tunnelblick-new.app"

// NOTE: Several up scripts refer to the log directory without using this header file
#define L_AS_T_LOGS   @"/Library/Application Support/Tunnelblick/Logs"

#define L_AS_T_SHARED @"/Library/Application Support/Tunnelblick/Shared"
#define L_AS_T_USERS  @"/Library/Application Support/Tunnelblick/Users"

#define L_AS_T_TBLKS  @"/Library/Application Support/Tunnelblick/Tblks"

#define L_AS_T_MIPS  @"/Library/Application Support/Tunnelblick/Mips"

#define L_AS_T_OPENVPN  @"/Library/Application Support/Tunnelblick/Openvpn"

#define L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH        @"/Library/Application Support/Tunnelblick/forced-preferences.plist"

#define L_AS_T_DEBUG_APP_RESOURCES_PATH               @"/Library/Application Support/Tunnelblick/debug-app-resources-path.txt"

#define L_AS_T_TUNNELBLICKD_HASH_PATH                 @"/Library/Application Support/Tunnelblick/tunnelblickd-hash.txt"
#define L_AS_T_TUNNELBLICKD_LAUNCHCTL_PLIST_HASH_PATH @"/Library/Application Support/Tunnelblick/tunnelblickd-launchctl-plist-hash.txt"

#define TUNNELBLICK_QUIT_LOG_PATH        [NSHomeDirectory() stringByAppendingPathComponent: @"/Library/Application Support/Tunnelblick/TBLogs/tunnelblick-quit-log.txt"]
#define TUNNELBLICK_LOG_PATH             [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Application Support/Tunnelblick/TBLogs/tunnelblick-log.txt"]
#define TUNNELBLICK_OLD_LOG_PATH         [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Application Support/Tunnelblick/TBLogs/tunnelblick-log-old.txt"]
#define OPENVPNSTART_LOG_PATH            [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Application Support/Tunnelblick/TBLogs/tunnelblick-openvpnstart-log.txt"]
#define TUNNELBLICK_UPDATER_LOG_PATH     [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Application Support/Tunnelblick/TBLogs/tunnelblick-updater-log.txt"]
#define TUNNELBLICK_UPDATER_OLD_LOG_PATH [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Application Support/Tunnelblick/TBLogs/tunnelblick-updater-log-old.txt"]

// NOTE: installer and tunnelblick-helper calculate the following path without using this macro because they use a specified username instead of using NSHomeDirectory()
#define TUNNELBLICK_UPDATER_ZIP_PATH [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Application Support/Tunnelblick/tunnelblick-update.zip"]

// NOTE: some scripts refer to the following paths without using this header file
#define L_AS_T_DISABLED_NETWORK_SERVICES_PATH         @"/Library/Application Support/Tunnelblick/disabled-network-services.txt"
#define L_AS_T_EXPECT_DISCONNECT_FOLDER_PATH          @"/Library/Application Support/Tunnelblick/expect-disconnect"
#define AUTHORIZED_DONE_PATH                          @"/Library/Application Support/Tunnelblick/tunnelblick-authorized-done"
#define DOWN_SCRIPT_NEEDS_TO_BE_RUN_PATH              @"/Library/Application Support/Tunnelblick/downscript-needs-to-be-run.txt"
#define INSTALLER_LOG_PATH                            @"/Library/Application Support/Tunnelblick/tunnelblick-installer-log.txt"
#define INSTALLER_OLD_LOG_PATH                        @"/Library/Application Support/Tunnelblick/tunnelblick-installer-log-old.txt"
#define TUNNELBLICK_UPDATE_HELPER_LOG_PATH            @"/Library/Application Support/Tunnelblick/tunnelblick-updater-helper-log.txt"
#define TUNNELBLICK_UPDATE_HELPER_OLD_LOG_PATH        @"/Library/Application Support/Tunnelblick/tunnelblick-updater-helper-log-old.txt"

#define UNINSTALL_DETAILS_PATH                        @"/tmp/UninstallDetails.txt"

// NOTE: net.tunnelblick.tunnelblick.tunnelblickd.plist and tunnelblick-uninstaller.sh refer to the tunnelblickd log path without using this header file
// NOTE: The "_C" strings are C-strings, not NSStrings
#define TUNNELBLICKD_LOG_FOLDER            @"/var/log/Tunnelblick"
#define TUNNELBLICKD_LOG_PATH_C             "/var/log/Tunnelblick/tunnelblickd.log"
#define TUNNELBLICKD_PREVIOUS_LOG_PATH_C    "/var/log/Tunnelblick/tunnelblickd.previous.log"

// NOTE: net.tunnelblick.tunnelblick.tunnelblickd.plist and tunnelblick-uninstaller.sh refer to the tunnelblickd socket path without using this header file
#define TUNNELBLICKD_SOCKET_PATH @"/var/run/net.tunnelblick.tunnelblick.tunnelblickd.socket"

// NOTE: tunnelblick-uninstaller.sh refers to the .plist path without using this header file
#define TUNNELBLICKD_PLIST_PATH @"/Library/LaunchDaemons/net.tunnelblick.tunnelblick.tunnelblickd.plist"

#define TUNNELBLICKD_STDOUT_PATH @"/Library/Application Support/Tunnelblick/tunnelblickd-stdout.txt"
#define TUNNELBLICKD_STDERR_PATH @"/Library/Application Support/Tunnelblick/tunnelblickd-stderr.txt"

#define TOOL_PATH_FOR_ARCH			@"/usr/bin/arch"
#define TOOL_PATH_FOR_BASH			@"/bin/bash"
#define TOOL_PATH_FOR_CODESIGN		@"/usr/bin/codesign"
#define TOOL_PATH_FOR_CSRUTIL		@"/usr/bin/csrutil"
#define TOOL_PATH_FOR_DISKUTIL		@"/usr/sbin/diskutil"
#define TOOL_PATH_FOR_FILE          @"/usr/bin/file"
#define TOOL_PATH_FOR_ID			@"/usr/bin/id"
#define TOOL_PATH_FOR_IFCONFIG		@"/sbin/ifconfig"
#define TOOL_PATH_FOR_KEXTSTAT		@"/usr/sbin/kextstat"
#define TOOL_PATH_FOR_KEXTUNLOAD    @"/sbin/kextunload"
#define TOOL_PATH_FOR_KILLALL		@"/usr/bin/killall"
#define TOOL_PATH_FOR_LAUNCHCTL		@"/bin/launchctl"
#define TOOL_PATH_FOR_NETWORKSETUP	@"/usr/sbin/networksetup"
#define TOOL_PATH_FOR_OPEN          @"/usr/bin/open"
#define TOOL_PATH_FOR_OSASCRIPT		@"/usr/bin/osascript"
#define TOOL_PATH_FOR_PLUTIL		@"/usr/bin/plutil"
#define TOOL_PATH_FOR_PS			@"/bin/ps"
#define TOOL_PATH_FOR_ROUTE         @"/sbin/route"
#define TOOL_PATH_FOR_SCUTIL		@"/usr/sbin/scutil"
#define TOOL_PATH_FOR_SQLITE3		@"/usr/bin/sqlite3"
#define TOOL_PATH_FOR_SW_VERS		@"/usr/bin/sw_vers"
#define TOOL_PATH_FOR_TAR			@"/usr/bin/tar"

// Strings returned by architecturesForExecutable() for supported architectures
#define ARCH_X86 @"x86_64"
#define ARCH_ARM @"arm64"
#define ARCH_ALL @"x86_64 arm64"

// The number of characters in each line of output from "ps -A" that are before the process' command line
#define PS_CHARACTERS_BEFORE_COMMAND  25

// Path with which tools are launched
#define STANDARD_PATH            @"/usr/bin:/bin:/usr/sbin:/sbin"

//*************************************************************************************************
// Characters in a configuration's display name that are not allowed
// Note that \000 - \037 and \177 are also prohibited, and that "(" and ")" _ARE_ allowed.
#define PROHIBITED_DISPLAY_NAME_CHARACTERS_CSTRING                 "\\!#&;:~|?'\"~<>^[]{}$%*"
#define PROHIBITED_DISPLAY_NAME_CHARACTERS_WITH_SPACES_CSTRING     "\\ ! # & ; : ~ | ? ' \" ~ < > ^ [ ] { } $ % *"
#define PROHIBITED_DISPLAY_NAME_CHARACTERS_INCLUDING_SLASH_CSTRING "\\!#&;:~|?'\"~<>^[]{}$%*/"
#define PROHIBITED_DISPLAY_NAME_CHARACTERS_INCLUDING_SLASH_WITH_SPACES_CSTRING "\\ ! # & ; : ~ | ? ' \" ~ < > ^ [ ] { } $ % * /"

// Characters that are allowed in a domain name (and thus, a CFBundleIdentifier)
#define ALLOWED_DOMAIN_NAME_CHARACTERS @".-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

// Characters that are allowed in an OpenVPN version folder name
#define ALLOWED_OPENVPN_VERSION_CHARACTERS @"._-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

//*************************************************************************************************
// Extensions that (for private configurations) require 640 permissions and ownership by Admin group
// (Shared, Deploy, and alternate configurations are 0:0/600)
#define KEY_AND_CRT_EXTENSIONS @[@"cer", @"cert", @"crt", @"der", @"key", @"p12", @"p7b", @"p7c", @"pem", @"crl", @"pfx", @"unknown"]

//*************************************************************************************************
// Extensions for files that should be copied when installing a .tblk
#define TBLK_INSTALL_EXTENSIONS @[@"cer", @"cert", @"crt", @"der", @"key", @"p12", @"p7b", @"p7c", @"pem", @"crl", @"pfx", @"sh", @"lproj", @"unknown"]

//*************************************************************************************************
// Extensions that indicate that a file is in non-binary format -- ASCII, not binary
// OpenVPN configuration files and script files may have binary characters in comments, single- and double-quotes, and after backslashes.
#define NONBINARY_CONTENTS_EXTENSIONS @[@"crt", @"key", @"pem", @"crl"]

//*************************************************************************************************
// Extensions for non-configuration files that may have the CR in CR-LF sequences removed, and other CR characters changed to LF
#define CONVERT_CR_CHARACTERS_EXTENSIONS @[@"crt", @"key", @"pem", @"crl", @"sh"]

//*************************************************************************************************
// OpenVPN options that are not allowed because they conflict with the operation of Tunnelblick
#define OPENVPN_OPTIONS_THAT_CAN_ONLY_BE_USED_BY_TUNNELBLICK @[@"log", @"log-append", @"syslog", @"config"]

//*************************************************************************************************
// OpenVPN options that are not allowed on macOS
#define OPENVPN_OPTIONS_THAT_ARE_WINDOWS_ONLY @[@"allow-nonadmin", @"cryptoapicert", @"dhcp-release", @"dhcp-renew", @"pause-exit", \
                                                @"register-dns", @"service", @"show-adapters", @"show-net", @"show-net-up", \
                                                @"show-valid-subnets", @"tap-sleep", @"win-sys", @"windows-driver"]

//*************************************************************************************************
// OpenVPN options that cannot appear in a "safe" configuration
//
// NOTE: dns-updown MAY OR MAY NOT BE SAFE AND IS NOT IN THIS LIST !!!
//
//       dns-updown force
//   and dns-updown disable ARE SAFE
//
//       dns-updown <command> IS NOT SAFE!

#define OPENVPN_OPTIONS_THAT_ARE_UNSAFE @[ \
@"auth-user-pass-verify", @"client-connect", @"client-crresponse", @"client-disconnect", \
@"config", @"dns-script", @"down", @"ipchange", @"iproute", @"learn-address", \
@"plugin", @"route-pre-down", @"route-up", @"tls-verify", @"up" \
]

//*************************************************************************************************
// OpenVPN options that can appear in a "safe" configuration
#define OPENVPN_OPTIONS_THAT_ARE_SAFE @[ \
@"allow-compression", @"allow-nonadmin", @"allow-pull-fqdn", @"allow-recursive-routing", @"askpass", \
@"auth-gen-token",@"auth-nocache",@"auth-retry",@"auth-token",@"auth-token-user",@"auth-user-pass-optional", \
/* UNSAFE: @"auth-user-pass-verify", */ \
@"auth-user-pass", @"auth", @"auth-gen-token-secret", \
@"bcast-buffers", @"bind", @"bind-dev", @"block-ipv6", @"block-outside-dns", \
@"ca", @"capath", @"ccd-exclusive", @"cd", @"cert", @"chroot", @"cipher", @"client-cert-not-required", \
@"client-config-dir", \
/* UNSAFE: @"client-connect", */ \
/* UNSAFE: @"client-crresponse", */ \
/* UNSAFE: @"client-disconnect", */ \
@"client-nat", @"client-to-client", @"client", @"comp-lzo", @"comp-noadapt", @"compat-names", \
@"compress", \
/* UNSAFE: @"config",  */ \
@"connect-freq", @"connect-retry-max", @"connect-retry", @"connect-timeout", @"connection", \
@"crl-verify", @"cryptoapicert", @"daemon", @"data-ciphers", @"data-ciphers-fallback", \
@"dev-node", @"dev-type", @"dev", @"dh", @"dhcp-internal", @"dhcp-option", @"dhcp-pre-release", \
@"dhcp-release", @"dhcp-renew", @"disable-occ", @"disable", \
/* UNSAFE: @"dns-script", */ \
/* MAY BE UNSAFE: @"dns-updown", */ \
@"down-pre", \
/* UNSAFE: @"down", */ \
@"duplicate-cn", \
@"ecdh-curve", @"echo", @"engine", @"errors-to-stderr", @"explicit-exit-notify", @"extra-certs", \
@"fast-io", @"float", @"force-tls-key-material-export", @"foreign-option", @"fragment", \
@"genkey", @"gremlin", @"group", \
@"hand-window", @"hash-size", @"help", @"http-proxy-option", @"http-proxy-override", \
@"http-proxy-retry", @"http-proxy-timeout", @"http-proxy-user-pass", @"http-proxy", \
@"ifconfig-ipv6-pool", @"ifconfig-ipv6-push", @"ifconfig-ipv6", @"ifconfig-noexec", \
@"ifconfig-nowarn", @"ifconfig-pool-linear", @"ifconfig-pool-persist", @"ifconfig-pool"\
@"ifconfig-push-constraint", @"ifconfig-push", @"ifconfig", @"ignore-unknown-option", \
@"inactive", @"inetd", @"ip-remote-hint", @"ip-win32", \
/* UNSAFE: @"ipchange", */ \
/* UNSAFE: @"iproute", */ \
@"iroute-ipv6", @"iroute", \
@"keepalive", @"key-direction", @"key-method", @"key", @"key-derivation", \
@"keying-material-exporter", @"keysize", \
/* UNSAFE: @"learn-address", */ \
@"link-mtu", @"lladdr", @"local", @"log-append", @"log", @"lport", \
@"machine-readable-output", @"management-client-auth", @"management-client-group", \
@"management-client-pf", @"management-client-user", @"management-client", \
@"management-external-cert", @"management-external-key", @"management-forget-disconnect", \
@"management-hold", @"management-log-cache", @"management-query-passwords", @"management-query-proxy", \
@"management-query-remote", @"management-signal", @"management-up-down", @"management", @"mark", \
@"max-clients", @"max-routes-per-client", @"max-routes", @"memstats", @"mktun", @"mlock", @"mode", \
@"msg-channel", @"mssfix", @"mtu-disc", @"mtu-dynamic", @"mtu-test", @"multihome", \
@"mute-replay-warnings", @"mute", \
@"ncp-ciphers", @"ncp-disable", @"nice", @"no-iv", @"no-name-remapping", @"no-replay", \
@"nobind", @"ns-cert-type", \
@"opt-verify", \
@"parameter", @"passtos", @"pause-exit", @"peer-fingerprint", @"peer-id", @"persist-key", \
@"persist-local-ip", @"persist-remote-ip", @"persist-tun", @"ping-exit", @"ping-restart", \
@"ping-timer-rem", @"ping", @"pkcs11-cert-private", @"pkcs11-id-management", @"pkcs11-id", \
@"pkcs11-pin-cache", @"pkcs11-private-mode", @"pkcs11-protected-authentication", \
@"pkcs11-providers", @"pkcs12", \
/* UNSAFE: @"plugin", */ \
@"port-share", @"port", @"preresolve", @"prng", @"proto-force", @"proto", @"pull", \
@"push-continuation", @"pull-filter", @"push-peer-info", @"push-remove", @"push-reset", @"push", \
@"rcvbuf", @"rdns-internal", @"redirect-gateway", @"redirect-private", @"register-dns", \
@"remap-usr1", @"remote-cert-eku", @"remote-cert-ku", @"remote-cert-tls", @"remote-random-hostname", \
@"remote-random", @"remote", @"reneg-bytes", @"reneg-pkts", @"reneg-sec", @"replay-persist", \
@"replay-window", @"resolv-retry", @"rmtun", @"route-delay", @"route-gateway", @"route-ipv6", \
@"route-ipv6-gateway", @"route-method", @"route-metric", @"route-noexec", @"route-nopull", \
/* UNSAFE: @"route-pre-down", */ \
/* UNSAFE: @"route-up", */ \
@"route", @"rport", \
@"scramble", @"script-security", @"secret", @"server-bridge", @"server-ipv6", @"server-poll-timeout", \
@"server", @"service", @"setcon", @"setenv-safe", @"setenv", @"shaper", @"show-adapters", \
@"show-ciphers", @"show-curves", @"show-digests", @"show-engines", @"show-gateway", @"show-groups", \
@"show-net-up", @"show-net", @"show-pkcs11-ids", @"show-tls", @"show-valid-subnets", \
@"single-session", @"sndbuf", @"socket-flags", @"socks-proxy-retry", @"socks-proxy", \
@"stale-routes-check", @"static-challenge", @"status-version", @"status", @"suppress-timestamps", \
@"syslog", \
@"tap-sleep", @"tcp-nodelay", @"tcp-queue-limit", @"test-crypto", @"tls-auth", @"tls-cert-profile", \
@"tls-cipher", @"tls-ciphersuites", @"tls-client", @"tls-crypt", @"tls-crypt-v2", \
@"tls-crypt-v2-verify", @"tls-exit", @"tls-export-cert", @"tls-groups", @"tls-remote", \
@"tls-server", @"tls-timeout", \
/* UNSAFE: @"tls-verify", */ \
@"tls-version-max", @"tls-version-min", @"tmp-dir", @"topology", @"tran-window", @"tun-ipv6", \
@"tun-mtu-extra", @"tun-mtu", @"txqueuelen", @"udp-mtu", \
/* UNSAFE: @"up", */ \
@"up-delay", @"up-restart", @"use-prediction-resistance", @"user", @"username-as-common-name", \
@"verb", @"verify-client-cert", @"verify-hash", @"verify-x509-name", @"version", @"vlan-accept", \
@"vlan-pvid", @"vlan-tagging", \
@"windows-driver", @"win-sys", @"writepid", \
@"x509-track", @"x509-username-field" \
]

//*************************************************************************************************
// Array of arrays with info about deprecated and removed options. Each array entry is an array with:
//		OpenVPN version the option(s) were deprecated in,
//		OpenVPN version the option(s) were removed in (if has a '?' suffix, the removal version has not been decided)
//		Option name...
//
// These entries are based on version 65 (modified 2023-02-01) of https://community.openvpn.net/openvpn/wiki/DeprecatedOptions
#define OPENVPN_OPTIONS_DEPRECATED_AND_REMOVED @[ \
                            @[@"2.1", @"2.5",  @"ifconfig-pool-linear"], \
                            @[@"2.3", @"2.4",  @"tls-remote"], \
                            @[@"2.3", @"2.5",  @"compat-names", @"no-name-remapping"], \
                            @[@"2.4", @"2.4",  @"tun-ipv6"], \
                            @[@"2.4", @"2.5",  @"client-cert-not-required", @"no-iv", @"secret"], \
                            @[@"2.4", @"2.5?", @"comp-lzo", @"comp-noadapt", @"dhcp-release", @"key-method", @"max-routes", @"no-replay"], \
                            @[@"2.4", @"2.6",  @"keysize"], \
                            @[@"2.4", @"2.6?", @"ns-cert-type"], \
                            @[@"2.5", @"2.6",  @"inetd", @"management-client-pf", @"ncp-disable", @"prng"], \
                            @[@"2.5", @"2.6?", @"compress"], \
                            @[@"2.6", @"2.7?", @"foreign-option", @"verify-hash"] \
                            ]

//*************************************************************************************************
// Array of arrays with info about options added to OpenVPN. Each array entry is an array with:
//		OpenVPN minor version the option(s) first appeared in,
//		Option name...
//
// By first appeared in, we mean that that option was not in the last minor version before it
// (e.g. something in 2.5.x that did not appear in 2.4.12, which was the last 2.4 version).
//
// So if an option appears in only in 2.4.12 and 2.5.0 and later, it is "new" in 2.4, and if a
// configuration with it is run in 2.4.11, no complaint will be made even though it should.
//
// The 2.6 list is as of 2.6.3.
//
#define OPENVPN_OPTIONS_ADDED @[ \
                        @[@"2.4", \
                             @"auth-gen-token", @"compat-names", @"compress", @"ecdh-curve", @"http-proxy-user-pass", @"ip-remote-hint", \
                             @"keying-material-exporter", @"machine-readable-output", @"management-external-cert", @"msg-channel", \
                             @"ncp-ciphers", @"ncp-disable", @"preresolve", @"pull-filter", @"push-remove", @"show-curves", @"tls-crypt", \
                             @"tls-cert-profile", @"tls-ciphersuites", @"tls-crypt", \
                             @"verify-client-cert"], \
\
                        @[@"2.5", \
                             @"allow-compression", @"auth-gen-token-secret", @"auth-token-user", @"bind-dev", @"block-ipv6", \
                             @"data-ciphers", @"data-ciphers-fallback", @"providers", @"route-ipv6-gateway", @"show-groups", \
                             @"tls-crypt-v2", @"tls-crypt-v2-verify", @"tls-groups", @"vlan-accept", @"vlan-pvid", @"vlan-tagging", \
                             @"windows-driver"], \
\
                        @[@"2.6", \
                             @"client-crresponse", @"compat-mode", @"connect-freq-initial", @"disable-dco", @"dns", @"key-derivation", \
                             @"max-packet-size", @"peer-fingerprint", @"protocol-flags", @"session-timeout", @"tun-mtu-max"] \
                        ];

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
// _FOLDER      entries are for folders
// _ROOT_SCRIPT entries are for files with the .sh extension that run as root
// _USER_SCRIPT entries are for files with the .sh extension that run as the user -- that is, if shouldRunScriptAsUserAtPath()
// _EXECUTABLE  entries are for files with the .executable extension (in Deploy folders only)
// _READABLE    entries are for files (such as Info.plist files) that should be readable (by owner/group in private configurations, by everyone everywhere else)
// _OTHER       entries are for all other files


#define PERMS_PRIVATE_FOLDER      0750
#define PERMS_PRIVATE_ROOT_SCRIPT 0740
#define PERMS_PRIVATE_USER_SCRIPT 0740
#define PERMS_PRIVATE_EXECUTABLE  0740
#define PERMS_PRIVATE_READABLE    0740
#define PERMS_PRIVATE_OTHER       0740

#define PERMS_PRIVATE_REMOTE_FOLDER      0700
#define PERMS_PRIVATE_REMOTE_ROOT_SCRIPT 0700
#define PERMS_PRIVATE_REMOTE_USER_SCRIPT 0700
#define PERMS_PRIVATE_REMOTE_EXECUTABLE  0700
#define PERMS_PRIVATE_REMOTE_READABLE    0700
#define PERMS_PRIVATE_REMOTE_OTHER       0700

#define PERMS_SECURED_FOLDER      0755
#define PERMS_SECURED_ROOT_SCRIPT 0700
#define PERMS_SECURED_USER_SCRIPT 0755
#define PERMS_SECURED_EXECUTABLE  0755
#define PERMS_SECURED_ROOT_EXEC   0744
#define PERMS_SECURED_ROOT_RO     0400
#define PERMS_SECURED_READABLE    0644
#define PERMS_SECURED_OTHER       0700


//*************************************************************************************************
// Values for the location of the configuration file (cfgLocCode argument to openvpnstart) 
#define CFG_LOC_PRIVATE   0
#define CFG_LOC_ALTERNATE 1
#define CFG_LOC_DEPLOY    2
#define CFG_LOC_SHARED    3
#define CFG_LOC_MAX       3


//*************************************************************************************************
// Bit masks for bitMask parameter of openvpnstart's start, loadkexts, and unloadkexts sub-commands
#define OPENVPNSTART_OUR_TUN_KEXT						0x00000001u
#define OPENVPNSTART_OUR_TAP_KEXT						0x00000002u

#define OPENVPNSTART_KEXTS_MASK_LOAD_DEFAULT   (OPENVPNSTART_OUR_TUN_KEXT | OPENVPNSTART_OUR_TAP_KEXT)
#define OPENVPNSTART_KEXTS_MASK_LOAD_MAX       (OPENVPNSTART_OUR_TUN_KEXT | OPENVPNSTART_OUR_TAP_KEXT)

#define OPENVPNSTART_FOO_TUN_KEXT						0x00000004u
#define OPENVPNSTART_FOO_TAP_KEXT						0x00000008u

#define OPENVPNSTART_KEXTS_MASK_UNLOAD_DEFAULT (OPENVPNSTART_FOO_TUN_KEXT | OPENVPNSTART_FOO_TAP_KEXT)
#define OPENVPNSTART_KEXTS_MASK_UNLOAD_MAX     (OPENVPNSTART_OUR_TUN_KEXT | OPENVPNSTART_OUR_TAP_KEXT | OPENVPNSTART_FOO_TUN_KEXT | OPENVPNSTART_FOO_TAP_KEXT)

#define OPENVPNSTART_RESTORE_ON_DNS_RESET				0x00000010u
#define OPENVPNSTART_RESTORE_ON_WINS_RESET				0x00000020u
#define OPENVPNSTART_USE_TAP							0x00000040u
#define OPENVPNSTART_PREPEND_DOMAIN_NAME				0x00000080u
#define OPENVPNSTART_FLUSH_DNS_CACHE					0x00000100u
#define OPENVPNSTART_USE_REDIRECT_GATEWAY_DEF1			0x00000200u
#define OPENVPNSTART_DISABLE_LOGGING					0x00000400u
#define OPENVPNSTART_TEST_MTU							0x00000800u
#define OPENVPNSTART_EXTRA_LOGGING						0x00001000u
#define OPENVPNSTART_NO_DEFAULT_DOMAIN					0x00002000u
#define OPENVPNSTART_NOT_WHEN_COMPUTER_STARTS			0x00004000u
#define OPENVPNSTART_USE_ROUTE_UP_NOT_UP				0x00008000u
#define OPENVPNSTART_OVERRIDE_MANUAL_NETWORK_SETTINGS	0x00010000u
#define OPENVPNSTART_WAIT_FOR_DHCP_IF_TAP				0x00020000u
#define OPENVPNSTART_DO_NOT_WAIT_FOR_INTERNET			0x00040000u
#define OPENVPNSTART_ENABLE_IPV6_ON_TAP					0x00080000u
#define OPENVPNSTART_DISABLE_IPV6_ON_TUN				0x00100000u
#define OPENVPNSTART_RESET_PRIMARY_INTERFACE			0x00200000u
#define OPENVPNSTART_DISABLE_INTERNET_ACCESS			0x00400000u
#define OPENVPNSTART_RESET_PRIMARY_INTERFACE_UNEXPECTED	0x00800000u
#define OPENVPNSTART_DISABLE_INTERNET_ACCESS_UNEXPECTED	0x01000000u
#define OPENVPNSTART_ON_BIG_SUR_OR_NEWER                0x02000000u
#define OPENVPNSTART_DISABLE_SECONDARY_NET_SERVICES     0x04000000u
#define OPENVPNSTART_FORCE_DNS_UP_DOWN                  0x08000000u
// DUPLICATE THE HIGHEST VALUE BELOW					vvvvvvvvvvv
#define OPENVPNSTART_HIGHEST_BITMASK_BIT				0x08000000u


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

#define OPENVPNSTART_COMMANDS_REQUIRING_NETWORK_REACHABILITY    @[@"route-pre-down", @"down", @"postDisconnect", @"preDisconnect", @"connected", @"reconnecting", @"start"]
//*************************************************************************************************
// Error return codes for openvpnstart
#define OPENVPNSTART_COMPARE_CONFIG_SAME             0
#define OPENVPNSTART_REVERT_CONFIG_OK				 0
#define OPENVPNSTART_UPDATE_SAFE_OK                  0
#define OPENVPNSTART_COULD_NOT_LOAD_KEXT             247
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

//********************************************
// Bit masks for optional operations which will be
// performed before the primary operation (if any)

// Set to clear the installer log before
// doing anything else
#define INSTALLER_CLEAR_LOG				     0x0001u

// Set to copy this app to /Applications
// (any existing app will be moved to
// the Trash)
#define INSTALLER_COPY_APP                   0x0002u

// Set to secure Tunnelblick.app and all of
// its contents (forced TRUE if
// INSTALLER_COPY_APP is set)
#define INSTALLER_SECURE_APP                 0x0004u

// UNUSED
//                                           0x0008u

// Set to secure all .tblk packages in
// Configurations, Shared, and the
// alternate configuration path
#define INSTALLER_SECURE_TBLKS               0x0010u

// Set to copy /Applications/Tunnelblick.app
// to /Library/Application Support/Tunnelblick/Tunnelblick.app
#define INSTALLER_COPY_APP_TO_L_AS_T         0x0020u

// UNUSED
//                                           0x0040u

// UNUSED
//                                           0x0080u

// Set to replace tunnelblickd
#define INSTALLER_REPLACE_DAEMON             0x0100u

// Set to install kexts to /Library/Extensions
#define INSTALLER_INSTALL_KEXTS              0x0200u

// Set to uninstall kexts from /Library/Extensions
#define INSTALLER_UNINSTALL_KEXTS            0x0400u

//********************************************
// PRIMARY OPERATION CODES
// Each primary operation also requires zero
// or more additional arguments

#define INSTALLER_OPERATION_MASK			 0xF000u
#define INSTALLER_OPERATION_SHIFT_COUNT      12

// Copy one configuration
// (Only if two paths are additional
//  arguments: target path,
//             source path)
#define INSTALLER_COPY						 0x0000u

// Move one configuration
// (arguments: target path,
//             source path)
#define INSTALLER_MOVE						 0x1000u

// Delete one configuration
// (argument: path)
#define INSTALLER_DELETE                     0x2000u

// Copy one file to forced preferences
// (argument: path)
// L_AS_T_PRIMARY_FORCED_PREFERENCES_PATH
#define INSTALLER_INSTALL_FORCED_PREFERENCES 0x3000u

// Export the Tunnelblick setup for all
// users (configurations and preferences but
// not Keychain items) to a .tblkSetup, then
// compress that to a .tar.gz on the Desktop
// (no arguments)
#define INSTALLER_EXPORT_ALL                 0x4000u

// Import from a .tblkSetup using a string
// that defines username mapping
// (arguments: path to .tblksetup,
//             string that describes username mapping)
#define INSTALLER_IMPORT                     0x5000u

// Install a private configuration
// (arguments: username,
//             path to configuration,
//             optional subfolder)
#define INSTALLER_INSTALL_PRIVATE_CONFIG     0x6000u

// Install a shared configuration
// (arguments: path to configuration,
//             optional subfolder)
#define INSTALLER_INSTALL_SHARED_CONFIG      0x7000u

// Install Tunnelblick from /Users/username/Library/Application Support/Tunnelblick/Tunnelblick.zip
// (arguments: zipSignature,
//             versionString,
//             username,
//             Tunnelblick process ID)
#define INSTALLER_UPDATE_TUNNELBLICK         0x8000u


//*************************************************************************************************
// Size to use to minimize the left navigation area when it is inactive
#define LEFT_NAV_AREA_MINIMAL_SIZE 8.0

//*************************************************************************************************
// Minimum size of the left navigation area when it is active
#define LEFT_NAV_AREA_MINIMUM_SIZE 40.0

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
// Macros to make it easy to use nil values in dictionaries or arrays
#define NSNullIfNil(v) (v                  ? v   : [NSNull null])
#define nilIfNSNull(v) (v != [NSNull null] ? v   : nil)

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

// The  @""  before __VA_ARGS__ allows TBTrace to accept no arguments and forces an error
// if there are arguments and the first argument isn't a literal NSString or C string
#define TBTrace(...) append_tb_trace_routine( __FILE__, __LINE__, @"" __VA_ARGS__)

#define NON_CONFIGURATIONS_PREFERENCES_NSARRAY @[	\
@"DB-ALL",    /* All extra logging */	\
@"DB-AA",     /* Extra logging for system authorization (for executeAuthorized) */	\
@"DB-AU",	  /* Extra logging for VPN authorization */	\
@"DB-CD",     /* Extra logging for connect/disconnect */	\
@"DB-DD",     /* Extra logging for drag/drop onto VPN Details window */	\
@"DB-D2",     /* Extra logging for drag/drop within the left navigation of the VPN Details window */	\
@"DB-HU",     /* Extra logging for hookup, */	\
@"DB-IC",     /* Extra logging for IP address checking */	\
@"DB-IT",     /* Extra logging for IP address check threading */	\
@"DB-MC",	  /* Extra logging for menu cache creation and use */	\
@"DB-MO",     /* Extra logging for mouseover (of icon and status windows) */	\
@"DB-PM",     /* Extra logging for password manipulation (password-replace.user.sh, etc.) */	\
@"DB-PO",     /* Extra logging for populating the NSOutlineView showing configurations */	\
@"DB-PU",     /* Extra logging for information popups */	\
@"DB-SD",     /* Extra logging for shutdown */	\
@"DB-SI",     /* Extra logging for status item creation/deletion/move */	\
@"DB-SU",     /* Extra logging for startup */	\
@"DB-SW",     /* Extra logging for sleep/wake and inactive user/active user */	\
@"DB-TD",     /* Extra logging for tunnelblickd interactions, */	\
@"DB-TO",     /* Extra logging for terminating OpenVPN processes (via kill, killall, or socket) */	\
@"DB-UA",     /* Extra logging for updating the application */    \
@"DB-UC",     /* Extra logging for updating configurations */    \
@"DB-UP",     /* Extra logging for the up and down scripts */	\
@"DB-UU",	  /* Extra logging for UI updates */	\
\
@"useRtlLayout",	/* Use RTL language layout, regardless of language (for debugging RTL layout issues) */	\
\
@"allowNonAdminSafeConfigurationReplacement",  /* Must be forced; regular preference is ignored */	\
\
@"-skipWarningAboutAppUpdateError", \
@"-skipWarningAboutVpnUpdateError", \
@"skipWarningAboutReprotectingConfigurationFile",	\
@"skipWarningAboutSimultaneousConnections",	\
@"skipWarningAboutConvertingToTblks",	\
@"skipWarningThatCannotModifyConfigurationFile",	\
@"skipWarningThatNameChangeDisabledUpdates",	\
@"skipWarningAboutNonAdminUpdatingTunnelblick",	\
@"skipWarningAboutUnknownOpenVpnProcesses",	\
@"skipWarningAboutOnComputerStartAndTblkScripts",	\
@"skipWarningAboutIgnoredConfigurations",	\
@"skipWarningAboutConfigFileProtectedAndAlwaysExamineIt",	\
@"skipWarningThatIPANotFetchedBeforeConnection",	\
@"skipWarningThatIPAddressDidNotChangeAfterConnection",	\
@"skipWarningThatDNSIsNotWorking",	\
@"skipWarningThatInternetIsNotReachable",	\
@"skipWarningAboutInvalidSignature",	\
@"skipWarningAboutNoSignature",	\
@"skipWarningAboutSystemClock",	\
@"skipWarningAboutUnavailableOpenvpnVersions",	\
@"skipWarningAbout64BitVersionOnSnowLeopardPointEight",	\
@"skipWarningAbout64BitVersionWithTap",	\
@"skipWarningAbout64BitVersionWithTunOnSnowLeopardPointEight",	\
@"skipWarningAbout64BitVersionOnNonSnowLeopardPointEight",	\
@"skipWarningAboutInstallsWithCommands",	\
@"skipWarningAboutPreAuthorizedActivity",	\
@"skipWarningAboutPlacingIconNearTheSpotlightIcon",	\
@"skipWarningAboutReenablingInternetAccessOnConnect", \
@"skipWarningAboutReenablingInternetAccessOnLaunch", \
@"skipWarningAboutReenablingInternetAccessOnQuit", \
@"skipWarningAboutErrorGettingDnsServers", \
@"skipWarningAboutErrorGettingKnownPublicDnsServers", \
@"skipWarningAboutDnsProblems", \
@"skipWarningAboutWhenSystemStartsConfigurationsThatAreNotConnected", \
@"skipWarningAboutAlwaysLoadTunAndOrTapOnFutureMacOS", \
@"skipWarningAboutDevNodeTunOnFutureMacOS", \
@"skipWarningAboutTapConnectionOnFutureMacOS", \
@"skipWarningAboutBigSur1", \
@"skipWarningAboutBigSur2", \
@"skipWarningAboutBigSur1m", \
@"skipWarningAboutBigSur2m", \
@"skipWarningAboutNotCheckingIPAddressChanges", \
@"skipWarningAboutRosetta", \
@"skipWarningThatTunnelblickLauncherIsDisabled", \
@"skipWarningAboutOpenSSL_1_1_1", \
\
@"buildExpirationTimestamp",	\
@"daysBeforeFirstWarningOfOldBuild",	\
@"daysToDeferWarningOfOldBuild",	\
\
\
@"timeoutForOpenvpnToTerminateAfterDisconnectBeforeAssumingItIsReconnecting",	\
@"timeoutForIPAddressCheckBeforeConnection",	\
@"timeoutForIPAddressCheckAfterConnection",	\
@"timeoutForIPAddressCheckAfterSleeping",	\
@"timeoutForDisconnectingConfigurations",    \
@"delayBeforeReconnectingAfterSleep",	\
@"delayBeforeReconnectingAfterSleepAndIpaFetchError",	\
@"delayBeforeIPAddressCheckAfterConnection",	\
@"delayBeforeRetryingUpdateCheckBecauseInternetIsOffline",    \
@"delayBeforeComplainingAboutFailedUpdateCheckBecauseInternetIsOffline",    \
@"delayBeforeSlowDisconnectDialog",	\
@"delayBeforePopupHelp",	\
@"delayBeforeConnectingAfterReenablingNetworkServices", \
@"hookupTimeout",	\
@"displayUpdateInterval",	\
\
@"TBUpdaterAllowNonAdminToUpdateTunnelblick", \
@"TBUpdaterCheckOnlyWhenConnectedToVPN", \
@"TBUpdaterDownloadUpdateWhenAvailable", \
@"TBUpdateVersionStringForDownloadedAppUpdate", \
@"TBUpdateTunnelblickLauncherLastEnabledTime", \
\
@"inhibitOutboundTunneblickTraffic",	\
@"placeIconInStandardPositionInStatusBar",	\
@"doNotMonitorConfigurationFolder",	\
@"doNotCheckForNetworkReachabilityWhenConnecting", \
@"doNotIgnoreSignal13",	\
@"doNotLaunchOnLogin", /* DISABLE the ability to launch on login provided by launchAtNextLogin */	\
@"launchAtNextLogin",	\
@"doNotCreateLaunchTunnelblickLinkinConfigurations",	\
@"menuIconSet",	\
@"easy-rsaPath",	\
@"IPAddressCheckURL",	\
@"notOKToCheckThatIPAddressDidNotChangeAfterConnection",	\
@"tunnelblickVersionHistory",	\
@"statusDisplayNumber",	\
@"lastLaunchTime",	\
@"allow64BitIntelOpenvpnOnTigerOrLeopard",	\
@"doNotRedisplayLoginOrPassphraseWindowAtScreenChangeOrWakeFromSleep",	\
@"doNotEjectTunnelblickVolume",	\
@"doNotCheckThatOpenvpnVersionIsCompatibleWithConfiguration",	\
@"openvpnAllowsDynamicChallengeRegardlessOfAuthRetrySetting",	\
@"tryToLoadKextsOnThisVersionOfMacOS",    \
@"doNotDisconnectForCertificateProblems", \
\
@"disableAdvancedButton",	\
@"disableCheckNowButton",	\
@"disableResetDisabledWarningsButton",	\
@"disableAddConfigurationButton",	\
@"disableRemoveConfigurationButton",	\
@"disableWorkOnConfigurationButton",	\
@"disableCopyConfigurationsIntoNewFolderMenuItem",	\
@"disableMoveConfigurationsIntoNewFolderMenuItem",	\
@"disableRenameConfigurationMenuItem",	\
@"disableDuplicateConfigurationMenuItem",	\
@"disableMakeConfigurationPublicOrPrivateMenuItem",	\
@"disableRevertToShadowMenuItem",	\
@"disableShowHideOnTbMenuItem",	\
@"disableExamineOpenVpnConfigurationFileMenuItem",	\
@"disableShowOpenVpnLogInFinderMenuItem",	\
@"disableDeleteConfigurationCredentialsInKeychainMenuItem",	\
@"disableCopyLogToClipboardButton",	\
\
@"doNotShowNotificationWindowBelowIconOnMouseover",	\
@"doNotShowNotificationWindowOnMouseover",	\
@"doNotShowDisconnectedNotificationWindows",	\
@"doNotShowConnectionSubmenus",	\
@"doNotShowVpnDetailsMenuItem",	\
@"doNotShowSuggestionOrBugReportMenuItem",	\
@"doNotShowAddConfigurationMenuItem",	\
@"doNotShowSplashScreen",	\
@"doNotShowOutlineViewOfConfigurations",	\
@"showConnectedDurations",	\
\
@"connectionLogTickInterval", \
@"connectionLogEntrySizeLimit", \
@"connectionLogInitialLoadMultiplier", \
\
@"maximumOpenvpnLogSize", \
\
@"chooseSameOpenvpnOverSameSsl",	\
\
@"welcomeURL",	\
@"welcomeWidth",	\
@"welcomeHeight",	\
@"doNotShowWelcomeDoNotShowAgainCheckbox",	\
@"skipWelcomeScreen",	\
@"doNotShowHaveNoConfigurationsGuide", \
@"lastLanguageAtLaunchWasRTL",	\
@"dateLastRequestedEmailCrashReports", \
\
@"openvpnVersion",	\
@"maximumNumberOfTabs",	\
@"maxConfigurationsForUncachedMenu",	\
@"onlyAdminCanUpdate",	\
@"connectionWindowDisplayCriteria",	\
@"showTooltips",	\
@"maxLogDisplaySize",	\
@"lastConnectedDisplayName",	\
@"keyboardShortcutIndex",	\
@"doNotUnrebrandLicenseDescription",	\
@"useSharedConfigurationsWithDeployedOnes",	\
@"usePrivateConfigurationsWithDeployedOnes",	\
@"namedCredentialsThatAllConfigurationsUse",	\
@"namedCredentialsNames",	\
\
@"delayToShowStatistics",	\
@"delayToHideStatistics",	\
@"statisticsRateTimeInterval",	\
\
@"updateCheckAutomatically",	\
@"updateCheckBetas",	\
@"updateCheckInterval",	\
@"updateFeedURL",	\
\
@"NSWindow Frame SettingsSheetWindow",	\
@"NSWindow Frame ConnectingWindow",	\
@"NSWindow Frame SUStatusFrame",	\
@"NSWindow Frame SUUpdateAlert",	\
@"NSWindow Frame ListingWindow",	\
@"NSWindow Frame NSFindPanel",      \
@"detailsWindowFrameVersion",	\
@"detailsWindowFrame",	\
@"detailsWindowLeftFrame",	\
@"detailsWindowViewIndex",	\
@"detailsWindowConfigurationsTabIdentifier",	\
@"leftNavOutlineViewExpandedDisplayNames",	\
@"leftNavSelectedDisplayName",	\
@"AdvancedWindowTabIdentifier",	\
\
@"haveDealtWithOldTunTapPreferences",	\
@"haveDealtWithAlwaysShowLoginWindow",	\
@"haveDealtWithOldLoginItem",	\
@"haveDealtWithAfterDisconnect",	\
@"haveStartedAnUpdateOfTheApp",	\
\
@"SUEnableAutomaticChecks",	\
@"SUFeedURL",	\
@"SUScheduledCheckInterval",	\
@"SUSendProfileInfo",	\
@"SUAutomaticallyUpdate",	\
@"SULastCheckTime",	\
@"SULastProfileSubmissionDate",	\
@"SUHasLaunchedBefore",	\
@"SUSkippedVersion",	\
\
\
@"WebKitDefaultFontSize",	\
@"WebKitStandardFont",	\
\
@"ApplicationCrashedAfterRelaunch",	\
\
/* No longer used */	\
@"askedUserIfOKToCheckThatIPAddressDidNotChangeAfterConnection",	\
@"bigSurCanLoadKexts",    \
@"buildExpirationTimestamp",	\
@"daysBeforeFirstWarningOfOldBuild",	\
@"daysToDeferWarningOfOldBuild",	\
@"doNotShowCheckForUpdatesNowMenuItem",	\
@"doNotShowForcedPreferenceMenuItems",	\
@"doNotShowKeyboardShortcutSubmenu",	\
@"doNotShowOptionsSubmenu",	\
@"keyboardShortcutKeyCode",	\
@"keyboardShortcutModifiers",	\
@"managementPortStartingPortNumber",	\
@"maximumLogSize",	\
@"onlyAdminsCanUnprotectConfigurationFiles",	\
@"skipWarningAboutUsingOpenvpnTxpVersion",	\
@"skipWarningAboutUsingOpenvpnNonTxpVersion",	\
@"skipWarningAboutNoOpenvpnTxpVersion",	\
@"skipWarningAboutOnlyOpenvpnTxpVersion",	\
@"skipWarningAboutReenablingInternetAccessAtExit",	\
@"standardApplicationPath",	\
@"tunnelblickdHash",	\
@"tunnelblickdPlistHash",	\
@"updateAutomatically",	\
@"updateSendProfileInfo",	\
@"updateSigned",	\
@"updateUnsigned"	\
@"userAgreementVersionAgreedTo",	\
@"useShadowConfigurationFiles",	\
]

#define CONFIGURATIONS_PREFERENCES_NSARRAY @[ \
@"-skipWarningAboutDownroot",	\
@"-skipWarningAboutNoTunOrTap",	\
@"-skipWarningUnableToToEstablishOpenVPNLink",	\
@"-skipWarningThatCannotConnectBecauseOfOpenVPNOptions",	\
@"-skipWarningThatNotUsingSpecifiedOpenVPN",	\
@"-skipWarningThatCannotConnectBecauseOfOpenVPNOptionConflicts",	\
@"autoConnect",	\
@"-onSystemStart",	\
@"useDNS",	\
@"-authenticateOnConnect", \
@"-notMonitoringConnection",	\
@"-doNotRestoreOnDnsReset",	\
@"-doNotRestoreOnWinsReset",	\
@"-leasewatchOptions",	\
@"-doNotDisconnectOnFastUserSwitch",	\
@"-doNotReconnectOnFastUserSwitch",	\
@"-doNotReconnectOnWakeFromSleep",	\
@"-resetPrimaryInterfaceAfterDisconnect",	\
@"-resetPrimaryInterfaceAfterUnexpectedDisconnect",	\
@"-routeAllTrafficThroughVpn",	\
@"-runMtuTest",	\
@"-doNotFlushCache",	\
@"-useUpInsteadOfRouteUp",	\
@"-useDownRootPlugin",	\
@"-keychainHasPrivateKey",	\
@"-keychainHasUsernameAndPassword",	\
@"-keychainHasUsername",	\
@"-doNotParseConfigurationFile",	\
@"-disableEditConfiguration",	\
@"-disableConnectButton",	\
@"-disableDisconnectButton",	\
@"-doNotLoadTapKext",	\
@"-doNotLoadTunKext",	\
@"-loadTapKext",	\
@"-loadTunKext",	\
@"-loadTap",	\
@"-loadTun",	\
@"-credentialsGroup",	\
@"-openvpnVersion",	\
@"-notOKToCheckThatIPAddressDidNotChangeAfterConnection",	\
@"-keepConnected",	\
@"-doNotDisconnectOnSleep",	\
@"-doNotUseDefaultDomain",	\
@"-waitForDHCPInfoIfTap",	\
@"-enableIpv6OnTap",	\
@"-doNotDisableIpv6onTun",	\
@"-disableSecondaryNetworkServices", \
@"-loggingLevel",	\
@"-allowChangesToManuallySetNetworkSettings",	\
@"-disableNetworkAccessAfterDisconnect",	\
@"-disableNetworkAccessAfterUnexpectedDisconnect",	\
@"-consecutiveSuccessfulIPAddressChanges", \
@"-loginWindowSecurityTokenCheckboxIsChecked", \
@"-changeDNSServersAction",	\
@"-changeDomainAction",	\
@"-changeSearchDomainAction",	\
@"-changeWINSServersAction",	\
@"-changeNetBIOSNameAction",	\
@"-changeWorkgroupAction",	\
@"-changeOtherDNSServersAction",	\
@"-changeOtherDomainAction",	\
@"-changeOtherSearchDomainAction",	\
@"-changeOtherWINSServersAction",	\
@"-changeOtherNetBIOSNameAction",	\
@"-changeOtherWorkgroupAction",	\
@"-lastConnectionSucceeded",	\
@"-tunnelDownSoundName",	\
@"-tunnelUpSoundName",	\
@"-doNotDisconnectWhenTunnelblickQuits",	\
@"-prependDomainNameToSearchDomains",	\
@"-doNotWaitForInternetAtBoot",	\
@"-doNotReconnectOnUnexpectedDisconnect", /* This preference is NOT IMPLEMENTED and it is not in the .xib */	\
@"-loginWindowSecurityTokenIsHidden", \
\
@"-doNotShowOnTunnelblickMenu",	\
\
/* No longer used */	\
@"-authUsername",	\
@"-alwaysShowLoginWindow", \
@"haveDealtWithSparkle1dot5b6",    \
@"-skipWarningThatMayNotConnectInFutureBecauseOfOpenVPNOptions",	\
@"-usernameIsSet",	\
@"-useRouteUpInsteadOfUp"   \
]
//*************************************************************************************************
// Comment out (with "//") the following line to EXclude the VPNService feature
//#define INCLUDE_VPNSERVICE 1
