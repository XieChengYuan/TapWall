import AppKit
import Combine

enum IconArrangement: String, CaseIterable, Decodable {
    case horizontal, vertical, grid
    var title: String {
        switch self { case .horizontal: return "横排"; case .vertical: return "竖排"; case .grid: return "方阵" }
    }
    var symbol: String {
        switch self { case .horizontal: return "rectangle.split.3x1"; case .vertical: return "rectangle.split.1x2"; case .grid: return "square.grid.2x2" }
    }
}
enum IconEdge: String, CaseIterable, Decodable {
    case left, right
    var title: String { self == .left ? "靠左" : "靠右" }
}
enum DropMode: String, CaseIterable, Decodable {
    case shake, freefall, wind, vortex, burst
    var title: String {
        switch self { case .shake: return "震落"; case .freefall: return "直落"; case .wind: return "风吹"; case .vortex: return "旋落"; case .burst: return "弹飞" }
    }
    var symbol: String {
        switch self { case .shake: return "waveform.path"; case .freefall: return "arrow.down"; case .wind: return "wind"; case .vortex: return "tornado"; case .burst: return "arrow.up.left.and.arrow.down.right" }
    }
    var detail: String {
        switch self { case .shake: return "轻轻震开，再自然落下"; case .freefall: return "沿竖直方向自由下落"; case .wind: return "从屏幕边缘向内吹散"; case .vortex: return "旋转着散开落下"; case .burst: return "向四周弹开、碰撞" }
    }
}
enum ReturnMode: String, CaseIterable, Decodable {
    case glide, spring, arc, cascade, instant
    var title: String {
        switch self { case .glide: return "平滑"; case .spring: return "弹性"; case .arc: return "弧线"; case .cascade: return "依次"; case .instant: return "瞬间" }
    }
    var symbol: String {
        switch self { case .glide: return "arrow.up.forward"; case .spring: return "waveform.path"; case .arc: return "arrow.turn.up.right"; case .cascade: return "line.3.horizontal.decrease"; case .instant: return "bolt" }
    }
}

/// The first icon is always at a top corner. A short last row/column never recenters.
func homePositions(count: Int, size: CGSize, arrangement: IconArrangement = .vertical, edge: IconEdge = .right) -> [CGPoint] {
    guard count > 0 else { return [] }
    let maxColumns = max(1, Int((size.width - 140) / 104) + 1)
    let maxRows = max(1, Int((size.height - 170) / 96) + 1)
    let columns: Int
    let rows: Int
    switch arrangement {
    case .horizontal:
        columns = min(count, maxColumns)
        rows = (count + columns - 1) / columns
    case .vertical:
        rows = min(count, maxRows)
        columns = (count + rows - 1) / rows
    case .grid:
        columns = min(maxColumns, max(1, Int(ceil(sqrt(Double(count))))))
        rows = (count + columns - 1) / columns
    }
    let stepX = columns > 1 ? min(104, max(1, size.width - 140) / CGFloat(columns - 1)) : 0
    let stepY = rows > 1 ? min(96, max(1, size.height - 170) / CGFloat(rows - 1)) : 0
    return (0..<count).map { index in
        let col = arrangement == .vertical ? index / rows : index % columns
        let row = arrangement == .vertical ? index % rows : index / columns
        let x = edge == .left ? 70 + CGFloat(col) * stepX : size.width - 70 - CGFloat(col) * stepX
        return CGPoint(x: x, y: size.height - 80 - CGFloat(row) * stepY)
    }
}

enum CueKind: CaseIterable { case drop, dropEnd, restore, restoreEnd
    var title: String { switch self { case .drop: return "掉落开始"; case .dropEnd: return "掉落结束"; case .restore: return "归位开始"; case .restoreEnd: return "归位结束" } }
    var isDrop: Bool { self == .drop || self == .dropEnd }
}
enum CuePhase { case ready, falling, settled, returning, returned }

