import Foundation

// MARK: - Alicloud Auth Token

struct AlicloudAuthTokenRequest: Codable {
    let platform: String
    let bundleId: String?
    let durationSeconds: Int

    init(bundleId: String? = Bundle.main.bundleIdentifier, durationSeconds: Int = 900) {
        self.platform = "iOS"
        self.bundleId = bundleId
        self.durationSeconds = durationSeconds
    }
}

struct AlicloudAuthTokenResponse: Codable {
    let success: Bool
    let code: String
    let message: String
    let authToken: String
    let durationSeconds: Int
    let requestId: String
}

// MARK: - Alicloud Fusion Login

struct AlicloudLoginRequest: Codable {
    let verifyToken: String
    let deviceId: String
    let platform: String

    init(verifyToken: String, deviceId: String) {
        self.verifyToken = verifyToken
        self.deviceId = deviceId
        self.platform = "iOS"
    }
}

struct AlicloudLoginResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let user: AlicloudUserInfo
    let authMethod: String?
    let carrier: String?
    let expiresAt: Int64
}

struct AlicloudUserInfo: Codable {
    let id: String
    let phone: String
    let nickname: String?
    let avatar: String?
    let status: Int?
}
