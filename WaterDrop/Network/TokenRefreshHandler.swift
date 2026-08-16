import Foundation
import os.log

actor TokenRefreshHandler {
    static let shared = TokenRefreshHandler()

    private let logger = Logger(subsystem: "com.waterdrop.ios", category: "TokenRefresh")
    private var isRefreshing = false
    private var waitingContinuations: [CheckedContinuation<Bool, Never>] = []

    private init() {}

    /// Refreshes the token if needed. Returns true if refresh succeeded, false otherwise.
    /// Multiple concurrent calls will coalesce into a single refresh request.
    func refreshTokenIfNeeded() async -> Bool {
        if isRefreshing {
            // Another refresh is in progress, wait for it
            return await withCheckedContinuation { continuation in
                waitingContinuations.append(continuation)
            }
        }

        isRefreshing = true

        let success = await performRefresh()

        // Notify all waiting callers
        let continuations = waitingContinuations
        waitingContinuations.removeAll()
        isRefreshing = false

        for continuation in continuations {
            continuation.resume(returning: success)
        }

        return success
    }

    private func performRefresh() async -> Bool {
        guard let refreshToken = AuthStateManager.shared.getRefreshToken() else {
            logger.warning("No refresh token available")
            await handleRefreshFailure()
            return false
        }

        do {
            let body = RefreshTokenRequest(refreshToken: refreshToken)
            let response: ApiResponse<RefreshTokenResponse> = try await APIClient.shared.request(
                endpoint: ServerConfig.Endpoints.refreshToken,
                method: .POST,
                body: body,
                requiresAuth: false
            )

            if response.code == 200, let data = response.data {
                guard let userId = AuthStateManager.shared.getCurrentUserId() else {
                    await handleRefreshFailure()
                    return false
                }
                AuthStateManager.shared.saveAuthInfo(
                    userId: userId,
                    accessToken: data.accessToken,
                    refreshToken: data.refreshToken,
                    expiresAt: data.expiresAt
                )
                logger.info("Token refreshed successfully")
                return true
            } else {
                logger.error("Token refresh business error: \(response.message)")
                await handleRefreshFailure()
                return false
            }
        } catch {
            logger.error("Token refresh failed: \(error.localizedDescription)")
            await handleRefreshFailure()
            return false
        }
    }

    private func handleRefreshFailure() async {
        AuthStateManager.shared.clearAuthInfo()
        AuthEventBus.shared.postLoginRequired()
    }
}
