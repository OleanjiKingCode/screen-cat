import AppKit

/// Renders a contact sheet of every clip so the recoloured art can be checked
/// at a glance. Not used at runtime.
func renderPreviewSheet(to path: String) {
    let cfg = Config.load()
    let sheet = SpriteSheet(resources: resourcesDirectory(), config: cfg)
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

/// `--glitches <path.png>`: every takeover look as a crawler breach on a small
/// pretend window, two seconds in, then one of them rebooting.
func renderGlitchSheet(to path: String) {
    let cell = CGSize(width: 300, height: 200)
    let cols = 10
    let count = glitchRecipes.count + 1
    let rowsCount = (count + cols - 1) / cols
    let board = CGSize(width: (cell.width + 12) * CGFloat(cols) + 12, height: (cell.height + 34) * CGFloat(rowsCount) + 12)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(board.width),
                                     pixelsHigh: Int(board.height), bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let gctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    NSColor(srgbRed: 0.85, green: 0.87, blue: 0.9, alpha: 1).setFill()
    NSBezierPath(rect: CGRect(origin: .zero, size: board)).fill()
    for i in 0..<count {
        let col = i % cols, row = i / cols
        let r = CGRect(x: 12 + CGFloat(col) * (cell.width + 12),
                       y: board.height - CGFloat(row + 1) * (cell.height + 34) + 22,
                       width: cell.width, height: cell.height)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        // The last cell reboots a look with its own big banner, the hardest case.
        let rebooting = i == glitchRecipes.count
        let index = rebooting ? glitchRecipes.firstIndex { $0.name == "Red Alert" } ?? 0 : i
        var b = Breach(rect: r, seed: UInt32(1234 + i * 77), recipeIndex: index)
        b.age = rebooting ? b.duration - 0.8 : 2
        drawBreach(b, in: gctx.cgContext)
        let label = "\(index + 1). \(glitchRecipes[index].name)" + (rebooting ? ", rebooting" : "")
        NSString(string: label).draw(at: CGPoint(x: r.minX + 2, y: r.minY - 18),
            withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}

/// `--app-icon <dir.iconset>`: the app icon at every size macOS asks for. The
/// purple cat in its shades and gold chain, sitting on a night-purple tile.
/// `iconutil -c icns` turns the folder into Assets/AppIcon.icns.
func renderAppIcon(to dir: String) {
    let cfg = Config()
    let sheet = SpriteSheet(resources: resourcesDirectory(), config: cfg)
    guard sheet.isLoaded, let master = drawAppIcon(sheet: sheet, palette: cfg.extras) else {
        FileHandle.standardError.write(Data("could not draw the icon\n".utf8))
        return
    }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = base * scale
            let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
            guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.interpolationQuality = .high
            ctx.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
            guard let image = ctx.makeImage() else { continue }
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
    }
    print("wrote \(dir)")
}

private func drawAppIcon(sheet: SpriteSheet, palette: Palette) -> CGImage? {
    let side = 1024
    guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    // The macOS tile: 824 points square, inset 100, with the standard corner.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor(white: 0, alpha: 0.35).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor(hex: "#2E1B47")!.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let colours = [NSColor(hex: "#1A0F2E")!.cgColor, NSColor(hex: "#4B2C7A")!.cgColor] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    }
    // A soft glow behind the cat, and a floor line it sits on.
    let glow = [NSColor(hex: "#B48CF0")!.withAlphaComponent(0.55).cgColor,
                NSColor(hex: "#B48CF0")!.withAlphaComponent(0).cgColor] as CFArray
    if let radial = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glow, locations: [0, 1]) {
        ctx.drawRadialGradient(radial, startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 470), endRadius: 380, options: [])
    }
    ctx.setFillColor(NSColor(hex: "#120A20")!.withAlphaComponent(0.6).cgColor)
    ctx.fill(CGRect(x: 100, y: 100, width: 824, height: 150))
    ctx.restoreGState()

    // The cat itself, drawn by the app's own renderer: 20 screen pixels per
    // sprite pixel, so it stays crisp pixel art.
    let cat = CatState()
    cat.clip = .sitIdle
    cat.size = SpriteSheet.standHeight * 20
    cat.pos = CGPoint(x: 530, y: 250)
    cat.wearing = [.chain, .glasses]
    drawCat(cat, sheet: sheet, drawShadow: true, palette: palette, in: ctx)
    return ctx.makeImage()
}
