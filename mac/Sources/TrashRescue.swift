import AppKit
import CoreServices

// MARK: - Watching the Trash

/// Something you threw in the Trash from a watched folder.
struct TrashedItem {
    /// Where it was before: in a watched folder, or a folder inside one.
    let original: URL
    /// Where Finder put it. Finder renames it if the name is already taken in
    /// the Trash, so this is not always the original name.
    let inTrash: URL
    let isFolder: Bool
    /// The file system's ID for it. A move keeps it, so it says whether what
    /// is at `inTrash` later is still this item.
    let fileID: UInt64

    var name: String { original.lastPathComponent }

    /// True when its icon was right on the Desktop, not in a folder there.
    var wasOnDesktop: Bool {
        original.deletingLastPathComponent().path == TrashWatch.desktop.resolvingSymlinksInPath().path
    }
}

/// Why something stayed in the Trash, in plain words for the activity log.
struct RescueMiss: Error {
    let why: String
}

/// Sees things go from the watched folders to the Trash.
///
/// `~/.Trash` cannot be listed without Full Disk Access, but FSEvents still
/// reports both ends of a move into it: the path that went away and the
/// Trash path that appeared. The two ends carry the same file ID, which is
/// how they are paired. FSEvents also reports every folder inside a watched
/// one. Nothing here reads the files or looks inside the watched folders,
/// so watching never makes macOS ask for access to them.
final class TrashWatch {
    var onTrashed: (([TrashedItem]) -> Void)?

    /// The folders being watched, as `folders(_:)` gave them.
    private(set) var folders: [URL] = []
    let trash: URL
    private var stream: FSEventStreamRef?
    /// Each watched folder with every spelling of its path that FSEvents may
    /// use: as resolved, and the real one (/private/var for /var).
    private var roots: [(url: URL, spellings: [String])] = []
    private let trashSpellings: [String]
    /// One end of a move seen, the other not yet: what left a watched folder
    /// and what landed in the Trash, by file ID, with the event's ID. The two
    /// ends of one move come one straight after the other.
    private var departed: [UInt64: (path: String, isFolder: Bool, event: UInt64)] = [:]
    private var arrived: [UInt64: (path: String, event: UInt64)] = [:]

    init() {
        trash = TrashWatch.userTrash.resolvingSymlinksInPath()
        trashSpellings = TrashWatch.spellings(of: trash)
    }

    // The stream holds an unretained pointer to this object, so it must be
    // gone before the object is.
    deinit { stop() }

    static var desktop: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    static var userTrash: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    /// Watched when the settings file does not say.
    static let defaultFolders = ["~/Desktop", "~/Documents", "~/Downloads"]

    var isRunning: Bool { stream != nil }

    /// The folders to watch, from the setting: `~` expanded, links followed,
    /// each one once. Also what was left out and why, for the log: a path
    /// that is not there or not a folder, one on another disk (things thrown
    /// from there go to that disk's own Trash), the Trash or a folder that
    /// holds it, and a folder inside another watched one, which is covered
    /// already. Only looks at the folders themselves, never inside them.
    static func folders(_ paths: [String]) -> (folders: [URL], skipped: [String]) {
        let fm = FileManager.default
        let trash = userTrash.resolvingSymlinksInPath().path
        let volumeKey: Set<URLResourceKey> = [.volumeIdentifierKey]
        let homeVolume = try? fm.homeDirectoryForCurrentUser.resourceValues(forKeys: volumeKey).volumeIdentifier
        func inside(_ path: String, _ folder: String) -> Bool { path == folder || path.hasPrefix(folder + "/") }
        func short(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }
        var found: [URL] = []
        var skipped: [String] = []
        for path in paths {
            let expanded = (path as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/") else { skipped.append("\(path) is not a full path"); continue }
            let url = URL(fileURLWithPath: expanded, isDirectory: true).resolvingSymlinksInPath()
            var isFolder: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isFolder) else {
                skipped.append("\(path) is not there")
                continue
            }
            guard isFolder.boolValue else { skipped.append("\(path) is not a folder"); continue }
            guard !inside(url.path, trash), !inside(trash, url.path) else {
                skipped.append("\(path) is or holds the Trash")
                continue
            }
            let volume = try? url.resourceValues(forKeys: volumeKey).volumeIdentifier
            if let volume, let homeVolume, !volume.isEqual(homeVolume) {
                skipped.append("\(path) is on another disk, which has its own Trash")
                continue
            }
            found.append(url)
        }
        var kept: [URL] = []
        for url in found where !kept.contains(where: { $0.path == url.path }) {
            if let outer = found.first(where: { $0.path != url.path && inside(url.path, $0.path) }) {
                skipped.append("\(short(url.path)) is inside \(short(outer.path)), watched already")
                continue
            }
            kept.append(url)
        }
        return (kept, skipped)
    }

    /// A path as resolved, and as the file system really spells it, which is
    /// how FSEvents reports it.
    private static func spellings(of url: URL) -> [String] {
        guard let real = realpath(url.path, nil) else { return [url.path] }
        defer { free(real) }
        let path = String(cString: real)
        return path == url.path ? [path] : [url.path, path]
    }

