import AppKit
import AVFoundation
import SwiftUI
import simd

// All filesystem operations in this app are reads. Finder owns the original items.
struct IconItem {
    let url: URL
    let title: String
    let image: NSImage
    let isDesktop: Bool
}

enum Catalog {
    static let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    static func items(in folder: URL, desktop: Bool) throws -> [IconItem] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isHiddenKey], options: [.skipsHiddenFiles])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { IconItem(url: $0, title: FileManager.default.displayName(atPath: $0.path), image: NSWorkspace.shared.icon(forFile: $0.path), isDesktop: desktop) }
    }
    static func applications() -> [IconItem] {
        let folders = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var seen = Set<String>()
        return folders.flatMap { (try? items(in: $0, desktop: false)) ?? [] }
            .filter { $0.url.pathExtension == "app" && seen.insert($0.url.resolvingSymlinksInPath().path).inserted }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

struct FileNode {
    let item: IconItem
}

final class TumbleScene {
    var files: [FileNode] = []
    var spatial: SpatialIcons!
    var onStatus: ((String) -> Void)?
    var onEscape: (() -> Void)?
    var onOpen: ((URL) -> Void)?
    var onToggleDesktop: (() -> Void)?
    var falling = false
    var arrangement: IconArrangement = .vertical
    var edge: IconEdge = .right
    var returnMode: ReturnMode = .glide { didSet { spatial?.returnMode = returnMode } }
    var dropMode: DropMode = .shake { didSet { sync() } }
    func sync() {
        guard spatial != nil else { return }
        spatial.arrangement = arrangement; spatial.edge = edge
        spatial.dropMode = dropMode; spatial.returnMode = returnMode
        spatial.configure(items: files.map(\.item))
    }
    func load(_ items: [IconItem]) {
        files = items.map(FileNode.init); sync(); restore(animated: false)
    }
    func restore(animated: Bool = true, interval: Double? = nil) {
        sync(); falling = false
        spatial?.restore(animated: animated, interval: interval ?? 0.8)
        onStatus?("立体图标归位")
    }
    func scatter() { sync(); falling = true; spatial?.scatter(); onStatus?("3D 掉落 · 完整翻转与堆叠") }
}

final class StageView: NSView {
    let playerLayer = AVPlayerLayer()
    var wallpaper: NSImage?
    var hasVideo = false { didSet { needsDisplay = true; playerLayer.isHidden = !hasVideo } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.isHidden = true
        layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); playerLayer.frame = bounds }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.035, green: 0.07, blue: 0.11, alpha: 1).setFill()
        bounds.fill()
        if let image = wallpaper, !hasVideo {
            let scale = max(bounds.width / max(1, image.size.width), bounds.height / max(1, image.size.height))
            let rect = NSRect(x: (bounds.width - image.size.width * scale) / 2, y: (bounds.height - image.size.height * scale) / 2, width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: rect)
            NSColor.black.withAlphaComponent(0.25).setFill(); bounds.fill()
        } else if !hasVideo {
            NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.23, blue: 0.26, alpha: 1), NSColor(calibratedRed: 0.055, green: 0.095, blue: 0.16, alpha: 1)])?.draw(in: bounds, angle: -60)
            NSColor.white.withAlphaComponent(0.055).setFill()
            for x in stride(from: CGFloat(20), to: bounds.width, by: 26) {
                for y in stride(from: CGFloat(20), to: bounds.height, by: 26) { NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 1.5, height: 1.5)).fill() }
            }
        }
    }
}

