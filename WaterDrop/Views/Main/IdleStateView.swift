import SwiftUI

struct IdleStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "drop.fill")
                .font(.system(size: 48))
                .foregroundStyle(ThemeManager.shared.palette.primary.opacity(0.3))

            Text("有什么需要我帮你记住的吗？")
                .font(.system(size: FontSizeManager.shared.currentFontSize.textSize))
                .foregroundStyle(ThemeManager.shared.palette.neutral600)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
