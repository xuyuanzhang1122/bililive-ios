import SwiftUI

struct VideoLibraryView: View {
    @Environment(AppConfig.self) private var appConfig
    @State private var vm: VideoLibraryViewModel?

    // 采用更宽的卡片布局，适配不同尺寸屏幕
    let columns = [GridItem(.adaptive(minimum: 160, maximum: 300), spacing: 16)]

    var body: some View {
        NavigationStack {
            ZStack {
                // 动态渐变背景
                LinearGradient(
                    colors: [Color(UIColor.systemGroupedBackground), Color.blue.opacity(0.05), Color.purple.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if let vm {
                    libraryContent(vm)
                } else {
                    ProgressView()
                        .controlSize(.large)
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
                .foregroundStyle(.secondary)
        } else if let err = vm.errorMessage {
            ContentUnavailableView("无法加载", systemImage: "exclamationmark.triangle", description: Text(err))
        } else if vm.rooms.isEmpty {
            ContentUnavailableView("暂无录播", systemImage: "film", description: Text("录播完成后会出现在这里"))
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(vm.rooms) { room in
                        NavigationLink(destination: VideoListView(room: room)) {
                            RoomCard(room: room, client: appConfig.client)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
            // 封面图区域
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    default:
                        ZStack {
                            Color.secondary.opacity(0.1)
                            ProgressView()
                        }
                    }
                }
                .frame(height: 200) // 固定高度，防止竖屏图片撑爆页面
                .frame(maxWidth: .infinity)
                .clipped()

                // 直播状态标签 (Glassmorphism)
                if room.recording {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("直播中")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(8)
                }
                
                // 播放图标居中悬浮
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 200)

            // 底部信息容器 (Glassmorphism 风格)
            VStack(alignment: .leading, spacing: 8) {
                Text(room.hostName)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                HStack {
                    Label("\(room.videoCount) 个视频", systemImage: "play.rectangle.on.rectangle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(room.totalSizeFormatted)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.blue.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(14)
            .background(.regularMaterial) // 毛玻璃材质
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        // 增加微微的白边，增强立体感
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
    }

    private var thumbnailURL: URL? {
        guard let latest = room.latestVideo else { return nil }
        return client.thumbnailURL(for: latest)
    }

    private var placeholder: some View {
        Color.secondary.opacity(0.1)
            .overlay {
                Image(systemName: "photo.tv")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
    }
}