final class StageWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: StageWindow!
    var controls: NSPanel!
    var stage: StageView!
    var spatial: SpatialIcons!
    var scene: TumbleScene!
    let console = ConsoleModel()
    let video = VideoSession()
    var wallpaperVideo: VideoSession?
    var draftItems: [IconItem] = []
    var draftWallpaper: NSImage?
    var draftMonitor: DirectoryMonitor?
    var appliedMonitor: DirectoryMonitor?
    var appliedSource: (index: Int, folder: URL)?
    var desktopMode = false
    var savedFrame = NSRect.zero
    var customFolder: URL?
    var loadedSource = 0
    var statusItem: NSStatusItem!
    var verification = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        verification = CommandLine.arguments.contains("--verify")
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "TapWall", withExtension: "png") {
            NSApp.applicationIconImage = NSImage(contentsOf: iconURL)
        }
        buildMenu()
        buildWindow()
        buildControls()
        if verification { scene.load(Array(Catalog.applications().prefix(24))) } else { reload() }
        window.makeKeyAndOrderFront(nil)
        controls.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let index = CommandLine.arguments.firstIndex(of: "--preview-video"), CommandLine.arguments.count > index + 1 {
            video.load(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        if verification { verifyRunningApp() }
    }
    func buildMenu() {
        let menu = NSMenu()
        let app = NSMenuItem(); let submenu = NSMenu()
        submenu.addItem(withTitle: "退出 TapWall", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = submenu; menu.addItem(app)
        let edit = NSMenuItem(); edit.title = "编辑"; let edits = NSMenu(title: "编辑")
        for (title, selector, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edits.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        edit.submenu = edits; menu.addItem(edit); NSApp.mainMenu = menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "TapWall")
        let statusMenu = NSMenu()
        for (title, action) in [("显示控制台", #selector(showControls)), ("执行掉落", #selector(scatter)), ("全部归位", #selector(restore)), ("切换桌面模式", #selector(toggleDesktop))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; statusMenu.addItem(item)
        }
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "退出并还原桌面", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = statusMenu
    }
    func buildWindow() {
        let screen = NSScreen.main!.visibleFrame
        let rect = NSRect(x: screen.midX - 560, y: screen.midY - 350, width: min(1120, screen.width - 60), height: min(700, screen.height - 80))
        window = StageWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "TapWall · 真实图标互动桌面"
        window.minSize = NSSize(width: 900, height: 650)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        stage = StageView(frame: NSRect(origin: .zero, size: rect.size))
        window.contentView = stage
        spatial = SpatialIcons(frame: stage.bounds)
        spatial.autoresizingMask = [.width, .height]
        stage.addSubview(spatial)
        scene = TumbleScene()
        scene.spatial = spatial
        scene.arrangement = console.arrangement
        scene.dropMode = console.dropMode
        scene.edge = console.edge
        scene.returnMode = console.returnMode
        scene.onStatus = { [weak self] status in
            self?.console.status = status
            self?.console.isFalling = self?.scene.falling ?? false
        }
        scene.onEscape = { [weak self] in self?.escape() }
        scene.onToggleDesktop = { [weak self] in self?.toggleDesktop() }
        scene.onOpen = { [weak self] url in
            NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                DispatchQueue.main.async { self?.console.status = error.map { "打开失败：\($0.localizedDescription)" } ?? "已打开：\(url.lastPathComponent)" }
            }
        }
        spatial.onOpen = scene.onOpen
        spatial.onEscape = scene.onEscape
        spatial.onToggle = scene.onToggleDesktop
        window.makeFirstResponder(spatial)
    }
    func buildControls() {
        controls = NSPanel(contentRect: NSRect(origin: .zero, size: CGSize(width: 1040, height: 720)), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        controls.title = "TapWall 控制台"
        controls.delegate = self
        controls.minSize = CGSize(width: 900, height: 700)
        controls.titleVisibility = .hidden
        controls.titlebarAppearsTransparent = true
        // Only the native title bar moves the panel. Content drags belong to
        // the video timeline and must not be interpreted as window dragging.
        controls.isMovableByWindowBackground = false
        controls.level = .floating
        controls.hidesOnDeactivate = false
        controls.isReleasedWhenClosed = false
        controls.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        controls.appearance = NSAppearance(named: .aqua)
        controls.backgroundColor = NSColor(calibratedWhite: 0.975, alpha: 1)
        controls.hasShadow = true
        controls.contentView = NSHostingView(rootView: ConsoleView(model: console, video: video) { [weak self] action in
            guard let self = self else { return }
            switch action {
            case .apply: self.applySettings()
            case .scatter: self.scatter()
            case .restore: self.restore()
            case .toggleDesktop: self.toggleDesktop()
            case .hide: self.hideControls()
            case .reload: self.reload()
            case .sourceChanged: self.changeSource()
            case .chooseVideo: self.chooseVideo()
            case .clearVideo: self.clearVideo()
            case .useWallpaper: self.useWallpaper()
            case .chooseFolder: self.chooseFolder()
            case .edge(let edge):
                self.console.edge = edge
                UserDefaults.standard.set(edge.rawValue, forKey: "iconEdge")
                if !self.console.hasApplied { self.scene.edge = edge; self.scene.restore() }
            case .returnMode(let mode):
                self.console.returnMode = mode
                if !self.console.hasApplied { self.scene.returnMode = mode }
                UserDefaults.standard.set(mode.rawValue, forKey: "returnMode")
            case .arrangement(let arrangement): self.changeArrangement(arrangement)
            case .dropMode(let mode): self.changeDropMode(mode)
            }
        })
        positionControls()
    }
    func changeArrangement(_ arrangement: IconArrangement) {
        console.arrangement = arrangement
        if !console.hasApplied { scene.arrangement = arrangement }
        if !verification { UserDefaults.standard.set(arrangement.rawValue, forKey: "iconArrangement") }
        if !console.hasApplied { scene.restore(animated: !verification && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
        console.status = "已选择\(arrangement.title) · 点击应用生效"
    }
    func changeDropMode(_ mode: DropMode) {
        console.dropMode = mode
        if !console.hasApplied { scene.dropMode = mode }
        if !verification { UserDefaults.standard.set(mode.rawValue, forKey: "dropMode") }
        console.status = "已选择\(mode.title)：\(mode.detail)"
    }
    func positionControls(animate: Bool = false) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = CGSize(width: min(1040, visible.width - 40), height: min(720, visible.height - 40))
        controls.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height), display: true, animate: animate)
    }
    func chooseFolder() {
        let old = console.source
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false
        picker.prompt = "读取图标"
        if picker.runModal() == .OK, let url = picker.url { customFolder = url; console.source = 2; reload() }
        else { console.source = old }
    }
    @objc func showControls() { controls.makeKeyAndOrderFront(nil) }
    @objc func hideControls() { controls.orderOut(nil); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(spatial) }
    @objc func changeSource() {
        if console.source == 2 {
            let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false; picker.prompt = "读取图标"; picker.message = "只读取文件名称和图标，不修改文件。"
            if picker.runModal() == .OK, let url = picker.url { customFolder = url }
            else { console.source = loadedSource; return }
        }
        reload()
    }
    private func readIcons(index: Int, folder: URL) throws -> [IconItem] {
        var items = try Catalog.items(in: folder, desktop: true)
        if index == 0 { items.append(contentsOf: Catalog.applications().prefix(max(0, 24 - items.count))) }
        return Array(items.prefix(32))
    }
    private func refreshDraft() {
        let folder = console.source == 2 ? (customFolder ?? Catalog.desktop) : Catalog.desktop
        do {
            let items = try readIcons(index: console.source, folder: folder)
            let changed = items.map(\.url) != draftItems.map(\.url)
            draftItems = items
            if !console.hasApplied && (changed || scene.files.isEmpty) { scene.load(items) }
            console.count = items.count
            console.status = items.count == 32 ? "图标已同步 · 最多显示 32 个项目" : "图标已同步 · 新文件会自动显示"
        } catch {
            console.status = "读取失败：\(error.localizedDescription)；保留当前图标。"
        }
    }
    private func refreshApplied() {
        guard let source = appliedSource else { return }
        do {
            let items = try readIcons(index: source.index, folder: source.folder)
            guard items.map(\.url) != scene.files.map({ $0.item.url }) else { return }
            // Keep the applied arrangement and animation modes, not the pending edits.
            scene.load(items)
            if let live = wallpaperVideo {
                let time = live.player?.currentTime().seconds ?? live.currentTime
                spatial.sample(time: time.isFinite ? time : live.currentTime, schedule: live.schedule)
            }
            console.status = "壁纸图标已自动同步 · 视频继续播放"
        } catch {
            console.status = "暂时无法同步文件夹，保留现有图标：\(error.localizedDescription)"
        }
    }
    @objc func reload() {
        loadedSource = console.source
        let folder = console.source == 2 ? (customFolder ?? Catalog.desktop) : Catalog.desktop
        draftMonitor = DirectoryMonitor(url: folder) { [weak self] in self?.refreshDraft() }
        refreshDraft()
        refreshApplied()
    }
    func applySettings() {
        guard !video.isLoading, video.error == nil else { return }
        let applied = video.appliedSnapshot()
        wallpaperVideo?.clear()
        wallpaperVideo = applied
        console.hasApplied = true
        scene.arrangement = console.arrangement; scene.edge = console.edge
        scene.returnMode = console.returnMode; scene.dropMode = console.dropMode
        scene.load(draftItems)
        let folder = console.source == 2 ? (customFolder ?? Catalog.desktop) : Catalog.desktop
        appliedSource = (console.source, folder)
        appliedMonitor = DirectoryMonitor(url: folder) { [weak self] in self?.refreshApplied() }
        stage.playerLayer.player = applied?.player
        stage.hasVideo = applied != nil
        stage.wallpaper = draftWallpaper
        stage.needsDisplay = true
        if !desktopMode { toggleDesktop() }
        if let applied = applied {
            applied.onTime = { [weak self, weak applied] time in
                guard let self = self, let applied = applied, self.wallpaperVideo === applied else { return }
                self.spatial.sample(time: time, schedule: applied.schedule)
            }
            applied.onSeek = { [weak self, weak applied] _ in
                guard let self = self, let applied = applied, self.wallpaperVideo === applied else { return }
                self.spatial.sample(time: applied.currentTime, schedule: applied.schedule)
            }
            applied.replay()
        }
        console.status = "已应用 · 预览操作不会影响壁纸，修改后再次点击应用"
        controls.makeKeyAndOrderFront(nil)
    }
    @objc func scatter() { scene.scatter(); window.makeFirstResponder(spatial) }
    @objc func restore() { scene.restore(); window.makeFirstResponder(spatial) }
    @objc func toggleDesktop() {
        desktopMode.toggle()
        if desktopMode {
            savedFrame = window.frame
            let screen = window.screen ?? NSScreen.main!
            window.styleMask = [.borderless]
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.setFrame(screen.frame, display: true)
            console.isDesktop = true
            console.status = "桌面模式 · 原生图标被本窗口覆盖，退出即恢复 · 菜单栏可呼出控制台"
        } else {
            window.level = .normal
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.collectionBehavior = []
            window.setFrame(savedFrame, display: true)
            console.isDesktop = false
            console.status = "已返回窗口模式 · Finder 桌面未修改"
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(spatial)
        positionControls()
    }
    func escape() { if desktopMode { toggleDesktop() }; showControls(); scene.restore() }
    @objc func useWallpaper() {
        clearVideo()
        if let screen = window.screen ?? NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen), let image = NSImage(contentsOf: url) {
            draftWallpaper = image; console.status = "已选择当前壁纸 · 点击应用生效"
        } else { console.status = "当前壁纸无法读取（可能为动态壁纸），继续使用默认背景。" }
    }
    @objc func chooseVideo() {
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.movie]; picker.canChooseDirectories = false; picker.message = "选择本地视频作为背景，图标按完整三维物理轨迹播放。视频默认静音。"
        guard picker.runModal() == .OK, let url = picker.url else { return }
        draftWallpaper = nil
        video.load(url)
    }
    @objc func clearVideo() { video.clear(); draftWallpaper = nil; console.status = "已移除预览视频 · 点击应用生效" }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === controls { controls.orderOut(nil) } else { NSApp.terminate(nil) }
        return false
    }
    func applicationWillTerminate(_ notification: Notification) { video.clear(); wallpaperVideo?.clear() }

    func verifyRunningApp() {
        verifyModels()
        precondition(!scene.files.isEmpty)
        for mode in DropMode.allCases {
            scene.dropMode = mode
            let frames = spatial.frames
            precondition(frames.count > 60)
            precondition(zip(frames.first!, frames.last!).contains { abs($0.position.y - $1.position.y) > 100 }, "Physics must actually advance")
            precondition(frames.last!.allSatisfy { $0.position.y < 260 && $0.position.y > 0 }, "All icons must finish near the lower edge")
            for duration in [0.1, 0.5, 2.0, 8.0] {
                let schedule = CueSchedule(duration: duration * 3, drop: 0, dropEnd: duration, restore: duration * 1.5, restoreEnd: duration * 2.5)
                spatial.sample(time: duration * 0.5, schedule: schedule)
                precondition(zip(spatial.visiblePoses, spatial.dropPose(0.5)).allSatisfy { simd_distance($0.position, $1.position) < 0.01 })
                spatial.sample(time: duration, schedule: schedule)
                precondition(zip(spatial.visiblePoses, frames.last!).allSatisfy { simd_distance($0.position, $1.position) < 0.01 })
                for returning in ReturnMode.allCases {
                    spatial.returnMode = returning
                    spatial.sample(time: schedule.restoreEnd, schedule: schedule)
                    precondition(zip(spatial.visiblePoses, frames.first!).allSatisfy { simd_distance($0.position, $1.position) < 0.01 && abs(simd_dot($0.rotation.vector, $1.rotation.vector)) > 0.999 })
                }
            }
        }
        print("PASS: real 3D physics bake, settled lower-edge pile, complete time remapping, four cue boundaries")
        NSApp.terminate(nil)
    }
}

