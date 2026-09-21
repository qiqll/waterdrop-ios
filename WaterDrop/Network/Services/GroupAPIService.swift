import Foundation

/// 群组 API。
///
/// 对应服务端 `/api/groups/*`（见 `wd_server/docs/api-reference.md` §4）。
/// 与 Android `GroupApiService.kt` 保持同一套契约：端点、字段名、错误码逐字一致。
///
/// ## 四条硬规则
///
/// 1. **群组响应里永远没有 `inviteCode`**（缺陷 S）。`GroupResponse` 是恰好 13 个键的
///    固定形状，邀请码的唯一出口是 `GET /groups/{groupId}/invite-code`，且仅群主/管理员可调。
///    —— 所以**不要**用「响应里有没有邀请码」来判断用户是不是有管理权。
/// 2. **角色一律读 `myRole`**（`1` 群主 / `2` 管理员 / `3` 成员，见 ``GroupRole``）。
///    非成员为 `nil`。
/// 3. **一律按 `body.code` 分支，不看 HTTP 状态码**（缺陷 R）。本模块尤其明显：
///    `POST /groups/join` 走错路径时服务端返回的是 **HTTP 200 + `body.code = 500`**。
/// 4. **移除成员的路径参数是 `userId` 不是 `memberId`**。传 `member.id`
///    （`group_members` 主键）会移错人。
///
/// ## 错误码（同一条 403 下有三种码，必须按 `body.code` 区分）
///
/// | 场景 | HTTP | `code` |
/// |---|---|---|
/// | 非成员访问群详情 `GET /groups/{groupId}` | 403 | `8003` |
/// | 非成员访问群内物品 `GET /items/group/{groupId}` | 403 | `8004` |
/// | 非成员访问成员列表 `GET /groups/{groupId}/members` | 403 | `8006` |
/// | 邀请码不存在 / 已作废 | 404 | `8001` |
/// | 已在群内（重复入群） | 409 | `8007` |
/// | 群已满 | — | `8002` |
///
/// 本模块所有端点都要登录态；`APIClient` 默认 `requiresAuth: true`，这里不逐条再写。
enum GroupAPIService {

    // MARK: - 群组读写

