//
//  AlicomFusionResetViewController.m
//  AlicomFusionAuthDemo
//
//  Created by 彦克 on 2023/2/13.
//

#import "AlicomFusionResetViewController.h"

@interface AlicomFusionResetViewController ()

@property (nonatomic, strong) UILabel *textLabel;

@end

@implementation AlicomFusionResetViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    self.title = @"重置密码";
}

- (void)toAddSubviews {
    [self.view addSubview:self.textLabel];
}


- (void)toLayoutSubviews {
    [self.textLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.mas_equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(153);
        make.left.right.mas_equalTo(self.view);
    }];
}

- (UILabel *)textLabel {
    if (!_textLabel) {
        _textLabel = [[UILabel alloc] init];
        _textLabel.text = @"请根据您的业务自定义重置密码的内容";
        _textLabel.textAlignment = NSTextAlignmentCenter;
        _textLabel.textColor = [UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1];
        _textLabel.font = [UIFont fontWithName:@"PingFangSC-Regular" size:12];
        
    }
    return _textLabel;
}

@end
