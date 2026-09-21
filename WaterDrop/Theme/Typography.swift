import SwiftUI
import UIKit

/// 语义字阶 —— 设计稿的层级，而非「用户可调的字号」。
///
/// ## 为什么需要它（F-017 标红项）
///
/// 本仓原本有约 139 处裸 `.font(.system(size:))`。SwiftUI 的 `Font.system(size:)`
/// **不随系统 Dynamic Type 缩放** —— 用户在系统设置里把字号调大，这些文字纹丝不动。
/// app 内的「字号」选项（`FontSizeManager`）也只覆盖主页 3 个 View，进物品列表就失效。
///
/// 对照 Android：那边文本统一用 `sp` 单位，**本就跟随系统缩放**。同一件事在两端后果
/// 完全不同，所以本文件只解决 iOS 侧。
///
/// ## 两步修复的第一步
///
/// 139 处散落的魔法数字是无根之木，无法逐个接缩放语义。先把它们收敛到这里的
/// 10 个档位，再在**档位这一处**统一接缩放 —— 139 个点变成 10 个点。
/// 接口见 ``SwiftUI/Font`` 的 `wd(_:weight:)`。
///
/// ## 与 `FontSizeManager` 的关系（不要合并）
///
/// - `Typography`（本文件）= 设计稿层级，**固定语义**，负责响应**系统**字号
/// - `FontSizeManager`   = 用户在 **app 内**选的档位，负责应用内缩放
///
/// 最终字号 = 语义档位（随系统缩放） × app 内档位系数。
/// 两者叠加，而不是二选一 —— 用户可以既放大系统字号、又在 app 内选「大字体」。
///
/// ## 与 Android 的对应
///
/// 档位取值与 Android `dimens.xml` 的 `text_*` 令牌**逐档对齐**（见下表），
/// 这样两端的设计层级是同一个坐标系。
enum Typography {

    /// 语义档位。取值 = Android `dimens.xml` 的对应令牌。
    ///
    /// | 本枚举 | Android 令牌 | 基准值 |
    /// |---|---|---|
    /// | `.display` | `text_display` | 32 |
    /// | `.headlineLarge` | `text_headline_large` | 24 |
    /// | `.headlineMedium` | `text_headline_medium` | 20 |
    /// | `.titleLarge` | `text_title_large` | 18 |
    /// | `.titleMedium` | `text_title_medium` | 16 |
    /// | `.bodyLarge` | `text_body_large` | 16 |
    /// | `.bodyMedium` | `text_body_medium` | 14 |
    /// | `.bodySmall` | `text_body_small` | 12 |
    /// | `.labelLarge` | `text_label_large` | 14 |
    /// | `.labelMedium` | `text_label_medium` | 12 |
    /// | `.labelSmall` | `text_label_small` | 11 |
    /// | `.displayHero` | （Android 无，iOS 装饰档） | 64 |
    ///
    /// > **不用 `enum Step: CGFloat`**：Swift 不允许重复的 raw value，而本表的档位
    /// > **本就存在同值不同语义**的情况（`titleMedium` 与 `bodyLarge` 同为 16、
    /// > `labelLarge` 与 `bodyMedium` 同为 14、`bodySmall` 与 `labelMedium` 同为 12）。
    /// > 用 `enum` + 计算属性而非 raw value，才能既保住语义区分、又共享数值。
    enum Step: CaseIterable {
        case labelSmall
        case labelMedium
        case bodySmall
        case labelLarge
        case bodyMedium
        case bodyLarge
        case titleMedium
        case titleLarge
        case headlineMedium
        case headlineLarge
        case display
        /// 装饰性超大字号（Splash 品牌字、空态插画字）。
        ///
        /// **单列的理由**：它不参与正文层级的缩放语义。34~80pt 这个区间继续按
        /// Dynamic Type 放大，在 Accessibility 档位下会直接撑破版面。故本档
        /// **刻意不缩放** —— 它是图形，不是文本。参见 ``Font/wdHero(size:)``。
        case displayHero

        /// 设计基准值（pt），与 Android `text_*` 令牌逐档对齐。
        var baseValue: CGFloat {
            switch self {
            case .labelSmall:     return 11
            case .labelMedium:    return 12
            case .bodySmall:      return 12
            case .labelLarge:     return 14
            case .bodyMedium:     return 14
            case .bodyLarge:      return 16
            case .titleMedium:    return 16
            case .titleLarge:     return 18
            case .headlineMedium: return 20
            case .headlineLarge:  return 24
            case .display:        return 32
            case .displayHero:    return 64
            }
        }
    }

