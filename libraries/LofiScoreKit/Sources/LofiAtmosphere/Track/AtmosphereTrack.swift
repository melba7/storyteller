import Foundation
import LofiMood
import LofiText

/// A book's scenes, scored once ahead of time: where the story is and what it sounds
/// like, every couple of hundred narrated words and at every turn of scene.
///
/// Spoiler safety, the same rule as ``MoodTrack``: every entry was judged from
/// `SpoilerGuard.window(at:)` for its own sentence plus the ``PlaceMemory`` of the
/// entries before it, which were judged the same way. Playback only ever uses the
/// newest entry at or before the sentence being narrated. So the sounds at any moment
/// depend only on text the listener has already heard.
public struct AtmosphereTrack: Codable, Sendable, Hashable {
    public static let currentFormat = 1
    /// File names end in this, e.g. "Dracula.atmosphere.json".
    public static let fileSuffix = ".atmosphere.json"

    public struct Entry: Codable, Sendable, Hashable {
        public let chapterOrdinal: Int
        public let sentenceIndex: Int
        public let globalIndex: Int
        /// Digest of the entry's own sentence (``TextDigest``), so a track made for an
        /// older alignment of the book is never applied to a newer one.
        public let sentenceDigest: String
        public let scene: StoryScene
        /// What the scorer had worked out about the book's world so far ("Victorian
        /// London, autumn"), carried forward to later entries.
        public let world: String?
        /// Global index of the sentence where, by this entry's own answer, its scene
        /// began: its own sentence or an earlier one of its passage. Nil when the answer
        /// did not say. Only the builder reads it, to choose which sentence to score next
        /// (``SceneChangeFinder``); playback never does.
        public let sceneStart: Int?

        public init(position: SentencePosition, sentence: String, scene: StoryScene, world: String? = nil, sceneStart: Int? = nil) {
            chapterOrdinal = position.chapterOrdinal
            sentenceIndex = position.sentenceIndex
            globalIndex = position.globalIndex
            sentenceDigest = TextDigest.fnv1a64(sentence)
            self.scene = scene
            self.world = world
            self.sceneStart = sceneStart.map { min($0, position.globalIndex) }
        }

        init(copying entry: Entry, scene: StoryScene) {
            chapterOrdinal = entry.chapterOrdinal
            sentenceIndex = entry.sentenceIndex
            globalIndex = entry.globalIndex
            sentenceDigest = entry.sentenceDigest
            self.scene = scene
            world = entry.world
            sceneStart = entry.sceneStart
        }
    }

    /// A one-off sound (``OneShotSound``) on the sentence that says it happens.
    ///
    /// Spoiler safety: a cue is kept only when an answer judged from the text up to and
    /// including its own sentence (and places before it) put the sound on that sentence.
    public struct Cue: Codable, Sendable, Hashable {
        public let globalIndex: Int
        /// Digest of the sentence, like an entry's.
        public let sentenceDigest: String
        public let sound: OneShotSound
        /// Words of the sentence up to where the sound happens, and the sentence's words,
        /// so playback can place it inside the sentence.
        public let wordsBefore: Int
        public let words: Int
        /// The words that say it happens, for reports.
        public let quote: String?

        public init(position: SentencePosition, sentence: String, sound: OneShotSound, wordsBefore: Int, words: Int, quote: String? = nil) {
            globalIndex = position.globalIndex
            sentenceDigest = TextDigest.fnv1a64(sentence)
            self.sound = sound
            self.wordsBefore = max(0, wordsBefore)
            self.words = max(0, words)
            self.quote = quote
        }

        /// Where in the sentence the sound falls, from 0 (its start) to 1 (its end).
        public var fraction: Double {
            words > 1 ? min(1, Double(wordsBefore) / Double(words - 1)) : 0
        }
    }

    public var format: Int
    /// The engine that scored it, e.g. "claude.sonnet-5-5/a1".
    public var engineID: String
    /// Whatever the tool was given to name the book. The app matches tracks by sentence
    /// digests, not by this.
    public var bookID: String
    public var wordsBetweenEntries: Int
    /// Global index of each chapter's first narrated sentence, so playback can let the
    /// sounds settle at a chapter break. Says nothing about the story.
    public var chapterStarts: [Int]
    /// Sorted by position.
    public private(set) var entries: [Entry]
    /// The more specific sounds the entries use (``SoundVariant``), each with the entry
    /// that first asked for it, so the fetch script knows what to look for online.
    public private(set) var variants: [SoundVariant]
    /// One-off sounds, sorted by position, at most one per sentence.
    public private(set) var cues: [Cue]

    public init(
        engineID: String, bookID: String, wordsBetweenEntries: Int, chapterStarts: [Int] = [],
        entries: [Entry] = [], variants: [SoundVariant] = [], cues: [Cue] = []
    ) {
        format = Self.currentFormat
        self.engineID = engineID
        self.bookID = bookID
        self.wordsBetweenEntries = wordsBetweenEntries
        self.chapterStarts = chapterStarts.sorted()
        self.entries = []
        self.variants = []
        self.cues = []
        entries.forEach { insert($0) }
        variants.forEach { addVariant($0) }
        cues.forEach { insertCue($0) }
    }

