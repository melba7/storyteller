import Foundation
import LofiScoreCore

/// Every threshold the director uses, in one place, so the listening test can tune them.
///
/// The defaults follow the plan: evidence smoothed over about 60 seconds of listening,
/// a new mood must win two readings in a row (or one very confident reading after a
/// big jump), and the music keeps a mood for at least 90 seconds, except after a seek
/// or at a chapter start.
///
/// Decoding accepts any subset of the keys and keeps the default for the rest, so a
/// replay script can override one or two values.
public struct DirectorConfig: Sendable, Hashable {
    /// How quickly old evidence fades, in seconds of listening. Paused time does not count.
    public var evidenceTimeConstant: TimeInterval = 60

    /// For readings without per-bucket scores: how much the engine's own bucket label
    /// counts (0...1). The rest comes from how close the reading's valence and arousal
    /// sit to each bucket's anchor.
    public var labelWeight: Double = 0.6

    /// Width of that valence/arousal match, in ``MoodPoint/distance(to:)`` units.
    public var anchorSpread: Double = 0.35

    /// The least a reading counts for, however low its confidence.
    public var confidenceFloor: Double = 0.05

    /// Standing evidence for the neutral bucket (Calm). Weak or mixed text settles there.
    public var neutralPrior: Double = 0.25

    /// A challenger must lead the current mood by this share of all evidence to count as winning.
    public var switchMargin: Double = 0.1

    /// Readings in a row a challenger must win before the music changes.
    public var confirmationReadings: Int = 2

    /// A single reading at least this confident...
    public var bigJumpConfidence: Double = 0.8

    /// ...and at least this far from the current mood's anchor changes the music at once.
    public var bigJumpDistance: Double = 1.0

    /// The least time the music keeps a mood before a regular change, in wall-clock seconds.
    public var minimumDwell: TimeInterval = 90

    /// The least time the music keeps a mood before a big-jump change.
    public var bigJumpMinimumDwell: TimeInterval = 30

    /// Share of the evidence carried over at a chapter start. The rest is dropped,
    /// so a new chapter can set its own mood quickly.
    public var chapterCarryOver: Double = 0.3

    /// The first reading after a seek or chapter start below this confidence only sets
    /// a provisional mood: the dwell rule does not lock it in.
    public var provisionalConfidence: Double = 0.35

    /// After a seek, readings that are not the seek's own are ignored for at most this long.
    public var seekReadingTimeout: TimeInterval = 30

    /// A `.start` reading within this many sentences after the last reading is a resume
    /// (handled like a regular reading); anything else is a jump (handled like a seek).
    public var resumeContinuityWindow: Int = 40

    public init() {}
}

extension DirectorConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case evidenceTimeConstant, labelWeight, anchorSpread, confidenceFloor, neutralPrior
        case switchMargin, confirmationReadings, bigJumpConfidence, bigJumpDistance
        case minimumDwell, bigJumpMinimumDwell, chapterCarryOver, provisionalConfidence
        case seekReadingTimeout, resumeContinuityWindow
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
        try read(.labelWeight, into: &labelWeight)
        try read(.anchorSpread, into: &anchorSpread)
        try read(.confidenceFloor, into: &confidenceFloor)
        try read(.neutralPrior, into: &neutralPrior)
        try read(.switchMargin, into: &switchMargin)
        try read(.confirmationReadings, into: &confirmationReadings)
        try read(.bigJumpConfidence, into: &bigJumpConfidence)
        try read(.bigJumpDistance, into: &bigJumpDistance)
        try read(.minimumDwell, into: &minimumDwell)
        try read(.bigJumpMinimumDwell, into: &bigJumpMinimumDwell)
        try read(.chapterCarryOver, into: &chapterCarryOver)
        try read(.provisionalConfidence, into: &provisionalConfidence)
        try read(.seekReadingTimeout, into: &seekReadingTimeout)
        try read(.resumeContinuityWindow, into: &resumeContinuityWindow)
    }
}
