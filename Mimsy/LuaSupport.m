#import "LuaSupport.h"

#import <lauxlib.h>

#import "Assert.h"
#import "ColorCategory.h"
#import "FunctionalTest.h"
#import "StartupScripts.h"
#import "TextController.h"
#import "TextDocument.h"
#import "TextStyles.h"
#import "TextView.h"
#import "TranscriptController.h"

#define LUA_ASSERT(e, format, ...)						\
	do													\
	{													\
		if (__builtin_expect(!(e), 0))					\
		{												\
			__PRAGMA_PUSH_NO_EXTRA_ARG_WARNINGS			\
			luaL_error(state, format, ##__VA_ARGS__);	\
			__PRAGMA_POP_NO_EXTRA_ARG_WARNINGS			\
		}												\
	} while(0)

static NSColor* textColor(TextDocument* doc, NSString* name)
{
	NSColor* color = nil;
	
	if (doc.controller.styles && [name hasSuffix:@"color"])
	{
		name = [name stringByReplacingOccurrencesOfString:@" " withString:@""];
		name = [name lowercaseString];
		
		if ([name isEqualToString:@"backcolor"])
		{
			color = doc.controller.styles.backColor;
		}
		else if ([name isEqualToString:@"selectionbackcolor"])
		{
			color = [NSColor selectedTextBackgroundColor];
		}
		else
		{
			NSString* element = [name substringToIndex:name.length - 5];
			NSDictionary* attrs = [doc.controller.styles attributesForOnlyElement:element];
			if (attrs)
			{
				color = attrs[NSForegroundColorAttributeName];
			}
		}
	}
	
	if (!color)
		color = [NSColor colorWithMimsyName:name];
	
	return color;
}

void pushTextDoc(struct lua_State* state, NSDocument* doc)
{
	luaL_Reg methods[] =
	{
		{"close", doc_close},
		{"data", textdoc_data},
		{"getelementat", textdoc_getelementat},
		{"getselection", textdoc_getselection},
		{"getwholeelement", textdoc_getwholeelement},
		{"resetstyle", textdoc_resetstyle},
		{"saveas", doc_saveas},
		{"setbackcolor", textdoc_setbackcolor},
		{"setfont", textdoc_setfont},
		{"setforecolor", textdoc_setforecolor},
		{"setlink", textdoc_setlink},
		{"setselection", textdoc_setselection},
		{"setstrikethrough", textdoc_setstrikethrough},
		{"setstrokewidth", textdoc_setstrokewidth},
		{"settooltip", textdoc_settooltip},
		{"setunderline", textdoc_setunderline},
		{NULL, NULL}
	};
	luaL_register(state, "doc", methods);
	
	lua_pushlightuserdata(state, (__bridge void*) doc);
	lua_setfield(state, -2, "target");
}

void initMethods(struct lua_State* state)
{
	luaL_Reg methods[] =
	{
		{"addhook", app_addhook},
		{"log", app_log},
		{"newdoc", app_newdoc},
		{"openfile", app_openfile},
		{"schedule", app_schedule},
		{"stderr", app_stderr},
		{"stdout", app_stdout},
		{NULL, NULL}
	};
	luaL_register(state, "app", methods);
	
	lua_pushlightuserdata(state, (__bridge void*) NSApp);
	lua_setfield(state, -2, "target");
	
	lua_setglobal(state, "app");
}

// openfile(app, path, success = nil, failure = nil)
int app_openfile(struct lua_State* state)
{
	const char* path = lua_tostring(state, 2);
	const char* success = luaL_optstring(state, 3, NULL);
	const char* failure = luaL_optstring(state, 4, NULL);
	
	LUA_ASSERT(path != NULL, "path was nil");
	
	NSURL* url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
	
	[[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url display:YES completionHandler:
	 ^(NSDocument* document, BOOL documentWasAlreadyOpen, NSError* error)
	 {
		 (void) documentWasAlreadyOpen;
		 if (error && failure)
		 {
			 NSString* reason = [error localizedFailureReason];
			 
			 lua_getglobal(state, failure);
			 lua_pushstring(state, reason.UTF8String);
			 lua_call(state, 1, 0);						// 1 arg, no result
		 }
		 else if (!error && success)
		 {
			 if ([document isKindOfClass:[TextDocument class]])
			 {
				 lua_getglobal(state, success);
				 pushTextDoc(state, document);
				 lua_call(state, 1, 0);					// 1 arg, no result
			 }
			 else
			 {
				 lua_getglobal(state, failure);
				 lua_pushstring(state, "Document isn't a text document");
				 lua_call(state, 1, 0);					// 1 arg, no result
			 }
		 }
	 }
	 ];
	
	return 0;
}

// schedule(app, secs, callback)
int app_schedule(struct lua_State* state)
{
	double secs = lua_tonumber(state, 2);
	NSString* callback = [NSString stringWithUTF8String:lua_tostring(state, 3)];	// NSString to ensure the memory doesn't go away when we return and pop the stack
	
	LUA_ASSERT(secs >= 0.0, "secs was negative");
	LUA_ASSERT(callback != NULL && callback.length > 0, "callback was NULL or empty");
	
	dispatch_queue_t main = dispatch_get_main_queue();
	dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t) (secs*1.0e9));
	dispatch_after(delay, main,
		^{
			// TODO: It would be nice to support calling lua closures, but I'm not
			// quite sure how to do that (e.g. how do we prevent the closure from
			// being GCed?).
			lua_getglobal(state, callback.UTF8String);
			int err = lua_pcall(state, 0, 0, 0);		// 0 args, no result
			if (err)
			{
				if (functionalTestsAreRunning())
				{
					lua_pushvalue(state, -1);
					ftest_failed(state);
				}
				else
				{
					[TranscriptController writeStderr:[NSString stringWithUTF8String:lua_tostring(state, -1)]];
				}
			}
		}
	);

	return 0;
}

