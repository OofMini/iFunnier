#import "../include/iFunnier.h"

// Hardcode preferences for IPA/Sideloading use
// Since we deleted the PreferenceBundle, we force these to YES.
static void loadPreferences() {
    enabled = YES;
    blockAds = YES;
    removeWatermarks = YES;
    saveAnyContent = YES;
}

// --- AD BLOCKING ---
// Wrapped in a group so we can conditionally initialize it
%group AdBlocking
%hook AdvertisementAvailableServiceImpl
- (BOOL)isBannerEnabled { return NO; }
- (BOOL)isNativeEnabled { return NO; }
- (BOOL)isRewardEnabled { return NO; }
%end
%end

// --- SAVING & WATERMARK REMOVAL ---
%hook FCSaveToGalleryActivity

- (void)save {
    // 1. SAFE VARIABLES: Initialize nil to prevent garbage data
    NSURL *gifURL = nil;
    UIImage *image = nil;
    
    // 2. REFLECTION: Safely attempt to pull variables using Key-Value Coding
    // If these keys ('gifURL', 'image') were renamed in a new update, this @catch block prevents a crash.
    @try {
        if ([self respondsToSelector:@selector(valueForKey:)]) {
            gifURL = (NSURL *)[self valueForKey:@"gifURL"];
            image = (UIImage *)[self valueForKey:@"image"];
        }
    } @catch (NSException *e) {
        %orig; // Fallback to default behavior if structure changed
        return;
    }

    // 3. LOGIC:
    if (gifURL) {
        // It's a GIF, run default save (watermark removal on GIFs is hard/unsupported)
        %orig;
    } else if (image) {
        if (removeWatermarks) {
            // SAFE CROP: Ensure image is actually large enough to crop
            if (image.size.height > 22.0) {
                // Crop 20px (watermark) + 1px safety from bottom
                CGRect cropRect = CGRectMake(0, 0, image.size.width, image.size.height - 20);
                CGImageRef imageRef = CGImageCreateWithImageInRect([image CGImage], cropRect);
                UIImage *croppedImage = [UIImage imageWithCGImage:imageRef];
                CGImageRelease(imageRef);
                UIImageWriteToSavedPhotosAlbum(croppedImage, nil, nil, nil);
            } else {
                %orig;
            }
        } else {
            %orig;
        }
    } else {
        // VIDEO SAVING LOGIC
        // This is the most fragile part. We wrap it heavily in try/catch.
        @try {
            // Check if the controller chain exists
            Class controllerClass = %c(FNApplicationController);
            if (controllerClass && [controllerClass respondsToSelector:@selector(instance)]) {
                 
                id instance = [controllerClass instance];
                id adVC = [instance performSelector:@selector(adViewController)];
                id topVC = [adVC performSelector:@selector(topViewController)];
                id activeCell = [topVC performSelector:@selector(activeCell)];
                
                if (activeCell && [activeCell respondsToSelector:@selector(contentData)]) {
                    NSData *contentData = [activeCell contentData];
                    
                    if (contentData) {
                        NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
                        NSString *tmpPath = [docsDir stringByAppendingPathComponent:@"ifunniertmp.mp4"];
                        
                        [contentData writeToFile:tmpPath atomically:YES];
                        
                        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                            [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:[NSURL fileURLWithPath:tmpPath]];
                        } completionHandler:^(BOOL success, NSError *error) {
                            [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
                        }];
                        // Skip %orig because we saved it manually
                    } else {
                        %orig;
                    }
                } else {
                    %orig;
                }
            } else {
                %orig;
            }
        } @catch (NSException *exception) {
            // View hierarchy changed? Just do the normal save.
            %orig;
        }
    }
    
    // Close the menu
    [self saveToGaleryEndedWithError:nil];
}

- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems {
    return YES;
}

%end

// --- TOKEN SAVING ---
%hook IFNetworkService

- (instancetype)initWithNetworkClient:(IFNetworkClientImpl *)client {
    @try {
        if (client && [client respondsToSelector:@selector(authorizationHeader)]) {
            NSString *header = [client authorizationHeader];
            if (header && [header isKindOfClass:[NSString class]]) {
                NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
                NSString *bearerToken = [header stringByReplacingOccurrencesOfString:@"Bearer " withString:@""];
                NSString *tokenPath = [docsDir stringByAppendingPathComponent:@"ifunnierbearertoken.txt"];
                
                [bearerToken writeToFile:tokenPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }
    } @catch (NSException *e) {
        // Ignore token errors
    }
    return %orig;
}

%end

%ctor {
    loadPreferences();
    
    // Initialize hooks
    %init;
    
    // Dynamic initialization for Ad Blocking
    // This checks if the class exists before trying to hook it.
    Class adClass = NSClassFromString(@"AdvertisementAvailableServiceImpl") ?: NSClassFromString(@"libFunny.AdvertisementAvailableServiceImpl");
    if (adClass) {
        %init(AdBlocking, AdvertisementAvailableServiceImpl = adClass);
    }
}