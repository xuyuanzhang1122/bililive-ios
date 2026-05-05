import SwiftUI
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @Environment(AppConfig.self) private var appConfig

    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var remoteID: String?
    @State private var restoreID = ""
    @State private var exportDocument: BackupDocument?
    @State private var importedPackage: BackupPackage?
    @State private var showExporter = false
    @State private var showImporter = false

    var body: some View {
        Form {
            Section {
                Button(action: createBackup) {
                    HStack {
                        Label("一键导出/备份", systemImage: "square.and.arrow.up")
                        Spacer()
                        if isWorking { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(isWorking || appConfig.activeURL.isEmpty)
            } footer: {
                Text("备份会包含服务器地址、端口绑定、输出目录、AppData 路径和直播间地址；不会包含 API Key、Cookie 或观看历史。")
            }

            if let remoteID {
                Section {
                    LabeledContent("备份 ID", value: remoteID)
                    Button("复制 ID", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = remoteID
                        statusMessage = "备份 ID 已复制"
                    }
                }
            }

            Section {
                Button("选择本地备份文件", systemImage: "folder") {
                    showImporter = true
                }

                TextField("输入服务器备份 ID", text: $restoreID)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button("通过 ID 找回配置", systemImage: "arrow.down.doc") {
                    restoreFromID()
                }
                .disabled(isWorking || restoreID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("恢复")
            } footer: {
                Text("恢复会要求后端写入配置并重启服务。当前服务器未实现接口时会提示暂不支持。")
            }

            if let importedPackage {
                Section {
                    BackupPreview(package: importedPackage)
                    Button("恢复这个备份", systemImage: "arrow.clockwise") {
                        restore(package: importedPackage)
                    }
                    .disabled(isWorking)
                } header: {
                    Text("已选择的备份")
                }
            }

            if let statusMessage {
                Section {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: defaultBackupFilename
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
    }

    private var defaultBackupFilename: String {
        "bililive-ios-backup-\(Int(Date().timeIntervalSince1970)).json"
    }

    private func createBackup() {
        isWorking = true
        statusMessage = nil
        errorMessage = nil
        remoteID = nil
        Task {
            do {
                let package = try await makeBackupPackage()
                await MainActor.run {
                    exportDocument = BackupDocument(package: package)
                    showExporter = true
                }
                do {
                    let record = try await appConfig.client.createRemoteBackup(package)
                    await MainActor.run {
                        remoteID = record.id
                        statusMessage = "本地备份已生成，远端备份已上传"
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = backupErrorMessage(error)
                        statusMessage = "本地备份已生成"
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            await MainActor.run { isWorking = false }
        }
    }

    private func makeBackupPackage() async throws -> BackupPackage {
        let server = try await appConfig.client.getServerBackupSnapshot()
        let iosConfig = BackupIOSConfig(
            serverURL: appConfig.serverURL,
            lanURL: appConfig.lanURL,
            publicURL: appConfig.publicURL,
            autoSwitchNetwork: appConfig.autoSwitchNetwork
        )
        return BackupPackage(
            schemaVersion: BackupPackage.currentSchemaVersion,
            exportedAt: Date(),
            iosConfig: iosConfig,
            server: server
        )
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let didStart = url.startAccessingSecurityScopedResource()
                defer {
                    if didStart { url.stopAccessingSecurityScopedResource() }
                }
                let data = try Data(contentsOf: url)
                importedPackage = try JSONDecoder.backupDecoder.decode(BackupPackage.self, from: data)
                statusMessage = "备份文件已读取，请确认后恢复"
                errorMessage = nil
            } catch {
                errorMessage = "备份文件无法解析：\(error.localizedDescription)"
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func restoreFromID() {
        let id = restoreID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        isWorking = true
        statusMessage = nil
        errorMessage = nil
        Task {
            do {
                let package = try await appConfig.client.fetchRemoteBackup(id: id)
                let result = try await appConfig.client.restoreBackup(id: id)
                let finalResult = try await pollRestoreIfNeeded(result)
                await MainActor.run {
                    applyIOSConfig(from: package)
                    importedPackage = package
                    statusMessage = finalResult.message ?? "恢复完成，正在同步 iOS 配置"
                }
            } catch {
                await MainActor.run {
                    errorMessage = backupErrorMessage(error)
                }
            }
            await MainActor.run { isWorking = false }
        }
    }

    private func restore(package: BackupPackage) {
        isWorking = true
        statusMessage = nil
        errorMessage = nil
        Task {
            do {
                let result = try await appConfig.client.restoreBackup(package: package)
                let finalResult = try await pollRestoreIfNeeded(result)
                await MainActor.run {
                    applyIOSConfig(from: package)
                    statusMessage = finalResult.message ?? "恢复完成，正在同步 iOS 配置"
                }
            } catch {
                await MainActor.run {
                    errorMessage = backupErrorMessage(error)
                }
            }
            await MainActor.run { isWorking = false }
        }
    }

    private func pollRestoreIfNeeded(_ result: BackupRestoreResult) async throws -> BackupRestoreResult {
        guard let jobID = result.jobID, ["pending", "running", "restarting"].contains(result.status) else {
            return result
        }
        var latest = result
        for _ in 0..<20 {
            try await Task.sleep(for: .seconds(2))
            latest = try await appConfig.client.getRestoreStatus(jobID: jobID)
            if !["pending", "running", "restarting"].contains(latest.status) {
                return latest
            }
        }
        return latest
    }

    @MainActor
    private func applyIOSConfig(from package: BackupPackage) {
        appConfig.applySettings(serverURL: package.iosConfig.serverURL, apiKey: appConfig.apiKey)
        appConfig.applyNetworkSettings(
            lanURL: package.iosConfig.lanURL,
            publicURL: package.iosConfig.publicURL,
            autoSwitch: package.iosConfig.autoSwitchNetwork
        )
        appConfig.refreshNetworkStatus()
    }

    private func backupErrorMessage(_ error: Error) -> String {
        if case APIError.serverError(let code, _) = error, code == 404 || code == 405 {
            return "当前服务器暂不支持备份接口，请先按后端接口文档实现。"
        }
        return error.localizedDescription
    }
}

private struct BackupPreview: View {
    let package: BackupPackage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("导出时间", value: package.exportedAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("服务器", value: package.iosConfig.autoSwitchNetwork ? "智能切换" : package.iosConfig.serverURL)
            LabeledContent("端口绑定", value: package.server.rpcBind)
            LabeledContent("输出目录", value: package.server.outputPath)
            LabeledContent("直播间", value: "\(package.server.liveRooms.count) 个")
        }
        .font(.subheadline)
    }
}
