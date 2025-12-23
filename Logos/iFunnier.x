#import <UIKit/UIKit.h>

// --- PREFERENCES ---
#define kIFBlockAds @"kIFBlockAds"
#define kIFBlockUpsells @"kIFBlockUpsells"
#define kIFNoWatermark @"kIFNoWatermark"

// --- PREMIUM SPOOFER ---
%group PremiumSpoofer

// Hook the Swift class you found in FLEX
// Class: Premium.PremiumStatusServiceImpl
%hook PremiumStatusServiceImpl

// The "Master Switch" property you found. 
// We force it to return YES (1) to enable Premium.
- (BOOL)isActive {
    return YES; 
}

%end
%end

// --- AD BLOCKING (Clean up any leftovers) ---
%group UICleaner
%hook ALAdService
- (void)loadNextAd:(id)a andNotify:(id)b { }
%end
%hook ISNativeAd
- (void)loadAd { }
%end
%end

%ctor {
    %init(UICleaner);
    
    // Initialize the Premium Hook safely
    // We check for the class name you found: "Premium.PremiumStatusServiceImpl"
    Class premiumClass = objc_getClass("Premium.PremiumStatusServiceImpl");
    
    // Fallback: Try without the "Premium." prefix just in case
    if (!premiumClass) {
        premiumClass = objc_getClass("PremiumStatusServiceImpl");
    }
    
    // If we found the class, activate the hook
    if (premiumClass) {
        %init(PremiumSpoofer, PremiumStatusServiceImpl = premiumClass);
    }
    
    // Set Default Preferences
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d objectForKey:kIFBlockAds]) [d setBool:YES forKey:kIFBlockAds];
}
