//
//  DataStack.mm
//  MyMessenger
//
//  Created by Jinwoo Kim on 3/28/25.
//

#import "DataStack.h"
#import "Chatroom+CoreDataProperties.h"
#import "User+CoreDataProperties.h"
#import "Message+CoreDataProperties.h"
#import "CloudRecordMap+CoreDataProperties.h"

NSNotificationName const DataStackDidInitializeNotification = @"DataStackDidInitializeNotification";

@interface DataStack () {
    BOOL _ignoreSaveNotification;
}
@property (retain, nonatomic, readonly, getter=_isolated_records) NSMutableArray<CKRecord *> *isolated_records;
@property (class, copy, nonatomic, nullable, getter=_serverChangeToken, setter=_setServerChangeToken:) CKServerChangeToken *serverChangeToken;
@end

@implementation DataStack
@synthesize isolated_records = _recods;

+ (DataStack *)sharedInstance {
    static DataStack *instance;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DataStack new];
    });
    
    return instance;
}

+ (NSURL *)_localStoreURLWithCreatingDirectory:(BOOL)createDirectory __attribute__((objc_direct)) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *applicationSupportURL = [fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask][0];
    NSURL *containerURL = [applicationSupportURL URLByAppendingPathComponent:[NSBundle bundleForClass:[self class]].bundleIdentifier];
    
    if (createDirectory) {
        BOOL isDirectory;
        BOOL exists = [fileManager fileExistsAtPath:containerURL.path isDirectory:&isDirectory];
        
        NSError * _Nullable error = nil;
        
        if (!exists) {
            [fileManager createDirectoryAtURL:containerURL withIntermediateDirectories:YES attributes:nil error:&error];
            assert(error == nil);
        } else {
            assert(isDirectory);
        }
    }
    
    NSURL *result = [[containerURL URLByAppendingPathComponent:@"container"] URLByAppendingPathExtension:@"sqlite"];
    return result;
}

- (instancetype)init {
    if (self = [super init]) {
        NSManagedObjectContext *backgroundContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        
        CKContainer *cloudContainer = [CKContainer containerWithIdentifier:@"iCloud.com.pookjw.BabiFud"];
        _cloudContainer = [cloudContainer retain];
        
        _backgroundContext = backgroundContext;
        _recods = [NSMutableArray new];
        
        [backgroundContext performBlock:^{
            NSURL *modelURL = [NSBundle.mainBundle URLForResource:@"Model" withExtension:@"mom" subdirectory:@"Model.momd"];
            assert(modelURL != nil);
            NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
            
            NSPersistentContainer *persistentContainer = [[NSPersistentContainer alloc] initWithName:@"Model" managedObjectModel:model];
            [model release];
            
            NSPersistentStoreDescription *description = [[NSPersistentStoreDescription alloc] initWithURL:[DataStack _localStoreURLWithCreatingDirectory:YES]];
            NSLog(@"%@", description.URL.path);
            description.type = NSSQLiteStoreType;
            description.shouldAddStoreAsynchronously = NO;
            description.shouldInferMappingModelAutomatically = NO;
            [description setOption:@YES forKey:NSPersistentHistoryTrackingKey];
            
            persistentContainer.persistentStoreDescriptions = @[description];
            [description release];
            
            [persistentContainer loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription * _Nonnull description, NSError * _Nullable error) {
                assert(error == nil);
            }];
            
            backgroundContext.persistentStoreCoordinator = persistentContainer.persistentStoreCoordinator;
            [persistentContainer release];
            
            [NSNotificationCenter.defaultCenter postNotificationName:DataStackDidInitializeNotification object:self];
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_didSave:) name:NSManagedObjectContextDidSaveNotification object:backgroundContext];
            
            [self _addCloudSubscriptionWithCompletionHandler:^{
                [self _mirrorContainer];
            }];
        }];
    }
    
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_backgroundContext release];
    [_cloudContainer release];
    [_recods release];
    [super dealloc];
}

- (BOOL)isInitialized {
    return self.backgroundContext.persistentStoreCoordinator != nil;
}

