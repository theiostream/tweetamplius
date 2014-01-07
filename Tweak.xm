/*%%%%%
%% Tweak.xm
%% DMLonger
%% created by theiostream in 2013
%% (c) 2013 Colégio Visconde de Porto Seguro. Not all rights reserved.
%%%%%*/

// COMPATIBILITY:
// Twitter 5.x / 6.x (UI Bugs!)
// Tweetbot 2.6.2 (untested on previous versions)
// Tweetbot for iPad 2.6.2
// Tweetbot 3.0 (NOT REALLY)

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

#define Twitter6x() ([[[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString *)kCFBundleVersionKey] compare:@"6.0" options:NSNumericSearch] != NSOrderedAscending)
static BOOL isTweetbot3 = NO;

static NSOperationQueue *tweetbotQueue = nil;

/* Shared {{{ */
static NSString *NSStringURLEncode(NSString *string) {
	return [(NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)string, NULL, CFSTR("!*'();:@&=+$,/?%#[]"), kCFStringEncodingUTF8) autorelease];
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

typedef void (^TBInstapaperMobilizeCompletionHandler)(NSString *);
static void TBInstapaperMobilize(NSString *pastie, TBInstapaperMobilizeCompletionHandler completion) {
	NSLog(@"mobilizing");
	NSString *number = [[pastie componentsSeparatedByString:@"/"] lastObject];
	NSString *pastie_raw = [NSString stringWithFormat:@"http://pastie.org/pastes/%@/download", number];
	NSString *instapaper = [NSString stringWithFormat:@"http://instapaper.com/m?u=%@", NSStringURLEncode(pastie_raw)];
	
	NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://is.gd/create.php?format=simple&url=%@", instapaper]]];
	[NSURLConnection sendAsynchronousRequest:request queue:tweetbotQueue completionHandler:^(NSURLResponse *response, NSData *data, NSError *error){
		NSLog(@"okay, this is the start of this block.");

		NSString *replyString;
		if (data == nil) {
			completion(instapaper);
			return;			
		}
		replyString = [NSString stringWithUTF8String:(const char *)[data bytes]];
		
		if (replyString != nil) {
			NSLog(@"completion(replyString = %@)", replyString);
			completion(replyString);
		}
		else {
			inst:
			NSLog(@"completion(instapaper = %@)", instapaper);
			completion(instapaper);
		}
	}];
}

static void TBLimitTweet(NSUInteger limitIndex, NSString *text, NSString **limit, NSString **rest) {
	NSLog(@"limitIndex: %i", limitIndex);
	*limit = [text substringToIndex:limitIndex];
	NSLog(@"hi");
	
	NSInteger index = limitIndex-1;
	while (index >= 0) {
		//NSLog(@"index is %i run", index);
		char whitespace = [*limit characterAtIndex:index];
		if (whitespace == ' ' || whitespace == '\t') break;
		
		index--;
	}
	if (index == -1) index = limitIndex;
	
	//NSLog(@"index ended up as %i", index);
	*limit = [*limit substringToIndex:index];
	//NSLog(@"kool");
	
	if (rest != NULL)
		*rest = [text substringFromIndex:index+1];
	NSLog(@"she's leaving home bye bye");
}
/* }}} */

/* Tweetbot {{{ */

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
- (NSArray *)mediaArray;
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
	%log;
	if ((self = %orig)) tweetbotCounter = MSHookIvar<UILabel *>(self, "_counterLabel");
	return self;
}
%end

