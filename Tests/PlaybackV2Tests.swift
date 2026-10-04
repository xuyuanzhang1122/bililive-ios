import Foundation

final class V2FixtureProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (URLRequest) -> (Int, String) = { _ in (500, "") }
    nonisolated(unsafe) static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let (status, body) = Self.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct PlaybackV2Tests {
    @MainActor static func main() async throws {
        var failures = 0
        func check(_ condition: Bool, _ name: String) { if !condition { failures += 1; print("FAIL: \(name)") } }
        func fixture(_ name: String) throws -> String {
            let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "Tests/contracts/v2/v2-\(name).json"))) as! [String: Any]
            return String(data: try JSONSerialization.data(withJSONObject: raw["value"]!), encoding: .utf8)!
        }
        URLProtocol.registerClass(V2FixtureProtocol.self)
        let recordings = try fixture("recordings")
        V2FixtureProtocol.handler = { request in request.url!.path.contains("/api/v2/") ? (200, recordings) : (200, "[]") }
        let client = APIClient(baseURL: "https://server/proxy", apiKey: "secret")
        let files = try await client.getVideoFiles(folderPath: "平台/主播")
        check(files.count == 1, "v2 清单不能被旧清单空数组代替")
        if let file = files.first {
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(file)) as! [String: Any]
            check(encoded["recording_id"] as? String == "00000000-0000-4000-8000-000000000001", "文件保留稳定录播身份")
            check(file.sizeFormatted == "189.0 GB", "文件直接显示服务器核验文本")
        }
        check(client.absoluteURL("/api/v2/media/s/file?play_token=short")?.query == "play_token=short", "短媒体token不追加管理Key")
        check(client.absoluteURL("https://cdn/clip.mp4")?.query == nil, "跨源媒体不泄漏管理Key")
        V2FixtureProtocol.handler = { request in request.url!.path.contains("/api/v2/") ? (401, "{\"data\":null,\"error\":{\"code\":\"unauthorized\",\"message\":\"denied\",\"retryable\":false},\"request_id\":\"r\"}") : (200,"[]") }
        do { _ = try await client.getVideoFiles(folderPath: "平台/主播"); check(false, "v2 鉴权失败不得回退") } catch {}
        let ready = try fixture("session-ready")
        for name in ["session-ready", "session-processing", "session-paused", "session-failed"] {
            let body = try fixture(name)
            V2FixtureProtocol.handler = { _ in (200, body) }
            let value = try await client.getPlaybackSession("s")
            check(value.status.rawValue == name.replacingOccurrences(of: "session-", with: ""), "共享会话状态 \(name)")
            if value.status == .ready { check(value.url?.contains("_key=") == false, "会话媒体不泄漏Key") }
        }
        V2FixtureProtocol.handler = { _ in (410, try! fixture("session-expired")) }
        do { _ = try await client.getPlaybackSession("s"); check(false, "过期会话应失败") }
        catch let error as V2RequestError { check(error.failure.code == "session_expired" && !error.requestId.isEmpty, "保留结构化错误与请求标识") }
        catch { check(false, "错误不得丢失原code") }
        for fragment in ["\"status\":\"unknown\"", "\"url\":\"https://foreign/file?play_token=x\""] {
            var object = try JSONSerialization.jsonObject(with: Data(ready.utf8)) as! [String: Any]
            var data = object["data"] as! [String: Any]
            let fields = try JSONSerialization.jsonObject(with: Data(("{"+fragment+"}").utf8)) as! [String: Any]
            for (key,value) in fields { data[key] = value }; object["data"] = data
            let body = String(data: try JSONSerialization.data(withJSONObject: object), encoding:.utf8)!
            V2FixtureProtocol.handler = { _ in (200,body) }
            do { _ = try await client.getPlaybackSession("s"); check(false, "未知状态及跨源会话失败关闭") } catch {}
        }
        let batch = try fixture("batch-partial")
        V2FixtureProtocol.handler = { _ in (200,batch) }
        let second = VideoFileInfo(name: "b", relPath: "平台/主播/b.mp4", size: 1, modTime: 0, fileURL:nil,thumbnailURL:nil,hlsURL:nil,recording:false,playbackStatus:nil,
            recordingId:"00000000-0000-4000-8000-000000000003",sourceVersion:"version-b",sizeText:"1 B")
        if let first = files.first {
            let results = try await client.deleteRecordings([first,second])
            check(results.count == 1 && !results[0].success && results[0].message == "来源版本变化", "v2 批删保留逐项失败")
            let body = V2FixtureProtocol.requests.last?.httpBodyStream
            check(body != nil || V2FixtureProtocol.requests.last?.httpBody != nil, "v2 批删发送身份请求")
        }
        let unknown = VideoFileInfo(name:"old",relPath:"old",size:1,modTime:0,fileURL:nil,thumbnailURL:nil,hlsURL:nil,recording:false,playbackStatus:nil)
        do { _ = try await client.deleteRecordings([unknown]); check(false,"缺身份v2缓存不可删除") } catch {}
        let room = VideoRoomInfo(hostName:"主播",platform:"平台",folderPath:"平台/主播",videoCount:1,totalSize:1,latestVideoAt:0,latestVideo:nil,recording:false,url:nil)
        let model = VideoListViewModel(client:client,room:room)
        model.files = [unknown]; model.selection = ["old"]
        do { _ = try await model.deleteSelected(); check(false,"VM 不得绕过v2身份删除") } catch {}
        if let first = files.first {
            model.files = [first,second]; model.selection = [first.relPath,second.relPath]
            V2FixtureProtocol.handler = { _ in (200,batch) }
            do { check(try await model.deleteSelected() == 0 && model.deleteFailures.count == 2, "VM 保留失败项和遗漏项") }
            catch { check(false,"VM 消费v2批删结果") }
            check(V2FixtureProtocol.requests.last?.url?.path.hasSuffix("/api/v2/recordings/batch-delete") == true, "VM 必须使用稳定身份端点")
        }
        V2FixtureProtocol.handler = { _ in (401, "denied") }
        await model.load()
        check(model.errorMessage != nil, "缓存存在时仍显示新清单失败")
        V2FixtureProtocol.handler = { _ in (401,"denied") }
        let other = VideoListViewModel(client:APIClient(baseURL:"https://other",apiKey:"secret",playbackAPIMode:.legacy),room:room)
        await other.load()
        check(other.files.isEmpty,"另一服务器不读取旧文件列表缓存")
        let oldHistoryJSON = Data("{\"id\":1,\"video_path\":\"clip\",\"video_name\":\"clip\",\"position_seconds\":30,\"duration_seconds\":100,\"updated_at\":\"2026-10-04\"}".utf8)
        let oldHistory = try JSONDecoder().decode(HistoryEntry.self,from:oldHistoryJSON)
        check(!oldHistory.matches(identity:RecordingIdentity(recordingId:"id",sourceVersion:"v")),"无身份旧历史不能用于v2续播")
        var boundJSON = try JSONSerialization.jsonObject(with:oldHistoryJSON) as! [String:Any]
        boundJSON["recording_id"]="id";boundJSON["source_version"]="v"
        let boundHistory = try JSONDecoder().decode(HistoryEntry.self,from:JSONSerialization.data(withJSONObject:boundJSON))
        check(boundHistory.matches(identity:RecordingIdentity(recordingId:"id",sourceVersion:"v")) && !boundHistory.matches(identity:RecordingIdentity(recordingId:"id",sourceVersion:"changed")),"续播绑定来源版本")
        var history = APIClient.SaveHistoryRequest(videoPath:"clip",videoName:"clip",positionSeconds:30,durationSeconds:100)
        history.recordingId = "original-id";history.sourceVersion = "original-version"
        let historyJSON = try JSONSerialization.jsonObject(with:JSONEncoder().encode(history)) as! [String:Any]
        check(historyJSON["recording_id"] as? String == "original-id" && historyJSON["source_version"] as? String == "original-version","历史提交保留预期录播身份")
        failures += try await runSessionLifecycleTests()
        failures += runNativeCapabilitiesTests()
        failures += try await runPlaybackRefreshTests()
        if failures > 0 { exit(1) }
        print("PASS: T7 v2 清单、身份、统计、URL 与鉴权边界")
    }
}
