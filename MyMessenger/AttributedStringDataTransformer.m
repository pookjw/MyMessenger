//
//  AttributedStringDataTransformer.m
//  MyMessenger
//
//  Created by Jinwoo Kim on 3/28/25.
//

#import "AttributedStringDataTransformer.h"

@implementation AttributedStringDataTransformer

+ (void)load {
    AttributedStringDataTransformer *transformer = [AttributedStringDataTransformer new];
    [NSValueTransformer setValueTransformer:transformer forName:AttributedStringDataTransformer.valueTransformerName];
    [transformer release];
}

+ (NSValueTransformerName)valueTransformerName {
    return @"AttributedStringDataTransformer";
}

+ (NSArray<Class> *)allowedTopLevelClasses {
    return [[super allowedTopLevelClasses] arrayByAddingObject:[NSAttributedString class]];
}

@end
