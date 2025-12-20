#import "../include/iFunnier.h"
#import <UIKit/UIKit.h>

// --- HELPER ALERTS ---
void showDebugAlert(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        
        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }
        [rootVC presentViewController:alert animated:YES completion:nil];
    });
}

// --- 1. NUCLEAR AD BLOCKING (Hooks SDKs directly - Default Group) ---

// AppLovin (MAX)
%hook ALAdService
- (void)loadNextAd:(id)arg1 andNotify:(id)arg2 { } // Block loading
- (void)loadNextAd:(id)arg1 { }
%end

%hook ALInterstitialAd
- (void)show { } // Block show
- (void)showOver:(id)arg1 { }
%end

// InMobi
%hook IMBanner
- (void)load { }
- (void)shouldAutoRefresh:(BOOL)arg1 { %orig(NO); }
%end

%hook IMInterstitial
- (void)load { }
- (void)showFrom:(id)arg1 { }
%end

// Pangle (Bytedance/TikTok Ads)
%hook PAGBannerAd
- (void)loadAd:(id)arg1 { }
%end

%hook PAGInterstitialAd
- (void)loadAd:(id)arg1 { }
%end

// Amazon Publisher Services (DTB)
%hook DTBAdLoader
- (void)loadAd:(id)arg1 { }
%end

// --- 2. IFUNNY SPECIFIC HOOKS (Legacy Support) ---
// FIX: Moved to a named group to prevent "re-init" errors
%group LegacyAds
%hook AdvertisementAvailableServiceImpl
- (BOOL)isBannerEnabled { return NO; }
- (BOOL)isNativeEnabled { return NO; }
- (BOOL)isRewardEnabled { return NO; }
%end
%end

// --- 3. SAVING & WATERMARK REMOVAL (Default Group) ---
%hook FCSaveToGalleryActivity

- (void)save {
    NSURL *gifURL = nil;
    UIImage *image = nil;
    
    @try {
        if ([self respondsToSelector:@selector(valueForKey:)]) {
            gifURL = (NSURL *)[self valueForKey:@"gifURL"];
            image = (UIImage *)[self valueForKey:@"image"];
        }
    } @catch (NSException *e) {
        showDebugAlert(@"Save Error", @"Could not find image data. iFunny changed the class structure.");
        %orig; 
        return;
    }

    if (gifURL) {
        %orig;
    } else if (image) {
        if (image.size.height > 22.0) {
            CGRect cropRect = CGRectMake(0, 0, image.size.width, image.size.height - 20);
            CGImageRef imageRef = CGImageCreateWithImageInRect([image CGImage], cropRect);
            UIImage *croppedImage = [UIImage imageWithCGImage:imageRef];
            CGImageRelease(imageRef);
            UIImageWriteToSavedPhotosAlbum(croppedImage, nil, nil, nil);
            showDebugAlert(@"iFunnier", @"Image Saved (No Watermark)");
        } else {
            %orig;
        }
    } else {
        // Video Logic
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
                        showDebugAlert(@"iFunnier", @"Video Saved!");
                    } else { %orig; }
                } else { %orig; }
            } else { %orig; }
        } @catch (NSException *exception) {
            %orig;
        }
    }
    [self saveToGaleryEndedWithError:nil];
}
%end

// --- 4. DIAGNOSTIC TOOLS (Default Group) ---
%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        showDebugAlert(@"iFunnier", @"Tweak Injected Successfully!\n\nTap with 3 fingers to identify screens.");
    });
}

- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (event.type == UIEventTypeTouches) {
        NSSet *touches = [event allTouches];
        UITouch *touch = [touches anyObject];
        if (touch.phase == UITouchPhaseBegan && touches.count == 3) {
            UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
            while (topVC.presentedViewController) topVC = topVC.presentedViewController;
            
            NSString *msg = [NSString stringWithFormat:@"Current VC: %@", NSStringFromClass([topVC class])];
            showDebugAlert(@"Inspector", msg);
        }
    }
}
%end

%ctor {
    %init; // Initialize Default Group (SDK Blockers, Saving, Inspector)
    
    // Check for Legacy Ad Class
    Class oldAdClass = NSClassFromString(@"AdvertisementAvailableServiceImpl") ?: NSClassFromString(@"libFunny.AdvertisementAvailableServiceImpl");
    if (oldAdClass) {
        // FIX: Initialize ONLY the LegacyAds group
        %init(LegacyAds, AdvertisementAvailableServiceImpl = oldAdClass);
    }
}
