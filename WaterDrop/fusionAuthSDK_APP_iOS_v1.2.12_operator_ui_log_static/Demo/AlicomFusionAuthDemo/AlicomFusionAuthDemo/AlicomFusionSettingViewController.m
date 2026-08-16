//
//  AlicomFusionSettingViewController.m
//  AlicomFusionAuthDemo
//
//  Created by shenchao12344 on 2023/1/3.
//

#import "AlicomFusionSettingViewController.h"
#import "AccountTableViewCell.h"
//#import <AlicomFusionAuthSDK/AlicomFusionAuthSDK.h>

@interface AlicomFusionSettingViewController ()<UITableViewDelegate, UITableViewDataSource,AlicomFusionAuthUIDelegate, AlicomFusionAuthDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray *dataSource;
@property (nonatomic, strong) AlicomFusionAuthHandler *handler;
@property (nonatomic, assign) BOOL isActive;
@property (nonatomic, assign) BOOL isStart;
@end

@implementation AlicomFusionSettingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置";

    AlicomFusionAuthToken *token = [[AlicomFusionAuthToken alloc] initWithTokenStr:@"11223344"];
    self.handler = [[AlicomFusionAuthHandler alloc] initWithToken:token];
    [self.handler setFusionAuthDelegate:self];
    
    
    // Do any additional setup after loading the view.
}


- (void)toAddSubviews {
    [self.view addSubview:self.tableView];
}

- (void)toLayoutSubviews {
    [self.tableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.top.right.bottom.mas_equalTo(self.view);
    }];
}


#pragma mark - UItableviewDelegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
//    if (!self.isActive) {
//        [self.handler startSceneUIWithTemplateId:@"100001" viewController:self delegate:self];
//        self.isActive = YES;
//    } else {
//        [self.handler contiuneSceneWithTemplateId:@"100001" isSuccess:YES];
//    }
    if (!self.isActive) {
        return;
    }
    
    if (!self.isStart) {
        [self.handler startSceneUIWithTemplateId:@"100001" viewController:self delegate:self];
        self.isStart = YES;
    } else {
        [self.handler contiuneSceneWithTemplateId:@"100001" isSuccess:YES];
    }
  
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 1 ? @"其他功能" : @"";
}


#pragma mark -UITableviewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.dataSource.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return ((NSArray *)self.dataSource[section]).count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdent = @"cellIdent";
    AccountTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdent];
    if (!cell) {
        cell = [[AccountTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdent];
    }
    [cell updateCell:self.dataSource[indexPath.section][indexPath.row] detail:@""];
    return cell;
}

- (UITableView *)tableView {
    if (!_tableView) {
        _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
        _tableView.delegate = self;
        _tableView.dataSource = self;
    }
    return _tableView;
}

- (NSArray *)dataSource {
    if (!_dataSource) {
        _dataSource = @[
            @[@"修改手机号", @"绑定新手机号", @"验证当前手机号", @"重置登录密码"],
            @[@"功能1", @"功能2", @"功能3"]
        ];
    }
    return _dataSource;
}

#pragma mark - AlicomFusionAuthDelegate
/**
 *  token需要更新
 *  @note 必选回调，handler 初始化&历史token过期前5分钟，会触发此回调，由SDK维护token的生命周期
 *  @param handler handler
 *  @return token，APP更新最新token后，组装AlicomFusionAuthToken返回给到SDK，SDK会通过此token进行鉴权更新
 */
- (AlicomFusionAuthToken *)onSDKTokenUpdate:(AlicomFusionAuthHandler *)handler {
    NSLog(@"%s，调用",__func__);
    return nil;
}

/**
 *  token鉴权成功
 *  @note 必选回调，token鉴权成功后，才可以调用startScene接口拉起场景
 *  @param handler handler
 */
- (void)onSDKTokenAuthSuccess:(AlicomFusionAuthHandler *)handler {
    NSLog(@"%s，调用",__func__);
    self.isActive = YES;
}

/**
 *  token鉴权失败
 *  @note 必选回调，token初次鉴权失败&token更新后鉴权失败均会触发此回调
 *  @note token鉴权失败后，无法继续使用SDK的功能，请销毁SDK后重新初始化
 *  @param handler handler
 *  @param failToken 错误token
 *  @param error 错误定义
 */
