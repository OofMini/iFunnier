#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <os/log.h>

// --- PREFERENCES ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFBlockUpsells @"kIFBlockUpsells"
#define kIFNoWatermark @"kIFNoWatermark"

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
    if (!gLastPlayedURL) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [NSData dataWithContentsOfURL:gLastPlayedURL];
        if (data) {
            NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"if_%@.mp4", [[NSUUID UUID] UUIDString]]];
            [data writeToFile:path atomically:YES];
            UISaveVideoAtPathToSavedPhotosAlbum(path, nil, nil, nil);
        }
    });
    [self activityDidFinish:YES];
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
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Restart Required" message:@"Restart iFunny to apply." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Close App Now" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { exit(0); }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
@end

// ==========================================================
// 2. NETWORK INTERCEPTION (Fake Server Response)
// ==========================================================
%group NetworkHook
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    NSURL *url = request.URL;
    NSString *str = url.absoluteString;
    
    // Check for premium/subscription validation endpoints
    if ([str containsString:@"premium"] || [str containsString:@"subscription"] || [str containsString:@"billing"]) {
        NSLog(@"[iFunnier] Intercepted Request: %@", str);
        
        // Fake JSON response saying "Yes, they are premium"
        NSDictionary *fakeResponse = @{
            @"is_premium": @YES,
            @"subscription_active": @YES,
            @"video_save_enabled": @YES,
            @"no_ads": @YES
        };
        
        NSData *data = [NSJSONSerialization dataWithJSONObject:fakeResponse options:0 error:nil];
        NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
        
        if (handler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                handler(data, resp, nil);
            });
        }
        return nil; // Block real request
    }
    return %orig;
}
%end
%end

// ==========================================================
// 3. SETTINGS MENU
// ==========================================================
%group MenuHook
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
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[iFunnierSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]];
    [(UIViewController *)self presentViewController:nav animated:YES completion:nil];
}
%end
%end

// ==========================================================
// 4. REMOTE CONFIG (Google/Firebase)
// ==========================================================
%group RemoteConfigHook
%hook FIRRemoteConfig
- (id)configValueForKey:(NSString *)key {
    if ([key containsString:@"premium"] || [key containsString:@"video"] || [key containsString:@"save"]) {
        return [NSNumber numberWithBool:YES];
    }
    return %orig;
}
%end
%end

// ==========================================================
// 5. SERVICE HOOKS (Backends)
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
- (BOOL)isEntryPointEnabled:(NSInteger)e { return YES; }
%end
%end

%group VideoHook
%hook VideoSaveEnableServiceImpl
- (BOOL)isEnabled { return YES; }
- (BOOL)isVideoSaveEnabled { return YES; }
- (void)setIsVideoSaveEnabled:(BOOL)enabled { %orig(YES); } // Setter Hook
- (BOOL)canSaveVideo { return YES; }
- (BOOL)shouldShowUpsell { return NO; }
+ (instancetype)shared { // Singleton Hook
    id shared = %orig;
    if ([shared respondsToSelector:@selector(setIsVideoSaveEnabled:)]) {
        [shared performSelector:@selector(setIsVideoSaveEnabled:) withObject:@YES];
    }
    return shared;
}
%end
%end

%group OfferHook
%hook LimitedTimeOfferServiceImpl
- (BOOL)shouldShowOffer { return NO; }
- (BOOL)isEnabled { return NO; }
%end
%end

%group PurchaseHook
%hook PremiumPurchaseManagerImpl
- (BOOL)hasActiveSubscription { return YES; }
- (BOOL)isSubscriptionActive { return YES; }
- (id)activeSubscription { return nil; }
%end
%end

%group IconsHook
%hook PremiumAppIconsServiceImpl
- (BOOL)canChangeAppIcon { return YES; }
- (BOOL)isAppIconChangeEnabled { return YES; }
%end
%end

// ==========================================================
// 6. AD BLOCKER
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
%hook GADMobileAds
- (void)startWithCompletionHandler:(id)arg1 { }
%end
%hook ISNativeAd
- (void)loadAd { }
%end
%hook IronSource
+ (void)initWithAppKey:(id)arg1 { }
%end
%hook PAGBannerAd
- (void)loadAd:(id)a { }
%end
%hook PAGNativeAd
- (void)loadAd:(id)a { }
%end
%end

