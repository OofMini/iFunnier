#import "../include/iFunnier.h"
#import <UIKit/UIKit.h>

// --- PREFS KEYS ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFNoWatermark @"kIFNoWatermark"
#define kIFSaveVids @"kIFSaveVids"
#define kIFBlockUpsells @"kIFBlockUpsells"

// --- HELPERS ---
void showToast(NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window) return;
        
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"iFunnier" message:msg preferredStyle:UIAlertControllerStyleAlert];
        [window.rootViewController presentViewController:a animated:YES completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [a dismissViewControllerAnimated:YES completion:nil];
        });
    });
}

// --- SMART DOWNLOADER ---
NSData* findVideoDataInView(UIView *v) {
    if (!v) return nil;
    if ([v respondsToSelector:@selector(contentData)]) {
        NSData *d = [v performSelector:@selector(contentData)];
        if (d && [d isKindOfClass:[NSData class]] && d.length > 0) return d;
    }
    for (UIView *sub in v.subviews) {
        NSData *found = findVideoDataInView(sub);
        if (found) return found;
    }
    return nil;
}

void saveVideoData(NSData *data) {
    if (!data) { showToast(@"❌ Error: No Video Data Found"); return; }
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"if_%@.mp4", [[NSUUID UUID] UUIDString]]];
    [data writeToFile:path atomically:YES];
    
    if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(path)) {
        UISaveVideoAtPathToSavedPhotosAlbum(path, nil, nil, nil);
        showToast(@"✅ Video Saved to Photos");
    } else {
        UIImage *img = [UIImage imageWithData:data];
        if (img) {
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
            showToast(@"✅ Image Saved to Photos");
        } else { showToast(@"❌ Error: Unknown Media Type"); }
    }
}

void smartDownload() {
    @try {
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if (!w) { showToast(@"❌ No Active Window"); return; }
        
        NSData *d = findVideoDataInView(w);
        if (d) {
            saveVideoData(d);
        } else {
            UIViewController *root = w.rootViewController;
            while (root.presentedViewController) root = root.presentedViewController;
            
            if ([root respondsToSelector:@selector(activeCell)]) {
                 id cell = [root performSelector:@selector(activeCell)];
                 if (cell && [cell respondsToSelector:@selector(contentData)]) {
                     saveVideoData([cell performSelector:@selector(contentData)]);
                     return;
                 }
            }
            showToast(@"❌ Could not find video on screen.");
        }
    } @catch (NSException *e) { showToast(@"❌ Error during scan."); }
}

