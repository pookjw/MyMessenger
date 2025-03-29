//
//  ComposeView.h
//  MyMessenger
//
//  Created by Jinwoo Kim on 3/29/25.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ComposeView : UIView
@property (retain, nonatomic, readonly) UITextView *textView;
@property (retain, nonatomic, readonly) UIButton *sendButton;
@end

NS_ASSUME_NONNULL_END
