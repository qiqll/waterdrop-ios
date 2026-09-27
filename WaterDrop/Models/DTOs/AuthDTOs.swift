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


// MARK: - 心跳（F-018 ①）

/// 心跳上报的客户端信息。
///
/// 服务端该接口的 body 是**可选**的 —— 不带时行为与从前一致（只记活跃度）。
/// 带上之后，服务端才能回答「有多少用户还在用老版本」，
/// 那是 `app_versions.min_support_version` 判定所缺的输入。
///
/// ⚠️ 字段名与 Android `HeartbeatRequest` 逐字一致，两端共用一个服务端 DTO。
struct HeartbeatRequest: Encodable {
    let deviceId: String
    /// `android` / `ios`。服务端在缺失时会从 UA 推断，但显式给更准。
    let platform: String
    let version: String
    let versionCode: Int
}