// --- SETTINGS VC ---
@interface iFunnierSettingsViewController : UITableViewController
@end

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
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 4; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *sw = [UISwitch new];
    [sw addTarget:self action:@selector(t:) forControlEvents:UIControlEventValueChanged];
    sw.tag = indexPath.row;
    
    NSString *txt = @"";
    BOOL on = NO;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    
    if (indexPath.row == 0) { txt = @"Block Ads (Feed & Banner)"; on = [d boolForKey:kIFBlockAds]; }
    else if (indexPath.row == 1) { txt = @"Block Upsells/Popups"; on = [d boolForKey:kIFBlockUpsells]; }
    else if (indexPath.row == 2) { txt = @"No Watermark"; on = [d boolForKey:kIFNoWatermark]; }
    else if (indexPath.row == 3) { txt = @"Auto-Save Video"; on = [d boolForKey:kIFSaveVids]; }
    
    cell.textLabel.text = txt;
    [sw setOn:on animated:NO];
    cell.accessoryView = sw;
    return cell;
}
- (void)t:(UISwitch *)s {
    NSString *k = (s.tag==0)?kIFBlockAds:(s.tag==1)?kIFBlockUpsells:(s.tag==2)?kIFNoWatermark:kIFSaveVids;
    [[NSUserDefaults standardUserDefaults] setBool:s.isOn forKey:k];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
@end

void openSettingsMenu() {
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    iFunnierSettingsViewController *vc = [[iFunnierSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [root presentViewController:nav animated:YES completion:nil];
}

// --- SHARE BUTTONS ---
@interface IFDownloadActivity : UIActivity @end
@implementation IFDownloadActivity
- (UIActivityType)activityType { return @"com.ifunnier.download"; }
- (NSString *)activityTitle { return @"Download Video"; }
- (UIImage *)activityImage { return [UIImage systemImageNamed:@"arrow.down.circle.fill"]; }
- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems { return YES; }
- (void)performActivity { smartDownload(); [self activityDidFinish:YES]; }
+ (UIActivityCategory)activityCategory { return UIActivityCategoryAction; }
@end

@interface IFSettingsActivity : UIActivity @end
@implementation IFSettingsActivity
- (UIActivityType)activityType { return @"com.ifunnier.settings"; }
- (NSString *)activityTitle { return @"iFunnier Settings"; }
- (UIImage *)activityImage { return [UIImage systemImageNamed:@"gear"]; }
- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems { return YES; }
- (void)performActivity { openSettingsMenu(); [self activityDidFinish:YES]; }
+ (UIActivityCategory)activityCategory { return UIActivityCategoryAction; }
@end

%hook UIActivityViewController
- (instancetype)initWithActivityItems:(NSArray *)items applicationActivities:(NSArray *)activities {
    NSMutableArray *newActivities = [NSMutableArray arrayWithArray:activities];
    [newActivities addObject:[[IFDownloadActivity alloc] init]];
    [newActivities addObject:[[IFSettingsActivity alloc] init]];
    return %orig(items, newActivities);
}
%end

// --- TRIPLE TAP BACKUP ---
%hook UIWindow
- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (event.type == UIEventTypeTouches) {
        NSSet *t = [event allTouches];
        if ([[t anyObject] phase] == UITouchPhaseBegan && t.count == 3) {
             openSettingsMenu();
        }
    }
}
%end

// --- ADS & UPSELLS ---
BOOL en(NSString *k) { return [[NSUserDefaults standardUserDefaults] boolForKey:k]; }
BOOL ads() { return en(kIFBlockAds); }
BOOL upsells() { return en(kIFBlockUpsells); }

%group AdBlockers

// 1. AppLovin
%hook ALAdService
- (void)loadNextAd:(id)a andNotify:(id)b { if(ads()) return; %orig; }
%end

// 2. InMobi
%hook IMBanner
- (void)load { if(ads()) return; %orig; }
%end

// 3. Pangle
%hook PAGBannerAd
- (void)loadAd:(id)a { if(ads()) return; %orig; }
%end
%hook PAGInterstitialAd
- (void)loadAd:(id)a { if(ads()) return; %orig; }
%end

// 4. Amazon
%hook DTBAdLoader
- (void)loadAd:(id)a { if(ads()) return; %orig; }
%end

// 5. IronSource
%hook ISNativeAd
- (instancetype)initWithInteractionDelegate:(id)d { if(ads()) return nil; return %orig; }
%end

// 6. Native Feed Ad View (FIX: Correct Interface)
// Explicitly tell compiler this is a UIView
@interface IFNativeAdInfoView : UIView
@end

%hook IFNativeAdInfoView
- (void)didMoveToWindow {
    %orig;
    if (ads()) {
        self.hidden = YES;
        self.alpha = 0;
        CGRect f = self.frame;
        f.size.height = 0;
        self.frame = f;
    }
}
%end
%end // End AdBlockers


// --- UPSELL BLOCKER ---
%group UpsellBlockers
%hook UIViewController
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)flag completion:(void (^)(void))completion {
    if (upsells()) {
        NSString *name = NSStringFromClass([vc class]);
        if ([name containsString:@"Premium"] || 
            [name containsString:@"Subscription"] || 
            [name containsString:@"Upsell"] ||
            [name containsString:@"Paywall"]) {
            if (completion) completion();
            return;
        }
    }
    %orig;
}
%end
%end

%ctor {
    %init;
    %init(AdBlockers);
    %init(UpsellBlockers);
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];
    if (![d objectForKey:kIFBlockUpsells]) [d setBool:YES forKey:kIFBlockUpsells];
    if (![d objectForKey:kIFNoWatermark]) [d setBool:YES forKey:kIFNoWatermark];
}
