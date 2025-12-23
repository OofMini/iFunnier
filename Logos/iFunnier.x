#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// --- PREFERENCES ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFBlockUpsells @"kIFBlockUpsells"
#define kIFNoWatermark @"kIFNoWatermark"
#define kIFSaveVids @"kIFSaveVids"

static NSURL *gLastPlayedURL = nil;

// --- HELPERS ---
BOOL en(NSString *k) { return [[NSUserDefaults standardUserDefaults] boolForKey:k]; }
BOOL ads() { return en(kIFBlockAds); }

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

// --- UI CLEANER ENGINE ---
%group UICleaner

void nuke(UIView *v) {
    if (!v) return;
    v.hidden = YES;
    v.alpha = 0;
    v.userInteractionEnabled = NO;
    v.backgroundColor = [UIColor clearColor];
    v.clipsToBounds = YES;
    CGRect f = v.frame;
    f.size.height = 0;
    f.size.width = 0;
    v.frame = f;
}

BOOL isViewNasty(UIView *v) {
    if ([v isKindOfClass:[UILabel class]]) {
        NSString *t = ((UILabel *)v).text ?: @"";
        if ([t localizedCaseInsensitiveContainsString:@"Advertisement"] || 
            [t localizedCaseInsensitiveContainsString:@"Sponsored"] ||
            [t localizedCaseInsensitiveContainsString:@"Premium"] ||
            [t localizedCaseInsensitiveContainsString:@"Shop Now"] ||
            [t localizedCaseInsensitiveContainsString:@"Install"]) {
            return YES;
        }
    }
    if ([v isKindOfClass:[UIButton class]]) {
        NSString *t = ((UIButton *)v).currentTitle ?: @"";
        if ([t localizedCaseInsensitiveContainsString:@"Hide"] || 
            [t localizedCaseInsensitiveContainsString:@"Report"] ||
            [t localizedCaseInsensitiveContainsString:@"Remove"]) {
            return YES;
        }
    }
    if (v.accessibilityLabel) {
        NSString *ax = v.accessibilityLabel;
        if ([ax localizedCaseInsensitiveContainsString:@"Advertisement"] ||
            [ax localizedCaseInsensitiveContainsString:@"Sponsored"] ||
            [ax localizedCaseInsensitiveContainsString:@"Holiday"] ||
            [ax localizedCaseInsensitiveContainsString:@"Sale"]) {
            return YES;
        }
    }
    return NO;
}

BOOL cellHasNastyContent(UIView *v, int depth) {
    if (depth > 8) return NO;
    if (isViewNasty(v)) return YES;
    for (UIView *sub in v.subviews) {
        if (cellHasNastyContent(sub, depth + 1)) return YES;
    }
    return NO;
}

%hook UIView
- (void)layoutSubviews {
    %orig;
    if (!ads()) return;

    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    if (self.frame.origin.y > (screenH - 150) && self.frame.origin.x > (screenW - 100)) {
        if (self.frame.size.width < 100 && self.frame.size.height < 100) {
            if ([self isKindOfClass:[UIButton class]] || [self isKindOfClass:[UILabel class]]) {
                if (![self.superview isKindOfClass:[UITabBar class]]) {
                    nuke(self);
                    return;
                }
            }
        }
    }

    if (self.frame.origin.y >= (screenH - 100)) {
        NSString *cls = NSStringFromClass([self class]);
        if ([self isKindOfClass:[UITabBar class]] || [cls containsString:@"TabBar"] || [cls containsString:@"Input"]) return;
        if ([cls containsString:@"Banner"] || [cls containsString:@"Ad"] || [cls containsString:@"Pub"]) {
            nuke(self);
            return;
        }
        if ((self.frame.size.height >= 49 && self.frame.size.height <= 51) || 
            (self.frame.size.height >= 89 && self.frame.size.height <= 95)) {
            if (self.subviews.count == 0) nuke(self);
            else self.backgroundColor = [UIColor clearColor];
        }
    }

    if (isViewNasty(self)) {
        nuke(self);
        if (self.superview && self.superview.frame.size.height < 200) {
            nuke(self.superview);
        }
    }
}
%end

%hook UICollectionViewCell
- (void)layoutSubviews {
    %orig;
    if (ads()) {
        if (cellHasNastyContent(self, 0)) {
            nuke(self);
            nuke(self.contentView);
        }
    }
}
%end

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
%end

// --- POPUP BLOCKER ---
%group UpsellBlockers
%hook UIViewController
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)flag completion:(void (^)(void))completion {
    if (en(kIFBlockUpsells)) {
        NSString *name = NSStringFromClass([vc class]);
        if ([name localizedCaseInsensitiveContainsString:@"Premium"] || 
            [name localizedCaseInsensitiveContainsString:@"Subscription"] || 
            [name localizedCaseInsensitiveContainsString:@"Upsell"] ||
            [name localizedCaseInsensitiveContainsString:@"Offer"]) {
            if (completion) completion();
            return;
        }
    }
    %orig;
}

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
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (en(kIFBlockUpsells)) {
        NSString *name = NSStringFromClass([self class]);
        if ([name localizedCaseInsensitiveContainsString:@"Premium"] || 
            [name localizedCaseInsensitiveContainsString:@"Subscription"] || 
            [name localizedCaseInsensitiveContainsString:@"Upsell"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self dismissViewControllerAnimated:NO completion:nil];
            });
        }
    }
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

// --- SHARE SHEET ACTIVITY (DOWNLOAD ONLY) ---
@interface IFDownloadActivity : UIActivity @end
@implementation IFDownloadActivity
- (UIActivityType)activityType { return @"com.ifunnier.download"; }
- (NSString *)activityTitle { return @"Download Video"; }
- (UIImage *)activityImage { return [UIImage systemImageNamed:@"arrow.down.circle.fill"]; }
- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems { return YES; }
- (void)performActivity { downloadLastVideo(); [self activityDidFinish:YES]; }
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
    %init;
    %init(AdBlockers);
    %init(UICleaner);
    %init(UpsellBlockers);
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];
    if (![d objectForKey:kIFBlockUpsells]) [d setBool:YES forKey:kIFBlockUpsells];
    if (![d objectForKey:kIFNoWatermark]) [d setBool:YES forKey:kIFNoWatermark];
}
