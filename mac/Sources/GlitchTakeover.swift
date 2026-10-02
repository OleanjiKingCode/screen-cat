import AppKit

// The full-screen glitch for the idle crawl. Fifty named styles, each a stack
// of effect layers in its own colours. One style plays for about a minute,
// then the next takes over. It is all paint on the overlay; no app is touched.
//
// It renders at half resolution into a bitmap shown with nearest-neighbour
// scaling: chunky pixels suit a glitch, and it keeps a full-screen effect
// cheap enough to run for as long as you are away.

/// One effect. A style stacks a few of these.
enum TakeoverLayer {
    case scanlines, slices, staticNoise, colorBars, rollingBar, tint, tears
    case matrix(String)
    case hexWall, codeWall, blueScreen, melt, pixelSort, vhs, blocks, cracks
    case popups, radar, tunnel, warp, scope, heartbeat, gridFloor, waves, checker
    case loading, virus, dataStream
    /// Big pixel-font words. "#" counts down from 10.
    case bigText([String])
    /// A word tiled over the whole screen in scrolling rows.
    case tiled(String)
}

struct GlitchRecipe {
    let name: String
    /// How dark the screen goes under the effect, 0 to 1.
    let dim: CGFloat
    let layers: [TakeoverLayer]
    let palette: [NSColor]
}

private func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

private let toxic = [hex(0x39FF7A), hex(0xB6FF3B), hex(0x0B6E34)]
private let ice = [hex(0x33E6FF), hex(0xBDF4FF), hex(0x1E6BFF)]
private let hotPink = [hex(0xFF4DD8), hex(0xFF8FD1), hex(0x8A2BE2)]
private let amber = [hex(0xFFBF33), hex(0xFF7A1A), hex(0xFFE08A)]
private let blood = [hex(0xFF3B4A), hex(0xFF8A80), hex(0x8A0016)]
private let synth = [hex(0xFF2E97), hex(0x00E5FF), hex(0xFFD319)]
private let ghost = [hex(0xFFFFFF), hex(0xB0B0B0), hex(0x5A5A5A)]
private let royal = [hex(0xA87BE0), hex(0xFFC94A), hex(0x5B2D91)]
private let sunset = [hex(0xFF6B35), hex(0xF7C59F), hex(0x2EC4B6)]
private let void = [hex(0xE0AAFF), hex(0x9D4EDD), hex(0x3C096C)]

private let kana = "アイウエオカキクケコサシスセソタチツテトナニヌネノ0123456789"

