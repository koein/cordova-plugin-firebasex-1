#import "FirebasePlugin.h"
#import <FirebaseCore/FirebaseCore.h>
#import <FirebaseMessaging/FirebaseMessaging.h>
#import <FirebaseCrashlytics/FirebaseCrashlytics.h>
#import <UserNotifications/UserNotifications.h>

@interface FirebasePlugin () <UNUserNotificationCenterDelegate, FIRMessagingDelegate>
@end

@implementation FirebasePlugin

static FirebasePlugin* firebasePlugin;

+ (FirebasePlugin*)firebasePlugin {
    return firebasePlugin;
}

- (void)pluginInitialize {
    firebasePlugin = self;

    // Configure Firebase if not already configured
    if (![FIRApp defaultApp]) {
        NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"GoogleService-Info" ofType:@"plist"];
        if (plistPath) {
            FIROptions *options = [[FIROptions alloc] initWithContentsOfFile:plistPath];
            [FIRApp configureWithOptions:options];
        } else {
            [FIRApp configure];
        }
    }

    // Enable Crashlytics
    [FIRCrashlytics crashlytics];

    // Setup FCM
    [UNUserNotificationCenter currentNotificationCenter].delegate = self;
    [FIRMessaging messaging].delegate = self;

    [[UNUserNotificationCenter currentNotificationCenter]
     requestAuthorizationWithOptions:(UNAuthorizationOptionAlert |
                                      UNAuthorizationOptionSound |
                                      UNAuthorizationOptionBadge)
     completionHandler:^(BOOL granted, NSError * _Nullable error) {}];

    [[UIApplication sharedApplication] registerForRemoteNotifications];
}

#pragma mark - FCM Token
- (void)messaging:(FIRMessaging *)messaging didReceiveRegistrationToken:(NSString *)fcmToken {
    if (!fcmToken) return;
    NSString *js = [NSString stringWithFormat:@"FirebasePlugin._onToken('%@')", fcmToken];
    [self.commandDelegate evalJs:js];
}

#pragma mark - APNS
- (void)application:(UIApplication *)application
didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {

    [FIRMessaging messaging].APNSToken = deviceToken;
}

#pragma mark - Receive notification
- (void)application:(UIApplication *)application
didReceiveRemoteNotification:(NSDictionary *)userInfo
fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {

    NSString *js = [NSString stringWithFormat:@"FirebasePlugin._onMessage(%@)",
                    [self dictionaryToJson:userInfo]];
    [self.commandDelegate evalJs:js];

    completionHandler(UIBackgroundFetchResultNewData);
}

#pragma mark - Helpers
- (NSString*)dictionaryToJson:(NSDictionary*)dict {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&error];
    if (!jsonData) return @"{}";
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

@end
