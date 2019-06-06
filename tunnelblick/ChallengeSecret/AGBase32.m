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

#import "AGBase32.h"
#import "AGStringEncoding.h"

static NSString *const kBase32Charset = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
static NSString *const kBase32Synonyms =
        @"AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz";
static NSString *const kBase32Sep = @" -";

@implementation AGBase32

- (id)init {
    if ([self class] == [AGBase32 class]) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"Error, attempting to instantiate AGBase32 directly."
                                     userInfo:nil];
    }

    self = [super init];
    if (self) {
        // Initialization code here.
    }
    return self;
}

+ (NSData *)base32Decode:(NSString *)string {
    AGStringEncoding *coder =
            [AGStringEncoding stringEncodingWithString:kBase32Charset];
    [coder addDecodeSynonyms:kBase32Synonyms];
    [coder ignoreCharacters:kBase32Sep];
    return [coder decode:string];
}

@end