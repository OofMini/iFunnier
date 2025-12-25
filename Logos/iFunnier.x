#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <os/log.h>

// --- PREFERENCES ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFBlockUpsells @"kIFBlockUpsells"
#define kIFNoWatermark @"kIFNoWatermark"

// --- LOGGING MACROS ---
#ifdef DEBUG
#define IFLog(fmt, ...) NSLog(@"[iFunnier] " fmt, ##__VA_ARGS__)
#else
#define IFLog(fmt, ...) // Disabled in release
#endif

// --- THREAD SAFETY ---
static NSLock *gURLLock = nil;
static NSURL *gLastPlayedURL = nil;

// ==========================================================
// 1. HELPER CLASSES
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

    if (!url) {
        [self activityDidFinish:NO];
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (data) {
            NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"if_%@.mp4", [[NSUUID UUID] UUIDString]]];
            [data writeToFile:path atomically:YES];
            UISaveVideoAtPathToSavedPhotosAlbum(path, nil, nil, nil);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self activityDidFinish:YES];
        });
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
    
    UIWindow *window = self.view.window;
    [window addSubview:banner];
    
    [UIView animateWithDuration:0.3 animations:^{ banner.alpha = 1; } completion:^(BOOL f){
        [UIView animateWithDuration:0.3 delay:2.0 options:0 animations:^{ banner.alpha = 0; } completion:^(BOOL f){ [banner removeFromSuperview]; }];
    }];
}
@end

// ==========================================================
// 2. OPTIMIZED HELPERS
// ==========================================================
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
// 3. NETWORK INTERCEPTION
// ==========================================================
%group NetworkHook
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    NSString *str = request.URL.absoluteString;
    
    if ([str containsString:@"premium"] || [str containsString:@"subscription"] || [str containsString:@"billing"]) {
        IFLog("Intercepted: %@", str);
        
        NSURLSessionDataTask *dummy = %orig(request, ^(NSData *d, NSURLResponse *r, NSError *e){});
        
        NSDictionary *fake = @{
            @"is_premium": @YES, @"subscription_active": @YES,
            @"video_save_enabled": @YES, @"no_ads": @YES,
            @"watermark_removal": @YES
        };
        NSData *data = [NSJSONSerialization dataWithJSONObject:fake options:0 error:nil];
        NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
        
        if (handler) {
            dispatch_async(dispatch_get_main_queue(), ^{ handler(data, resp, nil); });
        }
        return dummy;
    }
    return %orig;
}
%end
%end

// ==========================================================
// 4. MENU HOOKS
// ==========================================================
%group MenuHookStatic
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
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
    } else {
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    [(UIViewController *)self presentViewController:nav animated:YES completion:nil];
}
%end
%end

%group MenuHookDynamic
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
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
    } else {
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    [(UIViewController *)self presentViewController:nav animated:YES completion:nil];
}
%end
%end

// ==========================================================
// 5. USER & SIDEBAR HOOKS (NEW!)
// ==========================================================
%group UserHook
%hook FNUser // Helper for User Model
- (BOOL)isPremium { return YES; }
- (BOOL)isPro { return YES; }
- (BOOL)hasSubscription { return YES; }
// Force the Sidebar Label
- (NSString *)subscriptionStatusText { return @"Lifetime Subscription"; }
- (NSString *)premiumStatusTitle { return @"Lifetime Premium"; }
%end

%hook UserProfile
- (BOOL)isPremium { return YES; }
- (NSString *)subscriptionTitle { return @"Lifetime"; }
%end
%end

// ==========================================================
// 6. VIDEO SAVER HOOKS
// ==========================================================
%group VideoHookStatic
%hook VideoSaveEnableServiceImpl
- (BOOL)isEnabled { return YES; }
- (BOOL)isVideoSaveEnabled { return YES; }
- (void)setIsVideoSaveEnabled:(BOOL)enabled { %orig(YES); }
- (BOOL)canSaveVideo { return YES; }
- (BOOL)shouldShowUpsell { return NO; }
// Force No Watermark
- (BOOL)isWatermarkRemovalEnabled { return YES; }
+ (instancetype)shared {
    id shared = %orig;
    if ([shared respondsToSelector:@selector(setIsVideoSaveEnabled:)]) {
        [shared performSelector:@selector(setIsVideoSaveEnabled:) withObject:@YES];
    }
    return shared;
}
%end
%end

