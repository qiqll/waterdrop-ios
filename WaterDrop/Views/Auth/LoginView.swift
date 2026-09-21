import SwiftUI

struct LoginView: View {
    let onLoginSuccess: () -> Void

    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            ThemeManager.shared.palette.background.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // App icon
                Image(systemName: "drop.fill")
                    .font(.wdHero(size: 64))
                    .foregroundStyle(ThemeManager.shared.palette.primary)

                Text("水滴管家")
                    .font(.wd(.headlineLarge, weight: .bold))
                    .foregroundStyle(ThemeManager.shared.palette.neutral800)

                Text("点点滴滴，记在心里")
                    .font(.wd(.bodyMedium))
                    .foregroundStyle(ThemeManager.shared.palette.neutral600)

                Spacer()

                // Login button
                Button(action: handleLogin) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("一键登录")
                            .font(.wd(.titleLarge, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(ThemeManager.shared.palette.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 25))
                }
                .disabled(isLoading)
                .padding(.horizontal, 40)

                // Error message
                if let errorMessage {
                    Text(errorMessage)
                        .font(.wd(.bodyMedium))
                        .foregroundStyle(ThemeManager.shared.palette.semanticError)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                // Terms hint
                Text("登录即表示同意用户协议和隐私政策")
                    .font(.wd(.bodySmall))
                    .foregroundStyle(ThemeManager.shared.palette.neutral400)
                    .padding(.bottom, 40)
            }
        }
        .background(ViewControllerAccessor { vc in
            self.hostViewController = vc
        })
        .onAppear {
            checkExistingAuth()
        }
    }

    @State private var hostViewController: UIViewController?

    private func checkExistingAuth() {
        let authState = AuthStateManager.shared

        if authState.isAuthenticated && !authState.isTokenExpired {
            onLoginSuccess()
            return
        }

        if case .expired = authState.state {
            Task {
                isLoading = true
                let refreshed = await AuthService.shared.refreshAccessToken()
                isLoading = false
                if refreshed {
                    onLoginSuccess()
                }
            }
        }
    }

    private func handleLogin() {
        guard let viewController = hostViewController else {
            errorMessage = "无法获取界面控制器，请重试"
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await AuthService.shared.performAlicloudAuthentication(from: viewController)

                // F-012 ②: 登录成功后拉取云端设置（昵称/主题/字体大小）。
                // 放在这里而不是别处：这是拿到 token 之后、进入主界面前唯一的汇合点，
                // 早于它的任何请求都会因为还没鉴权而被 401 拒掉。
                // 不 await —— pull() 自身是同步的 fire-and-forget（内部起 Task），
                // 设置同步是尽力而为的后台行为，不该让进主页等它。
                SettingsSyncManager.pull()

                await MainActor.run {
                    isLoading = false
                    onLoginSuccess()
                }
            } catch let error as AlicomFusionAuthManager.AlicomFusionError {
                await MainActor.run {
                    isLoading = false
                    switch error {
                    case .userCancelled:
                        // User cancelled, don't show error
                        break
                    default:
                        errorMessage = error.errorDescription
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = (error as? NetworkError)?.userMessage ?? "登录失败，请稍后重试"
                }
            }
        }
    }
}

// MARK: - UIViewController Accessor for SwiftUI

/// Helper to access the hosting UIViewController from SwiftUI
private struct ViewControllerAccessor: UIViewControllerRepresentable {
    let callback: (UIViewController) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        DispatchQueue.main.async {
            if let parent = vc.parent {
                callback(parent)
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if let parent = uiViewController.parent {
            callback(parent)
        }
    }
}
