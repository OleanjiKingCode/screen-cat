import AppKit

// Crawler mode's "hack" effects. Everything here is paint on the cat's own
// overlay: the app underneath is never touched, it only looks broken for a few
// seconds and then "reboots".

/// The look of one breach. Picked at random each time, so a long crawl does
/// not repeat itself.
enum GlitchStyle: CaseIterable {
    /// Cracks, RGB slices, scrolling hacker code, "SYSTEM BREACHED".
    case breach
    /// Columns of falling characters.
    case matrix
    /// A crash screen: ":(", "CAT.EXE HAS STOPPED" and a counting percentage.
    case blueScreen
    /// TV static, colour bars and "NO SIGNAL".
    case noSignal
    /// The window melts down in drips of colour.
    case melt
}

/// The colours a breach can come in.
let glitchAccents: [NSColor] = [
    NSColor(srgbRed: 0.0, green: 1.0, blue: 0.25, alpha: 1),    // terminal green
    NSColor(srgbRed: 1.0, green: 0.0, blue: 0.2, alpha: 1),     // blood red
    NSColor(srgbRed: 1.0, green: 0.69, blue: 0.0, alpha: 1),    // warning amber
    NSColor(srgbRed: 1.0, green: 0.23, blue: 0.0, alpha: 1),    // fire orange
    NSColor(white: 1, alpha: 1),                                // white
    NSColor(srgbRed: 0.71, green: 1.0, blue: 0.23, alpha: 1),   // acid green
]

private let alarmRed = NSColor(srgbRed: 1.0, green: 0.23, blue: 0.36, alpha: 1)

/// One window the cat has broken, in the same coordinates as the cat.
struct Breach {
    var rect: CGRect
    /// Where the zap landed. The cracks spread out from here.
    var touch: CGPoint
    var seed: UInt32
    var style: GlitchStyle = .breach
    /// Index into `glitchAccents`.
    var accentIndex = 0
    var age: CGFloat = 0
    let duration: CGFloat = 4.2

    var finished: Bool { age >= duration }
    var accent: NSColor { glitchAccents[accentIndex % glitchAccents.count] }

    /// A breach in a random style and colour.
    static func random(rect: CGRect, touch: CGPoint) -> Breach {
        Breach(rect: rect, touch: touch, seed: UInt32.random(in: 1...UInt32.max),
               style: GlitchStyle.allCases.randomElement()!,
               accentIndex: Int.random(in: 0..<glitchAccents.count))
    }
}

/// Anything that has breaches and a zap to paint: both crawl routines.
protocol BreachSource: AnyObject {
    var breaches: [Breach] { get }
    var zap: Zap? { get }
    /// The glow while the cat powers up, if it is.
    var aura: Aura? { get }
}

extension BreachSource {
    var aura: Aura? { nil }
}

/// Rings pulsing out from the cat while it grows.
struct Aura {
    var center: CGPoint
    /// Roughly the cat's height now, so the rings scale with it.
    var size: CGFloat
    var progress: CGFloat
    var age: CGFloat
    var accentIndex: Int

    var bounds: CGRect {
        CGRect(x: center.x - size * 2, y: center.y - size * 2, width: size * 4, height: size * 4)
    }
}

/// Three rings expanding and fading, with a flicker of sparks.
func drawAura(_ a: Aura, in ctx: CGContext) {
    let accent = glitchAccents[a.accentIndex % glitchAccents.count]
    ctx.saveGState()
    for k in 0..<3 {
        let phase = (a.age * 1.6 + CGFloat(k) / 3).truncatingRemainder(dividingBy: 1)
        let radius = a.size * (0.4 + phase * 1.5)
        accent.withAlphaComponent((1 - phase) * 0.8).setStroke()
        let ring = NSBezierPath(ovalIn: CGRect(x: a.center.x - radius, y: a.center.y - radius,
                                               width: radius * 2, height: radius * 2))
        ring.lineWidth = 3
        ring.stroke()
    }
    var sparks = GlitchRandom(UInt32(a.age / 0.06) &+ 99)
    accent.setFill()
    for _ in 0..<14 {
        let angle = sparks.range(0, .pi * 2), d = a.size * sparks.range(0.5, 1.6)
        CGRect(x: a.center.x + cos(angle) * d - 2, y: a.center.y + sin(angle) * d - 2, width: 4, height: 4).fill()
    }
    ctx.restoreGState()
}

/// The bolt from the cat's head to the window, while it is "hacking" it.
struct Zap {
    var from: CGPoint
    var to: CGPoint
    var age: CGFloat = 0
    var accentIndex = 0

