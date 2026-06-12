import AVFoundation
import Combine
import CoreMedia
import MediaPlayer
import PillarboxPlayer
import SwiftUI

// MARK: - Screen Access
/// iOS 26 起 `UIScreen.main` 已废弃，改用当前前台 window scene 关联的屏幕。
@MainActor
func activeScreen() -> UIScreen? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
}

// MARK: - Volume Manager
final class VolumeManager: ObservableObject {
    static let shared = VolumeManager()
    private var volumeSlider: UISlider?
    
    init() {
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.alpha = 0.0001
        for view in volumeView.subviews {
            if let slider = view as? UISlider {
                self.volumeSlider = slider
                break
            }
        }
    }
    
    func setVolume(_ value: Float) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.volumeSlider?.value = value
        }
    }
    
    func getVolume() -> Float {
        return AVAudioSession.sharedInstance().outputVolume
    }
}

struct SystemVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.alpha = 0.0001
        return volumeView
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - Gesture Handler
enum GestureType {
    case none, seeking, volume, brightness
}

struct PlayerGestureView: UIViewRepresentable {
    var onTap: () -> Void
    var onDoubleTap: () -> Void
    var onLongPressBegan: (CGPoint, CGSize) -> Void
    var onLongPressChanged: (CGPoint, CGSize) -> Void
    var onLongPressEnded: () -> Void
    var onPanBegan: (GestureType) -> Void
    var onPanChanged: (GestureType, CGPoint) -> Void
    var onPanEnded: (GestureType) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(longPress)
        view.addGestureRecognizer(pan)
        
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PlayerGestureView
        var currentPanType: GestureType = .none
        
        init(parent: PlayerGestureView) {
            self.parent = parent
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended { parent.onTap() }
        }
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended { parent.onDoubleTap() }
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            let size = gesture.view?.bounds.size ?? .zero
            switch gesture.state {
            case .began:
                parent.onLongPressBegan(location, size)
            case .changed:
                parent.onLongPressChanged(location, size)
            case .ended, .cancelled, .failed:
                parent.onLongPressEnded()
            default: break
            }
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            let location = gesture.location(in: gesture.view)
            guard let view = gesture.view else { return }
            
            switch gesture.state {
            case .began:
                let isHorizontal = abs(velocity.x) > abs(velocity.y)
                if isHorizontal {
                    currentPanType = .seeking
                } else {
                    currentPanType = location.x < view.bounds.width / 2 ? .brightness : .volume
                }
                parent.onPanBegan(currentPanType)
            case .changed:
                parent.onPanChanged(currentPanType, translation)
            case .ended, .cancelled, .failed:
                parent.onPanEnded(currentPanType)
                currentPanType = .none
            default: break
            }
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return false
        }
    }
}

// MARK: - PlayerView
struct PlayerView: View {
    let file: VideoFileInfo
    let client: APIClient

    @Environment(\.dismiss) private var dismiss

    @StateObject private var player: Player
    @StateObject private var progressTracker = ProgressTracker(
        interval: CMTime(seconds: 0.25, preferredTimescale: 600)
    )

    @State private var playbackState: PlaybackState = .idle
    @State private var isBusy = false
    @State private var buffer: Float = 0
    @State private var currentSpeed: Float = 1
    @State private var baseSpeed: Float = 1
    @State private var isCommandDeckVisible = true
    @State private var errorMessage: String?
    @State private var resumeMessage: String?
    @State private var syncMessage: String?
    
    // Gestures States
    @State private var showSeekHUD = false
    @State private var seekTargetTime: CMTime = .zero
    @State private var seekDeltaSeconds: Double = 0
    @State private var panSeekStartTime: CMTime = .zero
    
    @State private var showVolumeHUD = false
    @State private var initialVolume: Float = 0
    @State private var currentVolume: Float = VolumeManager.shared.getVolume()
    
    @State private var showBrightnessHUD = false
    @State private var initialBrightness: CGFloat = 0
    @State private var currentBrightness: CGFloat = 0.5
    @State private var viewWidth: CGFloat = 0
    
    @State private var isSpeedingUp = false
    @State private var isSpeedLocked = false
    @State private var speedPressStartY: CGFloat = 0
    @State private var showSpeedHUD = false
    @State private var speedGestureMode: SpeedGestureMode = .none
    @State private var resumeEntry: HistoryEntry?
    @State private var didApplyResume = false
    /// 续播决议（应用成功 / 确认无需续播）前禁止上报历史，避免把服务端旧进度覆盖成片头位置
    @State private var isResumeSettled = false
    @State private var didStartPlayback = false
    
