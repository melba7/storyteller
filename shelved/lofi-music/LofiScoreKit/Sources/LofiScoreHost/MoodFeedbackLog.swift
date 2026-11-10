import Foundation

/// The "Wrong mood" button's log, for the listening test: one JSON line per tap in
/// `mood-feedback.jsonl`, and per-book counts of the music's mood changes and of the ones
/// marked wrong in `mood-feedback-counts.json` (the plan's bar: under 1 change in 5 marked
/// wrong). Nothing here leaves the phone unless the listener shares it from Settings.
///
/// Thread safety: every method may be called from any thread.
public final class MoodFeedbackLog: @unchecked Sendable {
    /// One tap of "Wrong mood", or one mood picked from the panel.
    public struct Entry: Codable, Sendable, Hashable {
        public var time: Date
        public var bookID: String
        /// The sentence being narrated, across the whole book.
        public var sentence: Int?
        /// The mood that was playing, which the listener said was wrong.
        public var rejected: String
        /// The mood the music moved to.
        public var chosen: String
        /// "guess" (the engine's next guess) or "picked" (the listener chose it).
        public var how: String
        /// True when this replaced a guess made moments before: the same miss, not a new one.
        public var correction: Bool
        /// "track" (the book's mood track) or "live" (an engine on the phone).
        public var readingSource: String?
        /// The live engine's id, for "live".
        public var engine: String?
        /// The track that was playing.
        public var track: String?

        public init(
            time: Date = Date(),
            bookID: String,
            sentence: Int?,
            rejected: String,
            chosen: String,
            how: String,
            correction: Bool,
            readingSource: String?,
            engine: String?,
            track: String?
        ) {
            self.time = time
            self.bookID = bookID
            self.sentence = sentence
            self.rejected = rejected
            self.chosen = chosen
            self.how = how
            self.correction = correction
            self.readingSource = readingSource
            self.engine = engine
            self.track = track
        }
    }

    /// Mood changes the music made in a book, and how many of them the listener marked wrong.
    public struct Counts: Codable, Sendable, Hashable {
        public var changes: Int = 0
        public var wrong: Int = 0

        public init(changes: Int = 0, wrong: Int = 0) {
            self.changes = changes
            self.wrong = wrong
        }
    }

    public static let logName = "mood-feedback.jsonl"
    public static let countsName = "mood-feedback-counts.json"

    public let folder: URL
    private let lock = NSLock()
    private var counts: [String: Counts]?

    public init(folder: URL) {
        self.folder = folder
    }

    private var logURL: URL { folder.appendingPathComponent(Self.logName) }
    private var countsURL: URL { folder.appendingPathComponent(Self.countsName) }

    /// The music changed mood in `bookID` (on its own, not at the listener's request).
    public func noteChange(bookID: String) {
        lock.withLock {
            var all = loadedCounts()
            all[bookID, default: Counts()].changes += 1
            save(all)
        }
    }

    /// Records a tap. A correction is logged but does not count as another miss.
    public func record(_ entry: Entry) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(entry)
        line.append(0x0A)
        try lock.withLock {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: logURL, options: .atomic)
            }
            guard !entry.correction else { return }
            var all = loadedCounts()
            all[entry.bookID, default: Counts()].wrong += 1
            save(all)
        }
    }

    /// The counts for `bookID`, or all books together with nil.
    public func counts(bookID: String?) -> Counts {
        lock.withLock {
            let all = loadedCounts()
            if let bookID { return all[bookID] ?? Counts() }
            return all.values.reduce(into: Counts()) {
                $0.changes += $1.changes
                $0.wrong += $1.wrong
            }
        }
    }

    /// The whole log as text to share: a line of totals, then the JSON lines. Nil when
    /// nothing was marked yet.
    public func exportText() -> String? {
        lock.withLock {
            guard let log = try? String(contentsOf: logURL, encoding: .utf8), !log.isEmpty else { return nil }
            let all = loadedCounts()
            var totals = Counts()
            for value in all.values {
                totals.changes += value.changes
                totals.wrong += value.wrong
            }
            var text = "# Storyteller Lofi wrong-mood log: \(totals.wrong) of \(totals.changes) mood changes marked wrong"
            for (book, value) in all.sorted(by: { $0.key < $1.key }) {
                text += "\n# book \(book): \(value.wrong) of \(value.changes)"
            }
            return text + "\n" + log
        }
    }

    // MARK: - Files (under the lock)

    private func loadedCounts() -> [String: Counts] {
        if let counts { return counts }
        let loaded = (try? Data(contentsOf: countsURL)).flatMap { try? JSONDecoder().decode([String: Counts].self, from: $0) } ?? [:]
        counts = loaded
        return loaded
    }

    private func save(_ all: [String: Counts]) {
        counts = all
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(all) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: countsURL, options: .atomic)
    }
}
