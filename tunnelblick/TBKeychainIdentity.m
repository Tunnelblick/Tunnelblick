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

#import "TBKeychainIdentity.h"

#import <CommonCrypto/CommonDigest.h>

#import "helper.h"

typedef enum {
    TBKeychainMatchSubject,
    TBKeychainMatchIssuer,
    TBKeychainMatchThumbprint
} TBKeychainMatchType;

@implementation TBKeychainIdentity

//**************************************************************************************************
// Errors

+(NSString *) messageForOSStatus: (OSStatus) status {

    CFStringRef cfMessage = SecCopyErrorMessageString(status, NULL);
    if (  cfMessage == NULL  ) {
        return [NSString stringWithFormat: @"status = %d", (int)status];
    }

    NSString * message = [NSString stringWithFormat: @"status = %d: '%@'", (int)status, (__bridge NSString *)cfMessage];
    CFRelease(cfMessage);
    return message;
}

+(NSString *) messageForCFError: (CFErrorRef) error {

    if (  error == NULL  ) {
        return @"an unknown error occurred";
    }

    return [(__bridge NSError *)error localizedDescription];
}

//**************************************************************************************************
// Getting strings out of a certificate

+(NSString *) shortNameForOID: (NSString *) oid {

    // Returns the conventional abbreviation for the OID of a distinguished name component, or the
    // OID itself if there is no conventional abbreviation for it.

    static NSDictionary * shortNames = nil;
    if (  shortNames == nil  ) {
        shortNames = [[NSDictionary alloc] initWithObjectsAndKeys:
                      @"CN",           @"2.5.4.3",
                      @"SN",           @"2.5.4.4",
                      @"serialNumber", @"2.5.4.5",
                      @"C",            @"2.5.4.6",
                      @"L",            @"2.5.4.7",
                      @"ST",           @"2.5.4.8",
                      @"STREET",       @"2.5.4.9",
                      @"O",            @"2.5.4.10",
                      @"OU",           @"2.5.4.11",
                      @"T",            @"2.5.4.12",
                      @"GN",           @"2.5.4.42",
                      @"emailAddress", @"1.2.840.113549.1.9.1",
                      @"UID",          @"0.9.2342.19200300.100.1.1",
                      @"DC",           @"0.9.2342.19200300.100.1.25",
                      nil];
    }

    NSString * shortName = [shortNames objectForKey: oid];
    return (  shortName
            ? shortName
            : oid);
}

+(NSString *) distinguishedNameFromCertificate: (SecCertificateRef) certificate
                                        forOID: (CFStringRef)       nameOID {

    // Returns a distinguished name (the subject or the issuer of a certificate) as a string such as
    //      "C=US, O=Example, OU=IT, CN=John Doe"
    // with the components in the order in which they appear in the certificate.
    //
    // Returns nil if the name could not be obtained from the certificate.

    if (  certificate == NULL  ) {
        return nil;
    }

    CFArrayRef keys = CFArrayCreate(NULL, (const void **)&nameOID, 1, &kCFTypeArrayCallBacks);
    if (  keys == NULL  ) {
        return nil;
    }

    CFErrorRef error = NULL;
    CFDictionaryRef values = SecCertificateCopyValues(certificate, keys, &error);
    CFRelease(keys);

    if (  values == NULL  ) {
        if (  error != NULL  ) {
            CFRelease(error);
        }
        return nil;
    }
    if (  error != NULL  ) {
        CFRelease(error);
    }

    NSString * result = nil;

    NSDictionary * nameEntry = [(__bridge NSDictionary *)values objectForKey: (__bridge NSString *)nameOID];
    NSArray * components = [nameEntry objectForKey: (__bridge NSString *)kSecPropertyKeyValue];
    if (  [components isKindOfClass: [NSArray class]]  ) {

        NSMutableArray * parts = [NSMutableArray arrayWithCapacity: [components count]];
        NSUInteger ix;
        for (  ix=0; ix<[components count]; ix++  ) {
            NSDictionary * component = [components objectAtIndex: ix];
            if (  ! [component isKindOfClass: [NSDictionary class]]  ) {
                continue;
            }
            NSString * label = [component objectForKey: (__bridge NSString *)kSecPropertyKeyLabel];
            id         value = [component objectForKey: (__bridge NSString *)kSecPropertyKeyValue];
            if (   [label isKindOfClass: [NSString class]]
                && [value isKindOfClass: [NSString class]]  ) {
                [parts addObject: [NSString stringWithFormat: @"%@=%@", [self shortNameForOID: label], value]];
            }
        }

        if (  [parts count] != 0  ) {
            result = [parts componentsJoinedByString: @", "];
        }
    }

    CFRelease(values);

    return result;
}

