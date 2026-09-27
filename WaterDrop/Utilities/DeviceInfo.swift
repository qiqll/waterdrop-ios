import UIKit

enum DeviceInfo {
    static var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }

    static var platform: String { "iOS" }

    static var systemVersion: String {
        UIDevice.current.systemVersion
    }

    static var deviceModel: String {
        UIDevice.current.model
    }

    // MARK: - 应用版本（F-018 ②）

    /// 营销版本号，如 `1.0.0`。读 `CFBundleShortVersionString`。
    ///
    /// 这个值来自 Xcode 的 `MARKETING_VERSION`，**发版时会随构建变** ——
    /// 而那正是此前 UA 里硬编码 `1.0` 所缺的性质。
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    /// 构建号，读 `CFBundleVersion`（Xcode 的 `CURRENT_PROJECT_VERSION`）。
    ///
    /// 与 `appVersion` 分开：营销版本是给人看的（1.0.0 → 1.2.0），
    /// 构建号才是每次上传都变的那个。只比对营销版本时，
    /// 一次「同版本号的热修」是看不出来的。
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    /// 上报给服务端的 User-Agent。
    ///
    /// ## 为什么要改（F-018 ②）
    ///
    /// 此前 UA 是**硬编码**的 `"WaterDrop-iOS/1.0"`（见 `APIClient.swift`），
    /// 发版到 1.2 了 UA 里还是 1.0 —— 服务端据此完全无法判断
    /// 「用户在用哪个版本」，而这正是 `min_support_version` 判定所缺的输入。
    ///
    /// 格式与 Android 保持一致（`WaterDrop-Android/{versionName}`），
    /// 服务端 `extractVersionFromUserAgent` 按 `名称/版本` 解析，
    /// 两端同一个解析器就够了。
    static var userAgent: String {
        "WaterDrop-iOS/\(appVersion) (build \(buildNumber))"
    }
}
