/*
 * TBTotpCredentials — TOTP secret storage implementation.
 */

#import "TBTotpCredentials.h"
#import "TBTotpGenerator.h"
#import "KeyChain.h"
#import "helper.h"
#import "TBUserDefaults.h"

extern TBUserDefaults * gTbDefaults;

@implementation TBTotpCredentials

+ (NSString *) credentialsNameForDisplayName: (NSString *) displayName
{
    NSString * allGroup = [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"];
    if (  [allGroup length] != 0  ) {
        return allGroup;
    }

    NSString * group = credentialsGroupFromDisplayName(displayName);
    if (  group  ) {
        return group;
    }

    return displayName;
}

+ (KeyChain *) totpKeychainForDisplayName: (NSString *) displayName
{
    NSString * credentialsName = [self credentialsNameForDisplayName: displayName];
    NSString * prefix = @"Tunnelblick-Auth-";
    if (   [gTbDefaults stringForKey: @"namedCredentialsThatAllConfigurationsUse"]
        || credentialsGroupFromDisplayName(displayName)  ) {
        prefix = @"Tunnelblick-Auth-Group-";
    }
    return [[[KeyChain alloc] initWithService: [prefix stringByAppendingString: credentialsName]
                               withAccountName: @"totpSecret"] autorelease];
}

+ (NSString *) totpAutoFillEnabledPreferenceKeyForCredentialsName: (NSString *) credentialsName
{
    return [NSString stringWithFormat: @"%@-totpAutoFillEnabled", credentialsName];
}

+ (NSString *) keychainHasTotpSecretPreferenceKeyForCredentialsName: (NSString *) credentialsName
{
    return [NSString stringWithFormat: @"%@-keychainHasTotpSecret", credentialsName];
}

+ (NSString *) loginWindowSecurityTokenPreferenceKeyForDisplayName: (NSString *) displayName
{
    return [displayName stringByAppendingString: @"-loginWindowSecurityTokenCheckboxIsChecked"];
}

+ (BOOL) totpAutoFillEnabledForCredentialsName: (NSString *) credentialsName
{
    NSString * key = [self totpAutoFillEnabledPreferenceKeyForCredentialsName: credentialsName];
    return [gTbDefaults boolForKey: key];
}

+ (BOOL) keychainHasTotpSecretForCredentialsName: (NSString *) credentialsName
{
    NSString * key = [self keychainHasTotpSecretPreferenceKeyForCredentialsName: credentialsName];
    return (   [gTbDefaults boolForKey: key]
            && [gTbDefaults canChangeValueForKey: key]  );
}

+ (NSString *) totpSecretForDisplayName: (NSString *) displayName
{
    NSString * credentialsName = [self credentialsNameForDisplayName: displayName];
    if (  ! [self keychainHasTotpSecretForCredentialsName: credentialsName]  ) {
        return nil;
    }

    KeyChain * kc = [self totpKeychainForDisplayName: displayName];
    NSString * secret = [kc password];
    if (  [secret length] == 0  ) {
        NSString * prefKey = [self keychainHasTotpSecretPreferenceKeyForCredentialsName: credentialsName];
        [gTbDefaults removeObjectForKey: prefKey];
        return nil;
    }

    return secret;
}

+ (NSString *) currentTotpCodeForDisplayName: (NSString *) displayName
{
    return [self totpCodeForDisplayName: displayName atTime: [[NSDate date] timeIntervalSince1970]];
}

+ (NSString *) totpCodeForDisplayName: (NSString *) displayName atTime: (NSTimeInterval) timestamp
{
    NSString * credentialsName = [self credentialsNameForDisplayName: displayName];
    if (  ! [self totpAutoFillEnabledForCredentialsName: credentialsName]  ) {
        return nil;
    }

    NSString * secret = [self totpSecretForDisplayName: displayName];
    if (  ! secret  ) {
        return nil;
    }

    return [TBTotpGenerator generateCodeWithSecret: secret digits: 6 period: 30 atTime: timestamp];
}

+ (BOOL) saveTotpSecret: (NSString *) base32Secret
        forDisplayName: (NSString *) displayName
{
    if (  ! [TBTotpGenerator isValidBase32Secret: base32Secret]  ) {
        return NO;
    }

    NSString * credentialsName = [self credentialsNameForDisplayName: displayName];
    NSString * normalized = [[base32Secret uppercaseString] stringByReplacingOccurrencesOfString: @" " withString: @""];
    KeyChain * kc = [self totpKeychainForDisplayName: displayName];
    [kc deletePassword];
    if (  [kc setPassword: normalized] != 0  ) {
        NSLog(@"Could not save TOTP secret in Keychain for credentials '%@'", credentialsName);
        return NO;
    }

    NSString * hasKey = [self keychainHasTotpSecretPreferenceKeyForCredentialsName: credentialsName];
    [gTbDefaults setBool: YES forKey: hasKey];
    [self setTotpAutoFillEnabled: YES forCredentialsName: credentialsName];
    [self enableSecurityTokenForDisplayName: displayName];
    return YES;
}

+ (void) deleteTotpSecretForDisplayName: (NSString *) displayName
{
    NSString * credentialsName = [self credentialsNameForDisplayName: displayName];
    KeyChain * kc = [self totpKeychainForDisplayName: displayName];
    [kc deletePassword];
    [gTbDefaults removeObjectForKey: [self keychainHasTotpSecretPreferenceKeyForCredentialsName: credentialsName]];
    [gTbDefaults removeObjectForKey: [self totpAutoFillEnabledPreferenceKeyForCredentialsName: credentialsName]];
}

+ (void) setTotpAutoFillEnabled: (BOOL) enabled
             forCredentialsName: (NSString *) credentialsName
{
    NSString * key = [self totpAutoFillEnabledPreferenceKeyForCredentialsName: credentialsName];
    if (  enabled  ) {
        [gTbDefaults setBool: YES forKey: key];
    } else {
        [gTbDefaults removeObjectForKey: key];
    }
}

+ (void) enableSecurityTokenForDisplayName: (NSString *) displayName
{
    NSString * tokenKey = [self loginWindowSecurityTokenPreferenceKeyForDisplayName: displayName];
    [gTbDefaults setBool: YES forKey: tokenKey];
}

@end
