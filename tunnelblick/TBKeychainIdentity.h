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

#import <Foundation/Foundation.h>
#import <Security/Security.h>

// Finds identities (a certificate together with its private key) in the user's Keychain and signs
// data with them, so that OpenVPN's "--management-external-cert" and "--management-external-key"
// options can be used on macOS instead of the Windows-only "--cryptoapicert" option.
//
// The argument to "--management-external-cert" is passed through to the management interface in the
// ">NEED-CERTIFICATE:" message and is used here to select which identity to use. The syntax mirrors
// the syntax of "--cryptoapicert":
//
//      SUBJ:<string>   Use the identity whose certificate's subject contains <string>
//      ISSUER:<string> Use the identity whose certificate's issuer contains <string>
//      THUMB:<string>  Use the identity whose certificate's SHA-1 fingerprint is <string>
//
// A selector without one of those prefixes is interpreted as if it had the "SUBJ:" prefix.

@interface TBKeychainIdentity : NSObject

// Returns a retained SecIdentityRef which the caller must CFRelease(), or NULL if an identity could
// not be found (in which case *errMsgPtr is set to a localized message describing the problem).
+(SecIdentityRef) copyIdentityMatchingSelector: (NSString *)  selector
                                  errorMessage: (NSString **) errMsgPtr;

// Returns the identity's certificate as PEM (including the "-----BEGIN CERTIFICATE-----" and
// "-----END CERTIFICATE-----" lines, separated by LF characters, without a trailing LF), or nil if
// it could not be obtained (in which case *errMsgPtr is set to a localized message).
+(NSString *) pemForIdentity: (SecIdentityRef) identity
                errorMessage: (NSString **)    errMsgPtr;

// Signs data with the identity's private key and returns the signature, or nil if the data could
// not be signed (in which case *errMsgPtr is set to a localized message).
//
// 'algorithm' is the algorithm string from the management interface's ">PK_SIGN:" message (that is,
// everything after the comma that follows the base64-encoded data). It may be nil or empty, which
// happens with the obsolete ">RSA_SIGN:" message and means "RSA_PKCS1_PADDING".
+(NSData *) signData: (NSData *)        data
        withIdentity: (SecIdentityRef)  identity
           algorithm: (NSString *)      algorithm
        errorMessage: (NSString **)     errMsgPtr;

// Returns a one-line description of an identity's certificate ("subject; SHA-1 fingerprint"), for
// use in the Tunnelblick log. Returns nil if the description could not be created.
+(NSString *) descriptionForIdentity: (SecIdentityRef) identity;

@end