+(NSString *) sha1FingerprintOfCertificate: (SecCertificateRef) certificate {

    // Returns the SHA-1 fingerprint of a certificate as a lowercase hexadecimal string without
    // separators, or nil if it could not be calculated.

    if (  certificate == NULL  ) {
        return nil;
    }

    CFDataRef der = SecCertificateCopyData(certificate);
    if (  der == NULL  ) {
        return nil;
    }

    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(CFDataGetBytePtr(der), (CC_LONG)CFDataGetLength(der), digest);
    CFRelease(der);

    NSMutableString * fingerprint = [NSMutableString stringWithCapacity: 2 * CC_SHA1_DIGEST_LENGTH];
    unsigned ix;
    for (  ix=0; ix<CC_SHA1_DIGEST_LENGTH; ix++  ) {
        [fingerprint appendFormat: @"%02x", digest[ix]];
    }

    return [NSString stringWithString: fingerprint];
}

+(BOOL) certificateIsCurrentlyValid: (SecCertificateRef) certificate {

    // Returns YES if 'now' is within the certificate's validity period.
    //
    // Returns YES if the validity period could not be obtained: it is up to OpenVPN and the server
    // to reject a certificate; all this does is avoid using an obviously expired certificate when
    // the Keychain contains both an expired one and a current one that match the selector.

    if (  certificate == NULL  ) {
        return NO;
    }

    const void * keys[] = { kSecOIDX509V1ValidityNotBefore, kSecOIDX509V1ValidityNotAfter };
    CFArrayRef keysArray = CFArrayCreate(NULL, keys, 2, &kCFTypeArrayCallBacks);
    if (  keysArray == NULL  ) {
        return YES;
    }

    CFErrorRef error = NULL;
    CFDictionaryRef values = SecCertificateCopyValues(certificate, keysArray, &error);
    CFRelease(keysArray);

    if (  values == NULL  ) {
        if (  error != NULL  ) {
            CFRelease(error);
        }
        return YES;
    }
    if (  error != NULL  ) {
        CFRelease(error);
    }

    BOOL isValid = YES;

    NSDictionary * dict = (__bridge NSDictionary *)values;
    NSNumber * notBefore = [[dict objectForKey: (__bridge NSString *)kSecOIDX509V1ValidityNotBefore] objectForKey: (__bridge NSString *)kSecPropertyKeyValue];
    NSNumber * notAfter  = [[dict objectForKey: (__bridge NSString *)kSecOIDX509V1ValidityNotAfter ] objectForKey: (__bridge NSString *)kSecPropertyKeyValue];

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();

    if (   [notBefore isKindOfClass: [NSNumber class]]
        && (now < [notBefore doubleValue])  ) {
        isValid = NO;
    }
    if (   [notAfter isKindOfClass: [NSNumber class]]
        && (now > [notAfter doubleValue])  ) {
        isValid = NO;
    }

    CFRelease(values);

    return isValid;
}

+(CFAbsoluteTime) notBeforeOfCertificate: (SecCertificateRef) certificate {

    // Returns the certificate's notBefore as a CFAbsoluteTime, or 0.0 if it could not be obtained.
    // Used only to choose the newest certificate when several of them match the selector.

    if (  certificate == NULL  ) {
        return 0.0;
    }

    const void * keys[] = { kSecOIDX509V1ValidityNotBefore };
    CFArrayRef keysArray = CFArrayCreate(NULL, keys, 1, &kCFTypeArrayCallBacks);
    if (  keysArray == NULL  ) {
        return 0.0;
    }

    CFErrorRef error = NULL;
    CFDictionaryRef values = SecCertificateCopyValues(certificate, keysArray, &error);
    CFRelease(keysArray);

    if (  values == NULL  ) {
        if (  error != NULL  ) {
            CFRelease(error);
        }
        return 0.0;
    }
    if (  error != NULL  ) {
        CFRelease(error);
    }

    CFAbsoluteTime notBefore = 0.0;

    NSDictionary * dict = (__bridge NSDictionary *)values;
    NSNumber * number = [[dict objectForKey: (__bridge NSString *)kSecOIDX509V1ValidityNotBefore] objectForKey: (__bridge NSString *)kSecPropertyKeyValue];
    if (  [number isKindOfClass: [NSNumber class]]  ) {
        notBefore = [number doubleValue];
    }

    CFRelease(values);

    return notBefore;
}