- (void)didReceiveCloudKitNotification:(__kindof CKNotification *)notification {
    [self _mirrorContainer];
}

- (void)_mirrorContainer {
    [self _zoneWithCompletionHandler:^(CKRecordZone *recordZone) {
        [self _recordsWithZone:recordZone completionHandler:^ (NSSet<CKRecord *> *updatedRecords, NSDictionary<CKRecordID *, CKRecordType> *deletedRecordIDs) {
            [self.backgroundContext performBlock:^{
                [self _updateContainerWithUpdatedRecords:updatedRecords deletedRecordIDs:deletedRecordIDs];
            }];
        }];
    }];
}

- (void)_didSave:(NSNotification *)notification {
    if (_ignoreSaveNotification) return;
    
    NSSet<__kindof NSManagedObject *> * _Nullable insertedObjects = notification.userInfo[NSInsertedObjectsKey];
    NSSet<__kindof NSManagedObject *> * _Nullable updatedObjects = notification.userInfo[NSUpdatedObjectsKey];
    
    NSManagedObjectContext *context = self.backgroundContext;
    CKDatabase *database = self.cloudContainer.privateCloudDatabase;
    
    NSArray<CKRecord *> * _Nullable recordsToSave;
    if ((insertedObjects == nil) and (updatedObjects == nil)) {
        recordsToSave = nil;
    } else {
        NSMutableArray<CKRecord *> *records = [NSMutableArray new];
        NSArray<__kindof NSManagedObject *> *allObjects = [insertedObjects.allObjects arrayByAddingObjectsFromArray:updatedObjects.allObjects];
        allObjects = [allObjects filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
            return ![evaluatedObject isKindOfClass:[CloudRecordMap class]];
        }]];
        
        for (__kindof NSManagedObject *object in allObjects) {
            NSFetchRequest<CloudRecordMap *> *fetchRequest = [CloudRecordMap fetchRequest];
            NSString *keyPath;
            if ([object isKindOfClass:[Chatroom class]]) {
                keyPath = @"chatroom";
            } else if ([object isKindOfClass:[Message class]]) {
                keyPath = @"message";
            } else if ([object isKindOfClass:[User class]]) {
                keyPath = @"user";
            } else {
                abort();
            }
            fetchRequest.predicate = [NSPredicate predicateWithFormat:@"%K == %@" argumentArray:@[keyPath, object]];
            
            NSError * _Nullable error = nil;
            NSArray<CloudRecordMap *> *maps = [context executeFetchRequest:fetchRequest error:&error];
            assert(maps.count < 2);
            
            NSString *recordName;
            if (CloudRecordMap *map = maps.firstObject) {
                recordName = map.recordName;
            } else {
                recordName = [NSUUID UUID].UUIDString;
                
                CloudRecordMap *recordMap = [[CloudRecordMap alloc] initWithContext:context];
                recordMap.recordName = recordName;
                recordMap.scope = database.databaseScope;
                [recordMap setValue:object forKey:keyPath];
                [recordMap release];
            }
            
            CKRecordZoneID *zoneID = [[CKRecordZoneID alloc] initWithZoneName:@"MyMessenger" ownerName:CKCurrentUserDefaultName];
            CKRecordID *recordID = [[CKRecordID alloc] initWithRecordName:recordName zoneID:zoneID];
            [zoneID release];
            
            CKRecord *record;
            if ([object isKindOfClass:[Chatroom class]]) {
                auto chat = static_cast<Chatroom *>(object);
                
                record = [[CKRecord alloc] initWithRecordType:@"MM_Chat" recordID:recordID];
                [record setObject:chat.timestamp forKey:@"timestamp"];
            } else if ([object isKindOfClass:[Message class]]) {
                auto message = static_cast<Message *>(object);
                
                record = [[CKRecord alloc] initWithRecordType:@"MM_Message" recordID:recordID];
                [record setObject:message.text forKey:@"text"];
                [record setObject:message.timestamp forKey:@"timestamp"];
            } else if ([object isKindOfClass:[User class]]) {
                auto user = static_cast<User *>(object);
                
                record = [[CKRecord alloc] initWithRecordType:@"MM_User" recordID:recordID];
                [record setObject:user.name forKey:@"name"];
            } else {
                abort();
            }
            
            [recordID release];
            
            [records addObject:record];
            [record release];
        }
        
        assert(records.count == allObjects.count);
        
        [allObjects enumerateObjectsUsingBlock:^(__kindof NSManagedObject * _Nonnull object, NSUInteger idx, BOOL * _Nonnull stop) {
            CKRecord *record = records[idx];
            
            if ([object isKindOfClass:[Chatroom class]]) {
                auto chat = static_cast<Chatroom *>(object);
                
                NSMutableArray<CKReference *> *messageRefs = [NSMutableArray new];
                for (Message *message in chat.messages) {
                    NSInteger index = [allObjects indexOfObject:message];
                    if (index == NSNotFound) continue;
                    
                    CKRecord *messageRecord = [records objectAtIndex:index];
                    assert(messageRecord != nil);
                    
                    CKReference *reference = [[CKReference alloc] initWithRecord:messageRecord action:CKReferenceActionNone];
                    [messageRefs addObject:reference];
                    [reference release];
                }
                
                if (messageRefs.count > 0) {
                    [record setObject:messageRefs forKey:@"messages"];
                }
                
                [messageRefs release];
            } else if ([object isKindOfClass:[Message class]]) {
                auto message = static_cast<Message *>(object);
                
                {
                    Chatroom *chat = message.chatroom;
                    assert(chat != nil);
                    
                    NSInteger index = [allObjects indexOfObject:chat];
                    if (index != NSNotFound) {
                        CKRecord *chatRecord = [records objectAtIndex:index];
                        assert(chatRecord != nil);
                        
                        CKReference *reference = [[CKReference alloc] initWithRecord:chatRecord action:CKReferenceActionDeleteSelf];
                        [record setObject:reference forKey:@"chat"];
                        [reference release];
                    }
                }
                
                {
                    User *user = message.user;
                    assert(user != nil);
                    
                    NSInteger index = [allObjects indexOfObject:user];
                    if (index != NSNotFound) {
                        CKRecord *userRecord = [records objectAtIndex:index];
                        assert(userRecord != nil);
                        
                        CKReference *reference = [[CKReference alloc] initWithRecord:userRecord action:CKReferenceActionDeleteSelf];
                        [record setObject:reference forKey:@"user"];
                        [reference release];
                    }
                }
            } else if ([object isKindOfClass:[User class]]) {
                auto user = static_cast<User *>(object);
                
                NSMutableArray<CKReference *> *chatRefs = [NSMutableArray new];
                for (Chatroom *chat in user.chatrooms) {
                    NSInteger index = [allObjects indexOfObject:chat];
                    if (index == NSNotFound) continue;
                    
                    CKRecord *chatRecord = [records objectAtIndex:index];
                    assert(chatRecord != nil);
                    
                    CKReference *reference = [[CKReference alloc] initWithRecord:chatRecord action:CKReferenceActionNone];
                    [chatRefs addObject:reference];
                    [reference release];
                }
                if (chatRefs.count > 0) {
                    [record setObject:chatRefs forKey:@"chatrooms"];
                }
                [chatRefs release];
                
                NSMutableArray<CKReference *> *messageRefs = [NSMutableArray new];
                for (Message *message in user.messages) {
                    NSInteger index = [allObjects indexOfObject:message];
                    if (index == NSNotFound) continue;
                    CKRecord *messageRecord = [records objectAtIndex:index];
                    assert(message != nil);
                    
                    CKReference *reference = [[CKReference alloc] initWithRecord:messageRecord action:CKReferenceActionNone];
                    [messageRefs addObject:reference];
                    [reference release];
                }
                if (messageRefs.count > 0) {
                    [record setObject:messageRefs forKey:@"messages"];
                }
                [messageRefs release];
            } else {
                abort();
            }
        }];
        
        recordsToSave = records;
    }
    
    //
    
    CKModifyRecordsOperation *operation = [[CKModifyRecordsOperation alloc] initWithRecordsToSave:recordsToSave recordIDsToDelete:nil];
    [recordsToSave release];
    
    operation.savePolicy = CKRecordSaveChangedKeys;
    
    operation.perRecordProgressBlock = ^(CKRecord * _Nonnull record, double progress) {
        NSLog(@"perRecordProgressBlock (%@, %lf)", record, progress);
    };
    
    operation.perRecordDeleteBlock = ^(CKRecordID *recordID, NSError * _Nullable error) {
        NSLog(@"perRecordDeleteBlock (%@, %@)", recordID, error);
    };
    
    operation.perRecordSaveBlock = ^(CKRecordID *recordID, CKRecord * _Nullable record, NSError * _Nullable error) {
        NSLog(@"perRecordSaveBlock (%@, %@, %@)", recordID, record, error);
    };
    
    [database addOperation:operation];
    [operation release];
    
    
    if (context.hasChanges) {
        _ignoreSaveNotification = YES;
        NSError * _Nullable error = nil;
        [context save:&error];
        assert(error == nil);
        _ignoreSaveNotification = NO;
    }
}

