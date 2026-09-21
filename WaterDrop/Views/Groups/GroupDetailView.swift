import SwiftUI

/// 群组详情（F-012 ④ B-3.2 / B-3.3 / B-3.5）。
///
/// 与 Android `GroupDetailActivity` 一一对应：群组概要、成员列表、邀请码展示/分享/作废、
/// 群内共享物品、退群、删除群组，以及 B-3.5 的「移除成员后提示作废邀请码」。
///
/// ⭐ 本屏**所有**角色相关按钮的显隐都读 `viewModel.myRole` 派生出来的
/// `canManage` / `isOwner` / `canLeave`，不散在子视图里判断 ——
/// 分散判断很容易出现「群主看到了退群按钮」这种不一致。
struct GroupDetailView: View {
    @State private var viewModel: GroupDetailViewModel

    @State private var confirmRevoke = false
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var memberToRemove: GroupMemberResponse?

    @Environment(\.dismiss) private var dismiss

    init(groupId: String, placeholderName: String = "") {
        _viewModel = State(initialValue: GroupDetailViewModel(groupId: groupId, placeholderName: placeholderName))
    }

    var body: some View {
        ZStack {
            ThemeManager.shared.palette.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    inviteSection
                    membersSection
                    groupItemsSection
                    dangerZone
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle(viewModel.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.shouldDismiss) { _, should in
            if should { dismiss() }
        }
        // B-3.3：分享邀请码。系统分享面板复用 SettingsView 里已有的 ShareSheet。
        .sheet(isPresented: Binding(
            get: { viewModel.shareText != nil },
            set: { if !$0 { viewModel.clearShareText() } }
        )) {
            if let text = viewModel.shareText {
                ShareSheet(activityItems: [text])
            }
        }
        .alert(viewModel.noticeTitle, isPresented: $viewModel.showNotice) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(viewModel.noticeMessage)
        }
        .alert("作废邀请码？", isPresented: $confirmRevoke) {
            Button("取消", role: .cancel) {}
            Button("作废", role: .destructive) {
                Task { await viewModel.revokeInviteCode() }
            }
        } message: {
            Text("作废后已发出的邀请码立即失效，群成员可能已经拿到但还没使用。")
        }
        .alert("移出成员？", isPresented: Binding(
            get: { memberToRemove != nil },
            set: { if !$0 { memberToRemove = nil } }
        )) {
            Button("取消", role: .cancel) { memberToRemove = nil }
            Button("移出", role: .destructive) {
                if let member = memberToRemove {
                    Task { await viewModel.removeMember(member) }
                }
                memberToRemove = nil
            }
        } message: {
            if let member = memberToRemove {
                Text("确定要把「\(member.displayName)」移出群组吗？")
            }
        }
        // B-3.5：移出成员后追问作废邀请码 —— 否则被踢的人拿旧码一秒就能回来（缺陷 T）
        .alert("同时作废邀请码？", isPresented: Binding(
            get: { viewModel.pendingRevokePromptName != nil },
            set: { if !$0 { viewModel.clearPendingRevokePrompt() } }
        )) {
            Button("暂不作废", role: .cancel) { viewModel.clearPendingRevokePrompt() }
            Button("同时作废", role: .destructive) {
                viewModel.clearPendingRevokePrompt()
                Task { await viewModel.revokeInviteCode() }
            }
        } message: {
            if let name = viewModel.pendingRevokePromptName {
                Text("「\(name)」已被移出，但原邀请码仍然有效，对方用旧码可以立刻重新加入。是否作废当前邀请码？")
            }
        }
        .alert("退出群组？", isPresented: $confirmLeave) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) {
                Task { await viewModel.leaveGroup() }
            }
        } message: {
            Text("退出后需要新的邀请码才能重新加入「\(viewModel.displayName)」。")
        }
        .alert("删除群组？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await viewModel.deleteGroup() }
            }
        } message: {
            Text("删除「\(viewModel.displayName)」后所有成员都会被移出，且不可恢复。")
        }
    }

    // MARK: - 群组概要

    @ViewBuilder
    private var headerSection: some View {
        switch viewModel.detailState {
        case .loading where viewModel.group == nil:
            HStack {
                ProgressView()
                Text("加载中…")
                    .font(.wd(.bodyMedium))
                    .foregroundStyle(ThemeManager.shared.palette.neutral500)
                Spacer()
            }
            .card()

        case .failed(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(ThemeManager.shared.palette.semanticError)
                Text(message)
                    .font(.wd(.bodyMedium))
                    .foregroundStyle(ThemeManager.shared.palette.semanticError)
                Spacer()
                Button("重试") { Task { await viewModel.loadGroup() } }
                    .font(.wd(.labelLarge, weight: .medium))
                    .foregroundStyle(ThemeManager.shared.palette.primary)
            }
            .card()

        default:
            if let group = viewModel.group {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(group.name ?? "未命名群组")
                            .font(.wd(.titleLarge, weight: .semibold))
                            .foregroundStyle(ThemeManager.shared.palette.neutral800)

                        // 角色徽标读 myRole；非成员为 nil 时整块隐藏
                        if let role = viewModel.roleLabel {
                            Text(role)
                                .font(.wd(.labelSmall, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(ThemeManager.shared.palette.primaryLight)
                                .foregroundStyle(ThemeManager.shared.palette.primary)
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }

                    if let description = group.description, !description.isEmpty {
                        Text(description)
                            .font(.wd(.bodyMedium))
                            .foregroundStyle(ThemeManager.shared.palette.neutral600)
                    }

                    Text(viewModel.memberCountText)
                        .font(.wd(.bodySmall))
                        .foregroundStyle(ThemeManager.shared.palette.neutral500)
                }
                .card()
            }
        }
    }

    // MARK: - 邀请码（B-3.3）

    /// 邀请码区**仅群主/管理员可见** —— 普通成员调该端点是 403，
    /// 与其让用户点出一个必然失败的错误，不如不展示入口。
    @ViewBuilder
    private var inviteSection: some View {
        if viewModel.canManage {
            VStack(alignment: .leading, spacing: 12) {
                Text("邀请码")
                    .font(.wd(.bodyLarge, weight: .medium))
                    .foregroundStyle(ThemeManager.shared.palette.neutral700)

                if let invite = viewModel.invite {
                    Text(invite.inviteCode ?? "")
                        .font(.wdHero(size: 24, weight: .semibold).monospaced())
                        .foregroundStyle(ThemeManager.shared.palette.primary)
                        .textSelection(.enabled)

                    if let expire = invite.expireTime, !expire.isEmpty {
                        // 服务端给的是 `yyyy-MM-dd HH:mm:ss`，原样展示，不做本地重新格式化
                        Text("\(expire) 失效")
                            .font(.wd(.bodySmall))
                            .foregroundStyle(ThemeManager.shared.palette.neutral500)
                    }

                    Text("同一个邀请码在失效前会一直复用，重复获取不会轮换。要让旧码失效请点「作废邀请码」。")
                        .font(.wd(.bodySmall))
                        .foregroundStyle(ThemeManager.shared.palette.neutral500)

                    HStack(spacing: 12) {
                        secondaryButton(title: "分享邀请码", tint: ThemeManager.shared.palette.primary) {
                            viewModel.prepareShare()
                        }
                        secondaryButton(title: "作废邀请码", tint: ThemeManager.shared.palette.semanticError) {
                            confirmRevoke = true
                        }
                    }
                } else {
                    Text("邀请码是别人加入这个群组的唯一凭证。")
                        .font(.wd(.bodySmall))
                        .foregroundStyle(ThemeManager.shared.palette.neutral500)

                    primaryButton(
                        title: viewModel.isInviteLoading ? "生成中…" : "获取邀请码",
                        enabled: !viewModel.isInviteLoading
                    ) {
                        Task { await viewModel.fetchInviteCode() }
                    }
                }
            }
            .card()
        }
    }

    // MARK: - 成员

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("成员")
                .font(.wd(.bodyLarge, weight: .medium))
                .foregroundStyle(ThemeManager.shared.palette.neutral700)

            switch viewModel.membersState {
            case .loading:
                HStack { ProgressView(); Spacer() }

            case .failed(let message):
                // 非成员是 403 / code=8006，文案由服务端给（「非群组成员」），透传更准
                Text(message)
                    .font(.wd(.bodyMedium))
                    .foregroundStyle(ThemeManager.shared.palette.semanticError)

            case .empty:
                Text("暂无成员")
                    .font(.wd(.bodyMedium))
                    .foregroundStyle(ThemeManager.shared.palette.neutral500)

            case .loaded:
                ForEach(viewModel.members) { member in
                    memberRow(member)
                }
            }
        }
        .card()
    }

    private func memberRow(_ member: GroupMemberResponse) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.wd(.headlineLarge))
                .foregroundStyle(ThemeManager.shared.palette.neutral300)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    // nickname 可能为 nil（用户未设资料）—— displayName 已回退「未设置昵称」
                    Text(member.displayName)
                        .font(.wd(.bodyLarge))
                        .foregroundStyle(ThemeManager.shared.palette.neutral800)

                    if viewModel.isSelf(member) {
                        Text("（我）")
                            .font(.wd(.bodySmall))
                            .foregroundStyle(ThemeManager.shared.palette.neutral500)
                    }
                }

                if let role = member.roleLabel {
                    Text(role)
                        .font(.wd(.bodySmall))
                        .foregroundStyle(ThemeManager.shared.palette.neutral500)
                }

                if let joinTime = member.joinTime, !joinTime.isEmpty {
                    Text(joinTime)
                        .font(.wd(.labelSmall))
                        .foregroundStyle(ThemeManager.shared.palette.neutral400)
                }
            }

            Spacer()

            // 移出按钮三条约束：我有管理权 / 不是我自己 / 目标不是群主 —— 判定集中在 VM
            if viewModel.canRemove(member) {
                Button {
                    memberToRemove = member
                } label: {
                    Text("移出")
                        .font(.wd(.labelMedium))
                        .foregroundStyle(ThemeManager.shared.palette.semanticError)
                }
                .disabled(viewModel.isRemoving)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 群内共享物品

    /// 群内共享物品（缺陷 H 的客户端侧）。
    ///
    /// 这是「建群 → 邀请 → 共享物品」整条链的最后一环：没有它，用户能看到群友的名字，
    /// 看不到群友的东西 —— 而看到群友的东西正是共享的全部意义。
    ///
    /// 「谁放的」只读 `ItemDto.userId`（再由 VM 去成员列表比昵称），
    /// **不读 `createBy`** —— 那是手机号（缺陷 V）。
    private var groupItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("群内共享物品")
                .font(.wd(.bodyLarge, weight: .medium))
                .foregroundStyle(ThemeManager.shared.palette.neutral700)

            switch viewModel.groupItemsState {
            case .loading:
                HStack { ProgressView(); Spacer() }

            case .failed(let message):
                // 非成员是 403 / code=8004（与成员列表的 8006、群详情的 8003 都不同）
                Text(message)
                    .font(.wd(.bodyMedium))
                    .foregroundStyle(ThemeManager.shared.palette.semanticError)

            case .empty:
                Text("该群组还没有共享物品")
                    .font(.wd(.bodyMedium))
                    .foregroundStyle(ThemeManager.shared.palette.neutral500)

            case .loaded:
                ForEach(viewModel.groupItems, id: \.id) { item in
                    groupItemRow(item)
                }
            }
        }
        .card()
    }

    private func groupItemRow(_ item: ItemDto) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "cube")
                .font(.wd(.bodyLarge))
                .foregroundStyle(ThemeManager.shared.palette.primary)
                .frame(width: 34, height: 34)
                .background(ThemeManager.shared.palette.primaryLight)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.wd(.bodyLarge))
                    .foregroundStyle(ThemeManager.shared.palette.neutral800)

                HStack(spacing: 6) {
                    if let category = item.category, !category.isEmpty {
                        Text(category)
                            .font(.wd(.bodySmall))
                            .foregroundStyle(ThemeManager.shared.palette.neutral500)
                    }
                    if let location = item.location, !location.isEmpty {
                        Text(location)
                            .font(.wd(.bodySmall))
                            .foregroundStyle(ThemeManager.shared.palette.neutral500)
                    }
                }

                // 归属查不到（成员列表未到 / 那人已退群）就整行隐藏
                if let owner = viewModel.ownerName(of: item) {
                    Text("\(owner) 共享")
                        .font(.wd(.labelSmall))
                        .foregroundStyle(ThemeManager.shared.palette.neutral400)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - 退群 / 删除群组

    /// 只读 `myRole` 派生：群主看到「删除群组」，成员/管理员看到「退出群组」，
    /// 群主**看不到**退群 —— 服务端会拒绝，出口是删除群组。
    @ViewBuilder
    private var dangerZone: some View {
        VStack(spacing: 12) {
            if viewModel.canLeave {
                primaryButton(title: "退出群组", tint: ThemeManager.shared.palette.semanticError) {
                    confirmLeave = true
                }
            }

            if viewModel.isOwner {
                primaryButton(title: "删除群组", tint: ThemeManager.shared.palette.semanticError) {
                    confirmDelete = true
                }

                Text("你是群主，群主不能退群 —— 请使用「删除群组」。")
                    .font(.wd(.bodySmall))
                    .foregroundStyle(ThemeManager.shared.palette.neutral500)
            }
        }
    }

    // MARK: - 按钮

    private func primaryButton(
        title: String,
        tint: Color = ThemeManager.shared.palette.primary,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.wd(.bodyLarge, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(tint)
                .foregroundStyle(ThemeManager.shared.palette.onPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
    }

    private func secondaryButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.wd(.labelLarge, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(ThemeManager.shared.palette.surface)
                .foregroundStyle(tint)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ThemeManager.shared.palette.neutral200, lineWidth: 1)
                )
        }
        .disabled(viewModel.isInviteLoading)
        .opacity(viewModel.isInviteLoading ? 0.6 : 1)
    }
}

// MARK: - 卡片样式

private extension View {
    /// 与会员中心一致的白底卡片：圆角 + 细描边。
    func card() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(ThemeManager.shared.palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(ThemeManager.shared.palette.neutral200, lineWidth: 1)
            )
    }
}