+(NSString *) descriptionForIdentity: (SecIdentityRef) identity {

    if (  identity == NULL  ) {
        return nil;
    }

    SecCertificateRef certificate = NULL;
    OSStatus status = SecIdentityCopyCertificate(identity, &certificate);
    if (   (status != errSecSuccess)
        || (certificate == NULL)  ) {
        return nil;
    }

    NSString * subject     = [self distinguishedNameFromCertificate: certificate forOID: kSecOIDX509V1SubjectName];
    NSString * fingerprint = [self sha1FingerprintOfCertificate: certificate];
    CFRelease(certificate);

    return [NSString stringWithFormat: @"%@; SHA-1 %@",
            (  subject     ? subject     : @"(unknown subject)"),
            (  fingerprint ? fingerprint : @"(unknown fingerprint)")];
}

//**************************************************************************************************
// Finding an identity

+(BOOL) certificate: (SecCertificateRef) certificate
     matchesPattern: (NSString *)        pattern
            forType: (TBKeychainMatchType) matchType {

    switch (  matchType  ) {

        case TBKeychainMatchThumbprint: {
            NSString * fingerprint = [self sha1FingerprintOfCertificate: certificate];
            return (   (fingerprint != nil)
                    && ([fingerprint caseInsensitiveCompare: pattern] == NSOrderedSame));
        }

        case TBKeychainMatchIssuer: {
            NSString * issuer = [self distinguishedNameFromCertificate: certificate forOID: kSecOIDX509V1IssuerName];
            return (   (issuer != nil)
                    && ([issuer rangeOfString: pattern options: NSCaseInsensitiveSearch].length != 0));
        }

        case TBKeychainMatchSubject:
        default: {
            NSString * subject = [self distinguishedNameFromCertificate: certificate forOID: kSecOIDX509V1SubjectName];
            return (   (subject != nil)
                    && ([subject rangeOfString: pattern options: NSCaseInsensitiveSearch].length != 0));
        }
    }
}

