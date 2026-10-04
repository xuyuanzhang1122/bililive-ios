import Foundation

enum PlaybackAPIMode { case auto, v2, legacy }
struct V2Failure: Codable, Sendable {
    let code: String
    let message: String
    let retryable: Bool
    var retryAfterSeconds: Double?
}
struct V2RequestError: LocalizedError {
    let status: Int
    let failure: V2Failure
    let requestId: String
    var errorDescription: String? { failure.message }
}
struct V2Envelope<T: Decodable>: Decodable {
    let data: T?
    let error: V2Failure?
    let requestId: String
}
struct RecordingIdentity: Codable, Equatable, Sendable {
    let recordingId: String
    let sourceVersion: String
}
struct V2Recording: Decodable {
    let recordingId: String
    let sourceVersion: String
    let path: String
    let room: String
    let sizeBytes: Int64
    let sizeText: String
}
struct V2Recordings: Decodable {
    let items: [V2Recording]
    let nextCursor: String
    let catalogStatus: String
}
struct VideoDecodeCapability: Codable, Sendable {
    let codec: String
    let profiles: [String]
    let maxLevel: Int
    let maxWidth: Int
    let maxHeight: Int
    let maxFps: Int
    let maxBitDepth: Int
    let hdr: Bool
}
struct AudioDecodeCapability: Codable, Sendable {
    let codec: String
    let profiles: [String]
    let maxChannels: Int
    let maxSampleRate: Int
}
struct PlaybackCapabilities: Codable, Sendable {
    let containers: [String]
    let protocols: [String]
    let video: [VideoDecodeCapability]
    let audio: [AudioDecodeCapability]
}
struct CreatePlaybackSession: Codable, Sendable {
    let recordingId: String
    let sourceVersion: String
    let capabilities: PlaybackCapabilities
}
enum V2SessionStatus: String, Codable, Sendable { case ready, processing, paused, failed, cancelled }
enum V2Decision: String, Codable, Sendable {
    case direct, remux
    case audioTranscode = "audio-transcode"
    case videoTranscode = "video-transcode"
}
struct PlaybackSession: Decodable, Sendable {
    let id: String
    let recordingId: String
    let sourceVersion: String
    let assetVersion: String
    let status: V2SessionStatus
    let decision: V2Decision
    let `protocol`: String?
    var url: String?
    let expiresAt: Int64
    let tokenExpiresAt: Int64?
    var refreshAfterSeconds: Double?
    let retryAfterSeconds: Double
    let error: V2Failure?

    func validate() throws {
        guard !id.isEmpty, !recordingId.isEmpty, !sourceVersion.isEmpty, expiresAt > 0,
              retryAfterSeconds.isFinite, retryAfterSeconds >= 0 else {
            throw APIError.serverError(-1, "播放会话字段无效")
        }
        if status == .ready {
            guard !assetVersion.isEmpty, let url, !url.isEmpty, ["file", "hls"].contains(`protocol` ?? ""),
                  error == nil, let tokenExpiresAt, tokenExpiresAt > 0,
                  let refreshAfterSeconds, refreshAfterSeconds.isFinite, refreshAfterSeconds >= 0 else {
                throw APIError.serverError(-1, "ready 会话缺少媒体或刷新信息")
            }
        } else {
            guard url == nil, status != .failed || error != nil else {
                throw APIError.serverError(-1, "未就绪会话字段无效")
            }
        }
    }
}
struct V2BatchRequest: Encodable { let items: [RecordingIdentity] }
struct V2DeleteResult: Decodable {
    let recordingId: String
    let status: String
    let deletedFiles: Int
    let error: V2Failure?
}
struct V2BatchResult: Decodable { let items: [V2DeleteResult] }
