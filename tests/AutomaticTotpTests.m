#import <Cocoa/Cocoa.h>
#import "TBTotpGenerator.h"
#import "TBTotpTiming.h"
#import "NSTimer+TB.h"
#include <assert.h>

#define TBLog(...) do {} while (0);
static BOOL gShuttingDownTunnelblick, gShuttingDownOrRestartingComputer;
static NSUInteger alerts, notifications;
static int TBRunAlertPanel(NSString *a, NSString *b, NSString *c, NSString *d, NSString *e) {
    alerts++;
    return NSAlertDefaultReturn;
}
@interface NSString (TestComparison)
-(BOOL) isNotEqualTo: (id) other;
@end
@implementation NSString (TestComparison)
-(BOOL) isNotEqualTo: (id) other { return ![self isEqual: other]; }
@end
@interface UIHelper : NSObject
+(void) showSuccessNotificationTitle: (NSString *) title msg: (NSString *) message;
@end
@implementation UIHelper
+(void) showSuccessNotificationTitle: (NSString *) title msg: (NSString *) message { notifications++; }
@end
@interface TestAuthAgent : NSObject {
@public BOOL automatic, saved; NSTimeInterval codeTime;
}
-(BOOL) authenticationUsedAutoTotp;
-(BOOL) keychainHasUsernameAndPassword;
-(BOOL) keychainHasPassphrase;
-(NSTimeInterval) automaticTotpCodeTime;
-(NSString *) authMode;
-(void) deletePassword;
-(void) deletePassphrase;
@end
@implementation TestAuthAgent
-(BOOL) authenticationUsedAutoTotp { return automatic; }
-(BOOL) keychainHasUsernameAndPassword { return saved; }
-(BOOL) keychainHasPassphrase { return saved; }
-(NSTimeInterval) automaticTotpCodeTime { return codeTime; }
-(NSString *) authMode { return @"password"; }
-(void) deletePassword { assert(!"automatic retry must not delete credentials"); }
-(void) deletePassphrase { assert(!"automatic retry must not delete credentials"); }
@end
static BOOL totpEnabled = YES;
@interface TBTotpCredentials : NSObject
+(NSString *) credentialsNameForDisplayName: (NSString *) name;
+(BOOL) totpAutoFillEnabledForCredentialsName: (NSString *) name;
+(BOOL) keychainHasTotpSecretForCredentialsName: (NSString *) name;
@end
@implementation TBTotpCredentials
+(NSString *) credentialsNameForDisplayName: (NSString *) name { return name; }
+(BOOL) totpAutoFillEnabledForCredentialsName: (NSString *) name { return totpEnabled; }
+(BOOL) keychainHasTotpSecretForCredentialsName: (NSString *) name { return YES; }
@end

