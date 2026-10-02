import AppKit
import IOKit.pwr_mgt

/// Decides whether the cat should stay away.
///
/// Deliberately dumb: only apps you name in `blockedApps` can banish the cat,
/// and only while they are frontmost or fullscreen. Everything else gets the
/// cat, which is what you want from a desktop pet.
///
/// An earlier version inferred "is playing video" from the display-sleep power
/// assertion. It looked clever and was useless in practice: WhatsApp holds one
/// permanently as an idle timer, so focusing WhatsApp banished the cat. The
/// assertion helpers are kept below because `--watching` reports them, but
/// nothing decides anything from them any more.
enum Watching {
    static let defaultBlockedApps = [
        "org.videolan.vlc",
        "com.colliderli.iina",
        "io.mpv",
        "com.apple.QuickTimePlayerX",
        "com.apple.TV",
        "com.netflix.Netflix",
        "com.plexapp.plexamp",
        "tv.plex.desktop",
        "com.firecore.infuse",
    ]

    private static let displayAssertionTypes: Set<String> = [
        kIOPMAssertionTypePreventUserIdleDisplaySleep as String,
        kIOPMAssertionTypeNoDisplaySleep as String,
    ]

    /// True while some app is holding the display awake, anywhere at all.
    static func displayIsHeldAwake() -> Bool {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&raw) == kIOReturnSuccess,
              let status = raw?.takeRetainedValue() as? [String: Any] else { return false }
        for key in displayAssertionTypes {
            if let n = status[key] as? Int, n > 0 { return true }
        }
        return false
    }

    /// The processes currently holding a display-sleep assertion.
    static func pidsHoldingDisplayAssertions() -> Set<pid_t> {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byProcess = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        var pids = Set<pid_t>()
        for (pidNumber, assertions) in byProcess {
            let holdsOne = assertions.contains { entry in
                (entry[kIOPMAssertionTypeKey as String] as? String).map(displayAssertionTypes.contains) ?? false
            }
            if holdsOne { pids.insert(pid_t(truncating: pidNumber)) }
        }
        return pids
    }

    /// Normal on-screen windows belonging to `pids`, in AppKit coordinates.
    /// Window bounds and owner are readable without Screen Recording access;
    /// only window *titles* need it, and those are never asked for.
    static func windows(of pids: Set<pid_t>, allLayers: Bool = false) -> [(pid: pid_t, rect: CGRect, layer: Int)] {
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        // CGWindow coordinates are top-left origin; AppKit's are bottom-left.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        var found: [(pid_t, CGRect, Int)] = []
        for window in list {
            guard let owner = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(owner),
                  let layer = window[kCGWindowLayer as String] as? Int, allLayers || layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"] else { continue }
            found.append((owner, CGRect(x: x, y: primaryTop - (y + h), width: w, height: h), layer))
        }
        return found
    }

    /// Apps with at least one real window, on any Space, not just this one.
    /// Used to pick the next app to swipe to.
    static func pidsWithWindows() -> Set<pid_t> {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        var pids = Set<pid_t>()
        for window in list {
            guard let owner = window[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"], w >= 300, h >= 200,
                  (window[kCGWindowAlpha as String] as? CGFloat ?? 1) > 0 else { continue }
            pids.insert(owner)
        }
        return pids
    }

    /// One of `pids` filling the whole of `screen`. Covering the entire frame,
    /// menu bar included, is what separates true fullscreen from a merely
    /// zoomed window, which only reaches the visible frame.
    static func fullscreenHolder(pids: Set<pid_t>, on screen: NSScreen) -> pid_t? {
        let frame = screen.frame
        for (pid, rect, _) in windows(of: pids)
        where rect.width >= frame.width - 2 && rect.height >= frame.height - 2 && rect.intersects(frame) {
            return pid
        }
        return nil
    }

    /// True when the app in front is one the cat should not walk over. Being
    /// frontmost already implies it is on screen, so no window check is needed.
    static func frontmostIsBlocked(_ blocked: [String]) -> Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() else {
            return false
        }
        return blocked.contains { !$0.isEmpty && id.contains($0.lowercased()) }
    }

    static func shouldStayAway(_ config: Config, screen: NSScreen) -> Bool {
        reason(config, screen: screen) != nil
    }

    /// Processes belonging to apps on the blocked list.
    static func blockedPids(_ blocked: [String]) -> Set<pid_t> {
        var pids = Set<pid_t>()
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier?.lowercased() else { continue }
            if blocked.contains(where: { !$0.isEmpty && id.contains($0.lowercased()) }) {
                pids.insert(app.processIdentifier)
            }
        }
        return pids
    }

    /// A human-readable reason, or nil if the cat is free to come out.
    ///
    /// Only apps on `blockedApps` can keep the cat away, and only when they are
    /// frontmost or fullscreen. Nothing else gets a vote.
    ///
    /// This used to also treat "holds a display-sleep assertion" as "is playing
    /// video". That was wrong: WhatsApp holds one permanently as an idle timer,
    /// and Electron apps do the same, so ordinary apps kept banishing the cat.
    /// The trade-off is that video in a browser tab is no longer detected; add
    /// the browser to `blockedApps` if you want that back.
    static func reason(_ config: Config, screen: NSScreen) -> String? {
        guard config.hideWhileWatching else { return nil }

        if frontmostIsBlocked(config.blockedApps) {
            let name = NSWorkspace.shared.frontmostApplication?.localizedName ?? "an app"
            return "hiding: \(name) is in front"
        }
        if let pid = fullscreenHolder(pids: blockedPids(config.blockedApps), on: screen) {
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "an app"
            return "hiding: \(name) is fullscreen"
        }
        return nil
    }
}
