
//  NetSocket
//  NetSocket.m
//  Version 0.9
//  Created by Dustin Mierau

#import "NetSocket.h"

#import <arpa/inet.h>
#import <fcntl.h>
#import <netdb.h>
#import <sys/socket.h>
#import <sys/time.h>
#import <sys/ioctl.h>
#import <unistd.h>

#import "NSTimer+TB.h"

static void _cfsocketCallback( CFSocketRef inCFSocketRef, CFSocketCallBackType inType, CFDataRef inAddress, const void* inData, void* inContext );

#pragma mark -

@interface NetSocket (Private)
- (id)initWithNativeSocket:(int)inNativeSocket;
- (void)unscheduleFromRunLoop;;
- (void)_cfsocketCreateForNative:(CFSocketNativeHandle)inNativeSocket;
- (BOOL)_cfsocketCreated;
- (void)_cfsocketConnected;
- (void)_cfsocketDisconnected;
- (void)_cfsocketNewConnection;
- (void)_cfsocketDataAvailable;
- (void)_cfsocketWritable;
- (void)_socketConnectionTimedOut:(NSTimer*)inTimer;
- (NetSocket*)_socketAcceptConnection;
- (void)_socketReadData;
- (void)_socketWriteData;
- (BOOL)_socketIsWritable;
- (int)_socketReadableByteCount;
- (void)_scheduleConnectionTimeoutTimer:(NSTimeInterval)inTimeout;
- (void)_unscheduleConnectionTimeoutTimer;
@end

#pragma mark -

@implementation NetSocket

- (id)init
{
    self = [super init];
	if (  ! self  )
		return nil;
	
	// Initialize some values
	mCFSocketRef = NULL;
	mCFSocketRunLoopSourceRef = NULL;
	mDelegate = nil;
	mConnectionTimer = nil;
	mSocketConnected = NO;
	mSocketListening = NO;
	mOutgoingBuffer = nil;
	mIncomingBuffer = [[NSMutableData alloc] init];
	
	return self;
}

- (id)initWithNativeSocket:(int)inNativeSocket
{
    self = [self init];
	if (  ! self  )
		return nil;
	
	// Create CFSocketRef based on specified native socket
	[self _cfsocketCreateForNative:inNativeSocket];
	
	// If creation of the CFSocketRef failed, we return nothing and cleanup
	if( ![self _cfsocketCreated] )
	{
		[super dealloc];
		return nil;
	}
	
	// Remember that we are a connected socket
	mSocketConnected = YES;
	
	return self;
}

- (void)dealloc
{
	// We don't want the delegate receiving anymore messages from us
	mDelegate = nil;
	
	// Unschedule connection timeout timer
	[self _unscheduleConnectionTimeoutTimer];
	
	// Unschedule socket from runloop
	[self unscheduleFromRunLoop];
	
	// Close socket if it is still open
	[self close];
	
	// Reset some values
	mSocketConnected = NO;
	mSocketListening = NO;
	
	// Release our incoming buffer
	[mIncomingBuffer release];
	mIncomingBuffer = nil;
	
	[super dealloc];
}

#pragma mark -

+ (NetSocket*)netsocket
{
	NetSocket*	netsocket;
	BOOL			success = NO;
	
	// Allocate new NetSocket
	netsocket = [[[NetSocket alloc] init] autorelease];
	
	// Attempt to open the socket and schedule it on the current runloop
	if( [netsocket open] )
		if( [netsocket scheduleOnCurrentRunLoop] )
			success = YES;
	
	// Return the new NetSocket if creation was successful
	return ( success ? netsocket : nil );
}

+ (NetSocket*)netsocketListeningOnRandomPort
{
	// Return a new netsocket listening on a random open port
	return [self netsocketListeningOnPort:0];
}

+ (NetSocket*)netsocketListeningOnPort:(UInt16)inPort
{
	NetSocket*	netsocket;
	BOOL			success = NO;
	
	// Create a new NetSocket
	netsocket = [self netsocket];
	
	// Set the NetSocket to listen on the specified port
	if( [netsocket listenOnPort:inPort] )
		success = YES;
	
	// Return the new NetSocket if everything went alright
	return ( success ? netsocket : nil );
}

