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
/// before it. Both ways stream, so the card fills in as Claude writes.
///
/// The tool runs with no tools, no MCP servers, no CLAUDE.md and no memory,
/// from an empty folder, so your coding setup does not leak into the answers.
final class Asker {
    private var process: Process?
    private var apiJob: Task<Void, Never>?
    /// Bumped on every ask and cancel, so a late reply to an old question is
    /// dropped instead of replacing the new one.
    private var generation = 0
    /// A `claude` already started and waiting for its question. Starting the
    /// tool takes a few seconds before it even asks Claude, so while LLM mode
    /// is on one is kept ready, and each question takes it.
    private var spare: Spare?
    /// Keep a spare ready. On while LLM mode is on.
    var keepWarm = false
    private var warmConfig: Config?

    private struct Spare {
        let process: Process
        let input: Pipe
        let output: Pipe
        let errors: Pipe
        /// The tool, model and effort it was started with.
        let key: String
        let born: Date

        /// Started with these settings, still running, and not too old.
        func isFresh(for key: String) -> Bool {
            self.key == key && process.isRunning && Date().timeIntervalSince(born) < Asker.spareLifetime
        }
    }

    /// A spare older than this is swapped for a new one when asked, in case
    /// the login it started with has gone stale.
    static let spareLifetime: TimeInterval = 30 * 60

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

    /// The models the LLM menu offers, fastest first.
    static let models: [(id: String, name: String)] = [
        ("claude-haiku-5-5", "Haiku 5.5 (fastest)"),
        ("claude-sonnet-5-5", "Sonnet 5.5"),
        ("claude-opus-5-5", "Opus 5.5 (smartest)"),
    ]

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

    /// A question is out and its answer has not come back yet.
    var isAsking: Bool { process != nil || apiJob != nil }

    func cancel() {
        generation += 1
        process?.terminate()
        process = nil
        apiJob?.cancel()
        apiJob = nil
        // The question that was cut off took the spare, so start the next one.
        if let warm = warmConfig { prewarm(warm) }
    }

