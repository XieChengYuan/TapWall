import AppKit
import AVFoundation
@main struct VideoChecks {
 static func main() {
    let video = VideoSession()
    var events: [CueKind] = []
    var configured = false
    var finishing = false
    video.onEvent = { events.append($0) }
    video.load(URL(fileURLWithPath: CommandLine.arguments[1]))
    let start = Date()
    let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
        if let error = video.error { fatalError(error) }
        if video.ready && !configured {
            configured = true
            precondition(abs(video.duration - 6) < 0.1)
            precondition(!video.isPlaying)
            video.setCue(.drop, to: 0.2, showFrame: false)
            video.setCue(.dropEnd, to: 0.5, showFrame: false)
            video.setCue(.restore, to: 0.7, showFrame: false)
            video.setCue(.restoreEnd, to: 1.0, showFrame: false)
            video.replay()
        }
        if events.count >= 8 && !finishing {
            finishing = true
            precondition(events == CueKind.allCases + CueKind.allCases)
            video.seek(to: 0.4)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                precondition(!video.isPlaying && abs(video.currentTime - 0.4) < 0.04)
                precondition(events.count == 8)
                guard let wallpaper = video.appliedSnapshot() else { fatalError("Missing applied snapshot") }
                precondition(wallpaper.player !== video.player)
                precondition(wallpaper.player?.currentItem !== video.player?.currentItem)
                let appliedDrop = wallpaper.dropTime
                wallpaper.replay()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let before = wallpaper.currentTime
                    video.setCue(.drop, to: 0.35)
                    video.muted = false; video.loop = false
                    video.seek(to: 3.5)
                    video.pause()
                    precondition(wallpaper.dropTime == appliedDrop && wallpaper.muted && wallpaper.loop)
                    guard let next = video.appliedSnapshot() else { fatalError("Reapply failed") }
                    precondition(next.dropTime == 0.35 && !next.loop && !next.muted)
                    next.clear()
                    video.clear()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        precondition(wallpaper.isPlaying && wallpaper.currentTime > before + 0.2)
                        precondition(wallpaper.dropTime == appliedDrop)
                        precondition(!video.ready && video.previewPlayer == nil)
                        wallpaper.clear()
                        print("PASS: timed ranges, loop, seek, independent apply snapshot; preview pause/seek/settings/clear cannot affect wallpaper; reapply copies updated settings")
                        exit(0)
                    }
                }
            }
        }
        if Date().timeIntervalSince(start) > 18 { fatalError("Video timeout: \(events.count)") }
    }
    RunLoop.main.add(timer, forMode: .common)
    RunLoop.main.run()
 }
}
