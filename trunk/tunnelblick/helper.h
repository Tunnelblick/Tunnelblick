/*
 *  Copyright (c) 2005, 2006, 2007, 2008, 2009 Angelo Laub
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

NSString     * configPathFromTblkPath   (NSString * path);
NSString     * tblkPathFromConfigPath   (NSString * path);

BOOL           checkOwnerAndPermissions (NSString * fPath,
                                         uid_t      uid,
                                         gid_t      gid,
                                         NSString * permsShouldHave);


NSString     * escaped                  (NSString * string);

BOOL           itemIsVisible            (NSString * path);

NSString     * firstPartOfPath          (NSString * thePath);
NSString     * lastPartOfPath           (NSString * thePath);
NSString     * firstPathComponent       (NSString * thePath);

NSString     * constructOpenVPNLogPath  (NSString * configurationPath,
                                         int        port);
NSString     * deconstructOpenVPNLogPath(NSString * logPath,
                                         int      * portPtr);

NSString     * tunnelblickVersion       (NSBundle * bundle);
NSDictionary * getOpenVPNVersion        (void);

int            TBRunAlertPanel          (NSString * title,
                                         NSString * msg,
                                         NSString * defaultButtonLabel,
                                         NSString * alternateButtonLabel,
                                         NSString * otherButtonLabel);

int            TBRunAlertPanelExtended  (NSString * title,
                                         NSString * msg,
                                         NSString * defaultButtonLabel,
                                         NSString * alternateButtonLabel,
                                         NSString * otherButtonLabel,
                                         NSString * doNotShowAgainPreferenceKey,
                                         NSString * checkboxLabel,
                                         BOOL     * checkboxResult);

BOOL           useDNSStatus             (id         connection);

BOOL           isUserAnAdmin            (void);

BOOL           runningOnTigerOrNewer    (void);
BOOL           runningOnLeopardOrNewer  (void);
BOOL           runningOnSnowLeopardOrNewer(void);