func verifyModels() {
    for size in [CGSize(width: 900, height: 650), CGSize(width: 1120, height: 700), CGSize(width: 1512, height: 982)] {
        for count in [0, 1, 24, 32] {
            for arrangement in IconArrangement.allCases {
                for edge in IconEdge.allCases {
                    let points = homePositions(count: count, size: size, arrangement: arrangement, edge: edge)
                    precondition(points.count == count)
                    precondition(points.allSatisfy { $0.x >= 40 && $0.x <= size.width - 40 && $0.y >= 80 && $0.y <= size.height - 40 })
                    precondition(Set(points.map { "\($0.x),\($0.y)" }).count == count)
                    if let first = points.first { precondition(first.x == (edge == .left ? 70 : size.width - 70) && first.y == size.height - 80) }
                }
            }
        }
    }
    var schedule = CueSchedule(duration: 6, drop: 1, dropEnd: 2, restore: 4, restoreEnd: 5)
    schedule.set(.drop, to: 9); precondition(abs(schedule.drop - 1.9) < 0.001)
    schedule.set(.restoreEnd, to: 99); precondition(schedule.restoreEnd == 6)
    schedule.moveRange(dropRange: true, by: -10); precondition(schedule.drop == 0)
    schedule.moveRange(dropRange: false, by: 10); precondition(schedule.restoreEnd == 6)
    for cue in CueKind.allCases {
        for value in [-10.0, 0, 2, 4, 99] {
            var copy = schedule; copy.set(cue, to: value)
            precondition(copy.drop >= 0 && copy.drop < copy.dropEnd && copy.dropEnd <= copy.restore && copy.restore < copy.restoreEnd && copy.restoreEnd <= 6)
        }
    }
    var clock = CueClock()
    precondition(clock.advance(to: 6, schedule: schedule) == CueKind.allCases)
    precondition(clock.advance(to: 6, schedule: schedule).isEmpty)
    clock.reset(); precondition(clock.advance(to: 6, schedule: schedule) == CueKind.allCases)

}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
