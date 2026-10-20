import AppKit
import Foundation

/// User settings, read from ~/.screencat.json. Every key is optional; missing keys
/// fall back to the defaults below, so a partial or hand-edited file still works.
struct Config {
    // Size ---------------------------------------------------------------
    /// Cat standing height = screen height / sizeDivisor. Bigger number = smaller cat.
    var sizeDivisor: CGFloat = 24

    // Timing -------------------------------------------------------------
    var firstAppearanceDelay: CGFloat = 20
    var minGapSeconds: CGFloat = 3
    var maxGapSeconds: CGFloat = 15

    // Pace, expressed in "body heights per second" so it scales with the cat.
    var walkSpeed: CGFloat = 1.35
    var runSpeed: CGFloat = 4.2

    // Behaviour lengths --------------------------------------------------
    var napSecondsMin: CGFloat = 20
    var napSecondsMax: CGFloat = 60
    var begSecondsMin: CGFloat = 9
    var begSecondsMax: CGFloat = 20
    var playSecondsMin: CGFloat = 4
    var playSecondsMax: CGFloat = 8

    /// How much smaller the cat gets at the top of the screen than at the
    /// bottom. This is what makes walking up read as walking away.
    var depthShrink: CGFloat = 0.18

    // Where the cat is allowed to be, and how steeply it may travel ----------
    /// The cat only roams the bottom this fraction of the screen.
    var roamHeight: CGFloat = 0.55
    /// Pulls positions toward the very bottom. 1 = anywhere in the band,
    /// higher = hugs the bottom edge more tightly.
    var groundBias: CGFloat = 3.0
    /// Steepest a walk may be, as a rise over run. Keeps travel to shallow
    /// diagonals so the cat never appears to drop straight down the screen.
    var maxSlope: CGFloat = 0.45
    /// How often a routine treats a side edge as the floor instead of the
    /// bottom, so the cat also walks up and down the left and right edges.
    var wallChance: Double = 0.4

    // Where the window sits, and who can see it ---------------------------
    /// "top" floats above full-screen apps, which is the only way the cat can
    /// appear over anything but the desktop. "status" and "floating" sit lower.
    var windowLevel = "top"
    /// Leave the cat out of screenshots, screen recordings and screen sharing,
    /// while still showing it to you on the glass.
    var hideFromCapture = true

    // Keeping out of the way ---------------------------------------------
    /// Stay hidden while video is playing or a blocked app is in front.
    var hideWhileWatching = true
    /// Bundle identifier fragments. Matched case-insensitively as substrings.
    var blockedApps: [String] = Watching.defaultBlockedApps

    // Relative chance of each behaviour being picked.
    var weightStroll: Double = 4
    var weightNap: Double = 2
    var weightBall: Double = 2
    var weightHungry: Double = 2
    /// Deliberately low: the invite ties the cat up for minutes at a time.
    var weightPlay: Double = 0.25

    /// How long the cat waits with its speech bubble up before giving up.
    var inviteSeconds: CGFloat = 180
    /// How long it follows the pointer once you accept.
    var followSeconds: CGFloat = 60
    /// Rest the pointer on the cat or its bubble this long to accept, instead of
    /// clicking OK. The button fills up as it counts.
    var dwellSeconds: CGFloat = 30
    /// How much the cat shrinks between the bottom of the screen and the top
    /// while following you. This is what makes moving up read as walking away
    /// rather than lifting off, so do not set it to zero.
    var followDepthShrink: CGFloat = 0.35
    /// Rest the pointer on the cat this long and it stops for a pet. 0 turns
    /// petting off.
    var petSeconds: CGFloat = 1.0

    // Look ---------------------------------------------------------------
    /// "cat" or "dog". The colour settings below recolour the cat; the dog
    /// keeps its own coat.
    var pet = "cat"
    var furColor = "#A87BE0"
    var furShadeColor = "#7E52B3"
    var outlineColor = "#2E1B47"
    var innerColor = "#F5A8CE"
    var eyeColor = "#FFC94A"
    var ballColor = "#BC4A9B"
    var shadow = true
    /// Chance per visit, 0 to 1, that the cat turns up in each accessory.
    var chainChance: Double = 1.0
    var glassesChance: Double = 0.35

