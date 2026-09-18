import SwiftUI

struct PulseAnimationView: View {
    let isAnimating: Bool
    // 默认参数不能引用 `ThemeManager.shared.palette`（实例属性无法用于默认值），
    // 故留一个无害占位；唯一调用点 VoiceFabView 始终显式传色。
    var color: Color = .clear
    var slowMode: Bool = false

    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    var body: some View {
        Circle()
            .fill(color.opacity(0.2))
            .scaleEffect(scale)
            .opacity(opacity)
            .onChange(of: isAnimating) { _, newValue in
                if newValue {
                    startPulse()
                } else {
                    stopPulse()
                }
            }
            .onAppear {
                if isAnimating {
                    startPulse()
                }
            }
    }

    private func startPulse() {
        let duration = slowMode ? 2.0 : 1.0
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
            scale = 1.4
            opacity = 0.3
        }
    }

    private func stopPulse() {
        withAnimation(.easeOut(duration: 0.3)) {
            scale = 1.0
            opacity = 0.0
        }
    }
}
