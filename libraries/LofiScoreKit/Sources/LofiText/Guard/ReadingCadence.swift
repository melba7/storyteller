import Foundation
import LofiScoreCore

/// Decides when to take a new mood reading as narration moves forward.
///
/// From the plan: a new reading every 4 sentences or 20 seconds, whichever
/// comes later, plus one right after a seek, and one a few sentences into each
/// new chapter. Pure logic with the time passed in, so tests can replay a whole
/// book quickly.
///
/// Guarantees relied on by the director:
/// - Between a chapter change and that chapter's `.chapterStart` reading there
///   are no `.cadence` readings.
/// - Within one listening stretch `globalIndex` never decreases. Only `.start`
///   and `.seek` begin a new stretch, and those may jump backwards.
/// - A trigger is only ever returned for the sentence that has just started, so
///   a reading (and any crossfade it causes) starts after that sentence starts.
public struct ReadingCadence: Sendable {
    public struct Configuration: Sendable, Hashable {
        /// Minimum sentences between regular readings.
        public var sentencesBetweenReadings: Int
        /// Minimum seconds between regular readings.
        public var secondsBetweenReadings: Double
        /// The first reading of a new chapter happens on this sentence number
        /// (1-based), so the window holds a little of the new chapter.
        public var sentencesIntoNewChapter: Int
        /// A forward jump of more than this many sentences counts as a seek.
        public var maxContinuousStep: Int

        public init(
            sentencesBetweenReadings: Int = 4,
            secondsBetweenReadings: Double = 20,
            sentencesIntoNewChapter: Int = 3,
            maxContinuousStep: Int = 2
        ) {
            self.sentencesBetweenReadings = max(1, sentencesBetweenReadings)
            self.secondsBetweenReadings = max(0, secondsBetweenReadings)
            self.sentencesIntoNewChapter = max(1, sentencesIntoNewChapter)
            self.maxContinuousStep = max(1, maxContinuousStep)
        }

        /// The plan's original cadence: every 4 sentences or 20 seconds,
        /// whichever is later. Right for engines that take a second or more
        /// per reading (Apple's on-device model).
        public static let `default` = Configuration()

        /// A reading on every sentence. For engines that answer in
        /// milliseconds (a mood track lookup, the Fast classifier), so a
        /// mood change reaches the director as soon as its sentence starts.
        /// The chapter-start rule is unchanged.
        public static let everySentence = Configuration(sentencesBetweenReadings: 1, secondsBetweenReadings: 0)
    }

    public let configuration: Configuration

    private var lastSeen: SentencePosition?
    private var lastReading: (position: SentencePosition, time: Double)?
    /// The chapter whose first reading is still to come, if any.
    private var awaitingChapter: Int?

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    /// Call whenever the player reports a clip change. Returns a trigger when a
    /// reading should be taken now, for exactly this position.
    ///
    /// - Parameters:
    ///   - position: the sentence that just started.
    ///   - time: a monotonic clock in seconds (wall-clock, not media time, so
    ///     the playback rate does not change the cadence).
    ///   - seek: true when the player knows the listener jumped. Jumps are also
    ///     detected from the positions themselves.
    public mutating func observe(_ position: SentencePosition, at time: Double, seek: Bool = false) -> ReadingTrigger? {
        defer { lastSeen = position }

        // Word-level books report every word; the sentence has not changed.
        if let seen = lastSeen, seen == position, !seek { return nil }

        guard let last = lastReading else {
            return take(.start, at: position, time: time)
        }

        let jumped = seek || lastSeen.map { isDiscontinuous(from: $0, to: position) } ?? true
        if jumped {
            awaitingChapter = nil
            return take(.seek, at: position, time: time)
        }

        if awaitingChapter == nil, position.chapterOrdinal != last.position.chapterOrdinal {
            awaitingChapter = position.chapterOrdinal
        }
        if let waiting = awaitingChapter {
            if position.chapterOrdinal != waiting {
                // A very short chapter ended before its first reading; wait for this one.
                awaitingChapter = position.chapterOrdinal
            }
            if position.sentenceIndex + 1 >= configuration.sentencesIntoNewChapter {
                awaitingChapter = nil
                return take(.chapterStart, at: position, time: time)
            }
            return nil
        }

        let sentences = position.globalIndex - last.position.globalIndex
        let seconds = time - last.time
        if sentences >= configuration.sentencesBetweenReadings && seconds >= configuration.secondsBetweenReadings {
            return take(.cadence, at: position, time: time)
        }
        return nil
    }

    /// Forget everything, for example after the book is closed or playback has
    /// been paused long enough that the engine stopped. The next position starts
    /// a new stretch with a `.start` reading.
    public mutating func reset() {
        lastSeen = nil
        lastReading = nil
        awaitingChapter = nil
    }

    private mutating func take(_ trigger: ReadingTrigger, at position: SentencePosition, time: Double) -> ReadingTrigger {
        lastReading = (position, time)
        return trigger
    }

    private func isDiscontinuous(from previous: SentencePosition, to next: SentencePosition) -> Bool {
        let step = next.globalIndex - previous.globalIndex
        return step <= 0 || step > configuration.maxContinuousStep
    }
}
