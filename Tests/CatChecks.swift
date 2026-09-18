import AppKit
@main struct CatChecks {
    static func main() {
        var cat = CatMotion()
        for _ in 0..<18 { cat.step(dt: 0.05, pointer: CGPoint(x: 0.75, y: 0.4), reducedMotion: false) }
        precondition(cat.mood == .pouncing)
        for _ in 0..<15 { cat.step(dt: 0.05, pointer: nil, reducedMotion: false) }
        precondition(abs(cat.x - 0.75) < 0.001 && cat.jump == 0)
        for _ in 0..<280 { cat.step(dt: 0.05, pointer: nil, reducedMotion: false) }
        precondition(cat.mood == .resting)
        cat.step(dt: 0.05, pointer: CGPoint(x: 0.75, y: 0.55), reducedMotion: false)
        precondition(cat.mood == .petting)
        for _ in 0..<25 { cat.step(dt: 0.05, pointer: CGPoint(x: 0.75, y: 0.35), reducedMotion: false) }
        precondition(cat.mood == .pawing)
        for _ in 0..<200 {
            cat.step(dt: 0.05, pointer: CGPoint(x: 0.4, y: 0.4), reducedMotion: true)
            precondition(cat.jump == 0 && cat.x >= 0.16 && cat.x <= 0.84)
        }
        var below = CatMotion()
        for _ in 0..<20 { below.step(dt: 0.05, pointer: CGPoint(x: 0.5, y: 0.1), reducedMotion: false) }
        precondition(below.mood == .reaching && below.jump == 0 && below.x == 0.5 && below.downwardReach > 0.9)
        for _ in 0..<60 {
            below.step(dt: 0.05, pointer: CGPoint(x: 0.8, y: 0.12), reducedMotion: false)
            precondition(below.jump == 0 && below.mood != .pouncing)
        }
        precondition(below.mood == .reaching && abs(below.x - 0.8) < 0.1 && below.downwardReach > 0.9)
        for _ in 0..<30 { below.step(dt: 0.05, pointer: nil, reducedMotion: false) }
        precondition(below.downwardReach < 0.01)
        below.step(dt: 0.05, pointer: CGPoint(x: below.x, y: 0.1), reducedMotion: true)
        precondition(below.downwardReach == 1 && below.jump == 0)
        for _ in 0..<270 { below.step(dt: 0.05, pointer: nil, reducedMotion: false) }
        precondition(below.mood == .resting && below.downwardReach < 0.01)
        print("PASS: downward reach in place, approach then reach without jumping, retraction and rest")
        print("PASS: cat pounce completion, rest, wake, petting, pawing, reduced motion and bounds")
    }
}
