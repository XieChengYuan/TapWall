import AppKit
import SceneKit
import simd
import Metal

struct IconPose {
    var position: SIMD3<Float>
    var rotation: simd_quatf
    static func mix(_ a: Self, _ b: Self, _ t: Float) -> Self {
        Self(position: a.position + (b.position - a.position) * t, rotation: simd_slerp(a.rotation, b.rotation, t))
    }
}

/// Physics is baked once in simulation time. Playback samples the whole result,
/// so even a short video interval includes the complete fall and settlement.
final class SpatialIcons: SCNView {
    private let world = SCNScene()
    private var tiles: [SCNNode] = []
    private var items: [IconItem] = []
    private var homes: [IconPose] = []
    private(set) var frames: [[IconPose]] = []
    private var draggedTile: SCNNode?
    private var dragDepth: Float = 0
    private var timer: Timer?
    var visiblePoses: [IconPose] { tiles.map { IconPose(position: $0.simdPosition, rotation: $0.simdOrientation) } }
    private var bakeKey = ""
    var arrangement: IconArrangement = .vertical
    var edge: IconEdge = .right
    var dropMode: DropMode = .shake
    var returnMode: ReturnMode = .glide
    var onOpen: ((URL) -> Void)?
    var onEscape: (() -> Void)?
    var onToggle: (() -> Void)?
    private let cameraNode = SCNNode()
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override init(frame: NSRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        scene = world; backgroundColor = .clear
        wantsLayer = true; layer?.isOpaque = false
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 60
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.camera?.zNear = 1; cameraNode.camera?.zFar = 5000
        world.rootNode.addChildNode(cameraNode); pointOfView = cameraNode
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 650; world.rootNode.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional
        key.light?.intensity = 1050; key.eulerAngles = SCNVector3(-0.5, -0.5, 0)
        world.rootNode.addChildNode(key)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        cameraNode.position = SCNVector3(Float(bounds.width / 2), Float(bounds.height / 2), 1500)
        cameraNode.camera?.orthographicScale = Double(bounds.height / 2)
        if !items.isEmpty { configure(items: items) }
    }
    func configure(items: [IconItem]) {
        stop()
        let key = "\(bounds.size)-\(arrangement)-\(edge)-\(dropMode)-" + items.map { $0.url.path }.joined(separator: "|")
        guard key != bakeKey else { return }
        bakeKey = key; self.items = items
        tiles.forEach { $0.removeFromParentNode() }; tiles = []
        homes = homePositions(count: items.count, size: bounds.size, arrangement: arrangement, edge: edge).map {
            IconPose(position: SIMD3(Float($0.x), Float($0.y), 0), rotation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)))
        }
        for item in items {
            let box = SCNBox(width: 64, height: 64, length: 6, chamferRadius: 2)
            let face = SCNMaterial(); face.diffuse.contents = item.image
            face.lightingModel = .constant; face.diffuse.minificationFilter = .linear; face.diffuse.magnificationFilter = .linear
            face.isDoubleSided = true
            let side = SCNMaterial(); side.diffuse.contents = NSColor(calibratedWhite: 0.22, alpha: 1)
            side.lightingModel = .lambert; side.specular.contents = NSColor.black
            box.materials = [face, side, face, side, side, side]
            let tile = SCNNode(geometry: box); world.rootNode.addChildNode(tile); tiles.append(tile)
        }
        bake()
        apply(homes)
    }
    private func bake() {
        frames = [homes]
        guard !homes.isEmpty else { return }
        let simulation = SCNScene()
        simulation.physicsWorld.gravity = SCNVector3(0, -980, 0)
        simulation.physicsWorld.timeStep = 1.0 / 120
        func barrier(_ size: SCNVector3, _ position: SCNVector3) {
            let node = SCNNode(geometry: SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: 0))
            node.position = position; node.physicsBody = SCNPhysicsBody.static()
            simulation.rootNode.addChildNode(node)
        }
        let w = Float(bounds.width)
        // Collision boundaries exist only in the simulation, never in the visible scene.
        barrier(SCNVector3(w + 200, 40, 400), SCNVector3(w / 2, 0, 0))
        barrier(SCNVector3(40, 4000, 400), SCNVector3(-10, 1000, 0))
        barrier(SCNVector3(40, 4000, 400), SCNVector3(w + 10, 1000, 0))
        barrier(SCNVector3(w + 200, 4000, 20), SCNVector3(w / 2, 1000, -90))
        barrier(SCNVector3(w + 200, 4000, 20), SCNVector3(w / 2, 1000, 90))
        var bodies: [SCNNode] = []
        for (i, home) in homes.enumerated() {
            let node = SCNNode(geometry: SCNBox(width: 64, height: 64, length: 6, chamferRadius: 2))
            node.simdPosition = home.position
            let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: node.geometry!, options: nil))
            body.mass = 1; body.friction = 0.85; body.restitution = 0.12
            body.damping = 0.3; body.angularDamping = 0.65
            body.continuousCollisionDetectionThreshold = 4
            node.physicsBody = body; simulation.rootNode.addChildNode(node)
            let sign: Float = edge == .right ? -1 : 1
            let varied = Float((i * 37 % 101)) / 100
            var vx = sign * (35 + varied * 75), vy: Float = 15, vz = (varied - 0.5) * 70
            switch dropMode {
            case .freefall: vx *= 0.15; vy = 0
            case .shake: vy = 80 + varied * 70
            case .wind: vx = sign * (200 + varied * 140)
            case .vortex: vx = sign * (140 + sin(Float(i)) * 80); vz *= 2; vy = 90
            case .burst: vx = sign * (200 + varied * 200); vy = 180
            }
            body.velocity = SCNVector3(vx, vy, vz)
            body.angularVelocity = SCNVector4(0.7, 0.35, (i % 2 == 0 ? 0.4 : -0.4), 2.2 + varied)
            bodies.append(node)
        }
        let device = MTLCreateSystemDefaultDevice()!
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = simulation
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.position = SCNVector3(w / 2, 300, 1500)
        simulation.rootNode.addChildNode(camera); renderer.pointOfView = camera
        let queue = device.makeCommandQueue()!
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 8, height: 8, mipmapped: false)
        descriptor.usage = [.renderTarget]; descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)!
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 8, height: 8, mipmapped: false)
        depthDescriptor.usage = [.renderTarget]; depthDescriptor.storageMode = .private
        let depth = device.makeTexture(descriptor: depthDescriptor)!
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture; pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .dontCare
        pass.depthAttachment.texture = depth; pass.depthAttachment.loadAction = .clear; pass.depthAttachment.storeAction = .dontCare; pass.depthAttachment.clearDepth = 1
        func tick(_ time: Double) {
            let command = queue.makeCommandBuffer()!
            renderer.render(atTime: time, viewport: CGRect(x: 0, y: 0, width: 8, height: 8), commandBuffer: command, passDescriptor: pass)
            command.commit(); command.waitUntilCompleted()
        }
        tick(0)
        var quiet = 0
        // Continue until settled, instead of truncating at the user's video duration.
        for step in 1...1800 {
            tick(Double(step) / 120)
            if step % 2 == 0 {
                let poses = bodies.map { IconPose(position: $0.presentation.simdPosition, rotation: $0.presentation.simdOrientation) }
                frames.append(poses)
                let previous = frames[frames.count - 2]
                let stable = zip(previous, poses).allSatisfy { simd_distance($0.position, $1.position) < 0.07 && abs(simd_dot($0.rotation.vector, $1.rotation.vector)) > 0.9999 }
                quiet = stable && step > 360 ? quiet + 1 : 0
                if quiet > 45 { break }
            }
        }
    }
    private func apply(_ poses: [IconPose]) {
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0; SCNTransaction.disableActions = true
        for (node, pose) in zip(tiles, poses) { node.simdPosition = pose.position; node.simdOrientation = pose.rotation }
        SCNTransaction.commit()
        needsDisplay = true
    }
    func dropPose(_ progress: Double) -> [IconPose] {
        guard frames.count > 1 else { return homes }
        let cursor = min(1, max(0, progress)) * Double(frames.count - 1)
        let lower = Int(cursor), upper = min(frames.count - 1, lower + 1)
        return zip(frames[lower], frames[upper]).map { IconPose.mix($0, $1, Float(cursor - Double(lower))) }
    }
    private func returning(from start: [IconPose], progress: Double) -> [IconPose] {
        zip(start, homes).enumerated().map { index, pair in
            var t = Float(min(1, max(0, progress)))
            if returnMode == .instant || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { t = 1 }
            if returnMode == .cascade { t = min(1, max(0, (t - Float(index) / Float(max(1, homes.count - 1)) * 0.4) / 0.6)) }
            if t >= 1 { return pair.1 }
            let eased = t * t * (3 - 2 * t)
            let p = returnMode == .spring ? 1 - exp(-7 * t) * cos(10 * t) : eased
            var pose = IconPose.mix(pair.0, pair.1, eased)
            pose.position = pair.0.position + (pair.1.position - pair.0.position) * p
            if returnMode == .arc { pose.position.y += sin(.pi * t) * 100; pose.position.z += sin(.pi * t) * 80 }
            return pose
        }
    }
    func sample(time: Double, schedule: CueSchedule) {
        stop()
        if time < schedule.drop { apply(homes) }
        else if time < schedule.dropEnd { apply(dropPose((time - schedule.drop) / max(0.001, schedule.dropEnd - schedule.drop))) }
        else if time < schedule.restore { apply(dropPose(1)) }
        else if time < schedule.restoreEnd { apply(returning(from: dropPose(1), progress: (time - schedule.restore) / max(0.001, schedule.restoreEnd - schedule.restore))) }
        else { apply(homes) }
    }
    func scatter(interval: Double = 2) { animate(duration: interval) { [weak self] t in self?.apply(self?.dropPose(t) ?? []) } }
    func restore(animated: Bool, interval: Double = 0.8) {
        let start = tiles.map { IconPose(position: $0.simdPosition, rotation: $0.simdOrientation) }
        if !animated { stop(); apply(homes); return }
        animate(duration: interval) { [weak self] t in guard let self = self else { return }; self.apply(self.returning(from: start, progress: t)) }
    }
    private func animate(duration: Double, update: @escaping (Double) -> Void) {
        stop(); let start = ProcessInfo.processInfo.systemUptime
        update(0)
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            let t = min(1, (ProcessInfo.processInfo.systemUptime - start) / max(0.01, duration))
            update(t); if t >= 1 { self?.stop() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func stop() { timer?.invalidate(); timer = nil }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let index = index(at: event) else { return }
        if event.clickCount == 2 { onOpen?(items[index].url); return }
        stop(); draggedTile = tiles[index]; dragDepth = Float(projectPoint(tiles[index].position).z)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let tile = draggedTile else { return }
        let point = convert(event.locationInWindow, from: nil)
        tile.position = unprojectPoint(SCNVector3(Float(point.x), Float(point.y), dragDepth))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        draggedTile = nil
    }
    private func index(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return hitTest(point, options: nil).compactMap { hit in tiles.firstIndex(where: { $0 === hit.node }) }.first
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let index = index(at: event) else { return }
        let menu = NSMenu(); let item = NSMenuItem(title: "在 Finder 中显示", action: #selector(reveal(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = items[index].url; menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func reveal(_ sender: NSMenuItem) { if let url = sender.representedObject as? URL { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?(); return }
        switch event.charactersIgnoringModifiers?.lowercased() { case " ": scatter(); case "r": restore(animated: true); case "d": onToggle?(); default: super.keyDown(with: event) }
    }
}