    var accent: NSColor { glitchAccents[accentIndex % glitchAccents.count] }

    var bounds: CGRect {
        CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
               width: abs(to.x - from.x), height: abs(to.y - from.y)).insetBy(dx: -16, dy: -16)
    }
}

/// Small deterministic random source. Seeded from the breach plus a time
/// bucket, so the glitch flickers a few times a second but each frame is stable.
struct GlitchRandom {
    private var state: UInt64

    init(_ seed: UInt32) {
        // SplitMix64 scramble, so neighbouring seeds (column 1, column 2, ...)
        // start far apart instead of drawing near-identical first numbers.
        var z = UInt64(seed) &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        state = z ^ (z >> 31)
    }

    mutating func unit() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }

    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * unit() }
}

/// Fictional, harmless "hacker" lines for the scrolling code.
private let fakeCode = [
    "> connecting to 185.220.101.47:22 ...",
    "$ nmap -sS -p- 10.0.0.0/24 --open",
    "PORT     STATE SERVICE",
    "22/tcp   open  ssh",
    "443/tcp  open  https",
    "$ ssh -i id_rsa root@10.0.0.14",
    "Permission denied (publickey).",
    "$ hydra -l admin -P rockyou.txt ssh://10.0.0.14",
    "[22][ssh] login: admin  password: ********",
    "bypassing firewall ... rule 0x1F dropped",
    "decrypt(0x3F2A9C) -> ok",
    "dumping /etc/shadow ...",
    "root:$6$Zx9Q...:19622:0:99999:7:::",
    "privilege escalation: CVE-20XX-0000 ... ok",
    "uid=0(root) gid=0(root)",
    "$ curl -s http://10.0.0.14/admin.php?id=1' OR '1'='1",
    "injecting payload stage2.bin (48 KB)",
    "spawning reverse shell -> 185.220.101.47:4444",
    "keylogger attached to pid 4127",
    "exfiltrating /Users/*/Documents (2.3 GB)",
    "wiping logs: /var/log/*.log",
    "kernel: segfault at 0x00007ffd in libsystem",
    "ERROR 0xDEAD: process not responding",
    "rerouting traffic through 7 proxies",
    "hash cracked: 5f4dcc3b5aa765d61d8327deb882cf99",
    "AES-256 key found: 9b2e...c41f",
    "mounting /dev/disk2s1 /mnt/target",
    "GET /api/v1/users  200 OK",
    "0101 1100 0011 1010 1110",
    "establishing persistence: launchd.plist",
]

/// Paints a breach in its style. Every style fades in, darkens the window,
/// does its thing, then shows "REBOOTING..." and fades back to the real app.
func drawBreach(_ b: Breach, in ctx: CGContext) {
    let fadeIn = min(1, b.age / 0.25)
    let fadeOut = min(1, max(0, (b.duration - b.age) / 0.6))
    let envelope = fadeIn * fadeOut
    guard envelope > 0.01 else { return }
    let r = b.rect
    var flicker = GlitchRandom(b.seed &+ UInt32(b.age / 0.07))

    ctx.saveGState()
    ctx.setAlpha(envelope)
    ctx.clip(to: r)

    // Falling code only reads against near black.
    NSColor(white: 0, alpha: b.style == .matrix ? 0.88 : 0.55).setFill()
    r.fill()

    switch b.style {
    case .breach:
        drawScanlines(r)
        drawSlices(r, flicker: &flicker)
        drawCracks(b, in: ctx)
        drawCode(b, in: r)
        drawBanner(b, in: r, flicker: &flicker, ctx: ctx,
                   options: ["SYSTEM BREACHED", "HACKED!"], colour: alarmRed)
    case .matrix:
        drawMatrix(b, in: r, ctx: ctx)
        drawBanner(b, in: r, flicker: &flicker, ctx: ctx,
                   options: ["ACCESS GRANTED", "ACCESS OK"], colour: b.accent)
    case .blueScreen:
        drawBlueScreen(b, in: r, ctx: ctx)
        drawBanner(b, in: r, flicker: &flicker, ctx: ctx, options: [], colour: b.accent)
    case .noSignal:
        drawNoSignal(b, in: r, flicker: &flicker)
        drawBanner(b, in: r, flicker: &flicker, ctx: ctx,
                   options: ["NO SIGNAL", "NO SIGNAL"], colour: b.accent)
    case .melt:
        drawMelt(b, in: r)
        drawScanlines(r)
        drawBanner(b, in: r, flicker: &flicker, ctx: ctx,
                   options: ["MELTDOWN", "MELT"], colour: b.accent)
    }

    // A flickering border, like a target lock.
    b.accent.withAlphaComponent(flicker.range(0.5, 1)).setStroke()
    let border = NSBezierPath(rect: r.insetBy(dx: 1.5, dy: 1.5))
    border.lineWidth = 3
    border.stroke()
    ctx.restoreGState()
}