// ==========================================================
// 7. SHARE SHEET & VIDEO SAVER (Direct Hook)
// ==========================================================
%group BackupVideo
%hook AVPlayer
- (void)replaceCurrentItemWithPlayerItem:(id)item {
    %orig;
    if (item && [item respondsToSelector:@selector(asset)]) {
        id asset = [item performSelector:@selector(asset)];
        Class urlAssetClass = objc_getClass("AVURLAsset");
        if (asset && urlAssetClass && [asset isKindOfClass:urlAssetClass]) {
            if ([asset respondsToSelector:@selector(URL)]) {
                gLastPlayedURL = [asset performSelector:@selector(URL)];
            }
        }
    }
}
%end

%hook UIActivityViewController
- (instancetype)initWithActivityItems:(NSArray *)items applicationActivities:(NSArray *)activities {
    NSMutableArray *filtered = [NSMutableArray array];
    // Remove locked/premium activities
    for (UIActivity *activity in activities) {
        NSString *title = activity.activityTitle;
        if (![title containsString:@"Premium"] && ![title containsString:@"Upgrade"]) {
            [filtered addObject:activity];
        }
    }
    // Add our UNLOCKED download activity
    [filtered addObject:[[IFDownloadActivity alloc] init]];
    return %orig(items, filtered);
}
%end
%end

// ==========================================================
// 8. ROBUST INITIALIZATION (With Ghost Class Detection)
// ==========================================================
static Class FindSwiftClass(NSString *name) {
    Class cls = objc_getClass([name UTF8String]);
    if (cls) return cls;
    
    NSArray *modules = @[@"Premium", @"iFunny", @"iFunnyApp", @"Core"];
    for (NSString *module in modules) {
        NSString *fullName = [NSString stringWithFormat:@"%@.%@", module, name];
        cls = objc_getClass([fullName UTF8String]);
        if (cls) return cls;
    }
    
    NSString *mangled = [NSString stringWithFormat:@"_TtC7Premium%lu%@", (unsigned long)name.length, name];
    cls = objc_getClass([mangled UTF8String]);
    if (cls) return cls;

    return nil;
}

%ctor {
    // 1. CLEAR CACHE (Persistence Busting)
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"premium_status"];
    [d removeObjectForKey:@"subscription_status"];
    [d removeObjectForKey:@"video_save_enabled"];
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];
    [d synchronize];

    // 2. INIT HOOKS IMMEDIATELY (Don't wait for didFinishLaunching)
    if ([d boolForKey:kIFBlockAds]) %init(AdBlocker);
    %init(BackupVideo); // Share Sheet Hook
    %init(NetworkHook); // Server Fake Hook

    // 3. FIND CLASSES
    Class statusCls = FindSwiftClass(@"PremiumStatusServiceImpl");
    if (statusCls) %init(StatusHook, PremiumStatusServiceImpl = statusCls);

    Class featuresCls = FindSwiftClass(@"PremiumFeaturesServiceImpl");
    if (featuresCls) %init(FeaturesHook, PremiumFeaturesServiceImpl = featuresCls);

    Class videoCls = FindSwiftClass(@"VideoSaveEnableServiceImpl");
    if (videoCls) %init(VideoHook, VideoSaveEnableServiceImpl = videoCls);
    
    Class offerCls = FindSwiftClass(@"LimitedTimeOfferServiceImpl");
    if (offerCls) %init(OfferHook, LimitedTimeOfferServiceImpl = offerCls);

    Class purchaseCls = FindSwiftClass(@"PremiumPurchaseManagerImpl");
    if (purchaseCls) %init(PurchaseHook, PremiumPurchaseManagerImpl = purchaseCls);

    Class iconsCls = FindSwiftClass(@"PremiumAppIconsServiceImpl");
    if (iconsCls) %init(IconsHook, PremiumAppIconsServiceImpl = iconsCls);
    
    Class rcCls = objc_getClass("FIRRemoteConfig");
    if (rcCls) %init(RemoteConfigHook, FIRRemoteConfig = rcCls);

    // 4. GHOST CLASS HOOK (Late Init)
    %init(GhostClassHook);
}

// 5. GHOST CLASS HOOK (Catches classes as they load)
%group GhostClassHook
%hook NSObject
+ (void)initialize {
    %orig;
    const char *cName = class_getName(self);
    if (!cName) return;
    
    // Only verify "VideoSave" related classes
    if (strstr(cName, "VideoSaveEnableServiceImpl")) {
        NSLog(@"[iFunnier] Ghost Class Caught: %s", cName);
        %init(VideoHook, VideoSaveEnableServiceImpl = self);
    }
    // Only verify "Menu" classes (UI)
    if (strstr(cName, "MenuViewController") && strstr(cName, "Menu")) {
        %init(MenuHook, MenuViewController = self);
    }
}
%end
%end
