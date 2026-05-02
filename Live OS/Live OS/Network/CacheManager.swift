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
            let wrapper = EncodableCacheWrapper(data: object, savedAt: Date())
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
            let wrapper = try JSONDecoder().decode(DecodableCacheWrapper<T>.self, from: data)
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

private struct EncodableCacheWrapper<T: Encodable>: Encodable {
    let data: T
    let savedAt: Date
}

private struct DecodableCacheWrapper<T: Decodable>: Decodable {
    let data: T
    let savedAt: Date
}

// MARK: - Local History Manager

final class LocalHistoryManager {
    static let shared = LocalHistoryManager()
    private let defaults = UserDefaults.standard
    private let key = "LocalWatchHistory"

    private init() {}

    func getHistory() -> [HistoryEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            let entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
            // Sort by updated time descending
            return entries.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            print("Failed to decode local history: \(error)")
            return []
        }
    }

    func saveHistory(videoPath: String, videoName: String, positionSeconds: Double, durationSeconds: Double) {
        var current = getHistory()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let now = formatter.string(from: Date())
        
        if let idx = current.firstIndex(where: { $0.videoPath == videoPath }) {
            let existing = current[idx]
            let updated = HistoryEntry(
                id: existing.id,
                videoPath: videoPath,
                videoName: videoName,
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds,
                updatedAt: now
            )
            current[idx] = updated
        } else {
            let newId = (current.map { $0.id }.max() ?? 0) + 1
            let newEntry = HistoryEntry(
                id: newId,
                videoPath: videoPath,
                videoName: videoName,
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds,
                updatedAt: now
            )
            current.insert(newEntry, at: 0)
        }
        
        // Keep max 200 entries to prevent UserDefaults bloat
        if current.count > 200 {
            current = Array(current.prefix(200))
        }
        
        do {
            let data = try JSONEncoder().encode(current)
            defaults.set(data, forKey: key)
        } catch {
            print("Failed to encode local history: \(error)")
        }
    }

    func deleteHistory(videoPath: String) {
        var current = getHistory()
        current.removeAll { $0.videoPath == videoPath }
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: key)
        }
    }
}
