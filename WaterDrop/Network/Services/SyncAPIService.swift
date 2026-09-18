import Foundation
import os.log

/// 数据同步 API。
///
/// 对应服务端 `sync` 包下的四个端点（见 `wd_server/docs/api-reference.md` §7）。
/// 全部需要登录态 —— `APIClient` 默认 `requiresAuth: true`，这里不逐条再写。
///
/// 与 Android `SyncApiService.kt` 保持同一套契约：端点、字段名、策略取值
/// 必须逐字一致，两端才能互相看见对方推上去的设置。
enum SyncAPIService {

    private static let logger = Logger(subsystem: "com.yjhome.waterdrop.ios", category: "SyncAPIService")

    /// 合并同步：一次调用完成「读服务器 + 合并 + 写回」，是设置同步的主路径。
    ///
    /// - Parameters:
    ///   - clientData: dataType → 值。本机设置的全部内容。
    ///   - strategy: `server_priority` / `client_priority` / `merge`。
    ///     传 null 或空串服务端会归一化为 `server_priority`；传无法识别的值会被
    ///     422 拒掉而**不会**静默回退，所以这里只传上面三个之一。
    static func sync(
        clientData: [String: Any],
        strategy: String
    ) async throws -> ApiResponse<SyncResponseDTO> {
        let request = SyncRequestDTO(
            clientData: clientData,
            syncStrategy: strategy,
            deviceInfo: DeviceInfo.deviceId,
            forceSync: false
        )
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.syncMerge,
            method: .POST,
            body: request
        )
    }

    /// 上传数据。按 dataType 逐条 upsert，不是整表覆盖 —— 只传本次变更的类型即可。
    ///
    /// 一次调用消耗 1 个同步配额；同一 dataType 重复上传只留最新一条。
    static func upload(
        data: [String: Any]
    ) async throws -> ApiResponse<EmptyData> {
        let request = SyncUploadRequestDTO(data: data, deviceInfo: DeviceInfo.deviceId)
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.syncUpload,
            method: .POST,
            body: request
        )
    }

    /// 下载该用户的全部数据。
    ///
    /// 从未上传过时返回空字典 —— **不是错误**，调用方不要把它当成「服务器要求清空本地」。
    static func download() async throws -> ApiResponse<SyncDownloadResponseDTO> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.syncDownload,
            method: .GET
        )
    }

    /// 检查数据版本。只读，不计入同步配额。
    ///
    /// - Parameter clientVersion: **服务器数据指纹**（上次响应里的 `serverVersion`，
    ///   形如 `server_data_3_2100801093770592259`），不是 App 版本号。
    ///   传错不会报错，只会让 `needSync` 恒为 true、同步永远省不下来。
    static func checkVersion(
        clientVersion: String?,
        dataTypeVersions: [String: String]? = nil
    ) async throws -> ApiResponse<SyncVersionCheckResponseDTO> {
        let request = SyncVersionCheckRequestDTO(
            clientVersion: clientVersion,
            dataTypeVersions: dataTypeVersions,
            deviceInfo: DeviceInfo.deviceId
        )
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.syncVersionCheck,
            method: .POST,
            body: request
        )
    }
}