    /// Watches `folders`, and every folder inside them, and the Trash.
    /// Already watching others, it starts over with these. False when there
    /// is nothing to watch or FSEvents will not have it.
    @discardableResult
    func start(_ folders: [URL]) -> Bool {
        if stream != nil {
            if folders == self.folders { return true }
            stop()
        }
        guard !folders.isEmpty else { return false }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
            guard let info else { return }
            let watch = Unmanaged<TrashWatch>.fromOpaque(info).takeUnretainedValue()
            watch.handle(unsafeBitCast(paths, to: NSArray.self),
                         flags: Array(UnsafeBufferPointer(start: flags, count: count)),
                         ids: Array(UnsafeBufferPointer(start: ids, count: count)))
        }
        let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagUseExtendedData
        guard let s = FSEventStreamCreate(nil, callback, &context, (folders.map(\.path) + [trash.path]) as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2,
                                          FSEventStreamCreateFlags(flags)) else { return false }
        self.folders = folders
        roots = folders.map { ($0, TrashWatch.spellings(of: $0)) }
        FSEventStreamSetDispatchQueue(s, .main)
        guard FSEventStreamStart(s) else {
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            self.folders = []
            roots = []
            return false
        }
        stream = s
        return true
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
        folders = []
        roots = []
        departed = [:]
        arrived = [:]
    }

    private func handle(_ paths: NSArray, flags: [FSEventStreamEventFlags], ids: [FSEventStreamEventId]) {
        let renamed = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)
        let isDir = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)
        // Only renames are unpacked. A code project in Documents can send
        // thousands of other events in a second.
        for i in flags.indices where flags[i] & renamed != 0 {
            guard let entry = paths[i] as? NSDictionary,
                  let path = entry[kFSEventStreamEventExtendedDataPathKey] as? String,
                  let id = (entry[kFSEventStreamEventExtendedFileIDKey] as? NSNumber)?.uint64Value else { continue }
            // A rename event does not say which end it is. In the Trash, the
            // end that still exists is where the item went. In a watched
            // folder it is taken as where it came from, unchecked, as a look
            // there could make macOS ask for access: a move the other way,
            // out of the Trash, never has a Trash end that still exists.
            if let from = watchedPath(path) {
                departed[id] = (from, flags[i] & isDir != 0, ids[i])
            } else if let landed = trashPath(path), FileManager.default.fileExists(atPath: path) {
                arrived[id] = (landed, ids[i])
            }
        }

        var found: [TrashedItem] = []
        for (id, gone) in departed {
            // Same item and the very next events: one move, into the Trash.
            // Moved to another folder first and thrown away from there is two
            // moves, far apart in the event stream. Moved from one watched
            // folder to another has no Trash end at all.
            guard let landed = arrived[id],
                  max(landed.event, gone.event) - min(landed.event, gone.event) <= 3 else { continue }
            found.append(TrashedItem(original: URL(fileURLWithPath: gone.path, isDirectory: gone.isFolder),
                                     inTrash: URL(fileURLWithPath: landed.path, isDirectory: gone.isFolder),
                                     isFolder: gone.isFolder, fileID: id))
            departed[id] = nil
            arrived[id] = nil
        }
        // Events come in order, so an end more than three events behind the
        // newest can never be paired now: moved somewhere else, or emptied
        // straight away. Forget it.
        if let newest = ids.max() {
            departed = departed.filter { $0.value.event + 3 >= newest }
            arrived = arrived.filter { $0.value.event + 3 >= newest }
        }
        if !found.isEmpty { onTrashed?(found.sorted { $0.name < $1.name }) }
    }

    /// The path spelled from the watched folder it is in, the way it will be
    /// put back. Nil when it is in none, or is hidden or inside a hidden
    /// folder such as `.git`, which Finder does not show.
    private func watchedPath(_ path: String) -> String? {
        for root in roots {
            for spelling in root.spellings where path.hasPrefix(spelling + "/") {
                let rest = path.dropFirst(spelling.count + 1)
                guard !rest.hasPrefix("."), !rest.contains("/.") else { return nil }
                return root.url.path + "/" + rest
            }
        }
        return nil
    }

    /// The path when it is right in the Trash and not hidden, else nil.
    private func trashPath(_ path: String) -> String? {
        let name = (path as NSString).lastPathComponent
        guard !name.hasPrefix("."), trashSpellings.contains((path as NSString).deletingLastPathComponent) else {
            return nil
        }
        return trash.path + "/" + name
    }

    /// Moves an item back where it was. If something new has taken its name
    /// meanwhile, it comes back as "name 2", the way Finder numbers copies.
    /// Throws, with the reason, when it is gone from the Trash, something
    /// else is at its Trash path now, or the move fails. The first move into
    /// a protected folder such as Documents may wait on the macOS prompt
    /// for access, so the app calls this off the main thread.
    static func restore(_ item: TrashedItem) throws -> URL {
        let fm = FileManager.default
        // Only the item that was seen going in. Put back and thrown again
        // from elsewhere, another item can land on the same Trash path.
        let id = (try? fm.attributesOfItem(atPath: item.inTrash.path)[.systemFileNumber] as? NSNumber)?.uint64Value
        guard id == item.fileID else { throw RescueMiss(why: "gone from the Trash, or something else is there now") }
        let folder = item.original.deletingLastPathComponent()
        let ext = item.original.pathExtension
        let stem = item.original.deletingPathExtension().lastPathComponent
        // A plain folder is numbered after its whole name. A file, or a
        // bundle such as a .pages or .app, before its extension.
        let isPackage = (try? item.inTrash.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
        let numberWhole = ext.isEmpty || (item.isFolder && isPackage != true)
        var target = item.original
        var n = 2
        while fm.fileExists(atPath: target.path) {
            let name = numberWhole ? "\(item.name) \(n)" : "\(stem) \(n).\(ext)"
            target = folder.appendingPathComponent(name, isDirectory: item.isFolder)
            n += 1
        }
        // Looked at again just before the move: the checks above can wait on
        // the macOS prompt for a while, and the Trash can change meanwhile.
        let stillThere = (try? fm.attributesOfItem(atPath: item.inTrash.path)[.systemFileNumber] as? NSNumber)?.uint64Value
        guard stillThere == item.fileID else { throw RescueMiss(why: "gone from the Trash, or something else is there now") }
        do {
            try fm.moveItem(at: item.inTrash, to: target)
            return target
        } catch {
            guard isNoAccess(error) else { throw RescueMiss(why: error.localizedDescription) }
            // A file some app opened for you (a film opened in VLC, say)
            // carries a label that lets only that app and Finder move it, and
            // macOS says EPERM. Finder can, so it is asked to. Not for a plain
            // locked folder (EACCES): Finder would ask for a password.
            let posix = ((error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError)?.code
            if posix == Int(EPERM), moveWithFinder(item.inTrash, to: target) { return target }
            throw RescueMiss(why: noAccess(folder, error))
        }
    }

    /// Moves an item with Finder, through `osascript`, and gives it the
    /// target's name. macOS asks once whether Screen Cat may control Finder.
    /// True when the item is at `target` afterwards.
    private static func moveWithFinder(_ from: URL, to target: URL) -> Bool {
        let rename = target.lastPathComponent == from.lastPathComponent ? "" : target.lastPathComponent
        let script = [
            "on run argv",
            "tell application \"Finder\"",
            "set moved to move (POSIX file (item 1 of argv) as alias) to (POSIX file (item 2 of argv) as alias)",
            "if (item 3 of argv) is not \"\" then set name of moved to (item 3 of argv)",
            "end tell",
            "end run",
        ]
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = script.flatMap { ["-e", $0] }
            + [from.path, target.deletingLastPathComponent().path, rename]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return false
        }
        p.waitUntilExit()
        return p.terminationStatus == 0 && FileManager.default.fileExists(atPath: target.path)
    }

    /// macOS said no: no permission to write there.
    private static func isNoAccess(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == NSCocoaErrorDomain, [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(e.code) {
            return true
        }
        guard let under = e.userInfo[NSUnderlyingErrorKey] as? NSError, under.domain == NSPOSIXErrorDomain else {
            return false
        }
        return under.code == Int(EPERM) || under.code == Int(EACCES)
    }

    /// Why a folder cannot be used, and the fix. Only the Desktop, Documents
    /// and Downloads are behind the macOS privacy setting, and macOS says no
    /// to those with EPERM. Anything else, such as a locked folder, is a
    /// plain file permission (EACCES).
    static func noAccess(_ folder: URL, _ error: Error? = nil) -> String {
        let place = place(of: folder)
        let posix = ((error as NSError?)?.userInfo[NSUnderlyingErrorKey] as? NSError)?.code
        guard ["Desktop", "Documents", "Downloads"].contains(place), posix != Int(EACCES) else {
            return "no permission to write to \((folder.path as NSString).abbreviatingWithTildeInPath)"
        }
        return "no access to \(place), allow Screen Cat in System Settings > Privacy & Security > Files and Folders"
    }

    /// The folder in your home that holds `folder`, such as Documents, as
    /// macOS names it in the privacy settings. Outside home, the folder's own
    /// name.
    private static func place(of folder: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard folder.path.hasPrefix(home + "/"),
              let top = folder.path.dropFirst(home.count + 1).split(separator: "/").first else {
            return folder.lastPathComponent
        }
        return String(top)
    }
}

// MARK: - Where the Trash is

/// Where the Trash sits in the Dock, as a global x on the cat's floor.
///
/// There is no public way to ask the Dock where its icons are without the
/// Accessibility permission, so this works it out from the Dock's own
/// settings: which side it is on, the icon size, and how many icons it shows.
/// It only has to be close: the cat digs at the spot, not in the icon.
enum DockTrash {
    /// The screen the Dock is on: the one with room kept for it, else the
    /// one with the menu bar.
    static func screen() -> NSScreen {
        let screens = NSScreen.screens
        let reserved = screens.first { s in
            s.visibleFrame.minY - s.frame.minY > 8 || s.visibleFrame.minX - s.frame.minX > 8
                || s.frame.maxX - s.visibleFrame.maxX > 8
        }
        return reserved ?? screens.first ?? targetScreen()
    }

    static func x(on screen: NSScreen) -> CGFloat {
        let dock = UserDefaults(suiteName: "com.apple.dock")
        let orientation = dock?.string(forKey: "orientation") ?? "bottom"
        let tile = tileSize(dock)
        let frame = screen.frame
        let visible = screen.visibleFrame
        switch orientation {
        case "left":
            // A side Dock ends with the Trash at its bottom, so the spot is the
            // bottom corner on that side.
            return visible.minX + tile * 0.6
        case "right":
            return visible.maxX - tile * 0.6
        default:
            let trash = frame.midX + length(dock, tile: tile) / 2 - tile * 0.15 - tile / 2
            return min(max(trash, visible.minX + tile), visible.maxX - tile * 0.5)
        }
    }

    /// Where Finder sits in the Dock, at the other end from the Trash, as a
    /// global point. Things thrown from a folder other than the Desktop are
    /// tossed back there. Like the Trash spot, only close.
    static func finder(on screen: NSScreen) -> CGPoint {
        let dock = UserDefaults(suiteName: "com.apple.dock")
        let orientation = dock?.string(forKey: "orientation") ?? "bottom"
        let tile = tileSize(dock)
        let frame = screen.frame
        let visible = screen.visibleFrame
        switch orientation {
        case "left", "right":
            // A side Dock starts with Finder at its top.
            let x = orientation == "left" ? (frame.minX + visible.minX) / 2 : (visible.maxX + frame.maxX) / 2
            let top = frame.midY + length(dock, tile: tile) / 2 - tile * 0.65
            return CGPoint(x: x, y: min(top, visible.maxY - tile / 2))
        default:
            let x = frame.midX - length(dock, tile: tile) / 2 + tile * 0.15 + tile / 2
            return CGPoint(x: min(max(x, visible.minX + tile * 0.5), visible.maxX - tile), y: visible.minY)
        }
    }

    /// The Dock's icon size, in points.
    private static func tileSize(_ dock: UserDefaults?) -> CGFloat {
        let size = CGFloat(dock?.double(forKey: "tilesize") ?? 0)
        return size > 0 ? size : 48
    }

    /// How long the Dock is from end to end: every icon, the separators and
    /// a little padding.
    private static func length(_ dock: UserDefaults?, tile: CGFloat) -> CGFloat {
        let count = CGFloat(iconCount(dock))
        let separators: CGFloat = showsRecents(dock) ? 2 : 1
        return count * tile + separators * tile * 0.35 + tile * 0.3
    }

    private static func showsRecents(_ dock: UserDefaults?) -> Bool {
        dock?.object(forKey: "show-recents") as? Bool ?? true
    }

    /// Finder, the kept apps, the running ones not kept, the recent ones if
    /// shown, the folders on the right, and the Trash itself.
    private static func iconCount(_ dock: UserDefaults?) -> Int {
        func bundleIDs(_ key: String) -> [String] {
            (dock?.array(forKey: key) as? [[String: Any]] ?? []).compactMap {
                ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
            }
        }
        let kept = Set(bundleIDs("persistent-apps"))
        let others = (dock?.array(forKey: "persistent-others") ?? []).count
        let running = Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier))
            .subtracting(kept)
            .subtracting(["com.apple.finder"])
        var middle = running
        if showsRecents(dock) { middle.formUnion(bundleIDs("recent-apps")) }
        return 1 + kept.count + middle.subtracting(kept).count + others + 1
    }
}