// newdoc(app) -> textdoc
int app_newdoc(struct lua_State* state)
{
	NSError* error = nil;
	NSDocument* doc = [[NSDocumentController sharedDocumentController] makeUntitledDocumentOfType:@"Plain Text, UTF8 Encoded" error:&error];
	ASSERT(doc);
	ASSERT(!error);
	
	[[NSDocumentController sharedDocumentController] addDocument:doc];
	[doc makeWindowControllers];
	[doc showWindows];
		
	pushTextDoc(state, doc);
	
	return 1;
}

// function addhook(app, hname, fname)
int app_addhook(struct lua_State* state)
{
	const char* hname = lua_tostring(state, 2);
	const char* fname = lua_tostring(state, 3);
	
	LUA_ASSERT(hname != NULL && strlen(hname) > 0, "hname was NULL or empty");
	LUA_ASSERT(fname != NULL && strlen(fname) > 0, "fname was NULL or empty");

	[StartupScripts addHook:[NSString stringWithUTF8String:hname] function:[NSString stringWithUTF8String:fname]];
	return 0;
}

// log(app, mesg)
// TODO: might want to stick a log method on all tables (so we get better categories)
int app_log(struct lua_State* state)
{
	const char* mesg = lua_tostring(state, 2);
	LUA_ASSERT(mesg != NULL, "mesg was NULL");

	LOG_INFO("Mimsy", "%s", mesg);
	return 0;
}

// close(doc)
int doc_close(struct lua_State* state)
{
	lua_getfield(state, 1, "target");
	NSDocument* doc = (__bridge NSDocument*) lua_touserdata(state, -1);
	LUA_ASSERT(doc != NULL, "doc was NULL");

	[doc close];		// doesn't ask to save changes
	return 0;
}

