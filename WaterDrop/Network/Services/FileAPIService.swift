import Foundation

/// 文件/图片上传服务。对齐 Android `FileApiService` 的 `uploadFile` → `files/upload` 接口。
enum FileAPIService {
    /// 上传图片数据，返回服务端相对路径 `fileUrl`（如 `/api/files/2026/.../img_xxx.jpg`）。
    /// 调用方用 `ServerConfig.resolveImageUrl` 补全为可访问的绝对地址。
    static func uploadImage(data: Data, mimeType: String) async throws -> String? {
        let ext = fileExtension(for: mimeType)
        let fileName = "img_\(UUID().uuidString).\(ext)"
        let response = try await APIClient.shared.uploadFile(
            data: data, fileName: fileName, mimeType: mimeType
        )
        if response.code == 200, let fileUrl = response.data?["fileUrl"] {
            return fileUrl
        }
        return nil
    }

    /// 根据 MIME 类型推断文件扩展名。`extension` 是 Swift 保留字，故命名 fileExtension。
    private static func fileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        default: return "jpg"
        }
    }
}