/// The fifty styles.
let glitchRecipes: [GlitchRecipe] = [
    GlitchRecipe(name: "Green Breach", dim: 0.7, layers: [.scanlines, .slices, .codeWall, .cracks, .bigText(["SYSTEM BREACHED", "BREACHED"])], palette: toxic),
    GlitchRecipe(name: "Digital Rain", dim: 0.92, layers: [.matrix(kana), .rollingBar], palette: toxic),
    GlitchRecipe(name: "Ice Rain", dim: 0.92, layers: [.matrix("01"), .scanlines], palette: ice),
    GlitchRecipe(name: "Pink Rain", dim: 0.92, layers: [.matrix(kana), .tint], palette: hotPink),
    GlitchRecipe(name: "Blue Screen of Meow", dim: 1, layers: [.blueScreen], palette: ice),
    GlitchRecipe(name: "No Signal", dim: 0.7, layers: [.staticNoise, .colorBars, .rollingBar, .bigText(["NO SIGNAL"])], palette: ghost),
    GlitchRecipe(name: "Amber Static", dim: 0.75, layers: [.staticNoise, .scanlines, .tint], palette: amber),
    GlitchRecipe(name: "Meltdown", dim: 0.7, layers: [.melt, .scanlines, .bigText(["MELTDOWN"])], palette: blood),
    GlitchRecipe(name: "Pixel Sort", dim: 0.78, layers: [.pixelSort, .tears], palette: synth),
    GlitchRecipe(name: "VHS Rewind", dim: 0.85, layers: [.colorBars, .waves, .vhs, .tears, .scanlines], palette: sunset),
    GlitchRecipe(name: "Corrupt Blocks", dim: 0.72, layers: [.blocks, .slices, .scanlines], palette: synth),
    GlitchRecipe(name: "Shatter", dim: 0.78, layers: [.cracks, .tears, .tint], palette: ghost),
    GlitchRecipe(name: "Error Storm", dim: 0.62, layers: [.popups, .scanlines], palette: royal),
    GlitchRecipe(name: "Radar Lock", dim: 0.92, layers: [.radar, .scanlines], palette: toxic),
    GlitchRecipe(name: "Tunnel", dim: 0.88, layers: [.tunnel, .scanlines], palette: hotPink),
    GlitchRecipe(name: "Warp Speed", dim: 0.96, layers: [.warp], palette: ice),
    GlitchRecipe(name: "Oscilloscope", dim: 0.92, layers: [.scope, .scanlines], palette: toxic),
    GlitchRecipe(name: "Flatline", dim: 0.94, layers: [.heartbeat, .scanlines], palette: blood),
    GlitchRecipe(name: "Outrun", dim: 0.96, layers: [.gridFloor, .scanlines], palette: synth),
    GlitchRecipe(name: "RGB Waves", dim: 0.78, layers: [.waves, .slices], palette: synth),
    GlitchRecipe(name: "Checker Panic", dim: 0.72, layers: [.checker, .bigText(["ALERT"])], palette: blood),
    GlitchRecipe(name: "Meow Wall", dim: 0.88, layers: [.tiled("MEOW"), .scanlines], palette: royal),
    GlitchRecipe(name: "Hacked Wall", dim: 0.88, layers: [.tiled("HACKED"), .slices], palette: toxic),
    GlitchRecipe(name: "Download Everything", dim: 0.92, layers: [.hexWall, .loading], palette: amber),
    GlitchRecipe(name: "Cat Virus", dim: 0.85, layers: [.virus, .bigText(["CAT VIRUS DETECTED", "CAT VIRUS"])], palette: toxic),
    GlitchRecipe(name: "Hex Dump", dim: 0.94, layers: [.hexWall, .rollingBar], palette: amber),
    GlitchRecipe(name: "Root Shell", dim: 0.94, layers: [.codeWall, .scanlines], palette: toxic),
    GlitchRecipe(name: "Data Stream", dim: 0.92, layers: [.dataStream, .scanlines], palette: ice),
    GlitchRecipe(name: "Purple Haze", dim: 0.8, layers: [.waves, .tint, .staticNoise], palette: void),
    GlitchRecipe(name: "Ghost Signal", dim: 0.78, layers: [.staticNoise, .tears, .bigText(["IS ANYONE THERE?", "HELLO?"])], palette: ghost),
    GlitchRecipe(name: "Red Alert", dim: 0.82, layers: [.rollingBar, .checker, .bigText(["SELF DESTRUCT IN #", "BOOM IN #"])], palette: blood),
    GlitchRecipe(name: "Sunset Melt", dim: 0.72, layers: [.melt, .waves], palette: sunset),
    GlitchRecipe(name: "Neon Tunnel", dim: 0.92, layers: [.tunnel, .warp], palette: synth),
    GlitchRecipe(name: "Matrix Breach", dim: 0.88, layers: [.matrix(kana), .cracks, .bigText(["ACCESS GRANTED", "GRANTED"])], palette: toxic),
    GlitchRecipe(name: "Static Rain", dim: 0.85, layers: [.staticNoise, .matrix("01")], palette: ghost),
    GlitchRecipe(name: "Glitch Mosaic", dim: 0.72, layers: [.blocks, .checker], palette: royal),
    GlitchRecipe(name: "Broken Display", dim: 0.72, layers: [.tears, .colorBars, .slices, .cracks], palette: ghost),
    GlitchRecipe(name: "Radar Rain", dim: 0.92, layers: [.radar, .matrix("01")], palette: ice),
    GlitchRecipe(name: "Synthwave Scope", dim: 0.96, layers: [.gridFloor, .scope], palette: synth),
    GlitchRecipe(name: "Error 404", dim: 0.75, layers: [.tiled("404"), .popups], palette: blood),
    GlitchRecipe(name: "Infection", dim: 0.85, layers: [.virus, .codeWall], palette: hotPink),
    GlitchRecipe(name: "Deep Sort", dim: 0.75, layers: [.pixelSort, .rollingBar, .scanlines], palette: void),
    GlitchRecipe(name: "Gold Rush", dim: 0.9, layers: [.tiled("PAY ME"), .dataStream], palette: amber),
    GlitchRecipe(name: "Heartbeat Grid", dim: 0.94, layers: [.gridFloor, .heartbeat], palette: toxic),
    GlitchRecipe(name: "Frozen", dim: 0.78, layers: [.checker, .tint, .cracks], palette: ice),
    GlitchRecipe(name: "Cat OS Crash", dim: 1, layers: [.blueScreen, .tears], palette: royal),
    GlitchRecipe(name: "Signal Lost", dim: 0.75, layers: [.vhs, .staticNoise, .bigText(["SIGNAL LOST", "LOST"])], palette: amber),
    GlitchRecipe(name: "Laser Grid", dim: 0.94, layers: [.gridFloor, .radar], palette: blood),
    GlitchRecipe(name: "Hyperdrive", dim: 0.96, layers: [.warp, .tunnel], palette: void),
    GlitchRecipe(name: "Total Chaos", dim: 0.72, layers: [.blocks, .slices, .tears, .popups, .cracks], palette: synth),
]

// MARK: - Rendering

/// Paints one frame of `recipe`, `t` seconds in, filling `r`. Needs a current
/// NSGraphicsContext wrapping `ctx`, because the text and fills go through
/// AppKit. `pulse` (0 to 1) flashes the screen when the cat zaps something.
func renderTakeover(_ recipe: GlitchRecipe, in r: CGRect, time t: CGFloat, seed: UInt32,
                    pulse: CGFloat, ctx: CGContext) {
    ctx.saveGState()
    ctx.setShouldAntialias(false)
    ctx.clip(to: r)
    NSColor(white: 0, alpha: recipe.dim).setFill()
    r.fill()
    let pal = recipe.palette
    for layer in recipe.layers {
        var f = GlitchRandom(seed &+ UInt32(max(0, t) * 20))
        switch layer {
        case .scanlines: scanlines(r)
        case .slices: slices(r, pal, &f)
        case .staticNoise: staticNoise(r, pal, &f)
        case .colorBars: colorBars(r, &f)
        case .rollingBar: rollingBar(r, t)
        case .tint: pal[0].withAlphaComponent(0.14).setFill(); r.fill()
        case .tears: tears(r, pal, &f)
        case .matrix(let chars): matrix(r, t, pal, seed, Array(chars), ctx)
        case .hexWall: hexWall(r, t, pal, seed)
        case .codeWall: codeWall(r, t, pal, seed)
        case .blueScreen: blueScreen(r, t, pal, ctx)
        case .melt: melt(r, t, pal, seed)
        case .pixelSort: pixelSort(r, t, pal, seed)
        case .vhs: vhs(r, t, pal, &f, ctx)
        case .blocks: blocks(r, pal, &f)
        case .cracks: cracks(r, t, seed)
        case .popups: popups(r, t, pal, seed, ctx)
        case .radar: radar(r, t, pal, seed)
        case .tunnel: tunnel(r, t, pal)
        case .warp: warp(r, t, pal, seed)
        case .scope: scope(r, t, pal)
        case .heartbeat: heartbeat(r, t, pal, &f, ctx)
        case .gridFloor: gridFloor(r, t, pal)
        case .waves: waves(r, t, pal)
        case .checker: checker(r, t, pal, &f)
        case .loading: loading(r, t, pal, ctx)
        case .virus: virus(r, t, pal, seed, &f)
        case .dataStream: dataStream(r, t, pal, seed)
        case .bigText(let options): bigText(r, t, pal, options, &f, ctx)
        case .tiled(let word): tiled(r, t, pal, word, ctx)
        }
    }
    if pulse > 0.01 {
        NSColor(white: 1, alpha: 0.35 * pulse).setFill()
        r.fill()
    }
    ctx.restoreGState()
}