// MARK: - The rescue

/// The cat runs to the Trash, digs out what you just threw away, carries it
/// back out, and tosses it home, where it really appears again: up to the
/// Desktop icons, or to Finder in the Dock for things from other folders.
/// Level the whole way: in from the side, along the floor, out the side.
final class RescueBehavior: Behavior {
    private enum Stage { case arriving, digging, carrying, tossing, proud, leaving }
    private var stage: Stage = .arriving
    private var walk: ScriptedBehavior
    private var timer: CGFloat = 0
    private var items: [TrashedItem]
    private let trashX: CGFloat
    /// Called once, when the toss lands. The app moves the items back then.
    var onRestore: (([TrashedItem]) -> Void)?
    /// True once the items have been handed back. A rescue cut short before
    /// that leaves them in the Trash.
    private(set) var restored = false

    /// What the cat has on its back, or what is flying, for the overlay.
    private(set) var carried: CarriedItem?
    private var tossFrom = CGPoint.zero
    private var tossTo = CGPoint.zero

    init(scene: Scene, items: [TrashedItem], trashX: CGFloat) {
        self.items = items
        let cat = scene.cat
        let rect = scene.stage
        let size = cat.size
        let floor = rect.minY
        self.trashX = min(max(trashX, rect.minX + size), rect.maxX - size * 0.6)
        // In from the side nearer the Trash, so it gets there quickly.
        let fromRight = self.trashX > rect.midX
        cat.pos = CGPoint(x: fromRight ? rect.maxX + size * 1.4 : rect.minX - size * 1.4, y: floor)
        cat.facing = fromRight ? -1 : 1
        cat.visible = true
        walk = ScriptedBehavior([.runTo(CGPoint(x: self.trashX, y: floor), pace: 1.3)])
    }

