import Foundation
import UniformTypeIdentifiers
import os.log

final class BackupManager {
    static let shared = BackupManager()
    private let logger = Logger(subsystem: "com.waterdrop.ios", category: "BackupManager")

    private init() {}

    func exportData() async throws -> URL {
        let items = ItemRepository.shared.allItems
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(items)

        let fileName = "waterdrop_backup_\(Date().formatted(as: "yyyyMMdd_HHmmss")).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: tempURL)

        logger.info("Data exported: \(items.count) items")
        return tempURL
    }

    func importData(from url: URL) async throws -> Int {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let items = try decoder.decode([Item].self, from: data)

        var importedCount = 0
        for item in items {
            let request = ItemCreateRequest(
                name: item.name,
                location: item.location,
                description: item.description,
                category: item.category,
                imageUrl: item.imageUrl,
                remark: item.remark
            )
            let id = await ItemRepository.shared.insert(request)
            if !id.isEmpty {
                importedCount += 1
            }
        }

        logger.info("Data imported: \(importedCount) of \(items.count) items")
        return importedCount
    }
}