%group VideoHookDynamic
%hook VideoSaveEnableServiceImpl
- (BOOL)isEnabled { return YES; }
- (BOOL)isVideoSaveEnabled { return YES; }
- (void)setIsVideoSaveEnabled:(BOOL)enabled { %orig(YES); }
- (BOOL)canSaveVideo { return YES; }
- (BOOL)shouldShowUpsell { return NO; }
- (BOOL)isWatermarkRemovalEnabled { return YES; }
+ (instancetype)shared {
    id shared = %orig;
    if ([shared respondsToSelector:@selector(setIsVideoSaveEnabled:)]) {
        [shared performSelector:@selector(setIsVideoSaveEnabled:) withObject:@YES];
    }
    return shared;
}
%end
%end

// ==========================================================
// 7. POPUP & AD KILLERS
// ==========================================================
%group PopupKiller
// Kill Feed Popup
%hook InAppMessageService
- (BOOL)shouldShowMessage:(id)arg1 { return NO; }
%end

%hook OverlayManager
- (void)showOverlay:(id)arg1 { }
%end

%hook LimitedTimeOfferServiceImpl
- (BOOL)shouldShowOffer { return NO; }
- (BOOL)isEnabled { return NO; }
%end
%end

// ==========================================================
// 8. OTHER SERVICE HOOKS
// ==========================================================
%group StatusHook
%hook PremiumStatusServiceImpl
- (BOOL)isActive { return YES; }
%end
%end

%group FeaturesHook
%hook PremiumFeaturesServiceImpl
- (BOOL)isEnabled { return YES; }
- (BOOL)isFeatureAvailable:(NSInteger)f forPlan:(NSInteger)p { return YES; }
- (BOOL)isFeatureAvailableForAnyPlan:(NSInteger)f { return YES; }
// Fix for "No Watermark" specific feature flag
- (BOOL)isFeatureEnabled:(NSInteger)f { return YES; }
%end
%end

%group PurchaseHook
%hook PremiumPurchaseManagerImpl
- (BOOL)hasActiveSubscription { return YES; }
- (BOOL)isSubscriptionActive { return YES; }
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

%group IconsHook
%hook PremiumAppIconsServiceImpl
- (BOOL)canChangeAppIcon { return YES; }
- (BOOL)isAppIconChangeEnabled { return YES; }
%end
%end

// ==========================================================
// 9. AD BLOCKER
// ==========================================================
%group AdBlocker
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
%hook ISNativeAd
- (void)loadAd { }
%end
%hook PAGBannerAd
- (void)loadAd:(id)a { }
%end
%hook PAGNativeAd
- (void)loadAd:(id)a { }
%end
// Block Native Feed Ads
%hook FNFeedNativeAdCell
- (void)layoutSubviews {
    self.hidden = YES; 
    self.alpha = 0;
}
%end
%end

// ==========================================================
// 10. TARGETED UI HOOKS
// ==========================================================
%group UIHacks
%hook UIButton
- (void)layoutSubviews {
    %orig;
    if (!self.superview) return;
    
    // Unhide Save/Share buttons
    if ([self.accessibilityIdentifier containsString:@"save"] || [self.accessibilityIdentifier containsString:@"share"]) {
        self.enabled = YES;
        self.userInteractionEnabled = YES;
        self.alpha = 1.0;
        
        // Aggressive Lock Removal
        for (UIView *subview in self.subviews) {
            // Check Accessibility ID
            if ([[subview accessibilityIdentifier] containsString:@"lock"]) {
                subview.hidden = YES;
            }
            // Check Image Name
            if ([subview isKindOfClass:[UIImageView class]]) {
                UIImageView *img = (UIImageView *)subview;
                if ([[img.image accessibilityIdentifier] containsString:@"lock"]) {
                    img.hidden = YES;
                }
            }
        }
    }
}
%end
%end

