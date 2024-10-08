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
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *  or see http://www.gnu.org/licenses/.
 */

#import "TBValidator.h"

#import <CommonCrypto/CommonDigest.h>

NSString * callStack(void);


@implementation TBValidator

-(TBValidator *) initWithLogger: (id) _logger {

    if (  (self = [super init])  ) {
        logger = [_logger retain];
    }

    return self;
}

-(void) appendLog: (NSString *) message {

    [logger performSelector: @selector(appendLog:) withObject: message];
}

-(BOOL) validateAppcastData: (NSData *)   data
           withPublicDSAKey: (NSString *) pkeyString {

    // This method is a modified version of Tunenlblick's 03_Require_signed_appcasts.diff patch for Sparkle.

    /* Verifies that the contents of data were signed using a digital signature in an XML/HTML comment prepended to the contents.

     "data" is the data to be validated (presumably the downloaded data of an appcast).
     "publicDSAKey" is used to verify the signature.

     The data must start with two fixed-length XML/HTML comments:

     The "signature comment" contains a digital signature of the remainder of the data.
     The comment 103 bytes long and is of the form:
     <!-- Tunnelblick_DSA_Signature v2 SIGNATURE -->\n
     where SIGNATURE is a 64-character base-64 encoded digital signature created by the Sparkle-provided "sign_update.rb"
     command using a private DSA key.

     The "validation comment" contains information about the validity of the file.
     The comment is of the form:
     <!--LENGTH BEFORE_DATE AFTER_DATE -->\n
     where LENGTH (7 digits with leading zeroes) is the length in bytes of the remainder of the data after the validation comment and its terminating LF;
     and BEFORE_DATE (YYYY-MM-DDTHH:MM:SS) is the date before which the signature is NOT valid;
     and AFTER_DATE (YYYY-MM-DDTHH:MM:SS)  is the date after which the signature is NOT valid.

     In both comments, there must be exactly one space character between each part of the comment.

     Example:

     <!-- Tunnelblick_Signature v2 MC4CFQCt61RNh0xUU9AtTI/7yoXqDURxQAIVAJGrfk+pD1iRy8ggGtV2meEK6qxD ->
     <!-- 0000833 2017-01-15T22:59:02 2017-03-15T22:59:02 ->


     Notes:
     1. The validity comment and LF is prepended to the data, the signature is calculated on the result, and then the signature
     comment and LF is prepended to the data, so the signature protects the validity information.
     2. The comments are plain (7-bit) ASCII, but the remainder of the file can have any encoding.
     */

    // Lengths of fields in the comments are fixed as follows (all must fit in an unsigned integer:
#define TB_APPCAST_SIGNATURE_COMMENT_LENGTH       99
#define TB_APPCAST_VALIDATION_COMMENT_LENGTH      57
#define TB_APPCAST_NUMBER_OF_PARSED_FIELDS         9
#define TB_APPCAST_ENCODED_SIGNATURE_LENGTH       64
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
        || [[parsed objectAtIndex: 2] isNotEqualTo: @"v2"]
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
    BOOL itemSignatureIsGood = [self validateData: signedContents withEncodedDSASignature: signature withPublicDSAKey: pkeyString];
    if (  ! itemSignatureIsGood  ) {
        [logger appendLog: @"validateAppcastData: Failed to verify appcast signature"];
        return NO;
    }

    if (  [self isNowBefore: beforeDate
                    orAfter: afterDate]  ) {
        return NO;    // (Error message has been logged)
    }

    [logger appendLog: @"validateAppcastData: Verified appcast signature"];
    return YES;
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
                   @"Failed to verify appcast signature; signature not yet now (%@); it is valid from %@ to %@",
                   currentDateTime, beforeDateTime, afterDateTime]];
        return YES;
    }

    return NO;
}

