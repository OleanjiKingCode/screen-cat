// Draws the dog sprites for Screen Cat and checks them.
//
// Run from the repo root:
//     swift mac/Tools/make_dog.swift
// or with enlarged previews written to a folder:
//     swift mac/Tools/make_dog.swift --preview /some/dir
//
// Writes mac/Assets/Dog_Sprite_Sheet.png (384x288, a 12 x 9 grid of 32x32
// frames, same layout as Cat_Sprite_Sheet.png) and mac/Assets/Dog_Ball.png
// (13x13 tennis ball). All art is original and drawn here as character grids.
//
// Rules the sheet follows, and the checks at the bottom enforce:
// - Every frame is bottom aligned: the lowest opaque pixel is row 30.
// - Eyes are the only pure white (#FFFFFF) pixels. The app finds the face by
//   them and recolours them at load time. Nothing else on the sheet is #FFFFFF.
// - Front rows have two eyes side by side, 4px apart. The ball-play row has the
//   face turned a quarter (crown to +x, chin to -x), so the eyes stack and the
//   lids close toward -x, like the cat sheet.

import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

let palette: [Character: UInt32] = [
    "k": 0x222034, // outline, nose
    "W": 0xFFFFFF, // eyes (only pure white on the sheet)
    "T": 0xD4914F, // tan coat
    "t": 0xA8663A, // tan shade, far legs
    "D": 0x6B3D28, // dark brown: ears, saddle
    "d": 0x4B2A22, // ear shade
    "C": 0xF2DFC0, // cream: muzzle, chest, paws, tail tip
    "c": 0xD5B78D, // cream shade
    "P": 0xEC7C8A, // tongue
    "Y": 0xC8DC3E, // tennis ball
    "y": 0x8FA72A, // tennis ball shade
    "O": 0xF4EFE6, // off-white: ball seam
]

// MARK: - Canvas

typealias Grid = [String]

struct Pix {
    var ch: Character
    var part: Int
}

let S = 32
/// Lowest fill row. The auto outline puts the ground line one below, on row 30.
let floorY = 29

final class Frame {
    var px = [Pix?](repeating: nil, count: S * S)

    func at(_ x: Int, _ y: Int) -> Pix? {
        guard x >= 0, x < S, y >= 0, y < S else { return nil }
        return px[y * S + x]
    }

    func put(_ x: Int, _ y: Int, _ ch: Character, part: Int = 0) {
        guard x >= 0, x < S, y >= 0, y < S else { return }
        px[y * S + x] = Pix(ch: ch, part: part)
    }

    /// Stamps a grid with its top-left at (ox, oy). '.' and ' ' are holes.
    /// With `ring`, a one pixel outline is drawn around the grid over whatever
    /// is already there, except parts listed in `merge`, so a front part reads
    /// as in front. The outer silhouette is always closed by `finish()`.
    func stamp(_ g: Grid, _ ox: Int, _ oy: Int, part: Int = 0,
               ring: Bool = false, merge: Set<Int> = []) {
        var mask = Set<Int>()
        for (r, line) in g.enumerated() {
            for (c, ch) in line.enumerated() where ch != "." && ch != " " {
                let x = ox + c, y = oy + r
                guard x >= 0, x < S, y >= 0, y < S else { continue }
                mask.insert(y * S + x)
            }
        }
        if ring {
            for i in mask {
                let x = i % S, y = i / S
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < S, ny >= 0, ny < S else { continue }
                    let j = ny * S + nx
                    if mask.contains(j) { continue }
                    guard let p = px[j] else { continue }
                    if merge.contains(p.part) || p.part == part { continue }
                    px[j] = Pix(ch: "k", part: part)
                }
            }
        }
        for (r, line) in g.enumerated() {
            for (c, ch) in line.enumerated() where ch != "." && ch != " " {
                precondition(palette[ch] != nil, "unknown colour '\(ch)' in a grid")
                put(ox + c, oy + r, ch, part: part)
            }
        }
    }

    /// Closes the outer silhouette: every empty pixel touching a non-outline
    /// pixel (4-neighbour) becomes outline.
    func finish() {
        var add: [Int] = []
        for y in 0..<S {
            for x in 0..<S where at(x, y) == nil {
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    if let p = at(x + dx, y + dy), p.ch != "k" { add.append(y * S + x); break }
                }
            }
        }
        for i in add { px[i] = Pix(ch: "k", part: -1) }
    }
}

// MARK: - Grid helpers

func flipX(_ g: Grid) -> Grid { g.map { String($0.reversed()) } }

/// Rotates a grid a quarter turn clockwise: its top ends up on the right.
func rotateCW(_ g: Grid) -> Grid {
    let h = g.count
    let w = g.map { $0.count }.max() ?? 0
    let rows = g.map { Array($0.padding(toLength: w, withPad: ".", startingAt: 0)) }
    var out: [String] = []
    for x in 0..<w {
        var line = ""
        for y in (0..<h).reversed() { line.append(rows[y][x]) }
        out.append(line)
    }
    return out
}

func recolour(_ g: Grid, _ map: [Character: Character]) -> Grid {
    g.map { String($0.map { map[$0] ?? $0 }) }
}

/// Mirrors the left half of each row onto the right (odd widths keep the centre column).
func mirrored(_ half: Grid) -> Grid {
    half.map { line in
        let chars = Array(line)
        return String(chars + chars.dropLast().reversed())
    }
}

// MARK: - PNG output

func rgba(_ hex: UInt32) -> (UInt8, UInt8, UInt8) {
    (UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF))
}

/// Writes an RGBA PNG. `pixel(x, y)` returns a hex colour or nil for clear.
func writePNG(width w: Int, height h: Int, to url: URL, scale: Int = 1,
              background: ((Int, Int) -> UInt32?)? = nil,
              pixel: (Int, Int) -> UInt32?) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w * scale, pixelsHigh: h * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: w * scale * 4, bitsPerPixel: 32)!
    let data = rep.bitmapData!
    for y in 0..<(h * scale) {
        for x in 0..<(w * scale) {
            let i = (y * w * scale + x) * 4
            let sx = x / scale, sy = y / scale
            if let c = pixel(sx, sy) ?? background?(x, y) {
                let (r, g, b) = rgba(c)
                data[i] = r; data[i + 1] = g; data[i + 2] = b; data[i + 3] = 255
            } else {
                data[i] = 0; data[i + 1] = 0; data[i + 2] = 0; data[i + 3] = 0
            }
        }
    }
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: url)
}

// MARK: - Previews

/// Eye colour used in previews to show the frames the way the app draws them.
let previewEye: UInt32 = 0x1B1220

/// Writes frames side by side, enlarged, on a checker with a red frame border
/// and a blue line under the ground row. `darkEyes` shows them as in the app.
func writeStrip(_ frames: [Frame?], to url: URL, scale: Int = 8, darkEyes: Bool = false, columns: Int? = nil) {
    let cols = columns ?? max(1, frames.count)
    let rows = (frames.count + cols - 1) / cols
    let w = cols * S, h = rows * S
    func px(_ x: Int, _ y: Int) -> UInt32? {
        let fi = (y / S) * cols + x / S
        guard fi < frames.count, let f = frames[fi], let p = f.at(x % S, y % S) else { return nil }
        if p.ch == "W" && darkEyes { return previewEye }
        return palette[p.ch]
    }
    writePNG(width: w, height: h, to: url, scale: scale, background: { x, y in
        let sx = x / scale, sy = y / scale
        if x % (S * scale) == 0 { return 0xE05050 }
        if (sy % S) == 31 && y % scale == 0 { return 0x5090E0 }
        return ((sx + sy) % 2 == 0) ? 0xE6E9EE : 0xD3D8E0
    }, pixel: px)
}

