import Foundation

// MARK: - Refresh Token

struct RefreshTokenRequest: Codable {
    let refreshToken: String
}

struct RefreshTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int64
}

// MARK: - User Info

struct UserInfoResponse: Codable {
    let id: String
    let phone: String
    let nickname: String?
    let avatar: String?
    let status: Int
    let createTime: String?
    let lastLoginTime: String?
}

// MARK: - Logout

struct LogoutRequest: Codable {
    let refreshToken: String
}
