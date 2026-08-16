import SwiftUI

struct ListeningStateView: View {
    let partialText: String

    var body: some View {
        VStack(spacing: 16) {
            Text("正在聆听…")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.primary)

            if !partialText.isEmpty {
                Text(partialText)
                    .font(.system(size: FontSizeManager.shared.currentFontSize.textSize))
                    .foregroundStyle(AppColors.neutral700)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .padding(32)
    }
}
