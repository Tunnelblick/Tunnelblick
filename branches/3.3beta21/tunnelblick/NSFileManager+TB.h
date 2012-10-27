/*
 * Copyright (c) 2010 Jonathan Bullard
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

#import <Cocoa/Cocoa.h>


@interface NSFileManager (TB)

-(BOOL)           tbChangeFileAttributes:(NSDictionary *)attributes
                                  atPath:(NSString *)path;

-(BOOL)           tbCopyPath:(NSString *)source
                      toPath:(NSString *)destination
                     handler:(id)handler;

-(BOOL)           tbCreateDirectoryAtPath:(NSString *)path
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

-(NSString *)     tbPathContentOfSymbolicLinkAtPath:(NSString *)path;

@end
