import AppKit

/// What the cat is asked about: something you copied, or a screenshot.
enum Question {
    case text(String)
    /// PNG data, already shrunk for upload, and where it came from.
    case image(Data, from: String)

    /// For the activity log and the card. Never the full content.
    var summary: String {
        switch self {
        case .text(let s): return "copied text (\(s.count) characters)"
        case .image(_, let from): return from
        }
    }
}

enum Answer {
    case text(String)
    case failed(String)
}

/// Answers a question with the `claude` command line tool and the login it
/// already has, so LLM mode needs no API key. One question at a time: a new
/// one cancels the one before it.
///
/// The tool runs with no tools, no MCP servers, no CLAUDE.md and no memory,
/// from an empty folder, so your coding setup does not leak into the answers.
final class Asker {
    private var process: Process?
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
    }

    /// Calls `done` once, on the main queue, unless cancelled first.
    func ask(_ question: Question, config: Config, done: @escaping (Answer) -> Void) {
        cancel()
        let mine = generation
        let finish: (Answer) -> Void = { [weak self] answer in
            DispatchQueue.main.async {
                guard let self, self.generation == mine else { return }
                // Once only: a timeout and the reader can both get here.
                self.generation += 1
                self.process = nil
                done(answer)
            }
        }
        guard let exe = Self.claudePath(config.llmClaudePath) else {
            finish(.failed("Could not find the claude command. Install Claude Code, or set llmClaudePath in settings."))
            return
        }
        guard let line = Self.inputLine(question) else {
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

    /// One stream-json user message: the copied text, or the screenshot.
    private static func inputLine(_ question: Question) -> Data? {
        let content: [[String: Any]]
        switch question {
        case .text(let s):
            content = [["type": "text", "text": "I copied this:\n<copied>\n\(s)\n</copied>"]]
        case .image(let png, _):
            content = [
                ["type": "image", "source": ["type": "base64", "media_type": "image/png",
                                             "data": png.base64EncodedString()]],
                ["type": "text", "text": "I took this screenshot."],
            ]
        }
        let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": content]]
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

/// LLM mode's ears: new clipboard contents and new screenshots.
final class QuestionWatch {
    var onQuestion: ((Question) -> Void)?
    /// Text the cat itself put there, such as a line copied out of an answer.
    /// It is not a new question.
    var isOwnText: ((String) -> Bool)?
    /// Set after the cat writes the clipboard, so that change is skipped.
    var ownChange = -1

    private var timer: Timer?
    private var lastChange = 0
    private var lastText = ""
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
    /// clipboard, or already on the Desktop, is left alone.
    func start(clipboard: Bool, screenshots: Bool) {
        stop()
        lastChange = NSPasteboard.general.changeCount
        if clipboard {
            let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.checkClipboard() }
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
        if hasImage, let image = NSImage(pasteboard: pb), let png = pngForUpload(image) {
            return .image(png, from: "copied image")
        }
        return nil
    }

    private func checkClipboard() {
        let pb = NSPasteboard.general
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
