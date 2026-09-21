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

    // MARK: - F-012 ⑥ (D-6) 历史加载

    /// 进入帮助页时拉取历史问答，把最近 20 条记录摊成聊天气泡。对齐 Android
    /// `HelpViewModel.loadHistory()` 的语义，四条守卫一个不少：
    ///
    /// 1. **已有消息就直接返回** —— 用户可能已经在当前会话里问过问题了，
    ///    这时候用历史把界面刷掉等于把用户刚看到的内容抹掉。
    /// 2. **`await` 回来后要再查一次** —— 网络往返期间用户完全可能已经发出了第一个
    ///    问题，第一次检查通过不代表现在还能覆盖。
    /// 3. **记录是倒序的，必须整体反转** —— 服务端 `findByUserIdAndType` 是
    ///    `ORDER BY create_time DESC`（最新在前），聊天视图要的是正序。
    /// 4. **单条记录摊成两个气泡** —— 一次问答在库里是一行，`inputText` 是用户的话、
    ///    `outputText` 是 AI 的回答，空/纯空白的那个跳过，不要留空气泡。
    ///
    /// 失败一律静默：用户是来提问的，不是来看历史加载报错的。历史没加载出来，
    /// 界面退回空态引导语，照样能提问。
    func loadHistory() async {
        guard messages.isEmpty else { return }

        do {
            let response = try await HelpAPIService.getHelpHistory(page: 1, size: 20)
            guard response.code == 200, let paged = response.data else {
                logger.warning("加载帮助历史业务失败: \(response.message)")
                return
            }

            let history = paged.records
                .reversed()
                .flatMap { recordToMessages($0) }

            // 第二次检查：网络往返期间用户可能已经开了新对话
            if !history.isEmpty, messages.isEmpty {
                messages = history
            }
        } catch {
            logger.warning("加载帮助历史异常: \(error.localizedDescription)")
        }
    }

    /// 一条历史记录 → 最多两个气泡（先用户、后 AI）。
    ///
    /// `status == 0` 是服务端的「失败」标记（1-成功 0-失败），失败的 AI 回答同样回显，
    /// 但标成 `isError` 让气泡用错误色 —— 历史里那次失败是真实发生过的，藏掉反而
    /// 让用户以为没问过。
    ///
    /// 不给气泡解析 `createTime`：与 Android 一致，历史消息按加载顺序排列即可，
    /// 不显示时间戳，也就不需要为它引入第二套日期解析（服务端给的是
    /// `yyyy-MM-dd HH:mm:ss`，与 ⑤ 的 ISO 串还不是同一个格式）。
    private func recordToMessages(_ record: AiUsageRecordDto) -> [ChatMessage] {
        var result: [ChatMessage] = []

        if let input = record.inputText, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(ChatMessage(content: input, isUser: true))
        }
        if let output = record.outputText, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(ChatMessage(content: output, isUser: false, isError: record.status == 0))
        }

        return result
    }
}
