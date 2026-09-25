import Foundation
import os.log

/// 群组详情视图模型（F-012 ④ B-3.2 / B-3.3 / B-3.5）。
///
/// 与 Android `GroupDetailActivity` 一一对应：群组概要 / 成员列表 / 邀请码 / 群内共享物品 /
/// 退群 / 删除群组，外加 B-3.5 的「移除成员后提示作废邀请码」。
///
/// ## ⭐ 角色按钮显隐一律读 `myRole`
///
/// `1`-群主 `2`-管理员 `3`-成员（``GroupRole``）。**不要**试图从响应里找 `inviteCode`
/// 来判断权限 —— 缺陷 S 已经把它从群组响应里彻底拿掉了，那个隐式信号不存在。
///
/// ## 三条容易踩的契约约束
///
/// - 移除成员的路径参数是 **`userId` 不是 `memberId`**。
/// - 非成员访问**三个端点三种码**：群详情 `403/8003`、群内物品 `403/8004`、
///   成员列表 `403/8006`。所以一律按 `body.code` 分支，文案透传服务端的。
/// - 群内物品返回的是**裸 `Item` 实体**，含 `createBy` / `updateBy` ——
///   那是**手机号**（缺陷 V）。「谁放的」只读 `userId` 再回成员列表比昵称。
///
/// 本类刻意不 `import UIKit`：分享与系统弹窗交回视图层，逻辑保持可测。
@Observable
@MainActor
final class GroupDetailViewModel {

    /// 通用三态（成员列表与群内物品各用一份）。
    enum SectionState {
        case loading
        case loaded
        case empty
        case failed(String)
    }

    let groupId: String

    // MARK: - 群组概要

    /// 群组概要。接口回来之前为 nil —— 底部按钮的显隐完全依赖它，
    /// 所以显隐判定集中在 ``isOwner`` / ``canManage`` 两个计算属性上，不散在视图里。
    private(set) var group: GroupResponse?
    private(set) var detailState: SectionState = .loading
    /// 从列表页带过来的群名，用于加载期间占位，避免标题空白闪一下。
    private(set) var placeholderName: String

    // MARK: - 成员

    private(set) var members: [GroupMemberResponse] = []
    private(set) var membersState: SectionState = .loading

    /// 当前登录用户 id，用于「不给自己显示移出按钮」。
    private let currentUserId: String?

    // MARK: - 群内共享物品

    private(set) var groupItems: [ItemDto] = []
    private(set) var groupItemsState: SectionState = .loading

    // MARK: - 邀请码（B-3.3）

    /// 已取到的邀请码。仅群主/管理员会取 —— 普通成员调该端点是 403。
    private(set) var invite: GroupInviteCodeResponse?
    private(set) var isInviteLoading = false

    // MARK: - 在途状态

    private(set) var isRemoving = false
    private(set) var isLeaving = false

    private(set) var noticeTitle = ""
    private(set) var noticeMessage = ""
    var showNotice = false

    /// 需要交给系统分享面板的文本（邀请码）。视图看到它非 nil 就弹 `ShareSheet`。
    private(set) var shareText: String?

    /// 移除成员成功后是否要追问作废邀请码（B-3.5）。非 nil 即为被移出者的昵称。
    private(set) var pendingRevokePromptName: String?

    /// 群已解散/已退出，视图据此收栈返回上一页。
    var shouldDismiss = false

    private let logger = Logger(subsystem: "com.yjhome.waterdrop.ios", category: "GroupDetailViewModel")

    /// 群组上限 50 人，一次拉够。
    private static let memberPageSize = 100

    init(groupId: String, placeholderName: String = "") {
        self.groupId = groupId
        self.placeholderName = placeholderName
        self.currentUserId = AuthStateManager.shared.getCurrentUserId()
    }

    // MARK: - 派生状态

    var displayName: String { group?.name ?? placeholderName }

    var roleLabel: String? { GroupRole.label(group?.myRole) }

    /// 已入群（拿到 `myRole` 就是）。退群入口据此显隐。
    var isMember: Bool { group?.myRole != nil }

    var isOwner: Bool { group?.myRole == GroupRole.owner }

    /// 群主或管理员。邀请码区、成员行的移出按钮都看它。
    var canManage: Bool { group?.canManage ?? false }

    /// 群主不提供退群入口 —— 服务端会拒绝，群主的出口是删除群组。
    var canLeave: Bool { isMember && !isOwner }

    /// 成员数量文案：服务端给了 `maxMembers` 才显示 `n / m`。
    var memberCountText: String {
        let current = group?.memberCount ?? 0
        let base: String
        if let max = group?.maxMembers, max > 0 {
            base = "\(current) / \(max) 名成员"
        } else {
            base = "\(current) 名成员"
        }

        // 共享物品数（F-017 §15.9）。
        //
        // 与列表项的取舍**故意不同**：列表里为 0 就不显示（扫视用的行，
        // 多一个恒为 0 的字段只会稀释成员数）；详情页是「看全貌」的地方，
        // 0 必须显示 —— 用户来这里就是要知道这个群到底有没有东西。
        // 只有服务端没返回（nil，如旧版本服务端）才不拼。
        guard let items = group?.itemCount else { return base }
        return "\(base) · \(items) 件共享物品"
    }

