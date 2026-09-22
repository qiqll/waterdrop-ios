import Foundation

enum AiAPIService {
    static func recognizeIntent(text: String) async throws -> ApiResponse<IntentResultResponse> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.aiIntent,
            method: .POST,
            queryItems: [URLQueryItem(name: "text", value: text)]
        )
    }

    /// 通用问答（F-017 §11.5 修订版）。
    ///
    /// UNKNOWN 兜底走这条而不是 `/ai/help`：help 只能答产品使用问题，
    /// 问「这个季节适合养什么花」会得到「该功能需求当前尚未开发」（实测确认）。
    static func chat(question: String) async throws -> ApiResponse<ChatAnswerResponse> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.aiChat,
            method: .POST,
            body: ChatQuestionDto(question: question)
        )
    }

    static func getTodayUsage() async throws -> ApiResponse<AiUsageTodayResponse> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.aiUsageToday
        )
    }
}
