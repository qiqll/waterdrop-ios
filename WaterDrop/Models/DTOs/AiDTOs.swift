import Foundation

// MARK: - Intent Result

struct IntentResultResponse: Codable {
    let type: String
    let itemName: String?
    let location: String?
    let category: String?
    let queryText: String?
}

// MARK: - AI Usage

struct AiUsageTodayResponse: Codable {
    let count: Int
    let cost: Double
    let limit: Int
}
