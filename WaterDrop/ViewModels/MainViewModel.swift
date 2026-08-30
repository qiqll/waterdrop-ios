import Foundation
import os.log

@Observable
final class MainViewModel {
    enum UIState {
        case idle
        case listening
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
