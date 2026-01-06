#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <StoreKit/StoreKit.h>

// --- PREFERENCES ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFBlockUpsells @"kIFBlockUpsells"
#define kIFNoWatermark @"kIFNoWatermark"

// --- THREAD SAFETY ---
static NSLock *gURLLock = nil;
static NSURL *gLastPlayedURL = nil;

// ==========================================================
// 1. HELPER CLASSES & FUNCTIONS
// ==========================================================
@interface IFDownloadActivity : UIActivity @end
@implementation IFDownloadActivity
- (UIActivityType)activityType { return @"com.ifunnier.download"; }
- (NSString *)activityTitle { return @"Download Video"; }
- (UIImage *)activityImage { return [UIImage systemImageNamed:@"arrow.down.circle.fill"]; }
- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems { return YES; }
- (void)performActivity {
    [gURLLock lock];
    NSURL *url = gLastPlayedURL;
    [gURLLock unlock];

    if (!url) { [self activityDidFinish:NO]; return; }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (data) {
            NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"if_%@.mp4", [[NSUUID UUID] UUIDString]]];
            [data writeToFile:path atomically:YES];
            UISaveVideoAtPathToSavedPhotosAlbum(path, nil, nil, nil);
        }
        dispatch_async(dispatch_get_main_queue(), ^{ [self activityDidFinish:YES]; });
    });
}
+ (UIActivityCategory)activityCategory { return UIActivityCategoryAction; }
@end

@interface iFunnierSettingsViewController : UITableViewController @end
@implementation iFunnierSettingsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"iFunnier Control";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 3; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *sw = [UISwitch new];
    sw.tag = indexPath.row;
    [sw addTarget:self action:@selector(t:) forControlEvents:UIControlEventValueChanged];
    
    NSString *txt = (indexPath.row==0)?@"Block Ads":(indexPath.row==1)?@"No Watermark":@"Block Upsells";
    NSString *key = (indexPath.row==0)?kIFBlockAds:(indexPath.row==1)?kIFNoWatermark:kIFBlockUpsells;
    cell.textLabel.text = txt;
    [sw setOn:[[NSUserDefaults standardUserDefaults] boolForKey:key] animated:NO];
    cell.accessoryView = sw;
    return cell;
}
- (void)t:(UISwitch *)s {
    NSString *k = (s.tag==0)?kIFBlockAds:(s.tag==1)?kIFNoWatermark:kIFBlockUpsells;
    [[NSUserDefaults standardUserDefaults] setBool:s.isOn forKey:k];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    UILabel *banner = [[UILabel alloc] initWithFrame:CGRectMake(0, 50, UIScreen.mainScreen.bounds.size.width, 44)];
    banner.text = @"⚠️ Restart iFunny to apply changes";
    banner.backgroundColor = [UIColor systemOrangeColor];
    banner.textAlignment = NSTextAlignmentCenter;
    banner.textColor = [UIColor whiteColor];
    banner.alpha = 0;
    [self.view.window addSubview:banner];
    [UIView animateWithDuration:0.3 animations:^{ banner.alpha = 1; } completion:^(BOOL f){
        [UIView animateWithDuration:0.3 delay:2.0 options:0 animations:^{ banner.alpha = 0; } completion:^(BOOL f){ [banner removeFromSuperview]; }];
    }];
}
@end

static BOOL IsAdItem(id item) {
    if (!item) return NO;
    NSString *cls = NSStringFromClass([item class]);
    if ([cls containsString:@"Ad"] || [cls containsString:@"Sponsored"] || [cls containsString:@"Native"]) return YES;
    if ([item respondsToSelector:@selector(isAd)]) { if ([[item performSelector:@selector(isAd)] boolValue]) return YES; }
    if ([item respondsToSelector:@selector(isSponsored)]) { if ([[item performSelector:@selector(isSponsored)] boolValue]) return YES; }
    return NO;
}

