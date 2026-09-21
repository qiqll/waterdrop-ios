import Foundation

enum AuthAPIService {
    static func refreshToken(refreshToken: String) async throws -> ApiResponse<RefreshTokenResponse> {
        let request = RefreshTokenRequest(refreshToken: refreshToken)
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.refreshToken,
            method: .POST,
            body: request,
            requiresAuth: false
        )
    }

    static func logout(refreshToken: String) async throws -> ApiResponse<EmptyData> {
        let request = LogoutRequest(refreshToken: refreshToken)
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.logout,
            method: .POST,
            body: request
        )
    }

    static func getUserProfile() async throws -> ApiResponse<UserInfoResponse> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.userProfile
        )
    }

    /// F-012 (D-1)：更新昵称/头像。
    ///
    /// 服务端返回 `Result<Void>`（data 为空），故用 `ApiResponse<EmptyData>` 解码。
    /// 传入 `nil` 的字段不会出现在请求体里，服务端按「本次不修改」处理。
    static func updateProfile(nickname: String? = nil, avatar: String? = nil) async throws -> ApiResponse<EmptyData> {
        let request = UpdateProfileRequest(nickname: nickname, avatar: avatar)
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.userProfile,
            method: .PUT,
            body: request
        )
    }

    /// F-012 ⑥ (D-10)：上报一次活跃。服务端返回 `Result<Void>`。
    ///
    /// 调用方应走 `HeartbeatReporter`（按天节流），不要直接按页面出现频率调用 ——
    /// 服务端落的是累加计数器，见 `ServerConfig.Endpoints.heartbeat` 的说明。
    static func reportHeartbeat() async throws -> ApiResponse<EmptyData> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.heartbeat,
            method: .POST
        )
    }
}
