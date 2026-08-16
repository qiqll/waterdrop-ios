import Foundation

struct ApiResponse<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T?
    let timestamp: String?
    let traceId: String?
}

struct PagedResult<T: Decodable>: Decodable {
    let records: [T]
    let total: Int
    let size: Int
    let current: Int
    let pages: Int
}

struct EmptyData: Decodable {}
