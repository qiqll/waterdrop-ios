import SwiftUI

struct ListeningStateView: View {
    let partialText: String

    var body: some View {
        VStack(spacing: 16) {
            Text("正在聆听…")
                .font(.wd(.titleLarge, weight: .semibold))
                .foregroundStyle(ThemeManager.shared.palette.primary)

            if !partialText.isEmpty {
                Text(partialText)
                    .font(.wd(.bodyLarge, userScale: FontSizeManager.shared.currentFontSize.scaleFactor))
                    .foregroundStyle(ThemeManager.shared.palette.neutral700)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .padding(32)
    }
}
