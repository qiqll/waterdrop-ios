import Foundation
import os.log

final class IntentRecognitionService {
    static let shared = IntentRecognitionService()

    private let itemRepository = ItemRepository.shared
    private let logger = Logger(subsystem: "com.waterdrop.ios", category: "IntentRecognition")

    static let deletePendingPrefix = "DELETE_PENDING:"

    private var _pendingDeleteItem: Item?

    private init() {}

    // MARK: - Intent Types

    enum IntentType: String {
        case recordLocation = "RECORD_LOCATION"
        case queryLocation = "QUERY_LOCATION"
        case updateLocation = "UPDATE_LOCATION"
        case deleteItem = "DELETE_ITEM"
        case queryCategory = "QUERY_CATEGORY"
        case unknown = "UNKNOWN"
    }

    struct IntentResult {
        let type: IntentType
        var itemName: String = ""
        var location: String = ""
        var category: String = ""
        var description: String = ""
        var storeTime: Date = Date()
        var storeUser: String = ""
        var queryText: String = ""
        var degraded: Bool = false   // 对齐 Android：仅传输失败降级时置 true
    }

    // MARK: - Pending Delete

    func consumePendingDeleteItem() -> Item? {
        let item = _pendingDeleteItem
        _pendingDeleteItem = nil
        return item
    }

    // MARK: - Recognize Intent

    func recognizeIntent(text: String) async -> IntentResult {
        // Try online API first
        do {
            return try await recognizeIntentOnline(text: text)
        } catch {
            logger.error("Online intent recognition failed: \(error.localizedDescription)")
            // 对齐 Android：仅网络/服务异常时降级到本地关键词，并标记 degraded
            var result = recognizeIntentLocal(text: text)
            result.degraded = true
            return result
        }
    }

    /// 对齐 Android：本地关键词兜底时反馈给用户。
    enum IntentRecognitionError: LocalizedError {
        case serverError

        var errorDescription: String? {
            switch self {
            case .serverError: return "意图识别服务返回异常"
            }
        }
    }

    private func recognizeIntentOnline(text: String) async throws -> IntentResult {
        let response = try await AiAPIService.recognizeIntent(text: text)

        guard response.code == 200, let data = response.data else {
            throw IntentRecognitionError.serverError
        }

        let intentType = IntentType(rawValue: data.type) ?? .unknown

        return IntentResult(
            type: intentType,
            itemName: data.itemName ?? "",
            location: data.location ?? "",
            category: (data.category?.isEmpty ?? true) ? guessCategory(data.itemName ?? "") : (data.category ?? ""),
            storeUser: getCurrentUser(),
            queryText: text
        )
    }

    private func recognizeIntentLocal(text: String) -> IntentResult {
        let lower = text.lowercased()

        // 1. Unambiguous question forms. Checked before the record branch, because
        //    "护照在哪" also contains "在" and would otherwise be read as a record.
        if lower.contains("在哪") || lower.contains("在哪里") || lower.contains("哪去了") ||
           lower.contains("放哪了") || lower.contains("哪有") || lower.contains("放哪里") {
            return IntentResult(
                type: .queryLocation,
                itemName: extractItemName(lower, stripping: ["找一个", "找一下", "查找", "查询", "寻找", "找"]),
                queryText: text
            )
        }

        // 2. Explicit record verbs. "记录一下" is stripped, but bare "记录" is not —
        //    "记录本" is a noun, so stripping it would corrupt the item name. "找到"/"找"
        //    are stripped too, for compound "找到钥匙放在玄关" → "钥匙".
        if lower.contains("放在") || lower.contains("放到") || lower.contains("记录一下") || lower.contains("记录") {
            let itemName = extractItemName(lower, stripping: ["找到", "把", "将", "记录一下"])
            let location = extractLocation(lower)
            return IntentResult(
                type: .recordLocation,
                itemName: itemName,
                location: location,
                category: guessCategory(itemName),
                storeUser: getCurrentUser(),
                queryText: text
            )
        }

        // Update location
        if lower.contains("现在在") || lower.contains("移动到") || lower.contains("搬到") {
            let itemName = extractItemName(lower, stripping: ["把", "将", "搬到"])
            let location = extractLocation(lower)
            if !itemName.isEmpty && !location.isEmpty {
                return IntentResult(
                    type: .updateLocation,
                    itemName: itemName,
                    location: location,
                    queryText: text
                )
            }
        }

        // Query category — before the generic "找"/"查询" catch, so "查询所有钥匙"
        // reads as a category query rather than a single-item lookup.
        if lower.contains("查看所有") || lower.contains("查询所有") || lower.contains("所有的") {
            return IntentResult(
                type: .queryCategory,
                category: extractCategory(lower)
            )
        }

        // 3. "找"/"查询" with no explicit record verb — a single-item lookup.
        if lower.contains("找") || lower.contains("查询") {
            return IntentResult(
                type: .queryLocation,
                itemName: extractItemName(lower, stripping: ["找一个", "找一下", "查找", "查询", "寻找", "找"]),
                queryText: text
            )
        }

        // 4. Bare "在" as a location statement, e.g. "钥匙在玄关" → record.
        if lower.contains("在") {
            let itemName = extractItemName(lower, stripping: ["把", "将"])
            let location = extractLocation(lower)
            return IntentResult(
                type: .recordLocation,
                itemName: itemName,
                location: location,
                category: guessCategory(itemName),
                storeUser: getCurrentUser(),
                queryText: text
            )
        }

        // Delete item
        if lower.contains("删除") || lower.contains("移除") {
            return IntentResult(
                type: .deleteItem,
                itemName: extractItemName(lower, stripping: ["删除", "移除"]),
                queryText: text
            )
        }

        return IntentResult(type: .unknown, queryText: text)
    }

