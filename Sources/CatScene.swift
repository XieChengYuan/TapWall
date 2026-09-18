import AppKit
import SwiftUI

struct CatMotion {
    enum Mood { case watching, stalking, pouncing, resting, petting, pawing, approaching, reaching }
    private(set) var x: CGFloat = 0.5
    private(set) var mood = Mood.watching
    private(set) var jump: CGFloat = 0
    private(set) var downwardReach: CGFloat = 0
    private var idle = 0.0, charge = 0.0, progress = 0.0, cooldown = 0.0
    private var origin: CGFloat = 0.5, destination: CGFloat = 0.5
    private var previous: CGPoint?
    mutating func step(dt: Double, pointer: CGPoint?, reducedMotion: Bool) {
        let dt = min(0.05, max(0, dt))
        cooldown = max(0, cooldown - dt)
        let moved = pointer.map { p in previous.map { hypot(p.x - $0.x, p.y - $0.y) > 0.001 } ?? true } ?? false
        previous = pointer; idle = moved ? 0 : idle + dt
        let wantsReach = pointer.map { $0.y < 0.25 && abs($0.x - x) < 0.14 } ?? false
        let reachTarget: CGFloat = wantsReach && idle <= 12 && mood != .pouncing ? 1 : 0
        downwardReach += (reachTarget - downwardReach) * (reducedMotion ? 1 : CGFloat(1 - exp(-dt * 8)))
        if mood == .pouncing {
            progress = min(1, progress + dt / 0.65)
            let t = CGFloat(progress), ease = t * t * (3 - 2 * t)
            x = origin + (destination - origin) * ease
            jump = reducedMotion ? 0 : sin(t * .pi) * 0.13
            if progress >= 1 { mood = .watching; cooldown = 2; jump = 0 }
            return
        }
        if idle > 12 { mood = .resting; charge = 0; return }
        guard let pointer = pointer else { mood = .watching; charge = 0; return }
        let distance = abs(pointer.x - x)
        if pointer.y < 0.25 {
            charge = 0; jump = 0
            if distance > 0.09 {
                mood = .approaching
                let target = min(0.84, max(0.16, pointer.x))
                let travel = CGFloat(dt) * 0.24
                x += min(travel, max(-travel, target - x))
            } else { mood = .reaching }
            return
        }
        if distance < 0.08 && pointer.y > 0.46 && pointer.y < 0.64 {
            mood = .petting; charge = 0; return
        }
        if distance < 0.12 && pointer.y > 0.28 && pointer.y < 0.46 && idle > 0.7 {
            mood = .pawing; charge = 0; return
        }
        if pointer.y < 0.65 && distance > 0.08 && distance < 0.42 && cooldown == 0 {
            mood = .stalking; charge += dt
            if charge > 0.85 {
                origin = x; destination = min(0.84, max(0.16, pointer.x))
                progress = 0; charge = 0; mood = .pouncing
            }
        } else { mood = .watching; charge = 0 }
    }
}

