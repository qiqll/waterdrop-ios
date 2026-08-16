import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let isUser: Bool
    var inScope: Bool = true
    var isError: Bool = false
    let timestamp: Date

    init(content: String, isUser: Bool, inScope: Bool = true, isError: Bool = false, timestamp: Date = Date()) {
        self.content = content
        self.isUser = isUser
        self.inScope = inScope
        self.isError = isError
        self.timestamp = timestamp
    }
}
