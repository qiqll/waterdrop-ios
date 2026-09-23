import SwiftUI

/// 底部的「撤销」提示条。
///
/// F-017 §14.1：原先文案写死为「已删除「X」」，只能用于删除。
/// 现在记录也需要同一条提示（「已记下「X」」），所以把文案提为参数 ——
/// 两种场景共用同一套视觉与交互，用户只需要理解一次「刚做的事能反悔」。
struct UndoSnackbarView: View {
    /// 提示文案，例如「已删除「钥匙」」/「已记下「钥匙」」
    let message: String
    let onUndo: () -> Void
    let isShowing: Bool

    var body: some View {
        if isShowing {
            HStack {
                Text(message)
                    .font(.wd(.bodyMedium))
                    .foregroundStyle(.white)

                Spacer()

                Button("撤销") {
                    onUndo()
                }
                .font(.wd(.labelLarge, weight: .bold))
                .foregroundStyle(ThemeManager.shared.palette.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(ThemeManager.shared.palette.neutral800)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

#if DEBUG
#Preview {
    VStack {
        Spacer()
        UndoSnackbarView(
            message: "已记下「钥匙」",
            onUndo: {},
            isShowing: true
        )
    }
}
#endif
