#import <Foundation/Foundation.h>

// Preferences loaded from app.mimsy and the current directory's
//.mimsy.rtf (if present).
@interface Settings : NSObject

+ (bool)boolValue:(NSString*)name missing:(bool)value;

+ (int)intValue:(NSString*)name missing:(int)value;

+ (unsigned int)uintValue:(NSString*)name missing:(unsigned int)value;

+ (NSString*)stringValue:(NSString*)name missing:(NSString*)value;

+ (NSArray*)stringValues:(NSString*)name;

@end