+ (NetSocket*)netsocketConnectedToHost:(NSString*)inHostname port:(UInt16)inPort
{
	NetSocket*	netsocket;
	BOOL			success = NO;
	
	// Create a new NetSocket
	netsocket = [self netsocket];
	
	// Attempt to connect to the specified host on the specified port
	if( [netsocket connectToHost:inHostname port:inPort] )
		success = YES;
	
	// Return the new NetSocket if everything went alright
	return ( success ? netsocket : nil );
}

#pragma mark -

- (id)delegate
{
	return mDelegate;
}

- (void)setDelegate:(id)inDelegate
{
	// Set the delegate to the specified delegate
	mDelegate = inDelegate;
}

#pragma mark -

- (BOOL)open
{
	// If the CFSocketRef has not been allocated, try and do so now
	if( ![self _cfsocketCreated] )
	{
		int nativeSocket;
		
		// Create native socket
		nativeSocket = socket( AF_INET, SOCK_STREAM, 0 );
		if( nativeSocket < 0 )
			return NO;
	
		// Create CFSocketRef based on new native socket
		[self _cfsocketCreateForNative:nativeSocket];
	}
		
	// Return whether or not the CFSocket was successfully created
	return [self _cfsocketCreated];
}

- (void)close
{
	CFSocketNativeHandle	nativeSocket;
	
	// Unschedule from runloop
	[self unscheduleFromRunLoop];
	
	// If the CFSocket was created, destroy it
	if( [self _cfsocketCreated] )
	{
		// Get native socket descriptor
		nativeSocket = [self nativeSocketHandle];
		
		// Close socket descriptor
		if( nativeSocket > -1 )
			close( nativeSocket );
		
		// Invalidate the CFSocketRef
		CFSocketInvalidate( mCFSocketRef );
		
		// Release the CFSocketRef and reset our reference to it
		CFRelease( mCFSocketRef );
		mCFSocketRef = NULL;
	}
	
	// Remember that we are no longer connected
	mSocketConnected = NO;
	
	// Remember that we are no longer listening
	mSocketListening = NO;
	
	// Release outgoing buffer
	[mOutgoingBuffer release];
	mOutgoingBuffer = nil;
}

#pragma mark -

- (BOOL)scheduleOnCurrentRunLoop
{
	return [self scheduleOnRunLoop:[NSRunLoop currentRunLoop]];
}

- (BOOL)scheduleOnRunLoop:(NSRunLoop*)inRunLoop
{
	CFRunLoopRef runloop;
	
	// If our CFSocketRef has not been created or we have already been scheduled in a runloop, return
	if( ![self _cfsocketCreated] || mCFSocketRunLoopSourceRef )
		return NO;
	
	// Remove ourselves from any other runloop we might be apart of
	[self unscheduleFromRunLoop];
	
	// Get specified CFRunLoop
	runloop = [inRunLoop getCFRunLoop];
	if( !runloop )
		return NO;
	
	// Create a CFRunLoopSource for our CFSocketRef
	mCFSocketRunLoopSourceRef = CFSocketCreateRunLoopSource( kCFAllocatorDefault, mCFSocketRef, 0 );
	if( !mCFSocketRunLoopSourceRef )
		return NO;
	
	// Finally schedule our runloop source with the specified CFRunLoop
	CFRunLoopAddSource( runloop, mCFSocketRunLoopSourceRef, kCFRunLoopDefaultMode );
	
	return YES;
}

- (void)unscheduleFromRunLoop
{
	// If our CFSocketRef has not been created than it probably hasn't been scheduled yet
	if( ![self _cfsocketCreated] || mCFSocketRunLoopSourceRef == NULL )
		return;
	
	// If the runloop source is not valid, return
	if( !CFRunLoopSourceIsValid( mCFSocketRunLoopSourceRef ) )
		return;
	
	// Invalidate and release the runloop source
	CFRunLoopSourceInvalidate( mCFSocketRunLoopSourceRef );
	CFRelease( mCFSocketRunLoopSourceRef );
	
	// Reset our reference to the runloop source
	mCFSocketRunLoopSourceRef = NULL;
}

#pragma mark -

- (BOOL)listenOnRandomPort
{
	return [self listenOnPort:0 maxPendingConnections:5];
}

- (BOOL)listenOnPort:(UInt16)inPort
{
	return [self listenOnPort:inPort maxPendingConnections:5];
}

