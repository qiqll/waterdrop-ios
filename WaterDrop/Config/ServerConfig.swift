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
        static let filesUpload = "files/upload"
        static let versionCheck = "version/check"

        // F-012 ②: 数据同步。对应服务端 sync 包下的四个端点。
        static let syncUpload = "sync/upload"
        static let syncDownload = "sync/download"
        static let syncMerge = "sync/sync"
        static let syncVersionCheck = "sync/version/check"

        // F-012 ③: 会员与支付。对应服务端 membership / payment 两个包。
        static let membershipPlans = "membership/plans"
        static let membershipCurrent = "membership/current"
        static let membershipHistory = "membership/history"
        static let membershipPurchase = "membership/purchase"
        static let membershipActivate = "membership/activate"
        static let membershipCancelAutoRenew = "membership/cancel-auto-renew"
        static let membershipCheckPremium = "membership/check-premium"

        static let paymentCreate = "payment/create"
        static let paymentHistory = "payment/history"

        static func membershipPlansByType(_ planType: String) -> String {
            "membership/plans/\(planType.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? planType)"
        }
        static func paymentOrder(_ orderId: String) -> String { "payment/order/\(orderId)" }
        static func paymentCancel(_ orderId: String) -> String { "payment/cancel/\(orderId)" }
        static func paymentRefund(_ orderId: String) -> String { "payment/refund/\(orderId)" }
        static func paymentStatus(_ orderId: String) -> String { "payment/status/\(orderId)" }

        static func itemById(_ id: String) -> String { "items/\(id)" }
        static func itemsByCategory(_ category: String) -> String {
            "items/category/\(category.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? category)"
        }
    }

    // MARK: - Image URL Resolution

    /// 服务端返回的 fileUrl 形如 `/api/files/xxx`，而 baseURL 已含 `/api` 前缀，
    /// 直接拼接会得到重复的 `/api/api/...`。这里提取 scheme+host+port 得到 origin，
    /// 将相对路径拼接为完整 URL。
    static var origin: String {
        if let url = URL(string: baseURL),
           let scheme = url.scheme,
           let host = url.host {
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            if let port = url.port { components.port = port }
            if let resolved = components.string { return resolved }
        }
        return baseURL
    }

    /// 将服务端返回的相对 fileUrl 解析为可用于加载的完整 URL。
    /// 绝对地址（http/https）原样返回；相对地址则拼上 origin。
    static func resolveImageUrl(_ fileUrl: String?) -> String? {
        guard let fileUrl, !fileUrl.isEmpty else { return nil }
        if fileUrl.hasPrefix("http://") || fileUrl.hasPrefix("https://") {
            return fileUrl
        }
        return origin + fileUrl
    }
}
