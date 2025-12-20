#import "../include/iFunnier.h"
#import <UIKit/UIKit.h>

// --- PREFERENCES KEYS ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFNoWatermark @"kIFNoWatermark"
#define kIFSaveVids @"kIFSaveVids"

// --- SETTINGS VIEW CONTROLLER ---
@interface iFunnierSettingsViewController : UITableViewController
@end

@implementation iFunnierSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"iFunnier Settings";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    
    // Add "Close" button
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeSettings)];
}

- (void)closeSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    toggle.tag = indexPath.row;
    
    NSString *text = @"";
    BOOL isOn = NO;
    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    
    if (indexPath.row == 0) {
        text = @"Block Ads (Nuclear)";
        isOn = [prefs boolForKey:kIFBlockAds];
    } else if (indexPath.row == 1) {
        text = @"Remove Watermarks";
        isOn = [prefs boolForKey:kIFNoWatermark];
    } else if (indexPath.row == 2) {
        text = @"Save Videos";
        isOn = [prefs boolForKey:kIFSaveVids];
    }
    
    cell.textLabel.text = text;
    [toggle setOn:isOn animated:NO];
    cell.accessoryView = toggle;
    
    return cell;
}

- (void)toggleChanged:(UISwitch *)sender {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSString *key = @"";
    
    if (sender.tag == 0) key = kIFBlockAds;
    else if (sender.tag == 1) key = kIFNoWatermark;
    else if (sender.tag == 2) key = kIFSaveVids;
    
    [prefs setBool:sender.isOn forKey:key];
    [prefs synchronize];
}

@end

// --- HELPER: CHECK SETTINGS ---
BOOL isFeatureEnabled(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

// --- 1. NUCLEAR AD BLOCKING (Gated by Settings) ---
%group AdBlockers

// Helper to check if we should block
BOOL shouldBlock() { return isFeatureEnabled(kIFBlockAds); }

// AppLovin (MAX)
%hook ALAdService
- (void)loadNextAd:(id)arg1 andNotify:(id)arg2 { if(shouldBlock()) return; %orig; }
- (void)loadNextAd:(id)arg1 { if(shouldBlock()) return; %orig; }
%end

%hook ALInterstitialAd
- (void)show { if(shouldBlock()) return; %orig; }
- (void)showOver:(id)arg1 { if(shouldBlock()) return; %orig; }
%end

// InMobi
%hook IMBanner
- (void)load { if(shouldBlock()) return; %orig; }
- (void)shouldAutoRefresh:(BOOL)arg1 { if(shouldBlock()) return %orig(NO); return %orig; }
%end

// Pangle
%hook PAGBannerAd
- (void)loadAd:(id)arg1 { if(shouldBlock()) return; %orig; }
%end

// Amazon
%hook DTBAdLoader
- (void)loadAd:(id)arg1 { if(shouldBlock()) return; %orig; }
%end

%end // End AdBlockers Group


// --- 2. SAVING & WATERMARK (Gated by Settings) ---
%hook FCSaveToGalleryActivity

- (void)save {
    // Check Settings First
    BOOL noWatermark = isFeatureEnabled(kIFNoWatermark);
    BOOL saveVideo = isFeatureEnabled(kIFSaveVids);
    
    NSURL *gifURL = nil;
    UIImage *image = nil;
    
    @try {
        if ([self respondsToSelector:@selector(valueForKey:)]) {
            gifURL = (NSURL *)[self valueForKey:@"gifURL"];
            image = (UIImage *)[self valueForKey:@"image"];
        }
    } @catch (NSException *e) {
        %orig; return;
    }

    if (gifURL) {
        %orig;
    } else if (image) {
        // IMAGE LOGIC
        if (noWatermark && image.size.height > 22.0) {
            // Crop Watermark
            CGRect cropRect = CGRectMake(0, 0, image.size.width, image.size.height - 20);
            CGImageRef imageRef = CGImageCreateWithImageInRect([image CGImage], cropRect);
            UIImage *croppedImage = [UIImage imageWithCGImage:imageRef];
            CGImageRelease(imageRef);
            UIImageWriteToSavedPhotosAlbum(croppedImage, nil, nil, nil);
        } else {
            %orig;
        }
    } else {
        // VIDEO LOGIC
        if (saveVideo) {
             @try {
                Class controllerClass = %c(FNApplicationController);
                if (controllerClass && [controllerClass respondsToSelector:@selector(instance)]) {
                    id instance = [controllerClass instance];
                    id adVC = [instance performSelector:@selector(adViewController)];
                    id topVC = [adVC performSelector:@selector(topViewController)];
                    id activeCell = [topVC performSelector:@selector(activeCell)];
                    
                    if (activeCell && [activeCell respondsToSelector:@selector(contentData)]) {
                        NSData *contentData = [activeCell contentData];
                        if (contentData) {
                            NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ifunniertmp.mp4"];
                            [contentData writeToFile:tmpPath atomically:YES];
                            UISaveVideoAtPathToSavedPhotosAlbum(tmpPath, nil, nil, nil);
                        } else { %orig; }
                    } else { %orig; }
                } else { %orig; }
            } @catch (NSException *e) { %orig; }
        } else {
            %orig;
        }
    }
    [self saveToGaleryEndedWithError:nil];
}
%end

// --- 3. MENU TRIGGER (Triple Tap) ---
%hook UIWindow
- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (event.type == UIEventTypeTouches) {
        NSSet *touches = [event allTouches];
        UITouch *touch = [touches anyObject];
        // 3 Fingers = Open Menu
        if (touch.phase == UITouchPhaseBegan && touches.count == 3) {
            UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
            while (rootVC.presentedViewController) {
                rootVC = rootVC.presentedViewController;
            }
            
            iFunnierSettingsViewController *settingsVC = [[iFunnierSettingsViewController alloc] initWithStyle:UITableViewStyleGrouped];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
            [rootVC presentViewController:nav animated:YES completion:nil];
        }
    }
}
%end

%ctor {
    %init;
    %init(AdBlockers);
    
    // Set Defaults if not set
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    if ([prefs objectForKey:kIFBlockAds] == nil) [prefs setBool:YES forKey:kIFBlockAds];
    if ([prefs objectForKey:kIFNoWatermark] == nil) [prefs setBool:YES forKey:kIFNoWatermark];
    if ([prefs objectForKey:kIFSaveVids] == nil) [prefs setBool:YES forKey:kIFSaveVids];
}
