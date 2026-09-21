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
                        .foregroundStyle(ThemeManager.shared.palette.neutral600)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    nicknameInput = viewModel.nickname
                    viewModel.showNicknameEditor = true
                }
            }

            // 今日 AI 用量 (F-012 ⑥ / D-7)
            // 纯展示行，不可点 —— 与 Android `activity_settings.xml` 的 ai_usage 卡片同位
            // （在「个人」和「会员中心」之间）。
            Section {
                HStack {
                    Text("今日 AI 用量")
                    Spacer()
                    Text(viewModel.aiUsageEntryValue)
                        .foregroundStyle(ThemeManager.shared.palette.neutral500)
                }
            }

            // Membership (F-012 ③)
            Section {
                HStack {
                    Text("会员中心")
                    Spacer()
                    Text(viewModel.membershipEntryValue)
                        .foregroundStyle(ThemeManager.shared.palette.neutral500)
                    Image(systemName: "chevron.right")
                        .font(.wd(.labelMedium))
                        .foregroundStyle(ThemeManager.shared.palette.neutral400)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.showMembership = true
                }
            }

            // Groups (F-012 ④)
            // ⚠️ 这一行是必需的入口：群组页面写好了但没有入口，用户就永远到不了 ——
            // Android B-2.2 踩过同一个坑（页面写完了、不可达）。
            Section {
                HStack {
                    Text("我的群组")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.wd(.labelMedium))
                        .foregroundStyle(ThemeManager.shared.palette.neutral400)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.showGroups = true
                }
            }

            // Reminders (F-012 ⑤)
            // ⚠️ 同样是必需的入口：提醒页写完了没有入口，用户就永远到不了。
            Section {
                HStack {
                    Text("提醒")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.wd(.labelMedium))
                        .foregroundStyle(ThemeManager.shared.palette.neutral400)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.showSchedules = true
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
                .foregroundStyle(ThemeManager.shared.palette.semanticError)
            }

            // Status message
            if !viewModel.statusMessage.isEmpty {
                Section {
                    Text(viewModel.statusMessage)
                        .font(.wd(.bodyMedium))
                        .foregroundStyle(ThemeManager.shared.palette.neutral600)
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $viewModel.showMembership) {
            MembershipView()
        }
        .navigationDestination(isPresented: $viewModel.showGroups) {
            GroupListView()
        }
        .navigationDestination(isPresented: $viewModel.showSchedules) {
            ScheduleListView()
        }
        .task {
            // 两个回显互不依赖，**并发**取 —— 串行会让设置页首屏多等一个网络往返。
            // 两者都是失败静默、失败保留占位符，谁先回来都不影响谁。
            async let membership: Void = viewModel.loadMembershipEntry()
            async let aiUsage: Void = viewModel.loadAiUsage()
            _ = await (membership, aiUsage)
        }
        // 从会员中心返回时 `.task` 不会重跑（SettingsView 一直留在导航栈里），
        // 所以额外盯着导航开关：它翻回 false 就是用户回来了，此时刷新右侧文案 ——
        // 用户刚下单成功的话，这里要立刻从「免费用户」变成「会员」。
        .onChange(of: viewModel.showMembership) { _, isShowing in
            if !isShowing {
                Task { await viewModel.loadMembershipEntry() }
            }
        }
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
