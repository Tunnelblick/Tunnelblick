
/*=====================================================================
 *
 *  Copyright 2025 Jonathan K. Bullard. All rights reserved.
 *
 *  This file is part of Tunnelblick.
 *
 *  Tunnelblick is free software:  you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  Tunnelblick is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution) ; if not, see http: //www.gnu.org/licenses/.
 *
 *===================================================================*/

// NOTE: THIS CLASS CAN BE DEBUGGED USING THE Debug_update_signing_util Xcode project.

#import <Foundation/Foundation.h>
#import <Security/Security.h>

#import "UpdateSigning.h"
#import "defines.h"

@implementation UpdateSigning

#pragma mark - Helper Methods

+(NSData *) fileContentsFromPath: (NSString * _Nonnull)              path
                 errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr {

    //--------------------------------------------------------------
    // Return the contents of a file as an NSData object
    // -------------------------------------------------------------

    NSError * err = nil;
    NSData * data = [NSData dataWithContentsOfFile:path options:0 error: &err];
    if (  ! data  ) {
        [self logErrorMessage: [NSString stringWithFormat: @"Error: reading '%@'; error was '%@'", path, err]
              toNSLogOrString: errorMessagePtr];
    }
    return data;
}

+(NSString *) stringWithBase64UrlEncodingOfData: (NSData *) data {

    //-----------------------------------------------------------------------------------
    // Returns a string with data encoded using base64 URL encoding.
    // (Base 64 URL encoding is base 64 with "-" instead of "+" and "_" instead of "/".)
    //
    // This encoding is used instead of standard base 64 encoding to avoid having the
    // strings include the slash character because most shells replace "//" with "/".
    // ----------------------------------------------------------------------------------

    NSString * base64 = [data base64EncodedStringWithOptions: 0];
    NSString * base64URL = [[base64
                             stringByReplacingOccurrencesOfString: @"/" withString: @"_"]
                            stringByReplacingOccurrencesOfString: @"+" withString: @"-"];
    return base64URL;
}

+(NSData *) dataFromBase64UrlEncodedString: (NSString *) string {

    //-----------------------------------------------------------------------------------
    // Returns a data object from decoding a base-64-URL-encoded string.
    // (Base 64 URL encoding is base 64 with "-" instead of "+" and "_" instead of "/".)
    //
    // This encoding is used instead of standard base 64 encoding to avoid having the
    // strings include the slash character because most shells replace "//" with "/".
    // ----------------------------------------------------------------------------------

    NSString * base64 = [[string
                          stringByReplacingOccurrencesOfString: @"_" withString: @"/"]
                         stringByReplacingOccurrencesOfString: @"-" withString: @"+"];
    NSData * data = [[[NSData alloc] initWithBase64EncodedString: base64 options: 0] autorelease];
    return data;
}

+(void) logErrorMessage: (NSString * _Nonnull) message
        toNSLogOrString: (NSString * _Nullable * _Nullable) string {

    //-------------------------------------------------------------------
    // Logs a string to "string" if it is non-null, othewise to NSLog().
    // ------------------------------------------------------------------
    if (  string  ) {
        *string = message;
    } else {
        NSLog(@"%@", message);
    }
}

+(SecKeyRef) createPublicSecKeyFromData: (CFDataRef) keyData
                        errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr {

    //------------------------------------------------------------------------------------
    // Creates a SecKeyRef for a public key whose raw bytes are stored in `keyData`.
    // - Parameter keyData: The CFData/NSData containing the DER‑encoded public key.
    // - Returns: A SecKeyRef on success, or NULL on failure. Errors are logged.
    //------------------------------------------------------------------------------------

    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType       : (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass      : (__bridge id)kSecAttrKeyClassPublic,
        (__bridge id)kSecAttrKeySizeInBits : @(2048)
    };

    //
    // SecKeyCreateWithData validates the data format (DER‑encoded SubjectPublicKeyInfo
    // for RSA/EC keys). If the data is just the raw modulus/exponent it must be
    // wrapped first.
    //
    CFErrorRef error = NULL;

    SecKeyRef secKey = SecKeyCreateWithData(keyData,
                                            (__bridge CFDictionaryRef)attributes,
                                            &error);
    if (  ! secKey ) {
        [self logErrorMessage: [NSString stringWithFormat: @"Error: could not create public key from data: %@", (__bridge NSError *)error]
              toNSLogOrString: errorMessagePtr];
        CFReleaseIfNotNULL(error);
        return NULL;
    }

    CFReleaseIfNotNULL(error);
    return secKey;
}