    let saveHistoryTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var thumbnailURL: URL? {
        client.thumbnailURL(for: file)
    }

    private var isPlaying: Bool {
        playbackState == .playing
    }

    init(file: VideoFileInfo, client: APIClient) {
        self.file = file
        self.client = client

        let configuration = PlayerConfiguration(
            backwardSkipInterval: 15,
            forwardSkipInterval: 15
        )

        if let url = client.playbackURL(for: file) {
            let p = Player(item: .simple(url: url), configuration: configuration)
            p.actionAtItemEnd = .pause
            _player = StateObject(wrappedValue: p)
            _errorMessage = State(initialValue: nil)
        } else {
            _player = StateObject(wrappedValue: Player())
            _errorMessage = State(initialValue: Self.failureMessage(for: file))
        }
    }

    /// 播放失败提示按文件状态区分：录制中 / 处理中 / 其他
    static func failureMessage(for file: VideoFileInfo) -> String {
        if file.recording == true || file.playbackStatus == "recording" {
            return "正在录制，请稍后"
        }
        if file.playbackStatus == "processing" {
            return "正在处理，请稍后"
        }
        return "视频暂时无法播放"
    }

    var body: some View {
        ZStack {
            PlayerBackdrop(thumbnailURL: thumbnailURL, isPlaying: isPlaying)
            
            SystemVolumeView()
                .frame(width: 0, height: 0)

            if errorMessage == nil {
                VideoView(player: player)
                    .gravity(.resizeAspect)
                    .supportsPictureInPicture()
                    .ignoresSafeArea()

                PlayerVignette()
                
                PlayerGestureView(
                    onTap: toggleCommandDeck,
                    onDoubleTap: togglePlay,
                    onLongPressBegan: handleLongPressBegan,
                    onLongPressChanged: handleLongPressChanged,
                    onLongPressEnded: handleLongPressEnded,
                    onPanBegan: handlePanBegan,
                    onPanChanged: handlePanChanged,
                    onPanEnded: handlePanEnded
                )

                PlayerHUDLayer()

                VStack {
                    Spacer()
                    if let resumeMessage {
                        PlayerStatusToast(text: resumeMessage, systemImage: "clock.arrow.circlepath")
                            .padding(.bottom, 132)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if let syncMessage {
                        PlayerStatusToast(text: syncMessage, systemImage: "checkmark.icloud.fill")
                            .padding(.bottom, 132)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 24)
                .allowsHitTesting(false)

                // Replay overlay when video ends
                if playbackState == .ended {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    
                    Button(action: { player.replay() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 80, height: 80)
                            .floatingGlass(in: Circle(), interactive: true)
                            .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                VStack(spacing: 0) {
                    PlayerTopChrome(
                        title: file.name,
                        subtitle: file.sizeFormatted,
                        dismiss: closePlayer,
                        togglePiP: startPictureInPicture
                    )
                    .opacity(isCommandDeckVisible ? 1 : 0)

                    Spacer(minLength: 0)

                    PlayerBottomControls(
                        player: player,
                        progressTracker: progressTracker,
                        playbackState: playbackState,
                        isBusy: isBusy,
                        buffer: buffer,
                        currentSpeed: currentSpeed,
                        formatTime: formatTime,
                        togglePlay: togglePlay,
                        seekToFraction: seekToFraction,
                        setSpeed: setSpeed
                    )
                    .opacity(isCommandDeckVisible ? 1 : 0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 0)
                .padding(.bottom, 8)
                // opacity(0) 的视图仍会参与命中测试，隐藏时必须显式关掉，否则吞掉手势层的点击
                .allowsHitTesting(isCommandDeckVisible)
            } else if let errorMessage {
                PlayerErrorState(message: errorMessage, dismiss: closePlayer)
                    .padding(24)
            }
        }
        .bind(progressTracker, to: player)
        .onReceive(player: player, assign: \.playbackState, to: $playbackState)
        .onReceive(player: player, assign: \.isBusy, to: $isBusy)
        .onReceive(player: player, assign: \.buffer, to: $buffer)
        .onReceive(player.$error.compactMap { $0?.localizedDescription }) { _ in
            errorMessage = Self.failureMessage(for: file)
        }
        .onReceive(saveHistoryTimer) { _ in
            if isPlaying { saveHistory() }
        }
        .onChange(of: progressTracker.timeRange.duration.seconds) { _, _ in
            Task { await applyResumeWhenReady() }
        }
        .onChange(of: resumeEntry?.positionSeconds) { _, _ in
            Task { await applyResumeWhenReady() }
        }
        .onChange(of: resumeEntry?.durationSeconds) { _, _ in
            Task { await applyResumeWhenReady() }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newWidth in viewWidth = newWidth }
            }
        }
        .onAppear {
            currentBrightness = activeScreen()?.brightness ?? currentBrightness
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .task(preparePlayer)
        .onDisappear {
            saveHistory()
            stopPlayer()
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isCommandDeckVisible)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: playbackState)
        .sensoryFeedback(.impact(weight: .light), trigger: playbackState)
    }
    
    // MARK: - Gesture Methods
    private func handlePanBegan(_ type: GestureType) {
        if showSpeedHUD { return }
        switch type {
        case .seeking:
            showSeekHUD = true
            panSeekStartTime = progressTracker.time  // lock start; progressTracker.time freezes once isInteracting=true
            seekTargetTime = progressTracker.time
            seekDeltaSeconds = 0
            progressTracker.isInteracting = true
        case .volume:
            showVolumeHUD = true
            initialVolume = VolumeManager.shared.getVolume()
            currentVolume = initialVolume
        case .brightness:
            showBrightnessHUD = true
            initialBrightness = activeScreen()?.brightness ?? currentBrightness
            currentBrightness = initialBrightness
        case .none: break
        }
    }
    
    private func handlePanChanged(_ type: GestureType, translation: CGPoint) {
        if showSpeedHUD { return }
        switch type {
        case .seeking:
            let width = viewWidth > 0 ? viewWidth : 1
            let duration = progressTracker.timeRange.duration.seconds
            // Scale with video duration: 15% of total per full-screen swipe, clamped 30–300 s
            let seekRange = (duration.isFinite && duration > 0)
                ? min(max(duration * 0.15, 30), 300)
                : 90.0
            seekDeltaSeconds = Double(translation.x / width) * seekRange
            // Always compute from locked start time so translation.x deltas don't accumulate
            var target = CMTimeAdd(panSeekStartTime, CMTime(seconds: seekDeltaSeconds, preferredTimescale: 600))
            if target < .zero { target = .zero }
            if target > progressTracker.timeRange.duration { target = progressTracker.timeRange.duration }
            seekTargetTime = target
            // Sync progress bar so it moves in real time
            if duration.isFinite && duration > 0 {
                progressTracker.progress = Float(target.seconds / duration)
            }
        case .volume:
            let delta = Float(-translation.y / 200.0)
            var newVol = initialVolume + delta
            newVol = max(0, min(1, newVol))
            currentVolume = newVol
            VolumeManager.shared.setVolume(newVol)
        case .brightness:
            let delta = CGFloat(-translation.y / 200.0)
            var newBright = initialBrightness + delta
            newBright = max(0, min(1, newBright))
            currentBrightness = newBright
            activeScreen()?.brightness = newBright
        case .none: break
        }
    }
    
    private func handlePanEnded(_ type: GestureType) {
        if showSpeedHUD { return }
        switch type {
        case .seeking:
            showSeekHUD = false
            progressTracker.isInteracting = false  // ProgressTracker seeks to the progress we set during pan
        case .volume:
            showVolumeHUD = false
        case .brightness:
            showBrightnessHUD = false
        case .none: break
        }
    }

    private func setTemporarySpeed(_ speed: Float) {
        currentSpeed = speed
        player.playbackSpeed = speed
    }

    private func handleLongPressBegan(location: CGPoint, size: CGSize) {
        guard size.width > 0 else { return }
        let sideZone = size.width * 0.28
        guard location.x <= sideZone || location.x >= size.width - sideZone else {
            speedGestureMode = .none
            return
        }
        speedPressStartY = location.y
        speedGestureMode = isSpeedLocked ? .unlocking : .locking
        isSpeedingUp = true
        showSpeedHUD = true
        isCommandDeckVisible = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        setTemporarySpeed(2.0)
    }

    private func handleLongPressChanged(location: CGPoint, size: CGSize) {
        guard speedGestureMode == .locking || speedGestureMode == .unlocking, size.height > 0 else { return }
        // 必须有真实下拉动作（≥30pt）才允许触发，防止起手就在下 1/3 区域时瞬间锁定
        guard location.y - speedPressStartY >= 30, location.y >= size.height * 2 / 3 else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch speedGestureMode {
        case .locking:
            isSpeedLocked = true
            setTemporarySpeed(2.0)
            speedGestureMode = .locked
        case .unlocking:
            isSpeedingUp = false
            setSpeed(baseSpeed)
            speedGestureMode = .none
            showSpeedHUD = false
        case .none, .locked:
            break
        }
    }

    private func handleLongPressEnded() {
        switch speedGestureMode {
        case .locking:
            if !isSpeedLocked {
                isSpeedingUp = false
                setSpeed(baseSpeed)
            }
            showSpeedHUD = false
        case .unlocking:
            if isSpeedLocked {
                setTemporarySpeed(2.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation { showSpeedHUD = false }
                }
            }
        case .locked:
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation { showSpeedHUD = false }
            }
        case .none:
            break
        }
        speedGestureMode = .none
    }

    // MARK: - HUD Layer
    @ViewBuilder
    private func PlayerHUDLayer() -> some View {
        ZStack {
            // Top HUDs (Volume, Brightness, Seek)
            VStack {
                if showSeekHUD {
                    SeekHUD(time: seekTargetTime, delta: seekDeltaSeconds, totalTime: progressTracker.timeRange.duration)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if showVolumeHUD {
                    ValueHUD(icon: "speaker.wave.3.fill", value: CGFloat(currentVolume))
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if showBrightnessHUD {
                    ValueHUD(icon: "sun.max.fill", value: currentBrightness)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(.top, 48)
            
            // Bottom HUDs (Speed)
            VStack {
                Spacer()
                if showSpeedHUD {
                    SpeedHUDView(mode: speedGestureMode, isSpeedLocked: isSpeedLocked)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 60)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showSeekHUD)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showVolumeHUD)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showBrightnessHUD)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showSpeedHUD)
        .allowsHitTesting(false)
    }

    // MARK: - Actions
    func preparePlayer() async {
        guard errorMessage == nil else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            errorMessage = "音频会话启动失败"
            return
        }
        player.becomeActive()
        if !didStartPlayback {
            didStartPlayback = true
            player.play()
        }
        resumeEntry = await loadResumeHistory()
        if resumeEntry == nil {
            isResumeSettled = true
        }
        await applyResumeWhenReady()
    }

    func stopPlayer() {
        player.pause()
        player.resignActive()
    }

    func closePlayer() {
        saveHistory()
        PictureInPicture.shared.close()
        stopPlayer()
        dismiss()
    }
    
    func saveHistory() {
        guard isResumeSettled else { return }
        guard !client.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            syncMessage = "未绑定 API Key，无法同步历史"
            return
        }
        let position = progressTracker.time.seconds
        let duration = progressTracker.timeRange.duration.seconds
        guard position.isFinite, duration.isFinite, duration > 0 else { return }
        Task {
            do {
                try await client.saveWatchHistory(
                    videoPath: file.relPath,
                    videoName: file.name,
                    positionSeconds: position,
                    durationSeconds: duration
                )
                await MainActor.run {
                    syncMessage = "已同步到服务端"
                }
                try? await Task.sleep(for: .seconds(1.4))
                await MainActor.run {
                    if syncMessage == "已同步到服务端" { syncMessage = nil }
                }
            } catch {
                await MainActor.run {
                    syncMessage = "同步失败"
                }
            }
        }
    }

    @MainActor
    func applyResumeWhenReady() async {
        guard !didApplyResume, let entry = resumeEntry, entry.durationSeconds > 0 else { return }
        let playerDuration = progressTracker.timeRange.duration.seconds
        guard playerDuration.isFinite, playerDuration > 0 else { return }
        let position = min(max(entry.positionSeconds, 0), max(entry.durationSeconds - 1, 0))
        guard position > 5, position < entry.durationSeconds - 5 else {
            didApplyResume = true
            isResumeSettled = true
            return
        }
        didApplyResume = true
        let target = CMTime(seconds: position, preferredTimescale: 600)
        // item 未完全就绪时 seek 可能被播放器丢弃，发出后校验实际位置，必要时重试
        var applied = false
        for _ in 0..<3 {
            player.seek(to: target)
            try? await Task.sleep(for: .milliseconds(500))
            if abs(progressTracker.time.seconds - position) < 3 {
                applied = true
                break
            }
        }
        isResumeSettled = true
        guard applied else { return }
        resumeMessage = "已从 \(formatTime(position)) 继续播放"
        try? await Task.sleep(for: .seconds(2.2))
        if resumeMessage != nil {
            resumeMessage = nil
        }
    }

    func loadResumeHistory() async -> HistoryEntry? {
        do {
            return try await client.getWatchHistoryEntry(videoPath: file.relPath)
        } catch {
            if let entries = try? await client.getWatchHistory() {
                return entries.first { $0.videoPath == file.relPath }
            }
            return nil
        }
    }


    func togglePlay() {
        if playbackState == .ended || player.canReplay() {
            player.replay()
        } else {
            if playbackState == .playing { saveHistory() }
            player.togglePlayPause()
        }
    }

    func toggleCommandDeck() {
        guard !showSpeedHUD else { return }
        isCommandDeckVisible.toggle()
    }

    func startPictureInPicture() {
        PictureInPicture.shared.startIfPossible()
    }

    func setSpeed(_ speed: Float) {
        currentSpeed = speed
        baseSpeed = speed
        // 显式选择速度即解除手势锁定，避免菜单调速后下次长按进入"解锁"分支
        isSpeedLocked = false
        isSpeedingUp = false
        player.playbackSpeed = speed
    }

    func seekToFraction(_ fraction: CGFloat) {
        let duration = progressTracker.timeRange.duration.seconds
        guard duration.isFinite, duration > 0 else { return }
        let clamped = min(max(Double(fraction), 0), 1)
        let target = CMTime(seconds: duration * clamped, preferredTimescale: 600)
        progressTracker.isInteracting = false
        progressTracker.progress = Float(clamped)
        player.seek(to: target)
        saveHistory()
    }

    func formatTime(_ time: CMTime) -> String {
        formatTime(time.seconds)
    }

    func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - HUD Views
private struct SeekHUD: View {
    let time: CMTime
    let delta: Double
    let totalTime: CMTime
    
    var body: some View {
        HStack(spacing: 8) {
            Text(delta >= 0 ? ">>" : "<<")
                .font(.subheadline.weight(.bold))
            HStack(spacing: 4) {
                Text(formatTime(time))
                    .foregroundStyle(Color(red: 0.12, green: 0.86, blue: 0.78))
                Text("/")
                    .foregroundStyle(.white.opacity(0.6))
                Text(formatTime(totalTime))
            }
            .font(.subheadline.monospacedDigit().weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .floatingGlass(in: Capsule())
    }

    func formatTime(_ time: CMTime) -> String {
        guard time.seconds.isFinite && time.seconds >= 0 else { return "00:00" }
        let total = Int(time.seconds.rounded())
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

private struct ValueHUD: View {
    let icon: String
    let value: CGFloat
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
            
            GeometryReader { proxy in
                Capsule()
                    .fill(.white.opacity(0.2))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.white)
                            .frame(width: proxy.size.width * value)
                    }
            }
            .frame(width: 80, height: 4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .floatingGlass(in: Capsule())
    }
}

private enum SpeedGestureMode {
    case none
    case locking
    case unlocking
    case locked
}

private struct SpeedHUDView: View {
    let mode: SpeedGestureMode
    let isSpeedLocked: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 14))
            
            Text(text)
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6), in: Capsule())
    }

