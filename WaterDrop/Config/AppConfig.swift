import Foundation

enum AppConfig {
    static var serverBaseURL: String {
        infoPlistValue(for: "SERVER_BASE_URL") ?? "https://your-server.com/api/"
    }

    static var alicloudAppKey: String {
        infoPlistValue(for: "ALICLOUD_APP_KEY") ?? ""
    }

    static var alicloudSchemeCode: String {
        infoPlistValue(for: "ALICLOUD_SCHEME_CODE") ?? ""
    }

    static var alicloudAppSecret: String {
        infoPlistValue(for: "ALICLOUD_APP_SECRET") ?? ""
    }

    static var alicloudAuthSdkInfo: String {
        infoPlistValue(for: "ALICLOUD_AUTH_SDK_INFO") ?? ""
    }

    private static func infoPlistValue(for key: String) -> String? {
        Bundle.main.infoDictionary?[key] as? String
    }
}
