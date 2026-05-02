import Foundation

final class CacheManager {
    static let shared = CacheManager()
    
    private let fileManager = FileManager.default
    private lazy var cacheDirectory: URL = {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("APICache")
    }()

    /// 默认缓存过期时间：30 分钟
    private let defaultMaxAge: TimeInterval = 30 * 60
    
    private init() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        // 启动时清理过期缓存
        cleanExpiredCache()
    }
    
    func save<T: Encodable>(_ object: T, forKey key: String) {
        let url = cacheDirectory.appendingPathComponent(key)
        do {
            let wrapper = CacheWrapper(data: object, savedAt: Date())
            let data = try JSONEncoder().encode(wrapper)
            try data.write(to: url)
        } catch {
            print("Failed to save cache for key: \(key) - \(error)")
        }
    }
    
    func load<T: Decodable>(forKey key: String, as type: T.Type, maxAge: TimeInterval? = nil) -> T? {
        let url = cacheDirectory.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let wrapper = try JSONDecoder().decode(CacheWrapper<T>.self, from: data)
            let age = Date().timeIntervalSince(wrapper.savedAt)
            if age > (maxAge ?? defaultMaxAge) {
                // 缓存已过期，删除文件
                try? fileManager.removeItem(at: url)
                return nil
            }
            return wrapper.data
        } catch {
            // 可能是旧格式数据（无 wrapper），尝试直接解码
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                print("Failed to load cache for key: \(key) - \(error)")
                return nil
            }
        }
    }

    /// 清理所有过期缓存文件
    private func cleanExpiredCache() {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files {
            guard let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = attrs.contentModificationDate else { continue }
            if Date().timeIntervalSince(modDate) > defaultMaxAge * 2 {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}

// MARK: - Cache Wrapper

private struct CacheWrapper<T: Codable>: Codable {
    let data: T
    let savedAt: Date
}
