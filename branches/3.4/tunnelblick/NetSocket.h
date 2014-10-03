
//  NetSocket
//  NetSocket.h
//  Version 0.9
//  Created by Dustin Mierau

#import <Foundation/Foundation.h>
#import <netinet/in.h>

@interface NetSocket : NSObject 
{
	CFSocketRef				mCFSocketRef;
	CFRunLoopSourceRef	mCFSocketRunLoopSourceRef;
	id							mDelegate;
	NSTimer*					mConnectionTimer;
	BOOL						mSocketConnected;
	BOOL						mSocketListening;
	NSMutableData*			mOutgoingBuffer;
	NSMutableData*			mIncomingBuffer;
}

// Creation
+ (NetSocket*)netsocket;
+ (NetSocket*)netsocketListeningOnRandomPort;
+ (NetSocket*)netsocketListeningOnPort:(UInt16)inPort;
+ (NetSocket*)netsocketConnectedToHost:(NSString*)inHostname port:(UInt16)inPort;

// Delegate
- (id)delegate;
- (void)setDelegate:(id)inDelegate;

// Opening and Closing
- (BOOL)open;
- (void)close;

// Runloop Scheduling
- (BOOL)scheduleOnCurrentRunLoop;
- (BOOL)scheduleOnRunLoop:(NSRunLoop*)inRunLoop;

// Listening
- (BOOL)listenOnRandomPort;
- (BOOL)listenOnPort:(UInt16)inPort;
- (BOOL)listenOnPort:(UInt16)inPort maxPendingConnections:(int)inMaxPendingConnections;

// Connecting
- (BOOL)connectToHost:(NSString*)inHostname port:(UInt16)inPort;
- (BOOL)connectToHost:(NSString*)inHostname port:(UInt16)inPort timeout:(NSTimeInterval)inTimeout;

// Peeking
- (NSData*)peekData;

// Reading
- (unsigned)read:(void*)inBuffer amount:(unsigned)inAmount;
- (unsigned)readOntoData:(NSMutableData*)inData;
- (unsigned)readOntoData:(NSMutableData*)inData amount:(unsigned)inAmount;
- (unsigned)readOntoString:(NSMutableString*)inString encoding:(NSStringEncoding)inEncoding amount:(unsigned)inAmount;
- (NSData*)readData;
- (NSData*)readData:(unsigned)inAmount;
- (NSString*)readString:(NSStringEncoding)inEncoding;
- (NSString*)readString:(NSStringEncoding)inEncoding amount:(unsigned)inAmount;

// Writing
- (void)write:(const void*)inBytes length:(unsigned)inLength;
- (void)writeData:(NSData*)inData;
- (void)writeString:(NSString*)inString encoding:(NSStringEncoding)inEncoding;

// Properties
- (NSString*)remoteHost;
- (UInt16)remotePort;
- (NSString*)localHost;
- (UInt16)localPort;
- (BOOL)isConnected;
- (BOOL)isListening;
- (unsigned)incomingBufferLength;
- (unsigned)outgoingBufferLength;
- (CFSocketNativeHandle)nativeSocketHandle;
- (CFSocketRef)cfsocketRef;

// Convenience methods
+ (void)ignoreBrokenPipes;
+ (NSString*)stringWithSocketAddress:(struct in_addr*)inAddress;

@end

#pragma mark -

@interface NSObject (NetSocketDelegate)
- (void)netsocketConnected:(NetSocket*)inNetSocket;
- (void)netsocket:(NetSocket*)inNetSocket connectionTimedOut:(NSTimeInterval)inTimeout;
- (void)netsocketDisconnected:(NetSocket*)inNetSocket;
- (void)netsocket:(NetSocket*)inNetSocket connectionAccepted:(NetSocket*)inNewNetSocket;
- (void)netsocket:(NetSocket*)inNetSocket dataAvailable:(unsigned)inAmount;
- (void)netsocketDataSent:(NetSocket*)inNetSocket;
@end
