import SwiftUI
import UIKit

/// 语音按钮：按住说短句 / 点按连续说（F-017 §14.1）。
///
/// ## 两种按法
///
/// | | 按住 | 点按 |
/// |---|---|---|
/// | 语义 | 说完就走 | 我准备连着说几件 |
/// | 结束 | 松手 | **再点一下** |
/// | 之后 | 回待机 | **继续听下一句** |
///
/// 区分方式：**按压时长**。按下后不足 `tapThreshold` 就抬起 = 单击；
/// 超过则是一次「按住说」，抬起即结束。
///
/// ## 为什么删掉了右滑
///
/// 上一版靠「按住后向右滑过阈值」进入连续模式。问题有二：
/// ① 同一按钮要同时承载「短按/长按/滑动」三种语义，用户学不会；
/// ② 按住本身就要求悬腕，再叠一个横向滑动，单手很难完成。
/// 现在连续模式改用**单击**进入 —— 点一下就能放下手，正是它该有的样子。
///
/// 与 Android `VoiceFabLayout` 是一套设计的两处实现，改动请同步。
struct VoiceFabView: View {
    /// 开始录音（两种按法共用）
    let onPressStart: () -> Void
    /// 按住的松手 —— 一次短句结束
    let onPressRelease: () -> Void
    /// 进入连续聆听
    let onEnterListenMode: () -> Void
    /// 退出连续聆听
    let onExitListenMode: () -> Void

    @State private var fabState: FabState = .idle
    @State private var fabScale: CGFloat = 1.0
    @State private var isPulseAnimating: Bool = false
    @State private var showCoachHint: Bool = false
    @State private var coachHintOpacity: Double = 0

    /// 按下时刻，用于判定单击还是按住。
    @State private var pressStartedAt: Date?

    private let fabSize: CGFloat = 64

    /// 按下到抬起若短于这个时长，判为「单击」。
    ///
    /// 300ms 的依据：低于它几乎不可能是「想按住说一句话」——
    /// 正常人说完三个字也要 600ms 以上。同时它又足够长，
    /// 不会把一次手抖的轻触误判成按住。与 Android 的 `TAP_THRESHOLD_MS` 一致。
    private let tapThreshold: TimeInterval = 0.3

    /// 连续聆听中。
    private var isInListenMode: Bool { fabState == .listenMode }

    enum FabState {
        case idle
        /// 按住说话中（松手即结束）
        case pressing
        /// 连续聆听中（再点一下结束）
        case listenMode
    }

    var body: some View {
        ZStack {
            // Pulse ring
            PulseAnimationView(
                isAnimating: isPulseAnimating,
                color: ThemeManager.shared.palette.recordingActive,
                slowMode: isInListenMode
            )
            .frame(width: fabSize * 1.8, height: fabSize * 1.8)

            // FAB button
            Circle()
                .fill(fabState == .idle ? ThemeManager.shared.palette.accent : ThemeManager.shared.palette.recordingActive)
                .frame(width: fabSize, height: fabSize)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .overlay {
                    Image(systemName: fabState == .idle ? "mic.fill" : "stop.fill")
                        .font(.wd(.headlineLarge))
                        .foregroundStyle(.white)
                }
                .scaleEffect(fabScale)
                .gesture(fabGesture)

            // Coach hint —— 悬在 FAB **上方**。
            //
            // 放在上方而不是下方：拇指按压时在球上，球上方不会被手挡；
            // 而下方紧挨着屏幕边缘，既容易压到手，也容易被 Home Indicator 挤到。
            if showCoachHint {
                Text("按住说一句，或点一下连续说")
                    .font(.wd(.bodySmall))
                    .foregroundStyle(ThemeManager.shared.palette.neutral600)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(ThemeManager.shared.palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    .offset(y: -fabSize - 16)
                    .opacity(coachHintOpacity)
            }
        }
    }

    // MARK: - Gesture

    private var fabGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                // 连续聆听中：这一次触摸是「结束」，不需要判断时长。
                // 由 onEnded 统一处理，这里不做事，避免按下瞬间就退出。
                guard fabState != .listenMode else { return }

                // 只在「刚按下」时启动一次。
                // DragGesture 的 onChanged 会持续回调，不判空会反复触发。
                guard fabState == .idle else { return }

                pressStartedAt = Date()
                // 先按下即开始录 —— 不等判定结果。
                // 理由：判定要等 300ms，而人从按下到开口往往不到 300ms，
                // 等判完再开录会吃掉开头一两个字。
                enterPressingState()
            }
            .onEnded { _ in
                switch fabState {
                case .listenMode:
                    // 再点一下 → 结束连续模式
                    exitListenMode()

                case .pressing:
                    let held = pressStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                    pressStartedAt = nil

                    if held < tapThreshold {
                        // 单击 → 转连续聆听。
                        // 录音不中断（audio 一直在跑），只是语义从「短句」变成「连着说」。
                        enterListenMode()
                    } else {
                        // 按住说完，松手结束
                        onPressRelease()
                        resetFab()
                    }

                case .idle:
                    break
                }
            }
    }

    // MARK: - State Transitions

    private func enterPressingState() {
        fabState = .pressing
        withAnimation(.easeOut(duration: 0.1)) {
            fabScale = 0.85
        }
        isPulseAnimating = true

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        showCoachMarkIfNeeded()

        onPressStart()
    }

    /// 进入连续聆听。**不重新开始录音** —— 音频从 `enterPressingState` 起就在跑，
    /// 这里只是把语义从「按住」升级为「连续」。
    private func enterListenMode() {
        fabState = .listenMode

        // Overshoot bounce animation
        withAnimation(.interpolatingSpring(stiffness: 120, damping: 12)) {
            fabScale = 1.0
        }

        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        isPulseAnimating = true

        onEnterListenMode()
    }

    private func exitListenMode() {
        onExitListenMode()
        resetFab()
    }

    /// 恢复到待机外观。
    func resetFab() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            fabScale = 1.0
        }
        fabState = .idle
        isPulseAnimating = false
        pressStartedAt = nil
    }

    // MARK: - Coach Mark

    private func showCoachMarkIfNeeded() {
        let useCount = UserDefaults.standard.integer(forKey: "voice_fab_use_count")
        guard useCount < 3 else { return }

        showCoachHint = true
        withAnimation(.easeIn(duration: 0.2)) {
            coachHintOpacity = 1
        }
        UserDefaults.standard.set(useCount + 1, forKey: "voice_fab_use_count")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.3)) {
                coachHintOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showCoachHint = false
            }
        }
    }
}
