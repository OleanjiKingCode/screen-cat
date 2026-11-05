import AppKit

/// The card the cat sits under in LLM mode, with the answer in it. A small
/// floating panel rather than paint on the overlay, so the text can be
/// selected, scrolled and copied. It never takes focus from your app, and it
/// follows the same screenshot setting as the cat, until you click into the
/// follow-up field under an answer to ask more.
///
/// Everything on it is drawn in `draw(_:)`, not with layer colours, so an
/// offscreen render (`--answer-card`) shows exactly what the screen does.
final class AnswerPanel: NSPanel, NSTextFieldDelegate {
    /// The card was closed by you, with ✕ or Esc. Not called by `dismiss()`.
    var onClose: (() -> Void)?
    /// The answer was put on the clipboard, by the button or automatically.
    var onCopy: (() -> Void)?
    /// Typed into the field under the answer and sent with Enter or the arrow.
    var onFollowUp: ((String) -> Void)?
    private(set) var answer = ""
    /// The pet's menu bar silhouette, shown at the start of the header.
    var petIcon: NSImage? {
        didSet {
            iconView.image = petIcon
            iconView.isHidden = petIcon == nil
        }
    }
    /// Off for offscreen renders, which build the card without showing it.
    var showsOnScreen = true

    static let width: CGFloat = 400
    private static let maxTextHeight: CGFloat = 360
    private static let side: CGFloat = 16
    private static let headerHeight: CGFloat = 24
    private static let replyHeight: CGFloat = 32
    private static let dotsHeight: CGFloat = 22

    private let ink: NSColor
    private let accent: NSColor
    private let card = CardView()
    private let iconView = NSImageView()
    private let status = PillView()
    private let copiedNote = NSStackView()
    private let copyButton = CardButton()
    private let closeButton = CardButton()
    private let asked = NSTextField(wrappingLabelWithString: "")
    private let divider = DividerView()
    private let textView = NSTextView()
    private let scroll = NSScrollView()
    private let dots = ThinkingDots()
    private let replyBox = ReplyBox()
    private let reply = NSTextField()
    private let sendButton = CardButton()
    private var bodyHeight: NSLayoutConstraint!
    private var bodyToCard: NSLayoutConstraint!
    private var bodyToReply: NSLayoutConstraint!
    private var thinkingTimer: Timer?
    /// Bumped on each copy, so an old "Copied" flip does not undo a newer one.
    private var copyFlip = 0
    private var anchor = CGPoint.zero
    private var area = CGRect.zero

    private var muted: NSColor { ink.withAlphaComponent(0.55) }
    private static let errorRed = NSColor(srgbRed: 0.64, green: 0.09, blue: 0.17, alpha: 1)
    private static let copiedGreen = NSColor(srgbRed: 0.18, green: 0.56, blue: 0.33, alpha: 1)

