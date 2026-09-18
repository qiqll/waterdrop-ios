import Foundation

/// 会员 API。
///
/// 对应服务端 `/api/membership/*`（见 `wd_server/docs/api-reference.md` §9）。
/// 与 Android `MembershipApiService.kt` 保持同一套契约：端点、字段名、状态字面量逐字一致。
///
/// 两条贯穿全模块的约定：
///
/// - **本模块所有端点都要登录态**，包括看起来像公开数据的 `/membership/plans`。
///   `APIClient` 默认 `requiresAuth: true`，这里不逐条再写。
/// - **一律按 `body.code` 分支，不看 HTTP 状态码**（缺陷 R）。服务端错误走
///   `BusinessException` → `ResultCode` → HTTP，HTTP 状态与业务成败并非一一对应。
///   唯一的例外是 `/payment/callback`，那个端点不是给客户端用的（见 `PaymentAPIService`）。
enum MembershipAPIService {

    /// 获取全部可用套餐（§9.2）。
    ///
    /// 只返回 `enabled = true` 的套餐，已按 `sortOrder` 排好序，客户端不必再排。
    ///
    /// ⚠️ 依赖 `membership_plans` 表有数据，而该表**默认 0 行**且没有管理端创建接口。
    /// 联调前须先跑 `wd_server/scripts/seed-membership-plans.sh`（幂等）。
    /// 返回空数组是正常的 `code: 200`，**不是错误** —— UI 应呈现「暂无可用套餐」而非报错。
    static func getPlans() async throws -> ApiResponse<[MembershipPlanResponse]> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.membershipPlans
        )
    }

    /// 按类型获取套餐（§9.2）。
    ///
    /// `planType` 传未知值**不报错**，返回 `code: 200` + 空数组，所以「空」既可能是
    /// 「该类型确实没套餐」也可能是「类型名拼错了」，客户端无法区分。
    /// 常规流程用 `getPlans()` 即可，本方法留给按类型分栏展示的场景。
    static func getPlans(byType planType: String) async throws -> ApiResponse<[MembershipPlanResponse]> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.membershipPlansByType(planType)
        )
    }

    /// 查询当前会员状态（§9.3）。
    ///
    /// 这也是支付后轮询用的端点（§10.5 降级流程）。
    ///
    /// - Note: 服务端取的是 **`expireTime` 最大**的那条记录，不是最近购买的那条。
    ///   对正常用户两者通常一致，但退订后重购的场景下会出现差异。
    static func getCurrent() async throws -> ApiResponse<UserMembershipResponse> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.membershipCurrent
        )
    }

    /// 查询会员开通历史（§9.4）。
    static func getHistory() async throws -> ApiResponse<[UserMembershipResponse]> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.membershipHistory
        )
    }

    /// 购买会员（下单，§9.5）。
    ///
    /// 返回的是**会员订单号**，形如 `ORDER_1789723550170_c8af0a4b`。这个值就是下一步
    /// `PaymentAPIService.createPayment(productId:)` 的入参 —— 不要再传套餐 ID。
    ///
    /// 下单成功会同时建一条 `status = pending` 的会员记录，其起止时间**为 nil**，
    /// 直到支付回调激活时才写入。也就是说：调完本方法**用户还不是会员**。
    static func purchase(planId: String, paymentMethod: String? = nil) async throws -> ApiResponse<String> {
        let request = PurchaseMembershipRequest(
            planId: planId,
            paymentMethod: paymentMethod,
            autoRenew: nil,
            couponCode: nil
        )
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.membershipPurchase,
            method: .POST,
            body: request
        )
    }

    /// 激活会员（手工补偿，§9.6）。
    ///
    /// ⚠️ 本端点的 `orderId` 走 **query string**，不是 JSON body ——
    /// 与 `purchase` 的 body 风格不同，别照着上面抄。
    ///
    /// 正常路径下由支付回调自动激活，本端点是支付网关未能重试时的补偿入口。
    /// **幂等**：对已生效的会员重复调用返回 200，且不会重复叠加时长。
    /// 未支付的订单调用会得到 `code: 7001`。
    static func activate(orderId: String) async throws -> ApiResponse<String> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.membershipActivate,
            method: .POST,
            queryItems: [URLQueryItem(name: "orderId", value: orderId)]
        )
    }

    /// 取消自动续费（§9.7）。
    ///
    /// 无参数、无请求体。自动续费本身未实现（§9.9），本端点的实际效果仅限「关掉标记」。
    static func cancelAutoRenew() async throws -> ApiResponse<String> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.membershipCancelAutoRenew,
            method: .POST
        )
    }

    /// 是否付费会员（§9.8）。
    ///
    /// 判定条件是四个全满足：有记录 且 `memberType == 1` 且 `status == "active"`
    /// 且 `expireTime` 晚于当前时间。服务端做了空值防护 —— `pending` 行的
    /// `expireTime` 为 nil 时不会崩。
    ///
    /// 比客户端本地比较 `expireTime` 更可靠，也比 `getCurrent()` 更严格：
    /// `/current` 只要有生效记录就返回正常对象，本端点还额外要求 `memberType == 1`。
    /// 做「是不是 VIP」判断时以本端点为准。
    static func checkPremium() async throws -> ApiResponse<Bool> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.membershipCheckPremium
        )
    }
}
