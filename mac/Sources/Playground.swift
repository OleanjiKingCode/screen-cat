import AppKit

/// A window to play with the cat in. It has its own cat, a row of pretend apps
/// standing at the back, the mode switch, and buttons for each routine. In
/// crawler mode the cat goes along the pretend apps and breaks them.
final class PlaygroundController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var view: PlaygroundView?
    private var modeControl: NSSegmentedControl?
    private let config: Config
    private let onModeChange: (String) -> Void

    var mode: String {
        didSet {
            view?.mode = mode
            modeControl?.selectedSegment = mode == "crawler" ? 1 : 0
        }
    }

    init(config: Config, onModeChange: @escaping (String) -> Void) {
        self.config = config
        self.mode = config.mode
        self.onModeChange = onModeChange
    }

    func show() {
        if window == nil { build() }
        view?.startLoop()
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 640),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "Screen Cat Playground"
        w.minSize = CGSize(width: 700, height: 460)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()

        let root = NSView(frame: w.contentLayoutRect)
        root.autoresizingMask = [.width, .height]
        let barHeight: CGFloat = 48

        let stage = PlaygroundView(frame: CGRect(x: 0, y: 0, width: root.bounds.width,
                                                 height: root.bounds.height - barHeight),
                                   config: config)
        stage.autoresizingMask = [.width, .height]
        stage.mode = mode
        root.addSubview(stage)

        let modes = NSSegmentedControl(labels: ["Normal", "Crawler"], trackingMode: .selectOne,
                                       target: self, action: #selector(modeChanged(_:)))
        modes.selectedSegment = mode == "crawler" ? 1 : 0
        let buttons: [(String, Routine)] = [("Walk", .stroll), ("Nap", .nap), ("Ball", .ball),
                                            ("Feed", .hungry), ("Break the apps", .crawl)]
        var items: [NSView] = [NSTextField(labelWithString: "Mode"), modes]
        for (index, (title, _)) in buttons.enumerated() {
            let b = NSButton(title: title, target: self, action: #selector(runRoutine(_:)))
            b.bezelStyle = .rounded
            b.tag = index
            items.append(b)
        }
        let bar = NSStackView(views: items)
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        bar.frame = CGRect(x: 0, y: root.bounds.height - barHeight, width: root.bounds.width, height: barHeight)
        bar.autoresizingMask = [.width, .minYMargin]
        root.addSubview(bar)

        w.contentView = root
        window = w
        view = stage
        modeControl = modes
        routines = buttons.map(\.1)
    }

    private var routines: [Routine] = []

    @objc private func runRoutine(_ sender: NSButton) {
        guard sender.tag < routines.count else { return }
        view?.start(routines[sender.tag])
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        mode = sender.selectedSegment == 1 ? "crawler" : "normal"
        onModeChange(mode)
    }

    func windowWillClose(_ notification: Notification) { view?.stopLoop() }
}

/// The pretend apps standing along the back of the playground.
enum FakeApp: CaseIterable {
    case terminal, browser, notes, music, files

    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .browser: return "Browser"
        case .notes: return "Notes"
        case .music: return "Music"
        case .files: return "Files"
        }
    }
}

final class PlaygroundView: NSView {
    private let scene = Scene()
    private let sheet: SpriteSheet
    private var behavior: Behavior?
    private var timer: Timer?
    private var lastTick = CFAbsoluteTimeGetCurrent()
    private var restFor: CGFloat = 1
    private var props: [(app: FakeApp, rect: CGRect)] = []
    var mode = "normal"

    init(frame: CGRect, config: Config) {
        var c = config
        // A shallow strip in front of the apps, so the cat stays in front of them.
        c.roamHeight = 0.2
        c.groundBias = 2
        scene.config = c
        sheet = SpriteSheet(resources: resourcesDirectory(), config: c)
        scene.cat.isDog = c.pet == "dog"
        super.init(frame: frame)
        layoutStage()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutStage()
        // The stage moved under the cat, so send it off and start fresh.
        behavior = nil
        scene.cat.visible = false
        scene.ball.visible = false
        restFor = 0.5
    }

    private var floorTop: CGFloat { bounds.height * 0.24 }

