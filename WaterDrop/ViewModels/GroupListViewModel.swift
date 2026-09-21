import Foundation
import os.log

/// 群组列表视图模型（F-012 ④，对应 B-3.2）。
///
/// 与 Android `GroupListActivity` 一一对应：列表三态 → 建组 → 用邀请码入群。
/// 服务端契约见 `wd_server/docs/api-reference.md` §4。
///
/// 两条铁律（与 `MembershipViewModel` 一致）：
///
/// 1. **一律按 `body.code` 分支，不看 HTTP 状态码**（缺陷 R）。`APIClient` 对 HTTP 2xx
///    原样返回 `ApiResponse`，不因 `code != 200` 抛错，所以每个调用点都要自己判 `code`。
/// 2. **空列表是正常态**：`GET /groups` 对没加入过群的用户返回 `code: 200` + 空数组，
///    **不是 403**。「空」必须与「加载失败」分开呈现。
///
/// 本类刻意不 `import UIKit` —— 以便放进 `WaterDropTests`。
@Observable
@MainActor
final class GroupListViewModel {

    /// 列表三态。`empty` 与 `failed` 必须分开：前者是正常的空群组，后者才该给重试提示。
    enum ListState {
        case loading
        case loaded
        case empty
        case failed
    }

    private(set) var groups: [GroupResponse] = []
    private(set) var listState: ListState = .loading

    /// 提交在途（建组/入群）。视图据此禁用按钮，避免连点重复提交。
    private(set) var isSubmitting = false

    var showCreateDialog = false
    var showJoinDialog = false

    private(set) var noticeTitle = ""
    private(set) var noticeMessage = ""
    var showNotice = false

    private let logger = Logger(subsystem: "com.yjhome.waterdrop.ios", category: "GroupListViewModel")

    /// 群组数量上限不高（成员上限 50），一页拉够，不做分页控件。
    /// 与 Android `GroupListActivity.LIST_PAGE_SIZE` 一致。
    private static let pageSize = 50

    // MARK: - 加载

    /// 加载我加入的群组（`GET /groups`）。
    func loadGroups() async {
        listState = .loading
        do {
            let response = try await GroupAPIService.getGroups(page: 1, size: Self.pageSize)
            guard response.code == 200 else {
                // 失败文案透传服务端的：比自造文案准确
                logger.error("群组列表业务失败: \(response.message)")
                listState = .failed
                return
            }
            let list = response.data?.records ?? []
            groups = list
            listState = list.isEmpty ? .empty : .loaded
        } catch {
            logger.error("群组列表加载失败: \(error.localizedDescription)")
            listState = .failed
        }
    }

    // MARK: - 创建（B-3.2）

    /// 创建群组（`POST /groups`）。创建者自动成为群主。
    ///
    /// 名称必填 —— 本地先拦一道只是省一次往返，服务端仍会独立校验。
    /// 成功后把新群插到列表最前面，避免为了一个新群重拉整页。
    func createGroup(name: String, description: String?) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            presentNotice(title: "创建失败", message: "请填写群组名称")
            return
        }
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let desc = description?.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await GroupAPIService.createGroup(
                name: trimmedName,
                description: (desc?.isEmpty ?? true) ? nil : desc
            )
            guard response.code == 200, let created = response.data else {
                presentNotice(title: "创建失败", message: response.message)
                return
            }
            showCreateDialog = false
            groups.insert(created, at: 0)
            if listState == .empty { listState = .loaded }
            presentNotice(title: "创建成功", message: "群组「\(created.name ?? trimmedName)」已创建")
        } catch {
            logger.error("创建群组失败: \(error.localizedDescription)")
            presentNotice(title: "创建失败", message: "网络不可用，请检查网络后重试")
        }
    }

    // MARK: - 入群（B-3.2）

    /// 用邀请码入群（`POST /groups/join`）。
    ///
    /// ⚠️ 这条路径**没有 `{groupId}` 段**。服务端对错误路径返回的是
    /// **HTTP 200 + `body.code = 500`**，只看 HTTP 状态就会误判成功 ——
    /// 所以这里必须判 `code`。
    ///
    /// 失败消息（邀请码无效/已过期、已在群内、群已满）服务端已是中文，直接透传。
    /// 成功后刷新整个列表而不是插入新群：服务端返回的群对象与列表项的
    /// `myRole` / `memberCount` 口径可能有差异，重拉一次最稳。
    func joinGroup(inviteCode: String) async {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else {
            presentNotice(title: "加入失败", message: "请输入邀请码")
            return
        }
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let response = try await GroupAPIService.joinGroup(inviteCode: code)
            guard response.code == 200, let joined = response.data else {
                presentNotice(title: "加入失败", message: response.message)
                return
            }
            showJoinDialog = false
            await loadGroups()
            presentNotice(title: "加入成功", message: "已加入「\(joined.name ?? "")」")
        } catch {
            logger.error("加入群组失败: \(error.localizedDescription)")
            presentNotice(title: "加入失败", message: "网络不可用，请检查网络后重试")
        }
    }

    // MARK: - 弹窗

    private func presentNotice(title: String, message: String) {
        noticeTitle = title
        noticeMessage = message
        showNotice = true
    }
}
