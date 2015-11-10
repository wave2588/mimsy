#import "MimsyEndpoint.h"

#import <CoreFoundation/CoreFoundation.h>
#include <sys/fcntl.h>
#include <sys/socket.h>
#include <netinet/tcp.h>
#include <netinet/in.h>
#import "Logger.h"

const int port = 5331;

static CFSocketRef _acceptSocket;

// -----------------------------------------------------------------------------------------------------------
@interface ExtensionConnection : NSObject

- (id)initWithInputStream:(NSInputStream*)inputStream outputStream:(NSOutputStream*)outputStream;

- (void)open;
- (void)close;

@property (readonly) NSString* name;

@end

@interface ExtensionConnection () <NSStreamDelegate>
@end

// -----------------------------------------------------------------------------------------------------------
static NSMutableArray* _extensions;

@implementation ExtensionConnection
{
    NSInputStream* _inputStream;
    NSOutputStream* _outputStream;
    bool _needsReply;
    bool _canReply;
}

- (id)initWithInputStream:(NSInputStream*)inputStream outputStream:(NSOutputStream*)outputStream
{
    if (!_extensions)
        _extensions = [NSMutableArray new];
    
    self = [super init];
    if (self != nil)
    {
        _inputStream = inputStream;
        _outputStream = outputStream;
        _name = @"";
    }
    return self;
}

- (void)open
{
    LOG("Extensions", "Opened connection to extension");
    [_inputStream  setDelegate:self];
    [_outputStream setDelegate:self];
    [_inputStream  scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_inputStream  open];
    [_outputStream open];
    [_extensions addObject:self];
}

