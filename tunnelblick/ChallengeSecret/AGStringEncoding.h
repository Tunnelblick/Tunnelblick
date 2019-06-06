//
//  Taken with small modifications
//  GTMStringEncoding.h
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
 * A generic class for arbitrary base-2 to 128 string encoding and decoding.
 */
@interface AGStringEncoding : NSObject {
 @private
  NSData *charMapData_;
  char *charMap_;
  int reverseCharMap_[128];
  int shift_;
  int mask_;
  BOOL doPad_;
  char paddingChar_;
  int padLen_;
}

/**
 * Creates and returns a new autoreleased AGStringEncoding object initialized by the given string.
 *
 * @param string The string to use.
 *
 * @return An AGStringEncoding object initialized by the given string.
 */
+ (id)stringEncodingWithString:(NSString *)string;

/**
 * Returns an AGStringEncoding object initialized by the specified string.
 *
 * The length of the string must be a power of 2, at least 2 and at most 128.
 * Only 7-bit ASCII characters are permitted in the string.
 *
 * These characters are the canonical set emitted during encoding.
 * If the characters have alternatives (e.g. case, easily transposed) then use
 * addDecodeSynonyms: to configure them.
 *
 * @param string The string to use.
 *
 * @return An AGStringEncoding object initialized by the given string.
 */
- (id)initWithString:(NSString *)string;

/**
 * Add decoding synonyms as specified in the synonyms argument.
 *
 * It should be a sequence of one previously reverse mapped character,
 * followed by one or more non-reverse mapped character synonyms.
 * Only 7-bit ASCII characters are permitted in the string.
 *
 * e.g. If a GTMStringEncoder object has already been initialised with a set
 * of characters excluding I, L and O (to avoid confusion with digits) and you
 * want to accept them as digits you can call addDecodeSynonyms:@"0oO1iIlL".
 *
 * @param synonyms the sequence of synonyms.
 */
- (void)addDecodeSynonyms:(NSString *)synonyms;

/**
 * A sequence of characters to ignore if they occur during encoding.
 * 
 * Only 7-bit ASCII characters are permitted in the string.
 *
 * @param chars The sequence of chars to ignore.
 */
- (void)ignoreCharacters:(NSString *)chars;

/**
 * Encode a raw binary buffer to a 7-bit ASCII string.
 *
 * @param data The data to encode
 *
 * @return The encoded string
 */
- (NSString *)encode:(NSData *)data;

/**
 * Decode a 7-bit ASCII string to a raw binary buffer.
 *
 * @param string The string to decode
 *
 * @return The raw binary buffer
 */
- (NSData *)decode:(NSString *)string;

@end
