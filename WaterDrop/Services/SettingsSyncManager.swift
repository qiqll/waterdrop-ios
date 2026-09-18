import Foundation
import os.log

/// 设置项跨设备同步。
///
/// F-012 ②: 双端上传/下载/状态查询跑通，多设备数据一致。
///
/// ## 同步什么、不同步什么
///
/// 物品数据**不在这里** —— items 的唯一真相源已在服务端，另有完整 REST 链路。
/// 这里同步的是本地独有、原先不上云的设置类数据：昵称 / 主题 / 字体大小。
/// 这正是「多设备数据一致」可被真实验证的形态：
/// 设备 A 改主题 → 设备 B（或清数据后重装）拉到同一主题。
///
/// ## 两个方向，两种策略
///
/// | 时机 | 策略 | 理由 |
/// |------|------|------|
/// | 用户在本机改设置（`push`） | `client_priority` | 用户刚在本机做的选择就是最新意图，必须覆盖服务器 |
/// | 登录后拉取（`pull`） | `server_priority` | 新设备/重装后应以服务器为准，不能拿本机默认值把服务器覆盖掉 |
///
/// 用一个策略包打两边一定错：全是 `client_priority`，重装后的默认值会抹掉服务器上
/// 用户配好的主题；全是 `server_priority`，用户改了设置也推不上去。
///
/// ## 失败一律静默
///
/// 所有方法都不抛异常，失败只记日志。设置同步是**尽力而为**的后台行为：
/// 它失败不该让用户改个主题就弹错误提示 —— 本地值已经写进去了，
/// 下次登录或下次改设置会再推一次。
///
/// 与 Android `SettingsSyncManager.kt` 一一对应，dataType 常量必须逐字一致。
@MainActor
enum SettingsSyncManager {

    private static let logger = Logger(subsystem: "com.yjqi.waterdrop.ios", category: "SettingsSyncManager")

    /// 服务端响应里的服务器数据指纹，存下来供下次 `clientVersion` 用。
    private static let serverVersionKey = "sync_server_version"

    // MARK: - dataType 契约
    //
    // 服务端要求 dataType 匹配 `^[a-z][a-z0-9_]{0,49}$`（小写字母开头，
    // 只含小写字母/数字/下划线）。用 `settings_` 前缀把设置类数据与将来的
    // 其他业务数据区分开，避免撞键。这四个常量与 Android 端必须完全一致。
    private static let typeNickname = "settings_nickname"
    private static let typeTheme = "settings_theme"
    private static let typeFontSize = "settings_font_size"

    // MARK: - Push

    /// 把本机设置整体推到服务器。用户在设置页改完任一项后调用。
    ///
    /// 用 `client_priority`：本机刚改的值就是最新意图。
    ///
    /// 不绑定任何 View 生命周期 —— 它由 `Task` 发起，调用方不必等待；
    /// Android 那边特意为此单独开了一个 scope（`recreate()` 会取消 `lifecycleScope`），
    /// iOS 这边 `Task {}` 本身就不挂在 View 上，天然没有这个坑。
    static func push() {
        Task {
            let payload = readLocalSettings()

            do {
                let response = try await SyncAPIService.sync(
                    clientData: payload,
                    strategy: "client_priority"
                )
                guard response.code == 200 else {
                    logger.warning("推送设置失败: code=\(response.code), message=\(response.message)")
                    return
                }
                if let version = response.data?.syncVersion {
                    saveServerVersion(version)
                }
                logger.info("设置已推送: \(payload.keys.sorted())")
            } catch {
                logger.warning("推送设置异常: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Pull

    /// 从服务器拉取设置并落到本机。登录成功后调用。
    ///
    /// 用 `server_priority`：本机没有的键会被补上，本机已有的键保留服务器的值。
    /// 这样「重装后拿到服务器上配好的主题」，同时「本机新增的 dataType 也不会丢」。
    ///
    /// 服务器上什么都没有时（首次使用的新用户）返回空字典，不做任何本地改动 ——
    /// 不是错误，也**不能**把空结果当成「服务器要求清空本地设置」。
    static func pull() {
        Task {
            do {
                // clientData 必须非空（服务端 @NotNull），传本机设置既是校验需要，
                // 也让 server_priority 顺带把本机独有的新类型补到服务器上。
                let response = try await SyncAPIService.sync(
                    clientData: readLocalSettings(),
                    strategy: "server_priority"
                )
                guard response.code == 200, let data = response.data else {
                    logger.warning("拉取设置失败: code=\(response.code), message=\(response.message)")
                    return
                }

                if let serverData = data.data, !serverData.isEmpty {
                    applyServerSettings(serverData.mapValues(\.value))
                    logger.info("设置已拉取: \(serverData.keys.sorted())")
                } else {
                    // 新用户，服务器还没有他的数据 —— 不是错误，保持本地值
                    logger.info("服务器无设置数据，保持本地值")
                }

                if let version = data.syncVersion {
                    saveServerVersion(version)
                }
            } catch {
                logger.warning("拉取设置异常: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 本地读写

    /// 读取本机设置，转成服务端要的 `dataType -> value` 结构。
    ///
    /// 主题以 Int 发送（与 Android `ThemeManager.THEME_WARM = 0 / THEME_NEUTRAL = 1`
    /// 取值一致），字体大小以字符串发送（`small` / `medium` / `large`）。
    /// 两端取值必须对齐，否则会出现「阿安卓改成暖色、iOS 读到 0 但认不出」这类问题。
    private static func readLocalSettings() -> [String: Any] {
        return [
            typeNickname: UserPreferencesManager.shared.nickname,
            typeTheme: ThemeManager.shared.currentTheme.rawValue,
            typeFontSize: FontSizeManager.shared.currentFontSize.rawValue
        ]
    }

    /// 把服务器返回的设置应用到本机。逐项容错：
    /// 某一项类型不对或值非法时跳过该项，不影响其余项 —— 半个正确的设置也好过整个同步失败。
    private static func applyServerSettings(_ data: [String: Any]) {
        if let nickname = data[typeNickname] as? String, !nickname.isEmpty {
            UserPreferencesManager.shared.nickname = nickname
        }

        // JSON 数字可能解成 Int 也可能解成 Double，统一走 NSNumber 兜住两种形态。
        if let raw = data[typeTheme] as? NSNumber,
           let theme = ThemeManager.Theme(rawValue: raw.intValue) {
            ThemeManager.shared.currentTheme = theme
        }

        if let raw = data[typeFontSize] as? String,
           let size = FontSizeManager.FontSize(rawValue: raw) {
            FontSizeManager.shared.currentFontSize = size
        }
    }

    // MARK: - 服务器指纹

    /// 保存服务器数据指纹。供将来做「进设置页先 checkVersion，无变化就跳过同步」用；
    /// 注意该字段与 App 版本号无关，别混用。
    private static func saveServerVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: serverVersionKey)
    }

    /// 上次同步得到的服务器数据指纹；从未同步过时为 nil。
    static var serverVersion: String? {
        UserDefaults.standard.string(forKey: serverVersionKey)
    }

    /// 退出登录时清掉同步状态，避免换账号后沿用上一个账号的版本指纹。
    static func clearSyncState() {
        UserDefaults.standard.removeObject(forKey: serverVersionKey)
    }
}