// MARK: - Front head

// 13 wide, centred on its column 6. Stamped at x 10 it covers x 10...22 with the
// eyes at x 14 and x 18. Row 5 is the bottom row of the eyes (v = 0 for the
// accessories): the nose is at v+1, the mouth at v+2 and v+3, and the chin's
// outline at v+4, which is where the chain hangs.
enum Eyes { case open, half, shut, sleep }
enum Mouth { case closed, tongue }
enum Ears { case down, perk }

func frontHead(_ eyes: Eyes = .open, mouth: Mouth = .closed, ears: Ears = .down) -> Grid {
    var e4: Character = "W", e5: Character = "W"
    switch eyes {
    case .open: break
    case .half: e4 = "T"
    case .shut, .sleep: e4 = "T"; e5 = "T"
    }
    var half: Grid
    switch ears {
    case .down:
        half = [
            "....TTT",
            "...TTTT",
            ".DDTTTT",
            "DDkTTTC",
            "DDkT\(e4)TC",
            "DDkT\(e5)CC",
            "DDkCCkk",
            "DdkCCCk",
            ".DDkCkC",
        ]
    case .perk:
        half = [
            "....TTT",
            ".DDTTTT",
            "DDDkTTT",
            "DDkTTTC",
            "DdkT\(e4)TC",
            ".DkT\(e5)CC",
            "..kCCkk",
            "..kCCCk",
            "...kCkC",
        ]
    }
    var g = mirrored(half)
    if eyes == .shut || eyes == .sleep {
        // Shut eyes are little curved lids, low in the middle. A blink draws
        // them in outline (no white). Sleep draws them in eye white, so the
        // app still finds the face and keeps the glasses on while the dog
        // sleeps; it recolours them dark, so on screen they read the same.
        let lid: Character = eyes == .sleep ? "W" : "k"
        var r4 = Array(g[4]), r5 = Array(g[5])
        for c in [3, 5, 7, 9] { r4[c] = lid }
        for c in [4, 8] { r5[c] = lid }
        g[4] = String(r4); g[5] = String(r5)
    }
    if mouth == .tongue {
        var r8 = Array(g[8]); r8[6] = "P"; g[8] = String(r8)
        g.append("......P......")
    }
    return g
}

// MARK: - Composition

struct Layer {
    var grid: Grid
    var x: Int
    var y: Int
    var part: Int
    var ring = true
    var merge: Set<Int> = []
}

func compose(_ layers: [Layer], finish: Bool = true) -> Frame {
    let f = Frame()
    for l in layers {
        f.stamp(l.grid, l.x, l.y, part: l.part, ring: l.ring, merge: l.merge)
    }
    if finish { f.finish() }
    return f
}

// Part ids, back to front.
let pTail = 1, pFarLeg = 2, pBody = 3, pNearLeg = 4, pHead = 5, pBall = 6

// MARK: - Sitting and standing, front on

// Sitting: 17 wide (x 8...24), rows 14...29.
let sitBody: Grid = mirrored([
    ".....TCCC",
    "....TTCCC",
    "...TTCCCC",
    "...TTCCCC",
    "..TTTTCCC",
    "..TTTTCCC",
    ".TTTTTTCC",
    ".TTTTTTTk",
    "TTTTtTTTk",
    "TTTTkTTTk",
    "TTTTkTTTk",
    "TTTtkTTTk",
    "TTTtkTTTk",
    "tTttkTTTk",
    ".CCkkCCCk",
    ".CCk.CCCk",
])

// Standing: rows 13...29. The hind legs show as a sliver outside the front ones.
let standBody: Grid = mirrored([
    ".....TCCC",
    "....TTCCC",
    "...TTTCCC",
    "...TTTCCC",
    "..TTTTTCC",
    ".TTTTTTCC",
    ".TTTTTTTC",
    ".tTTTTTTt",
    ".tTTTTTtk",
    ".tTkTTTk.",
    ".ttkTTTk.",
    "..tkTTTk.",
    "..tkTTTk.",
    "..tkTTTk.",
    "..tkTTTk.",
    "..ckCCCk.",
    "...kCCCk.",
])

/// The standing body down to the belly (rows 13...21); the walk adds legs.
let standTorso: Grid = Array(standBody[0...8])

/// Front leg, 3 wide, top at row 22. `lift` raises the paw off the floor.
func frontLeg(lift: Int) -> Grid {
    Array(repeating: "TTT", count: 4 - lift) + ["TTT", "TTT", "CCC", "CCC"]
}

/// Hind leg sliver beside a front leg, top at row 22, a row short of the floor.
func hindLegFront(lift: Int, flip: Bool = false) -> Grid {
    var g: Grid = ["tT", "tt"] + Array(repeating: ".t", count: 4 - lift) + [".c"]
    if flip { g = flipX(g) }
    return g
}

// Sitting tail, out to the right of the haunch. Stamped at (22, 20).
let sitTails: [Grid] = [
    [
        "........",
        "........",
        "........",
        "........",
        "........",
        "......CC",
        ".....TTC",
        "..TTTTT.",
        "TTTTT...",
    ],
    [
        "........",
        "........",
        "........",
        ".....CC.",
        ".....TC.",
        "....TT..",
        "...TTT..",
        ".TTTT...",
        "TTT.....",
    ],
    [
        "....CC..",
        "....CT..",
        "....TT..",
        "...TT...",
        "...TT...",
        "..TTT...",
        ".TTT....",
        "TTT.....",
        "TT......",
    ],
]

// Standing tail, held up behind the head and showing over it. Stamped at
// (19, 1 + bob). 0 is upright, 3 leans furthest right.
let standTails: [Grid] = [
    ["..CC..", "..TC..", "..TT..", "..TT..", "..TT..", ".TT...", ".TT...", "TT...."],
    ["...CC.", "...CT.", "...TT.", "..TT..", "..TT..", ".TT...", ".TT...", "TT...."],
    ["....CC", "...TTC", "...TT.", "..TT..", "..TT..", ".TT...", ".TT...", "TT...."],
    [".....C", "....TC", "...TT.", "..TT..", ".TT...", ".TT...", "TT....", "TT...."],
]

// MARK: - Sit-down in-betweens

// The thighs start to bulge as the rear drops (1), then the haunches land (2).
let sitDownBody1: Grid = mirrored([
    ".....TCCC",
    "....TTCCC",
    "...TTTCCC",
    "...TTTCCC",
    "..TTTTTCC",
    ".TTTTTTCC",
    ".TTTTTTTC",
    "TTTTTTTTt",
    "TTtTTTTtk",
    "TTtkTTTk.",
    "TTtkTTTk.",
    ".ttkTTTk.",
    ".ttkTTTk.",
    "..tkTTTk.",
    "..tkTTTk.",
    ".cckCCCk.",
    "...kCCCk.",
])

let sitDownBody2: Grid = mirrored([
    ".....TCCC",
    "....TTCCC",
    "...TTTCCC",
    "...TTCCCC",
    "..TTTTCCC",
    "..TTTTTCC",
    ".TTTTTTCC",
    ".TTTTTTTk",
    "TTTTtTTTk",
    "TTTTkTTTk",
    "TTTTkTTTk",
    "TTTtkTTTk",
    "tTTtkTTTk",
    ".tttkTTTk",
    ".cckkCCCk",
    "....kCCCk",
])

// MARK: - Three-quarter poses (face to the viewer, body off to the left)