// saveas(doc, path, type = nil, success = nil, failure = nil)
int doc_saveas(struct lua_State* state)
{
	const char* path = lua_tostring(state, 2);
	const char* type = luaL_optstring(state, 3, "Plain Text, UTF8 Encoded");
	const char* success = luaL_optstring(state, 4, NULL);
	const char* failure = luaL_optstring(state, 5, NULL);
	lua_getfield(state, 1, "target");			// need to be careful about pushing onto the string when there are optional arguments
	NSDocument* doc = (__bridge NSDocument*) lua_touserdata(state, -1);
	
	LUA_ASSERT(doc != NULL, "doc was NULL");
	LUA_ASSERT(path != NULL && strlen(path) > 0, "path was NULL or empty");
	LUA_ASSERT(type != NULL && strlen(type) > 0, "type was NULL or empty");

	NSURL* url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
	[doc saveToURL:url ofType:[NSString stringWithUTF8String:type] forSaveOperation:NSSaveAsOperation completionHandler:
		^(NSError* error)
		{
			if (error && failure)
			{
				NSString* reason = [error localizedFailureReason];
				
				lua_getglobal(state, failure);
				lua_pushstring(state, reason.UTF8String);
				lua_call(state, 1, 0);						// 1 arg, no result
			}
			else if (!error && success)
			{
				lua_getglobal(state, success);
				lua_pushvalue(state, 1);
				lua_call(state, 1, 0);						// 1 arg, no result
			}
		}
	];
	return 0;
}

// stderr(app, mesg)
int app_stderr(struct lua_State* state)
{
	const char* mesg = lua_tostring(state, 2);
	LUA_ASSERT(mesg != NULL, "mesg was NULL");
	[TranscriptController writeStderr:[NSString stringWithUTF8String:mesg]];
	return 0;
}

// stdout(app, mesg)
int app_stdout(struct lua_State* state)
{
	const char* mesg = lua_tostring(state, 2);
	LUA_ASSERT(mesg != NULL, "mesg was NULL");
	[TranscriptController writeStdout:[NSString stringWithUTF8String:mesg]];
	return 0;
}

// data(textdoc) -> text
int textdoc_data(struct lua_State* state)
{
	lua_getfield(state, 1, "target");
	TextDocument* doc = (__bridge TextDocument*) lua_touserdata(state, -1);
	LUA_ASSERT(doc != NULL, "doc was NULL");
	lua_pushstring(state, doc.controller.text.UTF8String);
	return 1;
}

// getelementat(textdoc, loc) -> name
int textdoc_getelementat(struct lua_State* state)
{
	lua_getfield(state, 1, "target");
	TextDocument* doc = (__bridge TextDocument*) lua_touserdata(state, -1);
	lua_Integer loc = lua_tointeger(state, 2) - 1;
	
	LUA_ASSERT(doc != NULL, "doc was NULL");
	LUA_ASSERT(loc >= 0 && loc < doc.controller.text.length, "loc = %d", loc);

	NSString* name = nil;
	NSTextStorage* storage = doc.controller.textView.textStorage;
	
	// Note that effectiveRange is so poorly specified as to be useless.
	NSDictionary* attrs = [storage attributesAtIndex:(NSUInteger)loc effectiveRange:NULL];
	if (attrs)
		name = attrs[@"element name"];
	
	lua_pushstring(state, name.UTF8String);
	
	return 1;
}

// getselection(textdoc) -> loc, len
int textdoc_getselection(struct lua_State* state)
{
	lua_getfield(state, 1, "target");
	TextDocument* doc = (__bridge TextDocument*) lua_touserdata(state, -1);
	
	LUA_ASSERT(doc != NULL, "doc was NULL");

	NSRange selection = doc.controller.textView.selectedRange;
	lua_pushinteger(state, (lua_Integer) (selection.location+1));
	lua_pushinteger(state, (lua_Integer) selection.length);
	
	return 2;
}

// getwholeelement(textdoc, loc, len) -> name
int textdoc_getwholeelement(struct lua_State* state)
{
	lua_getfield(state, 1, "target");
	TextDocument* doc = (__bridge TextDocument*) lua_touserdata(state, -1);
	NSUInteger loc = (NSUInteger) lua_tointeger(state, 2) - 1;
	NSUInteger len = (NSUInteger) lua_tointeger(state, 3);
	
	LUA_ASSERT(doc != NULL, "doc was NULL");
	LUA_ASSERT(loc >= 0 && loc+len <= doc.controller.text.length, "loc = %d, len = %d", loc, len);

	NSTextStorage* storage = doc.controller.textView.textStorage;
	
	NSRange clipRange;
	clipRange.location = loc > 0 ? loc-1 : loc;
	clipRange.length   = MIN(len + 2, doc.controller.text.length - clipRange.location);
	
	NSString* name = nil;
	NSRange effRange;
	NSDictionary* attrs = [storage attributesAtIndex:loc longestEffectiveRange:&effRange inRange:clipRange];
	if (attrs && effRange.location == loc && effRange.length == len)
		name = attrs[@"element name"];
	
	if (name)
		lua_pushstring(state, name.UTF8String);
	else
		lua_pushnil(state);
	
	return 1;
}