    /// Has a `claude` ready for the next question, started with these
    /// settings. Does nothing with an API key, which needs no tool, or when
    /// `keepWarm` is off. A spare started with other settings is replaced.
    func prewarm(_ config: Config) {
        warmConfig = config
        guard keepWarm, APIKey.load() == nil, let exe = Self.claudePath(config.llmClaudePath) else {
            dropSpare()
            return
        }
        if let spare, spare.isFresh(for: Self.spareKey(exe, config)) { return }
        dropSpare()
        let fresh = Self.launch(exe, config)
        spare = fresh
        // Swapped for a new one once it is too old, so a question after a
        // long quiet spell does not start cold.
        guard let born = fresh?.born else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.spareLifetime + 1) { [weak self] in
            guard let self, self.spare?.born == born, let warm = self.warmConfig else { return }
            self.prewarm(warm)
        }
    }

    func dropSpare() {
        spare?.process.terminate()
        spare = nil
    }

    private static func spareKey(_ exe: String, _ config: Config) -> String {
        "\(exe)|\(config.llmModel)|\(config.llmEffort)"
    }

    /// Takes the spare when it was started with these settings and is still
    /// fresh, else nil.
    private func takeSpare(_ key: String) -> Spare? {
        guard let s = spare else { return nil }
        spare = nil
        if s.isFresh(for: key) { return s }
        s.process.terminate()
        return nil
    }

    /// Starts `claude`, which then waits for its question on standard input.
    private static func launch(_ exe: String, _ config: Config) -> Spare? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenCatLLM")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.currentDirectoryURL = folder
        p.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                       "--include-partial-messages",
                       "--tools", "", "--strict-mcp-config", "--disable-slash-commands",
                       "--no-session-persistence", "--model", config.llmModel, "--effort", config.llmEffort,
                       "--system-prompt", systemPrompt]
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
            return nil
        }
        return Spare(process: p, input: input, output: output, errors: errors,
                     key: spareKey(exe, config), born: Date())
    }

    /// Calls `done` once, on the main queue, unless cancelled first. `history`
    /// is the conversation so far on the card, oldest first. `partial` gets
    /// the answer so far, on the main queue, as it streams in.
    func ask(_ question: Question, after history: [Turn] = [], config: Config,
             partial: ((String) -> Void)? = nil, done: @escaping (Answer) -> Void) {
        // The newest settings, so the spare started after this matches them.
        if warmConfig != nil { warmConfig = config }
        cancel()
        let mine = generation
        let finish: (Answer) -> Void = { [weak self] answer in
            DispatchQueue.main.async {
                guard let self, self.generation == mine else { return }
                // Once only: a timeout and the reader can both get here.
                self.generation += 1
                self.process = nil
                self.apiJob = nil
                done(answer)
                // Ready for the next question, now this one is done.
                if let warm = self.warmConfig { self.prewarm(warm) }
            }
        }
        let progress = Self.throttled { [weak self] text in
            DispatchQueue.main.async {
                guard let self, self.generation == mine else { return }
                partial?(text)
            }
        }
        if let apiKey = APIKey.load() {
            askAPI(question, after: history, key: apiKey, config: config, progress: progress, finish: finish)
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
        guard let tool = takeSpare(Self.spareKey(exe, config)) ?? Self.launch(exe, config) else {
            finish(.failed("Could not start claude."))
            return
        }
        let p = tool.process
        process = p

        // Both pipes are drained on their own queues, or a chatty stderr could
        // fill its buffer and stall the process before stdout ends.
        var errorText = ""
        let drained = DispatchGroup()
        drained.enter()
        DispatchQueue.global().async {
            errorText = String(decoding: tool.errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            drained.leave()
        }
        DispatchQueue.global().async {
            // A screenshot is a few MB of base64, so the write can block until
            // claude reads it. Never on the main thread.
            tool.input.fileHandleForWriting.write(line)
            try? tool.input.fileHandleForWriting.close()
        }
        DispatchQueue.global().async {
            // Read as it comes. The answer is complete at the end of Claude's
            // message; the tool then spends a few more seconds on its own
            // bookkeeping before it exits, which nobody needs to wait for.
            var out = Data()
            var pending = Data()
            var stream = CLIStream()
            let handle = tool.output.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                out.append(chunk)
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = pending[pending.startIndex..<newline]
                    pending.removeSubrange(pending.startIndex...newline)
                    switch stream.feed(line) {
                    case .partial(let text):
                        progress(text)
                    case .finished(let answer):
                        finish(answer)
                        p.terminate()
                    case nil:
                        break
                    }
                }
            }
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

    /// Passes on at most one update every 60 ms, so a fast stream does not
    /// lay out the card hundreds of times. The last text always arrives with
    /// the finished answer, so a skipped update is never lost.
    private static func throttled(_ send: @escaping (String) -> Void) -> (String) -> Void {
        let lock = NSLock()
        var last: TimeInterval = 0
        return { text in
            let now = ProcessInfo.processInfo.systemUptime
            lock.lock()
            let due = now - last >= 0.06
            if due { last = now }
            lock.unlock()
            if due { send(text) }
        }
    }

    /// Models that take `fallbacks: "default"`: a declined answer is retried
    /// on another model by the API instead of coming back empty.
    private static let fallbackModels: Set<String> = [
        "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
    ]

    /// Straight to the Claude API with your key, streamed. Two or three
    /// seconds faster than the command line tool, and works on a Mac without
    /// Claude Code.
    private func askAPI(_ question: Question, after history: [Turn], key: String, config: Config,
                        progress: @escaping (String) -> Void, finish: @escaping (Answer) -> Void) {
        var body: [String: Any] = [
            "model": config.llmModel,
            "max_tokens": 16000,
            "stream": true,
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
        apiJob = Task.detached {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else {
                    // An error is one JSON body, not a stream.
                    var whole = Data()
                    for try await byte in bytes { whole.append(byte) }
                    finish(Self.parseAPI(whole, status: status))
                    return
                }
                var stream = APIStream()
                for try await line in bytes.lines {
                    switch stream.feed(line) {
                    case .partial(let text):
                        progress(text)
                    case .finished(let answer):
                        finish(answer)
                        return
                    case nil:
                        break
                    }
                }
                finish(stream.end())
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
                finish(.failed("Could not reach the Claude API: \(error.localizedDescription)"))
            }
        }
    }

    /// An error reply from the API, as a reason to show on the card.
    private static func parseAPI(_ data: Data, status: Int) -> Answer {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed("The Claude API sent back something unreadable (HTTP \(status)).")
        }
        let message = (obj["error"] as? [String: Any])?["message"] as? String ?? "unknown error (HTTP \(status))"
        return .failed(status == 401 ? "Your API key was not accepted: \(message)" : "Claude API error: \(message)")
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

    /// When the stream ended without a finished message: the last line of
    /// claude's output is a "result" event with the reply, or the reason
    /// there is none (not logged in, out of usage, and so on).
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

/// What one line of a stream says: more of the answer, or the end of it.
enum StreamStep {
    case partial(String)
    case finished(Answer)
}

/// Claude's streaming events, shared by the API and the command line tool:
/// text deltas build up the answer, and the end of the message finishes it.
/// Thinking and other blocks are skipped.
struct MessageEvents {
    private(set) var text = ""
    private var stop: String?

    mutating func handle(_ event: [String: Any]) -> StreamStep? {
        switch event["type"] as? String {
        case "content_block_delta":
            guard let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                  let piece = delta["text"] as? String, !piece.isEmpty else { return nil }
            text += piece
            return .partial(text)
        case "message_delta":
            stop = (event["delta"] as? [String: Any])?["stop_reason"] as? String
            return nil
        case "message_stop":
            return .finished(end())
        case "error":
            let message = (event["error"] as? [String: Any])?["message"] as? String ?? "unknown error"
            return .finished(.failed("Claude API error: \(message)"))
        default:
            return nil
        }
    }

    /// The answer as it stands. A refusal drops any text already streamed:
    /// it is not an answer.
    func end() -> Answer {
        if stop == "refusal" { return .failed("Claude would not answer this one.") }
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return answer.isEmpty ? .failed("Claude sent back an empty answer.") : .text(answer)
    }
}

/// The API's server-sent events, one line at a time.
struct APIStream {
    private var events = MessageEvents()

    mutating func feed(_ line: String) -> StreamStep? {
        guard line.hasPrefix("data:") else { return nil }
        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return nil }
        return events.handle(obj)
    }

    func end() -> Answer { events.end() }
}

/// The command line tool's stream-json output, one line at a time. With
/// `--include-partial-messages` it wraps the API's events in "stream_event"
/// lines. Anything else (its own status lines, the final "result") is left
/// to `Asker.parse` once the tool exits.
struct CLIStream {
    private var events = MessageEvents()

    mutating func feed<Bytes: DataProtocol>(_ line: Bytes) -> StreamStep? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              obj["type"] as? String == "stream_event",
              let event = obj["event"] as? [String: Any],
              // The tool retries an API error itself and reports the outcome
              // in its "result" line, so an error here does not end the answer.
              event["type"] as? String != "error" else { return nil }
        return events.handle(event)
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
/// always has; copying the same picture again within the window does not ask
/// a second time. It is fed every poll of the clipboard's change count. All the
/// changes one poll sees count as ONE copy, because some apps clear and then
/// write the clipboard for a single Cmd+C, and those would otherwise ask on
/// every copy.
struct CopyTwiceDetector {
    /// What a clipboard change holds, as far as LLM mode cares.
    enum Content: Equatable {
        case text(String)
        /// A picture, with a cheap fingerprint: its types and size.
        case image(String)
    }

    let window: TimeInterval = 1.0
    private var lastCount: Int
    private var first: (text: String, at: TimeInterval)?
    /// The picture that last asked, so Cmd+C Cmd+C on it asks only once.
    private var lastImage: (key: String, at: TimeInterval)?

    init(changeCount: Int) { lastCount = changeCount }

    /// True when this poll's change should ask. `content` is read only when
    /// the clipboard changed; nil means it can never be a question, and it
    /// breaks any pair in progress.
    mutating func poll(changeCount: Int, at time: TimeInterval, content: () -> Content?) -> Bool {
        guard changeCount != lastCount else { return false }
        lastCount = changeCount
        let now = content()
        if case .image = now {} else { lastImage = nil }
        switch now {
        case nil:
            first = nil
            return false
        case .image(let key):
            first = nil
            if let asked = lastImage, asked.key == key, time - asked.at <= window { return false }
            lastImage = (key, time)
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
        ("image only, copied once (a copied screenshot)", [Copy(at: 0.12, bump: 1, content: .image("p"))], 1),
        ("text copied once, then an image", [Copy(at: 0.12, bump: 1, content: a),
                                            Copy(at: 0.42, bump: 1, content: .image("p"))], 1),
        ("image copied twice", [Copy(at: 0.12, bump: 1, content: .image("p")),
                                Copy(at: 0.42, bump: 1, content: .image("p"))], 1),
        ("two different images", [Copy(at: 0.12, bump: 1, content: .image("p")),
                                  Copy(at: 0.42, bump: 1, content: .image("q"))], 2),
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

    /// What kind of question the clipboard holds. Text is read as text. A
    /// picture's bytes are read every time this runs, to size it for the
    /// fingerprint. It runs once per clipboard change, and in copy-twice mode
    /// once more when a change asks. Copied pictures are rare, so that is
    /// cheap enough. Nil for what can never be a question: private, a file,
    /// or nothing usable.
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
        guard hasImage else { return nil }
        let size = (pb.data(forType: .png) ?? pb.data(forType: .tiff))?.count ?? 0
        return .image(types.sorted().joined(separator: ",") + ":\(size):" + text)
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
