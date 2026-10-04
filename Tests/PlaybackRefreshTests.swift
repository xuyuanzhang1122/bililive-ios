import Foundation

@MainActor final class TestPlaybackController: SessionPlaybackController {
    var positionSeconds: Double = 90
    var intendedPlaying = false
    var speed: Float = 1.5
    var events: [String] = []
    var pending: CheckedContinuation<Void, Error>?
    var delay = false
    func prepare(url:URL) async throws { events.append("prepare"); if delay { try await withCheckedThrowingContinuation { pending = $0 } } }
    func restorePosition(_ seconds:Double) async throws { events.append("seek:\(seconds)") }
    func updateSpeed(_ value:Float) { events.append("rate:\(value)") }
    func play() { events.append("play") }
    func pause() { events.append("pause") }
    func stop() { events.append("stop") }
}
@MainActor func runPlaybackRefreshTests() async throws -> Int {
    var failures = 0
    let controller = TestPlaybackController()
    let bridge = PlaybackRefreshCoordinator(controller:controller)
    let url = URL(string:"https://server/media?play_token=short")!
    try await bridge.apply(url: url)
    controller.events.removeAll()
    try await bridge.apply(url: url)
    if controller.events != ["pause","prepare","seek:90.0","rate:1.5"] { failures += 1;print("FAIL: 暂停刷新必须先准备与seek且不播放") }
    controller.intendedPlaying = true;controller.events.removeAll()
    try await bridge.apply(url: url)
    if controller.events != ["pause","prepare","seek:90.0","rate:1.5","play"] { failures += 1;print("FAIL: 运行中刷新恢复位置倍速后再播放") }
    controller.delay = true;controller.events.removeAll()
    let pending = Task { try await bridge.apply(url:url) }
    for _ in 0..<80 { await Task.yield() }
    bridge.close();controller.pending?.resume()
    do { try await pending.value } catch is CancellationError {} catch { failures += 1 }
    if controller.events.contains("play") { failures += 1;print("FAIL: 关闭后旧准备回调不得恢复播放") }
    return failures
}