private func stroke(_ path: NSBezierPath, _ colour: NSColor, _ width: CGFloat, glow: Bool = false) {
    if glow {
        colour.withAlphaComponent(0.25).setStroke()
        path.lineWidth = width * 4
        path.stroke()
    }
    colour.setStroke()
    path.lineWidth = width
    path.stroke()
}

private func scanlines(_ r: CGRect) {
    NSColor(white: 0, alpha: 0.35).setFill()
    var y = r.minY
    while y < r.maxY { CGRect(x: r.minX, y: y, width: r.width, height: 2).fill(); y += 6 }
}

private func slices(_ r: CGRect, _ pal: [NSColor], _ f: inout GlitchRandom) {
    for i in 0..<16 {
        pal[i % pal.count].withAlphaComponent(0.3).setFill()
        let h = f.range(4, 40)
        CGRect(x: r.minX + f.range(-80, 80), y: f.range(r.minY, r.maxY - h),
               width: r.width * f.range(0.3, 1.1), height: h).fill()
    }
}

private func staticNoise(_ r: CGRect, _ pal: [NSColor], _ f: inout GlitchRandom) {
    let block = max(10, r.width / 90)
    var y = r.minY
    while y < r.maxY {
        var x = r.minX
        while x < r.maxX {
            let roll = f.unit()
            if roll < 0.4 {
                NSColor(white: f.range(0.1, 0.95), alpha: 0.85).setFill()
                CGRect(x: x, y: y, width: block, height: block).fill()
            } else if roll < 0.46 {
                pal[Int(f.unit() * 2.99)].withAlphaComponent(0.8).setFill()
                CGRect(x: x, y: y, width: block, height: block).fill()
            }
            x += block
        }
        y += block
    }
}

private func colorBars(_ r: CGRect, _ f: inout GlitchRandom) {
    let bars: [NSColor] = [NSColor(white: 0.8, alpha: 1), .systemYellow, .systemTeal, .systemGreen,
                           .systemPink, .systemRed, .systemBlue]
    let band = CGRect(x: r.minX, y: r.midY - r.height * 0.18, width: r.width, height: r.height * 0.36)
    let w = band.width / CGFloat(bars.count)
    let shift = f.range(-20, 20)
    for (i, c) in bars.enumerated() {
        c.withAlphaComponent(0.85).setFill()
        CGRect(x: band.minX + CGFloat(i) * w + shift, y: band.minY, width: w + 1, height: band.height).fill()
    }
}

private func rollingBar(_ r: CGRect, _ t: CGFloat) {
    let y = r.minY + (t * r.height * 0.35).truncatingRemainder(dividingBy: r.height)
    NSColor(white: 1, alpha: 0.16).setFill()
    CGRect(x: r.minX, y: y, width: r.width, height: max(12, r.height * 0.06)).fill()
}

private func tears(_ r: CGRect, _ pal: [NSColor], _ f: inout GlitchRandom) {
    for i in 0..<28 {
        let y = f.range(r.minY, r.maxY)
        let x = r.minX + f.range(-40, r.width * 0.5)
        let colour = i % 3 == 0 ? NSColor.white : pal[i % pal.count]
        colour.withAlphaComponent(f.range(0.35, 0.8)).setFill()
        CGRect(x: x, y: y, width: r.width * f.range(0.2, 0.9), height: f.range(1, 4)).fill()
    }
}

/// Glyph images in a given colour, rendered once and reused every frame.
private enum TakeoverGlyphs {
    static var cache: [String: CGImage] = [:]
    static let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .bold)

    static func image(_ ch: Character, _ colour: NSColor) -> CGImage? {
        let c = colour.usingColorSpace(.sRGB) ?? colour
        let key = "\(ch)|\(Int(c.redComponent * 255))|\(Int(c.greenComponent * 255))|\(Int(c.blueComponent * 255))"
        if let hit = cache[key] { return hit }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        let image = NSImage(size: CGSize(width: 16, height: 20), flipped: false) { _ in
            NSString(string: String(ch)).draw(at: CGPoint(x: 2, y: 1), withAttributes: attrs)
            return true
        }
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        cache[key] = cg
        return cg
    }
}

private func matrix(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ seed: UInt32,
                    _ chars: [Character], _ ctx: CGContext) {
    let colW: CGFloat = max(18, r.width / 80)
    let rowH: CGFloat = 20
    var columns = GlitchRandom(seed)
    let tick = UInt32(t / 0.1)
    for c in 0..<Int(r.width / colW) {
        let speed = columns.range(120, 420)
        let start = columns.range(0, r.height)
        let trail = Int(columns.range(8, 22))
        let span = r.height + CGFloat(trail) * rowH
        let head = r.maxY - (t * speed + start).truncatingRemainder(dividingBy: span)
        var glyphs = GlitchRandom(seed &+ UInt32(c) &* 977 &+ tick)
        let x = r.minX + CGFloat(c) * colW
        for k in 0..<trail {
            let y = head + CGFloat(k) * rowH
            guard y > r.minY - rowH, y < r.maxY else { _ = glyphs.unit(); continue }
            let ch = chars[Int(glyphs.unit() * CGFloat(chars.count - 1))]
            guard let img = TakeoverGlyphs.image(ch, k == 0 ? .white : pal[k % 7 == 3 ? 1 : 0]) else { continue }
            ctx.saveGState()
            ctx.setAlpha(k == 0 ? 1 : max(0.12, 1 - CGFloat(k) / CGFloat(trail)))
            ctx.draw(img, in: CGRect(x: x, y: y, width: 16, height: 20))
            ctx.restoreGState()
        }
    }
}

