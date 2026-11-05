import AppKit
import CoreServices

// MARK: - Watching the Trash

/// Something you dragged from the Desktop to the Trash.
struct TrashedItem {
    /// Where it was before, on the Desktop.
    let original: URL
    /// Where Finder put it. Finder renames it if the name is already taken in
    /// the Trash, so this is not always the original name.
    let inTrash: URL
    let isFolder: Bool
    /// The file system's ID for it. A move keeps it, so it says whether what
    /// is at `inTrash` later is still this item.
    let fileID: UInt64

    var name: String { original.lastPathComponent }
}

/// Sees things go from the Desktop to the Trash.
///
/// `~/.Trash` cannot be listed without Full Disk Access, but FSEvents still
/// reports both ends of a move into it: the Desktop path that went away and
/// the Trash path that appeared. The two ends carry the same file ID, which
/// is how they are paired. Nothing here reads the files themselves.
final class TrashWatch {
    var onTrashed: (([TrashedItem]) -> Void)?

    let folder: URL
    let trash: URL
    private var stream: FSEventStreamRef?
    /// One end of a move seen, the other not yet: what left the Desktop and
    /// what landed in the Trash, by file ID, with the event's ID. The two
    /// ends of one move come one straight after the other.
    private var departed: [UInt64: (url: URL, isFolder: Bool, event: UInt64, at: Date)] = [:]
    private var arrived: [UInt64: (url: URL, event: UInt64, at: Date)] = [:]

    init(folder: URL = TrashWatch.desktop) {
        self.folder = folder.resolvingSymlinksInPath()
        trash = TrashWatch.userTrash.resolvingSymlinksInPath()
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

    var isRunning: Bool { stream != nil }

    func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
            guard let info else { return }
            let watch = Unmanaged<TrashWatch>.fromOpaque(info).takeUnretainedValue()
            let entries = unsafeBitCast(paths, to: NSArray.self) as? [[String: Any]] ?? []
            watch.handle(entries, flags: Array(UnsafeBufferPointer(start: flags, count: count)),
                         ids: Array(UnsafeBufferPointer(start: ids, count: count)))
        }
        let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagUseExtendedData
        guard let s = FSEventStreamCreate(nil, callback, &context, [folder.path, trash.path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2,
                                          FSEventStreamCreateFlags(flags)) else {
            ActivityLog.shared.cat("trash rescue: could not watch the Desktop")
            return
        }
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        stream = s
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
        departed = [:]
        arrived = [:]
    }

