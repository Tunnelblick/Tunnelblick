/*
 * Copyright 2024 Jonathan K. Bullard. All rights reserved.
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
 *  distribution); if not, see http://www.gnu.org/licenses/.
 */

#import "TBValidator.h"

#import <Security/Security.h>

#import "UpdateSigning.h"

NSString * callStack(void);


@implementation TBValidator


#pragma mark - Private Methods

-(void) appendLog: (NSString *) message {

    [logger performSelector: @selector(appendLog:) withObject: message];
}

-(BOOL) isNowBefore: (NSString *) beforeDateTime
            orAfter: (NSString *) afterDateTime {

    // Returns TRUE if the current date is before or after the specified date/times
    // Each date/time should be a string of the form YYYY-MM-DDTHH:MM:SS

    // Get current date and time
    NSDateFormatter * formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setDateFormat: @"yyyy-MM-dd'T'HH:mm:ss"];
    [formatter setTimeZone: [NSTimeZone timeZoneForSecondsFromGMT: 0]];
    [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    NSString * currentDateTime = [formatter stringFromDate: [NSDate date]];

    if (   (NSOrderedDescending == [beforeDateTime compare: currentDateTime])
        || (NSOrderedAscending  == [afterDateTime compare: currentDateTime])  ) {
        [logger appendLog: [NSString stringWithFormat:
                            @"Failed to verify appcast signature; signature not valid now (%@); it is valid from %@ to %@",
                            currentDateTime, beforeDateTime, afterDateTime]];
        return YES;
    }

    return NO;
}

#pragma mark - Public Methods

-(TBValidator *) initWithLogger: (id) _logger {

    if (  (self = [super init])  ) {
        logger = [_logger retain];
    }

    return self;
}

