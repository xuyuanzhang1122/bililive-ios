import Foundation

final class FixtureProtocol: URLProtocol {
    nonisolated(unsafe) static var body = ""
    nonisolated(unsafe) static var libraryCachePolicy: URLRequest.CachePolicy?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.path.hasSuffix("/api/video-library") == true {
            Self.libraryCachePolicy = request.cachePolicy
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body.data(using: .utf8)!)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct PlaybackContractTests {
    @MainActor static func main() async throws {
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            if !condition { failures += 1; print("FAIL: \(name)") }
        }
        let client = APIClient(baseURL: "https://server/proxy/", apiKey: "secret", playbackAPIMode: .legacy)
        check(client.absoluteURL("https://cdn/movie.mp4?sig=abc&expires=123")?.absoluteString == "https://cdn/movie.mp4?sig=abc&expires=123", "绝对签名地址保持不变")
        check(client.absoluteURL("/files/a.mp4?sig=abc&expires=123")?.absoluteString == "https://server/proxy/files/a.mp4?sig=abc&expires=123", "相对签名地址不追加 Key")
        check(client.absoluteURL("/files/a.mp4?_key=old")?.absoluteString == "https://server/proxy/files/a.mp4?_key=old", "已有 Key 不重复")
        check(client.absoluteURL("files/a.mp4")?.absoluteString == "https://server/proxy/files/a.mp4?_key=secret", "代理子路径和 Key 回退")
        check(client.absoluteURL("   ") == nil, "空地址拒绝")
        URLProtocol.registerClass(FixtureProtocol.self)
        for payload in ["{\"status\":\"unknown\"}", "{\"status\":\"ready\"}", "{\"status\":\"ready\",\"url\":\" \"}"] {
            FixtureProtocol.body = "{\"err_no\":0,\"err_msg\":\"\",\"data\":\(payload)}"
            do {
                _ = try await client.resolvePlayback("clip.flv")
                check(false, "非法 resolver 响应应失败: \(payload)")
            } catch {}
        }
        for (raw, expected) in [("null", 2.0), ("\"bad\"", 2.0), ("0", 1.0), ("99", 10.0), ("1.5", 1.5)] {
            FixtureProtocol.body = "{\"err_no\":0,\"err_msg\":\"\",\"data\":{\"status\":\"processing\",\"retry_after_seconds\":\(raw)}}"
            do {
                let result = try await client.resolvePlayback("clip.flv")
                check(Double(result.retryAfterSeconds ?? 2) == expected, "轮询值归一化 \(raw)")
            } catch { check(false, "异常轮询值应兼容 \(raw)") }
        }
        check(APIClient.canFallbackPlayback(APIError.serverError(404, "404 page not found")), "旧端点允许回退")
        check(APIClient.canFallbackPlayback(APIError.serverError(405, "Method Not Allowed")), "旧方法允许回退")
        for error in [APIError.unauthorized, APIError.serverError(404, "文件不存在"), APIError.serverError(-1, "响应缺失"), APIError.networkError(URLError(.timedOut))] {
            check(!APIClient.canFallbackPlayback(error), "真实错误不可回退")
        }
        let fixturesURL = URL(fileURLWithPath: "../bililive-go-UI/docs/contracts/playback-resolve-fixtures.json")
        let fixtures = try JSONSerialization.jsonObject(with: Data(contentsOf: fixturesURL)) as! [[String: Any]]
        for fixture in fixtures {
            let name = fixture["name"] as! String
            FixtureProtocol.body = String(data: try JSONSerialization.data(withJSONObject: fixture["response"]!), encoding: .utf8)!
            do {
                let result = try await client.resolvePlayback("clip.flv")
                check(fixture["reject"] as? Bool != true, "共享样例拒绝 \(name)")
                let response = fixture["response"] as! [String: Any]
                let payload = response["data"] as! [String: Any]
                check(result.status == payload["status"] as? String, "共享样例状态 \(name)")
                if let url = fixture["url"] as? String {
                    check(client.absoluteURL(result.url ?? "")?.absoluteString == url, "共享样例 URL \(name)")
                }
                if let retry = fixture["retry"] as? Double {
                    check(result.retryAfterSeconds == retry, "共享样例轮询 \(name)")
                }
            } catch { check(fixture["reject"] as? Bool == true, "共享样例意外失败 \(name): \(error)") }
        }
        FixtureProtocol.body = "{\"err_no\":0,\"err_msg\":\"\",\"data\":[{\"path\":\"a\",\"success\":true,\"message\":\"成功\"},{\"path\":\"b\",\"success\":false,\"message\":\"正在录制\"}]}"
        do {
            _ = try await client.deleteFiles(relPaths: ["a", "b"])
        } catch { check(false, "批量删除合法逐项数组应成功解包: \(error)") }
        let room = VideoRoomInfo(hostName: "主播", platform: "抖音", folderPath: "test-room", videoCount: 3, totalSize: 3,
                                 latestVideoAt: 0, latestVideo: nil, recording: false, url: nil)
        let model = VideoListViewModel(client: client, room: room)
        let files = ["a", "b", "c"].map { VideoFileInfo(name: $0, relPath: $0, size: 1, modTime: 0, fileURL: nil,
                thumbnailURL: nil, hlsURL: nil, recording: false, playbackStatus: "ready") }
        model.files = files
        model.selection = ["a", "b"]
        check(try await model.deleteSelected() == 1, "批删返回真实成功数量")
        check(model.deleteFailures.first?.message == "正在录制", "批删保留失败原因")
        check(model.files.map(\.id) == ["b", "c"], "批删只移除成功项")
        check(model.selection == ["b"], "批删保留失败选择")
        let cached = CacheManager.shared.load(forKey: "VideoListFiles_https:%2F%2Fserver%2Fproxy_test-room", as: [VideoFileInfo].self)
        check(cached?.map(\.id) == ["b", "c"], "批删同步剩余列表缓存")
        for payload in ["[]", "[{\"path\":\"a\",\"success\":false,\"message\":\"失败\"},{\"path\":\"b\",\"success\":false,\"message\":\"失败\"}]"] {
            model.files = files; model.selection = ["a", "b"]
            FixtureProtocol.body = "{\"err_no\":0,\"err_msg\":\"\",\"data\":\(payload)}"
            check(try await model.deleteSelected() == 0, "全部失败或遗漏返回零")
            check(model.files.map(\.id) == ["a", "b", "c"], "全部失败或遗漏保留文件")
            check(model.selection == ["a", "b"], "全部失败或遗漏保留选择")
        }
        for payload in ["null", "{}", "[{\"path\":\"a\",\"success\":\"true\"}]", "[{\"path\":\"a\",\"success\":true},{\"path\":\"a\",\"success\":false}]"] {
            model.files = files; model.selection = ["a", "b"]
            FixtureProtocol.body = "{\"err_no\":0,\"err_msg\":\"\",\"data\":\(payload)}"
            do { try await model.deleteSelected(); check(false, "非法批删结果必须失败") } catch {}
            check(model.files.map(\.id) == ["a", "b", "c"], "非法结果不能移除文件")
        }
        model.files = files; model.selection = ["a", "b"]
        FixtureProtocol.body = "{\"err_no\":500,\"err_msg\":\"请求失败\",\"data\":null}"
        do { try await model.deleteSelected(); check(false, "请求失败不能伪报成功") } catch {}
        check(model.files.count == 3 && model.selection == ["a", "b"], "请求失败保持状态")
        let nestedRoom = VideoRoomInfo(hostName: "主播", platform: "抖音", folderPath: "test/room", videoCount: 1, totalSize: 1,
                                       latestVideoAt: 0, latestVideo: nil, recording: false, url: nil)
        let nestedModel = VideoListViewModel(client: client, room: nestedRoom)
        nestedModel.files = files; nestedModel.selection = ["a"]
        FixtureProtocol.body = "{\"err_no\":0,\"err_msg\":\"\",\"data\":[{\"path\":\"a\",\"success\":true}]}"
        _ = try await nestedModel.deleteSelected()
        check(CacheManager.shared.stored["VideoListFiles_https:%2F%2Fserver%2Fproxy_test%2Froom"] != nil, "房间相对路径不能变成缓存子目录")
        FixtureProtocol.body = "[{\"host_name\":\"主播\",\"platform\":\"抖音\",\"folder_path\":\"抖音/主播\",\"video_count\":1,\"total_size\":176,\"total_size_text\":\"189.0 GB\",\"statistics_status\":\"verified\",\"statistics_checked_at\":1790000000,\"latest_video_at\":0,\"recording\":false}]"
        let libraryRooms = try await client.getVideoLibrary()
        check(FixtureProtocol.libraryCachePolicy == .reloadIgnoringLocalCacheData, "视频库请求绕过旧 HTTP 缓存")
        check(libraryRooms[0].totalSizeFormatted == "189.0 GB", "视频库优先显示服务端统计文本")
        let legacyRoom = VideoRoomInfo(hostName: "主播", platform: "抖音", folderPath: "test", videoCount: 1,
                                      totalSize: 188978561024, latestVideoAt: 0, latestVideo: nil, recording: false, url: nil)
        check(legacyRoom.totalSizeFormatted == "189.0 GB", "旧服务端大小使用相同十进制规则")
        FixtureProtocol.body = "[{\"host_name\":\"主播\",\"platform\":\"抖音\",\"folder_path\":\"抖音/主播\",\"video_count\":0,\"total_size\":176,\"total_size_text\":\"176 GB\",\"statistics_status\":\"unavailable\",\"latest_video_at\":0,\"recording\":false}]"
        let unavailableRooms = try await client.getVideoLibrary()
        check(unavailableRooms[0].totalSizeFormatted == "统计暂不可用", "视频库不能显示未核验统计")
        let libraryModel = VideoLibraryViewModel(client: client)
        libraryModel.rooms = [legacyRoom]
        FixtureProtocol.body = "{}"
        await libraryModel.load()
        check(libraryModel.errorMessage != nil, "缓存存在时仍报告统计刷新失败")
        CacheManager.shared.save([legacyRoom], forKey: "VideoLibraryRooms")
        let otherClient = APIClient(baseURL: "https://other-server", apiKey: "")
        let otherModel = VideoLibraryViewModel(client: otherClient)
        await otherModel.load()
        check(otherModel.rooms.isEmpty, "另一服务器不能读取旧全局视频库缓存")
        FixtureProtocol.body = "[{\"host_name\":\"主播\",\"platform\":\"抖音\",\"folder_path\":\"抖音/主播\",\"video_count\":2,\"total_size\":200000000000,\"total_size_text\":\"200.0 GB\",\"statistics_status\":\"verified\",\"latest_video_at\":0,\"recording\":false}]"
        await libraryModel.load()
        check(libraryModel.errorMessage == nil && libraryModel.rooms[0].totalSize == 200000000000,
              "刷新以服务端新总量替换缓存并清除错误")
        if failures > 0 { exit(1) }
        print("PASS: 19 播放契约检查 + 15 共享服务端样例 + iOS 批删回归 + 7 视频库统计检查")
    }
}
