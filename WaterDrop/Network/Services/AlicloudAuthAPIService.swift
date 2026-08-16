import Foundation

enum AlicloudAuthAPIService {
    static func getAuthToken(bundleId: String? = Bundle.main.bundleIdentifier) async throws -> ApiResponse<AlicloudAuthTokenResponse> {
        let request = AlicloudAuthTokenRequest(bundleId: bundleId)
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.alicloudAuthToken,
            method: .POST,
            body: request,
            requiresAuth: false
        )
    }

    static func fusionLogin(verifyToken: String, deviceId: String) async throws -> ApiResponse<AlicloudLoginResponse> {
        let request = AlicloudLoginRequest(verifyToken: verifyToken, deviceId: deviceId)
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.alicloudLogin,
            method: .POST,
            body: request,
            requiresAuth: false
        )
    }
}
