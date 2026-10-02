import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var window: OverlayWindow!
    private var view: OverlayView!
    /// The idle crawl's full-screen glitch, under the cat.
    private var takeover: TakeoverView!
    private var takeoverFrame = 0
    private var shownRecipe = -1
    private var statusItem: NSStatusItem!
    private let scene = Scene()

    private var behavior: Behavior?
    private var frameTimer: Timer?
    private var scheduleTimer: Timer?
    private var lastTick = CFAbsoluteTimeGetCurrent()
    private var lastDirty = CGRect.zero
    private var paused = false
    /// `--demo` runs the routines back to back so you can see all of them now.
    private let demo = CommandLine.arguments.contains("--demo")
    private var demoQueue: [Routine] = [.stroll, .ball, .hungry, .nap]
    private var loadedPaletteKey = ""
    private var watchCheck: CGFloat = 0.5
    private var currentScreen: NSScreen?
    /// A menu pick. It skips the blocked-app check for the whole routine, not
    /// just at the start, or the cat would leave again half a second later.
    private var forced = false
    /// Screen asleep, locked, or another user switched in. Nobody can see the
    /// cat then, so it stays in and the 60Hz timer does not run for nothing.
    private var away = false
    private var nextVisitAt: Date?

    // Petting: rest the pointer on the cat and it stops, sits and shows hearts.
    private var petDwell: CGFloat = 0
    private var petLeft: CGFloat = 0
    private var petTime: CGFloat = 0
    /// Must leave the cat before it can be petted again, so a parked pointer
    /// does not hold it still forever.
    private var petArmed = true
    private var clipBeforePet: Clip?
    private var playground: PlaygroundController?

    // The idle crawl: starts after `idleCrawlSeconds` without input, ends on
    // the first touch or key.
    private var idleTimer: Timer?
    private var idleCrawlStarted: CFAbsoluteTime = 0
    /// Ignore input this soon after a menu start, or the click that chose it
    /// would end it at once.
    private var idleCrawlGrace: CFAbsoluteTime = 0
    /// The app in front when it began, to go back to when you return.
    private var appBeforeCrawl: NSRunningApplication?
    private var switchedApps = false
    /// The shrink-away exit has already put you back in your app.
    private var exitHandled = false

    /// `--selftest <png>`: run the real on-screen window, force a walk, then
    /// photograph our own window to prove what actually reached the screen.
    private func runSelfTest(to path: String) {
        view.debugDraw = true
        start(.stroll, force: true)
        Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            let w = self.window!
            NSLog("Screen Cat: SELFTEST: cat at %.0f,%.0f visible=%@ sheet=%@ size=%.0f",
                  self.scene.cat.pos.x, self.scene.cat.pos.y,
                  self.scene.cat.visible ? "yes" : "no",
                  self.view.sheet != nil ? "loaded" : "NIL", self.scene.cat.size)
            let sharing: String
            switch w.sharingType {
            case .none: sharing = "none (excluded from screenshots/recording/sharing)"
            case .readOnly: sharing = "readOnly (WILL appear in captures)"
            default: sharing = "other"
            }
            NSLog("Screen Cat: SELFTEST: window visible=%@ alpha=%.2f level=%ld frame=%@",
                  w.isVisible ? "yes" : "no", w.alphaValue, w.level.rawValue,
                  NSStringFromRect(w.frame))
            NSLog("Screen Cat: SELFTEST: sharingType=%@  surface=%@",
                  sharing, String(describing: self.scene.surface))
            NSLog("Screen Cat: SELFTEST: draw() called %d times, cat painted %d times",
                  self.view.drawCount, self.view.drewCatCount)
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        Config.writeDefaultFileIfMissing()
        scene.config = Config.load()

        let union = screensUnion()
        window = makeOverlayWindow(frame: union)
        view = OverlayView(frame: CGRect(origin: .zero, size: union.size))
        view.scene = scene
        view.autoresizingMask = [.width, .height]
        view.onOKClicked = { [weak self] in
            (self?.behavior as? PlayBehavior)?.accepted = true
        }
        loadSprites()
        // The cat's view sits on top of the full-screen glitch. Both are
        // layer-backed, so the cat redrawing at 60 fps never repaints the
        // glitch, which only renders at 20.
        let container = OverlayContainer(frame: CGRect(origin: .zero, size: union.size))
        container.wantsLayer = true
        container.autoresizingMask = [.width, .height]
        takeover = TakeoverView(frame: .zero)
        container.addSubview(takeover)
        container.addSubview(view)
        window.contentView = container
        applyConfig()

        buildStatusItem()

        if scene.config.activityLog {
            ActivityLog.shared.catStatus = { [weak self] in self?.catReport() }
            ActivityLog.shared.start(keepDays: Int(scene.config.activityLogDays))
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            ws.addObserver(self, selector: #selector(goAway), name: name, object: nil)
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.addObserver(self, selector: #selector(comeBack), name: name, object: nil)
        }
        let dist = DistributedNotificationCenter.default()
        dist.addObserver(self, selector: #selector(goAway),
                         name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        dist.addObserver(self, selector: #selector(comeBack),
                         name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)

        idleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkIdleCrawl()
        }

        // `--idle-selftest`: run the idle crawl through the real window with
        // the window fully transparent, log what it does each second, and
        // quit. Nothing shows on screen and no app is switched.
        if CommandLine.arguments.contains("--idle-selftest") {
            idleTimer?.invalidate()
            // `--idle-selftest mrrobot` runs Mr. Robot instead. Either way, at
            // 11s it acts as if you touched the trackpad, to test the exit.
            let robot = CommandLine.arguments.contains("mrrobot")
            beginIdleCrawl(grace: .greatestFiniteMagnitude, routine: robot ? .mrRobot : .idleCrawl)
            window.alphaValue = 0
            (behavior as? IdleCrawlBehavior)?.requestNextApp = nil
            (behavior as? IdleCrawlBehavior)?.requestRandomApp = nil
            var seconds = 0
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { exit(1) }
                guard let idle = self.behavior as? IdleCrawlBehavior else {
                    print("exited: cat gone, glitch \(self.takeover.layer?.contents == nil ? "cleared" : "STILL SHOWING")")
                    exit(0)
                }
                seconds += 1
                if seconds == 11 { idle.beginExit() }
                print(String(format: "%2ds  stage %@  cat %.0fpt at %.0f,%.0f  glitch %.2f  style %@  layer %@  image %@",
                             seconds, idle.stageName, self.scene.cat.size, self.scene.cat.pos.x, self.scene.cat.pos.y,
                             idle.takeoverOpacity, glitchRecipes[idle.recipeIndex].name,
                             NSStringFromRect(self.takeover.frame),
                             self.takeover.layer?.contents == nil ? "none" : "yes"))
                if seconds >= 16 { print("did not exit"); exit(1) }
            }
            return
        }

        if let i = CommandLine.arguments.firstIndex(of: "--selftest"), i + 1 < CommandLine.arguments.count {
            runSelfTest(to: CommandLine.arguments[i + 1])
            return
        }
        schedule(after: demo ? 2 : scene.config.firstAppearanceDelay)
    }

    // MARK: - Config

    private func applyConfig() {
        let c = scene.config
        view.extras = c.extras
        view.drawShadows = c.shadow
        window.alphaValue = c.opacity
        window.level = windowLevel(named: c.windowLevel)
        // .none keeps the cat off screenshots, screen recordings and anything
        // being screen-shared, while you still see it on the glass.
        window.sharingType = c.hideFromCapture ? .none : .readOnly
    }

    /// The sheet is recoloured at load time, so it is only rebuilt when the
    /// colour settings actually change.
    private func loadSprites() {
        let c = scene.config
        let key = [c.furColor, c.furShadeColor, c.outlineColor,
                   c.innerColor, c.eyeColor, c.ballColor].joined(separator: "|")
        guard key != loadedPaletteKey else { return }
        let sheet = SpriteSheet(resources: resourcesDirectory(), palette: c.spritePalette)
        guard sheet.isLoaded else {
            NSLog("Screen Cat: could not load sprites from \(resourcesDirectory().path)")
            return
        }
        view.sheet = sheet
        loadedPaletteKey = key
    }

    @objc private func reloadConfig() {
        scene.config = Config.load()
        applyConfig()
        loadSprites()
        view.needsDisplay = true
    }

    @objc private func screensChanged() {
        let union = screensUnion()
        window.setFrame(union, display: false)
        view.frame = CGRect(origin: .zero, size: union.size)
        view.needsDisplay = true
        // The stage was laid out for the old screen, which may be gone or have
        // moved. Send the cat home and let the next visit lay it out again.
        if behavior != nil {
            stopBehavior()
            if !paused && !away { schedule(after: 3) }
        }
    }

    @objc private func goAway() {
        guard !away else { return }
        if behavior is IdleCrawlBehavior { endIdleCrawl(reason: "screen went off") }
        away = true
        stopBehavior()
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        nextVisitAt = nil
    }

    @objc private func comeBack() {
        guard away else { return }
        away = false
        if !paused { schedule(after: scene.config.firstAppearanceDelay) }
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐈"
        statusItem.button?.toolTip = "Screen Cat"

        let menu = NSMenu()
        menu.delegate = self
        let status = NSMenuItem(title: "Waiting", action: nil, keyEquivalent: "")
        status.isEnabled = false
        status.tag = 200
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Take a walk", action: #selector(runStroll), keyEquivalent: "")
        menu.addItem(withTitle: "Have a nap", action: #selector(runNap), keyEquivalent: "")
        menu.addItem(withTitle: "Chase a ball", action: #selector(runBall), keyEquivalent: "")
        menu.addItem(withTitle: "Beg for food", action: #selector(runHungry), keyEquivalent: "")
        menu.addItem(withTitle: "Ask to play", action: #selector(runPlay), keyEquivalent: "")
        menu.addItem(withTitle: "Break some apps (crawler)", action: #selector(runCrawl), keyEquivalent: "")
        menu.addItem(withTitle: "Crawl until I touch something", action: #selector(runIdleCrawl), keyEquivalent: "")
        menu.addItem(.separator())
        let modes = NSMenu()
        for (tag, title) in [(500, "Normal"), (501, "Crawler"), (502, "Mr. Robot (3 min hack, starts now)")] {
            let item = NSMenuItem(title: title, action: #selector(pickMode(_:)), keyEquivalent: "")
            item.tag = tag
            item.target = self
            modes.addItem(item)
        }
        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        modeItem.submenu = modes
        menu.addItem(modeItem)
        menu.addItem(withTitle: "Open playground", action: #selector(openPlayground), keyEquivalent: "")
        menu.addItem(.separator())
        let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.tag = 100
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        let capture = NSMenuItem(title: "Show in screenshots & recordings",
                                 action: #selector(toggleCapture), keyEquivalent: "")
        capture.tag = 300
        menu.addItem(capture)
        let login = NSMenuItem(title: "Open at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.tag = 400
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open today's activity log", action: #selector(openActivityLog), keyEquivalent: "")
        menu.addItem(withTitle: "Show all activity logs", action: #selector(showActivityLogs), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Edit settings…", action: #selector(editSettings), keyEquivalent: "")
        menu.addItem(withTitle: "Reload settings", action: #selector(reloadConfig), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Screen Cat", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    /// Refresh the top line each time the menu opens, so it is obvious why the
    /// cat is or is not showing up.
    func menuWillOpen(_ menu: NSMenu) {
        scene.config = Config.load()
        menu.item(withTag: 300)?.state = scene.config.hideFromCapture ? .off : .on
        menu.item(withTag: 400)?.state = LoginItem.isEnabled ? .on : .off
        if let modes = menu.items.first(where: { $0.title == "Mode" })?.submenu {
            modes.item(withTag: 500)?.state = scene.config.mode == "crawler" ? .off : .on
            modes.item(withTag: 501)?.state = scene.config.mode == "crawler" ? .on : .off
        }
        guard let item = menu.item(withTag: 200) else { return }
        if paused {
            item.title = "Paused"
        } else if away {
            item.title = "Away while the screen is off"
        } else if let why = Watching.reason(scene.config, screen: targetScreen()) {
            item.title = why.prefix(1).uppercased() + why.dropFirst()
        } else if behavior != nil {
            item.title = "Out and about"
        } else if let at = nextVisitAt {
            item.title = "Next visit in \(max(1, Int(at.timeIntervalSinceNow.rounded())))s"
        } else {
            item.title = "Waiting for the next visit"
        }
    }

    // Menu picks force the routine: if you ask for the cat, you get the cat.
    @objc private func runStroll() { start(.stroll, force: true) }
    @objc private func runNap()    { start(.nap, force: true) }
    @objc private func runBall()   { start(.ball, force: true) }
    @objc private func runHungry() { start(.hungry, force: true) }
    @objc private func runPlay()   { start(.play, force: true) }
    @objc private func runCrawl()  { start(.crawl, force: true) }
    @objc private func runIdleCrawl() { beginIdleCrawl(grace: 1.0) }

    // MARK: - Idle crawl

    /// Real hardware input only. Posted or synthetic events do not count, so
    /// nothing the cat does can make it look like you came back.
    private static func secondsSinceInput() -> CFTimeInterval {
        let anyInput = CGEventType(rawValue: ~0) ?? .null
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }

    private func checkIdleCrawl() {
        let c = scene.config
        guard c.idleCrawl, !paused, !away, !(behavior is IdleCrawlBehavior) else { return }
        guard Self.secondsSinceInput() >= TimeInterval(c.idleCrawlSeconds) else { return }
        // Two quiet minutes in front of a film is watching, not away.
        guard Watching.reason(c, screen: targetScreen()) == nil else { return }
        beginIdleCrawl(grace: 0)
    }

    private func beginIdleCrawl(grace: CFAbsoluteTime, routine: Routine = .idleCrawl) {
        appBeforeCrawl = NSWorkspace.shared.frontmostApplication
        switchedApps = false
        exitHandled = false
        idleCrawlStarted = CFAbsoluteTimeGetCurrent()
        idleCrawlGrace = grace
        ActivityLog.shared.cat("idle crawl started")
        start(routine, force: grace > 0)
    }

    /// True once there has been real input since the crawl began.
    private func touchedSinceIdleCrawl() -> Bool {
        let running = CFAbsoluteTimeGetCurrent() - idleCrawlStarted
        guard running > idleCrawlGrace else { return false }
        return Self.secondsSinceInput() + 0.05 < running
    }

    private func endIdleCrawl(reason: String) {
        ActivityLog.shared.cat("idle crawl ended: \(reason)")
        stopBehavior()
        returnToStartApp()
        if !paused && !away { scheduleNext() }
    }

    /// Put you back in the app you left, if the crawl swiped away from it.
    private func returnToStartApp() {
        if switchedApps, let app = appBeforeCrawl, !app.isTerminated {
            if let url = app.bundleURL {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: config)
            }
        }
        appBeforeCrawl = nil
        switchedApps = false
    }

    /// Mr. Robot's hop: a random app one to three places left or right of the
    /// one in front, so it jumps around rather than stepping through in order.
    private func switchToRandomApp() -> Bool {
        let apps = switchableApps()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard apps.count >= 2 else { return false }
        let i = apps.firstIndex { $0.processIdentifier == front } ?? 0
        let side = Bool.random() ? 1 : -1
        let places = Int.random(in: 1...min(3, apps.count - 1))
        let next = apps[((i + side * places) % apps.count + apps.count) % apps.count]
        guard next.processIdentifier != front, let url = next.bundleURL else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
        switchedApps = true
        ActivityLog.shared.cat("hopped to \(next.localizedName ?? "an app") (\(places) to the \(side > 0 ? "right" : "left"))")
        return true
    }

    /// Apps the crawl may bring forward: ordinary apps with a real window on
    /// some Space, not hidden, not blocked, not Screen Cat, in name order.
    private func switchableApps() -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        let blocked = Watching.blockedPids(scene.config.blockedApps)
        let withWindows = Watching.pidsWithWindows()
        return NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular && !app.isHidden && app.bundleURL != nil
                    && app.processIdentifier != me && !blocked.contains(app.processIdentifier)
                    && withWindows.contains(app.processIdentifier)
            }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    /// The three-finger swipe. Brings the next app forward, in name order in
    /// the cat's direction, and macOS slides to its Space if it has one.
    /// Skips blocked apps and apps with no window anywhere.
    private func switchToNextApp(_ direction: CGFloat) -> Bool {
        let apps = switchableApps()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let others = apps.filter { $0.processIdentifier != front }
        guard !others.isEmpty, let url = pickNext(apps, front: front, direction: direction)?.bundleURL else {
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
        switchedApps = true
        ActivityLog.shared.cat("crawled over to \(url.deletingPathExtension().lastPathComponent)")
        return true
    }

    private func pickNext(_ apps: [NSRunningApplication], front: pid_t?,
                          direction: CGFloat) -> NSRunningApplication? {
        guard !apps.isEmpty else { return nil }
        guard let i = apps.firstIndex(where: { $0.processIdentifier == front }) else {
            return direction > 0 ? apps.first : apps.last
        }
        let step = direction > 0 ? 1 : apps.count - 1
        let next = apps[(i + step) % apps.count]
        return next.processIdentifier == front ? nil : next
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        // Mr. Robot is a show, not a lasting mode: it runs once and the saved
        // mode stays what it was.
        if sender.tag == 502 {
            ActivityLog.shared.cat("Mr. Robot started from the menu")
            beginIdleCrawl(grace: 3.2, routine: .mrRobot)
            return
        }
        setMode(sender.tag == 501 ? "crawler" : "normal")
    }

    /// One mode for the desktop cat and the playground, saved to settings.
    private func setMode(_ mode: String) {
        scene.config.mode = mode
        Config.update("mode", to: mode)
        playground?.mode = mode
        ActivityLog.shared.cat("mode set to \(mode)")
    }

    @objc private func openPlayground() {
        if playground == nil {
            playground = PlaygroundController(config: Config.load()) { [weak self] mode in
                self?.setMode(mode)
            }
        }
        playground?.show()
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        paused.toggle()
        sender.title = paused ? "Resume" : "Pause"
        if paused {
            stopBehavior()
            scheduleTimer?.invalidate()
            scheduleTimer = nil
            nextVisitAt = nil
        } else if !away {
            schedule(after: 3)
        }
    }

    /// Ticked means the cat is visible to screen capture. Off, the default,
    /// keeps it out of screenshots, recordings and anything screen shared.
    @objc private func toggleCapture(_ sender: NSMenuItem) {
        scene.config.hideFromCapture.toggle()
        Config.update("hideFromCapture", to: scene.config.hideFromCapture)
        applyConfig()
        sender.state = scene.config.hideFromCapture ? .off : .on
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        sender.state = LoginItem.isEnabled ? .on : .off
    }

    @objc private func editSettings() {
        Config.writeDefaultFileIfMissing()
        NSWorkspace.shared.open(Config.fileURL)
    }

    @objc private func openActivityLog() {
        let url = ActivityLog.todayURL
        guard FileManager.default.fileExists(atPath: url.path) else { showActivityLogs(); return }
        NSWorkspace.shared.open(url)
    }

    @objc private func showActivityLogs() {
        try? FileManager.default.createDirectory(at: ActivityLog.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(ActivityLog.folder)
    }

    func applicationWillTerminate(_ note: Notification) { ActivityLog.shared.stop() }

    /// Puts the idle crawl's glitch over the whole of the cat's screen, menu
    /// bar and Dock included, and renders it every third frame.
    private func showTakeover(_ idle: IdleCrawlBehavior) {
        guard let screen = currentScreen else { return }
        let rect = screen.frame.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
        if takeover.frame != rect { takeover.frame = rect }
        if idle.recipeIndex != shownRecipe, idle.takeoverOpacity > 0 {
            shownRecipe = idle.recipeIndex
            ActivityLog.shared.cat("glitch style: \(glitchRecipes[idle.recipeIndex].name)")
        }
        takeoverFrame += 1
        guard takeoverFrame % 3 == 0 else { return }
        if idle.countdownLeft > 0 {
            takeover.show(countdownRecipe(Int(ceil(idle.countdownLeft))), time: idle.countdownLeft, seed: 7,
                          pulse: 0, opacity: 1)
            return
        }
        if idle.takeoverOpacity <= 0.01 {
            takeover.clear()
            return
        }
        takeover.show(glitchRecipes[idle.recipeIndex], time: idle.styleTime, seed: idle.styleSeed,
                      pulse: idle.pulse, opacity: idle.takeoverOpacity)
    }

    /// Windows on `screen` worth breaking, in surface-local coordinates: the
    /// ones you can mostly see, from apps that are not on the blocked list, up
    /// to four of them. Window frames need no permission; titles are not read.
    private func crawlTargets(on screen: NSScreen) -> [CGRect] {
        let me = ProcessInfo.processInfo.processIdentifier
        let pids = Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me }
            .map(\.processIdentifier))
            .subtracting(Watching.blockedPids(scene.config.blockedApps))
        let area = screen.visibleFrame
        // Front to back. A window whose middle is under one in front of it is
        // mostly hidden, so breaking it would paint over the front one.
        var inFront: [CGRect] = []
        var picked: [CGRect] = []
        for window in Watching.windows(of: pids) {
            let rect = window.rect.intersection(area)
            defer { inFront.append(window.rect) }
            guard !rect.isNull, rect.width >= 200, rect.height >= 120 else { continue }
            if inFront.contains(where: { $0.contains(CGPoint(x: rect.midX, y: rect.midY)) }) { continue }
            picked.append(rect)
        }
        let toLocal = scene.surface.transform(for: scene.screenRect).inverted()
        return picked.shuffled().prefix(4).map { $0.applying(toLocal) }
    }

    /// For the activity log on every app switch: is the cat out, and is its
    /// window really on the Space you are looking at? A "no" here names an app
    /// the cat failed to show over.
    private func catReport() -> String? {
        guard behavior != nil else { return nil }
        let space = window.isOnActiveSpace ? "yes" : "NO"
        return "out on the \(scene.surface); window on this Space: \(space), visible: \(window.isVisible ? "yes" : "NO"), level \(window.level.rawValue)"
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Scheduling

    private func schedule(after seconds: CGFloat) {
        scheduleTimer?.invalidate()
        let delay = TimeInterval(max(1, seconds))
        nextVisitAt = Date(timeIntervalSinceNow: delay)
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.nextVisitAt = nil
            self?.startRandom()
        }
    }

    private func scheduleNext() {
        if demo { schedule(after: 2); return }
        let c = scene.config
        schedule(after: CGFloat.random(in: c.minGapSeconds...c.maxGapSeconds))
    }

    private func startRandom() {
        guard !away, !paused else { return }
        // Never wander out over a film. Check again in a minute instead.
        scene.config = Config.load()
        if let why = Watching.reason(scene.config, screen: targetScreen()) {
            ActivityLog.shared.cat("stayed in: \(why)")
            schedule(after: 60)
            return
        }
        if scene.config.mode == "crawler", Double.random(in: 0..<1) < scene.config.crawlChance {
            start(.crawl)
            return
        }
        if demo {
            if demoQueue.isEmpty { demoQueue = [.stroll, .ball, .hungry, .nap] }
            start(demoQueue.removeFirst())
            return
        }
        let c = scene.config
        let table: [(Routine, Double)] = [
            (.stroll, max(0, c.weightStroll)),
            (.nap, max(0, c.weightNap)),
            (.ball, max(0, c.weightBall)),
            (.hungry, max(0, c.weightHungry)),
            (.play, max(0, c.weightPlay)),
        ]
        let total = table.reduce(0) { $0 + $1.1 }
        guard total > 0 else { scheduleNext(); return }
        var roll = Double.random(in: 0..<total)
        for (routine, weight) in table {
            roll -= weight
            if roll < 0 { start(routine); return }
        }
        start(.stroll)
    }

    private func start(_ requested: Routine, force: Bool = false) {
        var routine = requested
        // One cat at a time: whatever is out now leaves before the next arrives.
        stopBehavior()
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        nextVisitAt = nil

        if !force, Watching.shouldStayAway(Config.load(), screen: targetScreen()) {
            schedule(after: 60); return
        }

        scene.config = Config.load()
        applyConfig()
        loadSprites()

        let screen = targetScreen()
        currentScreen = screen
        // visibleFrame, not frame: the overlay sits below the Dock and the menu
        // bar, so a cat that walked there would be half-hidden.
        scene.cat.size = max(24, screen.visibleFrame.height / scene.config.sizeDivisor)
        // Begging faces the viewer, so it only makes sense the right way up.
        // Begging and the play invite both face you and need a clickable
        // bubble the right way up, so they stay on the bottom edge.
        let mayUseWall = routine != .hungry && routine != .play && routine != .crawl
            && routine != .idleCrawl && routine != .mrRobot
            && Double.random(in: 0..<1) < scene.config.wallChance
        let surface: Surface = mayUseWall ? (Bool.random() ? .left : .right) : .bottom
        scene.setStage(surface: surface, screen: screen.visibleFrame, catSize: scene.cat.size)
        if routine == .idleCrawl || routine == .mrRobot { scene.crawlTargets = crawlTargets(on: screen) }
        if routine == .crawl {
            scene.crawlTargets = crawlTargets(on: screen)
            // Nothing to break on this screen: just take a walk.
            if scene.crawlTargets.isEmpty { routine = .stroll }
        }
        scene.cat.clipTime = 0
        scene.cat.stride = 0
        scene.cat.depth = 1
        scene.ball.visible = false
        view.bowlAt = nil
        view.bubbleTip = nil

        behavior = makeBehavior(routine, scene: scene)
        forced = force
        scene.cat.wearing = pickOutfit(scene.config)
        // A hacker wears shades.
        if [.crawl, .idleCrawl, .mrRobot].contains(routine) { scene.cat.wearing.insert(.glasses) }
        if let idle = behavior as? IdleCrawlBehavior {
            idle.requestTargets = { [weak self] in
                guard let self else { return [] }
                return self.crawlTargets(on: self.currentScreen ?? targetScreen())
            }
            idle.requestNextApp = { [weak self] direction in self?.switchToNextApp(direction) ?? false }
            idle.requestRandomApp = { [weak self] in self?.switchToRandomApp() ?? false }
        }
        scene.cat.visible = true
        let outfit = scene.cat.wearing.map { "\($0)" }.sorted().joined(separator: " + ")
        ActivityLog.shared.cat("came out: \(routine.rawValue) on the \(scene.surface) of \(screen.localizedName)"
                               + (outfit.isEmpty ? "" : ", wearing \(outfit)") + (force ? " (menu pick)" : ""))
        NSLog("Screen Cat: %@ on the %@ at %.0f,%.0f size %.0fpt, stage %@ band %.0f",
              routine.rawValue, String(describing: scene.surface),
              scene.cat.pos.x, scene.cat.pos.y, scene.cat.size,
              NSStringFromRect(scene.stage), scene.roamBand)

        window.orderFrontRegardless()
        lastDirty = .zero
        lastTick = CFAbsoluteTimeGetCurrent()
        frameTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func stopBehavior() {
        if behavior != nil {
            NSLog("Screen Cat: routine ended")
            ActivityLog.shared.cat("went in")
        }
        frameTimer?.invalidate()
        frameTimer = nil
        behavior = nil
        scene.cat.visible = false
        scene.ball.visible = false
        view?.bowlAt = nil
        view?.bubbleTip = nil
        view?.okHovered = false
        view?.dwellProgress = 0
        view?.petTime = nil
        view?.breaches = []
        view?.zap = nil
        view?.aura = nil
        takeover?.clear()
        shownRecipe = -1
        petDwell = 0
        petLeft = 0
        petArmed = true
        clipBeforePet = nil
        forced = false
        window?.ignoresMouseEvents = true
        window?.orderOut(nil)
    }

    // MARK: - Frame loop

    private func tick() {
        guard let behavior else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let dt = CGFloat(min(0.05, max(0.001, now - lastTick)))
        lastTick = now

        // A touch or key: the glitch goes at once and the cat shrinks away.
        // Mr. Robot ending on time takes the same exit.
        if let idle = behavior as? IdleCrawlBehavior {
            if !idle.isExiting, touchedSinceIdleCrawl() {
                ActivityLog.shared.cat("idle crawl ended: you are back")
                idle.beginExit()
            }
            if idle.isExiting, !exitHandled {
                exitHandled = true
                takeover.clear()
                returnToStartApp()
            }
        }

        // If a video starts mid-routine, get out of the way at once.
        watchCheck -= dt
        if watchCheck <= 0 && !forced {
            watchCheck = 0.5
            if let why = Watching.reason(scene.config, screen: currentScreen ?? targetScreen()) {
                ActivityLog.shared.cat("left early: \(why)")
                stopBehavior()
                if !paused { schedule(after: 60) }
                return
            }
        }

        scene.cat.advance(dt)
        let finished = updatePetting(dt) ? false : behavior.update(dt, scene)
        view.bowlAt = (behavior as? HungryBehavior)?.bowlAt
        view.bubbleTip = (behavior as? PlayBehavior)?.bubbleTip

        // Pointer tracking for the play invite. Resting on the cat or its
        // bubble accepts after a dwell; clicking OK accepts at once. Only the
        // button ever intercepts clicks, so nothing else is swallowed.
        if let play = behavior as? PlayBehavior, let area = view.acceptArea {
            let mouse = NSEvent.mouseLocation
            let inView = CGPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
            play.pointerResting = area.contains(inView)
            view.dwellProgress = play.dwellProgress
            let overButton = view.okButton?.contains(inView) ?? false
            if overButton != view.okHovered { view.okHovered = overButton }
            window.ignoresMouseEvents = !overButton
        } else if view.okHovered || view.dwellProgress > 0 || !window.ignoresMouseEvents {
            view.okHovered = false
            view.dwellProgress = 0
            window.ignoresMouseEvents = true
        }

        view.petTime = petLeft > 0 ? petTime : nil
        let crawl = behavior as? BreachSource
        view.breaches = crawl?.breaches ?? []
        view.zap = crawl?.zap
        view.aura = crawl?.aura
        var dirty = scene.cat.bounds
        for breach in view.breaches { dirty = dirty.union(breach.rect.insetBy(dx: -6, dy: -6)) }
        if let zap = view.zap { dirty = dirty.union(zap.bounds) }
        if let aura = view.aura { dirty = dirty.union(aura.bounds) }
        if let idle = behavior as? IdleCrawlBehavior { showTakeover(idle) }
        if scene.ball.visible { dirty = dirty.union(scene.ball.bounds) }
        if let tip = view.bubbleTip {
            // The bubble is much taller than the cat, so it needs its own patch.
            dirty = dirty.union(CGRect(x: tip.x - scene.cat.size * 4, y: tip.y - 8,
                                       width: scene.cat.size * 8, height: scene.cat.size * 5))
        }
        if let bowl = view.bowlAt {
            dirty = dirty.union(CGRect(x: bowl.x - scene.cat.drawnSize, y: bowl.y - 8,
                                       width: scene.cat.drawnSize * 2, height: scene.cat.drawnSize))
        }
        // Local -> screen -> view, then repaint both the old and the new spot.
        let offset = window.frame.origin
        let onScreen = dirty.applying(scene.surface.transform(for: scene.screenRect))
        let viewRect = onScreen.offsetBy(dx: -offset.x, dy: -offset.y).insetBy(dx: -8, dy: -8)
        view.setNeedsDisplay(viewRect.union(lastDirty))
        lastDirty = viewRect

        if finished {
            stopBehavior()
            if !paused { scheduleNext() }
        }
    }
}

extension AppDelegate {
    /// Rest the pointer on the cat for `petSeconds` and it stops what it is
    /// doing, sits, and shows two hearts. A sleeping cat stays asleep and just
    /// gets the hearts. Returns true while the pet is on, and the routine is
    /// frozen for that time, ball included. Hover only: no click is taken.
    fileprivate func updatePetting(_ dt: CGFloat) -> Bool {
        let cat = scene.cat
        if petLeft > 0 {
            petLeft -= dt
            petTime += dt
            if petLeft <= 0, let before = clipBeforePet {
                cat.setClip(before)
                clipBeforePet = nil
            }
            return petLeft > 0
        }
        // The play invite has its own dwell on the same pointer.
        guard scene.config.petSeconds > 0, cat.visible, !(behavior is PlayBehavior) else {
            petDwell = 0
            return false
        }
        let size = cat.drawnSize
        let body = CGRect(x: cat.pos.x - size * 0.6, y: cat.pos.y, width: size * 1.2, height: size)
        // Both are global screen coordinates, so no window offset is needed.
        let onScreen = body.applying(scene.surface.transform(for: scene.screenRect))
        let over = onScreen.contains(NSEvent.mouseLocation)
        if !over {
            petArmed = true
            petDwell = 0
            return false
        }
        guard petArmed else { return false }
        petDwell += dt
        guard petDwell >= scene.config.petSeconds else { return false }
        petDwell = 0
        petArmed = false
        petLeft = 2.6
        petTime = 0
        if cat.clip != .sleep && cat.clip != .ballPlay && cat.clip != .lieDown {
            clipBeforePet = cat.clip
            cat.setClip(.sitIdle)
        }
        return true
    }
}

/// Rolls what the cat wears for one visit, so the glasses stay a surprise.
func pickOutfit(_ c: Config) -> Set<Accessory> {
    var outfit: Set<Accessory> = []
    if Double.random(in: 0..<1) < c.chainChance { outfit.insert(.chain) }
    if Double.random(in: 0..<1) < c.glassesChance { outfit.insert(.glasses) }
    return outfit
}

/// Holds the glitch view and the cat's view. Only the cat's OK button ever
/// takes a click; everything else falls through to the apps underneath.
final class OverlayContainer: NSView {
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's space; subviews want it in ours.
        let local = convert(point, from: superview)
        for sub in subviews.reversed() {
            if let hit = sub.hitTest(local) { return hit }
        }
        return nil
    }
}

// MARK: - Entry point

// `--preview <path.png>` renders a contact sheet of every pose. Handy for
// checking the artwork without waiting for the cat to wander past.
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--preview" {
    renderPreviewSheet(to: CommandLine.arguments[2])
    exit(0)
}

if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--takeover" {
    renderTakeoverSheet(to: CommandLine.arguments[2])
    exit(0)
}
if CommandLine.arguments.contains("--takeover-bench") {
    benchTakeover()
    exit(0)
}
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--glitches" {
    renderGlitchSheet(to: CommandLine.arguments[2])
    exit(0)
}

// `--watching` reports whether the cat would currently stay out of the way.
if CommandLine.arguments.contains("--watching") {
    let cfg = Config.load()
    print("hideWhileWatching: \(cfg.hideWhileWatching)")
    let screen = targetScreen()
    let front = NSWorkspace.shared.frontmostApplication
    let blocked = Watching.blockedPids(cfg.blockedApps)
    let names = blocked.map { NSRunningApplication(processIdentifier: $0)?.localizedName ?? "pid \($0)" }
    print("blocked apps open:  \(names.isEmpty ? "none" : names.joined(separator: ", "))")
    print("frontmost app:      \(front?.bundleIdentifier ?? "?")")
    print("  on blocked list:  \(Watching.frontmostIsBlocked(cfg.blockedApps))")
    let holders = Watching.pidsHoldingDisplayAssertions()
        .map { NSRunningApplication(processIdentifier: $0)?.localizedName ?? "pid \($0)" }
    print("(fyi) holding display awake: \(holders.isEmpty ? "nobody" : holders.joined(separator: ", ")), no longer used to decide")
    if let pid = Watching.fullscreenHolder(pids: blocked, on: screen) {
        print("fullscreen blocked: \(NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)")")
    } else {
        print("fullscreen blocked: none")
    }
    // Self-check: the frontmost app is on screen by definition, so window
    // detection is working if and only if this finds a window for it.
    if let front {
        let n = Watching.windows(of: [front.processIdentifier]).count
        print("window detection:   \(n > 0 ? "working" : "FOUND NO WINDOW for frontmost app")")
    }
    print("=> stay away:       \(Watching.shouldStayAway(cfg, screen: screen))")
    print("   reason:          \(Watching.reason(cfg, screen: screen) ?? "none, cat is free to roam")")
    exit(0)
}

// `--checkpid <pid>` reports whether that one process has a window on screen.
if let i = CommandLine.arguments.firstIndex(of: "--checkpid"),
   i + 1 < CommandLine.arguments.count, let pid = pid_t(CommandLine.arguments[i + 1]) {
    let screen = targetScreen()
    let wins = Watching.windows(of: [pid], allLayers: true)
    print("pid \(pid): \(wins.count) on-screen window(s)")
    for w in wins {
        print("   layer \(w.layer): \(Int(w.rect.width))x\(Int(w.rect.height)) at \(Int(w.rect.minX)),\(Int(w.rect.minY))")
    }
    print("   fullscreen here: \(Watching.fullscreenHolder(pids: [pid], on: screen) != nil)")
    exit(0)
}

// `--simulate <routine> <path.png>` plays a routine offscreen through the real
// window and view, then writes a trail of where the cat went.
if CommandLine.arguments.count >= 4, CommandLine.arguments[1] == "--simulate",
   let routine = Routine(rawValue: CommandLine.arguments[2]) {
    NSApplication.shared.setActivationPolicy(.prohibited)
    runSimulation(routine: routine, to: CommandLine.arguments[3])
    exit(0)
}

// `--playground <path.png> [seconds]` runs the playground's crawl offscreen
// for that long and writes what the window would show.
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--playground" {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let view = PlaygroundView(frame: CGRect(x: 0, y: 0, width: 1000, height: 592), config: Config.load())
    view.mode = "crawler"
    view.start(.crawl)
    let seconds = CommandLine.arguments.count >= 4 ? Double(CommandLine.arguments[3]) ?? 6 : 6
    for _ in 0..<Int(seconds * 60) { view.step(1.0 / 60.0) }
    if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        print("wrote \(CommandLine.arguments[2])")
    }
    exit(0)
}

// Only one Screen Cat may run at a time, or you get two cats.
guard SingleInstance.claim() else {
    FileHandle.standardError.write(Data("Screen Cat is already running.\n".utf8))
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
