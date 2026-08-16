import Foundation

enum ServerConfig {
    static var baseURL: String { AppConfig.serverBaseURL }

    enum Timeout {
        static let connect: TimeInterval = 10
        static let read: TimeInterval = 30
    }

    enum Endpoints {
        static let alicloudAuthToken = "users/aliyun/auth-token"
        static let alicloudLogin = "users/aliyun/login"
        static let refreshToken = "users/refresh"
        static let logout = "users/logout"
        static let userProfile = "users/profile"
        static let items = "items"
        static let itemSearch = "items/search"
        static let itemByName = "items/search/by-name"
        static let aiIntent = "ai/intent"
        static let aiUsageToday = "ai/usage/today"
        static let aiHelp = "ai/help"
        static let aiHelpHistory = "ai/help/history"

        static func itemById(_ id: String) -> String { "items/\(id)" }
        static func itemsByCategory(_ category: String) -> String {
            "items/category/\(category.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? category)"
        }
    }
}
