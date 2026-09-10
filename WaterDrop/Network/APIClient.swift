import Foundation
import os.log

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger = Logger(subsystem: "com.waterdrop.ios", category: "APIClient")

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = ServerConfig.Timeout.read
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    enum HTTPMethod: String {
        case GET, POST, PUT, DELETE
    }

    // MARK: - Generic Request

    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        requiresAuth: Bool = true
    ) async throws -> ApiResponse<T> {
        let urlRequest = try buildRequest(
            endpoint: endpoint,
            method: method,
            body: body,
            queryItems: queryItems,
            requiresAuth: requiresAuth
        )

        // Try request, handle 401 with token refresh
        do {
            let response: ApiResponse<T> = try await executeRequest(urlRequest)
            return response
        } catch NetworkError.unauthorized {
            guard requiresAuth else { throw NetworkError.unauthorized }

            // Attempt token refresh
            let refreshed = await TokenRefreshHandler.shared.refreshTokenIfNeeded()
            if refreshed {
                // Rebuild request with new token
                let retryRequest = try buildRequest(
                    endpoint: endpoint,
                    method: method,
                    body: body,
                    queryItems: queryItems,
                    requiresAuth: true
                )
                return try await executeRequest(retryRequest)
            } else {
                throw NetworkError.unauthorized
            }
        }
    }

    // MARK: - Build Request

    private func buildRequest(
        endpoint: String,
        method: HTTPMethod,
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        requiresAuth: Bool
    ) throws -> URLRequest {
        var urlString = ServerConfig.baseURL
        if !urlString.hasSuffix("/") { urlString += "/" }
        urlString += endpoint

        guard var components = URLComponents(string: urlString) else {
            throw NetworkError.invalidResponse
        }

        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw NetworkError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = ServerConfig.Timeout.read

        // Standard headers
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("WaterDrop-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("iOS", forHTTPHeaderField: "X-Client-Platform")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")

        // Auth header
        if requiresAuth {
            if let token = AuthStateManager.shared.getAccessToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }

        // Body
        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        return request
    }

    // MARK: - Multipart Upload

    /// 上传单个文件（multipart/form-data），复用 executeRequest 的鉴权+重试逻辑。
    /// - Returns: 服务端返回的 `{ fileName, fileUrl }`。
    func uploadFile(
        data: Data,
        fileName: String,
        mimeType: String,
        fieldName: String = "file"
    ) async throws -> ApiResponse<[String: String]> {
        let body = try makeMultipartBody(data: data, fileName: fileName, mimeType: mimeType, fieldName: fieldName)

        var urlString = ServerConfig.baseURL
        if !urlString.hasSuffix("/") { urlString += "/" }
        urlString += ServerConfig.Endpoints.filesUpload
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.POST.rawValue
        request.timeoutInterval = ServerConfig.Timeout.read
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("WaterDrop-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("iOS", forHTTPHeaderField: "X-Client-Platform")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        request.setValue("multipart/form-data; boundary=\(body.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data

        if let token = AuthStateManager.shared.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Try upload, handle 401 with token refresh (与 request() 保持一致)
        do {
            return try await executeRequest(request)
        } catch NetworkError.unauthorized {
            let refreshed = await TokenRefreshHandler.shared.refreshTokenIfNeeded()
            if refreshed {
                if let token = AuthStateManager.shared.getAccessToken() {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                return try await executeRequest(request)
            } else {
                throw NetworkError.unauthorized
            }
        }
    }

    private struct MultipartBody {
        let boundary: String
        let data: Data
    }

    private func makeMultipartBody(
        data: Data,
        fileName: String,
        mimeType: String,
        fieldName: String
    ) throws -> MultipartBody {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func append(_ string: String) {
            body.append(string.data(using: .utf8)!)
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n")
        append("--\(boundary)--\r\n")

        return MultipartBody(boundary: boundary, data: body)
    }

    // MARK: - Execute with Retry

    private func executeRequest<T: Decodable>(_ request: URLRequest) async throws -> ApiResponse<T> {
        var lastError: Error = NetworkError.unknown(NSError(domain: "", code: -1))

        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }

                // Handle status codes
                switch httpResponse.statusCode {
                case 200...299:
                    do {
                        let apiResponse = try decoder.decode(ApiResponse<T>.self, from: data)
                        return apiResponse
                    } catch {
                        logger.error("Decoding failed: \(error.localizedDescription)")
                        throw NetworkError.decodingFailed(error)
                    }
                case 401:
                    throw NetworkError.unauthorized
                case 400...499:
                    // Client errors - don't retry
                    if let apiResponse = try? decoder.decode(ApiResponse<T>.self, from: data) {
                        throw NetworkError.businessError(code: apiResponse.code, message: apiResponse.message)
                    }
                    throw NetworkError.businessError(code: httpResponse.statusCode, message: "请求失败")
                case 500...599:
                    // Server errors - retry with backoff
                    lastError = NetworkError.serverError(statusCode: httpResponse.statusCode)
                    if attempt < 2 {
                        let delay = pow(2.0, Double(attempt))
                        try await Task.sleep(for: .seconds(delay))
                        continue
                    }
                    throw lastError
                default:
                    throw NetworkError.invalidResponse
                }
            } catch let error as NetworkError {
                // Don't retry client errors
                switch error {
                case .unauthorized, .decodingFailed, .businessError, .invalidResponse:
                    throw error
                default:
                    lastError = error
                    if attempt < 2 {
                        let delay = pow(2.0, Double(attempt))
                        try await Task.sleep(for: .seconds(delay))
                        continue
                    }
                }
            } catch let error as URLError {
                switch error.code {
                case .timedOut:
                    lastError = NetworkError.timeout
                case .notConnectedToInternet, .networkConnectionLost:
                    throw NetworkError.networkUnavailable
                default:
                    lastError = NetworkError.unknown(error)
                }
                if attempt < 2 {
                    let delay = pow(2.0, Double(attempt))
                    try await Task.sleep(for: .seconds(delay))
                    continue
                }
            }
        }

        throw lastError
    }
}

// MARK: - Type Erasure Helper

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        _encode = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
