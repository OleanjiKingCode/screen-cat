import Foundation

/// One cat at a time.
///
/// `open ScreenCat.app` on an already-running bundle just activates it, but
/// running the executable directly, or a login item plus a manual launch, would
/// happily start a second process and put a second cat on the screen. An
/// advisory file lock stops that. The kernel drops the lock when the process
/// exits, including on a crash, so there is no stale-lock case to clean up.
enum SingleInstance {
    private static var lockDescriptor: Int32 = -1

    static var lockURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".screencat.lock")
    }

    /// True if this process now owns the lock, false if another one already does.
    static func claim() -> Bool {
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        // If the lock file cannot be opened at all, do not block startup over it.
        guard fd >= 0 else { return true }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        // Held for the lifetime of the process; never closed deliberately.
        lockDescriptor = fd
        return true
    }
}
