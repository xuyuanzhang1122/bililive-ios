import Foundation

// 隔离缩略图和磁盘 I/O；批删网络及 ViewModel 执行实际源码。
@MainActor final class ThumbnailCache {
    static let shared = ThumbnailCache()
    func invalidate(urls: [URL]) {}
}

@MainActor final class CacheManager {
    static let shared = CacheManager()
    var stored: [String: Data] = [:]
    func save<T: Encodable>(_ object: T, forKey key: String) {
        stored[key] = try! JSONEncoder().encode(object)
    }
    func load<T: Decodable>(forKey key: String, as type: T.Type) -> T? {
        stored[key].flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
