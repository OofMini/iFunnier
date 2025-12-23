#import <UIKit/UIKit.h>

// --- SETTINGS VIEW CONTROLLER ---
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
    UISwitch *sw = [UISwitch new];
    sw.tag = indexPath.row;
    [sw addTarget:self action:@selector(t:) forControlEvents:UIControlEventValueChanged];
    
    NSString *txt = @"";
    NSString *key = @"";
    if (indexPath.row == 0) { txt = @"Block Ads"; key = @"kIFBlockAds"; }
    else if (indexPath.row == 1) { txt = @"No Watermark"; key = @"kIFNoWatermark"; }
    else if (indexPath.row == 2) { txt = @"Block Upsells"; key = @"kIFBlockUpsells"; }
    
    cell.textLabel.text = txt;
    [sw setOn:[[NSUserDefaults standardUserDefaults] boolForKey:key] animated:NO];
    cell.accessoryView = sw;
    return cell;
}
- (void)t:(UISwitch *)s {
    NSString *k = (s.tag==0)?@"kIFBlockAds":(s.tag==1)?@"kIFNoWatermark":@"kIFBlockUpsells";
    [[NSUserDefaults standardUserDefaults] setBool:s.isOn forKey:k];
}
@end

// --- MENU HOOK ---
// Class: Menu.MenuViewController
%group MenuHook

%hook MenuViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    // Check if we already added the button
    if (self.navigationItem.rightBarButtonItem && self.navigationItem.rightBarButtonItem.tag == 999) {
        return;
    }
    
    // Create a "Gear" icon button
    UIBarButtonItem *settingsBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gear"] 
                                                                    style:UIBarButtonItemStylePlain 
                                                                   target:self 
                                                                   action:@selector(openIFunnierSettings)];
    settingsBtn.tag = 999; // Tag to identify our button
    
    // Add it to the top right of the menu
    self.navigationItem.rightBarButtonItem = settingsBtn;
}

%new
- (void)openIFunnierSettings {
    iFunnierSettingsViewController *vc = [[iFunnierSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
}

%end
%end

%ctor {
    // Initialize the Menu Hook
    // Class name found in FLEX: "Menu.MenuViewController"
    Class menuClass = objc_getClass("Menu.MenuViewController");
    
    if (!menuClass) {
        menuClass = objc_getClass("MenuViewController");
    }
    
    if (menuClass) {
        %init(MenuHook, MenuViewController = menuClass);
    }
}
