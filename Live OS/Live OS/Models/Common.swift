import Foundation

struct APIResponse<T: Decodable>: Decodable {
    let errNo: Int
    let errMsg: String
    let data: T?

    enum CodingKeys: String, CodingKey {
        case errNo = "err_no"
        case errMsg = "err_msg"
        case data
    }
}

struct EmptyData: Decodable {}

struct SignedURLData: Decodable {
    let url: String
    let expires: Int64
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case url, expires
        case expiresIn = "expires_in"
    }
}

struct ResolveURLResult: Decodable {
    let url: String
}

struct PlaybackResolveResult: Decodable {
    let status: String
    let protocolName: String?
    let mimeType: String?
    let url: String?
    let expiresAt: Int64?
    let error: String?
    let retryAfterSeconds: Double?

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        status = try values.decode(String.self, forKey: .status)
        protocolName = try values.decodeIfPresent(String.self, forKey: .protocolName)
        mimeType = try values.decodeIfPresent(String.self, forKey: .mimeType)
        url = try values.decodeIfPresent(String.self, forKey: .url)
        expiresAt = try values.decodeIfPresent(Int64.self, forKey: .expiresAt)
        error = try values.decodeIfPresent(String.self, forKey: .error)
        let retry = try? values.decode(Double.self, forKey: .retryAfterSeconds)
        retryAfterSeconds = retry.map { $0.isFinite ? min(10, max(1, $0)) : 2 } ?? 2
    }

    enum CodingKeys: String, CodingKey {
        case status
        case protocolName = "protocol"
        case mimeType = "mime_type"
        case url
        case expiresAt = "expires_at"
        case error
        case retryAfterSeconds = "retry_after_seconds"
    }
}

struct APIKeyUser: Decodable, Equatable {
    let id: String
    let name: String
    let keySuffix: String?
    let lastUsedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case keySuffix = "key_suffix"
        case lastUsedAt = "last_used_at"
    }
}

struct ServerInfo: Decodable {
    let appName: String
    let appVersion: String
    let platform: String

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case appVersion = "app_version"
        case platform
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(Int, String)
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:               return "无效的服务器地址"
        case .unauthorized:             return "API Key 错误，请在设置中检查"
        case .serverError(let c, let m): return "服务器错误 \(c): \(m)"
        case .networkError(let e):      return "网络错误: \(e.localizedDescription)"
        case .decodingError(let e):     return "数据解析失败: \(e.localizedDescription)"
        }
    }
}

struct BatchDeleteResult: Codable {
    let path: String
    let success: Bool
    let message: String?
}
