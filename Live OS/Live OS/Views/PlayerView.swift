import AVFoundation
import Combine
import CoreMedia
import MediaPlayer
import PillarboxPlayer
import SwiftUI

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
    var onLongPressBegan: () -> Void
    var onLongPressEnded: () -> Void
    var onLongPressSwipeDown: () -> Void
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
        var initialLongPressY: CGFloat = 0
        
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
            switch gesture.state {
            case .began:
                initialLongPressY = location.y
                parent.onLongPressBegan()
            case .changed:
                if location.y - initialLongPressY > 60 { // Swipe down to lock
                    parent.onLongPressSwipeDown()
                }
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
    @State private var isCommandDeckVisible = true
    @State private var errorMessage: String?
    @State private var resumeMessage: String?
    @State private var syncMessage: String?
    
    // Gestures States
    @State private var showSeekHUD = false
    @State private var seekTargetTime: CMTime = .zero
    @State private var seekDeltaSeconds: Double = 0
    
    @State private var showVolumeHUD = false
    @State private var initialVolume: Float = 0
    @State private var currentVolume: Float = VolumeManager.shared.getVolume()
    
    @State private var showBrightnessHUD = false
    @State private var initialBrightness: CGFloat = 0
    @State private var currentBrightness: CGFloat = UIScreen.main.brightness
    
    @State private var isSpeedingUp = false
    @State private var isSpeedLocked = false
    @State private var showSpeedHUD = false
    
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
            _errorMessage = State(initialValue: "无法获取播放地址")
        }
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
                    onLongPressBegan: {
                        isSpeedingUp = true
                        showSpeedHUD = true
                        setSpeed(2.0)
                    },
                    onLongPressEnded: {
                        if !isSpeedLocked {
                            isSpeedingUp = false
                            showSpeedHUD = false
                            setSpeed(currentSpeed) // Revert to set speed
                        } else {
                            // If locked, hide the hint after a short delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { showSpeedHUD = false }
                            }
                        }
                    },
                    onLongPressSwipeDown: {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        if isSpeedLocked {
                            // Unlock: revert speed and dismiss
                            isSpeedLocked = false
                            isSpeedingUp = false
                            showSpeedHUD = false
                            setSpeed(1.0)
                        } else {
                            isSpeedLocked = true
                        }
                    },
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
                            .background(.ultraThinMaterial, in: Circle())
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
                        setSpeed: {
                            if showSpeedHUD {
                                isSpeedLocked = false
                            }
                            self.setSpeed($0)
                        }
                    )
                    .opacity(isCommandDeckVisible ? 1 : 0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 0)
                .padding(.bottom, 8)
            } else if let errorMessage {
                PlayerErrorState(message: errorMessage, dismiss: closePlayer)
                    .padding(24)
            }
        }
        .bind(progressTracker, to: player)
        .onReceive(player: player, assign: \.playbackState, to: $playbackState)
        .onReceive(player: player, assign: \.isBusy, to: $isBusy)
        .onReceive(player: player, assign: \.buffer, to: $buffer)
        .onReceive(player.$error.compactMap { $0?.localizedDescription }) { errorMessage = $0 }
        .onReceive(saveHistoryTimer) { _ in
            if isPlaying { saveHistory() }
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
        switch type {
        case .seeking:
            showSeekHUD = true
            seekTargetTime = progressTracker.time
            seekDeltaSeconds = 0
            progressTracker.isInteracting = true
        case .volume:
            showVolumeHUD = true
            initialVolume = VolumeManager.shared.getVolume()
            currentVolume = initialVolume
        case .brightness:
            showBrightnessHUD = true
            initialBrightness = UIScreen.main.brightness
            currentBrightness = initialBrightness
        case .none: break
        }
    }
    
    private func handlePanChanged(_ type: GestureType, translation: CGPoint) {
        switch type {
        case .seeking:
            let width = UIScreen.main.bounds.width
            seekDeltaSeconds = Double(translation.x / width) * 90.0
            seekTargetTime = CMTimeAdd(progressTracker.time, CMTime(seconds: seekDeltaSeconds, preferredTimescale: 600))
            if seekTargetTime < .zero { seekTargetTime = .zero }
            if seekTargetTime > progressTracker.timeRange.duration { seekTargetTime = progressTracker.timeRange.duration }
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
            UIScreen.main.brightness = newBright
        case .none: break
        }
    }
    
    private func handlePanEnded(_ type: GestureType) {
        switch type {
        case .seeking:
            showSeekHUD = false
            player.seek(to: seekTargetTime)
            progressTracker.isInteracting = false
        case .volume:
            showVolumeHUD = false
        case .brightness:
            showBrightnessHUD = false
        case .none: break
        }
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
                    SpeedHUDView(isSpeedLocked: isSpeedLocked)
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
        await resumeFromServerHistoryIfNeeded()
        player.play()
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

    func resumeFromServerHistoryIfNeeded() async {
        guard let entry = await loadResumeHistory(), entry.durationSeconds > 0 else { return }
        let position = min(max(entry.positionSeconds, 0), max(entry.durationSeconds - 1, 0))
        guard position > 5, position < entry.durationSeconds - 5 else { return }
        let target = CMTime(seconds: position, preferredTimescale: 600)
        player.seek(to: target)
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
            player.togglePlayPause()
        }
    }

    func toggleCommandDeck() {
        isCommandDeckVisible.toggle()
    }

    func startPictureInPicture() {
        PictureInPicture.shared.startIfPossible()
    }

    func setSpeed(_ speed: Float) {
        currentSpeed = speed
        player.playbackSpeed = speed
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
        .background(.ultraThinMaterial, in: Capsule())
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
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct SpeedHUDView: View {
    let isSpeedLocked: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isSpeedLocked ? "lock.fill" : "chevron.down")
                .font(.system(size: 14))
            
            Text(isSpeedLocked ? "已锁定 2 倍速" : "下滑松手锁定 2 倍速")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6), in: Capsule())
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
    let setSpeed: (Float) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            PlayerTimeline(
                progressTracker: progressTracker,
                buffer: buffer,
                formatTime: formatTime
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
                
                SpeedMenu(player: player, currentSpeed: currentSpeed, setSpeed: setSpeed)
            }
        }
    }
}

