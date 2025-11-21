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


@interface UpdateSigning :  NSObject

+(BOOL) generateKeyPairWithKeychainItemLabel: (NSString * _Nonnull)              itemLabel
                             errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr;

+(BOOL) setPrivateKeyRefPtr: (SecKeyRef _Nonnull * _Nonnull)    keyPtr
  fromKeychainItemWithLabel: (NSString * _Nonnull)              itemLabel
           okIfDoesNotExist: (BOOL)                             okIfDoesNotExist
            errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr;

+(BOOL) deletePrivateKeyFromKeychainWithLabel: (NSString * _Nonnull)              itemLabel
                              errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr;

+(BOOL) setBase64URLEncodedStringOfPublicKeyPtr: (NSString * _Nonnull * _Nonnull)  base64URLEncodedStringOfPublicKeyPtr
                              keychainItemLabel: (NSString * _Nonnull)             itemLabel
                                errorMessagePtr: (NSString * _Nullable * _Nonnull) errorMessagePtr;

+(BOOL) setBase64URLEncodedStringOfSignaturePtr: (NSString * _Nonnull * _Nonnull)   base64URLEncodedStringOfSignaturePtr
                                   ofFileAtPath: (NSString * _Nonnull)              path
                              keychainItemLabel: (NSString * _Nonnull)              itemLabel
                                errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr;

+(BOOL) verifyData: (NSData * _Nonnull)                data
   signatureBase64: (NSString * _Nonnull)              signatureBase64
   publicKeyBase64: (NSString * _Nonnull)              publicKeyBase64
   errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr;

+(BOOL) verifyFileAtPath: (NSString * _Nonnull)              path
         signatureBase64: (NSString * _Nonnull)              signatureBase64
       keychainItemLabel: (NSString * _Nonnull)              itemLabel
         errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr;

+(BOOL) verifyFileAtPath: (NSString * _Nonnull)              path
         signatureBase64: (NSString * _Nonnull)              signatureBase64
         publicKeyBase64: (NSString * _Nonnull)              publicKeyBase64
         errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr;

+(BOOL) testSigningFileAtPath: (NSString * _Nonnull)              path
       usingKeychainItemLabel: (NSString * _Nonnull)              label
              errorMessagePtr: (NSString * _Nullable * _Nullable) errorMessagePtr;

@end
