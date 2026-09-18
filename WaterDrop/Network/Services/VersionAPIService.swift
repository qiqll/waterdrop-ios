import Foundation

/// 版本检查 API。
///
/// 对应服务端 `/api/version/*`。当前只用到 `POST /version/check`，
/// 其余（create / publish / set-current / list）是后台管理动作，客户端不接入。
enum VersionAPIService {

    /// 检查是否有新版本。
    ///
    /// - Parameter currentVersion: 当前版本号，取自 `CFBundleShortVersionString`。
    ///   服务端要求它可解析（1~3 段数字，允许 `v` 前缀等宽松形式），畸形输入按「不更新」处理。
    /// - Note: `requiresAuth: false` —— `/version/check` 在服务端是 `permitAll` 的。
    ///   这一点很关键：更新检查发生在**登录之前**（冷启动闪屏页），此时没有 token，
    ///   若这里要求鉴权，请求会被 401 拒掉，整条更新链路永远不生效。
    static func checkVersion(currentVersion: String) async throws -> ApiResponse<VersionCheckResponse> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.versionCheck,
            method: .POST,
            body: VersionCheckRequest(platform: "ios", currentVersion: currentVersion),
            requiresAuth: false
        )
    }
}
