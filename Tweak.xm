/*%%%%%
%% Tweak.xm
%% DMLonger
%% created by theiostream in 2013
%% (c) 2013 Colégio Visconde de Porto Seguro. Not all rights reserved.
%%%%%*/

// COMPATIBILITY:
// Twitter 5.x+
// Tweetbot 2.6.2 (untested on previous versions)
// Tweetbot for iPad 2.6.2

/*
A small note on compatibility:

I chose not to have support for older than 5.x Twitter versions even though I use 4.x
on my iPad because then I would end up having to port back to 3.x (last good version on
the iPhone) and someone would want it back on Tweetie (2.x) and I'd just keep backporting
forever.

In my opinion, apart from the downside that I think Twitter for iPad 4.x is the best app
ever, Tweetbot for iPhone is awesome and the iPad version is getting there. :P
*/

// - FIX SPACE BUG BECAUSE FUCK YOU.

/*================ SHARED */

// From Cocoanetics (s/&amp/&)
static NSString *NSStringURLEncode(NSString *string) {
	return (NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)string, NULL, CFSTR("!*'();:@&=+$,/?%#[]"), kCFStringEncodingUTF8);
}

static NSString *NSDictionaryURLEncode(NSDictionary *dict) {
	NSMutableString *ret = [NSMutableString string];
	
	NSArray *allKeys = [dict allKeys];
	for (NSString *key in allKeys) {
		[ret appendString:NSStringURLEncode(key)];
		[ret appendString:@"="];
		[ret appendString:NSStringURLEncode([dict objectForKey:key])];
		[ret appendString:@"&"];
	}
	
	return [ret substringToIndex:[ret length]-1];
}

static NSURLRequest *TBPastieRequest(NSString *text) {
	NSDictionary *pastie = [NSDictionary dictionaryWithObjectsAndKeys:
		@"plain_text", @"paste[parser]",
		@"burger", @"paste[authorization]",
		@"0", @"paste[restricted]",
		text, @"paste[body]",
		nil];
	NSString *body = NSDictionaryURLEncode(pastie);
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://pastie.org/pastes/"]];
	[request setHTTPMethod:@"POST"];
	[request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
	
	return (NSURLRequest *)request;
}

static NSString *TBInstapaperMobilize(NSString *pastie) {
	NSString *number = [[pastie componentsSeparatedByString:@"/"] lastObject];
	NSString *pastie_raw = [NSString stringWithFormat:@"http://pastie.org/pastes/%@/text", number];
	NSString *instapaper = [NSString stringWithFormat:@"http://instapaper.com/m?u=%@", NSStringURLEncode(pastie_raw)];
	
	NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://tinyurl.com/api-create.php?url=%@", instapaper]]];
	NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:NULL];
	return [NSString stringWithUTF8String:(const char *)[data bytes]];
}

static void TBLimitTweet(NSUInteger limitIndex, NSString *text, NSString **limit, NSString **rest) {
	NSLog(@"limitIndex: %i", limitIndex);
	*limit = [text substringToIndex:limitIndex];
	NSLog(@"hi");
	
	NSInteger index = limitIndex-1;
	while (index >= 0) {
		NSLog(@"index is %i run", index);
		char whitespace = [*limit characterAtIndex:index];
		if (whitespace == ' ' || whitespace == '\t') break;
		
		index--;
	}
	if (index == -1) index = limitIndex;
	
	NSLog(@"index ended up as %i", index);
	*limit = [*limit substringToIndex:index];
	NSLog(@"kool");
	
	if (rest != NULL)
		*rest = [text substringFromIndex:index+1];
	NSLog(@"she's leaving home bye bye");
}

/*================ TWEETBOT */

@interface UIBarButtonItem (PTHTweetbotShitCategory)
+ (UIBarButtonItem *)rightSpinnerItemWithWidth:(CGFloat)width;
@end

@interface PTHTweetbotSettings : NSObject
+ (id)sharedSettings;
- (BOOL)postInBackground;
@end

@interface PTHTweetbotUser : NSObject
@end

@interface PTHTweetbotPostDraft : NSObject
- (id)initWithToUser:(PTHTweetbotUser *)user;
- (PTHTweetbotUser *)toUser;
- (NSString *)text;
- (void)setPosting:(BOOL)posting;
- (void)setText:(NSString *)text;
- (BOOL)isPosting;
- (NSUInteger)length;
@end

@interface PTHTweetbotDirectMessagesController : UIViewController
- (void)sendMessage:(UIButton *)sender;
@end

@interface PTHTweetbotPostController : UIViewController
- (void)post:(id)sender;
- (UITextView *)textView;
- (id)postToolbarView;
@end

static PTHTweetbotDirectMessagesController *tweetbotDMController = nil;
static UILabel *tweetbotDMCounter = nil;
static UIButton *tweetbotDMSender = nil;
static UILabel *tweetbotCounter = nil;