- (BOOL)listenOnPort:(UInt16)inPort maxPendingConnections:(int)inMaxPendingConnections
{
	CFSocketNativeHandle	nativeSocket;
	struct sockaddr_in	socketAddress;
	int						socketOptionFlag;
	int						result;
	
	// If the CFSocket was never created, is connected to another host or is already listening, we cannot use it
	if( ![self _cfsocketCreated] || [self isConnected] || [self isListening] )
		return NO;
	
	// Get native socket descriptor
	nativeSocket = [self nativeSocketHandle];
	if( nativeSocket < 0 )
		return NO;
	
	// Set this socket option so we can reuse the address immediately
	socketOptionFlag = 1;
	result = setsockopt( nativeSocket, SOL_SOCKET, SO_REUSEADDR, &socketOptionFlag, sizeof( socketOptionFlag ) );
	if( result < 0 )
		return NO;
	
	// Setup socket address
	bzero( &socketAddress, sizeof( socketAddress ) );
	socketAddress.sin_family = PF_INET;
	socketAddress.sin_addr.s_addr = htonl( INADDR_ANY );
	socketAddress.sin_port = htons( inPort );
	
	// Bind socket to the specified port
	result = bind( nativeSocket, (struct sockaddr*)&socketAddress, sizeof( socketAddress ) );
	if( result < 0 )
		return NO;
	
	// Start the socket listening on the specified port
	result = listen( nativeSocket, inMaxPendingConnections );
	if( result < 0 )
		return NO;
	
	// Note that we are actually listening now
	mSocketListening = YES;
	
	return YES;
}

#pragma mark -

- (BOOL)connectToHost:(NSString*)inHostname port:(UInt16)inPort
{
	return [self connectToHost:inHostname port:inPort timeout:-1.0];
}

- (BOOL)connectToHost:(NSString*)inHostname port:(UInt16)inPort timeout:(NSTimeInterval)inTimeout
{
	struct hostent*		socketHost;
	struct sockaddr_in	socketAddress;
	NSData*					socketAddressData;
	CFSocketError			socketError;
	
	// If the CFSocket was never created, is connected to another host or is already listening, we cannot use it
	if( ![self _cfsocketCreated] || [self isConnected] || [self isListening] )
		return NO;

	// Get host information
	socketHost = gethostbyname( [inHostname UTF8String] );
	if( !socketHost )
		return NO;
	
	// Setup socket address
	bzero( &socketAddress, sizeof( socketAddress ) );

	// The pointer socketHost->h_addr is not aligned, so create an aligned pointer and use it.
	char * ptr_to_hw_addr;
	memcpy( &ptr_to_hw_addr, (char*)&(socketHost->h_addr), sizeof(char*));

	// Copy h_addr to sin_addr
	memcpy( &socketAddress.sin_addr, ptr_to_hw_addr, (unsigned) socketHost->h_length);

	socketAddress.sin_family = PF_INET;
	socketAddress.sin_port = htons( inPort );
	
	// Enclose socket address in an NSData object
	socketAddressData = [NSData dataWithBytes:(void*)&socketAddress length:sizeof( socketAddress )];
	
	// Attempt to connect our CFSocketRef to the specified host
	socketError = CFSocketConnectToAddress( mCFSocketRef, (CFDataRef)socketAddressData, -1.0 );
	if( socketError != kCFSocketSuccess )
		return NO;
	
	// Schedule our timeout timer if the timeout is greater than zero
	if( inTimeout >= 0.0 )
		[self _scheduleConnectionTimeoutTimer:inTimeout];
	
	// Remove any data left in our outgoing buffer
	[mIncomingBuffer setLength:0];
	
	return YES;
}

#pragma mark -

- (NSData*)peekData
{
	return mIncomingBuffer;
}

#pragma mark -

- (unsigned)read:(void*)inBuffer amount:(unsigned)inAmount
{
	unsigned amountToRead;
	
	// If there is no data to read, simply return
	if( [mIncomingBuffer length] == 0 )
		return 0;
	
	// Determine how much to actually read
	amountToRead = MIN( inAmount, [mIncomingBuffer length] );
	
	// Read bytes from our incoming buffer
	if (inBuffer) [mIncomingBuffer getBytes:inBuffer length:amountToRead];
	[mIncomingBuffer replaceBytesInRange:NSMakeRange( 0, amountToRead ) withBytes:NULL length:0];
	
	return amountToRead;
}

