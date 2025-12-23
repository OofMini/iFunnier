#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

// --- PREFERENCES ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFBlockUpsells @"kIFBlockUpsells"
#define kIFNoWatermark @"kIFNoWatermark"

// ==========================================================
// 1. PREMIUM STATUS (The Master Switch)
// ==========================================================
%group StatusHook
%hook PremiumStatusServiceImpl
- (BOOL)isActive { return YES; }
%end
%end

// ==========================================================
// 2. PREMIUM FEATURES (The Perks)
// ==========================================================
%group FeaturesHook
%hook PremiumFeaturesServiceImpl
- (BOOL)isEnabled { return YES; }
- (BOOL)isFeatureAvailable:(NSInteger)feature forPlan:(NSInteger)plan { return YES; }
- (BOOL)isFeatureAvailableForAnyPlan:(NSInteger)feature { return YES; }
- (BOOL)isEntryPointEnabled:(NSInteger)entryPoint { return YES; }
%end
%end

// ==========================================================
// 3. VIDEO SAVER (Native Save Button)
// ==========================================================
%group VideoHook
%hook VideoSaveEnableServiceImpl
- (BOOL)isEnabled { return YES; }
- (BOOL)isVideoSaveEnabled { return YES; }
- (BOOL)canSaveVideo { return YES; }
- (BOOL)shouldShowUpsell { return NO; }
%end
%end

// ==========================================================
// 4. PURCHASE MANAGER (Backup Check)
// ==========================================================
%group PurchaseHook
%hook PremiumPurchaseManagerImpl
- (BOOL)hasActiveSubscription { return YES; }
- (BOOL)isSubscriptionActive { return YES; }
- (id)activeSubscription { return [NSObject new]; }
%end
%end

// ==========================================================
// 5. APP ICONS
// ==========================================================
%group IconsHook
%hook PremiumAppIconsServiceImpl
- (BOOL)canChangeAppIcon { return YES; }
- (BOOL)isAppIconChangeEnabled { return YES; }
%end
%end

// ==========================================================
// 6. NUCLEAR AD BLOCKER (All Networks)
// ==========================================================
%group AdBlocker

// --- AppLovin ---
%hook ALAdService
- (void)loadNextAd:(id)a andNotify:(id)b { }
%end
%hook ALAdView
- (void)loadNextAd { }
%end

// --- Google AdMob ---
%hook GADBannerView
- (void)loadRequest:(id)arg1 { }
- (void)setAdUnitID:(id)arg1 { }
%end
%hook GADInterstitialAd
- (void)presentFromRootViewController:(id)arg1 { }
%end
%hook GADMobileAds
- (void)startWithCompletionHandler:(id)arg1 { }
%end

// --- IronSource ---
%hook ISNativeAd
- (void)loadAd { }
%end
%hook IronSource
+ (void)initWithAppKey:(id)arg1 { }
%end

// --- Generic Cleanup ---
%hook PAGBannerAd
- (void)loadAd:(id)a { }
%end
%hook PAGNativeAd
- (void)loadAd:(id)a { }
%end

%end

// ==========================================================
// 7. VIDEO SAVER HELPER (Backup Strategy)
// ==========================================================
// We keep this ungrouped so it ALWAYS loads
static NSURL *gLastPlayedURL = nil;

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

%hook UIActivityViewController
- (instancetype)initWithActivityItems:(NSArray *)items applicationActivities:(NSArray *)activities {
    NSMutableArray *newActivities = [NSMutableArray arrayWithArray:activities];
    [newActivities addObject:[[IFDownloadActivity alloc] init]];
    return %orig(items, newActivities);
}
%end

// ==========================================================
// CONSTRUCTOR (The Logic Fix)
// ==========================================================
%ctor {
    // 1. Initialize Ungrouped Hooks (Video Backup)
    %init;

    // 2. Initialize Ad Blockers (ALWAYS)
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kIFBlockAds]) {
        %init(AdBlocker);
    }
    
    // 3. Helper Block to find classes safely
    // This allows us to init each feature INDEPENDENTLY. 
    // If "Icons" fail, "Ads" and "Premium" will still work.
    
    // --- Status ---
    Class statusCls = objc_getClass("Premium.PremiumStatusServiceImpl");
    if (!statusCls) statusCls = objc_getClass("PremiumStatusServiceImpl");
    if (statusCls) %init(StatusHook, PremiumStatusServiceImpl = statusCls);

    // --- Features ---
    Class featuresCls = objc_getClass("Premium.PremiumFeaturesServiceImpl");
    if (!featuresCls) featuresCls = objc_getClass("PremiumFeaturesServiceImpl");
    if (featuresCls) %init(FeaturesHook, PremiumFeaturesServiceImpl = featuresCls);

    // --- Video ---
    Class videoCls = objc_getClass("Premium.VideoSaveEnableServiceImpl");
    if (!videoCls) videoCls = objc_getClass("VideoSaveEnableServiceImpl");
    if (videoCls) %init(VideoHook, VideoSaveEnableServiceImpl = videoCls);

    // --- Purchase ---
    Class purchaseCls = objc_getClass("Premium.PremiumPurchaseManagerImpl");
    if (!purchaseCls) purchaseCls = objc_getClass("PremiumPurchaseManagerImpl");
    if (purchaseCls) %init(PurchaseHook, PremiumPurchaseManagerImpl = purchaseCls);

    // --- Icons ---
    Class iconsCls = objc_getClass("Premium.PremiumAppIconsServiceImpl");
    if (!iconsCls) iconsCls = objc_getClass("PremiumAppIconsServiceImpl");
    if (iconsCls) %init(IconsHook, PremiumAppIconsServiceImpl = iconsCls);

    // Set Default Preferences if missing
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];
}