static Class FindSwiftClass(NSString *name) {
    static NSMutableDictionary *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [NSMutableDictionary dictionary]; });
    if (cache[name]) return cache[name];
    
    Class cls = objc_getClass([name UTF8String]);
    if (!cls) {
        NSArray *modules = @[@"Premium", @"iFunny", @"iFunnyApp", @"Core", @"libiFunny", @"User"];
        for (NSString *module in modules) {
            NSString *full = [NSString stringWithFormat:@"%@.%@", module, name];
            cls = objc_getClass([full UTF8String]);
            if (cls) break;
        }
    }
    if (!cls) {
        NSString *mangled = [NSString stringWithFormat:@"_TtC7Premium%lu%@", (unsigned long)name.length, name];
        cls = objc_getClass([mangled UTF8String]);
    }
    if (cls) cache[name] = cls;
    return cls;
}

// ==========================================================
// 2. CORE LOGIC (Network & User Model)
// ==========================================================
%group CoreLogic

// Network Interception
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    NSString *str = request.URL.absoluteString;
    if ([str containsString:@"premium"] || [str containsString:@"subscription"] || [str containsString:@"billing"]) {
        NSURLSessionDataTask *dummy = %orig(request, ^(NSData *d, NSURLResponse *r, NSError *e){});
        NSDictionary *fake = @{ @"is_premium": @YES, @"subscription_active": @YES, @"video_save_enabled": @YES, @"no_ads": @YES, @"watermark_removal": @YES };
        NSData *data = [NSJSONSerialization dataWithJSONObject:fake options:0 error:nil];
        NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
        if (handler) dispatch_async(dispatch_get_main_queue(), ^{ handler(data, resp, nil); });
        return dummy;
    }
    return %orig;
}
%end

// JSON Injection
%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    id json = %orig;
    if ([json isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *mutable = [json mutableCopy];
        if (mutable[@"data"] && mutable[@"data"][@"user"]) {
            NSMutableDictionary *user = [mutable[@"data"][@"user"] mutableCopy];
            user[@"isPremium"] = @YES;
            mutable[@"data"] = [@{@"user": user} mutableCopy];
            return mutable;
        }
    }
    return json;
}
%end

// User Model
%hook FNUser
- (BOOL)isPremium { return YES; }
- (BOOL)isPro { return YES; }
- (BOOL)hasSubscription { return YES; }
- (NSString *)subscriptionStatusText { return @"Lifetime Subscription"; }
- (NSInteger)featureFlags { return 0xFFFFFF; } 
- (NSInteger)entitlements { return NSIntegerMax; }
%end

%hook UserProfile
- (BOOL)isPremium { return YES; }
- (NSString *)subscriptionTitle { return @"Lifetime"; }
%end

// State Restoration
%hook NSKeyedUnarchiver
+ (id)unarchivedObjectOfClass:(Class)cls fromData:(NSData *)data error:(NSError **)error {
    id obj = %orig;
    if ([obj respondsToSelector:@selector(isPremium)]) {
        @try { [obj setValue:@YES forKey:@"isPremium"]; } @catch(NSException *e) {}
    }
    return obj;
}
%end
%end

// ==========================================================
// 3. FEED LOGIC
// ==========================================================
%group FeedLogic
%hook FeedDataProvider
- (NSArray *)items {
    NSArray *orig = %orig;
    NSMutableArray *clean = [NSMutableArray array];
    for (id item in orig) { if (!IsAdItem(item)) [clean addObject:item]; }
    return clean;
}
- (void)setItems:(NSArray *)items {
    NSMutableArray *clean = [NSMutableArray array];
    for (id item in items) { if (!IsAdItem(item)) [clean addObject:item]; }
    %orig(clean);
}
- (void)loadNextPageWithCompletion:(void (^)(NSArray *, BOOL))completion {
    void (^wrapped)(NSArray *, BOOL) = ^(NSArray *items, BOOL hasMore) {
        NSMutableArray *cleaned = [NSMutableArray array];
        for (id item in items) { if (!IsAdItem(item)) [cleaned addObject:item]; }
        completion(cleaned, hasMore);
    };
    %orig(wrapped);
}
%end

