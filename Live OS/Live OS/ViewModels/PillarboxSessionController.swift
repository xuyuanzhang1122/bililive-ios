import AVFoundation
import PillarboxPlayer

@MainActor final class PillarboxSessionController: SessionPlaybackController {
    private let player: Player
    private var generation = 0
    private var seekFinished: Bool?
    init(player:Player) { self.player = player }
    var positionSeconds: Double { player.systemPlayer.currentTime().seconds }
    var intendedPlaying: Bool { player.shouldPlay }
    var speed: Float { player.systemPlayer.defaultRate }
    func prepare(url:URL) async throws {
        generation += 1
        let token = generation
        player.pause()
        player.items = [.simple(url:url)]
        player.actionAtItemEnd = .pause
        player.becomeActive()
        for _ in 0..<100 {
            try Task.checkCancellation()
            guard token == generation else { throw CancellationError() }
            if let item = player.systemPlayer.currentItem, (item.asset as? AVURLAsset)?.url == url {
                if item.status == .readyToPlay { return }
                if item.status == .failed { throw item.error ?? APIError.serverError(-1,"播放器准备失败") }
            }
            try await Task.sleep(for:.milliseconds(100))
        }
        throw APIError.serverError(-1,"播放器准备超时")
    }
    func restorePosition(_ seconds:Double) async throws {
        let token = generation
        seekFinished = nil
        player.seek(to:CMTime(seconds:seconds,preferredTimescale:600)) { [weak self] succeeded in
            Task { @MainActor in if self?.generation == token { self?.seekFinished = succeeded } }
        }
        for _ in 0..<50 {
            try Task.checkCancellation()
            guard token == generation else { throw CancellationError() }
            if let finished = seekFinished {
                guard finished, abs(player.systemPlayer.currentTime().seconds - seconds) < 3 else {
                    throw APIError.serverError(-1,"刷新播放位置恢复失败")
                }
                return
            }
            try await Task.sleep(for:.milliseconds(100))
        }
        throw APIError.serverError(-1,"刷新播放位置恢复超时")
    }
    func updateSpeed(_ value:Float) { player.playbackSpeed = value }
    func play() { player.play() }
    func pause() { player.pause() }
    func stop() { generation += 1; player.pause(); player.items = []; player.resignActive() }
}
