import Foundation
import os

/// 构建期配置读取。
///
/// 取值链路：`Configs/Secrets.xcconfig` → 构建设置 → `Info.plist` 的 `$(VAR)` 占位 → `Bundle.main`。
/// 这条链路任何一环断掉都不会编译失败，只会让 `Info.plist` 里出现一个空串，
/// 所以这里把**空串一律当作「未配置」**处理，避免 `?? fallback` 因拿到 `""` 而永不生效。
enum AppConfig {
    private static let logger = Logger(subsystem: "com.yjqi.waterdrop.ios", category: "AppConfig")

    static var serverBaseURL: String {
        // 联调/回归用例可以覆盖服务端地址：模拟器里 IP 会因为开发机换网络而变，
        // 而且测试常常要打本机 server 而不是 Secrets.xcconfig 里那台。
        // 只认进程环境变量，不改任何配置文件，Release 下没人设就没有影响。
        if let override = ProcessInfo.processInfo.environment["SERVER_BASE_URL_OVERRIDE"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }
        return resolvedValue(for: "SERVER_BASE_URL", fallback: "https://your-server.com/api/")
    }

    static var alicloudAppKey: String {
        infoPlistValue(for: "ALICLOUD_APP_KEY") ?? ""
    }

    static var alicloudSchemeCode: String {
        infoPlistValue(for: "ALICLOUD_SCHEME_CODE") ?? ""
    }

    static var alicloudAppSecret: String {
        infoPlistValue(for: "ALICLOUD_APP_SECRET") ?? ""
    }

    static var alicloudAuthSdkInfo: String {
        infoPlistValue(for: "ALICLOUD_AUTH_SDK_INFO") ?? ""
    }

    /// 读取 `Info.plist` 中的构建期注入值。
    ///
    /// 返回 `nil` 的三种情况：键不存在、值不是字符串、值是空串或纯空白。
    /// 最后一种最关键 —— `Info.plist` 里写了 `$(SERVER_BASE_URL)` 但 xcconfig 没接上时，
    /// 拿到的是 `""` 而不是 `nil`，调用方的 `??` 兜底会失效。
    private static func infoPlistValue(for key: String) -> String? {
        guard let raw = Bundle.main.infoDictionary?[key] as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 带兜底值的读取：缺配置时显式告警。
    ///
    /// Debug 下直接断言失败（开发期立刻暴露），Release 下只记 error 日志、返回兜底值，
    /// 不因为一个配置项缺失就让线上 App 起不来。
    private static func resolvedValue(for key: String, fallback: String) -> String {
        if let value = infoPlistValue(for: key) {
            return value
        }
        logger.error("""
            缺少构建期配置 \(key, privacy: .public)：\
            Info.plist 中该键不存在或为空。请确认已从 Configs/Secrets.xcconfig.example \
            复制出 Configs/Secrets.xcconfig 并填入真实值。
            """)
        assertionFailure("缺失构建期配置：\(key)")
        return fallback
    }
}
