//
//  DataStack.h
//  MyMessenger
//
//  Created by Jinwoo Kim on 3/28/25.
//

#import <CoreData/CoreData.h>
#import <CloudKit/CloudKit.h>
#import "Extern.h"

NS_ASSUME_NONNULL_BEGIN

MM_EXTERN NSNotificationName const DataStackDidInitializeNotification;

@interface DataStack : NSObject
@property (class, retain, readonly, nonatomic) DataStack *sharedInstance;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@property (retain, nonatomic, readonly) NSManagedObjectContext *backgroundContext;
@property (retain, nonatomic, readonly) CKContainer *cloudContainer;

@property (assign, nonatomic, readonly, getter=isInitialized) BOOL initialized; // can call from any threads

- (void)didReceiveCloudKitNotification:(__kindof CKNotification *)notification;
@end

NS_ASSUME_NONNULL_END
