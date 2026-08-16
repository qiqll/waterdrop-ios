import SwiftUI

struct SplashView: View {
    let onFinished: () -> Void
    @State private var dropOffset: CGFloat = -100
    @State private var dropOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var sloganOpacity: Double = 0

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                // Water drop icon
                Image(systemName: "drop.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(AppColors.primary)
                    .offset(y: dropOffset)
                    .opacity(dropOpacity)

                // App name
                Text("水滴管家")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppColors.neutral800)
                    .opacity(textOpacity)

                // Slogan
                Text("点点滴滴，记在心里")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.neutral600)
                    .opacity(sloganOpacity)

                Spacer()
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "has_launched_before")
        let totalDuration: Double = isFirstLaunch ? 2.8 : 1.2

        // Drop animation with overshoot
        withAnimation(.interpolatingSpring(stiffness: 100, damping: 10).delay(0.1)) {
            dropOffset = 0
            dropOpacity = 1
        }

        // Text fade in
        withAnimation(.easeOut(duration: 0.5).delay(totalDuration * 0.3)) {
            textOpacity = 1
        }

        // Slogan fade in
        withAnimation(.easeOut(duration: 0.5).delay(totalDuration * 0.5)) {
            sloganOpacity = 1
        }

        // Mark as launched and navigate
        UserDefaults.standard.set(true, forKey: "has_launched_before")

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            onFinished()
        }
    }
}