- (void)_addCloudSubscriptionWithCompletionHandler:(void (^)(void))completionHandler {
    CKDatabase *privateCloudDatabase = self.cloudContainer.privateCloudDatabase;
    
    NSMutableArray<__kindof CKSubscription *> *subscriptions = [NSMutableArray new];
    
    CKDatabaseSubscription *subscription = [[CKDatabaseSubscription alloc] initWithSubscriptionID:@"Test"];
    
    CKNotificationInfo *notificationInfo = [CKNotificationInfo new];
    notificationInfo.shouldSendContentAvailable = YES;
    subscription.notificationInfo = notificationInfo;
    
    [subscriptions addObject:subscription];
    [subscription release];
    
    CKModifySubscriptionsOperation *operation = [[CKModifySubscriptionsOperation alloc] initWithSubscriptionsToSave:subscriptions subscriptionIDsToDelete:nil];
    [subscriptions release];
    
    operation.modifySubscriptionsCompletionBlock = ^(NSArray<CKSubscription *> * _Nullable savedSubscriptions, NSArray<CKSubscriptionID> * _Nullable deletedSubscriptionIDs, NSError * _Nullable operationError) {
        NSLog(@"modifySubscriptionsCompletionBlock (%@, %@, %@)", savedSubscriptions, deletedSubscriptionIDs, operationError);
        assert(operationError == nil);
        
        completionHandler();
    };
    
    operation.perSubscriptionSaveBlock = ^(CKSubscriptionID subscriptionID, CKSubscription * _Nullable subscription, NSError * _Nullable error) {
        NSLog(@"perSubscriptionSaveBlock (%@, %@, %@)", subscriptionID, subscription, error);
        assert(error == nil);
    };
    
    operation.perSubscriptionDeleteBlock = ^(CKSubscriptionID subscriptionID, NSError * _Nullable error) {
        NSLog(@"perSubscriptionDeleteBlock (%@, %@)", subscriptionID, error);
        assert(error == nil);
    };
    
    [privateCloudDatabase addOperation:operation];
    [operation release];
}