    // MARK: - Process User Input

    func processUserInput(_ text: String) async -> String {
        let intent = await recognizeIntent(text: text)
        let reply: String

            switch intent.type {
            case .recordLocation:
                if intent.itemName.isEmpty || intent.location.isEmpty {
                    reply = "抱歉，我没有理解您要存储的物品或位置，请重新描述"
                } else {
                    let category = intent.category.isEmpty ? guessCategory(intent.itemName) : intent.category
                    let itemId = await itemRepository.recordItemLocation(
                        name: intent.itemName,
                        location: intent.location,
                        category: category,
                        description: intent.description
                    )
                    if itemId.isEmpty {
                        reply = "物品存储失败，请检查网络连接后重试"
                    } else {
                        reply = formatItemRecordResult(
                            itemName: intent.itemName,
                            location: intent.location,
                            category: category,
                            description: intent.description,
                            storeTime: intent.storeTime,
                            storeUser: intent.storeUser
                        )
                    }
                }

            case .queryLocation:
                if intent.itemName.isEmpty {
                    reply = "抱歉，我没有理解您要查询的物品，请重新描述"
                } else {
                    let items = await itemRepository.searchItemsByName(intent.itemName)
                    if !items.isEmpty {
                        reply = formatItemQueryResults(items)
                    } else {
                        reply = "抱歉，我不知道 \(intent.itemName) 在哪里"
                    }
                }

            case .updateLocation:
                let success = await itemRepository.updateItemLocation(
                    name: intent.itemName,
                    newLocation: intent.location
                )
                if success {
                    reply = "已更新：\(intent.itemName) 现在在 \(intent.location)"
                } else {
                    reply = "抱歉，找不到 \(intent.itemName) 的记录"
                }

            case .deleteItem:
                if let item = await itemRepository.getItemByName(intent.itemName) {
                    _pendingDeleteItem = item
                    reply = "\(Self.deletePendingPrefix)\(intent.itemName)"
                } else {
                    reply = "抱歉，找不到 \(intent.itemName) 的记录"
                }

            case .queryCategory:
                let items = await itemRepository.getItemsByCategory(intent.category)
                if !items.isEmpty {
                    reply = formatCategoryQueryResults(intent.category, items)
                } else {
                    reply = "\(intent.category) 类别下没有物品"
                }

            case .unknown:
                // F-017 §3.2（D2）：五类物品意图都没命中时，兜底到开放问答。
                //
                // 这样「问一句」（如「这个季节适合养什么花」）无需新增意图 ——
                // QUERY_LOCATION / QUERY_CATEGORY 答的是**库里的结构化事实**，
                // 而 /ai/help 才是**通用知识问答**，两者是不同的能力。
                // 先识别、识别不出再问，用户不必知道这条分界。
                //
                // 但离线降级时不要再发这次请求：degraded=true 的含义就是
                // 「服务端不可达」，此刻再调 help 只会白等一次超时。
                reply = intent.degraded
                    ? "我没太听懂，换个说法再试试？比如「钥匙放在玄关了」"
                    : await askChatOrFallback(text)
            }

        // 对齐 Android：仅降级识别时添加文本前缀提示
        if intent.degraded && !reply.hasPrefix(Self.deletePendingPrefix) {
            return "⚠️ 当前网络不佳，已使用离线识别（结果可能不准）\n\n\(reply)"
        }
        return reply
    }

    // MARK: - UNKNOWN 兜底

