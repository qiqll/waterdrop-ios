import SwiftUI

/// 套餐卡片（对应 Android `item_membership_plan.xml`）。
///
/// 字段几乎全是可选的 —— 服务端未配置的项直接不渲染对应行，而不是显示空占位。
struct PlanCardView: View {
    let plan: MembershipPlanResponse
    /// 有下单在途时全部按钮置灰，避免连点重复下单。
    let isPurchasing: Bool
    let onBuy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.planName ?? "")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(ThemeManager.shared.palette.neutral800)

                if plan.isRecommended == true {
                    Text("推荐")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ThemeManager.shared.palette.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ThemeManager.shared.palette.primaryLight)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥\(formatAmount(plan.price))")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(ThemeManager.shared.palette.primary)

                // 只有原价**高于**现价才划线 —— 否则看着像涨价。
                // 判定逻辑放在 DTO 的 `hasDiscount` 上，与 Android `PlanViewHolder` 同一口径。
                if plan.hasDiscount {
                    Text("¥\(formatAmount(plan.originalPrice))")
                        .font(.system(size: 14))
                        .foregroundStyle(ThemeManager.shared.palette.neutral400)
                        .strikethrough()

                    if let discountText = plan.discountText, !discountText.isEmpty {
                        Text(discountText)
                            .font(.system(size: 12))
                            .foregroundStyle(ThemeManager.shared.palette.semanticWarning)
                    }
                }

                Spacer()
            }

            if let metaText {
                Text(metaText)
                    .font(.system(size: 12))
                    .foregroundStyle(ThemeManager.shared.palette.neutral500)
            }

            if let privilegesText {
                Text(privilegesText)
                    .font(.system(size: 13))
                    .foregroundStyle(ThemeManager.shared.palette.neutral600)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let description = plan.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(ThemeManager.shared.palette.neutral500)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onBuy) {
                Text(isPurchasing ? "处理中…" : "立即开通")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ThemeManager.shared.palette.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(isPurchasing
                                ? ThemeManager.shared.palette.neutral300
                                : ThemeManager.shared.palette.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(isPurchasing)
            .padding(.top, 4)
        }
        .padding(16)
        .background(ThemeManager.shared.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ThemeManager.shared.palette.neutral200, lineWidth: 1)
        )
    }

    /// 「30 天 · 每日 50 次 AI 识别」。两段都可能缺，缺了就不拼那一段，全缺则整行不显示。
    private var metaText: String? {
        var parts: [String] = []
        if let days = plan.validDays, days > 0 {
            parts.append("\(days) 天")
        }
        if let limit = plan.dailyUsageLimit, limit > 0 {
            parts.append("每日 \(limit) 次 AI 识别")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 权益：服务端给的是排好版的短句，逐条加「· 」前缀直接展示。
    private var privilegesText: String? {
        let items = (plan.privileges ?? []).filter { !$0.isEmpty }
        return items.isEmpty ? nil : items.map { "· \($0)" }.joined(separator: "\n")
    }

    /// 金额去掉多余的尾随零：`12.90` 显示成 `12.9`，与 Android 侧
    /// `BigDecimal.stripTrailingZeros().toPlainString()` 的呈现一致。
    private func formatAmount(_ value: Double?) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ""
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
