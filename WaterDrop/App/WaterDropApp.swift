import SwiftUI

@main
struct WaterDropApp: App {
    @State private var appState = AppNavigationState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                switch appState.currentScreen {
                case .splash:
                    SplashView {
                        appState.onSplashFinished()
                    }
                case .login:
                    LoginView {
                        appState.onLoginSuccess()
                    }
                case .onboarding:
                    OnboardingView {
                        appState.onOnboardingComplete()
                    }
                case .main:
                    MainView()
                }
            }
            .onChange(of: AuthEventBus.shared.loginRequired) { _, loginRequired in
                if loginRequired {
                    appState.currentScreen = .login
                    AuthEventBus.shared.consumeLoginRequired()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    if case .main = appState.currentScreen {
                        if !AuthStateManager.shared.isAuthenticated {
                            appState.currentScreen = .login
                        }
                    }
                }
            }
        }
    }
}

@Observable
final class AppNavigationState {
    enum Screen {
        case splash, login, onboarding, main
    }

    var currentScreen: Screen = .splash

    func onSplashFinished() {
        let authState = AuthStateManager.shared
        if authState.isAuthenticated && !authState.isTokenExpired {
            currentScreen = .main
        } else if case .expired = authState.state {
            // Try token refresh
            Task {
                let refreshed = await AuthService.shared.refreshAccessToken()
                await MainActor.run {
                    currentScreen = refreshed ? .main : .login
                }
            }
        } else {
            currentScreen = .login
        }
    }

    func onLoginSuccess() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "has_completed_onboarding")
        currentScreen = hasCompletedOnboarding ? .main : .onboarding
    }

    func onOnboardingComplete() {
        currentScreen = .main
    }
}
