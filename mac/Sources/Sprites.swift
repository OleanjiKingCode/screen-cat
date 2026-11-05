import AppKit

// Sprite art: "Cat Pack" (free tier) by Glem / octopusINKUS.
// https://octopusinkus.itch.io/cat-pack , see Assets/CREDIT.txt.
//
// The sheet is 384x288: a 12 x 9 grid of 32x32 frames. Frames are bottom
// aligned, with the ground line at row 30 and a standing cat about 27px tall.
// Side-view rows face right and are mirrored to walk left.

enum Clip {
    case sitIdle      // sitting, front on, tail swishing, blinks
    case standIdle    // standing, front on
    case sitDown      // sit, then settle down
    case crouch       // low crouch, front on
    case lieDown      // drop from standing to lying
    case sleep        // lying, slow breathing
    case frontWalk    // walking toward the viewer
    case sideWalk     // walking in profile
    case ballPlay     // lying on its side batting the yarn ball
    case run          // profile pounce / run
}

struct ClipInfo {
    var row: Int
    var start: Int
    var count: Int
    var fps: CGFloat
    var loops: Bool
    /// Side-view clips mirror when the cat faces left; front-view ones never do.
    var mirrors: Bool
    /// Frame index is driven by distance travelled, not by the clock, so the
    /// paws do not skate along the ground.
    var strideDriven: Bool
}

extension Clip {
    var info: ClipInfo {
        switch self {
        case .sitIdle:   return ClipInfo(row: 0, start: 0, count: 9,  fps: 7,  loops: true,  mirrors: false, strideDriven: false)
        case .standIdle: return ClipInfo(row: 1, start: 0, count: 11, fps: 7,  loops: true,  mirrors: false, strideDriven: false)
        case .sitDown:   return ClipInfo(row: 2, start: 0, count: 11, fps: 10, loops: false, mirrors: false, strideDriven: false)
        case .crouch:    return ClipInfo(row: 3, start: 0, count: 6,  fps: 7,  loops: true,  mirrors: false, strideDriven: false)
        case .lieDown:   return ClipInfo(row: 4, start: 0, count: 4,  fps: 7,  loops: false, mirrors: false, strideDriven: false)
        case .sleep:     return ClipInfo(row: 4, start: 4, count: 6,  fps: 3,  loops: true,  mirrors: false, strideDriven: false)
        case .frontWalk: return ClipInfo(row: 5, start: 0, count: 10, fps: 10, loops: true,  mirrors: false, strideDriven: true)
        case .sideWalk:  return ClipInfo(row: 6, start: 0, count: 10, fps: 10, loops: true,  mirrors: true,  strideDriven: true)
        case .ballPlay:  return ClipInfo(row: 7, start: 0, count: 11, fps: 12, loops: true,  mirrors: true,  strideDriven: false)
        case .run:       return ClipInfo(row: 8, start: 0, count: 6,  fps: 14, loops: true,  mirrors: true,  strideDriven: true)
        }
    }
}

/// Loads the sheet, recolours it once, and hands out frames.
final class SpriteSheet {
    static let frameSize = 32
    /// Row 30 of each frame is where the paws meet the ground.
    static let groundRow: CGFloat = 30
    /// A standing cat measures about this many pixels, used to map the
    /// configured cat height onto a pixel scale.
    static let standHeight: CGFloat = 27

    private(set) var sheet: CGImage?
    private(set) var ball: CGImage?
    private(set) var shadow: CGImage?
    private var frames: [Int: CGImage] = [:]
    /// The unrecoloured sheet's pixels, kept to find the face in each frame.
    private var raw: [UInt8] = []
    private var rawWidth = 0
    private var accessoryFrames: [Int: CGImage] = [:]

    /// The pet the settings ask for, in the settings' colours.
    convenience init(resources: URL, config: Config) {
        self.init(resources: resources, palette: config.spritePalette, pet: config.pet)
    }