// ---- Tweetbot Post Hooks
%group TBTweetbot
%hook PTHTweetbotPostToolbarView
- (id)initWithFrame:(CGRect)frame {
	if ((self = %orig)) tweetbotCounter = MSHookIvar<UILabel *>(self, "_counterLabel");
	return self;
}
%end

%hook PTHTweetbotPostController
- (void)post:(id)sender {
	PTHTweetbotPostDraft **draft = &MSHookIvar<PTHTweetbotPostDraft *>(self, "_draft");
	NSString *text = [[*draft text] retain];
	
	if ([*draft length] > 140) {
		NSString *before_pastie;
		TBLimitTweet(116, text, &before_pastie, NULL);
		
		// Unfortunately using this hooking way we are unable to completely cooperate with Tweetbot's "Post In Background" feature.
		[[self navigationItem] setRightBarButtonItem:[%c(UIBarButtonItem) rightSpinnerItemWithWidth:24.f]];
		
		NSURLRequest *request = TBPastieRequest(text);
		[NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error){
			NSString *pastie_link = TBInstapaperMobilize([[response URL] absoluteString]);
			NSString *res = [before_pastie stringByAppendingString:[@"... " stringByAppendingString:pastie_link]];
			
			[*draft setText:res];
			[self post:sender];
		}];
	}
	else %orig;
	
	[text release];
}
%end

%hook PTHTweetbotDirectMessagesController
- (id)initWithDirectMessageThread:(id)thread {
	if ((self = %orig)) tweetbotDMController = self;
	return self;
}

- (void)loadView {
	%orig;
	tweetbotDMSender = MSHookIvar<UIButton *>(self, "_sendButton");
	tweetbotDMCounter = MSHookIvar<UILabel *>(self, "_counterLabel");
}

- (void)dealloc {
	tweetbotDMController = nil;
	tweetbotDMSender = nil;
	tweetbotDMCounter = nil;
	
	%orig;
}

- (void)sendMessage:(UIButton *)sender {
	PTHTweetbotPostDraft **draft = &MSHookIvar<PTHTweetbotPostDraft *>(self, "_draft");
	PTHTweetbotUser *toUser = [[*draft toUser] retain];
	NSString *text = [[*draft text] retain];
	BOOL posting = [*draft isPosting];
	
	if ([*draft length] > 140) {
		NSString *limited, *rest;
		TBLimitTweet(140, text, &limited, &rest);
		
		[*draft release];
		PTHTweetbotPostDraft *currentDraft = [[%c(PTHTweetbotPostDraft) alloc] initWithToUser:toUser];
		[currentDraft setPosting:YES];
		[currentDraft setText:limited];
		*draft = currentDraft;
		[self sendMessage:sender];
		NSLog(@"hey joe");
		
		[*draft release];
		PTHTweetbotPostDraft *nextDraft = [[%c(PTHTweetbotPostDraft) alloc] initWithToUser:toUser];
		[nextDraft setPosting:YES];
		[nextDraft setText:rest];
		*draft = nextDraft;
		[self sendMessage:sender];
		NSLog(@"run down to mexico");
	}
	else %orig;
	
	[*draft release];
	PTHTweetbotPostDraft *finalDraft = [[%c(PTHTweetbotPostDraft) alloc] initWithToUser:toUser];
	[finalDraft setPosting:posting];
	[finalDraft setText:[MSHookIvar<UITextView *>(self, "_textView") text]];
	*draft = finalDraft;
	
	[toUser release];
	[text release];
}
%end

%hook UIButton
- (void)setEnabled:(BOOL)enabled {
	if (self == tweetbotDMSender && !enabled) {
		if (![[MSHookIvar<UITextView *>(tweetbotDMController, "_textView") text] isEqualToString:@""]) {
			if ([self isEnabled]) return;
			else { [self setEnabled:YES]; return; }
		}
	}
	
	%orig;
}
%end

%hook UILabel
- (void)setText:(NSString *)text {
	if ([text intValue] < 0 && (self==tweetbotDMCounter || self==tweetbotCounter)) {
		%orig(@"...");
		return;
	}
	
	%orig;
}

- (void)setTextColor:(UIColor *)color {
	if (self==tweetbotDMCounter || self==tweetbotCounter) {
		if (CGColorSpaceGetModel(CGColorGetColorSpace([color CGColor])) == kCGColorSpaceModelMonochrome)
			%orig;
	}
	else %orig;
}
%end
%end

/*================ TWITTER */

static UIViewController *conversationViewController = nil;
static UIViewController *composeViewController = nil;
static UIBarButtonItem *dmSendButton = nil;
static UIBarButtonItem *sendButton = nil;
static UILabel *dmCounterLabel = nil;
static UILabel *counterLabel = nil;
static BOOL theiostream_in_the_house = NO;

