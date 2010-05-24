/*
 * Copyright (c) 2010 Jonathan K. Bullard
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2
 * as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program (see the file COPYING included with this
 * distribution); if not, write to the Free Software Foundation, Inc.,
 * 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */


// Bit masks for bitMask parameter of openvpnstart start, loadkexts, and unloadkexts commands

// For start, loadkexts, and unloadkexts:
#define OUR_TUN_KEXT     1
#define OUR_TAP_KEXT     2

// For start and unloadkexts:
#define FOO_TUN_KEXT     4
#define FOO_TAP_KEXT     8

// For start
#define CREATE_LOG_FILE          16

// For start to pass on to scripts as arguments in the --up and --down OpenVPN options
#define RESTORE_ON_DNS_RESET     32
#define RESTORE_ON_WINS_RESET    64
