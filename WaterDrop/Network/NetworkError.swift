import Foundation

enum NetworkError: Error, LocalizedError {
    case unauthorized
    case serverError(statusCode: Int)
    case networkUnavailable
    case timeout
    case decodingFailed(Error)
    case invalidResponse
    case businessError(code: Int, message: String)
    case unknown(Error)

    var errorDescription: String? { userMessage }

    var userMessage: String {
        switch self {
        case .unauthorized:
            return "认证已过期，请重新登录"
        case .serverError:
            return "服务器繁忙，请稍后重试"
        case .networkUnavailable:
            return "网络连接失败，请检查网络设置"
        case .timeout:
            return "连接超时，请稍后重试"
        case .decodingFailed:
            return "数据解析失败"
        case .invalidResponse:
            return "服务器响应异常"
        case .businessError(_, let message):
            return message
        case .unknown:
            return "未知错误，请稍后重试"
        }
    }
}
