import SwiftUI

struct HistoryView: View {
    @Environment(AppConfig.self) private var appConfig
    @State private var vm: HistoryViewModel?
    @State private var selectedFile: VideoFileInfo?

    var body: some View {
        NavigationStack {
            Group {
                if let vm {
                    historyContent(vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("观看历史")
            .background(Color(.systemGroupedBackground))
            .fullScreenCover(item: $selectedFile) { file in
                PlayerView(file: file, client: appConfig.client)
            }
            .task {
                let model = HistoryViewModel(client: appConfig.client)
                vm = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func historyContent(_ vm: HistoryViewModel) -> some View {
        if vm.isLoading && vm.entries.isEmpty {
            ProgressView("加载中…")
        } else if appConfig.apiKey.isEmpty {
            ContentUnavailableView("未绑定 API Key", systemImage: "key.fill", description: Text("请先在设置中绑定 Key，以同步你的观看历史"))
        } else if let err = vm.errorMessage {
            ContentUnavailableView("无法加载观看历史", systemImage: "exclamationmark.triangle", description: Text(err))
        } else if vm.entries.isEmpty {
            ContentUnavailableView("暂无观看历史", systemImage: "clock.fill", description: Text("观看过的视频会同步到当前 Key 用户"))
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(vm.entries) { entry in
                        HistoryCard(entry: entry, client: appConfig.client) {
                            Task { await vm.deleteEntry(entry) }
                        }
                        .onTapGesture {
                            selectedFile = entry.videoFile
                        }
                    }
                }
                .padding()
            }
            .refreshable { await vm.load() }
        }
    }
}

// MARK: - History Card

private struct HistoryCard: View {
    let entry: HistoryEntry
    let client: APIClient
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            AsyncImage(url: client.thumbnailURL(for: entry.videoPath)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    placeholder
                default:
                    Color.secondary.opacity(0.15)
                        .overlay { ProgressView() }
                }
            }
            .frame(width: 140, height: 78)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            // Info
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.displayName)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                
                Spacer(minLength: 0)
                
                HStack {
                    Text("\(formatTime(entry.positionSeconds)) / \(formatTime(entry.durationSeconds))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.updatedAt.components(separatedBy: " ").first ?? "")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                // Progress Bar
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: proxy.size.width * progressRatio)
                        }
                }
                .frame(height: 4)
            }
            .padding(.vertical, 4)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("删除记录", systemImage: "trash")
            }
        }
    }
    
    private var progressRatio: CGFloat {
        guard entry.durationSeconds > 0 else { return 0 }
        let ratio = CGFloat(entry.positionSeconds / entry.durationSeconds)
        return min(max(ratio, 0), 1)
    }

    private var placeholder: some View {
        Color.secondary.opacity(0.15)
            .overlay { Image(systemName: "video.slash").foregroundStyle(.secondary) }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - ViewModel

@Observable
final class HistoryViewModel {
    var entries: [HistoryEntry] = []
    var isLoading = false
    var errorMessage: String?

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    @MainActor
    func load() async {
        isLoading = entries.isEmpty
        errorMessage = nil
        do {
            entries = try await client.getWatchHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    func deleteEntry(_ entry: HistoryEntry) async {
        do {
            try await client.deleteWatchHistory(videoPath: entry.videoPath)
            self.entries.removeAll { $0.videoPath == entry.videoPath }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Model

struct HistoryEntry: Identifiable, Codable, Equatable {
    let id: Int64
    let videoPath: String
    let videoName: String
    let positionSeconds: Double
    let durationSeconds: Double
    let updatedAt: String

    var displayName: String {
        if !videoName.isEmpty { return videoName }
        return videoPath.split(separator: "/").last.map(String.init) ?? "未知视频"
    }

    var videoFile: VideoFileInfo {
        VideoFileInfo(
            name: displayName,
            relPath: videoPath,
            size: 0,
            modTime: Int64(parsedUpdatedAt?.timeIntervalSince1970.rounded() ?? 0),
            fileURL: nil,
            thumbnailURL: nil,
            hlsURL: nil,
            recording: nil,
            playbackStatus: nil
        )
    }

    private var parsedUpdatedAt: Date? {
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: updatedAt) { return date }
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case videoPath = "video_path"
        case videoName = "video_name"
        case positionSeconds = "position_seconds"
        case durationSeconds = "duration_seconds"
        case updatedAt = "updated_at"
    }
}


#Preview {
    HistoryView()
        .environment(AppConfig())
}
