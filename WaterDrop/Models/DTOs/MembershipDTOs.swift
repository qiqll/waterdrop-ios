import Foundation

// MARK: - Membership

/// 会员套餐，对应服务端 `MembershipPlanResponse`（`docs/api-reference.md` §9.2）。
///
/// `originalPrice` 与 `price` 的差额即优惠额；`discountText` 是服务端给好的文案。
/// 两者都可能是 nil，展示前判空 —— 服务端未配置原价时前端不该自己算。
///
/// `dailyUsageLimit` 是该套餐的每日 AI 调用上限，与设置页「今日AI用量」是同一套配额。
struct MembershipPlanResponse: Codable, Identifiable {
    let id: String?
    let planName: String?
    let planType: String?
    let price: Double?
    let originalPrice: Double?
    let validDays: Int?
    let dailyUsageLimit: Int?
    let description: String?
    let privileges: [String]?
    let enabled: Bool?
    let sortOrder: Int?
    let isRecommended: Bool?
    let discountText: String?

    /// `ForEach` 需要稳定标识。服务端套餐必有 `id`，缺了就退回套餐名，最后兜个常量 ——
    /// 宁可列表里两行撞 id，也不要在解码正常数据时崩掉。
    var stableId: String { id ?? planName ?? "unknown" }

    /// 是否是「真优惠」：原价高于现价才值得划线展示。
    /// 服务端可能只填其一，这里统一判定，两端 UI 才不会各算各的。
    var hasDiscount: Bool {
        guard let price, let originalPrice else { return false }
        return originalPrice > price
    }
}

/// 当前会员状态，对应服务端 `UserMembershipResponse`（§9.3）。
///
/// ⚠️ 非会员不返回错误：服务端合成一个 `status = "free"`、`memberType = 0`、
/// 且 `startTime` / `expireTime` / `remainingDays` **全为 nil** 的对象。
/// 判断「是不是会员」请用 `status` / `memberType`，别靠时间字段是否存在。
///
/// `statusText` 是服务端给好的中文（「使用中」「免费用户」），优先直接展示它，
/// 自己按状态码拼中文会与服务端口径漂移。
///
/// 时间字段是 ISO-8601 字符串，形如 `2026-09-18T17:16:09`（**有 `T`、无时区后缀**）。
/// 注意别被 `application.yml` 的 `date-format: yyyy-MM-dd HH:mm:ss` 误导 ——
/// 那条只作用于 `java.util.Date`，`LocalDateTime` 走 JavaTimeModule，实测就是这个 ISO 形态。
struct UserMembershipResponse: Codable {
    let id: String?
    let planName: String?
    let memberType: Int?
    let startTime: String?
    let expireTime: String?
    let status: String?
    let autoRenew: Bool?
    let remainingDays: Int?
    let isExpired: Bool?
    let statusText: String?

    /// 服务端 `user_memberships.status` 的「生效中」字面量。
    static let activeStatus = "active"
    /// 非会员的合成状态。
    static let freeStatus = "free"
    /// 已下单未支付的合成状态。
    static let pendingStatus = "pending"

    /// 是否处于生效中的会员态（与 Android `MembershipActivity` 判定一致）。
    var isActive: Bool {
        guard let status else { return false }
        return status != Self.freeStatus && status != Self.pendingStatus
    }

    /// 到期日的纯日期部分（`2026-10-18`）。免费用户无 `expireTime` 时为 nil。
    var expireDateText: String? {
        guard let expireTime = expireTime?.split(separator: "T").first else { return nil }
        return String(expireTime)
    }
}

// MARK: - Payment

/// 支付订单，对应服务端 `PaymentOrder`（§10.2）。
///
/// §10.2 的 `PaymentOrder` 是 §10.1 `PaymentResponse` 的超集（多出
/// `thirdPartyOrderId` / `paidAt` / `callbackData` / `refundAmount` / `refundedAt`），
/// 所以一个结构体覆盖两个端点 —— 与 Android 侧用 `typealias PaymentResponse = PaymentOrder` 同理。
///
/// ⚠️ `currency` 服务端当前恒为 nil；`amount` 是服务端按套餐重算后的价，
/// 客户端传什么都会被忽略。
struct PaymentOrder: Codable {
    let orderId: String?
    let userId: String?
    let productType: String?
    let productId: String?
    let amount: Double?
    let currency: String?
    let paymentMethod: String?
    let status: String?
    let paymentUrl: String?
    let expiresAt: String?
    let description: String?
    let thirdPartyOrderId: String?
    let paidAt: String?
    let callbackData: String?
    let refundAmount: Double?
    let refundedAt: String?
}

// MARK: - Requests

/// 购买请求（§9.5）。
///
/// `autoRenew` 与 `couponCode` 服务端**当前都不实现**：前者只落库、无扣款协议，
/// 后者传了不校验也不抵扣。保留字段是为了对齐契约，UI 不要据此做承诺。
struct PurchaseMembershipRequest: Encodable {
    let planId: String
    let paymentMethod: String?
    let autoRenew: Bool?
    let couponCode: String?
}

/// 创建支付单请求（§10.1）。
///
/// `productId` 传的是 **`/membership/purchase` 返回的会员订单号 `ORDER_…`**，
/// 不是套餐 ID —— 服务端已统一 `productId` 语义为 `user_memberships.order_id`。
/// `amount` 同样不传：服务端按套餐重新定价。
struct CreatePaymentRequest: Encodable {
    let productType: String
    let productId: String
    let paymentMethod: String?
    let amount: Double?
    let currency: String?
    let description: String?
    let callbackUrl: String?
}