- (void)_zoneWithCompletionHandler:(void (^)(CKRecordZone *recordZone))completionHandler {
    CKDatabase *privateCloudDatabase = self.cloudContainer.privateCloudDatabase;
    
    CKRecordZoneID *zoneID = [[CKRecordZoneID alloc] initWithZoneName:@"MyMessenger" ownerName:CKCurrentUserDefaultName];
    CKFetchRecordZonesOperation *fetchRecordZonesOperation = [[CKFetchRecordZonesOperation alloc] initWithRecordZoneIDs:@[zoneID]];
    [zoneID release];
    
    fetchRecordZonesOperation.perRecordZoneCompletionBlock = ^(CKRecordZoneID *zoneID, CKRecordZone * _Nullable recordZone, NSError * _Nullable error) {
        if ([error.domain isEqualToString:CKErrorDomain] and (error.code == CKErrorZoneNotFound)) {
            CKRecordZone *recordZone = [[CKRecordZone alloc] initWithZoneID:zoneID];
            
            CKModifyRecordZonesOperation *modifyRecordZonesOperation = [[CKModifyRecordZonesOperation alloc] initWithRecordZonesToSave:@[recordZone] recordZoneIDsToDelete:nil];
            [recordZone release];
            
            modifyRecordZonesOperation.perRecordZoneSaveBlock = ^(CKRecordZoneID *recordZoneID, CKRecordZone * _Nullable recordZone, NSError * _Nullable error) {
                NSLog(@"perRecordZoneSaveBlock (%@, %@, %@)", recordZoneID, recordZone, error);
                assert(error == nil);
                completionHandler(recordZone);
            };
            
            modifyRecordZonesOperation.perRecordZoneDeleteBlock = ^(CKRecordZoneID *recordZoneID, NSError * _Nullable error) {
                NSLog(@"perRecordZoneDeleteBlock (%@, %@)", recordZoneID, error);
                assert(error == nil);
            };
            
            [privateCloudDatabase addOperation:modifyRecordZonesOperation];
            [modifyRecordZonesOperation release];
            
            return;
        } else if (error != nil) {
            abort();
        }
        
        assert(recordZone != nil);
        completionHandler(recordZone);
    };
    
    [privateCloudDatabase addOperation:fetchRecordZonesOperation];
    [fetchRecordZonesOperation release];
}