// Lowering to lie down: elbows bending out, rear sinking. Rows 16...29.
let lieDownBody1: Grid = mirrored([
    ".....TCCC",
    "....TTCCC",
    "...TTTCCC",
    "..TTTTCCC",
    "..TTTTTCC",
    ".TTTTTTCC",
    ".TTTTTTTC",
    "TTtTTTTTt",
    "TTtTTTTtk",
    "TTkTTTTk.",
    "TtkTTTTk.",
    ".tkTTTk..",
    ".ckCCCCk.",
    "...CCCCk.",
])

// Forelegs lying flat toward the viewer, chest down between them. x 11...21.
let flatForelegs: Grid = [
    ".TTTCCCTTT.",
    "TTTTCCCTTTT",
    "TTTkCCCkTTT",
    "CCCkcCckCCC",
    "CCCkccckCCC",
    "CCCk...kCCC",
]

// Play bow: rump up at the left, back sloping down behind the head. At (2, 12).
let bowBody: Grid = [
    "..DDDD.......",
    ".DDDDDDD.....",
    "TTDDDDDDDD...",
    "TTTTDDDDDDDD.",
    "TTTTTTDDDDDDD",
    "TTTTTTTTDDDDD",
    ".TTTTTTTTTTTT",
    "...ttTTTTTTTT",
    ".....ttTTTTTT",
    ".......ttTTTT",
    ".........ttTT",
]

// Near hind leg, long from the rump, stifle forward and hock back. At (2, 17).
let bowNearHind: Grid = [
    "TTTT..",
    "TTTT..",
    ".TTTT.",
    "..TTT.",
    "..TTT.",
    "..TT..",
    ".TT...",
    ".TT...",
    ".TT...",
    ".TT...",
    ".CC...",
    ".CCC..",
    ".CCCC.",
]

// Far hind leg, in shade. At (7, 19).
let bowFarHind: Grid = [
    "tt",
    "tt",
    "tt",
    "tt",
    "tt",
    "tt",
    "tt",
    "tt",
    "tt",
    "cc",
]

// Tail up off the rump, wagging. At (1, 5).
let bowTails: [Grid] = [
    ["..CC..", "..TC..", "..TT..", "..TT..", "..TT..", "..TT..", "..TT..", "..TT.."],
    ["CC....", "CT....", ".TT...", ".TT...", "..TT..", "..TT..", "..TT..", "..TT.."],
    ["....CC", "...TTC", "...TT.", "..TT..", "..TT..", "..TT..", "..TT..", "..TT.."],
]

// Lying: a long low loaf off to the left, saddle on the back, the hind leg
// folded with its paw forward. At (3, 20); `inhale` lifts the back a pixel.
func lieBody(inhale: Bool = false) -> Grid {
    var g: Grid = [
        "...DDDDDDDD...",
        ".DDDDDDDDDDDD.",
        "TDDDDDDDDDDDDD",
        "TTTDDDDDDDDDTT",
        "TTTTTTTTTTTTTT",
        "TTTTTTTTTTTTTT",
        "TkkkTTTTTTTTTT",
        "kTTTkTTTTTTTTT",
        "TTTTkkCCCTTTTT",
        "ttttkCCCCttttt",
    ]
    if inhale { g.insert(g[4], at: 4) }
    return g
}

// Tail curled up off the rump like a question mark. At (1, 15).
let lieTails: [Grid] = [
    ["..CC.", ".TTC.", "TT...", "TT...", "TT...", ".TT..", ".TT..", "..T.."],
    ["...CC", "..TTC", ".TT..", "TT...", "TT...", ".TT..", ".TT..", "..T.."],
]

// Front paws under a resting chin. x 11...21, rows 26...29.
let restingPaws: Grid = [
    "TTTTTkTTTTT",
    "CCCCCkCCCCC",
    "CCCCCkCCCCC",
    "CCCCCkCCCCC",
]

// MARK: - Rows: front on

func sitFrame(tail: Int, eyes: Eyes = .open, headY: Int = 5) -> Frame {
    compose([
        Layer(grid: sitTails[tail], x: 22, y: 20, part: pTail, ring: false),
        Layer(grid: sitBody, x: 8, y: 14, part: pBody),
        Layer(grid: frontHead(eyes), x: 10, y: headY, part: pHead),
    ])
}

/// Row 0: sitting, tail sweeping the floor, one blink. 9 frames at 7 fps.
func rowSitIdle() -> [Frame] {
    let tails = [0, 1, 2, 1, 0, 1, 2, 1, 0]
    let eyes: [Eyes] = [.open, .open, .open, .half, .shut, .half, .open, .open, .open]
    return (0..<9).map { sitFrame(tail: tails[$0], eyes: eyes[$0]) }
}

/// Standing, built from torso + four legs so the walk can lift them.
func standFrame(tail: Int?, eyes: Eyes = .open, bob: Int = 0, headBob: Int = 0,
                lifts: (fl: Int, fr: Int, hl: Int, hr: Int) = (0, 0, 0, 0)) -> Frame {
    var layers: [Layer] = []
    if let tail { layers.append(Layer(grid: standTails[tail], x: 19, y: 1 + bob, part: pTail, ring: false)) }
    layers.append(Layer(grid: hindLegFront(lift: lifts.hl), x: 9, y: 22, part: pFarLeg, ring: false))
    layers.append(Layer(grid: hindLegFront(lift: lifts.hr, flip: true), x: 22, y: 22, part: pFarLeg, ring: false))
    layers.append(Layer(grid: frontLeg(lift: lifts.fl), x: 12, y: 22, part: pNearLeg, merge: [pBody]))
    layers.append(Layer(grid: frontLeg(lift: lifts.fr), x: 18, y: 22, part: pNearLeg + 10, merge: [pBody]))
    layers.append(Layer(grid: standTorso, x: 8, y: 13 + bob, part: pBody,
                        merge: [pTail, pFarLeg, pNearLeg, pNearLeg + 10]))
    layers.append(Layer(grid: frontHead(eyes), x: 10, y: 4 + bob + headBob, part: pHead))
    return compose(layers)
}

/// Row 1: standing, tail wagging over the back, a breath and a blink. 11 frames at 7 fps.
func rowStandIdle() -> [Frame] {
    let tails = [0, 1, 2, 3, 3, 2, 1, 0, 1, 2, 1]
    let head = [0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0]
    let eyes: [Eyes] = [.open, .open, .open, .open, .open, .open, .open, .half, .shut, .half, .open]
    return (0..<11).map { standFrame(tail: tails[$0], eyes: eyes[$0], headBob: head[$0]) }
}

/// Row 2: from standing, the rear drops into a sit and settles. 11 frames at 10 fps, once.
func rowSitDown() -> [Frame] {
    var out: [Frame] = []
    out.append(standFrame(tail: 0))
    out.append(compose([
        Layer(grid: standTails[2], x: 19, y: 3, part: pTail, ring: false),
        Layer(grid: sitDownBody1, x: 8, y: 13, part: pBody),
        Layer(grid: frontHead(), x: 10, y: 5, part: pHead),
    ]))
    out.append(compose([
        Layer(grid: sitTails[2], x: 22, y: 20, part: pTail, ring: false),
        Layer(grid: sitDownBody2, x: 8, y: 14, part: pBody),
        Layer(grid: frontHead(), x: 10, y: 6, part: pHead),
    ]))
    out.append(sitFrame(tail: 2, headY: 6))
    out.append(sitFrame(tail: 1, headY: 6))
    out.append(sitFrame(tail: 0, headY: 5))
    out.append(sitFrame(tail: 0))
    out.append(sitFrame(tail: 1))
    out.append(sitFrame(tail: 2))
    out.append(sitFrame(tail: 1))
    out.append(sitFrame(tail: 0))
    return out
}