final class CatSceneView: NSView {
    var paused = false
    private var timer: Timer?
    private var lastTime = ProcessInfo.processInfo.systemUptime
    private var elapsed = 0.0
    private var motion = CatMotion()
    private var pointer: CGPoint?
    override var isOpaque: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); timer?.invalidate(); timer = nil
        guard window != nil else { return }
        lastTime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    deinit { timer?.invalidate() }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.05, now - lastTime); lastTime = now
        guard !paused, !isHidden, let window = window, window.isVisible,
              window.occlusionState.contains(.visible), bounds.width > 0, bounds.height > 0 else { return }
        let local = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        pointer = bounds.contains(local) ? CGPoint(x: local.x / bounds.width, y: local.y / bounds.height) : nil
        elapsed += dt
        motion.step(dt: dt, pointer: pointer, reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        needsDisplay = true
    }
    private func fill(_ color: NSColor, _ rect: NSRect, radius: CGFloat = 0) {
        color.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
    private func oval(_ color: NSColor, _ rect: NSRect) { color.setFill(); NSBezierPath(ovalIn: rect).fill() }
    private func stroke(_ color: NSColor, width: CGFloat, points: [CGPoint]) {
        guard let first = points.first else { return }
        let path = NSBezierPath(); path.move(to: first)
        for p in points.dropFirst() { path.line(to: p) }
        path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        color.setStroke(); path.stroke()
    }
    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, h = bounds.height
        NSGradient(colors: [NSColor(srgbRed: 0.83, green: 0.86, blue: 0.88, alpha: 1), NSColor(srgbRed: 0.96, green: 0.94, blue: 0.90, alpha: 1)])!.draw(in: bounds, angle: 90)
        let pane = NSRect(x: w * 0.12, y: h * 0.3, width: w * 0.76, height: h * 0.8)
        fill(NSColor(srgbRed: 0.64, green: 0.76, blue: 0.79, alpha: 1), pane, radius: 8)
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: pane).addClip()
        for i in 0..<9 {
            let x = CGFloat(i) * w * 0.13 - w * 0.03
            let height = h * (0.13 + CGFloat((i * 7) % 5) * 0.035)
            fill(NSColor(srgbRed: 0.45, green: 0.61, blue: 0.64, alpha: 0.25), NSRect(x: x, y: h * 0.3, width: w * 0.085, height: height), radius: 3)
        }
        NSGraphicsContext.restoreGraphicsState()
        let frameColor = NSColor(srgbRed: 0.94, green: 0.93, blue: 0.89, alpha: 1)
        fill(frameColor, NSRect(x: w * 0.49, y: h * 0.3, width: w * 0.018, height: h))
        fill(frameColor, NSRect(x: w * 0.12, y: h * 0.73, width: w * 0.76, height: h * 0.017))
        fill(NSColor(srgbRed: 0.78, green: 0.78, blue: 0.73, alpha: 1), NSRect(x: 0, y: 0, width: w, height: h * 0.205))
        fill(frameColor, NSRect(x: 0, y: h * 0.205, width: w, height: h * 0.09))
        fill(.white.withAlphaComponent(0.55), NSRect(x: 0, y: h * 0.287, width: w, height: h * 0.008))
        drawCat(w: w, h: h)
    }
    private func drawCat(w: CGFloat, h: CGFloat) {
        let scale = min(w / 900, h / 580), x = motion.x * w, y = (0.25 + motion.jump) * h
        oval(.black.withAlphaComponent(0.09 - motion.jump * 0.3), NSRect(x: x - 100 * scale, y: h * 0.25 - 8 * scale, width: 200 * scale, height: 20 * scale))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.translateBy(x: x, y: y)
        NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let sleeping = motion.mood == .resting
        let petting = motion.mood == .petting
        let crouch: CGFloat = motion.mood == .stalking ? 0.82 : (sleeping ? 0.75 : 1 - motion.downwardReach * 0.20)
        NSGraphicsContext.current?.cgContext.scaleBy(x: 1, y: crouch)
        let fur = NSColor(srgbRed: 0.26, green: 0.30, blue: 0.33, alpha: 1)
        let lightFur = NSColor(srgbRed: 0.36, green: 0.40, blue: 0.42, alpha: 1)
        let cream = NSColor(srgbRed: 0.92, green: 0.91, blue: 0.86, alpha: 1)
        let tail = NSBezierPath(); tail.move(to: CGPoint(x: 48, y: 30))
        let swish: CGFloat = reduced ? 0 : CGFloat(sin(elapsed * (motion.mood == .stalking ? 7 : 1.8))) * 13
        tail.curve(to: CGPoint(x: 121, y: 72 + swish), controlPoint1: CGPoint(x: 123, y: -5), controlPoint2: CGPoint(x: 143, y: 32))
        tail.lineWidth = 21; tail.lineCapStyle = .round; fur.setStroke(); tail.stroke()
        oval(fur, NSRect(x: -62, y: 4, width: 125, height: 132))
        oval(lightFur, NSRect(x: -48, y: 7, width: 42, height: 72))
        oval(cream, NSRect(x: -25, y: 8, width: 51, height: 88))
        let reachingSide: CGFloat = (pointer?.x ?? motion.x) < motion.x ? -1 : 1
        for side: CGFloat in [-1, 1] {
            let amount = side == reachingSide ? motion.downwardReach : 0
            let shoulder = CGPoint(x: side * 29, y: 55)
            let aim = min(32, max(-32, ((pointer?.x ?? motion.x) - motion.x) * w / max(0.01, scale)))
            let depth = min(75, max(38, (0.25 - (pointer?.y ?? 0.25)) * h / max(0.01, scale)))
            let wiggle: CGFloat = reduced ? 0 : CGFloat(sin(elapsed * 3.5)) * 3 * amount
            let paw = CGPoint(x: side * 29 + aim * amount, y: 9 - depth * amount + wiggle)
            let arm = NSBezierPath(); arm.move(to: shoulder)
            arm.curve(to: paw, controlPoint1: CGPoint(x: shoulder.x + side * 8, y: 30),
                      controlPoint2: CGPoint(x: paw.x + side * 9, y: paw.y + 24))
            arm.lineWidth = 27; arm.lineCapStyle = .round; fur.setStroke(); arm.stroke()
            oval(cream, NSRect(x: paw.x - 18, y: paw.y - 10, width: 36, height: 21))
        }
        if motion.mood == .pawing || motion.mood == .pouncing {
            let side: CGFloat = (pointer?.x ?? motion.x) < motion.x ? -1 : 1
            let reach: CGFloat = reduced ? 32 : 32 + CGFloat(sin(elapsed * 5)) * 7
            stroke(fur, width: 25, points: [CGPoint(x: side * 30, y: 62), CGPoint(x: side * 56, y: 62 + reach)])
            oval(cream, NSRect(x: side * 56 - 14, y: 50 + reach, width: 28, height: 23))
        }
        let lookX: CGFloat = sleeping ? 0 : min(9, max(-9, ((pointer?.x ?? motion.x) - motion.x) * 35))
        let lookY: CGFloat = motion.downwardReach > 0.01 ? -22 * motion.downwardReach : petting ? 8 : sleeping ? -6 : min(7, max(-5, ((pointer?.y ?? 0.4) - 0.45) * 22))
        NSGraphicsContext.current?.cgContext.translateBy(x: lookX, y: lookY)
        for side: CGFloat in [-1, 1] {
            let ear = NSBezierPath(); ear.move(to: CGPoint(x: side * 51, y: 137))
            ear.line(to: CGPoint(x: side * 53, y: 190)); ear.line(to: CGPoint(x: side * 14, y: 160)); ear.close(); fur.setFill(); ear.fill()
            let inner = NSBezierPath(); inner.move(to: CGPoint(x: side * 44, y: 151))
            inner.line(to: CGPoint(x: side * 46, y: 178)); inner.line(to: CGPoint(x: side * 26, y: 161)); inner.close()
            NSColor(srgbRed: 0.68, green: 0.51, blue: 0.50, alpha: 1).setFill(); inner.fill()
        }
        oval(fur, NSRect(x: -59, y: 91, width: 118, height: 86))
        let blink = !reduced && elapsed.truncatingRemainder(dividingBy: 5.7) < 0.14
        for side: CGFloat in [-1, 1] {
            let ex = side * 26
            if sleeping || petting || blink {
                stroke(cream, width: 2.5, points: [CGPoint(x: ex - 10, y: 136), CGPoint(x: ex, y: 132), CGPoint(x: ex + 10, y: 136)])
            } else {
                oval(NSColor(srgbRed: 0.76, green: 0.80, blue: 0.53, alpha: 1), NSRect(x: ex - 12, y: 125, width: 24, height: 23))
                oval(NSColor(srgbRed: 0.09, green: 0.14, blue: 0.15, alpha: 1), NSRect(x: ex - 4 + lookX * 0.45, y: 128 + lookY * 0.3, width: 8, height: 18))
                oval(.white.withAlphaComponent(0.8), NSRect(x: ex - 3, y: 139, width: 4, height: 4))
            }
            oval(cream, NSRect(x: side * 11 - 16, y: 102, width: 32, height: 23))
            for j in 0..<3 {
                stroke(cream.withAlphaComponent(0.8), width: 1, points: [CGPoint(x: side * 29, y: CGFloat(110 + j * 5)), CGPoint(x: side * 75, y: CGFloat(102 + j * 11))])
            }
        }
        let nose = NSBezierPath(); nose.move(to: CGPoint(x: -6, y: 119)); nose.line(to: CGPoint(x: 6, y: 119)); nose.line(to: CGPoint(x: 0, y: 112)); nose.close()
        NSColor(srgbRed: 0.65, green: 0.45, blue: 0.44, alpha: 1).setFill(); nose.fill()
        stroke(fur, width: 1.5, points: [CGPoint(x: 0, y: 112), CGPoint(x: 0, y: 108)])
        NSGraphicsContext.restoreGraphicsState()
        if sleeping {
            for i in 0..<3 {
                let phase = reduced ? Double(i) / 3 : (elapsed * 0.32 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let alpha = reduced ? 0.65 : sin(phase * .pi) * 0.75
                let text = i == 0 ? "Z" : "ZZ"
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: (13 + CGFloat(phase) * 8) * scale, weight: .medium),
                    .foregroundColor: fur.withAlphaComponent(alpha)
                ]
                (text as NSString).draw(at: CGPoint(x: x + (55 + CGFloat(phase) * 32) * scale,
                                                    y: y + (135 + CGFloat(phase) * 65) * scale), withAttributes: attributes)
            }
        }
    }
}

struct CatPreview: NSViewRepresentable {
    var paused: Bool
    func makeNSView(context: Context) -> CatSceneView { CatSceneView(frame: .zero) }
    func updateNSView(_ view: CatSceneView, context: Context) { view.paused = paused }
}