    /// More things thrown away while it is on its way are carried out too.
    /// Returns false once it is too late to pick them up.
    func add(_ more: [TrashedItem]) -> Bool {
        guard stage == .arriving || stage == .digging else { return false }
        items += more.filter { new in !items.contains { $0.inTrash == new.inTrash } }
        return true
    }

    func update(_ dt: CGFloat, _ scene: Scene) -> Bool {
        let cat = scene.cat
        let rect = scene.stage
        let pixel = cat.pixelScale
        switch stage {
        case .arriving:
            if walk.update(dt, scene) {
                stage = .digging
                timer = 1.1
                cat.setClip(.crouch)
            }

        case .digging:
            timer -= dt
            // Out it pops, up from the Trash onto the cat's back.
            let popAt: CGFloat = 0.3
            if timer < popAt {
                let t = 1 - max(timer, 0) / popAt
                var item = held(cat, scene.sheet)
                item.pos.y = cat.pos.y + (item.pos.y - cat.pos.y) * t
                item.alpha = t
                carried = item
            }
            if timer <= 0 {
                stage = .carrying
                // Back toward the middle, a good way from the Trash.
                let away: CGFloat = trashX > rect.midX ? -1 : 1
                let x = min(max(trashX + away * rect.width * 0.22, rect.minX + cat.size), rect.maxX - cat.size)
                walk = ScriptedBehavior([.walkTo(CGPoint(x: x, y: rect.minY), pace: 1.25, bend: 0)])
            }

        case .carrying:
            let done = walk.update(dt, scene)
            carried = held(cat, scene.sheet)
            if done {
                // Still mid-stride with it on its back for the wind-up; it
                // only looks up once the thing is in the air.
                stage = .tossing
                timer = 0
                tossFrom = held(cat, scene.sheet).pos
                // Desktop icons line up from the top right by default.
                // Anything else goes to Finder, which holds the other
                // folders. The first thing on its back decides.
                if items.first?.wasOnDesktop ?? true {
                    tossTo = CGPoint(x: rect.maxX - cat.size * 1.6, y: rect.maxY - cat.size * 1.8)
                } else {
                    let finder = scene.finderSpot
                    tossTo = CGPoint(x: min(max(finder.x, rect.minX + cat.size * 0.5), rect.maxX - cat.size * 0.5),
                                     y: min(max(finder.y, rect.minY), rect.maxY - cat.size))
                }
            }

        case .tossing:
            timer += dt
            let wind: CGFloat = 0.25
            let flight: CGFloat = 0.85
            if timer > wind {
                cat.setClip(.standIdle)
                let t = min((timer - wind) / flight, 1)
                // One arc up and over, easing out as it nears the icons.
                let e = 1 - pow(1 - t, 2)
                let control = CGPoint(x: (tossFrom.x + tossTo.x) / 2,
                                      y: max(tossFrom.y, tossTo.y) + rect.height * 0.12)
                let u = 1 - e
                let p = CGPoint(x: u * u * tossFrom.x + 2 * u * e * control.x + e * e * tossTo.x,
                                y: u * u * tossFrom.y + 2 * u * e * control.y + e * e * tossTo.y)
                carried = carrying(at: p, pixel: pixel * (1 + 0.8 * e),
                                   alpha: t < 0.7 ? 1 : max(0, (1 - t) / 0.3))
                if t >= 1 {
                    carried = nil
                    if !restored {
                        restored = true
                        onRestore?(items)
                    }
                    stage = .proud
                    timer = 1.6
                    cat.setClip(.sitIdle)
                }
            }

        case .proud:
            timer -= dt
            if timer <= 0 {
                stage = .leaving
                walk = ScriptedBehavior([
                    .hold(.standIdle, 0.3),
                    .walkTo(exitPoint(rect, from: cat.pos, size: cat.size), pace: 1.3, bend: 0),
                ])
            }

        case .leaving:
            return walk.update(dt, scene)
        }
        return false
    }

