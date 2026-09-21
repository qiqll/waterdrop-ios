import Foundation
import os.log

@Observable
final class AuthStateManager {
    static let shared = AuthStateManager()

    enum AuthState: Equatable {
        case unauthenticated
        case authenticated(userId: String, expiresAt: Int64)
        case expired(userId: String)
    }

    private(set) var state: AuthState = .unauthenticated
    private let keychain = KeychainManager.shared
    private let logger = Logger(subsystem: "com.waterdrop.ios", category: "AuthState")

    private enum Keys {
        static let userId = "auth_user_id"
        static let accessToken = "auth_access_token"
        static let refreshToken = "auth_refresh_token"
        static let expiresAt = "auth_expires_at"
    }

    private init() {
        self.state = loadCurrentState()
    }

    // MARK: - Public API

    var isAuthenticated: Bool {
        if case .authenticated = state { return true }
        return false
    }

    var isTokenExpired: Bool {
        if case .expired = state { return true }
        guard case .authenticated(_, let expiresAt) = state else { return true }
        return expiresAt > 0 && Int64(Date().timeIntervalSince1970 * 1000) > expiresAt
    }

    func saveAuthInfo(userId: String, accessToken: String, refreshToken: String, expiresAt: Int64) {
        keychain.save(userId, for: Keys.userId)
        keychain.save(accessToken, for: Keys.accessToken)
        keychain.save(refreshToken, for: Keys.refreshToken)
        keychain.save(expiresAt, for: Keys.expiresAt)

        state = .authenticated(userId: userId, expiresAt: expiresAt)
        logger.info("Auth info saved for user: \(userId)")
    }

    func getAccessToken() -> String? {
        keychain.read(for: Keys.accessToken)
    }

    func getRefreshToken() -> String? {
        keychain.read(for: Keys.refreshToken)
    }

    func getCurrentUserId() -> String? {
        keychain.read(for: Keys.userId)
    }

    /// 清除认证信息。
    ///
    /// ⚠️ 这里同时撤销本地的提醒通知（F-012 ⑤）。通知是**与账号无关的系统资源**：
    /// 不撤销的话，退出登录后（甚至换了账号后）上一个账号的提醒照样会响，
    /// 在通知栏里直接泄露前一用户的数据。
    ///
    /// 之所以放在这个**唯一出口**而不是各个调用点（`AuthService.logout`、
    /// `TokenRefreshHandler.handleRefreshFailure`）：散在各处的清理迟早会漏 ——
    /// 将来任何新的「清认证」路径只要忘了写这一行，就会静默地漏通知。
    ///
    /// 撤销走 `Task`（`UNUserNotificationCenter` 只有 async API），**不等待**：
    /// 认证状态的清除必须是同步、立即生效的，不能让登出卡在一次系统调用上。
    /// 撤销本身很快，且 `removePendingNotificationRequests` 不依赖登录态。
    func clearAuthInfo() {
        Task.detached {
            await ScheduleReminderManager.cancelAll()
        }
        keychain.delete(for: Keys.userId)
        keychain.delete(for: Keys.accessToken)
        keychain.delete(for: Keys.refreshToken)
        keychain.delete(for: Keys.expiresAt)
        state = .unauthenticated
        logger.info("Auth info cleared")
    }

    // MARK: - Private

    private func loadCurrentState() -> AuthState {
        guard let userId = keychain.read(for: Keys.userId),
              let _ = keychain.read(for: Keys.accessToken) else {
            return .unauthenticated
        }

        let expiresAt = keychain.readInt64(for: Keys.expiresAt) ?? 0
        if expiresAt > 0 && Int64(Date().timeIntervalSince1970 * 1000) > expiresAt {
            return .expired(userId: userId)
        }

        return .authenticated(userId: userId, expiresAt: expiresAt)
    }
}
