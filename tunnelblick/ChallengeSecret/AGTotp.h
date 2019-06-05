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
#import "AGOtp.h"

@class AGClock;

/**
 * The Totp class generates a one-time password (OTP) using
 * the Time-based One-time Password Algorithm described in:
 * http://tools.ietf.org/html/draft-mraihi-totp-timebased
 *
 * Basically, we define TOTP as TOTP = HOTP(K, T) where T is an integer
 * and represents the number of time steps between the initial counter
 * time T0 and the current Unix time (i.e. the number of seconds elapsed
 * since midnight UTC of January 1, 1970).
 *
 * More specifically T = (Current Unix time - T0) / X where:
 *
 * - X represents the time step in seconds (default value X = 30
 *   seconds) and is a system parameter;
 *
 * - T0 is the Unix time to start counting time steps (default value is
 *   0, Unix epoch) and is also a system parameter.
 */
@interface AGTotp : AGOtp

@property (nonatomic, copy) AGClock *clock;

/**
 * Returns an AGTotp object initialized with a secret specified by the given string.
 *
 * @param secret The secret to use.
 *
 * @return An AGTotp object initialized by the specified secret.
 */
- (id)initWithSecret:(NSData *)secret;

/**
 * Returns an AGTOtp object initialized with a non-default digit length and secret specified by the given string.
 *
 * @param digits The number of digits to use in the returned OTP code (min. 6, max. 8)
 * @param secret The secret to use.
 *
 * @return An AGTotp object initialized by the specified secret.
 */
- (id)initWithDigits:(uint32_t)digits andSecret:(NSData *)secret;


/**
 * Generate an TOTP token using the current time.
 * 
 * @returns An NSString that contains the token with leading zero-padding as required.
 */
- (NSString *)now;

/**
 * Generate an TOTP token using the specified AGClock.
 *
 * @param clock The AGClock object to use.
 *
 * @returns An NSString that contains the token with leading zero-padding as required.
 */
- (NSString *)now:(AGClock *)clock;

@end
