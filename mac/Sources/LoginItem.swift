import Foundation

/// Start at login, from the menu. Writes the same LaunchAgent as
/// `install-login-item.sh`, so either one can undo the other.
///
/// Only the file is written or removed; launchctl is never called. Loading the
/// agent now would start a second copy (it refuses, but still), and booting it
/// out would kill this very process if launchd started it at login. launchd
/// reads the folder at the next login, which is all that is wanted.
enum LoginItem {
    static let label = "local.screencat"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func setEnabled(_ on: Bool) {
        guard on else {
            try? FileManager.default.removeItem(at: plistURL)
            return
        }
        guard let exe = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe],
            "RunAtLoad": true,
            "KeepAlive": false,
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                             format: .xml, options: 0) else { return }
        try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: plistURL)
    }
}
