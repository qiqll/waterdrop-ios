import SwiftUI
import UIKit

/// 提醒列表（F-012 ⑤ B-3.3）。
///
/// 与 Android `ScheduleListActivity` 一一对应：列表 / 建 / 改 / 启停 / 删。
/// 服务端契约见 `wd_server/docs/api-reference.md` §5。
///
/// ## 五条契约纪律
///
/// 1. **`page` 从 0 开始**（群组那边是 1）—— 传 1 会静默跳过第一页，不报错。
/// 2. **一律按 `body.code` 分支**，HTTP 状态码不可信。
/// 3. **cron 不让用户输入**：只给 ``ScheduleCronPreset`` 预设，客户端永远不构造、
///    不解析 cron（决议 2：cron 解析全服务端只此一处）。
/// 4. **不接「试响一次」按钮**：`POST /{id}/execute` 只往 `schedule_executions`
///    记一条历史、**不产生任何通知**，接到「测试提醒」上是骗用户。
/// 5. **状态只读 `enabled`、时间只读 `nextExecutionAt`**，不读派生的 `taskStatus`。
struct ScheduleListView: View {
    /// F-017 §3.4（D5）：工具栏语音按钮退出本页后回到主页
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ScheduleListViewModel()

    /// 编辑目标。`nil` = 新建 —— 两者字段完全相同，共用一个表单。
    @State private var editingSchedule: ScheduleResponse?
    @State private var showDeleteConfirm = false
    @State private var pendingDelete: ScheduleResponse?

    /// 权限状态**查过之后**才敢显示提示条：初值是 `false`，
    /// 不设这个闸门的话已授权的用户每次进页面都会闪一下「通知没开」。
    @State private var authorizationChecked = false

    @State private var titleInput = ""
    @State private var descInput = ""
    @State private var taskTypeIndex = 0
    @State private var cronIndex = 0

    /// 与 Android `ScheduleListActivity` 及服务端校验一致。
    private static let titleMaxLength = 50
    private static let descMaxLength = 200

