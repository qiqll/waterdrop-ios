import Foundation

// MARK: - Sync Requests

/// 合并同步请求，对应服务端 `SyncRequest`。
///
/// `clientData` 的 key 是 dataType（服务端要求形如 `^[a-z][a-z0-9_]{0,49}$`，
/// 即小写字母开头、只含小写字母/数字/下划线），value 是任意 JSON 结构。
/// 服务端对 dataType 只做结构校验、没有业务白名单，两端可以自由加新类型。
///
/// `clientVersion` 留空即可：服务端缺失时会回落到 `X-Client-Version` 请求头。
/// 注意它的语义是**服务器数据指纹**（上次响应里的 `serverVersion`），不是 App 版本号。
struct SyncRequestDTO: Encodable {
    let clientData: [String: Any]
    let syncStrategy: String
    let deviceInfo: String?
    let forceSync: Bool
}

/// 上传请求，对应服务端 `SyncUploadRequest`。
struct SyncUploadRequestDTO: Encodable {
    let data: [String: Any]
    let deviceInfo: String?
}

/// 版本检查请求，对应服务端 `VersionCheckRequest`。
struct SyncVersionCheckRequestDTO: Encodable {
    let clientVersion: String?
    let dataTypeVersions: [String: String]?
    let deviceInfo: String?
}

// MARK: - Sync Responses

/// 合并同步响应，对应服务端 `SyncResponse`。
struct SyncResponseDTO: Decodable {
    let data: [String: AnyDecodable]?
    /// 同步后的服务器数据指纹，存下来供下次 `clientVersion` 传回。
    let syncVersion: String?
    let syncTime: String?
    let conflictResolutions: [String: String]?
    let stats: SyncStatsDTO?
}

struct SyncStatsDTO: Decodable {
    let uploadedItems: Int?
    let downloadedItems: Int?
    let conflictedItems: Int?
    let syncDurationMs: Int64?
}

/// 下载响应，对应服务端 `SyncDownloadResponse`。
///
/// 从未上传过数据时 `data` 是**空字典而不是错误**，调用方不必特判。
struct SyncDownloadResponseDTO: Decodable {
    let data: [String: AnyDecodable]?
    let serverVersion: String?
    let lastUpdateTime: String?
    let dataSize: Int64?
    let dataTypeCount: Int?
}

/// 版本检查响应，对应服务端 `VersionCheckResponse`（sync 包下的那个）。
///
/// `needSync` 为 true 的条件是「逐类型版本对不上」**或**「clientVersion 与服务器指纹不等」。
/// 后者兜住「客户端有、服务器没有的新类型」—— 这类项不会出现在 `outdatedDataTypes` 里。
struct SyncVersionCheckResponseDTO: Decodable {
    let needSync: Bool
    let serverVersion: String?
    let outdatedDataTypes: [String: String]?
    let lastSyncTime: String?
    let recommendedSyncStrategy: String?
    let serverTime: String?
}

// MARK: - AnyDecodable

/// 任意 JSON 值的解码包装。
///
/// 同步通道的数据是「dataType → 任意 JSON」，服务端原样存取，
/// 因此客户端这边也只能是动态类型 —— 用不上 `Codable` 的静态结构。
///
/// 之所以自己写而不是用 `Any`：`Decodable` 无法直接解码到 `Any`，
/// 必须有一个 `init(from:)` 的实现来分支处理 6 种 JSON 形态。
/// `Int` 的判断必须排在 `Double` **前面** —— JSON 里 `0` 两者都能解，
/// 先判 `Double` 会把所有整数读成浮点，写回服务端时变成 `0.0`。
struct AnyDecodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyDecodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyDecodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "无法识别的 JSON 值"
            )
        }
    }
}

// MARK: - Encodable Helper

/// `[String: Any]` 无法直接 `Encodable`（`Any` 不满足协议），
/// 用这个包装把字典原样交给编码器。同步请求体的 `clientData` / `data` 需要它。
struct AnyEncodableValue: Encodable {
    let value: Any

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map(AnyEncodableValue.init))
        case let dict as [String: Any]:
            try container.encode(dict.mapValues(AnyEncodableValue.init))
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "无法编码的 JSON 值: \(type(of: value))"
                )
            )
        }
    }
}

// MARK: - Coding Keys

/// `[String: Any]` 字段需要手写编码逻辑，因为 `Encodable` 的自动合成
/// 对 `[String: Any]` 无能为力。这里统一转成 `[String: AnyEncodableValue]` 再编。
extension SyncRequestDTO {
    enum CodingKeys: String, CodingKey {
        case clientData, syncStrategy, deviceInfo, forceSync
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientData.mapValues(AnyEncodableValue.init), forKey: .clientData)
        try container.encode(syncStrategy, forKey: .syncStrategy)
        try container.encodeIfPresent(deviceInfo, forKey: .deviceInfo)
        try container.encode(forceSync, forKey: .forceSync)
    }
}

extension SyncUploadRequestDTO {
    enum CodingKeys: String, CodingKey {
        case data, deviceInfo
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data.mapValues(AnyEncodableValue.init), forKey: .data)
        try container.encodeIfPresent(deviceInfo, forKey: .deviceInfo)
    }
}