/// Row 3: play bow, rump up and tail going, a small bounce. 6 frames at 7 fps.
/// Shifted right 3px so the whole dog, not just the head, sits near the centre.
func rowCrouch() -> [Frame] {
    let tails = [0, 1, 0, 2, 0, 1]
    let bounce = [0, 0, 1, 1, 1, 0]
    let dx = 3
    return (0..<6).map { i in
        compose([
            Layer(grid: bowTails[tails[i]], x: 1 + dx, y: 5, part: pTail, ring: false),
            Layer(grid: bowFarHind, x: 7 + dx, y: 19, part: pFarLeg, ring: false),
            Layer(grid: bowBody, x: 2 + dx, y: 12, part: pBody, merge: [pTail, pFarLeg]),
            Layer(grid: bowNearHind, x: 2 + dx, y: 17, part: pNearLeg, merge: [pBody]),
            Layer(grid: flatForelegs, x: 11 + dx, y: 24, part: pNearLeg + 10, merge: []),
            Layer(grid: frontHead(.open, mouth: .tongue, ears: .perk), x: 10 + dx, y: 15 + bounce[i], part: pHead),
        ])
    }
}

/// Lying, body off to the left; shifted right 3px to sit near the centre.
func lieFrame(headY: Int, eyes: Eyes, inhale: Bool = false, resting: Bool, tail: Int = 0) -> Frame {
    let dx = 3
    return compose([
        Layer(grid: lieTails[tail], x: 1 + dx, y: 15, part: pTail, ring: false),
        Layer(grid: lieBody(inhale: inhale), x: 3 + dx, y: inhale ? 19 : 20, part: pBody, merge: [pTail]),
        resting ? Layer(grid: restingPaws, x: 11 + dx, y: 26, part: pNearLeg + 10, merge: [])
                : Layer(grid: flatForelegs, x: 11 + dx, y: 24, part: pNearLeg + 10, merge: []),
        Layer(grid: frontHead(eyes), x: 10 + dx, y: headY, part: pHead),
    ])
}

/// Row 4: lie down from standing (0-3, 7 fps), then sleep (4-9, 3 fps).
func rowLieAndSleep() -> [Frame] {
    var out: [Frame] = []
    out.append(standFrame(tail: 0))
    out.append(compose([
        Layer(grid: lieDownBody1, x: 8, y: 16, part: pBody),
        Layer(grid: frontHead(), x: 10, y: 8, part: pHead),
    ]))
    out.append(lieFrame(headY: 13, eyes: .open, resting: false))
    out.append(lieFrame(headY: 15, eyes: .half, resting: true))
    let breath = [false, false, true, true, true, false]
    let tails = [0, 0, 0, 1, 1, 0]
    for i in 0..<6 {
        out.append(lieFrame(headY: 16, eyes: .sleep, inhale: breath[i], resting: true, tail: tails[i]))
    }
    return out
}

