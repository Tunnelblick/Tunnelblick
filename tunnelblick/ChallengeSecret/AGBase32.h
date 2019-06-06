//
//  Taken with small modifications
//
//  Copyright 2011 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not
//  use this file except in compliance with the License.  You may obtain a copy
//  of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
//  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
//  License for the specific language governing permissions and limitations under
//  the License.
//

#import <Foundation/Foundation.h>

/**
 * Utility methods for handling Base32 encoding schemas.
 */
@interface AGBase32 : NSObject

/**
 * Creates and returns a data object by decoding the given base32 encoded string.
 *
 * @param string The base32 string from which to decode.
 *
 * @return A data object containing the data from the decoded string.
 */
+ (NSData *)base32Decode:(NSString *)string;

@end