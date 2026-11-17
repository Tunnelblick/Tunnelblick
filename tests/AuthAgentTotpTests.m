#import <Cocoa/Cocoa.h>
#include <assert.h>

static BOOL useToken = YES, savedCredentials = YES;
static NSUInteger refreshedCodes, loginPrompts;
static NSString *freshCode = @"222222";

@interface TestDefaults : NSObject
-(BOOL) boolForKey: (NSString *) key;
-(BOOL) canChangeValueForKey: (NSString *) key;
-(void) removeObjectForKey: (NSString *) key;
-(void) setBool: (BOOL) value forKey: (NSString *) key;
@end
@implementation TestDefaults
-(BOOL) boolForKey: (NSString *) key { return YES; }
-(BOOL) canChangeValueForKey: (NSString *) key { return YES; }
-(void) removeObjectForKey: (NSString *) key {}
-(void) setBool: (BOOL) value forKey: (NSString *) key {}
@end
static TestDefaults *gTbDefaults;
@interface TestKeychain : NSObject {
@public NSString *value;
}
-(NSString *) password;
-(void) deletePassword;
-(int) setPassword: (NSString *) password;
@end
@implementation TestKeychain
-(NSString *) password { return value; }
-(void) deletePassword {}
-(int) setPassword: (NSString *) password { return 0; }
@end
@interface TestWindow : NSObject
-(void) close;
@end
@implementation TestWindow
-(void) close {}
@end
@interface TestField : NSObject {
    NSString *value;
}
-(id) initWithValue: (NSString *) text;
-(NSString *) stringValue;
@end
@implementation TestField
-(id) initWithValue: (NSString *) text { if ((self = [super init])) value = [text copy]; return self; }
-(NSString *) stringValue { return value; }
-(void) dealloc { [value release]; [super dealloc]; }
@end
@interface LoginWindowController : NSObject
-(id) initWithDelegate: (id) delegate;
-(void) redisplay;
-(TestWindow *) window;
-(TestField *) username;
-(TestField *) password;
-(TestField *) securityToken;
-(BOOL) useSecurityTokenChecked;
-(BOOL) isSaveUsernameInKeychainChecked;
-(BOOL) isSavePasswordInKeychainChecked;
@end
@implementation LoginWindowController
-(id) initWithDelegate: (id) delegate { return [super init]; }
-(void) redisplay {}
-(TestWindow *) window { return [[[TestWindow alloc] init] autorelease]; }
-(TestField *) username { return [[[TestField alloc] initWithValue: @"user"] autorelease]; }
-(TestField *) password { return [[[TestField alloc] initWithValue: @"base-password"] autorelease]; }
-(TestField *) securityToken { return [[[TestField alloc] initWithValue: @"111111"] autorelease]; }
-(BOOL) useSecurityTokenChecked { return useToken; }
-(BOOL) isSaveUsernameInKeychainChecked { return YES; }
-(BOOL) isSavePasswordInKeychainChecked { return YES; }
@end
@interface TestApplication : NSObject
-(NSInteger) runModalForWindow: (TestWindow *) window;
@end
@implementation TestApplication
-(NSInteger) runModalForWindow: (TestWindow *) window { loginPrompts++; return NSRunStoppedResponse; }
@end
static TestApplication *testApplication;
#undef NSApp
#define NSApp testApplication

@interface TBTotpCredentials : NSObject
+(NSString *) currentTotpCodeForDisplayName: (NSString *) name;
+(NSString *) totpCodeForDisplayName: (NSString *) name atTime: (NSTimeInterval) timestamp;
@end
@implementation TBTotpCredentials
+(NSString *) currentTotpCodeForDisplayName: (NSString *) name { return @"111111"; }
+(NSString *) totpCodeForDisplayName: (NSString *) name atTime: (NSTimeInterval) timestamp {
    refreshedCodes++;
    assert(timestamp > 0);
    return freshCode;
}
@end
@interface TestCredentialAgent : NSObject {
@public
    BOOL authenticationUsedAutoTotp, authenticationWasFromKeychain, allowInteraction, showingLoginWindow;
    NSTimeInterval automaticTotpCodeTime;
    NSString *authMode, *usernameAndPasswordPreferenceKey, *usernamePreferenceKey;
    TestKeychain *usernameKeychain, *passwordKeychain;
    LoginWindowController *loginScreen;
}
-(NSArray *) getUsernameAndPassword;
-(NSString *) authMode;
-(NSString *) displayName;
-(BOOL) usernameIsInKeychain;
-(BOOL) passwordIsInKeychain;
@end
@implementation TestCredentialAgent
#include "ProductionCredentialHandler.inc"
-(id) init {
    if ((self = [super init])) {
        authMode = @"password";
        allowInteraction = YES;
        usernameKeychain = [TestKeychain new]; usernameKeychain->value = @"user";
        passwordKeychain = [TestKeychain new]; passwordKeychain->value = @"base-password";
        usernameAndPasswordPreferenceKey = @"saved-both";
        usernamePreferenceKey = @"saved-username";
    }
    return self;
}
-(void) dealloc { [usernameKeychain release]; [passwordKeychain release]; [loginScreen release]; [super dealloc]; }
-(NSString *) authMode { return authMode; }
-(NSString *) displayName { return @"Regression VPN"; }
-(BOOL) usernameIsInKeychain { return savedCredentials; }
-(BOOL) passwordIsInKeychain { return savedCredentials; }
@end
int main(void) {
    @autoreleasepool {
        gTbDefaults = [[[TestDefaults alloc] init] autorelease];
        testApplication = [[[TestApplication alloc] init] autorelease];
        TestCredentialAgent *a = [[[TestCredentialAgent alloc] init] autorelease];
        NSArray *credentials = [a getUsernameAndPassword];
        assert([credentials[1] isEqualToString: @"base-password222222"]);
        assert(loginPrompts == 0 && a->authenticationUsedAutoTotp && a->authenticationWasFromKeychain);
        savedCredentials = NO;
        credentials = [a getUsernameAndPassword];
        assert([credentials[1] isEqualToString: @"base-password222222"]);
        assert(loginPrompts == 1 && a->authenticationUsedAutoTotp && !a->authenticationWasFromKeychain);
        assert(refreshedCodes == 2);
        useToken = NO;
        credentials = [a getUsernameAndPassword];
        assert([credentials[1] isEqualToString: @"base-password"] && !a->authenticationUsedAutoTotp);
        assert(refreshedCodes == 2);
        useToken = YES;
        freshCode = nil;
        assert(![a getUsernameAndPassword] && !a->authenticationUsedAutoTotp);
        puts("PASS: saved-credential login skips modal, TOTP refreshed at submission after modal, token checkbox respected, generation failure stops submission.");
    }
    return 0;
}
