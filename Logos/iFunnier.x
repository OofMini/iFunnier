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
// 1. SETTINGS MENU UI (Optimized with "Close App")
// ==========================================================
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
    
    NSString *txt = @"";
    NSString *key = @"";
    if (indexPath.row == 0) { txt = @"Block Ads"; key = @"kIFBlockAds"; }
    else if (indexPath.row == 1) { txt = @"No Watermark"; key = @"kIFNoWatermark"; }
    else if (indexPath.row == 2) { txt = @"Block Upsells"; key = @"kIFBlockUpsells"; }
    
    cell.textLabel.text = txt;
    [sw setOn:[[NSUserDefaults standardUserDefaults] boolForKey:key] animated:NO];
    cell.accessoryView = sw;
    return cell;
}
- (void)t:(UISwitch *)s {
    NSString *k = (s.tag==0)?@"kIFBlockAds":(s.tag==1)?@"kIFNoWatermark":@"kIFBlockUpsells";
    [[NSUserDefaults standardUserDefaults] setBool:s.isOn forKey:k];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // UX Optimization: Offer to close the app immediately
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restart Required" 
                                                                   message:@"Changes will take effect after you restart iFunny." 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Close App Now" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        exit(0); // Force close the app for user convenience
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}
@end

// ==========================================================
// 2. SETTINGS BUTTON INJECTION
// ==========================================================
%group MenuHook
%hook MenuViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    if (vc.navigationItem.rightBarButtonItem && vc.navigationItem.rightBarButtonItem.tag == 999) return;
    
    UIBarButtonItem *settingsBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gear"] 
                                                                    style:UIBarButtonItemStylePlain 
                                                                   target:self 
                                                                   action:@selector(openIFunnierSettings)];
    settingsBtn.tag = 999;
    vc.navigationItem.rightBarButtonItem = settingsBtn;
}
%new
- (void)openIFunnierSettings {
    iFunnierSettingsViewController *vc = [[iFunnierSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [(UIViewController *)self presentViewController:nav animated:YES completion:nil];
}
%end
%end

// ==========================================================
// 3. PREMIUM STATUS
// ==========================================================
%group StatusHook
%hook PremiumStatusServiceImpl
- (BOOL)isActive { return YES; }
%end
%end

// ==========================================================
// 4. PREMIUM FEATURES
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
// 5. VIDEO SAVER (Native Button)
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
// 6. PURCHASE MANAGER (Crash Fix)
// ==========================================================
%group PurchaseHook
%hook PremiumPurchaseManagerImpl
- (BOOL)hasActiveSubscription { return YES; }
- (BOOL)isSubscriptionActive { return YES; }
// FIX: Return nil instead of [NSObject new] to prevent crashes if the app reads properties
- (id)activeSubscription { return nil; } 
%end
%end

// ==========================================================
// 7. APP ICONS
// ==========================================================
%group IconsHook
%hook PremiumAppIconsServiceImpl
- (BOOL)canChangeAppIcon { return YES; }
- (BOOL)isAppIconChangeEnabled { return YES; }
%end
%end

// ==========================================================
// 8. NUCLEAR AD BLOCKER (Optimized)
// ==========================================================
%group AdBlocker

// AppLovin (Legacy)
%hook ALAdService
- (void)loadNextAd:(id)a andNotify:(id)b { }
%end

// AppLovin MAX (Modern)
%hook MARequestManager
- (void)loadAdWithAdUnitIdentifier:(id)id { }
%end
%hook MAAdLoader
- (void)loadAd:(id)ad { }
%end

// Google AdMob
%hook GADBannerView
- (void)loadRequest:(id)arg1 { }
%end
%hook GADInterstitialAd
- (void)presentFromRootViewController:(id)arg1 { }
%end
// Block AdMob Initialization
%hook GADMobileAds
- (void)startWithCompletionHandler:(id)arg1 { }
%end

// IronSource
%hook ISNativeAd
- (void)loadAd { }
%end
// Block IronSource Initialization
%hook IronSource
+ (void)initWithAppKey:(id)arg1 { }
%end

// Pangle (TikTok Ads)
%hook PAGBannerAd
- (void)loadAd:(id)a { }
%end
%hook PAGNativeAd
- (void)loadAd:(id)a { }
%end

%end

// ==========================================================
// 9. VIDEO SAVER BACKUP (Share Sheet)
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
    [newActivities addObject:[[IFDownloadActivity alloc] init]];
    return %orig(items, newActivities);
}
%end
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

// ==========================================================
// 10. CENTRALIZED INITIALIZATION
// ==========================================================
%group AppLifecycle
%hook UIApplication
- (void)didFinishLaunching {
    %orig;
    
    if (gHooksInitialized) return;
    gHooksInitialized = YES;

    // 1. Ads (If Enabled)
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kIFBlockAds]) {
        %init(AdBlocker);
    }
    
    // 2. Backup Video
    %init(BackupVideo);

    // 3. Dynamic Class Loading
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

    // 4. Settings Menu
    Class menuCls = objc_getClass("Menu.MenuViewController");
    if (!menuCls) menuCls = objc_getClass("MenuViewController");
    if (menuCls) %init(MenuHook, MenuViewController = menuCls);
}
%end
%end

%ctor {
    // 1. Defaults
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];

    // 2. Start Lifecycle Monitor
    %init(AppLifecycle);
}