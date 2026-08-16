import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var nicknameInput = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Personal
            Section("个人") {
                HStack {
                    Text("昵称")
                    Spacer()
                    Text(viewModel.nickname)
                        .foregroundStyle(AppColors.neutral600)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    nicknameInput = viewModel.nickname
                    viewModel.showNicknameEditor = true
                }
            }

            // Theme
            Section("主题") {
                Picker("主题风格", selection: Binding(
                    get: { viewModel.theme },
                    set: { viewModel.updateTheme($0) }
                )) {
                    ForEach(ThemeManager.Theme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            }

            // Font size
            Section("字体大小") {
                Picker("字体大小", selection: Binding(
                    get: { viewModel.fontSize },
                    set: { viewModel.updateFontSize($0) }
                )) {
                    ForEach(FontSizeManager.FontSize.allCases, id: \.self) { size in
                        Text(size.displayName).tag(size)
                    }
                }
            }

            // Data management
            Section("数据管理") {
                Button("导出数据") {
                    Task { await viewModel.exportData() }
                }

                Button("导入数据") {
                    viewModel.showImportPicker = true
                }
            }

            // Logout
            Section {
                Button("退出登录") {
                    viewModel.showLogoutConfirm = true
                }
                .foregroundStyle(AppColors.semanticError)
            }

            // Status message
            if !viewModel.statusMessage.isEmpty {
                Section {
                    Text(viewModel.statusMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.neutral600)
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .alert("修改昵称", isPresented: $viewModel.showNicknameEditor) {
            TextField("输入昵称", text: $nicknameInput)
            Button("确定") {
                viewModel.updateNickname(nicknameInput)
            }
            Button("取消", role: .cancel) {}
        }
        .alert("确认退出", isPresented: $viewModel.showLogoutConfirm) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) {
                Task {
                    await viewModel.logout()
                }
            }
        } message: {
            Text("确定要退出登录吗？")
        }
        .sheet(isPresented: $viewModel.showExportShare) {
            if let url = viewModel.exportURL {
                ShareSheet(activityItems: [url])
            }
        }
        .fileImporter(
            isPresented: $viewModel.showImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await viewModel.importData(from: url) }
            }
        }
    }
}

// MARK: - Share Sheet wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
