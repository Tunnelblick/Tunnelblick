//
//  AuthAgent.h
//  Tunnelblick
//
//  Created by al on 12/22/05.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "KeyChain.h"
#import "NetSocket.h"
#import <Foundation/NSDebug.h>

@interface AuthAgent : NSObject {
	NSString *authMode;
	BOOL defaultIsSetKey;
	NSString *username;
	NSString *password;
	NSString *passphrase;
	NSString *configName;
	KeyChain *keyChainManager;
}
-(id) initWithConfigName:(NSString *)inConfigName;
-(void)deletePassphraseFromKeychain;
-(void)performAuthentication;
-(void)performPasswordAuthentication;
-(void)performPrivateKeyAuthentication;
-(NSString *)authenticate:(id)keyChainManager;
-(NSArray *)getAuth;
- (NSString *)authMode;
- (void)setAuthMode:(NSString *)value;
- (NSString *)username;
- (void)setUsername:(NSString *)value;

- (NSString *)username;
- (void)setUsername:(NSString *)value;

- (NSString *)password;
- (void)setPassword:(NSString *)value;

- (NSString *)passphrase;
- (void)setPassphrase:(NSString *)value;

- (NSString *)configName;
- (void)setConfigName:(NSString *)value;




@end