- (void)onSDKTokenAuthFaliure:(AlicomFusionAuthHandler *)handler
                    failToken:(AlicomFusionAuthToken *)failToken
                        error:(AlicomFusionEvent *)error {
    self.isActive = NO;
    NSLog(@"%s，调用:{\n%@}",__func__,error.description);
}

/**
 *  认证成功
 *  @note 必选回调
 *  @note 可以使用码号效验maskToken去APP Server做最终验证换取真实手机号码，如果换取手机号失败，可以通过SDK的continue接口继续后续场景流程
 *  @param handler handler
 *  @param maskToken 码号效验token
 */
- (void)onVerifySuccess:(AlicomFusionAuthHandler *)handler
               nodeName:(nonnull NSString *)nodeName
              maskToken:(NSString *)maskToken {
    NSLog(@"%s，调用.nodeName=%@",__func__,nodeName);
//    BOOL isSuccess = YES;
//    if ([nodeId isEqualToString:@"300000100001004"]) {
//        isSuccess = NO;
//    }
    
    [self.handler contiuneSceneWithTemplateId:@"100001" isSuccess:YES];
}

- (void)onVerifyFailed:(AlicomFusionAuthHandler *)handler nodeName:(nonnull NSString *)nodeName error:(nonnull AlicomFusionEvent *)error {
    NSLog(@"%s，nodeName=%@,调用:{\n%@}",__func__,nodeName,error.description);
    [self.handler contiuneSceneWithTemplateId:@"100001" isSuccess:NO];
}

/**
 *  认证结束
 *  @note 必选回调，SDK认证流程结束
 *  @param handler handler
 *  @param event 结束事件
 */
- (void)onVerifyFinish:(AlicomFusionAuthHandler *)handler
                 event:(AlicomFusionEvent *)event {
    NSLog(@"%s，调用:{\n%@}",__func__,event.description);
    [self.handler stopSceneWithTemplateId:@"100001"];
    self.isStart = NO;
}

/**
 *  SDK业务逻辑错误
 *  @note 必选回调，SDK业务逻辑错误，收到此回调后，SDK已无法继续处理业务逻辑，请销毁SDK后重新初始化重试
 *  @param handler handler
 *  @param error 错误定义
 */
- (void)onBusinessError:(AlicomFusionAuthHandler *)handler
                  error:(AlicomFusionEvent *)error {
    NSLog(@"%s，调用:{\n%@}",__func__,error.description);
}

/**
 *  场景事件回调
 *  @note 可选回调，SDK场景流程中流程中各个界面点击事件&界面跳转事件等UI相关回调
 *  @note 本回调接口仅做事件通知，不可再此回调内处理业务逻辑
 *  @param handler handler
 *  @param event 点击事件，具体定义参考AlicomFusionEvent.h
 */
- (void)onAuthEvent:(AlicomFusionAuthHandler *)handler
          eventData:(AlicomFusionEvent *)event {
    NSLog(@"%s，调用:{\n%@}",__func__,event.description);
}

#pragma mark - AlicomFusionAuthUIDelegate
- (void)onPhoneNumberVerifyUICustomDefined:(AlicomFusionAuthHandler *)handler nodeId:(NSString *)nodeId UIModel:(AlicomFusionNumberAuthModel *)model {
//    model.backgroundColor = UIColor.redColor;
    NSLog(@"%s，调用",__func__);
}

// 由用户自定义短信验证码认证相关UI，通过修改view的参数实现自定义UI，不可将view删除
- (void)onSMSCodeVerifyUICustomDefined:(AlicomFusionAuthHandler *)handler
                                nodeId:(NSString *)nodeId
                                  view:(AlicomFusionVerifyCodeView *)view {
    view.backgroundColor = UIColor.redColor;
    NSLog(@"%s，调用",__func__);
}

// // 由用户自定义短信验证码认证相关UI，通过修改view的参数实现自定义UI，不可将view删除
- (void)onSMSSendVerifyUICustomDefined:(AlicomFusionAuthHandler *)handler
                                nodeId:(NSString *)nodeId
                                  view:(AlicomFusionUpGoingView *)view {
    NSLog(@"%s，调用",__func__);
}

// iOS特有  定制navigationBar
- (void)onNavigationControllerCustomDefined:(AlicomFusionAuthHandler *)handler
                                 navigation:(UINavigationController *)naviController {
    NSLog(@"%s，调用",__func__);
}




@end
