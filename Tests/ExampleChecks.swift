import AppKit
@main struct ExampleChecks {
    static func main() {
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let preset = DefaultExample.load(from: resources.appendingPathComponent("DefaultExample.json")) else { fatalError("Missing example preset") }
        precondition(preset.arrangement == .grid && preset.edge == .left)
        precondition(preset.dropMode == .shake && preset.returnMode == .cascade)
        precondition(preset.loop && preset.muted)
        let video = VideoSession()
        video.load(resources.appendingPathComponent("default-wallpaper.mp4"), preset: preset)
        let start = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let error = video.error { fatalError(error) }
            if video.ready {
                precondition(!video.isPlaying && video.currentTime == 0)
                precondition(video.dropTime == 2.35 && video.dropEndTime == 3.32)
                precondition(video.returnTime == 4.84 && video.returnEndTime == 5.94)
                precondition(video.loop && video.muted)
                guard let applied = video.appliedSnapshot() else { fatalError("Cannot apply default video") }
                precondition(applied.dropTime == 2.35 && applied.returnEndTime == 5.94)
                precondition(applied.player !== video.player)
                applied.clear(); video.clear()
                print("PASS: bundled example video, exact screenshot preset, paused preview and independent apply")
                exit(0)
            }
            if Date().timeIntervalSince(start) > 15 { fatalError("Example load timeout") }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.run()
    }
}
