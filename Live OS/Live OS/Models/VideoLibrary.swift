import Foundation

struct VideoRoomInfo: Identifiable, Codable {
    let hostName: String
    let platform: String
    let folderPath: String
    let videoCount: Int
    let totalSize: Int64
    let latestVideoAt: Int64
    let latestVideo: String?
    let recording: Bool
    let url: String?
    var totalSizeText: String? = nil
    var statisticsStatus: String? = nil
    var statisticsCheckedAt: Int64? = nil

    var id: String { folderPath }

    var totalSizeFormatted: String {
        if statisticsStatus == "unavailable" { return "统计暂不可用" }
        if let text = totalSizeText, !text.isEmpty { return text }
        // 旧服务端只提供字节时，采用与服务端相同的十进制兼容显示。
        guard totalSize >= 0 else { return "统计暂不可用" }
        if totalSize < 1000 { return "\(totalSize) B" }
        let units = ["B", "kB", "MB", "GB", "TB", "PB", "EB"]
        var amount = Double(totalSize)
        var unit = 0
        while amount >= 1000 && unit < units.count - 1 {
            amount /= 1000
            unit += 1
        }
        return String(format: "%.1f %@", locale: Locale(identifier: "en_US_POSIX"), amount, units[unit])
    }

    var latestDate: Date {
        Date(timeIntervalSince1970: TimeInterval(latestVideoAt))
    }

    enum CodingKeys: String, CodingKey {
        case hostName = "host_name"
        case platform
        case folderPath = "folder_path"
        case videoCount = "video_count"
        case totalSize = "total_size"
        case totalSizeText = "total_size_text"
        case statisticsStatus = "statistics_status"
        case statisticsCheckedAt = "statistics_checked_at"
        case latestVideoAt = "latest_video_at"
        case latestVideo = "latest_video"
        case recording
        case url
    }
}

struct VideoFileInfo: Identifiable, Codable {
    let name: String
    let relPath: String
    let size: Int64
    let modTime: Int64
    let fileURL: String?
    let thumbnailURL: String?
    let hlsURL: String?
    /// 该文件是否仍在录制写入中
    let recording: Bool?
    /// 后端播放状态：ready / recording / processing / unsupported
    let playbackStatus: String?

    var recordingId: String? = nil
    var sourceVersion: String? = nil
    var sizeText: String? = nil

    var recordingIdentity: RecordingIdentity? {
        guard let recordingId, !recordingId.isEmpty, let sourceVersion, !sourceVersion.isEmpty else { return nil }
        return RecordingIdentity(recordingId: recordingId, sourceVersion: sourceVersion)
    }
    var id: String { relPath }

    var sizeFormatted: String {
        sizeText ?? ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var modDate: Date {
        Date(timeIntervalSince1970: TimeInterval(modTime))
    }

    var isNativePlayable: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mp4", "m4v", "mov", "ts"].contains(ext)
    }

    enum CodingKeys: String, CodingKey {
        case name, size, recording
        case relPath = "rel_path"
        case modTime = "mod_time"
        case fileURL = "file_url"
        case thumbnailURL = "thumbnail_url"
        case hlsURL = "hls_url"
        case playbackStatus = "playback_status"
        case recordingId = "recording_id"
        case sourceVersion = "source_version"
        case sizeText = "size_text"
    }
}
