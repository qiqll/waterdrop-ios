import Foundation
import os.log

/// 会员中心视图模型（F-012 ③，对应 B-3.2 / B-3.3）。
///
/// 与 Android `MembershipActivity` 一一对应：套餐加载 → 两步下单 → 降级提示 → 轮询激活。
/// 服务端契约见 `wd_server/docs/api-reference.md` §9 / §10，降级流程即 §10.5。
///
/// 两条铁律：
///
/// 1. **一律按 `body.code` 分支**，HTTP 状态码不可信（缺陷 R）。`APIClient` 对
///    HTTP 2xx 是原样返回 `ApiResponse` 的，不会因为 `code != 200` 抛错，所以每个
///    调用点都要自己判 `code`。
/// 2. 本阶段**没有真实支付渠道**：`generatePaymentUrl` 返回显式桩 `stub://…`。
///    识别该前缀后 **不跳转**，只提示「支付通道未配置」，然后靠轮询等服
///    务端测试回调激活。真实收银台接入后只需替换 `handlePaymentURL` 的跳转分支，
///    轮询逻辑原样复用。
///
/// 本类刻意不 `import UIKit` —— 真实收银台的跳转通过 `externalURL` 交回视图层执行，
/// 这样下单/轮询逻辑保持纯逻辑，便于放进 `WaterDropTests`。
@Observable
@MainActor
final class MembershipViewModel {

    /// 套餐列表的三态。空态是**正常的 `code: 200` + 空数组**（`membership_plans`
    /// 表默认 0 行，联调前没跑 seed 脚本），必须与「加载失败」分开。
    enum PlansState {
        case loading
        case loaded
        case empty
        case failed
    }

    private(set) var plans: [MembershipPlanResponse] = []
    private(set) var plansState: PlansState = .loading

    /// 当前会员状态。nil 表示**网络失败或 `code != 200`**，与「免费用户」区分 ——
    /// 免费用户服务端会合成一个 `status = "free"` 的对象，不是 nil。
    private(set) var membership: UserMembershipResponse?

    /// 下单在途。视图据此禁用所有按钮，避免连点重复下单。
    private(set) var isPurchasing = false

    /// 状态卡里的补充提示（「等待支付结果…」/「开通成功」/「暂未收到支付结果」）。
    /// 这些是瞬时反馈，走行内文案而不是弹窗，与 Android 侧的 Toast 对应。
    private(set) var statusHint = ""

    var showNotice = false
    private(set) var noticeTitle = ""
    private(set) var noticeMessage = ""

    /// 需要交给系统浏览器打开的地址。当前**永远是 nil** —— 支付渠道是桩，
    /// 这个出口是为接真实收银台预留的，视图看到它变化就调 `openURL`。
    private(set) var externalURL: URL?

    private var pollTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.yjhome.waterdrop.ios", category: "MembershipViewModel")

    /// 轮询间隔与总超时：30s 内每 2s 一次。够测试回调跑完，又不至于让用户干等。
    /// 与 Android `MembershipActivity` 的常量保持一致。
    private static let pollInterval: Duration = .seconds(2)
    private static let pollTimeout: TimeInterval = 30

    /// `POST /payment/create` 当前只接受 `MEMBERSHIP`，其它值服务端回 7001。
    private static let productTypeMembership = "MEMBERSHIP"

    /// 支付桩地址前缀（服务端 `PaymentServiceImpl.generatePaymentUrl`）。
    private static let stubScheme = "stub://"

    // MARK: - 加载

    /// 加载套餐列表（`GET /membership/plans`）。
    func loadPlans() async {
        plansState = .loading
        do {
            let response = try await MembershipAPIService.getPlans()
            guard response.code == 200 else {
                logger.error("套餐加载业务失败: \(response.message)")
                plansState = .failed
                return
            }
            let list = response.data ?? []
            plans = list
            plansState = list.isEmpty ? .empty : .loaded
        } catch {
            logger.error("套餐加载失败: \(error.localizedDescription)")
            plansState = .failed
        }
    }

    /// 刷新当前会员状态（`GET /membership/current`）。
    ///
    /// 失败时把 `membership` 置 nil，视图按「免费用户」呈现并隐藏依赖时间的行 ——
    /// 与 Android `loadMembershipStatus` 的处理一致：宁可少显示，也不要显示上一轮的陈旧到期日。
    func loadMembership() async {
        membership = await fetchCurrentMembership()
    }