    private var iconName: String {
        if mode == .unlocking { return "lock.open.fill" }
        return isSpeedLocked ? "lock.fill" : "chevron.down"
    }

    private var text: String {
        switch mode {
        case .unlocking:
            return "下拉解锁 2 倍速"
        case .locked:
            return "已锁定 2 倍速"
        case .locking, .none:
            return "下拉锁定 2 倍速"
        }
    }
}

private struct PlayerStatusToast: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.68), in: Capsule())
    }
}

// MARK: - UI Components
private struct PlayerBottomControls: View {
    @ObservedObject var player: Player
    @ObservedObject var progressTracker: ProgressTracker

    let playbackState: PlaybackState
    let isBusy: Bool
    let buffer: Float
    let currentSpeed: Float
    let formatTime: (CMTime) -> String
    let togglePlay: () -> Void
    let seekToFraction: (CGFloat) -> Void
    let setSpeed: (Float) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            PlayerTimeline(
                progressTracker: progressTracker,
                buffer: buffer,
                formatTime: formatTime,
                seekToFraction: seekToFraction
            )
            
            HStack {
                Button(action: togglePlay) {
                    Image(systemName: playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                
                Spacer()
                
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0], id: \.self) { speed in
                        Button {
                            setSpeed(Float(speed))
                        } label: {
                            if abs(Double(currentSpeed) - speed) < 0.01 {
                                Label(String(format: "%.2gx", speed), systemImage: "checkmark")
                            } else {
                                Text(String(format: "%.2gx", speed))
                            }
                        }
                    }
                } label: {
                    Text(String(format: "%.2gx", currentSpeed))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minWidth: 44, minHeight: 36)
                        .floatingGlass(in: Capsule())
                        .contentShape(Capsule())
                }
            }
        }
    }
}