@interface TwitterComposition : NSObject
- (id)initWithInitialText:(NSString *)text;
- (BOOL)isDirectMessage;
- (void)setText:(NSString *)text;
- (void)sendFromAccount:(id)account;
- (NSString *)text;
- (NSInteger)remainingCharactersForAccount:(id)account;
- (void)setDirectMessageUser:(id)user;
- (id)directMessageUser;
@end

%group TBTwitter
%hook T1ConversationViewController
- (id)init {
	if ((self = %orig)) conversationViewController = (UIViewController *)self;
	return self;
}

- (void)loadView {
	%orig;
	dmSendButton = MSHookIvar<UIBarButtonItem *>(self, "sendButton");
}

- (void)setupComposeBar {
	%orig;
	dmCounterLabel = MSHookIvar<UILabel *>(self, "counter");
}

- (void)updateCounter {
	theiostream_in_the_house = YES;
	%orig;
	theiostream_in_the_house = NO;
}

- (void)dealloc {
	conversationViewController = nil;
	dmSendButton = nil;
	%orig;
}

- (void)textViewDidBeginEditing:(UITextView *)textView {
	%orig;
	
	UIBarButtonItem *item = MSHookIvar<UIBarButtonItem *>(self, "sendButton");
	if (![item isEnabled] && ![[textView text] isEqualToString:@""])
		 [item setEnabled:YES];
}
%end

%hook T1ComposeViewController
- (id)init {
	%log;
	if ((self = %orig)) composeViewController = (UIViewController *)self;
	return self;
}

- (void)viewDidLoad {
	%orig;
	sendButton = MSHookIvar<UIBarButtonItem *>(self, "sendButton");
	[sendButton setEnabled:NO];
}

- (void)_setupCounter {
	%orig;
	counterLabel = MSHookIvar<UILabel *>(self, "remainingCharactersLabel");
}

- (void)_textDidChange {
	theiostream_in_the_house = YES;
	%orig;
	theiostream_in_the_house = NO;
}

- (void)dealloc {
	composeViewController = nil;
	sendButton = nil;
	counterLabel = nil;
	%orig;
}
%end

%hook UIBarButtonItem
- (void)setEnabled:(BOOL)enabled {
	if (!enabled) {
		if (self == dmSendButton) {
			if (![[MSHookIvar<UITextView *>(conversationViewController, "composeTextView") text] isEqualToString:@""]) {
				if ([dmSendButton isEnabled]) return;
				else { %orig(YES); return; }
			}
		}
		else if (self == sendButton) {
			if (![[MSHookIvar<UITextView *>(composeViewController, "textView") text] isEqualToString:@""]) {
				if ([sendButton isEnabled]) return;
				else { %orig(YES); return; }
			}
		}
	}
	
	%orig;
}
%end

%hook UILabel
- (void)setText:(NSString *)text {
	if (self == counterLabel || self == dmCounterLabel) {
		NSInteger remaining = [text intValue];
		%orig(remaining<0 ? @"..." : text);
	}
	else %orig;
}
%end

%hook UIColor
+ (UIColor *)textColorForRemainingCharacterCount:(NSInteger)count {
	return %orig(140);
}
%end

%hook TwitterComposition
- (void)sendFromAccount:(id)account {
	%log;
	NSString *text = [self text];
	theiostream_in_the_house = YES;
	NSInteger remaining = [self remainingCharactersForAccount:account];
	theiostream_in_the_house = NO;
	
	if ([self isDirectMessage]) {
		if (remaining < 0) {
			NSString *limited, *rest;
			TBLimitTweet(140, text, &limited, &rest);
			
			[self setText:limited];
			[self sendFromAccount:account];
			
			TwitterComposition *composition = [[%c(TwitterComposition) alloc] initWithInitialText:rest];
			[composition setDirectMessageUser:[self directMessageUser]];
			[composition sendFromAccount:account];
			[composition release];
			
			[self setText:[NSString string]];
		}
		else %orig;
	}
	
	else {
		if (remaining < 0) {
			NSString *limited;
			TBLimitTweet(116, text, &limited, NULL);
			
			NSURLRequest *request = TBPastieRequest(text);
			[NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error){
				NSString *pastie_link = TBInstapaperMobilize([[response URL] absoluteString]);
				[self setText:[limited stringByAppendingString:[@"... " stringByAppendingString:pastie_link]]];
				[self sendFromAccount:account];
			}];
		}
		else %orig;
	}
}

- (BOOL)isWorthSendingFromAccount:(id)account {
	return ![[self text] isEqualToString:@""];
}

- (NSInteger)remainingCharactersForAccount:(id)account {
	return theiostream_in_the_house ? %orig : 0;
}
%end
%end

%ctor {
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	
	NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
	if ([bundleID isEqualToString:@"com.tapbots.Tweetbot"] || [bundleID isEqualToString:@"com.tapbots.TweetbotPad"])
		%init(TBTweetbot);
	else if ([bundleID isEqualToString:@"com.atebits.Tweetie2"])
		%init(TBTwitter);
	
	[pool drain];
}