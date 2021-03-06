#import "ConditionalGlob.h"

#import <fnmatch.h>
#import "Logger.h"

@implementation ConditionalGlob
{
	NSArray* _regexen;
	NSArray* _conditionals;
}

- (id)initWithGlob:(NSString*)glob
{
	self = [super initWithGlob:glob];
	return self;
}

- (id)initWithGlobs:(NSArray*)globs
{
	self = [super initWithGlobs:globs];
	return self;
}

- (id)initWithGlobs:(NSArray*)globs regexen:(NSArray*)regexen conditionals:(NSArray*)conditionals
{
	self = [super initWithGlobs:globs];
	
	if (self)
	{
		_regexen = regexen;
		_conditionals = conditionals;
	}
	
	return self;
}

- (int)matchName:(NSString*)name contents:(NSString*)contents
{
	for (NSUInteger i = 0; i < _conditionals.count; ++i)
	{
		if (fnmatch([_conditionals[i] UTF8String], [name UTF8String], FNM_CASEFOLD) == 0)
		{
			NSTextCheckingResult* match = [_regexen[i] firstMatchInString:contents options:0 range:NSMakeRange(0, contents.length)];
			if (match && match.range.location != NSNotFound)
			{
				return 2;
			}
		}
	}
	
	if ([super matchName:name])
		return 1;
	
	return 0;
}

- (id)copyWithZone:(NSZone*)zone
{
	return [[ConditionalGlob allocWithZone:zone] initWithGlobs:self.globs regexen:_regexen conditionals:_conditionals];
}

- (NSUInteger)hash
{
	return [self.globs hash] + [_regexen hash] + [_conditionals hash];
}

- (BOOL)isEqual:(id)rhs
{
	if (rhs && [rhs isMemberOfClass:[ConditionalGlob class]])
	{
		ConditionalGlob* g = (ConditionalGlob*) rhs;
		return [self.globs isEqual:g.globs] && [_regexen isEqual:g->_regexen] && [_conditionals isEqual:g->_conditionals];
	}
	return FALSE;
}

@end
