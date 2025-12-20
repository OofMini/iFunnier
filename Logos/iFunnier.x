#import "../include/iFunnier.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// --- PREFS KEYS ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFBlockUpsells @"kIFBlockUpsells"
#define kIFNoWatermark @"kIFNoWatermark"
#define kIFSaveVids @"kIFSaveVids"

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

BOOL en(NSString *k) { return [[NSUserDefaults standardUserDefaults] boolForKey:k]; }
BOOL ads() { return en(kIFBlockAds); }

// --- UI CLEANER ENGINE (v4.0 - Anti-Freeze Edition) ---
%group UICleaner

void nukeView(UIView *v) {
    if (!v) return;
    v.hidden = YES;
    v.alpha = 0;
    v.userInteractionEnabled = NO;
    v.backgroundColor = [UIColor clearColor];
    
    CGRect f = v.frame;
    f.size.height = 0;
    f.size.width = 0;
    v.frame = f;
}

// 1. Alert Blocker
%hook UIAlertController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (ads()) {
        NSString *title = self.title ?: @"";
        NSString *msg = self.message ?: @"";
        if ([title localizedCaseInsensitiveContainsString:@"wrong"] || 
            [msg localizedCaseInsensitiveContainsString:@"wrong"] ||
            [title localizedCaseInsensitiveContainsString:@"error"]) {
            [self dismissViewControllerAnimated:NO completion:nil];
        }
    }
}
%end

// 2. Text Cleaner
%hook UILabel
- (void)setText:(NSString *)text {
    %orig;
    if (ads() && text.length > 0) {
        NSString *clean = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        // Holiday / Sale / Premium
        if ([clean localizedCaseInsensitiveContainsString:@"Holiday"] || 
            [clean localizedCaseInsensitiveContainsString:@"Sale"] || 
            [clean localizedCaseInsensitiveContainsString:@"Premium"] ||
            [clean localizedCaseInsensitiveContainsString:@"Offer"]) {
            
            if (clean.length < 35) { 
                self.hidden = YES;
                nukeView(self.superview); 
            }
        }
        
        // Hide Ads Button
        if ([clean localizedCaseInsensitiveContainsString:@"Hide Ads"] || 
            [clean localizedCaseInsensitiveContainsString:@"Remove Ads"]) {
            self.hidden = YES;
            UIView *p = self.superview;
            for (int i=0; i<8; i++) {
                if (!p) break;
                if (p.frame.size.height > 30 && p.frame.size.height < 160) nukeView(p);
                p = p.superview;
            }
        }
    }
}

// 3. Attributed Text
- (void)setAttributedText:(NSAttributedString *)text {
    %orig;
    if (ads() && text.string.length > 0) {
        NSString *str = text.string;
        if ([str localizedCaseInsensitiveContainsString:@"Holiday"] || 
            [str localizedCaseInsensitiveContainsString:@"Sale"]) {
            if (str.length < 35) {
                self.hidden = YES;
                nukeView(self.superview);
            }
        }
    }
}
%end

// 4. Button Cleaner
%hook UIButton
- (void)setTitle:(NSString *)t forState:(UIControlState)s {
    %orig;
    if (ads() && t.length > 0) {
        if ([t localizedCaseInsensitiveContainsString:@"Hide Ads"] || [t localizedCaseInsensitiveContainsString:@"Remove Ads"]) {
            self.hidden = YES;
            UIView *p = self.superview;
            for (int i=0; i<8; i++) {
                if (!p) break;
                if (p.frame.size.height > 30 && p.frame.size.height < 160) nukeView(p);
                p = p.superview;
            }
        }
    }
}
%end

// 5. Feed Ad View
@interface IFNativeAdInfoView : UIView @end
%hook IFNativeAdInfoView
- (void)didMoveToWindow { %orig; if (ads()) nukeView(self); }
- (void)layoutSubviews { %orig; if (ads()) nukeView(self); }
%end