private func monoAttrs(_ colour: NSColor, _ size: CGFloat = 12) -> [NSAttributedString.Key: Any] {
    [.font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium), .foregroundColor: colour]
}

private func hexWall(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ seed: UInt32) {
    let lineH: CGFloat = 16
    let scroll = Int(t * 7)
    let rows = Int(r.height / lineH) + 1
    let highlight = (scroll / 5) % max(1, rows)
    for row in 0..<rows {
        var g = GlitchRandom(seed &+ UInt32(row + scroll) &* 131)
        var line = String(format: "%08X  ", (row + scroll) * 16)
        for _ in 0..<16 { line += String(format: "%02X ", Int(g.unit() * 255)) }
        line += " " + String((0..<12).map { _ in Character(UnicodeScalar(UInt8(33 + Int(g.unit() * 90)))) })
        let colour = row == highlight ? pal[1] : pal[0].withAlphaComponent(0.55 + 0.4 * g.unit())
        var x = r.minX + 12
        while x < r.maxX {
            NSString(string: line).draw(at: CGPoint(x: x, y: r.maxY - CGFloat(row + 1) * lineH), withAttributes: monoAttrs(colour))
            x += 560
        }
    }
}

private let wallCode = [
    "$ sudo purr --force --no-mercy", "inject --payload whiskers.bin", "bypass firewall :: port 443 OPEN",
    "decrypt(0x3F2A9C) -> ok", "while (true) { claw(memory); }", "rm -rf /system/naps/*",
    "kernel.panic(\"too many cats\")", "ssh root@mainframe --whiskers", "override AUTH_TOKEN=meow",
    "patching memory @ 0x0C47", "exfiltrating yarn.db (2.3 MB)", "access level: ROOT",
    "segfault in app.render()", "chmod 777 /dev/catnip", "ERROR 0xDEAD: app not responding",
    "uploading hairball.zip", "fork() x 9 lives", "GET /api/v1/treats  200 OK", "deleting monday.exe ...",
    "for (i = 0; i < 9; i++) lives[i].backup()", "mount /dev/fishtank /mnt/snacks", "compiling mischief.c ... done",
]

private func codeWall(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ seed: UInt32) {
    let lineH: CGFloat = 16
    let colW: CGFloat = 420
    let columns = max(1, Int(r.width / colW))
    let rows = Int(r.height / lineH)
    let typed = t * 9
    for c in 0..<columns {
        let offset = Int(seed % 97) + c * 7
        for row in 0..<rows {
            let index = Int(typed) - row + offset + c * 3
            var text = wallCode[((index % wallCode.count) + wallCode.count) % wallCode.count]
            if row == 0 {
                text = String(text.prefix(Int((typed - floor(typed)) * CGFloat(text.count)))) + "_"
            }
            let colour = row == 0 ? pal[1] : pal[0].withAlphaComponent(max(0.3, 1 - CGFloat(row) / CGFloat(rows)))
            NSString(string: text).draw(at: CGPoint(x: r.minX + 16 + CGFloat(c) * colW, y: r.minY + 12 + CGFloat(row) * lineH),
                                        withAttributes: monoAttrs(colour))
        }
    }
}

/// Pixel-font text, fitted to `maxWidth`. Returns the pixel size used.
@discardableResult
private func pixelText(_ text: String, centre: CGPoint, maxWidth: CGFloat, maxPixel: CGFloat,
                       colour: NSColor, ctx: CGContext, box: Bool = false) -> CGFloat {
    let w = CGFloat(PixelFont.width(of: text))
    let p = max(2, min(maxPixel, floor(maxWidth / max(1, w))))
    let width = w * p, height = CGFloat(PixelFont.height) * p
    let origin = CGPoint(x: (centre.x - width / 2).rounded(), y: (centre.y - height / 2).rounded())
    if box {
        let frame = CGRect(x: origin.x - p * 3, y: origin.y - p * 3, width: width + p * 6, height: height + p * 6)
        NSColor(white: 0, alpha: 0.85).setFill()
        frame.fill()
        colour.setStroke()
        let path = NSBezierPath(rect: frame.insetBy(dx: p / 2, dy: p / 2))
        path.lineWidth = p
        path.stroke()
    }
    PixelFont.draw(text, at: origin, pixel: p, color: colour, in: ctx)
    return p
}

private func blueScreen(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ ctx: CGContext) {
    (pal[2].blended(withFraction: 0.15, of: .black) ?? pal[2]).setFill()
    r.fill()
    let percent = min(100, Int(t * 1.7))
    let lines = ["YOUR CAT RAN INTO A PROBLEM", "CAT.EXE HAS STOPPED", "STOP CODE: HAIRBALL",
                 "COLLECTING CATNIP \(percent)%"]
    let widest = CGFloat(lines.map { PixelFont.width(of: $0) }.max() ?? 1)
    let p = max(2, min(7, floor(r.width * 0.75 / widest)))
    let left = r.minX + r.width * 0.1
    var y = r.maxY - r.height * 0.2
    y -= CGFloat(PixelFont.height) * p * 3
    PixelFont.draw(":(", at: CGPoint(x: left, y: y), pixel: p * 3, color: .white, in: ctx)
    y -= p * 8
    for line in lines {
        y -= CGFloat(PixelFont.height) * p + p * 4
        PixelFont.draw(line, at: CGPoint(x: left, y: y), pixel: p, color: .white, in: ctx)
    }
}