%hook FeedRepository
- (void)fetchItemsWithCompletion:(void (^)(NSArray *, NSError *))completion {
    void (^wrapped)(NSArray *, NSError *) = ^(NSArray *items, NSError *error) {
        if (items) {
            NSMutableArray *clean = [NSMutableArray array];
            for (id item in items) { if (!IsAdItem(item)) [clean addObject:item]; }
            completion(clean, error);
        } else { completion(items, error); }
    };
    %orig(wrapped);
}
%end
%end

// ==========================================================
// 4. POPUP LOGIC
// ==========================================================

// Fix: Define the interface so we can call methods on self
@interface OfferViewController : UIViewController
@end

%group PopupLogic
%hook StartupCoordinator
- (void)start { }
- (void)showOffer { }
- (void)presentOffer:(id)offer { }
%end
%hook ShowOfferCommand
- (BOOL)shouldExecute { return NO; }
- (void)execute { }
%end
%hook OfferViewController
- (void)viewWillAppear:(BOOL)animated { [self dismissViewControllerAnimated:NO completion:nil]; }
%end
%hook UIViewController
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)flag completion:(void (^)(void))completion {
    NSString *name = NSStringFromClass([vc class]);
    if ([name containsString:@"Offer"] || [name containsString:@"Premium"] || [name containsString:@"Upsell"]) {
        if (completion) completion();
        return;
    }
    %orig;
}
%end
%hook NSTimer
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)target selector:(SEL)selector userInfo:(id)userInfo repeats:(BOOL)repeats {
    if (NSStringFromSelector(selector) && ([NSStringFromSelector(selector) containsString:@"showOffer"])) return nil;
    return %orig;
}
%end
%end

// ==========================================================
// 5. FEATURE LOGIC
// ==========================================================
%group FeatureLogic
%hook ExperimentService
- (NSInteger)variantForExperiment:(NSInteger)id { return 1; }
- (BOOL)isEnabled:(NSInteger)id { return YES; }
- (BOOL)isInTreatment:(NSInteger)id { return YES; }
- (NSInteger)experimentBitmask { return NSIntegerMax; }
%end
%hook ConfigService
- (id)valueForKey:(NSString *)key { return @YES; }
- (NSInteger)intValueForKey:(NSString *)key { return 1; }
%end
%hook FIRRemoteConfig
- (id)configValueForKey:(NSString *)key {
    if ([key containsString:@"premium"] || [key containsString:@"video"] || [key containsString:@"save"]) return [NSNumber numberWithBool:YES];
    return %orig;
}
%end
%end

// ==========================================================
// 6. SYSTEM UI HOOKS (System classes)
// ==========================================================
%group SystemUIHooks
// Text Replacer
%hook UILabel
- (void)setText:(NSString *)text {
    if ([text isEqualToString:@"Get Premium"] || [text isEqualToString:@"Upgrade to Premium"]) { %orig(@"Lifetime Subscription"); return; }
    %orig;
}
- (void)setAttributedText:(NSAttributedString *)text {
    if ([text.string containsString:@"Get Premium"]) {
        NSDictionary *attrs = [text attributesAtIndex:0 effectiveRange:nil];
        NSAttributedString *newText = [[NSAttributedString alloc] initWithString:@"Lifetime Subscription" attributes:attrs];
        %orig(newText);
        return;
    }
    %orig;
}
%end

// Lock Icons
%hook CALayer
- (void)setContents:(id)contents {
    if ([contents isKindOfClass:[UIImage class]]) {
        UIImage *img = (UIImage *)contents;
        if ([[img accessibilityIdentifier] containsString:@"lock"]) return;
    }
    %orig;
}
%end
%end

// ==========================================================
// 7. APP UI HOOKS (Static & Dynamic Groups)
// ==========================================================