// resetstyle(textdoc)
int textdoc_resetstyle(struct lua_State* state)
{
	lua_getfield(state, 1, "target");
	TextDocument* doc = (__bridge TextDocument*) lua_touserdata(state, -1);
	LUA_ASSERT(doc != NULL, "doc was NULL");
	[doc.controller resetStyles];
	return 0;
}

// setselection(textdoc, loc, len)
int textdoc_setselection(struct lua_State* state)
{
	lua_getfield(state, 1, "target");
	TextDocument* doc = (__bridge TextDocument*) lua_touserdata(state, -1);
	lua_Integer loc = lua_tointeger(state, 2) - 1;
	lua_Integer len = lua_tointeger(state, 3);
	
	LUA_ASSERT(doc != NULL, "doc was NULL");
	LUA_ASSERT(loc >= 0 && loc+len <= doc.controller.text.length, "loc = %d, len = %d", loc, len);

	NSTextView* view = doc.controller.textView;	
	[view setSelectedRange:NSMakeRange((NSUInteger)loc, (NSUInteger)len)];

	return 0;
}

// setbackcolor(textdoc, loc, len, color)
int textdoc_setbackcolor(struct lua_State* state)
{
	lua_getfield(state, 1, "target");
	TextDocument* doc = (__bridge TextDocument*) lua_touserdata(state, -1);
	lua_Integer loc = lua_tointeger(state, 2) - 1;
	lua_Integer len = lua_tointeger(state, 3);
	const char* cname = lua_tostring(state, 4);
	
	LUA_ASSERT(doc != NULL, "doc was NULL");
	LUA_ASSERT(loc >= 0 && loc+len <= doc.controller.text.length, "loc = %d, len = %d", loc, len);
	LUA_ASSERT(cname != NULL && strlen(cname) > 0, "color was NULL or empty");

	NSTextStorage* storage = doc.controller.textView.textStorage;
	NSColor* color = textColor(doc, [NSString stringWithUTF8String:cname]);
	if (color)
	{
		NSRange range = NSMakeRange((NSUInteger)loc, (NSUInteger)len);
		[storage addAttributes:@{NSBackgroundColorAttributeName: color} range:range];
	}
	else
	{
		luaL_error(state, "bad color: %s", cname);
	}		
	
	return 0;
}

// setfont(textdoc, loc, len, name, size)
int textdoc_setfont(struct lua_State* state)
{
	lua_getfield(state, 1, "target");
	TextDocument* doc = (__bridge TextDocument*) lua_touserdata(state, -1);
	lua_Integer loc = lua_tointeger(state, 2) - 1;
	lua_Integer len = lua_tointeger(state, 3);
	const char* name = lua_tostring(state, 4);
	lua_Number size = lua_tonumber(state, 5);
	
	LUA_ASSERT(doc != NULL, "doc was NULL");
	LUA_ASSERT(loc >= 0 && loc+len <= doc.controller.text.length, "loc = %d, len = %d", loc, len);
	LUA_ASSERT(name != NULL && strlen(name) > 0, "name was NULL or empty");
	LUA_ASSERT(size > 0, "size = %f", (float) size);
		
	NSTextStorage* storage = doc.controller.textView.textStorage;
	NSString* s = [NSString stringWithUTF8String:name];
	NSRange range = NSMakeRange((NSUInteger)loc, (NSUInteger)len);
	[storage addAttributes:@{NSFontAttributeName: [NSFont fontWithName:s size:size]} range:range];
	
	return 0;
}

