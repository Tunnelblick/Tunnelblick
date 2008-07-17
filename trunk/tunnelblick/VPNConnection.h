//
//  VPNConnection.h
//  Tunnelblick
//
//  Created by Angelo Laub on 6/4/05.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>
#import <CoreServices/CoreServices.h>
#import "KeyChain.h"
#import "NetSocket.h"
#import <signal.h>
#import "NSApplication+LoginItem.h"
#import <Foundation/NSDebug.h>
#import "AuthAgent.h"

@interface VPNConnection : NSObject {
	NSString *configPath;
	unsigned int portNumber;
	NetSocket *managementSocket;
//	LogController *myLogController;
	NSString* lastState;
	NSDate *connectedSinceDate;
	NSMenu *myMenu;
	
        NSTextStorage* logStorage;
        id delegate;
		AuthAgent *myAuthAgent;
}

-(id) initWithConfig:(NSString *)inConfig;

- (void) setManagementSocket: (NetSocket*) socket;
- (IBAction) connect: (id) sender;
//- (IBAction) viewLog: (id) sender;
- (NSTextStorage*) logStorage;
- (void) setDelegate: (id) newDelegate;
- (NSString*) state;

- (void) connectToManagementSocket;
- (IBAction) disconnect: (id) sender;
- (IBAction) toggle: (id) sender;
-(BOOL) isDisconnected ;

- (void) netsocketConnected: (NetSocket*) socket;
- (void) processLine: (NSString*) line;
- (void) netsocket: (NetSocket*) socket dataAvailable: (unsigned) inAmount;
- (void) netsocketDisconnected: (NetSocket*) inSocket;
- (void) setState: (NSString*) newState;
-(void)addToLog:(NSString *)text atDate:(NSCalendarDate *)date;
-(void)setMenu:(NSMenu *)inMenu;
- (NSString*) configPath;
- (NSString*) configName;
- (NSDate *)connectedSinceDate;
- (void)setConnectedSinceDate:(NSDate *)value;





//- (IBAction) updateUI;

- (unsigned int) getFreePort;

@end
