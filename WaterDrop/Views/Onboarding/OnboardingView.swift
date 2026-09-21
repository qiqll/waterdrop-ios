import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentPage = 0

    private let pages: [(icon: String, title: String, subtitle: String)] = [
        ("mic.fill", "说一句话，记住物品位置", "对着麦克风说「护照放在书桌抽屉里」\n我会帮你记住"),
        ("magnifyingglass", "忘了放哪？问一声就好", "说「护照在哪里」\n我会马上告诉你"),
        ("checkmark.circle.fill", "准备好了", "轻按麦克风按钮\n开始管理你的物品")
    ]

    var body: some View {
        ZStack {
            ThemeManager.shared.palette.background.ignoresSafeArea()

            VStack {
                // Skip button
                HStack {
                    Spacer()
                    if currentPage < pages.count - 1 {
                        Button("跳过") {
                            completeOnboarding()
                        }
                        .font(.wd(.bodyLarge))
                        .foregroundStyle(ThemeManager.shared.palette.neutral600)
                        .padding(.trailing, 24)
                        .padding(.top, 16)
                    }
                }

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        VStack(spacing: 24) {
                            Spacer()

                            Image(systemName: pages[index].icon)
                                .font(.wdHero(size: 64))
                                .foregroundStyle(ThemeManager.shared.palette.primary)

                            Text(pages[index].title)
                                .font(.wd(.headlineLarge, weight: .bold))
                                .foregroundStyle(ThemeManager.shared.palette.neutral800)
                                .multilineTextAlignment(.center)

                            Text(pages[index].subtitle)
                                .font(.wd(.bodyLarge))
                                .foregroundStyle(ThemeManager.shared.palette.neutral600)
                                .multilineTextAlignment(.center)
                                .lineSpacing(6)

                            Spacer()
                        }
                        .padding(.horizontal, 40)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                // Bottom button
                Button(action: {
                    if currentPage < pages.count - 1 {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        completeOnboarding()
                    }
                }) {
                    Text(currentPage < pages.count - 1 ? "下一步" : "开始使用")
                        .font(.wd(.titleLarge, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(ThemeManager.shared.palette.primary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 25))
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "has_completed_onboarding")
        onComplete()
    }
}
