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
- (BOOL)isActive { return YES; }
%end

// 2. FEATURES MANAGER
// Class: Premium.PremiumFeaturesServiceImpl
%hook PremiumFeaturesServiceImpl
- (BOOL)isFeatureEnabled:(id)arg1 { return YES; }
- (BOOL)isEnabled:(id)arg1 { return YES; }
- (BOOL)hasPremiumFeatures { return YES; }
%end

// 3. APP ICONS
// Class: Premium.PremiumAppIconsServiceImpl
%hook PremiumAppIconsServiceImpl
- (BOOL)canChangeAppIcon { return YES; }
- (BOOL)isAppIconChangeEnabled { return YES; }
%end

// 4. VIDEO SAVING (Native)
// Class: Premium.VideoSaveEnableServiceImpl
%hook VideoSaveEnableServiceImpl
- (BOOL)isEnabled { return YES; }
- (BOOL)isVideoSaveEnabled { return YES; }
- (BOOL)canSaveVideo { return YES; }
%end

// 5. VERIFICATION (Safety Net)
// Class: Premium.PremiumVerificationServiceImpl
%hook PremiumVerificationServiceImpl
- (BOOL)isVerified { return YES; }
- (BOOL)hasValidReceipt { return YES; }
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

// --- CUSTOM VIDEO SAVER (Backup Strategy) ---
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
    // 1. Initialize Ungrouped Hooks (Video Saver & Share Sheet)
    %init;
    
    // 2. Initialize Ad Blockers
    %init(UICleaner);
    
    // 3. Initialize Premium Hooks Dynamically
    
    // Find Classes
    Class statusClass = objc_getClass("Premium.PremiumStatusServiceImpl");
    if (!statusClass) statusClass = objc_getClass("PremiumStatusServiceImpl");
    
    Class featuresClass = objc_getClass("Premium.PremiumFeaturesServiceImpl");
    if (!featuresClass) featuresClass = objc_getClass("PremiumFeaturesServiceImpl");
    
    Class iconsClass = objc_getClass("Premium.AppIconsServiceImpl"); // Fixed Typo
    if (!iconsClass) iconsClass = objc_getClass("Premium.PremiumAppIconsServiceImpl");
    if (!iconsClass) iconsClass = objc_getClass("PremiumAppIconsServiceImpl");

    Class videoSaveClass = objc_getClass("Premium.VideoSaveEnableServiceImpl");
    if (!videoSaveClass) videoSaveClass = objc_getClass("VideoSaveEnableServiceImpl");

    Class verifyClass = objc_getClass("Premium.PremiumVerificationServiceImpl");
    if (!verifyClass) verifyClass = objc_getClass("PremiumVerificationServiceImpl");

    // Init Group
    // We pass whatever classes we found. If a class is nil, that specific hook just won't run, preventing crashes.
    if (statusClass) {
        %init(PremiumSpoofer, 
              PremiumStatusServiceImpl = statusClass,
              PremiumFeaturesServiceImpl = featuresClass,
              PremiumAppIconsServiceImpl = iconsClass,
              VideoSaveEnableServiceImpl = videoSaveClass,
              PremiumVerificationServiceImpl = verifyClass);
    }
    
    // Set Default Preferences
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];
}