private func melt(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ seed: UInt32) {
    let colW = max(10, r.width / 80)
    let phase = (t / 14).truncatingRemainder(dividingBy: 1)
    let eased = 1 - pow(1 - phase, 2)
    var cols = GlitchRandom(seed)
    let dark = pal[2]
    for c in 0..<Int(ceil(r.width / colW)) {
        let length = r.height * eased * cols.range(0.3, 1.1)
        let x = r.minX + CGFloat(c) * colW
        dark.withAlphaComponent(0.9).setFill()
        CGRect(x: x, y: r.maxY - length, width: colW + 0.5, height: length).fill()
        pal[0].setFill()
        CGRect(x: x, y: r.maxY - length, width: colW + 0.5, height: min(length, colW)).fill()
        if cols.unit() < 0.35 {
            let fall = (t * 300 * cols.range(0.6, 1.4)).truncatingRemainder(dividingBy: r.height)
            pal[1].setFill()
            CGRect(x: x + colW * 0.25, y: r.maxY - length - fall, width: colW * 0.5, height: colW).fill()
        }
    }
}

private func pixelSort(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ seed: UInt32) {
    let colW = max(6, r.width / 140)
    var cols = GlitchRandom(seed)
    for c in 0..<Int(r.width / colW) {
        let x = r.minX + CGFloat(c) * colW
        let base = cols.range(r.minY, r.maxY)
        let speed = cols.range(0.5, 2.5), phase = cols.range(0, 6.28)
        let h = r.height * (0.15 + 0.35 * (0.5 + 0.5 * sin(t * speed + phase)))
        let colour = pal[Int(cols.unit() * 2.99)]
        for s in 0..<5 {
            colour.withAlphaComponent(0.85 - CGFloat(s) * 0.16).setFill()
            CGRect(x: x, y: base - CGFloat(s) * h / 5, width: colW, height: h / 5).fill()
        }
    }
}

private func vhs(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ f: inout GlitchRandom, _ ctx: CGContext) {
    let bandH = r.height * 0.12
    let bandY = r.maxY - (t * r.height * 0.25).truncatingRemainder(dividingBy: r.height + bandH)
    var y = bandY
    while y < bandY + bandH {
        NSColor(white: f.range(0.3, 1), alpha: 0.6).setFill()
        CGRect(x: r.minX + f.range(-30, 30), y: y, width: r.width, height: 3).fill()
        y += 5
    }
    let secs = Int(t) % 60, mins = (Int(t) / 60) % 60
    PixelFont.draw("PLAY", at: CGPoint(x: r.minX + 40, y: r.maxY - 70), pixel: 5, color: .white, in: ctx)
    PixelFont.draw(String(format: "00:%02d:%02d", mins, secs), at: CGPoint(x: r.minX + 40, y: r.minY + 40),
                   pixel: 5, color: pal[0], in: ctx)
}

private func blocks(_ r: CGRect, _ pal: [NSColor], _ f: inout GlitchRandom) {
    for _ in 0..<46 {
        let w = f.range(20, 180), h = f.range(14, 120)
        let rect = CGRect(x: f.range(r.minX, r.maxX - w), y: f.range(r.minY, r.maxY - h), width: w, height: h)
        pal[Int(f.unit() * 2.99)].withAlphaComponent(f.range(0.4, 0.9)).setFill()
        rect.fill()
        if f.unit() < 0.4 {
            NSColor(white: 1, alpha: 0.5).setFill()
            CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: 2).fill()
        }
    }
}

private func cracks(_ r: CGRect, _ t: CGFloat, _ seed: UInt32) {
    let cycle: CGFloat = 8
    let round = UInt32(t / cycle)
    let grow = min(1, (t.truncatingRemainder(dividingBy: cycle)) / 2.5)
    var shape = GlitchRandom(seed &+ round &* 31)
    let reach = max(r.width, r.height) * 0.35 * (1 - pow(1 - grow, 3))
    for _ in 0..<4 {
        let origin = CGPoint(x: shape.range(r.minX, r.maxX), y: shape.range(r.minY, r.maxY))
        for k in 0..<8 {
            let path = NSBezierPath()
            path.move(to: origin)
            var angle = CGFloat(k) * .pi / 4 + shape.range(-0.3, 0.3)
            var p = origin
            for _ in 0..<7 {
                angle += shape.range(-0.5, 0.5)
                let step = reach / 7 * shape.range(0.6, 1.3)
                p = CGPoint(x: p.x + cos(angle) * step, y: p.y + sin(angle) * step)
                path.line(to: p)
            }
            stroke(path, NSColor(white: 0, alpha: 0.7), 4)
            stroke(path, NSColor(white: 1, alpha: 0.9), 1.5)
        }
    }
}

private func popups(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ seed: UInt32, _ ctx: CGContext) {
    let shown = Int(t * 1.6) + 2
    let first = max(0, shown - 36)
    for i in first..<shown {
        var g = GlitchRandom(seed &+ UInt32(i) &* 7919)
        let w = g.range(220, 320), h = g.range(100, 130)
        let box = CGRect(x: g.range(r.minX, r.maxX - w), y: g.range(r.minY, r.maxY - h), width: w, height: h)
        NSColor(white: 0, alpha: 0.4).setFill()
        box.offsetBy(dx: 6, dy: -6).fill()
        NSColor(white: 0.93, alpha: 1).setFill()
        box.fill()
        pal[i % pal.count].setFill()
        CGRect(x: box.minX, y: box.maxY - 22, width: w, height: 22).fill()
        PixelFont.draw("ERROR", at: CGPoint(x: box.minX + 10, y: box.maxY - 18), pixel: 2, color: .white, in: ctx)
        let messages = ["CAT.EXE IS NOT RESPONDING", "TOO MANY CATS", "OUT OF TREATS", "PURR OVERFLOW", "LITTER BOX FULL"]
        PixelFont.draw(messages[i % messages.count], at: CGPoint(x: box.minX + 12, y: box.midY - 6), pixel: 2,
                       color: NSColor(white: 0.15, alpha: 1), in: ctx)
        NSColor(white: 0.8, alpha: 1).setFill()
        let ok = CGRect(x: box.maxX - 60, y: box.minY + 10, width: 48, height: 22)
        ok.fill()
        PixelFont.draw("OK", at: CGPoint(x: ok.minX + 15, y: ok.minY + 4), pixel: 2,
                       color: NSColor(white: 0.15, alpha: 1), in: ctx)
    }
}