    /// The item riding on the pet's back. The side-on walk carries the
    /// head low, about 7 sheet pixels up, so anything held in the mouth
    /// would drag along the floor; on the back it reads as carried. The spot
    /// comes from the frame itself, so it rises and falls with each step.
    private func held(_ cat: CatState, _ sheet: SpriteSheet?) -> CarriedItem {
        let ps = cat.pixelScale
        let half = CGFloat(SpriteSheet.frameSize) / 2
        let back = sheet?.backTop(cat.clip, cat.frameIndex) ?? (x: 12, y: 14)
        // Mirrored frames are flipped about the middle of the frame.
        let mirrored = cat.clip.info.mirrors && cat.facing < 0
        let column = CGFloat(back.x) + 0.5 - half
        // Sunk one pixel into the fur, so it sits rather than hovers.
        return carrying(at: CGPoint(x: cat.pos.x + (mirrored ? -column : column) * ps,
                                    y: cat.pos.y + (SpriteSheet.groundRow - CGFloat(back.y) - 1) * ps),
                        pixel: ps)
    }

    /// What is being rescued, drawn at one spot: a folder or a page, as a
    /// stack when there is more than one.
    private func carrying(at pos: CGPoint, pixel: CGFloat, alpha: CGFloat = 1) -> CarriedItem {
        CarriedItem(isFolder: items.first?.isFolder ?? true, count: items.count,
                    pos: pos, pixel: pixel, alpha: alpha)
    }
}

/// The folder or page the cat is carrying, drawn as pixel art like the bowl.
struct CarriedItem {
    var isFolder: Bool
    /// More than one thing rescued at once shows as a little stack.
    var count: Int
    /// Bottom middle of the icon, in surface-local coordinates.
    var pos: CGPoint
    var pixel: CGFloat
    var alpha: CGFloat

    var glyph: [String] { isFolder ? folderGlyph : pageGlyph }

    /// One copy, in points.
    var size: CGSize {
        CGSize(width: CGFloat(glyph[0].count) * pixel, height: CGFloat(glyph.count) * pixel)
    }

