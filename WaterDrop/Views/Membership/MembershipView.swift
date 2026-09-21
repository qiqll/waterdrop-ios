import SwiftUI

/// 会员中心（F-012 ③，B-3.2 / B-3.3）。
///
/// 结构与 Android `MembershipActivity` 对齐：状态卡（当前会员）+ 套餐列表（三态）。
/// 下单与轮询的具体逻辑都在 `MembershipViewModel` 里，本视图只负责呈现和转发。
struct MembershipView: View {
    @State private var viewModel = MembershipViewModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            ThemeManager.shared.palette.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    statusCard
                    planSection
                }
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("会员中心")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 两个请求互不依赖，并发发出 —— 与 Android onCreate 里并排的两个 launch 一致。
            // 用 async let 而非先 status 再 plans，是因为串行会让套餐列表多等一个往返。
            async let status: Void = viewModel.loadMembership()
            async let plans: Void = viewModel.loadPlans()
            _ = await (status, plans)
        }
        .onDisappear {
            // 不取消的话，返回上一层后轮询仍会跑满 30 秒
            viewModel.cancelPolling()
        }
        .alert(viewModel.noticeTitle, isPresented: $viewModel.showNotice) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(viewModel.noticeMessage)
        }
        .onChange(of: viewModel.externalURL) { _, url in
            // 真实收银台分支：ViewModel 不 import UIKit，跳转交回这里执行。
            // 当前支付渠道是桩，这条路径不会走到。
            guard let url else { return }
            openURL(url)
            viewModel.clearExternalURL()
        }
    }

    // MARK: - 当前状态

    /// 会员状态卡。
    ///
    /// 免费用户下服务端返回的是**合成对象**（`status = "free"`、时间为 nil），
    /// 与真正的网络失败在数据上都表现为「没有到期时间」，所以这里统一按免费态呈现：
    /// 少显示几行，也好过展示上一轮的陈旧到期日。
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(statusTitle)
                    .font(.wd(.titleLarge, weight: .medium))
                    .foregroundStyle(ThemeManager.shared.palette.neutral800)

                Spacer()

                if let remainingText {
                    Text(remainingText)
                        .font(.wd(.bodyMedium))
                        .foregroundStyle(ThemeManager.shared.palette.primary)
                }
            }

            if let planNameText {
                Text(planNameText)
                    .font(.wd(.bodyMedium))
                    .foregroundStyle(ThemeManager.shared.palette.neutral600)
            }

            if let expireText {
                Text(expireText)
                    .font(.wd(.bodySmall))
                    .foregroundStyle(ThemeManager.shared.palette.neutral500)
            }

            if !viewModel.statusHint.isEmpty {
                Text(viewModel.statusHint)
                    .font(.wd(.bodySmall))
                    .foregroundStyle(ThemeManager.shared.palette.neutral500)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(ThemeManager.shared.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ThemeManager.shared.palette.neutral200, lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    /// 优先用服务端给的 `statusText`（「使用中」「免费用户」）—— 自己按状态码拼中文
    /// 会与服务端口径漂移。
    private var statusTitle: String {
        guard let membership = viewModel.membership else { return "免费用户" }
        if let statusText = membership.statusText, !statusText.isEmpty {
            return statusText
        }
        return membership.isActive ? (membership.planName ?? "会员") : "免费用户"
    }

    private var planNameText: String? {
        guard let membership = viewModel.membership, membership.isActive,
              let planName = membership.planName, !planName.isEmpty else { return nil }
        return planName
    }

    /// 到期日只取日期部分：`expireTime` 是 ISO-8601（`2026-09-18T17:16:09`，无时区后缀）。
    private var expireText: String? {
        guard let membership = viewModel.membership, membership.isActive,
              let date = membership.expireDateText else { return nil }
        return "\(date) 到期"
    }

    private var remainingText: String? {
        guard let membership = viewModel.membership, membership.isActive,
              let days = membership.remainingDays, days > 0 else { return nil }
        return "剩余 \(days) 天"
    }

    // MARK: - 套餐列表

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择套餐")
                .font(.wd(.titleMedium, weight: .medium))
                .foregroundStyle(ThemeManager.shared.palette.neutral800)
                .padding(.horizontal, 20)

            switch viewModel.plansState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.horizontal, 20)

            case .failed:
                Text("套餐加载失败")
                    .font(.wd(.bodyMedium))
                    .foregroundStyle(ThemeManager.shared.palette.semanticError)
                    .frame(maxWidth: .infinity)
                    .padding(16)

            case .empty:
                // `membership_plans` 表默认 0 行，空列表是正常的 code 200，
                // 联调时最常撞见的就是这一态，所以把种子脚本的提示一起写出来。
                VStack(spacing: 6) {
                    Text("暂无可用套餐")
                        .font(.wd(.bodyMedium))
                        .foregroundStyle(ThemeManager.shared.palette.neutral600)
                    Text("服务端尚未配置套餐。联调时请先执行 seed-membership-plans.sh。")
                        .font(.wd(.bodySmall))
                        .foregroundStyle(ThemeManager.shared.palette.neutral500)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(16)

            case .loaded:
                VStack(spacing: 12) {
                    ForEach(viewModel.plans) { plan in
                        PlanCardView(plan: plan, isPurchasing: viewModel.isPurchasing) {
                            Task { await viewModel.buy(plan) }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 24)
    }
}
