/*
 * TBTotpGenerator — RFC 6238 TOTP generator implementation
 */

#import "TBTotpGenerator.h"
#import <CommonCrypto/CommonHMAC.h>
#include <math.h>

@implementation TBTotpGenerator

+ (NSString *) parseOtpauthURI: (NSString *) uri
{
    if (  [uri length] == 0  ) {
        return nil;
    }

    NSString * trimmed = [uri stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSURL * url = [NSURL URLWithString: trimmed];
    if (  ! url  ) {
        return nil;
    }

    NSString * scheme = [[url scheme] lowercaseString];
    if (   ( ! [scheme isEqualToString: @"otpauth"] )
        && ( ! [scheme isEqualToString: @"otpauth:"] )  ) {
        if (  ! [trimmed hasPrefix: @"otpauth://"]  ) {
            return nil;
        }
        url = [NSURL URLWithString: trimmed];
        if (  ! url  ) {
            return nil;
        }
    }

    NSString * host = [[url host] lowercaseString];
    if (   ( ! [host isEqualToString: @"totp"] )
        && ( ! [host isEqualToString: @"hotp"] )  ) {
        return nil;
    }

    NSURLComponents * components = [NSURLComponents componentsWithURL: url resolvingAgainstBaseURL: NO];
    for ( NSURLQueryItem * item in [components queryItems]  ) {
        if (  [[item name] caseInsensitiveCompare: @"secret"] == NSOrderedSame  ) {
            NSString * secret = [item value];
            if (  [self isValidBase32Secret: secret]  ) {
                return [[secret uppercaseString] stringByReplacingOccurrencesOfString: @" " withString: @""];
            }
            return nil;
        }
    }

    return nil;
}

+ (BOOL) isValidBase32Secret: (NSString *) secret
{
    if (  [secret length] == 0  ) {
        return NO;
    }

    NSCharacterSet * allowed = [NSCharacterSet characterSetWithCharactersInString: @"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567= "];
    NSCharacterSet * upper = [NSCharacterSet uppercaseLetterCharacterSet];
    NSString * upperSecret = [secret uppercaseString];

    for (  NSUInteger i = 0; i < [upperSecret length]; i++  ) {
        unichar c = [upperSecret characterAtIndex: i];
        if (  ! [allowed characterIsMember: c]  ) {
            return NO;
        }
        (void) upper;
    }

    return YES;
}

+ (NSData *) decodeBase32Secret: (NSString *) base32Secret
{
    if (  ! [self isValidBase32Secret: base32Secret]  ) {
        return nil;
    }

    static char decodeTable[256];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        memset(decodeTable, 0xFF, sizeof(decodeTable));
        const char * alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
        for (  int i = 0; alphabet[i] != '\0'; i++  ) {
            decodeTable[(unsigned char) alphabet[i]] = (char) i;
        }
    });

    NSString * cleaned = [[[base32Secret uppercaseString]
                            stringByReplacingOccurrencesOfString: @" " withString: @""]
                           stringByReplacingOccurrencesOfString: @"=" withString: @""];

    const char * chars = [cleaned UTF8String];
    if (  ! chars  ) {
        return nil;
    }

    size_t inputLen = strlen(chars);
    size_t outputLen = (inputLen * 5) / 8;
    NSMutableData * output = [NSMutableData dataWithLength: outputLen];
    if (  outputLen == 0  ) {
        return nil;
    }

    unsigned char * bytes = [output mutableBytes];
    unsigned int buffer = 0;
    int bitsLeft = 0;
    size_t outIndex = 0;

    for (  size_t i = 0; i < inputLen; i++  ) {
        unsigned char value = decodeTable[(unsigned char) chars[i]];
        if (  value == 0xFF  ) {
            return nil;
        }
        buffer = (buffer << 5) | value;
        bitsLeft += 5;
        if (  bitsLeft >= 8  ) {
            bytes[outIndex++] = (unsigned char) ((buffer >> (bitsLeft - 8)) & 0xFF);
            bitsLeft -= 8;
        }
    }

    [output setLength: outIndex];
    return output;
}

+ (NSString *) generateCodeWithSecret: (NSString *) base32Secret
{
    return [self generateCodeWithSecret: base32Secret digits: 6 period: 30];
}

+ (NSString *) generateCodeWithSecret: (NSString *) base32Secret
                               digits: (NSUInteger) digits
                               period: (NSUInteger) period
{
    return [self generateCodeWithSecret: base32Secret digits: digits period: period
                                atTime: [[NSDate date] timeIntervalSince1970]];
}

+ (NSString *) generateCodeWithSecret: (NSString *) base32Secret
                              digits: (NSUInteger) digits
                              period: (NSUInteger) period
                              atTime: (NSTimeInterval) timestamp
{
    NSData * keyData = [self decodeBase32Secret: base32Secret];
    if (  ! keyData  ) {
        return nil;
    }

    if (  digits == 0  ) {
        digits = 6;
    }
    if (  period == 0  ) {
        period = 30;
    }
    if (  digits > 8 || !isfinite(timestamp) || timestamp < 0 || timestamp >= (double)UINT64_MAX  ) {
        return nil;
    }

    uint64_t counter = (uint64_t) (timestamp / (NSTimeInterval) period);
    uint8_t counterBytes[8];
    for (  int i = 7; i >= 0; i--  ) {
        counterBytes[i] = (uint8_t) (counter & 0xFF);
        counter >>= 8;
    }

    unsigned char hmac[CC_SHA1_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA1, [keyData bytes], [keyData length], counterBytes, 8, hmac);

    unsigned int offset = hmac[CC_SHA1_DIGEST_LENGTH - 1] & 0x0F;
    unsigned int binaryCode = ((hmac[offset] & 0x7F) << 24)
                            | ((hmac[offset + 1] & 0xFF) << 16)
                            | ((hmac[offset + 2] & 0xFF) << 8)
                            | (hmac[offset + 3] & 0xFF);

    unsigned int modulo = 1;
    for (  NSUInteger i = 0; i < digits; i++  ) {
        modulo *= 10;
    }

    unsigned int otp = binaryCode % modulo;
    return [NSString stringWithFormat: @"%0*lu", (int)digits, (unsigned long)otp];
}

@end