    private enum CodingKeys: String, CodingKey {
        case format, engineID, bookID, wordsBetweenEntries, chapterStarts, entries, variants, cues
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(Int.self, forKey: .format)
        engineID = try c.decode(String.self, forKey: .engineID)
        bookID = try c.decode(String.self, forKey: .bookID)
        wordsBetweenEntries = try c.decode(Int.self, forKey: .wordsBetweenEntries)
        chapterStarts = try c.decode([Int].self, forKey: .chapterStarts)
        entries = try c.decode([Entry].self, forKey: .entries)
        // Tracks made before variants existed have none.
        variants = try c.decodeIfPresent([SoundVariant].self, forKey: .variants) ?? []
        // And before one-off sounds, none of those.
        cues = try c.decodeIfPresent([Cue].self, forKey: .cues) ?? []
    }

    /// Adds or replaces the cue on its sentence.
    public mutating func insertCue(_ cue: Cue) {
        var low = 0
        var high = cues.count
        while low < high {
            let mid = (low + high) / 2
            if cues[mid].globalIndex < cue.globalIndex { low = mid + 1 } else { high = mid }
        }
        if low < cues.count, cues[low].globalIndex == cue.globalIndex {
            cues[low] = cue
        } else {
            cues.insert(cue, at: low)
        }
    }

    /// The cue on exactly this sentence.
    public func cue(at globalIndex: Int) -> Cue? {
        var low = 0
        var high = cues.count
        while low < high {
            let mid = (low + high) / 2
            if cues[mid].globalIndex < globalIndex { low = mid + 1 } else { high = mid }
        }
        return low < cues.count && cues[low].globalIndex == globalIndex ? cues[low] : nil
    }

    /// Adds a variant, or moves a known one's first use earlier.
    public mutating func addVariant(_ variant: SoundVariant) {
        if let index = variants.firstIndex(where: { $0.id == variant.id }) {
            if let new = variant.firstIndex, new < (variants[index].firstIndex ?? Int.max) {
                variants[index].firstIndex = new
            }
            return
        }
        variants.append(variant)
        variants.sort { ($0.firstIndex ?? -1, $0.id) < ($1.firstIndex ?? -1, $1.id) }
    }

    /// The variants first asked for strictly before the sentence.
    public func variants(before globalIndex: Int) -> [SoundVariant] {
        variants.filter { ($0.firstIndex ?? 0) < globalIndex }
    }

    /// Adds or replaces the entry for its sentence.
    public mutating func insert(_ entry: Entry) {
        let index = firstIndex(notBefore: entry.globalIndex)
        if index < entries.count, entries[index].globalIndex == entry.globalIndex {
            entries[index] = entry
        } else {
            entries.insert(entry, at: index)
        }
    }

    public func contains(_ position: SentencePosition) -> Bool {
        let index = firstIndex(notBefore: position.globalIndex)
        return index < entries.count && entries[index].globalIndex == position.globalIndex
    }

    /// The newest entry at or before the sentence, never one after it.
    public func entry(atOrBefore globalIndex: Int) -> Entry? {
        let index = firstIndex(notBefore: globalIndex)
        if index < entries.count, entries[index].globalIndex == globalIndex { return entries[index] }
        return index > 0 ? entries[index - 1] : nil
    }

    /// Entries strictly before the sentence, oldest first.
    public func entries(before globalIndex: Int) -> ArraySlice<Entry> {
        entries[..<firstIndex(notBefore: globalIndex)]
    }

    /// The chapter break at or before the sentence (the global index of that chapter's
    /// first sentence), if any.
    public func chapterStart(atOrBefore globalIndex: Int) -> Int? {
        chapterStarts.last { $0 <= globalIndex }
    }

    /// Renames place ids everywhere (used when two ids turn out to be the same place).
    public mutating func renamePlaces(_ mapping: [String: String]) {
        guard !mapping.isEmpty else { return }
        entries = entries.map { entry in
            guard let id = entry.scene.placeID, let renamed = mapping[id] else { return entry }
            var scene = entry.scene
            scene.placeID = renamed
            return Entry(copying: entry, scene: scene)
        }
    }

    private func firstIndex(notBefore globalIndex: Int) -> Int {
        var low = 0
        var high = entries.count
        while low < high {
            let mid = (low + high) / 2
            if entries[mid].globalIndex < globalIndex { low = mid + 1 } else { high = mid }
        }
        return low
    }

    // MARK: - Files

    public static func load(from url: URL) throws -> AtmosphereTrack {
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

    public static func decode(_ data: Data) throws -> AtmosphereTrack {
        let track = try JSONDecoder().decode(AtmosphereTrack.self, from: data)
        guard track.format == currentFormat else {
            throw AtmosphereTrackError.unsupportedFormat(track.format)
        }
        // Re-sort in case the file was edited by hand.
        return AtmosphereTrack(
            engineID: track.engineID, bookID: track.bookID, wordsBetweenEntries: track.wordsBetweenEntries,
            chapterStarts: track.chapterStarts, entries: track.entries, variants: track.variants, cues: track.cues
        )
    }
}

public enum AtmosphereTrackError: Error, Sendable, Equatable {
    case unsupportedFormat(Int)
}

/// A track that grows while it is being built; readers see whatever is there.
public final class AtmosphereTrackStore: @unchecked Sendable {
    private let lock = NSLock()
    private var track: AtmosphereTrack

    public init(_ track: AtmosphereTrack) {
        self.track = track
    }

    public var snapshot: AtmosphereTrack {
        lock.lock()
        defer { lock.unlock() }
        return track
    }

    public var count: Int { snapshot.entries.count }

    public func insert(_ entry: AtmosphereTrack.Entry) {
        lock.lock()
        track.insert(entry)
        lock.unlock()
    }

    public func contains(_ position: SentencePosition) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return track.contains(position)
    }

    public func update(_ body: (inout AtmosphereTrack) -> Void) {
        lock.lock()
        body(&track)
        lock.unlock()
    }
}