%hook PTHTweetbotPostController
- (void)post:(id)sender {
	%log;

	PTHTweetbotPostDraft **draft = &MSHookIvar<PTHTweetbotPostDraft *>(self, "_draft");
	NSString *text = [[*draft text] retain];
	NSLog(@"text is %@ %i %i", text, [text length], [*draft length]);
	
	if ([*draft length] > 140) {
		NSString *before_pastie;
		
		NSInteger limit = 116;
		limit -= 20*([[*draft mediaArray] count]) + 3;
		NSLog(@"limit is %i (%i)", limit, [[*draft mediaArray] count]);
		
		TBLimitTweet(limit, text, &before_pastie, NULL);
		NSLog(@"before_pastie = %@", before_pastie);
		
		// Unfortunately using this hooking way we are unable to completely cooperate with Tweetbot's "Post In Background" feature.
		if (!isTweetbot3) {
			[[self navigationItem] setRightBarButtonItem:[%c(UIBarButtonItem) rightSpinnerItemWithWidth:24.f]];
		}
		else {
			// Since Tweetbot 3 no longer ships with a spinner, and we can't just push this into the background atm
			// (well we could, but... :P) we'll just push this one.
			UIActivityIndicatorView *indicator = [[%c(UIActivityIndicatorView) alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
			[indicator setColor:[%c(UIColor) grayColor]];
			UIBarButtonItem *barButton = [[%c(UIBarButtonItem) alloc] initWithCustomView:indicator];
			[[self navigationItem] setRightBarButtonItem:barButton];
			[barButton release];
			[indicator startAnimating];
			[indicator release];
		}
		
		NSURLRequest *request = TBPastieRequest(text);
		
		tweetbotQueue = [[NSOperationQueue alloc] init];
		NSLog(@"DID BLOCK COPY");
		void (^lolblock)(NSURLResponse *, NSData *, NSError *) = Block_copy(^(NSURLResponse *response, NSData *data, NSError *error){
			NSLog(@"this is before we attempt to access data.");
			NSLog(@"data = %p", data);

			if (data != nil) {
				NSLog(@"paste: %@", [[response URL] absoluteString]);
				
				TBInstapaperMobilize([[response URL] absoluteString], ^(NSString *pastie_link){
					NSLog(@"pastie_link = %@", pastie_link);
					NSString *res = [before_pastie stringByAppendingString:[@"... " stringByAppendingString:pastie_link]];
					if ([[*draft mediaArray] count] > 0) res = [res stringByAppendingString:@":"];
					
					[*draft setText:res];
					
					dispatch_sync(dispatch_get_main_queue(), ^{
						[self post:sender];
					});
				});
			}
			
			else {
				NSLog(@"is it this?!");
				
				dispatch_sync(dispatch_get_main_queue(), ^{
					[self dismissViewControllerAnimated:YES completion:^{
						UIAlertView *failed = [[[%c(UIAlertView) alloc] init] autorelease];
						[failed setTitle:@"TweetAmplius"];
						[failed setMessage:@"Request to pastie.org has failed."];
						[failed addButtonWithTitle:@"Dismiss"];
						[failed show];
					}];
				});
			}
		});
		
		NSLog(@"so ok we are sending the async request, right? %@ %@ %@", request, tweetbotQueue, lolblock);
		[NSURLConnection sendAsynchronousRequest:request queue:tweetbotQueue completionHandler:lolblock];

		NSLog(@"okay, so we just continue with this, right?");
		//[tweetbotQueue release];
		// FIXME <---------
	}
	else %orig;
	
	NSLog(@"right here we release text");
	[text release];
	NSLog(@"and quit -post:");
}
%end

%hook PTHTweetbotDirectMessagesController
- (id)initWithDirectMessageThread:(id)thread {
	%log;

	if ((self = %orig)) tweetbotDMController = self;
	NSLog(@"tweetbotDMController = %@", tweetbotDMController);
	return self;
}

- (void)loadView {
	%log;
	%orig;
	
	if (!isTweetbot3) {
		tweetbotDMSender = MSHookIvar<UIButton *>(self, "_sendButton");
		tweetbotDMCounter = MSHookIvar<UILabel *>(self, "_counterLabel");
	}
}

- (void)dealloc {
	%log;
	tweetbotDMController = nil;
	
	if (!isTweetbot3) {
		tweetbotDMSender = nil;
		tweetbotDMCounter = nil;
	}
	
	%orig;
}

- (void)sendMessage:(UIButton *)sender {
	%log;
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
	[finalDraft setText:[MSHookIvar<UITextView *>(self, isTweetbot3 ? "_messageTextView" : "_textView") text]];
	*draft = finalDraft;
	
	[toUser release];
	[text release];
}
%end

%hook PTHTweetbotDirectMessageTextView
- (id)initWithFrame:(CGRect)frame {
	%log;
	if ((self = %orig)) {
		if (isTweetbot3) {
			tweetbotDMSender = MSHookIvar<UIButton *>(self, "_sendButton");
			tweetbotDMCounter = MSHookIvar<UILabel *>(self, "_counterLabel");
		}
	}

	return self;
}

- (void)dealloc {
	%log;
	if (isTweetbot3) {
		tweetbotDMSender = nil;
		tweetbotDMCounter = nil;
	}

	%orig;
}
%end

%hook UIButton
- (void)setEnabled:(BOOL)enabled {
	%log;
	if (self == tweetbotDMSender && !enabled) {
		if (![[MSHookIvar<UITextView *>(tweetbotDMController, isTweetbot3 ? "_messageTextView" : "_textView") text] isEqualToString:@""]) {
			if ([self isEnabled]) return;
			else { [self setEnabled:YES]; return; }
		}
	}
	
	%orig;
}
%end

%hook UILabel
- (void)setText:(NSString *)text {
	%log;
	if ([text intValue] < 0 && (self==tweetbotDMCounter || self==tweetbotCounter)) {
		%orig(@"...");
		return;
	}
	
	%orig;
}

- (void)setTextColor:(UIColor *)color {
	%log;
	if (self==tweetbotDMCounter || self==tweetbotCounter) {
		if (CGColorSpaceGetModel(CGColorGetColorSpace([color CGColor])) == kCGColorSpaceModelMonochrome)
			%orig;
	}
	else %orig;
}
%end
%end

/* }}} */

/* Twitter {{{ */

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
- (int)attachmentsLengthForAccount:(id)account;
- (id)attachment;
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
	
	sendButton = MSHookIvar<UIBarButtonItem *>(self, Twitter6x() ? "sendButtonItem" : "sendButton");
	[sendButton setEnabled:NO];
}

- (void)_setupCounter {
	%orig;
	counterLabel = MSHookIvar<UILabel *>(self, "remainingCharactersLabel");
}

- (void)_setupPadCounter {
	%log;
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

+ (UIColor *)twitterTextColorForRemainingCharacterCount:(int)remainingCharacterCount light:(BOOL)light {
	return %orig(140, light);
}
%end

%hook TwitterComposition
- (void)sendFromAccount:(id)account {
	%log;
	NSString *text = [self text];
	NSLog(@"TEXT: %@", text);
	theiostream_in_the_house = YES;
	NSInteger remaining = [self remainingCharactersForAccount:account];// + [self attachmentsLengthForAccount:account];
	NSLog(@"Remaining = %d (textlen = %d)", remaining, [text length]);
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
		NSLog(@"HI TWITTER");
		if (remaining < 0) {
			NSString *limited;
			
			NSLog(@"THIS BETTER BE NULL %@", [self attachment]);
			TBLimitTweet(([self attachment] ? 93 : 116) - (Twitter6x() ? 3 : 0), text, &limited, NULL);
			
			NSURLRequest *request = TBPastieRequest(text);
			[NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error){
				NSLog(@"k %@", [[response URL] absoluteString]);
				if (data != nil) {
					TBInstapaperMobilize([[response URL] absoluteString], ^(NSString *pastie_link){
						NSLog(@"pastie_link = %@", pastie_link);
						NSString *res = [limited stringByAppendingString:[@"... " stringByAppendingString:pastie_link]];
						NSLog(@"got res! %@ %d", res, [res length]);
						if ([self attachment]) res = [res stringByAppendingString:@":"];
						[self setText:res];
						
						[self sendFromAccount:account];
					});
				}
				
				else {
					UIAlertView *failed = [[[%c(UIAlertView) alloc] init] autorelease];
					[failed setTitle:@"TweetAmplius"];
					[failed setMessage:@"Request to pastie.org has failed."];
					[failed addButtonWithTitle:@"Dismiss"];
					[failed show];
				}
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
/* }}} */

%ctor {
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	
	NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
	if ([bundleID isEqualToString:@"com.tapbots.Tweetbot"] || [bundleID isEqualToString:@"com.tapbots.TweetbotPad"] || [bundleID isEqualToString:@"com.tapbots.Tweetbot3"]) {
		isTweetbot3 = [bundleID isEqualToString:@"com.tapbots.Tweetbot3"];
		%init(TBTweetbot);
	}
	else if ([bundleID isEqualToString:@"com.atebits.Tweetie2"])
		%init(TBTwitter);
	
	[pool drain];
}
