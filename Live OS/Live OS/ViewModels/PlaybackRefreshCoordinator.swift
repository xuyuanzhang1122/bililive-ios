import Foundation

@MainActor protocol SessionPlaybackController: AnyObject {
    var positionSeconds: Double { get }
    var intendedPlaying: Bool { get }
    var speed: Float { get }
    func prepare(url:URL) async throws
    func restorePosition(_ seconds:Double) async throws
    func updateSpeed(_ value:Float)
    func play()
    func pause()
    func stop()
}
@MainActor final class PlaybackRefreshCoordinator {
    private let controller: any SessionPlaybackController
    init(controller: any SessionPlaybackController) { self.controller = controller }
    private var generation = 0
    private var started = false
    private var closed = false
    func apply(url:URL) async throws {
        guard !closed else { throw CancellationError() }
        generation += 1
        let token = generation
        let position = started && controller.positionSeconds.isFinite ? max(0,controller.positionSeconds) : 0
        let playing = started ? controller.intendedPlaying : true
        let speed = controller.speed
        controller.pause()
        try await controller.prepare(url:url)
        try check(token)
        if position > 0 { try await controller.restorePosition(position); try check(token) }
        controller.updateSpeed(speed)
        if playing { controller.play() }
        started = true
    }
    private func check(_ token:Int) throws {
        guard token == generation && !closed && !Task.isCancelled else { throw CancellationError() }
    }
    func close() { generation += 1; closed = true; controller.stop() }
}
