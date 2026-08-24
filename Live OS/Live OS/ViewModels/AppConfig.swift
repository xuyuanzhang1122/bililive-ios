import Foundation
import Network
import Security

@Observable
final class AppConfig {
    var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: "serverURL")
            _cachedClient = nil
        }
    }

    var lanURL: String {
        didSet {
            UserDefaults.standard.set(lanURL, forKey: "lanURL")
            _cachedClient = nil
        }
    }

    var publicURL: String {
        didSet {
            UserDefaults.standard.set(publicURL, forKey: "publicURL")
            _cachedClient = nil
        }
    }

    var autoSwitchNetwork: Bool {
        didSet {
            UserDefaults.standard.set(autoSwitchNetwork, forKey: "autoSwitchNetwork")
            if autoSwitchNetwork {
                startNetworkMonitor()
            } else {
                stopNetworkMonitor()
            }
        }
    }

    var apiKey: String {
        didSet {
            APIKeychain.save(key: apiKey)
            _cachedClient = nil
        }
    }

    /// 备份服务器（源站）地址：远端备份存放在这里，主服务器重装后仍可按 ID 找回
    var backupServerURL: String {
        didSet {
            UserDefaults.standard.set(backupServerURL, forKey: "backupServerURL")
            _cachedBackupClient = nil
        }
    }

    /// The currently active URL (auto-switched or manual)
    var activeURL: String {
        if autoSwitchNetwork {
            if !lanURL.isEmpty && !publicURL.isEmpty {
                return isOnLAN ? lanURL : publicURL
            }
            // Partial config: use whichever is filled
            if !lanURL.isEmpty { return lanURL }
            if !publicURL.isEmpty { return publicURL }
        }
        return serverURL
    }

    /// Whether we're currently detected as being on the LAN
    private(set) var isOnLAN: Bool = false

    @ObservationIgnored
    private var _cachedClient: APIClient?

    @ObservationIgnored
    private var _cachedBackupClient: APIClient?

    @ObservationIgnored
    private var monitor: NWPathMonitor?

    @ObservationIgnored
    private var monitorQueue = DispatchQueue(label: "NetworkMonitor")

    @ObservationIgnored
    private var lanCheckTask: Task<Void, Never>?

    var client: APIClient {
        let url = activeURL
        if let existing = _cachedClient, existing.baseURL == url {
            return existing
        }
        let fresh = APIClient(baseURL: url, apiKey: apiKey)
        _cachedClient = fresh
        return fresh
    }

    /// 指向备份服务器的客户端；未配置时为 nil（此时备份回落到主服务器存储）
    var backupClient: APIClient? {
        let url = backupServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        if let existing = _cachedBackupClient, existing.baseURL == url {
            return existing
        }
        let fresh = APIClient(baseURL: url, apiKey: "")
        _cachedBackupClient = fresh
        return fresh
    }

    init() {
        serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        lanURL = UserDefaults.standard.string(forKey: "lanURL") ?? ""
        publicURL = UserDefaults.standard.string(forKey: "publicURL") ?? ""
        autoSwitchNetwork = UserDefaults.standard.bool(forKey: "autoSwitchNetwork")
        backupServerURL = UserDefaults.standard.string(forKey: "backupServerURL") ?? ""
        // 优先读 Keychain，缺失则从 UserDefaults 迁移
        apiKey = APIKeychain.load() ?? UserDefaults.standard.string(forKey: "apiKey") ?? ""
        if !apiKey.isEmpty && UserDefaults.standard.string(forKey: "apiKey") != nil {
            APIKeychain.save(key: apiKey)
            UserDefaults.standard.removeObject(forKey: "apiKey")
        }

        if autoSwitchNetwork && !lanURL.isEmpty && !publicURL.isEmpty {
            startNetworkMonitor()
        }
    }

    func applySettings(serverURL: String, apiKey: String) {
        self.serverURL = serverURL
        self.apiKey = apiKey
    }

    func applyNetworkSettings(lanURL: String, publicURL: String, autoSwitch: Bool) {
        self.lanURL = lanURL
        self.publicURL = publicURL
        self.autoSwitchNetwork = autoSwitch
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitor() {
        stopNetworkMonitor()

        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            switch path.status {
            case .satisfied where path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet):
                // WiFi/有线才可能直连局域网服务器，重新探测确认
                self.checkLANConnectivity()
            default:
                // 蜂窝或无网络时局域网地址必然不可达，直接判定公网，省去探测等待
                self.setNotOnLAN()
            }
        }
        monitor?.start(queue: monitorQueue)
        // NWPathMonitor 启动后会立刻回调一次当前网络状态，无需额外做初始探测
    }

    private func stopNetworkMonitor() {
        monitor?.cancel()
        monitor = nil
        lanCheckTask?.cancel()
        lanCheckTask = nil
    }

    private func checkLANConnectivity() {
        lanCheckTask?.cancel()
        lanCheckTask = Task { [weak self] in
            guard let self, !self.lanURL.isEmpty else { return }

            let lanReachable = await self.pingServer(self.lanURL)

            // 如果首次检测失败，短暂等待后重试一次（避免瞬时不可达误判）
            let finalResult: Bool
            if !lanReachable {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                finalResult = await self.pingServer(self.lanURL)
            } else {
                finalResult = true
            }

            if !Task.isCancelled {
                applyLANResult(finalResult)
            }
        }
    }

    /// 蜂窝/无网络时直接判定不在局域网，同时取消仍在进行中的探测
    private func setNotOnLAN() {
        lanCheckTask?.cancel()
        lanCheckTask = nil
        applyLANResult(false)
    }

    private func applyLANResult(_ value: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let changed = self.isOnLAN != value
            self.isOnLAN = value
            if changed {
                // 网络环境变化，清除 APIClient 缓存以强制使用新 URL
                self._cachedClient = nil
            }
        }
    }

    /// Try a quick HTTP GET to see if the server at the given URL is reachable
    private func pingServer(_ urlString: String) async -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/api/info") else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 2

        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            // 收到任何 HTTP 状态码（含 401/404/405）都说明服务器可达；
            // 只有请求本身抛错（超时、无路由、被系统拒绝）才视为不可达
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status > 0
        } catch {
            return false
        }
    }

    /// Manually trigger a LAN check (e.g., user pulls to refresh)
    func refreshNetworkStatus() {
        if autoSwitchNetwork && !lanURL.isEmpty && !publicURL.isEmpty {
            checkLANConnectivity()
        }
    }
}

// MARK: - Keychain

private enum APIKeychain {
    private static let service = "com.bililive-go.ios"

    static func save(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "apiKey",
        ]
        SecItemDelete(query as CFDictionary)
        guard !key.isEmpty else { return }
        let data = Data(key.utf8)
        var addQuery = query
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "apiKey",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
