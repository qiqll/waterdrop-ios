import SwiftUI

struct LoginView: View {
    let onLoginSuccess: () -> Void

    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // App icon
                Image(systemName: "drop.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(AppColors.primary)

                Text("水滴管家")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppColors.neutral800)

                Text("点点滴滴，记在心里")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.neutral600)

                Spacer()

                // Login button
                Button(action: handleLogin) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("一键登录")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AppColors.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 25))
                }
                .disabled(isLoading)
                .padding(.horizontal, 40)

                // Error message
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.semanticError)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                // Terms hint
                Text("登录即表示同意用户协议和隐私政策")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.neutral400)
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
