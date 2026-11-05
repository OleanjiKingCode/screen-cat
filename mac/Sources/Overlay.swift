import AppKit

/// The view that paints the cat. It lives inside a transparent, click-through
/// window that spans every display.
final class OverlayView: NSView {
    var scene: Scene?
    var sheet: SpriteSheet?
    var extras = Config().extras
    var drawShadows = true
    /// Set by the hungry routine while the bowl should be on the ground.
    var bowlAt: CGPoint?

    /// The play invite, in surface-local coordinates. Nil when nothing is asked.
    var bubbleTip: CGPoint?
    /// The OK button in view coordinates, set as a side effect of drawing it.
    private(set) var okButton: CGRect?
    /// Bubble plus cat: rest the pointer anywhere in here to accept.
    private(set) var acceptArea: CGRect?
    var okHovered = false
    /// 0...1 of the dwell needed to accept, drawn as a fill in the button.
    var dwellProgress: CGFloat = 0
    var onOKClicked: (() -> Void)?
    /// Seconds into a pet, while the cat is being petted. Draws the hearts.
    var petTime: CGFloat?
    /// Crawler mode effects, in surface-local coordinates like the cat.
    var breaches: [Breach] = []
    var zap: Zap?
    var aura: Aura?
    /// What the trash rescue has in its mouth or in the air.
    var carried: CarriedItem?

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    /// Click-through everywhere except the OK button. The window also toggles
    /// `ignoresMouseEvents`, so a click outside the button reaches the app
    /// underneath instead of being swallowed by a transparent overlay.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let okButton, okButton.contains(point) { return self }
        return nil
    }

    /// The app is an accessory and never becomes key, so every click on the
    /// button is a "first mouse" and would otherwise be eaten activating us.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let okButton, okButton.contains(p) { onOKClicked?() }
    }

    /// Set by --selftest to prove whether the paint path actually runs.
    var debugDraw = false
    private(set) var drawCount = 0
    private(set) var drewCatCount = 0

    override func draw(_ dirtyRect: NSRect) {
        drawCount += 1
        guard let scene, let sheet, let ctx = NSGraphicsContext.current?.cgContext else {
            if debugDraw {
                NSLog("Screen Cat: draw bailed: scene=%@ sheet=%@ ctx=%@",
                      self.scene == nil ? "NIL" : "ok",
                      self.sheet == nil ? "NIL" : "ok",
                      NSGraphicsContext.current == nil ? "NIL" : "ok")
            }
            return
        }
        // Two hops. First global screen coordinates -> view coordinates: the
        // window spans every display, so its origin is the offset between the
        // two spaces. Then surface-local coordinates -> global, which is what
        // lets the same walking code run along the bottom or up a side edge.
        let offset = window?.frame.origin ?? .zero
        ctx.saveGState()
        ctx.translateBy(x: -offset.x, y: -offset.y)
        ctx.concatenate(scene.surface.transform(for: scene.screenRect))

        for breach in breaches { drawBreach(breach, in: ctx) }
        if let bowlAt {
            drawFoodBowl(at: bowlAt, pixel: scene.cat.pixelScale,
                         palette: extras, alpha: 1, in: ctx)
        }
        if scene.ball.visible {
            drawBall(scene.ball, sheet: sheet, in: ctx)
        }
        if let tip = bubbleTip, scene.cat.visible {
            let bubble = SpeechBubble(text: "LET'S PLAY", button: "OK")
            let drawn = bubble.draw(tipAt: tip,
                                    pixel: max(2, (scene.cat.size / 14).rounded()),
                                    palette: extras, hovering: okHovered,
                                    progress: dwellProgress, in: ctx)
            // Drawn in local space; remembered in view space so hit testing does
            // not have to redo the transform on every mouse event.
            let toView = { (r: CGRect) in
                r.applying(scene.surface.transform(for: scene.screenRect))
                 .offsetBy(dx: -offset.x, dy: -offset.y)
            }
            okButton = toView(drawn.button)
            acceptArea = toView(drawn.body).union(toView(scene.cat.bounds))
        } else {
            okButton = nil
            acceptArea = nil
        }
        if scene.cat.visible {
            drawCat(scene.cat, sheet: sheet, drawShadow: drawShadows,
                    palette: extras, in: ctx)
            if let carried { drawCarriedItem(carried, palette: extras, in: ctx) }
            if let petTime {
                drawHearts(above: scene.cat, time: petTime, palette: extras, in: ctx)
            }
            if let zap { drawZap(zap, in: ctx) }
            if let aura { drawAura(aura, in: ctx) }
            drewCatCount += 1
            if debugDraw, drewCatCount <= 3 {
                NSLog("Screen Cat: drew cat at %.0f,%.0f into dirty %@ (view %@, offset %@)",
                      scene.cat.pos.x, scene.cat.pos.y, NSStringFromRect(dirtyRect),
                      NSStringFromRect(bounds), NSStringFromPoint(offset))
            }
        }
        ctx.restoreGState()
    }
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

func makeOverlayWindow(frame: CGRect) -> OverlayWindow {
    let w = OverlayWindow(contentRect: frame, styleMask: .borderless,
                          backing: .buffered, defer: false)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.ignoresMouseEvents = true
    w.level = .screenSaver
    // canJoinAllSpaces carries the cat onto every Space, and fullScreenAuxiliary
    // lets it sit over a full-screen app. Without a level above the full-screen
    // window, though, it would still only ever show on the desktop.
    w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    w.isReleasedWhenClosed = false
    w.setFrame(frame, display: false)
    return w
}

/// Named window levels. "top" is the only one that shows over full-screen apps.
func windowLevel(named name: String) -> NSWindow.Level {
    switch name.lowercased() {
    case "floating": return .floating
    case "status":   return .statusBar
    default:         return .screenSaver
    }
}

/// The screen the cat should use: the one the pointer is on, else the main one.
func targetScreen() -> NSScreen {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
}

/// The rectangle that covers every attached display.
func screensUnion() -> CGRect {
    guard var u = NSScreen.screens.first?.frame else { return .zero }
    for s in NSScreen.screens.dropFirst() { u = u.union(s.frame) }
    return u
}

/// Where the sprite files live: inside the .app bundle when built, or next to
/// the sources when running the raw binary.
func resourcesDirectory() -> URL {
    if let r = Bundle.main.resourceURL,
       FileManager.default.fileExists(atPath: r.appendingPathComponent("Cat_Sprite_Sheet.png").path) {
        return r
    }
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    for candidate in [exe.appendingPathComponent("Assets"),
                      exe.appendingPathComponent("../Assets"),
                      URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                          .appendingPathComponent("Assets")] {
        if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Cat_Sprite_Sheet.png").path) {
            return candidate.standardizedFileURL
        }
    }
    return Bundle.main.resourceURL ?? exe
}
