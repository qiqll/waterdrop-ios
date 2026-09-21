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

            Spacer()
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