struct CueSchedule {
    var duration: Double
    var drop: Double
    var dropEnd: Double
    var restore: Double
    var restoreEnd: Double
    var gap: Double { min(0.1, duration / 8) }
    func time(_ kind: CueKind) -> Double {
        switch kind { case .drop: return drop; case .dropEnd: return dropEnd; case .restore: return restore; case .restoreEnd: return restoreEnd }
    }
    mutating func set(_ kind: CueKind, to value: Double) {
        guard duration.isFinite, duration > 0, value.isFinite else { return }
        switch kind {
        case .drop: drop = min(max(0, value), dropEnd - gap)
        case .dropEnd: dropEnd = min(restore, max(drop + gap, value))
        case .restore: restore = min(restoreEnd - gap, max(dropEnd, value))
        case .restoreEnd: restoreEnd = min(duration, max(restore + gap, value))
        }
    }
    mutating func moveRange(dropRange: Bool, by delta: Double) {
        guard delta.isFinite else { return }
        if dropRange {
            let shift = min(restore - dropEnd, max(-drop, delta))
            drop += shift; dropEnd += shift
        } else {
            let shift = min(duration - restoreEnd, max(dropEnd - restore, delta))
            restore += shift; restoreEnd += shift
        }
    }
    func phase(at time: Double) -> CuePhase {
        if time >= restoreEnd { return .returned }
        if time >= restore { return .returning }
        if time >= dropEnd { return .settled }
        return time >= drop ? .falling : .ready
    }
}

struct CueClock {
    private(set) var previous = -Double.ulpOfOne
    mutating func reset() { previous = -Double.ulpOfOne }
    mutating func seek(to time: Double) { previous = time }
    mutating func advance(to time: Double, schedule: CueSchedule) -> [CueKind] {
        guard time.isFinite, time >= previous else { return [] }
        let events = CueKind.allCases.filter { previous < schedule.time($0) && time >= schedule.time($0) }
        previous = time
        return events
    }
}

enum WallpaperCategory: String, CaseIterable, Identifiable {
    case video, interactive
    var id: String { rawValue }
    var title: String { self == .video ? "视频壁纸" : "互动壁纸" }
    var symbol: String { self == .video ? "play.rectangle" : "cursorarrow.motionlines" }
    var detail: String { self == .video ? "视频与图标动作" : "选择场景，与桌面互动" }
}

enum WallpaperKind: String, CaseIterable, Identifiable {
    case video, cat
    var id: String { rawValue }
    var category: WallpaperCategory { self == .video ? .video : .interactive }
    var title: String { self == .video ? "视频壁纸" : "窗边的猫" }
    static var interactiveScenes: [WallpaperKind] { allCases.filter { $0.category == .interactive } }
}

final class ConsoleModel: ObservableObject {
    @Published var wallpaperKind = WallpaperKind.video
    @Published var catPreviewPaused = false
    @Published var arrangement = IconArrangement(rawValue: UserDefaults.standard.string(forKey: "iconArrangement") ?? "") ?? .vertical
    @Published var edge = IconEdge(rawValue: UserDefaults.standard.string(forKey: "iconEdge") ?? "") ?? .right
    @Published var dropMode = DropMode(rawValue: UserDefaults.standard.string(forKey: "dropMode") ?? "") ?? .shake
    @Published var returnMode = ReturnMode(rawValue: UserDefaults.standard.string(forKey: "returnMode") ?? "") ?? .glide
    @Published var source = 0
    @Published var status = "准备就绪"
    @Published var count = 0
    @Published var isDesktop = false
    @Published var hasApplied = false
    @Published var isFalling = false
}

func timecode(_ seconds: Double) -> String {
    let safe = seconds.isFinite ? max(0, seconds) : 0
    return String(format: "%02d:%05.2f", Int(safe) / 60, safe.truncatingRemainder(dividingBy: 60))
}
