//
//  ChatsViewController.mm
//  MyMessenger
//
//  Created by Jinwoo Kim on 3/28/25.
//

#import "ChatsViewController.h"
#import "DataStack.h"
#import "Chatroom+CoreDataProperties.h"
#import "User+CoreDataProperties.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import "MessagesViewController.h"

@interface ChatsViewController () <NSFetchedResultsControllerDelegate>
@property (retain, nonatomic, nullable, getter=_fetchedResultsController, setter=_setFetchedResultsController:) NSFetchedResultsController<Chatroom *> *fetchedResultsController;
@property (retain, nonatomic, readonly, getter=_cellRegistration) UICollectionViewCellRegistration *cellRegistration;
@property (retain, nonatomic, readonly, getter=_userBarButtonItem) UIBarButtonItem *userBarButtonItem;
@property (retain, nonatomic, readonly, getter=_composeBarButtonItem) UIBarButtonItem *composeBarButtonItem;
@property (retain, nonatomic, nullable, getter=_isolated_currentUser, setter=_isolated_setCurrentUser:) User *isolated_currentUser;
@end

@implementation ChatsViewController
@synthesize fetchedResultsController = _fetchedResultsController;
@synthesize cellRegistration = _cellRegistration;
@synthesize userBarButtonItem = _userBarButtonItem;
@synthesize composeBarButtonItem = _composeBarButtonItem;
@synthesize isolated_currentUser = _currentUser;

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    UICollectionLayoutListConfiguration *listConfiguration = [[UICollectionLayoutListConfiguration alloc] initWithAppearance:UICollectionLayoutListAppearanceInsetGrouped];
    UICollectionViewCompositionalLayout *collectionViewLayout = [UICollectionViewCompositionalLayout layoutWithListConfiguration:listConfiguration];
    [listConfiguration release];
    
    if (self = [super initWithCollectionViewLayout:collectionViewLayout]) {
        
    }
    
    return self;
}

- (void)dealloc {
    [_fetchedResultsController release];
    [_cellRegistration release];
    [_userBarButtonItem release];
    [_composeBarButtonItem release];
    [_currentUser release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self _cellRegistration];
    
    UINavigationItem *navigationItem = self.navigationItem;
    navigationItem.title = @"Chats";
    navigationItem.leftBarButtonItem = self.userBarButtonItem;
    navigationItem.rightBarButtonItem = self.composeBarButtonItem;
    
    [DataStack.sharedInstance.backgroundContext performBlock:^{
        if (DataStack.sharedInstance.isInitialized) {
            NSError * _Nullable error = nil;
            [self.fetchedResultsController performFetch:&error];
            assert(error == nil);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self.userBarButtonItem.enabled = YES;
                [self.collectionView reloadData];
            });
            
            [self _isolated_selectAnyUser];
        } else {
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_didInitializeDataStack:) name:DataStackDidInitializeNotification object:DataStack.sharedInstance];
        }
    }];
}

- (void)_didInitializeDataStack:(NSNotification *)notification {
    [self _isolated_selectAnyUser];
    
    NSError * _Nullable error = nil;
    [self.fetchedResultsController performFetch:&error];
    assert(error == nil);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.userBarButtonItem.enabled = YES;
        [self.collectionView reloadData];
    });
    
    [self _isolated_selectAnyUser];
}

- (UICollectionViewCellRegistration *)_cellRegistration {
    if (auto cellRegistration = _cellRegistration) return cellRegistration;
    
    UICollectionViewCellRegistration *cellRegistration = [UICollectionViewCellRegistration registrationWithCellClass:[UICollectionViewListCell class] configurationHandler:^(UICollectionViewListCell * _Nonnull cell, NSIndexPath * _Nonnull indexPath, Chatroom * _Nonnull item) {
        UIListContentConfiguration *contentConfiguration = [cell defaultContentConfiguration];
        contentConfiguration.text = indexPath.description;
        cell.contentConfiguration = contentConfiguration;
    }];
    
    _cellRegistration = [cellRegistration retain];
    return cellRegistration;
}