/// Row 5: walking toward the viewer, diagonal pairs stepping. 10 frames.
func rowFrontWalk() -> [Frame] {
    let a = [1, 2, 2, 1, 0, 0, 0, 0, 0, 0]
    let b = [0, 0, 0, 0, 0, 1, 2, 2, 1, 0]
    let bob = [0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    let tails = [0, 1, 2, 3, 2, 1, 0, 1, 2, 1]
    return (0..<10).map { i in
        standFrame(tail: tails[i], bob: bob[i],
                   lifts: (fl: a[i], fr: b[i], hl: min(1, b[i]), hr: min(1, a[i])))
    }
}

// MARK: - Profile parts (facing right, face turned to the viewer)

// Profile tails off the rump. Stamped at (1, 9 + bob). 0 is upright.
let sideTails: [Grid] = [
    ["..CC..", "..TC..", "..TT..", "..TT..", "...TT.", "...TT.", "....TT", "....TT"],
    ["CC....", "TC....", ".TT...", ".TT...", "..TT..", "...TT.", "...TTT", "....TT"],
    ["......", "......", "CC....", "TTT...", ".TTT..", "..TTT.", "...TTT", "....TT"],
]

// Walking torso: deep chest under the head, belly tucked up behind it,
// a haunch line over the hind leg. At (3, 16).
let walkTorso: Grid = [
    "...DDDDDDDDDDDDD......",
    ".TDDDDDDDDDDDDDDDT....",
    "TTTDDDDDDDDDDDDDTTTT..",
    "TTTTTtTTTTTTTTTTTTTTCC",
    "TTTTTTtTTTTTTTTTTTTCCC",
    "TTTTTTtTTTTTTTTTTTTCCC",
    ".TTTTtTT.......TTTTCC.",
]

/// One walking leg from the hip (top row `hipY`) to a paw `lift` off the
/// floor, toe `footX`. Hind legs are thick to the hock, then slim, with the
/// hock set back; front legs are straight. Paws are cream with a toe forward.
func walkLeg(hipX: Int, hipY: Int, footX: Int, lift: Int, hind: Bool, far: Bool) -> (Grid, Int, Int) {
    let footY = floorY - lift
    let fur: Character = far ? "t" : "T", paw: Character = far ? "c" : "C"
    var cells: [(Int, Int, Character)] = []
    let rows = footY - hipY
    let hockT = 0.6
    let hockX = Double(hipX + footX) / 2 - 1
    for r in 0...rows {
        let y = hipY + r
        let t = Double(r) / Double(max(1, rows))
        var x: Double
        if hind {
            x = t < hockT ? Double(hipX) + (hockX - Double(hipX)) * (t / hockT)
                          : hockX + (Double(footX) - hockX) * ((t - hockT) / (1 - hockT))
        } else {
            x = Double(hipX) + Double(footX - hipX) * t
        }
        let xi = Int((x + 0.5).rounded(.down))
        var w = far ? 2 : (hind && t < hockT ? 3 : (hind ? 2 : 3))
        let isPaw = y >= footY - 1
        if y == footY { w += 1 }
        for i in 0..<w { cells.append((xi + i, y, isPaw ? paw : fur)) }
    }
    let minX = cells.map { $0.0 }.min()!, maxX = cells.map { $0.0 }.max()!
    var g = Array(repeating: Array(repeating: Character("."), count: maxX - minX + 1), count: rows + 1)
    for (x, y, c) in cells { g[y - hipY][x - minX] = c }
    return (g.map { String($0) }, minX, hipY)
}

// MARK: - Rows: profile

/// Where each foot is, relative to its hip, through one 10-frame walk cycle:
/// six frames planted, sweeping back 8px (1.6px a frame, so the cycle covers
/// 16 sheet pixels of ground), then four in the air swinging forward.
let walkFootX = [4, 2, 1, -1, -2, -4, -2, 0, 2, 4]
let walkLift  = [0, 0, 0, 0, 0, 0, 1, 2, 2, 1]

struct LegPose { var dx: Int; var lift: Int }

func walkPose(_ frame: Int, phase: Int) -> LegPose {
    let i = (frame + phase) % 10
    return LegPose(dx: walkFootX[i], lift: walkLift[i])
}

/// A profile body with four legs. Hips are given relative to the torso; `bob`
/// moves the torso, head and tail down.
func sideFrame(nearHind: LegPose, nearFront: LegPose, farHind: LegPose, farFront: LegPose,
               bob: Int, tail: Int, eyes: Eyes = .open, mouth: Mouth = .closed,
               ears: Ears = .down) -> Frame {
    func leg(_ hx: Int, _ p: LegPose, far: Bool, hind: Bool) -> (Grid, Int, Int) {
        walkLeg(hipX: hx, hipY: 21 + bob, footX: hx + p.dx, lift: p.lift, hind: hind, far: far)
    }
    let fh = leg(8, farHind, far: true, hind: true)
    let ff = leg(18, farFront, far: true, hind: false)
    let nh = leg(5, nearHind, far: false, hind: true)
    let nf = leg(20, nearFront, far: false, hind: false)
    return compose([
        Layer(grid: sideTails[tail], x: 1, y: 9 + bob, part: pTail, ring: false),
        Layer(grid: fh.0, x: fh.1, y: fh.2, part: pFarLeg, ring: false),
        Layer(grid: ff.0, x: ff.1, y: ff.2, part: pFarLeg + 10, ring: true, merge: [pFarLeg]),
        Layer(grid: walkTorso, x: 3, y: 16 + bob, part: pBody, merge: [pTail, pFarLeg, pFarLeg + 10]),
        Layer(grid: nh.0, x: nh.1, y: nh.2, part: pNearLeg, merge: [pBody]),
        Layer(grid: nf.0, x: nf.1, y: nf.2, part: pNearLeg + 10, merge: [pBody]),
        Layer(grid: frontHead(eyes, mouth: mouth, ears: ears), x: 18, y: 8 + bob, part: pHead),
    ])
}

/// Row 6: side walk facing right, a four-beat walk. 10 frames, stride driven.
func rowSideWalk() -> [Frame] {
    let bob = [0, 0, 1, 1, 0, 0, 0, 1, 1, 0]
    let tails = [0, 1, 1, 0, 2, 2, 0, 1, 1, 0]
    return (0..<10).map { i in
        sideFrame(nearHind: walkPose(i, phase: 0), nearFront: walkPose(i, phase: 8),
                  farHind: walkPose(i, phase: 5), farFront: walkPose(i, phase: 3),
                  bob: bob[i], tail: tails[i])
    }
}

// Stretched and gathered torsos for the gallop.
let runStretchTorso: Grid = [
    "....DDDDDDDDDDDDDD....",
    "..TDDDDDDDDDDDDDDDDT..",
    ".TTTDDDDDDDDDDDDDDTTT.",
    "TTTTTTtTTTTTTTTTTTTTTC",
    "TTTTTTTtTTTTTTTTTTTTCC",
    ".TTTTTtTTTTTTTTTTTTTC.",
]

let runGatherTorso: Grid = [
    ".....DDDDDDD.....",
    "...DDDDDDDDDDD...",
    "..TDDDDDDDDDDDDT.",
    ".TTTDDDDDDDDDDTTT",
    "TTTTTtTTTTTTTTTTC",
    "TTTTTTtTTTTTTTTCC",
    ".TTTTtTTTTTTTTTC.",
]

// Tail streaming out behind at a run. Stamped at (tailX, tailY).
let runTails: [Grid] = [
    ["CC.....", "CTT....", ".TTT...", "..TTT..", "...TTTT", ".....TT"],
    ["......", "CC....", "CTTT..", ".TTTTT", "....TT"],
]

// Hand-drawn leg poses for the gallop, near side; far legs are recoloured.
// Each pair (near and far) moves together, the far leg a step behind.
let legFrontUpright: Grid = ["TT.", "TT.", "TT.", "TT.", "TT.", "TT.", "CC.", "CCC"]
let legFrontBack: Grid    = ["..TT", "..TT", ".TT.", ".TT.", "TT..", "TT..", "CC..", "CCC."]
let legFrontLand: Grid    = ["TT...", "TT...", ".TT..", ".TT..", "..TT.", "..TT.", "..CC.", "..CCC"]
let legFrontReach: Grid   = ["TT....", ".TT...", "..TT..", "...TT.", "....CC", ".....C"]
let legFrontFold: Grid    = ["TT..", ".TT.", "..TT", ".CC.", "CC.."]
let legHindUnder: Grid    = ["TTT.", "TTT.", "TT..", "TT..", ".TT.", ".TT.", ".CC.", ".CCC"]
let legHindBack: Grid     = ["..TTT", ".TTT.", ".TT..", "TT...", "TT...", "CC...", "CCC.."]
let legHindForward: Grid  = ["TTT...", ".TTT..", "..TT..", "...TT.", "...TT.", "...CC.", "...CCC"]
let legHindLift: Grid     = ["TTT..", ".TTT.", "..TT.", ".CC..", "CC..."]

func far(_ g: Grid) -> Grid { recolour(g, ["T": "t", "C": "c"]) }

struct Placed { var g: Grid; var x: Int; var y: Int }

struct RunPose {
    var torso: Grid
    var tx: Int, ty: Int
    var farHind: Placed, farFront: Placed, nearHind: Placed, nearFront: Placed
    var headX: Int, headY: Int
    var ears: Ears
    var tail: Int, tailX: Int, tailY: Int
}

func runFrame(_ p: RunPose) -> Frame {
    compose([
        Layer(grid: runTails[p.tail], x: p.tailX, y: p.tailY, part: pTail, ring: false),
        Layer(grid: far(p.farHind.g), x: p.farHind.x, y: p.farHind.y, part: pFarLeg, ring: false),
        Layer(grid: far(p.farFront.g), x: p.farFront.x, y: p.farFront.y, part: pFarLeg + 10, merge: [pFarLeg]),
        Layer(grid: p.torso, x: p.tx, y: p.ty, part: pBody, merge: [pTail, pFarLeg, pFarLeg + 10]),
        Layer(grid: p.nearHind.g, x: p.nearHind.x, y: p.nearHind.y, part: pNearLeg, merge: [pBody]),
        Layer(grid: p.nearFront.g, x: p.nearFront.x, y: p.nearFront.y, part: pNearLeg + 10, merge: [pBody]),
        Layer(grid: frontHead(.open, mouth: .tongue, ears: p.ears), x: p.headX, y: p.headY, part: pHead),
    ])
}

/// Row 8: gallop facing right, stretch and gather. 6 frames at 14 fps.
func rowRun() -> [Frame] {
    let poses: [RunPose] = [
        // 0: stretched, lead front foot lands ahead, hind feet just off the ground.
        RunPose(torso: runStretchTorso, tx: 2, ty: 17,
                farHind: Placed(g: legHindBack, x: 4, y: 21), farFront: Placed(g: legFrontLand, x: 18, y: 21),
                nearHind: Placed(g: legHindBack, x: 2, y: 22), nearFront: Placed(g: legFrontLand, x: 21, y: 22),
                headX: 18, headY: 9, ears: .perk, tail: 0, tailX: 1, tailY: 12),
        // 1: front feet take the weight, hind legs swing in.
        RunPose(torso: walkTorso, tx: 3, ty: 16,
                farHind: Placed(g: legHindLift, x: 8, y: 21), farFront: Placed(g: legFrontBack, x: 18, y: 22),
                nearHind: Placed(g: legHindLift, x: 6, y: 21), nearFront: Placed(g: legFrontUpright, x: 20, y: 22),
                headX: 18, headY: 8, ears: .down, tail: 1, tailX: 1, tailY: 12),
        // 2: gathering, back rounds, hind feet reach under the belly.
        RunPose(torso: runGatherTorso, tx: 5, ty: 15,
                farHind: Placed(g: legHindForward, x: 10, y: 21), farFront: Placed(g: legFrontFold, x: 15, y: 21),
                nearHind: Placed(g: legHindForward, x: 7, y: 22), nearFront: Placed(g: legFrontBack, x: 15, y: 22),
                headX: 17, headY: 7, ears: .down, tail: 1, tailX: 2, tailY: 10),
        // 3: hind feet carry it, front legs fold up.
        RunPose(torso: runGatherTorso, tx: 5, ty: 15,
                farHind: Placed(g: legHindUnder, x: 10, y: 21), farFront: Placed(g: legFrontFold, x: 16, y: 21),
                nearHind: Placed(g: legHindUnder, x: 8, y: 22), nearFront: Placed(g: legFrontFold, x: 18, y: 21),
                headX: 17, headY: 7, ears: .down, tail: 0, tailX: 2, tailY: 10),
        // 4: hind legs drive back, front legs reach.
        RunPose(torso: walkTorso, tx: 3, ty: 16,
                farHind: Placed(g: legHindBack, x: 6, y: 22), farFront: Placed(g: legFrontReach, x: 19, y: 22),
                nearHind: Placed(g: legHindBack, x: 4, y: 23), nearFront: Placed(g: legFrontReach, x: 21, y: 21),
                headX: 18, headY: 8, ears: .perk, tail: 0, tailX: 1, tailY: 11),
        // 5: full stretch, last hind toe pushing off.
        RunPose(torso: runStretchTorso, tx: 2, ty: 16,
                farHind: Placed(g: legHindBack, x: 3, y: 21), farFront: Placed(g: legFrontReach, x: 19, y: 22),
                nearHind: Placed(g: legHindBack, x: 1, y: 23), nearFront: Placed(g: legFrontReach, x: 21, y: 21),
                headX: 18, headY: 8, ears: .perk, tail: 0, tailX: 1, tailY: 11),
    ]
    return poses.map(runFrame)
}

// MARK: - Tennis ball

/// A round tennis ball `size` pixels across including its outline, shaded to
/// the lower right, with the two curved seams turned by `angle` (radians; the
/// seams repeat every half turn). `seam` is the seam colour: off-white on the
/// sheet, where pure white is kept for eyes.
func ballGrid(size: Int, angle: Double, seam: Character = "O") -> Grid {
    let r = Double(size) / 2 - 1          // fill radius, inside the outline
    let c = Double(size) / 2 - 0.5
    var rows: [String] = []
    for y in 0..<size {
        var line = ""
        for x in 0..<size {
            let dx = Double(x) - c, dy = Double(y) - c
            let d = (dx * dx + dy * dy).squareRoot()
            if d > r + 0.75 { line.append("."); continue }
            if d > r - 0.25 { line.append("k"); continue }
            // Each seam is an arc of a circle centred just outside the ball.
            let u = dx * cos(angle) + dy * sin(angle)
            let v = -dx * sin(angle) + dy * cos(angle)
            let dl = ((u + 1.25 * r) * (u + 1.25 * r) + v * v).squareRoot()
            let dr = ((u - 1.25 * r) * (u - 1.25 * r) + v * v).squareRoot()
            if abs(dl - 0.9 * r) < 0.55 || abs(dr - 0.9 * r) < 0.55 { line.append(seam); continue }
            let lit = (-dx * 0.6 - dy * 0.8) / r
            line.append(lit < -0.35 ? "y" : "Y")
        }
        rows.append(line)
    }
    return rows
}

// MARK: - Ball play (lying on its back, face turned a quarter)

// On its back, belly up, saddle on the floor. At (2, 21).
let backBody: Grid = [
    "......CCCCCCCCC......",
    "....CCCCCCCCCCCCCC...",
    "..TCCCCCCCCCCCCCCCCT.",
    ".TTTTCCCCCCCCCCCCTTTT",
    "TTTTTTTTTTTTTTTTTTTTT",
    "TTTTTTTTTTTTTTTTTTTTT",
    "tTTTTTTTTTTTTTTTTTTTt",
    ".tDDDDDDDDDDDDDDDDDt.",
    "..DDDDDDDDDDDDDDDDD..",
]

// A leg in the air, paw at the top. `bend` tips the paw toward +x (1) or -x (-1).
func upLeg(height h: Int, bend: Int, far: Bool) -> Grid {
    let f: Character = far ? "t" : "T", p: Character = far ? "c" : "C"
    let ff = String([f, f]), pp = String([p, p])
    var g: Grid
    switch bend {
    case 1:  g = ["." + pp, pp + "."] + Array(repeating: ff + ".", count: max(0, h - 2))
    case -1: g = [pp + ".", "." + pp] + Array(repeating: "." + ff, count: max(0, h - 2))
    default: g = [pp, pp] + Array(repeating: ff, count: max(0, h - 2))
    }
    return g
}

// Tail flicking along the floor at the rump. At (1, 23).
let playTails: [Grid] = [
    ["CC...", "CTT..", ".TTT.", "..TTT"],
    [".....", "CCTT.", "CTTTT", "....T"],
    ["....", "....", "CCTTT", "CTTTT"],
]

struct PlayPose {
    var ballX: Int, ballY: Int, ballAngle: Double
    var nearFront: (h: Int, bend: Int), farFront: (h: Int, bend: Int)
    var nearHind: (h: Int, bend: Int), farHind: (h: Int, bend: Int)
    var tail: Int
    var tongue: Bool
}

/// The head turned a quarter: crown to +x, chin to -x. Eyes end up stacked at
/// x 24...25, rows 21 and 25, with the lids closing toward -x.
func playHead(tongue: Bool) -> (Grid, Int) {
    let g = rotateCW(frontHead(.open, mouth: tongue ? .tongue : .closed))
    return (g, tongue ? 20 : 21)
}

func playFrame(_ p: PlayPose) -> Frame {
    let (head, hx) = playHead(tongue: p.tongue)
    let by = 21
    func legY(_ h: Int) -> Int { by + 2 - h }
    return compose([
        Layer(grid: playTails[p.tail], x: 1, y: 23, part: pTail, ring: false),
        Layer(grid: upLeg(height: p.farHind.h, bend: p.farHind.bend, far: true), x: 4, y: legY(p.farHind.h), part: pFarLeg, ring: false),
        Layer(grid: upLeg(height: p.farFront.h, bend: p.farFront.bend, far: true), x: 18, y: legY(p.farFront.h), part: pFarLeg + 10, ring: false),
        Layer(grid: backBody, x: 2, y: by, part: pBody, merge: [pTail, pFarLeg, pFarLeg + 10]),
        Layer(grid: upLeg(height: p.nearHind.h, bend: p.nearHind.bend, far: false), x: 7, y: legY(p.nearHind.h) + 1, part: pNearLeg, merge: [pBody]),
        Layer(grid: head, x: hx, y: 17, part: pHead),
        Layer(grid: ballGrid(size: 11, angle: p.ballAngle), x: p.ballX - 5, y: p.ballY - 5, part: pBall, ring: false),
        Layer(grid: upLeg(height: p.nearFront.h, bend: p.nearFront.bend, far: false), x: 15, y: legY(p.nearFront.h) + 1, part: pNearLeg + 10, merge: [pBody]),
    ])
}

/// Row 7: on its back, tossing the ball off its front paws and catching it,
/// then a quick chew. 11 frames at 12 fps, facing right, ball baked in.
func rowBallPlay() -> [Frame] {
    let poses: [PlayPose] = [
        PlayPose(ballX: 16, ballY: 13, ballAngle: 0.0, nearFront: (6, 0), farFront: (6, 0), nearHind: (8, 1), farHind: (7, -1), tail: 0, tongue: false),
        PlayPose(ballX: 16, ballY: 10, ballAngle: 0.35, nearFront: (8, 0), farFront: (8, 0), nearHind: (7, 1), farHind: (8, -1), tail: 1, tongue: true),
        PlayPose(ballX: 16, ballY: 7, ballAngle: 0.7, nearFront: (7, 1), farFront: (7, 1), nearHind: (8, 1), farHind: (7, 1), tail: 2, tongue: true),
        PlayPose(ballX: 16, ballY: 6, ballAngle: 1.05, nearFront: (6, 1), farFront: (6, 1), nearHind: (7, -1), farHind: (8, 1), tail: 1, tongue: true),
        PlayPose(ballX: 16, ballY: 7, ballAngle: 1.4, nearFront: (6, 0), farFront: (6, 0), nearHind: (8, -1), farHind: (7, -1), tail: 0, tongue: true),
        PlayPose(ballX: 16, ballY: 10, ballAngle: 1.75, nearFront: (7, 0), farFront: (7, 0), nearHind: (7, 1), farHind: (8, -1), tail: 1, tongue: true),
        PlayPose(ballX: 16, ballY: 13, ballAngle: 2.1, nearFront: (6, 0), farFront: (6, 0), nearHind: (8, 1), farHind: (7, -1), tail: 2, tongue: false),
        PlayPose(ballX: 17, ballY: 16, ballAngle: 2.4, nearFront: (5, 1), farFront: (5, 1), nearHind: (7, 1), farHind: (8, 1), tail: 1, tongue: false),
        PlayPose(ballX: 18, ballY: 18, ballAngle: 2.65, nearFront: (4, 1), farFront: (4, 1), nearHind: (8, -1), farHind: (7, 1), tail: 0, tongue: false),
        PlayPose(ballX: 18, ballY: 18, ballAngle: 2.85, nearFront: (4, 1), farFront: (4, 1), nearHind: (7, -1), farHind: (8, -1), tail: 1, tongue: false),
        PlayPose(ballX: 17, ballY: 15, ballAngle: 3.0, nearFront: (5, 0), farFront: (5, 0), nearHind: (8, 1), farHind: (7, -1), tail: 2, tongue: false),
    ]
    return poses.map(playFrame)
}

// MARK: - Animated previews

/// Writes an animated GIF of `frames` at `fps`, enlarged, eyes dark as in the
/// app. `travel` moves the sprite right that many sheet pixels a frame over a
/// ground line, so a planted paw that slides shows up at once.
func writeGIF(_ frames: [Frame], fps: Double, to url: URL, scale: Int = 6, travel: Double = 0, loops: Int = 1) {
    let seq = Array(repeating: frames, count: loops).flatMap { $0 }
    let span = Int((travel * Double(seq.count)).rounded(.up))
    let w = (S + span) * scale, h = S * scale
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, seq.count, nil) else { return }
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (i, f) in seq.enumerated() {
        let ox = Int((travel * Double(i)).rounded())
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.89, green: 0.91, blue: 0.94, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Ground line and world ticks every 4 sheet pixels.
        ctx.setFillColor(CGColor(red: 0.55, green: 0.6, blue: 0.7, alpha: 1))
        ctx.fill(CGRect(x: 0, y: h - 31 * scale, width: w, height: 1))
        for tx in stride(from: 0, to: w, by: 4 * scale) {
            ctx.fill(CGRect(x: tx, y: h - 32 * scale, width: 1, height: scale))
        }
        for y in 0..<S {
            for x in 0..<S {
                guard let p = f.at(x, y) else { continue }
                let hex = p.ch == "W" ? previewEye : palette[p.ch]!
                let (r, g, b) = rgba(hex)
                ctx.setFillColor(CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1))
                ctx.fill(CGRect(x: (ox + x) * scale, y: h - (y + 1) * scale, width: scale, height: scale))
            }
        }
        CGImageDestinationAddImage(dest, ctx.makeImage()!,
                                   [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]] as CFDictionary)
    }
    CGImageDestinationFinalize(dest)
}

