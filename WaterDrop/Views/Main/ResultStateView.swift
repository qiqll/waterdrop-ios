import SwiftUI

struct ResultStateView: View {
    let result: String
    let errorMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !errorMessage.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(ThemeManager.shared.palette.semanticWarning)
                    Text(errorMessage)
                        .font(.wd(.bodyLarge, userScale: FontSizeManager.shared.currentFontSize.scaleFactor))
                        .foregroundStyle(ThemeManager.shared.palette.semanticError)
                }
            } else {
                Text(result)
                    .font(.wd(.bodyLarge, userScale: FontSizeManager.shared.currentFontSize.scaleFactor))
                    .foregroundStyle(ThemeManager.shared.palette.neutral800)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }
}
