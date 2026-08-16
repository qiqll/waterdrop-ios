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

    func clearAuthInfo() {
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
