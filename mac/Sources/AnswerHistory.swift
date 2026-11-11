import Foundation

/// The last few answers, newest first, for the LLM menu's Recent answers.
/// Kept in a file only you can read, in Application Support, so they are
/// still there after the cat restarts. Nothing leaves the Mac.
final class AnswerHistory {
    struct Entry: Codable {
        /// What was asked, cut short: the start of the text, or which picture.
        let asked: String
        let answer: String
        let at: Date
    }

    static let limit = 10
    private(set) var entries: [Entry] = []
    private let file: URL

    init(file: URL = AnswerHistory.defaultFile) {
        self.file = file
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Array(saved.prefix(Self.limit))
        }
    }

    static var defaultFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ScreenCat/answers.json")
    }

    func add(_ question: Question, answer: String) {
        entries.insert(Entry(asked: Self.asked(question), answer: answer, at: Date()), at: 0)
        entries = Array(entries.prefix(Self.limit))
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private static func asked(_ question: Question) -> String {
        switch question {
        case .text(let s), .followUp(let s):
            return oneLine(s, max: 80)
        case .image(_, let from):
            return from == "screenshot" ? "a screenshot" : "a copied image"
        }
    }

    /// Newlines folded to spaces, cut to `max` characters with an ellipsis.
    static func oneLine(_ s: String, max: Int) -> String {
        let flat = s.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count > max ? String(flat.prefix(max)) + "…" : flat
    }
}