- (void)close
{
    [_inputStream  setDelegate:nil];
    [_outputStream setDelegate:nil];
    [_inputStream  close];
    [_outputStream close];
    [_inputStream  removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    LOG("Extensions", "Closed connection to %s extension", STR(_name));
    [_extensions removeObject:self];
}

- (void)stream:(NSStream*)stream handleEvent:(NSStreamEvent)event
{
    if (event == NSStreamEventEndEncountered)
    {
        LOG("Extensions", "EOF for %s extension connection", STR(_name));
        [self close];
    }
    else if (event == NSStreamEventErrorOccurred)
    {
        NSString* reason = [[_outputStream streamError] localizedFailureReason];
        LOG("Error", "Error for %s extension connection: %s", STR(_name), STR(reason));
        [self close];
    }
    else if (stream == _inputStream && event == NSStreamEventHasBytesAvailable)
    {
        NSString* message = [self _read];
        if (message)
        {
            if (_canReply)
            {
                const char* reply = "OK\n";
                [self _write:reply bytes:strlen(reply)];
            }
            else
            {
                _needsReply = true;
            }
        }
    }
    else if (stream == _outputStream && event == NSStreamEventHasSpaceAvailable)
    {
        // This is pretty dorky: we're using loopback so you'd think we could just send replies without
        // worrying about blocking (especially if we make the socket non-blocking). But this doesn't
        // work, probably because NSOutputStream is trying to be helpful. To make matters worse we
        // only get the NSStreamEventHasSpaceAvailable once which means we need that lame _canReply
        // flag.
        if (_needsReply)
        {
            const char* reply = "OK\n";
            [self _write:reply bytes:strlen(reply)];

            _needsReply = false;
        }
        else
        {
            _canReply = true;
        }
    }
}

- (NSString*)_read
{
    NSString* message = nil;
    
    uint32_t bytesToRead;
    if ([self _primitiveRead:&bytesToRead bytes:sizeof(bytesToRead)])
    {
        bytesToRead = ntohl(bytesToRead);
        
        char* payload = malloc(bytesToRead+1);
        if (payload)
        {
            if ([self _primitiveRead:payload bytes:bytesToRead])
            {
                payload[bytesToRead] = '\0';
                
                message = [NSString stringWithCString:payload encoding:NSUTF8StringEncoding];
                if (bytesToRead < 256)
                    LOG("Extensions", "received '%s' from %s endpoint", STR(message), STR(_name));
                else
                    LOG("Extensions", "received '%s...%s' from %s endpoint", STR([message substringToIndex:60]), STR([message substringFromIndex:bytesToRead-60]), STR(_name));
            }
            else
            {
                LOG("Error", "Failed to read %d byte payload for %s extension connection", bytesToRead, STR(_name));
            }
            free(payload);
        }
        else
        {
            LOG("Error", "Failed to allocate %d byte payload for %s extension connection", bytesToRead, STR(_name));
            [self close];
        }
    }
    else
    {
        LOG("Error", "Failed to read payload size for %s extension connection", STR(_name));
    }
    
    return message;
}

- (bool)_write:(const void*)buffer bytes:(NSUInteger)bytes
{
    uint32_t bytesToWrite = htonl(bytes);
    return [self _primitiveWrite:&bytesToWrite bytes:sizeof(bytesToWrite)] && [self _primitiveWrite:buffer bytes:bytes];
}

- (bool)_primitiveRead:(void*)buffer bytes:(NSUInteger)bytes
{
    NSInteger bytesRead = 0;
    
    while (_inputStream.hasBytesAvailable && bytesRead < bytes)
    {
        // If there was an error we'll wait for NSStreamEventEndEncountered or NSStreamEventErrorOccurred
        // to come around.
        bytesRead += [_inputStream read:(uint8_t*) (buffer + bytesRead) maxLength:bytes - (NSUInteger) bytesRead];
    }
    
    return bytesRead == bytes;
}

- (bool)_primitiveWrite:(const void*)buffer bytes:(NSUInteger)bytes
{
    NSInteger bytesWritten = [_outputStream write:buffer maxLength:bytes];
    if (bytesWritten < 0)
    {
        NSString* reason = [[_outputStream streamError] localizedFailureReason];
        LOG("Error", "There was an error sending to the %s extension: %s", STR(_name), STR(reason));
        [self close];
    }
    else if (bytesWritten < bytes)
    {
        // Should only happen if the extension stops reading data and the send buffer
        // fills up.
        LOG("Error", "Sent %ld instead of %lu bytes to %s extension", (long)bytesWritten, (unsigned long)bytes, STR(_name));
        [self close];
    }
    
    return bytesWritten == bytes;
}
@end

// -----------------------------------------------------------------------------------------------------------
static void acceptCallback(CFSocketRef socket, CFSocketCallBackType callbackType, CFDataRef address, const void *data, void *info)
{
    UNUSED(socket, callbackType, address, info);
    
    CFSocketNativeHandle socketH = *(CFSocketNativeHandle*)data;
    
    const int yes = 1;
    (void) setsockopt(socketH, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof(yes));
    
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocket(kCFAllocatorDefault, socketH, &readStream, &writeStream);
    if (readStream && writeStream)
    {
        CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
        CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
        
        ExtensionConnection* connection = [[ExtensionConnection alloc] initWithInputStream:(__bridge NSInputStream*)(readStream) outputStream:(__bridge NSOutputStream*)(writeStream)];
        [connection open];
    }
    else
    {
        // On any failure, we need to destroy the CFSocketNativeHandle
        // since we are not going to use it any more.
        (void) close(socketH);
    }

    if (readStream) CFRelease(readStream);
    if (writeStream) CFRelease(writeStream);
}

@implementation MimsyEndpoint

+ (void) setup
{
    _acceptSocket = CFSocketCreate(kCFAllocatorDefault, AF_INET, SOCK_STREAM, 0, kCFSocketAcceptCallBack, acceptCallback, NULL);
    if (!_acceptSocket)
    {
        LOG("Error", "Failed to create the accept socket for mimsy extensions");
        return;
    }
    
    const int yes = 1;
    (void) setsockopt(CFSocketGetNative(_acceptSocket), SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    CFDataRef address = CFDataCreate(kCFAllocatorDefault, (UInt8*)&addr, sizeof(addr));
    CFSocketError err = CFSocketSetAddress(_acceptSocket, address);
    if (err)
    {
        LOG("Error", "Mimsy accept socket CFSocketSetAddress failed (%ld)", err);
        CFSocketInvalidate(_acceptSocket);
        CFRelease(_acceptSocket);
        _acceptSocket = NULL;
        return;
    }
    
    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _acceptSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    CFRelease(source);
}

@end