+(BOOL) parseSelector: (NSString *)           selector
          intoPattern: (NSString **)          patternPtr
            matchType: (TBKeychainMatchType *) matchTypePtr
         errorMessage: (NSString **)          errMsgPtr {

    NSString * trimmed = [selector stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // OpenVPN strips the quotation marks that surround an option's argument, but strip them here,
    // too, so that a selector that was quoted twice still works.
    if (   ([trimmed length] > 1)
        && [trimmed hasPrefix: @"\""]
        && [trimmed hasSuffix: @"\""]  ) {
        trimmed = [trimmed substringWithRange: NSMakeRange(1, [trimmed length] - 2)];
    }

    if (  [trimmed length] == 0  ) {
        *errMsgPtr = NSLocalizedString(@"The 'management-external-cert' option does not specify which certificate to use.", @"Window text");
        return NO;
    }

    if (  [[trimmed uppercaseString] hasPrefix: @"THUMB:"]  ) {
        *matchTypePtr = TBKeychainMatchThumbprint;
        NSString * thumbprint = [trimmed substringFromIndex: [@"THUMB:" length]];

        // Accept the separators that are used when a fingerprint is displayed by Keychain Access,
        // by OpenSSL, and by Windows' certificate manager.
        thumbprint = [thumbprint stringByReplacingOccurrencesOfString: @" "  withString: @""];
        thumbprint = [thumbprint stringByReplacingOccurrencesOfString: @":"  withString: @""];
        *patternPtr = thumbprint;

    } else if (  [[trimmed uppercaseString] hasPrefix: @"ISSUER:"]  ) {
        *matchTypePtr = TBKeychainMatchIssuer;
        *patternPtr   = [trimmed substringFromIndex: [@"ISSUER:" length]];

    } else if (  [[trimmed uppercaseString] hasPrefix: @"SUBJ:"]  ) {
        *matchTypePtr = TBKeychainMatchSubject;
        *patternPtr   = [trimmed substringFromIndex: [@"SUBJ:" length]];

    } else {
        *matchTypePtr = TBKeychainMatchSubject;
        *patternPtr   = trimmed;
    }

    if (  [*patternPtr length] == 0  ) {
        *errMsgPtr = [NSString stringWithFormat:
                      NSLocalizedString(@"The 'management-external-cert' option's argument ('%@') does not specify which certificate to use.", @"Window text; the '%@' is replaced by an OpenVPN option's argument"),
                      selector];
        return NO;
    }

    return YES;
}

+(SecIdentityRef) copyIdentityMatchingSelector: (NSString *)  selector
                                  errorMessage: (NSString **) errMsgPtr {

    NSString          * pattern   = nil;
    TBKeychainMatchType matchType = TBKeychainMatchSubject;
    if (  ! [self parseSelector: selector intoPattern: &pattern matchType: &matchType errorMessage: errMsgPtr]  ) {
        return NULL;
    }

    NSDictionary * query = [NSDictionary dictionaryWithObjectsAndKeys:
                            (__bridge id)kSecClassIdentity, (__bridge id)kSecClass,
                            (__bridge id)kSecMatchLimitAll, (__bridge id)kSecMatchLimit,
                            (id)kCFBooleanTrue,             (__bridge id)kSecReturnRef,
                            nil];

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

    if (  status == errSecItemNotFound  ) {
        *errMsgPtr = NSLocalizedString(@"There are no certificates with private keys in the Keychain.", @"Window text");
        return NULL;
    }

    if (   (status != errSecSuccess)
        || (result == NULL)  ) {
        *errMsgPtr = [NSString stringWithFormat:
                      NSLocalizedString(@"Could not search the Keychain for certificates (%@).", @"Window text; the '%@' is replaced by a description of an error"),
                      [self messageForOSStatus: status]];
        if (  result != NULL  ) {
            CFRelease(result);
        }
        return NULL;
    }

    NSArray * identities = (__bridge NSArray *)result;

    SecIdentityRef bestIdentity  = NULL;
    CFAbsoluteTime bestNotBefore = 0.0;
    unsigned       matchCount    = 0;
    unsigned       expiredCount  = 0;

    NSUInteger ix;
    for (  ix=0; ix<[identities count]; ix++  ) {

        SecIdentityRef identity = (SecIdentityRef)[identities objectAtIndex: ix];

        SecCertificateRef certificate = NULL;
        if (   (SecIdentityCopyCertificate(identity, &certificate) != errSecSuccess)
            || (certificate == NULL)  ) {
            continue;
        }

        if (  ! [self certificate: certificate matchesPattern: pattern forType: matchType]  ) {
            CFRelease(certificate);
            continue;
        }

        matchCount++;

        if (  ! [self certificateIsCurrentlyValid: certificate]  ) {
            expiredCount++;
            appendLog([NSString stringWithFormat: @"Keychain identity matches '%@' but is not valid at this time, so it is being ignored: %@",
                       selector, [self descriptionForIdentity: identity]]);
            CFRelease(certificate);
            continue;
        }

        appendLog([NSString stringWithFormat: @"Keychain identity matches '%@': %@",
                   selector, [self descriptionForIdentity: identity]]);

        // If more than one identity matches, use the one that was issued most recently
        CFAbsoluteTime notBefore = [self notBeforeOfCertificate: certificate];
        if (   (bestIdentity == NULL)
            || (notBefore > bestNotBefore)  ) {
            if (  bestIdentity != NULL  ) {
                CFRelease(bestIdentity);
            }
            bestIdentity  = (SecIdentityRef)CFRetain(identity);
            bestNotBefore = notBefore;
        }

        CFRelease(certificate);
    }

    CFRelease(result);

    if (  bestIdentity == NULL  ) {
        if (  expiredCount != 0  ) {
            *errMsgPtr = [NSString stringWithFormat:
                          NSLocalizedString(@"The Keychain contains %u certificate(s) that match '%@', but none of them is valid at this time.", @"Window text; the '%u' is replaced by a number and the '%@' is replaced by an OpenVPN option's argument"),
                          expiredCount, selector];
        } else {
            *errMsgPtr = [NSString stringWithFormat:
                          NSLocalizedString(@"The Keychain does not contain a certificate with a private key that matches '%@'.", @"Window text; the '%@' is replaced by an OpenVPN option's argument"),
                          selector];
        }
        return NULL;
    }

    if (  matchCount > 1  ) {
        appendLog([NSString stringWithFormat: @"%u Keychain identities match '%@'; using %@",
                   matchCount, selector, [self descriptionForIdentity: bestIdentity]]);
    }

    return bestIdentity;
}

//**************************************************************************************************
// Using an identity

+(NSString *) pemForIdentity: (SecIdentityRef) identity
                errorMessage: (NSString **)    errMsgPtr {

    if (  identity == NULL  ) {
        *errMsgPtr = NSLocalizedString(@"No Keychain certificate has been selected.", @"Window text");
        return nil;
    }

    SecCertificateRef certificate = NULL;
    OSStatus status = SecIdentityCopyCertificate(identity, &certificate);
    if (   (status != errSecSuccess)
        || (certificate == NULL)  ) {
        *errMsgPtr = [NSString stringWithFormat:
                      NSLocalizedString(@"Could not get the certificate from the Keychain (%@).", @"Window text; the '%@' is replaced by a description of an error"),
                      [self messageForOSStatus: status]];
        return nil;
    }

    CFDataRef der = SecCertificateCopyData(certificate);
    CFRelease(certificate);
    if (  der == NULL  ) {
        *errMsgPtr = NSLocalizedString(@"Could not get the contents of the certificate from the Keychain.", @"Window text");
        return nil;
    }

    NSString * base64 = [(__bridge NSData *)der base64EncodedStringWithOptions: NSDataBase64Encoding64CharacterLineLength];
    CFRelease(der);

    if (  [base64 length] == 0  ) {
        *errMsgPtr = NSLocalizedString(@"Could not encode the certificate from the Keychain.", @"Window text");
        return nil;
    }

    // base64EncodedStringWithOptions inserts CR-LF; OpenVPN wants the PEM as separate lines
    base64 = [base64 stringByReplacingOccurrencesOfString: @"\r\n" withString: @"\n"];

    return [NSString stringWithFormat: @"-----BEGIN CERTIFICATE-----\n%@\n-----END CERTIFICATE-----", base64];
}

+(SecKeyAlgorithm) algorithmFromString: (NSString *)  algorithm
                          errorMessage: (NSString **) errMsgPtr {

    // Translates the algorithm from a '>PK_SIGN:' message into a SecKeyAlgorithm.
    //
    // The algorithms that OpenVPN can ask for are documented in OpenVPN's doc/management-notes.txt.

    // The obsolete '>RSA_SIGN:' message does not include an algorithm and always means PKCS#1 v1.5
    if (  [algorithm length] == 0  ) {
        return kSecKeyAlgorithmRSASignatureDigestPKCS1v15Raw;
    }

    NSArray  * parameters = [algorithm componentsSeparatedByString: @","];
    NSString * padding    = [[parameters objectAtIndex: 0] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];

    if (  [padding isEqualToString: @"RSA_PKCS1_PADDING"]  ) {
        // OpenVPN has already prepended the DigestInfo header, so the digest algorithm is not specified here
        return kSecKeyAlgorithmRSASignatureDigestPKCS1v15Raw;
    }

    if (  [padding isEqualToString: @"RSA_NO_PADDING"]  ) {
        return kSecKeyAlgorithmRSASignatureRaw;
    }

    if (  [padding isEqualToString: @"ECDSA"]  ) {
        // Produces the DER-encoded (r, s) signature that OpenVPN expects
        return kSecKeyAlgorithmECDSASignatureDigestX962;
    }

    if (  [padding isEqualToString: @"RSA_PKCS1_PSS_PADDING"]  ) {

        NSString * hashAlgorithm = nil;
        NSString * saltLength    = nil;

        NSUInteger ix;
        for (  ix=1; ix<[parameters count]; ix++  ) {
            NSString * parameter = [[parameters objectAtIndex: ix] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
            if (  [parameter hasPrefix: @"hashalg="]  ) {
                hashAlgorithm = [[parameter substringFromIndex: [@"hashalg=" length]] uppercaseString];
            } else if (  [parameter hasPrefix: @"saltlen="]  ) {
                saltLength = [parameter substringFromIndex: [@"saltlen=" length]];
            }
        }

        // The Security framework always uses a salt whose length is the length of the digest
        if (   (saltLength != nil)
            && ( ! [saltLength isEqualToString: @"digest"])  ) {
            *errMsgPtr = [NSString stringWithFormat:
                          NSLocalizedString(@"OpenVPN asked for a PSS signature with a salt length of '%@', which macOS cannot create.", @"Window text; the '%@' is replaced by the name of a salt length"),
                          saltLength];
            return NULL;
        }

        if (  [hashAlgorithm isEqualToString: @"SHA256"]  ) {
            return kSecKeyAlgorithmRSASignatureDigestPSSSHA256;
        }
        if (  [hashAlgorithm isEqualToString: @"SHA384"]  ) {
            return kSecKeyAlgorithmRSASignatureDigestPSSSHA384;
        }
        if (  [hashAlgorithm isEqualToString: @"SHA512"]  ) {
            return kSecKeyAlgorithmRSASignatureDigestPSSSHA512;
        }
        if (  [hashAlgorithm isEqualToString: @"SHA224"]  ) {
            return kSecKeyAlgorithmRSASignatureDigestPSSSHA224;
        }
        if (  [hashAlgorithm isEqualToString: @"SHA1"]  ) {
            return kSecKeyAlgorithmRSASignatureDigestPSSSHA1;
        }

        *errMsgPtr = [NSString stringWithFormat:
                      NSLocalizedString(@"OpenVPN asked for a PSS signature using the '%@' hash, which Tunnelblick does not support.", @"Window text; the '%@' is replaced by the name of a hash algorithm"),
                      (  hashAlgorithm ? hashAlgorithm : @"(not specified)")];
        return NULL;
    }

    *errMsgPtr = [NSString stringWithFormat:
                  NSLocalizedString(@"OpenVPN asked for a signature using '%@', which Tunnelblick does not support.", @"Window text; the '%@' is replaced by the name of a signature algorithm"),
                  algorithm];
    return NULL;
}

+(NSData *) signData: (NSData *)       data
        withIdentity: (SecIdentityRef) identity
           algorithm: (NSString *)     algorithm
        errorMessage: (NSString **)    errMsgPtr {

    if (  identity == NULL  ) {
        *errMsgPtr = NSLocalizedString(@"No Keychain certificate has been selected.", @"Window text");
        return nil;
    }

    if (  [data length] == 0  ) {
        *errMsgPtr = NSLocalizedString(@"OpenVPN asked Tunnelblick to sign nothing.", @"Window text");
        return nil;
    }

    SecKeyAlgorithm secAlgorithm = [self algorithmFromString: algorithm errorMessage: errMsgPtr];
    if (  secAlgorithm == NULL  ) {
        return nil;
    }

    SecKeyRef privateKey = NULL;
    OSStatus status = SecIdentityCopyPrivateKey(identity, &privateKey);
    if (   (status != errSecSuccess)
        || (privateKey == NULL)  ) {
        *errMsgPtr = [NSString stringWithFormat:
                      NSLocalizedString(@"Could not get the private key from the Keychain (%@).", @"Window text; the '%@' is replaced by a description of an error"),
                      [self messageForOSStatus: status]];
        return nil;
    }

    if (  ! SecKeyIsAlgorithmSupported(privateKey, kSecKeyOperationTypeSign, secAlgorithm)  ) {
        *errMsgPtr = [NSString stringWithFormat:
                      NSLocalizedString(@"The private key in the Keychain cannot create the '%@' signature that OpenVPN asked for.", @"Window text; the '%@' is replaced by the name of a signature algorithm"),
                      (  [algorithm length] == 0  ? @"RSA_PKCS1_PADDING" : algorithm)];
        CFRelease(privateKey);
        return nil;
    }

    CFErrorRef error = NULL;
    CFDataRef signature = SecKeyCreateSignature(privateKey, secAlgorithm, (__bridge CFDataRef)data, &error);
    CFRelease(privateKey);

    if (  signature == NULL  ) {
        *errMsgPtr = [NSString stringWithFormat:
                      NSLocalizedString(@"Could not sign data with the private key in the Keychain (%@).", @"Window text; the '%@' is replaced by a description of an error"),
                      [self messageForCFError: error]];
        if (  error != NULL  ) {
            CFRelease(error);
        }
        return nil;
    }

    if (  error != NULL  ) {
        CFRelease(error);
    }

    NSData * result = [[(__bridge NSData *)signature copy] autorelease];
    CFRelease(signature);

    return result;
}

@end