    /// 该档位对应的 Dynamic Type 缩放基准文本样式。
    ///
    /// 用 `UIFontMetrics` 而非 SwiftUI 的 `.font(.body)` 等语义字体，原因是本仓的
    /// 基准值来自设计稿（与 Android 逐档对齐），不是 Apple 的默认字号。
    /// `UIFontMetrics(forTextStyle:)` 保留了「这一档大致相当于什么文本样式」的语义，
    /// 从而在不同 Dynamic Type 档位下按对应曲线缩放。
    static func textStyle(for step: Step) -> UIFont.TextStyle {
        switch step {
        case .displayHero:      return .largeTitle   // 不缩放，仅占位
        case .display:          return .largeTitle
        case .headlineLarge:    return .title1
        case .headlineMedium:   return .title2
        case .titleLarge:       return .title3
        case .titleMedium:      return .headline
        case .bodyLarge:        return .body
        case .bodyMedium:       return .callout
        case .bodySmall:        return .subheadline
        case .labelLarge:       return .subheadline
        case .labelMedium:      return .caption1
        case .labelSmall:       return .caption2
        }
    }

    /// 把基准值换算成当前 Dynamic Type 档位下的实际点数。
    ///
    /// - Parameter step: 语义档位
    /// - Returns: 已按系统字号设置缩放后的点数
    static func scaledValue(for step: Step) -> CGFloat {
        guard step != .displayHero else { return step.baseValue }
        return UIFontMetrics(forTextStyle: textStyle(for: step))
            .scaledValue(for: step.baseValue)
    }
}

// MARK: - Font 扩展

extension Font {

    /// 取一个语义档位的字体，并响应系统 Dynamic Type。
    ///
    /// 用法：`Text("钥匙").font(.wd(.bodyMedium))`
    ///
    /// 替代裸 `.font(.system(size: 14))` —— 后者在系统字号调大时**不会变化**。
    ///
    /// - Parameters:
    ///   - step: 语义档位，见 ``Typography/Step``
    ///   - weight: 字重，默认 `.regular`
    static func wd(_ step: Typography.Step, weight: Font.Weight = .regular) -> Font {
        guard step != .displayHero else { return wdHero(weight: weight) }
        return .system(size: Typography.scaledValue(for: step), weight: weight)
    }

    /// 装饰性超大字号。**不响应 Dynamic Type**（见 ``Typography/Step/displayHero``）。
    ///
    /// - Parameter size: 实际点数；省略则用基准 64
    static func wdHero(size: CGFloat = Typography.Step.displayHero.baseValue,
                       weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - app 内字号档位

extension FontSizeManager.FontSize {

    /// 该档位相对于「中」的字号系数。
    ///
    /// 与 ``Typography`` 的语义档位**相乘**，而非替代它：
    /// 语义档位负责「这一段是什么层级」，本系数负责「用户想整体看多大」。
    ///
    /// 取值为线性比例（16/20/24 → 0.8 / 1.0 / 1.2），而非把基准值直接替换掉 ——
    /// 后者会让 `.display`(32) 在小档位下缩成 16，标题层级整个塌掉。
    var scaleFactor: CGFloat {
        switch self {
        case .small:  return 0.8
        case .medium: return 1.0
        case .large:  return 1.2
        }
    }
}

extension Font {

    /// 同时应用语义档位与 app 内字号选项。
    ///
    /// 这是**页面代码应该优先使用**的入口 —— 只用 `.wd(...)` 会响应系统字号
    /// 但不响应 app 内的字号设置，而现状是后者只覆盖主页。
    ///
    /// - Parameters:
    ///   - step: 语义档位
    ///   - weight: 字重
    ///   - userScale: app 内字号档位系数；传 `nil` 表示不应用（默认取当前设置）
    static func wd(_ step: Typography.Step,
                   weight: Font.Weight = .regular,
                   userScale: CGFloat? = nil) -> Font {
        let factor = userScale ?? FontSizeManager.shared.currentFontSize.scaleFactor
        guard step != .displayHero else { return wdHero(weight: weight) }
        return .system(size: Typography.scaledValue(for: step) * factor, weight: weight)
    }
}
