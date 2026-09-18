import Foundation

// MARK: - Version Check Request

/// 版本检查请求体，对应服务端 `POST /api/version/check` 的 `VersionCheckRequest`。
///
/// `platform` 服务端会做大小写归一化（缺陷修复），但这里仍固定发小写，
/// 不依赖服务端的容错 —— 两侧一致，排查时少一个变量。
struct VersionCheckRequest: Encodable {
    let platform: String
    let currentVersion: String
}

// MARK: - Version Check Response

/// 版本检查响应，对应服务端 `VersionCheckResponse`。
///
/// 字段可用性（服务端 F-012 缺陷 C 的修复结果）：
/// - `needUpdate` 为 `false` 时，`updateType` / `downloadUrl` / `fileSize` **为 null**
///   （服务端 `@JsonInclude(NON_NULL)` 会把它们整个省略）。
/// - `latestVersion` / `versionName` / `description` / `changelog` 无论是否需要更新都会返回，
///   供「已是最新」的呈现使用。
///
/// 因此「要展示什么」必须由 `needUpdate` 决定，而不是由某个字段是否为空决定。
struct VersionCheckResponse: Codable {
    let needUpdate: Bool
    let updateType: String?
    let latestVersion: String?
    let versionName: String?
    let description: String?
    let downloadUrl: String?
    let fileSize: Int64?
    let changelog: String?
}

/// `fullScreenCover(item:)` 要求元素可标识。
/// 用 `latestVersion` 作 id：一个版本检查结果对应一个最新版本号，
/// 每次启动重新拉取时若版本号变了，弹窗内容也会跟着更新。
extension VersionCheckResponse: Identifiable {
    var id: String { latestVersion ?? "unknown" }
}

// MARK: - Update Type

/// 服务端 `update_type` 的字面量，与 `AppVersion.updateType` 的注释一致。
enum VersionUpdateType: String {
    /// 强制更新：不可取消，必须升级才能继续使用。
    case force = "FORCE"
    /// 可选更新：可「稍后再说」。
    case optional = "OPTIONAL"
    /// 静默更新：不打扰用户。
    case silent = "SILENT"
}
