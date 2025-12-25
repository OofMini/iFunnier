#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <os/log.h>

// --- PREFERENCES ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFBlockUpsells @"kIFBlockUpsells"
#define kIFNoWatermark @"kIFNoWatermark"

static BOOL gHooksInitialized = NO;
static NSURL *gLastPlayedURL = nil;

// ==========================================================
// 1. HELPER: CLASS DUMPER (The Magic Tool)
// ==========================================================
static void DumpRelevantClasses() {
    // This logs to the Console.app on Mac or sysdiagnose
    NSLog(@"[iFunnier] === STARTING CLASS DUMP ===");
    
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    
    for (unsigned int i = 0; i < count; i++) {
        const char *cName = class_getName(classes[i]);
        if (!cName) continue;
        
        NSString *name = [NSString stringWithUTF8String:cName];
        
        // Filter for keywords related to our missing features
        if ([name containsString:@"Premium"] || 
            [name containsString:@"VideoSave"] || 
            [name containsString:@"Offer"] || 
            [name containsString:@"ViewModel"] || // CHECK FOR VIEWMODELS
            [name containsString:@"RemoteConfig"] ||
            [name containsString:@"Experiment"]) {
            
            NSLog(@"[iFunnier] FOUND CANDIDATE: %@", name);
        }
    }
    free(classes);
    NSLog(@"[iFunnier] === CLASS DUMP FINISHED ===");
}

// ==========================================================
// 2. HELPER CLASSES
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
// 3. SETTINGS MENU INJECTION
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
// 4. REMOTE CONFIG & EXPERIMENTS (New!)
// ==========================================================
%group RemoteConfigHook
// Hook generic Remote Config to force-enable features
%hook FIRRemoteConfig
- (id)configValueForKey:(NSString *)key {
    // If asking for anything premium/feature related, say YES
    if ([key containsString:@"premium"] || [key containsString:@"video_save"] || [key containsString:@"watermark"]) {
        // Return a dummy object that evaluates to boolean True
        return [NSNumber numberWithBool:YES];
    }
    return %orig;
}
%end
%end

// ==========================================================
// 5. SERVICE HOOKS (Expanded)
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
- (BOOL)canSaveVideo { return YES; }
- (BOOL)shouldShowUpsell { return NO; }
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
// 7. BACKUP VIDEO SAVER
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
// 8. ROBUST INITIALIZATION
// ==========================================================
static Class FindSwiftClass(NSString *name) {
    // 1. Try Clean Name
    Class cls = objc_getClass([name UTF8String]);
    if (cls) return cls;
    
    // 2. Try Modules: Premium, iFunny, iFunnyApp, Core
    NSArray *modules = @[@"Premium", @"iFunny", @"iFunnyApp", @"Core"];
    for (NSString *module in modules) {
        NSString *fullName = [NSString stringWithFormat:@"%@.%@", module, name];
        cls = objc_getClass([fullName UTF8String]);
        if (cls) {
            NSLog(@"[iFunnier] Hooked: %@", fullName);
            return cls;
        }
    }
    
    // 3. Try Common Mangled Prefixes (Swift 5+)
    // _TtC + Length(module) + Module + Length(name) + Name
    // This is hard to guess perfectly, but we try the most common "Premium" one
    // _TtC7Premium + Length + Name
    NSString *mangled = [NSString stringWithFormat:@"_TtC7Premium%lu%@", (unsigned long)name.length, name];
    cls = objc_getClass([mangled UTF8String]);
    if (cls) return cls;

    return nil;
}

%group AppLifecycle
%hook UIApplication
- (void)didFinishLaunching {
    %orig;
    if (gHooksInitialized) return;
    gHooksInitialized = YES;

    // RUN THE CLASS DUMPER
    // Look at your Console/Syslog to see the output!
    DumpRelevantClasses();

    if ([[NSUserDefaults standardUserDefaults] boolForKey:kIFBlockAds]) {
        %init(AdBlocker);
    }
    %init(BackupVideo);

    // Try to hook Services with expanded search
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

    // Try to hook Remote Config (Google/Firebase)
    Class remoteConfigCls = objc_getClass("FIRRemoteConfig");
    if (remoteConfigCls) %init(RemoteConfigHook, FIRRemoteConfig = remoteConfigCls);

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