- (unsigned)readOntoData:(NSMutableData*)inData
{
	unsigned amountRead;
	
	// If there is no data to read, simply return
	if( [mIncomingBuffer length] == 0 )
		return 0;
	
	// Remember the length of our incoming buffer
	amountRead = [mIncomingBuffer length];
	
	// Read bytes from our incoming buffer
	[inData appendData:mIncomingBuffer];
	
	// Empty out our incoming buffer as we have read it all
	[mIncomingBuffer setLength:0];
	
	return amountRead;
}

- (unsigned)readOntoData:(NSMutableData*)inData amount:(unsigned)inAmount
{
	unsigned amountToRead;
	
	// If there is no data to read, simply return
	if( [mIncomingBuffer length] == 0 )
		return 0;
	
	// Determine how much to actually read
	amountToRead = MIN( inAmount, [mIncomingBuffer length] );
	
	// Read bytes from our incoming buffer
	[inData appendBytes:[mIncomingBuffer bytes] length:amountToRead];
	[mIncomingBuffer replaceBytesInRange:NSMakeRange( 0, amountToRead ) withBytes:NULL length:0];
	
	return amountToRead;
}

- (unsigned)readOntoString:(NSMutableString*)inString encoding:(NSStringEncoding)inEncoding amount:(unsigned)inAmount
{
	NSData*		readData;
	NSString*	readString;
	unsigned		amountToRead;
	
	// If there is no data to read, simply return
	if( [mIncomingBuffer length] == 0 )
		return 0;
	
	// Determine how much to actually read
	amountToRead = MIN( inAmount, [mIncomingBuffer length] );
	
	// Reference our incoming buffer, we cut down some overhead when the requested amount is the same length as our incoming buffer
	if( amountToRead == [mIncomingBuffer length] )
		readData = [mIncomingBuffer retain];
	else
		readData = [[NSData alloc] initWithBytesNoCopy:(void*)[mIncomingBuffer bytes] length:amountToRead freeWhenDone:NO];
	
	// If for some reason we could not create the data object, return
	if( !readData )
		return 0;
	
	// Create an NSString from the read data using the specified string encoding
	readString = [[NSString alloc] initWithData:readData encoding:inEncoding];
	if( readString )
	{
		// Read bytes from our incoming buffer
		[mIncomingBuffer replaceBytesInRange:NSMakeRange( 0, amountToRead ) withBytes:NULL length:0];
		
		// Append created string
		[inString appendString:readString];
		
		// Release the NSString we created
		[readString release];
	}
	
	// Release our buffer
	[readData release];
	
	return amountToRead;
}

- (NSData*)readData
{
	NSData* readData;
	
	// If there is no data to read, simply return
	if( [mIncomingBuffer length] == 0 )
		return nil;
	
	// Create new data object with contents of our incoming buffer
	readData = [NSData dataWithData:mIncomingBuffer];
	if( !readData )
		return nil;
	
	// Size our incoming data buffer as we have now read it all
	[mIncomingBuffer setLength:0];
	
	return readData;
}

- (NSData*)readData:(unsigned)inAmount
{
	NSData*	readData;
	unsigned	amountToRead;
	
	// If there is no data to read, simply return
	if( [mIncomingBuffer length] == 0 )
		return nil;
	
	// Determine how much to actually read
	amountToRead = MIN( inAmount, [mIncomingBuffer length] );
	
	// Read bytes from our incoming buffer
	readData = [NSData dataWithBytes:[mIncomingBuffer bytes] length:amountToRead];
	if( !readData )
		return nil;
	
	// Read bytes from our incoming buffer
	[mIncomingBuffer replaceBytesInRange:NSMakeRange( 0, amountToRead ) withBytes:NULL length:0];
	
	return readData;
}

- (NSString*)readString:(NSStringEncoding)inEncoding
{
	NSString* readString;
	
	// If there is no data to read, simply return
	if( [mIncomingBuffer length] == 0 )
		return nil;
	
	// Read bytes from our incoming buffer
	readString = [[[NSString alloc] initWithData:mIncomingBuffer encoding:inEncoding] autorelease];
	if( !readString )
		return nil;
	
	// Size our incoming data buffer as we have now read it all
	[mIncomingBuffer setLength:0];
	
	return readString;
}

