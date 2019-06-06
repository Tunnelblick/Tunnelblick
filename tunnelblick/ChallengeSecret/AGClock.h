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

#import <Foundation/Foundation.h>

/**
 * AGClock objects represent a single point in time and used by OTP to calculate 
 * the time interval between either the current date or the specified date passed
 * during construction of the object.
 */

@interface AGClock : NSObject

/**
 * The date this AGClock object is initialized to.
 */
@property (nonatomic, copy) NSDate *date;

/**
 * Initialize a new AGClock object using the specified startingDate.
 *
 * @param startingDate The NSDate to initialize to.
 *
 * @returns A new AGClock object set to the date specified by startingDate.
 */
- (id)initWithDate:(NSDate *)startingDate;

/**
 * Calculate the time interval from the date this AGClock object
 * is initialized to.
 *
 * @returns the calculated time interval.
 */
- (uint64_t)currentInterval;

@end