//
//  AlicomFusionDemoUtil.h
//  AlicomFusionAuthDemo
//
//  Created by shenchao12344 on 2023/2/28.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AlicomFusionDemoUtil : NSObject
+ (UIImage *)demoImageWithColor:(UIColor *)color size:(CGSize)size isRoundedCorner:(BOOL )isRounded radius:(CGFloat)radius;
+ (CGFloat)getDemoStatusBarHeight;
@end

NS_ASSUME_NONNULL_END