    init(palette: Palette, accent: NSColor) {
        ink = palette.outline
        self.accent = accent
        super.init(contentRect: CGRect(x: 0, y: 0, width: Self.width, height: 160),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = true
        // Clear, so the rounded corners and the tail are real: only the card
        // shape is painted, and the shadow follows it.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        // Same as the cat's window: on every Space, over full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // The card is drawn in fixed light colours.
        appearance = NSAppearance(named: .aqua)
        buildContent()
    }

    // A borderless panel cannot become key by default, and then the text
    // cannot be selected. Non-activating, so your app keeps the focus.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { closeByUser() }

    /// The cat has no Edit menu, so Cmd+X, C, V and A are wired up here for
    /// the answer and the follow-up field.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let actions: [String: Selector] = [
            "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
            "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:)),
        ]
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let action = event.charactersIgnoringModifiers.flatMap({ actions[$0] }),
           NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Esc in the field closes the card, as it does everywhere else on it.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        closeByUser()
        return true
    }

    /// The send arrow lights up once there is something to send.
    func controlTextDidChange(_ obj: Notification) { tintSend() }

    // MARK: - Building

    private func buildContent() {
        card.fill = NSColor(srgbRed: 1.0, green: 0.988, blue: 0.965, alpha: 1)
        card.stroke = ink
        contentView = card

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = ink
        iconView.isHidden = true

        let check = NSImageView()
        check.image = symbol("checkmark.circle.fill", size: 11)
        check.contentTintColor = Self.copiedGreen
        let copiedLabel = NSTextField(labelWithString: "Copied to clipboard")
        copiedLabel.font = .systemFont(ofSize: 11, weight: .medium)
        copiedLabel.textColor = muted
        copiedNote.orientation = .horizontal
        copiedNote.spacing = 4
        copiedNote.addArrangedSubview(check)
        copiedNote.addArrangedSubview(copiedLabel)
        copiedNote.isHidden = true

        let left = NSStackView(views: [iconView, status, copiedNote])
        left.orientation = .horizontal
        left.spacing = 8
        left.alignment = .centerY

        copyButton.target = self
        copyButton.action = #selector(copyAnswer)
        style(copyButton, symbol: "doc.on.doc", title: "Copy", color: ink)
        copyButton.toolTip = "Copy the answer"
        closeButton.target = self
        closeButton.action = #selector(closeByUser)
        style(closeButton, symbol: "xmark", title: nil, color: muted)
        closeButton.toolTip = "Close (Esc)"
        let right = NSStackView(views: [copyButton, closeButton])
        right.orientation = .horizontal
        right.spacing = 2

        asked.font = .systemFont(ofSize: 11.5)
        asked.textColor = muted
        asked.maximumNumberOfLines = 2
        asked.lineBreakMode = .byTruncatingTail
        asked.cell?.truncatesLastVisibleLine = true
        asked.preferredMaxLayoutWidth = Self.width - Self.side * 2

        divider.color = ink.withAlphaComponent(0.12)
        dots.color = ink

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.selectedTextAttributes = [.backgroundColor: accent.withAlphaComponent(0.35)]
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        replyBox.fill = .white
        replyBox.stroke = ink.withAlphaComponent(0.2)
        reply.isBordered = false
        reply.drawsBackground = false
        reply.focusRingType = .none
        reply.font = .systemFont(ofSize: 13)
        reply.textColor = ink
        reply.placeholderAttributedString = NSAttributedString(string: "Ask a follow-up…", attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: ink.withAlphaComponent(0.4),
        ])
        reply.cell?.usesSingleLineMode = true
        reply.cell?.isScrollable = true
        reply.delegate = self
        reply.target = self
        reply.action = #selector(sendFollowUp)
        sendButton.target = self
        sendButton.action = #selector(sendFollowUp)
        sendButton.hoverFill = .clear
        style(sendButton, symbol: "arrow.up.circle.fill", title: nil, color: ink, size: 19)
        sendButton.toolTip = "Ask (Return)"
        tintSend()

        for v in [left, right, asked, divider, scroll, dots, replyBox] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(v)
        }
        for v in [reply, sendButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            replyBox.addSubview(v)
        }
        let side = Self.side
        bodyHeight = scroll.heightAnchor.constraint(equalToConstant: 20)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            right.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            right.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            right.heightAnchor.constraint(equalToConstant: Self.headerHeight),
            left.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: side),
            left.centerYAnchor.constraint(equalTo: right.centerYAnchor),
            left.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -8),
            status.heightAnchor.constraint(equalToConstant: 18),

            asked.topAnchor.constraint(equalTo: right.bottomAnchor, constant: 8),
            asked.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: side),
            asked.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -side),
            divider.topAnchor.constraint(equalTo: asked.bottomAnchor, constant: 10),
            divider.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: side),
            divider.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -side),
            divider.heightAnchor.constraint(equalToConstant: 1),

            scroll.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: side),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -side),
            bodyHeight,
            dots.topAnchor.constraint(equalTo: scroll.topAnchor),
            dots.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            dots.widthAnchor.constraint(equalToConstant: 60),
            dots.heightAnchor.constraint(equalToConstant: Self.dotsHeight),

            replyBox.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            replyBox.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            replyBox.heightAnchor.constraint(equalToConstant: Self.replyHeight),
            replyBox.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -(CardView.tail + 12)),
            reply.leadingAnchor.constraint(equalTo: replyBox.leadingAnchor, constant: 14),
            reply.centerYAnchor.constraint(equalTo: replyBox.centerYAnchor),
            reply.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -6),
            sendButton.trailingAnchor.constraint(equalTo: replyBox.trailingAnchor, constant: -4),
            sendButton.centerYAnchor.constraint(equalTo: replyBox.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 26),
            sendButton.heightAnchor.constraint(equalToConstant: 26),
        ])
        // The text runs down to the field when it shows, else to the edge.
        bodyToCard = scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -(CardView.tail + 16))
        bodyToReply = scroll.bottomAnchor.constraint(equalTo: replyBox.topAnchor, constant: -14)
        showReply(false)
    }

    // MARK: - States

    /// Shows the card above `anchor` (a global point, the top of the cat's
    /// head) while the answer is on its way: what was asked, and dots.
    func showThinking(_ question: Question, above anchor: CGPoint, within screen: CGRect) {
        self.anchor = anchor
        area = screen
        answer = ""
        copyFlip += 1
        setStatus(.thinking)
        copyButton.isHidden = true
        copiedNote.isHidden = true
        setAsked(question)
        showReply(false)
        textView.string = ""
        scroll.isHidden = true
        dots.isHidden = false
        dots.phase = 0
        thinkingTimer?.invalidate()
        if showsOnScreen {
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.dots.phase = (self.dots.phase + 1.0 / 30.0 / 1.2).truncatingRemainder(dividingBy: 1)
            }
            RunLoop.main.add(timer, forMode: .common)
            thinkingTimer = timer
        }
        resize(bodyHeight: Self.dotsHeight)
        if showsOnScreen { orderFrontRegardless() }
    }

    /// The answer. It stays up until you close it, however long you read.
    /// With `autoCopy` it also goes on the clipboard, and the header says so.
    func showAnswer(_ text: String, autoCopy: Bool = false) {
        stopThinking()
        answer = text
        setStatus(.answer)
        copyButton.isHidden = false
        style(copyButton, symbol: "doc.on.doc", title: "Copy", color: ink)
        showReply(true)
        setBody(answerText(text))
        if autoCopy {
            putOnClipboard()
            copiedNote.isHidden = false
        }
    }

    func showError(_ text: String) {
        stopThinking()
        answer = ""
        setStatus(.failed)
        copyButton.isHidden = true
        copiedNote.isHidden = true
        showReply(true)
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.2
        setBody(NSAttributedString(string: text.trimmingCharacters(in: .whitespacesAndNewlines), attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: Self.errorRed, .paragraphStyle: para,
        ]))
    }

    /// Takes the card away without telling anyone: the cat is already going.
    func dismiss() {
        stopThinking()
        reply.stringValue = ""
        tintSend()
        orderOut(nil)
    }

    private func stopThinking() {
        thinkingTimer?.invalidate()
        thinkingTimer = nil
        dots.isHidden = true
        scroll.isHidden = false
    }

    private enum Status { case thinking, answer, failed }

    private func setStatus(_ s: Status) {
        switch s {
        case .thinking:
            status.text = "THINKING"
            status.fill = NSColor(srgbRed: 1.0, green: 0.91, blue: 0.64, alpha: 1)
            status.textColor = NSColor(srgbRed: 0.48, green: 0.31, blue: 0.0, alpha: 1)
        case .answer:
            status.text = "ANSWER"
            status.fill = accent.blended(withFraction: 0.7, of: .white) ?? accent
            status.textColor = ink
        case .failed:
            status.text = "NO ANSWER"
            status.fill = NSColor(srgbRed: 0.98, green: 0.86, blue: 0.87, alpha: 1)
            status.textColor = Self.errorRed
        }
    }

    /// One muted line of what was asked, so the answer has its context.
    private func setAsked(_ question: Question) {
        let prefix: String
        let rest: String
        switch question {
        case .text(let s):
            prefix = "You copied: "
            rest = s.split(whereSeparator: \.isNewline).joined(separator: " ")
        case .followUp(let s):
            prefix = "You asked: "
            rest = s.split(whereSeparator: \.isNewline).joined(separator: " ")
        case .image(_, let from):
            prefix = from == "screenshot" ? "Your screenshot" : "Your copied image"
            rest = ""
        }
        let text = NSMutableAttributedString(string: prefix, attributes: [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: muted,
        ])
        text.append(NSAttributedString(string: rest, attributes: [
            .font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: muted,
        ]))
        // Wraps, and the label cuts the second line short with an ellipsis.
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        text.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: text.length))
        asked.attributedStringValue = text
    }

    /// The first line is the answer itself, so it reads as a headline; the
    /// lines after it are the working, in a quieter body style.
    private func answerText(_ raw: String) -> NSAttributedString {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let head = String(parts.first ?? "")
        let rest = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""

        let headPara = NSMutableParagraphStyle()
        headPara.lineHeightMultiple = 1.15
        headPara.paragraphSpacing = 8
        let bodyPara = NSMutableParagraphStyle()
        bodyPara.lineHeightMultiple = 1.2
        bodyPara.paragraphSpacing = 6

        let out = NSMutableAttributedString(string: head, attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: ink, .paragraphStyle: headPara,
        ])
        guard !rest.isEmpty else { return out }
        out.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .paragraphStyle: headPara,
        ]))
        out.append(NSAttributedString(string: rest, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: ink.withAlphaComponent(0.82),
            .paragraphStyle: bodyPara,
        ]))
        return out
    }

    private func setBody(_ text: NSAttributedString) {
        textView.textStorage?.setAttributedString(text)
        let width = Self.width - Self.side * 2
        textView.frame = CGRect(x: 0, y: 0, width: width, height: 10)
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = ceil(layout.usedRect(for: container).height)
        textView.frame.size.height = max(used, 18)
        textView.scroll(.zero)
        resize(bodyHeight: min(Self.maxTextHeight, max(18, used)))
    }

    /// The field shows under an answer, not while one is on its way. Once
    /// you have clicked into it, it keeps the focus for the next follow-up.
    private func showReply(_ shown: Bool) {
        if !shown, reply.currentEditor() != nil { makeFirstResponder(nil) }
        replyBox.isHidden = !shown
        NSLayoutConstraint.deactivate([shown ? bodyToCard : bodyToReply])
        NSLayoutConstraint.activate([shown ? bodyToReply : bodyToCard])
        if shown, isKeyWindow { makeFirstResponder(reply) }
    }

    @objc private func sendFollowUp() {
        let text = reply.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        reply.stringValue = ""
        tintSend()
        onFollowUp?(text)
    }

    @objc private func closeByUser() {
        dismiss()
        onClose?()
    }

    /// The Copy button: copies, and says so on the button for a moment.
    @objc func copyAnswer() {
        guard putOnClipboard() else { return }
        copyFlip += 1
        let mine = copyFlip
        style(copyButton, symbol: "checkmark", title: "Copied", color: Self.copiedGreen)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.copyFlip == mine else { return }
            self.style(self.copyButton, symbol: "doc.on.doc", title: "Copy", color: self.ink)
        }
    }

    @discardableResult
    private func putOnClipboard() -> Bool {
        guard !answer.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
        onCopy?()
        return true
    }

    // MARK: - Look

    private func symbol(_ name: String, size: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .semibold))
    }

    /// No bezel, and the colour set on the title and the tint. A bezel
    /// button greys out whenever the card is not focused, which is nearly
    /// always.
    private func style(_ button: CardButton, symbol name: String, title: String?, color: NSColor,
                       size: CGFloat = 12) {
        button.isBordered = false
        button.image = symbol(name, size: size)
        button.contentTintColor = color
        button.imagePosition = title == nil ? .imageOnly : .imageLeading
        button.imageHugsTitle = true
        button.attributedTitle = NSAttributedString(string: title ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: color,
        ])
        button.invalidateIntrinsicContentSize()
    }

    private func tintSend() {
        let empty = reply.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.contentTintColor = empty ? ink.withAlphaComponent(0.25) : ink
    }

    /// Fits the card to its content, keeps it inside the screen, and points
    /// the tail at the cat's head even when the card is pushed sideways.
    private func resize(bodyHeight body: CGFloat) {
        bodyHeight.constant = body
        let askedHeight = ceil(asked.intrinsicContentSize.height)
        let footer = replyBox.isHidden ? 16 : 14 + Self.replyHeight + 12
        let height = 12 + Self.headerHeight + 8 + askedHeight + 10 + 1 + 12 + body + footer + CardView.tail
        // No screen given yet: use the main one, never an empty rect, which
        // AppKit rejects as a window frame.
        let given = area.width > 24 && area.height > 24 ? area : (NSScreen.main?.visibleFrame ?? .zero)
        let room = given.insetBy(dx: 12, dy: 12)
        var x = anchor.x - Self.width / 2
        x = min(max(x, room.minX), room.maxX - Self.width)
        var y = anchor.y + 4
        y = min(y, room.maxY - height)
        card.tailX = anchor.x - x
        setFrame(CGRect(x: x, y: y, width: Self.width, height: height), display: true)
        card.layoutSubtreeIfNeeded()
        invalidateShadow()
    }
}

