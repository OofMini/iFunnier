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

// --- NETWORK ASSASSIN (The "Nuclear" AdBlock) ---
%group NetworkAssassin

BOOL isAdURL(NSURL *url) {
    NSString *s = url.absoluteString.lowercaseString;
    return ([s containsString:@"applovin"] || 
            [s containsString:@"pangle"] || 
            [s containsString:@"tiktokv"] || // Pangle uses tiktokv domains
            [s containsString:@"ironsource"] || 
            [s containsString:@"supersonic"] || // IronSource legacy
            [s containsString:@"inmobi"] || 
            [s containsString:@"amazon-adsystem"] || 
            [s containsString:@"ads"] && [s containsString:@"api"]); // Generic catch
}

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (ads() && isAdURL(request.URL)) {
        // Silently fail the request
        if (completionHandler) {
            completionHandler(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
        }
        return nil;
    }
    return %orig;
}
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (ads() && isAdURL(url)) {
        if (completionHandler) {
            completionHandler(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
        }
        return nil;
    }
    return %orig;
}
%end
%end


// --- UI CLEANER (Continuous Enforcement) ---
%group UICleaner

void nuke(UIView *v) {
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

// 1. Universal Scanner (Now runs on ALL views)
%hook UIView
- (void)layoutSubviews {
    %orig;
    if (!ads()) return;

    // A. Accessibility & Label Scan (Sidebar Holiday & Report Button)
    NSString *ax = self.accessibilityLabel;
    
    // Check Accessibility Label
    if (ax && [ax isKindOfClass:[NSString class]]) {
        if ([ax localizedCaseInsensitiveContainsString:@"Holiday"] || 
            [ax localizedCaseInsensitiveContainsString:@"Sale"] ||
            [ax localizedCaseInsensitiveContainsString:@"Report"]) {
            nuke(self);
            return;
        }
    }

    // Check Buttons specifically
    if ([self isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)self;
        NSString *t = btn.currentTitle ?: @"";
        if ([t localizedCaseInsensitiveContainsString:@"Report"] || 
            [t localizedCaseInsensitiveContainsString:@"Hide"] ||
            [t localizedCaseInsensitiveContainsString:@"Remove"]) {
            nuke(self);
            if (self.superview.frame.size.height < 150) nuke(self.superview); // Kill container
            return;
        }
    }

    // B. Bottom Vacuum (The "Gray Bar" Fix)
    CGFloat y = self.frame.origin.y;
    CGFloat h = self.frame.size.height;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    
    if (y >= (screenH - 150)) {
        NSString *cls = NSStringFromClass([self class]);
        // SAFETY: Ignore TabBar/Input
        if ([self isKindOfClass:[UITabBar class]] || 
            [cls containsString:@"TabBar"] || 
            [cls containsString:@"Input"] || 
            [cls containsString:@"Keyboard"]) return;

        // Kill Banners
        if ([cls containsString:@"Banner"] || [cls containsString:@"Ad"] || [cls containsString:@"Pub"]) {
            nuke(self);
            return;
        }
        
        // Kill Blur Effects (Gray Bar)
        if ([self isKindOfClass:[UIVisualEffectView class]] && h < 100) nuke(self);

        // Kill Generic Placeholders (Empty white/gray boxes)
        if ((h >= 49 && h <= 51) || (h >= 89 && h <= 95)) {
             if (self.subviews.count == 0) nuke(self);
             else self.backgroundColor = [UIColor clearColor];
        }
    }
}
%end

// 2. Alert Blocker (Aggressive)
%hook UIAlertController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (ads()) {
        NSString *t = self.title ?: @"";
        NSString *m = self.message ?: @"";
        if ([t localizedCaseInsensitiveContainsString:@"wrong"] || 
            [m localizedCaseInsensitiveContainsString:@"wrong"] ||
            [t localizedCaseInsensitiveContainsString:@"error"]) {
            self.view.hidden = YES;
            [self dismissViewControllerAnimated:NO completion:nil];
        }
    }
}
%end
%end // End UICleaner


// --- LAYER KILLER (Popup Assassin) ---
%group UpsellBlockers
%hook CALayer
- (void)addSublayer:(CALayer *)layer {
    if (en(kIFBlockUpsells)) {
        // Check the Delegate (The View owning this layer)
        id delegate = layer.delegate;
        if (delegate && [delegate isKindOfClass:[UIView class]]) {
            UIView *v = (UIView *)delegate;
            // Identify if this view belongs to a Premium VC
            UIResponder *next = v.nextResponder;
            while (next) {
                if ([next isKindOfClass:[UIViewController class]]) {
                    NSString *name = NSStringFromClass([next class]);
                    if ([name localizedCaseInsensitiveContainsString:@"Premium"] || 
                        [name localizedCaseInsensitiveContainsString:@"Subscription"] || 
                        [name localizedCaseInsensitiveContainsString:@"Upsell"]) {
                        return; // DENY: Do not add this layer to screen.
                    }
                    break;
                }
                next = next.nextResponder;
            }
        }
    }
    %orig;
}
%end

// Backup: Standard VC Block
%hook UIViewController
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)flag completion:(void (^)(void))completion {
    if (en(kIFBlockUpsells)) {
        NSString *name = NSStringFromClass([vc class]);
        if ([name localizedCaseInsensitiveContainsString:@"Premium"] || 
            [name localizedCaseInsensitiveContainsString:@"Subscription"] || 
            [name localizedCaseInsensitiveContainsString:@"Upsell"]) {
            if (completion) completion();
            return;
        }
    }
    %orig;
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

%ctor {
    %init;
    %init(NetworkAssassin);
    %init(UICleaner);
    %init(UpsellBlockers);
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];
    if (![d objectForKey:kIFBlockUpsells]) [d setBool:YES forKey:kIFBlockUpsells];
    if (![d objectForKey:kIFNoWatermark]) [d setBool:YES forKey:kIFNoWatermark];
}
