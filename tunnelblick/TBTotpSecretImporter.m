/*
 * TBTotpSecretImporter — import TOTP provisioning secrets.
 */

#import "TBTotpSecretImporter.h"
#import "TBTotpGenerator.h"
#import <Vision/Vision.h>
#import <AppKit/AppKit.h>

@implementation TBTotpSecretImporter

+ (NSString *) secretFromPastedString: (NSString *) pastedString
                                error: (NSString **) errorOut
{
    if (  errorOut  ) {
        *errorOut = nil;
    }

    if (  [pastedString length] == 0  ) {
        if (  errorOut  ) {
            *errorOut = NSLocalizedString(@"The TOTP secret is empty.", @"Window text");
        }
        return nil;
    }

    NSString * trimmed = [pastedString stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (  [trimmed hasPrefix: @"otpauth://"]  ) {
        NSString * secret = [TBTotpGenerator parseOtpauthURI: trimmed];
        if (  secret  ) {
            return secret;
        }
        if (  errorOut  ) {
            *errorOut = NSLocalizedString(@"The otpauth URI is invalid or does not contain a valid secret.", @"Window text");
        }
        return nil;
    }

    NSString * normalized = [[trimmed uppercaseString] stringByReplacingOccurrencesOfString: @" " withString: @""];
    if (  [TBTotpGenerator isValidBase32Secret: normalized]  ) {
        NSData * decoded = [TBTotpGenerator decodeBase32Secret: normalized];
        if (  decoded  ) {
            return normalized;
        }
    }

    if (  errorOut  ) {
        *errorOut = NSLocalizedString(@"The pasted text is not a valid otpauth URI or Base32 secret.", @"Window text");
    }
    return nil;
}

+ (NSString *) secretFromQRImageAtPath: (NSString *) imagePath
                                 error: (NSString **) errorOut
{
    if (  errorOut  ) {
        *errorOut = nil;
    }

    if (  [imagePath length] == 0  ) {
        if (  errorOut  ) {
            *errorOut = NSLocalizedString(@"No image file was selected.", @"Window text");
        }
        return nil;
    }

    NSURL * fileURL = [NSURL fileURLWithPath: imagePath];
    NSImage * image = [[NSImage alloc] initWithContentsOfURL: fileURL];
    if (  ! image  ) {
        if (  errorOut  ) {
            *errorOut = NSLocalizedString(@"Could not read the selected image file.", @"Window text");
        }
        return nil;
    }

    CGImageRef cgImage = [image CGImageForProposedRect: NULL context: nil hints: nil];
    [image release];
    if (  ! cgImage  ) {
        if (  errorOut  ) {
            *errorOut = NSLocalizedString(@"Could not convert the image for QR decoding.", @"Window text");
        }
        return nil;
    }

    __block NSString * payload = nil;
    __block NSString * decodeError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    VNDetectBarcodesRequest * request = [[VNDetectBarcodesRequest alloc] initWithCompletionHandler:
        ^(VNRequest * req, NSError * err) {
            if (  err  ) {
                decodeError = [[err localizedDescription] copy];
                dispatch_semaphore_signal(sem);
                return;
            }
            for ( VNBarcodeObservation * obs in [req results]  ) {
                if (  [[obs payloadStringValue] length] != 0  ) {
                    payload = [[obs payloadStringValue] copy];
                    break;
                }
            }
            dispatch_semaphore_signal(sem);
        }];

    if (@available(macOS 11.0, *)) {
        request.symbologies = @[VNBarcodeSymbologyQR];
    }

    VNImageRequestHandler * handler = [[VNImageRequestHandler alloc] initWithCGImage: cgImage options: @{}];
    NSError * handlerError = nil;
    BOOL ok = [handler performRequests: @[request] error: &handlerError];
    [request release];
    [handler release];

    if (  ! ok  ) {
        if (  errorOut  ) {
            if (  handlerError  ) {
                *errorOut = [handlerError localizedDescription];
            } else {
                *errorOut = NSLocalizedString(@"QR code detection failed.", @"Window text");
            }
        }
        return nil;
    }

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    dispatch_release(sem);

    if (  decodeError  ) {
        if (  errorOut  ) {
            *errorOut = decodeError;
        }
        [decodeError release];
        return nil;
    }

    if (  [payload length] == 0  ) {
        if (  errorOut  ) {
            *errorOut = NSLocalizedString(@"No QR code was found in the image.", @"Window text");
        }
        return nil;
    }

    NSString * secret = [self secretFromPastedString: payload error: errorOut];
    [payload release];
    return secret;
}

@end