    init(resources: URL, palette: SpritePalette, pet: String = "cat") {
        // The dog is drawn in its own colours. Only its eyes are recoloured:
        // they are pure white in the file, the same as the cat's, so the
        // glasses and chain can find the face.
        let dogSheet = resources.appendingPathComponent("Dog_Sprite_Sheet.png")
        if pet == "dog", FileManager.default.fileExists(atPath: dogSheet.path) {
            sheet = SpriteSheet.load(dogSheet, recolour: [SpritePalette.srcEye: SpritePalette.dogEye])
            ball = SpriteSheet.load(resources.appendingPathComponent("Dog_Ball.png"), recolour: [:])
            shadow = SpriteSheet.load(resources.appendingPathComponent("Cat_Shadow.png"), recolour: [:])
            loadRaw(dogSheet)
            return
        }
        // The sheet gets the coat mapping only. The yarn colours are left alone
        // there because the cat's nose and mouth are drawn in them too, and
        // tinting those turns its face the colour of the ball.
        sheet = SpriteSheet.load(resources.appendingPathComponent("Cat_Sprite_Sheet.png"),
                                 recolour: palette.coat)
        ball = SpriteSheet.load(resources.appendingPathComponent("Cat_Ball.png"),
                                recolour: palette.yarn)
        shadow = SpriteSheet.load(resources.appendingPathComponent("Cat_Shadow.png"),
                                  recolour: [:])
        loadRaw(resources.appendingPathComponent("Cat_Sprite_Sheet.png"))
    }

