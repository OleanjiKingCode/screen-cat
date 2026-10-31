import AppKit

/// Everything the renderer needs to know about the cat right now.
final class CatState {
    /// Global screen coordinates of the point under the cat's paws.
    var pos = CGPoint.zero
    /// 1 = facing right, -1 = facing left. Only side-view clips use it.
    var facing: CGFloat = 1
    var clip: Clip = .standIdle
    var clipTime: CGFloat = 0
    /// Distance walked in the current clip, used to drive walk and run frames.
    var stride: CGFloat = 0
    /// Standing height in points, before perspective.
    var size: CGFloat = 120
    /// Shrinks the cat slightly as it moves up the screen, so travelling "up"
    /// reads as walking away rather than levitating.
    var depth: CGFloat = 1
    var visible = false
    /// What it has on for this visit. Picked when a routine starts.
    var wearing: Set<Accessory> = []
    /// The dog takes shorter steps than the cat, so a cycle covers less ground.
    var isDog = false

    func setClip(_ c: Clip) {
        guard c != clip else { return }
        clip = c
        clipTime = 0
        stride = 0
    }

    var drawnSize: CGFloat { size * depth }
    var pixelScale: CGFloat { drawnSize / SpriteSheet.standHeight }

    /// How far the cat travels per full cycle of the current walk or run.
    var cycleDistance: CGFloat {
        switch clip {
        case .run: return drawnSize * (isDog ? 0.88 : 2.0)
        case .frontWalk: return drawnSize * 0.9
        default: return drawnSize * (isDog ? 0.6 : 1.15)
        }
    }

    var frameIndex: Int {
        let info = clip.info
        if info.strideDriven {
            let cycles = stride / max(1, cycleDistance)
            return Int(cycles * CGFloat(info.count)) % max(1, info.count)
        }
        let i = Int(clipTime * info.fps)
        return info.loops ? i % max(1, info.count) : min(i, info.count - 1)
    }

    var finishedOnce: Bool {
        let info = clip.info
        return !info.loops && clipTime * info.fps >= CGFloat(info.count)
    }

    func advance(_ dt: CGFloat) { clipTime += dt }

    /// Generous bounding box in global coordinates, for dirty-rect redraws.
    var bounds: CGRect {
        let s = pixelScale * CGFloat(SpriteSheet.frameSize)
        return CGRect(x: pos.x - s, y: pos.y - s * 0.35, width: s * 2, height: s * 2.2)
    }
}

// MARK: - Cat

func drawCat(_ c: CatState, sheet: SpriteSheet, drawShadow: Bool,
             palette: Palette, in ctx: CGContext) {
    guard let frame = sheet.frame(c.clip, c.frameIndex) else { return }
    let ps = c.pixelScale
    let side = CGFloat(SpriteSheet.frameSize) * ps
    // The frame's ground line is row 30 of 32, so the sprite sits two source
    // pixels below the paws.
    let rect = CGRect(x: c.pos.x - side / 2,
                      y: c.pos.y - (CGFloat(SpriteSheet.frameSize) - SpriteSheet.groundRow) * ps,
                      width: side, height: side)

    if drawShadow, let shadow = sheet.shadow {
        let w = side * 0.72
        let h = w * CGFloat(shadow.height) / CGFloat(shadow.width)
        drawPixelImage(shadow, in: ctx,
                       rect: CGRect(x: c.pos.x - w / 2, y: c.pos.y - h * 0.45, width: w, height: h),
                       mirrored: false, alpha: 0.35)
    }

    let mirrored = c.clip.info.mirrors && c.facing < 0
    drawPixelImage(frame, in: ctx, rect: rect, mirrored: mirrored, alpha: 1)
    // Chain first, so the glasses win anywhere the two overlap.
    for item in [Accessory.chain, .glasses] where c.wearing.contains(item) {
        if let overlay = sheet.accessory(item, c.clip, c.frameIndex) {
            drawPixelImage(overlay, in: ctx, rect: rect, mirrored: mirrored, alpha: 1)
        }
    }

    if c.clip == .sleep { drawZzz(c, palette, in: ctx) }
}

// MARK: - Pixel extras the sprite pack does not include

/// A 5x7 pixel "z". Big enough that a one-pixel halo reads as an outline rather
/// than swallowing the letter.
private let zGlyph = [
    "#####",
    "....#",
    "...#.",
    "..#..",
    ".#...",
    "#....",
    "#####",
]

private func drawZzz(_ c: CatState, _ pal: Palette, in ctx: CGContext) {
    let ps = c.pixelScale
    // The sleeping cat's head is at the front, so trail the z's off that side.
    let dir: CGFloat = c.facing < 0 ? -1 : 1
    let headX = c.pos.x + dir * ps * 8
    for i in 0..<3 {
        let cycle: CGFloat = 2.7
        let local = (c.clipTime + CGFloat(i) * cycle / 3).truncatingRemainder(dividingBy: cycle) / cycle
        let alpha = sin(local * .pi)
        guard alpha > 0.05 else { continue }
        let px = ps * (0.8 + local * 0.5)
        let x = headX + dir * local * ps * 7
        let y = c.pos.y + ps * 13 + local * ps * 14
        // White letter, dark outline: readable over light and dark wallpaper.
        drawGlyph(zGlyph, at: CGPoint(x: x, y: y), pixel: px,
                  fill: NSColor(white: 1, alpha: 0.95), halo: pal.outline,
                  alpha: alpha, in: ctx)
    }
}

