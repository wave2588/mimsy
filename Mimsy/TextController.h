#import <Cocoa/Cocoa.h>

#import "BaseTextController.h"
#import "MimsyPlugins.h"
#import "Settings.h"

@class DeclarationsPopup, GlyphsAttribute, Language, TextController, TextStyles, TextView;

typedef void (^LayoutCallback)(TextController* controller);

@interface CharacterMapping : NSObject

- (id)initWithFields:(NSString*)fields controller:(TextController*)controller;

- (void)reload:(TextController*)controller;

@property (readonly) NSString* key;
@property (readonly) NSRegularExpression* regex;
@property (readonly) NSString* style;
@property (readonly) GlyphsAttribute* glyphs;

@end

// Contoller used to mediate between text documents and the NSTextView in the associated window.
@interface TextController : BaseTextController<MimsyTextView, SettingsContext>

+ (void)startup;

+ (TextController*)frontmost;
+ (void)enumerate:(void (^)(TextController* controller, bool* stop))block;
+ (TextController*)find:(NSString*)path;

- (void)open;
- (bool)closed;
- (void)onPathChanged;
- (bool)isWordWrapping;
- (void)toggleWordWrap;
- (NSDictionary*)resetTypingAttributes;
- (void)changeStyle:(NSString*)path;
- (void)resetStyles;
- (void)showLine:(NSInteger)line atCol:(NSInteger)col withTabWidth:(NSInteger)width;
- (NSString*)path;

- (void)shiftLeft:(id)sender;
- (void)shiftRight:(id)sender;

// Returns the language element name the range is within, e.g. String, Comment, Identifier, etc.
// Returns nil if the window has no language or the range crosses multiple elements. Note that
// this returns a lower case version of the element name.
- (NSString*)getElementNameFor:(NSRange)range;

- (NSString*)getElementNames;

- (bool)isBrace:(unichar)ch;
- (bool)isOpenBrace:(NSUInteger)index;
- (bool)isCloseBrace:(NSUInteger)index;

- (void)registerBlockWhenLayoutCompletes:(LayoutCallback)block;

- (NSTextView*)getTextView;
- (NSUInteger)getEditCount;

- (void)onAppliedStyles;

- (void)addMapping:(CharacterMapping*)mapping;
- (void)removeMapping:(NSString*)key;
- (NSArray*) charMappings;

- (bool)showingLeadingSpaces;
- (bool)showingLeadingTabs;
- (bool)showingLongLines;
- (bool)showingNonLeadingTabs;

- (id<SettingsContext>)parent;
- (Settings*)settings;

@property IBOutlet TextView* textView;
@property IBOutlet __weak NSScrollView* scrollView;
@property NSAttributedString* attributedText;
@property (readonly) NSUInteger editCount;
@property (readonly) TextStyles* styles;
@property NSString* customTitle;
@property (strong) IBOutlet NSButton *lineButton;
@property (strong) IBOutlet DeclarationsPopup *declarationsPopup;

@end