    /// The whole drawing, the stacked copy included, with a pixel to spare.
    var bounds: CGRect {
        let extra = count > 1 ? pixel * 2 : 0
        return CGRect(x: pos.x - size.width / 2 - pixel, y: pos.y - pixel,
                      width: size.width + extra + pixel * 2, height: size.height + extra + pixel * 2)
    }
}

/// Small enough to carry: about a quarter of the cat's height, in the
/// sprite's own pixel size.
private let folderGlyph = [
    "ooo.....",
    "ottooooo",
    "oooooooo",
    "offffffo",
    "offffffo",
    "oooooooo",
]

private let pageGlyph = [
    "oooo..",
    "owwoo.",
    "owllwo",
    "owwwwo",
    "owllwo",
    "oooooo",
]

private let folderFace = NSColor(srgbRed: 0.40, green: 0.72, blue: 0.96, alpha: 1)
private let folderTab = NSColor(srgbRed: 0.29, green: 0.60, blue: 0.88, alpha: 1)
private let pageWhite = NSColor(white: 0.98, alpha: 1)
private let pageLine = NSColor(white: 0.72, alpha: 1)

func drawCarriedItem(_ item: CarriedItem, palette: Palette, in ctx: CGContext) {
    // The sprite's own pixel size, not rounded to whole points, so the
    // item and the cat read as the same pixel art.
    let p = item.pixel
    let glyph = item.glyph
    let width = item.size.width
    ctx.saveGState()
    ctx.setShouldAntialias(false)
    ctx.setAlpha(max(0, min(1, item.alpha)))
    // A second copy peeking out behind says "more than one".
    let copies = item.count > 1 ? [CGPoint(x: p * 2, y: p * 2), .zero] : [.zero]
    for shift in copies {
        let origin = CGPoint(x: item.pos.x - width / 2 + shift.x, y: item.pos.y + shift.y)
        for (rowIndex, row) in glyph.reversed().enumerated() {
            for (colIndex, ch) in row.enumerated() {
                let color: NSColor
                switch ch {
                case "o": color = palette.outline
                case "t": color = folderTab
                case "f": color = folderFace
                case "w": color = pageWhite
                case "l": color = pageLine
                default: continue
                }
                color.setFill()
                CGRect(x: origin.x + CGFloat(colIndex) * p, y: origin.y + CGFloat(rowIndex) * p,
                       width: p, height: p).fill()
            }
        }
    }
    ctx.restoreGState()
}

// MARK: - Self-test

