#import "ArrayCategory.h"

@implementation NSArray (ArrayCategory)

- (NSArray*)filteredArrayUsingBlock:(bool (^)(id element))block
{
	NSMutableArray* result = [[NSMutableArray alloc] initWithCapacity:self.count];
	
	for (id element in self)
	{
		if (block(element))
			[result addObject:element];
	}
	
	return result;
}

- (NSArray*)map:(id (^)(id element))block
{
	NSMutableArray* result = [[NSMutableArray alloc] initWithCapacity:self.count];
	
	for (id element in self)
	{
		[result addObject:block(element)];
	}
	
	return result;
}

- (NSArray*)arrayByRemovingObject:(id)object
{
	NSMutableArray* result = [[NSMutableArray alloc] initWithCapacity:self.count - 1];
	
	for (id element in self)
	{
		if (![element isEqualTo:object])
			[result addObject:element];
	}
	
	return result;
}

@end

@implementation NSMutableArray (MutableArrayCategory)

- (NSMutableArray*)map:(id (^)(id element))block
{
	NSMutableArray* result = [[NSMutableArray alloc] initWithCapacity:self.count];
	
	for (id element in self)
	{
		[result addObject:block(element)];
	}
	
	return result;
}

@end
