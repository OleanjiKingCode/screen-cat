import AppKit

/// What the cat is asked about: something you copied, or a screenshot.
enum Question {
    case text(String)
    /// PNG data, already shrunk for upload, and where it came from.
    case image(Data, from: String)
    /// Typed on the card, about the answer already there.
    case followUp(String)

    /// For the activity log and the card. Never the full content.
    var summary: String {
        switch self {
        case .text(let s): return "copied text (\(s.count) characters)"
        case .image(_, let from): return from
        case .followUp(let s): return "a follow-up (\(s.count) characters)"
        }
    }

    var isFollowUp: Bool {
        if case .followUp = self { return true }
        return false
    }
}

/// One question on the card and Claude's answer to it. A follow-up is sent
/// with the ones before it, so Claude knows what "it" and "that" are.
struct Turn {
    let question: Question
    let answer: String
}

enum Answer {
    case text(String)
    case failed(String)
}

/// Answers a question with Claude. With your own API key it calls the Claude
/// API directly. Without one it runs the `claude` command line tool with the
/// login it already has. One question at a time: a new one cancels the one
/// before it.
///
/// The tool runs with no tools, no MCP servers, no CLAUDE.md and no memory,
/// from an empty folder, so your coding setup does not leak into the answers.
final class Asker {
    private var process: Process?
    private var task: URLSessionDataTask?
    /// Bumped on every ask and cancel, so a late reply to an old question is
    /// dropped instead of replacing the new one.
    private var generation = 0

    static let systemPrompt = """
    You are the brain of Screen Cat, a desktop pet cat. The user just copied some text or took \
    a screenshot, and the cat shows your reply in a small card. Work out what they want and give it:
    - A question: answer it.
    - Maths (an equation, a sum, a word problem): solve it. Give the final answer, then the few \
    steps that get there.
    - A statement of fact: say whether it is right, and correct it if it is not.
    - A word or phrase: explain what it means.
    - Code or an error message: say what is wrong and how to fix it, or what the code does.
    - A quiz or multiple-choice question: give the correct option and one line on why.
    - Anything else: the most useful short explanation or summary.
    They can then type a follow-up on the card: a question about your answer, or a request such \
    as shorter, simpler, more detail or another language. Answer it in light of what came before.
    Put the answer in the first line. Keep the whole reply short, a few lines, unless the \
    working is needed. Write plain text only: no Markdown, no headings, no bold. Write maths \
    in plain text, for example x^2 + 3x = 10, sqrt(2), pi.
    """

    /// launchd starts the cat with a bare PATH, so the usual install spots are
    /// checked by hand.
    static func claudePath(_ configured: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [configured, "\(home)/.local/bin/claude", "/opt/homebrew/bin/claude",
                          "/usr/local/bin/claude", "\(home)/.claude/local/claude"]
        return candidates
            .filter { !$0.isEmpty }
            .map { ($0 as NSString).expandingTildeInPath }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func cancel() {
        generation += 1
        process?.terminate()
        process = nil
        task?.cancel()
        task = nil
    }

    /// Calls `done` once, on the main queue, unless cancelled first. `history`
    /// is the conversation so far on the card, oldest first.
    func ask(_ question: Question, after history: [Turn] = [], config: Config,
             done: @escaping (Answer) -> Void) {
        cancel()
        let mine = generation
        let finish: (Answer) -> Void = { [weak self] answer in
            DispatchQueue.main.async {
                guard let self, self.generation == mine else { return }
                // Once only: a timeout and the reader can both get here.
                self.generation += 1
                self.process = nil
                self.task = nil
                done(answer)
            }
        }
        if let key = APIKey.load() {
            askAPI(question, after: history, key: key, config: config, finish: finish)
            return
        }
        guard let exe = Self.claudePath(config.llmClaudePath) else {
            finish(.failed("Could not find the claude command. Install Claude Code, or set llmClaudePath in settings."))
            return
        }
        guard let line = Self.inputLine(question, after: history) else {
            finish(.failed("Could not read what you copied."))
            return
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenCatLLM")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.currentDirectoryURL = folder
        p.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                       "--tools", "", "--strict-mcp-config", "--disable-slash-commands",
                       "--no-session-persistence", "--model", config.llmModel, "--effort", config.llmEffort,
                       "--system-prompt", Self.systemPrompt]
        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] = "1"
        env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
        env["PATH"] = [env["PATH"], "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            .compactMap { $0 }.joined(separator: ":")
        p.environment = env
        let input = Pipe(), output = Pipe(), errors = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = errors
        do {
            try p.run()
        } catch {
            finish(.failed("Could not start claude: \(error.localizedDescription)"))
            return
        }
        process = p

        // Both pipes are drained on their own queues, or a chatty stderr could
        // fill its buffer and stall the process before stdout ends.
        var errorText = ""
        let drained = DispatchGroup()
        drained.enter()
        DispatchQueue.global().async {
            errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            drained.leave()
        }
        DispatchQueue.global().async {
            // A screenshot is a few MB of base64, so the write can block until
            // claude reads it. Never on the main thread.
            input.fileHandleForWriting.write(line)
            try? input.fileHandleForWriting.close()
        }
        DispatchQueue.global().async {
            let out = output.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            drained.wait()
            finish(Self.parse(out, status: p.terminationStatus, errors: errorText))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak self] in
            guard let self, self.generation == mine, p.isRunning else { return }
            p.terminate()
            finish(.failed("No answer after three minutes, so the cat gave up."))
        }
    }

