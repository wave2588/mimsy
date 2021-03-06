#import "ConfigParserTests.h"

#import "ConfigParser.h"

@implementation ConfigParserTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testEmpty
{
	[self checkGood:@"" keys:@[] values:@[] func:__func__];
	[self checkGood:@"  \n \r " keys:@[] values:@[] func:__func__];
	[self checkGood:@"# blah\n\n# blah" keys:@[] values:@[] func:__func__];
}

- (void)testContent
{
	[self checkGood:@"alpha: one\nbeta: two\n" keys:@[@"alpha", @"beta"] values:@[@"one", @"two"] func:__func__];
}

- (void)testMixedContent
{
	[self checkGood:@"# blah\nalpha: one\n\n\nb*t!  : two\t \ngamma: \n#trailer" keys:@[@"alpha", @"b*t!", @"gamma"] values:@[@"one", @"two", @""] func:__func__];
}

- (void)testRepeated
{
	[self checkGood:@"alpha: one\nbeta: two\nalpha: three\n" keys:@[@"alpha", @"beta", @"alpha"] values:@[@"one", @"two", @"three"] func:__func__];
}

- (void)testMissingColon
{
	[self checkBad:@"alpha: one\nbeta: two\nalpha three\n" errors:@[@"Expected a colon", @"found EOF"] func:__func__];
}

- (void)testNonBlankLine
{
	[self checkBad:@"alpha: one\n beta: two\nalpha: three\n" errors:@[@"Expected EOL", @"line 2"] func:__func__];
}

- (void)testWindowsLines
{
	[self checkBad:@"alpha: one\r\nbeta: two\r\nalpha three\r\n" errors:@[@"Expected a colon", @"line 3"] func:__func__];
}

// For now we don't check offsets.
- (void)checkGood:(NSString*)content keys:(NSArray*)keys values:(NSArray*)values func:(const char*)func
{
	ASSERT(keys.count == values.count);
	
	NSString* fname = [[NSString alloc] initWithFormat:@"%s", func];
	
	NSError* error = nil;
	ConfigParser* parser = [[ConfigParser alloc] initWithContent:content outError:&error];
	STAssertNil(error, nil);
	
	STAssertEquals(keys.count, parser.length, fname);
	for (NSUInteger i = 0; i < MIN(keys.count, parser.length); ++i)
	{
		STAssertEqualObjects(keys[i], [parser[i] key], fname);
		STAssertEqualObjects(values[i], [parser[i] value], fname);
	}
}

- (void)checkBad:(NSString*)content errors:(NSArray*)errors func:(const char*)func
{	
	NSError* error = nil;
	(void) [[ConfigParser alloc] initWithContent:content outError:&error];
	STAssertNotNil(error, nil);
	
	for (NSString* err in errors)
	{
		NSRange range = [[error localizedFailureReason] rangeOfString:err];
		if (range.location == NSNotFound)
			STFail(@"Expected '%@' within '%@' for %s", err, error.localizedFailureReason, func);
	}
}

@end