- (NSString*)readString:(NSStringEncoding)inEncoding amount:(unsigned)inAmount
{
	NSString*	readString;
	NSData*		readData;
	unsigned		amountToRead;
	
	// If there is no data to read, simply return
	if( [mIncomingBuffer length] == 0 )
		return nil;
	
	// Determine how much to actually read
	amountToRead = MIN( inAmount, [mIncomingBuffer length] );
	
	// Reference our incoming buffer, we cut down some overhead when the requested amount is the same length as our incoming buffer
	if( amountToRead == [mIncomingBuffer length] )
		readData = [mIncomingBuffer retain];
	else
		readData = [[NSData alloc] initWithBytesNoCopy:(void*)[mIncomingBuffer bytes] length:amountToRead freeWhenDone:NO];
	
	// If for some reason we could not create the data object, return
	if( !readData )
		return nil;
	
	// Create a new NSString from the read bytes using the specified encoding
	readString = [[[NSString alloc] initWithData:readData encoding:inEncoding] autorelease];
	if( readString )
	{
		// Read bytes from our incoming buffer
		[mIncomingBuffer replaceBytesInRange:NSMakeRange( 0, amountToRead ) withBytes:NULL length:0];
	}
	
	// Release our buffer
	[readData release];
	
	return readString;
}

#pragma mark -

- (void)write:(const void*)inBytes length:(unsigned)inLength
{
	// Return if there are no bytes to write
	if( inLength == 0 )
		return;
		
	// If the socket is not connected, simply return
	if( ![self isConnected] )
		return;
	
	// Create or re-create an outgoing buffer of the correct length for this data.
	if( mOutgoingBuffer )
        [mOutgoingBuffer release];
    mOutgoingBuffer = [[NSMutableData alloc] initWithCapacity:inLength];
	
	// Append specified bytes to our outgoing buffer
	[mOutgoingBuffer appendBytes:inBytes length:inLength];
	
	// Attempt to write the data to the socket
	[self _socketWriteData];
}

- (void)writeData:(NSData*)inData
{
	[self write:[inData bytes] length:[inData length]];
}

- (void)writeString:(NSString*)inString encoding:(NSStringEncoding)inEncoding
{
	[self writeData:[inString dataUsingEncoding:inEncoding]];
}

#pragma mark -

- (NSString*)remoteHost
{
	CFSocketNativeHandle	nativeSocket;
	struct sockaddr_in	address;
	socklen_t				addressLength = sizeof( address );
	
	// Get the native socket
	nativeSocket = [self nativeSocketHandle];
	if( nativeSocket < 0 )
		return nil;
	
	// Get peer name information
	if( getpeername( nativeSocket, (struct sockaddr*)&address, &addressLength ) < 0 )
		return nil;
	
	// Return string representation of the remote hostname
	return [NetSocket stringWithSocketAddress:&address.sin_addr];
}

- (UInt16)remotePort
{
	CFSocketNativeHandle	nativeSocket;
	struct sockaddr_in	address;
	socklen_t					addressLength = sizeof( address );
	
	// Get the native socket
	nativeSocket = [self nativeSocketHandle];
	if( nativeSocket < 0 )
		return 0;
	
	// Get peer name information
	if( getpeername( nativeSocket, (struct sockaddr*)&address, &addressLength ) < 0 )
		return 0;
	
	// Return remote port
	return ntohs( address.sin_port );
}

- (NSString*)localHost
{
	CFSocketNativeHandle	nativeSocket;
	struct sockaddr_in	address;
	socklen_t					addressLength = sizeof( address );
	
	// Get the native socket
	nativeSocket = [self nativeSocketHandle];
	if( nativeSocket < 0 )
		return nil;
	
	// Get socket name information
	if( getsockname( nativeSocket, (struct sockaddr*)&address, &addressLength ) < 0 )
		return nil;
	
	// Return string representation of the local hostname
	return [NetSocket stringWithSocketAddress:&address.sin_addr];
}

- (UInt16)localPort
{
	CFSocketNativeHandle	nativeSocket;
	struct sockaddr_in	address;
	socklen_t					addressLength = sizeof( address );
	
	// Get the native socket
	nativeSocket = [self nativeSocketHandle];
	if( nativeSocket < 0 )
		return 0;
	
	// Get socket name information
	if( getsockname( nativeSocket, (struct sockaddr*)&address, &addressLength ) < 0 )
		return 0;
	
	// Return local port
	return ntohs( address.sin_port );
}

