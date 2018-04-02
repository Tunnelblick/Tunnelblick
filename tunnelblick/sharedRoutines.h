/*
 * Copyright 2012, 2013, 2014, 2015, 2016, 2018 Jonathan K. Bullard. All rights reserved.
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

#import <Foundation/Foundation.h>


NSString * sha256HexStringForData (NSData * data);

NSString * mipName(void);

BOOL isValidIPAdddress(NSString * ipAddress);

NSDictionary * tunnelblickdPlistDictionaryToUse(void);

BOOL needToReplaceLaunchDaemon(void);

OSStatus getSystemVersion(unsigned * major, unsigned * minor, unsigned * bugFix);

unsigned cvt_atou(const char * s, NSString * description);

int            createDir(NSString * d,
						 unsigned long perms);

id             callStack(void);

BOOL isOnRemoteVolume(NSString * path);

mode_t privateFolderPermissions(NSString * path);

gid_t privateFolderGroup(NSString * path);

BOOL isSanitizedOpenvpnVersion(NSString * s);

BOOL checkOwnerAndPermissions (NSString * fPath,
                               uid_t      uid,
                               gid_t      gid,
                               mode_t     permsShouldHave);

BOOL checkSetItemOwnership(NSString *     path,
						   NSDictionary * atts,
						   uid_t          uid,
						   gid_t          gid,
						   BOOL           traverseLink);

BOOL checkSetOwnership(NSString * path,
					   BOOL       deeply,
					   uid_t      uid,
					   gid_t      gid);

BOOL checkSetPermissions(NSString * path,
						 mode_t     permsShouldHave,
						 BOOL       fileMustExist);

BOOL createDirWithPermissionAndOwnership(NSString * dirPath,
										 mode_t     permissions,
										 uid_t      owner,
										 gid_t      group);

NSString * fileIsReasonableSize(NSString * path);

NSString * allFilesAreReasonableIn(NSString * path);

NSDictionary * highestEditionForEachBundleIdinL_AS_T(void);

BOOL invalidConfigurationName (NSString * name,
                               const char badChars[]);

unsigned int getFreePort();

BOOL itemIsVisible(NSString * path);

BOOL makeUnlockedAtPath(NSString * path);

BOOL secureOneFolder(NSString * path, BOOL isPrivate, uid_t theUser);

NSDictionary * getSafeEnvironment(void);

OSStatus runTool(NSString * launchPath,
                 NSArray  * arguments,
                 NSString * * stdOut,
                 NSString * * stdErr);

void startTool(NSString * launchPath,
			   NSArray *  arguments);

NSString * newTemporaryDirectoryPath(void);

OSStatus runTunnelblickd(NSString * command, NSString ** stdoutString, NSString ** stderrString);

unsigned getLoadedKextsMask(void);

NSString * sanitizedConfigurationContents(NSString * cfgContents);