    private func layoutStage() {
        scene.cat.size = min(110, max(48, bounds.height / 6.5))
        scene.setStage(surface: .bottom, screen: bounds, catSize: scene.cat.size)
        let apps = FakeApp.allCases
        let gap: CGFloat = 18
        let width = (bounds.width - gap * CGFloat(apps.count + 1)) / CGFloat(apps.count)
        let height = min(bounds.height * 0.62, width * 1.6)
        props = apps.enumerated().map { i, app in
            (app, CGRect(x: gap + CGFloat(i) * (width + gap), y: floorTop, width: width, height: height))
        }
    }

    func startLoop() {
        guard timer == nil else { return }
        lastTick = CFAbsoluteTimeGetCurrent()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopLoop() {
        timer?.invalidate()
        timer = nil
        behavior = nil
        scene.cat.visible = false
    }

    func start(_ routine: Routine) {
        scene.cat.clipTime = 0
        scene.cat.stride = 0
        scene.cat.depth = 1
        scene.ball.visible = false
        scene.crawlTargets = props.map(\.rect)
        scene.cat.wearing = pickOutfit(scene.config)
        if routine == .crawl { scene.cat.wearing.insert(.glasses) }
        behavior = makeBehavior(routine, scene: scene)
        scene.cat.visible = true
    }

    private func tick() {
        let now = CFAbsoluteTimeGetCurrent()
        step(CGFloat(min(0.05, max(0.001, now - lastTick))))
        lastTick = now
    }

    /// One frame of the playground. Also driven directly by `--playground`.
    func step(_ dt: CGFloat) {
        if let behavior {
            scene.cat.advance(dt)
            if behavior.update(dt, scene) {
                self.behavior = nil
                scene.cat.visible = false
                scene.ball.visible = false
                restFor = 1.5
            }
        } else {
            restFor -= dt
            if restFor <= 0 {
                let normal: [Routine] = [.stroll, .stroll, .ball, .hungry, .nap]
                start(mode == "crawler" ? .crawl : normal.randomElement()!)
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSColor(srgbRed: 0.08, green: 0.09, blue: 0.13, alpha: 1).setFill()
        bounds.fill()
        // Dot grid, so it reads as a play area rather than an empty window.
        NSColor(white: 1, alpha: 0.05).setFill()
        var y: CGFloat = 12
        while y < bounds.height {
            var x: CGFloat = 12
            while x < bounds.width {
                CGRect(x: x, y: y, width: 2, height: 2).fill()
                x += 24
            }
            y += 24
        }
        NSColor(srgbRed: 0.13, green: 0.14, blue: 0.2, alpha: 1).setFill()
        CGRect(x: 0, y: 0, width: bounds.width, height: floorTop).fill()

        for prop in props { drawFakeApp(prop.app, in: prop.rect) }

        let crawl = behavior as? BreachSource
        for breach in crawl?.breaches ?? [] { drawBreach(breach, in: ctx) }
        let palette = scene.config.extras
        if let bowl = (behavior as? HungryBehavior)?.bowlAt {
            drawFoodBowl(at: bowl, pixel: scene.cat.pixelScale, palette: palette, alpha: 1, in: ctx)
        }
        if scene.ball.visible { drawBall(scene.ball, sheet: sheet, in: ctx) }
        if scene.cat.visible {
            drawCat(scene.cat, sheet: sheet, drawShadow: scene.config.shadow, palette: palette, in: ctx)
        }
        if let zap = crawl?.zap { drawZap(zap, in: ctx) }

        let label = mode == "crawler" ? "CRAWLER MODE" : "NORMAL MODE"
        PixelFont.draw(label, at: CGPoint(x: 16, y: bounds.height - 30), pixel: 2,
                       color: mode == "crawler" ? NSColor(srgbRed: 0.22, green: 1, blue: 0.48, alpha: 1)
                                                : NSColor(white: 1, alpha: 0.5),
                       in: ctx)
    }

    // MARK: - Pretend apps

    private func drawFakeApp(_ app: FakeApp, in r: CGRect) {
        let dark = app == .terminal || app == .music
        let body: NSColor = {
            switch app {
            case .terminal: return NSColor(srgbRed: 0.05, green: 0.07, blue: 0.09, alpha: 1)
            case .music: return NSColor(srgbRed: 0.2, green: 0.12, blue: 0.3, alpha: 1)
            case .notes: return NSColor(srgbRed: 1, green: 0.96, blue: 0.78, alpha: 1)
            default: return NSColor(white: 0.96, alpha: 1)
            }
        }()
        let shape = NSBezierPath(roundedRect: r, xRadius: 9, yRadius: 9)
        body.setFill()
        shape.fill()
        NSColor(white: 0, alpha: 0.4).setStroke()
        shape.lineWidth = 1
        shape.stroke()

        // Title bar with the three window buttons.
        let bar = CGRect(x: r.minX, y: r.maxY - 24, width: r.width, height: 24)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        (dark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.06)).setFill()
        bar.fill()
        NSGraphicsContext.restoreGraphicsState()
        for (i, colour) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            colour.setFill()
            NSBezierPath(ovalIn: CGRect(x: r.minX + 10 + CGFloat(i) * 16, y: bar.midY - 5, width: 10, height: 10)).fill()
        }
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: dark ? NSColor(white: 1, alpha: 0.7) : NSColor(white: 0, alpha: 0.6),
        ]
        let title = NSString(string: app.title)
        let size = title.size(withAttributes: titleAttrs)
        title.draw(at: CGPoint(x: bar.midX - size.width / 2, y: bar.midY - size.height / 2), withAttributes: titleAttrs)

        let inner = CGRect(x: r.minX + 12, y: r.minY + 12, width: r.width - 24, height: r.height - 48)
        switch app {
        case .terminal:
            lines(["$ npm run dev", "> ready on :3000", "$ git status", "nothing to commit", "$ _"],
                  in: inner, colour: NSColor(srgbRed: 0.4, green: 0.95, blue: 0.55, alpha: 1), mono: true)
        case .notes:
            lines(["Buy cat food", "Fix the bug", "Pet the cat", "Call mum"],
                  in: inner, colour: NSColor(white: 0.25, alpha: 1), mono: false)
        case .browser:
            NSColor(white: 0.88, alpha: 1).setFill()
            NSBezierPath(roundedRect: CGRect(x: inner.minX, y: inner.maxY - 16, width: inner.width, height: 16),
                         xRadius: 8, yRadius: 8).fill()
            NSColor(srgbRed: 0.66, green: 0.48, blue: 0.88, alpha: 0.5).setFill()
            CGRect(x: inner.minX, y: inner.maxY - 26 - inner.height * 0.35, width: inner.width,
                   height: inner.height * 0.35).fill()
            NSColor(white: 0.85, alpha: 1).setFill()
            let cardW = (inner.width - 16) / 3
            for i in 0..<3 {
                CGRect(x: inner.minX + CGFloat(i) * (cardW + 8), y: inner.minY,
                       width: cardW, height: inner.height * 0.35).fill()
            }
        case .music:
            let art = min(inner.width * 0.6, inner.height * 0.6)
            NSGradient(starting: .systemPink, ending: .systemPurple)?
                .draw(in: CGRect(x: inner.midX - art / 2, y: inner.maxY - art, width: art, height: art), angle: 45)
            lines(["Lo-fi Purrs"], in: CGRect(x: inner.minX, y: inner.minY + 10, width: inner.width, height: 20),
                  colour: NSColor(white: 1, alpha: 0.8), mono: false)
            NSColor(white: 1, alpha: 0.25).setFill()
            CGRect(x: inner.minX, y: inner.minY + 2, width: inner.width, height: 3).fill()
            NSColor(white: 1, alpha: 0.9).setFill()
            CGRect(x: inner.minX, y: inner.minY + 2, width: inner.width * 0.4, height: 3).fill()
        case .files:
            let cols = 3
            let cell = inner.width / CGFloat(cols)
            for i in 0..<6 {
                let x = inner.minX + CGFloat(i % cols) * cell + cell * 0.2
                let y = inner.maxY - CGFloat(i / cols + 1) * cell * 0.8
                NSColor.systemBlue.withAlphaComponent(0.75).setFill()
                NSBezierPath(roundedRect: CGRect(x: x, y: y, width: cell * 0.6, height: cell * 0.42),
                             xRadius: 3, yRadius: 3).fill()
                CGRect(x: x, y: y + cell * 0.42 - 2, width: cell * 0.25, height: 6).fill()
            }
        }
    }

    private func lines(_ text: [String], in r: CGRect, colour: NSColor, mono: Bool) {
        let font = mono ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                        : NSFont.systemFont(ofSize: 12, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        for (i, line) in text.enumerated() {
            let y = r.maxY - CGFloat(i + 1) * 17
            guard y >= r.minY else { break }
            NSString(string: line).draw(at: CGPoint(x: r.minX, y: y), withAttributes: attrs)
        }
    }
}