- (void)_recordsWithZone:(CKRecordZone *)zone completionHandler:(void (^)(NSSet<CKRecord *> *updatedRecords, NSDictionary<CKRecordID *, CKRecordType> *deletedRecordIDs))completionHandler {
    CKDatabase *privateCloudDatabase = self.cloudContainer.privateCloudDatabase;
    
    CKFetchRecordZoneChangesConfiguration *configuration = [CKFetchRecordZoneChangesConfiguration new];
    configuration.previousServerChangeToken = DataStack.serverChangeToken;
    
    CKFetchRecordZoneChangesOperation *fetchRecordZoneChangesOperation = [[CKFetchRecordZoneChangesOperation alloc] initWithRecordZoneIDs:@[zone.zoneID] configurationsByRecordZoneID:@{zone.zoneID: configuration}];
    [configuration release];
    
    NSMutableSet<CKRecord *> *updatedRecords = [NSMutableSet new];
    NSMutableDictionary<CKRecordID *, CKRecordType> *deletedRecordIDs = [NSMutableDictionary new];
    
    fetchRecordZoneChangesOperation.recordWasChangedBlock = ^(CKRecordID *recordID, CKRecord * _Nullable record, NSError * _Nullable error) {
        assert(error == nil);
        assert(record != nil);
        [updatedRecords addObject:record];
    };
    
    fetchRecordZoneChangesOperation.recordWithIDWasDeletedBlock = ^(CKRecordID * _Nonnull recordID, CKRecordType  _Nonnull recordType) {
        deletedRecordIDs[recordID] = recordType;
    };
    
    fetchRecordZoneChangesOperation.recordZoneChangeTokensUpdatedBlock = ^(CKRecordZoneID * _Nonnull recordZoneID, CKServerChangeToken * _Nullable serverChangeToken, NSData * _Nullable clientChangeTokenData) {
        if (serverChangeToken != nil) {
            DataStack.serverChangeToken = serverChangeToken;
        }
    };
    
    fetchRecordZoneChangesOperation.recordZoneFetchCompletionBlock = ^(CKRecordZoneID * _Nonnull recordZoneID, CKServerChangeToken * _Nullable serverChangeToken, NSData * _Nullable clientChangeTokenData, BOOL moreComing, NSError * _Nullable recordZoneError) {
        assert(recordZoneError == nil);
        assert(!moreComing);
        
        if (serverChangeToken != nil) {
            DataStack.serverChangeToken = serverChangeToken;
        }
    };
    
    fetchRecordZoneChangesOperation.fetchRecordZoneChangesCompletionBlock = ^(NSError * _Nullable operationError) {
        assert(operationError == nil);
        completionHandler(updatedRecords, deletedRecordIDs);
    };
    
    [updatedRecords release];
    [deletedRecordIDs release];
    
    [privateCloudDatabase addOperation:fetchRecordZoneChangesOperation];
    [fetchRecordZoneChangesOperation release];
}