private struct PlayerTimeline: View {
    @ObservedObject var progressTracker: ProgressTracker
    let buffer: Float
    let formatTime: (CMTime) -> String
    let seekToFraction: (CGFloat) -> Void
    @State private var dragFraction: CGFloat?

    var body: some View {
        HStack(spacing: 12) {
            Text(formatTime(displayTime))
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
            
            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                let available = progressTracker.isProgressAvailable
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(height: 4)
                    Capsule()
                        .fill(.white.opacity(0.4))
                        .frame(width: width * CGFloat(buffer), height: 4)
                    Capsule()
                        .fill(Color(red: 0.12, green: 0.86, blue: 0.78))
                        .frame(width: width * currentFraction, height: 4)
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .offset(x: max(0, min(width - 14, width * currentFraction - 7)))
                }
                .frame(maxHeight: .infinity)
                // 命中区垂直外扩到 44pt 标准触控尺寸，视觉高度保持不变；点击（零位移拖动）即跳转
                .contentShape(Rectangle().inset(by: -10))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard available else { return }
                            progressTracker.isInteracting = true
                            dragFraction = fraction(for: value.location.x, width: width)
                        }
                        .onEnded { value in
                            guard available else { return }
                            let target = fraction(for: value.location.x, width: width)
                            dragFraction = nil
                            progressTracker.isInteracting = false
                            seekToFraction(target)
                        }
                )
            }
            .frame(height: 24)
            
            Text(formatTime(progressTracker.timeRange.duration))
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var displayTime: CMTime {
        guard let dragFraction else { return progressTracker.time }
        let duration = progressTracker.timeRange.duration.seconds
        guard duration.isFinite, duration > 0 else { return progressTracker.time }
        return CMTime(seconds: duration * Double(dragFraction), preferredTimescale: 600)
    }

    private var currentFraction: CGFloat {
        if let dragFraction { return dragFraction }
        let duration = progressTracker.timeRange.duration.seconds
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(max(CGFloat(progressTracker.time.seconds / duration), 0), 1)
    }

    private func fraction(for x: CGFloat, width: CGFloat) -> CGFloat {
        min(max(x / max(width, 1), 0), 1)
    }
}

private struct PlayerTopChrome: View {
    let title: String
    let subtitle: String
    let dismiss: () -> Void
    let togglePiP: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            IconButton(systemName: "chevron.left", action: dismiss)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            IconButton(systemName: "pip.enter", action: togglePiP)
        }
        .padding(.top, 8)
    }
}

private struct IconButton: View {
    let systemName: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Backdrops & Extras
private struct PlayerBackdrop: View {
    let thumbnailURL: URL?
    let isPlaying: Bool
    var body: some View {
        Color.black
            .ignoresSafeArea()
            .overlay {
                AsyncImage(url: thumbnailURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill().blur(radius: 40).opacity(0.4)
                    }
                }
            }
            .clipped()
            .ignoresSafeArea()
    }
}

private struct PlayerVignette: View {
    var body: some View {
        VStack {
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
            Spacer()
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .frame(height: 160)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct PlayerErrorState: View {
    let message: String
    let dismiss: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.orange)
            Text("无法播放").font(.title3.weight(.bold)).foregroundStyle(.white)
            Text(message).font(.subheadline).foregroundStyle(.white.opacity(0.68))
            Button("退出", action: dismiss)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(.white, in: Capsule())
        }
        .padding(24)
        .floatingGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