// STATIC GROUP (Used in ctor)
%group AppUIHooks_Static
%hook SidebarViewModel
- (NSString *)premiumStatusText { return @"Lifetime Subscription"; }
%end
%hook MenuViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    if (vc.navigationItem.rightBarButtonItem && vc.navigationItem.rightBarButtonItem.tag == 999) return;
    UIBarButtonItem *btn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gear"] style:UIBarButtonItemStylePlain target:self action:@selector(openSettings)];
    btn.tag = 999;
    vc.navigationItem.rightBarButtonItem = btn;
}
%new
- (void)openSettings {
    iFunnierSettingsViewController *vc = [[iFunnierSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) nav.modalPresentationStyle = UIModalPresentationFormSheet;
    else nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [(UIViewController *)self presentViewController:nav animated:YES completion:nil];
}
%end
%end

// DYNAMIC GROUP (Duplicate logic for Ghost Hook)
%group AppUIHooks_Dynamic
%hook SidebarViewModel
- (NSString *)premiumStatusText { return @"Lifetime Subscription"; }
%end
%hook MenuViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    if (vc.navigationItem.rightBarButtonItem && vc.navigationItem.rightBarButtonItem.tag == 999) return;
    UIBarButtonItem *btn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gear"] style:UIBarButtonItemStylePlain target:self action:@selector(openSettings)];
    btn.tag = 999;
    vc.navigationItem.rightBarButtonItem = btn;
}
%new
- (void)openSettings {
    iFunnierSettingsViewController *vc = [[iFunnierSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) nav.modalPresentationStyle = UIModalPresentationFormSheet;
    else nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [(UIViewController *)self presentViewController:nav animated:YES completion:nil];
}
%end
%end

// ==========================================================
// 8. AD LOGIC
// ==========================================================
@interface FNFeedNativeAdCell : UICollectionViewCell @end
%group AdLogic
%hook ALAdService
- (void)loadNextAd:(id)a andNotify:(id)b { }
%end
%hook MARequestManager
- (void)loadAdWithAdUnitIdentifier:(id)id { }
%end
%hook MAAdLoader
- (void)loadAd:(id)ad { }
%end
%hook GADBannerView
- (void)loadRequest:(id)arg1 { }
%end
%hook GADInterstitialAd
- (void)presentFromRootViewController:(id)arg1 { }
%end
%hook FNFeedNativeAdCell
- (void)layoutSubviews { self.hidden = YES; self.alpha = 0; }
%end
%end

// ==========================================================
// 9. SHARE LOGIC
// ==========================================================
%group ShareLogic
%hook UIActivityItemProvider
- (id)activityViewController:(UIActivityViewController *)ac itemForActivityType:(UIActivityType)type {
    id item = %orig;
    if (!item && [type containsString:@"save"]) return gLastPlayedURL ?: @"";
    return item;
}
%end
%hook AVPlayer
- (void)replaceCurrentItemWithPlayerItem:(id)item {
    %orig;
    if (item && [item respondsToSelector:@selector(asset)]) {
        id asset = [item performSelector:@selector(asset)];
        if ([asset isKindOfClass:objc_getClass("AVURLAsset")]) {
            NSURL *url = [asset performSelector:@selector(URL)];
            [gURLLock lock];
            gLastPlayedURL = url;
            [gURLLock unlock];
        }
    }
}
%end
%hook UIActivityViewController
- (instancetype)initWithActivityItems:(NSArray *)items applicationActivities:(NSArray *)activities {
    NSMutableArray *filtered = [NSMutableArray array];
    for (UIActivity *activity in activities) {
        if (![activity.activityTitle containsString:@"Premium"]) [filtered addObject:activity];
    }
    [filtered addObject:[[IFDownloadActivity alloc] init]];
    return %orig(items, filtered);
}
%end
%end

// ==========================================================
// 10. LEGACY FALLBACKS (Static & Dynamic Groups)
// ==========================================================

// STATIC
%group LegacyHooks_Static
%hook PremiumStatusServiceImpl
- (BOOL)isActive { return YES; }
%end
%hook PremiumFeaturesServiceImpl
- (BOOL)isEnabled { return YES; }
- (BOOL)isFeatureAvailable:(NSInteger)f forPlan:(NSInteger)p { return YES; }
%end
%hook VideoSaveEnableServiceImpl
- (BOOL)isEnabled { return YES; }
- (BOOL)isVideoSaveEnabled { return YES; }
- (void)setIsVideoSaveEnabled:(BOOL)enabled { %orig(YES); }
- (BOOL)isWatermarkRemovalEnabled { return YES; }
+ (instancetype)shared {
    id shared = %orig;
    if ([shared respondsToSelector:@selector(setIsVideoSaveEnabled:)]) [shared performSelector:@selector(setIsVideoSaveEnabled:) withObject:@YES];
    return shared;
}
%end
%hook PremiumPurchaseManagerImpl
- (BOOL)hasActiveSubscription { return YES; }
- (id)activeSubscription {
    static id mockSub = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class subClass = FindSwiftClass(@"Subscription");
        if (subClass) mockSub = [subClass new];
        else mockSub = [NSObject new];
    });
    return mockSub;
}
%end
%end

