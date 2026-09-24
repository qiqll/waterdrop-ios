import SwiftUI

struct ItemCardView: View {
    let item: Item
    /// 编辑保存成功后回调，用于让外层刷新列表（ItemListViewModel 持有独立 items 快照）。
    var onUpdated: () async -> Void = {}

    @State private var showEditSheet = false

    private var categoryIcon: String {
        switch item.category {
        case "文具": return "pencil.and.ruler"
        case "电子产品": return "desktopcomputer"
        case "证件": return "creditcard"
        case "衣物": return "tshirt"
        case "厨房用品": return "fork.knife"
        case "书籍": return "book"
        case "工具": return "wrench.and.screwdriver"
        case "药品": return "cross.case"
        case "珠宝首饰": return "sparkles"
        default: return "cube"
        }
    }

    /// 物品状态标签（F-017-screens §03）。
    ///
    /// 与 Android `ItemListActivity.statusLabelOf` 逐条对应 —— 两端必须一致，
    /// 否则同一件东西在两个平台上叫法不同。
    /// 正常（1）返回 nil，不显示徽章：满屏的「正常」是噪音。
    private var statusLabel: String? {
        switch item.status {
        case 2: return "已借出"
        case 3: return "已丢失"
        case 4: return "已损坏"
        default: return nil
        }
    }

    /// 状态徽章配色。借出/丢失用警示色，损坏用中性色 ——
    /// 「损坏」是既成事实，不是待处理的事，用红色反而像在报警。
    private var statusColors: (fg: Color, bg: Color) {
        switch item.status {
        case 2: return (ThemeManager.shared.palette.semanticWarning,
                        ThemeManager.shared.palette.semanticWarningBg)
        case 3: return (ThemeManager.shared.palette.semanticError,
                        ThemeManager.shared.palette.semanticErrorBg)
        default: return (ThemeManager.shared.palette.neutral600,
                         ThemeManager.shared.palette.surfaceVariant)
        }
    }

    /// F-011：品牌 / 型号 / 序列号拼接成的规格行，全空时返回 nil（整行不显示）。
    private var specLine: String? {
        let parts = [
            item.brand.flatMap { $0.isEmpty ? nil : "品牌：\($0)" },
            item.model.flatMap { $0.isEmpty ? nil : "型号：\($0)" },
            item.serialNumber.flatMap { $0.isEmpty ? nil : "SN：\($0)" }
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Item image (if any), else category icon
            if let imageUrl = item.imageUrl,
               let resolved = ServerConfig.resolveImageUrl(imageUrl) {
                AuthenticatedRemoteImage(urlString: resolved)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: categoryIcon)
                    .font(.wd(.headlineMedium))
                    .foregroundStyle(ThemeManager.shared.palette.primary)
                    .frame(width: 40, height: 40)
                    .background(ThemeManager.shared.palette.primaryLight)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.wd(.titleMedium, weight: .medium))
                    .foregroundStyle(ThemeManager.shared.palette.neutral800)

                Text(item.location)
                    .font(.wd(.bodyMedium))
                    .foregroundStyle(ThemeManager.shared.palette.neutral600)
                    .lineLimit(1)

                // F-011：规格行（有值才显示）
                if let specLine {
                    Text(specLine)
                        .font(.wd(.bodySmall))
                        .foregroundStyle(ThemeManager.shared.palette.neutral500)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // 状态徽章（非正常状态才显示）。
            // 放右侧而不是名称下方：位置是卡片的第二主角，
            // 状态是补充信息，挤在位置下面会让两行都变窄。
            if let statusLabel {
                Text(statusLabel)
                    .font(.wd(.labelMedium))
                    .foregroundStyle(statusColors.fg)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColors.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            showEditSheet = true
        }
        .sheet(isPresented: $showEditSheet) {
            ItemEditSheetView(item: item) {
                await onUpdated()
            }
        }
    }
}
