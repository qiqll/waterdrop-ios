import SwiftUI

// MARK: - WaterDrop Theme Palettes
//
// 双主题色板。`.warm` 与既有 `AppColors` 逐值等价（暖色系，与 Android colors.xml 对齐）；
// `.neutral` 为冷色系，按「保明度、保饱和度、仅换色相」规则从 warm 对位生成：
//
//   primary   142-153° → 203° (雾蓝)      secondary  33-35° → 228° (靛蓝)
//   accent    24°      → 188° (青)        neutral    30-36° → 215° (冷灰)
//
// 两处偏离纯对位（见 docs/dev/plans/F-009.md §2.2）：
//   ① accent 为使 FAB 白色图标对比度不低于暖色基准(2.03)，明度由 69.8 下调至 54.4 → #39C6DC (2.04)
//   ② recordingActive 与 semanticError 同族（暖色两值相同），同样取 error 色相 358°
//
// 使用方式：`ThemeManager.shared.palette.primary`（见 ThemeManager.palette）。

struct Palette {
    // MARK: Primary
    let primary: Color
    let primaryVariant: Color
    let primaryLight: Color
    let onPrimary: Color

    // MARK: Secondary
    let secondary: Color
    let secondaryVariant: Color
    let onSecondary: Color

    // MARK: Accent (FAB only)
    let accent: Color
    let accentVariant: Color
    let onAccent: Color

    // MARK: Semantic
    let semanticSuccess: Color
    let semanticWarning: Color
    let semanticError: Color
    let semanticInfo: Color
    let semanticSuccessBg: Color
    let semanticWarningBg: Color
    let semanticErrorBg: Color
    let semanticInfoBg: Color

    // MARK: Neutral (10 steps)
    let neutral0: Color
    let neutral50: Color
    let neutral100: Color
    let neutral200: Color
    let neutral300: Color
    let neutral400: Color
    let neutral500: Color
    let neutral600: Color
    let neutral700: Color
    let neutral800: Color
    let neutral900: Color

    // MARK: Surface & Background
    let background: Color
    let surface: Color
    let surfaceVariant: Color
    let divider: Color

    // MARK: Recording State
    let recordingActive: Color

    /// 录音脉冲环：录制色 20% 透明度。
    var recordingPulse: Color { recordingActive.opacity(0.2) }
}

// MARK: - Warm (松绿 / 沙金 / 杏橙)

extension Palette {
    static let warm = Palette(
        primary: Color(hex: "5B7E6B"),              // Mist Pine Green
        primaryVariant: Color(hex: "476256"),       // Deep Pine Green (pressed)
        primaryLight: Color(hex: "E8F0EB"),         // Mint Mist (subtle bg)
        onPrimary: .white,

        secondary: Color(hex: "C4A882"),            // Warm Sand Gold
        secondaryVariant: Color(hex: "A68B6A"),     // Deep Sand Gold
        onSecondary: .white,

        accent: Color(hex: "E8A87C"),               // Apricot - FAB button
        accentVariant: Color(hex: "D4956B"),        // Deep Apricot (pressed)
        onAccent: .white,

        semanticSuccess: Color(hex: "5B9A6B"),
        semanticWarning: Color(hex: "E5A84B"),
        semanticError: Color(hex: "C75450"),
        semanticInfo: Color(hex: "5B8EC7"),
        semanticSuccessBg: Color(hex: "EDF5EF"),
        semanticWarningBg: Color(hex: "FDF5E6"),
        semanticErrorBg: Color(hex: "FAEDEC"),
        semanticInfoBg: Color(hex: "EDF2F9"),

        neutral0: .white,
        neutral50: Color(hex: "FAFAF8"),            // Page background
        neutral100: Color(hex: "F5F3F0"),           // Subtle area bg
        neutral200: Color(hex: "E8E5E1"),           // Border, divider
        neutral300: Color(hex: "D4D0CB"),           // Disabled bg
        neutral400: Color(hex: "B0ABA4"),           // Placeholder text
        neutral500: Color(hex: "8A847D"),           // Secondary icon
        neutral600: Color(hex: "6B665F"),           // Secondary text
        neutral700: Color(hex: "4A4640"),           // Subtitle text
        neutral800: Color(hex: "2D2A26"),           // Primary text
        neutral900: Color(hex: "1A1816"),           // Deepest, rare use

        background: Color(hex: "FAFAF8"),
        surface: .white,
        surfaceVariant: Color(hex: "F5F3F0"),
        divider: Color(hex: "E8E5E1"),

        recordingActive: Color(hex: "C75450")
    )

    // MARK: - Neutral (雾蓝 / 靛蓝 / 青)

    static let neutral = Palette(
        primary: Color(hex: "5B717E"),              // Mist Blue
        primaryVariant: Color(hex: "475862"),       // Deep Mist Blue (pressed)
        primaryLight: Color(hex: "E8EDF0"),         // Pale Blue Mist (subtle bg)
        onPrimary: .white,

        secondary: Color(hex: "828FC4"),            // Cool Periwinkle
        secondaryVariant: Color(hex: "6A76A6"),     // Deep Periwinkle
        onSecondary: .white,

        accent: Color(hex: "39C6DC"),               // Cyan - FAB button (对比度对齐暖色 FAB)
        accentVariant: Color(hex: "36A9BA"),        // Deep Cyan (pressed)
        onAccent: .white,

        semanticSuccess: Color(hex: "5B9A85"),
        semanticWarning: Color(hex: "E5BC4B"),
        semanticError: Color(hex: "C75054"),
        semanticInfo: Color(hex: "5B86C7"),
        semanticSuccessBg: Color(hex: "EDF5F2"),
        semanticWarningBg: Color(hex: "FDF7E6"),
        semanticErrorBg: Color(hex: "FAECEC"),
        semanticInfoBg: Color(hex: "EDF2F9"),

        neutral0: .white,
        neutral50: Color(hex: "F8F9FA"),            // Page background
        neutral100: Color(hex: "F0F2F5"),           // Subtle area bg
        neutral200: Color(hex: "E1E4E8"),           // Border, divider
        neutral300: Color(hex: "CBCFD4"),           // Disabled bg
        neutral400: Color(hex: "A4A9B0"),           // Placeholder text
        neutral500: Color(hex: "7D828A"),           // Secondary icon
        neutral600: Color(hex: "5F646B"),           // Secondary text
        neutral700: Color(hex: "40444A"),           // Subtitle text
        neutral800: Color(hex: "26292D"),           // Primary text
        neutral900: Color(hex: "16181A"),           // Deepest, rare use

        background: Color(hex: "F8F9FA"),
        surface: .white,
        surfaceVariant: Color(hex: "F0F2F5"),
        divider: Color(hex: "E1E4E8"),

        recordingActive: Color(hex: "C75054")
    )
}
