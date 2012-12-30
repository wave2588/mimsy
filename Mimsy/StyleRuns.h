#import <Foundation/Foundation.h>
#import "StyleRunVector.h"

typedef id (^ElementToStyle)(NSString* elementName);

typedef void (^ProcessStyleRun)(id style, NSRange range, bool* stop);

// Style runs computed for a text document. Once constructed it
// should only be used by the main thread.
@interface StyleRuns : NSObject

- (id)initWithElementNames:(NSArray*)names runs:(struct StyleRunVector)runs editCount:(NSUInteger)count;

// The version of the document these runs were computed for.
@property (readonly) NSUInteger editCount;

// The number of unprocessed runs.
@property (readonly) NSUInteger length;

// Pre-computes style information (usually an NSDictionary) for
// each element name.
- (void)mapElementsToStyles:(ElementToStyle)block;

// Calls block until there are no more unprocessed runs or stop
// is set. As a side effect length is adjusted by the number of
// times block was called.
- (void)process:(ProcessStyleRun)block;

// Sorts the run so that the runs closest to offset will be
// processed first. Will not sort if abs(oldOffset - offset) <= threshold.
- (void)sortByDistanceFrom:(NSUInteger)offset threshold:(NSUInteger)threshold;

@end