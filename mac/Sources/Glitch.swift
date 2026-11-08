import AppKit

// Crawler mode's "hack" effects. Everything here is paint on the cat's own
// overlay: the app underneath is never touched, it only looks broken for a few
// seconds and then "reboots".

/// The colours a bolt or an aura can come in.
let glitchAccents: [NSColor] = [
    NSColor(srgbRed: 0.0, green: 1.0, blue: 0.25, alpha: 1),    // terminal green
    NSColor(srgbRed: 1.0, green: 0.0, blue: 0.2, alpha: 1),     // blood red
    NSColor(srgbRed: 1.0, green: 0.69, blue: 0.0, alpha: 1),    // warning amber
    NSColor(srgbRed: 1.0, green: 0.23, blue: 0.0, alpha: 1),    // fire orange
    NSColor(white: 1, alpha: 1),                                // white
    NSColor(srgbRed: 0.71, green: 1.0, blue: 0.23, alpha: 1),   // acid green
]

/// The `glitchAccents` entry closest to `colour`, so the bolt that breaks a
/// window is the colour of the look it starts.
func accentIndex(nearest colour: NSColor) -> Int {
    let target = colour.usingColorSpace(.sRGB) ?? colour
    func distance(_ index: Int) -> CGFloat {
        let c = glitchAccents[index].usingColorSpace(.sRGB) ?? glitchAccents[index]
        return pow(c.redComponent - target.redComponent, 2) + pow(c.greenComponent - target.greenComponent, 2)
            + pow(c.blueComponent - target.blueComponent, 2)
    }
    return glitchAccents.indices.min { distance($0) < distance($1) } ?? 0
}

/// One window the cat has broken, in the same coordinates as the cat. It plays
/// one of the fifty full-screen looks (`glitchRecipes`), cut to the window.
struct Breach {
    var rect: CGRect
    var seed: UInt32
    /// Index into `glitchRecipes`.
    var recipeIndex: Int
    var age: CGFloat = 0
    let duration: CGFloat = 5
    /// The end of it: the look goes dark behind "REBOOTING..." and fades out.
    let rebootSeconds: CGFloat = 1.1
    /// The latest rendered frame, shared by every copy of this breach.
    let frames = BreachFrames()

    var finished: Bool { age >= duration }
    var recipe: GlitchRecipe { glitchRecipes[recipeIndex % glitchRecipes.count] }
    /// The look's main colour, for the border and "REBOOTING...".
    var accent: NSColor { recipe.palette[0] }
    /// Fades in over a quarter second and out over the last 0.6 s.
    var opacity: CGFloat { min(1, age / 0.25) * min(1, max(0, (duration - age) / 0.6)) }
    /// Seconds into the look. It runs at double speed, the idle crawl's
    /// default `glitchSpeed`, so even a short breach shows the look move.
    var lookTime: CGFloat { age * 2 }
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

/// The latest frame of one breach. A look renders at most 20 times a second,
/// however often it is shown, like the full-screen takeover.
final class BreachFrames {
    private(set) var image: CGImage?
    private var renderedAt: CGFloat = 0

    /// Seconds since the frame shown was rendered; infinite before the first.
    func staleness(_ b: Breach) -> CGFloat { image == nil ? .infinity : abs(b.age - renderedAt) }

    /// True once the frame shown is a twentieth of a second old.
    func isStale(_ b: Breach) -> Bool { staleness(b) >= 0.045 }

    func render(_ b: Breach) {
        image = renderBreachFrame(b)
        renderedAt = b.age
    }