private func drawScanlines(_ r: CGRect) {
    NSColor(white: 0, alpha: 0.3).setFill()
    var y = r.minY
    while y < r.maxY {
        CGRect(x: r.minX, y: y, width: r.width, height: 1).fill()
        y += 4
    }
}

/// Sliced, shifted bars in the two halves of an RGB split.
private func drawSlices(_ r: CGRect, flicker: inout GlitchRandom) {
    let tints = [NSColor(srgbRed: 1, green: 0, blue: 0.2, alpha: 0.3),
                 NSColor(srgbRed: 0, green: 1, blue: 0.25, alpha: 0.28),
                 NSColor(white: 1, alpha: 0.12)]
    for i in 0..<10 {
        tints[i % tints.count].setFill()
        let h = flicker.range(3, 24)
        CGRect(x: r.minX + flicker.range(-50, 50), y: flicker.range(r.minY, r.maxY - h),
               width: r.width * flicker.range(0.3, 1.05), height: h).fill()
    }
}

/// Jagged cracks from the touch point. Their shape comes from the seed alone,
/// so they grow without wobbling.
private func drawCracks(_ b: Breach, in ctx: CGContext) {
    let grow = min(1, max(0, (b.age - 0.15) / 0.9))
    let eased = 1 - pow(1 - grow, 3)
    guard eased > 0 else { return }
    let reach = max(b.rect.width, b.rect.height) * 0.55 * eased
    var shape = GlitchRandom(b.seed)
    let base = shape.range(0, .pi * 2)
    let count = 7
    for k in 0..<count {
        let path = NSBezierPath()
        path.move(to: b.touch)
        var angle = base + CGFloat(k) * .pi * 2 / CGFloat(count) + shape.range(-0.3, 0.3)
        var point = b.touch
        let segments = 7
        for _ in 0..<segments {
            angle += shape.range(-0.5, 0.5)
            let step = reach / CGFloat(segments) * shape.range(0.6, 1.3)
            point = CGPoint(x: point.x + cos(angle) * step, y: point.y + sin(angle) * step)
            path.line(to: point)
        }
        path.lineJoinStyle = .miter
        NSColor(white: 0, alpha: 0.7).setStroke()
        path.lineWidth = 3.5
        path.stroke()
        NSColor(white: 1, alpha: 0.9).setStroke()
        path.lineWidth = 1.2
        path.stroke()
    }
}

/// Code scrolling up the left side, newest line at the bottom, typed out.
private func drawCode(_ b: Breach, in r: CGRect) {
    let lineHeight: CGFloat = 15
    let rows = Int((r.height - 20) / lineHeight)
    guard rows > 0, b.age > 0.3 else { return }
    let typed = (b.age - 0.3) * 11
    let shown = min(rows, Int(typed) + 1)
    let first = Int(b.seed % UInt32(fakeCode.count))
    let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
    for row in 0..<shown {
        let index = Int(typed) - row
        var text = fakeCode[(first + max(0, index)) % fakeCode.count]
        if row == 0 {
            // The newest line types itself out, cursor and all.
            let chars = Int((typed - floor(typed)) * CGFloat(text.count))
            text = String(text.prefix(chars)) + "_"
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: b.accent.withAlphaComponent(row == 0 ? 1 : max(0.35, 0.95 - CGFloat(row) * 0.03)),
        ]
        NSString(string: text).draw(at: CGPoint(x: r.minX + 14, y: r.minY + 10 + CGFloat(row) * lineHeight),
                                    withAttributes: attrs)
    }
}

/// Glyph images rendered once per character and colour, because drawing a
/// screenful of text through NSString every frame is far too slow.
private enum GlyphCache {
    static var images: [String: CGImage] = [:]
    static let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)

    static func image(_ ch: Character, colour: NSColor, key: Int) -> CGImage? {
        let id = "\(ch)|\(key)"
        if let hit = images[id] { return hit }
        let text = NSString(string: String(ch))
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        let size = CGSize(width: 14, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            text.draw(at: CGPoint(x: 2, y: 1), withAttributes: attrs)
            return true
        }
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        images[id] = cg
        return cg
    }
}

private let rainGlyphs = Array("01アイウエオカキクケコサシスセソタチツテト$#@*<>=+ABCDEFXYZ")

