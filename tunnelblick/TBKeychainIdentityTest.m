/*
 * Copyright 2026 Andrew Grishenko. All rights reserved.
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

// A command line program that exercises TBKeychainIdentity against the Keychain of the user that runs it,
// so that the selection of a certificate and the creation of signatures can be tested without connecting
// to a VPN. It is not part of the Tunnelblick application; build and run it with:
//
//      cd tunnelblick
//      clang -fno-objc-arc -mmacosx-version-min=13.0 -framework Foundation -framework Security \
//            -o /tmp/tbkeychainidentitytest TBKeychainIdentity.m TBKeychainIdentityTest.m
//      /tmp/tbkeychainidentitytest 'SUBJ:CN=someone'
//
// For each signature algorithm that OpenVPN can ask for, the program creates a signature and verifies it
// with the certificate's public key.

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>

#import "TBKeychainIdentity.h"

// TBKeychainIdentity logs via appendLog(), which is part of the Tunnelblick application
void appendLog(NSString * msg) {
    fprintf(stderr, "    log: %s\n", [msg UTF8String]);
}

static BOOL anythingFailed = NO;

static void report(NSString * name, BOOL ok, NSString * detail) {

    fprintf(stdout, "%s %-46s %s\n",
            (ok ? "ok  " : "FAIL"),
            [name UTF8String],
            [(detail ? detail : @"") UTF8String]);
    if (  ! ok  ) {
        anythingFailed = YES;
    }
}

static NSData * sha256OfString(NSString * string) {

    NSData * data = [string dataUsingEncoding: NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([data bytes], (CC_LONG)[data length], digest);
    return [NSData dataWithBytes: digest length: sizeof(digest)];
}

static NSData * digestInfoForSha256(NSData * digest) {

    // The DigestInfo header for SHA-256 that OpenVPN prepends before asking for a PKCS#1 v1.5 signature
    static const unsigned char prefix[] = {
        0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01,
        0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20
    };

    NSMutableData * digestInfo = [NSMutableData dataWithBytes: prefix length: sizeof(prefix)];
    [digestInfo appendData: digest];
    return digestInfo;
}

static SecKeyRef copyPublicKeyOfIdentity(SecIdentityRef identity) {

    SecCertificateRef certificate = NULL;
    if (   (SecIdentityCopyCertificate(identity, &certificate) != errSecSuccess)
        || (certificate == NULL)  ) {
        return NULL;
    }

    SecKeyRef publicKey = SecCertificateCopyKey(certificate);
    CFRelease(certificate);
    return publicKey;
}

static void testAlgorithm(SecIdentityRef  identity,
                          SecKeyRef       publicKey,
                          NSString *      algorithm,
                          NSData *        dataToSign,
                          SecKeyAlgorithm verifyAlgorithm) {

    NSString * errMsg = nil;
    NSData * signature = [TBKeychainIdentity signData: dataToSign
                                        withIdentity: identity
                                           algorithm: algorithm
                                        errorMessage: &errMsg];
    if (  signature == nil  ) {
        report(algorithm, NO, errMsg);
        return;
    }

    if (  verifyAlgorithm == NULL  ) {
        report(algorithm, YES, [NSString stringWithFormat: @"%lu-byte signature (not verified)", (unsigned long)[signature length]]);
        return;
    }

    CFErrorRef error = NULL;
    BOOL verified = SecKeyVerifySignature(publicKey,
                                          verifyAlgorithm,
                                          (__bridge CFDataRef)dataToSign,
                                          (__bridge CFDataRef)signature,
                                          &error);
    NSString * detail = (  verified
                         ? [NSString stringWithFormat: @"%lu-byte signature verified", (unsigned long)[signature length]]
                         : [(__bridge NSError *)error localizedDescription]);
    if (  error != NULL  ) {
        CFRelease(error);
    }

    report(algorithm, verified, detail);
}

static int listAllIdentities(void) {

    // Lists every identity in the Keychain without using any private key, so it does not ask the user for
    // permission to use a key.

    NSDictionary * query = [NSDictionary dictionaryWithObjectsAndKeys:
                            (__bridge id)kSecClassIdentity, (__bridge id)kSecClass,
                            (__bridge id)kSecMatchLimitAll, (__bridge id)kSecMatchLimit,
                            (id)kCFBooleanTrue,             (__bridge id)kSecReturnRef,
                            nil];

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (  status == errSecItemNotFound  ) {
        fprintf(stdout, "There are no identities (certificates with private keys) in the Keychain.\n");
        return 0;
    }
    if (   (status != errSecSuccess)
        || (result == NULL)  ) {
        fprintf(stderr, "Could not search the Keychain: status = %d\n", (int)status);
        return 1;
    }

    NSArray * identities = (__bridge NSArray *)result;
    fprintf(stdout, "%lu identities in the Keychain:\n", (unsigned long)[identities count]);
    NSUInteger ix;
    for (  ix=0; ix<[identities count]; ix++  ) {
        SecIdentityRef identity = (SecIdentityRef)[identities objectAtIndex: ix];
        NSString * description = [TBKeychainIdentity descriptionForIdentity: identity];
        fprintf(stdout, "    %s\n", [(description ? description : @"(could not be described)") UTF8String]);
    }
    CFRelease(result);

    return 0;
}

int main(int argc, const char * argv[]) {

    @autoreleasepool {

        if (  argc == 1  ) {
            return listAllIdentities();
        }

        if (   (argc < 2)
            || (argc > 3)
            || (   (argc == 3)
                && (strcmp(argv[2], "--no-sign") != 0))  ) {
            fprintf(stderr, "Usage: %s [<selector> [--no-sign]]\n"
                            "   with no arguments, lists all identities in the Keychain\n"
                            "   for example: %s 'SUBJ:CN=someone'\n"
                            "                %s 'THUMB:a1b2c3...'\n"
                            "                %s 'ISSUER:Example CA'\n"
                            "   '--no-sign' stops after getting the certificate, so no private key is used\n",
                    argv[0], argv[0], argv[0], argv[0]);
            return 2;
        }

        BOOL signingIsWanted = (argc == 2);

        NSString * selector = [NSString stringWithUTF8String: argv[1]];

        NSString * errMsg = nil;
        SecIdentityRef identity = [TBKeychainIdentity copyIdentityMatchingSelector: selector errorMessage: &errMsg];
        if (  identity == NULL  ) {
            report(@"find identity", NO, errMsg);
            return 1;
        }
        report(@"find identity", YES, [TBKeychainIdentity descriptionForIdentity: identity]);

        NSString * pem = [TBKeychainIdentity pemForIdentity: identity errorMessage: &errMsg];
        BOOL pemIsOK = (   (pem != nil)
                        && [pem hasPrefix: @"-----BEGIN CERTIFICATE-----\n"]
                        && [pem hasSuffix: @"\n-----END CERTIFICATE-----"]
                        && ([pem rangeOfString: @"\r"].length == 0));
        NSString * pemDetail = (  pemIsOK
                                ? [NSString stringWithFormat: @"%lu characters", (unsigned long)[pem length]]
                                : errMsg);

        if (  pemIsOK  ) {

            // Parse the PEM back into a certificate, the way OpenVPN will, and make sure it is the same
            // certificate that we started with
            NSString * body = [pem substringWithRange: NSMakeRange([@"-----BEGIN CERTIFICATE-----\n" length],
                                                                   [pem length] - [@"-----BEGIN CERTIFICATE-----\n" length] - [@"\n-----END CERTIFICATE-----" length])];
            NSData * der = [[[NSData alloc] initWithBase64EncodedString: body
                                                               options: NSDataBase64DecodingIgnoreUnknownCharacters] autorelease];
            SecCertificateRef parsed = (  der
                                        ? SecCertificateCreateWithData(NULL, (__bridge CFDataRef)der)
                                        : NULL);
            if (  parsed == NULL  ) {
                pemIsOK = NO;
                pemDetail = @"the PEM could not be parsed back into a certificate";
            } else {
                CFStringRef summaryCF = SecCertificateCopySubjectSummary(parsed);
                NSString * parsedSummary = (  summaryCF
                                            ? [[(__bridge NSString *)summaryCF copy] autorelease]
                                            : @"(no subject summary)");
                if (  summaryCF != NULL  ) {
                    CFRelease(summaryCF);
                }
                CFRelease(parsed);
                pemDetail = [NSString stringWithFormat: @"%@, parses back to '%@'", pemDetail, parsedSummary];
            }
        }

        report(@"certificate as PEM", pemIsOK, pemDetail);

        // Algorithms that OpenVPN will not ask for must be rejected instead of creating a wrong signature.
        // These are checked before the private key is used, so they do not ask the user for permission.
        NSData * digest = sha256OfString(@"Tunnelblick TBKeychainIdentity test data");

        errMsg = nil;
        NSData * signature = [TBKeychainIdentity signData: digest
                                             withIdentity: identity
                                                algorithm: @"RSA_PKCS1_PSS_PADDING,hashalg=SHA256,saltlen=max"
                                             errorMessage: &errMsg];
        report(@"reject saltlen=max", (signature == nil), errMsg);

        errMsg = nil;
        signature = [TBKeychainIdentity signData: digest
                                    withIdentity: identity
                                       algorithm: @"NO_SUCH_PADDING"
                                    errorMessage: &errMsg];
        report(@"reject unknown algorithm", (signature == nil), errMsg);

        if (  ! signingIsWanted  ) {
            CFRelease(identity);
            return (anythingFailed ? 1 : 0);
        }

        SecKeyRef publicKey = copyPublicKeyOfIdentity(identity);
        if (  publicKey == NULL  ) {
            report(@"get public key", NO, @"could not get the public key from the certificate");
            CFRelease(identity);
            return 1;
        }

        if (  SecKeyIsAlgorithmSupported(publicKey, kSecKeyOperationTypeVerify, kSecKeyAlgorithmECDSASignatureDigestX962)  ) {

            testAlgorithm(identity, publicKey, @"ECDSA", digest, kSecKeyAlgorithmECDSASignatureDigestX962);

        } else {

            testAlgorithm(identity, publicKey, @"RSA_PKCS1_PADDING", digestInfoForSha256(digest),
                          kSecKeyAlgorithmRSASignatureDigestPKCS1v15Raw);

            testAlgorithm(identity, publicKey, @"RSA_PKCS1_PSS_PADDING,hashalg=SHA256,saltlen=digest", digest,
                          kSecKeyAlgorithmRSASignatureDigestPSSSHA256);

            // OpenVPN pads the data itself for RSA_NO_PADDING, so the input is as long as the key and the
            // result cannot be verified with a padding-aware algorithm
            NSUInteger keySizeInBytes = SecKeyGetBlockSize(publicKey);
            NSMutableData * rawData = [NSMutableData dataWithLength: keySizeInBytes];
            [rawData replaceBytesInRange: NSMakeRange(keySizeInBytes - [digest length], [digest length])
                               withBytes: [digest bytes]];
            testAlgorithm(identity, publicKey, @"RSA_NO_PADDING", rawData, NULL);
        }

        CFRelease(publicKey);
        CFRelease(identity);
    }

    return (anythingFailed ? 1 : 0);
}