private struct PlayerTimeline: View {
    @ObservedObject var progressTracker: ProgressTracker
    let buffer: Float
    let formatTime: (CMTime) -> String

    var body: some View {
        HStack(spacing: 12) {
            Text(formatTime(progressTracker.time))
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
            
            ZStack(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(height: 3)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.4))
                                .frame(width: geometry.size.width * CGFloat(buffer), height: 3)
                        }
                        .frame(maxHeight: .infinity)
                }

                Slider(progressTracker: progressTracker)
                    .tint(Color(red: 0.12, green: 0.86, blue: 0.78))
                    .disabled(!progressTracker.isProgressAvailable)
                    .scaleEffect(y: 0.8) // Sleeker slider
            }
            .frame(height: 24)
            
            Text(formatTime(progressTracker.timeRange.duration))
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

private struct SpeedMenu: View {
    @ObservedObject var player: Player
    let currentSpeed: Float
    let setSpeed: (Float) -> Void
    private let speeds: [Float] = [0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        Menu {
            ForEach(speeds, id: \.self) { speed in
                Button {
                    setSpeed(speed)
                } label: {
                    Label(speedLabel(speed), systemImage: currentSpeed == speed ? "checkmark" : "")
                }
                .disabled(!player.playbackSpeedRange.contains(speed))
            }
        } label: {
            Text(speedLabel(currentSpeed))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private func speedLabel(_ speed: Float) -> String {
        String(format: "%.2gx", speed)
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
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: thumbnailURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill().blur(radius: 40).opacity(0.4)
                }
            }
            .ignoresSafeArea()
        }
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