    private func handle(_ entries: [[String: Any]], flags: [FSEventStreamEventFlags],
                        ids: [FSEventStreamEventId]) {
        let renamed = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)
        let isDir = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)
        let fm = FileManager.default
        for ((entry, flag), event) in zip(zip(entries, flags), ids) where flag & renamed != 0 {
            guard let path = entry[kFSEventStreamEventExtendedDataPathKey] as? String,
                  let id = (entry[kFSEventStreamEventExtendedFileIDKey] as? NSNumber)?.uint64Value else { continue }
            let name = (path as NSString).lastPathComponent
            guard !name.hasPrefix(".") else { continue }
            // Resolved the same way as the watched folders, so /private/var
            // and /var compare equal.
            let parentURL = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent).resolvingSymlinksInPath()
            let parent = parentURL.path
            let url = parentURL.appendingPathComponent(name)
            // A rename event does not say which end it is. The end that still
            // exists is where the item went; the one that does not is where
            // it came from.
            let exists = fm.fileExists(atPath: path)
            if parent == folder.path, !exists {
                departed[id] = (url, flag & isDir != 0, event, Date())
            } else if parent == trash.path, exists {
                arrived[id] = (url, event, Date())
            }
        }

        var found: [TrashedItem] = []
        for (id, gone) in departed {
            // Same item and the very next events: one move, Desktop to Trash.
            // Moved to another folder first and thrown away from there is two
            // moves, far apart in the event stream, and is not ours.
            guard let landed = arrived[id],
                  max(landed.event, gone.event) - min(landed.event, gone.event) <= 3 else { continue }
            found.append(TrashedItem(original: gone.url, inTrash: landed.url, isFolder: gone.isFolder, fileID: id))
            departed[id] = nil
            arrived[id] = nil
        }
        // Moved somewhere else, or emptied straight away: forget it.
        let stale = Date().addingTimeInterval(-5)
        departed = departed.filter { $0.value.at > stale }
        arrived = arrived.filter { $0.value.at > stale }
        if !found.isEmpty { onTrashed?(found.sorted { $0.name < $1.name }) }
    }

    /// Moves an item back where it was. If something new has taken its name
    /// meanwhile, it comes back as "name 2", the way Finder numbers copies.
    /// Nil when it is gone from the Trash, something else is at its Trash
    /// path now, or the move fails.
    static func restore(_ item: TrashedItem) -> URL? {
        let fm = FileManager.default
        // Only the item that was seen going in. Put back and thrown again
        // from elsewhere, another item can land on the same Trash path.
        let id = (try? fm.attributesOfItem(atPath: item.inTrash.path)[.systemFileNumber] as? NSNumber)?.uint64Value
        guard id == item.fileID else { return nil }
        let folder = item.original.deletingLastPathComponent()
        let ext = item.original.pathExtension
        let stem = item.original.deletingPathExtension().lastPathComponent
        // A plain folder is numbered after its whole name. A file, or a
        // bundle such as a .pages or .app, before its extension.
        let numberWhole = ext.isEmpty || (item.isFolder && !NSWorkspace.shared.isFilePackage(atPath: item.inTrash.path))
        var target = item.original
        var n = 2
        while fm.fileExists(atPath: target.path) {
            let name = numberWhole ? "\(item.name) \(n)" : "\(stem) \(n).\(ext)"
            target = folder.appendingPathComponent(name)
            n += 1
        }
        do {
            try fm.moveItem(at: item.inTrash, to: target)
            return target
        } catch {
            ActivityLog.shared.cat("trash rescue: could not put back \(item.name): \(error.localizedDescription)")
            return nil
        }
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
        let size = CGFloat(dock?.double(forKey: "tilesize") ?? 0)
        let tile = size > 0 ? size : 48
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
            let count = CGFloat(iconCount(dock))
            let separators: CGFloat = showsRecents(dock) ? 2 : 1
            let width = count * tile + separators * tile * 0.35 + tile * 0.3
            let trash = frame.midX + width / 2 - tile * 0.15 - tile / 2
            return min(max(trash, visible.minX + tile), visible.maxX - tile * 0.5)
        }
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
/// back out, and tosses it up to the Desktop, where it really appears again.
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

    /// What the cat has in its mouth, or what is flying, for the overlay.
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
            // Out it pops, up from the Trash into the cat's mouth.
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
                // Still mid-stride with it in its mouth for the wind-up; it
                // only looks up once the thing is in the air.
                stage = .tossing
                timer = 0
                tossFrom = held(cat, scene.sheet).pos
                // Desktop icons line up from the top right by default.
                tossTo = CGPoint(x: rect.maxX - cat.size * 1.6, y: rect.maxY - cat.size * 1.8)
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

