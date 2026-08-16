//
//  AccountTableViewCell.h
//  AlicomFusionAuthDemo
//
//  Created by shenchao12344 on 2023/1/3.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AccountTableViewCell : UITableViewCell
- (void)updateCell:(NSString *)nameStr detail:(NSString *)detailStr;
@end

NS_ASSUME_NONNULL_END
