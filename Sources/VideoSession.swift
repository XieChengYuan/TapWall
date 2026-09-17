import AppKit
import AVFoundation
import Combine

final class VideoSession: ObservableObject {
    @Published private(set) var player: AVPlayer?
    // Each session owns one clock. Applied wallpaper uses a separate snapshot session.
    @Published private(set) var previewPlayer: AVPlayer?
    @Published private(set) var name: String?
    @Published private(set) var duration = 0.0
    @Published private(set) var currentTime = 0.0
    @Published private(set) var dropTime = 0.0
    @Published private(set) var returnTime = 0.0
    @Published private(set) var dropEndTime = 0.0
    @Published private(set) var returnEndTime = 0.0
    private var rangeOrigin: CueSchedule?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var thumbnails: [NSImage] = []
    @Published private(set) var error: String?
    @Published var loop = true
    @Published var muted = true { didSet { player?.isMuted = muted } }
    var onTime: ((Double) -> Void)?
    var onEvent: ((CueKind) -> Void)?
    var onSeek: ((CuePhase) -> Void)?
    var onPlayerChanged: ((AVPlayer?) -> Void)?

    private var observer: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSKeyValueObservation?
    private var loadTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var generation = UUID()
    private var seekGeneration = 0
    private var seeking = false
    private var clock = CueClock()
    private var fps = 30.0
    var ready: Bool { player != nil && duration > 0 && !isLoading }
    var schedule: CueSchedule { CueSchedule(duration: duration, drop: dropTime, dropEnd: dropEndTime, restore: returnTime, restoreEnd: returnEndTime) }

