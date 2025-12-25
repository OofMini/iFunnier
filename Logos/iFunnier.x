#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// --- PREFERENCES ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFBlockUpsells @"kIFBlockUpsells"
#define kIFNoWatermark @"kIFNoWatermark"

// Global flag to avoid double-initialization
static BOOL gHooksInitialized = NO;

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
// 6. NUCLEAR AD BLOCKER (Updated for AppLovin MAX)
// ==========================================================
%group AdBlocker

// --- AppLovin (Legacy) ---
%hook ALAdService
- (void)loadNextAd:(id)a andNotify:(id)b { }
%end

// --- AppLovin MAX (Newer SDK) ---
// iFunny now uses 'MA' prefixed classes for ads
%hook MARequestManager
- (void)loadAdWithAdUnitIdentifier:(id)id { }
%end
%hook MAAdLoader
- (void)loadAd:(id)ad { }
%end

// --- Google AdMob ---
%hook GADBannerView
- (void)loadRequest:(id)arg1 { }
%end
%hook GADInterstitialAd
- (void)presentFromRootViewController:(id)arg1 { }
%end

// --- IronSource ---
%hook ISNativeAd
- (void)loadAd { }
%end

%end

// ==========================================================
// 7. VIDEO SAVER HELPER (Backup Strategy)
// ==========================================================
%group BackupVideo
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

%hook UIActivityViewController
- (instancetype)initWithActivityItems:(NSArray *)items applicationActivities:(NSArray *)activities {
    NSMutableArray *newActivities = [NSMutableArray arrayWithArray:activities];
    // Note: IFDownloadActivity implementation is assumed to be below or in a separate file
    // For this single-file fix, we assume the class definition exists as in previous versions
    return %orig(items, newActivities);
}
%end
%end

// --- Helper for IFDownloadActivity ---
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


// ==========================================================
// LATE INITIALIZATION (The Fix)
// ==========================================================
%group AppLifecycle
%hook UIApplication
- (void)didFinishLaunching {
    %orig;
    
    if (gHooksInitialized) return;
    gHooksInitialized = YES;

    // Initialize Ad Blockers
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kIFBlockAds]) {
        %init(AdBlocker);
    }
    
    // Initialize Backup Video Saver
    %init(BackupVideo);

    // --- Dynamic Class Lookup ---
    // Now that the app has launched, Frameworks should be loaded.

    Class statusCls = objc_getClass("Premium.PremiumStatusServiceImpl");
    if (!statusCls) statusCls = objc_getClass("PremiumStatusServiceImpl");
    if (statusCls) %init(StatusHook, PremiumStatusServiceImpl = statusCls);

    Class featuresCls = objc_getClass("Premium.PremiumFeaturesServiceImpl");
    if (!featuresCls) featuresCls = objc_getClass("PremiumFeaturesServiceImpl");
    if (featuresCls) %init(FeaturesHook, PremiumFeaturesServiceImpl = featuresCls);

    Class videoCls = objc_getClass("Premium.VideoSaveEnableServiceImpl");
    if (!videoCls) videoCls = objc_getClass("VideoSaveEnableServiceImpl");
    if (videoCls) %init(VideoHook, VideoSaveEnableServiceImpl = videoCls);

    Class purchaseCls = objc_getClass("Premium.PremiumPurchaseManagerImpl");
    if (!purchaseCls) purchaseCls = objc_getClass("PremiumPurchaseManagerImpl");
    if (purchaseCls) %init(PurchaseHook, PremiumPurchaseManagerImpl = purchaseCls);

    Class iconsCls = objc_getClass("Premium.PremiumAppIconsServiceImpl");
    if (!iconsCls) iconsCls = objc_getClass("PremiumAppIconsServiceImpl");
    if (iconsCls) %init(IconsHook, PremiumAppIconsServiceImpl = iconsCls);
}
%end
%end

%ctor {
    // 1. Initialize Default Preferences
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];

    // 2. Only init the Lifecycle hook at startup.
    // The rest will load when the app finishes launching.
    %init(AppLifecycle);
}