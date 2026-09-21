import SwiftUI

/// 「正在理解…」状态（F-017 §4.2）。
///
/// ## 为什么需要它
///
/// 从「松手」到「出结果」要经过 **ASR 终稿 → 网络 → 服务端 AI → 返回** 两次往返。
/// 在此之前这段是无反馈的空窗期，用户会以为没听见而重复按。
/// 这是 F-017 四态设计里唯一新增的状态。
///
/// ## 视觉为什么是「确定性加载环」而不是无限旋转
///
/// 无限旋转的 spinner 传达的是「不知道还要多久」；而这里我们知道这是一次
/// 有限的两跳往返，通常 <2 秒。所以用一段**有起点、绕完即走**的弧：
/// 它表达「马上好」，而不是「等着吧」。
///
/// 弧的角度也刻意配了慢速（1.05s/圈）—— 比系统 spinner 慢，与「正在思考」
/// 的节奏相称，而不是「正在加载」的焦躁感。
struct ProcessingStateView: View {

    /// 用 SwiftUI 环境值而非 `UIAccessibility.isReduceMotionEnabled`：
    /// 前者会在用户**运行期**切换「减弱动态效果」时自动触发重绘，后者只在
    /// 视图重建时读一次。无障碍设置恰恰是用户会边看边调的东西。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 弧的旋转进度。
    @State private var arcRotation: Double = 0

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // 底环：极淡的一圈，给弧一个「轨道」的参照
                Circle()
                    .stroke(
                        ThemeManager.shared.palette.primary.opacity(0.18),
                        lineWidth: 3
                    )
                    .frame(width: 44, height: 44)

                // 进度弧：约 1/4 圈，绕轨道走
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(
                        ThemeManager.shared.palette.primary,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(arcRotation))
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) {
                    arcRotation = 360
                }
            }

            Text("正在理解…")
                .font(.wd(.titleLarge, weight: .semibold))
                .foregroundStyle(ThemeManager.shared.palette.primary)
        }
        .padding(32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在理解")
        // 告知读屏用户这是一段等待，而不是静态内容
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#if DEBUG
struct ProcessingStateView_Previews: PreviewProvider {
    static var previews: some View {
        ProcessingStateView()
            .background(ThemeManager.shared.palette.surface)
    }
}
#endif