/// Stacks the frames of a cycle top to bottom, each shifted right by the
/// ground it has covered, over fixed world ticks: a planted paw should sit on
/// the same tick from one frame to the next.
func writeTrack(_ frames: [Frame], travel: Double, to url: URL, scale: Int = 6) {
    let span = Int((travel * Double(frames.count)).rounded(.up))
    let w = S + span, h = S * frames.count
    writePNG(width: w, height: h, to: url, scale: scale, background: { x, y in
        let sx = x / scale, sy = y / scale
        if sx % 4 == 0 && x % scale == 0 { return 0xB8C0CC }
        if sy % S == 30 && y % scale == scale - 1 { return 0x5090E0 }
        return 0xE8EBF0
    }) { x, y in
        let i = y / S
        let ox = Int((travel * Double(i)).rounded())
        let fx = x - ox
        guard fx >= 0, fx < S, let p = frames[i].at(fx, y % S) else { return nil }
        return p.ch == "W" ? previewEye : palette[p.ch]
    }
}

// MARK: - Main

/// Rows of the sheet, top to bottom, and how many frames each must have.
let rowSpecs: [(name: String, count: Int, build: () -> [Frame])] = [
    ("sit idle", 9, rowSitIdle),
    ("stand idle", 11, rowStandIdle),
    ("sit down", 11, rowSitDown),
    ("crouch (play bow)", 6, rowCrouch),
    ("lie down + sleep", 10, rowLieAndSleep),
    ("front walk", 10, rowFrontWalk),
    ("side walk", 10, rowSideWalk),
    ("ball play", 11, rowBallPlay),
    ("run", 6, rowRun),
]

let toolsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let assetsDir = toolsDir.deletingLastPathComponent().appendingPathComponent("Assets")
let sheetURL = assetsDir.appendingPathComponent("Dog_Sprite_Sheet.png")
let ballURL = assetsDir.appendingPathComponent("Dog_Ball.png")

var previewDir: URL?
if let i = CommandLine.arguments.firstIndex(of: "--preview"), i + 1 < CommandLine.arguments.count {
    previewDir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    try? FileManager.default.createDirectory(at: previewDir!, withIntermediateDirectories: true)
}

let rows: [[Frame]] = rowSpecs.map { $0.build() }
let cols = 12
let sheetW = cols * S, sheetH = rows.count * S

func sheetPixel(_ x: Int, _ y: Int) -> UInt32? {
    let r = y / S, c = x / S
    guard r < rows.count, c < rows[r].count, let p = rows[r][c].at(x % S, y % S) else { return nil }
    return palette[p.ch]
}

writePNG(width: sheetW, height: sheetH, to: sheetURL, pixel: sheetPixel)

// The loose ball: 13x13, seam in pure white (this file is never searched for eyes).
var ballPalette = palette
ballPalette["O"] = 0xFFFFFF
let looseBall = ballGrid(size: 13, angle: 0)
writePNG(width: 13, height: 13, to: ballURL) { x, y in
    let ch = Array(looseBall[y])[x]
    return ch == "." ? nil : ballPalette[ch]
}

// MARK: - Checks (run on the PNGs as written, read back from disk)

