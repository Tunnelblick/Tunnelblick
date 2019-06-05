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

#import "AGOtp.h"
#import "AGClock.h"

#import <CommonCrypto/CommonCrypto.h>

const uint32_t digitsModLut[] = { 0, 0, 0, 0, 0, 0, 1000000, 10000000, 100000000 };
const uint32_t defaultDigits = 6;

@interface AGOtp ()
@property (readwrite, nonatomic, copy) NSData *secret;
@end

@implementation AGOtp {
    uint32_t digitsMod_;
}

@synthesize secret = secret_;
@synthesize digits = digits_;

- (id)init {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (id)initWithSecret:(NSData *)secret {
  if ((self = [super init])) {
    secret_    = [secret copy];
    digits_    = defaultDigits;
    digitsMod_ = digitsModLut[defaultDigits];
  }
  return self;
}

- (id)initWithDigits:(uint32_t)digits andSecret:(NSData *)secret {
  NSAssert((digits >= 6) && (digits <= 8),@"digits can only be between 6 and 8");
  if ((self = [super init])) {
    secret_    = [secret copy];
    digits_    = digits;
    digitsMod_ = digitsModLut[digits];
  }
  return self;
}

- (void)dealloc {
  self.secret = nil;
}

// Must be overriden by subclass.
- (NSString *)generateOTP {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (NSString *)generateOTPForCounter:(uint64_t)counter {
  CCHmacAlgorithm alg = kCCHmacAlgSHA1;
  NSUInteger hashLength = CC_SHA1_DIGEST_LENGTH;

  NSMutableData *hash = [NSMutableData dataWithLength:hashLength];

  counter = NSSwapHostLongLongToBig(counter);
  NSData *counterData = [NSData dataWithBytes:&counter
                                       length:sizeof(counter)];
  CCHmacContext ctx;
  CCHmacInit(&ctx, alg, [secret_ bytes], [secret_ length]);
  CCHmacUpdate(&ctx, [counterData bytes], [counterData length]);
  CCHmacFinal(&ctx, [hash mutableBytes]);

  const char *ptr = [hash bytes];
  char const offset = ptr[hashLength-1] & 0x0f;
  uint32_t truncatedHash =
    NSSwapBigIntToHost(*((uint32_t *)&ptr[offset])) & 0x7fffffff;
  uint32_t pinValue = truncatedHash % digitsMod_;

  return [NSString stringWithFormat:@"%0*d", digits_, pinValue];
}

@end
