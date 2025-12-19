#import "../include/iFunnier.h"

// --- AD BLOCKING ---
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
        // It's a GIF, run default save
        %orig;
    } else if (image) {
        // SAFE CROP: Ensure image is actually large enough to crop
        if (image.size.height > 22.0) {
            // Crop 20px (watermark)
            CGRect cropRect = CGRectMake(0, 0, image.size.width, image.size.height - 20);
            CGImageRef imageRef = CGImageCreateWithImageInRect([image CGImage], cropRect);
            UIImage *croppedImage = [UIImage imageWithCGImage:imageRef];
            CGImageRelease(imageRef);
            UIImageWriteToSavedPhotosAlbum(croppedImage, nil, nil, nil);
        } else {
            %orig;
        }
    } else {
        // VIDEO SAVING LOGIC
        // Wrapped heavily in try/catch because view hierarchy changes often.
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
                        NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
                        NSString *tmpPath = [docsDir stringByAppendingPathComponent:@"ifunniertmp.mp4"];
                        
                        [contentData writeToFile:tmpPath atomically:YES];
                        
                        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                            [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:[NSURL fileURLWithPath:tmpPath]];
                        } completionHandler:^(BOOL success, NSError *error) {
                            [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
                        }];
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
        // FIX: Cast to (id) to ensure the compiler allows 'respondsToSelector' check
        if (client && [(id)client respondsToSelector:@selector(authorizationHeader)]) {
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
    %init;
    Class adClass = NSClassFromString(@"AdvertisementAvailableServiceImpl") ?: NSClassFromString(@"libFunny.AdvertisementAvailableServiceImpl");
    if (adClass) {
        %init(AdBlocking, AdvertisementAvailableServiceImpl = adClass);
    }
}
