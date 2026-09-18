import SwiftUI
import UIKit

struct VoiceFabView: View {
    let onPressStart: () -> Void
    let onPressRelease: () -> Void
    let onSlideToListenMode: () -> Void
    let onExitListenMode: () -> Void

    @State private var fabState: FabState = .idle
    @State private var fabScale: CGFloat = 1.0
    @State private var isPulseAnimating: Bool = false
    @State private var slideProgress: CGFloat = 0
    @State private var showTrack: Bool = false
    @State private var showCoachHint: Bool = false
    @State private var coachHintOpacity: Double = 0
    @State private var isInListenMode: Bool = false

    private let fabSize: CGFloat = 64
    private let slideThreshold: CGFloat = 120

    enum FabState {
        case idle, pressing, sliding, listenMode
    }

    var body: some View {
        ZStack {
            // Slide track
            if showTrack {
                HStack {
                    Spacer()
                    Text("聆听模式")
                        .font(.system(size: 14))
                        .foregroundStyle(ThemeManager.shared.palette.neutral600.opacity(Double(slideProgress)))
                    Image(systemName: "chevron.right")
                        .foregroundStyle(ThemeManager.shared.palette.neutral400.opacity(Double(slideProgress)))
                }
                .padding(.trailing, 24)
                .transition(.opacity)
            }

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
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }
                .scaleEffect(fabScale)
                .gesture(fabGesture)

            // Coach hint
            if showCoachHint {
                Text("按住说话，右滑进入聆听模式")
                    .font(.system(size: 13))
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
            .onChanged { value in
                let translation = value.translation

                if fabState == .idle {
                    // Finger down
                    enterPressingState()
                }

                if fabState == .pressing || fabState == .sliding {
                    let rightSlide = max(0, translation.width)
                    slideProgress = min(1.0, rightSlide / slideThreshold)

                    if rightSlide > slideThreshold && fabState != .listenMode {
                        enterListenMode()
                    } else if fabState != .listenMode {
                        fabState = translation.width > 10 ? .sliding : .pressing
                    }
                }
            }
            .onEnded { _ in
                if fabState == .listenMode || isInListenMode {
                    // In listen mode, tap to stop
                    exitListenMode()
                } else {
                    onPressReleaseAction()
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
        showTrack = true

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Coach hint for first 3 uses
        let useCount = UserDefaults.standard.integer(forKey: "voice_fab_use_count")
        if useCount < 3 {
            showCoachHint = true
            withAnimation(.easeIn(duration: 0.2)) {
                coachHintOpacity = 1
            }
            UserDefaults.standard.set(useCount + 1, forKey: "voice_fab_use_count")

            // Auto dismiss coach hint
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.easeOut(duration: 0.3)) {
                    coachHintOpacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showCoachHint = false
                }
            }
        }

        onPressStart()
    }

    private func enterListenMode() {
        fabState = .listenMode
        isInListenMode = true

        // Overshoot bounce animation
        withAnimation(.interpolatingSpring(stiffness: 120, damping: 12)) {
            fabScale = 1.0
        }

        // Heavy haptic
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        // Slow pulse
        isPulseAnimating = true

        onSlideToListenMode()
    }

    private func exitListenMode() {
        isInListenMode = false
        onExitListenMode()
        resetFab()
    }

    private func onPressReleaseAction() {
        onPressRelease()
        resetFab()
    }

    private func resetFab() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            fabScale = 1.0
        }
        fabState = .idle
        isPulseAnimating = false
        showTrack = false
        slideProgress = 0
    }
}