    /// 创建群组（§4.2）。创建者自动成为群主。
    static func createGroup(name: String, description: String? = nil) async throws -> ApiResponse<GroupResponse> {
        let request = GroupCreateRequest(name: name, description: description)
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.groups,
            method: .POST,
            body: request
        )
    }

    /// 修改群组（§4.3）。仅群主/管理员。
    ///
    /// ⚠️ 服务端 `updateById` 的字段策略是 `NOT_NULL`，**null 字段会被静默跳过**。
    /// 想「清空描述」传 nil 是无效的 —— 而且响应会把 nil 原样回显，看起来像成功了。
    /// 本方法要求名称，描述只在非 nil 时提交，正是为了避开这个坑。
    static func updateGroup(groupId: String, name: String, description: String? = nil)
        async throws -> ApiResponse<GroupResponse> {
        let request = GroupCreateRequest(name: name, description: description)
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.groupById(groupId),
            method: .PUT,
            body: request
        )
    }

    /// 删除群组（§4.4）。仅群主，**不可逆**。
    static func deleteGroup(groupId: String) async throws -> ApiResponse<EmptyData> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.groupById(groupId),
            method: .DELETE
        )
    }

    /// 群组详情（§4.5）。
    ///
    /// 非成员访问是 `403 / code=8003`（注意与成员列表的 `8006`、群内物品的 `8004` 不同）。
    static func getGroup(groupId: String) async throws -> ApiResponse<GroupResponse> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.groupById(groupId)
        )
    }

    /// 我加入的群组列表（§4.6），已分页。
    ///
    /// ⚠️ 非成员在这里**不会**拿到 403 —— 服务端按 `user_id` 过滤，没加入过群就是
    /// `code: 200` + 空列表。所以「空」是正常态，UI 要呈现「还没有群组」而非报错。
    static func getGroups(page: Int = 1, size: Int = 50) async throws -> ApiResponse<PagedResult<GroupResponse>> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.groups,
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "size", value: String(size)),
            ]
        )
    }

    // MARK: - 成员

    /// 群成员列表（§4.8）。非成员是 `403 / code=8006`。
    ///
    /// 群组上限 50 人，一次拉够即可，不必做分页控件。
    static func getMembers(groupId: String, page: Int = 1, size: Int = 100)
        async throws -> ApiResponse<PagedResult<GroupMemberResponse>> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.groupMembers(groupId),
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "size", value: String(size)),
            ]
        )
    }

    /// 移出成员（§4.9）。仅群主/管理员。
    ///
    /// ⚠️ **路径参数是 `userId`，不是 `member.id`。** 取 `GroupMemberResponse.userId`。
    ///
    /// 移出后**不会**自动作废邀请码 —— 被踢的人拿旧码可以立刻回来（缺陷 T，已实测复现）。
    /// 调用方须在成功后提示群主作废邀请码，见 `GroupDetailViewModel.maybePromptRevoke`。
    static func removeMember(groupId: String, userId: String) async throws -> ApiResponse<EmptyData> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.groupMember(groupId, userId: userId),
            method: .DELETE
        )
    }

    /// 主动退群（§4.10）。
    ///
    /// ⚠️ **群主不能退群** —— 服务端会拒绝。群主的出口是删除群组，
    /// 所以 UI 上群主根本不该看到这个按钮。
    static func leaveGroup(groupId: String) async throws -> ApiResponse<EmptyData> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.groupLeave(groupId),
            method: .POST
        )
    }

    // MARK: - 邀请码

    /// 取邀请码（§4.12）。仅群主/管理员，普通成员调用是 403。
    ///
    /// ⚠️ 服务端对**未过期的码直接复用，不会轮换** —— 反复点「获取」不会把已经
    /// 分享出去的码作废。要让旧码失效必须走 ``revokeInviteCode(groupId:)``。
    ///
    /// `expireTime` 形如 `2026-09-21 15:04:05`，原样展示即可，别本地重新格式化。
    static func getInviteCode(groupId: String) async throws -> ApiResponse<GroupInviteCodeResponse> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.groupInviteCode(groupId)
        )
    }

    /// 作废邀请码（§4.12）。仅群主/管理员。
    ///
    /// 破坏性操作 —— 已经把码发出去、对方还没填的情形会被一并废掉，
    /// 所以调用方必须先弹确认。
    ///
    /// 作废后服务端把 `invite_code` 与 `invite_code_expiry` 一起置空，
    /// 旧码再填就是 `404 / code=8001`。
    static func revokeInviteCode(groupId: String) async throws -> ApiResponse<EmptyData> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.groupInviteCode(groupId),
            method: .DELETE
        )
    }

    /// 用邀请码入群（§4.11）。
    ///
    /// ⚠️ 路径是**单调的** `POST /groups/join`，没有 `{groupId}` 段。
    /// 拼成 `groups/{groupId}/join` 会落到没有映射的路径上，服务端返回
    /// **HTTP 200 + `body.code = 500`** —— 只看 HTTP 状态就会误判成功。
    ///
    /// 失败码：`404/8001` 邀请码无效或已过期、`400/400` 邀请码为空、
    /// `409/8007` 已在群内、`8002` 群已满。服务端消息已是中文，直接透传给用户。
    static func joinGroup(inviteCode: String) async throws -> ApiResponse<GroupResponse> {
        let request = GroupJoinRequest(inviteCode: inviteCode)
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.groupJoin,
            method: .POST,
            body: request
        )
    }

    // MARK: - 群内共享物品

    /// 群内共享物品（§4.13）。**非分页**，直接返回 `[ItemDto]`（与 `GET /items` 的
    /// `PagedResult` 形状不同）。非成员是 `403 / code=8004`。
    ///
    /// ⚠️ 返回的是**裸 `Item` 实体**，含 `createBy` / `updateBy` ——
    /// **那两个字段的值是手机号**（缺陷 V）。
    ///
    /// 「谁放的」请用 `ItemDto.userId` 去 ``getMembers(groupId:)`` 的成员列表里
    /// 比出昵称，**绝不**把 `createBy` 映射到 UI：它既是隐私泄露，
    /// 也是即将随缺陷 V 修复被移除的字段。
    static func getGroupItems(groupId: String) async throws -> ApiResponse<[ItemDto]> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.itemsByGroup(groupId)
        )
    }
}