+(BOOL) setPublicKey: (SecKeyRef *) publicKeyPtr
      fromPrivateKey: (SecKeyRef)   privateKey
     errorMessagePtr: (NSString **) errorMessagePtr {

    //--------------------------------------------------------------
    // Pull the public key out of the private‑key reference
    //--------------------------------------------------------------

    if (   privateKey == NULL  ) {
        [self logErrorMessage: @"Error: private key is has not been made available"
              toNSLogOrString: errorMessagePtr];
        return NO;
    }

    *publicKeyPtr = SecKeyCopyPublicKey(privateKey);
    if (  *publicKeyPtr == NULL  ) {
        [self logErrorMessage: @"Error: Failed to obtain public key from private key"
              toNSLogOrString: errorMessagePtr];
        return NO;
    }

    return YES;
}

+(BOOL) generateKeyPairWithKeychainItemLabel: (NSString * _Nonnull)              itemLabel
                             errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr {

    //-----------------------------------------------------------
    // Generate a brand‑new key pair and store the private key in the keychain
    //-----------------------------------------------------------

    SecKeyRef privateKey = NULL;

    if (  ! [self setPrivateKeyRefPtr: &privateKey
            fromKeychainItemWithLabel: itemLabel
                     okIfDoesNotExist: YES
                      errorMessagePtr: errorMessagePtr]  ) {
        return NO;
    }
    if (  privateKey != NULL  ) {
        CFRelease(privateKey);
        [self logErrorMessage: [NSString stringWithFormat: @"Error: Keychain item named '%@' already exists", itemLabel]
              toNSLogOrString: errorMessagePtr];
        return NO;
    }

    /* Generate a key pair, storing the private key in the Keychain */
    NSData * itemLabelData = [itemLabel dataUsingEncoding: NSUTF8StringEncoding];
    NSDictionary * attributes = @{
        (__bridge NSString *) kSecAttrKeyType       : (__bridge NSString *) kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge NSString *) kSecAttrAccessible    : (__bridge NSString *) kSecAttrAccessibleWhenUnlocked,
        (__bridge NSString *) kSecAttrKeySizeInBits : @256,
        (__bridge NSString *) kSecAttrLabel         : itemLabel,
        (__bridge NSString *)kSecPrivateKeyAttrs    : @{ (__bridge NSString *)kSecAttrIsPermanent:    @YES,
                                                         (__bridge NSString *)kSecAttrApplicationTag: itemLabelData,
        },
    };

    CFErrorRef cfErr = NULL;
    privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &cfErr);
    if (  privateKey == NULL  ) {
        [self logErrorMessage: [NSString stringWithFormat: @"Error: Could not create key pair; error was %@", (__bridge NSError *) cfErr]
              toNSLogOrString: errorMessagePtr];
        CFReleaseIfNotNULL(cfErr);
        return NO;
    }

    CFReleaseIfNotNULL(cfErr);
    CFRelease(privateKey);

    return YES;
}

+(BOOL) setPrivateKeyRefPtr: (SecKeyRef _Nonnull * _Nonnull)    keyPtr
  fromKeychainItemWithLabel: (NSString * _Nonnull)              itemLabel
           okIfDoesNotExist: (BOOL)                             okIfDoesNotExist
            errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr {

    if (   (keyPtr == NULL)
        || ( ! itemLabel)  ) {
        [self logErrorMessage: [NSString stringWithFormat:
                                @"Internal Error: NULL argument to setPrivateKeyRefPtr: (%p) fromKeychainItemWithLabel '%@'",
                                (void *)keyPtr, itemLabel]
              toNSLogOrString: errorMessagePtr];
        return NO;
    }

    NSDictionary *query = @{
        (__bridge NSString *) kSecClass           : (__bridge NSString *) kSecClassKey,
        (__bridge NSString *) kSecMatchLimit      : (__bridge NSString *) kSecMatchLimitOne,
        (__bridge NSString *) kSecAttrLabel       : itemLabel,
        (__bridge NSString *) kSecAttrIsPermanent : @YES,
        (__bridge NSString *) kSecReturnRef       : @YES,
        (__bridge NSString *) kSecAttrCanSign     : @YES,
    };

    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query,
                                          (CFTypeRef *)keyPtr);

    if (   status == errSecSuccess
        && *keyPtr != NULL  ) {
        return YES;
    }

    if (  status == errSecItemNotFound  ) {
        if (  okIfDoesNotExist  ) {
            return YES;
        }
        [self logErrorMessage: [NSString stringWithFormat: @"Error: no keychain item named \"%@\" was found", itemLabel]
              toNSLogOrString: errorMessagePtr];
    } else {
        [self logErrorMessage: @"Error: Unexpected keychain lookup failure"
              toNSLogOrString: errorMessagePtr];
    }

    return NO;
}

