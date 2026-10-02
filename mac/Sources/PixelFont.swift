import AppKit

/// A 5x7 pixel font, so speech matches the sprites instead of sitting on top of
/// them in Helvetica. Uppercase only, which is all the cat has to say.
enum PixelFont {
    static let height = 7
    static let width = 5
    /// One blank column between letters.
    static let tracking = 1

    static let glyphs: [Character: [String]] = [
        "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
        "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
        "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
        "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
        "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
        "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
        "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
        "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
        "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
        "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
        "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
        "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
        "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
        "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
        "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
        "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
        "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
        "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
        "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
        "W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
        "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
        "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
        "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
        "'": ["00100", "00100", "01000", "00000", "00000", "00000", "00000"],
        "!": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
        "?": ["01110", "10001", "00001", "00010", "00100", "00000", "00100"],
        ".": ["00000", "00000", "00000", "00000", "00000", "00000", "00100"],
        " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ":": ["00000", "00100", "00100", "00000", "00100", "00100", "00000"],
        "(": ["00010", "00100", "01000", "01000", "01000", "00100", "00010"],
        ")": ["01000", "00100", "00010", "00010", "00010", "00100", "01000"],
        "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
        "%": ["11000", "11001", "00010", "00100", "01000", "10011", "00011"],
        "/": ["00000", "00001", "00010", "00100", "01000", "10000", "00000"],
    ]

    /// Width of a rendered string, in font pixels.
    static func width(of text: String) -> Int {
        let n = text.count
        guard n > 0 else { return 0 }
        return n * width + (n - 1) * tracking
    }

    /// Draws `text` with its bottom-left corner at `origin`. `pixel` should
    /// already be a whole number of points so the glyphs stay square.
    static func draw(_ text: String, at origin: CGPoint, pixel: CGFloat,
                     color: NSColor, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        color.setFill()
        var penX = origin.x
        for character in text.uppercased() {
            if let rows = glyphs[character] {
                for (rowIndex, row) in rows.reversed().enumerated() {
                    for (colIndex, bit) in row.enumerated() where bit == "1" {
                        CGRect(x: penX + CGFloat(colIndex) * pixel,
                               y: origin.y + CGFloat(rowIndex) * pixel,
                               width: pixel, height: pixel).fill()
                    }
                }
            }
            penX += CGFloat(width + tracking) * pixel
        }
        ctx.restoreGState()
    }
}

/// The speech bubble the cat uses to ask for a game, plus the button in it.
struct SpeechBubble {
    /// Everything is laid out in font pixels first, then scaled once.
    private static let padding = 4
    private static let gap = 4
    private static let buttonPadX = 4
    private static let buttonPadY = 2
    private static let tail = 4

    let text: String
    let button: String

    /// Size in font pixels, tail included.
    var pixelSize: CGSize {
        let contentW = max(PixelFont.width(of: text), buttonPixelWidth)
        return CGSize(width: contentW + Self.padding * 2,
                      height: Self.padding * 2 + PixelFont.height + Self.gap
                              + buttonPixelHeight + Self.tail)
    }

    private var buttonPixelWidth: Int { PixelFont.width(of: button) + Self.buttonPadX * 2 }
    private var buttonPixelHeight: Int { PixelFont.height + Self.buttonPadY * 2 }

    /// Draws the bubble with the tip of its tail at `tip`, pointing down at the
    /// cat. Returns the button rect for click matching and the whole body rect,
    /// which together with the cat forms the area you can rest the pointer on.
    /// `progress` fills the button as the dwell accumulates, so a thirty second
    /// wait is something you can watch rather than guess at.
    @discardableResult
    func draw(tipAt tip: CGPoint, pixel: CGFloat, palette: Palette,
              hovering: Bool, progress: CGFloat = 0,
              in ctx: CGContext) -> (button: CGRect, body: CGRect) {
        let p = max(2, pixel.rounded())
        let size = pixelSize
        let w = CGFloat(size.width) * p
        let bodyH = CGFloat(Int(size.height) - Self.tail) * p
        let originX = (tip.x - w / 2).rounded()
        let originY = (tip.y + CGFloat(Self.tail) * p).rounded()

        ctx.saveGState()
        ctx.setShouldAntialias(false)

        let body = CGRect(x: originX, y: originY, width: w, height: bodyH)
        // Border first, then the fill inset by one pixel: a chunky 1px outline.
        palette.outline.setFill()
        body.insetBy(dx: -p, dy: -p).fill()
        NSColor(white: 0.98, alpha: 1).setFill()
        body.fill()

        // Tail: a stepped triangle down to the tip, in the same two passes.
        for step in 0..<Self.tail {
            let half = CGFloat(Self.tail - step)
            let row = CGRect(x: (tip.x - half * p).rounded(),
                             y: originY - CGFloat(step + 1) * p,
                             width: (half * 2 * p).rounded(), height: p)
            palette.outline.setFill()
            row.insetBy(dx: -p, dy: 0).fill()
            NSColor(white: 0.98, alpha: 1).setFill()
            row.fill()
        }

        // Text, centred.
        let textW = CGFloat(PixelFont.width(of: text)) * p
        PixelFont.draw(text,
                       at: CGPoint(x: body.midX - textW / 2,
                                   y: body.maxY - CGFloat(Self.padding + PixelFont.height) * p),
                       pixel: p, color: palette.outline, in: ctx)

        // Button, centred under the text.
        let buttonW = CGFloat(buttonPixelWidth) * p
        let buttonH = CGFloat(buttonPixelHeight) * p
        let buttonRect = CGRect(x: (body.midX - buttonW / 2).rounded(),
                                y: (body.minY + CGFloat(Self.padding) * p).rounded(),
                                width: buttonW, height: buttonH)
        palette.outline.setFill()
        buttonRect.insetBy(dx: -p, dy: -p).fill()
        (hovering ? NSColor(white: 0.94, alpha: 1) : NSColor(white: 0.88, alpha: 1)).setFill()
        buttonRect.fill()
        if progress > 0 {
            palette.inner.setFill()
            CGRect(x: buttonRect.minX, y: buttonRect.minY,
                   width: (buttonRect.width * min(progress, 1)).rounded(),
                   height: buttonRect.height).fill()
        }
        let labelW = CGFloat(PixelFont.width(of: button)) * p
        PixelFont.draw(button,
                       at: CGPoint(x: buttonRect.midX - labelW / 2,
                                   y: buttonRect.midY - CGFloat(PixelFont.height) * p / 2),
                       pixel: p, color: palette.outline, in: ctx)

        ctx.restoreGState()
        // The button is grown a little, because it is a small target.
        return (buttonRect.insetBy(dx: -p * 2, dy: -p * 2),
                body.insetBy(dx: -p, dy: -p))
    }
}
