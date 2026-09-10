import Foundation
import os.log

@Observable
final class ItemRepository {
    static let shared = ItemRepository()

    private(set) var allItems: [Item] = []
    private let logger = Logger(subsystem: "com.waterdrop.ios", category: "ItemRepository")

    private init() {}

    // MARK: - Refresh

    func refreshItems() async {
        do {
            let response = try await ItemAPIService.getItems()
            if response.code == 200, let data = response.data {
                allItems = data.map { $0.toItem() }
                logger.info("Refreshed items: \(data.count) total")
            } else {
                logger.error("Refresh items business error: \(response.message)")
            }
        } catch {
            logger.error("Refresh items failed: \(error.localizedDescription)")
        }
    }

    // MARK: - CRUD

    func insert(_ request: ItemCreateRequest) async -> String {
        do {
            let response = try await ItemAPIService.createItem(request)
            if response.code == 200, let data = response.data {
                await refreshItems()
                return data.id
            }
        } catch {
            logger.error("Create item failed: \(error.localizedDescription)")
        }
        return ""
    }

    /// 更新物品。返回是否成功（成功时已刷新 allItems）。
    /// 仅供 ItemEditSheetView 等直接面向用户更新的路径使用，调用方据此决定是否保留/撤销编辑状态。
    func update(id: String, _ request: ItemCreateRequest) async -> Bool {
        do {
            let response = try await ItemAPIService.updateItem(id: id, request)
            if response.code == 200 {
                await refreshItems()
                return true
            }
            logger.error("Update item business error: \(response.message)")
        } catch {
            logger.error("Update item failed: \(error.localizedDescription)")
        }
        return false
    }

    func delete(id: String) async {
        do {
            let response = try await ItemAPIService.deleteItem(id: id)
            if response.code == 200 {
                await refreshItems()
            }
        } catch {
            logger.error("Delete item failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Search

    func searchItemsByName(_ name: String) async -> [Item] {
        do {
            let request = ItemSearchRequest(keyword: name)
            let response = try await ItemAPIService.searchItems(request)
            if response.code == 200, let data = response.data {
                return data.records.map { $0.toItem() }
            }
        } catch {
            logger.error("Search items failed: \(error.localizedDescription)")
        }
        return []
    }

    func getItemByName(_ name: String) async -> Item? {
        do {
            let response = try await ItemAPIService.getItemByName(name: name)
            if response.code == 200, let data = response.data {
                return data.toItem()
            }
        } catch {
            logger.error("Get item by name failed: \(error.localizedDescription)")
        }
        return nil
    }

    func getItemsByCategory(_ category: String) async -> [Item] {
        do {
            let response = try await ItemAPIService.getItemsByCategory(category: category)
            if response.code == 200, let data = response.data {
                return data.map { $0.toItem() }
            }
        } catch {
            logger.error("Get items by category failed: \(error.localizedDescription)")
        }
        return []
    }

    // MARK: - Smart Operations

    func recordItemLocation(name: String, location: String, category: String = "其他", description: String = "") async -> String {
        // Check if item exists, update or create
        if let existing = await getItemByName(name) {
            let request = ItemCreateRequest(
                name: name,
                location: location,
                description: description.isEmpty ? existing.description : description,
                category: category,
                imageUrl: existing.imageUrl
            )
            do {
                let response = try await ItemAPIService.updateItem(id: existing.id, request)
                if response.code == 200 {
                    await refreshItems()
                    return existing.id
                }
            } catch {
                logger.error("Update item location failed: \(error.localizedDescription)")
            }
            return ""
        } else {
            let request = ItemCreateRequest(
                name: name,
                location: location,
                description: description.isEmpty ? nil : description,
                category: category
            )
            return await insert(request)
        }
    }

    func updateItemLocation(name: String, newLocation: String) async -> Bool {
        guard let item = await getItemByName(name) else { return false }
        let request = ItemCreateRequest(
            name: item.name,
            location: newLocation,
            description: item.description,
            category: item.category,
            imageUrl: item.imageUrl
        )
        do {
            let response = try await ItemAPIService.updateItem(id: item.id, request)
            if response.code == 200 {
                await refreshItems()
                return true
            }
        } catch {
            logger.error("Update item location failed: \(error.localizedDescription)")
        }
        return false
    }
}