-(BOOL) validateAppcastData: (NSData *)   data
           withPublicDSAKey: (NSString *) pkeyString {

    /* Verifies that the contents of data were signed using the digital signature in an XML/HTML comment prepended to the contents.

     "data" is the data to be validated (presumably the downloaded data of an appcast).
     "pkeyString" is the public key used to verify the signature.

     The data must start with two fixed-length XML/HTML comments:

     The "signature comment" contains a digital signature of the remainder of the data.
     The comment is of the form:
     <!-- Tunnelblick_DSA_Signature v4 SIGNATURE -->\n
     where SIGNATURE is a 96-character base-64-URL-encoded ECDSA with SHA‑256 (X9.62 format) digital signature

     The "validation comment" contains information about the validity of the file.
     The comment is of the form:
     <!--LENGTH BEFORE_DATE AFTER_DATE -->\n
     where LENGTH (7 digits with leading zeroes) is the length in bytes of the remainder of the data after the validation comment and its terminating LF;
     and BEFORE_DATE (YYYY-MM-DDTHH:MM:SS) is the date before which the signature is NOT valid;
     and AFTER_DATE (YYYY-MM-DDTHH:MM:SS)  is the date after which the signature is NOT valid.

     In both comments, there must be exactly one space character between each part of the comment.

     Example:

     <!-- Tunnelblick_Signature v4 MEYCIQDjFXeAL73pKwOfqeflY1ZDEZJb5r4gMafQu_SLC1nLRgIhALwx-NuezHB58MexEtgDAdlfxzQ81lkK9riq0GBZHGmj -->
     <!-- 0000833 2017-01-15T22:59:02 2017-03-15T22:59:02 -->

     <!-- Tunnelblick_Signature v4 MEYCIQDjFXeAL73pKwOfqeflY1ZDEZJb5r4gMafQu_SLC1nLRgIhALwx-NuezHB58MexEtgDAdlfxzQ81lkK9riq0GBZHGmj -->
     <!-- Tunnelblick_Signature v2 MC0CFQCAV//wNMa58PV2aK5vZTkgjHZUxQIUYGmBaucjkcQrQ1ONbpp40bu3sYY= -->
     <!-- 0005601 2025-10-26T12:02:50 2025-12-25T12:02:50 -->

     Notes:
     1. The validity comment and LF is prepended to the data, the signature is calculated on the result, and then the signature
     comment and LF is prepended to the data, so the signature protects the validity information.
     2. The comments are plain (7-bit) ASCII, but the remainder of the file can have any encoding.
     */

    // Lengths of fields in the comments are fixed as follows (all must fit in an unsigned integer:
#define TB_APPCAST_SIGNATURE_COMMENT_LENGTH       131
#define TB_APPCAST_VALIDATION_COMMENT_LENGTH      57
#define TB_APPCAST_NUMBER_OF_PARSED_FIELDS         9
#define TB_APPCAST_ENCODED_SIGNATURE_LENGTH       96
#define TB_APPCAST_DATE_LENGTH                    19
#define TB_APPCAST_LENGTH_LENGTH                   7
    //  if  TB_LENGTH_LENGTH changes, the format string used to create payloadLengthString must be modified correspondingly

    if (  !data || !pkeyString  ) {
        [logger appendLog: @"validateAppcastData: data and/or PublicDSAKey == nil"];
        return NO;
    }

    if (   (data.length <= TB_APPCAST_SIGNATURE_COMMENT_LENGTH + TB_APPCAST_VALIDATION_COMMENT_LENGTH + 10) // +10 to make sure there are some contents
        || (data.length > TB_APPCAST_MAX_FILE_SIZE)  ) {
        [logger appendLog: @"validateAppcastData: data to validate is too short or too long"];
        return NO;
    }

    // Isolate the comments and "parse" them into fields separated by a single space character
    NSString * comments = [[[NSString alloc] initWithBytes: [data bytes]
                                                    length: (TB_APPCAST_SIGNATURE_COMMENT_LENGTH + TB_APPCAST_VALIDATION_COMMENT_LENGTH)
                                                  encoding: NSASCIIStringEncoding] autorelease];
    if (  ! comments  ) {
        [logger appendLog: @"validateAppcastData: Failed to verify appcast signature; the signature and validation comments are not 7-bit ASCII"];
        return NO;
    }
    NSArray * parsed = [comments componentsSeparatedByString: @" "];
    if (  [parsed count] != TB_APPCAST_NUMBER_OF_PARSED_FIELDS  ) {
        [logger appendLog: [NSString stringWithFormat:
                            @"validateAppcastData: Failed to verify appcast signature;"
                            @" the signature and validation comments had %lu fields; they should have %u fields",
                            (unsigned long)[parsed count], TB_APPCAST_NUMBER_OF_PARSED_FIELDS]];
        return NO;
    }

    // Check the fixed components of the comments
    if (   [[parsed objectAtIndex: 0] isNotEqualTo: @"<!--"]
        || [[parsed objectAtIndex: 1] isNotEqualTo: @"Tunnelblick_Signature"]
        || [[parsed objectAtIndex: 2] isNotEqualTo: @"v4"]
        || [[parsed objectAtIndex: 4] isNotEqualTo: @"-->\n<!--"]
        || [[parsed objectAtIndex: 8] isNotEqualTo: @"-->\n"]
        ) {
        [logger appendLog: @"validateAppcastData: Failed to verify appcast signature; one or more fixed fields were not correct"];
        return NO;
    }

    // Extract and check the variable components of the comments
    NSString * signature  = [parsed objectAtIndex: 3];
    NSString * length     = [parsed objectAtIndex: 5];
    NSString * beforeDate = [parsed objectAtIndex: 6];
    NSString * afterDate  = [parsed objectAtIndex: 7];

    if (   ([signature  length] != TB_APPCAST_ENCODED_SIGNATURE_LENGTH)
        || ([length     length] != TB_APPCAST_LENGTH_LENGTH)
        || ([beforeDate length] != TB_APPCAST_DATE_LENGTH)
        || ([afterDate  length] != TB_APPCAST_DATE_LENGTH)
        ) {
        [logger appendLog: @"validateAppcastData: Failed to verify appcast signature; one or more variable fields was not the correct length"];
        return NO;
    }

    // The "payloadLength" is the length of the file before the comments were prepended to it.
    unsigned long payloadLength = data.length - TB_APPCAST_SIGNATURE_COMMENT_LENGTH - TB_APPCAST_VALIDATION_COMMENT_LENGTH;
    NSString * payloadLengthString = [NSString stringWithFormat: @"%07lu", payloadLength];
    if (   [length isNotEqualTo: payloadLengthString]  ) {
        [logger appendLog: [NSString stringWithFormat:
                            @"validateAppcastData: Failed to verify appcast signature;"
                            @"expected payload length was '%@' but the actual payload length was '%@'; ",
                            length, payloadLengthString]];
        return NO;
    }

    if (   [[beforeDate substringWithRange: NSMakeRange(4,  1)] isNotEqualTo: @"-"]
        || [[beforeDate substringWithRange: NSMakeRange(7,  1)] isNotEqualTo: @"-"]
        || [[beforeDate substringWithRange: NSMakeRange(10, 1)] isNotEqualTo: @"T"]
        || [[beforeDate substringWithRange: NSMakeRange(13, 1)] isNotEqualTo: @":"]
        || [[beforeDate substringWithRange: NSMakeRange(16, 1)] isNotEqualTo: @":"]
        || [[afterDate  substringWithRange: NSMakeRange(4,  1)] isNotEqualTo: @"-"]
        || [[afterDate  substringWithRange: NSMakeRange(7,  1)] isNotEqualTo: @"-"]
        || [[afterDate  substringWithRange: NSMakeRange(10, 1)] isNotEqualTo: @"T"]
        || [[afterDate  substringWithRange: NSMakeRange(13, 1)] isNotEqualTo: @":"]
        || [[afterDate  substringWithRange: NSMakeRange(16, 1)] isNotEqualTo: @":"]  ) {
        [logger appendLog: @"validateAppcastData: Failed to verify appcast signature; one or more date fields was not formatted properly (must be YYYY-MM-DDTHH:MM:SS)"];
        return NO;
    }

    // Verify the signature on the data
    unsigned long signedLength = TB_APPCAST_VALIDATION_COMMENT_LENGTH + payloadLength;
    const void * signedStart = (const void *)(((const char *)[data bytes]) + TB_APPCAST_SIGNATURE_COMMENT_LENGTH);
    NSData * signedContents = [NSData dataWithBytes: signedStart length: signedLength];

    NSString * errorMessage = nil;

    BOOL signatureIsGood = [UpdateSigning verifyData: signedContents
                                     signatureBase64: signature
                                     publicKeyBase64: pkeyString
                                     errorMessagePtr: &errorMessage];
    if (  ! signatureIsGood  ) {
        [logger appendLog: [NSString stringWithFormat: @"validateAppcastData: Failed to verify appcast signature: %@", errorMessage]];
        return NO;
    }

    if (  [self isNowBefore: beforeDate
                    orAfter: afterDate]  ) {
        return NO;    // (Error message has been logged)
    }

    [logger appendLog: [NSString stringWithFormat: @"validateAppcastData: Verified appcast with signature '%@'", signature]];
    return YES;
}

-(BOOL) validateUpdateData: (NSData *)   data
             withSignature: (NSString *) signature
          withPublicDSAKey: (NSString *) publicKey {

    // Verifies that the contents of the update data with the proposed signature were signed with the public key.
    //
    //  "data" is the data to be validated (the downloaded .zip for an update).

    if (   ( ! data)
        || ( ! signature)
        || ( ! publicKey)  ) {
        [logger appendLog: @"validateUpdateData: data, signature, and/or public key == nil"];
        return NO;
    }

    NSString * errorMessage = nil;

    BOOL itemSignatureIsGood = [UpdateSigning verifyData: data
                                         signatureBase64: signature
                                         publicKeyBase64: publicKey
                                         errorMessagePtr: &errorMessage];
    if (  ! itemSignatureIsGood  ) {
        [logger appendLog: [NSString stringWithFormat: @"validateUpdateData: Failed to verify update .zip signature: %@", errorMessage]];
        return NO;
    }

    [logger appendLog: [NSString stringWithFormat: @"validateUpdateData: Verified update .zip signature '%@'", signature]];
    return YES;
}

@end

