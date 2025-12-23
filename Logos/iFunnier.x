#import <UIKit/UIKit.h>

// --- PREFERENCES ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFBlockUpsells @"kIFBlockUpsells"
#define kIFNoWatermark @"kIFNoWatermark"

// --- PREMIUM SPOOFER ---
%group PremiumSpoofer

// 1. MASTER SWITCH
// Class: Premium.PremiumStatusServiceImpl
%hook PremiumStatusServiceImpl
- (BOOL)isActive { return YES; }
%end

// 2. FEATURES MANAGER (Fixed based on your screenshot!)
// Class: Premium.PremiumFeaturesServiceImpl
%hook PremiumFeaturesServiceImpl

// The generic "Is the service on?" check
- (BOOL)isEnabled { return YES; }

// The SPECIFIC feature checks found in your screenshot
- (BOOL)isFeatureAvailable:(NSInteger)feature forPlan:(NSInteger)plan { 
    return YES; 
}

- (BOOL)isFeatureAvailableForAnyPlan:(NSInteger)feature { 
    return YES; 
}

- (BOOL)isEntryPointEnabled:(NSInteger)entryPoint { 
    return YES; 
}

%end

// 3. PURCHASE MANAGER (Safety Net)
// Class: Premium.PremiumPurchaseManagerImpl
%hook PremiumPurchaseManagerImpl
- (BOOL)hasActiveSubscription { return YES; }
- (BOOL)isSubscriptionActive { return YES; }
- (id)activeSubscription { return [NSObject new]; }
%end

// 4. APP ICONS
// Class: Premium.PremiumAppIconsServiceImpl
%hook PremiumAppIconsServiceImpl
- (BOOL)canChangeAppIcon { return YES; }
- (BOOL)isAppIconChangeEnabled { return YES; }
%end

// 5. USER MODEL (Backup)
%hook FNUser
- (BOOL)isPro { return YES; }
- (BOOL)isPremium { return YES; }
%end

%end

// --- AD BLOCKERS & CLEANUP ---
%group UICleaner
%hook ALAdService
- (void)loadNextAd:(id)a andNotify:(id)b { }
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
%end

// --- VIDEO SAVER & SHARE SHEET ---
static NSURL *gLastPlayedURL = nil;

%hook AVPlayer
- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    %orig;
    if (item && [item.asset isKindOfClass:[AVURLAsset class]]) {
        gLastPlayedURL = [(AVURLAsset *)item.asset URL];
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

%ctor {
    // 1. Initialize Ungrouped Hooks (Video Saver)
    %init;

    // 2. Initialize Ad Blockers
    %init(UICleaner);
    
    // 3. Initialize Premium Hooks
    Class statusClass = objc_getClass("Premium.PremiumStatusServiceImpl");
    if (!statusClass) statusClass = objc_getClass("PremiumStatusServiceImpl");

    Class featuresClass = objc_getClass("Premium.PremiumFeaturesServiceImpl");
    if (!featuresClass) featuresClass = objc_getClass("PremiumFeaturesServiceImpl");

    Class purchaseClass = objc_getClass("Premium.PremiumPurchaseManagerImpl");
    if (!purchaseClass) purchaseClass = objc_getClass("PremiumPurchaseManagerImpl");

    Class iconsClass = objc_getClass("Premium.PremiumAppIconsServiceImpl");
    if (!iconsClass) iconsClass = objc_getClass("PremiumAppIconsServiceImpl");
    
    Class userClass = objc_getClass("FNUser");
    if (!userClass) userClass = objc_getClass("iFunnyUser");

    if (statusClass) {
        %init(PremiumSpoofer, 
              PremiumStatusServiceImpl = statusClass,
              PremiumFeaturesServiceImpl = featuresClass,
              PremiumPurchaseManagerImpl = purchaseClass,
              PremiumAppIconsServiceImpl = iconsClass,
              FNUser = userClass);
    }
    
    // Set Default Preferences
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];
}
