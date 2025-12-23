#import <UIKit/UIKit.h>

// --- PREFERENCES KEYS ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFBlockUpsells @"kIFBlockUpsells"
#define kIFNoWatermark @"kIFNoWatermark"
#define kIFSaveVids @"kIFSaveVids"

// --- INTERFACES ---
@interface iFunnierSettingsViewController : UITableViewController @end

// iFunny Menu Classes (Common names, verify if needed)
@interface FNMenuItem : NSObject
@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) NSString *iconName;
@property (nonatomic, assign) NSInteger type;
+ (instancetype)itemWithTitle:(NSString *)title icon:(NSString *)icon type:(NSInteger)type;
@end

@interface FNMenuViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) NSMutableArray *menuItems;
@property (nonatomic, strong) UITableView *tableView;
@end

// Constants
static const NSInteger kIFunnierSettingsTag = 98765;

// --- SETTINGS VIEW CONTROLLER ---
@implementation iFunnierSettingsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"iFunnier Control";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    
    // Add a Done button
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
}

- (void)close { 
    [self dismissViewControllerAnimated:YES completion:nil]; 
}

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
    
    if (indexPath.row == 0) { 
        txt = @"Block Ads / Upsells"; 
        on = [d boolForKey:kIFBlockAds];
    }
    else if (indexPath.row == 1) { 
        txt = @"No Watermark"; 
        on = [d boolForKey:kIFNoWatermark];
    }
    else if (indexPath.row == 2) { 
        txt = @"Auto-Save Video"; 
        on = [d boolForKey:kIFSaveVids];
    }
    
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

// --- SIDEBAR INTEGRATION HOOK ---
%hook FNMenuViewController

- (void)viewDidLoad {
    %orig;
    [self insertIFunnierSettings];
}

- (void)reloadMenu {
    %orig;
    [self insertIFunnierSettings];
}

%new
- (void)insertIFunnierSettings {
    NSMutableArray *items = [self.menuItems mutableCopy];
    if (!items) return;

    // Avoid duplicates
    for (FNMenuItem *item in items) {
        if ([item respondsToSelector:@selector(type)] && item.type == kIFunnierSettingsTag) {
            return;
        }
    }

    // Find "Featured" to insert ABOVE it
    NSUInteger insertIndex = 0;
    BOOL foundFeatured = NO;

    for (NSUInteger i = 0; i < items.count; i++) {
        FNMenuItem *item = items[i];
        if ([[item.title lowercaseString] containsString:@"featured"]) {
            insertIndex = i;
            foundFeatured = YES;
            break;
        }
    }

    // Fallback if Featured isn't found
    if (!foundFeatured && items.count > 0) {
        insertIndex = 1;
    }

    // Create Item (Icon name "gear" or "settings" usually works if assets exist, or uses default)
    FNMenuItem *newItem = [%c(FNMenuItem) itemWithTitle:@"iFunnier" 
                                                   icon:@"gear" 
                                                   type:kIFunnierSettingsTag];

    [items insertObject:newItem atIndex:insertIndex];
    self.menuItems = items;
    [self.tableView reloadData];
}

// Handle Tap
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // Check range
    if (indexPath.row >= self.menuItems.count) {
        %orig; 
        return;
    }

    FNMenuItem *selectedItem = self.menuItems[indexPath.row];

    if ([selectedItem respondsToSelector:@selector(type)] && selectedItem.type == kIFunnierSettingsTag) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];

        // Present Settings
        iFunnierSettingsViewController *vc = [[iFunnierSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        [self presentViewController:nav animated:YES completion:nil];
        
        return;
    }

    %orig;
}

%end
