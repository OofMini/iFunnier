#import "../include/iFunnier.h"
#import <UIKit/UIKit.h>

// --- PREFS KEYS ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFNoWatermark @"kIFNoWatermark"
#define kIFSaveVids @"kIFSaveVids"

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
    
    if (indexPath.row == 0) { txt = @"Block Ads"; on = [d boolForKey:kIFBlockAds]; }
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

// --- DOWNLOAD HELPER ---
void downloadVideo() {
    @try {
        Class app = NSClassFromString(@"FNApplicationController");
        if (app) {
            id inst = [app performSelector:@selector(instance)];
            id adVC = [inst performSelector:@selector(adViewController)];
            id topVC = [adVC performSelector:@selector(topViewController)];
            id cell = [topVC performSelector:@selector(activeCell)];
            if (cell && [cell respondsToSelector:@selector(contentData)]) {
                NSData *d = [cell contentData];
                if (d) {
                    NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:@"if_dl.mp4"];
                    [d writeToFile:p atomically:YES];
                    if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(p)) {
                        UISaveVideoAtPathToSavedPhotosAlbum(p, nil, nil, nil);
                    } else {
                         UIImage *img = [UIImage imageWithData:d];
                         if (img) UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
                    }
                    
                    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Saved!" message:nil preferredStyle:UIAlertControllerStyleAlert];
                    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:a animated:YES completion:nil];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [a dismissViewControllerAnimated:YES completion:nil];
                    });
                }
            }
        }
    } @catch (NSException *e) {}
}

// --- NATIVE SHARE SHEET BUTTON ---
@interface IFDownloadActivity : UIActivity
@end

@implementation IFDownloadActivity
- (UIActivityType)activityType { return @"com.ifunnier.download"; }
- (NSString *)activityTitle { return @"Download Video"; }
- (UIImage *)activityImage { return [UIImage systemImageNamed:@"arrow.down.circle.fill"]; }
- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems { return YES; }
- (void)performActivity { downloadVideo(); [self activityDidFinish:YES]; }
+ (UIActivityCategory)activityCategory { return UIActivityCategoryAction; }
@end

%hook UIActivityViewController
- (instancetype)initWithActivityItems:(NSArray *)items applicationActivities:(NSArray *)activities {
    NSMutableArray *newActivities = [NSMutableArray arrayWithArray:activities];
    [newActivities addObject:[[IFDownloadActivity alloc] init]];
    return %orig(items, newActivities);
}
%end

// --- FIX: Explicitly define the class so compiler knows it has a 'view' ---
@interface IFActivitiesViewController : UIViewController
@end

%hook IFActivitiesViewController
- (void)viewDidLoad {
    %orig;
    
    // Inject a "Download" button
    UIButton *dlBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [dlBtn setTitle:@"Save No Watermark" forState:UIControlStateNormal];
    [dlBtn setImage:[UIImage systemImageNamed:@"arrow.down.circle"] forState:UIControlStateNormal];
    [dlBtn setBackgroundColor:[UIColor systemBlueColor]];
    [dlBtn setTintColor:[UIColor whiteColor]];
    dlBtn.layer.cornerRadius = 10;
    dlBtn.frame = CGRectMake(20, 20, self.view.frame.size.width - 40, 50); // Now self.view is valid
    
    [dlBtn addTarget:self action:@selector(manualDownload) forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:dlBtn];
    [self.view bringSubviewToFront:dlBtn];
}

%new
- (void)manualDownload {
    downloadVideo();
}
%end

// --- SETTINGS BUTTON ---
// Interface to declare the new method exists
@interface UINavigationItem (iFunnier)
- (void)openIFSettings;
@end

%hook UINavigationItem
- (void)setTitle:(NSString *)title {
    %orig;
    if ([title isEqualToString:@"Settings"] || [title isEqualToString:@"Profile"] || [title isEqualToString:@"More"]) {
        UIBarButtonItem *btn = [[UIBarButtonItem alloc] initWithTitle:@"iFunnier" 
                                                                style:UIBarButtonItemStylePlain 
                                                               target:self 
                                                               action:@selector(openIFSettings)];
        [btn setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor systemOrangeColor], NSFontAttributeName:[UIFont boldSystemFontOfSize:16]} forState:UIControlStateNormal];
        self.rightBarButtonItem = btn;
    }
}

%new
- (void)openIFSettings {
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    iFunnierSettingsViewController *vc = [[iFunnierSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [root presentViewController:nav animated:YES completion:nil];
}
%end

// --- TRIPLE TAP BACKUP ---
%hook UIWindow
- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (event.type == UIEventTypeTouches) {
        NSSet *t = [event allTouches];
        if ([[t anyObject] phase] == UITouchPhaseBegan && t.count == 3) {
             // FIX: Cast the navigationItem to id so compiler doesn't check selector
             id navItem = self.rootViewController.navigationItem;
             if ([navItem respondsToSelector:@selector(openIFSettings)]) {
                 [navItem performSelector:@selector(openIFSettings)];
             }
        }
    }
}
%end

// --- AD BLOCK LOGIC ---
BOOL en(NSString *k) { return [[NSUserDefaults standardUserDefaults] boolForKey:k]; }
%group Ads
BOOL blk() { return en(kIFBlockAds); }
%hook ALAdService
- (void)loadNextAd:(id)a andNotify:(id)b { if(blk()) return; %orig; }
%end
%hook IMBanner
- (void)load { if(blk()) return; %orig; }
%end
%hook PAGBannerAd
- (void)loadAd:(id)a { if(blk()) return; %orig; }
%end
%hook DTBAdLoader
- (void)loadAd:(id)a { if(blk()) return; %orig; }
%end
%end

%ctor {
    %init;
    %init(Ads);
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];
    if (![d objectForKey:kIFNoWatermark]) [d setBool:YES forKey:kIFNoWatermark];
}
