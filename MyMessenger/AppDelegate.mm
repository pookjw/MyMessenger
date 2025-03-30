//
//  AppDelegate.mm
//  MyMessenger
//
//  Created by Jinwoo Kim on 3/28/25.
//

#import "AppDelegate.h"
#import "SceneDelegate.h"
#import "DataStack.h"
#import <UserNotifications/UserNotifications.h>

@interface AppDelegate () <UNUserNotificationCenterDelegate>
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [UNUserNotificationCenter currentNotificationCenter].delegate = self;
    [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:UNAuthorizationOptionAlert completionHandler:^(BOOL granted, NSError * _Nullable error) {
        assert(granted);
        assert(error == nil);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [application registerForRemoteNotifications];
        });
    }];
    
    [DataStack sharedInstance];
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [connectingSceneSession.configuration copy];
    configuration.delegateClass = [SceneDelegate class];
    return [configuration autorelease];
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    if (CKNotification *notification = [CKNotification notificationFromRemoteNotificationDictionary:userInfo]) {
        [DataStack.sharedInstance didReceiveCloudKitNotification:notification];
    }
    
    completionHandler(UIBackgroundFetchResultNoData);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler {
    if (CKNotification *notification = [CKNotification notificationFromRemoteNotificationDictionary:response.notification.request.content.userInfo]) {
        [DataStack.sharedInstance didReceiveCloudKitNotification:notification];
    }
    
    completionHandler();
}

@end
