#import <Cocoa/Cocoa.h>

// Misc utility functions.
@interface Utils : NSObject

// Converts bytes to a string like "10 KiB" or "1.2 MiB".
+ (NSString*)bytesToStr:(NSUInteger)bytes;

// Returns a `hexdump -C` sort of string except that unicode symbols are
// used for control characters.
+ (NSString*)bufferToStr:(const void*)buffer length:(NSUInteger)length;

@end
