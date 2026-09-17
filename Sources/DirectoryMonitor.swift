import Foundation
import Darwin

/// Coalesces Finder's bursts of writes. Polling also recovers after the watched
/// directory is replaced (for example by cloud synchronization).
final class DirectoryMonitor {
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var signature: [String]?
    private let url: URL
    private let changed: () -> Void
    init(url: URL, changed: @escaping () -> Void) {
        self.url = url; self.changed = changed
        signature = scan()
        attach()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.check()
            if self.source == nil { self.attach() }
        }
    }
    private func scan() -> [String]? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isHiddenKey], options: [.skipsHiddenFiles]) else { return nil }
        return files.map(\.lastPathComponent).sorted()
    }
    private func attach() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .revoke], queue: .main)
        watcher.setCancelHandler { close(fd) }
        watcher.setEventHandler { [weak self, weak watcher] in
            guard let self = self else { return }
            if let flags = watcher?.data, !flags.intersection([.rename, .delete, .revoke]).isEmpty {
                self.source?.cancel(); self.source = nil
            }
            self.pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.check() }
            self.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
        source = watcher; watcher.resume()
    }
    private func check() {
        let current = scan()
        guard current != signature else { return }
        signature = current; changed()
    }
    deinit { pending?.cancel(); source?.cancel(); timer?.invalidate() }
}
