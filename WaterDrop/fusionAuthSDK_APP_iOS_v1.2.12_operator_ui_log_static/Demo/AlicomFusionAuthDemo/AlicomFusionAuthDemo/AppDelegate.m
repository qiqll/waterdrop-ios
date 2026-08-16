//
//  AppDelegate.m
//  AlicomFusionAuthDemo
//
//  Created by shenchao12344 on 2023/1/3.
//

#import "AppDelegate.h"
#import "AppDelegate+CYLTabBar.h" // 导入的分类文件

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    [self alicom_configureForTabBarController];
    return YES;
}



@end