- (BOOL)isConnected
{
	return mSocketConnected;
}

- (BOOL)isListening
{
	return mSocketListening;
}

- (unsigned)incomingBufferLength
{
	return [mIncomingBuffer length];
}

- (unsigned)outgoingBufferLength
{
	return [mOutgoingBuffer length];
}

- (CFSocketNativeHandle)nativeSocketHandle
{
	// If the CFSocketRef was never created, return an invalid handle
	if( ![self _cfsocketCreated] )
		return -1;
	
	// Return a valid native socket handle
	return CFSocketGetNative( mCFSocketRef );
}

- (CFSocketRef)cfsocketRef
{
	return mCFSocketRef;
}

#pragma mark -

+ (void)ignoreBrokenPipes
{
	// Ignore the broken pipe signal
	signal( SIGPIPE, SIG_IGN );
}

+ (NSString*)stringWithSocketAddress:(struct in_addr*)inAddress
{
	return [NSString stringWithUTF8String:inet_ntoa( *inAddress )];
}

#pragma mark -

- (void)_cfsocketCreateForNative:(CFSocketNativeHandle)inNativeSocket
{
	CFSocketContext	socketContext;
	CFOptionFlags		socketCallbacks;
	CFOptionFlags		socketOptions;
	int					socketFlags;
	BOOL					success = NO;
	
	// Create socket context
	bzero( &socketContext, sizeof( socketContext ) );
	socketContext.info = self;
	
	// Set socket callbacks
	socketCallbacks = kCFSocketConnectCallBack + kCFSocketReadCallBack + kCFSocketWriteCallBack;

	// Get the sockets flags
	socketFlags = fcntl( inNativeSocket, F_GETFL, 0 );
	if( socketFlags >= 0 )
	{
		// Put the socket into non-blocking mode
		if( fcntl( inNativeSocket, F_SETFL, socketFlags | O_NONBLOCK ) >= 0 )
		{
			// Create CFSocketRef based on native socket, if it is created...success!
			mCFSocketRef = CFSocketCreateWithNative( kCFAllocatorDefault, inNativeSocket, socketCallbacks, &_cfsocketCallback, &socketContext );
			if( mCFSocketRef )
				success = YES;
		}
	}
	
	if( !success )
	{
		close( inNativeSocket );
		return;
	}
	
	// Set socket options
	socketOptions = kCFSocketAutomaticallyReenableReadCallBack;
	CFSocketSetSocketFlags( mCFSocketRef, socketOptions );
}

- (BOOL)_cfsocketCreated
{
	return ( mCFSocketRef != NULL );
}

- (void)_cfsocketConnected
{
	// Unschedule connection timeout timer and release it if it's still running
	[self _unscheduleConnectionTimeoutTimer];
	
	// Remember that we are now connected
	mSocketConnected = YES;
	
	// Notify our delegate that the socket has connected successfully
	if( [mDelegate respondsToSelector:@selector( netsocketConnected: )] )
		[mDelegate netsocketConnected:self];
	
	// Attempt to write any data that has already been added to our outgoing buffer
	[self _socketWriteData];
}

- (void)_cfsocketDisconnected
{
	// Close socket
	[self close];
	
	// Notify our delegate that the socket has been disconnected
	if( [mDelegate respondsToSelector:@selector( netsocketDisconnected: )] )
		[mDelegate netsocketDisconnected:self];
}

- (void)_cfsocketNewConnection
{
	NetSocket* netsocket;
	
	// Accept all pending connections
	while( (netsocket = [self _socketAcceptConnection]) )
	{
		// Notify our delegate that a new connection has been accepted
		if( [mDelegate respondsToSelector:@selector( netsocket:connectionAccepted: )] )
			[mDelegate netsocket:self connectionAccepted:netsocket];
	}
}

- (void)_cfsocketDataAvailable
{
	unsigned oldIncomingBufferLength;
	
	// Store the old incoming buffer length
	oldIncomingBufferLength = [mIncomingBuffer length];
	
	// Read in available data
	[self _socketReadData];
	
	// Return if there was no data added to our incoming data buffer
	if( [mIncomingBuffer length] <= oldIncomingBufferLength )
		return;
	
	// Notify our delegate that new data is now available
	if( [mDelegate respondsToSelector:@selector( netsocket:dataAvailable: )] )
		[mDelegate netsocket:self dataAvailable:[mIncomingBuffer length]];
}

