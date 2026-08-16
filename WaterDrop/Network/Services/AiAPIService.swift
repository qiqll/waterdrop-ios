import Foundation

enum AiAPIService {
    static func recognizeIntent(text: String) async throws -> ApiResponse<IntentResultResponse> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.aiIntent,
            method: .POST,
            queryItems: [URLQueryItem(name: "text", value: text)]
        )
    }

    static func getTodayUsage() async throws -> ApiResponse<AiUsageTodayResponse> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.aiUsageToday
        )
    }
}