    // Modes ----------------------------------------------------------------
    /// "normal", or "crawler": the cat goes round zapping windows and they
    /// look like they break. Only paint; no app is ever touched.
    var mode = "normal"
    /// In crawler mode, the chance that a visit is a crawl rather than a
    /// normal routine.
    var crawlChance: Double = 0.7
    /// Start the nonstop crawl after this long with no mouse, trackpad or
    /// keyboard input, whatever the mode. Any input stops it.
    var idleCrawl = true
    var idleCrawlSeconds: CGFloat = 1800
    /// How big the cat grows when the idle crawl starts, with a glow you can
    /// watch, before the screen turns into a glitch.
    var growScale: CGFloat = 2
    /// How long each full-screen glitch style plays before the next one.
    var glitchStyleSeconds: CGFloat = 60
    /// How fast the idle crawl's glitches animate and change. Zero Day runs
    /// at `zeroDaySpeed`.
    var glitchSpeed: CGFloat = 2
    var zeroDaySpeed: CGFloat = 8
    /// Zero Day's background sound, and how loud it is (0 to 1).
    var zeroDaySound = true
    var zeroDayVolume: CGFloat = 0.25
    /// Stepped out: keep the Mac awake and the screen on until you turn it
    /// off. Works with any mode.
    var steppedOut = false

    // LLM mode ----------------------------------------------------------------
    /// Answer what you copy, and screenshots you take, with Claude. Runs the
    /// `claude` command line tool with the login it already has.
    var llmMode = false
    var llmFromClipboard = true
    var llmFromScreenshots = true
    /// Put each answer on the clipboard as it arrives, ready to paste.
    var llmCopyAnswer = true
    /// Show the cat and the answer card. Off, answers only go to the
    /// clipboard, and the menu bar icon says when one is ready.
    var llmShowAnswer = true
    var llmModel = "claude-opus-5-5"
    /// How hard Claude thinks: "low", "medium", "high", "xhigh" or "max".
    var llmEffort = "medium"
    /// Full path to `claude`, if it is not in one of the usual places.
    var llmClaudePath = ""

    // Activity log ---------------------------------------------------------
    /// Keep a plain-text diary of apps, sleep, Bluetooth and what is running,
    /// in ~/Library/Logs/ScreenCat. Local only.
    var activityLog = true
    /// Day files older than this are deleted. 0 keeps them forever.
    var activityLogDays: CGFloat = 30
    var opacity: CGFloat = 1.0

    /// Recolour table applied to the sprite sheet when it loads.
    var spritePalette: SpritePalette {
        SpritePalette(fur: NSColor(hex: furColor) ?? .purple,
                      furShade: NSColor(hex: furShadeColor) ?? .purple,
                      outline: NSColor(hex: outlineColor) ?? .black,
                      inner: NSColor(hex: innerColor) ?? .systemPink,
                      eye: NSColor(hex: eyeColor) ?? .white,
                      ball: NSColor(hex: ballColor) ?? .magenta)
    }

