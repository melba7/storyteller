import Foundation
import LofiScoreCore

/// A timeline of narrator events and mood readings to replay through a ``MoodDirector``.
///
/// Scripts are JSON so they can be written by hand, recorded from a listening session,
/// or generated (``SyntheticBook``). Example:
///
/// ```json
/// {
///   "title": "Calm opening, then a fight",
///   "config": { "minimumDwell": 90 },
///   "duration": 600,
///   "events": [
///     { "t": 0, "playing": true },
///     { "t": 2, "index": 4, "trigger": "start", "reading": { "bucket": "calm", "confidence": 0.6 } },
///     { "t": 22, "index": 8, "reading": { "bucket": "tense", "confidence": 0.9, "valence": -0.6, "arousal": 0.9 },
///       "expect": "tense", "note": "sudden violence: a big jump" }
///   ]
/// }
/// ```
///
/// Each event may set any of these, applied in this order: `playing`, `seek`, `playhead`,
/// `reading` (with `index`, `chapter`, `sentence`, `trigger`), then `expect`, which checks
/// the director's current mood after the event.
public struct ReplayScript: Codable, Sendable, Hashable {
    public var title: String?
    /// Overrides for the director's defaults. Keys that are left out keep their defaults.
    public var config: DirectorConfig?
    /// Replay runs until at least this time, so held-back changes still fire at the end.
    public var duration: TimeInterval?
    public var events: [ReplayEvent]

    public init(title: String? = nil, config: DirectorConfig? = nil, duration: TimeInterval? = nil, events: [ReplayEvent]) {
        self.title = title
        self.config = config
        self.duration = duration
        self.events = events
    }

    public static func load(from url: URL) throws -> ReplayScript {
        try JSONDecoder().decode(ReplayScript.self, from: Data(contentsOf: url))
    }

    public func jsonData(pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }
}

public struct ReplayEvent: Codable, Sendable, Hashable {
    /// Seconds from the start of the replay.
    public var t: TimeInterval
    /// Narration started (true) or stopped (false).
    public var playing: Bool?
    /// The listener jumped to this sentence (-1 when the target is unknown).
    public var seek: Int?
    /// The sentence being narrated now.
    public var playhead: Int?
    public var reading: ReplayReading?
    /// Global sentence index of the reading. Defaults to 4 after the previous one.
    public var index: Int?
    public var chapter: Int?
    public var sentence: Int?
    /// Defaults to `cadence`.
    public var trigger: ReadingTrigger?
    /// The mood the music should be in after this event.
    public var expect: MoodBucket?
    public var note: String?

    public init(
        t: TimeInterval,
        playing: Bool? = nil,
        seek: Int? = nil,
        playhead: Int? = nil,
        reading: ReplayReading? = nil,
        index: Int? = nil,
        chapter: Int? = nil,
        sentence: Int? = nil,
        trigger: ReadingTrigger? = nil,
        expect: MoodBucket? = nil,
        note: String? = nil
    ) {
        self.t = t
        self.playing = playing
        self.seek = seek
        self.playhead = playhead
        self.reading = reading
        self.index = index
        self.chapter = chapter
        self.sentence = sentence
        self.trigger = trigger
        self.expect = expect
        self.note = note
    }
}

/// A mood reading in a replay. Valence and arousal default to the bucket's anchor,
/// confidence to 0.7, source to `live`.
public struct ReplayReading: Codable, Sendable, Hashable {
    public var bucket: MoodBucket
    public var valence: Double?
    public var arousal: Double?
    public var confidence: Double?
    public var scores: [MoodBucket: Double]?
    /// `track` for a reading from the book's mood track.
    public var source: ReadingSource?

    public init(
        bucket: MoodBucket,
        valence: Double? = nil,
        arousal: Double? = nil,
        confidence: Double? = nil,
        scores: [MoodBucket: Double]? = nil,
        source: ReadingSource? = nil
    ) {
        self.bucket = bucket
        self.valence = valence
        self.arousal = arousal
        self.confidence = confidence
        self.scores = scores
        self.source = source
    }

    public var moodReading: MoodReading {
        MoodReading(
            bucket: bucket,
            valence: valence ?? bucket.anchor.valence,
            arousal: arousal ?? bucket.anchor.arousal,
            confidence: confidence ?? 0.7,
            scores: scores,
            engineID: "replay"
        )
    }
}