- (void)_updateContainerWithUpdatedRecords:(NSSet<CKRecord *> *)updatedRecords deletedRecordIDs:(NSDictionary<CKRecordID *, CKRecordType> *)deletedRecordIDs {
    NSManagedObjectContext *context = self.backgroundContext;
    
    NSMutableArray<CKRecord *> *updatedRecordsArray = [[NSMutableArray alloc] initWithCapacity:updatedRecords.count];
    NSMutableArray<__kindof NSManagedObject *> *updatedObjectsArray = [[NSMutableArray alloc] initWithCapacity:updatedRecords.count];
    
    for (CKRecord *updatedRecord in updatedRecords) {
        [updatedRecordsArray addObject:updatedRecord];
        
        if (CloudRecordMap *map = [self _mapFromRecordName:updatedRecord.recordID.recordName]) {
            if ([updatedRecord.recordType isEqualToString:@"MM_User"]) {
                User *user = map.user;
                assert(user != nil);
                
                user.name = [updatedRecord objectForKey:@"name"];
                [updatedObjectsArray addObject:user];
            } else if ([updatedRecord.recordType isEqualToString:@"MM_Chat"]) {
                Chatroom *chat = map.chatroom;
                assert(chat != nil);
                
                chat.timestamp = [updatedRecord objectForKey:@"timestamp"];
                [updatedObjectsArray addObject:chat];
            } else if ([updatedRecord.recordType isEqualToString:@"MM_Message"]) {
                Message *message = map.message;
                assert(message != nil);
                
                message.text = [updatedRecord objectForKey:@"text"];
                message.timestamp = [updatedRecord objectForKey:@"timestamp"];
                [updatedObjectsArray addObject:message];
            } else {
                abort();
            }
        } else {
            CloudRecordMap *newMap = [[CloudRecordMap alloc] initWithContext:context];
            
            if ([updatedRecord.recordType isEqualToString:@"MM_User"]) {
                User *user = [[User alloc] initWithContext:context];
                user.name = [updatedRecord objectForKey:@"name"];
                
                newMap.user = user;
                
                [updatedObjectsArray addObject:user];
                [user release];
            } else if ([updatedRecord.recordType isEqualToString:@"MM_Chat"]) {
                Chatroom *chat = [[Chatroom alloc] initWithContext:context];
                chat.timestamp = [updatedRecord objectForKey:@"timestamp"];
                
                newMap.chatroom = chat;
                
                [updatedObjectsArray addObject:chat];
                [chat release];
            } else if ([updatedRecord.recordType isEqualToString:@"MM_Message"]) {
                Message *message = [[Message alloc] initWithContext:context];
                message.text = [updatedRecord objectForKey:@"text"];
                message.timestamp = [updatedRecord objectForKey:@"timestamp"];
                
                newMap.message = message;
                
                [updatedObjectsArray addObject:message];
                [message release];
            } else {
                abort();
            }
            
            newMap.recordName = updatedRecord.recordID.recordName;
            newMap.scope = CKDatabaseScopePrivate;
            
            [newMap release];
        }
    }
    
    assert(updatedRecordsArray.count == updatedRecords.count);
    assert(updatedObjectsArray.count == updatedRecords.count);
    
    //
    
    [updatedRecordsArray enumerateObjectsUsingBlock:^(CKRecord * _Nonnull record, NSUInteger idx, BOOL * _Nonnull stop) {
        __kindof NSManagedObject *object = updatedObjectsArray[idx];
        
        if ([record.recordType isEqualToString:@"MM_User"]) {
            auto user = static_cast<User *>(object);
            
            if (NSArray<CKReference *> *chatRefs = [record objectForKey:@"chatrooms"]) {
                for (CKReference *chatRef in chatRefs) {
                    CloudRecordMap *map = [self _mapFromRecordName:chatRef.recordID.recordName];
                    assert(map != nil);
                    Chatroom *chat = map.chatroom;
                    assert(chat != nil);
                    
                    [user addChatroomsObject:chat];
                }
            }
            
            if (NSArray<CKReference *> *messageRefs = [record objectForKey:@"messages"]) {
                for (CKReference *messageRef in messageRefs) {
                    CloudRecordMap *map = [self _mapFromRecordName:messageRef.recordID.recordName];
                    assert(map != nil);
                    Message *message = map.message;
                    assert(message != nil);
                    
                    [user addMessagesObject:message];
                }
            }
        } else if ([record.recordType isEqualToString:@"MM_Chat"]) {
            auto chat = static_cast<Chatroom *>(object);
            
            if (NSArray<CKReference *> *messageRefs = [record objectForKey:@"messages"]) {
                for (CKReference *messageRef in messageRefs) {
                    CloudRecordMap *map = [self _mapFromRecordName:messageRef.recordID.recordName];
                    assert(map != nil);
                    Message *message = map.message;
                    assert(message != nil);
                    
                    [chat addMessagesObject:message];
                }
            }
            
            if (NSArray<CKReference *> *userRefs = [record objectForKey:@"users"]) {
                for (CKReference *userRef in userRefs) {
                    CloudRecordMap *map = [self _mapFromRecordName:userRef.recordID.recordName];
                    assert(map != nil);
                    User *user = map.user;
                    assert(user != nil);
                    
                    [chat addUsersObject:user];
                }
            }
        } else if ([record.recordType isEqualToString:@"MM_Message"]) {
            auto message = static_cast<Message *>(object);
            
            if (NSArray<CKReference *> *chatRefs = [record objectForKey:@"chatroom"]) {
                for (CKReference *chatRef in chatRefs) {
                    CloudRecordMap *map = [self _mapFromRecordName:chatRef.recordID.recordName];
                    assert(map != nil);
                    Chatroom *chat = map.chatroom;
                    assert(chat != nil);
                    
                    message.chatroom = chat;
                }
            }
            
            if (NSArray<CKReference *> *userRefs = [record objectForKey:@"users"]) {
                for (CKReference *userRef in userRefs) {
                    CloudRecordMap *map = [self _mapFromRecordName:userRef.recordID.recordName];
                    assert(map != nil);
                    User *user = map.user;
                    assert(user != nil);
                    
                    message.user = user;
                }
            }
        } else {
            abort();
        }
    }];
    
    //
    
    [updatedRecordsArray release];
    [updatedObjectsArray release];
    
    _ignoreSaveNotification = YES;
    NSError * _Nullable error = nil;
    [context save:&error];
    assert(error == nil);
    _ignoreSaveNotification = NO;
}