+(BOOL) deletePrivateKeyFromKeychainWithLabel: (NSString * _Nonnull) itemLabel
                              errorMessagePtr: (NSString **)         errorMessagePtr {

    NSDictionary * query = @{
        (__bridge NSString *) kSecClass           : (__bridge NSString *) kSecClassKey,
        (__bridge NSString *) kSecMatchLimit      : (__bridge NSString *) kSecMatchLimitOne,
        (__bridge NSString *) kSecAttrLabel       : itemLabel,
    };

    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);

    if (  status == errSecSuccess  ) {
        return YES;
    }

    [self logErrorMessage: [NSString stringWithFormat: @"Error: Deletion of private key named '%@' failed.",  itemLabel]
          toNSLogOrString: errorMessagePtr];
    return NO;
}

+(BOOL) setBase64URLEncodedStringOfPublicKeyPtr: (NSString * _Nonnull * _Nonnull)  base64URLEncodedStringOfPublicKeyPtr
                              keychainItemLabel: (NSString * _Nonnull           )  itemLabel
                                errorMessagePtr: (NSString * _Nullable * _Nonnull) errorMessagePtr {

    //-----------------------------------------------------------------------------------------------------
    // Get the public key from the public/private key pair from the Keychain
    //-----------------------------------------------------------------------------------------------------

    SecKeyRef privateKey = NULL;
    SecKeyRef publicKey  = NULL;

    if (  ! [self setPrivateKeyRefPtr: &privateKey
            fromKeychainItemWithLabel: itemLabel
                     okIfDoesNotExist: NO
                      errorMessagePtr: errorMessagePtr]  ) {
        return NO;
    }

    if (  ! [self setPublicKey: &publicKey
                fromPrivateKey: privateKey
               errorMessagePtr: errorMessagePtr]  ) {
        CFReleaseIfNotNULL(privateKey);
        return NO;
    }

    CFReleaseIfNotNULL(privateKey);

    CFErrorRef cfErr = NULL;

    CFDataRef publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &cfErr);

    CFRelease(publicKey);

    if (   (! publicKeyData)
        || (cfErr != NULL)  ) {
        NSError * err = (__bridge NSError *)cfErr;
        [self logErrorMessage: [NSString stringWithFormat: @"Error: extracting public key; error was '%@'", (__bridge NSError *)err]
              toNSLogOrString: errorMessagePtr];
        CFReleaseIfNotNULL(cfErr);
        CFReleaseIfNotNULL(publicKeyData);

        return NO;
    }

    CFReleaseIfNotNULL(cfErr);

    // Get base 64 URL encoding of the public key data
    *base64URLEncodedStringOfPublicKeyPtr = [self stringWithBase64UrlEncodingOfData: (__bridge NSData *)publicKeyData];
    if (  ! *base64URLEncodedStringOfPublicKeyPtr  ) {
        [self logErrorMessage: @"Error converting public key to base 64 URL encoding"
              toNSLogOrString: errorMessagePtr];
        CFReleaseIfNotNULL(publicKeyData);
        return NO;
    }

    CFReleaseIfNotNULL(publicKeyData);

    return YES;
}

