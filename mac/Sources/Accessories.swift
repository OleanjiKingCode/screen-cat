import AppKit

/// Things the cat can wear. Each one is baked into a 32x32 overlay per sprite
/// frame and drawn on top of that frame with the same rect and mirroring, so it
/// stays glued to the face through every walk cycle, blink and head bob.
enum Accessory: CaseIterable {
    case chain, glasses
}

/// Where the face is in one frame, found from the eye pixels of the source sheet.
///
/// Designs are written in (u, v): u runs along the line joining the eyes, with
/// the eyes at u = -2 and +2, and v runs toward the chin, with v = 0 the bottom
/// row of the eyes. That one frame of reference covers the upright frames and
/// the ball-play frames, where the cat lies on its side and the face is turned
/// a quarter with the chin pointing left.
struct FaceAnchor {
    var x: Int
    var y: Int
    var upright: Bool

    /// (u, v) to frame pixels, y counted down from the top.
    func point(_ u: Int, _ v: Int) -> (x: Int, y: Int) {
        upright ? (x + u, y + v) : (x - v, y + u)
    }

    /// Finds the face in the frame at (col, row). Nil when the eyes are fully
    /// shut, since there is then nothing to find.
    ///
    /// Eyes are the only pure white pixels on the sheet. They close from the
    /// top down, so the bottom row of an eye stays put through a blink and
    /// makes a steady anchor.
    static func find(in px: UnsafePointer<UInt8>, sheetWidth: Int, col: Int, row: Int) -> FaceAnchor? {
        let s = SpriteSheet.frameSize
        var minX = s, maxX = -1, minY = s, maxY = -1
        for y in 0..<s {
            for x in 0..<s {
                let i = ((row * s + y) * sheetWidth + col * s + x) * 4
                guard px[i + 3] == 255, px[i] == 255, px[i + 1] == 255, px[i + 2] == 255 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        // Upright eyes sit side by side, four pixels apart. Stacked ones are
        // the ball-play frames, where the lids close toward -x.
        if maxX - minX >= 4 {
            return FaceAnchor(x: (minX + maxX) / 2, y: maxY, upright: true)
        }
        return FaceAnchor(x: minX, y: (minY + maxY) / 2, upright: false)
    }
}

private struct RGB {
    var r: UInt8, g: UInt8, b: UInt8
    init(_ hex: UInt32) {
        r = UInt8((hex >> 16) & 0xFF); g = UInt8((hex >> 8) & 0xFF); b = UInt8(hex & 0xFF)
    }
}

private let goldLight = RGB(0xFFD34E)
private let goldDark = RGB(0xC98A1B)
private let goldShine = RGB(0xFFF4B0)
private let shadesFrame = RGB(0x111018)
private let shadesLens = RGB(0x2A2440)
private let shadesGlint = RGB(0xB8E4FF)

/// Paints one accessory for one frame into a 32x32 image.
/// `alpha(x, y)` is the frame's own opacity, used to keep the chain on the body.
func makeAccessoryImage(_ accessory: Accessory, anchor: FaceAnchor,
                        frameAlpha alpha: (Int, Int) -> UInt8) -> CGImage? {
    let s = SpriteSheet.frameSize
    guard let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8,
                              bytesPerRow: s * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let data = ctx.data else { return nil }
    let px = data.bindMemory(to: UInt8.self, capacity: s * s * 4)

    func put(_ u: Int, _ v: Int, _ c: RGB, onBodyOnly: Bool = false) {
        let p = anchor.point(u, v)
        guard p.x >= 0, p.x < s, p.y >= 0, p.y < s else { return }
        if onBodyOnly && alpha(p.x, p.y) == 0 { return }
        let i = (p.y * s + p.x) * 4
        px[i] = c.r; px[i + 1] = c.g; px[i + 2] = c.b; px[i + 3] = 255
    }

    switch accessory {
    case .chain:
        // A U of links hanging under the chin, light and dark alternating so
        // it reads as a chain and not a line, with a small pendant at the
        // bottom. Clipped to the body so it never floats in the air.
        let links: [(Int, Int)] = [(-4, 2), (-3, 3), (-2, 4), (-1, 4), (0, 4),
                                   (1, 4), (2, 4), (3, 3), (4, 2)]
        for (u, v) in links {
            put(u, v, (u & 1) == 0 ? goldLight : goldDark, onBodyOnly: true)
        }
        put(-1, 5, goldDark, onBodyOnly: true)
        put(1, 5, goldDark, onBodyOnly: true)
        put(0, 5, goldShine, onBodyOnly: true)
        put(0, 6, goldLight, onBodyOnly: true)

    case .glasses:
        // Small shades, just over the eyes: a 3x3 lens per eye with a dark
        // top rim, a one-pixel bridge between them, and a glint top left.
        for e in [-2, 2] {
            for u in (e - 1)...(e + 1) {
                put(u, -2, shadesFrame)
                put(u, -1, shadesLens)
                put(u, 0, shadesLens)
            }
            put(e - 1, -1, shadesGlint)
        }
        put(0, -2, shadesFrame)

    }
    return ctx.makeImage()
}
