import Foundation

@MainActor
final class APIClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    var baseURL: String
    var apiKey: String
    private(set) var playbackAPIMode: PlaybackAPIMode

    init(baseURL: String, apiKey: String, playbackAPIMode: PlaybackAPIMode = .auto) {
        self.playbackAPIMode = playbackAPIMode
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = URLSession.shared
        self.decoder = JSONDecoder()
    }

    // MARK: - Request helpers

    private func makeRequest(_ path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        let urlString = baseURL.trimmingCharacters(in: .init(charactersIn: "/")) + path
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if path == "/api/video-library" {
            req.cachePolicy = .reloadIgnoringLocalCacheData
        }
        req.timeoutInterval = 30
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func fetch<T: Decodable>(
        _ type: T.Type,
        path: String,
        method: String = "GET",
        body: Data? = nil,
        decoder responseDecoder: JSONDecoder? = nil
    ) async throws -> T {
        let req = try makeRequest(path, method: method, body: body)
        let (data, response) = try await session.data(for: req)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let activeDecoder = responseDecoder ?? decoder
        if statusCode == 401 || statusCode == 403 { throw APIError.unauthorized }
        if statusCode >= 400 {
            if let wrappedError = try? activeDecoder.decode(APIResponse<EmptyData>.self, from: data) {
                throw APIError.serverError(wrappedError.errNo == 0 ? statusCode : wrappedError.errNo, wrappedError.errMsg)
            }
            let responseText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = responseText.flatMap { $0.isEmpty ? nil : $0 } ?? "请求失败"
            throw APIError.serverError(statusCode, message)
        }
        do {
            return try activeDecoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func fetchWrapped<T: Decodable>(_ type: T.Type, path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let wrapped = try await fetch(APIResponse<T>.self, path: path, method: method, body: body)
        if wrapped.errNo != 0 {
            throw APIError.serverError(wrapped.errNo, wrapped.errMsg)
        }
        guard let data = wrapped.data else {
            throw APIError.serverError(-1, "响应 data 为空")
        }
        return data
    }

    // MARK: - Server info

    func getServerInfo() async throws -> ServerInfo {
        try await fetch(ServerInfo.self, path: "/api/info")
    }

    func getServerBackupSnapshot() async throws -> BackupServerSnapshot {
        let config = try await fetch(ServerConfigSnapshot.self, path: "/api/config")
        return BackupServerSnapshot(
            rpcBind: config.rpc.bind,
            outputPath: config.outputPath,
            appDataPath: config.appDataPath,
            liveRooms: config.liveRooms.map {
                BackupLiveRoom(url: $0.url, isListening: $0.isListening)
            }
        )
    }

    func getCurrentAPIKeyUser() async throws -> APIKeyUser {
        try await fetch(APIKeyUser.self, path: "/api/auth/me")
    }

    // MARK: - Live rooms

    func getLives() async throws -> [LiveInfo] {
        try await fetch([LiveInfo].self, path: "/api/lives")
    }

    func addLive(url: String, listen: Bool = true) async throws {
        let body = try JSONEncoder().encode([AddLiveRequest(url: url, listen: listen)])
        let req = try makeRequest("/api/lives", method: "POST", body: body)
        let (_, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw APIError.unauthorized }
        if status >= 400 { throw APIError.serverError(status, "添加直播间失败") }
    }

    func deleteLive(id: String, deleteFiles: Bool = false) async throws {
        let body = try JSONEncoder().encode(DeleteLiveRequest(deleteFiles: deleteFiles))
        _ = try await fetch(APIResponse<EmptyData>.self, path: "/api/lives/\(id)", method: "DELETE", body: body)
    }

    func controlLive(id: String, action: String) async throws -> LiveInfo {
        try await fetch(LiveInfo.self, path: "/api/lives/\(id)/\(action)")
    }

    // MARK: - URL resolver

    func resolveURL(_ rawURL: String) async throws -> String {
        let encoded = rawURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? rawURL
        // 后端直接返回 {"url":"..."} 而非 APIResponse 包装
        let result = try await fetch(ResolveURLResult.self, path: "/api/resolve-url?url=\(encoded)")
        return result.url
    }

    func resolvePlayback(_ relPath: String) async throws -> PlaybackResolveResult {
        let encoded = encodedRelPath(relPath)
        let result = try await fetchWrapped(PlaybackResolveResult.self, path: "/api/playback/resolve/\(encoded)")
        guard ["ready", "processing", "recording", "failed"].contains(result.status) else {
            throw APIError.serverError(-1, "未知播放解析状态: \(result.status)")
        }
        if result.status == "ready" {
            guard let raw = result.url, absoluteURL(raw) != nil else {
                throw APIError.serverError(-1, "播放解析 ready 响应缺少有效 URL")
            }
        }
        return result
    }

    static func canFallbackPlayback(_ error: Error) -> Bool {
        guard case APIError.serverError(let code, let message) = error else { return false }
        return code == 405 || (code == 404 && message.contains("404 page not found"))
    }

    // MARK: - Video library

    func getVideoLibrary() async throws -> [VideoRoomInfo] {
        try await fetch([VideoRoomInfo].self, path: "/api/video-library")
    }

    func getVideoFiles(folderPath: String) async throws -> [VideoFileInfo] {
        if playbackAPIMode != .legacy {
            do {
                var items: [V2Recording] = []
                var after = ""
                var cursors = Set<String>()
                var identities = Set<String>()
                repeat {
                    let page = try await getRecordings(after: after)
                    for item in page.items {
                        guard identities.insert(item.recordingId).inserted else { throw APIError.serverError(-1, "录播清单身份重复") }
                        items.append(item)
                    }
                    after = page.nextCursor
                    if !after.isEmpty && !cursors.insert(after).inserted { throw APIError.serverError(-1, "录播分页游标重复") }
                } while !after.isEmpty
                playbackAPIMode = .v2
                let metadata = (try? await getLegacyVideoFiles(folderPath: folderPath)) ?? []
                return items.filter { $0.room == folderPath }.map { item in
                    let old = metadata.first { $0.relPath == item.path }
                    return VideoFileInfo(name: (item.path as NSString).lastPathComponent, relPath: item.path,
                        size: item.sizeBytes, modTime: old?.modTime ?? 0, fileURL: nil,
                        thumbnailURL: old?.thumbnailURL, hlsURL: nil, recording: old?.recording,
                        playbackStatus: old?.playbackStatus, recordingId: item.recordingId,
                        sourceVersion: item.sourceVersion, sizeText: item.sizeText)
                }
            } catch {
                guard playbackAPIMode == .auto, Self.canFallbackPlayback(error) else { throw error }
                playbackAPIMode = .legacy
            }
        }
        return try await getLegacyVideoFiles(folderPath: folderPath)
    }

    private func getLegacyVideoFiles(folderPath: String) async throws -> [VideoFileInfo] {
        try await fetch([VideoFileInfo].self, path: "/api/video-files/\(encodedRelPath(folderPath))")
    }

    private func fetchV2<T: Decodable>(_ type: T.Type, path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let request = try makeRequest(path, method: method, body: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if status == 405 || (status == 404 && text == "404 page not found") {
            throw APIError.serverError(status, text ?? "Method Not Allowed")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope: V2Envelope<T>
        do { envelope = try decoder.decode(V2Envelope<T>.self, from: data) }
        catch { throw APIError.decodingError(error) }
        guard !envelope.requestId.isEmpty else { throw APIError.serverError(-1, "v2 响应缺少请求标识") }
        if let error = envelope.error {
            guard !error.code.isEmpty, !error.message.isEmpty else { throw APIError.serverError(-1, "v2 错误字段无效") }
            throw V2RequestError(status: status, failure: error, requestId: envelope.requestId)
        }
        guard (200..<300).contains(status), let value = envelope.data else {
            throw APIError.serverError(status, "v2 响应 data 为空")
        }
        return value
    }

    func getRecordings(after: String = "") async throws -> V2Recordings {
        let cursor = after.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let page = try await fetchV2(V2Recordings.self, path: "/api/v2/recordings?limit=100&after=\(cursor)")
        guard page.catalogStatus == "verified", page.items.allSatisfy({ !$0.recordingId.isEmpty && !$0.sourceVersion.isEmpty &&
            !$0.path.isEmpty && !$0.sizeText.isEmpty && $0.sizeBytes >= 0 }) else {
            throw APIError.serverError(-1, "录播目录未核验或字段无效")
        }
        return page
    }

    func createPlaybackSession(_ body: CreatePlaybackSession) async throws -> PlaybackSession {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try normalizeSession(await fetchV2(PlaybackSession.self, path: "/api/v2/playback-sessions", method: "POST", body: encoder.encode(body)))
    }
    func getPlaybackSession(_ id: String) async throws -> PlaybackSession {
        try normalizeSession(await fetchV2(PlaybackSession.self, path: "/api/v2/playback-sessions/\(encodedRelPath(id))"))
    }
    func cancelPlaybackSession(_ id: String) async throws {
        let value = try await fetchV2(PlaybackSession.self, path: "/api/v2/playback-sessions/\(encodedRelPath(id))", method: "DELETE")
        try value.validate()
        guard value.status == .cancelled else { throw APIError.serverError(-1, "播放会话未取消") }
    }
    private func normalizeSession(_ value: PlaybackSession) throws -> PlaybackSession {
        var value = value
        if value.status == .ready && value.refreshAfterSeconds == nil && value.tokenExpiresAt == value.expiresAt &&
            value.expiresAt <= Int64(Date().timeIntervalSince1970) + 60 { value.refreshAfterSeconds = 0 }
        try value.validate()
        if value.status == .ready {
            guard let url = absoluteURL(value.url ?? ""), Self.sameOrigin(url, URL(string: baseURL)),
                  URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "play_token" && !($0.value ?? "").isEmpty }) == true,
                  URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "_key" }) != true else {
                throw APIError.serverError(-1, "v2 媒体地址授权无效")
            }
            value.url = url.absoluteString
        }
        return value
    }
    func deleteRecordings(_ files: [VideoFileInfo]) async throws -> [BatchDeleteResult] {
        if playbackAPIMode == .legacy { return try await deleteFiles(relPaths: files.map(\.relPath)) }
        let identities = files.compactMap(\.recordingIdentity)
        guard !files.isEmpty, files.count <= 100, identities.count == files.count,
              Set(identities.map(\.recordingId)).count == files.count else {
            throw APIError.serverError(-1, "缺少录播身份或选择无效，请刷新列表")
        }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let result = try await fetchV2(V2BatchResult.self, path: "/api/v2/recordings/batch-delete", method: "POST", body: encoder.encode(V2BatchRequest(items: identities)))
        var seen = Set<String>()
        return try result.items.map { item in
            guard let file = files.first(where: { $0.recordingId == item.recordingId }), seen.insert(item.recordingId).inserted,
                  ["deleted", "already_deleted", "failed"].contains(item.status), item.deletedFiles >= 0,
                  item.status != "failed" || item.error != nil else { throw APIError.serverError(-1, "批删逐项响应无效") }
            return BatchDeleteResult(path: file.relPath, success: item.status != "failed", message: item.error?.message)
        }
    }

    // MARK: - Backup / restore

    func createRemoteBackup(_ package: BackupPackage) async throws -> BackupRemoteRecord {
        let body = try JSONEncoder.backupEncoder.encode(package)
        return try await fetch(BackupRemoteRecord.self, path: "/api/backups", method: "POST", body: body)
    }

    func fetchRemoteBackup(id: String) async throws -> BackupPackage {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await fetch(BackupPackage.self, path: "/api/backups/\(encoded)", decoder: .backupDecoder)
    }

    func restoreBackup(package: BackupPackage) async throws -> BackupRestoreResult {
        let body = try JSONEncoder.backupEncoder.encode(BackupRestorePackageRequest(package: package))
        return try await fetch(BackupRestoreResult.self, path: "/api/backups/restore", method: "POST", body: body)
    }

    func restoreBackup(id: String) async throws -> BackupRestoreResult {
        let body = try JSONEncoder().encode(BackupRestoreIDRequest(id: id))
        return try await fetch(BackupRestoreResult.self, path: "/api/backups/restore", method: "POST", body: body)
    }

    func getRestoreStatus(jobID: String) async throws -> BackupRestoreResult {
        let encoded = jobID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobID
        return try await fetch(BackupRestoreResult.self, path: "/api/backups/restore/status/\(encoded)")
    }

    // MARK: - File management

    func deleteFile(relPath: String) async throws {
        let encoded = encodedRelPath(relPath)
        _ = try await fetch(APIResponse<EmptyData>.self, path: "/api/file/\(encoded)", method: "DELETE")
    }

    func deleteFiles(relPaths: [String]) async throws -> [BatchDeleteResult] {
        let body = try JSONEncoder().encode(["paths": relPaths])
        let results = try await fetchWrapped([BatchDeleteResult].self, path: "/api/batch/file/delete", method: "POST", body: body)
        guard Set(results.map(\.path)).count == results.count else {
            throw APIError.serverError(-1, "批量删除逐项结果包含重复路径")
        }
        return results
    }

    // MARK: - Watch history

    struct SaveHistoryRequest: Codable {
        var recordingId: String?
        var sourceVersion: String?
        let videoPath: String
        let videoName: String
        let positionSeconds: Double
        let durationSeconds: Double

        enum CodingKeys: String, CodingKey {
            case recordingId = "recording_id"
            case sourceVersion = "source_version"
            case videoPath = "video_path"
            case videoName = "video_name"
            case positionSeconds = "position_seconds"
            case durationSeconds = "duration_seconds"
        }
    }

    func saveWatchHistory(videoPath: String, videoName: String, positionSeconds: Double, durationSeconds: Double, recordingId: String? = nil, sourceVersion: String? = nil) async throws {
        var req = SaveHistoryRequest(videoPath: videoPath, videoName: videoName, positionSeconds: positionSeconds, durationSeconds: durationSeconds)
        req.recordingId = recordingId; req.sourceVersion = sourceVersion
        let body = try JSONEncoder().encode(req)
        _ = try await fetch(APIResponse<EmptyData>.self, path: "/api/history", method: "POST", body: body)
    }

    func getWatchHistory() async throws -> [HistoryEntry] {
        try await fetch([HistoryEntry].self, path: "/api/history")
    }

    func getWatchHistoryEntry(videoPath: String) async throws -> HistoryEntry {
        let encoded = encodedRelPath(videoPath)
        return try await fetch(HistoryEntry.self, path: "/api/history/\(encoded)")
    }

    func deleteWatchHistory(videoPath: String) async throws {
        let encoded = encodedRelPath(videoPath)
        _ = try await fetch(APIResponse<EmptyData>.self, path: "/api/history/\(encoded)", method: "DELETE")
    }

    // MARK: - Signed URLs

    func absoluteURL(_ relativeURLString: String) -> URL? {
        let raw = relativeURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .init(charactersIn: "/"))
        let isAbsolute = raw.lowercased().hasPrefix("https://") || raw.lowercased().hasPrefix("http://")
        let value = isAbsolute ? raw : base + (raw.hasPrefix("/") ? raw : "/" + raw)
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty else { return nil }
        let items = components.queryItems ?? []
        let hasSignature = items.contains { $0.name == "sig" } && items.contains { $0.name == "expires" }
        if !apiKey.isEmpty && !hasSignature && !items.contains(where: { $0.name == "play_token" || $0.name == "_key" }) &&
            Self.sameOrigin(components.url, URL(string: base)) {
            components.queryItems = items + [URLQueryItem(name: "_key", value: apiKey)]
        }
        return components.url
    }

    static func sameOrigin(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs else { return false }
        func port(_ url: URL) -> Int { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased() && lhs.host?.lowercased() == rhs.host?.lowercased() && port(lhs) == port(rhs)
    }

    func thumbnailURL(for relPath: String) -> URL? {
        let encoded = encodedRelPath(relPath)
        return absoluteURL("/api/thumbnail/\(encoded)")
    }

    func makeHLSURL(hlsRelative: String) -> URL? {
        absoluteURL(hlsRelative)
    }

    func makeFileURL(fileRelative: String) -> URL? {
        absoluteURL(fileRelative)
    }

    private static let urlPathSafeChars: CharacterSet = {
        var c = CharacterSet.urlPathAllowed
        c.remove(charactersIn: "[]{}|\\^`\"<>#% ")
        return c
    }()

    private func encodedRelPath(_ relPath: String) -> String {
        relPath.split(separator: "/").map {
            $0.addingPercentEncoding(withAllowedCharacters: Self.urlPathSafeChars) ?? String($0)
        }.joined(separator: "/")
    }

    /// 计算播放 URL：优先使用后端返回的签名 URL；否则按后缀回退到 /api/stream/hls 或 /files
    func playbackURL(for file: VideoFileInfo) -> URL? {
        if let hls = file.hlsURL, let u = makeHLSURL(hlsRelative: hls) { return u }
        if let f = file.fileURL, let u = makeFileURL(fileRelative: f) { return u }
        let encoded = encodedRelPath(file.relPath)
        let path = file.isNativePlayable ? "/files/\(encoded)" : "/api/stream/hls/\(encoded)"
        return absoluteURL(path)
    }

    /// 计算缩略图 URL：优先使用后端返回的签名 URL；否则回退到 /api/thumbnail
    func thumbnailURL(for file: VideoFileInfo) -> URL? {
        if let t = file.thumbnailURL, let u = absoluteURL(t) { return u }
        return thumbnailURL(for: file.relPath)
    }
}
