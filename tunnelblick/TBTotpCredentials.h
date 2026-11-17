/*
 * TBTotpCredentials — Keychain storage and preferences for TOTP secrets.
 * Scope secrets by credentialsName, following the existing username/password rules.
 */

#import <Foundation/Foundation.h>

@interface TBTotpCredentials : NSObject

// Resolve credentialsName for a VPN displayName, including named credentials groups.
+ (NSString *) credentialsNameForDisplayName: (NSString *) displayName;

+ (NSString *) totpAutoFillEnabledPreferenceKeyForCredentialsName: (NSString *) credentialsName;
+ (NSString *) keychainHasTotpSecretPreferenceKeyForCredentialsName: (NSString *) credentialsName;

+ (NSString *) loginWindowSecurityTokenPreferenceKeyForDisplayName: (NSString *) displayName;

+ (BOOL) totpAutoFillEnabledForCredentialsName: (NSString *) credentialsName;
+ (BOOL) keychainHasTotpSecretForCredentialsName: (NSString *) credentialsName;

+ (NSString *) totpSecretForDisplayName: (NSString *) displayName;
+ (NSString *) currentTotpCodeForDisplayName: (NSString *) displayName;
+ (NSString *) totpCodeForDisplayName: (NSString *) displayName atTime: (NSTimeInterval) timestamp;

+ (BOOL) saveTotpSecret: (NSString *) base32Secret
        forDisplayName: (NSString *) displayName;

+ (void) deleteTotpSecretForDisplayName: (NSString *) displayName;

+ (void) setTotpAutoFillEnabled: (BOOL) enabled
             forCredentialsName: (NSString *) credentialsName;

+ (void) enableSecurityTokenForDisplayName: (NSString *) displayName;

@end