    var body: some View {
        ZStack {
            ThemeManager.shared.palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // ⚠️ 通知被拒时必须显式告知（B-3.2）：iOS 上没授权时
                // `UNUserNotificationCenter.add` 照样返回成功，通知却永远不响 ——
                // 不说的话，用户是几天后发现提醒没响才知道的。
                if authorizationChecked && !viewModel.notificationsAuthorized {
                    permissionBanner
                }
                content
            }

            VStack {
                Spacer()
                actionButton(title: "新建提醒", icon: "plus") {
                    beginCreate()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("提醒")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // F-017 §3.4（决策 D5）：语音入口常驻。
                // iOS 这里用导航栏按钮而非浮动按钮 —— 三个列表页的底部都已有内容
                // （群组/提醒是横向操作按钮、物品是撤销提示条），浮动按钮会遮挡。
                // 语义相同：不必退回主页就能开口。
                Button {
                    VoiceEntryBus.shared.postStartListening()
                    dismiss()
                } label: {
                    Image(systemName: "mic")
                }
                .accessibilityLabel("用语音记录或查找物品")
            }
        }

        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 首次进入本页才请求通知权限（不在启动时弹，见 ScheduleListViewModel）
            await viewModel.requestNotificationAuthorizationIfNeeded()
            authorizationChecked = true
            await viewModel.loadSchedules()
        }
        .onAppear {
            // 从系统设置改完权限回来，提示条要立刻反映真实状态
            Task {
                await viewModel.refreshAuthorizationState()
                authorizationChecked = true
            }
        }
        .sheet(isPresented: $viewModel.showEditor) { editorSheet }
        .alert(viewModel.noticeTitle, isPresented: $viewModel.showNotice) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(viewModel.noticeMessage)
        }
        .alert("删除提醒", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                guard let target = pendingDelete else { return }
                pendingDelete = nil
                Task { await viewModel.deleteSchedule(target) }
            }
        } message: {
            Text("确定要删除「\(pendingDelete?.displayTitle ?? "")」吗？删除后无法恢复。")
        }
    }

    // MARK: - 权限提示条

    /// B-3.2 的硬性要求：**不能静默**。
    ///
    /// 深链到系统设置 —— iOS 没有「再问一次」的 API，用户拒过一次之后
    /// 只能由用户自己去设置里开，App 唯一能做的是把入口递过去。
    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.wd(.bodyMedium))
            Text("通知权限未开启，提醒到点不会响。点此去系统设置里打开。")
                .font(.wd(.bodySmall))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.wd(.labelMedium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(ThemeManager.shared.palette.semanticWarningBg)
        .foregroundStyle(ThemeManager.shared.palette.semanticWarning)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }
    }

    // MARK: - 列表三态

    @ViewBuilder
    private var content: some View {
        switch viewModel.listState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .empty:
            emptyState

        case .failed:
            failedState

        case .loaded:
            List {
                ForEach(viewModel.schedules) { schedule in
                    ScheduleRowView(schedule: schedule)
                        .contentShape(Rectangle())
                        .onTapGesture { beginEdit(schedule) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = schedule
                                showDeleteConfirm = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                Task { await viewModel.toggleSchedule(schedule) }
                            } label: {
                                Label(
                                    schedule.isEnabled ? "停用" : "启用",
                                    systemImage: schedule.isEnabled ? "pause.circle" : "play.circle"
                                )
                            }
                            .tint(ThemeManager.shared.palette.primary)
                        }
                        .listRowBackground(ThemeManager.shared.palette.surface)
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await viewModel.loadSchedules() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.badge")
                .font(.wdHero(size: 48))
                .foregroundStyle(ThemeManager.shared.palette.neutral400)
            Text("还没有提醒")
                .font(.wd(.titleLarge, weight: .medium))
                .foregroundStyle(ThemeManager.shared.palette.neutral700)
            Text("建一条提醒，到点会在这台设备上通知你")
                .font(.wd(.bodyMedium))
                .foregroundStyle(ThemeManager.shared.palette.neutral500)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.wdHero(size: 44))
                .foregroundStyle(ThemeManager.shared.palette.neutral400)
            Text("提醒加载失败")
                .font(.wd(.bodyLarge, weight: .medium))
                .foregroundStyle(ThemeManager.shared.palette.neutral700)
            Button("重试") {
                Task { await viewModel.loadSchedules() }
            }
            .font(.wd(.bodyLarge, weight: .medium))
            .foregroundStyle(ThemeManager.shared.palette.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 编辑器

    private var isEditing: Bool { editingSchedule != nil }

    private var editorSheet: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("标题（最多 \(Self.titleMaxLength) 字）", text: $titleInput)
                    TextField("描述（选填，最多 \(Self.descMaxLength) 字）", text: $descInput, axis: .vertical)
                        .lineLimit(2...3)
                }

                Section("任务类型") {
                    Picker("任务类型", selection: $taskTypeIndex) {
                        ForEach(Array(ScheduleTaskType.all.enumerated()), id: \.offset) { index, type in
                            Text(ScheduleTaskType.label(type) ?? type).tag(index)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Picker("提醒时间", selection: $cronIndex) {
                        ForEach(Array(ScheduleCronPreset.all.enumerated()), id: \.offset) { index, preset in
                            Text(preset.label).tag(index)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("提醒时间")
                } footer: {
                    // 不让用户敲 cron：服务端用 Spring `CronExpression` 校验
                    // （6 段含秒位），手机上既难输入又难理解，敲错就是 400 / 12002。
                    // 从预设里选，客户端就永远不需要构造或解析 cron。
                    Text("下次提醒时间由服务端计算，保存后生效。")
                }
            }
            .navigationTitle(isEditing ? "编辑提醒" : "新建提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { viewModel.showEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { submitEditor() }
                        .disabled(viewModel.isSubmitting || trimmedTitle.isEmpty)
                }
            }
        }
    }

    private var trimmedTitle: String {
        titleInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func beginCreate() {
        editingSchedule = nil
        titleInput = ""
        descInput = ""
        // 默认「自定义」—— 用户新建时通常没有现成类型可用
        taskTypeIndex = ScheduleTaskType.all.count - 1
        cronIndex = 0
        viewModel.showEditor = true
    }

    private func beginEdit(_ schedule: ScheduleResponse) {
        editingSchedule = schedule
        titleInput = schedule.title ?? ""
        descInput = schedule.description ?? ""
        // 存量数据里的未知类型找不到下标 —— 退到「自定义」而不是越界崩掉
        taskTypeIndex = ScheduleTaskType.all.firstIndex(of: schedule.taskType ?? "")
            ?? ScheduleTaskType.all.count - 1
        cronIndex = ScheduleCronPreset.index(of: schedule.cronExpression)
        viewModel.showEditor = true
    }

    /// 先关表单再发请求。
    ///
    /// ⚠️ 顺序不能反：失败提示（`viewModel.showNotice`）挂在**外层视图**上，
    /// 而表单还盖着的时候它弹不出来 —— 用户会看到「保存」按了没反应。
    /// 代价是失败时输入不保留，但提示里会说清原因，用户重填一次即可。
    private func submitEditor() {
        let title = String(trimmedTitle.prefix(Self.titleMaxLength))
        let desc = String(descInput.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.descMaxLength))
        let taskType = ScheduleTaskType.all[taskTypeIndex]
        let cron = ScheduleCronPreset.all[cronIndex].cron
        let existing = editingSchedule

        viewModel.showEditor = false

        Task {
            if let existing {
                await viewModel.updateSchedule(
                    existing,
                    title: title,
                    description: desc,
                    taskType: taskType,
                    cronExpression: cron
                )
            } else {
                await viewModel.createSchedule(
                    title: title,
                    description: desc,
                    taskType: taskType,
                    cronExpression: cron
                )
            }
        }
    }

    // MARK: - 底部按钮

    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.wd(.labelLarge, weight: .semibold))
                Text(title).font(.wd(.bodyLarge, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(ThemeManager.shared.palette.primary)
            .foregroundStyle(ThemeManager.shared.palette.onPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(viewModel.isSubmitting)
        .opacity(viewModel.isSubmitting ? 0.6 : 1)
    }
}

// MARK: - 列表行

/// 提醒列表行。
///
/// ⭐ 开关看 `enabled`（**不看派生的 `taskStatus`**，它恒等于 `enabled`，
/// 读它会在将来某次服务端改动后静默失灵）。
///
/// 「下次提醒」为 `nil` 有两种可能（已停用 / cron 已无下次触发），
/// 两种都显示「已停顿」，**不装作有下次时间**。
private struct ScheduleRowView: View {
    let schedule: ScheduleResponse

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: schedule.isEnabled ? "bell.fill" : "bell.slash")
                .font(.wd(.titleLarge))
                .foregroundStyle(schedule.isEnabled
                    ? ThemeManager.shared.palette.primary
                    : ThemeManager.shared.palette.neutral400)
                .frame(width: 40, height: 40)
                .background(ThemeManager.shared.palette.primaryLight)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(schedule.displayTitle)
                        .font(.wd(.titleMedium, weight: .medium))
                        .foregroundStyle(ThemeManager.shared.palette.neutral800)
                        .lineLimit(1)

                    if let taskTypeLabel = schedule.taskTypeLabel {
                        Text(taskTypeLabel)
                            .font(.wd(.labelSmall, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ThemeManager.shared.palette.primaryLight)
                            .foregroundStyle(ThemeManager.shared.palette.primary)
                            .clipShape(Capsule())
                    }
                }

                if let description = schedule.description, !description.isEmpty {
                    Text(description)
                        .font(.wd(.bodySmall))
                        .foregroundStyle(ThemeManager.shared.palette.neutral500)
                        .lineLimit(1)
                }

                // 频率与下次时间**合成一行**（F-017-screens §04：
                // 「每月 1 日 09:00 · 下次 10 月 1 日 09:00」）。
                // 分两行时它们看着像两个独立信息，实际是同一件事的两面 ——
                // 「多久一次」和「下次什么时候」。
                //
                // cron 只展示，不给用户看字面量 —— 优先预设的中文说明，
                // 存量自造 cron 回退显示原文（不隐藏，否则用户以为这条没排期）
                Text("\(schedule.cronLabel) · \(nextRunText)")
                    .font(.wd(.bodySmall))
                    .foregroundStyle(schedule.nextExecutionAt?.isEmpty == false
                        ? ThemeManager.shared.palette.neutral600
                        : ThemeManager.shared.palette.neutral400)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // 状态徽章（F-017-screens §04）。
            //
            // 此前只用 `opacity(0.55)` 表示停用 —— 那对色弱用户、或强光下的屏幕
            // 都不可靠，而且**说不清是「停用」还是「不可用」**。
            // 设计稿要求明确的文字标签，这里照做，并存留透明度作为辅助。
            Text(schedule.isEnabled ? "已启用" : "已停用")
                .font(.wd(.labelMedium, weight: .medium))
                .foregroundStyle(schedule.isEnabled
                    ? ThemeManager.shared.palette.primary
                    : ThemeManager.shared.palette.neutral500)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(schedule.isEnabled
                    ? ThemeManager.shared.palette.primaryLight
                    : ThemeManager.shared.palette.surfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.vertical, 4)
        .opacity(schedule.isEnabled ? 1 : 0.75)
    }

    /// `nextExecutionAt` 是 ISO 格式（`2026-09-19T09:00:00`，**带 `T`、不带时区后缀**），
    /// 跟 `JSONDecoder` 的默认策略解不出来，所以复用 ``ScheduleReminderManager``
    /// 那份 formatter。解析失败原样显示，**绝不抛异常崩掉列表**。
    private var nextRunText: String {
        guard let raw = schedule.nextExecutionAt, !raw.isEmpty else {
            return "已停顿"
        }
        guard let date = ScheduleReminderManager.parseServerDate(raw) else {
            return raw
        }
        return "下次 " + Self.displayFormatter.string(from: date)
    }

    /// 展示用 `09-19 09:00`。省掉年份 —— 提醒都在近期，年份是噪音。
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
