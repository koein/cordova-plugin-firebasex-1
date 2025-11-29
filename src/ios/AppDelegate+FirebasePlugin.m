#import "AppDelegate+FirebasePlugin.h"
#import "FirebasePlugin.h"
#import "FirebaseWrapper.h"
#import <objc/runtime.h>

@import UserNotifications;
@import FirebaseCore;
@import FirebaseMessaging;

@interface AppDelegate () <UNUserNotificationCenterDelegate, FIRMessagingDelegate>
@end

#define kApplicationInBackgroundKey @"applicationInBackground"

@implementation AppDelegate (FirebasePlugin)

static AppDelegate* instance;
static NSDictionary* mutableUserInfo;
static __weak id <UNUserNotificationCenterDelegate> _prevUserNotificationCenterDelegate = nil;

+ (AppDelegate*) instance {
    return instance;
}

+ (void)load {
    Method original = class_getInstanceMethod(self, @selector(application:didFinishLaunchingWithOptions:));
    Method swizzled = class_getInstanceMethod(self, @selector(application:swizzledDidFinishLaunchingWithOptions:));
    method_exchangeImplementations(original, swizzled);
}

- (void)setApplicationInBackground:(NSNumber *)applicationInBackground {
    objc_setAssociatedObject(self, kApplicationInBackgroundKey, applicationInBackground, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSNumber *)applicationInBackground {
    return objc_getAssociatedObject(self, kApplicationInBackgroundKey);
}

- (BOOL)application:(UIApplication *)application swizzledDidFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [self application:application swizzledDidFinishLaunchingWithOptions:launchOptions];

    instance = self;

    // Firebase Init
    if (![FIRApp defaultApp]) {
        NSString *filePath = [[NSBundle mainBundle] pathForResource:@"GoogleService-Info" ofType:@"plist"];
        if (filePath) {
            FIROptions *options = [[FIROptions alloc] initWithContentsOfFile:filePath];
            [FIRApp configureWithOptions:options];
        } else {
            [FIRApp configure];
        }
    }

    if (self.isFCMEnabled) {
        _prevUserNotificationCenterDelegate = [UNUserNotificationCenter currentNotificationCenter].delegate;
        [UNUserNotificationCenter currentNotificationCenter].delegate = self;

        [FIRMessaging messaging].delegate = self;
    } else {
        [[FIRMessaging messaging] setAutoInitEnabled:NO];
    }

    self.applicationInBackground = @(YES);

    return YES;
}

- (BOOL)isFCMEnabled {
    return FirebasePlugin.firebasePlugin.isFCMEnabled;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    self.applicationInBackground = @(NO);
    [FirebasePlugin.firebasePlugin executeGlobalJavascript:@"FirebasePlugin._applicationDidBecomeActive()"];
    [FirebasePlugin.firebasePlugin sendPendingNotifications];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    self.applicationInBackground = @(YES);
    [FirebasePlugin.firebasePlugin executeGlobalJavascript:@"FirebasePlugin._applicationDidEnterBackground()"];
}

#pragma mark - FIRMessagingDelegate

- (void)messaging:(FIRMessaging *)messaging didReceiveRegistrationToken:(NSString *)fcmToken {
    [FirebasePlugin.firebasePlugin sendToken:fcmToken];
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    if (!self.isFCMEnabled) return;
    [FIRMessaging messaging].APNSToken = deviceToken;
    [FirebasePlugin.firebasePlugin sendApnsToken:[FirebasePlugin.firebasePlugin hexadecimalStringFromData:deviceToken]];
}

#pragma mark - APNS Message Handling

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
    fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {

    if (!self.isFCMEnabled) return;

    mutableUserInfo = [userInfo mutableCopy];

    [[FIRMessaging messaging] appDidReceiveMessage:userInfo];

    [FirebasePlugin.firebasePlugin sendNotification:mutableUserInfo];

    completionHandler(UIBackgroundFetchResultNewData);
}

#pragma mark - Notification Delegates

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {

    NSDictionary *userInfo = notification.request.content.userInfo;

    [[FIRMessaging messaging] appDidReceiveMessage:userInfo];

    [FirebasePlugin.firebasePlugin sendNotification:userInfo];

    completionHandler(UNNotificationPresentationOptionAlert |
                      UNNotificationPresentationOptionSound |
                      UNNotificationPresentationOptionBadge);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
 didReceiveNotificationResponse:(UNNotificationResponse *)response
          withCompletionHandler:(void (^)(void))completionHandler {

    NSDictionary *userInfo = response.notification.request.content.userInfo;

    [[FIRMessaging messaging] appDidReceiveMessage:userInfo];

    [FirebasePlugin.firebasePlugin sendNotification:userInfo];

    completionHandler();
}

@end
