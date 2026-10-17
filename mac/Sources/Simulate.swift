import AppKit

/// Runs a routine offscreen through the real window and view, then writes a PNG
/// showing where the cat was at evenly spaced moments. This exercises the same
/// draw path and the same global-screen-to-view mapping the live app uses, so it
/// catches coordinate and behaviour bugs without needing a screen recording.
func runSimulation(routine: Routine, to path: String) {
    let cfg = Config.load()
    let stage = CGRect(x: 0, y: 0, width: 1512, height: 982)

    let surface: Surface = {
        if let i = CommandLine.arguments.firstIndex(of: "--surface"), i + 1 < CommandLine.arguments.count {
            switch CommandLine.arguments[i + 1] {
            case "left": return .left
            case "right": return .right
            default: return .bottom
            }
        }
        return .bottom
    }()

    let scene = Scene()
    scene.config = cfg
    scene.cat.size = max(24, stage.height / cfg.sizeDivisor)
    scene.setStage(surface: surface, screen: stage, catSize: scene.cat.size)

    let window = makeOverlayWindow(frame: stage)
    let view = OverlayView(frame: CGRect(origin: .zero, size: stage.size))
    view.scene = scene
    view.sheet = SpriteSheet(resources: resourcesDirectory(), config: cfg)
    view.extras = cfg.extras
    view.drawShadows = cfg.shadow
    window.contentView = view
    guard view.sheet?.isLoaded == true else {
        print("could not load sprites from \(resourcesDirectory().path)"); return
    }

    // A synthetic pointer so the follow phase can be exercised and measured
    // without a hand on the mouse. It parks high on the screen, which is the
    // case that used to look like levitating.
    var pointerClock: CGFloat = 0
    if CommandLine.arguments.contains("--accept") {
        PlayBehavior.pointerSource = {
            let t = pointerClock
            return CGPoint(x: stage.midX + sin(t * 0.7) * stage.width * 0.38,
                           y: stage.minY + stage.height * (0.5 + 0.42 * sin(t * 0.31)))
        }
    }

    // Stand-in windows for crawler mode.
    let fakeWindows = [CGRect(x: 120, y: 300, width: 520, height: 380),
                       CGRect(x: 820, y: 220, width: 560, height: 520)]
    scene.crawlTargets = fakeWindows
    let behavior = makeBehavior(routine, scene: scene)
    scene.cat.visible = true

    // Step the routine, snapshotting at regular intervals.
    let dt: CGFloat = 1.0 / 60.0
    // The idle crawl never ends by itself, so it gets a fixed slice.
    let maxSeconds: CGFloat = routine == .idleCrawl ? 40 : 320
    var elapsed: CGFloat = 0
    var finished = false
    var snapshots: [NSBitmapImageRep] = []
    let wantSnapshots = 8
    var nextSnapshotAt: CGFloat = 0
    var snapshotEvery: CGFloat = 1.0

    var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
    var minY = CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
    var clipsSeen: [String] = []
    var frames = 0
    var steepest: CGFloat = 0
    var minDepth: CGFloat = .greatestFiniteMagnitude
    var maxDepth: CGFloat = 0

    // First pass: how long does the routine take?
    let probeScene = Scene()
    probeScene.config = cfg
    probeScene.cat.size = scene.cat.size
    probeScene.setStage(surface: surface, screen: stage, catSize: scene.cat.size)
    probeScene.applyDepth()
    probeScene.crawlTargets = fakeWindows
    let probe = makeBehavior(routine, scene: probeScene)
    var probeTime: CGFloat = 0
    while probeTime < maxSeconds {
        if CommandLine.arguments.contains("--accept") {
            (probe as? PlayBehavior)?.pointerResting = true
        }
        probeScene.cat.advance(dt)
        if probe.update(dt, probeScene) { break }
        probeTime += dt
    }
    snapshotEvery = max(0.2, probeTime / CGFloat(wantSnapshots - 1))
    print("surface: \(surface)")
    print("routine \(routine.rawValue): lasts \(String(format: "%.1f", probeTime))s")

    while elapsed < maxSeconds {
        // --accept pretends the pointer is resting on the invite, so the dwell
        // completes and the follow phase can be exercised headlessly.
        if CommandLine.arguments.contains("--accept") {
            (behavior as? PlayBehavior)?.pointerResting = true
        }
        let before = scene.cat.pos
        pointerClock += dt
        scene.cat.advance(dt)
        finished = behavior.update(dt, scene)
        frames += 1

        // Measure how steeply the cat ever travels, and how much it scales.
        let moveX = abs(scene.cat.pos.x - before.x)
        let moveY = abs(scene.cat.pos.y - before.y)
        if moveY > 0.01 {
            let slope = moveX > 0.0001 ? moveY / moveX : .greatestFiniteMagnitude
            steepest = max(steepest, slope)
        }
        minDepth = min(minDepth, scene.cat.depth)
        maxDepth = max(maxDepth, scene.cat.depth)

        minX = min(minX, scene.cat.pos.x); maxX = max(maxX, scene.cat.pos.x)
        minY = min(minY, scene.cat.pos.y); maxY = max(maxY, scene.cat.pos.y)
        let name = String(describing: scene.cat.clip)
        if clipsSeen.last != name { clipsSeen.append(name) }
        view.bowlAt = (behavior as? HungryBehavior)?.bowlAt
        view.breaches = (behavior as? BreachSource)?.breaches ?? []
        view.zap = (behavior as? BreachSource)?.zap
        view.aura = (behavior as? BreachSource)?.aura

        if elapsed >= nextSnapshotAt && snapshots.count < wantSnapshots {
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                snapshots.append(rep)
            }
            nextSnapshotAt += snapshotEvery
        }
        if finished { break }
        elapsed += dt
    }

    print("  finished=\(finished) after \(String(format: "%.1f", elapsed))s (\(frames) frames)")
    print("  clips: \(clipsSeen.joined(separator: " -> "))")
    print("  x \(Int(minX))...\(Int(maxX)) (stage 0...\(Int(stage.width)))")
    print("  y \(Int(minY))...\(Int(maxY)) (stage 0...\(Int(stage.height)))")
    print("  cat size \(Int(scene.cat.size))pt, snapshots \(snapshots.count)")
    print("  steepest move: \(String(format: "%.2f", steepest)) rise/run (cap \(cfg.maxSlope))")
    print("  scale range:   \(String(format: "%.2f", minDepth))...\(String(format: "%.2f", maxDepth))")
    print("  vertical: rises above start? see y range vs entry")

    // Composite the snapshots onto one dark board.
    let scale: CGFloat = 0.5
    let board = CGSize(width: stage.width * scale, height: stage.height * scale)
    guard let out = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: Int(board.width), pixelsHigh: Int(board.height),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let gctx = NSGraphicsContext(bitmapImageRep: out) else { return }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    NSColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1).setFill()
    NSBezierPath(rect: CGRect(origin: .zero, size: board)).fill()
    NSColor(white: 1, alpha: 0.1).setStroke()
    let border = NSBezierPath(rect: CGRect(x: 1, y: 1, width: board.width - 2, height: board.height - 2))
    border.lineWidth = 2
    border.stroke()

    for (i, rep) in snapshots.enumerated() {
        let img = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        img.addRepresentation(rep)
        let fade = 0.28 + 0.72 * CGFloat(i) / CGFloat(max(1, snapshots.count - 1))
        img.draw(in: CGRect(origin: .zero, size: board),
                 from: .zero, operation: .sourceOver, fraction: fade)
    }
    NSString(string: "\(routine.rawValue): \(snapshots.count) moments, oldest faintest")
        .draw(at: CGPoint(x: 12, y: 10),
              withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                               .foregroundColor: NSColor(white: 1, alpha: 0.5)])
    NSGraphicsContext.restoreGraphicsState()

    if let data = out.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
        print("  wrote \(path)")
    }
}
