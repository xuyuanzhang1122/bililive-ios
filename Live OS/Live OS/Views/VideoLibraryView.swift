import SwiftUI

struct VideoLibraryView: View {
    @Environment(AppConfig.self) private var appConfig
    @State private var vm: VideoLibraryViewModel?

    let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if let vm {
                    libraryContent(vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("视频库")
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Button("刷新", systemImage: "arrow.clockwise") {
                        Task { await vm?.load() }
                    }
                }
            }
            .task {
                let model = VideoLibraryViewModel(client: appConfig.client)
                vm = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func libraryContent(_ vm: VideoLibraryViewModel) -> some View {
        if vm.isLoading && vm.rooms.isEmpty {
            ProgressView("加载中…")
        } else if let err = vm.errorMessage {
            ContentUnavailableView("无法加载", systemImage: "exclamationmark.triangle", description: Text(err))
        } else if vm.rooms.isEmpty {
            ContentUnavailableView("暂无录播", systemImage: "tray", description: Text("录播完成后会出现在这里"))
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(vm.rooms) { room in
                        NavigationLink(destination: VideoListView(room: room)) {
                            RoomCard(room: room, client: appConfig.client)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .refreshable { await vm.load() }
        }
    }
}

private struct RoomCard: View {
    let room: VideoRoomInfo
    let client: APIClient

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: thumbnailURL) { phase in
                switch phase {
                case .success(let img):
                    ZStack {
                        img.resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                            .blur(radius: 20)
                            .scaleEffect(1.2)
                        
                        Color.black.opacity(0.3)
                        
                        img.resizable()
                            .aspectRatio(contentMode: .fit)
                        
                        // Play Icon Overlay
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.5), radius: 4)
                    }
                    .aspectRatio(16/9, contentMode: .fill)
                case .failure:
                    placeholder
                default:
                    Color.secondary.opacity(0.15).aspectRatio(16/9, contentMode: .fill).overlay { ProgressView() }
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
            
            // Bottom Info Container with slight blur
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(room.hostName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if room.recording {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("直播中")
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.8), in: Capsule())
                    }
                }
                
                HStack {
                    Label("\(room.videoCount) 视频", systemImage: "film")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(room.totalSizeFormatted)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }

    private var thumbnailURL: URL? {
        guard let latest = room.latestVideo else { return nil }
        return client.thumbnailURL(for: latest)
    }

    private var placeholder: some View {
        Color.secondary.opacity(0.15)
            .aspectRatio(16/9, contentMode: .fill)
            .overlay { Image(systemName: "video").font(.largeTitle).foregroundStyle(.secondary) }
    }
}