    /// `userId -> 昵称`，来自成员列表。
    private var memberNames: [String: String] {
        var map: [String: String] = [:]
        for member in members {
            if let userId = member.userId { map[userId] = member.displayName }
        }
        return map
    }

    /// 物品所有者的昵称。
    ///
    /// ⚠️ **由 `userId` 在成员列表里查出**，不是从 `ItemDto.createBy` 取的 ——
    /// 那是手机号（缺陷 V）。nil 表示查不到（成员列表还没到 / 那人已退群），此时整行隐藏。
    func ownerName(of item: ItemDto) -> String? {
        guard let userId = item.userId else { return nil }
        return memberNames[userId]
    }

    /// 能否把某成员移出：我有管理权 且 不是我自己 且 对方不是群主。
    func canRemove(_ member: GroupMemberResponse) -> Bool {
        guard canManage, member.role != GroupRole.owner else { return false }
        if let userId = member.userId, userId == currentUserId { return false }
        return true
    }

    func isSelf(_ member: GroupMemberResponse) -> Bool {
        guard let userId = member.userId, let currentUserId else { return false }
        return userId == currentUserId
    }

    // MARK: - 加载

    /// 首次进入：三个请求并发拉。
    func load() async {
        async let detail: Void = loadGroup()
        async let members: Void = loadMembers()
        async let items: Void = loadGroupItems()
        _ = await (detail, members, items)
    }

    /// 群组概要（`GET /groups/{groupId}`）。
    ///
    /// 非成员是 `403 / code=8003`（成员列表是 8006、群内物品是 8004，三个码不同）。
    func loadGroup() async {
        do {
            let response = try await GroupAPIService.getGroup(groupId: groupId)
            guard response.code == 200, let data = response.data else {
                detailState = .failed(response.message)
                return
            }
            group = data
            detailState = .loaded
        } catch {
            logger.error("群组详情加载失败: \(error.localizedDescription)")
            detailState = .failed("群组加载失败")
        }
    }

    /// 成员列表（`GET /groups/{groupId}/members`）。非成员是 `403 / code=8006`。
    func loadMembers() async {
        do {
            let response = try await GroupAPIService.getMembers(groupId: groupId, page: 1, size: Self.memberPageSize)
            guard response.code == 200 else {
                // 文案透传服务端的（如「非群组成员」），比自造准确
                membersState = .failed(response.message)
                return
            }
            let list = response.data?.records ?? []
            members = list
            membersState = list.isEmpty ? .empty : .loaded
            // 「谁放的」靠成员列表解析昵称，所以成员一到就重算物品行的归属
            refreshItemOwners()
        } catch {
            logger.error("成员列表加载失败: \(error.localizedDescription)")
            membersState = .failed("群组加载失败")
        }
    }

    /// 群内共享物品（`GET /items/group/{groupId}`）。**非分页**，直接 `[ItemDto]`。
    ///
    /// 非成员是 `403 / code=8004`。这条读取路径是缺陷 H 的客户端侧：
    /// 服务端路由 2026-09-19 才补上，客户端此前没有任何入口调用它 ——
    /// 于是「建群 → 邀请 → 共享物品」走到最后一步仍是断的：能看到群友的名字，
    /// 看不到群友的东西。而看到群友的物品正是共享的全部意义。
    func loadGroupItems() async {
        do {
            let response = try await GroupAPIService.getGroupItems(groupId: groupId)
            guard response.code == 200 else {
                groupItemsState = .failed(response.message)
                return
            }
            let list = response.data ?? []
            groupItems = list
            groupItemsState = list.isEmpty ? .empty : .loaded
        } catch {
            logger.error("群内共享物品加载失败: \(error.localizedDescription)")
            groupItemsState = .failed("共享物品加载失败")
        }
    }

    /// 成员列表更新后触发一次归属重算。
    ///
    /// `groupItems` 本身没变，但它依赖的 `memberNames` 变了，而 SwiftUI 观察不到
    /// 计算属性的输入变化 —— 所以这里把数组重新赋值，强制视图刷新。
    private func refreshItemOwners() {
        guard !groupItems.isEmpty else { return }
        groupItems = groupItems
    }

    // MARK: - 邀请码（B-3.3）

