import SwiftUI

struct VideoListView: View {
    let room: VideoRoomInfo
    @Environment(AppConfig.self) private var appConfig
    @State private var vm: VideoListViewModel?
    @State private var editMode: EditMode = .inactive
    @State private var deleteError: String?
    @State private var selectedFile: VideoFileInfo?

    var body: some View {
        Group {
            if let vm {
                fileList(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(room.hostName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbar }
        .environment(\.editMode, $editMode)
        .task {
            let model = VideoListViewModel(client: appConfig.client, room: room)
            vm = model
            await model.load()
        }
        .fullScreenCover(item: $selectedFile) { file in
            PlayerView(file: file, client: appConfig.client)
        }
        .onChange(of: selectedFile?.relPath) { _, newValue in
            // 播放页关闭后刷新列表，更新“已看 x%”徽章与进度条
            if newValue == nil, let vm {
                Task { await vm.load() }
            }
        }
        .alert("删除失败", isPresented: .constant(deleteError != nil), presenting: deleteError) { _ in
            Button("好") { deleteError = nil }
        } message: { Text($0) }
    }

    @ViewBuilder
    private func fileList(_ vm: VideoListViewModel) -> some View {
        @Bindable var vm = vm
        if vm.isLoading && vm.files.isEmpty {
            ProgressView("加载中…")
        } else if let err = vm.errorMessage {
            ContentUnavailableView("无法加载", systemImage: "exclamationmark.triangle", description: Text(err))
        } else if vm.files.isEmpty {
            ContentUnavailableView("暂无视频", systemImage: "tray", description: Text("该主播尚无录播文件"))
        } else {
            List(selection: $vm.selection) {
                ForEach(vm.files) { file in
                    FileRow(file: file, client: appConfig.client, history: vm.historyByPath[file.relPath], thumbnailRefreshToken: vm.thumbnailRefreshToken)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if editMode == .inactive { selectedFile = file }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("删除", role: .destructive) {
                                Task {
                                    do { try await vm.deleteFile(file) }
                                    catch { deleteError = error.localizedDescription }
                                }
                            }
                        }
                }
            }
            .refreshable { await vm.load() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button("刷新", systemImage: "arrow.clockwise") {
                Task { await vm?.load() }
            }
        }
        if let vm, !vm.files.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                if editMode == .active {
                    Button("删除(\(vm.selection.count))") {
                        Task {
                            do { try await vm.deleteSelected() }
                            catch { deleteError = error.localizedDescription }
                            editMode = .inactive
                        }
                    }
                    .disabled(vm.selection.isEmpty)
                    .tint(.red)
                } else {
                    EditButton()
                }
            }
        }
    }
}

private struct FileRow: View {
    let file: VideoFileInfo
    let client: APIClient
    let history: HistoryEntry?
    let thumbnailRefreshToken: Int

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: client.thumbnailURL(for: file), refreshToken: thumbnailRefreshToken) { phase in
                if case .success(let img) = phase {
                    img.resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 45)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.15)).frame(width: 80, height: 45)
                        .overlay { Image(systemName: "video").foregroundStyle(.secondary) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(file.name).font(.subheadline).lineLimit(2)
                    if file.recording == true || file.playbackStatus == "recording" {
                        Text("录制中")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                    }
                }
                HStack {
                    Text(file.sizeFormatted).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let watchedText {
                        Text(watchedText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(red: 0.05, green: 0.54, blue: 0.51))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(red: 0.90, green: 1.0, blue: 0.98), in: Capsule())
                    } else {
                        Text(file.modDate, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let progressRatio {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.secondary.opacity(0.18))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(Color(red: 0.12, green: 0.86, blue: 0.78))
                                    .frame(width: proxy.size.width * progressRatio)
                            }
                    }
                    .frame(height: 4)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var progressRatio: CGFloat? {
        guard let history, history.durationSeconds > 0, history.positionSeconds > 5 else { return nil }
        let ratio = history.positionSeconds / history.durationSeconds
        return min(max(CGFloat(ratio), 0), 1)
    }

    private var watchedText: String? {
        guard let progressRatio else { return nil }
        return "已看 \(Int((progressRatio * 100).rounded()))%"
    }
}