/// A 5x5 pixel heart, floated up over the cat while it is being petted.
private let heartGlyph = [
    ".#.#.",
    "#####",
    "#####",
    ".###.",
    "..#..",
]

/// Two hearts rising and fading, staggered. `time` is seconds into the pet.
func drawHearts(above c: CatState, time: CGFloat, palette pal: Palette, in ctx: CGContext) {
    let ps = c.pixelScale
    for i in 0..<2 {
        let local = (time - CGFloat(i) * 0.5) / 1.6
        guard local > 0, local < 1 else { continue }
        let side: CGFloat = i == 0 ? -1 : 1
        let x = c.pos.x + side * ps * 5 - ps * 2.5
        let y = c.pos.y + ps * 24 + local * ps * 10
        drawGlyph(heartGlyph, at: CGPoint(x: x, y: y), pixel: ps * 0.9,
                  fill: pal.inner, halo: pal.outline, alpha: sin(local * .pi), in: ctx)
    }
}

/// A little pixel food bowl, so the begging routine reads as "hungry".
private let bowlGlyph = [
    "..rrrrrrr..",
    ".rrrrrrrrr.",
    ".rbbbbbbbr.",
    "..bbbbbbb..",
    "...bbbbb...",
    "....bbb....",
]

func drawFoodBowl(at point: CGPoint, pixel: CGFloat, palette pal: Palette, alpha: CGFloat, in ctx: CGContext) {
    let w = CGFloat(bowlGlyph[0].count) * pixel
    let origin = CGPoint(x: point.x - w / 2, y: point.y)
    ctx.saveGState()
    ctx.setShouldAntialias(false)
    ctx.setAlpha(alpha)
    for (rowIndex, row) in bowlGlyph.reversed().enumerated() {
        for (colIndex, ch) in row.enumerated() {
            guard ch != "." else { continue }
            (ch == "r" ? pal.inner : pal.outline).setFill()
            CGRect(x: (origin.x + CGFloat(colIndex) * pixel).rounded(),
                   y: (origin.y + CGFloat(rowIndex) * pixel).rounded(),
                   width: pixel.rounded(), height: pixel.rounded()).fill()
        }
    }
    ctx.restoreGState()
}

private func drawGlyph(_ glyph: [String], at point: CGPoint, pixel: CGFloat,
                       fill: NSColor, halo: NSColor, alpha: CGFloat, in ctx: CGContext) {
    // Snap the pixel size and the origin to whole points first, so every cell
    // lands on the same grid instead of rounding independently into mush.
    let p = max(2, pixel.rounded())
    let ox = point.x.rounded(), oy = point.y.rounded()
    ctx.saveGState()
    ctx.setShouldAntialias(false)
    ctx.setAlpha(alpha)
    halo.setFill()
    for dx in [CGFloat(-1), 0, 1] {
        for dy in [CGFloat(-1), 0, 1] where !(dx == 0 && dy == 0) {
            paint(glyph, ox + dx * p, oy + dy * p, p)
        }
    }
    fill.setFill()
    paint(glyph, ox, oy, p)
    ctx.restoreGState()
}

private func paint(_ glyph: [String], _ ox: CGFloat, _ oy: CGFloat, _ pixel: CGFloat) {
    for (rowIndex, row) in glyph.reversed().enumerated() {
        for (colIndex, ch) in row.enumerated() where ch != "." {
            CGRect(x: ox + CGFloat(colIndex) * pixel,
                   y: oy + CGFloat(rowIndex) * pixel,
                   width: pixel, height: pixel).fill()
        }
    }
}

// MARK: - Ball

struct BallState {
    var pos = CGPoint.zero
    /// Drawn width in points.
    var size: CGFloat = 26
    var rotation: CGFloat = 0
    var visible = false

    var bounds: CGRect {
        CGRect(x: pos.x - size, y: pos.y - size, width: size * 2, height: size * 2)
    }
}

func drawBall(_ b: BallState, sheet: SpriteSheet, in ctx: CGContext) {
    guard let img = sheet.ball else { return }
    ctx.saveGState()
    ctx.interpolationQuality = .none
    ctx.setShouldAntialias(false)
    ctx.translateBy(x: b.pos.x, y: b.pos.y)
    ctx.rotate(by: b.rotation)
    let h = b.size * CGFloat(img.height) / CGFloat(img.width)
    ctx.draw(img, in: CGRect(x: -b.size / 2, y: -h / 2, width: b.size, height: h))
    ctx.restoreGState()
}

/// Colours used by the bits that are drawn rather than blitted.
struct Palette {
    var outline: NSColor
    var inner: NSColor
}