-(BOOL) validateUpdateData: (NSData *)   data
             withSignature: (NSString *) signature
          withPublicDSAKey: (NSString *) publicKey {

    // Verifies that the contents of the update data were signed using a digital signature.
    //
    //  "data" is the data to be validated (the downloaded .zip for an update).

    if (  !data  ) {
        [logger appendLog: @"validateUpdateData: data == nil"];
        return NO;
    }

    BOOL itemSignatureIsGood = [self validateData: data
                          withEncodedDSASignature: signature
                                 withPublicDSAKey: publicKey];
    if (  ! itemSignatureIsGood  ) {
        [logger appendLog: @"validateUpdateData: Failed to verify update .zip signature"];
        return NO;
    }

    [logger appendLog: @"validateUpdateData: Verified update .zip signature"];
    return YES;
}

-(BOOL)    validateData: (NSData *)   data
withEncodedDSASignature: (NSString *) encodedSignature
       withPublicDSAKey: (NSString *) pkeyString {

    // This method was copied from the Sparkle source code version 1.5b6 and has been modified as follows:
    //
    //      * This introductory comment and some whitespace changes were made.
    //      * References to NSLog were changed to appendUpdateLog.
    //      * Code from initWithPublicKeyData: was copied in to set _secKey
    //

    if (  !data || !encodedSignature || !pkeyString  ) {
        [logger appendLog: [NSString stringWithFormat:
                   @"validateData:withEncodedDSASignature:withPublicDSAKey: data (%@), encodedSignature (%@), and/or publicDSAKey (%@) == nil; stack trace = \n%@",
                   data, encodedSignature, pkeyString, callStack()]];
        return NO;
    }

    NSData * pkeyData = [pkeyString dataUsingEncoding:NSUTF8StringEncoding];

    SecKeyRef _secKey = NULL;

    // START OF MODIFIED CODE FROM SUDSAVerifier initWithPublicKeyData: which sets _secKey

    if (  pkeyData.length == 0  ) {
        [logger appendLog: @"validateData:withEncodedDSASignature:withPublicDSAKey: Could not read public DSA key"];
        return NO;
    }

    SecExternalFormat format = kSecFormatOpenSSL;
    SecExternalItemType itemType = kSecItemTypePublicKey;
    CFArrayRef items = NULL;

    OSStatus status = SecItemImport((__bridge CFDataRef)pkeyData, NULL, &format, &itemType, (SecItemImportExportFlags)0, NULL, NULL, &items);
    if (status != errSecSuccess || !items) {
        if (items) {
            CFRelease(items);
        }
        [logger appendLog: [NSString stringWithFormat:
                   @"validateData:withEncodedDSASignature:withPublicDSAKey: Public DSA key could not be imported: %d",
                   status]];
        return NO;
    }

    if (format == kSecFormatOpenSSL && itemType == kSecItemTypePublicKey && CFArrayGetCount(items) == 1) {
        // Seems silly, but we can't quiet the warning about dropping CFTypeRef's const qualifier through
        // any manner of casting I've tried, including interim explicit cast to void*. The -Wcast-qual
        // warning is on by default with -Weverything and apparently became more noisy as of Xcode 7.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-qual"
        _secKey = (SecKeyRef)CFRetain(CFArrayGetValueAtIndex(items, 0));
#pragma clang diagnostic pop
    } else {
        [logger appendLog: @"validateData:withEncodedDSASignature:withPublicDSAKey: key was not in proper format"];
        return NO;
    }

    if ( items ) {
        CFRelease(items);
    }
    // END OF CODE FROM SUDSAVerifier

    NSString *strippedSignature = [encodedSignature stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSData *signature = [[[NSData alloc] initWithBase64EncodedString: strippedSignature options: 0] autorelease];
    if (  ! signature  ) {
        [logger appendLog: [NSString stringWithFormat:
                   @"validateData:withEncodedDSASignature:withPublicDSAKey: signature includes non-base64 characters: '%@'",
                   strippedSignature]];
        return NO;
    }

    NSInputStream *dataInputStream = [NSInputStream inputStreamWithData:data];
    BOOL result = [self verifyStream:dataInputStream signature:signature secKeyRef: _secKey];

    if (  _secKey ) {
        CFRelease(_secKey);
    }

    return result;
}

-(BOOL) verifyStream: (NSInputStream *) stream
           signature: (NSData *)        signature
           secKeyRef: (SecKeyRef)      _secKey {

    // This method was copied from the Sparkle source code version 1.5b6 and has been modified as follows:
    //
    //      * This introductory comment and some whitespace changes were made.
    //      * References to NSLog were changed to appendUpdateLog.
    //      * The _secKey parameter was added (it was a reference to an instance variable set in initWithPublicKeyData)
    //      * Renamed internal-to-this-method routing "cleanup" to cleanupVerifyStream
    //

    if (  !stream || !signature || !_secKey  ) {
        return NO;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    __block SecGroupTransformRef group = SecTransformCreateGroupTransform();
    __block SecTransformRef dataReadTransform = NULL;
    __block SecTransformRef dataDigestTransform = NULL;
    __block SecTransformRef dataVerifyTransform = NULL;
    __block CFErrorRef error = NULL;
#pragma clang diagnostic pop

    BOOL (^cleanupVerifyStreamSignatureWithPublicDSAKey)(void) = ^{
        if (group) CFRelease(group);
        if (dataReadTransform) CFRelease(dataReadTransform);
        if (dataDigestTransform) CFRelease(dataDigestTransform);
        if (dataVerifyTransform) CFRelease(dataVerifyTransform);
        if (error) CFRelease(error);
        return NO;
    };

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    dataReadTransform = SecTransformCreateReadTransformWithReadStream((__bridge CFReadStreamRef)stream);
#pragma clang diagnostic pop
    if (!dataReadTransform) {
        [logger appendLog: @"File containing update archive could not be read (failed to create SecTransform for input stream)"];
        return cleanupVerifyStreamSignatureWithPublicDSAKey();
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    dataDigestTransform = SecDigestTransformCreate(kSecDigestSHA1, CC_SHA1_DIGEST_LENGTH, NULL);
#pragma clang diagnostic pop
    if (!dataDigestTransform) {
        return cleanupVerifyStreamSignatureWithPublicDSAKey();
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    dataVerifyTransform = SecVerifyTransformCreate(_secKey, (__bridge CFDataRef)signature, &error);
#pragma clang diagnostic pop
    if (!dataVerifyTransform || error) {
        [logger appendLog: [NSString stringWithFormat:
                   @"Could not understand format of the signature: %@; Signature data: %@",
                   error, signature]];
        return cleanupVerifyStreamSignatureWithPublicDSAKey();
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    SecTransformConnectTransforms(dataReadTransform, kSecTransformOutputAttributeName, dataDigestTransform, kSecTransformInputAttributeName, group, &error);
#pragma clang diagnostic pop
    if (error) {
        [logger appendLog: [NSString stringWithFormat:
                   @"SecTransformConnectTransforms #1: Error: %@",
                   error]];
        return cleanupVerifyStreamSignatureWithPublicDSAKey();
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    SecTransformConnectTransforms(dataDigestTransform, kSecTransformOutputAttributeName, dataVerifyTransform, kSecTransformInputAttributeName, group, &error);
#pragma clang diagnostic pop
    if (error) {
        [logger appendLog: [NSString stringWithFormat:
                   @"SecTransformConnectTransforms #2: Error: %@",
                   error]];
        return cleanupVerifyStreamSignatureWithPublicDSAKey();
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSNumber *result = CFBridgingRelease(SecTransformExecute(group, &error));
#pragma clang diagnostic pop
    if (error) {
        [logger appendLog: [NSString stringWithFormat:
                   @"DSA signature verification failed: %@",
                   error]];
        return cleanupVerifyStreamSignatureWithPublicDSAKey();
    }

    if (!result.boolValue) {
        [logger appendLog: @"DSA signature does not match. Data of the update file being checked is different than data that has been signed, or the public key and the private key are not from the same set."];
    }

    cleanupVerifyStreamSignatureWithPublicDSAKey();
    return result.boolValue;
}

@end
