//
//  ComposeView.mm
//  MyMessenger
//
//  Created by Jinwoo Kim on 3/29/25.
//

#import "ComposeView.h"

@interface ComposeView ()
@property (retain, nonatomic, readonly, getter=_stackView) UIStackView *stackView;
@end

@implementation ComposeView
@synthesize textView = _textView;
@synthesize sendButton = _sendButton;
@synthesize stackView = _stackView;

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        UIStackView *stackView = self.stackView;
        stackView.frame = self.bounds;
        stackView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:stackView];
    }
    
    return self;
}

- (void)dealloc {
    [_textView release];
    [_sendButton release];
    [_stackView release];
    [super dealloc];
}

- (CGSize)systemLayoutSizeFittingSize:(CGSize)targetSize {
    return [self.stackView systemLayoutSizeFittingSize:targetSize];
}

- (CGSize)systemLayoutSizeFittingSize:(CGSize)targetSize withHorizontalFittingPriority:(UILayoutPriority)horizontalFittingPriority verticalFittingPriority:(UILayoutPriority)verticalFittingPriority {
    return [self.stackView systemLayoutSizeFittingSize:targetSize withHorizontalFittingPriority:horizontalFittingPriority verticalFittingPriority:verticalFittingPriority];
}

- (CGSize)intrinsicContentSize {
    return self.stackView.intrinsicContentSize;
}

- (UIStackView *)_stackView {
    if (auto stackView = _stackView) return stackView;
    
    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[self.textView, self.sendButton]];
    stackView.axis = UILayoutConstraintAxisHorizontal;
    stackView.alignment = UIStackViewAlignmentFill;
    stackView.distribution = UIStackViewDistributionFill;
    
    _stackView = stackView;
    return stackView;
}

- (UITextView *)textView {
    if (auto textView = _textView) return textView;
    
    UITextView *textView = [UITextView new];
    textView.backgroundColor = UIColor.systemPinkColor;
    textView.textColor = UIColor.whiteColor;
    textView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [textView setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    
    _textView = textView;
    return textView;
}

- (UIButton *)sendButton {
    if (auto sendButton = _sendButton) return sendButton;
    
    UIButton *sendButton = [UIButton new];
    
    UIButtonConfiguration *configuration = [UIButtonConfiguration tintedButtonConfiguration];
    configuration.image = [UIImage systemImageNamed:@"arrow.up"];
    sendButton.configuration = configuration;
    
    [sendButton setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    
    _sendButton = sendButton;
    return sendButton;
}

@end
