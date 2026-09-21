import Foundation

enum ServerConfig {
    static var baseURL: String { AppConfig.serverBaseURL }

    enum Timeout {
        static let connect: TimeInterval = 10
        static let read: TimeInterval = 30
    }

    enum Endpoints {
        static let alicloudAuthToken = "users/aliyun/auth-token"
        static let alicloudLogin = "users/aliyun/login"
        static let refreshToken = "users/refresh"
        static let logout = "users/logout"
        static let userProfile = "users/profile"

        /// F-012 ⑥ (D-10)：活跃上报。服务端返回 `Result<Void>`，且**失败也不影响任何业务**。
        /// ⚠️ 服务端对 `user:activity:{userId}:{date}` 做的是 **increment**（累加计数），
        /// 不是去重集合 —— 按 onResume 无脑上报会把「活跃次数」灌成几十。调用方需自行按天节流。
        static let heartbeat = "users/heartbeat"

        static let items = "items"
        static let itemSearch = "items/search"
        static let itemByName = "items/search/by-name"
        static let aiIntent = "ai/intent"
        static let aiUsageToday = "ai/usage/today"
        static let aiHelp = "ai/help"
        static let aiHelpHistory = "ai/help/history"
        static let filesUpload = "files/upload"
        static let versionCheck = "version/check"

        // F-012 ②: 数据同步。对应服务端 sync 包下的四个端点。
        static let syncUpload = "sync/upload"
        static let syncDownload = "sync/download"
        static let syncMerge = "sync/sync"
        static let syncVersionCheck = "sync/version/check"

        // F-012 ③: 会员与支付。对应服务端 membership / payment 两个包。
        static let membershipPlans = "membership/plans"
        static let membershipCurrent = "membership/current"
        static let membershipHistory = "membership/history"
        static let membershipPurchase = "membership/purchase"
        static let membershipActivate = "membership/activate"
        static let membershipCancelAutoRenew = "membership/cancel-auto-renew"
        static let membershipCheckPremium = "membership/check-premium"

        static let paymentCreate = "payment/create"
        static let paymentHistory = "payment/history"

        static func membershipPlansByType(_ planType: String) -> String {
            "membership/plans/\(planType.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? planType)"
        }
        static func paymentOrder(_ orderId: String) -> String { "payment/order/\(orderId)" }
        static func paymentCancel(_ orderId: String) -> String { "payment/cancel/\(orderId)" }
        static func paymentRefund(_ orderId: String) -> String { "payment/refund/\(orderId)" }
        static func paymentStatus(_ orderId: String) -> String { "payment/status/\(orderId)" }

        static func itemById(_ id: String) -> String { "items/\(id)" }
        static func itemsByCategory(_ category: String) -> String {
            "items/category/\(category.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? category)"
        }

        // F-012 ④: 群组共享。对应服务端 group 包，外加一条挂在 items 包下的群内物品读取。
        static let groups = "groups"

        /// ⚠️ 入群**没有** `{groupId}` 路径段 —— 只有邀请码。写成 `groups/\(groupId)/join`
        /// 会落到没有映射的路径上，服务端返回 **HTTP 200 + `body.code=500`**，
        /// 前端若只看 HTTP 状态就会当成成功。
        static let groupJoin = "groups/join"

        static func groupById(_ groupId: String) -> String { "groups/\(groupId)" }
        static func groupMembers(_ groupId: String) -> String { "groups/\(groupId)/members" }

        /// ⚠️ 路径参数是 **userId 不是 memberId**（`member.id` 是 `group_members` 主键，
        /// 传它必然移错人）。取 `GroupMemberResponse.userId`。
        static func groupMember(_ groupId: String, userId: String) -> String {
            "groups/\(groupId)/members/\(userId)"
        }

        static func groupLeave(_ groupId: String) -> String { "groups/\(groupId)/leave" }

        /// 邀请码的**唯一出口**：群组响应里永远不含 `inviteCode`（缺陷 S）。
        /// `GET` 取码 / `DELETE` 作废，仅群主、管理员可用。
        static func groupInviteCode(_ groupId: String) -> String { "groups/\(groupId)/invite-code" }

        /// 群内共享物品。**非分页**，直接返回 `[Item]`（与 `items` 的 `PagedResult` 不同）。
        static func itemsByGroup(_ groupId: String) -> String { "items/group/\(groupId)" }

        // F-012 ⑤: 计划任务（提醒）。对应服务端 schedule 包，契约见 `api-reference.md` §5。
        static let schedules = "schedules"

        /// ⚠️ `keyword` **必填**，不传是 HTTP 400 而不是空结果。
        static let scheduleSearch = "schedules/search"

        /// ⚠️ **降级实现**：服务端没有模板表，`templateId` 传什么都一样，
        /// 等价于「用一套默认值建一条普通提醒」。客户端别拿它当真正的模板功能。
        static func scheduleTemplate(_ templateId: String) -> String {
            "schedules/templates/\(templateId)"
        }

        static func scheduleById(_ scheduleId: String) -> String { "schedules/\(scheduleId)" }

        /// 启用/停用是**独立端点**，不是 `PUT {enabled: false}` ——
        /// 只有这两个端点会重算 `nextExecutionAt`（停用置 `null`）。
        static func scheduleEnable(_ scheduleId: String) -> String { "schedules/\(scheduleId)/enable" }
        static func scheduleDisable(_ scheduleId: String) -> String { "schedules/\(scheduleId)/disable" }

        /// ⚠️ 「立即执行」只往 `schedule_executions` 记一条，**不产生任何通知**。
        /// 别接到「测试提醒」按钮上。
        static func scheduleExecute(_ scheduleId: String) -> String { "schedules/\(scheduleId)/execute" }
    }

    // MARK: - Image URL Resolution

    /// 服务端返回的 fileUrl 形如 `/api/files/xxx`，而 baseURL 已含 `/api` 前缀，
    /// 直接拼接会得到重复的 `/api/api/...`。这里提取 scheme+host+port 得到 origin，
    /// 将相对路径拼接为完整 URL。
    static var origin: String {
        if let url = URL(string: baseURL),
           let scheme = url.scheme,
           let host = url.host {
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            if let port = url.port { components.port = port }
            if let resolved = components.string { return resolved }
        }
        return baseURL
    }

    /// 将服务端返回的相对 fileUrl 解析为可用于加载的完整 URL。
    /// 绝对地址（http/https）原样返回；相对地址则拼上 origin。
    static func resolveImageUrl(_ fileUrl: String?) -> String? {
        guard let fileUrl, !fileUrl.isEmpty else { return nil }
        if fileUrl.hasPrefix("http://") || fileUrl.hasPrefix("https://") {
            return fileUrl
        }
        return origin + fileUrl
    }
}
