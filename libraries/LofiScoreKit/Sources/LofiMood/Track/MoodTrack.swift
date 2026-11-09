import Foundation
import LofiScoreCore
import LofiText

/// A book's moods, scored once ahead of time: one reading every few hundred
/// narrated words, each judged only from the text up to its own sentence.
///
/// Spoiler safety: every entry was made from `SpoilerGuard.window(at:)` for the
/// entry's own position, and playback only ever looks up the newest entry at or
/// before the sentence being narrated. So the music at any moment depends only
/// on text that has already been narrated, exactly as with a live engine. The
/// file does hold moods for later chapters, but nothing reads them early.
public struct MoodTrack: Codable, Sendable, Hashable {
    public static let currentFormat = 1

    public struct Entry: Codable, Sendable, Hashable {
        public let chapterOrdinal: Int
        public let sentenceIndex: Int
        public let globalIndex: Int
        /// Digest of the entry's own sentence, so a track made for an older
        /// alignment of the book is never applied to a newer one.
        public let sentenceDigest: String
        public let reading: MoodReading

        public init(position: SentencePosition, sentence: String, reading: MoodReading) {
            self.chapterOrdinal = position.chapterOrdinal
            self.sentenceIndex = position.sentenceIndex
            self.globalIndex = position.globalIndex
            self.sentenceDigest = TextDigest.fnv1a64(sentence)
            self.reading = reading
        }

        var key: SentenceKey { SentenceKey(chapterOrdinal: chapterOrdinal, sentenceIndex: sentenceIndex) }
    }

    public var format: Int
    /// The engine that scored it, e.g. "claude.opus-5-5/p1".
    public var engineID: String
    /// Whatever the app uses to recognise the book (Storyteller's book uuid).
    public var bookID: String
    /// Narrated words between entries the builder aimed for.
    public var wordsBetweenEntries: Int
    /// Sorted by position.
    public private(set) var entries: [Entry]

    public init(engineID: String, bookID: String, wordsBetweenEntries: Int, entries: [Entry] = []) {
        self.format = Self.currentFormat
        self.engineID = engineID
        self.bookID = bookID
        self.wordsBetweenEntries = wordsBetweenEntries
        self.entries = []
        entries.forEach { insert($0) }
    }

    /// Adds or replaces the entry for its sentence.
    public mutating func insert(_ entry: Entry) {
        let index = firstIndex(notBefore: entry.key)
        if index < entries.count, entries[index].key == entry.key {
            entries[index] = entry
        } else {
            entries.insert(entry, at: index)
        }
    }

    public func contains(_ position: SentencePosition) -> Bool {
        let key = SentenceKey(position)
        let index = firstIndex(notBefore: key)
        return index < entries.count && entries[index].key == key
    }

    /// The newest entry at or before `position`, never one after it.
    public func entry(atOrBefore position: SentencePosition) -> Entry? {
        let key = SentenceKey(position)
        let index = firstIndex(notBefore: key)
        if index < entries.count, entries[index].key == key { return entries[index] }
        return index > 0 ? entries[index - 1] : nil
    }

    /// Index of the first entry whose position is not before `key`.
    private func firstIndex(notBefore key: SentenceKey) -> Int {
        var low = 0
        var high = entries.count
        while low < high {
            let mid = (low + high) / 2
            if entries[mid].key < key { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Reads a track saved with `save(to:)`.
    public static func load(from url: URL) throws -> MoodTrack {
        try decode(Data(contentsOf: url))
    }

    /// Writes the track atomically, so a crash mid-save keeps the old file.
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded().write(to: url, options: .atomic)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> MoodTrack {
        let track = try JSONDecoder().decode(MoodTrack.self, from: data)
        guard track.format == currentFormat else {
            throw MoodTrackError.unsupportedFormat(track.format)
        }
        // Re-sort in case the file was edited by hand.
        return MoodTrack(engineID: track.engineID, bookID: track.bookID, wordsBetweenEntries: track.wordsBetweenEntries, entries: track.entries)
    }
}

public enum MoodTrackError: Error, Sendable, Equatable {
    case unsupportedFormat(Int)
}

struct SentenceKey: Hashable, Comparable {
    let chapterOrdinal: Int
    let sentenceIndex: Int

    init(chapterOrdinal: Int, sentenceIndex: Int) {
        self.chapterOrdinal = chapterOrdinal
        self.sentenceIndex = sentenceIndex
    }

    init(_ position: SentencePosition) {
        self.init(chapterOrdinal: position.chapterOrdinal, sentenceIndex: position.sentenceIndex)
    }

    static func < (lhs: SentenceKey, rhs: SentenceKey) -> Bool {
        (lhs.chapterOrdinal, lhs.sentenceIndex) < (rhs.chapterOrdinal, rhs.sentenceIndex)
    }
}

/// A short, stable digest of a sentence (64-bit FNV-1a over its normalized
/// words). Not cryptographic; it only has to notice that the text changed.
public enum TextDigest {
    public static func fnv1a64(_ text: String) -> String {
        let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}

/// A mood track that can grow while the book plays: the builder adds entries
/// as Claude answers, and `TrackedMoodEngine` reads whatever is there.
public final class MoodTrackStore: @unchecked Sendable {
    private let lock = NSLock()
    private var track: MoodTrack

    public init(_ track: MoodTrack) {
        self.track = track
    }

    public var snapshot: MoodTrack {
        lock.lock()
        defer { lock.unlock() }
        return track
    }

    public var engineID: String { snapshot.engineID }
    public var count: Int { snapshot.entries.count }

    public func insert(_ entry: MoodTrack.Entry) {
        lock.lock()
        track.insert(entry)
        lock.unlock()
    }

    public func contains(_ position: SentencePosition) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return track.contains(position)
    }

    public func entry(atOrBefore position: SentencePosition) -> MoodTrack.Entry? {
        lock.lock()
        defer { lock.unlock() }
        return track.entry(atOrBefore: position)
    }
}