enum { userWantsUndecided, userWantsRetry, userWantsAbandon };
@interface TestConnection : NSObject {
@public
    TestAuthAgent *myAuthAgent;
    BOOL authFailed, credentialsAskedFor, areDisconnecting, disconnected;
    int userWantsState;
    NSUInteger automaticTotpRetryCount, connects, sends, challenges;
    NSTimeInterval automaticTotpRetryNotBefore;
    NSTimer *automaticTotpCredentialsTimer;
    NSString *displayName, *requested;
}
-(void) processPasswordOrPassphraseWithLine: (NSString *) line parameterString: (NSString *) parameter command: (NSString *) command;
-(void) afterFailure: (NSDictionary *) dict;
-(void) afterFailureHandler: (NSTimer *) timer;
-(void) credentialsHaveBeenAskedFor: (NSDictionary *) dict;
-(void) credentialsHaveBeenAskedForHandler: (NSTimer *) timer;
-(void) provideCredentials: (NSString *) parameter line: (NSString *) line;
-(void) cancelAutomaticTotpCredentialsTimer;
-(void) notifyAutomaticTotpFailure;
-(void) prepareAutomaticTotpForConnection;
-(void) provideAutomaticTotpCredentials: (NSTimer *) timer;
-(BOOL) deferAutomaticTotpCredentials: (NSString *) parameter line: (NSString *) line;
-(BOOL) isDisconnected;
-(NSString *) localizedName;
-(NSString *) displayName;
-(NSString *) requestedState;
-(NSString *) dynamicChallengeUsername;
-(void) parseAndSaveDynamicChallengeResponseInfo: (NSString *) line;
-(void) addToLog: (NSString *) text;
-(void) startDisconnectingUserKnows: (NSNumber *) known;
-(void) connect: (id) sender userKnows: (BOOL) known;
@end
@implementation TestConnection
#include "ProductionAuthHandlers.inc"
-(id) init {
    if ((self = [super init])) {
        myAuthAgent = [TestAuthAgent new];
        myAuthAgent->automatic = myAuthAgent->saved = YES;
        myAuthAgent->codeTime = [[NSDate date] timeIntervalSince1970];
        displayName = @"Regression VPN";
        requested = @"CONNECTED";
    }
    return self;
}
-(void) dealloc { [self cancelAutomaticTotpCredentialsTimer]; [myAuthAgent release]; [super dealloc]; }
-(BOOL) isDisconnected { return disconnected; }
-(NSString *) localizedName { return displayName; }
-(NSString *) displayName { return displayName; }
-(NSString *) requestedState { return requested; }
-(NSString *) dynamicChallengeUsername { return nil; }
-(void) parseAndSaveDynamicChallengeResponseInfo: (NSString *) line { challenges++; }
-(void) addToLog: (NSString *) text {}
-(void) notifyAutomaticTotpFailure { notifications++; }
-(void) startDisconnectingUserKnows: (NSNumber *) known {
    areDisconnecting = YES;
    requested = @"EXITING";
    [self cancelAutomaticTotpCredentialsTimer];
}
-(void) connect: (id) sender userKnows: (BOOL) known {
    [self prepareAutomaticTotpForConnection];
    connects++;
    authFailed = NO;
}
-(void) provideCredentials: (NSString *) parameter line: (NSString *) line {
    if (![self deferAutomaticTotpCredentials: parameter line: line]) { sends++; authFailed = NO; }
}
-(void) afterFailureHandler: (NSTimer *) timer {}
-(void) credentialsHaveBeenAskedForHandler: (NSTimer *) timer {}
@end

static void cryptoTests(void) {
    NSString *secret = @"GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
    const NSTimeInterval times[] = {59, 1111111109, 1111111111, 1234567890, 2000000000, 20000000000};
    NSArray *expected = @[@"94287082", @"07081804", @"14050471", @"89005924", @"69279037", @"65353130"];
    for (NSUInteger i = 0; i < expected.count; i++) {
        NSString *code = [TBTotpGenerator generateCodeWithSecret: secret digits: 8 period: 30 atTime: times[i]];
        assert([code isEqualToString: expected[i]]);
    }
    assert([[TBTotpGenerator generateCodeWithSecret: secret digits: 6 period: 30 atTime: 59] isEqualToString: @"287082"]);
    assert([[TBTotpGenerator generateCodeWithSecret: secret digits: 6 period: 30 atTime: 1111111109] isEqualToString: @"081804"]);
    assert(![TBTotpGenerator generateCodeWithSecret: secret digits: 20 period: 30 atTime: 59]);
    assert(![TBTotpGenerator generateCodeWithSecret: secret digits: 6 period: 30 atTime: NAN]);
    assert(![TBTotpGenerator generateCodeWithSecret: secret digits: 6 period: 30 atTime: -1]);
    assert(TBTotpFreshCodeDelay(24.9) == 0);
    assert(TBTotpFreshCodeDelay(25) == 6);
    assert(fabs(TBTotpFreshCodeDelay(29.9) - 1.1) < 1e-6);
    assert(TBTotpFreshCodeDelay(30) == 0);
    assert(TBTotpRetryNotBefore(12, 10) == 31);
    assert(TBTotpRetryNotBefore(35, 10) == 36);
    assert(TBTotpRetryNotBefore(5, 60) == 91);
}

