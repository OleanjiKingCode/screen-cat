import AppKit
import CoreBluetooth

/// A plain-text diary of what happens on this Mac, one file per day in
/// ~/Library/Logs/ScreenCat. It records which app is in front and for how long,
/// apps and background helpers starting and quitting, sleep, wake, lock and
/// idle, Bluetooth on or off, hourly lists of everything running, and what the
/// cat did, including whether it was really on screen when you switched apps.
/// That last part is there to find the apps the cat does not show over.
///
/// Nothing leaves the machine. No window titles, no keystrokes, no screen
/// contents: only app names, process names and times.
final class ActivityLog: NSObject, CBCentralManagerDelegate {
    static let shared = ActivityLog()

    /// Asked a second after an app or Space switch. Returns a line about the
    /// cat, or nil when it is not out.
    var catStatus: (() -> String?)?
    /// The pending ask, so a quick run of switches is reported once.
    private var catCheck: DispatchWorkItem?

    private var started = false
    private var bluetooth: CBCentralManager?
    private var lastBluetooth: String?
    private var frontmost: (name: String, since: Date)?
    private var idleSince: Date?
    private var timers: [Timer] = []
    private let idleThreshold: TimeInterval = 300

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ScreenCat")
    }

    static var todayURL: URL {
        folder.appendingPathComponent("activity-\(stamp("yyyy-MM-dd", Date())).txt")
    }

    func start(keepDays: Int) {
        guard !started else { return }
        started = true
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        prune(keepDays: keepDays)
        write("START", "Screen Cat started (macOS \(ProcessInfo.processInfo.operatingSystemVersionString))")

        let ws = NSWorkspace.shared.notificationCenter
        let workspace: [(Notification.Name, Selector)] = [
            (NSWorkspace.didActivateApplicationNotification, #selector(appActivated(_:))),
            (NSWorkspace.activeSpaceDidChangeNotification, #selector(spaceChanged)),
            (NSWorkspace.didLaunchApplicationNotification, #selector(appLaunched(_:))),
            (NSWorkspace.didTerminateApplicationNotification, #selector(appQuit(_:))),
            (NSWorkspace.willSleepNotification, #selector(willSleep)),
            (NSWorkspace.didWakeNotification, #selector(didWake)),
            (NSWorkspace.screensDidSleepNotification, #selector(displayOff)),
            (NSWorkspace.screensDidWakeNotification, #selector(displayOn)),
            (NSWorkspace.sessionDidResignActiveNotification, #selector(userSwitchedOut)),
            (NSWorkspace.sessionDidBecomeActiveNotification, #selector(userSwitchedIn)),
            (NSWorkspace.willPowerOffNotification, #selector(powerOff)),
        ]
        for (name, selector) in workspace { ws.addObserver(self, selector: selector, name: name, object: nil) }
        let dist = DistributedNotificationCenter.default()
        dist.addObserver(self, selector: #selector(locked), name: .init("com.apple.screenIsLocked"), object: nil)
        dist.addObserver(self, selector: #selector(unlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)

        if let app = NSWorkspace.shared.frontmostApplication {
            frontmost = (name(of: app), Date())
            write("APP", "in front: \(name(of: app))")
        }
        snapshot("at start")

        // CoreBluetooth reports power changes as they happen, so nothing polls.
        // Creating the manager without the usage string in Info.plist kills the
        // process, so a bare binary run outside the .app skips Bluetooth.
        // Started from a terminal, macOS checks Bluetooth against the terminal,
        // which has no usage string either, and kills this process. Only an
        // app launched normally (parent is launchd) asks for itself.
        if Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil,
           getppid() == 1 {
            bluetooth = CBCentralManager(delegate: self, queue: nil,
                                         options: [CBCentralManagerOptionShowPowerAlertKey: false])
        } else {
            write("BLUETOOTH", "not checked (started from a terminal, not as an app)")
        }

        timers.append(Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkIdle()
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.snapshot("hourly")
        })
    }

    /// Something the cat did: came out, went in, or hid and why.
    func cat(_ message: String) {
        guard started else { return }
        write("CAT", message)
    }

    func stop() {
        guard started else { return }
        closeFrontmost()
        write("STOP", "Screen Cat quit")
    }

    // MARK: - Apps

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let new = name(of: app)
        var line = "in front: \(new)"
        if let previous = frontmost, previous.name != new {
            line += "  (after \(previous.name) for \(duration(Date().timeIntervalSince(previous.since))))"
        }
        if fullscreen(app) { line += "  [fullscreen]" }
        frontmost = (new, Date())
        write("APP", line)
        reportCatSoon()
    }

    @objc private func spaceChanged() { reportCatSoon() }

    /// The cat line waits a second for the switch to settle. The app comes to
    /// the front before its Space slides in, so asking at once described the
    /// Space you were leaving.
    private func reportCatSoon() {
        catCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in
            if let cat = self?.catStatus?() { self?.write("CAT", cat) }
        }
        catCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: check)
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        write(app.activationPolicy == .regular ? "OPENED" : "BG-START", name(of: app))
    }

    @objc private func appQuit(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        write(app.activationPolicy == .regular ? "QUIT" : "BG-STOP", name(of: app))
    }

    private func closeFrontmost() {
        guard let previous = frontmost else { return }
        write("APP", "\(previous.name) was in front for \(duration(Date().timeIntervalSince(previous.since)))")
    }

    /// A window of `app` covering a whole display, menu bar included.
    private func fullscreen(_ app: NSRunningApplication) -> Bool {
        let wins = Watching.windows(of: [app.processIdentifier])
        return NSScreen.screens.contains { screen in
            wins.contains { $0.rect.width >= screen.frame.width - 2 && $0.rect.height >= screen.frame.height - 2 }
        }
    }

    // MARK: - Sleep, lock, idle

    @objc private func willSleep() { closeFrontmost(); write("SLEEP", "Mac going to sleep") }
    @objc private func didWake() {
        write("WAKE", "Mac woke up")
        if let app = NSWorkspace.shared.frontmostApplication { frontmost = (name(of: app), Date()) }
        snapshot("after wake")
    }
    @objc private func displayOff() { write("DISPLAY", "screen turned off") }
    @objc private func displayOn() { write("DISPLAY", "screen turned on") }
    @objc private func locked() { write("LOCK", "screen locked") }
    @objc private func unlocked() { write("LOCK", "screen unlocked") }
    @objc private func userSwitchedOut() { write("USER", "switched to another user") }
    @objc private func userSwitchedIn() { write("USER", "back to this user") }
    @objc private func powerOff() { closeFrontmost(); write("POWER", "shutting down or restarting") }

    /// No keyboard, mouse or trackpad input for five minutes counts as idle.
    /// Reading the idle time needs no permission.
    private func checkIdle() {
        let anyInput = CGEventType(rawValue: ~0) ?? .null
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if idle >= idleThreshold, idleSince == nil {
            let since = Date(timeIntervalSinceNow: -idle)
            idleSince = since
            write("IDLE", "no input since \(Self.stamp("HH:mm:ss", since))")
        } else if idle < idleThreshold, let since = idleSince {
            idleSince = nil
            write("IDLE", "back after \(duration(Date().timeIntervalSince(since))) away")
        }
    }

    // MARK: - Bluetooth

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state: String
        switch central.state {
        case .poweredOn: state = "on"
        case .poweredOff: state = "off"
        case .unauthorized: state = "unknown (allow Screen Cat in Privacy & Security > Bluetooth)"
        case .unsupported: state = "not available on this Mac"
        case .resetting: state = "restarting"
        default: state = "unknown"
        }
        guard state != lastBluetooth else { return }
        lastBluetooth = state
        write("BLUETOOTH", state)
    }

    // MARK: - What is running

    /// Every open app, every background helper with a bundle, and your own
    /// command-line processes (node, python, docker and the like). System
    /// daemons are left out; there are hundreds and they never change.
    private func snapshot(_ when: String) {
        let me = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter { $0.processIdentifier != me }
        let open = grouped(apps.filter { $0.activationPolicy == .regular }.map(name(of:)))
        let background = grouped(apps.filter { $0.activationPolicy != .regular }.map(name(of:)))
        write("RUNNING", "\(when): \(open.count) open apps: \(open.joined(separator: ", "))")
        write("RUNNING", "\(when): \(background.count) background apps: \(background.joined(separator: ", "))")
        let tools = grouped(commandLineProcesses())
        write("RUNNING", "\(when): \(tools.count) command-line processes: \(tools.isEmpty ? "none" : tools.joined(separator: ", "))")
        if let bt = lastBluetooth { write("BLUETOOTH", "\(bt) (\(when))") }
    }

    private func commandLineProcesses() -> [String] {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-x", "-o", "comm="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/",
                              "/usr/bin/", "/bin/", "/Library/Developer/", "/private/"]
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { path in
                !path.isEmpty && !path.contains(".app/") && !path.contains(".framework/")
                    && !systemPrefixes.contains(where: path.hasPrefix) && path != "ps"
                    && !path.hasPrefix("-")
            }
            // Postgres and friends retitle their workers ("postgres: me db idle"),
            // so keep only the program name or every connection is its own line.
            .map { ($0 as NSString).lastPathComponent.components(separatedBy: ": ")[0] }
    }

    /// Sorted, with repeats folded into "name x3".
    private func grouped(_ names: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for n in names { counts[n, default: 0] += 1 }
        return counts.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { counts[$0]! > 1 ? "\($0) x\(counts[$0]!)" : $0 }
    }

    // MARK: - Writing

    private func name(of app: NSRunningApplication) -> String {
        // Some names carry invisible direction marks (WhatsApp starts with one).
        let raw = app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)"
        return raw.replacingOccurrences(of: "\u{200E}", with: "").replacingOccurrences(of: "\u{200F}", with: "")
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    private static func stamp(_ format: String, _ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f.string(from: date)
    }

    private func write(_ kind: String, _ message: String) {
        let line = "\(Self.stamp("HH:mm:ss", Date()))  \(kind.padding(toLength: 10, withPad: " ", startingAt: 0))\(message)\n"
        let url = Self.todayURL
        if !FileManager.default.fileExists(atPath: url.path) {
            let header = "Screen Cat activity log for \(Self.stamp("EEEE d MMMM yyyy", Date()))\n\n"
            try? Data(header.utf8).write(to: url)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    /// Deletes day files older than `keepDays`.
    private func prune(keepDays: Int) {
        guard keepDays > 0,
              let files = try? FileManager.default.contentsOfDirectory(
                at: Self.folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date(timeIntervalSinceNow: -Double(keepDays) * 86_400)
        for file in files where file.lastPathComponent.hasPrefix("activity-") {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }
}
