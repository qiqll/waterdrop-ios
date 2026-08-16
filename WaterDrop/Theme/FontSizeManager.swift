import SwiftUI

@Observable
final class FontSizeManager {
    static let shared = FontSizeManager()

    enum FontSize: String, CaseIterable {
        case small = "small"
        case medium = "medium"
        case large = "large"

        var displayName: String {
            switch self {
            case .small: return "小字体"
            case .medium: return "中字体"
            case .large: return "大字体"
            }
        }

        var textSize: CGFloat {
            switch self {
            case .small: return 16
            case .medium: return 20
            case .large: return 24
            }
        }
    }

    private static let prefsKey = "font_size"

    var currentFontSize: FontSize {
        didSet {
            UserDefaults.standard.set(currentFontSize.rawValue, forKey: Self.prefsKey)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.prefsKey) ?? FontSize.small.rawValue
        self.currentFontSize = FontSize(rawValue: raw) ?? .small
    }
}
