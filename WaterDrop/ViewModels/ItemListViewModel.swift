import Foundation

@Observable
final class ItemListViewModel {
    private(set) var items: [Item] = []
    private(set) var showUndoSnackbar: Bool = false
    private(set) var undoItemName: String = ""

    private let itemRepository = ItemRepository.shared
    private var pendingDeleteItem: Item?
    private var undoTimerTask: Task<Void, Never>?

    var groupedItems: [(category: String, items: [Item])] {
        let grouped = Dictionary(grouping: items) { $0.category.isEmpty ? "其他" : $0.category }
        return grouped.sorted { $0.key < $1.key }.map { (category: $0.key, items: $0.value) }
    }

    func refreshItems() async {
        await itemRepository.refreshItems()
        items = itemRepository.allItems
    }

    func scheduleDelete(_ item: Item) {
        pendingDeleteItem = item
        undoItemName = item.name
        showUndoSnackbar = true

        // Remove from local list immediately
        items.removeAll { $0.id == item.id }

        undoTimerTask?.cancel()
        undoTimerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await confirmDelete()
        }
    }

    func confirmDelete() async {
        guard let item = pendingDeleteItem else { return }
        await itemRepository.delete(id: item.id)
        pendingDeleteItem = nil
        undoItemName = ""
        showUndoSnackbar = false
        undoTimerTask?.cancel()
    }

    func cancelDelete() {
        if let item = pendingDeleteItem {
            items.append(item)
            items.sort { $0.name < $1.name }
        }
        pendingDeleteItem = nil
        undoItemName = ""
        showUndoSnackbar = false
        undoTimerTask?.cancel()
    }
}