+(BOOL) setBase64URLEncodedStringOfSignaturePtr: (NSString * _Nonnull * _Nonnull)   base64URLEncodedStringOfSignaturePtr
                                   ofFileAtPath: (NSString * _Nonnull)              path
                              keychainItemLabel: (NSString * _Nonnull)              itemLabel
                                errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr {

    //-----------------------------------------------------------------------------------------------------
    // Create a signature for the file at path using a public/private key pair from the Keychain
    //-----------------------------------------------------------------------------------------------------

    SecKeyRef privateKey = NULL;

    NSData * fileData = [NSData dataWithContentsOfFile: path];
    if (  ! fileData  ) {
        [self logErrorMessage: [NSString stringWithFormat: @"Error: File not found at '%@'", path]
              toNSLogOrString: errorMessagePtr];
        return NO;
    }

    if (  ! [self setPrivateKeyRefPtr: &privateKey
            fromKeychainItemWithLabel: itemLabel
                     okIfDoesNotExist: NO
                      errorMessagePtr: errorMessagePtr]  ) {
        return NO;
    }

    Boolean ok = SecKeyIsAlgorithmSupported(privateKey,
                                            kSecKeyOperationTypeSign,
                                            kSecKeyAlgorithmECDSASignatureMessageX962SHA512);
    if (ok != true) {
        [self logErrorMessage: @"private key does not support ECDSA X9.62 512-bit signing"
              toNSLogOrString: errorMessagePtr];
        CFReleaseIfNotNULL(privateKey);
        return NO;
    }

    CFErrorRef cfErr = NULL;
    CFDataRef signatureData = SecKeyCreateSignature(privateKey,
                                                    kSecKeyAlgorithmECDSASignatureMessageX962SHA512,
                                                    (__bridge CFDataRef)fileData,
                                                    &cfErr);
    CFReleaseIfNotNULL(privateKey);

    if (  signatureData == NULL  ) {
        [self logErrorMessage: [NSString stringWithFormat: @"Unknown error occurred creating signature: '%@'", (__bridge NSError *) cfErr]
              toNSLogOrString: errorMessagePtr];
        return NO;
    }

    // Get base 64 URL encoding of the signature data
    *base64URLEncodedStringOfSignaturePtr = [self stringWithBase64UrlEncodingOfData: (__bridge NSData *)signatureData];
    if (  ! *base64URLEncodedStringOfSignaturePtr  ) {
        [self logErrorMessage: @"Error converting public key to base 64 URL encoding"
              toNSLogOrString: errorMessagePtr];
        CFReleaseIfNotNULL(signatureData);
        return NO;
    }

    CFReleaseIfNotNULL(signatureData);

    return YES;
}

+(BOOL) verifyData: (NSData * _Nonnull)                data
   signatureBase64: (NSString * _Nonnull)              signatureBase64
   publicKeyBase64: (NSString * _Nonnull)              publicKeyBase64
   errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr {

    //------------------------------------------------------------------------------
    // Verify data against a supplied Base‑64 signature using a supplied public key
    //------------------------------------------------------------------------------

    NSData * signatureData = [self dataFromBase64UrlEncodedString: signatureBase64];
    if (  ! signatureData  ) {
        [self logErrorMessage: [NSString stringWithFormat: @"Error: Signature '%@' could not be decoded using base 64 URL decoding", signatureBase64]
              toNSLogOrString: errorMessagePtr];
        return NO;
    }

    NSData * publicKeyData = [self dataFromBase64UrlEncodedString: publicKeyBase64];
    if (  ! publicKeyData  ) {
        [self logErrorMessage: [NSString stringWithFormat: @"Error: Public key '%@' could not be decoded using base 64 URL decoding", signatureBase64]
              toNSLogOrString: errorMessagePtr];
        return NO;
    }

    SecKeyRef publicKey = [self createPublicSecKeyFromData: (__bridge CFDataRef)publicKeyData
                                           errorMessagePtr: errorMessagePtr];
    if (  publicKey == NULL  ) {
        [self logErrorMessage: [NSString stringWithFormat: @"Error: Public key '%@' could not be created using base 64 URL encoded '%@'", publicKeyBase64, signatureBase64]
              toNSLogOrString: errorMessagePtr];
        return NO;
    }

    CFErrorRef cfErr = NULL;
    Boolean ok = SecKeyVerifySignature(publicKey,
                                       kSecKeyAlgorithmECDSASignatureMessageX962SHA512,
                                       (__bridge CFDataRef)data,
                                       (__bridge CFDataRef)signatureData,
                                       &cfErr);
    CFReleaseIfNotNULL(publicKey);
    CFReleaseIfNotNULL(cfErr);

    if (  ok != true  ) {
        [self logErrorMessage: [NSString stringWithFormat: @"Error: Could not verify signature ('%@'); error was %@",
                                signatureBase64, (__bridge NSError *) cfErr]
              toNSLogOrString: errorMessagePtr];
        CFReleaseIfNotNULL(cfErr);
        return NO;
    }

    return YES;
}

