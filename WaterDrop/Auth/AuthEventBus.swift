import Foundation

@Observable
final class AuthEventBus {
    static let shared = AuthEventBus()

    private(set) var loginRequired: Bool = false

    private init() {}

    func postLoginRequired() {
        Task { @MainActor in
            self.loginRequired = true
        }
    }

    func consumeLoginRequired() {
        loginRequired = false
    }
}
