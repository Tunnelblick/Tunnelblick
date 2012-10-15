/*
 * Copyright 2012  Jonathan K. Bullard
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


unsigned cvt_atou(const char * s, NSString * description);

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

unsigned int getFreePort(void);

BOOL itemIsVisible(NSString * path);

BOOL secureOneFolder(NSString * path, BOOL isPrivate);
