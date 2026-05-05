import SwiftUI

struct RoomListView: View {
    @Environment(AppConfig.self) private var appConfig
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm: RoomListViewModel?
    @State private var showAddSheet = false
    @State private var addInput = ""
    @State private var isAdding = false
    @State private var addError: String?
    @State private var deleteError: String?
    @State private var actionError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let vm {
                    roomList(vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("直播间")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("添加", systemImage: "plus") { showAddSheet = true }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("刷新", systemImage: "arrow.clockwise") {
                        Task { await vm?.load() }
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) { addSheet }
            .task {
                let model = RoomListViewModel(client: appConfig.client)
                vm = model
                await model.load()
                await refreshRoomsWhileVisible(model)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await vm?.load(useCache: false, silent: true) }
                }
            }
            .alert("删除失败", isPresented: .constant(deleteError != nil), presenting: deleteError) { _ in
                Button("好") { deleteError = nil }
            } message: { Text($0) }
            .alert("操作失败", isPresented: .constant(actionError != nil), presenting: actionError) { _ in
                Button("好") { actionError = nil }
            } message: { Text($0) }
        }
    }

    @ViewBuilder
    private func roomList(_ vm: RoomListViewModel) -> some View {
        if vm.isLoading && vm.rooms.isEmpty {
            ProgressView("加载中…")
        } else if let err = vm.errorMessage {
            ContentUnavailableView("无法加载", systemImage: "exclamationmark.triangle", description: Text(err))
        } else if vm.rooms.isEmpty {
            ContentUnavailableView("暂无直播间", systemImage: "antenna.radiowaves.left.and.right", description: Text("点右上角 + 添加抖音直播间"))
        } else {
            List {
                ForEach(vm.rooms) { room in
                    RoomRow(room: room, client: appConfig.client) {
                        Task {
                            do { try await vm.deleteRoom(room) }
                            catch { deleteError = error.localizedDescription }
                        }
                    } onToggle: {
                        Task {
                            do { try await vm.toggleListening(room) }
                            catch { actionError = error.localizedDescription }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .listStyle(.plain)
            .background(Color(.systemGroupedBackground))
            .refreshable { await vm.load() }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("抖音直播间链接或分享文案", text: $addInput, axis: .vertical)
                        .lineLimit(3...6)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("支持 live.douyin.com 链接、抖音短链或完整分享文案，服务器将自动解析。")
                }
                if let err = addError {
                    Section { Text(err).foregroundStyle(.red) }
                }
                Section {
                    Button(action: submitAdd) {
                        HStack {
                            Spacer()
                            if isAdding { ProgressView().tint(.white) }
                            else { Text("添加").bold() }
                            Spacer()
                        }
                    }
                    .disabled(addInput.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
                }
            }
            .navigationTitle("添加直播间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showAddSheet = false }
                }
            }
        }
    }

    private func submitAdd() {
        guard let vm else { return }
        isAdding = true
        addError = nil
        Task {
            do {
                try await vm.addRoom(rawInput: addInput)
                showAddSheet = false
                addInput = ""
            } catch {
                addError = error.localizedDescription
            }
            isAdding = false
        }
    }

    private func refreshRoomsWhileVisible(_ model: RoomListViewModel) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            if Task.isCancelled { return }
            await model.load(useCache: false, silent: true)
        }
    }
}

private struct RoomRow: View {
    let room: LiveInfo
    let client: APIClient
    let onDelete: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Status Indicator (Neon Glow effect)
            ZStack {
                Circle()
                    .fill(room.recording ? Color.red : room.listening ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 12, height: 12)
                
                if room.recording || room.listening {
                    Circle()
                        .stroke(room.recording ? Color.red.opacity(0.4) : Color.green.opacity(0.4), lineWidth: 4)
                        .frame(width: 18, height: 18)
                }
            }
            .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(room.hostName.isEmpty ? "未知主播" : room.hostName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(room.roomName.isEmpty ? "—" : room.roomName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onToggle) {
                Text(room.listening ? "停止" : "监听")
                    .font(.subheadline.bold())
                    .foregroundStyle(room.listening ? Color.orange : Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        room.listening ? Color.orange.opacity(0.15) : Color.accentColor,
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