/// Throws scratch things away (a file, a folder, and a name the Trash
/// already holds), checks the watcher reports each one, puts them back, and
/// checks they are where they started. Cleans up after itself. Exits with 0
/// when every case passes.
func runRescueSelfTest(onDesktop: Bool) -> Never {
    let fm = FileManager.default
    let folder = onDesktop ? TrashWatch.desktop
        : fm.temporaryDirectory.appendingPathComponent("ScreenCatRescueTest", isDirectory: true)
    try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let stamp = Int(Date().timeIntervalSince1970)
    let watch = TrashWatch(folder: folder)
    var seen: [TrashedItem] = []
    watch.onTrashed = { seen += $0 }
    watch.start()
    /// Our own scratch things still in the Trash, to take back out and delete.
    var leftovers: [(trashed: URL, home: URL)] = []
    var made: [URL] = []

    func cleanUp() {
        for (trashed, home) in leftovers where fm.fileExists(atPath: trashed.path) {
            if !fm.fileExists(atPath: home.path) { try? fm.moveItem(at: trashed, to: home) }
            made.append(home)
        }
        for url in made { try? fm.removeItem(at: url) }
        if !onDesktop { try? fm.removeItem(at: folder) }
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
        seen = []
        var landed: NSURL?
        do { try fm.trashItem(at: url, resultingItemURL: &landed) } catch { fail("could not trash: \(error)") }
        guard let landed = landed as URL? else { fail("no Trash path for \(url.lastPathComponent)") }
        leftovers.append((landed, url))
        wait(3) { !seen.isEmpty }
        guard let item = seen.first else { fail("watcher saw nothing for \(url.lastPathComponent)") }
        guard item.original.path == url.resolvingSymlinksInPath().path else {
            fail("wrong original path \(item.original.path)")
        }
        guard item.inTrash.lastPathComponent == landed.lastPathComponent else {
            fail("wrong Trash path \(item.inTrash.path), expected \(landed.path)")
        }
        print("  saw \(item.name) go to the Trash as \(item.inTrash.lastPathComponent), folder \(item.isFolder)")
        return item
    }
    func putBack(_ item: TrashedItem, expect url: URL) {
        guard let back = TrashWatch.restore(item) else { fail("restore of \(item.name) failed") }
        guard back.path == url.resolvingSymlinksInPath().path, fm.fileExists(atPath: url.path) else {
            fail("\(item.name) came back at \(back.path)")
        }
        leftovers.removeAll { $0.trashed.lastPathComponent == item.inTrash.lastPathComponent }
        print("  put back at \(back.lastPathComponent)")
    }

    print("file:")
    let file = folder.appendingPathComponent("screencat-rescue-test-\(stamp).txt")
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
    let box = folder.appendingPathComponent("screencat-rescue-test-\(stamp) folder")
    make(box, folder: true)
    let boxItem = throwAway(box)
    guard boxItem.isFolder else { fail("a folder was reported as a file") }
    putBack(boxItem, expect: box)
    guard fm.fileExists(atPath: box.appendingPathComponent("note.txt").path) else { fail("folder came back empty") }

    print("same name already in the Trash:")
    let twin = folder.appendingPathComponent("screencat-rescue-test-\(stamp)-twin.txt")
    make(twin, folder: false)
    let first = throwAway(twin)
    make(twin, folder: false)
    let second = throwAway(twin)
    guard first.inTrash != second.inTrash else { fail("both throws reported the same Trash path") }
    putBack(second, expect: twin)
    // The first one is ours too; it comes back under the next free name.
    guard let firstBack = TrashWatch.restore(first) else { fail("restore of the first twin failed") }
    made.append(firstBack)
    leftovers.removeAll { $0.trashed.lastPathComponent == first.inTrash.lastPathComponent }
    guard firstBack.lastPathComponent == "screencat-rescue-test-\(stamp)-twin 2.txt" else {
        fail("taken name came back as \(firstBack.lastPathComponent)")
    }
    print("  name taken, so the first came back as \(firstBack.lastPathComponent)")

    print("something else at the Trash path:")
    let swap = folder.appendingPathComponent("screencat-rescue-test-\(stamp)-swap.txt")
    make(swap, folder: false)
    let swapped = throwAway(swap)
    let impostor = TrashedItem(original: swapped.original, inTrash: swapped.inTrash,
                               isFolder: false, fileID: swapped.fileID &+ 1)
    guard TrashWatch.restore(impostor) == nil else { fail("restored an item with another file ID") }
    print("  refused an item with another file ID")
    putBack(swapped, expect: swap)

    print("several at once:")
    let pair = [folder.appendingPathComponent("screencat-rescue-test-\(stamp)-a.txt"),
                folder.appendingPathComponent("screencat-rescue-test-\(stamp)-b.txt")]
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
    let wanderer = folder.appendingPathComponent("screencat-rescue-test-\(stamp)-moved.txt")
    make(wanderer, folder: false)
    let moved = elsewhere.appendingPathComponent(wanderer.lastPathComponent)
    do { try fm.moveItem(at: wanderer, to: moved) } catch { fail("could not move: \(error)") }
    made.append(moved)
    made.append(elsewhere)
    wait(0.8) { false }
    seen = []
    var movedLanded: NSURL?
    do { try fm.trashItem(at: moved, resultingItemURL: &movedLanded) } catch { fail("could not trash: \(error)") }
    if let landed = movedLanded as URL? { leftovers.append((landed, moved)) }
    wait(2) { !seen.isEmpty }
    guard seen.isEmpty else { fail("a move to another folder was taken for a throw from the Desktop") }
    print("  not reported")

    cleanUp()
    print("PASS")
    exit(0)
}
