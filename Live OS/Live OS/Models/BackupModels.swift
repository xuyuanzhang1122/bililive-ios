import Foundation
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct BackupPackage: Codable, Equatable {
    let schemaVersion: Int
    let exportedAt: Date
    let iosConfig: BackupIOSConfig
    let server: BackupServerSnapshot

    static let currentSchemaVersion = 1
}

nonisolated struct BackupIOSConfig: Codable, Equatable {
    let serverURL: String
    let lanURL: String
    let publicURL: String
    let autoSwitchNetwork: Bool
}

nonisolated struct BackupServerSnapshot: Codable, Equatable {
    let rpcBind: String
    let outputPath: String
    let appDataPath: String
    let liveRooms: [BackupLiveRoom]

    enum CodingKeys: String, CodingKey {
        case rpcBind = "rpc_bind"
        case outputPath = "out_put_path"
        case appDataPath = "app_data_path"
        case liveRooms = "live_rooms"
    }
}

nonisolated struct BackupLiveRoom: Codable, Equatable, Identifiable {
    let url: String
    let isListening: Bool

    var id: String { url }

    enum CodingKeys: String, CodingKey {
        case url
        case isListening = "is_listening"
    }
}

nonisolated struct BackupRemoteRecord: Codable, Equatable {
    let id: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
    }
}

nonisolated struct BackupRestoreResult: Codable, Equatable {
    let status: String
    let jobID: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case jobID = "job_id"
        case message
    }
}

nonisolated struct BackupRestorePackageRequest: Encodable {
    let package: BackupPackage
}

nonisolated struct BackupRestoreIDRequest: Encodable {
    let id: String
}

nonisolated struct ServerConfigSnapshot: Decodable {
    let rpc: ServerRPCSnapshot
    let outputPath: String
    let appDataPath: String
    let liveRooms: [ServerLiveRoomSnapshot]

    enum CodingKeys: String, CodingKey {
        case rpc
        case outputPath = "out_put_path"
        case appDataPath = "app_data_path"
        case liveRooms = "live_rooms"
    }
}

nonisolated struct ServerRPCSnapshot: Decodable {
    let bind: String
}

nonisolated struct ServerLiveRoomSnapshot: Decodable {
    let url: String
    let isListening: Bool

    enum CodingKeys: String, CodingKey {
        case url
        case isListening = "is_listening"
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var package: BackupPackage

    init(package: BackupPackage) {
        self.package = package
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        package = try JSONDecoder.backupDecoder.decode(BackupPackage.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder.backupEncoder.encode(package)
        return FileWrapper(regularFileWithContents: data)
    }
}

extension JSONEncoder {
    static var backupEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var backupDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
