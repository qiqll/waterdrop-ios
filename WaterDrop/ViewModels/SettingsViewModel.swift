import Foundation
import os.log

@Observable
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

    private let logger = Logger(subsystem: "com.waterdrop.ios", category: "SettingsViewModel")

    init() {
        self.nickname = UserPreferencesManager.shared.nickname
        self.theme = ThemeManager.shared.currentTheme
        self.fontSize = FontSizeManager.shared.currentFontSize
    }

    func updateNickname(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        nickname = trimmed
        UserPreferencesManager.shared.nickname = trimmed
    }

    func updateTheme(_ newTheme: ThemeManager.Theme) {
        theme = newTheme
        ThemeManager.shared.currentTheme = newTheme
    }

    func updateFontSize(_ newSize: FontSizeManager.FontSize) {
        fontSize = newSize
        FontSizeManager.shared.currentFontSize = newSize
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
}
