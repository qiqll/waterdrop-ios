import Foundation

enum ItemAPIService {
    static func createItem(_ request: ItemCreateRequest) async throws -> ApiResponse<ItemDto> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.items,
            method: .POST,
            body: request
        )
    }

    static func getItems() async throws -> ApiResponse<[ItemDto]> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.items
        )
    }

    static func getItem(id: String) async throws -> ApiResponse<ItemDto> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.itemById(id)
        )
    }

    static func updateItem(id: String, _ request: ItemCreateRequest) async throws -> ApiResponse<ItemDto> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.itemById(id),
            method: .PUT,
            body: request
        )
    }

    static func deleteItem(id: String) async throws -> ApiResponse<EmptyData> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.itemById(id),
            method: .DELETE
        )
    }

    static func searchItems(_ request: ItemSearchRequest) async throws -> ApiResponse<PagedResult<ItemDto>> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.itemSearch,
            method: .POST,
            body: request
        )
    }

    static func getItemByName(name: String) async throws -> ApiResponse<ItemDto> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.itemByName,
            queryItems: [URLQueryItem(name: "name", value: name)]
        )
    }

    static func getItemsByCategory(category: String) async throws -> ApiResponse<[ItemDto]> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.itemsByCategory(category)
        )
    }
}
