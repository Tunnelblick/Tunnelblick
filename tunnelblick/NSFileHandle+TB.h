/*
 * Copyright (c) 2024 Jonathan K. Bullard. All rights reserved.
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

NS_ASSUME_NONNULL_BEGIN

@interface NSFileHandle(TBFileHandle)

-(BOOL) tbCloseAndReturnError: (out NSError * _Nullable *) error;

NS_ASSUME_NONNULL_END

-(NSData * _Nullable ) tbReadDataToEndOfFileAndReturnError: (out NSError * _Nullable * _Nullable) error;

NS_ASSUME_NONNULL_BEGIN

-(BOOL) tbSeekToEndReturningOffset: (out unsigned long long *) offsetInFile
                             error: (out NSError * _Nullable *) error;

-(BOOL) tbSeekToOffset: (unsigned long long) offset
                 error: (out NSError * _Nullable *) error;

-(BOOL) tbTruncateAtOffset: (unsigned long long) offset
                     error: (out NSError * _Nullable *) error;

-(BOOL) tbWriteData: (NSData *) data
              error: (out NSError * _Nullable *) error;

@end

NS_ASSUME_NONNULL_END
