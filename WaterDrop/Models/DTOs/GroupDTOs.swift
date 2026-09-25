import Foundation

// MARK: - 角色

/// 群组成员角色，对应服务端 `GroupRole`（`docs/api-reference.md` §4.14）。
///
/// ⭐ **权限判断一律读 `GroupResponse.myRole` / `GroupMemberResponse.role`**，
/// 不要试图从响应里找 `inviteCode` 之类的字段来判断 —— 缺陷 S 已经把
/// `inviteCode` 从群组响应里彻底拿掉了，那个隐式信号不存在。
///
/// 与 Android `object GroupRole` 同为裸 `Int` 常量，不用 Swift `enum`：
/// 服务端将来加角色时 `enum` 解码会直接失败（`rawValue` 不匹配），
/// 而 `Int?` 只是走到 `nil` 分支、UI 少显示一个徽标。**容错优先。**
enum GroupRole {
    static let owner = 1
    static let admin = 2
    static let member = 3

    /// 角色中文名。**非成员返回 nil**（服务端给非成员的 `myRole` 就是 nil），
    /// 调用方据此隐藏徽标，而不是显示一个「成员」的空壳。
    static func label(_ role: Int?) -> String? {
        switch role {
        case owner: return "群主"
        case admin: return "管理员"
        case member: return "成员"
        default: return nil
        }
    }
}

// MARK: - 群组

/// 群组概要，对应服务端 `GroupResponse`（§4.14）。
///
/// ⚠️ 这个结构体刻意**没有** `inviteCode` / `inviteCodeExpiry` / `createBy` /
/// `updateBy` / `deleted` 字段（缺陷 S / U）：群组响应是**恰好 14 个键**的固定形状，
/// 加了字段就等着在服务端加固后的某天全部解码失败。
/// （`itemCount` 是 2026-09-25 新加的，服务端 `931dc00`；此前是 13 个键。）
/// 邀请码有且只有一个出口 —— `GET /groups/{groupId}/invite-code`，且仅群主/管理员可调。
///
/// `myRole` 对**非成员为 nil**（理论上拿不到，非成员访问群详情是 403/`code=8003`，
/// 但 `GET /groups` 列表里出现的历史群组会走到这个分支）。所有角色相关按钮的显隐
/// 都该集中在一处判断，别散在多个子视图里 —— 否则很容易出现「群主看到了退群按钮」。
/// 所有字段都是可选基础类型，`Hashable` / `Equatable` 交给编译器合成 ——
/// `Hashable` 是 `.navigationDestination(item:)` 的要求（它靠值比较判断是不是同一个目标）。
struct GroupResponse: Codable, Identifiable, Hashable {
    let id: String?
    let name: String?
    let description: String?
    let ownerId: String?
    let avatar: String?
    let memberCount: Int?
    let maxMembers: Int?
    /// 群内共享物品数（F-017 §15.9）。
    ///
    /// 为 `nil` 表示**服务端没给这个数字**（而不是「确实为 0」）——
    /// 界面据此决定是否显示，不要用 `?? 0` 抹平这个区别。
    let itemCount: Int?
    let status: String?
    let tags: String?
    let settings: String?
    let myRole: Int?
    let createTime: String?
    let updateTime: String?

    /// `ForEach` 的稳定标识。群 id 服务端必给，缺了退回名称再兜一个常量 ——
    /// 宁可两行撞 id，也不要在解码正常数据时崩掉。
    var stableId: String { id ?? name ?? "unknown" }

    var isOwner: Bool { myRole == GroupRole.owner }

    /// 能否管理（群主或管理员）。邀请码取/作废、移出成员都看这个。
    var canManage: Bool { myRole == GroupRole.owner || myRole == GroupRole.admin }

    /// 是否已在群内（拿到 `myRole` 就是）。退群入口要据此显隐。
    var isMember: Bool { myRole != nil }
}

/// 群成员，对应服务端 `GroupMemberResponse`（§4.14）。
///
/// ⚠️ 两个易错点：
/// - **路径参数要的是 `userId`，不是 `id`** —— 移出成员时传 `id`（`group_members`
///   主键）会移错人。
/// - `nickname` 可能为 nil（用户没设资料）。展示时回退成「未设置昵称」，
///   别显示空白，更别退化去显示 `userId`。
///
/// 响应**不含**审计列（缺陷 U 修复于 2026-09-19）。
struct GroupMemberResponse: Codable, Identifiable, Hashable {
    let id: String?
    let groupId: String?
    let userId: String?
    let nickname: String?
    let avatar: String?
    let role: Int?
    let status: String?
    let joinTime: String?

    var stableId: String { id ?? userId ?? "unknown" }

    /// 展示用昵称；未设置时回退「未设置昵称」。
    var displayName: String {
        guard let nickname, !nickname.isEmpty else { return "未设置昵称" }
        return nickname
    }

    var roleLabel: String? { GroupRole.label(role) }
}

/// 邀请码，对应服务端 `GroupInviteCodeResponse`（§4.14）。
///
/// `expireTime` 是服务端给好的 `yyyy-MM-dd HH:mm:ss` 字符串 ——
/// **原样展示**，不要本地重新格式化或转成 `Date`（转 `Date` 还得多配一个
/// formatter，且服务端改格式时前端会静默显示空白）。
struct GroupInviteCodeResponse: Codable {
    let groupId: String?
    let inviteCode: String?
    let expireTime: String?
}

// MARK: - 请求

/// 创建群组（§4.2）。
///
/// 名称上限 50 字、描述上限 200 字 —— 与 Android `GroupListActivity` 一致，
/// 客户端限长只是为了输入体验，服务端仍会独立校验。
struct GroupCreateRequest: Encodable {
    let name: String
    let description: String?
}

/// 加入群组（§4.11）。
///
/// ⚠️ 这条请求**没有 `groupId`** —— 只有邀请码，路径也是单调的 `POST /groups/join`。
/// 传的是 8 位大写邀请码。
struct GroupJoinRequest: Encodable {
    let inviteCode: String
}
