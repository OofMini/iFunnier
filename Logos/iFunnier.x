#import "../include/iFunnier.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// --- PREFS ---
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

// --- FEED CLEANER (The Fix for Swiping Ads) ---
%group UICleaner

void nuke(UIView *v) {
    if (!v) return;
    v.hidden = YES;
    v.alpha = 0;
    v.userInteractionEnabled = NO;
    v.backgroundColor = [UIColor clearColor];
    // Collapse frame to remove "Black Box"
    CGRect f = v.frame;
    f.size.height = 0;
    f.size.width = 0;
    v.frame = f;
}

// 1. CELL HUNTER: Kills the "Page" before you see it
%hook UICollectionViewCell
- (void)layoutSubviews {
    %orig;
    if (ads()) {
        // Scan children for "Advertisement" label
        BOOL isAd = NO;
        
        // Deep scan of subviews (Recursive is too slow, we do iterative scan of top levels)
        for (UIView *sub in self.contentView.subviews) {
            // Check Labels
            if ([sub isKindOfClass:[UILabel class]]) {
                NSString *t = ((UILabel *)sub).text;
                if ([t localizedCaseInsensitiveContainsString:@"Advertisement"] || 
                    [t localizedCaseInsensitiveContainsString:@"Sponsored"]) {
                    isAd = YES; break;
                }
            }
            // Check Accessibility (SwiftUI)
            if (sub.accessibilityLabel && [sub.accessibilityLabel localizedCaseInsensitiveContainsString:@"Advertisement"]) {
                isAd = YES; break;
            }
            // Check Buttons (Hide Ads button)
            if ([sub isKindOfClass:[UIButton class]]) {
                NSString *t = ((UIButton *)sub).currentTitle;
                if ([t localizedCaseInsensitiveContainsString:@"Hide Ads"] || [t localizedCaseInsensitiveContainsString:@"Report"]) {
                    isAd = YES; break;
                }
            }
        }
        
        if (isAd) {
            nuke(self);
            nuke(self.contentView);
        }
    }
}
%end

// 2. VIEW SCANNER: Clean up any leftovers
%hook UIView
- (void)layoutSubviews {
    %orig;
    if (!ads()) return;

    // A. Accessibility Scan
    if ([self respondsToSelector:@selector(accessibilityLabel)]) {
        NSString *ax = self.accessibilityLabel;
        if (ax && [ax isKindOfClass:[NSString class]]) {
            if ([ax localizedCaseInsensitiveContainsString:@"Sponsored"] ||
                [ax localizedCaseInsensitiveContainsString:@"Advertisement"]) {
                nuke(self);
                return; 
            }
        }
    }

    // B. Bottom Vacuum (Gray Bar Fix)
    CGFloat y = self.frame.origin.y;
    CGFloat h = self.frame.size.height;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    
    if (y >= (screenH - 150)) {
        NSString *cls = NSStringFromClass([self class]);
        // SAFETY: Ignore TabBar/Input
        if ([self isKindOfClass:[UITabBar class]] || 
            [cls containsString:@"TabBar"] || 
            [cls containsString:@"Input"] || 
            [cls containsString:@"Keyboard"] ||
            [cls containsString:@"Composer"]) return;

        // Kill Banners
        if ([cls containsString:@"Banner"] || [cls containsString:@"Ad"] || [cls containsString:@"Pub"]) {
            nuke(self);
            return;
        }
        
        // Kill Blur Effects (Gray Bar)
        if ([self isKindOfClass:[UIVisualEffectView class]] && h < 100) nuke(self);

        // Kill Generic Placeholders
        if ((h >= 49 && h <= 51) || (h >= 89 && h <= 95)) {
             if (self.subviews.count == 0) nuke(self);
             else self.backgroundColor = [UIColor clearColor];
        }
    }
}
%end

// 3. Alert Blocker (Something Went Wrong)
%hook UIAlertController
- (void)viewDidLoad {
    %orig;
    if (ads()) {
        NSString *t = self.title ?: @"";
        NSString *m = self.message ?: @"";
        if ([t localizedCaseInsensitiveContainsString:@"wrong"] || 
            [m localizedCaseInsensitiveContainsString:@"wrong"] ||
            [t localizedCaseInsensitiveContainsString:@"error"] ||
            [t localizedCaseInsensitiveContainsString:@"oops"]) {
            
            self.view.hidden = YES;
            self.view.alpha = 0;
        }
    }
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (self.view.hidden) [self dismissViewControllerAnimated:NO completion:nil];
}
%end
%end // End UICleaner