    /// 取邀请码（`GET /groups/{groupId}/invite-code`）。仅群主/管理员。
    ///
    /// ⚠️ 服务端对**未过期的码直接复用，不会轮换** —— 反复点「获取」不会把已经
    /// 分享出去的码作废。要让旧码失效必须走 ``revokeInviteCode()``。
    func fetchInviteCode() async {
        guard !isInviteLoading else { return }
        isInviteLoading = true
        defer { isInviteLoading = false }

        do {
            let response = try await GroupAPIService.getInviteCode(groupId: groupId)
            guard response.code == 200, let data = response.data else {
                presentNotice(title: "获取失败", message: response.message)
                return
            }
            invite = data
        } catch {
            logger.error("获取邀请码失败: \(error.localizedDescription)")
            presentNotice(title: "获取失败", message: "网络不可用，请检查网络后重试")
        }
    }

    /// 作废邀请码（`DELETE /groups/{groupId}/invite-code`）。
    ///
    /// 破坏性操作 —— 已经发出去、对方还没填的码会被一并废掉，所以视图层必须先弹确认。
    func revokeInviteCode() async {
        guard !isInviteLoading else { return }
        isInviteLoading = true
        defer { isInviteLoading = false }

        do {
            let response = try await GroupAPIService.revokeInviteCode(groupId: groupId)
            guard response.code == 200 else {
                presentNotice(title: "作废失败", message: response.message)
                return
            }
            invite = nil
            presentNotice(title: "已作废", message: "邀请码已作废")
        } catch {
            logger.error("作废邀请码失败: \(error.localizedDescription)")
            presentNotice(title: "作废失败", message: "网络不可用，请检查网络后重试")
        }
    }

    /// 生成分享文案（B-3.3）。
    ///
    /// 到期时间原样使用服务端给的 `yyyy-MM-dd HH:mm:ss`，不做本地重新格式化 ——
    /// 转 `Date` 还得多配一个 formatter，且服务端改格式时前端会静默显示空白。
    func prepareShare() {
        guard let code = invite?.inviteCode, !code.isEmpty else {
            presentNotice(title: "还没有邀请码", message: "请先获取邀请码")
            return
        }
        let name = group?.name ?? placeholderName
        if let expire = invite?.expireTime, !expire.isEmpty {
            shareText = "邀请你加入「\(name)」\n邀请码：\(code)\n（\(expire) 前有效）"
        } else {
            shareText = "邀请你加入「\(name)」\n邀请码：\(code)"
        }
    }

    func clearShareText() { shareText = nil }

    // MARK: - 移除成员 + B-3.5

    /// 移出成员（`DELETE /groups/{groupId}/members/{userId}`）。
    ///
    /// ⚠️ 路径参数传 `member.userId`，**不是** `member.id`（那是 `group_members` 主键，
    /// 传它会移错人）。
    func removeMember(_ member: GroupMemberResponse) async {
        guard let userId = member.userId, !userId.isEmpty else { return }
        guard !isRemoving else { return }
        isRemoving = true
        defer { isRemoving = false }

        do {
            let response = try await GroupAPIService.removeMember(groupId: groupId, userId: userId)
            guard response.code == 200 else {
                presentNotice(title: "移出失败", message: response.message)
                return
            }
            // 成员数与物品归属都会变，两个都重拉
            await loadMembers()
            await loadGroup()
            // B-3.5：群主/管理员才有必要提示
            if canManage {
                pendingRevokePromptName = member.displayName
            }
        } catch {
            logger.error("移出成员失败: \(error.localizedDescription)")
            presentNotice(title: "移出失败", message: "网络不可用，请检查网络后重试")
        }
    }

    func clearPendingRevokePrompt() { pendingRevokePromptName = nil }

    // MARK: - 退群 / 删除群组

    /// 退群（`POST /groups/{groupId}/leave`）。
    ///
    /// ⚠️ 群主不能退群 —— 视图层不该给群主展示这个按钮（见 ``canLeave``）。
    func leaveGroup() async {
        guard !isLeaving else { return }
        isLeaving = true
        defer { isLeaving = false }

        do {
            let response = try await GroupAPIService.leaveGroup(groupId: groupId)
            guard response.code == 200 else {
                presentNotice(title: "退出失败", message: response.message)
                return
            }
            presentNotice(title: "已退出", message: "已退出群组")
            shouldDismiss = true
        } catch {
            logger.error("退出群组失败: \(error.localizedDescription)")
            presentNotice(title: "退出失败", message: "网络不可用，请检查网络后重试")
        }
    }

    /// 删除群组（`DELETE /groups/{groupId}`）。仅群主，**不可逆**。
    func deleteGroup() async {
        guard !isLeaving else { return }
        isLeaving = true
        defer { isLeaving = false }

        do {
            let response = try await GroupAPIService.deleteGroup(groupId: groupId)
            guard response.code == 200 else {
                presentNotice(title: "删除失败", message: response.message)
                return
            }
            presentNotice(title: "已删除", message: "群组已删除")
            shouldDismiss = true
        } catch {
            logger.error("删除群组失败: \(error.localizedDescription)")
            presentNotice(title: "删除失败", message: "网络不可用，请检查网络后重试")
        }
    }

    // MARK: - 弹窗

    private func presentNotice(title: String, message: String) {
        noticeTitle = title
        noticeMessage = message
        showNotice = true
    }
}
