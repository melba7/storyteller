import Foundation
import LofiScoreCore

/// The director's instruction to change the music to another mood.
public struct MoodDecision: Sendable, Hashable, Codable {
    public enum Reason: String, Sendable, Hashable, Codable {
        /// The first reading after a book was opened.
        case firstReading
        /// The first reading after the listener jumped elsewhere in the book.
        case seek
        /// The first reading a few sentences into a new chapter.
        case chapterStart
        /// A new mood won enough readings in a row.
        case confirmed
        /// A confirmed change that had to wait for the minimum dwell.
        case dwellElapsed
        /// One very confident reading far from the current mood, such as sudden violence.
        case bigJump
        /// Narration reached the sentence where the book's mood track turns to a new mood.
        case trackTurn
    }

    /// How fast the music should get there.
    public enum Transition: String, Sendable, Hashable, Codable {
        /// A regular mood change: a long crossfade (about 8 seconds).
        case gentle
        /// After a seek or a sudden jump: a short crossfade (about 3.5 seconds).
        case quick
    }

    public var bucket: MoodBucket
    public var previous: MoodBucket
    public var reason: Reason
    public var transition: Transition
    /// Clock time of the decision.
    public var time: TimeInterval
    /// The sentence whose reading led to the decision.
    public var globalSentenceIndex: Int?
    /// True when the deciding evidence was weak. The dwell rule does not lock in a provisional mood.
    public var provisional: Bool
    /// True when the dwell rule did not apply to this change (after a seek, a chapter start
    /// or a provisional mood).
    public var dwellWaived: Bool

    public init(
        bucket: MoodBucket,
        previous: MoodBucket,
        reason: Reason,
        transition: Transition,
        time: TimeInterval,
        globalSentenceIndex: Int?,
        provisional: Bool,
        dwellWaived: Bool = false
    ) {
        self.bucket = bucket
        self.previous = previous
        self.reason = reason
        self.transition = transition
        self.time = time
        self.globalSentenceIndex = globalSentenceIndex
        self.provisional = provisional
        self.dwellWaived = dwellWaived
    }
}

extension MoodDecision: CustomStringConvertible {
    public var description: String {
        let at = String(format: "%7.1fs", time)
        let index = globalSentenceIndex.map { " @\($0)" } ?? ""
        let flag = provisional ? " (provisional)" : ""
        return "\(at) \(previous) -> \(bucket) [\(reason.rawValue), \(transition.rawValue)]\(index)\(flag)"
    }
}
