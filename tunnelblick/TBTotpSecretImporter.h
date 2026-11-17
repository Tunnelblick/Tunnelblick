/*
 * TBTotpSecretImporter — import a TOTP provisioning secret from text or a QR image.
 */

#import <Foundation/Foundation.h>

@interface TBTotpSecretImporter : NSObject

// Extract a secret from a pasted otpauth URI or a plain Base32 string.
+ (NSString *) secretFromPastedString: (NSString *) pastedString
                                error: (NSString **) errorOut;

// Read a provisioning payload from a QR image file.
+ (NSString *) secretFromQRImageAtPath: (NSString *) imagePath
                                 error: (NSString **) errorOut;

@end
