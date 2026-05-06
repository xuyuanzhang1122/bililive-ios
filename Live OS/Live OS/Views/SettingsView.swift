import SwiftUI

// MARK: - Main Settings

struct SettingsView: View {
    @Environment(AppConfig.self) private var appConfig
    // isInitialSetup kept for API compatibility but no longer changes behavior
    let isInitialSetup: Bool

    @State private var showSaved = false
    @State private var serverVersion: String?
    @State private var isCheckingConnection = false
    @State private var connectionOK: Bool?

    var body: some View {
        NavigationStack {
            List {
                // MARK: 服务器
                serverSection

                // MARK: 认证
                authSection

                // MARK: 存储
                storageSection

                // MARK: 关于
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(colors: [Color(UIColor.systemGroupedBackground), Color.blue.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .overlay(alignment: .bottom) {
                if showSaved {
                    savedBadge
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showSaved)
        }
    }

    // MARK: - Sections

    private var serverSection: some View {
        Section {
            NavigationLink(destination: NetworkConfigView()) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("网络配置")
                        Text(networkSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "network")
                        .foregroundStyle(.blue)
                }
            }

            NavigationLink(destination: BackupRestoreView()) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("备份与恢复")
                        Text("导出服务器配置和直播间，支持按 ID 找回")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "archivebox.fill")
                        .foregroundStyle(.teal)
                }
            }

            // Connection status row
            HStack {
                Label {
                    Text("连接状态")
                } icon: {
                    Image(systemName: connectionStatusIcon)
                        .foregroundStyle(connectionStatusColor)
                }
                Spacer()
                if isCheckingConnection {
                    ProgressView().controlSize(.small)
                } else {
                    Button("测试") {
                        testConnection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    if let ok = connectionOK {
                        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(ok ? .green : .red)
                    }
                }
            }

            if let ver = serverVersion {
                Label {
                    Text(ver).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        } header: {
            Text("服务器")
        }
    }

    private var authSection: some View {
        Section {
            NavigationLink(destination: APIKeyView()) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("API Key")
                        Text(appConfig.apiKey.isEmpty ? "未设置" : "已配置 (\(maskedKey))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("认证")
        } footer: {
            Text("服务器启用 security.enable_api_key 后需要填写。")
        }
    }

    private var storageSection: some View {
        Section {
            NavigationLink(destination: StorageManagementView()) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("存储管理")
                        Text(storageSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "internaldrive.fill")
                        .foregroundStyle(.purple)
                }
            }
        } header: {
            Text("存储")
        }
    }

    private var storageSummary: String {
        let total = ThumbnailCache.shared.diskSizeBytes + CacheManager.shared.cacheDirectorySizeBytes
        return "已用 \(formatBytes(total))"
    }

    private func formatBytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb < 1 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", mb)
    }

    private var aboutSection: some View {
        Section {
            NavigationLink(destination: AboutVersionView()) {
                Label {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(appVersion).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                }
            }

            Link(destination: URL(string: "https://github.com/xuyuanzhang1122/bililive-ios")!) {
                Label {
                    Text("GitHub 开源项目")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "link")
                        .foregroundStyle(.blue)
                }
            }

            HStack {
                Spacer()
                Text("由 Xumy 开发")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            Text("关于")
        }
    }

    // MARK: - Helpers

    private var networkSummary: String {
        if appConfig.autoSwitchNetwork {
            let lan = appConfig.lanURL.isEmpty ? "未设置" : appConfig.lanURL
            return "智能切换 · \(appConfig.isOnLAN ? "局域网" : "公网")"
        }
        return appConfig.serverURL.isEmpty ? "未配置" : appConfig.serverURL
    }

    private var connectionStatusIcon: String {
        guard connectionOK != nil else { return "circle.dotted" }
        return connectionOK! ? "wifi" : "wifi.slash"
    }

    private var connectionStatusColor: Color {
        guard let ok = connectionOK else { return .secondary }
        return ok ? .green : .red
    }

