import Foundation
import os.log

@Observable
@MainActor
final class SettingsViewModel {
    var nickname: String
    var theme: ThemeManager.Theme
    var fontSize: FontSizeManager.FontSize
    var showNicknameEditor: Bool = false
    var showLogoutConfirm: Bool = false
    var showExportShare: Bool = false
    var showImportPicker: Bool = false
    var exportURL: URL?
    var statusMessage: String = ""
    var showMembership = false

    /// 「会员中心」行右侧的文案。初值即占位符，取到结果后覆盖。
    var membershipEntryValue: String = "加载中…"

    private let logger = Logger(subsystem: "com.waterdrop.ios", category: "SettingsViewModel")

    init() {
        self.nickname = UserPreferencesManager.shared.nickname
        self.theme = ThemeManager.shared.currentTheme
        self.fontSize = FontSizeManager.shared.currentFontSize
    }

    /// F-011 (D-1)：改名 = 本地先写 + 服务端后同步、失败不回滚。
    ///
    /// 对齐 Android `SettingsActivity.updateNickname`：本地立即生效，服务端同步放到
    /// 后台 Task，失败只提示「稍后重试」而不撤销本地值 —— 否则用户改完昵称看到它被
    /// 打回原样，比「已存本地、暂未上云」更糟。
    func updateNickname(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        nickname = trimmed
        UserPreferencesManager.shared.nickname = trimmed
        // 清掉上一次的残留提示，避免重试成功时仍显示旧的失败文案
        statusMessage = ""

        // F-012 ②: 昵称也纳入设置项跨设备同步（dataType = settings_nickname）。
        // 与下面的 PUT /users/profile 不重复：那条走用户资料表，这条走 sync 通道，
        // 二者共用同一个本地值，各自失败互不影响。
        SettingsSyncManager.push()

        Task { @MainActor in
            do {
                let response = try await AuthAPIService.updateProfile(nickname: trimmed)
                if response.code == 200 {
                    logger.info("Nickname synced to server")
                } else {
                    logger.error("Nickname sync business error: \(response.message)")
                    statusMessage = "昵称已保存到本地，服务端同步失败，稍后会自动重试"
                }
            } catch {
                logger.error("Nickname sync failed: \(error.localizedDescription)")
                statusMessage = "昵称已保存到本地，服务端同步失败，稍后会自动重试"
            }
        }
    }

    func updateTheme(_ newTheme: ThemeManager.Theme) {
        theme = newTheme
        ThemeManager.shared.currentTheme = newTheme
        // F-012 ②: 推送策略在 SettingsSyncManager 内部固定为 client_priority。
        SettingsSyncManager.push()
    }

    func updateFontSize(_ newSize: FontSizeManager.FontSize) {
        fontSize = newSize
        FontSizeManager.shared.currentFontSize = newSize
        SettingsSyncManager.push()
    }

    func exportData() async {
        do {
            let url = try await BackupManager.shared.exportData()
            exportURL = url
            showExportShare = true
        } catch {
            logger.error("Export failed: \(error.localizedDescription)")
            statusMessage = "导出失败"
        }
    }

    func importData(from url: URL) async {
        do {
            let count = try await BackupManager.shared.importData(from: url)
            statusMessage = "成功导入 \(count) 件物品"
        } catch {
            logger.error("Import failed: \(error.localizedDescription)")
            statusMessage = "导入失败"
        }
    }

    func logout() async {
        await AuthService.shared.logout()
    }

    /// F-012 ③：会员中心入口的右侧回显。
    ///
    /// 用 `GET /membership/check-premium` 而不是 `/membership/current` —— 前者才是
    /// 「是不是 VIP」的权威判定（额外要求 `memberType == 1` 且 `status == "active"`
    /// 且未过期），`/current` 只要有生效记录就返回正常对象。
    ///
    /// 失败时保留占位符不打扰：用户点进去后 `MembershipView` 会再拉一次完整状态，
    /// 没必要在这里弹错。与 Android `SettingsActivity.setupMembershipEntry` 同策略。
    func loadMembershipEntry() async {
        do {
            let response = try await MembershipAPIService.checkPremium()
            guard response.code == 200 else {
                membershipEntryValue = "免费用户"
                return
            }
            membershipEntryValue = (response.data == true) ? "会员" : "免费用户"
        } catch {
            logger.warning("会员状态回显失败: \(error.localizedDescription)")
        }
    }
}
