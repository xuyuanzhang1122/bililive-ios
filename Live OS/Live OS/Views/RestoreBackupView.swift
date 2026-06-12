import SwiftUI
import UniformTypeIdentifiers

struct RestoreBackupView: View {
    @Environment(AppConfig.self) private var appConfig

    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var restoreID = ""
    @State private var importedPackage: BackupPackage?
    @State private var showImporter = false

    var body: some View {
        Form {
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
        .navigationTitle("恢复备份")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }
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
                // 配置了备份服务器时从源站取包再恢复到主服务器；
                // 否则按旧行为让主服务器用本地存储的 ID 恢复
                let result: BackupRestoreResult
                let package: BackupPackage
                if let backupClient = appConfig.backupClient {
                    package = try await backupClient.fetchRemoteBackup(id: id)
                    result = try await appConfig.client.restoreBackup(package: package)
                } else {
                    package = try await appConfig.client.fetchRemoteBackup(id: id)
                    result = try await appConfig.client.restoreBackup(id: id)
                }
                let finalResult = try await pollRestoreIfNeeded(result)
                await MainActor.run {
                    applyIOSConfig(from: package)
                    importedPackage = package
                    statusMessage = finalResult.message ?? "恢复完成，正在同步 iOS 配置"
                }
            } catch {
                await MainActor.run { errorMessage = backupErrorMessage(error) }
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
                await MainActor.run { errorMessage = backupErrorMessage(error) }
            }
            await MainActor.run { isWorking = false }
        }
    }

    private func pollRestoreIfNeeded(_ result: BackupRestoreResult) async throws -> BackupRestoreResult {
        guard let jobID = result.jobID, ["pending", "running", "restarting"].contains(result.status) else { return result }
        var latest = result
        for _ in 0..<20 {
            try await Task.sleep(for: .seconds(2))
            do {
                latest = try await appConfig.client.getRestoreStatus(jobID: jobID)
                if !["pending", "running", "restarting"].contains(latest.status) { return latest }
            } catch {
                // 重启后任务表在内存中丢失：服务可达但任务 404 即视为重启完成
                if case APIError.serverError(let code, _) = error, code == 404 {
                    return BackupRestoreResult(status: "completed", jobID: jobID, message: "服务已重启完成")
                }
                // 重启期间连接失败属于预期，继续轮询
                continue
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
