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

// MARK: - Update Profile

/// F-011 (D-1)：`PUT /users/profile` 请求体。
///
/// 可选字段契约（与 D-4 一致）：`nil` = 本次不修改；`""` = 显式清空。
struct UpdateProfileRequest: Codable {
    let nickname: String?
    let avatar: String?

    init(nickname: String? = nil, avatar: String? = nil) {
        self.nickname = nickname
        self.avatar = avatar
    }
}

// MARK: - Logout

struct LogoutRequest: Codable {
    let refreshToken: String
}