// setforecolor(textdoc, loc, len, color)
int textdoc_setforecolor(struct lua_State* state)
{
	lua_getfield(state, 1, "target");
	TextDocument* doc = (__bridge TextDocument*) lua_touserdata(state, -1);
	lua_Integer loc = lua_tointeger(state, 2) - 1;
	lua_Integer len = lua_tointeger(state, 3);
	const char* cname = lua_tostring(state, 4);
	
	LUA_ASSERT(doc != NULL, "doc was NULL");
	LUA_ASSERT(loc >= 0 && loc+len <= doc.controller.text.length, "loc = %d, len = %d", loc, len);
	LUA_ASSERT(cname != NULL && strlen(cname) > 0, "color was NULL or empty");
	
	NSTextStorage* storage = doc.controller.textView.textStorage;
	NSColor* color = textColor(doc, [NSString stringWithUTF8String:cname]);
	if (color)
	{
		NSRange range = NSMakeRange((NSUInteger)loc, (NSUInteger)len);
		[storage addAttributes:@{NSForegroundColorAttributeName: color} range:range];
	}
	else
	{
		luaL_error(state, "bad color: %s", cname);
	}
	
	return 0;
}

// setlink(textdoc, loc, len, url)
int textdoc_setlink(struct lua_State* state)
{
	lua_getfield(state, 1, "target");
	TextDocument* doc = (__bridge TextDocument*) lua_touserdata(state, -1);
	lua_Integer loc = lua_tointeger(state, 2) - 1;
	lua_Integer len = lua_tointeger(state, 3);
	const char* url = lua_tostring(state, 4);
	
	LUA_ASSERT(doc != NULL, "doc was NULL");
	LUA_ASSERT(loc >= 0 && loc+len <= doc.controller.text.length, "loc = %d, len = %d", loc, len);
	LUA_ASSERT(url != NULL && strlen(url) > 0, "url was NULL or empty");
	
	NSURL* u = [NSURL URLWithString:[NSString stringWithUTF8String:url]];
	LUA_ASSERT(u != nil && strlen(url) > 0, "url was malformed: %s", url);
	
	NSTextStorage* storage = doc.controller.textView.textStorage;
	NSRange range = NSMakeRange((NSUInteger)loc, (NSUInteger)len);
	[storage addAttributes:@{NSLinkAttributeName: u} range:range];
	
	return 0;
}

// setstrokewidth(textdoc, loc, len, width)
int textdoc_setstrokewidth(struct lua_State* state)
{
	lua_getfield(state, 1, "target");
	TextDocument* doc = (__bridge TextDocument*) lua_touserdata(state, -1);
	lua_Integer loc = lua_tointeger(state, 2) - 1;
	lua_Integer len = lua_tointeger(state, 3);
	lua_Number width = lua_tonumber(state, 4);
	
	LUA_ASSERT(doc != NULL, "doc was NULL");
	LUA_ASSERT(loc >= 0 && loc+len <= doc.controller.text.length, "loc = %d, len = %d", loc, len);
	
	NSTextStorage* storage = doc.controller.textView.textStorage;
	NSRange range = NSMakeRange((NSUInteger)loc, (NSUInteger)len);
	[storage addAttributes:@{NSStrokeWidthAttributeName: [NSNumber numberWithDouble:width]} range:range];
	
	return 0;
}

