//
//  Taken with small modifications
//  GTMStringEncoding.m
//
//  Copyright 2009 Google Inc.
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

#import "AGStringEncoding.h"

enum {
  kUnknownChar = -1,
  kPaddingChar = -2,
  kIgnoreChar = -3
};

@implementation AGStringEncoding

+ (id)stringEncodingWithString:(NSString *)string {
  return [[self alloc] initWithString:string];
}

- (id)initWithString:(NSString *)string {
  if ((self = [super init])) {
    charMapData_ = [string dataUsingEncoding:NSASCIIStringEncoding];
    if (!charMapData_) {
        return nil;
    }
    charMap_ = (char *)[charMapData_ bytes];
    NSUInteger length = [charMapData_ length];
    if (length < 2 || length > 128 || length & (length - 1)) {
        return nil;
    }

    memset(reverseCharMap_, kUnknownChar, sizeof(reverseCharMap_));
    for (unsigned int i = 0; i < length; i++) {
      if (reverseCharMap_[(int)charMap_[i]] != kUnknownChar) {
          return nil;
      }
      reverseCharMap_[(int)charMap_[i]] = i;
    }

    for (NSUInteger i = 1; i < length; i <<= 1)
      shift_++;
    mask_ = (1 << shift_) - 1;
  }
  return self;
}

- (NSString *)description {
  // TODO(iwade) track synonyms
  return [NSString stringWithFormat:@"<Base%d StringEncoder: %@>",
          1 << shift_, charMapData_];
}

- (void)addDecodeSynonyms:(NSString *)synonyms {
  char *buf = (char *)[synonyms cStringUsingEncoding:NSASCIIStringEncoding];
  int val = kUnknownChar;
  while (*buf) {
    int c = *buf++;
    if (reverseCharMap_[c] == kUnknownChar) {
      reverseCharMap_[c] = val;
    } else {
      val = reverseCharMap_[c];
    }
  }
}

- (void)ignoreCharacters:(NSString *)chars {
  char *buf = (char *)[chars cStringUsingEncoding:NSASCIIStringEncoding];
  while (*buf) {
    int c = *buf++;
    reverseCharMap_[c] = kIgnoreChar;
  }
}

- (NSString *)encode:(NSData *)inData {
  NSUInteger inLen = [inData length];
  if (inLen <= 0) {
    return @"";
  }
  unsigned char *inBuf = (unsigned char *)[inData bytes];
  NSUInteger inPos = 0;

  NSUInteger outLen = (inLen * 8 + shift_ - 1) / shift_;
  if (doPad_) {
    outLen = ((outLen + padLen_ - 1) / padLen_) * padLen_;
  }
  NSMutableData *outData = [NSMutableData dataWithLength:outLen];
  unsigned char *outBuf = (unsigned char *)[outData mutableBytes];
  NSUInteger outPos = 0;

  int buffer = inBuf[inPos++];
  int bitsLeft = 8;
  while (bitsLeft > 0 || inPos < inLen) {
    if (bitsLeft < shift_) {
      if (inPos < inLen) {
        buffer <<= 8;
        buffer |= (inBuf[inPos++] & 0xff);
        bitsLeft += 8;
      } else {
        int pad = shift_ - bitsLeft;
        buffer <<= pad;
        bitsLeft += pad;
      }
    }
    int idx = (buffer >> (bitsLeft - shift_)) & mask_;
    bitsLeft -= shift_;
    outBuf[outPos++] = charMap_[idx];
  }

  if (doPad_) {
    while (outPos < outLen)
      outBuf[outPos++] = paddingChar_;
  }

  [outData setLength:outPos];

  return [[NSString alloc] initWithData:outData
                                encoding:NSASCIIStringEncoding];
}

- (NSData *)decode:(NSString *)inString {
  char *inBuf = (char *)[inString cStringUsingEncoding:NSASCIIStringEncoding];
  if (!inBuf) {
    return nil;
  }
  NSUInteger inLen = strlen(inBuf);

  NSUInteger outLen = inLen * shift_ / 8;
  NSMutableData *outData = [NSMutableData dataWithLength:outLen];
  unsigned char *outBuf = (unsigned char *)[outData mutableBytes];
  NSUInteger outPos = 0;

  int buffer = 0;
  int bitsLeft = 0;
  BOOL expectPad = NO;
  for (NSUInteger i = 0; i < inLen; i++) {
    int val = reverseCharMap_[(int)inBuf[i]];
    switch (val) {
      case kIgnoreChar:
        break;
      case kPaddingChar:
        expectPad = YES;
        break;
      case kUnknownChar:
        return nil;
      default:
        if (expectPad) {
          return nil;
        }
        buffer <<= shift_;
        buffer |= val & mask_;
        bitsLeft += shift_;
        if (bitsLeft >= 8) {
          outBuf[outPos++] = (unsigned char)(buffer >> (bitsLeft - 8));
          bitsLeft -= 8;
        }
        break;
    }
  }

  if (bitsLeft && buffer & ((1 << bitsLeft) - 1)) {
    return nil;
  }

  // Shorten buffer if needed due to padding chars
  [outData setLength:outPos];

  return outData;
}

@end
