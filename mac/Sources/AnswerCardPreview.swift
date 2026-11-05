import AppKit

/// `--answer-card <out.png>`: builds the LLM answer card offscreen in each of
/// its states and stacks them into one picture, so the card can be checked
/// without a screen, a cat or a call to Claude.
func renderAnswerCards(to path: String) {
    let config = Config.load()
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let panel = AnswerPanel(palette: config.extras, accent: NSColor(hex: config.furColor) ?? .systemPurple)
    panel.showsOnScreen = false
    panel.petIcon = SpriteSheet(resources: resourcesDirectory(), config: config).menuBarIcon()
    var shots: [(String, NSBitmapImageRep)] = []
    func snap(_ label: String) {
        guard let view = panel.contentView else { return }
        view.layoutSubtreeIfNeeded()
        // A clear bitmap of our own, so the corners and the sides of the
        // tail stay see-through, as they are on screen.
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
                                         pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        shots.append((label, rep))
    }

    let question = "A train leaves at 3:40 pm and the trip takes 2 h 35 min. What time does it arrive?"
    panel.showThinking(.text(question), above: CGPoint(x: 1000, y: 120), within: screen)
    snap("Thinking")
    panel.showAnswer("It arrives at 6:15 pm.\n3:40 pm + 2 h = 5:40 pm.\n5:40 pm + 35 min = 6:15 pm.",
                     autoCopy: true)
    snap("Answer, copied to the clipboard")
    panel.showThinking(.followUp("Now say it in French"), above: CGPoint(x: 1000, y: 120), within: screen)
    snap("Follow-up on its way")
    // Near the right edge, so the card is pushed in and the tail has to lean.
    panel.showThinking(.image(Data(), from: "screenshot"), above: CGPoint(x: 1460, y: 120), within: screen)
    panel.showAnswer("""
        The error means the array is empty when you read its first item.
        In loadUsers(), users[0] runs before the fetch has finished, so users is still [].
        Wait for the fetch, then read the first user: let first = users.first.
        Or guard against the empty case: guard let first = users.first else { return }.
        """)
    snap("Screenshot answer, card pushed in from the screen edge")
    panel.showError("Could not find the claude command. Install Claude Code, or set llmClaudePath in settings.")
    snap("No answer")
    stackCardShots(shots, to: path)
}

/// Lays the shots out top to bottom on a grey board with a label over each.
private func stackCardShots(_ shots: [(String, NSBitmapImageRep)], to path: String) {
    let pad: CGFloat = 28, labelGap: CGFloat = 22, gap: CGFloat = 26
    let width = (shots.map { $0.1.size.width }.max() ?? 400) + pad * 2
    let height = shots.reduce(pad * 2) { $0 + labelGap + $1.1.size.height + gap } - gap
    let scale: CGFloat = 2
    guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale),
                                     pixelsHigh: Int(height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: out) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)
    NSColor(srgbRed: 0.36, green: 0.40, blue: 0.47, alpha: 1).setFill()
    CGRect(x: 0, y: 0, width: width, height: height).fill()
    var y = height - pad
    for (label, rep) in shots {
        NSString(string: label).draw(at: CGPoint(x: pad, y: y - 14), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.85),
        ])
        y -= labelGap + rep.size.height
        // Source-over, not the copy that draw(in:) does, so the clear
        // corners show the board through them.
        rep.draw(in: CGRect(x: pad, y: y, width: rep.size.width, height: rep.size.height), from: .zero,
                 operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        y -= gap
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let data = out.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}
