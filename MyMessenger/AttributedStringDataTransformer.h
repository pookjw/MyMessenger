//
//  AttributedStringDataTransformer.h
//  MyMessenger
//
//  Created by Jinwoo Kim on 3/28/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AttributedStringDataTransformer : NSSecureUnarchiveFromDataTransformer
@property (class, nonatomic, readonly) NSValueTransformerName valueTransformerName;
@end

NS_ASSUME_NONNULL_END
