import Foundation
import UIKit
import os.log

// AlicomFusionAuthHandler is an ObjC class that doesn't conform to Sendable
// but is safe to use on main thread
extension AlicomFusionAuthHandler: @unchecked @retroactive Sendable {}

/// Swift wrapper for Alicloud Fusion Auth SDK (Objective-C)
/// Handles SDK initialization, token management, and authentication callbacks
final class AlicomFusionAuthManager: NSObject {
    static let shared = AlicomFusionAuthManager()

    private let logger = Logger(subsystem: "com.yjqi.waterdrop.ios", category: "AlicomFusionAuth")

    private var handler: AlicomFusionAuthHandler?
    private var isSDKReady = false

    // Continuation for async/await bridge
    private var loginContinuation: CheckedContinuation<String, Error>?

    private override init() {
        super.init()
    }

    // MARK: - SDK Lifecycle

    /// Initialize the SDK with an auth token from the server
    func initialize(authToken: String) {
        let token = AlicomFusionAuthToken(tokenStr: authToken)
        let schemeCode = AppConfig.alicloudSchemeCode

        handler = AlicomFusionAuthHandler(token: token, schemeCode: schemeCode)
        handler?.setFusionAuthDelegate(self)

        logger.info("Alicloud Fusion Auth SDK initialized with schemeCode: \(schemeCode)")
    }

    /// Start the login scene and return the maskToken (verify token) via async/await
    func startLoginScene(from viewController: UIViewController) async throws -> String {
        guard let handler, isSDKReady else {
            throw AlicomFusionError.sdkNotReady
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.loginContinuation = continuation
            let sdkHandler = handler
            DispatchQueue.main.async {
                // Use SDK built-in UI for login/register scene (template 100001)
                // Note: AlicomFusionAuthHandler is ObjC and not Sendable,
                // but it's safe to use on main thread
                sdkHandler.startScene(withTemplateId: AlicomFusionTemplateId_100001,
                                      viewController: viewController)
            }
        }
    }

    /// Stop the current scene
    func stopScene() {
        handler?.stopScene(withTemplateId: AlicomFusionTemplateId_100001)
    }

    /// Destroy the SDK handler
    func destroy() {
        handler?.destroy()
        handler = nil
        isSDKReady = false
    }

    // MARK: - Error

    enum AlicomFusionError: LocalizedError {
        case sdkNotReady
        case tokenAuthFailed(String)
        case verifyFailed(String)
        case userCancelled
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .sdkNotReady:
                return "认证服务未就绪，请稍后重试"
            case .tokenAuthFailed(let msg):
                return "认证初始化失败：\(msg)"
            case .verifyFailed(let msg):
                return "认证失败：\(msg)"
            case .userCancelled:
                return "用户取消了登录"
            case .unknown(let msg):
                return "认证异常：\(msg)"
            }
        }
    }

    // MARK: - Helper

    private func resumeLoginContinuation(with result: Result<String, Error>) {
        if let continuation = loginContinuation {
            loginContinuation = nil
            continuation.resume(with: result)
        }
    }
}

// MARK: - AlicomFusionAuthDelegate

extension AlicomFusionAuthManager: AlicomFusionAuthDelegate {

    /// SDK requests a new auth token (called on init and before token expiry)
    func onSDKTokenUpdate(_ handler: AlicomFusionAuthHandler) -> AlicomFusionAuthToken {
        logger.info("SDK requesting token update")

        // Synchronously fetch a new token from our server
        // The SDK calls this on a background thread, so we can block
        let semaphore = DispatchSemaphore(value: 0)
        var tokenStr: String?

        Task {
            do {
                let response = try await AuthService.shared.getAlicloudAuthToken()
                tokenStr = response.authToken
            } catch {
                self.logger.error("Failed to get auth token for SDK: \(error.localizedDescription)")
            }
            semaphore.signal()
        }

        semaphore.wait()
        return AlicomFusionAuthToken(tokenStr: tokenStr ?? "")
    }

