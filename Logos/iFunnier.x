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

// --- HELPERS ---
void showToast(NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"iFunnier" message:msg preferredStyle:UIAlertControllerStyleAlert];
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:a animated:YES completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [a dismissViewControllerAnimated:YES completion:nil];
        });
    });
}

void openSettingsMenu() {
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    iFunnierSettingsViewController *vc = [[iFunnierSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [root presentViewController:nav animated:YES completion:nil];
}

// --- DOWNLOAD LOGIC ---
void saveVideoData(NSData *data) {
    if (!data) { showToast(@"Error: Data was empty"); return; }
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"if_%@.mp4", [[NSUUID UUID] UUIDString]]];
    [data writeToFile:path atomically:YES];
    
    if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(path)) {
        UISaveVideoAtPathToSavedPhotosAlbum(path, nil, nil, nil);
        showToast(@"✅ Video Saved");
    } else {
        UIImage *img = [UIImage imageWithData:data];
        if (img) {
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
            showToast(@"✅ Image Saved");
        } else { showToast(@"❌ Unknown Media"); }
    }
}

void attemptScraperDownload() {
    @try {
        Class app = NSClassFromString(@"FNApplicationController");
        if (!app) { showToast(@"❌ App Controller Not Found"); return; }
        id inst = [app performSelector:@selector(instance)];
        id adVC = [inst performSelector:@selector(adViewController)];
        id topVC = [adVC performSelector:@selector(topViewController)];
        id cell = [topVC performSelector:@selector(activeCell)];
        if (cell && [cell respondsToSelector:@selector(contentData)]) {
            NSData *d = [cell contentData];
            if (d && d.length > 0) saveVideoData(d);
            else showToast(@"❌ No Data in Cell");
        } else { showToast(@"❌ No Active Cell Found"); }
    } @catch (NSException *e) { showToast(@"❌ Crash in Scraper"); }
}

// --- BUTTON 1: DOWNLOAD ---
@interface IFDownloadActivity : UIActivity
@property (nonatomic, strong) NSArray *activityItems;
@end
@implementation IFDownloadActivity
- (UIActivityType)activityType { return @"com.ifunnier.download"; }
- (NSString *)activityTitle { return @"Download Video"; }
- (UIImage *)activityImage { return [UIImage systemImageNamed:@"arrow.down.circle.fill"]; }
- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems { return YES; }
- (void)prepareWithActivityItems:(NSArray *)activityItems { self.activityItems = activityItems; }
- (void)performActivity {
    BOOL found = NO;
    for (id item in self.activityItems) {
        if ([item isKindOfClass:[NSURL class]] && [(NSURL *)item isFileURL]) {
            saveVideoData([NSData dataWithContentsOfURL:(NSURL *)item]);
            found = YES; break;
        } else if ([item isKindOfClass:[NSData class]]) {
            saveVideoData((NSData *)item);
            found = YES; break;
        }
    }
    if (!found) attemptScraperDownload();
    [self activityDidFinish:YES];
}
+ (UIActivityCategory)activityCategory { return UIActivityCategoryAction; }
@end

// --- BUTTON 2: SETTINGS (NEW) ---
@interface IFSettingsActivity : UIActivity
@end
@implementation IFSettingsActivity
- (UIActivityType)activityType { return @"com.ifunnier.settings"; }
- (NSString *)activityTitle { return @"iFunnier Settings"; }
- (UIImage *)activityImage { return [UIImage systemImageNamed:@"gear"]; }
- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems { return YES; }
- (void)performActivity {
    openSettingsMenu(); // Open our menu
    [self activityDidFinish:YES];
}
+ (UIActivityCategory)activityCategory { return UIActivityCategoryAction; }
@end

// --- HOOK SYSTEM SHARE SHEET ---
%hook UIActivityViewController
- (instancetype)initWithActivityItems:(NSArray *)items applicationActivities:(NSArray *)activities {
    NSMutableArray *newActivities = [NSMutableArray arrayWithArray:activities];
    // Add BOTH buttons
    [newActivities addObject:[[IFDownloadActivity alloc] init]];
    [newActivities addObject:[[IFSettingsActivity alloc] init]];
    return %orig(items, newActivities);
}
%end

// --- LEGACY/CUSTOM SHARE SHEET BACKUP ---
@interface IFActivitiesViewController : UIViewController
@end
%hook IFActivitiesViewController
- (void)viewDidLoad {
    %orig;
    // Add floating Settings Button to custom sheet
    UIButton *setBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [setBtn setTitle:@"⚙️ Settings" forState:UIControlStateNormal];
    [setBtn setBackgroundColor:[UIColor systemGrayColor]];
    [setBtn setTintColor:[UIColor whiteColor]];
    setBtn.layer.cornerRadius = 8;
    setBtn.frame = CGRectMake(16, 70, 140, 44); // Below the download button
    [setBtn addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:setBtn];
}
%new
- (void)openSettings { openSettingsMenu(); }
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

// --- ADS ---
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