- (void)_cfsocketWritable
{
	// Attempt to write more data to the socket
	[self _socketWriteData];
}

#pragma mark -

- (void)_socketConnectionTimedOut:(NSTimer*)inTimer
{
	(void) inTimer;
	
	NSTimeInterval timeInterval;
	
	// Store the timers time interval
	timeInterval = [mConnectionTimer timeInterval];
	
	// Unschedule the timeout timer and release it
	[self _unscheduleConnectionTimeoutTimer];
	
	// Notify our delegate that our attempt to connect to the specified remote host failed
	if( [mDelegate respondsToSelector:@selector( netsocket:connectionTimedOut: )] )
		[mDelegate netsocket:self connectionTimedOut:timeInterval];
}

- (NetSocket*)_socketAcceptConnection
{
	CFSocketNativeHandle	nativeSocket;
	struct sockaddr_in	socketAddress;
	NetSocket*				netsocket;
	socklen_t				socketAddressSize;
	int						socketDescriptor;
	
	// Get the native socket
	nativeSocket = [self nativeSocketHandle];
	if( nativeSocket < 0 )
		return nil;
	
	// Accept pending connection
	socketAddressSize = sizeof( socketAddress );
	socketDescriptor = accept( nativeSocket, (struct sockaddr*)&socketAddress, &socketAddressSize );
	if( socketDescriptor < 0 )
		return nil;
	
	// Create a new NetSocket object based on the accepted connection
	netsocket = [[[NetSocket alloc] initWithNativeSocket:socketDescriptor] autorelease];
	
	// If creating the NetSocket object failed, let's close the connection and never speak of this to anyone
	if( !netsocket )
		close( socketDescriptor );
	
	// Return NetSocket based on accepted connection
	return netsocket;
}

- (void)_socketReadData
{
	CFSocketNativeHandle	nativeSocket;
	void*						readBuffer;
	int						amountAvailable;
	int						amountRead;
	
	// Determine how many bytes are available on the socket to read
	amountAvailable = [self _socketReadableByteCount];
	if( amountAvailable < 0 )
		return;
	
	// Get the native socket
	nativeSocket = [self nativeSocketHandle];
	if( nativeSocket < 0 )
		return;
	
	// Create read buffer
	readBuffer = malloc( ( amountAvailable == 0 ) ? 1u : (unsigned) amountAvailable );
	if( !readBuffer )
		return;
	
	// Attempt to read the available data
	amountRead = read( nativeSocket, readBuffer, ( amountAvailable == 0 ) ? 1u : (unsigned) amountAvailable );
	if( amountRead > 0 )
	{
		// Append data to our incoming buffer
		[mIncomingBuffer appendBytes:readBuffer length: (unsigned) amountRead];
	}
	else
	if( amountRead == 0 )
	{
		// We have been disconnected
		[self _cfsocketDisconnected];
	}
	else
	if( amountRead < 0 )
	{
		if( errno != EAGAIN )
			[self _cfsocketDisconnected];
	}
	
	// Free our read buffer
	free( readBuffer );
}