    /// 读一次当前会员状态。nil 表示网络失败或 `code != 200`。
    private func fetchCurrentMembership() async -> UserMembershipResponse? {
        do {
            let response = try await MembershipAPIService.getCurrent()
            guard response.code == 200 else { return nil }
            return response.data
        } catch {
            logger.warning("查询会员状态失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 下单（B-3.3）

    /// 下单两步走：
    ///
    /// 1. `POST /membership/purchase` → 拿**会员订单号** `ORDER_…`
    /// 2. `POST /payment/create`（`productType = MEMBERSHIP`、`productId =` 上面的订单号）
    ///    → 拿 `paymentUrl`
    ///
    /// ⚠️ 第 2 步的 `productId` 是**会员订单号**，不是套餐 ID —— 服务端已统一
    /// `productId` 语义为 `user_memberships.order_id`（决议 2）。
    ///
    /// ⚠️ `amount` 不传：服务端按套餐重新定价，客户端传了也会被忽略（防篡改，有意设计）。
    func buy(_ plan: MembershipPlanResponse) async {
        guard let planId = plan.id, !planId.isEmpty else {
            // 服务端套餐一定有 id；走到这里说明数据有问题，如实提示，别静默吞掉
            presentNotice(title: "下单失败", message: "套餐信息不完整")
            return
        }
        guard !isPurchasing else { return }
        isPurchasing = true
        statusHint = ""
        defer { isPurchasing = false }

        do {
            let purchaseResponse = try await MembershipAPIService.purchase(planId: planId)
            guard purchaseResponse.code == 200,
                  let membershipOrderId = purchaseResponse.data,
                  !membershipOrderId.isEmpty else {
                presentNotice(title: "下单失败", message: purchaseResponse.message)
                return
            }

            let payResponse = try await PaymentAPIService.createPayment(productId: membershipOrderId)
            guard payResponse.code == 200 else {
                // 此处失败消息来自服务端（如「会员订单不存在」），透传比自造文案准确
                presentNotice(title: "下单失败", message: payResponse.message)
                return
            }

            handlePaymentURL(payResponse.data?.paymentUrl, membershipOrderId: membershipOrderId)
            // 订单已建好，无论走哪个分支都要开始等激活
            startPollingForActivation()
        } catch {
            logger.error("下单失败: \(error.localizedDescription)")
            presentNotice(title: "下单失败", message: "网络不可用，请检查网络后重试")
        }
    }

    // MARK: - 降级流程（B-3.3）

    /// 拿到 `paymentUrl` 之后怎么办。
    ///
    /// 本阶段没有真实收银台，服务端返回的是 `stub://payment-not-configured?orderId=…&method=…`。
    /// 识别该前缀后**不跳转**，只提示「支付通道未配置」，把真实付款这一步空出来；
    /// 会员最终由服务端用测试回调激活（见 `startPollingForActivation`）。
    private func handlePaymentURL(_ paymentUrl: String?, membershipOrderId: String) {
        guard let paymentUrl, !paymentUrl.isEmpty else {
            // 没有 URL 也未必是错：服务端可能只建单。同样按「未配置通道」处理。
            logger.warning("paymentUrl 为空，orderId=\(membershipOrderId, privacy: .public)")
            presentPayUnavailable(membershipOrderId: membershipOrderId)
            return
        }

        guard !paymentUrl.hasPrefix(Self.stubScheme) else {
            logger.info("检测到支付桩地址，按降级流程处理")
            presentPayUnavailable(membershipOrderId: membershipOrderId)
            return
        }

        // 真实收银台分支：当前不存在，接上以后无需再改轮询部分。
        // 这里不直接 openURL，而是把地址抛给视图层 —— 见类注释。
        guard let url = URL(string: paymentUrl) else {
            presentPayUnavailable(membershipOrderId: membershipOrderId)
            return
        }
        externalURL = url
    }

    func clearExternalURL() {
        externalURL = nil
    }

    private func presentPayUnavailable(membershipOrderId: String) {
        presentNotice(
            title: "支付通道未配置",
            message: "当前版本未接入真实支付渠道，无法完成付款。\n订单已创建（\(membershipOrderId)），可稍后重试或在服务端补偿开通。"
        )
    }

    // MARK: - 轮询激活（B-3.3）

    /// 轮询 `GET /membership/current` 直到 `status = active` 或超时。
    ///
    /// 服务端激活由支付回调（或手工 `/membership/activate` 补偿）完成，客户端无法主动触发，
    /// 所以这里是唯一的「等结果」手段。超时**不报错** —— 订单可能稍后才被回调，
    /// 提示用户回来看即可。
    ///
    /// 刻意不调 `/membership/activate` 作为兜底：契约里它是服务端手工补偿入口，
    /// 客户端越权调用会把「未付款却已开通」变成一条正常路径。
    private func startPollingForActivation() {
        pollTask?.cancel()
        statusHint = "等待支付结果…"

        pollTask = Task { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(Self.pollTimeout)

            while Date() < deadline {
                try? await Task.sleep(for: Self.pollInterval)
                if Task.isCancelled { return }

                guard let latest = await self.fetchCurrentMembership() else { continue }
                if latest.status == UserMembershipResponse.activeStatus {
                    self.membership = latest
                    self.statusHint = "开通成功，欢迎加入会员"
                    return
                }
            }

            if Task.isCancelled { return }
            // 超时：刷新一次真实状态（可能刚好在最后一轮之后激活），再给提示
            await self.loadMembership()
            self.statusHint = "暂未收到支付结果，请稍后在会员中心查看"
        }
    }

    /// 离开页面时取消轮询。不取消的话，用户返回上一层后 `Task` 仍会跑满 30 秒，
    /// 且可能对着已销毁的视图写状态。
    func cancelPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - 弹窗

    private func presentNotice(title: String, message: String) {
        noticeTitle = title
        noticeMessage = message
        showNotice = true
    }
}