+(BOOL) verifyData: (NSData * _Nonnull)                data
   signatureBase64: (NSString * _Nonnull)              signatureBase64
 keychainItemLabel: (NSString * _Nonnull)              itemLabel
   errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr {

    //-------------------------------------------------------------------------------------------------------------
    // Verify data against a supplied Base‑64 signature using a supplied public/private key pair from the Keychain
    //-------------------------------------------------------------------------------------------------------------

    SecKeyRef privateKey = NULL;
    SecKeyRef publicKey  = NULL;

    if (  ! [self setPrivateKeyRefPtr: &privateKey
            fromKeychainItemWithLabel: itemLabel
                     okIfDoesNotExist: NO
                      errorMessagePtr: errorMessagePtr]  ) {
        return NO;
    }

    if (  ! [self setPublicKey: &publicKey
                fromPrivateKey: privateKey
               errorMessagePtr: errorMessagePtr]  ) {
        CFReleaseIfNotNULL(privateKey);
        return NO;
    }

    CFErrorRef cfErr = NULL;
    if (  ! data  ) {
        [self logErrorMessage: @"Error: data is NULL"
              toNSLogOrString: errorMessagePtr];
        return NO;
    }

    NSData * signatureData = [self dataFromBase64UrlEncodedString: signatureBase64];
    if (  ! signatureData  ) {
        [self logErrorMessage: @"Error: signatureBase64 is NULL"
              toNSLogOrString: errorMessagePtr];
        return NO;
    }
    Boolean ok = SecKeyVerifySignature(publicKey,
                                       kSecKeyAlgorithmECDSASignatureMessageX962SHA512,
                                       (__bridge CFDataRef)data,
                                       (__bridge CFDataRef)signatureData,
                                       &cfErr);

    CFReleaseIfNotNULL(privateKey);
    CFReleaseIfNotNULL(publicKey);

    if (  ok != true  ) {
        [self logErrorMessage: [NSString stringWithFormat: @"Error: Could not verify signature ('%@'); error was %@",
                                signatureBase64, (__bridge NSError *) cfErr]
              toNSLogOrString: errorMessagePtr];
        CFReleaseIfNotNULL(cfErr);
        return NO;
    }

    return YES;
}

+(BOOL) verifyFileAtPath: (NSString * _Nonnull)              path
         signatureBase64: (NSString * _Nonnull)              signatureBase64
       keychainItemLabel: (NSString * _Nonnull)              itemLabel
         errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr {

    //-----------------------------------------------------------------------------------------------------
    // Verify a file against a supplied Base‑64 signature using a public/private key pair from the Keychain
    //-----------------------------------------------------------------------------------------------------

    NSData * data = [self fileContentsFromPath: path errorMessagePtr: errorMessagePtr];
    if (  ! data  ) {
        return NO;
    }

    BOOL ok = [self verifyData: data
               signatureBase64: signatureBase64
             keychainItemLabel: itemLabel
               errorMessagePtr: errorMessagePtr];
    return ok;
}

+(BOOL) verifyFileAtPath: (NSString * _Nonnull)              path
         signatureBase64: (NSString * _Nonnull)              signatureBase64
         publicKeyBase64: (NSString * _Nonnull)              publicKeyBase64
         errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr {

    //----------------------------------------------------------------------
    // Verify a file against a base‑64 signature using a base‑64 public key
    //----------------------------------------------------------------------

    NSData * data = [self fileContentsFromPath: path errorMessagePtr: errorMessagePtr];
    if (  ! data  ) {
        return NO;
    }

    BOOL ok = [self verifyData: data
               signatureBase64: signatureBase64
               publicKeyBase64: publicKeyBase64
               errorMessagePtr: errorMessagePtr];
    return ok;
}

