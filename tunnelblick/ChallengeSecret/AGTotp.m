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

#import "AGTotp.h"
#import "AGClock.h"

const NSUInteger defaultInterval = 30;

@interface AGTotp ()

@end

@implementation AGTotp

- (id)initWithSecret:(NSData *)secret {
    if ((self = [super initWithSecret:secret])) {
    }
    return (self);
}

- (id)initWithDigits:(uint32_t)digits andSecret:(NSData *)secret {
    if ((self = [super initWithDigits:digits andSecret:secret])) {
    }
    return (self);
}

- (NSString *)generateOTP {
    return [self now];
}

- (NSString *)now {
    return [self now:[[[AGClock alloc] init] autorelease]];
}

- (NSString *)now:(AGClock *)clock {
    uint64_t interval = [clock currentInterval];
    return [super generateOTPForCounter:interval];
}

-(void) dealloc {
    [_clock release];
    _clock = nil;
    [super dealloc];
}

@end