private func radar(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ seed: UInt32) {
    let c = CGPoint(x: r.midX, y: r.midY)
    let radius = min(r.width, r.height) * 0.46
    for i in 1...5 {
        let rr = radius * CGFloat(i) / 5
        stroke(NSBezierPath(ovalIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
               pal[0].withAlphaComponent(0.45), 2)
    }
    let cross = NSBezierPath()
    cross.move(to: CGPoint(x: c.x - radius, y: c.y)); cross.line(to: CGPoint(x: c.x + radius, y: c.y))
    cross.move(to: CGPoint(x: c.x, y: c.y - radius)); cross.line(to: CGPoint(x: c.x, y: c.y + radius))
    stroke(cross, pal[0].withAlphaComponent(0.35), 1.5)
    let angle = t * 1.8
    for k in 0..<24 {
        let a0 = angle - CGFloat(k) * 0.03
        let wedge = NSBezierPath()
        wedge.move(to: c)
        wedge.appendArc(withCenter: c, radius: radius, startAngle: (a0 - 0.03) * 180 / .pi, endAngle: a0 * 180 / .pi)
        wedge.close()
        pal[0].withAlphaComponent(0.4 * (1 - CGFloat(k) / 24)).setFill()
        wedge.fill()
    }
    var blips = GlitchRandom(seed)
    for _ in 0..<10 {
        let a = blips.range(0, .pi * 2), d = blips.range(0.15, 0.95) * radius
        let since = (angle - a).truncatingRemainder(dividingBy: .pi * 2)
        let fade = since < 0 ? 0 : max(0, 1 - since / 3)
        pal[1].withAlphaComponent(fade).setFill()
        NSBezierPath(ovalIn: CGRect(x: c.x + cos(a) * d - 6, y: c.y + sin(a) * d - 6, width: 12, height: 12)).fill()
    }
}

private func tunnel(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor]) {
    let c = CGPoint(x: r.midX, y: r.midY)
    for i in 0..<16 {
        let z = (t * 0.35 + CGFloat(i) / 16).truncatingRemainder(dividingBy: 1)
        let s = z * z
        let rect = CGRect(x: c.x - r.width * s * 0.6, y: c.y - r.height * s * 0.6,
                          width: r.width * s * 1.2, height: r.height * s * 1.2)
        stroke(NSBezierPath(rect: rect), pal[i % pal.count].withAlphaComponent(z), 2 + 6 * z, glow: true)
    }
}

private func warp(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ seed: UInt32) {
    let c = CGPoint(x: r.midX, y: r.midY)
    let maxR = hypot(r.width, r.height) * 0.55
    var stars = GlitchRandom(seed)
    for i in 0..<240 {
        let a = stars.range(0, .pi * 2)
        let speed = stars.range(0.15, 0.6)
        let z = (t * speed + stars.unit()).truncatingRemainder(dividingBy: 1)
        let d = z * z * maxR
        let tail = d * 0.82
        let path = NSBezierPath()
        path.move(to: CGPoint(x: c.x + cos(a) * tail, y: c.y + sin(a) * tail))
        path.line(to: CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d))
        stroke(path, (i % 4 == 0 ? pal[i % pal.count] : .white).withAlphaComponent(min(1, z * 1.6)), 1 + 3 * z)
    }
}

private func scope(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor]) {
    NSColor(white: 1, alpha: 0.06).setFill()
    var gx = r.minX
    while gx < r.maxX { CGRect(x: gx, y: r.minY, width: 1, height: r.height).fill(); gx += 60 }
    var gy = r.minY
    while gy < r.maxY { CGRect(x: r.minX, y: gy, width: r.width, height: 1).fill(); gy += 60 }
    for w in 0..<3 {
        let path = NSBezierPath()
        let amp = r.height * (0.12 + 0.08 * CGFloat(w)) * (1 + 0.3 * sin(t * 0.7 + CGFloat(w)))
        let freq = 0.006 + 0.004 * CGFloat(w)
        let mid = r.midY + CGFloat(w - 1) * r.height * 0.18
        var x = r.minX
        path.move(to: CGPoint(x: x, y: mid))
        while x <= r.maxX {
            path.line(to: CGPoint(x: x, y: mid + amp * sin(x * freq + t * (2 + CGFloat(w)))))
            x += 6
        }
        stroke(path, pal[w], 3, glow: true)
    }
}

private func heartbeat(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ f: inout GlitchRandom, _ ctx: CGContext) {
    func ecg(_ p: CGFloat) -> CGFloat {
        switch p {
        case 0.40..<0.44: return (p - 0.40) / 0.04 * 0.2
        case 0.44..<0.47: return 0.2 - (p - 0.44) / 0.03 * 0.5
        case 0.47..<0.50: return -0.3 + (p - 0.47) / 0.03 * 1.3
        case 0.50..<0.54: return 1.0 - (p - 0.50) / 0.04 * 1.0
        case 0.62..<0.70: return 0.15 * sin((p - 0.62) / 0.08 * .pi)
        default: return 0
        }
    }
    let path = NSBezierPath()
    var x = r.minX
    let amp = r.height * 0.28
    path.move(to: CGPoint(x: x, y: r.midY))
    while x <= r.maxX {
        let p = ((x - r.minX) / r.width * 3 - t * 0.9).truncatingRemainder(dividingBy: 1)
        path.line(to: CGPoint(x: x, y: r.midY + ecg(p < 0 ? p + 1 : p) * amp))
        x += 4
    }
    stroke(path, pal[0], 4, glow: true)
    let bpm = 180 + Int(f.unit() * 819)
    PixelFont.draw("BPM \(bpm)", at: CGPoint(x: r.maxX - 360, y: r.maxY - 90), pixel: 8, color: pal[1], in: ctx)
}

