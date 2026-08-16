import SwiftUI

@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    enum Theme: Int, CaseIterable {
        case warm = 0
        case neutral = 1

        var displayName: String {
            switch self {
            case .warm: return "暖色系主题"
            case .neutral: return "素色系主题"
            }
        }
    }

    private static let prefsKey = "current_theme"

    var currentTheme: Theme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: Self.prefsKey)
        }
    }

    private init() {
        let raw = UserDefaults.standard.integer(forKey: Self.prefsKey)
        self.currentTheme = Theme(rawValue: raw) ?? .warm
    }
}
