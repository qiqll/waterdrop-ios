import Foundation

final class UserPreferencesManager {
    static let shared = UserPreferencesManager()

    private let nicknameKey = "user_nickname"

    private init() {}

    var nickname: String {
        get { UserDefaults.standard.string(forKey: nicknameKey) ?? "用户" }
        set { UserDefaults.standard.set(newValue, forKey: nicknameKey) }
    }

    var hasCustomNickname: Bool {
        UserDefaults.standard.string(forKey: nicknameKey) != nil
    }
}