/// Columns of falling characters, bright at the head and fading up the trail.
private func drawMatrix(_ b: Breach, in r: CGRect, ctx: CGContext) {
    let colW = max(16, r.width / 60)
    let rowH: CGFloat = 18
    let cols = Int(r.width / colW)
    var columnRandom = GlitchRandom(b.seed)
    let charTick = UInt32(b.age / 0.09)
    for c in 0..<cols {
        let speed = columnRandom.range(140, 420)
        let start = columnRandom.range(0, r.height)
        let trail = Int(columnRandom.range(5, 13))
        let span = r.height + CGFloat(trail) * rowH
        let headY = r.maxY - (b.age * speed + start).truncatingRemainder(dividingBy: span)
        var chars = GlitchRandom(b.seed &+ UInt32(c) &* 977 &+ charTick)
        let x = r.minX + CGFloat(c) * colW
        for k in 0..<trail {
            let y = headY + CGFloat(k) * rowH
            guard y > r.minY - rowH, y < r.maxY else { continue }
            let ch = rainGlyphs[Int(chars.unit() * CGFloat(rainGlyphs.count - 1))]
            let isHead = k == 0
            guard let img = GlyphCache.image(ch, colour: isHead ? .white : b.accent,
                                             key: isHead ? -1 : b.accentIndex) else { continue }
            ctx.saveGState()
            ctx.setAlpha(isHead ? 1 : max(0.15, 1 - CGFloat(k) / CGFloat(trail)))
            ctx.draw(img, in: CGRect(x: x, y: y, width: 14, height: 18))
            ctx.restoreGState()
        }
    }
}

/// A pixel-font crash screen that counts its way up to "100%".
private func drawBlueScreen(_ b: Breach, in r: CGRect, ctx: CGContext) {
    NSColor(srgbRed: 0.08, green: 0.33, blue: 0.82, alpha: 1).setFill()
    r.fill()
    let percent = min(100, Int(max(0, b.age - 0.4) / 2.6 * 100))
    let lines = ["SYSTEM HALTED", "STOP CODE: 0XC000021A", "DUMPING MEMORY \(percent)%"]
    let widest = CGFloat(lines.map { PixelFont.width(of: $0) }.max() ?? 1)
    let pixel = max(2, min(6, floor(r.width * 0.8 / widest)))
    let left = r.minX + max(12, r.width * 0.08)
    var y = r.maxY - max(20, r.height * 0.18)
    let face = pixel * 3
    y -= CGFloat(PixelFont.height) * face
    PixelFont.draw(":(", at: CGPoint(x: left, y: y), pixel: face, color: .white, in: ctx)
    y -= pixel * 6
    for line in lines {
        y -= CGFloat(PixelFont.height) * pixel + pixel * 3
        guard y > r.minY + 6, CGFloat(PixelFont.width(of: line)) * pixel < r.width - 12 else { continue }
        PixelFont.draw(line, at: CGPoint(x: left, y: y), pixel: pixel, color: .white, in: ctx)
    }
}

/// TV static with a band of colour bars and a rolling bright bar.
private func drawNoSignal(_ b: Breach, in r: CGRect, flicker: inout GlitchRandom) {
    let block = max(10, r.width / 70)
    var y = r.minY
    while y < r.maxY {
        var x = r.minX
        while x < r.maxX {
            if flicker.unit() < 0.45 {
                NSColor(white: flicker.range(0.15, 0.9), alpha: 0.85).setFill()
                CGRect(x: x, y: y, width: block, height: block).fill()
            }
            x += block
        }
        y += block
    }
    let bars: [NSColor] = [NSColor(white: 0.85, alpha: 1), glitchAccents[1], .black, glitchAccents[0],
                           glitchAccents[2], NSColor(srgbRed: 0.55, green: 0, blue: 0, alpha: 1), .black]
    let band = CGRect(x: r.minX, y: r.midY - r.height * 0.15, width: r.width, height: r.height * 0.3)
    let barW = band.width / CGFloat(bars.count)
    let shift = flicker.range(-12, 12)
    for (i, colour) in bars.enumerated() {
        colour.withAlphaComponent(0.85).setFill()
        CGRect(x: band.minX + CGFloat(i) * barW + shift, y: band.minY, width: barW + 1, height: band.height).fill()
    }
    let roll = r.minY + (b.age * r.height * 0.6).truncatingRemainder(dividingBy: r.height)
    NSColor(white: 1, alpha: 0.18).setFill()
    CGRect(x: r.minX, y: roll, width: r.width, height: max(8, r.height * 0.05)).fill()
}

