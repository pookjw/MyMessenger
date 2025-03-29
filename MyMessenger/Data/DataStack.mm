//
//  DataStack.mm
//  MyMessenger
//
//  Created by Jinwoo Kim on 3/28/25.
//

#import "DataStack.h"

NSNotificationName const DataStackDidInitializeNotification = @"DataStackDidInitializeNotification";

@interface DataStack ()
@end

@implementation DataStack

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
        }];
        
        _backgroundContext = backgroundContext;
    }
    
    return self;
}

- (void)dealloc {
    [_backgroundContext release];
    [super dealloc];
}

- (BOOL)isInitialized {
    return self.backgroundContext.persistentStoreCoordinator != nil;
}

@end
