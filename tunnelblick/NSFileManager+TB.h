/*
 * Copyright (c) 2010, 2011, 2012 Jonathan K. Bullard. All rights reserved.
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

#import <Foundation/Foundation.h>


@interface NSFileManager (TB)

-(BOOL)           tbChangeFileAttributes:(NSDictionary *)attributes
                                  atPath:(NSString *)path;

-(BOOL)           tbCopyPath:(NSString *)source
                      toPath:(NSString *)destination
                     handler:(id)handler;

-(BOOL)         tbCopyFileAtPath: (NSString *) source
                          toPath: (NSString *) destination
 ownedByRootWheelWithPermissions: (mode_t)     permissions;

-(BOOL)    tbCopyItemAtPath: (NSString *) source
 toBeOwnedByRootWheelAtPath: (NSString *) destination;

-(BOOL)           tbCreateDirectoryAtPath:(NSString *)path
			  withIntermediateDirectories:(BOOL)withIntermediateDirectories
							   attributes:(NSDictionary *)attributes;

-(BOOL)           tbCreateSymbolicLinkAtPath:(NSString *)path
                                 pathContent:(NSString *)otherPath;

-(NSArray *)      tbDirectoryContentsAtPath:(NSString *)path;

-(NSDictionary *) tbFileAttributesAtPath:(NSString *)path
                            traverseLink:(BOOL)flag;

-(BOOL)           tbMovePath:(NSString *)source
                      toPath:(NSString *)destination
                     handler:(id)handler;

-(BOOL)           tbRemoveFileAtPath:(NSString *)path
                             handler:(id)handler;

-(BOOL)           tbRemovePathIfItExists: (NSString *) path;

-(BOOL)           tbForceRenamePath: (NSString *) sourcePath
                             toPath: (NSString *) targetPath;

-(BOOL) tbForceMovePath: (NSString *) sourcePath
                 toPath: (NSString *) targetPath;

-(NSString *)     tbPathContentOfSymbolicLinkAtPath:(NSString *)path;

@end
