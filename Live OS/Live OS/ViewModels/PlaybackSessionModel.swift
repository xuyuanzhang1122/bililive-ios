import Foundation

@MainActor protocol PlaybackSessionTransport: AnyObject {
    func createPlaybackSession(_ body: CreatePlaybackSession) async throws -> PlaybackSession
    func getPlaybackSession(_ id: String) async throws -> PlaybackSession
    func cancelPlaybackSession(_ id: String) async throws
}
extension APIClient: PlaybackSessionTransport {}

@MainActor final class PlaybackSessionModel {
    var onReady: (PlaybackSession) async throws -> Void = { _ in }
    var onError: (Error) -> Void = { _ in }
    private let client: any PlaybackSessionTransport
    private let sleep: (Double) async throws -> Void
    private var generation = 0
    private var current: PlaybackSession?
    private var body: CreatePlaybackSession?
    private var refreshTask: Task<Void, Never>?

    init(client: any PlaybackSessionTransport,
         sleep: @escaping (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.client = client
        self.sleep = sleep
    }
    private func invalidate() -> String? {
        generation += 1
        refreshTask?.cancel(); refreshTask = nil
        let id = current?.id
        current = nil; body = nil
        return id
    }
    func close() async {
        let id = invalidate()
        if let id { await cancelQuietly(id) }
    }
    func open(identity: RecordingIdentity, capabilities: PlaybackCapabilities) async {
        let old = invalidate(), token = generation
        if let old { await cancelQuietly(old) }
        guard active(token) else { return }
        let request = CreatePlaybackSession(recordingId: identity.recordingId, sourceVersion: identity.sourceVersion, capabilities: capabilities)
        body = request
        do {
            let created = try await client.createPlaybackSession(request)
            guard active(token) else { await cancelQuietly(created.id); return }
            current = created
            try await ready(created, token: token)
            if active(token) { refreshTask = Task { await self.refreshLoop(token: token) } }
        } catch { fail(error, token: token) }
    }
    private func active(_ token: Int) -> Bool { token == generation && !Task.isCancelled }
    private func check(_ value: PlaybackSession) throws {
        try value.validate()
        guard let body, value.recordingId == body.recordingId, value.sourceVersion == body.sourceVersion else {
            throw APIError.serverError(-1, "播放来源身份已变化")
        }
    }
    private func ready(_ initial: PlaybackSession, token: Int) async throws {
        var value = initial
        while active(token) {
            try check(value)
            current = value
            if value.status == .ready {
                try await onReady(value)
                return
            }
            guard value.status == .processing || value.status == .paused else {
                throw APIError.serverError(409, value.error?.message ?? "播放会话已取消")
            }
            try await sleep(retry(value.retryAfterSeconds))
            guard active(token), let body else { return }
            do {
                let expectedID = value.id
                value = try await client.getPlaybackSession(expectedID)
                guard value.id == expectedID else { throw APIError.serverError(-1,"播放会话身份不匹配") }
            }
            catch let error as V2RequestError where error.status == 410 && error.failure.code == "session_expired" {
                value = try await client.createPlaybackSession(body)
                if !active(token) { await cancelQuietly(value.id); return }
            }
            guard active(token) else { return }
        }
    }
    private func refreshLoop(token: Int) async {
        var failures = 0
        var retryDelay: Double?
        while active(token), let previous = current, let body {
            do {
                try await sleep(retryDelay ?? max(1, previous.refreshAfterSeconds ?? 1))
                guard active(token) else { return }
                var renewed = false
                var value: PlaybackSession
                do { value = try await client.getPlaybackSession(previous.id) }
                catch let error as V2RequestError where error.status == 410 && error.failure.code == "session_expired" {
                    value = try await client.createPlaybackSession(body); renewed = true
                    if !active(token) { await cancelQuietly(value.id); return }
                }
                guard active(token) else { return }
                try check(value)
                guard renewed || value.id == previous.id else { throw APIError.serverError(-1, "播放会话身份不匹配") }
                if value.status == .ready && value.refreshAfterSeconds == 0 {
                    let fresh = try await client.createPlaybackSession(body)
                    if !active(token) { await cancelQuietly(fresh.id); return }
                    current = fresh
                    try check(fresh)
                    await cancelQuietly(value.id)
                    guard active(token) else { return }
                    value = fresh
                }
                guard previous.assetVersion.isEmpty || value.assetVersion.isEmpty || previous.assetVersion == value.assetVersion else {
                    throw APIError.serverError(-1, "播放资产版本变化，请重新打开")
                }
                failures = 0; retryDelay = nil
                try await ready(value, token: token)
            } catch {
                guard active(token) else { return }
                let transient = (error as? V2RequestError)?.failure.retryable ?? (error is URLError)
                failures += 1
                if transient && failures <= 3 { retryDelay = retry((error as? V2RequestError)?.failure.retryAfterSeconds ?? 2) }
                else { fail(error, token: token); return }
            }
        }
    }
    private func retry(_ value: Double) -> Double { value.isFinite && value > 0 ? min(60, max(1, value)) : 2 }
    private func fail(_ error: Error, token: Int) {
        guard active(token) else { return }
        onError(error)
    }
    private func cancelQuietly(_ id: String) async { try? await client.cancelPlaybackSession(id) }
}
