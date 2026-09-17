import Foundation

/// One bundled preset is shared by first-run UI and the example video's timing.
struct DefaultExample: Decodable {
    let arrangement: IconArrangement
    let edge: IconEdge
    let dropMode: DropMode
    let returnMode: ReturnMode
    let dropStart: Double
    let dropEnd: Double
    let returnStart: Double
    let returnEnd: Double
    let loop: Bool
    let muted: Bool

    static func load(from url: URL?) -> DefaultExample? {
        guard let url = url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DefaultExample.self, from: data)
    }
    func schedule(duration: Double) -> CueSchedule? {
        guard dropStart >= 0, dropStart < dropEnd, dropEnd <= returnStart,
              returnStart < returnEnd, returnEnd <= duration else { return nil }
        return CueSchedule(duration: duration, drop: dropStart, dropEnd: dropEnd, restore: returnStart, restoreEnd: returnEnd)
    }
}