    /// Colours for the few things drawn rather than blitted: the z's and the
    /// food bowl.
    var extras: Palette {
        Palette(outline: NSColor(hex: outlineColor) ?? .black,
                inner: NSColor(hex: innerColor) ?? .systemPink)
    }

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".screencat.json")
    }

    static func load() -> Config {
        var c = Config()
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return c
        }
        func num(_ key: String) -> CGFloat? { (raw[key] as? NSNumber).map { CGFloat($0.doubleValue) } }
        func dbl(_ key: String) -> Double? { (raw[key] as? NSNumber)?.doubleValue }
        func str(_ key: String) -> String? { raw[key] as? String }
        func bool(_ key: String) -> Bool? { raw[key] as? Bool }
        func strs(_ key: String) -> [String]? { raw[key] as? [String] }

        c.sizeDivisor           = num("sizeDivisor")           ?? c.sizeDivisor
        c.pet                   = str("pet")                   ?? c.pet
        c.firstAppearanceDelay  = num("firstAppearanceDelay")  ?? c.firstAppearanceDelay
        c.minGapSeconds         = num("minGapSeconds")         ?? c.minGapSeconds
        c.maxGapSeconds         = num("maxGapSeconds")         ?? c.maxGapSeconds
        c.walkSpeed             = num("walkSpeed")             ?? c.walkSpeed
        c.runSpeed              = num("runSpeed")              ?? c.runSpeed
        c.napSecondsMin         = num("napSecondsMin")         ?? c.napSecondsMin
        c.napSecondsMax         = num("napSecondsMax")         ?? c.napSecondsMax
        c.begSecondsMin         = num("begSecondsMin")         ?? c.begSecondsMin
        c.begSecondsMax         = num("begSecondsMax")         ?? c.begSecondsMax
        c.playSecondsMin        = num("playSecondsMin")        ?? c.playSecondsMin
        c.playSecondsMax        = num("playSecondsMax")        ?? c.playSecondsMax
        c.depthShrink           = num("depthShrink")           ?? c.depthShrink
        c.roamHeight            = num("roamHeight")            ?? c.roamHeight
        c.groundBias            = num("groundBias")            ?? c.groundBias
        c.maxSlope              = num("maxSlope")              ?? c.maxSlope
        c.wallChance            = dbl("wallChance")            ?? c.wallChance
        c.windowLevel           = str("windowLevel")           ?? c.windowLevel
        c.hideFromCapture       = bool("hideFromCapture")      ?? c.hideFromCapture
        c.weightStroll          = dbl("weightStroll")          ?? c.weightStroll
        c.weightNap             = dbl("weightNap")             ?? c.weightNap
        c.weightBall            = dbl("weightBall")            ?? c.weightBall
        c.weightHungry          = dbl("weightHungry")          ?? c.weightHungry
        c.weightPlay            = dbl("weightPlay")            ?? c.weightPlay
        c.inviteSeconds         = num("inviteSeconds")         ?? c.inviteSeconds
        c.followSeconds         = num("followSeconds")         ?? c.followSeconds
        c.dwellSeconds          = num("dwellSeconds")          ?? c.dwellSeconds
        c.followDepthShrink     = num("followDepthShrink")     ?? c.followDepthShrink
        c.petSeconds            = num("petSeconds")            ?? c.petSeconds
        c.furColor              = str("furColor")              ?? c.furColor
        c.furShadeColor         = str("furShadeColor")         ?? c.furShadeColor
        c.outlineColor          = str("outlineColor")          ?? c.outlineColor
        c.innerColor            = str("innerColor")            ?? c.innerColor
        c.eyeColor              = str("eyeColor")              ?? c.eyeColor
        c.ballColor             = str("ballColor")             ?? c.ballColor
        c.hideWhileWatching     = bool("hideWhileWatching")     ?? c.hideWhileWatching
        c.blockedApps           = strs("blockedApps")           ?? c.blockedApps
        c.shadow                = bool("shadow")               ?? c.shadow
        c.chainChance           = dbl("chainChance")           ?? c.chainChance
        c.glassesChance         = dbl("glassesChance")         ?? c.glassesChance
        c.mode                  = str("mode")                  ?? c.mode
        c.crawlChance           = dbl("crawlChance")           ?? c.crawlChance
        c.idleCrawl             = bool("idleCrawl")            ?? c.idleCrawl
        c.idleCrawlSeconds      = num("idleCrawlSeconds")      ?? c.idleCrawlSeconds
        c.glitchStyleSeconds    = num("glitchStyleSeconds")    ?? c.glitchStyleSeconds
        c.glitchSpeed           = num("glitchSpeed")           ?? c.glitchSpeed
        c.zeroDaySpeed          = num("zeroDaySpeed")          ?? c.zeroDaySpeed
        c.zeroDaySound          = bool("zeroDaySound")         ?? c.zeroDaySound
        c.zeroDayVolume         = num("zeroDayVolume")         ?? c.zeroDayVolume
        c.steppedOut            = bool("steppedOut")           ?? c.steppedOut
        c.llmMode               = bool("llmMode")              ?? c.llmMode
        c.llmFromClipboard      = bool("llmFromClipboard")     ?? c.llmFromClipboard
        c.llmFromScreenshots    = bool("llmFromScreenshots")   ?? c.llmFromScreenshots
        c.llmCopyAnswer         = bool("llmCopyAnswer")        ?? c.llmCopyAnswer
        c.llmShowAnswer         = bool("llmShowAnswer")        ?? c.llmShowAnswer
        c.llmModel              = str("llmModel")              ?? c.llmModel
        c.llmEffort             = str("llmEffort")             ?? c.llmEffort
        c.llmClaudePath         = str("llmClaudePath")         ?? c.llmClaudePath
        c.growScale             = num("growScale")             ?? c.growScale
        c.activityLog           = bool("activityLog")          ?? c.activityLog
        c.activityLogDays       = num("activityLogDays")       ?? c.activityLogDays
        c.opacity               = num("opacity")               ?? c.opacity

        c.sizeDivisor = max(2, min(60, c.sizeDivisor))
        if !["cat", "dog"].contains(c.pet) { c.pet = "cat" }
        c.roamHeight = max(0.05, min(1, c.roamHeight))
        c.groundBias = max(1, min(8, c.groundBias))
        c.maxSlope = max(0, min(2, c.maxSlope))
        c.wallChance = max(0, min(1, c.wallChance))
        c.minGapSeconds = max(3, c.minGapSeconds)
        c.maxGapSeconds = max(c.minGapSeconds, c.maxGapSeconds)
        c.opacity = max(0.1, min(1, c.opacity))
        // Each pair feeds `random(in: min...max)`, which traps when min > max,
        // so a hand edit that swaps them would crash the app on the next visit.
        c.napSecondsMin = max(0, c.napSecondsMin)
        c.napSecondsMax = max(c.napSecondsMin, c.napSecondsMax)
        c.begSecondsMin = max(0, c.begSecondsMin)
        c.begSecondsMax = max(c.begSecondsMin, c.begSecondsMax)
        c.playSecondsMin = max(0, c.playSecondsMin)
        c.playSecondsMax = max(c.playSecondsMin, c.playSecondsMax)
        c.petSeconds = max(0, c.petSeconds)
        c.crawlChance = max(0, min(1, c.crawlChance))
        c.idleCrawlSeconds = max(15, c.idleCrawlSeconds)
        c.glitchStyleSeconds = max(5, c.glitchStyleSeconds)
        c.glitchSpeed = max(0.25, min(16, c.glitchSpeed))
        c.zeroDaySpeed = max(1, min(16, c.zeroDaySpeed))
        c.zeroDayVolume = max(0, min(1, c.zeroDayVolume))
        c.growScale = max(1, min(4, c.growScale))
        if !["low", "medium", "high", "xhigh", "max"].contains(c.llmEffort) { c.llmEffort = "medium" }
        c.chainChance = max(0, min(1, c.chainChance))
        c.glassesChance = max(0, min(1, c.glassesChance))
        return c
    }

    /// Writes one key back to the settings file, leaving every other key, and
    /// any hand edits, exactly as they were.
    static func update(_ key: String, to value: Any) {
        var raw: [String: Any] = [:]
        if let data = try? Data(contentsOf: fileURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            raw = existing
        }
        raw[key] = value
        guard let data = try? JSONSerialization.data(withJSONObject: raw,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: fileURL)
    }

    /// Writes a fully commented-by-example default file if the user has none yet.
    static func writeDefaultFileIfMissing() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let d = Config()
        let dict: [String: Any] = [
            "sizeDivisor": d.sizeDivisor,
            "pet": d.pet,
            "firstAppearanceDelay": d.firstAppearanceDelay,
            "minGapSeconds": d.minGapSeconds,
            "maxGapSeconds": d.maxGapSeconds,
            "walkSpeed": d.walkSpeed,
            "runSpeed": d.runSpeed,
            "napSecondsMin": d.napSecondsMin,
            "napSecondsMax": d.napSecondsMax,
            "begSecondsMin": d.begSecondsMin,
            "begSecondsMax": d.begSecondsMax,
            "playSecondsMin": d.playSecondsMin,
            "playSecondsMax": d.playSecondsMax,
            "depthShrink": d.depthShrink,
            "roamHeight": d.roamHeight,
            "groundBias": d.groundBias,
            "maxSlope": d.maxSlope,
            "wallChance": d.wallChance,
            "windowLevel": d.windowLevel,
            "hideFromCapture": d.hideFromCapture,
            "weightStroll": d.weightStroll,
            "weightNap": d.weightNap,
            "weightBall": d.weightBall,
            "weightHungry": d.weightHungry,
            "weightPlay": d.weightPlay,
            "inviteSeconds": d.inviteSeconds,
            "followSeconds": d.followSeconds,
            "dwellSeconds": d.dwellSeconds,
            "followDepthShrink": d.followDepthShrink,
            "petSeconds": d.petSeconds,
            "furColor": d.furColor,
            "furShadeColor": d.furShadeColor,
            "outlineColor": d.outlineColor,
            "innerColor": d.innerColor,
            "eyeColor": d.eyeColor,
            "ballColor": d.ballColor,
            "hideWhileWatching": d.hideWhileWatching,
            "blockedApps": d.blockedApps,
            "shadow": d.shadow,
            "chainChance": d.chainChance,
            "glassesChance": d.glassesChance,
            "mode": d.mode,
            "crawlChance": d.crawlChance,
            "idleCrawl": d.idleCrawl,
            "idleCrawlSeconds": d.idleCrawlSeconds,
            "glitchStyleSeconds": d.glitchStyleSeconds,
            "glitchSpeed": d.glitchSpeed,
            "zeroDaySpeed": d.zeroDaySpeed,
            "zeroDaySound": d.zeroDaySound,
            "zeroDayVolume": d.zeroDayVolume,
            "steppedOut": d.steppedOut,
            "llmMode": d.llmMode,
            "llmFromClipboard": d.llmFromClipboard,
            "llmFromScreenshots": d.llmFromScreenshots,
            "llmCopyAnswer": d.llmCopyAnswer,
            "llmShowAnswer": d.llmShowAnswer,
            "llmModel": d.llmModel,
            "llmEffort": d.llmEffort,
            "growScale": d.growScale,
            "activityLog": d.activityLog,
            "activityLogDays": d.activityLogDays,
            "opacity": d.opacity,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: fileURL)
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt32(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let r = CGFloat((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(v & 0xFF) / 255 : 1
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
