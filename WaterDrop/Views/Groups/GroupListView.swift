import SwiftUI

/// 群组列表（F-012 ④ B-3.2）。
///
/// 与 Android `GroupListActivity` 一一对应：我的群组列表 → 建组 / 入群 / 进群详情。
/// 服务端契约见 `wd_server/docs/api-reference.md` §4。
struct GroupListView: View {
    /// F-017 §3.4（D5）：工具栏语音按钮退出本页后回到主页
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = GroupListViewModel()
    @State private var selectedGroup: GroupResponse?

    @State private var createName = ""
    @State private var createDesc = ""
    @State private var joinCode = ""

    /// 名称 50 字、描述 200 字 —— 与 Android `GroupListActivity` 及服务端校验一致。
    private static let nameMaxLength = 50
    private static let descMaxLength = 200
    /// 邀请码固定 8 位。
    private static let codeMaxLength = 8

    var body: some View {
        ZStack {
            ThemeManager.shared.palette.background.ignoresSafeArea()

            content

            VStack {
                Spacer()
                HStack(spacing: 12) {
                    actionButton(title: "创建群组", icon: "plus") {
                        createName = ""
                        createDesc = ""
                        viewModel.showCreateDialog = true
                    }
                    actionButton(title: "加入群组", icon: "person.badge.plus") {
                        joinCode = ""
                        viewModel.showJoinDialog = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("我的群组")
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
        .navigationDestination(item: $selectedGroup) { group in
            GroupDetailView(groupId: group.id ?? "", placeholderName: group.name ?? "")
        }
        .task {
            await viewModel.loadGroups()
        }
        // 从详情页返回时刷新：可能刚退群或把群删了，列表要跟着变
        .onChange(of: selectedGroup) { _, group in
            if group == nil {
                Task { await viewModel.loadGroups() }
            }
        }
        .alert("创建群组", isPresented: $viewModel.showCreateDialog) {
            TextField("群组名称（最多 50 字）", text: $createName)
            TextField("群组描述（选填，最多 200 字）", text: $createDesc)
            Button("取消", role: .cancel) {}
            Button("创建") {
                Task {
                    await viewModel.createGroup(
                        name: String(createName.prefix(Self.nameMaxLength)),
                        description: String(createDesc.prefix(Self.descMaxLength))
                    )
                }
            }
        } message: {
            Text("创建后你就是群主，可以把物品共享给群成员")
        }
        .alert("加入群组", isPresented: $viewModel.showJoinDialog) {
            TextField("请输入 8 位邀请码", text: $joinCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("取消", role: .cancel) {}
            Button("加入") {
                Task { await viewModel.joinGroup(inviteCode: joinCode) }
            }
        }
        .alert(viewModel.noticeTitle, isPresented: $viewModel.showNotice) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(viewModel.noticeMessage)
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
                ForEach(viewModel.groups) { group in
                    GroupRowView(group: group)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedGroup = group }
                        .listRowBackground(ThemeManager.shared.palette.surface)
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await viewModel.loadGroups() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.wdHero(size: 48))
                .foregroundStyle(ThemeManager.shared.palette.neutral400)
            Text("还没有群组")
                .font(.wd(.titleLarge, weight: .medium))
                .foregroundStyle(ThemeManager.shared.palette.neutral700)
            Text("创建一个群组，或输入邀请码加入别人的群组")
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
            Text("群组加载失败")
                .font(.wd(.bodyLarge, weight: .medium))
                .foregroundStyle(ThemeManager.shared.palette.neutral700)
            Button("重试") {
                Task { await viewModel.loadGroups() }
            }
            .font(.wd(.bodyLarge, weight: .medium))
            .foregroundStyle(ThemeManager.shared.palette.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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

/// 群组列表行。角色徽标读 `myRole`（``GroupRole``）—— 非成员返回 nil 时整块隐藏，
/// 不做「成员」占位。
private struct GroupRowView: View {
    let group: GroupResponse

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.wd(.titleLarge))
                .foregroundStyle(ThemeManager.shared.palette.primary)
                .frame(width: 40, height: 40)
                .background(ThemeManager.shared.palette.primaryLight)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(group.name ?? "未命名群组")
                        .font(.wd(.titleMedium, weight: .medium))
                        .foregroundStyle(ThemeManager.shared.palette.neutral800)
                        .lineLimit(1)

                    if let role = GroupRole.label(group.myRole) {
                        Text(role)
                            .font(.wd(.labelSmall, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ThemeManager.shared.palette.primaryLight)
                            .foregroundStyle(ThemeManager.shared.palette.primary)
                            .clipShape(Capsule())
                    }
                }

                if let description = group.description, !description.isEmpty {
                    Text(description)
                        .font(.wd(.bodySmall))
                        .foregroundStyle(ThemeManager.shared.palette.neutral500)
                        .lineLimit(1)
                }

                Text(memberCountText)
                    .font(.wd(.bodySmall))
                    .foregroundStyle(ThemeManager.shared.palette.neutral400)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.wd(.labelMedium))
                .foregroundStyle(ThemeManager.shared.palette.neutral400)
        }
        .padding(.vertical, 4)
    }

    private var memberCountText: String {
        let count = group.memberCount ?? 0
        if let max = group.maxMembers, max > 0 {
            return "\(count) / \(max) 名成员"
        }
        return "\(count) 名成员"
    }
}