// MARK: - Pieces

/// The card itself: a rounded speech bubble with a tail at the bottom that
/// points at the cat.
final class CardView: NSView {
    static let radius: CGFloat = 14
    static let tail: CGFloat = 10
    var fill = NSColor.white
    var stroke = NSColor.black
    /// Where the tail points, in this view's coordinates.
    var tailX: CGFloat = 200 { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = Self.outline(in: bounds, tailX: tailX)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    static func outline(in bounds: CGRect, tailX: CGFloat) -> NSBezierPath {
        let r = CGRect(x: bounds.minX + 1, y: bounds.minY + tail + 1,
                       width: bounds.width - 2, height: bounds.height - tail - 2)
        let corner = radius, half: CGFloat = 9
        let tip = min(max(tailX, r.minX + corner + half), r.maxX - corner - half)
        let p = NSBezierPath()
        p.move(to: CGPoint(x: r.minX + corner, y: r.minY))
        p.line(to: CGPoint(x: tip - half, y: r.minY))
        p.line(to: CGPoint(x: tip, y: r.minY - tail))
        p.line(to: CGPoint(x: tip + half, y: r.minY))
        p.line(to: CGPoint(x: r.maxX - corner, y: r.minY))
        p.appendArc(from: CGPoint(x: r.maxX, y: r.minY), to: CGPoint(x: r.maxX, y: r.minY + corner), radius: corner)
        p.line(to: CGPoint(x: r.maxX, y: r.maxY - corner))
        p.appendArc(from: CGPoint(x: r.maxX, y: r.maxY), to: CGPoint(x: r.maxX - corner, y: r.maxY), radius: corner)
        p.line(to: CGPoint(x: r.minX + corner, y: r.maxY))
        p.appendArc(from: CGPoint(x: r.minX, y: r.maxY), to: CGPoint(x: r.minX, y: r.maxY - corner), radius: corner)
        p.line(to: CGPoint(x: r.minX, y: r.minY + corner))
        p.appendArc(from: CGPoint(x: r.minX, y: r.minY), to: CGPoint(x: r.minX + corner, y: r.minY), radius: corner)
        p.close()
        p.lineJoinStyle = .round
        return p
    }
}

/// THINKING, ANSWER or NO ANSWER, in a small coloured pill.
final class PillView: NSView {
    var text = "" { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var fill = NSColor.white { didSet { needsDisplay = true } }
    var textColor = NSColor.black { didSet { needsDisplay = true } }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: textColor, .kern: 0.6]
    }

