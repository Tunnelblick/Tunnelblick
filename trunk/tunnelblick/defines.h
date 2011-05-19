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
// Paths:
// Note: The standard up script refers to the log directory without using this header file
#define LOG_DIR   @"/Library/Application Support/Tunnelblick/Logs"
#define CONFIGURATION_UPDATES_BUNDLE_PATH  @"/Library/Application Support/Tunnelblick/Configuration Updates/Tunnelblick Configurations.bundle"


// Values for the location of the configuration file (cfgLocCode argument to openvpnstart) 
#define CFG_LOC_PRIVATE   0
#define CFG_LOC_ALTERNATE 1
#define CFG_LOC_DEPLOY    2
#define CFG_LOC_SHARED    3


//*************************************************************************************************
// Bit masks for bitMask parameter of openvpnstart's start, loadkexts, and unloadkexts sub-commands
// For openvpn's start, loadkexts, and unloadkexts sub-commands:
#define OPENVPNSTART_OUR_TUN_KEXT           1
#define OPENVPNSTART_OUR_TAP_KEXT           2
// For openvpn's  start and unloadkexts sub-commands:
#define OPENVPNSTART_FOO_TUN_KEXT           4
#define OPENVPNSTART_FOO_TAP_KEXT           8
// For openvpn's  start sub-command
#define OPENVPNSTART_RESTORE_ON_DNS_RESET  16
#define OPENVPNSTART_RESTORE_ON_WINS_RESET 32
#define OPENVPNSTART_USE_TAP               64


//*************************************************************************************************
// Bit masks for bitMask parameter of installer
#define INSTALLER_COPY_APP      0x01
#define INSTALLER_COPY_BUNDLE   0x02
#define INSTALLER_SECURE_APP    0x04
#define INSTALLER_SECURE_TBLKS  0x08
#define INSTALLER_SET_VERSION   0x10
#define INSTALLER_MOVE_NOT_COPY 0x20
#define INSTALLER_DELETE        0x40


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
	statusWindowControllerCancelChoice
} StatusWindowControllerChoice;

//*************************************************************************************************
// Comment out (with "//") the following line to EXclude the VPNService feature
//#define INCLUDE_VPNSERVICE 1