+(BOOL) testSigningFileAtPath: (NSString * _Nonnull) path
       usingKeychainItemLabel: (NSString * _Nonnull) itemLabel
              errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr  {

    CFErrorRef cfErr        = NULL;
    SecKeyRef privateKey    = NULL;
    SecKeyRef publicKey     = NULL;
    CFDataRef signatureData = NULL;

    //
    // Generate a key pair, storing the private key in the Keychain
    //

    NSData * itemLabelData = [itemLabel dataUsingEncoding: NSUTF8StringEncoding];
    NSDictionary * attributes = @{
        (__bridge NSString *) kSecAttrKeyType       : (__bridge NSString *) kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge NSString *) kSecAttrAccessible    : (__bridge NSString *) kSecAttrAccessibleWhenUnlocked,
        (__bridge NSString *) kSecAttrKeySizeInBits : @256,
        (__bridge NSString *) kSecAttrLabel         : itemLabel,
        (__bridge NSString *)kSecPrivateKeyAttrs    : @{ (__bridge NSString *)kSecAttrIsPermanent:    @YES,
                                                         (__bridge NSString *)kSecAttrApplicationTag: itemLabelData,
        },
    };

    privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &cfErr);
    if ( privateKey == NULL  ) {
        [self logErrorMessage: [NSString stringWithFormat: @"Error: Could not create key pair; error was %@", (__bridge NSError *) cfErr]
              toNSLogOrString: errorMessagePtr];
        goto errorExit;
    }

    //
    // Get file signature as a base64 string
    //

    // Get the file's data
    NSData * fileData = [NSData dataWithContentsOfFile: path];
    if (  ! fileData  ) {
        [self logErrorMessage: [NSString stringWithFormat: @"Error: File not found at '%@'", path]
              toNSLogOrString: errorMessagePtr];
        goto errorExit;
    }

    // Verify that the algorithm can sign
    if (  true != SecKeyIsAlgorithmSupported(privateKey,
                                             kSecKeyOperationTypeSign,
                                             kSecKeyAlgorithmECDSASignatureMessageX962SHA512)  ) {
        [self logErrorMessage: @"Error: Private key does not support ECDSA X9.62 512-bit signing"
              toNSLogOrString: errorMessagePtr];
        goto errorExit;
    };

    // Get the signature
    signatureData = SecKeyCreateSignature(privateKey,
                                          kSecKeyAlgorithmECDSASignatureMessageX962SHA512,
                                          (__bridge CFDataRef)fileData,
                                          &cfErr);
    if (  signatureData == NULL  ) {
        [self logErrorMessage: [NSString stringWithFormat: @"Error occurred creating signature: '%@'", (__bridge NSError *) cfErr]
              toNSLogOrString: errorMessagePtr];
        goto errorExit;
    }

    // Get base 64 URL encoded string of the signature data
    NSString * signatureb64String = [self stringWithBase64UrlEncodingOfData: (__bridge NSData *)signatureData];
    if (  ! signatureb64String  ) {
        [self logErrorMessage: @"Error occurred creating string encoded as a base64 representation of data"
              toNSLogOrString: errorMessagePtr];
        goto errorExit;
    }

    // Get data from that string
    NSData * signatureDataFromStringFromData = [self dataFromBase64UrlEncodedString: signatureb64String];
    if (  ! signatureDataFromStringFromData  ) {
        [self logErrorMessage: @"Error getting data from string encoded as a base64 representation of data"
              toNSLogOrString: errorMessagePtr];
        goto errorExit;
    }

    // Check that the conversion from base 64 URL encoding and back didn't change it
    if (  [(__bridge NSData *)signatureData isNotEqualTo: signatureDataFromStringFromData]  ) {
        [self logErrorMessage: [NSString stringWithFormat:
                                @"Error converting data from string encoded as a base64 representation back to the data failed. Original data was\n%@\nConverted data is\n%@",
                                (__bridge NSData *)signatureData, signatureDataFromStringFromData]
              toNSLogOrString: errorMessagePtr];
        goto errorExit;
    }

    //
    // Get the public key
    //
    publicKey = SecKeyCopyPublicKey(privateKey);
    if (  publicKey == NULL  ) {
        [self logErrorMessage: @"Error: Failed to obtain public key from private key"
              toNSLogOrString: errorMessagePtr];
        goto errorExit;
    }

    //
    // Verify signature of file
    //
    if (  true != SecKeyVerifySignature(publicKey,
                                        kSecKeyAlgorithmECDSASignatureMessageX962SHA512,
                                        (__bridge CFDataRef)fileData,
                                        (__bridge CFDataRef)signatureData,
                                        &cfErr)  ) {
        [self logErrorMessage: @"Error: Could not verify signature"
              toNSLogOrString: errorMessagePtr];
        goto errorExit;
    }

    if (  ! [self deletePrivateKeyFromKeychainWithLabel: itemLabel
                                        errorMessagePtr: errorMessagePtr]  ) {
        [self logErrorMessage: @"Error: Could not delete private key"
              toNSLogOrString: errorMessagePtr];
        goto errorExit;
    }

    if (  cfErr          ) CFRelease(cfErr);
    if (  privateKey     ) CFRelease(privateKey);
    if (  publicKey      ) CFRelease(publicKey);
    if (  signatureData  ) CFRelease(signatureData);

    return YES;

errorExit:
    if (  cfErr          ) CFRelease(cfErr);
    if (  privateKey     ) CFRelease(privateKey);
    if (  publicKey      ) CFRelease(publicKey);
    if (  signatureData  ) CFRelease(signatureData);

    return NO;
}

@end