// DYNAMIC
%group LegacyHooks_Dynamic
%hook PremiumStatusServiceImpl
- (BOOL)isActive { return YES; }
%end
%hook PremiumFeaturesServiceImpl
- (BOOL)isEnabled { return YES; }
- (BOOL)isFeatureAvailable:(NSInteger)f forPlan:(NSInteger)p { return YES; }
%end
%hook VideoSaveEnableServiceImpl
- (BOOL)isEnabled { return YES; }
- (BOOL)isVideoSaveEnabled { return YES; }
- (void)setIsVideoSaveEnabled:(BOOL)enabled { %orig(YES); }
- (BOOL)isWatermarkRemovalEnabled { return YES; }
+ (instancetype)shared {
    id shared = %orig;
    if ([shared respondsToSelector:@selector(setIsVideoSaveEnabled:)]) [shared performSelector:@selector(setIsVideoSaveEnabled:) withObject:@YES];
    return shared;
}
%end
%hook PremiumPurchaseManagerImpl
- (BOOL)hasActiveSubscription { return YES; }
- (id)activeSubscription {
    static id mockSub = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class subClass = FindSwiftClass(@"Subscription");
        if (subClass) mockSub = [subClass new];
        else mockSub = [NSObject new];
    });
    return mockSub;
}
%end
%end

// ==========================================================
// 11. GHOST HOOK (Lazy Loading)
// ==========================================================
%group GhostLogic
%hook NSObject
+ (void)initialize {
    %orig;
    const char *n = class_getName(self);
    if (!n) return;
    if (strstr(n, "VideoSaveEnableServiceImpl")) %init(LegacyHooks_Dynamic, VideoSaveEnableServiceImpl = self);
    if (strstr(n, "MenuViewController")) %init(AppUIHooks_Dynamic, MenuViewController = self);
}
%end
%end

// ==========================================================
// INITIALIZATION
// ==========================================================
%ctor {
    gURLLock = [[NSLock alloc] init];
    
    // 1. Clear Cache
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"premium_status"];
    
    // 2. Init Core Hooks
    %init(CoreLogic);
    %init(PopupLogic);
    %init(FeatureLogic);
    %init(FeedLogic);
    %init(SystemUIHooks); // System classes (UILabel, etc)
    %init(ShareLogic);
    
    // 3. Init Ads if enabled
    if (![[NSUserDefaults standardUserDefaults] objectForKey:kIFBlockAds]) 
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kIFBlockAds];
        
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kIFBlockAds]) 
        %init(AdLogic);
    
    // 4. Remote Config
    Class rc = objc_getClass("FIRRemoteConfig");
    if (rc) %init(FeatureLogic); // Re-apply for RC
    
    // 5. Try Static Init for App Classes
    Class menu = FindSwiftClass(@"MenuViewController");
    if (menu) %init(AppUIHooks_Static, MenuViewController = menu);
    
    Class vid = FindSwiftClass(@"VideoSaveEnableServiceImpl");
    if (vid) %init(LegacyHooks_Static, VideoSaveEnableServiceImpl = vid);
    
    // 6. Enable Ghost Hook for fallbacks
    %init(GhostLogic);
}
