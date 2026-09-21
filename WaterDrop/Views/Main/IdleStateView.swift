import SwiftUI

struct IdleStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "drop.fill")
                .font(.wdHero(size: 48))
                .foregroundStyle(ThemeManager.shared.palette.primary.opacity(0.3))

            Text("有什么需要我帮你记住的吗？")
                .font(.wd(.bodyLarge, userScale: FontSizeManager.shared.currentFontSize.scaleFactor))
                .foregroundStyle(ThemeManager.shared.palette.neutral600)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