- (UIBarButtonItem *)_userBarButtonItem {
    if (auto userBarButtonItem = _userBarButtonItem) return userBarButtonItem;
    
    __block auto unretained = self;
    
    UIDeferredMenuElement *element = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^ _Nonnull completion)(NSArray<UIMenuElement *> * _Nonnull)) {
        NSManagedObjectContext *backgroundContext = DataStack.sharedInstance.backgroundContext;
        
        [backgroundContext performBlock:^{
            NSFetchRequest<User *> *fetchRequest = [User fetchRequest];
            
            NSError * _Nullable error = nil;
            NSArray<User *> *users = [backgroundContext executeFetchRequest:fetchRequest error:&error];
            assert(error == nil);
            
            User * _Nullable currentUser = unretained.isolated_currentUser;
            
            NSMutableArray<UIMenu *> *usersMenuChildren = [[NSMutableArray alloc] initWithCapacity:users.count];
            for (User *user in users) {
                NSMutableArray<UIAction *> *actions = [[NSMutableArray alloc] initWithCapacity:2];
                
                if (![currentUser isEqual:user]) {
                    UIAction *selectUserAction = [UIAction actionWithTitle:@"Select" image:[UIImage systemImageNamed:@"person.fill.checkmark"] identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
                        [backgroundContext performBlock:^{
                            unretained.isolated_currentUser = user;
                        }];
                    }];
                    [actions addObject:selectUserAction];
                }
                
                NSString * _Nullable name = user.name;
                
                UIAction *editNameAction = [UIAction actionWithTitle:@"Edit name" image:[UIImage systemImageNamed:@"pencil"] identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
                    [unretained _presentEditNameAlertControllerWithUser:user oldName:name];
                }];
                [actions addObject:editNameAction];
                
                UIAction *deleteUserAction = [UIAction actionWithTitle:@"Delete" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
                    [backgroundContext performBlock:^{
                        [backgroundContext deleteObject:user];
                        
                        NSError * _Nullable error = nil;
                        [backgroundContext save:&error];
                        assert(error == nil);
                        
                        if ([currentUser isEqual:user]) {
                            [self _isolated_selectAnyUser];
                        }
                    }];
                }];
                deleteUserAction.attributes = UIMenuOptionsDestructive;
                [actions addObject:deleteUserAction];
                
                UIMenu *menu = [UIMenu menuWithTitle:(name == nil) ? @"(nil)" : name
                                               image:[currentUser isEqual:user] ? [UIImage systemImageNamed:@"checkmark"] : nil
                                          identifier:nil
                                             options:0
                                            children:actions];
                [actions release];
                
                [usersMenuChildren addObject:menu];
            }
            
            UIMenu *usersMenu = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:usersMenuChildren];
            [usersMenuChildren release];
            
            UIAction *addUserAction = [UIAction actionWithTitle:@"Add User" image:[UIImage systemImageNamed:@"plus"] identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
                [unretained _presentAddUserAlertController];
            }];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@[usersMenu, addUserAction]);
            });
        }];
    }];
    
    UIBarButtonItem *userBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"User" image:[UIImage systemImageNamed:@"person.circle"] target:nil action:nil menu:[UIMenu menuWithChildren:@[element]]];
    userBarButtonItem.enabled = NO;
    
    _userBarButtonItem = userBarButtonItem;
    return userBarButtonItem;
}

- (UIBarButtonItem *)_composeBarButtonItem {
    if (auto composeBarButtonItem = _composeBarButtonItem) return composeBarButtonItem;
    
    UIBarButtonItem *composeBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Compose" image:[UIImage systemImageNamed:@"bubble.and.pencil"] target:self action:@selector(_didTriggerComposeBarButtonItem:) menu:nil];
    
    _composeBarButtonItem = composeBarButtonItem;
    return composeBarButtonItem;
}

- (void)_didTriggerComposeBarButtonItem:(UIBarButtonItem *)sender {
    sender.enabled = NO;
    
    NSManagedObjectContext *context = DataStack.sharedInstance.backgroundContext;
    [context performBlock:^{
        User *user = self.isolated_currentUser;
        assert(user != nil);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            MessagesViewController *messagesViewController = [[MessagesViewController alloc] initWithCurrentUser:user chat:nil];
            [self.navigationController pushViewController:messagesViewController animated:YES];
            [messagesViewController release];
            sender.enabled = YES;
        });
    }];
}