    /// The frame for `b`, rendered again only when it is stale.
    func current(_ b: Breach) -> CGImage? {
        if isStale(b) { render(b) }
        return image
    }
}

/// How many times the window's size a look is laid out at. The looks are made
/// for a whole screen, so in a small window they are laid out bigger and shrunk
/// to fit, instead of their text and boxes spilling off the edge. Whole powers
/// of two, so the chunky pixels stay square on the screen.
private func breachLayout(_ size: CGSize) -> CGFloat {
    let side = min(size.width, size.height)
    return side >= 400 ? 1 : side >= 200 ? 2 : 4
}

/// One frame of a breach, the window's shape: the look at half resolution, laid
/// out at `breachLayout` times the window's size, then a flickering border and,
/// at the end, "REBOOTING...".
func renderBreachFrame(_ b: Breach) -> CGImage? {
    let layout = breachLayout(b.rect.size)
    let look = CGRect(x: 0, y: 0, width: b.rect.width * layout, height: b.rect.height * layout)
    let w = Int((look.width / 2).rounded(.up)), h = Int((look.height / 2).rounded(.up))
    guard w > 0, h > 0,
          let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.scaleBy(x: 0.5, y: 0.5)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    // The zap lands with a flash.
    renderTakeover(b.recipe, in: look, time: b.lookTime, seed: b.seed, pulse: max(0, 1 - b.age / 0.4), ctx: ctx)
    drawBorderAndReboot(b, in: look, layout: layout, ctx: ctx)
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()
}

/// A flickering border, like a target lock. At the end the look goes dark
/// behind a boxed "REBOOTING..." before the real window comes back.
private func drawBorderAndReboot(_ b: Breach, in r: CGRect, layout: CGFloat, ctx: CGContext) {
    var flicker = GlitchRandom(b.seed &+ UInt32(b.age / 0.07))
    let rebooting = b.age - (b.duration - b.rebootSeconds)
    if rebooting > 0 {
        // Dark enough that the look's own banner does not fight this one.
        NSColor(white: 0, alpha: min(0.88, rebooting / 0.4)).setFill()
        r.fill()
        // The long wording when it fits at a readable size, else a short one.
        let maxWidth = r.width * 0.6
        let text = CGFloat(PixelFont.width(of: "REBOOTING...")) * 4 <= maxWidth ? "REBOOTING..." : "REBOOT"
        pixelText(text, centre: CGPoint(x: r.midX, y: r.midY), maxWidth: maxWidth, maxPixel: 5 * layout,
                  colour: b.accent, ctx: ctx, box: true)
    }
    b.accent.withAlphaComponent(flicker.range(0.5, 1)).setStroke()
    let border = NSBezierPath(rect: r.insetBy(dx: 1.5 * layout, dy: 1.5 * layout))
    border.lineWidth = 3 * layout
    border.stroke()
}

/// Paints a breach straight into `ctx` from its latest frame, for the
/// playground and the offscreen renders. The app itself shows the same frames
/// on their own layers under the cat, so its 60 fps redraw never covers them.
func drawBreach(_ b: Breach, in ctx: CGContext) {
    guard b.opacity > 0.01, let image = b.frames.current(b) else { return }
    ctx.saveGState()
    ctx.setAlpha(b.opacity)
    ctx.interpolationQuality = .none
    ctx.draw(image, in: b.rect)
    ctx.restoreGState()
}

/// `--takeover-bench`, second part: milliseconds per frame for each look as a
/// breach on a few window sizes. The app renders at most one breach a frame.
func benchBreaches() {
    let windows = [CGSize(width: 1100, height: 720), CGSize(width: 640, height: 420), CGSize(width: 300, height: 220)]
    for size in windows {
        var worst: (String, Double) = ("", 0)
        var total: Double = 0
        for i in glitchRecipes.indices {
            var b = Breach(rect: CGRect(origin: .zero, size: size), seed: UInt32(i + 1), recipeIndex: i)
            let start = CFAbsoluteTimeGetCurrent()
            for frame in 0..<20 {
                b.age = 1 + CGFloat(frame) * 0.05
                _ = renderBreachFrame(b)
            }
            let ms = (CFAbsoluteTimeGetCurrent() - start) / 20 * 1000
            total += ms
            if ms > worst.1 { worst = (glitchRecipes[i].name, ms) }
        }
        print(String(format: "breach %4.0f x %3.0f: average %5.1f ms, slowest %@ %.1f ms", size.width, size.height,
                     total / Double(glitchRecipes.count), worst.0 as NSString, worst.1))
    }
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
