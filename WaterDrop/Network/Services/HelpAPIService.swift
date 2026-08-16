import Foundation

enum HelpAPIService {
    static func askHelp(question: String) async throws -> ApiResponse<HelpResponseDto> {
        let request = HelpRequestDto(question: question)
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.aiHelp,
            method: .POST,
            body: request
        )
    }

    static func getHelpHistory(page: Int = 1, size: Int = 20) async throws -> ApiResponse<PagedResult<AiUsageRecordDto>> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.aiHelpHistory,
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "size", value: String(size))
            ]
        )
    }
}