// ==========================================================
// 11. JAILBREAK BYPASS
// ==========================================================
%group JBDectionBypass
%hook NSFileManager
- (BOOL)fileExistsAtPath:(NSString *)path {
    if ([path containsString:@"cydia"] || [path containsString:@"substrate"] || [path containsString:@"/bin/bash"]) return NO;
    return %orig;
}
%end
%hook UIApplication
- (BOOL)canOpenURL:(NSURL *)url {
    if ([url.scheme isEqualToString:@"cydia"] || [url.scheme isEqualToString:@"sileo"]) return NO;
    return %orig;
}
%end
%end

// ==========================================================
// 12. SHARE SHEET
// ==========================================================
%group BackupVideo
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
        if (![activity.activityTitle containsString:@"Premium"]) {
            [filtered addObject:activity];
        }
    }
    [filtered addObject:[[IFDownloadActivity alloc] init]];
    return %orig(items, filtered);
}
%end
%end

// ==========================================================
// 13. GHOST HOOK
// ==========================================================
%group GhostClassHook
%hook NSObject
+ (void)initialize {
    %orig;
    const char *cName = class_getName(self);
    if (!cName || cName[0] != '_' || !strstr(cName, "Premium")) return;
    
    if (strstr(cName, "VideoSaveEnableServiceImpl")) {
        IFLog("Ghost Caught: %s", cName);
        %init(VideoHookDynamic, VideoSaveEnableServiceImpl = self);
    }
    if (strstr(cName, "MenuViewController")) {
        %init(MenuHookDynamic, MenuViewController = self);
    }
}
%end
%end

%ctor {
    gURLLock = [[NSLock alloc] init];
    
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"premium_status"];
    
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];
    
    %init(BackupVideo);
    %init(NetworkHook);
    %init(JBDectionBypass);
    %init(UIHacks);
    
    if ([d boolForKey:kIFBlockAds]) %init(AdBlocker);

    // Initialization Logic
    
    Class c;
    
    c = FindSwiftClass(@"PremiumStatusServiceImpl");
    if (c) %init(StatusHook, PremiumStatusServiceImpl = c);
    
    c = FindSwiftClass(@"PremiumFeaturesServiceImpl");
    if (c) %init(FeaturesHook, PremiumFeaturesServiceImpl = c);
    
    // Video Saver
    c = FindSwiftClass(@"VideoSaveEnableServiceImpl");
    if (c) %init(VideoHookStatic, VideoSaveEnableServiceImpl = c);
    
    // Popups
    c = FindSwiftClass(@"LimitedTimeOfferServiceImpl");
    if (c) %init(PopupKiller, LimitedTimeOfferServiceImpl = c);
    // Try to find generic popup managers
    Class msgSvc = objc_getClass("InAppMessageService"); 
    if (msgSvc) %init(PopupKiller, InAppMessageService = msgSvc);
    
    c = FindSwiftClass(@"PremiumPurchaseManagerImpl");
    if (c) %init(PurchaseHook, PremiumPurchaseManagerImpl = c);
    
    c = FindSwiftClass(@"PremiumAppIconsServiceImpl");
    if (c) %init(IconsHook, PremiumAppIconsServiceImpl = c);
    
    // User / Sidebar
    Class userCls = FindSwiftClass(@"FNUser");
    if (userCls) %init(UserHook, FNUser = userCls);
    
    // Menu
    c = FindSwiftClass(@"MenuViewController");
    if (!c) c = objc_getClass("MenuViewController");
    if (c) %init(MenuHookStatic, MenuViewController = c);
    
    // Remote Config
    Class rc = objc_getClass("FIRRemoteConfig");
    if (rc) %init(RemoteConfigHook, FIRRemoteConfig = rc);
    
    %init(GhostClassHook);
}
