//
//  MessagesViewController.mm
//  MyMessenger
//
//  Created by Jinwoo Kim on 3/29/25.
//

#import "MessagesViewController.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import "Message+CoreDataProperties.h"
#import "ComposeView.h"
#import "DataStack.h"

@interface MessagesViewController () <NSFetchedResultsControllerDelegate>
@property (retain, nonatomic, readonly, getter=_user) User *user;
@property (retain, nonatomic, nullable, getter=_isolated_chat, setter=_isolated_setChat:) Chatroom *isolated_chat;

@property (retain, nonatomic, nullable, getter=_fetchedResultsController, setter=_setFetchedResultsController:) NSFetchedResultsController<Message *> *fetchedResultsController;

@property (retain, nonatomic, readonly, getter=_cellRegistration) UICollectionViewCellRegistration *cellRegistration;
@property (retain, nonatomic, readonly, getter=_composeView) ComposeView *composeView;
@property (retain, nonatomic, readonly, getter=_participantsBarButtonItem) UIBarButtonItem *participantsBarButtonItem;
@end

@implementation MessagesViewController
@synthesize cellRegistration = _cellRegistration;
@synthesize composeView = _composeView;
@synthesize participantsBarButtonItem = _participantsBarButtonItem;
@synthesize isolated_chat = _chat;

- (instancetype)initWithCurrentUser:(User *)user chat:(Chatroom *)chat {
    UICollectionLayoutListConfiguration *listConfiguration = [[UICollectionLayoutListConfiguration alloc] initWithAppearance:UICollectionLayoutListAppearanceInsetGrouped];
    UICollectionViewCompositionalLayout *collectionViewLayout = [UICollectionViewCompositionalLayout layoutWithListConfiguration:listConfiguration];
    [listConfiguration release];
    
    if (self = [super initWithCollectionViewLayout:collectionViewLayout]) {
        _user = [user retain];
        _chat = [chat retain];
    }
    
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_user release];
    [_chat release];
    [_fetchedResultsController release];
    [_cellRegistration release];
    [_composeView release];
    [_participantsBarButtonItem release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self _cellRegistration];
    
    ComposeView *composeView = self.composeView;
    composeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.view.keyboardLayoutGuide.usesBottomSafeArea = NO;
    [self.view addSubview:composeView];
    [NSLayoutConstraint activateConstraints:@[
        [composeView.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
        [composeView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [composeView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [composeView.heightAnchor constraintEqualToConstant:100.]
    ]];
    
    UINavigationItem *navigationItem = self.navigationItem;
    navigationItem.rightBarButtonItem = self.participantsBarButtonItem;
    
    [DataStack.sharedInstance.backgroundContext performBlock:^{
        self.isolated_chat = self.isolated_chat;
    }];
    
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_objectsDidChange:) name:NSManagedObjectContextObjectsDidChangeNotification object:DataStack.sharedInstance.backgroundContext];
}

- (void)_objectsDidChange:(NSNotification *)notification {
    Chatroom * _Nullable chat = self.isolated_chat;
    if (chat == nil) return;
    
    NSSet<__kindof NSManagedObject *> *updatedObjects = notification.userInfo[NSUpdatedObjectsKey];
    if ([updatedObjects containsObject:chat]) {
        if (![chat.users containsObject:self.user]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.navigationController popViewControllerAnimated:YES];
            });
            return;
        }
    }
    
    NSSet<__kindof NSManagedObject *> *deletecObjects = notification.userInfo[NSDeletedObjectsKey];
    if ([deletecObjects containsObject:chat]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.navigationController popViewControllerAnimated:YES];
        });
        return;
    }
}

- (NSFetchedResultsController<Message *> *)_fetchedResultsControllerIfExists {
    return _fetchedResultsController;
}

- (UICollectionViewCellRegistration *)_cellRegistration {
    if (auto cellRegistration = _cellRegistration) return cellRegistration;
    
    UICollectionViewCellRegistration *cellRegistration = [UICollectionViewCellRegistration registrationWithCellClass:[UICollectionViewListCell class] configurationHandler:^(UICollectionViewListCell * _Nonnull cell, NSIndexPath * _Nonnull indexPath, Message * _Nonnull item) {
        cell.contentConfiguration = nil;
        
        static void *key = &key;
        objc_setAssociatedObject(cell, key, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        [item.managedObjectContext performBlock:^{
            NSAttributedString * _Nullable attributedString = item.attributedString;
            NSString * _Nullable sender = item.user.name;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([item isEqual:objc_getAssociatedObject(cell, key)]) {
                    UIListContentConfiguration *contentConfiguration = [cell defaultContentConfiguration];
    //                contentConfiguration.attributedText = attributedString;
                    contentConfiguration.text = attributedString.string;
                    contentConfiguration.secondaryText = sender;
                    cell.contentConfiguration = contentConfiguration;
                }
            });
        }];
    }];
    
    _cellRegistration = [cellRegistration retain];
    return cellRegistration;
}

- (ComposeView *)_composeView {
    if (auto composeView = _composeView) return composeView;
    
    ComposeView *composeView = [ComposeView new];
    [composeView.sendButton addTarget:self action:@selector(_didTriggerSendButton:) forControlEvents:UIControlEventPrimaryActionTriggered];
    
    _composeView = composeView;
    return composeView;
}

