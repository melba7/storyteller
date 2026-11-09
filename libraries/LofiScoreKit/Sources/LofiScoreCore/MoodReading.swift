import Foundation

/// One mood judgement about a causal window of narrated text.
///
/// Engines produce these; the director smooths them into music decisions.
/// Every field describes text at or before the sentence being narrated.
public struct MoodReading: Sendable, Hashable, Codable {
    /// The single bucket the engine picked.
    public var bucket: MoodBucket
    /// -1 (unpleasant) ... 1 (pleasant).
    public var valence: Double
    /// 0 (still) ... 1 (urgent).
    public var arousal: Double
    /// 0 ... 1. How sure the engine is. Low-confidence readings should move the music less.
    public var confidence: Double
    /// Per-bucket probabilities summing to about 1, when the engine has them
    /// (the Create ML classifier does; a language model answering one line does not).
    public var scores: [MoodBucket: Double]?
    /// Which engine and version produced the reading, e.g. "fm.system/1".
    /// Part of the cache key, and shown in the debug overlay.
    public var engineID: String

    public init(
        bucket: MoodBucket,
        valence: Double,
        arousal: Double,
        confidence: Double,
        scores: [MoodBucket: Double]? = nil,
        engineID: String
    ) {
        self.bucket = bucket
        self.valence = Self.clamp(valence, -1, 1)
        self.arousal = Self.clamp(arousal, 0, 1)
        self.confidence = Self.clamp(confidence, 0, 1)
        self.scores = scores.map(Self.normalized)
        self.engineID = engineID
    }

    /// The reading's position in valence/arousal space.
    public var point: MoodPoint { MoodPoint(valence: valence, arousal: arousal) }

    /// A neutral reading used when nothing has been narrated yet or every engine failed.
    public static func neutral(engineID: String) -> MoodReading {
        let anchor = MoodBucket.neutral.anchor
        return MoodReading(
            bucket: .neutral,
            valence: anchor.valence,
            arousal: anchor.arousal,
            confidence: 0,
            engineID: engineID
        )
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        guard value.isFinite else { return low < 0 ? 0 : low }
        return min(high, max(low, value))
    }

    private static func normalized(_ scores: [MoodBucket: Double]) -> [MoodBucket: Double] {
        let cleaned = scores.mapValues { $0.isFinite ? max(0, $0) : 0 }
        let total = cleaned.values.reduce(0, +)
        guard total > 0 else { return cleaned }
        return cleaned.mapValues { $0 / total }
    }
}

/// Why a reading was taken. The director treats some triggers specially
/// (for example, a seek allows a faster crossfade).
public enum ReadingTrigger: String, Sendable, Hashable, Codable {
    /// The first reading after playback started or a book was opened.
    case start
    /// The regular cadence: enough sentences and enough time since the last reading.
    case cadence
    /// The listener jumped to another place in the book.
    case seek
    /// Playback moved into a new chapter and a few sentences have been narrated.
    case chapterStart
}

/// A reading tied to the place in the book where it was taken.
/// This is what the text side hands to the director.
public struct MoodObservation: Sendable, Hashable, Codable {
    public var reading: MoodReading
    /// Ordinal of the narrated chapter (0 = first chapter with narration).
    public var chapterOrdinal: Int
    /// Index of the sentence within that chapter (0-based).
    public var sentenceIndex: Int
    /// Index of the sentence across the whole book, counting only sentences at or before it.
    public var globalSentenceIndex: Int
    public var trigger: ReadingTrigger

    public init(
        reading: MoodReading,
        chapterOrdinal: Int,
        sentenceIndex: Int,
        globalSentenceIndex: Int,
        trigger: ReadingTrigger
    ) {
        self.reading = reading
        self.chapterOrdinal = chapterOrdinal
        self.sentenceIndex = sentenceIndex
        self.globalSentenceIndex = globalSentenceIndex
        self.trigger = trigger
    }
}
