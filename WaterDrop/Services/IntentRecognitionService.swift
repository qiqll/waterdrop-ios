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
            let result = try await recognizeIntentOnline(text: text)
            if result.type != .unknown {
                return result
            }
        } catch {
            logger.error("Online intent recognition failed: \(error.localizedDescription)")
        }

        // Fallback to local keyword matching
        return recognizeIntentLocal(text: text)
    }

    private func recognizeIntentOnline(text: String) async throws -> IntentResult {
        let response = try await AiAPIService.recognizeIntent(text: text)

        guard response.code == 200, let data = response.data else {
            return IntentResult(type: .unknown, queryText: text)
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

        // Record location
        if lower.contains("放在") || lower.contains("放到") || lower.contains("在") || lower.contains("记录") {
            let itemName = extractItemName(lower)
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

        // Query location
        if lower.contains("在哪") || lower.contains("在哪里") || lower.contains("放哪了") ||
           lower.contains("查询") || lower.contains("找") || lower.contains("哪有") {
            return IntentResult(
                type: .queryLocation,
                itemName: extractItemName(lower),
                queryText: text
            )
        }

        // Update location
        if lower.contains("现在在") || lower.contains("移动到") || lower.contains("搬到") {
            let itemName = extractItemName(lower)
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

        // Delete item
        if lower.contains("删除") || lower.contains("移除") {
            return IntentResult(
                type: .deleteItem,
                itemName: extractItemName(lower),
                queryText: text
            )
        }

        // Query category
        if lower.contains("查看所有") || lower.contains("查询所有") || lower.contains("所有的") {
            return IntentResult(
                type: .queryCategory,
                category: extractCategory(lower)
            )
        }

        return IntentResult(type: .unknown, queryText: text)
    }

    // MARK: - Process User Input

    func processUserInput(_ text: String) async -> String {
        let intent = await recognizeIntent(text: text)

            switch intent.type {
            case .recordLocation:
                if intent.itemName.isEmpty || intent.location.isEmpty {
                    return "抱歉，我没有理解您要存储的物品或位置，请重新描述"
                }
                let category = intent.category.isEmpty ? guessCategory(intent.itemName) : intent.category
                let itemId = await itemRepository.recordItemLocation(
                    name: intent.itemName,
                    location: intent.location,
                    category: category,
                    description: intent.description
                )
                if itemId.isEmpty {
                    return "物品存储失败，请检查网络连接后重试"
                }
                return formatItemRecordResult(
                    itemName: intent.itemName,
                    location: intent.location,
                    category: category,
                    description: intent.description,
                    storeTime: intent.storeTime,
                    storeUser: intent.storeUser
                )

            case .queryLocation:
                if intent.itemName.isEmpty {
                    return "抱歉，我没有理解您要查询的物品，请重新描述"
                }
                let items = await itemRepository.searchItemsByName(intent.itemName)
                if !items.isEmpty {
                    return formatItemQueryResults(items)
                }
                return "抱歉，我不知道 \(intent.itemName) 在哪里"

            case .updateLocation:
                let success = await itemRepository.updateItemLocation(
                    name: intent.itemName,
                    newLocation: intent.location
                )
                if success {
                    return "已更新：\(intent.itemName) 现在在 \(intent.location)"
                }
                return "抱歉，找不到 \(intent.itemName) 的记录"

            case .deleteItem:
                if let item = await itemRepository.getItemByName(intent.itemName) {
                    _pendingDeleteItem = item
                    return "\(Self.deletePendingPrefix)\(intent.itemName)"
                }
                return "抱歉，找不到 \(intent.itemName) 的记录"

            case .queryCategory:
                let items = await itemRepository.getItemsByCategory(intent.category)
                if !items.isEmpty {
                    return formatCategoryQueryResults(intent.category, items)
                }
                return "\(intent.category) 类别下没有物品"

            case .unknown:
                return "当前问题能力正在开发中"
            }
    }

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

    private func extractItemName(_ text: String) -> String {
        let locationMarkers = ["放在", "放到", "在", "现在在"]
        for marker in locationMarkers {
            if let range = text.range(of: marker), range.lowerBound > text.startIndex {
                return String(text[text.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }

        let patterns = ["我的", "的"]
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
        let markers = ["在", "放在", "放到", "现在在"]
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