    func load(_ url: URL) {
        clear()
        let token = generation
        isLoading = true
        name = url.lastPathComponent
        loadTask = Task { @MainActor [weak self] in
            do {
                let asset = AVURLAsset(url: url)
                let length = try await asset.load(.duration).seconds
                let playable = try await asset.load(.isPlayable)
                guard !Task.isCancelled, let self = self, self.generation == token else { return }
                guard playable, length.isFinite, length >= 0.2 else {
                    self.isLoading = false; self.error = "无法读取这段视频，请选择可播放的 MOV 或 MP4。"; return
                }
                self.install(asset: asset, duration: length, token: token)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                if let track = tracks.first {
                    let rate = try await track.load(.nominalFrameRate)
                    if self.generation == token, rate > 0 { self.fps = Double(rate) }
                }
            } catch {
                guard let self = self, self.generation == token, !Task.isCancelled else { return }
                self.error = "视频读取失败：\(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func install(asset: AVAsset, duration: Double, token: UUID, thumbnails: Bool = true) {
        self.duration = duration
        dropTime = duration * 0.15
        dropEndTime = duration * 0.45
        returnTime = duration * 0.65
        returnEndTime = duration * 0.9
        let item = AVPlayerItem(asset: asset)
        let master = AVPlayer(playerItem: item)
        master.isMuted = muted
        player = master; previewPlayer = master
        isLoading = false
        onPlayerChanged?(master)
        clock.reset()
        onSeek?(.ready)
        observer = master.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1 / 60.0, preferredTimescale: 600), queue: .main) { [weak self, weak master] time in
            guard let self = self, self.generation == token, !self.seeking else { return }
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            self.currentTime = min(self.duration, max(0, seconds))
            self.onTime?(self.currentTime)
            if self.isPlaying {
                self.deliver(at: self.currentTime)

            }
            if let error = master?.currentItem?.error { self.error = error.localizedDescription }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self = self, self.generation == token else { return }
            // Include cues exactly at the final frame, even if the last periodic tick missed it.
            self.deliver(at: self.duration)
            self.onTime?(self.duration)
            if self.loop { self.replay() } else { self.pause(); self.currentTime = self.duration }
        }
        failureObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async {
                guard let self = self, self.generation == token else { return }
                self.pause(); self.error = item.error?.localizedDescription ?? "视频无法播放。"
            }
        }
        if thumbnails { makeThumbnails(asset: asset, token: token) }
    }

    /// Copy immutable media and settings; never share an AVPlayer or playback cursor.
    func appliedSnapshot() -> VideoSession? {
        guard ready, let asset = player?.currentItem?.asset else { return nil }
        let copy = VideoSession()
        copy.loop = loop; copy.muted = muted; copy.name = name
        copy.install(asset: asset, duration: duration, token: copy.generation, thumbnails: false)
        copy.applySchedule(schedule)
        return copy
    }

    private func makeThumbnails(asset: AVAsset, token: UUID) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 120)
        let duration = self.duration
        thumbnailTask = Task { @MainActor [weak self] in
            for index in 0..<10 {
                guard !Task.isCancelled, self?.generation == token else { generator.cancelAllCGImageGeneration(); return }
                let time = CMTime(seconds: min(duration - 0.01, duration * Double(index) / 10), preferredTimescale: 600)
                guard let result = try? await generator.image(at: time) else { continue }
                guard !Task.isCancelled, self?.generation == token else { return }
                self?.thumbnails.append(NSImage(cgImage: result.image, size: .zero))
            }
        }
    }

    private func deliver(at time: Double) {
        for event in clock.advance(to: time, schedule: schedule) { onEvent?(event) }
    }
    func setCue(_ kind: CueKind, to value: Double, showFrame: Bool = true) {
        guard ready else { return }
        var updated = schedule
        updated.set(kind, to: value)
        applySchedule(updated)
        if showFrame { seek(to: schedule.time(kind)) }
        else { clock.seek(to: currentTime) }
    }
    private func applySchedule(_ updated: CueSchedule) {
        dropTime = updated.drop; dropEndTime = updated.dropEnd
        returnTime = updated.restore; returnEndTime = updated.restoreEnd
    }
    func moveRange(dropRange: Bool, translation: Double) {
        guard ready else { return }
        if rangeOrigin == nil { rangeOrigin = schedule }
        var updated = rangeOrigin!
        updated.moveRange(dropRange: dropRange, by: translation)
        applySchedule(updated)
        seek(to: dropRange ? dropTime : returnTime)
    }
    func endRangeDrag() { rangeOrigin = nil }
    func seek(to value: Double, resume: Bool = false, restarting: Bool = false) {
        guard ready, value.isFinite, let player = player else { return }
        pause()
        seeking = true
        seekGeneration += 1
        let revision = seekGeneration
        let token = generation
        let target = min(duration, max(0, value))
        currentTime = target
        let time = CMTime(seconds: target, preferredTimescale: 60000)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self = self, self.generation == token, self.seekGeneration == revision else { return }
                self.seeking = false
                guard finished else { return }
                if restarting { self.clock.reset(); self.onSeek?(.ready) }
                else { self.clock.seek(to: target); self.onSeek?(self.schedule.phase(at: target)) }
                if resume { self.startPlayers() }
            }
        }
    }
    private func startPlayers() {
        guard ready else { return }
        isPlaying = true
        player?.play()
    }
    func playPause() {
        if isPlaying { pause() }
        else if currentTime >= duration - 0.01 { replay() }
        else if seeking { seek(to: currentTime, resume: true) }
        else { startPlayers() }
    }
    func pause() { player?.pause(); isPlaying = false }
    func replay() { seek(to: 0, resume: true, restarting: true) }
    func step(_ direction: Int) { seek(to: currentTime + Double(direction) / fps) }
    func clear() {
        generation = UUID(); seekGeneration += 1
        loadTask?.cancel(); thumbnailTask?.cancel()
        pause()
        if let observer = observer { player?.removeTimeObserver(observer) }
        if let endObserver = endObserver { NotificationCenter.default.removeObserver(endObserver) }
        observer = nil; endObserver = nil; failureObserver = nil
        player = nil; previewPlayer = nil
        duration = 0; currentTime = 0; dropTime = 0; returnTime = 0
        dropEndTime = 0; returnEndTime = 0; rangeOrigin = nil
        name = nil; error = nil; thumbnails = []; isLoading = false; seeking = false
        clock.reset()
        onPlayerChanged?(nil)
    }
}
