import Foundation
@main struct DirectoryChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var monitor: DirectoryMonitor?
        var stage = 0
        let first = root.appendingPathComponent("first.txt")
        let renamed = root.appendingPathComponent("renamed.txt")
        let start = Date()
        monitor = DirectoryMonitor(url: root) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            do {
                switch stage {
                case 0:
                    precondition(names == ["first.txt"])
                    stage = 1; try FileManager.default.moveItem(at: first, to: renamed)
                case 1:
                    precondition(names == ["renamed.txt"])
                    stage = 2; try FileManager.default.removeItem(at: renamed)
                case 2:
                    precondition(names.isEmpty)
                    stage = 3; monitor = nil
                    try FileManager.default.removeItem(at: root)
                    print("PASS: directory creation, rename, deletion notifications and monitor cleanup")
                    exit(0)
                default: fatalError("Unexpected callback")
                }
            } catch { fatalError(error.localizedDescription) }
        }
        precondition(monitor != nil)
        try Data("test".utf8).write(to: first)
        _ = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            if Date().timeIntervalSince(start) > 8 { fatalError("Directory monitor timed out at step \(stage)") }
        }
        RunLoop.main.run()
    }
}
