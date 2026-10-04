import SwiftUI

@Observable
final class VideoLibraryViewModel {
    var rooms: [VideoRoomInfo] = []
    var isLoading = false
    var errorMessage: String?
    var thumbnailRefreshToken: Int = 0

    private let client: APIClient

    @MainActor private var cacheKey: String {
        let characters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/%"))
        let server = client.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "VideoLibraryRooms_" + (server.addingPercentEncoding(withAllowedCharacters: characters) ?? "")
    }

    init(client: APIClient) {
        self.client = client
    }

    @MainActor
    func load() async {
        let cacheKey = self.cacheKey
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
            errorMessage = error.localizedDescription
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
    var deleteFailures: [BatchDeleteResult] = []
    var thumbnailRefreshToken: Int = 0

    private let client: APIClient
    let room: VideoRoomInfo

    @MainActor private var cacheKey: String {
        let characters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/%"))
        let folder = room.folderPath.addingPercentEncoding(withAllowedCharacters: characters) ?? ""
        let server = client.baseURL.trimmingCharacters(in:.init(charactersIn:"/"))
            .addingPercentEncoding(withAllowedCharacters:characters) ?? ""
        return "VideoListFiles_" + server + "_" + folder
    }

    init(client: APIClient, room: VideoRoomInfo) {
        self.client = client
        self.room   = room
    }

    @MainActor
    func load() async {
        // Use stable cache key (hashValue is not stable across launches)
        let cacheKey = self.cacheKey
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
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    func deleteFile(_ file: VideoFileInfo) async throws {
        let results = try await client.deleteRecordings([file])
        guard let result = results.first, result.success else {
            throw APIError.serverError(-1, results.first?.message ?? "服务端未确认删除")
        }
        files.removeAll { $0.id == file.id }
        CacheManager.shared.save(files, forKey: cacheKey)
    }

    @MainActor
    @discardableResult
    func deleteSelected() async throws -> Int {
        let paths = selection
        guard !paths.isEmpty else { return 0 }
        let selected = files.filter { paths.contains($0.relPath) }.sorted { $0.relPath < $1.relPath }
        guard selected.count == paths.count else { throw APIError.serverError(-1, "选择已变化，请刷新列表") }
        let results = try await client.deleteRecordings(selected)
        let resultsByPath = Dictionary(uniqueKeysWithValues: results.map { ($0.path, $0) })
        let succeeded = Set(results.filter { $0.success && paths.contains($0.path) }.map(\.path))
        deleteFailures = paths.subtracting(succeeded).sorted().map { path in
            BatchDeleteResult(path: path, success: false,
                message: resultsByPath[path]?.message ?? "服务端未返回该文件的删除结果")
        }
        files.removeAll { succeeded.contains($0.id) }
        selection.subtract(succeeded)
        CacheManager.shared.save(files, forKey: cacheKey)
        return succeeded.count
    }
}
