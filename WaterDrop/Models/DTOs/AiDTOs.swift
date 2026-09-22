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

// MARK: - Chat（通用问答，F-017 §11.5 修订版）

/// 通用问答请求。
///
/// 与 `HelpRequestDto` 形状相同但语义不同：help 问的是「产品怎么用」，
/// chat 问的是「随便一句」。服务端有两条独立的端点与提示词。
struct ChatQuestionDto: Codable {
    let question: String
}

/// 通用问答响应。
///
/// **没有 `inScope`** —— help 用它表达「超出产品能力范围」并据此记入功能需求表；
/// chat 面向通用知识，不存在「超出范围」这回事。
struct ChatAnswerResponse: Codable {
    let answer: String
    /// true 表示这是服务端兜底文案而非模型作答。
    ///
    /// ⚠️ 与 `IntentResult.degraded`（离线降级）**同名不同源**，不要混用。
    let degraded: Bool
}