    /// The eyes are found by their pure white, which the recolour replaces, so
    /// the search runs on the original pixels.
    private func loadRaw(_ url: URL) {
        guard let src = NSImage(contentsOf: url),
              let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let w = cg.width, h = cg.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return }
        raw = bytes
        rawWidth = w
    }

    /// `accessory` for frame `index` of `clip`, built on first use and cached.
    /// A frame with the eyes shut borrows the face from the nearest earlier
    /// frame of the same clip that has them open.
    func accessory(_ accessory: Accessory, _ clip: Clip, _ index: Int) -> CGImage? {
        guard !raw.isEmpty else { return nil }
        let info = clip.info
        let i = info.count > 0 ? ((index % info.count) + info.count) % info.count : 0
        let key = (Accessory.allCases.firstIndex(of: accessory) ?? 0) * 10_000 + info.row * 100 + info.start + i
        if let cached = accessoryFrames[key] { return cached }

        let col = info.start + i
        let s = SpriteSheet.frameSize
        let image: CGImage? = raw.withUnsafeBufferPointer { buffer in
            guard let px = buffer.baseAddress else { return nil }
            var anchor: FaceAnchor?
            for back in 0..<info.count where anchor == nil {
                let c = info.start + ((i - back) % info.count + info.count) % info.count
                anchor = FaceAnchor.find(in: px, sheetWidth: rawWidth, col: c, row: info.row)
            }
            guard let anchor else { return nil }
            let width = rawWidth
            return makeAccessoryImage(accessory, anchor: anchor) { x, y in
                px[((info.row * s + y) * width + col * s + x) * 4 + 3]
            }
        }
        if let image { accessoryFrames[key] = image }
        return image
    }

    var isLoaded: Bool { sheet != nil }

    /// The menu bar icon: the first sitting frame as a template silhouette,
    /// with the eyes cut out so it reads as a face. Pixel-exact at 2x, so it
    /// stays crisp. macOS tints it to match the menu bar.
    func menuBarIcon() -> NSImage? {
        guard !raw.isEmpty else { return nil }
        let s = SpriteSheet.frameSize
        let info = Clip.sitIdle.info
        func px(_ x: Int, _ y: Int) -> (a: UInt8, eye: Bool) {
            let i = ((info.row * s + y) * rawWidth + info.start * s + x) * 4
            let eye = raw[i] == 255 && raw[i + 1] == 255 && raw[i + 2] == 255
            return (raw[i + 3], eye)
        }
        var minX = s, maxX = -1, minY = s, maxY = -1
        for y in 0..<s { for x in 0..<s where px(x, y).a > 0 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= 0 else { return nil }
        let w = maxX - minX + 1, h = maxY - minY + 1
        // Two image pixels per sprite pixel on a 2x screen: about 14pt tall.
        let scale = max(1, 36 / h)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w * scale, pixelsHigh: h * scale,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        for y in 0..<h { for x in 0..<w {
            let p = px(minX + x, minY + y)
            let alpha = p.eye ? 0 : (p.a > 0 ? 1.0 : 0)
            let colour = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: alpha)
            for dy in 0..<scale { for dx in 0..<scale { rep.setColor(colour, atX: x * scale + dx, y: y * scale + dy) } }
        } }
        let image = NSImage(size: NSSize(width: CGFloat(w * scale) / 2, height: CGFloat(h * scale) / 2))
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    private var backTops: [Int: (x: Int, y: Int)] = [:]

    /// The top of the back in one frame, in sheet pixels (x from the left, y
    /// down from the top), as drawn facing right: the highest body pixel in
    /// the stretch between the tail and the head. Things the pet carries
    /// ride there, so they follow every step of the walk.
    func backTop(_ clip: Clip, _ index: Int) -> (x: Int, y: Int)? {
        let info = clip.info
        let i = info.count > 0 ? ((index % info.count) + info.count) % info.count : 0
        let key = info.row * 100 + info.start + i
        if let cached = backTops[key] { return cached }
        guard let img = frame(clip, index) else { return nil }
        let s = SpriteSheet.frameSize
        guard let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: s * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: s, height: s))
        let px = data.bindMemory(to: UInt8.self, capacity: s * s * 4)
        // Row 0 of the buffer is the top of the frame.
        func top(_ x: Int) -> Int? { (0..<s).first { px[($0 * s + x) * 4 + 3] > 0 } }
        let columns = (0..<s).filter { top($0) != nil }
        guard let left = columns.first, let right = columns.last else { return nil }
        // The tail is at the left end and the head at the right, so the back
        // is the stretch just left of the middle.
        let from = left + (right - left) * 3 / 10
        let to = max(from, left + (right - left) * 11 / 20)
        guard let y = (from...to).compactMap(top).min() else { return nil }
        let found = (x: (from + to) / 2, y: y)
        backTops[key] = found
        return found
    }

    /// Frame `index` of `clip`, cropped out of the sheet and cached.
    func frame(_ clip: Clip, _ index: Int) -> CGImage? {
        guard let sheet else { return nil }
        let info = clip.info
        let i = info.count > 0 ? ((index % info.count) + info.count) % info.count : 0
        let col = info.start + i
        let key = info.row * 100 + col
        if let cached = frames[key] { return cached }
        let s = SpriteSheet.frameSize
        let rect = CGRect(x: col * s, y: info.row * s, width: s, height: s)
        guard let img = sheet.cropping(to: rect) else { return nil }
        frames[key] = img
        return img
    }

    private static func load(_ url: URL, recolour: [UInt32: UInt32]) -> CGImage? {
        guard let src = NSImage(contentsOf: url),
              let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        guard !recolour.isEmpty else { return cg }

        let w = cg.width, h = cg.height
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cg }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return cg }

        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let a = px[i + 3]
            guard a > 0 else { continue }
            // Undo premultiplication before matching, so the source colours
            // compare exactly against the palette table.
            let r = a == 255 ? px[i]     : UInt8(min(255, Int(px[i])     * 255 / Int(a)))
            let g = a == 255 ? px[i + 1] : UInt8(min(255, Int(px[i + 1]) * 255 / Int(a)))
            let b = a == 255 ? px[i + 2] : UInt8(min(255, Int(px[i + 2]) * 255 / Int(a)))
            let key = (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
            guard let to = recolour[key] else { continue }
            let nr = UInt8((to >> 16) & 0xFF), ng = UInt8((to >> 8) & 0xFF), nb = UInt8(to & 0xFF)
            px[i]     = a == 255 ? nr : UInt8(Int(nr) * Int(a) / 255)
            px[i + 1] = a == 255 ? ng : UInt8(Int(ng) * Int(a) / 255)
            px[i + 2] = a == 255 ? nb : UInt8(Int(nb) * Int(a) / 255)
        }
        return ctx.makeImage() ?? cg
    }
}