// --- POPUP BLOCKER (Triple Tap Strategy) ---
%group UpsellBlockers
%hook UIViewController

// 1. Block Presentation
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)flag completion:(void (^)(void))completion {
    if (en(kIFBlockUpsells)) {
        NSString *name = NSStringFromClass([vc class]);
        if ([name localizedCaseInsensitiveContainsString:@"Premium"] || 
            [name localizedCaseInsensitiveContainsString:@"Subscription"] || 
            [name localizedCaseInsensitiveContainsString:@"Upsell"] ||
            [name localizedCaseInsensitiveContainsString:@"Offer"] ||
            [name localizedCaseInsensitiveContainsString:@"Sale"]) {
            
            if (completion) completion(); 
            return;
        }
    }
    %orig;
}

// 2. Content Eraser (Invisibility)
- (void)viewDidLoad {
    %orig;
    if (en(kIFBlockUpsells)) {
        NSString *name = NSStringFromClass([self class]);
        if ([name localizedCaseInsensitiveContainsString:@"Premium"] || 
            [name localizedCaseInsensitiveContainsString:@"Subscription"] || 
            [name localizedCaseInsensitiveContainsString:@"Upsell"]) {
            
            self.view.backgroundColor = [UIColor clearColor];
            self.view.userInteractionEnabled = NO;
            for (UIView *sub in self.view.subviews) sub.hidden = YES;
        }
    }
}

// 3. FORCE DISMISS (The Fix for "GUI not closing")
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (en(kIFBlockUpsells)) {
        NSString *name = NSStringFromClass([self class]);
        if ([name localizedCaseInsensitiveContainsString:@"Premium"] || 
            [name localizedCaseInsensitiveContainsString:@"Subscription"] || 
            [name localizedCaseInsensitiveContainsString:@"Upsell"]) {
            
            // Try 1: Dismiss Self
            [self dismissViewControllerAnimated:NO completion:nil];
            
            // Try 2: Tell Parent to Dismiss (Stronger)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self.presentingViewController dismissViewControllerAnimated:NO completion:nil];
            });
            
            // Try 3: Nuclear Option (Root VC Dismiss)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [[UIApplication sharedApplication].keyWindow.rootViewController dismissViewControllerAnimated:NO completion:nil];
            });
        }
    }
}
%end
%end


// --- NETWORK REDIRECT (Keep this, it stops the crash) ---
%group NetworkAssassin

BOOL isAdURL(NSURL *url) {
    NSString *s = url.absoluteString.lowercaseString;
    return ([s containsString:@"applovin"] || 
            [s containsString:@"pangle"] || 
            [s containsString:@"tiktokv"] || 
            [s containsString:@"ironsource"] || 
            [s containsString:@"supersonic"] ||
            [s containsString:@"inmobi"] || 
            [s containsString:@"amazon-adsystem"] || 
            [s containsString:@"mopub"] ||
            [s containsString:@"adjust"] ||
            [s containsString:@"appsflyer"]);
}

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (ads() && isAdURL(request.URL)) {
        NSMutableURLRequest *deadReq = [request mutableCopy];
        deadReq.URL = [NSURL URLWithString:@"http://0.0.0.0"];
        return %orig(deadReq, completionHandler);
    }
    return %orig;
}
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (ads() && isAdURL(url)) {
        return %orig([NSURL URLWithString:@"http://0.0.0.0"], completionHandler);
    }
    return %orig;
}
%end
%end


// --- AD SDK LOBOTOMY ---
%group AdBlockers
%hook ALAdService
- (void)loadNextAd:(id)a andNotify:(id)b { if(ads()) return; %orig; }
%end
%hook ISNativeAd
- (void)loadAd { if(ads()) return; %orig; }
- (void)loadAdWithViewController:(id)vc { if(ads()) return; %orig; }
%end
%hook PAGBannerAd
- (void)loadAd:(id)a { if(ads()) return; %orig; }
%end
%hook PAGNativeAd
- (void)loadAd:(id)a { if(ads()) return; %orig; }
%end
%hook DTBAdLoader
- (void)loadAd:(id)a { if(ads()) return; %orig; }
%end
%hook IMBanner
- (void)load { if(ads()) return; %orig; }
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

%ctor {
    %init;
    %init(NetworkAssassin);
    %init(AdBlockers);
    %init(UICleaner);
    %init(UpsellBlockers);
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];
    if (![d objectForKey:kIFBlockUpsells]) [d setBool:YES forKey:kIFBlockUpsells];
    if (![d objectForKey:kIFNoWatermark]) [d setBool:YES forKey:kIFNoWatermark];
}
