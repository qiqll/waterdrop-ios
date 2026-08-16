//
//  AlicomFusionAccountViewController.m
//  AlicomFusionAuthDemo
//
//  Created by shenchao12344 on 2023/1/3.
//

#import "AlicomFusionAccountViewController.h"
#import "AlicomFusionSettingViewController.h"

#define LOGIN_TEMPLATEID @"100001"

@interface AlicomFusionAccountViewController ()<AlicomFusionAuthDelegate>
@property (nonatomic, strong) UIButton *headView;
@property (nonatomic, strong) UIImageView *avatorImageView;
@property (nonatomic, strong) UILabel *textLabel;
@property (nonatomic, strong) UIImageView *arrowImageView;
@property (nonatomic, strong) UIView *contentView;

@end

@implementation AlicomFusionAccountViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    [self checkLogin];
}

- (void)toAddSubviews {
    [self.view addSubview:self.headView];
    [self.headView addSubview:self.avatorImageView];
    [self.headView addSubview:self.textLabel];
    [self.headView addSubview:self.arrowImageView];
    [self.view addSubview:self.contentView];
}


- (void)toLayoutSubviews {
    [self.headView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.mas_equalTo(self.view);
        make.top.mas_equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(30);
        make.height.mas_equalTo(54);
    }];
    [self.avatorImageView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(26);
        make.top.mas_equalTo(self.headView);
        make.size.mas_equalTo(CGSizeMake(54, 54));
    }];
    [self.arrowImageView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.mas_equalTo(self.avatorImageView);
        make.size.mas_equalTo(CGSizeMake(7, 13));
        make.right.mas_equalTo(-16);
    }];
    [self.textLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(self.avatorImageView.mas_right).offset(24);
        make.right.mas_equalTo(self.arrowImageView.mas_left).offset(-24);
        make.centerY.mas_equalTo(self.avatorImageView);
    }];
    [self.contentView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(16);
        make.top.mas_equalTo(self.headView.mas_bottom).offset(24);
        make.right.mas_equalTo(-16);
        make.bottom.mas_equalTo(self.view.mas_safeAreaLayoutGuideBottom).offset(-16);
    }];
}

- (BOOL)checkLogin{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *phoneNum = [ud objectForKey:kDEMO_UD_PHONE_NUM];
    if(phoneNum && [phoneNum isKindOfClass:NSString.class] && phoneNum.length > 4){
        self.textLabel.text = [phoneNum stringByReplacingCharactersInRange:NSMakeRange(3, 4) withString:@"****"];
        NSLog(@"login-->%@",phoneNum);
        return YES;
    } else {
        self.textLabel.text = @"登录/注册";
    }
    return NO;
}

#pragma mark - action
- (void)goToSetting {
    if ([self checkLogin]){
        AlicomFusionSettingViewController *VC = [[AlicomFusionSettingViewController alloc] init];
        [self.navigationController pushViewController:VC animated:YES];
    }else{
        if ([AlicomFusionManager shareInstance].isActive){
            [[AlicomFusionManager shareInstance] startSceneWithTemplateId:LOGIN_TEMPLATEID viewController:self];
        }else{
            [[AlicomFusionManager shareInstance] start];
            [AlicomFusionToastTool showToastMsg:@"token鉴权未完成" time:2];
        }
    }
}


#pragma mark - load
- (UIButton *)headView {
    if (!_headView) {
        _headView = [UIButton buttonWithType:UIButtonTypeCustom];
        [_headView addTarget:self action:@selector(goToSetting) forControlEvents:UIControlEventTouchUpInside];
    }
    return _headView;
}

- (UIImageView *)avatorImageView {
    if (!_avatorImageView) {
        _avatorImageView = [UIImageView new];
        _avatorImageView.image = [UIImage imageNamed:@"alicom_account_avator"];
    }
    return _avatorImageView;
}

- (UILabel *)textLabel {
    if (!_textLabel) {
        _textLabel = [[UILabel alloc] init];
        _textLabel.text = @"登录/注册";
        _textLabel.textColor = AlicomColorHex(0x262626);
        _textLabel.font = [UIFont systemFontOfSize:24];
        
    }
    return _textLabel;
}


- (UIImageView *)arrowImageView {
    if (!_arrowImageView) {
        _arrowImageView = [UIImageView new];
        _arrowImageView.image = [UIImage imageNamed:@"alicom_arrow_icon"];
    }
    return _arrowImageView;
}

- (UIView *)contentView {
    if (!_contentView) {
        _contentView = [UIView new];
        _contentView.backgroundColor = AlicomColorHex(0xE8E8E8);
        _contentView.layer.cornerRadius = 8;
    }
    return _contentView;
}

@end
