import Foundation
import os.log

@Observable
final class HelpViewModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var isLoading: Bool = false

    private let logger = Logger(subsystem: "com.waterdrop.ios", category: "HelpViewModel")

    func sendQuestion(_ question: String) async {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Add user message
        let userMessage = ChatMessage(content: question, isUser: true)
        messages.append(userMessage)
        isLoading = true

        do {
            let response = try await HelpAPIService.askHelp(question: question)
            if response.code == 200, let data = response.data {
                let aiMessage = ChatMessage(
                    content: data.answer ?? "抱歉，我暂时无法回答这个问题",
                    isUser: false,
                    inScope: data.inScope
                )
                messages.append(aiMessage)
            } else {
                let errorMessage = ChatMessage(
                    content: "请求失败，请稍后重试",
                    isUser: false,
                    isError: true
                )
                messages.append(errorMessage)
            }
        } catch {
            logger.error("Help question failed: \(error.localizedDescription)")
            let errorMessage = ChatMessage(
                content: "网络似乎不太好，请再试一次",
                isUser: false,
                isError: true
            )
            messages.append(errorMessage)
        }

        isLoading = false
    }
}
