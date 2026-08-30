import Foundation
import UIKit
import os.log

final class AuthService {
    static let shared = AuthService()

    private let logger = Logger(subsystem: "com.yjqi.waterdrop.ios", category: "AuthService")
    private let fusionAuthManager = AlicomFusionAuthManager.shared

    private init() {}

    // MARK: - Alicloud Authentication Flow

    /// Full flow: get auth token → init SDK → SDK verify phone → send maskToken to server → save tokens
    func performAlicloudAuthentication(from viewController: UIViewController) async throws {
        // Step 1: Get auth token from our server
        logger.info("Step 1: Getting auth token from server")
        let authTokenResponse = try await getAlicloudAuthToken()

        // Step 2: Initialize SDK with auth token
        logger.info("Step 2: Initializing Alicloud SDK")
        fusionAuthManager.initialize(authToken: authTokenResponse.authToken)

        // Wait briefly for SDK token authentication
        try await Task.sleep(for: .seconds(1))

        // Step 3: Launch SDK login scene and get maskToken
        logger.info("Step 3: Starting login scene")
        let maskToken = try await fusionAuthManager.startLoginScene(from: viewController)

        // Step 4: Send maskToken to our server for login
        logger.info("Step 4: Sending verify token to server")
        let deviceId = DeviceInfo.deviceId
        let loginRequest = AlicloudLoginRequest(verifyToken: maskToken, deviceId: deviceId)
        let response: ApiResponse<AlicloudLoginResponse> = try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.alicloudLogin,
            method: .POST,
            body: loginRequest,
            requiresAuth: false
        )

        guard response.code == 200, let data = response.data else {
            throw NetworkError.businessError(code: response.code, message: response.message)
        }

        // Step 5: Save auth info
        AuthStateManager.shared.saveAuthInfo(
            userId: data.user.id,
            accessToken: data.accessToken,
            refreshToken: data.refreshToken,
            expiresAt: data.expiresAt
        )

        logger.info("Alicloud authentication successful for user: \(data.user.id)")

        // Cleanup SDK
        fusionAuthManager.destroy()
    }

    /// Get alicloud auth token from server
    func getAlicloudAuthToken() async throws -> AlicloudAuthTokenResponse {
        let request = AlicloudAuthTokenRequest()
        let response: ApiResponse<AlicloudAuthTokenResponse> = try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.alicloudAuthToken,
            method: .POST,
            body: request,
            requiresAuth: false
        )

        guard response.code == 200, let data = response.data else {
            throw NetworkError.businessError(code: response.code, message: response.message)
        }

        return data
    }

    // MARK: - Token Refresh

    func refreshAccessToken() async -> Bool {
        return await TokenRefreshHandler.shared.refreshTokenIfNeeded()
    }

    // MARK: - Logout

    func logout() async {
        if let refreshToken = AuthStateManager.shared.getRefreshToken() {
            do {
                let request = LogoutRequest(refreshToken: refreshToken)
                let _: ApiResponse<EmptyData> = try await APIClient.shared.request(
                    endpoint: ServerConfig.Endpoints.logout,
                    method: .POST,
                    body: request
                )
            } catch {
                logger.error("Logout API call failed: \(error.localizedDescription)")
            }
        }

        fusionAuthManager.destroy()
        AuthStateManager.shared.clearAuthInfo()
        // Notify the app to switch back to the login screen. Post on the main actor
        // because AuthEventBus.loginRequired backs an @Observable consumed by SwiftUI.
        AuthEventBus.shared.postLoginRequired()
        logger.info("User logged out")
    }

    // MARK: - User Profile

    func getUserProfile() async throws -> UserInfoResponse {
        let response: ApiResponse<UserInfoResponse> = try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.userProfile
        )

        guard response.code == 200, let data = response.data else {
            throw NetworkError.businessError(code: response.code, message: response.message)
        }

        return data
    }
}