- (UIBarButtonItem *)_participantsBarButtonItem {
    if (auto participantsBarButtonItem = _participantsBarButtonItem) return participantsBarButtonItem;
    
    __block auto unretained = self;
    
    UIDeferredMenuElement *element = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^ _Nonnull completion)(NSArray<UIMenuElement *> * _Nonnull)) {
        NSManagedObjectContext *context = DataStack.sharedInstance.backgroundContext;
        
        [context performBlock:^{
            Chatroom * _Nullable chat = unretained.isolated_chat;
            if (chat == nil) {
                completion(@[]);
                return;
            }
            
            NSSet<User *> *users = chat.users;
            
            NSMutableArray<UIMenu *> *usersMenuChildren = [[NSMutableArray alloc] initWithCapacity:users.count];
            
            for (User *user in users) {
                NSString * _Nullable name = user.name;
                
                UIAction *removeAction = [UIAction actionWithTitle:@"Remove" image:[UIImage systemImageNamed:@"door.right.hand.open"] identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
                    [context performBlock:^{
                        [chat removeUsersObject:user];
                        
                        NSError * _Nullable error = nil;
                        [context save:&error];
                        assert(error == nil);
                    }];
                }];
                removeAction.attributes = UIMenuElementAttributesDestructive;
                
                UIMenu *menu = [UIMenu menuWithTitle:(name == nil) ? @"(nil)" : name
                                               image:nil
                                          identifier:nil
                                             options:0
                                            children:@[removeAction]];
                
                [usersMenuChildren addObject:menu];
            }
            
            UIMenu *usersMenu = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:usersMenuChildren];
            [usersMenuChildren release];
            
            //
            
            NSFetchRequest<User *> *fetchRequest = [User fetchRequest];
            fetchRequest.predicate = [NSPredicate predicateWithFormat:@"SUBQUERY(chatrooms, $a, $a CONTAINS %@).@count == 0" argumentArray:@[chat]];
            
            NSError * _Nullable error = nil;
            NSArray<User *> *notInChatUsers = [context executeFetchRequest:fetchRequest error:&error];
            assert(error == nil);
            
            NSMutableArray<UIAction *> *inviteActions = [[NSMutableArray alloc] initWithCapacity:notInChatUsers.count];
            for (User *user in notInChatUsers) {
                NSString * _Nullable name = user.name;
                
                UIAction *inviteAction = [UIAction actionWithTitle:(name == nil) ? @"(nil)" : name
                                                             image:nil
                                                        identifier:nil
                                                           handler:^(__kindof UIAction * _Nonnull action) {
                    [context performBlock:^{
                        [chat addUsersObject:user];
                        
                        NSError * _Nullable error = nil;
                        [context save:&error];
                        assert(error == nil);
                    }];
                }];
                
                [inviteActions addObject:inviteAction];
            }
            
            UIMenu *inviteMenu = [UIMenu menuWithTitle:@"Invite User" children:inviteActions];
            [inviteActions release];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@[usersMenu, inviteMenu]);
            });
        }];
    }];
    
    UIMenu *menu = [UIMenu menuWithChildren:@[element]];
    
    UIBarButtonItem *participantsBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Participants" image:[UIImage systemImageNamed:@"person.3.fill"] target:nil action:nil menu:menu];
    
    _participantsBarButtonItem = participantsBarButtonItem;
    return participantsBarButtonItem;
}

- (void)_didTriggerSendButton:(UIButton *)sender {
    NSAttributedString *attributedText = self.composeView.textView.attributedText;
    if (attributedText == nil) return;
    if (attributedText.length == 0) return;
    
    self.composeView.textView.text = nil;
    
    NSManagedObjectContext *context = DataStack.sharedInstance.backgroundContext;
    
    [context performBlock:^{
        Chatroom * _Nullable chat = self.isolated_chat;
        User *user = self.user;
        
        NSDate *timestamp = [NSDate now];
        NSError * _Nullable error = nil;
        
        Chatroom *_chat;
        if (chat == nil) {
            _chat = [[Chatroom alloc] initWithContext:context];
            [_chat addUsersObject:user];
            [_chat autorelease];
        } else {
            _chat = chat;
        }
        
        Message *message = [[Message alloc] initWithContext:context];
        message.attributedString = attributedText;
        message.timestamp = timestamp;
        message.user = user;
        [chat addMessagesObject:message];
        [message release];
        
        [context save:&error];
        assert(error == nil);
        
        self.isolated_chat = _chat;
    }];
}

- (void)_isolated_setChat:(Chatroom *)chat {
    [_chat release];
    _chat = [chat retain];
    
    if (chat == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.fetchedResultsController = nil;
            [self.collectionView reloadData];
        });
    } else {
        NSFetchRequest<Message *> *fetchRequest = [Message fetchRequest];
        fetchRequest.predicate = [NSPredicate predicateWithFormat:@"%K == %@" argumentArray:@[@"chatroom", chat]];
        fetchRequest.sortDescriptors = @[
            [NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:YES]
        ];
        
        NSFetchedResultsController<Message *> *fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                                                                                              managedObjectContext:DataStack.sharedInstance.backgroundContext
                                                                                                                sectionNameKeyPath:nil
                                                                                                                         cacheName:nil];
        
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