- (CloudRecordMap * _Nullable)_mapFromRecordName:(NSString *)recordName {
    NSFetchRequest<CloudRecordMap *> *fetchRequest = [CloudRecordMap fetchRequest];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"%K == %@" argumentArray:@[@"recordName", recordName]];
    fetchRequest.fetchLimit = 1;
    NSError * _Nullable error = nil;
    NSArray<CloudRecordMap *> *results = [self.backgroundContext executeFetchRequest:fetchRequest error:&error];
    assert(error == nil);
    return results.firstObject;
}

+ (CKServerChangeToken *)_serverChangeToken {
    NSData * _Nullable data = [NSUserDefaults.standardUserDefaults objectForKey:@"serverChangeToken"];
    if (data == nil) return nil;
    
    NSError * _Nullable error = nil;
    CKServerChangeToken *serverChangeToken = [NSKeyedUnarchiver unarchivedObjectOfClass:[CKServerChangeToken class] fromData:data error:&error];
    assert(error == nil);
    
    return serverChangeToken;
}

+ (void)_setServerChangeToken:(CKServerChangeToken *)serverChangeToken {
    NSError * _Nullable error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:serverChangeToken requiringSecureCoding:YES error:&error];
    assert(error == nil);
    
    [NSUserDefaults.standardUserDefaults setObject:data forKey:@"serverChangeToken"];
}

@end
