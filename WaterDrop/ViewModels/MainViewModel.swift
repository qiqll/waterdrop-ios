import Foundation
import os.log

@Observable
final class MainViewModel {
    enum UIState {
        case idle
        case listening
        /// 「正在理解…」（F-017 §4.2）。
        ///
        /// 从「松手」到「出结果」之间要经过 ASR 终稿 → 网络 → 服务端 AI → 返回 **两次往返**。
        /// 在此之前这段是无反馈的空窗期，用户会以为没听见而重复按。
        ///
        /// 这是 F-017 四态设计里**唯一新增**的状态 —— 其余三态（idle/listening/result）
        /// 双端原本就有，只是都没有表达这一段。
        case processing
        case result
    }

    private(set) var uiState: UIState = .idle
    private(set) var processedResult: String = ""
    private(set) var errorMessage: String = ""
    private(set) var showUndoSnackbar: Bool = false
    private(set) var pendingDeleteItemName: String = ""

    let speechManager = SpeechRecognitionManager()
    private let intentService = IntentRecognitionService.shared
    private let itemRepository = ItemRepository.shared
    private let logger = Logger(subsystem: "com.waterdrop.ios", category: "MainViewModel")
    private var autoResetTask: Task<Void, Never>?
    private var undoTimerTask: Task<Void, Never>?
    private var pendingDeleteItem: Item?

    // MARK: - Voice Input

    func processVoiceInput(_ text: String) async {
        guard !text.isEmpty else {
            errorMessage = "没听清楚，可以再说一次吗？"
            uiState = .result
            scheduleAutoReset()
            return
        }

        // F-017 §4.2：进入「理解中」，消除松手后的零反馈空窗期。
        // 放到 await 之前，让 UI 在第一次网络往返开始前就切换过去。
        uiState = .processing

        let result = await intentService.processUserInput(text)

        if result.hasPrefix(IntentRecognitionService.deletePendingPrefix) {
            let itemName = String(result.dropFirst(IntentRecognitionService.deletePendingPrefix.count))
            if let item = intentService.consumePendingDeleteItem() {
                scheduleDelete(item)
            }
            processedResult = "确定要删除「\(itemName)」的记录吗？"
        } else {
            processedResult = result
        }

        errorMessage = ""
        uiState = .result
        scheduleAutoReset()
    }

    // MARK: - Delete Management

    func scheduleDelete(_ item: Item) {
        pendingDeleteItem = item
        pendingDeleteItemName = item.name
        showUndoSnackbar = true

        undoTimerTask?.cancel()
        undoTimerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await confirmDelete()
        }
    }

    func confirmDelete() async {
        guard let item = pendingDeleteItem else { return }
        // Snapshot the id up-front and clear the pending slot before the await, so a
        // concurrent flush (e.g. onDisappear) can't double-delete the same item.
        let id = item.id
        pendingDeleteItem = nil
        pendingDeleteItemName = ""
        showUndoSnackbar = false
        undoTimerTask?.cancel()

        await itemRepository.delete(id: id)
    }

    func cancelDelete() {
        pendingDeleteItem = nil
        pendingDeleteItemName = ""
        showUndoSnackbar = false
        undoTimerTask?.cancel()
    }

    func flushPendingDelete() {
        guard let item = pendingDeleteItem else { return }
        let id = item.id
        pendingDeleteItem = nil
        showUndoSnackbar = false
        Task {
            await itemRepository.delete(id: id)
        }
    }

    // MARK: - Auto Reset

    func scheduleAutoReset() {
        autoResetTask?.cancel()
        autoResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            resetToIdle()
        }
    }

    func resetToIdle() {
        uiState = .idle
        processedResult = ""
        errorMessage = ""
    }

    func setListening() {
        autoResetTask?.cancel()
        uiState = .listening
    }
}