private func gridFloor(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor]) {
    let horizon = r.minY + r.height * 0.42
    let sunR = r.height * 0.22
    let sun = CGRect(x: r.midX - sunR, y: horizon - sunR * 0.3, width: sunR * 2, height: sunR * 2)
    NSGradient(starting: pal[2], ending: pal[0])?.draw(in: NSBezierPath(ovalIn: sun), angle: 90)
    NSColor(white: 0, alpha: 0.9).setFill()
    for i in 0..<6 {
        let y = horizon + CGFloat(i) * sunR * 0.18
        CGRect(x: sun.minX, y: y, width: sun.width, height: CGFloat(i + 1) * 2).fill()
    }
    NSColor(white: 0, alpha: 1).setFill()
    CGRect(x: r.minX, y: r.minY, width: r.width, height: horizon - r.minY).fill()
    let lines = NSBezierPath()
    for i in -20...20 {
        lines.move(to: CGPoint(x: r.midX + CGFloat(i) * 30, y: horizon))
        lines.line(to: CGPoint(x: r.midX + CGFloat(i) * r.width * 0.12, y: r.minY))
    }
    for k in 0..<14 {
        let z = (CGFloat(k) / 14 + t * 0.35).truncatingRemainder(dividingBy: 1)
        let y = horizon - (horizon - r.minY) * z * z * z
        lines.move(to: CGPoint(x: r.minX, y: y))
        lines.line(to: CGPoint(x: r.maxX, y: y))
    }
    stroke(lines, pal[1], 2, glow: true)
}

private func waves(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor]) {
    let bands = 34
    let h = r.height / CGFloat(bands)
    for i in 0..<bands {
        let y = r.minY + CGFloat(i) * h
        let shift = sin(CGFloat(i) * 0.45 + t * 3) * 70
        pal[i % pal.count].withAlphaComponent(0.26).setFill()
        CGRect(x: r.minX + shift, y: y, width: r.width, height: h * 0.7).fill()
    }
}

private func checker(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ f: inout GlitchRandom) {
    let cell = r.width / 18
    let tick = Int(t * 4)
    var y = r.minY, j = 0
    while y < r.maxY {
        var x = r.minX, i = 0
        while x < r.maxX {
            if (i + j + tick) % 2 == 0 && f.unit() < 0.7 {
                pal[(i + j + tick / 2) % pal.count].withAlphaComponent(0.38).setFill()
                CGRect(x: x, y: y, width: cell, height: cell).fill()
            }
            x += cell; i += 1
        }
        y += cell; j += 1
    }
}

private func loading(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ ctx: CGContext) {
    let labels = ["DELETING PHOTOS", "UPLOADING BRAIN", "ENCRYPTING DISK", "FEEDING CAT", "FORMATTING C:", "MINING CATNIP"]
    let barW = min(r.width * 0.6, 900), barH: CGFloat = 26
    let x = r.midX - barW / 2
    var y = r.midY + CGFloat(labels.count) * 34
    for (i, label) in labels.enumerated() {
        let progress = (t * (0.05 + 0.03 * CGFloat(i)) + CGFloat(i) * 0.17).truncatingRemainder(dividingBy: 1)
        y -= 68
        PixelFont.draw("\(label) \(Int(progress * 100))%", at: CGPoint(x: x, y: y + barH + 8), pixel: 3,
                       color: pal[i % pal.count], in: ctx)
        NSColor(white: 0, alpha: 0.85).setFill()
        CGRect(x: x, y: y, width: barW, height: barH).fill()
        pal[i % pal.count].setFill()
        CGRect(x: x + 3, y: y + 3, width: (barW - 6) * progress, height: barH - 6).fill()
    }
}

private func virus(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ seed: UInt32, _ f: inout GlitchRandom) {
    let cell = r.width / 48
    let phase = (t / 20).truncatingRemainder(dividingBy: 1)
    var g = GlitchRandom(seed &+ UInt32(t / 20))
    let seeds = (0..<5).map { _ in CGPoint(x: g.range(r.minX, r.maxX), y: g.range(r.minY, r.maxY)) }
    let radius = phase * hypot(r.width, r.height) * 0.6
    var y = r.minY
    while y < r.maxY {
        var x = r.minX
        while x < r.maxX {
            let d = seeds.map { hypot($0.x - x, $0.y - y) }.min() ?? .infinity
            if d < radius {
                let front = radius - d < cell * 2
                (front ? pal[1] : pal[0]).withAlphaComponent(front ? 0.9 : f.range(0.25, 0.6)).setFill()
                CGRect(x: x + 1, y: y + 1, width: cell - 2, height: cell - 2).fill()
            }
            x += cell
        }
        y += cell
    }
}

private func dataStream(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ seed: UInt32) {
    let rows = 40
    let h = r.height / CGFloat(rows)
    var g = GlitchRandom(seed)
    for row in 0..<rows {
        let speed = g.range(80, 600) * (row % 2 == 0 ? 1 : -1)
        let dash = g.range(20, 140), gap = g.range(10, 80)
        let period = dash + gap
        let offset = (t * speed).truncatingRemainder(dividingBy: period)
        pal[row % pal.count].withAlphaComponent(0.7).setFill()
        var x = r.minX - period + offset
        while x < r.maxX {
            CGRect(x: x, y: r.minY + CGFloat(row) * h + h * 0.3, width: dash, height: h * 0.35).fill()
            x += period
        }
    }
}

