import Foundation
import LofiScoreCore

/// Every threshold the director uses, in one place, so the listening test can tune them.
///
/// There are two paths to a mood change:
///
/// - **A book's mood track** (readings with ``ReadingSource/track``): the book was scored
///   ahead of time and each turn of mood was pinned to the sentence where the text first
///   reads as the new mood. When narration reaches that sentence the music follows within
///   seconds, as long as the last change was at least ``trackMinimumDwell`` ago.
/// - **A live engine** (everything else): evidence smoothed over about a minute of
///   listening, a new mood must lead for two readings and ``confirmationTime`` seconds (or
///   be named by very confident readings far from the current mood: a big jump), and the
///   music keeps a mood for at least ``minimumDwell``, except after a seek or at a chapter
///   start. Readings are weighted by the time between them, so an engine that reads every
///   sentence is no twitchier than one that reads every 20 seconds.
///
/// Decoding accepts any subset of the keys and keeps the default for the rest, so a
/// replay script can override one or two values.
public struct DirectorConfig: Sendable, Hashable {
    /// How quickly old evidence fades, in seconds of listening. Paused time does not count.
    public var evidenceTimeConstant: TimeInterval = 60

    /// A reading counts in full when at least this many seconds passed since the previous
    /// one, and proportionally less when readings come faster. This keeps the smoothing the
    /// same whether the text side reads every sentence or every 20 seconds. 0 turns it off.
    public var evidenceReferenceInterval: TimeInterval = 20

    /// For readings without per-bucket scores: how much the engine's own bucket label
    /// counts (0...1). The rest comes from how close the reading's valence and arousal
    /// sit to each bucket's anchor.
    public var labelWeight: Double = 0.7

    /// Width of that valence/arousal match, in ``MoodPoint/distance(to:)`` units.
    public var anchorSpread: Double = 0.3

    /// The least a reading counts for, however low its confidence.
    public var confidenceFloor: Double = 0.05

    /// Standing evidence for the neutral bucket (Calm). Weak or mixed text settles there.
    public var neutralPrior: Double = 0.25

    /// A challenger must lead the current mood by this share of all evidence to count as winning.
    public var switchMargin: Double = 0.1

    /// Readings in a row a challenger must win before the music changes.
    public var confirmationReadings: Int = 2

    /// ...and the challenger must have led for at least this many seconds, so a run of
    /// near-identical readings taken a sentence apart is not mistaken for a lasting change.
    /// 20 seconds is what two readings in a row meant at the 20-second cadence.
    public var confirmationTime: TimeInterval = 20

    /// A single reading at least this confident...
    public var bigJumpConfidence: Double = 0.8

    /// ...and at least this far from the current mood's anchor changes the music at once.
    public var bigJumpDistance: Double = 1.0

    /// How much live reading a big jump needs: the summed weights (see
    /// ``evidenceReferenceInterval``) of the confident, far readings in a row that name it.
    /// At the slow cadence one reading weighs 1, so one is enough, as before. Read every
    /// sentence, it takes two or three in a row (about 8 seconds of text), so a single odd
    /// sentence cannot throw the music.
    public var bigJumpWeight: Double = 0.4

    /// The least time the music keeps a mood before a regular change, in wall-clock seconds.
    public var minimumDwell: TimeInterval = 60

    /// The least time the music keeps a mood before a big-jump change.
    public var bigJumpMinimumDwell: TimeInterval = 30

    /// Share of the evidence carried over at a chapter start. The rest is dropped,
    /// so a new chapter can set its own mood quickly.
    public var chapterCarryOver: Double = 0.2

    /// The first reading after a seek or chapter start below this confidence only sets
    /// a provisional mood: the dwell rule does not lock it in.
    public var provisionalConfidence: Double = 0.35

    /// After a seek, readings that are not the seek's own are ignored for at most this long.
    public var seekReadingTimeout: TimeInterval = 30

    /// A `.start` reading within this many sentences after the last reading is a resume
    /// (handled like a regular reading); anything else is a jump (handled like a seek).
    public var resumeContinuityWindow: Int = 40

    // MARK: Mood-track readings

    /// Track readings in a row that must name the new mood before the music follows.
    /// 1 follows at the first sentence the track marks as the new mood.
    public var trackConfirmationReadings: Int = 1

    /// The least time the music keeps a mood before a track turn changes it. A turn that
    /// comes sooner waits for this, then goes ahead if the track still says so.
    public var trackMinimumDwell: TimeInterval = 45

    /// Track readings less sure than this are treated like live readings (smoothed).
    public var trackMinimumConfidence: Double = 0.3

    public init() {}
}

extension DirectorConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case evidenceTimeConstant, evidenceReferenceInterval, labelWeight, anchorSpread, confidenceFloor, neutralPrior
        case switchMargin, confirmationReadings, confirmationTime, bigJumpConfidence, bigJumpDistance, bigJumpWeight
        case minimumDwell, bigJumpMinimumDwell, chapterCarryOver, provisionalConfidence
        case seekReadingTimeout, resumeContinuityWindow
        case trackConfirmationReadings, trackMinimumDwell, trackMinimumConfidence
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func read<Value: Decodable>(_ key: CodingKeys, into value: inout Value) throws {
            if let decoded = try container.decodeIfPresent(Value.self, forKey: key) {
                value = decoded
            }
        }
        try read(.evidenceTimeConstant, into: &evidenceTimeConstant)
        try read(.evidenceReferenceInterval, into: &evidenceReferenceInterval)
        try read(.labelWeight, into: &labelWeight)
        try read(.anchorSpread, into: &anchorSpread)
        try read(.confidenceFloor, into: &confidenceFloor)
        try read(.neutralPrior, into: &neutralPrior)
        try read(.switchMargin, into: &switchMargin)
        try read(.confirmationReadings, into: &confirmationReadings)
        try read(.confirmationTime, into: &confirmationTime)
        try read(.bigJumpConfidence, into: &bigJumpConfidence)
        try read(.bigJumpDistance, into: &bigJumpDistance)
        try read(.bigJumpWeight, into: &bigJumpWeight)
        try read(.minimumDwell, into: &minimumDwell)
        try read(.bigJumpMinimumDwell, into: &bigJumpMinimumDwell)
        try read(.chapterCarryOver, into: &chapterCarryOver)
        try read(.provisionalConfidence, into: &provisionalConfidence)
        try read(.seekReadingTimeout, into: &seekReadingTimeout)
        try read(.resumeContinuityWindow, into: &resumeContinuityWindow)
        try read(.trackConfirmationReadings, into: &trackConfirmationReadings)
        try read(.trackMinimumDwell, into: &trackMinimumDwell)
        try read(.trackMinimumConfidence, into: &trackMinimumConfidence)
    }
}