    /// Models that take `fallbacks: "default"`: a declined answer is retried
    /// on another model by the API instead of coming back empty.
    private static let fallbackModels: Set<String> = [
        "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
    ]

    /// Straight to the Claude API with your key. Two or three seconds faster
    /// than the command line tool, and works on a Mac without Claude Code.
    private func askAPI(_ question: Question, after history: [Turn], key: String, config: Config,
                        finish: @escaping (Answer) -> Void) {
        var body: [String: Any] = [
            "model": config.llmModel,
            "max_tokens": 16000,
            "system": Self.systemPrompt,
            "output_config": ["effort": config.llmEffort],
            "messages": Self.messages(question, after: history),
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if Self.fallbackModels.contains(config.llmModel) {
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            finish(.failed("Could not build the request."))
            return
        }
        request.httpBody = data
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error as? URLError, error.code == .cancelled { return }
            if let error {
                finish(.failed("Could not reach the Claude API: \(error.localizedDescription)"))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            finish(Self.parseAPI(data ?? Data(), status: status))
        }
        self.task = task
        task.resume()
    }

    /// The reply's text blocks, joined; thinking blocks are skipped. A refusal
    /// or an API error comes back as a reason to show on the card.
    private static func parseAPI(_ data: Data, status: Int) -> Answer {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed("The Claude API sent back something unreadable (HTTP \(status)).")
        }
        if let error = obj["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "unknown error"
            return .failed(status == 401 ? "Your API key was not accepted: \(message)" : "Claude API error: \(message)")
        }
        if obj["stop_reason"] as? String == "refusal" {
            return .failed("Claude would not answer this one.")
        }
        let blocks = obj["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? .failed("Claude sent back an empty answer.") : .text(text)
    }

    /// The conversation as API messages: each earlier question and its
    /// answer, then the new one.
    private static func messages(_ question: Question, after history: [Turn]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for turn in history {
            out.append(["role": "user", "content": content(turn.question)])
            out.append(["role": "assistant", "content": [["type": "text", "text": turn.answer]]])
        }
        out.append(["role": "user", "content": content(question)])
        return out
    }

    /// The user message: the copied text, the screenshot, or a follow-up.
    private static func content(_ question: Question) -> [[String: Any]] {
        switch question {
        case .text(let s):
            return [["type": "text", "text": "I copied this:\n<copied>\n\(s)\n</copied>"]]
        case .followUp(let s):
            return [["type": "text", "text": s]]
        case .image(let png, _):
            return [
                ["type": "image", "source": ["type": "base64", "media_type": "image/png",
                                             "data": png.base64EncodedString()]],
                ["type": "text", "text": "I took this screenshot."],
            ]
        }
    }

    /// One stream-json user message for the command line tool. It takes only
    /// user messages, so for a follow-up the earlier answers are written into
    /// that one message, each after the question it answered.
    private static func inputLine(_ question: Question, after history: [Turn]) -> Data? {
        var blocks: [[String: Any]] = []
        for turn in history {
            blocks += content(turn.question)
            blocks.append(["type": "text", "text": "You answered:\n<answer>\n\(turn.answer)\n</answer>"])
        }
        blocks += content(question)
        let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": blocks]]
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return nil }
        data.append(0x0A)
        return data
    }

