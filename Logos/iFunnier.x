#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// --- PREFERENCES ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFBlockUpsells @"kIFBlockUpsells"
#define kIFNoWatermark @"kIFNoWatermark"

// --- PREMIUM SPOOFER ---
%group PremiumSpoofer

// 1. MASTER SWITCH
// Class: Premium.PremiumStatusServiceImpl
%hook PremiumStatusServiceImpl

// Force "isActive" to YES (1). This tricks the app into thinking you bought Premium.
- (BOOL)isActive {
    return YES; 
}

%end

// 2. FEATURES MANAGER
// Class: Premium.PremiumFeaturesServiceImpl
// This handles specific perks. We force all feature checks to return YES.
%hook PremiumFeaturesServiceImpl

- (BOOL)isFeatureEnabled:(id)arg1 {
    return YES;
}

- (BOOL)isEnabled:(id)arg1 {
    return YES;
}

// Fallback for simple property checks
- (BOOL)hasPremiumFeatures {
    return YES;
}

%end

// 3. APP ICONS (Bonus)
// Class: Premium.PremiumAppIconsServiceImpl
%hook PremiumAppIconsServiceImpl
- (BOOL)canChangeAppIcon {
    return YES; 
}
%end

%end

// --- AD BLOCKING (SDK Removal) ---
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

// --- VIDEO SAVER ---
static NSURL *gLastPlayedURL = nil;

%hook AVPlayer
- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    %orig;
    if (item && [item.asset isKindOfClass:[AVURLAsset class]]) {
        gLastPlayedURL = [(AVURLAsset *)item.asset URL];
    }
}
%end

// --- SHARE SHEET (Download Button) ---
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
    %init(UICleaner);
    
    // --- Initialize Premium Hooks Safely ---
    
    // 1. Status Service
    Class statusClass = objc_getClass("Premium.PremiumStatusServiceImpl");
    if (!statusClass) statusClass = objc_getClass("PremiumStatusServiceImpl");
    
    // 2. Features Service
    Class featuresClass = objc_getClass("Premium.PremiumFeaturesServiceImpl");
    if (!featuresClass) featuresClass = objc_getClass("PremiumFeaturesServiceImpl");
    
    // 3. Icons Service
    Class iconsClass = objc_getClass("Premium.PremiumAppIconsServiceImpl");
    if (!iconsClass) iconsClass = objc_getClass("PremiumAppIconsServiceImpl");

    // Init the group with whatever classes we found
    if (statusClass || featuresClass) {
        %init(PremiumSpoofer, 
              PremiumStatusServiceImpl = statusClass, 
              PremiumFeaturesServiceImpl = featuresClass,
              PremiumAppIconsServiceImpl = iconsClass);
    }
    
    // Set Default Preferences
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];
}