    /// UNKNOWN 兜底：转通用问答（F-017 §3.2 / 决策 D2，**2026-09-22 修订**）。
    ///
    /// ## 为什么从 `/ai/help` 改成 `/ai/chat`
    ///
    /// 初版接的是 `/ai/help`，但实测发现它的职责被提示词**限定在产品帮助文档内**
    /// （`HelpServiceImpl` 的 system prompt 明写「根据以下帮助文档回答用户的使用问题」），
    /// 超出范围一律返回「该功能需求当前尚未开发」，并**把问题记入功能需求表**。
    /// 于是「这个季节适合养什么花」得到的是一句答非所问的产品话术，
    /// 还在库里留下一条被自动分类为「植物养护」的伪需求。
    ///
    /// `/ai/chat` 是为此新开的通用问答路径：不注入帮助文档、不判定 inScope、
    /// 不写功能需求表，由模型按通用知识作答。
    ///
    /// ## 覆盖范围
    ///
    /// 产品使用类与通用知识类**都能答**（实测：三种问法均返回具体回答）。
    /// 唯一不适合的是需要实时数据的（天气、股价）—— 模型会说明自己查不了。
    ///
    /// - Parameter userInput: 用户原话
    /// - Returns: 回答，或提示换种说法的兜底文案
    private func askChatOrFallback(_ userInput: String) async -> String {
        do {
            let response = try await AiAPIService.chat(question: userInput)
            guard response.code == 200, let data = response.data else {
                logger.warning("chat 兜底失败：code=\(response.code)")
                return Self.unknownFallbackReply
            }
            // degraded 表示服务端也没答上来（模型调用失败），它给的是兜底文案。
            // 照常展示即可 —— 服务端已经保证 answer 不会是空串。
            return data.answer.isEmpty ? Self.unknownFallbackReply : data.answer
        } catch {
            logger.error("chat 兜底异常：\(error.localizedDescription)")
            return Self.unknownFallbackReply
        }
    }

    /// 兜底文案。两端共用同一句 —— 用户看到的话术不该因平台而异。
    static let unknownFallbackReply = "我没太听懂，换个说法再试试？比如「钥匙放在玄关了」"

    // MARK: - Formatting

    private func formatItemRecordResult(itemName: String, location: String, category: String, description: String, storeTime: Date, storeUser: String) -> String {
        var result = "物品记录成功\n"
        result += "━━━━━━━━━━━━━━━━\n"
        result += "物品名称：\(itemName)\n"
        result += "存放位置：\(location)\n"
        result += "物品类别：\(category)\n"
        if !description.isEmpty {
            result += "物品描述：\(description)\n"
        }
        result += "存储时间：\(storeTime.formatted(as: "yyyy-MM-dd HH:mm:ss"))\n"
        result += "存储人员：\(storeUser)"
        return result
    }