private func bigText(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ options: [String],
                     _ f: inout GlitchRandom, _ ctx: CGContext) {
    guard f.unit() > 0.12 else { return }
    let count = String(10 - Int(t) % 11)
    let texts = options.map { $0.replacingOccurrences(of: "#", with: count) }
    let maxWidth = r.width * 0.7
    let text = texts.first { CGFloat(PixelFont.width(of: $0)) * 4 <= maxWidth } ?? texts[texts.count - 1]
    let centre = CGPoint(x: r.midX + f.range(-4, 4), y: r.midY)
    pixelText(text, centre: centre, maxWidth: maxWidth, maxPixel: 16, colour: pal[0], ctx: ctx, box: true)
    // A shifted ghost copy, the RGB split look.
    pixelText(text, centre: CGPoint(x: centre.x + 5, y: centre.y - 3), maxWidth: maxWidth, maxPixel: 16,
              colour: pal[1].withAlphaComponent(0.45), ctx: ctx)
}

private func tiled(_ r: CGRect, _ t: CGFloat, _ pal: [NSColor], _ word: String, _ ctx: CGContext) {
    let p = max(3, (r.width / 260).rounded())
    let unit = CGFloat(PixelFont.width(of: word + "  ")) * p
    let rowH = CGFloat(PixelFont.height + 5) * p
    var row = 0
    var y = r.minY
    while y < r.maxY {
        let dir: CGFloat = row % 2 == 0 ? 1 : -1
        let offset = (t * 40 * dir).truncatingRemainder(dividingBy: unit)
        var x = r.minX - unit + offset
        while x < r.maxX {
            PixelFont.draw(word, at: CGPoint(x: x, y: y), pixel: p,
                           color: pal[row % pal.count].withAlphaComponent(0.6), in: ctx)
            x += unit
        }
        y += rowH; row += 1
    }
}

// MARK: - The view

/// A layer-backed view that shows the takeover over one screen. It sits under
/// the cat's view, so the cat's own 60 fps redraws never repaint it.
final class TakeoverView: NSView {
    private var image: CGImage?
    private var shownOpacity: Float = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }
    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        layer?.magnificationFilter = .nearest
        layer?.contentsGravity = .resize
        layer?.contents = image
        layer?.opacity = shownOpacity
    }

    /// Renders one frame of `recipe` at half resolution and shows it.
    func show(_ recipe: GlitchRecipe, time: CGFloat, seed: UInt32, pulse: CGFloat, opacity: CGFloat) {
        shownOpacity = Float(opacity)
        guard opacity > 0.01, bounds.width > 1, bounds.height > 1 else { clear(); return }
        let scale: CGFloat = 0.5
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        renderTakeover(recipe, in: CGRect(origin: .zero, size: bounds.size), time: time, seed: seed,
                       pulse: pulse, ctx: ctx)
        NSGraphicsContext.restoreGraphicsState()
        image = ctx.makeImage()
        needsDisplay = true
    }

    func clear() {
        image = nil
        shownOpacity = 0
        needsDisplay = true
    }
}

/// `--takeover <path.png>`: every style as a thumbnail, ten seconds in.
/// `--takeover-bench`: milliseconds per frame for each style, full screen.
func renderTakeoverSheet(to path: String) {
    let cell = CGSize(width: 302, height: 196)
    let cols = 10
    let rowsCount = (glitchRecipes.count + cols - 1) / cols
    let board = CGSize(width: cell.width * CGFloat(cols), height: (cell.height + 22) * CGFloat(rowsCount))
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(board.width), pixelsHigh: Int(board.height),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let g = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = g
    NSColor(white: 0.2, alpha: 1).setFill()
    NSBezierPath(rect: CGRect(origin: .zero, size: board)).fill()
    // Render each at full size, then shrink into its cell, so text and
    // spacing look as they would on a real screen.
    let full = CGSize(width: 1512, height: 982)
    for (i, recipe) in glitchRecipes.enumerated() {
        guard let ctx = CGContext(data: nil, width: Int(full.width / 2), height: Int(full.height / 2),
                                  bitsPerComponent: 8, bytesPerRow: Int(full.width / 2) * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
        ctx.scaleBy(x: 0.5, y: 0.5)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSColor(white: 0.92, alpha: 1).setFill()
        CGRect(origin: .zero, size: full).fill()
        renderTakeover(recipe, in: CGRect(origin: .zero, size: full), time: 10, seed: UInt32(100 + i), pulse: 0, ctx: ctx)
        NSGraphicsContext.restoreGraphicsState()
        guard let img = ctx.makeImage() else { continue }
        let col = i % cols, row = i / cols
        let origin = CGPoint(x: CGFloat(col) * cell.width, y: board.height - CGFloat(row + 1) * (cell.height + 22))
        g.cgContext.draw(img, in: CGRect(x: origin.x + 4, y: origin.y + 22, width: cell.width - 8, height: cell.height - 4))
        NSString(string: "\(i + 1). \(recipe.name)").draw(at: CGPoint(x: origin.x + 6, y: origin.y + 4),
            withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white])
    }
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}

func benchTakeover() {
    let full = CGSize(width: 1512, height: 982)
    var worst: (String, Double) = ("", 0)
    for (i, recipe) in glitchRecipes.enumerated() {
        guard let ctx = CGContext(data: nil, width: Int(full.width / 2), height: Int(full.height / 2),
                                  bitsPerComponent: 8, bytesPerRow: Int(full.width / 2) * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
        ctx.scaleBy(x: 0.5, y: 0.5)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let start = CFAbsoluteTimeGetCurrent()
        for frame in 0..<20 {
            renderTakeover(recipe, in: CGRect(origin: .zero, size: full), time: 5 + CGFloat(frame) * 0.05,
                           seed: UInt32(i), pulse: 0, ctx: ctx)
        }
        let ms = (CFAbsoluteTimeGetCurrent() - start) / 20 * 1000
        NSGraphicsContext.restoreGraphicsState()
        print(String(format: "%2d %-22@ %6.1f ms", i + 1, recipe.name as NSString, ms))
        if ms > worst.1 { worst = (recipe.name, ms) }
    }
    print("slowest: \(worst.0) \(String(format: "%.1f", worst.1)) ms")
}
