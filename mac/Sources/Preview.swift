import AppKit

/// Renders a contact sheet of every clip so the recoloured art can be checked
/// at a glance. Not used at runtime.
func renderPreviewSheet(to path: String) {
    let cfg = Config.load()
    let sheet = SpriteSheet(resources: resourcesDirectory(), palette: cfg.spritePalette)
    guard sheet.isLoaded else {
        FileHandle.standardError.write(Data("could not load sprites from \(resourcesDirectory().path)\n".utf8))
        return
    }

    struct Row { var clip: Clip; var label: String; var facing: CGFloat }
    let rows: [Row] = [
        Row(clip: .sideWalk,  label: "side walk (right)", facing: 1),
        Row(clip: .sideWalk,  label: "side walk (left)",  facing: -1),
        Row(clip: .frontWalk, label: "front walk",        facing: 1),
        Row(clip: .run,       label: "run",               facing: 1),
        Row(clip: .sitIdle,   label: "sit / beg",         facing: 1),
        Row(clip: .standIdle, label: "stand",             facing: 1),
        Row(clip: .lieDown,   label: "lie down",          facing: 1),
        Row(clip: .sleep,     label: "sleep + z's",       facing: 1),
        Row(clip: .ballPlay,  label: "ball play",         facing: 1),
    ]

    let size: CGFloat = 96                     // standing cat height, points
    let cell = CGSize(width: 118, height: 132)
    let bubbleStrip: CGFloat = 150
    let cols = rows.map { $0.clip.info.count }.max() ?? 11
    let labelW: CGFloat = 150
    let board = CGSize(width: labelW + cell.width * CGFloat(cols),
                       height: cell.height * CGFloat(rows.count) + bubbleStrip)

    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: Int(board.width), pixelsHigh: Int(board.height),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let gctx = NSGraphicsContext(bitmapImageRep: rep) else { return }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext
    NSColor(srgbRed: 0.15, green: 0.16, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(rect: CGRect(origin: .zero, size: board)).fill()

    for (r, row) in rows.enumerated() {
        let oy = board.height - CGFloat(r + 1) * cell.height
        NSColor(white: 1, alpha: r % 2 == 0 ? 0.05 : 0.02).setFill()
        NSBezierPath(rect: CGRect(x: 0, y: oy, width: board.width, height: cell.height)).fill()
        NSString(string: row.label).draw(
            at: CGPoint(x: 12, y: oy + cell.height / 2 - 8),
            withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                             .foregroundColor: NSColor(white: 1, alpha: 0.7)])

        for f in 0..<row.clip.info.count {
            let ox = labelW + CGFloat(f) * cell.width
            NSColor(white: 1, alpha: 0.13).setFill()
            NSBezierPath(rect: CGRect(x: ox + 10, y: oy + 26, width: cell.width - 20, height: 1)).fill()

            let cat = CatState()
            cat.size = size
            cat.clip = row.clip
            cat.facing = row.facing
            cat.visible = true
            if CommandLine.arguments.contains("--outfit") { cat.wearing = Set(Accessory.allCases) }
            // Drive the frame directly by feeding the clock or the stride.
            let info = row.clip.info
            if info.strideDriven {
                cat.stride = (CGFloat(f) + 0.01) / CGFloat(info.count) * cat.cycleDistance
            } else {
                cat.clipTime = (CGFloat(f) + 0.01) / info.fps
            }
            cat.pos = CGPoint(x: ox + cell.width / 2, y: oy + 27)
            drawCat(cat, sheet: sheet, drawShadow: cfg.shadow, palette: cfg.extras, in: ctx)
        }
    }

    // The play invite, at the real on-screen scale.
    let bubble = SpeechBubble(text: "LET'S PLAY", button: "OK")
    for (i, hover) in [false, true].enumerated() {
        bubble.draw(tipAt: CGPoint(x: labelW + cell.width * CGFloat(3 + i * 3), y: 30),
                    pixel: max(2, (45.0 / 14).rounded()),
                    palette: cfg.extras, hovering: hover, in: ctx)
        NSString(string: hover ? "OK hovered" : "OK normal").draw(
            at: CGPoint(x: labelW + cell.width * CGFloat(3 + i * 3) - 30, y: 6),
            withAttributes: [.font: NSFont.systemFont(ofSize: 11),
                             .foregroundColor: NSColor(white: 1, alpha: 0.55)])
    }

    // Loose ball and food bowl along the bottom strip.
    var ball = BallState()
    ball.size = size * 0.42
    ball.pos = CGPoint(x: labelW * 0.45, y: 34)
    ball.visible = true
    drawBall(ball, sheet: sheet, in: ctx)
    drawFoodBowl(at: CGPoint(x: labelW * 0.8, y: 12), pixel: size / SpriteSheet.standHeight,
                 palette: cfg.extras, alpha: 1, in: ctx)

    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}

/// `--glitches <path.png>`: every crawler glitch style side by side, part way
/// through, each in a different colour.
func renderGlitchSheet(to path: String) {
    let cell = CGSize(width: 420, height: 300)
    let styles = GlitchStyle.allCases
    let board = CGSize(width: cell.width * CGFloat(styles.count) + 20 * CGFloat(styles.count + 1),
                       height: cell.height + 40)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(board.width),
                                     pixelsHigh: Int(board.height), bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let gctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    NSColor(srgbRed: 0.85, green: 0.87, blue: 0.9, alpha: 1).setFill()
    NSBezierPath(rect: CGRect(origin: .zero, size: board)).fill()
    for (i, style) in styles.enumerated() {
        let r = CGRect(x: 20 + CGFloat(i) * (cell.width + 20), y: 20, width: cell.width, height: cell.height)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        var b = Breach(rect: r, touch: CGPoint(x: r.midX, y: r.minY + 30), seed: UInt32(1234 + i * 77),
                       style: style, accentIndex: i)
        b.age = 2.0
        drawBreach(b, in: gctx.cgContext)
    }
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
