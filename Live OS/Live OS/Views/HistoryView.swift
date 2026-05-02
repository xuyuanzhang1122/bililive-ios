import SwiftUI

struct HistoryView: View {
    @Environment(AppConfig.self) private var appConfig
    @State private var vm: HistoryViewModel?

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
        } else if let err = vm.errorMessage, vm.entries.isEmpty {
            ContentUnavailableView("无法加载", systemImage: "exclamationmark.triangle", description: Text(err))
        } else if vm.entries.isEmpty {
            ContentUnavailableView("暂无观看历史", systemImage: "clock", description: Text("观看过的视频会出现在这里"))
        } else {
            List {
                ForEach(vm.entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.displayName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            Text("\(formatTime(entry.positionSeconds)) / \(formatTime(entry.durationSeconds))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.blue)
                            Text(entry.updatedAt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    Task { await vm.deleteEntries(at: offsets) }
                }
            }
            .refreshable { await vm.load() }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds > 0 else { return "00:00" }
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
        let cacheKey = "WatchHistory"
        // 先读缓存
        if let cached: [HistoryEntry] = CacheManager.shared.load(forKey: cacheKey, as: [HistoryEntry].self), entries.isEmpty {
            self.entries = cached
        }
        isLoading = entries.isEmpty
        errorMessage = nil
        do {
            let newEntries = try await client.getWatchHistory()
            self.entries = newEntries
            CacheManager.shared.save(newEntries, forKey: cacheKey)
        } catch {
            if entries.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    @MainActor
    func deleteEntries(at offsets: IndexSet) async {
        for idx in offsets {
            let entry = entries[idx]
            try? await client.deleteWatchHistory(videoPath: entry.videoPath)
        }
        entries.remove(atOffsets: offsets)
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
