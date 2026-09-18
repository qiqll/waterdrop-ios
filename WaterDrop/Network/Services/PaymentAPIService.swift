import Foundation

/// 支付 API。
///
/// 对应服务端 `/api/payment/*`（见 `wd_server/docs/api-reference.md` §10）。
/// 与 Android `PaymentApiService.kt` 保持同一套契约。
///
/// 服务端契约要点：
///
/// - **除 `/payment/callback` 外全部需要 JWT。** callback 不在本文件里 ——
///   那是给支付网关调的，客户端不要调（见文件末尾说明）。
/// - **一律按 `body.code` 分支，不看 HTTP 状态码。** 本模块尤其容易踩坑：
///   `order(_:)` / `cancel(_:)` 的失败形态都是 **HTTP 200 + `code: 500`**，
///   按 HTTP 判断会把失败当成功。
/// - **本模块的路由参数一律在 path 里**，唯一的例外是 `refund(_:reason:)` 的 `reason`（query）。
///   把路径参数误写成 query 形式**不会**得到 404，而是命中一个无匹配路由的兜底，
///   返回 HTTP 200 + `code: 500` + message「系统内部错误」—— 与真正的业务失败文案不同，
///   但同样会被误判成「操作失败」，排查时容易走错方向。
enum PaymentAPIService {

    /// 创建支付订单（§10.2）。
    ///
    /// - `productType` 必须显式传 `"MEMBERSHIP"`。
    /// - `productId` 传**会员订单号**（`ORDER_…`，`MembershipAPIService.purchase` 的返回值），
    ///   不是套餐 ID，也不是会员记录主键。
    ///
    /// 两者的失败码**不同**，不要合并处理：
    /// - `productType` 缺失 → `code: 7001`，message 是 `暂不支持的商品类型: null`
    ///   （走的是「非 MEMBERSHIP」分支而非必填校验，那个 `null` 是字面量字符串，不要展示给用户）
    /// - `productId` 缺失或不存在 → `code: 5001`
    ///
    /// 请求体里的 `amount` **会被服务端忽略** —— 金额一律由服务端按订单号重新计算，
    /// 这是防客户端篡改的有意设计。传了不生效，这里也就不传。
    ///
    /// 返回的 `productId` 是会员订单号，`orderId` 是**支付订单号**（`PAY…`），
    /// 后续 `order` / `cancel` / `refund` / `status` 都用后者。
    static func createPayment(productId: String, paymentMethod: String? = nil) async throws -> ApiResponse<PaymentOrder> {
        let request = CreatePaymentRequest(
            productType: "MEMBERSHIP",
            productId: productId,
            paymentMethod: paymentMethod,
            amount: nil,
            currency: nil,
            description: nil,
            callbackUrl: nil
        )
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.paymentCreate,
            method: .POST,
            body: request
        )
    }

    /// 查询支付订单（§10.3）。
    ///
    /// `orderId` 是**支付订单号**（`PAY…`）。
    ///
    /// ⚠️ 订单不存在或不属于当前用户时返回 **HTTP 200 + `code: 500`** +
    /// message「订单不存在或无权访问」。两种情形返回同一条消息是**有意的** ——
    /// 避免泄露他人订单是否存在，客户端据此也无法区分，不要试图区分。
    static func order(_ orderId: String) async throws -> ApiResponse<PaymentOrder> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.paymentOrder(orderId)
        )
    }

    /// 查询支付历史（§10.3）。
    ///
    /// 用户身份取自 JWT，没有 `userId` 参数（旧文档里那个是过时的）。
    static func history() async throws -> ApiResponse<[PaymentOrder]> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.paymentHistory
        )
    }

    /// 取消订单（§10.4）。
    ///
    /// 仅 `PENDING` 订单可取消，服务端用原子条件更新保证。
    ///
    /// ⚠️ 失败时返回 **HTTP 200 + `code: 500`** + message「订单取消失败」，
    /// 必须判 `code`，不能因 HTTP 200 就当取消成功。
    static func cancel(_ orderId: String) async throws -> ApiResponse<String> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.paymentCancel(orderId),
            method: .POST
        )
    }

    /// 申请退款（§10.4）。
    ///
    /// 仅 `PAID` 订单可申请，幂等（重复退款返回失败而非重复退）。
    /// 当前只改状态，无真实退款通道 —— 依赖真实收银台接入。
    ///
    /// ⚠️ `reason` 是**必填 query 参数**，漏传返回 `code: 400` +「缺少参数: reason」，
    /// 与「退款申请失败」的 `code: 500` 是两种不同的失败，排查时别混为一谈。
    static func refund(_ orderId: String, reason: String) async throws -> ApiResponse<String> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.paymentRefund(orderId),
            method: .POST,
            queryItems: [URLQueryItem(name: "reason", value: reason)]
        )
    }

    /// 查询订单状态（§10.3）。
    ///
    /// 返回状态字符串：`PENDING` / `PAID` / `CANCELLED` / `REFUNDED` / `EXPIRED`。
    ///
    /// ⚠️ 订单不存在时返回 **HTTP 200 + `code: 200` + `data` 为 nil**（不是错误）。
    /// 本方法**无法**用于判断订单是否存在 —— 它区分不了「不存在」与「存在但状态为 nil」。
    /// 要确认存在性请用 `order(_:)`（那里会给 `code: 500`）。
    static func status(_ orderId: String) async throws -> ApiResponse<String> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.paymentStatus(orderId)
        )
    }
}

// 说明：服务端另有 `POST /api/payment/callback`（支付回调），此处**刻意不提供**。
// 它是本模块唯一 permitAll 的端点，用 HMAC-SHA256 签名鉴权、消费方是支付网关而非 App。
// 其错误语义也与其他接口相反（永久拒绝回 HTTP 200 让网关别重试，可恢复失败回非 2xx 触发重试），
// 包进客户端接口只会诱导误用。联调期由服务端侧的脚本触发（见 api-reference.md §10.4）。
