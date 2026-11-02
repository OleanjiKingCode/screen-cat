import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var window: OverlayWindow!
    private var view: OverlayView!
    /// The idle crawl's full-screen glitch, under the cat.
    private var takeover: TakeoverView!
    private var takeoverFrame = 0
    private let zeroDaySound = ZeroDaySound()
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

    // LLM mode: what you copy or screenshot goes to Claude, and the cat sits
    // under the answer.
    private let asker = Asker()
    private let questions = QuestionWatch()
    private var answerPanel: AnswerPanel?
    /// The newest answer, so copying part of it is not asked about again.
    private var lastAnswer = ""
    /// What has been asked and answered on the card that is up, so a
    /// follow-up typed on it is answered in context.
    private var conversation: [Turn] = []
    /// After the cat in the menu bar: 💭 while an answer with no card is on
    /// its way, then ✅ or ⚠️ for a few seconds.
    private var badge = ""
    private var badgeTimer: Timer?
    /// The pet's silhouette, shown in the menu bar.
    private var menuIcon: NSImage?

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
        // No settings file yet means this is the very first launch.
        let firstRun = !FileManager.default.fileExists(atPath: Config.fileURL.path)
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
            // `--idle-selftest zeroday` runs Zero Day instead. Either way, at
            // 11s it acts as if you touched the trackpad, to test the exit.
            let zeroDay = CommandLine.arguments.contains("zeroday")
            beginIdleCrawl(grace: .greatestFiniteMagnitude, routine: zeroDay ? .zeroDay : .idleCrawl)
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
        applySteppedOut()
        questions.onQuestion = { [weak self] question in self?.ask(question) }
        questions.isOwnText = { [weak self] text in
            guard let answer = self?.lastAnswer, !answer.isEmpty else { return false }
            return answer.contains(text)
        }
        applyLLMMode()
        if firstRun { showWelcome() }
        schedule(after: demo ? 2 : scene.config.firstAppearanceDelay)
    }

    /// The app has no window and no Dock icon, so on the first launch say
    /// where it went.
    private func showWelcome() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Screen Cat is running"
        alert.informativeText = """
        Your pet lives in the menu bar: look for the little cat at the top right of the screen. \
        Click it to pick a cat or a dog, change modes, turn on LLM mode, or quit.

        The pet comes out on its own every few seconds. Nothing it does touches your apps.
        """
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Also open at login")
        if alert.runModal() == .alertSecondButtonReturn { LoginItem.setEnabled(true) }
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
        // The answer card follows the cat: in captures only if the cat is.
        answerPanel?.sharingType = window.sharingType
        answerPanel?.level = window.level
    }

    /// The sheet is recoloured at load time, so it is only rebuilt when the
    /// colour settings actually change.
    private func loadSprites() {
        let c = scene.config
        let key = [c.pet, c.furColor, c.furShadeColor, c.outlineColor,
                   c.innerColor, c.eyeColor, c.ballColor].joined(separator: "|")
        guard key != loadedPaletteKey else { return }
        let sheet = SpriteSheet(resources: resourcesDirectory(), config: c)
        guard sheet.isLoaded else {
            NSLog("Screen Cat: could not load sprites from \(resourcesDirectory().path)")
            return
        }
        view.sheet = sheet
        scene.cat.isDog = c.pet == "dog"
        loadedPaletteKey = key
        menuIcon = sheet.menuBarIcon()
        refreshStatusTitle()
    }

    @objc private func reloadConfig() {
        scene.config = Config.load()
        applyConfig()
        applySteppedOut()
        applyLLMMode()
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
        // An answer stays up until you close it, so it is still there when
        // the screen comes back. Anything else goes home.
        if !(behavior is AskBehavior) { stopBehavior() }
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        nextVisitAt = nil
    }

    @objc private func comeBack() {
        guard away else { return }
        away = false
        if !paused && behavior == nil { schedule(after: scene.config.firstAppearanceDelay) }
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.toolTip = "Screen Cat"
        menuIcon = view.sheet?.menuBarIcon()
        refreshStatusTitle()

        func add(_ menu: NSMenu, _ title: String, _ action: Selector?, tag: Int = 0, key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.tag = tag
            menu.addItem(item)
        }
        func submenu(_ menu: NSMenu, _ title: String, tag: Int) -> NSMenu {
            let sub = NSMenu()
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = tag
            item.submenu = sub
            menu.addItem(item)
            return sub
        }

        let menu = NSMenu()
        menu.delegate = self
        add(menu, "Waiting", nil, tag: 200)
        menu.addItem(.separator())
        add(menu, "Pause", #selector(togglePause), tag: 100)
        menu.addItem(.separator())

        let pet = submenu(menu, "Pet", tag: 810)
        add(pet, "Cat", #selector(pickPet(_:)), tag: 800)
        add(pet, "Dog", #selector(pickPet(_:)), tag: 801)
        let mode = submenu(menu, "Mode", tag: 510)
        add(mode, "Normal", #selector(pickMode(_:)), tag: 500)
        add(mode, "Crawler (breaks windows, just paint)", #selector(pickMode(_:)), tag: 501)
        let now = submenu(menu, "Play now", tag: 520)
        add(now, "Take a walk", #selector(runStroll))
        add(now, "Have a nap", #selector(runNap))
        add(now, "Chase a ball", #selector(runBall))
        add(now, "Beg for food", #selector(runHungry))
        add(now, "Ask to play", #selector(runPlay))
        now.addItem(.separator())
        add(now, "Break some apps", #selector(runCrawl))
        add(now, "Crawl until I touch something", #selector(runIdleCrawl))
        add(now, "Zero Day (3 min hack)", #selector(pickMode(_:)), tag: 502)
        menu.addItem(.separator())

        let llm = submenu(menu, "LLM mode", tag: 710)
        add(llm, Self.llmModeTitle(false), #selector(toggleLLMMode), tag: 700)
        add(llm, "Ask about what I copied now", #selector(askAboutClipboard))
        llm.addItem(.separator())
        add(llm, "Show answer box", #selector(toggleShowAnswers), tag: 702)
        add(llm, "Copy answers to clipboard", #selector(toggleCopyAnswers), tag: 701)
        llm.addItem(.separator())
        add(llm, "Set API key…", #selector(setAPIKey))
        add(llm, "Answers come from", nil, tag: 703)
        menu.addItem(.separator())

        add(menu, "Stepped out (Mac never sleeps)", #selector(toggleSteppedOut), tag: 600)
        add(menu, "Show in screenshots & recordings", #selector(toggleCapture), tag: 300)
        add(menu, "Open at login", #selector(toggleLogin), tag: 400)
        menu.addItem(.separator())

        add(menu, "Open playground", #selector(openPlayground))
        let logs = submenu(menu, "Activity log", tag: 0)
        add(logs, "Open today's log", #selector(openActivityLog))
        add(logs, "Show all logs", #selector(showActivityLogs))
        let settings = submenu(menu, "Settings", tag: 0)
        add(settings, "Edit settings file…", #selector(editSettings))
        add(settings, "Reload settings", #selector(reloadConfig))
        menu.addItem(.separator())
        add(menu, "Quit Screen Cat", #selector(quit), key: "q")

        func target(_ menu: NSMenu) {
            for item in menu.items {
                if item.action != nil { item.target = self }
                if let sub = item.submenu { target(sub) }
            }
        }
        target(menu)
        statusItem.menu = menu
    }

    /// Finds an item by tag anywhere in the menu, submenus included.
    private func menuItem(_ tag: Int, in menu: NSMenu? = nil) -> NSMenuItem? {
        for item in (menu ?? statusItem.menu)?.items ?? [] {
            if item.tag == tag { return item }
            if let sub = item.submenu, let found = menuItem(tag, in: sub) { return found }
        }
        return nil
    }

    /// Refresh the ticks and the top line each time the menu opens, so it is
    /// obvious why the pet is or is not showing up.
    func menuWillOpen(_ menu: NSMenu) {
        let c = Config.load()
        scene.config = c
        func tick(_ tag: Int, _ on: Bool) { menuItem(tag)?.state = on ? .on : .off }
        tick(300, !c.hideFromCapture)
        tick(400, LoginItem.isEnabled)
        tick(600, StayAwake.isOn)
        tick(701, c.llmCopyAnswer)
        tick(702, c.llmShowAnswer)
        tick(500, c.mode != "crawler")
        tick(501, c.mode == "crawler")
        tick(800, c.pet == "cat")
        tick(801, c.pet == "dog")
        // The submenu titles carry the current choice, so the menu reads at
        // a glance without opening each one.
        menuItem(810)?.title = "Pet: \(c.pet == "dog" ? "Dog" : "Cat")"
        menuItem(510)?.title = "Mode: \(c.mode == "crawler" ? "Crawler" : "Normal")"
        menuItem(710)?.title = "LLM mode: \(c.llmMode ? "On" : "Off")"
        menuItem(700)?.title = Self.llmModeTitle(c.llmMode)
        menuItem(703)?.title = APIKey.isSet ? "Answers come from your API key" : "Answers come from your Claude Code login"
        menuItem(703)?.isEnabled = false
        guard let item = menuItem(200) else { return }
        item.isEnabled = false
        if paused {
            item.title = "Paused"
        } else if away {
            item.title = "Away while the screen is off"
        } else if let why = Watching.reason(c, screen: targetScreen()) {
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

    /// Zero Day's hop: a random app one to three places left or right of the
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
        zeroDaySound.hop()
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
        // Zero Day is a show, not a lasting mode: it runs once and the saved
        // mode stays what it was.
        if sender.tag == 502 {
            ActivityLog.shared.cat("Zero Day started from the menu")
            // No countdown: it starts at once, and input in the first 1.5 s
            // (letting go of the trackpad after the click) does not count.
            beginIdleCrawl(grace: 1.5, routine: .zeroDay)
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

    /// Cat or dog, saved, and swapped in at once, even mid-walk.
    @objc private func pickPet(_ sender: NSMenuItem) {
        let pet = sender.tag == 801 ? "dog" : "cat"
        scene.config.pet = pet
        Config.update("pet", to: pet)
        loadSprites()
        view.needsDisplay = true
        ActivityLog.shared.cat("pet set to \(pet)")
    }

    /// Paste your own Anthropic API key. It goes in the keychain. With it,
    /// answers come from the Claude API; without it, from Claude Code.
    @objc private func setAPIKey() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Anthropic API key"
        alert.informativeText = """
        With a key, LLM mode calls the Claude API directly, and you pay Anthropic for what you use. \
        Without one, it uses the claude command (Claude Code) and its login. \
        The key is kept in your Mac's keychain, not in the settings file. Get one at console.anthropic.com.
        """
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.placeholderString = APIKey.isSet ? "A key is saved. Paste a new one to replace it." : "sk-ant-..."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if APIKey.isSet { alert.addButton(withTitle: "Remove key") }
        alert.window.initialFirstResponder = field
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            if APIKey.save(key) {
                ActivityLog.shared.cat("llm: api key saved")
            } else {
                NSSound.beep()
            }
        case .alertThirdButtonReturn:
            APIKey.delete()
            ActivityLog.shared.cat("llm: api key removed")
        default:
            break
        }
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

    /// Ticked, the Mac never sleeps and the screen stays on. Saved to
    /// settings, so it is still on after a restart.
    @objc private func toggleSteppedOut(_ sender: NSMenuItem) {
        scene.config.steppedOut.toggle()
        Config.update("steppedOut", to: scene.config.steppedOut)
        applySteppedOut()
        sender.state = StayAwake.isOn ? .on : .off
    }

    /// The cup next to the cat in the menu bar says the Mac is being kept awake.
    private func applySteppedOut() {
        let wasOn = StayAwake.isOn
        StayAwake.set(scene.config.steppedOut)
        refreshStatusTitle()
        guard wasOn != StayAwake.isOn else { return }
        ActivityLog.shared.cat(StayAwake.isOn ? "stepped out: Mac stays awake" : "stepped out off: Mac may sleep")
    }

    // MARK: - LLM mode

    /// Says what clicking it will do, so turning the mode off is obvious.
    private static func llmModeTitle(_ on: Bool) -> String {
        on ? "Turn LLM mode off" : "Turn LLM mode on (answer what I copy or screenshot)"
    }

    @objc private func toggleLLMMode(_ sender: NSMenuItem) {
        scene.config.llmMode.toggle()
        Config.update("llmMode", to: scene.config.llmMode)
        applyLLMMode()
        sender.title = Self.llmModeTitle(scene.config.llmMode)
    }

    /// Ticked, each answer goes on the clipboard as it arrives, ready to paste.
    @objc private func toggleCopyAnswers(_ sender: NSMenuItem) {
        scene.config.llmCopyAnswer.toggle()
        Config.update("llmCopyAnswer", to: scene.config.llmCopyAnswer)
        sender.state = scene.config.llmCopyAnswer ? .on : .off
    }

    /// Unticked, there is no cat and no card: each answer goes straight to
    /// the clipboard. Unticking it while a card is up closes the card.
    @objc private func toggleShowAnswers(_ sender: NSMenuItem) {
        scene.config.llmShowAnswer.toggle()
        Config.update("llmShowAnswer", to: scene.config.llmShowAnswer)
        sender.state = scene.config.llmShowAnswer ? .on : .off
        if !scene.config.llmShowAnswer, behavior is AskBehavior {
            answerPanel?.dismiss()
            closeAnswer()
        }
    }

    /// Listens only while the mode is on. Turning it on never answers what
    /// was already on the clipboard.
    private func applyLLMMode() {
        let c = scene.config
        guard c.llmMode else {
            if questions.isRunning { ActivityLog.shared.cat("llm mode off") }
            questions.stop()
            return
        }
        if !questions.isRunning { ActivityLog.shared.cat("llm mode on") }
        questions.start(clipboard: c.llmFromClipboard, screenshots: c.llmFromScreenshots)
    }

    /// A one-off, with or without LLM mode: ask about the clipboard now.
    @objc private func askAboutClipboard() {
        guard let question = QuestionWatch.clipboardQuestion() else {
            NSSound.beep()
            return
        }
        ask(question, fromMenu: true)
    }

    /// The cat walks on and sits, the card goes up above where it will sit,
    /// and the answer fills the card when Claude replies. A new question while
    /// the cat is already sitting reuses the same cat and card, and starts a
    /// new conversation; a follow-up typed on the card carries it on.
    private func ask(_ question: Question, fromMenu: Bool = false) {
        guard !away, fromMenu || !paused else { return }
        if !question.isFollowUp { conversation = [] }
        let history = conversation
        scene.config = Config.load()
        guard scene.config.llmShowAnswer else { askQuietly(question); return }
        // A quiet question still on its way is replaced by this one.
        if !badge.isEmpty { setBadge("") }
        // A cat already walking off cannot sit under a new card: send a new one.
        if (behavior as? AskBehavior)?.isLeaving ?? true { start(.ask, force: true) }
        guard let sitting = behavior as? AskBehavior else { return }
        let panel = answerPanel ?? makeAnswerPanel()
        let head = CGPoint(x: sitting.spot.x, y: sitting.spot.y + scene.cat.size * 1.05)
            .applying(scene.surface.transform(for: scene.screenRect))
        panel.showThinking(question, above: head, within: scene.screenRect)
        ActivityLog.shared.cat("llm: asked about \(question.summary)")
        let asked = Date()
        let c = scene.config
        asker.ask(question, after: history, config: c) { [weak self] answer in
            guard let self else { return }
            let took = String(format: "%.1fs", Date().timeIntervalSince(asked))
            switch answer {
            case .text(let text):
                ActivityLog.shared.cat("llm: answered in \(took)")
                self.lastAnswer = text
                self.conversation = history + [Turn(question: question, answer: text)]
                panel.showAnswer(text)
                // Through the card's own copy, so the watcher knows it is ours.
                if c.llmCopyAnswer { panel.copyAnswer() }
            case .failed(let why):
                ActivityLog.shared.cat("llm: no answer after \(took): \(why)")
                panel.showError(why)
            }
        }
    }

    /// No cat and no card: the answer goes straight to the clipboard, and
    /// the menu bar icon shows it is coming, then that it is ready.
    private func askQuietly(_ question: Question) {
        ActivityLog.shared.cat("llm: asked about \(question.summary), no card")
        setBadge("💭")
        let asked = Date()
        asker.ask(question, config: scene.config) { [weak self] answer in
            guard let self else { return }
            let took = String(format: "%.1fs", Date().timeIntervalSince(asked))
            switch answer {
            case .text(let text):
                ActivityLog.shared.cat("llm: answered in \(took), copied")
                self.lastAnswer = text
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self.questions.ownChange = NSPasteboard.general.changeCount
                self.statusItem.button?.toolTip = "Screen Cat: answer copied"
                self.setBadge("✅", for: 4)
            case .failed(let why):
                ActivityLog.shared.cat("llm: no answer after \(took): \(why)")
                self.statusItem.button?.toolTip = "Screen Cat: \(why)"
                self.setBadge("⚠️", for: 6)
            }
        }
    }

    private func setBadge(_ mark: String, for seconds: TimeInterval? = nil) {
        badgeTimer?.invalidate()
        badge = mark
        refreshStatusTitle()
        guard let seconds else { return }
        badgeTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.badge = ""
            self?.statusItem.button?.toolTip = "Screen Cat"
            self?.refreshStatusTitle()
        }
    }

    /// The pet, a cup while the Mac is kept awake, then the answer badge.
    /// Falls back to an emoji if the sprites did not load.
    private func refreshStatusTitle() {
        guard let button = statusItem?.button else { return }
        button.image = menuIcon
        let extras = (StayAwake.isOn ? "☕" : "") + badge
        button.title = menuIcon == nil ? "🐈" + extras : extras
    }

    /// Sends the sitting cat off and drops any answer still coming.
    private func closeAnswer() {
        asker.cancel()
        conversation = []
        (behavior as? AskBehavior)?.release()
    }

    private func makeAnswerPanel() -> AnswerPanel {
        let panel = AnswerPanel(palette: scene.config.extras)
        panel.sharingType = window.sharingType
        panel.level = window.level
        panel.onClose = { [weak self] in self?.closeAnswer() }
        panel.onCopy = { [weak self] in self?.questions.ownChange = NSPasteboard.general.changeCount }
        // Asked on purpose, so it goes even while paused, like the menu's ask.
        panel.onFollowUp = { [weak self] text in self?.ask(.followUp(text), fromMenu: true) }
        answerPanel = panel
        return panel
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
        // Zero Day moves fast, so it renders at 30 fps; the idle crawl at 20.
        guard takeoverFrame % (idle.catless ? 2 : 3) == 0 else { return }
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
        let mayUseWall = routine != .hungry && routine != .play && routine != .crawl && routine != .ask
            && routine != .idleCrawl && routine != .zeroDay
            && Double.random(in: 0..<1) < scene.config.wallChance
        let surface: Surface = mayUseWall ? (Bool.random() ? .left : .right) : .bottom
        scene.setStage(surface: surface, screen: screen.visibleFrame, catSize: scene.cat.size)
        if routine == .idleCrawl || routine == .zeroDay { scene.crawlTargets = crawlTargets(on: screen) }
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
        if [.crawl, .idleCrawl, .zeroDay].contains(routine) { scene.cat.wearing.insert(.glasses) }
        // The invisible self-test stays silent too.
        if routine == .zeroDay, scene.config.zeroDaySound, !CommandLine.arguments.contains("--idle-selftest") {
            zeroDaySound.start(volume: Float(scene.config.zeroDayVolume))
        }
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
                               + (outfit.isEmpty ? "" : ", wearing \(outfit)") + (force && routine != .ask ? " (menu pick)" : ""))
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
        let wasAsking = behavior is AskBehavior
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
        // The card goes with the cat, whatever sent the cat away. An answer
        // with no card is not the cat's, so a new routine leaves it running.
        if wasAsking { asker.cancel() }
        conversation = []
        answerPanel?.dismiss()
        shownRecipe = -1
        zeroDaySound.stop()
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
        // Zero Day ending on time takes the same exit.
        if let idle = behavior as? IdleCrawlBehavior {
            if !idle.isExiting, touchedSinceIdleCrawl() {
                ActivityLog.shared.cat("idle crawl ended: you are back")
                idle.beginExit()
            }
            if idle.isExiting, !exitHandled {
                exitHandled = true
                takeover.clear()
                zeroDaySound.stop()
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

if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--app-icon" {
    renderAppIcon(to: CommandLine.arguments[2])
    exit(0)
}

if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--takeover" {
    renderTakeoverSheet(to: CommandLine.arguments[2])
    exit(0)
}
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--zeroday-sound" {
    ZeroDaySound.writeSample(to: CommandLine.arguments[2],
                             seconds: CommandLine.arguments.count >= 4 ? Double(CommandLine.arguments[3]) ?? 10 : 10)
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

// `--ask <text>` or `--ask-image <file>` sends one question through LLM mode's
// asker, with the real settings, and prints the answer. No cat, no card.
if CommandLine.arguments.count >= 3, ["--ask", "--ask-image"].contains(CommandLine.arguments[1]) {
    let arg = CommandLine.arguments[2]
    let question: Question
    if CommandLine.arguments[1] == "--ask" {
        question = .text(arg)
    } else if let image = NSImage(contentsOfFile: arg), let png = pngForUpload(image) {
        question = .image(png, from: "screenshot")
    } else {
        print("could not read \(arg)")
        exit(1)
    }
    let asker = Asker()
    let started = Date()
    var finished = false
    asker.ask(question, config: Config.load()) { answer in
        switch answer {
        case .text(let text): print(text)
        case .failed(let why): print("FAILED: \(why)")
        }
        print(String(format: "(%.1fs)", Date().timeIntervalSince(started)))
        finished = true
    }
    while !finished { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1)) }
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