static void flowTests(void) {
    NSString *failure = @">PASSWORD:Verification Failed: 'Auth'";
    NSString *need = @">PASSWORD:Need 'Auth' username/password";
    NSDictionary *request = @{@"parameterString": @"Need 'Auth' username/password", @"line": need};
    TestConnection *c = [[[TestConnection alloc] init] autorelease];
    for (NSUInteger i = 1; i <= 2; i++) {
        c->authFailed = NO; // A new credentials submission.
        [c processPasswordOrPassphraseWithLine: failure parameterString: @"Verification Failed: 'Auth'" command: @"PASSWORD"];
        assert(c->automaticTotpRetryCount == i && c->userWantsState == userWantsRetry);
        assert(alerts == 0 && !c->areDisconnecting);
        [c processPasswordOrPassphraseWithLine: failure parameterString: @"Verification Failed: 'Auth'" command: @"PASSWORD"];
        assert(c->automaticTotpRetryCount == i); // Duplicate notification.
    }
    c->authFailed = NO;
    [c processPasswordOrPassphraseWithLine: failure parameterString: @"Verification Failed: 'Auth'" command: @"PASSWORD"];
    assert(c->areDisconnecting && c->userWantsState == userWantsAbandon && alerts == 0 && notifications == 1);
    c->disconnected = YES;
    [c afterFailure: request];
    assert(c->connects == 0);

    TestConnection *retry = [[[TestConnection alloc] init] autorelease];
    [retry processPasswordOrPassphraseWithLine: failure parameterString: @"Verification Failed: 'Auth'" command: @"PASSWORD"];
    retry->disconnected = YES;
    [retry afterFailure: request];
    assert(retry->connects == 1 && retry->automaticTotpRetryCount == 1);
    [retry afterFailure: request];
    assert(retry->connects == 1); // Stale callback cannot reconnect twice.
    retry->automaticTotpRetryCount = 2;
    [retry prepareAutomaticTotpForConnection];
    assert(retry->automaticTotpRetryCount == 0 && retry->automaticTotpRetryNotBefore == 0);

    TestConnection *waiting = [[[TestConnection alloc] init] autorelease];
    waiting->automaticTotpRetryCount = 1;
    waiting->automaticTotpRetryNotBefore = [[NSDate date] timeIntervalSince1970] + 30;
    assert([waiting deferAutomaticTotpCredentials: request[@"parameterString"] line: need]);
    NSTimer *pending = [waiting->automaticTotpCredentialsTimer retain];
    assert([pending isValid] && waiting->sends == 0);
    assert([waiting deferAutomaticTotpCredentials: request[@"parameterString"] line: need]);
    assert(waiting->automaticTotpCredentialsTimer == pending); // Coalesce duplicate requests.
    [waiting startDisconnectingUserKnows: @YES];
    assert(![pending isValid] && !waiting->automaticTotpCredentialsTimer);
    [waiting provideAutomaticTotpCredentials: pending];
    assert(waiting->sends == 0 && waiting->connects == 0);
    [pending release];

    TestConnection *manual = [[[TestConnection alloc] init] autorelease];
    manual->myAuthAgent->automatic = NO;
    [manual processPasswordOrPassphraseWithLine: failure parameterString: @"Verification Failed: 'Auth'" command: @"PASSWORD"];
    assert(alerts == 1 && manual->automaticTotpRetryCount == 0);
    [manual processPasswordOrPassphraseWithLine: @">PASSWORD:Verification Failed: 'Auth' ['CRV1:R:state:user:code']" parameterString: @"" command: @"PASSWORD"];
    assert(manual->challenges == 1 && alerts == 1);
    totpEnabled = NO;
    assert(![manual deferAutomaticTotpCredentials: request[@"parameterString"] line: need]);
    totpEnabled = YES;
    assert(![manual deferAutomaticTotpCredentials: request[@"parameterString"] line: [need stringByAppendingString: @" SC:1,Challenge"]]);
}
int main(void) {
    @autoreleasepool {
        cryptoTests();
        flowTests();
        puts("PASS: RFC 6238 vectors, leading zeroes, expiry boundaries, fresh-code retry, retry limit, duplicate events, reconnect, cancellation, manual auth, CRV1 and static challenge isolation.");
    }
    return 0;
}