/// Drips of colour sliding down from the top edge, each at its own pace.
private func drawMelt(_ b: Breach, in r: CGRect) {
    let colW = max(8, r.width / 60)
    let cols = Int(ceil(r.width / colW))
    let progress = min(1, b.age / (b.duration - 1.2))
    let eased = 1 - pow(1 - progress, 2)
    var columns = GlitchRandom(b.seed)
    let dark = b.accent.blended(withFraction: 0.45, of: .black) ?? b.accent
    for c in 0..<cols {
        let length = r.height * eased * columns.range(0.25, 1.05)
        let x = r.minX + CGFloat(c) * colW
        dark.withAlphaComponent(0.9).setFill()
        CGRect(x: x, y: r.maxY - length, width: colW + 0.5, height: length).fill()
        b.accent.setFill()
        CGRect(x: x, y: r.maxY - length, width: colW + 0.5, height: min(length, colW * 0.6)).fill()
        // A drop falling ahead of the drip now and then.
        if columns.unit() < 0.3 {
            let fall = (b.age * 260 * columns.range(0.6, 1.4)).truncatingRemainder(dividingBy: r.height)
            b.accent.withAlphaComponent(0.8).setFill()
            CGRect(x: x + colW * 0.25, y: r.maxY - length - fall, width: colW * 0.5, height: colW * 0.8).fill()
        }
    }
}

/// The style's banner in the pixel font, then "REBOOTING..." before it clears.
/// Empty `options` shows only the rebooting part.
private func drawBanner(_ b: Breach, in r: CGRect, flicker: inout GlitchRandom, ctx: CGContext,
                        options: [String], colour: NSColor) {
    let rebooting = b.age > b.duration - 1.1
    guard b.age > 0.6 else { return }
    if !rebooting && options.isEmpty { return }
    // Blink on and off now and then, the way a warning does.
    if !rebooting && flicker.unit() < 0.12 { return }
    // The long wording when it fits at the smallest pixel size, else a short one.
    let choices = rebooting ? ["REBOOTING...", "REBOOT"] : options
    let text = choices.first { CGFloat(PixelFont.width(of: $0) + 6) * 2 <= r.width * 0.9 } ?? choices[choices.count - 1]
    let tint = rebooting ? b.accent : colour
    let widthPx = CGFloat(PixelFont.width(of: text))
    let pixel = max(2, min(5, floor(r.width * 0.6 / widthPx)))
    let w = widthPx * pixel, h = CGFloat(PixelFont.height) * pixel
    let box = CGRect(x: r.midX - w / 2 - pixel * 3, y: r.midY - h / 2 - pixel * 3,
                     width: w + pixel * 6, height: h + pixel * 6)
    NSColor(white: 0, alpha: 0.85).setFill()
    box.fill()
    tint.setStroke()
    let frame = NSBezierPath(rect: box.insetBy(dx: pixel / 2, dy: pixel / 2))
    frame.lineWidth = pixel
    frame.stroke()
    PixelFont.draw(text, at: CGPoint(x: (r.midX - w / 2).rounded(), y: (r.midY - h / 2).rounded()),
                   pixel: pixel, color: tint, in: ctx)
}

/// A jittery bolt from the cat to the window it is hacking.
func drawZap(_ z: Zap, in ctx: CGContext) {
    var jitter = GlitchRandom(UInt32(z.age / 0.05) &+ 7)
    let path = NSBezierPath()
    path.move(to: z.from)
    let segments = 9
    let dx = z.to.x - z.from.x, dy = z.to.y - z.from.y
    let len = max(1, hypot(dx, dy))
    let nx = -dy / len, ny = dx / len
    for i in 1..<segments {
        let t = CGFloat(i) / CGFloat(segments)
        let off = jitter.range(-8, 8)
        path.line(to: CGPoint(x: z.from.x + dx * t + nx * off, y: z.from.y + dy * t + ny * off))
    }
    path.line(to: z.to)
    ctx.saveGState()
    z.accent.withAlphaComponent(0.3).setStroke()
    path.lineWidth = 7
    path.stroke()
    z.accent.setStroke()
    path.lineWidth = 2
    path.stroke()
    // Sparks where it lands.
    z.accent.setFill()
    for _ in 0..<6 {
        let a = jitter.range(0, .pi * 2), d = jitter.range(3, 14)
        CGRect(x: z.to.x + cos(a) * d - 1.5, y: z.to.y + sin(a) * d - 1.5, width: 3, height: 3).fill()
    }
    ctx.restoreGState()
}