/// Reads a PNG back the way the app does (Sprites.swift loadRaw): NSImage to
/// CGImage, drawn into a device RGB context, premultiplied.
func readRGBA(_ url: URL) -> (w: Int, h: Int, px: [UInt8]) {
    let cg = NSImage(contentsOf: url)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let w = cg.width, h = cg.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    px.withUnsafeMutableBytes { buf in
        let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return (w, h, px)
}

var failures: [String] = []
func check(_ ok: Bool, _ msg: @autoclosure () -> String) { if !ok { failures.append(msg()) } }

let sheet = readRGBA(sheetURL)
check(sheet.w == 384 && sheet.h == 288, "sheet is \(sheet.w)x\(sheet.h), want 384x288")
let allowed = Set(palette.values)
func rgbAt(_ x: Int, _ y: Int) -> (UInt32, UInt8) {
    let i = (y * sheet.w + x) * 4
    let rgb = (UInt32(sheet.px[i]) << 16) | (UInt32(sheet.px[i + 1]) << 8) | UInt32(sheet.px[i + 2])
    return (rgb, sheet.px[i + 3])
}

var report: [String] = []
for (r, spec) in rowSpecs.enumerated() {
    var nonEmpty = 0
    var line = "row \(r) \(spec.name):"
    for c in 0..<cols {
        var opaque: [(Int, Int)] = []
        var whites: [(Int, Int)] = []
        for y in 0..<S {
            for x in 0..<S {
                let (rgb, a) = rgbAt(c * S + x, r * S + y)
                check(a == 0 || a == 255, "row \(r) frame \(c): partial alpha at \(x),\(y)")
                guard a > 0 else { continue }
                opaque.append((x, y))
                check(allowed.contains(rgb), String(format: "row %d frame %d: stray colour #%06X at %d,%d", r, c, rgb, x, y))
                if rgb == 0xFFFFFF { whites.append((x, y)) }
            }
        }
        if opaque.isEmpty { continue }
        nonEmpty += 1
        check(c < spec.count, "row \(r): frame \(c) should be empty")
        let lowest = opaque.map { $0.1 }.max()!
        check(lowest == 30, "row \(r) frame \(c): lowest pixel on row \(lowest), want 30")
        check(whites.count <= 6, "row \(r) frame \(c): \(whites.count) white pixels, want <= 6")
        // White may only be eye pixels: every one must belong to the head.
        let frame = rows[r][c]
        for (x, y) in whites {
            check(frame.at(x, y)?.part == pHead, "row \(r) frame \(c): white outside the head at \(x),\(y)")
        }
        // Same test the app runs to find the face.
        if !whites.isEmpty {
            let minX = whites.map { $0.0 }.min()!, maxX = whites.map { $0.0 }.max()!
            let minY = whites.map { $0.1 }.min()!, maxY = whites.map { $0.1 }.max()!
            let upright = maxX - minX >= 4
            check(upright == (r != 7), "row \(r) frame \(c): face reads as \(upright ? "upright" : "quarter turned")")
            line += upright ? " [\((minX + maxX) / 2),\(maxY)]" : " [q \(minX),\((minY + maxY) / 2)]"
        } else {
            line += " [shut]"
        }
        // The silhouette is closed: no fill pixel touches transparency.
        let set = Set(opaque.map { $0.1 * S + $0.0 })
        for (x, y) in opaque {
            let (rgb, _) = rgbAt(c * S + x, r * S + y)
            if rgb == palette["k"]! { continue }
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                let inside = nx >= 0 && nx < S && ny >= 0 && ny < S && set.contains(ny * S + nx)
                check(inside, "row \(r) frame \(c): fill at \(x),\(y) not outlined")
            }
        }
        // No stray pixels: everything hangs together (the ball may float free in row 7).
        var seen = Set<Int>(), parts = 0
        for p in set where !seen.contains(p) {
            parts += 1
            var stack = [p]; seen.insert(p)
            while let q = stack.popLast() {
                let x = q % S, y = q / S
                for dy in -1...1 { for dx in -1...1 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < S, ny >= 0, ny < S else { continue }
                    let n = ny * S + nx
                    if set.contains(n) && !seen.contains(n) { seen.insert(n); stack.append(n) }
                }}
            }
        }
        check(parts <= (r == 7 ? 2 : 1), "row \(r) frame \(c): \(parts) separate pieces")
    }
    check(nonEmpty == spec.count, "row \(r): \(nonEmpty) frames, want \(spec.count)")
    report.append(line)
}

// Every clip must show the eyes in at least one frame, so accessories can anchor.
let clipRanges: [(String, Int, Range<Int>)] = [
    ("sitIdle", 0, 0..<9), ("standIdle", 1, 0..<11), ("sitDown", 2, 0..<11), ("crouch", 3, 0..<6),
    ("lieDown", 4, 0..<4), ("sleep", 4, 4..<10), ("frontWalk", 5, 0..<10), ("sideWalk", 6, 0..<10),
    ("ballPlay", 7, 0..<11), ("run", 8, 0..<6),
]
for (name, r, range) in clipRanges {
    let any = range.contains { c in
        (0..<S).contains { y in (0..<S).contains { x in
            let (rgb, a) = rgbAt(c * S + x, r * S + y); return a == 255 && rgb == 0xFFFFFF } }
    }
    check(any, "clip \(name): no eyes in any frame, accessories would vanish")
}

let ball = readRGBA(ballURL)
check(ball.w == 13 && ball.h == 13, "ball is \(ball.w)x\(ball.h), want 13x13")

for line in report { print(line) }
if failures.isEmpty {
    print("all checks passed: 384x288, 94 frames, ground row 30, eyes only white (<= 6 a frame), outlines closed")
} else {
    for f in failures.prefix(40) { print("FAIL: \(f)") }
    print("\(failures.count) check(s) failed")
}

// MARK: - Previews

if let dir = previewDir {
    for (r, frames) in rows.enumerated() {
        writeStrip(frames, to: dir.appendingPathComponent("dog_row\(r).png"), scale: 8, darkEyes: true, columns: 12)
        writeStrip(frames, to: dir.appendingPathComponent("dog_row\(r)_raw.png"), scale: 8, darkEyes: false, columns: 12)
    }
    writeStrip(rows.flatMap { f in f + Array(repeating: nil, count: 12 - f.count) } as [Frame?],
               to: dir.appendingPathComponent("dog_sheet_4x.png"), scale: 4, darkEyes: true, columns: 12)
    writePNG(width: 13, height: 13, to: dir.appendingPathComponent("dog_ball_16x.png"), scale: 16,
             background: { x, y in ((x / 16 + y / 16) % 2 == 0) ? 0xE6E9EE : 0xD3D8E0 }) { x, y in
        let ch = Array(looseBall[y])[x]
        return ch == "." ? nil : ballPalette[ch]
    }
    // Animated checks, at the app's frame rates. Walk and run move over the
    // ground at the speed their planted paws sweep back.
    let walkTravel = 1.6, runTravel = 4.0
    writeGIF(rows[0], fps: 7, to: dir.appendingPathComponent("anim_sit_idle.gif"), loops: 2)
    writeGIF(rows[1], fps: 7, to: dir.appendingPathComponent("anim_stand_idle.gif"), loops: 2)
    writeGIF(rows[2], fps: 10, to: dir.appendingPathComponent("anim_sit_down.gif"))
    writeGIF(rows[3], fps: 7, to: dir.appendingPathComponent("anim_crouch.gif"), loops: 3)
    writeGIF(Array(rows[4][0..<4]) + Array(repeating: rows[4][3], count: 2), fps: 7, to: dir.appendingPathComponent("anim_lie_down.gif"))
    writeGIF(Array(rows[4][4..<10]), fps: 3, to: dir.appendingPathComponent("anim_sleep.gif"), loops: 2)
    writeGIF(rows[5], fps: 10, to: dir.appendingPathComponent("anim_front_walk.gif"), loops: 2)
    writeGIF(rows[6], fps: 10, to: dir.appendingPathComponent("anim_side_walk.gif"), travel: walkTravel, loops: 3)
    writeGIF(rows[7], fps: 12, to: dir.appendingPathComponent("anim_ball_play.gif"), loops: 2)
    writeGIF(rows[8], fps: 14, to: dir.appendingPathComponent("anim_run.gif"), travel: runTravel, loops: 4)
    writeTrack(rows[6] + [rows[6][0]], travel: walkTravel, to: dir.appendingPathComponent("track_side_walk.png"))
    writeTrack(rows[8] + [rows[8][0]], travel: runTravel, to: dir.appendingPathComponent("track_run.png"))
    print("previews in \(dir.path)")
}

if !failures.isEmpty { exit(1) }
