#import "AppDelegate+FirebasePlugin.h"
#import "FirebasePlugin.h"
#import "FirebaseWrapper.h"
#import <objc/runtime.h>

@import UserNotifications;
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

#if DEBUG
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"/google/firebase/debug_mode"];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"/google/measurement/debug_mode"];
#endif

    @try {
        instance = self;

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

    } @catch (NSException *exception) {
        [FirebasePlugin.firebasePlugin handlePluginExceptionWithoutContext:exception];
    }

    return YES;
}

- (BOOL)isFCMEnabled {
    return FirebasePlugin.firebasePlugin.isFCMEnabled;
}

#pragma mark - App State

- (void)applicationDidBecomeActive:(UIApplication *)application {
    self.applicationInBackground = @(NO);

    @try {
        [FirebasePlugin.firebasePlugin executeGlobalJavascript:@"FirebasePlugin._applicationDidBecomeActive()"];
        [FirebasePlugin.firebasePlugin sendPendingNotifications];
    } @catch (NSException *exception) {}
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    self.applicationInBackground = @(YES);

    @try {
        [FirebasePlugin.firebasePlugin executeGlobalJavascript:@"FirebasePlugin._applicationDidEnterBackground()"];
    } @catch (NSException *exception) {}
}

#pragma mark - FCM Token

- (void)messaging:(FIRMessaging *)messaging didReceiveRegistrationToken:(NSString *)fcmToken {
    @try {
        [FirebasePlugin.firebasePlugin sendToken:fcmToken];
    } @catch (NSException *exception) {}
}

#pragma mark - APNS

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    if (!self.isFCMEnabled) return;

    [FIRMessaging messaging].APNSToken = deviceToken;
    [FirebasePlugin.firebasePlugin sendApnsToken:[FirebasePlugin.firebasePlugin hexadecimalStringFromData:deviceToken]];
}

#pragma mark - Notification Handling

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {

    if (!self.isFCMEnabled) return;

    mutableUserInfo = [userInfo mutableCopy];

    completionHandler(UIBackgroundFetchResultNewData);
    [FirebasePlugin.firebasePlugin sendNotification:mutableUserInfo];
}

@end