// 6. BOTTOM VACUUM (OLED Fix)
%hook UIView
- (void)layoutSubviews {
    %orig;
    if (ads()) {
        CGFloat y = self.frame.origin.y;
        CGFloat h = self.frame.size.height;
        CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
        
        // Detect Bottom Views
        if (y >= (screenH - 120)) {
            NSString *cls = NSStringFromClass([self class]);
            
            // SKIP Tab Bar and Input Fields
            if ([self isKindOfClass:[UITabBar class]] || 
                [cls containsString:@"TabBar"] || 
                [cls containsString:@"Input"] ||
                [cls containsString:@"Keyboard"] ||
                [cls containsString:@"Composer"]) return;

            // Target 1: Banners
            if ([cls containsString:@"Banner"] || [cls containsString:@"Ad"] || [cls containsString:@"Pub"] || [cls containsString:@"Sticky"]) {
                nukeView(self);
                return;
            }
            
            // Target 2: The "Gray Bar" (Blur Effect)
            if ([self isKindOfClass:[UIVisualEffectView class]]) {
                 if (h < 100) nukeView(self);
            }
            
            // Target 3: Generic Placeholder Rectangles
            if ((h >= 49 && h <= 51) || (h >= 89 && h <= 91)) {
                nukeView(self);
            }
        }
    }
}
%end
%end // End UICleaner

// --- UPSALE ASSASSIN (Fixed: No Freezing) ---
%group UpsellBlockers
%hook UIViewController

// Method 1: Block Presentation (Proactive)
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)flag completion:(void (^)(void))completion {
    if (en(kIFBlockUpsells)) {
        NSString *name = NSStringFromClass([vc class]);
        if ([name localizedCaseInsensitiveContainsString:@"Premium"] || 
            [name localizedCaseInsensitiveContainsString:@"Subscription"] || 
            [name localizedCaseInsensitiveContainsString:@"Upsell"] ||
            [name localizedCaseInsensitiveContainsString:@"Offer"] ||
            [name localizedCaseInsensitiveContainsString:@"Sale"]) {
            if (completion) completion(); // Silently fail
            return;
        }
    }
    %orig;
}

// Method 2: Kill on Sight (Reactive - Moved to viewDidAppear to prevent Freeze)
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (en(kIFBlockUpsells)) {
        NSString *name = NSStringFromClass([self class]);
        if ([name localizedCaseInsensitiveContainsString:@"Premium"] || 
            [name localizedCaseInsensitiveContainsString:@"Subscription"] || 
            [name localizedCaseInsensitiveContainsString:@"Upsell"]) {
            
            self.view.hidden = YES;
            
            // SAFELY DISMISS after 0.05s to avoid Lifecycle Deadlock
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self dismissViewControllerAnimated:NO completion:nil];
            });
        }
    }
}
%end
%end

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
    if (!gLastPlayedURL) { showToast(@"❌ No Video Detected.\nPlay a video first!"); return; }
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

// --- SETTINGS ---
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
    [sw addTarget:self action:@selector(t:) forControlEvents:UIControlEventValueChanged];
    sw.tag = indexPath.row;
    NSString *txt = @"";
    BOOL on = NO;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (indexPath.row == 0) { txt = @"Block Ads / Upsells"; on = [d boolForKey:kIFBlockAds]; }
    else if (indexPath.row == 1) { txt = @"No Watermark"; on = [d boolForKey:kIFNoWatermark]; }
    else if (indexPath.row == 2) { txt = @"Auto-Save Video"; on = [d boolForKey:kIFSaveVids]; }
    cell.textLabel.text = txt;
    [sw setOn:on animated:NO];
    cell.accessoryView = sw;
    return cell;
}
- (void)t:(UISwitch *)s {
    NSString *k = (s.tag==0)?kIFBlockAds:(s.tag==1)?kIFNoWatermark:kIFSaveVids;
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
%end

%ctor {
    %init;
    %init(AdBlockers);
    %init(UICleaner);
    %init(UpsellBlockers);
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];
    if (![d objectForKey:kIFBlockUpsells]) [d setBool:YES forKey:kIFBlockUpsells];
    if (![d objectForKey:kIFNoWatermark]) [d setBool:YES forKey:kIFNoWatermark];
}