    /// Token authentication succeeded - SDK is ready
    func onSDKTokenAuthSuccess(_ handler: AlicomFusionAuthHandler) {
        logger.info("SDK token auth success - SDK is ready")
        isSDKReady = true
    }

    /// Token authentication failed
    func onSDKTokenAuthFailure(_ handler: AlicomFusionAuthHandler,
                                fail failToken: AlicomFusionAuthToken,
                                error: AlicomFusionEvent) {
        logger.error("SDK token auth failed: \(error.resultCode) - \(error.resultMsg)")
        isSDKReady = false
        resumeLoginContinuation(with: .failure(
            AlicomFusionError.tokenAuthFailed(error.resultMsg)
        ))
    }

    /// Verification succeeded - received maskToken for server-side phone number retrieval
    func onVerifySuccess(_ handler: AlicomFusionAuthHandler,
                         nodeName: String,
                         maskToken: String,
                         event: AlicomFusionEvent) {
        logger.info("Verify success via node: \(nodeName)")

        // Stop the scene and return the maskToken
        handler.stopScene(withTemplateId: AlicomFusionTemplateId_100001)
        resumeLoginContinuation(with: .success(maskToken))
    }

    /// Halfway verification (for multi-step flows like phone number change)
    func onHalfwayVerifySuccess(_ handler: AlicomFusionAuthHandler,
                                 nodeName: String,
                                 maskToken: String,
                                 event: AlicomFusionEvent,
                                 resultBlock: @escaping (Bool) -> Void) {
        logger.info("Halfway verify success via node: \(nodeName)")
        // For login flow, treat as full success
        handler.stopScene(withTemplateId: AlicomFusionTemplateId_100001)
        resumeLoginContinuation(with: .success(maskToken))
        resultBlock(true)
    }

    /// Verification failed at a node
    func onVerifyFailed(_ handler: AlicomFusionAuthHandler,
                        nodeName: String,
                        error: AlicomFusionEvent) {
        logger.error("Verify failed at node \(nodeName): \(error.resultCode) - \(error.resultMsg)")

        // For number auth failures, continue to next node (e.g., SMS fallback)
        if nodeName != AlicomFusionNodeNameVerifyCodeAuth {
            handler.continueScene(withTemplateId: AlicomFusionTemplateId_100001, isSuccess: false)
        }
    }

    /// Scene template finished
    func onTemplateFinish(_ handler: AlicomFusionAuthHandler, event: AlicomFusionEvent) {
        logger.info("Template finished: \(event.resultCode) - \(event.resultMsg)")
        handler.stopScene(withTemplateId: AlicomFusionTemplateId_100001)

        // If we still have a pending continuation, the user cancelled or flow ended without success
        resumeLoginContinuation(with: .failure(AlicomFusionError.userCancelled))
    }

    /// Provide phone number for verification (for password reset, phone change scenarios)
    func onGetPhoneNumber(forVerification handler: AlicomFusionAuthHandler,
                          event: AlicomFusionEvent) -> String {
        // Not applicable for login flow, return empty
        return ""
    }

    /// Protocol/privacy link clicked
    func onProtocolClick(_ handler: AlicomFusionAuthHandler,
                         protocolName: String,
                         protocolUrl: String,
                         event: AlicomFusionEvent) {
        logger.info("Protocol clicked: \(protocolName) -> \(protocolUrl)")
        // Open in Safari
        if let url = URL(string: protocolUrl) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
    }

    /// Verification interrupted (e.g., checkbox not checked, loading state)
    func onVerifyInterrupt(_ handler: AlicomFusionAuthHandler, event: AlicomFusionEvent) {
        logger.info("Verify interrupt: \(event.resultCode) - \(event.resultMsg)")
        // Loading states are handled by SDK UI internally
    }
}
