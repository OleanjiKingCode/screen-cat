import AppKit

/// The card the cat sits under in LLM mode, with the answer in it. A small
/// floating panel rather than paint on the overlay, so the text can be
/// selected, scrolled and copied. It never takes focus from your app, and it
/// follows the same screenshot setting as the cat, until you click into the
/// follow-up field under an answer to ask more.
final class AnswerPanel: NSPanel, NSTextFieldDelegate {
    /// The card was closed by you or timed out. Not called by `dismiss()`.
    var onClose: (() -> Void)?
    /// The answer was put on the clipboard, by the button or automatically.
    var onCopy: (() -> Void)?
    /// Typed into the field under the answer and sent with Enter or ASK.
    var onFollowUp: ((String) -> Void)?
    private(set) var answer = ""

    private static let width: CGFloat = 380
    private static let maxTextHeight: CGFloat = 320
    private let ink: NSColor
    private let heading = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private let scroll = NSScrollView()
    private let copyButton = NSButton()
    private let reply = NSTextField()
    private let askButton = NSButton()
    private var scrollToCard: NSLayoutConstraint!
    private var scrollToReply: NSLayoutConstraint!
    private var dots = 0
    private var thinkingTimer: Timer?
    private var closeTimer: Timer?
    private var secondsLeft: CGFloat = 0
    private var anchor = CGPoint.zero
    private var area = CGRect.zero

    init(palette: Palette) {
        ink = palette.outline
        super.init(contentRect: CGRect(x: 0, y: 0, width: Self.width, height: 120),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        // Same as the cat's window: on every Space, over full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // The card is drawn in the bubble's fixed light colours.
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

    /// The cat's speech bubble, grown up: off-white with a chunky outline.
    private func buildContent() {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(white: 0.98, alpha: 1).cgColor
        card.layer?.borderColor = ink.cgColor
        card.layer?.borderWidth = 3
        contentView = card

        heading.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        heading.textColor = ink

        copyButton.target = self
        copyButton.action = #selector(copyAnswer)
        label(copyButton, "COPY")
        let close = NSButton(title: "", target: self, action: #selector(closeByUser))
        label(close, "✕")
        close.toolTip = "Close (Esc)"

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = ink
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        reply.placeholderString = "Ask a follow-up…"
        reply.font = .systemFont(ofSize: 13)
        reply.bezelStyle = .roundedBezel
        reply.delegate = self
        reply.target = self
        reply.action = #selector(sendFollowUp)
        askButton.target = self
        askButton.action = #selector(sendFollowUp)
        label(askButton, "ASK")

        for v in [heading, copyButton, close, scroll, reply, askButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(v)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            heading.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            close.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            close.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -6),
            copyButton.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
            reply.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            reply.trailingAnchor.constraint(equalTo: askButton.leadingAnchor, constant: -8),
            reply.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            askButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            askButton.centerYAnchor.constraint(equalTo: reply.centerYAnchor),
        ])
        // The text runs down to the field when it shows, else to the edge.
        scrollToCard = scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        scrollToReply = scroll.bottomAnchor.constraint(equalTo: reply.topAnchor, constant: -10)
        showReply(false)
    }

    /// Shows the card above `anchor` (a global point, the top of the cat's
    /// head) while the answer is on its way, with what was asked in grey.
    func showThinking(_ question: Question, above anchor: CGPoint, within screen: CGRect) {
        self.anchor = anchor
        area = screen
        stopTimers()
        answer = ""
        copyButton.isHidden = true
        showReply(false)
        let asked: String
        switch question {
        case .text(let s), .followUp(let s):
            let line = s.replacingOccurrences(of: "\n", with: " ")
            asked = line.count > 160 ? String(line.prefix(160)) + "…" : line
        case .image(_, let from):
            asked = from == "screenshot" ? "Your screenshot" : "Your copied image"
        }
        setBody(asked, color: ink.withAlphaComponent(0.55))
        dots = 0
        heading.stringValue = "THINKING"
        thinkingTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.dots = (self.dots + 1) % 4
            self.heading.stringValue = "THINKING" + String(repeating: ".", count: self.dots)
        }
        orderFrontRegardless()
    }