- (void)_socketWriteData
{
	CFSocketNativeHandle	nativeSocket;
	ssize_t                  amountSent;
	
	// Return if our CFSocketRef has not been created, the outgoing buffer has no data in it or we are simply not connected
	if( ![self _cfsocketCreated] || [mOutgoingBuffer length] == 0 || ![self isConnected] )
		return;
	
	// Get the native socket
	nativeSocket = [self nativeSocketHandle];
	if( nativeSocket < 0 )
		return;
	
	// Send all we can
	amountSent = write( nativeSocket, [mOutgoingBuffer bytes], [mOutgoingBuffer length] );
	if( amountSent == (ssize_t)[mOutgoingBuffer length] )
	{
		// We managed to write the entire outgoing buffer to the socket
		// Disable the write callback for now since we know we are writable
		CFSocketDisableCallBacks( mCFSocketRef, kCFSocketWriteCallBack );
	}
	else
	if( amountSent != (ssize_t) -1 )
	{
		// We managed to write some of our buffer to the socket
		// Enable the write callback on our CFSocketRef so we know when the socket is writable again
		CFSocketEnableCallBacks( mCFSocketRef, kCFSocketWriteCallBack );
	}
	else
	if( errno == EWOULDBLOCK )
	{
		// No data has actually been written here
		amountSent = 0;
		
		// Enable the write callback on our CFSocketRef so we know when the socket is writable again
		CFSocketEnableCallBacks( mCFSocketRef, kCFSocketWriteCallBack );
	}
	else
	{
		// Disable the write callback
		CFSocketDisableCallBacks( mCFSocketRef, kCFSocketWriteCallBack );
		
		// Note that we have been disconnected
		[self _cfsocketDisconnected];
		return;
	}
	
	// Remove the data we managed to write to the socket 
	[mOutgoingBuffer replaceBytesInRange:NSMakeRange( 0, (unsigned)amountSent ) withBytes:NULL length:0];
	
	// If our outgoing buffer is empty, notify our delegate
	if( [mOutgoingBuffer length] == 0 )
		if( [mDelegate respondsToSelector:@selector( netsocketDataSent: )] )
			[mDelegate netsocketDataSent:self];
}

- (BOOL)_socketIsWritable
{
	CFSocketNativeHandle	nativeSocket;
	struct timeval			timeout;
	fd_set					writableSet;
	int						socketCount;
	
	// Get the native socket
	nativeSocket = [self nativeSocketHandle];
	if( nativeSocket < 0 )
		return NO;
	
	// Create a socket descriptor set to check against
	FD_ZERO( &writableSet );
	FD_SET( nativeSocket, &writableSet );
	
	// Create a timeout so select does not block
	timeout.tv_sec = 0;
	timeout.tv_usec = 0;
	
	// Check socket descriptor for data
	socketCount = select( nativeSocket + 1, NULL, &writableSet, NULL, &timeout );
	if( socketCount < 0 )
		return NO;
	
	return ( socketCount == 1 );
}

- (int)_socketReadableByteCount
{
	CFSocketNativeHandle	nativeHandle;
	int						bytesAvailable;
	
	// Get native socket
	nativeHandle = [self nativeSocketHandle];
	if( nativeHandle < 0 )
		return 0;
	
	// Determine how many bytes are available on the socket
	if( ioctl( nativeHandle, FIONREAD, &bytesAvailable ) == -1 )
	{
		if( errno == EINVAL )
			bytesAvailable = -1;
		else
			bytesAvailable = 0;
	}
	
	return bytesAvailable;
}

#pragma mark -

- (void)_scheduleConnectionTimeoutTimer:(NSTimeInterval)inTimeout
{
	// Schedule our timeout timer
	mConnectionTimer = [[NSTimer scheduledTimerWithTimeInterval:inTimeout target:self selector:@selector( _socketConnectionTimedOut: ) userInfo:nil repeats:NO] retain];
    [mConnectionTimer tbSetTolerance: -1.0];

}

- (void)_unscheduleConnectionTimeoutTimer
{
	// Remove timer from its runloop
	[mConnectionTimer invalidate];
	
	// Release the timer and reset our reference to it
	[mConnectionTimer release];
	mConnectionTimer = nil;
}

@end

#pragma mark -

void 
_cfsocketCallback( CFSocketRef inCFSocketRef, CFSocketCallBackType inType, CFDataRef inAddress, const void* inData, void* inContext )
{
    (void) inCFSocketRef;
    (void) inAddress;
    
	NetSocket*	netsocket;
	
	netsocket = (NetSocket*)inContext;
	if( !netsocket )
		return;
	
	switch( inType )
	{
		case kCFSocketConnectCallBack:
			// Notify NetSocket that we connected successfully
			if(!inData) [netsocket _cfsocketConnected];
			break;
		
		case kCFSocketReadCallBack:
			{
				// If the CFSocketRef is in a listening state, we have a new connection. If not, data is available on the socket.
				if( [netsocket isListening] )
					[netsocket _cfsocketNewConnection];
				else
					[netsocket _cfsocketDataAvailable];
			}
			break;
		
		case kCFSocketWriteCallBack:
			// Notify the NetSocket object that its CFSocketRef is writable again
			[netsocket _cfsocketWritable];
			break;
		
		default:
			// Unknow CFSocketCallBackType
			break;
	}
}
