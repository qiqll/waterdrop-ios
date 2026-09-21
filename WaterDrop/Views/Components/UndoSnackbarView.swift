import SwiftUI

struct UndoSnackbarView: View {
    let itemName: String
    let onUndo: () -> Void
    let isShowing: Bool

    var body: some View {
        if isShowing {
            HStack {
                Text("已删除「\(itemName)」")
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