    /// The answer, and a countdown to close it. Resting the pointer on the
    /// card holds the countdown, so it never vanishes while you read.
    func showAnswer(_ text: String, closeAfter seconds: CGFloat) {
        stopTimers()
        answer = text
        heading.stringValue = "ANSWER"
        copyButton.isHidden = false
        showReply(true)
        setBody(text, color: ink)
        startCloseTimer(seconds)
    }

    func showError(_ text: String, closeAfter seconds: CGFloat) {
        stopTimers()
        answer = ""
        heading.stringValue = "NO ANSWER"
        copyButton.isHidden = true
        showReply(true)
        setBody(text, color: NSColor(srgbRed: 0.7, green: 0.12, blue: 0.2, alpha: 1))
        startCloseTimer(seconds)
    }

    /// Takes the card away without telling anyone: the cat is already going.
    func dismiss() {
        stopTimers()
        reply.stringValue = ""
        orderOut(nil)
    }

    /// The field shows under an answer, not while one is on its way. Once
    /// you have clicked into it, it keeps the focus for the next follow-up.
    private func showReply(_ shown: Bool) {
        if !shown, reply.currentEditor() != nil { makeFirstResponder(nil) }
        reply.isHidden = !shown
        askButton.isHidden = !shown
        NSLayoutConstraint.deactivate([shown ? scrollToCard : scrollToReply])
        NSLayoutConstraint.activate([shown ? scrollToReply : scrollToCard])
        if shown, isKeyWindow { makeFirstResponder(reply) }
    }

    @objc private func sendFollowUp() {
        let text = reply.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        reply.stringValue = ""
        onFollowUp?(text)
    }

    /// Typing a follow-up holds the countdown, like resting the pointer.
    private var isReplying: Bool {
        (isKeyWindow && reply.currentEditor() != nil) || !reply.stringValue.isEmpty
    }

    @objc private func closeByUser() {
        dismiss()
        onClose?()
    }

    @objc func copyAnswer() {
        guard !answer.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
        onCopy?()
        label(copyButton, "COPIED")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.label(self.copyButton, "COPY")
        }
    }

    /// Plain ink text, no bezel. A bezel button greys out whenever the card
    /// is not focused, which is nearly always.
    private func label(_ button: NSButton, _ title: String) {
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: ink,
        ])
    }

    private func setBody(_ text: String, color: NSColor) {
        textView.string = text
        textView.textColor = color
        textView.font = .systemFont(ofSize: 13)
        resize()
    }

    /// Grows to fit the text up to a cap, then scrolls. The bottom edge stays
    /// just above the cat's head, kept inside the screen.
    private func resize() {
        let textWidth = Self.width - 28
        textView.frame = CGRect(x: 0, y: 0, width: textWidth, height: 10)
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
        container.containerSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let textHeight = min(Self.maxTextHeight, max(18, ceil(layout.usedRect(for: container).height)))
        let replyHeight = reply.isHidden ? 0 : reply.intrinsicContentSize.height + 10
        let height = textHeight + 12 + 16 + 10 + 14 + replyHeight
        // No screen given yet: use the main one, never an empty rect, which
        // AppKit rejects as a window frame.
        let given = area.width > 24 && area.height > 24 ? area : (NSScreen.main?.visibleFrame ?? .zero)
        let room = given.insetBy(dx: 12, dy: 12)
        var x = anchor.x - Self.width / 2
        x = min(max(x, room.minX), room.maxX - Self.width)
        var y = anchor.y + 8
        y = min(y, room.maxY - height)
        setFrame(CGRect(x: x, y: y, width: Self.width, height: height), display: true)
    }

    private func startCloseTimer(_ seconds: CGFloat) {
        guard seconds > 0 else { return }
        secondsLeft = seconds
        closeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.frame.contains(NSEvent.mouseLocation) || self.isReplying { return }
            self.secondsLeft -= 1
            if self.secondsLeft <= 0 { self.closeByUser() }
        }
    }

    private func stopTimers() {
        thinkingTimer?.invalidate()
        thinkingTimer = nil
        closeTimer?.invalidate()
        closeTimer = nil
    }
}
