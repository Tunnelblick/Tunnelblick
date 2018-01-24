/*
 * JBoss, Home of Professional Open Source.
 * Copyright Red Hat, Inc., and individual contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "AGClock.h"

@implementation AGClock

- (id)init {
    return [self initWithDate:[NSDate date]];
}

- (id)initWithDate:(NSDate *)startingDate {
    if (self = [super init]) {
        self.date = startingDate;
    }
    return (self);
}

- (uint64_t)currentInterval {

    NSTimeInterval seconds = [self.date timeIntervalSince1970];
    uint64_t counter = (uint64_t) (seconds / 30);
    return counter;
}
@end