import SwiftUI

@Observable
final class VideoLibraryViewModel {
    var rooms: [VideoRoomInfo] = []
    var isLoading = false
    var errorMessage: String?
    var thumbnailRefreshToken: Int = 0

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    @MainActor
    func load() async {
        let cacheKey = "VideoLibraryRooms"
        // On manual refresh (rooms already loaded), invalidate thumbnails
        if !rooms.isEmpty {
            let urls = rooms.compactMap { room -> URL? in
                guard let latest = room.latestVideo else { return nil }
                return client.thumbnailURL(for: latest)
            }
            ThumbnailCache.shared.invalidate(urls: urls)
            thumbnailRefreshToken += 1
        }

        // 1. 先读取本地缓存，快速显示
        if let cached: [VideoRoomInfo] = CacheManager.shared.load(forKey: cacheKey, as: [VideoRoomInfo].self), rooms.isEmpty {
            self.rooms = cached
        }

        // 2. 然后再去取最新数据
        isLoading = rooms.isEmpty
        errorMessage = nil
        do {
            let newRooms = try await client.getVideoLibrary()
            self.rooms = newRooms
            CacheManager.shared.save(newRooms, forKey: cacheKey)
        } catch {
            if rooms.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
}

@Observable
final class VideoListViewModel {
    var files: [VideoFileInfo] = []
    var historyByPath: [String: HistoryEntry] = [:]
    var isLoading = false
    var errorMessage: String?
    var selection: Set<String> = []
    var thumbnailRefreshToken: Int = 0

    private let client: APIClient
    let room: VideoRoomInfo

    init(client: APIClient, room: VideoRoomInfo) {
        self.client = client
        self.room   = room
    }

    @MainActor
    func load() async {
        // Use stable cache key (hashValue is not stable across launches)
        let cacheKey = "VideoListFiles_" + room.folderPath
        // On manual refresh (files already loaded), invalidate thumbnails
        if !files.isEmpty {
            let urls = files.compactMap { client.thumbnailURL(for: $0) }
            ThumbnailCache.shared.invalidate(urls: urls)
            thumbnailRefreshToken += 1
        }

        // 1. 先读取本地缓存，快速显示
        if let cached: [VideoFileInfo] = CacheManager.shared.load(forKey: cacheKey, as: [VideoFileInfo].self), files.isEmpty {
            self.files = cached
        }

        // 2. 然后再去取最新数据
        isLoading = files.isEmpty
        errorMessage = nil
        do {
            let newFiles = try await client.getVideoFiles(folderPath: room.folderPath)
            self.files = newFiles
            CacheManager.shared.save(newFiles, forKey: cacheKey)
            if let history = try? await client.getWatchHistory() {
                self.historyByPath = Dictionary(uniqueKeysWithValues: history.map { ($0.videoPath, $0) })
            }
        } catch {
            if files.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    @MainActor
    func deleteFile(_ file: VideoFileInfo) async throws {
        try await client.deleteFile(relPath: file.relPath)
        files.removeAll { $0.id == file.id }
    }

    @MainActor
    func deleteSelected() async throws {
        let paths = Array(selection)
        try await client.deleteFiles(relPaths: paths)
        files.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }
}
