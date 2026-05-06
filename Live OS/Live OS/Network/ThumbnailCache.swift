import CryptoKit
import SwiftUI
import UIKit

// MARK: - ThumbnailCache

/// Disk + memory cache for thumbnail images with session-scoped freshness.
///
/// - Cold start: URLs not yet seen this session are always fetched from the network
///   and saved to disk. The disk entry is reused on the next request within the
///   same session without hitting the network again.
/// - Manual refresh: call `invalidate(urls:)` before reloading; the next request
///   for each URL fetches fresh data from the network.
/// - Clear all: call `clearAll()` to wipe both memory and disk caches.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cacheDir: URL
    private let memory = NSCache<NSURL, UIImage>()
    private let queue = DispatchQueue(label: "ThumbnailCache", attributes: .concurrent)
    private var sessionLoaded: Set<URL> = []

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = base.appendingPathComponent("Thumbnails")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        memory.countLimit = 100
        memory.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }

    // MARK: - Public API

    func image(for url: URL) async -> UIImage? {
        if let img = memory.object(forKey: url as NSURL) { return img }

        let inSession = queue.sync { sessionLoaded.contains(url) }
        if inSession, let img = diskLoad(url) {
            memory.setObject(img, forKey: url as NSURL)
            return img
        }

        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return nil }
        store(img: img, data: data, for: url)
        return img
    }

    func invalidate(urls: [URL]) {
        for url in urls { removeSingle(url) }
    }

    func clearAll() {
        memory.removeAllObjects()
        queue.async(flags: .barrier) { self.sessionLoaded.removeAll() }
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    var diskSizeBytes: Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
                    .reduce(0, +)
    }

    // MARK: - Private

    private func removeSingle(_ url: URL) {
        memory.removeObject(forKey: url as NSURL)
        queue.async(flags: .barrier) { self.sessionLoaded.remove(url) }
        try? FileManager.default.removeItem(at: diskPath(for: url))
    }

    private func store(img: UIImage, data: Data, for url: URL) {
        memory.setObject(img, forKey: url as NSURL, cost: data.count)
        queue.async(flags: .barrier) {
            self.sessionLoaded.insert(url)
            try? data.write(to: self.diskPath(for: url))
        }
    }

    private func diskLoad(_ url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: diskPath(for: url)) else { return nil }
        return UIImage(data: data)
    }

    private func diskPath(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent(hash)
    }
}

// MARK: - CachedAsyncImage

/// Drop-in replacement for AsyncImage that uses ThumbnailCache.
///
/// Pass the ViewModel's `thumbnailRefreshToken` so the view automatically
/// re-fetches when the token increments (manual refresh).
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    let refreshToken: Int
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(
        url: URL?,
        refreshToken: Int = 0,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.refreshToken = refreshToken
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: TaskKey(url: url, token: refreshToken)) {
                await load()
            }
    }

    private struct TaskKey: Equatable {
        let url: URL?
        let token: Int
    }

    private func load() async {
        guard let url else { phase = .empty; return }
        if let img = await ThumbnailCache.shared.image(for: url) {
            phase = .success(Image(uiImage: img))
        } else {
            phase = .failure(URLError(.badURL))
        }
    }
}
