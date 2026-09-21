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

    /// F-012 ④：群组列表的导航开关。Android B-2.2 的教训 —— 页面写完不等于可达，
    /// 入口必须在设置里显式补上，否则用户永远点不到。
    var showGroups = false

    /// F-012 ⑤：提醒列表的导航开关。同上 —— 页面可达才算做完。
    var showSchedules = false

    /// 「会员中心」行右侧的文案。初值即占位符，取到结果后覆盖。
    var membershipEntryValue: String = "加载中…"

    /// F-012 ⑥ (D-7)：「今日 AI 用量」行右侧的文案。占位符与 Android
    /// `activity_settings.xml` 里的 `"—"` 保持一致（**不写「加载中…」** ——
    /// 用量是旁路信息，加载失败时就该停在「—」，而不是把「加载中」永远挂在那里）。
    var aiUsageEntryValue: String = "—"

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

    /// F-012 ⑥ (D-7)：今日 AI 用量回显。对齐 Android `SettingsActivity.setupAiUsage()`。
    ///
    /// 只显示 `"count/limit 次"`，**不显示 `cost`** —— 服务端确实返回了 `cost`（BigDecimal），
    /// 但那是内部计费字段，展示给用户既看不懂也无意义，两端显示口径还不一致。
    ///
    /// 失败静默保留占位符「—」：用量是**旁路信息**，不是用户此行目的。为了它弹错、
    /// 或者一直显示「加载中…」，都比显示「—」更糟。与 `loadMembershipEntry()` 同策略。
    func loadAiUsage() async {
        do {
            let response = try await AiAPIService.getTodayUsage()
            guard response.code == 200, let data = response.data else {
                logger.warning("AI 用量回显业务失败: \(response.message)")
                return
            }
            aiUsageEntryValue = "\(data.count)/\(data.limit) 次"
        } catch {
            logger.warning("AI 用量回显失败: \(error.localizedDescription)")
        }
    }
}
