//
//  AppDelegate+CYLTabbar.m
//  AlicomFusionAuthDemo
//
//  Created by shenchao12344 on 2023/1/3.
//

#import "AppDelegate+CYLTabbar.h"
#import "CYLTabBarController.h"
#import "AlicomFusionAccountViewController.h"

@implementation AppDelegate (CYLTabbar)
- (void)alicom_configureForTabBarController {
    //获取鉴权token
    [[AlicomFusionManager shareInstance] start];
    // 设置主窗口，并设置根视图控制器
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    // 初始化 CYLTabBarController 对象
    CYLTabBarController *tabBarController =
    [CYLTabBarController tabBarControllerWithViewControllers:[self viewControllers]
                                              tabBarItemsAttributes:[self tabBarItemsAttributes]];
    // 设置遵守委托协议
    tabBarController.delegate = self;
    tabBarController.tabBar.backgroundColor = UIColor.whiteColor;
    tabBarController.selectedIndex = 3;
    // 将 CYLTabBarController 设置为 window 的 RootViewController
    self.window.rootViewController = tabBarController;
}

/// 控制器数组
- (NSArray *)viewControllers {
    // 首页
    UIViewController *homeVC = [[UIViewController alloc] init];
    homeVC.navigationItem.title = @"首页";
    CYLBaseNavigationController *homeNav = [[CYLBaseNavigationController alloc] initWithRootViewController:homeVC];
    [homeNav cyl_setHideNavigationBarSeparator:YES];
    
    // 活动
    UIViewController *activityVC = [[UIViewController alloc] init];
    activityVC.navigationItem.title = @"权益";
    CYLBaseNavigationController *activityNav = [[CYLBaseNavigationController alloc] initWithRootViewController:activityVC];
    [activityNav cyl_setHideNavigationBarSeparator:YES];
    
    // 订单
    UIViewController *orderVC = [[UIViewController alloc] init];
    orderVC.navigationItem.title = @"订单";
    CYLBaseNavigationController *orderNav = [[CYLBaseNavigationController alloc] initWithRootViewController:orderVC];
    [orderNav cyl_setHideNavigationBarSeparator:YES];
    
    // 我的
    AlicomFusionAccountViewController *accountVC = [[AlicomFusionAccountViewController alloc] init];
    accountVC.navigationItem.title = @"我的";
    CYLBaseNavigationController *accountNav = [[CYLBaseNavigationController alloc] initWithRootViewController:accountVC];
    [accountNav cyl_setHideNavigationBarSeparator:YES];
    
    NSArray *viewControllersArray = @[homeNav, activityNav, orderNav, accountNav];
    return viewControllersArray;
}

/// tabBar 属性数组
- (NSArray *)tabBarItemsAttributes {
    NSDictionary *homeTabBarItemsAttributes = @{
        CYLTabBarItemTitle: @"首页",
        CYLTabBarItemImage: @"alicom_home_unselected_icon",
        CYLTabBarItemSelectedImage: @"alicom_home_selected_icon",
    };
    NSDictionary *activityTabBarItemsAttributes = @{
        CYLTabBarItemTitle: @"权益",
        CYLTabBarItemImage: @"alicom_activity_unselected_icon",
        CYLTabBarItemSelectedImage: @"alicom_activity_selected_icon",
    };
    NSDictionary *orderTabBarItemsAttributes = @{
        CYLTabBarItemTitle: @"订单",
        CYLTabBarItemImage: @"alicom_order_unselected_icon",
        CYLTabBarItemSelectedImage: @"alicom_order_selected_icon",
    };
    NSDictionary *accountTabBarItemsAttributes = @{
        CYLTabBarItemTitle: @"我的",
        CYLTabBarItemImage: @"alicom_mine_unselected_icon",
        CYLTabBarItemSelectedImage: @"alicom_mine_selected_icon",
    };

    NSArray *tabBarItemsAttributes = @[
        homeTabBarItemsAttributes,
        activityTabBarItemsAttributes,
        orderTabBarItemsAttributes,
        accountTabBarItemsAttributes
    ];
    return tabBarItemsAttributes;
}

@end
