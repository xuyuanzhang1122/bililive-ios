import Foundation

@MainActor final class TestSessionClock {
    var delays: [Double] = []
    private var pending: [UUID: CheckedContinuation<Void, Error>] = [:]
    func sleep(_ seconds: Double) async throws {
        delays.append(seconds)
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending[id] = $0 }
        } onCancel: { Task { @MainActor in self.pending.removeValue(forKey: id)?.resume(throwing: CancellationError()) } }
    }
    func tick() { let waits = pending; pending.removeAll(); waits.values.forEach { $0.resume() } }
}
@MainActor final class TestSessionTransport: PlaybackSessionTransport {
    var created: [CreatePlaybackSession] = []
    var cancelled: [String] = []
    var make: () async throws -> PlaybackSession
    var get: () async throws -> PlaybackSession
    init(_ ready: PlaybackSession) { make = { ready }; get = { ready } }
    func createPlaybackSession(_ body: CreatePlaybackSession) async throws -> PlaybackSession { created.append(body); return try await make() }
    func getPlaybackSession(_ id: String) async throws -> PlaybackSession { try await get() }
    func cancelPlaybackSession(_ id: String) async throws { cancelled.append(id) }
}

@MainActor func runSessionLifecycleTests() async throws -> Int {
    var failures = 0
    func check(_ condition: Bool, _ name: String) { if !condition { failures += 1; print("FAIL: \(name)") } }
    func settle() async { for _ in 0..<80 { await Task.yield() } }
    let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath:"Tests/contracts/v2/v2-session-ready.json"))) as! [String:Any]
    let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
    let ready = try decoder.decode(V2Envelope<PlaybackSession>.self,from:JSONSerialization.data(withJSONObject:raw["value"]!)).data!
    let identity = RecordingIdentity(recordingId:ready.recordingId,sourceVersion:ready.sourceVersion)
    let caps = PlaybackCapabilities(containers:["mp4"],protocols:["file"],video:[],audio:[])
    let clock = TestSessionClock(), transport = TestSessionTransport(ready)
    let model = PlaybackSessionModel(client:transport,sleep:clock.sleep)
    var applied: [PlaybackSession] = [], errors: [Error] = []
    model.onReady = { applied.append($0) }; model.onError = { errors.append($0) }
    await model.open(identity:identity,capabilities:caps);await settle()
    check(applied.count == 1 && clock.delays == [240],"ready 按服务端时间刷新")
    clock.tick();await settle();check(applied.count == 2,"刷新应用新授权")
    transport.get = { throw V2RequestError(status:410,failure:V2Failure(code:"session_expired",message:"expired",retryable:false),requestId:"r") }
    clock.tick();await settle();check(transport.created.count == 2 && applied.count == 3,"410 按同一身份重建")
    check(transport.created.allSatisfy { $0.recordingId == identity.recordingId && $0.sourceVersion == identity.sourceVersion },"重建保留来源身份")
    await model.close();await settle();check(transport.cancelled.count == 1,"退出取消活动会话一次")
    clock.tick();await settle();check(applied.count == 3,"退出后不再应用授权")

    let late = TestSessionTransport(ready), lateClock = TestSessionClock()
    var complete: CheckedContinuation<PlaybackSession, Error>?
    late.make = { try await withCheckedThrowingContinuation { complete = $0 } }
    let closingModel = PlaybackSessionModel(client:late,sleep:lateClock.sleep)
    var lateReady = 0; closingModel.onReady = { _ in lateReady += 1 }
    let task = Task { await closingModel.open(identity:identity,capabilities:caps) };await settle()
    await closingModel.close();complete?.resume(returning:ready);await task.value
    check(lateReady == 0 && late.cancelled == [ready.id],"退出后晚到创建被取消且不播放")

    let changed = TestSessionTransport(ready), changedClock = TestSessionClock()
    changed.get = { throw V2RequestError(status:409,failure:V2Failure(code:"source_changed",message:"来源变化",retryable:false),requestId:"r") }
    let changedModel = PlaybackSessionModel(client:changed,sleep:changedClock.sleep)
    var changedErrors = 0; changedModel.onError = { _ in changedErrors += 1 }
    await changedModel.open(identity:identity,capabilities:caps);await settle();changedClock.tick();await settle()
    check(changedErrors == 1 && changed.created.count == 1,"来源变化可见且不回退重建")
    await changedModel.close();await settle()
    check(errors.isEmpty,"合法刷新没有隐藏失败")
    let processingRaw = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath:"Tests/contracts/v2/v2-session-processing.json"))) as! [String:Any]
    let processing = try decoder.decode(V2Envelope<PlaybackSession>.self,from:JSONSerialization.data(withJSONObject:processingRaw["value"]!)).data!
    var wrongRaw = (raw["value"] as! [String:Any])["data"] as! [String:Any]
    wrongRaw["id"] = "00000000-0000-4000-8000-000000000099"
    let wrong = try decoder.decode(PlaybackSession.self,from:JSONSerialization.data(withJSONObject:wrongRaw))
    let polling = TestSessionTransport(processing), pollingClock = TestSessionClock()
    polling.get = { wrong }
    let pollingModel = PlaybackSessionModel(client:polling,sleep:pollingClock.sleep)
    var pollingReady = 0, pollingErrors = 0
    pollingModel.onReady = { _ in pollingReady += 1 }; pollingModel.onError = { _ in pollingErrors += 1 }
    let pollingTask = Task { await pollingModel.open(identity:identity,capabilities:caps) };await settle()
    pollingClock.tick();await settle();await pollingTask.value
    check(pollingReady == 0 && pollingErrors == 1,"处理轮询不接受其他会话 ID")
    await pollingModel.close()
    for transition in ["ready", "processing"] {
        var alteredRaw = (raw["value"] as! [String:Any])["data"] as! [String:Any]
        alteredRaw["id"] = "new-session"; alteredRaw["asset_version"] = "changed-asset"
        let altered = try decoder.decode(PlaybackSession.self,from:JSONSerialization.data(withJSONObject:alteredRaw))
        let bound = TestSessionTransport(ready), boundClock = TestSessionClock()
        var creations = 0
        bound.make = { creations += 1; return creations == 1 ? ready : transition == "ready" ? altered : processing }
        bound.get = { if creations < 2 { throw V2RequestError(status:410,failure:V2Failure(code:"session_expired",message:"expired",retryable:false),requestId:"r") }; var nextRaw = alteredRaw; nextRaw["id"] = processing.id; return try decoder.decode(PlaybackSession.self,from:JSONSerialization.data(withJSONObject:nextRaw)) }
        let assetModel = PlaybackSessionModel(client:bound,sleep:boundClock.sleep)
        var callbacks = 0, failuresSeen = 0
        assetModel.onReady = { _ in callbacks += 1 }; assetModel.onError = { _ in failuresSeen += 1 }
        await assetModel.open(identity:identity,capabilities:caps);await settle();boundClock.tick();await settle()
        if transition == "processing" {boundClock.tick();await settle()}
        check(callbacks == 1 && failuresSeen == 1,"资产绑定跨410/\(transition)保持")
        check(bound.cancelled.contains(transition == "ready" ? altered.id : processing.id),"资产变化取消新会话")
        await assetModel.close();await settle()
    }
    return failures
}