- (void)_presentAddUserAlertController {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"New User" message:nil preferredStyle:UIAlertControllerStyleAlert];
    
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {}];
    [alertController addAction:cancelAction];
    
    UIAlertAction *doneAction = [UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UIAlertController *alertController = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(action, sel_registerName("_alertController"));
        UITextField *textField = alertController.textFields.firstObject;
        NSString *name = textField.text;
        
        NSManagedObjectContext *context = DataStack.sharedInstance.backgroundContext;
        [context performBlock:^{
            User *user = [[User alloc] initWithContext:context];
            user.name = name;
            
            NSError * _Nullable error = nil;
            [context save:&error];
            assert(error == nil);
            
            self.isolated_currentUser = user;
            [user release];
        }];
    }];
    [alertController addAction:doneAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)_presentEditNameAlertControllerWithUser:(User *)user oldName:(NSString * _Nullable)name {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Edit name" message:nil preferredStyle:UIAlertControllerStyleAlert];
    
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.text = name;
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {}];
    [alertController addAction:cancelAction];
    
    UIAlertAction *doneAction = [UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UIAlertController *alertController = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(action, sel_registerName("_alertController"));
        UITextField *textField = alertController.textFields.firstObject;
        NSString *name = textField.text;
        
        NSManagedObjectContext *context = DataStack.sharedInstance.backgroundContext;
        [context performBlock:^{
            user.name = name;
            
            NSError * _Nullable error = nil;
            [context save:&error];
            assert(error == nil);
        }];
    }];
    [alertController addAction:doneAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)_isolated_selectAnyUser {
    NSFetchRequest<User *> *fetchRequest = [User fetchRequest];
    NSError * _Nullable error = nil;
    NSArray<User *> *users = [DataStack.sharedInstance.backgroundContext executeFetchRequest:fetchRequest error:&error];
    assert(error == nil);
    
    User * _Nullable user = users.firstObject;
    self.isolated_currentUser = user;
}

- (void)_isolated_setCurrentUser:(User *)currentUser {
    [_currentUser release];
    _currentUser = [currentUser retain];
    
    if (currentUser == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.fetchedResultsController = nil;
            [self.collectionView reloadData];
        });
    } else {
        NSFetchRequest<Chatroom *> *fetchRequest = [Chatroom fetchRequest];
        fetchRequest.predicate = [NSPredicate predicateWithFormat:@"%K CONTAINS %@" argumentArray:@[@"users", currentUser]];
        fetchRequest.sortDescriptors = @[
            [NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:NO]
        ];
        
        NSFetchedResultsController<Chatroom *> *fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:DataStack.sharedInstance.backgroundContext sectionNameKeyPath:nil cacheName:nil];
        
        fetchedResultsController.delegate = self;
        
        NSError * _Nullable error = nil;
        [fetchedResultsController performFetch:&error];
        assert(error == nil);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.fetchedResultsController = fetchedResultsController;
            [self.collectionView reloadData];
        });
        
        [fetchedResultsController release];
    }
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.fetchedResultsController.fetchedObjects.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    return [collectionView dequeueConfiguredReusableCellWithRegistration:self.cellRegistration forIndexPath:indexPath item:[self.fetchedResultsController objectAtIndexPath:indexPath]];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    Chatroom * _Nullable chat = [self.fetchedResultsController objectAtIndexPath:indexPath];
    if (chat == nil) return;
    
    NSManagedObjectContext *context = DataStack.sharedInstance.backgroundContext;
    
    [context performBlock:^{
        User *user = self.isolated_currentUser;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            MessagesViewController *viewController = [[MessagesViewController alloc] initWithCurrentUser:user chat:chat];
            [self.navigationController pushViewController:viewController animated:YES];
            [viewController release];
        });
    }];
}

- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type newIndexPath:(NSIndexPath *)newIndexPath {
    dispatch_async(dispatch_get_main_queue(), ^{
        UICollectionView *collectionView = self.collectionView;
        
        [collectionView performBatchUpdates:^{
            switch (type) {
                case NSFetchedResultsChangeInsert: {
                    [collectionView insertItemsAtIndexPaths:@[newIndexPath]];
                    break;
                }
                case NSFetchedResultsChangeDelete: {
                    [collectionView deleteItemsAtIndexPaths:@[indexPath]];
                    break;
                }
                case NSFetchedResultsChangeMove:{
                    [collectionView moveItemAtIndexPath:indexPath toIndexPath:newIndexPath];
                    break;
                }
                case NSFetchedResultsChangeUpdate:
                    [collectionView reconfigureItemsAtIndexPaths:@[indexPath]];
                    break;
                default:
                    abort();
            }
        }
                                      completion:^(BOOL finished) {
            
        }];
    });
}

@end
