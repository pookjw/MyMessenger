//
//  MessagesViewController.h
//  MyMessenger
//
//  Created by Jinwoo Kim on 3/29/25.
//

#import <UIKit/UIKit.h>
#import "Chatroom+CoreDataProperties.h"
#import "User+CoreDataProperties.h"

NS_ASSUME_NONNULL_BEGIN

@interface MessagesViewController : UICollectionViewController
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCollectionViewLayout:(UICollectionViewLayout *)layout NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (instancetype)initWithCurrentUser:(User *)user chat:(Chatroom * _Nullable)chat;
@end

NS_ASSUME_NONNULL_END