/// Maps the pack's ten source colours onto the user's configured colours.
struct SpritePalette {
    // The exact palette of the original sheet.
    static let srcOutline: UInt32 = 0x222034   // darkest, the outline
    static let srcBody: UInt32    = 0x322B28   // main coat
    static let srcDark: UInt32    = 0x221C1A   // deep shadow
    static let srcShade1: UInt32  = 0x45283C   // mid shadow
    static let srcShade2: UInt32  = 0x422433   // mid shadow
    static let srcAccent: UInt32  = 0x793A80   // paw pads / underside
    static let srcEar: UInt32     = 0xE86A73   // inner ear
    static let srcEye: UInt32     = 0xFFFFFF   // eyes
    static let srcYarnA: UInt32   = 0xBC4A9B   // yarn ball
    static let srcYarnB: UInt32   = 0xD25A87   // yarn ball highlight
    /// What the dog's white eye pixels turn into: near black.
    static let dogEye: UInt32     = 0x1B1220

    /// Coat, ears and eyes. Applied to the sheet.
    var coat: [UInt32: UInt32]
    /// Yarn only. Applied to the loose ball sprite, never to the sheet.
    var yarn: [UInt32: UInt32]

    init(fur: NSColor, furShade: NSColor, outline: NSColor,
         inner: NSColor, eye: NSColor, ball: NSColor) {
        func rgb(_ c: NSColor) -> UInt32 {
            guard let s = c.usingColorSpace(.sRGB) else { return 0 }
            return (UInt32(s.redComponent * 255) << 16)
                 | (UInt32(s.greenComponent * 255) << 8)
                 |  UInt32(s.blueComponent * 255)
        }
        func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
            a.blended(withFraction: t, of: b) ?? a
        }
        coat = [
            SpritePalette.srcOutline: rgb(outline),
            SpritePalette.srcBody:    rgb(fur),
            SpritePalette.srcDark:    rgb(mix(furShade, outline, 0.55)),
            SpritePalette.srcShade1:  rgb(furShade),
            SpritePalette.srcShade2:  rgb(mix(furShade, outline, 0.25)),
            SpritePalette.srcAccent:  rgb(mix(fur, furShade, 0.45)),
            SpritePalette.srcEar:     rgb(inner),
            SpritePalette.srcEye:     rgb(eye),
        ]
        yarn = [
            SpritePalette.srcOutline: rgb(outline),
            SpritePalette.srcYarnA:   rgb(ball),
            SpritePalette.srcYarnB:   rgb(mix(ball, .white, 0.32)),
            SpritePalette.srcAccent:  rgb(mix(ball, .black, 0.28)),
        ]
    }
}

// MARK: - Drawing

/// Draws `image` as crisp pixel art: nearest-neighbour, snapped to whole pixels
/// so the sprite never shimmers as it moves.
func drawPixelImage(_ image: CGImage, in ctx: CGContext, rect: CGRect, mirrored: Bool, alpha: CGFloat) {
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.interpolationQuality = .none
    ctx.setShouldAntialias(false)
    let snapped = CGRect(x: rect.origin.x.rounded(), y: rect.origin.y.rounded(),
                         width: rect.width.rounded(), height: rect.height.rounded())
    if mirrored {
        ctx.translateBy(x: snapped.midX, y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.translateBy(x: -snapped.midX, y: 0)
    }
    ctx.draw(image, in: snapped)
    ctx.restoreGState()
}
