/*
 * TBTotpGenerator — RFC 6238 TOTP generator
 * Generates Google Authenticator-compatible six-digit codes from a Base32 secret.
 */

#import <Foundation/Foundation.h>

@interface TBTotpGenerator : NSObject

// Extract the Base32 secret from an otpauth URI; return nil if it is invalid.
+ (NSString *) parseOtpauthURI: (NSString *) uri;

// Decode a Base32 secret into NSData.
+ (NSData *) decodeBase32Secret: (NSString *) base32Secret;

// Generate a TOTP code; zero digits or period select six digits or 30 seconds.
+ (NSString *) generateCodeWithSecret: (NSString *) base32Secret
                               digits: (NSUInteger) digits
                               period: (NSUInteger) period;

+ (NSString *) generateCodeWithSecret: (NSString *) base32Secret
                              digits: (NSUInteger) digits
                              period: (NSUInteger) period
                              atTime: (NSTimeInterval) timestamp;

// Convenience method for six digits and a 30-second period.
+ (NSString *) generateCodeWithSecret: (NSString *) base32Secret;

// Validate the Base32 character set, allowing spaces and ignoring case.
+ (BOOL) isValidBase32Secret: (NSString *) secret;

@end
