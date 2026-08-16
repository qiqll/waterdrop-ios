import Foundation

struct HelpRequestDto: Codable {
    let question: String
}

struct HelpResponseDto: Codable {
    let answer: String?
    let inScope: Bool
    let featureRequestId: String?
}

struct AiUsageRecordDto: Codable {
    let id: String?
    let userId: String?
    let requestId: String?
    let model: String?
    let requestType: String?
    let inputText: String?
    let outputText: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let cost: Double?
    let responseTime: Int?
    let status: Int?
    let errorMessage: String?
    let createTime: String?
    let updateTime: String?
}
