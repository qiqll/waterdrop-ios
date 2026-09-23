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

    /// 刚记录成功的物品（F-017 §14.1）。
    ///
    /// 回应页据此提供「撤回」—— 撤回即删除这条。非记录场景为 nil，
    /// 界面据此决定是否显示撤回条。与 Android `lastRecordedItemId` 对应。
    private(set) var lastRecordedItemId: String?
    private(set) var lastRecordedItemName: String = ""

    let speechManager = SpeechRecognitionManager()
    private let intentService = IntentRecognitionService.shared
    private let itemRepository = ItemRepository.shared
    private let logger = Logger(subsystem: "com.waterdrop.ios", category: "MainViewModel")
    private var autoResetTask: Task<Void, Never>?
    /// 记录撤回窗口的计时器（F-017 §14.1）
    private var recordUndoTask: Task<Void, Never>?
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

        let outcome = await intentService.processUserInput(text)

        if let deleteName = outcome.pendingDeleteName {
            if let item = intentService.consumePendingDeleteItem() {
                scheduleDelete(item)
            }
            processedResult = "确定要删除「\(deleteName)」的记录吗？"
        } else {
            // 记录成功时留下 ID 与名称，回应页据此显示「撤回」
            lastRecordedItemId = outcome.createdItemId
            lastRecordedItemName = outcome.createdItemName ?? ""
            processedResult = outcome.reply

            // 开一个 5 秒窗口，与 Android 及删除撤销保持一致。
            // 没有它，撤回条会一直挂着 —— 用户以为「现在还能撤」，
            // 但那条记录早就落库了，点下去只是删掉一条早已生效的记录。
            if outcome.createdItemId != nil {
                scheduleRecordUndoWindow()
            }
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

    /// 撤回刚才那条记录（F-017 §14.1）。
    ///
    /// 语义上等同于删除，所以复用 [ItemRepository.delete] —— 不新造「撤回」接口。
    /// 这样「刚做的事能反悔」在应用里只有一套实现，用户只需理解一次。
    func undoLastRecord() {
        guard let id = lastRecordedItemId else { return }

        // 先清状态再发请求：连点两次不该删两条
        recordUndoTask?.cancel()
        recordUndoTask = nil
        lastRecordedItemId = nil

        Task {
            await itemRepository.delete(id: id)
            processedResult = "已撤回，这条记录没有保存"
        }
    }

    /// 记录已被保留（倒计时走完，用户没撤回）—— 清掉撤回入口。
    func keepLastRecord() {
        recordUndoTask?.cancel()
        recordUndoTask = nil
        lastRecordedItemId = nil
        lastRecordedItemName = ""
    }

    /// 开一个 5 秒的撤回窗口。与 Android `RECORD_UNDO_WINDOW_MS` 一致。
    private func scheduleRecordUndoWindow() {
        recordUndoTask?.cancel()
        recordUndoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            lastRecordedItemId = nil
            lastRecordedItemName = ""
        }
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
        lastRecordedItemId = nil
        lastRecordedItemName = ""
    }

    func setListening() {
        autoResetTask?.cancel()
        uiState = .listening
    }
}
