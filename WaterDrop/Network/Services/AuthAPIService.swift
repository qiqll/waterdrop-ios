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
}