    /// The last line of claude's output is a "result" event with the reply,
    /// or the reason there is none (not logged in, out of usage, and so on).
    private static func parse(_ out: Data, status: Int32, errors: String) -> Answer {
        for line in String(decoding: out, as: UTF8.self).split(separator: "\n").reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["type"] as? String == "result" else { continue }
            let result = (obj["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if obj["is_error"] as? Bool == true || obj["subtype"] as? String != "success" || result.isEmpty {
                return .failed(result.isEmpty ? "claude stopped: \(obj["subtype"] as? String ?? "no reply")" : result)
            }
            return .text(result)
        }
        let tail = errors.split(separator: "\n").last.map(String.init) ?? ""
        return .failed(tail.isEmpty ? "claude exited with code \(status) and no answer." : tail)
    }
}

/// Your own Anthropic API key, kept in the login keychain and never in the
/// settings file. `ANTHROPIC_API_KEY` in the environment works too, for
/// running the binary from a terminal.
enum APIKey {
    private static let service = "local.screencat"
    private static let account = "anthropic-api-key"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static var isSet: Bool { load() != nil }

    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data {
            let key = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { return key }
        }
        let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return env.isEmpty ? nil : env
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        var q = query
        q[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// Shrinks an image so its long edge is at most 1568 px, the most Claude
/// looks at, and returns it as PNG. A Retina screenshot is far bigger than
/// that, and sending the full size only makes the upload slower.
func pngForUpload(_ image: NSImage) -> Data? {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let scale = min(1, 1568 / CGFloat(max(cg.width, cg.height)))
    let w = max(1, Int(CGFloat(cg.width) * scale)), h = max(1, Int(CGFloat(cg.height) * scale))
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    ctx.cgContext.interpolationQuality = .high
    ctx.cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return rep.representation(using: .png, properties: [:])
}

/// Copy-twice mode's trigger. For text, the same text copied twice in a row,
/// within `window` seconds, is a question; one copy is just a copy. A copied
/// picture (such as a screenshot copied with Control) asks at once, as it
/// always has. It is fed every poll of the clipboard's change count. All the
/// changes one poll sees count as ONE copy, because some apps clear and then
/// write the clipboard for a single Cmd+C, and those would otherwise ask on
/// every copy.
struct CopyTwiceDetector {
    /// What a clipboard change holds, as far as LLM mode cares.
    enum Content: Equatable {
        case text(String)
        case image
    }

    let window: TimeInterval = 1.0
    private var lastCount: Int
    private var first: (text: String, at: TimeInterval)?

    init(changeCount: Int) { lastCount = changeCount }

    /// True when this poll's change should ask. `content` is read only when
    /// the clipboard changed; nil means it can never be a question, and it
    /// breaks any pair in progress.
    mutating func poll(changeCount: Int, at time: TimeInterval, content: () -> Content?) -> Bool {
        guard changeCount != lastCount else { return false }
        lastCount = changeCount
        switch content() {
        case nil:
            first = nil
            return false
        case .image:
            first = nil
            return true
        case .text(let text):
            if let pending = first, pending.text == text, time - pending.at <= window {
                first = nil
                return true
            }
            first = (text, time)
            return false
        }
    }
}

/// `--copy-twice-selftest`: plays scripted copy sequences through the
/// detector, polled every 0.05 s as the app does, and prints PASS or FAIL for
/// each. Never touches the real clipboard, except to time how long reading
/// its change count takes.
func runCopyTwiceSelfTest() -> Bool {
    typealias Content = CopyTwiceDetector.Content
    struct Copy { let at: TimeInterval; let bump: Int; let content: Content? }
    let a = Content.text("a"), b = Content.text("b")
    let cases: [(String, [Copy], Int)] = [
        ("single copy", [Copy(at: 0.12, bump: 1, content: a)], 0),
        ("double copy 0.3 s apart", [Copy(at: 0.12, bump: 1, content: a), Copy(at: 0.42, bump: 1, content: a)], 1),
        ("double copy 1.5 s apart", [Copy(at: 0.12, bump: 1, content: a), Copy(at: 1.62, bump: 1, content: a)], 0),
        ("one copy that bumps the count by 2", [Copy(at: 0.12, bump: 2, content: a)], 0),
        ("two different texts", [Copy(at: 0.12, bump: 1, content: a), Copy(at: 0.42, bump: 1, content: b)], 0),
        ("triple copy", [Copy(at: 0.12, bump: 1, content: a), Copy(at: 0.37, bump: 1, content: a),
                         Copy(at: 0.62, bump: 1, content: a)], 1),
        ("double copy of a password", [Copy(at: 0.12, bump: 1, content: nil),
                                       Copy(at: 0.42, bump: 1, content: nil)], 0),
        ("double copy in an app that writes twice", [Copy(at: 0.12, bump: 2, content: a),
                                                     Copy(at: 0.42, bump: 2, content: a)], 1),
        ("double copy, then the same text once more later",
         [Copy(at: 0.12, bump: 1, content: a), Copy(at: 0.42, bump: 1, content: a),
          Copy(at: 2.02, bump: 1, content: a)], 1),
        ("image only, copied once (a copied screenshot)", [Copy(at: 0.12, bump: 1, content: .image)], 1),
        ("text copied once, then an image", [Copy(at: 0.12, bump: 1, content: a),
                                            Copy(at: 0.42, bump: 1, content: .image)], 1),
    ]
    var allPassed = true
    for (name, copies, expected) in cases {
        var detector = CopyTwiceDetector(changeCount: 100)
        var count = 100
        var current: Content?
        var next = 0
        var asks = 0
        for tick in 0...80 {
            let now = Double(tick) * 0.05
            while next < copies.count, copies[next].at <= now {
                count += copies[next].bump
                current = copies[next].content
                next += 1
            }
            if detector.poll(changeCount: count, at: now, content: { current }) { asks += 1 }
        }
        let passed = asks == expected
        allPassed = allPassed && passed
        print("\(passed ? "PASS" : "FAIL")  \(name): asked \(asks), expected \(expected)")
    }
    let reads = 2000
    let started = ProcessInfo.processInfo.systemUptime
    var sum = 0
    for _ in 0..<reads { sum &+= NSPasteboard.general.changeCount }
    let each = (ProcessInfo.processInfo.systemUptime - started) / Double(reads) * 1_000_000
    print(String(format: "reading the change count: %.1f microseconds a read, %.2f ms a second at 20 polls",
                 each, each * 20 / 1000))
    return allPassed
}

/// LLM mode's ears: new clipboard contents and new screenshots.
final class QuestionWatch {
    var onQuestion: ((Question) -> Void)?
    /// Every-copy mode only: text found in the last answer, such as a line
    /// copied out of it some other way, is not a new question.
    var isOwnText: ((String) -> Bool)?
    /// The change count after the cat, or a Cmd+C or Cmd+X in its card,
    /// wrote the clipboard, so that change is skipped.
    var ownChange = -1

    private var timer: Timer?
    private var lastChange = 0
    private var lastText = ""
    /// Only a copy made twice in a row asks. See `CopyTwiceDetector`.
    private var copyTwice = false
    private var detector = CopyTwiceDetector(changeCount: 0)
    private var sources: [DispatchSourceFileSystemObject] = []
    private var folders: [URL] = []
    private var seen: Set<String> = []
    private var since = Date()

    /// Password managers mark what they copy with these, so a password is
    /// never sent anywhere. See nspasteboard.org.
    private static let privateTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
    ]

    var isRunning: Bool { timer != nil || !sources.isEmpty }

    /// Only what changes after this call counts. Whatever is already on the
    /// clipboard, or already on the Desktop, is left alone. With `copyTwice`,
    /// one copy of text is ignored and only the same text copied twice in a
    /// row asks; a copied picture asks at once.
    func start(clipboard: Bool, screenshots: Bool, copyTwice: Bool) {
        stop()
        lastChange = NSPasteboard.general.changeCount
        self.copyTwice = copyTwice
        detector = CopyTwiceDetector(changeCount: lastChange)
        if clipboard {
            // Fast enough in copy-twice mode that the two presses of a quick
            // Cmd+C Cmd+C land in two different polls.
            let interval = copyTwice ? 0.05 : 0.4
            let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.checkClipboard() }
            t.tolerance = copyTwice ? 0.01 : 0.1
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        if screenshots { watchScreenshots() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        sources.forEach { $0.cancel() }
        sources = []
    }

    /// What is on the clipboard now, for the menu's one-off ask. Nil when it
    /// is empty, private, or a file.
    static func clipboardQuestion() -> Question? {
        switch clipboardContent() {
        case .text(let text)?:
            return .text(text)
        case .image?:
            guard let image = NSImage(pasteboard: .general), let png = pngForUpload(image) else { return nil }
            return .image(png, from: "copied image")
        case nil:
            return nil
        }
    }

    /// What kind of question the clipboard holds, without reading a picture
    /// into memory. Nil for what can never be a question: private, a file, or
    /// nothing usable.
    static func clipboardContent() -> CopyTwiceDetector.Content? {
        let pb = NSPasteboard.general
        let types = Set((pb.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: privateTypes),
              !types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) else { return nil }
        let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasImage = pb.canReadObject(forClasses: [NSImage.self], options: nil)
        // "Copy Image" in a browser also puts the image's address there. The
        // picture is the question, not the link.
        let justALink = (text.hasPrefix("http://") || text.hasPrefix("https://"))
            && !text.contains(where: \.isWhitespace)
        if text.count >= 2, !(hasImage && justALink) { return .text(text) }
        return hasImage ? .image : nil
    }

    private func checkClipboard() {
        let pb = NSPasteboard.general
        if copyTwice {
            // Copies the cat or its card made set `ownChange`, so they never
            // count. A double copy is on purpose, so the same text asks again
            // even when it also appears in the last answer.
            let count = pb.changeCount
            let asks = detector.poll(changeCount: count, at: ProcessInfo.processInfo.systemUptime) {
                count == ownChange ? nil : Self.clipboardContent()
            }
            guard asks, let question = Self.clipboardQuestion() else { return }
            onQuestion?(question)
            return
        }
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        guard pb.changeCount != ownChange, let question = Self.clipboardQuestion() else { return }
        if case .text(let s) = question {
            // Copying the same thing twice in a row is not a new question.
            guard s != lastText, !(isOwnText?(s) ?? false) else { return }
            lastText = s
        }
        onQuestion?(question)
    }

    // MARK: Screenshots

    /// Where screenshots land: the folder set in the Screenshot app, if any,
    /// and the Desktop, which is the default.
    private static func screenshotFolders() -> [URL] {
        var paths: [String] = []
        for key in ["location", "location-last"] {
            if let p = CFPreferencesCopyAppValue(key as CFString, "com.apple.screencapture" as CFString) as? String {
                paths.append(p)
            }
        }
        paths.append("~/Desktop")
        var seen: Set<String> = []
        return paths
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL }
            .filter { seen.insert($0.path).inserted }
            .filter { var dir: ObjCBool = false
                      return FileManager.default.fileExists(atPath: $0.path, isDirectory: &dir) && dir.boolValue }
    }

    private func watchScreenshots() {
        since = Date()
        seen = []
        folders = Self.screenshotFolders()
        for folder in folders {
            let fd = open(folder.path, O_EVTONLY)
            guard fd >= 0 else {
                ActivityLog.shared.cat("llm: cannot watch \(folder.path) for screenshots")
                continue
            }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            source.setEventHandler { [weak self] in
                // The file can land a moment before its screenshot tag does,
                // so look twice.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.scan() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self?.scan() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    private func scan() {
        guard !sources.isEmpty else { return }
        let images: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]
        for folder in folders {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) else { continue }
            for url in files where !seen.contains(url.path) && images.contains(url.pathExtension.lowercased()) {
                guard let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
                      created > since, Self.isScreenshot(url) else { continue }
                seen.insert(url.path)
                guard let image = NSImage(contentsOf: url), let png = pngForUpload(image) else { continue }
                onQuestion?(.image(png, from: "screenshot"))
            }
        }
    }

    /// macOS tags every screenshot it saves, whatever the file is called and
    /// whatever language the name is in.
    private static func isScreenshot(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
    }
}
