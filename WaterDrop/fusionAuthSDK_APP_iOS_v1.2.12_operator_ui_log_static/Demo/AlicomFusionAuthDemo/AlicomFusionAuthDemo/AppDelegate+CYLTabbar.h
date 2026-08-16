//
//  AppDelegate+CYLTabbar.h
//  AlicomFusionAuthDemo
//
//  Created by shenchao12344 on 2023/1/3.
//

#import "AppDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate (CYLTabbar)<UITabBarControllerDelegate>
- (void)alicom_configureForTabBarController;
@end

NS_ASSUME_NONNULL_END
