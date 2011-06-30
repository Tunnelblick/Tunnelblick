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
// Return values for openvpnstart compareConfig command
#define OPENVPNSTART_COMPARE_CONFIG_SAME 3
#define OPENVPNSTART_COMPARE_CONFIG_DIFFERENT 5


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
