#import <Photos/Photos.h>
#import <UIKit/UIKit.h>

// Inherit from NSObject to prevent compiler errors
@interface IFFeedCell : NSObject
@property NSData *contentData;
@end

@interface IFFeedViewController : NSObject
@property IFFeedCell *activeCell;
@end

@interface IFAdViewcontroller : NSObject
@property IFFeedViewController *topViewController;
@end

@interface FNApplicationController : NSObject
@property IFAdViewcontroller *adViewController;
+ (instancetype)instance;
@end

@interface FCSaveToGalleryActivity : UIActivity
- (void)saveToGaleryEndedWithError:(NSError *)error;
@end

@interface IFNetworkClientImpl : NSObject
- (NSString *)authorizationHeader;
@end