    private func formatItemQueryResults(_ items: [Item]) -> String {
        var result = ""
        if items.count == 1 {
            let item = items[0]
            result += "查询结果\n"
            result += "━━━━━━━━━━━━━━━━\n"
            result += "物品名称：\(item.name)\n"
            result += "存放位置：\(item.location)\n"
            result += "物品类别：\(item.category)\n"
            if !item.description.isEmpty {
                result += "物品描述：\(item.description)\n"
            }
            result += "存储时间：\(item.createTime)\n"
            result += "存储人员：\(item.operatorUser)"
        } else {
            result += "查询结果（共找到 \(items.count) 条记录）\n"
            result += "━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            for (index, item) in items.enumerated() {
                result += "\n\(index + 1). \(item.name)\n"
                result += "   位置：\(item.location)\n"
                result += "   类别：\(item.category)\n"
                result += "   时间：\(item.createTime)"
                if index < items.count - 1 { result += "\n" }
            }
        }
        return result
    }

    private func formatCategoryQueryResults(_ category: String, _ items: [Item]) -> String {
        var result = "\(category) 类别物品（共 \(items.count) 件）\n"
        result += "━━━━━━━━━━━━━━━━━━━━━━━━\n"
        for (index, item) in items.enumerated() {
            result += "\(index + 1). \(item.name) -> \(item.location)"
            if index < items.count - 1 { result += "\n" }
        }
        return result
    }

    // MARK: - Text Extraction

    /// Extract the item name from an utterance.
    ///
    /// `stripping` is the caller-supplied list of leading action verbs to remove, so a
    /// noun that happens to start with a verb (e.g. "记录本") is never corrupted. The
    /// possessives "我的"/"把"/"将" are always stripped; everything else uses the given list.
    private func extractItemName(_ text: String, stripping actionPrefixes: [String]) -> String {
        var text = text

        // Possessive/object markers are always safe to strip.
        if text.hasPrefix("我的") { text = String(text.dropFirst(2)) }
        if text.hasPrefix("把") { text = String(text.dropFirst(1)) }
        if text.hasPrefix("将") { text = String(text.dropFirst(1)) }

        // Strip only what the caller says is an action verb for this intent.
        for prefix in actionPrefixes where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }

        // "记录本放在桌上" → "记录本" (location marker cuts off after the noun).
        // Most-specific markers first: "现在在"/"放在"/"放到" all contain "在", so a bare
        // "在" checked before them would split "手机现在在玄关" as "手机现"/"在玄关".
        let locationMarkers = ["现在在", "放在", "放到", "在"]
        for marker in locationMarkers {
            if let range = text.range(of: marker), range.lowerBound > text.startIndex {
                return String(text[text.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }

        // "我的护照" → strip possessive (handled above) then take the noun before "在"
        let patterns = ["的"]
        for pattern in patterns {
            if let range = text.range(of: pattern) {
                let afterPattern = text[range.upperBound...]
                let endMarkers = [" ", "，", "。", "、", "在", "放", "现在", "删除"]
                var endIndex = afterPattern.endIndex
                for marker in endMarkers {
                    if let markerRange = afterPattern.range(of: marker) {
                        if markerRange.lowerBound < endIndex {
                            endIndex = markerRange.lowerBound
                        }
                    }
                }
                let itemName = String(afterPattern[afterPattern.startIndex..<endIndex]).trimmingCharacters(in: .whitespaces)
                if !itemName.isEmpty { return itemName }
            }
        }

        let words = text.components(separatedBy: CharacterSet(charactersIn: " ，。、"))
        for word in words {
            let trimmed = word.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 2 && !isStopWord(trimmed) {
                return trimmed
            }
        }

        return ""
    }

    private func extractLocation(_ text: String) -> String {
        // Most-specific first: "现在在"/"放在"/"放到" all contain "在", so a bare "在"
        // checked before them would truncate "手机现在在玄关" as location "在玄关".
        let markers = ["现在在", "放在", "放到", "在"]
        for marker in markers {
            if let range = text.range(of: marker) {
                let afterMarker = text[range.upperBound...]
                let endMarkers = ["，", "。", "、"]
                var endIndex = afterMarker.endIndex
                for endMarker in endMarkers {
                    if let markerRange = afterMarker.range(of: endMarker) {
                        if markerRange.lowerBound < endIndex {
                            endIndex = markerRange.lowerBound
                        }
                    }
                }
                let location = String(afterMarker[afterMarker.startIndex..<endIndex]).trimmingCharacters(in: .whitespaces)
                if !location.isEmpty { return location }
            }
        }
        return ""
    }

    private func extractCategory(_ text: String) -> String {
        let markers = ["所有", "所有的", "查看所有", "查询所有"]
        for marker in markers {
            if let range = text.range(of: marker) {
                let after = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !after.isEmpty { return after }
            }
        }
        return ""
    }

    // MARK: - Category Guessing

    func guessCategory(_ itemName: String) -> String {
        let categoryKeywords: [String: [String]] = [
            "文具": ["笔", "本", "纸", "尺", "橡皮", "笔记本", "文件夹"],
            "电子产品": ["手机", "电脑", "平板", "充电器", "耳机", "相机", "电视"],
            "证件": ["身份证", "护照", "驾照", "学生证", "工作证", "银行卡", "信用卡"],
            "衣物": ["衣服", "裤子", "鞋", "袜子", "帽子", "围巾", "手套"],
            "厨房用品": ["锅", "碗", "筷子", "勺子", "刀", "叉", "杯子"],
            "书籍": ["书", "杂志", "报纸", "小说", "教材", "字典"],
            "工具": ["扳手", "螺丝刀", "锤子", "钳子", "尺子", "胶带"],
            "药品": ["药", "药片", "药水", "感冒药", "消炎药", "创可贴"],
            "珠宝首饰": ["戒指", "项链", "手链", "耳环", "手表", "胸针"]
        ]

        for (category, keywords) in categoryKeywords {
            for keyword in keywords {
                if itemName.contains(keyword) {
                    return category
                }
            }
        }

        return "其他"
    }

    private func isStopWord(_ word: String) -> Bool {
        let stopWords = ["的", "了", "在", "是", "我", "你", "他", "她", "它", "们", "和", "与", "或"]
        return stopWords.contains(word)
    }

    private func getCurrentUser() -> String {
        let userPrefs = UserPreferencesManager.shared
        if userPrefs.hasCustomNickname {
            return userPrefs.nickname
        }
        return AuthStateManager.shared.getCurrentUserId() ?? "未登录用户"
    }
}
