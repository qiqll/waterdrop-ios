import SwiftUI

struct ItemCardView: View {
    let item: Item

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

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: categoryIcon)
                .font(.system(size: 20))
                .foregroundStyle(AppColors.primary)
                .frame(width: 40, height: 40)
                .background(AppColors.primaryLight)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.neutral800)

                Text(item.location)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.neutral600)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
