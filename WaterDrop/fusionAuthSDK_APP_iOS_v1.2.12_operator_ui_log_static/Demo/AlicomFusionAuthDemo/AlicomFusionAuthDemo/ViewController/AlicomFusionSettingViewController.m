//
//  AlicomFusionSettingViewController.m
//  AlicomFusionAuthDemo
//
//  Created by shenchao12344 on 2023/1/3.
//

#import "AlicomFusionSettingViewController.h"
#import "AccountTableViewCell.h"
#import "AlicomFusionToastTool.h"
#import "AlicomFusionResetViewController.h"

@interface AlicomFusionSettingViewController ()<UITableViewDelegate, UITableViewDataSource,AlicomFusionManagerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray *dataSource;
@property (nonatomic, copy) NSArray *templateIdArr;
@property (nonatomic, copy) NSString *currTemplateId;
@end

@implementation AlicomFusionSettingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    self.title = @"我的个人信息";
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
    if (indexPath.section == 1){
        if (indexPath.row == 0) {
            [AlicomFusionAuthTokenManager logout];
            [[AlicomFusionManager shareInstance] destory];
            
            NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
            [ud removeObjectForKey:kDEMO_UD_PHONE_NUM];
            [self.navigationController popViewControllerAnimated:YES];
        }
        return;
    }
    self.currTemplateId = self.templateIdArr[indexPath.row];
    if ([AlicomFusionManager shareInstance].isActive){
        [[AlicomFusionManager shareInstance] startSceneWithTemplateId:self.currTemplateId viewController:self];
        if (indexPath.row == 3){
            [[AlicomFusionManager shareInstance] setDelegate:self];
        }
    }else{
        [[AlicomFusionManager shareInstance] start];
        [AlicomFusionToastTool showToastMsg:@"token鉴权未完成" time:2];
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

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{
    return 56;
}

- (UITableView *)tableView {
    if (!_tableView) {
        _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
        _tableView.delegate = self;
        _tableView.dataSource = self;
        _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    }
    return _tableView;
}

#pragma mark - AlicomFusionManagerDelegate
- (void)verifySuccess{
    if ([self.currTemplateId isEqualToString:self.templateIdArr.lastObject]){
        AlicomFusionResetViewController *VC = [[AlicomFusionResetViewController alloc] init];
        [self.navigationController pushViewController:VC animated:YES];
    }
}

- (NSArray *)dataSource {
    if (!_dataSource) {
        _dataSource = @[
            @[@"修改手机号", @"绑定新手机号", @"验证当前手机号", @"重置登录密码"],
            @[@"退出登录"]
        ];
    }
    return _dataSource;
}

- (NSArray *)templateIdArr{
    if (!_templateIdArr){
        _templateIdArr = @[@"100002",@"100004",@"100005",@"100003"];
    }
    return _templateIdArr;
}



@end