/// Throws scratch things away (a file, a folder, a name the Trash already
/// holds, one from a folder inside a watched one, and more), checks the
/// watcher reports each one, puts them back, and checks they are where they
/// started. With `realFolders` it also throws from the real Documents and
/// Downloads. macOS protects those, so run that only from a shell that has
/// access, or macOS asks. Cleans up after itself, in every folder and in
/// the Trash. Exits with 0 when every case passes.
func runRescueSelfTest(onDesktop: Bool, realFolders: Bool) -> Never {
    let fm = FileManager.default
    let scratch = fm.temporaryDirectory.appendingPathComponent("ScreenCatRescueTest", isDirectory: true)
    /// A second watched folder, for a move from one watched folder to another.
    let other = fm.temporaryDirectory.appendingPathComponent("ScreenCatRescueTest2", isDirectory: true)
    let folder = onDesktop ? TrashWatch.desktop : scratch
    for url in [scratch, other] { try? fm.createDirectory(at: url, withIntermediateDirectories: true) }
    let stamp = Int(Date().timeIntervalSince1970)
    let tag = "screencat-rescue-test-\(stamp)"
    let watch = TrashWatch()
    var seen: [TrashedItem] = []
    // Only our own scratch things. Something you throw away meanwhile is not
    // part of the test.
    watch.onTrashed = { seen += $0.filter { $0.name.hasPrefix(tag) } }
    /// Our own scratch things still in the Trash, to take back out and delete.
    var leftovers: [(trashed: URL, home: URL)] = []
    var made: [URL] = []
    /// Folders made read-only, to open up again before deleting.
    var locked: [URL] = []

    func cleanUp() {
        for url in locked { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        // Out of the Trash by a move, which needs no Full Disk Access, then
        // deleted. Somewhere else in the scratch folder if home is taken.
        for (i, leftover) in leftovers.enumerated() where fm.fileExists(atPath: leftover.trashed.path) {
            for out in [leftover.home, scratch.appendingPathComponent("leftover-\(i)")]
            where !fm.fileExists(atPath: out.path) {
                if (try? fm.moveItem(at: leftover.trashed, to: out)) != nil { made.append(out); break }
            }
        }
        // Newest first, so things go before the folders they are in.
        for url in made.reversed() { try? fm.removeItem(at: url) }
        for url in [scratch, other] { try? fm.removeItem(at: url) }
        for leftover in leftovers where fm.fileExists(atPath: leftover.trashed.path) {
            print("  still in the Trash: \(leftover.trashed.path)")
        }
    }
    func fail(_ why: String) -> Never {
        print("FAIL: \(why)")
        cleanUp()
        exit(1)
    }
    func wait(_ seconds: Double, until done: () -> Bool) {
        let end = Date().addingTimeInterval(seconds)
        while !done() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }
    func make(_ url: URL, folder isFolder: Bool) {
        do {
            if isFolder {
                try fm.createDirectory(at: url, withIntermediateDirectories: false)
                try "inside".write(to: url.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
            } else {
                try "rescue me".write(to: url, atomically: true, encoding: .utf8)
            }
        } catch { fail("could not make \(url.path): \(error)") }
        made.append(url)
        wait(0.5) { false }
    }
    /// Trashes `url` and returns what the watcher reported for it.
    func throwAway(_ url: URL) -> TrashedItem {
        let expected = url.resolvingSymlinksInPath().path
        seen = []
        var landed: NSURL?
        do { try fm.trashItem(at: url, resultingItemURL: &landed) } catch { fail("could not trash: \(error)") }
        guard let landed = landed as URL? else { fail("no Trash path for \(url.lastPathComponent)") }
        leftovers.append((landed, url))
        wait(3) { !seen.isEmpty }
        guard let item = seen.first else { fail("watcher saw nothing for \(url.lastPathComponent)") }
        guard item.original.path == expected else {
            fail("wrong original path \(item.original.path), expected \(expected)")
        }
        guard item.inTrash.lastPathComponent == landed.lastPathComponent else {
            fail("wrong Trash path \(item.inTrash.path), expected \(landed.path)")
        }
        print("  saw \(item.name) go to the Trash as \(item.inTrash.lastPathComponent), folder \(item.isFolder)")
        return item
    }
    func putBack(_ item: TrashedItem, expect url: URL) {
        let back: URL
        do { back = try TrashWatch.restore(item) } catch {
            fail("restore of \(item.name) failed: \((error as? RescueMiss)?.why ?? "\(error)")")
        }
        guard back.path == url.resolvingSymlinksInPath().path, fm.fileExists(atPath: url.path) else {
            fail("\(item.name) came back at \(back.path)")
        }
        leftovers.removeAll { $0.trashed.lastPathComponent == item.inTrash.lastPathComponent }
        print("  put back at \(back.path.replacingOccurrences(of: folder.path + "/", with: ""))")
    }

    print("folders that cannot be watched:")
    let sub = folder.appendingPathComponent("\(tag) sub", isDirectory: true)
    make(sub, folder: true)
    let plain = scratch.appendingPathComponent("\(tag)-not-a-folder.txt")
    make(plain, folder: false)
    let bad = [scratch.appendingPathComponent("\(tag)-not-there").path, plain.path, "~/.Trash", sub.path,
               "relative/folder"]
    let wanted = [folder.path, other.path] + (realFolders ? TrashWatch.defaultFolders : [])
    let watched = TrashWatch.folders(wanted + bad)
    for line in watched.skipped { print("  skipped \(line)") }
    guard watched.skipped.count == bad.count else { fail("skipped \(watched.skipped.count) of \(bad.count)") }
    guard watched.folders.count == (realFolders ? (onDesktop ? 4 : 5) : 2) else {
        fail("watching \(watched.folders.map(\.path))")
    }
    guard watch.start(watched.folders) else { fail("could not start watching") }
    print("  watching \(watched.folders.count) folders")

    print("file:")
    let file = folder.appendingPathComponent("\(tag).txt")
    make(file, folder: false)
    let fileItem = throwAway(file)
    guard !fileItem.isFolder else { fail("a file was reported as a folder") }
    putBack(fileItem, expect: file)
    guard (try? String(contentsOf: file, encoding: .utf8)) == "rescue me" else { fail("file came back changed") }
    // Moving it back out of the Trash must not look like a new throw.
    seen = []
    wait(1.5) { !seen.isEmpty }
    guard seen.isEmpty else { fail("putting back was reported as a new throw") }

    print("folder:")
    let box = folder.appendingPathComponent("\(tag) folder")
    make(box, folder: true)
    let boxItem = throwAway(box)
    guard boxItem.isFolder else { fail("a folder was reported as a file") }
    putBack(boxItem, expect: box)
    guard fm.fileExists(atPath: box.appendingPathComponent("note.txt").path) else { fail("folder came back empty") }

    print("same name already in the Trash:")
    let twin = folder.appendingPathComponent("\(tag)-twin.txt")
    make(twin, folder: false)
    let first = throwAway(twin)
    make(twin, folder: false)
    let second = throwAway(twin)
    guard first.inTrash != second.inTrash else { fail("both throws reported the same Trash path") }
    putBack(second, expect: twin)
    // The first one is ours too; it comes back under the next free name.
    guard let firstBack = try? TrashWatch.restore(first) else { fail("restore of the first twin failed") }
    made.append(firstBack)
    leftovers.removeAll { $0.trashed.lastPathComponent == first.inTrash.lastPathComponent }
    guard firstBack.lastPathComponent == "\(tag)-twin 2.txt" else {
        fail("taken name came back as \(firstBack.lastPathComponent)")
    }
    print("  name taken, so the first came back as \(firstBack.lastPathComponent)")

    print("something else at the Trash path:")
    let swap = folder.appendingPathComponent("\(tag)-swap.txt")
    make(swap, folder: false)
    let swapped = throwAway(swap)
    let impostor = TrashedItem(original: swapped.original, inTrash: swapped.inTrash,
                               isFolder: false, fileID: swapped.fileID &+ 1)
    guard (try? TrashWatch.restore(impostor)) == nil else { fail("restored an item with another file ID") }
    print("  refused an item with another file ID")
    putBack(swapped, expect: swap)

    print("several at once:")
    let pair = [folder.appendingPathComponent("\(tag)-a.txt"), folder.appendingPathComponent("\(tag)-b.txt")]
    for url in pair { make(url, folder: false) }
    seen = []
    for url in pair {
        var landed: NSURL?
        do { try fm.trashItem(at: url, resultingItemURL: &landed) } catch { fail("could not trash: \(error)") }
        if let landed = landed as URL? { leftovers.append((landed, url)) }
    }
    wait(3) { seen.count >= 2 }
    guard seen.count == 2 else { fail("saw \(seen.count) of 2 things thrown at once") }
    for item in seen {
        guard let url = pair.first(where: { $0.resolvingSymlinksInPath().path == item.original.path }) else {
            fail("unexpected item \(item.name)")
        }
        putBack(item, expect: url)
    }

    print("moved to another folder, then thrown away from there:")
    let elsewhere = fm.temporaryDirectory.appendingPathComponent("ScreenCatRescueElsewhere-\(stamp)", isDirectory: true)
    try? fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
    let wanderer = folder.appendingPathComponent("\(tag)-moved.txt")
    make(wanderer, folder: false)
    let moved = elsewhere.appendingPathComponent(wanderer.lastPathComponent)
    do { try fm.moveItem(at: wanderer, to: moved) } catch { fail("could not move: \(error)") }
    made.append(elsewhere)
    made.append(moved)
    wait(0.8) { false }
    seen = []
    var movedLanded: NSURL?
    do { try fm.trashItem(at: moved, resultingItemURL: &movedLanded) } catch { fail("could not trash: \(error)") }
    if let landed = movedLanded as URL? { leftovers.append((landed, moved)) }
    wait(2) { !seen.isEmpty }
    guard seen.isEmpty else { fail("a move to another folder was taken for a throw from a watched one") }
    print("  not reported")

    print("from a folder inside a watched one:")
    let deeper = sub.appendingPathComponent("deeper", isDirectory: true)
    make(deeper, folder: true)
    let nested = deeper.appendingPathComponent("\(tag)-nested.txt")
    make(nested, folder: false)
    putBack(throwAway(nested), expect: nested)
    guard (try? String(contentsOf: nested, encoding: .utf8)) == "rescue me" else {
        fail("nested file came back changed")
    }

    print("from one watched folder to another:")
    let traveller = folder.appendingPathComponent("\(tag)-travel.txt")
    make(traveller, folder: false)
    let travelled = other.appendingPathComponent(traveller.lastPathComponent)
    seen = []
    do { try fm.moveItem(at: traveller, to: travelled) } catch { fail("could not move: \(error)") }
    made.append(travelled)
    wait(1.5) { !seen.isEmpty }
    guard seen.isEmpty else { fail("a move between watched folders was taken for a throw") }
    print("  not reported")
    putBack(throwAway(travelled), expect: travelled)

    print("no access to where it goes back:")
    let shutIn = folder.appendingPathComponent("\(tag) locked", isDirectory: true)
    make(shutIn, folder: true)
    let shut = shutIn.appendingPathComponent("\(tag)-shut.txt")
    make(shut, folder: false)
    let shutItem = throwAway(shut)
    locked.append(shutIn)
    try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: shutIn.path)
    do {
        _ = try TrashWatch.restore(shutItem)
        fail("put back into a folder it may not write to")
    } catch let miss as RescueMiss {
        guard miss.why.hasPrefix("no permission to write") else { fail("wrong reason: \(miss.why)") }
        print("  left in the Trash: \(miss.why)")
    } catch { fail("wrong error: \(error)") }
    guard fm.fileExists(atPath: shutItem.inTrash.path) else { fail("it is not in the Trash any more") }
    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shutIn.path)
    putBack(shutItem, expect: shut)

    if realFolders {
        let home = fm.homeDirectoryForCurrentUser
        for name in ["Documents", "Downloads"] {
            let place = home.appendingPathComponent(name, isDirectory: true)
            print("\(name):")
            let top = place.appendingPathComponent("\(tag).txt")
            make(top, folder: false)
            putBack(throwAway(top), expect: top)
            print("\(name), from a folder inside it:")
            let inner = place.appendingPathComponent("\(tag) sub", isDirectory: true)
            make(inner, folder: true)
            let innerFile = inner.appendingPathComponent("\(tag)-inner.txt")
            make(innerFile, folder: false)
            putBack(throwAway(innerFile), expect: innerFile)
        }
        print("Documents to the Desktop:")
        let mover = home.appendingPathComponent("Documents/\(tag)-to-desktop.txt")
        make(mover, folder: false)
        let onDesk = TrashWatch.desktop.appendingPathComponent(mover.lastPathComponent)
        seen = []
        do { try fm.moveItem(at: mover, to: onDesk) } catch { fail("could not move: \(error)") }
        made.append(onDesk)
        wait(1.5) { !seen.isEmpty }
        guard seen.isEmpty else { fail("a move from Documents to the Desktop was taken for a throw") }
        print("  not reported")
        let deskItem = throwAway(onDesk)
        guard deskItem.wasOnDesktop else { fail("not seen as on the Desktop") }
        putBack(deskItem, expect: onDesk)
    }

    cleanUp()
    for url in made where fm.fileExists(atPath: url.path) { fail("left behind \(url.path)") }
    print("PASS")
    exit(0)
}
