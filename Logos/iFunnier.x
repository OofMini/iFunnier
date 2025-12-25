#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// --- PREFERENCES ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFBlockUpsells @"kIFBlockUpsells"
#define kIFNoWatermark @"kIFNoWatermark"

// Global flag
static BOOL gHooksInitialized = NO;
static NSURL *gLastPlayedURL = nil;

// ==========================================================
// 1. HELPER CLASSES
// ==========================================================

// --- DOWNLOAD ACTIVITY (Video Saver) ---
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

// --- SETTINGS MENU CONTROLLER ---
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
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restart Required" 
                                                                   message:@"Changes will take effect after you restart iFunny." 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Close App Now" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        exit(0);
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
// 3. PREMIUM HOOKS
// ==========================================================

// --- Status ---
%group StatusHook
%hook PremiumStatusServiceImpl
- (BOOL)isActive { return YES; }
%end
%end

// --- Features ---
%group FeaturesHook
%hook PremiumFeaturesServiceImpl
- (BOOL)isEnabled { return YES; }
- (BOOL)isFeatureAvailable:(NSInteger)feature forPlan:(NSInteger)plan { return YES; }
- (BOOL)isFeatureAvailableForAnyPlan:(NSInteger)feature { return YES; }
- (BOOL)isEntryPointEnabled:(NSInteger)entryPoint { return YES; }
%end
%end

// --- Video Saver (Fixes Lock Icon) ---
%group VideoHook
%hook VideoSaveEnableServiceImpl
- (BOOL)isEnabled { return YES; }
- (BOOL)isVideoSaveEnabled { return YES; }
- (BOOL)canSaveVideo { return YES; }
- (BOOL)shouldShowUpsell { return NO; }
%end
%end

// --- Offer Popup (Fixes Feed Popup) ---
%group OfferHook
%hook LimitedTimeOfferServiceImpl
- (BOOL)shouldShowOffer { return NO; }
- (BOOL)isEnabled { return NO; }
%end
%end

// --- Purchase Manager ---
%group PurchaseHook
%hook PremiumPurchaseManagerImpl
- (BOOL)hasActiveSubscription { return YES; }
- (BOOL)isSubscriptionActive { return YES; }
- (id)activeSubscription { return nil; } // Safety fix
%end
%end

// --- App Icons ---
%group IconsHook
%hook PremiumAppIconsServiceImpl
- (BOOL)canChangeAppIcon { return YES; }
- (BOOL)isAppIconChangeEnabled { return YES; }
%end
%end

// ==========================================================
// 4. NUCLEAR AD BLOCKER
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
// 5. VIDEO SAVER BACKUP
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
    NSMutableArray *newActivities = [NSMutableArray arrayWithArray:activities];
    [newActivities addObject:[[IFDownloadActivity alloc] init]];
    return %orig(items, newActivities);
}
%end
%end


// ==========================================================
// 6. ROBUST INITIALIZATION (The Final Fix)
// ==========================================================

// Helper to find Swift classes by Name, Module, or Mangled Name
static Class FindSwiftClass(NSString *name, NSString *mangledName) {
    // 1. Try clean name
    Class cls = objc_getClass([name UTF8String]);
    if (cls) return cls;
    
    // 2. Try Module.Name
    NSString *moduleName = [@"Premium." stringByAppendingString:name];
    cls = objc_getClass([moduleName UTF8String]);
    if (cls) return cls;
    
    // 3. Try Mangled Name (Most reliable for Swift)
    if (mangledName) {
        cls = objc_getClass([mangledName UTF8String]);
        if (cls) return cls;
    }
    
    return nil;
}

%group AppLifecycle
%hook UIApplication
- (void)didFinishLaunching {
    %orig;
    
    if (gHooksInitialized) return;
    gHooksInitialized = YES;

    // 1. Ads & Backup
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kIFBlockAds]) {
        %init(AdBlocker);
    }
    %init(BackupVideo);

    // 2. Initialize Hooks with Mangled Name Fallbacks
    
    // Status
    Class statusCls = FindSwiftClass(@"PremiumStatusServiceImpl", @"_TtC7Premium24PremiumStatusServiceImpl");
    if (statusCls) %init(StatusHook, PremiumStatusServiceImpl = statusCls);

    // Features
    Class featuresCls = FindSwiftClass(@"PremiumFeaturesServiceImpl", @"_TtC7Premium26PremiumFeaturesServiceImpl");
    if (featuresCls) %init(FeaturesHook, PremiumFeaturesServiceImpl = featuresCls);

    // Video Saver (Fixes Lock Icon)
    Class videoCls = FindSwiftClass(@"VideoSaveEnableServiceImpl", @"_TtC7Premium26VideoSaveEnableServiceImpl");
    if (videoCls) %init(VideoHook, VideoSaveEnableServiceImpl = videoCls);
    
    // Offer Popup (Fixes Feed Popup)
    Class offerCls = FindSwiftClass(@"LimitedTimeOfferServiceImpl", @"_TtC7Premium29LimitedTimeOfferServiceImpl");
    if (offerCls) %init(OfferHook, LimitedTimeOfferServiceImpl = offerCls);

    // Purchase
    Class purchaseCls = FindSwiftClass(@"PremiumPurchaseManagerImpl", @"_TtC7Premium26PremiumPurchaseManagerImpl");
    if (purchaseCls) %init(PurchaseHook, PremiumPurchaseManagerImpl = purchaseCls);

    // Icons
    Class iconsCls = FindSwiftClass(@"PremiumAppIconsServiceImpl", @"_TtC7Premium26PremiumAppIconsServiceImpl");
    if (iconsCls) %init(IconsHook, PremiumAppIconsServiceImpl = iconsCls);

    // Menu
    Class menuCls = objc_getClass("Menu.MenuViewController");
    if (!menuCls) menuCls = objc_getClass("MenuViewController");
    if (menuCls) %init(MenuHook, MenuViewController = menuCls);
}
%end
%end

%ctor {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];
    %init(AppLifecycle);
}
