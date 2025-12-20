#import "../include/iFunnier.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// --- PREFS KEYS ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFBlockUpsells @"kIFBlockUpsells"
#define kIFNoWatermark @"kIFNoWatermark"
#define kIFSaveVids @"kIFSaveVids"

// --- GLOBAL STORAGE ---
static NSURL *gLastPlayedURL = nil;

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

// --- PREFS HELPERS ---
BOOL en(NSString *k) { return [[NSUserDefaults standardUserDefaults] boolForKey:k]; }
BOOL ads() { return en(kIFBlockAds); }
BOOL upsells() { return en(kIFBlockUpsells); }

// --- UI CLEANER (The Fix for Blank Spaces & Text) ---
%group UICleaner

// Helper to collapse a view completely
void killView(UIView *v) {
    if (!v) return;
    v.hidden = YES;
    v.alpha = 0;
    CGRect f = v.frame;
    f.size.height = 0;
    f.size.width = 0;
    v.frame = f;
}

// Hook Labels to catch "Holiday Sale" and "Hide Ads" text
%hook UILabel
- (void)setText:(NSString *)text {
    %orig;
    if (ads() && text.length > 0) {
        // Fix 1: Holiday Sale (Top Right & Sidebar)
        if ([text containsString:@"Holiday Sale"] || [text containsString:@"Sale"]) {
            // Check if it's a short promo label (avoid hiding actual memes)
            if (text.length < 20) {
                self.hidden = YES;
                killView(self.superview); // Kill the badge container
            }
            return;
        }
        
        // Fix 2: "Hide Ads" (Bottom Right)
        // If we see this, we are INSIDE the ad banner. Kill the parent!
        if ([text isEqualToString:@"Hide Ads"]) {
            self.hidden = YES;
            
            // Walk up the hierarchy to find the main banner container
            UIView *parent = self.superview;
            for (int i = 0; i < 6; i++) {
                if (!parent) break;
                
                // If view is at the bottom of screen and has banner-like height
                if (parent.frame.size.height > 40 && parent.frame.size.height < 150) {
                    killView(parent); // FOUND IT! Kill the blank space.
                }
                parent = parent.superview;
            }
        }
    }
}
%end

// Hook Buttons (Sometimes "Hide Ads" is a button)
%hook UIButton
- (void)setTitle:(NSString *)title forState:(UIControlState)state {
    %orig;
    if (ads() && title.length > 0) {
        if ([title isEqualToString:@"Hide Ads"]) {
            self.hidden = YES;
            UIView *parent = self.superview;
            for (int i = 0; i < 6; i++) {
                if (!parent) break;
                if (parent.frame.size.height > 40 && parent.frame.size.height < 150) {
                    killView(parent);
                }
                parent = parent.superview;
            }
        }
    }
}
%end

// Backup: Check for any view stuck at the bottom of the screen (Blank Placeholder)
%hook UIView
- (void)layoutSubviews {
    %orig;
    if (ads()) {
        // Heuristic: Is this a banner at the bottom?
        CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
        if (self.frame.origin.y >= (screenH - 100) && self.frame.size.height > 40 && self.frame.size.height < 120) {
            
            // Don't kill the Tab Bar! (Tab bar is usually exactly 49 or 83 high)
            if ([self isKindOfClass:[UITabBar class]]) return;
            if ([NSStringFromClass([self class]) containsString:@"TabBar"]) return;

            // Check if it's an ad container (often has 'Banner', 'Ad', or 'Mopub' in name)
            NSString *name = NSStringFromClass([self class]);
            if ([name containsString:@"Banner"] || [name containsString:@"Ad"] || [name containsString:@"Pub"]) {
                killView(self);
            }
        }
    }
}
%end

%end // End UICleaner

// --- VIDEO SNIFFER ---
%hook AVPlayer
- (void)replaceCurrentItemWithPlayerItem:(AVPlayerItem *)item {
    %orig;
    if (item && [item.asset isKindOfClass:[AVURLAsset class]]) {
        gLastPlayedURL = [(AVURLAsset *)item.asset URL];
    }
}
- (instancetype)initWithPlayerItem:(AVPlayerItem *)item {
    self = %orig;
    if (item && [item.asset isKindOfClass:[AVURLAsset class]]) {
        gLastPlayedURL = [(AVURLAsset *)item.asset URL];
    }
    return self;
}
%end

void downloadLastVideo() {
    if (!gLastPlayedURL) { showToast(@"❌ No Video Detected Yet.\nPlay a video first!"); return; }
    showToast(@"⏳ Downloading...");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [NSData dataWithContentsOfURL:gLastPlayedURL];
        if (!data) { showToast(@"❌ Download Failed"); return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"if_%@.mp4", [[NSUUID UUID] UUIDString]]];
            [data writeToFile:path atomically:YES];
            if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(path)) {
                UISaveVideoAtPathToSavedPhotosAlbum(path, nil, nil, nil);
                showToast(@"✅ Video Saved");
            } else { showToast(@"❌ Error: Format not supported"); }
        });
    });
}

// --- SETTINGS MENU ---
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
    
    if (indexPath.row == 0) { txt = @"Block Ads / Upsells"; on = [d boolForKey:kIFBlockAds]; }
    else if (indexPath.row == 1) { txt = @"Block Holiday Promos"; on = [d boolForKey:kIFBlockUpsells]; }
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
- (void)performActivity { downloadLastVideo(); [self activityDidFinish:YES]; }
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
%group AdBlockers
%hook ALAdService
- (void)loadNextAd:(id)a andNotify:(id)b { if(ads()) return; %orig; }
%end
%hook IMBanner
- (void)load { if(ads()) return; %orig; }
%end
%hook PAGBannerAd
- (void)loadAd:(id)a { if(ads()) return; %orig; }
%end
%hook DTBAdLoader
- (void)loadAd:(id)a { if(ads()) return; %orig; }
%end
%hook ISNativeAd
- (instancetype)initWithInteractionDelegate:(id)d { if(ads()) return nil; return %orig; }
%end
@interface IFNativeAdInfoView : UIView @end
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
%end

%group UpsellBlockers
%hook UIViewController
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)flag completion:(void (^)(void))completion {
    if (upsells()) {
        NSString *name = NSStringFromClass([vc class]);
        if ([name containsString:@"Premium"] || [name containsString:@"Subscription"] || [name containsString:@"Upsell"]) {
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
    %init(UICleaner); // Init new UI cleaner
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];
    if (![d objectForKey:kIFBlockUpsells]) [d setBool:YES forKey:kIFBlockUpsells];
    if (![d objectForKey:kIFNoWatermark]) [d setBool:YES forKey:kIFNoWatermark];
}