    override var intrinsicContentSize: NSSize {
        let size = (text as NSString).size(withAttributes: attributes)
        return NSSize(width: ceil(size.width) + 18, height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                                withAttributes: attributes)
    }
}

/// A one-point rule under what was asked.
final class DividerView: NSView {
    var color = NSColor.black
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill()
    }
}

/// Three dots that pulse in turn while the answer is on its way.
final class ThinkingDots: NSView {
    var color = NSColor.black
    /// 0 to 1 through one pulse.
    var phase: CGFloat = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let size: CGFloat = 7, gap: CGFloat = 6
        for i in 0..<3 {
            let wave = 0.5 + 0.5 * sin(phase * 2 * .pi - CGFloat(i) * 0.9)
            color.withAlphaComponent(0.2 + 0.7 * wave).setFill()
            let rect = CGRect(x: 1 + CGFloat(i) * (size + gap), y: (bounds.height - size) / 2 + wave * 2,
                              width: size, height: size)
            NSBezierPath(ovalIn: rect).fill()
        }
    }
}

/// The rounded box the follow-up field and its send arrow sit in.
final class ReplyBox: NSView {
    var fill = NSColor.white
    var stroke = NSColor.black
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// A borderless button with a soft highlight under the pointer. The card is
/// never the key window, so the hover tracking is always active.
final class CardButton: NSButton {
    var hoverFill = NSColor.black.withAlphaComponent(0.06)
    private var hovering = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += imagePosition == .imageOnly ? 8 : 14
        size.height = max(size.height, 24)
        return size
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            hoverFill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}