// <strikethrough|underline>(textdoc, loc, len, style = 'single', pattern = 'solid, color = nil)
static void strikeunderline(struct lua_State* state, TextDocument** outDoc, NSRange* outRange, NSNumber** outStyle, NSColor** outColor)
{
	lua_Integer loc = lua_tointeger(state, 2) - 1;
	lua_Integer len = lua_tointeger(state, 3);
	const char* style = luaL_optstring(state, 4, "single");
	const char* pattern = luaL_optstring(state, 5, "solid");
	const char* cname = luaL_optstring(state, 6, NULL);
	lua_getfield(state, 1, "target");			// need to be careful about pushing onto the string when there are optional arguments
	*outDoc = (__bridge TextDocument*) lua_touserdata(state, -1);
	
	LUA_ASSERT(outDoc != NULL, "doc was NULL");
	LUA_ASSERT(loc >= 0 && loc+len <= (*outDoc).controller.text.length, "loc = %d, len = %d", loc, len);
		
	int value = 0;
	if (strcmp(style, "none") == 0)			// TODO: may also want to support NSUnderlineByWordMask
		value |= NSUnderlineStyleNone;
	else if (strcmp(style, "single") == 0)
		value |= NSUnderlineStyleSingle;
	else if (strcmp(style, "thick") == 0)
		value |= NSUnderlineStyleThick;
	else if (strcmp(style, "double") == 0)
		value |= NSUnderlineStyleDouble;
	else
		luaL_error(state, "bad style: %s", style);
	
	if (strcmp(pattern, "solid") == 0)
		value |= NSUnderlinePatternSolid;
	else if (strcmp(pattern, "dot") == 0)
		value |= NSUnderlinePatternDot;
	else if (strcmp(pattern, "dash") == 0)
		value |= NSUnderlinePatternDash;
	else if (strcmp(pattern, "dashdot") == 0)
		value |= NSUnderlinePatternDashDot;
	else if (strcmp(pattern, "dashdotdot") == 0)
		value |= NSUnderlinePatternDashDotDot;
	else
		luaL_error(state, "bad pattern: %s", pattern);
	*outStyle = [NSNumber numberWithInt:value];
	
	if (cname)
	{
		*outColor = textColor(*outDoc, [NSString stringWithUTF8String:cname]);
		if (!*outColor)
		{
			luaL_error(state, "bad color: %s", cname);
		}
	}

	*outRange = NSMakeRange((NSUInteger)loc, (NSUInteger)len);
}

// setstrikethrough(textdoc, loc, len, style = 'single', pattern = 'solid, color = nil)
int textdoc_setstrikethrough(struct lua_State* state)
{
	TextDocument* doc = nil;
	NSRange range;
	NSNumber* style = nil;
	NSColor* color = nil;
	strikeunderline(state, &doc, &range, &style, &color);
	
	NSTextStorage* storage = doc.controller.textView.textStorage;
	
	NSMutableDictionary* attrs = [NSMutableDictionary new];
	attrs[NSStrikethroughStyleAttributeName] = style;
	if (color)
		attrs[NSStrikethroughColorAttributeName] = color;
	
	[storage addAttributes:attrs range:range];
	
	return 0;
}

// setunderline(textdoc, loc, len, style = 'single', pattern = 'solid, color = nil)
int textdoc_setunderline(struct lua_State* state)
{
	TextDocument* doc = nil;
	NSRange range;
	NSNumber* style = nil;
	NSColor* color = nil;
	strikeunderline(state, &doc, &range, &style, &color);
	
	NSTextStorage* storage = doc.controller.textView.textStorage;
	
	NSMutableDictionary* attrs = [NSMutableDictionary new];
	attrs[NSUnderlineStyleAttributeName] = style;
	if (color)
		attrs[NSUnderlineColorAttributeName] = color;
	
	[storage addAttributes:attrs range:range];
	
	return 0;
}

// settooltip(textdoc, loc, len, text)
int textdoc_settooltip(struct lua_State* state)
{
	lua_getfield(state, 1, "target");
	TextDocument* doc = (__bridge TextDocument*) lua_touserdata(state, -1);
	lua_Integer loc = lua_tointeger(state, 2) - 1;
	lua_Integer len = lua_tointeger(state, 3);
	const char* text = lua_tostring(state, 4);
	
	LUA_ASSERT(doc != NULL, "doc was NULL");
	LUA_ASSERT(loc >= 0 && loc+len <= doc.controller.text.length, "loc = %d, len = %d", loc, len);
	LUA_ASSERT(text != NULL, "text was NULL");
	
	if (strlen(text) > 0)
	{
		NSTextStorage* storage = doc.controller.textView.textStorage;
		NSRange range = NSMakeRange((NSUInteger)loc, (NSUInteger)len);
		[storage addAttributes:@{NSToolTipAttributeName: [NSString stringWithUTF8String:text]} range:range];
	}
	
	return 0;
}