    private var maskedKey: String {
        let k = appConfig.apiKey
        guard k.count > 4 else { return String(repeating: "•", count: k.count) }
        return String(repeating: "•", count: k.count - 4) + k.suffix(4)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func testConnection() {
        guard !appConfig.activeURL.isEmpty else {
            connectionOK = false
            return
        }
        isCheckingConnection = true
        connectionOK = nil
        serverVersion = nil
        Task {
            do {
                let info = try await appConfig.client.getServerInfo()
                await MainActor.run {
                    connectionOK = true
                    serverVersion = "\(info.appName) \(info.appVersion)"
                    isCheckingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionOK = false
                    isCheckingConnection = false
                }
            }
        }
    }

    private var savedBadge: some View {
        Text("已保存")
            .font(.subheadline)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Network Config Sub-page

struct NetworkConfigView: View {
    @Environment(AppConfig.self) private var appConfig
    @State private var mode: NetworkMode = .manual
    @State private var serverURL = ""
    @State private var lanURL = ""
    @State private var publicURL = ""
    @State private var showSaved = false

    enum NetworkMode: String, CaseIterable {
        case manual = "手动"
        case smart = "智能切换"
    }

    var body: some View {
        Form {
            // Mode picker
            Section {
                Picker("模式", selection: $mode) {
                    ForEach(NetworkMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(mode == .manual
                    ? "直接填写服务器地址。"
                    : "App 自动检测网络，在局域网时用内网地址，在外出时用公网地址，速度更快且更省流量。")
            }

            if mode == .manual {
                manualSection
            } else {
                smartSection
            }

            Section {
                Button(action: save) {
                    HStack {
                        Spacer()
                        Text("保存").bold()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("网络配置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadValues() }
        .overlay(alignment: .bottom) {
            if showSaved {
                Text("已保存")
                    .font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSaved)
        .animation(.easeInOut(duration: 0.2), value: mode)
    }

    private var manualSection: some View {
        Section {
            TextField("http://192.168.1.x:8080", text: $serverURL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text("服务器地址")
        } footer: {
            Text("运行 bililive-go 的设备 IP 和端口。")
        }
    }

    private var smartSection: some View {
        Group {
            Section {
                TextField("http://192.168.1.x:8080", text: $lanURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                HStack {
                    Image(systemName: "wifi").foregroundStyle(.green)
                    Text("局域网地址")
                }
            } footer: {
                Text("在家或店里，通过局域网直接访问，速度最快。")
            }

            Section {
                TextField("http://your-domain.com:8080", text: $publicURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                HStack {
                    Image(systemName: "globe").foregroundStyle(.blue)
                    Text("公网地址")
                }
            } footer: {
                Text("在外出时通过公网访问。需要在路由器设置端口转发，或使用 frp/cloudflare 等内网穿透。")
            }

            if appConfig.autoSwitchNetwork {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: appConfig.isOnLAN ? "wifi" : "globe")
                            .foregroundStyle(appConfig.isOnLAN ? .green : .blue)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appConfig.isOnLAN ? "当前：局域网" : "当前：公网")
                                .font(.subheadline)
                            Text(appConfig.activeURL.isEmpty ? "未配置" : appConfig.activeURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("当前连接")
                }
            }
        }
    }

    private func loadValues() {
        mode = appConfig.autoSwitchNetwork ? .smart : .manual
        serverURL = appConfig.serverURL
        lanURL = appConfig.lanURL
        publicURL = appConfig.publicURL
    }

    private func save() {
        let isSmart = mode == .smart
        appConfig.applySettings(
            serverURL: isSmart ? "" : serverURL.trimmingCharacters(in: .whitespaces),
            apiKey: appConfig.apiKey
        )
        appConfig.applyNetworkSettings(
            lanURL: lanURL.trimmingCharacters(in: .whitespaces),
            publicURL: publicURL.trimmingCharacters(in: .whitespaces),
            autoSwitch: isSmart
        )
        showSaved = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run { showSaved = false }
        }
    }
}

// MARK: - API Key Sub-page

struct APIKeyView: View {
    @Environment(AppConfig.self) private var appConfig
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var showSaved = false
    @State private var boundUser: APIKeyUser?
    @State private var isVerifying = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let boundUser {
                Section {
                    BoundKeyCard(user: boundUser, keySuffix: keySuffix)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                HStack {
                    Group {
                        if showKey {
                            TextField("留空表示不启用鉴权", text: $apiKey)
                        } else {
                            SecureField("留空表示不启用鉴权", text: $apiKey)
                        }
                    }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("API Key")
            } footer: {
                Text("粘贴 Web 管理台生成的 Key。验证成功后，此设备的观看历史和续播进度会同步到该 Key 对应的用户。")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            }

            if !apiKey.isEmpty {
                Section {
                    Button("清除", role: .destructive) {
                        apiKey = ""
                        boundUser = nil
                        errorMessage = nil
                        appConfig.applySettings(serverURL: appConfig.serverURL, apiKey: "")
                    }
                }
            }

            Section {
                Button(action: save) {
                    HStack {
                        Spacer()
                        if isVerifying {
                            ProgressView()
                        } else {
                            Text(apiKey.isEmpty ? "保存为空 Key" : "测试并绑定").bold()
                        }
                        Spacer()
                    }
                }
                .disabled(isVerifying)
            }
        }
        .navigationTitle("API Key")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            apiKey = appConfig.apiKey
            Task { await refreshCurrentUser() }
        }
        .overlay(alignment: .bottom) {
            if showSaved {
                Text("已保存")
                    .font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSaved)
    }

    private func save() {
        Task {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                appConfig.applySettings(serverURL: appConfig.serverURL, apiKey: "")
                boundUser = nil
                errorMessage = nil
                await showSavedBadge()
                return
            }
            guard !appConfig.activeURL.isEmpty else {
                errorMessage = "请先配置服务器地址"
                return
            }
            isVerifying = true
            errorMessage = nil
            do {
                let client = APIClient(baseURL: appConfig.activeURL, apiKey: trimmed)
                let user = try await client.getCurrentAPIKeyUser()
                appConfig.applySettings(serverURL: appConfig.serverURL, apiKey: trimmed)
                boundUser = user
                await showSavedBadge()
            } catch {
                errorMessage = error.localizedDescription
            }
            isVerifying = false
        }
    }

    @MainActor
    private func refreshCurrentUser() async {
        guard !appConfig.apiKey.isEmpty, !appConfig.activeURL.isEmpty else { return }
        do {
            boundUser = try await appConfig.client.getCurrentAPIKeyUser()
        } catch {
            boundUser = nil
        }
    }

    @MainActor
    private func showSavedBadge() async {
        showSaved = true
        try? await Task.sleep(for: .seconds(1.5))
        showSaved = false
    }

    private var keySuffix: String {
        let source = boundUser?.keySuffix ?? apiKey
        guard source.count > 4 else { return source }
        return String(source.suffix(4))
    }
}

private struct BoundKeyCard: View {
    let user: APIKeyUser
    let keySuffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(red: 0.12, green: 0.86, blue: 0.78))
                    Text(user.name.prefix(1).uppercased())
                        .font(.title2.bold())
                        .foregroundStyle(Color(red: 0.02, green: 0.17, blue: 0.16))
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(.headline)
                    Text("User ID · \(user.id)")
                        .font(.caption.monospaced())
                        .foregroundStyle(Color(red: 0.05, green: 0.54, blue: 0.51))
                        .lineLimit(1)
                }
                Spacer()
                Label("已同步", systemImage: "checkmark.icloud.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }

            HStack(spacing: 8) {
                statusPill("Key 末尾 \(keySuffix)")
                statusPill(user.lastUsedAt == nil ? "首次绑定" : "最近同步")
            }

            Text("此设备会只读取该用户的服务端观看历史；退出播放器时会把最新进度同步回后端。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(red: 0.93, green: 1.0, blue: 0.99))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color(red: 0.70, green: 0.96, blue: 0.93), lineWidth: 1)
                )
        )
    }

    private func statusPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.75), in: Capsule())
    }
}

// MARK: - Storage Management

struct StorageManagementView: View {
    @State private var thumbnailBytes: Int = 0
    @State private var apiCacheBytes: Int = 0
    @State private var showClearConfirm = false
    @State private var justCleared = false

    var body: some View {
        List {
            Section {
                cacheRow(label: "缩略图缓存", bytes: thumbnailBytes, icon: "photo.stack.fill", color: .blue)
                cacheRow(label: "接口数据缓存", bytes: apiCacheBytes, icon: "network", color: .teal)

                HStack {
                    Label {
                        Text("合计")
                            .fontWeight(.semibold)
                    } icon: {
                        Image(systemName: "sum")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(formatBytes(thumbnailBytes + apiCacheBytes))
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            } header: {
                Text("缓存占用")
            }

            Section {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("清除所有缓存", systemImage: "trash.fill")
                }
            } footer: {
                Text("清除后，缩略图和接口数据将在下次访问时重新从服务器加载。")
            }
        }
        .navigationTitle("存储管理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshSizes() }
        .confirmationDialog("确认清除全部缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                ThumbnailCache.shared.clearAll()
                CacheManager.shared.clearAll()
                refreshSizes()
                justCleared = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    justCleared = false
                }
            }
            Button("取消", role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if justCleared {
                Text("已清除")
                    .font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: justCleared)
    }

    private func cacheRow(label: String, bytes: Int, icon: String, color: Color) -> some View {
        HStack {
            Label {
                Text(label)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
            Spacer()
            Text(formatBytes(bytes))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func refreshSizes() {
        thumbnailBytes = ThumbnailCache.shared.diskSizeBytes
        apiCacheBytes = CacheManager.shared.cacheDirectorySizeBytes
    }

    private func formatBytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb < 1 { return "\(max(bytes / 1024, 0)) KB" }
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - About / Version Changelog

struct AboutVersionView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("1.1 版本更新内容")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .padding(.bottom, 4)

                    changelogItem(icon: "sparkles", color: .purple, text: "新增：全新玻璃拟物化 (Glassmorphism) 主页设计")
                    changelogItem(icon: "key.fill", color: .orange, text: "新增：支持服务端多用户 API Key 鉴权及进度隔离")
                    changelogItem(icon: "app.dashed", color: .blue, text: "新增：自适应 iOS 18 暗黑及染色模式的极客图标")
                    changelogItem(icon: "arrow.triangle.2.circlepath", color: .green, text: "优化：重构云端备份及播放进度双向同步逻辑")
                    changelogItem(icon: "hand.point.up.left.fill", color: .teal, text: "优化：加入全局触觉震动反馈 (Haptics)")
                    changelogItem(icon: "ant.fill", color: .red, text: "修复：视频库缩略图在特定比例下过大撑爆页面的问题")
                }
                .padding(.vertical, 8)
            } header: {
                Text("更新日志")
            } footer: {
                Text("感谢您使用 Live OS，我们将持续为您带来更好的录播观看体验！")
                    .padding(.top, 16)
            }
        }
        .navigationTitle("版本信息")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func changelogItem(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
